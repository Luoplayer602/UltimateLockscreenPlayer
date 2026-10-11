#import "ULPCoverView.h"
#import <QuartzCore/QuartzCore.h>
#import "ULPStyleColors.h"
#import "../Visualization/ULPCover.h"
#import "../Visualization/ULPBeat.h"

// The worker uses its own bitmap context and no live UIKit/CA view state.
static UIImage *ULPHaloTexture(CGFloat diameter, CGFloat radius, CGFloat screenScale, UIColor *color) {
    if (radius <= 0) return nil;
    CGFloat extent = ceil(diameter + 6 * radius + 4);
    CGFloat pixels = MIN(512, ceil(extent * screenScale)), ratio = pixels / extent;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(pixels, pixels), NO, 1);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (context) {
        // Match the falloff measured against CALayer in the device probe.
        CGContextSetShadowWithColor(context, CGSizeZero, 2 * radius * ratio, color.CGColor);
        CGContextSetFillColorWithColor(context, color.CGColor);
        CGContextFillEllipseInRect(context, CGRectMake((pixels - diameter * ratio) / 2,
            (pixels - diameter * ratio) / 2, diameter * ratio, diameter * ratio));
    }
    UIImage *image = context ? UIGraphicsGetImageFromCurrentImageContext() : nil;
    UIGraphicsEndImageContext();
    return image;
}

@implementation ULPCoverView {
    UIView *_disc, *_rotor;
    UIImageView *_image;
    UILabel *_logo;
    CAShapeLayer *_outline;
    CAGradientLayer *_flash;
    ULPBeatMotionState _motion;
    double _angle, _coordinateScale;
    CFTimeInterval _lastEffectTime;
    float _rawLevel, _beatLevel, _haloLevel;
    NSArray<CALayer *> *_haloLayers;
    double _haloCacheDiameter, _haloCacheUnit;
    uint32_t _haloCacheColor;
    BOOL _haloCacheValid, _haloCacheBuilding, _renderingSuspended;
    NSUInteger _haloTextureGeneration;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    _visualConfig = ULPVisualConfigDefault();
    _coordinateScale = 1;
    NSMutableArray *halos = [NSMutableArray array];
    for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) [halos addObject:[CALayer layer]];
    _haloLayers = halos;
    for (CALayer *halo in _haloLayers) {
        halo.opacity = 0;
        [self.layer addSublayer:halo];
    }
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
    _flash = [CAGradientLayer layer];
    _flash.type = kCAGradientLayerRadial;
    _flash.startPoint = CGPointMake(.5, .5);
    _flash.endPoint = CGPointMake(1, 1);
    _flash.colors = @[(id)[UIColor colorWithWhite:1 alpha:.9].CGColor,
                      (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
    _flash.opacity = 0;
    [_disc.layer addSublayer:_flash];
    _outline = [CAShapeLayer layer];
    _outline.fillColor = UIColor.clearColor.CGColor;
    [self.layer addSublayer:_outline];
    [self updateAppearance];
    return self;
}

- (void)setVisualConfig:(ULPVisualConfig)config {
    if (config.coverReactType != _visualConfig.coverReactType ||
        config.beatMotion != _visualConfig.beatMotion ||
        config.coverReaction != _visualConfig.coverReaction ||
        config.coverMode != _visualConfig.coverMode || config.enabled != _visualConfig.enabled)
        [self resetReaction];
    _visualConfig = ULPVisualConfigNormalize(config);
    [self updateAppearance];
    CFTimeInterval now = CACurrentMediaTime();
    BOOL stale = _lastEffectTime > 0 && now - _lastEffectTime > .5;
    [self updateReactionAtTime:now rawLevel:stale ? 0 : _rawLevel beatLevel:stale ? 0 : _beatLevel];
    [self setNeedsLayout];
}

- (void)setArtwork:(UIImage *)artwork {
    if (_artwork == artwork) return;
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
    [self prepareHaloCache];
    [self updateHalo];
    self.layer.shadowOffset = CGSizeZero;
    [CATransaction commit];
}

- (void)updateHalo {
    if (_visualConfig.coverGlowPulse > 0 && _haloCacheValid) {
        self.layer.shadowOpacity = 0;
        ULPCoverHaloBlend blend = ULPCoverHaloWeights(_visualConfig.coverGlow,
            _visualConfig.coverGlowPulse, _haloLevel);
        for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) {
            CALayer *layer = _haloLayers[i];
            float opacity = layer.contents ? blend.opacity[i] : 0;
            if (layer.opacity != opacity) layer.opacity = opacity;
        }
    } else {
        for (CALayer *layer in _haloLayers) if (layer.opacity) layer.opacity = 0;
        float opacity = _visualConfig.coverGlow;
        CGFloat radius = 35 * opacity * _coordinateScale;
        if (self.layer.shadowOpacity != opacity) self.layer.shadowOpacity = opacity;
        if (self.layer.shadowRadius != radius) self.layer.shadowRadius = radius;
    }
}

