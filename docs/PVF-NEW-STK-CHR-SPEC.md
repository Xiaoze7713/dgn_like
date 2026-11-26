# latest PVF：`.stk`（道具）与 `.chr`（角色）规格 + 解析工具

> 数据源：latest 国服 `Script.pvf` → `analysis/pvf-new/pvf34.sqlite`（6,288,780 条目）。
> 旧版（`data/Script.pvf`，923 MB）的结论在 `analysis/02-character.md`、`05-item.md`、`06-monster.md`、`07-map.md`，**数字已过时，别直接复用**；本文只写 latest 实测。
> 用户目标（m00001）：先理解格式 → 列出 dict 探明属性与枚举 → 逐字段搞清含义；按批读、不爆内存。产出将作为 dnf_like 数据层的基础。

---

## 1. 数据层与工具链

| 环节 | 位置 | 说明 |
|---|---|---|
| 抽取库 | `analysis/pvf-new/pvf34.sqlite` | `files(path,dtype,size,chunk,off,data)` 628 万行；`text(path,body)` 只覆盖 equ/stk/skl/lua/lst |
| 目录树 | `analysis/pvf-new/pvf34.tree.sqlite` | `entries(parent,name,kind,size)` / `dirs(path,nfiles,nbytes)` |
| 字符串池 | `analysis/pvf-new/pools/strW.bin` | 509 MB，UTF-16LE 双 NUL；`strA.bin` 本版为 **0 字节** |
| 内层包 | `analysis/pvf-new/inner/Script.inner.pvf` | 850 MB |
| 官方注释 | `export/_meta/tagdict.sqlite` | 表 `tags(ext,tag,title,comment,desc,uses)`；ext=stk 274 条、chr 76 条 |
| 旧版文本导出 | `export/text/**` | 只用于交叉验证（旧版 .stk 28,794 / .chr 13，与 latest 不同） |

工具（`/home/sunmingze/dnf_like/tools/`）：

| 脚本 | 用途 | 产物 |
|---|---|---|
| `pvf_script.py` | token 化 + 通用解析 + 渲染（`python3 tools/pvf_script.py <pvf路径>`） | — |
| `stk_dict.py` | **全量** .stk 字段字典（199,043 个文件，727 字段，26 s） | `analysis/pvf-new/items/stk_dict.json`（4.2 MB：meta/enums/fields） |
| `stk_scan.py` | 探路版（400 种 layout 签名） | `analysis/pvf-new/items/stk_fields.json` |
| `chr_scan.py` | 55 个 .chr 结构树 + 字段统计（1 s） | `analysis/pvf-new/chr/chr_fields.json`、`chr_trees.json` |
| `pvf_refs.py` | 引用图（11 s，115,496 条边） | `analysis/pvf-new/chr/refs.json` |

---

## 2. token 流格式（两种文件共用）

每个 token 固定 5 字节：`[1B type][4B int32 value]`

| type | 含义 | 备注 |
|---|---|---|
| 0 | int | 直接是值 |
| 2 | float32 | 按 int32 存，需 `struct` 位重解释；打印用 `%.7g` |
| 3 | 换行 + 字符串 | 行首标签 `[grade]`，也可能是裸串 |
| 5 | `{` | 匿名块开始 |
| 6 | 反引号字符串 | 枚举串，如 ``[trade limit] 1`` |
| 7 | `}` | 匿名块结束 |
| 8 | 值字符串 | 挂在上一标签后，如 `<13::name_10000039>` |

字符串解码：`v & 1 == 1` 时起点 `(v >> 1) * 2`，UTF-16LE，双 NUL 结尾。
`dtype == 1` 且 `size % 5 == 0` 才是 token 流（`dtype == 3` 如 `*.cos` 不是）。

**两类文件的根本差异**：

- `.stk`：有显式 `[x] … [/x]` 闭合 → 可以 `parse()` 成树（值挂到当前容器最后一个子节点）。
- `.chr`：**没有任何 `{`/`}`，`[growtype N]` 也不闭合** → 只能按「标签文本 + 出现顺序」用状态机切段（见 §4）。

---

## 3. `.stk`（道具，199,043 个）

### 3.1 结构与解析规则

```
[name] <13::name_x>          [flavor text] <13::flavor_text_x>
[grade] 1  [rarity] 2        [attach type] `[trade limit] 1`
[usable job] `[all]` [/usable job]
[icon] Item/stackable/cash.img 0
[stackable type] `[usable cera package]` 0   [minimum level] 1
[stack limit] 1   [price] …   [weight] …
[impossible contents] `gift` [/impossible contents]
[need material] 10015553 265 [/need material]
```

