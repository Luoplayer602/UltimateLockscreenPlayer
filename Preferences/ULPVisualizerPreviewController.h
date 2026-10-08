#import <Preferences/PSViewController.h>

@interface ULPVisualizerPreviewController : PSViewController
@property (nonatomic) BOOL compact;
- (void)startPreviewRendering;
- (void)stopPreviewRendering;
@end
