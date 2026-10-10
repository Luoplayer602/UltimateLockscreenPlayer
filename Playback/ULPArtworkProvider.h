#import <UIKit/UIKit.h>
#import "ULPNowPlaying.h"

// Main queue only. Never changes the system catalog or its destination.
@interface ULPArtworkProvider : NSObject
@property (nonatomic, copy) void (^imageHandler)(UIImage *image, NSString *trackIdentifier);
@property (nonatomic, copy) void (^diagnosticHandler)(NSString *message);
- (void)updateWithSnapshot:(ULPNowPlayingSnapshot *)snapshot
                     host:(UIView *)host excludingView:(UIView *)excluded;
@end
