#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AVFoundation/AVFoundation.h>
#import <fcntl.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <math.h>
#import <unistd.h>

#import "Audio/MSH2Client.h"
#import "Playback/ULPLifecycle.h"
#import "Playback/ULPNowPlaying.h"
#import "Visualization/ULPSignal.h"
#import "Visualization/ULPVisualPreferences.h"
#import "UI/ULPLockScreenView.h"
#import "UI/ULPBackgroundView.h"
#import "UI/ULPVisualizerView.h"
#import "UI/ULPVolumeHUDView.h"

static ULPMSH2Client *gAudioProbe;
static ULPNowPlaying *gNowPlaying;
static ULPLifecycle gLifecycle;
static ULPSignalState gSignal;
static ULPVisualConfig gVisualConfig;
static UIColor *gVisualManualColor;
static __weak ULPLockScreenView *gPlayer;
static __weak ULPBackgroundView *gBackground;
static __weak ULPBackgroundView *gFixedBackground;
static __weak ULPVisualizerView *gVisualizer;
static __weak UIView *gMediaView;
static __weak UIView *gCoverSheetView;
static __weak ULPVolumeHUDView *gVolumeHUD;
static BOOL gEnabled;
static BOOL gCoverSheetVisible;
static BOOL gCoverSheetAuthenticated;
static BOOL gHasNowPlaying;
static BOOL gSceneShown;
static uint64_t gSessionLastSeenMs;
static int gLastProcessID;
static NSUInteger gSceneGeneration;
static dispatch_source_t gPauseDecayTimer;
static dispatch_source_t gVolumePollTimer;
static NSString *gActiveAudioCategoryKey;
static uint64_t gPauseDecayStartMs;
static char kULPOriginalHiddenKey;
static char kULPReplacementKey;
static char kULPOriginalAlphaKey;
static char kULPOriginalListInsetKey;

static void ULPDiagnosticLog(NSString *message);
static BOOL ULPIsActive(void);

@interface ULPVolumeObserver : NSObject
@property (nonatomic) float lastVolume;
- (void)handleVolume:(float)volume;
@end

@implementation ULPVolumeObserver
- (void)handleVolume:(float)volume {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self handleVolume:volume]; });
        return;
    }
    if (!isfinite(volume) || fabsf(volume - self.lastVolume) < .005f) return;
    float previousVolume = self.lastVolume;
    self.lastVolume = volume;
    if (ULPIsActive()) ULPDiagnosticLog([NSString stringWithFormat:@"Volume changed %.3f", volume]);
    if (ULPIsActive() && gVolumeHUD)
        [gVolumeHUD showVolume:volume previousVolume:previousVolume];
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                       change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"outputVolume"])
        [self handleVolume:[AVAudioSession sharedInstance].outputVolume];
}
- (void)volumeDidChange:(NSNotification *)notification {
    NSNumber *value = notification.userInfo[@"AVSystemController_AudioVolumeNotificationParameter"];
    if ([value isKindOfClass:NSNumber.class]) [self handleVolume:value.floatValue];
}
@end

static ULPVolumeObserver *gVolumeObserver;

static CFPropertyListRef ULPPreference(CFStringRef key) {
    return CFPreferencesCopyAppValue(key, CFSTR("com.luoplayer.ultimatelockscreenplayer"));
}





static BOOL ULPPreferenceBool(CFStringRef key, BOOL fallback) {
    CFPropertyListRef value = ULPPreference(key);
    BOOL result = fallback;
    if (value && CFGetTypeID(value) == CFBooleanGetTypeID())
        result = CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return result;
}

@interface CSCoverSheetViewController : UIViewController
- (BOOL)authenticated;
@end

@interface CSMediaControlsView : UIView
@end

@interface PLPlatterCustomContentView : UIView
@end

@interface NCNotificationListView : UIScrollView
@end

@interface SBFLockScreenDateView : UIView
@end

@interface PLPlatterView : UIView
@property (nonatomic, readonly) UIView *backgroundMaterialView;
@property (nonatomic, readonly) UIView *mainOverlayView;
@property (nonatomic, readonly) UIView *backgroundView;
@end

@interface ULPSBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@end

