#!/usr/bin/env python3
"""全量扫 .stk → 完整字段字典（不截断的枚举值）+ 官方释义。

与 tools/stk_scan.py 的区别：
  * stk_scan.py 是「探路」版：每个字段只留 top40、distinct 上限 4000，体积小。
  * 本脚本是「字典」版：小基数（<= --cap，默认 200000）的字段保留**完整**取值计数，
    并额外记录每个字段的取值类型签名、父块、出现文件数、官方释义，产出可直接查询的 dict。

用法：
  python3 tools/stk_dict.py                     # 全量 199k，约 40~60 s
  python3 tools/stk_dict.py --limit 5000        # 试跑
  python3 tools/stk_dict.py --out x.json

产物（默认 analysis/pvf-new/items/stk_dict.json）：
  meta     口径 / 文件数 / 失败
  fields   {标签: {files, occ, kinds, sig, parents, ints/strs/vals(完整或 top), official}}
  enums    关键枚举字段的「值 → 计数」纯表，方便直接查
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_script import Pvf, parse, tokenize  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DEFAULT = os.path.join(ROOT, "analysis", "pvf-new", "items", "stk_dict.json")
TAGDICT = os.path.join(ROOT, "export", "_meta", "tagdict.sqlite")

# 这些字段是「枚举」，即使基数大也尽量全留
ENUM_FIELDS = {
    "grade", "rarity", "item category", "attach type", "usable job", "stackable type",
    "sub type", "action usable place", "expert type", "avatar emblem target type",
    "enchant index", "impossible contents", "move wav", "cool time", "stack limit",
    "minimum level", "usable first growtype", "action type", "hide booster info",
    "booster equipment grade", "booster selection num", "booster category num",
    "rune option", "string data", "equipment parameter", "enchant table", "need skill",
    "purchase limit", "price", "weight", "max stack", "trade limit max",
}
TOP_N = 120
# 单字段 distinct 超过这个数就只留 top，避免 equipment 之类把内存压满
DISTINCT_CAP = 200_000


def load_tagdict(ext: str = "stk") -> dict:
    import sqlite3
    if not os.path.exists(TAGDICT):
        return {}
    conn = sqlite3.connect(f"file:{TAGDICT}?mode=ro", uri=True)
    out = {}
    for tag, title, comment, desc, uses in conn.execute(
            "select tag,title,comment,desc,uses from tags where ext=?", (ext,)):
        out[tag.lower()] = {
            "title": title,
            "comment": comment,
            "example": desc,
            "uses_old": uses,
        }
    conn.close()
    return out


def norm_label(label: str) -> str:
    if len(label) >= 2 and label[0] == "[" and label[-1] == "]":
        return label[1:-1]
    return label


class Agg:
    __slots__ = ("files", "occ", "kinds", "ints", "strs", "vals", "parents", "sig",
                 "samples", "overflow_int", "overflow_str", "overflow_val")

    def __init__(self) -> None:
        self.files = 0
        self.occ = 0
        self.kinds: Counter = Counter()
        self.ints: Counter = Counter()
        self.strs: Counter = Counter()
        self.vals: Counter = Counter()
        self.parents: Counter = Counter()
        self.sig: Counter = Counter()
        self.samples: list[str] = []
        self.overflow_int = self.overflow_str = self.overflow_val = 0

    def add(self, node, path: str, parent: str) -> None:
        self.files += 1
        self.occ += 1
        self.parents[parent] += 1
        if len(self.samples) < 5:
            self.samples.append(path)
        sig = []
        for tk in node.values:
            sig.append(tk.kind)
            self.kinds[tk.kind] += 1
            if tk.kind in ("int", "float"):
                v = tk.value if tk.kind == "int" else round(tk.value, 6)
                if len(self.ints) >= DISTINCT_CAP and v not in self.ints:
                    self.overflow_int += 1
                else:
                    self.ints[v] += 1
            elif tk.kind == "str":
                if len(self.strs) >= DISTINCT_CAP and tk.value not in self.strs:
                    self.overflow_str += 1
                else:
                    self.strs[tk.value] += 1
            elif tk.kind == "val":
                if len(self.vals) >= DISTINCT_CAP and tk.value not in self.vals:
                    self.overflow_val += 1
                else:
                    self.vals[tk.value] += 1
        self.sig[",".join(sig)] += 1

    def dump(self, name: str, official: dict) -> dict:
        full = name in ENUM_FIELDS
        d = {
            "files": self.files,
            "occ": self.occ,
            "kinds": dict(self.kinds),
            "sig": [[k, v] for k, v in self.sig.most_common(10)],
            "parents": [[k or "<root>", v] for k, v in self.parents.most_common(6)],
            "samples": self.samples,
            "official": official or None,
        }
        for key, counter, ovf in (("int", self.ints, self.overflow_int),
                                  ("str", self.strs, self.overflow_str),
                                  ("val", self.vals, self.overflow_val)):
            if not counter:
                continue
            d[f"{key}_distinct"] = len(counter)
            if ovf:
                d[f"{key}_overflow"] = ovf
            items = counter.most_common(None if full else TOP_N)
            d[f"{key}s"] = [[k, v] for k, v in items]
        return d


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", default="stackable/")
    ap.add_argument("--ext", default=".stk")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--batch", type=int, default=10000)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    p = Pvf()
    total = p.count(args.prefix, args.ext)
    if args.limit:
        total = min(total, args.limit)
    official = load_tagdict("stk")

    fields: dict[str, Agg] = {}
    failures: list[dict] = []
    nfiles = 0
    ntok = 0

    for path, dtype, size, data in p.iter_files(args.prefix, args.ext, batch=args.batch):
        if args.limit and nfiles >= args.limit:
            break
        nfiles += 1
        if dtype != 1:
            failures.append({"path": path, "why": f"dtype={dtype}"})
            continue
        toks = tokenize(data, p.pool)
        ntok += len(toks)
        root = parse(toks)

        def visit(node, parent: str) -> None:
            for c in node.children:
                lab = norm_label(c.label).lower()
                agg = fields.get(lab)
                if agg is None:
                    agg = fields[lab] = Agg()
                agg.add(c, path, parent)
                if c.children:
                    visit(c, f"[{lab}]")

        visit(root, "")
        if not args.quiet and nfiles % 20000 == 0:
            print(f"  ... {nfiles}/{total} files, {len(fields)} fields, {ntok:,} tokens",
                  file=sys.stderr)

    out_fields = {name: agg.dump(name, official.get(name)) for name, agg in fields.items()}
    out_fields = dict(sorted(out_fields.items(), key=lambda kv: -kv[1]["files"]))

    enums = {}
    for name in ENUM_FIELDS:
        d = out_fields.get(name)
        if not d:
            continue
        e = {}
        for key in ("strs", "ints", "vals"):
            if d.get(key):
                e[key] = d[key] if d.get(f"{key}_distinct", 0) <= 2000 else d[key][:200]
        if e:
            enums[name] = e

    payload = {
        "meta": {
            "source": "analysis/pvf-new/pvf34.sqlite",
            "prefix": args.prefix,
            "ext": args.ext,
            "files_scanned": nfiles,
            "files_total": p.count(args.prefix, args.ext),
            "tokens": ntok,
            "fields": len(out_fields),
            "fields_with_official": sum(1 for v in out_fields.values() if v["official"]),
            "generated_by": "tools/stk_dict.py",
            "failures": failures[:20],
            "failure_count": len(failures),
        },
        "enums": enums,
        "fields": out_fields,
    }
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print(f"-> {args.out}  ({os.path.getsize(args.out) / 1e6:.2f} MB)")
    print(f"files={nfiles} fields={len(out_fields)} "
          f"official={payload['meta']['fields_with_official']} fail={len(failures)}")

    # 终端速览：文件覆盖数前 40 的字段
    print(f"\n{'tag':34s} {'files':>8s} {'kinds':22s} {'distinct':>9s} official")
    for name, d in list(out_fields.items())[:40]:
        kinds = ",".join(f"{k}:{v}" for k, v in list(d["kinds"].items())[:2])
        dist = d.get("int_distinct", 0) + d.get("str_distinct", 0) + d.get("val_distinct", 0)
        print(f"{name[:34]:34s} {d['files']:8d} {kinds[:22]:22s} {dist:9d} "
              f"{'Y' if d['official'] else '-'}")


if __name__ == "__main__":
    main()
