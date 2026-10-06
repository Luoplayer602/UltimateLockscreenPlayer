#ifndef ULP_MSH2_PROTOCOL_H
#define ULP_MSH2_PROTOCOL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Wire constants from AudioSnapshotServer2's MSHFProtocol.h (MSH2).
enum {
    ULP_MSH2_PORT = 44333,
    ULP_MSH2_HEADER_SIZE = 32,
    ULP_MSH2_MAX_PACKET_SIZE = 1024,
    ULP_MSH2_FEATURE_PREFIX_SIZE = 28,
    ULP_MSH2_FEATURE_VALUES = 64,
    ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE = 8,
};

typedef enum {
    ULP_MSH2_SUBSCRIBE = 1,
    ULP_MSH2_UNSUBSCRIBE = 2,
    ULP_MSH2_FEATURE = 3,
} ULPMSH2MessageType;

typedef enum {
    ULP_MSH2_WAVEFORM = 1u << 0,
    ULP_MSH2_SPECTRUM = 1u << 1,
} ULPMSH2FeatureMask;

typedef struct {
    uint16_t type;
    uint16_t payloadLength;
    uint64_t clientSessionID;
    uint64_t serverInstanceID;
    uint64_t sequence;
} ULPMSH2Header;

typedef struct {
    uint64_t streamEpoch;
    uint32_t featureMask;
    uint32_t status;
    float sampleRate;
    float rms;
    float peak;
    float waveform[ULP_MSH2_FEATURE_VALUES];
    float spectrum[ULP_MSH2_FEATURE_VALUES];
} ULPMSH2FeatureFrame;

bool ULPMSH2DecodeHeader(const uint8_t *bytes, size_t length, ULPMSH2Header *header);
bool ULPMSH2DecodeFeature(const uint8_t *bytes, size_t length,
                          const ULPMSH2Header *header, ULPMSH2FeatureFrame *frame);
void ULPMSH2EncodeSubscribe(uint8_t *bytes, uint64_t sessionID,
                            uint64_t sequence, uint16_t rate);
void ULPMSH2EncodeHeader(uint8_t *bytes, const ULPMSH2Header *header);
uint16_t ULPMSH2ReadU16(const uint8_t *bytes);
uint32_t ULPMSH2ReadU32(const uint8_t *bytes);
uint64_t ULPMSH2ReadU64(const uint8_t *bytes);
float ULPMSH2ReadF32(const uint8_t *bytes);
void ULPMSH2WriteU32(uint8_t *bytes, uint32_t value);

#endif
