#!/usr/bin/env python3
"""P0.9 数据字典：把「标签流里的 [xxx] 标签」和官方注释库对起来。

数据来源：
  /mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Options/PvfComments/*.json
    每个文件 = 一种 PVF 扩展名的标签注释库（Section=标签名, Title=中文名, Comment=解释, OfficialDescription=官例）
  /mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/AgentKnowledge/dictionaries/*.md
    专题词典（人读）

产出：
  export/_meta/tagdict.sqlite   表 tags(ext,tag,title,comment,desc,uses) / usage(tag,ext,n) / unmapped(ext,tag,n)
  analysis/01-TAG-DICT.md       人读版：每类文件的常用标签 + 中文含义；全库未收录标签清单
"""
from __future__ import annotations

import json
import re
import sqlite3
from collections import Counter, defaultdict
from multiprocessing import Pool
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT_DIR = ROOT / "export" / "text"
HEX = Path("/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64")
COMMENTS = HEX / "Options" / "PvfComments"
DB = ROOT / "export" / "_meta" / "tagdict.sqlite"
OUT_MD = ROOT / "analysis" / "01-TAG-DICT.md"

TAG_RE = re.compile(r"^\s*\[([^\[\]\r\n]{1,72})\]")


def scan(path: str):
    # 导出文件名形如 xxx.skl.txt，真实扩展名要去掉末尾的 .txt
    name = path[:-4] if path.endswith(".txt") else path
    ext = name.rsplit(".", 1)[-1].lower()
    c = Counter()
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                m = TAG_RE.match(line)
                if m:
                    c[m.group(1).strip().lower()] += 1
    except OSError:
        pass
    return ext, c