@interface ULPSBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (ULPSBApplication *)applicationWithPid:(int)pid;
@end

@interface ULPSBMediaController : NSObject
+ (instancetype)sharedInstance;
- (ULPSBApplication *)nowPlayingApplication;
@end

@interface ULPLSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (void)openApplicationWithBundleIdentifier:(NSString *)bundleID
                              configuration:(id)configuration completionHandler:(id)completionHandler;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface ULPAVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (id)attributeForKey:(NSString *)key;
- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
@end

static uint64_t ULPNowMs(void);
static void ULPManageMediaAlpha(UIView *view, BOOL dim, CGFloat dimAlpha);
static BOOL ULPShouldShowPlayer(void);
static void ULPStopPauseDecay(void);

static void ULPOpenNowPlayingSource(void) {
    ULPDiagnosticLog(@"Player card tapped");
    NSString *bundleID = nil;
    ULPSBApplication *app = nil;
    Class mediaClass = NSClassFromString(@"SBMediaController");
    if ([mediaClass respondsToSelector:@selector(sharedInstance)]) {
        id controller = [mediaClass sharedInstance];
        if ([controller respondsToSelector:@selector(nowPlayingApplication)])
            app = [controller nowPlayingApplication];
    }
    if (!app && gLastProcessID > 0) {
        Class controllerClass = NSClassFromString(@"SBApplicationController");
        if ([controllerClass respondsToSelector:@selector(sharedInstance)]) {
            id controller = [controllerClass sharedInstance];
            if ([controller respondsToSelector:@selector(applicationWithPid:)])
                app = [controller applicationWithPid:gLastProcessID];
        }
    }
    if (!bundleID.length && [app respondsToSelector:@selector(bundleIdentifier)])
        bundleID = app.bundleIdentifier;
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!bundleID.length || ![workspaceClass respondsToSelector:@selector(defaultWorkspace)]) {
        ULPDiagnosticLog([NSString stringWithFormat:@"Open source unavailable bundle=%@ workspace=%d",
            bundleID ?: @"", [workspaceClass respondsToSelector:@selector(defaultWorkspace)]]);
        return;
    }
    id workspace = [workspaceClass defaultWorkspace];
    if ([workspace respondsToSelector:@selector(openApplicationWithBundleIdentifier:configuration:completionHandler:)]) {
        ULPDiagnosticLog([NSString stringWithFormat:@"Open source requested bundle=%@", bundleID]);
        [workspace openApplicationWithBundleIdentifier:bundleID configuration:nil completionHandler:nil];
    } else if ([workspace respondsToSelector:@selector(openApplicationWithBundleID:)]) {
        BOOL accepted = [workspace openApplicationWithBundleID:bundleID];
        ULPDiagnosticLog([NSString stringWithFormat:@"Open source requested bundle=%@ accepted=%d",
            bundleID, accepted]);
    } else ULPDiagnosticLog(@"Open source selector unavailable");
}

static BOOL ULPIsActive(void) {
    return gEnabled && gCoverSheetVisible && !gCoverSheetAuthenticated && gHasNowPlaying &&
           ULPLifecycleIsVisible(&gLifecycle);
}

// Keep the date hidden while the display sleeps, so waking does not expose it
// for one frame before CoverSheet's visibility callback runs.
static BOOL ULPShouldHideDate(void) {
    return gEnabled && !gCoverSheetAuthenticated && gHasNowPlaying &&
           ULPLifecycleIsVisible(&gLifecycle);
}

