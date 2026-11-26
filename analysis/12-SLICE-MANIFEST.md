# 切片素材总清单（M3 可玩切片）

> 输入：`analysis/10-SLICE.md` 画的范围。输出：`export/_meta/slice_manifest.json`（机器读）＋本文（人读）。
> 生成器：`tools/slice_manifest.py`，可重跑（`python3 tools/slice_manifest.py`，约 12 秒）。
> 一句话：**数据层极小（745 个文件、418 KB），体量全在图上（174 张 .img、18.2 MB 打包 / 100.8 MB 解包 / 8,684 帧）。**

---

## 0. 总账

| 项 | 数值 | 备注 |
|---|---|---|
| 数据文件（PVF 内） | **745 个 / 417.7 KB** | 纯文本，全部可一次读进内存 |
| 根 | 158 条（157 条必需 + 1 条已缺） | `10-SLICE` 显式 102 条 + 由 `.lay`/目录约定反查 56 条 |
| 根未命中 | 1 条 | `swordman_key.nut`（PVF 里没有，见 §4） |
| 图像 `.img` | **174 张**（171 找到 / 3 缺） | 分布在 **71 个 NPK** |
| 图像体积 | **18.16 MB 打包**，8,684 帧，**100.8 MB 若全解 RGBA** | 见 §3 |
| 悬空引用 | 5 条 | 4 条 `.chr` 历史残留 + 1 条 `.twn` 指向不存在的 gate 地图 |
| 被 `.chr` 枚举而排除 | 301 条 | 全职业/全流派的动画与 `.atk`，切片用不到 |

三条结论：

1. **数据层可以"全量预载"**：418 KB 文本，Godot 里连懒加载都不用设计，启动直接全读。
2. **图必须分档 + 按帧裁**：18.2 MB 里 `item/` 占 5.5 MB，但切片只用到 10 个图标（4,618 帧里 10 帧）；裁完 item 从 5.5 MB 掉到几十 KB。
3. **"不多不少"的边界是可以写成规则的**（§1），其中 6 条规则里 2 条（R4 `.chr` 不展开、R5 只留一档动画）决定了 60% 的文件去留。

---

## 1. 判定规则：什么算"在切片里"

清单不是拍脑袋列的，是**从根沿引用边做 BFS** 得到的最小闭包。规则如下，按影响大小排序：

| # | 规则 | 为什么 | 影响 |
|---|---|---|---|
| R1 | 根 = `10-SLICE` 点名的文件 | 范围由分析决定，不由数据决定 | 158 条根 → 745 个文件 |
| R2 | 只沿 `refgraph.sqlite` 里 `resolved=1` 的边扩 | `resolved=0` 的边指向 PVF 里不存在的东西，跟过去就是死路 | 5 条悬空被记进缺口，不污染清单 |
| R3 | **`.lst` / `.tbl` / `.lay` 只收文件，不展开** | `map.lst` 一个文件就把 2,989 张 `.map`、574 个 `.dgn`、330 个 `.qst` 全拉进来——那是整库，不是切片 | 从 13,509 → 745，砍掉 95% |
| R4 | **`.chr` 不跟 `.ani` / `.atk` 边** | `swordman.chr` 把全职业、全流派（含三觉）的动画枚举了一遍；切片只要未转职 Lv1–20 | 排除 301 条，`character/` 从 264 → 207 |
| R5 | 技能动画**只留 `character/swordman/animation/` 一档** | 同名 `.ani` 在 `animation` / `dsanimation` / `atanimation` 三档各有一份，只有未转职这一档对得上 `swordman.chr` | 少带 2 套动画 + 对应特效图 |
| R6 | 动作表里的 `%s` 用**文件名回查**补根 | `.lay` 写的是 `%s/Stay.ani`，`%s` 要运行时才知道展开成什么；纯 BFS 永远走不到 | 补进 56 条根（15 基础动作 + 30 技能动作 + 11 技能 `.atk`） |
| R7 | **同目录优先于全局后缀匹配** | `Animation/Background/Back_Middle.ani` 这种同名文件全库 10 份，refgraph 只会取第一个，会把艾爾文防線的背景错指到别的副本 | 修正了城镇背景/地块；不修的话城镇会缺 20+ 张图 |

### 1.1 推断层（R6 补的 56 条根）

`.lay` 的 `[<xxx> motion]` 段给的是**动作名**，不是路径：

