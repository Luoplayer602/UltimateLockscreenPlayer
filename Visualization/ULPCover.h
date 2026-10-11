#ifndef ULP_COVER_H
#define ULP_COVER_H
#include "ULPVisualConfig.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double x, y, diameter, coordinateScale; } ULPCoverLayout;
ULPCoverLayout ULPCoverLayoutForViewport(double width, double height, ULPVisualConfig config);
double ULPCoverAdvanceSpin(double angle, double seconds, double degreesPerSecond);
// Offsets in the demo's 400-unit coordinate system. reactionLevel selects
// Raw or the detector envelope in the caller; independent of CoverReaction.
typedef struct { double x, y, halo; } ULPCoverAmbient;
ULPCoverAmbient ULPCoverAmbientEvaluate(ULPVisualConfig config, double time,
                                        float rawLevel, float reactionLevel);
// Zero plus five fixed cached radii. No live blur or rebuilding while sliders
// change Glow/GlowPulse. At most two textures are visible between anchors.
#define ULP_COVER_HALO_STAGES 6
typedef struct { double levels[ULP_COVER_HALO_STAGES], opacity[ULP_COVER_HALO_STAGES]; } ULPCoverHaloBlend;
ULPCoverHaloBlend ULPCoverHaloWeights(float base, float pulse, float level);
#ifdef __cplusplus
}
#endif
#endif