- 列表型标签用 `[x] … [/x]` 包围；值有 4 种：int / float / 反引号枚举 / `<N::key>` 本地化引用。
- `[icon]` 恒为 `img路径 + 帧号`；`[stackable type]` 恒为 `枚举串 + 配套 int`。

### 3.2 关键枚举（`stk_dict.json → enums`，全部实测）

| 字段 | 取值（次数） |
|---|---|
| `[rarity]` | 2×82539 · 3×50532 · 6×23800 · 1×19998 · 4×12211 · 0×6511 · 8×2716 · 5×500 · 7×120 |
| `[attach type]` | `[account]`90979 · `[trade]`80942 · `[free]`14912 · `[trade delete]`5952 · `[trade limit]`2190 · `[trade limit] 1`67 · `[account`3 · `[sealing]`1 |
| `[usable job]` | `[all]`176013 · mage 3070 · swordman 2913 · priest 2805 · gunner 2772 · at swordman 2767 · at mage 2640 · fighter 2580 · thief 2453 · at fighter 2435 · knight 2374 · at gunner 2365 · demonic lancer 2340 · demonic swordman 1950 · at priest 1920 · creator mage 1709 · gun blader 1699 · archer 1161 · account 110 · imperial knight 24 |
| `[stackable type]` | 83 种，前几名见下 |
| `[item category]` | 21 值：event 41211 · monster card 8834 · cannot bind 546 · use 2nd upgrade table 541 · expertjob 370 · recipe 370 · … |
| `[action usable place]` | village 27239 · seria room 22742 · dont use assult 9418 · dungeon 1847 · pvp 402 · dont use exercise 35 · dont open 14 · pvp playing 14 · tournament 2 |
| `[impossible contents]` | gift 17814 · cant compound 12259 · use emblem 12010 · ban redeemitem 6538 · hardcore mode 2366 · free title 1440 · … |
| `[move wav]` | BONE_TOUCH 78221 · JEWEL_TOUCH 47418 · PAPER_TOUCH 30048 · POTION_TOUCH 16947 · CLOTH_TOUCH 9679 · …（29 值） |
| `[expert type]` | enchanter 10215 · alchemist 1021 · doll_controller 139 · disjointer 10 |
| `[avatar emblem target type]` | `[S socket]`12250 · `[C socket]`1420 · `[B socket]`1363 · `[A socket]`1116 · `[D socket]`1036 |

`[stackable type]` 高频：`[booster]`41394 · `[booster selection]`24814 · `[waste]`19118 · `[rune]`18395 · `[avatar emblem]`16388 · `[etc]`13581 · `[recipe]`10201 · `[material expert job]`9479 · `[enchant waste]`7938 · `[material]`7513 · `[usable cera package]`7171 · `[upgradable legacy]`4744 · `[flag gem]`2951 ……长尾到 `[apc legacy]`1。
配套 int 值：0×165748 · 1×32323 · 4×221 · 2×217 · 3×203 · 5×162 · 6×34 · 1000×31 …（136 种）。

### 3.3 `[grade]` 不是品质（重要）

全量 78 个不同值：`1×172468 · 4×12230 · 3×3206 · 84×2116 · 2×1373 · 50×922 · 57×791 · 0×385 · 6×336 · 5×307 · 37×307 · 95×301 …`

交叉表（按 `[stackable type]` 分域）：

| grade | 主要落在 | 说明 |
|---|---|---|
| 4 | `[avatar emblem]` 12,210（其 rarity 恒 6） | 徽章档位 |
| 84 / 57 | `[recipe]` 2,116 / 791 | 配方面板档位 |
| 50 | `[booster]` 707 | 礼包档位 |
| 1 | booster / booster selection / rune / waste / etc | 通用档位 |

⇒ **`[grade]` 是「按 stackable type 分域的档位号」**，不能当品质用；品质看 `[rarity]`。tagdict 对它也只有「需按父结构确认」的模糊注释。

### 3.4 数值单位与坑

- `[inventory limit]` / `[weight]` 单位 **10g**（`3000` = 30 kg）。
- `[move speed]` 以 `1000` 为基准。
- `[grade]`/`[rarity]` 都是 int，别混。
- 脏值确实存在：`[attach type] [account`、`[sealing]`（旧枚举），解析时要容错。

### 3.5 还没有官方释义的高频字段（32 个，待定名）

