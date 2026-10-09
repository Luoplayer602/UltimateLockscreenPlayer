#import <UIKit/UIKit.h>

@interface ULPVolumeHUDView : UIView
- (void)showVolume:(float)volume previousVolume:(float)previousVolume;
- (void)dismissImmediately;
@end
