#import "ULPVisualizerPreviewController.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <dlfcn.h>
#import <math.h>

#import "../UI/ULPVisualizerView.h"
#import "../Visualization/ULPVisualPreferences.h"
#import "../Visualization/ULPSignal.h"

typedef void (*ULPGetPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*ULPGetInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*ULPSendCommand)(NSInteger, NSDictionary *);

@interface ULPVisualizerPreviewController () {
    UIView *_previewSurface;
    CAGradientLayer *_previewGradient;
    UILabel *_compactCaption;
    ULPVisualizerView *_visualizer;
    UIButton *_playButton;
    UILabel *_message;
    AVAudioPlayer *_player;
    AVAudioFile *_analysisFile;
    AVAudioPCMBuffer *_analysisBuffer;
    CADisplayLink *_displayLink;
    CFTimeInterval _lastPreferenceRead;
    ULPVisualConfig _config;
    ULPSignalState _signal;
    void *_mediaRemote;
    ULPGetPlaying _getPlaying;
    ULPGetInfo _getInfo;
    ULPSendCommand _sendCommand;
    BOOL _wasPlayingExternally;
    BOOL _starting;
    NSString *_externalTitle;
    NSUInteger _requestGeneration;
}
@end

@implementation ULPVisualizerPreviewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Preview";
    self.view.backgroundColor = self.compact ? UIColor.clearColor :
        [UIColor colorWithRed:0.06 green:0.07 blue:0.10 alpha:1];

    _previewSurface = [UIView new];
    _previewSurface.backgroundColor = [UIColor colorWithRed:0.15 green:0.17 blue:0.24 alpha:1];
    _previewSurface.layer.cornerRadius = 22;
    _previewSurface.clipsToBounds = YES;
    [self.view addSubview:_previewSurface];

    _previewGradient = [CAGradientLayer layer];
    _previewGradient.colors = @[(id)[UIColor colorWithRed:0.16 green:0.20 blue:0.29 alpha:1].CGColor,
                                (id)[UIColor colorWithRed:0.10 green:0.11 blue:0.17 alpha:1].CGColor];
    _previewGradient.startPoint = CGPointMake(0, 0);
    _previewGradient.endPoint = CGPointMake(1, 1);
    [_previewSurface.layer addSublayer:_previewGradient];

    _visualizer = [[ULPVisualizerView alloc] initWithFrame:CGRectZero];
    [_previewSurface addSubview:_visualizer];

    if (self.compact) {
        _compactCaption = [UILabel new];
        _compactCaption.text = @"PREVIEW · INST.WAV";
        _compactCaption.textColor = [UIColor colorWithWhite:1 alpha:0.66];
        _compactCaption.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightSemibold];
        [_previewSurface addSubview:_compactCaption];
    }

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.44];
    _playButton.layer.cornerRadius = 30;
    _playButton.titleLabel.font = [UIFont boldSystemFontOfSize:27];
    [_playButton setTitle:@"▶" forState:UIControlStateNormal];
    [_playButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [_playButton addTarget:self action:@selector(togglePreview) forControlEvents:UIControlEventTouchUpInside];
    [_previewSurface addSubview:_playButton];
    if (self.compact) {
        UITapGestureRecognizer *reveal = [[UITapGestureRecognizer alloc]
            initWithTarget:self action:@selector(revealCompactControls)];
        reveal.cancelsTouchesInView = NO;
        [_previewSurface addGestureRecognizer:reveal];
    }

    _message = [UILabel new];
    _message.textColor = [UIColor colorWithWhite:0.86 alpha:1];
    _message.font = [UIFont systemFontOfSize:13];
    _message.numberOfLines = 2;
    _message.textAlignment = NSTextAlignmentCenter;
    _message.text = @"Nhấn Play để phát lặp inst.wav";
    [self.view addSubview:_message];
    _message.hidden = self.compact;

    NSURL *audioURL = [[NSBundle bundleForClass:self.class] URLForResource:@"inst" withExtension:@"wav"];
    NSError *error = nil;
    if (audioURL) {
        _player = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:&error];
        _player.numberOfLoops = -1;
        _analysisFile = [[AVAudioFile alloc] initForReading:audioURL error:&error];
        if (_analysisFile)
            _analysisBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_analysisFile.processingFormat
                                                             frameCapacity:1024];
    }
    if (!_player || !_analysisBuffer) {
        _playButton.enabled = NO;
        _message.text = @"Không đọc được inst.wav trong gói ULP.";
    }
    _mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                         RTLD_LAZY | RTLD_LOCAL);
    if (_mediaRemote) {
        _getPlaying = (ULPGetPlaying)dlsym(_mediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        _getInfo = (ULPGetInfo)dlsym(_mediaRemote, "MRMediaRemoteGetNowPlayingInfo");
        _sendCommand = (ULPSendCommand)dlsym(_mediaRemote, "MRMediaRemoteSendCommand");
    }
    ULPSignalInit(&_signal);
    [self refreshVisualPreferences];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = CGRectGetWidth(self.view.bounds);
    CGFloat height = CGRectGetHeight(self.view.bounds);
    if (self.compact) {
        _previewSurface.frame = CGRectMake(0, 0, width, height);
        _previewGradient.frame = _previewSurface.bounds;
        _previewSurface.layer.cornerRadius = 16;
        _visualizer.frame = _previewSurface.bounds;
        _compactCaption.frame = CGRectMake(17, 13, width - 34, 16);
        _playButton.frame = CGRectMake(width - 56, height - 56, 42, 42);
        _playButton.layer.cornerRadius = 21;
        _playButton.titleLabel.font = [UIFont boldSystemFontOfSize:21];
        _message.frame = CGRectZero;
        return;
    }
    CGFloat top = MAX(18, self.view.safeAreaInsets.top + 12);
    CGFloat panelHeight = MIN(410, MAX(250, height * 0.66));
    _previewSurface.frame = CGRectMake(16, top, width - 32, panelHeight);
    _previewGradient.frame = _previewSurface.bounds;
    _visualizer.frame = _previewSurface.bounds;
    _playButton.frame = CGRectMake((width - 32 - 60) / 2,
                                   panelHeight * 0.42 - 30, 60, 60);
    _message.frame = CGRectMake(22, CGRectGetMaxY(_previewSurface.frame) + 18,
                                width - 44, 48);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startPreviewRendering];
}