`icon marks`(92801, sig `str,int`) · `booster equipment grade`(23924) · `skill data up`(19834) · `usable first growtype`(18435) · `rune skillindex`/`rune option`(18395) · `equipment parameter`(容器) · `input item`(17070) · `output item`(14276) · `hide booster info` · `enchant index` · `fame table` · `recommend` · `purchase limit` · `enchant table` · `booster equipment separate` · `monster collection piece` · `emancipate group` · `default select auto job and growtype` · `grow type` · `recipe image type` · `charactor` · `trade limit` · `bead limited usable item` · `category`

---

## 4. `.chr`（角色，55 个；swordman 6 个）

### 4.1 解析规则（状态机，不能当树读）

`chr_scan.py` 的 `flatten()` + `build()`：

- `flatten(tokens) -> [Pair(label, values)]`：label token 开新键，int/float/str/val 归它。`[job] [swordman]` 里的 `[swordman]` 是 **str 不是 label**，所以方括号无二义性；`[physic]`/`[magic]` 才是真 label。
- **容器** = 文件里存在 `[/同名]` 的标签（`close_set` 动态推导，不硬编码），`[/x]` 关最近容器。
- **区域**（region）只由 `^(growtype|awakening) \d+$|^initial value$` 命中，`initial value`/`growtype N` = level 1，`awakening N` = level 2。
- `awakening` 区域里只允许 `awakening skill` / `pvp awakening skill`，其它标签出现就先关掉 level-2 区域（否则 `[awakening name]` 会错挂）。
- `TAIL_RE = motion( [\d-]+)?$ | info$ | ^weapon wav$` 命中时关掉所有区域（动作/攻击信息段回到顶层）。
- 浮点按 float32 最短表示 `%.7g`（`5.800000190734863` → `5.8`）。

### 4.2 结构（swordman.chr，1505 token / 355 label）

```
[job] [swordman]
[growtype name] ×6   <0::growtype_name_75/80/85/90/95/137>
[growtype name translation] ×6
[width] 40 10                                   ← X/Y 像素
[initial value]
  HP MAX 520 · MP MAX 480 · physical|magical attack 101.5|98.5
  physical|magical defense 101.5|98.5 · dark resistance 20 · light resistance -20
  inventory limit 48000 · MP regen speed 50 · move speed 850 · attack speed 850
  cast speed 700 · hit recovery 600 · jump power 430 · weight 50000 · jump speed 95
  [skill] …                                     ← 三元组容器
[growtype 1] … [growtype 6]
  属性增量（gt1: HP+55/MP+35/物攻+5.8/物防+5.8/魔攻+5.2/魔防+5.2/inventory+300/MPregen+2.5/hitrec+1.5）
  [skill] …  [module damage rate] 4 列（gt1 `0.95 1 1 0.1`、gt2 `0.7 1 1.1 0.05`…）
  [usable weapon sub type] (子类型, -1|33) ×N
  [pvp private create equipment list]（[weapon] id 0|1 分组）
  [pvp private recreate penaly period] 30
  [selectable awakening skill index] ×2 · [CHARACTER ATTACK TYPE] `[physic]|[magic]`
  [CHARACTER DAMAGE TYPE] power · [show skill] (id, N∈0..2) · [showskill level] 50
  [preset skill] id… · [awakening name]/[awakening name translation] ×3
  [awakening 1..3] → [awakening skill]/[pvp awakening skill] (id, 等级)
尾部（TAIL 标签逐段关区域）
  [waiting motion] Animation/Stay.ani …（36 条动作，victory motion 出现两次）
  [attack info]/[jumpattack info]/[dashattack info] .atk 路径
  [growtype attack info] (growtype, 索引, 路径) 三元组
  [weapon wav] ×6 · [weapon hit info] 六元组重复 · [weapon skill info] 24 数
  [upgrade weapon attack power rate] 12 数 · [body image path] …%04d.img
  [weapon durability decrease rate] 0.7 0.5 … · [create equipment list]
  [max grow count] 5 · [class change quest reward] … · [awakening quest reward] …
  [second awakening quest reward] … · [awakening skill Index] … · [sync skill level list] 4 元组
  音效名若干 · [limit slowdown attack|move speed] 10 · [create character button img offset]
  [attack x velocity|accel] …
```

`atswordman.chr` / `dsswordman.chr` 同构（job 分别是 `[at swordman]` / `[demonic swordman]`，后者只有 1 个 growtype）。`*customdata.chr` 只有 `[etc motion]`/`[etc attack info]` 两类硬编码调用，**顺序重要**。

### 4.3 `[skill]` 三元组（id, 等级, X）

