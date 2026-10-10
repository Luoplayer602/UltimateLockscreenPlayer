#include "ULPArtworkRequest.h"
#include <math.h>

void ULPArtworkRequestReset(ULPArtworkRequest *s) {
    if (!s) return;
    ++s->generation;
    s->attempts = 0;
    s->pending = false;
    s->retryAfter = 0;
}
bool ULPArtworkRequestBegin(ULPArtworkRequest *s, double now, ULPArtworkTicket *ticket) {
    if (!s || !ticket || !isfinite(now) || s->pending || s->attempts >= 4 || now < s->retryAfter)
        return false;
    s->pending = true;
    ++s->attempts;
    *ticket = (ULPArtworkTicket){s->generation, ++s->serial};
    return true;
}
bool ULPArtworkRequestMatches(const ULPArtworkRequest *s, ULPArtworkTicket ticket) {
    return s && s->pending && ticket.generation == s->generation && ticket.serial == s->serial;
}
bool ULPArtworkRequestFinish(ULPArtworkRequest *s, ULPArtworkTicket ticket, double now) {
    if (!ULPArtworkRequestMatches(s, ticket) || !isfinite(now)) return false;
    s->pending = false;
    s->retryAfter = now + (s->attempts < 2 ? 2 : s->attempts < 3 ? 4 : 8);
    return true;
}
