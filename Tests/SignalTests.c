#include "../Visualization/ULPSignal.h"

#include <assert.h>
#include <math.h>

int main(void) {
    ULPSignalState state;
    ULPSignalInit(&state);
    assert(state.visual.firstBand == 0 && state.visual.lastBand == 63);
    assert(state.zoom.firstBand == 0 && state.zoom.lastBand == 16);

    ULPMSH2FeatureFrame frame = {.featureMask = ULP_MSH2_SPECTRUM};
    frame.spectrum[0] = 1.0f;
    frame.spectrum[63] = 1.0f;
    state.visual = (ULPBandConfig){.firstBand = 63, .lastBand = 63,
                                   .gain = 1, .attack = 1, .release = 1};
    state.zoom = (ULPBandConfig){.firstBand = 0, .lastBand = 0,
                                 .gain = 0.25f, .attack = 1, .release = 1};
    ULPSignalProcess(&state, &frame);
    assert(fabsf(state.visualLevel - 1.0f) < 0.001f);
    assert(fabsf(state.zoomLevel - 0.25f) < 0.001f);

    frame.spectrum[0] = 0;
    frame.spectrum[63] = 0;
    ULPSignalProcess(&state, &frame);
    assert(state.visualLevel == 0 && state.zoomLevel == 0);
    return 0;
}
