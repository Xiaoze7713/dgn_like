# 11 · P0 三问收口：flagIndex / .atk 索引 / 伤害公式

> 目的：把 ROADMAP 里挡住「战斗能不能动」的三件事各自收口到一个**可执行**的结论。
> 每条结论后标证据等级：**实证**（有命令与数据，可复跑）/ **推断**（有间接证据，缺最后一环）/ **自定**（PVF 里没有，我们自己的设计选择）。
> 三问都不需要再读全量语料，实现组看完 §4 就能开工。

| 问题 | 一句话结论 | 等级 |
|---|---|---|
| ① `flagIndex` 从哪来 | `.ani` 每帧字段 **`0x17`，4 字节小端整数**；帧推进到该帧就回调 `onKeyFrameFlag(obj, 0x17值)` | 实证 |
| ② `.atk` 整数索引怎么解 | 解析到**角色自己的 `.chr` `[etc attack info]` 有序数组，0 基下标**；不是目录排序，也没有全局 `.lst` | 实证 |
| ③ 伤害公式 | 9 步管线里 ③④⑤⑦ 高可信，⑥（防御减免）PVF 里没有，用线性式替代；Lv1 单次普攻量级 **6~12** | 实证 + 自定 |

---

## 1. 阻断 1：`flagIndex` 由 `.ani` 哪个字段承载

### 1.1 症状回顾

脚本里 `onKeyFrameFlag(obj, flagIndex)` 的实参见过 `67` / `100` / `101`，而 `docs/ANI-FORMAT.md` 记的 `0x17` 是「4~6B 未知字段，取值 0..7」。两边对不上，于是怀疑还有别的字段。

### 1.2 结论（实证）

`0x17` 就是 flagIndex，值域是**作者自定义的整数**，不是位掩码、也不是 0..7 的枚举。ANI-FORMAT 的「0..7」是抽样里小值占多数造成的假象（多数帧的 flag 是 `1`/`2`/`3` 这类小整数）。

证据（`tools/ani_parser.py` 的 `parse_ani()`，字段落在帧的 `other_fields`，不在 `fields`）：

```
export/text/character/swordman/atanimation/dashattack.ani.bin   （5 帧）
  帧 0  0x17  —                  帧 1  0x17 raw=64000000 → 100
  帧 2  0x17  —                  帧 3  0x17 raw=01000000 → 1
  帧 4  0x17 raw=65000000 → 101
export/text/character/swordman/atanimation/after_threesideex.ani.bin
  帧 2  0x17 raw=03000000 → 3
```

`64000000` / `65000000` 是 4 字节小端 `i32`（100 / 101），与脚本实参**逐一相等**。一条 `.ani` 里同时出现 `100` 和 `101`，正好对上剑士冲刺攻击脚本里两个 case。复跑：

```bash
python3 -c "import sys;sys.path.insert(0,'tools');from ani_parser import parse_ani;\
d=parse_ani(open('export/text/character/swordman/atanimation/dashattack.ani.bin','rb').read());\
print([[o['value']['raw'] for o in f['other_fields'] if o['id']=='0x17'] for f in d['frames']])"
```

### 1.3 语义与执行顺序

- **承载文件**：`.ani`，每帧的帧头字段区（`u16 n_head` 之后那一段），与坐标 `x/y`、`[DELAY]` 同级；**同一帧可以有 0 个或 1 个 `0x17`**。
- **消费端**：角色 `.nut` 的 `onKeyFrameFlag(obj, flagIndex)`；怪物侧在 `.act` 的 `[BEHAVIOR]` 里按帧号挂行为，不读 `0x17`。
- **时序**：帧**进入**时先切图（`image`/`image_frame`）→ 再触发 `0x17` → 同一帧的 `[ATTACK BOX]` 在本帧内持续有效。三者互不依赖：一帧可以只有攻击盒没有 flag，也可以只有 flag 没有攻击盒（`attack1.ani` 6 帧全无 `0x17`，`dashattack.ani` 帧 1 有 4 个攻击盒 + flag 100）。
- **别混淆**：`0x0b`（统计上 99.7% 取值 2，ANI-FORMAT 猜 `[GRAPHIC EFFECT]`）**不是** flag；它跟 `0x17` 在 30,000 抽样里出现频次差 10 倍（`0x0b` 107,920 次 vs `0x17` 9,260 次），语义不同。

