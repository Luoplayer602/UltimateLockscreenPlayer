#ifndef MSHF_FEATURE_PACING_H
#define MSHF_FEATURE_PACING_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint32_t phase;
    bool deliverImmediately;
} MSHFFeaturePacer;

typedef struct {
    uint64_t lastSilenceDeliveryNs;
    bool silenceObserved;
} MSHFSilencePacer;

typedef enum {
    MSHFSilencePacerSuppress = 0,
    MSHFSilencePacerDeliver,
    MSHFSilencePacerDeliverTransition,
} MSHFSilencePacerDecision;

static inline void MSHFResetFeaturePacer(MSHFFeaturePacer *pacer) {
    if (!pacer) {
        return;
    }
    pacer->phase = 0;
    pacer->deliverImmediately = true;
}

static inline bool MSHFFeaturePacerShouldDeliver(MSHFFeaturePacer *pacer,
                                                 uint16_t clientRate,
                                                 uint16_t analysisRate) {
    if (!pacer || clientRate == 0 || analysisRate == 0 ||
        clientRate > analysisRate) {
        return false;
    }
    if (pacer->deliverImmediately) {
        pacer->deliverImmediately = false;
        pacer->phase = 0;
        return true;
    }
    pacer->phase += clientRate;
    if (pacer->phase < analysisRate) {
        return false;
    }
    pacer->phase -= analysisRate;
    return true;
}

static inline void MSHFResetSilencePacer(MSHFSilencePacer *pacer) {
    if (!pacer) {
        return;
    }
    pacer->lastSilenceDeliveryNs = 0;
    pacer->silenceObserved = false;
}

static inline MSHFSilencePacerDecision
MSHFSilencePacerShouldDeliver(MSHFSilencePacer *pacer, bool silence,
                              uint64_t now, uint64_t heartbeatIntervalNs) {
    if (!pacer) {
        return MSHFSilencePacerSuppress;
    }
    if (!silence) {
        const bool transition = pacer->silenceObserved;
        pacer->silenceObserved = false;
        pacer->lastSilenceDeliveryNs = 0;
        return transition ? MSHFSilencePacerDeliverTransition
                          : MSHFSilencePacerDeliver;
    }
    if (!pacer->silenceObserved) {
        pacer->silenceObserved = true;
        pacer->lastSilenceDeliveryNs = now;
        return MSHFSilencePacerDeliverTransition;
    }
    if (heartbeatIntervalNs != 0 &&
        now - pacer->lastSilenceDeliveryNs >= heartbeatIntervalNs) {
        pacer->lastSilenceDeliveryNs = now;
        return MSHFSilencePacerDeliver;
    }
    return MSHFSilencePacerSuppress;
}

#endif
