#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ULPNowPlayingSnapshot : NSObject
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, copy, nullable) NSData *artworkData;
@property (nonatomic, strong, nullable) UIImage *artworkImage;
@property (nonatomic) double duration;
@property (nonatomic) double elapsed;
@property (nonatomic) BOOL playing;
@property (nonatomic) int processID;
@property (nonatomic, copy, nullable) NSString *trackIdentifier;
@property (nonatomic) double playbackRate;
@property (nonatomic) BOOL sessionPresent;
@end

typedef void (^ULPNowPlayingHandler)(ULPNowPlayingSnapshot *snapshot);

@interface ULPNowPlaying : NSObject
@property (nonatomic, copy, nullable) void (^diagnosticHandler)(NSString *message);
- (instancetype)initWithHandler:(ULPNowPlayingHandler)handler;
- (void)start;
- (void)stop;
- (void)requestRefresh;
- (BOOL)sendCommand:(NSInteger)command;
@end

NS_ASSUME_NONNULL_END
