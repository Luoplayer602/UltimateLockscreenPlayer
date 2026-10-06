const $ = (id) => document.getElementById(id);
const audio = $('audio');
const screen = $('screen');
const player = $('player');
const canvas = $('visualizer');
const context2d = canvas.getContext('2d');
const progressSegments = ['progressGlowTop', 'progressGlowBottom', 'progressLineTop', 'progressLineBottom'].map($);
const defaultSource = 'audio/inst.wav';
const frequencyBands = {
  drum: [40, 160], bass: [20, 250], mid: [250, 2000],
  high: [2000, 8000], full: [20, 8000]
};

let files = [];
let currentIndex = 0;
let objectUrl = null;
let artworkUrl = null;
let audioContext = null;
let analyser = null;
let frequencyData = null;
let rafId = 0;
let lastFrameAt = 0;
let settingsTimer = 0;
let artworkColors = ['#ffe6be', '#e7bbef', '#92d7ef'];

function readSettings() {
  return {
    backgroundMode: $('backgroundMode').value,
    visualMode: $('visualMode').value,
    points: Number($('points').value),
    animationScale: Number($('animationScale').value) / 100,
    frequencyBand: $('frequencyBand').value,
    zoomBand: $('zoomBand').value,
    symmetry: $('symmetry').value,
    autoColor: $('autoColor').checked,
    colors: ['color1', 'color2', 'color3'].map((id) => $(id).value),
    offsetX: Number($('offsetX').value),
    offsetY: Number($('offsetY').value),
    fps: Number($('fps').value),
    blurAmount: Number($('blurAmount').value),
    staticDim: Number($('staticDim').value) / 100,
    morphSpeed: Number($('morphSpeed').value),
    showThumbnail: $('showThumbnail').checked,
    beatZoom: $('beatZoom').checked
  };
}
let settings = readSettings();

function applySettings() {
  settings = readSettings();
  screen.classList.toggle('radian', settings.backgroundMode === 'radian');
  screen.classList.toggle('static', settings.backgroundMode === 'static');
  screen.style.setProperty('--radian-blur', `${settings.blurAmount}px`);
  screen.style.setProperty('--static-dim', settings.staticDim.toFixed(2));
  screen.style.setProperty('--morph-duration', `${settings.morphSpeed}s`);
  player.classList.toggle('no-thumb', !settings.showThumbnail);
  $('visualizerWrap').style.setProperty('--offset-x', `${settings.offsetX}px`);
  $('visualizerWrap').style.setProperty('--offset-y', `${settings.offsetY}px`);
  for (const id of ['color1', 'color2', 'color3']) $(id).disabled = settings.autoColor;
}
function scheduleSettings() {
  clearTimeout(settingsTimer);
  settingsTimer = setTimeout(applySettings, 1000);
}
function colorAt(position) {
  const palette = settings.autoColor ? artworkColors : settings.colors;
  const t = Math.max(0, Math.min(1, position)) * 2;
  const segment = Math.min(1, Math.floor(t));
  const a = palette[segment];
  const b = palette[segment + 1];
  const mix = t - segment;
  const channels = [1, 3, 5].map((index) => {
    const start = parseInt(a.slice(index, index + 2), 16);
    const end = parseInt(b.slice(index, index + 2), 16);
    return Math.round(start + (end - start) * mix).toString(16).padStart(2, '0');
  });
  return `#${channels.join('')}`;
}

