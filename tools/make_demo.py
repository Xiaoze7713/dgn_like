#!/usr/bin/env python3
"""从 PVF + ImagePacks2 里抽一份「鬼剑士 + 哥布林 + 格兰之森」的开发素材包。

    python3 tools/make_demo.py plan          # 只统计会抽多少东西
    python3 tools/make_demo.py index         # 建 img -> npk 索引（缓存）
    python3 tools/make_demo.py extract       # 抽 PVF 条目 + PNG
    python3 tools/make_demo.py readme        # 生成 README/manifest

输出目录：dnf_demo/
    pvf/      原始 PVF 条目（保持原路径，二进制原样）
    text/     可读文本（.act/.ani/.chr/.nut/.lua/...，由 pvf_unpack 解码）
    img/      从 NPK 解出来的 PNG（路径同 img 原名，每帧一个文件）
    manifest.csv / README.md
"""
import argparse
import csv
import json
import os
import posixpath
import shutil
import sqlite3
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

PVF = "/mnt/e/dnf-sf/sf115/Script.pvf"
PVF_ALT = "/mnt/e/dnf-sf/sf110.08/客户端/客户端神话8.0/Script.pvf"   # 中文名完好
PACKS = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"
DB = os.path.join(HERE, "..", "analysis", "pvf", "graph.sqlite")
OUT = os.path.join(HERE, "..", "dnf_demo")
IDX = os.path.join(HERE, "..", "analysis", "pvf", "reports", "img-index.json")

SEEDS = {
    "swordman": [
        "character/swordman/",
        "skill/swordmanskill.lst",
    ],
    "goblin": [
        "monster/goblin/",
        "monster/newmonsters/goblin/",
    ],
    "granfloris": [
        "dungeon/act1/",
        "map/elvengard/",
        "map/mirkwood/",
        "map/mirkwooddeep/",
        "map/sunderland/",
        "map/sunderlanddark/",
        "map/sunderlandpoison/",
        "map/grakkarak/",
        "map/grakkarakburning/",
        "passiveobject/mapobject/pathgate/act1/",
        "passiveobject/mapobject/act1/",
    ],
}
# 允许 join 的边（.nut/.lua 里的引用不建边，跳过）
FOLLOW = {"path", "img", "id"}


def dbc():
    db = sqlite3.connect(DB)
    db.execute("pragma temp_store=MEMORY")
    return db


def plan(verbose=True):
    db = dbc()
    q = lambda s, *a: db.execute(s, a).fetchall()
    found = {}          # path -> group
    frontier = {}       # path -> group
    for group, prefixes in SEEDS.items():
        for p in prefixes:
            if p.endswith("/"):
                rows = q("select path from node where path like ?", p + "%")
            else:
                rows = q("select path from node where path=?", p)
            for (path,) in rows:
                if path not in found:
                    found[path] = group
                    frontier[path] = group
    print(f"种子 {len(found):,} 个节点")
    depth = 0
    while frontier:
        depth += 1
        if depth > 3:
            break
        keys = list(frontier)
        new = {}
        for i in range(0, len(keys), 400):
            batch = keys[i:i + 400]
            marks = ",".join("?" * len(batch))
            rows = q(f"select src, dst, kind from edge where src in ({marks})", *batch)
            for src, dst, kind in rows:
                if kind not in FOLLOW:
                    continue
                if dst in found or dst in new:
                    continue
                new[dst] = frontier[src]
        print(f"  +{depth} 跳: +{len(new):,} → 累计 {len(found) + len(new):,}")
        found.update(new)
        frontier = new
    pvf = {p: g for p, g in found.items() if not p.endswith((".img", ".wav", ".ogg", ".png"))}
    img = sorted(p for p in found if p.endswith(".img"))
    print(f"\nPVF 条目 {len(pvf):,}   .img {len(img):,}")
    byext = {}
    for p in pvf:
        e = p.rsplit(".", 1)[-1] if "." in p else "(none)"
        byext[e] = byext.get(e, 0) + 1
    print("后缀:", dict(sorted(byext.items(), key=lambda x: -x[1])[:18]))
    return pvf, img


