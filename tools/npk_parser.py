#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPK / IMG 解析与解码器（DNF 客户端图像包）。

纯 Python 实现（struct + zlib + 可选 numpy），无第三方必需依赖。

    # 列出一个 NPK 里的所有 img
    python3 tools/npk_parser.py list "<npk路径或文件名>"

    # 在 ImagePacks2 里模糊找 img
    python3 tools/npk_parser.py find "swordman/effect/animation"

    # 看一个 img 的头与逐帧字段
    python3 tools/npk_parser.py info "<npk>" "sprite/.../x.img"

    # 导出所有帧为 PNG
    python3 tools/npk_parser.py dump "<npk>" "sprite/.../x.img" --out /tmp/out

    # 统计整个目录的版本/帧类型分布
    python3 tools/npk_parser.py census

    # 吞吐压测
    python3 tools/npk_parser.py bench --n 200

设计要点见 docs/NPK-FORMAT.md。所有 NPK 只读，不写回原始目录。
"""

from __future__ import annotations

import argparse
import json
import os
import random
import struct
import sys
import time
import zlib

try:  # 可选：只用于加速 DXT 解码与像素转换，缺失也能跑
    import numpy as _np
except Exception:  # pragma: no cover
    _np = None


# --------------------------------------------------------------------------
# 常量
# --------------------------------------------------------------------------

NPK_MAGIC = b"NeoplePack_Bill\x00"
IMG_MAGIC = b"Neople Img File\x00"
NPK_ENTRY_SIZE = 264          # i32 offset + i32 size + 256B xor 文件名
NPK_SUM_SIZE = 32             # 头 + 索引表的 SHA-256

# 256 字节文件名密钥："puchikon@neople dungeon and fighter " 之后 "DNF" 循环，末字节 \0
_NAME_SEED = b"puchikon@neople dungeon and fighter "
IMG_NAME_KEY = (_NAME_SEED + b"DNF" * 256)[:255] + b"\x00"
assert len(IMG_NAME_KEY) == 256

# 帧类型
T_INDEXED = 0x0E      # v2/v5 里等于 ARGB1555；v4/v6 里是调色板索引
T_ARGB1555 = 0x0E
T_ARGB4444 = 0x0F
T_ARGB8888 = 0x10
T_REFERENCE = 0x11
T_FXT1 = 0x12
T_FXT2 = 0x13
T_FXT3 = 0x14
FXT_TYPES = (T_FXT1, T_FXT2, T_FXT3)

# 帧体压缩方式
C_RAW = 0x05          # 未压缩
C_ZLIB = 0x06         # zlib 内联在帧数据区
C_DDSREF = 0x07       # 帧体在共享 DDS 表里（v5 特有，记录长 64 字节）

TYPE_NAMES = {
    T_ARGB1555: "ARGB1555",
    T_ARGB4444: "ARGB4444",
    T_ARGB8888: "ARGB8888",
    T_REFERENCE: "REFERENCE",
    T_FXT1: "FXT1(DXT1)",
    T_FXT2: "FXT2(DXT3)",
    T_FXT3: "FXT3(DXT5)",
}

DEFAULT_PACK_DIR = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)   # 仓库根目录


class NpkError(Exception):
    """结构错误 / 不支持的版本 / 有向环。"""


# --------------------------------------------------------------------------
# 名字
# --------------------------------------------------------------------------

def decode_name(raw256: bytes) -> str:
    """索引表里的 256 字节异或密文 -> 文件名（DNF 用 GBK 存名）。"""
    plain = bytes(b ^ IMG_NAME_KEY[i] for i, b in enumerate(raw256))
    plain = plain.split(b"\x00", 1)[0]
    for enc in ("gbk", "utf-8", "latin-1"):
        try:
            return plain.decode(enc)
        except UnicodeDecodeError:
            continue
    return plain.decode("latin-1")


def encode_name(name: str) -> bytes:
    raw = name.encode("gbk")[:255]
    raw = raw + b"\x00" * (256 - len(raw))
    return bytes(b ^ IMG_NAME_KEY[i] for i, b in enumerate(raw))


# --------------------------------------------------------------------------
# NPK 容器
# --------------------------------------------------------------------------

class NpkEntry(object):
    __slots__ = ("name", "offset", "size")

    def __init__(self, name, offset, size):
        self.name = name
        self.offset = offset
        self.size = size

    def __repr__(self):
        return "NpkEntry(%r, %d, %d)" % (self.name, self.offset, self.size)


class Npk(object):
    """只解析索引；img 数据按需读（33GB 不能整个读进来）。"""

    def __init__(self, path, verify=False):
        self.path = path
        self.file_size = os.path.getsize(path)
        self.entries = []
        self.verify_ok = None
        with open(path, "rb") as f:
            head = f.read(20)
            if len(head) < 20 or head[:16] != NPK_MAGIC:
                raise NpkError("不是 NPK：%s（magic=%r）" % (path, head[:16]))
            self.count = struct.unpack("<I", head[16:20])[0]
            need = 20 + self.count * NPK_ENTRY_SIZE + NPK_SUM_SIZE
            if need > self.file_size:
                raise NpkError(
                    "索引越界：声明 %d 条目需要 %d 字节，文件只有 %d"
                    % (self.count, need, self.file_size))
            blob = f.read(self.count * NPK_ENTRY_SIZE)
            if len(blob) != self.count * NPK_ENTRY_SIZE:
                raise NpkError("索引表被截断")
            for i in range(self.count):
                base = i * NPK_ENTRY_SIZE
                off, size = struct.unpack_from("<ii", blob, base)
                self.entries.append(
                    NpkEntry(decode_name(blob[base + 8: base + NPK_ENTRY_SIZE]), off, size))
            if verify:
                self.verify_ok = self._verify(f)

    def _verify(self, f):
        f.seek(0)
        body = f.read(20 + self.count * NPK_ENTRY_SIZE)
        digest = f.read(NPK_SUM_SIZE)
        cut = len(body) // 17 * 17
        import hashlib
        return hashlib.sha256(body[:cut]).digest() == digest

    # -- 查询 ------------------------------------------------------------
    def names(self):
        return [e.name for e in self.entries]

    def find(self, needle, limit=0):
        needle = needle.lower()
        out = []
        for i, e in enumerate(self.entries):
            if needle in e.name.lower():
                out.append((i, e))
                if limit and len(out) >= limit:
                    break
        return out

    def index_of(self, name):
        for i, e in enumerate(self.entries):
            if e.name == name:
                return i
        low = name.lower()
        for i, e in enumerate(self.entries):
            if e.name.lower() == low:
                return i
        if "%" in name:
            exp = self.expand_pattern(name)
            if exp:
                return self.index_of(exp[0])
        hits = self.find(name, limit=8)
        if len(hits) == 1:
            return hits[0][0]
        if not hits:
            raise NpkError("%s 里没有匹配 %r 的条目" % (os.path.basename(self.path), name))
        # 同一个名字在包里出现多次（真实语料里很常见，如 sprite/worldmap/lorien.img
        # 连出现两次）→ 取第一条；名字不同才算歧义。
        names = {self.entries[h[0]].name for h in hits}
        if len(names) == 1:
            return hits[0][0]
        raise NpkError("%r 在 %s 里匹配到 %d 个不同条目，请写全名：%s"
                       % (name, os.path.basename(self.path), len(names),
                          ", ".join(sorted(names)[:4])))

    def expand_pattern(self, name):
        """展开 sm_body%04d.img 这类「按装扮 id 编号」的模板名。

        PVF 里装扮引用的是模板（`%04d` 由玩家当前装扮 id 填），
        所以语料里没有这个字面条目。返回包里所有匹配的真实条目名（升序）。
        """
        import re
        if "%" not in name:
            return [name] if any(e.name.lower() == name.lower() for e in self.entries) else []
        parts = re.split(r"%0?\d*d", name)
        if len(parts) != 2:
            return []
        rx = re.compile("^" + re.escape(parts[0]) + r"(\d+)" + re.escape(parts[1]) + "$",
                        re.IGNORECASE)
        out = []
        for e in self.entries:
            m = rx.match(e.name)
            if m:
                out.append((int(m.group(1)), e.name))
            else:
                m = rx.match(e.name[len("sprite/"):]) if e.name.lower().startswith("sprite/") else None
                if m:
                    out.append((int(m.group(1)), e.name))
        out.sort()
        return [n for _, n in out]

    def read(self, name):
        i = self.index_of(name)
        return self.read_index(i)

    def read_index(self, i, limit=None):
        """读条目内容。limit 只读前 limit 字节（普查时省内存/IO）。"""
        e = self.entries[i]
        if e.offset < 0 or e.size < 0 or e.offset + e.size > self.file_size:
            raise NpkError("条目 %r 偏移越界（off=%d size=%d 文件=%d）"
                           % (e.name, e.offset, e.size, self.file_size))
        n = e.size if limit is None else min(e.size, limit)
        with open(self.path, "rb") as f:
            f.seek(e.offset)
            data = f.read(n)
        if len(data) != n:
            raise NpkError("条目 %r 读到的字节数不足" % (e.name,))
        return data

    def open_img(self, name):
        """返回 (Img, entry_name)。.ogg 会抛 NpkError。"""
        i = self.index_of(name)
        e = self.entries[i]
        data = self.read_index(i)
        if not data.startswith(IMG_MAGIC):
            raise NpkError("条目 %r 不是 IMG（前 16 字节 %r）" % (e.name, data[:16]))
        return Img(data), e.name


# --------------------------------------------------------------------------
# IMG
# --------------------------------------------------------------------------

class Frame(object):
    __slots__ = ("index", "type", "compressed", "width", "height", "length",
                 "x", "y", "frame_width", "frame_height",
                 "reference", "dds_index", "left", "up", "right", "down", "raw",
                 "_consumed", "truncated", "length_declared", "bpp")

    def __init__(self):
        self._consumed = 36
        self.truncated = False
        self.length_declared = None
        self.bpp = 0
        self.index = -1
        self.type = 0
        self.compressed = 0
        self.width = 0
        self.height = 0
        self.length = 0
        self.x = 0
        self.y = 0
        self.frame_width = 0
        self.frame_height = 0
        self.reference = -1
        self.dds_index = -1
        self.left = 0
        self.up = 0
        self.right = 0
        self.down = 0
        self.raw = None

    @property
    def is_reference(self):
        return self.type == T_REFERENCE

    @property
    def is_fxt(self):
        return self.type in FXT_TYPES

    def type_name(self):
        if self.is_reference:
            return "REFERENCE->%d" % self.reference
        return TYPE_NAMES.get(self.type, "0x%02X" % self.type)

    def crop_size(self):
        return (self.right - self.left, self.down - self.up)


class Img(object):
    """一整个 .img。构造时解析头 + 全部帧记录，帧体按需解码。"""

    def __init__(self, data, parse_bodies=True, cycle_policy="raise"):
        """cycle_policy: "raise"（默认，自检/严格模式）或 "degrade"（图集管线用：
        有环的帧记成空帧并累计到 self.cycles，不中断整张图解包）。"""
        self.data = data
        self.cycle_policy = cycle_policy
        self.cycles = []
        if len(data) < 32:
            raise NpkError("IMG 数据太短（%d 字节，至少 32）" % (len(data),))
        if data[:16] != IMG_MAGIC:
            raise NpkError("不是 IMG（前 16 字节 %r）" % (data[:16],))
        self.table_length, self._skip, self.version, self.frame_count = \
            struct.unpack_from("<IIII", data, 16)
        if self.version not in (1, 2, 4, 5, 6):
            raise NpkError("不支持的 IMG 版本 v%d" % self.version)
        self.warnings = []          # 可降级的异常（不中断解析）
        self.palettes = []          # [(bytes RGBA*N)]
        self.dds_table = []         # [{title,pixel_format,index,full_length,length,width,height,raw}]
        pos = 32
        pos = self._read_version_header(pos)
        self.frames = []
        for i in range(self.frame_count):
            f = self._read_frame(pos, i)
            f.bpp = self._bpp_for(f.type)
            pos += f._consumed
            self.frames.append(f)
        self._resolve_references()
        if parse_bodies:
            pos = self._read_bodies(pos)
        self.body_end = pos

    # -- 头 --------------------------------------------------------------
    def _read_version_header(self, pos):
        d = self.data
        if self.version == 4:
            n = struct.unpack_from("<i", d, pos)[0]
            pos += 4
            self.palettes.append(d[pos:pos + n * 4])
            pos += n * 4
        elif self.version == 5:
            dds_count, _img_len, color_num = struct.unpack_from("<iii", d, pos)
            pos += 12
            self.palettes.append(d[pos:pos + color_num * 4])
            pos += color_num * 4
            for _ in range(dds_count):
                (title, pf, idx, full_len, raw_len, w, h) = \
                    struct.unpack_from("<7i", d, pos)
                pos += 28
                self.dds_table.append({
                    "title": title, "pixel_format": pf, "index": idx,
                    "full_length": full_len, "length": raw_len,
                    "width": w, "height": h, "raw": None,
                })
        elif self.version == 6:
            pal_count = struct.unpack_from("<i", d, pos)[0]
            pos += 4
            for _ in range(pal_count):
                n = struct.unpack_from("<i", d, pos)[0]
                pos += 4
                self.palettes.append(d[pos:pos + n * 4])
                pos += n * 4
        # v1 / v2 无附加头
        return pos

    # -- 帧记录 ----------------------------------------------------------
    def _bpp_for(self, ftype):
        """每像素字节数（未压缩帧算体长用）。"""
        if ftype == T_ARGB8888:
            return 4
        if ftype in (0x0F, 0x0E):
            # 0x0E：v2 是 ARGB1555（2B），v4/v6 是调色板索引（1B）
            if ftype == 0x0E and self.version in (4, 6):
                return 1
            return 2
        return 0

    def _read_frame(self, pos, index):
        d = self.data
        if pos + 4 > len(d):
            raise NpkError("帧记录越界（帧 %d）" % index)
        ftype = struct.unpack_from("<i", d, pos)[0]
        f = Frame()
        f.index = index
        f.type = ftype
        if ftype == T_REFERENCE:
            if pos + 8 > len(d):
                raise NpkError("指向帧记录越界（帧 %d）" % index)
            f.reference = struct.unpack_from("<i", d, pos + 4)[0]
            f._consumed = 8
            return f
        if pos + 36 > len(d):
            raise NpkError("帧记录越界（帧 %d）" % index)
        (f.compressed, f.width, f.height, f.length,
         f.x, f.y, f.frame_width, f.frame_height) = struct.unpack_from("<8i", d, pos + 4)
        # v5 实测：compressed==0x07 的帧体在共享 DDS 表里，记录额外带
        # skip4 / ddsIndex / left / up / right / down / skip4（共 64 字节）。
        if self.version == 5 and (f.compressed == C_DDSREF or f.is_fxt):
            if pos + 64 > len(d):
                raise NpkError("DDS 帧记录越界（帧 %d）" % index)
            (_skip1, f.dds_index, f.left, f.up, f.right, f.down, _skip2) = \
                struct.unpack_from("<7i", d, pos + 36)
            f._consumed = 64
        else:
            f._consumed = 36
        return f

    # -- 指向帧解析（含环检测） -------------------------------------------
    def _resolve_references(self, max_depth=64):
        """把 reference 链解析成真实帧号；有环抛 NpkError（绝不递归挂死）。"""
        self.resolved = []
        for f in self.frames:
            if not f.is_reference:
                self.resolved.append(f.index)
                continue
            seen = {f.index}
            cur = f.reference
            depth = 0
            while True:
                if cur < 0 or cur >= len(self.frames):
                    # 真实语料里存在指向越界的引用帧（如 fighter 的
                    # fm_body0121.img 末帧 -> 越界）：这不是「环」，
                    # 降级成「该帧无图像」，记进 warnings，别整张图作废。
                    self.warnings.append(
                        "帧 %d 指向越界帧 %d，按无图像处理" % (f.index, cur))
                    self.resolved.append(-1)
                    cur = None
                    break
                if cur in seen:
                    msg = ("指向帧存在有向环：帧 %d -> %d -> ... -> %d"
                           % (f.index, f.reference, cur))
                    if self.cycle_policy == "degrade":
                        self.cycles.append({"frame": f.index, "cycle_to": cur})
                        self.warnings.append(msg)
                        self.resolved.append(-1)
                        cur = None
                        break
                    raise NpkError(msg)
                depth += 1
                if depth > max_depth:
                    msg = "指向帧链过深（>%d），起点帧 %d" % (max_depth, f.index)
                    if self.cycle_policy == "degrade":
                        self.cycles.append({"frame": f.index, "cycle_to": cur})
                        self.warnings.append(msg)
                        self.resolved.append(-1)
                        cur = None
                        break
                    raise NpkError(msg)
                seen.add(cur)
                nxt = self.frames[cur]
                if not nxt.is_reference:
                    self.resolved.append(cur)
                    break
                cur = nxt.reference

    # -- 帧体 ------------------------------------------------------------
    def _read_bodies(self, pos):
        d = self.data
        # v5：先 全部 DDS 裸数据，再 各内联帧体
        if self.version == 5:
            for rec in self.dds_table:
                n = rec["full_length"]
                rec["raw"] = d[pos:pos + n]
                pos += n
        for f in self.frames:
            if f.is_reference:
                continue
            if self.version == 5 and f.compressed == C_DDSREF:
                continue  # 帧体在 DDS 表
            n = f.length
            if f.compressed == C_RAW:
                # 未压缩帧的真实体长由 w*h*bpp 决定；语料里存在 length 写错的情况
                # （如 goblin acc2.img 的 1x1 帧写 length=4，实际 2 字节），
                # 按 length 走会连带后面所有帧错位，所以这里以几何尺寸为准。
                exp = f.width * f.height * (f.bpp or 1)
                if exp != n:
                    f.length_declared = n
                    n = exp
                    f.length = exp
            if n < 0:
                raise NpkError("帧 %d 的 length 为负（%d）" % (f.index, n))
            f.raw = d[pos:pos + n]
            if len(f.raw) < n:
                # 真实语料里存在「声明 N 字节、实际只给 N-4」的截断帧
                # （如 sprite_monster_goblin_equipment 的 acc2.img 末帧）。
                # 直接报错会让整张图不可用，这里降级为「尽力解码 + 标记」。
                f.truncated = True
                pos += len(f.raw)
                continue
            pos += n
        self.body_end = pos
        return pos

    # -- 解码 ------------------------------------------------------------
    def palette(self, i=0):
        if not self.palettes or i >= len(self.palettes):
            return None
        return self.palettes[i]

    def frame_image(self, index):
        """帧号 -> (w, h, x, y, rgba bytes)。指向帧会解析到真实帧。"""
        if index < 0 or index >= len(self.frames):
            raise IndexError("帧号 %d 超出范围（共 %d 帧）" % (index, len(self.frames)))
        real = self.resolved[index]
        if real < 0:
            # 指向越界/无图的帧 -> 1x1 全透明占位，保证帧号连续可用
            return (1, 1, 0, 0, b"\x00\x00\x00\x00")
        f = self.frames[real]
        if self.version == 5 and f.compressed == C_DDSREF:
            return self._decode_dds_frame(f)
        data = self._inflate(f)
        w, h = f.width, f.height
        t = f.type
        if t == T_ARGB8888:
            px = _to_rgba8888(data, w, h)
        elif t == T_ARGB4444:
            px = _to_rgba4444(data, w, h)
        elif t == T_ARGB1555:
            if self.version in (4, 6):
                px = _to_rgba_indexed(data, w, h, self.palette())
            else:
                px = _to_rgba1555(data, w, h)
        elif t == T_INDEXED and self.version in (4, 6):
            px = _to_rgba_indexed(data, w, h, self.palette())
        else:
            raise NpkError("v%d 帧 %d 类型 0x%02X 不支持" % (self.version, real, t))
        return (w, h, f.x, f.y, px)

    def _decode_dds_frame(self, f):
        rec = self.dds_table[f.dds_index] if 0 <= f.dds_index < len(self.dds_table) else None
        if rec is None:
            raise NpkError("帧 %d 的 ddsIndex=%d 越界（表大小 %d）"
                           % (f.index, f.dds_index, len(self.dds_table)))
        if rec["raw"] is None:
            raise NpkError("DDS %d 没有读到裸数据" % f.dds_index)
        blob = rec["raw"]
        if blob[:2] in (b"\x78\x01", b"\x78\x9c", b"\x78\xda") or f.compressed == C_DDSREF:
            try:
                blob = zlib.decompress(blob)
            except zlib.error as e:
                raise NpkError("DDS %d zlib 解压失败：%s" % (f.dds_index, e))
        dw, dh = rec["width"], rec["height"]
        rgba = _decode_dds_or_raw(blob, dw, dh, rec["pixel_format"])
        left, up = f.left, f.up
        right, down = f.right, f.down
        cw, ch = right - left, down - up
        if cw < 0 or ch < 0:
            raise NpkError("帧 %d 裁剪矩形反了（l=%d u=%d r=%d d=%d）"
                           % (f.index, left, up, right, down))
        if cw > dw or ch > dh:
            raise NpkError("帧 %d 裁剪 %dx%d 超出 DDS %dx%d"
                           % (f.index, cw, ch, dw, dh))
        cropped = _crop(rgba, dw, dh, left, up, cw, ch)
        return (cw, ch, f.x, f.y, cropped)

    def _inflate(self, f):
        raw = f.raw
        if raw is None:
            raise NpkError("帧 %d 没有帧体" % f.index)
        if f.compressed == C_RAW:
            return raw
        if f.compressed in (C_ZLIB, C_DDSREF):
            try:
                return zlib.decompress(raw)
            except zlib.error as e:
                if getattr(f, "truncated", False):
                    # 截断帧：zlib 流不完整，用 decompressobj 抢救已解出的部分
                    try:
                        o = zlib.decompressobj()
                        return o.decompress(raw)
                    except zlib.error:
                        pass
                raise NpkError("帧 %d zlib 解压失败：%s（%d 字节）" % (f.index, e, len(raw)))
        raise NpkError("帧 %d 未知压缩方式 0x%02X" % (f.index, f.compressed))

    # -- 元信息 ----------------------------------------------------------
    def describe(self):
        rows = [{
            "index": f.index,
            "type": f.type_name(),
            "raw_type": "0x%02X" % f.type,
            "compressed": f.compressed,
            "width": f.width,
            "height": f.height,
            "length": f.length,
            "x": f.x,
            "y": f.y,
            "frame_width": f.frame_width,
            "frame_height": f.frame_height,
        } for f in self.frames]
        return {
            "version": self.version,
            "frame_count": self.frame_count,
            "palettes": [len(p) // 4 for p in self.palettes],
            "dds_count": len(self.dds_table),
            "dds": [{k: v for k, v in r.items() if k != "raw"} for r in self.dds_table],
            "frames": rows,
        }


# --------------------------------------------------------------------------
# 像素格式转换
# --------------------------------------------------------------------------

def _to_rgba8888(data, w, h):
    """ARGB8888：每像素 4 字节，**内存顺序 B,G,R,A**（D3D9 的 A8R8G8B8，
    即小端 u32 = 0xAARRGGBB），不是 R,G,B,A。

    证据（2026-11 复核，见 docs/NPK-FRAME-BYTES.md §4）：
    - `sprite/interface2/hud/hp_vessel.img`（HP 血球，8888）按 B,G,R,A 解=红球，
      按 R,G,B,A 解=蓝球；`mp_vessel.img` 正好反过来 → 两者必须是红/蓝。
    - `avatar/skin/sm_body0000.img`（裸体皮肤模型，8888）按 B,G,R,A 解=正常肤色，
      按 R,G,B,A 解=整具蓝人。
    旧版文档误用 ARGB1555 的帧当 8888 的证据，已纠正。
    """
    need = w * h * 4
    n = len(data) // 4
    if len(data) < need:
        # 真实语料里有「几何说 N 字节、实际少几十字节」的帧，
        # 补零比整张图作废划算（缺的通常是边缘空白）。
        n = len(data) // 4
        data = bytes(data) + b"\x00" * (need - len(data))
    out = bytearray(need)
    # B,G,R,A -> R,G,B,A
    out[0::4] = data[2::4]
    out[1::4] = data[1::4]
    out[2::4] = data[0::4]
    out[3::4] = data[3::4]
    return bytes(out)


def _to_rgba1555(data, w, h):
    """ARGB1555：每像素 2 字节小端；bit15=A, 14-10=R, 9-5=G, 4-0=B。"""
    n = w * h
    need = n * 2
    if len(data) < need:
        data = bytes(data) + b"\x00" * (need - len(data))
    out = bytearray(n * 4)
    for i in range(n):
        v = data[2 * i] | (data[2 * i + 1] << 8)
        a = 255 if (v & 0x8000) else 0
        r = (v >> 10) & 0x1F
        g = (v >> 5) & 0x1F
        b = v & 0x1F
        o = i * 4
        out[o] = (r << 3) | (r >> 2)
        out[o + 1] = (g << 3) | (g >> 2)
        out[o + 2] = (b << 3) | (b >> 2)
        out[o + 3] = a
    return bytes(out)


def _to_rgba4444(data, w, h):
    """ARGB4444：每像素 2 字节小端；bit15-12=A, 11-8=R, 7-4=G, 3-0=B。"""
    n = w * h
    need = n * 2
    if len(data) < need:
        data = bytes(data) + b"\x00" * (need - len(data))
    out = bytearray(n * 4)
    for i in range(n):
        v = data[2 * i] | (data[2 * i + 1] << 8)
        a = (v >> 12) & 0xF
        r = (v >> 8) & 0xF
        g = (v >> 4) & 0xF
        b = v & 0xF
        o = i * 4
        out[o] = r * 17
        out[o + 1] = g * 17
        out[o + 2] = b * 17
        out[o + 3] = a * 17
    return bytes(out)


def _to_rgba_indexed(data, w, h, palette):
    """调色板索引帧（v4/v6）：每像素 1 字节索引，调色板条目 4 字节 RGBA。"""
    if palette is None:
        raise NpkError("索引帧但 IMG 没有调色板")
    n = w * h
    if len(data) < n:
        data = bytes(data) + b"\x00" * (n - len(data))
    colors = len(palette) // 4
    out = bytearray(n * 4)
    for i in range(n):
        idx = data[i]
        if idx >= colors:
            idx = 0
        o = i * 4
        p = idx * 4
        out[o] = palette[p]
        out[o + 1] = palette[p + 1]
        out[o + 2] = palette[p + 2]
        out[o + 3] = palette[p + 3]
    return bytes(out)


def _crop(rgba, w, h, left, up, cw, ch):
    if left == 0 and up == 0 and cw == w and ch == h:
        return rgba
    if _np is not None:
        a = _np.frombuffer(rgba, dtype=_np.uint8).reshape(h, w, 4)
        return a[up:up + ch, left:left + cw].copy().tobytes()
    out = bytearray(cw * ch * 4)
    for y in range(ch):
        src = ((up + y) * w + left) * 4
        dst = y * cw * 4
        out[dst:dst + cw * 4] = rgba[src:src + cw * 4]
    return bytes(out)


# --------------------------------------------------------------------------
# DDS（v5 的 DXT 贴图）
# --------------------------------------------------------------------------

def _decode_dds_or_raw(blob, w, h, pixel_format):
    """v5 的 DDS 表里可能存 完整 DDS 文件，也可能存裸像素。两种都吃。"""
    if blob[:4] == b"DDS ":
        _w, _h, px = decode_dds(blob)
        return px
    need4, need2 = w * h * 4, w * h * 2
    if len(blob) >= need4:
        if pixel_format in (T_ARGB8888, 0):
            return _to_rgba8888(blob, w, h)
        return _to_rgba8888(blob, w, h)
    if len(blob) >= need2:
        if pixel_format == T_ARGB4444:
            return _to_rgba4444(blob, w, h)
        return _to_rgba1555(blob, w, h)
    raise NpkError("DDS 裸数据长度 %d 既不是 %dx%d 的 32 位也不是 16 位"
                   % (len(blob), w, h))


def decode_dds(blob):
    """解 128 字节头的 DDS（DXT1/3/5 或 未压缩 ARGB）-> (w,h,rgba)。"""
    if len(blob) < 128 or blob[:4] != b"DDS ":
        raise NpkError("不是 DDS")
    height, width = struct.unpack_from("<II", blob, 12)
    pf_off = 76 + 8  # 跳过 magic(4)+dwSize..reserved1(72)，再跳过 ddspf 的 size/flags
    fourcc = blob[pf_off:pf_off + 4]
    bit_count, rmask, gmask, bmask, amask = struct.unpack_from("<5I", blob, pf_off + 4)
    # 跳过 128 字节头（DX10 额外 20 字节）
    data_off = 128 + (20 if fourcc == b"DX10" else 0)
    payload = blob[data_off:]
    if fourcc == b"DXT1":
        return width, height, _dxt(1, payload, width, height)
    if fourcc == b"DXT3":
        return width, height, _dxt(3, payload, width, height)
    if fourcc == b"DXT5":
        return width, height, _dxt(5, payload, width, height)
    if bit_count in (32, 24, 16) and fourcc == b"\x00\x00\x00\x00":
        return width, height, _uncompressed_dds(payload, width, height,
                                                bit_count, rmask, gmask, bmask, amask)
    raise NpkError("不支持的 DDS 格式 fourCC=%r bits=%d" % (fourcc, bit_count))


def _uncompressed_dds(payload, w, h, bits, rm, gm, bm, am):
    bpp = bits // 8
    n = w * h
    if len(payload) < n * bpp:
        raise NpkError("未压缩 DDS 数据不足")
    out = bytearray(n * 4)

    def shift(mask):
        if not mask:
            return 0, 255
        s = 0
        while not (mask >> s) & 1:
            s += 1
        return s, mask >> s

    rs, rx = shift(rm)
    gs, gx = shift(gm)
    bs, bx = shift(bm)
    as_, ax = shift(am) if am else (0, 0)
    for i in range(n):
        v = int.from_bytes(payload[i * bpp:(i + 1) * bpp], "little")
        o = i * 4
        out[o] = ((v & rm) >> rs) * 255 // rx if rx else 0
        out[o + 1] = ((v & gm) >> gs) * 255 // gx if gx else 0
        out[o + 2] = ((v & bm) >> bs) * 255 // bx if bx else 0
        out[o + 3] = (((v & am) >> as_) * 255 // ax) if (am and ax) else 255
    return bytes(out)


def _rgb565(c):
    r = (c >> 11) & 0x1F
    g = (c >> 5) & 0x3F
    b = c & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def _dxt(mode, payload, w, h):
    """mode: 1=DXT1, 3=DXT3, 5=DXT5。返回 RGBA bytes。"""
    if _np is not None:
        return _dxt_np(mode, payload, w, h)
    return _dxt_py(mode, payload, w, h)


def _dxt_np(mode, payload, w, h):
    """vectorized DXT1/3/5 解码。"""
    bpb = 8 if mode == 1 else 16
    bw, bh = (w + 3) // 4, (h + 3) // 4
    need = bw * bh * bpb
    if len(payload) < need:
        raise NpkError("DXT 数据不足：要 %d 得 %d" % (need, len(payload)))
    src = _np.frombuffer(payload[:need], dtype=_np.uint8).reshape(bh, bw, bpb)

    cbytes = src[:, :, 0:8] if mode == 1 else src[:, :, 8:16]
    c0 = cbytes[:, :, 0].astype(_np.uint16) | (cbytes[:, :, 1].astype(_np.uint16) << 8)
    c1 = cbytes[:, :, 2].astype(_np.uint16) | (cbytes[:, :, 3].astype(_np.uint16) << 8)

    def exp5(v):
        return ((v << 3) | (v >> 2)).astype(_np.float32)

    def exp6(v):
        return ((v << 2) | (v >> 4)).astype(_np.float32)

    r0, g0, b0 = exp5((c0 >> 11) & 0x1F), exp6((c0 >> 5) & 0x3F), exp5(c0 & 0x1F)
    r1, g1, b1 = exp5((c1 >> 11) & 0x1F), exp6((c1 >> 5) & 0x3F), exp5(c1 & 0x1F)
    p0 = _np.stack([r0, g0, b0], axis=-1)
    p1 = _np.stack([r1, g1, b1], axis=-1)
    p2 = (2.0 * p0 + p1) / 3.0
    p3 = (p0 + 2.0 * p1) / 3.0
    pal = _np.stack([p0, p1, p2, p3], axis=2)          # (bh,bw,4,3)

    code = (cbytes[:, :, 4].astype(_np.uint32)
            | (cbytes[:, :, 5].astype(_np.uint32) << 8)
            | (cbytes[:, :, 6].astype(_np.uint32) << 16)
            | (cbytes[:, :, 7].astype(_np.uint32) << 24))
    idx = _np.stack([(code >> (2 * i)) & 3 for i in range(16)], axis=-1)   # (bh,bw,16)
    n = bh * bw
    col = _np.take_along_axis(pal.reshape(n, 4, 3),
                              idx.reshape(n, 16)[:, :, None], axis=1)   # (n,16,3)
    rgba = _np.zeros((n, 16, 4), dtype=_np.float32)
    rgba[:, :, :3] = col

    if mode == 1:
        rgba[:, :, 3] = 255.0
        if bool((c0 <= c1).any()):
            trans = ((c0 <= c1).reshape(n)[:, None]) & (idx.reshape(n, 16) == 3)
            rgba[:, :, 3] = _np.where(trans, 0.0, 255.0)
    elif mode == 3:
        a = src[:, :, 0:8].astype(_np.uint16)
        nib = _np.stack([(a[:, :, i // 2] >> (4 * (i % 2))) & 0xF
                         for i in range(16)], axis=-1).reshape(n, 16)
        rgba[:, :, 3] = nib.astype(_np.float32) * 17.0
    else:
        a = src[:, :, 0:8]
        a0 = a[:, :, 0].astype(_np.float32).reshape(n, 1)
        a1 = a[:, :, 1].astype(_np.float32).reshape(n, 1)
        acode = (a[:, :, 2].astype(_np.uint64)
                 | (a[:, :, 3].astype(_np.uint64) << 8)
                 | (a[:, :, 4].astype(_np.uint64) << 16)
                 | (a[:, :, 5].astype(_np.uint64) << 24)
                 | (a[:, :, 6].astype(_np.uint64) << 32)
                 | (a[:, :, 7].astype(_np.uint64) << 40)).reshape(n)
        aidx = _np.stack([(acode >> (3 * i)) & 7 for i in range(16)], axis=-1)  # (n,16)
        i8 = _np.arange(8, dtype=_np.float32)
        big = a0 > a1
        tab_big = (_np.clip(8.0 - i8, 0, None) * a0 + _np.clip(i8 - 1.0, 0, None) * a1) / 7.0
        tab_small = (_np.clip(6.0 - i8, 0, None) * a0 + _np.clip(i8 - 1.0, 0, None) * a1) / 5.0
        tab_small[:, 6] = 0.0
        tab_small[:, 7] = 255.0
        tab = _np.where(big, tab_big, tab_small)
        tab[:, 0] = a0[:, 0]
        tab[:, 1] = a1[:, 0]
        rgba[:, :, 3] = _np.take_along_axis(tab, aidx, axis=1)

    rgba = _np.clip(rgba + 0.5, 0, 255).astype(_np.uint8)
    tex = rgba.reshape(bh, bw, 4, 4, 4).transpose(0, 2, 1, 3, 4)
    tex = tex.reshape(bh * 4, bw * 4, 4)[:h, :w]
    return _np.ascontiguousarray(tex).tobytes()


def _dxt_py(mode, payload, w, h):
    """纯 Python 回退（慢，但保证没有 numpy 也能出图）。"""
    bpb = 8 if mode == 1 else 16
    bw, bh = (w + 3) // 4, (h + 3) // 4
    out = bytearray(w * h * 4)
    pos = 0
    for by in range(bh):
        for bx in range(bw):
            blk = payload[pos:pos + bpb]
            pos += bpb
            if len(blk) < bpb:
                raise NpkError("DXT 数据不足")
            if mode == 3:
                abits = [int.from_bytes(blk[0:8], "little")]
                a = [((abits[0] >> (4 * i)) & 0xF) * 17 for i in range(16)]
                c = blk[8:16]
            elif mode == 5:
                a0, a1 = blk[0], blk[1]
                if a0 > a1:
                    atab = [a0, a1] + [((7 - i) * a0 + i * a1) // 7 for i in range(1, 7)]
                else:
                    atab = [a0, a1] + [((5 - i) * a0 + i * a1) // 5 for i in range(1, 5)] + [0, 255]
                code = int.from_bytes(blk[2:8], "little")
                a = [atab[(code >> (3 * i)) & 7] for i in range(16)]
                c = blk[8:16]
            else:
                a = [255] * 16
                c = blk[0:8]
            c0 = c[0] | (c[1] << 8)
            c1 = c[2] | (c[3] << 8)
            r0, g0, b0 = _rgb565(c0)
            r1, g1, b1 = _rgb565(c1)
            if mode == 1:
                if c0 > c1:
                    pal = [(r0, g0, b0), (r1, g1, b1),
                           ((2 * r0 + r1) // 3, (2 * g0 + g1) // 3, (2 * b0 + b1) // 3),
                           ((r0 + 2 * r1) // 3, (g0 + 2 * g1) // 3, (b0 + 2 * b1) // 3)]
                    alpha3 = 255
                else:
                    pal = [(r0, g0, b0), (r1, g1, b1),
                           ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2), (0, 0, 0)]
                    alpha3 = 0
            else:
                pal = [(r0, g0, b0), (r1, g1, b1),
                       ((r0 + r1) // 2, (g0 + g1) // 2, (b0 + b1) // 2), (0, 0, 0)]
                alpha3 = 255
            code = c[4] | (c[5] << 8) | (c[6] << 16) | (c[7] << 24)
            for i in range(16):
                k = (code >> (2 * i)) & 3
                px, py = bx * 4 + (i % 4), by * 4 + (i // 4)
                if px >= w or py >= h:
                    continue
                r, g, b = pal[k]
                o = (py * w + px) * 4
                out[o] = r
                out[o + 1] = g
                out[o + 2] = b
                out[o + 3] = a[i] if mode != 1 else (alpha3 if k == 3 else 255)
    return bytes(out)


# --------------------------------------------------------------------------
# PNG
# --------------------------------------------------------------------------

def write_png(path, w, h, rgba):
    if len(rgba) < w * h * 4:
        raise NpkError("PNG 像素不足：要 %d 得 %d" % (w * h * 4, len(rgba)))
    stride = w * 4
    raw = bytearray((stride + 1) * h)
    for y in range(h):
        o = y * (stride + 1)
        raw[o] = 0  # filter none
        raw[o + 1:o + 1 + stride] = rgba[y * stride:(y + 1) * stride]
    comp = zlib.compress(bytes(raw), 6)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", ihdr))
        f.write(chunk(b"IDAT", comp))
        f.write(chunk(b"IEND", b""))


def read_png(path):
    """只读本工具写出的 RGBA8 非隔行 PNG。"""
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise NpkError("%s 不是 PNG" % path)
    pos = 8
    w = h = 0
    idat = bytearray()
    while pos + 8 <= len(data):
        ln = struct.unpack_from(">I", data, pos)[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or ctype != 6 or interlace:
                raise NpkError("只支持 RGBA8 非隔行 PNG")
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    raw = zlib.decompress(bytes(idat))
    stride = w * 4
    out = bytearray(stride * h)
    prev = bytearray(stride)
    o = 0
    for y in range(h):
        ft = raw[o]
        o += 1
        line = bytearray(raw[o:o + stride])
        o += stride
        if ft == 1:
            for i in range(4, stride):
                line[i] = (line[i] + line[i - 4]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - 4] if i >= 4 else 0
                b = prev[i]
                c = prev[i - 4] if i >= 4 else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        elif ft != 0:
            raise NpkError("PNG 过滤器 %d 不支持" % ft)
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, bytes(out)


# --------------------------------------------------------------------------
# 打包（可选）：PNG 目录 -> NPK
# --------------------------------------------------------------------------

def build_img(frames, version=2):
    """frames: [(w,h,x,y, rgba bytes)] -> IMG 字节串（ARGB8888 + zlib）。"""
    head = bytearray(IMG_MAGIC)
    head += struct.pack("<III", 0, 0, version)
    head += struct.pack("<I", len(frames))
    recs = bytearray()
    body = bytearray()
    for (w, h, x, y, rgba) in frames:
        payload = zlib.compress(rgba, 6)
        recs += struct.pack("<9i", T_ARGB8888, C_ZLIB, w, h, len(payload),
                            x, y, w, h)
        body += payload
    table_len = len(recs)
    out = bytearray(head)
    struct.pack_into("<I", out, 16, table_len)
    out += recs
    out += body
    return bytes(out)


def build_npk(items):
    """items: [(name, bytes)] -> NPK 字节串。"""
    import hashlib
    count = len(items)
    header = bytearray(NPK_MAGIC + struct.pack("<I", count))
    offset = 20 + count * NPK_ENTRY_SIZE + NPK_SUM_SIZE
    index = bytearray()
    body = bytearray()
    for name, blob in items:
        index += struct.pack("<ii", offset, len(blob))
        index += encode_name(name)
        body += blob
        offset += len(blob)
    head_bytes = bytes(header) + bytes(index)
    cut = len(head_bytes) // 17 * 17
    digest = hashlib.sha256(head_bytes[:cut]).digest()
    return head_bytes + digest + bytes(body)


# --------------------------------------------------------------------------
# 目录操作 / 统计
# --------------------------------------------------------------------------

def iter_npk(paths):
    """接受 NPK 文件、目录或目录列表，产出 .npk 路径。"""
    for p in paths:
        if os.path.isdir(p):
            for name in sorted(os.listdir(p)):
                if name.lower().endswith(".npk"):
                    yield os.path.join(p, name)
        elif os.path.isfile(p):
            yield p


def resolve_npk(arg, pack_dir):
    """把 '路径' 或 '文件名' 解析成真实 NPK 路径（文件名有前导空格，必须 listdir）。"""
    if os.path.isfile(arg):
        return arg
    cand = os.path.join(pack_dir, arg)
    if os.path.isfile(cand):
        return cand
    low = arg.lower()
    hits = [n for n in os.listdir(pack_dir)
            if n.lower() == low or (low in n.lower() and n.lower().endswith(".npk"))]
    if len(hits) == 1:
        return os.path.join(pack_dir, hits[0])
    if not hits:
        raise NpkError("在 %s 下找不到 %r" % (pack_dir, arg))
    raise NpkError("%r 匹配到多个：%s" % (arg, hits[:5]))


def safe_filename(name):
    out = []
    for ch in name:
        out.append(ch if (ch.isalnum() or ch in "._-") else "_")
    return "".join(out)[-120:]


# --------------------------------------------------------------------------
# 子命令
# --------------------------------------------------------------------------

def cmd_list(args):
    path = resolve_npk(args.npk, args.pack_dir)
    npk = Npk(path, verify=args.verify)
    print("# %s  条目 %d  大小 %d  校验 %s"
          % (os.path.basename(path), npk.count, npk.file_size,
             "OK" if npk.verify_ok else ("跳过" if npk.verify_ok is None else "FAIL")))
    show = npk.entries if not args.filter else [e for _, e in npk.find(args.filter)]
    for e in show[:args.limit or None]:
        print("%-90s %10d %10d" % (e.name, e.offset, e.size))
    if args.limit and len(show) > args.limit:
        print("... 共 %d 条，只显示 %d" % (len(show), args.limit))


def cmd_find(args):
    t0 = time.time()
    total = 0
    hit = 0
    for path in iter_npk(args.npk or [args.pack_dir]):
        try:
            npk = Npk(path)
        except NpkError as e:
            print("!! %s: %s" % (os.path.basename(path), e), file=sys.stderr)
            continue
        total += 1
        for i, e in npk.find(args.name):
            hit += 1
            print("%s\t%d\t%s\t%d\t%d" % (os.path.basename(path), i, e.name, e.offset, e.size))
            if args.limit and hit >= args.limit:
                break
        if args.limit and hit >= args.limit:
            break
    print("# 扫描 %d 个 NPK，命中 %d，用时 %.1fs"
          % (total, hit, time.time() - t0), file=sys.stderr)


def cmd_info(args):
    path = resolve_npk(args.npk, args.pack_dir)
    npk = Npk(path, verify=args.verify)
    img, name = npk.open_img(args.img)
    d = img.describe()
    print("img      : %s" % name)
    print("npk      : %s" % os.path.basename(path))
    print("version  : v%d" % d["version"])
    print("frames   : %d" % d["frame_count"])
    print("palettes : %s" % (["%d 色" % n for n in d["palettes"]] or "无"))
    print("dds table: %d" % d["dds_count"])
    for r in d["dds"]:
        print("   dds idx=%-3d fmt=0x%02X %dx%d full=%d raw=%d"
              % (r["index"], r["pixel_format"], r["width"], r["height"],
                 r["full_length"], r["length"]))
    if args.json:
        print(json.dumps(d, ensure_ascii=False, indent=2))
        return
    print("%-5s %-16s %3s %5s %5s %8s %6s %6s %6s %6s %s"
          % ("idx", "type", "cmp", "w", "h", "len", "x", "y", "fw", "fh", "note"))
    for f, res in zip(d["frames"], img.resolved):
        note = ""
        if img.frames[f["index"]].is_reference:
            note = "-> %d" % res
        elif img.frames[f["index"]].compressed == C_DDSREF:
            note = "dds#%d crop(%d,%d,%d,%d)" % (
                img.frames[f["index"]].dds_index, img.frames[f["index"]].left,
                img.frames[f["index"]].up, img.frames[f["index"]].right,
                img.frames[f["index"]].down)
        print("%-5d %-16s 0x%02X %5d %5d %8d %6d %6d %6d %6d %s"
              % (f["index"], f["type"], f["compressed"], f["width"], f["height"],
                 f["length"], f["x"], f["y"], f["frame_width"], f["frame_height"], note))


def cmd_dump(args):
    path = resolve_npk(args.npk, args.pack_dir)
    npk = Npk(path)
    img, name = npk.open_img(args.img)
    os.makedirs(args.out, exist_ok=True)
    if args.frames:
        want = parse_frame_spec(args.frames, img.frame_count)
    else:
        want = list(range(img.frame_count))
    base = safe_filename(os.path.splitext(os.path.basename(name))[0])
    wrote = 0
    for i in want:
        try:
            w, h, x, y, px = img.frame_image(i)
        except NpkError as e:
            print("!! 帧 %d: %s" % (i, e), file=sys.stderr)
            if args.strict:
                raise
            continue
        out = os.path.join(args.out, "%s_%03d.png" % (base, i))
        write_png(out, w, h, px)
        wrote += 1
        if args.verbose:
            print("%s  %dx%d  offset=(%d,%d)" % (out, w, h, x, y))
    print("# %s: 导出 %d/%d 帧 -> %s" % (name, wrote, len(want), args.out))


def parse_frame_spec(spec, count):
    out = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = part.split("-", 1)
            out.extend(range(int(a), int(b) + 1))
        else:
            out.append(int(part))
    bad = [i for i in out if i < 0 or i >= count]
    if bad:
        raise SystemExit("帧号越界：%s（共 %d 帧）" % (bad[:5], count))
    return out


def read_img_records(npk, i):
    """只读 IMG 的头 + 帧记录（不读像素），精确按需读取。

    语料里有 1GB 级的 img，整条 read() 会直接 ENOMEM，所以先摸头算长度。
    """
    head_len = 4096
    while True:
        head = npk.read_index(i, head_len)
        if not head.startswith(IMG_MAGIC):
            raise NpkError("不是 IMG")
        try:
            version, fc = struct.unpack_from("<Ii", head, 24)
            pos = 32
            if version == 4:
                n = struct.unpack_from("<i", head, pos)[0]
                pos += 4 + n * 4
            elif version == 5:
                dds, _il, cn = struct.unpack_from("<iii", head, pos)
                pos += 12 + cn * 4 + dds * 28
            elif version == 6:
                pc = struct.unpack_from("<i", head, pos)[0]
                pos += 4
                for _ in range(pc):
                    n = struct.unpack_from("<i", head, pos)[0]
                    pos += 4 + n * 4
        except struct.error:
            if head_len >= len(head):
                raise NpkError("IMG 头不完整（文件截断？）")
            head_len *= 8
            continue
        need = pos + fc * 64 + 64
        data = npk.read_index(i, need)
        return Img(data, parse_bodies=False)


def cmd_census(args):
    """全量普查：只读头与帧记录，不碰像素。"""
    t0 = time.time()
    ver_hist = {}
    type_hist = {}
    comp_hist = {}
    ref_count = 0
    bad = []
    nbad = [0]
    imgs = 0
    npks = 0
    targets = []
    for a in (args.npk or [args.pack_dir]):
        if os.path.isdir(a):
            targets.extend(iter_npk([a]))
        else:
            try:
                targets.append(resolve_npk(a, args.pack_dir))
            except NpkError:
                bad.append((a, "找不到该 NPK"))
    for path in targets:
        try:
            npk = Npk(path)
        except NpkError as e:
            bad.append((os.path.basename(path), str(e)))
            continue
        npks += 1
        for i in range(len(npk.entries)):
            e = npk.entries[i]
            if not e.name.lower().endswith(".img"):
                continue
            try:
                if args.no_bodies:
                    img = read_img_records(npk, i)
                else:
                    data = npk.read_index(i)
                    if not data.startswith(IMG_MAGIC):
                        continue
                    img = Img(data)
            except (NpkError, struct.error, IndexError, MemoryError, OSError) as ex:
                nbad[0] += 1
                if len(bad) < 50:
                    bad.append((e.name, "%s: %s" % (type(ex).__name__, ex)))
                continue
            imgs += 1
            ver_hist[img.version] = ver_hist.get(img.version, 0) + 1
            for f in img.frames:
                key = (img.version, "0x%02X" % f.type)
                type_hist[key] = type_hist.get(key, 0) + 1
                comp_hist[(img.version, f.compressed)] = \
                    comp_hist.get((img.version, f.compressed), 0) + 1
                if f.is_reference:
                    ref_count += 1
    print("NPK %d，IMG %d，失败 %d，用时 %.1fs" % (npks, imgs, nbad[0], time.time() - t0))
    print("版本分布 :", dict(sorted(ver_hist.items())))
    print("帧类型   :", dict(sorted(type_hist.items())))
    print("压缩标志 :", dict(sorted(comp_hist.items())))
    print("指向帧数 :", ref_count)
    for name, why in bad[:20]:
        print("  !! %s: %s" % (name, why))


def cmd_slice(args):
    """按切片清单（export/_meta/slice_manifest.json）批量抽图。

    这是给图集管线（t11）用的入口：只抽清单里点名的 .img，绝不整包拷。
    清单来自 `tools/slice_manifest.py`；结构见 analysis/12-SLICE-MANIFEST.md。
    """
    import json
    man = json.load(open(args.manifest, encoding="utf-8"))
    items = man.get("images") or []
    if args.limit:
        items = items[:args.limit]
    os.makedirs(args.out, exist_ok=True)
    pool = {}
    for f in os.listdir(args.pack_dir):
        if f.lower().endswith(".npk"):
            pool[f] = os.path.join(args.pack_dir, f)
    t0 = time.time()
    rows = []
    ok = fail = 0
    frames = 0
    for it in items:
        path = it["path"]
        cands = [n for n in it.get("npk", []) if n in pool] or list(pool)
        done = False
        err = None
        for n in cands:
            try:
                npk = Npk(pool[n])
                npk.index_of(path)
            except (NpkError, OSError) as ex:
                err = "%s: %s" % (n, ex)
                continue
            try:
                img, real = npk.open_img(path)
            except NpkError as ex:
                err = "%s: %s" % (n, ex)
                continue
            base = safe_filename(path)
            stem = base[:-4] if base.lower().endswith(".img") else base
            made = 0
            bad = 0
            for j in range(img.frame_count):
                try:
                    w, h, x, y, px = img.frame_image(j)
                except NpkError as ex:
                    bad += 1
                    continue
                if args.frames and j not in args.frames:
                    continue
                write_png(os.path.join(args.out, "%s_%03d.png" % (stem, j)), w, h, px)
                made += 1
            frames += made
            rows.append({"path": path, "entry": real, "npk": n,
                         "version": img.version, "frames": img.frame_count,
                         "written": made, "failed_frames": bad})
            ok += 1
            done = True
            break
        if not done:
            rows.append({"path": path, "error": err or "未找到"})
            fail += 1
            print("!! %s：%s" % (path, err or "未找到"), file=sys.stderr)
    report = os.path.join(args.out, "slice-report.json")
    with open(report, "w", encoding="utf-8") as f:
        json.dump({"manifest": args.manifest, "ok": ok, "fail": fail,
                   "frames_written": frames, "items": rows}, f,
                  ensure_ascii=False, indent=1)
    print("# 清单 %d 项：成功 %d、失败 %d、写出 %d 帧 -> %s（%.1fs）"
          % (len(items), ok, fail, frames, args.out, time.time() - t0))
    return 0 if fail == 0 else 1


def cmd_bench(args):
    rng = random.Random(args.seed)
    paths = list(iter_npk([args.pack_dir]))
    rng.shuffle(paths)
    t0 = time.time()
    ok = fail = frames = 0
    reasons = {}
    per_img = []
    for path in paths:
        if ok + fail >= args.n:
            break
        try:
            npk = Npk(path)
        except NpkError as e:
            fail += 1
            reasons[str(e)[:60]] = reasons.get(str(e)[:60], 0) + 1
            continue
        idxs = [i for i, e in enumerate(npk.entries) if e.name.lower().endswith(".img")]
        if not idxs:
            continue
        rng.shuffle(idxs)
        for i in idxs[:args.per_npk]:
            if ok + fail >= args.n:
                break
            t1 = time.time()
            try:
                if args.mode == "meta":
                    img = Img(npk.read_index(i), parse_bodies=False)
                    n = img.frame_count
                elif args.mode == "first":
                    img = Img(npk.read_index(i))
                    n = 1
                    if img.frame_count:
                        img.frame_image(0)
                else:
                    img = Img(npk.read_index(i))
                    n = 0
                    for j in range(img.frame_count):
                        img.frame_image(j)
                        n += 1
                frames += n
                ok += 1
                per_img.append(time.time() - t1)
            except (NpkError, IndexError, ValueError, struct.error) as e:
                fail += 1
                key = str(e)[:60]
                reasons[key] = reasons.get(key, 0) + 1
    dt = time.time() - t0
    print("模式 %s" % args.mode)
    print("样本 %d 个 img：成功 %d，失败 %d，成功率 %.1f%%"
          % (ok + fail, ok, fail, 100.0 * ok / max(1, ok + fail)))
    print("帧总数 %d，总耗时 %.2fs，吞吐 %.0f img/s（%.0f 帧/s）"
          % (frames, dt, (ok + fail) / max(dt, 1e-9), frames / max(dt, 1e-9)))
    if per_img:
        per_img.sort()
        print("单 img 中位 %.1fms  p95 %.1fms" %
              (per_img[len(per_img) // 2] * 1000, per_img[int(len(per_img) * 0.95)] * 1000))
    for k, v in sorted(reasons.items(), key=lambda kv: -kv[1])[:10]:
        print("  失败原因 x%d: %s" % (v, k))


def _make_img(version, frames, palette=None, pal_count=0):
    """造一个最小 IMG（仅供 selftest 用）。frames: [(type, w, h, x, y, payload, extra)]"""
    out = bytearray(IMG_MAGIC)
    out += struct.pack("<III", 0, 0, version)
    out += struct.pack("<I", len(frames))
    if version == 4:
        out += struct.pack("<i", len(palette) // 4 if palette else 0)
        out += palette or b""
    elif version == 6:
        out += struct.pack("<i", pal_count)
        for k in range(pal_count):
            out += struct.pack("<i", len(palette) // 4)
            out += palette
    recs = bytearray()
    bodies = bytearray()
    for (ftype, w, h, x, y, payload, extra) in frames:
        if ftype == T_REFERENCE:
            recs += struct.pack("<2i", T_REFERENCE, payload)
            continue
        recs += struct.pack("<9i", ftype, C_ZLIB, w, h, len(payload), x, y, w, h)
        bodies += payload
    struct.pack_into("<I", out, 16, len(recs))
    out += recs + bodies
    return bytes(out)


# 生成文档用样例的清单：(输出名, NPK 名片段, img 路径, 帧列表, 说明)
SAMPLE_PLAN = [
    ("v2_argb8888_swordman_avatar", "2025年耕耘犬夜叉", "sprite/character/swordman/equipment/avatar/skin/sm_body16800.img",
     [0, 1, 2, 3], "v2 / ARGB8888 / zlib —— 剑士装扮皮肤，四帧站立"),
    ("v2_argb1555_skilleffect", "sprite_character_fighter_effect_chainawakeni",
     "sprite/character/fighter/effect/chainawakeningskill/finish01.img",
     [0, 3, 6], "v2 / ARGB1555(0x0E) —— 格斗家觉醒技特效"),
    ("v2_argb1555_skillshop", "sprite_interface2_ui_skillshop", "sprite/interface2/ui/skillshop/tp_skill_able.img",
     [0, 4, 8], "v2 / ARGB1555(0x0E) —— 技能商店可购买标记"),
    ("v2_monster_with_reference", "sprite_monster_skillhuntress", "sprite/monster/skillhuntress/skillhuntress.img",
     [0, 2, 4], "v2 / 0x0E + 0x11 混排 —— 怪物图（含指向帧）"),
    ("v2_argb4444_customui", "sprite_character_common_customui", "sprite/character/common/customui/block.img",
     [0, 1, 2], "v2 / ARGB4444(0x0F) —— 自定义 UI 格挡标记"),
    ("v2_reference_chain", "sprite_character_priest_equipment_weapon_cro",
     "sprite/character/priest/equipment/weapon/cross/pr_cross4100d.img",
     [0, 169], "v2 / 指向帧(reference) —— 0 是实体图，169 是 linkTo 0 的指向帧（解出同一张图）"),
    ("v5_argb8888_digit", "sprite_common_digit_tp", "sprite/common/digit/red_systemfont.img",
     [0, 10], "v5 / 共享 DDS 裁剪帧 —— 红色数字字体"),
    ("v5_ddsref_raid", "sprite_interface2_raid", "sprite/interface2/raid/raid_channel_cn.img",
     [0, 1, 2, 3], "v5 / compressed=0x07 的 64 字节记录 + DDS 裁剪 —— 团队频道横幅"),
    ("v5_dxt1_monsterface", "1A冥灵之塔补丁", "sprite/monster/ch_monsterface.img",
     [0, 1, 2, 3, 4, 5], "v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集"),
]


def _compose_demo(pool, outdir, made):
    """坐标系验证：.ani 的 [IMAGE POS] 与 .img 帧的 (x,y) 直接相加。

    结论见 docs/NPK-FORMAT.md §5.1；这里把 attack1.ani 的前 8 帧叠到一张画布上，
    人若能站住（脚在原点附近）就说明叠加公式对。
    """
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import ani_parser as A  # 只读工具，不算本模块依赖

    ani_path = os.path.join(ROOT, "export", "text", "character", "swordman",
                            "animation", "attack1.ani.bin")
    if not os.path.exists(ani_path):
        raise RuntimeError("找不到 %s" % ani_path)
    cand = [p for p in pool if "swordman_equipment_avatar_skin" in os.path.basename(p)]
    if not cand:
        raise RuntimeError("找不到 swordman avatar skin 包")
    npk = Npk(cand[0])
    want = "sprite/character/swordman/equipment/avatar/skin/sm_body0000.img"
    img, _ = npk.open_img(want)
    ani = A.parse_ani(open(ani_path, "rb").read())

    W = H = 400
    ox, oy = 200, 320          # 把角色原点摆到画布上的位置
    canvas = bytearray(W * H * 4)
    n = 0
    for fr in ani["frames"]:
        if not fr.get("has_image"):
            continue
        if n >= 8:
            break
        w, h, ix, iy, px = img.frame_image(fr["image_frame"])
        dx, dy = ox + fr["x"] + ix, oy + fr["y"] + iy   # <= 核心公式
        for yy in range(h):
            ty = dy + yy
            if ty < 0 or ty >= H:
                continue
            row = (yy * w) * 4
            for xx in range(w):
                tx = dx + xx
                if tx < 0 or tx >= W:
                    continue
                s = row + xx * 4
                if px[s + 3] > 128:
                    d = (ty * W + tx) * 4
                    canvas[d:d + 4] = px[s:s + 4]
        n += 1
    name = "compose_ani_img_offset.png"
    write_png(os.path.join(outdir, name), W, H, bytes(canvas))
    made.append((name, W, H, want, 0,
                 "attack1.ani 前 %d 帧叠加：验证 draw=(ani.x+img.x, ani.y+img.y)，脚落在原点" % n))
    return n


def cmd_samples(args):
    """把文档要引用的样例 PNG 一次性导到 analysis/npk/。"""
    outdir = args.out
    os.makedirs(outdir, exist_ok=True)
    made = []
    pool = [os.path.join(args.pack_dir, f) for f in sorted(os.listdir(args.pack_dir))
            if f.lower().endswith(".npk")]
    for base, npk_hint, img_path, frames, note in SAMPLE_PLAN:
        cand = [p for p in pool if npk_hint in os.path.basename(p)]
        if not cand:
            print("!! 找不到 NPK：%s（跳过 %s）" % (npk_hint, base), file=sys.stderr)
            continue
        done = False
        for npk_path in cand:
            try:
                npk = Npk(npk_path)
                if img_path is None:
                    names = [e.name for e in npk.entries
                             if e.name.lower().endswith(".img") and "skillicon" in e.name.lower()]
                    if not names:
                        continue
                    img_path2 = names[0]
                else:
                    img_path2 = img_path
                img, real = npk.open_img(img_path2)
            except NpkError:
                continue
            want = [i for i in frames if i < img.frame_count]
            if not want:
                continue
            if img_path is not None:
                img_path2 = real
            for i in want:
                try:
                    w, h, _x, _y, px = img.frame_image(i)
                except NpkError as e:
                    print("!! %s 帧 %d: %s" % (base, i, e), file=sys.stderr)
                    continue
                fn = "%s_%03d.png" % (base, i)
                write_png(os.path.join(outdir, fn), w, h, px)
                made.append((fn, w, h, img_path2, i, note))
            done = True
            break
        if not done:
            print("!! 未产出 %s" % base, file=sys.stderr)

    # ---- 合成样例：语料里没有 v4/v6 与 DXT3/DXT5，用造出来的数据验证解码路径 ----
    pal = bytes([255, 0, 0, 255,   0, 255, 0, 255,   0, 0, 255, 255,   0, 0, 0, 0])
    idx = bytearray()
    for y in range(16):
        for x in range(16):
            idx.append((0 if (x // 4 + y // 4) % 4 == 0 else
                        1 if (x // 4 + y // 4) % 4 == 1 else
                        2 if (x // 4 + y // 4) % 4 == 2 else 3))
    body = zlib.compress(bytes(idx), 6)
    v4 = _make_img(4, [(T_INDEXED, 16, 16, 0, 0, body, None)], palette=pal)
    v6 = _make_img(6, [(T_INDEXED, 16, 16, 0, 0, body, None)], palette=pal, pal_count=3)
    for tag, blob, note in (("v4_palette_indexed", v4, "v4 / 调色板索引(0x0E+palette) —— 合成样例"),
                            ("v6_multi_palette", v6, "v6 / 多调色板(取 0 号) —— 合成样例")):
        im = Img(blob)
        w, h, _x, _y, px = im.frame_image(0)
        fn = tag + ".png"
        write_png(os.path.join(outdir, fn), w, h, px)
        made.append((fn, w, h, "(合成 IMG)", 0, note))

    # DXT 合成：4x4 红块（两种 code 顺序）+ 透名块；DXT3/DXT5 的 8 级 alpha 阶梯
    red = 0xF800
    blk = struct.pack("<HHI", red, red, 0)
    dxt1 = _dxt(1, blk, 4, 4)
    write_png(os.path.join(outdir, "dxt1_red_block.png"), 4, 4, dxt1)
    made.append(("dxt1_red_block.png", 4, 4, "(合成 DXT 块)", 0, "DXT1 纯红块"))
    # DXT3：alpha 从 0 到 F 递增
    nib = bytearray()
    for i in range(16):
        v = i
        if i % 2 == 0:
            nib.append(v & 0xF)
        else:
            nib[-1] |= (v & 0xF) << 4
    dxt3 = _dxt(3, bytes(nib) + blk, 4, 4)
    write_png(os.path.join(outdir, "dxt3_alpha_steps.png"), 4, 4, dxt3)
    made.append(("dxt3_alpha_steps.png", 4, 4, "(合成 DXT 块)", 0, "DXT3 alpha 阶梯"))
    # DXT5：a0=255 > a1=0，8 级插值
    acode = 0
    for i in range(16):
        acode |= (i & 7) << (3 * i)
    dxt5 = _dxt(5, bytes([255, 0]) + acode.to_bytes(6, "little") + blk, 4, 4)
    write_png(os.path.join(outdir, "dxt5_alpha_steps.png"), 4, 4, dxt5)
    made.append(("dxt5_alpha_steps.png", 4, 4, "(合成 DXT 块)", 0, "DXT5 alpha 8 级插值"))

    # ---- 坐标系验证图：把 .ani 的前若干帧按 (ani.x+img.x, ani.y+img.y) 叠起来 ----
    try:
        _compose_demo(pool, outdir, made)
    except Exception as ex:  # ani_parser 缺失或数据不在，跳过即可
        print("!! 坐标系验证图跳过：%s" % ex, file=sys.stderr)

    man = os.path.join(outdir, "MANIFEST.md")
    with open(man, "w", encoding="utf-8") as f:
        f.write("# analysis/npk 样例清单\n\n")
        f.write("由 `python3 tools/npk_parser.py samples --out analysis/npk` 生成。\n\n")
        f.write("| 文件 | 尺寸 | IMG | 帧 | 说明 |\n| --- | --- | --- | --- | --- |\n")
        for fn, w, h, ip, i, note in made:
            f.write("| `%s` | %dx%d | `%s` | %d | %s |\n" % (fn, w, h, ip, i, note))
    print("生成 %d 个样例 + MANIFEST.md -> %s" % (len(made), outdir))
    return 0


def cmd_selftest(args):
    """自检：reference 环检测 + v4/v6 调色板解码往返。"""
    ok = True

    # --- 1) 指向帧有向环必须报错，不能挂死 -------------------------------
    cyc = _make_img(2, [
        (T_REFERENCE, 0, 0, 0, 0, 0, None),      # 0 -> 1
        (T_REFERENCE, 0, 0, 0, 0, 1, None),      # 1 -> 0
        (T_REFERENCE, 0, 0, 0, 0, 2, None),      # 2 -> 2（自指）
    ])
    try:
        Img(cyc)
        print("[FAIL] 指向帧有向环没有报错")
        ok = False
    except NpkError as e:
        print("[ OK ] 环检测报错：%s" % e)

    # --- 2) 正常指向帧链 0->1->2(实体) 应解析到 2 ------------------------
    payload = zlib.compress(bytes([10, 20, 30, 255]), 6)
    good = _make_img(2, [
        (T_REFERENCE, 0, 0, 0, 0, 1, None),
        (T_REFERENCE, 0, 0, 0, 0, 2, None),
        (T_ARGB8888, 1, 1, 0, 0, payload, None),
    ])
    im = Img(good)
    if im.resolved == [2, 2, 2]:
        print("[ OK ] 指向帧链解析：%s" % (im.resolved,))
    else:
        print("[FAIL] 指向帧链解析得到 %s" % (im.resolved,))
        ok = False

    # --- 3) v4 调色板索引往返 -------------------------------------------
    pal = bytes([255, 0, 0, 255,  0, 255, 0, 128])   # 红不透明、绿半透明
    idx = zlib.compress(bytes([0, 1]), 6)
    v4 = _make_img(4, [(T_INDEXED, 2, 1, 0, 0, idx, None)], palette=pal)
    w, h, _, _, px = Img(v4).frame_image(0)
    expect = bytes([255, 0, 0, 255, 0, 255, 0, 128])
    if (w, h) == (2, 1) and px == expect:
        print("[ OK ] v4 调色板索引解码")
    else:
        print("[FAIL] v4 解码 %r != %r" % (px, expect))
        ok = False

    # --- 4) v6 多调色板 --------------------------------------------------
    v6 = _make_img(6, [(T_INDEXED, 2, 1, 0, 0, idx, None)], palette=pal, pal_count=2)
    w, h, _, _, px = Img(v6).frame_image(0)
    if px == expect:
        print("[ OK ] v6 多调色板解码（取 0 号调色板）")
    else:
        print("[FAIL] v6 解码 %r" % (px,))
        ok = False

    # --- 5) ARGB1555 / ARGB4444 ------------------------------------------
    p1555 = zlib.compress(bytes([0x00, 0xFC]), 6)   # r=31,g=0,b=0,a=1 -> 纯红
    w, h, _, _, px = Img(_make_img(2, [(T_ARGB1555, 1, 1, 0, 0, p1555, None)])).frame_image(0)
    if px == bytes([255, 0, 0, 255]):
        print("[ OK ] ARGB1555 解码")
    else:
        print("[FAIL] ARGB1555 -> %r" % (px,))
        ok = False
    p4444 = zlib.compress(bytes([0x00, 0xFF]), 6)   # a=f,r=f,g=0,b=0
    w, h, _, _, px = Img(_make_img(2, [(T_ARGB4444, 1, 1, 0, 0, p4444, None)])).frame_image(0)
    if px == bytes([255, 0, 0, 255]):
        print("[ OK ] ARGB4444 解码")
    else:
        print("[FAIL] ARGB4444 -> %r" % (px,))
        ok = False

    # --- 6) DXT1 / DXT3 / DXT5 基本色 ------------------------------------
    def dxt1_block(c0, c1, idxbits):
        return struct.pack("<HHI", c0, c1, idxbits)

    red = 0xF800      # r=31 -> 纯红
    blk = dxt1_block(red, red, 0x00000000)
    w, h, _, _, px = Img(_make_img(5, [(T_FXT1, 4, 4, 0, 0, b"", None)])).frame_image(0) if False else (0, 0, 0, 0, b"")
    # 直接测解码器
    rgba = _dxt(1, blk, 4, 4)
    if rgba[:4] == bytes([255, 0, 0, 255]):
        print("[ OK ] DXT1 解码（纯红块）")
    else:
        print("[FAIL] DXT1 -> %r" % (rgba[:4],))
        ok = False
    a_blk = struct.pack("<Q", 0xFFFFFFFFFFFFFFFF) + dxt1_block(red, red, 0)
    rgba = _dxt(3, a_blk, 4, 4)
    if rgba[:4] == bytes([255, 0, 0, 255]) and rgba[3] == 255:
        print("[ OK ] DXT3 解码（不透明块）")
    else:
        print("[FAIL] DXT3 -> %r" % (rgba[:4],))
        ok = False
    a5 = bytes([255, 0]) + b"\x00" * 6 + dxt1_block(red, red, 0)
    rgba = _dxt(5, a5, 4, 4)
    if rgba[:4] == bytes([255, 0, 0, 255]):
        print("[ OK ] DXT5 解码（alpha=255）")
    else:
        print("[FAIL] DXT5 -> %r" % (rgba[:4],))
        ok = False

    # --- 7) NPK 打包/读回 ------------------------------------------------
    npk_bytes = build_npk([("sprite/t/x.img", _make_img(2, [(T_ARGB8888, 1, 1, 0, 0, payload, None)]))])
    tmp = os.path.join("/tmp", "npk_selftest_%d.npk" % os.getpid())
    with open(tmp, "wb") as f:
        f.write(npk_bytes)
    n2 = Npk(tmp, verify=True)
    im2, _ = n2.open_img("sprite/t/x.img")
    if n2.verify_ok and im2.frame_count == 1:
        print("[ OK ] NPK 打包 -> 读回（含 SHA-256 校验）")
    else:
        print("[FAIL] NPK 往返 verify=%r frames=%d" % (n2.verify_ok, im2.frame_count))
        ok = False
    os.unlink(tmp)

    print("\n自检结果：%s" % ("全部通过" if ok else "有失败项"))
    return 0 if ok else 1


def cmd_pack(args):
    """把一个目录下的 <name>.img/<NNN>.png 打成 NPK。"""
    items = []
    src = os.path.abspath(args.src)
    for root, dirs, files in os.walk(src):
        dirs.sort()
        if not root.lower().endswith(".img"):
            continue
        rel = os.path.relpath(root, src).replace(os.sep, "/")
        frames = []
        for fn in sorted(files):
            if not fn.lower().endswith(".png"):
                continue
            w, h, px = read_png(os.path.join(root, fn))
            frames.append((w, h, 0, 0, px))
        if not frames:
            continue
        items.append((rel, build_img(frames)))
    if not items:
        raise SystemExit("没找到可打包的 <name>.img/ 目录")
    blob = build_npk(items)
    with open(args.out, "wb") as f:
        f.write(blob)
    print("# 写入 %s：%d 个 img，%d 字节" % (args.out, len(items), len(blob)))


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        description="DNF NPK/IMG 解析与 PNG 导出",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__)
    ap.add_argument("--pack-dir", default=DEFAULT_PACK_DIR,
                    help="ImagePacks2 目录（默认 %(default)s）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="列出一个 NPK 的条目")
    p.add_argument("npk")
    p.add_argument("--filter", default="")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--verify", action="store_true", help="校验 SHA-256 尾码")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("find", help="在目录里模糊找 img")
    p.add_argument("name")
    p.add_argument("--npk", nargs="*", default=None, help="限定 NPK 文件或目录")
    p.add_argument("--limit", type=int, default=0)
    p.set_defaults(func=cmd_find)

    p = sub.add_parser("info", help="看一个 img 的头与帧表")
    p.add_argument("npk")
    p.add_argument("img")
    p.add_argument("--json", action="store_true")
    p.add_argument("--verify", action="store_true")
    p.set_defaults(func=cmd_info)

    p = sub.add_parser("dump", help="导出一个 img 的帧为 PNG")
    p.add_argument("npk")
    p.add_argument("img")
    p.add_argument("--out", required=True)
    p.add_argument("--frames", default="", help="如 0,2-5；默认全部")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("--strict", action="store_true", help="任何一帧失败就抛异常")
    p.set_defaults(func=cmd_dump)

    p = sub.add_parser("census", help="统计版本/帧类型分布")
    p.add_argument("npk", nargs="*", default=None)
    p.add_argument("--no-bodies", action="store_true",
                   help="只解头+帧记录（快，用于全量普查）")
    p.set_defaults(func=cmd_census)

    p = sub.add_parser("bench", help="吞吐压测")
    p.add_argument("--n", type=int, default=200)
    p.add_argument("--per-npk", type=int, default=3)
    p.add_argument("--seed", type=int, default=20261026)
    p.add_argument("--mode", choices=["all", "first", "meta"], default="all",
                   help="all=解全部帧；first=每 img 只解首帧；meta=只解头+帧记录")
    p.set_defaults(func=cmd_bench)

    p = sub.add_parser("slice", help="按切片清单批量抽图（给图集管线用）")
    p.add_argument("--manifest",
                   default=os.path.join(ROOT, "export", "_meta", "slice_manifest.json"))
    p.add_argument("--out", default=os.path.join(ROOT, "export", "atlas", "slice"))
    p.add_argument("--limit", type=int, default=0, help="只处理前 N 项（调试用）")
    p.add_argument("--frames", type=int, nargs="*", default=None,
                   help="只导出这些帧号")
    p.set_defaults(func=cmd_slice)

    p = sub.add_parser("samples", help="导出文档用样例 PNG 到 analysis/npk/")
    p.add_argument("--out", default=os.path.join(ROOT, "analysis", "npk"))
    p.set_defaults(func=cmd_samples)

    p = sub.add_parser("selftest", help="自检：环检测/调色板/DXT/NPK 往返")
    p.set_defaults(func=cmd_selftest)

    p = sub.add_parser("pack", help="PNG 目录 -> NPK")
    p.add_argument("src")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_pack)

    args = ap.parse_args(argv)
    try:
        rc = args.func(args)
        if rc:
            return rc
    except NpkError as e:
        print("错误：%s" % e, file=sys.stderr)
        return 2
    except BrokenPipeError:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
