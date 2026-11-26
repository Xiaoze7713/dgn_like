#!/usr/bin/env python3
"""按 .equ 里的 variation 配置给角色穿衣服（默认套装 / 指定时装），并合成预览。

核心规则（全部由数据反推，已核对）：
  * 时装物品 `.equ` 里有一组 `[animation job]` 块，每块对应一个职业层：
        [animation job]
            [swordman]
        [variation]
            0            <- look（款式号，2 位）
            0            <- color（染色号，2 位）
        [layer variation]
            1500         <- z 序（越大越靠前）
            pants_a      <- 层目录名：<part>_<体型档>
        [equipment ani script]
            equipment/character/swordman.lay
  * 图集文件 = `character/swordman/equipment/avatar/<part>/sm_<part><look:02><color:02><体型>.img`
  * 动作 = `equipment/character/swordman/avatar/<part>/<层目录>/<motion>.ani`
  * 画法 = PNG 左上角 = (ani.x + img.x, ani.y + img.y)，与身体层同一坐标系，按 z 从小到大叠。

用法：
    python3 tools/make_outfit.py list                    # 列出可用的默认套装
    python3 tools/make_outfit.py show <equ> [<equ> ...]  # 打印解析结果
    python3 tools/make_outfit.py render --motion move --out x.png
"""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from pvf_unpack import PvfArchive, decode_entry  # noqa: E402

PVF = "/mnt/e/dnf-sf/sf115/Script.pvf"
PACKS = "/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2"
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "dnf_demo")
INDEX = os.path.join(ROOT, "analysis/pvf/reports/img-index.json")

JOB = "swordman"
BODY = "character/swordman/equipment/avatar/skin/sm_body0001.img"
# 时装槽位（DNF 鬼剑士 9 个可见部位 + 皮肤；皮肤不单独画层，它决定 sm_body 的 look）
SLOTS = ["pants", "shoes", "belt", "coat", "neck", "face", "hair", "cap", "aura"]
DEFAULT_EQU = {
    "pants": "equipment/character/swordman/avatar/pants/apants_default.equ",
    "shoes": "equipment/character/swordman/avatar/shoes/ashoes_default.equ",
    "hair": "equipment/character/swordman/avatar/hair/ahair_default.equ",
    "coat": "equipment/character/swordman/avatar/coat/acoat_default.equ",
    "cap": "equipment/character/swordman/avatar/cap/ahat_default.equ",  # look 101 无图集 → 默认不戴帽
    # belt / neck / face / aura 没有 *_default.equ：默认空槽
}


# ---------------------------------------------------------------- 解析 .equ
def read_doc(ar, path):
    kind, payload, _ = decode_entry(ar, ar.entry(path))
    if kind != "doc":
        raise RuntimeError("%s 不是文档（%s）" % (path, kind))
    return payload.splitlines()


def parse_equ(ar, path):
    """从一个 .equ 里抽出 [animation job] 块 -> variation / layer variation。

    返回 {job: {"variation": (look, color), "layers": [(z, dir)]}}
    """
    lines = [l.strip() for l in read_doc(ar, path)]
    out = {}
    cur = None            # 当前 job
    mode = None           # 'variation' | 'layer' | 'script'
    pending_z = None
    i = 0
    while i < len(lines):
        l = lines[i]
        if l == "[animation job]":
            i += 1
            if i < len(lines) and lines[i].startswith("["):
                job = lines[i].strip("[]")
                cur = out.setdefault(job, {"variation": None, "layers": []})
                mode = None
            i += 1
            continue
        if l == "[variation]" and cur is not None:
            vals = []
            j = i + 1
            while j < len(lines) and not lines[j].startswith("["):
                vals.append(int(lines[j]))
                j += 1
            if len(vals) >= 2:
                cur["variation"] = (vals[0], vals[1])
            mode = None
            i = j
            continue
        if l == "[layer variation]" and cur is not None:
            j = i + 1
            z = None
            while j < len(lines) and not lines[j].startswith("["):
                tok = lines[j]
                if re.fullmatch(r"-?\d+", tok):
                    z = int(tok)
                else:
                    cur["layers"].append((z, tok))
                j += 1
            mode = None
            i = j
            continue
        i += 1
    return out


