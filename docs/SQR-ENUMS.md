# SQR 全局枚举对照表（dnf_enum_header.nut）

> 源文件：`sqr/dnf_enum_header.nut`（Squirrel / CP949，1403 行）
> 生成方式：从源文件逐行解析（常量名、值均由脚本取出，未手抄），韩文注释人工译为中文。

## 总述

这就是原版客户端**唯一一张全局枚举表**：把 C++ 侧的 `enum`（地形、怪物分类、状态机、技能 ID、装备类型、绘制层、热键……）抄成 Squirrel 常量，所有 `.nut` 共享同一个全局命名空间，所以任何脚本都能直接写 `STATE_ATTACK`。

- **常量数**：`1315` 个有效常量，分 `57` 族（按名字前缀切分，族序 = 源文件行序）。
- **注释**：`1187` 条带韩文注释，`128` 条原文件没注释（说明列按常量名推断，末尾标「推断」）。
- **源文件里的 `<-`**：共 `1323` 行，其中 `8` 行是注释掉的旧值（见文末附录），`1315` 行有效。
- **在 Godot 里怎么用**：这些常量已经由 `tools/sqr_consts.py` 全量生成进基类 `SqrConsts`（`sqr_gd/sqr_consts.gd`），翻译脚本 `extends SqrScript` 后**直接裸用同名常量**，不需要前缀、也不需要在本表对应文件里重复声明。本表只作文档对照。
- **不在本表的东西**：非整数 slot（如 `common.nut` 的 `DEBUG <- isDebugMode()`、字符串、数组、表、函数引用）不生成常量，因此也不在本表。本文件内没有这类 slot。

## 目录

