#ifndef ULP_WAVEFORM_H
#define ULP_WAVEFORM_H
#include "../Audio/MSH2Protocol.h"
#include <stdbool.h>
typedef struct { float samples[ULP_MSH2_FEATURE_VALUES]; } ULPWaveformState;
void ULPWaveformUpdate(ULPWaveformState *state, const ULPMSH2FeatureFrame *frame,
                       float smoothing, float deltaSeconds);
float ULPWaveformSample(const ULPWaveformState *state, float phase);
float ULPWaveformOffset(float sample, float amplitude, float extent, bool mirror,
                        float gap, bool lower);
float ULPSiriOffset(float sample, float phase, float amplitude, float extent,
                    unsigned layer);
#endif
