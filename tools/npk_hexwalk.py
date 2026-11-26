#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""npk_hexwalk.py —— 把 NPK / IMG 的二进制结构逐字段打印出来（给文档用）。

不依赖 numpy、不依赖 tools/npk_parser.py 的解析代码（常量与偏移独立实现），
只做「读原始字节 -> 按格式假设切字段 -> 打印 + 自校验」。像素解码不在这里做。

用法:
    python3 tools/npk_hexwalk.py <npk 路径或 ImagePacks2 下的文件名>
    python3 tools/npk_hexwalk.py <npk> --all-entries        # 索引表全打印
    python3 tools/npk_hexwalk.py <npk> --img <img 名>        # 解剖某个 .img
    python3 tools/npk_hexwalk.py <npk> --entry 0             # 按条目号解剖
    python3 tools/npk_hexwalk.py <npk> --dump 0x13c:0x184    # 任意区间 hexdump

只读 NPK，不写任何文件。
"""
import argparse
import hashlib
import os
import struct
import sys
import zlib

NPK_MAGIC = b"NeoplePack_Bill\x00"
IMG_MAGIC = b"Neople Img File\x00"
ENTRY_SIZE = 264                  # i32 offset + i32 size + 256B XOR 名字
SUM_SIZE = 32                     # 索引表之后 32B SHA-256
NAME_KEY = (b"puchikon@neople dungeon and fighter " + b"DNF" * 256)[:255] + b"\x00"

TYPE_NAMES = {
    0x00: "INDEXED?", 0x06: "0x06(遗留)", 0x0E: "ARGB1555/索引",
    0x0F: "ARGB4444", 0x10: "ARGB8888", 0x11: "REFERENCE",
    0x12: "DXT1", 0x13: "DXT3", 0x14: "DXT5",
}
CMP_NAMES = {0x05: "未压缩", 0x06: "zlib", 0x07: "v5-DDS表"}

DEFAULT_PACK_DIR = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"


# ---------------------------------------------------------------- helpers
def resolve_pack(path, pack_dir):
    """文件名可能有大量前导空格，必须用 os.listdir 模糊匹配。"""
    if os.path.isfile(path):
        return path
    if os.path.isdir(pack_dir):
        cand = [os.path.join(pack_dir, n) for n in os.listdir(pack_dir)
                if n.lower() == path.lower()]
        if len(cand) == 1:
            return cand[0]
        cand = [os.path.join(pack_dir, n) for n in os.listdir(pack_dir)
                if path.lower() in n.lower()]
        if len(cand) == 1:
            return cand[0]
        if cand:
            raise SystemExit("匹配到多个：%r" % [os.path.basename(c) for c in cand[:5]])
    raise SystemExit("找不到 NPK: %r" % path)


def unhex(data, offset, width=16):
    """data 是 bytes，offset 是它在文件里的绝对偏移（用于显示地址）。"""
    lines = []
    for i in range(0, len(data), width):
        chunk = data[i:i + width]
        hx = " ".join("%02x" % b for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        lines.append("  0x%08X  %-47s  %s" % (offset + i, hx, asc))
    return "\n".join(lines)


def decode_name(raw256):
    plain = bytes(b ^ NAME_KEY[i] for i, b in enumerate(raw256))
    plain = plain.split(b"\x00", 1)[0]
    for enc in ("gbk", "utf-8"):
        try:
            return plain.decode(enc)
        except UnicodeDecodeError:
            continue
    return plain.decode("latin-1", "replace")


def u32(d, o):
    return struct.unpack_from("<I", d, o)[0]


def i32(d, o):
    return struct.unpack_from("<i", d, o)[0]


def banner(title):
    print("\n" + "=" * 78)
    print(title)
    print("=" * 78)


# ---------------------------------------------------------------- sections
def show_container(path):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        head = f.read(20)
        count = u32(head, 16)
        index = f.read(count * ENTRY_SIZE)
        digest = f.read(SUM_SIZE)
        f.seek(0)
        prefix = f.read(20 + count * ENTRY_SIZE)

    banner("SECTION 1  NPK 容器")
    print("文件            : %s" % path)
    print("大小            : %d 字节 (0x%X)" % (size, size))
    print("magic           : %r" % head[:16])
    print("条目数 n        : %d" % count)
    print("索引表          : [0x%X, 0x%X)  = %d × %d 字节" %
          (20, 20 + count * ENTRY_SIZE, count, ENTRY_SIZE))
    print("SHA-256 校验    : [0x%X, 0x%X)" % (20 + count * ENTRY_SIZE, 20 + count * ENTRY_SIZE + SUM_SIZE))
    data_start = 20 + count * ENTRY_SIZE + SUM_SIZE
    print("数据区起点      : 0x%X (%d)" % (data_start, data_start))

    print("\n[0x00000000, 0x00000014) 头（magic + 条目数）:")
    print(unhex(head, 0, 16))

    print("\n[0x00000014, 0x%08X) 第一条索引项（前 48 字节）:" % (20 + 48))
    print(unhex(index[:48], 20, 16))

    cut = len(prefix) // 17 * 17
    calc = hashlib.sha256(prefix[:cut]).digest()
    ok = calc == digest
    print("\nSHA-256: 存储=%s" % digest.hex())
    print("         计算=%s  (对 [0, 0x%X) 取 len/17*17=%d 字节)" %
          (calc.hex(), cut, cut))
    print("         结论: %s" % ("通过 ✓" if ok else "不匹配 ✗"))

    # 索引项
    entries = []
    for i in range(count):
        b = i * ENTRY_SIZE
        entries.append((i, i32(index, b), i32(index, b + 4),
                        decode_name(index[b + 8:b + ENTRY_SIZE])))

    print("\n索引项（offset, size, 名字）:")
    print("  %-4s %-12s %-12s %s" % ("#", "offset", "size", "name"))
    lim = count if SHOW_ALL else min(count, 8)
    for i, off, sz, nm in entries[:lim]:
        print("  %-4d 0x%-10X %-12d %s" % (i, off, sz, nm))
    if lim < count:
        print("  ...（共 %d 条，--all-entries 全打印）" % count)

    # 数据区连续性
    used = sorted((off, off + sz, nm) for _, off, sz, nm in entries)
    gaps = []
    cur = data_start
    for off, end, nm in used:
        if off != cur:
            gaps.append((cur, off, nm))
        cur = max(cur, end)
    print("\n数据区: 条目 offset 起点=%d%s；%s" % (
        used[0][0] if used else -1,
        "" if not used else ("，与数据区起点%s" % ("一致 ✓" if used[0][0] == data_start else "不一致 ✗")),
        "相邻条目偏移连续 ✓" if not gaps else "发现 %d 处空洞/重叠（首处 0x%X..0x%X, %s）" % (
            len(gaps), gaps[0][0], gaps[0][1], gaps[0][2])))
    print("条目覆盖到文件尾: %s（max(offset+size)=0x%X, 文件大小=0x%X）" % (
        "✓" if used and used[-1][1] == size else "✗", used[-1][1] if used else 0, size))

    return entries, data_start


def find_entry(entries, img=None, idx=None):
    if idx is not None:
        return entries[idx]
    if img:
        low = img.lower()
        for e in entries:
            if e[3].lower() == low:
                return e
        for e in entries:
            if low in e[3].lower():
                return e
    raise SystemExit("没找到指定 img")


def show_img(entries, entry, data_start):
    i, off, sz, name = entry
    if not name.lower().endswith(".img"):
        print("条目 %d 不是 .img：%s（%d 字节），跳过 IMG 解析" % (i, name, sz))
        return
    with open(PACK_PATH, "rb") as f:
        f.seek(off)
        raw = f.read(sz)
    if raw[:16] != IMG_MAGIC:
        print("条目 %d magic 不是 IMG：%r" % (i, raw[:16]))
        return

    banner("SECTION 2  IMG 解剖：%s（NPK 内 offset=0x%X, size=%d）" % (name, off, sz))
    table_len, skip, version, frame_count = struct.unpack_from("<IIII", raw, 16)
    print("IMG 头（32 字节）:")
    print("  +0x00 16B magic        = %r" % raw[:16])
    print("  +0x10 u32 tableLength  = %d  (待校验：疑似=帧记录区总字节数)" % (table_len,))
    print("  +0x14 u32 zero         = %d" % skip)
    print("  +0x18 u32 version      = %d" % version)
    print("  +0x1C u32 frameCount   = %d" % frame_count)
    print("\n原始头 48 字节:")
    print(unhex(raw[:48], off, 16))

    pos = 32
    palettes = []
    dds = []
    if version == 4:
        n = i32(raw, pos); pos += 4
        palettes.append((n, raw[pos:pos + n * 4])); pos += n * 4
        print("\nv4 扩展头: +0x20 colorNum=%d，调色板 %d×4B 紧随其后" % (n, n))
    elif version == 5:
        dds_count, img_len, color_num = struct.unpack_from("<iii", raw, pos); pos += 12
        palettes.append((color_num, raw[pos:pos + color_num * 4])); pos += color_num * 4
        print("\nv5 扩展头: ddsCount=%d, imgLength(未用)=%d, colorNum=%d" % (dds_count, img_len, color_num))
        for k in range(dds_count):
            t, pf, ix, fl, rl, w, h = struct.unpack_from("<7i", raw, pos); pos += 28
            dds.append(dict(title=t, pf=pf, idx=ix, full=fl, raw_len=rl, w=w, h=h, pos=pos - 28))
            print("  DDS[%d] @ +0x%X: title=%d pixelFormat=0x%X index=%d "
                  "fullLength=%d length=%d %dx%d  (%s)" %
                  (k, pos - 28, t, pf, ix, fl, rl, w, h, TYPE_NAMES.get(pf, "?")))
    elif version == 6:
        pc = i32(raw, pos); pos += 4
        print("\nv6 扩展头: paletteCount=%d" % pc)
        for k in range(pc):
            n = i32(raw, pos); pos += 4
            palettes.append((n, raw[pos:pos + n * 4])); pos += n * 4
    else:
        print("\nv%d 无扩展头，帧记录从 +0x20 开始" % version)

    frames = []
    rec_start = pos
    for k in range(frame_count):
        if pos + 4 > len(raw):
            print("帧记录越界：frame %d" % k)
            break
        ftype = i32(raw, pos)
        if ftype == 0x11:
            ref = i32(raw, pos + 4)
            frames.append(dict(k=k, type=ftype, ref=ref, rec=pos, consumed=8))
            pos += 8
            continue
        cmp_, w, h, ln, x, y, fw, fh = struct.unpack_from("<8i", raw, pos + 4)
        fr = dict(k=k, type=ftype, cmp=cmp_, w=w, h=h, len=ln, x=x, y=y,
                  fw=fw, fh=fh, rec=pos, consumed=36, dds=None)
        if version == 5 and (cmp_ == 0x07 or ftype in (0x12, 0x13, 0x14)):
            sk1, dds_ix, left, up, right, down, sk2 = struct.unpack_from("<7i", raw, pos + 36)
            fr.update(dds=dict(ix=dds_ix, left=left, up=up, right=right, down=down),
                      consumed=64)
        pos += fr["consumed"]
        frames.append(fr)

    rec_bytes = pos - rec_start
    verdict = "✓ 与 tableLength 一致" if rec_bytes == table_len else "✗ 与 tableLength 不一致（差 %d）" % (table_len - rec_bytes)
    print("\n[tableLength 校验] 声明=%d，实测记录区 +0x%X..+0x%X = %d 字节，%s" %
          (table_len, rec_start, pos, rec_bytes, verdict))
    banner("SECTION 3  帧记录（%d 帧，记录区 +0x%X..+0x%X）" % (len(frames), rec_start, pos))
    print("  %-4s %-14s %-9s %-5s %-5s %-9s %-8s %-8s %s" %
          ("#", "type", "cmp", "w", "h", "length", "x", "y", "fw×fh"))
    for fr in frames[:FRAME_LIMIT]:
        tn = TYPE_NAMES.get(fr["type"], "0x%02X" % fr["type"])
        if fr["type"] == 0x11:
            print("  %-4d %-14s (指向帧 -> %d，8 字节记录)" % (fr["k"], tn, fr["ref"]))
        else:
            line = "  %-4d %-14s 0x%02X %-9d %-5d %-5d %-9d %-8d %s" % (
                fr["k"], tn, fr["cmp"], fr["w"], fr["h"], fr["len"],
                fr["x"], fr["y"], "%d×%d" % (fr["fw"], fr["fh"]))
            if fr["dds"]:
                line += "  DDS#%d crop[%d,%d)-[%d,%d)" % (
                    fr["dds"]["ix"], fr["dds"]["left"], fr["dds"]["up"],
                    fr["dds"]["right"], fr["dds"]["down"])
            print(line)
    if len(frames) > FRAME_LIMIT:
        print("  ...（共 %d 帧，只打印前 %d）" % (len(frames), FRAME_LIMIT))

    if frames:
        print("\n首帧记录原始字节（%d 字节）:" % frames[0]["consumed"])
        print(unhex(raw[frames[0]["rec"]:frames[0]["rec"] + frames[0]["consumed"]],
                    off + frames[0]["rec"], 16))

    # 帧体
    body = pos
    if dds:
        print("\n[DDS 裸数据] 起点 +0x%X" % body)
        for k, rec in enumerate(dds):
            blob = raw[body:body + rec["full"]]
            head = blob[:4]
            note = ""
            if head[:2] in (b"\x78\x01", b"\x78\x9c", b"\x78\xda"):
                try:
                    out = zlib.decompress(blob)
                    note = "zlib -> %d 字节，开头 %r" % (len(out), out[:4])
                except zlib.error as e:
                    note = "zlib 解压失败: %s" % e
            print("  DDS[%d] +0x%X..+0x%X (%d 字节) %s %s" %
                  (k, body, body + rec["full"], rec["full"], blob[:8].hex(), note))
            body += rec["full"]

    print("\n[帧体区] 起点 +0x%X" % body)
    for fr in frames:
        if fr["type"] == 0x11:
            continue
        if fr.get("dds"):
            if fr["k"] < FRAME_LIMIT:
                print("  frame %-4d: 体在 DDS[%d]（本帧无字节）" % (fr["k"], fr["dds"]["ix"]))
            continue
        ln = fr["len"]
        if fr["cmp"] == 0x05:
            bpp = 4 if fr["type"] == 0x10 else (1 if (fr["type"] == 0x0E and version in (4, 6)) else 2)
            exp = fr["w"] * fr["h"] * bpp
            if exp != ln and fr["k"] < FRAME_LIMIT:
                print("  frame %-4d: 声明 length=%d，但 w×h×%dB=%d  → 以几何为准（语料有脏 length）" %
                      (fr["k"], ln, bpp, exp))
            ln = exp
        blob = raw[body:body + ln]
        if fr["k"] < FRAME_LIMIT:
            info = ""
            if fr["cmp"] == 0x06 and blob[:2] in (b"\x78\x01", b"\x78\x9c", b"\x78\xda"):
                try:
                    out = zlib.decompress(blob)
                    _bpp = 4 if fr["type"] == 0x10 else (1 if (fr["type"] == 0x0E and version in (4, 6)) else 2)
                    info = "zlib 头=%s 解压后=%d 字节 (w×h×bpp=%d)" % (blob[:2].hex(), len(out), fr["w"] * fr["h"] * _bpp)
                except zlib.error as e:
                    info = "zlib 解压失败: %s" % e
            print("  frame %-4d +0x%X..+0x%X (%d 字节) 头=%s %s" %
                  (fr["k"], body, body + ln, ln, blob[:8].hex(), info))
            print("           " + unhex(blob[:32], off + body, 16).replace("\n", "\n           "))
        body += ln

    print("\n[对齐检查] 帧体结束 +0x%X，IMG 声明 size=%d (0x%X)，%s" %
          (body, sz, sz, "完全对齐 ✓" if body == sz else "差 %d 字节" % (sz - body)))


# ---------------------------------------------------------------- main
def main():
    global SHOW_ALL, FRAME_LIMIT, PACK_PATH
    ap = argparse.ArgumentParser(description="NPK/IMG 逐字段十六进制解剖")
    ap.add_argument("npk")
    ap.add_argument("--pack-dir", default=DEFAULT_PACK_DIR)
    ap.add_argument("--all-entries", action="store_true")
    ap.add_argument("--img", default=None, help="IMG 名字（可模糊）")
    ap.add_argument("--entry", type=int, default=None, help="条目序号")
    ap.add_argument("--dump", default=None, help="额外 hexdump 区间，如 0x13c:0x184")
    ap.add_argument("--frame-limit", type=int, default=12)
    args = ap.parse_args()

    SHOW_ALL = args.all_entries
    FRAME_LIMIT = args.frame_limit
    PACK_PATH = resolve_pack(args.npk, args.pack_dir)
    entries, data_start = show_container(PACK_PATH)

    if args.dump:
        a, b = args.dump.split(":")
        a, b = int(a, 0), int(b, 0)
        with open(PACK_PATH, "rb") as f:
            f.seek(a); blob = f.read(b - a)
        banner("SECTION X  区间 hexdump [0x%X, 0x%X)" % (a, b))
        print(unhex(blob, a, 16))

    if args.img is not None or args.entry is not None:
        entry = find_entry(entries, args.img, args.entry)
        show_img(entries, entry, data_start)
    else:
        imgs = [e for e in entries if e[3].lower().endswith(".img")]
        if imgs:
            print("\n（未指定 --img/--entry，默认解剖第 1 个 .img）")
            show_img(entries, imgs[0], data_start)


SHOW_ALL = False
FRAME_LIMIT = 12
PACK_PATH = None

if __name__ == "__main__":
    main()
