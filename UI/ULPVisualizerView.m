#import "ULPVisualizerView.h"
#import "../Visualization/ULPWaveform.h"
#import "../Visualization/ULPTrail.h"
#import "ULPStyleColors.h"
#import "ULPCoverView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface ULPVisualizerView () {
    UIView *_visualContainer;
    ULPCoverView *_cover;
    CAShapeLayer *_visualLayer;
    CAShapeLayer *_capsLayer;
    CAShapeLayer *_ringLayer;
    CAShapeLayer *_unlitLayer;
    CAShapeLayer *_fillLayer;
    CAShapeLayer *_siriBackStroke;
    CAShapeLayer *_siriMiddleStroke;
    CAShapeLayer *_siriBackFill;
    CAShapeLayer *_siriMiddleFill;
    CGFloat _zoom;
    float _levels[128];
    float _peaks[128];
    ULPWaveformState _wave;
    CFTimeInterval _lastFrameTime;
    CGFloat _radialRotation;
    UIColor *_manualColor;
    UIColor *_artworkColor;
    CAGradientLayer *_shapePaint;
    CALayer *_shapeMask;
    CALayer *_trailLayer;
    ULPTrailBuffer _trail;
    CGContextRef _trailContext;
    NSTimer *_trailTimer;
    CFTimeInterval _lastTrailTime;
    CGRect _trailViewport;
    BOOL _trailUnavailable;
    __weak UIImage *_trailArtwork;
}
@end

static float ULPClampLevel(float value) {
    return isfinite(value) ? fminf(1, fmaxf(0, value)) : 0;
}

// Capture geometry only: the halo, label, background and current Glow never
// enter the history. The live CAShapeLayers remain the foreground renderer.
static void ULPTrailDrawShape(CGContextRef context, CAShapeLayer *layer, BOOL mask) {
    if (!layer.path || layer.hidden || layer.opacity <= 0) return;
    if (layer.fillColor && CGColorGetAlpha(layer.fillColor) > 0) {
        CGContextSetAlpha(context, layer.opacity);
        if (mask) CGContextSetRGBFillColor(context, 1, 1, 1, CGColorGetAlpha(layer.fillColor));
        else CGContextSetFillColorWithColor(context, layer.fillColor);
        CGContextAddPath(context, layer.path);
        if ([layer.fillRule isEqualToString:kCAFillRuleEvenOdd]) CGContextEOFillPath(context);
        else CGContextFillPath(context);
    }
    if (layer.strokeColor && CGColorGetAlpha(layer.strokeColor) > 0 && layer.lineWidth > 0) {
        CGContextSetAlpha(context, layer.opacity);
        if (mask) CGContextSetRGBStrokeColor(context, 1, 1, 1, CGColorGetAlpha(layer.strokeColor));
        else CGContextSetStrokeColorWithColor(context, layer.strokeColor);
        CGContextSetLineWidth(context, layer.lineWidth);
        CGContextSetLineCap(context, [layer.lineCap isEqualToString:kCALineCapRound] ? kCGLineCapRound :
            [layer.lineCap isEqualToString:kCALineCapSquare] ? kCGLineCapSquare : kCGLineCapButt);
        CGContextSetLineJoin(context, [layer.lineJoin isEqualToString:kCALineJoinRound] ? kCGLineJoinRound :
            [layer.lineJoin isEqualToString:kCALineJoinBevel] ? kCGLineJoinBevel : kCGLineJoinMiter);
        CGContextAddPath(context, layer.path);
        CGContextStrokePath(context);
    }
}

static float ULPSampleSpectrum(ULPMSH2FeatureFrame frame, float position) {
    position = fminf(63, fmaxf(0, position));
    unsigned lower = (unsigned)floorf(position);
    unsigned upper = lower < 63 ? lower + 1 : lower;
    float fraction = position - lower;
    return ULPClampLevel(frame.spectrum[lower]) * (1 - fraction) +
           ULPClampLevel(frame.spectrum[upper]) * fraction;
}

static float ULPSpectrumPhase(float phase, ULPSymmetry symmetry) {
    switch (symmetry) {
        case ULPSymmetryVertical:
            return 2 * fminf(phase, 1 - phase);
        case ULPSymmetryHorizontal:
            if (phase <= 0.25f) return 0.5f + 2 * phase;
            if (phase >= 0.75f) return 2 * (phase - 0.75f);
            return 1.5f - 2 * phase;
        case ULPSymmetryBoth:
            return 4 * fminf(fminf(phase, 1 - phase), fabsf(0.5f - phase));
        default:
            return phase;
    }
}

static void ULPAppendSmoothLine(UIBezierPath *path, const CGPoint *points,
                                NSUInteger count) {
    if (!count) return;
    [path moveToPoint:points[0]];
    for (NSUInteger i = 1; i < count; ++i) {
        CGPoint midpoint = CGPointMake((points[i - 1].x + points[i].x) / 2,
                                       (points[i - 1].y + points[i].y) / 2);
        [path addQuadCurveToPoint:midpoint controlPoint:points[i - 1]];
    }
    [path addQuadCurveToPoint:points[count - 1] controlPoint:points[count - 1]];
}

static void ULPAppendWaveLine(UIBezierPath *path, const CGPoint *points,
                              NSUInteger count, BOOL smooth, BOOL connect) {
    if (!count) return;
    if (connect) [path addLineToPoint:points[0]];
    else [path moveToPoint:points[0]];
    for (NSUInteger i = 1; i < count; ++i) {
        if (smooth) {
            CGPoint middle = CGPointMake((points[i-1].x + points[i].x) / 2,
                                         (points[i-1].y + points[i].y) / 2);
            [path addQuadCurveToPoint:middle controlPoint:points[i-1]];
        } else [path addLineToPoint:points[i]];
    }
    if (smooth) [path addQuadCurveToPoint:points[count-1] controlPoint:points[count-1]];
}

