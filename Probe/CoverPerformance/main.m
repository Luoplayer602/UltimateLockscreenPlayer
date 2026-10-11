#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <assert.h>
#import "../../UI/ULPCoverView.h"

static int ascending(const void *a, const void *b) {
    double x=*(const double *)a, y=*(const double *)b;
    return (x>y)-(x<y);
}

static void run(NSString *tag, float glowPulse, BOOL ambient) {
    double setupStart=CACurrentMediaTime();
    UIView *host=[[UIView alloc] initWithFrame:CGRectMake(0,0,375,667)];
    host.backgroundColor=[UIColor colorWithWhite:.06 alpha:1];
    ULPCoverView *cover=[ULPCoverView new]; [host addSubview:cover];
    ULPVisualConfig c=ULPVisualConfigDefault();
    c.coverMode=ULPCoverModeArtwork; c.coverSize=.502;
    c.coverGlow=.229; c.coverGlowPulse=glowPulse; c.coverReactType=ULPReactRaw;
    c.coverReaction=ambient ? 1 : 0; c.coverRumble=ambient ? .136 : 0;
    c.coverDrift=ambient ? .2 : 0; c.coverSpin=ambient ? 11 : 0;
    cover.visualConfig=c; [cover layoutInViewport:host.bounds];
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(200,200),YES,1);
    [UIColor.systemPinkColor setFill]; UIRectFill(CGRectMake(0,0,200,200));
    [UIColor.systemIndigoColor setFill]; UIRectFill(CGRectMake(100,0,100,200));
    [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(45,25,110,35));
    cover.artwork=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    double foreground=(CACurrentMediaTime()-setupStart)*1000;
    if(glowPulse>0) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
        while(![[cover valueForKey:@"haloCacheValid"] boolValue] && deadline.timeIntervalSinceNow>0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        assert([[cover valueForKey:@"haloCacheValid"] boolValue]);
    }
    double setup=(CACurrentMediaTime()-setupStart)*1000;
    double clock=CACurrentMediaTime();
    double begin=CACurrentMediaTime();
    for(int i=0;i<3000;++i) {
        @autoreleasepool {
            [cover updateReactionAtTime:clock+i/60.0 rawLevel:(1+sin(i*.21))*.5 beatLevel:0];
            [cover advanceSpinBy:1.0/60];
        }
    }
    double update=(CACurrentMediaTime()-begin)/3000*1e6;
    // CPU raster benchmark. This does not measure GPU/display FPS, battery,
    // or SpringBoard hitches; both binaries use the same software path.
    UIGraphicsBeginImageContextWithOptions(host.bounds.size,YES,1);
    CGContextRef ctx=UIGraphicsGetCurrentContext(); double elapsed[80];
    for(int i=0;i<90;++i) {
        @autoreleasepool {
            [cover updateReactionAtTime:clock+51+i/60.0 rawLevel:(1+sin(i*.21))*.5 beatLevel:0];
            [cover advanceSpinBy:1.0/60];
            CGContextClearRect(ctx,host.bounds);
            double t=CACurrentMediaTime(); [host.layer renderInContext:ctx];
            if(i>=10) elapsed[i-10]=(CACurrentMediaTime()-t)*1000;
        }
    }
    double total=0; for(int i=0;i<80;++i)total+=elapsed[i];
    qsort(elapsed,80,sizeof(double),ascending);
    printf("%s pulse=%.3f ambient=%d foreground_setup_ms=%.2f cache_ready_ms=%.2f update_us=%.2f raster_mean_ms=%.3f raster_p95_ms=%.3f\n",
           tag.UTF8String,glowPulse,ambient,foreground,setup,update,total/80,elapsed[75]);
    NSString *path=[NSString stringWithFormat:@"/var/mobile/Library/Caches/ULP/cover-perf-%@-%.2f-%d.png",tag,glowPulse,ambient];
    [UIImagePNGRepresentation(UIGraphicsGetImageFromCurrentImageContext()) writeToFile:path atomically:YES];
    UIGraphicsEndImageContext();
    assert(isfinite(update+total));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *tag=argc>1 ? @(argv[1]) : @"test";
        int rounds=argc>2 ? MAX(1,MIN(3,atoi(argv[2]))) : 3;
        for(int round=0;round<rounds;++round) {
            @autoreleasepool { run(tag,0,NO); }
            @autoreleasepool { run(tag,.777,NO); }
            @autoreleasepool { run(tag,.777,YES); }
            @autoreleasepool { run(tag,1.5,YES); }
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        }
        puts("CoverPerformance OK (CPU software raster only)");
    }
    return 0;
}
