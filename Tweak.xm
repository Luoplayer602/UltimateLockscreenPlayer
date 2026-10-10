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
#import "Playback/ULPListPlacement.h"
#import "Visualization/ULPSignal.h"
#import "Visualization/ULPVisualPreferences.h"
#import "UI/ULPLockScreenView.h"
#import "UI/ULPArtworkImage.h"
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
static __weak UIScrollView *gManagedList;
static ULPNowPlayingSnapshot *gLastSnapshot;
static UIImage *gRenderedArtwork;
static NSData *gRenderedArtworkData;
static NSString *gArtworkTrack;
static BOOL gRepairingPlayer;
static uint64_t gLastPlayerScanMs;
static uint64_t gLastMissingHostLogMs;
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
static void ULPManageListPositionForList(UIScrollView *list, BOOL active);
static void ULPSetMediaDim(UIView *mediaView, BOOL dim);
static void ULPEnsurePlayerForMediaView(UIView *mediaView);
static void ULPCheckPlayer(BOOL force);

static void ULPCachePreviewArtwork(UIImage *artwork) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.luoplayer.ulp.preview-artwork", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSString *directory = @"/var/mobile/Library/Caches/ULP";
            NSString *path = [directory stringByAppendingPathComponent:@"preview-artwork.jpg"];
            if (!artwork) { [NSFileManager.defaultManager removeItemAtPath:path error:nil]; return; }
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
            [UIImageJPEGRepresentation(artwork, .75) writeToFile:path atomically:YES];
        }
    });
}

static void ULPReceiveArtwork(UIImage *artwork) {
    if (artwork == gRenderedArtwork) return;
    if (artwork && !ULPArtworkShouldUpgrade(artwork, gRenderedArtwork)) return;
    gRenderedArtwork = artwork;
    gRenderedArtworkData = nil;
    ULPCachePreviewArtwork(artwork);
    [gBackground setArtwork:artwork];
    [gFixedBackground setArtwork:artwork renderedArtwork:gBackground.renderedArtwork];
    [gVisualizer setArtwork:artwork manualColor:gVisualManualColor];
}

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

@interface ULPListPlacementState : NSObject
@property (nonatomic) ULPListPlacement placement;
@property (nonatomic) BOOL applying;
@end
@implementation ULPListPlacementState
@end

static void ULPSettleListPosition(UIScrollView *list) {
    if (!list) return;
    ULPListPlacementState *state = objc_getAssociatedObject(list, &kULPOriginalListInsetKey);
    if (!state || state.applying || list != gManagedList || !ULPShouldShowPlayer()) return;
    CGPoint offset = list.contentOffset;
    ULPListPlacement placement = state.placement;
    CGFloat target = ULPListPlacementRestingOffset(&placement, offset.y,
        list.dragging || list.decelerating || list.tracking);
    if (fabs(target - offset.y) < .5) return;
    state.applying = YES;
    list.contentOffset = CGPointMake(offset.x, target);
    state.applying = NO;
    ULPDiagnosticLog([NSString stringWithFormat:@"Player list settled offset=%.0f→%.0f base=%.0f applied=%.0f",
        offset.y, target, state.placement.baseTop, state.placement.appliedTop]);
}

static void ULPManageListPosition(UIView *mediaView, BOOL active) {
    UIScrollView *list = nil;
    for (UIView *ancestor = mediaView.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:NSClassFromString(@"NCNotificationListView")]) {
            list = (UIScrollView *)ancestor; break;
        }
    }
    if (gManagedList && gManagedList != list)
        ULPManageListPositionForList(gManagedList, NO);
    if (list) ULPManageListPositionForList(list, active);
    gManagedList = active ? list : nil;
}

