#include "MSH2Protocol.h"

#include <math.h>
#include <string.h>

uint16_t ULPMSH2ReadU16(const uint8_t *bytes) {
    return (uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8);
}

uint32_t ULPMSH2ReadU32(const uint8_t *bytes) {
    return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) |
           ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

uint64_t ULPMSH2ReadU64(const uint8_t *bytes) {
    return (uint64_t)ULPMSH2ReadU32(bytes) |
           ((uint64_t)ULPMSH2ReadU32(bytes + 4) << 32);
}

float ULPMSH2ReadF32(const uint8_t *bytes) {
    const uint32_t bits = ULPMSH2ReadU32(bytes);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

void ULPMSH2WriteU32(uint8_t *bytes, uint32_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
    bytes[2] = (uint8_t)(value >> 16);
    bytes[3] = (uint8_t)(value >> 24);
}

static void writeU16(uint8_t *bytes, uint16_t value) {
    bytes[0] = (uint8_t)value;
    bytes[1] = (uint8_t)(value >> 8);
}

static void writeU64(uint8_t *bytes, uint64_t value) {
    ULPMSH2WriteU32(bytes, (uint32_t)value);
    ULPMSH2WriteU32(bytes + 4, (uint32_t)(value >> 32));
}

bool ULPMSH2DecodeHeader(const uint8_t *bytes, size_t length, ULPMSH2Header *header) {
    if (!bytes || !header || length < ULP_MSH2_HEADER_SIZE ||
        length > ULP_MSH2_MAX_PACKET_SIZE || memcmp(bytes, "MSH2", 4) != 0) {
        return false;
    }

    ULPMSH2Header decoded = {
        .type = ULPMSH2ReadU16(bytes + 4),
        .payloadLength = ULPMSH2ReadU16(bytes + 6),
        .clientSessionID = ULPMSH2ReadU64(bytes + 8),
        .serverInstanceID = ULPMSH2ReadU64(bytes + 16),
        .sequence = ULPMSH2ReadU64(bytes + 24),
    };
    if (decoded.type < ULP_MSH2_SUBSCRIBE || decoded.type > ULP_MSH2_FEATURE ||
        length != (size_t)ULP_MSH2_HEADER_SIZE + decoded.payloadLength) {
        return false;
    }
    *header = decoded;
    return true;
}

void ULPMSH2EncodeHeader(uint8_t *bytes, const ULPMSH2Header *header) {
    memcpy(bytes, "MSH2", 4);
    writeU16(bytes + 4, header->type);
    writeU16(bytes + 6, header->payloadLength);
    writeU64(bytes + 8, header->clientSessionID);
    writeU64(bytes + 16, header->serverInstanceID);
    writeU64(bytes + 24, header->sequence);
}

void ULPMSH2EncodeSubscribe(uint8_t *bytes, uint64_t sessionID,
                            uint64_t sequence, uint16_t rate) {
    const ULPMSH2Header header = {
        .type = ULP_MSH2_SUBSCRIBE,
        .payloadLength = ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE,
        .clientSessionID = sessionID,
        .serverInstanceID = 0,
        .sequence = sequence,
    };
    ULPMSH2EncodeHeader(bytes, &header);
    ULPMSH2WriteU32(bytes + ULP_MSH2_HEADER_SIZE,
                     ULP_MSH2_WAVEFORM | ULP_MSH2_SPECTRUM);
    writeU16(bytes + ULP_MSH2_HEADER_SIZE + 4, rate);
    writeU16(bytes + ULP_MSH2_HEADER_SIZE + 6, 0); // no idle grace
}

bool ULPMSH2DecodeFeature(const uint8_t *bytes, size_t length,
                          const ULPMSH2Header *header, ULPMSH2FeatureFrame *frame) {
    if (!bytes || !header || !frame || header->type != ULP_MSH2_FEATURE ||
        length != (size_t)ULP_MSH2_HEADER_SIZE + header->payloadLength ||
        header->payloadLength < ULP_MSH2_FEATURE_PREFIX_SIZE) {
        return false;
    }
    const uint8_t *payload = bytes + ULP_MSH2_HEADER_SIZE;
    const uint32_t mask = ULPMSH2ReadU32(payload + 8);
    if (mask == 0 || (mask & ~(ULP_MSH2_WAVEFORM | ULP_MSH2_SPECTRUM)) != 0) {
        return false;
    }
    const size_t values = ((mask & ULP_MSH2_WAVEFORM) ? ULP_MSH2_FEATURE_VALUES : 0) +
                          ((mask & ULP_MSH2_SPECTRUM) ? ULP_MSH2_FEATURE_VALUES : 0);
    if (header->payloadLength != ULP_MSH2_FEATURE_PREFIX_SIZE + values * sizeof(float)) {
        return false;
    }
    ULPMSH2FeatureFrame decoded = {0};
    decoded.streamEpoch = ULPMSH2ReadU64(payload);
    decoded.featureMask = mask;
    decoded.status = ULPMSH2ReadU32(payload + 12);
    decoded.sampleRate = ULPMSH2ReadF32(payload + 16);
    decoded.rms = ULPMSH2ReadF32(payload + 20);
    decoded.peak = ULPMSH2ReadF32(payload + 24);
    if (!isfinite(decoded.sampleRate) || decoded.sampleRate <= 0 ||
        !isfinite(decoded.rms) || !isfinite(decoded.peak)) {
        return false;
    }
    size_t offset = ULP_MSH2_FEATURE_PREFIX_SIZE;
    if (mask & ULP_MSH2_WAVEFORM) {
        for (size_t i = 0; i < ULP_MSH2_FEATURE_VALUES; ++i, offset += 4) {
            decoded.waveform[i] = ULPMSH2ReadF32(payload + offset);
            if (!isfinite(decoded.waveform[i])) return false;
        }
    }
    if (mask & ULP_MSH2_SPECTRUM) {
        for (size_t i = 0; i < ULP_MSH2_FEATURE_VALUES; ++i, offset += 4) {
            decoded.spectrum[i] = ULPMSH2ReadF32(payload + offset);
            if (!isfinite(decoded.spectrum[i])) return false;
        }
    }
    *frame = decoded;
    return true;
}
