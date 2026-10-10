#include "../Playback/ULPProgressClock.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>

static void near(double actual, double expected) {
    assert(fabs(actual - expected) < 0.001);
}

int main(void) {
    ULPProgressClock clock;
    ULPProgressClockReset(&clock);
    near(ULPProgressClockUpdate(&clock, 20, 120, true, 0), 20);
    near(ULPProgressClockUpdate(&clock, 20, 120, true, 1), 21);
    near(ULPProgressClockUpdate(&clock, 20, 120, false, 2), 22);
    near(ULPProgressClockUpdate(&clock, 20, 120, false, 5), 22);
    near(ULPProgressClockUpdate(&clock, 20, 120, true, 6), 22);
    near(ULPProgressClockUpdate(&clock, 20, 120, true, 7), 23);
    near(ULPProgressClockUpdate(&clock, 50, 120, true, 8), 50);
    near(ULPProgressClockUpdate(&clock, 50, 120, true, 9), 51);
    near(ULPProgressClockUpdate(&clock, 120, 120, true, 10), 120);
    ULPProgressClockReset(&clock);
    near(ULPProgressClockUpdate(&clock, 0, 100, true, 11), 0);
    ULPProgressClockReset(&clock);
    near(ULPProgressClockUpdate(&clock, 20, 100, true, 0), 20);
    near(ULPProgressClockUpdate(&clock, NAN, 100, true, 1), 21);
    near(ULPProgressClockUpdate(&clock, 22.15, 100, true, 2), 22); // Small jitter must not move backwards.
    near(ULPProgressClockUpdate(&clock, 23.1, 100, true, 3), 23);
    near(ULPProgressClockUpdate(&clock, NAN, 100, false, 4), 24);
    near(ULPProgressClockUpdate(&clock, NAN, 100, false, 8), 24);
    near(ULPProgressClockUpdate(&clock, 10, 100, false, 9), 10); // Seek while paused.
    near(ULPProgressClockUpdate(&clock, 10, 100, true, 10), 10);
    near(ULPProgressClockUpdate(&clock, NAN, 100, true, 11), 11);
    near(ULPProgressClockUpdate(&clock, 0, 100, true, 12), 0); // Zero is a real seek when present.
    near(ULPProgressClockUpdateRate(&clock, NAN, 100, true, 1.5, 13), 1);
    near(ULPProgressClockUpdateRate(&clock, NAN, 100, true, 1.5, 15), 4);
    near(ULPProgressClockUpdateRate(&clock, NAN, 100, false, 1.5, 16), 5.5);
    near(ULPProgressClockUpdateRate(&clock, NAN, 100, false, 1.5, 20), 5.5);
    ULPProgressClockReset(&clock); // New track/session.
    near(ULPProgressClockUpdate(&clock, NAN, 100, true, 21), 0);
    near(ULPProgressClockUpdate(&clock, 45, 100, true, 22), 45);
    near(ULPProgressClockUpdate(&clock, NAN, 100, true, 23), 46);
    // YouTube Music publishes elapsed=0 plus a start timestamp throughout playback.
    // Previous once restarts the SAME song with a new timestamp and elapsed still 0.
    ULPProgressClockReset(&clock);
    near(ULPProgressClockUpdateSource(&clock, 0, 1000, 200, true, 1, 1080, 80), 80);
    near(ULPProgressClockUpdateSource(&clock, 0, 1000, 200, true, 1, 1081, 81), 81);
    near(ULPProgressClockUpdateSource(&clock, 0, 1082, 200, true, 1, 1082.2, 82.2), .2);
    near(ULPProgressClockUpdateSource(&clock, 0, 1082, 200, true, 1, 1083.2, 83.2), 1.2);
    // Same identity at the end of a repeated song must restart, not remain full.
    near(ULPProgressClockUpdateSource(&clock, 0, 1082, 200, true, 1, 1282.2, 282.2), 200);
    near(ULPProgressClockUpdateSource(&clock, 0, 1283, 200, true, 1, 1283.1, 283.1), .1);
    // Pause/resume and seek while paused still honor explicit source anchors.
    near(ULPProgressClockUpdateSource(&clock, 1, 1284, 200, false, 1, 1284, 284), 1);
    near(ULPProgressClockUpdateSource(&clock, 1, 1284, 200, false, 1, 1290, 290), 1);
    near(ULPProgressClockUpdateSource(&clock, 0, 1291, 200, false, 1, 1291, 291), 0);
    near(ULPProgressClockUpdateSource(&clock, 0, 1292, 200, true, 1, 1292, 292), 0);
    near(ULPProgressClockUpdateSource(&clock, NAN, 0, 200, true, 1, 1293, 293), 1);
    // A stale tuple must not reapply an adjusted wall clock on every poll.
    near(ULPProgressClockUpdateSource(&clock, 0, 1292, 200, true, 1, 2294, 294), 2);
    ULPProgressClockReset(&clock); // Previous twice selects another song.
    near(ULPProgressClockUpdateSource(&clock, 0, 2300, 180, true, 1, 2300, 300), 0);
    near(ULPProgressClockUpdateSource(&clock, 0, 2300, 180, true, 1, 2301, 301), 1);
    ULPProgressClockReset(&clock);
    near(ULPProgressClockUpdateSource(&clock, 0, 3000, 180, true, 1, 3000, 0), 0);
    near(ULPProgressClockUpdateSource(&clock, 0, 3000, 180, true, 1, 3080, 80), 80);
    // New start timestamp, but the corrected value is exactly the prior raw value.
    near(ULPProgressClockUpdateSource(&clock, 0, 3081, 180, true, 1, 3081, 81), 0);
    near(ULPProgressClockUpdateSource(&clock, 0, 3081, 180, true, 1, 3082, 82), 1);
    puts("ProgressClockTests OK");
    return 0;
}
