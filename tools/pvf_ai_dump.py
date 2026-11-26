#!/usr/bin/env python3
"""把 PVF 里的旧式 `.ai` 脚本（24,644 个）解码成可读文本。

`.ai` 与 `.equ/.stk` 同为 dtype=1 的 token 流（5 B/token: [type][i32 value]），
只是它用 `[...]` 词条作为控制结构 + 命令名字符串，解出来就是一棵可读的行为树：

    [ai pattern]
        [think] [void] `is target in attack area()` 200 200 30 30
            [true] ... [return] -1 [false] ...
        [/think]
    [/ai pattern]

用法:
    python3 tools/pvf_ai_dump.py            # 全部导出到 analysis/pvf-new/ai-legacy/
    python3 tools/pvf_ai_dump.py --census   # 只统计命令名词表
"""
from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_new_extract import NewPvf, decode_script  # noqa: E402

DB = "analysis/pvf-new/pvf34.sqlite"
OUT = "analysis/pvf-new/ai-legacy"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=DB)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--census", action="store_true")
    args = ap.parse_args()

    db = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    rows = db.execute("select path,data from files where path like '%.ai'").fetchall()
    print(f".ai 文件 {len(rows):,} 个")

    a = NewPvf("/tmp/inner/Script.inner.pvf")
    cmds: collections.Counter = collections.Counter()
    words: collections.Counter = collections.Counter()
    n = 0
    for path, data in rows:
        text = decode_script(data, a.resolve)
        for m in re.finditer(r"`([^`]*)`", text):
            cmds[m.group(1)] += 1
        for m in re.finditer(r"\[([a-z][a-z /_%]*)\]", text):
            words[m.group(1)] += 1
        if not args.census:
            dst = os.path.join(args.out, path)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, "w", encoding="utf-8") as fh:
                fh.write(text)
        n += 1
        if n % 5000 == 0:
            print(f"  {n:,}/{len(rows):,}")

    os.makedirs("analysis/pvf-new", exist_ok=True)
    json.dump({"commands": cmds.most_common(), "keywords": words.most_common()},
              open("analysis/pvf-new/ai-legacy-census.json", "w"), ensure_ascii=False, indent=1)
    print(f"完成 {n:,} 个 -> {args.out}")
    print("控制词:", [w for w, _ in words.most_common(20)])
    print("命令名 top20:", [c for c, _ in cmds.most_common(20)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
