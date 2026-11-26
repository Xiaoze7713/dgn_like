# 15 · 玩家普攻的攻击盒在「武器动画」里（推翻 t14 的「必须自定」）

> 结论一句话：**普攻第 1、2 段有攻击盒，位置是 `equipment/character/<job>/weapon/<武器类型>/<套名>/attack1.ani`，不在 `character/<job>/animation/` 里。**
> `analysis/14-SKILL-ANIM-MAP.md` 的「普攻 1/2 段无攻击盒、需自定」**作废**——它只查了角色动画副本。

---

## 1. 怎么发现的

t14 查 `character/swordman/animation/attack1.ani`：10 帧、只有 0x0E（受击盒）、没有 0x0F（攻击盒）→ 判定「无盒」。
但鬼剑士的攻击动画**是两层叠加**：

| 层 | 文件 | 帧数 | 内容 |
|---|---|---|---|
| 身体 | `character/swordman/animation/attack1.ani` | 10 | 人物姿态 + 受击盒（`db`，3 块 = 头/躯干/腿） |
| 武器 | `equipment/character/swordman/weapon/katana/katanac/attack1.ani` | **10** | 武器轨迹 + **攻击盒（`ab`）** |

两边帧数逐一对应（attack1 10、attack2 11、attack3 9），时长也一致（600/650/550 ms）。
→ 攻击判定不是「角色文件里缺了」，而是**挂在武器那一层上**。

## 2. 实测：刀类普攻三段

```
equipment/character/swordman/weapon/katana/katanac/attack1.ani  (10 帧 / 600 ms)
  f3  ab = [49, -10, 47, 68, 23, 53]

equipment/character/swordman/weapon/katana/katanac/attack2.ani  (11 帧 / 650 ms)
  f2  ab = [58, -26, 54, 74, 49, 30]
  f3  ab = [-45, -17, 36, 91, 55, 35]

equipment/character/swordman/weapon/katana/katanac/attack3.ani  (9 帧 / 550 ms)
  f2  ab = [-32, -10, 0, 179, 20, 94]
  f3  ab = [15, -10, 1, 137, 20, 138]
```

第三段与 `character/swordman/animation/attack3.ani` 里那份几乎一致（`[-32,-13,0,179,26,94]`）——
说明**部分技能动画在角色层也带盒，普攻只靠武器层**。所以实现时「角色层有就用角色层的，没有就去武器层找」。

## 3. 覆盖度（鬼剑士，非 `at_` 套）

| 武器类型 | 套数 | 有攻击盒 | 普攻 1 段最远触及 X |
|---|---|---|---|
| katana | 10 | 9 | 104 ~ 111 |
| ssword | 13 | 12 | 104 |
| hsword | 8 | 8 | 104 |
| club | 9 | 8 | 104 |
| beamsword | 11 | 8 | 104 |
| **合计** | **51** | **45** | — |

- 45/51 套在普攻 1 段就有盒；缺的 6 套全是 `at_` 前缀或特殊外观套。
- **不同武器实际判定范围不同**（katana 能到 111，其余 104）——说明「武器类型影响手感」这件事是真的，不只是数值面板。

## 4. `at_` 前缀 / `ATEquipment` 是什么

`character/swordman/atanimation/attack1.ani` 用的是另一套图 `ATEquipment/Avatar/skin/sg_body%04d.img`，
帧数 6/5/4（与本体 10/11/9 不同）。它不是「普攻的判定来源」，而是**另一套外观（AT）的动画**。
同理 `equipment/.../weapon/beamsword/at_beamswda/` 这些套也没有普攻盒。

→ **解析顺序要加一层「过滤 `at_` / ATEquipment」**，否则会把 6 帧的 AT 动画错配到 10 帧的本体上。

## 5. 实现口径

```
普攻第 N 段 =
    body  = character/swordman/animation/attack{N}.ani        ← 姿态 + 受击盒
  + weapon = equipment/character/swordman/weapon/<type>/<set>/attack{N}.ani  ← 武器轨迹 + 攻击盒
  两层帧数必须相等，按帧号一一对应叠加
  攻击盒判定：优先 weapon 层；weapon 层没有再看 body 层
```

`<set>` 由**装备的武器 `.equ`** 决定（`[icon]` 只给图标；套装对应关系在 `.equ` 的动画相关字段里，待补精确字段名）。
切片阶段可以硬编码：太刀 → `katana/katanac`。

## 6. `.equ → 武器动画套` 的映射（已挖到）

武器 `.equ` 里有三个字段构成完整链路（以 `equipment/character/swordman/weapon/katana/kat_damaged.equ` 为例）：

```
[equipment type]
    [weapon] 17 
[animation job]
    [swordman] 
[layer variation]
    2790 katanac                          ← 第 1 值 = 层槽位，第 2 值 = 动画套目录名
[equipment ani script]
    equipment/character/swordman.lay       ← 层模板（含 %s 占位）
[item group name]
    katana 
```

拼接规则：

```
weapon_ani = <该 .equ 所在目录> / <layer variation 第 2 值> / <motion>.ani
           = equipment/character/swordman/weapon/katana/katanac/ attack1.ani
```

`.lay` 模板只写 `%s/Attack1.ani`（见 `export/text/equipment/character/swordman.lay.txt` 的 `[attack motion]`），
`%s` 就是 `[layer variation]` 的第二个值 —— **所以「哪个套」完全由 `.equ` 决定，不由文件名猜**。

`[layer variation]` 第 1 值实测分布（400 个鬼剑士武器 `.equ`）：

| 层槽位 | 含义（推断） | 出现 |
|---|---|---|
| `2790` | 普通武器层 | 主用 |
| `2791` | 替代武器层（`lswdc1` 这类） | 少量 |
| `650` | 黑暗武士（`[demonic swordman]`）块用 | 14 |
| `2050` | 作者自定义外观（`at_lswda`） | 2 |

**多职业块**：同一 `.equ` 里有 `[animation job]` / `[layer variation]` / `[equipment ani script]` 的
**重复段，用 `-1` / `-2` 后缀区分**（`[animation job]-1 [demonic swordman]`、`[layer variation]-1 650 katanab`、
`[equipment ani script]-1 equipment/character/swordman.lay`）。→ 解析 `.equ` 时必须按后缀分组，
否则会把不同职业的层混在一起（这是 `docs/STRUCTURED-DATA.md` 记的「同名标签 `-N` 后缀」坑的一个实例）。

## 7. 仍未闭合

- `[item group name]`（`lswd`）与动画目录名（`hsword`）不一致 —— **目录名取 `.equ` 的父目录，不要用 `item group name`**，否则 `hsword/lswdc` 解不出来。
- 层槽位 `2790/2791/650/2050` 的权威语义没有文档，是实测归纳。
- 攻击盒的 `z` 与 `d` 在 2D 里怎么用：`z` 是高度偏移（跳跃攻击才会非零，如 `jumpattack` 的 `z=-11`），`d` 是深度（横版里通常忽略）。
