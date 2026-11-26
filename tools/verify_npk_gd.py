"""运行时 GDScript 解码 vs Python 参考实现的像素比对

用途：确认 `utils/npk/npk_image.gd`（纯 GDScript）解出来的 RGBA 与
`tools/npk_parser.py`（Python，已用 35 张 PNG 验证过）完全一致。

跑法：
  python3 tools/verify_npk_gd.py                 # 只打印 Python 侧摘要
  python3 tools/verify_npk_gd.py --gd gd.txt     # 再和 Godot 输出逐行对比

Godot 侧摘要由 `tests/test_npk_store.gd` 打印（格式：`  F<帧> rect=(x,y,w,h) ... md5=<md5>`）。
"""
import argparse
import gzip
import hashlib
import json
import os
import sys

sys.path.insert(0, "tools")
import npk_parser  # noqa: E402

PACK_DIR = "/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2"

CASES = [
    ("character/swordman/equipment/avatar/skin/sm_body0001.img", [0, 90, 180, 181, 184]),
    ("character/swordman/equipment/avatar/coat/sm_coat0000a.img", [180, 184]),
    ("map/02tile03.img", [0]),
    ("character/swordman/equipment/weapon/sswd/sswd1200b.img", [0, 1]),
    ("character/swordman/atequipment/weapon/sswd/(tn)sg_sswd0912a.img", [0, 1, 2]),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gd", help="Godot 输出文件")
    a = ap.parse_args()

    # 先用运行时索引找出每条 img 在哪个包里（与 Godot 侧同一份数据）
    where = {}
    with gzip.open("analysis/sf85/npk-index.jsonl.gz", "rt", encoding="utf-8") as g:
        for line in g:
            d = json.loads(line)
            where[d["p"]] = d["npk"]

    cache = {}
    mine = {}
    for path, frames in CASES:
        full = path if path.startswith("sprite/") else "sprite/" + path
        if full not in where:
            print("索引里没有 %s" % full, file=sys.stderr)
            continue
        npk_name = os.path.join(PACK_DIR, where[full])
        if npk_name not in cache:
            cache[npk_name] = npk_parser.Npk(npk_name)
        npk = cache[npk_name]
        img, _ = npk.open_img(full)
        for fr in frames:
            w, h, x, y, rgba = img.frame_image(fr)
            md5 = hashlib.md5(rgba).hexdigest()
            print("  F%d rect=(%d,%d,%d,%d) md5=%s" % (fr, x, y, w, h, md5))
            mine[(path, fr)] = md5

    if not a.gd:
        return 0

    got = {}
    cur = None
    for line in open(a.gd, encoding="utf-8", errors="replace"):
        if line.startswith("IMG "):
            cur = line.split()[1]
        elif line.strip().startswith("F") and "md5=" in line:
            parts = line.split()
            fr = int(parts[0][1:])
            got[(cur, fr)] = parts[-1].split("=", 1)[1].strip()
    bad = 0
    for k, v in mine.items():
        g = got.get(k)
        if g is None:
            print("缺 %s F%d" % k, file=sys.stderr)
            bad += 1
        elif g != v:
            print("不一致 %s F%d py=%s gd=%s" % (k[0], k[1], v, g), file=sys.stderr)
            bad += 1
    print("比对 %d 帧，不一致 %d" % (len(mine), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
