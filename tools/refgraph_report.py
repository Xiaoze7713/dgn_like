#!/usr/bin/env python3
"""从 export/_meta/refgraph.sqlite 生成人读报告 docs/REFGRAPH.md"""
from __future__ import annotations

import collections
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "export" / "_meta" / "refgraph.sqlite"
OUT = ROOT / "docs" / "REFGRAPH.md"


def ext_of(p: str) -> str:
    return "." + p.rsplit(".", 1)[-1].lower() if "." in p.rsplit("/", 1)[-1] else "-"


def main():
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    q = lambda s, *a: db.execute(s, a).fetchall()

    tot = q("select count(*) from edges")[0][0]
    res = q("select count(*) from edges where resolved=1")[0][0]
    nfiles = q("select count(distinct src) from edges")[0][0]
    ntgt = q("select count(distinct dst) from edges")[0][0]

    L = ["# 引用图（P0.7）\n"]
    L.append("自动生成，勿手改。生成器：`tools/refgraph_report.py`；数据：`export/_meta/refgraph.sqlite`。\n")
    L.append("**这张图回答什么**：谁引用了谁。技能用了哪些动画、怪物挂了哪些动作库、副本用到哪些地图、装备的图标在哪个 img。"
             "它是「改一处会炸哪里」和「读一个系统要顺着看哪些文件」的地图。\n")
    L.append("## 规模\n")
    L.append(f"- 边（引用关系）：**{tot:,}** 条")
    L.append(f"- 有出边的文件：**{nfiles:,}** 个（全库 1,460,792 个文件）")
    L.append(f"- 被引用的不同目标：**{ntgt:,}** 个")
    L.append(f"- 能落到 PVF 内真实文件的边：**{res:,}** 条（{res/tot:.1%}）；其余绝大多数是 `.img`（图像在 NPK 里，不属 PVF）\n")

    L.append("## 边按性质\n")
    L.append("| kind | 边数 | 含义 |\n| --- | ---: | --- |")
    kind_desc = {"img": "指向图像包里的 .img", "anim": "指向 .ani/.als/.act 动画链", "data": "指向其它数据文件", "script": "指向 .nut 脚本", "meta": "指向 .lst/.str/.tbl 注册表"}
    for k, n in q("select kind, count(*) from edges group by kind order by 2 desc"):
        L.append(f"| `{k}` | {n:,} | {kind_desc.get(k,'')} |")
    L.append("")

    L.append("## 被引用最多的目标 top 20\n")
    L.append("这些是「公共依赖」，改它们影响面最大。\n")
    L.append("| 被引用次数 | 目标 |\n| ---: | --- |")
    for dst, n in q("select dst, count(*) c from edges group by dst order by c desc limit 20"):
        L.append(f"| {n:,} | `{dst}` |")
    L.append("")

    L.append("## 出边最多的源文件 top 10\n")
    L.append(".lst 注册表天然出边最多——它们就是「id → 文件」的总目录。\n")
    L.append("| 出边数 | 源文件 |\n| ---: | --- |")
    for src, n in q("select src, count(*) c from edges group by src order by c desc limit 10"):
        L.append(f"| {n:,} | `{src}` |")
    L.append("")

    L.append("## 跨类型引用矩阵（已解析的边）\n")
    rows = q("""select src, dst, count(*) c from edges where resolved=1 group by src, dst""")
    mat = collections.Counter()
    for s, d, c in rows:
        mat[(ext_of(s), ext_of(d))] += c
    L.append("| 源类型 → 目标类型 | 边数 |\n| --- | ---: |")
    for (a, b), n in mat.most_common(25):
        L.append(f"| `{a}` → `{b}` | {n:,} |")
    L.append("")

    L.append("## 悬空引用（目标找不到，且不是 .img）\n")
    L.append("说明引用了**本 PVF 里不存在**的文件——多半是版本删改残留，实现时可以直接跳过。\n")
    un = collections.Counter()
    for (d,) in q("select dst from edges where resolved=0 and dst not like '%.img'"):
        un[ext_of(d)] += 1
    L.append("| 扩展名 | 悬空边数 |\n| --- | ---: |")
    for e, n in un.most_common(15):
        L.append(f"| `{e}` | {n:,} |")
    L.append("")

    L.append("## 示例链路\n")
    examples = [
        ("一个技能引用了什么", "skill/swordman/bloodboom.skl"),
        ("一个怪物引用了什么", "monster/casillas/casillas.mob"),
        ("一个副本引用了什么", None),
        ("一个装备引用了什么", None),
    ]
    for title, exact in examples:
        L.append(f"### {title}\n")
        if exact:
            rows = q("select dst, kind from edges where src=? limit 12", exact)
            if not rows:
                L.append(f"（`{exact}` 无出边）\n")
                continue
            L.append(f"源：`{exact}`\n")
            L.append("| 目标 | 类型 |\n| --- | --- |")
            for d, k in rows:
                L.append(f"| `{d}` | {k} |")
            L.append("")
        else:
            pat = "dungeon/%.dgn" if "副本" in title else "equipment/%"
            rows = q(f"select src, count(*) c from edges where src like '{pat}' group by src order by c desc limit 1")
            if not rows:
                continue
            src = rows[0][0]
            L.append(f"典型源：`{src}`（出边 {rows[0][1]} 条）\n")
            L.append("| 目标 | 类型 |\n| --- | --- |")
            for d, k in q("select dst, kind from edges where src=? limit 12", src):
                L.append(f"| `{d}` | {k} |")
            L.append("")

    L.append("## 已知边界与坑\n")
    L.append("1. **路径解析不是根相对**。大量引用写成 `../Animation/x.ani`，基准是「逻辑根」（如 `character/swordman/`）。"
             "只用根相对解析会有 48 万条 `.ani` 悬空；本图已加「后缀匹配 + 同根优先」回退，仍有约 56 万条只能模糊落到同名前缀的候选上（记 `suffix2-ambig`）。")
    L.append("2. **`.img` 一律解析不到**——图像在 NPK 客户端包里，PVF 只存路径。这类边不算错。")
    L.append("3. **反向查询用 `ix_dst`**：`sqlite3 export/_meta/refgraph.sqlite \"select src from edges where dst='monster/casillas/casillas.mob'\"` 可以查「谁在用这个怪物」。")
    L.append("4. 图只覆盖 PVF 内的**文本**引用；`.nut` 里用字符串拼出来的路径（如 `\"...\" + idx + \".ani\"`）无法静态抽全。")
    L.append("")
    OUT.write_text("\n".join(L), encoding="utf-8")
    print(f"-> {OUT} ({OUT.stat().st_size/1024:.0f} KB, {len(L)} 行)")


if __name__ == "__main__":
    main()
