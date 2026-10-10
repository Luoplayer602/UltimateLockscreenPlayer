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
