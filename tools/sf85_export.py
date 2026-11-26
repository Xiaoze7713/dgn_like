#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""sf85 → Godot 资产导出 + 索引。

把 PVF 里的「房间 / 角色 / 怪物」翻译成 Godot 能直接画的东西：

    房间：8 张 224×480 的地板分片 + 112×30 的通行格 + 装饰动画
    角色：皮肤/时装/武器 分层，每层若干动作，每帧 = 一张 PNG + 偏移 + 延迟
    怪物：.mob 里声明的动作（stay/move/damage/die/attack）

产物：<out>/index.json + <out>/png/*.png（PNG 按 (img,帧号) 去重）

用法：
    python3 tools/sf85_export.py --room map/mirkwood/n201.map --out /mnt/e/godot_proj/dnf_like/assets/sf85
"""
import argparse
import gzip
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import npk_parser as NPK
import pvf_unpack as PU

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PVF = os.path.join(HERE, "build/sf85.Script.utf8.pvf")
PACK = "/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2"
IDX = os.path.join(HERE, "analysis/sf85/npk-index.jsonl.gz")

JOB = "swordman"


# ---------------------------------------------------------------------------
# NPK 索引：img 路径 -> (npk, offset, size)
# ---------------------------------------------------------------------------
class Imgs(object):
    def __init__(self, index_path=IDX, pack_dir=PACK):
        self.by_path = {}
        with gzip.open(index_path, "rt", encoding="utf-8") as f:
            for line in f:
                d = json.loads(line)
                self.by_path[d["p"].lower()] = d
        self.pack_dir = pack_dir
        self._packs = {}
        self._imgs = {}

    def _pack(self, name):
        p = self._packs.get(name)
        if p is None:
            p = NPK.Npk(os.path.join(self.pack_dir, name))
            self._packs[name] = p
        return p

    def has(self, path):
        return path.lower() in self.by_path

    def open(self, path):
        key = path.lower()
        img = self._imgs.get(key)
        if img is not None:
            return img
        rec = self.by_path.get(key)
        if rec is None:
            for cand in ("sprite/" + path, path[7:] if path.lower().startswith("sprite/") else None):
                if cand and cand.lower() in self.by_path:
                    rec = self.by_path[cand.lower()]
                    break
        if rec is None:
            raise KeyError(path)
        img = self._pack(rec["npk"]).open_img(rec["p"])[0]
        self._imgs[key] = img
        return img


class Pngs(object):
    """PNG 落盘 + 去重。"""

    def __init__(self, out_dir):
        self.dir = os.path.join(out_dir, "png")
        os.makedirs(self.dir, exist_ok=True)
        self.imgs = Imgs()
        self.cache = {}
        self.n = 0

    def frame(self, img_path, index):
        key = (img_path.lower(), index)
        hit = self.cache.get(key)
        if hit:
            return hit
        img = self.imgs.open(img_path)
        w, h, x, y, rgba = img.frame_image(index)
        name = "f_%05d.png" % self.n
        self.n += 1
        NPK.write_png(os.path.join(self.dir, name), w, h, rgba)
        rec = {"png": "png/" + name, "w": w, "h": h, "ix": x, "iy": y}
        self.cache[key] = rec
        return rec

    def sheet(self, img_path, index, name):
        """整张图（房间地板用），返回 png 相对路径与尺寸。"""
        img = self.imgs.open(img_path)
        w, h, x, y, rgba = img.frame_image(index)
        os.makedirs(os.path.join(self.dir, "rooms"), exist_ok=True)
        rel = "png/rooms/%s.png" % name
        NPK.write_png(os.path.join(self.dir, "rooms", name + ".png"), w, h, rgba)
        return {"png": rel, "w": w, "h": h, "ix": x, "iy": y}


# ---------------------------------------------------------------------------
# PVF 侧
# ---------------------------------------------------------------------------
class Pvf(object):
    def __init__(self, path=PVF):
        self.ar = PU.PvfArchive(path)

    def has(self, p):
        try:
            return self.ar.entry(p) is not None
        except KeyError:
            return False

    def doc(self, p):
        e = self.ar.entry(p)
        if e is None:
            raise KeyError(p)
        return PU.decode_entry(self.ar, e)[1]

    def raw(self, p):
        e = self.ar.entry(p)
        if e is None:
            raise KeyError(p)
        return PU.decode_entry(self.ar, e)[2]


def parse_ani(raw):
    """.ani -> (frames, params)。帧字段：path/img_param(x,y,delay,boxes)"""
    a = PU.parse_animation(raw)
    frames = []
    for f in a.get("frames", []):
        boxes = []
        for b in f.get("attack_box") or []:
            boxes.append({"kind": "attack", "box": b})
        for b in f.get("damage_box") or []:
            boxes.append({"kind": "damage", "box": b})
        frames.append({
            "path": f.get("path"),
            "frame": f.get("img_param", 0),
            "x": f.get("x", 0), "y": f.get("y", 0),
            "delay": f.get("delay", 100),
            "boxes": boxes,
        })
    return frames, a.get("params", {})


def expand(tpl, look=0, color=0):
    """sm_body%04d / foo%02d%02db 之类模板 -> 具体路径"""
    n4 = tpl.count("%04d")
    n2 = tpl.count("%02d")
    if "%" not in tpl or (n4 + n2) == 0:
        return tpl
    if n4:
        return tpl.replace("%04d", "%04d" % look, 1)
    if n2 == 2:
        return tpl.replace("%02d%02d", "%02d%02d" % (look, color), 1)
    return tpl.replace("%02d", "%02d" % look, 1)


def build_anim(pngs, ani_raw, look=0, color=0):
    frames, params = parse_ani(ani_raw)
    out = []
    for f in frames:
        if not f["path"]:
            continue
        img = expand(f["path"], look, color)
        try:
            rec = pngs.frame(img, f["frame"])
        except KeyError:
            continue
        out.append({
            "png": rec["png"], "w": rec["w"], "h": rec["h"],
            "x": f["x"] + rec["ix"], "y": f["y"] + rec["iy"],
            "delay": f["delay"] or 100,
            "boxes": f["boxes"],
        })
    return {"frames": out,
            "loop": bool(params.get("loop")),
            "total_ms": sum(x["delay"] for x in out)}


# ---------------------------------------------------------------------------
# 时装（复用 make_outfit 的 .equ 解析）
# ---------------------------------------------------------------------------
DEFAULT_EQU = [
    ("skin", "equipment/character/swordman/avatar/skin/askin_default.equ"),
    ("pants", "equipment/character/swordman/avatar/pants/apants_default.equ"),
    ("shoes", "equipment/character/swordman/avatar/shoes/ashoes_default.equ"),
    ("coat", "equipment/character/swordman/avatar/coat/acoat_default.equ"),
    ("hair", "equipment/character/swordman/avatar/hair/ahair_default.equ"),
]


def equ_layers(pvf, path):
    """.equ -> [(z, look, color, sheet_tpl, ani_dir)]"""
    txt = pvf.doc(path)
    look = color = 0
    layers = []
    section = None
    for line in txt.splitlines():
        s = line.strip()
        if not s:
            continue
        if s.startswith("["):
            section = s.strip("[]").lower()
            continue
        if section == "variation":
            v = s.split()
            if len(v) >= 2 and look == 0 and color == 0:
                look, color = int(v[0]), int(v[1])
            elif len(v) >= 1 and look == 0:
                look = int(v[0])
        elif section == "layer variation":
            pass
    # 结构是「z 行 + 目录行」交替
    lines = [l.strip() for l in txt.splitlines() if l.strip()]
    try:
        i = lines.index("[layer variation]")
    except ValueError:
        i = -1
    if i >= 0:
        j = i + 1
        cur_z = None
        while j < len(lines):
            s = lines[j]
            if s.startswith("["):
                break
            if cur_z is None:
                try:
                    cur_z = int(s)
                except ValueError:
                    break
            else:
                layers.append((cur_z, s))
                cur_z = None
            j += 1
    return look, color, layers


def part_prefix(part):
    return {"skin": "body"}.get(part, part)


def actor_player(pvf, pngs, motions):
    layers_out = []
    for part, equ in DEFAULT_EQU:
        if not pvf.has(equ):
            continue
        look, color, lays = equ_layers(pvf, equ)
        if part == "skin":
            # 皮肤只有一张图集，动作来自 character/swordman/animation/
            anims = {}
            for m in motions:
                p = "character/swordman/animation/%s.ani" % m
                if pvf.has(p):
                    anims[m] = build_anim(pngs, pvf.raw(p), look, color)
            layers_out.append({"name": "skin", "z": 0, "anims": anims})
            continue
        for z, laydir in lays:
            suffix = laydir[-1] if re.search(r"_[a-z]$", laydir) else "a"
            anims = {}
            for m in motions:
                p = "equipment/character/swordman/avatar/%s/%s/%s.ani" % (part, laydir, m)
                if not pvf.has(p):
                    continue
                a = build_anim(pngs, pvf.raw(p), look, color)
                if a["frames"]:
                    anims[m] = a
            if anims:
                layers_out.append({"name": "%s_%s" % (part, laydir), "z": z, "anims": anims})
    return layers_out


# 武器图集分层（.equ 只列一层，另一层是同目录的同级目录；实测 b=刀身/650、c=刀光/2790）
WEAPON_EXTRA_Z = {"a": 640, "b": 650, "c": 2790, "d": 2800}


def actor_weapon(pvf, pngs, motions, equ_path):
    look, color, lays = equ_layers(pvf, equ_path)
    wtype = equ_path.split("/weapon/")[1].split("/")[0]
    have = set(d for _z, d in lays)
    base = lays[0][1][:-1] if lays else wtype
    for suffix, z in WEAPON_EXTRA_Z.items():
        d = base + suffix
        if d in have:
            continue
        if any(pvf.has("equipment/character/swordman/weapon/%s/%s/%s.ani" % (wtype, d, m))
               for m in motions):
            lays.append((z, d))
    out = []
    for z, laydir in lays:
        anims = {}
        for m in motions:
            p = "equipment/character/swordman/weapon/%s/%s/%s.ani" % (wtype, laydir, m)
            if not pvf.has(p):
                continue
            a = build_anim(pngs, pvf.raw(p), look, color)
            if a["frames"]:
                anims[m] = a
        if anims:
            out.append({"name": "weapon_%s" % laydir, "z": z, "anims": anims})
    return out


def actor_monster(pvf, pngs, mob_path):
    txt = pvf.doc(mob_path)
    base = os.path.dirname(mob_path)
    motions = {}
    cur = None
    for line in txt.splitlines():
        s = line.strip()
        if not s:
            continue
        m = re.match(r"^\[(.+?) motion(?: (\d))?\]$", s)
        if m:
            cur = m.group(1)
            continue
        if s.startswith("["):
            cur = None
            continue
        if cur and s.endswith(".ani"):
            motions.setdefault(cur, s)
    name = ""
    lines = txt.splitlines()
    for i, l in enumerate(lines):
        if l.strip() == "[name]":
            name = lines[i + 1].strip()
            break
    anims = {}
    for motion, rel in motions.items():
        p = base + "/" + rel
        if not pvf.has(p):
            continue
        a = build_anim(pngs, pvf.raw(p), 0, 0)
        if a["frames"]:
            anims[motion] = a
    return {"name": name,
            "layers": [{"name": "body", "z": 0, "anims": anims}]}


# ---------------------------------------------------------------------------
# 房间
# ---------------------------------------------------------------------------
def parse_map(pvf, path):
    txt = pvf.doc(path)
    lines = txt.splitlines()

    def section(name):
        out, on = [], False
        for l in lines:
            s = l.strip()
            if s == "[%s]" % name:
                on = True
                continue
            if on and s.startswith("[") and s.endswith("]") and not s.startswith("    "):
                break
            if on:
                out.append(l)
        return out

    tiles = [l.strip() for l in section("tile") if l.strip() and not l.strip().startswith("[")]
    tiles = [t for t in tiles if t.endswith(".til")]

    # [monster] 段：8 个数 + 层标签，循环
    mons = []
    try:
        i = lines.index("[monster]")
    except ValueError:
        i = -1
    if i >= 0:
        j, buf = i + 1, []
        while j < len(lines):
            s = lines[j].strip()
            if s.startswith("[") and s.endswith("]"):
                if s.lower() in ("[fixed]", "[normal]", "[bottom]", "[pass]"):
                    j += 1
                    continue
                break
            if s:
                buf.append(s)
            if len(buf) >= 8:
                try:
                    mid, cnt, _z, x, y = int(buf[0]), int(buf[1]), int(buf[2]), int(buf[3]), int(buf[4])
                    mons.append({"id": mid, "count": cnt, "x": x, "y": y})
                except ValueError:
                    pass
                buf = []
            j += 1
    return tiles, mons


def parse_bg_deco(pvf, map_path):
    """[background animation] 的远/中景 + [animation] 的装饰物"""
    base = os.path.dirname(map_path)
    lines = pvf.doc(map_path).splitlines()
    bgs, decos = [], []
    i = 0
    while i < len(lines):
        s = lines[i].strip()
        if s == "[background animation]":
            i += 1
            while i < len(lines) and lines[i].strip() != "[/background animation]":
                if lines[i].strip() in ("[ani info]",):
                    fn, layer, order = None, "", 0
                    i += 1
                    while i < len(lines) and lines[i].strip() != "[/ani info]":
                        t = lines[i].strip()
                        if t == "[filename]":
                            fn = lines[i + 1].strip()
                            i += 1
                        elif t == "[layer]":
                            layer = lines[i + 1].strip().strip("[]")
                            i += 1
                        elif t == "[order]":
                            order = lines[i + 1].strip().strip("[]")
                            i += 1
                        i += 1
                    if fn:
                        bgs.append({"ani": base + "/" + fn, "layer": layer, "order": order})
                i += 1
            continue
        if s == "[animation]":
            i += 1
            while i < len(lines):
                t = lines[i].strip()
                if t.startswith("[") and t.endswith("]") and not t.endswith(".ani"):
                    if t in ("[normal]", "[bottom]", "[pass]"):
                        break
                    break
                if t.endswith(".ani"):
                    fn = t
                    layer = lines[i + 1].strip().strip("[]")
                    try:
                        x = int(lines[i + 2].strip())
                        y = int(lines[i + 3].strip())
                        od = int(lines[i + 4].strip())
                    except (ValueError, IndexError):
                        i += 1
                        continue
                    decos.append({"ani": base + "/" + fn, "layer": layer,
                                  "x": x, "y": y, "order": od})
                    i += 5
                    continue
                i += 1
            continue
        i += 1
    return bgs, decos


def export_room(pvf, pngs, map_path, out_name, mob_table, actors):
    tiles, mons = parse_map(pvf, map_path)
    base = os.path.dirname(map_path)
    out_tiles, pass_cells = [], []
    for i, t in enumerate(tiles):
        p = base + "/" + t
        if not pvf.has(p):
            continue
        txt = pvf.doc(p)
        tl = [l.strip() for l in txt.splitlines() if l.strip()]
        img = tl[tl.index("[image]") + 1]
        frame = int(tl[tl.index("[image]") + 2])
        k = tl.index("[pass type]")
        cells = [int(x) for x in tl[k + 1:] if x.isdigit()]
        rec = pngs.sheet(img, frame, "%s_%d" % (out_name.replace("/", "_"), i))
        rec["cell_x"] = i * 224
        out_tiles.append(rec)
        pass_cells.append(cells)
    monsters = []
    for m in mons:
        mob = mob_table.get(m["id"])
        if not mob:
            continue
        key = mob
        if key not in actors:
            actors[key] = actor_monster(pvf, pngs, "monster/" + mob)
        monsters.append({"mob": key, "x": m["x"], "y": m["y"], "count": m["count"]})
    bgs, decos = parse_bg_deco(pvf, map_path)
    bg_out, deco_out = [], []
    for b in bgs:
        if not pvf.has(b["ani"]):
            continue
        key = "bg:" + os.path.basename(b["ani"])[:-4]
        if key not in actors:
            actors[key] = {"layers": [{"name": "back", "z": 0, "anims": {
                "stay": build_anim(pngs, pvf.raw(b["ani"]))}}]}
        bg_out.append({"actor": key, "layer": b["layer"], "order": b["order"]})
    for d in decos:
        if not pvf.has(d["ani"]):
            continue
        key = "deco:%s@%d,%d" % (os.path.basename(d["ani"])[:-4], d["x"], d["y"])
        if key not in actors:
            actors[key] = {"layers": [{"name": "body", "z": 0, "anims": {
                "stay": build_anim(pngs, pvf.raw(d["ani"]))}}]}
        deco_out.append({"actor": key, "layer": d["layer"],
                         "x": d["x"], "y": d["y"], "order": d["order"]})
    return {"tiles": out_tiles, "pass": pass_cells, "monsters": monsters,
            "backgrounds": bg_out, "decos": deco_out,
            "width": 224 * len(out_tiles), "height": 480}


def mob_table(pvf):
    txt = pvf.doc("monster/monster.lst")
    lines = [l.strip() for l in txt.splitlines() if l.strip()]
    out = {}
    for i in range(0, len(lines) - 1, 2):
        try:
            out[int(lines[i])] = lines[i + 1]
        except ValueError:
            pass
    return out


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--room", default="map/mirkwood/n201.map")
    ap.add_argument("--out", required=True)
    ap.add_argument("--weapon", default=None)
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    pvf = Pvf()
    pngs = Pngs(args.out)

    motions = ["stay", "move", "dash", "jump", "jumpattack",
               "weaponcomboshort1", "weaponcomboshort2", "weaponcomboshort3",
               "attack1", "dashattack"]

    actors = {}
    layers = actor_player(pvf, pngs, motions)
    if args.weapon:
        layers += actor_weapon(pvf, pngs, motions, args.weapon)
    actors["player"] = {"layers": layers}

    rooms = {}
    mt = mob_table(pvf)
    room = export_room(pvf, pngs, args.room, args.room.rsplit("/", 1)[-1][:-4], mt, actors)
    room["map"] = args.room
    rooms[args.room] = room

    data = {"pack": "sf85", "actors": actors, "rooms": rooms,
            "png_count": pngs.n}
    with open(os.path.join(args.out, "index.json"), "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("actor 层", len(layers), "怪物", len(actors) - 1, "PNG", pngs.n,
          "index.json", os.path.getsize(os.path.join(args.out, "index.json")), "B")


if __name__ == "__main__":
    main()
