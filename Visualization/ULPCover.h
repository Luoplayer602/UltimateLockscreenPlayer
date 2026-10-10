#ifndef ULP_COVER_H
#define ULP_COVER_H
#include "ULPVisualConfig.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { double x, y, diameter, coordinateScale; } ULPCoverLayout;
ULPCoverLayout ULPCoverLayoutForViewport(double width, double height, ULPVisualConfig config);
double ULPCoverAdvanceSpin(double angle, double seconds, double degreesPerSecond);
#ifdef __cplusplus
}
#endif
#endif
