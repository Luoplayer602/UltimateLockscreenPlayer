#include "../Visualization/ULPWaveform.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void) {
    ULPMSH2FeatureFrame frame = {0};
    frame.featureMask = ULP_MSH2_WAVEFORM;
    for (unsigned i=0;i<64;i++) frame.waveform[i] = sinf((float)i*.2f);
    ULPWaveformState a={0},b={0};
    ULPWaveformUpdate(&a,&frame,0,1.f/60);
    assert(ULPWaveformSample(&a,0)==frame.waveform[0]);
    assert(fabsf(ULPWaveformSample(&a,1)-frame.waveform[63])<1e-6f);
    assert(ULPWaveformSample(&a,.4f)<0); // Keep the signed PCM, not spectral magnitudes.
    for (int pass=0;pass<8;pass++) {
        frame.waveform[1] = pass % 2 ? -1 : 1;
        ULPWaveformUpdate(&a,&frame,0,1.f/60);
        assert(a.samples[1] == frame.waveform[1]); // Default keeps the original motion.
    }
    ULPWaveformState changing = {0};
    for (int pass=0;pass<40;pass++) {
        frame.waveform[1] = pass % 2 ? -1 : 1;
        ULPWaveformUpdate(&changing,&frame,1,1.f/60);
    }
    assert(fabsf(changing.samples[1]) > .2f); // Even maximum smoothing remains visible.
    for (unsigned i=0;i<64;i++) {
        float x=frame.waveform[i];
        float upper=ULPWaveformOffset(x,1,95,true,12,false);
        float lower=ULPWaveformOffset(x,1,95,true,12,true);
        assert(upper == -lower && lower >= 6);
        assert(ULPWaveformOffset(x,0,95,false,0,false)==0);
    }
    assert(fabsf(ULPSiriOffset(1,0,1,95,0)) < 1e-5f);
    assert(fabsf(ULPSiriOffset(1,1,1,95,0)) < 1e-3f);
    assert(fabsf(ULPSiriOffset(1,.5f,1,95,0)-95) < 1e-4f);
    assert(fabsf(ULPSiriOffset(-1,.5f,1,95,1)+95*.78f) < 1e-4f);
    assert(fabsf(ULPSiriOffset(1,.5f,1,95,2)-95*.56f) < 1e-4f);
    assert(ULPSiriOffset(1,.2f,0,95,0) == 0);
    a=(ULPWaveformState){0};
    for(int i=0;i<60;i++) ULPWaveformUpdate(&a,&frame,.7f,1.f/60);
    for(int i=0;i<30;i++) ULPWaveformUpdate(&b,&frame,.7f,1.f/30);
    for(int i=0;i<64;i++) assert(fabsf(a.samples[i]-b.samples[i])<1e-5f);
    frame.waveform[0]=NAN;frame.waveform[1]=INFINITY;frame.waveform[2]=4;
    ULPWaveformUpdate(&a,&frame,0,.016f);
    assert(a.samples[0]==0 && a.samples[1]==0 && a.samples[2]==1);
    // A circular waveform retains polarity and wraps both ends continuously.
    ULPWaveformState loop = {0};
    loop.samples[0] = .6f; loop.samples[32] = -.6f; loop.samples[63] = -.4f;
    assert(fabsf(ULPWaveformLoopSample(&loop, 0) - .6f) < 1e-6f);
    assert(ULPWaveformLoopSample(&loop, 1) == ULPWaveformLoopSample(&loop, 0));
    assert(fabsf(ULPWaveformLoopSample(&loop, .5f) + .6f) < 1e-6f);
    assert(fabsf(ULPWaveformLoopSample(&loop, 63.5f/64) - .1f) < 1e-6f);
    assert(fabsf(ULPWaveformLoopSample(&loop, -1e-5f) -
                 ULPWaveformLoopSample(&loop, 1e-5f)) < .002f);
    assert(ULPCircularWaveformRadius(&loop, 0, 1, .38f) > .19f);
    assert(ULPCircularWaveformRadius(&loop, .5f, 1, .38f) < .19f);
    for (int i=0;i<128;i++) {
        float phase = i/128.f;
        assert(fabsf(ULPCircularWaveformRadius(&loop, phase, 0, .38f) - .19f) < 1e-6f);
        float radius = ULPCircularWaveformRadius(&loop, phase, 2, .1f);
        assert(radius >= .01f && radius <= .49f);
    }
    assert(ULPCircularWaveformRadius(&loop, .5f, 2, .1f) == .01f);
    loop.samples[0] = 1;
    assert(ULPCircularWaveformRadius(&loop, 0, 2, .8f) == .49f);
    assert(isfinite(ULPCircularWaveformRadius(&loop, NAN, INFINITY, NAN)));
    loop.samples[0] = NAN;
    assert(ULPWaveformLoopSample(&loop, 0) == 0);
    ULPWaveformUpdate(&loop, &(ULPMSH2FeatureFrame){.featureMask=ULP_MSH2_WAVEFORM}, 0, .016f);
    for(int i=0;i<64;i++)
        assert(fabsf(ULPCircularWaveformRadius(&loop, i/64.f, 1, .38f) - .19f) < 1e-6f);
    frame.featureMask=ULP_MSH2_SPECTRUM;
    ULPWaveformUpdate(&a,&frame,0,.016f);
    for(int i=0;i<64;i++) assert(a.samples[i]==0); // No invented wave without PCM.
    puts("WaveformTests OK");
}
