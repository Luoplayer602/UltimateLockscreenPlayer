#include "../Visualization/ULPVisualConfig.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    ULPVisualConfig defaults = ULPVisualConfigDefault();
    assert(defaults.enabled && defaults.points == 64 && defaults.framesPerSecond == 60);
    assert(defaults.firstBand == 0 && defaults.lastBand == 63);
    assert(defaults.symmetry == ULPSymmetryVertical);
    assert(defaults.mode == ULPVisualModeCircle);
    assert(defaults.scale == 1.0f && defaults.zoomStrength == 0.18f);
    assert(defaults.colorMode == 2 && defaults.automaticColor);
    assert(defaults.artworkBackground && defaults.artworkBackgroundType == 2);
    assert(ULPVisualModeForPreset(ULPVisualPresetSpectrumBars) == ULPVisualModeBar);
    assert(ULPVisualModeForPreset(ULPVisualPresetSiriFlow) == ULPVisualModeSiri);

    ULPVisualConfig preset = defaults;
    preset.preset = ULPVisualPresetDottedOrbit;
    preset.mode = ULPVisualModeWave;
    preset = ULPVisualConfigNormalize(preset);
    assert(preset.mode == ULPVisualModeDot);

    ULPVisualConfig invalid = defaults;
    invalid.points = 3;
    invalid.framesPerSecond = 1;
    invalid.firstBand = 50;
    invalid.lastBand = 10;
    invalid.symmetry = (ULPSymmetry)-1;
    invalid.mode = (ULPVisualMode)99;
    invalid.preset = (ULPVisualPreset)99;
    invalid.offsetX = INFINITY;
    invalid.offsetY = -100;
    invalid.animationScale = NAN;
    invalid.scale = 9;
    invalid.zoomStrength = -1;
    invalid = ULPVisualConfigNormalize(invalid);
    assert(invalid.points == 12 && invalid.framesPerSecond == 15);
    assert(invalid.firstBand == 50 && invalid.lastBand == 50);
    assert(invalid.symmetry == ULPSymmetryVertical);
    assert(invalid.mode == ULPVisualModeCircle);
    assert(invalid.preset == ULPVisualPresetCustom);
    assert(invalid.offsetX == -80 && invalid.offsetY == -80);
    assert(invalid.animationScale == 0);
    assert(invalid.scale == 1.8f && invalid.zoomStrength == 0);

    // Distinct stable storage IDs must survive adding new modes.
    for (int mode = 0; mode <= ULPVisualModeSmoothSpectro; ++mode) {
        ULPVisualConfig c = ULPVisualConfigDefaultForMode((ULPVisualMode)mode);
        assert(c.mode == (ULPVisualMode)mode);
        for (int other = mode + 1; other <= ULPVisualModeSmoothSpectro; ++other)
            assert(strcmp(ULPVisualModeID((ULPVisualMode)mode),
                          ULPVisualModeID((ULPVisualMode)other)) != 0);
    }
    assert(strcmp(ULPVisualModeID(ULPVisualModeDot), "dotted-orbit") == 0);
    assert(ULPVisualConfigDefaultForMode(ULPVisualModeEqualizer).points == 32);
    assert(ULPVisualConfigDefaultForMode(ULPVisualModeDotMatrix).rows == 12);
    ULPVisualConfig siri = ULPVisualConfigDefaultForMode(ULPVisualModeSiri);
    assert(siri.thickness == 3 && siri.waveAmplitude == 1);
    assert(siri.symmetry == ULPSymmetryNone && siri.smoothCurve);
    siri.thickness = 15;
    assert(ULPVisualConfigNormalize(siri).thickness == 12);

    // Mirroring centres bass; reversing then centres treble.
    assert(ULPSpectrumFrequencyPhase(0.5f, true, false) == 0);
    assert(ULPSpectrumFrequencyPhase(0, true, false) == 1);
    assert(ULPSpectrumFrequencyPhase(1, true, false) == 1);
    assert(ULPSpectrumFrequencyPhase(0.5f, true, true) == 1);
    assert(ULPSpectrumFrequencyPhase(0.25f, false, true) == 0.75f);
    ULPVisualConfig bars = ULPVisualConfigDefaultForMode(ULPVisualModeBar);
    bars.dynamics = 2;
    bars.edgeFade = 1;
    assert(ULPSpectrumHeight(0.5f, 0.5f, bars) == 0.25f);
    assert(ULPSpectrumHeight(1, 0, bars) == 0);
    assert(ULPSpectrumHeight(1, 1, bars) == 0);
    assert(ULPSpectrumHeight(NAN, 0.5f, bars) == 0);
    bars.rows = 255; bars.spacing = 2; bars.frequencyRange = -1;
    bars.growFrom = 255; bars.minimumHeight = INFINITY;
    bars.zoomFirstBand = 60; bars.zoomLastBand = 2;
    bars = ULPVisualConfigNormalize(bars);
    assert(bars.rows == 32 && bars.spacing == 0.9f && bars.frequencyRange == 0);
    assert(bars.growFrom == 0 && bars.minimumHeight == 0);
    assert(bars.zoomFirstBand == 60 && bars.zoomLastBand == 60);

    ULPVisualConfig wave = ULPVisualConfigDefaultForMode(ULPVisualModeMirror);
    assert(wave.thickness == 3 && wave.waveAmplitude == 1 && wave.centreGap == 12);
    assert(strcmp(ULPVisualModeID(wave.mode), "mirror") == 0);
    wave.waveAmplitude = 99; wave.waveSmoothing = NAN; wave.centreGap = -3; wave.thickness = 15;
    wave = ULPVisualConfigNormalize(wave);
    assert(wave.waveAmplitude == 2 && wave.waveSmoothing == 0 && wave.centreGap == 0 && wave.thickness == 12);
    ULPVisualConfig spectro = ULPVisualConfigDefaultForMode(ULPVisualModeRadial);
    assert(spectro.innerRadius == .38f && spectro.radialBarLength == .45f);
    assert(spectro.radialSymmetry == 1 && spectro.showInnerRing && spectro.roundedCaps);
    spectro.innerRadius = 2; spectro.radialBarLength = -1;
    spectro.radialBarThickness = 50; spectro.rotationSpeed = -200;
    spectro.radialSymmetry = 0; spectro.peakCapsType = 4;
    spectro = ULPVisualConfigNormalize(spectro);
    assert(spectro.innerRadius == .8f && spectro.radialBarLength == 0);
    assert(spectro.radialBarThickness == 12 && spectro.rotationSpeed == -90);
    assert(spectro.radialSymmetry == 1 && spectro.peakCapsType == 0);
    ULPVisualConfig circular = ULPVisualConfigDefaultForMode(ULPVisualModeCircularWave);
    assert(circular.mode == 10 && circular.points == 64 && circular.thickness == 3);
    assert(circular.symmetry == ULPSymmetryNone && circular.innerRadius == .38f);
    assert(circular.waveAmplitude == 1 && circular.rotationSpeed == 0 && !circular.fill);
    assert(strcmp(ULPVisualModeID(circular.mode), "circular-waveform") == 0);
    circular.thickness = 20; circular.waveAmplitude = -1; circular.rotationSpeed = INFINITY;
    circular = ULPVisualConfigNormalize(circular);
    assert(circular.thickness == 12 && circular.waveAmplitude == 0 && circular.rotationSpeed == -90);
    ULPVisualConfig smooth = ULPVisualConfigDefaultForMode(ULPVisualModeSmoothSpectro);
    assert(smooth.mode == 11 && smooth.points == 64 && smooth.thickness == 3);
    assert(smooth.smoothSpectroSize == .42f && smooth.smoothSpectroReactivity == .5f);
    assert(smooth.radialSymmetry == 1 && smooth.symmetry == ULPSymmetryNone && !smooth.fill);
    assert(strcmp(ULPVisualModeID(smooth.mode), "smooth-spectro") == 0);
    smooth.smoothSpectroSize = NAN; smooth.smoothSpectroReactivity = 99; smooth.thickness = 20;
    smooth = ULPVisualConfigNormalize(smooth);
    assert(smooth.smoothSpectroSize == .1f && smooth.smoothSpectroReactivity == 2 && smooth.thickness == 12);
    // Silence and zero reactivity give the base circle; loud bands only bulge
    // outward. Size controls the base independently of audio gain.
    assert(fabsf(ULPSmoothSpectroRadius(0, .42f, 2) - .21f) < 1e-6f);
    assert(fabsf(ULPSmoothSpectroRadius(1, .42f, 0) - .21f) < 1e-6f);
    assert(fabsf(ULPSmoothSpectroRadius(1, .42f, .5f) - .29125f) < 1e-6f);
    assert(fabsf(ULPSmoothSpectroRadius(1, 1, 2) - .825f) < 1e-6f);
    assert(isfinite(ULPSmoothSpectroRadius(NAN, INFINITY, NAN)));
    // One segment is unfolded, while multiple segments fold both halves and
    // repeat without changing the 1-segment frequency order.
    assert(ULPRadialFrequencyPhase(.25f, 1) == .25f);
    assert(ULPRadialFrequencyPhase(.125f, 2) == .5f);
    assert(ULPRadialFrequencyPhase(.375f, 2) == .5f);
    assert(ULPRadialFrequencyPhase(.125f, 2) == ULPRadialFrequencyPhase(.625f, 2));
    assert(ULPRadialFrequencyPhase(.25f, 2) == 0);
    ULPVisualConfig style = defaults;
    style.colorMode = 1; style.color1 = 0xFF010203;
    style.gradientAngle = 999; style.backgroundMode = 99; style.artworkBackgroundType = 99;
    style = ULPVisualConfigNormalize(style);
    assert(!style.automaticColor && style.color1 == 0x010203 && style.gradientAngle == 360);
    assert(style.backgroundMode == 0 && style.artworkBackgroundType == 2);
    puts("VisualConfigTests OK");
    return 0;
}
