#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <string.h>
#import <substrate.h>

// Observe system catalog callbacks and request via an independent catalog; no image files or UI mutations.
// All UIKit/runtime reads occur on SpringBoard's main queue.
static const char *logPath = "/var/mobile/Library/Logs/ULP-ArtworkProbe.log";
static NSMutableSet<NSString *> *seenClasses;
static NSMutableDictionary<NSString *, NSString *> *lastImages;
static NSMutableSet<NSString *> *seenObjects;
static NSMutableSet<NSString *> *seenEdges;
static NSString *lastInfo;
static dispatch_source_t probeTimer;
static unsigned tick;
static BOOL infoPending;
static BOOL objectImageCompletionVerified;
static unsigned requestRoute;
static BOOL configurationHasBool;
static __thread BOOL issuingRequest;
static NSMutableDictionary<NSNumber *, id> *pendingDestinations;
static void InstallCatalogHooks(void);
static NSMutableSet<NSString *> *requestedCatalogs;
static NSMutableDictionary<NSNumber *, id> *pendingCatalogs;
static unsigned requestNumber;

@interface ULPProbeCatalog : NSObject
- (instancetype)initWithToken:(id)token dataSource:(id)source;
- (void)setFittingSize:(CGSize)size;
- (void)setDestinationScale:(double)scale;
- (void)requestImageWithCompletionHandler:(void (^)(id result))completion;
- (void)requestImageWithCompletion:(void (^)(id result))completion;
- (void)setDestination:(id)destination configurationBlock:(id)block;
- (void)setDestination:(id)destination progressiveConfigurationBlock:(id)block;
@end

static void TryIndependentCatalog(UIView *view, NSString *path);
typedef void (*GetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
static GetInfo getInfo;
static void *mediaRemote;

static void Log(NSString *message) {
    int fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    struct stat status;
    if (fstat(fd, &status) == 0 && status.st_size < 4 * 1024 * 1024) {
        NSData *data = [[NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, message]
            dataUsingEncoding:NSUTF8StringEncoding];
        (void)write(fd, data.bytes, data.length);
    }
    close(fd);
}

static BOOL Related(NSString *name) {
    NSString *lower = name.lowercaseString;
    return [lower containsString:@"artwork"] || [lower containsString:@"nowplaying"] ||
        [lower containsString:@"contentitem"] || [lower containsString:@"mediacontrol"] ||
        [name hasPrefix:@"MRU"];
}

static NSString *Dimensions(UIImage *image) {
    if (!image) return @"none";
    CGImageRef cg = image.CGImage;
    return [NSString stringWithFormat:@"pixels=%zux%zu points=%.1fx%.1f scale=%.1f orientation=%ld",
        cg ? CGImageGetWidth(cg) : 0, cg ? CGImageGetHeight(cg) : 0,
        image.size.width, image.size.height, image.scale, (long)image.imageOrientation];
}

static void DescribeClass(Class cls) {
    if (!cls) return;
    NSString *name = NSStringFromClass(cls);
    if (!Related(name) || [seenClasses containsObject:name]) return;
    [seenClasses addObject:name];
    Log([NSString stringWithFormat:@"CLASS %@ super=%@", name, NSStringFromClass(class_getSuperclass(cls))]);
    unsigned count = 0;
    for (unsigned kind = 0; kind < 2; ++kind) {
        Method *methods = class_copyMethodList(kind ? object_getClass(cls) : cls, &count);
        for (unsigned i = 0; i < count; ++i) {
            NSString *selector = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = selector.lowercaseString;
            if ([lower containsString:@"artwork"] || [lower containsString:@"image"] ||
                [lower containsString:@"request"] || [lower containsString:@"contentitem"] ||
                [lower containsString:@"playerpath"] || [lower containsString:@"identifier"] ||
                [lower containsString:@"size"] || [lower containsString:@"datasource"])
                Log([NSString stringWithFormat:@"METHOD %@ %c%@ encoding=%s", name, kind ? '+' : '-', selector, method_getTypeEncoding(methods[i])]);
        }
        free(methods);
    }
    Ivar *ivars = class_copyIvarList(cls, &count);
    for (unsigned i = 0; i < count; ++i)
        Log([NSString stringWithFormat:@"IVAR %@ %s type=%s", name, ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i])]);
    free(ivars);
}

