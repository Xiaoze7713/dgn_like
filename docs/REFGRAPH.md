# 引用图（P0.7）

自动生成，勿手改。生成器：`tools/refgraph_report.py`；数据：`export/_meta/refgraph.sqlite`。

**这张图回答什么**：谁引用了谁。技能用了哪些动画、怪物挂了哪些动作库、副本用到哪些地图、装备的图标在哪个 img。它是「改一处会炸哪里」和「读一个系统要顺着看哪些文件」的地图。

## 规模

- 边（引用关系）：**2,608,572** 条
- 有出边的文件：**1,354,326** 个（全库 1,460,792 个文件）
- 被引用的不同目标：**610,295** 个
- 能落到 PVF 内真实文件的边：**1,030,336** 条（39.5%）；其余绝大多数是 `.img`（图像在 NPK 里，不属 PVF）

## 边按性质

| kind | 边数 | 含义 |
| --- | ---: | --- |
| `img` | 1,335,379 | 指向图像包里的 .img |
| `anim` | 920,976 | 指向 .ani/.als/.act 动画链 |
| `data` | 347,535 | 指向其它数据文件 |
| `script` | 4,246 | 指向 .nut 脚本 |
| `meta` | 436 | 指向 .lst/.str/.tbl 注册表 |

## 被引用最多的目标 top 20

这些是「公共依赖」，改它们影响面最大。

| 被引用次数 | 目标 |
| ---: | --- |
| 73,550 | `item/iconmark.img` |
| 37,092 | `item/fieldimage.img` |
| 19,158 | `item/field_equip.img` |
| 14,158 | `monster/mj/ai/movemethod.ai` |
| 13,983 | `monster/mj/ai/event.ai` |
| 13,805 | `monster/mj/ai/destinationselect.ai` |
| 12,913 | `monster/mj/ai/action.ai` |
| 6,273 | `interface2/gcontents/200618_miangdevilpalace/200618_devilpalacesaga_icons.img` |
| 6,259 | `interface2/gcontents/200618_miangdevilpalace/200618_devilpalacesaga_fieldmaterial.img` |
| 6,224 | `item/iconmaterial2.img` |
| 6,121 | `item/field_weapon.img` |
| 4,702 | `monster/monsterface.img` |
| 4,528 | `common/commoneffect2/glow/base_circle.img` |
| 4,330 | `common/commoneffect/glow/circle.img` |
| 4,064 | `monster/gcontents/190307_preyraid/commoneffect/warningfloor_line.img` |
| 3,802 | `aicharacter/swordman/kagemaru/kagemaru.aic` |
| 3,664 | `item/stackable/consumption.img` |
| 3,341 | `monster/gcontents/190307_preyraid/commoneffect/warningfloor_circle500.img` |
| 2,819 | `monster/mj/action/stay.act` |
| 2,580 | `character/swordman/atequipment/avatar/coat/sg_coat%02d%02da.img` |

## 出边最多的源文件 top 10

.lst 注册表天然出边最多——它们就是「id → 文件」的总目录。

| 出边数 | 源文件 |
| ---: | --- |
| 101,930 | `equipment/equipment.lst` |
| 32,169 | `stackable/stackable.lst` |
| 17,691 | `passiveobject/passiveobject.lst` |
| 9,693 | `etc/skillpreload.etc` |
| 4,107 | `map/map.lst` |
| 3,479 | `monster/monster.lst` |
| 1,867 | `appendage/appendage.lst` |
| 1,057 | `etc/equipmentpartset.etc` |
| 1,012 | `character/swordman/atswordman.chr` |
| 894 | `sqr/character/demoniclancer/demoniclancer_common.nut` |

## 跨类型引用矩阵（已解析的边）

| 源类型 → 目标类型 | 边数 |
| --- | ---: |
| `.act` → `.ani` | 222,125 |
| `.als` → `.ani` | 184,114 |
| `.map` → `.ani` | 137,053 |
| `.lst` → `.equ` | 106,067 |
| `.map` → `.til` | 61,049 |
| `.mob` → `.ai` | 58,956 |
| `.mob` → `.act` | 46,340 |
| `.obj` → `.act` | 36,986 |
| `.lst` → `.stk` | 27,692 |
| `.lst` → `.obj` | 18,287 |
| `.obj` → `.ani` | 11,914 |
| `.obj` → `.atk` | 11,530 |
| `.mob` → `.atk` | 10,778 |
| `.etc` → `.ani` | 9,882 |
| `.nut` → `.ani` | 9,737 |
| `.mob` → `.ani` | 9,395 |
| `.ptl` → `.ani` | 9,209 |
| `.equ` → `.ani` | 7,853 |
| `.act` → `.ptl` | 7,690 |
| `.cre` → `.ani` | 4,231 |
| `.chr` → `.ani` | 4,139 |
| `.nut` → `.nut` | 3,825 |
| `.ani` → `.aic` | 3,804 |
| `.lst` → `.mob` | 3,476 |
| `.lst` → `.skl` | 2,968 |