def build_index(force=False):
    if os.path.exists(IDX) and not force:
        d = json.load(open(IDX))
        print(f"复用索引 {IDX}: {len(d):,} 个 img")
        return d
    from npk_parser import Npk
    t0 = time.time()
    files = [f for f in os.listdir(PACKS) if f.lower().endswith(".npk")]
    idx = {}
    for i, fn in enumerate(files):
        try:
            npk = Npk(os.path.join(PACKS, fn))
        except Exception:
            continue
        for e in npk.entries:
            if e.name.lower().endswith(".img"):
                idx[e.name.lower()] = [fn, e.offset, e.size]
        if i % 500 == 0:
            print(f"  {i}/{len(files)}  索引 {len(idx):,}  {time.time()-t0:.0f}s", flush=True)
    json.dump(idx, open(IDX, "w"))
    print(f"索引完成 {len(idx):,} 个 img，{time.time()-t0:.0f}s -> {IDX}")
    return idx


def load_index():
    return json.load(open(IDX)) if os.path.exists(IDX) else {}


def lookup_idx(idx, p):
    """PVF 里的 img 路径不带 sprite/ 前缀，NPK 条目带 —— 两边都试"""
    for cand in (p, "sprite/" + p):
        if cand in idx:
            return cand, idx[cand]
    return None, None


def count_frames(img_paths, limit=0):
    """只读头，数帧数与体积（不解码像素）"""
    from npk_parser import Npk, Img
    idx = load_index()
    packs, tot_frames, miss = {}, 0, []
    for i, p in enumerate(img_paths):
        if limit and i >= limit:
            break
        key, rec = lookup_idx(idx, p)
        if not rec:
            miss.append(p)
            continue
        fn, off, size = rec
        try:
            n = packs.get(fn)
            if n is None:
                n = Npk(os.path.join(PACKS, fn))
                packs[fn] = n
            img = Img(n.read(key), parse_bodies=False)
            tot_frames += len(img.frames)
        except Exception as e:
            miss.append(p + "  (%s)" % e)
        if i % 500 == 0:
            print(f"  {i:,}/{len(img_paths):,} 帧 {tot_frames:,}  {len(packs)} 包", flush=True)
    print(f"共 {len(img_paths)-len(miss):,} 个 img，帧数 {tot_frames:,}，缺失 {len(miss):,}")
    for m in miss[:10]:
        print("   miss:", m)
    return tot_frames, miss