static void DescribeProviderObjectsAtDepth(id object, unsigned depth) {
    if (!object || depth > 3) return;
    NSString *objectKey = [NSString stringWithFormat:@"%p:%@", object, NSStringFromClass([object class])];
    if ([seenObjects containsObject:objectKey]) return;
    [seenObjects addObject:objectKey];
    // Only declared object ivars; never message an unknown private selector.
    unsigned total = 0;
    for (Class cls = [object class]; cls && Related(NSStringFromClass(cls)) && total < 60;
         cls = class_getSuperclass(cls)) {
        DescribeClass(cls);
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned i = 0; i < count && total < 60; ++i, ++total) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            if (!type || type[0] != '@') continue;
            NSString *name = @(ivar_getName(ivars[i]));
            NSString *lower = name.lowercaseString;
            if (![lower containsString:@"artwork"] && ![lower containsString:@"controller"] &&
                ![lower containsString:@"request"] && ![lower containsString:@"provider"] &&
                ![lower containsString:@"contentitem"] && ![lower containsString:@"catalog"] &&
                ![lower containsString:@"datasource"] && ![lower containsString:@"response"]) continue;
            id value = object_getIvar(object, ivars[i]);
            if (!value) continue;
            NSString *edge = [NSString stringWithFormat:@"%p:%@:%p", object, name, value];
            if (![seenEdges containsObject:edge]) {
                [seenEdges addObject:edge];
                Log([NSString stringWithFormat:@"OBJECT owner=%@ ivar=%@ class=%@",
                    NSStringFromClass([object class]), name, NSStringFromClass([value class])]);
            }
            DescribeClass([value class]);
            if (Related(NSStringFromClass([value class]))) DescribeProviderObjectsAtDepth(value, depth + 1);
            if ([value isKindOfClass:UIImage.class])
                Log([NSString stringWithFormat:@"OBJECT-IMAGE owner=%@ ivar=%@ %@",
                    NSStringFromClass([object class]), name, Dimensions(value)]);
        }
        free(ivars);
    }
}

static void DescribeProviderObjects(id object) { DescribeProviderObjectsAtDepth(object, 0); }

static void ScanView(UIView *view, NSString *path, unsigned depth, unsigned *count) {
    if (!view || depth > 32 || ++*count > 2500) return;
    NSString *name = NSStringFromClass(view.class);
    NSString *next = [path stringByAppendingFormat:@"/%@", name];
    BOOL relevant = Related(next) || [next containsString:@"ULPLockScreenView"] ||
        [next containsString:@"ULPBackgroundView"];
    if (relevant && [view isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)view).image;
        if (image) {
            NSString *key = [NSString stringWithFormat:@"%p", view];
            NSString *state = [NSString stringWithFormat:@"path=%@ image=%p %@ frame=%@ hidden=%d window=%d",
                next, image, Dimensions(image), NSStringFromCGRect(view.frame), view.hidden, view.window != nil];
            NSString *fingerprint = [NSString stringWithFormat:@"%@ %p %@ hidden=%d", next, image, Dimensions(image), view.hidden];
            if (![lastImages[key] isEqual:fingerprint]) {
                lastImages[key] = fingerprint;
                Log([@"VIEW-IMAGE " stringByAppendingString:state]);
                UIView *ancestor = view.superview;
                for (unsigned i = 0; ancestor && i < 5; ++i, ancestor = ancestor.superview)
                    if (Related(NSStringFromClass(ancestor.class))) DescribeProviderObjects(ancestor);
                UIResponder *responder = view;
                for (unsigned i = 0; responder && i < 14; ++i, responder = responder.nextResponder) {
                    if ([responder isKindOfClass:UIViewController.class] && Related(NSStringFromClass(responder.class)))
                        DescribeProviderObjects(responder);
                }
            }
        }
    }
    if ([name isEqualToString:@"MRUArtworkView"] &&
        [path containsString:@"SBCoverSheetWindow"])
        TryIndependentCatalog(view, next);
    if (Related(name)) DescribeClass(view.class);
    for (UIView *child in view.subviews) ScanView(child, next, depth + 1, count);
}

static id InfoValue(NSDictionary *info, const char *symbol) {
    CFStringRef *key = mediaRemote ? (CFStringRef *)dlsym(mediaRemote, symbol) : NULL;
    return key && *key ? info[(__bridge NSString *)*key] : nil;
}

