# DNF `.ani` v6 二进制格式规范（逆向）

> 状态：**已验证**（主结构 + 10 个字段 id 经正样本逐帧核对）；文件级前置区、尾部区、4.8% 变体仍为**待验证**。
> 实现：`tools/ani_parser.py`（`parse_ani(bytes) -> dict`，永不抛异常）。
> 数据基础：`export/text/**/*.ani.bin`（1,047,702 个文件，原样二进制）+ 知识库正样本账本
> `/mnt/e/dnf-sf/pvfUtility-v1.0.0-win-x64/Resources/AgentKnowledge/indexes/passiveobject-hitbox-ani-sample-ledger.zh-CN.md`。
> 本文所有结论都附「证据」行（路径 + 十六进制 / 统计数字）。标「待验证」的不要当结论用。

---

## 1. 一句话概览

`.ani` = 一个动作动画的**时间轴 + 逐帧判定盒 + 逐帧图像引用**。它不含像素，只按
`(图像文件, 该图像内帧号)` 引用 `.img`；**判定盒（攻击/受击）只存在于 .ani 里**，
`.act` 只引用 ani 路径与触发帧号（见 §8）。所以"机制仅通过 PVF 文本/二进制表达"这条链路里，
.ani 是**判定盒与时间轴的唯一承载者**，是战斗手感的核心数据。

```
文件 = header{frame_max, img_count, img_path[]}  +  prologue  +  frame × frame_max  +  trailing
帧   = n_head  + n_head×(u16 id, payload)  +  image_slot  +  (i32 x, i32 y)
       + n_tail + n_tail×(u16 id, payload)
```

---

## 2. 头部（已验证，全量 1,047,702 文件）

| 偏移 | 类型 | 含义 |
|---|---|---|
| 0 | u16 | `frame_max`：帧数，等于文本格式里的 `[FRAME MAX]` |
| 2 | u16 | `img_count`：引用图像路径个数（**可以是 0**） |
| 4 | `img_count` × (u32 len + char[len]) | 图像路径，**无 NUL 结尾**，`len` 即字符数 |

- 证据：`export/text/monster/casillas/animation/attack1.ani.bin`（384B）开头
  `06 00 | 01 00 | 22 00 00 00 | "Monster/Casillas/Body/casillas.img"` → frame_max=6, img_count=1, 路径长 34 字节。
- 全量统计（按上式解析，失败 866 个，其中 19 个是 0 字节空文件）：
  `frame_max` 分布 fc=1:97000, 4:85840, 5:100773, 6:88907 … 最大 1118；`img_count` 分布
  ic=1:27124 / 0:917 / 2:285 / 3:30 / 4:2（30k 抽样）。
- 大端？不是，全文件 **little-endian**。
- 带 `.bin` 后缀只是解包约定，内容就是原 PVF 里的字节。

## 3. 文件级前置区（prologue，**待验证**）

头部之后、第 1 帧之前有一段 0~12 字节的小结构，长度随文件变化：

| 长度 | 30k 抽样命中数 | 常见内容（hex） |
|---|---|---|
| 2 | 13430 | `00 00` |
| 5 | 8533 | `01 00 01 00 00` 或 `01 00 00 00 01` |
| 3 | 2405 | `01 00 01` |
| 8 | 1764 | `02 00 00 00 01 01 00 00` |
| 9 | 1206 | `02 00 01 00 00 1c 00 01 00` |
| 0 | 636 | — |
| 6 | 430 | `02 00 00 00 01 01` |
| 12 | 115 | — |

假设（待验证）：`[u16 nFileFields][(u16 id, 定宽值)×n]`，见过的文件级 id = `0x0000`、`0x0001`、`0x001c`(4B)。
**无法用"穷举起点恰好读到 EOF"来定它**（会过拟合，已试过：单文件能出 >20000 个"解"）。
因此解析器把 prologue 当成 0..12 的搜索参数，取「帧数正好 frame_max 且读到底」的那个 s；
这条信息本身不是解析目的，故标待验证不影响帧数据正确性。

