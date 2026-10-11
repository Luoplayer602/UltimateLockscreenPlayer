#ifndef ULP_BEAT_H
#define ULP_BEAT_H
#include "../Audio/MSH2Protocol.h"
#include "ULPVisualConfig.h"

// Causal onset detection on the un-smoothed DSP64 spectrum. No tempo clock,
// future frames, allocations or per-track analysis. One state per renderer.
typedef struct {
    float previous[64], floor[64], mean[4], variance[4];
    double lastFrameAt, pulseAt, startedAt, lastBeatAt;
    uint64_t streamEpoch, count;
    float sampleRate, pulse, strength, score;
    bool initialized;
} ULPBeatState;
typedef struct { bool hit, reset; float pulse, strength, score; uint64_t count; } ULPBeatResult;
void ULPBeatReset(ULPBeatState *state);
void ULPBeatDecay(ULPBeatState *state, double time, float release);
ULPBeatResult ULPBeatProcess(ULPBeatState *state, const ULPMSH2FeatureFrame *frame,
                            double time, ULPVisualConfig config);

typedef struct { double scale, x, y, rotation, flash; } ULPBeatMotion;
typedef struct {
    ULPBeatMotion from;
    double startedAt;
    float strength;
    ULPBeatMotionType type;
    bool active;
} ULPBeatMotionState;
ULPBeatMotion ULPBeatMotionIdentity(void);
ULPBeatMotion ULPBeatMotionEvaluate(const ULPBeatMotionState *state, double time);
void ULPBeatMotionTrigger(ULPBeatMotionState *state, ULPBeatMotionType type,
                          float strength, double time);
bool ULPBeatMotionActive(const ULPBeatMotionState *state, double time);
#endif