static void RecordInfo(NSDictionary *info) {
    if (![info isKindOfClass:NSDictionary.class]) return;
    id data = InfoValue(info, "kMRMediaRemoteNowPlayingInfoArtworkData");
    unsigned long width = 0, height = 0;
    if ([data isKindOfClass:NSData.class] && [data length]) {
        CGImageSourceRef image = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
        if (image) {
            NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(image, 0, NULL));
            width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedLongValue];
            height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedLongValue];
            CFRelease(image);
        }
    }
    NSString *state = [NSString stringWithFormat:@"INFO source=MediaRemote title=%@ artist=%@ pixels=%lux%lu bytes=%lu",
        InfoValue(info, "kMRMediaRemoteNowPlayingInfoTitle") ?: @"",
        InfoValue(info, "kMRMediaRemoteNowPlayingInfoArtist") ?: @"", width, height,
        (unsigned long)([data isKindOfClass:NSData.class] ? [data length] : 0)];
    if (![lastInfo isEqual:state]) { lastInfo = state; Log(state); }
}

__attribute__((constructor)) static void StartProbe(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        seenClasses = [NSMutableSet set];
        seenObjects = [NSMutableSet set];
        seenEdges = [NSMutableSet set];
        requestedCatalogs = [NSMutableSet set];
        pendingCatalogs = [NSMutableDictionary dictionary];
        pendingDestinations = [NSMutableDictionary dictionary];
        // Install after explicitly loading the framework, rather than relying
        // on class availability during Substrate's initial dylib load.
        dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", RTLD_LAZY);
        InstallCatalogHooks();
        lastImages = [NSMutableDictionary dictionary];
        mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (mediaRemote) getInfo = (GetInfo)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo");
        Log([NSString stringWithFormat:@"START artwork probe v4 getInfo=%d duration=12min interval=4s", getInfo != NULL]);
        for (NSString *name in @[@"MPUNowPlayingController", @"MRUArtworkView", @"MRUArtworkController",
            @"MRNowPlayingRequest", @"MRArtworkRequest", @"MRContentItem", @"MRUContentItem",
            @"MRUControlCenterViewController", @"MRUNowPlayingViewController",
            @"MPArtworkCatalog", @"MRUEndpointMetadataController", @"MRNowPlayingPlayerResponse"])
            DescribeClass(NSClassFromString(name));
        probeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(probeTimer, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC),
            4 * NSEC_PER_SEC, NSEC_PER_SEC / 4);
        dispatch_source_set_event_handler(probeTimer, ^{
            @autoreleasepool {
                if (tick < 5) InstallCatalogHooks();
                if (++tick > 180) {
                    Log(@"STOP 12-minute sampling completed; remove probe package after collection");
                    dispatch_source_cancel(probeTimer); probeTimer = nil; return;
                }
                [seenObjects removeAllObjects];
                unsigned count = 0;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                for (UIWindow *window in UIApplication.sharedApplication.windows)
                    ScanView(window, @"", 0, &count);
#pragma clang diagnostic pop
                if (tick % 5 == 1) Log([NSString stringWithFormat:@"SAMPLE tick=%u views=%u", tick, count]);
                if (getInfo && !infoPending) {
                    infoPending = YES;
                    getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef raw) {
                        infoPending = NO;
                        RecordInfo((__bridge NSDictionary *)raw);
                    });
                }
            }
        });
        dispatch_resume(probeTimer);
    });
}


static id ObjectIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable([object class], name) : NULL;
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static BOOL HasSignature(id object, SEL selector, const char *result, unsigned count) {
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    return sig && sig.numberOfArguments == count && !strcmp(sig.methodReturnType, result);
}

