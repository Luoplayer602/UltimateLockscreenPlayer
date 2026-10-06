#ifndef ULP_SIGNAL_H
#define ULP_SIGNAL_H

#include <stdint.h>

#include "../Audio/MSH2Protocol.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t firstBand;
    uint8_t lastBand;
    float gain;
    float attack;
    float release;
} ULPBandConfig;

typedef struct {
    ULPBandConfig visual;
    ULPBandConfig zoom;
    float visualLevel;
    float zoomLevel;
} ULPSignalState;

void ULPSignalInit(ULPSignalState *state);
void ULPSignalProcess(ULPSignalState *state, const ULPMSH2FeatureFrame *frame);
float ULPSignalBandLevel(const ULPMSH2FeatureFrame *frame, ULPBandConfig config);

#ifdef __cplusplus
}
#endif

#endif
