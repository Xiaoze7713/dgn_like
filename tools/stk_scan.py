#!/usr/bin/env python3
"""批量扫 .stk（可堆叠道具）→ 字段字典 / 枚举 / 布局签名。

用法：
  python3 tools/stk_scan.py                    # 全量 199k，约 1~2 分钟
  python3 tools/stk_scan.py --limit 2000       # 快速试跑
  python3 tools/stk_scan.py --out path.json    # 指定输出
  python3 tools/stk_scan.py --samples 20 --sample-dir /tmp/stk_samples

产物（默认 analysis/pvf-new/items/stk_fields.json）：
  meta      统计口径、文件数、失败列表
  fields    {标签: {出现次数, 值类型分布, 每种类型的分位数/枚举, 父块, 官方释义}}
  signatures 各种「字段顺序」的布局（同一种 .stk 模板算一个签名）
  blocks    所有 [x]...[/x] 块对的出现次数

设计要点（为什么这样扫）：
  * 按 path 字典序 keyset 分页，每批 10000 条，内存只压一批的 data；
  * 字符串池用 mmap，值不复制成 python str 也会被 cache 住（上限 200 万条）；
  * 聚合只用 Counter + 小整数，不保留每个文件的树。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_script import Node, Pvf, tokenize  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DEFAULT = os.path.join(ROOT, "analysis", "pvf-new", "items", "stk_fields.json")
TAGDICT = os.path.join(ROOT, "export", "_meta", "tagdict.sqlite")

# 单字段最多跟踪多少个不同取值（超过就只计数）
MAX_DISTINCT = 4000
MAX_SIGS = 400
TOP_N = 40


def load_tagdict(ext: str) -> dict[str, dict]:
    """官方标签字典（来自 85 版 PVF 的 tagdict，字段名基本沿用）。"""
    import sqlite3
    if not os.path.exists(TAGDICT):
        return {}
    conn = sqlite3.connect(f"file:{TAGDICT}?mode=ro", uri=True)
    out = {}
    for tag, title, comment, desc, uses in conn.execute(
            "select tag,title,comment,desc,uses from tags where ext=?", (ext,)):
        out[tag] = {"title": title, "comment": comment, "example": desc, "uses_old": uses}
    conn.close()
    return out


class FieldAgg:
    """一个标签的聚合器。"""

    __slots__ = ("files", "occ", "kinds", "ints", "strs", "vals", "parents", "examples",
                 "distinct_int", "distinct_str", "distinct_val", "sig")

    def __init__(self) -> None:
        self.files = 0
        self.occ = 0
        self.kinds = Counter()          # 值类型计数
        self.ints = Counter()
        self.strs = Counter()
        self.vals = Counter()
        self.parents = Counter()
        self.examples: list[str] = []
        self.distinct_int = 0
        self.distinct_str = 0
        self.distinct_val = 0
        self.sig = Counter()            # 该标签的值类型序列，如 "str,int"

    def add(self, node: Node, path: str, parent: str) -> None:
        self.files += 1
        self.occ += 1
        self.parents[parent] += 1
        if len(self.examples) < 3:
            self.examples.append(path)
        sig = []
        for tk in node.values:
            sig.append(tk.kind)
            self.kinds[tk.kind] += 1
            if tk.kind == "int":
                if self.ints[tk.value] == 0 and self.distinct_int >= MAX_DISTINCT:
                    self.ints[-2 ** 31] += 1  # overflow 桶
                else:
                    if self.ints[tk.value] == 0:
                        self.distinct_int += 1
                    self.ints[tk.value] += 1
            elif tk.kind == "float":
                self.ints[round(tk.value, 4)] += 1
            elif tk.kind == "str":
                if self.strs[tk.value] == 0 and self.distinct_str >= MAX_DISTINCT:
                    self.strs["<overflow>"] += 1
                else:
                    if self.strs[tk.value] == 0:
                        self.distinct_str += 1
                    self.strs[tk.value] += 1
            elif tk.kind == "val":
                if self.vals[tk.value] == 0 and self.distinct_val >= MAX_DISTINCT:
                    self.vals["<overflow>"] += 1
                else:
                    if self.vals[tk.value] == 0:
                        self.distinct_val += 1
                    self.vals[tk.value] += 1
        self.sig[",".join(sig)] += 1

    def to_dict(self) -> dict:
        d = {
            "files": self.files,
            "kinds": dict(self.kinds),
            "value_signatures": [[k, v] for k, v in self.sig.most_common(12)],
            "parents": [[k or "<root>", v] for k, v in self.parents.most_common(8)],
            "examples": self.examples,
        }
        if self.ints:
            if any(isinstance(k, float) for k in self.ints):
                d["floats"] = [[k, v] for k, v in self.ints.most_common(TOP_N)]
            else:
                ks = [k for k in self.ints if k != -2 ** 31]
                if ks:
                    d["int_range"] = [min(ks), max(ks)]
                    d["int_distinct"] = self.distinct_int
                    d["int_top"] = [[k, v] for k, v in self.ints.most_common(TOP_N)]
        if self.strs:
            d["str_distinct"] = self.distinct_str
            d["str_top"] = [[k, v] for k, v in self.strs.most_common(TOP_N)]
        if self.vals:
            d["val_distinct"] = self.distinct_val
            d["val_top"] = [[k, v] for k, v in self.vals.most_common(TOP_N)]
        return d


def norm_label(label: str) -> str:
    """`[grade]` -> grade；`[usable job]` 保持原样（去方括号）。"""
    if len(label) >= 2 and label[0] == "[" and label[-1] == "]":
        return label[1:-1]
    return label


def scan(limit: int | None, prefix: str, ext: str, batch: int, verbose: bool):
    p = Pvf()
    total = p.count(prefix, ext)
    if limit:
        total = min(total, limit)
    fields: dict[str, FieldAgg] = {}
    sigs: Counter = Counter()
    sig_example: dict[str, str] = {}
    blocks: Counter = Counter()
    failures: list[dict] = []
    nfiles = 0
    ntok = 0

    for path, dtype, size, data in p.iter_files(prefix, ext, batch=batch):
        if limit and nfiles >= limit:
            break
        nfiles += 1
        if dtype != 1:
            failures.append({"path": path, "why": f"dtype={dtype}"})
            continue
        if size % 5:
            failures.append({"path": path, "why": f"size%5={size % 5}"})
        toks = tokenize(data, p.pool)
        ntok += len(toks)

        # 本轮只做「平铺 + 块」解析：块用 [x]...[/x] 显式配对
        from pvf_script import parse
        root = parse(toks)

        # 布局签名：顶层标签顺序
        order = []
        for c in root.children:
            order.append(norm_label(c.label))
        sig = "|".join(order)
        if len(sigs) < MAX_SIGS or sig in sigs:
            sigs[sig] += 1
            sig_example.setdefault(sig, path)

        # 字段聚合：遍历所有节点，记录父块
        def visit(node: Node, parent: str):
            for c in node.children:
                lab = norm_label(c.label)
                agg = fields.get(lab)
                if agg is None:
                    agg = fields[lab] = FieldAgg()
                agg.add(c, path, parent)
                if c.children:
                    if parent == "":
                        blocks[f"[{lab}]"] += 0  # 仅占位
                    visit(c, f"[{lab}]")

        visit(root, "")
        if verbose and nfiles % 10000 == 0:
            print(f"  ... {nfiles}/{total} files, {len(fields)} fields, {ntok:,} tokens",
                  file=sys.stderr)

    td = load_tagdict(ext.lstrip("."))
    out = {
        "meta": {
            "source": "analysis/pvf-new/pvf34.sqlite",
            "prefix": prefix, "ext": ext,
            "files_scanned": nfiles,
            "files_total": p.count(prefix, ext),
            "tokens": ntok,
            "generated_by": "tools/stk_scan.py",
        },
        "signatures": {
            "count": len(sigs),
            "items": [{"n": v, "example": sig_example.get(k, ""),
                       "fields": k.split("|")} for k, v in sigs.most_common(MAX_SIGS)],
        },
        "fields": {k: fields[k].to_dict() for k in sorted(fields)},
    }
    # 附加官方释义
    for lab, d in out["fields"].items():
        if lab in td:
            t = td[lab]
            d["official"] = {k: v for k, v in t.items() if v}
    out["meta"]["fields_with_official"] = sum(1 for d in out["fields"].values() if "official" in d)
    if failures:
        out["meta"]["failures"] = failures[:200]
        out["meta"]["failure_count"] = len(failures)
    return out, p, fields


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None)
    ap.add_argument("--prefix", default="stackable/")
    ap.add_argument("--ext", default=".stk")
    ap.add_argument("--batch", type=int, default=10000)
    ap.add_argument("--out", default=OUT_DEFAULT)
    ap.add_argument("--samples", type=int, default=0, help="额外导出 N 个样例的渲染文本")
    ap.add_argument("--sample-dir", default="/tmp/stk_samples")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    out, p, fields = scan(args.limit, args.prefix, args.ext, args.batch, not args.quiet)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f"-> {args.out}  ({os.path.getsize(args.out)/1e6:.2f} MB)")

    if args.samples:
        from pvf_script import to_text
        os.makedirs(args.sample_dir, exist_ok=True)
        got = 0
        for path, dtype, size, data in p.iter_files(args.prefix, args.ext, batch=2000):
            name = path.replace("/", "__") + ".txt"
            with open(os.path.join(args.sample_dir, name), "w", encoding="utf-8") as f:
                f.write(f"# {path}\n" + to_text(p.tree(path)))
            got += 1
            if got >= args.samples:
                break
        print(f"-> {args.sample_dir} ({got} samples)")

    # 控制台摘要
    print(f"\nfiles={out['meta']['files_scanned']}  fields={len(fields)}  "
          f"layouts={out['signatures']['count']}  "
          f"official={out['meta']['fields_with_official']}")
    print(f"{'tag':32s} {'files':>7s} {'kinds':22s} distinct")
    for lab, d in sorted(out["fields"].items(), key=lambda kv: -kv[1]["files"])[:60]:
        kinds = ",".join(f"{k}:{v}" for k, v in d["kinds"].items())
        dist = d.get("str_distinct", 0) + d.get("int_distinct", 0)
        print(f"{lab:32s} {d['files']:7d} {kinds:22s} {dist}")


if __name__ == "__main__":
    main()
