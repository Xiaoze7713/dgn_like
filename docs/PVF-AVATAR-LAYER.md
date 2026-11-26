# PVF 的时装/装备分层（avatar layer）：实际结构与导出方法

> 本文只讲「角色由哪几层图叠出来、这些层在 PVF 里长什么样」。
> 容器/文档/`.ani` 的字节格式见 [PVF-FORMAT-BYTES.md](PVF-FORMAT-BYTES.md)，
> 依赖关系见 [PVF-DEPENDENCY-GRAPH.md](PVF-DEPENDENCY-GRAPH.md)。

## 0. 结论

1. 角色的**身体**和**时装**是两套独立的图，靠 `.ani` 里的 `POS` + 图内的 `(x,y)` 对齐后**按层叠加**。
2. 时装按部件分目录：`equipment/character/<job>/avatar/<part>/`，本客户端鬼剑士共 **210,707** 个条目
   （`weapon 82,063 / at_avatar 73,963 / avatar 53,270 / growtype 1,411`）。
3. 8 个可叠的部件：`pants → shoes → belt → coat → neck → face → hair → cap`（从下往上画）。
4. **`.equ`（物品定义）里没有「用哪个 look 目录」的字段**，`.ani` 里只有一个模板
   `sm_<part>%02d%02da.img`；两个 `%02d` 是**时装图集的编号**，由身上穿的物品决定，
   **PVF 里没有任何一张表能直接查到它**（需要遍历 `.equ` → 图标 → 图集名，或用运行时 dump）。
5. 因此导出的做法是：给每个部件**挑一张固定的图集**（`sm_<part>NNNNa.img`，≥188 帧），
   把所有动作的 `IMG_PARAM`（帧号）套进去。这能跑通全套动作，只是外观固定。

## 1. 目录结构（鬼剑士）

```
equipment/character/swordman/
├── swordman.lay                 # 21 条「动作名 → %s/<motion>.ani」模板
├── avatar/                      # 一觉前的外观
│   ├── coat/
│   │   ├── 401500102.equ        # 物品定义（名字/图标/技能加成）
│   │   ├── coat_a/              # look 变体 a：710 个 .ani，0 个 .img
│   │   │   ├── stay.ani  move.ani  attack1.ani ...（22 个基础动作）
│   │   └── coat_b/ ...          # 共 1,068 个变体目录
│   ├── cap/ hair/ pants/ shoes/ belt/ face/ neck/
│   └── skin/askin_42217.equ     # 皮肤：没有 look 目录，只有 .equ
└── at_avatar/                   # 二觉外观（结构同构）
```

各部件条目数（`avatar/`）：`neck 11,068 / coat 9,635 / hair 6,228 / pants 6,126 / cap 5,563 /
shoes 5,097 / belt 4,792 / face 4,183 / skin 280 / aura 198 / weapon 100`。

## 2. `swordman.lay`：动作模板

`equipment/character/swordman.lay`（1,642B，Document，顶层 `[layer] 0`）给出 21 条模板，
`%s` 由部件目录替换：

```
waiting   → %s/stay.ani          move      → %s/move.ani         sit        → %s/sit.ani
damage 1  → %s/damage1.ani       damage 2  → %s/damage2.ani      down       → %s/down.ani
overturn  → %s/overturn.ani      jump      → %s/jump.ani         jumpattack → %s/jumpattack.ani
rest      → %s/rest.ani          throw 1-1 → %s/throw1.ani        1-2        → %s/throw2.ani
throw 2-1 → %s/summon1.ani       2-2       → %s/summon2.ani      dash       → %s/dash.ani
dashattack→ %s/dashattack.ani    getitem   → %s/getitem.ani       buff       → %s/summon2.ani
back      → %s/attack3.ani       attack    → %s/attack1.ani      etc        → %s/guard.ani
```

## 3. 部件 `.ani` 里到底存了什么

`coat_a/stay.ani`（206B，3 帧）解出来是：

```
[IMAGE] 0  character/swordman/equipment/avatar/coat/sm_coat%02d%02da.img
[POS] -232 -333
[IMG_PARAM] 90      ← 帧号（不是文件号）
[DELAY] 100
```

- 8 个部件 × 22 个基础动作，每个部件共 **142 帧**，`IMG_PARAM` 最大 **187**。
- 所有部件的 `POS` 完全相同（`-232 -333`），所以叠图不会错位。
- `sm_<part>%02d%02da` 的两个 `%02d` = 时装图集编号；最后的 `a` = **体型档**（见 §5）。

## 4. 图集命名与「帧数够不够」

NPK 里的图集叫 `sm_<part><4 位编号><后缀>.img`，后缀不是随便加的：

