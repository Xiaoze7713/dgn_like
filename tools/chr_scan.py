#!/usr/bin/env python3
"""解析 .chr（职业定义）—— 平铺 token 流 + 隐式区域，并抽取文件引用。

为什么不能用 pvf_script.parse()：
  .chr 里没有任何 `{`/`}`，`[growtype N]` 也没有 `[/growtype]`。
  整份文件是「标签 + 值」的平铺序列，嵌套只由「标签名 + 出现顺序」表达。
  所以这里写一个专用结构解析器：
    1) flatten：label token 开新键，其余 token（int/float/str/val）都当它的值；
       —— `[job] [swordman]` 里 `[swordman]` 是 str 值不是 label（实测 kind=='str'），
          所以不存在「方括号二义性」。
    2) 容器：某 label 若在文件里出现过 `[/label]`，它就是显式闭合容器（skill / show skill …）。
    3) 区域：无值、无闭合、后面跟 label 的 → 区域起始（initial value / growtype N / awakening N）。
       区域在遇到「动作尾部标签」（* motion / * info / weapon wav）或同级新区域时结束。
       未知标签一律吸收进当前区域（宁可多收，不可丢字段）。

用法：
  python3 tools/chr_scan.py --dump character/swordman/swordman.chr   # 看结构
  python3 tools/chr_scan.py                                         # 全 55 个 .chr 聚合
  python3 tools/chr_scan.py --refs character/swordman/swordman.chr   # 抽引用并校验存在性
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, OrderedDict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_script import Pvf, Token, tokenize  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "analysis", "pvf-new", "chr")
TAGDICT = os.path.join(ROOT, "export", "_meta", "tagdict.sqlite")

REGION_RE = re.compile(r"^(?:growtype|awakening) \d+$|^initial value$")
# 动作/攻击信息段：一旦出现，之前的 growtype/awakening 区域全部结束
TAIL_RE = re.compile(r"motion(?: [\d-]+)?$| info$|^weapon wav$")
PATH_RE = re.compile(r"\.(ani|als|atk|act|til|ptl|img|obj|eff)$", re.I)
REFLABEL_RE = re.compile(r"^/.*/$")


def norm_label(label: str) -> str:
    if len(label) >= 2 and label[0] == "[" and label[-1] == "]":
        return label[1:-1]
    return label


# ---------------------------------------------------------------- flat layer

class Pair:
    """平铺流里的一项：一个标签 + 它的直接值（不递归）。"""

    __slots__ = ("label", "values", "idx")

    def __init__(self, label: str, idx: int):
        self.label = label
        self.values: list[Token] = []
        self.idx = idx

    def __repr__(self) -> str:
        return f"<Pair {self.label} {[v.value for v in self.values]}>"

    def scalar(self):
        return self.values[0].value if self.values else None

    def nums(self) -> list:
        return [v.value for v in self.values if v.kind in ("int", "float")]

    def strs(self) -> list[str]:
        return [v.value for v in self.values if v.kind in ("str", "val")]


def flatten(tokens: list[Token]) -> list[Pair]:
    out: list[Pair] = []
    cur: Pair | None = None
    for i, tk in enumerate(tokens):
        if tk.kind == "label":
            cur = Pair(norm_label(tk.value), i)
            out.append(cur)
        else:
            if cur is None:            # 文件头就是裸值（罕见，记为 <bootstrap>）
                cur = Pair("<bootstrap>", i)
                out.append(cur)
            cur.values.append(tk)
    return out


# ------------------------------------------------------------ structure layer

class Node:
    """结构节点：label + 自己的值 + 子节点；kind 标记它是什么。"""

    __slots__ = ("label", "values", "children", "kind", "idx", "markers", "level")

    def __init__(self, label: str, idx: int, kind: str = "leaf"):
        self.label = label
        self.values: list[Token] = []
        self.children: list[Node] = []
        self.kind = kind          # root/region/container/leaf
        self.idx = idx
        self.markers: list[str] = []
        self.level = 0

    def find(self, label: str) -> "Node | None":
        for c in self.children:
            if c.label == label:
                return c
        return None

    def all(self, label: str) -> list["Node"]:
        return [c for c in self.children if c.label == label]

    def scalar(self):
        return self.values[0].value if self.values else None

    def nums(self) -> list:
        return [v.value for v in self.values if v.kind in ("int", "float")]

    def strs(self) -> list[str]:
        return [v.value for v in self.values if v.kind in ("str", "val")]

    def to_dict(self) -> dict:
        d = {"label": self.label, "kind": self.kind}
        vals = [v.value for v in self.values]
        if vals:
            d["values"] = vals
        if self.children:
            d["children"] = [c.to_dict() for c in self.children]
        return d

    def render(self, depth: int = 0) -> str:
        pad = "  " * depth
        v = " ".join(_fmt(x) for x in self.values)
        lines = [f"{pad}[{self.label}]{(' ' + v) if v else ''}"]
        for c in self.children:
            lines.append(c.render(depth + 1))
        return "\n".join(lines)


def _fmt(tk: Token) -> str:
    if tk.kind == "float":
        v = float(tk.value)
        return str(int(v)) if v.is_integer() else f"{v:.7g}"
    return str(tk.value)


AWAKENING_ONLY = {"awakening skill", "pvp awakening skill"}


def _pop_regions(stack: list[Node], min_level: int) -> None:
    while len(stack) > 1 and stack[-1].kind == "region" and stack[-1].level >= min_level:
        stack.pop()


def build(pairs: list[Pair]) -> Node:
    """平铺 pair 流 → 结构树。

    规则（针对 .chr 实测，全部 55 个文件验证过）：
      * `[/x]` 关闭最近的容器；
      * 容器 = 文件里存在 `[/同名]` 的标签（skill / show skill / usable weapon sub type…）；
      * 区域 = 只由 REGION_RE 命中（initial value / growtype N / awakening N），
        区域遇到新的区域起始、或尾部动作标签时关闭；
      * 其余一律是叶子（含 `[physic]`/`[magic]`/`[swordman]` 这类枚举标记）。
    """
    close_set = {p.label[1:] for p in pairs if p.label.startswith("/")}
    root = Node("<root>", -1, "root")
    stack: list[Node] = [root]
    markers: list[str] = []

    for p in pairs:
        if p.label.startswith("/"):
            if len(stack) > 1:
                stack.pop()
            continue

        # 关闭已打开的区域
        if TAIL_RE.search(p.label):
            _pop_regions(stack, 1)
        elif REGION_RE.match(p.label):
            lvl = 2 if p.label.startswith("awakening") else 1
            _pop_regions(stack, lvl)
        elif stack[-1].kind == "region" and stack[-1].level == 2 \
                and p.label not in AWAKENING_ONLY:
            _pop_regions(stack, 2)

        parent = stack[-1]
        if p.label in close_set:
            node = Node(p.label, p.idx, "container")
            node.values = p.values
            parent.children.append(node)
            stack.append(node)
            continue
        if REGION_RE.match(p.label):
            node = Node(p.label, p.idx, "region")
            node.level = 2 if p.label.startswith("awakening") else 1
            parent.children.append(node)
            stack.append(node)
            continue

        node = Node(p.label, p.idx, "leaf")
        node.values = p.values
        parent.children.append(node)
        if not p.values:
            markers.append(p.label)
    root.markers = markers
    return root


# ------------------------------------------------------------------ chr doc

class ChrDoc:
    def __init__(self, path: str, root: Node, tokens: int):
        self.path = path
        self.root = root
        self.tokens = tokens

    # --- 便捷访问
    @property
    def job(self) -> str | None:
        n = self.root.find("job")
        return n.scalar() if n else None

    @property
    def growtype_names(self) -> list[str]:
        n = self.root.find("growtype name")
        return [v.value for v in n.values] if n else []

    @property
    def width(self) -> list:
        n = self.root.find("width")
        return n.nums() if n else []

    @property
    def initial(self) -> Node | None:
        return self.root.find("initial value")

    def growtypes(self) -> list[Node]:
        return [c for c in self.root.children if re.match(r"^growtype \d+$", c.label)]

    def stats(self, node: Node | None) -> dict[str, list]:
        """把某区域下的数值标签收成 {标签: [值…]}。"""
        out: dict[str, list] = OrderedDict()
        if node is None:
            return out
        for c in node.children:
            if c.label in ("skill", "show skill", "preset skill", "usable weapon sub type",
                           "pvp private create equipment list", "awakening skill",
                           "pvp awakening skill") and c.kind == "container":
                out[c.label] = [v.value for v in c.values]
                continue
            if c.kind == "leaf":
                out.setdefault(c.label, []).extend(v.value for v in c.values)
        return out

    def motions(self) -> dict[str, list[str]]:
        """尾部动作表：标签 -> 动画路径列表。"""
        out: dict[str, list[str]] = OrderedDict()
        for c in self.root.children:
            if TAIL_RE.search(c.label):
                out[c.label] = [v.value for v in c.values]
        return out


def parse_chr(p: Pvf, path: str) -> ChrDoc:
    data = p.data(path)
    toks = tokenize(data, p.pool)
    return ChrDoc(path, build(flatten(toks)), len(toks))


# ---------------------------------------------------------------- aggregation

def load_tagdict(ext: str) -> dict[str, dict]:
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


MAX_DISTINCT = 500


class Agg:
    __slots__ = ("files", "occ", "kinds", "ints", "strs", "vals", "sections", "examples",
                 "sig", "paths", "distinct", "fileset")

    def __init__(self) -> None:
        self.files = 0
        self.occ = 0
        self.kinds = Counter()
        self.ints = Counter()
        self.strs = Counter()
        self.vals = Counter()
        self.sections = Counter()
        self.examples: list[str] = []
        self.sig = Counter()
        self.paths = 0
        self.distinct = 0
        self.fileset: set[str] = set()

    def add(self, node: Node, section: str, path: str) -> None:
        self.fileset.add(path)
        self.files = len(self.fileset)
        self.occ += 1
        self.sections[section] += 1
        if len(self.examples) < 3:
            self.examples.append(path)
        sig = []
        for tk in node.values:
            sig.append(tk.kind)
            self.kinds[tk.kind] += 1
            if tk.kind == "int":
                self.ints[tk.value] += 1
            elif tk.kind == "float":
                self.ints[round(tk.value, 4)] += 1
            elif tk.kind == "str":
                if str(tk.value) and PATH_RE.search(str(tk.value)):
                    self.paths += 1
                self.strs[tk.value] += 1
            elif tk.kind == "val":
                self.vals[tk.value] += 1
        self.sig[",".join(sig)] += 1

    def to_dict(self) -> dict:
        d = {
            "files": self.files,
            "occ": self.occ,
            "sections": dict(self.sections),
            "kinds": dict(self.kinds),
            "value_signatures": [[k, v] for k, v in self.sig.most_common(8)],
            "examples": self.examples,
        }
        if self.ints:
            ks = [k for k in self.ints if isinstance(k, int)]
            if ks and len(ks) <= MAX_DISTINCT:
                d["int_range"] = [min(ks), max(ks)]
                d["int_distinct"] = len(ks)
            d["num_top"] = [[k, v] for k, v in self.ints.most_common(30)]
        if self.strs:
            d["str_distinct"] = len(self.strs)
            d["str_top"] = [[k, v] for k, v in self.strs.most_common(30)]
        if self.vals:
            d["val_distinct"] = len(self.vals)
            d["val_top"] = [[k, v] for k, v in self.vals.most_common(30)]
        if self.paths:
            d["path_values"] = self.paths
        return d


def scan_all(verbose: bool = True):
    p = Pvf()
    rows = p.conn.execute("select path from files where path like 'character/%.chr' order by path").fetchall()
    paths = [r[0] for r in rows]
    aggs: dict[str, Agg] = {}
    docs: dict[str, ChrDoc] = {}
    fail = []
    for path in paths:
        try:
            doc = parse_chr(p, path)
        except Exception as exc:  # noqa: BLE001
            fail.append({"path": path, "why": repr(exc)})
            continue
        docs[path] = doc
        def walk(node: Node, section: str):
            for c in node.children:
                sec = c.label if c.kind in ("region", "container") else section
                if c.kind == "leaf":
                    sec = section
                a = aggs.get(c.label)
                if a is None:
                    a = aggs[c.label] = Agg()
                a.add(c, sec, path)
                if c.children:
                    walk(c, c.label if c.kind in ("region", "container") else section)
        walk(doc.root, "<top>")
        if verbose:
            print(f"  {path:52s} top={len(doc.root.children)} tokens={doc.tokens}", file=sys.stderr)
    return p, paths, docs, aggs, fail


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dump", metavar="PATH")
    ap.add_argument("--refs", metavar="PATH")
    ap.add_argument("--out", default=os.path.join(OUT_DIR, "chr_fields.json"))
    ap.add_argument("--tree-out", default=os.path.join(OUT_DIR, "chr_trees.json"))
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    if args.dump:
        p = Pvf()
        for path in [args.dump]:
            doc = parse_chr(p, path)
            print(f"# {path}  tokens={doc.tokens}  top-labels={len(doc.root.children)}")
            print(doc.root.render())
        return

    if args.refs:
        p = Pvf()
        doc = parse_chr(p, args.refs)
        base = args.refs.rsplit("/", 1)[0]
        for edge in extract_refs(p, base, doc):
            print(edge)
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    p, paths, docs, aggs, fail = scan_all(verbose=False)
    td = load_tagdict("chr")
    meta = {
        "source": "analysis/pvf-new/pvf34.sqlite (files.data, raw tokens)",
        "files": len(docs),
        "files_total": len(paths),
        "region_labels": sorted({c.label for d in docs.values() for c in d.root.children
                                 if c.kind == "region"}),
        "container_labels": sorted({c.label for d in docs.values() for c in d.root.children
                                    if c.kind == "container"}),
        "failures": fail,
        "generated_by": "tools/chr_scan.py",
    }
    out = {"meta": meta, "fields": {}}
    for lab, a in sorted(aggs.items()):
        d = a.to_dict()
        if lab in td:
            d["official"] = {k: v for k, v in td[lab].items() if v}
        out["fields"][lab] = d
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    trees = {path: docs[path].root.to_dict() for path in docs}
    with open(args.tree_out, "w", encoding="utf-8") as f:
        json.dump(trees, f, ensure_ascii=False, indent=1)
    print(f"-> {args.out} ({os.path.getsize(args.out)/1024:.0f} KB)")
    print(f"-> {args.tree_out} ({os.path.getsize(args.tree_out)/1024:.0f} KB)")
    print(f"files={len(docs)}/{len(paths)} fields={len(aggs)} "
          f"regions={len(meta['region_labels'])} containers={len(meta['container_labels'])} "
          f"fail={len(fail)}")
    for path in ["character/swordman/swordman.chr", "character/swordman/atswordman.chr",
                 "character/swordman/dsswordman.chr"]:
        d = docs.get(path)
        if d:
            print(f"{path}: job={d.job} growtypes={len(d.growtypes())} "
                  f"motions={len(d.motions())}")


# --------------------------------------------------------------- references

def extract_refs(p: Pvf, base: str, doc: ChrDoc) -> list[dict]:
    """从 .chr 里抽路径型引用并校验存在性（DB path 全小写，引用带大小写）。"""
    edges = []
    for node in _walk_nodes(doc.root):
        for tk in node.values:
            if tk.kind not in ("str", "val"):
                continue
            s = str(tk.value)
            if not PATH_RE.search(s) or "/" not in s:
                continue
            target = resolve(p, base, s)
            edges.append({"from": doc.path, "label": node.label, "raw": s,
                          "resolved": target, "exists": p.exists(target)})
    return edges


def _walk_nodes(node: Node):
    yield node
    for c in node.children:
        yield from _walk_nodes(c)


def resolve(p: Pvf, base: str, rel: str) -> str:
    """相对路径 → 归一化小写 DB key。"""
    if rel.startswith("/"):
        raw = rel.lstrip("/")
    else:
        raw = base + "/" + rel
    parts: list[str] = []
    for seg in raw.split("/"):
        if seg in ("", "."):
            continue
        if seg == "..":
            if parts:
                parts.pop()
            continue
        parts.append(seg)
    return "/".join(parts).lower()


if __name__ == "__main__":
    main()
