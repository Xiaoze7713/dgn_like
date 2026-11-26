#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""PVF Studio —— 新版 DNF Script.pvf（dfo_20260901_inner）桌面阅读器。

为什么是桌面程序：
  * 左边是真正的目录树（懒加载，一层一层展开，不会"点一下就跳进去"）；
  * 大文件（几十 MB）只读前 N MB 预览，想全看就"导出"，不会把浏览器卡死；
  * .lst/.skl/.equ/.stk 这类 token 流直接解码成文本，`<13::name_xxx>` 自动还原中文。

数据依赖（都在 analysis/pvf-new/ 下，由 tools/pvf_new_*.py 生成）：
  pvf34.tree.sqlite   目录树索引（entries/dirs）
  pvf34.sqlite        文件表（files：path/dtype/size/chunk/off/data）
  pools/strW.bin      字符串池（mmap 随机读，脚本里的名字全靠它）

用法：
  python3 tools/pvf_studio/pvf_studio.py            # 正常打开
  python3 tools/pvf_studio/pvf_studio.py --selftest # 不开窗口，跑解码自检
"""

from __future__ import annotations

import argparse
import json
import mmap
import os
import re
import sqlite3
import sys
import threading
import tkinter as tk
from tkinter import filedialog, messagebox, ttk

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOLS = os.path.dirname(HERE)
ANALYSIS = os.path.join(ROOT, "analysis", "pvf-new")
DB_FILES = os.path.join(ANALYSIS, "pvf34.sqlite")
DB_TREE = os.path.join(ANALYSIS, "pvf34.tree.sqlite")
POOL_DIR = os.path.join(ANALYSIS, "pools")

sys.path.insert(0, TOOLS)
import pvf_new_extract as pvfmod  # noqa: E402  (decode_script + keystream 复用)

MAX_TEXT_CHARS = 20_000_000     # 只在界面里显示这么多字符（Tk 插 2400 万字符约 1.2 s）
MAX_READ_BYTES = 16_000_000     # 从库里最多取这么多原始字节来解码
MAX_HEX_BYTES = 262_144         # HEX 页最多显示这么多字节
MAX_CHILDREN = 3000             # 一个目录一次最多插入多少行
REF_RE = re.compile(r"<(\d+)::([^<>]+)>")
PH_SUFFIX = "|ph|"      # 懒加载占位节点（Tcl 不接受 iid 里的 \x00）
MORE_SUFFIX = "|more|"  # "还有 N 项" 节点

KIND_FILE, KIND_DIR = 0, 1


def human(n: int) -> str:
    if n is None:
        return ""
    v = float(n)
    for unit in ("B", "KB", "MB", "GB"):
        if v < 1024 or unit == "GB":
            return f"{v:,.0f} {unit}" if unit == "B" else f"{v:,.1f} {unit}"
        v /= 1024.0
    return f"{v:,.1f} GB"


# ---------------------------------------------------------------- 字符串池
class Pools:
    """mmap 的 strW/strA，用来把脚本 token 里的整数还原成名字。"""

    def __init__(self, pool_dir: str = POOL_DIR) -> None:
        self.str_w = b""
        self.str_a = b""
        for name, attr in (("strW", "str_w"), ("strA", "str_a")):
            path = os.path.join(pool_dir, name + ".bin")
            if os.path.exists(path):
                size = os.path.getsize(path)
                with open(path, "rb") as f:
                    blob = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ) if size else b""
                setattr(self, attr, blob)
        self._cache: dict[int, str] = {}

    def resolve(self, off: int) -> str:
        if off < 0:
            return ""
        hit = self._cache.get(off)
        if hit is not None:
            return hit
        if off & 1:
            start = (off >> 1) * 2
            buf = self.str_w
            # 找 UTF-16 的 0 结尾（对齐到 2 字节）
            end = start
            n = len(buf)
            while end + 1 < n and not (buf[end] == 0 and buf[end + 1] == 0):
                end += 2
            out = buf[start:end].decode("utf-16-le", "replace")
        else:
            start = off >> 1
            buf = self.str_a
            end = buf.find(b"\x00", start)
            if end < 0:
                out = ""
            else:
                raw = buf[start:end]
                try:
                    out = raw.decode("utf-8")
                except UnicodeDecodeError:
                    out = raw.decode("gb18030", "replace")
        if len(self._cache) > 200_000:
            self._cache.clear()
        self._cache[off] = out
        return out


# ---------------------------------------------------------------- 本地化表
class LazyL10n:
    """按需加载 string/<name>.chn.str，把 <N::key> 换成中文。"""

    def __init__(self, files_db: sqlite3.Connection) -> None:
        self.db = files_db
        self.paths: dict[int, str] = {}
        self.tables: dict[int, dict[str, str]] = {}
        self._lock = threading.Lock()
        self._load_index()

    def _load_index(self) -> None:
        row = self.db.execute(
            "select data,dtype from files where path=?", ("list/n_string.lst",)
        ).fetchone()
        if not row:
            return
        raw, dtype = row
        if dtype == 3:
            text = raw.decode("utf-16-le", "replace")
            for i, line in enumerate(text.splitlines()):
                self.paths[i] = line.strip().lower()
            return
        # token 流：type0=int(表序号)，type6=字符串(路径)
        idx = None
        for i in range(0, len(raw) - 4, 5):
            t = raw[i]
            v = int.from_bytes(raw[i + 1:i + 5], "little", signed=True)
            if t == 0:
                idx = v
            elif t == 6 and idx is not None:
                if v >= 0:
                    path = REF_STR.resolve(v)  # type6 的 value 是字符串池魔法偏移
                    if path:
                        self.paths[idx] = path.strip().lower()
                idx = None

    def _table(self, n: int) -> dict[str, str]:
        with self._lock:
            if n in self.tables:
                return self.tables[n]
        out: dict[str, str] = {}
        path = self.paths.get(n)
        if path:
            row = self.db.execute("select data,dtype from files where path=?", (path,)).fetchone()
            if row:
                raw, dtype = row
                body = raw.decode("utf-16-le", "replace") if dtype == 3 else raw.decode("utf-8", "replace")
                for line in body.splitlines():
                    if not line or line.startswith("//"):
                        continue
                    k, sep, v = line.partition(">")
                    if sep:
                        out[k] = v
        with self._lock:
            self.tables[n] = out
        return out

    def __call__(self, text: str) -> str:
        if not text or "<" not in text:
            return text

        def rep(m: re.Match) -> str:
            n = int(m.group(1))
            tab = self._table(n)
            return tab.get(m.group(2), m.group(0))

        return REF_RE.sub(rep, text)


REF_STR: Pools = Pools()


# ---------------------------------------------------------------- 数据层
class Store:
    def __init__(self) -> None:
        for p in (DB_FILES, DB_TREE):
            if not os.path.exists(p):
                raise SystemExit(f"缺少索引文件：{p}\n先跑 tools/pvf_new_db.py 和 tools/pvf_browser/build_tree.py")
        self.files = sqlite3.connect(DB_FILES, check_same_thread=False)
        self.tree = sqlite3.connect(DB_TREE, check_same_thread=False)
        self.lock = threading.Lock()
        self.l10n = LazyL10n(self.files)

    def q_tree(self, sql: str, args=()) -> list:
        with self.lock:
            return self.tree.execute(sql, args).fetchall()

    def q_files(self, sql: str, args=()) -> list:
        with self.lock:
            return self.files.execute(sql, args).fetchall()

    def children(self, parent: str, limit: int, offset: int) -> list:
        return self.q_tree(
            "select name,kind,size from entries where parent=? order by kind desc,name limit ? offset ?",
            (parent, limit, offset),
        )

    def count_children(self, parent: str) -> int:
        row = self.q_tree("select count(*) from entries where parent=?", (parent,))
        return row[0][0] if row else 0

    def meta(self, path: str):
        rows = self.q_files("select dtype,size,chunk,off from files where path=?", (path,))
        return rows[0] if rows else None

    def blob(self, path: str, nbytes: int | None = None) -> bytes:
        if nbytes is None:
            rows = self.q_files("select data from files where path=?", (path,))
        else:
            rows = self.q_files("select substr(data,1,?) from files where path=?", (nbytes, path))
        return rows[0][0] if rows and rows[0][0] is not None else b""

    def search_path(self, q: str, limit: int = 800) -> list:
        return self.q_tree(
            "select parent,name,kind,size from entries where name like ? order by kind desc,name limit ?",
            (f"%{q}%", limit),
        )

    def search_body(self, q: str, limit: int = 200) -> list:
        return self.q_files("select path from text where body like ? limit ?", (f"%{q}%", limit))


_HANGUL = re.compile(r"[\uac00-\ud7a3]")


def recover_korean_str(s: str) -> str:
    """把「韩文被当 GBK 解」的乱码还原成韩文原名。

    实测：根目录 15 个 name 表（aicharactername.lst / skillnameN.lst / itemname.lst …）
    里的字符串是 UTF-16 存的、内容是 cp949 韩文被 GBK 解码后的产物。
    还原 = 先按 GBK 编回原字节，再按 cp949 解。例：矫鄂 → 시란。
    """
    if not s or s.isascii():
        return s
    try:
        back = s.encode("gbk").decode("cp949")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return s
    if "\ufffd" in back or not _HANGUL.search(back):
        return s
    return back


def recover_korean(text: str) -> str:
    """只动反引号里的字符串，标签/数值不碰（中文是本地化表来的，不在反引号里）。"""
    return re.sub(r"`([^`]*)`", lambda m: "`" + recover_korean_str(m.group(1)) + "`", text)



def kor_mojibake_score(text: str) -> tuple[int, int]:
    """(非 ASCII 反引号字符串数, 其中能还原成韩文的数量)，用来判断整个文件是不是韩文乱码。"""
    total = hit = 0
    for m in re.finditer(r"`([^`]*)`", text):
        s = m.group(1)
        if not s or s.isascii():
            continue
        total += 1
        if recover_korean_str(s) != s:
            hit += 1
    return total, hit


def render(store: Store, path: str, full: bool = False, kor: bool = False):
    """返回 (kind, payload, note)。kind ∈ text/hex/err"""
    meta = store.meta(path)
    if not meta:
        return "err", "", "文件不存在"
    dtype, size, chunk, off = meta
    limit = None if full else MAX_READ_BYTES
    raw = store.blob(path, limit)
    note = ""
    if not full and size and len(raw) < size:
        note = f"只读了前 {human(len(raw))} / 共 {human(size)}（大文件预览）"
    if dtype == 3:
        body = raw.decode("utf-16-le", "replace")
        body = body.split("\x00")[0] if "\x00" in body[:4] else body
        kind = "text"
    elif dtype == 1:
        cut = len(raw) - len(raw) % 5
        try:
            kind = "text"
            body = pvfmod.decode_script(raw[:cut], REF_STR.resolve, ref=store.l10n)
        except Exception as e:  # 解码失败就给 hex，别让界面空白
            return "hex", raw, f"解码失败：{type(e).__name__}: {e}"
    else:
        return "hex", raw, "二进制（无文本解码器）"
    if kor:
        body = recover_korean(body)
        note = (note + "；" if note else "") + "已按韩文还原"
    if not full and len(body) > MAX_TEXT_CHARS:
        body = body[:MAX_TEXT_CHARS] + f"\n\n… 已截断（全文 {len(body):,} 字符，点『导出』看完整内容）"
        note = (note + "；" if note else "") + "显示已截断"
    return kind, body, note


# ---------------------------------------------------------------- 界面
class App(tk.Tk):
    def __init__(self, store: Store) -> None:
        super().__init__()
        self.store = store
        self.title("PVF Studio · 新版 DNF Script.pvf 阅读器")
        self.minsize(900, 560)
        self._fit_screen()
        self.current_path: str | None = None
        self._loading_more: dict[str, int] = {}
        self._build_ui()
        self._load_root()
        self.status(f"已就绪 · 6,288,780 个文件 · 520,799 个目录")

    def _fit_screen(self) -> None:
        """按屏幕大小开窗（WSLg 下 'zoomed' 状态不一定生效，直接算）。"""
        self.update_idletasks()
        sw = self.winfo_screenwidth() or 1600
        sh = self.winfo_screenheight() or 900
        w = max(1000, min(1800, int(sw * 0.62)))
        h = max(620, min(1150, int(sh * 0.80)))
        self.geometry(f"{w}x{h}+60+40")

    # -- 布局 ---------------------------------------------------------
    def _build_ui(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("Treeview", rowheight=22)
        style.configure("Mono.TLabel", font=("Consolas", 9))

        bar = ttk.Frame(self, padding=(8, 6))
        bar.pack(side="top", fill="x")
        ttk.Label(bar, text="搜索").pack(side="left")
        self.search_var = tk.StringVar()
        ent = ttk.Entry(bar, textvariable=self.search_var, width=34)
        ent.pack(side="left", padx=(6, 6))
        ent.bind("<Return>", lambda e: self.do_search())
        self.mode_var = tk.StringVar(value="path")
        ttk.Radiobutton(bar, text="按路径", value="path", variable=self.mode_var).pack(side="left")
        ttk.Radiobutton(bar, text="按内容", value="body", variable=self.mode_var).pack(side="left")
        ttk.Button(bar, text="搜索", command=self.do_search).pack(side="left", padx=6)
        ttk.Button(bar, text="返回目录", command=lambda: self.nb_left.select(0)).pack(side="left")
        ttk.Button(bar, text="导出当前文件", command=self.export_current).pack(side="right")
        ttk.Button(bar, text="复制路径", command=self.copy_path).pack(side="right", padx=6)
        self.wrap_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(bar, text="折行", variable=self.wrap_var, command=self.toggle_wrap).pack(side="right", padx=6)
        self.kor_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(bar, text="还原韩文", variable=self.kor_var, command=self.toggle_kor).pack(side="right", padx=6)

        paned = ttk.Panedwindow(self, orient="horizontal")
        paned.pack(fill="both", expand=True, padx=8, pady=(0, 4))

        # 左：目录树 / 搜索结果
        left = ttk.Frame(paned)
        self.nb_left = ttk.Notebook(left)
        self.nb_left.pack(fill="both", expand=True)

        tree_tab = ttk.Frame(self.nb_left)
        self.nb_left.add(tree_tab, text="目录树")
        cols = ("size",)
        self.tv = ttk.Treeview(tree_tab, columns=cols, selectmode="browse")
        self.tv.heading("#0", text="名称")
        self.tv.heading("size", text="大小")
        self.tv.column("#0", width=330, stretch=True)
        self.tv.column("size", width=90, anchor="e", stretch=False)
        vs = ttk.Scrollbar(tree_tab, orient="vertical", command=self.tv.yview)
        hs = ttk.Scrollbar(tree_tab, orient="horizontal", command=self.tv.xview)
        self.tv.configure(yscrollcommand=vs.set, xscrollcommand=hs.set)
        self.tv.grid(row=0, column=0, sticky="nsew")
        vs.grid(row=0, column=1, sticky="ns")
        hs.grid(row=1, column=0, sticky="ew")
        tree_tab.rowconfigure(0, weight=1)
        tree_tab.columnconfigure(0, weight=1)
        self.tv.bind("<<TreeviewOpen>>", self.on_open)
        self.tv.bind("<<TreeviewSelect>>", self.on_select_tree)
        self.tv.bind("<Double-1>", self.on_double)

        search_tab = ttk.Frame(self.nb_left)
        self.nb_left.add(search_tab, text="搜索结果")
        self.sr = ttk.Treeview(search_tab, columns=("size", "path"), show="headings", selectmode="browse")
        self.sr.heading("size", text="大小")
        self.sr.heading("path", text="路径 / 名称")
        self.sr.column("size", width=90, anchor="e", stretch=False)
        self.sr.column("path", width=520, stretch=True)
        svs = ttk.Scrollbar(search_tab, orient="vertical", command=self.sr.yview)
        self.sr.configure(yscrollcommand=svs.set)
        self.sr.grid(row=0, column=0, sticky="nsew")
        svs.grid(row=0, column=1, sticky="ns")
        search_tab.rowconfigure(0, weight=1)
        search_tab.columnconfigure(0, weight=1)
        self.sr.bind("<Double-1>", self.on_search_open)
        self.sr.bind("<Return>", self.on_search_open)
        paned.add(left, weight=3)

        # 右：内容
        right = ttk.Frame(paned)
        self.title_var = tk.StringVar(value="（未选择文件）")
        ttk.Label(right, textvariable=self.title_var, anchor="w", padding=(4, 4)).pack(fill="x")
        self.nb_right = ttk.Notebook(right)
        self.nb_right.pack(fill="both", expand=True)

        text_tab = ttk.Frame(self.nb_right)
        self.nb_right.add(text_tab, text="文本")
        self.text = tk.Text(text_tab, wrap="word", undo=False, font=("Consolas", 10), padx=8, pady=6)
        tvs = ttk.Scrollbar(text_tab, orient="vertical", command=self.text.yview)
        self.text.configure(yscrollcommand=tvs.set, state="disabled")
        self.text.grid(row=0, column=0, sticky="nsew")
        tvs.grid(row=0, column=1, sticky="ns")
        text_tab.rowconfigure(0, weight=1)
        text_tab.columnconfigure(0, weight=1)
        self.text.tag_configure("hit", background="#ffe066")

        hex_tab = ttk.Frame(self.nb_right)
        self.nb_right.add(hex_tab, text="HEX")
        self.hex = tk.Text(hex_tab, wrap="none", font=("Consolas", 9), padx=8, pady=6)
        hvs = ttk.Scrollbar(hex_tab, orient="vertical", command=self.hex.yview)
        self.hex.configure(yscrollcommand=hvs.set, state="disabled")
        self.hex.grid(row=0, column=0, sticky="nsew")
        hvs.grid(row=0, column=1, sticky="ns")
        hex_tab.rowconfigure(0, weight=1)
        hex_tab.columnconfigure(0, weight=1)

        info_tab = ttk.Frame(self.nb_right)
        self.nb_right.add(info_tab, text="信息")
        self.info = tk.Text(info_tab, wrap="word", font=("Consolas", 10), padx=8, pady=6)
        self.info.configure(state="disabled")
        self.info.pack(fill="both", expand=True)

        paned.add(right, weight=7)

        self.status_var = tk.StringVar(value="")
        ttk.Label(self, textvariable=self.status_var, anchor="w", padding=(8, 2)).pack(side="bottom", fill="x")

    # -- 目录树 -------------------------------------------------------
    @staticmethod
    def _is_helper(iid: str) -> bool:
        return iid.endswith(PH_SUFFIX) or iid.endswith(MORE_SUFFIX)

    def _load_root(self) -> None:
        for name, kind, size in self.store.children("", MAX_CHILDREN * 4, 0):
            iid = name
            self._add_node("", iid, name, kind, size)

    def _add_node(self, parent_iid: str, iid: str, name: str, kind: int, size: int) -> None:
        if kind == KIND_DIR:
            label = name + "/"
            self.tv.insert(parent_iid, "end", iid=iid, text=label, values=("",), open=False)
            # 占位，展开时才真正查库
            self.tv.insert(iid, "end", iid=iid + PH_SUFFIX, text="…", tags=("ph",))
        else:
            self.tv.insert(parent_iid, "end", iid=iid, text=name, values=(human(size),))

    def on_open(self, _evt=None) -> None:
        iid = self.tv.focus()
        if not iid:
            return
        kids = self.tv.get_children(iid)
        if len(kids) == 1 and kids[0].endswith(PH_SUFFIX):
            self.tv.delete(kids[0])
            self._fill_children(iid, 0)
        elif kids and kids[-1].endswith(MORE_SUFFIX):
            more = kids[-1]
            start = self._loading_more.get(iid, 0)
            self.tv.delete(more)
            self._fill_children(iid, start)

    def _fill_children(self, dir_path: str, offset: int) -> None:
        rows = self.store.children(dir_path, MAX_CHILDREN, offset)
        for name, kind, size in rows:
            self._add_node(dir_path, dir_path + "/" + name, name, kind, size)
        total = self.store.count_children(dir_path)
        done = offset + len(rows)
        self._loading_more[dir_path] = done
        if done < total:
            self.tv.insert(
                dir_path, "end", iid=dir_path + MORE_SUFFIX, text=f"… 还有 {total - done:,} 项（展开继续）",
                tags=("more",),
            )

    def on_double(self, _evt=None) -> None:
        """双击：目录展开/收起；文件直接打开。双击写在 on_select_tree 之后，避免抢焦点。"""
        iid = self.tv.focus()
        if not iid or self._is_helper(iid):
            return
        if self.store.meta(iid) is None:
            self.tv.item(iid, open=not bool(self.tv.item(iid, "open")))

    def on_select_tree(self, _evt=None) -> None:
        iid = self.tv.focus()
        if iid and not self._is_helper(iid):
            self.open_file(iid)

    # -- 打开 / 展示 ---------------------------------------------------
    def open_file(self, path: str) -> None:
        meta = self.store.meta(path)
        if not meta:
            return
        self.current_path = path
        dtype, size, chunk, off = meta
        self.title_var.set(f"{path}    [{human(size)} · dtype={dtype}]")
        self.status(f"读取 {path} …")
        self.update_idletasks()
        kind, payload, note = render(self.store, path)
        self._last_text = payload if kind == "text" else ""
        body = payload if kind == "text" else ""
        if kind == "text":
            total, hit = kor_mojibake_score(body)
            # 整个文件都是「韩文被当 GBK 解」的乱码时自动还原（根目录 name 表就是这种）
            auto = hit >= 5 and total and hit / total >= 0.5
            if auto:
                self.kor_var.set(True)
            if self.kor_var.get():
                body = recover_korean(body)
                note = (note + "；" if note else "") + (
                    f"已自动识别为韩文乱码并还原（{hit}/{total}）" if auto else "已按韩文还原"
                )
        self._set_text(self.text, body)
        if kind == "hex":
            self._set_text(self.hex, hexdump(payload))
            self.nb_right.select(1)
        else:
            self.nb_right.select(0)
        self._set_info(path, dtype, size, chunk, off, note)
        self.status(note or f"已载入 {path}")

    def _set_text(self, widget: tk.Text, body: str) -> None:
        widget.configure(state="normal")
        widget.delete("1.0", "end")
        if body:
            widget.insert("1.0", body)
        widget.configure(state="disabled")

    def _set_info(self, path: str, dtype: int, size: int, chunk: int, off: int, note: str) -> None:
        lines = [
            f"path   : {path}",
            f"size   : {size:,} B  ({human(size)})",
            f"dtype  : {dtype}   {'1=token 脚本' if dtype == 1 else '3=UTF-16 文本' if dtype == 3 else '4=二进制'}",
            f"chunk  : {chunk}",
            f"offset : {off:,}",
        ]
        if note:
            lines.append(f"note   : {note}")
        self._set_text(self.info, "\n".join(lines))

    def toggle_wrap(self) -> None:
        self.text.configure(wrap="word" if self.wrap_var.get() else "none")

    def toggle_kor(self) -> None:
        """切换「还原韩文」后重绘当前文件（只影响反引号里的字符串）。"""
        body = getattr(self, "_last_text", "")
        if not body:
            return
        if self.kor_var.get():
            body = recover_korean(body)
        self._set_text(self.text, body)
        self.nb_right.select(0)
        self.status("已开启韩文还原（反引号字符串）" if self.kor_var.get() else "已关闭韩文还原")

    def copy_path(self) -> None:
        if self.current_path:
            self.clipboard_clear()
            self.clipboard_append(self.current_path)
            self.status(f"已复制：{self.current_path}")

    def export_current(self) -> None:
        if not self.current_path:
            return
        meta = self.store.meta(self.current_path)
        if not meta:
            return
        dtype, size, _chunk, _off = meta
        name = os.path.basename(self.current_path)
        default = os.path.join(os.path.expanduser("~"), "pvf_export", name)
        out = filedialog.asksaveasfilename(initialfile=name, initialdir=os.path.dirname(default))
        if not out:
            return
        self.status("导出中…")
        self.update_idletasks()
        kind, payload, note = render(self.store, self.current_path, full=True)
        if kind == "hex":
            with open(out, "wb") as f:
                f.write(payload)
        else:
            with open(out, "w", encoding="utf-8", newline="\n") as f:
                f.write(payload)
        self.status(f"已导出 {size:,} B -> {out}")

    # -- 搜索 ---------------------------------------------------------
    def do_search(self) -> None:
        q = self.search_var.get().strip()
        if not q:
            return
        self.nb_left.select(1)
        for iid in self.sr.get_children():
            self.sr.delete(iid)
        mode = self.mode_var.get()
        self.status(f"搜索（{'内容' if mode == 'body' else '路径'}）：{q} …")
        self.update_idletasks()

        def work() -> None:
            if mode == "body":
                rows = [(p, "") for (p,) in self.store.search_body(q)]
            else:
                rows = [(parent + "/" + name if parent else name, size) for parent, name, _k, size in self.store.search_path(q)]
            self.after(0, lambda: self._show_results(rows, q))

        threading.Thread(target=work, daemon=True).start()

    def _show_results(self, rows: list, q: str) -> None:
        for iid in self.sr.get_children():
            self.sr.delete(iid)
        for path, size in rows:
            self.sr.insert("", "end", iid=path, values=(human(size), path))
        self.status(f"命中 {len(rows)} 条（{q}）；双击打开")

    def on_search_open(self, _evt=None) -> None:
        sel = self.sr.focus()
        if sel:
            self.open_file(sel)

    def status(self, msg: str) -> None:
        self.status_var.set(msg)


def hexdump(raw: bytes) -> str:
    raw = raw[:MAX_HEX_BYTES]
    out = []
    for i in range(0, len(raw), 16):
        chunk = raw[i:i + 16]
        hx = " ".join(f"{b:02x}" for b in chunk)
        asc = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append(f"{i:08x}  {hx:<47}  {asc}")
    return "\n".join(out)


# ---------------------------------------------------------------- 自检
def selftest() -> int:
    store = Store()
    probes = [
        "list/n_string.lst",
        "list/monster.lst",
        "skill/gunner/activation.skl",
        "stackable/10015001/10015138.stk",
        "clientonly/lua/ai/aistructures.lua",
        "equipment/oldequipmentstatinfolist.dat",
    ]
    ok = True
    for p in probes:
        kind, payload, note = render(store, p)
        head = payload.replace("\n", " ")[:110] if isinstance(payload, str) else ""
        print(f"[{kind:4s}] {p}\n         {head}\n         note={note}")
        if kind == "err":
            ok = False
    print("selftest", "OK" if ok else "FAIL")
    return 0 if ok else 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--open", metavar="PATH", help="启动后直接打开某个文件")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    store = Store()
    app = App(store)
    if args.open:
        app.after(300, lambda: app.open_file(args.open))
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
