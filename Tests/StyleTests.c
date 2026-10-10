#include "../Visualization/ULPStyle.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    uint32_t rgb = 123;
    assert(ULPParseHexColor("#12abEF", &rgb) && rgb == 0x12ABEF);
    assert(ULPParseHexColor("000000", &rgb) && rgb == 0);
    assert(!ULPParseHexColor("#GGGGGG", &rgb) && rgb == 0);
    assert(!ULPParseHexColor("#123", &rgb));
    assert(!ULPParseHexColor("#FFFFFF00", &rgb));
    ULPGradientPoints p = ULPGradientEndpoints(0, 400, 200);
    assert(fabs(p.x1) < 1e-6 && p.y1 == .5 && p.x2 == 1 && p.y2 == .5);
    p = ULPGradientEndpoints(90, 400, 200);
    assert(fabs(p.x1-.5) < 1e-6 && fabs(p.y1) < 1e-6 && fabs(p.y2-1) < 1e-6);
    p = ULPGradientEndpoints(45, 400, 200);
    // Physical direction remains 45 degrees on a non-square layer.
    assert(fabs((p.x2-p.x1)*400 - (p.y2-p.y1)*200) < 1e-6);
    p = ULPGradientEndpoints(NAN, 0, INFINITY);
    assert(isfinite(p.x1) && isfinite(p.y2));
    // Large images survive small observer updates, within the same track only.
    assert(ULPArtworkHasMorePixels(750, 750, 200, 200));
    assert(!ULPArtworkHasMorePixels(200, 200, 750, 750));
    assert(!ULPArtworkHasMorePixels(750, 750, 750, 750));
    assert(!ULPArtworkHasMorePixels(NAN, 750, 0, 0));
    assert(ULPArtworkHasMorePixels(200, 200, 0, 0));
    ULPArtworkExtent e = ULPArtworkForegroundExtent(546, 546, 2, 375, 667, false);
    assert(fabs(e.width - 311.25) < 1e-6 && fabs(e.height - 311.25) < 1e-6);
    assert(e.width * 1.08 < 375 * .90); // Full zoom remains below 90% of screen width.
    e = ULPArtworkForegroundExtent(750, 750, 2, 375, 667, false);
    assert(fabs(e.width - 311.25) < 1e-6 && fabs(e.height - 311.25) < 1e-6);
    e = ULPArtworkForegroundExtent(1500, 1500, 2, 375, 667, false);
    assert(fabs(e.width - 311.25) < 1e-6 && fabs(e.height - 311.25) < 1e-6); // Resolution-independent framing.
    e = ULPArtworkForegroundExtent(750, 750, 2, 375, 667, true);
    assert(fabs(e.width - 667) < 1e-6 && fabs(e.height - 667) < 1e-6); // Not 867pt overscan.
    e = ULPArtworkForegroundExtent(1280, 720, 2, 375, 667, false);
    assert(fabs(e.width - 311.25) < 1e-6 && fabs(e.height - 175.078125) < 1e-6); // Center video thumbnail.
    e = ULPArtworkForegroundExtent(1280, 720, 2, 375, 667, true);
    assert(fabs(e.height - 667) < 1e-6 && e.width >= 375);
    e = ULPArtworkForegroundExtent(750, 750, 2, 343, 184, false);
    assert(fabs(e.width * 1.08 - 184) < 1e-6 && fabs(e.height * 1.08 - 184) < 1e-6); // Preview reserves zoom room.
    e = ULPArtworkForegroundExtent(0, 750, 2, 375, 667, true);
    assert(e.width == 0 && e.height == 0);
    puts("StyleTests OK");
}
