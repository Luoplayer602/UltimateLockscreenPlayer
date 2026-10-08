const assert=require('node:assert/strict');
const {BeatDetector,AudioFrameProcessor}=require('../audio-response.js');
const sr=44100,n=2048,hop=735;
// Independent radix-2 FFT of PCM mixtures, so tests exercise real spectral changes.
function fftDb(pcm) {
  const re=Float64Array.from(pcm,(x,i)=>x*(.5-.5*Math.cos(2*Math.PI*i/(n-1))));
  const im=new Float64Array(n);
  for(let i=1,j=0;i<n;i++){let bit=n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j)[re[i],re[j]]=[re[j],re[i]];}
  for(let len=2;len<=n;len*=2)for(let a=0;a<n;a+=len)for(let k=0;k<len/2;k++){
    const angle=-2*Math.PI*k/len,c=Math.cos(angle),s=Math.sin(angle),b=a+k+len/2;
    const tr=re[b]*c-im[b]*s,ti=re[b]*s+im[b]*c;re[b]=re[a+k]-tr;im[b]=im[a+k]-ti;re[a+k]+=tr;im[a+k]+=ti;
  }
  return Float32Array.from({length:n/2},(_,i)=>20*Math.log10(Math.max(1e-8,Math.hypot(re[i],im[i])/n)));
}
function run(signal,seconds=8) {
  const detector=new BeatDetector(),events=[];
  for(let start=0;start<seconds*sr-n;start+=hop){
    const pcm=Float32Array.from({length:n},(_,i)=>signal((start+i)/sr));
    const rms=Math.sqrt(pcm.reduce((sum,x)=>sum+x*x,0)/n),time=(start+n)/sr;
    const frame=detector.process(fftDb(pcm),sr,n,rms,time,hop/sr);
    if(frame.beat)events.push(time);
  }
  return events;
}
const silence=run(()=>0,2);assert.equal(silence.length,0,'silence');
const steady=run(t=>.25*Math.sin(2*Math.PI*220*t),3);assert.equal(steady.length,0,'steady tone must not generate repeated beats');
const expected=Array.from({length:13},(_,i)=>1+i*.5);
function mix(t,layered) {
  let value=layered ? .22*Math.sin(2*Math.PI*220*t)+.15*Math.sin(2*Math.PI*330*t)+.09*Math.sin(2*Math.PI*660*t):0;
  for(const hit of expected){const age=t-hit;if(age>=0&&age<.25)value+=.4*Math.exp(-age*25)*Math.sin(2*Math.PI*(72*age+8*(1-Math.exp(-age*35))));}
  return value;
}
for(const layered of [false,true]) {
  const events=run(t=>mix(t,layered));
  const hits=expected.filter(t=>events.some(e=>e>=t-.03&&e<t+.13)).length;
  const falsePositives=events.filter(e=>!expected.some(t=>e>=t-.03&&e<t+.13)).length;
  assert.ok(hits>=11,`beat recall ${hits}/13, layered=${layered}: ${events}`);
  assert.ok(falsePositives<=2,`too many false beats ${falsePositives}`);
  console.log(`PCM mixture layered=${layered}: ${hits}/13 hits, ${falsePositives} extra events`);
}
const processor=new AudioFrameProcessor(),pcm=Float32Array.from({length:n},(_,i)=>.3*Math.sin(2*Math.PI*3*i/n));
const a=processor.process(fftDb(pcm),pcm,sr,n,1,1/60,{smoothing:0,waveformSmoothing:0});
assert.ok(a.wave.some(x=>x>.05)&&a.wave.some(x=>x<-.05),'waveform must retain PCM polarity');
processor.reset();const zero=processor.process(new Float32Array(n/2).fill(-Infinity),new Float32Array(n),sr,n,2,1/60,{});
assert.ok(zero.wave.every(x=>x===0),'silent PCM must draw a flat line');
console.log('Silence, steady tone, layered onsets, signed PCM: PASS');
