#!/usr/bin/env python3
"""PVF 依赖图构建器：把 Script.pvf 里 40 万个文档解析成「节点 + 边」的 sqlite 图。

边有两类：
  1. path  —— 文本里出现的路径（相对本文件目录，或相对包根）
  2. img   —— .ani 的资源表（指向 ImagePacks2 里的 .img，即跨到 NPK 那一层）

用法：
    python3 tools/pvf_graph.py build  <pvf> <out.sqlite> [--limit N]
    python3 tools/pvf_graph.py report <out.sqlite> [--out report.md]
    python3 tools/pvf_graph.py query  <out.sqlite> "skill/swordman/..." [--depth 2]
"""
import argparse
import os
import posixpath
import re
import sqlite3
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_unpack import PvfArchive, parse_document, parse_animation  # noqa: E402

# 当作"引用"看的后缀
REF_EXTS = {
    "ani", "act", "als", "atk", "ai", "aic", "skl", "mob", "chr", "cre", "npc", "equ",
    "stk", "etc", "obj", "map", "til", "ptl", "key", "qst", "dgn", "apd", "twn", "rgn",
    "ora", "shp", "wrd", "lay", "pos", "sd", "ui", "tbl", "exj", "mm", "blu", "stm",
    "img", "nut", "lst", "rep", "bm", "co", "msn", "lua", "zmg", "ogg",
}
PATH_RE = re.compile(r"^[\w\-. /\\()]+\.([A-Za-z0-9]{2,4})$")


def is_ref(v):
    if not isinstance(v, str):
        return None
    s = v.strip()
    if not s or len(s) > 200:
        return None
    m = PATH_RE.match(s)
    if not m:
        return None
    return m.group(1).lower() if m.group(1).lower() in REF_EXTS else None


def walk_collect(node, out):
    """收集节点树里所有 path-like 值（迭代 + 去重，防环/防深递归）"""
    stack = [node]
    seen = set()
    while stack:
        n = stack.pop()
        if id(n) in seen:
            continue
        seen.add(id(n))
        for a in n.attrs:
            ext = is_ref(a)
            if ext:
                out.append((a.strip(), ext))
        for _, ch in n.children:
            stack.append(ch)


def resolve(src_path, raw):
    """把一个引用值解析成包内绝对路径（小写），返回 (候选1, 候选2)"""
    p = raw.replace("\\", "/").strip()
    if p.startswith("/"):
        p = p.lstrip("/")
    d = posixpath.dirname(src_path)
    c1 = posixpath.normpath(posixpath.join(d, p))
    c2 = posixpath.normpath(p)
    return c1.lower(), c2.lower()