static void ULPManageHidden(UIView *view, BOOL hide) {
    NSNumber *original = objc_getAssociatedObject(view, &kULPOriginalHiddenKey);
    if (hide) {
        if (!original)
            objc_setAssociatedObject(view, &kULPOriginalHiddenKey,
                                     @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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

static void ULPFadeDateViews(UIView *view, BOOL prepare) {
    if (!view) return;
    if ([NSStringFromClass(view.class) isEqualToString:@"SBFLockScreenDateView"]) {
        ULPManageMediaAlpha(view, prepare, 0);
        return;
    }
    for (UIView *child in view.subviews) ULPFadeDateViews(child, prepare);
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

static BOOL ULPShouldShowPlayer(void) {
    return gEnabled && gCoverSheetVisible && !gCoverSheetAuthenticated && gHasNowPlaying;
}

static void ULPRefreshPresentation(void) {
    BOOL active = ULPIsActive();
    BOOL showPlayer = ULPShouldShowPlayer();
    gPlayer.hidden = !showPlayer;
    if (gVolumeHUD.superview == gCoverSheetView) [gCoverSheetView bringSubviewToFront:gVolumeHUD];
    ULPManageMediaAlpha(gMediaView, showPlayer, 0.001);
    UIView *platter = gMediaView.superview.superview;
    if ([platter isKindOfClass:NSClassFromString(@"PLPlatterView")]) {
        PLPlatterView *nativePlatter = (PLPlatterView *)platter;
        if ([nativePlatter respondsToSelector:@selector(backgroundMaterialView)])
            ULPManageMediaAlpha(nativePlatter.backgroundMaterialView, showPlayer, 0);
        if ([nativePlatter respondsToSelector:@selector(mainOverlayView)])
            ULPManageMediaAlpha(nativePlatter.mainOverlayView, showPlayer, 0);
        if ([nativePlatter respondsToSelector:@selector(backgroundView)])
            ULPManageMediaAlpha(nativePlatter.backgroundView, showPlayer, 0);
    }
    ULPManageListPosition(gMediaView, showPlayer);
    BOOL revealDate = gSceneShown && !active && gCoverSheetVisible && !ULPShouldHideDate();
    if (revealDate) ULPFadeDateViews(gCoverSheetView, YES);
    ULPManageDateViews(gCoverSheetView, ULPShouldHideDate());
    if (active == gSceneShown) return;
    gSceneShown = active;
    NSUInteger generation = ++gSceneGeneration;
    if (active) {
        if (gFixedBackground.hidden) gFixedBackground.alpha = 0;
        if (gBackground.hidden) gBackground.alpha = 0;
        if (gVisualizer.hidden) gVisualizer.alpha = 0;
        gFixedBackground.hidden = NO;
        gBackground.hidden = NO;
        gVisualizer.hidden = !gVisualConfig.enabled;
    }
    NSTimeInterval duration = gCoverSheetVisible ? 0.42 : 0;
    if (!active) [gVolumeHUD dismissImmediately];
    [UIView animateWithDuration:duration delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        gFixedBackground.alpha = active ? 1 : 0;
        gBackground.alpha = active ? 1 : 0;
        gVisualizer.alpha = active ? 1 : 0;
        if (revealDate) ULPFadeDateViews(gCoverSheetView, NO);
    } completion:^(BOOL finished) {
        if (generation != gSceneGeneration) return;
        ULPManageDateViews(gCoverSheetView, ULPShouldHideDate());
        if (!gSceneShown) {
            gFixedBackground.hidden = YES;
            gBackground.hidden = YES;
            gVisualizer.hidden = YES;
            [gBackground resetMotion];
        }
    }];
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
    visualizer.visualConfig = gVisualConfig;
    [visualizer setArtwork:nil manualColor:gVisualManualColor];
    visualizer.hidden = YES;
    [self.view insertSubview:visualizer aboveSubview:background];
    gVisualizer = visualizer;
    ULPVolumeHUDView *volumeHUD = [[ULPVolumeHUDView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:volumeHUD];
    gVolumeHUD = volumeHUD;
    gSceneShown = NO;
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
        // Bounds/center remain stable while the HUD is sliding in or out.
        gVolumeHUD.bounds = CGRectMake(0, 0, 54, 56);
        gVolumeHUD.center = CGPointMake(33, height * .20);
        ULPRefreshPresentation();
    }
}

- (void)viewWillAppear:(BOOL)animated {
    gCoverSheetVisible = YES;
    gCoverSheetAuthenticated = [self respondsToSelector:@selector(authenticated)] &&
                               [self authenticated];
    ULPRefreshPresentation();
    %orig;
    ULPRefreshPresentation();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = NO;
    [gVolumeHUD dismissImmediately];
    ULPRefreshPresentation();
}

%end

%hook SBFLockScreenDateView

- (void)didMoveToWindow {
    %orig;
    if (gEnabled && self.window && ULPIsInsideCoverSheet(self))
        ULPManageHidden(self, ULPShouldHideDate());
}

- (void)layoutSubviews {
    %orig;
    if (gEnabled && ULPIsInsideCoverSheet(self))
        ULPManageHidden(self, ULPShouldHideDate());
}

%end

%hook NCNotificationListView

- (void)layoutSubviews {
    %orig;
    if (gEnabled && gMediaView)
        ULPManageListPosition(gMediaView, ULPShouldShowPlayer());
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
        replacement.openSourceHandler = ^{ ULPOpenNowPlayingSource(); };
        replacement.artworkHandler = ^(UIImage *artwork) {
            [gBackground setArtwork:artwork];
            [gFixedBackground setRenderedArtwork:gBackground.renderedArtwork];
            [gVisualizer setArtwork:artwork manualColor:gVisualManualColor];
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

static void ULPStopPauseDecay(void) {
    if (!gPauseDecayTimer) return;
    dispatch_source_cancel(gPauseDecayTimer);
    gPauseDecayTimer = nil;
}

static void ULPStartPauseDecay(void) {
    ULPStopPauseDecay();
    gPauseDecayStartMs = ULPNowMs();
    gPauseDecayTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                               dispatch_get_main_queue());
    dispatch_source_set_timer(gPauseDecayTimer, DISPATCH_TIME_NOW,
                              NSEC_PER_SEC / 30, NSEC_PER_SEC / 120);
    dispatch_source_set_event_handler(gPauseDecayTimer, ^{
        if (gLifecycle.presentation != ULPPlaybackPausePending || !gSceneShown) {
            ULPStopPauseDecay();
            return;
        }
        ULPMSH2FeatureFrame silence = {0};
        silence.featureMask = ULP_MSH2_SPECTRUM | ULP_MSH2_WAVEFORM;
        [gVisualizer updateAudio:silence zoomLevel:0];
        [gBackground setZoomLevel:0];
        [gFixedBackground setZoomLevel:0];
        uint64_t elapsed = ULPNowMs() - gPauseDecayStartMs;
        if ((elapsed > 800 && ![gVisualizer hasUnsettledPeakCaps]) || elapsed > 3000)
            ULPStopPauseDecay();
    });
    dispatch_resume(gPauseDecayTimer);
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
        BOOL enabled = ULPPreferenceBool(CFSTR("Enabled"), NO);
        if (!enabled) return;
        gEnabled = YES;

        ULPLifecycleInit(&gLifecycle, 15000);
        ULPSignalInit(&gSignal);
        gVisualConfig = ULPLoadVisualPreferences();
        gVisualManualColor = ULPLoadVisualManualColor();
        gVolumeObserver = [ULPVolumeObserver new];
        gVolumeObserver.lastVolume = [AVAudioSession sharedInstance].outputVolume;
        void *celestial = dlopen("/System/Library/PrivateFrameworks/Celestial.framework/Celestial",
                                 RTLD_LAZY | RTLD_LOCAL);
        NSString *__unsafe_unretained *categoryKey = celestial ?
            (NSString *__unsafe_unretained *)dlsym(celestial,
                "AVSystemController_CurrentlyActiveCategoryAttribute") : NULL;
        gActiveAudioCategoryKey = categoryKey ? *categoryKey : nil;
        NSString *__unsafe_unretained *volumeNotification = celestial ?
            (NSString *__unsafe_unretained *)dlsym(celestial,
                "AVSystemController_SystemVolumeDidChangeNotification") : NULL;
        @try {
            [[AVAudioSession sharedInstance] addObserver:gVolumeObserver
                forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:NULL];
        } @catch (NSException *exception) {
            ULPDiagnosticLog([NSString stringWithFormat:@"Volume observation unavailable: %@", exception.name]);
        }
        if (volumeNotification && *volumeNotification)
            [[NSNotificationCenter defaultCenter] addObserver:gVolumeObserver
                selector:@selector(volumeDidChange:)
                name:*volumeNotification object:nil];
        gVolumePollTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                   dispatch_get_main_queue());
        dispatch_source_set_timer(gVolumePollTimer, DISPATCH_TIME_NOW,
                                  NSEC_PER_SEC / 8, NSEC_PER_SEC / 40);
        dispatch_source_set_event_handler(gVolumePollTimer, ^{
            static BOOL tracking;
            static BOOL unavailableLogged;
            if (!ULPIsActive()) { tracking = NO; return; }
            Class controllerClass = NSClassFromString(@"AVSystemController");
            if (![controllerClass respondsToSelector:@selector(sharedAVSystemController)]) return;
            id controller = [controllerClass sharedAVSystemController];
            if (![controller respondsToSelector:@selector(getVolume:forCategory:)]) return;
            NSString *category = gActiveAudioCategoryKey &&
                [controller respondsToSelector:@selector(attributeForKey:)] ?
                [controller attributeForKey:gActiveAudioCategoryKey] : nil;
            if (![category isKindOfClass:NSString.class] || !category.length) category = @"Audio/Video";
            float volume = 0;
            BOOL available = [controller getVolume:&volume forCategory:category];
            if (!available && ![category isEqualToString:@"Audio/Video"])
                available = [controller getVolume:&volume forCategory:@"Audio/Video"];
            if (!available) {
                if (!unavailableLogged) ULPDiagnosticLog(@"Volume poll unavailable");
                unavailableLogged = YES;
                return;
            }
            unavailableLogged = NO;
            if (!tracking) { gVolumeObserver.lastVolume = volume; tracking = YES; }
            else [gVolumeObserver handleVolume:volume];
        });
        dispatch_resume(gVolumePollTimer);
        gSignal.visual.firstBand = gVisualConfig.firstBand;
        gSignal.visual.lastBand = gVisualConfig.lastBand;
        gSignal.zoom.firstBand = gVisualConfig.zoomFirstBand;
        gSignal.zoom.lastBand = gVisualConfig.zoomLastBand;
        if (gSignal.zoom.lastBand < gSignal.zoom.firstBand)
            gSignal.zoom.lastBand = gSignal.zoom.firstBand;
        gNowPlaying = [[ULPNowPlaying alloc] initWithHandler:^(ULPNowPlayingSnapshot *snapshot) {
            static BOOL lastArtwork;
            ULPPlaybackPresentation previous = gLifecycle.presentation;
            uint64_t now = ULPNowMs();
            BOOL sessionPresent = snapshot.title.length > 0 || snapshot.artist.length > 0 ||
                                  snapshot.artworkData.length > 0 || snapshot.artworkImage != nil ||
                                  snapshot.processID > 0;
            if (sessionPresent) gSessionLastSeenMs = now;
            gHasNowPlaying = sessionPresent || (gSessionLastSeenMs && now - gSessionLastSeenMs < 3000);
            gLastProcessID = snapshot.processID;
            ULPLifecycleSetPlaying(&gLifecycle, snapshot.playing, now);
            ULPLifecycleTick(&gLifecycle, now);
            if (previous == ULPPlaybackPlaying && gLifecycle.presentation == ULPPlaybackPausePending)
                ULPStartPauseDecay();
            if (gLifecycle.presentation != ULPPlaybackPausePending)
                ULPStopPauseDecay();
            BOOL hasArtwork = snapshot.artworkData.length > 0 || snapshot.artworkImage != nil;
            if (previous != gLifecycle.presentation || lastArtwork != hasArtwork) {
                ULPDiagnosticLog([NSString stringWithFormat:
                    @"NowPlaying state=%d pid=%d titlePresent=%d artworkPresent=%d duration=%.1f",
                    gLifecycle.presentation, snapshot.processID,
                    snapshot.title.length > 0, hasArtwork, snapshot.duration]);
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
                if (gLifecycle.presentation == ULPPlaybackPlaying && gVisualizer && !gVisualizer.hidden)
                    [gVisualizer updateAudio:frame zoomLevel:zoom];
                if (gLifecycle.presentation == ULPPlaybackPlaying && gBackground && !gBackground.hidden)
                    [gBackground setZoomLevel:zoom];
                if (gLifecycle.presentation == ULPPlaybackPlaying && gFixedBackground && !gFixedBackground.hidden)
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
