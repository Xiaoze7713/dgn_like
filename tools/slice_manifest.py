#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""切片素材总清单生成器（t12）。

从 `analysis/10-SLICE.md` 的切片范围出发，用 `export/_meta/refgraph.sqlite` 做
反向可达（BFS），产出 `export/_meta/slice_manifest.json`：

    {"roots": [...], "files": [{"path","kind","bytes","refs_by","required"}],
     "totals": {...}, "gaps": [...], "img_packages": {...}}

约定
----
* 路径一律是 **PVF 原路径**（小写、带扩展名，与 `export/_meta/index.sqlite` 一致）。
  磁盘上的文本副本是 `export/text/<path>.txt`。
* 边只跟 `resolved=1`（落到了 PVF 真实文件）的；`kind='img'` 的边**不跟**，
  只收集为图像依赖 —— `.img` 在 NPK 里，不在 PVF 里。
* 函数引用（`.nut` 里的 `CUSTOM_ANI_*` 整数下标 → `.lay [etc motion]` → `%s` 展开）
  refgraph 看不见，由本脚本按 `analysis/10-SLICE.md` 的 6 个技能 + 15 个基础动作
  显式推断，并单独记进 `gaps`（标 `inferred`）。

用法
----
    python3 tools/slice_manifest.py                # 生成 manifest.json
    python3 tools/slice_manifest.py --trace <path> # 打印一个根的反查树
    python3 tools/slice_manifest.py --stat         # 只打印分类型统计
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sqlite3
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "tools"))
from ani_parser import parse_ani

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INDEX_DB = os.path.join(ROOT_DIR, "export", "_meta", "index.sqlite")
GRAPH_DB = os.path.join(ROOT_DIR, "export", "_meta", "refgraph.sqlite")
OUT_JSON = os.path.join(ROOT_DIR, "export", "_meta", "slice_manifest.json")
NPK_INDEX = "/tmp/t12/npk_img_index.tsv"        # 由 tools/npk_parser.py 全量枚举生成

# ---------------------------------------------------------------- 根集合
# 显式根：analysis/10-SLICE.md 点名要的文件。required=True 表示 "切片跑不起来就缺它"。
ROOTS: list[tuple[str, bool, str]] = []


def _r(path: str, note: str, required: bool = True) -> None:
    ROOTS.append((path.lower(), required, note))


# ---- 角色 / 成长 / 技能（10-SLICE §3）
_r("character/swordman/swordman.chr", "职业基表 Lv1 值 + [growtype 1] 每级增量")
_r("character/exptable.tbl", "升级经验表 115 级")
_r("etc/sptable.etc", "SP 累计池 Lv1-20")
_r("equipment/character/swordman.lay", "动作表：15 基础动作 + [etc motion] 276 项")
for _p in [
    "character/swordman/swordman_key.nut",  # 可能不存在，脚本会自动记 gap
]:
    _r(_p, "按键映射（若缺则不加载）", required=False)

# 23 个可学/白送技能（10-SLICE §3.2 的表 + 初始技能）
for _sk in [
    "upperslash", "hardattack", "guard", "dashattackmultihit", "ashenfork",
    "jumpattackmulti", "khazan", "vaneslash", "hopsmash", "tripleslash",
    "normalwave", "gorecross", "moonlightslash", "shortswordmastery",
    "blademastery", "heavyswordmastery", "bluntmastery", "ghoststep",
    "grandwave", "diehard", "backstep", "basicattackup", "quickstanding",
]:
    _r("skill/swordman/%s.skl" % _sk, "技能数值（无 ani/atk）")

# ---- 城镇（10-SLICE §4）
_r("town/town.lst", "id→城镇路径")
_r("town/1_new/new_elvengard.twn", "艾爾文防線")
_r("map/1_new/cataclysm/town/elvengard/new_elvengard.map", "城镇主街")
_r("npc/1_new/linus.npc", "林納斯：商店+技能导师+任务")
_r("npc/seria.npc", "賽麗亞：任务")
_r("itemshop/equipmentshop1.shp", "武器店货架")
_r("worldmap/worldmap.lst", "id→wdm")
_r("worldmap/lorien.wdm", "洛蘭世界地图（副本入口）")

# ---- 副本（10-SLICE §5）
_r("dungeon/dungeon.lst", "id→dgn")
for _d in ["lorien", "mirkwooddeep", "sunderlandpoison"]:
    _r("dungeon/act1/%s.dgn" % _d, "副本结构 [greed]/[map specification]")
