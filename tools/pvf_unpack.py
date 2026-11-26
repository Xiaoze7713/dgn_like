#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pvf_unpack.py — DNF/DFO `Script.pvf` 纯 Python 解包器（零依赖，可选 numpy 加速）

=====================================================================
一、容器层（Script.pvf）
=====================================================================
文件 = [56 字节头][目录树 dirTree][文件数据区 ...]

  struct PvfHeader {            // 56 = 0x38 字节
      int32  sizeGUID;          // 恒 0x24
      char   GUID[0x24];        // 36 字节 ASCII，如 "fa08bf71-4395-6a4b-a3e3-2617c9fee116"
      int32  fileVersion;       // 形如 66282 / 53579（作者版号，不是格式版本）
      int32  dirTreeLength;     // 目录树字节数（4 字节对齐）
      int32  dirTreeChecksum;   // CRC32，同时用作目录树的解密密钥
      int32  numFiles;          // 条目总数
  };

  目录树解密：对每 4 字节
      plain = ror32(cipher ^ 0x81A79011 ^ dirTreeChecksum, 6)
  （ror32(x,6) = ((x >> 6) | (x << 26)) & 0xFFFFFFFF）

  目录树 = numFiles 条紧邻记录，每条：
      uint32 fileNumber;
      int32  pathLength;
      char   path[pathLength];   // 路径，编码 = 客户端区域（CN 为 GBK/CP936）
      int32  fileLength;         // 明文长度
      uint32 fileCrc32;          // CRC32，同时用作该文件的解密密钥
      int32  relativeOffset;     // 相对数据区的偏移

  绝对偏移 = 56 + dirTreeLength + relativeOffset
  数据块长度 = (fileLength + 3) & ~3   (4 字节对齐)，解密方式同上（密钥 = fileCrc32），
  解密后按 fileLength 截断。

  ★ 自校验：zlib.crc32(plaintext) == fileCrc32（本工具 verify 子命令用这个判定整条链路对不对）

=====================================================================
二、文件类型
=====================================================================
  *.ani              -> 二进制动画（帧/资源/攻击盒/伤害盒），见 PvfAnimation 格式
  *.str              -> 纯文本（多语言字符串表）
  其它（.act/.atk/.chr/.equ/.stk/.mob/... .lst/stringtable.bin）
                     -> PvfDocument 二进制节点树（见下）

=====================================================================
三、PvfDocument 二进制格式
=====================================================================
  int16  header（跳过）
  之后是 5 字节记录流：[uint8 type][int32 index]
  type 枚举：
      2 Int  3 IntEx  4 Float  5 Section  6 Command  7 String
      8 CommandSeparator  9 StringLinkIndex  10 StringLink
  解释：
      Int/IntEx    -> 追加整数属性 index
      Float        -> 把 index 的 32 位按 IEEE754 重解释为 float
      Section      -> name = stringBinMap[index]
                      不以 "[/" 开头 = 开标签：建子节点；若上一个节点没有结束标签则先弹栈
                      以   "[/" 开头 = 闭标签：弹栈到同名节点
                      是否需要结束标签由「全文件是否出现过对应的 [/xxx]」决定
      String/Command/CommandSeparator -> 追加字符串属性 stringBinMap[index]
      StringLink   -> 追加 stringStringMap[stringBinMap[index]]

  stringtable.bin： int32 count，之后第 i 项 = (int32 startPos @ i*4+4, int32 endPos @ i*4+8)，
                    字符串位于 buffer + startPos + 4，长度 endPos - startPos
  n_string.lst：    uint16 magic 必须 == 53424；从 offset 2 起每 10 字节一条，
                    int32 @ +6 是 stringtable 下标 -> 该下标的字符串是一个 .str 文件路径；
                    那个 .str 每行形如 `name_xxx>格斗家`，按 '>' 切成 stringStringMap[key]=val

