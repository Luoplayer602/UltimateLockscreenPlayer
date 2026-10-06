#ifndef MSHF_LIFECYCLE_POLICY_H
#define MSHF_LIFECYCLE_POLICY_H

#include <algorithm>
#include <cstdint>

namespace MSHFLifecyclePolicy {

constexpr uint32_t kFastYieldCount = 32;
constexpr uint64_t kInitialBackoffNs = UINT64_C(50) * 1000;
constexpr uint64_t kMaximumBackoffNs = UINT64_C(5) * 1000 * 1000;
constexpr uint64_t kDrainTimeoutNs = UINT64_C(250) * 1000 * 1000;
constexpr uint64_t kQuarantinePollNs = UINT64_C(1) * 1000 * 1000 * 1000;

struct Backoff {
    uint64_t delayNs = kInitialBackoffNs;
};

inline uint64_t NextDelay(Backoff *backoff) {
    if (!backoff) {
        return kMaximumBackoffNs;
    }
    const uint64_t delay = backoff->delayNs;
    backoff->delayNs =
        std::min(delay * 2, kMaximumBackoffNs);
    return delay;
}

inline bool ShouldQuarantine(uint64_t elapsedNs) {
    return elapsedNs >= kDrainTimeoutNs;
}

} // namespace MSHFLifecyclePolicy

#endif
