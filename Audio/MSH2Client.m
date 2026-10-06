#import "MSH2Client.h"

#import <arpa/inet.h>
#import <dispatch/dispatch.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/socket.h>
#import <unistd.h>

@interface ULPMSH2Client () {
    dispatch_queue_t _queue;
    dispatch_source_t _reader;
    dispatch_source_t _leaseTimer;
    int _socket;
    uint64_t _sessionID;
    uint64_t _requestSequence;
    uint64_t _lastFeatureSequence;
    uint64_t _serverInstanceID;
    BOOL _started;
    BOOL _stopped;
}
@property (nonatomic, copy) ULPMSH2FrameHandler handler;
@property (nonatomic, copy) ULPMSH2StatusHandler statusHandler;
@end

@implementation ULPMSH2Client

- (instancetype)initWithFrameHandler:(ULPMSH2FrameHandler)handler
                        statusHandler:(ULPMSH2StatusHandler)statusHandler {
    self = [super init];
    if (self) {
        _handler = [handler copy];
        _statusHandler = [statusHandler copy];
        _queue = dispatch_queue_create("com.luoplayer.ulp.msh2", DISPATCH_QUEUE_SERIAL);
        _socket = -1;
        _sessionID = ((uint64_t)arc4random() << 32) | arc4random();
        if (_sessionID == 0) _sessionID = 1;
    }
    return self;
}

- (void)start {
    dispatch_async(_queue, ^{
        if (self->_started || self->_stopped) return;
        self->_started = YES;
        self->_socket = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (self->_socket < 0) {
            [self report:[NSString stringWithFormat:@"socket failed errno=%d", errno]];
            return;
        }
        int flags = fcntl(self->_socket, F_GETFL, 0);
        if (flags < 0 || fcntl(self->_socket, F_SETFL, flags | O_NONBLOCK) < 0) {
            [self report:[NSString stringWithFormat:@"fcntl failed errno=%d", errno]];
            close(self->_socket);
            self->_socket = -1;
            return;
        }
        struct sockaddr_in local = {0};
        local.sin_family = AF_INET;
        local.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        local.sin_port = 0;
        if (bind(self->_socket, (const struct sockaddr *)&local, sizeof(local)) != 0) {
            [self report:[NSString stringWithFormat:@"bind failed errno=%d", errno]];
            close(self->_socket);
            self->_socket = -1;
            return;
        }

        const int fd = self->_socket;
        self->_reader = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, fd, 0, self->_queue);
        self->_leaseTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self->_queue);
        if (!self->_reader || !self->_leaseTimer) {
            [self report:@"dispatch source creation failed"];
            if (self->_reader) {
                dispatch_source_set_cancel_handler(self->_reader, ^{ close(fd); });
                dispatch_resume(self->_reader);
                dispatch_source_cancel(self->_reader);
                self->_reader = nil;
            } else {
                close(fd);
            }
            if (self->_leaseTimer) {
                dispatch_resume(self->_leaseTimer);
                dispatch_source_cancel(self->_leaseTimer);
                self->_leaseTimer = nil;
            }
            self->_socket = -1;
            return;
        }
        dispatch_source_set_event_handler(self->_reader, ^{ [self readAvailablePackets]; });
        dispatch_source_set_cancel_handler(self->_reader, ^{ close(fd); });
        dispatch_source_set_event_handler(self->_leaseTimer, ^{ [self sendSubscribe]; });
        dispatch_source_set_timer(self->_leaseTimer, DISPATCH_TIME_NOW,
                                  5 * NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_resume(self->_reader);
        dispatch_resume(self->_leaseTimer);
        [self report:@"UDP listener ready"];
    });
}

- (void)stop {
    dispatch_async(_queue, ^{
        if (self->_stopped) return;
        self->_stopped = YES;
        if (self->_socket >= 0 && self->_serverInstanceID != 0) {
            uint8_t packet[ULP_MSH2_HEADER_SIZE];
            const ULPMSH2Header header = {
                .type = ULP_MSH2_UNSUBSCRIBE,
                .payloadLength = 0,
                .clientSessionID = self->_sessionID,
                .serverInstanceID = self->_serverInstanceID,
                .sequence = ++self->_requestSequence,
            };
            ULPMSH2EncodeHeader(packet, &header);
            [self sendPacket:packet length:sizeof(packet)];
        }
        if (self->_leaseTimer) {
            dispatch_source_cancel(self->_leaseTimer);
            self->_leaseTimer = nil;
        }
        if (self->_reader) {
            dispatch_source_cancel(self->_reader);
            self->_reader = nil;
        }
        else if (self->_socket >= 0) close(self->_socket);
        self->_socket = -1;
    });
}

- (void)sendPacket:(const uint8_t *)packet length:(size_t)length {
    struct sockaddr_in server = {0};
    server.sin_family = AF_INET;
    server.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    server.sin_port = htons(ULP_MSH2_PORT);
    ssize_t sent = sendto(_socket, packet, length, 0,
                          (const struct sockaddr *)&server, sizeof(server));
    if (sent < 0) [self report:[NSString stringWithFormat:@"sendto failed errno=%d", errno]];
}

- (void)sendSubscribe {
    if (_stopped || _socket < 0) return;
    uint8_t packet[ULP_MSH2_HEADER_SIZE + ULP_MSH2_SUBSCRIBE_PAYLOAD_SIZE];
    ULPMSH2EncodeSubscribe(packet, _sessionID, ++_requestSequence, 60);
    [self sendPacket:packet length:sizeof(packet)];
    if (_requestSequence <= 2) [self report:@"MSH2 subscribe sent"];
}

- (void)report:(NSString *)message {
    if (_statusHandler) _statusHandler(message);
}

- (void)readAvailablePackets {
    for (unsigned count = 0; count < 32; ++count) {
        uint8_t packet[ULP_MSH2_MAX_PACKET_SIZE];
        struct sockaddr_in sender = {0};
        socklen_t senderLength = sizeof(sender);
        ssize_t size = recvfrom(_socket, packet, sizeof(packet), 0,
                                (struct sockaddr *)&sender, &senderLength);
        if (size < 0) {
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK)
                [self report:[NSString stringWithFormat:@"recvfrom failed errno=%d", errno]];
            return;
        }
        static unsigned receivedCount;
        if (++receivedCount <= 2)
            [self report:[NSString stringWithFormat:@"UDP packet received bytes=%zd", size]];
        if (senderLength != sizeof(sender) || sender.sin_family != AF_INET ||
            sender.sin_addr.s_addr != htonl(INADDR_LOOPBACK) ||
            sender.sin_port != htons(ULP_MSH2_PORT)) continue;

        ULPMSH2Header header;
        if (!ULPMSH2DecodeHeader(packet, (size_t)size, &header) ||
            header.type != ULP_MSH2_FEATURE ||
            header.clientSessionID != _sessionID || header.serverInstanceID == 0) {
            if (receivedCount <= 2) [self report:@"UDP packet header/session rejected"];
            continue;
        }
        if (_serverInstanceID != header.serverInstanceID) {
            _serverInstanceID = header.serverInstanceID;
            _lastFeatureSequence = 0;
        }
        if (header.sequence <= _lastFeatureSequence) continue;
        ULPMSH2FeatureFrame frame;
        if (!ULPMSH2DecodeFeature(packet, (size_t)size, &header, &frame)) {
            if (receivedCount <= 2) [self report:@"MSH2 feature payload rejected"];
            continue;
        }
        _lastFeatureSequence = header.sequence;
        if (_handler && !_stopped) _handler(frame);
    }
}

@end
