#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""NPK/IMG -> 图集（atlas）打包管线。

把 t6 的 `npk_parser` 从「一张 .img -> 一堆散 PNG」提升到「一张 .img -> 若干张
2048x2048 页 PNG + 一份可按需 seek 的帧矩形表」，给 Godot 侧用
`Sprite2D.texture` + `region_rect` 渲染（见 docs/GODOT-EVAL.md C1：
百万帧不能当资源导入，只能走自建运行时管线）。

产出（默认 `export/atlas/`）：

    manifest.jsonl     一行一个 .img：版本 / 页清单 / 矩形表字节区间 / 统计
    rects.jsonl        帧矩形，按 .img 顺序连续排列（引擎按 manifest 里的
                       rect_offset + rect_length 直接 seek 读，不用整文件解析）
    <img 路径>.p<N>.png 每页一张 PNG（单页时就是 .p0.png）

用法：
    python3 tools/npk_atlas.py build            # 按切片清单打包
    python3 tools/npk_atlas.py build --limit 8  # 先试 8 张
    python3 tools/npk_atlas.py check --n 200    # 覆盖率抽样（四个根）
    python3 tools/npk_atlas.py stats            # 页数/体积/DDS 分布统计
    python3 tools/npk_atlas.py verify           # 回读 manifest+rects+页 PNG
    python3 tools/npk_atlas.py batch --monsters 12 --skills 20

坐标系（与 t6 的 docs/NPK-FORMAT.md §5.1 一致）：
    帧在角色原点坐标系里的左上角 = (帧头 x, 帧头 y)，
    渲染时再叠加 .ani 的 `[IMAGE POS]`：draw = (ani.x + pivot_x, ani.y + pivot_y)。
    矩形表里的 `pivot_x/pivot_y` 就是这里说的「帧头 x/y」，**没有做任何居中修正**。
