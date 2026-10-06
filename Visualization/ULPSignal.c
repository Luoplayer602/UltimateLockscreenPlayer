#include "ULPSignal.h"

#include <math.h>
#include <stddef.h>

static float ULPClamp(float value, float low, float high) {
    if (!isfinite(value)) return low;
    return fminf(high, fmaxf(low, value));
}

void ULPSignalInit(ULPSignalState *state) {
    if (!state) return;
    *state = (ULPSignalState){
        .visual = {.firstBand = 0, .lastBand = 63, .gain = 1.0f,
                   .attack = 0.55f, .release = 0.16f},
        .zoom = {.firstBand = 0, .lastBand = 16, .gain = 1.0f,
                 .attack = 0.42f, .release = 0.10f},
    };
}

float ULPSignalBandLevel(const ULPMSH2FeatureFrame *frame, ULPBandConfig config) {
    if (!frame || !(frame->featureMask & ULP_MSH2_SPECTRUM)) return 0.0f;
    unsigned first = config.firstBand < ULP_MSH2_FEATURE_VALUES
                         ? config.firstBand : ULP_MSH2_FEATURE_VALUES - 1;
    unsigned last = config.lastBand < ULP_MSH2_FEATURE_VALUES
                        ? config.lastBand : ULP_MSH2_FEATURE_VALUES - 1;
    if (last < first) return 0.0f;
    float total = 0.0f;
    for (unsigned band = first; band <= last; ++band)
        total += ULPClamp(frame->spectrum[band], 0.0f, 1.0f);
    float mean = total / (last - first + 1);
    return ULPClamp(mean * config.gain, 0.0f, 1.0f);
}

static float ULPSmooth(float previous, float target, ULPBandConfig config) {
    float factor = target > previous ? config.attack : config.release;
    factor = ULPClamp(factor, 0.0f, 1.0f);
    return previous + (target - previous) * factor;
}

void ULPSignalProcess(ULPSignalState *state, const ULPMSH2FeatureFrame *frame) {
    if (!state) return;
    float visual = ULPSignalBandLevel(frame, state->visual);
    float zoom = ULPSignalBandLevel(frame, state->zoom);
    state->visualLevel = ULPSmooth(state->visualLevel, visual, state->visual);
    state->zoomLevel = ULPSmooth(state->zoomLevel, zoom, state->zoom);
}