## 4. 帧结构（**已验证**，见 §9 正样本）

| 顺序 | 类型 | 含义 |
|---|---|---|
| 1 | u16 `n_head` | 帧前字段个数（判定盒在这里） |
| 2 | `n_head` × (u16 id + payload) | 见 §5 字段表 |
| 3 | image_slot | `u16 0xFFFF` = 该帧无图像；否则 `u16 img_index, u16 img_frame` |
| 4 | i32 `x`, i32 `y` | `[IMAGE POS]`，相对角色原点 |
| 5 | u16 `n_tail` | 帧后字段个数 |
| 6 | `n_tail` × (u16 id + payload) | 见 §5 |

- `img_index` 是**头部 img_path 数组的下标**，`img_frame` 是该 `.img` 内的帧号 —— 这两个数才是渲染所需的全部信息。
- `n_head`/`n_tail` 上限按 64 处理（防坏文件）。

### 4.1 逐字节走查：`passiveobject/actionobject/monster/chiefmong/animation/boom.ani`（340B, fc=8, ic=1, body@53, body 287B）

```
0000  01 00 01 00 00 01 00 0f 00 e1 ff ff ff f6 ff ff
0010  ff 13 00 00 00 41 00 00 00 14 00 00 00 47 00 00
0020  00 00 00 00 00 bb ff ff ff 80 ff ff ff 02 00 0b
0030  00 02 00 0c 00 78 00 00 00 | 01 00 0f 00 e3 ff ff
...
0110  ff 80 ff ff ff 01 00 0c 00 78 00 00 00 00 00
```
第 0 帧：`01 00`(n_head=1) `0f 00`(ATTACK BOX) `e1ffffff f6ffffff 13000000 41000000 14000000 47000000`
= **(-31,-10,19,65,20,71)**；`00 00 00 00`(img=0, frame=0) `bbffffff`(x=-69) `80ffffff`(y=-128)
`02 00`(n_tail=2) `0b 00 02 00`(GRAPHIC EFFECT 类=2) `0c 00 78000000`(DELAY=120)。
该盒六值与知识库正样本 `FRAME000 [ATTACK BOX] -31 -10 19 65 20 71` **完全一致**；
8 帧字节数 52+52+52+26+26+26+26+20 = 287，加 prologue 5 与 trailing 2 正好闭合。

### 4.2 无图像帧同样有判定盒

`passiveobject/common/animation/noneexplosion.ani`（56B, fc=1, **ic=0**）body：
```
0000  01 00 01 00 00 01 00 0f 00 bf ff ff ff d3 ff ff
0010  ff ce ff ff ff 82 00 00 00 5a 00 00 00 64 00 00
0020  00 ff ff 00 00 00 00 00 00 00 00 01 00 0c 00 90
0030  01 00 00 00
```
`0f 00` 盒 = **(-65,-45,-50,130,90,100)**（= 正样本 `FRAME000 [ATTACK BOX] -65 -45 -50 130 90 100`）；
image_slot = `ff ff`（无图像）。⇒ `img_count=0` 的文件是合法的，**空图帧依然承载攻击盒**。

## 5. 字段 id 表

「size」= payload 字节数；证据一栏是核对方式。

