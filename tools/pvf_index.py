#!/usr/bin/env python3
"""把 PVF 的目录树导成一份紧凑索引，供运行时（Godot/其它）O(1) 查路径。

PVF 本身就是「索引 + 数据」：56 字节头 + 加密目录树 + 文件体。
目录树解密一次就能拿到全部 (path, offset, size, crc) —— 本工具把这一步的结果落盘，
运行时就不必每次解密 141 MB 的目录树（sf115 里 146 万条目）。

输出（默认 analysis/pvf/index/）：
    pvf-index.jsonl.gz   每行 {"p":"路径","o":偏移,"s":长度}
    pvf-index.meta.json  {"pvf","md5_head","file_version","count","encoding"}

用法：
    python3 tools/pvf_index.py build [--pvf PVF] [--out DIR]
    python3 tools/pvf_index.py query <路径前缀>
"""
import argparse
import gzip
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pvf_unpack import PvfArchive  # noqa: E402

PVF = "/mnt/e/dnf-sf/sf115/Script.pvf"
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "analysis/pvf/index")


def build(pvf, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    ar = PvfArchive(pvf)
    jl = os.path.join(out_dir, "pvf-index.jsonl.gz")
    n = 0
    with gzip.open(jl, "wt", encoding="utf-8", compresslevel=6) as f:
        for e in ar.entries:
            f.write(json.dumps({"p": e.path, "o": e.abs_offset, "s": e.length},
                               ensure_ascii=False, separators=(",", ":")) + "\n")
            n += 1
    head = open(pvf, "rb").read(4096)
    meta = {"pvf": pvf, "size": os.path.getsize(pvf),
            "sha1_head": hashlib.sha1(head).hexdigest(),
            "file_version": ar.file_version, "count": n,
            "data_start": ar.data_start, "dir_tree_length": ar.dir_tree_length}
    with open(os.path.join(out_dir, "pvf-index.meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print("索引: %s  %d 条  %.1f MB" % (jl, n, os.path.getsize(jl) / 1e6))
    print("元数据: %s" % os.path.join(out_dir, "pvf-index.meta.json"))


def query(out_dir, prefix):
    f = gzip.open(os.path.join(out_dir, "pvf-index.jsonl.gz"), "rt", encoding="utf-8")
    for line in f:
        if prefix in line:
            print(line.rstrip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build", "query"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--pvf", default=PVF)
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    if a.cmd == "build":
        build(a.pvf, a.out)
    else:
        query(a.out, a.arg or "")


if __name__ == "__main__":
    main()
