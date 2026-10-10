#ifndef ULP_TRAIL_H
#define ULP_TRAIL_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// One retained footprint, independent of duration/FPS. No frame queue.
#define ULP_TRAIL_MAX_PIXELS ((size_t)524288)

typedef struct {
    uint8_t rgba[4]; // Original premultiplied colour, before fading.
    float coverage; // Floating point alpha avoids frame-rate-dependent rounding.
} ULPTrailPixel;

typedef struct {
    size_t width, height;
    ULPTrailPixel *history;
    uint8_t *current; // Premultiplied RGBA, top row first.
    uint8_t *output;  // Only the residual needed UNDER the live vector shapes.
    bool hasOutput;
} ULPTrailBuffer;

// Zero-initialize before use. A rejected resize leaves the old buffer intact.
bool ULPTrailResize(ULPTrailBuffer *buffer, size_t width, size_t height);
void ULPTrailFree(ULPTrailBuffer *buffer);
// capture=false fades history without feeding the frozen live frame back in.
// Returns whether history remains above the alpha quantization threshold.
bool ULPTrailComposite(ULPTrailBuffer *buffer, double seconds, float duration,
                       float trailOpacity, float visualOpacity, bool capture);

#endif