| id | size | 字段 | 解码 | 证据 / 置信度 |
|---|---|---|---|---|
| 0x07 | 8 | `[IMAGE RATE]` | 2×float | 实测 0.5/0.6 等合理值；出现率 105,750/312,300 帧 ✅ |
| 0x08 | 4 | `[IMAGE ROTATE]` | 1×float | 角度值合理 ✅ |
| 0x09 | 4 | `[RGBA]` | 4×u8 | `ff ff ff 00` / `ff ff ff aa` 形态 ✅ |
| 0x0A | 1 | `[INTERPOLATION]` | u8 0/1 | 值域 0/1（1505:37）✅ |
| 0x0B | 2 | `[GRAPHIC EFFECT]`? | u16 枚举 | 出现率 34% ≈ 账本 32%；**但取值 99.7% 为 2**，与「NONE/DODGE/LINEARDODGE…」语义不符 → **语义待验证**（长度与位置已定，解成原值保留在 `value.enum`） |
| 0x0C | 4 | `[DELAY]` | u32 毫秒 | 铁证：单帧文件末尾 `0c 00 32 00 00 00` = 50ms，与文本格式一致 ✅ |
| 0x0D | 2 | `[DAMAGE TYPE]` | u16 枚举 0/1/2 | 值域 0:NORMAL 2388 / 1:SUPERARMOR 544 / 2:UNBREAKABLE 16，符合枚举 ✅ |
| 0x0E | 24 | `[DAMAGE BOX]` | 6×i32 | **三处正样本核对通过**（见 §9.2）✅ |
| 0x0F | 24 | `[ATTACK BOX]` | 6×i32 | **五处正样本逐值相等**（§9.1）✅ |
| 0x10 | 4+len | 字符串字段（`[PLAY SOUND]` 类） | u32 长度 + ASCII | 实测 `10 00 | 14 00 00 00 | "R_DL_DEMONIC_INFERNO"`（`character/demoniclancer/animation/diatkb_bodyb.ani.bin`，长度 0x14=20 字符）✅ 长度与形态已定、字段名待验证 |
| 0x17 | 4 | `[FLAG]` **flagIndex** | i32（作者自定义整数） | **已定案**（`analysis/11-P0-BLOCKERS.md` ①）：`dashattack.ani` 5 帧 = `[—,100,—,1,101]`、`after_threesideex.ani` 帧 2 = 3，与 `.nut`/`.act` 脚本实参**逐值相等**；出现率 9.6% 文件（2,881/30,000 抽样），8,379 次出现**全部恰好 4 字节** ✅ |
| 0x00/0x01/0x02/0x03/0x05/0x12/0x18/0xFFFF | — | 未定 | — | 只出现在 4.8% 变体文件里（§10.3）⚠️ |

盒六元组语义 = **(相对X, 相对Y, 相对Z, 宽, 高, 深)**（与文本格式 `[ATTACK BOX]` 的 6 个 int 一致；
`/mnt/e/dnf-sf/pvfUtility-.../Resources/OfficialAnnotationTranslation/animation.ani.txt` 也按此顺序列出）。

## 6. 文本格式 ↔ 二进制对照

pvfUtility 官方注释 `OfficialAnnotationTranslation/animation.ani.txt` 给出字段顺序：
`[LOOP] [SHADOW] [FRAME MAX] [SPECTRUM…]` → 逐帧 `[IMAGE] [IMAGE POS] [IMAGE RATE] [IMAGE ROTATE] [RGBA]
[INTERPOLATION] [GRAPHIC EFFECT] [DELAY] [DAMAGE TYPE] [ATTACK BOX] [PLAY SOUND] [FLIP TYPE] [SET FLAG] [CLIP]`。
二进制里这个顺序被「id+payload」取代，且**文件级 [LOOP]/[SHADOW] 没有以 id 形式出现**——
它们很可能就藏在 §3 的 prologue 里（`01 00 01 00 00` 的两个 1 很像 LOOP=1/SHADOW=1），**待验证**。
`[FLIP TYPE]`/`[CLIP]`/`[SET FLAG]`/`[SPECTRUM*]` 在解析结果里尚未找到对应 id。

## 7. 帧表（中间产物契约，P0.5 → P0.6 → Godot）

**不做「一帧一个文件」导出**：Godot 4.7.2 实测导入 5000 张 32s / 20000 张 5min（超线性），
106 万 ani 上千万帧必爆。改为给每个 `.ani` 产出一条记录（JSONL 一行），帧数组内联：

```json
{"src":"monster/casillas/animation/attack1.ani",
 "ani_frames":6,
 "images":["Monster/Casillas/Body/casillas.img"],
 "total_ms":780,
 "clean":true,
 "frames":[
   {"i":0,"x":-220,"y":-294,"d":80,"t":0,
    "img":[["Monster/Casillas/Body/casillas.img",12]],
    "ab":[],
    "db":[[-28,-7,0,58,14,152]],
    "flag":null,
    "fx":{"rate":null,"rot":null,"rgba":null,"gfx":null,"interp":null,"dmgtype":null}}
 ]}
```

