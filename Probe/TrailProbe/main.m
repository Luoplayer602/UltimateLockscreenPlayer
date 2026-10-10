#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <math.h>
#import "../../UI/ULPVisualizerView.h"
#import "../../Visualization/ULPTrail.h"
#import "../../Visualization/ULPVisualPreferences.h"
#import "../../Audio/ULPPreviewSpectrum.h"

@interface ULPVisualizerView (TrailProbe)
- (BOOL)prepareTrailBitmap;
- (void)captureTrailGeometry;
@end

static void savePixels(const uint8_t *data, ULPTrailBuffer *buffer, NSString *name) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CFDataRef bytes = CFDataCreate(kCFAllocatorDefault, data, buffer->width * buffer->height * 4);
    CGDataProviderRef provider = CGDataProviderCreateWithCFData(bytes);
    CGImageRef image = CGImageCreate(buffer->width, buffer->height, 8, 32, buffer->width * 4,
        space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big, provider, NULL, YES,
        kCGRenderingIntentDefault);
    if (image) {
        NSString *path = [@"/var/mobile/Library/Caches/ULP" stringByAppendingPathComponent:name];
        [UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:path atomically:YES];
        CGImageRelease(image);
    }
    CGDataProviderRelease(provider); CFRelease(bytes); CGColorSpaceRelease(space);
}

static void saveScene(ULPVisualizerView *view, ULPTrailBuffer *buffer, NSString *name) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, buffer->width, buffer->height, 8,
        buffer->width * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextTranslateCTM(context, 0, buffer->height);
    CGContextScaleCTM(context, buffer->width / view.bounds.size.width,
                              -(CGFloat)buffer->height / view.bounds.size.height);
    CGContextSetRGBFillColor(context, .06, .07, .1, 1);
    CGContextFillRect(context, view.bounds);
    [view.layer renderInContext:context];
    savePixels(CGBitmapContextGetData(context), buffer, name);
    CGContextRelease(context); CGColorSpaceRelease(space);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // Hidden window: exercises the real view/window gate without presenting
        // UI or attaching to SpringBoard's visible hierarchy.
        __attribute__((objc_precise_lifetime)) UIWindow *window =
            [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 375, 667)];
        ULPVisualizerView *view = [[ULPVisualizerView alloc] initWithFrame:CGRectMake(0, 0, 375, 667)];
        [window addSubview:view];
        ULPVisualConfig loaded = ULPLoadVisualPreferences();
        printf("stored mode=%s trail=%d length=%.3f opacity=%.3f\n",
            ULPVisualModeID(loaded.mode), loaded.trailEnabled, loaded.trailDuration, loaded.trailOpacity);
        ULPVisualConfig config = ULPVisualConfigDefaultForMode(ULPVisualModeWave);
        config.trailEnabled = true; config.trailDuration = 2; config.trailOpacity = 1; config.glow = 0;
        BOOL audioTest = argc > 1 && !strcmp(argv[1], "--audio");
        AVAudioFile *file = nil;
        AVAudioPCMBuffer *audio = nil;
        if (audioTest) {
            NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:
                @"/var/jb/var/mobile/Library/Preferences/com.luoplayer.ultimatelockscreenplayer.plist"];
            config.trailDuration = [values[@"v1.waveform.TrailDuration"] floatValue];
            config.trailOpacity = [values[@"v1.waveform.TrailOpacity"] floatValue];
            config.smoothCurve = [values[@"v1.waveform.SmoothCurve"] boolValue];
            config.points = [values[@"v1.waveform.VisualPoints"] intValue];
            file = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:
                @"/var/jb/Library/PreferenceBundles/ULPPreferences.bundle/inst.wav"] error:nil];
            audio = [[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:1024];
            if (!file || !audio) { puts("FAIL reading installed inst.wav"); return 4; }
        }
        view.visualConfig = config;
        [view setArtwork:nil manualColor:UIColor.whiteColor];
        [view layoutIfNeeded];
        if (![view prepareTrailBitmap]) { puts("FAIL prepare bitmap"); return 2; }
        Ivar ivar = class_getInstanceVariable(view.class, "_trail");
        ULPTrailBuffer *buffer = (ULPTrailBuffer *)((uint8_t *)(__bridge void *)view + ivar_getOffset(ivar));
        unsigned steps = audioTest ? 180 : 5;
        double totalCPU = 0, maxCPU = 0;
        for (unsigned step = 0; step < steps; ++step) {
            ULPMSH2FeatureFrame frame = {0};
            frame.featureMask = ULP_MSH2_WAVEFORM | ULP_MSH2_SPECTRUM;
            frame.sampleRate = 44100;
            if (audioTest) {
                file.framePosition = file.processingFormat.sampleRate * (1 + step / 60.0);
                if (![file readIntoBuffer:audio frameCount:1024 error:nil] || audio.frameLength < 1024) return 5;
                frame.sampleRate = file.processingFormat.sampleRate;
                const float *samples = audio.floatChannelData[0];
                ULPPreviewSpectrum(samples, 1024, frame.sampleRate, frame.spectrum);
                for (unsigned i = 0; i < 64; ++i) frame.waveform[i] = samples[i * 16];
            } else for (unsigned i = 0; i < 64; ++i)
                frame.waveform[i] = .6f * sinf(i * .3f + step * 1.0f);
            double start = CACurrentMediaTime();
            [view updateAudio:frame zoomLevel:0];
            double cpu = CACurrentMediaTime() - start;
            totalCPU += cpu; maxCPU = MAX(maxCPU, cpu);
            if (!buffer->history) { puts("FAIL live pipeline has no history"); return 3; }
            size_t current = 0, old = 0; unsigned maxAlpha = 0;
            for (size_t i = 0; i < buffer->width * buffer->height; ++i) {
                unsigned alpha = buffer->current[i * 4 + 3];
                if (alpha) ++current;
                if (buffer->output[i * 4 + 3]) ++old;
                maxAlpha = MAX(maxAlpha, alpha);
            }
            printf("step=%u bitmap=%zux%zu current=%zu trail=%zu maxAlpha=%u\n",
                   step, buffer->width, buffer->height, current, old, maxAlpha);
            if (step + 1 == steps) {
                savePixels(buffer->current, buffer, @"trail-probe-current.png");
                savePixels(buffer->output, buffer, @"trail-probe-output.png");
                Ivar layerIvar = class_getInstanceVariable(view.class, "_trailLayer");
                CALayer *layer = object_getIvar(view, layerIvar);
                printf("layerFrame=%s hidden=%d opacity=%.2f contents=%d siblings=%lu\n",
                    NSStringFromCGRect(layer.frame).UTF8String, layer.hidden, layer.opacity,
                    layer.contents != nil, (unsigned long)view.layer.sublayers.count);
                saveScene(view, buffer, @"trail-probe-scene-on.png");
                layer.hidden = YES;
                saveScene(view, buffer, @"trail-probe-scene-off.png");
            }
            usleep(audioTest ? 17000 : 40000);
        }
        printf("render mean=%.2fms max=%.2fms length=%.3f opacity=%.3f\n",
            totalCPU * 1000 / steps, maxCPU * 1000, config.trailDuration, config.trailOpacity);
        [view resetTrail];
    }
    return 0;
}
