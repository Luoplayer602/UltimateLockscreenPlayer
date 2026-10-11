#include "ULPCover.h"
#include <math.h>

ULPCoverLayout ULPCoverLayoutForViewport(double w, double h, ULPVisualConfig config) {
    if (!isfinite(w) || !isfinite(h) || w <= 0 || h <= 0) return (ULPCoverLayout){0};
    config = ULPVisualConfigNormalize(config);
    double unit = w / 400;
    // Same 270-unit maximum diameter as the demo; compact Preview reserves
    // room for the circle and uses the native scene's vertical anchor.
    return (ULPCoverLayout){w / 2 + config.coverX * unit,
        h * (h < 240 ? .5 : .42) + config.coverY * unit,
        fmin(w * .675, h * .72) * config.coverSize, unit};
}

double ULPCoverAdvanceSpin(double angle, double seconds, double speed) {
    if (!isfinite(angle)) angle = 0;
    if (!isfinite(seconds) || seconds <= 0 || !isfinite(speed)) return angle;
    speed = fmin(90, fmax(-90, speed));
    // Do not catch up an offscreen/stalled interval in a single jump.
    return remainder(angle + fmin(.1, seconds) * speed * 3.14159265358979323846 / 180,
                     2 * 3.14159265358979323846);
}

static double unitLevel(double level) {
    return isfinite(level) ? fmin(1, fmax(0, level)) : 0;
}

static double phase(double time, double speed) {
    // Reduce before multiplication: very large finite times remain finite.
    return fmod(time, 2 * 3.14159265358979323846 / speed) * speed;
}

ULPCoverAmbient ULPCoverAmbientEvaluate(ULPVisualConfig c, double time,
                                        float rawLevel, float reactionLevel) {
    c = ULPVisualConfigNormalize(c);
    ULPCoverAmbient a = {.halo = c.coverGlow};
    if (!c.enabled || c.coverMode == ULPCoverModeOff || c.coverOpacity <= 0) return a;
    a.halo += c.coverGlowPulse * unitLevel(reactionLevel);
    if (!isfinite(time)) return a;
    double rumble = c.coverRumble * unitLevel(rawLevel);
    a.x = c.coverDrift * 25 * sin(phase(time, .63)) + rumble * 35 * sin(phase(time, 47));
    a.y = c.coverDrift * 25 * cos(phase(time, .49)) + rumble * 22 * cos(phase(time, 53));
    return a;
}

ULPCoverHaloBlend ULPCoverHaloWeights(float base, float pulse, float level) {
    base = isfinite(base) ? fminf(1, fmaxf(0, base)) : 0;
    pulse = isfinite(pulse) ? fminf(1.5, fmaxf(0, pulse)) : 0;
    double halo = base + pulse * unitLevel(level), opacity = fmin(1, halo);
    ULPCoverHaloBlend blend = {.levels = {0, .2, .5, 1, 1.75, 2.5}};
    unsigned lower = 0;
    while (lower + 1 < ULP_COVER_HALO_STAGES && halo >= blend.levels[lower + 1]) ++lower;
    double mix = lower + 1 < ULP_COVER_HALO_STAGES ?
        (halo - blend.levels[lower]) / (blend.levels[lower + 1] - blend.levels[lower]) : 0;
    blend.opacity[lower] = opacity * (1 - mix);
    if (lower + 1 < ULP_COVER_HALO_STAGES) blend.opacity[lower + 1] = opacity * mix;
    return blend;
}
