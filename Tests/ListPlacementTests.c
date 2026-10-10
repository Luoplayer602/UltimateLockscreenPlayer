#include "../Playback/ULPListPlacement.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    ULPListPlacement s = {0};
    // Reproduced on iPhone: transient host at 207, native layout settles at 497.
    assert(ULPListPlacementBegin(&s, 207, 120) == 327);
    assert(ULPListPlacementObserve(&s, 497) == 617);
    assert(s.baseTop == 497);
    assert(ULPListPlacementRestingOffset(&s, -497, false) == -617);
    assert(ULPListPlacementRestingOffset(&s, -617, false) == -617);
    assert(ULPListPlacementRestingOffset(&s, -497, true) == -497);
    assert(ULPListPlacementRestingOffset(&s, -420, false) == -420);
    assert(ULPListPlacementRestingOffset(&s, -498, false) == -617);
    assert(ULPListPlacementRestingOffset(&s, -500, false) == -500);
    for (int i = 0; i < 100; ++i) {
        assert(ULPListPlacementObserve(&s, 497) == 617);
        assert(ULPListPlacementObserve(&s, 617) == 617);
    }
    assert(ULPListPlacementBegin(&s, 617, 90) == 587);
    assert(ULPListPlacementEnd(&s) == 497 && !s.active);
    assert(ULPListPlacementRestingOffset(&s, -497, false) == -497);
    assert(ULPListPlacementObserve(&s, 210) == 210);
    for (int i = 0; i < 20; ++i) {
        assert(ULPListPlacementBegin(&s, 497, 120) == 617);
        assert(ULPListPlacementEnd(&s) == 497);
    }
    s = (ULPListPlacement){0};
    assert(isfinite(ULPListPlacementBegin(&s, NAN, INFINITY)));
    puts("ListPlacementTests OK");
}
