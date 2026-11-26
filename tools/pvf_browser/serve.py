#!/usr/bin/env python3
"""PVF 34 浏览器 —— 本地 web 工具，不用装任何依赖。

    python3 tools/pvf_browser/serve.py            # 默认 http://127.0.0.1:8770
    python3 tools/pvf_browser/serve.py --port 9000 --decode

数据来源：
  analysis/pvf-new/pvf34.sqlite        全量条目（6,288,780 条，二进制已在库里）
  analysis/pvf-new/pvf34.tree.sqlite   目录索引（build_tree.py 生成）
  analysis/pvf-new/inner/Script.inner.pvf  只有 `--decode` 时才需要（解析 type1 token 文本）

接口：
  GET /                        页面
  GET /api/stats               总览
  GET /api/tree?parent=        某目录下的子目录/文件
  GET /api/file?path=&raw=0    文件内容（dtype1 → 解码文本；dtype3 → UTF-16；raw=1 → hex）
  GET /api/search?q=&ext=&mode=path|text&limit=
"""
from __future__ import annotations

import argparse
import html
import json
import os
import sqlite3
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))

DB = os.path.join(ROOT, "analysis/pvf-new/pvf34.sqlite")
TREE = os.path.join(ROOT, "analysis/pvf-new/pvf34.tree.sqlite")
INNER = os.path.join(ROOT, "analysis/pvf-new/inner/Script.inner.pvf")

_DECODER = None


def db_ro(path: str) -> sqlite3.Connection:
    if not os.path.exists(path):
        raise SystemExit(f"缺少 {path}")
    c = sqlite3.connect(f"file:{path}?mode=ro", uri=True, check_same_thread=False)
    c.execute("PRAGMA temp_store=MEMORY")  # 沙箱里临时文件写不出去
    return c


def decoder():
    """按需加载 token 解码器（需要 inner pvf，占内存较多）。"""
    global _DECODER
    if _DECODER is None:
        from pvf_new_extract import NewPvf, decode_script, L10n
        pvf = NewPvf(INNER)
        try:
            l10n = L10n(pvf)
        except Exception:
            l10n = None
        _DECODER = (decode_script, l10n, pvf.resolve)
    return _DECODER


class Handler(BaseHTTPRequestHandler):
    files: sqlite3.Connection
    tree: sqlite3.Connection

    def log_message(self, *a):  # 安静点
        pass

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj) -> None:
        self._send(200, json.dumps(obj, ensure_ascii=False).encode(), "application/json; charset=utf-8")

    def do_GET(self):  # noqa: N802
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        try:
            if u.path in ("/", "/index.html"):
                p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "index.html")
                self._send(200, open(p, "rb").read(), "text/html; charset=utf-8")
            elif u.path == "/api/stats":
                self._stats()
            elif u.path == "/api/tree":
                self._tree(q.get("parent", [""])[0])
            elif u.path == "/api/file":
                self._file(q.get("path", [""])[0], q.get("raw", ["0"])[0] == "1")
            elif u.path == "/api/search":
                self._search(q)
            else:
                self._send(404, b"not found", "text/plain")
        except Exception as exc:  # noqa: BLE001
            self._json({"error": f"{type(exc).__name__}: {exc}"})

    # --- 接口 -------------------------------------------------------
    def _stats(self):
        f = self.files.execute("select count(*), sum(size) from files").fetchone()
        d = self.tree.execute("select count(*) from dirs").fetchone()[0]
        self._json({"files": f[0], "bytes": f[1], "dirs": d - 1, "exts": _exts(self.files)})

    def _tree(self, parent: str):
        parent = parent.strip("/")
        rows = self.tree.execute(
            "select name, kind, size from entries where parent=? order by kind desc, name", (parent,)).fetchall()
        info = self.tree.execute("select nfiles, nbytes from dirs where path=?", (parent,)).fetchone()
        self._json({"parent": parent, "nfiles": info[0] if info else 0, "nbytes": info[1] if info else 0,
                    "items": [{"name": n, "dir": bool(k), "size": s} for n, k, s in rows]})

    def _file(self, path: str, raw: bool):
        row = self.files.execute("select data, dtype, size from files where path=?", (path,)).fetchone()
        if not row:
            return self._json({"error": "not found", "path": path})
        data, dtype, size = row
        out = {"path": path, "dtype": dtype, "size": size, "mode": "raw"}
        if raw:
            out["hex"] = data.hex()
            out["text"] = None
            return self._json(out)
        if dtype == 3:
            out.update(mode="utf16", text=data.decode("utf-16-le", "replace"))
        elif dtype == 1:
            decode_script, l10n, resolve = decoder()
            res = l10n if l10n else (lambda v: f"<0x{v:x}>")
            try:
                out.update(mode="script", text=decode_script(data, resolve, ref=res))
            except Exception as exc:  # noqa: BLE001
                out.update(mode="script-error", text=f"{type(exc).__name__}: {exc}", hex=data.hex())
        else:
            out.update(mode="binary", hex=data.hex(), text=None)
        self._json(out)

    def _search(self, q):
        kw = q.get("q", [""])[0]
        ext = q.get("ext", [""])[0]
        mode = q.get("mode", ["path"])[0]
        limit = min(int(q.get("limit", ["200"])[0]), 2000)
        if not kw:
            return self._json({"items": []})
        if mode == "text":
            sql = "select path from text where body like ?"
            args = [f"%{kw}%"]
            if ext:
                sql += " and path like ?"
                args.append(f"%{ext}")
        else:
            sql = "select path from files where path like ?"
            args = [f"%{kw}%"]
            if ext:
                sql += " and path like ?"
                args.append(f"%{ext}")
        rows = self.files.execute(sql + " limit ?", (*args, limit)).fetchall()
        self._json({"items": [r[0] for r in rows], "truncated": len(rows) >= limit})


_EXTS = None


def _exts(files: sqlite3.Connection) -> list:
    """后缀直方图（6.29M 行扫一遍约 10–20 秒，只算一次）。"""
    global _EXTS
    if _EXTS is None:
        import collections
        c = collections.Counter()
        for (p,) in files.execute("select path from files"):
            i = p.rfind(".")
            if i > 0:
                c[p[i:].lower()] += 1
        _EXTS = [{"ext": e, "n": n} for e, n in c.most_common(40)]
    return _EXTS


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8770)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--decode", action="store_true", help="启动时加载 token 解码器（想吃 type1 文本就必须开）")
    args = ap.parse_args()

    Handler.files = db_ro(DB)
    Handler.tree = db_ro(TREE)
    if args.decode:
        print("加载 token 解码器（约 10–30 秒）…", flush=True)
        decoder()
        print("就绪", flush=True)
    print(f"PVF 浏览器: http://{args.host}:{args.port}", flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