- (void)prepareHaloCache {
    CGFloat diameter = CGRectGetWidth(self.bounds);
    if (_renderingSuspended || self.hidden || diameter <= 0 || _visualConfig.coverGlowPulse <= 0) {
        if (_haloCacheValid) {
            for (CALayer *layer in _haloLayers) { layer.contents = nil; layer.opacity = 0; }
            _haloCacheValid = NO;
        }
        return;
    }
    if (_haloCacheValid && _haloCacheDiameter == diameter && _haloCacheUnit == _coordinateScale &&
        _haloCacheColor == _visualConfig.coverOutlineColor) return;
    if (_haloCacheValid) {
        for (CALayer *layer in _haloLayers) { layer.contents = nil; layer.opacity = 0; }
        _haloCacheValid = NO;
    }
    // One worker per Cover. If style changes during a build, the completion
    // discards it and schedules only the latest style, rather than queuing each
    // slider event. Until ready, updateHalo keeps the old static Glow behavior.
    if (_haloCacheBuilding) return;
    _haloCacheDiameter = diameter; _haloCacheUnit = _coordinateScale;
    _haloCacheColor = _visualConfig.coverOutlineColor;
    _haloCacheBuilding = YES;
    double unit = _coordinateScale;
    uint32_t colorKey = _visualConfig.coverOutlineColor;
    CGFloat screenScale = UIScreen.mainScreen.scale;
    ULPCoverHaloBlend blend = ULPCoverHaloWeights(_visualConfig.coverGlow, _visualConfig.coverGlowPulse, 0);
    // Five soft textures <= 5 MiB, unchanged during audio or strength edits.
    // Each has its own extent; weak halos do not blend a peak-sized quad.
    UIColor *color = ULPStyleColor(colorKey);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            NSMutableArray *images = [NSMutableArray array];
            for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) {
                @autoreleasepool {
                    UIImage *image = ULPHaloTexture(diameter, 35 * blend.levels[i] * unit, screenScale, color);
                    [images addObject:image ?: NSNull.null];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                self->_haloCacheBuilding = NO;
                if (self->_renderingSuspended || self.hidden || self->_visualConfig.coverGlowPulse <= 0 ||
                    diameter != CGRectGetWidth(self.bounds) || unit != self->_coordinateScale ||
                    colorKey != self->_visualConfig.coverOutlineColor) {
                    [self prepareHaloCache];
                    return;
                }
                [CATransaction begin]; [CATransaction setDisableActions:YES];
                for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) {
                    CALayer *layer = self->_haloLayers[i];
                    CGFloat extent = ceil(diameter + 6 * 35 * blend.levels[i] * unit + 4);
                    layer.frame = CGRectInset(self.bounds, -(extent - diameter) / 2, -(extent - diameter) / 2);
                    UIImage *image = images[i] == NSNull.null ? nil : images[i];
                    layer.contents = (__bridge id)image.CGImage;
                }
                self->_haloCacheValid = YES;
                ++self->_haloTextureGeneration;
                [self updateHalo];
                [CATransaction commit];
            });
        }
    });
}

- (void)setRenderingSuspended:(BOOL)suspended {
    _renderingSuspended = suspended;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    [self prepareHaloCache]; [self updateHalo];
    [CATransaction commit];
}

