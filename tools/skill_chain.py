#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""技能 → 动画 → 判定 的链条解析器（P1 / t14）。

把「`.skl` → `.nut` → `[etc motion]` 下标 → `.ani` 帧 → `[etc attack info]` 下标 → `.atk`」
这条 5 层链做成机器可读表，输出 `export/_meta/skill_anim_map.json`。

用法::

    python tools/skill_chain.py                 # 生成 JSON + 打印统计
    python tools/skill_chain.py --json OUT      # 指定输出
    python tools/skill_chain.py --dump 8        # 打印单个技能的全部中间量

只读 `export/`，不修改任何既有产物。
"""
from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from tools.ani_parser import parse_ani, to_frame_table  # noqa: E402

EXPORT = os.path.join(ROOT, "export")
TEXT = os.path.join(EXPORT, "text")
STRUCT = os.path.join(EXPORT, "structured")
META = os.path.join(EXPORT, "_meta")

# 首切片（analysis/10-SLICE.md §3.2）的 23 行技能 + 3 个内置动作。
# id → (期望动作名 stem, 备注)
SLICE_SKILLS = [
    (46, "UpperSlash"), (5, "HardAttack"), (1, "Guard"), (11, "DashAttackMultiHit"),
    (16, "AshenFork"), (17, "JumpAttackMulti"), (25, "Khazan"), (58, "VaneSlash"),
    (65, "HopSmash"), (8, "TripleSlash"), (20, "NormalWave"), (64, "GoreCross"),
    (77, "MoonlightSlash"), (12, "ShortSwordMastery"), (13, "BladeMastery"),
    (14, "HeavySwordMastery"), (15, "BluntMastery"), (18, "GhostStep"),
    (50, "GrandWave"), (34, "DieHard"), (169, "BackStep"), (174, "BasicAttackUp"),
    (190, "QuickStanding"),
]

# 内置动作（stateId 直接在引擎里，ani/atk 来自 chr 的 [xxx motion]/[xxx info]）
BUILTIN = [
    ("basic_attack_1", 8, "[attack motion]", 0, "[attack info]", 0),
    ("basic_attack_2", 8, "[attack motion]", 1, "[attack info]", 1),
    ("basic_attack_3", 8, "[attack motion]", 2, "[attack info]", 2),
    ("dash_attack", None, "[dashattack motion]", 0, "[dashattack info]", 0),
    ("jump_attack", None, "[jumpattack motion]", 0, "[jumpattack info]", 0),
]

# 无 nut（引擎内置）时，技能名 → etc motion 里的候选名（人工核对，证据见
# analysis/14-SKILL-ANIM-MAP.md §4）。None = 数据里找不到本体动作。
# 值为 (候选下标列表, 依据)；按顺序取第一个「带 [ATTACK BOX]」的候选，都不带则取最末一个。
MOTION_HINT = {
    "UpperSlash": ([260, 16],
                   "CUSTOM_ANI_UPPER_BODY=260（tripleslash.nut 的 substate 1006 用它配 atk 11=UpperSlash.atk）"),
    "HardAttack": ([1], "etc motion[1]=HardAttack.ani，与 atk[0]=HardAttack.atk 同名"),
    "Guard": ([0], "etc motion[0]=Guard.ani（格擋，无独立 atk）"),
    "DashAttackMultiHit": ([11], "etc motion[11]=DashAttackMultiHit.ani，atk[14]=DashAttackMultiHIt.atk（官方拼写 HIt）"),
    "AshenFork": ([16], "无 AshenFork.ani；取 UpperSlashAfter.ani[16]（銀光落刃=上挑的空中版，待验证）"),
    "JumpAttackMulti": ([24, 23], "etc motion[23/24]=JumpAttackMultiSlash1/2.ani，atk=JumpAttackMultiSlash1"),
    "VaneSlash": ([15, 14], "etc motion[15]=VaneSlash.ani（14=Try），atk[16..18]=VaneSlashTry/Upper/Smash"),
    "HopSmash": ([27, 26], "etc motion[26]=HopSmashReady → [27]=HopSmash.ani，atk[25..26]"),
    "NormalWave": ([22, 21, 20], "etc motion[20..22]=StandAloneWave{Ready,Basic,Strong}.ani，atk[22]=StandAloneWave.atk"),
    "GoreCross": ([25], "etc motion[25]=GoreCross.ani，atk[23..24]=GoreCross1/2"),
    "MoonlightSlash": ([61, 62], "etc motion[61..62]=MoonlightSlash1/2.ani"),
    "GhostStep": ([19, 18], "etc motion[18/19]=GhostStepSlash{Ready,Move}.ani，atk[21]=GhostStepSlash.atk"),
}

# atk 名 → etc attack info 里的名字（容错官方拼写）
ATK_NAME_HINT = {
    "UpperSlash": "UpperSlash", "HardAttack": "HardAttack", "Guard": None,
    "DashAttackMultiHit": "DashAttackMultiHIt", "AshenFork": "AshenFork",
    "JumpAttackMulti": None, "VaneSlash": "VaneSlashSmash",
    "HopSmash": "HopSmash", "NormalWave": "StandAloneWave", "GoreCross": "GoreCross1",
    "MoonlightSlash": "MoonlightSlash1", "GhostStep": "GhostStepSlash",
    "TripleSlash": "TripleSlash1",
}


# --------------------------------------------------------------------------
# 载入
# --------------------------------------------------------------------------
def load_jsonl_gz(path):
    out = []
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        for line in fh:
            out.append(json.loads(line))
    return out


def load_chr():
    for rec in load_jsonl_gz(os.path.join(STRUCT, "chr.jsonl.gz")):
        if rec["path"].lower().endswith("swordman/swordman.chr"):
            return rec["path"], rec["data"]
    raise SystemExit("swordman.chr not found")


def load_skl_by_id():
    """id → {path, data}；id 来自 skill__swordmanskill.lst.tsv。"""
    lst = os.path.join(META, "lst", "skill__swordmanskill.lst.tsv")
    id2path = {}
    if os.path.exists(lst):
        with open(lst, encoding="utf-8") as fh:
            for line in fh:
                parts = line.rstrip("\n").split("\t")
                if len(parts) >= 2 and parts[0].isdigit():
                    id2path[int(parts[0])] = parts[1]
    bypath = {r["path"].lower(): r["data"] for r in load_jsonl_gz(os.path.join(STRUCT, "skl.jsonl.gz"))}
    out = {}
    for sid, rel in id2path.items():
        for key in (("skill/" + rel).lower(), rel.lower()):
            if key in bypath:
                out[sid] = {"path": key, "data": bypath[key]}
                break
    return out, id2path


def load_atk_index():
    return {r["path"].lower(): r["data"] for r in load_jsonl_gz(os.path.join(STRUCT, "atk.jsonl.gz"))}


def load_constants():
    """swordman_value.nut → {NAME: int}（权威常量表）。"""
    path = os.path.join(TEXT, "sqr/character/swordman_jg/swordman_value.nut.txt")
    consts = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"\s*([A-Z][A-Z0-9_]*)\s*<-\s*(-?\d+)", line)
            if m and not line.lstrip().startswith("//"):
                consts[m.group(1)] = int(m.group(2))
    return consts


def load_push_state():
    """load_state.nut → skill_id → [(stateId, nut, name)]。"""
    path = os.path.join(TEXT, "sqr/character/swordman_load_state.nut.txt")
    rx = re.compile(r'pushState\(\s*\d+\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*\)')
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for lineno, line in enumerate(fh, 1):
            for m in rx.finditer(line):
                nut, name, state, skill = m.group(1), m.group(2), int(m.group(3)), int(m.group(4))
                out.setdefault(skill, []).append({"state_id": state, "nut": nut, "name": name,
                                                  "line": lineno})
    return out


AT_MARKERS = ("/at_", "atequipment", "at_avatar")


def is_at_avatar(path):
    """AT（二次觉醒/装扮专用）动画：帧数是 6/5/4，与本体 10/11/9 不同，
    混用会把整数帧号整体错位，而且**不会报错**——必须显式排除。"""
    low = path.replace("\\", "/").lower()
    return any(m in low for m in AT_MARKERS)


def build_ani_index():
    """basename(小写) → [路径...]"""
    idx = {}
    for dp, _, fns in os.walk(TEXT):
        for fn in fns:
            if fn.endswith(".ani.bin"):
                idx.setdefault(fn[:-8].lower(), []).append(os.path.join(dp, fn))
    return idx


WEAPON_DIR = "equipment/character/swordman/weapon"


def build_weapon_index():
    """武器层动画：普攻 1/2 段的 [ATTACK BOX] 在这里（身体层只有受击盒）。"""
    idx = {}
    root = os.path.join(TEXT, WEAPON_DIR)
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if fn.endswith(".ani.bin"):
                idx.setdefault(fn[:-8].lower(), []).append(os.path.join(dp, fn))
    for k in idx:
        idx[k].sort(key=len)
    return idx


# 首切片装备的是太刀（27600 破損的武士刀 / `[item group name] katana`、
# `[layer variation] 2790 katanac`）。换武器只要改这两个常量。
WEAPON_KEY = "/weapon/katana/"
WEAPON_VARIATION = "katanac"


def weapon_layer_ani(stem, weapon_ani_index):
    """普攻 1/2 段的 [ATTACK BOX] 不在身体动画里，在**武器**动画里。

    身体层（character/swordman/animation/attack1.ani）给姿态 + 受击盒（db 3 块），
    武器层（equipment/character/swordman/weapon/katana/katanac/attack1.ani）给轨迹 + 攻击盒（ab）。
    两层帧数与时长逐一相等（10 帧/600ms、11 帧/650ms），是叠加关系。
    """
    cands = [p for p in weapon_ani_index.get(stem.lower(), [])
             if WEAPON_KEY in p.replace("\\", "/").lower() and not is_at_avatar(p)]
    if not cands:
        return None
    cands.sort(key=lambda p: (WEAPON_VARIATION not in p.lower(), len(p)))
    return cands[0]


# --------------------------------------------------------------------------
# ani 定位（PVF 路径不是根相对：先按 layer variation 归位，再退回同根）
# --------------------------------------------------------------------------
WEAPONMASTER = "equipment/character/swordman/growtype/weaponmaster"
SWORDMAN_ANIM = "character/swordman"


def resolve_ani(motion_path, ani_index):
    """`Animation/Guard.ani` → 真实 .ani.bin；返回 (绝对路径|None, 依据)。"""
    base = motion_path.replace("\\", "/").split("/")[-1]
    stem = base[:-4] if base.lower().endswith(".ani") else base
    low = stem.lower()
    # 1) chr 根：把 motion 路径原样落到 character/swordman/ 下（如 Animation/Guard.ani →
    #    character/swordman/animation/guard.ani.bin）。这份副本才是带 [ATTACK BOX] 的。
    rel = motion_path.replace("\\", "/").lower()
    rel = rel if rel.endswith(".ani") else rel + ".ani"
    p = os.path.join(TEXT, SWORDMAN_ANIM, rel + ".bin")
    if os.path.exists(p):
        return p, "character/swordman 根（带判定盒）"
    # 2) layer variation 展开：%s/xxx.ani → growtype/<variation>/xxx.ani
    #    该副本帧数/flag 与 chr 根一致，但判定盒被剥掉。
    p = os.path.join(TEXT, WEAPONMASTER, low + ".ani.bin")
    if os.path.exists(p):
        return p, "layer variation=weaponmaster"
    # 3) 全局同名兜底
    cands = [p for p in ani_index.get(low, []) if not is_at_avatar(p)]
    if cands:
        cands.sort(key=lambda p: ("growtype" not in p, len(p)))
        return cands[0], "全局同名兜底"
    return None, "not found"


# --------------------------------------------------------------------------
# 解析
# --------------------------------------------------------------------------
def skill_nut_info(nut_rel, consts, motions, atks):
    """读 nut，抽出 (substate → ani 下标 / atk 下标)。"""
    p = os.path.join(TEXT, nut_rel)
    if not os.path.exists(p) or not p.endswith(".nut.txt"):
        return [], []
    text = open(p, encoding="utf-8", errors="replace").read()
    branches = []
    cur = None
    for line in text.split("\n"):
        s = line.strip()
        m = re.search(r"substate\s*==\s*(\d+)", s)
        if m:
            cur = {"substate": int(m.group(1)), "ani_const": None, "atk_const": None}
            branches.append(cur)
            continue
        if cur is None:
            continue
        m = re.search(r"sq_SetCurrentAnimation\(\s*([^)]*)\)", s)
        if m and cur["ani_const"] is None:
            cur["ani_const"] = m.group(1).strip()
        m = re.search(r"sq_SetCurrentAttackInfo\(\s*([^)]*)\)", s)
        if m and cur["atk_const"] is None:
            cur["atk_const"] = m.group(1).strip()
    out = []
    for b in branches:
        ani_i = resolve_int(b["ani_const"], consts)
        atk_i = resolve_int(b["atk_const"], consts)
        out.append({"substate": b["substate"],
                    "ani_const": b["ani_const"], "ani_index": ani_i,
                    "atk_const": b["atk_const"], "atk_index": atk_i,
                    "ani": motions[ani_i] if ani_i is not None and 0 <= ani_i < len(motions) else None,
                    "atk": atks[atk_i] if atk_i is not None and 0 <= atk_i < len(atks) else None})
    return out, text.split("\n")


def resolve_int(expr, consts):
    if not expr:
        return None
    expr = expr.strip()
    if re.fullmatch(r"-?\d+", expr):
        return int(expr)
    m = re.fullmatch(r"([A-Z][A-Z0-9_]*)\s*([+-])\s*(\d+)", expr)
    if m and m.group(1) in consts:
        v = consts[m.group(1)]
        return v + int(m.group(3)) if m.group(2) == "+" else v - int(m.group(3))
    if expr in consts:
        return consts[expr]
    return None


def atk_fields(atk_data):
    """从 .atk dict 抽关键伤害字段。

    `structured/atk.jsonl` 把嵌套枚举**拍平成兄弟键**（`[attack type]` 后紧跟
    `[physic]`），所以枚举值要按「插入顺序取父键的下一个键」来读，不能查子 dict。
    """
    if not atk_data:
        return {}
    keys = list(atk_data.keys())

    def child(parent):
        if parent not in keys:
            return None
        i = keys.index(parent)
        return keys[i + 1] if i + 1 < len(keys) else None

    def num(key, idx=0):
        v = atk_data.get(key)
        if isinstance(v, list) and len(v) > idx:
            return v[idx]
        return None

    out = {
        "damage_bonus": num("[damage bonus]"),
        "attack_type": child("[attack type]"),
        "element": child("[elemental property]"),
        "reaction": child("[damage reaction]"),
        "direction": child("[attack direction]"),
        "push_aside": num("[push aside]"),
        "lift_up": num("[lift up]"),
        "knuck_back": num("[knuck back]"),
        "absolute_damage": num("[absolute damage]"),
        "weapon_damage_apply": num("[weapon damage apply]"),
        "stuck": num("[stuck]"),
        "hit_wav": (atk_data.get("[hit wav]") or [None])[0],
    }
    return {k: (v.strip("[]") if isinstance(v, str) else v)
            for k, v in out.items() if v not in (None, [])}


def ani_detail(abs_path):
    if not abs_path or not os.path.exists(abs_path):
        return None
    info = parse_ani(open(abs_path, "rb").read())
    if not info.get("ok"):
        return {"error": info.get("error")}
    ft = to_frame_table(info, abs_path)
    atk_frames = [f["i"] for f in ft["frames"] if f["ab"]]
    flags = [{"frame": f["i"], "flag": f["flag"]} for f in ft["frames"]
             if f["flag"] is not None and f["flag"] != 65534]
    boxes = []
    for f in ft["frames"]:
        for b in f["ab"]:
            boxes.append({"frame": f["i"], "x": b[0], "y": b[1], "z": b[2],
                          "w": b[3], "h": b[4], "d": b[5]})
    return {
        "frame_count": ft["ani_frames"],
        "total_ms": ft["total_ms"],
        "attack_frames": atk_frames,
        "flags": flags,
        "boxes": boxes,
        "delays": [f["d"] for f in ft["frames"]],
    }


def build():
    chr_path, chr_data = load_chr()
    motions = chr_data["[etc motion]"]
    atks = chr_data["[etc attack info]"]
    skls, id2path = load_skl_by_id()
    consts = load_constants()
    push = load_push_state()
    atk_idx = load_atk_index()
    ani_index = build_ani_index()
    widx = build_weapon_index()

    records = []

    # ---- 内置动作 ----
    for tag, state, mkey, mi, akey, ai in BUILTIN:
        motion = chr_data[mkey][mi]
        atkp = chr_data[akey][ai]
        ani_abs, why = resolve_ani(motion, ani_index)
        det = ani_detail(ani_abs)
        ad = atk_fields(atk_idx.get(("character/swordman/" + atkp).lower()))
        rec = {
            "skill_id": None, "name": tag, "level_req": 1, "state_id": state,
            "nut": None, "flag_index": None,
            "ani": ani_abs.replace(TEXT + "/", "") if ani_abs else None,
            "ani_motion": motion, "ani_index": None,
            "ani_frames": (det or {}).get("attack_frames", []),
            "ani_frame_count": (det or {}).get("frame_count"),
            "ani_frame_ms": (det or {}).get("total_ms"),
            "ani_flags": (det or {}).get("flags", []),
            "attack_info_index": ai, "atk": "character/swordman/" + atkp,
            "damage_bonus": ad.get("damage_bonus"),
            "atk_fields": ad,
            "hitbox": (det or {}).get("boxes", [None])[0] if (det or {}).get("boxes") else None,
            "boxes": (det or {}).get("boxes", []),
            "ani_source": "chr %s[%d]" % (mkey, mi),
            "atk_source": "chr %s[%d]" % (akey, ai),
            "unresolved": [],
        }
        if not det or not det.get("frame_count"):
            rec["unresolved"].append("ani 解析失败")
        if not rec["hitbox"]:
            rec["unresolved"].append("身体层 ani 无 [ATTACK BOX]（判定盒不在动画里）")
        records.append(rec)

    # ---- 技能 ----
    for sid, stem in SLICE_SKILLS:
        skl = skls.get(sid)
        data = skl["data"] if skl else {}
        name = (data.get("[name]") or [None])[0]
        level_req = (data.get("[required level]") or [None])[0]
        skl_type = data.get("[type]")
        if isinstance(skl_type, dict) and skl_type:
            skl_type = next(iter(skl_type))
        unresolved = []
        nut_rel, state_id, flag_index = None, None, None
        pushes = push.get(sid, [])
        if pushes:
            p0 = pushes[0]
            nut_rel = "sqr/" + p0["nut"].replace("character/", "character/", 1)
            nut_rel = nut_rel if nut_rel.endswith(".nut") else nut_rel
            nut_rel = nut_rel + ".txt"
            state_id = p0["state_id"]
        branches, nut_lines = ([], [])
        if nut_rel and os.path.exists(os.path.join(TEXT, nut_rel)):
            branches, nut_lines = skill_nut_info(nut_rel, consts, motions, atks)

        rec = {
            "skill_id": sid, "name": name or stem, "level_req": level_req,
            "skl": skl["path"] if skl else None,
            "skl_type": skl_type,
            "state_id": state_id, "nut": nut_rel if branches else None,
            "flag_index": flag_index,
            "ani": None, "ani_motion": None, "ani_index": None,
            "ani_frames": [], "ani_frame_count": None, "ani_frame_ms": None,
            "ani_flags": [],
            "attack_info_index": None, "atk": None, "damage_bonus": None,
            "atk_fields": {}, "hitbox": None, "boxes": [],
            "ani_source": None, "atk_source": None,
            "substates": [],
            "unresolved": unresolved,
        }

        if branches:
            # 有 nut：直接用脚本里的下标（权威）
            best = next((b for b in branches if b["atk_index"] is not None), branches[0])
            seen_ss = set()
            subs = []
            for b in branches:
                if b["substate"] in seen_ss:
                    continue
                if b["ani_index"] is None and b["atk_index"] is None:
                    continue
                seen_ss.add(b["substate"])
                subs.append({"substate": b["substate"], "ani_const": b["ani_const"],
                             "ani_index": b["ani_index"], "ani": b["ani"],
                             "atk_const": b["atk_const"], "atk_index": b["atk_index"],
                             "atk": b["atk"]})
            rec["substates"] = subs
            rec["ani_index"] = best["ani_index"]
            rec["ani_motion"] = motions[best["ani_index"]] if best["ani_index"] is not None else None
            rec["attack_info_index"] = best["atk_index"]
            rec["atk"] = best["atk"]
            rec["ani_source"] = "nut %s substate %s" % (nut_rel, best["substate"])
            rec["atk_source"] = "nut %s substate %s" % (nut_rel, best["substate"])
            if best["ani_const"]:
                m = re.search(r"<-\s*(\d+)", nut_rel)  # placeholder, unused
            # flag：nut 的 onKeyFrameFlag 处理的 flag 值拿不到（实参由 ani 决定），记 None
            rec["flag_index"] = None
            if best["ani_index"] is None:
                unresolved.append("nut 里的 ani 常量无法解析：%r" % best["ani_const"])
            if best["atk_index"] is None:
                unresolved.append("nut 里的 atk 常量无法解析：%r" % best["atk_const"])
        else:
            unresolved.append("无 .nut（引擎内置技能，skillId→动作下标不在数据里）")
            hint = MOTION_HINT.get(stem)
            if hint:
                cands, why = hint
                chosen = None
                for c in cands:
                    if not (0 <= c < len(motions)):
                        continue
                    abs_c, _ = resolve_ani(motions[c], ani_index)
                    det_c = ani_detail(abs_c)
                    if det_c and det_c.get("attack_frames"):
                        chosen = c
                        break
                if chosen is None:
                    chosen = cands[0]
                rec["ani_index"] = chosen
                rec["ani_motion"] = motions[chosen] if 0 <= chosen < len(motions) else None
                rec["ani_source"] = "名字/常量推断（候选 %s）：%s" % (cands, why)
            else:
                unresolved.append("etc motion 里无同名动作")
            atk_name = ATK_NAME_HINT.get(stem)
            if atk_name:
                for i, a in enumerate(atks):
                    if a.split("/")[-1].lower() == (atk_name + ".atk").lower():
                        rec["attack_info_index"] = i
                        rec["atk"] = "character/swordman/" + a
                        rec["atk_source"] = "etc attack info[%d] 名字匹配 %s" % (i, atk_name)
                        break
                if rec["attack_info_index"] is None:
                    low = atk_name.lower()
                    pref = [(i, a) for i, a in enumerate(atks)
                            if a.split("/")[-1].lower().startswith(low)]
                    if pref:
                        i, a = pref[0]
                        rec["attack_info_index"] = i
                        rec["atk"] = "character/swordman/" + a
                        rec["atk_source"] = "etc attack info[%d] 前缀匹配 %s（同名不存在，取同前缀首个）" % (i, atk_name)
                    else:
                        unresolved.append("etc attack info 里找不到 %s.atk（及其前缀变体）" % atk_name)

        # ani → 帧表
        if rec["ani_motion"]:
            ani_abs, why = resolve_ani(rec["ani_motion"], ani_index)
            det = ani_detail(ani_abs)
            if det and det.get("frame_count"):
                rec["ani"] = ani_abs.replace(TEXT + "/", "")
                rec["ani_frames"] = det["attack_frames"]
                rec["ani_frame_count"] = det["frame_count"]
                rec["ani_frame_ms"] = det["total_ms"]
                rec["ani_flags"] = det["flags"]
                if det["flags"]:
                    seen = []
                    for fl in det["flags"]:
                        if fl["flag"] not in seen:
                            seen.append(fl["flag"])
                    rec["flag_index"] = seen if len(seen) > 1 else seen[0]
                rec["boxes"] = det["boxes"]
                rec["hitbox"] = det["boxes"][0] if det["boxes"] else None
                if not det["attack_frames"]:
                    unresolved.append("身体层 ani 无 [ATTACK BOX]（判定盒不在动画里）")
                if not det["flags"]:
                    unresolved.append("ani 无 [FLAG]（无 flagIndex 帧）")
            else:
                unresolved.append("ani 文件解析失败：%s" % rec["ani_motion"])

        # atk 伤害字段
        if rec["atk"]:
            key = rec["atk"].lower()
            ad = atk_idx.get(key)
            if ad is None and not key.startswith("character/"):
                k2 = "character/swordman/" + key
                if k2 in atk_idx:
                    ad = atk_idx[k2]
                    rec["atk"] = k2
            ad = atk_fields(ad)
            rec["atk_fields"] = ad
            rec["damage_bonus"] = ad.get("damage_bonus")
            if not ad:
                unresolved.append("atk 内容为空/未命中")
        records.append(rec)

    for rec in records:
        attach_weapon_layer(rec, widx)

    stats = classify(records)
    return records, stats


BODY_NO_BOX = "身体层 ani 无 [ATTACK BOX]"


def attach_weapon_layer(rec, widx):
    """挂武器层 ani / 攻击盒。

    普攻 1/2 段的攻击盒只在武器动画里（身体层 db 3 块 = 头/躯干/腿的受击盒）。
    两层帧数与时长逐一相等，是叠加关系：身体给姿态、武器给轨迹与判定。
    """
    rec["weapon_ani"] = None
    rec["weapon_boxes"] = []
    rec["weapon_ani_frames"] = []
    rec["hitbox_source"] = "none"   # 取值集合固定为 body | weapon | none
    motion = rec.get("ani_motion")
    if not motion:
        return
    stem = motion.replace("\\", "/").split("/")[-1]
    stem = stem[:-4] if stem.lower().endswith(".ani") else stem
    w = weapon_layer_ani(stem, widx)
    if not w:
        return
    det = ani_detail(w)
    if not det:
        return
    rec["weapon_ani"] = w.replace(TEXT + "/", "")
    rec["weapon_boxes"] = det.get("boxes", [])
    rec["weapon_ani_frames"] = det.get("attack_frames", [])
    if not rec.get("boxes") and rec["weapon_boxes"]:
        rec["boxes"] = rec["weapon_boxes"]
        rec["hitbox"] = rec["weapon_boxes"][0]
        rec["hitbox_source"] = "weapon"
        rec["unresolved"] = [u for u in rec["unresolved"] if not u.startswith(BODY_NO_BOX)]
        if not any("武器层" in u for u in rec["unresolved"]):
            rec["unresolved"].append("攻击盒取自武器层 ani（身体层无盒，帧号与身体层一一对应）")
    elif rec.get("boxes"):
        rec["hitbox_source"] = "body"


def classify(records):
    stats = {"total": len(records), "full": 0, "no_nut": 0, "no_ani": 0,
             "no_atk": 0, "no_hitbox": 0, "no_flag": 0, "passive_only": 0}
    for r in records:
        ok = True
        if not r["nut"]:
            stats["no_nut"] += 1
            ok = False
        if not r["ani"]:
            stats["no_ani"] += 1
            ok = False
        if not r["atk"]:
            stats["no_atk"] += 1
            ok = False
        if not r["hitbox"]:
            stats["no_hitbox"] += 1
        if not r["ani_flags"]:
            stats["no_flag"] += 1
        if ok:
            stats["full"] += 1
    return stats


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", default=os.path.join(META, "skill_anim_map.json"))
    ap.add_argument("--dump", type=int, default=None)
    args = ap.parse_args(argv)

    records, stats = build()
    if args.dump is not None:
        for r in records:
            if r["skill_id"] == args.dump:
                print(json.dumps(r, ensure_ascii=False, indent=1))
                return 0
        print("skill", args.dump, "not in slice", file=sys.stderr)
        return 1

    payload = {
        "source": {
            "chr": "character/swordman/swordman.chr（[etc motion] 281 项 / [etc attack info] 155 项）",
            "nut": "sqr/character/swordman_load_state.nut（pushState 注册表）",
            "const": "sqr/character/swordman_jg/swordman_value.nut（权威常量表）",
            "ani": "export/text/**/*.ani.bin + tools/ani_parser.py",
            "atk": "export/structured/atk.jsonl.gz",
        },
        "legend": {
            "ani_index": "chr [etc motion] 的 0 基下标",
            "attack_info_index": "chr [etc attack info] 的 0 基下标",
            "hitbox": "(x,y,z,w,h,d) 相对坐标+宽高深，来自 .ani [ATTACK BOX]",
            "flag": "ani 帧的 [FLAG]；65534=无 flag 哨兵",
        },
        "stats": stats,
        "skills": records,
    }
    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    with open(args.json, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    print("wrote", args.json)
    print(json.dumps(stats, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