function status(message) { $('status').textContent = message; }
function formatTime(seconds) {
  if (!Number.isFinite(seconds)) return '0:00';
  const value = Math.max(0, Math.floor(seconds));
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
}
function cleanTitle(filename) {
  return filename.replace(/\.[^.]+$/, '').replace(/[_-]+/g, ' ').trim() || 'Bản nhạc của bạn';
}
function applyArtwork(url) {
  for (const id of ['backgroundA', 'thumb']) {
    $(id).style.backgroundImage = url ? `url("${url}")` : '';
  }
  screen.classList.toggle('has-artwork', Boolean(url));
  $('thumb').classList.toggle('has-image', Boolean(url));
  if (url) {
    const image = new Image();
    image.onload = () => {
      const sample = document.createElement('canvas');
      sample.width = sample.height = 24;
      const context = sample.getContext('2d');
      context.drawImage(image, 0, 0, 24, 24);
      const pixels = context.getImageData(0, 0, 24, 24).data;
      const locations = [[5, 5], [12, 12], [19, 19]];
      artworkColors = locations.map(([x, y]) => {
        const index = (y * 24 + x) * 4;
        return `#${[pixels[index], pixels[index + 1], pixels[index + 2]].map((value) => Math.max(65, value).toString(16).padStart(2, '0')).join('')}`;
      });
    };
    image.src = url;
  }
}
function chooseTrack(index) {
  if (!files.length) return;
  currentIndex = (index + files.length) % files.length;
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  objectUrl = URL.createObjectURL(files[currentIndex]);
  audio.src = objectUrl;
  $('songTitle').textContent = cleanTitle(files[currentIndex].name);
  $('songArtist').textContent = 'Nhạc của bạn';
  audio.load();
  status(`Đã chọn: ${files[currentIndex].name}`);
}
function ensureAnalyser() {
  if (audioContext) return;
  const AudioContextClass = window.AudioContext || window.webkitAudioContext;
  if (!AudioContextClass) { status('Trình duyệt này không hỗ trợ Web Audio API.'); return; }
  audioContext = new AudioContextClass();
  const source = audioContext.createMediaElementSource(audio);
  analyser = audioContext.createAnalyser();
  analyser.fftSize = 2048;
  analyser.smoothingTimeConstant = .76;
  frequencyData = new Uint8Array(analyser.frequencyBinCount);
  source.connect(analyser);
  analyser.connect(audioContext.destination);
}
async function togglePlayback() {
  if (!audio.paused) { audio.pause(); return; }
  ensureAnalyser();
  if (audioContext && audioContext.state === 'suspended') await audioContext.resume();
  try { await audio.play(); }
  catch { status(`Không mở được nhạc. Hãy chọn tệp hoặc đặt ${defaultSource}.`); }
}
function updateProgress() {
  const fraction = Number.isFinite(audio.duration) && audio.duration > 0 ? Math.min(1, audio.currentTime / audio.duration) : 0;
  const dash = `${(fraction * 100).toFixed(2)} 100`;
  for (const segment of progressSegments) segment.style.strokeDasharray = dash;
  $('timeLabel').textContent = `${formatTime(audio.currentTime)} / ${formatTime(audio.duration)}`;
}
function resizeCanvas() {
  const rect = canvas.getBoundingClientRect();
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.max(1, Math.round(rect.width * ratio));
  canvas.height = Math.max(1, Math.round(rect.height * ratio));
  context2d.setTransform(ratio, 0, 0, ratio, 0, 0);
}
function selectedBinRange(band) {
  const [lowHz, highHz] = frequencyBands[band];
  const hzPerBin = audioContext.sampleRate / analyser.fftSize;
  const first = Math.max(1, Math.floor(lowHz / hzPerBin));
  const last = Math.max(first, Math.min(frequencyData.length - 1, Math.ceil(highHz / hzPerBin)));
  return [first, last];
}
function sampleAt(index, count, first, last, circular = false) {
  const symmetry = settings.symmetry;
  let position = index;
  if (circular) {
    const mirrorVertical = (count - index) % count;
    const mirrorHorizontal = ((count / 2 - index) % count + count) % count;
    if (symmetry === 'vertical' || symmetry === 'both') position = Math.min(position, mirrorVertical);
    if (symmetry === 'horizontal' || symmetry === 'both') position = Math.min(position, mirrorHorizontal);
    if (symmetry === 'both') position = Math.min(position, ((count / 2 + index) % count));
  } else if (symmetry === 'vertical' || symmetry === 'both') {
    position = Math.min(position, count - 1 - position);
  }
  const bin = first + Math.round((last - first) * position / Math.max(1, count - 1));
  return frequencyData[Math.min(last, bin)] / 255;
}
function draw(timestamp = 0) {
  rafId = requestAnimationFrame(draw);
  if (timestamp - lastFrameAt < 1000 / settings.fps) return;
  lastFrameAt = timestamp;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  context2d.clearRect(0, 0, width, height);
  if (!analyser || audio.paused || audio.ended) {
    $('visualizerWrap').style.setProperty('--beat-scale', '1');
    $('artworkZoom').style.setProperty('--background-beat-scale', '1');
    return;
  }
  analyser.getByteFrequencyData(frequencyData);
  const [first, last] = selectedBinRange(settings.frequencyBand);
  const [zoomFirst, zoomLast] = selectedBinRange(settings.zoomBand);
  let energy = 0;
  for (let i = zoomFirst; i <= zoomLast; i++) energy += frequencyData[i];
  energy /= zoomLast - zoomFirst + 1;
  const beatScale = settings.beatZoom ? 1 + energy / 255 * settings.animationScale : 1;
  $('visualizerWrap').style.setProperty('--beat-scale', beatScale.toFixed(3));
  $('artworkZoom').style.setProperty('--background-beat-scale', screen.classList.contains('has-artwork') ? beatScale.toFixed(3) : '1');

  const mode = settings.visualMode;
  const count = settings.points;
  const symmetry = settings.symmetry;
  const cx = width / 2, cy = height / 2;
  context2d.strokeStyle = colorAt(0);
  context2d.fillStyle = colorAt(0);
  context2d.lineWidth = 2.3;
  context2d.shadowColor = colorAt(.5);
  context2d.shadowBlur = 12;
  if (mode === 'bar') {
    const barWidth = width * .76 / count;
    for (let i = 0; i < count; i++) {
      const amplitude = sampleAt(i, count, first, last);
      const barHeight = Math.max(3, amplitude * height * .43);
      const x = width * .12 + i * barWidth;
      context2d.fillStyle = colorAt(i / (count - 1));
      if (symmetry === 'horizontal' || symmetry === 'both') {
        context2d.fillRect(x, cy - barHeight / 2, barWidth * .55, barHeight);
      } else {
        context2d.fillRect(x, cy + height * .2 - barHeight, barWidth * .55, barHeight);
      }
    }
  } else if (mode === 'wave' || mode === 'siri') {
    const gradient = context2d.createLinearGradient(0, 0, width, 0);
    gradient.addColorStop(0, colorAt(0));
    gradient.addColorStop(.5, colorAt(.5));
    gradient.addColorStop(1, colorAt(1));
    context2d.strokeStyle = gradient;
    if (mode === 'siri') context2d.lineWidth = 3.5;
    const layers = mode === 'siri' ? 3 : 1;
    for (let layer = 0; layer < layers; layer++) {
    context2d.beginPath();
    const wavePoints = [];
    for (let i = 0; i < count; i++) {
      const x = width * .08 + i / (count - 1) * width * .84;
      const phase = mode === 'siri' ? i * .19 + audio.currentTime * (5 + layer) + layer * 1.4 : i * .65 + audio.currentTime * 9;
      const y = cy + Math.sin(phase) * sampleAt(i, count, first, last) * (mode === 'siri' ? 42 + layer * 8 : 66);
      wavePoints.push([x, y]);
      if (i === 0) context2d.moveTo(x, y); else context2d.lineTo(x, y);
    }
    context2d.stroke();
    if (symmetry === 'horizontal' || symmetry === 'both') {
      context2d.beginPath();
      for (let i = 0; i < wavePoints.length; i++) {
        const [x, y] = wavePoints[i];
        if (i === 0) context2d.moveTo(x, 2 * cy - y); else context2d.lineTo(x, 2 * cy - y);
      }
      context2d.stroke();
    }
    }
  } else {
    const radius = Math.min(width, height) * .29;
    const linePoints = [];
    for (let i = 0; i < count; i++) {
      const amplitude = sampleAt(i, count, first, last, true);
      const angle = i / count * Math.PI * 2 - Math.PI / 2;
      const outer = radius + 7 + amplitude * 42;
      const x = cx + Math.cos(angle) * outer;
      const y = cy + Math.sin(angle) * outer;
      context2d.strokeStyle = colorAt(i / (count - 1));
      context2d.fillStyle = context2d.strokeStyle;
      if (mode === 'dot') {
        context2d.beginPath();
        context2d.arc(x, y, 2.3 + amplitude * 2, 0, Math.PI * 2);
        context2d.fill();
      } else if (mode === 'line') {
        linePoints.push([x, y]);
      } else {
      context2d.beginPath();
      context2d.moveTo(cx + Math.cos(angle) * radius, cy + Math.sin(angle) * radius);
      context2d.lineTo(x, y);
      context2d.stroke();
      }
    }
    if (mode === 'line' && linePoints.length) {
      const gradient = context2d.createLinearGradient(0, 0, width, 0);
      gradient.addColorStop(0, colorAt(0));
      gradient.addColorStop(.5, colorAt(.5));
      gradient.addColorStop(1, colorAt(1));
      context2d.strokeStyle = gradient;
      context2d.beginPath();
      linePoints.forEach(([x, y], index) => { if (index === 0) context2d.moveTo(x, y); else context2d.lineTo(x, y); });
      context2d.closePath();
      context2d.stroke();
    }
  }
}