### 1.4 实现口径

```gdscript
# 每帧推进时
if frame.has_flag_0x17:
    owner.on_key_frame_flag(frame.flag_0x17)   # 幂等：同一帧只发一次
if frame.attack_boxes.size() > 0:
    hitbox.enable_for_frame(frame.attack_boxes, damage_type)
```

- 同一帧重复进入（回放/断线重连）时用「帧序号 + 已发集合」去重（自定）。
- 帧数据里 `0x17` 缺失 ≠ flag 0；是「本帧不回调」，两者要分开存（自定）。

### 1.5 仍未闭合（不影响开工）

- `0x17` 与 `0x0b` 是否**互斥**：目前看到的样本里同帧同时出现的情况没统计。稳妥做法是两个都发、脚本侧幂等（自定）。
- `0x17` 是否有符号：实测值都是正整数，按 `i32` 读即可。

---

## 2. 阻断 2：`.atk` 整数索引 → 文件的注册表在哪

### 2.1 结论（实证）

**注册表就是角色自己的 `.chr` 里的 `[etc attack info]` 有序数组，索引是 0 基下标。** 没有全局 `.lst`，没有 exe 内置表可查（`attackinfo*.lst` 全库 0 命中）。

最硬的一条证据是「武器连击分支」——脚本对同一段普攻按武器子类型选不同的动画与攻击信息：

```
sqr/character/swordman/attack.nut
  巨剑分支： sq_SetCurrentAnimation(37)  + sq_SetCurrentAttackInfo(36)
  其它武器： sq_SetCurrentAnimation(170) + sq_SetCurrentAttackInfo(100)
```

对照 `export/text/character/swordman/swordman.chr.txt` 的 `[etc attack info]`：

| 下标 | 数组里的路径 | 与脚本语义 |
|---|---|---|
| 36 | `AttackInfo/WeaponComboBlunt3.atk` | 巨剑第 3 段 ✔ 完全对上 |
| 35 | `AttackInfo/WeaponComboBlunt2.atk` | 若用 1 基就会错位到这一段 ✘ |
| 100 | `AttackInfo/WeaponComboBlunt4.atk` | 默认武器第 4 段 ✔ |
| 0 | `AttackInfo/HardAttack.atk` | 全库 `sq_SetCurrentAttackInfo(0)` 出现最多的默认槽 |

`WeaponComboBlunt3.atk` 的内容也自洽：`[damage bonus] 49`、`[push aside] 110`、`[lift up] 180`、`[hit info] [blow] [no blood] 65 1.5`——重剑第三段的「大击退 + 浮空」。

数组长度实测（同一解析器，`[etc attack info]` 只出现 1 次，不存在多块合并）：

| 文件 | 条目数 |
|---|---|
| `character/swordman/swordman.chr` | **154** |
| `character/fighter/fighter.chr` | **103** |
| `monster/casillas/casillas.mob` | 3（另有 `[attack info]` 3，怪物是**分块**的：普攻 3 槽 + 其它 3 槽） |

### 2.2 任务书里的 290 / 244 复现不出来

任务书说「swordman 290 项、fighter 244 项」。我用三种口径都数过：

| 口径 | swordman | fighter |
|---|---|---|
| `.chr` 的 `[etc attack info]` 条目 | 154 | 103 |
| `.chr` 全文里 `.atk` 字符串出现次数 | 159 | — |
| `character/<job>/attackinfo/` 下 `.atk` 文件数 | 111 | 122 |
| 整个 `character/<job>/`（含 zrr 子目录）`.atk` 文件数 | 541 | — |

