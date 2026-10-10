#ifndef ULP_STYLE_H
#define ULP_STYLE_H
#include <stdint.h>
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double x1, y1, x2, y2; } ULPGradientPoints;
typedef struct { double width, height; } ULPArtworkExtent;
ULPGradientPoints ULPGradientEndpoints(double degrees, double width, double height);
bool ULPParseHexColor(const char *text, uint32_t *rgb);
bool ULPArtworkHasMorePixels(double width, double height, double oldWidth, double oldHeight);
// cover=true: minimal aspect-preserving viewport cover. Otherwise centered at
// 83% of viewport width, with vertical room for the original 8% audio zoom.
ULPArtworkExtent ULPArtworkForegroundExtent(double pixelsWide, double pixelsHigh,
    double displayScale, double viewportWidth, double viewportHeight, bool cover);
#ifdef __cplusplus
}
#endif
#endif