_r("map/map.lst", "id→map（房间）")
for _m in [
    "map/lorien/s0.map", "map/lorien/6.map", "map/lorien/bn10.map",
    "map/lorien/9.map", "map/lorien/b1.map",
    "map/mirkwooddeep/403.map", "map/mirkwooddeep/406.map",
    "map/mirkwooddeep/407.map", "map/mirkwooddeep/412.map",
    "map/mirkwooddeep/411.map", "map/mirkwooddeep/b413.map",
    "map/sunderlandpoison/s801.map", "map/sunderlandpoison/e817(1,2).map",
    "map/sunderlandpoison/n809(2,1).map", "map/sunderlandpoison/h825(3,2).map",
    "map/sunderlandpoison/b813(5,1).map",
]:
    _r(_m, "房间：怪物布点 + tile + 装饰动画")

# ---- 怪物（10-SLICE §6）
for _mb in [
    "monster/goblin/goblin.mob", "monster/goblin/goblinthrower.mob",
    "monster/goblin/seagab.mob", "monster/goblin/hillgab.mob",
    "monster/goblin/goblintaskmaster.mob",
    "monster/goblin/goblinthrowertaskmaster.mob",
    "monster/goblin/flagseagab.mob", "monster/tau/taubeast.mob",
    "monster/lugaru/lugaru.mob", "monster/lugaru/kurogaru.mob",
    "monster/lugaru/sirogaru.mob", "monster/lugaru/penril.mob",
]:
    _r(_mb, "怪物声明：乘数 + 攻击槽 + [item] 权重")
for _fam in ["goblin"]:
    for _ai in ["event", "destinationselect", "action", "movemethod"]:
        _r("monster/%s/ai/%s.ai" % (_fam, _ai), "AI 条件树（同族共用 4 件套）")

# ---- 掉落物 / 装备（10-SLICE §8）
for _st in [
    "stackable/food_strawberry.stk", "stackable/food_rhybread.stk",
    "stackable/plant_lamihwaleaf.stk", "stackable/food_driedmeat.stk",
    "stackable/ftcoin.stk", "stackable/food_blueberry.stk",
    "stackable/flower_magical.stk", "stackable/material/tooth_poison.stk",
    "stackable/material/ryan_cokes.stk", "stackable/throw/stone1.stk",
]:
    _r(_st, "消耗品/材料：图标 + 价格 + 堆叠")
for _eq in [
    "equipment/character/swordman/weapon/katana/kat_damaged.equ",
    "equipment/character/swordman/weapon/katana/kat_worn.equ",
    "equipment/character/swordman/weapon/katana/kat.equ",
    "equipment/character/swordman/weapon/katana/kat_hkotachi.equ",
    "equipment/character/swordman/weapon/katana/kat_kogaras.equ",
    "equipment/character/common/jacket/cloth/sht_ragcloth.equ",
    "equipment/character/common/jacket/cloth/sht_tatcloth.equ",
    "equipment/character/common/jacket/cloth/sht_sbcloth.equ",
    "equipment/character/common/belt/leather/str_crleather.equ",
    "equipment/character/common/pants/leather/pant_wleather.equ",
]:
    _r(_eq, "装备：物攻/物防 + 图标 + 外观动画")

# ---- 任务（10-SLICE §9）
_r("n_quest/epicquest.lst", "章节→任务 id 顺序")
_r("n_quest/quest.lst", "任务 id→路径（339 条）")
_r("n_quest/questparameter.etc", "任务经验/金币基数")
for _q in [
    "n_quest/elvengard/lorien/sq.qst",
    "n_quest/elvengard/lorien/epic_1_lorien_1.qst",
    "n_quest/elvengard/lorien/epic_1_lorien_2.qst",
    "n_quest/elvengard/lorieninside/epic_2_lorieninside_3.qst",
    "n_quest/elvengard/lorieninside/epic_2_lorieninside_4.qst",
    "n_quest/elvengard/lorieninside/normal_2_lorieninside_seria_ring.qst",
]:
    _r(_q, "任务条件 + 奖励（含任务道具掉落链）")

