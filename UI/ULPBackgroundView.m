#import "ULPBackgroundView.h"

#import <CoreImage/CoreImage.h>
#import <math.h>
#import "ULPStyleColors.h"
#import "ULPArtworkImage.h"

@interface ULPBackgroundView () <UIGestureRecognizerDelegate> {
    UIImageView *_imageView;
    UIImageView *_foreground;
    CAGradientLayer *_fallbackGradient;
    UIImage *_blurredArtwork;
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
    _visualConfig = ULPVisualConfigDefault();
    _fallbackGradient = [CAGradientLayer layer];
    [self.layer addSublayer:_fallbackGradient];
    _imageView = [[UIImageView alloc] initWithFrame:self.bounds];
    _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _imageView.contentMode = UIViewContentModeScaleAspectFill;
    [self addSubview:_imageView];
    _foreground = [UIImageView new];
    _foreground.clipsToBounds = YES;
    _foreground.layer.cornerCurve = kCACornerCurveContinuous;
    [self addSubview:_foreground];
    _dimView = [[UIView alloc] initWithFrame:self.bounds];
    _dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _dimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.36];
    [self addSubview:_dimView];
    [self updateAppearance];
    return self;
}

- (UIImage *)blurArtwork:(UIImage *)artwork {
    if (!artwork || artwork.size.width <= 0 || artwork.size.height <= 0) return nil;
    CGFloat ratio = MIN(1, 512 / MAX(artwork.size.width, artwork.size.height));
    CGSize size = CGSizeMake(artwork.size.width * ratio, artwork.size.height * ratio);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1);
    [UIColor.blackColor setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    [artwork drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *opaque = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CIImage *input = [[CIImage alloc] initWithImage:opaque];
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:[input imageByClampingToExtent] forKey:kCIInputImageKey];
    [blur setValue:@24 forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    if (!_imageContext) _imageContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    CGImageRef image = output ? [_imageContext createCGImage:output fromRect:input.extent] : NULL;
    UIImage *result = image ? [UIImage imageWithCGImage:image] : opaque;
    if (image) CGImageRelease(image);
    return result;
}

- (void)setVisualConfig:(ULPVisualConfig)config {
    _visualConfig = ULPVisualConfigNormalize(config);
    [self updateAppearance];
}

- (void)setContentViewport:(CGRect)rect {
    _contentViewport = rect;
    [self setNeedsLayout];
}

- (void)setArtwork:(UIImage *)artwork {
    [self setArtwork:artwork renderedArtwork:nil];
}

- (void)setArtwork:(UIImage *)artwork renderedArtwork:(UIImage *)blur {
    if (artwork != _sourceArtwork) {
        _sourceArtwork = artwork;
        _blurredArtwork = blur;
    } else if (blur) _blurredArtwork = blur;
    [self updateAppearance];
}

- (void)updateAppearance {
    BOOL art = _sourceArtwork && _visualConfig.artworkBackground;
    if (art && _visualConfig.artworkBackgroundType != 0 && !_blurredArtwork)
        _blurredArtwork = [self blurArtwork:_sourceArtwork];
    _imageView.hidden = !art || _visualConfig.artworkBackgroundType == 0;
    _imageView.image = _blurredArtwork;
    _foreground.hidden = !art || _visualConfig.artworkBackgroundType == 2;
    _foreground.image = _sourceArtwork;
    _foreground.contentMode = UIViewContentModeScaleAspectFit;
    _dimView.hidden = !art;
    _fallbackGradient.hidden = art;
    UIColor *one = ULPStyleColor(_visualConfig.backgroundColor1);
    UIColor *two = _visualConfig.backgroundMode == 1 ? ULPStyleColor(_visualConfig.backgroundColor2) : one;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fallbackGradient.colors = @[(id)one.CGColor, (id)two.CGColor];
    _fallbackGradient.startPoint = CGPointMake(0, 0);
    _fallbackGradient.endPoint = CGPointMake(1, 1);
    [CATransaction commit];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fallbackGradient.frame = self.bounds;
    [CATransaction commit];
    CGRect viewport = CGRectIsEmpty(_contentViewport) ? self.bounds : _contentViewport;
    CGSize pixels = ULPArtworkPixelSize(_sourceArtwork);
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    ULPArtworkExtent extent = ULPArtworkForegroundExtent(pixels.width, pixels.height, scale,
        CGRectGetWidth(viewport), CGRectGetHeight(viewport), _visualConfig.artworkBackgroundType == 0);
    _foreground.bounds = CGRectMake(0, 0, extent.width, extent.height);
    _foreground.center = CGPointMake(CGRectGetMidX(viewport), CGRectGetMidY(viewport));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _foreground.layer.cornerRadius = _visualConfig.artworkBackgroundType == 1 ?
        MIN(24, MIN(extent.width, extent.height) * .065) : 0;
    [CATransaction commit];
    [self applyArtworkZoom];
}

- (UIImage *)renderedArtwork {
    return _blurredArtwork;
}

- (void)setRenderedArtwork:(UIImage *)artwork {
    _blurredArtwork = artwork;
    [self updateAppearance];
}

- (void)setZoomLevel:(float)level {
    if (!isfinite(level)) return;
    float target = 1 + fminf(1, fmaxf(0, level)) * 0.08f;
    _zoom = _zoom > 0 ? _zoom + (target - _zoom) * 0.35f : target;
    [self applyArtworkZoom];
}

- (void)applyArtworkZoom {
    float zoom = _zoom > 0 ? _zoom : 1;
    _imageView.transform = CGAffineTransformMakeScale(zoom, zoom);
    // Both foreground styles retain the original smoothed 8% audio motion.
    _foreground.transform = CGAffineTransformMakeScale(zoom, zoom);
}

@end
