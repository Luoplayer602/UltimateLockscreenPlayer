#import "ULPVolumeHUDView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

@interface ULPVolumeHUDView () {
    UIView *_dial;
    CAShapeLayer *_surface;
    CAShapeLayer *_track;
    CAShapeLayer *_fill;
    UIView *_iconTile;
    UIImageView *_icon;
    UILabel *_value;
    NSUInteger _dismissGeneration;
    BOOL _presented;
}
@end

@implementation ULPVolumeHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.userInteractionEnabled = NO;
    self.backgroundColor = UIColor.clearColor;
    self.hidden = YES;
    self.alpha = 0;
    self.bounds = CGRectMake(0, 0, 54, 56);

    _dial = [[UIView alloc] initWithFrame:self.bounds];
    _dial.backgroundColor = UIColor.clearColor;
    [self addSubview:_dial];
    _surface = [CAShapeLayer layer];
    _surface.fillColor = [UIColor colorWithWhite:.09 alpha:.92].CGColor;
    [_dial.layer addSublayer:_surface];
    for (CAShapeLayer *layer in @[_track = [CAShapeLayer layer],
                                  _fill = [CAShapeLayer layer]]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.lineWidth = 3;
        layer.lineCap = kCALineCapRound;
        [_dial.layer addSublayer:layer];
    }
    _track.strokeColor = [UIColor colorWithWhite:1 alpha:.18].CGColor;
    _fill.strokeColor = [UIColor colorWithWhite:.97 alpha:1].CGColor;
    _fill.strokeEnd = 0;

    _value = [UILabel new];
    _value.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    _value.textColor = UIColor.whiteColor;
    _value.textAlignment = NSTextAlignmentCenter;
    [_dial addSubview:_value];
    _iconTile = [UIView new];
    _iconTile.backgroundColor = [UIColor colorWithWhite:.09 alpha:1];
    _iconTile.layer.cornerRadius = 6;
    [_dial addSubview:_iconTile];
    _icon = [UIImageView new];
    _icon.tintColor = [UIColor colorWithWhite:.96 alpha:1];
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    [_iconTile addSubview:_icon];

    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOpacity = .22;
    self.layer.shadowRadius = 5;
    self.layer.shadowOffset = CGSizeMake(1, 2);
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // Only the root translates; the dial's rotation is a presentation animation.
    _dial.frame = self.bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _surface.frame = _dial.bounds;
    _surface.path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(1, 0, 52, 52)].CGPath;
    UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:CGPointMake(27, 26)
        radius:23 startAngle:2 * M_PI / 3 endAngle:7 * M_PI / 3 clockwise:YES];
    _track.frame = _dial.bounds;
    _fill.frame = _dial.bounds;
    _track.path = arc.CGPath;
    _fill.path = arc.CGPath;
    self.layer.shadowPath = _surface.path;
    [CATransaction commit];
    _value.frame = CGRectMake(7, 16, 40, 20);
    _iconTile.frame = CGRectMake(18, 39, 18, 17);
    _icon.frame = CGRectMake(3, 3, 12, 11);
}

- (void)showVolume:(float)volume previousVolume:(float)previousVolume {
    if (!isfinite(volume) || !isfinite(previousVolume)) return;
    volume = fminf(1, fmaxf(0, volume));
    previousVolume = fminf(1, fmaxf(0, previousVolume));
    NSUInteger generation = ++_dismissGeneration;
    BOOL entering = !_presented;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    _value.text = [NSString stringWithFormat:@"%ld%%", (long)lroundf(volume * 100)];
    _icon.image = [UIImage systemImageNamed:volume <= .005 ? @"speaker.slash.fill" :
        volume < .35 ? @"speaker.wave.1.fill" : @"speaker.wave.2.fill"];
    [self layoutIfNeeded];

    CGFloat from = entering ? previousVolume :
        ((CAShapeLayer *)_fill.presentationLayer ?: _fill).strokeEnd;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _fill.strokeEnd = volume;
    [CATransaction commit];
    CABasicAnimation *fill = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    fill.fromValue = @(from);
    fill.toValue = @(volume);
    fill.duration = reduceMotion ? .08 : .18;
    fill.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [_fill addAnimation:fill forKey:@"level"];

    if (!reduceMotion && fabsf(volume - previousVolume) > .001f) {
        CGFloat direction = volume > previousVolume ? 1 : -1;
        NSNumber *rotation = [_dial.layer.presentationLayer valueForKeyPath:@"transform.rotation.z"];
        CAKeyframeAnimation *spin = [CAKeyframeAnimation animationWithKeyPath:@"transform.rotation.z"];
        spin.values = @[@(rotation.doubleValue), @(direction * .14), @(direction * -.012), @0];
        spin.keyTimes = @[@0, @.25, @.72, @1];
        spin.duration = .30;
        spin.timingFunctions = @[
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
            [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
        [_dial.layer addAnimation:spin forKey:@"volumeSpin"];
    }
    // Use center/bounds, never the transformed frame, for the hidden position.
    CGFloat offscreen = -(self.center.x + CGRectGetWidth(self.bounds) / 2 + 4);
    if (entering) {
        _presented = YES;
        self.alpha = 0;
        self.transform = reduceMotion ? CGAffineTransformIdentity :
            CGAffineTransformMakeTranslation(offscreen, 0);
    }
    self.hidden = NO;
    [UIView animateWithDuration:reduceMotion ? .10 : .22 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut |
                UIViewAnimationOptionAllowUserInteraction
        animations:^{ self.alpha = 1; self.transform = CGAffineTransformIdentity; }
        completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (generation != self->_dismissGeneration) return;
        [UIView animateWithDuration:reduceMotion ? .10 : .18 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn |
                    UIViewAnimationOptionAllowUserInteraction
            animations:^{
                self.alpha = 0;
                self.transform = reduceMotion ? CGAffineTransformIdentity :
                    CGAffineTransformMakeTranslation(offscreen, 0);
            } completion:^(BOOL finished) {
                if (generation != self->_dismissGeneration) return;
                self.hidden = YES;
                self->_presented = NO;
            }];
    });
}

- (void)dismissImmediately {
    ++_dismissGeneration;
    [self.layer removeAllAnimations];
    [_dial.layer removeAllAnimations];
    [_fill removeAllAnimations];
    self.hidden = YES;
    self.alpha = 0;
    self.transform = CGAffineTransformIdentity;
    _presented = NO;
}

@end
