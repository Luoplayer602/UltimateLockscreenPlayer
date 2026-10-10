#include "../Visualization/ULPCover.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ULPVisualConfig c = ULPVisualConfigDefault();
    ULPCoverLayout full = ULPCoverLayoutForViewport(400, 800, c);
    assert(fabs(full.diameter - 118.8) < .001 && full.x == 200 && full.y == 336);
    ULPCoverLayout preview = ULPCoverLayoutForViewport(343, 184, c);
    assert(fabs(preview.diameter - 58.2912) < .001 && preview.y == 92);
    // Visualizer flips/nonuniform scale/zoom geometry never distort the circle.
    c.scale = 1.8; c.width = 2; c.height = .25; c.flipX = c.flipY = true;
    c.offsetX = -80; c.offsetY = 80; c.rotation = 180;
    ULPCoverLayout same = ULPCoverLayoutForViewport(400, 800, c);
    assert(same.diameter == full.diameter && same.x == full.x && same.y == full.y);
    c.coverX = 40; c.coverY = -30; c.coverSize = 1;
    ULPCoverLayout moved = ULPCoverLayoutForViewport(375, 667, c);
    assert(moved.x == 225 && fabs(moved.y - 252.015) < .001);
    assert(fabs(moved.diameter - 253.125) < 1e-10);
    assert(ULPCoverLayoutForViewport(0, 667, c).diameter == 0);
    assert(ULPCoverLayoutForViewport(NAN, INFINITY, c).diameter == 0);
    // Spin uses seconds, supports both directions, and bounds long stalls.
    double fast = 0, slow = 0;
    for (int i = 0; i < 60; ++i) fast = ULPCoverAdvanceSpin(fast, 1.0 / 60, 90);
    for (int i = 0; i < 15; ++i) slow = ULPCoverAdvanceSpin(slow, 1.0 / 15, 90);
    assert(fabs(fast - slow) < 1e-10 && fabs(fast - 1.570796326794897) < 1e-10);
    assert(fabs(ULPCoverAdvanceSpin(0, .1, -90) + .1570796326794897) < 1e-10);
    assert(ULPCoverAdvanceSpin(1, 0, 90) == 1);
    assert(ULPCoverAdvanceSpin(1, 1, 0) == 1);
    assert(ULPCoverAdvanceSpin(0, 100, 90) == ULPCoverAdvanceSpin(0, .1, 90));
    assert(isfinite(ULPCoverAdvanceSpin(NAN, INFINITY, NAN)));
    puts("CoverTests OK: viewport fit, independent circle geometry and playback spin");
}
