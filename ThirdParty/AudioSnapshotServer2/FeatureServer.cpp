#include "ServerInternal.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <unistd.h>

namespace MSHFServer {

FeatureServerState gServer{};

uint32_t ClientCountOnControlQueue() {
    uint32_t count = 0;
    for (const Client &client : gServer.clients) {
        count += client.used ? 1u : 0u;
    }
    return count;
}

namespace {

void ExpireClients(uint64_t now);

bool SameEndpoint(const sockaddr_in &left, const sockaddr_in &right) {
    return left.sin_family == right.sin_family &&
           left.sin_port == right.sin_port &&
           left.sin_addr.s_addr == right.sin_addr.s_addr;
}

Client *FindClient(uint64_t sessionID, const sockaddr_in &address) {
    for (Client &client : gServer.clients) {
        if (client.used && client.sessionID == sessionID &&
            SameEndpoint(client.address, address)) {
            return &client;
        }
    }
    return nullptr;
}

Client *FindClientBySessionID(uint64_t sessionID) {
    for (Client &client : gServer.clients) {
        if (client.used && client.sessionID == sessionID) {
            return &client;
        }
    }
    return nullptr;
}

void RecomputeClientConfiguration() {
    uint32_t mask = 0;
    uint16_t rate = 5;
    for (const Client &client : gServer.clients) {
        if (client.used) {
            mask |= client.featureMask;
            rate = std::max(rate, client.featureRate);
        }
    }
    const uint32_t previousMask = gServer.requestedFeatureMask;
    gServer.requestedFeatureMask = mask;
    if (MSHFFeatureDSP::SpectrumMaskChanged(
            previousMask, mask, MSHFFeatureMaskSpectrum)) {
        ResetSpectrumSmoothing();
    }
    uint16_t previousDrainRate = gServer.drainRate;
    uint16_t previousProductionRate = gServer.productionRate;
    gServer.productionRate = std::min<uint16_t>(std::max<uint16_t>(rate, 5), 60);
    gServer.drainRate = std::min<uint16_t>(
        std::max<uint16_t>(rate, kMinimumAnalysisRate), 60);
    if (gServer.drainRate != previousDrainRate ||
        gServer.productionRate != previousProductionRate) {
        MSHFResetFeaturePacer(&gServer.productionPacer);
        for (Client &client : gServer.clients) {
            if (client.used) {
                MSHFResetFeaturePacer(&client.featurePacer);
            }
        }
    }

    if (ClientCountOnControlQueue() == 0) {
        MSHFResetSilencePacer(&gServer.silencePacer);
        dispatch_source_set_timer(gServer.analysisTimer, DISPATCH_TIME_FOREVER,
                                  DISPATCH_TIME_FOREVER, 0);
    } else {
        uint64_t interval = NSEC_PER_SEC / gServer.drainRate;
        dispatch_source_set_timer(gServer.analysisTimer,
                                  dispatch_time(DISPATCH_TIME_NOW, interval),
                                  interval, std::min<uint64_t>(interval / 10,
                                                               2 * NSEC_PER_MSEC));
    }
}

void EncodeFeaturePayload(uint8_t *payload, uint32_t mask,
                          const FeatureFrame &frame) {
    uint8_t *cursor = payload;
    MSHFWriteU64(cursor, frame.streamEpoch);
    cursor += sizeof(uint64_t);
    MSHFWriteU32(cursor, mask);
    cursor += sizeof(uint32_t);
    MSHFWriteU32(cursor, frame.status);
    cursor += sizeof(uint32_t);
    MSHFWriteF32(cursor, frame.sampleRate);
    cursor += sizeof(float);
    MSHFWriteF32(cursor, frame.rms);
    cursor += sizeof(float);
    MSHFWriteF32(cursor, frame.peak);
    cursor += sizeof(float);

    if (mask & MSHFFeatureMaskWaveform) {
        for (float value : frame.waveform) {
            MSHFWriteF32(cursor, value);
            cursor += sizeof(float);
        }
    }
    if (mask & MSHFFeatureMaskSpectrum) {
        for (float value : frame.spectrum) {
            MSHFWriteF32(cursor, value);
            cursor += sizeof(float);
        }
    }
}

bool SendPacket(const sockaddr_in &address, uint64_t sessionID, uint16_t type,
                const uint8_t *payload, uint16_t payloadLength) {
    uint8_t packet[MSHF_PROTOCOL_MAX_PACKET_SIZE];
    MSHFEncodeHeader(packet, type, payloadLength, sessionID,
                     gRuntime.serverInstanceID, ++gServer.datagramSequence);
    if (payloadLength) {
        memcpy(packet + MSHF_PROTOCOL_HEADER_SIZE, payload, payloadLength);
    }
    ssize_t sent = sendto(gServer.socketDescriptor, packet,
                          MSHF_PROTOCOL_HEADER_SIZE + payloadLength, 0,
                          reinterpret_cast<const sockaddr *>(&address),
                          sizeof(address));
    if (sent != (ssize_t)(MSHF_PROTOCOL_HEADER_SIZE + payloadLength)) {
        return false;
    }
    return true;
}

void StartCaptureForSubscribers() {
    Candidate *candidate = NewestInitializedCandidate();
    SourceDescription description{};
    if (!DescribeBestSource(candidate, &description)) {
        BeginTransition(nullptr);
        return;
    }

    CaptureSource *active = ActiveSourceOnControlQueue();
    if (!gCapture.transitionScheduled && SourceMatchesDescription(active, description)) {
        gCapture.captureFaults.fetch_or(CaptureFaultWarmResume,
                                std::memory_order_release);
        gCapture.captureEnabled.store(true, std::memory_order_release);
        return;
    }
    BeginTransition(&description);
}

void ScheduleIdleExpiry(uint16_t graceSeconds) {
    uint64_t generation = ++gServer.idleGeneration;
    gCapture.captureEnabled.store(false, std::memory_order_release);
    gAnalyzer.activityAccumulator.Reset();
    gAnalyzer.activityGate.ResetInactive();
    gAnalyzer.lastAudioNs = 0;
    if (graceSeconds == 0) {
        BeginTransition(nullptr);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)graceSeconds * NSEC_PER_SEC),
                   gRuntime.controlQueue, ^{
                     if (ClientCountOnControlQueue() == 0 &&
                         gServer.idleGeneration == generation) {
                         BeginTransition(nullptr);
                     }
                   });
}

