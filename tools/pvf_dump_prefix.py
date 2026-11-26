#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""按前缀把 PVF 里的一棵子树导出到本地目录（保持相对路径）。

  python3 tools/pvf_dump_prefix.py <pvf> <prefix> <outdir> [--limit N]

例：python3 tools/pvf_dump_prefix.py "E:/dnf/.../Script.pvf" sqr/ sqr_src/
"""
import sys, os, argparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_unpack import PvfArchive


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pvf")
    ap.add_argument("prefix")
    ap.add_argument("out")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--encoding", default="utf-8")
    a = ap.parse_args()

    ar = PvfArchive(a.pvf)
    n = 0
    total = 0
    for e in ar.entries:
        if not e.path.startswith(a.prefix):
            continue
        rel = e.path
        dst = os.path.join(a.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        data = ar.read_raw(e)
        with open(dst, "wb") as f:
            f.write(data)
        n += 1
        total += len(data)
        if a.limit and n >= a.limit:
            break
    print(f"导出 {n} 个文件 / {total} 字节 -> {a.out}")


if __name__ == "__main__":
    main()
