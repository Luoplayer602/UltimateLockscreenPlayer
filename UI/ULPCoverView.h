#import <UIKit/UIKit.h>
#import "../Visualization/ULPVisualConfig.h"

@interface ULPCoverView : UIView
@property (nonatomic) ULPVisualConfig visualConfig;
@property (nonatomic) UIImage *artwork;
- (void)layoutInViewport:(CGRect)viewport;
- (void)advanceSpinBy:(NSTimeInterval)seconds;
- (void)resetMotion;
- (void)resetReaction;
- (void)triggerBeat:(float)strength atTime:(CFTimeInterval)time;
- (void)updateReactionAtTime:(CFTimeInterval)time rawLevel:(float)level;
- (void)updateReactionAtTime:(CFTimeInterval)time rawLevel:(float)raw beatLevel:(float)beat;
- (BOOL)hasReactionAtTime:(CFTimeInterval)time;
- (void)setRenderingSuspended:(BOOL)suspended;
@end
