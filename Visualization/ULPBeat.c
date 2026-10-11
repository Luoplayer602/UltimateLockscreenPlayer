#include "ULPBeat.h"
#include <math.h>
#include <stddef.h>

static double bound(double x, double lo, double hi) {
    return isfinite(x) ? fmin(hi, fmax(lo, x)) : lo;
}
static ULPBeatResult result(const ULPBeatState *s, bool hit, bool reset) {
    return (ULPBeatResult){hit, reset, s->pulse, s->strength, s->score, s->count};
}
void ULPBeatReset(ULPBeatState *s) { if (s) *s = (ULPBeatState){0}; }
void ULPBeatDecay(ULPBeatState *s, double time, float release) {
    if (!s || !s->initialized || !isfinite(time) || time <= s->pulseAt) return;
    s->pulse *= exp(-(time - s->pulseAt) / bound(release, .08, .6));
    if (s->pulse < .0001f) s->pulse = 0;
    s->pulseAt = time;
}
ULPBeatResult ULPBeatProcess(ULPBeatState *s, const ULPMSH2FeatureFrame *f,
                            double time, ULPVisualConfig c) {
    if (!s) return (ULPBeatResult){0};
    if (!f || !isfinite(time)) return result(s, false, false);
    bool reset = s->initialized && (time < s->lastFrameAt || time - s->lastFrameAt > .5 ||
        f->streamEpoch != s->streamEpoch || f->sampleRate != s->sampleRate);
    if (reset) ULPBeatReset(s);
    ULPBeatDecay(s, time, c.beatRelease);
    if (!(f->featureMask & ULP_MSH2_SPECTRUM) || !isfinite(f->sampleRate) || f->sampleRate < 1000)
        return result(s, false, reset);
    if (s->initialized && time <= s->lastFrameAt) return result(s, false, reset);
    bool first = !s->initialized;
    double dt = first ? 1.0 / 60 : bound(time - s->lastFrameAt, .001, .1);
    if (first) {
        s->startedAt = time; s->lastBeatAt = -INFINITY;
        s->sampleRate = f->sampleRate; s->streamEpoch = f->streamEpoch;
        s->initialized = true; s->pulseAt = time;
    }
    float novelty[4] = {0}; unsigned counts[4] = {0};
    double floorAlpha = -expm1(-dt / .65), historyAlpha = -expm1(-dt / 1.4);
    for (unsigned i = 0; i < 64; ++i) {
        double hz = 45 * pow(1.1, i);
        if (hz > 12000 || hz > f->sampleRate * .47) break;
        unsigned lane = hz <= 180 ? 0 : hz <= 650 ? 1 : hz <= 2800 ? 2 : 3;
        // DSP64 is already gain-scaled/clamped; do not pretend it is FFT dB.
        float mag = log1pf(4 * bound(f->spectrum[i], 0, 1));
        if (first) s->floor[i] = s->previous[i] = mag;
        novelty[lane] += fmaxf(0, mag - s->previous[i]) / fmaxf(.16f, s->floor[i]);
        ++counts[lane];
        s->floor[i] += (mag - s->floor[i]) * floorAlpha;
        s->previous[i] = mag;
    }
    float score = 0; unsigned active = 0;
    const float weight[] = {1, .95f, .86f, .72f};
    for (unsigned lane = 0; lane < 4; ++lane) {
        float n = novelty[lane] / (counts[lane] ? counts[lane] : 1);
        double threshold = fmax(.045, s->mean[lane] + 1.25 * sqrt(fmax(0, s->variance[lane]))) /
                           bound(c.beatSensitivity, .5, 2);
        double ratio = n / threshold;
        if (ratio > 1) ++active;
        score = fmaxf(score, ratio * weight[lane]);
        double delta = n - s->mean[lane];
        s->mean[lane] += historyAlpha * delta;
        s->variance[lane] = (1 - historyAlpha) * (s->variance[lane] + historyAlpha * delta * delta);
    }
    bool hit = !first && time - s->startedAt > .12 && isfinite(f->rms) && f->rms > .004f &&
        score > 1 && (active > 1 || score > 1.5) &&
        time - s->lastBeatAt + 1e-6 >= bound(c.beatInterval, .12, .5);
    if (hit) {
        s->lastBeatAt = time; s->pulse = s->strength = bound(score / 2.5, .45, 1);
        ++s->count;
    }
    s->score = score; s->lastFrameAt = time;
    return result(s, hit, reset);
}

ULPBeatMotion ULPBeatMotionIdentity(void) { return (ULPBeatMotion){.scale=1}; }
static double duration(ULPBeatMotionType type) {
    return type == ULPBeatMotionBounce ? .8 : type == ULPBeatMotionWobble ? .7 :
           type == ULPBeatMotionSwell ? .32 : type == ULPBeatMotionSpin ? .48 : .6;
}
static double smooth(double x) { x = bound(x, 0, 1); return x * x * (3 - 2 * x); }
static double envelope(double age, double attack, double end) {
    return age < attack ? smooth(age / attack) : 1 - smooth((age - attack) / (end - attack));
}
bool ULPBeatMotionActive(const ULPBeatMotionState *s, double time) {
    return s && s->active && isfinite(time) && time >= s->startedAt &&
           time - s->startedAt < duration(s->type);
}
ULPBeatMotion ULPBeatMotionEvaluate(const ULPBeatMotionState *s, double time) {
    ULPBeatMotion m = ULPBeatMotionIdentity();
    if (!ULPBeatMotionActive(s, time)) return m;
    double age = time - s->startedAt, a = bound(s->strength, 0, 1);
    double quick = exp(-age * 10) * (1 - smooth(age / .6));
    double slow = exp(-age * 5) * (1 - smooth(age / .7));
    switch (s->type) {
        case ULPBeatMotionSwell: m.scale += a * .6 * envelope(age, .045, .32); break;
        case ULPBeatMotionFlash: m.flash = a * envelope(age, .018, .6); break;
        case ULPBeatMotionShake:
            m.x = a * 13 * quick * sin(age * 95); m.y = a * 8 * quick * sin(age * 79); break;
        case ULPBeatMotionSpin:
            m.scale += a * .45 * envelope(age, .035, .4);
            m.rotation = a * .65 * envelope(age, .06, .48); break;
        case ULPBeatMotionBounce: m.scale += a * .48 * envelope(age, .19, .8); break;
        case ULPBeatMotionWobble:
            m.x = a * 5 * slow * sin(age * 48); m.y = a * 3 * slow * sin(age * 41);
            m.rotation = a * .18 * slow * sin(age * 28); break;
    }
    // On a new hit start exactly at the current pose, then release that pose.
    // This prevents discontinuities when a second kick interrupts Bounce.
    double carry = 1 - smooth(age / .12);
    m.scale += (s->from.scale - 1) * carry; m.x += s->from.x * carry;
    m.y += s->from.y * carry; m.rotation += s->from.rotation * carry;
    m.flash = bound(m.flash + s->from.flash * carry, 0, 1);
    m.scale = bound(m.scale, 1, 2.2);
    m.x = bound(m.x, -26, 26); m.y = bound(m.y, -16, 16);
    m.rotation = bound(m.rotation, -.4, 1.3);
    return m;
}
void ULPBeatMotionTrigger(ULPBeatMotionState *s, ULPBeatMotionType type, float strength, double time) {
    if (!s || !isfinite(time) || type < ULPBeatMotionSwell || type > ULPBeatMotionWobble) return;
    ULPBeatMotion from = ULPBeatMotionEvaluate(s, time);
    *s = (ULPBeatMotionState){from, time, bound(strength, 0, 1), type, true};
}
