#ifndef ULP_PROGRESS_CLOCK_H
#define ULP_PROGRESS_CLOCK_H

#include <stdbool.h>

typedef struct {
    double anchorElapsed;
    double anchorTime;
    double lastRawElapsed;
    bool playing;
    bool initialized;
} ULPProgressClock;

void ULPProgressClockReset(ULPProgressClock *clock);
double ULPProgressClockUpdate(ULPProgressClock *clock, double rawElapsed,
                              double duration, bool playing, double now);

#endif
