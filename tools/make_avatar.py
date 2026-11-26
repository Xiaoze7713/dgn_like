#!/usr/bin/env python3
"""导出鬼剑士的「装备/时装分层」（avatar layer），用来给 dnf_demo 里的身体穿衣服。

背景（本轮实测结论）：
  - `equipment/character/swordman/avatar/<part>/<part>_a/<motion>.ani` 是**每个部件**的动画，
    里面引用的贴图是模板 `character/swordman/equipment/avatar/<part>/sm_<part>%02d%02da.img`
    —— 两个 %02d 是「这件时装在图集里的编号」，由身上穿的装备决定，.ani 里没有。
  - 帧号仍然是 `IMG_PARAM`（同 PVF-FORMAT-BYTES §5.0 的结论）。
  - 8 个部件（coat/cap/hair/pants/shoes/belt/face/neck）都用同一套动作名、同一个 POS，
    所以只要给每个部件挑一张 `sm_<part>NNNNa.img`（≥188 帧）就能对齐合成。

用法：
  python3 tools/make_avatar.py export     # 导出部件动画 JSON + 图集 PNG
  python3 tools/make_avatar.py preview    # 合成预览图（stay / attack1）
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_unpack import PvfArchive, parse_animation, parse_document, decode_entry  # noqa: E402
from npk_parser import Npk, Img, write_png  # noqa: E402

PVF = "/mnt/e/dnf-sf/sf115/Script.pvf"
PACKS = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "dnf_demo")
META = os.path.join(OUT, "img-meta.json")
INDEX = os.path.join(ROOT, "analysis/pvf/reports/img-index.json")

JOB = "swordman"
# 身体图必须和时装图集同一"体型档"：sm_body0001（官方皮肤，内容 ~64×106）才和 a 后缀时装配得上；
# sm_body0180（活动包，内容 ~147×187）是放大版，叠 a 后缀时装会变成"大身体 + 小时装"。
BODY = "character/swordman/equipment/avatar/skin/sm_body0001.img"
PARTS = ["pants", "shoes", "belt", "coat", "neck", "face", "hair", "cap"]  # 从下往上
MOTIONS = ["stay", "move", "attack1", "attack2", "attack3", "attack4", "damage1",
           "damage2", "down", "overturn", "jump", "jumpattack", "dash", "dashattack",
           "guard", "sit", "rest", "getitem", "hitback", "throw1", "throw2",
           "summon1", "summon2"]


idx_global = {}


def load_index():
    global idx_global
    with open(INDEX, encoding="utf-8") as f:
        idx_global = json.load(f)
    return idx_global


def _sheet_score(path, packs):
    """返回 (帧数, 平均内容面积)；用于挑「画得最完整」的那张图集。"""
    rec = idx_global.get(path)
    if not rec:
        return 0, 0
    fn, off, size = rec
    n = packs.get(fn)
    if n is None:
        n = Npk(os.path.join(PACKS, fn))
        packs[fn] = n
    try:
        img = Img(n.read(path))
    except Exception:
        return 0, 0
    area = 0
    for fr in img.frames:
        area += fr.width * fr.height
    return len(img.frames), area / max(1, len(img.frames))


def choose_sheets(idx, packs, scan=60):
    """每个部件从候选图集里挑「帧数够 + 平均画幅最大」的一张。

    为什么不是按编号挑：同一 part 下 `sm_coat0000a` 可能是「领子/肩甲」这种小件，
    `sm_coat0703a` 才是整件大衣。按平均内容面积挑能稳定选到完整服装。
    """
    import re
    out = {}
    for part in PARTS:
        pat = re.compile(r"/avatar/%s/sm_%s(\d{4})a\.img$" % (part, part))
        cands = sorted(p for p in idx if pat.search(p))[:scan]
        scored = []
        for p in cands:
            fc, area = _sheet_score(p, packs)
            if fc >= 188:
                scored.append((area, fc, p))
        if not scored:
            # 放宽：任意 a 后缀、帧数 ≥188
            pat2 = re.compile(r"/avatar/%s/sm_%s\d{4}a\.img$" % (part, part))
            for p in sorted(x for x in idx if pat2.search(x)):
                fc, area = _sheet_score(p, packs)
                if fc >= 188:
                    scored.append((area, fc, p))
        if not scored:
            continue
        scored.sort(reverse=True)
        area, fc, best = scored[0]
        out[part] = {"img": best, "frames": fc, "area": round(area)}
    return out


def _norm(p):
    """统一去掉 `sprite/` 前缀：内存里 imag-pack 路径带，dnf_demo 里不带。"""
    return p[len("sprite/"):] if p.startswith("sprite/") else p


def export():
    idx = load_index()
    packs = {}
    meta = json.load(open(META, encoding="utf-8")) if os.path.exists(META) else {}
    sheets = choose_sheets(idx, packs)
    print("选中图集：")
    for part, info in sheets.items():
        print("  %-6s %s  (%d 帧)" % (part, info["img"], info["frames"]))

    ar = PvfArchive(PVF)
    ar.load_strings()

    # 1) 图集 -> PNG（每帧一张，和 img/ 目录同构）
    n_png = 0
    for part, info in sheets.items():
        p = info["img"]
        fn, off, size = idx[p]
        n = packs.get(fn) or Npk(os.path.join(PACKS, fn))
        packs[fn] = n
        img = Img(n.read(p))
        base = _norm(p)[:-4]
        d = os.path.join(OUT, "img", base.replace("/", os.sep))
        os.makedirs(d, exist_ok=True)
        frames = []
        for fi in range(len(img.frames)):
            try:
                w, h, x, y, px = img.frame_image(fi)
            except Exception:
                continue
            write_png(os.path.join(d, "%04d.png" % fi), w, h, px)
            fr = img.frames[fi]
            frames.append({"i": fi, "w": w, "h": h, "x": x, "y": y,
                           "cw": fr.frame_width, "ch": fr.frame_height})
            n_png += 1
        meta[base + ".img"] = {"pack": fn, "frames": frames}
    json.dump(meta, open(META, "w", encoding="utf-8"), ensure_ascii=False)
    print("图集 PNG %d 张" % n_png)

    # 2) 每个部件 × 每个动作 -> JSON
    outdir = os.path.join(OUT, "avatar")
    n_ani = 0
    for part, info in sheets.items():
        sheet = info["img"]
        sfr = (meta.get(_norm(sheet)) or {}).get("frames") or []
        for motion in MOTIONS:
            p = "equipment/character/%s/avatar/%s/%s_a/%s.ani" % (JOB, part, part, motion)
            try:
                raw = ar.read_raw(ar.entry(p))
            except Exception:
                continue
            a = parse_animation(raw, ar.encoding)
            sprites = a.get("sprites") or []
            frames = []
            for fr in a["frames"]:
                iid = fr.get("img_id", 0)
                frame_no = fr.get("img_param") or 0
                ax, ay = fr.get("x", 0), fr.get("y", 0)
                it = sfr[frame_no] if 0 <= frame_no < len(sfr) else {}
                ix, iy = it.get("x", 0), it.get("y", 0)
                frames.append({
                    "img": _norm(sheet), "frame": frame_no,
                    "x": ax, "y": ay, "ix": ix, "iy": iy,
                    "draw_x": ax + ix, "draw_y": ay + iy,
                    "delay": fr.get("delay", 0),
                    "src": sprites[iid] if 0 <= iid < len(sprites) else None,
                })
            d = os.path.join(outdir, part)
            os.makedirs(d, exist_ok=True)
            json.dump({"part": part, "motion": motion, "sheet": sheet, "frames": frames},
                      open(os.path.join(d, motion + ".json"), "w", encoding="utf-8"),
                      ensure_ascii=False)
            n_ani += 1
    ar.close()

    # 3) 分层配置
    layers = {
        "job": JOB,
        "order": PARTS,                      # 从下往上绘制
        "sheets": {p: _norm(v["img"]) for p, v in sheets.items()},
        "body": BODY,
        "body_candidates": [
            "character/swordman/equipment/avatar/skin/sm_body0001.img",
            "character/swordman/equipment/avatar/skin/sm_body0000.img",
            "character/swordman/equipment/avatar/skin/sm_body0180.img",
        ],
        "note": "同一动作的 8 个部件共用同一个 POS；按 order 顺序叠在 body 上即可。"
                "img 字段统一不带 sprite/ 前缀。"
                "body 与部件必须同体型档：0001/0000 配 a 后缀时装，0180 是放大版会错位。",
    }
    json.dump(layers, open(os.path.join(OUT, "avatar", "layers.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print("部件动作 JSON %d 个 -> %s" % (n_ani, outdir))

    # 4) 顺手导出 lay（动作模板表）与几个 .equ 样例，方便对着看物品定义
    ar2 = PvfArchive(PVF)
    ar2.load_strings()
    extra = os.path.join(outdir, "defs")
    os.makedirs(extra, exist_ok=True)
    for p2 in ["equipment/character/swordman.lay", "equipment/character/atswordman.lay"]:
        try:
            kind, txt, raw = decode_entry(ar2, ar2.entry(p2))
            open(os.path.join(extra, p2.split("/")[-1] + ".txt"), "w", encoding="utf-8").write(txt)
        except Exception as e:
            print("  lay 导出失败", p2, e)
    ar2.close()
    print("lay -> ", extra)


def preview(bodies=None):
    """把 body + 8 个部件按层的顺序合成一张动图预览。"""
    from PIL import Image

    layers = json.load(open(os.path.join(OUT, "avatar", "layers.json"), encoding="utf-8"))
    meta = json.load(open(META, encoding="utf-8"))
    bodies = bodies or [BODY, "character/swordman/equipment/avatar/skin/sm_body0000.img",
                        "character/swordman/equipment/avatar/skin/sm_body0180.img"]

    def meta_of(img):
        return meta.get("sprite/" + img) or meta.get(img)

    def png(img, fr):
        p = os.path.join(OUT, "img", img[:-4], "%04d.png" % fr)
        return Image.open(p).convert("RGBA") if os.path.exists(p) else None

    def place(img, fr, posx, posy):
        """PNG 左上角 = 画布左上角(POS) + 内容在画布里的 (x,y)。"""
        e = meta_of(img)
        f = e["frames"][fr] if e and 0 <= fr < len(e["frames"]) else None
        return posx + (f["x"] if f else 0), posy + (f["y"] if f else 0)

    for motion in ["stay", "move", "attack1"]:
        bp = os.path.join(OUT, "anim", "character/swordman/animation", motion + ".json")
        if not os.path.exists(bp):
            continue
        body = json.load(open(bp, encoding="utf-8"))["frames"]
        parts = []
        for part in layers["order"]:
            fp = os.path.join(OUT, "avatar", part, motion + ".json")
            if os.path.exists(fp):
                parts.append(json.load(open(fp, encoding="utf-8"))["frames"])
        for bimg in bodies:
            n = min([len(body)] + [len(x) for x in parts])
            tiles = []
            for i in range(n):
                items = [(bimg, body[i]["frame"], body[i]["x"], body[i]["y"])]
                for pf in parts:
                    f = pf[i]
                    items.append((f["img"], f["frame"], f["x"], f["y"]))
                L = []
                for img, fr, px, py in items:
                    im = png(img, fr)
                    if im:
                        dx, dy = place(img, fr, px, py)
                        L.append((im, dx, dy))
                if not L:
                    continue
                minx = min(x for _, x, _ in L)
                miny = min(y for _, _, y in L)
                maxx = max(x + im.width for im, x, _ in L)
                maxy = max(y + im.height for im, _, y in L)
                t = Image.new("RGBA", (maxx - minx, maxy - miny), (0, 0, 0, 0))
                for im, x, y in L:
                    t.alpha_composite(im, (x - minx, y - miny))
                tiles.append(t)
            if not tiles:
                continue
            W = max(t.width for t in tiles)
            H = max(t.height for t in tiles) + 6
            sh = Image.new("RGBA", ((W + 8) * len(tiles), H), (250, 250, 250, 255))
            for i, t in enumerate(tiles):
                sh.alpha_composite(t, (i * (W + 8) + 4, 3))
            name = "preview_avatar_%s_%s.png" % (motion, bimg.split("/")[-1][:-4])
            path = os.path.join(OUT, name)
            sh.save(path)
            print("preview ->", path, sh.size, len(tiles))


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "export"
    if cmd == "export":
        export()
    elif cmd == "preview":
        preview()
    else:
        print(__doc__)
