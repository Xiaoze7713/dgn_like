# PVF 依赖图报告

- 节点 **1,460,792**　边 **2,589,988**　注册表 **171,325**　断链 **227,725**

## 1. 出边：谁引用谁

| 源类型 | 目标类型 | 边数 |
| --- | --- | --- |
| `ani` | `img` | 1,034,774 |
| `als` | `ani` | 216,328 |
| `equ` | `img` | 206,363 |
| `act` | `ani` | 191,846 |
| `equ` | `lay` | 165,708 |
| `map` | `ani` | 140,959 |
| `lst` | `equ` | 106,484 |
| `stk` | `img` | 88,233 |
| `map` | `til` | 60,957 |
| `mob` | `ai` | 58,916 |
| `mob` | `act` | 46,369 |
| `obj` | `act` | 38,012 |
| `lst` | `stk` | 28,017 |
| `lst` | `obj` | 18,293 |
| `obj` | `ani` | 11,699 |
| `mob` | `atk` | 11,633 |
| `obj` | `atk` | 11,390 |
| `dgn` | `map` | 10,476 |
| `etc` | `ani` | 9,910 |
| `ptl` | `ani` | 9,558 |
| `mob` | `ani` | 9,350 |
| `til` | `img` | 9,206 |
| `skl` | `img` | 8,008 |
| `equ` | `ani` | 7,911 |
| `act` | `ptl` | 7,513 |
| `dgn` | `obj` | 5,785 |
| `map` | `dgn` | 4,828 |
| `qst` | `npc` | 4,547 |
| `cre` | `ani` | 4,539 |
| `equ` | `apd` | 4,397 |
| `chr` | `ani` | 4,143 |
| `ani` | `` | 4,139 |
| `mob` | `img` | 4,132 |
| `lst` | `mob` | 3,550 |
| `lst` | `map` | 3,211 |
| `act` | `act` | 3,101 |
| `lst` | `skl` | 2,968 |
| `ui` | `img` | 2,687 |
| `npc` | `img` | 2,064 |
| `dgn` | `img` | 1,865 |

## 2. 入度最高（被最多文件引用）

| 目标 | 入边数 |
| --- | --- |
| `item/iconmark.img` | 73,550 |
| `item/fieldimage.img` | 37,092 |
| `equipment/character/mage.lay` | 28,631 |
| `item/field_equip.img` | 19,158 |
| `equipment/character/swordman.lay` | 17,160 |
| `equipment/character/gunner.lay` | 15,257 |
| `equipment/character/fighter.lay` | 14,749 |
| `equipment/character/priest.lay` | 14,046 |
| `equipment/character/atfighter.lay` | 13,067 |
| `equipment/character/dsswordman.lay` | 12,481 |
| `equipment/character/atgunner.lay` | 12,222 |
| `equipment/character/atswordman.lay` | 10,661 |
| `equipment/character/atmage.lay` | 9,857 |
| `equipment/character/atpriest.lay` | 7,734 |
| `equipment/character/thief.lay` | 7,190 |
| `interface2/gcontents/200618_miangdevilpalace/200618_devilpalacesaga_icons.img` | 6,273 |
| `interface2/gcontents/200618_miangdevilpalace/200618_devilpalacesaga_fieldmaterial.img` | 6,259 |
| `item/iconmaterial2.img` | 6,224 |
| `item/field_weapon.img` | 6,121 |
| `monster/monsterface.img` | 4,704 |
| `common/commoneffect2/glow/base_circle.img` | 4,575 |
| `common/commoneffect/glow/circle.img` | 4,534 |
| `monster/gcontents/190307_preyraid/commoneffect/warningfloor_line.img` | 4,151 |
| `.` | 3,967 |
| `item/stackable/consumption.img` | 3,664 |

## 3. 出度最高（依赖最多）

