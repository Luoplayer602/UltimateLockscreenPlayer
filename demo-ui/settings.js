const settingsScreen = document.getElementById('settingsScreen');
const settingsScroll = document.getElementById('settingsScroll');
const previewHost = document.getElementById('settingsPreviewHost');
const settingsTitle = document.getElementById('settingsTitle');
const fakeHome = document.getElementById('fakeHome');
const STORE = new URLSearchParams(location.search).has('test') ? 'ulp-demo-settings-test' : 'ulp-demo-settings-v2';
const saved = (() => { try { return JSON.parse(localStorage.getItem(STORE)) || {}; } catch { return {}; } })();
const design = {mode:modeSpecs[saved.mode] ? saved.mode : 'waveform', enabled:saved.enabled !== false,
  visualEnabled:saved.visualEnabled !== false, language:saved.language === 'en' ? 'en' : 'vi', profiles:saved.profiles || {}};
let settingsPage = 'root';
let previewControlsTimer = 0;
let previewFeedbackTimer = 0;
const viLabels = {
  'TWEAK ENABLED':'BẬT TWEAK','SETTINGS':'CÀI ĐẶT','MERGED PRESETS':'PRESET TỔNG HỢP',
  'PROJECT':'DỰ ÁN','VISUAL ENABLED':'BẬT VISUAL','SPECTRUM':'PHỔ TẦN',
  'WAVEFORM':'DẠNG SÓNG','CIRCULAR':'VÒNG TRÒN','COLOUR':'MÀU SẮC',
  'POSITION & SIZE':'VỊ TRÍ & KÍCH THƯỚC','RESET':'ĐẶT LẠI','BACKGROUND':'HÌNH NỀN',
  'EFFECTS':'HIỆU ỨNG','COVER':'ẢNH GIỮA','AUDIO RESPONSE':'PHẢN ỨNG ÂM THANH',
  'Mode':'Chế độ','Colour 1':'Màu 1','Colour 2':'Màu 2','Gradient angle':'Góc chuyển màu',
  'Opacity':'Độ mờ','Glow':'Quầng sáng','Horizontal position':'Vị trí ngang','Vertical position':'Vị trí dọc',
  'Width':'Chiều rộng','Height':'Chiều cao','Scale':'Tỷ lệ','Rotation':'Góc xoay',
  'Flip horizontally':'Lật ngang','Flip vertically':'Lật dọc','Non-artwork songs':'Bài không có artwork',
  'Artwork background':'Nền artwork','Artwork background type':'Kiểu nền artwork','Dim':'Làm tối','Blur':'Làm mờ',
  'Trail':'Vệt lưu','Beat reaction':'Phản ứng theo nhịp','Grain':'Hạt ảnh','Cover mode':'Kiểu ảnh giữa',
  'Size':'Kích thước','Outline thickness':'Độ dày viền','Outline colour':'Màu viền',
  'Outline opacity':'Độ mờ viền','React to beat':'Phản ứng theo nhịp','Beat motion':'Chuyển động theo nhịp',
  'React to beat type':'Nguồn phản ứng',
  'Rumble':'Rung nhẹ','Drift':'Trôi nhẹ','Glow pulse':'Quầng sáng theo nhạc','Spin · °/s':'Xoay · °/s',
  'Sensitivity':'Độ nhạy','Bass':'Âm trầm','Mids':'Âm trung','Treble':'Âm cao',
  'Smoothing':'Làm mượt','Waveform smoothing':'Làm mượt dạng sóng','Normalise level':'Chuẩn hóa âm lượng',
  'Visual: frequency band':'Dải âm visualizer','Zoom: frequency band':'Dải âm Zoom',
  'Bars':'Số cột','Bar width':'Độ rộng cột','Spacing':'Khoảng cách','Bar height':'Chiều cao cột',
  'Corner radius':'Bo góc','Frequency range':'Dải tần','Mirror':'Đối xứng','Reverse':'Đảo chiều',
  'Edge fade':'Mờ cạnh','Grow from':'Mọc từ','Minimum height · px':'Chiều cao tối thiểu · px',
  'Dynamics':'Động lực','Peak caps':'Vạch đỉnh','Cap thickness · px':'Độ dày vạch đỉnh · px',
  'Rows':'Số hàng','Unlit opacity':'Độ mờ ô tắt','Detail':'Độ chi tiết','Thickness':'Độ dày',
  'Fill under curve':'Tô dưới đường','Fill opacity':'Độ mờ phần tô','Mirror vertically':'Đối xứng dọc',
  'Dot size':'Cỡ chấm','Amplitude':'Biên độ','Smooth curve':'Đường cong mượt',
  'Fill under wave':'Tô dưới sóng','Centre gap':'Khoảng trống giữa','Fill':'Tô màu',
  'Inner radius':'Bán kính trong','Bar length':'Chiều dài tia','Bar thickness':'Độ dày tia',
  'Rotation speed · °/s':'Tốc độ xoay · °/s','Symmetry':'Đối xứng','Grow inward':'Mọc vào trong',
  'Rounded caps':'Đầu bo tròn','Show inner ring':'Hiện vòng trong','Ring opacity':'Độ mờ vòng',
  'Peak caps type':'Kiểu vạch đỉnh','Hide visualizer but peak caps':'Chỉ hiện vạch đỉnh',
  'Fill ring':'Tô vòng','Reactivity':'Độ phản ứng',
  'Beat sensitivity':'Độ nhạy bắt nhịp','Minimum beat interval · s':'Khoảng cách nhịp tối thiểu · s','Beat release · s':'Thời gian nhả nhịp · s'
};
const tr = text => design.language === 'vi' ? (viLabels[text] || text) : text;