$('audioFiles').addEventListener('change', (event) => {
  files = Array.from(event.target.files || []);
  if (files.length) chooseTrack(0);
});
$('artworkFile').addEventListener('change', (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (artworkUrl) URL.revokeObjectURL(artworkUrl);
  artworkUrl = URL.createObjectURL(file);
  applyArtwork(artworkUrl);
});
for (const id of ['backgroundMode', 'visualMode', 'points', 'animationScale', 'frequencyBand', 'zoomBand', 'symmetry', 'autoColor', 'color1', 'color2', 'color3', 'offsetX', 'offsetY', 'fps', 'blurAmount', 'staticDim', 'morphSpeed', 'showThumbnail', 'beatZoom']) {
  $(id).addEventListener('input', (event) => {
    if (event.target.type === 'range') {
      const suffix = ['offsetX', 'offsetY', 'blurAmount'].includes(id) ? ' px' : ['animationScale', 'staticDim'].includes(id) ? '%' : id === 'morphSpeed' ? ' s' : '';
      $(`${id}Value`).textContent = `${event.target.value}${suffix}`;
    }
    scheduleSettings();
  });
}
$('playButton').addEventListener('click', togglePlayback);
$('prevButton').addEventListener('click', async () => {
  if (files.length > 1 && audio.currentTime < 3) chooseTrack(currentIndex - 1);
  else audio.currentTime = 0;
  if (audio.paused) await togglePlayback();
});
$('nextButton').addEventListener('click', async () => {
  if (files.length > 1) chooseTrack(currentIndex + 1);
  else audio.currentTime = 0;
  if (audio.paused) await togglePlayback();
});
audio.addEventListener('play', () => { $('playButton').textContent = 'Ⅱ'; $('playButton').setAttribute('aria-label', 'Tạm dừng'); status('Đang phát. Viền sáng hiển thị tiến trình bài hát.'); });
audio.addEventListener('pause', () => { $('playButton').textContent = '▶'; $('playButton').setAttribute('aria-label', 'Phát'); });
audio.addEventListener('timeupdate', updateProgress);
audio.addEventListener('loadedmetadata', updateProgress);
audio.addEventListener('ended', async () => {
  if (files.length > 1) chooseTrack(currentIndex + 1);
  else audio.currentTime = 0;
  await togglePlayback();
});
audio.addEventListener('error', () => {
  if (!files.length) status(`Chưa tìm thấy ${defaultSource}. Hãy nạp nhạc bằng nút Nhạc thử.`);
  else status('Tệp nhạc này không phát được trong trình duyệt.');
});
window.addEventListener('resize', resizeCanvas);
window.addEventListener('beforeunload', () => {
  cancelAnimationFrame(rafId);
  if (objectUrl) URL.revokeObjectURL(objectUrl);
  if (artworkUrl) URL.revokeObjectURL(artworkUrl);
});
applySettings();
resizeCanvas();
draw();
