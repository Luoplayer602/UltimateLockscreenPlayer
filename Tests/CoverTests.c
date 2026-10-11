#include "../Visualization/ULPCover.h"
#include <assert.h>
#include <math.h>
#include <float.h>
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
    c = ULPVisualConfigDefault();
    ULPCoverAmbient base = ULPCoverAmbientEvaluate(c, 3, 1, 1);
    assert(base.x == 0 && base.y == 0 && base.halo == c.coverGlow);
    c.coverRumble = .2;
    ULPCoverAmbient silent = ULPCoverAmbientEvaluate(c, 3, 0, 0);
    ULPCoverAmbient quiet = ULPCoverAmbientEvaluate(c, 3, .25, 0);
    ULPCoverAmbient loud = ULPCoverAmbientEvaluate(c, 3, 1, 0);
    assert(silent.x == 0 && silent.y == 0);
    assert(fabs(loud.x - 4 * quiet.x) < 1e-8 && fabs(loud.y - 4 * quiet.y) < 1e-8);
    c.coverDrift = .2;
    // Drift is clock driven even without audio or any Beat reaction strength.
    c.coverReaction = 0;
    ULPCoverAmbient drift = ULPCoverAmbientEvaluate(c, 3, 0, 0);
    ULPCoverAmbient later = ULPCoverAmbientEvaluate(c, 4, 0, 0);
    assert(fabs(drift.x) > 0 && fabs(drift.x - later.x) > .1);
    c.coverGlowPulse = 1.5;
    assert(ULPCoverAmbientEvaluate(c, 3, 0, 0).halo == c.coverGlow);
    assert(fabs(ULPCoverAmbientEvaluate(c, 3, 0, 1).halo - (c.coverGlow + 1.5)) < 1e-7);
    for(int i=0;i<600;++i) {
        ULPCoverAmbient a = ULPCoverAmbientEvaluate(c, i / 60.0, 1, 1);
        assert(fabs(a.x) <= 12.001 && fabs(a.y) <= 9.401 && a.halo <= 2.5);
    }
    ULPCoverAmbient extreme = ULPCoverAmbientEvaluate(c, DBL_MAX, NAN, INFINITY);
    assert(isfinite(extreme.x + extreme.y + extreme.halo));
    extreme = ULPCoverAmbientEvaluate(c, NAN, 1, 1);
    assert(extreme.x == 0 && extreme.y == 0 && isfinite(extreme.halo));
    c.coverMode = ULPCoverModeOff;
    ULPCoverAmbient off = ULPCoverAmbientEvaluate(c, 3, 1, 1);
    assert(off.x == 0 && off.y == 0 && off.halo == c.coverGlow);
    // Cached blur interpolation retains the requested opacity, uses no more
    // than two adjacent textures, and stays continuous at every radius anchor.
    for (int i = 0; i <= 1000; ++i) {
        float level = i / 1000.0f;
        ULPCoverHaloBlend blend = ULPCoverHaloWeights(1, 1.5, level);
        double total = 0; unsigned count = 0;
        for (unsigned j = 0; j < ULP_COVER_HALO_STAGES; ++j) {
            assert(isfinite(blend.opacity[j]) && blend.opacity[j] >= 0 && blend.opacity[j] <= 1);
            total += blend.opacity[j]; if (blend.opacity[j] > 0) ++count;
        }
        assert(fabs(total - 1) < 1e-10 && count <= 2);
    }
    ULPCoverHaloBlend dark = ULPCoverHaloWeights(0, 0, 1);
    for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) assert(dark.opacity[i] == 0);
    for (unsigned i = 1; i < ULP_COVER_HALO_STAGES; ++i) {
        double anchor = dark.levels[i];
        ULPCoverHaloBlend at = ULPCoverHaloWeights(0, 1.5, anchor / 1.5);
        if (anchor > 1.5) at = ULPCoverHaloWeights(1, 1.5, (anchor - 1) / 1.5);
        assert(fabs(at.opacity[i] - fmin(1, anchor)) < 2e-7);
    }
    ULPCoverHaloBlend bad = ULPCoverHaloWeights(NAN, INFINITY, NAN);
    for (unsigned i = 0; i < ULP_COVER_HALO_STAGES; ++i) assert(bad.opacity[i] == 0);
    c.coverMode = ULPCoverModeLogo; c.enabled = false;
    off = ULPCoverAmbientEvaluate(c, 3, 1, 1);
    assert(off.x == 0 && off.y == 0 && off.halo == c.coverGlow);
    puts("CoverTests OK: viewport, spin, level-driven rumble/halo, silent drift and finite bounds");
}
