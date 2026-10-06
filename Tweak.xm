#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <mach/mach_time.h>
#import <unistd.h>

#import "Audio/MSH2Client.h"
#import "Playback/ULPLifecycle.h"
#import "Playback/ULPNowPlaying.h"
#import "Visualization/ULPSignal.h"
#import "UI/ULPLockScreenView.h"

static ULPMSH2Client *gAudioProbe;
static ULPNowPlaying *gNowPlaying;
static ULPLifecycle gLifecycle;
static ULPSignalState gSignal;
static __weak ULPLockScreenView *gOverlay;
static BOOL gEnabled;
static BOOL gCoverSheetVisible;
static BOOL gCoverSheetAuthenticated;

static void ULPDiagnosticLog(NSString *message);

@interface CSCoverSheetViewController : UIViewController
- (BOOL)authenticated;
@end

static void ULPRefreshOverlay(void) {
    if (!gOverlay) return;
    gOverlay.hidden = !gEnabled || !gCoverSheetVisible ||
                      gCoverSheetAuthenticated || !ULPLifecycleIsVisible(&gLifecycle);
}

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    if (!gEnabled) return;
    ULPLockScreenView *overlay = [[ULPLockScreenView alloc] initWithFrame:self.view.bounds];
    overlay.hidden = YES;
    overlay.commandHandler = ^(NSInteger command) { [gNowPlaying sendCommand:command]; };
    [self.view addSubview:overlay];
    gOverlay = overlay;
    ULPDiagnosticLog(@"CoverSheet overlay attached");
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = YES;
    gCoverSheetAuthenticated = [self respondsToSelector:@selector(authenticated)] &&
                               [self authenticated];
    ULPRefreshOverlay();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = NO;
    ULPRefreshOverlay();
}

%end

static uint64_t ULPNowMs(void) {
    static mach_timebase_info_data_t timebase;
    if (!timebase.denom) mach_timebase_info(&timebase);
    return mach_absolute_time() * timebase.numer / timebase.denom / 1000000;
}

static void ULPDiagnosticLog(NSString *message) {
    NSLog(@"[ULP] %@", message);
    NSString *line = [NSString stringWithFormat:@"%.3f %@\n", CFAbsoluteTimeGetCurrent(), message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open("/var/mobile/Library/Logs/ULP.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    (void)write(fd, data.bytes, data.length);
    close(fd);
}

%ctor {
    @autoreleasepool {
        ULPDiagnosticLog(@"SpringBoard tweak loaded");
        CFPropertyListRef value = CFPreferencesCopyAppValue(
            CFSTR("Enabled"), CFSTR("com.luoplayer.ultimatelockscreenplayer"));
        BOOL enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() &&
                       CFBooleanGetValue((CFBooleanRef)value);
        if (value) CFRelease(value);
        if (!enabled) return;
        gEnabled = YES;

        ULPLifecycleInit(&gLifecycle, 15000);
        ULPSignalInit(&gSignal);
        gNowPlaying = [[ULPNowPlaying alloc] initWithHandler:^(ULPNowPlayingSnapshot *snapshot) {
            static BOOL lastArtwork;
            ULPPlaybackPresentation previous = gLifecycle.presentation;
            uint64_t now = ULPNowMs();
            ULPLifecycleSetPlaying(&gLifecycle, snapshot.playing, now);
            ULPLifecycleTick(&gLifecycle, now);
            BOOL hasArtwork = snapshot.artworkData.length > 0 || snapshot.artworkImage != nil;
            if (previous != gLifecycle.presentation || lastArtwork != hasArtwork) {
                ULPDiagnosticLog([NSString stringWithFormat:
                    @"NowPlaying state=%d pid=%d titlePresent=%d artworkPresent=%d duration=%.1f",
                    gLifecycle.presentation, snapshot.processID,
                    snapshot.title.length > 0, hasArtwork,
                    snapshot.duration]);
            }
            lastArtwork = hasArtwork;
            [gOverlay updateNowPlaying:snapshot];
            ULPRefreshOverlay();
        }];
        [gNowPlaying start];

        // M1 device probe. UI and playback gating are added after audio validation.
        gAudioProbe = [[ULPMSH2Client alloc] initWithFrameHandler:^(ULPMSH2FeatureFrame frame) {
            ULPSignalProcess(&gSignal, &frame);
            float zoom = gSignal.zoomLevel;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (gOverlay && !gOverlay.hidden)
                    [gOverlay updateAudio:frame zoomLevel:zoom];
            });
            static CFAbsoluteTime lastLog;
            CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
            if (now - lastLog < 2.0) return;
            lastLog = now;
            ULPDiagnosticLog([NSString stringWithFormat:
                @"MSH2 sampleRate=%.0f rms=%.3f peak=%.3f spectrum0=%.3f visual=%.3f zoom=%.3f status=0x%x",
                frame.sampleRate, frame.rms, frame.peak, frame.spectrum[0],
                gSignal.visualLevel, gSignal.zoomLevel, frame.status]);
        } statusHandler:^(NSString *message) {
            ULPDiagnosticLog(message);
        }];
        [gAudioProbe start];
        ULPDiagnosticLog(@"MSH2 probe started");
    }
}