=====================================================================
四、.ani 二进制格式（PvfAnimation）
=====================================================================
  uint16 frameCount
  uint16 resourceCount
  resourceCount × { int32 len; char path[len] }        # 资源(图片)路径表，转小写
  uint16 paramCount
  paramCount × { uint16 type; ... }                    # 0 LOOP -> int8, 1 SHADOW -> int8
  frameCount × {
      uint16 boxCount
      boxCount × { uint16 type(14=伤害盒 15=攻击盒); int32 x6 }
      uint16 imgId; uint16 imgParam;
      int32 x; int32 y;
      uint16 propCount
      propCount × { uint16 type; <payload according to type> }
  }
  每帧属性 type：
      0 LOOP int8 | 1 SHADOW int8 | 3 Ani_COORD uint16 | 7 IMAGE_RATE float×2
      8 IMAGE_ROTATE int32 | 9 RGBA uint32 | 10 INTERPOLATION int8
      11 GRAPHIC_EFFECT uint16 (+MONOCHROME rgb3 / SPACEDISTORT u16×2)
      12 DELAY int32 | 13 DAMAGE_TYPE uint16 | 16 PLAY_SOUND {int32 len; char[len]}
      23 SET_FLAG int32 | 24 FLIP_TYPE uint16 | 25 LOOP_START (无载荷)
      26 LOOP_END int32 | 27 CLIP int16×4
      2,4,5,6,14,15,17,18,19,20,21,22 -> 无载荷（占位/未使用）

=====================================================================

用法：
  python3 tools/pvf_unpack.py info   <Script.pvf>
  python3 tools/pvf_unpack.py verify <Script.pvf> [--limit N]
  python3 tools/pvf_unpack.py list   <Script.pvf> [--grep PAT] [--limit N]
  python3 tools/pvf_unpack.py cat    <Script.pvf> <内部路径>
  python3 tools/pvf_unpack.py raw    <Script.pvf> <内部路径> --out FILE
  python3 tools/pvf_unpack.py extract <Script.pvf> --out DIR [--grep PAT] [--max N]
"""

from __future__ import annotations

import argparse
import json
import mmap
import os
import struct
import sys
import zlib
from pathlib import Path

try:
    import numpy as np
except Exception:  # pragma: no cover
    np = None

PASSWORD_PVF = 0x81A79011
HEADER_SIZE = 56
DEFAULT_ENCODING = "gb18030"

# ---------------- ValueType ----------------
V_INT, V_INT_EX, V_FLOAT, V_SECTION = 2, 3, 4, 5
V_COMMAND, V_STRING, V_CMD_SEP, V_STRLINK_IDX, V_STRLINK = 6, 7, 8, 9, 10

# ---------------- AnimationNodeType ----------------
ANI_LOOP, ANI_SHADOW, ANI_COORD, ANI_IMAGE_RATE, ANI_IMAGE_ROTATE = 0, 1, 3, 7, 8
ANI_RGBA, ANI_INTERPOLATION, ANI_GRAPHIC_EFFECT, ANI_DELAY = 9, 10, 11, 12
ANI_DAMAGE_TYPE, ANI_DAMAGE_BOX, ANI_ATTACK_BOX, ANI_PLAY_SOUND = 13, 14, 15, 16
ANI_PRELOAD, ANI_SPECTRUM, ANI_SET_FLAG, ANI_FLIP_TYPE = 17, 18, 23, 24
ANI_LOOP_START, ANI_LOOP_END, ANI_CLIP = 25, 26, 27


# =====================================================================
# 解密
# =====================================================================
def decrypt(buf: bytearray, crc: int) -> bytearray:
    """原地解密 len//4*4 字节：v = ror32(v ^ PASSWORD_PVF ^ crc, 6)"""
    n = len(buf) // 4 * 4
    if n == 0:
        return buf
    key = (PASSWORD_PVF ^ (crc & 0xFFFFFFFF)) & 0xFFFFFFFF
    if np is not None:
        arr = np.frombuffer(memoryview(buf)[:n], dtype="<u4").copy()
        arr ^= np.uint32(key)
        rot = ((arr >> np.uint32(6)) | (arr << np.uint32(26))) & np.uint32(0xFFFFFFFF)
        buf[:n] = rot.tobytes()
        return buf
    for i in range(0, n, 4):
        v = struct.unpack_from("<I", buf, i)[0] ^ key
        v = ((v >> 6) | (v << 26)) & 0xFFFFFFFF
        struct.pack_into("<I", buf, i, v)
    return buf


def _u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def _i32(b, o):
    return struct.unpack_from("<i", b, o)[0]


def _i16(b, o):
    return struct.unpack_from("<h", b, o)[0]


def _u16(b, o):
    return struct.unpack_from("<H", b, o)[0]


# =====================================================================
# 容器
# =====================================================================
class Entry:
    __slots__ = ("file_number", "path", "length", "crc", "rel_offset", "abs_offset", "computed_length")

    def __init__(self, file_number, path, length, crc, rel_offset, abs_offset):
        self.file_number = file_number
        self.path = path
        self.length = length
        self.crc = crc
        self.rel_offset = rel_offset
        self.abs_offset = abs_offset
        self.computed_length = (length + 3) & 0xFFFFFFFC

    def __repr__(self):
        return f"<Entry {self.path} len={self.length} crc=0x{self.crc:08x} @{self.abs_offset}>"