static void TryIndependentCatalog(UIView *view, NSString *path) {
    if (!objectImageCompletionVerified || requestNumber >= 8 || pendingCatalogs.count) return;
    id sourceCatalog = ObjectIvar(view, "_catalog");
    id token = ObjectIvar(sourceCatalog, "_token");
    id source = ObjectIvar(sourceCatalog, "_dataSource");
    if (!token || !source || ![NSStringFromClass([source class]) isEqualToString:@"MPCMediaRemoteArtworkRemoteDataSource"]) return;
    NSString *key = [NSString stringWithFormat:@"%p:%p", token, source];
    if ([requestedCatalogs containsObject:key]) return;
    Class cls = NSClassFromString(@"MPArtworkCatalog");
    ULPProbeCatalog *allocated = [cls alloc];
    SEL selected = requestRoute == 1 ? @selector(requestImageWithCompletionHandler:) :
        requestRoute == 2 ? @selector(requestImageWithCompletion:) :
        requestRoute == 3 ? @selector(setDestination:configurationBlock:) :
                           @selector(setDestination:progressiveConfigurationBlock:);
    if (!HasSignature(allocated, @selector(initWithToken:dataSource:), "@", 4) ||
        !HasSignature(allocated, @selector(setFittingSize:), "v", 3) ||
        !HasSignature(allocated, @selector(setDestinationScale:), "v", 3) ||
        !HasSignature(allocated, selected, "v", requestRoute < 3 ? 3 : 4)) {
        [requestedCatalogs addObject:key];
        Log(@"REQUEST-SKIP catalog signatures not available"); return;
    }
    NSMethodSignature *sizeSignature = [allocated methodSignatureForSelector:@selector(setFittingSize:)];
    NSMethodSignature *scaleSignature = [allocated methodSignatureForSelector:@selector(setDestinationScale:)];
    if (strcmp([sizeSignature getArgumentTypeAtIndex:2], @encode(CGSize)) ||
        strcmp([scaleSignature getArgumentTypeAtIndex:2], @encode(double))) {
        Log(@"REQUEST-SKIP size/scale ABI mismatch"); return;
    }
    [requestedCatalogs addObject:key];
    @try {
        // Clone the token/data source into an independent catalog: original fit,
        // requesting context and destination remain unchanged.
        ULPProbeCatalog *catalog = [allocated initWithToken:token dataSource:source];
        if (!catalog) { Log(@"REQUEST-SKIP init returned nil"); return; }
        [catalog setDestinationScale:1];
        [catalog setFittingSize:CGSizeMake(750, 750)];
        NSNumber *number = @(++requestNumber);
        pendingCatalogs[number] = catalog;
        Log([NSString stringWithFormat:@"REQUEST-BEGIN id=%@ source=lockscreen target=750x750 route=%u provider=%@ metadata=%@",
            number, requestRoute, NSStringFromClass([source class]), lastInfo ?: @"not-yet-read"]);
        void (^resultHandler)(id, BOOL) = ^(id result, BOOL finalResult) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!pendingCatalogs[number]) { Log([NSString stringWithFormat:@"REQUEST-LATE id=%@ ignored", number]); return; }
                Log([NSString stringWithFormat:@"REQUEST-RESULT id=%@ class=%@ %@ final=%d metadataNow=%@",
                    number, result ? NSStringFromClass([result class]) : @"nil",
                    [result isKindOfClass:UIImage.class] ? Dimensions(result) : @"not-UIImage", finalResult,
                    lastInfo ?: @"not-yet-read"]);
                CGImageRef cg = [result isKindOfClass:UIImage.class] ? [(UIImage *)result CGImage] : NULL;
                BOOL reachedTarget = cg && MAX(CGImageGetWidth(cg), CGImageGetHeight(cg)) >= 750;
                if (finalResult || reachedTarget) {
                    [pendingCatalogs removeObjectForKey:number];
                    [pendingDestinations removeObjectForKey:number];
                }
            });
        };
        issuingRequest = YES;
        if (requestRoute == 1) [catalog requestImageWithCompletionHandler:^(id image) { resultHandler(image, YES); }];
        else if (requestRoute == 2) [catalog requestImageWithCompletion:^(id image) { resultHandler(image, YES); }];
        else {
            NSObject *destination = [NSObject new];
            pendingDestinations[number] = destination;
            id block = configurationHasBool ? (id)^(id target, id image, BOOL best) { resultHandler(image, best); } :
                                               (id)^(id target, id image) { resultHandler(image, NO); };
            if (requestRoute == 3) [catalog setDestination:destination configurationBlock:block];
            else [catalog setDestination:destination progressiveConfigurationBlock:block];
        }
        issuingRequest = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (pendingCatalogs[number]) {
                Log([NSString stringWithFormat:@"REQUEST-TIMEOUT id=%@", number]);
                [pendingCatalogs removeObjectForKey:number];
                [pendingDestinations removeObjectForKey:number];
            }
        });
    } @catch (NSException *exception) {
        Log([NSString stringWithFormat:@"REQUEST-EXCEPTION %@ %@", exception.name, exception.reason]);
        [pendingCatalogs removeAllObjects];
        [pendingDestinations removeAllObjects];
    } @finally { issuingRequest = NO; }
}

