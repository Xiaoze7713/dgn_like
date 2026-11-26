#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pvf_string_census.py — 字符串表体检：编码分布 + 真正读不出来的条目

输出到 analysis/pvf/broken/：
  summary.txt          编码分布、可疑区间、每条路径的原始字节与三种候选解码
  nonascii-paths.tsv   目录树里含非 ASCII 的路径（原始字节 / gbk / big5 / cp949 / 最终）
  broken-strings.tsv   解不出来或结果里带私用区/扩展A/兼容字模的可疑字符串
"""
from __future__ import annotations

import importlib.util
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvf_unpack as pu                                   # noqa: E402

spec = importlib.util.spec_from_file_location("pvf_to_utf8", os.path.join(HERE, "pvf_to_utf8.py"))
M = importlib.util.module_from_spec(spec)
spec.loader.exec_module(M)

OUT = os.environ.get("PVF_CENSUS_OUT", "analysis/pvf/broken")
CODECS = ("gb18030", "big5hkscs", "cp949", "utf-8", "shift_jis")


def suspicious(t: str):
    """返回第一个可疑码位（私用区 / 扩展 A / 兼容字母 / 半角片假名 / 兼容汉字）。"""
    for ch in t:
        o = ord(ch)
        # 私用区（0xE000-0xF8FF）不算：DNF 用它放图标/按键字形，是合法内容
        if o == 0xFFFD or 0x3400 <= o <= 0x4DBF or 0x3130 <= o <= 0x318F:
            return o
        if 0xFF61 <= o <= 0xFF9F or 0xF900 <= o <= 0xFAFF:
            return o
    return None


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else "/mnt/e/dnf-sf/sf115/Script.pvf"
    global OUT
    if len(sys.argv) > 2:
        OUT = sys.argv[2]
    os.makedirs(OUT, exist_ok=True)
    a = pu.PvfArchive(src)
    st = a.entry("stringtable.bin")
    f = open(src, "rb")
    f.seek(a.data_start + st.rel_offset)
    plain = M.decrypt(f.read(M.pad4(st.length)), st.crc)[:st.length]
    n = struct.unpack_from("<i", plain, 0)[0]

    dist: dict[str, int] = {}
    bad = []
    for i in range(n):
        raw = M.string_record(plain, i)
        if not any(b > 0x7F for b in raw):
            continue
        t, c = M.decode_any(raw)
        dist[c or "fail"] = dist.get(c or "fail", 0) + 1
        if t is None or suspicious(t) is not None:
            bad.append((i, raw, t, c))

    with open(f"{OUT}/broken-strings.tsv", "w", encoding="utf-8") as fo:
        fo.write("index\thex\tdecoded\tcodec\n")
        for i, raw, t, c in bad:
            fo.write(f"{i}\t{raw.hex()}\t{(t or '').replace(chr(9), ' ')}\t{c or ''}\n")

    # 目录树里的非 ASCII 路径
    rows = []
    raw_tree = a.dir_tree
    pos = 0
    for k in range(a.num_files):
        plen = pu._i32(raw_tree, pos + 4)
        pstart, pend = pos + 8, pos + 8 + plen
        pb = bytes(raw_tree[pstart:pend])
        if any(b > 0x7F for b in pb):
            cand = {}
            for c in CODECS:
                try:
                    cand[c] = pb.decode(c)
                except UnicodeDecodeError:
                    cand[c] = ""
            t, c = M.detect_decode(pb)
            rows.append((k, pb, cand, t, c))
        pos = pend + 12

    with open(f"{OUT}/nonascii-paths.tsv", "w", encoding="utf-8") as fo:
        fo.write("index\thex\tgb18030\tbig5hkscs\tcp949\tfinal_codec\tfinal\n")
        for k, pb, cand, t, c in rows:
            fo.write(f"{k}\t{pb.hex()}\t{cand['gb18030']}\t{cand['big5hkscs']}\t{cand['cp949']}\t{c}\t{t}\n")

    # 可疑条目的下标聚类
    runs: list[list[int]] = []
    for i, _, _, _ in bad:
        if runs and i - runs[-1][1] <= 40:
            runs[-1][1] = i
        else:
            runs.append([i, i])

    with open(f"{OUT}/summary.txt", "w", encoding="utf-8") as fo:
        fo.write(f"源：{src}\n")
        fo.write(f"条目 {a.num_files:,} / 字符串 {n:,} / 非 ASCII {sum(dist.values()):,}\n\n")
        fo.write("== 编码分布 ==\n")
        for k, v in sorted(dist.items(), key=lambda kv: -kv[1]):
            fo.write(f"  {k:<12} {v:>8,}\n")
        fo.write(f"\n== 真正读不出来的 {len(bad)} 条（含私用区/扩展A/兼容字模，多为源包已被替换成 '?'）==\n")
        for s, e in runs:
            fo.write(f"  {s}..{e}  ({e - s + 1} 条)\n")
        fo.write("\n== 目录树里非 ASCII 的路径 ==\n")
        for k, pb, cand, t, c in rows:
            fo.write(f"  #{k}  [{c}] {t}\n")
            fo.write(f"        raw = {pb.hex(' ')}\n")
    print(f"编码分布 {dist}")
    print(f"可疑 {len(bad)} 条，区间 {len(runs)} 段；非 ASCII 路径 {len(rows)} 条")
    print(f"写出 {OUT}/summary.txt / nonascii-paths.tsv / broken-strings.tsv")


if __name__ == "__main__":
    main()
