#!/usr/bin/env python3
"""P0.7 引用图：扫描已解包的文本树，抽出「文件 → 它引用的文件」关系。

设计要点（第一版踩过的坑）：
- 不在 worker 里 import pvf_loader（父进程 load_pvf 后的 1.46M 项树经 fork 会复制成每 worker 3.5GB，12 进程直接压垮 31GB 内存）；
  已知文件集合改成从 export/_meta/index.sqlite 读路径。
- 只扫文本文件（.bin 是 .ani 二进制，除了头部的 img 路径没有可读引用，单独处理头部）。
- journal_mode=OFF，避免几百万行插入时 WAL 膨胀到 680MB 还写不动。

产出 export/_meta/refgraph.sqlite
  edges(src TEXT, dst TEXT, raw TEXT, resolved INT, kind TEXT)
  meta(k, v)
"""
from __future__ import annotations

import re
import sqlite3
import sys
from multiprocessing import Pool
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT_DIR = ROOT / "export" / "text"
INDEX = ROOT / "export" / "_meta" / "index.sqlite"
DB = ROOT / "export" / "_meta" / "refgraph.sqlite"

EXTS = (
    "img|ani|act|als|skl|equ|stk|mob|obj|atk|ai|aic|til|map|dgn|twn|npc|qst|apd|cre|"
    "ptl|key|ui|nut|chr|tbl|rep|etc|lst|str"
)
REF_RE = re.compile(r"[A-Za-z0-9_./\-]+\.(?:" + EXTS + r")\b")

KIND = {"img": "img", "ani": "anim", "als": "anim", "act": "anim",
        "nut": "script", "lst": "meta", "str": "meta", "tbl": "meta"}
for _e in EXTS.split("|"):
    KIND.setdefault(_e, "data")


def normalize(src: str, ref: str) -> str:
    r = ref.replace("\\", "/").strip()
    while r.startswith("./"):
        r = r[2:]
    if r.startswith("/"):
        r = r[1:]
    if r.startswith("../"):
        base = src.rsplit("/", 1)[0].split("/") if "/" in src else []
        parts = r.split("/")
        while parts and parts[0] == "..":
            parts.pop(0)
            if base:
                base.pop()
        r = "/".join(base + parts)
    return r.lower()


def scan_one(item):
    """item = (src_pvf_path, disk_path, is_binary) -> (src, [(dst, raw, kind)])"""
    src, path, is_bin = item
    try:
        data = Path(path).read_bytes()
    except OSError:
        return src, []
    out = []
    if is_bin:
        # .ani v6 头部：u16 ver | u16 | u32 len | img 路径（latin-1）
        try:
            n = int.from_bytes(data[4:8], "little")
            if 0 < n < 512:
                p = data[8:8 + n].split(b"\x00")[0].decode("latin-1")
                if "/" in p and p.lower().endswith(".img"):
                    out.append((normalize(src, p), p, "img"))
        except Exception:
            pass
        return src, out
    if src.endswith((".lst", ".str")):
        text = data.decode("latin-1")
    else:
        text = data.decode("utf-8", "ignore")
    for m in REF_RE.finditer(text):
        raw = m.group(0)
        dst = normalize(src, raw)
        if dst == src:
            continue
        out.append((dst, raw, KIND.get(raw.rsplit(".", 1)[-1].lower(), "other")))
    return src, out


def resolve_pending(db, known):
    """PVF 的路径引用不是根相对（大量 `../Animation/x.ani` 以「逻辑根」为基准），
    所以首轮解析不到的边要用「后缀匹配 + 同根优先」再落一次地。"""
    import collections

    kset = set(known)
    tail = collections.defaultdict(list)
    for p in known:
        parts = p.rsplit("/", 2)
        tail["/".join(parts[-2:]) if len(parts) > 1 else p].append(p)

    def pick(src, dst):
        if dst in kset:
            return dst
        d = dst
        while d.startswith("../"):
            d = d[3:]
        if d in kset:
            return d
        parts = dst.rsplit("/", 2)
        hit = tail.get("/".join(parts[-2:]) if len(parts) > 1 else dst)
        if not hit:
            return None
        if len(hit) == 1:
            return hit[0]
        root = src.split("/", 1)[0]
        same = [h for h in hit if h.startswith(root + "/")]
        return min(same or hit, key=len)

    rows = db.execute("select src, dst from edges where resolved=0 group by src, dst").fetchall()
    upd, n = [], 0
    for src, dst in rows:
        r = pick(src, dst)
        if r:
            upd.append((r, src, dst))
            n += 1
            if len(upd) >= 100000:
                db.executemany("update edges set dst=?, resolved=1 where src=? and dst=?", upd)
                upd.clear()
    if upd:
        db.executemany("update edges set dst=?, resolved=1 where src=? and dst=?", upd)
    db.commit()
    print(f"二次落地：{n:,} 个 (src,dst) 组合被重新解析", flush=True)