class PvfArchive:
    def __init__(self, path, encoding=DEFAULT_ENCODING, verbose=False):
        self.path = str(path)
        self.encoding = encoding
        self.verbose = verbose
        self._fh = open(self.path, "rb")
        size = os.fstat(self._fh.fileno()).st_size
        self._mm = mmap.mmap(self._fh.fileno(), 0, access=mmap.ACCESS_READ)
        self.size = size
        self._parse_header()
        self._parse_dir_tree()
        self._entries = {e.path: e for e in self.entries}
        self._string_bin = None
        self._text_encoding = None
        self._string_map = None
        self._string_loaded = False

    # ---------- header / dirTree ----------
    def _parse_header(self):
        b = self._mm[:HEADER_SIZE]
        self.size_guid = _i32(b, 0)
        self.guid = bytes(b[4:40]).decode("ascii", "replace").rstrip("\x00")
        self.file_version = _i32(b, 40)
        self.dir_tree_length = _i32(b, 44)
        self.dir_tree_checksum = _u32(b, 48)
        self.num_files = _i32(b, 52)
        if self.size_guid != 0x24:
            raise ValueError(f"不是 PVF：sizeGUID=0x{self.size_guid:x}（期望 0x24）")
        self.data_start = HEADER_SIZE + self.dir_tree_length

    def _parse_dir_tree(self):
        raw = bytearray(self._mm[HEADER_SIZE:HEADER_SIZE + self.dir_tree_length])
        decrypt(raw, self.dir_tree_checksum)
        self.dir_tree = raw
        entries = []
        pos = 0
        n = self.num_files
        for _ in range(n):
            if pos + 20 > len(raw):
                raise ValueError(f"目录树在 {pos} 处提前结束（声明 {n} 条，实际 {len(entries)} 条）")
            file_number = _u32(raw, pos)
            plen = _i32(raw, pos + 4)
            pstart = pos + 8
            pend = pstart + plen
            if plen < 0 or pend + 12 > len(raw):
                raise ValueError(f"第 {len(entries)} 条路径长度异常 plen={plen} pos={pos}")
            path = bytes(raw[pstart:pend]).decode(self.encoding, "replace")
            length = _i32(raw, pend)
            crc = _u32(raw, pend + 4)
            rel = _i32(raw, pend + 8)
            entries.append(Entry(file_number, path, length, crc, rel, self.data_start + rel))
            pos = pend + 12
        self.entries = entries
        self.dir_tree_used = pos

    # ---------- 读文件 ----------
    def read_raw(self, entry: Entry) -> bytes:
        """读取解密后的明文（未按 fileLength 截断前也用这个拿对齐块）"""
        off = entry.abs_offset
        clen = entry.computed_length
        if off + clen > self.size:
            clen = self.size - off
        buf = bytearray(self._mm[off:off + clen])
        decrypt(buf, entry.crc)
        return bytes(buf[:entry.length])

    def entry(self, path: str) -> Entry:
        p = path.replace("\\", "/").strip("/")
        if p in self._entries:
            return self._entries[p]
        # 宽松匹配：大小写不敏感 + 允许只给文件名
        low = p.lower()
        for e in self.entries:
            if e.path.lower() == low:
                return e
        cand = [e for e in self.entries if e.path.lower().endswith(low)]
        if len(cand) == 1:
            return cand[0]
        raise KeyError(f"找不到条目：{path}" + (f"（有 {len(cand)} 个同后缀候选）" if cand else ""))

    # ---------- 字符串表 ----------
    def load_strings(self):
        if self._string_loaded:
            return
        self._string_loaded = True
        self._string_bin = []
        self._string_map = {}
        try:
            st = self.entry("stringtable.bin")
        except KeyError:
            return
        buf = self.read_raw(st)
        count = _i32(buf, 0)
        if count <= 0 or count > 4_000_000:
            return
        out = []
        for i in range(count):
            start = _i32(buf, i * 4 + 4)
            end = _i32(buf, i * 4 + 8)
            ln = end - start
            s = b""
            if 0 <= ln <= 4 * 1024 * 1024 and 0 <= start + 4 + ln <= len(buf):
                s = bytes(buf[start + 4:start + 4 + ln])
            out.append(self._decode_text(s).strip().lower())
        self._string_bin = out
        try:
            nstr = self.entry("n_string.lst")
        except KeyError:
            return
        nb = self.read_raw(nstr)
        if len(nb) < 12 or _u16(nb, 0) != 53424:
            return
        i = 2
        while i + 10 <= len(nb):
            key_idx = _i32(nb, i + 6)
            i += 10
            if not (0 <= key_idx < len(out)):
                continue
            fname = out[key_idx]
            if not fname:
                continue
            try:
                f = self.entry(fname)
            except KeyError:
                continue
            try:
                txt = self._decode_str(self.read_raw(f), fname)
            except Exception:
                continue
            for line in txt.split("\r\n"):
                if ">" in line:
                    k, v = line.split(">", 1)
                    self._string_map[k.strip()] = v.strip()

    @property
    def string_bin(self):
        self.load_strings()
        return self._string_bin

    @property
    def string_map(self):
        self.load_strings()
        return self._string_map

    def _detect_text_encoding(self) -> str:
        """推断包内「文档里的字符串」的编码（big5hkscs / gb18030 / cp949 / utf-8）。

        判据必须用 stringtable.bin（真正的正文串都在这里），而不是 .str 语言表——
        sf115 的 .str 语言表已被构建工具写成 U+FFFD，但 stringtable 仍是完好的 big5。
        评分：常用汉字数 - 10×(私用区 + 替换符) - 2×(CJK 扩展 A/B)，取最高。
        实测：sf110.08=big5hkscs、sf115=big5hkscs、sf85=cp949。
        """
        if self._text_encoding:
            return self._text_encoding
        sample = b""
        try:
            e = self.entry("stringtable.bin")
            sample = self.read_raw(e)[:65536]
        except Exception:
            sample = b""
        if not sample:
            for e in self.entries:
                if e.path.lower().endswith((".chn.str", ".kor.str", ".jpn.str")):
                    try:
                        sample = self.read_raw(e)[:16384]
                    except Exception:
                        continue
                    break
        if not sample:
            self._text_encoding = self.encoding
            return self.encoding
        best, best_score = self.encoding, -1e18
        for enc in ("big5hkscs", "gb18030", "cp949", "utf-8"):
            # 用 ignore 解码：个别坏字节不该让整段判负；判据是「常用汉字多、私用区字符少」
            txt = sample.decode(enc, "ignore")
            common = sum(1 for c in txt if "\u4e00" <= c <= "\u9fff")
            pua = sum(1 for c in txt if "\ue000" <= c <= "\uf8ff")
            score = common - 20 * pua
            if score > best_score:
                best, best_score = enc, score
        self._text_encoding = best
        return best

    def _decode_text(self, raw: bytes) -> str:
        """正文（stringtable / .str / Document 字符串）解码"""
        enc = self._detect_text_encoding()
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            return raw.decode(enc, "replace")

    def _decode_str(self, raw: bytes, name: str) -> str:
        """语言表解码：按候选编码逐个试，用「CJK 命中率 - 替换符惩罚」打分挑最优。

        实测三种客户端：sf110.08 是繁体中文(big5)、sf115 是简体(被损坏成 U+FFFD)、
        sf85 是韩文(cp949)。后缀只作提示，真正判据是打分。
        """
        if b"\xef\xbf\xbd" in raw:
            return raw.decode("utf-8", "replace")
        best, best_score = None, -1e9
        for enc in (self._enc_for(name), "big5hkscs", "gb18030", "cp949", "utf-8"):
            try:
                txt = raw.decode(enc)
            except UnicodeDecodeError:
                continue
            cjk = sum(1 for c in txt if "\u3400" <= c <= "\u9fff" or "\uff00" <= c <= "\uffef")
            bad = txt.count("\ufffd")
            score = (cjk - 4 * bad) / max(len(txt), 1)
            if score > best_score:
                best, best_score = txt, score
        if best is None:
            best = raw.decode(self.encoding, "replace")
        return best

    @staticmethod
    def _enc_for(name: str) -> str:
        """语言表编码：.kor.str=cp949 / .jpn.str=cp932 / .chn.str=gb18030"""
        low = name.lower()
        if low.endswith(".kor.str"):
            return "cp949"
        if low.endswith(".jpn.str"):
            return "cp932"
        if low.endswith(".chn.str"):
            return "utf-8"
        return DEFAULT_ENCODING

    def close(self):
        try:
            self._mm.close()
        finally:
            self._fh.close()


