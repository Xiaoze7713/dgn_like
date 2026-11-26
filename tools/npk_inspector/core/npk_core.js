/* ==========================================================================
 * npk_core.js —— DNF NPK / IMG / DDS / OGG 纯 JS 解析与解码核心
 * 无 DOM 依赖；浏览器挂到 window.NPKCore，Node 里 module.exports。
 * 格式依据：docs/NPK-FORMAT.md（v1/v2/v4/v5/v6 全实测）
 * ========================================================================== */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.NPKCore = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const NPK_MAGIC = 'NeoplePack_Bill\0';
  const IMG_MAGIC = 'Neople Img File\0';
  const IMG_MAGIC_V1 = 'Neople Image File\0';
  const NPK_ENTRY_SIZE = 264;
  const NPK_SUM_SIZE = 32;

  const T_INDEXED = 0x0e;
  const T_ARGB1555 = 0x0e;
  const T_ARGB4444 = 0x0f;
  const T_ARGB8888 = 0x10;
  const T_REFERENCE = 0x11;
  const T_FXT1 = 0x12;
  const T_FXT2 = 0x13;
  const T_FXT3 = 0x14;
  const C_RAW = 0x05;
  const C_ZLIB = 0x06;
  const C_DDSREF = 0x07;

  const TYPE_NAMES = {
    0x0e: 'ARGB1555 / 索引', 0x0f: 'ARGB4444', 0x10: 'ARGB8888',
    0x11: 'REFERENCE 指向帧', 0x12: 'FXT1 / DXT1', 0x13: 'FXT2 / DXT3',
    0x14: 'FXT3 / DXT5', 0x06: '历史类型 0x06',
  };
  const COMP_NAMES = { 0x05: '未压缩', 0x06: 'zlib', 0x07: '共享贴图' };

  /* ---------------- 文件名 XOR 密钥 ---------------- */
  const NAME_KEY = (function () {
    const seed = 'puchikon@neople dungeon and fighter ';
    let s = seed;
    while (s.length < 256) s += 'DNF';
    const out = new Uint8Array(256);
    for (let i = 0; i < 256; i++) out[i] = s.charCodeAt(i) & 0xff;
    out[255] = 0;
    return out;
  })();

  let gbkDecoder = null;
  try { gbkDecoder = new TextDecoder('gbk'); } catch (e) { gbkDecoder = null; }

  function decodeName(raw) {
    const plain = new Uint8Array(256);
    for (let i = 0; i < 256; i++) plain[i] = raw[i] ^ NAME_KEY[i];
    let end = plain.indexOf(0);
    if (end < 0) end = 256;
    const slice = plain.subarray(0, end);
    if (gbkDecoder) {
      try { return gbkDecoder.decode(slice); } catch (e) { /* fallthrough */ }
    }
    let s = '';
    for (let i = 0; i < slice.length; i++) s += String.fromCharCode(slice[i]);
    return s;
  }

  function asciiAt(u8, off, len) {
    if (off + len > u8.length) return '';
    let s = '';
    for (let i = 0; i < len; i++) s += String.fromCharCode(u8[off + i]);
    return s;
  }

  /* ---------------- zip 解压（DecompressionStream） ---------------- */
  async function inflateZlib(u8) {
    if (typeof DecompressionStream === 'undefined') {
      throw new Error('当前环境不支持 DecompressionStream');
    }
    const ds = new DecompressionStream('deflate');
    const writer = ds.writable.getWriter();
    const reader = ds.readable.getReader();
    // 先写后读，避免大块数据把管道的背压卡死
    writer.write(u8).catch(function () {});
    writer.close().catch(function () {});
    const chunks = [];
    let total = 0;
    try {
      for (;;) {
        const r = await reader.read();
        if (r.done) break;
        if (r.value && r.value.length) { chunks.push(r.value); total += r.value.length; }
      }
    } catch (e) {
      // 截断的 zlib 流：保留已解出的部分
      if (!total) throw new Error('zlib 解压失败：' + e.message);
    }
    const out = new Uint8Array(total);
    let p = 0;
    for (const c of chunks) { out.set(c, p); p += c.length; }
    return out;
  }

  function looksZlib(u8) {
    return u8.length >= 2 && u8[0] === 0x78 && (u8[1] === 0x01 || u8[1] === 0x9c || u8[1] === 0xda);
  }

  /* ---------------- NPK ---------------- */
  function isNpk(u8) {
    return asciiAt(u8, 0, 16) === NPK_MAGIC;
  }

  function parseNpkIndex(u8) {
    if (u8.length < 20 || !isNpk(u8)) throw new Error('不是 NPK（magic 不符）');
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    const count = dv.getUint32(16, true);
    const indexEnd = 20 + count * NPK_ENTRY_SIZE;
    if (indexEnd > u8.length) throw new Error('索引表越界：声明 ' + count + ' 条目');
    const entries = [];
    for (let i = 0; i < count; i++) {
      const base = 20 + i * NPK_ENTRY_SIZE;
      entries.push({
        index: i,
        offset: dv.getInt32(base, true),
        size: dv.getInt32(base + 4, true),
        name: decodeName(u8.subarray(base + 8, base + NPK_ENTRY_SIZE)),
      });
    }
    return {
      count, entries,
      headerEnd: 20,
      indexEnd,
      checksumEnd: indexEnd + NPK_SUM_SIZE,
      fileSize: u8.length,
      trailing: u8.length - (indexEnd + NPK_SUM_SIZE),
    };
  }

  /* ---------------- IMG ---------------- */
  function bppFor(version, type, compressed) {
    if (type === T_ARGB8888) return 4;
    if (type === 0x0f) return 2;
    if (type === 0x0e) {
      // v4 实测：zlib 帧是调色板索引(1B/px)，未压缩帧仍是 ARGB1555(2B/px)
      // —— 60 张 v4 头像图按此规则体长全部精确对齐（见 README“v4 未压缩帧”）
      if (version === 4 && compressed === C_RAW) return 2;
      if (version === 4 || version === 6) return 1;
      return 2;
    }
    return 0;
  }

  function parseImg(u8) {
    if (u8.length < 32) throw new Error('IMG 数据太短（' + u8.length + ' 字节）');
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    const v1 = asciiAt(u8, 0, 18) === IMG_MAGIC_V1;
    if (!v1 && asciiAt(u8, 0, 16) !== IMG_MAGIC) throw new Error('不是 IMG（magic 不符）');
    let tableLength = 0, version, frameCount, pos = 32;
    if (v1) {
      version = dv.getUint32(24, true);
      frameCount = dv.getUint32(28, true);
    } else {
      tableLength = dv.getUint32(16, true);
      version = dv.getUint32(24, true);
      frameCount = dv.getUint32(28, true);
    }
    if ([1, 2, 4, 5, 6].indexOf(version) < 0) throw new Error('不支持的 IMG 版本 v' + version);
    const img = {
      version, frameCount, tableLength, v1,
      palettes: [], dds: [], frames: [], warnings: [], resolved: [],
      extStart: 32, recordsStart: 0, ddsStart: 0, bodyStart: 0, dataEnd: 0,
    };
    if (version === 4) {
      const n = dv.getInt32(pos, true); pos += 4;
      if (n < 0 || n > 65536) throw new Error('v4 调色板条目数异常：' + n);
      img.palettes.push(u8.slice(pos, pos + n * 4)); pos += n * 4;
    } else if (version === 5) {
      const ddsCount = dv.getInt32(pos, true);
      const imgLength = dv.getInt32(pos + 4, true);
      const colorNum = dv.getInt32(pos + 8, true);
      pos += 12;
      if (colorNum > 0) {
        if (colorNum * 4 > u8.length) throw new Error('v5 调色板越界');
      }
      img.palettes.push(u8.slice(pos, pos + Math.max(0, colorNum) * 4));
      pos += Math.max(0, colorNum) * 4;
      img.v5imgLength = imgLength;
      if (ddsCount < 0 || ddsCount > 65536) throw new Error('v5 DDS 数量异常：' + ddsCount);
      for (let i = 0; i < ddsCount; i++) {
        if (pos + 28 > u8.length) throw new Error('v5 DDS 记录越界');
        img.dds.push({
          index: i,
          title: dv.getInt32(pos, true),
          pixelFormat: dv.getInt32(pos + 4, true),
          reserved: dv.getInt32(pos + 8, true),
          fullLength: dv.getInt32(pos + 12, true),
          length: dv.getInt32(pos + 16, true),
          width: dv.getInt32(pos + 20, true),
          height: dv.getInt32(pos + 24, true),
          rawOffset: -1, rawLength: 0, rgba: null, error: null,
        });
        pos += 28;
      }
    } else if (version === 6) {
      const palCount = dv.getInt32(pos, true); pos += 4;
      for (let i = 0; i < palCount; i++) {
        const n = dv.getInt32(pos, true); pos += 4;
        img.palettes.push(u8.slice(pos, pos + n * 4)); pos += n * 4;
      }
    }
    img.recordsStart = pos;
    for (let i = 0; i < frameCount; i++) {
      if (pos + 8 > u8.length) throw new Error('帧记录越界（帧 ' + i + '）');
      const type = dv.getInt32(pos, true);
      const f = {
        index: i, type, compressed: 0, width: 0, height: 0, length: 0,
        x: 0, y: 0, canvasW: 0, canvasH: 0, reference: -1, ddsIndex: -1,
        left: 0, up: 0, right: 0, down: 0,
        recOffset: pos, recLength: 8, bodyOffset: -1, bodyLength: 0, bpp: 0,
        lengthDeclared: null, truncated: false,
      };
      if (type === T_REFERENCE) {
        if (pos + 8 > u8.length) throw new Error('指向帧记录越界（帧 ' + i + '）');
        f.reference = dv.getInt32(pos + 4, true);
      } else {
        if (pos + 36 > u8.length) throw new Error('帧记录越界（帧 ' + i + '）');
        f.compressed = dv.getInt32(pos + 4, true);
        f.width = dv.getInt32(pos + 8, true);
        f.height = dv.getInt32(pos + 12, true);
        f.length = dv.getInt32(pos + 16, true);
        f.x = dv.getInt32(pos + 20, true);
        f.y = dv.getInt32(pos + 24, true);
        f.canvasW = dv.getInt32(pos + 28, true);
        f.canvasH = dv.getInt32(pos + 32, true);
        f.bpp = bppFor(version, type, f.compressed);
        if (version === 5 && (f.compressed === C_DDSREF || type === T_FXT1 || type === T_FXT2 || type === T_FXT3)) {
          if (pos + 64 > u8.length) throw new Error('DDS 帧记录越界（帧 ' + i + '）');
          f.ddsIndex = dv.getInt32(pos + 40, true);
          f.left = dv.getInt32(pos + 44, true);
          f.up = dv.getInt32(pos + 48, true);
          f.right = dv.getInt32(pos + 52, true);
          f.down = dv.getInt32(pos + 56, true);
          f.recLength = 64;
        } else {
          f.recLength = 36;
        }
        if (!v1 && f.compressed === C_RAW) {
          const exp = f.width * f.height * (f.bpp || 1);
          if (exp !== f.length) { f.lengthDeclared = f.length; f.length = exp; }
        }
      }
      img.frames.push(f);
      pos += f.recLength;
      if (v1 && type !== T_REFERENCE) {
        // v1：记录后紧跟自己的帧体
        let n = f.compressed === C_RAW ? f.length : f.length;
        if (n < 0) n = 0;
        f.bodyOffset = pos;
        f.bodyLength = n;
        pos += n;
      }
    }
    img.recordsEnd = pos;
    if (!v1) {
      if (version === 5) {
        img.ddsStart = pos;
        for (const d of img.dds) {
          const n = Math.max(0, d.fullLength);
          d.rawOffset = pos;
          d.rawLength = Math.min(n, Math.max(0, u8.length - pos));
          pos += n;
        }
      }
      img.bodyStart = pos;
      for (const f of img.frames) {
        if (f.type === T_REFERENCE) continue;
        if (version === 5 && f.compressed === C_DDSREF) continue;
        let n = f.length;
        if (f.compressed === C_RAW) {
          const exp = f.width * f.height * (f.bpp || 1);
          if (exp !== n) { f.lengthDeclared = n; n = exp; f.length = exp; }
        }
        if (n < 0) n = 0;
        f.bodyOffset = pos;
        const avail = Math.max(0, u8.length - pos);
        f.bodyLength = Math.min(n, avail);
        f.truncated = f.bodyLength < n;
        pos += n;
      }
    }
    img.dataEnd = pos;
    img.regions = buildRegions(img, u8.length);
    // 指向帧解析（含环检测，降级为 -1）
    for (const f of img.frames) {
      if (f.type !== T_REFERENCE) { img.resolved.push(f.index); continue; }
      const seen = new Set([f.index]);
      let cur = f.reference, depth = 0, ok = false;
      for (;;) {
        if (cur < 0 || cur >= img.frames.length) {
          img.warnings.push('帧 ' + f.index + ' 指向越界帧 ' + cur + '，按无图像处理');
          break;
        }
        if (seen.has(cur)) {
          img.warnings.push('帧 ' + f.index + ' 的指向链有环（到帧 ' + cur + '）');
          break;
        }
        if (++depth > 64) {
          img.warnings.push('帧 ' + f.index + ' 的指向链过深（>64）');
          break;
        }
        seen.add(cur);
        const nxt = img.frames[cur];
        if (nxt.type !== T_REFERENCE) { cur = nxt.index; ok = true; break; }
        cur = nxt.reference;
      }
      img.resolved.push(ok ? cur : -1);
    }
    return img;
  }

  function buildRegions(img, fileLen) {
    const R = [];
    const add = (key, label, start, end, color) => {
      if (end > start) R.push({ key, label, start, end, color });
    };
    add('header', 'IMG 头 32B', 0, Math.min(32, fileLen), '#64748b');
    if (img.v1) {
      add('records', '记录 + 帧体（交替）', 32, img.dataEnd, '#38bdf8');
      return R;
    }
    if (img.version === 4 && img.palettes.length) {
      add('palette', '调色板 ' + (img.palettes[0].length / 4) + ' 色', 32, img.recordsStart, '#a78bfa');
    } else if (img.version === 5) {
      add('ext', 'v5 扩展头（ddsCount/imgLength/调色板）', 32, img.recordsStart, '#a78bfa');
    } else if (img.version === 6) {
      add('ext', 'v6 调色板区', 32, img.recordsStart, '#a78bfa');
    }
    add('records', '帧记录 ' + img.frames.length + ' 条', img.recordsStart, img.recordsEnd, '#38bdf8');
    if (img.dds.length) {
      add('ddsTable', 'DDS 表 ' + img.dds.length + ' 项', img.recordsEnd, img.ddsStart, '#f59e0b');
      add('ddsData', 'DDS 贴图数据', img.ddsStart, img.bodyStart, '#fbbf24');
    }
    add('bodies', '帧体数据', img.bodyStart, img.dataEnd, '#34d399');
    add('tail', '尾部/未识别', img.dataEnd, fileLen, '#475569');
    return R;
  }

  /* ---------------- 像素格式 ---------------- */
  function toRgba8888(data, w, h) {
    const need = w * h * 4;
    const out = new Uint8ClampedArray(need);
    const n = Math.min(w * h, Math.floor(data.length / 4));
    for (let i = 0; i < n; i++) {
      const s = i * 4, o = i * 4;
      out[o] = data[s + 2];     // B,G,R,A -> R,G,B,A
      out[o + 1] = data[s + 1];
      out[o + 2] = data[s];
      out[o + 3] = data[s + 3];
    }
    return out;
  }

  function toRgba1555(data, w, h) {
    const n = w * h;
    const out = new Uint8ClampedArray(n * 4);
    const avail = Math.min(n, Math.floor(data.length / 2));
    for (let i = 0; i < avail; i++) {
      const v = data[2 * i] | (data[2 * i + 1] << 8);
      const r = (v >> 10) & 0x1f, g = (v >> 5) & 0x1f, b = v & 0x1f;
      const o = i * 4;
      out[o] = (r << 3) | (r >> 2);
      out[o + 1] = (g << 3) | (g >> 2);
      out[o + 2] = (b << 3) | (b >> 2);
      out[o + 3] = (v & 0x8000) ? 255 : 0;
    }
    return out;
  }

  function toRgba4444(data, w, h) {
    const n = w * h;
    const out = new Uint8ClampedArray(n * 4);
    const avail = Math.min(n, Math.floor(data.length / 2));
    for (let i = 0; i < avail; i++) {
      const v = data[2 * i] | (data[2 * i + 1] << 8);
      const o = i * 4;
      out[o] = ((v >> 8) & 0xf) * 17;
      out[o + 1] = ((v >> 4) & 0xf) * 17;
      out[o + 2] = (v & 0xf) * 17;
      out[o + 3] = ((v >> 12) & 0xf) * 17;
    }
    return out;
  }

  function toRgbaIndexed(data, w, h, palette) {
    if (!palette) throw new Error('索引帧但 IMG 没有调色板');
    const colors = palette.length >> 2;
    const n = w * h;
    const out = new Uint8ClampedArray(n * 4);
    for (let i = 0; i < n; i++) {
      let idx = i < data.length ? data[i] : 0;
      if (idx >= colors) idx = 0;
      const p = idx * 4, o = i * 4;
      out[o] = palette[p]; out[o + 1] = palette[p + 1];
      out[o + 2] = palette[p + 2]; out[o + 3] = palette[p + 3];
    }
    return out;
  }

  function cropRgba(src, w, h, left, up, cw, ch) {
    if (left === 0 && up === 0 && cw === w && ch === h) return src;
    const out = new Uint8ClampedArray(cw * ch * 4);
    for (let y = 0; y < ch; y++) {
      const s = ((up + y) * w + left) * 4;
      out.set(src.subarray(s, s + cw * 4), y * cw * 4);
    }
    return out;
  }

  /* ---------------- DDS / DXT ---------------- */
  function rgb565(c) {
    const r = (c >> 11) & 0x1f, g = (c >> 5) & 0x3f, b = c & 0x1f;
    return [(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)];
  }

  function decodeDxt(mode, payload, w, h) {
    const bpb = mode === 1 ? 8 : 16;
    const bw = (w + 3) >> 2, bh = (h + 3) >> 2;
    const need = bw * bh * bpb;
    if (payload.length < need) throw new Error('DXT 数据不足：要 ' + need + ' 得 ' + payload.length);
    const out = new Uint8ClampedArray(w * h * 4);
    let pos = 0;
    const a = new Uint8Array(16);
    for (let by = 0; by < bh; by++) {
      for (let bx = 0; bx < bw; bx++) {
        let c;
        if (mode === 3) {
          for (let i = 0; i < 16; i++) {
            const byte = payload[pos + (i >> 1)];
            a[i] = ((i & 1) ? (byte >> 4) : (byte & 0xf)) * 17;
          }
          c = payload.subarray(pos + 8, pos + 16);
        } else if (mode === 5) {
          const a0 = payload[pos], a1 = payload[pos + 1];
          let atab;
          if (a0 > a1) {
            atab = [a0, a1];
            for (let i = 1; i <= 6; i++) atab.push(Math.round(((7 - i) * a0 + i * a1) / 7));
          } else {
            atab = [a0, a1];
            for (let i = 1; i <= 4; i++) atab.push(Math.round(((5 - i) * a0 + i * a1) / 5));
            atab.push(0, 255);
          }
          let lo = 0, hi = 0;
          for (let i = 0; i < 6; i++) { lo |= payload[pos + 2 + i] << (8 * i); }
          // 6 字节 = 48 位，用两个 32 位安全拆
          const lo32 = (payload[pos + 2] | (payload[pos + 3] << 8) | (payload[pos + 4] << 16) | (payload[pos + 5] << 24)) >>> 0;
          const hi16 = payload[pos + 6] | (payload[pos + 7] << 8);
          for (let i = 0; i < 16; i++) {
            const bit = i * 3;
            let idx;
            if (bit < 32) idx = (lo32 >>> bit) & 7;
            else if (bit === 30) idx = ((lo32 >>> 30) | (hi16 << 2)) & 7;
            else idx = (hi16 >>> (bit - 32)) & 7;
            a[i] = atab[idx];
          }
          c = payload.subarray(pos + 8, pos + 16);
        } else {
          for (let i = 0; i < 16; i++) a[i] = 255;
          c = payload.subarray(pos, pos + 8);
        }
        const c0 = c[0] | (c[1] << 8), c1 = c[2] | (c[3] << 8);
        const p0 = rgb565(c0), p1 = rgb565(c1);
        // DXT1/DXT3/DXT5 的**颜色块**都是同一套 4 色插值（2/1 与 1/2 三分）；
        // 只有 alpha 通道的来源不同。之前 DXT3/DXT5 用了 [p0,p1,均值,黑]，
        // 于是颜色索引 3 的像素被画成纯黑 —— 表现为图上撒了一层不规则黑斑。
        const pal = [p0, p1,
          [Math.round((2 * p0[0] + p1[0]) / 3), Math.round((2 * p0[1] + p1[1]) / 3), Math.round((2 * p0[2] + p1[2]) / 3)],
          [Math.round((p0[0] + 2 * p1[0]) / 3), Math.round((p0[1] + 2 * p1[1]) / 3), Math.round((p0[2] + 2 * p1[2]) / 3)]];
        const code = (c[4] | (c[5] << 8) | (c[6] << 16) | (c[7] << 24)) >>> 0;
        for (let i = 0; i < 16; i++) {
          const k = (code >>> (2 * i)) & 3;
          const px = bx * 4 + (i & 3), py = by * 4 + (i >> 2);
          if (px >= w || py >= h) continue;
          const o = (py * w + px) * 4;
          out[o] = pal[k][0]; out[o + 1] = pal[k][1]; out[o + 2] = pal[k][2];
          if (mode === 1) out[o + 3] = (c0 <= c1 && k === 3) ? 0 : 255;
          else out[o + 3] = a[i];
        }
        pos += bpb;
      }
    }
    return out;
  }

  function decodeUncompressedDds(payload, w, h, bits, rm, gm, bm, am) {
    const bpp = bits >> 3;
    const n = w * h;
    if (payload.length < n * bpp) throw new Error('未压缩 DDS 数据不足');
    const out = new Uint8ClampedArray(n * 4);
    function shift(mask) {
      if (!mask) return [0, 255];
      let s = 0;
      while (((mask >>> s) & 1) === 0) s++;
      return [s, (mask >>> s) >>> 0];
    }
    const [rs, rx] = shift(rm), [gs, gx] = shift(gm), [bs, bx] = shift(bm);
    const [as_, ax] = am ? shift(am) : [0, 0];
    const dv = new DataView(payload.buffer, payload.byteOffset, payload.byteLength);
    for (let i = 0; i < n; i++) {
      const off = i * bpp;
      let v = 0;
      for (let k = 0; k < bpp; k++) v |= payload[off + k] << (8 * k);
      const o = i * 4;
      out[o] = rx ? (((v & rm) >>> rs) * 255 / rx) | 0 : 0;
      out[o + 1] = gx ? (((v & gm) >>> gs) * 255 / gx) | 0 : 0;
      out[o + 2] = bx ? (((v & bm) >>> bs) * 255 / bx) | 0 : 0;
      out[o + 3] = (am && ax) ? (((v & am) >>> as_) * 255 / ax) | 0 : 255;
    }
    return out;
  }

  function decodeDdsBlob(blob, w, h, pixelFormat) {
    const dv = new DataView(blob.buffer, blob.byteOffset, blob.byteLength);
    if (asciiAt(blob, 0, 4) !== 'DDS ') {
      // 裸像素
      if (blob.length >= w * h * 4) return { w, h, rgba: toRgba8888(blob, w, h), format: 'raw8888' };
      if (blob.length >= w * h * 2) {
        return { w, h, format: pixelFormat === T_ARGB4444 ? 'raw4444' : 'raw1555',
          rgba: pixelFormat === T_ARGB4444 ? toRgba4444(blob, w, h) : toRgba1555(blob, w, h) };
      }
      throw new Error('DDS 裸数据长度异常：' + blob.length);
    }
    if (blob.length < 128) throw new Error('DDS 头不完整');
    const dh = dv.getUint32(12, true), dw = dv.getUint32(16, true);
    const fourCC = asciiAt(blob, 84, 4);
    const bits = dv.getUint32(88, true);
    const rm = dv.getUint32(92, true), gm = dv.getUint32(96, true);
    const bm = dv.getUint32(100, true), am = dv.getUint32(104, true);
    const start = 128 + (fourCC === 'DX10' ? 20 : 0);
    const payload = blob.subarray(start);
    if (fourCC === 'DXT1') return { w: dw, h: dh, rgba: decodeDxt(1, payload, dw, dh), format: 'DXT1' };
    if (fourCC === 'DXT3') return { w: dw, h: dh, rgba: decodeDxt(3, payload, dw, dh), format: 'DXT3' };
    if (fourCC === 'DXT5') return { w: dw, h: dh, rgba: decodeDxt(5, payload, dw, dh), format: 'DXT5' };
    if (!fourCC.charCodeAt(0) && (bits === 32 || bits === 24 || bits === 16)) {
      return { w: dw, h: dh, rgba: decodeUncompressedDds(payload, dw, dh, bits, rm, gm, bm, am), format: 'raw' + bits };
    }
    throw new Error('不支持的 DDS 格式 fourCC=' + JSON.stringify(fourCC) + ' bits=' + bits);
  }

  async function getDdsTexture(img, ddsIndex) {
    const rec = img.dds[ddsIndex];
    if (!rec) throw new Error('DDS 下标越界：' + ddsIndex);
    if (rec.rgba || rec.error) return rec;
    try {
      let blob = img.bytes.subarray(rec.rawOffset, rec.rawOffset + rec.rawLength);
      if (looksZlib(blob)) blob = await inflateZlib(blob);
      const tex = decodeDdsBlob(blob, rec.width, rec.height, rec.pixelFormat);
      rec.rgba = tex.rgba;
      rec.decodedW = tex.w; rec.decodedH = tex.h; rec.decodedFormat = tex.format;
      rec.blobLength = blob.length;
    } catch (e) { rec.error = e.message || String(e); }
    return rec;
  }

  /* ---------------- 帧解码 ---------------- */
  async function decodeFrame(img, index) {
    if (index < 0 || index >= img.frames.length) throw new Error('帧号超出范围：' + index);
    const real = img.resolved[index];
    if (real < 0) {
      return { w: 1, h: 1, x: 0, y: 0, rgba: new Uint8ClampedArray([0, 0, 0, 0]), empty: true };
    }
    const f = img.frames[real];
    if (img.version === 5 && f.compressed === C_DDSREF) {
      const rec = await getDdsTexture(img, f.ddsIndex);
      if (!rec.rgba) throw new Error(rec.error || 'DDS 解码失败');
      const cw = f.right - f.left, ch = f.down - f.up;
      if (cw < 0 || ch < 0) throw new Error('帧 ' + real + ' 裁剪矩形反了');
      if (cw > rec.decodedW || ch > rec.decodedH) throw new Error('帧 ' + real + ' 裁剪超出贴图');
      return { w: cw, h: ch, x: f.x, y: f.y, rgba: cropRgba(rec.rgba, rec.decodedW, rec.decodedH, f.left, f.up, cw, ch) };
    }
    if (f.bodyOffset < 0) throw new Error('帧 ' + real + ' 没有帧体');
    let data = img.bytes.subarray(f.bodyOffset, f.bodyOffset + f.bodyLength);
    if (f.compressed === C_ZLIB || f.compressed === C_DDSREF) {
      data = await inflateZlib(data);
    } else if (f.compressed !== C_RAW) {
      throw new Error('帧 ' + real + ' 未知压缩方式 0x' + f.compressed.toString(16));
    }
    const w = f.width, h = f.height;
    let rgba;
    if (f.type === T_ARGB8888) rgba = toRgba8888(data, w, h);
    else if (f.type === T_ARGB4444) rgba = toRgba4444(data, w, h);
    else if (f.type === T_ARGB1555) {
      rgba = (img.version === 4 || img.version === 6)
        ? toRgbaIndexed(data, w, h, img.palettes[0])
        : toRgba1555(data, w, h);
    } else if (f.type === T_INDEXED && (img.version === 4 || img.version === 6)) {
      rgba = toRgbaIndexed(data, w, h, img.palettes[0]);
    } else {
      throw new Error('v' + img.version + ' 帧 ' + real + ' 类型 0x' + f.type.toString(16) + ' 不支持');
    }
    return { w, h, x: f.x, y: f.y, rgba };
  }

  /* ---------------- OGG ---------------- */
  function parseOgg(u8) {
    const out = { valid: false, pages: [], channels: 0, sampleRate: 0, version: 0, bitrateNominal: 0,
      serials: [], duration: 0, codec: 'unknown', comment: null, error: null };
    if (asciiAt(u8, 0, 4) !== 'OggS') { out.error = '不是 Ogg 流'; return out; }
    out.valid = true;
    const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
    let pos = 0, lastGranule = 0, seqEnd = -1;
    while (pos + 27 <= u8.length) {
      if (asciiAt(u8, pos, 4) !== 'OggS') { out.error = '在第 ' + out.pages.length + ' 页偏移 ' + pos + ' 处断链'; break; }
      const ver = u8[pos + 4], htype = u8[pos + 5];
      const granule = dv.getBigInt64(pos + 6, true);
      const serial = dv.getUint32(pos + 14, true);
      const seq = dv.getUint32(pos + 18, true);
      const segs = u8[pos + 26];
      const segTable = u8.subarray(pos + 27, pos + 27 + segs);
      let bodyLen = 0;
      for (let i = 0; i < segs; i++) bodyLen += segTable[i];
      const bodyOff = pos + 27 + segs;
      out.pages.push({ offset: pos, size: 27 + segs + bodyLen, version: ver, headerType: htype,
        granule: granule.toString(), serial, seq, segs, bodyLen });
      if (granule > 0n) lastGranule = granule;
      if (out.serials.indexOf(serial) < 0) out.serials.push(serial);
      seqEnd = seq;
      // 解析第一页 body 的 identification header
      if (out.pages.length === 1 && bodyLen >= 30) {
        const b = bodyOff;
        if (u8[b] === 1 && asciiAt(u8, b + 1, 6) === 'vorbis') {
          out.codec = 'Vorbis';
          out.version = dv.getUint32(b + 7, true);
          out.channels = u8[b + 11];
          out.sampleRate = dv.getUint32(b + 12, true);
          out.bitrateMax = dv.getInt32(b + 16, true);
          out.bitrateNominal = dv.getInt32(b + 20, true);
          out.bitrateMin = dv.getInt32(b + 24, true);
        }
      }
      pos = bodyOff + bodyLen;
    }
    out.duration = out.sampleRate ? Number(lastGranule) / out.sampleRate : 0;
    out.lastGranule = lastGranule.toString();
    out.endOffset = pos;
    out.truncated = pos !== u8.length;
    return out;
  }

  /* ---------------- 导出 ---------------- */
  return {
    NPK_MAGIC, IMG_MAGIC, NPK_ENTRY_SIZE,
    TYPE_NAMES, COMP_NAMES,
    decodeName, parseNpkIndex, parseImg, decodeFrame, getDdsTexture,
    decodeDdsBlob, decodeDxt, decodeOgg: parseOgg, inflateZlib, looksZlib,
    isNpk, toRgba8888, toRgba1555, toRgba4444, toRgbaIndexed,
  };
});