| 部件 | 后缀分布 | 带 `a` 的数量 |
| --- | --- | --- |
| coat | a 317 / c 101 / b 116 / d 40 / f 9 / g 2 | 317 |
| cap | a 252 / b 83 / c 61 / d 12 / f 9 | 252 |
| hair | a 339 / b 77 / d 64 / c 26 / h 4 | 339 |
| pants | a 322 / b 240 / d 107 / f 2 | 322 |
| shoes | a 336 / b 335 / f 9 | 336 |
| belt | c 263 / d 151 / a 55 / b 36 / f 9 | 55 |
| face | b 231 / a 40 / c 15 / g 8 / h 4 / f 1 | 40 |
| neck | d 171 / c 132 / x 109 / a 87 / b 30 / e 26 / f 2 | 87 |

实测 `sm_coat0000a.img` 有 **242 帧**（pack `sprite_character_swordman_equipment_avatar_coat.NPK`，97,279B），
足够覆盖 `IMG_PARAM` 0..187 的全部动作。注意 cap 的最小编号是 `0500`（没有 `sm_cap0000a`）。

## 5. 最容易踩的坑：**体型档必须一致**

同一个动作，身体图有「小档」和「放大档」两种：

| 图 | 帧数 | 某帧内容尺寸 | 与 `a` 后缀时装 |
| --- | --- | --- | --- |
| `sm_body0001.img`（官方皮肤） | 242 | 64×106 | ✅ 对齐 |
| `sm_body0000.img`（新模型包） | 179 | 109×120 | 大致可用（旧模型） |
| `sm_body0180.img`（2020 活动皮肤） | 243 | 147×187 | ❌ 大身体 + 小时装 |

`sm_body0180` 是从 `sprite_interface2_event_event_202_grwthequiment.NPK` 里来的**放大版**活动皮肤，
把它和 `a` 后缀时装叠在一起，就会得到「一个大人身上挂一套小衣服」的效果。
所以本仓库的合成默认用 `sm_body0001`。

### 5.1 第二个坑：按编号挑图集会挑到「小配件」

同一个 part 下，`sm_coat0000a` 不一定是一整件衣服。实测它的 frame 0..9 内容只有 **32×27**，
画出来是「领子/肩甲」这一级别的小件；而 `sm_coat0703a` 是 50×49 的整件大衣。
`id` 靠前的图集大量是**配饰**，不是主服装。

判定办法（本仓库采用）：**按平均帧面积排序**，取「帧数 ≥ 188（够覆盖 22 个基础动作的
`IMG_PARAM` 0..187）+ 平均内容面积最大」的那张。当前选中的 8 张：

| 部件 | 图集 | 帧数 | 平均内容 |
| --- | --- | --- | --- |
| pants | `sm_pants1103a.img` | 242 | 大 |
| shoes | `sm_shoes0403a.img` | 242 | 103×56 |
| belt | `sm_belt0503a.img` | 242 | 56×53 |
| coat | `sm_coat0703a.img` | 242 | 50×49 |
| neck | `sm_neck4101a.img` | 210 | 85×113（翅膀披风） |
| face | `sm_face4200a.img` | 242 | 35×35 |
| hair | `sm_hair1303a.img` | 242 | 48×49 |
| cap | `sm_cap1403a.img` | 242 | 30×28 |

### 5.2 第三个坑：img 路径带不带 `sprite/`

PVF 里写的 `.img` 路径**不带** `sprite/` 前缀（`character/swordman/...`），
而 NPK 条目和 img-index 里**带**（`sprite/character/swordman/...`）。
两套字符串混着用会在 `dnf_demo/img/` 下生成两份重复目录。
本仓库统一规则：**落盘与 JSON 里一律不带 `sprite/`**，只在查 img-index 时临时拼上（`_norm()`）。

## 6. 导出产物（`dnf_demo/avatar/`）

```
dnf_demo/avatar/
├── layers.json          # order / sheets / body / body_candidates
├── coat/stay.json       # 每帧：{img, frame, x, y, ix, iy, draw_x, draw_y, delay, src}
├── coat/move.json  coat/attack1.json ...   （8 个部件 × 22 个动作 = 176 个 JSON）
└── ...
```

`src` 保留原始模板（`...sm_coat%02d%02da.img`），换成别的时装时改解析结果即可。
图集 PNG 落在 `dnf_demo/img/sprite/character/.../sm_coat0000a/0000.png ... 0241.png`。

合成顺序（`layers.json.order`）：

```
body(sm_body0001) → pants → shoes → belt → coat → neck → face → hair → cap
```

每层都画在 `(draw_x, draw_y)`，其中 `draw_x = POS.x + img.x`、`draw_y = POS.y + img.y`。

