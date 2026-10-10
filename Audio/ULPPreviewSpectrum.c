#include "ULPPreviewSpectrum.h"
#include <math.h>
#include <string.h>
void ULPPreviewSpectrum(const float *samples, size_t count, float sampleRate,
                        float output[ULP_PREVIEW_BANDS]) {
    if (!output) return;
    memset(output, 0, sizeof(float) * ULP_PREVIEW_BANDS);
    if (!samples || count < ULP_PREVIEW_WINDOW || !isfinite(sampleRate) || sampleRate <= 0) return;
    samples += count - ULP_PREVIEW_WINDOW;
    for (unsigned band = 0; band < ULP_PREVIEW_BANDS; ++band) {
        float frequency = 45.0f * powf(1.1f, band);
        float coefficient = 2 * cosf(2 * 3.14159265358979323846f * frequency / sampleRate);
        float first = 0, second = 0;
        for (unsigned i = 0; i < ULP_PREVIEW_WINDOW; ++i) {
            float sample = isfinite(samples[i]) ? samples[i] : 0;
            float next = sample + coefficient * first - second;
            second = first; first = next;
        }
        float power = fmaxf(0, first * first + second * second - coefficient * first * second);
        output[band] = fminf(1, sqrtf(power) * 24 / ULP_PREVIEW_WINDOW);
    }
}
