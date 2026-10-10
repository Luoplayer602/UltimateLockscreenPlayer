#include "../Visualization/ULPTrail.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static void pixel(ULPTrailBuffer *b, size_t index, unsigned alpha) {
    // White, premultiplied. A partially transparent fill is a useful case.
    memset(b->current + index * 4, (int)alpha, 4);
}

static float residual_over_live(ULPTrailBuffer *b, size_t i, float opacity) {
    float current = b->current[i * 4 + 3] * opacity;
    return current + b->output[i * 4 + 3] * (1 - current / 255);
}

int main(void) {
    ULPTrailBuffer b = {0};
    assert(ULPTrailResize(&b, 2, 1));
    pixel(&b, 0, 51);
    for (unsigned i = 0; i < 600; ++i) {
        assert(ULPTrailComposite(&b, 1.0 / 60, .8f, 1, 1, true));
        assert(b.output[3] == 0);
        assert(!b.hasOutput);
        assert(b.history[0].coverage == 51);
        assert(residual_over_live(&b, 0, 1) == 51);
    }
    // Movement leaves an old footprint, without disturbing the new geometry.
    memset(b.current, 0, 8);
    pixel(&b, 1, 255);
    assert(ULPTrailComposite(&b, .05, .8f, .7f, 1, true));
    assert(b.output[3] > 0 && b.output[3] < 51);
    assert(b.hasOutput);
    assert(b.output[7] == 0);
    assert(residual_over_live(&b, 1, 1) == 255);
    // Old bright geometry under a dim current fill uses residual alpha. It
    // must reach the max, rather than the sum, even with visual opacity < 1.
    pixel(&b, 0, 20);
    for (unsigned i = 0; i < 2; ++i) {
        float opacity = i ? .35f : 1;
        ULPTrailComposite(&b, 0, .8f, 1, opacity, true);
        float maximum = b.history[0].coverage * opacity;
        assert(fabsf(residual_over_live(&b, 0, opacity) - maximum) <= .51f);
        for (size_t p = 0; p < 2; ++p)
            for (unsigned c = 0; c < 3; ++c)
                assert(b.output[p * 4 + c] <= b.output[p * 4 + 3]);
    }
    ULPTrailFree(&b);
    // Wall-clock decay is independent of render FPS, including irregular ticks.
    ULPTrailBuffer slow = {0}, fast = {0}, jitter = {0};
    assert(ULPTrailResize(&slow, 1, 1));
    assert(ULPTrailResize(&fast, 1, 1));
    assert(ULPTrailResize(&jitter, 1, 1));
    pixel(&slow, 0, 255); pixel(&fast, 0, 255); pixel(&jitter, 0, 255);
    ULPTrailComposite(&slow, 0, 2, 1, 1, true);
    ULPTrailComposite(&fast, 0, 2, 1, 1, true);
    ULPTrailComposite(&jitter, 0, 2, 1, 1, true);
    memset(slow.current, 0, 4); memset(fast.current, 0, 4); memset(jitter.current, 0, 4);
    for (unsigned i = 0; i < 15; ++i) ULPTrailComposite(&slow, 1.0 / 15, 2, 1, 1, false);
    for (unsigned i = 0; i < 60; ++i) ULPTrailComposite(&fast, 1.0 / 60, 2, 1, 1, false);
    ULPTrailComposite(&jitter, .13, 2, 1, 1, false);
    ULPTrailComposite(&jitter, .27, 2, 1, 1, false);
    ULPTrailComposite(&jitter, .60, 2, 1, 1, false);
    assert(fabsf(slow.history[0].coverage - fast.history[0].coverage) < .001f);
    assert(fabsf(slow.history[0].coverage - jitter.history[0].coverage) < .001f);
    assert(fabsf(slow.history[0].coverage - 25.5f) < .001f);
    assert(slow.output[3] == fast.output[3] && slow.output[3] == jitter.output[3]);
    ULPTrailComposite(&slow, 1, 2, 1, 1, false);
    assert(fabsf(slow.history[0].coverage - 2.55f) < .001f);
    assert(!ULPTrailComposite(&slow, 1, 2, 1, 1, false));
    // Pause must not feed the frozen live frame back into history.
    pixel(&fast, 0, 255);
    ULPTrailComposite(&fast, 0, .8f, 1, 1, true);
    for (unsigned i = 0; i < 120; ++i) ULPTrailComposite(&fast, 1.0 / 30, .8f, 1, 1, false);
    assert(fast.history[0].coverage < .5f);
    assert(fast.output[3] == 0);
    // Bad input must never create invalid premultiplied image bytes.
    ULPTrailComposite(&jitter, NAN, NAN, NAN, INFINITY, false);
    assert(jitter.output[3] == 0);
    ULPTrailFree(&slow); ULPTrailFree(&fast); ULPTrailFree(&jitter);
    // Resource bounds, overflow protection, reset and reallocations.
    assert(ULPTrailResize(&b, 512, 1024));
    assert(!ULPTrailResize(&b, SIZE_MAX, SIZE_MAX));
    assert(!ULPTrailResize(&b, 512, 1025));
    assert(!ULPTrailResize(&b, 0, 2));
    assert(b.width == 512 && b.height == 1024);
    assert(ULPTrailResize(&b, 3, 1));
    assert(b.history[0].coverage == 0 && b.current[0] == 0 && b.output[0] == 0);
    ULPTrailFree(&b); ULPTrailFree(&b);
    assert(!b.history && !b.current && !b.output && !b.width);
    puts("TrailTests OK: max coverage, elapsed-time fade, pause, reset and memory bounds");
    return 0;
}
