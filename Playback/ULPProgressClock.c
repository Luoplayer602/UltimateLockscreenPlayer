#include "ULPProgressClock.h"

#include <math.h>
#include <string.h>

void ULPProgressClockReset(ULPProgressClock *clock) {
    memset(clock, 0, sizeof(*clock));
}

double ULPProgressClockUpdate(ULPProgressClock *clock, double rawElapsed,
                              double duration, bool playing, double now) {
    if (!isfinite(rawElapsed) || rawElapsed < 0) rawElapsed = 0;
    if (!isfinite(now) || now < 0) now = 0;
    if (!isfinite(duration) || duration < 0) duration = 0;

    if (!clock->initialized) {
        clock->anchorElapsed = rawElapsed;
        clock->anchorTime = now;
        clock->lastRawElapsed = rawElapsed;
        clock->playing = playing;
        clock->initialized = true;
    } else {
        double elapsedSinceAnchor = fmax(0, now - clock->anchorTime);
        double projected = clock->anchorElapsed +
                           (clock->playing ? elapsedSinceAnchor : 0);
        if (fabs(rawElapsed - clock->lastRawElapsed) > 0.1) {
            clock->anchorElapsed = rawElapsed;
            clock->anchorTime = now;
        } else if (playing != clock->playing) {
            clock->anchorElapsed = projected;
            clock->anchorTime = now;
        }
        clock->lastRawElapsed = rawElapsed;
        clock->playing = playing;
    }

    double elapsed = clock->anchorElapsed +
                     (clock->playing ? fmax(0, now - clock->anchorTime) : 0);
    return duration > 0 ? fmin(duration, elapsed) : elapsed;
}
