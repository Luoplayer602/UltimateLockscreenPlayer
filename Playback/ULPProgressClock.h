#ifndef ULP_PROGRESS_CLOCK_H
#define ULP_PROGRESS_CLOCK_H

#include <stdbool.h>

typedef struct {
    double anchorElapsed;
    double anchorTime;
    double lastRawElapsed;
    double rate;
    bool hasRawElapsed;
    bool playing;
    bool initialized;
    double lastSourceElapsed;
    double lastSourceTimestamp;
    bool hasSourceAnchor;
} ULPProgressClock;

void ULPProgressClockReset(ULPProgressClock *clock);
double ULPProgressClockUpdate(ULPProgressClock *clock, double rawElapsed,
                              double duration, bool playing, double now);
// NAN elapsed means missing metadata, not a seek to zero.
double ULPProgressClockUpdateRate(ULPProgressClock *clock, double rawElapsed,
                                  double duration, bool playing, double rate, double now);
// Source identity is (elapsed, timestamp), not elapsed alone. Timestamp changes
// can signal a restart of the same song even when elapsed remains exactly zero.
double ULPProgressClockUpdateSource(ULPProgressClock *clock, double sourceElapsed,
    double sourceTimestamp, double duration, bool playing, double rate,
    double wallTime, double now);

#endif
