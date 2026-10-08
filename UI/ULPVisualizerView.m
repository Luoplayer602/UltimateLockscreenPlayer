#import "ULPVisualizerView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface ULPVisualizerView () {
    UIView *_visualContainer;
    UIView *_halo;
    UILabel *_centerLabel;
    CAShapeLayer *_visualLayer;
    CAShapeLayer *_capsLayer;
    CAShapeLayer *_unlitLayer;
    CAShapeLayer *_fillLayer;
    CGFloat _zoom;
    float _levels[128];
    float _peaks[128];
    CFTimeInterval _lastFrameTime;
    UIColor *_manualColor;
    UIColor *_artworkColor;
}
@end

static float ULPClampLevel(float value) {
    return isfinite(value) ? fminf(1, fmaxf(0, value)) : 0;
}

static float ULPSampleSpectrum(ULPMSH2FeatureFrame frame, float position) {
    position = fminf(63, fmaxf(0, position));
    unsigned lower = (unsigned)floorf(position);
    unsigned upper = lower < 63 ? lower + 1 : lower;
    float fraction = position - lower;
    return ULPClampLevel(frame.spectrum[lower]) * (1 - fraction) +
           ULPClampLevel(frame.spectrum[upper]) * fraction;
}

static float ULPSampleWaveform(ULPMSH2FeatureFrame frame, float phase) {
    float position = fminf(63, fmaxf(0, phase * 63));
    unsigned lower = (unsigned)floorf(position);
    unsigned upper = lower < 63 ? lower + 1 : lower;
    float fraction = position - lower;
    float a = isfinite(frame.waveform[lower]) ? frame.waveform[lower] : 0;
    float b = isfinite(frame.waveform[upper]) ? frame.waveform[upper] : 0;
    return fminf(1, fmaxf(-1, a * (1 - fraction) + b * fraction));
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

    _visualContainer = [UIView new];
    _visualContainer.userInteractionEnabled = NO;
    [self addSubview:_visualContainer];

    _visualLayer = [CAShapeLayer layer];
    _unlitLayer = [CAShapeLayer layer];
    _fillLayer = [CAShapeLayer layer];
    _capsLayer = [CAShapeLayer layer];
    [_visualContainer.layer addSublayer:_unlitLayer];
    [_visualContainer.layer addSublayer:_fillLayer];
    _visualLayer.fillColor = UIColor.clearColor.CGColor;
    _visualLayer.strokeColor = UIColor.whiteColor.CGColor;
    _visualLayer.lineWidth = 2;
    _visualLayer.lineJoin = kCALineJoinRound;
    _visualLayer.shadowColor = UIColor.whiteColor.CGColor;
    _visualLayer.shadowOpacity = 0.35;
    _visualLayer.shadowRadius = 5;
    [_visualContainer.layer addSublayer:_visualLayer];
    [_visualContainer.layer addSublayer:_capsLayer];

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

- (void)setVisualConfig:(ULPVisualConfig)visualConfig {
    BOOL changedMode = visualConfig.mode != _visualConfig.mode || visualConfig.points != _visualConfig.points;
    _visualConfig = ULPVisualConfigNormalize(visualConfig);
    if (changedMode) {
        memset(_levels, 0, sizeof(_levels));
        memset(_peaks, 0, sizeof(_peaks));
        _visualLayer.path = NULL; _capsLayer.path = NULL;
        _unlitLayer.path = NULL; _fillLayer.path = NULL;
    }
    [self updateVisualTransform];
    BOOL radial = _visualConfig.mode == ULPVisualModeCircle ||
                  _visualConfig.mode == ULPVisualModeDot ||
                  _visualConfig.mode == ULPVisualModeRadial;
    _halo.hidden = !radial;
    _centerLabel.hidden = !radial;
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
    BOOL filled = _visualConfig.mode == ULPVisualModeDot || _visualConfig.mode == ULPVisualModeBar ||
                  _visualConfig.mode == ULPVisualModeEqualizer || _visualConfig.mode == ULPVisualModeDotMatrix;
    _visualLayer.strokeColor = filled ? UIColor.clearColor.CGColor : color.CGColor;
    _visualLayer.fillColor = filled ?
                             color.CGColor : UIColor.clearColor.CGColor;
    _capsLayer.fillColor = color.CGColor;
    _unlitLayer.fillColor = [color colorWithAlphaComponent:_visualConfig.unlitOpacity].CGColor;
    _fillLayer.fillColor = [color colorWithAlphaComponent:_visualConfig.fillOpacity].CGColor;
    _visualLayer.shadowColor = color.CGColor;
    _halo.layer.borderColor = [color colorWithAlphaComponent:0.28].CGColor;
    _halo.layer.shadowColor = color.CGColor;
    _halo.layer.shadowOpacity = _visualConfig.glow * 0.35;
}

- (void)setArtwork:(UIImage *)artwork manualColor:(UIColor *)manualColor {
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
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    // Width determines the normal size; short preview cards limit it to fit.
    CGFloat side = MIN(width * 0.44, height * 0.72);
    _visualContainer.bounds = CGRectMake(0, 0, side, side);
    CGFloat verticalCenter = height < 240 ? 0.50 : 0.42;
    _visualContainer.center = CGPointMake(width / 2 + _visualConfig.offsetX,
                                           height * verticalCenter + _visualConfig.offsetY);
    _visualLayer.frame = _visualContainer.bounds;
    _capsLayer.frame = _visualContainer.bounds;
    _unlitLayer.frame = _visualContainer.bounds;
    _fillLayer.frame = _visualContainer.bounds;
    CGFloat haloSide = side * 0.44;
    _halo.frame = CGRectMake((side - haloSide) / 2, (side - haloSide) / 2,
                             haloSide, haloSide);
    _halo.layer.cornerRadius = haloSide / 2;
    _centerLabel.frame = _halo.frame;
    _centerLabel.font = [UIFont boldSystemFontOfSize:MIN(19, haloSide * 0.25)];
}

- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel {
    if (!(frame.featureMask & ULP_MSH2_SPECTRUM)) return;
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
    NSUInteger count = _visualConfig.points;
    ULPVisualMode mode = _visualConfig.mode;
    BOOL radial = mode == ULPVisualModeCircle || mode == ULPVisualModeDot ||
                  mode == ULPVisualModeRadial;
    for (NSUInteger i = 0; i < count; ++i) {
        float fraction = (float)i / (radial ? count : MAX(1, count - 1));
        float phase = ULPVisualIsSpectrum(mode) ?
                      ULPSpectrumFrequencyPhase(fraction, _visualConfig.mirror, _visualConfig.reverse) :
                      radial ? ULPSpectrumPhase(fraction, _visualConfig.symmetry) :
                      ((_visualConfig.symmetry & ULPSymmetryVertical) ?
                       2 * fminf(fraction, 1 - fraction) : fraction);
        float position = _visualConfig.firstBand +
                         phase * (_visualConfig.lastBand - _visualConfig.firstBand) *
                         (ULPVisualIsSpectrum(mode) ? _visualConfig.frequencyRange : 1);
        float target = (ULPSampleSpectrum(frame, position - 0.6f) +
                        ULPSampleSpectrum(frame, position) +
                        ULPSampleSpectrum(frame, position + 0.6f)) / 3;
        float factor = 1 - powf(1 - (target > _levels[i] ? 0.42f : 0.18f), dt * 60);
        _levels[i] += (target - _levels[i]) * factor;
    }

    if (radial) {
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
                _peaks[i] = MAX(amplitude, _peaks[i] - dt * availableHeight * 0.45);
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
        NSUInteger layers = mode == ULPVisualModeSiri ? 3 : 1;
        CGFloat usable = side * 0.9;
        for (NSUInteger layer = 0; layer < layers; ++layer) {
            CGPoint points[128];
            for (NSUInteger i = 0; i < count; ++i) {
                float phase = (float)i / MAX(1, count - 1);
                CGFloat x = center - usable / 2 + phase * usable;
                float smooth = (_levels[i == 0 ? 0 : i - 1] +
                                2 * _levels[i] +
                                _levels[i + 1 < count ? i + 1 : i]) * 0.25f;
                CGFloat sample = mode == ULPVisualModeWave &&
                                  (frame.featureMask & ULP_MSH2_WAVEFORM) ?
                                  ULPSampleWaveform(frame, phase) :
                                  sin(phase * (M_PI * 4) + now * (3 + layer) + layer * 2) * smooth;
                CGFloat y = center + sample * side * _visualConfig.animationScale *
                                     (mode == ULPVisualModeSiri ? (1.0 + layer * 0.3) : 1.7);
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
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _visualLayer.path = path.CGPath;
    _capsLayer.path = caps.CGPath;
    _unlitLayer.path = unlit.CGPath;
    _fillLayer.path = fill.CGPath;
    _visualLayer.lineWidth = mode == ULPVisualModeLine ? _visualConfig.thickness :
        (mode == ULPVisualModeSiri ? 2.8 : 2.0);
    _visualLayer.shadowOpacity = _visualConfig.glow;
    CGFloat targetZoom = 1 + ULPClampLevel(zoomLevel) * _visualConfig.zoomStrength;
    CGFloat response = 1 - pow(1 - (targetZoom > _zoom ? 0.52 : 0.19), dt * 60);
    _zoom += (targetZoom - _zoom) * response;
    [self updateVisualTransform];
    [CATransaction commit];
}

@end
