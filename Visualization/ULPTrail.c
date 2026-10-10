#include "ULPTrail.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

static float unit(float value) {
    return isfinite(value) ? fminf(1, fmaxf(0, value)) : 0;
}

bool ULPTrailResize(ULPTrailBuffer *buffer, size_t width, size_t height) {
    if (!buffer || !width || !height || width > ULP_TRAIL_MAX_PIXELS / height)
        return false;
    if (buffer->history && width == buffer->width && height == buffer->height)
        return true;
    size_t count = width * height;
    ULPTrailPixel *history = calloc(count, sizeof(*history));
    uint8_t *current = calloc(count, 4), *output = calloc(count, 4);
    if (!history || !current || !output) {
        free(history); free(current); free(output);
        return false;
    }
    ULPTrailFree(buffer);
    *buffer = (ULPTrailBuffer){.width = width, .height = height,
        .history = history, .current = current, .output = output};
    return true;
}

void ULPTrailFree(ULPTrailBuffer *buffer) {
    if (!buffer) return;
    free(buffer->history); free(buffer->current); free(buffer->output);
    memset(buffer, 0, sizeof(*buffer));
}

bool ULPTrailComposite(ULPTrailBuffer *buffer, double seconds, float duration,
                       float trailOpacity, float visualOpacity, bool capture) {
    if (!buffer || !buffer->history) return false;
    seconds = isfinite(seconds) ? fmax(0, seconds) : 10;
    duration = isfinite(duration) ? fminf(2, fmaxf(.1f, duration)) : .1f;
    float retention = (float)exp(log(.01) * seconds / duration);
    trailOpacity = unit(trailOpacity); visualOpacity = unit(visualOpacity);
    float currentAlpha[256], inverse[256];
    for (unsigned alpha = 0; alpha < 256; ++alpha) {
        currentAlpha[alpha] = alpha * visualOpacity;
        inverse[alpha] = currentAlpha[alpha] < 255 ?
                        1 / (1 - currentAlpha[alpha] / 255) : 0;
    }
    size_t count = buffer->width * buffer->height;
    memset(buffer->output, 0, count * 4);
    buffer->hasOutput = false;
    bool alive = false;
    for (size_t i = 0; i < count; ++i) {
        ULPTrailPixel *old = &buffer->history[i];
        const uint8_t *current = buffer->current + i * 4;
        float coverage = old->coverage * retention;
        if (capture && current[3] && current[3] >= coverage) {
            memcpy(old->rgba, current, 4);
            coverage = current[3];
        }
        old->coverage = coverage;
        if (coverage < .5f) continue;
        alive = true;
        float target = coverage * trailOpacity * visualOpacity;
        if (target < .5f) continue;
        float source = currentAlpha[current[3]];
        if (target <= source || !old->rgba[3]) continue;
        // source + residual * (1 - source) = max(source, target).
        // A stationary translucent fill therefore never accumulates brightness.
        unsigned alpha = (unsigned)lroundf(fminf(255, (target - source) * inverse[current[3]]));
        if (!alpha) continue;
        buffer->hasOutput = true;
        uint8_t *output = buffer->output + i * 4;
        output[3] = (uint8_t)alpha;
        for (unsigned channel = 0; channel < 3; ++channel)
            output[channel] = (uint8_t)lroundf(fminf(alpha,
                old->rgba[channel] * (float)alpha / old->rgba[3]));
    }
    return alive;
}