def body_type(layers, prefer="a"):
    """从 layer 目录名里取体型档（coat_a -> a）。"""
    for _, d in layers:
        m = re.search(r"_([a-z])(?:_|$)", d)
        if m and m.group(1) == prefer:
            return prefer
    return prefer


def sheet_path(part, look, color, bt):
    return "character/swordman/equipment/avatar/%s/sm_%s%02d%02d%s.img" % (part, part, look, color, bt)


def ani_path(part, laydir, motion):
    return "equipment/character/swordman/avatar/%s/%s/%s.ani" % (part, laydir, motion)


# ---------------------------------------------------------------- 素材读取
class Assets:
    def __init__(self):
        from npk_parser import Npk, Img
        self._Npk, self._Img = Npk, Img
        self.index = json.load(open(INDEX, encoding="utf-8"))
        self.npks = {}
        self.imgs = {}

    def _open_img(self, path):
        if path in self.imgs:
            return self.imgs[path]
        key = "sprite/" + path if "sprite/" + path in self.index else path
        if key not in self.index:
            return None
        fn = self.index[key][0]
        npk = self.npks.get(fn)
        if npk is None:
            npk = self._Npk(os.path.join(PACKS, fn))
            self.npks[fn] = npk
        img = self._Img(npk.read(key))
        self.imgs[path] = img
        return img

    def frame_png(self, path, fr):
        from PIL import Image
        img = self._open_img(path)
        if img is None or fr >= len(img.frames):
            return None
        w, h, x, y, px = img.frame_image(fr)
        return Image.frombytes("RGBA", (w, h), px), x, y


def build_layers(ar, equ_paths):
    """把一队 .equ 解析成绘制层：[(z, part, look, color, suffix, laydir, sheet)]

    关键：一个部件可以有**多个 layer**（`[layer variation]` 里每对 z + 目录名 各一层），
    例如默认裤子 = `1500 pants_a`（前腿）+ `1300 pants_b`（后腿），两层的图集后缀不同。
    """
    layers = []
    for part, path in equ_paths:
        jobs = parse_equ(ar, path)
        info = jobs.get(JOB)
        if not info or not info["variation"]:
            continue
        look, color = info["variation"]
        for zz, dd in info["layers"]:
            suffix = dd[-1] if re.search(r"_[a-z]$", dd) else "a"
            layers.append({"z": zz or 0, "kind": "avatar", "part": part, "look": look, "color": color,
                           "suffix": suffix, "laydir": dd,
                           "sheet": sheet_path(part, look, color, suffix),
                           "ani_dir": "equipment/character/swordman/avatar/%s/%s" % (part, dd)})
    layers.sort(key=lambda d: d["z"])
    return layers


def build_weapon_layers(ar, equ_path):
    """武器 .equ -> 绘制层。结构与时装一致，但图集/动作在 weapon 目录。

    [equipment type]
        [weapon]
        24                 <- 武器子类型（短剑）
    [animation job][swordman]
    [variation] 63 0        <- look=63 color=0
    [layer variation] 2790 sswdc / 650 sswdb   <- 两层（刀身层+握把层）
    """
    jobs = parse_equ(ar, equ_path)
    info = jobs.get(JOB)
    if not info or not info["variation"]:
        return []
    look, color = info["variation"]
    # equipment/character/swordman/weapon/ssword/5003219.equ -> ssword
    wtype = equ_path.split("/weapon/")[1].split("/")[0]
    layers = []
    for zz, dd in info["layers"]:
        prefix = dd[:-1] if re.search(r"_[a-z]$", dd) or re.search(r"[a-z]$", dd) else dd
        suffix = dd[-1]
        sheet = "character/swordman/equipment/weapon/%s/%s%02d%02d%s.img" % (prefix, prefix, look, color, suffix)
        layers.append({"z": zz or 0, "kind": "weapon", "part": "weapon", "look": look, "color": color,
                       "suffix": suffix, "laydir": dd, "sheet": sheet,
                       "ani_dir": "equipment/character/swordman/weapon/%s/%s" % (wtype, dd),
                       "wtype": wtype})
    layers.sort(key=lambda d: d["z"])
    return layers


