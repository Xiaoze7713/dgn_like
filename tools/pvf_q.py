#!/usr/bin/env python3
"""查 `analysis/pvf-new/pvf34.sqlite`（全量 6,288,780 条）的小工具。

    python3 tools/pvf_q.py cat  skill/atfighter/crouchex.skl      # 打印解码后文本
    python3 tools/pvf_q.py ls   skill/atfighter                  # 列目录
    python3 tools/pvf_q.py find '%crouch%'                       # 路径模糊匹配
    python3 tools/pvf_q.py grep 'isSkillCooltime' --ext .lua      # 全库搜文本
    python3 tools/pvf_q.py sql  "select count(*) from files where path like 'equipment/%'"
    python3 tools/pvf_q.py ai-legacy monster/                     # 找解码好的旧式 .ai
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys

DB = "analysis/pvf-new/pvf34.sqlite"
AI = "analysis/pvf-new/ai-legacy"


def conn() -> sqlite3.Connection:
    if not os.path.exists(DB):
        sys.exit(f"找不到 {DB}")
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    db.execute("PRAGMA temp_store=MEMORY")  # 沙箱里临时文件写不出去，GROUP BY 必须走内存
    return db


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["cat", "ls", "find", "grep", "sql", "ai-legacy", "stats"])
    ap.add_argument("arg", nargs="?")
    ap.add_argument("--ext", default="")
    ap.add_argument("--limit", type=int, default=50)
    args = ap.parse_args()

    if args.cmd == "ai-legacy":
        base = os.path.join(AI, (args.arg or "").strip("/"))
        if os.path.isdir(base):
            for n in sorted(os.listdir(base))[: args.limit]:
                print(n)
        elif os.path.isfile(base):
            print(open(base, encoding="utf-8").read())
        else:
            sys.exit(f"没有 {base}")
        return 0

    db = conn()
    if args.cmd == "cat":
        r = db.execute("select data,dtype,size from files where path=?", (args.arg,)).fetchone()
        if not r:
            sys.exit(f"没有 {args.arg}")
        data, dt, size = r
        if dt == 3:
            print(data.decode("utf-16-le", "replace"))
        else:
            print(data.decode("utf-8", "replace"))
        return 0
    if args.cmd == "ls":
        pre = (args.arg or "").rstrip("/") + "/"
        for (p,) in db.execute("select path from files where path like ? limit ?", (pre + "%", args.limit)):
            print(p[len(pre):])
        return 0
    if args.cmd == "find":
        for (p,) in db.execute("select path from files where path like ? limit ?", (args.arg, args.limit)):
            print(p)
        return 0
    if args.cmd == "grep":
        q = "select path from text where body like ?"
        params = [f"%{args.arg}%"]
        if args.ext:
            q += " and path like ?"
            params.append(f"%{args.ext}")
        for (p,) in db.execute(q + " limit ?", (*params, args.limit)):
            print(p)
        return 0
    if args.cmd == "stats":
        for q in ("select count(*) from files",
                  "select count(*) from text",
                  "select sum(size) from files"):
            print(q, "=>", db.execute(q).fetchone()[0])
        for r in db.execute("select dtype,count(*),sum(size) from files group by dtype"):
            print("dtype", r)
        return 0
    # sql
    cur = db.execute(args.arg)
    for row in cur.fetchmany(args.limit):
        print(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