**都不是 290 / 244。** 最可能的来源是把「目录里的 `.atk` 文件数」或「`.chr` 的 `[etc motion]` 条目数」（swordman 280、fighter 212）记成了数组长度。这不影响结论，反而印证了一件事：

> **目录里的 `.atk` 文件远多于数组槽位**（541 个文件 vs 154 个槽）。所以索引**绝不可能**是「按文件名排序取第 N 个」——那样一加文件就全错。以数组为准。

### 2.3 私服（zrr）改过数组，常量表已错位（实证）

`sqr/character/swordman_jg/swordman_value.nut` 里定义了一组 `ATTACKINFO_* <- <整数>` 常量，理论上应该等于数组下标：

```
ATTACKINFO_BLOODCUTHIT_LAST          <- 117
ATTACKINFO_BALDECHANGTION_NORMALATTACK <- 118
...
ATTACKINFO_UNLIMITED_SPEEDSLASH_FINISH_HIT <- 154
```

但现在的 `swordman.chr`：

```
[117] attackinfo/zrr/rage_atk3.atk
[118] attackinfo/zrr/bladespiritattack1.atk
...
[153] attackinfo/zrr/explosionofpathend.atk
[151] AttackInfo/DashAttack.atk        ← 与 zrr 条目交替
```

从 117 起被私服塞进了 `attackinfo/zrr/*` 的条目（且是**穿插**，不是整段后移），下游 35 个常量全部指向了错误的 `.atk`。也就是说：**这份私服的剑神技能，攻击信息大概率是错的**（伤害/硬直对不上原版）。

这也解释了为什么「用常量反查数组」会得到 0/35 命中率——不是我的解析错，是数据本身错位。

### 2.4 另一张表：`CUSTOM_ATTACKINFO_*` 全局枚举（实证，但不是你要的那张）

`export/text/sqr/dnf_enum_header.nut.txt` 里有 154 条 `CUSTOM_ATTACKINFO_* <- <0..83>`，是**跨职业共享的「通用抓取/投技槽」语义表**（`CRASH_LOW_KICK` 0、`LIFT_UPPER` 1、`SUPLEX` 4、`MOUNT` 5 …）。

`fighter.chr` 的数组前 15 项与它**逐项同名同序**：

```
0 CrashLowKick.atk == CUSTOM_ATTACKINFO_CRASH_LOW_KICK 0
1 LiftUpper.atk    == CUSTOM_ATTACKINFO_LIFT_UPPER 1
2 DamageLowKick.atk== CUSTOM_ATTACKINFO_DAMAGE_LOW_KICK 2
3 TryGrab.atk      == CUSTOM_ATTACKINFO_TRY_GRAB 3
4 Suplex.atk       == CUSTOM_ATTACKINFO_SUPLEX 4
...（0..14 全对，15 项）
```

但 `swordman.chr` 的第 0 项是 `HardAttack.atk`，跟这张表**不对应**。所以：

- 这张枚举是「通用动作（抓/摔/骑）」的规范命名表，供公共脚本按名字取槽；
- 它**不是**每个职业整张表（各职业技能的攻击信息不在里面）；
- 复刻时它的价值是：告诉我们 DNF 自己也需要「语义名 → 槽号」的一层，而不是裸整数到处都是。

### 2.5 实现口径（照做）

```
载入期（每个职业一次）：
  chr = 解析 <job>.chr
  atk_paths = chr["etc attack info"]          # 有序数组，0 基
  for i, p in enumerate(atk_paths):
      atk[i] = parse( p 相对于 character/<job>/ )   # 注意路径前缀有 AttackInfo/ 与 attackinfo/ 两种大小写

运行期（技能/普攻）：
  skill = 我们的技能表[skill_id]              # 自建，不依赖原 .nut
  cur_attack_info = atk[ skill.attack_info_index ]   # 越界 → 告警并回退 atk[0]
```

三条工程决定（自定，理由附后）：

