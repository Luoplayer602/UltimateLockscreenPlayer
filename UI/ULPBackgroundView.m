#import "ULPBackgroundView.h"

#import <CoreImage/CoreImage.h>
#import <math.h>

@interface ULPBackgroundView () <UIGestureRecognizerDelegate> {
    UIImageView *_imageView;
    UIView *_dimView;
    UIImage *_sourceArtwork;
    CIContext *_imageContext;
    float _zoom;
    UIPanGestureRecognizer *_swipeRecognizer;
    BOOL _swipeActive;
}
@end

@implementation ULPBackgroundView

- (void)attachSwipeRecognitionToView:(UIView *)view {
    if (_swipeRecognizer || !view) return;
    _swipeRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                              action:@selector(handleSwipe:)];
    _swipeRecognizer.delegate = self;
    _swipeRecognizer.cancelsTouchesInView = NO;
    [view addGestureRecognizer:_swipeRecognizer];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
        shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (void)handleSwipe:(UIPanGestureRecognizer *)gesture {
    if (self.hidden) return;
    CGFloat velocity = [gesture velocityInView:gesture.view].y;
    CGFloat screenHeight = CGRectGetHeight(gesture.view.bounds);
    CGFloat translation = [gesture translationInView:gesture.view].y;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        _swipeActive = NO;
        [self.layer removeAllAnimations];
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        if (!_swipeActive && velocity > 650 && translation > 20)
            _swipeActive = YES;
        if (_swipeActive)
            self.transform = CGAffineTransformMakeTranslation(
                0, MIN(screenHeight * 0.36, MAX(0, translation * 0.8)));
    } else if (gesture.state == UIGestureRecognizerStateEnded) {
        BOOL fling = velocity > 650 && translation > 20;
        if (!_swipeActive && !fling) return;
        if (fling) {
            CGFloat overscan = screenHeight * ULP_BACKGROUND_OVERSCAN_RATIO;
            CGFloat reveal = MIN(screenHeight * 0.18,
                                 (velocity - 650) * 0.00012 * screenHeight);
            CGFloat displacement = overscan + reveal;
            [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionCurveEaseOut
                             animations:^{ self.transform = CGAffineTransformMakeTranslation(0, displacement); }
                             completion:^(BOOL finished) {
                if (finished) [self springBack];
            }];
        } else {
            [self springBack];
        }
        _swipeActive = NO;
    } else if (gesture.state == UIGestureRecognizerStateCancelled ||
               gesture.state == UIGestureRecognizerStateFailed) {
        _swipeActive = NO;
        [self springBack];
    }
}

- (void)springBack {
    [UIView animateWithDuration:0.75 delay:0
         usingSpringWithDamping:0.72 initialSpringVelocity:0.3
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self.transform = CGAffineTransformIdentity; }
                     completion:nil];
}

- (void)resetMotion {
    [self.layer removeAllAnimations];
    _swipeActive = NO;
    self.transform = CGAffineTransformIdentity;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.backgroundColor = [UIColor colorWithRed:0.10 green:0.10 blue:0.12 alpha:1];
    self.clipsToBounds = YES;
    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    [self addSubview:_imageView];
    _dimView = [[UIView alloc] initWithFrame:self.bounds];
    _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.36];
    [self addSubview:_dimView];
    return self;
}

- (void)setArtwork:(UIImage *)artwork {
    if (artwork == _sourceArtwork) return;
    _sourceArtwork = artwork;
    if (!artwork) { _imageView.image = nil; return; }
    UIGraphicsBeginImageContextWithOptions(artwork.size, YES, artwork.scale);
    [UIColor.blackColor setFill];
    UIRectFill(CGRectMake(0, 0, artwork.size.width, artwork.size.height));
    [artwork drawInRect:CGRectMake(0, 0, artwork.size.width, artwork.size.height)];
    UIImage *opaque = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CIImage *input = [[CIImage alloc] initWithImage:opaque];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:input forKey:kCIInputImageKey];
    [blur setValue:@24 forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    if (!_imageContext) _imageContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    CGImageRef image = output ? [_imageContext createCGImage:output fromRect:input.extent] : NULL;
    _imageView.image = image ? [UIImage imageWithCGImage:image] : opaque;
    if (image) CGImageRelease(image);
}

- (UIImage *)renderedArtwork {
    return _imageView.image;
}

- (void)setRenderedArtwork:(UIImage *)artwork {
    _imageView.image = artwork;
}

- (void)setZoomLevel:(float)level {
    if (!isfinite(level)) return;
    float target = 1 + fminf(1, fmaxf(0, level)) * 0.08f;
    _zoom = _zoom > 0 ? _zoom + (target - _zoom) * 0.35f : target;
    _imageView.transform = CGAffineTransformMakeScale(_zoom, _zoom);
}

@end