1. [地形类型 LANDTYPE_*](#地形类型-landtype_)（12）
2. [地面粒子 LANDPARTICLE_*](#地面粒子-landparticle_)（3）
3. [地面音效 LANDSOUND_*](#地面音效-landsound_)（6）
4. [对象分类 CATEGORY_*](#对象分类-category_)（44）
5. [浮空/击退参数类型 DOWN_PARAM_TYPE_*](#浮空击退参数类型-down_param_type_)（5）
6. [方向 ENUM_DIRECTION_*](#方向-enum_direction_)（6）
7. [画面特效 GRAPHICEFFECT_*](#画面特效-graphiceffect_)（8）
8. [绘制层 ENUM_DRAWLAYER_*](#绘制层-enum_drawlayer_)（8）
9. [角色状态机（格斗家系）STATE_*](#角色状态机格斗家系state_)（76）
10. [技能 ID（格斗家系）SKILL_*](#技能-id格斗家系skill_)（124）
11. [自定义动画编号（格斗家系）CUSTOM_ANI_*](#自定义动画编号格斗家系custom_ani_)（140）
12. [攻击信息槽（格斗家系）CUSTOM_ATTACKINFO_*](#攻击信息槽格斗家系custom_attackinfo_)（84）
13. [武器子类型（格斗家）WEAPON_SUBTYPE_*](#武器子类型格斗家weapon_subtype_)（7）
14. [附加体循环音效 SOUND_ID_*](#附加体循环音效-sound_id_)（17）
15. [状态优先级 STATE_PRIORITY_*](#状态优先级-state_priority_)（5）
16. [角色状态机（男格斗/圣职者系）STATE_*](#角色状态机男格斗圣职者系state_)（39）
17. [技能 ID（男格斗/圣职者系）SKILL_*](#技能-id男格斗圣职者系skill_)（122）
18. [自定义动画编号（圣职者系）CUSTOM_ANI_*](#自定义动画编号圣职者系custom_ani_)（79）
19. [攻击信息槽（圣职者系）CUSTOM_ATTACKINFO_*](#攻击信息槽圣职者系custom_attackinfo_)（70）
20. [攻击方向 ATTACK_DIRECTION_*](#攻击方向-attack_direction_)（4）
21. [攻击类型 ATTACKTYPE_*](#攻击类型-attacktype_)（4）
22. [攻击目标 ATTACKTARGET_*](#攻击目标-attacktarget_)（3）
23. [伤害反应 DAMAGEACT_*](#伤害反应-damageact_)（4）
24. [击退类型 KNOCK_BACK_TYPE_*](#击退类型-knock_back_type_)（5）
25. [受击方向 HIT_DIRECTION_*](#受击方向-hit_direction_)（5）
26. [武器子类型（圣职者）WEAPON_SUBTYPE_*](#武器子类型圣职者weapon_subtype_)（6）
27. [成长类型 GROW_TYPE_*（第一次定义）](#成长类型-grow_type_第一次定义)（6）
28. [拳气延伸动作 EXTENDED_PUNCH_MOTION_*](#拳气延伸动作-extended_punch_motion_)（3）
29. [普攻类型 BASE_ATTACK_TYPE_*](#普攻类型-base_attack_type_)（3）
30. [战斗光环动作 BATTLE_AURA_MOTION_*](#战斗光环动作-battle_aura_motion_)（8）
31. [状态变更类型 CHANGE_STATUS_TYPE_*](#状态变更类型-change_status_type_)（98）
32. [装备类型 ENUM_EQUIPMENTTYPE_*](#装备类型-enum_equipmenttype_)（43）
33. [技能 ID（通用/基础精通）SKILL_*](#技能-id通用基础精通skill_)（38）
34. [异常状态 ACTIVESTATUS_*](#异常状态-activestatus_)（19）
35. [成长类型 GROW_TYPE_*（重复定义）](#成长类型-grow_type_重复定义)（5）
36. [职业 ENUM_CHARACTERJOB_*](#职业-enum_characterjob_)（12）
37. [动画布尔参数 ENUM_IS_* / ENUM_ANIMATION_BOOL_MAX](#动画布尔参数-enum_is_-enum_animation_bool_max)（8）
38. [模块类型 MODULE_TYPE_*](#模块类型-module_type_)（22）
39. [攻击类型（扩充）ATTACKTYPE_*](#攻击类型扩充attacktype_)（8）
40. [增益来源 BUFF_*](#增益来源-buff_)（6）
41. [暂停类型 PAUSETYPE_*](#暂停类型-pausetype_)（3）
42. [属性 ENUM_ELEMENT_*](#属性-enum_element_)（6）
43. [投掷/设置道具 THROW_TYPE_* / SETUP_TYPE_*](#投掷设置道具-throw_type_-setup_type_)（3）
44. [速度类型 SPEED_TYPE_*](#速度类型-speed_type_)（5）
45. [Z 轴加速度类型 Z_ACCEL_TYPE_*](#z-轴加速度类型-z_accel_type_)（4）
46. [静态信息深度 STATICINFO_DEPTH](#静态信息深度-staticinfo_depth)（1）
47. [移动速度基准 X_* / Y_*](#移动速度基准-x_-y_)（4）
48. [物理常数 FORCE_TO_VELOCITY_CONST / SPEED_VALUE_DEFAULT](#物理常数-force_to_velocity_const-speed_value_default)（2）
49. [音效重量与重力 LIGHT_* / MIDDLE_* / DEFAULT_GRAVITY_ACCEL](#音效重量与重力-light_-middle_-default_gravity_accel)（3）
50. [对象消息 OBJECT_MESSAGE_*](#对象消息-object_message_)（5）
51. [恢复类型 RECOVER_TYPE_*](#恢复类型-recover_type_)（4）
52. [原因 REASON_*](#原因-reason_)（5）
53. [移动热键（第一次定义）OPTION_HOTKEY_MOVE_*](#移动热键第一次定义option_hotkey_move_)（5）
54. [成长类型（男魔法师）GROW_TYPE_*](#成长类型男魔法师grow_type_)（3）
55. [打击粒子 PARTICLE_CREATER_*](#打击粒子-particle_creater_)（7）
56. [热键定义 OPTION_HOTKEY_*](#热键定义-option_hotkey_)（88）
57. [通用技能：破坏者 STATE_BURSTER / SKILL_BURSTER](#通用技能破坏者-state_burster-skill_burster)（2）

## 地形类型 LANDTYPE_*（12 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `LANDTYPE_GRASS` | 0 | 草地 |
| `LANDTYPE_WETGRASS` | 1 | 湿草地（被水浸湿的草地） |
| `LANDTYPE_SWAMP` | 2 | 沼泽上方 |
| `LANDTYPE_POISONSWAMP` | 3 | 毒沼泽上方 |
| `LANDTYPE_BROWNDIRT` | 4 | 褐色泥土 |
| `LANDTYPE_BLUEDIRT` | 5 | 蓝色泥土 |
| `LANDTYPE_BONEYARD` | 6 | 骨堆上方 |
| `LANDTYPE_WATER` | 7 | 水中 |
| `LANDTYPE_MAGMA` | 8 | 岩浆上方 |
| `LANDTYPE_SNOW` | 9 | 雪地上 |
| `LANDTYPE_RED_SWAMP` | 10 | 红色沼泽（推断） |
| `LANDTYPE_PURPLE_POISONSWAMP` | 11 | 紫色毒沼泽 |

## 地面粒子 LANDPARTICLE_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `LANDPARTICLE_DOWNLARGE` | 0 | 大型落地粒子（推断） |
| `LANDPARTICLE_DOWNSMALL` | 1 | 小型落地粒子（推断） |
| `LANDPARTICLE_MOVE` | 2 | 移动粒子（推断） |

## 地面音效 LANDSOUND_*（6 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `LANDSOUND_JUMPSTART` | 0 | 起跳音效（推断） |
| `LANDSOUND_JUMPLAND` | 1 | 落地音效（推断） |
| `LANDSOUND_MOVE` | 2 | 移动音效（推断） |
| `LANDSOUND_DASH` | 3 | 冲刺音效（推断） |
| `LANDSOUND_BACKSTEP` | 4 | 后撤步音效（推断） |
| `LANDSOUND_FASTTHROUGH` | 5 | 快速穿越音效（推断） |

## 对象分类 CATEGORY_*（44 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `CATEGORY_TRIBE_HUMAN` | 0 | 人型种族 |
| `CATEGORY_TRIBE_BEAST` | 1 | 兽族 |
| `CATEGORY_TRIBE_PLANT` | 2 | 植物 |
| `CATEGORY_TRIBE_INSECT` | 3 | 昆虫 |
| `CATEGORY_TRIBE_MACHINE` | 4 | 机械 |
| `CATEGORY_TRIBE_ORGANIC` | 5 | 有机体 |
| `CATEGORY_TRIBE_HYBRID` | 6 | 复合体 |
| `CATEGORY_TRIBE_UNDEAD` | 7 | 亡灵 |
| `CATEGORY_TRIBE_DEVIL` | 8 | 恶魔 |
| `CATEGORY_TRIBE_SPIRIT` | 9 | 精灵 |
| `CATEGORY_TRIBE_DRAGON` | 10 | 龙族 |
| `CATEGORY_AI_MELEE_ATTACK` | 11 | 仅近战攻击的怪物 |
| `CATEGORY_AI_RANGE_ATTACK` | 12 | 仅远程射击的怪物 |
| `CATEGORY_AI_NEGATIVE` | 13 | 消极型怪物 |
| `CATEGORY_AI_CAREFUL` | 14 | 谨慎型怪物 |
| `CATEGORY_AI_FULLSUPERARMOR` | 15 | 近战AI杀威胁怪时满霸体 |
| `CATEGORY_AI_RASH` | 16 | 鲁莽型怪物 |
| `CATEGORY_AI_MANACE` | 17 | 威胁型怪物 |
| `CATEGORY_ARMOR_HUMAN` | 18 | 人型护甲（受即死类选项影响） |
| `CATEGORY_ARMOR_FORT` | 19 | 建筑护甲（受破坏类选项影响） |
| `CATEGORY_ARMOR_DIVINE` | 20 | 圣灵护甲（防御力巨幅提升） |
| `CATEGORY_ETC_GOBLIN` | 21 | 哥布林 |
| `CATEGORY_ETC_TAU` | 22 | 牛头怪（Tau） |
| `CATEGORY_ETC_LUGARU` | 23 | 卢加鲁 |
| `CATEGORY_ETC_FIXTURE` | 24 | 固定型（不会被飓风翻滚等拖动） |
| `CATEGORY_ETC_STAY` | 25 | 不离开初始位置 |
| `CATEGORY_PASSIVEOBJECT_TYPE_MELEE` | 26 | 近战型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_MISSILE` | 27 | 导弹型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_ENERGY` | 28 | 能量型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_PHYSICAL` | 29 | 物理型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_MAGICAL` | 30 | 魔法型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_BULLET` | 31 | 子弹型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_CANON` | 32 | 加农炮型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_EXPLOSION` | 33 | 爆炸型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_INFLAME` | 34 | 燃烧型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_NONINFLAME` | 35 | 非燃烧型被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_LIGHT` | 36 | 光属性被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_DARK` | 37 | 暗属性被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_WATER` | 38 | 水属性被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_FIRE` | 39 | 火属性被动对象（推断） |
| `CATEGORY_PASSIVEOBJECT_TYPE_FORT` | 40 | 要塞型被动对象（推断） |
| `CATEGORY_ETC_UNBEATABLE` | 41 | 无敌；带暗黑文章附加体时可被攻击 |
| `CATEGORY_TRIBE_ANGEL` | 42 | 天使 |
| `CATEGORY_MAX` | 43 | 分类最大值（推断） |

## 浮空/击退参数类型 DOWN_PARAM_TYPE_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `DOWN_PARAM_TYPE_VALUE` | 0 | 传入浮空高度与击飞速度 |
| `DOWN_PARAM_TYPE_FORCE` | 1 | 传入力量 |
| `DOWN_PARAM_TYPE_BOUNCE_VALUE` | 2 | 弹跳；值暂存，落地反弹时才用 |
| `DOWN_PARAM_TYPE_BOUNCE_FORCE` | 3 | 弹跳；力暂存，落地反弹时才用 |
| `DOWN_PARAM_TYPE_BOUNCE` | 4 | 弹跳（配合值/力使用） |

## 方向 ENUM_DIRECTION_*（6 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_DIRECTION_LEFT` | 0 | 左（推断） |
| `ENUM_DIRECTION_RIGHT` | 1 | 右（推断） |
| `ENUM_DIRECTION_UP` | 2 | 上（推断） |
| `ENUM_DIRECTION_DOWN` | 3 | 下（推断） |
| `ENUM_DIRECTION_NEUTRAL` | 4 | 无方向/中立（推断） |
| `ENUM_DIRECTION_MAX` | 5 | 方向最大值（推断） |

## 画面特效 GRAPHICEFFECT_*（8 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `GRAPHICEFFECT_NONE` | 0 | 无画面特效 |
| `GRAPHICEFFECT_DODGE` | 1 | 闪避（半透明） |
| `GRAPHICEFFECT_LINEARDODGE` | 2 | 直线闪避 |
| `GRAPHICEFFECT_DARK` | 3 | 暗化 |
| `GRAPHICEFFECT_XOR` | 4 | 异或 |
| `GRAPHICEFFECT_MONOCHROME` | 5 | 单色（灰度） |
| `GRAPHICEFFECT_SPACE_DISTORT` | 6 | 空间扭曲 |
| `GRAPHICEFFECT_MAX` | 7 | 特效最大值（推断） |

## 绘制层 ENUM_DRAWLAYER_*（8 个）

> 由小到大依次压在各层之上；`COVER` 是覆盖全屏（致盲）用。

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_DRAWLAYER_CONTACT` | 0 | 贴地（接触）层 |
| `ENUM_DRAWLAYER_NORMAL` | 1 | 普通层 |
| `ENUM_DRAWLAYER_BOTTOM` | 2 | 地面层 |
| `ENUM_DRAWLAYER_CLOSEBACK` | 3 | 近景层 |
| `ENUM_DRAWLAYER_MIDDLEBACK` | 4 | 中景层 |
| `ENUM_DRAWLAYER_DISTANTBACK` | 5 | 远景层 |
| `ENUM_DRAWLAYER_COVER` | 6 | 覆盖全屏层（例：致盲） |
| `ENUM_DRAWLAYER_MAX` | 7 | 绘制层最大值（推断） |

## 角色状态机（格斗家系）STATE_*（76 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `STATE_STAND` | 0 | 站立、移动 |
| `STATE_SIT` | 1 | 坐下（起身前） |
| `STATE_SIT_FOREVER` | 2 | 保持坐姿 |
| `STATE_DAMAGE` | 3 | 受击 |
| `STATE_DOWN` | 4 | 倒地 |
| `STATE_DIE` | 5 | 死亡 |
| `STATE_JUMP` | 6 | 跳跃 |
| `STATE_JUMP_ATTACK` | 7 | 跳跃攻击 |
| `STATE_ATTACK` | 8 | 普通攻击 |
| `STATE_HOLD` | 9 | 无法行动（被控制） |
| `STATE_SUMMONSTART` | 10 | 召唤开始 |
| `STATE_SUMMONEND` | 11 | 召唤完成 |
| `STATE_UNSUMMON` | 12 | 被反召唤而消失 |
| `STATE_THROW` | 13 | 投掷 |
| `STATE_DASH` | 14 | 冲刺 |
| `STATE_DASH_ATTACK` | 15 | 冲刺攻击 |
| `STATE_GET_ITEM` | 16 | 拾取物品 |
| `STATE_BUFF` | 17 | 增益状态 |
| `STATE_QUICK_STANDING` | 18 | 快速起身 |
| `STATE_CROUCH` | 19 | 蹲伏 |
| `STATE_CROUCH_ATTACK` | 20 | 蹲伏肩撞 |
| `STATE_LOW_KICK` | 21 | 低踢、骨碎击、下段踢 |
| `STATE_TRY_GRAB` | 22 | 尝试抓取 |
| `STATE_SUPLEX` | 23 | 背摔（Suplex） |
| `STATE_JUMP_SUPLEX` | 24 | 空摔（Spire） |
| `STATE_JUMP_SUPLEX_LARIAT` | 25 | 空摔旋转追加攻击 |
| `STATE_MOUNT_TRY` | 26 | 尝试骑乘 |
| `STATE_MOUNT` | 27 | 骑乘压制 |
| `STATE_STOMP` | 28 | 踩踏 |
| `STATE_CLOSE_PUNCH` | 29 | 贴身一拳 |
| `STATE_LIFT_UPPER` | 30 | 浮空上勾拳（Muse Upper） |
| `STATE_GRAB_EXPLOSION` | 31 | 火药星爆破 |
| `STATE_VIRTUAL_ATTACK` | 32 | 普攻用的虚拟STATE（锤击踢等） |
| `STATE_SHOULDER_TACKLE` | 33 | 肩撞 |
| `STATE_WHIRL_WIND_KICK` | 34 | 旋风腿 |
| `STATE_BLOCK_BUSTER` | 35 | 格挡破坏（Block Buster） |
| `STATE_TRY_LEG_SUPLEX` | 36 | 空摔尝试（Air Steiner） |
| `STATE_LEG_SUPLEX` | 37 | 空摔执行（Air Steiner） |
| `STATE_LIGHTNING_DANCE` | 38 | 闪电舞 |
| `STATE_THROW_WEB` | 39 | 天罗地网 |
| `STATE_HIDDEN_STING` | 40 | 装填针（Hidden Sting） |
| `STATE_VENOM_MINE` | 41 | 毒液地雷 |
| `STATE_JUNK_SPIN` | 42 | 废铁旋转 |
| `STATE_SHOULDER_CHARGE` | 43 | 铁山靠（突进） |
| `STATE_SINGLE_KICK` | 44 | 锤击踢（Hammer Kick） |
| `STATE_NEN_FLOWER` | 45 | 念花 |
| `STATE_THROW_ENEMY` | 46 | 擒抱摔投（Ropling） |
| `STATE_DASH_PUNCH` | 47 | 直拳突刺 |
| `STATE_PUNCH_AFTER_RETURN` | 48 | 击打后将对手转向身后 |
| `STATE_RANDOM_KICK` | 49 | 百裂脚乱打 |
| `STATE_RISING_UPPER` | 50 | 升龙拳 |
| `STATE_DASH_AFTER_DASH` | 51 | 护身连击 |
| `STATE_EARTH_BREAK` | 52 | 金刚碎 |
| `STATE_HOLD_UP` | 53 | 举起控制（Hold Up） |
| `STATE_WILD_CANNON_SPIKE` | 54 | 野性炮刺 |
| `STATE_SUPLEX_CYCLONE` | 55 | 背摔旋风 |
| `STATE_LIGHTNING_DRAGON` | 56 | 光冲怒涛 |
| `STATE_STRONGEST_LOW_KICK` | 57 | 史上最强低踢 |
| `STATE_GROUND_KICK` | 58 | 地面踢 |
| `STATE_FAST_DASH` | 59 | 瞬步 |
| `STATE_DESTROY_EARTH_SKY_DROP` | 60 | 街霸觉醒技-天崩地坏 |
| `STATE_TYPHOON` | 61 | 柔道家觉醒技（台风） |
| `STATE_FLAME_LEGS` | 62 | 散打觉醒技-火焰之脚 |
| `STATE_THROW_SAND` | 63 | 撒沙（Helter Skelter） |
| `STATE_ENCHANT_POISON` | 64 | 毒装填 |
| `STATE_SPIRAL_NEN_SHOOT` | 65 | 螺旋念气：出 |
| `STATE_NEN_SPEAR_EX` | 66 | 念矛特性：标记1叠层+闪屏 |
| `STATE_HURRICANE_SPEAR` | 67 | 飓风矛（特性） |
| `STATE_CRASH_ROPE` | 68 | 狂暴血沙（特性） |
| `STATE_CHARGE_SPEAR_EX` | 69 | 充能矛（特性） |
| `STATE_SPIRAL_COLUMN_EX` | 70 | 螺旋环（特性） |
| `STATE_GLUEY_FRUIT_EX` | 71 | 黏黏果实（特性） |
| `STATE_CHAIN_KICK_EX` | 72 | 连环腿（特性） |
| `STATE_108_STAIRS_EX` | 73 | 108阶（特性） |
| `STATE_INHERIT_START` | 74 | 继承技起始（推断） |
| `STATE_MAX` | 75 | 状态最大值（推断） |

## 技能 ID（格斗家系）SKILL_*（124 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `SKILL_SHOULDER_CHARGE` | 1 | 铁山靠 |
| `SKILL_CROUCH` | 2 | 蹲伏 |
| `SKILL_GRAB_EXPLOSION` | 3 | 火药星 |
| `SKILL_CRASH_LOW_KICK` | 4 | 骨碎击（低踢） |
| `SKILL_LIFT_UPPER` | 5 | 缪斯上勾拳 |
| `SKILL_DAMAGE_LOW_KICK` | 6 | 低踢 |
| `SKILL_PHYSICAL_DEFENSE_UP` | 7 | 物理防御力提升 |
| `SKILL_CREATE_ILLUSION` | 8 | 分身 |
| `SKILL_SUPLEX` | 9 | 背摔 |
| `SKILL_BACK_SUPLEX` | 10 | 背摔破坏（Back Breaker） |
| `SKILL_THUNDER_SUPLEX` | 11 | 雷霆背摔 |
| `SKILL_ENERGY_BALL` | 12 | 念弹 |
| `SKILL_THROW_SAND` | 13 | 撒沙（Helter Skelter） |
| `SKILL_MOUNT` | 14 | 骑乘 |
| `SKILL_ROAR_STUN` | 15 | 狮子吼 |
| `SKILL_ENERGY_FIELD` | 16 | 气功掌 |
| `SKILL_STOMP` | 17 | 空中踩踏 |
| `SKILL_JUMP_SUPLEX` | 18 | 空摔（Spire） |
| `SKILL_CLOSE_PUNCH` | 19 | 寸拳 |
| `SKILL_SUPER_ARMOR` | 20 | 霸体 |
| `SKILL_CANCEL_ENERGY_BALL` | 21 | 可取消的念弹 |
| `SKILL_SUPLEX_SUB_POWER_UP` | 22 | 强力摔倒（Take Down） |
| `SKILL_CANCEL_LIFT_UPPER` | 23 | 可取消的缪斯上勾 |
| `SKILL_CANCEL_LOW_KICK` | 24 | 可取消的低踢 |
| `SKILL_CANCEL_THROW_SAND` | 25 | 可取消的撒沙 |
| `SKILL_CANCEL_CLOSE_PUNCH` | 26 | 可取消的寸拳 |
| `SKILL_CANCEL_SUPLEX` | 27 | 可取消的背摔 |
| `SKILL_CANCEL_JUMP_SUPLEX` | 28 | 可取消的空摔 |
| `SKILL_LIGHT_FRIENDSHIP` | 29 | 光之亲和 |
| `SKILL_LIGHT_ENCHANT_WEAPON` | 30 | 凯（Kai） |
| `SKILL_ATTACK_SPEED_UP` | 31 | 活性化呼吸 |
| `SKILL_POISON_TOLERANCE_UP` | 32 | 惯于毒素（毒抗性） |
| `SKILL_STUN_ON_USE_SKILL` | 33 | 走火入魔 |
| `SKILL_EQUIP_BOXING_GLOVE` | 34 | 可使用拳击手套 |
| `SKILL_BLIND_TOLERANCE_UP` | 35 | 以念感知（致盲抗性） |
| `SKILL_LIGHT_TOLERANCE_UP` | 36 | 太阳之幕 |
| `SKILL_SLOW_DOWN_POWER_UP` | 37 | 强拳 |
| `SKILL_ENCHANT_POISON` | 38 | 毒装填（涂毒） |
| `SKILL_AIM_VITAL_POINT` | 39 | 指定要害 |
| `SKILL_SPIRAL_NEN` | 40 | 螺旋念气 |
| `SKILL_FLAME_LEGS` | 41 | 散打觉醒技-火焰之脚 |
| `SKILL_NEN_GUARD` | 42 | 念气盾 |
| `SKILL_DOUBLE_THROW` | 43 | 双重投掷 |
| `SKILL_PROVOCATION` | 44 | 挑衅 |
| `SKILL_CLAW_MASTERY` | 45 | 爪精通 |
| `SKILL_SINGLE_KICK` | 46 | 锤击踢 |
| `SKILL_CANCEL_SINGLE_KICK` | 47 | 可取消的锤击踢 |
| `SKILL_CANCEL_GRAB_EXPLOSION` | 48 | 可取消的火药星 |
| `SKILL_THROW_ENEMY` | 49 | 擒抱摔投 |
| `SKILL_DEFINITE_GRAB` | 50 | 必定抓住！ |
| `SKILL_SLIDE_GRAB` | 51 | 滑行抓取 |
| `SKILL_THROW_WEB` | 52 | 天罗地网 |
| `SKILL_CANCEL_THROW_ENEMY` | 53 | 可取消的擒抱 |
| `SKILL_SHOULDER_TACKLE` | 54 | 肩撞 |
| `SKILL_GRAB_CANNON` | 55 | 抓取炮 |
| `SKILL_ARMOR_MASTERY_LIGHT_SK` | 56 | 溢力轻甲精通 |
| `SKILL_ARMOR_MASTERY_LIGHT_GP` | 57 | 坚韧轻甲精通 |
| `SKILL_WHIRL_WIND_KICK` | 58 | 疾风脚 |
| `SKILL_CANCEL_WHIRL_WIND_KICK` | 59 | 可取消的疾风脚 |
| `SKILL_BLOCK_BUSTER` | 60 | 格挡破坏 |
| `SKILL_CANCEL_THROW` | 61 | 可取消的投掷 |
| `SKILL_LEG_SUPLEX` | 62 | 空摔（Air Steiner） |
| `SKILL_TYPHOON` | 63 | 柔道家觉醒技 |
| `SKILL_DUMMY` | 64 | 未使用 |
| `SKILL_EFFICIENT_BURN` | 65 | 散打觉醒被动-高效燃烧 |
| `SKILL_GRAB_MASTERY` | 66 | 抓取精通 |
| `SKILL_NEN_FLOWER` | 67 | 念花 |
| `SKILL_LIGHTNING_DANCE` | 68 | 闪电舞 |
| `SKILL_ILLUSION_BOMB` | 69 | 幻影爆碎 |
| `SKILL_POWER_UP_ON_DASH` | 70 | 狂奔（Stampede） |
| `SKILL_STRONGEST_LOW_KICK` | 71 | 史上最强低踢 |
| `SKILL_NEN_SHIELD` | 72 | 漫天千炎花 |
| `SKILL_ARMOR_MASTERY_HEAVY_SP` | 73 | 重甲精通 |
| `SKILL_CRAZY_MOUNT` | 74 | 疯狂骑乘 |
| `SKILL_HIDDEN_STING` | 75 | 隐藏刺针 |
| `SKILL_VENOM_MINE` | 76 | 毒液地雷 |
| `SKILL_JUNK_SPIN` | 77 | 废铁旋转 |
| `SKILL_ENERGY_BALL_CHARGE` | 78 | 蓄力念弹 |
| `SKILL_NEN_MONSTER_WHITE_TIGER` | 79 | 念兽：白虎 |
| `SKILL_DASH_PUNCH` | 80 | 直拳突刺 |
| `SKILL_PUNCH_AFTER_RETURN` | 81 | 击打后转身 |
| `SKILL_RANDOM_KICK` | 82 | 百裂脚乱打 |
| `SKILL_RISING_UPPER` | 83 | 升龙拳 |
| `SKILL_DASH_AFTER_DASH` | 84 | 护身连击 |
| `SKILL_DASH_AFTER_DASH_EXTENSION` | 85 | 护身连击延伸（虎炮） |
| `SKILL_EARTH_BREAK` | 86 | 金刚碎 |
| `SKILL_HOLD_UP` | 87 | 举起控制 |
| `SKILL_WILD_CANNON_SPIKE` | 88 | 野性炮刺 |
| `SKILL_SUPLEX_CYCLONE` | 89 | 背摔旋风 |
| `SKILL_LIGHTNING_DRAGON` | 90 | 光冲怒涛 |
| `SKILL_MUSCLE_SHIFT` | 91 | 肌肉转移 |
| `SKILL_CANCEL_EARTH_BREAK` | 92 | 可取消的金刚碎 |
| `SKILL_CANCEL_DASH_PUNCH` | 93 | 可取消的崩拳（名字为直拳突刺） |
| `SKILL_CANCEL_SHOULDER_CHARGE` | 94 | 可取消的铁山靠 |
| `SKILL_CANCEL_PUNCH_AFTER_RETURN` | 95 | 可取消的击打后转身 |
| `SKILL_CANCEL_SUPLEX_CYCLONE` | 96 | 可取消的背摔旋风 |
| `SKILL_ARMOR_MASTERY_CLOTH_NM` | 97 | 布甲精通：念师 |
| `SKILL_CANCEL_NEN_GUARD` | 98 | 可取消的念气盾 |
| `SKILL_CANCEL_ROAR_STUN` | 99 | 可取消的狮子吼 |
| `SKILL_CANCEL_ENERGY_FIELD` | 100 | 可取消的气功掌 |
| `SKILL_CANCEL_ENCHANT_POISON` | 101 | 未使用 |
| `SKILL_CANCEL_VENOM_MINE` | 102 | 可取消的毒液地雷 |
| `SKILL_CANCEL_RANDOM_KICK` | 103 | 可取消的节拍驱动（Beat Drive） |
| `SKILL_BLOCK_BUSTER_EX` | 104 | 格挡破坏[强化] |
| `SKILL_DESTROY_EARTH_SKY_DROP` | 105 | 街霸觉醒技-天崩地坏 |
| `SKILL_GROUND_KICK` | 106 | 地面踢 |
| `SKILL_CANCEL_GROUND_KICK` | 107 | 可取消的地面踢 |
| `SKILL_FAST_DASH` | 108 | 瞬步 |
| `SKILL_SMART_THROW` | 109 | 帅气投掷（源码作业：郑镇洙） |
| `SKILL_AUTO_LOAD` | 110 | 自动装填 |
| `SKILL_SPIRAL_NEN_SHOOT` | 111 | 螺旋念气：出 |
| `SKILL_SPIRAL_NEN_SPIN` | 112 | 螺旋念气：周 |
| `SKILL_CANCEL_SPIRAL_NEN_SHOOT` | 113 | 可取消的螺旋念气：出 |
| `SKILL_NEN_POLE` | 114 | 念之极意 |
| `SKILL_TYPHOON_COUNTER_STRIKE` | 115 | 反击：柔道家觉醒被动 |
| `SKILL_1000HANDS_1000EYES` | 116 | 千手千眼：散打觉醒被动 |
| `SKILL_NEN_SPEAR_EX` | 117 | 念矛（特性） |
| `SKILL_CHARGE_SPEAR_EX` | 118 | 充能矛（特性） |
| `SKILL_GLUEY_FRUIT_EX` | 119 | 黏黏果实（特性） |
| `SKILL_SPIRAL_COLUMN_EX` | 120 | 螺旋环（特性）郑镇洙 |
| `SKILL_108_STAIRS_EX` | 121 | 108阶（特性） |
| `SKILL_HURRICANE_SPEAR` | 122 | 飓风矛（特性） |
| `SKILL_CRASH_ROPE` | 123 | 狂暴血沙（特性） |
| `SKILL_CHAIN_KICK_EX` | 124 | 连环腿（特性） |

## 自定义动画编号（格斗家系）CUSTOM_ANI_*（140 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `CUSTOM_ANI_CROUCH` | 0 | 蹲伏动作 |
| `CUSTOM_ANI_CRASH_LOW_KICK` | 1 | 骨碎击动作 |
| `CUSTOM_ANI_LIFT_UPPER` | 2 | 缪斯上勾动作 |
| `CUSTOM_ANI_DAMAGE_LOW_KICK` | 3 | 低踢动作 |
| `CUSTOM_ANI_TRY_SUPLEX` | 4 | 背摔尝试动作 |
| `CUSTOM_ANI_SUPLEX` | 5 | 背摔动作 |
| `CUSTOM_ANI_BACK_SUPLEX` | 6 | 背摔破坏动作 |
| `CUSTOM_ANI_MOUNT_TRY` | 7 | 骑乘尝试动作 |
| `CUSTOM_ANI_MOUNT` | 8 | 骑乘-压制到出拳前的动作 |
| `CUSTOM_ANI_MOUNT_PUNCH` | 9 | 骑乘-出拳 |
| `CUSTOM_ANI_NOT_USE` | 10 | 未使用 |
| `CUSTOM_ANI_STOMP` | 11 | 空中踩踏 |
| `CUSTOM_ANI_TRY_JUMP_SUPLEX` | 12 | 空摔尝试（Air Steiner） |
| `CUSTOM_ANI_JUMP_SUPLEX` | 13 | 空摔 |
| `CUSTOM_ANI_JUMP_SUPLEX_LARIAT` | 14 | 空摔旋转追加攻击 |
| `CUSTOM_ANI_CLOSE_PUNCH` | 15 | 寸拳 |
| `CUSTOM_ANI_GRAB_EXPLOSION` | 16 | 火药星 |
| `CUSTOM_ANI_SHOULDER_TACKLE` | 17 | 肩撞 |
| `CUSTOM_ANI_WHIRL_WIND_KICK` | 18 | 旋风腿 |
| `CUSTOM_ANI_BLOCK_BUSTER_READY` | 19 | 格挡破坏-准备（仅在强化投掷施放中触发） |
| `CUSTOM_ANI_BLOCK_BUSTER_JUMP` | 20 | 格挡破坏-跳跃（仅在强化投掷施放中触发） |
| `CUSTOM_ANI_BLOCK_BUSTER_SHOOT` | 21 | 格挡破坏-投掷（原注释误写“跳跃”） |
| `CUSTOM_ANI_BLOCK_BUSTER_NORMAL` | 22 | 格挡破坏-普通砖块投掷 |
| `CUSTOM_ANI_TRY_LEG_SUPLEX` | 23 | 空摔尝试（Air Steiner） |
| `CUSTOM_ANI_LEG_SUPLEX_THROW` | 24 | 空摔：投掷 |
| `CUSTOM_ANI_LEG_SUPLEX_KICK` | 25 | 下砸踢腿动作 |
| `CUSTOM_ANI_TYPHOON_GRAB` | 26 | 柔道家觉醒技：抓取 |
| `CUSTOM_ANI_TYPHOON_ATTACK1` | 27 | 柔道家觉醒技：第1击 |
| `CUSTOM_ANI_TYPHOON_ATTACK2` | 28 | 柔道家觉醒技：第2击 |
| `CUSTOM_ANI_TYPHOON_ATTACK3` | 29 | 柔道家觉醒技：第3击 |
| `CUSTOM_ANI_TYPHOON_KICKUP` | 30 | 柔道家觉醒技：上踢 |
| `CUSTOM_ANI_TYPHOON_JUMP` | 31 | 柔道家觉醒技：跳跃 |
| `CUSTOM_ANI_TYPHOON_LAST` | 32 | 柔道家觉醒技：最后一击 |
| `CUSTOM_ANI_TYPHOON_STAY` | 33 | 柔道家觉醒技：最后一击后待机 |
| `CUSTOM_ANI_CRAZY_MOUNT_START` | 34 | 疯狂骑乘 |
| `CUSTOM_ANI_CRAZY_MOUNT_PUNCH` | 35 | 疯狂骑乘普通攻击 |
| `CUSTOM_ANI_CRAZY_MOUNT_NOT_USE` | 36 | 未使用 |
| `CUSTOM_ANI_CRAZY_MOUNT_END` | 37 | 疯狂骑乘最后一击 |
| `CUSTOM_ANI_THROW_WEB` | 38 | 天罗地网 |
| `CUSTOM_ANI_HIDDEN_STING` | 39 | 隐藏刺针 |
| `CUSTOM_ANI_VENOM_MINE` | 40 | 毒液地雷 |
| `CUSTOM_ANI_FLAME_LEGS_CAST` | 41 | 散打觉醒技-火焰之脚（施放） |
| `CUSTOM_ANI_JUNK_SPIN_LOOP` | 42 | 废铁旋转 |
| `CUSTOM_ANI_JUNK_SPIN_FINISH` | 43 | 废铁旋转收尾（推断） |
| `CUSTOM_ANI_MOUNT_END` | 44 | 骑乘最后一击 |
| `CUSTOM_ANI_SHOULDER_CHARGE` | 45 | 铁山靠 |
| `CUSTOM_ANI_SINGLE_KICK` | 46 | 锤击踢 |
| `CUSTOM_ANI_NEN_FLOWER` | 47 | 念花 |
| `CUSTOM_ANI_TRY_THROW_ENEMY` | 48 | 擒抱尝试 |
| `CUSTOM_ANI_THROW_ENEMY_HOLD` | 49 | 擒抱抓握中 |
| `CUSTOM_ANI_THROW_ENEMY_THROW` | 50 | 擒抱投掷 |
| `CUSTOM_ANI_WHITE_TIGER_COMBO1` | 51 | 念兽：白虎第1击 |
| `CUSTOM_ANI_WHITE_TIGER_COMBO2` | 52 | 念兽：白虎第2击 |
| `CUSTOM_ANI_WHITE_TIGER_COMBO3` | 53 | 念兽：白虎第3击 |
| `CUSTOM_ANI_WHITE_TIGER_COMBO4` | 54 | 念兽：白虎第4击 |
| `CUSTOM_ANI_WHITE_TIGER_COMBO5` | 55 | 念兽：白虎第5击 |
| `CUSTOM_ANI_WHITE_TIGER_DASH_ATTACK` | 56 | 念兽：白虎冲刺攻击 |
| `CUSTOM_ANI_WHITE_TIGER_JUMP_ATTACK` | 57 | 念兽：白虎跳跃攻击 |
| `CUSTOM_ANI_DASH_PUNCH` | 58 | 直拳突刺 |
| `CUSTOM_ANI_PUNCH_AFTER_RETURN` | 59 | 击打后转身 |
| `CUSTOM_ANI_RANDOM_KICK1` | 60 | 节拍驱动第1击 |
| `CUSTOM_ANI_RANDOM_KICK2` | 61 | 节拍驱动第2击 |
| `CUSTOM_ANI_RANDOM_KICK3` | 62 | 节拍驱动第3击 |
| `CUSTOM_ANI_RANDOM_KICK_FINISH` | 63 | 节拍驱动最后一击 |
| `CUSTOM_ANI_RISING_UPPER_DASH` | 64 | 升龙拳：冲刺 |
| `CUSTOM_ANI_RISING_UPPER` | 65 | 升龙拳：上勾 |
| `CUSTOM_ANI_DASH_AFTER_DASH_COMBO1` | 66 | 护身连击：第1击 |
| `CUSTOM_ANI_DASH_AFTER_DASH_COMBO2` | 67 | 护身连击：第2击 |
| `CUSTOM_ANI_DASH_AFTER_DASH_COMBO3` | 68 | 护身连击：第3击（男格斗无此击） |
| `CUSTOM_ANI_DASH_AFTER_DASH_COMBO4` | 69 | 护身连击：第4击（男格斗无此击） |
| `CUSTOM_ANI_EARTH_BREAK` | 70 | 金刚碎 |
| `CUSTOM_ANI_HOLD_UP_TRY` | 71 | 举起控制：尝试 |
| `CUSTOM_ANI_HOLD_UP_HOLD` | 72 | 举起控制：抓住 |
| `CUSTOM_ANI_HOLD_UP_HIT` | 73 | 举起控制：殴打 |
| `CUSTOM_ANI_WILD_CANNON_SPIKE_CHARGE` | 74 | 野性炮刺：蓄力 |
| `CUSTOM_ANI_WILD_CANNON_SPIKE_FALL` | 75 | 野性炮刺：下落 |
| `CUSTOM_ANI_THROW_SAND` | 76 | 撒沙（Helter Skelter） |
| `CUSTOM_ANI_THROW_SAND_DOUBLE` | 77 | 撒沙（双重投掷版） |
| `CUSTOM_ANI_TRY_SUPLEX_CYCLONE` | 78 | 背摔旋风：尝试 |
| `CUSTOM_ANI_TURN_SUPLEX_CYCLONE` | 79 | 背摔旋风：抓住旋转 |
| `CUSTOM_ANI_WILD_CANNON_SPIKE_EXP` | 80 | 野性炮刺：最后一击 |
| `CUSTOM_ANI_FINISH_SUPLEX_CYCLONE` | 81 | 未使用 |
| `CUSTOM_ANI_LIGHTNING_DRAGON` | 82 | 光冲怒涛施放 |
| `CUSTOM_ANI_DESTROY_EARTH_SKY_DROP_START` | 83 | 街霸觉醒技-天崩地坏 起始 |
| `CUSTOM_ANI_DESTROY_EARTH_SKY_DROP_ON_SKY` | 84 | 天崩地坏：空中动作 |
| `CUSTOM_ANI_DESTROY_EARTH_SKY_DROP_FINISH` | 85 | 强化空摔第1次下砸 |
| `CUSTOM_ANI_TRY_LEG_SUPLEX_EX_SECOND` | 86 | 强化空摔第2次尝试跳跃 |
| `CUSTOM_ANI_LEG_SUPLEX_EX_2` | 87 | 强化空摔第2次下砸 |
| `CUSTOM_ANI_RISING_UPPER_EX_START` | 88 | 强化升龙拳起始 |
| `CUSTOM_ANI_RISING_UPPER_EX` | 89 | 强化升龙拳 |
| `CUSTOM_ANI_RISING_UPPER_EX_FINISH` | 90 | 强化升龙拳最后一击 |
| `CUSTOM_ANI_BLOCK_BUSTER_EX_TRY` | 91 | 强化格挡破坏起始 |
| `CUSTOM_ANI_BLOCK_BUSTER_EX_JUMP` | 92 | 强化格挡破坏跳跃 |
| `CUSTOM_ANI_BLOCK_BUSTER_EX_FINISH` | 93 | 强化格挡破坏最后一击 |
| `CUSTOM_ANI_SUPLEX_CYCLONE_JUMP_EX` | 94 | 强化背摔旋风：跳跃 |
| `CUSTOM_ANI_SUPLEX_CYCLONE_SPIN_EX` | 95 | 强化背摔旋风：旋转 |
| `CUSTOM_ANI_DASH_PUNCH_EX` | 96 | 强化崩拳 |
| `CUSTOM_ANI_STOMP_FINISH` | 97 | 空中踩踏最后一击 |
| `CUSTOM_ANI_GROUND_KICK_JUMP` | 98 | 地面踢-跳跃 |
| `CUSTOM_ANI_GROUND_KICK_ATTACK` | 99 | 地面踢-攻击 |
| `CUSTOM_ANI_GROUND_KICK_FINISH` | 100 | 地面踢-收尾 |
| `CUSTOM_ANI_FAST_DASH` | 101 | 瞬步 |
| `CUSTOM_ANI_CRASH_LOW_KICK_SECOND` | 102 | 骨碎击第二次攻击 |
| `CUSTOM_ANI_THROW_ENEMY_SIDEKICK` | 103 | 男格斗擒抱侧踢 |
| `CUSTOM_ANI_THROW_ENEMY_DOWNKICK` | 104 | 男格斗擒抱下砸踢 |
| `CUSTOM_ANI_THROW_GRAB_CANNON_ENEMY_SIDEKICK` | 105 | 男格斗擒抱抓取炮侧踢 |
| `CUSTOM_ANI_SUPLEX_FINAL_ATTACK` | 106 | 男格斗背摔抓取炮膝击 |
| `CUSTOM_ANI_SUPLEX_THROW_FINAL_ATTACK` | 107 | 男格斗背摔飞跃膝击 |
| `CUSTOM_ANI_DOUBLE_THROW_WEB` | 108 | 男格斗撒网（双重投掷） |
| `CUSTOM_ANI_LEG_SUPLEX_FIRST_KICK` | 109 | 男格斗空摔初始下砸动作 |
| `CUSTOM_ANI_JUMP_SUPLEX_HOLD_IMPRESSKICK` | 110 | 男格斗空摔-不可抓取目标-下砸踢 |
| `CUSTOM_ANI_LIGHTNING_DANCE_KICK` | 111 | 男格斗闪电舞踢击 |
| `CUSTOM_ANI_LIGHTNING_DANCE_LAST_LOW_KICK` | 112 | 男格斗闪电舞最后低踢 |
| `CUSTOM_ANI_GRAB_EXPLOSION_KICK` | 113 | 男格斗火药星-抓住踢击 |
| `CUSTOM_ANI_NEN_FLOWER_READY` | 114 | 念师觉醒-骑虎动作 |
| `CUSTOM_ANI_NEN_FLOWER_ATTACK` | 115 | 念师觉醒-虎攻击 |
| `CUSTOM_ANI_NEN_FLOWER_FINAL` | 116 | 念师觉醒-虎最后一击 |
| `CUSTOM_ANI_ENCHANT_POISON` | 117 | 毒装填发射 |
| `CUSTOM_ANI_SPIRALNEN_SHOOT_PREPARE` | 118 | 螺旋念气：出 发射准备 |
| `CUSTOM_ANI_SPIRALNEN_SHOOT` | 119 | 螺旋念气：出 发射 |
| `CUSTOM_ANI_BLOCK_BUSTER_DOUBLE` | 120 | 格挡破坏-双重投掷 |
| `CUSTOM_ANI_ENCHANT_POISON_DOUBLE` | 121 | 毒装填-双重投掷 |
| `CUSTOM_ANI_HIDDEN_STING_DOUBLE` | 122 | 装针-双重投掷 |
| `CUSTOM_ANI_DEFINITE_GRAB` | 123 | 必定抓住-特殊抓取动作 |
| `CUSTOM_ANI_NEN_SPEAR` | 124 | 念矛插刺（特性） |
| `CUSTOM_ANI_NEN_SPEAR_SUCCESS` | 125 | 念矛插刺成功（特性） |
| `CUSTOM_ANI_HURRICANE_SPEAR` | 126 | 男格斗特性技-飓风矛 |
| `CUSTOM_ANI_CHARGE_SPEAR_RECHARGE` | 127 | 充能矛（特性）蓄力 |
| `CUSTOM_ANI_CHARGE_SPEAR_RUSH` | 128 | 充能矛（特性）突进 |
| `CUSTOM_ANI_CHARGE_SPEAR_END` | 129 | 充能矛（特性）突进结束 |
| `CUSTOM_ANI_SPIRAL_COLUMN_EX` | 130 | 螺旋环（特性） |
| `CUSTOM_ANI_CRASH_ROPE` | 131 | 狂暴血沙（特性） |
| `CUSTOM_ANI_GLUEY_FRUIT` | 132 | 黏黏果实（特性） |
| `CUSTOM_ANI_CHAIN_KICK` | 133 | 连环腿（特性） |
| `CUSTOM_ANI_108_STAIRS_TRY_EX` | 134 | 108阶（特性）尝试 |
| `CUSTOM_ANI_108_STAIRS_KICK_EX` | 135 | 108阶（特性）踢击 |
| `CUSTOM_ANI_108_STAIRS_PUNCH_EX` | 136 | 108阶（特性）拳击 |
| `CUSTOM_ANI_108_STAIRS_BLOW_EX` | 137 | 108阶（特性）击飞 |
| `CUSTOM_ANI_108_STAIRS_THROW_EX` | 138 | 108阶（特性）投掷 |
| `CUSTOM_ANI_108_STAIRS_FINAL_EX` | 139 | 108阶（特性）收尾 |

## 攻击信息槽（格斗家系）CUSTOM_ATTACKINFO_*（84 个）

> `sq_SetAttackInfo` 之类的槽位号，与 `CUSTOM_ANI_*` 是两套独立编号。

| 常量 | 值 | 说明 |
|---|---|---|
| `CUSTOM_ATTACKINFO_CRASH_LOW_KICK` | 0 | 骨碎击 |
| `CUSTOM_ATTACKINFO_LIFT_UPPER` | 1 | 缪斯上勾 |
| `CUSTOM_ATTACKINFO_DAMAGE_LOW_KICK` | 2 | 低踢 |
| `CUSTOM_ATTACKINFO_TRY_GRAB` | 3 | 抓取尝试 |
| `CUSTOM_ATTACKINFO_SUPLEX` | 4 | 背摔的间接伤害 |
| `CUSTOM_ATTACKINFO_MOUNT` | 5 | 骑乘出拳 |
| `CUSTOM_ATTACKINFO_STOMP` | 6 | 空中踩踏 |
| `CUSTOM_ATTACKINFO_JUMP_SUPLEX` | 7 | 空摔（最初踢击） |
| `CUSTOM_ATTACKINFO_JUMP_SUPLEX_HEADING` | 8 | 空摔最后一记回旋踢 |
| `CUSTOM_ATTACKINFO_JUMP_SUPLEX_LARIAT` | 9 | 抓取炮空摔回旋踢（不可抓取目标） |
| `CUSTOM_ATTACKINFO_CLOSE_PUNCH` | 10 | 寸拳 |
| `CUSTOM_ATTACKINFO_SHOULDER_CHARGE` | 11 | 铁山靠 |
| `CUSTOM_ATTACKINFO_SINGLE_KICK` | 12 | 锤击踢 |
| `CUSTOM_ATTACKINFO_GRAB_EXPLOSION` | 13 | 火药星打击 |
| `CUSTOM_ATTACKINFO_SHOULDER_TACKLE` | 14 | 肩撞 |
| `CUSTOM_ATTACKINFO_GRAB_CANNON` | 15 | 抓取炮 |
| `CUSTOM_ATTACKINFO_WHIRL_WIND_KICK` | 16 | 旋风腿 |
| `CUSTOM_ATTACKINFO_JUNK_SPIN` | 17 | 针刺旋转（废铁旋转） |
| `CUSTOM_ATTACKINFO_LEG_SUPLEX_KICK` | 18 | 空摔：踢击 |
| `CUSTOM_ATTACKINFO_LIGHTNING_DANCE` | 19 | 闪电舞 |
| `CUSTOM_ATTACKINFO_STRONGEST_LOW_KICK` | 20 | 史上最强低踢 |
| `CUSTOM_ATTACKINFO_CRAZY_MOUNT` | 21 | 疯狂骑乘 |
| `CUSTOM_ATTACKINFO_THROW_WEB` | 22 | 天罗地网 |
| `CUSTOM_ATTACKINFO_HIDDEN_STING` | 23 | 隐藏刺针 |
| `CUSTOM_ATTACKINFO_DASH_PUNCH` | 24 | 直拳突刺 |
| `CUSTOM_ATTACKINFO_PUNCH_AFTER_RETURN` | 25 | 击打后转身 |
| `CUSTOM_ATTACKINFO_RANDOM_KICK_1` | 26 | 节拍驱动第1击 |
| `CUSTOM_ATTACKINFO_RANDOM_KICK_2` | 27 | 节拍驱动第2击 |
| `CUSTOM_ATTACKINFO_RANDOM_KICK_3` | 28 | 节拍驱动第3击 |
| `CUSTOM_ATTACKINFO_RANDOM_KICK_FINISH` | 29 | 节拍驱动最后一击 |
| `CUSTOM_ATTACKINFO_DUMMY_4` | 30 | 未被使用 |
| `CUSTOM_ATTACKINFO_RISING_UPPER` | 31 | 升龙拳：上勾 |
| `CUSTOM_ATTACKINFO_DASH_AFTER_DASH_COMBO1` | 32 | 护身连击：第1击 |
| `CUSTOM_ATTACKINFO_DASH_AFTER_DASH_COMBO2` | 33 | 护身连击：第2击 |
| `CUSTOM_ATTACKINFO_VENOM_MINE` | 34 | 毒液地雷攻击力 |
| `CUSTOM_ATTACKINFO_DUMMY_2` | 35 | 未被使用 |
| `CUSTOM_ATTACKINFO_HOLD_UP_TRY` | 36 | 举起控制：尝试 |
| `CUSTOM_ATTACKINFO_HOLD_UP_HIT` | 37 | 举起控制：殴打 |
| `CUSTOM_ATTACKINFO_WILD_CANNON_SPIKE_FALL` | 38 | 野性炮刺：空中下落时 |
| `CUSTOM_ATTACKINFO_WILD_CANNON_SPIKE_HIT` | 39 | 野性炮刺：落地造成伤害时 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_COMBO1` | 40 | 念兽：白虎第1击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_COMBO2` | 41 | 念兽：白虎第2击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_COMBO3` | 42 | 念兽：白虎第3击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_COMBO4` | 43 | 念兽：白虎第4击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_COMBO5` | 44 | 念兽：白虎第5击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_DASH_ATTACK` | 45 | 念兽：白虎冲刺攻击 |
| `CUSTOM_ATTACKINFO_WHITE_TIGER_JUMP_ATTACK` | 46 | 念兽：白虎跳跃攻击 |
| `CUSTOM_ATTACKINFO_SUPLEX_CYCLONE_CRASH` | 47 | 背摔旋风：抓住下砸 |
| `CUSTOM_ATTACKINFO_SUPLEX_CYCLONE_FINISH` | 48 | 背摔旋风：最后打击 |
| `CUSTOM_ATTACKINFO_LEG_SUPLEX_EX_SPIN` | 49 | 强化空摔旋转 |
| `CUSTOM_ATTACKINFO_DASH_PUNCH_EX` | 50 | 强化崩拳 |
| `CUSTOM_ATTACKINFO_BLOCK_BUSTER_FINISH_EX` | 51 | 强化格挡破坏最后一击 |
| `CUSTOM_ATTACKINFO_RISING_UPPER_START_EX` | 52 | 强化升龙拳：起始 |
| `CUSTOM_ATTACKINFO_RISING_UPPER_EX` | 53 | 强化升龙拳：上勾 |
| `CUSTOM_ATTACKINFO_RISING_UPPER_FINISH_EX` | 54 | 强化升龙拳：收尾 |
| `CUSTOM_ATTACKINFO_SUPLEX_CYCLONE_EX` | 55 | 强化背摔旋风 |
| `CUSTOM_ATTACKINFO_SUPLEX_CYCLONE_SPIN_EX` | 56 | 强化背摔旋风：旋转 |
| `CUSTOM_ATTACKINFO_STOMP_FINISH` | 57 | 空中踩踏最后一击 |
| `CUSTOM_ATTACKINFO_GROUND_KICK` | 58 | 地面踢 |
| `CUSTOM_ATTACKINFO_LIGHTNING_DRAGON` | 59 | 光冲怒涛 |
| `CUSTOM_ATTACKINFO_CRASH_LOW_KICK_SECOND` | 60 | 骨碎击第二次攻击 |
| `CUSTOM_ATTACKINFO_THROW_ENEMY_UPKICK` | 61 | 男格斗擒抱上踢 |
| `CUSTOM_ATTACKINFO_THROW_ENEMY_SIDEKICK` | 62 | 男格斗擒抱侧踢 |
| `CUSTOM_ATTACKINFO_THROW_ENEMY_DOWNKICK` | 63 | 男格斗擒抱下砸踢 |
| `CUSTOM_ATTACKINFO_TRY_GRAB_THROW_ENEMY` | 64 | 擒抱（原注释拼作 로풀링） |
| `CUSTOM_ATTACKINFO_THROW_WEB_DOUBLE` | 65 | 撒网（双重投掷时） |
| `CUSTOM_ATTACKINFO_LIGHTNING_LOW_KICK` | 66 | 闪电低踢（原注释误抄撒网行） |
| `CUSTOM_ATTACKINFO_SUPLEX_GRABCANNON` | 67 | 背摔+抓取炮 |
| `CUSTOM_ATTACKINFO_NEN_FLOWER` | 68 | 念师觉醒 |
| `CUSTOM_ATTACKINFO_TYPHOON` | 69 | 柔道家觉醒技 |
| `CUSTOM_ATTACKINFO_TYPHOON_LAST` | 70 | 柔道家觉醒技最后一击 |
| `CUSTOM_ATTACKINFO_SPIRAL_NEN_SHOOT` | 71 | 螺旋念气：出 |
| `CUSTOM_ATTACKINFO_NEN_SPEAR` | 72 | 念矛（特性） |
| `CUSTOM_ATTACKINFO_CHARGE_SPEAR` | 73 | 充能矛（特性） |
| `CUSTOM_ATTACKINFO_HURRICANE_SPEAR` | 74 | 飓风矛（特性） |
| `CUSTOM_ATTACKINFO_CRASH_ROPE` | 75 | 狂暴血沙（特性） |
| `CUSTOM_ATTACKINFO_CHAIN_KICK1` | 76 | 连环腿第1击（特性） |
| `CUSTOM_ATTACKINFO_CHAIN_KICK2` | 77 | 连环腿第2击（特性） |
| `CUSTOM_ATTACKINFO_CHAIN_KICK3` | 78 | 连环腿第3击（特性） |
| `CUSTOM_ATTACKINFO_108_STAIRS_KICK_EX` | 79 | 108阶踢击（特性） |
| `CUSTOM_ATTACKINFO_108_STAIRS_PUNCH_EX` | 80 | 108阶拳击（特性） |
| `CUSTOM_ATTACKINFO_108_STAIRS_BLOW_1_EX` | 81 | 108阶击飞1（特性） |
| `CUSTOM_ATTACKINFO_108_STAIRS_BLOW_2_EX` | 82 | 108阶击飞2（特性） |
| `CUSTOM_ATTACKINFO_108_STAIRS_BLOW_3_EX` | 83 | 108阶击飞3（特性） |

## 武器子类型（格斗家）WEAPON_SUBTYPE_*（7 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `WEAPON_SUBTYPE_KNUCKLE` | 0 | 拳套（Knuckle） |
| `WEAPON_SUBTYPE_GAUNTLET` | 1 | 护手（Gauntlet） |
| `WEAPON_SUBTYPE_CLAW` | 2 | 爪（Claw） |
| `WEAPON_SUBTYPE_BOXING_GLOVE` | 3 | 拳击手套 |
| `WEAPON_SUBTYPE_DUMMY` | 4 | 未知（UNKNOWN） |
| `WEAPON_SUBTYPE_TONFA` | 5 | 双拐（Tonfa） |
| `WEAPON_SUBTYPE_MAX` | 6 | 武器子类型最大值（推断） |

## 附加体循环音效 SOUND_ID_*（17 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `SOUND_ID_STATIC` | 0 | 停留地图期间持续播放 |
| `SOUND_ID_MOVE` | 1 | 脚步声 |
| `SOUND_ID_ACTIVESTATUS_POISON` | 2 | 中毒时 |
| `SOUND_ID_ACTIVESTATUS_BURN` | 3 | 燃烧时 |
| `SOUND_ID_ACTIVESTATUS_LIGHTNING` | 4 | 感电时 |
| `SOUND_ID_AURA_SHIELD` | 5 | 附加体：光环护盾 |
| `SOUND_ID_MAGICAL_TEMPO_UP` | 6 | 附加体：表演时间（Showtime） |
| `SOUND_ID_DOT_AREA` | 7 | 附加体：震动波 |
| `SOUND_ID_DOT_AREA_DAMAGE` | 8 | 附加体：震动波受击 |
| `SOUND_ID_DIVINE_LIGHT` | 9 | 附加体：神圣之光 |
| `SOUND_ID_SHADOW_BOXER` | 10 | 附加体：影子拳手 |
| `SOUND_ID_GUARD` | 11 | 格挡状态时 |
| `SOUND_ID_CHAKRA_OF_PASSION` | 12 | 附加体：热情查克拉 |
| `SOUND_ID_CHAKRA_OF_CALMNESS` | 13 | 附加体：冷静查克拉 |
| `SOUND_ID_WAVE_MARK` | 14 | 附加体：波动印 |
| `SOUND_ID_KEIGA` | 15 | 附加体：残影凯加 |
| `SOUND_ID_END` | 16 | 音效ID结束哨兵（推断） |

## 状态优先级 STATE_PRIORITY_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `STATE_PRIORITY_AUTO` | 0 | 按时间/条件自动触发 |
| `STATE_PRIORITY_USER` | 1 | 玩家指令触发（技能、攻击等） |
| `STATE_PRIORITY_HALF_FORCE` | 2 | 非主动、强制度低于完全强制（翻面等） |
| `STATE_PRIORITY_FORCE` | 3 | 强制执行的（倒地、受击、死亡、控制等） |
| `STATE_PRIORITY_IGNORE_FORCE` | 4 | 无视强制变更（背摔抓取对手等） |

## 角色状态机（男格斗/圣职者系）STATE_*（39 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `STATE_VIRTUAL_ATTACK` | 19 | 普攻用的虚拟STATE（攻击技能等） |
| `STATE_ANTIAIR_UPPER` | 20 | 上勾拳 |
| `STATE_DUCKING` | 21 | 下潜（Ducking） |
| `STATE_SWAY` | 22 | 摇摆（Sway） |
| `STATE_GIANT_SWING` | 23 | 大回旋击 |
| `STATE_REPEATED_SMASH` | 24 | 乱击 |
| `STATE_SMASHER` | 25 | 粉碎者（Smasher） |
| `STATE_QUAKE_AREA` | 26 | 落凤坠 |
| `STATE_WILL_DRIVER` | 27 | 意志驱动（Will Driver） |
| `STATE_DUCKING_SKILL` | 28 | 下潜状态下的各技能扩展 |
| `STATE_LUCKY_STRAIGHT` | 29 | 幸运直拳（Lucky Straight） |
| `STATE_SECOND_UPPER` | 30 | 二段上勾（Second Upper） |
| `STATE_HOLY_COUNTER` | 31 | 神圣反击（Holy Counter） |
| `STATE_GORGEOUS_COMBINATION` | 32 | 华丽连击（Gorgeous） |
| `STATE_CHOPPING_HAMMER` | 33 | 劈砍锤（Chopping Hammer） |
| `STATE_HURRICANE_OF_JUDGEMENT` | 34 | 审判旋风 |
| `STATE_HOME_RUN` | 35 | 全垒打（Home Run） |
| `STATE_BLADE_OF_PURE_WHITE` | 36 | 纯白之刃 |
| `STATE_HURRICANE_ROLL` | 37 | 飓风翻滚（Hurricane Roll） |
| `STATE_THROW_WEAPON` | 38 | 巨旋风 |
| `STATE_DEFLECT_WALL` | 39 | 偏转之墙（Deflect Wall） |
| `STATE_SPEAR_OF_VICTORY` | 40 | 胜利之枪 |
| `STATE_HAMMER_OF_CONTRITION` | 41 | 忏悔之锤 |
| `STATE_HEAVENLY_COMBINATION` | 42 | 天堂连击（Heavenly） |
| `STATE_DIVINE_CRUSH` | 43 | 神圣碾压（Divine Crush） |
| `STATE_SIDEWIND` | 44 | 侧旋（Sidewind） |
| `STATE_MACHINE_GUN_JAB` | 45 | 机枪刺拳 |
| `STATE_THROW_TALISMAN` | 46 | 成佛（投掷符咒） |
| `STATE_APOCALYPSE` | 47 | 天启（Apocalypse） |
| `STATE_GALE_SMASH` | 48 | 疾风打 |
| `STATE_ATOMIC_SMASH` | 49 | 无双击 |
| `STATE_BIG_BANG_PUNCH` | 50 | 大爆炸拳 |
| `STATE_BLUE_DRAGON` | 51 | 苍龙击 |
| `STATE_HEAL_WIND` | 52 | 治愈之风（Heal Wind） |
| `STATE_CUTTING_DARKNESS` | 53 | 斩暗 |
| `STATE_MACHINE_GUN_JAB_EX` | 54 | 强化机枪刺拳 |
| `STATE_HEAVENLY_COMBINATION_EX` | 55 | 天堂连击[强化] |
| `STATE_REPEATED_SMASH_EX` | 56 | 强化乱击 |
| `STATE_DEFLECT_WALL_EX` | 57 | 偏转之墙[强化] |

## 技能 ID（男格斗/圣职者系）SKILL_*（122 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `SKILL_ANTIAIR_UPPER` | 1 | 空斩打 |
| `SKILL_DUCKING` | 2 | 下潜冲刺 |
| `SKILL_SWAY` | 3 | 摇摆 |
| `SKILL_HURRICANE_ROLL` | 4 | 飓风翻滚 |
| `SKILL_GIANT_SWING` | 5 | 大回旋击 |
| `SKILL_CANCEL_ANTIAIR_UPPER` | 6 | 可取消的空斩打 |
| `SKILL_STRIKING` | 7 | 打击（Striking） |
| `SKILL_SMASHER` | 8 | 粉碎者 |
| `SKILL_CANCEL_SMASHER` | 9 | 可取消的粉碎者 |
| `SKILL_CHANGE_HP_TO_MP` | 10 | 痛苦之悦（HP 换 MP） |
| `SKILL_QUAKE_AREA` | 11 | 落凤坠 |
| `SKILL_CANCEL_QUAKE_AREA` | 12 | 可取消的落凤坠 |
| `SKILL_WILL_DRIVER` | 13 | 意志驱动 |
| `SKILL_TECHNICAL_MASTERY` | 14 | 技术精通 |
| `SKILL_BATTLE_AURA_MASTERY` | 15 | 战斗光环精通 |
| `SKILL_CORKSCREW_MASTERY` | 16 | 螺旋精通 |
| `SKILL_COMBINATION_MASTERY` | 17 | 连击精通 |
| `SKILL_HARD_PUNCH_MASTERY` | 18 | 硬拳精通 |
| `SKILL_HP_MAX_UP_PERSONAL` | 19 | 天上旋律（HP 上限提升·自身） |
| `SKILL_EMBLEM_OF_SAFEGUARD` | 20 | 保护徽记 |
| `SKILL_FOUNTAIN_OF_LIFE` | 21 | 生命之源 |
| `SKILL_DIVINE_LIGHT` | 22 | 神圣之光 |
| `SKILL_REVENGE_OF_LIGHT` | 23 | 光之复仇 |
| `SKILL_HP_MAX_UP_PARTY` | 24 | 天上和声（HP 上限提升·队伍） |
| `SKILL_SACRIFICE_OF_SOUL` | 25 | 灵魂牺牲 |
| `SKILL_HEAL_WIND` | 26 | 治愈之风 |
| `SKILL_DEFLECT_WALL` | 27 | 偏转之墙 |
| `SKILL_FLASH_GLOBE` | 28 | 闪光手套 |
| `SKILL_EXTENDED_PUNCH` | 29 | 拳气释放 |
| `SKILL_HOLY_COUNTER` | 30 | 神圣反击 |
| `SKILL_GORGEOUS_COMBINATION` | 31 | 华丽连击 |
| `SKILL_CANCEL_GORGEOUS_COMBINATION` | 32 | 可取消的华丽连击 |
| `SKILL_CHOPPING_HAMMER` | 33 | 劈砍锤 |
| `SKILL_ARMOR_MASTERY_PLATE_CS` | 34 | 圣骑士板甲精通 |
| `SKILL_SHADOW_BOXER` | 35 | 影子拳手 |
| `SKILL_DOUBLE_SHADOW_BOXER` | 36 | 双重影子拳手 |
| `SKILL_HURRICANE_OF_JUDGEMENT` | 37 | 审判旋风 |
| `SKILL_ENTERING_NIRVANA` | 38 | 成佛（进入涅槃） |
| `SKILL_OPPRESSION_TALISMAN` | 39 | 压制符（特效） |
| `SKILL_THUNDERBOLT_TALISMAN` | 40 | 落雷符（特效） |
| `SKILL_HOME_RUN` | 41 | 那天空的星（Home Run） |
| `SKILL_QUICK_PARRY` | 42 | 快速格挡 |
| `SKILL_BLADE_OF_PURE_WHITE` | 43 | 纯白之刃 |
| `SKILL_CANCEL_BLADE_OF_PURE_WHITE` | 44 | 可取消的纯白之刃 |
| `SKILL_GLORIOUS_BLESS` | 45 | 荣耀祝福 |
| `SKILL_CANCEL_HURRICANE_ROLL` | 46 | 可取消的飓风翻滚 |
| `SKILL_CHAKRA_OF_PASSION` | 47 | 热情查克拉 |
| `SKILL_CHAKRA_OF_CALMNESS` | 48 | 冷静查克拉 |
| `SKILL_REPEATED_SMASH` | 49 | 乱击 |
| `SKILL_THROW_WEAPON` | 50 | 巨旋风 |
| `SKILL_SLOW_HEAL` | 51 | 缓慢治愈 |
| `SKILL_CURE` | 52 | 治愈（Cure） |
| `SKILL_BLESS` | 53 | 智慧祝福 |
| `SKILL_GRACE_OF_GOD` | 54 | 神的恩宠 |
| `SKILL_FAST_HEAL` | 55 | 快速治愈 |
| `SKILL_DUCKING_STRAIGHT` | 56 | 下潜直拳 |
| `SKILL_DUCKING_BODYBLOW` | 57 | 下潜身体打击 |
| `SKILL_DUCKING_UPPER` | 58 | 下潜上勾 |
| `SKILL_CANCEL_DUCKING` | 59 | 可取消的下潜 |
| `SKILL_CANCEL_SWAY` | 60 | 可取消的摇摆 |
| `SKILL_LUCKY_STRAIGHT` | 61 | 幸运直拳 |
| `SKILL_CANCEL_LUCKY_STRAIGHT` | 62 | 可取消的幸运直拳 |
| `SKILL_SECOND_UPPER` | 63 | 二段上勾 |
| `SKILL_GRASP_HAND_OF_ANGER` | 64 | 愤怒之握 |
| `SKILL_CANCEL_GRASP_HAND_OF_ANGER` | 65 | 可取消的愤怒之握 |
| `SKILL_CHARGE_WEAPON` | 66 | 潜龙 |
| `SKILL_FORCE_OF_EXORCISM` | 67 | 退魔之气 |
| `SKILL_ARMOR_MASTERY_CLOTH_EC` | 68 | 布甲精通：退魔师（推断） |
| `SKILL_HYUN_MOO` | 69 | 地之式神-玄武 |
| `SKILL_BAEK_HO` | 70 | 空之式神-白虎 |
| `SKILL_CANCEL_REPEATED_SMASH` | 71 | 可取消的乱击 |
| `SKILL_CANCEL_HOME_RUN` | 72 | 可取消的全垒打 |
| `SKILL_SPEAR_OF_VICTORY` | 73 | 胜利之枪 |
| `SKILL_HAMMER_OF_CONTRITION` | 74 | 忏悔之锤 |
| `SKILL_HEAVENLY_COMBINATION` | 75 | 天堂连击 |
| `SKILL_DIVINE_CRUSH` | 76 | 神圣碾压 |
| `SKILL_SIDEWIND` | 77 | 侧旋 |
| `SKILL_MACHINE_GUN_JAB` | 78 | 机枪刺拳 |
| `SKILL_CANCEL_SIDEWIND` | 79 | 可取消的侧旋 |
| `SKILL_CANCEL_MACHINE_GUN_JAB` | 80 | 可取消的机枪刺拳 |
| `SKILL_JUDGEMENT` | 81 | 正义审判 |
| `SKILL_BIG_WEAPON_MASTERY` | 82 | 巨兵精通（生成） |
| `SKILL_BATTLE_AXE_MASTERY` | 83 | 战斧精通 |
| `SKILL_APOCALYPSE` | 84 | 天启 |
| `SKILL_GALE_SMASH` | 85 | 疾风打 |
| `SKILL_AURA_OF_FAITH` | 86 | 信念光环 |
| `SKILL_DRYOUT` | 87 | 枯竭（Dry Out） |
| `SKILL_ATOMIC_SMASH` | 88 | 无双击 |
| `SKILL_RADIATE_FIGHTING_AURA` | 89 | 斗气发散 |
| `SKILL_BIG_BANG_PUNCH` | 90 | 大爆炸拳 |
| `SKILL_ARMOR_MASTERY_LIGHT_IF` | 91 | 轻甲精通：散打 |
| `SKILL_ARMOR_MASTERY_PLATE_EC` | 92 | 板甲精通：退魔师 |
| `SKILL_BLUE_DRAGON` | 93 | 苍龙击 |
| `SKILL_CANCEL_ENTERING_NIRVANA` | 94 | 可取消的成佛 |
| `SKILL_CANCEL_GALE_SMASH` | 95 | 可取消的疾风打 |
| `SKILL_ARMOR_MASTERY_HEAVY_EC` | 96 | 重甲精通：退魔师 |
| `SKILL_GRACE_OF_COURAGE` | 97 | 勇气恩宠 |
| `SKILL_GRACE_OF_PROTECTION` | 98 | 守护恩宠 |
| `SKILL_RISING_AREA` | 99 | 升天阵 |
| `SKILL_CUTTING_DARKNESS` | 100 | 斩暗 |
| `SKILL_SHIKIGAMI` | 101 | 式神之群 |
| `SKILL_CANCEL_RISING_AREA` | 102 | 可取消的升天阵 |
| `SKILL_MACHINE_GUN_JAB_EX` | 103 | 强化机枪刺拳 |
| `SKILL_HEAVENLY_COMBINATION_EX` | 104 | 天堂连击[强化]（原注拼错） |
| `SKILL_REPEATED_SMASH_EX` | 105 | 强化乱击 |
| `SKILL_VERMILIONBIRD_TALISMAN` | 106 | 朱雀符 |
| `SKILL_CROSS_CRASH` | 107 | 十字斩（开发名：灼热十字） |
| `SKILL_FLASH_GLOBE_EX` | 108 | 闪光手套[强化] |
| `SKILL_DEFLECT_WALL_EX` | 109 | 偏转之墙[强化] |
| `SKILL_HYUN_MOO_EX` | 110 | 玄武[强化] |
| `SKILL_GROUND_CRASH` | 111 | 地面粉碎（开发名：黄牛突破） |
| `SKILL_CANCEL_GROUND_CRASH` | 112 | 可取消的地面粉碎 |
| `SKILL_SLOW_HEAL_EX` | 140 | 缓慢治愈被动 |
| `SKILL_LUCKY_STRAIGHT_EX` | 141 | 幸运直拳被动 |
| `SKILL_QUAKE_AREA_EX` | 142 | 落凤坠被动 |
| `SKILL_GRASP_HAND_OF_ANGER_EX` | 143 | 愤怒之握 |
| `SKILL_SPEAR_OF_VICTORY_EX` | 144 | 胜利之枪被动 |
| `SKILL_REVENGE_OF_LIGHT_EX` | 145 | 光之复仇被动 |
| `SKILL_DUCKING_STRAIGHT_EX` | 146 | 下潜直拳被动 |
| `SKILL_WILL_DRIVER_EX` | 147 | 意志驱动被动 |
| `SKILL_OPPRESSION_TALISMAN_EX` | 148 | 压制符被动 |
| `SKILL_THROW_WEAPON_EX` | 149 | 巨旋风被动 |

## 自定义动画编号（圣职者系）CUSTOM_ANI_*（79 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `CUSTOM_ANI_JUMP_PUNCH` | 0 | 跳跃拳（无巨兵时的跳跃攻击） |
| `CUSTOM_ANI_ANTIAIR_UPPER` | 1 | 上勾拳 |
| `CUSTOM_ANI_DUCKING` | 2 | 下潜 |
| `CUSTOM_ANI_SWAY` | 3 | 摇摆 |
| `CUSTOM_ANI_GIANT_SWING_READY` | 4 | 大回旋击：准备 |
| `CUSTOM_ANI_GIANT_SWING` | 5 | 大回旋击：旋转 |
| `CUSTOM_ANI_GIANT_SWING_FINAL` | 6 | 大回旋击：最后一击 |
| `CUSTOM_ANI_SMASHER_TRY_GRAB` | 7 | 粉碎者：抓取尝试 |
| `CUSTOM_ANI_SMASHER_SUCCESS_GRAB` | 8 | 粉碎者：抓取成功 |
| `CUSTOM_ANI_SMASHER_DASH` | 9 | 粉碎者：冲刺后投掷 |
| `CUSTOM_ANI_DUCKING_BODYBLOW` | 10 | 身体打击 |
| `CUSTOM_ANI_QUAKE_AREA` | 11 | 落凤坠 |
| `CUSTOM_ANI_WILL_DRIVER` | 12 | 意志驱动 |
| `CUSTOM_ANI_WILL_DRIVER_SECOND` | 13 | 意志驱动：已插在地上的状态 |
| `CUSTOM_ANI_LUCKY_STRAIGHT` | 14 | 幸运直拳 |
| `CUSTOM_ANI_DUCKING_STRAIGHT` | 15 | 下潜直拳 |
| `CUSTOM_ANI_SECOND_UPPER` | 16 | 二段上勾 |
| `CUSTOM_ANI_DUCKING_UPPER` | 17 | 下潜上勾 |
| `CUSTOM_ANI_HOLY_COUNTER_PRAY` | 18 | 神圣反击：祈祷 |
| `CUSTOM_ANI_HOLY_COUNTER_BODYBLOW` | 19 | 神圣反击：身体打击 |
| `CUSTOM_ANI_GORGEOUS_COMBINATION` | 20 | 华丽连击 |
| `CUSTOM_ANI_CHOPPING_HAMMER` | 21 | 劈砍锤 |
| `CUSTOM_ANI_HURRICANE_OF_JUDGEMENT` | 22 | 审判旋风 |
| `CUSTOM_ANI_HURRICANE_OF_JUDGEMENT2` | 23 | 审判旋风第2击 |
| `CUSTOM_ANI_HOME_RUN_GRAB` | 24 | 全垒打：抓取尝试 |
| `CUSTOM_ANI_HOME_RUN_CHARGE` | 25 | 全垒打：抓取与蓄力 |
| `CUSTOM_ANI_HOME_RUN_SMASH` | 26 | 全垒打：挥棒 |
| `CUSTOM_ANI_BLADE_OF_PURE_WHITE` | 27 | 纯白之刃 |
| `CUSTOM_ANI_HURRICANE_ROLL_HOOK` | 28 | 飓风翻滚：勾拳 |
| `CUSTOM_ANI_HURRICANE_ROLL_UPPER` | 29 | 飓风翻滚：上勾 |
| `CUSTOM_ANI_REPEATED_SMASH_START` | 30 | 乱击：第一击 |
| `CUSTOM_ANI_REPEATED_SMASH` | 31 | 乱击：连打 |
| `CUSTOM_ANI_REPEATED_SMASH_FINAL` | 32 | 乱击：最后一击 |
| `CUSTOM_ANI_THROW_WEAPON_READY` | 33 | 巨旋风：准备 |
| `CUSTOM_ANI_THROW_WEAPON_SWING` | 34 | 巨旋风：旋转（满蓄力多转1圈） |
| `CUSTOM_ANI_THROW_WEAPON_THROW` | 35 | 巨旋风：投掷（未满蓄力则准备→投掷） |
| `CUSTOM_ANI_DEFLECT_WALL` | 36 | 偏转之墙 |
| `CUSTOM_ANI_SPEAR_OF_VICTORY_READY` | 37 | 胜利之枪：准备与蓄力 |
| `CUSTOM_ANI_SPEAR_OF_VICTORY_THROW` | 38 | 胜利之枪：投掷 |
| `CUSTOM_ANI_HAMMER_OF_CONTRITION` | 39 | 忏悔之锤 |
| `CUSTOM_ANI_HEAVENLY_COMBINATION` | 40 | 天堂连击 |
| `CUSTOM_ANI_DIVINE_CRUSH` | 41 | 神圣碾压 |
| `CUSTOM_ANI_INFIGHTER_ATTACK12` | 42 | 散打普攻1、2击 |
| `CUSTOM_ANI_INFIGHTER_ATTACK3` | 43 | 散打普攻3击 |
| `CUSTOM_ANI_INFIGHTER_ATTACK4` | 44 | 散打普攻4击 |
| `CUSTOM_ANI_INFIGHTER_ATTACK5` | 45 | 散打普攻5击 |
| `CUSTOM_ANI_EXORCIST_ATTACK1` | 46 | 退魔师普攻1击 |
| `CUSTOM_ANI_EXORCIST_ATTACK2` | 47 | 退魔师普攻2击 |
| `CUSTOM_ANI_EXORCIST_ATTACK3` | 48 | 退魔师普攻3击 |
| `CUSTOM_ANI_SIDEWIND` | 49 | 侧旋基本 |
| `CUSTOM_ANI_SIDEWIND_SECOND` | 50 | 侧旋追加攻击 |
| `CUSTOM_ANI_MACHINE_GUN_JAB` | 51 | 机枪刺拳：连打 |
| `CUSTOM_ANI_MACHINE_GUN_JAB_FINISH` | 52 | 机枪刺拳：收尾 |
| `CUSTOM_ANI_MACHINE_GUN_JAB_APPEND` | 53 | 机枪刺拳：追加攻击 |
| `CUSTOM_ANI_THROW_TALISMAN1` | 54 | 成佛：投掷1 |
| `CUSTOM_ANI_THROW_TALISMAN2` | 55 | 成佛：投掷2 |
| `CUSTOM_ANI_APOCALYPSE` | 56 | 天启 |
| `CUSTOM_ANI_GALE_SMASH1` | 57 | 疾风打：肩撞 |
| `CUSTOM_ANI_GALE_SMASH2` | 58 | 疾风打：挥击 |
| `CUSTOM_ANI_ATOMIC_SMASH` | 59 | 无双击 |
| `CUSTOM_ANI_BIG_BANG_PUNCH_READY` | 60 | 大爆炸拳：准备 |
| `CUSTOM_ANI_BIG_BANG_PUNCH1` | 61 | 大爆炸拳第1击 |
| `CUSTOM_ANI_BIG_BANG_PUNCH2` | 62 | 大爆炸拳第2击 |
| `CUSTOM_ANI_BIG_BANG_PUNCH3` | 63 | 大爆炸拳第3击 |
| `CUSTOM_ANI_BIG_BANG_PUNCH4` | 64 | 大爆炸拳第4击 |
| `CUSTOM_ANI_HEAL_WIND_CAST` | 65 | 治愈之风：吟唱 |
| `CUSTOM_ANI_HEAL_WIND_BLAST` | 66 | 治愈之风：发动 |
| `CUSTOM_ANI_BLUE_DRAGON1` | 67 | 苍龙击：生成 |
| `CUSTOM_ANI_BLUE_DRAGON2` | 68 | 苍龙击：投掷准备 |
| `CUSTOM_ANI_BLUE_DRAGON3` | 69 | 苍龙击：投掷 |
| `CUSTOM_ANI_CUTTING_DARKNESS_CHARGE` | 70 | 斩暗：蓄力 |
| `CUSTOM_ANI_CUTTING_DARKNESS_SMASH` | 71 | 斩暗：挥击 |
| `CUSTOM_ANI_CUTTING_DARKNESS_FULL_SMASH` | 72 | 斩暗：满蓄力挥击 |
| `CUSTOM_ANI_MACHINE_GUN_JAB_EX_LEFT` | 73 | 强化机枪刺拳连打·左 |
| `CUSTOM_ANI_MACHINE_GUN_JAB_EX_RIGHT` | 74 | 强化机枪刺拳连打·右 |
| `CUSTOM_ANI_MACHINE_GUN_JAB_EX_FINISH` | 75 | 强化机枪刺拳收尾 |
| `CUSTOM_ANI_HEAVENLY_COMBINATION_EX` | 76 | 天堂连击[强化] |
| `CUSTOM_ANI_REPEATED_SMASH_EX_FINISH` | 77 | 强化乱击击飞 |
| `CUSTOM_ANI_GROUND_CRASH` | 78 | 地面粉碎 |

## 攻击信息槽（圣职者系）CUSTOM_ATTACKINFO_*（70 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `CUSTOM_ATTACKINFO_JUMP_PUNCH` | 0 | 跳跃拳（无巨兵时的跳跃攻击） |
| `CUSTOM_ATTACKINFO_DASH_ATTACK_SMASH` | 1 | 冲刺攻击第2击 |
| `CUSTOM_ATTACKINFO_ANTIAIR_UPPER` | 2 | 空斩打 |
| `CUSTOM_ATTACKINFO_GIANT_SWING` | 3 | 大回旋击：旋转 |
| `CUSTOM_ATTACKINFO_GIANT_SWING_FINAL` | 4 | 大回旋击：最后一击 |
| `CUSTOM_ATTACKINFO_SMASHER_TRY` | 5 | 粉碎者抓取尝试 |
| `CUSTOM_ATTACKINFO_SMASHER_DASH` | 6 | 粉碎者冲刺 |
| `CUSTOM_ATTACKINFO_SMASHER_THROW` | 7 | 粉碎者投掷 |
| `CUSTOM_ATTACKINFO_QUAKE_AREA` | 8 | 落凤坠 |
| `CUSTOM_ATTACKINFO_LUCKY_STRAIGHT` | 9 | 幸运直拳 |
| `CUSTOM_ATTACKINFO_SECOND_UPPER` | 10 | 二段上勾 |
| `CUSTOM_ATTACKINFO_DUCKING_STRAIGHT` | 11 | 下潜直拳 |
| `CUSTOM_ATTACKINFO_DUCKING_BODYBLOW` | 12 | 下潜身体打击 |
| `CUSTOM_ATTACKINFO_DUCKING_UPPER` | 13 | 下潜上勾 |
| `CUSTOM_ATTACKINFO_HOLY_COUNTER` | 14 | 神圣反击 |
| `CUSTOM_ATTACKINFO_GORGEOUS_COMBINATION1` | 15 | 华丽连击：刺拳 |
| `CUSTOM_ATTACKINFO_GORGEOUS_COMBINATION2` | 16 | 华丽连击：直拳 |
| `CUSTOM_ATTACKINFO_GORGEOUS_COMBINATION3` | 17 | 华丽连击：勾拳 |
| `CUSTOM_ATTACKINFO_CHOPPING_HAMMER` | 18 | 劈砍锤 |
| `CUSTOM_ATTACKINFO_HURRICANE_OF_JUDGEMENT` | 19 | 审判旋风 |
| `CUSTOM_ATTACKINFO_HOME_RUN_GRAB` | 20 | 全垒打：抓取尝试 |
| `CUSTOM_ATTACKINFO_HOME_RUN_HIT` | 21 | 全垒打：抓取成功第1击 |
| `CUSTOM_ATTACKINFO_HOME_RUN_SMASH` | 22 | 全垒打：挥棒 |
| `CUSTOM_ATTACKINFO_BLADE_OF_PURE_WHITE` | 23 | 纯白之刃 |
| `CUSTOM_ATTACKINFO_HURRICANE_ROLL_HOOK` | 24 | 飓风翻滚：勾拳 |
| `CUSTOM_ATTACKINFO_HURRICANE_ROLL_UPPER` | 25 | 飓风翻滚：上勾 |
| `CUSTOM_ATTACKINFO_REPEATED_SMASH` | 26 | 乱击：连打 |
| `CUSTOM_ATTACKINFO_REPEATED_SMASH_FINAL` | 27 | 乱击：最后一击 |
| `CUSTOM_ATTACKINFO_THROW_WEAPON` | 28 | 巨旋风：近距打击 |
| `CUSTOM_ATTACKINFO_HAMMER_OF_CONTRITION` | 29 | 忏悔之锤 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION1` | 30 | 天堂连击：第1击 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION2` | 31 | 天堂连击：第2击 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION3` | 32 | 天堂连击：第3击 |
| `CUSTOM_ATTACKINFO_DIVINE_CRUSH` | 33 | 神圣碾压 |
| `CUSTOM_ATTACKINFO_INFIGHTER_ATTACK1` | 34 | 散打普攻1击 |
| `CUSTOM_ATTACKINFO_INFIGHTER_ATTACK2` | 35 | 散打普攻2击 |
| `CUSTOM_ATTACKINFO_INFIGHTER_ATTACK3` | 36 | 散打普攻3击 |
| `CUSTOM_ATTACKINFO_INFIGHTER_ATTACK4` | 37 | 散打普攻4击 |
| `CUSTOM_ATTACKINFO_INFIGHTER_ATTACK5` | 38 | 散打普攻5击 |
| `CUSTOM_ATTACKINFO_EXORCIST_ATTACK1` | 39 | 退魔师普攻1击 |
| `CUSTOM_ATTACKINFO_EXORCIST_ATTACK2` | 40 | 退魔师普攻2击 |
| `CUSTOM_ATTACKINFO_EXORCIST_ATTACK3` | 41 | 退魔师普攻3击 |
| `CUSTOM_ATTACKINFO_SIDEWIND` | 42 | 侧旋 |
| `CUSTOM_ATTACKINFO_SIDEWIND_SECOND` | 43 | 侧旋追加攻击 |
| `CUSTOM_ATTACKINFO_MACHINE_GUN_JAB` | 44 | 机枪刺拳：连打 |
| `CUSTOM_ATTACKINFO_MACHINE_GUN_JAB_FINISH` | 45 | 机枪刺拳：收尾 |
| `CUSTOM_ATTACKINFO_MACHINE_GUN_JAB_APPEND` | 46 | 机枪刺拳：追加攻击 |
| `CUSTOM_ATTACKINFO_THROW_TALISMAN1` | 47 | 成佛：投掷1 |
| `CUSTOM_ATTACKINFO_THROW_TALISMAN2` | 48 | 成佛：投掷2 |
| `CUSTOM_ATTACKINFO_GALE_SMASH1` | 49 | 疾风打：肩撞 |
| `CUSTOM_ATTACKINFO_GALE_SMASH2` | 50 | 疾风打：挥击 |
| `CUSTOM_ATTACKINFO_ATOMIC_SMASH_SWING` | 51 | 无双击：挥击 |
| `CUSTOM_ATTACKINFO_ATOMIC_SMASH_SMASH` | 52 | 无双击：下砸 |
| `CUSTOM_ATTACKINFO_BIG_BANG_PUNCH_READY` | 53 | 大爆炸拳：准备 |
| `CUSTOM_ATTACKINFO_BIG_BANG_PUNCH1` | 54 | 大爆炸拳第1击 |
| `CUSTOM_ATTACKINFO_BIG_BANG_PUNCH2` | 55 | 大爆炸拳第2击 |
| `CUSTOM_ATTACKINFO_BIG_BANG_PUNCH3` | 56 | 大爆炸拳第3击 |
| `CUSTOM_ATTACKINFO_BIG_BANG_PUNCH4` | 57 | 大爆炸拳第4击 |
| `CUSTOM_ATTACKINFO_BLUE_DRAGON` | 58 | 苍龙击 |
| `CUSTOM_ATTACKINFO_CUTTING_DARKNESS` | 59 | 斩暗 |
| `CUSTOM_ATTACKINFO_MACHINE_GUN_JAB_EX` | 60 | 强化机枪刺拳：连打 |
| `CUSTOM_ATTACKINFO_MACHINE_GUN_JAB_EX_FINISH` | 61 | 强化机枪刺拳：收尾 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION_EX2` | 62 | 天堂连击：第2击 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION_EX3` | 63 | 天堂连击：第3击 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION_EX4` | 64 | 天堂连击：第4击 |
| `CUSTOM_ATTACKINFO_HEAVENLY_COMBINATION_EX5` | 65 | 天堂连击：第5击 |
| `CUSTOM_ATTACKINFO_REPEATED_SMASH_EX_LIFT` | 66 | 强化乱击挑空 |
| `CUSTOM_ATTACKINFO_REPEATED_SMASH_EX_FINAL` | 67 | 强化乱击击飞 |
| `CUSTOM_ATTACKINFO_GROUND_CRASH1` | 68 | 地面粉碎第1击 |
| `CUSTOM_ATTACKINFO_GROUND_CRASH2` | 69 | 地面粉碎第2击 |

## 攻击方向 ATTACK_DIRECTION_*（4 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ATTACK_DIRECTION_UP` | 0 | 上挑 |
| `ATTACK_DIRECTION_HORIZON` | 1 | 水平击 |
| `ATTACK_DIRECTION_DOWN` | 2 | 下劈 |
| `ATTACK_DIRECTION_MAX` | 3 | 攻击方向最大值（推断） |

## 攻击类型 ATTACKTYPE_*（4 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ATTACKTYPE_PHYSICAL` | 0 | 独立物理攻击 |
| `ATTACKTYPE_MAGICAL` | 1 | 独立魔法攻击 |
| `ATTACKTYPE_ABSOLUTE` | 2 | 无视防御攻击 |
| `ATTACKTYPE_MAX` | 3 | 攻击类型最大值（推断） |

## 攻击目标 ATTACKTARGET_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ATTACKTARGET_OWN` | 0 | 自身 |
| `ATTACKTARGET_FRIEND` | 1 | 友方 |
| `ATTACKTARGET_ENEMY` | 2 | 敌方（自身与友方之外） |

## 伤害反应 DAMAGEACT_*（4 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `DAMAGEACT_NONE` | 0 | 无反应 |
| `DAMAGEACT_DAMAGE` | 1 | 受击动作 |
| `DAMAGEACT_DOWN` | 2 | 倒地 |
| `DAMAGEACT_DAMAGE_EXCEPT_HUMAN` | 3 | 基本受击，人型护甲无反应 |

## 击退类型 KNOCK_BACK_TYPE_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `KNOCK_BACK_TYPE_NORMAL` | 0 | 普通 |
| `KNOCK_BACK_TYPE_KNOCK_BACK` | 1 | 大幅后退（击退） |
| `KNOCK_BACK_TYPE_SHORT_KNOCK_BACK_` | 2 | 小幅后退（击退） |
| `KNOCK_BACK_TYPE_PIXEL_WITHOUT_DAMAGE_TIME` | 3 | 指定时间内后退固定像素，硬直解除即停 |
| `KNOCK_BACK_TYPE_NOT_BACK` | -1 | 不后退（-1） |

## 受击方向 HIT_DIRECTION_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `HIT_DIRECTION_AUTO` | 0 | 自动判定 |
| `HIT_DIRECTION_FRONT` | 1 | 向前 |
| `HIT_DIRECTION_BACK` | 2 | 向后 |
| `HIT_DIRECTION_OUTER` | 3 | 向外 |
| `HIT_DIRECTION_INNER` | 4 | 向内 |

## 武器子类型（圣职者）WEAPON_SUBTYPE_*（6 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `WEAPON_SUBTYPE_CROSS` | 0 | 十字架 |
| `WEAPON_SUBTYPE_ROSARY` | 1 | 念珠 |
| `WEAPON_SUBTYPE_TOTEM` | 2 | 图腾 |
| `WEAPON_SUBTYPE_SCYTHE` | 3 | 镰刀 |
| `WEAPON_SUBTYPE_BATTLE_AXE` | 4 | 战斧 |
| `WEAPON_SUBTYPE_MAX` | 5 | 武器子类型最大值（推断） |

## 成长类型 GROW_TYPE_*（第一次定义）（6 个）

> 本族在源文件末尾（1104 行附近）又定义了一次，见「成长类型（重复定义）」一节。

| 常量 | 值 | 说明 |
|---|---|---|
| `GROW_TYPE_PRIEST` | 0 | 神父（Priest） |
| `GROW_TYPE_CRUSADER` | 1 | 圣骑士（Crusader） |
| `GROW_TYPE_INFIGHTER` | 2 | 散打（Infighter） |
| `GROW_TYPE_EXORCIST` | 3 | 退魔师（Exorcist） |
| `GROW_TYPE_AVENGER` | 4 | 复仇者（Avenger） |
| `GROW_TYPE_PRIEST_G` | 5 | 神父G（女圣职） |

## 拳气延伸动作 EXTENDED_PUNCH_MOTION_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `EXTENDED_PUNCH_MOTION_DASH_ATTACK` | 0 | 冲刺攻击 |
| `EXTENDED_PUNCH_MOTION_SECOND_UPPER` | 1 | 二段上勾 |
| `EXTENDED_PUNCH_MOTION_MAX` | 2 | 扩展拳动作最大值（推断） |

## 普攻类型 BASE_ATTACK_TYPE_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `BASE_ATTACK_TYPE_DEFAULT` | 0 | 基本 |
| `BASE_ATTACK_TYPE_INFIGHTER` | 1 | 散打拳头 |
| `BASE_ATTACK_TYPE_EXORCIST` | 2 | 退魔师巨兵 |

## 战斗光环动作 BATTLE_AURA_MOTION_*（8 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `BATTLE_AURA_MOTION_ATTACK_12` | 0 | 普攻1、2（刺拳） |
| `BATTLE_AURA_MOTION_ATTACK_3` | 1 | 普攻3（直拳） |
| `BATTLE_AURA_MOTION_ATTACK_4` | 2 | 普攻4（上勾） |
| `BATTLE_AURA_MOTION_ATTACK_5` | 3 | 普攻5（下砸） |
| `BATTLE_AURA_MOTION_GORGEOUS_COMBINATION` | 4 | 华丽连击 |
| `BATTLE_AURA_MOTION_SIDEWIND` | 5 | 侧旋 |
| `BATTLE_AURA_MOTION_SIDEWIND_SECOND` | 6 | 侧旋追加攻击 |
| `BATTLE_AURA_MOTION_MAX` | 7 | 战斗光环动作最大值（推断） |

## 状态变更类型 CHANGE_STATUS_TYPE_*（98 个）

> `sq_SetChangeStatus` 的槽位。源文件里另有一条拼错的 `CAHNGE_STATUS_TYPE_EQUIPMENT_ALL_STAT`（见本表末尾）。

| 常量 | 值 | 说明 |
|---|---|---|
| `CHANGE_STATUS_TYPE_PHYSICAL_ATTACK` | 0 | 物理攻击 |
| `CHANGE_STATUS_TYPE_MAGICAL_ATTACK` | 1 | 魔法攻击 |
| `CHANGE_STATUS_TYPE_MAGICAL_DEFENSE` | 2 | 魔法防御力 |
| `CHANGE_STATUS_TYPE_PHYSICAL_DEFENSE` | 3 | 物理防御力 |
| `CHANGE_STATUS_TYPE_EQUIPMENT_PHYSICAL_ATTACK` | 4 | 装备伤害 |
| `CHANGE_STATUS_TYPE_EQUIPMENT_PHYSICAL_DEFENSE` | 5 | 装备物理防御 |
| `CHANGE_STATUS_TYPE_PHYSICAL_ATTACK_BONUS` | 6 | 物理攻击加成 |
| `CHANGE_STATUS_TYPE_MAGICAL_ATTACK_BONUS` | 7 | 魔法攻击加成 |
| `CHANGE_STATUS_TYPE_JUMP_POWER` | 8 | 跳跃力 |
| `CHANGE_STATUS_TYPE_JUMP_SPEED_RATE` | 9 | 跳跃速度 |
| `CHANGE_STATUS_TYPE_ATTACK_SPEED` | 10 | 攻击速度 |
| `CHANGE_STATUS_TYPE_MOVE_SPEED` | 11 | 移动速度 |
| `CHANGE_STATUS_TYPE_CAST_SPEED` | 12 | 施放速度 |
| `CHANGE_STATUS_TYPE_HP_MAX` | 13 | HP 上限 |
| `CHANGE_STATUS_TYPE_HP_REGEN_RATE` | 14 | HP 回复速度 |
| `CHANGE_STATUS_TYPE_PHYSICAL_CRITICAL_HIT_RATE` | 15 | 物理暴击率 |
| `CHANGE_STATUS_TYPE_MAGICAL_CRITICAL_HIT_RATE` | 16 | 魔法暴击率 |
| `CHANGE_STATUS_TYPE_PHYSICAL_BACK_ATTACK_CRITICAL` | 17 | 背击暴击率 |
| `CHANGE_STATUS_TYPE_MAGICAL_BACK_ATTACK_CRITICAL` | 18 | 魔法背击暴击率（原注释与物理同文） |
| `CHANGE_STATUS_TYPE_CRITICAL_TOLERANCE_RATE` | 19 | 暴击抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_FIRE` | 20 | 火属性抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_WATER` | 21 | 水属性抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_DARK` | 22 | 暗属性抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_LIGHT` | 23 | 光属性抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_ALL` | 24 | 全属性抗性 |
| `CHANGE_STATUS_TYPE_ELEMENT_TOLERANCE_ZERO` | 25 | 属性抗性归零 |
| `CHANGE_STATUS_TYPE_ACTIVESTATUS_TOLERANCE_ALL` | 26 | 全状态抗性 |
| `CHANGE_STATUS_TYPE_ACTIVEPROPERTY_STUCK` | 27 | 硬直（闪避） |
| `CHANGE_STATUS_TYPE_BACK_ATTACK_STUCK_TOLERANCE` | 28 | 背击硬直抗性（自己受击时，%） |
| `CHANGE_STATUS_TYPE_MP_REGEN_RATE` | 29 | MP 回复速度 |
| `CHANGE_STATUS_TYPE_EXTRA_SPEED_RATE` | 30 | 命中时硬直 |
| `CHANGE_STATUS_TYPE_EQUIPMENT_MAGICAL_ATTACK` | 31 | 装备魔法攻击 |
| `CHANGE_STATUS_TYPE_EQUIPMENT_MAGICAL_DEFENSE` | 32 | 装备魔法防御 |
| `CHANGE_STATUS_TYPE_STUCK` | 33 | 硬直（自己攻击命中时） |
| `CHANGE_STATUS_TYPE_HIT_RECOVERY` | 34 | 受击恢复 |
| `CHANGE_STATUS_TYPE_MELEE_HIT_DELAY` | 35 | 近战命中延迟 |
| `CAHNGE_STATUS_TYPE_EQUIPMENT_ALL_STAT` | 36 | 提升装备全部属性时使用 |
| `CHANGE_STATUS_TYPE_CUSTOM` | 37 | 自定义状态（推断） |
| `CHANGE_STATUS_TYPE_EXP_DOUBLE` | 38 | 经验值2倍 |
| `CHANGE_STATUS_TYPE_EVIL_UP` | 39 | 抗魔力提升 |
| `CHANGE_STATUS_TYPE_EVIL_DOWN` | 40 | 抗魔力降低（原注释带“92”） |
| `CHANGE_STATUS_TYPE_RIGIDITY` | 41 | 硬直度 |
| `CHANGE_STATUS_TYPE_ELEMENT_ATTACK_FIRE` | 42 | 火属性强化 |
| `CHANGE_STATUS_TYPE_ELEMENT_ATTACK_WATER` | 43 | 水属性强化 |
| `CHANGE_STATUS_TYPE_ELEMENT_ATTACK_DARK` | 44 | 暗属性强化 |
| `CHANGE_STATUS_TYPE_ELEMENT_ATTACK_LIGHT` | 45 | 光属性强化 |
| `CHANGE_STATUS_TYPE_ELEMENT_ATTACK_ALL` | 46 | 全属性强化 |
| `CHANGE_STATUS_TYPE_DISEASE` | 47 | 疾病 |
| `CHANGE_STATUS_TYPE_MP_MAX` | 48 | MP 上限 |
| `CHANGE_STATUS_TYPE_COOLTIME_DECLINE` | 49 | 技能冷却时间 |
| `CHANGE_STATUS_TYPE_PHYSICAL_CRITICAL_DAMAGE_RATE` | 50 | 物理暴击伤害增加率 |
| `CHANGE_STATUS_TYPE_MAGICAL_CRITICAL_DAMAGE_RATE` | 51 | 魔法暴击伤害增加率 |
| `CHANGE_STATUS_TYPE_BLOODWAR_GROW_ABILITY` | 52 | 血斗之塔（血之塔）成长 |
| `CHANGE_STATUS_TYPE_ADDITIONAL_PHYSICAL_GENUINE_ATTACK` | 53 | 独立伤害物理攻击力变化 |
| `CHANGE_STATUS_TYPE_ADDITIONAL_MAGICAL_GENUINE_ATTACK` | 54 | 独立伤害魔法攻击力变化 |
| `CHANGE_STATUS_TYPE_SUMMON_SKILL_POWER_BONUS_RATE` | 55 | 法师召唤兽技能攻击力增加 |
| `CHANGE_STATUS_TYPE_ANTIEVIL` | 56 | 实际抗魔力数值调整 |
| `CHANGE_STATUS_TYPE_PHYSICAL_ABSOLUTE_DAMAGE` | 57 | 物理绝对伤害/无视物防伤害 |
| `CHANGE_STATUS_GHOST_TRAIN_NO_BREATH_TIME` | 58 | 幽灵列车窒息时间变更 |
| `CHANGE_STATUS_CHARACTER_LINK` | 59 | 角色链接 |
| `CHANGE_STATUS_GOLD_INCREASE` | 60 | 金币增加（推断） |
| `CHANGE_STATUS_TYPE_MAX` | 61 | 状态类型最大值（推断） |
| `OBJECTTYPE_OBJECT` | 0 | 最顶层对象 |
| `OBJECTTYPE_COLLISION` | 1 | 碰撞对象（OBJECT 子类） |
| `OBJECTTYPE_ACTIVE` | 17 | 主动对象（COLLISION 子类） |
| `OBJECTTYPE_CHARACTER` | 273 | 角色对象（ACTIVE 子类） |
| `OBJECTTYPE_MONSTER` | 529 | 怪物对象（ACTIVE 子类） |
| `OBJECTTYPE_RIDABLEOBJECT` | 4625 | 坐骑相关对象（MONSTER 子类） |
| `OBJECTTYPE_PASSIVE` | 33 | 被动对象（COLLISION 子类） |
| `OBJECTTYPE_ITEM` | 289 | 物品对象（PASSIVE 子类） |
| `OBJECTTYPE_TRAP` | 545 | 陷阱对象（PASSIVE 子类） |
| `OBJECTTYPE_BREAKABLE` | 1057 | 可破坏对象（兼宝箱） |
| `OBJECTTYPE_PET` | 65 | 神兽（COLLISION 子类） |
| `OBJECTTYPE_CREATURE` | 129 | 生物（COLLISION 子类） |
| `OBJECTTYPE_DRAWONLY` | 2 | 仅绘制对象（OBJECT 子类） |
| `OBJECTTYPE_VIRTUALCHARACTER` | 18 | 大厅用虚拟角色（DRAWONLY 子类） |
| `OBJECTTYPE_NPC` | 34 | 大厅 NPC（DRAWONLY 子类） |
| `OBJECTTYPE_DONKEY` | 66 | 大厅个人商店（DRAWONLY 子类） |
| `OBJECTTYPE_VIRTUALCREATURE` | 130 | 大厅用虚拟生物（DRAWONLY 子类） |
| `OBJECTTYPE_DISJOINTSHOP` | 258 | 大厅分解机商店（DRAWONLY 子类） |
| `OBJECTTYPE_VIRTUALMONSTER` | 514 | 大厅用虚拟怪物（DRAWONLY 子类） |
| `OBJECTTYPE_NONE_DELETE` | 1026 | 删除时不被删的对象 |
| `OBJECTTYPE_DEFINE_END` | 61440 | 对象类型定义结束（推断） |
| `CONVERT_TABLE_TYPE_DAMAGE` | 0 | 伤害 |
| `CONVERT_TABLE_TYPE_DEFENSE` | 1 | 防御力 |
| `CONVERT_TABLE_TYPE_HP` | 2 | HP 上限 |
| `CONVERT_TABLE_TYPE_PHYSICAL_ATTACK` | 3 | 力量 |
| `CONVERT_TABLE_TYPE_PHYSICAL_DEFENSE` | 4 | 体力 |
| `CONVERT_TABLE_TYPE_MAGICAL_ATTACK` | 5 | 智力 |
| `CONVERT_TABLE_TYPE_MAGICAL_DEFENSE` | 6 | 精神 |
| `CONVERT_TABLE_TYPE_PHYSICAL_ABSOLUTE_DAMAGE` | 7 | 物理绝对伤害 |
| `CONVERT_TABLE_TYPE_PHYSICAL_DAMAGE_REDUCE` | 8 | 物理伤害修正 |
| `CONVERT_TABLE_TYPE_MAGICAL_ABSOLUTE_DAMAGE` | 9 | 魔法绝对伤害 |
| `CONVERT_TABLE_TYPE_MAGICAL_DAMAGE_REDUCE` | 10 | 魔法伤害修正 |
| `CONVERT_TABLE_TYPE_ACTIVESTATUS_DAMAGE_REDUCE` | 11 | 异常状态伤害修正 |
| `CONVERT_TABLE_TYPE_MP` | 12 | MP 上限 |
| `CONVERT_TABLE_TYPE_SKILL_POWER` | 13 | 技能独立伤害 |
| `CONVERT_TABLE_TYPE_MAX` | 14 | 换算表类型最大值（推断） |

## 装备类型 ENUM_EQUIPMENTTYPE_*（43 个）

> 编号不连续：0~9 是时装槽，10~21 是普通装备，22~25 是生物/神器。末尾几条是区间标记而不是独立槽位。

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_EQUIPMENTTYPE_AVATAR_HEADGEAR` | 0 | 帽子时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_HAIR` | 1 | 头部时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_FACE` | 2 | 脸部时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_JACKET` | 3 | 上衣时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_PANTS` | 4 | 下装时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_SHOES` | 5 | 鞋子时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_BREAST` | 6 | 胸部时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_WAIST` | 7 | 腰部时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_SKIN` | 8 | 肤色时装 |
| `ENUM_EQUIPMENTTYPE_AVATAR_AURORA` | 9 | 极光时装 |
| `ENUM_EQUIPMENTTYPE_WEAPON` | 10 | 武器 |
| `ENUM_EQUIPMENTTYPE_TITLE` | 11 | 称号 |
| `ENUM_EQUIPMENTTYPE_JACKET` | 12 | 上衣 |
| `ENUM_EQUIPMENTTYPE_SHOULDER` | 13 | 护肩 |
| `ENUM_EQUIPMENTTYPE_PANTS` | 14 | 下装 |
| `ENUM_EQUIPMENTTYPE_SHOES` | 15 | 鞋子 |
| `ENUM_EQUIPMENTTYPE_WAIST` | 16 | 腰带 |
| `ENUM_EQUIPMENTTYPE_AMULET` | 17 | 项链 |
| `ENUM_EQUIPMENTTYPE_WRIST` | 18 | 手镯 |
| `ENUM_EQUIPMENTTYPE_RING` | 19 | 戒指 |
| `ENUM_EQUIPMENTTYPE_SUPPORT` | 20 | 辅助装备 |
| `ENUM_EQUIPMENTTYPE_MAGIC_STONE` | 21 | 魔法石 |
| `ENUM_EQUIPMENTTYPE_MAX` | 22 | 装备类型最大值（推断） |
| `ENUM_EQUIPMENTTYPE_AVATAR_START` | 0 | 时装起始 |
| `ENUM_EQUIPMENTTYPE_AVATAR_END` | 8 | 时装结束 |
| `ENUM_EQUIPMENTTYPE_AVATAR_SELL_END` | 8 | 商城售卖时装结束 |
| `ENUM_EQUIPMENTTYPE_AVATAR_MAX` | 9 | 时装数量 |
| `ENUM_EQUIPMENTTYPE_ITEM_START` | 10 | （非时装的）物品起始 |
| `ENUM_EQUIPMENTTYPE_VISIBLE_END` | 11 | 外观变更装备结束 |
| `ENUM_EQUIPMENTTYPE_CREATURE` | 22 | 生物（Creature） |
| `ENUM_EQUIPMENTTYPE_ARTIFACT_RED` | 23 | 神器第一槽 |
| `ENUM_EQUIPMENTTYPE_ARTIFACT_BLUE` | 24 | 神器第二槽 |
| `ENUM_EQUIPMENTTYPE_ARTIFACT_GREEN` | 25 | 神器第三槽 |
| `ENUM_EQUIPMENTTYPE_ARTIFACT_END` | 26 | 神器结束（推断） |
| `ENUM_EQUIPMENTTYPE_CREATURE_END` | 25 | 生物结束（推断） |
| `ENUM_EQUIPMENTTYPE_CREATURE_MAX` | 24 | 生物最大值（推断） |
| `ENUM_EQUIPMENTTYPE_ARTIFACT` | 0 | 神器代表索引 |
| `ENUM_EQUIPMENTTYPE_TOTAL_MAX` | 24 | 装备类型总数最大值（推断） |
| `ENUM_EQUIPMENTTYPE_VISIBLE_MAX` | 13 | 外观变更装备数量 |
| `ENUM_EQUIPMENTTYPE_ARMOR_START` | 12 | 防具起始（推断） |
| `ENUM_EQUIPMENTTYPE_ARMOR_END` | 21 | 防具结束（推断） |
| `ENUM_EQUIPMENTTYPE_ARMOR_NUM` | 10 | 防具数量（推断） |
| `ENUM_EQUIPMENTTYPE_EXPAND_EQUIPSLOT_REVISE` | 10 | 普通装备槽与扩展槽之间的修正值 |

## 技能 ID（通用/基础精通）SKILL_*（38 个）

> 与角色技能共用同一张 `SKILL_*` 表，编号 169~220 是通用技能与特性。

| 常量 | 值 | 说明 |
|---|---|---|
| `SKILL_BACK_STEP` | 169 | 后撤步 |
| `SKILL_CANCEL_BACK_STEP` | 170 | 可取消的后撤步 |
| `SKILL_CANCEL_THROW_ITEM` | 171 | 可取消的道具投掷 |
| `SKILL_ARMOR_MASTERY_LIGHT` | 172 | 轻甲精通 |
| `SKILL_ARMOR_MASTERY_HEAVY` | 173 | 重甲精通 |
| `SKILL_BASIC_ATTACK_UP` | 174 | 普攻强化 |
| `SKILL_JUMP_POWER_UP` | 175 | 跳跃（跳跃力提升） |
| `SKILL_MAGICAL_ATTACK_UP` | 176 | 古代记忆（魔法攻击提升） |
| `SKILL_THROW_MASTERY` | 177 | 投掷精通 |
| `SKILL_PHYSICAL_BACK_ATTACK_CRITICAL` | 178 | 物理背击 |
| `SKILL_DISJOINT_ITEM` | 179 | 道具分解 |
| `SKILL_SUPER_ARMOR_ON_CAST` | 180 | 不屈意志（施放时霸体） |
| `SKILL_COMPOUND_CRAFT` | 181 | 组合：手工艺 |
| `SKILL_COMPOUND_WEAVING` | 182 | 组合：纺织 |
| `SKILL_COMPOUND_MACHINE` | 183 | 组合：机械 |
| `SKILL_COMPOUND_CHEMISTRY` | 184 | 组合：化学 |
| `SKILL_ARMOR_MASTERY_LEATHER` | 185 | 皮甲精通 |
| `SKILL_PHYSICAL_CRITICAL_HIT_UP` | 186 | 物理暴击 |
| `SKILL_ARMOR_MASTERY_CLOTH` | 187 | 布甲精通 |
| `SKILL_MAGICAL_CRITICAL_HIT_UP` | 188 | 魔法暴击 |
| `SKILL_MAGICAL_BACK_ATTACK_CRITICAL` | 189 | 魔法背击 |
| `SKILL_QUICK_STANDING` | 190 | 快速起身 |
| `SKILL_BASIC_HP_MAX_UP` | 195 | 公平决斗场专用技-生命熟练 |
| `SKILL_ARMOR_MASTERY_PLATE` | 196 | 板甲精通 |
| `SKILL_GUILD_STATUS_UP` | 200 | 公会技能 |
| `SKILL_FEATURE_STAT_PHYSICAL_ATTACK_UP` | 210 | 力量特性 |
| `SKILL_FEATURE_STAT_PHYSICAL_DEFENCE_UP` | 211 | 体力特性 |
| `SKILL_FEATURE_STAT_MAGICAL_ATTACK_UP` | 212 | 智力特性 |
| `SKILL_FEATURE_STAT_MAGICAL_DEFENCE_UP` | 213 | 精神特性 |
| `SKILL_FEATURE_STAT_STUCK_UP` | 214 | 命中率特性 |
| `SKILL_FEATURE_STAT_ACTIVEPROPERTY_STUCK_UP` | 215 | 闪避率特性 |
| `SKILL_FEATURE_STAT_HP_REGEN_RATE_UP` | 216 | HP 回复特性 |
| `SKILL_FEATURE_STAT_MP_REGEN_RATE_UP` | 217 | MP 回复特性 |
| `SKILL_FEATURE_STAT_ELEMENT_ATTACK_ALL_UP` | 218 | 全属性强化 |
| `SKILL_FEATURE_STAT_ELEMENT_TOLERANCE_ALL_UP` | 219 | 全属性抗性 |
| `SKILL_MAX` | 220 | 技能最大值（推断） |
| `SKILL_FEATURE_STAT_START` | 210 | 属性特性起始（推断） |
| `SKILL_FEATURE_STAT_MAX` | 10 | 属性特性数量（10） |

## 异常状态 ACTIVESTATUS_*（19 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ACTIVESTATUS_SLOW` | 0 | 减速 |
| `ACTIVESTATUS_FREEZE` | 1 | 冰冻 |
| `ACTIVESTATUS_POISON` | 2 | 中毒 |
| `ACTIVESTATUS_STUN` | 3 | 眩晕 |
| `ACTIVESTATUS_CURSE` | 4 | 诅咒 |
| `ACTIVESTATUS_BLIND` | 5 | 致盲 |
| `ACTIVESTATUS_LIGHTNING` | 6 | 感电 |
| `ACTIVESTATUS_STONE` | 7 | 石化 |
| `ACTIVESTATUS_SLEEP` | 8 | 睡眠 |
| `ACTIVESTATUS_BURN` | 9 | 灼烧 |
| `ACTIVESTATUS_WEAPON_BREAK` | 10 | 武器破坏 |
| `ACTIVESTATUS_BLEEDING` | 11 | 出血 |
| `ACTIVESTATUS_HASTE` | 12 | 加速（Haste） |
| `ACTIVESTATUS_BLESS` | 13 | 祝福（Bless） |
| `ACTIVESTATUS_ELEMENT` | 14 | 属性赋予（Element） |
| `ACTIVESTATUS_CONFUSE` | 15 | 混乱 |
| `ACTIVESTATUS_HOLD` | 16 | 定身（Hold） |
| `ACTIVESTATUS_ARMOR_BREAK` | 17 | 防具破坏 |
| `ACTIVESTATUS_MAX` | 18 | 异常状态最大值（推断） |

## 成长类型 GROW_TYPE_*（重复定义）（5 个）

> 与前面 886 行那一段同名同值，只少了 `GROW_TYPE_PRIEST_G`；Squirrel 里后者覆盖前者，值没变。

| 常量 | 值 | 说明 |
|---|---|---|
| `GROW_TYPE_PRIEST` | 0 | 神父（重复定义，值同 886） |
| `GROW_TYPE_CRUSADER` | 1 | 圣骑士（重复定义） |
| `GROW_TYPE_INFIGHTER` | 2 | 散打（重复定义） |
| `GROW_TYPE_EXORCIST` | 3 | 退魔师（重复定义） |
| `GROW_TYPE_AVENGER` | 4 | 复仇者（重复定义） |

## 职业 ENUM_CHARACTERJOB_*（12 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_CHARACTERJOB_SWORDMAN` | 0 | 鬼剑士 |
| `ENUM_CHARACTERJOB_FIGHTER` | 1 | 格斗家 |
| `ENUM_CHARACTERJOB_GUNNER` | 2 | 枪手 |
| `ENUM_CHARACTERJOB_MAGE` | 3 | 魔法师 |
| `ENUM_CHARACTERJOB_PRIEST` | 4 | 神父 |
| `ENUM_CHARACTERJOB_AT_GUNNER` | 5 | 女枪手 |
| `ENUM_CHARACTERJOB_THIEF` | 6 | 盗贼 |
| `ENUM_CHARACTERJOB_AT_FIGHTER` | 7 | 男格斗家 |
| `ENUM_CHARACTERJOB_AT_MAGE` | 8 | 男魔法师 |
| `ENUM_CHARACTERJOB_DEMONIC_SWORDMAN` | 9 | 魔剑士 |
| `ENUM_CHARACTERJOB_CREATOR_MAGE` | 10 | 创造者（Creator） |
| `ENUM_CHARACTERJOB_MAX` | 11 | 职业最大值（推断） |

## 动画布尔参数 ENUM_IS_* / ENUM_ANIMATION_BOOL_MAX（8 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_IS_REVERSE` | 0 | 反向（推断） |
| `ENUM_IS_START` | 1 | 起始（推断） |
| `ENUM_IS_PAUSE` | 2 | 暂停（推断） |
| `ENUM_IS_END` | 3 | 结束（推断） |
| `ENUM_IS_INTERPOLATE_ATTACKBOX` | 4 | 攻击框插值（推断） |
| `ENUM_NEVER_APPLY_ANOTHER_PLAYERS_EFFECT_ALPHA_RATE` | 5 | 不应用他人特效透明度（推断） |
| `ENUM_IS_APPLY_ANOTHER_PLAYERS_EFFECT_ALPHA_RATE` | 6 | 应用他人特效透明度（推断） |
| `ENUM_ANIMATION_BOOL_MAX` | 7 | 动画布尔参数最大值（推断） |

## 模块类型 MODULE_TYPE_*（22 个）

> `-1` 表示无模块；18~20 是「类型合并」用的逻辑值，不是新模块。

| 常量 | 值 | 说明 |
|---|---|---|
| `MODULE_TYPE_NONE` | -1 | 无模块（推断） |
| `MODULE_TYPE_ENTRANCE` | 0 | 入口（推断） |
| `MODULE_TYPE_ROOM_LIST` | 1 | 村庄（房间列表） |
| `MODULE_TYPE_SELECT_DUNGEON` | 2 | 副本选择画面 |
| `MODULE_TYPE_MAIN_GAME` | 3 | 普通副本（含异界） |
| `MODULE_TYPE_PVP` | 4 | 决斗场（PVP） |
| `MODULE_TYPE_FAIR_PVP` | 5 | 公平决斗 |
| `MODULE_TYPE_SELECT_CHANNEL` | 6 | 选择频道（推断） |
| `MODULE_TYPE_WARROOM` | 7 | 战争区域 |
| `MODULE_TYPE_LOGIN` | 8 | 登录（推断） |
| `MODULE_TYPE_ASSAULT` | 9 | 对战（来战） |
| `MODULE_TYPE_DEAD_TOWER` | 10 | 死亡之塔 |
| `MODULE_TYPE_BLOOD_SYSTEM` | 11 | 无限祭坛 |
| `MODULE_TYPE_DESPAIR_TOWER` | 12 | 绝望之塔 |
| `MODULE_TYPE_BOSS_TOWER` | 13 | 深渊斗技场 |
| `MODULE_TYPE_ADVANCE_ALTAR` | 14 | 进击的祭坛 |
| `MODULE_TYPE_LOAD` | 15 | 加载（推断） |
| `MODULE_TYPE_TOURNAMENT` | 16 | 锦标赛（推断） |
| `MODULE_TYPE_MAX` | 17 | 模块类型最大值（推断） |
| `MODULE_TYPE_PVP_TYPE` | 18 | 决斗场/对战/战争区域统称 |
| `MODULE_TYPE_DUNGEON_TYPE` | 19 | 副本/死亡之塔/无限制统称 |
| `MODULE_TYPE_ALL` | 20 | 全部模块（推断） |

## 攻击类型（扩充）ATTACKTYPE_*（8 个）

> 把光/暗/水/火也算作攻击类型；前三条与 859 行那一段重复。

| 常量 | 值 | 说明 |
|---|---|---|
| `ATTACKTYPE_PHYSICAL` | 0 | 独立物理攻击 |
| `ATTACKTYPE_MAGICAL` | 1 | 独立魔法攻击 |
| `ATTACKTYPE_ABSOLUTE` | 2 | 无视防御攻击 |
| `ATTACKTYPE_LIGHT` | 3 | 光属性（推断） |
| `ATTACKTYPE_DARK` | 4 | 暗属性（推断） |
| `ATTACKTYPE_WATER` | 5 | 水属性（推断） |
| `ATTACKTYPE_FIRE` | 6 | 火属性（推断） |
| `ATTACKTYPE_MAX` | 7 | 攻击类型最大值（推断） |

## 增益来源 BUFF_*（6 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `BUFF_CAUSE_NORMAL` | 0 | 一般（与附加体同类型） |
| `BUFF_CAUSE_ACTIVE_STATUS` | 1 | 异常状态 |
| `BUFF_CAUSE_SKILL` | 2 | 技能 |
| `BUFF_CAUSE_EXCEPTIONAL` | 3 | 特殊处理（如村庄内保留的增益图标） |
| `BUFF_NONE` | 4 | 不做任何事 |
| `BUFF_CAUSE_MAX` | 5 | 增益原因最大值（推断） |

## 暂停类型 PAUSETYPE_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `PAUSETYPE_NONE` | 0 | 不暂停 |
| `PAUSETYPE_OBJECT` | 1 | 仅对象暂停（不受重力） |
| `PAUSETYPE_WORLD` | 2 | 全世界暂停（附加体/状态/特效也停） |

## 属性 ENUM_ELEMENT_*（6 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `ENUM_ELEMENT_FIRE` | 0 | 火 |
| `ENUM_ELEMENT_WATER` | 1 | 水 |
| `ENUM_ELEMENT_DARK` | 2 | 暗 |
| `ENUM_ELEMENT_LIGHT` | 3 | 光 |
| `ENUM_ELEMENT_NONE` | 4 | 无属性 |
| `ENUM_ELEMENT_MAX` | 4 | 属性最大值（== 无属性） |

## 投掷/设置道具 THROW_TYPE_* / SETUP_TYPE_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `THROW_TYPE_SKILL` | 0 | 技能 |
| `THROW_TYPE_ITEM` | 1 | 投掷道具 |
| `SETUP_TYPE_ITEM` | 2 | 设置道具 |

## 速度类型 SPEED_TYPE_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `SPEED_TYPE_CONST` | 0 | 常量值；需重调静态速度信息才生效 |
| `SPEED_TYPE_MOVE_SPEED` | 1 | 移动速度 |
| `SPEED_TYPE_ATTACK_SPEED` | 2 | 攻击速度 |
| `SPEED_TYPE_EXCEPT_WEAPON_ATTACK_SPEED` | 3 | 不含武器的攻击速度 |
| `SPEED_TYPE_CAST_SPEED` | 4 | 施放速度 |

## Z 轴加速度类型 Z_ACCEL_TYPE_*（4 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `Z_ACCEL_TYPE_CONST` | 0 | 任意常量 |
| `Z_ACCEL_TYPE_GRAVITY_WORLD` | 1 | 重力：世界强制重力 |
| `Z_ACCEL_TYPE_GRAVITY_OBJECT` | 2 | 重力：角色各自重力 |
| `Z_ACCEL_TYPE_ANTIGRAVITY_OBJECT` | 3 | 反重力：与重力相反的力或升力 |

## 静态信息深度 STATICINFO_DEPTH（1 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `STATICINFO_DEPTH` | 4 | 静态信息最大存储深度 |

## 移动速度基准 X_* / Y_*（4 个）

> 单位是「每秒像素」，不是比例。

| 常量 | 值 | 说明 |
|---|---|---|
| `X_NORMALMOVE_VELOCITY` | 143 | 横向移动每秒横向像素数 |
| `X_SLANTMOVE_VELOCITY` | 119 | 斜向移动每秒横向像素数 |
| `Y_NORMALMOVE_VELOCITY` | 114 | 纵向移动每秒纵向像素数 |
| `Y_SLANTMOVE_VELOCITY` | 95 | 斜向移动每秒纵向像素数 |

## 物理常数 FORCE_TO_VELOCITY_CONST / SPEED_VALUE_DEFAULT（2 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `FORCE_TO_VELOCITY_CONST` | 4000 | 力换算速度常数：速度=常数*力/重量 |
| `SPEED_VALUE_DEFAULT` | 1000 | 速度值基准（该值即 100%） |

## 音效重量与重力 LIGHT_* / MIDDLE_* / DEFAULT_GRAVITY_ACCEL（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `LIGHT_OBJECT_MAX_WEIGHT` | 60000 | 音效中“轻”重量上限 |
| `MIDDLE_OBJECT_MAX_WEIGHT` | 100000 | 音效中“中”重量上限 |
| `DEFAULT_GRAVITY_ACCEL` | -1500 | 默认重力加速度（-1500） |

## 对象消息 OBJECT_MESSAGE_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `OBJECT_MESSAGE_INVINCIBLE` | 0 | 无敌消息（推断） |
| `OBJECT_MESSAGE_GHOST` | 1 | 穿透/幽灵消息（推断） |
| `OBJECT_MESSAGE_SUPERARMOR` | 2 | 霸体消息（推断） |
| `OBJECT_MESSAGE_UNBREAKABLE` | 3 | 不可破坏消息（推断） |
| `OBJECT_MESSAGE_END` | 4 | 对象消息结束（推断） |

## 恢复类型 RECOVER_TYPE_*（4 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `RECOVER_TYPE_HP` | 0 | HP 恢复（推断） |
| `RECOVER_TYPE_MP` | 1 | MP 恢复（推断） |
| `RECOVER_TYPE_HP_MP` | 2 | HP+MP 恢复（推断） |
| `RECOVER_TYPE_MAX` | 3 | 恢复类型最大值（推断） |

## 原因 REASON_*（5 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `REASON_NONE` | 0 | 无原因（推断） |
| `REASON_DEATH` | 1 | 死亡（推断） |
| `REASON_MOVING_VILLAGE` | 2 | 移动村庄（推断） |
| `REASON_LOGIN` | 3 | 登录（推断） |
| `REASON_ALL` | 4 | 全部原因（推断） |

## 移动热键（第一次定义）OPTION_HOTKEY_MOVE_*（5 个）

> 后面 1226 行附近还有一份更完整的同名定义，且顺序不同（DOWN=2、LEFT=1）。

| 常量 | 值 | 说明 |
|---|---|---|
| `OPTION_HOTKEY_MOVE_UP` | 0 | 上移热键（推断） |
| `OPTION_HOTKEY_MOVE_DOWN` | 2 | 下移热键（推断） |
| `OPTION_HOTKEY_MOVE_LEFT` | 1 | 左移热键（推断） |
| `OPTION_HOTKEY_MOVE_RIGHT` | 3 | 右移热键（推断） |
| `ENUM_SUBKEY_TYPE_ALL` | 7 | 子键类型全部（7）（推断） |

## 成长类型（男魔法师）GROW_TYPE_*（3 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `GROW_TYPE_AT_MAGE` | 0 | 男魔法师 |
| `GROW_TYPE_ELEMENTAL_BOMBER` | 1 | 元素爆破者 |
| `GROW_TYPE_GRACIAL_MASTER` | 2 | 冰结师（Glacial Master） |

## 打击粒子 PARTICLE_CREATER_*（7 个）

| 常量 | 值 | 说明 |
|---|---|---|
| `PARTICLE_CREATER_LARGE_HIT` | 0 | 大打击粒子 |
| `PARTICLE_CREATER_SMALL_HIT` | 1 | 小打击粒子 |
| `PARTICLE_CREATER_FIRE_HIT` | 2 | 火属性打击粒子 |
| `PARTICLE_CREATER_FIRE_HIT_LIGHT` | 3 | 火属性打击粒子（轻） |
| `PARTICLE_CREATER_WATER_HIT` | 4 | 水属性打击粒子 |
| `PARTICLE_CREATER_WATER_HIT_LIGHT` | 5 | 水属性打击粒子（轻） |
| `PARTICLE_CREATER_WATER_HIT_ICE` | 6 | 水属性打击粒子（冰） |

## 热键定义 OPTION_HOTKEY_*（88 个）

> 完整表：包含上面那 5 个重复的移动热键。

| 常量 | 值 | 说明 |
|---|---|---|
| `OPTION_HOTKEY__UNDEFINED` | -1 | 未定义热键 |
| `OPTION_HOTKEY_MOVE_UP` | 0 | 上（↑） |
| `OPTION_HOTKEY_MOVE_LEFT` | 1 | 左（←） |
| `OPTION_HOTKEY_MOVE_DOWN` | 2 | 下（↓） |
| `OPTION_HOTKEY_MOVE_RIGHT` | 3 | 右（→） |
| `OPTION_HOTKEY_ATTACK` | 4 | 攻击（X） |
| `OPTION_HOTKEY_JUMP` | 5 | 跳跃（C） |
| `OPTION_HOTKEY_SKILL` | 6 | 技能（Z） |
| `OPTION_HOTKEY_SKILL2` | 7 | 增益键（空格） |
| `OPTION_HOTKEY_CREATURE_SKILL` | 8 | 生物技能（V） |
| `OPTION_HOTKEY_STATUS_WINDOW` | 9 | 状态窗口（M） |
| `OPTION_HOTKEY_SKILL_WINDOW` | 10 | 技能窗口（K） |
| `OPTION_HOTKEY_ITEM_INVENTORY` | 11 | 物品栏（I） |
| `OPTION_HOTKEY_OPTION_WINDOW` | 12 | 选项窗口（O） |
| `OPTION_HOTKEY_NORMAL_QUEST_WINDOW` | 13 | 普通任务窗口（Q） |
| `OPTION_HOTKEY_AVATAR_INVENTORY` | 14 | 时装栏（U） |
| `OPTION_HOTKEY_CERASHOP` | 15 | 商城（T） |
| `OPTION_HOTKEY_MINIMAP` | 16 | 副本小地图（N） |
| `OPTION_HOTKEY_CREATURE_WINDOW` | 17 | 生物窗口（Y） |
| `OPTION_HOTKEY_TOOLTIP_` | 18 | 详细查看切换键（R） |
| `OPTION_HOTKEY_EPIC_QUEST_WINDOW` | 19 | 史诗任务窗口（W） |
| `OPTION_HOTKEY_QUICK_SKILL1` | 20 | 技能快捷栏（A、S、D、F、G、H） |
| `OPTION_HOTKEY_QUICK_SKILL2` | 21 | 技能快捷栏2（推断） |
| `OPTION_HOTKEY_QUICK_SKILL3` | 22 | 技能快捷栏3（推断） |
| `OPTION_HOTKEY_QUICK_SKILL4` | 23 | 技能快捷栏4（推断） |
| `OPTION_HOTKEY_QUICK_SKILL5` | 24 | 技能快捷栏5（推断） |
| `OPTION_HOTKEY_QUICK_SKILL6` | 25 | 技能快捷栏6（推断） |
| `OPTION_HOTKEY_EXSKILL1` | 26 | 扩展技能栏（F1-F6） |
| `OPTION_HOTKEY_EXSKILL2` | 27 | 扩展技能栏2（推断） |
| `OPTION_HOTKEY_EXSKILL3` | 28 | 扩展技能栏3（推断） |
| `OPTION_HOTKEY_EXSKILL4` | 29 | 扩展技能栏4（推断） |
| `OPTION_HOTKEY_EXSKILL5` | 30 | 扩展技能栏5（推断） |
| `OPTION_HOTKEY_EXSKILL6` | 31 | 扩展技能栏6（推断） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT1` | 32 | 道具快捷栏（1-6） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT2` | 33 | 道具快捷栏2（推断） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT3` | 34 | 道具快捷栏3（推断） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT4` | 35 | 道具快捷栏4（推断） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT5` | 36 | 道具快捷栏5（推断） |
| `OPTION_HOTKEY_ITEM_QUICKSLOT6` | 37 | 道具快捷栏6（推断） |
| `OPTION_HOTKEY_TOGGLE_ITEM_NAME_IN_DUNGEON` | 38 | 副本中查看物品名（Ctrl） |
| `OPTION_HOTKEY_HIDE_MAIN_HUD` | 39 | 隐藏界面（Tab） |
| `OPTION_HOTKEY_TOGGLE_TITLE_ANIMATION` | 40 | 昵称信息模式切换（E） |
| `OPTION_HOTKEY_TOGGLE_SKILL_INFORMATION` | 41 | 技能提示说明模式切换（F7） |
| `OPTION_HOTKEY_PAUSE_IN_TOWER` | 42 | 死亡之塔暂停 |
| `OPTION_HOTKEY_CAPTURE_MOVING_PICTURE` | 43 | 录像捕获（Pause） |
| `OPTION_HOTKEY_MENU_MY_INFO` | 44 | 我的仓库菜单（7） |
| `OPTION_HOTKEY_MENU_COMMUNITY` | 45 | 社区菜单（8） |
| `OPTION_HOTKEY_MENU_CONTENTS` | 46 | 内容菜单（9） |
| `OPTION_HOTKEY_MENU_SERVICE` | 47 | 服务菜单（0） |
| `OPTION_HOTKEY_MENU_SYSTEM__CLOSE_ALL_WINDOW` | 48 | 关闭所有窗口（Esc） |
| `OPTION_HOTKEY_PVP` | 49 | 决斗场（P） |
| `OPTION_HOTKEY_RECOMMEND_USER` | 50 | 推荐同伴（[） |
| `OPTION_HOTKEY_PARTY_MATCHING` | 51 | 队伍匹配（]） |
| `OPTION_HOTKEY_FRIEND` | 52 | 好友（L） |
| `OPTION_HOTKEY_GUILD` | 53 | 公会（;） |
| `OPTION_HOTKEY_MEMBER` | 54 | 成员（'） |
| `OPTION_HOTKEY_BLACKLIST` | 55 | 屏蔽名单 |
| `OPTION_HOTKEY_PVP_BUDDY` | 56 | 决斗好友 |
| `OPTION_HOTKEY_WAR_AREA_LIST` | 57 | 战争区域列表（,） |
| `OPTION_HOTKEY_AUCTION_WINDOW` | 58 | 拍卖行（B） |
| `OPTION_HOTKEY_GOBLIN_PAD` | 59 | 哥布林帕德（Goblin Pad） |
| `OPTION_HOTKEY_HOTKEY_SETTING_WINDOW` | 60 | 快捷键设置窗口 |
| `OPTION_HOTKEY_WAR_AREA_INFORMATION` | 61 | 战争区域信息窗（End） |
| `OPTION_HOTKEY_HELLMODE_INFORMATION` | 62 | 不再使用 |
| `OPTION_HOTKEY_FAVOR_CHECK_WINDOW` | 63 | 不再使用 |
| `OPTION_HOTKEY_EXPERT_JOB` | 64 | 专业职业功能 |
| `OPTION_HOTKEY_EMOTION_EXPRESSION` | 65 | 表情功能 |
| `OPTION_HOTKEY_EVENT` | 66 | 活动键（Shift） |
| `OPTION_HOTKEY_PVP_MSSION` | 67 | 任务窗口 |
| `OPTION_HOTKEY_PVP_RECORD` | 68 | 战绩查看窗 |
| `OPTION_HOTKEY_QUICK_CHAT_0` | 69 | 快捷聊天0（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_1` | 70 | 快捷聊天1（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_2` | 71 | 快捷聊天2（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_3` | 72 | 快捷聊天3（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_4` | 73 | 快捷聊天4（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_5` | 74 | 快捷聊天5（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_6` | 75 | 快捷聊天6（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_7` | 76 | 快捷聊天7（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_8` | 77 | 快捷聊天8（推断） |
| `OPTION_HOTKEY_QUICK_CHAT_9` | 78 | 快捷聊天9（推断） |
| `OPTION_HOTKEY_TOGGLE_ITEMINFO_COMPARE` | 79 | 物品比较窗切换键（默认 F8） |
| `OPTION_HOTKEY_TITLEBOOK` | 80 | 称号簿 |
| `OPTION_HOTKEY_THIS_DUNGEON` | 81 | 再次挑战 |
| `OPTION_HOTKEY_ANOTHER_DUNGEON` | 82 | 挑战其他副本 |
| `OPTION_HOTKEY_RETURN_TO_TOWN` | 83 | 返回村庄 |
| `OPTION_HOTKEY_MERCENARY_SYSTEM` | 84 | 佣兵系统 |
| `OPTION_HOTKEY_ITEM_DICTIONARY` | 85 | 道具图鉴（推断） |
| `OPTION_HOTKEY_QUICK_PARTY_REGISTER` | 86 | 快速组队登记请求 |

## 通用技能：破坏者 STATE_BURSTER / SKILL_BURSTER（2 个）

> 公共技能（所有职业共享），附在文件末尾。

| 常量 | 值 | 说明 |
|---|---|---|
| `STATE_BURSTER` | 100 | 通用技能 state：破坏者 |
| `SKILL_BURSTER` | 198 | 通用技能：破坏者（Burster） |

## 附录：源文件里被注释掉的旧定义

源文件 1187~1213 行夹着一批 `//NAME <- 值`。它们在 Squirrel 里**不生效**，所以既不在上表、也不算作本文件的常量定义。

- `MODULE_TYPE_LABYRINTH`(7)、`MODULE_TYPE_CHAOS`(8) 是**废弃模块**：7 号和 8 号后来分别改给了 `MODULE_TYPE_WARROOM`(7) 与 `MODULE_TYPE_LOGIN`(8)，这两个名字在 `SqrConsts` 里不存在。
- 其余 6 条（LOAD~ALL）在生效区**另有同名定义**，值为 15~20；注释掉的 13~18 是旧编号，整块是「改编号后忘了删的残留」，不影响最终取值（`SqrConsts` 取的是生效区的值）。

| 常量 | 旧值 | 说明 |
|---|---|---|
| `MODULE_TYPE_LABYRINTH` | 7 | 已消失（原注「사라짐」）；7 号已改给 `MODULE_TYPE_WARROOM` |
| `MODULE_TYPE_CHAOS` | 8 | （无注释）；8 号已改给 `MODULE_TYPE_LOGIN` |
| `MODULE_TYPE_LOAD` | 13 | （无注释）；生效区同名定义的值为 15 |
| `MODULE_TYPE_TOURNAMENT` | 14 | （无注释）；生效值为 16 |
| `MODULE_TYPE_MAX` | 15 | （无注释）；生效值为 17 |
| `MODULE_TYPE_PVP_TYPE` | 16 | 决斗场、对战、战争区域的统称；生效值为 18 |
| `MODULE_TYPE_DUNGEON_TYPE` | 17 | 副本、死亡之塔、无限制的统称；生效值为 19 |
| `MODULE_TYPE_ALL` | 18 | 指所有模块；生效值为 20 |

## 附录：同名重复定义

Squirrel 后写覆盖先写，`SqrConsts` 生成时取**最后一次**的值（与运行期一致）。下列名字在本文件里出现了两次：

| 常量 | 首次（行） | 二次（行） | 生效值 |
|---|---|---|---|
| `STATE_VIRTUAL_ATTACK` | 32（134） | 19（562） | 19 |
| `WEAPON_SUBTYPE_MAX` | 6（536） | 5（913） | 5 |
| `ATTACKTYPE_MAX` | 3（885） | 7（1223） | 7 |

