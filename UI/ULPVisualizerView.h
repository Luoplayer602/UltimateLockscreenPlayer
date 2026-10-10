#import <UIKit/UIKit.h>

#import "../Audio/MSH2Protocol.h"
#import "../Visualization/ULPVisualConfig.h"

@interface ULPVisualizerView : UIView
@property (nonatomic) ULPVisualConfig visualConfig;
@property (nonatomic) BOOL playbackActive;
- (void)setArtwork:(UIImage *)artwork manualColor:(UIColor *)manualColor;
- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel;
- (BOOL)hasUnsettledPeakCaps;
- (void)resetTrail;
- (void)resetCoverMotion;
@end
