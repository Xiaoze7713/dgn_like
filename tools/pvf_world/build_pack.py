#!/usr/bin/env python3
"""把 latest PVF 的城镇 / 副本 / 房间 / 地砖编译成紧凑 JSON 内容包。

设计原则
--------
* 运行时（GDScript）**不碰 PVF token 流**：新格式 PVF 是 AES 分段 + 内层 nkpi，
  逐文件实时解析在客户端里不现实。这里离线把「加载地图所需的全部结构」压成 JSON，
  图片仍然运行时从 ImagePacks2（NPK）按 `[IMAGE]` 给的 img 路径 + 帧号读。
* 全部字段原样保留自 PVF（不做语义推测），语义留给 GDScript 侧按类型加载器解释；
  这样以后发现某字段含义时只改加载器，不用重编内容包。
* 一次只编一个「可玩切片」：指定城镇 + 它门口的副本，避免整库 34k 房间。

产出（默认写到 Godot 工程 assets/pvf/world/）
---------------------------------------------
    index.json                城镇 / 副本目录 + 编译统计
    towns/<id>.json           城镇：area 列表（map 路径、类型、迷你地图框、副本 id…）
    dungeons/<id>.json        副本：多套 maze（size/greed 格网/start/boss/map 绑定）
    maps/<key>.json           房间：地砖、通道、可走区、怪/NPC/被动对象/背景动画…
    tiles/<key>.json          地砖：img + 帧、img pos、pass type 逐格通行

用法
----
    python3 tools/pvf_world/build_pack.py --town hendonmyre --town centralpark
    python3 tools/pvf_world/build_pack.py --town hendonmyre --all-mazes --out /tmp/pack
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import defaultdict
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
from pvf_script import Pvf, parse  # noqa: E402

DEFAULT_OUT = "/mnt/e/godot_proj/dnf_like/assets/pvf/world"

# ---- 语义登记表（只登记 PVF 里出现的「控制 token」，其余一律按位置解释）-------

# .twn [area] 的类型 token；`[gate]`=城镇出口，`[dungeon gate]`=副本入口
AREA_TYPE_TOKENS = {
    "[normal]", "[gate]", "[dungeon gate]", "[safe zone]", "[housing]",
    "[open party list area]", "[minimap rect]", "[/minimap rect]",
}

# .dgn [greed] 的 15 个连通性 token（tagdict ext='dgn'/'map' 官方注释）
GREED_EXITS = {
    "BB": "r", "EE": "l", "CC": "u", "II": "d",
    "DD": "ru", "GG": "lu", "JJ": "rd", "MM": "ld",
    "NN": "ldr", "HH": "lur", "LL": "udr", "KK": "ud",
    "FF": "lr", "PP": "lrud", "AA": "",
}

# .dgn [map specification] 的条目类型 token
MAPSPEC_TOKENS = {"map", "boss", "layered"}

# .map [monster] 里的控制 token
MONSTER_TOKENS = {
    "[fixed]", "[half]", "[ratio]",
    "[normal]", "[champion]", "[super champion]", "[boss]",
    "[NPC]",
}


def tok_str(t) -> str:
    return str(t.value)


def node_strs(node) -> list[str]:
    return [] if node is None else [tok_str(t) for t in node.values]


def node_ints(node) -> list[int]:
    return [] if node is None else [int(t.value) for t in node.values if t.kind in ("int", "float")]


def lower_p(path: str) -> str:
    return path.replace("\\", "/").lower()


def key_of(path: str) -> str:
    return re.sub(r"[^a-z0-9._-]+", "_", lower_p(path))


def find_deep(node, label: str):
    """深度优先找第一个 label（`.act` 的 `[BASE ANI]` 就嵌在 `[MOTION]` 里）。"""
    if node.label == label:
        return node
    for c in node.children:
        got = find_deep(c, label)
        if got is not None:
            return got
    return None


def load_id_list(pvf: Pvf, path: str) -> dict[str, str]:
    """读 `list/*.lst`（`129 `Foo/Bar.obj``）：id -> 路径（原样大小写，查库时再 lower）。"""
    body = pvf.text(path)
    if not body:
        return {}
    return dict(re.findall(r"(\d+)\s+`([^`]+)`", body))


class StringTable:
    """离线解析 `<table::key>` 名称引用。

    `list/n_string.lst` 把表号映射到 `String/*.chn.str`；这些文件在 `files` 表里
    是 dtype=3 的 UTF-16LE 文本（不在 `text` 表里）。运行时不再碰字符串表，
    编译期把 NPC / 城镇 / 地区名字直接写成纯文本。
    """

    def __init__(self, pvf: Pvf) -> None:
        self.pvf = pvf
        self._files = load_id_list(pvf, "list/n_string.lst")
        self._tables: dict[str, dict[str, str]] = {}

    def _table(self, index: str) -> dict[str, str]:
        if index in self._tables:
            return self._tables[index]
        rel = self._files.get(str(index), "")
        out: dict[str, str] = {}
        raw = self.pvf.data(lower_p(rel).lstrip("/")) if rel else None
        if raw:
            body = raw.decode("utf-16-le", errors="ignore").lstrip("\ufeff")
            for line in body.splitlines():
                line = line.strip()
                if not line or line.startswith("//") or ">" not in line:
                    continue
                key, value = line.split(">", 1)
                out[key.strip()] = value.strip()
        self._tables[index] = out
        return out

    def resolve(self, raw) -> str:
        text = str(raw).strip()
        m = re.fullmatch(r"<(\d+)::([^>]+)>", text)
        if not m:
            return text
        return self._table(m.group(1)).get(m.group(2), text)

    def resolve_many(self, values) -> list[str]:
        return [self.resolve(v) for v in values]


def resolve_rel(pvf: Pvf, base_dir: str, rel: str) -> str | None:
    """相对引用：先相对引用者目录，再相对 PVF 根（两种基准在 latest 里都存在）。"""
    cand = lower_p(rel).lstrip("/")
    for full in (base_dir + cand, cand):
        full = re.sub(r"/\./", "/", full)
        while "/../" in full:
            full = re.sub(r"[^/]+/\.\./", "", full, count=1)
        if pvf.exists(full):
            return full
    return None


# --------------------------------------------------------------------------- #
# 引用解析
# --------------------------------------------------------------------------- #

class RefIndex:
    """把 `.dgn` 的格子（map id 或目录约定）解析成 `map/**.map` 路径。

    实测 latest 有两种并存约定：
      1. `map/<副本文件名>/<mapid>(x,y)<role>.map`  —— 目录名 = 副本 basename
      2. `[map specification]` 的 4/5 元组给出 map id，文件名里含这个 id
         （`655811_(0,0).act`、`q7939_655811.map`、`55605_1776(1,0).map`）
    两者都要试，命中即止；坐标 `(x,y)` 出现时用来消歧。
    """

    def __init__(self, pvf: Pvf, by_id: dict[str, str] | None = None) -> None:
        self.by_dir: dict[str, list[str]] = defaultdict(list)
        self.by_num: dict[str, list[str]] = defaultdict(list)
        # `list/map.lst` 是官方 id → 路径表（29,115 条），有它就是最权威的解析
        self.by_id: dict[str, str] = {}
        for mid, rel in (by_id or {}).items():
            full = lower_p(rel).lstrip("/")
            self.by_id[str(mid)] = full
        for (path,) in pvf.conn.execute(
            "select path from files where path like 'map/%' and path like '%.map'"
        ):
            parts = path.split("/")
            self.by_dir[parts[-2]].append(path)
            for num in re.findall(r"\d+", parts[-1][:-4]):
                self.by_num[num].append(path)
        self.stats = defaultdict(int)

    def _coord(self, path: str):
        m = re.search(r"\((\d+)[,.](\d+)\)", path)
        return (int(m.group(1)), int(m.group(2))) if m else None

    def resolve(self, dgn_path: str, x: int, y: int, ids: list[str], pvf: Pvf | None = None) -> str | None:
        # ① list/map.lst 官方 id 表（最权威）
        for mid in ids:
            got = self.by_id.get(str(mid))
            if got and (pvf is None or pvf.exists(got)):
                self.stats["id_list"] += 1
                return got
        base = dgn_path.rsplit("/", 1)[-1][:-4]
        cands: list[str] = list(self.by_dir.get(base, ()))

        coord_ok = [p for p in cands if self._coord(p) == (x, y)]
        if coord_ok:
            self.stats["dir_xy"] += 1
            return self._pick_role(coord_ok)

        for mid in ids:
            hits = [p for p in self.by_num.get(str(mid), ()) if self._coord(p) in (None, (x, y))]
            if hits:
                self.stats["id"] += 1
                return self._pick_role(hits)

        if cands:
            self.stats["dir_any"] += 1
            return self._pick_role(cands)
        self.stats["miss"] += 1
        return None

    def resolve_dircell(self, dgn_path: str, x: int, y: int, w: int, h: int) -> str | None:
        """没有任何 map id 的副本：靠 `map/<dgn basename>/` 目录里 `(x,y)` 命名反查。
        目录里没有坐标就只能按「文件数 == 格子数」时的行优先顺序，否则放弃。"""
        base = dgn_path.rsplit("/", 1)[-1][:-4]
        cands = self.by_dir.get(base, [])
        coord_ok = [p for p in cands if self._coord(p) == (x, y)]
        if coord_ok:
            self.stats["dir_xy"] += 1
            return self._pick_role(coord_ok)
        if len(cands) == w * h and 0 <= y * w + x < len(cands):
            self.stats["dir_order"] += 1
            return sorted(cands)[y * w + x]
        self.stats["miss"] += 1
        return None

    @staticmethod
    def _pick_role(paths: list[str]) -> str:
        # 同名多候选时优先 start / boss，其次字典序最小（保证可复现）
        for want in ("start", "boss"):
            for p in paths:
                if want in p.rsplit("/", 1)[-1]:
                    return p
        return sorted(paths)[0]


# --------------------------------------------------------------------------- #
# 各类文件 -> dict
# --------------------------------------------------------------------------- #

def _subtree_values(node):
    """一个 area 子树里所有 token 值（先父后子，保持出现顺序）。"""
    yield node.values
    for child in node.children:
        yield from _subtree_values(child)


def parse_areas(root) -> list[dict]:
    """解析 `[area]`。

    latest 的 area 类型/minimap 不再平铺在 [area] 自身，而是嵌在
    `[permission]`，或者作为 `[open party list area]` / `[extra dungeon gate]`
    这样的兄弟节点；所以这里扫整个 area 子树的 token，再按优先级选类型。
    `[phase]` 是同一 area 的天气/版本变体，只保留 base map，另记 phase 列表。
    """
    out = []
    type_rank = {"dungeon gate": 5, "gate": 4, "normal": 3, "safe zone": 2,
                 "housing": 1, "open party list area": 0}
    for node in root.all("[area]"):
        area = {"index": None, "map": None, "type": "normal", "args": [],
                "minimap": None, "phase": []}
        first = node.values
        if len(first) >= 2:
            area["index"] = int(first[0].value) if first[0].kind in ("int", "float") else first[0].value
            area["map"] = tok_str(first[1])

        best: tuple[int, str, list] | None = None
        for values in _subtree_values(node):
            i = 0
            while i < len(values):
                s = tok_str(values[i])
                if s == "[minimap rect]" and i + 4 < len(values):
                    area["minimap"] = [int(values[i + k].value) for k in range(1, 5)]
                    i += 5
                    continue
                if s == "[/minimap rect]":
                    i += 1
                    continue
                bare = s[1:-1] if s.startswith("[") and s.endswith("]") else ""
                if bare in type_rank:
                    args = []
                    i += 1
                    while i < len(values) and not tok_str(values[i]).startswith("["):
                        args.append(values[i].value)
                        i += 1
                    cand = (type_rank[bare], bare, args)
                    if best is None or cand[0] > best[0]:
                        best = cand
                    continue
                i += 1
        if best is not None:
            area["type"], area["args"] = best[1], best[2]

        for child in node.children:
            if child.label == "[phase]":
                area["phase"] = node_strs(child)
                break
        if area["map"]:
            area["map"] = "map/" + lower_p(area["map"]).lstrip("/")
        out.append(area)
    return out


def compile_town(pvf: Pvf, path: str, strings: StringTable, town_id: int) -> dict:
    root = parse(pvf.tokens(path))
    town = {
        "path": path,
        "id": town_id,
        "name": node_strs(root.first("[name]"))[:1],
        "sub_name": node_strs(root.first("[sub name]"))[:1],
        "name_text": strings.resolve_many(node_strs(root.first("[name]"))[:1]),
        "sub_name_text": strings.resolve_many(node_strs(root.first("[sub name]"))[:1]),
        "areas": parse_areas(root),
    }
    town["dungeon_gate_ids"] = [
        str(a["args"][0]) for a in town["areas"]
        if a["type"] == "dungeon gate" and a["args"]
    ]
    return town


def compile_region(pvf: Pvf, path: str, strings: StringTable) -> dict:
    root = parse(pvf.tokens(path))
    return {
        "path": path,
        "name": node_strs(root.first("[name]"))[:1],
        "name_text": strings.resolve_many(node_strs(root.first("[name]"))[:1]),
        "towns": [int(v) for v in node_ints(root.first("[towns]"))],
        "minimap": node_strs(root.first("[minimap]"))[:1],
    }


def compile_npc(pvf: Pvf, npc_id: int, npc_path: str, strings: StringTable,
                ctx: dict) -> dict | None:
    """`.npc` → 名字 + 站立动画。动画引用是相对 `npc/` 的 `Animation/*.ani`。"""
    if not pvf.exists(npc_path):
        return None
    root = parse(pvf.tokens(npc_path))
    base = npc_path.rsplit("/", 1)[0] + "/"
    ani_rel = (node_strs(root.first("[field animation]")) or [""])[0].strip("`")
    ani_path = None
    if ani_rel:
        ani_path = resolve_rel(pvf, base, ani_rel)
        if ani_path is None:
            ani_path = resolve_rel(pvf, "npc/", ani_rel)
        if ani_path and ctx.get("anis") is not None and ani_path not in ctx["anis"]:
            try:
                ctx["anis"][ani_path] = compile_ani(pvf, ani_path)
            except Exception:  # noqa: BLE001
                ani_path = None
    face = node_strs(root.first("[small face]"))
    rec = {
        "id": npc_id,
        "path": lower_p(npc_path),
        "name": strings.resolve_many(node_strs(root.first("[name]"))[:1]),
        "field_name": strings.resolve_many(node_strs(root.first("[field name]"))[:1]),
        "role": (node_strs(root.first("[role]")) or [""])[0].strip("[]"),
        "ani": ani_path,
        "face": {"img": face[0].strip("`") if face else "", "frame": int(face[1]) if len(face) > 1 else 0},
    }
    return rec


def split_mazes(root) -> tuple[dict, list[dict]]:
    """`.dgn` 的 `[maze info]` 是一个**没有子节点的段标记**，后随
    size / greed / map specification / start map / boss map 等同级字段。
    所以按出现顺序切段，而不是找它的 children。"""
    meta: dict = {}
    mazes: list[dict] = []
    cur: dict | None = None
    for child in root.children:
        label = child.label
        if label == "[maze info]":
            cur = {"size": None, "greed": None, "cells": [], "start": [], "boss": []}
            mazes.append(cur)
            continue
        target = cur if cur is not None else meta
        key = label.strip("[]")
        if label == "[map specification]":
            target.setdefault("spec", []).extend(parse_map_spec(child))
        elif label == "[boss map specification]":
            target.setdefault("boss_spec", []).extend(parse_map_spec(child))
        elif label == "[size]":
            target["size"] = node_ints(child)[:2]
        elif label == "[greed]":
            target["greed"] = node_strs(child)[0] if child.values else ""
        elif label == "[start map]":
            v = node_ints(child)
            target["start"].extend([v[i:i + 2] for i in range(0, len(v) - 1, 2)])
        elif label == "[boss map]":
            v = node_ints(child)
            target["boss"].extend([v[i:i + 2] for i in range(0, len(v) - 1, 2)])
        elif key in ("minimum required level", "basis level", "experience increasing point",
                     "recommend equipment", "champion", "difficulty level", "background pos",
                     "pathgate object", "quest connection", "difficulty", "escape hell",
                     "designate dungeon difficulty", "no amplify drop rarity"):
            target.setdefault(key, []).extend(
                node_strs(child) if child.values and child.values[0].kind in ("str", "val")
                else node_ints(child)
            )
        elif child.values and not child.children:
            raw = node_strs(child)
            target.setdefault(key, []).extend(raw)
    return meta, mazes


def parse_map_spec(node) -> list[dict]:
    """`map <x> <y> <id> [<id>…]` / `boss x y id` / `layered x y id…` —— 类型 token 起头，
    同一格子允许挂多个候选 id（DNF 的房间随机就是从这里来的）。"""
    out: list[dict] = []
    cur: dict | None = None
    for raw in node_strs(node):
        s = str(raw)
        if s in MAPSPEC_TOKENS:
            cur = {"kind": s, "x": None, "y": None, "ids": []}
            out.append(cur)
            continue
        if cur is None:
            continue
        if cur["x"] is None:
            cur["x"] = int(s)
        elif cur["y"] is None:
            cur["y"] = int(s)
        else:
            cur["ids"].append(s)
    return out


def compile_dungeon(pvf: Pvf, path: str, refs: RefIndex, all_mazes: bool) -> dict:
    root = parse(pvf.tokens(path))
    meta, mazes = split_mazes(root)
    if not all_mazes:
        mazes = mazes[:1]
    for maze in mazes:
        cells = []
        seen = set()
        for spec in maze.get("spec", []) + maze.get("boss_spec", []):
            target = refs.resolve(path, spec["x"], spec["y"], spec["ids"], pvf)
            cells.append({**spec, "map": target, "approx": target is not None and not spec["ids"]})
            seen.add((spec["x"], spec["y"]))
        rows = maze.get("greed_rows") or []
        if rows and rows[0].replace(" ", ""):
            w, h = len(rows[0].replace(" ", "")) // 2, len(rows)
        elif maze.get("size"):
            w, h = maze["size"][:2]
        if rows or maze.get("size"):
            for y in range(h):
                for x in range(w):
                    if (x, y) in seen:
                        continue
                    target = refs.resolve_dircell(path, x, y, w, h)
                    if target:
                        cells.append({"kind": "dir", "x": x, "y": y, "ids": [],
                                      "map": target, "approx": True})
        maze["cells"] = cells
        maze["greed_rows"] = split_greed(maze.get("greed") or "")
        maze.pop("spec", None)
        maze.pop("boss_spec", None)
    dgn_id = path.rsplit("/", 1)[-1][:-4]
    return {
        "path": path,
        "id": dgn_id,
        "name": node_strs(root.first("[name]")) or meta.get("name", []),
        "explain": node_strs(root.first("[explain]")) or meta.get("explain", []),
        "min_level": (meta.get("minimum required level") or [None])[0],
        "basis_level": (meta.get("basis level") or [None])[0],
        "mazes": mazes,
        "meta": {k: v for k, v in meta.items() if k not in ("name", "explain")},
    }


def split_greed(text: str) -> list[str]:
    return [row.strip() for row in re.split(r"[\r\n]+", text.strip()) if row.strip()]


def greed_cells(rows: list[str]) -> list[list[str]]:
    grid = []
    for row in rows:
        clean = row.replace(" ", "")
        grid.append([clean[i:i + 2] for i in range(0, len(clean) - 1, 2)])
    return grid


_IMPORT_STACK: set[str] = set()


def compile_map(pvf: Pvf, path: str, refs: RefIndex, ctx: dict | None = None) -> dict:
    ctx = ctx or {}
    root = parse(pvf.tokens(path))
    base_dir = path.rsplit("/", 1)[0] + "/"

    def resolve_til(p: str) -> str | None:
        cand = lower_p(p)
        for full in (base_dir + cand, "map/" + cand, cand):
            if pvf.exists(full):
                return full
        return None

    tiles = [resolve_til(t) for t in node_strs(root.first("[tile]"))] if root.first("[tile]") else []
    ext_node = root.first("[extended tile]")
    ext: list[str] = []
    ext_map: list[int] = []
    if ext_node is not None:
        if ext_node.children:
            # [tile files] 里是「序号 + 路径」交替，[tile map] 是「每个基础地砖列用第几块扩展地砖」
            by_idx: dict[int, str] = {}
            for files in ext_node.all("[tile files]"):
                toks = files.values
                for i in range(len(toks) - 1):
                    if toks[i].kind == "int" and toks[i + 1].kind == "str":
                        got = resolve_til(str(toks[i + 1].value))
                        if got:
                            by_idx[int(toks[i].value)] = got
            ext = [by_idx[k] for k in sorted(by_idx)]
            for tm in ext_node.all("[tile map]"):
                ext_map = [int(tok.value) for tok in tm.values if tok.kind == "int"]
        else:
            ext = [t for t in (resolve_til(x) for x in node_strs(ext_node)) if t]

    data = {
        "path": path,
        "type": (node_strs(root.first("[type]")) or [""])[0].strip("[]"),
        "greed": (node_strs(root.first("[greed]")) or [""])[0],
        "dungeon": (node_ints(root.first("[dungeon]")) or [None])[0],
        "name": node_strs(root.first("[map name]")),
        "tiles": tiles,
        "extended_tiles": ext,
        "extended_map": ext_map,
        "sight": {name: (node_ints(root.first(f"[{label}]")) or [None])[0]
                  for name, label in (("far", "far sight scroll"),
                                      ("middle", "middle sight scroll"),
                                      ("near", "near sight scroll"))},
        "pathgate": node_ints(root.first("[pathgate pos]")) if root.first("[pathgate pos]") else [],
        "way_point": node_ints(root.first("[way point]")) if root.first("[way point]") else [],
        # map 的第一行，背景层的垂直锚点（实测恒 80）：背景 y = 画布 y + background_pos
        "background_pos": (node_ints(root.first("[background pos]")) or [0])[0],
        "town_movable": node_ints(root.first("[town movable area]")) if root.first("[town movable area]") else [],
        "town_movable_name": node_strs(root.first("[town movable area name]")) if root.first("[town movable area name]") else [],
        "virtual_movable": node_ints(root.first("[virtual movable area]")) if root.first("[virtual movable area]") else [],
        "teleport": [],
        "monsters": [],
        "npcs": [],
        "objects": [],
        "anims": [],
        "background_anims": [],
        "sound": node_strs(root.first("[sound]")) if root.first("[sound]") else [],
    }

    for node in root.all("[teleport area option]"):
        data["teleport"].append(node_strs(node))

    # [passive object] = (对象 id, x, y, z) —— 间隔固定 4
    po = root.first("[passive object]")
    if po is not None:
        v = node_ints(po)
        obj_ids: dict[str, str] = ctx.get("obj_ids") or {}
        for i in range(0, len(v) - 3, 4):
            oid = v[i]
            rel = obj_ids.get(str(oid))
            obj_path = lower_p(rel).lstrip("/") if rel else None
            if obj_path and not pvf.exists(obj_path):
                obj_path = None
            rec = {"id": oid, "x": v[i + 1], "y": v[i + 2], "z": v[i + 3],
                   "obj": obj_path, "ani": None, "layer": "normal", "pass_type": ""}
            if obj_path and ctx.get("objects") is not None:
                if obj_path not in ctx["objects"]:
                    try:
                        ctx["objects"][obj_path] = compile_object(pvf, oid, obj_path)
                    except Exception:  # noqa: BLE001
                        ctx["objects"][obj_path] = None
                od = ctx["objects"].get(obj_path) or {}
                rec["layer"] = od.get("layer", "normal")
                rec["pass_type"] = od.get("pass_type", "")
                rec["ani"] = od.get("base_ani")
                if rec["ani"] and ctx.get("anis") is not None and rec["ani"] not in ctx["anis"]:
                    try:
                        ctx["anis"][rec["ani"]] = compile_ani(pvf, rec["ani"])
                    except Exception:  # noqa: BLE001
                        pass
            data["objects"].append(rec)

    # [animation] = (ani 路径, 图层 token, x, y, z) —— 间隔固定 5
    # 这是地图的「装饰层」：墙、门、铁轨、花草、火光…（不是被动对象）
    an = root.first("[animation]")
    if an is not None:
        v = node_strs(an)
        for i in range(0, len(v) - 4, 5):
            ani_path = resolve_rel(pvf, base_dir, v[i])
            data["anims"].append({
                "ani": v[i], "path": ani_path, "layer": v[i + 1].strip("[]"),
                "x": int(v[i + 2]), "y": int(v[i + 3]), "z": int(v[i + 4]),
            })
            if ani_path and ctx.get("anis") is not None and ani_path not in ctx["anis"]:
                try:
                    ctx["anis"][ani_path] = compile_ani(pvf, ani_path)
                except Exception:  # noqa: BLE001
                    pass

    # [NPC] = (id, 朝向 token, x, y, z)
    npc = root.first("[NPC]")
    if npc is not None:
        v = node_strs(npc)
        data["npcs"] = [
            {"id": v[i], "dir": v[i + 1], "x": int(v[i + 2]), "y": int(v[i + 3]), "z": int(v[i + 4])}
            for i in range(0, len(v) - 4, 5)
        ]
        npc_ids: dict[str, str] = ctx.get("npc_ids") or {}
        for rec in data["npcs"]:
            rel = npc_ids.get(str(rec["id"]))
            if not rel:
                continue
            rel_l = lower_p(rel).lstrip("/")
            rec["path"] = rel_l
            if ctx.get("npcs") is not None and str(rec["id"]) not in ctx["npcs"]:
                got = compile_npc(pvf, int(rec["id"]), rel_l, ctx["strings"], ctx)
                if got is not None:
                    ctx["npcs"][str(rec["id"])] = got

    data["monsters"] = parse_monsters(root)
    data["background_anims"] = parse_bg_anims(root, pvf, base_dir, ctx)

    # [import script]：地图继承。官方语义是「本图没写的字段从被 import 的图取」，
    # 典型用法是城镇门口那种只写一行 import + 几个可走区的小文件。
    imp_node = root.first("[import script]")
    if imp_node is not None:
        imp = node_strs(imp_node)
        if imp:
            ref = lower_p(imp[0])
            data["import"] = ref
            parent_path = None
            for full in (base_dir + ref, "map/" + ref, ref):
                if pvf.exists(full):
                    parent_path = full
                    break
            if parent_path is None:
                data["import_missing"] = True
            if parent_path and path not in _IMPORT_STACK:
                _IMPORT_STACK.add(path)
                try:
                    parent = compile_map(pvf, parent_path, refs, ctx)
                finally:
                    _IMPORT_STACK.discard(path)
                for k, v in parent.items():
                    if k in ("path", "import"):
                        continue
                    if not data.get(k):
                        data[k] = v

    for key, val in list(data.items()):
        if isinstance(val, list) and all(x is None for x in val):
            data[key] = []
    return data


def parse_monsters(root) -> list[dict]:
    """`[monster]` 一个标签里可以塞 N 条记录，记录之间靠控制 token 分隔：
    `8×int` + `[fixed|half|ratio]` + 类型 token(`[normal|champion|super champion|boss]`)，
    类型前可以插 `[NPC] id 朝向 x y z`（官方：击杀该怪后 NPC 出现）。
    所以只能按 token 流式切，不能假设「一个 [monster] = 一只怪」。"""
    out: list[dict] = []
    for node in root.all("[monster]"):
        vals = list(node.values)
        i = 0
        while i < len(vals):
            ints: list[int] = []
            while i < len(vals) and len(ints) < 8 and vals[i].kind in ("int", "float"):
                ints.append(int(vals[i].value))
                i += 1
            if len(ints) < 8:
                break
            rec = {
                "id": ints[0], "auto": ints[1], "level": ints[2],
                "x": ints[3], "y": ints[4], "z": ints[5],
                "rdrop": ints[6], "sdrop": ints[7],
                "copy": "fixed", "type": "normal", "npc": None, "extra": [],
            }
            while i < len(vals):
                s = tok_str(vals[i])
                if s in ("[fixed]", "[half]", "[ratio]"):
                    rec["copy"] = s.strip("[]")
                    i += 1
                elif s in ("[normal]", "[champion]", "[super champion]", "[boss]"):
                    rec["type"] = s.strip("[]")
                    i += 1
                    break
                elif s == "[NPC]":
                    i += 1
                    npc = []
                    while i < len(vals) and len(npc) < 5 and vals[i].kind not in ("int",) or (
                            len(npc) < 5 and i < len(vals) and not tok_str(vals[i]).startswith("[")
                            and tok_str(vals[i]) not in MONSTER_TOKENS):
                        npc.append(vals[i].value)
                        i += 1
                    rec["npc"] = npc
                else:
                    rec["extra"].append(tok_str(vals[i]))
                    i += 1
                    if len(rec["extra"]) > 8:
                        break
            out.append(rec)
    return out


def parse_bg_anims(root, pvf: Pvf | None = None, base_dir: str = "",
                   ctx: dict | None = None) -> list[dict]:
    """`[background animation]` → `[ani info] filename layer order`。

    注意它在地图里常常**不存在**（赫顿玛尔/中央公园/科勒都没有），
    这时画面背景只能靠 `[animation]` 的远图层 + `[far/middle/near sight scroll]` 视差。
    """
    box = root.first("[background animation]")
    if box is None:
        return []
    out = []
    for info in box.all("[ani info]"):
        # 两种写法都见过：子标签形式（[filename]/[layer]/[order]）与平铺值形式
        fn = node_strs(info.first("[filename]")) if info.first("[filename]") else []
        lay = node_strs(info.first("[layer]")) if info.first("[layer]") else []
        order = node_strs(info.first("[order]")) if info.first("[order]") else []
        if not fn:
            v = node_strs(info)
            if not v:
                continue
            fn, lay, order = [v[0]], v[1:2], v[2:3]
        name = fn[0]
        path = resolve_rel(pvf, base_dir, name) if (pvf is not None and base_dir) else None
        out.append({"ani": name, "path": path,
                    "layer": lay[0].strip("[]") if lay else "",
                    "order": order[0].strip("[]") if order else ""})
        if path and ctx and ctx.get("anis") is not None and path not in ctx["anis"]:
            try:
                ctx["anis"][path] = compile_ani(pvf, path)
            except Exception:  # noqa: BLE001
                pass
    return out


def compile_ani(pvf: Pvf, path: str) -> dict:
    """`.ani`（文本）→ {path, loop, shadow, frame_max, frames:[{img,frame,dx,dy,delay}]}。

    latest 的 `.ani` 是**平铺**的：`[FRAMEnnn]` 之后跟着属于该帧的
    `[IMAGE EX]`/`[IMAGE POS]`/`[DELAY]`/`[INTERPOLATION]`/`[GRAPHIC EFFECT]`，
    没有 `[/FRAME]`，所以只能顺序扫描 + 状态机。
    """
    root = parse(pvf.tokens(path))
    img = ""
    loop = 0
    shadow = 0
    frame_max = 0
    frames: list[dict] = []
    cur: dict | None = None
    for node in root.children:
        lab = node.label
        if lab == "[IMAGE PATH]":
            v = node_strs(node)
            if v:
                img = v[0].strip("`")
        elif lab == "[FRAME MAX]":
            v = node_ints(node)
            frame_max = v[0] if v else 0
        elif lab == "[LOOP]":
            v = node_ints(node)
            loop = v[0] if v else 0
        elif lab == "[SHADOW]":
            v = node_ints(node)
            shadow = v[0] if v else 0
        elif lab.startswith("[FRAME") and lab != "[FRAME MAX]":
            cur = {"img": img, "frame": 0, "dx": 0, "dy": 0, "delay": 100,
                   "effect": "", "rgba": []}
            frames.append(cur)
        elif cur is not None:
            if lab == "[IMAGE EX]":
                v = node_ints(node)
                if len(v) >= 2:
                    cur["frame"] = v[1]           # (图像序号, NPK 帧号)
                cur["img"] = img
            elif lab == "[IMAGE POS]":
                v = node_ints(node)
                if len(v) >= 2:
                    cur["dx"], cur["dy"] = v[0], v[1]
            elif lab == "[DELAY]":
                v = node_ints(node)
                if v:
                    cur["delay"] = v[0]
            elif lab == "[GRAPHIC EFFECT]":
                v = node_strs(node)
                if v:
                    cur["effect"] = v[0].strip("`")
            elif lab == "[RGBA]":
                cur["rgba"] = node_ints(node)
    return {"path": path, "loop": loop, "shadow": shadow,
            "frame_max": frame_max or len(frames), "frames": frames}


def _collect(node, label: str, out: list) -> None:
    for c in node.children:
        if c.label == label:
            out.append(c)
        _collect(c, label, out)


def compile_object(pvf: Pvf, oid: int, path: str) -> dict:
    """被动对象：`.obj` → `[basic action]` `.act` → `[MOTION]` 的 base/sub ani。

    `[passive object] id` 先查 `list/passiveobject.lst` 拿到 `.obj` 路径；
    `.act` 与 `.ani` 的引用都是相对上一级文件所在目录（也有少数根相对）。
    """
    root = parse(pvf.tokens(path))
    base = path.rsplit("/", 1)[0] + "/"
    act_rel = (node_strs(root.first("[basic action]")) or [""])[0].strip("`")
    act_path = resolve_rel(pvf, base, act_rel) if act_rel else None
    base_ani = None
    sub_anis: list[dict] = []
    if act_path:
        ar = parse(pvf.tokens(act_path))
        abase = act_path.rsplit("/", 1)[0] + "/"
        bnode = find_deep(ar, "[BASE ANI]")
        if bnode is not None:
            v = node_strs(bnode)
            if v:
                base_ani = resolve_rel(pvf, abase, v[0].strip("`"))
        sub_nodes: list = []
        _collect(ar, "[SUB ANI]", sub_nodes)
        for snode in sub_nodes:
            v = node_strs(snode)
            if v:
                ap = resolve_rel(pvf, abase, v[0].strip("`"))
                if ap:
                    sub_anis.append({"ani": ap,
                                     "start": int(v[1]) if len(v) > 1 else 0,
                                     "count": int(v[2]) if len(v) > 2 else 1})
    return {
        "id": oid,
        "path": path,
        "name": node_strs(root.first("[name]")),
        "width": node_ints(root.first("[width]")) if root.first("[width]") else [],
        "layer": (node_strs(root.first("[layer]")) or [""])[0].strip("[]"),
        "pass_type": (node_strs(root.first("[pass type]")) or [""])[0].strip("[]"),
        "basic_action": act_path,
        "base_ani": base_ani,
        "sub_anis": sub_anis,
    }


def compile_tile(pvf: Pvf, path: str) -> dict:
    root = parse(pvf.tokens(path))
    img = node_strs(root.first("[IMAGE]")) if root.first("[IMAGE]") else []
    pass_node = root.first("[pass type]")
    vals = node_ints(pass_node) if pass_node is not None else []
    return {
        "path": path,
        "img": img[0] if img else "",
        "frame": int(img[1]) if len(img) > 1 else 0,
        "img_pos": (node_ints(root.first("[img pos]")) or [0])[0],
        "tile_type": (node_strs(root.first("[tile type]")) or [""])[0].strip("[]"),
        "cols": 14,
        "rows": len(vals) // 14,
        "pass": vals,
    }


# --------------------------------------------------------------------------- #
# 主流程
# --------------------------------------------------------------------------- #

def load_dungeon_registry(pvf: Pvf) -> dict[str, str]:
    """`dungeon/tutorial/dungeon.lst`：`id \`Act1/Lorien.dgn\`` —— 副本 id 的全局表。
    latest 里没有 `worldmap/*.lst`，这张表就是 `.twn [dungeon gate] N` 的解析入口。"""
    reg: dict[str, str] = {}
    for cand in ("dungeon/dungeon.lst", "dungeon/tutorial/dungeon.lst"):
        if not pvf.exists(cand):
            continue
        txt = pvf.text(cand) or ""
        if not txt:
            continue
        base_dirs = [cand.rsplit("/", 1)[0] + "/", "dungeon/", ""]
        for idx, rel in re.findall(r"(\d+)\s+`([^`]+)`", txt):
            rel_l = lower_p(rel)
            for base in base_dirs:
                full = lower_p(base + rel_l) if base else rel_l
                if pvf.exists(full):
                    reg[idx] = full
                    break
        if reg:
            break
    return reg


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--town", action="append", default=[], help="城镇 basename，可重复")
    ap.add_argument("--dungeon", action="append", default=[], help="额外包含的副本路径/id")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--all-mazes", action="store_true", help="编译副本的全部 maze（默认只第一套）")
    ap.add_argument("--dry-run", action="store_true", help="只解析不落盘，打印统计")
    args = ap.parse_args()

    pvf = Pvf()
    map_ids = load_id_list(pvf, "list/map.lst")
    obj_ids = load_id_list(pvf, "list/passiveobject.lst")
    npc_ids = load_id_list(pvf, "list/npc.lst")
    town_ids = {
        lower_p(rel).rsplit("/", 1)[-1].removesuffix(".twn"): int(idx)
        for idx, rel in load_id_list(pvf, "list/town.lst").items()
    }
    strings = StringTable(pvf)
    refs = RefIndex(pvf, map_ids)
    registry = load_dungeon_registry(pvf)
    print(f"副本注册表：{len(registry)} 条；map id 表：{len(map_ids)} 条；"
          f"被动对象表：{len(obj_ids)} 条；NPC 表：{len(npc_ids)} 条")
    ctx: dict = {"obj_ids": obj_ids, "objects": {}, "anis": {}, "npcs": {},
                 "npc_ids": npc_ids, "strings": strings}

    out = Path(args.out)
    towns: dict[str, dict] = {}
    dungeons: dict[str, dict] = {}
    maps: dict[str, dict] = {}
    tiles: dict[str, dict] = {}
    regions: dict[str, dict] = {}
    problems: list[str] = []

    def want_map(path: str | None, origin: str) -> None:
        if not path:
            problems.append(f"{origin}: 房间未解析")
            return
        if path in maps:
            return
        if not pvf.exists(path):
            problems.append(f"{origin}: 房间不存在 {path}")
            return
        try:
            maps[path] = compile_map(pvf, path, refs, ctx)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{origin}: 解析失败 {path}: {exc}")
            return
        for til in maps[path]["tiles"] + maps[path]["extended_tiles"]:
            if til in tiles:
                continue
            try:
                tiles[til] = compile_tile(pvf, til)
            except Exception as exc:  # noqa: BLE001
                problems.append(f"{origin}: 地砖解析失败 {til}: {exc}")

    def want_dungeon(dgn_path: str, origin: str) -> None:
        if not dgn_path or dgn_path in dungeons:
            return
        if not pvf.exists(dgn_path):
            problems.append(f"{origin}: 副本不存在 {dgn_path}")
            return
        dgn = compile_dungeon(pvf, dgn_path, refs, args.all_mazes)
        dungeons[dgn_path] = dgn
        for maze in dgn["mazes"]:
            for cell in maze["cells"]:
                want_map(cell["map"], f"{dgn_path} 格({cell['x']},{cell['y']})")

    # 1) 城镇
    for name in args.town:
        cand = f"town/{lower_p(name)}.twn"
        if not pvf.exists(cand):
            problems.append(f"城镇不存在 {cand}")
            continue
        base = cand.rsplit("/", 1)[-1].removesuffix(".twn")
        town = compile_town(pvf, cand, strings, town_ids.get(base, -1))
        towns[cand] = town
        for area in town["areas"]:
            if area["type"] == "dungeon gate" and area["args"]:
                did = str(area["args"][0])
                if did in registry:
                    want_dungeon(registry[did], f"{cand} area{area['index']} 副本{did}")
                else:
                    problems.append(f"{cand} area{area['index']}: 副本 id {did} 不在注册表")
            want_map(area["map"], f"{cand} area{area['index']}")

    # 旧城镇不在 list/town.lst（如 hendonmyre）：用其地图里 town_movable 的
    # 内部目标 town id 的众数反推，这样跨城镇目标能正确指回自己。
    from collections import Counter
    for town in towns.values():
        if int(town.get("id", -1)) >= 0:
            continue
        c = Counter()
        for area in town["areas"]:
            m = maps.get(area["map"] or "")
            if not m:
                continue
            vals = m.get("town_movable", [])
            for i in range(0, len(vals) - 5, 6):
                tid = int(vals[i + 4])
                if tid > 0:
                    c[tid] += 1
        town["id"] = c.most_common(1)[0][0] if c else -1

    # 2) 地区（只用来给 UI 分组，不参与装载）
    for rpath in pvf.list_paths("region/", ".rgn"):
        try:
            regions[rpath] = compile_region(pvf, rpath, strings)
        except Exception as exc:  # noqa: BLE001
            problems.append(f"地区解析失败 {rpath}: {exc}")

    region_by_town: dict[int, str] = {}
    for rkey, r in regions.items():
        for tid in r["towns"]:
            region_by_town.setdefault(int(tid), rkey)
    for town in towns.values():
        tid = int(town.get("id", -1))
        town["region"] = region_by_town.get(tid, "")
        town["region_name"] = regions.get(town["region"], {}).get("name_text", [""])[0] \
            if town["region"] in regions else ""

    # 2) 显式追加的副本
    for spec in args.dungeon:
        path = spec if "/" in spec else registry.get(spec, "")
        want_dungeon(path, f"--dungeon {spec}")

    registry_inv = {v: k for k, v in registry.items()}
    towns_by_id = {str(t["id"]): key_of(p) for p, t in towns.items() if int(t.get("id", -1)) >= 0}
    index = {
        "generated_by": "tools/pvf_world/build_pack.py",
        "towns": [
            {"key": key_of(p), "path": p, "town_id": int(t.get("id", -1)),
             "name": t["name"], "name_text": t.get("name_text", []),
             "sub_name_text": t.get("sub_name_text", []),
             "region": t.get("region", ""), "region_name": t.get("region_name", ""),
             "areas": len(t["areas"])}
            for p, t in towns.items()
        ],
        "towns_by_id": towns_by_id,
        "regions": [
            {"key": key_of(p), "path": p, "name": r["name"], "name_text": r["name_text"],
             "towns": r["towns"], "town_keys": [towns_by_id[str(x)] for x in r["towns"]
                                               if str(x) in towns_by_id]}
            for p, r in regions.items()
        ],
        "npcs": [
            {"id": int(n["id"]), "path": n["path"], "name": n["name"],
             "field_name": n["field_name"], "ani": n["ani"]}
            for n in ctx["npcs"].values()
        ],
        "dungeons": [
            {"path": p, "registry_id": registry_inv.get(p, -1), "name": d["name"],
             "mazes": len(d["mazes"])}
            for p, d in dungeons.items()
        ],
        "counts": {"towns": len(towns), "dungeons": len(dungeons), "maps": len(maps),
                    "tiles": len(tiles), "anis": len(ctx["anis"]), "objects": len(ctx["objects"]),
                    "regions": len(regions), "npcs": len(ctx["npcs"])},
        "ref_stats": dict(refs.stats),
        "problems": problems[:200],
    }
    print(json.dumps(index["counts"], ensure_ascii=False), "refs:", dict(refs.stats))
    if problems:
        print(f"问题 {len(problems)} 条，前 10：")
        for p in problems[:10]:
            print("  -", p)

    if args.dry_run:
        return 0

    for sub in ("towns", "dungeons", "maps", "tiles", "anis", "objects", "regions", "npcs"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    (out / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")
    for kind, table in (("towns", towns), ("dungeons", dungeons), ("maps", maps),
                        ("tiles", tiles), ("anis", ctx["anis"]), ("objects", ctx["objects"]),
                        ("regions", regions)):
        for path, data in table.items():
            if data is None:
                continue
            f = out / kind / (key_of(path) + ".json")
            f.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    for nid, npc in ctx["npcs"].items():
        f = out / "npcs" / (str(nid) + ".json")
        f.write_text(json.dumps(npc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    total = sum(f.stat().st_size for f in out.rglob("*.json"))
    print(f"写入 {out}  共 {total / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