- **基础动作 15 个**：`stay / move / sit / damage1 / damage2 / down / overturn / jump / jumpattack / rest / dash / dashattack / getitem / buff / back / throw`（另有 `[attack motion]` = 普攻三段）。
- **技能动作 6 个**：`guard(46) / upperslash(5) / tripleslash(8) / dashattackmultihit(11) / ashenfork(16) / khazan(25)` —— 括号是等级。
- **技能 `.atk`**：目录约定 `character/swordman/{attackinfo,dsattackinfo,atattackinfo}/<skill>.atk`，命中的进清单。

> 推论（写进实现）：**角色的动作编排不在数据文件里**。`.lay` 只有名，`.nut` 里是整数常量（`sq_SetCurrentAnimation(122)` → `[etc motion]` 第 123 项）。所以清单只能靠"名字回查"补，任何纯引用的 BFS 都会漏掉玩家自己的动画——这是本任务最大的坑，也是 t11 做图集时同样要面对的坑。

### 1.2 怪物那边相反：`.mob` 直接写 `.ani`

实测 12 只怪（`goblin/goblinthrower/seagab/hillgab/goblintaskmaster/goblinthrowertaskmaster/flagseagab/taubeast/lugaru/kurogaru/sirogaru/penril`）的 `.mob`：

- `[waiting motion]` / `[move motion]` / `[damage motion 1]` … 直接写 `Animation_Goblin2/Stay.ani`
- `[attack motion]` = `Animation_Goblin2/Attack1.ani Animation_Goblin2/Stay.ani`
- `[attack info]` = `AttackInfo/Attack1.atk`
- **一个 `.act` 都没有**（`.act` 只在 `monster/<族>/action_<x>/` 里，由新版怪物的 `.mob` 引用；这 12 只老怪不走那条路）

所以怪物侧 BFS 能自动走到位，`monster/` 164 个文件里 152 个是 `.ani`。

---

## 2. 按类型分账

| 类型 | 文件 | 字节 | 作用 |
|---|---:|---:|---|
| `.ani` | 415 | 290.3 KB | 帧表 + 逐帧判定盒（**动画与几何都在这里**） |
| `.atk` | 181 | 20.4 KB | 伤害属性（伤害类型/倍率/命中反馈） |
| `.til` | 25 | 49.4 KB | 地块表（引用 tile `.img`） |
| `.map` | 23 | 42.8 KB | 房间：怪物布点、门、背景层、地块引用 |
| `.skl` | 23 | 93.0 KB | 技能数值（等级表/前置/SP） |
| `.equ` | 21 | 5.4 KB | 装备（10 件切片装备 + 掉落的武器外观） |
| `.mob` | 12 | 12.1 KB | 怪物：基表乘数、攻击槽、掉落权重、台词 |
| `.stk` | 10 | 2.2 KB | 消耗品/材料 |
| `.qst` | 6 | 1.4 KB | 主线 4 环 + 支线 2 个 |
| `.lst` | 6 | 67.5 KB | id→路径总表（`town/dungeon/map/worldmap/quest/epicquest`） |
| `.ai` | 4 | 0.6 KB | 哥布林 AI（其余两族无 `.ai` 目录） |
| `.dgn` | 3 | 1.9 KB | 副本结构（洛蘭/幽暗密林/毒沼） |
| 其它 | 18 | 4.4 KB | `.chr`1 `.lay`1 `.tbl`1 `.etc`2 `.ptl`3 `.act`2 `.twn`1 `.wdm`1 `.npc`2 `.shp`1 `.ui`1 |

## 2.1 按场景分账

| 场景 | 文件 | 字节 | 说明 |
|---|---:|---:|---|
| `map/` | 194 | 155.3 KB | 16 个房间 + 城镇主街 + 各自的动画/地块/门 |
| `skill/` | 23 | 93.0 KB | 鬼剑士全部 `.skl`（含 3 个被动） |
| `character/` | 207 | 58.6 KB | 主角动画/ATK + 头像/技能图标索引 |
| `monster/` | 164 | 52.9 KB | 12 只怪 + 4 件 AI |
| `n_quest/` | 9 | 19.5 KB | 6 个 `.qst` + 3 张表 |
| `equipment/` | 115 | 17.1 KB | 装备 + 掉落外观 |
| `dungeon/` | 7 | 8.7 KB | 3 个 `.dgn` + 副本标题动画 |
| `npc/` `town/` `worldmap/` `itemshop/` | 13 | 8.4 KB | NPC / 城镇 / 世界地图 / 商店 |
| 合计 | **745** | **417.7 KB** | |

---

## 3. 图像：174 张、71 个 NPK、18.16 MB

### 3.1 分场景