def build(jobs: int = 10):
    idx = sqlite3.connect(f"file:{INDEX}?mode=ro", uri=True)
    known = {r[0] for r in idx.execute("select path from files")}
    idx.close()
    print(f"已知 PVF 文件：{len(known):,}", flush=True)

    items = []
    for p in TEXT_DIR.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(TEXT_DIR).as_posix()
        src = rel[:-4] if rel.endswith((".txt", ".bin")) else rel
        items.append((src, str(p), rel.endswith(".bin")))
    items.sort()
    n_bin = sum(1 for i in items if i[2])
    print(f"待扫：{len(items):,}（文本 {len(items)-n_bin:,} / 二进制 {n_bin:,}）", flush=True)

    DB.parent.mkdir(parents=True, exist_ok=True)
    if DB.exists():
        DB.unlink()
    db = sqlite3.connect(DB)
    db.execute("pragma journal_mode=OFF")
    db.execute("pragma synchronous=OFF")
    db.execute("pragma cache_size=-200000")
    db.execute("create table edges (src text, dst text, raw text, resolved int, kind text)")
    db.execute("create table meta (k text primary key, v text)")

    batch = []
    total = 0
    done = 0
    with Pool(jobs) as pool:
        for src, refs in pool.imap_unordered(scan_one, items, chunksize=500):
            done += 1
            for dst, raw, kind in refs:
                batch.append((src, dst, raw, 1 if dst in known else 0, kind))
            total += len(refs)
            if len(batch) >= 200000:
                db.executemany("insert into edges values (?,?,?,?,?)", batch)
                batch.clear()
                print(f"  {done:,}/{len(items):,}  edges={total:,}", flush=True)
    if batch:
        db.executemany("insert into edges values (?,?,?,?,?)", batch)
    print(f"扫描完成：{done:,} 文件，{total:,} 条引用；建索引 ...", flush=True)
    db.execute("create index ix_src on edges(src)")
    db.execute("create index ix_dst on edges(dst)")
    db.execute("insert into meta values ('files', ?)", (str(len(items)),))
    db.commit()

    resolve_pending(db, known)

    q = lambda s: db.execute(s).fetchall()
    n_edges = q("select count(*) from edges")[0][0]
    n_res = q("select count(*) from edges where resolved=1")[0][0]
    n_src = q("select count(distinct src) from edges")[0][0]
    print(f"edges={n_edges:,} resolved={n_res:,} ({n_res/max(n_edges,1):.1%}) 有出边的文件={n_src:,}")
    print("\n被引用最多的目标 top 20：")
    for dst, n in q("select dst, count(*) c from edges group by dst order by c desc limit 20"):
        print(f"  {n:7,}  {dst}")
    print("\n引用最多的源文件 top 10：")
    for src, n in q("select src, count(*) c from edges group by src order by c desc limit 10"):
        print(f"  {n:7,}  {src}")
    print("\n悬空引用按扩展名（目标不在 PVF 内，.img 除外都值得查）：")
    import collections

    un = collections.Counter()
    for (d,) in q("select dst from edges where resolved=0 and dst not like '%.img'"):
        un["." + d.rsplit(".", 1)[-1].lower() if "." in d.rsplit("/", 1)[-1] else "-"] += 1
    for ext, n in un.most_common(12):
        print(f"  {n:8,}  {ext}")
    db.close()
    print(f"\n-> {DB}  ({DB.stat().st_size/1048576:.0f} MB)")


if __name__ == "__main__":
    build(int(sys.argv[1]) if len(sys.argv) > 1 else 10)
