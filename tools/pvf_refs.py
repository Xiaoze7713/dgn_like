#!/usr/bin/env python3
"""PVF 文件引用图：扫一棵子树里所有文件里的「路径型字符串」，解析并验证存在性。

为什么这么做：
  * .chr/.skl/.ani/.als/.atk/.act 全都是同一套 5 字节 token 流，路径一律以字符串方式内嵌；
  * 相对路径的基准是**引用者自己所在目录**（`../Effect/...` 从 character/swordman/animation/ 出发），
    所以必须按 src 的目录做 posixpath.normpath + lower 再用 files 表 PK 精确查；
  * .img 引用的是 NPK（ImagePacks2），PVF 里没有，必须单独归类为 npk，不能算 missing。

用法：
  python3 tools/pvf_refs.py                                  # 默认扫 character/swordman 等
  python3 tools/pvf_refs.py --root character/swordman --root skill/swordman
  python3 tools/pvf_refs.py --out x.json --limit 5000

产物（默认 analysis/pvf-new/chr/refs.json）：
  meta    {roots, files, edges, resolved, missing, npk, by_ext}
  edges   [{s 引用者, l 标签, r 原始串, t 解析结果, e 目标扩展名, ok 是否命中}]
  labels  {标签: {files, count, ext: {扩展名: 次数}, 例子}}
  missing 解析后仍查不到的前 200 条
"""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_script import Pvf, tokenize  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DEFAULT = os.path.join(ROOT, "analysis", "pvf-new", "chr", "refs.json")

# 会被当成「文件引用」的扩展名。img 单独处理（NS 在 NPK 里）
PVF_EXT = ("ani", "als", "atk", "act", "ptl", "eff", "obj", "equ", "skl", "stk", "chr",
           "lst", "til", "map", "mob", "npc", "apd", "evt", "dgn", "ai", "aic", "key",
           "xui", "cos", "cmt", "qst", "cre")
PATH_RE = re.compile(r"\.([A-Za-z0-9]{2,4})$")
# 带 %04d 之类的模板（.chr 的 body image path）不算可直接解析的引用
TPL_RE = re.compile(r"%[0-9]*d")


def _norm(joined: str) -> str:
    parts: list[str] = []
    for seg in joined.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
            continue
        parts.append(seg)
    return "/".join(parts).lower()


