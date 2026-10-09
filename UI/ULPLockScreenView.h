#import <UIKit/UIKit.h>

#import "../Audio/MSH2Protocol.h"
#import "../Playback/ULPNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

@interface ULPLockScreenView : UIView
@property (nonatomic, copy, nullable) void (^commandHandler)(NSInteger command);
@property (nonatomic, copy, nullable) void (^artworkHandler)(UIImage * _Nullable artwork);
@property (nonatomic, copy, nullable) void (^openSourceHandler)(void);
- (void)updateNowPlaying:(ULPNowPlayingSnapshot *)snapshot;
@end

NS_ASSUME_NONNULL_END
