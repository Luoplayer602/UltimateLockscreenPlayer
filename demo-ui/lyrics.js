/* Lyrics prototype: YouTube ID -> Unison lyrics/metadata/thumbnail; local audio drives timing. */
(() => {
  const key = new URLSearchParams(location.search).has('test') ? 'ulp-demo-lyrics-test' : 'ulp-demo-lyrics-v1';
  const saved = (() => { try { return JSON.parse(localStorage.getItem(key)) || {}; } catch { return {}; } })();
  const state = {
    videoId: saved.videoId || '', preset: saved.preset === 'preset1' ? saved.preset : 'preset1', lines: [], translated: [], raw: null, request: 0,
    cards: [], activeIndex: -1,
    message: saved.videoId ? 'Nhấn Lấy lời để tải lại' : '',
    options: { enabled: saved.enabled !== false, english: saved.english !== false,
      romanization: saved.romanization !== false, offset: Number.isFinite(Number(saved.offset)) ? Number(saved.offset) : 0 }
  };
  let requestController = null;
  const byId = id => document.getElementById(id);
  const save = () => { try { localStorage.setItem(key, JSON.stringify({ videoId: state.videoId, preset: state.preset, ...state.options })); } catch {} };
  const sourceStatus = text => {
    byId('lyricsSourceStatus').textContent = text;
  };
  const validId = value => {
    const text = String(value || '').trim();
    if (/^[\w-]{11}$/.test(text)) return text;
    try {
      const url = new URL(text);
      if (!['youtube.com','www.youtube.com','music.youtube.com','m.youtube.com','youtu.be'].includes(url.hostname)) return '';
      const id = url.hostname === 'youtu.be' ? url.pathname.slice(1) : url.searchParams.get('v');
      return /^[\w-]{11}$/.test(id || '') ? id : '';
    } catch { return ''; }
  };
  const seconds = value => {
    if (!value) return null;
    if (/^\d+(?:\.\d+)?s$/.test(value)) return Number.parseFloat(value);
    const parts = value.split(':').map(Number);
    return parts.length <= 3 && parts.every(Number.isFinite) ? parts.reduce((sum, part) => sum * 60 + part, 0) : null;
  };
  function parseLyrics(raw, format) {
    if (format === 'lrc' || /\[\d{1,2}:\d{2}/.test(raw)) {
      const lines = [];
      for (const row of raw.split(/\r?\n/)) {
        const stamps = [...row.matchAll(/\[(\d{1,2}:\d{2}(?:\.\d+)?)\]/g)];
        const text = row.replace(/\[[^\]]+\]/g, '').replace(/<\d{1,2}:\d{2}(?:\.\d+)?>/g, '').trim();
        for (const stamp of stamps) lines.push({ start: seconds(stamp[1]), text });
      }
      return lines.filter(line => line.start !== null).sort((a,b) => a.start - b.start);
    }
    if (format === 'ttml' || raw.trimStart().startsWith('<')) {
      const xml = new DOMParser().parseFromString(raw, 'application/xml');
      if (xml.querySelector('parsererror')) throw new Error('TTML không hợp lệ');
      return [...xml.getElementsByTagName('*')].filter(node => node.localName === 'p').map(node => ({
        start: seconds(node.getAttribute('begin')), end: seconds(node.getAttribute('end')), text: node.textContent.trim()
      })).filter(line => line.start !== null || line.text);
    }
    return raw.split(/\r?\n/).map(text => ({ start: null, text: text.trim() }));
  }
  function addInstrumentalGaps(parsed) {
    if (!parsed.some(line => line.start !== null)) return parsed.map((line, sourceIndex) => ({ ...line, kind: line.text ? 'lyric' : 'blank', sourceIndex }));
    const result = [];
    const first = parsed.find(line => line.start !== null);
    if (first?.start > 8) result.push({ start:0, text:'', kind:'instrumental', sourceIndex:-1 });
    for (let i = 0; i < parsed.length; i++) {
      const line = parsed[i];
      result.push({ ...line, kind: line.text === '♪' ? 'instrumental' : line.text ? 'lyric' : 'blank', sourceIndex:i });
      const next = parsed.slice(i+1).find(item => item.start !== null);
      if (!next || line.start === null || line.kind === 'instrumental' || line.text === '♪') continue;
      const gapStart = line.end !== null && line.end !== undefined ? line.end : line.start + (line.text ? 3.5 : .4);
      if (next.start - gapStart >= 8) result.push({ start:gapStart, text:'', kind:'instrumental', sourceIndex:-1 });
    }
    return result.sort((a,b) => (a.start ?? Infinity)-(b.start ?? Infinity));
  }
  function render() {
    const overlay = byId('lyricsOverlay');
    overlay.hidden = !state.options.enabled || (!state.videoId && !state.lines.length);
    byId('lyricsToggle').classList.toggle('is-active', state.options.enabled);
    const track = byId('lyricsTrack'), empty = byId('lyricsEmpty');
    if (!state.lines.length) {
      track.replaceChildren(); track.hidden = true;
      empty.hidden = false;
      empty.textContent = state.message || (state.videoId ? 'Đang lấy lời…' : 'Nhập YouTube ID để lấy lời');
      state.cards = []; state.activeIndex = -1;
      return;
    }
    empty.hidden = true; track.hidden = false;
    const fragment = document.createDocumentFragment();
    state.cards = state.lines.map((line,index) => {
      const card = document.createElement('div'); card.className = 'lyric-card'; card.dataset.index = index;
      if (line.kind === 'blank') card.classList.add('is-blank');
      if (line.kind === 'instrumental') card.classList.add('is-instrumental');
      if (line.kind === 'instrumental') {
        const note = document.createElement('span'); note.className = 'instrumental-note'; note.setAttribute('aria-label','Nhạc dạo');
        for (const layer of ['base','fill']) {
          const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
          svg.setAttribute('viewBox','0 0 40 48'); svg.setAttribute('aria-hidden','true'); svg.classList.add(`instrumental-note-${layer}`);
          const glyph = document.createElementNS('http://www.w3.org/2000/svg','text');
          glyph.setAttribute('x','1'); glyph.setAttribute('y','40'); glyph.textContent='♪'; svg.append(glyph); note.append(svg);
        }
        card.append(note); fragment.append(card); return card;
      }
      const original = document.createElement('span'); original.className = 'lyric-card-original'; original.textContent = line.text;
      const romanization = document.createElement('span'); romanization.className = 'lyric-card-romanization';
      const translation = document.createElement('span'); translation.className = 'lyric-card-translation';
      const extra = state.translated[index] || {};
      romanization.textContent = state.options.romanization ? extra.romanization || '' : '';
      translation.textContent = state.options.english && extra.needsTranslation !== false ? extra.translation || '' : '';
      card.append(original,romanization,translation); fragment.append(card); return card;
    });
    track.replaceChildren(fragment);
    state.activeIndex = -1;
    updateTime(true);
  }
  function updateTime(jump = false) {
    if (!state.cards.length) return;
    const position = audio.currentTime + state.options.offset;
    let active = 0;
    for (let i = 0; i < state.lines.length; i++) {
      if (state.lines[i].start !== null && state.lines[i].start <= position) active = i;
    }
    const track = byId('lyricsTrack');
    if (active !== state.activeIndex || jump) {
      const previous = state.activeIndex;
      state.activeIndex = active;
      state.cards.forEach((card,index) => {
        card.classList.toggle('is-active',index === active);
        card.classList.toggle('is-near',Math.abs(index-active) === 1);
        if (state.lines[index].kind === 'instrumental' && index !== active) card.style.setProperty('--gap-progress',index < active ? '100%' : '0%');
      });
      const card = state.cards[active];
      const center = byId('lyricsOverlay').clientHeight * .46;
      const y = center - (card.offsetTop + card.offsetHeight/2);
      if (jump || previous < 0 || Math.abs(active-previous) > 2) {
        track.style.transition = 'none';
        track.style.transform = `translate3d(0,${y}px,0)`;
        requestAnimationFrame(() => { track.style.transition = ''; });
      } else track.style.transform = `translate3d(0,${y}px,0)`;
    }
    const line = state.lines[active];
    const next = state.lines.slice(active+1).find(item => item.start !== null && item.start > line.start);
    const end = next?.start ?? (Number.isFinite(audio.duration) ? audio.duration : (line.start ?? 0)+5);
    const fraction = line.start === null ? 0 : Math.max(0,Math.min(1,(position-line.start)/Math.max(.1,end-line.start)));
    state.cards[active].style.setProperty('--lyric-progress',`${(fraction*100).toFixed(1)}%`);
    if (line.kind === 'instrumental') state.cards[active].style.setProperty('--gap-progress',`${(fraction*100).toFixed(1)}%`);
  }
  async function translate() {
    if (!state.lines.length || (!state.options.english && !state.options.romanization)) return;
    const sourceLines = state.lines.filter(line => line.sourceIndex >= 0);
    if (sourceLines.length > 200) return sourceStatus('Có hơn 200 dòng; bản demo chưa chia yêu cầu dịch thành nhiều đợt.');
    const request = state.request;
    sourceStatus('Đã lấy lời · đang lấy bản dịch tiếng Anh và phiên âm…');
    try {
      const response = await fetch('/api/translate', {
        method: 'POST', headers: { 'Content-Type':'application/json' }, signal: requestController.signal,
        body: JSON.stringify({ lines: sourceLines.map(line => line.text), to:'en', videoId:state.videoId })
      });
      const data = await response.json();
      if (request !== state.request) return;
      if (!response.ok || !Array.isArray(data.lines)) throw new Error(data.error || `HTTP ${response.status}`);
      if (data.lines.length !== sourceLines.length) throw new Error('Số dòng dịch không khớp lời gốc');
      state.translated = state.lines.map(line => line.sourceIndex >= 0 ? data.lines[line.sourceIndex] : null); render();
      const romanized = data.lines.filter(line => line.romanization).length;
      sourceStatus(`Đã lấy ${state.lines.length} dòng · ${romanized} dòng có phiên âm · ${data.provider || 'Unison'}`);
    } catch (error) {
      if (error.name !== 'AbortError') sourceStatus(`Có lời gốc; không lấy được bản dịch: ${error.message}`);
    }
  }
  async function loadVideo(value) {
    const videoId = validId(value);
    if (!videoId) return sourceStatus('Nhập YouTube video ID gồm 11 ký tự hoặc URL hợp lệ.');
    requestController?.abort(); requestController = new AbortController();
    const request = ++state.request;
    state.videoId = videoId; state.lines = []; state.translated = []; state.raw = null; state.message = 'Đang lấy lời…';
    byId('lyricsVideoId').value = videoId;
    save(); render(); sourceStatus('Đang lấy lời và thumbnail…');
    applyArtwork(`/api/thumbnail?v=${encodeURIComponent(videoId)}`);
    try {
      const response = await fetch(`/api/lyrics?v=${encodeURIComponent(videoId)}`, { signal:requestController.signal });
      const data = await response.json();
      if (request !== state.request) return;
      if (!response.ok || typeof data.data?.lyrics !== 'string') throw new Error(data.error || `HTTP ${response.status}`);
      state.raw = data.data;
      state.lines = addInstrumentalGaps(parseLyrics(data.data.lyrics, data.data.format));
      state.message = '';
      if (data.data.song) byId('songTitle').textContent = data.data.song;
      if (data.data.artist) byId('songArtist').textContent = data.data.artist;
      sourceStatus(`${state.lines.length} dòng · ${data.data.format || 'plain'} · ${data.data.syncType || 'không đồng bộ'}`);
      render();
      if (state.options.english || state.options.romanization) translate();
    } catch (error) {
      if (error.name === 'AbortError') return;
      state.message = 'Không tìm thấy lời bài hát';
      sourceStatus(`Không lấy được lời: ${error.message}`);
      render();
    }
  }
  function setOption(option, value) {
    if (!(option in state.options)) return;
    state.options[option] = option === 'offset' ? Math.max(-10, Math.min(10, Number(value) || 0)) : Boolean(value);
    save();
    if (option === 'english' || option === 'romanization') render();
    else {
      byId('lyricsOverlay').hidden = !state.options.enabled || (!state.videoId && !state.lines.length);
      byId('lyricsToggle').classList.toggle('is-active', state.options.enabled);
      updateTime(option === 'offset' || option === 'enabled');
    }
    if ((option === 'english' || option === 'romanization') && value && !state.translated.length && state.lines.length) translate();
  }
  function selectPreset(id) {
    if (id !== 'preset1') return;
    state.preset = id;
    save();
    render();
  }
  byId('lyricsVideoId').value = state.videoId;
  byId('loadLyrics').addEventListener('click', () => loadVideo(byId('lyricsVideoId').value));
  byId('lyricsVideoId').addEventListener('keydown', event => { if (event.key === 'Enter') loadVideo(event.target.value); });
  byId('lyricsToggle').addEventListener('click', () => setOption('enabled', !state.options.enabled));
  audio.addEventListener('timeupdate', () => updateTime());
  audio.addEventListener('seeked', () => updateTime(true));
  audio.addEventListener('loadedmetadata', () => updateTime(true));
  window.addEventListener('resize', () => updateTime(true));
  window.demoLyrics = { state, loadVideo, setOption, selectPreset, render, updateTime, translate, parseLyrics, addInstrumentalGaps };
  render();
})();
