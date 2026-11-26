# DNF 数据一览（sf115 · 人造神）

> 自动生成于 2026-10-26 21:07。数据源 `data/Script.pvf`（923MB，1,460,792 个文件，745MB 解压后）。
> 本文是**索引**：告诉你在哪找、怎么查、每个系统多少量。深度分析见 `analysis/01-*.md` 起。

## 1. 怎么看

```bash
export/text/          # 全量可读目录树，路径与 PVF 内一致（追加 .txt）
export/text/skill/    #   例：技能
export/_meta/         # 索引/注册表/字符串表
export/_meta/index.sqlite   # 全量索引，可用 SQL 查
```

三种查法：

```bash
# ① 按目录浏览（.txt 就是 PVF 里的标签流原文）
ls export/text/skill/swordman | head

# ② 全文搜索标签/数值（例：找所有带 [cooltime] 的技能）
rg -l '^\[cooltime\]' export/text/skill --glob '*.skl.txt' | head

# ③ SQL 查索引（例：某目录下最大的文件）
sqlite3 export/_meta/index.sqlite "select path,size from files where path like 'monster/casillas/%' order by size desc limit 5"
```

## 2. 规模

| 根目录 | 文件数 | 内容 |
|---|---:|---|
| `equipment` | 694,560 | 装备与时装（.equ）及其动画 |
| `monster` | 369,169 | 怪物数据 + 动作脚本 + AI + 攻击盒 |
| `passiveobject` | 192,420 | 被动对象（陷阱/机关/召唤物） |
| `character` | 71,291 | 14 个职业的骨架、动画、攻击信息 |
| `map` | 40,372 | 地图房间（.map）与地块图集（.til） |
| `stackable` | 33,001 | 材料/消耗品/设计图（.stk） |
| `creature` | 12,285 | 宠物 |
| `aicharacter` | 10,221 | APC（决斗/副本站台 AI） |
| `common` | 7,413 | 公共特效 |
| `skin` | 6,012 | 皮肤 |
| `sqr` | 4,815 | Squirrel 脚本 |
| `n_quest` | 3,859 | 任务 |
| `skill` | 3,685 | 技能（.skl） |
| `appendage` | 3,384 | buff/状态（.apd） |
| `npc` | 1,841 | NPC |
| `ui` | 1,468 | 界面 |
| `etc` | 1,378 | 杂项配置 |
| `dungeon` | 1,059 | 副本（.dgn） |
| `uniquebeast` | 631 | 唯一兽 |
| `worldmap` | 561 | 世界地图 |
| `localization` | 478 | 本地化特效 |
| `town` | 215 | 城镇 |
| `itemshop` | 135 | 商店 |
| `chatemoticon` | 132 | 聊天表情 |
| `pvp_mission` | 128 | 决斗任务 |
| `event` | 107 | 活动 |
| `region` | 57 | 区域 |
| `clientonly` | 40 | 客户端专用 |
| `aura` | 21 | 光环 |
| `cashshop` | 18 | 商城 |
| `data` | 15 |  |
| `pet` | 9 |  |
| `stagemap` | 5 |  |
| `nexon` | 5 |  |
| `stringtable.bin` | 1 |  |
| `n_string.lst` | 1 |  |

扩展名分布（top 24）：

| 扩展名 | 文件数 | 合计字节 | 性质 |
|---|---:|---:|---|
| `.ani` | 1,058,561 | 449,016,896 | 二进制动画（待 P0.5） |
| `.equ` | 108,645 | 68,439,248 | 标签流 |
| `.act` | 77,511 | 26,000,588 | 标签流（动作脚本） |
| `.als` | 77,490 | 14,145,832 | 标签流（动作链接） |
| `.stk` | 28,794 | 11,968,620 | 标签流 |
| `.obj` | 24,436 | 2,181,804 | 标签流 |
| `.atk` | 18,877 | 2,643,308 | 标签流 |
| `.ai` | 13,969 | 2,414,540 | 标签流 |
| `.til` | 9,944 | 15,320,924 | 标签流 |
| `.ptl` | 6,632 | 1,048,228 | 标签流 |
| `.key` | 6,461 | 516,156 | 标签流 |
| `.map` | 5,800 | 10,131,344 | 标签流 |
| `.mob` | 4,042 | 4,121,536 | 标签流 |
| `.skl` | 4,005 | 9,413,284 | 标签流 |
| `.qst` | 3,852 | 1,100,108 | 标签流 |
| `.apd` | 3,382 | 1,729,324 | 标签流 |
| `.nut` | 2,489 | 16,373,600 | 明文脚本 |
| `.npc` | 811 | 407,480 | 标签流 |
| `.cre` | 631 | 275,888 | 标签流 |
| `.dgn` | 625 | 374,300 | 标签流 |
| `.etc` | 620 | 9,460,580 | 标签流 |
| `.aic` | 595 | 928,564 | 标签流 |
| `.rep` | 484 | 1,172,216 | 标签流 |
| `.ui` | 378 | 369,736 | 标签流 |

