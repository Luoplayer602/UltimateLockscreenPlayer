#import <UIKit/UIKit.h>

#import "../Audio/MSH2Protocol.h"

@interface ULPVisualizerView : UIView
- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel;
@end
