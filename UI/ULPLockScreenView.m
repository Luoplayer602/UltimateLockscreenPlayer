#import "ULPLockScreenView.h"

#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

static void ULPFindArtworkInView(UIView *view, UIView *host, UIView *excluded,
                                 CGFloat width, CGFloat height,
                                 UIImage **best, CGFloat *bestScore) {
    if (view == excluded || view.hidden || view.alpha < 0.05) return;
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        UIImage *image = imageView.image;
        CGRect rect = [view convertRect:view.bounds toView:host];
        CGFloat side = MIN(rect.size.width, rect.size.height);
        CGFloat aspect = rect.size.height > 0 ? rect.size.width / rect.size.height : 0;
        if (image && side >= 58 && side <= 180 && aspect > 0.85 && aspect < 1.15 &&
            rect.origin.x < width * 0.5 && rect.origin.y > height * 0.25 &&
            rect.origin.y < height * 0.82) {
            CGFloat score = side - fabs(rect.origin.y - height * 0.45) * 0.1;
            if (score > *bestScore) { *bestScore = score; *best = image; }
        }
    }
    for (UIView *child in view.subviews)
        ULPFindArtworkInView(child, host, excluded, width, height, best, bestScore);
}

@interface ULPLockScreenView () {
    UIView *_backgroundClip;
    UIImageView *_background;
    UIView *_dim;
    UIView *_visualContainer;
    CAShapeLayer *_visualLayer;
    UIView *_card;
    UIImageView *_thumbnail;
    UILabel *_title;
    UILabel *_artist;
    UIButton *_previous;
    UIButton *_playPause;
    UIButton *_next;
    CAShapeLayer *_progressTop;
    CAShapeLayer *_progressBottom;
    CGFloat _zoom;
    float _levels[64];
    UIImage *_lastArtwork;
    CIContext *_imageContext;
}
@end

@implementation ULPLockScreenView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _backgroundClip = [[UIView alloc] initWithFrame:self.bounds];
    _backgroundClip.clipsToBounds = YES;
    _backgroundClip.userInteractionEnabled = NO;
    [self addSubview:_backgroundClip];
    _background = [[UIImageView alloc] initWithFrame:_backgroundClip.bounds];
    _background.contentMode = UIViewContentModeScaleAspectFill;
    _background.clipsToBounds = YES;
    _background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_backgroundClip addSubview:_background];

    _dim = [[UIView alloc] initWithFrame:_backgroundClip.bounds];
    _dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.36];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_backgroundClip addSubview:_dim];

    _visualContainer = [[UIView alloc] initWithFrame:CGRectZero];
    _visualContainer.userInteractionEnabled = NO;
    [self addSubview:_visualContainer];
    _visualLayer = [CAShapeLayer layer];
    _visualLayer.fillColor = UIColor.clearColor.CGColor;
    _visualLayer.strokeColor = UIColor.whiteColor.CGColor;
    _visualLayer.lineWidth = 2.0;
    _visualLayer.lineJoin = kCALineJoinRound;
    _visualLayer.shadowColor = UIColor.whiteColor.CGColor;
    _visualLayer.shadowOpacity = 0.35;
    _visualLayer.shadowRadius = 5;
    [_visualContainer.layer addSublayer:_visualLayer];

    _card = [[UIView alloc] initWithFrame:CGRectZero];
    _card.backgroundColor = [[UIColor colorWithRed:0.07 green:0.10 blue:0.11 alpha:1] colorWithAlphaComponent:0.86];
    _card.layer.cornerRadius = 20;
    _card.layer.masksToBounds = NO;
    [self addSubview:_card];

    _thumbnail = [[UIImageView alloc] initWithFrame:CGRectZero];
    _thumbnail.contentMode = UIViewContentModeScaleAspectFill;
    _thumbnail.clipsToBounds = YES;
    _thumbnail.layer.cornerRadius = 12;
    [_card addSubview:_thumbnail];

    _title = [UILabel new];
    _title.font = [UIFont boldSystemFontOfSize:16];
    _title.textColor = UIColor.whiteColor;
    _title.lineBreakMode = NSLineBreakByTruncatingTail;
    [_card addSubview:_title];
    _artist = [UILabel new];
    _artist.font = [UIFont systemFontOfSize:13];
    _artist.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.72];
    _artist.lineBreakMode = NSLineBreakByTruncatingTail;
    [_card addSubview:_artist];

    _previous = [self button:@"◀◀" command:5];
    _playPause = [self button:@"Ⅱ" command:2];
    _next = [self button:@"▶▶" command:4];

    for (CAShapeLayer *layer in @[_progressTop = [CAShapeLayer layer],
                                  _progressBottom = [CAShapeLayer layer]]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.strokeColor = [UIColor colorWithRed:1 green:0.87 blue:0.58 alpha:1].CGColor;
        layer.lineWidth = 2;
        layer.lineCap = kCALineCapRound;
        layer.shadowColor = layer.strokeColor;
        layer.shadowOpacity = 0.7;
        layer.shadowRadius = 5;
        layer.strokeEnd = 0;
        [_card.layer addSublayer:layer];
    }
    return self;
}

