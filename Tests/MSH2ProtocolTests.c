#include "../Audio/MSH2Protocol.h"

#include <assert.h>
#include <string.h>

int main(void) {
    uint8_t packet[ULP_MSH2_HEADER_SIZE + ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE] = {0};
    const ULPMSH2Header sent = {
        .type = ULP_MSH2_SUBSCRIBE,
        .payloadLength = ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE,
        .clientSessionID = 0x1020304050607080ULL,
        .serverInstanceID = 0,
        .sequence = 7,
    };
    ULPMSH2EncodeHeader(packet, &sent);
    ULPMSH2WriteU32(packet + ULP_MSH2_HEADER_SIZE, ULP_MSH2_WAVEFORM | ULP_MSH2_SPECTRUM);

    ULPMSH2Header received = {0};
    assert(ULPMSH2DecodeHeader(packet, sizeof(packet), &received));
    assert(received.type == sent.type);
    assert(received.payloadLength == sent.payloadLength);
    assert(received.clientSessionID == sent.clientSessionID);
    assert(received.sequence == sent.sequence);
    assert(ULPMSH2ReadU32(packet + ULP_MSH2_HEADER_SIZE) == 3);
    assert(!ULPMSH2DecodeHeader(packet, sizeof(packet) - 1, &received));

    packet[0] = 'X';
    assert(!ULPMSH2DecodeHeader(packet, sizeof(packet), &received));
    packet[0] = 'M';
    packet[4] = 9;
    assert(!ULPMSH2DecodeHeader(packet, sizeof(packet), &received));

    uint8_t feature[ULP_MSH2_HEADER_SIZE + ULP_MSH2_FEATURE_PREFIX_SIZE +
                    ULP_MSH2_FEATURE_VALUES * sizeof(float)] = {0};
    const ULPMSH2Header featureHeader = {
        .type = ULP_MSH2_FEATURE,
        .payloadLength = sizeof(feature) - ULP_MSH2_HEADER_SIZE,
        .clientSessionID = sent.clientSessionID,
        .serverInstanceID = 9,
        .sequence = 8,
    };
    ULPMSH2EncodeHeader(feature, &featureHeader);
    ULPMSH2WriteU32(feature + ULP_MSH2_HEADER_SIZE + 8, ULP_MSH2_SPECTRUM);
    ULPMSH2WriteU32(feature + ULP_MSH2_HEADER_SIZE + 16, 0x471c4000); // 40000 Hz
    ULPMSH2WriteU32(feature + ULP_MSH2_HEADER_SIZE + ULP_MSH2_FEATURE_PREFIX_SIZE,
                     0x3f000000); // first spectrum bin = 0.5
    ULPMSH2FeatureFrame decoded = {0};
    assert(ULPMSH2DecodeHeader(feature, sizeof(feature), &received));
    assert(ULPMSH2DecodeFeature(feature, sizeof(feature), &received, &decoded));
    assert(decoded.featureMask == ULP_MSH2_SPECTRUM);
    assert(decoded.spectrum[0] == 0.5f);
    ULPMSH2WriteU32(feature + ULP_MSH2_HEADER_SIZE + 8, 4);
    assert(!ULPMSH2DecodeFeature(feature, sizeof(feature), &received, &decoded));
    return 0;
}
