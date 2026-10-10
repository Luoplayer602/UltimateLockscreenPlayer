#import "ULPArtworkProvider.h"
#import "ULPArtworkRequest.h"
#import "../UI/ULPArtworkImage.h"
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>
#import <string.h>

// Callback ABI verified by probe v4 on iOS 15.8.5:
// void (^)(MRUArtworkView *destination, UIImage *image).
@interface ULPIndependentArtworkCatalog : NSObject
- (instancetype)initWithToken:(id)token dataSource:(id)source;
- (void)setFittingSize:(CGSize)size;
- (void)setDestinationScale:(double)scale;
- (void)setDestination:(id)destination configurationBlock:(void (^)(id, UIImage *))block;
@end

static id ULPArtworkObjectIvar(id object, const char *name) {
    Ivar ivar = object ? class_getInstanceVariable([object class], name) : NULL;
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(object, ivar) : nil;
}

static UIView *ULPFindCatalogView(UIView *view, UIView *excluded, unsigned depth) {
    if (!view || view == excluded || depth > 24) return nil;
    if ([NSStringFromClass(view.class) isEqualToString:@"MRUArtworkView"] &&
        ULPArtworkObjectIvar(view, "_catalog") && MIN(view.bounds.size.width, view.bounds.size.height) >= 40)
        return view;
    for (UIView *child in view.subviews) {
        UIView *found = ULPFindCatalogView(child, excluded, depth + 1);
        if (found) return found;
    }
    return nil;
}

static BOOL ULPCatalogMethod(id object, SEL selector, const char *result, unsigned count) {
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    return sig && sig.numberOfArguments == count && !strcmp(sig.methodReturnType, result);
}

@implementation ULPArtworkProvider {
    NSString *_track;
    id _lastToken;
    id _rejectedToken;
    id _pendingCatalog;
    id _pendingDestination;
    __weak UIView *_host;
    ULPArtworkRequest _request;
    BOOL _satisfied;
    BOOL _unsupportedLogged;
}

- (void)log:(NSString *)message {
    if (self.diagnosticHandler) self.diagnosticHandler([@"Artwork HQ " stringByAppendingString:message]);
}

- (void)finish:(ULPArtworkTicket)ticket {
    if (!ULPArtworkRequestFinish(&_request, ticket, CACurrentMediaTime())) return;
    _pendingCatalog = nil;
    _pendingDestination = nil;
}