- (UIButton *)button:(NSString *)title command:(NSInteger)command {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont boldSystemFontOfSize:19];
    button.tag = command;
    [button addTarget:self action:@selector(buttonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_card addSubview:button];
    return button;
}

- (void)buttonPressed:(UIButton *)sender {
    if (self.commandHandler) self.commandHandler(sender.tag);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;
    CGPoint inCard = [self convertPoint:point toView:_card];
    if (CGRectContainsPoint(_card.bounds, inCard)) return [super hitTest:point withEvent:event];
    return nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    _backgroundClip.frame = CGRectMake(0, 30, width, MAX(0, height - 72));
    CGFloat visualSide = MIN(width - 82, height * 0.39);
    _visualContainer.frame = CGRectMake((width - visualSide) / 2,
                                       (height - visualSide) / 2 - 24,
                                       visualSide, visualSide);
    _visualLayer.frame = _visualContainer.bounds;

    CGFloat cardWidth = width - 34;
    CGFloat cardHeight = 124;
    _card.frame = CGRectMake(17, height - cardHeight - 66, cardWidth, cardHeight);
    _thumbnail.frame = CGRectMake(15, 15, 94, 94);
    CGFloat textX = 123;
    CGFloat available = cardWidth - textX - 14;
    _title.frame = CGRectMake(textX, 18, available, 24);
    _artist.frame = CGRectMake(textX, 44, available, 20);
    CGFloat controlWidth = available / 3;
    _previous.frame = CGRectMake(textX, 73, controlWidth, 40);
    _playPause.frame = CGRectMake(textX + controlWidth, 73, controlWidth, 40);
    _next.frame = CGRectMake(textX + 2 * controlWidth, 73, controlWidth, 40);

    CGFloat left = 0.5, right = cardWidth - 0.5, top = 0.5, bottom = cardHeight - 0.5;
    CGFloat radius = _card.layer.cornerRadius;
    UIBezierPath *upper = [UIBezierPath bezierPath];
    [upper moveToPoint:CGPointMake(left, cardHeight / 2)];
    [upper addLineToPoint:CGPointMake(left, top + radius)];
    [upper addQuadCurveToPoint:CGPointMake(left + radius, top) controlPoint:CGPointMake(left, top)];
    [upper addLineToPoint:CGPointMake(right - radius, top)];
    [upper addQuadCurveToPoint:CGPointMake(right, top + radius) controlPoint:CGPointMake(right, top)];
    [upper addLineToPoint:CGPointMake(right, cardHeight / 2)];
    _progressTop.path = upper.CGPath;
    UIBezierPath *lower = [UIBezierPath bezierPath];
    [lower moveToPoint:CGPointMake(left, cardHeight / 2)];
    [lower addLineToPoint:CGPointMake(left, bottom - radius)];
    [lower addQuadCurveToPoint:CGPointMake(left + radius, bottom) controlPoint:CGPointMake(left, bottom)];
    [lower addLineToPoint:CGPointMake(right - radius, bottom)];
    [lower addQuadCurveToPoint:CGPointMake(right, bottom - radius) controlPoint:CGPointMake(right, bottom)];
    [lower addLineToPoint:CGPointMake(right, cardHeight / 2)];
    _progressBottom.path = lower.CGPath;
}