| 源 | 出边数 |
| --- | --- |
| `equipment/equipment.lst` | 102,330 |
| `stackable/stackable.lst` | 32,171 |
| `passiveobject/passiveobject.lst` | 17,691 |
| `etc/skillpreload.etc` | 9,701 |
| `monster/monster.lst` | 3,549 |
| `map/map.lst` | 3,211 |
| `appendage/appendage.lst` | 1,863 |
| `character/swordman/atswordman.chr` | 1,013 |
| `npc/npc.lst` | 610 |
| `passiveobject/old passiveobject.lst` | 604 |
| `dungeon/dungeon.lst` | 591 |
| `passiveobject/2022/meisterlaboratory/monster/2phase/verlorenstark/passiveobject/enrage/action/enrage_scene_1_basic.act` | 569 |
| `creature/creature.lst` | 567 |
| `etc/effectlevel.etc` | 558 |
| `aicharacter/aicharacter.lst` | 552 |
| `character/mage/atmage.chr` | 549 |
| `character/priest/atpriest.chr` | 516 |
| `dungeon/act7/counterattack.dgn` | 514 |
| `character/demoniclancer/demonicswordman.chr` | 505 |
| `character/priest/priest.chr` | 475 |
| `character/swordman/swordman.chr` | 460 |
| `character/thief/thief.chr` | 399 |
| `monster/meisterlaboratory/monster/2phase/verlorenstark/passiveobject/coreeffect/action/coreeffect_basic.act` | 360 |
| `passiveobject/2022/meisterlaboratory/monster/2phase/verlorenstark/passiveobject/coreeffect/action/coreeffect_basic.act` | 360 |
| `character/fighter/atfighter.chr` | 353 |

## 4. 断链（引用指向不存在的文件）

| 后缀 | 条数 | 例子 |
| --- | --- | --- |
| `ani` | 209,894 | `(0824)crystal.ani` |
| `key` | 6,150 | `1.key` |
| `ai` | 5,223 | `1.ai` |
| `ptl` | 2,293 | `../../../../../passiveobject/actionobject/common/particle/stone_0.ptl` |
| `equ` | 1,210 | `character/common/belt/harmor/115506.equ` |
| `act` | 1,145 | `../../castleofthedead/light_knight/action/sphere_light.act` |
| `atk` | 709 | `../../attackinfo/hit.atk` |
| `map` | 459 | `1_new/cataclysm/town/alfhlyra/alfhlyra_l.map` |
| `til` | 292 | `tile/bosstile_00.til` |
| `aic` | 134 | `priest/doran/doran.aic` |
| `lua` | 68 | `action.lua` |
| `obj` | 53 | `character/fighter/energyballsub.obj` |
| `tbl` | 52 | `dungeon/anton_awakening/table/monsterapcdifficultybonus_raid1.tbl` |
| `wrd` | 26 | `bluesnatchingpanda.wrd` |
| `rep` | 10 | `replay/atfighter/combo711.rep` |
| `skl` | 4 | `animation_y/skill/skill.skl` |
| `ui` | 2 | `ui/actionpointsystem/apsystem_main.ui` |
| `shp` | 1 | `avagacha.shp` |

## 5. 各类型节点数与平均出度

| 后缀 | 节点数 | 有出边的 | 平均出度 |
| --- | --- | --- | --- |
| `ani` | 1,058,561 | 1,024,407 | 0.98 |
| `equ` | 108,645 | 107,588 | 3.56 |
| `act` | 77,511 | 70,194 | 2.63 |
| `als` | 77,490 | 34,753 | 2.81 |
| `stk` | 28,794 | 28,789 | 3.10 |
| `obj` | 24,436 | 24,006 | 2.61 |
| `atk` | 18,877 | 0 | 0.00 |
| `ai` | 13,969 | 712 | 0.12 |
| `til` | 9,944 | 9,140 | 0.93 |
| `ptl` | 6,632 | 2,714 | 1.46 |
| `key` | 6,461 | 105 | 0.03 |
| `map` | 5,800 | 5,791 | 35.66 |
| `mob` | 4,042 | 4,041 | 32.37 |
| `skl` | 4,005 | 3,644 | 2.02 |
| `qst` | 3,852 | 3,723 | 1.38 |
| `apd` | 3,382 | 11 | 0.01 |
| `nut` | 2,489 | 0 | 0.00 |
| `npc` | 811 | 810 | 3.57 |
| `cre` | 631 | 628 | 8.23 |
| `dgn` | 625 | 625 | 30.21 |
| `etc` | 620 | 31 | 18.25 |
| `aic` | 595 | 73 | 0.43 |
| `rep` | 484 | 0 | 0.00 |
| `ui` | 378 | 309 | 10.49 |
| `ani(diff)` | 166 | 4 | 0.16 |

## 6. 孤立节点（无人引用）

- 无入边节点：**769,229** / 1,460,792

