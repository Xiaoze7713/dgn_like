#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""make_test_pvf.py — 造一个「迷你 PVF」给 Godot 侧自测用（秒级，不碰 141 MB 目录树）

产物（默认 /tmp/pvf_test/）：
    mini.pvf        ~几十 KB 的合法容器
    expected.json   Python 侧真值（GDScript 测试逐项对比）

mini.pvf 里放三类文件，覆盖三套解析器：
    1. stringtable.bin           **裁剪版**：只留被下面文档引用到的字符串，下标重编
    2. 两个真实文档              .equ（装备）/ .chr（角色），段名是真的
    3. 一个真实动画              character/swordman/animation/move.ani
    4. test/synthetic.act        自造文档，专门覆盖 Int/Float/String 三种值类型

为什么要裁剪 stringtable：真实表 93 MB（146 万条），塞不进最小夹具。
裁剪 = 把「被引用到的字符串」按原顺序重编号，并把文档记录里的下标原地改写；
下标只在 5 字节记录的第 2~5 字节，改写不改变长度，所以文档结构完全不变。

打包含义（与解包对称）：
    plain  = ror32(cipher ^ 0x81A79011 ^ key, 6)
    cipher = rol32(plain, 6) ^ 0x81A79011 ^ key
"""
from __future__ import annotations

import argparse
import json
import re
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASSWORD_PVF = 0x81A79011
GUID = b"fa08bf71-4395-6a4b-a3e3-2617c9fee116"

REAL_FILES = [
    "character/swordman/animation/move.ani",
    "equipment/character/swordman/avatar/coat/acoat_default.equ",
    "character/swordman/swordman.chr",
]
SYNTHETIC_PATH = "test/synthetic.act"

# 引用字符串的类型：5 Section / 6 Command / 7 String / 8 CommandSeparator / 10 StringLink
REF_TYPES = (5, 6, 7, 8, 10)


def ror32(v, n):
    return ((v >> n) | (v << (32 - n))) & 0xFFFFFFFF


def rol32(v, n):
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def decrypt(data: bytes, key: int) -> bytes:
    mix = (PASSWORD_PVF ^ key) & 0xFFFFFFFF
    out = bytearray(data)
    for i in range(len(out) // 4):
        v = struct.unpack_from("<I", out, i * 4)[0]
        struct.pack_into("<I", out, i * 4, ror32(v ^ mix, 6))
    return bytes(out)


def encrypt(data: bytes, key: int) -> bytes:
    mix = (PASSWORD_PVF ^ key) & 0xFFFFFFFF
    out = bytearray(data)
    for i in range(len(out) // 4):
        v = struct.unpack_from("<I", out, i * 4)[0]
        struct.pack_into("<I", out, i * 4, rol32(v, 6) ^ mix)
    return bytes(out)


def pad4(data: bytes) -> bytes:
    rem = len(data) % 4
    return data if rem == 0 else data + b"\x00" * (4 - rem)


def scan_refs(doc: bytes):
    """返回 [(记录起始偏移, 类型, 下标)]，按扫描顺序"""
    out, off = [], 2
    while off < len(doc):
        t = doc[off]
        off += 1
        if 2 <= t <= 10:
            if off + 4 > len(doc):
                break
            out.append((off - 1, t, struct.unpack_from("<i", doc, off)[0]))
            off += 4
        else:
            # 非记录字节：按参考实现的做法跳过（正常文件不会出现）
            continue
    return out


def rewrite_indices(doc: bytes, mapping: dict) -> bytes:
    buf = bytearray(doc)
    for pos, t, idx in scan_refs(doc):
        if t in REF_TYPES:
            buf[pos + 1:pos + 5] = struct.pack("<i", mapping.get(idx, 0))
    return bytes(buf)


def build_stringtable(strings) -> bytes:
    """stringtable.bin = i32 count + (count+1)×i32 偏移 + 串区（串区是纯拼接，没有长度头）

    解析器读法：start = buf[i*4+4]、end = buf[i*4+8]，正文 = buf[start+4 : start+4+(end-start)]。
    因此写入时 offs[i] = 文本起点 - 4，且 end_i(=offs[i+1]) - start_i 恰好等于第 i 条的字节数。
    """
    count = len(strings)
    base = 4 + (count + 1) * 4            # 串区起点
    offs, blob = [], b""
    for s in strings:
        # 真实表的 offset 语义：offs[i] = 文本起点 - 4（文本本身不带长度头）
        offs.append(base + len(blob) - 4)
        blob += s.encode("gb18030", "replace")
    offs.append(base + len(blob) - 4)
    out = bytearray(struct.pack("<i", count))
    for v in offs:
        out += struct.pack("<i", v)
    out += blob
    return bytes(out)


def build_synthetic_doc(strings: list) -> bytes:
    """自造文档：head(2) + 5 字节记录流，覆盖 Section/String/Int/Float。

    strings 用「待分配的表」，函数会把需要的串追加进去并返回 (doc, strings)。
    """
    def add(s: str) -> int:
        strings.append(s)
        return len(strings) - 1

    i_name = add("[name]")
    i_title = add("synthetic test doc")
    i_hello = add("hello")
    i_end_name = add("[/name]")
    i_items = add("[items]")
    i_end_items = add("[/items]")
    i_tail = add("[tail]")

    def sec(i):
        return bytes([5]) + struct.pack("<i", i)

    def s(i):
        return bytes([7]) + struct.pack("<i", i)

    def n(v):
        return bytes([2]) + struct.pack("<i", v)

    def f(v):
        return bytes([4]) + struct.pack("<I", struct.unpack("<I", struct.pack("<f", v))[0])

    buf = bytearray(b"\x00\x00")
    buf += sec(i_name) + s(i_title) + s(i_hello) + n(42) + f(1.5) + sec(i_end_name)
    buf += sec(i_items) + sec(i_end_items)          # 空段
    buf += sec(i_tail)                              # 无闭标签的段
    return bytes(buf)



FLOAT_RE = re.compile(r"^-?\d+\.\d+(?:[eE][-+]?\d+)?$")


def _godot_num(line: str) -> str:
    """把「整行就是一个浮点数」的行改成 Godot `str(float)` 的写法（15 位有效数字）。"""
    pad = len(line) - len(line.lstrip("\t"))
    body = line[pad:]
    if FLOAT_RE.match(body):
        v = "%.15g" % float(body)
        if "." not in v and "e" not in v and "E" not in v:
            v += ".0"                     # Godot 的 str(180.0) == "180.0"
        return "\t" * pad + v
    return line


class ShimArchive:
    """给 parse_document 用的最小外壳：它只用到 string_bin / string_map。"""

    def __init__(self, strings):
        self.string_bin = [s.lower() for s in strings]
        self.string_map = {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pvf", default="/mnt/e/dnf-sf/sf115/Script.pvf")
    ap.add_argument("--out", default="/tmp/pvf_test")
    args = ap.parse_args()

    from pvf_unpack import PvfArchive, parse_animation, parse_document  # noqa: E402

    ar = PvfArchive(args.pvf)
    full_bin = ar.string_bin                # 93 MB 的表，只在这里读一次
    print(f"  真实字符串表：{len(full_bin)} 条")

    # ---- 1. 真实文件 ----
    real = []
    for p in REAL_FILES:
        raw = ar.read_raw(ar.entry(p))
        real.append((p, raw))
        print(f"  + {p:62s} {len(raw):7d} B")

    # ---- 2. 收集所有被引用的字符串下标 ----
    used = set()
    for _p, raw in real:
        if _p.lower().endswith(".ani"):
            continue
        for _pos, t, idx in scan_refs(raw):
            if t in REF_TYPES:
                used.add(idx)
    used = sorted(i for i in used if 0 <= i < len(full_bin))
    print(f"  被引用字符串：{len(used)} 条（全表 {len(full_bin)} 条）")

    # ---- 3. 重编号 ----
    strings = [""]                          # 0 号留空
    mapping = {}
    for old in used:
        mapping[old] = len(strings)
        strings.append(full_bin[old])
    docs = []
    for p, raw in real:
        if p.lower().endswith(".ani"):
            docs.append((p, raw))
        else:
            docs.append((p, rewrite_indices(raw, mapping)))

    # ---- 4. 自造文档（追加串到同一张表）----
    syn = build_synthetic_doc(strings)
    docs.append((SYNTHETIC_PATH, syn))

    st = build_stringtable(strings)
    files = [("stringtable.bin", st)] + docs
    print(f"  裁剪后字符串表：{len(strings)} 条 / {len(st)} B")

    # ---- 5. 打包 ----
    placed, bodies, rel = [], [], 0
    for path, data in files:
        crc = zlib.crc32(pad4(data)) & 0xFFFFFFFF
        placed.append((path, data, rel, crc))
        bodies.append(pad4(data))
        rel += len(pad4(data))

    tree = bytearray()
    for i, (path, data, off, crc) in enumerate(placed):
        pb = path.encode("ascii")
        tree += struct.pack("<I", i)
        tree += struct.pack("<i", len(pb)) + pb
        tree += struct.pack("<i", len(data))
        tree += struct.pack("<I", crc)
        tree += struct.pack("<i", off)
    tree = pad4(bytes(tree))
    checksum = zlib.crc32(tree) & 0xFFFFFFFF

    out = bytearray(struct.pack("<i", len(GUID)) + GUID)
    out += struct.pack("<i", 53579)
    out += struct.pack("<i", len(tree))
    out += struct.pack("<I", checksum)
    out += struct.pack("<i", len(placed))
    out += encrypt(tree, checksum)
    for pl, body in zip(placed, bodies):
        out += encrypt(body, pl[3])

    os.makedirs(args.out, exist_ok=True)
    pvf_path = os.path.join(args.out, "mini.pvf")
    with open(pvf_path, "wb") as f:
        f.write(out)
    print(f"写出 {pvf_path}：{len(out)} B，{len(placed)} 条")

    # ---- 6. Python 侧真值 ----
    exp = {
        "file_version": 53579,
        "num_files": len(placed),
        "data_start": 56 + len(tree),
        "string_count": len(strings),
        "paths": [p for p, _, _, _ in placed],
        "documents": {},
        "animations": {},
    }
    shim = ShimArchive(strings)
    for path, data in files:
        low = path.lower()
        if low.endswith(".ani"):
            ani = parse_animation(data, "gb18030")
            exp["animations"][path] = {
                "frame_count": ani["frame_count"],
                "sprites": ani["sprites"],
                "params": ani["params"],
                "exact": ani["bytes_consumed"] == ani["bytes_total"],
                "frames": [
                    {
                        "img_id": fr["img_id"], "img_param": fr.get("img_param"),
                        "x": fr["x"], "y": fr["y"], "delay": fr.get("delay", 0),
                        "damage_box": fr["damage_box"], "attack_box": fr["attack_box"],
                    }
                    for fr in ani["frames"]
                ],
            }
        elif low.endswith(".bin"):
            continue
        else:
            node = parse_document(data, shim)
            # 浮点按 Godot str() 的 15 位有效数字重排，避免与 GDScript 侧逐字符比较时假失败
            text = "\n".join(_godot_num(t.replace("    ", "\t")) for t in node.to_text(0))
            exp["documents"][path] = {
                "text": text,
                # 非 ASCII 段折叠成单个 "@"：GDScript 没有 big5/gb18030 解码器，
                # 中文会退化成乱码，这一列用于在「结构完全一致」的前提下做自动化比对
                "text_masked": re.sub(r"[^\x00-\x7f]+", "@", text),
                "sections": [c[1].name if isinstance(c, tuple) else c.name for c in node.children],
            }

    exp_path = os.path.join(args.out, "expected.json")
    with open(exp_path, "w", encoding="utf-8") as f:
        json.dump(exp, f, ensure_ascii=False, indent=1)
    print(f"写出 {exp_path}（文档 {len(exp['documents'])} / 动画 {len(exp['animations'])}）")
    for p, d in exp["documents"].items():
        print(f"    {p}: {len(d['text'].splitlines())} 行，顶层段 {d['sections'][:6]}")


if __name__ == "__main__":
    main()
