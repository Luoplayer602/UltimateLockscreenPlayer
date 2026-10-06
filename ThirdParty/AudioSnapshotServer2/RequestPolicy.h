#ifndef MSHF_REQUEST_POLICY_H
#define MSHF_REQUEST_POLICY_H

#include "MSHFProtocol.h"

namespace MSHFRequestPolicy {

enum class Action : uint8_t {
    Reject = 0,
    Subscribe,
    Unsubscribe,
};

inline Action Classify(const MSHFPacketHeader &header,
                       uint64_t serverInstanceID) {
    if (header.clientSessionID == 0 || header.sequence == 0) {
        return Action::Reject;
    }
    if (header.type == MSHFMessageTypeSubscribe) {
        if (header.payloadLength != MSHF_PROTOCOL_SUBSCRIBE_PAYLOAD_SIZE ||
            (header.serverInstanceID != 0 &&
             header.serverInstanceID != serverInstanceID)) {
            return Action::Reject;
        }
        return Action::Subscribe;
    }
    if (header.type == MSHFMessageTypeUnsubscribe &&
        header.payloadLength == 0 && serverInstanceID != 0 &&
        header.serverInstanceID == serverInstanceID) {
        return Action::Unsubscribe;
    }
    return Action::Reject;
}

} // namespace MSHFRequestPolicy

#endif