# ---------------------------------------------------------------- 渲染
def render(ar, layers, motion, out_path, body=BODY, scale=3, label=True):
    from PIL import Image, ImageDraw

    asr = Assets()
    # 身体层
    body_ani = None
    for cand in ("character/swordman/animation/%s.ani" % motion,
                 "character/swordman/animation/standby/%s.ani" % motion):
        try:
            ar.entry(cand)
            body_ani = cand
            break
        except Exception:
            pass
    if body_ani is None:
        raise SystemExit("找不到身体动作 %s" % motion)
    from pvf_unpack import parse_animation
    ani = parse_animation(ar.read_raw(ar.entry(body_ani)), ar.encoding)
    frames = ani["frames"]

    part_anims = []
    for L in layers:
        p = "%s/%s.ani" % (L["ani_dir"], motion)
        try:
            a = parse_animation(ar.read_raw(ar.entry(p)), ar.encoding)
        except Exception:
            continue
        part_anims.append((L, a["frames"]))

    tiles = []
    for i, bf in enumerate(frames):
        items = []   # (z, png, x, y)
        im = asr.frame_png(body, bf["img_param"])
        if im:
            png, ix, iy = im
            items.append((0, png, bf["x"] + ix, bf["y"] + iy))
        for L, pf in part_anims:
            if i >= len(pf):
                continue
            f = pf[i]
            if f.get("img_id") is None or f.get("img_param") is None:
                continue
            im = asr.frame_png(L["sheet"], f["img_param"])
            if im and im[0].width > 1 and im[0].height > 1:
                png, ix, iy = im
                items.append((L["z"], png, f["x"] + ix, f["y"] + iy))
        if not items:
            continue
        minx = min(x for _, _, x, _ in items)
        miny = min(y for _, _, _, y in items)
        maxx = max(x + p.width for _, p, x, _ in items)
        maxy = max(y + p.height for _, p, _, y in items)
        canvas = Image.new("RGBA", (maxx - minx, maxy - miny), (0, 0, 0, 0))
        for _, p, x, y in sorted(items, key=lambda t: t[0]):
            canvas.alpha_composite(p, (x - minx, y - miny))
        tiles.append((canvas, bf["delay"]))

    if not tiles:
        raise SystemExit("没有可渲染的帧")
    W = max(t[0].width for t in tiles) * scale
    H = max(t[0].height for t in tiles) * scale
    pad, lab = 8, 16
    sheet = Image.new("RGBA", ((W + pad * 2) * len(tiles), H + pad * 2 + lab), (250, 250, 250, 255))
    dr = ImageDraw.Draw(sheet)
    for i, (t, delay) in enumerate(tiles):
        big = t.resize((t.width * scale, t.height * scale), Image.NEAREST)
        sheet.alpha_composite(big, (i * (W + pad * 2) + pad, lab + pad))
        if label:
            dr.text((i * (W + pad * 2) + pad, 3), "#%d %dms" % (i, delay), fill=(20, 20, 20, 255))
    sheet.save(out_path)
    print("-> %s  %dx%d  %d 帧  总 %dms" % (out_path, sheet.width, sheet.height, len(tiles),
                                          sum(t[1] for t in tiles)))
    return sheet


