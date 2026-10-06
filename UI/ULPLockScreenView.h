#import <UIKit/UIKit.h>

#import "../Audio/MSH2Protocol.h"
#import "../Playback/ULPNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

@interface ULPLockScreenView : UIView
@property (nonatomic, copy, nullable) void (^commandHandler)(NSInteger command);
- (void)updateNowPlaying:(ULPNowPlayingSnapshot *)snapshot;
- (void)updateAudio:(ULPMSH2FeatureFrame)frame zoomLevel:(float)zoomLevel;
@end

NS_ASSUME_NONNULL_END
