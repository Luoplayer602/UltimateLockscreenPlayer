#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <fcntl.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <math.h>
#import <unistd.h>

#import "Audio/MSH2Client.h"
#import "Playback/ULPLifecycle.h"
#import "Playback/ULPNowPlaying.h"
#import "Visualization/ULPSignal.h"
#import "UI/ULPLockScreenView.h"
#import "UI/ULPBackgroundView.h"
#import "UI/ULPVisualizerView.h"

static ULPMSH2Client *gAudioProbe;
static ULPNowPlaying *gNowPlaying;
static ULPLifecycle gLifecycle;
static ULPSignalState gSignal;
static __weak ULPLockScreenView *gPlayer;
static __weak ULPBackgroundView *gBackground;
static __weak ULPBackgroundView *gFixedBackground;
static __weak ULPVisualizerView *gVisualizer;
static __weak UIView *gMediaView;
static __weak UIView *gCoverSheetView;
static BOOL gEnabled;
static BOOL gCoverSheetVisible;
static BOOL gCoverSheetAuthenticated;
static char kULPOriginalHiddenKey;
static char kULPOriginalAlphaKey;
static char kULPOriginalListInsetKey;
static char kULPReplacementKey;

static void ULPDiagnosticLog(NSString *message);

@interface CSCoverSheetViewController : UIViewController
- (BOOL)authenticated;
@end

@interface CSMediaControlsView : UIView
@end

@interface PLPlatterCustomContentView : UIView
@end

@interface NCNotificationListView : UIScrollView
@end

@interface PLPlatterView : UIView
@property (nonatomic, readonly) UIView *backgroundMaterialView;
@property (nonatomic, readonly) UIView *mainOverlayView;
@property (nonatomic, readonly) UIView *backgroundView;
@end

static BOOL ULPIsActive(void) {
    return gEnabled && gCoverSheetVisible && !gCoverSheetAuthenticated &&
           ULPLifecycleIsVisible(&gLifecycle);
}