# ---------------------------------------------------------------- 推断层
# 1) 角色身体动画：.lay 的 [etc motion] 是 0 基下标，.nut 里 sq_SetCurrentAnimation(n)
#    直接索引它；%s 由装备 [layer variation] 展开。切片只做未转职基础档 →
#    %s 取 character/swordman/animation/（另两档 atanimation/dsanimation 不加载）。
BODY_DIR = "character/swordman/animation"
BASIC_MOTIONS = [  # .lay 的分段名 → 切片必须的基础动作
    "waiting", "move", "dash", "dashattack", "attack", "damage motion 1",
    "damage motion 2", "down", "overturn", "jump", "jumpattack", "rest",
    "getitem", "buff", "back", "sit",
]
SKILL_TOKENS = ["upper", "hardattack", "tripleslash", "dashattackmulti",
                "ashenfork", "khazan", "gorecross", "hopsmash", "guard", "hitback"]


def lay_motions() -> tuple[list[str], dict[str, list[str]]]:
    """读 swordman.lay：返回 (etc motion 名列表, 分段名→ani 名列表)。"""
    path = os.path.join(ROOT_DIR, "export", "text",
                        "equipment", "character", "swordman.lay.txt")
    raw = open(path, "rb").read().decode("utf-8", "replace").replace("\x00", "")
    sections: dict[str, list[str]] = {}
    cur = None
    etc: list[str] = []
    for line in raw.split("\n"):
        st = line.strip()
        if st.startswith("[") and st.endswith("]"):
            cur = st[1:-1]
            sections.setdefault(cur, [])
            continue
        if cur is None or not st:
            continue
        names = re.findall(r"(\S+\.ani)", st)
        sections[cur].extend(names)
    etc = sections.get("etc motion", [])
    return etc, sections


def inferred_body_roots(all_paths: set[str]) -> tuple[list[tuple[str, str]], list[str]]:
    """推断：基础动作 + 6 技能的身体动画 + 技能 .atk。

    .lay 里写的是 `%s/Stay.ani`（%s 由装备 [layer variation] 展开成
    animation / dsanimation / atanimation），所以只能拿文件名回查。
    回查范围限定 `character/swordman/`，同名的三套（animation/ds/at）
    与 `zrr/` 子目录变体都算——运行时按武器二次选择。
    """
    etc, sections = lay_motions()
    want: list[tuple[str, str]] = []
    for sec in sections:
        if not sec.endswith(" motion") or sec == "etc motion":
            continue
        for name in sections.get(sec, []):
            want.append((name.lower(), "基础动作 %s" % sec))
    for name in etc:
        low = name.lower()
        if any(t in low for t in SKILL_TOKENS):
            want.append((low, "技能动作"))

    sw = [p for p in all_paths if p.startswith("character/swordman/") and p.endswith(".ani")]
    out: list[tuple[str, str]] = []
    hit_names: set[str] = set()
    for name, note in want:
        base = name.rpartition("/")[2]
        if base in hit_names:
            continue
        # 只要未转职鬼剑士那一档：character/swordman/animation/（dsanimation/
        # atanimation 是转职/分支形态的动作档，切片用不到，留了会多带一整套特效）
        matches = [p for p in sw
                   if p.endswith("/" + base) and p.startswith("character/swordman/animation/")]
        if not matches:
            continue
        hit_names.add(base)
        for m in matches:
            out.append((m, note + "（由 .lay 反查）"))

    # 技能 .atk：按目录约定 character/swordman/{attackinfo,dsattackinfo,atattackinfo}/<skill>.atk
    for sk in ["upperslash", "hardattack", "tripleslash", "dashattackmultihit",
               "ashenfork", "khazan", "gorecross", "hopsmash"]:
        for d in ("attackinfo", "dsattackinfo", "atattackinfo"):
            cand = "character/swordman/%s/%s.atk" % (d, sk)
            if cand in all_paths:
                out.append((cand, "技能伤害属性（目录约定）"))
    return out, sorted(set(n for n, _ in want) - hit_names)


# ---------------------------------------------------------------- 图 → NPK
def load_npk_index(path: str = NPK_INDEX) -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    if not os.path.exists(path):
        return idx
    with open(path, encoding="utf-8") as f:
        for line in f:
            p, _, pkg = line.rstrip("\n").partition("\t")
            if not p:
                continue
            idx.setdefault(p, []).append(pkg)
    return idx


def npk_lookup(idx: dict[str, list[str]], img: str) -> list[str]:
    """`%04d` 这类占位符按正则在前缀目录里模糊匹配。"""
    img = img.lower().lstrip("/")
    if img in idx:
        return idx[img]
    if "%" not in img or not idx:
        return []
    pat = re.compile("^" + re.sub(r"%0?\d*d", r"\\d{1,6}", re.escape(img)) + "$")
    d, _, _base = img.rpartition("/")
    prefix = d + "/"
    hits: list[str] = []
    for k, pkgs in idx.items():
        if k.startswith(prefix) and pat.match(k):
            hits.extend(pkgs)
    return sorted(set(hits))