void RemoveClient(Client *client) {
    if (!client || !client->used) {
        return;
    }
    uint16_t grace = 0;
    for (const Client &activeClient : gServer.clients) {
        if (activeClient.used) {
            grace = std::max(grace, activeClient.graceSeconds);
        }
    }
    client->used = false;
    if (ClientCountOnControlQueue() == 0) {
        ScheduleIdleExpiry(grace);
    }
    RecomputeClientConfiguration();
}

void HandleSubscribe(const sockaddr_in &address,
                     const MSHFPacketHeader &header, const uint8_t *payload) {
    const uint8_t *cursor = payload;
    uint32_t mask = MSHFReadU32(cursor);
    cursor += sizeof(uint32_t);
    uint16_t rate = MSHFReadU16(cursor);
    cursor += sizeof(uint16_t);
    uint16_t grace = MSHFReadU16(cursor);
    if (mask == 0 || (mask & ~MSHFFeatureMaskAll) != 0 || rate < 5 ||
        rate > 60 || (grace != 0 && grace != 10)) {
        return;
    }

    const uint64_t now = MonotonicNanoseconds();
    // Reclaim expired fixed-capacity slots before reporting saturation.
    ExpireClients(now);
    Client *client = FindClientBySessionID(header.clientSessionID);
    if (client && header.sequence <= client->lastRequestSequence) {
        return;
    }
    bool firstSubscriber = ClientCountOnControlQueue() == 0;
    bool newClient = false;
    if (!client) {
        for (Client &slot : gServer.clients) {
            if (!slot.used) {
                client = &slot;
                memset(client, 0, sizeof(*client));
                client->used = true;
                client->address = address;
                client->sessionID = header.clientSessionID;
                newClient = true;
                break;
            }
        }
    }
    if (!client) {
        ++gServer.clientSaturationCount;
        return;
    }

    client->address = address;
    bool resetPacing = newClient || client->featureMask != mask ||
                       client->featureRate != rate;
    client->featureMask = mask;
    client->featureRate = rate;
    client->graceSeconds = grace;
    client->lastSeenNs = now;
    client->lastRequestSequence = header.sequence;
    if (resetPacing) {
        MSHFResetFeaturePacer(&client->featurePacer);
    }
    ++gServer.idleGeneration;
    if (firstSubscriber) {
        MSHFResetFeaturePacer(&gServer.productionPacer);
        MSHFResetSilencePacer(&gServer.silencePacer);
    }
    RecomputeClientConfiguration();
    if (firstSubscriber) {
        StartCaptureForSubscribers();
    }
}

