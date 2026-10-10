#import <UIKit/UIKit.h>
#import "../Visualization/ULPStyle.h"

static inline CGSize ULPArtworkPixelSize(UIImage *image) {
    if (!image) return CGSizeZero;
    CGImageRef cg = image.CGImage;
    CGSize size = cg ? CGSizeMake(CGImageGetWidth(cg), CGImageGetHeight(cg)) :
        CGSizeMake(image.size.width * image.scale, image.size.height * image.scale);
    if (cg && (image.imageOrientation == UIImageOrientationLeft || image.imageOrientation == UIImageOrientationRight ||
               image.imageOrientation == UIImageOrientationLeftMirrored || image.imageOrientation == UIImageOrientationRightMirrored))
        size = CGSizeMake(size.height, size.width);
    return size;
}

// Compare only within one track; callers must clear their image on track changes.
static inline BOOL ULPArtworkShouldUpgrade(UIImage *candidate, UIImage *current) {
    CGSize next = ULPArtworkPixelSize(candidate), old = ULPArtworkPixelSize(current);
    return ULPArtworkHasMorePixels(next.width, next.height, old.width, old.height);
}
