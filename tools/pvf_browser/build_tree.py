#!/usr/bin/env python3
"""为 PVF 浏览器建目录索引（`pvf34.tree.sqlite`）。

从 `pvf34.sqlite` 的 6,288,780 条路径里派生：
  entries(parent, name, kind, size)   kind: 0=文件 1=目录
  dirs(path, nfiles, nbytes)          目录递归统计
索引建一次约 1–2 分钟，之后浏览目录是 O(子项数)。

用法:
    python3 tools/pvf_browser/build_tree.py
"""
from __future__ import annotations

import os
import sqlite3
import sys
import time

SRC = "analysis/pvf-new/pvf34.sqlite"
TREE = "analysis/pvf-new/pvf34.tree.sqlite"


def main() -> int:
    t0 = time.time()
    if os.path.exists(TREE):
        print(f"重建 {TREE}")
        os.remove(TREE)
    src = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    src.execute("PRAGMA temp_store=MEMORY")
    out = sqlite3.connect(TREE)
    out.execute("PRAGMA journal_mode=OFF")
    out.execute("PRAGMA synchronous=OFF")
    out.execute("CREATE TABLE entries(parent TEXT, name TEXT, kind INT, size INT)")
    out.execute("CREATE TABLE dirs(path TEXT PRIMARY KEY, nfiles INT, nbytes INT)")

    dirs: dict[str, list[int]] = {"": [0, 0]}  # path -> [nfiles, nbytes]
    batch = []
    n = 0
    cur = src.execute("select path, size from files order by path")
    for path, size in cur:
        parent, _, name = path.rpartition("/")
        # 登记所有祖先目录
        acc = parent
        while True:
            st = dirs.get(acc)
            if st is None:
                st = dirs[acc] = [0, 0]
            st[0] += 1
            st[1] += size
            if not acc:
                break
            acc = acc.rpartition("/")[0]
        batch.append((parent, name, 0, size))
        n += 1
        if len(batch) >= 100_000:
            out.executemany("INSERT INTO entries VALUES (?,?,?,?)", batch)
            batch.clear()
            if n % 1_000_000 == 0:
                print(f"  {n:,} 条  {time.time()-t0:.0f}s")
    if batch:
        out.executemany("INSERT INTO entries VALUES (?,?,?,?)", batch)

    # 目录本身也是条目：从 dirs 里补齐 parent/name
    d = []
    for p in dirs:
        if not p:
            continue
        parent, _, name = p.rpartition("/")
        d.append((parent, name, 1, 0))
    out.executemany("INSERT INTO entries VALUES (?,?,?,?)", d)
    out.executemany("INSERT INTO dirs VALUES (?,?,?)",
                    [(p, v[0], v[1]) for p, v in dirs.items()])
    out.execute("CREATE INDEX idx_entries_parent ON entries(parent, kind, name)")
    out.commit()
    print(f"完成: {n:,} 文件 / {len(dirs):,} 目录 -> {TREE}  {time.time()-t0:.0f}s")
    out.close()
    src.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
