#include "ULPLifecycle.h"

#include <limits.h>

void ULPLifecycleInit(ULPLifecycle *state, uint32_t pauseDelayMs) {
    if (!state) return;
    state->presentation = ULPPlaybackHidden;
    state->pauseDeadlineMs = 0;
    state->pauseDelayMs = pauseDelayMs;
}

void ULPLifecycleSetPlaying(ULPLifecycle *state, bool playing, uint64_t nowMs) {
    if (!state) return;
    if (playing) {
        state->presentation = ULPPlaybackPlaying;
        state->pauseDeadlineMs = 0;
    } else if (state->presentation == ULPPlaybackPlaying) {
        state->presentation = ULPPlaybackPausePending;
        state->pauseDeadlineMs = nowMs > UINT64_MAX - state->pauseDelayMs
                                     ? UINT64_MAX : nowMs + state->pauseDelayMs;
    }
}

void ULPLifecycleTick(ULPLifecycle *state, uint64_t nowMs) {
    if (!state) return;
    if (state->presentation == ULPPlaybackPausePending &&
        nowMs >= state->pauseDeadlineMs) {
        state->presentation = ULPPlaybackHidden;
        state->pauseDeadlineMs = 0;
    }
}

void ULPLifecycleReset(ULPLifecycle *state) {
    if (!state) return;
    state->presentation = ULPPlaybackHidden;
    state->pauseDeadlineMs = 0;
}

bool ULPLifecycleIsVisible(const ULPLifecycle *state) {
    return state && state->presentation != ULPPlaybackHidden;
}
