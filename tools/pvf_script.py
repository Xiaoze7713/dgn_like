#!/usr/bin/env python3
"""PVF 脚本（dataType==1，5 字节 token 流）读取 / 反词法 / 结构化解析。

数据来源：analysis/pvf-new/pvf34.sqlite（由 dnf_latest 的 Script.pvf 解出）
  files(path, dtype, size, chunk, off, data)   dtype=1 是脚本 token 流，3 是 UTF-16 文本
  text(path, body)                             已渲染的脚本文本（只在需要看原文时用）

字符串寻址：token 里的 int 值如果是「字符串偏移」，按
  v & 1 == 1  -> strW 池，(v>>1)*2 起 UTF-16LE，双 NUL 结尾
  v & 1 == 0  -> strA 池，v>>1 起 UTF-8/GB18030，单 NUL 结尾
本版本 PVF 的 strA 池为空（0 字节），所有字符串都走 strW。

token 类型（5 字节：[1B type][4B int32 value]）：
  0  整数
  2  float32（value 按 int32 存，需要按位重解释）
  3  换行 + 字符串 —— 「行首标签」：`[grade]`、`[usable job]`、`[/usable job]`，也可能是裸串
  5  `{`  （换行 + 块开始）
  6  反引号字符串 —— 一种「带类型的枚举串」，如 `` `[trade limit] 1` ``
  7  `}`  （块结束）
  8  值字符串 —— 挂在上一标签后面的值，如 `<13::name_10000039>`

第 2 个任务（.chr）会用到 type 5/7 的花括号块，.stk 基本不用。
"""

from __future__ import annotations

import mmap
import os
import sqlite3
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_DB = os.path.join(ROOT, "analysis", "pvf-new", "pvf34.sqlite")
POOLS = os.path.join(ROOT, "analysis", "pvf-new", "pools")

TOKEN_SIZE = 5


# --------------------------------------------------------------------------
# 字符串池
# --------------------------------------------------------------------------
class StringPool:
    """mmap 两个字符串池，按 token 里的偏移取串。只读，常驻内存很小。"""

    def __init__(self, pools_dir: str = POOLS) -> None:
        self._files = []
        self.str_a = self._mmap(os.path.join(pools_dir, "strA.bin"))
        self.str_w = self._mmap(os.path.join(pools_dir, "strW.bin"))
        self._cache: dict[int, str] = {}

    def _mmap(self, path: str):
        if not os.path.exists(path) or os.path.getsize(path) == 0:
            return None
        fh = open(path, "rb")
        self._files.append(fh)  # 必须持有句柄，否则 mmap 失效
        return mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)

    def resolve(self, v: int) -> str:
        """把 token 的 int32 值当字符串偏移解析；不是合法偏移时返回 ''。"""
        if v in self._cache:
            return self._cache[v]
        if v < 0:
            out = ""
        elif v & 1:
            out = "" if self.str_w is None else self._read_w(v)
        else:
            out = "" if self.str_a is None else self._read_a(v)
        if len(self._cache) < 2_000_000:
            self._cache[v] = out
        return out

    def _read_w(self, v: int) -> str:
        mm = self.str_w
        start = (v >> 1) * 2
        if start >= len(mm):
            return ""
        end = start
        n = len(mm)
        # 双 NUL 结尾；按 2 字节步进
        while end + 1 < n and not (mm[end] == 0 and mm[end + 1] == 0):
            end += 2
        return mm[start:end].decode("utf-16-le", "replace")

    def _read_a(self, v: int) -> str:
        mm = self.str_a
        start = v >> 1
        if start >= len(mm):
            return ""
        end = mm.find(b"\x00", start)
        if end < 0:
            return ""
        raw = mm[start:end]
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("gb18030", "replace")


# --------------------------------------------------------------------------
# token 流
# --------------------------------------------------------------------------
class Token:
    __slots__ = ("kind", "value", "raw")

    def __init__(self, kind: str, value, raw: int) -> None:
        self.kind = kind      # int/float/str/label/val/open/close
        self.value = value    # 数字或字符串
        self.raw = raw

    def __repr__(self) -> str:
        return f"<{self.kind} {self.value!r}>"


