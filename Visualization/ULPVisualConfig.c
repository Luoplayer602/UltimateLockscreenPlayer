#include "ULPVisualConfig.h"

#include <math.h>

static float ULPBound(float value, float lower, float upper) {
    if (!isfinite(value)) return lower;
    return fminf(upper, fmaxf(lower, value));
}

ULPVisualConfig ULPVisualConfigDefault(void) {
    return (ULPVisualConfig){
        .enabled = true,
        .mode = ULPVisualModeCircle,
        .preset = ULPVisualPresetCustom,
        .points = 64,
        .framesPerSecond = 60,
        .firstBand = 0,
        .lastBand = 63,
        .symmetry = ULPSymmetryVertical,
        .offsetX = 0,
        .offsetY = 0,
        .animationScale = 0.16f,
        .scale = 1.0f,
        .zoomStrength = 0.18f,
        .zoomFirstBand = 0, .zoomLastBand = 16,
        .width = 1, .height = 1, .opacity = 1, .glow = 0.35f,
        .spacing = 0.25f, .barHeight = 1, .frequencyRange = 1,
        .mirror = true, .minimumHeight = 2, .dynamics = 1,
        .capThickness = 1, .rows = 16, .dotSize = 4,
        .unlitOpacity = 0.08f, .thickness = 2, .fillOpacity = 0.2f,
        .automaticColor = true,
        .waveAmplitude = 1, .waveSmoothing = 0, .centreGap = 12, .smoothCurve = true,
        .innerRadius = 0.38f, .radialBarLength = 0.45f,
        .radialBarThickness = 2, .radialSymmetry = 1,
        .roundedCaps = true, .showInnerRing = true, .ringOpacity = 0.4f,
    };
}

ULPVisualConfig ULPVisualConfigNormalize(ULPVisualConfig config) {
    if (config.mode < ULPVisualModeCircle || config.mode > ULPVisualModeMirror)
        config.mode = ULPVisualModeCircle;
    if (config.preset < ULPVisualPresetCustom || config.preset > ULPVisualPresetWaveform)
        config.preset = ULPVisualPresetCustom;
    if (config.preset != ULPVisualPresetCustom)
        config.mode = ULPVisualModeForPreset(config.preset);
    if (config.points < 12) config.points = 12;
    if (config.points > 128) config.points = 128;
    if (config.framesPerSecond < 15) config.framesPerSecond = 15;
    if (config.framesPerSecond > 60) config.framesPerSecond = 60;
    if (config.firstBand > 63) config.firstBand = 63;
    if (config.lastBand > 63) config.lastBand = 63;
    if (config.lastBand < config.firstBand) config.lastBand = config.firstBand;
    if (config.symmetry < ULPSymmetryNone || config.symmetry > ULPSymmetryBoth)
        config.symmetry = ULPSymmetryVertical;
    config.offsetX = ULPBound(config.offsetX, -80, 80);
    config.offsetY = ULPBound(config.offsetY, -80, 80);
    config.animationScale = ULPBound(config.animationScale, 0, 0.30f);
    config.scale = ULPBound(config.scale, 0.5f, 1.8f);
    config.zoomStrength = ULPBound(config.zoomStrength, 0, 0.4f);
    if (config.zoomFirstBand > 63) config.zoomFirstBand = 63;
    if (config.zoomLastBand > 63) config.zoomLastBand = 63;
    if (config.zoomLastBand < config.zoomFirstBand) config.zoomLastBand = config.zoomFirstBand;
    config.width = ULPBound(config.width, 0.25f, 2);
    config.height = ULPBound(config.height, 0.25f, 2);
    config.rotation = ULPBound(config.rotation, -180, 180);
    config.opacity = ULPBound(config.opacity, 0, 1);
    config.glow = ULPBound(config.glow, 0, 1);
    config.barWidth = ULPBound(config.barWidth, 0, 24);
    config.spacing = ULPBound(config.spacing, 0, 0.9f);
    config.barHeight = ULPBound(config.barHeight, 0.05f, 1);
    config.cornerRadius = ULPBound(config.cornerRadius, 0, 12);
    config.frequencyRange = ULPBound(config.frequencyRange, 0, 1);
    config.edgeFade = ULPBound(config.edgeFade, 0, 1);
    if (config.growFrom > 2) config.growFrom = 0;
    config.minimumHeight = ULPBound(config.minimumHeight, 0, 12);
    config.dynamics = ULPBound(config.dynamics, 0.25f, 4);
    config.capThickness = ULPBound(config.capThickness, 0.5f, 6);
    if (config.rows < 4) config.rows = 4;
    if (config.rows > 32) config.rows = 32;
    config.dotSize = ULPBound(config.dotSize, 1, 16);
    config.unlitOpacity = ULPBound(config.unlitOpacity, 0, 1);
    config.thickness = ULPBound(config.thickness, 0.5f,
        config.mode == ULPVisualModeWave || config.mode == ULPVisualModeMirror ||
        config.mode == ULPVisualModeSiri ? 12 : 8);
    config.waveAmplitude = ULPBound(config.waveAmplitude, 0, 2);
    config.waveSmoothing = ULPBound(config.waveSmoothing, 0, 1);
    config.centreGap = ULPBound(config.centreGap, 0, 80);
    config.fillOpacity = ULPBound(config.fillOpacity, 0, 1);
    config.innerRadius = ULPBound(config.innerRadius, 0.1f, 0.8f);
    config.radialBarLength = ULPBound(config.radialBarLength, 0, 1);
    config.radialBarThickness = ULPBound(config.radialBarThickness, 0.5f, 12);
    config.rotationSpeed = ULPBound(config.rotationSpeed, -90, 90);
    if (config.radialSymmetry < 1) config.radialSymmetry = 1;
    if (config.radialSymmetry > 12) config.radialSymmetry = 12;
    config.ringOpacity = ULPBound(config.ringOpacity, 0, 1);
    if (config.peakCapsType > 1) config.peakCapsType = 0;
    return config;
}