| 决定 | 理由 |
|---|---|
| **索引只在载入期用一次**，运行时对象上存 `.atk` 的属性值，不再存整数 | 私服式错位（§2.3）会静默变成错误伤害；转成值以后错误在载入期就暴露 |
| 路径解析**名字优先、大小写不敏感**：先精确匹配 `AttackInfo/X.atk`，再 `attackinfo/X.atk` | 同一份数据里两种前缀并存（117 起是小写 `attackinfo/`） |
| 越界/缺失 → **回退 `atk[0]` 并打 warning**，不崩 | `[etc attack info]` 末尾被私服改过，不能假设长 154 |

### 2.6 仍未闭合

- 其它职业（`atmage` 等）是否也 0 基：抽了 3 个职业都是 0 基，但**只对 swordman 做了逐项语义核对**（36/100 那两条）。其余职业建议用「每个职业技能脚本里的 `sq_SetCurrentAttackInfo(N)` + 该技能动画名」再核一遍，成本约 1 小时。
- `.atk` 里 `[pvp]` 子块（PVP 覆盖值）：`attack1.atk` 有，`weaponcomboblunt3.atk` 有；单机可先忽略。

---

## 3. 阻断 3：伤害公式的最大可信形式

### 3.1 PVF 里有什么、没有什么

- **有**：面板攻击力（`.chr` + `growtype` + 装备）、技能系数（`.skl` 的 `[level info]` 百分比/加值两列）、倍率（`[damage bonus]`）、属性、绝对伤害、防御数值、抗性、`[module damage rate]`。
- **没有**：公式本身。防御减免、暴击倍率、等级差修正**都不在 PVF**，在服务端/引擎里。所以任何声称「DNF 原版伤害 = …」的式子都是推断。

### 3.2 推荐形式（③④⑤⑦ 实证，⑥⑧ 自定）

```
面板攻击力 A = chr 基础 + growtype 增量 + 装备 + 被动%
技能基础     B = A × 技能百分比 + 技能加值
属性/倍率    C = B × (1 + [damage bonus]/100) × 属性克制
防御减免     D = C × clamp( 1 - 目标防御/(目标防御 + K1 + K2×攻击者等级), 0.05, 1 )
最终         E = D + [absolute damage]          # 若 [absolute damage] 存在
               （[ignore defense] / [absolute damage] 的项跳过 D）
```

- `[damage bonus]` 的语义**有官方注释**：`0` = 100%，`20` = 120%，`-15` = 85%。实证：`attack1.atk` 的 `[damage bonus] -15` = 0.85 倍。
- `K1`/`K2` 是**自定常数**，PVF 里不存在。建议初值 `K1 = 100 + 20×目标等级`、`K2 = 0`，然后按 §3.4 校准。
- 暴击：PVF 只有暴击率相关字段，**倍率取 1.5（自定）**。

### 3.3 Lv1 基准（实测字段 + 推断结果）

实测（`character/swordman/swordman.chr`）：

```
[physical attack]    7.5          [physical defense]   7.5
[HP MAX]           180.0          [MP MAX]           140.0
[attack speed]   1150.0           [move speed]      1350.0
[growtype 1]  [physical attack]-1  4.8   （每级 +4.8）
```

实测（`character/swordman/attackinfo/attack1.atk`）：`[damage bonus] -15`、`[weapon damage apply] 1`、`[push aside] 30`、`[lift up] 75`。

推算 Lv1 鬼剑士一次普攻：

```
A = 7.5（无装备、无被动）
C = 7.5 × 0.85 = 6.4
D ≈ 6.4 × (1 - 5/(5+100+20)) ≈ 6.1     ← 假设 Lv1 小怪防御 5
E ≈ 6
```

→ **单次普攻 6 左右（推断；`[weapon damage apply]` 是否引入武器攻击力会让它翻到 10~15，见 §3.5）**。
→ 配「Lv1 小怪 5~8 下打死」的手感锚点，怪物 HP 应落在 **30~50**（自定）。这一条比公式本身重要：DNF 的战斗手感是「短 TTK + 强反馈」，不是「数值精确」。