| 场景 | 打包 MB | 帧数 | 说明 |
|---|---:|---:|---|
| `map/` | 8.50 | 492 | 城镇物件 + 背景 + 地块 + 2 张过场大图 |
| `item/` | 5.49 | 4,618 | 图标图集（**只用到 10 帧**） |
| `monster/` | 1.73 | 2,531 | 12 只怪的身体/头像 |
| `character/` | 1.46 | 937 | 主角身体图集 + 特效 + 技能图标 |
| `common/` | 0.41 | 89 | 通用特效（门/光） |
| `worldmap/` | 0.34 | 13 | 洛蘭世界地图 |
| `interface` | 0.22 | 4 | 选副本界面 |
| 合计 | **18.16** | **8,684** | 解包后 100.8 MB |

### 3.2 最大的 6 张（也是裁剪收益最大的）

| 图 | 帧 | 打包 | 解包 | 切片实际要用 |
|---|---:|---:|---:|---|
| `item/stackable/consumption.img` | 2,670 | 3.56 MB | 8.0 MB | **10 帧**（草莓/面包/叶/肉干…） |
| `map/cutscene/elvengard.img` | 1 | 1.32 MB | 1.8 MB | 0（过场大图，M3 不播） |
| `map/cutscene/lorien.img` | 1 | 1.22 MB | 1.8 MB | 0（同上） |
| `item/stackable/material.img` | 821 | 1.06 MB | 2.4 MB | 4 帧（毒牙/焦炭…） |
| `monster/monsterface.img` | 2,034 | 1.00 MB | 4.5 MB | 12 帧（血条旁小头像） |
| `character/swordman/effect/skillicon.img` | 699 | 0.56 MB | 2.1 MB | 6 帧（技能图标） |

> **t11（图集切片）的最大一笔优化就在这里**：这 6 张占 8.7 MB / 18.2 MB，按帧裁完只剩约 1.9 MB（其中两张过场直接不要）。清单只到"哪张 `.img`"，到"哪一帧"必须由 `.ani` 的 `(img_index, img_frame)` 反推——`.ani` 头部的图路径 + 每帧 `img_frame` 就是帧清单。

### 3.3 NPK 分布

71 个包里最多的三个：`sprite_map.NPK`（58 张）、`sprite_map_town_04_elvengard_object.NPK`（15）、`sprite_monster_goblin_equipment.NPK`（11）。

**这意味着切片不能"按包复制"**：58/174 张集中在 `sprite_map.NPK`，这个包整个拷过来会带上所有地图。必须**按 `.img` 抽取**（`tools/npk_parser.py` 支持单 img 读取）。

---

## 4. 缺口清单（全部 3 类、10 条，已核对）

### 4.1 根未命中（1）

| 路径 | 判定 |
|---|---|
| `character/swordman/swordman_key.nut` | **不存在**。按键映射不在这；角色输入走引擎内建 + `.nut` 里的 `onKey...` 回调。→ 从根里删掉，实现时按键表自己定。 |

### 4.2 悬空引用（5）

| 引用者 | 指向 | 判定 |
|---|---|---|
| `swordman.chr` | `AttackInfo/MoonLightSlashDemonicCrownAttack1.atk` 等 3 个 | **历史残留**：三觉（真·月光斩/真·上挑）的 `.atk` 已被删，`.chr` 没清干净。不影响 Lv1–20。 |
| `swordman.chr` | `attackinfo/hellslashadd.atk` | 同上（`HellSlash` 附加段）。 |
| `town/1_new/new_elvengard.twn` | `1_new/Common/Gate_Seria_Elvengard.map` | **真缺**：城镇里的"赛丽亚房间"传送门。→ 实现时用相邻房间或直接开门，别等它。 |

### 4.3 图像找不到（3）

| 路径 | 判定 |
|---|---|
| `04d.img` | **坏路径**：上游把 `%04d` 拼坏了（`sm_body%04d.img` 之类）。丢弃。 |
| `interface2/selectdungeon/selectdungeonhell/selectdungeonhell.img` | 洛蘭世界地图 `.ui` 引用的界面图，**这 4,730 个包里确实没有**（可能在被裁掉的高清补丁包）。M3 自绘选关界面即可。 |
| `interface2/dungeonexercise/dungeonexercise.img` | 同上（练习模式按钮）。 |

> 结论：**卡通关卡的三张图没有缺口**——角色身体（`sm_body%04d.img`）、怪物、地块、城镇物件全在。缺的都是"历史残留 / 界面装饰"。

---