def main(jobs: int = 12):
    # ---------- 1. 官方注释库 ----------
    known: dict[str, dict] = defaultdict(dict)  # ext -> tag -> info
    for f in sorted(COMMENTS.glob("*.json")):
        d = json.loads(f.read_text(encoding="utf-8-sig"))
        ext = (d.get("FileType") or f.stem).lower()
        for e in d.get("Comments", []):
            tag = (e.get("Section") or "").strip().lower()
            if not tag:
                continue
            known[ext][tag] = {
                "title": (e.get("Title") or "").strip(),
                "comment": (e.get("Comment") or "").strip(),
                "desc": (e.get("OfficialDescription") or "").strip(),
            }
    n_known = sum(len(v) for v in known.values())
    print(f"官方标签注释：{len(known)} 类 / {n_known:,} 条", flush=True)

    # ---------- 2. 统计实际使用 ----------
    files = [p.as_posix() for p in TEXT_DIR.rglob("*") if p.is_file() and not p.as_posix().endswith(".bin")]
    print(f"扫描 {len(files):,} 个文本文件 ...", flush=True)
    per_ext: dict[str, Counter] = defaultdict(Counter)
    global_use = Counter()
    with Pool(jobs) as pool:
        for i, (ext, c) in enumerate(pool.imap_unordered(scan, files, chunksize=400), 1):
            per_ext[ext].update(c)
            global_use.update(c)
            if i % 50000 == 0:
                print(f"  {i:,}/{len(files):,}", flush=True)

    # ---------- 3. 落库 ----------
    DB.parent.mkdir(parents=True, exist_ok=True)
    if DB.exists():
        DB.unlink()
    db = sqlite3.connect(DB)
    db.execute("create table tags (ext text, tag text, title text, comment text, desc text, uses int)")
    db.execute("create table usage (tag text, ext text, n int)")
    db.execute("create table unmapped (ext text, tag text, n int)")
    rows, uses_rows, unmapped = [], [], []
    for ext, cnt in per_ext.items():
        for tag, n in cnt.items():
            uses_rows.append((tag, ext, n))
            info = known.get(ext, {}).get(tag)
            if info:
                rows.append((ext, tag, info["title"], info["comment"], info["desc"], n))
            else:
                unmapped.append((ext, tag, n))
    db.executemany("insert into tags values (?,?,?,?,?,?)", rows)
    db.executemany("insert into usage values (?,?,?)", uses_rows)
    db.executemany("insert into unmapped values (?,?,?)", unmapped)
    db.execute("create index ix_tags on tags(ext, uses desc)")
    db.execute("create index ix_usage on usage(tag)")
    db.execute("create index ix_un on unmapped(n desc)")
    db.commit()

    mapped = len(rows)
    total_pairs = len(rows) + len(unmapped)
    print(f"\n实际出现的 (扩展名,标签) 组合：{total_pairs:,}；有官方注释：{mapped:,}（{mapped/max(total_pairs,1):.1%}）")
    print(f"去重标签：{len(global_use):,}；未收录组合 {len(unmapped):,}")

    # ---------- 4. 人读文档 ----------
    ext_total = {ext: sum(c.values()) for ext, c in per_ext.items()}
    order = sorted(ext_total, key=lambda e: -ext_total[e])
    L = []
    L.append("# PVF 标签数据字典（P0.9）\n")
    L.append(
        "自动生成，勿手改。源：`pvfUtility/Options/PvfComments/*.json`（官方标签注释，"
        f"{n_known:,} 条）+ `export/text/**` 实际出现频次。查询库：`export/_meta/tagdict.sqlite`。\n"
    )
    L.append("## 用法\n")
    L.append("```bash\n# 某个标签在哪些文件类型里出现、各多少次\n")
    L.append("sqlite3 export/_meta/tagdict.sqlite \"select ext,n from usage where tag='base ani' order by n desc\"\n")
    L.append("# 官方怎么解释某个标签\n")
    L.append("sqlite3 export/_meta/tagdict.sqlite \"select title,comment from tags where tag='base ani' limit 3\"\n")
    L.append("# 某类文件最常用的标签\n")
    L.append("sqlite3 export/_meta/tagdict.sqlite \"select tag,title,uses from tags where ext='skl' order by uses desc limit 20\"\n```\n")
    L.append("## 文件类型总览\n")
    L.append("| 扩展名 | 标签出现总次数 | 去重标签数 | 有注释 | 注释覆盖率 |")
    L.append("| --- | ---: | ---: | ---: | ---: |")
    for ext in order:
        c = per_ext[ext]
        have = sum(1 for t in c if t in known.get(ext, {}))
        L.append(f"| `.{ext}` | {ext_total[ext]:,} | {len(c):,} | {have} | {have/max(len(c),1):.0%} |")
    L.append("")

    # 重点类型：把高频标签+中文名+解释首句列出来
    focus = ["skl", "equ", "stk", "act", "mob", "atk", "ai", "map", "dgn", "qst", "npc", "obj", "apd", "cre", "twn", "ani", "als", "ui"]
    for ext in focus:
        c = per_ext.get(ext)
        if not c:
            continue
        L.append(f"## `.{ext}` 高频标签\n")
        L.append("| 标签 | 中文名 | 出现次数 | 官方解释（截断） |")
        L.append("| --- | --- | ---: | --- |")
        for tag, n in c.most_common(40):
            info = known.get(ext, {}).get(tag)
            if info:
                cm = " ".join(info["comment"].split())[:150].replace("|", "／")
                L.append(f"| `[{tag}]` | {info['title']} | {n:,} | {cm} |")
            else:
                L.append(f"| `[{tag}]` | — | {n:,} | *（无注释）* |")
        L.append("")

    L.append("## 全库最常用标签 top 60（跨文件类型）\n")
    L.append("| 标签 | 总次数 | 出现的类型数 |")
    L.append("| --- | ---: | ---: |")
    tag_exts = Counter()
    for tag, _, _ in uses_rows:
        tag_exts[tag] += 1
    for tag, n in global_use.most_common(60):
        L.append(f"| `[{tag}]` | {n:,} | {tag_exts[tag]} |")
    L.append("")

    L.append("## 有实际使用但**无官方注释**的标签（知识缺口，实现组要自己摸）\n")
    top_un = sorted(unmapped, key=lambda r: -r[2])[:120]
    L.append("| 扩展名 | 标签 | 次数 |")
    L.append("| --- | --- | ---: |")
    for ext, tag, n in top_un:
        L.append(f"| `.{ext}` | `[{tag}]` | {n:,} |")
    L.append("")
    OUT_MD.write_text("\n".join(L), encoding="utf-8")
    print(f"-> {OUT_MD}  ({OUT_MD.stat().st_size/1024:.0f} KB, {len(L)} 行)")
    print(f"-> {DB}  ({DB.stat().st_size/1048576:.1f} MB)")
    db.close()


if __name__ == "__main__":
    main()