- latest 是**三元组**（旧版是二元组，`analysis/02-character.md` 的说法已过时）；89 个 skill 容器 `len % 3 == 0` 全部成立。
- 第 2 位 = 等级（旧版 `179 7` 与新版 `(179,7,1)` 对齐）。
- 第 3 位 X 分布：`{1: 565, 15: 27, 5: 26, 10: 24, 25: 1}`。
- 与 `.skl [required level]` 比对 643 条：**437 条 X == required level**；206 条不等（这些 X 全为 1，而 skl required > 1）；0 条找不到 skl。
- X 随 growtype 变化（不是技能常量）：swordman 25 在 gt2/4/5 = 5、gt3 = 1；65 在 gt2 = 10、gt3/4 = 1、gt5 = 10。
- **实用规则**：`X <= 1` 视为「无额外学习要求」，否则当作「该 growtype 下的学习等级」。唯一反例：`character/thief/thief.chr` growtype5 的 skill 8（`Thief/Eraser.skl` required 15，chr 写 10）。
- `.skl` 表的选法：用 **basename** 拼 `<name>skill.lst` → `<name>.lst`（`atpriest.chr` 必须用 `atpriestskill.lst`，不能用目录名）。
- `[awakening skill]` / `[pvp awakening skill]` 是**二元组** (id, 等级)，与 `[skill]` 不同。

### 4.4 单位与机制

- `[inventory limit]` / `[weight]` = 10g；`[move speed]` 以 1000 为基准；`[width]` 是 X/Y 像素。
- `[growtype N]` 的 N **只是该 .chr 内部分支索引**，不代表转职顺序（tagdict 明确否定「growtype 1 = 转职前」）。
- `[module damage rate]`：PVP/战场/混沌模式伤害比率，可省略或写 0 = 继承上级（转职沿用转职前）；列数必须保留。
- `[body image path]` 是 ImagePacks2 的 printf 模板（`%04d`），不是 PVF 路径。
- 运行时换算：`move speed 850` → `850 × 0.26 = 221 px/s`（与 sf85 标定一致）。

---

## 5. 文件引用规则（`pvf_refs.py`）

- 扫子树里所有 `dtype == 1 && size % 5 == 0` 的文件，取 str/val 里形如 `x.<ext>` 的值当引用。
- **两种基准并存**（必须都试，命中即止并记录 `how`）：
  1. 相对引用者目录（`.ani.als` 的 `../Effect/...`，32,588 条）；
  2. 相对 PVF 根（`.skl` 的 `Character/Swordman/Effect/...`，2,312 条）。
  只按相对目录解析会把 2,367 条 skl→ani 误判为缺失。
- `.als` **全部无人显式引用** ⇒ 它是 `.ani` 的**同名旁挂文件**（`xxx.ani` ↔ `xxx.ani.als`），引擎按文件名配对。
- `.atk` 只被 `.chr` 引用（566 个里 548 被引）。
- `.img` 一律属于 ImagePacks2（PVF 里没有），不算缺失；`%04d` 模板归 npk/template。
- latest 的 `.ani` 解析：`[LOOP]` + `[FRAME MAX] n` + `[IMAGE PATH] … [/IMAGE PATH]`，每帧 `[FRAMEnnn]` 里 `[IMAGE EX] w h`、`[IMAGE POS] x y`、`[DELAY] ms`、`[DAMAGE BOX] 6×int`、可选 `[ATTACK BOX]/[DAMAGE TYPE]/[IMAGE ROTATE]/[GRAPHIC EFFECT]/[PLAY SOUND]`。
- `.als` 的 `[use animation]` 后是**两个 str**：先 `.ani` 路径，第二个是短标记（不是路径后缀，别拼接）。
- tagdict **没有 ani / als** 的条目（有 act 591 / equ 375 / stk 274 / chr 76 / atk 100 / map 89 / dgn 139）。

---

## 6. 未闭合项（下次从这里接着做）

1. `.stk` 32 个无官方释义高频字段的定名（见 §3.5）。
2. `[grade]` 的分域枚举还缺「每域档位含义」的官方名字（§3.3 只给出了域归属）。
3. `[skill]` 第 3 位：198 条 `X=1` 而 `skl required > 1` 的成因（疑与「该分支已拥有该技能」有关）；thief Eraser 那条反例。
4. 少数 `.ptl` 的标签是韩文乱码（如 `character/common/particle/3th_awake_gunner/musicnote.ptl` 的 `[坷宏璃飘]`），字符串池非 ASCII 编码偏差未定位（不影响路径解析）。
5. `.skl [skill fitness growtype]`（0 基白名单）与 `[skill]` 三元组的联动规则未验证。
