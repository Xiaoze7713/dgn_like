#!/usr/bin/env python3
"""新版 PVF 内层 → sqlite 全量导出（分组读取，C 加速流密码）。

用法:
  python3 tools/pvf_new_db.py /tmp/inner/Script.inner.pvf analysis/pvf-new/pvf34.sqlite
  python3 tools/pvf_new_db.py /tmp/inner/Script.inner.pvf out.sqlite --text-exts .skl,.equ

表:
  files(path TEXT PRIMARY KEY, dtype INT, size INT, chunk INT, off INT, data BLOB)
  text (path TEXT PRIMARY KEY, body TEXT)      # 可选，解码后的脚本文本

思路（为什么快）:
  * 文件表按 chunkIndex 单调不减（实测 100%）⇒ 顺序扫一批条目就只解一次 chunk；
  * 每个 chunk 的 keystream 都从 seed0 重新开始 ⇒ 生成一次最大长度 keystream 复用；
  * 流密码用 C 实现（首次运行 gcc 编译到 /tmp/pvf_ks.so），600 MB body 秒级。
"""
from __future__ import annotations

import argparse
import ctypes
import os
import sqlite3
import struct
import subprocess
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_new_extract import HEADER_SIZE, FILE_ITEM_SIZE, GROUP_ITEM_SIZE, NewPvf, decode_script  # noqa: E402

C_SRC = r"""
#include <stdint.h>
#include <string.h>
void pvf_ks(const uint16_t *w, uint32_t magic, uint8_t *out, size_t nbytes) {
    uint32_t seed = (uint32_t)(0x339E9711u * (uint32_t)w[0]
                     + 0x393u * ((uint32_t)w[3] + 0x393u * ((uint32_t)w[2] + 0x393u * (uint32_t)w[1])));
    size_t i = 0;
    for (; i + 4 <= nbytes; i += 4) {
        uint32_t t1 = 0x343FDu * seed + magic;
        seed = 0x343FDu * t1 + magic;
        uint32_t k = (t1 & 0xFFFF0000u) + (seed >> 16);
        out[i + 0] = (uint8_t)(k & 0xFF);
        out[i + 1] = (uint8_t)((k >> 8) & 0xFF);
        out[i + 2] = (uint8_t)((k >> 16) & 0xFF);
        out[i + 3] = (uint8_t)((k >> 24) & 0xFF);
    }
    if (i < nbytes) {
        uint32_t t1 = 0x343FDu * seed + magic;
        uint32_t t2 = 0x343FDu * t1 + magic;
        uint32_t k = (t1 & 0xFFFF0000u) + ((t2 >> 16) & 0xFFFFu);
        for (size_t j = 0; i + j < nbytes; ++j)
            out[i + j] = (uint8_t)((k >> (8 * j)) & 0xFF);
    }
}
"""


def load_ks():
    so = "/tmp/pvf_ks.so"
    src = "/tmp/pvf_ks.c"
    if not os.path.exists(so):
        with open(src, "w") as fh:
            fh.write(C_SRC)
        subprocess.run(["gcc", "-O2", "-shared", "-fPIC", "-o", so, src], check=True)
    lib = ctypes.CDLL(so)
    lib.pvf_ks.argtypes = [ctypes.POINTER(ctypes.c_uint16), ctypes.c_uint32,
                           ctypes.POINTER(ctypes.c_uint8), ctypes.c_size_t]
    return lib


