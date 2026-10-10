#include "ULPProgressClock.h"

#include <math.h>
#include <string.h>

static double ULPProgressClockAdvance(ULPProgressClock *clock, double rawElapsed,
    double duration, bool playing, double rate, double now, bool freshSourceAnchor);

void ULPProgressClockReset(ULPProgressClock *clock) {
    memset(clock, 0, sizeof(*clock));
}

double ULPProgressClockUpdateSource(ULPProgressClock *clock, double sourceElapsed,
    double sourceTimestamp, double duration, bool playing, double rate,
    double wallTime, double now) {
    double rawElapsed = NAN;
    bool fresh = false;
    bool validTimestamp = isfinite(sourceTimestamp) && sourceTimestamp > 0;
    if (!validTimestamp) sourceTimestamp = 0;
    if (isfinite(sourceElapsed) && sourceElapsed >= 0) {
        fresh = !clock->hasSourceAnchor ||
            fabs(sourceElapsed - clock->lastSourceElapsed) > .001 ||
            fabs(sourceTimestamp - clock->lastSourceTimestamp) > .001;
        if (fresh) {
            rawElapsed = sourceElapsed;
            double age = wallTime - sourceTimestamp;
            double validRate = isfinite(rate) && rate >= 0 && rate <= 4 ? rate : 1;
            if (playing && validTimestamp && isfinite(age) && age >= 0 && age < 86400)
                rawElapsed += age * validRate;
        }
        clock->lastSourceElapsed = sourceElapsed;
        clock->lastSourceTimestamp = sourceTimestamp;
        clock->hasSourceAnchor = true;
    }
    return ULPProgressClockAdvance(clock, rawElapsed, duration, playing, rate, now, fresh);
}

double ULPProgressClockUpdate(ULPProgressClock *clock, double rawElapsed,
                              double duration, bool playing, double now) {
    return ULPProgressClockUpdateRate(clock, rawElapsed, duration, playing, 1, now);
}

double ULPProgressClockUpdateRate(ULPProgressClock *clock, double rawElapsed,
                                  double duration, bool playing, double rate, double now) {
    return ULPProgressClockAdvance(clock, rawElapsed, duration, playing, rate, now, false);
}

static double ULPProgressClockAdvance(ULPProgressClock *clock, double rawElapsed,
    double duration, bool playing, double rate, double now, bool freshSourceAnchor) {
    bool valid = isfinite(rawElapsed) && rawElapsed >= 0;
    if (!isfinite(now) || now < 0) now = 0;
    if (!isfinite(duration) || duration < 0) duration = 0;
    if (!isfinite(rate) || rate < 0 || rate > 4) rate = 1;

    if (!clock->initialized) {
        clock->anchorElapsed = valid ? rawElapsed : 0;
        clock->anchorTime = now;
        clock->lastRawElapsed = valid ? rawElapsed : 0;
        clock->hasRawElapsed = valid;
        clock->playing = playing;
        clock->rate = rate;
        clock->initialized = true;
    } else {
        double elapsedSinceAnchor = fmax(0, now - clock->anchorTime);
        double projected = clock->anchorElapsed +
                           (clock->playing ? elapsedSinceAnchor * clock->rate : 0);
        bool changedRaw = valid && (freshSourceAnchor || !clock->hasRawElapsed ||
                                   fabs(rawElapsed - clock->lastRawElapsed) > 0.1);
        // Ignore small timestamp jitter and repeated stale anchors. Accept an
        // actual seek immediately, including backward seeks and seeks to zero.
        bool seek = changedRaw && (!clock->hasRawElapsed || !clock->playing ||
                                  fabs(rawElapsed - projected) > 1.25);
        if (seek) {
            clock->anchorElapsed = rawElapsed;
            clock->anchorTime = now;
        } else if (playing != clock->playing || rate != clock->rate) {
            clock->anchorElapsed = projected;
            clock->anchorTime = now;
        }
        if (valid) {
            clock->lastRawElapsed = rawElapsed;
            clock->hasRawElapsed = true;
        }
        clock->playing = playing;
        clock->rate = rate;
    }

    double elapsed = clock->anchorElapsed +
                     (clock->playing ? fmax(0, now - clock->anchorTime) * clock->rate : 0);
    return duration > 0 ? fmin(duration, elapsed) : elapsed;
}