# =====================================================================
# PvfDocument 解析
# =====================================================================
class Node:
    __slots__ = ("name", "attrs", "children", "has_end")

    def __init__(self, name=""):
        self.name = name
        self.attrs = []
        self.children = []  # [(name, Node)] 保持文档顺序
        self.has_end = False

    def to_dict(self):
        d = {"_name": self.name} if self.name else {}
        if self.attrs:
            d["_attrs"] = [fmt_value(a) for a in self.attrs]
        if self.children:
            out = {}
            for name, ch in self.children:
                lst = out.setdefault(name, [])
                lst.append(ch.to_dict())
            d.update(out)
        return d

    def to_text(self, indent=0):
        pad = "    " * indent
        lines = []
        if self.name:
            lines.append(f"{pad}[{self.name}]")
        for a in self.attrs:
            lines.append(f"{pad}    {fmt_value(a)}")
        for _, ch in self.children:
            lines.extend(ch.to_text(indent + (1 if self.name else 0)))
        if self.name and self.has_end:
            lines.append(f"{pad}[/{self.name}]")
        return lines


def fmt_value(v):
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return f"{int(v)}.0"
        return repr(v)
    return str(v)


def _trim(s: str, chars: str) -> str:
    return s.strip(chars)


def parse_document(buf: bytes, ar: PvfArchive) -> Node:
    root = Node()
    if len(buf) <= 7:
        return root
    binmap = ar.string_bin
    n_bin = len(binmap)

    def lookup(idx):
        if 0 <= idx < n_bin:
            return binmap[idx]
        return ""

    # pass 1: 收集所有出现过的 Section 名 -> 判定谁有结束标签
    tags = set()
    off = 2
    end = len(buf)
    while off < end - 4:
        t = buf[off]
        off += 1
        if V_INT <= t <= V_STRLINK:
            if off + 4 > end:
                break
            idx = _i32(buf, off)
            off += 4
            if t == V_SECTION:
                tags.add(lookup(idx))

    # pass 2
    stack = [root]
    node = root
    off = 2
    while off < end:
        t = buf[off]
        off += 1
        if not (V_INT <= t <= V_STRLINK):
            continue
        if off + 4 > end:
            break
        idx = _i32(buf, off)
        off += 4

        if t in (V_INT, V_INT_EX):
            node.attrs.append(idx)
        elif t == V_FLOAT:
            node.attrs.append(struct.unpack("<f", struct.pack("<I", idx & 0xFFFFFFFF))[0])
        elif t == V_SECTION:
            name = lookup(idx)
            end_tag = name[:1] + "/" + name[1:] if name else ""
            if not name.startswith("[/"):
                nm = _trim(_trim(name, "["), "]")
                if node is not root and node is not None and not node.has_end:
                    node = _pop(stack, node, nm)
                if node is not None:
                    child = Node(nm)
                    child.has_end = end_tag in tags
                    node.children.append((nm, child))
                    stack.append(child)
                    node = child
            else:
                nm = _trim(_trim(name, "[/"), "]")
                node = _pop(stack, node, nm)
        elif t in (V_STRING, V_COMMAND, V_CMD_SEP):
            node.attrs.append(lookup(idx))
        elif t == V_STRLINK:
            key = lookup(idx)
            node.attrs.append(ar.string_map.get(key, ""))
        # V_STRLINK_IDX：参考实现里被注释掉，忽略
    return root


