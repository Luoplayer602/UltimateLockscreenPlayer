#import "ULPCoverView.h"
#import <QuartzCore/QuartzCore.h>
#import "ULPStyleColors.h"
#import "../Visualization/ULPCover.h"

@implementation ULPCoverView {
    UIView *_disc, *_rotor;
    UIImageView *_image;
    UILabel *_logo;
    CAShapeLayer *_outline;
    double _angle, _coordinateScale;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    _visualConfig = ULPVisualConfigDefault();
    _coordinateScale = 1;
    _disc = [UIView new];
    _disc.backgroundColor = ULPStyleColor(0x10131C);
    _disc.clipsToBounds = YES;
    [self addSubview:_disc];
    _rotor = [UIView new];
    [_disc addSubview:_rotor];
    _image = [UIImageView new];
    _image.contentMode = UIViewContentModeScaleAspectFill;
    [_rotor addSubview:_image];
    _logo = [UILabel new];
    _logo.text = @"ULP";
    _logo.textColor = ULPStyleColor(0xF5F6FB);
    _logo.textAlignment = NSTextAlignmentCenter;
    _logo.adjustsFontSizeToFitWidth = YES;
    _logo.minimumScaleFactor = .25;
    [_rotor addSubview:_logo];
    _outline = [CAShapeLayer layer];
    _outline.fillColor = UIColor.clearColor.CGColor;
    [self.layer addSublayer:_outline];
    [self updateAppearance];
    return self;
}

- (void)setVisualConfig:(ULPVisualConfig)config {
    _visualConfig = ULPVisualConfigNormalize(config);
    [self updateAppearance];
    [self setNeedsLayout];
}

- (void)setArtwork:(UIImage *)artwork {
    _artwork = artwork;
    _image.image = artwork;
    [self updateAppearance];
}

- (void)updateAppearance {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.hidden = !_visualConfig.enabled || _visualConfig.coverMode == ULPCoverModeOff ||
                  _visualConfig.coverOpacity <= 0;
    self.alpha = _visualConfig.coverOpacity;
    BOOL showImage = _visualConfig.coverMode == ULPCoverModeArtwork && _artwork != nil;
    _image.hidden = !showImage;
    _logo.hidden = showImage;
    UIColor *color = ULPStyleColor(_visualConfig.coverOutlineColor);
    _outline.strokeColor = color.CGColor;
    _outline.opacity = _visualConfig.coverOutlineOpacity;
    self.layer.shadowColor = color.CGColor;
    self.layer.shadowOpacity = _visualConfig.coverGlow;
    self.layer.shadowRadius = 35 * _visualConfig.coverGlow * _coordinateScale;
    self.layer.shadowOffset = CGSizeZero;
    [CATransaction commit];
}

- (void)layoutInViewport:(CGRect)viewport {
    ULPCoverLayout layout = ULPCoverLayoutForViewport(viewport.size.width, viewport.size.height, _visualConfig);
    _coordinateScale = layout.coordinateScale;
    self.bounds = CGRectMake(0, 0, layout.diameter, layout.diameter);
    self.center = CGPointMake(CGRectGetMinX(viewport) + layout.x, CGRectGetMinY(viewport) + layout.y);
    [self updateAppearance];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat diameter = CGRectGetWidth(self.bounds);
    _disc.frame = self.bounds;
    _disc.layer.cornerRadius = diameter / 2;
    // Set bounds/center rather than frame while the rotor is transformed.
    _rotor.bounds = self.bounds;
    _rotor.center = CGPointMake(diameter / 2, diameter / 2);
    // A square aspect-fill image remains full bleed at every rotation angle.
    _image.frame = self.bounds;
    _logo.frame = self.bounds;
    _logo.font = [UIFont systemFontOfSize:MAX(9, diameter * .17) weight:UIFontWeightHeavy];
    CGFloat thickness = MIN(diameter, _visualConfig.coverOutlineThickness * _coordinateScale);
    _outline.frame = self.bounds;
    _outline.lineWidth = thickness;
    _outline.hidden = thickness <= 0;
    _outline.path = diameter > 0 && thickness > 0 ?
        [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds,
            thickness / 2, thickness / 2)].CGPath : NULL;
    self.layer.shadowPath = diameter > 0 ? [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath : NULL;
    [CATransaction commit];
}

- (void)advanceSpinBy:(NSTimeInterval)seconds {
    if (self.hidden) return;
    _angle = ULPCoverAdvanceSpin(_angle, seconds, _visualConfig.coverSpin);
    [self applyRotation];
}

- (void)applyRotation {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _rotor.transform = CGAffineTransformMakeRotation(_angle);
    [CATransaction commit];
}

- (void)resetMotion {
    _angle = 0;
    [self applyRotation];
}
@end