def build(pvf, out_db, limit=0):
    t0 = time.time()
    ar = PvfArchive(pvf)
    ar.load_strings()
    paths = {e.path.lower(): e for e in ar.entries}
    print(f"[1/4] 打开 {pvf}\n      条目 {len(ar.entries):,}  字符串表 {len(ar.string_bin):,}  ({time.time()-t0:.1f}s)")

    db = sqlite3.connect(out_db)
    db.execute("pragma temp_store=MEMORY")
    db.executescript("""
    drop table if exists node;  drop table if exists edge;
    drop table if exists reg;   drop table if exists missing;
    create table node(path text primary key, ext text, size int, enc text);
    create table edge(src text, dst text, kind text, field text);
    create table reg(lst text, id int, target text);
    create table missing(src text, raw text, cand text, kind text);
    """)

    nodes, edges, regs, miss = [], [], [], []
    docs = []
    for e in ar.entries:
        low = e.path.lower()
        ext = low.rsplit(".", 1)[-1] if "." in low else ""
        enc = ("ani" if ext == "ani" else
               "text" if ext in ("nut", "str") else
               "doc")
        nodes.append((low, ext, e.length, enc))
        if enc == "doc":
            docs.append(e)
    print(f"[2/4] 节点 {len(nodes):,}（doc {len(docs):,}）")

    # ---- pass A: .lst 注册表 ----
    for e in ar.entries:
        low = e.path.lower()
        if not low.endswith(".lst"):
            continue
        try:
            node = parse_document(ar.read_raw(e), ar)
        except Exception:
            continue
        lines = [l.strip() for l in node.to_text() if l.strip()]
        d = posixpath.dirname(low)
        for i in range(0, len(lines) - 1, 2):
            a, b = lines[i], lines[i + 1]
            if not a.lstrip("-").isdigit():
                continue
            tgt = posixpath.normpath(posixpath.join(d, b.replace("\\", "/"))).lower()
            regs.append((low, int(a), tgt))
    print(f"[3/4] 注册表 {len(regs):,} 条（{sum(1 for n in nodes if n[0].endswith('.lst'))} 个 .lst）")

    # ---- pass B: 每个文档抽引用 ----
    n = 0
    for e in docs:
        if limit and n >= limit:
            break
        n += 1
        low = e.path.lower()
        try:
            node = parse_document(ar.read_raw(e), ar)
        except Exception:
            continue
        refs = []
        walk_collect(node, refs)
        for raw, ext in refs:
            c1, c2 = resolve(low, raw)
            if c1 in paths:
                edges.append((low, c1, "path", raw))
            elif c2 in paths:
                edges.append((low, c2, "path", raw))
            elif ext == "img":
                edges.append((low, c2, "img", raw))
            else:
                miss.append((low, raw, c1, ext))
        if n % 50000 == 0:
            el = time.time() - t0
            print(f"      {n:,}/{len(docs):,}  doc  edge={len(edges):,}  miss={len(miss):,}  {el:.0f}s")
    print(f"[4/4] 参考文件 {n:,} → 边 {len(edges):,}  断链 {len(miss):,}")

    # ---- pass C: .ani 资源表 → .img ----
    an = 0
    for e in ar.entries:
        low = e.path.lower()
        if not low.endswith(".ani"):
            continue
        an += 1
        try:
            a = parse_animation(ar.read_raw(e), ar.encoding)
        except Exception:
            continue
        for res in a.get("sprites", []):
            p = res.replace("\\", "/").lower()
            edges.append((low, posixpath.normpath(p), "img", res))
        if an % 200000 == 0:
            print(f"      ani {an:,}  edge={len(edges):,}  {time.time()-t0:.0f}s")
    print(f"      .ani {an:,} → 累计边 {len(edges):,}")

    db.executemany("insert or ignore into node values (?,?,?,?)", nodes)
    db.executemany("insert into edge values (?,?,?,?)", edges)
    db.executemany("insert into reg values (?,?,?)", regs)
    db.executemany("insert into missing values (?,?,?,?)", miss)
    db.executescript("""
    create index if not exists i_edge_src on edge(src);
    create index if not exists i_edge_dst on edge(dst);
    create index if not exists i_reg_lst on reg(lst);
    """)
    db.commit()
    print(f"完成 {out_db}  用时 {time.time()-t0:.0f}s")
    ar.close()


def add_ani(pvf, out_db):
    """.ani 的资源表 → img 边（跨到 NPK 那一层）"""
    t0 = time.time()
    db = sqlite3.connect(out_db)
    db.execute("pragma temp_store=MEMORY")
    ar = PvfArchive(pvf)
    rows, n = [], 0
    for e in ar.entries:
        low = e.path.lower()
        if not low.endswith(".ani"):
            continue
        n += 1
        try:
            a = parse_animation(ar.read_raw(e), ar.encoding)
        except Exception:
            continue
        for res in a.get("sprites", []):
            rows.append((low, posixpath.normpath(res.replace("\\", "/")).lower(), "img", res))
        if len(rows) >= 200000:
            db.executemany("insert into edge values (?,?,?,?)", rows)
            db.commit()
            rows = []
        if n % 200000 == 0:
            print(f"      ani {n:,}  {time.time()-t0:.0f}s", flush=True)
    if rows:
        db.executemany("insert into edge values (?,?,?,?)", rows)
    db.commit()
    print(f".ani {n:,} 完成，用时 {time.time()-t0:.0f}s")
    ar.close()