def _pop(stack, node, name):
    if node is not None and node is not stack[0]:
        if len(stack) > 1:
            stack.pop()
        node = stack[-1] if stack else None
        if node is not None and node is not stack[0] and node.name == name:
            return _pop(stack, node, name)
    return node


# =====================================================================
# PvfAnimation 解析
# =====================================================================
def _parse_animation_variant(buf: bytes, encoding: str, *, omit_imgparam_if_ff: bool,
                             coord_size: int, strict_types: bool,
                             unknown_param_payload=None) -> dict:
    pos = 0
    ln = len(buf)

    def rd(fmt, size):
        nonlocal pos
        v = struct.unpack_from(fmt, buf, pos)[0]
        pos += size
        return v

    def rstr():
        nonlocal pos
        n = struct.unpack_from("<i", buf, pos)[0]
        pos += 4
        if n < 0 or pos + n > ln:
            raise ValueError(f"ANI 字符串长度异常 n={n} pos={pos}")
        s = buf[pos:pos + n].decode(encoding, "replace")
        pos += n
        return s

    out = {"frame_count": 0, "sprites": [], "params": {}, "frames": []}
    frame_count = rd("<H", 2)
    res_count = rd("<H", 2)
    out["frame_count"] = frame_count
    sprites = []
    for _ in range(res_count):
        sprites.append(rstr().lower())
    out["sprites"] = sprites
    pcount = rd("<H", 2)
    for _ in range(pcount):
        t = rd("<H", 2)
        if t == ANI_LOOP:
            out["params"]["loop"] = rd("<b", 1)
        elif t == ANI_SHADOW:
            out["params"]["shadow"] = rd("<b", 1)
        elif t == ANI_COORD:          # 全局坐标：实测 4 字节（帧属性里是 2 字节）
            out["params"]["coord"] = rd("<i", 4) if coord_size == 4 else rd("<H", 2)
        elif t == ANI_SPECTRUM and unknown_param_payload is None:  # 频谱/操作块：载荷长度按文件变化
            out["params"]["spectrum"] = True
        elif unknown_param_payload is not None:
            pos += unknown_param_payload
        elif strict_types:
            raise ValueError(f"未知 ANI 参数类型 {t} @{pos - 2}")

    for _fi in range(frame_count):
        fr = {"damage_box": [], "attack_box": []}
        nbox = rd("<H", 2)
        for _ in range(nbox):
            bt = rd("<H", 2)
            box = [rd("<i", 4) for _ in range(6)]
            if bt == ANI_DAMAGE_BOX:
                fr["damage_box"].append(box)
            elif bt == ANI_ATTACK_BOX:
                fr["attack_box"].append(box)
            else:
                fr.setdefault("other_box", []).append([bt, box])
        img_id = rd("<H", 2)
        fr["img_id"] = img_id
        # 0xFFFF = 没有贴图；此时部分 .ani 变体省略 imgParam 两个字节（靠精确消费判定）
        if not (omit_imgparam_if_ff and img_id == 0xFFFF):
            fr["img_param"] = rd("<H", 2)
        else:
            fr["img_param"] = None
        fr["path"] = sprites[img_id] if 0 <= img_id < len(sprites) else None
        fr["x"] = rd("<i", 4)
        fr["y"] = rd("<i", 4)
        np_ = rd("<H", 2)
        for _ in range(np_):
            t = rd("<H", 2)
            if t == ANI_LOOP:
                fr["loop"] = rd("<b", 1)
            elif t == ANI_SHADOW:
                fr["shadow"] = rd("<b", 1)
            elif t == ANI_INTERPOLATION:
                fr["interpolation"] = rd("<b", 1)
            elif t == ANI_COORD:
                fr["coord"] = rd("<H", 2)
            elif t == ANI_IMAGE_RATE:
                fr["rate_x"] = rd("<f", 4)
                fr["rate_y"] = rd("<f", 4)
            elif t == ANI_IMAGE_ROTATE:
                fr["rotate"] = rd("<i", 4)
            elif t == ANI_RGBA:
                fr["color"] = rd("<I", 4)
            elif t == ANI_GRAPHIC_EFFECT:
                it = rd("<H", 2)
                fr["effect"] = it
                if it == 5:  # MONOCHROME
                    fr["effect_color"] = [rd("<B", 1) for _ in range(3)]
                elif it == 6:  # SPACEDISTORT
                    fr["effect_pos"] = [rd("<H", 2), rd("<H", 2)]
            elif t == ANI_DELAY:
                fr["delay"] = rd("<i", 4)
            elif t == ANI_DAMAGE_TYPE:
                fr["damage_type"] = rd("<H", 2)
            elif t == ANI_PLAY_SOUND:
                fr["sound"] = rstr()
            elif t == ANI_SET_FLAG:
                fr["set_flag"] = rd("<i", 4)
            elif t == ANI_FLIP_TYPE:
                fr["flip"] = rd("<H", 2)
            elif t == ANI_LOOP_START:
                fr["loop_start"] = True
            elif t == ANI_LOOP_END:
                fr["loop_end"] = rd("<i", 4)
            elif t == ANI_CLIP:
                fr["clip"] = [rd("<h", 2) for _ in range(4)]
            elif t in (2, 4, 5, 6, 14, 15, 17, 18, 19, 20, 21, 22):
                pass  # 已知但无载荷
            elif strict_types:
                raise ValueError(f"未知 ANI 帧属性类型 {t} @{pos - 2}")
        out["frames"].append(fr)
    out["bytes_consumed"] = pos
    out["bytes_total"] = ln
    return out


