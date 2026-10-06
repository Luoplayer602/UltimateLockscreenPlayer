#import "ULPNowPlaying.h"

#import <dlfcn.h>
#import <dispatch/dispatch.h>

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

@implementation ULPNowPlayingSnapshot
@end

@interface ULPNowPlaying () {
    void *_framework;
    ULPMRGetInfo _getInfo;
    ULPMRGetPlaying _getPlaying;
    ULPMRGetPID _getPID;
    ULPMRSendCommand _sendCommand;
    ULPArtworkController *_artworkController;
    dispatch_source_t _timer;
    uint64_t _generation;
    BOOL _running;
}
@property (nonatomic, copy) ULPNowPlayingHandler handler;
@end

@implementation ULPNowPlaying

- (instancetype)initWithHandler:(ULPNowPlayingHandler)handler {
    self = [super init];
    if (self) _handler = [handler copy];
    return self;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_running) return;
        self->_framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY | RTLD_LOCAL);
        if (!self->_framework) return;
        self->_getInfo = (ULPMRGetInfo)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingInfo");
        self->_getPlaying = (ULPMRGetPlaying)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        self->_getPID = (ULPMRGetPID)dlsym(self->_framework, "MRMediaRemoteGetNowPlayingApplicationPID");
        self->_sendCommand = (ULPMRSendCommand)dlsym(self->_framework, "MRMediaRemoteSendCommand");
        if (!self->_getInfo || !self->_getPlaying) return;
        Class artworkClass = NSClassFromString(@"MPUNowPlayingController");
        if (artworkClass) {
            self->_artworkController = [[artworkClass alloc] init];
            if ([self->_artworkController respondsToSelector:@selector(setShouldUpdateNowPlayingArtwork:)])
                [self->_artworkController setShouldUpdateNowPlayingArtwork:YES];
            if ([self->_artworkController respondsToSelector:@selector(startUpdating)])
                [self->_artworkController startUpdating];
        }
        self->_running = YES;
        self->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(self->_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC, NSEC_PER_SEC / 10);
        dispatch_source_set_event_handler(self->_timer, ^{ [self refresh]; });
        dispatch_resume(self->_timer);
    });
}

- (void)stop {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_running) return;
        self->_running = NO;
        ++self->_generation;
        if (self->_timer) dispatch_source_cancel(self->_timer);
        self->_timer = nil;
        if ([self->_artworkController respondsToSelector:@selector(stopUpdating)])
            [self->_artworkController stopUpdating];
        self->_artworkController = nil;
    });
}

- (id)valueForSymbol:(const char *)symbol inInfo:(NSDictionary *)info {
    CFStringRef *key = (CFStringRef *)dlsym(_framework, symbol);
    return key && *key ? info[(__bridge NSString *)*key] : nil;
}

- (void)refresh {
    if (!_running) return;
    uint64_t generation = ++_generation;
    __weak typeof(self) weakSelf = self;
    _getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef rawInfo) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self->_running || generation != self->_generation) return;
        NSDictionary *info = (__bridge NSDictionary *)rawInfo;
        if (![info isKindOfClass:[NSDictionary class]]) info = @{};
        ULPNowPlayingSnapshot *snapshot = [ULPNowPlayingSnapshot new];
        id title = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoTitle" inInfo:info];
        id artist = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtist" inInfo:info];
        id artwork = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtworkData" inInfo:info];
        if (![artwork isKindOfClass:[NSData class]]) {
            Class controllerClass = NSClassFromString(@"SBMediaController");
            if ([controllerClass respondsToSelector:@selector(sharedInstance)]) {
                ULPSBMediaController *controller = [controllerClass sharedInstance];
                if ([controller respondsToSelector:@selector(currentNowPlayingInfo)]) {
                    NSDictionary *systemInfo = [controller currentNowPlayingInfo];
                    if ([systemInfo isKindOfClass:[NSDictionary class]])
                        artwork = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoArtworkData"
                                                 inInfo:systemInfo];
                }
            }
        }
        id duration = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoDuration" inInfo:info];
        id elapsed = [self valueForSymbol:"kMRMediaRemoteNowPlayingInfoElapsedTime" inInfo:info];
        if ([title isKindOfClass:[NSString class]]) snapshot.title = title;
        if ([artist isKindOfClass:[NSString class]]) snapshot.artist = artist;
        if ([artwork isKindOfClass:[NSData class]]) snapshot.artworkData = artwork;
        if (snapshot.artworkData.length == 0 &&
            [self->_artworkController respondsToSelector:@selector(currentNowPlayingArtwork)]) {
            UIImage *image = [self->_artworkController currentNowPlayingArtwork];
            if ([image isKindOfClass:[UIImage class]]) snapshot.artworkImage = image;
        }
        if ([duration respondsToSelector:@selector(doubleValue)]) snapshot.duration = [duration doubleValue];
        if ([elapsed respondsToSelector:@selector(doubleValue)]) snapshot.elapsed = [elapsed doubleValue];
        self->_getPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            if (!self->_running || generation != self->_generation) return;
            snapshot.playing = playing;
            if (self->_getPID) {
                self->_getPID(dispatch_get_main_queue(), ^(int pid) {
                    if (!self->_running || generation != self->_generation) return;
                    snapshot.processID = pid;
                    if (self.handler) self.handler(snapshot);
                });
            } else if (self.handler) self.handler(snapshot);
        });
    });
}

- (BOOL)sendCommand:(NSInteger)command {
    return _sendCommand ? _sendCommand(command, nil) : NO;
}

@end
