#import <Foundation/Foundation.h>

#import "MSH2Protocol.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^ULPMSH2FrameHandler)(ULPMSH2FeatureFrame frame);
typedef void (^ULPMSH2StatusHandler)(NSString *message);

// One-use client. Call start once, then stop when audio features are no longer needed.
@interface ULPMSH2Client : NSObject

- (instancetype)initWithFrameHandler:(ULPMSH2FrameHandler)handler
                        statusHandler:(ULPMSH2StatusHandler)statusHandler;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