def parse_animation(buf: bytes, encoding=DEFAULT_ENCODING, strict=False) -> dict:
    """解析 .ani。

    .ani 存在两种变体：当 imgId==0xFFFF（该帧没有贴图）时，有的文件有
    imgParam(u16) 字段、有的没有；全局坐标参数也有人写成 u16 有人写 i32。
    这里用「正好把整个 buffer 消费完」来判定变体 —— 这是自证的，不需要外部真值。
    """
    variants = [
        dict(omit_imgparam_if_ff=True, coord_size=4, strict_types=strict),
        dict(omit_imgparam_if_ff=True, coord_size=2, strict_types=strict),
        dict(omit_imgparam_if_ff=False, coord_size=4, strict_types=strict),
        dict(omit_imgparam_if_ff=False, coord_size=2, strict_types=strict),
    ]
    # 极少数文件参数区有未知类型（实测 type 18 = 频谱/操作块）：用「精确消费」反推其载荷长度
    variants += [
        dict(omit_imgparam_if_ff=True, coord_size=4, strict_types=False, unknown_param_payload=n)
        for n in range(0, 33)
    ]
    variants += [
        dict(omit_imgparam_if_ff=False, coord_size=4, strict_types=False, unknown_param_payload=n)
        for n in range(0, 33)
    ]
    best = None
    for v in variants:
        try:
            r = _parse_animation_variant(buf, encoding, **v)
        except Exception:
            continue
        r["variant"] = v
        if r["bytes_consumed"] == r["bytes_total"]:
            return r
        if best is None or abs(r["bytes_consumed"] - r["bytes_total"]) < abs(best["bytes_consumed"] - best["bytes_total"]):
            best = r
    if best is not None:
        return best
    # 全部失败：返回只含 header 的空结果，避免整条流水线中断
    return {"frame_count": 0, "sprites": [], "params": {}, "frames": [],
            "bytes_consumed": 0, "bytes_total": len(buf), "variant": None, "error": "全部变体失败"}


