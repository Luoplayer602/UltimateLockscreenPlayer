#import <UIKit/UIKit.h>

#import "../Audio/MSH2Protocol.h"
#import "../Playback/ULPNowPlaying.h"

NS_ASSUME_NONNULL_BEGIN

@interface ULPLockScreenView : UIView
@property (nonatomic, copy, nullable) void (^commandHandler)(NSInteger command);
@property (nonatomic, copy, nullable) void (^artworkHandler)(UIImage * _Nullable artwork);
@property (nonatomic, copy, nullable) void (^openSourceHandler)(void);
@property (nonatomic, copy, nullable) void (^diagnosticHandler)(NSString *message);
- (void)updateNowPlaying:(ULPNowPlayingSnapshot *)snapshot;
- (BOOL)repairComponents;
@property (nonatomic, readonly, nullable) UIImage *currentArtwork;
@end

NS_ASSUME_NONNULL_END