（上面是真机输出：casillas 普攻第 0 帧 delay=80ms、引用 `casillas.img` 的第 12 帧、
受击盒恒为 `[-28,-7,0,58,14,152]`、该帧没有攻击盒；攻击盒只在带 `0f 00` 的帧出现。）

字段说明：

| 键 | 含义 |
|---|---|
| `src` | ani 在 PVF 内的路径（导出时去掉 `.bin`） |
| `ani_frames` | 声明帧数（= `[FRAME MAX]`） |
| `images` | 该 ani 引用的 `.img` 路径数组（下标 = `img[0]`） |
| `total_ms` | `Σ delay`，整段动画时长 |
| `frames[].i` | 帧号 |
| `frames[].x/y` | `[IMAGE POS]` |
| `frames[].d` | `[DELAY]` 毫秒 |
| `frames[].t` | 该帧起始时间（前缀和，运行时直接拿去比对） |
| `frames[].img` | `[[img路径, img 内帧号]]`；空数组 = 该帧无图像 |
| `frames[].ab` / `db` | 攻击盒 / 受击盒列表，每个 6 个 int |
| `frames[].flag` | `[FLAG]` flagIndex（i32）；缺省 = 该帧无 flag 事件，运行时不该触发回调 |
| `frames[].fx` | 图像速率/旋转/RGBA/GRAPHIC EFFECT/INTERPOLATION/DAMAGE TYPE 原值 |

**矩形裁剪交给 P0.6**：帧表只保留「img 路径 + img 内帧号」，P0.6 把 `.img` 打成 2048² 图集后，
运行时用 `Sprite2D.region_rect` 切；判定盒直接用 `ab`/`db` 建 `Area2D` 的 `CollisionShape2D`。
CLI（`analysis/ani/export_ani_tables.py`）：

```bash
.venv/bin/python analysis/ani/export_ani_tables.py --samples        # 5 个样例 JSON
.venv/bin/python analysis/ani/export_ani_tables.py --prefix monster/ --out analysis/ani/monster_frames.jsonl
.venv/bin/python analysis/ani/export_ani_tables.py --glob 'export/text/**/*.ani.bin' --stats
```

## 8. 与宿主 `.act` / `.atk` 的关系

- `.act` = `[MOTION][BASE ANI] ../Animation/Boom.ani [SUB ANI] ...` + `[TRIGGER][FRAME] 7 7` + `[BEHAVIOR]` 行为块。
  它**只引用 ani 路径与帧号**，不复制 ani 内的判定盒 → 判定盒的唯一来源是 .ani。
- 证据：`export/text/passiveobject/actionobject/monster/chiefmong/action/boom.act.txt` 引用
  `[BASE ANI] ../Animation/Boom.ani`、`[FRAME] 7 7`；对应 boom.ani 有 8 帧（0..7）→ 触发帧在末帧，自洽。
- `passiveobject/actionobject/monster/powerstation/kohlepowerstation/slime/action/boom.act.txt` `[FRAME] 10 10`
  对应 boom01.ani 11 帧（0..10）→ 同样落在末帧。

## 9. 校验数据

### 9.1 攻击盒正样本 5/5 逐值相等（知识库账本 → 本解析器）

