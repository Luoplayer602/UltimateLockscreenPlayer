const $ = id => document.getElementById(id);
const audio = $('audio'), screen = $('screen'), canvas = $('visualizer');
const sceneRenderer = new ULPRenderer.SceneRenderer(canvas);
const processor = new ULPAudio.AudioFrameProcessor();
const progressSegments = ['progressGlowTop','progressGlowBottom','progressLineTop','progressLineBottom'].map($);
let files=[],currentIndex=0,objectUrl=null,artworkUrl=null;
let audioContext=null,analyser=null,waveAnalyser=null,filters=null;
let frequencyData=null,waveData=null,rawData=null;
let rafId=0,lastAnalysisAt=0,lastPaintAt=0,playStartedAt=0;
let lastAudioFrame=processor.idle(),artworkColors=['#67a8ff','#bb91ff','#68d7df'];
function currentProfile() {
  if(window.demoVisualProfile)return window.demoVisualProfile;
  return Object.fromEntries([...modeSpecs.waveform.fields,...Object.values(shared).flat()].map(f=>[f.id,f.value]));
}
function status(text) { $('status').textContent=text; }
function formatTime(seconds) {const n=Number.isFinite(seconds)?Math.max(0,Math.floor(seconds)):0;return `${Math.floor(n/60)}:${String(n%60).padStart(2,'0')}`;}
function resetAnalysis() {processor.reset();sceneRenderer.clearHistory();lastAudioFrame=processor.idle(audio.currentTime);}
function configureAnalysis(p=currentProfile()) {
  if(!filters)return;
  const [low,high]=ULPAudio.bands[p.visualBand]||ULPAudio.bands.full;
  filters.highpass.frequency.value=low;filters.lowpass.frequency.value=Math.min(high,audioContext.sampleRate*.46);
  for(const band of ['bass','mids','treble'])filters[band].gain.value=20*Math.log10(Math.max(.001,Number(p[band]??1)));
}
function ensureAnalyser() {
  if(audioContext)return;
  const AudioContextClass=window.AudioContext||window.webkitAudioContext;
  if(!AudioContextClass)throw new Error('Trình duyệt không hỗ trợ Web Audio.');
  audioContext=new AudioContextClass();const source=audioContext.createMediaElementSource(audio);
  analyser=audioContext.createAnalyser();analyser.fftSize=4096;analyser.smoothingTimeConstant=0;
  source.connect(analyser);analyser.connect(audioContext.destination);
  waveAnalyser=audioContext.createAnalyser();waveAnalyser.fftSize=2048;waveAnalyser.smoothingTimeConstant=0;
  const filter=(type,freq)=>{const node=audioContext.createBiquadFilter();node.type=type;node.frequency.value=freq;return node;};
  filters={highpass:filter('highpass',25),lowpass:filter('lowpass',14000),bass:filter('lowshelf',250),mids:filter('peaking',1000),treble:filter('highshelf',2500)};
  filters.mids.Q.value=.7;
  source.connect(filters.highpass);filters.highpass.connect(filters.lowpass);filters.lowpass.connect(filters.bass);filters.bass.connect(filters.mids);filters.mids.connect(filters.treble);filters.treble.connect(waveAnalyser);
  const silent=audioContext.createGain();silent.gain.value=0;waveAnalyser.connect(silent);silent.connect(audioContext.destination);
  frequencyData=new Float32Array(analyser.frequencyBinCount);waveData=new Float32Array(waveAnalyser.fftSize);rawData=new Float32Array(analyser.fftSize);
  configureAnalysis();
}
async function togglePlayback() {
  if(!audio.paused) {audio.pause();return;}
  try {ensureAnalyser();await audioContext.resume();await audio.play();}
  catch(error) {status(`Không phát được nhạc: ${error.message}. Hãy chọn tệp ở Nhạc thử.`);}
}
function chooseTrack(index) {
  if(!files.length)return;
  currentIndex=(index+files.length)%files.length;
  const oldURL=objectUrl;objectUrl=URL.createObjectURL(files[currentIndex]);audio.src=objectUrl;audio.load();
  if(oldURL)URL.revokeObjectURL(oldURL);
  $('songTitle').textContent=files[currentIndex].name.replace(/\.[^.]+$/,'').replace(/[_-]+/g,' ');
  $('songArtist').textContent='Nhạc của bạn';resetAnalysis();status(`Đã chọn: ${files[currentIndex].name}`);
}
function coverArtwork(image) {
  const width=image.naturalWidth||image.width,height=image.naturalHeight||image.height;
  const sample=document.createElement('canvas');sample.width=sample.height=96;
  const scan=sample.getContext('2d',{willReadFrequently:true});scan.drawImage(image,0,0,96,96);
  const pixels=scan.getImageData(0,0,96,96).data;
  const hasPicture=(vertical,index)=>{
    let lit=0;
    for(let p=16;p<80;p++){
      const x=vertical?p:index,y=vertical?index:p,k=(y*96+x)*4;
      if(Math.max(pixels[k],pixels[k+1],pixels[k+2])>44)lit++;
    }
    return lit>=8;
  };
  const bounds=vertical=>{
    let start=0,end=95;
    while(start<23&&!hasPicture(vertical,start))start++;
    while(end>72&&!hasPicture(vertical,end))end--;
    return [start,end];
  };
  const [left,right]=bounds(false),[top,bottom]=bounds(true);
  const sx=left/96*width,sy=top/96*height,cropWidth=(right-left+1)/96*width,cropHeight=(bottom-top+1)/96*height;
  const side=Math.min(cropWidth,cropHeight);
  const output=document.createElement('canvas');output.width=output.height=Math.max(1,Math.min(1024,Math.round(side)));
  output.getContext('2d').drawImage(image,sx+(cropWidth-side)/2,sy+(cropHeight-side)/2,side,side,0,0,output.width,output.height);
  return output;
}
function applyArtwork(url) {
  const image=new Image();
  image.onload=()=>{
    const cropped=coverArtwork(image);
    const sample=document.createElement('canvas');sample.width=sample.height=24;const ctx=sample.getContext('2d');ctx.drawImage(cropped,0,0,24,24);
    const pixels=ctx.getImageData(0,0,24,24).data;
    artworkColors=[[5,5],[12,12],[19,19]].map(([x,y])=>{const k=(y*24+x)*4;return `#${[pixels[k],pixels[k+1],pixels[k+2]].map(v=>Math.max(60,v).toString(16).padStart(2,'0')).join('')}`;});
    sceneRenderer.setArtwork(image,artworkColors,cropped);$('thumb').style.backgroundImage=`url("${cropped.toDataURL('image/png')}")`;$('thumb').classList.add('has-image');window.refreshDemo();
  };
  image.onerror=()=>status('Không đọc được artwork. Hãy chọn một ảnh khác.');image.src=url;
}
function updateProgress() {
  const fraction=Number.isFinite(audio.duration)&&audio.duration>0?Math.min(1,audio.currentTime/audio.duration):0;
  for(const path of progressSegments)path.style.strokeDasharray=`${fraction*100} 100`;
  $('timeLabel').textContent=`${formatTime(audio.currentTime)} / ${formatTime(audio.duration)}`;
}
function paint(dt=.016,clock=performance.now()/1000) {
  const p=currentProfile();
  sceneRenderer.render(window.demoVisualMode||'waveform',p,lastAudioFrame,dt,window.demoEnabled!==false&&window.demoVisualEnabled!==false,clock);
  const coverZoom=ULPRenderer.coverMotion(p,lastAudioFrame,clock).scale;
  $('lyricsOverlay').style.setProperty('--cover-motion-scale',String(coverZoom));
  $('player').hidden=window.demoEnabled===false;
  if(window.updateSettingsPreview)window.updateSettingsPreview();
}
window.refreshDemo=()=>{configureAnalysis();paint(0);};
function tick(timestamp=0) {
  rafId=requestAnimationFrame(tick);
  const dt=Math.max(.001,Math.min(.1,(timestamp-lastAnalysisAt)/1000));lastAnalysisAt=timestamp;
  const p=currentProfile();
  if(analyser && !audio.paused && !audio.ended) {
    analyser.getFloatFrequencyData(frequencyData);analyser.getFloatTimeDomainData(rawData);waveAnalyser.getFloatTimeDomainData(waveData);
    lastAudioFrame=processor.process(frequencyData,waveData,audioContext.sampleRate,analyser.fftSize,audio.currentTime,dt,p,rawData);
    if(lastAudioFrame.rms<.00001 && timestamp-playStartedAt>3000 && location.protocol==='file:')status('Chưa nhận được mẫu âm thanh. Khi mở file HTML trực tiếp, hãy chọn bài bằng Nhạc thử; hoặc mở demo qua máy chủ localhost.');
  } else lastAudioFrame=processor.idle(audio.currentTime);
  if(timestamp-lastPaintAt>=1000/Number(p.fps||60)) {paint(Math.min(.1,(timestamp-lastPaintAt)/1000),timestamp/1000);lastPaintAt=timestamp;}
  if(window.demoLyrics)window.demoLyrics.updateTime();
}
$('audioFiles').addEventListener('change',event=>{files=Array.from(event.target.files||[]);if(files.length)chooseTrack(0);});
$('artworkFile').addEventListener('change',event=>{const file=event.target.files?.[0];if(!file)return;const old=artworkUrl;artworkUrl=URL.createObjectURL(file);applyArtwork(artworkUrl);if(old)URL.revokeObjectURL(old);});
$('playButton').addEventListener('click',togglePlayback);
$('prevButton').addEventListener('click',async()=>{if(files.length>1&&audio.currentTime<3)chooseTrack(currentIndex-1);else audio.currentTime=0;resetAnalysis();if(audio.paused)await togglePlayback();});
$('nextButton').addEventListener('click',async()=>{if(files.length>1)chooseTrack(currentIndex+1);else audio.currentTime=0;resetAnalysis();if(audio.paused)await togglePlayback();});
audio.addEventListener('play',()=>{playStartedAt=performance.now();$('playButton').textContent='Ⅱ';$('playButton').setAttribute('aria-label','Tạm dừng');status('Đang phát · phân tích âm thanh trực tiếp.');});
audio.addEventListener('pause',()=>{$('playButton').textContent='▶';$('playButton').setAttribute('aria-label','Phát');resetAnalysis();paint();});
audio.addEventListener('seeking',resetAnalysis);
audio.addEventListener('timeupdate',updateProgress);
audio.addEventListener('loadedmetadata',()=>{resetAnalysis();updateProgress();});
audio.addEventListener('ended',async()=>{if(files.length>1)chooseTrack(currentIndex+1);else audio.currentTime=0;resetAnalysis();await togglePlayback();});
audio.addEventListener('error',()=>status('Không mở được bài mẫu. Hãy chọn tệp bằng Nhạc thử.'));
window.addEventListener('beforeunload',()=>{cancelAnimationFrame(rafId);if(objectUrl)URL.revokeObjectURL(objectUrl);if(artworkUrl)URL.revokeObjectURL(artworkUrl);});
paint();tick();
