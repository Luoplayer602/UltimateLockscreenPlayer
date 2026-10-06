#ifndef ULP_VISUAL_CONFIG_H
#define ULP_VISUAL_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

typedef enum {
    ULPSymmetryNone = 0,
    ULPSymmetryVertical = 1,
    ULPSymmetryHorizontal = 2,
    ULPSymmetryBoth = 3,
} ULPSymmetry;

typedef struct {
    bool enabled;
    uint8_t points;
    uint8_t framesPerSecond;
    uint8_t firstBand;
    uint8_t lastBand;
    ULPSymmetry symmetry;
    float offsetX;
    float offsetY;
    float animationScale;
    bool automaticColor;
} ULPVisualConfig;

ULPVisualConfig ULPVisualConfigDefault(void);
ULPVisualConfig ULPVisualConfigNormalize(ULPVisualConfig config);

#endif
