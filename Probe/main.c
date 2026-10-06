#include "../Audio/MSH2Protocol.h"

#include <arpa/inet.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static double nowSeconds(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

static void sendRequest(int fd, const struct sockaddr_in *server,
                        uint64_t session, uint64_t sequence, uint64_t serverID,
                        int unsubscribe) {
    uint8_t packet[ULP_MSH2_HEADER_SIZE + ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE];
    size_t length;
    if (unsubscribe) {
        const ULPMSH2Header header = {
            .type = ULP_MSH2_UNSUBSCRIBE, .payloadLength = 0,
            .clientSessionID = session, .serverInstanceID = serverID,
            .sequence = sequence,
        };
        ULPMSH2EncodeHeader(packet, &header);
        length = ULP_MSH2_HEADER_SIZE;
    } else {
        ULPMSH2EncodeSubscribe(packet, session, sequence, 60);
        length = sizeof(packet);
    }
    ssize_t sent = sendto(fd, packet, length, 0,
                          (const struct sockaddr *)server, sizeof(*server));
    printf("%s seq=%llu sent=%zd errno=%d\n", unsubscribe ? "unsubscribe" : "subscribe",
           (unsigned long long)sequence, sent, sent < 0 ? errno : 0);
    fflush(stdout);
}

int main(void) {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) { perror("socket"); return 1; }
    struct sockaddr_in local = {0};
    local.sin_family = AF_INET;
    local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, (const struct sockaddr *)&local, sizeof(local)) != 0) {
        perror("bind"); close(fd); return 1;
    }
    struct sockaddr_in server = {0};
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    server.sin_port = htons(ULP_MSH2_PORT);
    uint64_t session = ((uint64_t)getpid() << 32) ^ (uint64_t)nowSeconds();
    if (!session) session = 1;
    uint64_t sequence = 0, serverID = 0;
    double start = nowSeconds(), nextRequest = 0;
    unsigned packets = 0;

    while (nowSeconds() - start < 20.0) {
        double now = nowSeconds();
        if (now >= nextRequest) {
            sendRequest(fd, &server, session, ++sequence, 0, 0);
            nextRequest = now + 5.0;
        }
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(fd, &readfds);
        struct timeval wait = {.tv_sec = 1, .tv_usec = 0};
        int ready = select(fd + 1, &readfds, NULL, NULL, &wait);
        if (ready < 0) { if (errno == EINTR) continue; perror("select"); break; }
        if (!ready) continue;
        uint8_t packet[ULP_MSH2_MAX_PACKET_SIZE];
        struct sockaddr_in sender = {0};
        socklen_t senderLength = sizeof(sender);
        ssize_t size = recvfrom(fd, packet, sizeof(packet), 0,
                                (struct sockaddr *)&sender, &senderLength);
        if (size < 0) { perror("recvfrom"); continue; }
        ULPMSH2Header header;
        if (!ULPMSH2DecodeHeader(packet, (size_t)size, &header)) {
            printf("invalid header, bytes=%zd\n", size); continue;
        }
        printf("packet type=%u bytes=%zd session=%llu server=%llu seq=%llu sender=%u\n",
               header.type, size, (unsigned long long)header.clientSessionID,
               (unsigned long long)header.serverInstanceID,
               (unsigned long long)header.sequence, ntohs(sender.sin_port));
        if (header.clientSessionID != session || header.type != ULP_MSH2_FEATURE) continue;
        serverID = header.serverInstanceID;
        ULPMSH2FeatureFrame frame;
        if (ULPMSH2DecodeFeature(packet, (size_t)size, &header, &frame)) {
            ++packets;
            if (packets <= 5 || packets % 60 == 0) {
                printf("feature mask=%u rate=%.0f rms=%.4f peak=%.4f bin0=%.4f status=0x%x\n",
                       frame.featureMask, frame.sampleRate, frame.rms,
                       frame.peak, frame.spectrum[0], frame.status);
            }
        } else {
            printf("invalid feature payload length=%u mask=%u sampleRate=%.3f\n",
                   header.payloadLength,
                   ULPMSH2ReadU32(packet + ULP_MSH2_HEADER_SIZE + 8),
                   ULPMSH2ReadF32(packet + ULP_MSH2_HEADER_SIZE + 16));
        }
        fflush(stdout);
    }
    if (serverID) sendRequest(fd, &server, session, ++sequence, serverID, 1);
    printf("total valid feature packets=%u\n", packets);
    close(fd);
    return packets ? 0 : 2;
}
