#include "../Playback/ULPLifecycle.h"

#include <assert.h>

int main(void) {
    ULPLifecycle state;
    ULPLifecycleInit(&state, 15000);
    assert(!ULPLifecycleIsVisible(&state));
    ULPLifecycleSetPlaying(&state, true, 1000);
    assert(state.presentation == ULPPlaybackPlaying);
    ULPLifecycleSetPlaying(&state, false, 2000);
    assert(state.pauseDeadlineMs == 17000);
    ULPLifecycleTick(&state, 16999);
    assert(ULPLifecycleIsVisible(&state));
    ULPLifecycleSetPlaying(&state, true, 16999);
    ULPLifecycleTick(&state, 20000);
    assert(state.presentation == ULPPlaybackPlaying);
    ULPLifecycleSetPlaying(&state, false, 21000);
    ULPLifecycleTick(&state, 36000);
    assert(!ULPLifecycleIsVisible(&state));
    ULPLifecycleReset(&state);
    assert(!ULPLifecycleIsVisible(&state));
    return 0;
}
