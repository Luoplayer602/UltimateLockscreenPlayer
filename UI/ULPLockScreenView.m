#import "ULPLockScreenView.h"

#import <QuartzCore/QuartzCore.h>
#import <math.h>

static void ULPFindArtworkInView(UIView *view, UIView *host, UIView *excluded,
                                 CGFloat width, CGFloat height,
                                 UIImage **best, CGFloat *bestScore) {
    if (view == excluded) return;
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        UIImage *image = imageView.image;
        CGRect rect = [view convertRect:view.bounds toView:host];
        CGFloat side = MIN(rect.size.width, rect.size.height);
        CGFloat aspect = rect.size.height > 0 ? rect.size.width / rect.size.height : 0;
        BOOL artworkView = NO;
        for (UIView *ancestor = view.superview; ancestor && ancestor != host; ancestor = ancestor.superview)
            if ([NSStringFromClass(ancestor.class) isEqualToString:@"MRUArtworkView"])
                artworkView = YES;
        if (image && ((artworkView && side >= 40) ||
                      (side >= 58 && side <= 310 && aspect > 0.85 && aspect < 1.15)) &&
            rect.origin.x < width * 0.6 && rect.origin.y >= -10 &&
            rect.origin.y < height * 0.9) {
            CGFloat score = (artworkView ? 1000 : 0) + side - rect.origin.x * 0.12;
            if (score > *bestScore) { *bestScore = score; *best = image; }
        }
    }
    for (UIView *child in view.subviews)
        ULPFindArtworkInView(child, host, excluded, width, height, best, bestScore);
}

@interface ULPLockScreenView () <UIGestureRecognizerDelegate> {
    UIView *_card;
    UIImageView *_thumbnail;
    UILabel *_title;
    UILabel *_artist;
    UIButton *_previous;
    UIButton *_playPause;
    UIButton *_next;
    CAShapeLayer *_trackTop;
    CAShapeLayer *_trackBottom;
    CAShapeLayer *_progressTop;
    CAShapeLayer *_progressBottom;
    UIImage *_lastArtwork;
    NSString *_artworkTrackKey;
}
@end

@implementation ULPLockScreenView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _card = [[UIView alloc] initWithFrame:CGRectZero];
    _card.backgroundColor = [[UIColor colorWithRed:0.07 green:0.10 blue:0.11 alpha:1] colorWithAlphaComponent:0.86];
    _card.layer.cornerRadius = 20;
    _card.layer.masksToBounds = NO;
    _card.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.22].CGColor;
    _card.layer.borderWidth = 1;
    [self addSubview:_card];
    UITapGestureRecognizer *openTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                            action:@selector(openSourceTapped:)];
    openTap.delegate = self;
    openTap.cancelsTouchesInView = NO;
    [_card addGestureRecognizer:openTap];

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

    for (CAShapeLayer *layer in @[_trackTop = [CAShapeLayer layer],
                                  _trackBottom = [CAShapeLayer layer]]) {
        layer.fillColor = UIColor.clearColor.CGColor;
        layer.strokeColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
        layer.lineWidth = 1;
        [_card.layer addSublayer:layer];
    }
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

- (void)openSourceTapped:(UITapGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateRecognized && self.openSourceHandler)
        self.openSourceHandler();
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    for (UIView *view = touch.view; view && view != _card; view = view.superview)
        if ([view isKindOfClass:[UIButton class]]) return NO;
    return YES;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;
    UIView *target = [super hitTest:point withEvent:event];
    if ([target isKindOfClass:[UIButton class]]) return target;
    for (UIView *view = target; view && view != self; view = view.superview)
        if (view == _card) return target;
    return nil;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat scale = MAX(0.7, width / 375.0);
    CGFloat cardHeight = 124 * scale;

    CGFloat cardWidth = width - 20 * scale;
    _card.frame = CGRectMake(10 * scale, height - cardHeight - 6 * scale, cardWidth, cardHeight);
    _card.layer.cornerRadius = 20 * scale;
    _thumbnail.frame = CGRectMake(15 * scale, 15 * scale, 94 * scale, 94 * scale);
    _thumbnail.layer.cornerRadius = 12 * scale;
    CGFloat textX = 123 * scale;
    CGFloat available = cardWidth - textX - 14 * scale;
    _title.frame = CGRectMake(textX, 18 * scale, available, 24 * scale);
    _artist.frame = CGRectMake(textX, 44 * scale, available, 20 * scale);
    _title.font = [UIFont boldSystemFontOfSize:16 * scale];
    _artist.font = [UIFont systemFontOfSize:13 * scale];
    CGFloat controlWidth = available / 3;
    _previous.frame = CGRectMake(textX, 73 * scale, controlWidth, 40 * scale);
    _playPause.frame = CGRectMake(textX + controlWidth, 73 * scale, controlWidth, 40 * scale);
    _next.frame = CGRectMake(textX + 2 * controlWidth, 73 * scale, controlWidth, 40 * scale);
    for (UIButton *button in @[_previous, _playPause, _next])
        button.titleLabel.font = [UIFont boldSystemFontOfSize:19 * scale];

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
    _trackTop.path = upper.CGPath;
    UIBezierPath *lower = [UIBezierPath bezierPath];
    [lower moveToPoint:CGPointMake(left, cardHeight / 2)];
    [lower addLineToPoint:CGPointMake(left, bottom - radius)];
    [lower addQuadCurveToPoint:CGPointMake(left + radius, bottom) controlPoint:CGPointMake(left, bottom)];
    [lower addLineToPoint:CGPointMake(right - radius, bottom)];
    [lower addQuadCurveToPoint:CGPointMake(right, bottom - radius) controlPoint:CGPointMake(right, bottom)];
    [lower addLineToPoint:CGPointMake(right, cardHeight / 2)];
    _progressBottom.path = lower.CGPath;
    _trackBottom.path = lower.CGPath;
    _progressTop.lineWidth = 2 * scale;
    _progressBottom.lineWidth = 2 * scale;
}

- (void)updateNowPlaying:(ULPNowPlayingSnapshot *)snapshot {
    _title.text = snapshot.title.length ? snapshot.title : @"Đang phát";
    _artist.text = snapshot.artist.length ? snapshot.artist : @"";
    NSString *trackKey = [NSString stringWithFormat:@"%d|%@|%@|%.0f",
                          snapshot.processID, snapshot.title ?: @"",
                          snapshot.artist ?: @"", snapshot.duration];
    if (![_artworkTrackKey isEqualToString:trackKey]) {
        _artworkTrackKey = trackKey;
        _lastArtwork = nil;
        _thumbnail.image = nil;
        if (self.artworkHandler) self.artworkHandler(nil);
    }
    UIImage *artwork = snapshot.artworkImage;
    if (!artwork && snapshot.artworkData.length)
        artwork = [UIImage imageWithData:snapshot.artworkData];
    if (!artwork) artwork = [self findSystemArtwork];
    if (artwork) {
        if (artwork != _lastArtwork) {
            _lastArtwork = artwork;
            if (self.artworkHandler) self.artworkHandler(artwork);
        }
        _thumbnail.image = artwork;
    }
    [_playPause setTitle:snapshot.playing ? @"Ⅱ" : @"▶" forState:UIControlStateNormal];
    CGFloat progress = snapshot.duration > 0 ? snapshot.elapsed / snapshot.duration : 0;
    if (!isfinite(progress)) progress = 0;
    progress = MIN(1, MAX(0, progress));
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.9];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
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

@end
