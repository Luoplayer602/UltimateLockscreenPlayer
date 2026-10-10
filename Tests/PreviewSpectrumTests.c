#include "../Audio/ULPPreviewSpectrum.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    float pcm[2048] = {0}, output[64];
    ULPPreviewSpectrum(pcm, 2048, 44100, output);
    for (unsigned i = 0; i < 64; ++i) assert(output[i] == 0);
    // A short bass transient reaches the spectrum immediately, and the next
    // silent window has no server-side release tail masking the next beat.
    for (unsigned i = 1024; i < 2048; ++i)
        pcm[i] = .15f * sinf(2 * 3.14159265358979323846f * 90 / 44100 * (i-1024));
    ULPPreviewSpectrum(pcm, 2048, 44100, output);
    assert(output[7] > .9f);
    float direct[64];
    ULPPreviewSpectrum(pcm + 1024, 1024, 44100, direct);
    for (unsigned i = 0; i < 64; ++i) assert(output[i] == direct[i]);
    // Older samples preceding the last 1024 must not affect the features.
    for (unsigned i = 0; i < 1024; ++i) pcm[i] = .9f;
    ULPPreviewSpectrum(pcm, 2048, 44100, output);
    for (unsigned i = 0; i < 64; ++i) assert(output[i] == direct[i]);
    for (unsigned i = 0; i < 2048; ++i) pcm[i] = 0;
    ULPPreviewSpectrum(pcm, 2048, 44100, output);
    for (unsigned i = 0; i < 64; ++i) assert(output[i] == 0);
    // Quiet treble keeps a nonzero response rather than a relative dB cutoff.
    float frequency = 45 * powf(1.1f, 50);
    for (unsigned i = 0; i < 1024; ++i)
        pcm[i] = .0001f * sinf(2 * 3.14159265358979323846f * frequency / 44100 * i);
    ULPPreviewSpectrum(pcm, 1024, 44100, output);
    assert(output[50] > .001f && output[50] < .002f);
    pcm[1] = NAN; pcm[2] = INFINITY;
    ULPPreviewSpectrum(pcm, 1024, 44100, output);
    for (unsigned i = 0; i < 64; ++i) assert(isfinite(output[i]) && output[i] >= 0 && output[i] <= 1);
    ULPPreviewSpectrum(pcm, 1023, 44100, output);
    for (unsigned i = 0; i < 64; ++i) assert(output[i] == 0);
    puts("PreviewSpectrumTests OK");
}
