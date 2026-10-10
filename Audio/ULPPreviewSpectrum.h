#ifndef ULP_PREVIEW_SPECTRUM_H
#define ULP_PREVIEW_SPECTRUM_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define ULP_PREVIEW_WINDOW 1024
#define ULP_PREVIEW_BANDS 64
// The accepted native Preview's spectrum, shared with the server build.
// Input is a chronological mono PCM window; output has no temporal smoothing.
void ULPPreviewSpectrum(const float *samples, size_t count, float sampleRate,
                        float output[ULP_PREVIEW_BANDS]);
#ifdef __cplusplus
}
#endif
#endif