def render_gif(ar, layers, motion, out_path, body=BODY, scale=3):
    from PIL import Image
    import tempfile
    tmp = tempfile.mktemp(suffix=".png")
    # 复用 render 的取帧逻辑：先渲染成条图再切回来不划算，这里直接重算
    asr = Assets()
    from pvf_unpack import parse_animation
    frames = parse_animation(ar.read_raw(ar.entry("character/swordman/animation/%s.ani" % motion)),
                             ar.encoding)["frames"]
    part_anims = []
    for L in layers:
        try:
            a = parse_animation(ar.read_raw(ar.entry(ani_path(L["part"], L["laydir"], motion))), ar.encoding)
            part_anims.append((L, a["frames"]))
        except Exception:
            continue
    ims, durs = [], []
    for i, bf in enumerate(frames):
        items = []
        im = asr.frame_png(body, bf["img_param"])
        if im:
            png, ix, iy = im
            items.append((0, png, bf["x"] + ix, bf["y"] + iy))
        for L, pf in part_anims:
            if i >= len(pf):
                continue
            f = pf[i]
            if f.get("img_param") is None or f.get("img_id") is None:
                continue
            im = asr.frame_png(L["sheet"], f["img_param"])
            if im and im[0].width > 1 and im[0].height > 1:
                png, ix, iy = im
                items.append((L["z"], png, f["x"] + ix, f["y"] + iy))
        if not items:
            continue
        minx = min(x for _, _, x, _ in items)
        miny = min(y for _, _, _, y in items)
        maxx = max(x + p.width for _, p, x, _ in items)
        maxy = max(y + p.height for _, p, _, y in items)
        c = Image.new("RGBA", (maxx - minx, maxy - miny), (0, 0, 0, 0))
        for _, p, x, y in sorted(items, key=lambda t: t[0]):
            c.alpha_composite(p, (x - minx, y - miny))
        ims.append(c)
        durs.append(bf["delay"])
    # 统一画布
    W = max(i.width for i in ims) * scale + 8
    H = max(i.height for i in ims) * scale + 8
    out = []
    for c, d in zip(ims, durs):
        canvas = Image.new("RGBA", (W, H), (250, 250, 250, 255))
        canvas.alpha_composite(c.resize((c.width * scale, c.height * scale), Image.NEAREST), (4, 4))
        out.append(canvas.convert("RGB"))
    out[0].save(out_path, save_all=True, append_images=out[1:], duration=durs, loop=0, disposal=2)
    print("-> %s  %dx%d  %d 帧  总 %dms" % (out_path, W, H, len(out), sum(durs)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["list", "show", "render", "gif"])
    ap.add_argument("equ", nargs="*")
    ap.add_argument("--weapon", action="append", default=[], help="武器 .equ 路径，可多次")
    ap.add_argument("--equ", dest="equ_opt", action="append", default=[],
                    help="part=equ 路径，可多次；用于换装/补空槽")
    ap.add_argument("--motion", default="move")
    ap.add_argument("--out", default=None)
    ap.add_argument("--body", default=BODY)
    ap.add_argument("--pvf", default=PVF)
    args = ap.parse_args()

    ar = PvfArchive(args.pvf)
    ar.load_strings()

    if args.cmd == "list":
        print("槽位:", ", ".join(SLOTS), "（skin 决定 sm_body，不画层）")
        for part, p in DEFAULT_EQU.items():
            jobs = parse_equ(ar, p)
            print("%-6s %s" % (part, p))
            for job, info in jobs.items():
                print("        job=%-18s variation=%-10s layers=%s" %
                      (job, info["variation"], info["layers"]))
        return

    equ_paths = list(DEFAULT_EQU.items())
    for spec in (args.equ_opt or args.equ):
        if "=" in spec:
            part, path = spec.split("=", 1)
            equ_paths = [x for x in equ_paths if x[0] != part] + [(part, path)]
        else:  # 只给路径时按目录名猜部件
            part = re.sub(r"^[a-z]|_default\.equ$", "", spec.rsplit("/", 1)[-2])
            equ_paths = [x for x in equ_paths if x[0] != part] + [(part, spec)]
    layers = build_layers(ar, equ_paths)
    for w in args.weapon:
        layers += build_weapon_layers(ar, w)
    layers.sort(key=lambda d: d["z"])

    if args.cmd == "show":
        for L in layers:
            print("%-6s z=%-5s look=%02d color=%02d %-10s sheet=%s" %
                  (L["part"], L["z"], L["look"], L["color"], L["laydir"], L["sheet"]))
        return

    out = args.out or os.path.join(OUT, "verify", "outfit_%s.png" % args.motion)
    if args.cmd == "render":
        render(ar, layers, args.motion, out, body=args.body)
    else:
        render_gif(ar, layers, args.motion, out, body=args.body)


if __name__ == "__main__":
    main()
