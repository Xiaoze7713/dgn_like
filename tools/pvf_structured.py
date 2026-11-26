#!/usr/bin/env python3
"""P0.8 结构化导出：把标签流文件转成「每行一个实体」的 JSONL。

为什么要它：`export/text/` 是给人看的，字段是「标签 + 值序列」，做数值表、生成
Godot 资源、跑交叉校验都得反复写正则。这里用 pvfReader 的 list2Dict 拿到嵌套
dict（标签已二次替换成中文），直接落 JSONL，一个实体一行。

用法：
    python tools/pvf_structured.py --jobs 10               # 全部标签流扩展名
    python tools/pvf_structured.py --exts chr,skl,atk --jobs 8
    python tools/pvf_structured.py --exts mob --limit 100  # 试跑

产出：export/structured/<ext>.jsonl.gz，每行 {"path": ..., "data": {...}}
断点续跑：已存在的 <ext>.jsonl.gz 会被跳过（用 --force 覆盖）。
"""
from __future__ import annotations

import argparse
import gzip
import json
import multiprocessing as mp
import sqlite3
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pvf_loader as L  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PVF = ROOT / "data" / "Script.pvf"
INDEX = ROOT / "export" / "_meta" / "index.sqlite"
OUTDIR = ROOT / "export" / "structured"

# 标签流（list2Dict 能吃）的扩展名；.nut/.str 是纯文本，.lst 走 read_lst_any
TAG_EXTS = [
    "chr", "skl", "atk", "mob", "obj", "act", "als", "equ", "stk", "dgn",
    "map", "twn", "qst", "apd", "cre", "npc", "ai", "aic", "til", "ptl",
    "key", "ui", "etc", "rep", "tbl", "chn", "rgn", "wdm", "rgn",
]

_P = None


def _init(pvf_path: str):
    global _P
    _P = L.load_pvf(pvf_path)


def _one(path: str):
    import dnfpkgtool.pvfReader as R

    try:
        lst = _P.read_File_In_List2(path)
        d = R.TinyPVF.list2Dict(lst)
        return json.dumps({"path": path, "data": d}, ensure_ascii=False, default=str)
    except Exception as exc:  # 单文件坏掉不该毁掉整批
        return json.dumps({"path": path, "error": f"{type(exc).__name__}: {exc}"},
                          ensure_ascii=False)


def paths_for(exts: list[str], limit: int | None) -> dict[str, list[str]]:
    db = sqlite3.connect(f"file:{INDEX}?mode=ro", uri=True)
    out: dict[str, list[str]] = {}
    for ext in exts:
        rows = [r[0] for r in db.execute(
            "select path from files where ext=? and kind!='meta' order by path", (ext,))]
        if limit:
            rows = rows[:limit]
        out[ext] = rows
    db.close()
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pvf", default=str(PVF))
    ap.add_argument("--exts", default="")
    ap.add_argument("--jobs", type=int, default=10)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--chunk", type=int, default=400)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    exts = [e.strip().lstrip(".") for e in args.exts.split(",") if e.strip()] or TAG_EXTS
    OUTDIR.mkdir(parents=True, exist_ok=True)
    plan = paths_for(exts, args.limit or None)

    for ext, paths in plan.items():
        if not paths:
            print(f"skip {ext}: no files", flush=True)
            continue
        dest = OUTDIR / f"{ext}.jsonl.gz"
        if dest.exists() and not args.force:
            print(f"skip {ext}: {dest.name} exists", flush=True)
            continue
        t = time.time()
        chunks = [paths[i:i + args.chunk] for i in range(0, len(paths), args.chunk)]
        ok = err = 0
        with mp.Pool(args.jobs, initializer=_init, initargs=(args.pvf,)) as pool, \
                gzip.open(dest, "wt", encoding="utf-8", compresslevel=6) as fh:
            for i, lines in enumerate(pool.imap(_pull, chunks), 1):
                for line in lines:
                    fh.write(line + "\n")
                    if '"error"' in line[:80]:
                        err += 1
                    else:
                        ok += 1
                if i % 20 == 0:
                    print(f"  {ext}: {i}/{len(chunks)} chunks, ok={ok:,} err={err:,}",
                          flush=True)
        print(f"{ext}: {len(paths):,} files -> {dest.name} "
              f"({dest.stat().st_size/1e6:.1f}MB) ok={ok:,} err={err:,} "
              f"in {time.time()-t:.0f}s", flush=True)


def _pull(chunk: list[str]) -> list[str]:
    return [_one(p) for p in chunk]


if __name__ == "__main__":
    main()
