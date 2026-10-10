#import "ULPNowPlaying.h"
#import <dlfcn.h>
#import <dispatch/dispatch.h>
#import <mach/mach_time.h>
#import <math.h>
#import "ULPProgressClock.h"

typedef void (*ULPMRGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*ULPMRGetPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*ULPMRGetPID)(dispatch_queue_t, void (^)(int));
typedef Boolean (*ULPMRSendCommand)(NSInteger, NSDictionary *);

@interface ULPArtworkController : NSObject
- (void)setShouldUpdateNowPlayingArtwork:(BOOL)update;
- (UIImage *)currentNowPlayingArtwork;
- (void)startUpdating;
- (void)stopUpdating;
@end
@interface ULPSBMediaController : NSObject
+ (instancetype)sharedInstance;
- (NSDictionary *)currentNowPlayingInfo;
@end

static double ULPMonotonicSeconds(void) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    return (double)mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}

@implementation ULPNowPlayingSnapshot
@end

@interface ULPNowPlaying () {
    void *_framework;
    ULPMRGetInfo _getInfo;
    ULPMRGetPlaying _getPlaying;
    ULPMRGetPID _getPID;
    ULPMRSendCommand _sendCommand;
    ULPArtworkController *_artworkController;
    UIImage *_rejectedArtworkImage;
    dispatch_source_t _timer;
    uint64_t _generation;
    BOOL _running, _inFlight, _pendingRefresh;
    ULPProgressClock _progressClock;
    ULPNowPlayingSnapshot *_lastSnapshot;
    double _lastMetadataTime, _lastArtworkRestart;
    double _lastProgressLogTime;
    double _nextRefreshTime;
    NSUInteger _timeoutCount;
    NSUInteger _artworkRetries;
    NSString *_lastHealth;
}
@property (nonatomic, copy) ULPNowPlayingHandler handler;
@end

