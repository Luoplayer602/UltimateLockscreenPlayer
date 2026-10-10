#import <Preferences/PSViewController.h>

@interface ULPVisualizerPreviewController : PSViewController
@property (nonatomic) BOOL compact;
- (void)refreshVisualPreferences;
- (void)resetCoverMotion;
- (void)startPreviewRendering;
- (void)stopPreviewRendering;
@end