def animation_to_text(ani: dict) -> str:
    L = []
    if ani["params"]:
        for k, v in ani["params"].items():
            L.append(f"[{k.upper()}]")
            L.append(f"    {v}")
    for i, fr in enumerate(ani["frames"]):
        L.append(f"[FRAME{i:04d}]")
        L.append(f"    [IMAGE] {fr.get('img_id')}  {fr.get('path')}")
        L.append(f"    [POS] {fr.get('x')} {fr.get('y')}")
        for k in ("img_param", "coord", "rate_x", "rate_y", "rotate", "color",
                  "delay", "damage_type", "flip", "set_flag", "loop", "shadow",
                  "interpolation", "loop_start", "loop_end", "sound", "effect"):
            if k in fr:
                L.append(f"    [{k.upper()}] {fr[k]}")
        for b in fr.get("attack_box", []):
            L.append(f"    [ATTACK BOX] {' '.join(str(x) for x in b)}")
        for b in fr.get("damage_box", []):
            L.append(f"    [DAMAGE BOX] {' '.join(str(x) for x in b)}")
        if "clip" in fr:
            L.append(f"    [CLIP] {' '.join(str(x) for x in fr['clip'])}")
    return "\n".join(L)


# =====================================================================
# 解码分派
# =====================================================================
TEXT_EXTS = (".str", ".nut", ".lua", ".txt", ".xml", ".json", ".cfg", ".ini")


def decode_entry(ar: PvfArchive, entry: Entry):
    """返回 ('text', str) / ('ani', dict) / ('json', dict) / ('bytes', bytes)"""
    raw = ar.read_raw(entry)
    p = entry.path.lower()
    if p.endswith(".ani"):
        ani = parse_animation(raw, ar.encoding)
        return "ani", ani, raw
    if p.endswith(TEXT_EXTS):
        return "text", ar._decode_text(raw), raw
    if p.endswith(".bin") or p.endswith(".wav") or p.endswith(".ogg") or p.endswith(".png") or p.endswith(".img"):
        return "bytes", raw, raw
    try:
        node = parse_document(raw, ar)
        txt = "\n".join(node.to_text())
        return "doc", txt, raw
    except Exception as e:  # 解析失败退回二进制
        return "bytes", (e, raw), raw


# =====================================================================
# CLI
# =====================================================================
def cmd_info(ar: PvfArchive, args):
    print(f"文件      : {ar.path}")
    print(f"大小      : {ar.size:,} 字节")
    print(f"GUID      : {ar.guid}  (sizeGUID=0x{ar.size_guid:02x})")
    print(f"fileVer   : {ar.file_version}")
    print(f"目录树    : {ar.dir_tree_length:,} 字节  (@0x{HEADER_SIZE:x})  checksum=0x{ar.dir_tree_checksum:08x}")
    print(f"条目数    : {ar.num_files:,}")
    print(f"数据区起点: 0x{ar.data_start:x} ({ar.data_start:,})")
    print(f"目录树消耗: {ar.dir_tree_used:,} / {ar.dir_tree_length:,} 字节"
          f"（{'✓ 正好用完' if ar.dir_tree_used == ar.dir_tree_length else '✗ 有剩余'}）")
    exts = {}
    for e in ar.entries:
        ext = os.path.splitext(e.path)[1].lower() or "(无后缀)"
        exts[ext] = exts.get(ext, 0) + 1
    print(f"后缀分布  : " + "  ".join(f"{k}={v:,}" for k, v in sorted(exts.items(), key=lambda kv: -kv[1])[:14]))
    total = sum(e.length for e in ar.entries)
    print(f"明文总长  : {total:,} 字节")
    ar.load_strings()
    print(f"字符串表  : stringtable={len(ar.string_bin):,} 条; n_string 映射={len(ar.string_map):,} 条")