## 3. 系统入口（注册表）

每个系统都有一个 `.lst` 把 id 映射到路径。想按 id 找东西，先查这里。

| 系统 | 注册表 | 条目 |
|---|---|---:|
| 角色（.chr） | `export/_meta/lst/character__character.lst` | 11 |
| 技能 · 鬼剑士 | `export/_meta/lst/skill__swordmanskill.lst` | 244 |
| 技能 · 格斗家 | `export/_meta/lst/skill__fighterskill.lst` | 202 |
| 技能 · 神枪手 | `export/_meta/lst/skill__gunnerskill.lst` | 208 |
| 技能 · 魔法师 | `export/_meta/lst/skill__mageskill.lst` | 247 |
| 技能 · 圣职者 | `export/_meta/lst/skill__priestskill.lst` | 237 |
| 技能 · 暗夜使者 | `export/_meta/lst/skill__thiefskill.lst` | 203 |
| 技能 · 魔枪士 | `export/_meta/lst/skill__demoniclancerskill.lst` | 223 |
| 技能 · 黑暗武士 | `export/_meta/lst/skill__demonicswordman.lst` | 214 |
| 技能 · 缔造者 | `export/_meta/lst/skill__creatormage.lst` | 49 |
| 技能 · 鬼剑士(决斗) | `export/_meta/lst/skill__atswordmanskill.lst` | 243 |
| 技能 · 格斗家(决斗) | `export/_meta/lst/skill__atfighterskill.lst` | 215 |
| 技能 · 神枪手(决斗) | `export/_meta/lst/skill__atgunnerskill.lst` | 210 |
| 技能 · 魔法师(决斗) | `export/_meta/lst/skill__atmageskill.lst` | 229 |
| 技能 · 圣职者(决斗) | `export/_meta/lst/skill__atpriestskill.lst` | 235 |
| 技能 · 通用自动 | `export/_meta/lst/skill__autoskill.lst` | 9 |
| 技能 · 总表 | `export/_meta/lst/skill__skilllist.lst` | 11 |
| 副本（.dgn） | `export/_meta/lst/dungeon__dungeon.lst` | 591 |
| 地图（.map） | `export/_meta/lst/map__map.lst` | 4,592 |
| 怪物（.mob） | `export/_meta/lst/monster__monster.lst` | 3,549 |
| NPC（.npc） | `export/_meta/lst/npc__npc.lst` | 610 |
| 任务（.qst） | `export/_meta/lst/n_quest__quest.lst` | 340 |
| 可堆叠物品（.stk） | `export/_meta/lst/stackable__stackable.lst` | 32,171 |
| 装备（.equ） | `export/_meta/lst/equipment__equipment.lst` | 102,330 |
| 被动对象（.obj） | `export/_meta/lst/passiveobject__passiveobject.lst` | 17,692 |
| 附加体（.apd） | `export/_meta/lst/appendage__appendage.lst` | 1,867 |
| 宠物（.cre） | `export/_meta/lst/creature__creature.lst` | 567 |
| 城镇（.twn） | `export/_meta/lst/town__town.lst` | 58 |
| 世界地图 | `export/_meta/lst/worldmap__worldmap.lst` | 74 |
| 区域 | `export/_meta/lst/region__region.lst` | 24 |
| 商店 | `export/_meta/lst/itemshop__itemshop.lst` | 125 |
| AI 角色（APC） | `export/_meta/lst/aicharacter__aicharacter.lst` | 552 |
| 随机词条 | `export/_meta/lst/etc__randomoption__randomoption.lst` | 125 |
| 独立掉落 | `export/_meta/lst/etc__independentdrop.lst` | 161 |
| 决斗任务 | `export/_meta/lst/pvp_mission__mission.lst` | 108 |
| 活动 · 大富翁 | `export/_meta/lst/event__bluemarble__bluemarblemap.lst` | 5 |

## 4. 职业与技能量

14 个职业树。技能注册表条目 = 该职业可用技能数（含转职前后与 TP/被动）。

