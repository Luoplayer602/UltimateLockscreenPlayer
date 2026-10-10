#import <UIKit/UIKit.h>
#import "../Visualization/ULPVisualConfig.h"

#define ULP_BACKGROUND_OVERSCAN_RATIO 0.30

@interface ULPBackgroundView : UIView
@property (nonatomic) ULPVisualConfig visualConfig;
@property (nonatomic) CGRect contentViewport;
- (void)setArtwork:(UIImage *)artwork;
- (void)setArtwork:(UIImage *)artwork renderedArtwork:(UIImage *)blur;
- (UIImage *)renderedArtwork;
- (void)setRenderedArtwork:(UIImage *)artwork;
- (void)attachSwipeRecognitionToView:(UIView *)view;
- (void)resetMotion;
- (void)setZoomLevel:(float)level;
@end