- (void)updateWithSnapshot:(ULPNowPlayingSnapshot *)snapshot
                     host:(UIView *)host excludingView:(UIView *)excluded {
    NSString *track = snapshot.sessionPresent ? snapshot.trackIdentifier ?: @"" : @"";
    if (![_track isEqualToString:track] || _host != host) {
        // A late callback cannot finish a request belonging to the next track.
        if (![_track isEqualToString:track] && _lastToken) {
            _rejectedToken = _lastToken;
            _lastToken = nil;
        }
        _track = [track copy];
        _host = host;
        ULPArtworkRequestReset(&_request);
        _pendingCatalog = nil;
        _pendingDestination = nil;
        _satisfied = NO;
    }
    if (!track.length || !host.window || _satisfied || _request.pending || _request.attempts >= 4 ||
        CACurrentMediaTime() < _request.retryAfter) return;
    @try {
        UIView *nativeView = ULPFindCatalogView(host, excluded, 0);
        id systemCatalog = ULPArtworkObjectIvar(nativeView, "_catalog");
        id token = ULPArtworkObjectIvar(systemCatalog, "_token");
        id source = ULPArtworkObjectIvar(systemCatalog, "_dataSource");
        if (!token || !source || [token isEqual:_rejectedToken] ||
            ![NSStringFromClass([source class]) isEqualToString:@"MPCMediaRemoteArtworkRemoteDataSource"]) return;
        // A rebuilt player may already have the global high-resolution cache.
        // Remember its native token as well, so the next track rejects that token.
        CGSize existing = ULPArtworkPixelSize(snapshot.artworkImage);
        if (MAX(existing.width, existing.height) >= 750) {
            _lastToken = token;
            _satisfied = YES;
            return;
        }
        Class cls = NSClassFromString(@"MPArtworkCatalog");
        ULPIndependentArtworkCatalog *allocated = [cls alloc];
        if (!ULPCatalogMethod(allocated, @selector(initWithToken:dataSource:), "@", 4) ||
            !ULPCatalogMethod(allocated, @selector(setFittingSize:), "v", 3) ||
            !ULPCatalogMethod(allocated, @selector(setDestinationScale:), "v", 3) ||
            !ULPCatalogMethod(allocated, @selector(setDestination:configurationBlock:), "v", 4)) {
            if (!_unsupportedLogged) { [self log:@"unavailable catalog methods; using standard artwork"]; _unsupportedLogged = YES; }
            return;
        }
        NSMethodSignature *sizeSig = [allocated methodSignatureForSelector:@selector(setFittingSize:)];
        NSMethodSignature *scaleSig = [allocated methodSignatureForSelector:@selector(setDestinationScale:)];
        NSMethodSignature *initSig = [allocated methodSignatureForSelector:@selector(initWithToken:dataSource:)];
        NSMethodSignature *configSig = [allocated methodSignatureForSelector:@selector(setDestination:configurationBlock:)];
        if (strcmp([sizeSig getArgumentTypeAtIndex:2], @encode(CGSize)) ||
            strcmp([scaleSig getArgumentTypeAtIndex:2], @encode(double)) ||
            [initSig getArgumentTypeAtIndex:2][0] != '@' || [initSig getArgumentTypeAtIndex:3][0] != '@' ||
            [configSig getArgumentTypeAtIndex:2][0] != '@' || strcmp([configSig getArgumentTypeAtIndex:3], "@?")) return;
        ULPArtworkTicket ticket;
        if (!ULPArtworkRequestBegin(&_request, CACurrentMediaTime(), &ticket)) return;
        _lastToken = token;
        ULPIndependentArtworkCatalog *catalog = [allocated initWithToken:token dataSource:source];
        if (!catalog) { [self finish:ticket]; return; }
        [catalog setDestinationScale:1];
        [catalog setFittingSize:CGSizeMake(750, 750)];
        NSObject *destination = [NSObject new];
        _pendingCatalog = catalog;
        _pendingDestination = destination;
        __weak typeof(self) weakSelf = self;
        __weak UIView *weakNative = nativeView;
        __weak UIView *weakHost = host;
        [self log:[NSString stringWithFormat:@"begin id=%llu attempt=%u target=750x750 track=%@",
            (unsigned long long)ticket.serial, _request.attempts, track]];
        // Register the deadline before invoking a private selector, including if it raises.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf || !ULPArtworkRequestMatches(&strongSelf->_request, ticket)) return;
            [strongSelf log:[NSString stringWithFormat:@"timeout id=%llu", (unsigned long long)ticket.serial]];
            [strongSelf finish:ticket];
        });
        [catalog setDestination:destination configurationBlock:^(id target, UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf || !ULPArtworkRequestMatches(&strongSelf->_request, ticket)) return;
                id currentCatalog = ULPArtworkObjectIvar(weakNative, "_catalog");
                id currentToken = ULPArtworkObjectIvar(currentCatalog, "_token");
                if (![strongSelf->_track isEqualToString:track] || !weakHost || strongSelf->_host != weakHost ||
                    !weakHost.window || ![weakNative isDescendantOfView:weakHost] || ![currentToken isEqual:token]) {
                    [strongSelf log:@"discarded result: track/catalog/host changed"];
                    [strongSelf finish:ticket]; return;
                }
                if (![image isKindOfClass:UIImage.class]) {
                    [strongSelf log:@"empty result; keeping current image until retry"]; return;
                }
                CGSize pixels = ULPArtworkPixelSize(image);
                [strongSelf log:[NSString stringWithFormat:@"result id=%llu pixels=%.0fx%.0f track=%@",
                    (unsigned long long)ticket.serial, pixels.width, pixels.height, track]];
                if (strongSelf.imageHandler) strongSelf.imageHandler(image, track);
                if (MAX(pixels.width, pixels.height) >= 750) {
                    strongSelf->_satisfied = YES;
                    [strongSelf finish:ticket];
                }
            });
        }];
    } @catch (NSException *exception) {
        [self log:[NSString stringWithFormat:@"exception %@; using standard artwork", exception.name]];
        if (_request.pending) [self finish:(ULPArtworkTicket){_request.generation, _request.serial}];
    }
}
@end
