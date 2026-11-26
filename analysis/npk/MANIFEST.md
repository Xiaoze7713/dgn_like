# analysis/npk 样例清单

由 `python3 tools/npk_parser.py samples --out analysis/npk` 生成。

| 文件 | 尺寸 | IMG | 帧 | 说明 |
| --- | --- | --- | --- | --- |
| `v2_argb8888_swordman_avatar_000.png` | 85x114 | `sprite/character/swordman/equipment/avatar/skin/sm_body16800.img` | 0 | v2 / ARGB8888 / zlib —— 剑士装扮皮肤，四帧站立 |
| `v2_argb8888_swordman_avatar_001.png` | 85x114 | `sprite/character/swordman/equipment/avatar/skin/sm_body16800.img` | 1 | v2 / ARGB8888 / zlib —— 剑士装扮皮肤，四帧站立 |
| `v2_argb8888_swordman_avatar_002.png` | 82x114 | `sprite/character/swordman/equipment/avatar/skin/sm_body16800.img` | 2 | v2 / ARGB8888 / zlib —— 剑士装扮皮肤，四帧站立 |
| `v2_argb8888_swordman_avatar_003.png` | 101x104 | `sprite/character/swordman/equipment/avatar/skin/sm_body16800.img` | 3 | v2 / ARGB8888 / zlib —— 剑士装扮皮肤，四帧站立 |
| `v2_argb1555_skilleffect_000.png` | 422x406 | `sprite/character/fighter/effect/chainawakeningskill/finish01.img` | 0 | v2 / ARGB1555(0x0E) —— 格斗家觉醒技特效 |
| `v2_argb1555_skilleffect_003.png` | 398x405 | `sprite/character/fighter/effect/chainawakeningskill/finish01.img` | 3 | v2 / ARGB1555(0x0E) —— 格斗家觉醒技特效 |
| `v2_argb1555_skilleffect_006.png` | 400x410 | `sprite/character/fighter/effect/chainawakeningskill/finish01.img` | 6 | v2 / ARGB1555(0x0E) —— 格斗家觉醒技特效 |
| `v2_argb1555_skillshop_000.png` | 142x48 | `sprite/interface2/ui/skillshop/tp_skill_able.img` | 0 | v2 / ARGB1555(0x0E) —— 技能商店可购买标记 |
| `v2_argb1555_skillshop_004.png` | 142x48 | `sprite/interface2/ui/skillshop/tp_skill_able.img` | 4 | v2 / ARGB1555(0x0E) —— 技能商店可购买标记 |
| `v2_argb1555_skillshop_008.png` | 142x48 | `sprite/interface2/ui/skillshop/tp_skill_able.img` | 8 | v2 / ARGB1555(0x0E) —— 技能商店可购买标记 |
| `v2_monster_with_reference_000.png` | 67x113 | `sprite/monster/skillhuntress/skillhuntress.img` | 0 | v2 / 0x0E + 0x11 混排 —— 怪物图（含指向帧） |
| `v2_monster_with_reference_002.png` | 74x112 | `sprite/monster/skillhuntress/skillhuntress.img` | 2 | v2 / 0x0E + 0x11 混排 —— 怪物图（含指向帧） |
| `v2_monster_with_reference_004.png` | 85x107 | `sprite/monster/skillhuntress/skillhuntress.img` | 4 | v2 / 0x0E + 0x11 混排 —— 怪物图（含指向帧） |
| `v2_argb4444_customui_000.png` | 65x66 | `sprite/character/common/customui/block.img` | 0 | v2 / ARGB4444(0x0F) —— 自定义 UI 格挡标记 |
| `v2_argb4444_customui_001.png` | 65x64 | `sprite/character/common/customui/block.img` | 1 | v2 / ARGB4444(0x0F) —— 自定义 UI 格挡标记 |
| `v2_argb4444_customui_002.png` | 65x64 | `sprite/character/common/customui/block.img` | 2 | v2 / ARGB4444(0x0F) —— 自定义 UI 格挡标记 |
| `v2_reference_chain_000.png` | 62x127 | `sprite/character/priest/equipment/weapon/cross/pr_cross4100d.img` | 0 | v2 / 指向帧(reference) —— 0 是实体图，169 是 linkTo 0 的指向帧（解出同一张图） |
| `v2_reference_chain_169.png` | 62x127 | `sprite/character/priest/equipment/weapon/cross/pr_cross4100d.img` | 169 | v2 / 指向帧(reference) —— 0 是实体图，169 是 linkTo 0 的指向帧（解出同一张图） |
| `v5_argb8888_digit_000.png` | 7x10 | `sprite/common/digit/red_systemfont.img` | 0 | v5 / 共享 DDS 裁剪帧 —— 红色数字字体 |
| `v5_argb8888_digit_010.png` | 75x45 | `sprite/common/digit/red_systemfont.img` | 10 | v5 / 共享 DDS 裁剪帧 —— 红色数字字体 |
| `v5_ddsref_raid_000.png` | 32x47 | `sprite/interface2/raid/raid_channel_cn.img` | 0 | v5 / compressed=0x07 的 64 字节记录 + DDS 裁剪 —— 团队频道横幅 |
| `v5_ddsref_raid_001.png` | 47x32 | `sprite/interface2/raid/raid_channel_cn.img` | 1 | v5 / compressed=0x07 的 64 字节记录 + DDS 裁剪 —— 团队频道横幅 |
| `v5_ddsref_raid_002.png` | 32x47 | `sprite/interface2/raid/raid_channel_cn.img` | 2 | v5 / compressed=0x07 的 64 字节记录 + DDS 裁剪 —— 团队频道横幅 |
| `v5_ddsref_raid_003.png` | 32x47 | `sprite/interface2/raid/raid_channel_cn.img` | 3 | v5 / compressed=0x07 的 64 字节记录 + DDS 裁剪 —— 团队频道横幅 |
| `v5_dxt1_monsterface_000.png` | 24x23 | `sprite/monster/ch_monsterface.img` | 0 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v5_dxt1_monsterface_001.png` | 24x24 | `sprite/monster/ch_monsterface.img` | 1 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v5_dxt1_monsterface_002.png` | 24x24 | `sprite/monster/ch_monsterface.img` | 2 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v5_dxt1_monsterface_003.png` | 24x24 | `sprite/monster/ch_monsterface.img` | 3 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v5_dxt1_monsterface_004.png` | 24x24 | `sprite/monster/ch_monsterface.img` | 4 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v5_dxt1_monsterface_005.png` | 24x24 | `sprite/monster/ch_monsterface.img` | 5 | v5 / DXT1(0x12) 共享贴图裁剪 —— 怪物头像图集 |
| `v4_palette_indexed.png` | 16x16 | `(合成 IMG)` | 0 | v4 / 调色板索引(0x0E+palette) —— 合成样例 |
| `v6_multi_palette.png` | 16x16 | `(合成 IMG)` | 0 | v6 / 多调色板(取 0 号) —— 合成样例 |
| `dxt1_red_block.png` | 4x4 | `(合成 DXT 块)` | 0 | DXT1 纯红块 |
| `dxt3_alpha_steps.png` | 4x4 | `(合成 DXT 块)` | 0 | DXT3 alpha 阶梯 |
| `dxt5_alpha_steps.png` | 4x4 | `(合成 DXT 块)` | 0 | DXT5 alpha 8 级插值 |
| `compose_ani_img_offset.png` | 400x400 | `sprite/character/swordman/equipment/avatar/skin/sm_body0000.img` | 0 | attack1.ani 前 8 帧叠加：验证 draw=(ani.x+img.x, ani.y+img.y)，脚落在原点 |