| ani | 帧数 | 账本给的 [ATTACK BOX] | 解析结果 |
|---|---|---|---|
| `passiveobject/actionobject/monster/chiefmong/animation/boom.ani` | 8 | f0 `-31 -10 19 65 20 71`；f1 `-29 -10 17 60 20 68`；f2 `-27 -10 12 68 20 84`；f3-7 无 | 全等 ✅ |
| `.../kohlepowerstation/slime/animation/boom01.ani` | 11 | f0-3 `-118 -19 -91 228 38 199`；f4-10 无 | 全等 ✅ |
| `.../timegate/conflagration/umtara/animation/boom_dodge.ani` | 10 | f0-7 `-82 -10 -71 169 20 150`；f8-9 无 | 全等 ✅ |
| `passiveobject/actionobject/spc/_firewitch/ador/animation/body.ani` | 4 | f0-3 `-46 -19 -10 69 38 48` | 全等 ✅ |
| `passiveobject/common/animation/noneexplosion.ani` | 1 | f0 `-65 -45 -50 130 90 100`（空图帧） | 全等 ✅ |

### 9.2 伤害盒正样本 3/3（**这是 0x0E = [DAMAGE BOX] 的决定性证据**）

| ani | 账本描述 | 解析结果 |
|---|---|---|
| `passiveobject/actionobject/monster/timegate/timelord/animation/chain/1chain_start.ani` | `[ATTACK BOX]` 在 FRAME001–004，`[DAMAGE BOX]` 在 FRAME000–006 | 7 帧全部有 db；ab 只在 f1,f2,f3,f4 ✅ **帧号集合完全一致** |
| `passiveobject/actionobject/spc/_cannontrap/animation/stay.ani` | 观察到 `[DAMAGE BOX]` | f0 db=1 `[-59,-23,-13,144,46,81]` ✅ |
| `passiveobject/actionobject/spc/_cannontrap/animation/attack.ani` | 观察到 `[DAMAGE BOX]` | 4 帧全部 db=1（同盒）✅ |

### 9.3 规模校验（seed=2024 随机 30,000 个 ani）

- **clean = 28,505 / 30,000 = 95.02%**（读到底、无残留、帧数 == frame_max、无未知 id）
- fail = 1,435（4.8%，多为 avatar 类变体，见 §10.3）；dirty = 60（0.20%，读完但尾部残留 1~4 个 0 字节）
- 解析出 308,342 帧、**5,098 个攻击盒、18,141 个伤害盒**；2,881 个文件（9.6%）含 flagIndex，
  其中 0x17 出现 8,379 次、**全部恰好 4 字节**；耗时约 13s（≈0.43 ms/文件）
- 字段出现次数（v1 口径同批）：0x0c 313,339 / 0x0b 107,920 / 0x07 106,742 / 0x09 98,968 / 0x08 44,332 /
  0x0d 28,281 / 0x0e 16,404 / 0x0a 15,208 / 0x0f 5,091 / 0x10 354
  → 「**每帧必有 DELAY(0x0c)**」（313,339/315,151 = 99.4%），与账本 `[DELAY] 1,041,665 / 1,046,502 帧`(99.5%) 吻合。
- 尾部残留长度分布：0:6956 / 1:7476 / 2:6738 / 3:7332 / 6:9 / 7:6（恒为全零字节）。

## 10. 未定项 / 待验证

1. **prologue 结构**（§3）：长度已实测，语义未定；`[LOOP]`/`[SHADOW]` 应在其中。
2. **trailing**：0~3 个全零字节最常见，但见过 6/7 个；是 padding 还是尾部文件级字段未定。
3. **4.6% 变体帧文法**（48,651 个失败）：集中在 `equipment/character/**` 的 avatar 动画（avatar 装备动画），
   特征 = 帧前缀比标准模型多 1 字节、或图像槽宽度不同；未知 id 0x00/0x01/0x12。
   对 0x00/0x01/0x12 穷举 payload 长度只能救活 2/277 个文件 ⇒ 是**文法变体**而非字段长度问题。
4. **0x0B 的语义**：长度=2、位置在 ATTACK BOX 之后很稳定，但取值 99.7% 是 2，
   与 GRAPHIC EFFECT 枚举不符 → 暂按原值输出，名字标待验证。
