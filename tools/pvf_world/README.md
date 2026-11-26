# tools/pvf_world —— PVF 世界内容包编译

把最新 `Script.pvf` 里的 `.twn` / `.dgn` / `.map` / `.til` / `.ani` / `.obj` / `.npc` / `.rgn` 编成运行时只读的 JSON。

## 用法

```bash
python3 tools/pvf_world/build_pack.py \
  --town hendonmyre --town centralpark --town metrocenter --town devildom_contact \
  --out dnf_like/assets/pvf/world
```

可选：`--dungeon <path>`、`--all-mazes`、`--dry-run`；`--town` 可重复。
输出：`index.json` + `towns/ dungeons/ maps/ tiles/ anis/ objects/ npcs/ regions/`。

## 关键函数

| 函数 | 说明 |
|---|---|
| `key_of(path)` | 路径归一化；正则必须与 `PackContent.KEY_PATTERN` 一致 |
| `load_id_list(pvf, rel)` | 读 `list/*.lst` 的 id→path |
| `StringTable` | 读 `String/*.chn.str`（UTF-16LE，`key>value`），`resolve("<8::name_...>")` |
| `parse_areas(town_node)` | 递归扫 area 子树，认 `[permission]` 里的 `[gate]/[normal]/[dungeon gate]/[minimap rect]` 和 `[phase]` |
| `compile_town(pvf, path, strings, town_id)` | 城镇 + area + 中文名 + phase |
| `compile_region(pvf, path, strings)` | 地区名 + `[towns]` + `town_keys` |
| `compile_npc(pvf, id, path, strings, ctx)` | `[field animation]`（先相对 .npc 目录，再 `npc/`）、name/field name/role/face |
| `compile_map(...)` | 地图字段、`[import script]` 递归、NPC 记录补 path |
| `compile_ani` / `compile_object` / `compile_tile` | 动画/物件/地砖 |

## 已知坑

- `.twn` 的 gate/normal 可能嵌在 `[permission]` 下，不能只读 `[area]` 的直接 values。
- `[gate] args` 只取同一 values 列表里的后续整数，别把 `[need level]` 的 82 收进来。
- `Common/Gate_Seria.map` 不存在，实际是 `map/common/(f)|(r)gate_seria.map`；centralpark/metrocenter 的 area 0 仍可能是空图，运行时自动回退。
- `list/town.lst` 里没有旧 `hendonmyre`；它的 `town_id` 靠 town_movable 目标众数推断为 2。
- NPC 动画路径必须加 `npc/`；`.ani` 的 `[IMAGE POS]` 不含 NPK 帧画布原点。

## 验证

```bash
python3 tools/pvf_world/build_pack.py --town hendonmyre --town centralpark --town metrocenter --town devildom_contact --out /tmp/pack_test --dry-run
```

看 `ref_stats` 命中率、`problems` 是否为空，以及 `index.json` 的 `towns_by_id/regions/npcs`。
