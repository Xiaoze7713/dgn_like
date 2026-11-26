/* NPK Inspector · 单文件查看器前端
 * 解析在 core/npk_core.js，本文件只做装载 / 渲染 / 交互。
 */
(function () {
  'use strict';
  const C = window.NPKCore;
  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const ROW_H = 46;
  const dpr = Math.min(window.devicePixelRatio || 1, 2);

  const TYPE_NAME = Object.assign({
    14: 'ARGB1555', 15: 'ARGB4444', 16: 'ARGB8888',
    17: '指向帧', 18: 'FXT1 / DXT1', 19: 'FXT2 / DXT3', 20: 'FXT3 / DXT5',
    0x0E: 'ARGB1555', 0x0F: 'ARGB4444', 0x10: 'ARGB8888', 0x11: '指向帧',
    0x12: 'FXT1 / DXT1', 0x13: 'FXT2 / DXT3', 0x14: 'FXT3 / DXT5',
  });
  const CMP_NAME = { 0: '无', 1: '1?', 5: 'raw 未压缩', 6: 'zlib 压缩', 7: 'DDS 引用' };
  const VER_NAME = { 1: 'v1 旧格式', 2: 'v2', 4: 'v4 调色板', 5: 'v5 共享贴图', 6: 'v6 调色板索引' };
  const COLORS = ['#3ec6ff', '#f7b955', '#b18cff', '#3ddc97', '#ff8fab', '#7dd3fc', '#fbbf24', '#a3e635'];

  const state = {
    fileName: '', fileSize: 0, bytes: null, npk: null, isDemo: false,
    entries: [], view: [], sel: -1, filter: 'all', q: '',
    img: null, imgEntry: null, frame: 0, playing: false, fps: 8, playTimer: 0,
    tab: 'preview', zoom: 'fit', bg: 'checker', showCanvas: true, showOrigin: true,
    audioBuf: null, audioEl: null, audioUrl: '', ogg: null,
    ddsHover: -1, structOffset: 0, structSel: -1, token: 0,
    imgCache: new Map(), frameCanvas: new Map(), drawToken: 0,
  };

  /* ---------------- 小工具 ---------------- */
  const esc = (s) => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function fmtBytes(n) {
    if (n == null) return '—';
    if (n < 1024) return n + ' B';
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 2 : 1) + ' KB';
    return (n / 1048576).toFixed(2) + ' MB';
  }
  const hex = (n, pad) => '0x' + (n >>> 0).toString(16).toUpperCase().padStart(pad || 2, '0');
  const commafy = (n) => String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const baseName = (p) => p.split('/').pop();
  const dirName = (p) => { const i = p.lastIndexOf('/'); return i < 0 ? '' : p.slice(0, i + 1); };
  function toast(msg, isErr) {
    const t = document.createElement('div');
    t.className = 'toast' + (isErr ? ' err' : '');
    t.textContent = msg;
    $('#toasts').appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; t.style.transition = 'opacity .3s'; setTimeout(() => t.remove(), 320); }, isErr ? 5200 : 2600);
  }
  function copyText(s) {
    if (navigator.clipboard) navigator.clipboard.writeText(s).then(() => toast('已复制'), () => toast('复制失败', true));
  }
  function download(name, blob) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  }
  function saveU8(name, u8) { download(name, new Blob([u8])); }

  /* ---------------- 装载 ---------------- */
  async function openFile(file) {
    try {
      const buf = new Uint8Array(await file.arrayBuffer());
      const lower = file.name.toLowerCase();
      if (lower.endsWith('.npk')) loadPack(buf, file.name, false);
      else if (lower.endsWith('.img') || lower.endsWith('.ogg')) loadDirect(buf, file.name);
      else loadPack(buf, file.name, false);
    } catch (e) {
      toast('读取失败：' + e.message, true);
    }
  }

  function loadDirect(bytes, name) {
    const isOgg = name.toLowerCase().endsWith('.ogg');
    const npk = { count: 1, entries: [{ name, offset: 0, size: bytes.length, isOgg }], warnings: [] };
    loadPack(bytes, name, false, npk);
  }

  function loadPack(bytes, name, isDemo, fakeNpk) {
    let npk = fakeNpk;
    if (!npk) {
      try { npk = C.parseNpkIndex(bytes); }
      catch (e) { toast('不是有效的 NPK：' + e.message, true); return; }
    }
    state.bytes = bytes;
    state.npk = npk;
    state.fileName = name;
    state.fileSize = bytes.length;
    state.isDemo = !!isDemo;
    for (const e of npk.entries) e.isOgg = /\.ogg$/i.test(e.name);
    state.entries = npk.entries;
    state.imgCache.clear();
    state.frameCanvas.clear();
    state.sel = -1;
    state.img = null; state.imgEntry = null; state.entryBytes = null; state.frame = 0;
    stopPlay();
    setFilter(state.filter, true);
    renderFileChip();
    renderHeaderNote();
    if (npk.count) selectEntry(0);
    else toast('这个 NPK 里没有条目', true);
  }

  function renderFileChip() {
    const chip = $('#filechip');
    chip.hidden = false;
    chip.innerHTML = `<span class="nm" title="${esc(state.fileName)}">${esc(state.fileName)}</span>` +
      (state.isDemo ? '<span class="demo">示例</span>' : '') +
      `<span>${fmtBytes(state.fileSize)} · ${commafy(state.npk.count)} 条</span>` +
      `<button class="x" title="关闭" id="chipClose">×</button>`;
    $('#chipClose').onclick = () => closePack();
  }

  function closePack() {
    stopPlay();
    state.bytes = null; state.npk = null; state.entries = []; state.sel = -1;
    state.img = null; state.imgEntry = null; state.audioBuf = null; state.ogg = null;
    state.imgCache.clear(); state.frameCanvas.clear();
    $('#filechip').hidden = true;
    $('#entryName').textContent = '未选择条目';
    $('#entryType').textContent = '—';
    $('#entryType').className = 'type-pill';
    $('#sideFoot').textContent = '未打开文件';
    $('#frameInfo').innerHTML = '';
    $('#atlasBody').innerHTML = '';
    $('#structBody').innerHTML = '';
    $('#audioBody').innerHTML = '';
    $('#stageEmpty').hidden = false;
    $('#stageEmpty').textContent = '选择左侧条目开始查看';
    $('#btnExportRaw').disabled = true;
    $('#btnExportJson').disabled = true;
    setFilter('all', true);
    drawIdle();
  }

  function renderHeaderNote() {
    const w = state.npk.warnings || [];
    if (w.length) toast('解析提示：' + w[0], true);
  }

  /* ---------------- 左侧列表 ---------------- */
  function setFilter(f, keepPos) {
    state.filter = f;
    $$('#filters .chip').forEach(b => b.classList.toggle('active', b.dataset.filter === f));
    const counts = { all: state.entries.length, img: 0, ogg: 0 };
    for (const e of state.entries) counts[e.isOgg ? 'ogg' : 'img']++;
    $('#filters [data-filter=all] b').textContent = commafy(counts.all);
    $('#filters [data-filter=img] b').textContent = commafy(counts.img);
    $('#filters [data-filter=ogg] b').textContent = commafy(counts.ogg);
    applyFilter(keepPos);
  }

  function applyFilter(keepPos) {
    const q = state.q.toLowerCase();
    state.view = [];
    for (let i = 0; i < state.entries.length; i++) {
      const e = state.entries[i];
      if (state.filter === 'img' && e.isOgg) continue;
      if (state.filter === 'ogg' && !e.isOgg) continue;
      if (q && e.name.toLowerCase().indexOf(q) < 0) continue;
      state.view.push(i);
    }
    $('#listEmpty').hidden = state.view.length > 0 || !state.npk;
    const wrap = $('#listWrap');
    $('#listSpacer').style.height = (state.view.length * ROW_H) + 'px';
    if (!keepPos) wrap.scrollTop = 0;
    renderRows();
    const total = state.entries.length;
    $('#sideFoot').textContent = state.npk
      ? `${commafy(state.view.length)} / ${commafy(total)} 条 · 索引区 ${fmtBytes(state.npk.indexEnd || 0)}`
      : '未打开文件';
  }

  function renderRows() {
    const wrap = $('#listWrap');
    const top = wrap.scrollTop, h = wrap.clientHeight || 600;
    const start = Math.max(0, Math.floor(top / ROW_H) - 5);
    const end = Math.min(state.view.length, Math.ceil((top + h) / ROW_H) + 5);
    const rows = $('#listRows');
    let html = '';
    for (let k = start; k < end; k++) {
      const i = state.view[k];
      const e = state.entries[i];
      html += `<div class="row${i === state.sel ? ' sel' : ''}" data-i="${i}" style="top:${k * ROW_H}px" title="${esc(e.name)}">
        <span class="idx">${String(i + 1).padStart(3, '0')}</span>
        <span class="dot ${e.isOgg ? 'ogg' : 'img'}"></span>
        <div class="meta"><div class="nm">${esc(baseName(e.name))}</div><div class="dir">${esc(dirName(e.name) || ' ')}</div></div>
        <span class="sz">${fmtBytes(e.size)}</span>
      </div>`;
    }
    rows.innerHTML = html;
    rows.style.height = '0px';
  }

  function scrollToSel() {
    const k = state.view.indexOf(state.sel);
    if (k < 0) return;
    const wrap = $('#listWrap');
    const y = k * ROW_H;
    if (y < wrap.scrollTop) wrap.scrollTop = y;
    else if (y + ROW_H > wrap.scrollTop + wrap.clientHeight) wrap.scrollTop = y + ROW_H - wrap.clientHeight;
    renderRows();
  }

  /* ---------------- 选中条目 ---------------- */
  let selToken = 0;
  async function selectEntry(idx, opts) {
    if (!state.npk || idx < 0 || idx >= state.entries.length) return;
    const tok = ++selToken;
    state.sel = idx;
    const e = state.entries[idx];
    const viewIdx = state.view.indexOf(idx);
    if (viewIdx >= 0) scrollToSel(); else renderRows();
    $('#entryName').textContent = e.name;
    $('#entryName').title = e.name;
    $('#btnExportRaw').disabled = false;
    $('#btnExportJson').disabled = e.isOgg;
    stopPlay();
    state.frame = 0;
    state.structOffset = 0;
    state.structSel = -1;
    state.ogg = null; state.audioBuf = null;
    destroyAudio();

    const bytes = state.bytes.subarray(e.offset, e.offset + e.size);
    state.entryBytes = bytes;
    if (e.isOgg) {
      state.img = null; state.imgEntry = null;
      state.ogg = C.decodeOgg(bytes);
      state.oggBytes = bytes;
      state.entryBytes = bytes;
      $('#entryType').textContent = 'OGG';
      $('#entryType').className = 'type-pill ogg';
      $('#tabAudio').disabled = false;
      setTab('audio');
      drawIdle();
      $('#frameInfo').innerHTML = `<div class="card"><h5>OGG 音频</h5>
        <dl class="kv">
          <dt>条目</dt><dd>${esc(e.name)}</dd>
          <dt>大小</dt><dd>${commafy(e.size)} B</dd>
          <dt>编码</dt><dd>${esc(state.ogg.codec || '?')}</dd>
          <dt>声道</dt><dd>${state.ogg.channels || '?'}</dd>
          <dt>采样率</dt><dd>${state.ogg.sampleRate || '?'} Hz</dd>
          <dt>时长</dt><dd>${state.ogg.duration.toFixed(3)} s</dd>
          <dt>页数</dt><dd>${state.ogg.pages.length}</dd>
        </dl></div>`;
      if (tok === selToken) { renderAudioPane(); }
      return;
    }

    let img = state.imgCache.get(idx);
    if (!img) {
      try {
        img = C.parseImg(bytes);
        img.bytes = bytes;
        state.imgCache.set(idx, img);
      } catch (err) {
        if (tok !== selToken) return;
        state.img = null; state.imgEntry = null;
        $('#entryType').textContent = '?';
        $('#entryType').className = 'type-pill err';
        renderImgError(e, err);
        return;
      }
    }
    if (tok !== selToken) return;
    state.img = img;
    state.imgEntry = { entry: e, bytes, index: idx };
    state.entryBytes = bytes;
    state.frame = Math.min(state.frame, img.frames.length - 1);
    $('#entryType').textContent = 'v' + img.version;
    $('#entryType').className = 'type-pill';
    $('#tabAudio').disabled = true;
    if (state.tab === 'audio') setTab('preview');
    if (tok === selToken) {
      renderFrameInfo();
      drawPreview();
      renderAtlas();
      renderStructure();
      if (state.tab === 'compose') { compEnsureBase(); compRender(); }
    }
  }

  function renderImgError(e, err) {
    $('#frameInfo').innerHTML = `<div class="alert"><b>无法解析这个 IMG</b><br>${esc(err.message)}</div>` +
      `<div class="card"><h5>原始数据</h5><div class="hint">条目 ${esc(e.name)}（${fmtBytes(e.size)}）<br>偏移 ${hex(e.offset)}，大小 ${e.size} 字节。<br>可在“结构”页查看十六进制。</div></div>`;
    $('#atlasBody').innerHTML = `<div class="err-big"><b>无法解析</b>${esc(err.message)}</div>`;
    $('#stageEmpty').hidden = false;
    $('#stageEmpty').textContent = '这个条目无法解析';
    state.structOffset = 0;
    renderStructureError(e, err);
  }

  /* ---------------- 预览：画布 ---------------- */
  let checker = null;
  function checkerPattern(ctx) {
    if (!checker) {
      const c = document.createElement('canvas');
      c.width = c.height = 16;
      const g = c.getContext('2d');
      g.fillStyle = '#151f2f'; g.fillRect(0, 0, 16, 16);
      g.fillStyle = '#1c2940'; g.fillRect(0, 0, 8, 8); g.fillRect(8, 8, 8, 8);
      checker = c;
    }
    return ctx.createPattern(checker, 'repeat');
  }

  function stageSize() {
    const r = $('#stage').getBoundingClientRect();
    return { w: Math.max(1, Math.round(r.width)), h: Math.max(1, Math.round(r.height)) };
  }

  function setupCanvas() {
    const cv = $('#cv');
    const { w, h } = stageSize();
    cv.width = Math.round(w * dpr); cv.height = Math.round(h * dpr);
    const ctx = cv.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return { ctx, w, h };
  }

  function fillBg(ctx, w, h) {
    if (state.bg === 'light') { ctx.fillStyle = '#e8edf5'; ctx.fillRect(0, 0, w, h); return; }
    if (state.bg === 'dark') { ctx.fillStyle = '#0a111d'; ctx.fillRect(0, 0, w, h); return; }
    ctx.fillStyle = checkerPattern(ctx);
    ctx.fillRect(0, 0, w, h);
  }

  function drawIdle() {
    const { ctx, w, h } = setupCanvas();
    fillBg(ctx, w, h);
  }

  function frameCanvas(i) {
    const key = state.sel + ':' + i;
    if (state.frameCanvas.has(key)) return state.frameCanvas.get(key);
    return null;
  }

  function cacheFrameCanvas(i, dec) {
    const c = document.createElement('canvas');
    c.width = Math.max(1, dec.w); c.height = Math.max(1, dec.h);
    const g = c.getContext('2d');
    const id = g.createImageData(dec.w, dec.h);
    id.data.set(dec.rgba);
    g.putImageData(id, 0, 0);
    state.frameCanvas.set(state.sel + ':' + i, c);
    return c;
  }

  async function drawPreview() {
    const img = state.img;
    if (!img || !img.frames.length) { drawIdle(); return; }
    const mine = ++state.drawToken;
    const i = state.frame;
    let dec;
    try {
      dec = await C.decodeFrame(img, i);
    } catch (e) {
      if (mine !== state.drawToken) return;
      const { ctx, w, h } = setupCanvas();
      fillBg(ctx, w, h);
      ctx.fillStyle = '#ff8a97';
      ctx.font = '13px "Microsoft YaHei", sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText('这一帧解码失败：' + e.message, w / 2, h / 2);
      $('#stageFoot').textContent = '解码失败 · ' + e.message;
      return;
    }
    if (mine !== state.drawToken) return;
    const f = img.frames[i];
    const { ctx, w, h } = setupCanvas();
    fillBg(ctx, w, h);
    const cw = (f.canvasW > 0 ? f.canvasW : dec.w);
    const ch = (f.canvasH > 0 ? f.canvasH : dec.h);
    const useCanvasBox = state.showCanvas && cw > 0 && ch > 0;
    const minX = useCanvasBox ? Math.min(0, f.x) : f.x;
    const minY = useCanvasBox ? Math.min(0, f.y) : f.y;
    const maxX = useCanvasBox ? Math.max(cw, f.x + dec.w) : f.x + dec.w;
    const maxY = useCanvasBox ? Math.max(ch, f.y + dec.h) : f.y + dec.h;
    const pad = 24;
    let s;
    if (state.zoom === 'fit') {
      s = Math.min((w - pad * 2) / Math.max(1, maxX - minX), (h - pad * 2) / Math.max(1, maxY - minY));
      s = Math.max(0.05, Math.min(s, 8));
    } else {
      s = Math.max(0.05, Number(state.zoom) || 1);
    }
    const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    const ox = w / 2 - cx * s, oy = h / 2 - cy * s;

    if (useCanvasBox) {
      ctx.save();
      ctx.setLineDash([5, 4]);
      ctx.strokeStyle = 'rgba(247,185,85,.55)';
      ctx.lineWidth = 1;
      ctx.strokeRect(ox, oy, cw * s, ch * s);
      ctx.restore();
      ctx.fillStyle = 'rgba(247,185,85,.55)';
      ctx.font = '10px "Cascadia Mono", monospace';
      ctx.fillText(`画布 ${cw}×${ch}`, ox + 4, oy + 12);
    }
    if (state.showOrigin) {
      ctx.save();
      ctx.strokeStyle = 'rgba(61,220,151,.85)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(ox - 9, oy); ctx.lineTo(ox + 9, oy);
      ctx.moveTo(ox, oy - 9); ctx.lineTo(ox, oy + 9);
      ctx.stroke();
      ctx.fillStyle = 'rgba(61,220,151,.9)';
      ctx.beginPath(); ctx.arc(ox, oy, 2.2, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
    }
    let fc = frameCanvas(i);
    if (!fc) fc = cacheFrameCanvas(i, dec);
    ctx.imageSmoothingEnabled = s < 1;
    ctx.drawImage(fc, ox + f.x * s, oy + f.y * s, Math.max(1, dec.w * s), Math.max(1, dec.h * s));
    // 细边框，方便看清单帧边界
    ctx.strokeStyle = 'rgba(62,198,255,.28)';
    ctx.lineWidth = 1;
    ctx.strokeRect(ox + f.x * s + .5, oy + f.y * s + .5, Math.max(1, dec.w * s) - 1, Math.max(1, dec.h * s) - 1);

    const z = Math.round(s * 100);
    $('#stageEmpty').hidden = true;
    $('#stageFoot').textContent =
      `帧 ${i + 1}/${img.frames.length} · ${dec.w}×${dec.h} · 偏移 (${f.x},${f.y}) · 画布 ${cw}×${ch} · ${z}%` +
      (img.version === 5 && f.ddsIndex >= 0 ? ` · DDS#${f.ddsIndex} 裁剪 (${f.left},${f.up})-(${f.right},${f.down})` : '');
  }

  /* ---------------- 预览：播放 ---------------- */
  function setFrame(i, opts) {
    const img = state.img;
    if (!img || !img.frames.length) return;
    const n = img.frames.length;
    i = ((i % n) + n) % n;
    state.frame = i;
    $('#frameSlider').value = i;
    $('#frameInput').value = i + 1;
    if (!opts || !opts.noInspector) renderFrameInfo();
    drawPreview();
  }

  function startPlay() {
    if (!state.img || !state.img.frames.length) return;
    state.playing = true;
    $('#btnPlay').classList.add('on');
    $('#btnPlay').textContent = '❚❚';
    clearInterval(state.playTimer);
    const tick = () => {
      if (!state.playing) return;
      const n = state.img.frames.length;
      if (!n) return;
      if (!(state.frame + 1 < n) && !$('#loopChk').checked) { stopPlay(); return; }
      setFrame(state.frame + 1);
    };
    state.playTimer = setInterval(tick, 1000 / Math.max(1, Math.min(60, state.fps)));
  }
  function stopPlay() {
    state.playing = false;
    clearInterval(state.playTimer);
    const b = $('#btnPlay');
    if (b) { b.classList.remove('on'); b.textContent = '▶'; }
  }

  /* ---------------- 预览：右侧信息 ---------------- */
  function frameInfoHTML() {
    const img = state.img;
    const { entry } = state.imgEntry;
    const i = state.frame;
    const f = img.frames[i];
    const real = img.resolved[i];
    const target = real >= 0 ? img.frames[real] : null;
    const notes = state.isDemo && window.DEMO_NPK && window.DEMO_NPK.notes ? window.DEMO_NPK.notes : {};
    const note = notes[entry.name];
    const warnings = (img.warnings || []).slice(0, 3);
    const palette = img.palettes.map(p => p.length / 4);
    return `
      ${note ? `<div class="alert ok">示例：${esc(note)}</div>` : ''}
      ${warnings.length ? `<div class="alert">${warnings.map(esc).join('<br>')}</div>` : ''}
      <div class="card">
        <h5>IMG 概览</h5>
        <div class="pill-row">
          <span class="pill on">${VER_NAME[img.version] || 'v' + img.version}</span>
          <span class="pill">${commafy(img.frames.length)} 帧</span>
          ${img.dds.length ? `<span class="pill">${img.dds.length} 张贴图</span>` : ''}
          ${palette.length ? `<span class="pill">${palette.join('/')} 色</span>` : ''}
          <span class="pill">${fmtBytes(entry.size)}</span>
        </div>
        <dl class="kv">
          <dt>条目</dt><dd>${esc(entry.name)}</dd>
          <dt>文件偏移</dt><dd>${hex(entry.offset)} · ${commafy(entry.size)} B</dd>
          <dt>帧记录区</dt><dd>${hex(img.recordsStart)} → ${hex(img.recordsEnd)}</dd>
          <dt>帧体起点</dt><dd>${hex(img.bodyStart)}</dd>
          <dt>数据结尾</dt><dd>${hex(img.dataEnd)} ${img.dataEnd === entry.size ? '<span style="color:#3ddc97">✓ 对齐</span>' : `<span style="color:#ff6b7a">≠ ${entry.size}</span>`}</dd>
        </dl>
      </div>
      <div class="card">
        <h5>当前帧 <span class="pill" style="margin-left:auto">#${i + 1}</span></h5>
        <dl class="kv">
          <dt>记录偏移</dt><dd>${f.recOffset != null ? hex(f.recOffset) : '—'} · ${f.recLength}B</dd>
          <dt>类型</dt><dd class="hi">${hex(f.type)} ${TYPE_NAME[f.type] || '?'}</dd>
          <dt>压缩</dt><dd>${CMP_NAME[f.compressed] || ('0x' + f.compressed.toString(16))}</dd>
          <dt>像素尺寸</dt><dd>${f.width} × ${f.height}</dd>
          <dt>偏移 x,y</dt><dd>${f.x}, ${f.y}</dd>
          <dt>画布</dt><dd>${f.canvasW} × ${f.canvasH}</dd>
          ${f.ddsIndex >= 0 ? `<dt>DDS 索引</dt><dd class="hi">#${f.ddsIndex}</dd>` : ''}
          ${f.ddsIndex >= 0 ? `<dt>裁剪矩形</dt><dd>L${f.left} U${f.up} R${f.right} D${f.down}</dd>` : ''}
          ${f.lengthDeclared != null ? `<dt>声明长度</dt><dd>${f.lengthDeclared}B → 按几何 ${f.length}B</dd>` : ''}
          <dt>帧体</dt><dd>${f.bodyOffset >= 0 ? hex(f.bodyOffset) + ' · ' + f.bodyLength + 'B' : '无（指向帧/贴图裁剪）'}</dd>
          ${f.type === 0x11 ? `<dt>指向</dt><dd>${f.reference}${real >= 0 ? ' → 帧 ' + (real + 1) : '（越界/环）'}</dd>` : ''}
        </dl>
        ${f.truncated ? '<div class="alert" style="margin-top:8px">帧体被截断（声明长度大于可用字节）</div>' : ''}
        ${target && f.type === 0x11 ? `<div class="hint" style="margin-top:6px">实际显示的是帧 ${real + 1}（${target.width}×${target.height}）。</div>` : ''}
      </div>`;
  }

  function renderFrameInfo() {
    if (!state.img) { $('#frameInfo').innerHTML = ''; return; }
    $('#frameInfo').innerHTML = frameInfoHTML();
    const n = state.img.frames.length;
    const s = $('#frameSlider');
    s.max = Math.max(0, n - 1);
    s.value = state.frame;
    $('#frameInput').max = n;
    $('#frameInput').value = state.frame + 1;
    $('#frameTotal').textContent = '/ ' + n;
    $('#btnExportJson').disabled = false;
  }

  /* ---------------- 图集 / 切图展板 ---------------- */
  let atlasToken = 0;
  const atlasTimers = new Map();
  function stopAtlasPlay() { for (const t of atlasTimers.values()) clearInterval(t); atlasTimers.clear(); }
  function renderAtlas() {
    stopAtlasPlay();
    const body = $('#atlasBody');
    const img = state.img;
    if (!img) { body.innerHTML = '<div class="err-big">先在左侧选择一个 IMG 条目</div>'; return; }
    const tok = ++atlasToken;
    $('#atlasBadge').hidden = !img.dds.length;
    if (img.dds.length) $('#atlasBadge').textContent = img.dds.length + ' 图';
    const groups = new Map();
    for (const f of img.frames) {
      if (f.type === 0x11) continue;
      const k = f.ddsIndex >= 0 ? f.ddsIndex : -1;
      if (!groups.has(k)) groups.set(k, []);
      groups.get(k).push(f.index);
    }
    const ddsIdx = [...groups.keys()].filter(k => k >= 0).sort((a, b) => a - b);
    const inline = groups.get(-1) || [];

    if (!ddsIdx.length) {
      body.innerHTML = `
        <div class="section-title"><h3>这张 IMG 没有共享大图</h3>
          <span class="sub">${VER_NAME[img.version] || 'v' + img.version} · 每帧独立存放 ${commafy(img.frames.length)} 帧</span></div>
        <div class="card"><div class="hint">v2 / v1 的帧是一帧一块像素数据，没有“从大图里切”的概念。下面按帧顺序铺开，点任意一帧可回到预览。</div></div>
        <div class="sheet" id="contactSheet"></div>
        <div class="hint" id="sheetNote" style="margin-top:10px;color:#5c708d"></div>`;
      contactSheet(img, tok);
      return;
    }

    let html = `<div class="section-title"><h3>图集展板</h3>
      <span class="sub">${commafy(img.frames.length)} 帧 · ${img.dds.length} 张贴图 · ${fmtBytes(state.imgEntry.entry.size)}</span></div>
      <div class="card"><div class="hint">每张大图上的彩色框 = 一帧的裁剪矩形（左上/右下坐标 + 宽高）。鼠标悬停看是哪一帧，点击直接跳到预览。
      ${inline.length ? `另有 <b>${inline.length}</b> 帧不走贴图（独立帧体），列在最后。` : ''}</div></div>`;
    for (const di of ddsIdx) {
      const frames = groups.get(di);
      html += `<div class="card atlas-card" data-dds="${di}">
        <h5>贴图 #${di} <span class="pill" id="ddsMeta${di}" style="margin-left:8px">解码中…</span>
          <button class="btn sm" id="atlasPlay${di}" style="margin-left:auto">▶ 逐帧看裁剪</button></h5>
        <div class="atlas-view" id="atlasView${di}">
          <canvas id="atlasCv${di}"></canvas>
          <div class="atlas-hover" id="atlasTip${di}" hidden></div>
        </div>
        <div class="hint" id="atlasNow${di}" style="margin-top:6px"></div>
        <div class="atlas-tiles tile-grid" id="atlasTiles${di}"></div>
      </div>`;
    }
    if (inline.length) {
      html += `<div class="section-title"><h3>独立帧（不属于任何贴图）</h3><span class="sub">${inline.length} 帧</span></div>
        <div class="sheet" id="inlineSheet"></div>`;
    }
    body.innerHTML = html;
    for (const di of ddsIdx) drawDdsCard(img, di, groups.get(di), tok);
    if (inline.length) drawFrameSheet($('#inlineSheet'), img, inline, tok);
    if (!img.dds.length) $('#atlasBadge').hidden = true;
  }

  async function drawDdsCard(img, di, frameIdxs, tok) {
    const rec = img.dds[di];
    const tex = await C.getDdsTexture(img, di);
    if (tok !== atlasToken) return;
    const meta = $(`#ddsMeta${di}`);
    if (!meta) return;
    if (!tex.rgba) {
      meta.textContent = '解码失败';
      $(`#atlasView${di}`).innerHTML = `<div class="err-big"><b>贴图解码失败</b>${esc(tex.error || '未知错误')}</div>`;
      return;
    }
    const w = tex.decodedW, h = tex.decodedH;
    meta.textContent = `${w}×${h} · ${tex.decodedFormat} · ${fmtBytes(rec.length)} → ${fmtBytes(rec.fullLength || 0)}`;
    const cv = $(`#atlasCv${di}`);
    cv.width = w; cv.height = h;
    const availW = (($(`#atlasView${di}`).clientWidth) || 900) - 16;
    const zs = Math.max(1, Math.min(8, Math.round(availW / Math.max(1, w) * 2) / 2));
    cv.style.width = Math.max(8, Math.round(w * zs)) + 'px';
    const g = cv.getContext('2d');
    const base = g.createImageData(w, h);
    base.data.set(tex.rgba);
    const rects = frameIdxs.map(fi => {
      const f = img.frames[fi];
      return { fi, l: f.left, u: f.up, r: f.right, d: f.down, w: f.right - f.left, h: f.down - f.up };
    });
    const draw = (hover) => {
      g.putImageData(base, 0, 0);
      // 棋盘底，方便看透明
      g.save();
      const whole = rects.length === 1 && rects[0].l === 0 && rects[0].u === 0 &&
        rects[0].r >= w && rects[0].d >= h;
      for (const r of rects) {
        const col = COLORS[r.fi % COLORS.length];
        if (!whole) {
          g.fillStyle = col + '14';
          g.fillRect(r.l, r.u, r.w, r.h);
        }
        g.strokeStyle = hover === r.fi ? '#ffffff' : col;
        g.lineWidth = hover === r.fi ? 2 : 1;
        g.strokeRect(r.l + .5, r.u + .5, Math.max(0, r.w - 1), Math.max(0, r.h - 1));
      }
      g.restore();
    };
    draw(-1);
    const nowLbl = $(`#atlasNow${di}`);
    const playBtn = $(`#atlasPlay${di}`);
    let k = 0, timer = 0;
    const showAt = (fi) => {
      draw(fi);
      const f = img.frames[fi];
      nowLbl.textContent = `帧 #${fi + 1} · 裁剪 (${f.left},${f.up})-(${f.right},${f.down}) · ${f.width}×${f.height}`;
    };
    playBtn.onclick = () => {
      if (timer) { clearInterval(timer); timer = 0; atlasTimers.delete(di); playBtn.textContent = '▶ 逐帧看裁剪'; return; }
      playBtn.textContent = '⏸ 暂停';
      timer = setInterval(() => {
        k = (k + 1) % frameIdxs.length;
        showAt(frameIdxs[k]);
      }, Math.round(1000 / (state.fps || 8)));
      atlasTimers.set(di, timer);
    };
    const view = $(`#atlasView${di}`);
    const tip = $(`#atlasTip${di}`);
    let last = -2;
    view.addEventListener('mousemove', (ev) => {
      const rc = cv.getBoundingClientRect();
      const x = (ev.clientX - rc.left) / rc.width * w;
      const y = (ev.clientY - rc.top) / rc.height * h;
      let hit = -1, bestArea = Infinity;
      for (const r of rects) {
        if (x >= r.l && x < r.r && y >= r.u && y < r.d) {
          const a = r.w * r.h;
          if (a < bestArea) { bestArea = a; hit = r.fi; }
        }
      }
      if (hit !== last) { last = hit; draw(hit); }
      if (hit >= 0) {
        const f = img.frames[hit];
        tip.hidden = false;
        tip.textContent = `帧 #${hit + 1} · ${f.width}×${f.height} @ (${f.left},${f.up})-(${f.right},${f.down})`;
        const vr = view.getBoundingClientRect();
        tip.style.left = Math.min(vr.width - tip.offsetWidth - 6, ev.clientX - vr.left) + 'px';
        tip.style.top = Math.min(vr.height - tip.offsetHeight - 6, ev.clientY - vr.top) + 'px';
      } else tip.hidden = true;
    });
    view.addEventListener('mouseleave', () => { tip.hidden = true; if (last !== -1) { last = -1; draw(-1); } });
    view.addEventListener('click', (ev) => {
      const rc = cv.getBoundingClientRect();
      const x = (ev.clientX - rc.left) / rc.width * w;
      const y = (ev.clientY - rc.top) / rc.height * h;
      let hit = -1, bestArea = Infinity;
      for (const r of rects) {
        if (x >= r.l && x < r.r && y >= r.u && y < r.d) {
          const a = r.w * r.h;
          if (a < bestArea) { bestArea = a; hit = r.fi; }
        }
      }
      if (hit >= 0) { setTab('preview'); setFrame(hit); }
    });

    // 去重裁剪块
    const uniq = new Map();
    for (const r of rects) {
      const k = `${r.l},${r.u},${r.r},${r.d}`;
      if (!uniq.has(k)) uniq.set(k, { ...r, frames: [] });
      uniq.get(k).frames.push(r.fi);
    }
    const list = [...uniq.values()].sort((a, b) => b.frames.length - a.frames.length || a.fi - b.fi);
    const box = $(`#atlasTiles${di}`);
    const frag = document.createDocumentFragment();
    const off = document.createElement('canvas');
    off.width = w; off.height = h;
    off.getContext('2d').putImageData(base, 0, 0);
    for (const u of list.slice(0, 400)) {
      const tw = Math.max(1, u.w), th = Math.max(1, u.h);
      const c = document.createElement('canvas');
      c.width = tw; c.height = th;
      const cg = c.getContext('2d');
      cg.imageSmoothingEnabled = false;
      cg.drawImage(off, u.l, u.u, tw, th, 0, 0, tw, th);
      const tile = document.createElement('div');
      tile.className = 'tile';
      tile.title = `帧 ${u.frames.slice(0, 12).map(i => '#' + (i + 1)).join(' ')}${u.frames.length > 12 ? ' …' : ''}`;
      tile.appendChild(c);
      const n1 = document.createElement('div'); n1.className = 't-name';
      n1.textContent = `(${u.l},${u.u}) ${u.w}×${u.h}`;
      const n2 = document.createElement('div'); n2.className = 't-sub';
      n2.textContent = `× ${u.frames.length} 帧`;
      tile.appendChild(n1); tile.appendChild(n2);
      tile.onclick = () => { setTab('preview'); setFrame(u.frames[0]); };
      frag.appendChild(tile);
    }
    box.innerHTML = '';
    box.appendChild(frag);
    if (list.length > 400) box.insertAdjacentHTML('beforeend', `<div class="hint">只显示前 400 个裁剪块（共 ${list.length} 个）</div>`);
  }

  async function contactSheet(img, tok) {
    const box = $('#contactSheet');
    const note = $('#sheetNote');
    const max = Math.min(img.frames.length, 400);
    for (let i = 0; i < max; i++) {
      if (tok !== atlasToken) return;
      let dec;
      try { dec = await C.decodeFrame(img, i); } catch { continue; }
      const scale = Math.min(64 / Math.max(1, dec.w), 64 / Math.max(1, dec.h), 1);
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(dec.w * scale)); c.height = Math.max(1, Math.round(dec.h * scale));
      const g = c.getContext('2d');
      const id = g.createImageData(dec.w, dec.h); id.data.set(dec.rgba);
      const tmp = document.createElement('canvas'); tmp.width = dec.w; tmp.height = dec.h;
      tmp.getContext('2d').putImageData(id, 0, 0);
      g.imageSmoothingEnabled = false;
      g.drawImage(tmp, 0, 0, c.width, c.height);
      const tile = document.createElement('div');
      tile.className = 'tile';
      tile.appendChild(c);
      const n = document.createElement('div'); n.className = 't-name'; n.textContent = '#' + (i + 1);
      tile.appendChild(n);
      tile.onclick = () => { setTab('preview'); setFrame(i); };
      box.appendChild(tile);
      if (i % 40 === 0) await new Promise(r => setTimeout(r, 0));
    }
    note.textContent = img.frames.length > max ? `只铺了前 ${max} 帧（共 ${img.frames.length} 帧）` : '';
  }

  async function drawFrameSheet(box, img, idxs, tok) {
    const max = Math.min(idxs.length, 200);
    for (let k = 0; k < max; k++) {
      if (tok !== atlasToken) return;
      const i = idxs[k];
      let dec;
      try { dec = await C.decodeFrame(img, i); } catch { continue; }
      const scale = Math.min(60 / Math.max(1, dec.w), 60 / Math.max(1, dec.h), 1);
      const tmp = document.createElement('canvas'); tmp.width = dec.w; tmp.height = dec.h;
      const tg = tmp.getContext('2d');
      const id = tg.createImageData(dec.w, dec.h); id.data.set(dec.rgba); tg.putImageData(id, 0, 0);
      const c = document.createElement('canvas');
      c.width = Math.max(1, Math.round(dec.w * scale)); c.height = Math.max(1, Math.round(dec.h * scale));
      const g = c.getContext('2d'); g.imageSmoothingEnabled = false;
      g.drawImage(tmp, 0, 0, c.width, c.height);
      const tile = document.createElement('div'); tile.className = 'tile';
      tile.appendChild(c);
      const n = document.createElement('div'); n.className = 't-name'; n.textContent = '#' + (i + 1);
      tile.appendChild(n);
      tile.onclick = () => { setTab('preview'); setFrame(i); };
      box.appendChild(tile);
    }
  }

  /* ---------------- 结构展板 ---------------- */
  function renderStructure() {
    const body = $('#structBody');
    if (!state.img || !state.imgEntry) { body.innerHTML = '<div class="err-big">先在左侧选择一个条目</div>'; return; }
    const img = state.img;
    const e = state.imgEntry.entry;
    const nFrames = img.frames.length;
    const palette = img.palettes;
    let html = `<div class="struct-grid">
      <div class="card">
        <h5>NPK 容器</h5>
        <dl class="kv">
          <dt>文件</dt><dd>${esc(state.fileName)}</dd>
          <dt>条目</dt><dd>${esc(e.name)}</dd>
          <dt>索引位置</dt><dd>${hex(20 + state.sel * 264)}（20 + #${state.sel}×264）</dd>
          <dt>数据偏移</dt><dd>${hex(e.offset)}</dd>
          <dt>数据大小</dt><dd>${commafy(e.size)} B</dd>
        </dl>
      </div>
      <div class="card">
        <h5>IMG 头（32 字节）</h5>
        <dl class="kv">
          <dt>magic</dt><dd>${img.v1 ? 'Neople Image File\\0' : 'Neople Img File\\0'}</dd>
          <dt>版本</dt><dd class="hi">v${img.version} · ${VER_NAME[img.version] || ''}</dd>
          <dt>帧数</dt><dd>${commafy(nFrames)}</dd>
          <dt>tableLength</dt><dd>${img.v1 ? '（v1 无此字段）' : commafy(img.tableLength) + ' B'}</dd>
          <dt>记录区</dt><dd>${hex(img.recordsStart)} → ${hex(img.recordsEnd)}</dd>
          <dt>走完长度</dt><dd>${hex(img.dataEnd)} / ${commafy(e.size)} ${img.dataEnd === e.size ? '✓' : '✗'}</dd>
        </dl>
      </div>
    </div>`;

    html += `<div class="card" style="margin-top:12px">
      <h5>字节分区</h5>
      <div class="bytemap">` +
      (img.regions || []).map(r => `<div class="seg" data-off="${r.start}" title="${esc(r.label)} · ${hex(r.start)} → ${hex(r.end)} · ${commafy(r.end - r.start)} B" style="flex:${Math.max(1, r.end - r.start)};background:${r.color};min-width:4px"></div>`).join('') +
      `</div><div class="legend">` +
      (img.regions || []).map(r => `<span><i style="background:${r.color}"></i>${esc(r.label)} <b style="color:#5c708d">${fmtBytes(r.end - r.start)}</b></span>`).join('') +
      `</div></div>`;

    if (img.dds.length) {
      html += `<div class="section-title"><h3>DDS 贴图表</h3><span class="sub">${img.dds.length} 项 · 每项 28 字节</span></div>
      <div class="table-wrap" style="max-height:none"><table class="data"><thead><tr>
        <th>#</th><th>pixelFormat</th><th>尺寸</th><th>fullLength</th><th>length</th><th>数据偏移</th><th>解码</th></tr></thead><tbody>` +
        img.dds.map(d => `<tr><td>${d.index}</td><td>${hex(d.pixelFormat)}</td><td>${d.width}×${d.height}</td>
          <td>${commafy(d.fullLength)}</td><td>${commafy(d.length)}</td><td>${hex(d.rawOffset)}</td>
          <td>${d.error ? '<span style="color:#ff6b7a">' + esc(d.error) + '</span>' : (d.rgba ? esc(d.decodedFormat || 'ok') : '按需')}</td></tr>`).join('') +
        `</tbody></table></div>`;
    }

    if (palette.some(p => p.length >= 4)) {
      html += `<div class="section-title" style="margin-top:14px"><h3>调色板</h3><span class="sub">${palette.map(p => (p.length / 4) + ' 色').join(' / ')}</span></div>
        <div class="card"><div style="display:flex;flex-wrap:wrap;gap:4px">` +
        palette.map((p, pi) => Array.from({ length: Math.min(p.length / 4, 256) }).map((_, i) => {
          const r = p[i * 4], g = p[i * 4 + 1], b = p[i * 4 + 2], a = p[i * 4 + 3];
          return `<span title="组${pi} #${i} · rgba(${r},${g},${b},${a})" style="width:22px;height:22px;border-radius:4px;border:1px solid #2b3f5e;background:rgba(${r},${g},${b},${a / 255})"></span>`;
        }).join('')).join('') +
        `</div></div>`;
    }

    html += `<div class="section-title" style="margin-top:14px"><h3>帧记录</h3>
      <span class="sub">${commafy(nFrames)} 条 · 点击行可联动预览与十六进制</span></div>
      <div class="table-wrap" id="frameTableWrap"><table class="data" id="frameTable"><thead><tr>
        <th>#</th><th>类型</th><th>压缩</th><th>像素</th><th>x,y</th><th>画布</th><th>裁剪 L,U,R,D</th><th>记录</th><th>帧体</th><th>长度</th><th>DDS</th>
      </tr></thead><tbody>` +
      img.frames.map(f => `<tr data-f="${f.index}" class="${f.index === state.frame ? 'sel' : ''}">
        <td class="hi">${f.index + 1}</td>
        <td title="${TYPE_NAME[f.type] || ''}">${hex(f.type)}</td>
        <td>${CMP_NAME[f.compressed] || f.compressed}</td>
        <td>${f.width}×${f.height}</td>
        <td>${f.x},${f.y}</td>
        <td>${f.canvasW}×${f.canvasH}</td>
        <td>${f.ddsIndex >= 0 ? `${f.left},${f.up},${f.right},${f.down}` : '—'}</td>
        <td>${hex(f.recOffset)}</td>
        <td>${f.bodyOffset >= 0 ? hex(f.bodyOffset) : '—'}</td>
        <td>${f.ddsIndex >= 0 ? '—' : f.length}</td>
        <td>${f.ddsIndex >= 0 ? '#' + f.ddsIndex : '—'}</td>
      </tr>`).join('') +
      `</tbody></table></div>`;

    html += `<div class="section-title" style="margin-top:16px"><h3>十六进制</h3><span class="sub">条目内偏移（从该条目起点算）</span></div>
      <div class="hexbar">
        <button class="btn sm" id="hexPrev">◀ 前 256B</button>
        <input type="number" id="hexGo" min="0" step="16" value="${state.structOffset}">
        <button class="btn sm" id="hexJumpEntry">条目开头</button>
        <button class="btn sm" id="hexJumpFrame">当前帧记录</button>
        <button class="btn sm" id="hexJumpBody">当前帧体</button>
        <button class="btn sm" id="hexNext">后 256B ▶</button>
      </div>
      <div class="hex" id="hexBox"></div>`;

    body.innerHTML = html;
    $$('#structBody .seg').forEach(el => el.onclick = () => { state.structOffset = +el.dataset.off; renderHex(); $('#hexGo').value = state.structOffset; });
    $$('#frameTable tbody tr').forEach(tr => {
      tr.onclick = () => {
        const i = +tr.dataset.f;
        state.frame = i;
        setFrame(i);
        $$('#frameTable tbody tr').forEach(x => x.classList.toggle('sel', x === tr));
        state.structOffset = state.img.frames[i].recOffset;
        $('#hexGo').value = state.structOffset;
        renderHex();
        $('#frameTableWrap').scrollTop = Math.max(0, tr.offsetTop - 90);
      };
    });
    $('#hexPrev').onclick = () => { state.structOffset = Math.max(0, state.structOffset - 256); $('#hexGo').value = state.structOffset; renderHex(); };
    $('#hexNext').onclick = () => { state.structOffset = Math.min(hexLen() - 1, state.structOffset + 256); $('#hexGo').value = state.structOffset; renderHex(); };
    $('#hexGo').onchange = (ev) => { state.structOffset = Math.max(0, Math.min(hexLen() - 1, +ev.target.value || 0)); renderHex(); };
    $('#hexJumpEntry').onclick = () => { state.structOffset = 0; $('#hexGo').value = 0; renderHex(); };
    $('#hexJumpFrame').onclick = () => { const f = state.img.frames[state.frame]; if (f) { state.structOffset = f.recOffset; $('#hexGo').value = state.structOffset; renderHex(); } };
    $('#hexJumpBody').onclick = () => { const f = state.img.frames[state.frame]; if (f && f.bodyOffset >= 0) { state.structOffset = f.bodyOffset; $('#hexGo').value = state.structOffset; renderHex(); } };
    renderHex();
  }

  function renderStructureError(e, err) {
    $('#structBody').innerHTML = `<div class="card"><h5>无法解析 IMG</h5><div class="hint">${esc(err.message)}</div></div>
      <div class="hexbar"><button class="btn sm" id="hexPrev">◀</button><span class="sub">偏移 ${hex(e.offset)}</span><button class="btn sm" id="hexNext">▶</button></div>
      <div class="hex" id="hexBox"></div>`;
    state.structOffset = 0;
    $('#hexPrev').onclick = () => { state.structOffset = Math.max(0, state.structOffset - 256); renderHex(); };
    $('#hexNext').onclick = () => { state.structOffset = Math.min(hexLen() - 1, state.structOffset + 256); renderHex(); };
    renderHex();
  }

  function hexLen() { const b = state.entryBytes || state.bytes; return b ? b.length : 0; }
  function renderHex(boxSel) {
    const box = $(boxSel || '#hexBox');
    if (!box) return;
    const bytes = state.entryBytes || state.bytes;
    if (!bytes) { box.textContent = ''; return; }
    const start = Math.max(0, Math.min(bytes.length - 1, state.structOffset));
    const end = Math.min(bytes.length, start + 512);
    const img = state.img;
    const hl = [];
    if (img) {
      const f = img.frames[state.frame];
      if (f) {
        hl.push([f.recOffset, f.recOffset + f.recLength]);
        if (f.bodyOffset >= 0) hl.push([f.bodyOffset, f.bodyOffset + Math.min(f.bodyLength, 4096)]);
      }
      for (const d of img.dds) if (d.rawOffset >= 0) hl.push([d.rawOffset, d.rawOffset + Math.min(d.rawLength, 4096)]);
    }
    const inHL = (o) => hl.some(([a, b]) => o >= a && o < b);
    let html = '';
    for (let row = start; row < end; row += 16) {
      let hx = '', as = '';
      for (let k = 0; k < 16; k++) {
        const o = row + k;
        if (o < end) {
          const b = bytes[o];
          hx += `<span class="b${inHL(o) ? ' hl' : ''}">${b.toString(16).padStart(2, '0')}</span> `;
          as += `<span class="${inHL(o) ? 'hl2' : ''}">${b >= 32 && b < 127 ? esc(String.fromCharCode(b)) : '.'}</span>`;
        } else { hx += '   '; as += ' '; }
      }
      html += `<div><span class="off">${row.toString(16).padStart(8, '0')}</span>${hx}<span class="asc">${as}</span></div>`;
    }
    box.innerHTML = html;
  }

  /* ---------------- 音频展板 ---------------- */
  let audioCtx = null;
  let audioEl = null;
  function ensureAudioEl() {
    if (!audioEl) {
      audioEl = document.createElement('audio');
      audioEl.preload = 'auto';
      document.body.appendChild(audioEl);
    }
    return audioEl;
  }
  function destroyAudio() {
    if (audioEl) { audioEl.pause(); audioEl.removeAttribute('src'); audioEl.load(); }
    if (state.audioUrl) { URL.revokeObjectURL(state.audioUrl); state.audioUrl = ''; }
  }

  function renderAudioPane() {
    const body = $('#audioBody');
    const ogg = state.ogg;
    if (!ogg) { body.innerHTML = '<div class="err-big">选择一个 OGG 条目</div>'; return; }
    const e = state.entries[state.sel];
    body.innerHTML = `
      <div class="section-title"><h3>${esc(baseName(e.name))}</h3><span class="sub">${esc(e.name)}</span></div>
      <div class="card">
        <div class="meta-row">
          <span class="m">编码<b>${esc(ogg.codec || '?')}</b></span>
          <span class="m">声道<b>${ogg.channels || '?'}</b></span>
          <span class="m">采样率<b>${ogg.sampleRate ? ogg.sampleRate + ' Hz' : '?'}</b></span>
          <span class="m">时长<b>${ogg.duration.toFixed(3)} s</b></span>
          <span class="m">码率<b>${ogg.bitrateNominal ? Math.round(ogg.bitrateNominal / 1000) + ' kbps' : '?'}</b></span>
          <span class="m">页数<b>${ogg.pages.length}</b></span>
          <span class="m">大小<b>${fmtBytes(e.size)}</b></span>
        </div>
        <div class="wave-box"><canvas id="wave" width="1200" height="130"></canvas></div>
        <div class="audio-controls">
          <button class="icon-btn play" id="audPlay">▶</button>
          <span class="time" id="audTime">0:00 / ${fmtTime(ogg.duration)}</span>
          <input type="range" id="audSeek" min="0" max="1000" value="0">
          <button class="btn sm" id="audExport">导出 .ogg</button>
        </div>
        <div class="hint" id="audioNote" style="margin-top:8px"></div>
      </div>
      <div class="section-title"><h3>Ogg 页表</h3><span class="sub">每页 27B 头 + 段表 + 数据</span></div>
      <div class="table-wrap" style="max-height:260px"><table class="data"><thead><tr>
        <th>#</th><th>偏移</th><th>granule</th><th>serial</th><th>seq</th><th>段数</th><th>字节</th></tr></thead><tbody>` +
        ogg.pages.map((p, i) => `<tr><td>${i}</td><td>${hex(p.offset)}</td><td>${p.granule}</td><td>${p.serial}</td><td>${p.seq}</td><td>${p.segs}</td><td>${commafy(p.size)}</td></tr>`).join('') +
        `</tbody></table></div>
      <div class="section-title"><h3>十六进制</h3><span class="sub">从条目起点开始 512 字节</span></div><div class="hex" id="hexBoxA"></div>`;
    const el = ensureAudioEl();
    destroyAudio();
    const blob = new Blob([state.oggBytes], { type: 'audio/ogg' });
    state.audioUrl = URL.createObjectURL(blob);
    el.src = state.audioUrl;
    el.loop = false;
    $('#audPlay').onclick = toggleAudio;
    $('#audSeek').oninput = (ev) => { if (el.duration) el.currentTime = (ev.target.value / 1000) * el.duration; };
    $('#audExport').onclick = () => saveU8(baseName(e.name), state.oggBytes);
    el.onloadedmetadata = () => { $('#audTime').textContent = '0:00 / ' + fmtTime(el.duration); };
    el.ontimeupdate = () => {
      if (!el.duration) return;
      $('#audSeek').value = Math.round(el.currentTime / el.duration * 1000);
      $('#audTime').textContent = fmtTime(el.currentTime) + ' / ' + fmtTime(el.duration);
    };
    el.onended = () => { $('#audPlay').textContent = '▶'; $('#audPlay').classList.remove('on'); };
    $('#audPlay').textContent = '▶';
    if (state.oggBytes) { state.structOffset = 0; renderHex('#hexBoxA'); }

    const drawPlaceholder = () => {
      const c = $('#wave'); if (!c) return;
      const g = c.getContext('2d');
      g.clearRect(0, 0, c.width, c.height);
      g.fillStyle = '#12243a';
      g.fillRect(0, c.height / 2 - 1, c.width, 2);
      $('#audioNote').textContent = '浏览器无法解码这个 ogg（波形/播放不可用），但页表与原始字节仍可查看与导出。';
    };
    try {
      audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
      const ab = state.oggBytes.slice().buffer;
      audioCtx.decodeAudioData(ab).then(buf => {
        if (state.sel < 0 || !state.entries[state.sel].isOgg) return;
        state.audioBuf = buf;
        drawWave(buf);
        $('#audioNote').textContent = `解码成功：${buf.numberOfChannels} 声道 · ${ogg.duration.toFixed(3)} s · ${commafy(buf.length)} 采样点（WebAudio 已重采样到 ${buf.sampleRate} Hz）`;
      }).catch(() => drawPlaceholder());
    } catch { drawPlaceholder(); }
    drawWave(null);
  }

  function fmtTime(s) {
    if (!isFinite(s)) return '0:00';
    const m = Math.floor(s / 60);
    const r = s - m * 60;
    const sec = (s < 10) ? r.toFixed(1).padStart(4, '0') : String(Math.floor(r)).padStart(2, '0');
    return m + ':' + sec;
  }

  function drawWave(buf) {
    const c = $('#wave');
    if (!c) return;
    const g = c.getContext('2d');
    const W = c.width, H = c.height;
    g.clearRect(0, 0, W, H);
    g.fillStyle = '#070e18'; g.fillRect(0, 0, W, H);
    if (!buf) return;
    const chs = [];
    for (let i = 0; i < buf.numberOfChannels; i++) chs.push(buf.getChannelData(i));
    const n = buf.length;
    const step = Math.max(1, Math.floor(n / W));
    g.strokeStyle = '#3ec6ff';
    g.globalAlpha = .9;
    g.beginPath();
    for (let x = 0; x < W; x++) {
      let lo = 0, hi = 0;
      for (let k = 0; k < step; k++) {
        const s = Math.floor(x * n / W) + k;
        if (s >= n) break;
        let v = 0;
        for (const ch of chs) v += ch[s];
        v /= chs.length;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      g.moveTo(x + .5, H / 2 - hi * H / 2);
      g.lineTo(x + .5, H / 2 - lo * H / 2 + .6);
    }
    g.stroke();
    g.globalAlpha = 1;
    g.strokeStyle = 'rgba(255,255,255,.08)';
    g.beginPath(); g.moveTo(0, H / 2); g.lineTo(W, H / 2); g.stroke();
    c.onclick = (ev) => {
      if (!audioEl || !audioEl.duration) return;
      const r = c.getBoundingClientRect();
      audioEl.currentTime = Math.max(0, Math.min(1, (ev.clientX - r.left) / r.width)) * audioEl.duration;
    };
  }

  function toggleAudio() {
    const el = ensureAudioEl();
    if (!state.audioUrl) return;
    if (el.paused) {
      el.play().then(() => { $('#audPlay').textContent = '❚❚'; $('#audPlay').classList.add('on'); })
        .catch(e => toast('播放失败：' + e.message, true));
    } else {
      el.pause();
      $('#audPlay').textContent = '▶';
      $('#audPlay').classList.remove('on');
    }
  }

  /* ---------------- Tab / 工具栏 ---------------- */
  function setTab(name) {
    if (name !== 'atlas') stopAtlasPlay();
    if (name === 'audio' && $('#tabAudio').disabled) name = 'preview';
    state.tab = name;
    $$('#tabs button').forEach(b => b.classList.toggle('active', b.dataset.tab === name));
    for (const t of ['preview', 'atlas', 'structure', 'audio', 'compose']) {
      const pane = $('#pane-' + t);
      if (pane) pane.hidden = (t !== name);
    }
    if (name === 'preview') drawPreview();
    if (name === 'audio' && state.ogg && !$('#audioBody').firstChild) renderAudioPane();
    if (name === 'compose') { compEnsureBase(); compRender(); }
  }

  function wirePreview() {
    $('#btnPrev').onclick = () => { stopPlay(); setFrame(state.frame - 1); };
    $('#btnNext').onclick = () => { stopPlay(); setFrame(state.frame + 1); };
    $('#btnPlay').onclick = () => { state.playing ? stopPlay() : startPlay(); };
    $('#frameSlider').oninput = (ev) => { stopPlay(); setFrame(+ev.target.value); };
    $('#frameInput').onchange = (ev) => {
      const n = state.img ? state.img.frames.length : 1;
      let v = Math.max(1, Math.min(n, +ev.target.value || 1));
      stopPlay(); setFrame(v - 1);
    };
    $('#fpsInput').onchange = (ev) => {
      state.fps = Math.max(1, Math.min(60, +ev.target.value || 8));
      ev.target.value = state.fps;
      if (state.playing) startPlay();
    };
    $('#bgSel').onchange = (ev) => { state.bg = ev.target.value; drawPreview(); };
    $('#zoomSel').onchange = (ev) => { state.zoom = ev.target.value; drawPreview(); };
    $('#canvasChk').onchange = (ev) => { state.showCanvas = ev.target.checked; drawPreview(); };
    $('#originChk').onchange = (ev) => { state.showOrigin = ev.target.checked; drawPreview(); };
  }

  /* ---------------- 导出 ---------------- */
  function exportRaw() {
    if (!state.imgEntry) return;
    const e = state.imgEntry.entry;
    saveU8(baseName(e.name), state.bytes.subarray(e.offset, e.offset + e.size));
  }
  function exportJson() {
    const img = state.img;
    if (!img) return;
    const meta = {
      npk: state.fileName,
      entry: state.imgEntry.entry,
      version: img.version,
      frameCount: img.frames.length,
      tableLength: img.tableLength,
      palettes: img.palettes.map(p => Array.from(p)),
      dds: img.dds.map(d => ({ index: d.index, pixelFormat: d.pixelFormat, width: d.width, height: d.height, fullLength: d.fullLength, length: d.length, offset: d.rawOffset, format: d.decodedFormat || null })),
      regions: img.regions,
      frames: img.frames,
    };
    download(baseName(state.imgEntry.entry.name) + '.json', new Blob([JSON.stringify(meta, null, 2)], { type: 'application/json' }));
  }

  /* ---------------- 弹窗 ---------------- */
  function showModal(title, html, onMount) {
    $('#modalTitle').textContent = title;
    $('#modalBody').innerHTML = html;
    $('#overlay').hidden = false;
    if (onMount) onMount($('#modalBody'));
  }
  function closeModal() { $('#overlay').hidden = true; }

  function showHelp() {
    showModal('使用说明 / 快捷键', `
      <div class="help-grid">
        <div>
          <h4>能打开什么</h4>
          <ul>
            <li><b>.npk</b>：DNF ImagePacks2 / SoundPacks 包（v1–v5 全部条目）</li>
            <li><b>.img</b>：单个 IMG 文件，直接查看</li>
            <li><b>.ogg</b>：单个音频文件，直接播放</li>
            <li>文件夹：一次列出其中所有 .npk 供选择</li>
          </ul>
          <h4 style="margin-top:12px">五个展板</h4>
          <ul>
            <li><b>预览</b>：逐帧播放；画出画布框、原点、帧偏移；右侧是当前帧的原始字段</li>
            <li><b>拼装 · 导出</b>：当前 IMG 当底层，可再叠加本包/外部 IMG 图层；导出精灵表 PNG + JSON 或 APNG 动图</li>
            <li><b>图集 · 切图</b>：v5 共享贴图全图 + 每帧裁剪框 + 去重后的裁剪块清单；非共享格式则铺开全部帧</li>
            <li><b>结构</b>：字节分区条、DDS 表、调色板、帧记录表、十六进制</li>
            <li><b>音频</b>：波形、播放、Ogg 页表</li>
          </ul>
        </div>
        <div>
          <h4>快捷键</h4>
          <ul>
            <li><kbd>←</kbd> / <kbd>→</kbd> 上一帧 / 下一帧</li>
            <li><kbd>空格</kbd> 播放 / 暂停</li>
            <li><kbd>F</kbd> 适应窗口，<kbd>1</kbd>–<kbd>5</kbd> 切展板</li>
            <li><kbd>Esc</kbd> 关闭弹窗</li>
          </ul>
          <h4 style="margin-top:12px">说明</h4>
          <ul>
            <li>画布框（黄色虚线）是 frameWidth×frameHeight；绿色十字是角色原点；图片按 x/y 偏移放置</li>
            <li>像素按最近邻放大；缩小时才做平滑</li>
            <li>v4 的未压缩 0x0E 帧按 ARGB1555 解析（与 Python 参考实现不同，已用 60 张头像对齐验证）</li>
            <li>所有解析都在浏览器本地完成，不上传任何文件</li>
          </ul>
        </div>
      </div>`);
  }

  function showNpkPicker(files) {
    const list = files.filter(f => /\.npk$/i.test(f.name)).sort((a, b) => a.name.localeCompare(b.name));
    showModal(`选择 NPK（${list.length} 个）`, `
      <div class="search" style="margin-bottom:10px"><input id="pickSearch" placeholder="过滤文件名…" style="width:100%"></div>
      <div class="npk-list" id="pickList"></div>`, (body) => {
      const render = (q) => {
        const arr = list.filter(f => !q || f.name.toLowerCase().includes(q));
        body.querySelector('#pickList').innerHTML = arr.slice(0, 300).map((f, i) =>
          `<div class="npk-item" data-pick="${list.indexOf(f)}"><span class="nm">${esc(f.webkitRelativePath || f.name)}</span><span class="sz">${fmtBytes(f.size)}</span></div>`).join('') ||
          '<div class="hint" style="padding:20px;text-align:center">没有匹配</div>';
        body.querySelectorAll('[data-pick]').forEach(el => el.onclick = () => { closeModal(); openFile(list[+el.dataset.pick]); });
      };
      render('');
      body.querySelector('#pickSearch').oninput = (ev) => render(ev.target.value.trim().toLowerCase());
    });
  }

  function showFilePickerForFolder(fileList) {
    const files = Array.from(fileList);
    const npks = files.filter(f => /\.npk$/i.test(f.name));
    if (!npks.length) { toast('这个文件夹里没有 .npk', true); return; }
    if (npks.length === 1) { openFile(npks[0]); return; }
    showNpkPicker(npks);
  }

  /* ---------------- 拖放 ---------------- */
  let dragDepth = 0;
  function hasFiles(e) { return e.dataTransfer && Array.from(e.dataTransfer.types || []).includes('Files'); }
  async function walkEntry(en, out, depth) {
    if (!en || depth > 6) return;
    if (en.isFile) {
      if (/\.(npk|img|ogg)$/i.test(en.name)) out.push(await new Promise((res, rej) => en.file(res, rej)));
    } else if (en.isDirectory) {
      const reader = en.createReader();
      const all = [];
      for (;;) {
        const batch = await new Promise((res, rej) => reader.readEntries(res, rej));
        if (!batch.length) break;
        all.push(...batch);
      }
      for (const c of all) await walkEntry(c, out, depth + 1);
    }
  }
  function wireDrag() {
    window.addEventListener('dragenter', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault(); dragDepth++; $('#dropHint').hidden = false;
    });
    window.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
    window.addEventListener('dragleave', (e) => {
      if (!hasFiles(e)) return;
      dragDepth = Math.max(0, dragDepth - 1);
      if (!dragDepth) $('#dropHint').hidden = true;
    });
    window.addEventListener('drop', async (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault(); dragDepth = 0; $('#dropHint').hidden = true;
      const out = [];
      try {
        const entries = Array.from(e.dataTransfer.items || []).map(i => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
        if (entries.length) { for (const en of entries) await walkEntry(en, out, 0); }
        else out.push(...Array.from(e.dataTransfer.files || []));
      } catch (err) { toast('读取拖入内容失败：' + err.message, true); }
      if (!out.length) { toast('拖入的内容里没有 .npk / .img / .ogg', true); return; }
      if (out.length === 1) openFile(out[0]);
      else showNpkPicker(out);
    });
  }

  /* ================= 拼装 · 导出 =================
   * 把「一个 IMG = 一层帧序列」按 x/y 偏移对齐后逐帧合成，
   * 支持多层叠加（角色 = 身体 + 装备 + 武器…），导出精灵表 + JSON。
   */
  let compSeq = 0;
  const comp = { layers: [], frame: 0, playing: false, timer: 0, fps: 8, bounds: null, bkey: '', cache: new Map(), token: 0 };

  function compBaseName() {
    const nm = (comp.layers[0] && comp.layers[0].name) || state.fileName || 'sheet';
    return baseName(nm).replace(/\.img$/i, '').replace(/[\\/:*?"<>|]/g, '_');
  }

  function compFrameDims(img, f) {
    let w = f.width, h = f.height;
    let r = f;
    for (let k = 0; k < 4 && r && r.reference != null && r.reference >= 0; k++) {
      const t = img.frames[r.reference];
      if (!t) break;
      r = t; w = t.width; h = t.height;
    }
    return { w: Math.max(1, w | 0), h: Math.max(1, h | 0) };
  }

  function compBounds() {
    const key = comp.layers.map(l => l.id + (l.visible ? '1' : '0')).join(',');
    if (comp.bounds && comp.bkey === key) return comp.bounds;
    let minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (const L of comp.layers) {
      if (!L.visible) continue;
      for (const f of L.img.frames) {
        const d = compFrameDims(L.img, f);
        if (f.x < minX) minX = f.x;
        if (f.y < minY) minY = f.y;
        if (f.x + d.w > maxX) maxX = f.x + d.w;
        if (f.y + d.h > maxY) maxY = f.y + d.h;
      }
    }
    if (maxX <= minX || maxY <= minY) { minX = 0; minY = 0; maxX = 1; maxY = 1; }
    comp.bounds = { x: Math.floor(minX), y: Math.floor(minY), w: Math.ceil(maxX - minX), h: Math.ceil(maxY - minY) };
    comp.bkey = key;
    return comp.bounds;
  }

  function compFrameCanv(L, i, dec) {
    const key = L.id + ':' + i;
    let c = comp.cache.get(key);
    if (c) return c;
    c = document.createElement('canvas');
    c.width = Math.max(1, dec.w); c.height = Math.max(1, dec.h);
    const g = c.getContext('2d');
    const id = g.createImageData(dec.w, dec.h);
    id.data.set(dec.rgba);
    g.putImageData(id, 0, 0);
    comp.cache.set(key, c);
    if (comp.cache.size > 3000) comp.cache.clear();
    return c;
  }

  function compEnsureBase() {
    if (!state.img) return;
    if (comp.layers.some(l => l.img === state.img)) return;
    if (comp.layers[0] && comp.layers[0].auto) {
      comp.layers[0] = { id: comp.layers[0].id, img: state.img, name: (state.imgEntry && state.imgEntry.entry.name) || '当前条目', visible: true, auto: true };
    } else {
      comp.layers.unshift({ id: ++compSeq, img: state.img, name: (state.imgEntry && state.imgEntry.entry.name) || '当前条目', visible: true, auto: true });
    }
    comp.cache.clear();
    comp.bounds = null; comp.bkey = '';
    comp.frame = 0;
  }

  async function compAddLayer(img, name) {
    if (comp.layers.some(l => l.img === img)) { toast('这个图层已经在列表里了'); return; }
    comp.layers.push({ id: ++compSeq, img, name, visible: true });
    comp.bounds = null; comp.bkey = '';
    toast('已添加图层：' + baseName(name));
    compRender();
  }

  async function compAddFromEntry(idx) {
    const e = state.entries[idx];
    if (!e || e.isOgg) { toast('这个条目不是 IMG', true); return; }
    let img = state.imgCache.get(idx);
    if (!img) {
      try {
        const b = state.bytes.subarray(e.offset, e.offset + e.size);
        img = C.parseImg(b); img.bytes = b;
        state.imgCache.set(idx, img);
      } catch (err) { toast('解析失败：' + err.message, true); return; }
    }
    closeModal();
    await compAddLayer(img, e.name);
  }

  function compShowPicker() {
    const rows = state.entries.map((e, i) => ({ e, i })).filter(r => !r.e.isOgg && !(r.e === (state.imgEntry && state.imgEntry.entry)));
    if (!rows.length) { toast('当前包里没有别的 IMG 可以叠加'); return; }
    showModal('添加图层（当前包里的 IMG）', `
      <div class="search" style="margin-bottom:10px"><input id="laySearch" placeholder="过滤条目名…" style="width:100%"></div>
      <div class="npk-list" id="layList"></div>`, (body) => {
      const render = (q) => {
        const arr = rows.filter(r => !q || r.e.name.toLowerCase().includes(q));
        body.querySelector('#layList').innerHTML = arr.slice(0, 400).map(r =>
          `<div class="npk-item" data-lay="${r.i}"><span class="nm">${esc(r.e.name)}</span><span class="sz">v? · ${fmtBytes(r.e.size)}</span></div>`).join('') ||
          '<div class="hint" style="padding:20px;text-align:center">没有匹配</div>';
        body.querySelectorAll('[data-lay]').forEach(el => el.onclick = () => compAddFromEntry(+el.dataset.lay));
      };
      render('');
      body.querySelector('#laySearch').oninput = (ev) => render(ev.target.value.trim().toLowerCase());
    });
  }

  function compAddFile() {
    const inp = document.createElement('input');
    inp.type = 'file'; inp.accept = '.img,.IMG';
    inp.onchange = async () => {
      const f = inp.files && inp.files[0];
      if (!f) return;
      try {
        const b = new Uint8Array(await f.arrayBuffer());
        await compAddLayer(C.parseImg(b), f.name);
      } catch (err) { toast('解析失败：' + err.message, true); }
    };
    inp.click();
  }

  function compLayerListHTML() {
    return comp.layers.slice().reverse().map((L) => {
      const vn = L.img.version;
      return `<div class="layer-row" data-id="${L.id}">
        <button class="icon-btn tiny ${L.visible ? 'on' : ''}" data-act="vis" title="显示/隐藏">${L.visible ? '●' : '○'}</button>
        <div class="layer-main"><div class="layer-nm" title="${esc(L.name)}">${esc(baseName(L.name))}</div>
          <div class="layer-sub">v${vn} · ${L.img.frames.length} 帧${L.auto ? ' · 当前条目' : ''}</div></div>
        <div class="layer-btns">
          <button class="icon-btn tiny" data-act="up" title="上移">↑</button>
          <button class="icon-btn tiny" data-act="down" title="下移">↓</button>
          <button class="icon-btn tiny" data-act="del" title="移除">×</button>
        </div></div>`;
    }).join('') || '<div class="hint" style="padding:12px">还没有图层</div>';
  }

  function compRender() {
    compEnsureBase();
    const img = comp.layers[0] && comp.layers[0].img;
    const n = img ? img.frames.length : 0;
    const b = n ? compBounds() : null;
    $('#cSlider').max = Math.max(0, n - 1);
    $('#cFrameNum').textContent = n ? `${comp.frame + 1} / ${n}` : '0 / 0';
    const body = $('#compBody');
    if (body) {
      body.innerHTML = n ? `
        <div class="card"><h5>拼装说明</h5>
          <div class="hint">每一层按自己的 x/y 偏移叠到同一个原点上，帧号各层独立循环。导出的是<b>整段动画</b>：
          精灵表每格 ${b.w}×${b.h}，格内左上角对应原点偏移 (${-b.x}, ${-b.y})。</div></div>
        <div class="card"><h5>图层（越靠上越盖住下层）</h5>
          <div class="layer-list" id="compLayers">${compLayerListHTML()}</div>
          <div class="row-actions"><button class="btn sm" id="compAddPick">＋ 从本包添加</button>
          <button class="btn sm ghost" id="compAddFile">＋ 从文件添加</button></div></div>
        <div class="card"><h5>导出</h5>
          <div class="row-actions">
            <button class="btn sm primary" id="compSheet">导出精灵表 PNG + JSON</button>
            <button class="btn sm" id="compApng">导出动图 APNG</button>
          </div>
          <div class="hint" style="margin-top:8px">精灵表按行排列，JSON 里带每帧的格内坐标与原点，Godot 里用
          <code>AtlasTexture</code> / <code>Sprite2D</code> 直接切。APNG 动图带透明通道，可直接预览/转换。</div></div>`
        : '<div class="card"><h5>拼装 · 导出</h5><div class="hint">先在左侧选一个 IMG 条目，这里会把它当作底层；然后可以从本包或文件里继续添加装备、武器、特效层。</div></div>';
      const addPick = $('#compAddPick'); if (addPick) addPick.onclick = compShowPicker;
      const addFile = $('#compAddFile'); if (addFile) addFile.onclick = compAddFile;
      const btnSheet = $('#compSheet'); if (btnSheet) btnSheet.onclick = compExportSheet;
      const btnApng = $('#compApng'); if (btnApng) btnApng.onclick = compExportApng;
      wireCompLayers();
    }
    compDraw();
  }

  function wireCompLayers() {
    const box = $('#compLayers');
    if (!box) return;
    box.onclick = (ev) => {
      const btn = ev.target.closest('button[data-act]');
      const row = ev.target.closest('.layer-row');
      if (!btn || !row) return;
      const id = +row.dataset.id;
      const i = comp.layers.findIndex(l => l.id === id);
      if (i < 0) return;
      const act = btn.dataset.act;
      if (act === 'vis') comp.layers[i].visible = !comp.layers[i].visible;
      if (act === 'del') { comp.layers.splice(i, 1); comp.bounds = null; comp.bkey = ''; }
      if (act === 'up' && i < comp.layers.length - 1) { const t = comp.layers[i]; comp.layers[i] = comp.layers[i + 1]; comp.layers[i + 1] = t; }
      if (act === 'down' && i > 0) { const t = comp.layers[i]; comp.layers[i] = comp.layers[i - 1]; comp.layers[i - 1] = t; }
      comp.bounds = null; comp.bkey = '';
      compRender();
    };
  }

  async function compDraw() {
    const cv = $('#cStage');
    if (!cv) return;
    const stage = cv.parentElement;
    const W = Math.max(200, stage.clientWidth), H = Math.max(160, stage.clientHeight);
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    cv.style.width = W + 'px'; cv.style.height = H + 'px';
    const ctx = cv.getContext('2d');
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    fillBg(ctx, W, H);
    const img = comp.layers[0] && comp.layers[0].img;
    if (!img || !img.frames.length) { $('#cFoot').textContent = '先选一个 IMG 条目'; return; }
    const mine = ++comp.token;
    const b = compBounds();
    const pad = 22;
    const s = Math.max(0.02, Math.min((W - pad * 2) / b.w, (H - pad * 2) / b.h, 8));
    const ox = W / 2 - (b.x + b.w / 2) * s;
    const oy = H / 2 - (b.y + b.h / 2) * s;
    const n = img.frames.length;
    const fi = comp.frame % n;
    for (const L of comp.layers) {
      if (!L.visible) continue;
      const li = comp.frame % L.img.frames.length;
      let dec;
      try { dec = await C.decodeFrame(L.img, li); } catch (e) { continue; }
      if (mine !== comp.token) return;
      const f = L.img.frames[li];
      const c = compFrameCanv(L, li, dec);
      ctx.imageSmoothingEnabled = s < 1;
      ctx.drawImage(c, ox + (f.x - b.x) * s, oy + (f.y - b.y) * s, Math.max(1, dec.w * s), Math.max(1, dec.h * s));
    }
    if (mine !== comp.token) return;
    // 原点 + 单元格外框
    const gx = ox + (0 - b.x) * s, gy = oy + (0 - b.y) * s;
    ctx.save();
    ctx.strokeStyle = 'rgba(62,198,255,.35)';
    ctx.setLineDash([4, 4]);
    ctx.strokeRect(ox + .5, oy + .5, b.w * s - 1, b.h * s - 1);
    ctx.setLineDash([]);
    ctx.strokeStyle = 'rgba(61,220,151,.9)';
    ctx.beginPath();
    ctx.moveTo(gx - 8, gy); ctx.lineTo(gx + 8, gy);
    ctx.moveTo(gx, gy - 8); ctx.lineTo(gx, gy + 8);
    ctx.stroke();
    ctx.restore();
    const total = comp.layers.reduce((m, L) => Math.max(m, L.img.frames.length), 0);
    $('#cFrameNum').textContent = `${comp.frame + 1} / ${n}` + (total > n ? `（最长层 ${total}）` : '');
    $('#cFoot').textContent = `${n} 帧 · 单元格 ${b.w}×${b.h} · 原点在格内 (${-b.x}, ${-b.y}) · ${comp.layers.filter(l => l.visible).length} 层 · ${Math.round(s * 100)}%`;
  }

  function compSetFrame(i) {
    const n = comp.layers[0] ? comp.layers[0].img.frames.length : 0;
    if (!n) return;
    comp.frame = ((i % n) + n) % n;
    $('#cSlider').value = comp.frame;
    compDraw();
  }
  function compStart() {
    if (!comp.layers[0]) return;
    comp.playing = true;
    $('#cPlay').classList.add('on'); $('#cPlay').textContent = '❚❚';
    clearInterval(comp.timer);
    comp.timer = setInterval(() => {
      if (!comp.playing) return;
      const n = comp.layers[0].img.frames.length;
      if (!(comp.frame + 1 < n) && !$('#cLoop').checked) { compStop(); return; }
      compSetFrame(comp.frame + 1);
    }, 1000 / Math.max(1, Math.min(60, comp.fps)));
  }
  function compStop() {
    comp.playing = false; clearInterval(comp.timer);
    const b = $('#cPlay'); if (b) { b.classList.remove('on'); b.textContent = '▶'; }
  }

  function compStepFor(L, i) {
    return i % L.img.frames.length;
  }

  async function compExportSheet() {
    if (!comp.layers.length) return;
    const n = comp.layers[0].img.frames.length;
    const b = compBounds();
    const maxW = 8192;
    const cols = Math.max(1, Math.min(n, Math.floor(maxW / b.w)));
    const rows = Math.ceil(n / cols);
    const cv = document.createElement('canvas');
    cv.width = cols * b.w; cv.height = rows * b.h;
    const g = cv.getContext('2d');
    const btn = $('#compSheet');
    if (btn) { btn.disabled = true; btn.textContent = '导出中…'; }
    const frames = [];
    for (let i = 0; i < n; i++) {
      if (i % 3 === 0) {
        $('#cFoot').textContent = `拼装导出中… ${i} / ${n}`;
        await new Promise(r => setTimeout(r));
      }
      const cx = (i % cols) * b.w, cy = Math.floor(i / cols) * b.h;
      for (const L of comp.layers) {
        if (!L.visible) continue;
        const li = compStepFor(L, i);
        let dec; try { dec = await C.decodeFrame(L.img, li); } catch (e) { continue; }
        const f = L.img.frames[li];
        g.drawImage(compFrameCanv(L, li, dec), cx + (f.x - b.x), cy + (f.y - b.y));
      }
      frames.push({ i, x: (i % cols) * b.w, y: Math.floor(i / cols) * b.h, w: b.w, h: b.h });
    }
    $('#cFoot').textContent = `${n} 帧 · 单元格 ${b.w}×${b.h} · ${comp.layers.filter(l => l.visible).length} 层`;
    const name = compBaseName();
    cv.toBlob((blob) => {
      if (!blob) { toast('生成 PNG 失败（可能太大）', true); return; }
      download(name + '_sheet.png', blob);
      const meta = {
        format: 'npk-inspector/sheet@1',
        name,
        fps: comp.fps,
        cell: { w: b.w, h: b.h },
        cols, rows,
        origin: { x: -b.x, y: -b.y },
        frames,
        layers: comp.layers.filter(l => l.visible).map(L => ({ name: L.name, version: L.img.version, frames: L.img.frames.length })),
      };
      download(name + '_sheet.json', new Blob([JSON.stringify(meta, null, 1)], { type: 'application/json' }));
      toast(`已导出 ${cols}×${rows} 格精灵表`);
      if (btn) { btn.disabled = false; btn.textContent = '导出精灵表 PNG + JSON'; }
    }, 'image/png');
  }

  async function compDrawFrameInto(g, i, b, dx, dy) {
    for (const L of comp.layers) {
      if (!L.visible) continue;
      const li = compStepFor(L, i);
      let dec; try { dec = await C.decodeFrame(L.img, li); } catch (e) { continue; }
      const f = L.img.frames[li];
      g.drawImage(compFrameCanv(L, li, dec), dx + (f.x - b.x), dy + (f.y - b.y));
    }
  }

  const CRC_T = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      t[n] = c >>> 0;
    }
    return t;
  })();
  function crc32(u8) {
    let c = 0xFFFFFFFF;
    for (let i = 0; i < u8.length; i++) c = CRC_T[(c ^ u8[i]) & 0xFF] ^ (c >>> 8);
    return (c ^ 0xFFFFFFFF) >>> 0;
  }
  function pngChunk(type, data) {
    const t = new TextEncoder().encode(type);
    const out = new Uint8Array(12 + data.length);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, data.length);
    out.set(t, 4); out.set(data, 8);
    const body = new Uint8Array(4 + data.length);
    body.set(t, 0); body.set(data, 4);
    dv.setUint32(8 + data.length, crc32(body));
    return out;
  }
  function u32(n) { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, n >>> 0); return b; }
  function u16(n) { const b = new Uint8Array(2); new DataView(b.buffer).setUint16(0, n & 0xFFFF); return b; }
  function cat(parts) {
    let n = 0; for (const p of parts) n += p.length;
    const o = new Uint8Array(n); let k = 0;
    for (const p of parts) { o.set(p, k); k += p.length; }
    return o;
  }
  function pngParts(buf) {
    const u8 = new Uint8Array(buf);
    let p = 8; const idat = []; let ihdr = null;
    while (p + 8 <= u8.length) {
      const dv = new DataView(u8.buffer, u8.byteOffset + p);
      const len = dv.getUint32(0);
      const type = new TextDecoder('ascii').decode(u8.subarray(p + 4, p + 8));
      const data = u8.subarray(p + 8, p + 8 + len);
      if (type === 'IHDR') ihdr = data;
      if (type === 'IDAT') idat.push(data);
      p += 12 + len;
      if (type === 'IEND') break;
    }
    return { ihdr, idat };
  }

  async function compExportApng() {
    if (!comp.layers.length) return;
    const n = comp.layers[0].img.frames.length;
    const b = compBounds();
    const cv = document.createElement('canvas');
    cv.width = b.w; cv.height = b.h;
    const g = cv.getContext('2d');
    const btn = $('#compApng');
    if (btn) { btn.disabled = true; btn.textContent = '生成中…'; }
    const delayNum = Math.max(1, Math.round(1000 / Math.max(1, comp.fps)));
    const frames = [];
    for (let i = 0; i < n; i++) {
      if (i % 3 === 0) {
        $('#cFoot').textContent = `APNG 生成中… ${i} / ${n}`;
        await new Promise(r => setTimeout(r));
      }
      g.clearRect(0, 0, b.w, b.h);
      await compDrawFrameInto(g, i, b, 0, 0);
      const blob = await new Promise(res => cv.toBlob(res, 'image/png'));
      if (!blob) continue;
      frames.push(pngParts(await blob.arrayBuffer()));
    }
    if (btn) { btn.disabled = false; btn.textContent = '导出动图 APNG'; }
    if (!frames.length) { toast('生成失败', true); return; }
    const sig = new Uint8Array([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    const parts = [sig, pngChunk('IHDR', frames[0].ihdr)];
    parts.push(pngChunk('acTL', cat([u32(frames.length), u32(0)])));
    let seq = 0;
    frames.forEach((fr, i) => {
      const fctl = cat([u32(seq++), u32(b.w), u32(b.h), u32(0), u32(0), u16(delayNum), u16(1000), new Uint8Array([0, 0])]);
      parts.push(pngChunk('fcTL', fctl));
      if (i === 0) {
        for (const d of fr.idat) parts.push(pngChunk('IDAT', d));
      } else {
        for (const d of fr.idat) parts.push(pngChunk('fdAT', cat([u32(seq++), d])));
      }
    });
    parts.push(pngChunk('IEND', new Uint8Array(0)));
    download(compBaseName() + '.png', new Blob([cat(parts)], { type: 'image/png' }));
    toast(`已导出 APNG：${frames.length} 帧 @ ${comp.fps}fps`);
    $('#cFoot').textContent = `${n} 帧 · 单元格 ${b.w}×${b.h}`;
  }

  function wireCompose() {
    $('#cPrev').onclick = () => { compStop(); compSetFrame(comp.frame - 1); };
    $('#cNext').onclick = () => { compStop(); compSetFrame(comp.frame + 1); };
    $('#cPlay').onclick = () => { comp.playing ? compStop() : compStart(); };
    $('#cSlider').oninput = (ev) => { compStop(); compSetFrame(+ev.target.value); };
    $('#cFps').onchange = (ev) => {
      comp.fps = Math.max(1, Math.min(60, +ev.target.value || 8));
      ev.target.value = comp.fps;
      if (comp.playing) compStart();
    };
  }

  /* ---------------- 初始化 ---------------- */
  function openDemo() {
    const d = window.DEMO_NPK;
    if (!d) { toast('没有内置示例数据', true); return; }
    const bin = atob(d.b64);
    const u8 = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
    loadPack(u8, d.name + '  ·  内置示例', true);
    applyUrlParams();
  }

  function applyUrlParams() {
    const p = new URLSearchParams(location.search);
    const name = p.get('entry');
    if (name) {
      const hit = state.entries.findIndex(e => e.name === name);
      const loose = hit >= 0 ? hit : state.entries.findIndex(e => e.name.toLowerCase().includes(name.toLowerCase()));
      if (loose >= 0) selectEntry(loose);
      else toast('找不到条目：' + name, true);
    }
    const tab = p.get('tab');
    if (tab && ['preview', 'atlas', 'structure', 'audio', 'compose'].includes(tab)) setTab(tab);
    const frame = +p.get('frame');
    if (frame > 0 && state.img) setFrame(frame - 1);
    const zoom = p.get('zoom');
    if (zoom) { state.zoom = zoom === 'fit' ? 'fit' : String(+zoom || 1); $('#zoomSel').value = state.zoom; }
    const bg = p.get('bg');
    if (bg) { state.bg = bg; $('#bgSel').value = bg; }
    const cf = +p.get('cframe');
    if (cf > 0 && state.tab === 'compose') compSetFrame(cf - 1);
    if (p.get('play') === '1') startPlay();
    if (state.img) drawPreview();
  }

  function init() {
    $('#btnOpen').onclick = () => $('#fileInput').click();
    $('#btnFolder').onclick = () => $('#dirInput').click();
    $('#btnHelp').onclick = showHelp;
    $('#fileInput').onchange = (ev) => { const f = ev.target.files[0]; if (f) openFile(f); ev.target.value = ''; };
    $('#dirInput').onchange = (ev) => { showFilePickerForFolder(ev.target.files); ev.target.value = ''; };
    $('#btnExportRaw').onclick = exportRaw;
    $('#btnExportJson').onclick = exportJson;
    $('#modalClose').onclick = closeModal;
    $('#overlay').onclick = (ev) => { if (ev.target === $('#overlay')) closeModal(); };
    $('#tabs').onclick = (ev) => { const b = ev.target.closest('button[data-tab]'); if (b) setTab(b.dataset.tab); };
    let q = 0;
    $('#search').oninput = (ev) => {
      state.q = ev.target.value.trim();
      clearTimeout(q);
      q = setTimeout(() => applyFilter(false), 110);
    };
    $('#filters').onclick = (ev) => { const b = ev.target.closest('button[data-filter]'); if (b) setFilter(b.dataset.filter, false); };
    let raf = 0;
    $('#listWrap').onscroll = () => { if (raf) return; raf = requestAnimationFrame(() => { raf = 0; renderRows(); }); };
    $('#listRows').onclick = (ev) => { const r = ev.target.closest('.row'); if (r) selectEntry(+r.dataset.i); };
    wirePreview();
    wireCompose();
    wireDrag();

    document.addEventListener('keydown', (ev) => {
      const t = ev.target;
      if (t && /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName)) return;
      if (ev.key === 'Escape') { closeModal(); return; }
      if (ev.key === '?' || (ev.key === '/' && ev.shiftKey)) { ev.preventDefault(); showHelp(); return; }
      if (state.tab === 'preview' && state.img) {
        if (ev.key === 'ArrowLeft') { ev.preventDefault(); stopPlay(); setFrame(state.frame - 1); return; }
        if (ev.key === 'ArrowRight') { ev.preventDefault(); stopPlay(); setFrame(state.frame + 1); return; }
        if (ev.key === ' ') { ev.preventDefault(); state.playing ? stopPlay() : startPlay(); return; }
        if (ev.key === 'f' || ev.key === 'F') { state.zoom = 'fit'; $('#zoomSel').value = 'fit'; drawPreview(); return; }
      }
      if (state.tab === 'compose' && comp.layers[0]) {
        if (ev.key === 'ArrowLeft') { ev.preventDefault(); compStop(); compSetFrame(comp.frame - 1); return; }
        if (ev.key === 'ArrowRight') { ev.preventDefault(); compStop(); compSetFrame(comp.frame + 1); return; }
        if (ev.key === ' ') { ev.preventDefault(); comp.playing ? compStop() : compStart(); return; }
      }
      if (ev.key === '1') setTab('preview');
      else if (ev.key === '2') setTab('atlas');
      else if (ev.key === '3') setTab('structure');
      else if (ev.key === '4') setTab('audio');
      else if (ev.key === '5') setTab('compose');
    });

    const onResize = () => {
      if (state.tab === 'compose') { compDraw(); return; }
      if (!state.img) drawIdle(); else drawPreview();
    };
    window.addEventListener('resize', onResize);
    if (window.ResizeObserver) new ResizeObserver(() => {
      if (state.tab === 'compose') compDraw();
      else if (!state.img) drawIdle(); else drawPreview();
    }).observe($('#stage'));
    $('#zoomSel').value = state.zoom;
    drawIdle();

    const p = new URLSearchParams(location.search);
    if (p.get('demo') !== '0' && window.DEMO_NPK) openDemo();
    window.__NPK = { state, comp, setTab, setFrame, selectEntry, openDemo, applyUrlParams, loadDirect, loadPack, openFile, compAddLayer, compExportSheet, compExportApng };
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
