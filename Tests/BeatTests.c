#include "../Visualization/ULPBeat.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static ULPMSH2FeatureFrame music(float bass, float mids) {
    ULPMSH2FeatureFrame f = {.featureMask=ULP_MSH2_SPECTRUM, .sampleRate=44100, .rms=.12, .streamEpoch=1};
    for (int i=0; i<64; ++i) f.spectrum[i] = i < 15 ? bass : mids;
    return f;
}
static void prime(ULPBeatState *s, ULPMSH2FeatureFrame f, ULPVisualConfig c) {
    for (int i=0; i<60; ++i) assert(!ULPBeatProcess(s,&f,i/60.0,c).hit);
}
static bool same(ULPBeatMotion a, ULPBeatMotion b) {
    return fabs(a.scale-b.scale)+fabs(a.x-b.x)+fabs(a.y-b.y)+
           fabs(a.rotation-b.rotation)+fabs(a.flash-b.flash) < 1e-8;
}
int main(void) {
    ULPVisualConfig c = ULPVisualConfigDefault();
    ULPBeatState s = {0};
    ULPMSH2FeatureFrame backing = music(.18,.45), kick = music(.8,.45);
    prime(&s,backing,c);
    ULPBeatResult hit = ULPBeatProcess(&s,&kick,1,c);
    assert(hit.hit && hit.count==1 && hit.strength > .45);
    // Sustained loud layers do not hide the bass rise and do not keep firing.
    for (int i=1; i<=30; ++i) assert(!ULPBeatProcess(&s,&kick,1+i/60.0,c).hit);
    for (int i=31; i<60; ++i) ULPBeatProcess(&s,&backing,1+i/60.0,c);
    assert(ULPBeatProcess(&s,&kick,2,c).hit && s.count==2);
    ULPBeatProcess(&s,&backing,2.01,c);
    assert(!ULPBeatProcess(&s,&kick,2.04,c).hit); // Refractory interval.
    ULPBeatDecay(&s,3,.2);
    assert(s.pulse < .01);
    ULPMSH2FeatureFrame silence = music(1,1); silence.rms=0;
    assert(!ULPBeatProcess(&s,&silence,3.01,c).hit);
    ULPMSH2FeatureFrame newStream = kick; newStream.streamEpoch=2;
    hit=ULPBeatProcess(&s,&newStream,3.02,c);
    assert(hit.reset && !hit.hit && hit.count==0 && hit.pulse==0);
    hit=ULPBeatProcess(&s,&kick,9,c);
    assert(hit.reset && !hit.hit); // Gap/reconnect primes, never synthetic beat.
    hit=ULPBeatProcess(&s,&kick,8,c);
    assert(hit.reset && !hit.hit); // Reversed clock.
    kick.sampleRate=NAN; kick.rms=NAN; kick.spectrum[0]=INFINITY;
    assert(!ULPBeatProcess(&s,&kick,8.1,c).hit);
    assert(isfinite(s.pulse));
    ULPBeatState quiet={0}; silence=music(0,0); silence.rms=0;
    prime(&quiet,silence,c); assert(quiet.count==0);
    // Sensitivity must have an observable effect on weaker attacks.
    ULPBeatState low={0}, high={0};
    ULPVisualConfig lc=c,hc=c; lc.beatSensitivity=.5; hc.beatSensitivity=2;
    prime(&low,backing,lc); prime(&high,backing,hc);
    ULPMSH2FeatureFrame small=music(.192,.45);
    assert(!ULPBeatProcess(&low,&small,1,lc).hit);
    assert(ULPBeatProcess(&high,&small,1,hc).hit);
    // Drawing at 15 FPS must not filter out incoming 60 Hz onsets.
    ULPBeatState a={0},b={0}; ULPVisualConfig slow=c; slow.framesPerSecond=15;
    for(int i=0;i<180;++i) {
        ULPMSH2FeatureFrame f=music(i>=30 && i%30<2 ? .8 : .18,.45);
        ULPBeatResult r1=ULPBeatProcess(&a,&f,i/60.0,c),r2=ULPBeatProcess(&b,&f,i/60.0,slow);
        assert(r1.hit==r2.hit && r1.count==r2.count && r1.pulse==r2.pulse);
    }
    assert(a.count>=4);
    ULPBeatMotion identity=ULPBeatMotionIdentity();
    for(int type=0;type<=5;++type) {
        ULPBeatMotionState m={0};
        assert(same(ULPBeatMotionEvaluate(&m,1),identity));
        ULPBeatMotionTrigger(&m,type,1,1);
        assert(same(ULPBeatMotionEvaluate(&m,1),identity));
        ULPBeatMotion live=ULPBeatMotionEvaluate(&m,1.055);
        assert(!same(live,identity));
        assert(same(ULPBeatMotionEvaluate(&m,3),identity));
        assert(!ULPBeatMotionActive(&m,3));
        if(type==ULPBeatMotionFlash) assert(live.flash>0 && live.scale==1 && live.rotation==0);
        if(type==ULPBeatMotionSpin) assert(live.scale>1 && live.rotation>0);
        // A new hit starts at the old pose without a jump.
        ULPBeatMotion before=ULPBeatMotionEvaluate(&m,1.15);
        ULPBeatMotionTrigger(&m,type,.7,1.15);
        assert(same(before,ULPBeatMotionEvaluate(&m,1.15)));
        for(int i=0;i<90;++i) {
            ULPBeatMotion x=ULPBeatMotionEvaluate(&m,1.15+i/60.0);
            assert(isfinite(x.scale+x.x+x.y+x.rotation+x.flash));
            assert(x.scale>=1 && x.scale<=2.2 && x.flash>=0 && x.flash<=1);
        }
        ULPBeatMotionTrigger(&m,type,NAN,4);
        assert(same(ULPBeatMotionEvaluate(&m,4.1),identity));
    }
    ULPBeatMotionState swell={0},bounce={0};
    ULPBeatMotionTrigger(&swell,ULPBeatMotionSwell,1,0);
    ULPBeatMotionTrigger(&bounce,ULPBeatMotionBounce,1,0);
    assert(ULPBeatMotionEvaluate(&swell,.05).scale>ULPBeatMotionEvaluate(&bounce,.05).scale);
    assert(!ULPBeatMotionActive(&swell,.4) && ULPBeatMotionActive(&bounce,.4));
    puts("BeatTests OK: layered onsets, silence, interval, sensitivity, resets, FPS, six finite continuous motions");
}