5. ~~**0x17**：4~6 字节、值域 0..7，语义待验证~~ → **已定案，早期版本这条是错的**：
   `0x17` = `[FLAG]` **flagIndex**，**i32 小端整数**（不是「4~6B 未知字段」，也不是「值域 0..7」）。
   语义 = 该帧的「关键帧 flag」，等同于脚本里传给 `sq_SetCurrentAnimation` 的 flag 实参；
   作者自定义整数，小值占多数所以早期只用少数样本看时误以为值域 0..7（实测见过 100/101）。
   证据：`analysis/11-P0-BLOCKERS.md` ①（archivist 用 `.nut` 实参逐值对照：
   `character/swordman/atanimation/dashattack.ani` 5 帧 = `[—,100,—,1,101]`、
   `after_threesideex.ani` 帧 2 = 3）。解析器按 4 字节优先 `_profiles()`，30,000 抽样里
   8,379 次 0x17 **无一是长 payload**；早期「profile 优先 6 字节」的写法已改为 4 字节优先。
   **注意副作用（实测）**：改成 4 字节优先后全量 ok 从 95.161% 升到 95.356%（+2,052 个文件），
   因为只有按真实宽度切分，后续帧才能继续闭合——所以 §9.4 的数字是重跑后的 v2 口径。
   帧表里该字段输出为 `flag`（见 §7）。
   遗留：`0x0b`（2B）与 `0x17` 是否互斥**尚未验证**（见 `analysis/ani/QUALITY.md` §10）。
6. **`[FLIP TYPE]` / `[CLIP]` / `[SET FLAG]` / `[SPECTRUM*]`** 的二进制 id 未定位（出现率低，合计 < 0.2%）。
7. **[PLAY SOUND] 是否就是 0x10**：长度前缀形态已确认，字段名待验证。
8. 账本 `[DAMAGE BOX]` 出现率（31.8% 帧）远高于本样本（4.9%），推测差异来自
   ① 账本样本偏向怪物/被动对象（盒多）② 部分盒密集文件落在失败集合里 → 待大盘重算。

## 11. 复现

```bash
# 单文件看结构
.venv/bin/python tools/ani_parser.py export/text/monster/casillas/animation/attack1.ani.bin
.venv/bin/python tools/ani_parser.py --json <ani.bin>     # 完整 JSON

# 全量统计 / 帧表导出
.venv/bin/python analysis/ani/export_ani_tables.py --glob 'export/text/**/*.ani.bin' --stats
.venv/bin/python analysis/ani/export_ani_tables.py --prefix monster/casillas/ --out analysis/ani/casillas_frames.jsonl
```

解析器策略（`tools/ani_parser.py`）：**两轮**
① 固定字段表 × prologue 0..12 的严格试解（要求帧数==frame_max 且读到底；不猜长度）；
② 失败才退回回溯试解（未知 id 按「u16 长度字符串」→ 候选定长依次尝试，带节点预算）。
坏文件永远返回 `{ok:false, error:…}`，不抛异常。

### 9.4 全量 1,047,702 个 ani 校验（t8 v2，2026-10-26；`0x17`=flagIndex 定案后重跑）

| 指标 | 数值 |
|---|---|
| 文件总数 | 1,047,702 |
| ok（帧数 == FRAME MAX 且帧结构自洽） | 999,051 = **95.356%** |
| ├ clean（读到 EOF 无残留） | 996,948 = 95.156% |
| └ dirty（尾部残留 1~3 个 0 字节） | 2,103 = 0.201% |
| fail | 48,651 = 4.644%（863 个 0 字节文件 + 3 个头部截断 + 其余为帧前导宽度变体） |
| 帧总数 | 10,947,930（平均 10.95 帧/动画，最大 1,118 帧） |
| 含攻击盒的 ani | 24,026（占 ok 的 2.40%），攻击盒帧 127,277 |
| 含伤害盒的 ani | 51,526（占 ok 的 5.16%），伤害盒帧 418,928 |
| **含 flagIndex 的 ani** | **104,008（占 ok 的 10.41%）** |

按根目录 / 职业 / 版本的分列、失败样本表与 hex 证据、`.img` 悬空率说明，见
`analysis/ani/QUALITY.md`；数据集用法见 `analysis/ani/READ-EXAMPLE.md`。
