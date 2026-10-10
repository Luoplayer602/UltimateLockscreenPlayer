#include "ULPListPlacement.h"
#include <math.h>
double ULPListPlacementBegin(ULPListPlacement *s, double top, double shift) {
    if (!s->active) s->baseTop = isfinite(top) ? top : 0;
    s->active = true;
    s->shift = isfinite(shift) ? fmax(0, shift) : 0;
    return s->appliedTop = s->baseTop + s->shift;
}
double ULPListPlacementObserve(ULPListPlacement *s, double top) {
    if (!s->active || !isfinite(top)) return top;
    // A setter echoing the already adjusted value must not add padding twice.
    if (fabs(top - s->appliedTop) > .5) s->baseTop = top;
    return s->appliedTop = s->baseTop + s->shift;
}
double ULPListPlacementEnd(ULPListPlacement *s) {
    s->active = false;
    s->shift = 0;
    return s->appliedTop = s->baseTop;
}
double ULPListPlacementRestingOffset(const ULPListPlacement *s, double offset,
                                    bool interacting) {
    // UIKit can restore the native home offset after applying our inset during
    // interactive CoverSheet presentation. Translate only that known anchor;
    // intentional scrolling and every offset during a gesture stay untouched.
    if (!s->active || interacting || !isfinite(offset)) return offset;
    if (fabs(offset + s->baseTop) < 2) return -s->appliedTop;
    return offset;
}
