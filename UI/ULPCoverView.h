#import <UIKit/UIKit.h>
#import "../Visualization/ULPVisualConfig.h"

@interface ULPCoverView : UIView
@property (nonatomic) ULPVisualConfig visualConfig;
@property (nonatomic) UIImage *artwork;
- (void)layoutInViewport:(CGRect)viewport;
- (void)advanceSpinBy:(NSTimeInterval)seconds;
- (void)resetMotion;
@end
