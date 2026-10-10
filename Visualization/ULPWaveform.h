#ifndef ULP_WAVEFORM_H
#define ULP_WAVEFORM_H
#include "../Audio/MSH2Protocol.h"
#include <stdbool.h>
typedef struct { float samples[ULP_MSH2_FEATURE_VALUES]; } ULPWaveformState;
void ULPWaveformUpdate(ULPWaveformState *state, const ULPMSH2FeatureFrame *frame,
                       float smoothing, float deltaSeconds);
float ULPWaveformSample(const ULPWaveformState *state, float phase);
// Periodic PCM sampling joins the last sample to the first without duplicating
// or mirroring the waveform. Radius is expressed as a fraction of layer size.
float ULPWaveformLoopSample(const ULPWaveformState *state, float phase);
float ULPCircularWaveformRadius(const ULPWaveformState *state, float phase,
                                float amplitude, float innerRadius);
float ULPWaveformOffset(float sample, float amplitude, float extent, bool mirror,
                        float gap, bool lower);
float ULPSiriOffset(float sample, float phase, float amplitude, float extent,
                    unsigned layer);
#endif
