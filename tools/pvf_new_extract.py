#!/usr/bin/env python3
"""新版 DNF PVF (dfo_20260901_inner) 解包器。

容器外层（sk.dat 钥匙链 + 每 10 MiB 段首 0x2800 AES-CBC）由
tools/pvf_new_unwrap.py 负责；本脚本处理**内层**（已解包出的 *.inner.pvf）。

内层布局（实测 + 对照 dfo-lan 服务端 parse.go）:

    0x00  0x30   header          decryptProtected("iNfO")
    0x30  N*24   file table      明文, 每条
                                  [0:4] nameOffset  [4:8] pathOffset
                                  [8:12] chunkIndex [12:16] dataOffset
                                  [16:20] dataSize  [20:24] dataType
    ...   hashSize   hash stream   decryptProtected("HSrm")
    ...   nameSize   name section  前 8 字节前缀 + strA 帧 + strW 帧
    ...   G*8        group table   decryptProtected("Gidx")
                                   [0:4] compressedSize(累计) [4:8] originalSize
    ...   bodySize   body          body 内每个 chunk: zlib -> decryptProtected("mAIn")

header 字段: [0:4] magic 'nkpi'; [24:28] fileCount; [32:36] bodySize;
            [36:40] groupCount; [40:44] hashSize; [44:48] nameSize

字符串寻址: v&1==1 -> strW 的字节偏移 (v>>1)*2（UTF-16LE）；否则 strA 的 v>>1
           （UTF-8 / GB18030），NUL 结尾。

脚本格式 (dataType==1): 5 字节一个 token, [1B type][4B int32 value];
    type 0 整数, 2 float32, 3 换行+字符串, 5 "{5=``}", 6 `字符串`,
    type 7 换行+"{7=``}"。dataType==3 是纯 UTF-16LE 文本。
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import struct
import sys
import zlib
from collections import Counter

HEADER_SIZE = 0x30
FILE_ITEM_SIZE = 0x18
GROUP_ITEM_SIZE = 8
MAGIC_PROTECTED = 0x269EC3
MAGIC_PSTRING = 0x269EC9
M32 = 0xFFFFFFFF


# --------------------------------------------------------------------------
# 流密码（crypto.go decryptProtectedCore 的复刻）
# --------------------------------------------------------------------------
def keystream(key: str, magic: int, nbytes: int) -> bytes:
    words = list(struct.unpack("<4H", key.encode("utf-16-le")[:8]))
    seed = (0x339E9711 * words[0] + 0x393 * (words[3] + 0x393 * (words[2] + 0x393 * words[1]))) & M32
    out = bytearray()
    while len(out) < nbytes:
        t1 = (0x343FD * seed + magic) & M32
        seed = (0x343FD * t1 + magic) & M32
        out += struct.pack("<I", ((t1 & 0xFFFF0000) + (seed >> 16)) & M32)
    return bytes(out[:nbytes])


class _KsCache:
    """同 key 的 keystream 只算一次（body 每 chunk 都从 0 重新开始）。"""

    def __init__(self) -> None:
        self._cache: dict[tuple[str, int, int], bytes] = {}

    def get(self, key: str, magic: int, n: int) -> bytes:
        ck = (key, magic, n)
        if ck not in self._cache:
            self._cache[ck] = keystream(key, magic, n)
        return self._cache[ck]


_KS = _KsCache()


def decrypt_protected(key: str, data: bytes, magic: int = MAGIC_PROTECTED) -> bytes:
    if not data:
        return b""
    ks = _KS.get(key, magic, len(data))
    return bytes(a ^ b for a, b in zip(data, ks))


# --------------------------------------------------------------------------
def decode_script(raw: bytes, resolve, ref=None) -> str:
    def R(v):
        t = resolve(v)
        return ref(t) if ref else t
    parts: list[str] = []
    for off in range(0, len(raw) - 4, 5):
        ttype = raw[off]
        value = struct.unpack_from("<i", raw, off + 1)[0]
        if ttype == 0:
            parts.append(f"{value} ")
        elif ttype == 2:
            parts.append(f"{struct.unpack('<f', struct.pack('<i', value))[0]:.2f} ")
        elif ttype == 3:
            parts.append("\n    " + R(value) + "\n    ")
        elif ttype == 5:
            parts.append("\n    {")
        elif ttype == 6:
            parts.append("`" + R(value) + "` ")
        elif ttype == 7:
            parts.append("\n    }")
        elif ttype == 8:
            # 新版新增：值字符串（多为本地化引用 "<N::key>"），接在上一条标签行之后
            parts.append(R(value) + " ")
    return "".join(parts)


class NewPvf:
    def __init__(self, path: str) -> None:
        self.path = path
        self.size = os.path.getsize(path)
        self.fh = open(path, "rb")
        self._parse()

    # -- 读取工具 ----------------------------------------------------------
    def _read(self, off: int, size: int) -> bytes:
        self.fh.seek(off)
        return self.fh.read(size)

    # -- 解析 --------------------------------------------------------------
    def _parse(self) -> None:
        head = decrypt_protected("iNfO", self._read(0, HEADER_SIZE))
        self.header_plain = head
        if head[:4] != b"nkpi":
            raise SystemExit(f"{self.path}: 不是 nkpi 容器（magic={head[:4]!r}）")
        self.file_count = struct.unpack_from("<i", head, 24)[0]
        self.body_size = struct.unpack_from("<i", head, 32)[0]
        self.group_count = struct.unpack_from("<i", head, 36)[0]
        self.hash_size = struct.unpack_from("<i", head, 40)[0]
        self.name_size = struct.unpack_from("<i", head, 44)[0]

        self.table_off = HEADER_SIZE
        self.hash_off = self.table_off + self.file_count * FILE_ITEM_SIZE
        self.name_off = self.hash_off + self.hash_size
        self.group_off = self.name_off + self.name_size
        self.body_off = self.group_off + self.group_count * GROUP_ITEM_SIZE
        expect = self.body_off + self.body_size
        if expect != self.size:
            raise SystemExit(f"{self.path}: 布局自洽失败 {expect} != {self.size}")
        self._load_groups()
        self._load_names()

    def _load_groups(self) -> None:
        raw = decrypt_protected("Gidx", self._read(self.group_off, self.group_count * GROUP_ITEM_SIZE))
        self.groups = [struct.unpack_from("<ii", raw, i * 8) for i in range(self.group_count)]
        self.max_chunk = max((b - a for (a, _), (b, _) in zip([(0, 0)] + self.groups, self.groups)), default=0)

    def _load_names(self) -> None:
        names = self._read(self.name_off, self.name_size)
        pos = 8
        self.str_a, pos = self._pool(names, pos, "stAs", 0xE7ADF7EA)
        self.str_w, pos = self._pool(names, pos, "stWs", 0xB8DEA7AC)

    @staticmethod
    def _pool(names: bytes, pos: int, key: str, xor_const: int) -> tuple[bytes, int]:
        enc_size_raw, orig_size_raw = struct.unpack_from("<II", names, pos)
        pos += 8
        enc_size = enc_size_raw ^ xor_const
        blob = decrypt_protected(key, names[pos:pos + enc_size], MAGIC_PSTRING)
        pos += enc_size
        out = zlib.decompress(blob)
        if (orig_size_raw ^ enc_size) != len(out):
            raise SystemExit(f"{key} 池长度校验失败")
        return out, pos

    # -- 字符串 ------------------------------------------------------------
    def resolve(self, magic_offset: int) -> str:
        if magic_offset < 0:
            return ""
        if magic_offset & 1:
            start = (magic_offset >> 1) * 2
            end = start
            while end + 1 < len(self.str_w) and not (self.str_w[end] == 0 and self.str_w[end + 1] == 0):
                end += 2
            return self.str_w[start:end].decode("utf-16-le", "replace")
        start = magic_offset >> 1
        end = self.str_a.find(b"\0", start)
        if end < 0:
            return ""
        raw = self.str_a[start:end]
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            return raw.decode("gb18030", "replace")

    # -- 文件数据 ----------------------------------------------------------
    def chunk(self, idx: int) -> bytes:
        prev = self.groups[idx - 1][0] if idx else 0
        cur, orig = self.groups[idx]
        blob = self._read(self.body_off + prev, cur - prev)
        plain = decrypt_protected("mAIn", blob)
        try:
            return zlib.decompress(plain)
        except zlib.error:
            out = zlib.decompressobj().decompress(plain)
            if len(out) != orig:
                raise
            return out

    def read_by_path(self, path: str):
        """按路径（大小写不敏感）取原始数据；找不到返回 None。"""
        want = path.lower().lstrip("./")
        for idx, d, n, p, dt, ds, ci, do in self.entries():
            if p.lower() == want:
                return self.chunk(ci)[do:do + ds]
        return None

    def entries(self):
        """逐条产出 (index, dir, name, path, dataType, size, chunkIndex, dataOffset)"""
        remaining = self.file_count
        base = 0
        while remaining:
            batch = min(remaining, 65536)
            # 每次都要重新定位：导出模式下 chunk() 会移动同一个文件句柄
            self.fh.seek(self.table_off + base * FILE_ITEM_SIZE)
            buf = self.fh.read(batch * FILE_ITEM_SIZE)
            for i in range(batch):
                no, po, ci, do, ds, dt = struct.unpack_from("<6i", buf, i * FILE_ITEM_SIZE)
                d = self.resolve(po)
                n = self.resolve(no)
                p = (d + "/" + n) if d and n else (d or n)
                p = p.replace("\\", "/").lstrip("./").strip()
                yield base + i, d, n, p, dt, ds, ci, do
            base += batch
            remaining -= batch



# --------------------------------------------------------------------------
# 本地化：脚本里的字符串值多为 "<N::key>" 引用
#   N  = list/n_string.lst 里的表序号 -> "String/<Name>.chn.str"
#   表 = UTF-16LE 文本，每行 "key>文本"
# --------------------------------------------------------------------------
import re as _re

_REF_RE = _re.compile(r"<(\d+)::([^<>]+)>")


class L10n:
    def __init__(self, pvf: "NewPvf") -> None:
        self.pvf = pvf
        self.tables: dict[int, str] = {}
        self.cache: dict[str, dict[str, str]] = {}
        self._load_index()

    def _load_index(self) -> None:
        raw = self.pvf.read_by_path("list/n_string.lst")
        if raw is None:
            return
        idx = None
        for off in range(0, len(raw) - 4, 5):
            t = raw[off]
            v = struct.unpack_from("<i", raw, off + 1)[0]
            if t == 0:
                idx = v
            elif t in (6, 3, 8) and idx is not None:
                self.tables[idx] = self.pvf.resolve(v).lower()
                idx = None

    def table(self, n: int) -> dict[str, str]:
        path = self.tables.get(n)
        if path is None:
            return {}
        if path not in self.cache:
            d: dict[str, str] = {}
            raw = self.pvf.read_by_path(path)
            if raw:
                for line in raw.decode("utf-16-le", "replace").splitlines():
                    line = line.strip("\ufeff")
                    if not line or line.startswith("//") or ">" not in line:
                        continue
                    k, _, v = line.partition(">")
                    d[k.strip()] = v
            self.cache[path] = d
        return self.cache[path]

    def __call__(self, text: str) -> str:
        if "<" not in text:
            return text
        def rep(m):
            n, key = int(m.group(1)), m.group(2)
            return self.table(n).get(key, m.group(0))
        return _REF_RE.sub(rep, text)


def main() -> int:
    ap = argparse.ArgumentParser(description="新版 DNF PVF 内层解包")
    ap.add_argument("pvf", help="*.inner.pvf 路径")
    ap.add_argument("--list", metavar="OUT.tsv.gz", help="导出全部条目索引（gz）")
    ap.add_argument("--stats", metavar="OUT.json", help="导出统计")
    ap.add_argument("--extract", metavar="DIR", help="按过滤条件导出文件内容")
    ap.add_argument("--types", default="", help="只导出这些 dataType（逗号分隔）")
    ap.add_argument("--prefix", default="", help="只导出路径以此开头的条目（逗号分隔）")
    ap.add_argument("--suffix", default="", help="只导出这些后缀（逗号分隔）")
    ap.add_argument("--xform", default="auto", choices=["auto", "raw", "script", "utf16"])
    ap.add_argument("--limit", type=int, default=0, help="最多导出多少个文件")
    ap.add_argument("--no-zh", action="store_true", help="不做 <N::key> 本地化解析")
    args = ap.parse_args()

    a = NewPvf(args.pvf)
    print(f"{args.pvf}: {a.size:,} B  files={a.file_count:,} body={a.body_size:,} "
          f"groups={a.group_count:,} hash={a.hash_size:,} names={a.name_size:,} "
          f"bodyOff={a.body_off:,} maxChunk={a.max_chunk:,}")
    print(f"header words: {list(struct.unpack('<12I', a.header_plain))}")
    print(f"strA={len(a.str_a):,} B  strW={len(a.str_w):,} B")

    ref = None
    if not args.no_zh:
        l10n = L10n(a)
        print(f"本地化表 {len(l10n.tables)} 张")
        ref = l10n
    types = {int(x) for x in args.types.split(",") if x.strip()}
    prefixes = [x for x in args.prefix.split(",") if x]
    suffixes = {x.lower() for x in args.suffix.split(",") if x}

    stat = Counter()
    top = Counter()
    ext = Counter()
    type_sizes = Counter()
    type_count = Counter()
    lister = gzip.open(args.list, "wt", encoding="utf-8") if args.list else None
    extracted = 0
    written = 0
    try:
        for idx, d, n, p, dt, ds, ci, do in a.entries():
            type_count[dt] += 1
            type_sizes[dt] += ds
            if lister:
                lister.write(f"{p}\t{dt}\t{ds}\t{ci}\t{do}\n")
            head = p.split("/", 1)[0] if "/" in p else "(root)"
            top[head] += 1
            ext[os.path.splitext(p)[1].lower()] += 1
            stat["files"] += 1
            stat["bytes"] += ds
            if not args.extract:
                continue
            if types and dt not in types:
                continue
            if prefixes and not any(p.startswith(x) for x in prefixes):
                continue
            if suffixes and os.path.splitext(p)[1].lower() not in suffixes:
                continue
            if args.limit and extracted >= args.limit:
                continue
            try:
                raw = a.chunk(ci)[do:do + ds]
            except Exception as exc:  # noqa: BLE001
                stat["errors"] += 1
                print(f"  ! {p}: {exc}", file=sys.stderr)
                continue
            xform = args.xform
            if xform == "auto":
                xform = "script" if dt == 1 else ("utf16" if dt == 3 else "raw")
            if xform == "script":
                data = decode_script(raw, a.resolve, ref).encode("utf-8")
            elif xform == "utf16":
                data = raw.decode("utf-16-le", "replace").encode("utf-8")
            else:
                data = raw
            out = os.path.join(args.extract, p)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            with open(out, "wb") as fh:
                fh.write(data)
            extracted += 1
            written += len(data)
    finally:
        if lister:
            lister.close()

    print(f"条目 {stat['files']:,} 总计 {stat['bytes']:,} B（解压后）")
    print("dataType 分布（数量 / 解压总字节）:", {k: (type_count[k], type_sizes[k]) for k in sorted(type_count)})
    print("顶层目录 Top20:", top.most_common(20))
    print("后缀 Top25:", ext.most_common(25))
    if args.extract:
        print(f"导出 {extracted:,} 个文件, {written:,} B -> {args.extract}")
    if args.stats:
        with open(args.stats, "w", encoding="utf-8") as fh:
            json.dump({
                "pvf": args.pvf,
                "size": a.size,
                "fileCount": a.file_count,
                "bodySize": a.body_size,
                "groupCount": a.group_count,
                "hashSize": a.hash_size,
                "nameSize": a.name_size,
                "bodyOffset": a.body_off,
                "maxChunk": a.max_chunk,
                "strA": len(a.str_a),
                "strW": len(a.str_w),
                "types": {str(k): {"count": type_count[k], "bytes": type_sizes[k]} for k in type_count},
                "topDirs": top.most_common(60),
                "extensions": ext.most_common(120),
            }, fh, ensure_ascii=False, indent=2)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