void HandleDatagram(const uint8_t *packet, size_t length,
                    const sockaddr_in &address) {
    if (address.sin_family != AF_INET ||
        address.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) {
        return;
    }

    MSHFPacketHeader header{};
    if (!MSHFDecodeHeader(packet, length, &header)) {
        return;
    }
    const MSHFRequestPolicy::Action action =
        MSHFRequestPolicy::Classify(header, gRuntime.serverInstanceID);
    if (action == MSHFRequestPolicy::Action::Reject) {
        return;
    }
    const uint8_t *payload = packet + MSHF_PROTOCOL_HEADER_SIZE;
    if (action == MSHFRequestPolicy::Action::Subscribe) {
        HandleSubscribe(address, header, payload);
        return;
    }

    Client *client = FindClient(header.clientSessionID, address);
    if (!client ||
        header.sequence <= client->lastRequestSequence) {
        return;
    }
    RemoveClient(client);
}

void ReadSocket() {
    uint32_t count = 0;
    while (count < kMaximumDatagramsPerRead) {
        uint8_t packet[MSHF_PROTOCOL_MAX_PACKET_SIZE];
        sockaddr_in address{};
        socklen_t addressLength = sizeof(address);
        ssize_t received = recvfrom(gServer.socketDescriptor, packet, sizeof(packet), 0,
                                    reinterpret_cast<sockaddr *>(&address),
                                    &addressLength);
        if (received < 0) {
            if (errno == EINTR) {
                continue;
            }
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            gServer.lastSocketError = errno;
            ++gServer.socketReadErrorCount;
            return;
        }
        ++count;
        if (received == 0 || addressLength != sizeof(address)) {
            continue;
        }
        HandleDatagram(packet, (size_t)received, address);
    }
}

void ExpireClients(uint64_t now) {
    uint16_t maximumGrace = 0;
    bool removed = false;
    for (Client &client : gServer.clients) {
        if (client.used && now - client.lastSeenNs > kClientTimeoutNs) {
            maximumGrace = std::max(maximumGrace, client.graceSeconds);
            client.used = false;
            removed = true;
        }
    }
    if (removed) {
        if (ClientCountOnControlQueue() == 0) {
            ScheduleIdleExpiry(maximumGrace);
        }
        RecomputeClientConfiguration();
    }
}

void SendFeatureFrames(const FeatureFrame &frame, bool bypassRatePacing) {
    uint8_t waveformPayload[MSHF_PROTOCOL_MAX_PACKET_SIZE -
                            MSHF_PROTOCOL_HEADER_SIZE];
    uint8_t spectrumPayload[MSHF_PROTOCOL_MAX_PACKET_SIZE -
                            MSHF_PROTOCOL_HEADER_SIZE];
    uint8_t combinedPayload[MSHF_PROTOCOL_MAX_PACKET_SIZE -
                            MSHF_PROTOCOL_HEADER_SIZE];
    if (gServer.requestedFeatureMask & MSHFFeatureMaskWaveform) {
        EncodeFeaturePayload(waveformPayload, MSHFFeatureMaskWaveform, frame);
    }
    if (gServer.requestedFeatureMask & MSHFFeatureMaskSpectrum) {
        EncodeFeaturePayload(spectrumPayload, MSHFFeatureMaskSpectrum, frame);
    }
    if (gServer.requestedFeatureMask == MSHFFeatureMaskAll) {
        EncodeFeaturePayload(combinedPayload, MSHFFeatureMaskAll, frame);
    }

    for (Client &client : gServer.clients) {
        if (!client.used) {
            continue;
        }
        if (!bypassRatePacing &&
            !MSHFFeaturePacerShouldDeliver(&client.featurePacer,
                                           client.featureRate,
                                           gServer.productionRate)) {
            continue;
        }
        const uint8_t *payload = combinedPayload;
        if (client.featureMask == MSHFFeatureMaskWaveform) {
            payload = waveformPayload;
        } else if (client.featureMask == MSHFFeatureMaskSpectrum) {
            payload = spectrumPayload;
        }
        SendPacket(client.address, client.sessionID, MSHFMessageTypeFeature,
                   payload, MSHFFeaturePayloadLength(client.featureMask));
    }
}