def idmap(pvf, out_db, out_json):
    """自动推断「哪个字段引用哪张 .lst 表」：
    对每个 (源后缀, 标签链) 收集整数值，与所有 .lst 的 id 集合比对，命中率高的即为引用边。
    """
    import json
    t0 = time.time()
    db = sqlite3.connect(out_db)
    db.execute("pragma temp_store=MEMORY")
    regs = {}
    for lst, i in db.execute("select lst, id from reg"):
        regs.setdefault(lst, set()).add(i)
    regs = {k: v for k, v in regs.items() if len(v) >= 5}
    print(f"注册表 {len(regs)} 张，最大 {max(len(v) for v in regs.values()):,} 个 id")

    ar = PvfArchive(pvf)
    ar.load_strings()
    values = {}   # (ext, chain) -> list[int]
    docs = [e for e in ar.entries
            if not e.path.lower().endswith((".ani", ".nut", ".lua", ".str", ".img", ".wav", ".ogg", ".png"))]
    print(f"文档 {len(docs):,}")

    def walk(node, chain, ext, out):
        stack = [(node, chain)]
        seen = set()
        while stack:
            n, ch = stack.pop()
            if id(n) in seen:
                continue
            seen.add(id(n))
            name = n.name or ch
            key = (ext, name)
            for a in n.attrs:
                if isinstance(a, int) and not isinstance(a, bool) and 0 <= a < 10_000_000:
                    out.setdefault(key, []).append(a)
            for cn, cnode in n.children:
                stack.append((cnode, cn))

    n = 0
    for e in docs:
        low = e.path.lower()
        ext = low.rsplit(".", 1)[-1] if "." in low else ""
        try:
            node = parse_document(ar.read_raw(e), ar)
        except Exception:
            continue
        n += 1
        walk(node, "", ext, values)
        if n % 100000 == 0:
            print(f"      {n:,}/{len(docs):,}  {time.time()-t0:.0f}s", flush=True)

    print(f"字段样本 {len(values):,} 组，开始比对…")
    res = []
    for (ext, chain), vals in values.items():
        if len(vals) < 20:
            continue
        uniq = set(vals)
        best = []
        for lst, ids in regs.items():
            hit = len(uniq & ids)
            if hit / len(uniq) >= 0.40:
                best.append((hit / len(uniq), hit, len(uniq), lst))
        best.sort(reverse=True)
        if best:
            res.append({"ext": ext, "field": chain, "n_samples": len(vals),
                        "n_uniq": len(uniq),
                        "candidates": [{"lst": b[3], "hit_rate": round(b[0], 3), "hits": b[1]} for b in best[:3]]})
    res.sort(key=lambda r: -r["candidates"][0]["hit_rate"])
    json.dump(res, open(out_json, "w"), ensure_ascii=False, indent=1)
    print(f"命中 {len(res):,} 组字段→表 映射 -> {out_json}  用时 {time.time()-t0:.0f}s")
    for r in res[:25]:
        c = r["candidates"][0]
        print(f"  .{r['ext']:5s} [{r['field']}] → {c['lst']}  {c['hit_rate']:.0%} ({c['hits']}/{r['n_uniq']})")
    ar.close()


def idedges(pvf, out_db, mapping_json):
    """按人工核过的 字段→注册表 映射，把 ID 引用落成 kind='id' 的边"""
    import json
    t0 = time.time()
    spec = json.load(open(mapping_json))
    want = {}
    for s_ in spec:
        want.setdefault(s_["ext"], {})[s_["field"]] = s_["lst"]
    db = sqlite3.connect(out_db)
    db.execute("pragma temp_store=MEMORY")
    reg = {}
    for lst, i, tgt in db.execute("select lst, id, target from reg"):
        reg[(lst, i)] = tgt
    ar = PvfArchive(pvf)
    ar.load_strings()
    docs = [e for e in ar.entries if e.path.lower().rsplit(".", 1)[-1] in want]
    print(f"待扫文档 {len(docs):,}（{sorted(want)}）  注册表索引 {len(reg):,}")
    rows, hit, missn = [], 0, 0
    for e in docs:
        low = e.path.lower()
        ext = low.rsplit(".", 1)[-1]
        fields = want[ext]
        try:
            node = parse_document(ar.read_raw(e), ar)
        except Exception:
            continue
        stack = [(node, None)]
        seen = set()
        while stack:
            n, parent = stack.pop()
            if id(n) in seen:
                continue
            seen.add(id(n))
            name = n.name
            key = None
            if name in fields:
                key = name
            elif parent in fields:
                key = parent
            if key:
                lst = fields[key]
                for a in n.attrs:
                    if isinstance(a, int) and not isinstance(a, bool):
                        tgt = reg.get((lst, a))
                        if tgt:
                            rows.append((low, tgt, "id", key))
                            hit += 1
                        else:
                            missn += 1
            for cn, ch in n.children:
                stack.append((ch, name))
        if len(rows) >= 100000:
            db.executemany("insert into edge values (?,?,?,?)", rows); db.commit(); rows = []
    if rows:
        db.executemany("insert into edge values (?,?,?,?)", rows)
    db.commit()
    print(f"id 边 {hit:,} 条，未命中 id {missn:,}，用时 {time.time()-t0:.0f}s")
    ar.close()


