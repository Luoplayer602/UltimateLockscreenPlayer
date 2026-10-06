#ifndef MSHF_ACTIVE_SOURCE_TOKEN_H
#define MSHF_ACTIVE_SOURCE_TOKEN_H

#include <cstdint>

namespace MSHFActiveSourceToken {

constexpr uint64_t kValidBit = UINT64_C(1);
constexpr uint64_t kSlotShift = 1;
constexpr uint64_t kGenerationShift = 8;
constexpr uint64_t kSlotMask = UINT64_C(0x7f);
constexpr uint64_t kGenerationMask = (UINT64_C(1) << 56) - 1;

inline uint64_t Encode(uint32_t slotIndex, uint64_t generation) {
    generation &= kGenerationMask;
    if (generation == 0 || slotIndex > kSlotMask) {
        return 0;
    }
    return (generation << kGenerationShift) |
           ((uint64_t)slotIndex << kSlotShift) | kValidBit;
}

inline bool Decode(uint64_t token, uint32_t slotCount, uint32_t *slotIndex,
                   uint64_t *generation) {
    if ((token & kValidBit) == 0) {
        return false;
    }
    uint32_t decodedSlot =
        (uint32_t)((token >> kSlotShift) & kSlotMask);
    uint64_t decodedGeneration = token >> kGenerationShift;
    if (decodedSlot >= slotCount || decodedGeneration == 0) {
        return false;
    }
    if (slotIndex) {
        *slotIndex = decodedSlot;
    }
    if (generation) {
        *generation = decodedGeneration;
    }
    return true;
}

} // namespace MSHFActiveSourceToken

#endif