static void ULPManageHidden(UIView *view, BOOL hide) {
    NSNumber *original = objc_getAssociatedObject(view, &kULPOriginalHiddenKey);
    if (hide) {
        if (!original) {
            objc_setAssociatedObject(view, &kULPOriginalHiddenKey,
                                     @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.hidden = YES;
    } else if (original) {
        view.hidden = original.boolValue;
        objc_setAssociatedObject(view, &kULPOriginalHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ULPManageDateViews(UIView *view, BOOL hide) {
    if (!view) return;
    if ([NSStringFromClass(view.class) isEqualToString:@"SBFLockScreenDateView"]) {
        ULPManageHidden(view, hide);
        return;
    }
    for (UIView *child in view.subviews)
        ULPManageDateViews(child, hide);
}

static void ULPManageMediaAlpha(UIView *view, BOOL dim, CGFloat dimAlpha) {
    if (!view) return;
    NSNumber *original = objc_getAssociatedObject(view, &kULPOriginalAlphaKey);
    if (dim) {
        if (!original) {
            objc_setAssociatedObject(view, &kULPOriginalAlphaKey,
                                     @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        view.alpha = dimAlpha;
    } else if (original) {
        view.alpha = original.doubleValue;
        objc_setAssociatedObject(view, &kULPOriginalAlphaKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ULPManageListPosition(UIView *mediaView, BOOL active) {
    UIScrollView *list = nil;
    for (UIView *ancestor = mediaView.superview; ancestor; ancestor = ancestor.superview) {
        if ([NSStringFromClass(ancestor.class) isEqualToString:@"NCNotificationListView"] &&
            [ancestor isKindOfClass:[UIScrollView class]]) {
            list = (UIScrollView *)ancestor;
            break;
        }
    }
    if (!list) return;
    NSValue *saved = objc_getAssociatedObject(list, &kULPOriginalListInsetKey);
    if (active && !saved) {
        UIEdgeInsets original = list.contentInset;
        objc_setAssociatedObject(list, &kULPOriginalListInsetKey,
                                 [NSValue valueWithUIEdgeInsets:original],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGFloat shift = MIN(120, CGRectGetHeight(list.bounds) * 0.18);
        UIEdgeInsets adjusted = original;
        adjusted.top += shift;
        CGPoint offset = list.contentOffset;
        list.contentInset = adjusted;
        list.contentOffset = CGPointMake(offset.x, offset.y - shift);
        ULPDiagnosticLog([NSString stringWithFormat:
            @"Native player list moved down %.0fpt inset=%.0f→%.0f",
            shift, original.top, adjusted.top]);
    } else if (active && saved) {
        UIEdgeInsets original = saved.UIEdgeInsetsValue;
        CGFloat shift = MIN(120, CGRectGetHeight(list.bounds) * 0.18);
        CGFloat targetTop = original.top + shift;
        CGFloat currentTop = list.contentInset.top;
        if (fabs(currentTop - targetTop) > 0.5) {
            BOOL atTop = fabs(list.contentOffset.y + currentTop) < 2;
            UIEdgeInsets adjusted = list.contentInset;
            adjusted.top = targetTop;
            list.contentInset = adjusted;
            if (atTop && !list.dragging && !list.decelerating)
                list.contentOffset = CGPointMake(list.contentOffset.x, -targetTop);
            ULPDiagnosticLog([NSString stringWithFormat:
                @"Native player list position restored inset=%.0f→%.0f atTop=%d",
                currentTop, targetTop, atTop]);
        }
    } else if (!active && saved) {
        UIEdgeInsets original = saved.UIEdgeInsetsValue;
        CGFloat shift = list.contentInset.top - original.top;
        CGPoint offset = list.contentOffset;
        list.contentInset = original;
        list.contentOffset = CGPointMake(offset.x, offset.y + shift);
        objc_setAssociatedObject(list, &kULPOriginalListInsetKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void ULPRefreshPresentation(void) {
    BOOL active = ULPIsActive();
    gFixedBackground.hidden = !active;
    gBackground.hidden = !active;
    if (!active) [gBackground resetMotion];
    gVisualizer.hidden = !active;
    gPlayer.hidden = !active;
    ULPManageMediaAlpha(gMediaView, active, 0.001);
    UIView *platter = gMediaView.superview.superview;
    if ([platter isKindOfClass:NSClassFromString(@"PLPlatterView")]) {
        PLPlatterView *nativePlatter = (PLPlatterView *)platter;
        if ([nativePlatter respondsToSelector:@selector(backgroundMaterialView)])
            ULPManageMediaAlpha(nativePlatter.backgroundMaterialView, active, 0);
        if ([nativePlatter respondsToSelector:@selector(mainOverlayView)])
            ULPManageMediaAlpha(nativePlatter.mainOverlayView, active, 0);
        if ([nativePlatter respondsToSelector:@selector(backgroundView)])
            ULPManageMediaAlpha(nativePlatter.backgroundView, active, 0);
    }
    ULPManageDateViews(gCoverSheetView, active);
    ULPManageListPosition(gMediaView, active);
}

static BOOL ULPIsInsideCoverSheet(UIView *view) {
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if (ancestor == gCoverSheetView ||
            [NSStringFromClass(ancestor.class) isEqualToString:@"CSCoverSheetView"] ||
            [NSStringFromClass(ancestor.class) isEqualToString:@"CSCoverSheetViewBase"])
            return YES;
    }
    return NO;
}

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    if (!gEnabled) return;
    ULPBackgroundView *fixedBackground = [[ULPBackgroundView alloc] initWithFrame:self.view.bounds];
    fixedBackground.hidden = YES;
    [self.view insertSubview:fixedBackground atIndex:0];
    gFixedBackground = fixedBackground;
    ULPBackgroundView *background = [[ULPBackgroundView alloc] initWithFrame:self.view.bounds];
    background.hidden = YES;
    [self.view insertSubview:background aboveSubview:fixedBackground];
    [background attachSwipeRecognitionToView:self.view];
    gBackground = background;
    ULPVisualizerView *visualizer = [[ULPVisualizerView alloc] initWithFrame:self.view.bounds];
    visualizer.hidden = YES;
    [self.view insertSubview:visualizer aboveSubview:background];
    gVisualizer = visualizer;
    gCoverSheetView = self.view;
    ULPDiagnosticLog(@"CoverSheet moving and fixed artwork backgrounds attached");
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (gCoverSheetView == self.view) {
        CGFloat width = CGRectGetWidth(self.view.bounds);
        CGFloat height = CGRectGetHeight(self.view.bounds);
        CGFloat overscan = height * ULP_BACKGROUND_OVERSCAN_RATIO;
        gFixedBackground.bounds = CGRectMake(0, 0, width, height + overscan);
        gFixedBackground.center = CGPointMake(width / 2, (height - overscan) / 2);
        gBackground.bounds = CGRectMake(0, 0, width, height + overscan);
        gBackground.center = CGPointMake(width / 2, (height - overscan) / 2);
        gVisualizer.frame = self.view.bounds;
        ULPRefreshPresentation();
    }
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = YES;
    gCoverSheetAuthenticated = [self respondsToSelector:@selector(authenticated)] &&
                               [self authenticated];
    ULPRefreshPresentation();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = NO;
    ULPRefreshPresentation();
}

%end

%hook NCNotificationListView

- (void)layoutSubviews {
    %orig;
    if (gEnabled && gMediaView)
        ULPManageListPosition(gMediaView, ULPIsActive());
}

%end

%hook PLPlatterCustomContentView

- (void)layoutSubviews {
    %orig;
    if (!gEnabled || self.bounds.size.height <= 0) return;
    for (UIView *child in self.subviews) {
        if (![child isKindOfClass:[ULPLockScreenView class]]) continue;
        if (!CGRectEqualToRect(child.frame, self.bounds)) {
            child.frame = self.bounds;
            ULPDiagnosticLog([NSString stringWithFormat:
                @"Native player host resized to %.0fx%.0f",
                self.bounds.size.width, self.bounds.size.height]);
        }
        break;
    }
}

%end

%hook CSMediaControlsView

- (void)didMoveToWindow {
    %orig;
    if (gEnabled && self.window && ULPIsInsideCoverSheet(self))
        [self setNeedsLayout];
}

- (void)layoutSubviews {
    %orig;
    if (!gEnabled || !ULPIsInsideCoverSheet(self)) return;
    UIView *host = self.superview;
    if (!host || ![NSStringFromClass(host.class) isEqualToString:@"PLPlatterCustomContentView"])
        return;
    ULPLockScreenView *replacement = objc_getAssociatedObject(self, &kULPReplacementKey);
    if (!replacement) {
        replacement = [[ULPLockScreenView alloc] initWithFrame:host.bounds];
        replacement.hidden = YES;
        replacement.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        replacement.commandHandler = ^(NSInteger command) { [gNowPlaying sendCommand:command]; };
        replacement.artworkHandler = ^(UIImage *artwork) {
            [gBackground setArtwork:artwork];
            [gFixedBackground setRenderedArtwork:gBackground.renderedArtwork];
        };
        objc_setAssociatedObject(self, &kULPReplacementKey, replacement,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [host addSubview:replacement];
        gPlayer = replacement;
        ULPDiagnosticLog([NSString stringWithFormat:
            @"Native player replacement attached host=%.0fx%.0f media=%.0fx%.0f",
            host.bounds.size.width, host.bounds.size.height,
            self.bounds.size.width, self.bounds.size.height]);
        PLPlatterView *platter = (PLPlatterView *)host.superview;
        ULPDiagnosticLog([NSString stringWithFormat:
            @"Platter class=%@ background=%@ overlay=%@ backgroundView=%@",
            NSStringFromClass(platter.class),
            [platter respondsToSelector:@selector(backgroundMaterialView)] ?
                NSStringFromClass(platter.backgroundMaterialView.class) : @"none",
            [platter respondsToSelector:@selector(mainOverlayView)] ?
                NSStringFromClass(platter.mainOverlayView.class) : @"none",
            [platter respondsToSelector:@selector(backgroundView)] ?
                NSStringFromClass(platter.backgroundView.class) : @"none"]);
    }
    replacement.frame = host.bounds;
    gMediaView = self;
    gPlayer = replacement;
    ULPRefreshPresentation();
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
            [gPlayer updateNowPlaying:snapshot];
            ULPRefreshPresentation();
        }];
        [gNowPlaying start];

        // M1 device probe. UI and playback gating are added after audio validation.
        gAudioProbe = [[ULPMSH2Client alloc] initWithFrameHandler:^(ULPMSH2FeatureFrame frame) {
            ULPSignalProcess(&gSignal, &frame);
            float zoom = gSignal.zoomLevel;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (gVisualizer && !gVisualizer.hidden)
                    [gVisualizer updateAudio:frame zoomLevel:zoom];
                if (gBackground && !gBackground.hidden)
                    [gBackground setZoomLevel:zoom];
                if (gFixedBackground && !gFixedBackground.hidden)
                    [gFixedBackground setZoomLevel:zoom];
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