def tokenize(data: bytes, pool: StringPool) -> list[Token]:
    """raw bytes -> token 列表。不解析结构。"""
    out: list[Token] = []
    n = len(data) - TOKEN_SIZE + 1
    for off in range(0, n, TOKEN_SIZE):
        t = data[off]
        v = struct.unpack_from("<i", data, off + 1)[0]
        if t == 0:
            out.append(Token("int", v, v))
        elif t == 2:
            out.append(Token("float", struct.unpack("<f", struct.pack("<i", v))[0], v))
        elif t == 3:
            out.append(Token("label", pool.resolve(v), v))
        elif t == 5:
            out.append(Token("open", "{", v))
        elif t == 6:
            out.append(Token("str", pool.resolve(v), v))
        elif t == 7:
            out.append(Token("close", "}", v))
        elif t == 8:
            out.append(Token("val", pool.resolve(v), v))
        else:
            out.append(Token(f"t{t}", v, v))
    return out


# --------------------------------------------------------------------------
# 结构化：块 / 行
# --------------------------------------------------------------------------
class Node:
    """一段脚本。

    label:   行首标签（`[grade]` / `[usable job]`），花括号块为 '{'，根为 ''
    values:  直接挂在本行后面的值（int/float/str/val），按出现顺序
    children: 子节点（行 或 块）
    """

    __slots__ = ("label", "values", "children")

    def __init__(self, label: str = "") -> None:
        self.label = label
        self.values: list[Token] = []
        self.children: list[Node] = []

    # -- 便捷取值 ---------------------------------------------------------
    def first(self, label: str) -> "Node | None":
        for c in self.children:
            if c.label == label:
                return c
        return None

    def all(self, label: str) -> list["Node"]:
        return [c for c in self.children if c.label == label]

    def scalar(self, label: str, default=None):
        node = self.first(label)
        if node is None or not node.values:
            return default
        return node.values[0].value

    def name(self) -> str:
        return _strip_bracket(self.label)

    def __repr__(self) -> str:
        return f"<Node {self.label!r} v={len(self.values)} c={len(self.children)}>"


def _strip_bracket(label: str) -> str:
    if len(label) >= 2 and label[0] == "[" and label[-1] == "]":
        return label[1:-1]
    return label


def _is_close_label(label: str) -> bool:
    return len(label) >= 3 and label.startswith("[/") and label.endswith("]")


def _close_name(label: str) -> str:
    return label[2:-1]


def parse(tokens: list[Token]) -> Node:
    """token -> 树。

    `[x] ... [/x]` 视为块；`{ ... }` 也视为块。只出现单个配对的标签是普通行。
    两遍：先按名字匹配算出哪些 label 是块的开始，再建树（避免把 `[grade]` 的下一个
    标量标签错当成子节点）。
    """
    block_open: set[int] = set()
    _mark_blocks(tokens, block_open)

    root = Node("")
    stack: list[Node] = [root]
    for i, tk in enumerate(tokens):
        if tk.kind == "label":
            if _is_close_label(tk.value):
                name = _close_name(tk.value)
                for j in range(len(stack) - 1, 0, -1):
                    if _strip_bracket(stack[j].label) == name:
                        del stack[j:]
                        break
                continue
            if i in block_open:
                node = Node(tk.value)
                stack[-1].children.append(node)
                stack.append(node)
            else:
                node = Node(tk.value)
                stack[-1].children.append(node)
        elif tk.kind == "open":
            node = Node("{")
            stack[-1].children.append(node)
            stack.append(node)
        elif tk.kind == "close":
            if len(stack) > 1:
                stack.pop()
        else:
            # 值挂在最近一个标签行上（普通行不会入栈，所以要找容器的最后一个子节点）
            container = stack[-1]
            target = container.children[-1] if container.children else container
            target.values.append(tk)
    return root


def _mark_blocks(tokens: list[Token], out: set[int]) -> None:
    """按名字配对，标记块起始 label 的下标。"""
    # 先给每个 label 下标一个名字
    labels = [(i, _strip_bracket(t.value)) for i, t in enumerate(tokens) if t.kind == "label"]
    open_stack: list[tuple[int, str]] = []
    for i, name in labels:
        if _is_close_label_name(name):
            target = name[1:]  # '[/x]' -> '/x' -> 'x'
            for k in range(len(open_stack) - 1, -1, -1):
                if open_stack[k][1] == target:
                    out.add(open_stack[k][0])
                    del open_stack[k:]
                    break
        else:
            open_stack.append((i, name))


def _is_close_label_name(stripped: str) -> bool:
    return stripped.startswith("/")


