#include "ULPVisualConfig.h"

#include <math.h>

static float ULPBound(float value, float lower, float upper) {
    if (!isfinite(value)) return lower;
    return fminf(upper, fmaxf(lower, value));
}

ULPVisualConfig ULPVisualConfigDefault(void) {
    return (ULPVisualConfig){
        .enabled = true,
        .points = 64,
        .framesPerSecond = 60,
        .firstBand = 0,
        .lastBand = 63,
        .symmetry = ULPSymmetryVertical,
        .offsetX = 0,
        .offsetY = 0,
        .animationScale = 0.16f,
        .automaticColor = true,
    };
}

ULPVisualConfig ULPVisualConfigNormalize(ULPVisualConfig config) {
    if (config.points < 12) config.points = 12;
    if (config.points > 128) config.points = 128;
    if (config.framesPerSecond < 15) config.framesPerSecond = 15;
    if (config.framesPerSecond > 60) config.framesPerSecond = 60;
    if (config.firstBand > 63) config.firstBand = 63;
    if (config.lastBand > 63) config.lastBand = 63;
    if (config.lastBand < config.firstBand) config.lastBand = config.firstBand;
    if (config.symmetry > ULPSymmetryBoth) config.symmetry = ULPSymmetryVertical;
    config.offsetX = ULPBound(config.offsetX, -80, 80);
    config.offsetY = ULPBound(config.offsetY, -80, 80);
    config.animationScale = ULPBound(config.animationScale, 0, 0.30f);
    return config;
}
