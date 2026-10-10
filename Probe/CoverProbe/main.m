#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <unistd.h>
#import <assert.h>
#import <math.h>
#import "../../UI/ULPVisualizerView.h"
#import "../../UI/ULPCoverView.h"
#import "../../Visualization/ULPCover.h"

static id child(id object, const char *name) {
    return object_getIvar(object, class_getInstanceVariable([object class], name));
}

static NSData *capture(UIView *view, NSString *name) {
    size_t width = view.bounds.size.width, height = view.bounds.size.height;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextTranslateCTM(context, 0, height); CGContextScaleCTM(context, 1, -1);
    CGContextSetRGBFillColor(context, .06, .07, .1, 1);
    CGContextFillRect(context, view.bounds);
    [view.layer renderInContext:context];
    NSData *pixels = [NSData dataWithBytes:CGBitmapContextGetData(context) length:width * height * 4];
    CGImageRef image = CGBitmapContextCreateImage(context);
    NSString *path = [@"/var/mobile/Library/Caches/ULP" stringByAppendingPathComponent:name];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    [UIImagePNGRepresentation([UIImage imageWithCGImage:image]) writeToFile:path atomically:YES];
    CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(space);
    return pixels;
}

static UIImage *wideArtwork(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(300, 100), YES, 1);
    [[UIColor colorWithRed:0 green:1 blue:1 alpha:1] setFill]; UIRectFill(CGRectMake(0,0,300,100));
    [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,100,100));
    [UIColor.blueColor setFill]; UIRectFill(CGRectMake(200,0,100,100));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext(); return image;
}

static void run(CGSize size, NSString *suffix) {
    __attribute__((objc_precise_lifetime)) UIWindow *window =
        [[UIWindow alloc] initWithFrame:(CGRect){CGPointZero,size}];
    ULPVisualizerView *view = [[ULPVisualizerView alloc] initWithFrame:window.bounds];
    [window addSubview:view];
    ULPVisualConfig c = ULPVisualConfigDefaultForMode(ULPVisualModeWave);
    c.glow = 0; c.coverMode = ULPCoverModeArtwork; c.coverGlow = 0;
    c.coverOutlineThickness = 0; c.coverSpin = 90;
    view.visualConfig = c;
    [view setArtwork:wideArtwork() manualColor:UIColor.whiteColor];
    [view layoutIfNeeded];
    ULPCoverView *cover = child(view, "_cover");
    UIView *rotor = child(cover, "_rotor");
    UILabel *logo = child(cover, "_logo");
    UIImageView *image = child(cover, "_image");
    assert(!cover.hidden && !image.hidden && logo.hidden);
    NSData *art = capture(view, [NSString stringWithFormat:@"cover-probe-art-%@.png",suffix]);
    ULPCoverLayout geometry = ULPCoverLayoutForViewport(size.width,size.height,c);
    // Sample near top/bottom inside the circular crop, where aspect-fit would
    // leave black bars. Wide input must cover every point of this circle.
    for (int direction = -1; direction <= 1; direction += 2) {
        NSUInteger x = lround(geometry.x), y = lround(geometry.y + direction * geometry.diameter * .38);
        const uint8_t *pixel = (const uint8_t *)art.bytes + (y * (NSUInteger)size.width + x) * 4;
        assert(pixel[0] < 10 && pixel[1] > 245 && pixel[2] > 245);
    }
    ULPMSH2FeatureFrame frame = {.featureMask=ULP_MSH2_WAVEFORM | ULP_MSH2_SPECTRUM, .sampleRate=44100};
    view.playbackActive = YES;
    for (int i=0; i<12; ++i) { [view updateAudio:frame zoomLevel:1]; usleep(17000); }
    assert(fabs(atan2(rotor.transform.b,rotor.transform.a)) > .05);
    CGAffineTransform rotation = rotor.transform;
    view.playbackActive = NO;
    for (int i=0; i<3; ++i) { [view updateAudio:frame zoomLevel:0]; usleep(17000); }
    assert(CGAffineTransformEqualToTransform(rotation,rotor.transform));
    [view resetCoverMotion];
    assert(CGAffineTransformEqualToTransform(rotor.transform,CGAffineTransformIdentity));
    // Setting visualizer geometry must not distort/move the cover.
    CGRect before = cover.frame;
    c.scale=1.8; c.width=2; c.height=.25; c.offsetX=80; c.rotation=180; c.flipX=YES;
    view.visualConfig=c; [view layoutIfNeeded];
    assert(CGRectEqualToRect(before,cover.frame));
    [view setArtwork:nil manualColor:UIColor.whiteColor];
    assert(image.hidden && !logo.hidden);
    NSData *fallback = capture(view, [NSString stringWithFormat:@"cover-probe-logo-%@.png",suffix]);
    assert(![fallback isEqualToData:art]);
    c.coverMode=ULPCoverModeOff; view.visualConfig=c; [view layoutIfNeeded];
    assert(cover.hidden);
    NSData *off = capture(view, [NSString stringWithFormat:@"cover-probe-off-%@.png",suffix]);
    assert(![fallback isEqualToData:off]);
    printf("PASS %s: full bleed, pause spin, reset, independent circle, artwork fallback, Off\n",suffix.UTF8String);
}

int main(void) {
    @autoreleasepool {
        run(CGSizeMake(375,667),@"lockscreen");
        run(CGSizeMake(343,184),@"preview");
        puts("CoverProbe OK");
    }
    return 0;
}
