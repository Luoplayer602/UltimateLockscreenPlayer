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
float ULPWaveformLoopSample(const ULPWaveformState *state, float phase) {
    if (!state || !isfinite(phase)) return 0;
    float turn = phase - floorf(phase);
    float position = turn * ULP_MSH2_FEATURE_VALUES;
    unsigned lo = (unsigned)position % ULP_MSH2_FEATURE_VALUES;
    unsigned hi = (lo + 1) % ULP_MSH2_FEATURE_VALUES;
    float a = bound(state->samples[lo], -1, 1);
    float b = bound(state->samples[hi], -1, 1);
    return a + (b - a) * (position - floorf(position));
}
float ULPCircularWaveformRadius(const ULPWaveformState *state, float phase,
                                float amplitude, float innerRadius) {
    float baseline = fminf(.8f, fmaxf(.1f, bound(innerRadius, .1f, .8f))) * .5f;
    float offset = ULPWaveformLoopSample(state, phase) * bound(amplitude, 0, 2) * .1375f;
    // Keep extreme inward peaks away from the centre and outward peaks inside
    // the layer. Silent PCM and zero amplitude produce the baseline circle.
    return bound(baseline + offset, .01f, .49f);
}
float ULPWaveformOffset(float sample, float amplitude, float extent, bool mirror,
                        float gap, bool lower) {
    float offset = bound(sample, -1, 1) * bound(amplitude, 0, 2) * extent;
    if (!mirror) return offset;
    offset = fabsf(offset) + bound(gap, 0, 80) * .5f;
    return lower ? offset : -offset;
}
float ULPSiriOffset(float sample, float phase, float amplitude, float extent,
                    unsigned layer) {
    float u = bound(phase, 0, 1);
    float envelope = powf(fmaxf(0, sinf(u * 3.14159265358979323846f)), .65f);
    float layerScale = 1 - fminf(layer, 2) * .22f;
    return ULPWaveformOffset(sample, amplitude, extent, false, 0, false) *
           envelope * layerScale;
}