def report(db_path, out_md):
    db = sqlite3.connect(db_path)
    db.execute("pragma temp_store=MEMORY")
    q = lambda s, *a: db.execute(s, a).fetchall()
    L = []
    A = L.append
    A("# PVF 依赖图报告\n")
    n_node = q("select count(*) from node")[0][0]
    n_edge = q("select count(*) from edge")[0][0]
    n_miss = q("select count(*) from missing")[0][0]
    n_reg = q("select count(*) from reg")[0][0]
    A(f"- 节点 **{n_node:,}**　边 **{n_edge:,}**　注册表 **{n_reg:,}**　断链 **{n_miss:,}**\n")

    A("## 1. 出边：谁引用谁\n")
    A("| 源类型 | 目标类型 | 边数 |")
    A("| --- | --- | --- |")
    agg = {}
    for s, d in q("select src, dst from edge"):
        se = s.rsplit(".", 1)[-1] if "." in s else ""
        de = d.rsplit(".", 1)[-1] if "." in d else ""
        agg[(se, de)] = agg.get((se, de), 0) + 1
    for (se, de), c in sorted(agg.items(), key=lambda x: -x[1])[:40]:
        A(f"| `{se}` | `{de}` | {c:,} |")

    A("\n## 2. 入度最高（被最多文件引用）\n")
    A("| 目标 | 入边数 |")
    A("| --- | --- |")
    for d, c in q("select dst, count(*) c from edge group by dst order by c desc limit 25"):
        A(f"| `{d}` | {c:,} |")

    A("\n## 3. 出度最高（依赖最多）\n")
    A("| 源 | 出边数 |")
    A("| --- | --- |")
    for s, c in q("select src, count(*) c from edge group by src order by c desc limit 25"):
        A(f"| `{s}` | {c:,} |")

    A("\n## 4. 断链（引用指向不存在的文件）\n")
    A("| 后缀 | 条数 | 例子 |")
    A("| --- | --- | --- |")
    for ext, c, ex in q("""select kind, count(*), min(raw) from missing group by kind order by 2 desc limit 20"""):
        A(f"| `{ext}` | {c:,} | `{ex}` |")

    A("\n## 5. 各类型节点数与平均出度\n")
    A("| 后缀 | 节点数 | 有出边的 | 平均出度 |")
    A("| --- | --- | --- | --- |")
    for ext, cnt, with_out, edges in q("""
        select n.ext, count(*) cnt,
               sum(case when o.c is null then 0 else 1 end),
               sum(coalesce(o.c,0))
        from node n left join (select src, count(*) c from edge group by src) o on o.src=n.path
        group by n.ext order by cnt desc limit 25"""):
        A(f"| `{ext}` | {cnt:,} | {with_out:,} | {(edges/cnt if cnt else 0):.2f} |")

    A("\n## 6. 孤立节点（无人引用）\n")
    iso = q("""select count(*) from node n where not exists (select 1 from edge where dst=n.path)""")[0][0]
    A(f"- 无入边节点：**{iso:,}** / {n_node:,}\n")
    open(out_md, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print(f"报告 -> {out_md}  ({len(L)} 行)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build", "ani", "idmap", "idedges", "report", "query"])
    ap.add_argument("pvf")
    ap.add_argument("out")
    ap.add_argument("extra", nargs="?")
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()
    if a.cmd == "build":
        build(a.pvf, a.out, a.limit)
    elif a.cmd == "ani":
        add_ani(a.pvf, a.out)
    elif a.cmd == "idedges":
        idedges(a.pvf, a.out, a.extra or "analysis/pvf/reports/idmap-curated.json")
    elif a.cmd == "idmap":
        idmap(a.pvf, a.out, a.extra or "analysis/pvf/reports/idmap.json")
    elif a.cmd == "report":
        report(a.pvf, a.out)
    else:
        db = sqlite3.connect(a.pvf)
        db.execute("pragma temp_store=MEMORY")
        p = a.out.lower()
        print("出边:")
        for s, d, k in db.execute("select dst, kind, src from edge where src=?", (p,)):
            print(f"  -> [{k}] {s}")
        print("入边:")
        for s, k in db.execute("select src, kind from edge where dst=?", (p,)):
            print(f"  <- [{k}] {s}")


if __name__ == "__main__":
    main()