// Inspect the callback ABI of an actual system request before invoking this
// selector ourselves. Do not wrap, replace, or call the system completion.
struct ProbeBlockLiteral {
    void *isa;
    int flags;
    int reserved;
    void *invoke;
    void *descriptor;
};

static void ObserveCompletion(id completion, unsigned route) {
    if (!completion || issuingRequest) return;
    struct ProbeBlockLiteral *block = (__bridge struct ProbeBlockLiteral *)completion;
    if (!(block->flags & (1 << 30)) || !block->descriptor) return;
    unsigned char *cursor = (unsigned char *)block->descriptor;
    cursor += 2 * sizeof(unsigned long);
    if (block->flags & (1 << 25)) cursor += 2 * sizeof(void *);
    const char *signature = *(const char **)cursor;
    if (!signature) return;
    NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:signature];
    BOOL valid = !strcmp(sig.methodReturnType, "v");
    BOOL hasBool = NO;
    if (route < 3) valid = valid && sig.numberOfArguments >= 2 &&
        [sig getArgumentTypeAtIndex:1][0] == '@';
    else {
        valid = valid && (sig.numberOfArguments == 3 || sig.numberOfArguments == 4) &&
            [sig getArgumentTypeAtIndex:1][0] == '@' && [sig getArgumentTypeAtIndex:2][0] == '@';
        if (valid && sig.numberOfArguments == 4) {
            const char *type = [sig getArgumentTypeAtIndex:3];
            valid = !strcmp(type, @encode(BOOL)); hasBool = valid;
        }
    }
    NSString *encoding = @(signature);
    dispatch_async(dispatch_get_main_queue(), ^{
        static unsigned recorded;
        if (!(recorded & (1u << route))) {
            recorded |= 1u << route;
            Log([NSString stringWithFormat:@"SYSTEM-COMPLETION route=%u encoding=%@ valid=%d", route, encoding, valid]);
        }
        if (valid && !objectImageCompletionVerified) {
            objectImageCompletionVerified = YES;
            requestRoute = route;
            configurationHasBool = hasBool;
        }
    });
}

typedef void (*CompletionIMP)(id, SEL, id);
typedef void (*ConfigurationIMP)(id, SEL, id, id);
static CompletionIMP originalHandler, originalCompletion;
static ConfigurationIMP originalConfiguration, originalProgressive;
static void HandlerHook(id object, SEL selector, id completion) {
    ObserveCompletion(completion, 1); originalHandler(object, selector, completion);
}
static void CompletionHook(id object, SEL selector, id completion) {
    ObserveCompletion(completion, 2); originalCompletion(object, selector, completion);
}
static void ConfigurationHook(id object, SEL selector, id destination, id block) {
    ObserveCompletion(block, 3); originalConfiguration(object, selector, destination, block);
}
static void ProgressiveHook(id object, SEL selector, id destination, id block) {
    ObserveCompletion(block, 4); originalProgressive(object, selector, destination, block);
}
static void InstallCatalogHooks(void) {
    static BOOL installed;
    if (installed) return;
    Class cls = NSClassFromString(@"MPArtworkCatalog");
    if (!cls) { Log(@"HOOK-WAIT MPArtworkCatalog not loaded"); return; }
    installed = YES;
    if (class_getInstanceMethod(cls, @selector(requestImageWithCompletionHandler:)))
        MSHookMessageEx(cls, @selector(requestImageWithCompletionHandler:), (IMP)HandlerHook, (IMP *)&originalHandler);
    if (class_getInstanceMethod(cls, @selector(requestImageWithCompletion:)))
        MSHookMessageEx(cls, @selector(requestImageWithCompletion:), (IMP)CompletionHook, (IMP *)&originalCompletion);
    if (class_getInstanceMethod(cls, @selector(setDestination:configurationBlock:)))
        MSHookMessageEx(cls, @selector(setDestination:configurationBlock:), (IMP)ConfigurationHook, (IMP *)&originalConfiguration);
    if (class_getInstanceMethod(cls, @selector(setDestination:progressiveConfigurationBlock:)))
        MSHookMessageEx(cls, @selector(setDestination:progressiveConfigurationBlock:), (IMP)ProgressiveHook, (IMP *)&originalProgressive);
    Log([NSString stringWithFormat:@"HOOK-INSTALLED handler=%d completion=%d configuration=%d progressive=%d",
        originalHandler != NULL, originalCompletion != NULL, originalConfiguration != NULL, originalProgressive != NULL]);
}
