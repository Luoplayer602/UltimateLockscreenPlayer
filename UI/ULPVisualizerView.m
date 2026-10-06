#import "ULPVisualizerView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface ULPVisualizerView () {
    UIView *_visualContainer;
    UIView *_halo;
    UILabel *_centerLabel;
    CAShapeLayer *_visualLayer;
    CGFloat _zoom;
    float _levels[64];
}
@end

@implementation ULPVisualizerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _visualContainer = [UIView new];
    _visualContainer.userInteractionEnabled = NO;
    [self addSubview:_visualContainer];

    _visualLayer = [CAShapeLayer layer];
    _visualLayer.fillColor = UIColor.clearColor.CGColor;
    _visualLayer.strokeColor = UIColor.whiteColor.CGColor;
    _visualLayer.lineWidth = 2;
    _visualLayer.lineJoin = kCALineJoinRound;
    _visualLayer.shadowColor = UIColor.whiteColor.CGColor;
    _visualLayer.shadowOpacity = 0.35;
    _visualLayer.shadowRadius = 5;
    [_visualContainer.layer addSublayer:_visualLayer];

    _halo = [UIView new];
    _halo.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.09];
    _halo.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.28].CGColor;
    _halo.layer.borderWidth = 1;
    _halo.layer.shadowColor = UIColor.whiteColor.CGColor;
    _halo.layer.shadowOpacity = 0.12;
    _halo.layer.shadowRadius = 24;
    [_visualContainer addSubview:_halo];

    _centerLabel = [UILabel new];
    _centerLabel.text = @"ULP";
    _centerLabel.textAlignment = NSTextAlignmentCenter;
    _centerLabel.textColor = UIColor.whiteColor;
    _centerLabel.font = [UIFont boldSystemFontOfSize:19];
    [_visualContainer addSubview:_centerLabel];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat side = MIN(width * 0.68, height * 0.38);
    _visualContainer.bounds = CGRectMake(0, 0, side, side);
    _visualContainer.center = CGPointMake(width / 2, height * 0.42);
    _visualLayer.frame = _visualContainer.bounds;
    CGFloat haloSide = side * 0.44;
    _halo.frame = CGRectMake((side - haloSide) / 2, (side - haloSide) / 2,
                             haloSide, haloSide);
    _halo.layer.cornerRadius = haloSide / 2;
    _centerLabel.frame = _halo.frame;
}

- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel {
    if (!(frame.featureMask & ULP_MSH2_SPECTRUM)) return;
    CGFloat side = CGRectGetWidth(_visualContainer.bounds);
    if (side < 1) return;
    CGFloat center = side / 2;
    CGFloat baseRadius = side * 0.29;
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (NSUInteger i = 0; i <= 64; ++i) {
        NSUInteger bin = i % 64;
        float target = 0;
        for (int offset = -1; offset <= 1; ++offset)
            target += MIN(1, MAX(0, frame.spectrum[(bin + offset + 64) % 64]));
        target /= 3;
        _levels[bin] += (target - _levels[bin]) * (target > _levels[bin] ? 0.42f : 0.18f);
        CGFloat angle = (CGFloat)i / 64 * (CGFloat)(M_PI * 2) - (CGFloat)M_PI_2;
        CGFloat radius = baseRadius + _levels[bin] * side * 0.16;
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
    [CATransaction commit];
}

@end
