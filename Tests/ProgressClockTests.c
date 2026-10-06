#include "../Playback/ULPProgressClock.h"

#include <assert.h>
#include <math.h>

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
    return 0;
}
