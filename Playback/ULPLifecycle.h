#ifndef ULP_LIFECYCLE_H
#define ULP_LIFECYCLE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ULPPlaybackHidden = 0,
    ULPPlaybackPlaying = 1,
    ULPPlaybackPausePending = 2,
} ULPPlaybackPresentation;

typedef struct {
    ULPPlaybackPresentation presentation;
    uint64_t pauseDeadlineMs;
    uint32_t pauseDelayMs;
} ULPLifecycle;

void ULPLifecycleInit(ULPLifecycle *state, uint32_t pauseDelayMs);
void ULPLifecycleSetPlaying(ULPLifecycle *state, bool playing, uint64_t nowMs);
void ULPLifecycleTick(ULPLifecycle *state, uint64_t nowMs);
void ULPLifecycleReset(ULPLifecycle *state);
bool ULPLifecycleIsVisible(const ULPLifecycle *state);

#ifdef __cplusplus
}
#endif

#endif
