#ifndef MSHF_PROTOCOL_H
#define MSHF_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <float.h>

#define MSHF_PROTOCOL_PORT 44333
#define MSHF_PROTOCOL_HEADER_SIZE 32
#define MSHF_PROTOCOL_MAX_PACKET_SIZE 1024
#define MSHF_PROTOCOL_FEATURE_PREFIX_SIZE 28
#define MSHF_PROTOCOL_MAX_FEATURE_VALUES 64
#define MSHF_PROTOCOL_SUBSCRIBE_PAYLOAD_SIZE 8

#if defined(__cplusplus)
static_assert(MSHF_PROTOCOL_HEADER_SIZE ==
                  4 + sizeof(uint16_t) + sizeof(uint16_t) +
                      3 * sizeof(uint64_t),
              "MSH2 header size must match its encoded fields");
static_assert(MSHF_PROTOCOL_FEATURE_PREFIX_SIZE +
                      2 * MSHF_PROTOCOL_MAX_FEATURE_VALUES * sizeof(float) <=
                  MSHF_PROTOCOL_MAX_PACKET_SIZE - MSHF_PROTOCOL_HEADER_SIZE,
              "Combined feature payload must fit in one MSH2 packet");
static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 &&
                  FLT_MAX_EXP == 128,
              "MSH2 requires four-byte IEEE-style float values");
#else
_Static_assert(MSHF_PROTOCOL_HEADER_SIZE ==
                   4 + sizeof(uint16_t) + sizeof(uint16_t) +
                       3 * sizeof(uint64_t),
               "MSH2 header size must match its encoded fields");
_Static_assert(MSHF_PROTOCOL_FEATURE_PREFIX_SIZE +
                       2 * MSHF_PROTOCOL_MAX_FEATURE_VALUES * sizeof(float) <=
                   MSHF_PROTOCOL_MAX_PACKET_SIZE - MSHF_PROTOCOL_HEADER_SIZE,
               "Combined feature payload must fit in one MSH2 packet");
_Static_assert(sizeof(float) == 4 && FLT_RADIX == 2 && FLT_MANT_DIG == 24 &&
                   FLT_MAX_EXP == 128,
               "MSH2 requires four-byte IEEE-style float values");
#endif

enum MSHFMessageType {
    MSHFMessageTypeSubscribe = 1,
    MSHFMessageTypeUnsubscribe = 2,
    MSHFMessageTypeFeature = 3,
};

enum MSHFFeatureMask {
    MSHFFeatureMaskWaveform = 1u << 0,
    MSHFFeatureMaskSpectrum = 1u << 1,
    MSHFFeatureMaskAll = MSHFFeatureMaskWaveform | MSHFFeatureMaskSpectrum,
};

enum MSHFFeatureStatus {
    MSHFFeatureStatusSilence = 1u << 0,
    MSHFFeatureStatusClipping = 1u << 1,
    MSHFFeatureStatusDiscontinuity = 1u << 2,
    MSHFFeatureStatusNonFiniteInput = 1u << 3,
    MSHFFeatureStatusSystemMix = 1u << 4,
};

/// Returns the exact fixed Feature payload size for a valid feature mask.
/// A zero result means the mask is empty or contains unsupported bits.
static inline uint16_t MSHFFeaturePayloadLength(uint32_t mask) {
    if (mask == 0 || (mask & ~MSHFFeatureMaskAll) != 0) {
        return 0;
    }
    uint16_t valueCount = 0;
    if (mask & MSHFFeatureMaskWaveform) {
        valueCount += MSHF_PROTOCOL_MAX_FEATURE_VALUES;
    }
    if (mask & MSHFFeatureMaskSpectrum) {
        valueCount += MSHF_PROTOCOL_MAX_FEATURE_VALUES;
    }
    return (uint16_t)(MSHF_PROTOCOL_FEATURE_PREFIX_SIZE +
                      valueCount * sizeof(float));
}

/// Decoded host-order header. Never overlay this structure on packet bytes.
/// All integer and floating-point values on the wire are little-endian.
typedef struct {
    uint16_t type;
    uint16_t payloadLength;
    uint64_t clientSessionID;
    uint64_t serverInstanceID;
    uint64_t sequence;
} MSHFPacketHeader;

static inline uint16_t MSHFReadU16(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

static inline uint32_t MSHFReadU32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static inline uint64_t MSHFReadU64(const uint8_t *bytes) {
    return (uint64_t)MSHFReadU32(bytes) |
           ((uint64_t)MSHFReadU32(bytes + 4) << 32);
}

static inline float MSHFReadF32(const uint8_t *bytes) {
    uint32_t bits = MSHFReadU32(bytes);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static inline void MSHFWriteU16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static inline void MSHFWriteU32(uint8_t *bytes, uint32_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}

static inline void MSHFWriteU64(uint8_t *bytes, uint64_t value) {
    MSHFWriteU32(bytes, (uint32_t)value);
    MSHFWriteU32(bytes + 4, (uint32_t)(value >> 32));
}

static inline void MSHFWriteF32(uint8_t *bytes, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    MSHFWriteU32(bytes, bits);
}

static inline bool MSHFDecodeHeader(const uint8_t *bytes, size_t length,
                                    MSHFPacketHeader *header) {
    if (!bytes || !header || length < MSHF_PROTOCOL_HEADER_SIZE ||
        memcmp(bytes, "MSH2", 4) != 0) {
        return false;
    }

    const uint8_t *cursor = bytes + 4;
    header->type = MSHFReadU16(cursor);
    cursor += sizeof(uint16_t);
    header->payloadLength = MSHFReadU16(cursor);
    cursor += sizeof(uint16_t);
    header->clientSessionID = MSHFReadU64(cursor);
    cursor += sizeof(uint64_t);
    header->serverInstanceID = MSHFReadU64(cursor);
    cursor += sizeof(uint64_t);
    header->sequence = MSHFReadU64(cursor);
    cursor += sizeof(uint64_t);

    return cursor == bytes + MSHF_PROTOCOL_HEADER_SIZE &&
           header->type >= MSHFMessageTypeSubscribe &&
           header->type <= MSHFMessageTypeFeature &&
           header->payloadLength <=
               MSHF_PROTOCOL_MAX_PACKET_SIZE - MSHF_PROTOCOL_HEADER_SIZE &&
           length == (size_t)MSHF_PROTOCOL_HEADER_SIZE +
                         header->payloadLength;
}

static inline void MSHFEncodeHeader(uint8_t *bytes, uint16_t type,
                                    uint16_t payloadLength,
                                    uint64_t clientSessionID,
                                    uint64_t serverInstanceID,
                                    uint64_t sequence) {
    memcpy(bytes, "MSH2", 4);
    uint8_t *cursor = bytes + 4;
    MSHFWriteU16(cursor, type);
    cursor += sizeof(uint16_t);
    MSHFWriteU16(cursor, payloadLength);
    cursor += sizeof(uint16_t);
    MSHFWriteU64(cursor, clientSessionID);
    cursor += sizeof(uint64_t);
    MSHFWriteU64(cursor, serverInstanceID);
    cursor += sizeof(uint64_t);
    MSHFWriteU64(cursor, sequence);
}

#endif