- (void)startPreviewRendering {
    [self refreshVisualPreferences];
    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayTick)];
        _displayLink.preferredFramesPerSecond = _config.framesPerSecond;
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopPreviewRendering];
}

- (void)stopPreviewRendering {
    [self stopPreview];
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)dealloc {
    [_displayLink invalidate];
    [_player stop];
    if (_mediaRemote) dlclose(_mediaRemote);
}

- (void)refreshVisualPreferences {
    _config = ULPLoadVisualPreferences();
    _signal.visual.firstBand = _config.firstBand;
    _signal.visual.lastBand = _config.lastBand;
    _signal.zoom.firstBand = _config.zoomFirstBand;
    _signal.zoom.lastBand = _config.zoomLastBand;
    _visualizer.visualConfig = _config;
    [_visualizer setArtwork:nil manualColor:ULPLoadVisualManualColor()];
    _visualizer.hidden = !_config.enabled;
    _displayLink.preferredFramesPerSecond = _config.framesPerSecond;
    _lastPreferenceRead = CACurrentMediaTime();
}

- (NSString *)titleFromInfo:(CFDictionaryRef)rawInfo {
    if (!_mediaRemote || !rawInfo) return nil;
    CFStringRef *key = (CFStringRef *)dlsym(_mediaRemote, "kMRMediaRemoteNowPlayingInfoTitle");
    NSDictionary *info = (__bridge NSDictionary *)rawInfo;
    id title = key && *key ? info[(__bridge NSString *)*key] : nil;
    return [title isKindOfClass:[NSString class]] ? title : nil;
}

- (void)togglePreview {
    if (_player.isPlaying) [self stopPreview];
    else [self startPreview];
}

- (void)revealCompactControls {
    if (!self.compact || !_player.isPlaying) return;
    _playButton.hidden = NO;
    NSUInteger generation = _requestGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (self && self->_requestGeneration == generation && self->_player.isPlaying)
            self->_playButton.hidden = YES;
    });
}

