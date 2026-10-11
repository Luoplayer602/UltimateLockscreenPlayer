#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <assert.h>
#import <unistd.h>
#import "../../UI/ULPVisualizerView.h"
#import "../../UI/ULPCoverView.h"
#import "../../Visualization/ULPCover.h"
#import "../../Audio/ULPPreviewSpectrum.h"

@interface ULPVisualizerView (CaptureBudgetProbe)
- (NSUInteger)drawingFramesPerSecond;
@end
@interface CaptureBudgetView : ULPVisualizerView
@property BOOL simulateCapture;
@end
@implementation CaptureBudgetView
- (NSUInteger)drawingFramesPerSecond {
    return ULPVisualDrawingFPS(self.visualConfig.framesPerSecond, self.simulateCapture);
}
@end

static id child(id object, const char *name) {
    return object_getIvar(object, class_getInstanceVariable([object class], name));
}
static double haloOpacity(ULPCoverView *cover) {
    double sum=0;
    for(CALayer *layer in child(cover,"_haloLayers")) if(layer.contents) sum+=layer.opacity;
    return sum;
}
static NSArray *haloContents(ULPCoverView *cover) {
    NSMutableArray *contents=[NSMutableArray array];
    for(CALayer *layer in child(cover,"_haloLayers")) {
        if(layer.contents) {
            CGImageRef image=(__bridge CGImageRef)layer.contents;
            assert(CGImageGetWidth(image)<=512 && CGImageGetHeight(image)<=512);
            [contents addObject:layer.contents];
        }
    }
    return contents;
}
static void waitHalo(ULPCoverView *cover) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while(![[cover valueForKey:@"haloCacheValid"] boolValue] && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    assert(haloContents(cover).count==5);
}
static void capture(UIView *view, NSString *name) {
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, YES, 1);
    [[UIColor colorWithRed:.06 green:.07 blue:.1 alpha:1] setFill]; UIRectFill(view.bounds);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    NSString *path=[@"/var/mobile/Library/Caches/ULP" stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES];
    UIGraphicsEndImageContext();
}
static UIImage *artwork(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(200,200),YES,1);
    [UIColor.systemIndigoColor setFill]; UIRectFill(CGRectMake(0,0,200,200));
    [UIColor.systemPinkColor setFill]; UIRectFill(CGRectMake(0,0,100,200));
    [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(45,25,110,35));
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();return image;
}
static void run(CGSize size, NSString *suffix) {
    __attribute__((objc_precise_lifetime)) UIWindow *window=[[UIWindow alloc] initWithFrame:(CGRect){CGPointZero,size}];
    ULPVisualizerView *view=[[ULPVisualizerView alloc] initWithFrame:window.bounds];[window addSubview:view];
    ULPVisualConfig c=ULPVisualConfigDefaultForMode(ULPVisualModeWave);
    c.glow=0; c.coverMode=ULPCoverModeArtwork;c.coverGlow=0;
    c.coverReaction=.8;c.coverSpin=30;c.visualReactType=ULPReactBeat;
    [view setArtwork:artwork() manualColor:UIColor.whiteColor];
    ULPCoverView *cover=child(view,"_cover");
    CAGradientLayer *flash=child(cover,"_flash");
    UIView *rotor=child(cover,"_rotor");
    const char *names[]={"swell","flash","shake","spin","bounce","wobble"};
    for(int type=0;type<6;++type) {
        c.beatMotion=type;view.visualConfig=c;[view layoutIfNeeded];[cover resetMotion];
        double time=CACurrentMediaTime();
        [cover triggerBeat:1 atTime:time];[cover updateReactionAtTime:time+.055 rawLevel:0];
        assert(!CGAffineTransformIsIdentity(cover.transform) || flash.opacity>0);
        if(type==ULPBeatMotionFlash) assert(CGAffineTransformIsIdentity(cover.transform) && flash.opacity>.1);
        if(type==ULPBeatMotionSpin) assert(cover.transform.b>0 && hypot(cover.transform.a,cover.transform.b)>1);
        capture(view,[NSString stringWithFormat:@"beat-%s-%@.png",names[type],suffix]);
        [cover updateReactionAtTime:time+1 rawLevel:0];
        assert(CGAffineTransformIsIdentity(cover.transform) && flash.opacity==0);
        assert(![cover hasReactionAtTime:time+1]);
    }
    c.coverReactType=ULPReactRaw;view.visualConfig=c;
    [cover updateReactionAtTime:1 rawLevel:1]; assert(cover.transform.a>1.4 && flash.opacity==0);
    [cover updateReactionAtTime:2 rawLevel:0]; assert(CGAffineTransformIsIdentity(cover.transform));
    // Feed through the actual renderer, including the FPS gate and pause timer.
    c.coverReactType=ULPReactBeat;c.beatMotion=ULPBeatMotionBounce;c.framesPerSecond=15;
    view.visualConfig=c;[view layoutIfNeeded];view.playbackActive=YES;
    ULPMSH2FeatureFrame f={.featureMask=ULP_MSH2_WAVEFORM|ULP_MSH2_SPECTRUM,.sampleRate=44100,.rms=.1};
    for(int i=0;i<35;++i) {
        for(int j=0;j<64;++j) f.spectrum[j]=j<15 ? (i==28 ? .9 : .1) : .35;
        [view updateAudio:f zoomLevel:.5];usleep(17000);
    }
    assert(view.beatStatus.count>0);
    assert(!CGAffineTransformIsIdentity(cover.transform));
    CGAffineTransform rotation=rotor.transform;
    view.playbackActive=NO;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.4]];
    assert(CGAffineTransformIsIdentity(cover.transform) && flash.opacity==0);
    assert(CGAffineTransformEqualToTransform(rotation,rotor.transform));
    assert(child(view,"_reactionTimer")==nil);
    // Ambient effects must work with CoverReaction=0, without requiring a hit.
    c.coverReaction=0;c.coverRumble=.2;c.coverGlowPulse=1.5;c.coverReactType=ULPReactRaw;
    c.coverGlow=.2;view.visualConfig=c;[view layoutIfNeeded];waitHalo(cover);[cover resetReaction];
    double time=CACurrentMediaTime();
    [cover updateReactionAtTime:time+.25 rawLevel:1 beatLevel:0];
    ULPCoverAmbient ambient=ULPCoverAmbientEvaluate(c,time+.25,1,1);
    assert(fabs(cover.transform.tx-ambient.x*size.width/400)<1e-5);
    assert(fabs(cover.transform.ty-ambient.y*size.width/400)<1e-5);
    assert(cover.transform.a==1 && cover.transform.b==0 && flash.opacity==0);
    assert(cover.layer.shadowOpacity==0 && haloOpacity(cover)>.8);
    NSArray *textures=haloContents(cover);assert(textures.count==5);
    NSNumber *generation=[cover valueForKey:@"haloTextureGeneration"];
    for(int i=0;i<120;++i) [cover updateReactionAtTime:time+.3+i/60.0 rawLevel:i%2 beatLevel:0];
    c.coverGlow=.3;c.coverGlowPulse=.8;view.visualConfig=c;[view layoutIfNeeded];
    assert([textures isEqualToArray:haloContents(cover)]);
    assert([generation isEqual:[cover valueForKey:@"haloTextureGeneration"]]);
    c.coverGlow=.2;c.coverGlowPulse=1.5;view.visualConfig=c;[cover resetReaction];
    [cover updateReactionAtTime:time+3 rawLevel:1 beatLevel:0];
    capture(view,[NSString stringWithFormat:@"ambient-raw-%@.png",suffix]);
    c.coverRumble=0;c.coverReactType=ULPReactBeat;view.visualConfig=c;[cover resetReaction];
    time=CACurrentMediaTime();
    [cover updateReactionAtTime:time+.25 rawLevel:1 beatLevel:0];
    assert(fabs(haloOpacity(cover)-c.coverGlow)<1e-5);
    [cover updateReactionAtTime:time+.5 rawLevel:0 beatLevel:1];
    assert(haloOpacity(cover)>.8 && flash.opacity==0);
    capture(view,[NSString stringWithFormat:@"ambient-beat-%@.png",suffix]);
    // Silent Drift reuses the idle timer, continues on Pause and stops hidden.
    c.coverGlowPulse=0;c.coverDrift=.2;view.visualConfig=c;[cover resetReaction];
    CGAffineTransform before=cover.transform;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.7]];
    assert(!CGAffineTransformEqualToTransform(before,cover.transform));
    assert(child(view,"_reactionTimer")!=nil);
    assert(CGAffineTransformEqualToTransform(rotation,rotor.transform));
    c.coverDrift=0;view.visualConfig=c;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
    assert(CGAffineTransformIsIdentity(cover.transform));
    assert(child(view,"_reactionTimer")==nil);
    c.coverDrift=.2;view.visualConfig=c;assert(child(view,"_reactionTimer")!=nil);
    c.coverMode=ULPCoverModeOff;view.visualConfig=c;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    assert(cover.hidden && child(view,"_reactionTimer")==nil);
    c.coverMode=ULPCoverModeArtwork;view.visualConfig=c;
    assert(!cover.hidden && child(view,"_reactionTimer")!=nil);
    c.coverGlowPulse=1.5;view.visualConfig=c;waitHalo(cover);
    // Change style during a pending worker, then hide. Its completion must not
    // resurrect textures; returning uses only the latest colour and geometry.
    c.coverOutlineColor=0x33AA77;view.visualConfig=c;
    c.coverOutlineColor=0x7733AA;c.coverSize=.51;view.visualConfig=c;[view layoutIfNeeded];
    view.hidden=YES;assert(view.beatStatus.count==0);
    assert(haloContents(cover).count==0);
    assert(child(view,"_reactionTimer")==nil);
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    assert(haloContents(cover).count==0);
    view.hidden=NO;assert(child(view,"_reactionTimer")!=nil);
    waitHalo(cover);
    assert([[cover valueForKey:@"haloCacheColor"] unsignedIntValue]==c.coverOutlineColor);
    assert(haloContents(cover).count==5);
    [view removeFromSuperview];assert(child(view,"_reactionTimer")==nil);
    assert(haloContents(cover).count==0);
    printf("PASS %s: six Beat motions, rumble, Raw/Beat cached halo, silent Drift, pause spin, timer/texture cleanup\n",suffix.UTF8String);
}
static void captureBudget(void) {
    __attribute__((objc_precise_lifetime)) UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,375,667)];
    CaptureBudgetView *view=[[CaptureBudgetView alloc] initWithFrame:window.bounds];[window addSubview:view];
    ULPVisualConfig c=ULPVisualConfigDefaultForMode(ULPVisualModeBar);
    c.framesPerSecond=60;c.visualReactType=ULPReactBeat;
    c.coverMode=ULPCoverModeArtwork;c.coverReaction=.8;c.coverReactType=ULPReactBeat;
    view.visualConfig=c;[view layoutIfNeeded];view.playbackActive=YES;
    ULPMSH2FeatureFrame f={.featureMask=ULP_MSH2_SPECTRUM|ULP_MSH2_WAVEFORM,.sampleRate=44100,.rms=.1};
    for(int phase=0;phase<2;++phase) {
        view.simulateCapture=phase==0;[view resetCoverMotion];
        unsigned drawn=0;
        for(int i=0;i<60;++i) {
            for(int j=0;j<64;++j) f.spectrum[j]=j<15 ? (i==28 ? .9 : .1) : .35;
            double before=[[view valueForKey:@"lastFrameTime"] doubleValue];
            [view updateAudio:f zoomLevel:.5];
            if([[view valueForKey:@"lastFrameTime"] doubleValue]!=before)++drawn;
            usleep(17000);
        }
        assert(view.beatStatus.count>0);
        if(view.simulateCapture) assert(drawn>=26 && drawn<=35);
        else assert(drawn>=53);
        printf("PASS capture=%d accepted_draws=%u/60 Beat_count=%llu\n",view.simulateCapture,drawn,(unsigned long long)view.beatStatus.count);
    }
    [view removeFromSuperview];
}
static void audio(void) {
    AVAudioFile *file=[[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:
        @"/var/jb/Library/PreferenceBundles/ULPPreferences.bundle/inst.wav"] error:nil];assert(file);
    AVAudioPCMBuffer *buf=[[AVAudioPCMBuffer alloc] initWithPCMFormat:file.processingFormat frameCapacity:1024];
    ULPBeatState s={0};ULPVisualConfig c=ULPVisualConfigDefault();
    double rate=file.processingFormat.sampleRate, seconds=MIN(30,file.length/rate-.1);
    for(int i=0;i<seconds*60;++i) {
        double time=i/60.0;file.framePosition=MAX(0,(AVAudioFramePosition)(time*rate)-1024);
        assert([file readIntoBuffer:buf frameCount:1024 error:nil]);
        const float *samples=buf.floatChannelData[0];float sum=0;
        for(unsigned j=0;j<buf.frameLength;++j)sum+=samples[j]*samples[j];
        ULPMSH2FeatureFrame f={.featureMask=ULP_MSH2_SPECTRUM,.sampleRate=rate,.rms=sqrtf(sum/buf.frameLength)};
        ULPPreviewSpectrum(samples,buf.frameLength,rate,f.spectrum);
        ULPBeatResult beat=ULPBeatProcess(&s,&f,time,c);
        assert(isfinite(beat.pulse+beat.score));
        if(beat.hit && beat.count<=8)printf("inst.wav onset %.3f score %.2f\n",time,beat.score);
    }
    assert(s.count>0);
    printf("inst.wav: %llu detected onsets over %.1f s (not a beat accuracy measurement)\n",(unsigned long long)s.count,seconds);
}
int main(void) {
    @autoreleasepool { run(CGSizeMake(375,667),@"lockscreen");run(CGSizeMake(343,184),@"preview");captureBudget();audio();puts("BeatProbe OK"); }
    return 0;
}
