#import <UIKit/UIKit.h>

#define ULP_BACKGROUND_OVERSCAN_RATIO 0.30

@interface ULPBackgroundView : UIView
- (void)setArtwork:(UIImage *)artwork;
- (UIImage *)renderedArtwork;
- (void)setRenderedArtwork:(UIImage *)artwork;
- (void)attachSwipeRecognitionToView:(UIView *)view;
- (void)resetMotion;
- (void)setZoomLevel:(float)level;
@end