ULPVisualConfig ULPVisualConfigDefaultForMode(ULPVisualMode mode) {
    ULPVisualConfig config = ULPVisualConfigDefault();
    config.mode = mode;
    if (mode == ULPVisualModeBar || mode == ULPVisualModeEqualizer) config.points = 32;
    if (mode == ULPVisualModeDotMatrix) { config.points = 24; config.rows = 12; }
    if (mode == ULPVisualModeRadial) config.points = 64;
    if (mode == ULPVisualModeWave || mode == ULPVisualModeMirror ||
        mode == ULPVisualModeSiri) {
        config.thickness = 3;
        config.symmetry = ULPSymmetryNone;
    }
    return ULPVisualConfigNormalize(config);
}

const char *ULPVisualModeID(ULPVisualMode mode) {
    switch (mode) {
        case ULPVisualModeBar: return "bar";
        case ULPVisualModeEqualizer: return "equalizer";
        case ULPVisualModeLine: return "line";
        case ULPVisualModeDotMatrix: return "dot-matrix";
        case ULPVisualModeSiri: return "siri";
        case ULPVisualModeWave: return "waveform";
        case ULPVisualModeMirror: return "mirror";
        case ULPVisualModeRadial: return "spectro";
        case ULPVisualModeDot: return "dotted-orbit";
        default: return "classic-circle";
    }
}

bool ULPVisualIsSpectrum(ULPVisualMode mode) {
    return mode == ULPVisualModeBar || mode == ULPVisualModeEqualizer ||
           mode == ULPVisualModeLine || mode == ULPVisualModeDotMatrix;
}

float ULPSpectrumFrequencyPhase(float phase, bool mirror, bool reverse) {
    phase = ULPBound(phase, 0, 1);
    // Mirrored bass belongs at the centre, treble at both edges.
    if (mirror) phase = fabsf(2 * phase - 1);
    return reverse ? 1 - phase : phase;
}

float ULPSpectrumHeight(float level, float phase, ULPVisualConfig config) {
    float taper = 1 - config.edgeFade * fabsf(2 * ULPBound(phase, 0, 1) - 1);
    return powf(ULPBound(level, 0, 1), config.dynamics) * taper * config.barHeight;
}

ULPVisualMode ULPVisualModeForPreset(ULPVisualPreset preset) {
    switch (preset) {
        case ULPVisualPresetDrumCrown: return ULPVisualModeRadial;
        case ULPVisualPresetSpectrumBars: return ULPVisualModeBar;
        case ULPVisualPresetDottedOrbit: return ULPVisualModeDot;
        case ULPVisualPresetMinimalLine: return ULPVisualModeLine;
        case ULPVisualPresetSiriFlow: return ULPVisualModeSiri;
        case ULPVisualPresetWaveform: return ULPVisualModeWave;
        default: return ULPVisualModeCircle;
    }
}