class FastPvf(NewPvf):
    """在 NewPvf 基础上加 C 版流密码 + 分组读取。"""

    def __init__(self, path: str) -> None:
        self._lib = load_ks()
        super().__init__(path)
        self._ks_cache: dict[tuple[str, int, int], np.ndarray] = {}

    def ks(self, key: str, magic: int, n: int) -> memoryview:
        ck = (key, magic, n)
        hit = self._ks_cache.get(ck)
        if hit is not None:
            return memoryview(hit)
        out = np.empty(n, dtype=np.uint8)
        w = (ctypes.c_uint16 * 4)(*struct.unpack("<4H", key.encode("utf-16-le")[:8]))
        self._lib.pvf_ks(w, ctypes.c_uint32(magic),
                         out.ctypes.data_as(ctypes.POINTER(ctypes.c_uint8)), ctypes.c_size_t(n))
        self._ks_cache[ck] = out
        return memoryview(out)

    def decrypt(self, key: str, data: bytes, magic: int = 0x269EC3) -> bytes:
        if not data:
            return b""
        a = np.frombuffer(data, dtype=np.uint8)
        return (a ^ self.ks(key, magic, len(data))).tobytes()

    def group_bytes(self, g: int) -> bytes:
        prev = self.groups[g - 1][0] if g else 0
        cur, _orig = self.groups[g]
        blob = self._read(self.body_off + prev, cur - prev)
        plain = self.decrypt("mAIn", blob)
        return zlib.decompress(plain)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pvf")
    ap.add_argument("db")
    ap.add_argument("--text-exts", default="", help="额外把这些后缀解码进 text 表（逗号分隔）")
    ap.add_argument("--batch", type=int, default=200_000)
    args = ap.parse_args()

    t0 = __import__("time").time()
    a = FastPvf(args.pvf)
    print(f"{args.pvf}: files={a.file_count:,} body={a.body_size:,} groups={a.group_count:,}")

    # 一次性把文件表读进内存（6.29M × 24 B = 151 MB）
    a.fh.seek(a.table_off)
    table = np.frombuffer(a.fh.read(a.file_count * FILE_ITEM_SIZE), dtype=np.int32).reshape(-1, 6)
    print(f"文件表 {table.shape} 读入 {__import__('time').time()-t0:.1f}s")

    if os.path.exists(args.db):
        os.remove(args.db)
    db = sqlite3.connect(args.db)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=OFF")
    db.execute("CREATE TABLE files(path TEXT PRIMARY KEY, dtype INT, size INT, chunk INT, off INT, data BLOB)")
    text_exts = {x.strip().lower() for x in args.text_exts.split(",") if x.strip()}
    if text_exts:
        db.execute("CREATE TABLE text(path TEXT PRIMARY KEY, body TEXT)")

    # 按 chunk 分组：chunkIndex 单调不减
    gidx = table[:, 2]
    bounds = np.searchsorted(gidx, np.arange(a.group_count + 1), side="left")

    n_written = 0
    n_text = 0
    rows = []
    trows = []
    for g in range(a.group_count):
        lo, hi = bounds[g], bounds[g + 1]
        if hi <= lo:
            continue
        buf = a.group_bytes(g)
        for i in range(lo, hi):
            no, po, ci, off, size, dt = table[i]
            path = (a.resolve(po) + "/" + a.resolve(no)) if po and no else (a.resolve(po) or a.resolve(no))
            path = path.replace("\\", "/").lstrip("./").strip()
            data = buf[off:off + size]
            rows.append((path, int(dt), int(size), int(ci), int(off), data))
            if text_exts and os.path.splitext(path)[1].lower() in text_exts:
                if dt == 1:
                    trows.append((path, decode_script(data, a.resolve)))
                elif dt == 3:
                    trows.append((path, data.decode("utf-16-le", "replace")))
        if len(rows) >= args.batch:
            db.executemany("INSERT OR REPLACE INTO files VALUES (?,?,?,?,?,?)", rows)
            n_written += len(rows)
            rows = []
            if trows:
                db.executemany("INSERT OR REPLACE INTO text VALUES (?,?)", trows)
                n_text += len(trows)
                trows = []
            db.commit()
            print(f"  chunk {g:,}/{a.group_count:,}  {n_written:,} files  {__import__('time').time()-t0:.0f}s")
    if rows:
        db.executemany("INSERT OR REPLACE INTO files VALUES (?,?,?,?,?,?)", rows)
        n_written += len(rows)
    if trows:
        db.executemany("INSERT OR REPLACE INTO text VALUES (?,?)", trows)
        n_text += len(trows)
    db.commit()
    db.execute("CREATE INDEX IF NOT EXISTS idx_ext ON files(path)")
    db.commit()
    db.close()
    print(f"完成: {n_written:,} 行 -> {args.db}  文本 {n_text:,} 行  {__import__('time').time()-t0:.0f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
