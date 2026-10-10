#include "ULPStyle.h"
#include <math.h>
#include <ctype.h>
bool ULPArtworkHasMorePixels(double w, double h, double ow, double oh) {
    if (!isfinite(w) || !isfinite(h) || w <= 0 || h <= 0) return false;
    return !isfinite(ow) || !isfinite(oh) || ow <= 0 || oh <= 0 || w * h > ow * oh;
}
ULPArtworkExtent ULPArtworkForegroundExtent(double pw, double ph, double ds,
    double vw, double vh, bool cover) {
    if (!isfinite(pw) || !isfinite(ph) || !isfinite(vw) || !isfinite(vh) ||
        pw <= 0 || ph <= 0 || vw <= 0 || vh <= 0) return (ULPArtworkExtent){0, 0};
    if (!isfinite(ds) || ds <= 0) ds = 1;
    double w = pw / ds, h = ph / ds;
    double ratio = cover ? fmax(vw / w, vh / h) : fmin(vw * .83 / w, vh / (1.08 * h));
    return (ULPArtworkExtent){w * ratio, h * ratio};
}
bool ULPParseHexColor(const char *s, uint32_t *rgb) {
    if (!s || !rgb) return false;
    if (*s == '#') ++s;
    uint32_t value = 0;
    for (unsigned i = 0; i < 6; ++i) {
        unsigned char c = (unsigned char)s[i];
        if (!c) return false;
        int digit = c >= '0' && c <= '9' ? c - '0' :
            c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (digit < 0) return false;
        value = (value << 4) | (unsigned)digit;
    }
    if (s[6]) return false;
    *rgb = value; return true;
}
ULPGradientPoints ULPGradientEndpoints(double degrees, double width, double height) {
    if (!isfinite(degrees)) degrees = 0;
    if (!isfinite(width) || width <= 0) width = 1;
    if (!isfinite(height) || height <= 0) height = 1;
    double angle = degrees * 3.14159265358979323846 / 180;
    double x = cos(angle), y = sin(angle);
    double half = (fabs(x) * width + fabs(y) * height) / 2;
    return (ULPGradientPoints){.5-x*half/width, .5-y*half/height,
                              .5+x*half/width, .5+y*half/height};
}
