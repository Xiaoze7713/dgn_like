import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const C = require('../core/npk_core.js');
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const exp = JSON.parse(fs.readFileSync(path.join(__dirname, 'expected.json'), 'utf8'));

let pass = 0, fail = 0;
function ok(cond, msg) {
  if (cond) pass++;
  else { fail++; console.error('  ✗ ' + msg); }
}
function eq(a, b, msg) {
  const ja = JSON.stringify(a), jb = JSON.stringify(b);
  if (ja === jb) pass++;
  else { fail++; console.error('  ✗ ' + msg + '\n      got ' + ja + '\n      exp ' + jb); }
}
const sha = (u8) => crypto.createHash('sha256').update(Buffer.from(u8.buffer, u8.byteOffset, u8.byteLength)).digest('hex');
const readFile = (p) => new Uint8Array(fs.readFileSync(p));

const CACHE = new Map();
function npkAt(p) {
  if (!CACHE.has(p)) CACHE.set(p, C.parseNpkIndex(readFile(p)));
  return CACHE.get(p);
}

console.log('== NPK 索引');
for (const [key, info] of Object.entries(exp.npks)) {
  const npk = npkAt(info.path);
  eq(npk.count, info.entries.length, key + ' count');
  eq(npk.entries.map(e => [e.name, e.offset, e.size]), info.entries, key + ' entries');
  console.log(`  ${key}: ${npk.count} entries, indexEnd=${npk.indexEnd}`);
}

console.log('== IMG 帧与像素');
for (const [key, info] of Object.entries(exp.imgs)) {
  const npk = npkAt(info.path);
  const entry = npk.entries.find(e => e.name === info.entry);
  ok(!!entry, key + ' 找到条目');
  if (!entry) continue;
  const raw = readFile(info.path).subarray(entry.offset, entry.offset + entry.size);
  eq(raw.length, info.size, key + ' 条目大小');
  const img = C.parseImg(raw);
  img.bytes = raw;
  eq(img.version, info.version, key + ' version');
  eq(img.frames.length, info.frameCount, key + ' frameCount');
  eq(img.dataEnd, raw.length, key + ' 数据区走完精确对齐');
  eq(img.palettes.map(p => p.length), info.paletteSizes, key + ' 调色板大小');
  if (info.dds.length) {
    eq(img.dds.map(d => ({ title: d.title, pixel_format: d.pixelFormat, full_length: d.fullLength, length: d.length, width: d.width, height: d.height })), info.dds, key + ' DDS 表');
  }
  for (let i = 0; i < img.frames.length; i++) {
    const f = img.frames[i], e = info.frames[i];
    const got = [f.type, f.compressed, f.width, f.height, f.x, f.y, f.canvasW, f.canvasH,
      f.length, f.type === 0x11 ? f.reference : -1, f.ddsIndex,
      [f.left, f.up, f.right, f.down]];
    const want = [e.type, e.compressed, e.w, e.h, e.x, e.y, e.cw, e.ch,
      e.length, e.ref, e.dds, e.crop];
    if (JSON.stringify(got) !== JSON.stringify(want)) {
      fail++; console.error(`  ✗ ${key} 帧 ${i} 字段\n      got ${JSON.stringify(got)}\n      exp ${JSON.stringify(want)}`);
      continue;
    }
    const out = await C.decodeFrame(img, i);
    eq([out.w, out.h], [e.ow, e.oh], `${key} 帧 ${i} 输出尺寸`);
    eq(sha(out.rgba), e.sha256, `${key} 帧 ${i} 像素`);
  }
  console.log(`  ${key}: v${img.version}, ${img.frames.length} 帧 ✓`);
}

console.log('== v4 未压缩 0x0E 帧（ARGB1555 体长对齐）');
{
  const pack = exp.v4pack;
  const npk = npkAt(pack.path);
  let n = 0, frames = 0;
  for (const e of npk.entries) {
    const raw = readFile(pack.path).subarray(e.offset, e.offset + e.size);
    const img = C.parseImg(raw);
    img.bytes = raw;
    ok(img.dataEnd === raw.length, `${e.name} 体长精确对齐（差 ${img.dataEnd - raw.length}）`);
    const out = await C.decodeFrame(img, 0);
    ok(out.rgba.length === out.w * out.h * 4, `${e.name} 首帧可解码`);
    n++; frames += img.frames.length;
  }
  ok(n === 60, 'v4 包 60 个条目');
  console.log(`  ${n} 个 v4 IMG / ${frames} 帧全部对齐 ✓`);
}

console.log('== OGG');
for (const [key, info] of Object.entries(exp.oggs)) {
  const npk = npkAt(info.path);
  const entry = npk.entries.find(e => e.name === info.entry);
  ok(!!entry, key + ' 条目');
  const raw = readFile(info.path).subarray(entry.offset, entry.offset + entry.size);
  eq(raw.length, info.size, key + ' 大小');
  eq(sha(raw), info.sha256, key + ' 原始字节');
  const ogg = C.decodeOgg(raw);
  eq([ogg.valid, ogg.channels, ogg.sampleRate], [true, info.channels, info.sampleRate], key + ' 头信息');
  console.log(`  ${key}: ${ogg.codec} ${ogg.channels}ch ${ogg.sampleRate}Hz ${ogg.duration.toFixed(3)}s ${ogg.pages.length} 页`);
}

console.log(`\n${pass} 通过, ${fail} 失败`);
process.exit(fail ? 1 : 0);