function profile() {
  const current = design.profiles[design.mode] || (design.profiles[design.mode] = {});
  for (const field of [...modeSpecs[design.mode].fields, ...Object.values(shared).flat()]) {
    if (current[field.id] === undefined) current[field.id] = field.value;
    if(field.type === 'picker' && !field.options.some(([key]) => key === current[field.id])) current[field.id] = field.value;
    if(field.type === 'range') current[field.id] = Number.isFinite(Number(current[field.id])) ? Math.max(field.min,Math.min(field.max,Number(current[field.id]))) : field.value;
    if(field.type === 'color' && !/^#[0-9a-f]{6}$/i.test(current[field.id])) current[field.id] = field.value;

  }
  return current;
}
function save() { try { localStorage.setItem(STORE, JSON.stringify(design)); } catch {} }
function section(title, content, note = '') {
  return `<section class="setting-section"><h2>${tr(title)}</h2><div class="setting-card">${content}</div>${note ? `<p class="setting-note">${note}</p>` : ''}</section>`;
}
function row(label, content) { return `<div class="setting-row"><span>${label}</span>${content}</div>`; }
function link(label, page, value = '') {
  return `<button class="setting-row setting-link" type="button" data-page="${page}"><span>${label}</span><span class="setting-value">${value}<b>›</b></span></button>`;
}
function renderField(field) {
  const value = profile()[field.id];
  const id = `setting-${field.id}`;
  const help = field.help ? `<small>${field.help}</small>` : '';
  const depends = {colour1:'colourMode',colour2:'colourMode',gradientAngle:'colourMode',backgroundColour2:'nonArtworkBackground',artworkBackgroundType:'artworkBackground',fillOpacity:'fill',capThickness:'peakCaps',peakCapsType:'peakCaps',ringOpacity:'showInnerRing',hideVisual:'peakCaps'};
  let disabled = false;
  if (field.id === 'colour1') disabled = profile().colourMode === 'artwork';
  else if (field.id === 'colour2' || field.id === 'gradientAngle') disabled = profile().colourMode !== 'gradient';
  else if (field.id === 'backgroundColour2') disabled = profile().nonArtworkBackground !== 'gradient';
  else if (field.id === 'beatMotion') disabled = profile().coverReactType === 'raw';
  else if (depends[field.id] && field.id !== 'backgroundColour2') disabled = !profile()[depends[field.id]];
  const disabledClass = disabled ? ' is-disabled' : '';
  const disabledAttr = disabled ? ' disabled' : '';
  if (field.type === 'range') return `<div class="setting-slider${disabledClass}"><div class="setting-slider-title"><label for="${id}">${tr(field.label)}</label><output>${Number(value).toFixed(field.step < .01 ? 3 : field.step < 1 ? 2 : 0)}</output></div><input id="${id}" type="range" data-field="${field.id}" min="${field.min}" max="${field.max}" step="${field.step}" value="${value}"${disabledAttr}>${help}</div>`;
  if (field.type === 'toggle') return `<label class="setting-row setting-field${disabledClass}"><span>${tr(field.label)}${help}</span><input class="setting-toggle" type="checkbox" data-field="${field.id}" ${value ? 'checked' : ''}${disabledAttr}></label>`;
  if (field.type === 'color') return `<label class="setting-row setting-field${disabledClass}"><span>${tr(field.label)}</span><span class="setting-value">${String(value).toUpperCase()} <input class="setting-color" type="color" data-field="${field.id}" value="${value}"${disabledAttr}></span></label>`;
  return `<label class="setting-row setting-picker${disabledClass}"><span>${tr(field.label)}${help}</span><select data-field="${field.id}"${disabledAttr}>${field.options.map(([key,label]) => `<option value="${key}" ${key === value ? 'selected' : ''}>${label}</option>`).join('')}</select></label>`;
}
function refreshDependentControls() {
  if (settingsPage !== 'visualizer') return;
  const p = profile();
  const enabled = {
    colour1:p.colourMode !== 'artwork',
    colour2:p.colourMode === 'gradient',
    gradientAngle:p.colourMode === 'gradient',
    backgroundColour2:p.nonArtworkBackground === 'gradient',
    artworkBackgroundType:Boolean(p.artworkBackground),
    fillOpacity:Boolean(p.fill),
    capThickness:Boolean(p.peakCaps),
    peakCapsType:Boolean(p.peakCaps),
    ringOpacity:Boolean(p.showInnerRing),
    hideVisual:Boolean(p.peakCaps),
    beatMotion:p.coverReactType !== 'raw'
  };
  for (const [id, active] of Object.entries(enabled)) {
    const input = [...settingsScroll.querySelectorAll('[data-field]')].find(node => node.dataset.field === id);
    if (!input) continue;
    input.disabled = !active;
    input.closest('.setting-row, .setting-slider')?.classList.toggle('is-disabled',!active);
  }
}
function fields(title, list, note = '') { return section(title, list.map(renderField).join(''), note); }
function previewMarkup() {
  return `<div class="settings-preview" id="settingsPreview" role="group" aria-label="Preview visualizer"><canvas id="settingsPreviewCanvas" aria-hidden="true"></canvas><span class="preview-caption" id="previewCaption">PREVIEW</span><span class="beat-indicator" id="previewBeat">BEAT</span><span id="settingsPreviewFeedback" class="preview-feedback" aria-live="polite"></span><button id="settingsPreviewPlay" type="button" aria-label="Phát preview">▶</button></div>`;
}
function announceSetting(id, value, isLive = true) {
  const badge = document.getElementById('settingsPreviewFeedback');
  if (!badge) return;
  const descriptor = [...modeSpecs[design.mode].fields,...Object.values(shared).flat()].find(field => field.id === id);
  const label = descriptor ? tr(descriptor.label) : id;
  const shown = typeof value === 'boolean' ? (value ? 'On' : 'Off') : String(value);
  badge.textContent = `${label}: ${shown}`;
  badge.classList.add('visible');
  clearTimeout(previewFeedbackTimer);
  previewFeedbackTimer = setTimeout(() => badge.classList.remove('visible'),2200);
}
function rootPage() {
  const later = design.language === 'vi' ? 'Sắp có' : 'Planned';
  return section('TWEAK ENABLED', row('Enabled', `<input class="setting-toggle" type="checkbox" data-global="enabled" ${design.enabled ? 'checked' : ''}>`)) +
    section('SETTINGS', link('Visualizer','visualizer') + row('Lyrics',`<span class="setting-value">${later}</span>`)) +
    section('MERGED PRESETS',row('Merged presets',`<span class="setting-value">${later}</span>`)) +
    section('PROJECT', `<label class="setting-row setting-picker"><span>Language</span><select data-global="language"><option value="vi" ${design.language === 'vi' ? 'selected' : ''}>Tiếng Việt</option><option value="en" ${design.language === 'en' ? 'selected' : ''}>English</option></select></label><a class="setting-row setting-link" href="https://github.com/luoplayer602" target="_blank" rel="noopener noreferrer"><span>GitHub · luoplayer602</span><span class="setting-value">↗</span></a>`);
}
function visualizerPage() {
  const mode = modeSpecs[design.mode];
  return section('VISUAL ENABLED', row('Enabled', `<input class="setting-toggle" type="checkbox" data-global="visualEnabled" ${design.visualEnabled ? 'checked' : ''}>`)) +
    section('SETTINGS', link('Modes','modes',mode.label) + link('Preview toàn màn hình','preview')) +
    fields(mode.family, mode.fields, mode.help || '') +
    fields('COLOUR', shared.colour,'Chọn Solid hoặc Gradient để bật màu thủ công; Artwork lấy màu từ ảnh bìa.') + fields('POSITION & SIZE',shared.position) +
    section('RESET', '<button type="button" class="setting-row setting-link" data-reset="position"><span>Reset position & size</span></button>') +
    fields('BACKGROUND',shared.background) + fields('EFFECTS',shared.effects) +
    fields('COVER',shared.cover,'A circular image at the centre of the frame. Circular visualizer styles are designed to wrap around it.') +
    section('RESET', '<button type="button" class="setting-row setting-link" data-reset="cover"><span>Reset cover</span></button>') +
    fields('AUDIO RESPONSE',shared.audio,'Dải Visual và Zoom độc lập. Preview dùng cùng nhạc thử với màn hình khóa.');
}
function modesPage() {
  return ['SPECTRUM','WAVEFORM','CIRCULAR'].map(family => section(family,
    Object.entries(modeSpecs).filter(([,mode]) => mode.family === family).map(([id,mode]) =>
      `<button class="setting-row setting-link mode-choice" type="button" data-mode="${id}"><span>${mode.label}${mode.detail ? `<small>${mode.detail}</small>` : ''}</span><span class="setting-value">${id === design.mode ? '✓' : ''}</span></button>`).join(''))).join('') +
    '<p class="setting-note mode-note">Mỗi mode ghi nhớ các giá trị riêng trong trình duyệt.</p>';
}
function setPage(page) {
  settingsPage = page;
  settingsScreen.dataset.page = page;
  settingsTitle.textContent = {root:'ULP',visualizer:'Visualizer',modes:'Modes',preview:'Preview'}[page];
  document.getElementById('settingsBack').hidden = false;
  previewHost.hidden = page === 'root';
  previewHost.innerHTML = page === 'root' ? '' : previewMarkup();
  settingsScroll.innerHTML = page === 'root' ? rootPage() : page === 'visualizer' ? visualizerPage() : page === 'modes' ? modesPage() : section('PREVIEW',link('Chỉnh visualizer','visualizer'));
  settingsScroll.scrollTop = 0;
  refreshDependentControls();
  syncPreviewButton();
  window.updateSettingsPreview();
}
function syncDesign() {
  const p = profile();
  window.demoVisualMode = design.mode;
  window.demoVisualProfile = p;
  window.demoEnabled = design.enabled;
  window.demoVisualEnabled = design.visualEnabled;
  save();
  window.refreshDemo();
}
function togglePhone() {
  const open = settingsScreen.hidden;
  settingsScreen.hidden = !open;
  fakeHome.setAttribute('aria-label',open ? 'Về màn hình khóa giả lập' : 'Mở Cài đặt giả lập');
  if (open) setPage('root');
}
function revealPreviewPlay() {
  const button = document.getElementById('settingsPreviewPlay');
  if (!button) return;
  button.classList.remove('is-hidden');
  clearTimeout(previewControlsTimer);
  if (!audio.paused) previewControlsTimer = setTimeout(() => button.classList.add('is-hidden'),2600);
}
function syncPreviewButton() {
  const button = document.getElementById('settingsPreviewPlay');
  if (!button) return;
  button.textContent = audio.paused ? '▶' : 'Ⅱ';
  button.setAttribute('aria-label',audio.paused ? 'Phát preview' : 'Tạm dừng preview');
  if (audio.paused) button.classList.remove('is-hidden'); else revealPreviewPlay();
}
window.updateSettingsPreview = function() {
  if (settingsScreen.hidden) return;
  const target = document.getElementById('settingsPreviewCanvas');
  const card = document.getElementById('settingsPreview');
  if (!target || !card) return;
  const ratio = Math.min(window.devicePixelRatio || 1, 2);
  const width = Math.max(1,Math.round(card.clientWidth*ratio));
  const height = Math.max(1,Math.round(card.clientHeight*ratio));
  if(target.width !== width) target.width = width;
  if(target.height !== height) target.height = height;
  sceneRenderer.copyPreview(target,settingsPage === 'preview');
  document.getElementById('previewCaption').textContent = `PREVIEW · ${document.getElementById('songTitle').textContent}`;
  document.getElementById('previewBeat').classList.toggle('active',lastAudioFrame.playing && lastAudioFrame.time-lastAudioFrame.lastBeatAt<.15);
};

fakeHome.addEventListener('click',togglePhone);
document.getElementById('settingsBack').addEventListener('click',() => {
  if (settingsPage === 'root') togglePhone();
  else setPage(['modes','preview'].includes(settingsPage) ? 'visualizer' : 'root');
});
document.getElementById('settingsApply').addEventListener('click',() => {
  syncDesign();
  status('Đã áp dụng cài đặt trong demo. Trên iPhone, Apply sẽ Respring.');
  togglePhone();
});
settingsScroll.addEventListener('click',event => {
  const choice = event.target.closest('button[data-mode]');
  if (choice) { design.mode = choice.dataset.mode; profile(); syncDesign(); setPage('visualizer'); return; }
  const nav = event.target.closest('button[data-page]');
  if (nav) { setPage(nav.dataset.page); return; }
  const reset = event.target.closest('button[data-reset]');
  if (reset) {
    const group = shared[reset.dataset.reset];
    for (const field of group) {
      profile()[field.id] = field.value;
      const input = [...settingsScroll.querySelectorAll('[data-field]')].find(node => node.dataset.field === field.id);
      if (!input) continue;
      if (input.type === 'checkbox') input.checked = Boolean(field.value);
      else input.value = field.value;
      const output = input.closest('.setting-slider')?.querySelector('output');
      if (output) output.textContent = String(field.value);
      if (input.type === 'color') input.parentElement.firstChild.textContent = `${String(field.value).toUpperCase()} `;
    }
    syncDesign(); refreshDependentControls(); window.updateSettingsPreview();
    announceSetting('Reset',reset.dataset.reset,true);
    return;
  }
});
previewHost.addEventListener('click',event => {
  if (event.target.closest('#settingsPreviewPlay')) { togglePlayback(); return; }
  if (event.target.closest('#settingsPreview')) revealPreviewPlay();
});
function handleSettingControl(event) {
  const fieldId = event.target.dataset.field;
  const globalId = event.target.dataset.global;
  if (!fieldId && !globalId) return;
  const value = event.target.type === 'checkbox' ? event.target.checked : event.target.type === 'range' ? Number(event.target.value) : event.target.value;
  if (event.type === 'change' && (fieldId ? profile()[fieldId] : design[globalId]) === value) return;
  if (fieldId) profile()[fieldId] = value;
  else design[globalId] = value;
  syncDesign();
  window.updateSettingsPreview();
  if (fieldId && (event.type === 'change' || event.target.type !== 'range')) announceSetting(fieldId,value);
  if (globalId === 'language') { setPage(settingsPage); return; }
  if (fieldId) {
    refreshDependentControls();
    const output = event.target.closest('.setting-slider')?.querySelector('output');
    if (output) output.textContent = String(value);
    if (event.target.type === 'color') event.target.parentElement.firstChild.textContent = `${String(value).toUpperCase()} `;
  }
}
settingsScroll.addEventListener('input',handleSettingControl);
settingsScroll.addEventListener('change',handleSettingControl);
audio.addEventListener('play',syncPreviewButton);
audio.addEventListener('pause',syncPreviewButton);
syncDesign();
window.syncDemoSettings = syncDesign;
setPage('root');