# ---------------------------------------------------------------- ani → 图
_ANI_CACHE: dict[str, list[str]] = {}


def ani_images(p: str) -> list[str]:
    """直接读 .ani 二进制头部（比 refgraph 的 img 边可靠：后者每个 ani 常只记一张）。"""
    if p in _ANI_CACHE:
        return _ANI_CACHE[p]
    out: list[str] = []
    bin_path = os.path.join(ROOT_DIR, "export", "text", p + ".bin")
    try:
        with open(bin_path, "rb") as f:
            d = parse_ani(f.read())
        if d.get("ok"):
            out = [i.lower().lstrip("/") for i in d.get("images") or []]
    except Exception:
        pass
    _ANI_CACHE[p] = out
    return out


# ---------------------------------------------------------------- BFS
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--trace", help="只反查这一个根并打印树")
    ap.add_argument("--stat", action="store_true", help="只打印统计")
    ap.add_argument("--no-json", action="store_true")
    args = ap.parse_args()

    idx_db = sqlite3.connect(INDEX_DB)
    sizes = {p: s for p, s in idx_db.execute("select path, size from files")}
    exts = {p: e for p, e in idx_db.execute("select path, ext from files")}
    gdb = sqlite3.connect(GRAPH_DB)

    edges: dict[str, list[dict]] = {}
    for src, dst, raw, resolved, kind in gdb.execute(
            "select src, dst, raw, resolved, kind from edges"):
        edges.setdefault(src, []).append(
            {"src": src, "dst": dst, "raw": raw, "resolved": resolved, "kind": kind})

    # 索引类文件（.lst = id→路径总表，.tbl = 全局表）：要装进清单，但**不展开**。
    # 展开它们会把整库 2,989 张 map / 574 个 dgn 全拉进来，那不是切片。
    LEAF_EXTS = {"lst", "tbl", "lay"}

    def edge_target(src: str, e: dict) -> tuple[str | None, str]:
        """解析一条边。

        规则（按优先级）：① 相对引用者所在目录 → 命中即用；② raw 当根相对路径；
        ③ refgraph 的结论；④ 解析不出来 = 悬空。
        为什么 ① 必须压过 ③：refgraph 对 `Animation/Background/Back_Middle.ani`
        这类**同名文件**只会取后缀匹配的第一个，会把艾爾文防線的背景错指到别的副本。
        """
        raw = (e["raw"] or "").strip().lower()
        d = src.rpartition("/")[0]
        if raw and not raw.startswith("/"):
            if d:
                cand = d + "/" + raw
                if cand in sizes:
                    return cand, "samedir"
            if raw in sizes:
                return raw, "rootrel"
        if e["kind"] == "img":
            # .img 不在 PVF 里（在 NPK 里），不能用 sizes 判存在；规范化后就交出去
            return (e["dst"] or raw).lstrip("/"), "img"
        if e["resolved"] == 1 and e["dst"] in sizes:
            return e["dst"], "graph"
        return None, "dangling"

    # 根（含推断层）
    roots: list[tuple[str, bool, str]] = list(ROOTS)
    inf, miss_names = inferred_body_roots(set(sizes))
    inferred: set[str] = set()
    for p, note in inf:
        pl = p.lower()
        inferred.add(pl)
        roots.append((pl, True, note))

    gaps: list[dict] = []
    deferred: list[str] = []
    start: list[str] = []
    for p, req, note in roots:
        if p in sizes:
            start.append(p)
        else:
            gaps.append({"kind": "root_missing", "path": p, "note": note,
                         "why": "PVF 内无此文件（推断路径或文件名不符）"})
    start = sorted(set(start))

    # BFS
    files: dict[str, dict] = {}
    img_deps: dict[str, list[str]] = {}
    queue = list(start)
    for p in start:
        files[p] = {"path": p, "kind": exts.get(p, "?"), "bytes": sizes.get(p, 0),
                    "refs_by": [], "required": True}
    while queue:
        cur = queue.pop(0)
        if exts.get(cur) in LEAF_EXTS:
            continue
        # .chr 把「全职业 / 全流派（含 3 转）」的动画与 attackinfo 都枚举了一遍；
        # 切片只要 growtype 0 + 15 个基础动作 + 6 个转职前技能（后两者已由推断层补入），
        # 所以这里不跟 .chr 的 .ani/.atk 边，否则会把血魔/鬼剑/剑魂的整套特效拉进来。
        chr_leaf = exts.get(cur) == "chr"
        for e in edges.get(cur, []):
            if chr_leaf and e["kind"] == "anim" and (
                    (e["dst"] or "").endswith(".ani") or (e["dst"] or "").endswith(".atk")):
                deferred.append(e["dst"])
                continue
            dst, how = edge_target(cur, e)
            if dst is None:
                gaps.append({"kind": "dangling_ref", "path": cur, "dst": e["dst"],
                             "raw": e["raw"], "edge": e["kind"],
                             "why": "引用了 PVF 内不存在的文件（同目录/根相对都试过）"})
                continue
            if e["kind"] == "img":
                img_deps.setdefault(dst, [])
                if cur not in img_deps[dst]:
                    img_deps[dst].append(cur)
                continue
            if dst not in files:
                files[dst] = {"path": dst, "kind": exts.get(dst, "?"),
                              "bytes": sizes.get(dst, 0), "refs_by": [],
                              "required": True}
                queue.append(dst)
            if len(files[dst]["refs_by"]) < 4 and cur not in files[dst]["refs_by"]:
                files[dst]["refs_by"].append(cur)

    # 图像依赖：.ani 以二进制头部为准（refgraph 常只记一张），其余源用 refgraph 的 img 边
    ani_hits = 0
    for p in list(files):
        if exts.get(p) != "ani":
            continue
        for img in ani_images(p):
            if re.match(r"^%?\d+d?\.img$", img.rsplit("/", 1)[-1]):
                continue  # %04d 这类占位符被上游拼坏了，不是真文件名
            if img not in img_deps:
                img_deps[img] = []
                ani_hits += 1
            if len(img_deps[img]) < 3 and p not in img_deps[img]:
                img_deps[img].append(p)

    # 图像依赖 → NPK
    npk_idx = load_npk_index()
    img_pkgs: dict[str, list[str]] = {}
    img_missing: list[str] = []
    for img in img_deps:
        pkgs = npk_lookup(npk_idx, img)
        if pkgs:
            img_pkgs[img] = pkgs
        else:
            img_missing.append(img)

    # 统计
    by_kind: dict[str, dict] = {}
    for f in files.values():
        k = f["kind"]
        d = by_kind.setdefault(k, {"files": 0, "bytes": 0})
        d["files"] += 1
        d["bytes"] += f["bytes"]
    pkg_files: dict[str, int] = {}
    for img, pkgs in img_pkgs.items():
        for p in pkgs:
            pkg_files[p] = pkg_files.get(p, 0) + 1

    manifest = {
        "generated_by": "tools/slice_manifest.py",
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "scope": "analysis/10-SLICE.md 的 M3 切片（未转职鬼剑士 Lv1-20 / 艾爾文防線 / dgn 1,4,6 / 12 怪 / 10 装备 / 4 环主线）",
        "roots": [{"path": p, "required": r, "note": n} for p, r, n in roots],
        "files": sorted(files.values(), key=lambda f: (f["kind"], f["path"])),
        "images": [{"path": k, "npk": v, "referenced_by": img_deps[k][:3]}
                   for k, v in sorted(img_pkgs.items())],
        "totals": {
            "root_count": len(start),
            "files": len(files),
            "bytes": sum(f["bytes"] for f in files.values()),
            "by_kind": by_kind,
            "images_unique": len(img_deps),
            "images_found_in_npk": len(img_pkgs),
            "images_missing": len(img_missing),
            "npk_packages": len(pkg_files),
            "npk_package_top": sorted(pkg_files.items(), key=lambda x: -x[1])[:15],
        },
        "deferred_by_chr": sorted(set(d for d in deferred if d)),
        "gaps": gaps,
    }
    if img_missing:
        manifest["gaps"].extend(
            {"kind": "img_not_found", "path": p, "why": "任何 NPK 里都没有这张 .img"}
            for p in img_missing)

    print(json.dumps(manifest["totals"], ensure_ascii=False, indent=1))
    print("gaps:", collections.Counter(g["kind"] for g in manifest["gaps"]))
    if not args.no_json and not args.stat:
        with open(OUT_JSON, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
        print("wrote", OUT_JSON)
    return 0


if __name__ == "__main__":
    sys.exit(main())