static void ULPManageListPositionForList(UIScrollView *list, BOOL active) {
    if (!list || list.dragging || list.decelerating) return;
    ULPListPlacementState *state = objc_getAssociatedObject(list, &kULPOriginalListInsetKey);
    if (!state && !active) return;
    if (!state) {
        state = [ULPListPlacementState new];
        objc_setAssociatedObject(list, &kULPOriginalListInsetKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    ULPListPlacement placement = state.placement;
    UIEdgeInsets inset = list.contentInset;
    CGFloat shift = MIN(120, CGRectGetHeight(list.bounds) * .18);
    if (active && placement.active && fabs(shift - placement.shift) < .5) {
        ULPSettleListPosition(list);
        return;
    }
    if (!active && !placement.active) return;
    CGFloat target = active ? ULPListPlacementBegin(&placement, inset.top, shift) : ULPListPlacementEnd(&placement);
    state.placement = placement;
    CGPoint offset = list.contentOffset;
    BOOL atTop = fabs(offset.y + inset.top) < 2;
    inset.top = target;
    state.applying = YES;
    list.contentInset = inset;
    state.applying = NO;
    list.contentOffset = atTop ? CGPointMake(offset.x, -target) : offset;
    ULPDiagnosticLog([NSString stringWithFormat:@"Player list placement active=%d base=%.0f applied=%.0f",
        active, placement.baseTop, placement.appliedTop]);
}

static BOOL ULPShouldShowPlayer(void) {
    return gEnabled && gCoverSheetVisible && !gCoverSheetAuthenticated && gHasNowPlaying;
}

static void ULPRefreshPresentation(void) {
    BOOL active = ULPIsActive();
    BOOL showPlayer = ULPShouldShowPlayer();
    if (gVolumeHUD.superview == gCoverSheetView) [gCoverSheetView bringSubviewToFront:gVolumeHUD];
    BOOL attached = gCoverSheetView && gPlayer && gPlayer.superview && gMediaView.window &&
                    gPlayer.bounds.size.height >= 80 && [gPlayer isDescendantOfView:gCoverSheetView];
    gPlayer.hidden = !(showPlayer && attached);
    ULPSetMediaDim(gMediaView, showPlayer && attached);
    ULPManageListPosition(gMediaView, showPlayer && attached);
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

static void ULPSetMediaDim(UIView *mediaView, BOOL dim) {
    ULPManageMediaAlpha(mediaView, dim, .001);
    for (UIView *ancestor = mediaView.superview; ancestor && ancestor != gCoverSheetView;
         ancestor = ancestor.superview) {
        if (![ancestor isKindOfClass:NSClassFromString(@"PLPlatterView")]) continue;
        PLPlatterView *platter = (PLPlatterView *)ancestor;
        if ([platter respondsToSelector:@selector(backgroundMaterialView)])
            ULPManageMediaAlpha(platter.backgroundMaterialView, dim, 0);
        if ([platter respondsToSelector:@selector(mainOverlayView)])
            ULPManageMediaAlpha(platter.mainOverlayView, dim, 0);
        if ([platter respondsToSelector:@selector(backgroundView)])
            ULPManageMediaAlpha(platter.backgroundView, dim, 0);
        break;
    }
}

static UIView *ULPPlayerHost(UIView *mediaView) {
    if (!gCoverSheetView || !mediaView.window || mediaView.hidden ||
        ![mediaView isDescendantOfView:gCoverSheetView]) return nil;
    for (UIView *view = mediaView.superview; view && view != gCoverSheetView; view = view.superview) {
        if (view.hidden) return nil;
        if ([view isKindOfClass:NSClassFromString(@"PLPlatterCustomContentView")]) return view;
    }
    return nil;
}

static UIView *ULPFindNativeMedia(UIView *root) {
    if (root.hidden || [root isKindOfClass:ULPLockScreenView.class]) return nil;
    if ([root isKindOfClass:NSClassFromString(@"CSMediaControlsView")] && ULPPlayerHost(root)) return root;
    for (UIView *child in root.subviews.reverseObjectEnumerator) {
        UIView *found = ULPFindNativeMedia(child);
        if (found) return found;
    }
    return nil;
}

static void ULPEnsurePlayerForMediaView(UIView *mediaView) {
    if (!gEnabled || gRepairingPlayer) return;
    UIView *host = ULPPlayerHost(mediaView);
    if (!host || host.bounds.size.width < 120 || host.bounds.size.height < 80) return;
    if (gMediaView && mediaView != gMediaView && ULPPlayerHost(gMediaView) &&
        ULPFindNativeMedia(gCoverSheetView) != mediaView) return;
    gRepairingPlayer = YES;
    // One replacement per current host. The association survives a native
    // controller removing its sibling views during a session restart.
    ULPLockScreenView *player = objc_getAssociatedObject(host, &kULPReplacementKey);
    BOOL created = !player;
    if (!player) {
        player = [[ULPLockScreenView alloc] initWithFrame:host.bounds];
        player.hidden = YES;
        player.commandHandler = ^(NSInteger command) { [gNowPlaying sendCommand:command]; };
        player.openSourceHandler = ^{ ULPOpenNowPlayingSource(); };
        player.diagnosticHandler = ^(NSString *message) { ULPDiagnosticLog(message); };
        __weak ULPLockScreenView *weakPlayer = player;
        player.artworkHandler = ^(UIImage *artwork) {
            if (weakPlayer != gPlayer || !artwork) return;
            if (artwork != gRenderedArtwork)
                ULPDiagnosticLog([NSString stringWithFormat:@"Player artwork recovered source=%@ pid=%d",
                    (gLastSnapshot.artworkData.length || gLastSnapshot.artworkImage) ? @"snapshot" : @"native-host",
                    gLastSnapshot.processID]);
            ULPReceiveArtwork(artwork);
        };
        objc_setAssociatedObject(host, &kULPReplacementKey, player, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL changedHost = mediaView != gMediaView || player != gPlayer;
    if (changedHost) {
        ULPSetMediaDim(gMediaView, NO);
        if (gPlayer != player) gPlayer.hidden = YES;
    }
    gMediaView = mediaView; gPlayer = player;
    BOOL reattached = player.superview != host;
    if (reattached) [host addSubview:player];
    for (UIView *child in host.subviews.copy)
        if (child != player && [child isKindOfClass:ULPLockScreenView.class]) [child removeFromSuperview];
    BOOL resized = !CGRectEqualToRect(player.frame, host.bounds);
    if (resized) { player.frame = host.bounds; [player setNeedsLayout]; }
    if (player.alpha != 1) player.alpha = 1;
    BOOL componentsRepaired = [player repairComponents];
    if (host.subviews.lastObject != player) [host bringSubviewToFront:player];
    if ((created || reattached || changedHost) && gLastSnapshot)
        [player updateNowPlaying:gLastSnapshot];
    if (created || reattached || changedHost || resized || componentsRepaired)
        ULPDiagnosticLog([NSString stringWithFormat:
            @"Player repair created=%d reattached=%d hostChanged=%d resized=%d components=%d host=%p media=%p size=%.0fx%.0f",
            created, reattached, changedHost, resized, componentsRepaired, host, mediaView,
            host.bounds.size.width, host.bounds.size.height]);
    gRepairingPlayer = NO;
}

static void ULPCheckPlayer(BOOL force) {
    if (!gEnabled || gRepairingPlayer || !gCoverSheetVisible || !gCoverSheetView.window) return;
    UIView *host = ULPPlayerHost(gMediaView);
    if (host) ULPEnsurePlayerForMediaView(gMediaView);
    uint64_t now = ULPNowMs();
    BOOL healthy = host && gPlayer.superview == host && gPlayer.bounds.size.height >= 80;
    if (force || (!healthy && now - gLastPlayerScanMs >= 2000)) {
        gLastPlayerScanMs = now;
        UIView *media = ULPFindNativeMedia(gCoverSheetView);
        if (media) ULPEnsurePlayerForMediaView(media);
        healthy = gPlayer && gPlayer.superview == ULPPlayerHost(gMediaView) && gPlayer.bounds.size.height >= 80;
    }
    if (force || (gHasNowPlaying && !healthy && now - gLastMissingHostLogMs >= 5000)) {
        gLastMissingHostLogMs = now;
        ULPDiagnosticLog([NSString stringWithFormat:@"Player audit healthy=%d media=%p player=%p parent=%p window=%d pid=%d artwork=%d",
            healthy, gMediaView, gPlayer, gPlayer.superview, gPlayer.window != nil,
            gLastSnapshot.processID, gPlayer.currentArtwork != nil]);
    }
}

%hook CSCoverSheetViewController

- (void)viewDidLoad {
    %orig;
    if (!gEnabled) return;
    ULPBackgroundView *fixedBackground = [[ULPBackgroundView alloc] initWithFrame:self.view.bounds];
    fixedBackground.visualConfig = gVisualConfig;
    fixedBackground.hidden = YES;
    [self.view insertSubview:fixedBackground atIndex:0];
    gFixedBackground = fixedBackground;
    ULPBackgroundView *background = [[ULPBackgroundView alloc] initWithFrame:self.view.bounds];
    background.visualConfig = gVisualConfig;
    background.hidden = YES;
    [self.view insertSubview:background aboveSubview:fixedBackground];
    [background attachSwipeRecognitionToView:self.view];
    gBackground = background;
    ULPVisualizerView *visualizer = [[ULPVisualizerView alloc] initWithFrame:self.view.bounds];
    visualizer.visualConfig = gVisualConfig;
    visualizer.playbackActive = gLastSnapshot.playing;
    [visualizer setArtwork:nil manualColor:gVisualManualColor];
    visualizer.hidden = YES;
    [self.view insertSubview:visualizer aboveSubview:background];
    gVisualizer = visualizer;
    ULPVolumeHUDView *volumeHUD = [[ULPVolumeHUDView alloc] initWithFrame:CGRectZero];
    [self.view addSubview:volumeHUD];
    gVolumeHUD = volumeHUD;
    gSceneShown = NO;
    gCoverSheetView = self.view;
    if (gRenderedArtwork) {
        [background setArtwork:gRenderedArtwork];
        [fixedBackground setArtwork:gRenderedArtwork renderedArtwork:background.renderedArtwork];
        [visualizer setArtwork:gRenderedArtwork manualColor:gVisualManualColor];
    }
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
        CGRect viewport = CGRectMake(0, overscan, width, height);
        gFixedBackground.contentViewport = viewport;
        gBackground.contentViewport = viewport;
        gVisualizer.frame = self.view.bounds;
        // Bounds/center remain stable while the HUD is sliding in or out.
        gVolumeHUD.bounds = CGRectMake(0, 0, 54, 56);
        gVolumeHUD.center = CGPointMake(33, height * .20);
        ULPCheckPlayer(NO);
        ULPRefreshPresentation();
    }
}

- (void)viewWillAppear:(BOOL)animated {
    gCoverSheetVisible = YES;
    gCoverSheetAuthenticated = [self respondsToSelector:@selector(authenticated)] &&
                               [self authenticated];
    ULPRefreshPresentation();
    %orig;
    ULPDiagnosticLog(@"CoverSheet appearing; checking native media host");
    ULPCheckPlayer(YES);
    [gNowPlaying requestRefresh];
    ULPRefreshPresentation();
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    gCoverSheetVisible = NO;
    ULPDiagnosticLog(@"CoverSheet disappeared; keeping data observers active");
    [gVolumeHUD dismissImmediately];
    ULPRefreshPresentation();
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!gEnabled || gCoverSheetView != self.view) return;
    ULPSettleListPosition(gManagedList);
    ULPDiagnosticLog([NSString stringWithFormat:@"CoverSheet settled list offset=%.0f inset=%.0f dragging=%d decelerating=%d",
        gManagedList.contentOffset.y, gManagedList.contentInset.top,
        gManagedList.dragging, gManagedList.decelerating]);
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

- (void)setContentOffset:(CGPoint)offset {
    ULPListPlacementState *state = objc_getAssociatedObject(self, &kULPOriginalListInsetKey);
    if (gEnabled && state && !state.applying && self == gManagedList && ULPShouldShowPlayer()) {
        ULPListPlacement placement = state.placement;
        offset.y = ULPListPlacementRestingOffset(&placement, offset.y,
            self.dragging || self.decelerating || self.tracking);
    }
    %orig(offset);
}

- (void)setContentOffset:(CGPoint)offset animated:(BOOL)animated {
    ULPListPlacementState *state = objc_getAssociatedObject(self, &kULPOriginalListInsetKey);
    if (gEnabled && state && !state.applying && self == gManagedList && ULPShouldShowPlayer()) {
        ULPListPlacement placement = state.placement;
        offset.y = ULPListPlacementRestingOffset(&placement, offset.y,
            self.dragging || self.decelerating || self.tracking);
    }
    %orig(offset, animated);
}

- (void)setContentInset:(UIEdgeInsets)inset {
    ULPListPlacementState *state = objc_getAssociatedObject(self, &kULPOriginalListInsetKey);
    if (!gEnabled || !state || state.applying || !state.placement.active) {
        %orig(inset);
        return;
    }
    if (self != gManagedList || !ULPShouldShowPlayer()) {
        ULPListPlacement old = state.placement;
        CGFloat baseline = ULPListPlacementEnd(&old);
        if (fabs(inset.top - state.placement.appliedTop) < .5) inset.top = baseline;
        state.placement = old;
        %orig(inset);
        return;
    }
    ULPListPlacement placement = state.placement;
    double base = placement.baseTop;
    inset.top = ULPListPlacementObserve(&placement, inset.top);
    state.placement = placement;
    UIEdgeInsets current = self.contentInset;
    if (fabs(current.top - inset.top) < .5 && fabs(current.left - inset.left) < .5 &&
        fabs(current.bottom - inset.bottom) < .5 && fabs(current.right - inset.right) < .5) return;
    BOOL atTop = fabs(self.contentOffset.y + current.top) < 2;
    %orig(inset);
    if (atTop && !self.dragging && !self.decelerating)
        self.contentOffset = CGPointMake(self.contentOffset.x, -inset.top);
    if (fabs(base - placement.baseTop) > .5)
        ULPDiagnosticLog([NSString stringWithFormat:@"Player list system layout changed base=%.0f→%.0f applied=%.0f",
            base, placement.baseTop, placement.appliedTop]);
}

- (void)layoutSubviews {
    %orig;
    if (gEnabled && gMediaView)
        ULPManageListPosition(gMediaView, ULPShouldShowPlayer() && gPlayer.superview && gPlayer.bounds.size.height >= 80);
    if (gEnabled) ULPSettleListPosition(self);
}

%end

%hook PLPlatterCustomContentView
- (void)layoutSubviews {
    %orig;
    if (!gEnabled || gRepairingPlayer || !gCoverSheetView || ![self isDescendantOfView:gCoverSheetView]) return;
    for (UIView *child in self.subviews)
        if ([child isKindOfClass:NSClassFromString(@"CSMediaControlsView")]) {
            ULPEnsurePlayerForMediaView(child); break;
        }
}
%end

%hook CSMediaControlsView
- (void)didMoveToWindow {
    %orig;
    if (!gEnabled) return;
    if (self.window && gCoverSheetView && [self isDescendantOfView:gCoverSheetView]) {
        ULPEnsurePlayerForMediaView(self);
        [gNowPlaying requestRefresh];
    } else if (self == gMediaView) {
        ULPDiagnosticLog(@"Native media host left window; rechecking current host");
        dispatch_async(dispatch_get_main_queue(), ^{ ULPCheckPlayer(YES); ULPRefreshPresentation(); });
    }
}
- (void)layoutSubviews {
    %orig;
    if (gEnabled) {
        ULPEnsurePlayerForMediaView(self);
        if (self == gMediaView) ULPRefreshPresentation();
    }
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
        ULPCachePreviewArtwork(nil);
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
            int oldPID = gLastSnapshot.processID;
            gLastSnapshot = snapshot;
            gVisualizer.playbackActive = snapshot.playing;
            ULPPlaybackPresentation previous = gLifecycle.presentation;
            uint64_t now = ULPNowMs();
            BOOL sessionPresent = snapshot.sessionPresent;
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
            if (![gArtworkTrack isEqualToString:snapshot.trackIdentifier ?: @""]) {
                [gVisualizer resetTrail];
                [gVisualizer resetCoverMotion];
                gArtworkTrack = snapshot.trackIdentifier ?: @"";
                ULPReceiveArtwork(nil);
            }
            if (oldPID != snapshot.processID) {
                [gVisualizer resetTrail];
                [gVisualizer resetCoverMotion];
            }
            UIImage *artwork = snapshot.artworkImage;
            if (!artwork && snapshot.artworkData.length)
                artwork = [gRenderedArtworkData isEqualToData:snapshot.artworkData] ? gRenderedArtwork :
                          [UIImage imageWithData:snapshot.artworkData];
            if (artwork) {
                ULPReceiveArtwork(artwork);
                gRenderedArtworkData = snapshot.artworkData;
                snapshot.artworkImage = gRenderedArtwork;
            }
            if (!snapshot.artworkImage && gRenderedArtwork) snapshot.artworkImage = gRenderedArtwork;
            ULPCheckPlayer(oldPID != snapshot.processID);
            [gPlayer updateNowPlaying:snapshot];
            ULPRefreshPresentation();
        }];
        gNowPlaying.diagnosticHandler = ^(NSString *message) { ULPDiagnosticLog(message); };
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
                @"MSH2 sampleRate=%.0f rms=%.3f peak=%.3f spectrum0=%.3f visual=%.3f zoom=%.3f status=0x%x bands8=%.3f bands16=%.3f bands32=%.3f bands48=%.3f bands63=%.3f",
                frame.sampleRate, frame.rms, frame.peak, frame.spectrum[0],
                gSignal.visualLevel, gSignal.zoomLevel, frame.status,
                frame.spectrum[8], frame.spectrum[16], frame.spectrum[32], frame.spectrum[48], frame.spectrum[63]]);
        } statusHandler:^(NSString *message) {
            ULPDiagnosticLog(message);
        }];
        [gAudioProbe start];
        ULPDiagnosticLog(@"MSH2 probe started");
    }
}