void AnalysisTick() {
    uint64_t now = MonotonicNanoseconds();
    ExpireClients(now);
    if (ClientCountOnControlQueue() == 0) {
        return;
    }
    if (gCapture.refreshRequested.exchange(false, std::memory_order_acq_rel)) {
        RefreshActiveSource();
    }
    DrainAudioRing(now);
    if (MSHFFeaturePacerShouldDeliver(&gServer.productionPacer, gServer.productionRate,
                                      gServer.drainRate)) {
        FeatureFrame frame{};
        if (ProduceFeatureFrame(now, &frame)) {
            const bool silence =
                (frame.status & MSHFFeatureStatusSilence) != 0;
            const MSHFSilencePacerDecision decision =
                MSHFSilencePacerShouldDeliver(
                    &gServer.silencePacer, silence, now,
                    kSilenceHeartbeatNs);
            if (decision != MSHFSilencePacerSuppress) {
                const bool transition =
                    decision == MSHFSilencePacerDeliverTransition;
                if (transition) {
                    for (Client &client : gServer.clients) {
                        if (client.used) {
                            MSHFResetFeaturePacer(&client.featurePacer);
                        }
                    }
                }
                SendFeatureFrames(frame, silence);
            }
        }
    }
}

bool ConfigureSocket() {
    gServer.socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (gServer.socketDescriptor < 0) {
        return false;
    }
    int flags = fcntl(gServer.socketDescriptor, F_GETFL, 0);
    if (flags < 0 || fcntl(gServer.socketDescriptor, F_SETFL, flags | O_NONBLOCK) < 0) {
        close(gServer.socketDescriptor);
        gServer.socketDescriptor = -1;
        return false;
    }
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(MSHF_PROTOCOL_PORT);
    if (bind(gServer.socketDescriptor, reinterpret_cast<const sockaddr *>(&address),
             sizeof(address)) < 0) {
        close(gServer.socketDescriptor);
        gServer.socketDescriptor = -1;
        return false;
    }
    return true;
}

} // namespace

bool ConfigureInfrastructure() {
    if (!gRuntime.controlQueue || !ConfigureDSP()) {
        return false;
    }

    __block bool configured = false;
    dispatch_sync(gRuntime.controlQueue, ^{
      if (!ConfigureSocket()) {
          return;
      }

      int capturedSocket = gServer.socketDescriptor;
      dispatch_source_t socketSource = dispatch_source_create(
          DISPATCH_SOURCE_TYPE_READ, capturedSocket, 0, gRuntime.controlQueue);
      if (!socketSource) {
          close(capturedSocket);
          gServer.socketDescriptor = -1;
          return;
      }

      dispatch_source_t analysisTimer = dispatch_source_create(
          DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gRuntime.controlQueue);
      if (!analysisTimer) {
          dispatch_source_set_cancel_handler(socketSource, ^{
            close(capturedSocket);
          });
          dispatch_source_cancel(socketSource);
          dispatch_activate(socketSource);
          gServer.socketDescriptor = -1;
          return;
      }

      gServer.socketSource = socketSource;
      gServer.analysisTimer = analysisTimer;
      dispatch_source_set_event_handler(gServer.socketSource, ^{
        ReadSocket();
      });
      dispatch_source_set_cancel_handler(gServer.socketSource, ^{
        close(capturedSocket);
        if (gServer.socketDescriptor == capturedSocket) {
            gServer.socketDescriptor = -1;
        }
      });
      dispatch_source_set_event_handler(gServer.analysisTimer, ^{
        AnalysisTick();
      });
      dispatch_source_set_cancel_handler(gServer.analysisTimer, ^{
        // The handler runs on the control queue after any in-flight analysis
        // event, so the FFT setup cannot be destroyed while vDSP is using it.
        if (gAnalyzer.fftSetup) {
            vDSP_destroy_fftsetup(gAnalyzer.fftSetup);
            gAnalyzer.fftSetup = nullptr;
        }
      });
      dispatch_source_set_timer(gServer.analysisTimer, DISPATCH_TIME_FOREVER,
                                DISPATCH_TIME_FOREVER, 0);
      dispatch_activate(gServer.socketSource);
      dispatch_activate(gServer.analysisTimer);
      configured = true;
    });

    if (!configured) {
        if (gAnalyzer.fftSetup) {
            vDSP_destroy_fftsetup(gAnalyzer.fftSetup);
            gAnalyzer.fftSetup = nullptr;
        }
        return false;
    }
    return true;
}

} // namespace MSHFServer
