/* Causal audio analysis. No track pre-analysis and no synthetic wave animation. */
(function (root) {
  'use strict';
  const clamp = (x, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, x));
  const bands = {drum:[40,180],bass:[25,250],mid:[250,2500],high:[2500,14000],full:[25,14000]};
  const mean = values => values.reduce((a,b) => a+b,0) / Math.max(1,values.length);
  class BeatDetector {
    constructor() { this.reset(); }
    reset() {
      this.previous = null; this.floor = null; this.history = [[],[],[],[]];
      this.lastBeatAt = -Infinity; this.pulse = 0; this.count = 0; this.startedAt = null;
    }
    process(db, sampleRate, fftSize, rms, time, dt, options = {}) {
      const hz = sampleRate / fftSize;
      if (!this.previous || this.previous.length !== db.length) {
        this.previous = new Float32Array(db.length); this.floor = new Float32Array(db.length);
      }
      const limits = [35,180,650,2800,12000];
      const novelty = [0,0,0,0], counts = [0,0,0,0];
      let lane = 0;
      for (let i = Math.max(1,Math.floor(limits[0]/hz)); i < db.length && i*hz <= limits[4]; i++) {
        while (lane < 3 && i*hz > limits[lane+1]) lane++;
        const magnitude = Math.log1p(Math.pow(10, Math.max(-120,db[i])/20) * 100);
        // Whitening exposes attacks hidden beneath sustained instruments.
        const rise = Math.max(0,magnitude - this.previous[i]);
        novelty[lane] += rise / Math.max(.16,this.floor[i]);
        counts[lane]++;
        this.floor[i] += (magnitude-this.floor[i]) * (1-Math.exp(-dt/.65));
        this.previous[i] = magnitude;
      }
      let score = 0, activeBands = 0;
      for (let i=0;i<4;i++) {
        novelty[i] /= Math.max(1,counts[i]);
        const history = this.history[i];
        const average = mean(history);
        const deviation = Math.sqrt(mean(history.map(x=>(x-average)**2)));
        const threshold = Math.max(.045,average + deviation * 1.25) / Number(options.beatSensitivity || 1);
        const bandScore = novelty[i] / threshold;
        if (bandScore > 1) activeBands++;
        score = Math.max(score,bandScore * [1,.95,.86,.72][i]);
        history.push(novelty[i]);
        if (history.length > Math.round(1.4/dt)) history.shift();
      }
      if (this.startedAt === null) this.startedAt = time;
      const beat = time-this.startedAt > .12 && rms > .004 && score > 1 &&
        (activeBands > 1 || score > 1.5) && time-this.lastBeatAt >= Number(options.beatInterval ?? .2);
      if (beat) { this.lastBeatAt = time; this.pulse = clamp(score/2.5,.45,1); this.count++; }
      else this.pulse *= Math.exp(-dt / Number(options.beatRelease ?? .2));
      return {beat,beatPulse:this.pulse,lastBeatAt:this.lastBeatAt,beatCount:this.count,novelty:score};
    }
  }
  class AudioFrameProcessor {
    constructor() { this.detector = new BeatDetector(); this.reset(); }
    reset() {
      this.spectrum = new Float32Array(128); this.wave = new Float32Array(128);
      this.peak = .12; this.raw = 0; this.detector.reset();
    }
    process(db, pcm, sampleRate, fftSize, time, dt, p = {}, rawPCM = pcm) {
      dt = clamp(dt,.001,.1);
      let energy = 0, peak = 0;
      for (const sample of rawPCM) energy += sample*sample;
      for (const sample of pcm) peak=Math.max(peak,Math.abs(sample));
      const rms = Math.sqrt(energy / Math.max(1,rawPCM.length));
      const beat = this.detector.process(db,sampleRate,fftSize,rms,time,dt,p);
      this.peak += (peak-this.peak)*(1-Math.exp(-dt/(peak>this.peak ? .045 : 1.4)));
      const gain = Number(p.sensitivity ?? 1) * (p.normalise ? clamp(.45/Math.max(.08,this.peak),.6,4) : 1);
      const hzPerBin=sampleRate/fftSize;
      const [low, bandHigh] = bands[p.visualBand] || bands.full;
      const high=Math.min(sampleRate*.48,low*Math.pow(bandHigh/low,Math.max(.015,Number(p.frequencyRange ?? 1))));
      const alpha = 1-Math.exp(-dt/(.012+Number(p.smoothing ?? .65)*.3));
      for (let j=0;j<128;j++) {
        const a=low*Math.pow(high/low,j/128), b=low*Math.pow(high/low,(j+1)/128);
        let sum=0,n=0,max=0;
        for(let k=Math.max(1,Math.floor(a/hzPerBin));k<=Math.min(db.length-1,Math.ceil(b/hzPerBin));k++) {
          const f=k*hzPerBin, eq=Number(f<250 ? p.bass ?? 1 : f<2500 ? p.mids ?? 1 : p.treble ?? 1);
          const value=Math.pow(10,Math.max(-120,db[k])/20)*eq;
          sum+=value*value; max=Math.max(max,value); n++;
        }
        const amplitude=(Math.sqrt(sum/Math.max(1,n))*.65+max*.35)*gain;
        const target=rms<.0003 ? 0 : clamp(Math.pow(amplitude*2.2,.62));
        this.spectrum[j]+=(target-this.spectrum[j])*alpha;
      }
      // Average PCM windows, preserving sign; align to a nearby rising zero crossing.
      let start=0;
      for(let i=1;i<Math.min(256,pcm.length/4);i++) if(pcm[i-1]<=0 && pcm[i]>0) { start=i; break; }
      const usable=pcm.length-Math.min(256,pcm.length/4);
      const waveAlpha=1-Math.exp(-dt/(.008+Number(p.waveformSmoothing ?? .5)*.13));
      for(let j=0;j<128;j++) {
        const a=start+Math.floor(j*usable/128),b=start+Math.floor((j+1)*usable/128);
        let sum=0;
        for(let k=a;k<b;k++) sum+=pcm[k] || 0;
        const target=clamp(sum/Math.max(1,b-a)*gain,-1,1);
        this.wave[j]+=(target-this.wave[j])*waveAlpha;
      }
      const [zLow,zHigh]=bands[p.zoomBand] || bands.bass;
      let zSum=0,zCount=0;
      for(let i=Math.max(1,Math.floor(zLow/hzPerBin));i<=Math.min(db.length-1,Math.ceil(zHigh/hzPerBin));i++) {
        zSum+=Math.pow(10,Math.max(-120,db[i])/10); zCount++;
      }
      const targetRaw=rms<.0003?0:clamp(Math.sqrt(zSum/Math.max(1,zCount))*gain*5);
      this.raw+=(targetRaw-this.raw)*(1-Math.exp(-dt/(targetRaw>this.raw?.04:.16)));
      return {spectrum:this.spectrum,wave:this.wave,rms,raw:this.raw,...beat,time,playing:true};
    }
    idle(time=0) {
      return {spectrum:new Float32Array(128),wave:new Float32Array(128),rms:0,raw:0,
        beat:false,beatPulse:0,lastBeatAt:-Infinity,beatCount:this.detector.count,novelty:0,time,playing:false};
    }
  }
  root.ULPAudio = {BeatDetector,AudioFrameProcessor,bands,clamp};
  if(typeof module !== 'undefined') module.exports=root.ULPAudio;
})(typeof window !== 'undefined'?window:globalThis);