### 3.4 怎么校准（不要凭感觉调）

1. 先用 §3.2 的式子跑通，所有自定常数写成 `const` 并集中在一个 `CombatTuning` 资源里（自定）。
2. 拿 3 个已知数值的样本对表：`.atk` 的 `[damage bonus]`、技能的 `[level info]` 百分比、装备的 `[physical attack]`——这三处是**原版真实值**，任何校准都不能改动它们，只能动 `K1`/暴击/等级差。
3. 用固定种子跑 100 次同条件攻击，看伤害方差是否为 0（暴击关掉时）。有方差说明有隐藏随机项，回头再查。

### 3.5 仍未闭合

- `[weapon damage apply] 1` 到底加不加武器攻击力：若加，Lv1 拿新手武器（物攻 +10 量级）会让单次伤害变成 16 左右，TTK 手感差一倍。验证方法：找同一技能在「空手 / 有武器」两种状态下的官方伤害录屏，或者找 `.atk` 里 `[weapon damage apply] 0` 的样本对比其数值设计（0 的样本通常是无武器技能，数值更高）。**这条建议排进下一批任务，优先级高于防御公式**。
- 等级差惩罚：`questparameter.etc` 里有难度×等级的经济表，但战斗侧的等级差修正不在 PVF。

---

## 4. 给实现组的一页清单

按顺序做，每步都能独立验证：

1. **帧驱动**（半天）：`.ani` → 帧表；每帧带 `{image, image_frame, x, y, delay, attack_boxes[], damage_boxes[], flag_0x17}`。验收：`dashattack.ani` 5 帧、帧 1 有 4 个攻击盒 + flag 100。
2. **flag 回调**（2 小时）：帧进入 → `on_key_frame_flag(v)`；用 `dashattack` 的 100/101 做自测。验收：日志里出现 `100@f1`、`101@f4`。
3. **判定**（1 天）：每帧把 6×i32 的盒子转成 `Rect2`（X/Z 是平面，Y 是高度），与目标盒做 AABB；同一次攻击对同一目标只结算一次（hit list）。
4. **攻击信息**（半天）：载入 `chr [etc attack info]` → `atk[i]` 值对象；`[damage bonus]`、`[push aside]`、`[lift up]`、`[hit info]` 四组先接。
5. **伤害**（半天）：§3.2 式子，常数集中；先不做防御（`D = C`），把手感跑出来再加。
6. **反馈**（1 天，最影响手感）：hit stop（`[hit info]` 的两个数 = 命中停顿 + 受击延迟倍数，如 `[blow] [no blood] 65 1.5`）、击退/浮空、受击动画。**这三项没做完之前不要调数值。**

红线（踩了会返工）：

- 不要把 `.atk` 整数索引带到运行时（§2.5）。
- 不要用 `0x0b` 当 flag（§1.3）。
- 不要试图还原 DNF 防御公式（§3.2）；也不要让防御减免超过 90%，否则高等级怪会变成无敌。

---

## 5. 三问之外，本轮顺带证伪/证实的四条

| 说法 | 实测 | 裁定 |
|---|---|---|
| 任务书：`[attack info]` swordman 290 项 | 154 项 | 以数据为准（§2.2） |
| ANI-FORMAT：`0x17` 值域 0..7、4~6B | `i32`，实测 1/3/100/101 | 以实测为准（§1.2） |
| ANI-FORMAT：`0x17` 语义待验证 | = flagIndex | 已闭合（§1.2） |
| 09：角色 `character/` 下只有 1 个 `.act` | 1 个（`booster_particle.act`，140 字节） | 一致，可作为「角色不用 .act」的旁证 |

> 下一步建议：先做 §4 的 1–3 步（帧 + flag + 判定），一周内能出一个「能打中、有卡肉」的灰盒。数值与防御放到灰盒之后再谈。
