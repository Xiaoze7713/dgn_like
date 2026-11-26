#!/usr/bin/env python3
"""从 sqr_gd/*.gd 的文件头生成 sqr_gd/INDEX.md（文件 → 一句话功能）。"""
import os
import re

ROOT = "sqr_gd"
HEADER_OK = re.compile(r"^##\s*源文件：\s*(.+)$")
HEADER_FN = re.compile(r"^##\s*功能：\s*(.+)$")


def scan() -> list[tuple[str, str, str]]:
    rows = []
    for dirpath, _, files in os.walk(ROOT):
        for f in sorted(files):
            if not f.endswith(".gd") or f.startswith("sqr_"):
                continue
            p = os.path.join(dirpath, f)
            src, func = "", ""
            with open(p, encoding="utf-8") as fh:
                for i, line in enumerate(fh):
                    if i > 40:
                        break
                    line = line.rstrip("\n")
                    m = HEADER_OK.match(line)
                    if m and not src:
                        # 头部常写成 "sqr/xxx.nut（Squirrel / CP949）"，只留路径
                        src = re.sub(r"\s*[（(].*$", "", m.group(1).strip())
                    m = HEADER_FN.match(line)
                    if m and not func:
                        func = m.group(1).strip()[:90]
                        if len(m.group(1).strip()) > 90:
                            func += "…"
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            rows.append((rel, src or rel[:-3] + ".nut", func or "（缺功能说明）"))
    rows.sort()
    return rows


def main() -> int:
    rows = scan()
    out = ["# sqr_gd 索引（PVF `sqr/` → GDScript 翻译对照）\n",
           f"\n共 **{len(rows)}** 个脚本。由 `tools/sqr_index.py` 生成，"
           "功能说明取自每个文件头的 `## 功能：` 行。\n",
           "\n| 目录 | 源文件 | 功能 |\n| --- | --- | --- |\n"]
    for rel, src, func in rows:
        d = rel.rsplit("/", 1)[0] if "/" in rel else "."
        out.append(f"| `{d}` | `{src}` | {func} |\n")
    with open(os.path.join(ROOT, "INDEX.md"), "w", encoding="utf-8") as fh:
        fh.write("".join(out))
    print(f"sqr_gd/INDEX.md: {len(rows)} 行")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