"""

import argparse
import json
import os
import struct
import sys
import tempfile
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import npk_parser as P  # noqa: E402  复用 t6 的解码器，不重写

DEFAULT_PACK_DIR = P.DEFAULT_PACK_DIR
DEFAULT_OUT = os.path.join(ROOT, "export", "atlas")
DEFAULT_MANIFEST = os.path.join(ROOT, "export", "_meta", "slice_manifest.json")

# 图集默认页尺寸；单帧超过它时整张 .img 的页尺寸升到 2 的幂
PAGE_SIZE = 2048
MAX_PAGE = 8192


# --------------------------------------------------------------------------
# 装箱：MaxRects (best-short-side-fit)
# --------------------------------------------------------------------------

class MaxRects(object):
    """经典 MaxRects 装箱。不支持旋转（DNF 的帧都是正的，旋转反而要额外矩阵）。"""

    __slots__ = ("w", "h", "free", "used_area")

    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.free = [(0, 0, w, h)]
        self.used_area = 0

    def insert(self, w, h):
        """Bottom-Left 放置：优先最靠上、再最靠左。

        不用 best-short-side-fit —— 对 DNF 这种「一大堆 28x28 图标」的语料，
        BSSF 会先填满 (0,y) 这条竖条（因为 28 宽的窄条 residual 更小），
        结果是图标沿左边一列铺到底、再横着铺一行，浪费且不利于纹理缓存。
        BL 保证按行铺开。
        """
        best = None
        best_score = None
        for (fx, fy, fw, fh) in self.free:
            if fw >= w and fh >= h:
                score = (fy, fx)
                if best_score is None or score < best_score:
                    best_score = score
                    best = (fx, fy, fw, fh)
        if best is None:
            return None
        x, y = best[0], best[1]
        self._split(x, y, w, h)
        self.used_area += w * h
        return x, y

    def _split(self, x, y, w, h):
        out = []
        for (fx, fy, fw, fh) in self.free:
            if x >= fx + fw or x + w <= fx or y >= fy + fh or y + h <= fy:
                out.append((fx, fy, fw, fh))          # 不相交，原样保留
                continue
            # 上
            if y > fy:
                out.append((fx, fy, fw, y - fy))
            # 下
            if y + h < fy + fh:
                out.append((fx, y + h, fw, fy + fh - (y + h)))
            # 左
            if x > fx:
                out.append((fx, fy, x - fx, fh))
            # 右
            if x + w < fx + fw:
                out.append((x + w, fy, fx + fw - (x + w), fh))
        # 去掉被其他空闲矩形完全包含的（MaxRects 的 prune）
        pruned = []
        for i, a in enumerate(out):
            ax, ay, aw, ah = a
            if aw <= 0 or ah <= 0:
                continue
            contained = False
            for j, b in enumerate(out):
                if i == j:
                    continue
                bx, by, bw, bh = b
                if ax >= bx and ay >= by and ax + aw <= bx + bw and ay + ah <= by + bh:
                    # 完全相同时只保留一个，避免互相判定为「包含」
                    if (ax, ay, aw, ah) == (bx, by, bw, bh) and j > i:
                        continue
                    contained = True
                    break
            if not contained:
                pruned.append(a)
        self.free = pruned


# --------------------------------------------------------------------------
# 单张 .img 的图集化
# --------------------------------------------------------------------------

def _next_pow2(n):
    p = 1
    while p < n:
        p <<= 1
    return p


def _frame_format(img, f):
    """给统计用的「源像素格式」标签。"""
    if f.is_reference:
        return "reference"
    v = img.version
    if v == 5 and f.compressed == P.C_DDSREF:
        rec = img.dds_table[f.dds_index] if 0 <= f.dds_index < len(img.dds_table) else None
        pf = rec["pixel_format"] if rec else -1
        return {0x0E: "dds-argb1555", 0x10: "dds-argb8888",
                0x12: "dxt1", 0x13: "dxt3", 0x14: "dxt5"}.get(pf, "dds-%02X" % (pf & 0xFF))
    t = f.type
    if t == P.T_ARGB8888:
        return "argb8888"
    if t == P.T_ARGB4444:
        return "argb4444"
    if t == P.T_ARGB1555:
        return "indexed" if v in (4, 6) else "argb1555"
    return "0x%02X" % t


class ImagePacker(object):
    """把一张 .img 的全部帧装进若干页，返回 (pages, rects, stats)。"""

    def __init__(self, page_size=PAGE_SIZE, adaptive=False):
        self.page_size = page_size
        self.adaptive = adaptive

    def pack(self, img, img_path):
        n = img.frame_count
        # 解一遍所有帧（含指向帧解引用），同时拿到每帧尺寸
        blobs = []
        rects = []
        max_dim = 1
        for i in range(n):
            if img.resolved[i] < 0:
                # 环 / 指向越界：按约定降级成空帧占位，不占图集面积
                blobs.append((0, 0, b""))
                rects.append({"frame_index": i, "w": 0, "h": 0,
                              "pivot_x": 0, "pivot_y": 0})
                continue
            try:
                w, h, x, y, rgba = img.frame_image(i)
            except P.NpkError as ex:
                img.warnings.append("帧 %d 解码失败：%s" % (i, ex))
                w, h, x, y, rgba = 0, 0, 0, 0, b""
            blobs.append((w, h, rgba))
            rects.append({"frame_index": i, "w": w, "h": h, "pivot_x": x, "pivot_y": y})
            max_dim = max(max_dim, w, h)

        size = self.page_size
        if self.adaptive:
            # 按内容面积挑最小的 2 的幂页，避免小图占一整张 2048x2048（16 MB 显存）
            area = sum(w * h for (w, h, _) in blobs if w > 0 and h > 0)
            need = _next_pow2(int((area * 1.25) ** 0.5) + 1)
            size = max(64, min(size, need))
        if max_dim > size:
            size = min(MAX_PAGE, _next_pow2(max_dim))

        # 按高度倒序装箱（大的先放，碎图填补空隙）
        order = sorted(range(n), key=lambda i: (-blobs[i][1], -blobs[i][0]))
        pages = []          # [{"packer":MaxRects, "canvas":bytearray, "frames":n}]
        for idx in order:
            w, h, rgba = blobs[idx]
            if w <= 0 or h <= 0:
                rects[idx]["empty"] = True
                continue
            placed = None
            for pg in pages:
                pos = pg["packer"].insert(w, h)
                if pos is not None:
                    placed = (pg, pos)
                    break
            if placed is None:
                pk = MaxRects(size, size)
                pos = pk.insert(w, h)
                pg = {"packer": pk, "canvas": bytearray(size * size * 4), "frames": 0}
                pages.append(pg)
                placed = (pg, pos)
            pg, (px, py) = placed
            rects[idx]["atlas_page"] = pages.index(pg)
            rects[idx]["x"] = px
            rects[idx]["y"] = py
            _blit(pg["canvas"], size, px, py, w, h, rgba)
            pg["frames"] += 1

        for r in rects:
            r.setdefault("empty", False)
            r.setdefault("atlas_page", -1)
            r.setdefault("x", 0)
            r.setdefault("y", 0)
        return pages, rects, size


def _blit(canvas, stride, dx, dy, w, h, rgba):
    """把 RGBA 帧贴到画布（canvas 是 stride x stride 的 RGBA）。"""
    for row in range(h):
        src = row * w * 4
        dst = ((dy + row) * stride + dx) * 4
        canvas[dst:dst + w * 4] = rgba[src:src + w * 4]


# --------------------------------------------------------------------------
# manifest / rects 写出
# --------------------------------------------------------------------------

def _safe_rel(img_path):
    """img 路径 -> 输出文件名（保留目录层级，去掉危险字符）。"""
    rel = img_path.replace("\\", "/")
    if rel.lower().startswith("sprite/"):
        pass
    bad = '<>:"|?*\x00'
    out = []
    for ch in rel:
        out.append("_" if ch in bad else ch)
    return "".join(out)


def build_one(npk, entry_name, out_dir, page_size, img_path=None, adaptive=False):
    """处理一张 .img：写页 PNG，返回 (manifest 记录, rect 列表)。"""
    img, real_name = npk.open_img(entry_name)
    packer = ImagePacker(page_size, adaptive=adaptive)
    pages, rects, size = packer.pack(img, real_name)

    rel = _safe_rel(img_path or real_name)
    page_files = []
    for pi, pg in enumerate(pages):
        fn = "%s.p%d.png" % (rel, pi)
        full = os.path.join(out_dir, fn)
        d = os.path.dirname(full)
        if d:
            os.makedirs(d, exist_ok=True)
        P.write_png(full, size, size, bytes(pg["canvas"]))
        page_files.append({
            "page": pi,
            "file": fn.replace(os.sep, "/"),
            "w": size,
            "h": size,
            "frames": pg["frames"],
            "bytes": os.path.getsize(full),
        })

    refs = sum(1 for f in img.frames if f.is_reference)
    for r in rects:
        f = img.frames[r["frame_index"]]
        r["is_reference"] = bool(f.is_reference)
        r["ref_target"] = img.resolved[r["frame_index"]] if f.is_reference else r["frame_index"]
        r["rotated"] = False
        r["canvas_w"] = f.frame_width
        r["canvas_h"] = f.frame_height
        r["source_format"] = _frame_format(img, f)

    # 指向帧不再占图集面积：直接复用目标帧的矩形（复用同一块纹理区域）
    by_index = {r["frame_index"]: r for r in rects}
    for r in rects:
        if not r["is_reference"]:
            continue
        t = by_index.get(r["ref_target"])
        if t is None or t["empty"] or t is r:
            continue
        for k in ("w", "h", "x", "y", "atlas_page", "empty"):
            r[k] = t[k]
        r["pivot_x"], r["pivot_y"] = t["pivot_x"], t["pivot_y"]

    rec = {
        "img_path": img_path or real_name,
        "entry": real_name,
        "npk": os.path.basename(npk.path),
        "version": img.version,
        "frame_count": img.frame_count,
        "page_size": size,
        "pages": page_files,
        "page_count": len(page_files),
        "references": refs,
        "cycles": len(img.cycles),
        "cycle_detected": bool(img.cycles),
        "cycle_frames": [c["frame"] for c in img.cycles],
        "warnings": img.warnings[:8],
        "decoded": True,
    }
    return rec, rects


def write_manifest(out_dir, records):
    """records: [(manifest_rec, rect_rows)] -> 写 manifest.jsonl + rects.jsonl"""
    os.makedirs(out_dir, exist_ok=True)
    man_path = os.path.join(out_dir, "manifest.jsonl")
    rect_path = os.path.join(out_dir, "rects.jsonl")
    with open(rect_path, "wb") as rf, open(man_path, "w", encoding="utf-8") as mf:
        for rec, rows in records:
            start = rf.tell()
            for r in rows:
                line = json.dumps(r, ensure_ascii=False, separators=(",", ":"))
                rf.write(line.encode("utf-8") + b"\n")
            length = rf.tell() - start
            rec["rect_offset"] = start
            rec["rect_length"] = length
            rec["rect_count"] = len(rows)
            mf.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")
    return man_path, rect_path


# --------------------------------------------------------------------------
# 命令
# --------------------------------------------------------------------------

def _load_img_list(args):
    """返回 [(npk 名或 None, img_path)]。"""
    if args.img_list:
        out = []
        for line in open(args.img_list, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            npk_name = None
            if "\t" in line:
                npk_name, line = line.split("\t", 1)
            out.append((npk_name, line))
        return out
    man = json.load(open(args.manifest, encoding="utf-8"))
    out = []
    for it in man.get("images", []):
        npk_hint = (it.get("npk") or [None])[0]
        out.append((npk_hint, it["path"]))
    return out


def cmd_build(args):
    t0 = time.time()
    items = _load_img_list(args)
    if args.limit:
        items = items[:args.limit]
    pool = {}
    for f in os.listdir(args.pack_dir):
        if f.lower().endswith(".npk"):
            pool[f] = os.path.join(args.pack_dir, f)
    os.makedirs(args.out, exist_ok=True)

    cache = {}
    records = []
    ok = fail = 0
    total_frames = 0
    for npk_hint, img_path in items:
        cands = [npk_hint] if npk_hint in pool else list(pool)
        done = False
        err = None
        for n in cands:
            npk = cache.get(n)
            if npk is None:
                try:
                    npk = P.Npk(pool[n])
                except (P.NpkError, OSError) as ex:
                    err = "%s: %s" % (n, ex)
                    continue
                cache[n] = npk
            try:
                npk.index_of(img_path)
            except P.NpkError:
                continue
            try:
                rec, rows = build_one(npk, img_path, args.out, args.page_size, img_path,
                                      adaptive=args.adaptive)
            except P.NpkError as ex:
                err = "%s: %s" % (n, ex)
                continue
            records.append((rec, rows))
            total_frames += rec["frame_count"]
            ok += 1
            done = True
            break
        if not done:
            fail += 1
            print("!! %s：%s" % (img_path, err or "未找到所在 NPK"), file=sys.stderr)

    man_path, rect_path = write_manifest(args.out, records)
    pages = sum(r["page_count"] for r, _ in records)
    pbytes = sum(p["bytes"] for r, _ in records for p in r["pages"])
    print("# 打包 %d 张 img（失败 %d）：%d 帧、%d 页、%.2f MB -> %s"
          % (ok, fail, total_frames, pages, pbytes / 1048576.0, args.out))
    print("# manifest: %s（%.1f KB）" % (man_path, os.path.getsize(man_path) / 1024.0))
    print("# rects   : %s（%.1f KB）" % (rect_path, os.path.getsize(rect_path) / 1024.0))
    print("# 用时 %.1fs" % (time.time() - t0))
    return 0 if fail == 0 else 1


def cmd_check(args):
    """四个根各抽样，统计「整张 .img 解全部帧」的成功率（与 t6 同口径）。"""
    import random
    rng = random.Random(args.seed)
    roots = args.roots
    pool = [f for f in sorted(os.listdir(args.pack_dir)) if f.lower().endswith(".npk")]
    rng.shuffle(pool)
    per_root = max(1, args.n // len(roots))
    got = {r: 0 for r in roots}
    ok = fail = 0
    frames = 0
    fails = []
    t0 = time.time()
    for fn in pool:
        if all(v >= per_root for v in got.values()):
            break
        try:
            npk = P.Npk(os.path.join(args.pack_dir, fn))
        except (P.NpkError, OSError):
            continue
        buckets = {r: [] for r in roots}
        for i, e in enumerate(npk.entries):
            low = e.name.lower()
            if not low.endswith(".img"):
                continue
            # equipment 的图大多住在 sprite/character/<job>/equipment/... 下，
            # 必须先判 equipment 再判 character，否则 equipment 永远抽到 0 张。
            for r in roots:
                if r == "equipment" and "/equipment/" in low:
                    buckets[r].append(i)
                    break
                if r == "character" and "/character/" in low and "/equipment/" not in low:
                    buckets[r].append(i)
                    break
                if r not in ("equipment", "character") and ("/%s/" % r) in low:
                    buckets[r].append(i)
                    break
        for r in roots:
            if got[r] >= per_root or not buckets[r]:
                continue
            i = rng.choice(buckets[r])
            name = npk.entries[i].name
            try:
                npk.index_of(name)
                img, _ = npk.open_img(name)
                for j in range(img.frame_count):
                    img.frame_image(j)
                frames += img.frame_count
                ok += 1
            except Exception as ex:
                fail += 1
                fails.append((name, "%s: %s" % (type(ex).__name__, str(ex)[:60])))
            got[r] += 1
    print("抽样 %d 张（%s）：成功 %d、失败 %d、成功率 %.1f%%，%d 帧，%.1fs"
          % (ok + fail, "/".join("%s=%d" % (r, got[r]) for r in roots), ok, fail,
             100.0 * ok / max(1, ok + fail), frames, time.time() - t0))
    for name, why in fails[:10]:
        print("  !! %s: %s" % (name, why))
    return 0 if ok and 100.0 * ok / max(1, ok + fail) >= 95.0 else 1


def cmd_stats(args):
    man = args.manifest_out
    if not os.path.exists(man):
        raise SystemExit("没有 manifest：%s（先跑 build）" % man)
    imgs = pages = frames = pbytes = 0
    versions = {}
    fmt = {}
    cycles = 0
    cycle_frames = 0
    refs = 0
    page_hist = {}
    with open(man, encoding="utf-8") as f:
        for line in f:
            r = json.loads(line)
            imgs += 1
            pages += r["page_count"]
            frames += r["frame_count"]
            refs += r.get("references", 0)
            for p in r["pages"]:
                pbytes += p["bytes"]
            versions[r["version"]] = versions.get(r["version"], 0) + 1
            page_hist[r["page_count"]] = page_hist.get(r["page_count"], 0) + 1
            if r.get("cycles"):
                cycles += 1
                cycle_frames += r["cycles"]
    # 源像素格式分布：扫 rects
    if os.path.exists(args.rects_out):
        with open(args.rects_out, encoding="utf-8") as f:
            for line in f:
                r = json.loads(line)
                k = r.get("source_format", "?")
                fmt[k] = fmt.get(k, 0) + 1
    print("img %d 张 / %d 帧 / %d 页 / %.2f MB" % (imgs, frames, pages, pbytes / 1048576.0))
    print("版本分布 :", dict(sorted(versions.items())))
    print("页数分布 :", dict(sorted(page_hist.items())))
    print("源格式   :", dict(sorted(fmt.items(), key=lambda x: -x[1])))
    print("指向帧   : %d 帧；含环 img %d 张（%d 帧降级为空帧）" % (refs, cycles, cycle_frames))
    if pages:
        print("平均每页 %.0f 帧、%.2f MB" % (frames / pages, pbytes / pages / 1048576.0))
    return 0


def cmd_verify(args):
    """回读校验：manifest -> rects 字节区间 -> 页 PNG 头，全部对得上才算过。"""
    man_path = args.manifest_out
    rect_path = args.rects_out
    bad = 0
    n = 0
    with open(man_path, encoding="utf-8") as mf, open(rect_path, "rb") as rf:
        for line in mf:
            r = json.loads(line)
            rf.seek(r["rect_offset"])
            blob = rf.read(r["rect_length"])
            rows = [json.loads(x) for x in blob.decode("utf-8").splitlines() if x.strip()]
            if len(rows) != r["frame_count"] or len(rows) != r["rect_count"]:
                print("!! %s 矩形数不符：%d vs 帧 %d" % (r["img_path"], len(rows), r["frame_count"]))
                bad += 1
            for row in rows:
                if row["empty"]:
                    continue
                pg = r["pages"][row["atlas_page"]]
                if row["x"] + row["w"] > pg["w"] or row["y"] + row["h"] > pg["h"]:
                    print("!! %s 帧 %d 越界" % (r["img_path"], row["frame_index"]))
                    bad += 1
                    break
            for p in r["pages"]:
                full = os.path.join(args.out, p["file"])
                if not os.path.exists(full):
                    print("!! 缺页 %s" % full)
                    bad += 1
                    continue
                with open(full, "rb") as f:
                    head = f.read(24)
                w, h = struct.unpack(">II", head[16:24])
                if (w, h) != (p["w"], p["h"]):
                    print("!! %s 页尺寸不符 %dx%d != %dx%d" % (p["file"], w, h, p["w"], p["h"]))
                    bad += 1
            n += 1
            if args.sample and n >= args.sample:
                break
    print("# 回读校验 %d 张 img：%s" % (n, "全部通过" if bad == 0 else "%d 处问题" % bad))
    return 0 if bad == 0 else 1


def cmd_batch(args):
    """小批实测：N 只怪（每只取一个代表 .img）+ 剑士技能特效 M 张。

    「一只怪」在 PVF 里不是一个 .img，而是 `sprite/monster/<怪名>/...` 一整个目录
    （本体动作 + 各种特效）。这里按目录分组，实测每个目录的文件数，再用「目录代表
    img」的真实页数/字节数外推整只怪。
    """
    pool = [f for f in sorted(os.listdir(args.pack_dir)) if f.lower().endswith(".npk")]
    monster_dirs = {}        # dir -> {"count": n, "pick": (npk, img)}
    skill_pick = []
    for fn in pool:
        if len(monster_dirs) >= args.monsters and len(skill_pick) >= args.skills:
            break
        try:
            npk = P.Npk(os.path.join(args.pack_dir, fn))
        except (P.NpkError, OSError):
            continue
        for e in npk.entries:
            low = e.name.lower()
            if not low.endswith(".img"):
                continue
            if "/monster/" in low:
                d = os.path.dirname(e.name)
                cur = monster_dirs.get(d)
                if cur is None:
                    if len(monster_dirs) < args.monsters * args.per_dir:
                        monster_dirs[d] = {"count": 1, "pick": (fn, e.name)}
                else:
                    cur["count"] += 1
            elif "/character/swordman/effect/" in low and len(skill_pick) < args.skills:
                skill_pick.append((fn, e.name))

    dirs = sorted(monster_dirs.items(), key=lambda kv: -kv[1]["count"])[:args.monsters]
    print("# 怪物目录 %d 个（每个目录 = 一只怪）：" % len(dirs))
    for d, v in dirs:
        print("#   %-70s %3d 个 img" % (d[:70], v["count"]))
    print("# 技能特效 %d 张" % len(skill_pick))

    tmp = os.path.join(args.out, "_batch")
    cache = {}

    def _npk(fn):
        n = cache.get(fn)
        if n is None:
            n = cache[fn] = P.Npk(os.path.join(args.pack_dir, fn))
        return n

    res = {}
    for label, items in (("monster", [(v["pick"], d, v["count"]) for d, v in dirs]),
                         ("skill", [((fn, name), name, 1) for fn, name in skill_pick])):
        pages = frames = 0
        nbytes = 0
        ext = 0          # 按目录文件数外推出的字节数
        for (fn, name), d, cnt in items:
            try:
                rec, _ = build_one(_npk(fn), name, tmp, args.page_size, name,
                                   adaptive=args.adaptive)
            except P.NpkError as ex:
                print("#  !! %s: %s" % (name, ex))
                continue
            pages += rec["page_count"]
            frames += rec["frame_count"]
            b = sum(p["bytes"] for p in rec["pages"])
            nbytes += b
            ext += b * cnt
        res[label] = {"imgs_sampled": len(items), "frames": frames,
                      "pages": pages, "bytes": nbytes, "bytes_extrapolated": ext}
        print("# %s：实测 %d 张 img、%d 帧、%d 页、%.2f MB；按目录文件数外推 %.2f MB"
              % (label, len(items), frames, pages, nbytes / 1048576.0, ext / 1048576.0))
    tot_pages = sum(v["pages"] for v in res.values())
    tot_bytes = sum(v["bytes"] for v in res.values())
    tot_ext = sum(v["bytes_extrapolated"] for v in res.values())
    print("# 合计实测：%d 页、%.2f MB（外推 %.2f MB）"
          % (tot_pages, tot_bytes / 1048576.0, tot_ext / 1048576.0))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump({"res": res, "total_pages": tot_pages, "total_bytes": tot_bytes,
                       "total_bytes_extrapolated": tot_ext,
                       "monster_dirs": {d: v["count"] for d, v in dirs}},
                      f, ensure_ascii=False, indent=1)
        print("# 写 %s" % args.json)
    return 0


def _fixture_img(version, records, bodies=b""):
    """拼一个最小 IMG：records = [("ref", target) | ("plain", w, h)]，bodies 串联。"""
    out = P.IMG_MAGIC + b"\x00" * 8 + version.to_bytes(4, "little") \
        + len(records).to_bytes(4, "little")
    for rec in records:
        if rec[0] == "ref":
            out += P.T_REFERENCE.to_bytes(4, "little") + rec[1].to_bytes(4, "little")
        else:
            _, w, h = rec
            out += P.T_ARGB8888.to_bytes(4, "little") + P.C_ZLIB.to_bytes(4, "little")
            out += w.to_bytes(4, "little") + h.to_bytes(4, "little")
            out += (0).to_bytes(4, "little") * 3          # length 占位，下面改写
            out += w.to_bytes(4, "little") + h.to_bytes(4, "little")
    # 简化：不做 length 回填，环用例全是 ref 帧，不需要帧体
    return out + bodies


def cmd_cycledemo(args):
    """环检测自证：三种环 + 一条正常链，跑 raise / degrade / 打包三条路。

    语料实测 0 环（41,411 张 img），没法拿真实样本抽查，所以这里用构造的 img
    证明「检测得到、降级不崩」。
    """
    cases = [
        ("self_loop", [("ref", 0)]),
        ("two_cycle", [("ref", 1), ("ref", 0)]),
        ("three_cycle", [("ref", 1), ("ref", 2), ("ref", 0)]),
    ]
    bad = 0
    for name, recs in cases:
        blob = _fixture_img(2, recs)
        try:
            P.Img(blob)
            print("%-12s raise   -> !! 未检测到环" % name)
            bad += 1
        except P.NpkError as ex:
            print("%-12s raise   -> %s" % (name, ex))
        d = P.Img(blob, cycle_policy="degrade")
        pages, rects, size = ImagePacker().pack(d, name)
        empties = sum(1 for r in rects if r["empty"])
        print("%-12s degrade -> cycles=%d resolved=%s | 打包：%d 矩形、%d 空帧、%d 页"
              % ("", len(d.cycles), d.resolved, len(rects), empties, len(pages)))
        if not d.cycles or empties != len(recs) or pages:
            print("             !! 降级不符合预期")
            bad += 1
    # 正常链对照：0 -> 1 -> 2(实体 4x4)
    payload = zlib.compress(bytes([200, 30, 30, 255]) * 16, 6)
    blob = bytearray(P.IMG_MAGIC + b"\x00" * 8 + (2).to_bytes(4, "little")
                     + (3).to_bytes(4, "little"))
    blob += P.T_REFERENCE.to_bytes(4, "little") + (1).to_bytes(4, "little")
    blob += P.T_REFERENCE.to_bytes(4, "little") + (2).to_bytes(4, "little")
    blob += P.T_ARGB8888.to_bytes(4, "little") + P.C_ZLIB.to_bytes(4, "little")
    blob += (4).to_bytes(4, "little") * 2 + len(payload).to_bytes(4, "little")
    blob += (0).to_bytes(4, "little") * 2 + (4).to_bytes(4, "little") * 2 + payload
    d = P.Img(bytes(blob), cycle_policy="degrade")
    print("%-12s chain_ok -> cycles=%d resolved=%s" % ("", len(d.cycles), d.resolved))
    if d.cycles or d.resolved != [2, 2, 2]:
        print("             !! 正常链解析错误")
        bad += 1
    print("# 环检测自证：%s" % ("通过（3/3 环捕获、降级为空帧）" if bad == 0 else "%d 项失败" % bad))
    return 0 if bad == 0 else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="NPK/IMG -> 图集（2048 页 + 矩形表）")
    ap.add_argument("--pack-dir", default=DEFAULT_PACK_DIR)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("build", help="按清单打包图集")
    p.add_argument("--manifest", default=DEFAULT_MANIFEST, help="t12 的切片清单")
    p.add_argument("--img-list", default=None,
                   help="换成自定义清单：每行 <npk>\\t<img 路径> 或 <img 路径>")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--page-size", type=int, default=PAGE_SIZE)
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--adaptive", action="store_true",
                   help="按内容面积自适应缩小页尺寸（省显存；默认固定 2048）")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("check", help="四个根抽样解码成功率")
    p.add_argument("--n", type=int, default=200)
    p.add_argument("--roots", nargs="*",
                   default=["monster", "character", "equipment", "map"])
    p.add_argument("--seed", type=int, default=20261026)
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("stats", help="按 manifest 统计页数/体积/格式分布")
    p.add_argument("--manifest-out", default=os.path.join(DEFAULT_OUT, "manifest.jsonl"))
    p.add_argument("--rects-out", default=os.path.join(DEFAULT_OUT, "rects.jsonl"))
    p.set_defaults(func=cmd_stats)

    p = sub.add_parser("verify", help="回读 manifest/rects/页 PNG 做一致性校验")
    p.add_argument("--out", default=DEFAULT_OUT)
    p.add_argument("--manifest-out", default=os.path.join(DEFAULT_OUT, "manifest.jsonl"))
    p.add_argument("--rects-out", default=os.path.join(DEFAULT_OUT, "rects.jsonl"))
    p.add_argument("--sample", type=int, default=0)
    p.set_defaults(func=cmd_verify)

    p = sub.add_parser("cycledemo", help="环检测自证（语料 0 环，用构造 img 验证）")
    p.set_defaults(func=cmd_cycledemo)

    p = sub.add_parser("batch", help="12 只怪 + 技能特效这一小批的页数/体积")
    p.add_argument("--monsters", type=int, default=12)
    p.add_argument("--skills", type=int, default=20)
    p.add_argument("--out", default=os.path.join(
        tempfile.gettempdir(), "npk_atlas_batch"),
        help="小批实测的落盘目录（默认临时目录，别污染 export/atlas）")
    p.add_argument("--page-size", type=int, default=PAGE_SIZE)
    p.add_argument("--per-dir", type=int, default=6,
                   help="每个怪物目录最多收录多少个 img（控制扫描量）")
    p.add_argument("--json", default=None)
    p.add_argument("--adaptive", action="store_true")
    p.set_defaults(func=cmd_batch)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