def candidates(base_dir: str, rel: str) -> list[str]:
    """一个引用串可能有两种基准：相对引用者目录 / 相对 PVF 根。

    实测两类都真实存在：
      * character/swordman/animation/*.ani.als 里 `../Effect/...` → 相对 als 自己所在目录；
      * skill/swordman/*.skl 里 `Character/Swordman/Effect/...` → 相对 PVF 根。
    所以两种都试，命中即止（返回顺序即优先级）。
    """
    rel = rel.replace("\\", "/")
    if rel.startswith("/"):
        return [_norm(rel)]
    return [_norm(posixpath.join(base_dir, rel)), _norm(rel)]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", action="append", default=None)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    roots = args.root or ["character/swordman", "character/common", "skill"]

    p = Pvf()
    exists_cache: dict[str, bool] = {}
    edges: list[dict] = []
    labels: dict[str, dict] = defaultdict(lambda: {"files": 0, "count": 0,
                                                   "ext": Counter(), "examples": []})
    missing: list[dict] = []
    by_ext: Counter = Counter()
    src_ext: Counter = Counter()
    failures: list[dict] = []
    nfiles = 0
    targets: set[str] = set()

    for root in roots:
        total = p.count(root + "/")
        if not args.quiet:
            print(f"[root] {root}  files={total}", file=sys.stderr)
        for path, dtype, size, data in p.iter_files(root + "/", None, batch=10000):
            if args.limit and nfiles >= args.limit:
                break
            nfiles += 1
            if dtype != 1 or size % 5:
                failures.append({"path": path, "dtype": dtype, "size": size})
                continue
            sext = path.rsplit(".", 1)[-1].lower()
            src_ext[sext] += 1
            base = posixpath.dirname(path)
            cur = None
            for tk in tokenize(data, p.pool):
                if tk.kind == "label":
                    cur = tk.value.strip("[]")
                    continue
                if tk.kind not in ("str", "val"):
                    continue
                s = str(tk.value)
                m = PATH_RE.search(s)
                if not m:
                    continue
                ext = m.group(1).lower()
                if ext not in PVF_EXT and ext != "img":
                    continue
                lab = labels[cur or ""]
                lab["count"] += 1
                lab["ext"][ext] += 1
                if len(lab["examples"]) < 4:
                    lab["examples"].append(s)
                if ext == "img" or TPL_RE.search(s):
                    edges.append({"s": path, "l": cur, "r": s, "t": None,
                                  "e": ext, "ok": None if ext == "img" else False})
                    by_ext[f"{sext}->npk"] += 1
                    continue
                t = None
                ok = False
                how = None
                cands = candidates(base, s)
                for i, cand in enumerate(cands):
                    if cand not in exists_cache:
                        exists_cache[cand] = p.exists(cand)
                    if exists_cache[cand]:
                        t = cand
                        ok = True
                        how = "rel" if i == 0 else "root"
                        break
                if t is None:
                    t = cands[0]
                edges.append({"s": path, "l": cur, "r": s, "t": t, "e": ext, "ok": ok,
                              "how": how})
                by_ext[f"{sext}->{ext}"] += 1
                if ok:
                    targets.add(t)
                elif len(missing) < 400:
                    missing.append({"s": path, "l": cur, "r": s, "t": t,
                                    "alt": cands[1] if len(cands) > 1 else None})
    # label 的 files 计数单独补（同一 label 多值只算一次文件，这里近似用 edges 统计）
    lab_files: dict[str, set] = defaultdict(set)
    for e in edges:
        lab_files[e["l"] or ""].add(e["s"])
    out_labels = {}
    for name, d in labels.items():
        out_labels[name] = {
            "files": len(lab_files.get(name, ())),
            "count": d["count"],
            "ext": dict(d["ext"].most_common(8)),
            "examples": d["examples"],
        }

    resolved = sum(1 for e in edges if e["ok"] is True)
    how = Counter(e.get("how") for e in edges if e.get("how"))
    missing_n = sum(1 for e in edges if e["ok"] is False)
    npk = sum(1 for e in edges if e["e"] == "img" or e["t"] is None)
    payload = {
        "meta": {
            "roots": roots,
            "files_scanned": nfiles,
            "files_by_ext": dict(src_ext.most_common(20)),
            "edges": len(edges),
            "resolved": resolved,
            "missing": missing_n,
            "npk_or_template": npk,
            "distinct_targets": len(targets),
            "by_ext": dict(by_ext.most_common(30)),
            "resolve_mode": dict(how),
            "failures": failures[:10],
            "generated_by": "tools/pvf_refs.py",
        },
        "labels": dict(sorted(out_labels.items(), key=lambda kv: -kv[1]["count"])),
        "edges": edges,
        "missing": missing,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    m = payload["meta"]
    print(f"-> {args.out}  ({os.path.getsize(args.out) / 1e6:.2f} MB)")
    print(f"files={m['files_scanned']} edges={m['edges']} resolved={m['resolved']} "
          f"missing={m['missing']} npk/tpl={m['npk_or_template']} "
          f"targets={m['distinct_targets']}")
    print("\n[src->dst]")
    for k, v in by_ext.most_common(24):
        print(f"  {k:26s} {v}")
    print("\n[labels]")
    for name, d in list(out_labels.items())[:26]:
        print(f"  {name[:30]:30s} files={d['files']:6d} refs={d['count']:7d} {d['ext']}")


if __name__ == "__main__":
    main()