@implementation ULPNowPlaying
- (instancetype)initWithHandler:(ULPNowPlayingHandler)handler {
    self = [super init];
    if (self) _handler = [handler copy];
    return self;
}
- (void)record:(NSString *)message {
    if (self.diagnosticHandler) self.diagnosticHandler(message);
}
- (void)restartArtworkUpdates {
    if ([_artworkController respondsToSelector:@selector(currentNowPlayingArtwork)])
        _rejectedArtworkImage = [_artworkController currentNowPlayingArtwork];
    if ([_artworkController respondsToSelector:@selector(stopUpdating)])
        [_artworkController stopUpdating];
    _artworkController = nil;
    Class artworkClass = NSClassFromString(@"MPUNowPlayingController");
    if (artworkClass) {
        _artworkController = [[artworkClass alloc] init];
        if ([_artworkController respondsToSelector:@selector(setShouldUpdateNowPlayingArtwork:)])
            [_artworkController setShouldUpdateNowPlayingArtwork:YES];
        if ([_artworkController respondsToSelector:@selector(startUpdating)])
            [_artworkController startUpdating];
    }
    _lastArtworkRestart = ULPMonotonicSeconds();
    [self record:[NSString stringWithFormat:@"Artwork observer restarted available=%d", _artworkController != nil]];
}
- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_running) return;
        if (!self->_framework)
            self->_framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
        if (!self->_framework) return;
        self->_getInfo = (ULPMRGetInfo)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingInfo");
        self->_getPlaying = (ULPMRGetPlaying)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        self->_getPID = (ULPMRGetPID)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingApplicationPID");
        self->_sendCommand = (ULPMRSendCommand)dlsym(self->_framework, "MRMediaRemoteSendCommand");
        if (!self->_getInfo || !self->_getPlaying) return;
        self->_running = YES;
        [self restartArtworkUpdates];
        self->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self->_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
        // A timer tick cannot invalidate an unfinished request.
        dispatch_source_set_event_handler(self->_timer, ^{ if (!self->_inFlight) [self refresh]; });
        dispatch_resume(self->_timer);
    });
}
- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_running = NO;
        ++self->_generation;
        self->_inFlight = NO; self->_pendingRefresh = NO;
        if (self->_timer) dispatch_source_cancel(self->_timer);
        self->_timer = nil;
        if ([self->_artworkController respondsToSelector:@selector(stopUpdating)])
            [self->_artworkController stopUpdating];
        self->_artworkController = nil;
        self->_rejectedArtworkImage = nil;
        self->_lastSnapshot = nil;
        ULPProgressClockReset(&self->_progressClock);
    });
}
- (void)requestRefresh {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_running) return;
        if (self->_inFlight) self->_pendingRefresh = YES;
        else [self refresh];
    });
}
- (id)valueForSymbol:(const char *)symbol inInfo:(NSDictionary *)info {
    CFStringRef *key = (CFStringRef *)dlsym(_framework, symbol);
    return key && *key ? info[(__bridge NSString *)*key] : nil;
}
- (void)finishRequest:(uint64_t)generation {
    if (generation != _generation) return;
    _inFlight = NO;
    if (_pendingRefresh) {
        _pendingRefresh = NO;
        [self requestRefresh];
    }
}
- (void)consumeInfo:(NSDictionary *)info pid:(int)pid playing:(BOOL)playing {
    double now = ULPMonotonicSeconds();
    ULPNowPlayingSnapshot *snapshot = [ULPNowPlayingSnapshot new];
    snapshot.processID = pid; snapshot.playing = playing;
    id title = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoTitle" inInfo:info];
    id artist = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtist" inInfo:info];
    if ([title isKindOfClass:NSString.class]) snapshot.title = title;
    if ([artist isKindOfClass:NSString.class]) snapshot.artist = artist;
    BOOL freshMetadata = snapshot.title.length || snapshot.artist.length;
    // A short metadata gap may reuse identity only within the same live PID.
    if (!freshMetadata && pid > 0 && pid == _lastSnapshot.processID && now - _lastMetadataTime <= 2) {
        snapshot.title = _lastSnapshot.title; snapshot.artist = _lastSnapshot.artist;
    } else if (snapshot.title.length && pid == _lastSnapshot.processID &&
               [snapshot.title isEqualToString:_lastSnapshot.title] && !snapshot.artist.length)
        snapshot.artist = _lastSnapshot.artist;
    if (freshMetadata) _lastMetadataTime = now;
    snapshot.sessionPresent = pid > 0 || snapshot.title.length || snapshot.artist.length;
    snapshot.trackIdentifier = snapshot.sessionPresent ? [NSString stringWithFormat:@"%d|%@|%@",
        pid, snapshot.title ?: @"", snapshot.artist ?: @""] : nil;
    BOOL sameTrack = snapshot.trackIdentifier.length &&
                     [snapshot.trackIdentifier isEqualToString:_lastSnapshot.trackIdentifier];
    if (!sameTrack && (snapshot.trackIdentifier.length || _lastSnapshot.trackIdentifier.length)) {
        ULPProgressClockReset(&_progressClock);
        _artworkRetries = 0;
        if (snapshot.sessionPresent) [self restartArtworkUpdates];
        [self record:[NSString stringWithFormat:@"NowPlaying identity changed oldPID=%d newPID=%d metadata=%d",
            _lastSnapshot.processID, pid, freshMetadata]];
    }
    id duration = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoDuration" inInfo:info];
    snapshot.duration = [duration isKindOfClass:NSNumber.class] && isfinite([duration doubleValue]) &&
                        [duration doubleValue] > 0 ? [duration doubleValue] : (sameTrack ? _lastSnapshot.duration : 0);
    id rate = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoPlaybackRate" inInfo:info];
    snapshot.playbackRate = [rate isKindOfClass:NSNumber.class] && isfinite([rate doubleValue]) &&
                           [rate doubleValue] > 0 && [rate doubleValue] <= 4 ? [rate doubleValue] : 1;
    id elapsed = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoElapsedTime" inInfo:info];
    BOOL validElapsed = [elapsed isKindOfClass:NSNumber.class] && isfinite([elapsed doubleValue]) && [elapsed doubleValue] >= 0;
    id timestamp = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoTimestamp" inInfo:info];
    double sourceTimestamp = [timestamp isKindOfClass:NSDate.class] ? [timestamp timeIntervalSinceReferenceDate] : 0;
    double wallTime = CFAbsoluteTimeGetCurrent();
    snapshot.elapsed = ULPProgressClockUpdateSource(&_progressClock,
        validElapsed ? [elapsed doubleValue] : NAN, sourceTimestamp, snapshot.duration,
        playing, snapshot.playbackRate, wallTime, now);
    if (now - _lastProgressLogTime >= 10 || (sameTrack && snapshot.elapsed < _lastSnapshot.elapsed - 1)) {
        _lastProgressLogTime = now;
        [self record:[NSString stringWithFormat:@"Progress sample pid=%d rawValid=%d raw=%.2f elapsed=%.2f duration=%.2f rate=%.2f playing=%d timestamp=%.3f age=%.3f timestampClass=%@",
            pid, validElapsed, validElapsed ? [elapsed doubleValue] : -1,
            snapshot.elapsed, snapshot.duration, snapshot.playbackRate, playing,
            sourceTimestamp, sourceTimestamp > 0 ? wallTime - sourceTimestamp : -1,
            timestamp ? NSStringFromClass([timestamp class]) : @"nil"]];
    }
    id artwork = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtworkData" inInfo:info];
    NSString *artworkSource = @"none";
    if ([artwork isKindOfClass:NSData.class] && [artwork length]) {
        snapshot.artworkData = artwork; artworkSource = @"MediaRemote";
    }
    // SpringBoard fallback must match the current track, not an arbitrary old
    // Now Playing dictionary or Control Center image.
    if (!snapshot.artworkData.length && freshMetadata && snapshot.title.length) {
        Class cls = NSClassFromString(@"SBMediaController");
        id controller = [cls respondsToSelector:@selector(sharedInstance)] ? [cls sharedInstance] : nil;
        NSDictionary *systemInfo = [controller respondsToSelector:@selector(currentNowPlayingInfo)] ?
                                  [controller currentNowPlayingInfo] : nil;
        if ([systemInfo isKindOfClass:NSDictionary.class]) {
            id systemTitle = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoTitle" inInfo:systemInfo];
            id systemArtist = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtist" inInfo:systemInfo];
            BOOL match = [systemTitle isEqual:snapshot.title] &&
                         (!snapshot.artist.length || [systemArtist isEqual:snapshot.artist]);
            id data = match ? [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtworkData" inInfo:systemInfo] : nil;
            if ([data isKindOfClass:NSData.class] && [data length]) {
                snapshot.artworkData = data; artworkSource = @"SpringBoard";
            }
        }
    }
    if (!snapshot.artworkData.length && freshMetadata && now - _lastArtworkRestart >= .4 &&
        [_artworkController respondsToSelector:@selector(currentNowPlayingArtwork)]) {
        UIImage *image = [_artworkController currentNowPlayingArtwork];
        if ([image isKindOfClass:UIImage.class] && image != _rejectedArtworkImage) {
            snapshot.artworkImage = image; artworkSource = @"artwork-controller";
        }
    }
    if (!snapshot.artworkData.length && !snapshot.artworkImage && sameTrack) {
        snapshot.artworkData = _lastSnapshot.artworkData;
        snapshot.artworkImage = _lastSnapshot.artworkImage;
        if (snapshot.artworkData.length || snapshot.artworkImage) artworkSource = @"same-track-cache";
    }
    if (freshMetadata && !snapshot.artworkData.length && !snapshot.artworkImage &&
        now - _lastArtworkRestart >= 5 && _artworkRetries < 2) {
        ++_artworkRetries;
        [self restartArtworkUpdates];
    }
    NSString *health = [NSString stringWithFormat:@"NowPlaying health pid=%d present=%d metadata=%d artwork=%@ elapsedValid=%d",
        pid, snapshot.sessionPresent, freshMetadata, artworkSource, validElapsed];
    if (![health isEqualToString:_lastHealth]) { _lastHealth = health; [self record:health]; }
    _lastSnapshot = snapshot;
    if (self.handler) self.handler(snapshot);
}
- (void)refresh {
    if (!_running || _inFlight || ULPMonotonicSeconds() < _nextRefreshTime) return;
    _inFlight = YES;
    uint64_t generation = ++_generation;
    __weak typeof(self) weakSelf = self;
    void (^readInfo)(int) = ^(int initialPID) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self->_running || generation != self->_generation) return;
        self->_getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef rawInfo) {
            if (!self->_running || generation != self->_generation) return;
            NSDictionary *info = [(__bridge id)rawInfo isKindOfClass:NSDictionary.class] ?
                                 [(__bridge NSDictionary *)rawInfo copy] : @{};
            self->_getPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
                if (!self->_running || generation != self->_generation) return;
                void (^finish)(int) = ^(int finalPID) {
                    if (!self->_running || generation != self->_generation) return;
                    if (finalPID == initialPID) {
                        self->_timeoutCount = 0;
                        self->_nextRefreshTime = 0;
                        [self consumeInfo:info pid:finalPID playing:playing];
                    }
                    else {
                        [self record:@"NowPlaying client changed during refresh; discarded mixed snapshot"];
                        self->_pendingRefresh = YES;
                    }
                    [self finishRequest:generation];
                };
                if (self->_getPID) self->_getPID(dispatch_get_main_queue(), finish);
                else finish(initialPID);
            });
        });
    };
    if (_getPID) _getPID(dispatch_get_main_queue(), readInfo);
    else readInfo(0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self->_running || !self->_inFlight || generation != self->_generation) return;
        [self record:@"NowPlaying refresh timed out; invalidating late callbacks"];
        ++self->_generation; self->_inFlight = NO; self->_pendingRefresh = NO;
        self->_timeoutCount = MIN(4, self->_timeoutCount + 1);
        self->_nextRefreshTime = ULPMonotonicSeconds() + MIN(30, pow(2, self->_timeoutCount));
        [self consumeInfo:@{} pid:0 playing:NO];
    });
}
- (BOOL)sendCommand:(NSInteger)command {
    BOOL accepted = _sendCommand ? _sendCommand(command, nil) : NO;
    [self requestRefresh];
    return accepted;
}
@end