static void ULPAppendClosedWave(UIBezierPath *path, const CGPoint *points,
                                NSUInteger count) {
    if (count < 3) return;
    // Periodic quadratic segments share their boundary tangent, including the
    // seam. Midpoints also avoid spline overshoot on strong signed PCM peaks.
    CGPoint first = CGPointMake((points[count-1].x + points[0].x) * .5,
                                (points[count-1].y + points[0].y) * .5);
    [path moveToPoint:first];
    for (NSUInteger i = 0; i < count; ++i) {
        CGPoint next = points[(i + 1) % count];
        CGPoint middle = CGPointMake((points[i].x + next.x) * .5,
                                     (points[i].y + next.y) * .5);
        [path addQuadCurveToPoint:middle controlPoint:points[i]];
    }
    [path closePath];
}

@implementation ULPVisualizerView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _visualConfig = ULPVisualConfigDefault();
    _zoom = 1;
    _manualColor = UIColor.whiteColor;

    _trailLayer = [CALayer layer];
    _trailLayer.actions = @{@"contents":NSNull.null, @"bounds":NSNull.null,
                            @"position":NSNull.null};
    [self.layer addSublayer:_trailLayer];

    _visualContainer = [UIView new];
    _visualContainer.userInteractionEnabled = NO;
    [self addSubview:_visualContainer];

    _visualLayer = [CAShapeLayer layer];
    _unlitLayer = [CAShapeLayer layer];
    _fillLayer = [CAShapeLayer layer];
    _siriBackStroke = [CAShapeLayer layer];
    _siriMiddleStroke = [CAShapeLayer layer];
    _siriBackFill = [CAShapeLayer layer];
    _siriMiddleFill = [CAShapeLayer layer];
    _capsLayer = [CAShapeLayer layer];
    _ringLayer = [CAShapeLayer layer];
    [_visualContainer.layer addSublayer:_unlitLayer];
    [_visualContainer.layer addSublayer:_siriBackFill];
    [_visualContainer.layer addSublayer:_siriMiddleFill];
    [_visualContainer.layer addSublayer:_fillLayer];
    for (CAShapeLayer *layer in @[_siriBackStroke, _siriMiddleStroke]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.lineJoin = kCALineJoinRound;
        layer.lineCap = kCALineCapRound;
        layer.shadowRadius = 5;
        [_visualContainer.layer addSublayer:layer];
    }
    _visualLayer.fillColor = UIColor.clearColor.CGColor;
    _visualLayer.strokeColor = UIColor.whiteColor.CGColor;
    _visualLayer.lineWidth = 2;
    _visualLayer.lineJoin = kCALineJoinRound;
    _visualLayer.shadowColor = UIColor.whiteColor.CGColor;
    _visualLayer.shadowOpacity = 0.35;
    _visualLayer.shadowRadius = 5;
    [_visualContainer.layer addSublayer:_visualLayer];
    [_visualContainer.layer addSublayer:_ringLayer];
    [_visualContainer.layer addSublayer:_capsLayer];

    _shapeMask = [CALayer layer];
    for (CALayer *layer in [_visualContainer.layer.sublayers copy]) {
        [layer removeFromSuperlayer];
        [_shapeMask addSublayer:layer];
    }
    _shapePaint = [CAGradientLayer layer];
    _shapePaint.mask = _shapeMask;
    [_visualContainer.layer addSublayer:_shapePaint];

    _cover = [[ULPCoverView alloc] initWithFrame:CGRectZero];
    _cover.visualConfig = _visualConfig;
    [self addSubview:_cover];
    return self;
}

- (void)setVisualConfig:(ULPVisualConfig)visualConfig {
    visualConfig = ULPVisualConfigNormalize(visualConfig);
    BOOL changedCover = visualConfig.mode != _visualConfig.mode ||
                        visualConfig.coverMode != _visualConfig.coverMode;
    BOOL changedMode = visualConfig.mode != _visualConfig.mode || visualConfig.points != _visualConfig.points;
    if (changedMode || visualConfig.trailEnabled != _visualConfig.trailEnabled ||
        visualConfig.enabled != _visualConfig.enabled ||
        visualConfig.colorMode != _visualConfig.colorMode ||
        visualConfig.color1 != _visualConfig.color1 || visualConfig.color2 != _visualConfig.color2 ||
        visualConfig.gradientAngle != _visualConfig.gradientAngle ||
        visualConfig.fill != _visualConfig.fill || visualConfig.fillOpacity != _visualConfig.fillOpacity ||
        visualConfig.opacity != _visualConfig.opacity || visualConfig.trailOpacity != _visualConfig.trailOpacity)
        [self resetTrail];
    _visualConfig = visualConfig;
    _cover.visualConfig = visualConfig;
    if (changedCover) [_cover resetMotion];
    if (changedMode) {
        memset(_levels, 0, sizeof(_levels));
        memset(_peaks, 0, sizeof(_peaks));
        memset(&_wave, 0, sizeof(_wave));
        _visualLayer.path = NULL; _capsLayer.path = NULL;
        _unlitLayer.path = NULL; _fillLayer.path = NULL;
        _ringLayer.path = NULL;
        _siriBackStroke.path = NULL; _siriMiddleStroke.path = NULL;
        _siriBackFill.path = NULL; _siriMiddleFill.path = NULL;
    }
    [self updateVisualTransform];
    [self setNeedsLayout];
    [self updateStrokeColor];
}

