#ifndef MSHF_AUDIO_ACTIVITY_GATE_H
#define MSHF_AUDIO_ACTIVITY_GATE_H

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace MSHFAudioActivity {

constexpr uint32_t kEnergyBlockFrames = 256;
constexpr uint64_t kAttackDurationNanoseconds = UINT64_C(100000000);
// Preserve an already-qualified stream across the short render gaps produced
// by seeking and track handoffs. Initial activation remains deliberately
// strict, so isolated taps and haptics cannot open the gate.
constexpr uint64_t kReleaseDurationNanoseconds = UINT64_C(1250000000);
constexpr uint64_t kCaptureStaleNanoseconds = UINT64_C(100000000);
constexpr float kAttackThresholdDecibels = -75.0f;
constexpr float kReleaseThresholdDecibels = -80.0f;

struct Observation {
    uint64_t coveredDurationNanoseconds = 0;
    float rmsDecibels = -160.0f;
};

/// Converts contiguous PCM into fixed-duration energy observations. Partial
/// blocks are deliberately discarded across capture discontinuities.
class EnergyAccumulator {
  public:
    void Reset() {
        frameCount_ = 0;
        sumSquares_ = 0;
    }

    bool Append(float sample, double sampleRate, Observation *observation) {
        if (!observation || !std::isfinite(sample) ||
            !std::isfinite(sampleRate) || sampleRate <= 0) {
            Reset();
            return false;
        }
        double value = sample;
        sumSquares_ += value * value;
        ++frameCount_;
        if (frameCount_ != kEnergyBlockFrames) {
            return false;
        }

        double meanSquare = sumSquares_ / kEnergyBlockFrames;
        double rms = std::sqrt(std::max(meanSquare, 1.0e-16));
        observation->rmsDecibels =
            static_cast<float>(20.0 * std::log10(rms));
        observation->coveredDurationNanoseconds = static_cast<uint64_t>(
            std::llround(kEnergyBlockFrames * 1000000000.0 / sampleRate));
        Reset();
        return true;
    }

    uint32_t pendingFrameCount() const { return frameCount_; }

  private:
    uint32_t frameCount_ = 0;
    double sumSquares_ = 0;
};

/// Classifies meaningful audio without knowing anything about applications or
/// playback sessions. Qualification is based on covered audio duration rather
/// than the cadence of feature-production timer callbacks.
class Gate {
  public:
    void ResetInactive() {
        active_ = false;
        BreakContinuity();
    }

    /// Keeps the latched state but prevents evidence on opposite sides of a
    /// missing interval from being joined into one continuous transition.
    void BreakContinuity() {
        attackDurationNanoseconds_ = 0;
        releaseDurationNanoseconds_ = 0;
    }

    void Observe(const Observation &observation) {
        if (observation.coveredDurationNanoseconds == 0 ||
            !std::isfinite(observation.rmsDecibels)) {
            BreakContinuity();
            return;
        }

        if (!active_) {
            releaseDurationNanoseconds_ = 0;
            if (observation.rmsDecibels > kAttackThresholdDecibels) {
                attackDurationNanoseconds_ = SaturatingAdd(
                    attackDurationNanoseconds_,
                    observation.coveredDurationNanoseconds);
                if (attackDurationNanoseconds_ >=
                    kAttackDurationNanoseconds) {
                    active_ = true;
                    BreakContinuity();
                }
            } else {
                attackDurationNanoseconds_ = 0;
            }
            return;
        }

        attackDurationNanoseconds_ = 0;
        if (observation.rmsDecibels <= kReleaseThresholdDecibels) {
            releaseDurationNanoseconds_ = SaturatingAdd(
                releaseDurationNanoseconds_,
                observation.coveredDurationNanoseconds);
            if (releaseDurationNanoseconds_ >=
                kReleaseDurationNanoseconds) {
                active_ = false;
                BreakContinuity();
            }
        } else {
            releaseDurationNanoseconds_ = 0;
        }
    }

    /// Missing capture breaks partial evidence after 100 ms and releases an
    /// active gate 1.25 seconds after the last fresh captured descriptor.
    void ObserveCaptureAge(uint64_t captureAgeNanoseconds) {
        if (captureAgeNanoseconds >= kCaptureStaleNanoseconds) {
            BreakContinuity();
        }
        if (active_ &&
            captureAgeNanoseconds >= kReleaseDurationNanoseconds) {
            active_ = false;
            BreakContinuity();
        }
    }

    bool active() const { return active_; }
    uint64_t attackDurationNanoseconds() const {
        return attackDurationNanoseconds_;
    }
    uint64_t releaseDurationNanoseconds() const {
        return releaseDurationNanoseconds_;
    }

  private:
    static uint64_t SaturatingAdd(uint64_t left, uint64_t right) {
        if (right > std::numeric_limits<uint64_t>::max() - left) {
            return std::numeric_limits<uint64_t>::max();
        }
        return left + right;
    }

    bool active_ = false;
    uint64_t attackDurationNanoseconds_ = 0;
    uint64_t releaseDurationNanoseconds_ = 0;
};

} // namespace MSHFAudioActivity

#endif
