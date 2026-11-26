#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DNF `.ani` 版本 6 二进制解析器（容错 + 自校验）。

库用法::

    from tools.ani_parser import parse_ani
    info = parse_ani(open(path, 'rb').read())

命令行::

    python tools/ani_parser.py FILE...          # 每个文件一行摘要
    python tools/ani_parser.py --json FILE      # 完整 JSON
    python tools/ani_parser.py --check GLOB     # 批量统计干净率

格式规范见 docs/ANI-FORMAT.md。核心语法（已用知识库里的 ANI 正样本逐字节核对）::

    file   = u16 frame_max, u16 img_count, img_count * (u32 len, char[len]),
             <prologue>, frame * frame_max, <trailing>
    frame  = u16 n_head, n_head * (u16 field_id, payload),
             image_slot, i32 x, i32 y,
             u16 n_tail, n_tail * (u16 field_id, payload)
    image_slot = 0xFFFF                      # 本帧无图
               | u16 img_index, u16 img_frame

未知字段 id 的处理：先试「u16 长度 + N 字节」的字符串形态，再试常见定长，
由「恰好读到 EOF / 帧数用尽」这一分帧约束挑出唯一解（见 `_payload_candidates`）。
"""
from __future__ import annotations

import json
import struct
import sys

sys.setrecursionlimit(20000)

# ---------------------------------------------------------------------------
# 定长字段表：id -> (payload 字节数, 名称, 解码格式)
# 依据：官方注释 OfficialAnnotationTranslation/animation.ani.txt 的字段顺序 +
#       二进制逐字节对齐（证据见 docs/ANI-FORMAT.md）。
# ---------------------------------------------------------------------------
FIELD_SPEC = {
    0x07: (8, "image_rate", "ff"),        # [IMAGE RATE] 2 * float
    0x08: (4, "image_rotate", "f"),       # [IMAGE ROTATE] 1 * float
    0x09: (4, "rgba", "BBBB"),            # [RGBA] 4 * u8
    0x0A: (1, "interpolation", "B"),      # [INTERPOLATION] u8
    0x0B: (2, "graphic_effect", "H"),     # [GRAPHIC EFFECT] u16 枚举
    0x0C: (4, "delay", "I"),              # [DELAY] u32 毫秒
    0x0D: (2, "damage_type", "H"),        # [DAMAGE TYPE] u16 枚举
    0x0E: (24, "damage_box", "6i"),       # [DAMAGE BOX] 6 * i32
    0x0F: (24, "attack_box", "6i"),       # [ATTACK BOX] 6 * i32
    # [FLAG] flagIndex：每帧的关键帧 flag，i32 小端，作者自定义整数，
    # 语义等同脚本里传给 sq_SetCurrentAnimation 的 flag 实参。
    # 证据：analysis/11-P0-BLOCKERS.md ① —— dashattack.ani 5 帧 = [-,100,-,1,101]，
    # 与脚本实参逐值相等；after_threesideex.ani 帧 2 = 3。
    # 两条历史修正：a) 早期版本记成「4~6B 未知字段」是错的；
    #   b) 少数文件只有按 6/8 字节才能闭合帧边界（对齐伪影/文法变体），
    #      这类由 _profiles() 保留兜底长度，语义仍取前 4 字节。
    0x17: (4, "flag_index", "i"),
}

# 非定长 / 未定长字段：由学习得到（id -> 说明）
VAR_FIELDS = {
    # [PLAY SOUND] 类字符串：u32 长度前缀 + ASCII（证据见 docs/ANI-FORMAT.md §5）
    0x10: ("string_u32len", "string_field_0x10"),
}

FIELD_TAG = {
    "image_rate": "[IMAGE RATE]",
    "image_rotate": "[IMAGE ROTATE]",
    "rgba": "[RGBA]",
    "interpolation": "[INTERPOLATION]",
    "graphic_effect": "[GRAPHIC EFFECT]",
    "delay": "[DELAY]",
    "damage_type": "[DAMAGE TYPE]",
    "damage_box": "[DAMAGE BOX]",
    "attack_box": "[ATTACK BOX]",
    "flag_index": "[FLAG]",
}

GRAPHIC_EFFECT = {0: "NONE", 1: "DODGE", 2: "LINEARDODGE", 3: "DARK", 4: "XOR", 5: "MONOCHROME"}
DAMAGE_TYPE = {0: "NORMAL", 1: "SUPERARMOR", 2: "UNBREAKABLE"}

NO_IMAGE = 0xFFFF
MAX_COUNT = 64           # n_head / n_tail 上限（防坏文件）
MAX_PROLOGUE = 12        # 文件级前置区最大搜索长度
NODE_BUDGET = 40000      # 单文件搜索节点上限
GUESS_SIZES = (2, 0, 4, 8, 1, 6, 12, 16, 24, 3, 5, 10, 20, 32)


# ---------------------------------------------------------------------------
# 头部
# ---------------------------------------------------------------------------
def _read_header(data):
    """返回 (frame_max, img_count, images, body_offset)；失败抛 ValueError。"""
    if len(data) < 4:
        raise ValueError("文件不足 4 字节")
    frame_max, img_count = struct.unpack_from("<HH", data, 0)
    off = 4
    images = []
    for _ in range(img_count):
        if off + 4 > len(data):
            raise ValueError("图像路径长度越界")
        n = struct.unpack_from("<I", data, off)[0]
        off += 4
        if off + n > len(data):
            raise ValueError("图像路径越界（长度 %d）" % n)
        images.append(data[off:off + n].decode("latin-1"))
        off += n
    return frame_max, img_count, images, off


# ---------------------------------------------------------------------------
# 字段 payload 候选
# ---------------------------------------------------------------------------
def _payload_candidates(body, p, fid):
    """给出 (payload_bytes, new_offset, 说明) 的候选列表，按可信度排序。"""
    out = []
    spec = FIELD_SPEC.get(fid)
    if spec is not None:
        size = spec[0]
        if p + size <= len(body):
            out.append((body[p:p + size], p + size, "fixed"))
        return out
    if fid in VAR_FIELDS:
        how = VAR_FIELDS[fid][0]
        if how == "string_u32len" and p + 4 <= len(body):
            n = struct.unpack_from("<I", body, p)[0]
            if n <= 256 and p + 4 + n <= len(body):
                out.append((body[p:p + 4 + n], p + 4 + n, how))
        if p + 2 <= len(body):
            n = struct.unpack_from("<H", body, p)[0]
            if n <= 256 and p + 2 + n <= len(body):
                out.append((body[p:p + 2 + n], p + 2 + n, "string_u16len"))
        return out
    # 未知 id：先猜「u16 长度 + N 字节」的字符串形态（0x10 就是这样），再猜定长
    if p + 2 <= len(body):
        n = struct.unpack_from("<H", body, p)[0]
        if 0 < n <= 128 and p + 2 + n <= len(body):
            out.append((body[p:p + 2 + n], p + 2 + n, "guess_u16len"))
    for size in GUESS_SIZES:
        if p + size <= len(body):
            out.append((body[p:p + size], p + size, "guess_%d" % size))
    return out


def _decode_field(fid, raw):
    spec = FIELD_SPEC.get(fid)
    if spec is None:
        return {"raw": raw.hex()}
    _, name, fmt = spec
    if fmt == "i":
        # flagIndex：i32 小端。绝大多数是 4 字节；若因对齐伪影/文法变体读到更长的
        # payload，语义仍取前 4 字节，同时保留原始 hex 以便复查。
        if len(raw) >= 4:
            v = struct.unpack("<i", raw[:4])[0]
            return {"int": v} if len(raw) == 4 else {"int": v, "raw": raw.hex()}
        return {"raw": raw.hex()}
    try:
        vals = struct.unpack("<" + fmt, raw)
    except struct.error:
        return {"raw": raw.hex()}
    if fmt == "6i":
        return {"box": list(vals)}
    if fmt == "ff":
        return {"float": list(vals)}
    if fmt == "f":
        return {"float": vals[0]}
    if fmt == "BBBB":
        return {"rgba": list(vals)}
    if fmt == "H":
        if name == "graphic_effect":
            return {"enum": vals[0], "name": GRAPHIC_EFFECT.get(vals[0], "?")}
        if name == "damage_type":
            return {"enum": vals[0], "name": DAMAGE_TYPE.get(vals[0], "?")}
        return {"int": vals[0]}
    if fmt in ("I", "B"):
        return {"int": vals[0]}
    return {"raw": raw.hex()}


def _make_field(fid, raw, how):
    spec = FIELD_SPEC.get(fid)
    name = spec[1] if spec else ("string_field_0x%02x" % fid if how.startswith("guess_u16len")
                                 else "unknown_0x%02x" % fid)
    return {"id": "0x%02x" % fid, "name": name, "tag": FIELD_TAG.get(name),
            "how": how, "value": _decode_field(fid, raw)}


# ---------------------------------------------------------------------------
# 帧解析（带回溯）
# ---------------------------------------------------------------------------
def _walk(body, frame_max, img_count, start, stats, budget):
    """从 start 解析 frame_max 帧，返回 (frames, end) 或 None。"""
    if frame_max == 0:
        return [], start
    return _walk_frame(body, frame_max, img_count, 0, start, stats, budget)


def _walk_frame(body, frame_max, img_count, idx, p, stats, budget):
    if idx == frame_max:
        return [], p
    if budget[0] <= 0:
        return None
    budget[0] -= 1
    if p + 2 > len(body):
        return None
    n_head = struct.unpack_from("<H", body, p)[0]
    if n_head > MAX_COUNT:
        return None
    got = _walk_fields(body, p + 2, n_head, stats, budget)
    if got is None:
        return None
    head, p2 = got
    if p2 + 2 > len(body):
        return None
    v = struct.unpack_from("<H", body, p2)[0]
    if v == NO_IMAGE:
        img_idx, img_frame, p3 = None, NO_IMAGE, p2 + 2
    else:
        if p2 + 4 > len(body):
            return None
        img_idx, img_frame, p3 = v, struct.unpack_from("<H", body, p2 + 2)[0], p2 + 4
    if p3 + 10 > len(body):
        return None
    x, y = struct.unpack_from("<ii", body, p3)
    p4 = p3 + 8
    n_tail = struct.unpack_from("<H", body, p4)[0]
    if n_tail > MAX_COUNT:
        return None
    got = _walk_fields(body, p4 + 2, n_tail, stats, budget)
    if got is None:
        return None
    tail, p5 = got
    rest = _walk_frame(body, frame_max, img_count, idx + 1, p5, stats, budget)
    if rest is None:
        return None
    frames, end = rest
    frames.insert(0, {
        "index": idx,
        "image": img_idx,
        "image_frame": (None if img_frame == NO_IMAGE else img_frame),
        "has_image": img_frame != NO_IMAGE,
        "pos": [x, y],
        "fields": head + tail,
    })
    return frames, end


def _walk_fields(body, p, count, stats, budget):
    """解析 count 个 (u16 id, payload)，返回 (fields, end) 或 None。"""
    if count == 0:
        return [], p
    if budget[0] <= 0:
        return None
    if p + 2 > len(body):
        return None
    fid = struct.unpack_from("<H", body, p)[0]
    p += 2
    for raw, np, how in _payload_candidates(body, p, fid):
        budget[0] -= 1
        if budget[0] <= 0:
            return None
        got = _walk_fields(body, np, count - 1, stats, budget)
        if got is None:
            continue
        tail, end = got
        if how != "fixed":
            stats[fid] = stats.get(fid, {})
            stats[fid][how] = stats[fid].get(how, 0) + 1
        return [_make_field(fid, raw, how)] + tail, end
    return None



def _walk_strict(body, frame_max, img_count, start, idsz):
    """不做回溯的严格解析：所有字段 id 都必须在 idsz 里。返回 (frames, end) 或 None。"""
    p = start
    frames = []
    for idx in range(frame_max):
        if p + 2 > len(body):
            return None
        n_head = struct.unpack_from("<H", body, p)[0]
        p += 2
        if n_head > MAX_COUNT:
            return None
        head = []
        for _ in range(n_head):
            if p + 2 > len(body):
                return None
            fid = struct.unpack_from("<H", body, p)[0]
            p += 2
            size = idsz.get(fid)
            if size is None or p + size > len(body):
                return None
            head.append(_make_field(fid, body[p:p + size], "fixed"))
            p += size
        if p + 2 > len(body):
            return None
        v = struct.unpack_from("<H", body, p)[0]
        if v == NO_IMAGE:
            img_idx, img_frame, p2 = None, NO_IMAGE, p + 2
        else:
            if p + 4 > len(body):
                return None
            img_idx = v
            img_frame = struct.unpack_from("<H", body, p + 2)[0]
            p2 = p + 4
        if p2 + 10 > len(body):
            return None
        x, y = struct.unpack_from("<ii", body, p2)
        p3 = p2 + 8
        n_tail = struct.unpack_from("<H", body, p3)[0]
        p3 += 2
        if n_tail > MAX_COUNT:
            return None
        tail = []
        for _ in range(n_tail):
            if p3 + 2 > len(body):
                return None
            fid = struct.unpack_from("<H", body, p3)[0]
            p3 += 2
            size = idsz.get(fid)
            if size is None or p3 + size > len(body):
                return None
            tail.append(_make_field(fid, body[p3:p3 + size], "fixed"))
            p3 += size
        frames.append({
            "index": idx,
            "image": img_idx,
            "image_frame": (None if img_frame == NO_IMAGE else img_frame),
            "has_image": img_frame != NO_IMAGE,
            "pos": [x, y],
            "fields": head + tail,
        })
        p = p3
    return frames, p


# 字段表 profile：0x17（flagIndex）的语义是 i32，故 4 字节优先；其余长度是对齐
# 伪影/文法变体的历史兜底。实测 30,000 抽样里 8,379 个 0x17 全部恰好 4 字节
# （把 4 放首位后没有一个是"长 payload"），且 ok/clean 计数与旧的 6 优先顺序完全一致。
def _profiles():
    base = {fid: spec[0] for fid, spec in FIELD_SPEC.items()}
    out = []
    for v17 in (4, 6, 8, 0, 2, 5, 12):
        prof = dict(base)
        prof[0x17] = v17
        out.append(prof)
    return out


# ---------------------------------------------------------------------------
# 主入口
# ---------------------------------------------------------------------------
def parse_ani(data):
    """解析一个 .ani（版本 6）。永远返回 dict，不抛异常。"""
    out = {
        "ok": False,
        "error": None,
        "version": 6,
        "size": len(data) if data else 0,
        "frame_max": None,
        "img_count": None,
        "images": [],
        "prologue": "",
        "trailing": "",
        "clean": False,
        "frames": [],
        "warnings": [],
        "unknown_fields": {},
    }
    if not data:
        out["error"] = "空文件"
        return out
    try:
        frame_max, img_count, images, body_off = _read_header(data)
    except (ValueError, struct.error) as exc:
        out["error"] = "头部损坏: %s" % exc
        return out
    out["frame_max"] = frame_max
    out["img_count"] = img_count
    out["images"] = images
    body = data[body_off:]
    out["body_size"] = len(body)

    best = None
    # 第一轮：定长 profile × prologue 严格试解（快，且不会产生编造的字段长度）
    for idsz in _profiles():
        for pro in range(0, MAX_PROLOGUE + 1):
            if pro > len(body):
                break
            res = _walk_strict(body, frame_max, img_count, pro, idsz)
            if res is None:
                continue
            frames, end = res
            rest = body[end:]
            clean = len(rest) <= 4 and not any(rest)
            score = (0 if clean else 1, 0, pro)
            if best is None or score < best[0]:
                best = (score, pro, frames, end, {}, rest, clean)
            if clean:
                break
        if best is not None and best[0][0] == 0:
            break
    # 第二轮：回溯试解（允许未知字段 id，靠 EOF 约束定型）
    if best is None or best[0][0] != 0:
        for pro in range(0, MAX_PROLOGUE + 1):
            if pro > len(body):
                break
            stats = {}
            budget = [NODE_BUDGET]
            try:
                res = _walk(body, frame_max, img_count, pro, stats, budget)
            except struct.error:
                res = None
            if res is None:
                continue
            frames, end = res
            rest = body[end:]
            clean = len(rest) <= 4 and not any(rest)
            score = (0 if clean else 1, len(stats), pro)
            if best is None or score < best[0]:
                best = (score, pro, frames, end, stats, rest, clean)
            if clean and not stats:
                break

    if best is None:
        out["error"] = "无法解析帧结构（%d 帧，body %d 字节）" % (frame_max, len(body))
        return out
    _, pro, frames, end, stats, rest, clean = best
    out["ok"] = True
    out["clean"] = clean
    out["prologue"] = body[:pro].hex()
    out["trailing"] = rest.hex()
    out["frames"] = [_flatten_frame(f) for f in frames]
    if stats:
        out["unknown_fields"] = {"0x%02x" % k: v for k, v in sorted(stats.items())}
        out["warnings"].append("出现未定字段 id: %s" % ", ".join("0x%02x" % k for k in sorted(stats)))
    if not clean:
        out["warnings"].append("尾部残留 %d 字节" % len(rest))
    if pro:
        out["warnings"].append("文件级前置区 %d 字节（结构待验证）" % pro)
    return out


def _flatten_frame(frame):
    flat = {
        "index": frame["index"],
        "image": frame["image"],
        "image_frame": frame["image_frame"],
        "has_image": frame["has_image"],
        "x": frame["pos"][0],
        "y": frame["pos"][1],
        "delay": None,
        "rgba": None,
        "image_rate": None,
        "image_rotate": None,
        "interpolation": None,
        "graphic_effect": None,
        "damage_type": None,
        "flag_index": None,
        "attack_boxes": [],
        "damage_boxes": [],
        "other_fields": [],
        "fields": frame["fields"],
    }
    for f in frame["fields"]:
        name, val = f["name"], f["value"]
        if name == "delay":
            flat["delay"] = val.get("int")
        elif name == "rgba":
            flat["rgba"] = val.get("rgba")
        elif name == "image_rate":
            flat["image_rate"] = val.get("float")
        elif name == "image_rotate":
            flat["image_rotate"] = val.get("float")
        elif name == "interpolation":
            flat["interpolation"] = val.get("int")
        elif name == "graphic_effect":
            flat["graphic_effect"] = val.get("name")
        elif name == "damage_type":
            flat["damage_type"] = val.get("name")
        elif name == "flag_index":
            flat["flag_index"] = val.get("int")
        elif name == "attack_box":
            flat["attack_boxes"].append(val.get("box"))
        elif name == "damage_box":
            flat["damage_boxes"].append(val.get("box"))
        else:
            flat["other_fields"].append({"id": f["id"], "name": name, "value": val})
    return flat


# ---------------------------------------------------------------------------
# 帧表（交给 P0.6 与 Godot 运行时的中间产物，见 docs/ANI-FORMAT.md §7）
# ---------------------------------------------------------------------------
def to_frame_table(info, image_path=None):
    """把 parse_ani 的结果压成一条「帧表」记录。"""
    if not info.get("ok"):
        return None
    images = info.get("images") or []
    frames = []
    t = 0
    for f in info["frames"]:
        rows = []
        if f["has_image"]:
            img = images[f["image"]] if f["image"] is not None and f["image"] < len(images) else None
            rows.append([img, f["image_frame"]])
        frames.append({
            "i": f["index"],
            "x": f["x"],
            "y": f["y"],
            "d": f["delay"],
            "t": t,
            "img": rows,
            "ab": f["attack_boxes"],
            "db": f["damage_boxes"],
            "flag": f["flag_index"],
            "fx": {"rate": f["image_rate"], "rot": f["image_rotate"],
                   "rgba": f["rgba"], "gfx": f["graphic_effect"],
                   "interp": f["interpolation"], "dmgtype": f["damage_type"]},
        })
        t += f["delay"] or 0
    return {
        "src": image_path,
        "ani_frames": info["frame_max"],
        "images": images,
        "total_ms": t,
        "frames": frames,
        "clean": info["clean"],
    }


# ---------------------------------------------------------------------------
# 命令行
# ---------------------------------------------------------------------------
def _summary(info, path):
    if not info["ok"]:
        return "FAIL   %-40s %s" % (info["error"], path)
    delays = [f["delay"] for f in info["frames"] if f["delay"] is not None]
    atk = sum(len(f["attack_boxes"]) for f in info["frames"])
    dmg = sum(len(f["damage_boxes"]) for f in info["frames"])
    flag = "ok " if info["clean"] else "dirty"
    flags = [(f["index"], f["flag_index"]) for f in info["frames"] if f["flag_index"] is not None]
    return ("%-5s frames=%d/%d imgs=%d delay=%s..%s atk=%d dmg=%d flag=%s pro=%d rest=%d  %s"
            % (flag, len(info["frames"]), info["frame_max"], info["img_count"],
               min(delays) if delays else "-", max(delays) if delays else "-",
               atk, dmg, "[" + ",".join("%d@f%d" % (v, i) for i, v in flags) + "]" if flags else "-",
               len(info["prologue"]) // 2, len(info["trailing"]) // 2, path))


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    if argv[0] == "--json":
        for path in argv[1:]:
            print(json.dumps(parse_ani(open(path, "rb").read()), ensure_ascii=False, indent=1))
        return 0
    if argv[0] == "--check":
        import collections
        import glob as _glob
        pat = argv[1] if len(argv) > 1 else "export/text/**/*.ani.bin"
        files = _glob.glob(pat, recursive=True)
        cnt = collections.Counter()
        for path in files:
            info = parse_ani(open(path, "rb").read())
            cnt["clean" if info["clean"] else ("dirty" if info["ok"] else "fail")] += 1
        total = sum(cnt.values())
        print(json.dumps({"total": total, "counts": dict(cnt),
                          "clean_rate": round(cnt["clean"] / total, 4) if total else 0}, ensure_ascii=False))
        return 0
    for path in argv:
        print(_summary(parse_ani(open(path, "rb").read()), path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
