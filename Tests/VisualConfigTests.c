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
    for (int mode = 0; mode <= ULPVisualModeMirror; ++mode) {
        ULPVisualConfig c = ULPVisualConfigDefaultForMode((ULPVisualMode)mode);
        assert(c.mode == (ULPVisualMode)mode);
        for (int other = mode + 1; other <= ULPVisualModeMirror; ++other)
            assert(strcmp(ULPVisualModeID((ULPVisualMode)mode),
                          ULPVisualModeID((ULPVisualMode)other)) != 0);
    }
    assert(strcmp(ULPVisualModeID(ULPVisualModeDot), "dotted-orbit") == 0);
    assert(ULPVisualConfigDefaultForMode(ULPVisualModeEqualizer).points == 32);
    assert(ULPVisualConfigDefaultForMode(ULPVisualModeDotMatrix).rows == 12);

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
    puts("VisualConfigTests OK");
    return 0;
}
