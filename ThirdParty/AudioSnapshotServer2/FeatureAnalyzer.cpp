#include "ServerInternal.h"

#include <cassert>

namespace MSHFServer {

FeatureAnalyzerState gAnalyzer{};

void ResetDSPState(bool preserveQualifiedActivity) {
    bool keepActivity = preserveQualifiedActivity && gAnalyzer.activityGate.active();
    uint64_t lastFreshAudioNs = keepActivity ? gAnalyzer.lastAudioNs : 0;
    gAnalyzer.rollingWrite = 0;
    gAnalyzer.rollingCount = 0;
    gAnalyzer.lastAudioNs = lastFreshAudioNs;
    gAnalyzer.activityAccumulator.Reset();
    if (keepActivity) {
        // A compatible AudioUnit can be torn down and replaced while seeking
        // or handing off tracks. Preserve only the qualified activity latch;
        // PCM, rolling analysis, smoothing, and incomplete qualification
        // evidence still reset at the stream-epoch boundary.
        gAnalyzer.activityGate.BreakContinuity();
    } else {
        gAnalyzer.activityGate.ResetInactive();
    }
    gAnalyzer.dspDiscontinuity = true;
    gAnalyzer.nonFiniteInputPending = false;
    gAnalyzer.lastAnalysisNs = 0;
    gAnalyzer.smoothedRMS = 0;
    gAnalyzer.smoothedPeak = 0;
    memset(gAnalyzer.rollingSamples, 0, sizeof(gAnalyzer.rollingSamples));
    memset(gAnalyzer.smoothedSpectrum, 0, sizeof(gAnalyzer.smoothedSpectrum));
}

void ResetSpectrumSmoothing() {
    memset(gAnalyzer.smoothedSpectrum, 0,
           sizeof(gAnalyzer.smoothedSpectrum));
    gAnalyzer.dspDiscontinuity = true;
}

float AppendRollingSample(float sample) {
    if (!std::isfinite(sample)) {
        sample = 0;
        gAnalyzer.dspDiscontinuity = true;
        gAnalyzer.nonFiniteInputPending = true;
    }
    gAnalyzer.rollingSamples[gAnalyzer.rollingWrite] = sample;
    gAnalyzer.rollingWrite = (gAnalyzer.rollingWrite + 1) % kAnalysisFrames;
    gAnalyzer.rollingCount = std::min(gAnalyzer.rollingCount + 1, kAnalysisFrames);
    return sample;
}

namespace {

void BuildBandWeights(float sampleRate) {
    memset(gAnalyzer.bandWeights, 0, sizeof(gAnalyzer.bandWeights));
    memset(gAnalyzer.bandWeightOffsets, 0, sizeof(gAnalyzer.bandWeightOffsets));
    memset(gAnalyzer.bandWeightSums, 0, sizeof(gAnalyzer.bandWeightSums));
    float upper = std::min(16000.0f, sampleRate * 0.5f);
    float ratio = powf(upper / 50.0f, 1.0f / kFeatureCount);
    float binWidth = sampleRate / kAnalysisFrames;
    uint16_t weightCount = 0;

    float lower = 50.0f;
    for (uint32_t band = 0; band < kFeatureCount; ++band) {
        gAnalyzer.bandWeightOffsets[band] = weightCount;
        float upperBand = band + 1 == kFeatureCount ? upper : lower * ratio;
        for (uint32_t bin = 0; bin < kFFTBinCount; ++bin) {
            float center = bin * binWidth;
            float binLower = std::max(0.0f, center - binWidth * 0.5f);
            float binUpper = std::min(sampleRate * 0.5f,
                                      center + binWidth * 0.5f);
            float overlap = std::max(
                0.0f, std::min(upperBand, binUpper) -
                          std::max(lower, binLower));
            if (overlap > 0) {
                float weight = overlap / std::max(binWidth, 1.0f);
                assert(weightCount < kMaximumBandWeights);
                gAnalyzer.bandWeights[weightCount++] = {
                    static_cast<uint16_t>(bin), weight};
                gAnalyzer.bandWeightSums[band] += weight;
            }
        }
        lower = upperBand;
    }
    gAnalyzer.bandWeightOffsets[kFeatureCount] = weightCount;
    gAnalyzer.bandSampleRate = sampleRate;
}

} // namespace

bool ProduceFeatureFrame(uint64_t now, FeatureFrame *frame) {
    CaptureSource *source = ActiveSourceOnControlQueue();
    if (!source || !frame) {
        return false;
    }

    bool stale =
        gAnalyzer.lastAudioNs == 0 ||
        now - gAnalyzer.lastAudioNs > MSHFAudioActivity::kCaptureStaleNanoseconds;
    if (gAnalyzer.rollingCount < kAnalysisFrames && !stale) {
        return false;
    }

    if (stale) {
        memset(gAnalyzer.rawWindow, 0, sizeof(gAnalyzer.rawWindow));
    } else {
        uint32_t firstCount = kAnalysisFrames - gAnalyzer.rollingWrite;
        memcpy(gAnalyzer.rawWindow, gAnalyzer.rollingSamples + gAnalyzer.rollingWrite,
               firstCount * sizeof(float));
        memcpy(gAnalyzer.rawWindow + firstCount, gAnalyzer.rollingSamples,
               gAnalyzer.rollingWrite * sizeof(float));
    }

    double deltaSeconds = gAnalyzer.lastAnalysisNs
                              ? (double)(now - gAnalyzer.lastAnalysisNs) / NSEC_PER_SEC
                              : 1.0 / std::max<uint16_t>(gServer.productionRate, 1);
    gAnalyzer.lastAnalysisNs = now;

    bool active = gAnalyzer.activityGate.active();
    float rms = 0;
    float peak = 0;
    if (!active) {
        memset(frame->waveform, 0, sizeof(frame->waveform));
        memset(frame->spectrum, 0, sizeof(frame->spectrum));
        memset(gAnalyzer.smoothedSpectrum, 0,
               sizeof(gAnalyzer.smoothedSpectrum));
        gAnalyzer.smoothedRMS = 0;
        gAnalyzer.smoothedPeak = 0;
    } else {
        const MSHFFeatureDSP::SmoothingCoefficients coefficients =
            MSHFFeatureDSP::MakeSmoothingCoefficients(deltaSeconds);
        vDSP_rmsqv(gAnalyzer.rawWindow, 1, &rms, kAnalysisFrames);
        vDSP_maxmgv(gAnalyzer.rawWindow, 1, &peak, kAnalysisFrames);

    if (gServer.requestedFeatureMask & MSHFFeatureMaskWaveform) {
        MSHFFeatureDSP::SelectCompatibilityWaveform(
            gAnalyzer.rawWindow, kAnalysisFrames, frame->waveform, kFeatureCount);
    } else {
        memset(frame->waveform, 0, sizeof(frame->waveform));
    }

    if (gServer.requestedFeatureMask & MSHFFeatureMaskSpectrum) {
        float mean = 0;
        vDSP_meanv(gAnalyzer.rawWindow, 1, &mean, kAnalysisFrames);
        float negativeMean = -mean;
        vDSP_vsadd(gAnalyzer.rawWindow, 1, &negativeMean, gAnalyzer.fftInput, 1,
                   kAnalysisFrames);
        vDSP_vmul(gAnalyzer.fftInput, 1, gAnalyzer.hannWindow, 1, gAnalyzer.fftInput, 1,
                  kAnalysisFrames);
        MSHFFeatureDSP::ComputeNormalizedPower(
            gAnalyzer.fftInput, kAnalysisFrames, kFFTLog2,
            gAnalyzer.fftSetup, gAnalyzer.windowPowerGain,
            gAnalyzer.fftSplitReal, gAnalyzer.fftSplitImag,
            gAnalyzer.fftPower);

        if (gAnalyzer.bandSampleRate != (float)source->format.mSampleRate) {
            BuildBandWeights((float)source->format.mSampleRate);
        }
        for (uint32_t band = 0; band < kFeatureCount; ++band) {
            float weightedPower = 0;
            for (uint16_t index = gAnalyzer.bandWeightOffsets[band];
                 index < gAnalyzer.bandWeightOffsets[band + 1]; ++index) {
                const BandWeight &entry = gAnalyzer.bandWeights[index];
                weightedPower += gAnalyzer.fftPower[entry.bin] * entry.weight;
            }
            float power = weightedPower /
                          std::max(gAnalyzer.bandWeightSums[band], 0.000001f);
            gAnalyzer.bandDecibels[band] =
                10.0f * log10f(std::max(power, 1.0e-8f));
        }
        MSHFFeatureDSP::ShapeSpectrum(gAnalyzer.bandDecibels, kFeatureCount, rms,
                                      gAnalyzer.spectrumTargets);
        for (uint32_t band = 0; band < kFeatureCount; ++band) {
            gAnalyzer.smoothedSpectrum[band] =
                MSHFFeatureDSP::Smooth(gAnalyzer.smoothedSpectrum[band],
                                       gAnalyzer.spectrumTargets[band],
                                       coefficients);
            frame->spectrum[band] = gAnalyzer.smoothedSpectrum[band];
        }
    } else {
        memset(frame->spectrum, 0, sizeof(frame->spectrum));
    }

        gAnalyzer.smoothedRMS = MSHFFeatureDSP::Smooth(
            gAnalyzer.smoothedRMS, rms, coefficients);
        gAnalyzer.smoothedPeak = MSHFFeatureDSP::Smooth(
            gAnalyzer.smoothedPeak, peak, coefficients);
    }

    frame->streamEpoch = source->streamEpoch;
    frame->sampleRate = (float)source->format.mSampleRate;
    frame->rms = active ? gAnalyzer.smoothedRMS : 0.0f;
    frame->peak = active ? gAnalyzer.smoothedPeak : 0.0f;
    frame->status |= MSHFFeatureStatusSystemMix;
    if (gAnalyzer.nonFiniteInputPending) {
        frame->status |= MSHFFeatureStatusNonFiniteInput;
        gAnalyzer.nonFiniteInputPending = false;
    }
    if (peak >= 0.999f) {
        frame->status |= MSHFFeatureStatusClipping;
    }
    if (gAnalyzer.dspDiscontinuity) {
        frame->status |= MSHFFeatureStatusDiscontinuity;
        gAnalyzer.dspDiscontinuity = false;
    }
    if (!active) {
        frame->status |= MSHFFeatureStatusSilence;
    }
    return true;
}

bool ConfigureDSP() {
    gAnalyzer.fftSetup = vDSP_create_fftsetup(kFFTLog2, kFFTRadix2);
    if (!gAnalyzer.fftSetup) {
        return false;
    }
    vDSP_hann_window(gAnalyzer.hannWindow, kAnalysisFrames, vDSP_HANN_DENORM);
    float power = 0;
    vDSP_measqv(gAnalyzer.hannWindow, 1, &power, kAnalysisFrames);
    gAnalyzer.windowPowerGain = std::max(power, 0.000001f);
    return true;
}

} // namespace MSHFServer