预览：`preview_avatar_stay_sm_body0001.png`（正确）、`preview_avatar_attack1_sm_body0001.png`、
以及反例 `preview_avatar_stay_sm_body0180.png`。

## 7. 还没解出来的（下一步）

1. **物品 → 图集编号**：`.equ` 只有 `[icon] item/avatar/swordman/sm_acoat.img 568`（图标 + 帧号），
   没有 look 目录/图集编号字段。可行路线：运行时从客户端 dump，或对每个 `.equ` 的图标帧号做聚类反推。
2. **`skin` 的 `[avatar type select] 7 0 0 1000`**：疑似「肤色号 / 层 / 优先级 / 上限」，未验证。
3. **武器层**（`weapon 82,063` 个条目）：需要 `equipment/character/swordman/weapon/<weapon id>/` 的
   动作按 `[attack]` 等字段绑定，还没做。
4. **`.lay` 的层级/偏移**：`swordman.lay` 只有 `[layer] 0`，各部件自己的 `.lay`
   （`equipment/character/<job>/avatar/<part>/<part>.lay`）还没读，可能含额外偏移。

## 8. 复现

```bash
python3 tools/make_avatar.py export     # 选图集 → 解 PNG → 生成部件 JSON + layers.json
python3 tools/make_avatar.py preview    # 合成 preview_avatar_<motion>_<body>.png
```

## 9. 已解出：`.equ` → 图集 / 层目录（补，2026-11-06）

§7 的第 1 条（物品 → 图集编号）**已解出**，`.equ` 里就是：

```
[animation job]
    [swordman]
[variation]
    0            <- look（款式号，2 位）
    0            <- color（染色号，2 位）
[layer variation]
    1500         <- z 序（越大越靠前），**每个部件可以有多层**
    pants_a      <- 层目录名 = <部件>_<档位后缀>
    1300
    pants_b
[equipment ani script]
    equipment/character/swordman.lay
```

- **图集路径** = `character/swordman/equipment/avatar/<part>/sm_<part><look:02d><color:02d><后缀>.img`
  （后缀取自层目录名最后一位；`sm_coat0000a` 这种：look=00 color=00 后缀 a）。
- **动作路径** = `equipment/character/swordman/avatar/<part>/<层目录>/<motion>.ani`。

### 9.1 一个部件是多层（这是最大坑）

默认裤子不是一张图，而是两层：`pants_a`(z=1500，前腿) + `pants_b`(z=1300，后腿)，
对应两张图集 `sm_pants0000a.img` / `sm_pants0000b.img`。**只画 a 层 → 后腿是裸的**
（曾经以为是「帧对不齐」，实际是漏了一层）。鞋同理：`shoes_a` 1400 + `shoes_b` 1200。

实测默认套装解析结果（`python3 tools/make_outfit.py show`）：

| 部件 | look | color | 层目录 | z | 图集 |
|---|---|---|---|---|---|
| shoes | 00 | 00 | shoes_b | 1200 | `sm_shoes0000b.img` |
| pants | 00 | 00 | pants_b | 1300 | `sm_pants0000b.img` |
| shoes | 00 | 00 | shoes_a | 1400 | `sm_shoes0000a.img` |
| pants | 00 | 00 | pants_a | 1500 | `sm_pants0000a.img` |
| coat  | 00 | 00 | coat_a  | 1800 | `sm_coat0000a.img` |
| hair  | 00 | 00 | hair_a  | 2000 | `sm_hair0000a.img` |
| cap   | 101 | 00 | cap_a | 2100 | `sm_cap10100a.img`（look 101 不存在 → 默认不戴帽） |

绘制顺序 = 按 z 从小到大；每层仍用 `draw_x = POS.x + img.x`、`draw_y = POS.y + img.y`。

### 9.2 工具

```bash
python3 tools/make_outfit.py list                 # 列出所有默认 .equ 的 variation / layer
python3 tools/make_outfit.py show                 # 展开成实际绘制层（含图集路径）
python3 tools/make_outfit.py render --motion move --out x.png   # 分帧条图
python3 tools/make_outfit.py gif    --motion move --out x.gif   # 按真实 delay 的动图
```

产物：`dnf_demo/verify/1x_outfit_{stay,move,dash,attack1,weaponcomboshort1}.png` 与
`dnf_demo/verify/2x_outfit_{stay,move,dash,weaponcomboshort1}.gif`（穿好默认套装的鬼剑士）。

### 9.3 还没做

- 换装：只要把 `.equ` 换成别的物品路径即可；`[variation]` 的 look/color 会指向别的图集。
  但目前没有「按名字搜索物品 id」的索引，得先列 `equipment/character/swordman/avatar/<part>/*.equ`。
- 武器层仍未接（`weapon/ssword/sswdb/weaponcomboshort1.ani` 已能解析，尚未叠进合成）。