def extract(pvf_path, limit_img=0, frame_limit=0, text_only=False):
    from pvf_unpack import PvfArchive, parse_document, parse_animation, animation_to_text
    pvf_paths, img_paths = plan(verbose=False)
    os.makedirs(OUT, exist_ok=True)
    idx = load_index()
    from npk_parser import Npk, Img, write_png

    # ---- 1. PVF ----
    t0 = time.time()
    ar = PvfArchive(pvf_path)
    ar.load_strings()
    n_pvf = 0
    rows = []
    for i, p in enumerate(sorted(pvf_paths)):
        try:
            e = ar.entry(p)
            raw = ar.read_raw(e)
        except Exception as ex:
            rows.append([p, "MISS", "", str(ex)])
            continue
        dst = os.path.join(OUT, "pvf", p.replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, "wb").write(raw)
        n_pvf += 1
        # 文本版本
        try:
            low = p.lower()
            if low.endswith((".nut", ".lua", ".str", ".txt", ".xml", ".cfg", ".ini")):
                tx = ar._decode_text(raw)
            elif low.endswith(".ani"):
                tx = animation_to_text(parse_animation(raw, ar.encoding))
            else:
                node = parse_document(raw, ar)
                tx = "\n".join(l for l in node.to_text())
            tp = os.path.join(OUT, "text", (p + ".txt").replace("/", os.sep))
            os.makedirs(os.path.dirname(tp), exist_ok=True)
            open(tp, "w", encoding="utf-8").write(tx)
        except Exception as ex:
            tx = None
        rows.append([p, "SIM", str(len(raw)), ""])
        if i % 2000 == 0:
            print(f"  pvf {i:,}/{len(pvf_paths):,}  {time.time()-t0:.0f}s", flush=True)
    ar.close()
    print(f"PVF 抽出 {n_pvf:,} 个条目 -> {OUT}/pvf  文本 -> {OUT}/text  {time.time()-t0:.0f}s")
    if text_only:
        return

    # ---- 2. IMG -> PNG ----
    t1 = time.time()
    packs = {}
    n_img = n_frame = n_miss = 0
    meta = {}
    for i, p in enumerate(img_paths):
        if limit_img and i >= limit_img:
            break
        key, rec = lookup_idx(idx, p)
        if not rec:
            n_miss += 1
            continue
        fn, off, size = rec
        try:
            n = packs.get(fn)
            if n is None:
                if len(packs) > 24:
                    packs.clear()
                n = Npk(os.path.join(PACKS, fn))
                packs[fn] = n
            img = Img(n.read(key))
        except Exception as ex:
            n_miss += 1
            rows.append([p, "IMG-ERR", "", str(ex)])
            continue
        base = p[:-4] if p.lower().endswith(".img") else p
        d = os.path.join(OUT, "img", base.replace("/", os.sep))
        os.makedirs(d, exist_ok=True)
        frames = []
        for fi in range(len(img.frames)):
            if frame_limit and fi >= frame_limit:
                break
            try:
                w, h, x, y, px = img.frame_image(fi)
            except Exception as ex:
                continue
            fp = os.path.join(d, "%04d.png" % fi)
            write_png(fp, w, h, px)
            fr_ = img.frames[fi]
            frames.append({"i": fi, "w": w, "h": h, "x": x, "y": y,
                           "cw": fr_.frame_width, "ch": fr_.frame_height})
            n_frame += 1
        meta[p] = {"pack": fn, "frames": frames}
        n_img += 1
        if i % 100 == 0:
            print(f"  img {i:,}/{len(img_paths):,}  png {n_frame:,}  {time.time()-t1:.0f}s", flush=True)
    json.dump(meta, open(os.path.join(OUT, "img-meta.json"), "w"), ensure_ascii=False)
    print(f"IMG 抽出 {n_img:,} 个 / {n_frame:,} 帧，缺 {n_miss:,}  {time.time()-t1:.0f}s")

    # ---- 3. manifest ----
    with open(os.path.join(OUT, "manifest.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["path", "group", "kind", "size", "note"])
        for p in sorted(pvf_paths):
            w.writerow([p, pvf_paths[p], "pvf", "", ""])
        for p in img_paths:
            w.writerow([p, "", "img", "", "png=" + str(len(meta.get(p, {}).get("frames", [])))])
    print("manifest ->", os.path.join(OUT, "manifest.csv"))


def extract_imgs(img_paths, frame_limit=0):
    from npk_parser import Npk, Img, write_png
    idx = load_index()
    packs = {}
    n_img = n_frame = n_miss = 0
    meta_path = os.path.join(OUT, "img-meta.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for i, p in enumerate(img_paths):
        key, rec = lookup_idx(idx, p)
        if not rec:
            n_miss += 1
            continue
        fn, off, size = rec
        try:
            npk = packs.get(fn)
            if npk is None:
                if len(packs) > 24:
                    packs.clear()
                npk = Npk(os.path.join(PACKS, fn))
                packs[fn] = npk
            img = Img(npk.read(key))
        except Exception:
            n_miss += 1
            continue
        base = p[:-4] if p.lower().endswith(".img") else p
        d = os.path.join(OUT, "img", base.replace("/", os.sep))
        os.makedirs(d, exist_ok=True)
        frames = []
        for fi in range(len(img.frames)):
            if frame_limit and fi >= frame_limit:
                break
            try:
                w, h, x, y, px = img.frame_image(fi)
            except Exception:
                continue
            write_png(os.path.join(d, "%04d.png" % fi), w, h, px)
            fr_ = img.frames[fi]
            frames.append({"i": fi, "w": w, "h": h, "x": x, "y": y,
                           "cw": fr_.frame_width, "ch": fr_.frame_height})
            n_frame += 1
        meta[p] = {"pack": fn, "frames": frames}
        n_img += 1
        if i % 200 == 0:
            print(f"  img {i:,}/{len(img_paths):,}  png {n_frame:,}", flush=True)
    json.dump(meta, open(meta_path, "w"), ensure_ascii=False)
    print(f"IMG {n_img:,} 个 / {n_frame:,} 帧，缺 {n_miss:,}")


def bind():
    """把 .ani 解析成「每帧用哪张图、图里第几帧」的 JSON。

    规则（来自官方注释 `[IMAGE] <路径> <帧编号>`）：
      - 路径不含 %  → img = 路径，frame = IMG_PARAM（图内帧号）
      - 路径含 %04d  → %04d 是「外观 id」（由装备/换装决定，.ani 里没有），
                       frame 仍是 IMG_PARAM。演示包固定用「帧数最全的那张外观」，
                       本客户端 = sm_body0180.img（243 帧，正好覆盖 0..242 的所有帧号）。
    """
    from pvf_unpack import PvfArchive, parse_animation
    pvf_paths, img_paths = plan(verbose=False)
    anis = sorted(p for p in pvf_paths if p.endswith(".ani"))
    print(f".ani {len(anis):,} 个")
    os.makedirs(os.path.join(OUT, "anim"), exist_ok=True)

    meta = json.load(open(os.path.join(OUT, "img-meta.json"))) if os.path.exists(os.path.join(OUT, "img-meta.json")) else {}
    # 「目录 -> 帧数最多的具体文件」：给 %04d 这类模板路径挑一张能覆盖所有帧号的外观
    by_dir = {}
    for img, info in meta.items():
        d = img.rsplit("/", 1)[0]
        n = len(info.get("frames") or [])
        if d not in by_dir or n > by_dir[d][1]:
            by_dir[d] = (img, n)

    ar = PvfArchive(PVF)
    ar.load_strings()
    index = {}
    n = 0
    n_pat = n_frame_fallback = 0
    for i, p in enumerate(anis):
        try:
            a = parse_animation(ar.read_raw(ar.entry(p)), ar.encoding)
        except Exception:
            continue
        sprites = a.get("sprites") or []
        frames = []
        for fr in a.get("frames") or []:
            iid = fr.get("img_id", 0)
            param = fr.get("img_param")
            pat = sprites[iid] if 0 <= iid < len(sprites) else None
            img = pat
            frame_no = param if isinstance(param, int) else 0
            if pat and "%" in pat:
                n_pat += 1
                d = pat.rsplit("/", 1)[0]
                cand = by_dir.get(d)          # 同目录里帧数最多的那张外观
                img = cand[0] if cand else None
                if img and frame_no >= len((meta.get(img) or {}).get("frames") or []):
                    n_frame_fallback += 1
            elif pat and pat not in meta:
                img = None
            boxes = []
            for kind, dims in (("attack", fr.get("attack_box")), ("damage", fr.get("damage_box"))):
                for b in (dims or []):
                    boxes.append({"kind": kind, "box": b})
            fi = (meta.get(img) or {}).get("frames") or []
            it = fi[frame_no] if 0 <= frame_no < len(fi) else {}
            ix, iy = it.get("x", 0), it.get("y", 0)
            ax, ay = fr.get("x", 0), fr.get("y", 0)
            frames.append({
                "img": img,
                "frame": frame_no,
                # 画布左上角 = (x, y)；PNG 是画布里 (ix, iy) 处的 w*h 裁剪
                "x": ax, "y": ay,
                "ix": ix, "iy": iy,
                "cw": it.get("cw", 0), "ch": it.get("ch", 0),
                "w": it.get("w", 0), "h": it.get("h", 0),
                # 直接把 PNG 画在 (draw_x, draw_y) 即对齐（y 轴朝下）
                "draw_x": ax + ix, "draw_y": ay + iy,
                "delay": fr.get("delay", 0),
                "boxes": boxes,
            })
        index[p] = {"frames": len(frames), "sprites": sprites}
        dst = os.path.join(OUT, "anim", (p[:-4] + ".json").replace("/", os.sep))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        name = os.path.basename(p)[:-4]
        json.dump({"name": name, "path": p, "frames": frames},
                  open(dst, "w", encoding="utf-8"), ensure_ascii=False)
        n += 1
        if i % 3000 == 0:
            print(f"  {i:,}/{len(anis):,}  %04d 帧 {n_pat:,}  回退 {n_frame_fallback:,}", flush=True)
    ar.close()
    print(f"anim JSON {n:,} 个；%04d 帧 {n_pat:,}；帧号越界回退 {n_frame_fallback:,}")


def readme():
    """按实际导出结果生成 README.md"""
    pvf_root = os.path.join(OUT, "pvf")
    txt_root = os.path.join(OUT, "text")
    img_root = os.path.join(OUT, "img")
    n_pvf = n_txt = n_png = 0
    ext = {}
    img_dirs = 0
    for root, dirs, files in os.walk(pvf_root):
        for f in files:
            n_pvf += 1
            e = f.rsplit(".", 1)[-1] if "." in f else "(none)"
            ext[e] = ext.get(e, 0) + 1
    for root, dirs, files in os.walk(txt_root):
        n_txt += len(files)
    for root, dirs, files in os.walk(img_root):
        if files:
            img_dirs += 1
            for f in files:
                if f.endswith(".png"):
                    n_png += 1
    size = 0
    for root, dirs, files in os.walk(OUT):
        for f in files:
            try:
                size += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    anim_root = os.path.join(OUT, "anim")
    n_anim = 0
    for root, dirs, files in os.walk(anim_root):
        n_anim += sum(1 for f in files if f.endswith(".json"))
    meta = json.load(open(os.path.join(OUT, "img-meta.json"))) if os.path.exists(os.path.join(OUT, "img-meta.json")) else {}
    frames_total = sum(len(v.get("frames", [])) for v in meta.values())
    tops = sorted(ext.items(), key=lambda x: -x[1])[:14]

    L = []
    A = L.append
    A("# dnf_demo —— 鬼剑士 / 哥布林 / 格兰之森 开发素材包\n")
    A("从 `sf115/Script.pvf`（1,460,792 条目）与 `ImagePacks2`（4,730 个 NPK）里，")
    A("按依赖图抽出这三块内容的**闭包**，解码成可直接用的文件。\n")
    A("## 规模\n")
    A("| 内容 | 数量 |")
    A("| --- | --- |")
    A(f"| PVF 原始条目 `pvf/` | **{n_pvf:,}** |")
    A(f"| 解码文本 `text/` | **{n_txt:,}** |")
    A(f"| 图片 `img/` | **{img_dirs:,} 个 img / {n_png:,} 帧 PNG** |")
    A(f"| 动画 `anim/` | **{n_anim:,} 个 .ani 的逐帧 JSON** |")
    A(f"| 总大小 | **{size/1e9:.2f} GB**（{n_png:,} 个小 PNG 占磁盘 1.7 GB） |")
    A(f"| 缺图（索引里没有/私服删过） | 294 + 313 个 |")
    A("")
    A("按类型：" + "、".join(f"`.{k}` {v:,}" for k, v in tops))
    A("")
    A("## 目录\n")
    A("```")
    A("dnf_demo/")
    A("├── pvf/        原始 PVF 条目（路径与 PVF 内一致，二进制原样，可用 tools/pvf_unpack.py 再解）")
    A("├── text/       同一路径 + .txt：.act/.ani/.chr/.mob/.equ/.skl/.nut/.lua 的可读形式")
    A("├── img/        从 NPK 解出的 PNG，每帧一个文件：img/<img 路径>/<帧号 4 位>.png")
    A("├── anim/       每个 .ani 一份 JSON：每帧用哪张图、图里第几帧、偏移、延迟、碰撞盒")
    A("├── original/   原始 NPK（保留未解包的原文件，方便对照格式）")
    if os.path.isdir(os.path.join(OUT, "avatar")):
        A("├── avatar/     装备/时装分层：<部件>/<动作>.json + layers.json（见下）")
    A("├── img-meta.json   每个 img 的帧表：{img: {pack, frames:[{i,w,h,x,y,cw,ch}]}}（x,y 是内容在画布里的位置，cw,ch 画布大小）")
    A("├── manifest.csv    全量清单：path, group, kind")
    A("├── missing-imgs.txt 607 张取不到的图（601 张本档没有、6 张解码失败）")
    A("└── README.md")
    A("```\n")
    A("## 三块内容各自是什么\n")
    A("| group | 内容 | 对应原路径 |")
    A("| --- | --- | --- |")
    A("| `swordman` | 鬼剑士：`swordman.chr` + 全部动作/特效动画 + 技能表 `skill/swordmanskill.lst`（244 条） | `character/swordman/**`, `skill/swordman*` |")
    A("| `goblin` | 哥布林：`.mob` 定义 + `.ai` 脚本 + 动作 `.act` + 攻击载荷 `.atk` + 动画 | `monster/goblin/**`, `monster/newmonsters/goblin/**` |")
    A("| `granfloris` | 格兰之森（Elvengard）：`dungeon/act1/*.dgn`（洛兰/幽暗密林/……）+ 地图 `.map` + 图块 `.til` + 传送门机关 | `dungeon/act1/**`, `map/{elvengard,mirkwood,sunderland,grakkarak}/**` |")
    A("")
    A("## 怎么用（Godot 4.7）\n")
    A("1. **动画直接看 `anim/`**：`anim/character/swordman/animation/move.json` 里每帧给出")
    A("   `img`（贴图）、**`frame`（这张图里的第几帧）**、**`draw_x,draw_y`（PNG 左上角的场景坐标）**、")
    A("   `delay`（毫秒）、`boxes`（attack/damage 碰撞盒六元组）。")
    A("   加载 = `img/<img 去掉 .img>/<frame:04d>.png` **画在 `(draw_x, draw_y)`**，按 `delay` 切帧。")
    A("")
    A("   > **`.ani` 的两个字段别搞混**：`imgId` 是「贴图路径表的下标」，`imgParam` 是「**图内帧号**」。")
    A("   > 官方注释写作 `[IMAGE] <路径> <帧编号>`。把 `imgParam` 当文件编号会解出 10 个不同职业的裸体。")
    A("   > 路径里的 `%04d` 是**外观 id**（由装备决定，`.ani` 里没有），本包固定解析到 `sm_body0180.img`")
    A("   > （该目录帧数最全的一张，243 帧，覆盖 0..242 全部帧号）。")
    A("")
    A("   > **`draw_x/draw_y` 是怎么来的（y 对齐的关键）**：每张 `.img` 的帧内容不是铺满画布，")
    A("   > 而是贴在 `frameWidth×frameHeight`（常见 500×500）画布的 `(ix, iy)` 处；`.ani` 的 `x,y` 给的是")
    A("   > **画布左上角**。所以 `draw_x = x + ix`、`draw_y = y + iy`。只按 `x,y` 摆 PNG（忽略 `ix,iy`）")
    A("   > 会让内容底边逐帧跳动 20~34px —— 这就是之前人物 y 轴没对齐的原因。JSON 里 `ix,iy,cw,ch,w,h`")
    A("   > 都保留了，需要按画布中心/底部对齐时可以自己换算。")
    A("2. **PNG 也可以直接用**：`img/<img 路径>/<帧号 4 位>.png`，文件名就是帧号。")
    A("3. **帧的偏移在 `img-meta.json`**：每帧有 `x,y`（DNF 的绘制原点偏移），宽的画布要按 `w,h` 摆，")
    A("   不要把 PNG 直接居中对齐——DNF 是「帧图 + (x,y) 偏移」绘制的。")
    A("4. **人读的动画顺序看 `text/*.ani.txt`**：`[FRAME0000]` 段里有 `IMAGE`（对应 img 路径）、`POS`（x,y）、")
    A("   `ATTACK BOX`（碰撞盒六元组 x y z w h d）、`DELAY`（毫秒）。")
    A("5. **行为看 `.act`**：`[motion]`/`[base ani]`/`[sub ani]`/`[speech]`/`[sound]`，一个 `.act` 就是一段动作编排。")
    A("6. **数值看 `.atk`**（哥布林 602 个攻击载荷）和 `.chr`（鬼剑士基础属性：hp 180 / mp 140 / move speed 1350…）。")
    A("7. **AI 看 `.ai` + `text/**/*.lua.txt`**（怪物 AI 是 Lua，`Patrol:isTargetAttackArea(...)` 这类接口）。")
    A("8. **名字/数值都在 `text/` 里**：`.chr` 是职业基础属性（hp 180 / mp 140 / move speed 1350…），")
    A("   `.mob` 是怪物属性，`.atk` 是每次攻击的伤害载荷（元素、状态、加成），`.skl` 是技能定义。")
    A("")
    A("## 预览（验证用）\n")
    A("| 文件 | 内容 |")
    A("| --- | --- |")
    A("| `preview_swordman_move.png` | 鬼剑士走路 8 帧（`sm_body0180` 的 180..187 帧） |")
    A("| `preview_swordman_attack1.png` | 鬼剑士普攻 10 帧（同一张图的 0..9 帧，动作连贯） |")
    A("| `preview_goblin_attack1.png` | 哥布林挥击 5 帧（`monster/goblin/body2.img` 的 0..4 帧） |")
    A("")
    A("## 已知缺口\n")
    A("1. **607 张图取不到**（清单见 `missing-imgs.txt`）：601 张本档 NPK 里根本没有")
    A("   （私服删改过的特效，如 `atswoedmaneffect/...`、`character/challenge2nd/...`），6 张读到了但解码失败。")
    A("   对应动画帧会缺图，Godot 侧按 1×1 透明占位处理即可。")
    A("2. **中文是繁体（big5）且可用**：`.chr/.mob/.skl/.act` 里的名字能正常读（如 `極詣·劍影 / 劍神 / 大將尹埃`）。")
    A("   例外是独立语言表 `character/*.chn.str`（ID→显示名的外部映射）在 sf115 已被写成 U+FFFD，")
    A("   所以「按 ID 反查名字」这条路暂时没数据，但文档内嵌的名字不受影响。")
    A("3. **`.nut`（Squirrel 技能逻辑）已原样导出**，但没转成可执行/GDScript；`.lua` 同理。")
    A("4. **外观 id 是运行时决定的**：`%04d` 模板（`sm_body%04d.img` 等）到底用哪张，取决于角色身上穿的装备/时装；")
    A("   `.ani` 里只存了帧号。本包用一个固定外观（帧数最全的那张）先把动作跑通，接装备系统时再按真实 look id 替换。")
    A("5. **时装只导了「一套默认外观」的 8 个部件**（见下面 `avatar/` 一节）：`.equ` 物品定义、")
    A("   武器层、`.lay` 的层级/偏移表、皮肤色号（`sm_bodyXXXX`）都还没进来，换装/换武器要再补。")
    A("6. **没导出**：音效（在 `SoundPacks/*.npk` 的 ogg，本包含引用但未解出）、字体、UI 全图。")
    A("")
    if os.path.isdir(os.path.join(OUT, "avatar")):
        npart = len([d for d in os.listdir(os.path.join(OUT, "avatar"))
                     if os.path.isdir(os.path.join(OUT, "avatar", d))])
        A("## 装备/时装分层（`avatar/`）\n")
        A("`avatar/<part>/<motion>.json`（%d 个部件 × 22 个动作）+ `avatar/layers.json`。\n" % npart)
        A("```json")
        A('// layers.json')
        A('{"job":"swordman","order":["pants","shoes","belt","coat","neck","face","hair","cap"],')
        A(' "sheets":{"coat":"sprite/.../sm_coat0000a.img", ...}, "body":"sprite/.../sm_body0001.img"}')
        A('// avatar/coat/stay.json 一帧')
        A('{"img":".../sm_coat0000a.img","frame":90,"x":-232,"y":-333,')
        A(' "draw_x":-11,"draw_y":-95,"delay":100}')
        A("```")
        A("画法：body 先画，再按 `order` 顺序把 8 个部件画在各自 `(draw_x, draw_y)` 上。")
        A("")
        A("> ⚠️ **体型档必须一致**：`sm_body0001`（内容约 64×106）配 `a` 后缀时装才对得上；")
        A("> `sm_body0180`（147×187）是放大版活动皮肤，叠上去会出现「大身体 + 小时装」。")
        A("> 三张对比图：`preview_avatar_stay_sm_body0001.png`（对）/`_sm_body0180.png`（错）。")
        A("")
    A("## 复现\n")
    A("```bash")
    A("python3 tools/make_demo.py index     # 建 img -> NPK 索引（43 秒）")
    A("python3 tools/make_demo.py plan      # 看闭包规模")
    A("python3 tools/make_demo.py extract      # 导出 PVF+IMG（约 4 分钟）")
    A("python3 tools/make_demo.py bind         # .ani -> anim/*.json")
    A("python3 tools/make_demo.py extract-extra  # 补导 %04d 展开出的图")
    A("```")
    open(os.path.join(OUT, "README.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("README ->", os.path.join(OUT, "README.md"))
    print(f"pvf={n_pvf:,} txt={n_txt:,} img={img_dirs:,} png={n_png:,} size={size/1e6:.0f}MB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stage", choices=["plan", "index", "count", "extract", "bind", "extract-extra", "readme"])
    ap.add_argument("--limit-img", type=int, default=0)
    ap.add_argument("--frames", type=str, default="all")
    ap.add_argument("--text-only", action="store_true")
    a = ap.parse_args()
    if a.stage == "plan":
        plan()
    elif a.stage == "index":
        build_index(force=True)
    elif a.stage == "count":
        _, img = plan(verbose=False)
        count_frames(img, a.limit_img)
    elif a.stage == "extract":
        extract(PVF, a.limit_img, a.frames if isinstance(a.frames, int) else 0, getattr(a, "text_only", False))
    elif a.stage == "bind":
        bind()
    elif a.stage == "extract-extra":
        extra = json.load(open(os.path.join(OUT, "extra-imgs.json")))["new_imgs"]
        extract_imgs(extra)
    elif a.stage == "readme":
        readme()


if __name__ == "__main__":
    main()
