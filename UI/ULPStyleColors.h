#import <UIKit/UIKit.h>
#import "../Visualization/ULPStyle.h"
static inline UIColor *ULPStyleColor(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0
        green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
