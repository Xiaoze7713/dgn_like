#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""旧版 IMG（v1，"Neople Image File\\0"）的独立解析 / 校验 / 导出工具。

和 v2 的最大区别（详见 docs/NPK-FRAME-BYTES.md §4.4）：

    v2: 32B 头（含 tableLength） + 全部帧记录 + 全部帧体
    v1: 32B 头（**无** tableLength） + [36B/8B 记录][该帧帧体] 交替到文件末尾

    头 = "Neople Image File\\0"(18B) + 6B 零 + u32 version(=1) + u32 frameCount

用法：
    # 1) 全语料校验：把每个 v1 条目按上面的模型走一遍，看是否精确对齐
    python3 tools/npk_v1_walk.py verify

    # 2) 列出一个包里所有 v1 条目
    python3 tools/npk_v1_walk.py list "!!!!!!!!!!!!!!!!!!整合的NPK.NPK"

    # 3) 导出某个 v1 条目的帧（PNG）
    python3 tools/npk_v1_walk.py dump "<pack.npk>" <条目名或序号> --out DIR --frames 0-3
"""
import argparse
import os
import struct
import sys
import zlib

MAGIC_V2 = b"Neople Img File\x00"      # 16B，v2/v5
MAGIC_V1 = b"Neople Image File\x00"    # 18B，旧版（注意多一个 "g"）
KEY = (b"puchikon@neople dungeon and fighter " + b"DNF" * 256)[:255] + b"\x00"
DEFAULT_DIR = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"

BPP = {0x0E: 2, 0x0F: 2, 0x10: 4, 0x12: 8, 0x13: 16, 0x14: 16}


class Npk:
    """够用就行的只读 NPK 访问器（不依赖 tools/npk_parser.py）。"""

    def __init__(self, path):
        if not os.path.exists(path):           # 允许只给文件名，默认在语料目录里找
            alt = os.path.join(DEFAULT_DIR, os.path.basename(path))
            if os.path.exists(alt):
                path = alt
        self.path = path
        with open(path, "rb") as f:
            head = f.read(20)
            if head[:16] != b"NeoplePack_Bill\x00":
                raise ValueError("不是 NPK：magic 不符")
            n = struct.unpack_from("<I", head, 16)[0]
            idx = f.read(n * 264)
        self.entries = []  # [(offset, size, name)]
        for i in range(n):
            off, size = struct.unpack_from("<ii", idx, i * 264)
            name = bytes(a ^ b for a, b in zip(idx[i * 264 + 8:i * 264 + 264], KEY))
            self.entries.append((off, size, name.split(b"\x00")[0].decode("gbk", "replace")))

    def read(self, idx):
        off, size, _ = self.entries[idx]
        with open(self.path, "rb") as f:
            f.seek(off)
            return f.read(size)

    def v1_entries(self):
        out = []
        with open(self.path, "rb") as f:
            for i, (off, size, name) in enumerate(self.entries):
                if size < 32:
                    continue
                f.seek(off)
                if f.read(18) == MAGIC_V1:
                    out.append((i, name, off, size))
        return out


def parse_v1(raw):
    """解析一个 v1 IMG，返回 (version, frameCount, records, 走完的偏移)。

    records: [(kind, data)]，kind 为 "img" 时 data=(type,cmp,w,h,length,x,y,fw,fh,body_off)，
             "ref" 时 data=(link_to,)；body_off 是帧体在 raw 里的偏移。
    """
    if raw[:18] != MAGIC_V1:
        raise ValueError("magic 不是 Neople Image File")
    version, frame_count = struct.unpack_from("<II", raw, 24)
    pos = 32
    recs = []
    for i in range(frame_count):
        ftype = struct.unpack_from("<i", raw, pos)[0]
        if ftype == 0x11:  # 指向帧：8B，无帧体
            _, link = struct.unpack_from("<2i", raw, pos)
            pos += 8
            recs.append(("ref", (link,)))
            continue
        t, c, w, h, length, x, y, fw, fh = struct.unpack_from("<9i", raw, pos)
        pos += 36
        body_off = pos
        if c == 5:  # 未压缩：length 可能是脏数据，按几何算
            pos += w * h * BPP.get(t, 4)
        else:       # zlib：按 length
            pos += length
        recs.append(("img", (t, c, w, h, length, x, y, fw, fh, body_off)))
    return version, frame_count, recs, pos


def walk_exact(raw):
    """按 v1 模型走一遍，返回 (是否精确对齐, 走到的偏移, 条目 size)。"""
    _, _, _, end = parse_v1(raw)
    return end == len(raw), end, len(raw)


def frame_bytes(raw, rec):
    """取一帧解压后的原始像素字节。"""
    t, c, w, h, length, x, y, fw, fh, off = rec
    blob = raw[off:off + length]
    if c == 6:
        blob = zlib.decompress(blob)
    need = w * h * BPP.get(t, 4)
    if len(blob) < need:  # 脏数据/截断：补零更划算
        blob += b"\x00" * (need - len(blob))
    return blob[:need]


def to_rgba(data, t, w, h):
    """v1 的像素规则与 v2 相同：8888 = B,G,R,A；1555 = A1R5G5B5；4444 = A4R4G4B4。"""
    px = bytearray(w * h * 4)
    if t == 0x10:
        for k in range(w * h):
            px[4 * k] = data[4 * k + 2]
            px[4 * k + 1] = data[4 * k + 1]
            px[4 * k + 2] = data[4 * k]
            px[4 * k + 3] = data[4 * k + 3]
    elif t == 0x0E:
        for k in range(w * h):
            v = data[2 * k] | (data[2 * k + 1] << 8)
            a = 255 if v & 0x8000 else 0
            r = (v >> 10) & 31
            g = (v >> 5) & 31
            b = v & 31
            px[4 * k] = (r << 3) | (r >> 2)
            px[4 * k + 1] = (g << 3) | (g >> 2)
            px[4 * k + 2] = (b << 3) | (b >> 2)
            px[4 * k + 3] = a
    elif t == 0x0F:
        for k in range(w * h):
            v = data[2 * k] | (data[2 * k + 1] << 8)
            a = ((v >> 12) & 0xF) * 17
            r = ((v >> 8) & 0xF) * 17
            g = ((v >> 4) & 0xF) * 17
            b = (v & 0xF) * 17
            px[4 * k:4 * k + 4] = bytes((r, g, b, a))
    else:
        raise ValueError("v1 工具只处理 0x0E/0x0F/0x10，遇到 type=0x%02X" % t)
    return bytes(px)


def save_png(path, rgba, w, h):
    from PIL import Image
    Image.frombytes("RGBA", (w, h), rgba).save(path)


def parse_frames_spec(spec, total):
    if not spec:
        return list(range(min(total, 1)))
    out = []
    for part in spec.split(","):
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    return [i for i in out if 0 <= i < total]


def cmd_verify(args):
    dirs = [args.dir] if args.dir else [DEFAULT_DIR]
    total = exact = 0
    fails = []
    for d in dirs:
        for fn in sorted(os.listdir(d)):
            if not fn.lower().endswith(".npk"):
                continue
            try:
                pk = Npk(os.path.join(d, fn))
                v1s = pk.v1_entries()
            except Exception:
                continue
            for idx, name, off, size in v1s:
                total += 1
                raw = pk.read(idx)
                try:
                    ok, end, sz = walk_exact(raw)
                except Exception as e:
                    ok, end, sz = False, -1, size
                if ok:
                    exact += 1
                else:
                    fails.append((fn, name, size, end))
    print("v1 条目 %d 个，按模型精确走完 %d 个（%s）" %
          (total, exact, "100%" if exact == total else "%.1f%%" % (100.0 * exact / total)))
    for f in fails[:20]:
        print("  未对齐：", f[0], f[1], "size", f[2], "end", f[3])
    return 0 if exact == total else 1


def cmd_list(args):
    pk = Npk(args.pack)
    v1s = pk.v1_entries()
    print("%s：%d 个条目，其中 v1 共 %d 个" % (args.pack, len(pk.entries), len(v1s)))
    for idx, name, off, size in v1s:
        print("  #%-5d off=0x%08X size=%-9d %s" % (idx, off, size, name))
    return 0


def cmd_dump(args):
    pk = Npk(args.pack)
    if args.which.isdigit():
        idx = int(args.which)
        name = pk.entries[idx][2]
    else:
        name = args.which
        hits = [i for i, (o, s, n) in enumerate(pk.entries) if n == name]
        if not hits:
            print("找不到条目：", name)
            return 2
        idx = hits[0]
    raw = pk.read(idx)
    version, frame_count, recs, end = parse_v1(raw)
    print("# %s：v%d，%d 帧，解析走完 %d / 条目 %d 字节" % (name, version, frame_count, end, len(raw)))
    os.makedirs(args.out, exist_ok=True)
    stem = os.path.basename(name).replace(".img", "")
    wanted = set(parse_frames_spec(args.frames, frame_count))
    for i, (kind, data) in enumerate(recs):
        if kind != "img":
            print("  #%d 指向帧 linkTo=%d（跳过）" % (i, data[0]))
            continue
        if i not in wanted:
            continue
        rec = data
        t, c, w, h, length, x, y, fw, fh, off = rec
        try:
            rgba = to_rgba(frame_bytes(raw, rec), t, w, h)
        except Exception as e:
            print("  #%d 解码失败：%s" % (i, e))
            continue
        path = os.path.join(args.out, "%s_%03d.png" % (stem, i))
        save_png(path, rgba, w, h)
        print("  #%d 0x%02X %dx%d -> %s" % (i, t, w, h, path))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="v1（Neople Image File）IMG 解析/校验/导出")
    sub = ap.add_subparsers(dest="cmd", required=True)

    v = sub.add_parser("verify", help="全语料校验 v1 布局是否精确对齐")
    v.add_argument("--dir", help="ImagePacks2 目录（默认 sf115）")
    v.set_defaults(func=cmd_verify)

    l = sub.add_parser("list", help="列出包里的 v1 条目")
    l.add_argument("pack")
    l.set_defaults(func=cmd_list)

    d = sub.add_parser("dump", help="导出 v1 条目的帧为 PNG")
    d.add_argument("pack")
    d.add_argument("which", help="条目名，或索引号")
    d.add_argument("--out", required=True)
    d.add_argument("--frames", help="如 0-3 或 0,2,5（默认第 0 帧）")
    d.set_defaults(func=cmd_dump)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