- (void)updateNowPlaying:(ULPNowPlayingSnapshot *)snapshot {
    _title.text = snapshot.title.length ? snapshot.title : @"Đang phát";
    _artist.text = snapshot.artist.length ? snapshot.artist : @"";
    UIImage *artwork = snapshot.artworkImage;
    if (!artwork && snapshot.artworkData.length)
        artwork = [UIImage imageWithData:snapshot.artworkData];
    if (!artwork) artwork = [self findSystemArtwork];
    if (artwork) {
        if (artwork != _lastArtwork) {
            _lastArtwork = artwork;
            _background.image = [self blurredArtwork:artwork] ?: artwork;
        }
        _thumbnail.image = artwork;
        _background.alpha = 1;
        _dim.alpha = 1;
    } else {
        _lastArtwork = nil;
        _background.image = nil;
        _thumbnail.image = nil;
        _background.alpha = 0;
        _dim.alpha = 0;
    }
    [_playPause setTitle:snapshot.playing ? @"Ⅱ" : @"▶" forState:UIControlStateNormal];
    CGFloat progress = snapshot.duration > 0 ? snapshot.elapsed / snapshot.duration : 0;
    if (!isfinite(progress)) progress = 0;
    progress = MIN(1, MAX(0, progress));
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _progressTop.strokeEnd = progress;
    _progressBottom.strokeEnd = progress;
    [CATransaction commit];
}

- (UIImage *)findSystemArtwork {
    UIView *host = self.superview;
    if (!host) return nil;
    UIImage *best = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    CGFloat width = CGRectGetWidth(host.bounds);
    CGFloat height = CGRectGetHeight(host.bounds);
    ULPFindArtworkInView(host, host, self, width, height, &best, &bestScore);
    return best;
}

- (UIImage *)blurredArtwork:(UIImage *)artwork {
    CIImage *input = [[CIImage alloc] initWithImage:artwork];
    if (!input) return nil;
    CIFilter *blur = [CIFilter filterWithName:@"CIGaussianBlur"];
    [blur setValue:input forKey:kCIInputImageKey];
    [blur setValue:@24 forKey:kCIInputRadiusKey];
    CIImage *output = [blur.outputImage imageByCroppingToRect:input.extent];
    if (!output) return nil;
    if (!_imageContext) _imageContext = [CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer: @NO}];
    CGImageRef result = [_imageContext createCGImage:output fromRect:input.extent];
    if (!result) return nil;
    UIImage *image = [UIImage imageWithCGImage:result];
    CGImageRelease(result);
    return image;
}

- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel {
    if (!(frame.featureMask & ULP_MSH2_SPECTRUM)) return;
    CGFloat side = CGRectGetWidth(_visualContainer.bounds);
    if (side < 1) return;
    CGFloat center = side / 2;
    CGFloat baseRadius = side * 0.30;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i <= 64; ++i) {
        NSUInteger bin = i % 64;
        float target = 0;
        for (int offset = -2; offset <= 2; ++offset)
            target += MIN(1, MAX(0, frame.spectrum[(bin + offset + 64) % 64]));
        target /= 5;
        _levels[bin] += (target - _levels[bin]) * (target > _levels[bin] ? 0.42f : 0.18f);
        CGFloat level = _levels[bin];
        CGFloat angle = (CGFloat)i / 64 * (CGFloat)(M_PI * 2) - (CGFloat)M_PI_2;
        CGFloat radius = baseRadius + level * side * 0.08;
        CGPoint point = CGPointMake(center + cos(angle) * radius,
                                    center + sin(angle) * radius);
        if (i == 0) [path moveToPoint:point];
        else [path addLineToPoint:point];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _visualLayer.path = path.CGPath;
    CGFloat targetZoom = 1 + MIN(1, MAX(0, zoomLevel)) * 0.08;
    _zoom += (targetZoom - _zoom) * 0.35;
    if (_zoom < 0.5) _zoom = 1;
    _visualContainer.transform = CGAffineTransformMakeScale(_zoom, _zoom);
    if (_background.image) _background.transform = CGAffineTransformMakeScale(_zoom, _zoom);
    [CATransaction commit];
}

@end
