#ifndef MSHF_FEATURE_DSP_H
#define MSHF_FEATURE_DSP_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>

#include <Accelerate/Accelerate.h>

namespace MSHFFeatureDSP {

constexpr size_t kCompatibilityWaveformFrames = 1024;
constexpr float kSpectrumShapeRangeDB = 36.0f;
constexpr float kSpectrumLevelFloorDB = -60.0f;
constexpr float kSpectrumLevelRangeDB = 45.0f;

inline bool SpectrumMaskChanged(uint32_t previousMask, uint32_t nextMask,
                                uint32_t spectrumBit) {
    return ((previousMask ^ nextMask) & spectrumBit) != 0;
}

struct SmoothingCoefficients {
    float attack;
    float release;
};

inline SmoothingCoefficients MakeSmoothingCoefficients(
    double deltaSeconds) {
    const float delta = static_cast<float>(deltaSeconds);
    return {
        1.0f - std::exp(-delta / 0.035f),
        1.0f - std::exp(-delta / 0.180f),
    };
}

inline float Smooth(float current, float target,
                    const SmoothingCoefficients &coefficients) {
    const float coefficient =
        target > current ? coefficients.attack : coefficients.release;
    return current + coefficient * (target - current);
}

inline void ComputeNormalizedPower(const float *windowedInput,
                                   vDSP_Length frameCount,
                                   vDSP_Length fftLog2, FFTSetup setup,
                                   float windowPowerGain, float *splitReal,
                                   float *splitImag, float *power) {
    const vDSP_Length complexCount = frameCount / 2;
    DSPSplitComplex split{splitReal, splitImag};
    vDSP_ctoz(reinterpret_cast<const DSPComplex *>(windowedInput), 2,
              &split, 1, complexCount);
    vDSP_fft_zrip(setup, &split, 1, fftLog2, FFT_FORWARD);

    power[0] = split.realp[0] * split.realp[0];
    power[complexCount] = split.imagp[0] * split.imagp[0];
    DSPSplitComplex interior{split.realp + 1, split.imagp + 1};
    vDSP_zvmags(&interior, 1, power + 1, 1, complexCount - 1);

    const float frames = static_cast<float>(frameCount);
    float normalization =
        0.5f / (frames * frames * windowPowerGain);
    vDSP_vsmul(power, 1, &normalization, power, 1, complexCount + 1);
    power[0] *= 0.5f;
    power[complexCount] *= 0.5f;
}

inline float Clamp(float value, float lower, float upper) {
    return std::min(std::max(value, lower), upper);
}

inline void SelectCompatibilityWaveform(const float *samples,
                                        size_t sampleCount, float *output,
                                        size_t outputCount) {
    if (!output || outputCount == 0) {
        return;
    }
    if (!samples || sampleCount < kCompatibilityWaveformFrames) {
        std::fill(output, output + outputCount, 0.0f);
        return;
    }

    const size_t windowStart = sampleCount - kCompatibilityWaveformFrames;
    for (size_t index = 0; index < outputCount; ++index) {
        const size_t sourceIndex =
            windowStart + index * kCompatibilityWaveformFrames / outputCount;
        const float sample = samples[sourceIndex];
        output[index] =
            std::isfinite(sample) ? Clamp(sample, -1.0f, 1.0f) : 0.0f;
    }
}

inline void ShapeSpectrum(const float *bandDecibels, size_t bandCount,
                          float rms, float *output) {
    if (!output || bandCount == 0) {
        return;
    }
    if (!bandDecibels) {
        std::fill(output, output + bandCount, 0.0f);
        return;
    }

    float referenceDB = -80.0f;
    for (size_t index = 0; index < bandCount; ++index) {
        if (std::isfinite(bandDecibels[index])) {
            referenceDB = std::max(referenceDB, bandDecibels[index]);
        }
    }

    const float safeRMS = std::isfinite(rms) ? std::max(rms, 1.0e-8f)
                                              : 1.0e-8f;
    const float rmsDB = 20.0f * std::log10(safeRMS);
    const float level =
        Clamp((rmsDB - kSpectrumLevelFloorDB) / kSpectrumLevelRangeDB,
              0.0f, 1.0f);
    const float floorDB = referenceDB - kSpectrumShapeRangeDB;

    for (size_t index = 0; index < bandCount; ++index) {
        const float db = std::isfinite(bandDecibels[index])
                             ? bandDecibels[index]
                             : floorDB;
        const float shape =
            Clamp((db - floorDB) / kSpectrumShapeRangeDB, 0.0f, 1.0f);
        output[index] = shape * level;
    }
}

} // namespace MSHFFeatureDSP

#endif