- (void)startPreview {
    if (!_player || !_analysisBuffer) return;
    NSUInteger generation = ++_requestGeneration;
    _starting = YES;
    _playButton.enabled = NO;
    _wasPlayingExternally = NO;
    _externalTitle = nil;
    __weak typeof(self) weakSelf = self;
    void (^beginAudio)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self->_requestGeneration != generation || !self.view.window) return;
        AVAudioSession *session = AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
        [session setActive:YES error:nil];
        [self->_player play];
        self->_starting = NO;
        self->_playButton.enabled = YES;
        [self->_playButton setTitle:@"Ⅱ" forState:UIControlStateNormal];
        self->_playButton.hidden = self.compact;
        self->_message.text = @"inst.wav · phát lặp · nhấn Pause để dừng";
    };
    if (!_getPlaying || !_sendCommand) {
        beginAudio();
        return;
    }
    void (^queryPlaying)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self->_requestGeneration != generation) return;
        self->_getPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            if (self->_requestGeneration != generation) return;
            self->_wasPlayingExternally = playing;
            if (playing) self->_sendCommand(1, nil); // MediaRemote pause.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 150),
                           dispatch_get_main_queue(), beginAudio);
        });
    };
    if (_getInfo) {
        _getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self->_requestGeneration != generation) return;
            self->_externalTitle = [self titleFromInfo:info];
            queryPlaying();
        });
    } else queryPlaying();
}

- (void)stopPreview {
    ++_requestGeneration;
    BOOL didPlay = _player.isPlaying;
    BOOL pausedExternal = _wasPlayingExternally;
    _starting = NO;
    _playButton.enabled = YES;
    [_player stop];
    _player.currentTime = 0;
    [_playButton setTitle:@"▶" forState:UIControlStateNormal];
    _playButton.hidden = NO;
    _message.text = @"Nhấn Play để phát lặp inst.wav";
    if (didPlay)
        [AVAudioSession.sharedInstance setActive:NO
                                     withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                           error:nil];
    if (!pausedExternal || !_getPlaying || !_sendCommand) return;
    _wasPlayingExternally = NO;
    NSString *expectedTitle = _externalTitle;
    __weak typeof(self) weakSelf = self;
    void (^resumeIfPaused)(void) = ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self->_getPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            if (!playing) self->_sendCommand(0, nil); // MediaRemote play.
        });
    };
    if (_getInfo && expectedTitle.length) {
        _getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self && [[self titleFromInfo:info] isEqualToString:expectedTitle])
                resumeIfPaused();
        });
    } else resumeIfPaused();
}

- (void)displayTick {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - _lastPreferenceRead >= 1) [self refreshVisualPreferences];
    if (!_player.isPlaying || !_analysisFile || !_analysisBuffer) return;
    AVAudioFramePosition position = (AVAudioFramePosition)(_player.currentTime *
                                                            _analysisFile.processingFormat.sampleRate);
    _analysisFile.framePosition = position;
    NSError *error = nil;
    if (![_analysisFile readIntoBuffer:_analysisBuffer frameCount:1024 error:&error] ||
        _analysisBuffer.frameLength < 512 || !_analysisBuffer.floatChannelData) return;

    const float *samples = _analysisBuffer.floatChannelData[0];
    ULPMSH2FeatureFrame frame = {0};
    frame.featureMask = ULP_MSH2_SPECTRUM | ULP_MSH2_WAVEFORM;
    frame.sampleRate = _analysisFile.processingFormat.sampleRate;
    NSUInteger sampleCount = _analysisBuffer.frameLength;
    float total = 0;
    for (NSUInteger i = 0; i < sampleCount; ++i) total += samples[i] * samples[i];
    frame.rms = sqrtf(total / sampleCount);
    for (NSUInteger band = 0; band < 64; ++band) {
        float frequency = 45.0f * powf(1.1f, band);
        float coefficient = 2 * cosf(2 * (float)M_PI * frequency / frame.sampleRate);
        float first = 0, second = 0;
        for (NSUInteger i = 0; i < sampleCount; ++i) {
            float next = samples[i] + coefficient * first - second;
            second = first;
            first = next;
        }
        float power = MAX(0, first * first + second * second - coefficient * first * second);
        frame.spectrum[band] = MIN(1, sqrtf(power) * 24 / sampleCount);
        frame.waveform[band] = samples[band * (sampleCount - 1) / 63];
    }
    ULPSignalProcess(&_signal, &frame);
    [_visualizer updateAudio:frame zoomLevel:_signal.zoomLevel];
}

@end
