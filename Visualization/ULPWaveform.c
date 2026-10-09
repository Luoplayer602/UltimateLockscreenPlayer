#include "ULPWaveform.h"
#include <math.h>
static float bound(float x, float lo, float hi) {
    return isfinite(x) ? fminf(hi, fmaxf(lo, x)) : 0;
}
void ULPWaveformUpdate(ULPWaveformState *state, const ULPMSH2FeatureFrame *frame,
                       float smoothing, float dt) {
    if (!state || !frame) return;
    smoothing = bound(smoothing, 0, 1);
    // PCM windows are not phase-aligned. Long temporal smoothing averages
    // opposite phases into a flat line, so keep even the maximum setting mild.
    float alpha = smoothing == 0 ? 1 : 1 - expf(-bound(dt, 0, .25f) / (.004f + smoothing * .024f));
    for (unsigned i = 0; i < ULP_MSH2_FEATURE_VALUES; ++i) {
        float target = (frame->featureMask & ULP_MSH2_WAVEFORM) ? bound(frame->waveform[i], -1, 1) : 0;
        state->samples[i] += alpha * (target - state->samples[i]);
    }
}
float ULPWaveformSample(const ULPWaveformState *state, float phase) {
    float position = bound(phase, 0, 1) * (ULP_MSH2_FEATURE_VALUES - 1);
    unsigned lo = (unsigned)position, hi = lo < ULP_MSH2_FEATURE_VALUES - 1 ? lo + 1 : lo;
    return state->samples[lo] + (state->samples[hi] - state->samples[lo]) * (position - lo);
}
float ULPWaveformOffset(float sample, float amplitude, float extent, bool mirror,
                        float gap, bool lower) {
    float offset = bound(sample, -1, 1) * bound(amplitude, 0, 2) * extent;
    if (!mirror) return offset;
    offset = fabsf(offset) + bound(gap, 0, 80) * .5f;
    return lower ? offset : -offset;
}