## 5. 冷启动体积预算

| 项 | 体积 | 什么时候要 |
|---|---:|---|
| 全部数据（745 文件） | 418 KB | 启动即读，可忽略 |
| 图：城镇首屏（背景+物件+地块+NPC） | ≈ 6.5 MB 打包 / ~35 MB 解包 | 进城镇 |
| 图：主角（身体图集 + 技能图标） | 1.46 MB / ~7 MB | 进游戏 |
| 图：12 只怪 | 1.73 MB / ~9 MB | 进副本时按需 |
| 图：3 个副本房间（地块+背景） | ≈ 2 MB / ~10 MB | 按房间懒加载 |
| 图：图标（裁帧后） | < 0.2 MB | 背包/技能栏 |

建议：**按场景分三个 pak**（town / dungeon / character+monster），配 `ResourceLoader.load_threaded_request`；单场景峰值控制在 15 MB 显存以内（DXT 压缩下约 3 MB）。这与 `docs/GODOT-EVAL.md` 的"显存 < 100 MB"验收口径一致，且有一倍余量。

---

## 6. `slice_manifest.json` 字段与用法

```
roots[]            根（path / required / note），含推断层
files[]            切片闭包：path, kind, bytes, refs_by(最多 4 个引用者), required
images[]           图：path, npk[可能多个包], referenced_by(最多 3 个 .ani)
deferred_by_chr[]  301 条：.chr 枚举到但切片不要的动画/atk（换职业时直接拿来用）
totals             汇总（root_count / files / bytes / by_kind / images_* / npk_packages）
gaps[]             缺口（root_missing / dangling_ref / img_not_found）
```

加载顺序（照 DNF 自己的层级来）：

1. 读 `.lst` 建 id→路径表（`town/dungeon/map/worldmap`）——它们**只是查表**，不要遍历。
2. 读实体（`.chr` / `.mob` / `.equ` / `.stk` / `.skl` / `.qst`）→ 得到"用哪些动作、哪些 atk、哪些图"。
3. 读 `.ani`（帧表 + 判定盒）→ 拿到 `(img, img_frame)` 序列。
4. 按 `.img` 抽帧建图集 → `Sprite2D.region_rect`。

排查用法：

```bash
python3 tools/slice_manifest.py --trace character/swordman/swordman.chr   # 反查一个根的树
python3 tools/slice_manifest.py --stat | head -40                        # 只看统计，不写文件
```

---

## 7. 复现与维护

- 生成器只读 `export/_meta/{index,refgraph}.sqlite`、`export/text/**`、`ImagePacks2/**`，**不写 export**。
- 加内容：在 `tools/slice_manifest.py` 的 `ROOTS` 里加一行 `_r("路径", "说明")`，重跑。推断层不用改（它按 `.lay` 现算）。
- 换职业：把 `BODY_DIR` 指到新职业的 `animation/`，`inferred_body_roots` 会自动按新 `.lay` 拉；`deferred_by_chr` 里那 301 条就是现成的"转职后要去拿的东西"清单。
- 已知会变慢：`inferred_body_roots` 每次要做一次全表 basename 回查（约 6 秒）。想更快就把 basename 索引缓存成 `export/_meta/basename.tsv`。

---

## 8. 已知偏差（写清，别让下游当真理）

| # | 偏差 | 影响 | 怎么办 |
|---|---|---|---|
| D1 | 技能动画只保留 `animation/` 一档，`dsanimation/`/`atanimation/` 未收 | 换武器/转职后动作会缺 | t11 若发现武器切换真会换档，按 R5 反向补齐；两档合计约 +120 个 `.ani` |
| D2 | `.atk` 收了 181 个，其中一部分是 `.skl` 的 `[attack info]` 全表 | 多收约 10 KB，无害 | 想瘦身就只留 6 个技能的 |
| D3 | 过场大图 `map/cutscene/{elvengard,lorien}.img` 在清单里（2.5 MB） | 占 1/7 图体积 | M3 不播过场 → 直接从 images 里去掉 |
| D4 | `.ani` 逐帧判定盒没有进清单（只有文件级） | t11 切图不需要，t14 做判定时需要 | 判定盒由 `tools/ani_parser.py` 现解，见 `docs/ANI-FORMAT.md` |
| D5 | `monster/tau`、`monster/lugaru` 没有 `.ai` 目录 | 行为层只能"引擎内建 AI + `.mob` 参数" | 符合预期：这两族是早期怪，行为写在 `.mob` 的 `[attack delay]/[sight]/[warlike]` 里 |