- (void)updateVisualTransform {
    CGFloat scale = _visualConfig.scale * MAX(1, _zoom);
    CGAffineTransform transform = CGAffineTransformMakeRotation(_visualConfig.rotation * M_PI / 180);
    transform = CGAffineTransformScale(transform,
        scale * _visualConfig.width * (_visualConfig.flipX ? -1 : 1),
        scale * _visualConfig.height * (_visualConfig.flipY ? -1 : 1));
    _visualContainer.transform = transform;
    _visualContainer.alpha = _visualConfig.opacity;
}

- (void)updateStrokeColor {
    UIColor *color = _visualConfig.automaticColor ? (_artworkColor ?: UIColor.whiteColor) :
                     (_manualColor ?: UIColor.whiteColor);
    UIColor *second = _visualConfig.colorMode == 1 ? ULPStyleColor(_visualConfig.color2) : color;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shapePaint.colors = @[(id)color.CGColor, (id)second.CGColor];
    // Solid/artwork keep the original direct shape layers and glow. Only
    // gradient needs the additional mask pass.
    BOOL gradient = _visualConfig.colorMode == 1;
    _shapePaint.hidden = !gradient;
    for (CAShapeLayer *layer in @[_unlitLayer, _siriBackFill, _siriMiddleFill,
         _fillLayer, _siriBackStroke, _siriMiddleStroke, _visualLayer, _ringLayer, _capsLayer]) {
        CALayer *parent = gradient ? _shapeMask : _visualContainer.layer;
        if (layer.superlayer == parent) continue;
        [layer removeFromSuperlayer];
        if (gradient) [_shapeMask addSublayer:layer];
        else [_visualContainer.layer insertSublayer:layer below:_shapePaint];
    }
    BOOL filled = _visualConfig.mode == ULPVisualModeDot || _visualConfig.mode == ULPVisualModeBar ||
                  _visualConfig.mode == ULPVisualModeEqualizer || _visualConfig.mode == ULPVisualModeDotMatrix;
    _visualLayer.strokeColor = filled ? UIColor.clearColor.CGColor : color.CGColor;
    _visualLayer.fillColor = filled ?
                             color.CGColor : UIColor.clearColor.CGColor;
    _capsLayer.fillColor = color.CGColor;
    _capsLayer.strokeColor = color.CGColor;
    _ringLayer.fillColor = UIColor.clearColor.CGColor;
    _ringLayer.strokeColor = [color colorWithAlphaComponent:_visualConfig.ringOpacity].CGColor;
    _unlitLayer.fillColor = [color colorWithAlphaComponent:_visualConfig.unlitOpacity].CGColor;
    _fillLayer.fillColor = [color colorWithAlphaComponent:_visualConfig.fillOpacity].CGColor;
    _siriMiddleStroke.strokeColor = [color colorWithAlphaComponent:.75].CGColor;
    _siriBackStroke.strokeColor = [color colorWithAlphaComponent:.5].CGColor;
    _siriMiddleFill.fillColor = [color colorWithAlphaComponent:_visualConfig.fillOpacity * .75].CGColor;
    _siriBackFill.fillColor = [color colorWithAlphaComponent:_visualConfig.fillOpacity * .5].CGColor;
    _visualLayer.shadowColor = color.CGColor;
    for (CAShapeLayer *layer in @[_siriBackStroke, _siriMiddleStroke]) {
        layer.shadowColor = color.CGColor;
        layer.shadowOpacity = _visualConfig.glow * .7;
    }
    [CATransaction commit];
}

- (void)setArtwork:(UIImage *)artwork manualColor:(UIColor *)manualColor {
    if (artwork != _trailArtwork || ![_manualColor isEqual:manualColor ?: UIColor.whiteColor])
        [self resetTrail];
    _trailArtwork = artwork;
    _cover.artwork = artwork;
    _manualColor = manualColor ?: UIColor.whiteColor;
    _artworkColor = nil;
    if (artwork.CGImage) {
        unsigned char pixel[4] = {0};
        CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space,
                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        if (context) {
            CGContextSetInterpolationQuality(context, kCGInterpolationLow);
            CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), artwork.CGImage);
            CGFloat red = pixel[0] / 255.0, green = pixel[1] / 255.0, blue = pixel[2] / 255.0;
            CGFloat brightest = MAX(red, MAX(green, blue));
            CGFloat lift = brightest < 0.72 ? (0.72 - brightest) : 0;
            _artworkColor = [UIColor colorWithRed:MIN(1, red + lift)
                                          green:MIN(1, green + lift)
                                           blue:MIN(1, blue + lift) alpha:1];
            CGContextRelease(context);
        }
        CGColorSpaceRelease(space);
    }
    [self updateStrokeColor];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectEqualToRect(_trailViewport, self.bounds)) {
        [self resetTrail];
        _trailViewport = self.bounds;
    }
    _trailLayer.frame = self.bounds;
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    // Width determines the normal size; short preview cards limit it to fit.
    BOOL waveform = _visualConfig.mode == ULPVisualModeWave ||
                    _visualConfig.mode == ULPVisualModeMirror ||
                    _visualConfig.mode == ULPVisualModeSiri;
    CGFloat side = waveform ? width * .94 : MIN(width * 0.44, height * 0.72);
    _visualContainer.bounds = CGRectMake(0, 0, side, side);
    CGFloat padding = _visualConfig.colorMode == 1 ? 24 : 0;
    _shapePaint.frame = CGRectInset(_visualContainer.bounds, -padding, -padding);
    _shapeMask.frame = _shapePaint.bounds;
    ULPGradientPoints gradient = ULPGradientEndpoints(_visualConfig.gradientAngle, side, side);
    CGFloat paintSide = MAX(1, side + 2 * padding);
    _shapePaint.startPoint = CGPointMake((gradient.x1 * side + padding) / paintSide,
                                         (gradient.y1 * side + padding) / paintSide);
    _shapePaint.endPoint = CGPointMake((gradient.x2 * side + padding) / paintSide,
                                       (gradient.y2 * side + padding) / paintSide);
    CGFloat verticalCenter = height < 240 ? 0.50 : 0.42;
    CGFloat coordinateScale = waveform ? width / 400.0 : 1;
    _visualContainer.center = CGPointMake(width / 2 + _visualConfig.offsetX * coordinateScale,
                                           height * verticalCenter + _visualConfig.offsetY * coordinateScale);
    for (CAShapeLayer *layer in @[_visualLayer, _capsLayer, _ringLayer, _unlitLayer,
         _fillLayer, _siriBackStroke, _siriMiddleStroke, _siriBackFill, _siriMiddleFill])
        layer.frame = CGRectMake(padding, padding, side, side);
    [_cover layoutInViewport:self.bounds];
}

- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel {
    BOOL waveform = _visualConfig.mode == ULPVisualModeWave ||
                    _visualConfig.mode == ULPVisualModeMirror ||
                    _visualConfig.mode == ULPVisualModeSiri ||
                    _visualConfig.mode == ULPVisualModeCircularWave;
    if (!waveform && !(frame.featureMask & ULP_MSH2_SPECTRUM)) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastFrameTime + 0.002 < 1.0 / _visualConfig.framesPerSecond) return;
    CGFloat dt = _lastFrameTime > 0 ? MIN(0.1, now - _lastFrameTime) : 1.0 / 60;
    _lastFrameTime = now;
    CGFloat side = CGRectGetWidth(_visualContainer.bounds);
    if (side < 1) return;
    CGFloat center = side / 2;
    CGFloat baseRadius = side * 0.29;
    UIBezierPath *path = [UIBezierPath bezierPath];
    UIBezierPath *caps = [UIBezierPath bezierPath];
    UIBezierPath *unlit = [UIBezierPath bezierPath];
    UIBezierPath *fill = [UIBezierPath bezierPath];
    UIBezierPath *ring = [UIBezierPath bezierPath];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NSUInteger count = _visualConfig.points;
    ULPVisualMode mode = _visualConfig.mode;
    BOOL radial = mode == ULPVisualModeCircle || mode == ULPVisualModeDot ||
                  mode == ULPVisualModeRadial || mode == ULPVisualModeSmoothSpectro;
    for (NSUInteger i = 0; !waveform && i < count; ++i) {
        float fraction = (float)i / (radial ? count : MAX(1, count - 1));
        float phase = (mode == ULPVisualModeRadial || mode == ULPVisualModeSmoothSpectro) ?
                      ULPRadialFrequencyPhase(fraction, _visualConfig.radialSymmetry) :
                      ULPVisualIsSpectrum(mode) ?
                      ULPSpectrumFrequencyPhase(fraction, _visualConfig.mirror, _visualConfig.reverse) :
                      radial ? ULPSpectrumPhase(fraction, _visualConfig.symmetry) :
                      ((_visualConfig.symmetry & ULPSymmetryVertical) ?
                       2 * fminf(fraction, 1 - fraction) : fraction);
        float position = _visualConfig.firstBand +
                         phase * (_visualConfig.lastBand - _visualConfig.firstBand) *
                         ((ULPVisualIsSpectrum(mode) || mode == ULPVisualModeRadial ||
                           mode == ULPVisualModeSmoothSpectro) ?
                          _visualConfig.frequencyRange : 1);
        float target = (ULPSampleSpectrum(frame, position - 0.6f) +
                        ULPSampleSpectrum(frame, position) +
                        ULPSampleSpectrum(frame, position + 0.6f)) / 3;
        float factor = 1 - powf(1 - (target > _levels[i] ? 0.42f : 0.18f), dt * 60);
        _levels[i] += (target - _levels[i]) * factor;
    }

    if (waveform) {
        ULPWaveformUpdate(&_wave, &frame, _visualConfig.waveSmoothing, dt);
        BOOL mirror = mode == ULPVisualModeMirror;
        BOOL siri = mode == ULPVisualModeSiri;
        CGPoint upper[128], lower[128];
        CGFloat usable = side * .9;
        CGFloat coordinateScale = side / 376.0;
        if (mode == ULPVisualModeCircularWave) {
            _radialRotation = fmod(_radialRotation + dt * _visualConfig.rotationSpeed * M_PI / 180, M_PI * 2);
            for (NSUInteger i = 0; i < count; ++i) {
                float phase = (float)i / count;
                CGFloat angle = phase * M_PI * 2 - M_PI_2 + _radialRotation;
                CGFloat radius = side * ULPCircularWaveformRadius(&_wave, phase,
                    _visualConfig.waveAmplitude, _visualConfig.innerRadius);
                upper[i] = CGPointMake(center + cos(angle) * radius,
                                       center + sin(angle) * radius);
                CGFloat baseline = side * _visualConfig.innerRadius / 2;
                lower[i] = CGPointMake(center + cos(angle) * baseline,
                                       center + sin(angle) * baseline);
            }
            ULPAppendClosedWave(path, upper, count);
            if (_visualConfig.fill) {
                [fill appendPath:path];
                // Same curve approximation for both contours: silence leaves
                // no filled sliver, and even-odd fill keeps the centre clear.
                ULPAppendClosedWave(fill, lower, count);
            }
        } else if (siri) {
            for (unsigned layer = 0; layer < 3; ++layer) {
                UIBezierPath *stroke = layer == 0 ? path : [UIBezierPath bezierPath];
                UIBezierPath *layerFill = layer == 0 ? fill : [UIBezierPath bezierPath];
                for (NSUInteger i = 0; i < count; ++i) {
                    float phase = (float)i / MAX(1, count - 1);
                    float sample = ULPWaveformSample(&_wave, phase);
                    CGFloat x = center - usable / 2 + phase * usable;
                    upper[i] = CGPointMake(x, center + ULPSiriOffset(sample, phase,
                        _visualConfig.waveAmplitude, 94, layer) * coordinateScale);
                }
                ULPAppendWaveLine(stroke, upper, count, _visualConfig.smoothCurve, NO);
                if (_visualConfig.fill) {
                    ULPAppendWaveLine(layerFill, upper, count, _visualConfig.smoothCurve, NO);
                    [layerFill addLineToPoint:CGPointMake(upper[count-1].x, center)];
                    [layerFill addLineToPoint:CGPointMake(upper[0].x, center)];
                    [layerFill closePath];
                }
                if (layer == 1) {
                    _siriMiddleStroke.path = stroke.CGPath;
                    _siriMiddleFill.path = layerFill.CGPath;
                } else if (layer == 2) {
                    _siriBackStroke.path = stroke.CGPath;
                    _siriBackFill.path = layerFill.CGPath;
                }
            }
        } else {
            for (NSUInteger i = 0; i < count; ++i) {
                float phase = (float)i / MAX(1, count - 1);
                float sample = ULPWaveformSample(&_wave, phase);
                CGFloat x = center - usable / 2 + phase * usable;
                upper[i] = CGPointMake(x, center + ULPWaveformOffset(sample,
                    _visualConfig.waveAmplitude, 94, mirror, _visualConfig.centreGap, false) * coordinateScale);
                lower[count-1-i] = CGPointMake(x, center + ULPWaveformOffset(sample,
                    _visualConfig.waveAmplitude, 94, true, _visualConfig.centreGap, true) * coordinateScale);
            }
            BOOL smooth = mirror || _visualConfig.smoothCurve;
            ULPAppendWaveLine(path, upper, count, smooth, NO);
            if (mirror) ULPAppendWaveLine(path, lower, count, smooth, NO);
            if (_visualConfig.fill) {
                ULPAppendWaveLine(fill, upper, count, smooth, NO);
                if (mirror) ULPAppendWaveLine(fill, lower, count, smooth, YES);
                else {
                    [fill addLineToPoint:CGPointMake(upper[count-1].x, center)];
                    [fill addLineToPoint:CGPointMake(upper[0].x, center)];
                }
                [fill closePath];
            }
        }
    } else if (mode == ULPVisualModeSmoothSpectro) {
        CGPoint points[128];
        _radialRotation = fmod(_radialRotation + dt * _visualConfig.rotationSpeed * M_PI / 180, M_PI * 2);
        for (NSUInteger i = 0; i < count; ++i) {
            CGFloat angle = (CGFloat)i / count * M_PI * 2 - M_PI_2 + _radialRotation;
            CGFloat radius = side * ULPSmoothSpectroRadius(_levels[i],
                _visualConfig.smoothSpectroSize, _visualConfig.smoothSpectroReactivity);
            points[i] = CGPointMake(center + cos(angle) * radius,
                                   center + sin(angle) * radius);
        }
        ULPAppendClosedWave(path, points, count);
        if (_visualConfig.fill) [fill appendPath:path];
    } else if (mode == ULPVisualModeRadial) {
        CGFloat radius = side * _visualConfig.innerRadius / 2;
        CGFloat maxLength = side * .25 * _visualConfig.radialBarLength;
        CGFloat gap = side * .01;
        _radialRotation = fmod(_radialRotation + dt * _visualConfig.rotationSpeed * M_PI / 180, M_PI * 2);
        BOOL drawBars = !(_visualConfig.hideVisualizerButPeakCaps && _visualConfig.peakCaps);
        for (NSUInteger i = 0; i < count; ++i) {
            CGFloat angle = (CGFloat)i / count * M_PI * 2 - M_PI_2 + _radialRotation;
            CGFloat direction = _visualConfig.growInward ? -1 : 1;
            CGFloat length = _levels[i] * maxLength;
            CGFloat end = radius + direction * length;
            if (drawBars) {
                CGPoint startPoint = CGPointMake(center + cos(angle) * radius,
                                                 center + sin(angle) * radius);
                CGPoint endPoint = CGPointMake(center + cos(angle) * end,
                                               center + sin(angle) * end);
                [path moveToPoint:startPoint];
                [path addLineToPoint:endPoint];
            }
            if (_visualConfig.peakCaps) {
                _peaks[i] = MAX(_levels[i], _peaks[i] - dt * 1.15);
                if (_peaks[i] <= .001) continue;
                CGFloat capRadius = radius + direction * (_peaks[i] * maxLength + gap);
                CGPoint cap = CGPointMake(center + cos(angle) * capRadius,
                                          center + sin(angle) * capRadius);
                if (_visualConfig.peakCapsType == 1) {
                    CGFloat dot = MAX(1, _visualConfig.capThickness * 1.5);
                    [caps appendPath:[UIBezierPath bezierPathWithOvalInRect:
                        CGRectMake(cap.x - dot/2, cap.y - dot/2, dot, dot)]];
                } else {
                    CGFloat half = MAX(1, _visualConfig.radialBarThickness * 1.5);
                    [caps moveToPoint:CGPointMake(cap.x - sin(angle)*half, cap.y + cos(angle)*half)];
                    [caps addLineToPoint:CGPointMake(cap.x + sin(angle)*half, cap.y - cos(angle)*half)];
                }
            }
        }
        if (_visualConfig.showInnerRing && drawBars)
            [ring appendPath:[UIBezierPath bezierPathWithArcCenter:CGPointMake(center, center)
                radius:radius startAngle:0 endAngle:M_PI*2 clockwise:YES]];
    } else if (radial) {
        for (NSUInteger i = 0; i < count; ++i) {
            CGFloat angle = (CGFloat)i / count * (CGFloat)(M_PI * 2) - (CGFloat)M_PI_2;
            CGFloat radius = baseRadius + _levels[i] * side * _visualConfig.animationScale;
            CGPoint point = CGPointMake(center + cos(angle) * radius,
                                        center + sin(angle) * radius);
            if (mode == ULPVisualModeCircle) {
                if (i == 0) [path moveToPoint:point];
                else [path addLineToPoint:point];
            } else if (mode == ULPVisualModeDot) {
                CGFloat dotRadius = 1.5 + _levels[i] * 2.2;
                [path appendPath:[UIBezierPath bezierPathWithArcCenter:point radius:dotRadius
                                                            startAngle:0 endAngle:M_PI * 2 clockwise:YES]];
            } else {
                CGPoint inner = CGPointMake(center + cos(angle) * baseRadius,
                                            center + sin(angle) * baseRadius);
                [path moveToPoint:inner];
                [path addLineToPoint:point];
            }
        }
        if (mode == ULPVisualModeCircle) [path closePath];
    } else if (mode == ULPVisualModeBar || mode == ULPVisualModeEqualizer ||
               mode == ULPVisualModeDotMatrix) {
        CGFloat usable = side * 0.9;
        CGFloat availableHeight = side * 0.72;
        CGFloat slot = usable / count;
        CGFloat width = slot * (1 - _visualConfig.spacing);
        if (_visualConfig.barWidth > 0) width = MIN(width, _visualConfig.barWidth);
        CGFloat baseY = center + availableHeight / 2;
        for (NSUInteger i = 0; i < count; ++i) {
            float phase = (float)i / MAX(1, count - 1);
            CGFloat amplitude = MAX(_visualConfig.minimumHeight,
                ULPSpectrumHeight(_levels[i], phase, _visualConfig) * availableHeight);
            amplitude = MIN(availableHeight, amplitude);
            CGFloat x = center - usable / 2 + (i + 0.5) * slot;
            CGFloat top = baseY - amplitude;
            if (_visualConfig.growFrom == 1) top = center - amplitude / 2;
            else if (_visualConfig.growFrom == 2) top = center - availableHeight / 2;
            if (mode == ULPVisualModeBar) {
                CGRect rect = CGRectMake(x - width / 2, top, width, amplitude);
                [path appendPath:[UIBezierPath bezierPathWithRoundedRect:rect
                    cornerRadius:MIN(_visualConfig.cornerRadius, MIN(width, amplitude) / 2)]];
            } else {
                CGFloat rowSlot = availableHeight / _visualConfig.rows;
                CGFloat cell = MIN(width, rowSlot * (1 - _visualConfig.spacing));
                if (mode == ULPVisualModeDotMatrix) cell = MIN(cell, _visualConfig.dotSize);
                for (NSUInteger row = 0; row < _visualConfig.rows; ++row) {
                    CGFloat y = center - availableHeight / 2 + (row + 0.5) * rowSlot;
                    CGRect rect = CGRectMake(x - cell / 2, y - cell / 2, cell, cell);
                    UIBezierPath *tile = mode == ULPVisualModeDotMatrix ?
                        [UIBezierPath bezierPathWithOvalInRect:rect] :
                        [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:MIN(cell / 2, _visualConfig.cornerRadius)];
                    [unlit appendPath:tile];
                    // Include a baseline row when Minimum height is nonzero.
                    CGFloat distance = _visualConfig.growFrom == 1 ? fabs(y - center) * 2 :
                        (_visualConfig.growFrom == 2 ? y - (center - availableHeight / 2) : baseY - y);
                    if (amplitude > 0 && distance <= MAX(rowSlot / 2, amplitude)) [path appendPath:tile];
                }
            }
            if (_visualConfig.peakCaps && mode != ULPVisualModeDotMatrix) {
                _peaks[i] = MAX(amplitude, _peaks[i] - dt * availableHeight * 1.15);
                CGFloat capY = baseY - _peaks[i];
                if (_visualConfig.growFrom == 1) capY = center - _peaks[i] / 2;
                if (_visualConfig.growFrom == 2) capY = center - availableHeight / 2 + _peaks[i];
                [caps appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(x - width / 2,
                    capY - _visualConfig.capThickness / 2, width, _visualConfig.capThickness)]];
                if (_visualConfig.growFrom == 1)
                    [caps appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(x - width / 2,
                        center + _peaks[i] / 2 - _visualConfig.capThickness / 2, width, _visualConfig.capThickness)]];
            }
        }
    } else if (mode == ULPVisualModeLine) {
        CGFloat usable = side * 0.9;
        CGFloat baseline = _visualConfig.mirrorVertical ? center : center + side * 0.24;
        for (NSUInteger copy = 0; copy < (_visualConfig.mirrorVertical ? 2 : 1); ++copy) {
            CGPoint points[128];
            for (NSUInteger i = 0; i < count; ++i) {
                float phase = (float)i / MAX(1, count - 1);
                CGFloat amplitude = _levels[i] * side * (_visualConfig.mirrorVertical ? 0.32 : 0.6);
                points[i] = CGPointMake(center - usable / 2 + phase * usable,
                    baseline + (copy ? amplitude : -amplitude));
            }
            UIBezierPath *curve = [UIBezierPath bezierPath];
            ULPAppendSmoothLine(curve, points, count);
            [path appendPath:curve];
            if (_visualConfig.fill) {
                [curve addLineToPoint:CGPointMake(points[count - 1].x, baseline)];
                [curve addLineToPoint:CGPointMake(points[0].x, baseline)];
                [curve closePath];
                [fill appendPath:curve];
            }
        }
    } else {
        NSUInteger layers = 1;
        CGFloat usable = side * 0.9;
        for (NSUInteger layer = 0; layer < layers; ++layer) {
            CGPoint points[128];
            for (NSUInteger i = 0; i < count; ++i) {
                float phase = (float)i / MAX(1, count - 1);
                CGFloat x = center - usable / 2 + phase * usable;
                float smooth = (_levels[i == 0 ? 0 : i - 1] +
                                2 * _levels[i] +
                                _levels[i + 1 < count ? i + 1 : i]) * 0.25f;
                CGFloat sample = sin(phase * (M_PI * 4) + now * (3 + layer) + layer * 2) * smooth;
                CGFloat y = center + sample * side * _visualConfig.animationScale * 1.7;
                points[i] = CGPointMake(x, y);
            }
            ULPAppendSmoothLine(path, points, count);
            if (_visualConfig.symmetry & ULPSymmetryHorizontal) {
                for (NSUInteger i = 0; i < count; ++i)
                    points[i].y = 2 * center - points[i].y;
                ULPAppendSmoothLine(path, points, count);
            }
        }
    }
    _visualLayer.path = path.CGPath;
    _capsLayer.path = caps.CGPath;
    _unlitLayer.path = unlit.CGPath;
    _fillLayer.path = fill.CGPath;
    _fillLayer.fillRule = mode == ULPVisualModeCircularWave ? kCAFillRuleEvenOdd : kCAFillRuleNonZero;
    _ringLayer.path = ring.CGPath;
    _ringLayer.lineWidth = MAX(0.5, _visualConfig.radialBarThickness * 0.6);
    _ringLayer.strokeColor = [[_visualConfig.automaticColor ? (_artworkColor ?: UIColor.whiteColor) :
        (_manualColor ?: UIColor.whiteColor) colorWithAlphaComponent:_visualConfig.ringOpacity] CGColor];
    _capsLayer.lineWidth = _visualConfig.capThickness;
    _capsLayer.lineCap = kCALineCapRound;
    _visualLayer.lineWidth = (waveform || mode == ULPVisualModeLine ||
                             mode == ULPVisualModeSmoothSpectro) ? _visualConfig.thickness : 2.0;
    _visualLayer.lineCap = kCALineCapButt;
    if (mode == ULPVisualModeRadial) {
        _visualLayer.lineWidth = _visualConfig.radialBarThickness;
        _visualLayer.lineCap = _visualConfig.roundedCaps ? kCALineCapRound : kCALineCapButt;
    }
    if (waveform && mode != ULPVisualModeCircularWave) {
        _visualLayer.lineWidth *= side / 376.0;
        _siriBackStroke.lineWidth = _visualLayer.lineWidth;
        _siriMiddleStroke.lineWidth = _visualLayer.lineWidth;
    }
    _visualLayer.shadowOpacity = _visualConfig.glow;
    CGFloat targetZoom = 1 + ULPClampLevel(zoomLevel) * _visualConfig.zoomStrength;
    CGFloat response = 1 - pow(1 - (targetZoom > _zoom ? 0.52 : 0.19), dt * 60);
    _zoom += (targetZoom - _zoom) * response;
    [self updateVisualTransform];
    [CATransaction commit];
    if (_playbackActive) [_cover advanceSpinBy:dt];
    [self updateTrailAtTime:now capture:YES];
}