## 悬空引用（目标找不到，且不是 .img）

说明引用了**本 PVF 里不存在**的文件——多半是版本删改残留，实现时可以直接跳过。

| 扩展名 | 悬空边数 |
| --- | ---: |
| `.ani` | 220,635 |
| `.ai` | 6,873 |
| `.key` | 6,416 |
| `.act` | 3,777 |
| `.map` | 1,370 |
| `.atk` | 1,307 |
| `.ptl` | 1,230 |
| `.nut` | 420 |
| `.stk` | 323 |
| `.npc` | 270 |
| `.til` | 67 |
| `.obj` | 61 |
| `.equ` | 28 |
| `.twn` | 23 |
| `.etc` | 12 |

## 示例链路

### 一个技能引用了什么

（`skill/swordman/bloodboom.skl` 无出边）

### 一个怪物引用了什么

源：`monster/casillas/casillas.mob`

| 目标 | 类型 |
| --- | --- |
| `monster/monsterface.img` | img |
| `monster/chahua/animation/stay.ani` | anim |
| `monster/chahua/animation/move.ani` | anim |
| `monster/chahua/animation/overturn.ani` | anim |
| `monster/casillas/animation/attack1.ani` | anim |
| `monster/casillas/animation/attack2.ani` | anim |
| `monster/casillas/animation/attack3.ani` | anim |
| `monster/casillas/animation/quake.ani` | anim |
| `monster/casillas/animation/disappearfront.ani` | anim |
| `monster/casillas/animation/disappearback.ani` | anim |
| `monster/casillas/animation/appearfront.ani` | anim |
| `monster/casillas/animation/appearback.ani` | anim |

### 一个副本引用了什么

典型源：`dungeon/110levelnormaldungeon/altarofheblon_hero.dgn`（出边 5 条）

| 目标 | 类型 |
| --- | --- |
| `dungeon/110levelnormaldungeon/title/dungeontitle_65.ani` | anim |
| `contents/2022/destroyedcastleofdead/cutscene/destroyedcastleofdead2.img` | img |
| `map/minimap/act3.img` | img |
| `castleofthedead_destroyed.img` | img |
| `dungeon/110levelnormaldungeon/110lvevnormal.tbl` | meta |

### 一个装备引用了什么

典型源：`equipment/equipment.lst`（出边 101930 条）

| 目标 | 类型 |
| --- | --- |
| `equipment/character/common/title/dz_cqds1.equ` | data |
| `equipment/character/common/title/dz_cqds.equ` | data |
| `equipment/character/swordman/avatar/aura/moranbaoyuqq27770481.equ` | data |
| `equipment/creature/swor1.equ` | data |
| `equipment/creature/sword.equ` | data |
| `equipment/creature/1261511678/a141.equ` | data |
| `equipment/fsb_1336991231/gh/7010101.equ` | data |
| `equipment/creature/chn_400990616.equ` | data |
| `equipment/creature/chn_400990618.equ` | data |
| `equipment/character/fighter/at_avatar/skin/202500012.equ` | data |
| `equipment/character/fighter/at_avatar/skin/2025416000.equ` | data |
| `equipment/character/fighter/at_avatar/skin/2025416001.equ` | data |

## 已知边界与坑

1. **路径解析不是根相对**。大量引用写成 `../Animation/x.ani`，基准是「逻辑根」（如 `character/swordman/`）。只用根相对解析会有 48 万条 `.ani` 悬空；本图已加「后缀匹配 + 同根优先」回退，仍有约 56 万条只能模糊落到同名前缀的候选上（记 `suffix2-ambig`）。
2. **`.img` 一律解析不到**——图像在 NPK 客户端包里，PVF 只存路径。这类边不算错。
3. **反向查询用 `ix_dst`**：`sqlite3 export/_meta/refgraph.sqlite "select src from edges where dst='monster/casillas/casillas.mob'"` 可以查「谁在用这个怪物」。
4. 图只覆盖 PVF 内的**文本**引用；`.nut` 里用字符串拼出来的路径（如 `"..." + idx + ".ani"`）无法静态抽全。