# --------------------------------------------------------------------------
# 渲染（阅读 / 调试用）
# --------------------------------------------------------------------------
def to_text(node: Node, indent: int = 0, out: list[str] | None = None) -> str:
    """把树渲染成缩进文本，接近原官方阅读器的样子。"""
    top = out is None
    out = [] if out is None else out
    pad = "    " * indent
    for child in node.children:
        if child.label == "{":
            out.append(f"{pad}{{")
            to_text(child, indent + 1, out)
            out.append(f"{pad}}}")
            continue
        line = f"{pad}{child.label}"
        if child.values:
            line += " " + " ".join(_fmt_value(v) for v in child.values)
        out.append(line)
        if child.children:
            to_text(child, indent + 1, out)
    if top:
        return "\n".join(out)
    return ""


def _fmt_value(tk: Token) -> str:
    if tk.kind == "int":
        return str(tk.value)
    if tk.kind == "float":
        return f"{tk.value:g}"
    if tk.kind == "str":
        return f"`{tk.value}`"
    return tk.value


def walk(node: Node):
    """深度优先遍历所有节点（含自身子树）。"""
    for c in node.children:
        yield c
        yield from walk(c)


# --------------------------------------------------------------------------
# 数据库
# --------------------------------------------------------------------------
class Pvf:
    """pvf34.sqlite 的只读访问 + 解析。"""

    def __init__(self, db: str = DEFAULT_DB, pool: StringPool | None = None) -> None:
        self.db = db
        self.conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True, check_same_thread=False)
        self.conn.execute("PRAGMA temp_store=MEMORY")
        self.pool = pool or StringPool()
        self._parse_cache: dict[str, Node] = {}

    def close(self) -> None:
        self.conn.close()

    # -- 取值 -------------------------------------------------------------
    def data(self, path: str) -> bytes | None:
        row = self.conn.execute("select data from files where path=?", (path,)).fetchone()
        return row[0] if row else None

    def text(self, path: str) -> str | None:
        row = self.conn.execute("select body from text where path=?", (path,)).fetchone()
        return row[0] if row else None

    def exists(self, path: str) -> bool:
        """精确存在性（path 必须是小写全路径）。"""
        return self.conn.execute("select 1 from files where path=?", (path,)).fetchone() is not None

    def size_of(self, path: str) -> int | None:
        row = self.conn.execute("select size from files where path=?", (path,)).fetchone()
        return row[0] if row else None

    def tokens(self, path: str) -> list[Token]:
        d = self.data(path)
        if d is None:
            raise KeyError(path)
        return tokenize(d, self.pool)

    def tree(self, path: str) -> Node:
        t = self._parse_cache.get(path)
        if t is None:
            t = parse(self.tokens(path))
            if len(self._parse_cache) < 4096:
                self._parse_cache[path] = t
        return t

    # -- 批量迭代 ---------------------------------------------------------
    def iter_files(self, prefix: str = "", ext: str | None = None, batch: int = 10000):
        """按 path 字典序 keyset 分页读 (path, dtype, size, data)，内存占用 ~batch 条。"""
        like = prefix + "%"
        if ext:
            like = prefix + "%" + ext
        cur = self.conn.cursor()
        last = ""
        while True:
            if last:
                cur.execute(
                    "select path, dtype, size, data from files where path > ? and path like ? "
                    "order by path limit ?", (last, like, batch))
            else:
                cur.execute(
                    "select path, dtype, size, data from files where path like ? "
                    "order by path limit ?", (like, batch))
            rows = cur.fetchall()
            if not rows:
                return
            for r in rows:
                yield r
            last = rows[-1][0]

    def count(self, prefix: str = "", ext: str | None = None) -> int:
        like = prefix + "%" + (ext or "")
        return self.conn.execute("select count(*) from files where path like ?", (like,)).fetchone()[0]

    def list_paths(self, prefix: str = "", ext: str | None = None, batch: int = 20000):
        like = prefix + "%" + (ext or "")
        cur = self.conn.cursor()
        last = ""
        while True:
            if last:
                cur.execute("select path from files where path > ? and path like ? order by path limit ?",
                            (last, like, batch))
            else:
                cur.execute("select path from files where path like ? order by path limit ?", (like, batch))
            rows = [r[0] for r in cur.fetchall()]
            if not rows:
                return
            yield from rows
            last = rows[-1]


if __name__ == "__main__":
    import sys
    p = Pvf()
    for arg in sys.argv[1:]:
        print("#" * 20, arg)
        print(to_text(p.tree(arg)))
