#ifndef ULP_ARTWORK_REQUEST_H
#define ULP_ARTWORK_REQUEST_H
#include <stdint.h>
#include <stdbool.h>

typedef struct { uint64_t generation, serial; } ULPArtworkTicket;
typedef struct {
    uint64_t generation, serial;
    unsigned attempts;
    bool pending;
    double retryAfter;
} ULPArtworkRequest;

void ULPArtworkRequestReset(ULPArtworkRequest *state);
bool ULPArtworkRequestBegin(ULPArtworkRequest *state, double now, ULPArtworkTicket *ticket);
bool ULPArtworkRequestMatches(const ULPArtworkRequest *state, ULPArtworkTicket ticket);
bool ULPArtworkRequestFinish(ULPArtworkRequest *state, ULPArtworkTicket ticket, double now);
#endif
