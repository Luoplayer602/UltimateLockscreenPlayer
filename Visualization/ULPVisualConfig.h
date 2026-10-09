#ifndef ULP_VISUAL_CONFIG_H
#define ULP_VISUAL_CONFIG_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    ULPSymmetryNone = 0,
    ULPSymmetryVertical = 1,
    ULPSymmetryHorizontal = 2,
    ULPSymmetryBoth = 3,
} ULPSymmetry;

typedef enum {
    ULPVisualModeCircle = 0,
    ULPVisualModeBar = 1,
    ULPVisualModeLine = 2,
    ULPVisualModeDot = 3,
    ULPVisualModeSiri = 4,
    ULPVisualModeWave = 5,
    ULPVisualModeRadial = 6,
    ULPVisualModeEqualizer = 7,
    ULPVisualModeDotMatrix = 8,
    ULPVisualModeMirror = 9,
} ULPVisualMode;

typedef enum {
    ULPVisualPresetCustom = 0,
    ULPVisualPresetClassicCircle = 1,
    ULPVisualPresetDrumCrown = 2,
    ULPVisualPresetSpectrumBars = 3,
    ULPVisualPresetDottedOrbit = 4,
    ULPVisualPresetMinimalLine = 5,
    ULPVisualPresetSiriFlow = 6,
    ULPVisualPresetWaveform = 7,
} ULPVisualPreset;

typedef struct {
    bool enabled;
    ULPVisualMode mode;
    ULPVisualPreset preset;
    uint8_t points;
    uint8_t framesPerSecond;
    uint8_t firstBand;
    uint8_t lastBand;
    ULPSymmetry symmetry;
    float offsetX;
    float offsetY;
    float animationScale;
    float scale;
    float zoomStrength;
    uint8_t zoomFirstBand;
    uint8_t zoomLastBand;
    float width;
    float height;
    float rotation;
    bool flipX;
    bool flipY;
    float opacity;
    float glow;
    float barWidth;
    float spacing;
    float barHeight;
    float cornerRadius;
    float frequencyRange;
    bool mirror;
    bool reverse;
    float edgeFade;
    uint8_t growFrom; // 0 bottom, 1 centre, 2 top.
    float minimumHeight;
    float dynamics;
    bool peakCaps;
    float capThickness;
    uint8_t rows;
    float dotSize;
    float unlitOpacity;
    float thickness;
    bool fill;
    float fillOpacity;
    bool mirrorVertical;
    bool automaticColor;
    float waveAmplitude;
    float waveSmoothing;
    float centreGap;
    bool smoothCurve;
} ULPVisualConfig;

ULPVisualConfig ULPVisualConfigDefault(void);
ULPVisualConfig ULPVisualConfigDefaultForMode(ULPVisualMode mode);
ULPVisualConfig ULPVisualConfigNormalize(ULPVisualConfig config);
ULPVisualMode ULPVisualModeForPreset(ULPVisualPreset preset);
const char *ULPVisualModeID(ULPVisualMode mode);
bool ULPVisualIsSpectrum(ULPVisualMode mode);
float ULPSpectrumFrequencyPhase(float phase, bool mirror, bool reverse);
float ULPSpectrumHeight(float level, float phase, ULPVisualConfig config);

#ifdef __cplusplus
}
#endif

#endif