def cmd_verify(ar: PvfArchive, args):
    limit = args.limit or len(ar.entries)
    ok = bad = err = 0
    bad_list = []
    for i, e in enumerate(ar.entries[:limit]):
        try:
            raw = ar.read_raw(e)
            if zlib.crc32(raw) & 0xFFFFFFFF == e.crc:
                ok += 1
            else:
                bad += 1
                if len(bad_list) < 10:
                    bad_list.append((e.path, zlib.crc32(raw) & 0xFFFFFFFF, e.crc))
        except Exception as ex:
            err += 1
            if len(bad_list) < 10:
                bad_list.append((e.path, "ERR", repr(ex)))
    n = min(limit, len(ar.entries))
    print(f"校验 {n:,} 个条目：crc32 命中 {ok:,}  不符 {bad:,}  异常 {err:,}"
          f"  → 通过率 {ok / max(n, 1) * 100:.2f}%")
    for p, got, want in bad_list:
        print("   不符:", p, got, want)


def cmd_list(ar: PvfArchive, args):
    pat = (args.grep or "").lower()
    n = 0
    for e in ar.entries:
        if pat and pat not in e.path.lower():
            continue
        print(f"{e.length:>10,}  {e.path}")
        n += 1
        if args.limit and n >= args.limit:
            break
    print(f"# 共 {n:,} 条" + (f"（已截断，加 --limit 0 看全部）" if args.limit and n >= args.limit else ""))


def cmd_cat(ar: PvfArchive, args):
    e = ar.entry(args.path)
    kind, val, raw = decode_entry(ar, e)
    print(f"# {e.path}  {e.length:,} 字节  kind={kind}")
    if kind == "ani":
        print(animation_to_text(val))
        print(json.dumps(val, ensure_ascii=False, indent=1)[:4000])
    elif kind == "doc":
        print(val)
    elif kind == "text":
        print(val)
    else:
        print(f"(二进制 {len(raw)} 字节) 前 64 字节: {raw[:64].hex(' ')}")


def cmd_raw(ar: PvfArchive, args):
    e = ar.entry(args.path)
    raw = ar.read_raw(e)
    out = Path(args.out or os.path.basename(e.path))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(raw)
    print(f"{e.path} -> {out}  {len(raw):,} 字节")


def cmd_extract(ar: PvfArchive, args):
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)
    pat = (args.grep or "").lower()
    n = 0
    for e in ar.entries:
        if pat and pat not in e.path.lower():
            continue
        kind, val, raw = decode_entry(ar, e)
        dst = outdir / (e.path.replace("\\", "/") + ".txt")
        dst.parent.mkdir(parents=True, exist_ok=True)
        if kind == "ani":
            dst.write_text(animation_to_text(val) + "\n\n/* JSON */\n" + json.dumps(val, ensure_ascii=False, indent=1), encoding="utf-8")
        elif kind in ("doc", "text"):
            dst.write_text(val, encoding="utf-8")
        else:
            dst = outdir / e.path
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(raw)
        n += 1
        if args.max and n >= args.max:
            break
    print(f"导出 {n:,} 个条目 -> {outdir}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="DNF Script.pvf 解包器（纯 Python）")
    ap.add_argument("cmd", choices=["info", "verify", "list", "cat", "raw", "extract"])
    ap.add_argument("pvf")
    ap.add_argument("path", nargs="?", help="内部路径（cat/raw 用）")
    ap.add_argument("--out", default=None)
    ap.add_argument("--grep", default=None)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--max", type=int, default=0)
    ap.add_argument("--encoding", default=DEFAULT_ENCODING)
    args = ap.parse_args(argv)

    ar = PvfArchive(args.pvf, encoding=args.encoding)
    try:
        {"info": cmd_info, "verify": cmd_verify, "list": cmd_list,
         "cat": cmd_cat, "raw": cmd_raw, "extract": cmd_extract}[args.cmd](ar, args)
    finally:
        ar.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