- (void)resetCoverMotion {
    [_cover resetMotion];
}

- (void)resetTrail {
    [_trailTimer invalidate];
    _trailTimer = nil;
    _trailLayer.contents = nil;
    if (_trailContext) CGContextRelease(_trailContext);
    _trailContext = NULL;
    ULPTrailFree(&_trail);
    _lastTrailTime = 0;
    _trailUnavailable = NO;
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    if (hidden) [self resetTrail];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) [self resetTrail];
}

- (BOOL)prepareTrailBitmap {
    if (_trailContext) return YES;
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    if (width < 1 || height < 1 || !isfinite(width * height)) return NO;
    CGFloat scale = MIN(UIScreen.mainScreen.scale,
                        sqrt((double)ULP_TRAIL_MAX_PIXELS / (width * height)));
    size_t pixelsWide = MAX(1, (size_t)floor(width * scale));
    size_t pixelsHigh = MAX(1, (size_t)floor(height * scale));
    if (!ULPTrailResize(&_trail, pixelsWide, pixelsHigh)) return NO;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    _trailContext = CGBitmapContextCreate(_trail.current, pixelsWide, pixelsHigh, 8,
        pixelsWide * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    return _trailContext != NULL;
}

- (void)captureTrailGeometry {
    CGContextRef context = _trailContext;
    memset(_trail.current, 0, _trail.width * _trail.height * 4);
    CGContextSaveGState(context);
    // Store old geometry in view coordinates, before any later zoom/rotation.
    CGContextTranslateCTM(context, 0, _trail.height);
    CGContextScaleCTM(context, _trail.width / CGRectGetWidth(self.bounds),
                              -(CGFloat)_trail.height / CGRectGetHeight(self.bounds));
    CGContextTranslateCTM(context, _visualContainer.center.x, _visualContainer.center.y);
    CGContextConcatCTM(context, _visualContainer.transform);
    CGContextTranslateCTM(context, -CGRectGetMidX(_visualContainer.bounds),
                                  -CGRectGetMidY(_visualContainer.bounds));
    BOOL gradient = _visualConfig.colorMode == 1;
    for (CAShapeLayer *shape in @[_unlitLayer, _siriBackFill, _siriMiddleFill,
         _fillLayer, _siriBackStroke, _siriMiddleStroke, _visualLayer, _ringLayer, _capsLayer])
        ULPTrailDrawShape(context, shape, gradient);
    if (gradient) {
        // The same combined alpha mask and local gradient as the live layers.
        CGContextSetAlpha(context, 1);
        CGContextSetBlendMode(context, kCGBlendModeSourceIn);
        CGGradientRef paint = CGGradientCreateWithColors(CGBitmapContextGetColorSpace(context),
            (__bridge CFArrayRef)_shapePaint.colors, NULL);
        ULPGradientPoints points = ULPGradientEndpoints(_visualConfig.gradientAngle,
            CGRectGetWidth(_visualContainer.bounds), CGRectGetHeight(_visualContainer.bounds));
        CGFloat side = CGRectGetWidth(_visualContainer.bounds);
        if (paint) {
            CGContextDrawLinearGradient(context, paint,
                CGPointMake(points.x1 * side, points.y1 * side),
                CGPointMake(points.x2 * side, points.y2 * side),
                kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
            CGGradientRelease(paint);
        }
    }
    CGContextRestoreGState(context);
}

- (void)updateTrailAtTime:(CFTimeInterval)now capture:(BOOL)capture {
    if (!_visualConfig.trailEnabled || !_visualConfig.enabled ||
        _visualConfig.trailOpacity <= 0 || _visualConfig.opacity <= 0 || self.hidden || !self.window) {
        if (_trail.history) [self resetTrail];
        return;
    }
    if (_trailUnavailable) return;
    if (![self prepareTrailBitmap]) {
        [self resetTrail];
        _trailUnavailable = YES;
        NSLog(@"[ULP] Trail bitmap unavailable; live renderer continues");
        return;
    }
    if (capture) [self captureTrailGeometry];
    double elapsed = _lastTrailTime ? MAX(0, now - _lastTrailTime) : 0;
    _lastTrailTime = now;
    if (!ULPTrailComposite(&_trail, elapsed, _visualConfig.trailDuration,
                           _visualConfig.trailOpacity, _visualConfig.opacity, capture)) {
        [self resetTrail];
        return;
    }
    // Copy the bytes: CA can keep an image after the next audio frame mutates
    // output. Never hand it a provider pointing at the reusable scratch buffer.
    CFDataRef pixels = _trail.hasOutput ?
        CFDataCreate(kCFAllocatorDefault, _trail.output, _trail.width * _trail.height * 4) : NULL;
    CGDataProviderRef provider = pixels ? CGDataProviderCreateWithCFData(pixels) : NULL;
    CGImageRef image = provider ? CGImageCreate(_trail.width, _trail.height, 8, 32, _trail.width * 4,
        CGBitmapContextGetColorSpace(_trailContext), kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big,
        provider, NULL, YES, kCGRenderingIntentDefault) : NULL;
    _trailLayer.contents = (__bridge id)image;
    if (image) CGImageRelease(image);
    if (provider) CGDataProviderRelease(provider);
    if (pixels) CFRelease(pixels);
    if (!_trailTimer) {
        __weak typeof(self) weakSelf = self;
        _trailTimer = [NSTimer timerWithTimeInterval:1.0 / 30 repeats:YES block:^(NSTimer *timer) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) { [timer invalidate]; return; }
            CFTimeInterval clock = CACurrentMediaTime();
            // Accepted audio frames already update the footprint. Only fade
            // independently after audio/preview updates stop (pause or stall).
            if (clock - self->_lastFrameTime > MAX(.08, 2.0 / self->_visualConfig.framesPerSecond))
                [self updateTrailAtTime:clock capture:NO];
        }];
        [NSRunLoop.mainRunLoop addTimer:_trailTimer forMode:NSRunLoopCommonModes];
    }
}

- (void)dealloc {
    [_trailTimer invalidate];
    if (_trailContext) CGContextRelease(_trailContext);
    ULPTrailFree(&_trail);
}

- (BOOL)hasUnsettledPeakCaps {
    if (!_visualConfig.peakCaps) return NO;
    NSUInteger count = _visualConfig.points;
    CGFloat baseline = _visualConfig.mode == ULPVisualModeRadial ? 0 : _visualConfig.minimumHeight;
    for (NSUInteger i = 0; i < count; ++i)
        if (_peaks[i] > baseline + (_visualConfig.mode == ULPVisualModeRadial ? .001 : .02))
            return YES;
    return NO;
}

@end