| 职业树 | 中文 | 技能注册表条目 | character/ 下文本文件 |
|---|---|---:|---:|
| `swordman` | 鬼剑士 | 244 | 2,571 |
| `fighter` | 格斗家 | 202 | 1,004 |
| `gunner` | 神枪手 | 208 | 1,093 |
| `mage` | 魔法师 | 247 | 2,218 |
| `priest` | 圣职者 | 237 | 2,354 |
| `thief` | 暗夜使者 | 203 | 644 |
| `demoniclancer` | 魔枪士 | 223 | 549 |
| `demonicswordman` | 黑暗武士 | 214 | 0 |
| `creatormage` | 缔造者 | 49 | 0 |
| `gunblader` | 枪剑士 | — | 2 |
| `expertjob` | 外传职业 | — | 4 |

## 5. 副本清单（前 40，共见注册表）

| id | 路径 |
|---:|---|
| 15054 | `raid_luke/phase1/sanctum_of_birth.dgn` |
| 15055 | `raid_luke/phase1/sanctum_of_extinction.dgn` |
| 15056 | `raid_luke/phase1/sanctum_of_spread.dgn` |
| 15154 | `raid_luke/phase1_new/sanctum_of_birth_0.dgn` |
| 15155 | `raid_luke/phase1_new/sanctum_of_birth_1.dgn` |
| 15156 | `raid_luke/phase1_new/sanctum_of_birth_2.dgn` |
| 15157 | `raid_luke/phase1_new/sanctum_of_extinction_0.dgn` |
| 15158 | `raid_luke/phase1_new/sanctum_of_extinction_1.dgn` |
| 15159 | `raid_luke/phase1_new/sanctum_of_extinction_2.dgn` |
| 15160 | `raid_luke/phase1_new/sanctum_of_spread_0.dgn` |
| 15161 | `raid_luke/phase1_new/sanctum_of_spread_1.dgn` |
| 15162 | `raid_luke/phase1_new/sanctum_of_spread_2.dgn` |
| 15059 | `raid_luke/phase2/buff_strengthen.dgn` |
| 15312 | `raid_luke/phase2/dark_energy_enter_easy.dgn` |
| 15058 | `raid_luke/phase2/dark_energy.dgn` |
| 15065 | `raid_luke/phase2/dark_temple.dgn` |
| 15063 | `raid_luke/phase2/energy_control.dgn` |
| 15066 | `raid_luke/phase2/energy_save.dgn` |
| 15310 | `raid_luke/phase2/light_energy_enter_easy.dgn` |
| 15057 | `raid_luke/phase2/light_energy.dgn` |
| 15064 | `raid_luke/phase2/light_temple.dgn` |
| 15062 | `raid_luke/phase2/luke_dark_1.dgn` |
| 15061 | `raid_luke/phase2/luke_light_1.dgn` |
| 15060 | `raid_luke/phase2/pattern_strengthen.dgn` |
| 2021 | `2021/2021.dgn` |
| 6401 | `KContents2/Siroco_raid_hard/Phase1/100000235_Borderline_of_Illusions.dgn` |
| 6402 | `shengmojiefuben/moshoufuben5.dgn` |
| 6403 | `Event/chn_golden_silver_monster_Dungeon/chn_golden_monster_dungeon3.dgn` |
| 7601 | `Event/chn_golden_silver_monster_Dungeon/chn_golden_monster_dungeon1.dgn` |
| 7602 | `Event/chn_golden_silver_monster_Dungeon/chn_golden_monster_dungeon2.dgn` |
| 7603 | `towers_1/11.dgn` |
| 7604 | `towers/championtower5.dgn` |
| 6404 | `kcontents3/theevildomgathering/8058.dgn` |
| 8063 | `kcontents3/theevildomgathering/8063.dgn` |
| 4391 | `2022/MeisterLaboratory/Dungeon/2Phase/MeisterLaboratory_2_copy0001.dgn` |
| 4394 | `2022/MeisterLaboratory/Dungeon/2Phase/MeisterLaboratory_2_copy0002.dgn` |
| 4395 | `2022/MeisterLaboratory/Dungeon/2Phase/MeisterLaboratory_2_copy0003.dgn` |
| 1 | `act1/lorien.dgn` |
| 2 | `act1/lorieninside.dgn` |
| 3 | `act1/mirkwood.dgn` |
| … | 共 591 条 |

## 6. 下一步

- `.ani` 二进制还没解（106 万文件），动画帧/攻击盒取不出来 → **P0.5**
- 图片在客户端 `ImagePacks2/*.NPK`（33GB），需要 NPK 解码 → **P0.6**
- 引用图（技能→动作→动画→图片）是分析骨架 → **P0.7**
- 各系统深度分析文档 → **P1**（按垂直切片优先级）

字段含义速查：`docs/PVF-FORMAT.md`；阶段计划：`docs/ROADMAP.md`。