- (void)layoutInViewport:(CGRect)viewport {
    ULPCoverLayout layout = ULPCoverLayoutForViewport(viewport.size.width, viewport.size.height, _visualConfig);
    BOOL resized = CGRectGetWidth(self.bounds) != layout.diameter || _coordinateScale != layout.coordinateScale;
    _coordinateScale = layout.coordinateScale;
    CGPoint center = CGPointMake(CGRectGetMinX(viewport) + layout.x, CGRectGetMinY(viewport) + layout.y);
    if (!CGPointEqualToPoint(self.center, center)) self.center = center;
    if (resized) {
        self.bounds = CGRectMake(0, 0, layout.diameter, layout.diameter);
        [self updateAppearance];
        [self setNeedsLayout];
    }
    [self layoutIfNeeded];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat diameter = CGRectGetWidth(self.bounds);
    _disc.frame = self.bounds;
    _disc.layer.cornerRadius = diameter / 2;
    _flash.frame = self.bounds;
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
    [self resetReaction];
}

- (void)resetReaction {
    _motion = (ULPBeatMotionState){0};
    _rawLevel = _beatLevel = _haloLevel = 0;
    _lastEffectTime = 0;
    [self updateReactionAtTime:CACurrentMediaTime() rawLevel:0 beatLevel:0];
}

- (void)triggerBeat:(float)strength atTime:(CFTimeInterval)time {
    if (self.hidden || _visualConfig.coverReactType != ULPReactBeat || _visualConfig.coverReaction <= 0) return;
    ULPBeatMotionTrigger(&_motion, _visualConfig.beatMotion,
                         strength * _visualConfig.coverReaction, time);
}

- (BOOL)hasReactionAtTime:(CFTimeInterval)time {
    if (self.hidden) return NO;
    return _visualConfig.coverDrift > 0 ||
        (_visualConfig.coverRumble > 0 && _rawLevel > 0) ||
        (_visualConfig.coverGlowPulse > 0 && _haloLevel > 0) ||
        (_visualConfig.coverReaction > 0 && ULPBeatMotionActive(&_motion, time)) ||
        !CGAffineTransformIsIdentity(self.transform);
}

- (void)updateReactionAtTime:(CFTimeInterval)time rawLevel:(float)level {
    [self updateReactionAtTime:time rawLevel:level beatLevel:0];
}

- (void)updateReactionAtTime:(CFTimeInterval)time rawLevel:(float)raw beatLevel:(float)beat {
    _rawLevel = !self.hidden && isfinite(raw) ? fminf(1, fmaxf(0, raw)) : 0;
    _beatLevel = !self.hidden && isfinite(beat) ? fminf(1, fmaxf(0, beat)) : 0;
    float targetHalo = _visualConfig.coverReactType == ULPReactRaw ? _rawLevel : _beatLevel;
    double dt = _lastEffectTime && isfinite(time) ? fmax(0, time - _lastEffectTime) : 1.0 / 60;
    _haloLevel += (targetHalo - _haloLevel) * -expm1(-dt / (targetHalo > _haloLevel ? .035 : .18));
    if (_haloLevel < .0001) _haloLevel = 0;
    if (isfinite(time)) _lastEffectTime = time;
    ULPBeatMotion m = ULPBeatMotionIdentity();
    if (!self.hidden && _visualConfig.coverReaction > 0) {
        if (_visualConfig.coverReactType == ULPReactBeat) m = ULPBeatMotionEvaluate(&_motion, time);
        else m.scale += .55 * _visualConfig.coverReaction * _rawLevel;
    }
    ULPCoverAmbient ambient = ULPCoverAmbientEvaluate(_visualConfig, time, _rawLevel, _haloLevel);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGAffineTransform transform = CGAffineTransformMakeRotation(m.rotation);
    transform = CGAffineTransformScale(transform, m.scale, m.scale);
    transform.tx = (m.x + ambient.x) * _coordinateScale;
    transform.ty = (m.y + ambient.y) * _coordinateScale;
    self.transform = transform;
    _flash.opacity = m.flash;
    [self updateHalo];
    [CATransaction commit];
}
@end
