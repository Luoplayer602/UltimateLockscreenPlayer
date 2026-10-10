#ifndef ULP_LIST_PLACEMENT_H
#define ULP_LIST_PLACEMENT_H
#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    bool active;
    double baseTop, shift, appliedTop;
} ULPListPlacement;
double ULPListPlacementBegin(ULPListPlacement *state, double top, double shift);
double ULPListPlacementObserve(ULPListPlacement *state, double systemTop);
double ULPListPlacementEnd(ULPListPlacement *state);
double ULPListPlacementRestingOffset(const ULPListPlacement *state, double offset,
                                    bool interacting);
#ifdef __cplusplus
}
#endif
#endif
