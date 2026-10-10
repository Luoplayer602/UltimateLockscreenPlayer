#include "../Playback/ULPArtworkRequest.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ULPArtworkRequest s = {0};
    ULPArtworkTicket old, next;
    ULPArtworkRequestReset(&s);
    assert(!ULPArtworkRequestBegin(&s, NAN, &old));
    assert(ULPArtworkRequestBegin(&s, 10, &old));
    assert(!ULPArtworkRequestBegin(&s, 11, &next)); // One in-flight request.
    ULPArtworkRequestReset(&s); // Track changed before the callback.
    assert(ULPArtworkRequestBegin(&s, 11, &next));
    assert(!ULPArtworkRequestMatches(&s, old));
    assert(!ULPArtworkRequestFinish(&s, old, 12)); // Must not cancel the new request.
    assert(ULPArtworkRequestMatches(&s, next));
    assert(ULPArtworkRequestFinish(&s, next, 12));
    assert(!ULPArtworkRequestBegin(&s, 13.9, &old));
    assert(ULPArtworkRequestBegin(&s, 14, &old));
    assert(!ULPArtworkRequestMatches(&s, next)); // Previous attempt's late result.
    assert(ULPArtworkRequestFinish(&s, old, 22));
    assert(!ULPArtworkRequestBegin(&s, 25.9, &next));
    assert(ULPArtworkRequestBegin(&s, 26, &next));
    assert(ULPArtworkRequestFinish(&s, next, 34));
    assert(!ULPArtworkRequestBegin(&s, 41.9, &old));
    assert(ULPArtworkRequestBegin(&s, 42, &old));
    assert(ULPArtworkRequestFinish(&s, old, 50));
    assert(!ULPArtworkRequestBegin(&s, 1000, &next)); // Four attempts per track.
    ULPArtworkRequestReset(&s);
    assert(ULPArtworkRequestBegin(&s, 1001, &next));
    assert(!ULPArtworkRequestFinish(&s, old, 1002));
    puts("ArtworkRequestTests OK");
}
