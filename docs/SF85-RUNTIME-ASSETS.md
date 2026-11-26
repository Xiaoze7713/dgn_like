# 运行时资产链路（PVF + NPK → 场景，零中间文件）

> 目标：从 `Script.pvf` 直接起一个能跑的场景，不再预导出 PNG / JSON。
> 代码：`utils/npk/*`（NPK 读取）+ `game/sf85/*`（语义组装）。

## 1. 数据从哪来

| 数据 | 位置 | 谁读 |
| --- | --- | --- |
| 动画 | `*.ani`（PVF 文本） | `Sf85Pvf.animation()` |
| 角色外观 | `avatar/<part>/*.equ`（`[variation]` look/color + `[layer variation]` z/目录） | `Sf85Pvf.equ_layers()` |
| 武器 | `weapon/<wtype>/*.equ`，图集模板在 `weapon/<wtype>/<lay>/<motion>.ani` 的 `sprites` | `Sf85Pvf.weapon_layers()` |
| 怪物 | `monster/*.mob`（`[waiting motion]` 等指向同目录的 `.ani`） | `Sf85Pvf.build_monster()` |
| 房间 | `map/<dungeon>/<room>.map` + `tile/*.til` | `Sf85Pvf.build_room()` |
| 像素 | `ImagePacks2/*.NPK` 里的 `.img` | `NpkStore.texture()` |

一张 `.img` 的帧 = 一段像素 + 一个落位 `(img.x, img.y)`；`.ani` 的帧 = 图集路径 +
帧号 + 偏移 `(ani.x, ani.y)`。**两者相加才是屏上坐标**：

```
draw_x = ani.x + img.x
draw_y = ani.y + img.y
```

（这条公式是这次修 bug 的核心：只加 ani 偏移会出现"衣服飘在头顶、身体只剩腿"。）

## 2. .map 的四个坑（都实测过）

**① `[tile]` 的 8 条 = 房间从左到右的 8 个竖直切片，不是 8 个图层。**

```ini
[tile]
    Tile/ForestOver.til ×4  Tile/ForestOverUnder.til  Tile/ForestUnder.til ×3
```

每条 `.til` 都是一张 **224 宽 × 480 高**的整幅切片（只带一个 `[IMAGE]` + 一张 14×30 的通行表），
按 `x = 序号 × 224` 并排摆；房间宽度 = `8 × 224 = 1792`。
不同切片用不同的 `.til` 是地图作者做纵深/材质变化的方式（`forestover` 深林、
`forestunder` 浅草、`forestoverunder` 过渡），**不能当成图层横向重复铺**——
那样会把三种图叠在一起，接缝处出现横向色带。

三张图的内容高度不同（235 / 233 / 203），但都**底对齐到 y=480**（IMG 帧自带的 y 偏移
分别是 245 / 247 / 277，`245+235 = 247+233 = 277+203 = 480`），所以并排后顶部透明区
会露出后面的远景动画。

**② `[background animation]` 的 `[layer]` 值带方括号**（`[distantback]`），
不去掉就匹配不上 z 映射表，会退到默认 `z=-30`——比地板（`z=-50`）还高，
远景会把地板的草整片盖住（表现为「人物站在一条暗色带上」）。正确 z 序：
`distantback=-100`、`middleback=-90`、`nearback=-80`，地板 `-50`。

**③ `[monster]` 每 8 个整数一组**，但 `attrs` 里会混进 `[fixed]` / `[normal]`
这类空段名（字符串），必须先滤掉非数字再分组：

```
id, count, ?, x, y, ?, ?, ?
```

n201 的 7 只：`4@(796,202) 10@(961,218) 1@(1259,221) 3@(1321,251) 1@(1210,266) 1@(717,299) 2@(896,304)`。

**④ `monster/monster.lst` 的路径相对 `monster/`** —— 要补前缀才找得到 `.mob`
（`goblin/hillgab.mob` → `monster/goblin/hillgab.mob`）。

## 3. 通行表与「地面 53px」偏移

`.til` 的 `[pass type]` 是 420 个整数（14 列 × 30 行，格 16 px），**0 = 可走，2 = 墙/天空**，
行序**从上往下**。每个 224 宽的切片带一张表，8 片拼成 112×30 的全局格；`Room.is_walkable(pos)` 查这张表。

**地面偏移 `GROUND_Y = 53`（`room.gd:36`）**：地图坐标和地贴图的像素坐标差了 53 px——
`[pass type]` 的可走带从第 12 行（y=192）开始，而 `.til` 的草地内容从 y=245 才开始
（`02tile03` 帧偏移 245、`02tile00` 277、`02tile02` 247，三者都底对齐到 480）。
不补偿的话人物会悬在草地之上 53 px。所以：**角色落位 = 地图 y + 53**、
**通行查询 = 查 (y − 53) 那一行**。三张地贴图的平均亮度几乎相同（44.8~46.1），
所以列与列之间看到的「色带」不是亮度差，而是不同 `.til` 的图案本身不横向可平铺
（`02tile03` 左右边缘 40/59 个采样点不一致），属源数据特性。

## 4. 怎么跑

```bash
# 首次/新增脚本后：让编辑器扫一遍（否则 res:// 找不到新文件）
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --editor --quit

# 逻辑探针（不开窗口）
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=/mnt/e/godot_proj/dnf_like \
  ./tools/godot.sh --headless --script res://tests/probe_mirkwood.gd

# 逐帧出图（自动驾驶：走 → 跳 → 三连击 → 上挑）
mkdir -p /tmp/mv && SF85_DEMO=1 ... \
  ./tools/godot.sh --write-movie /tmp/mv/f.png --quit-after 260 res://scenes/sf85_mirkwood.tscn
```

编辑器里直接 **F5** 也行（`run/main_scene` 已指向 `scenes/sf85_mirkwood.tscn`）。

决斗模式加 `SF85_DUEL=1`：玩家直接站到第一只怪身前，每 60 帧劈一刀（截判定盒的图用）。

> ⚠️ **`--write-movie` 不能配 `--headless`**：dummy 渲染器会崩在
> `Parameter "t" is null. at: texture_2d_get(./servers/rendering/dummy/storage/texture_storage.h:110)`。
> `tools/godot.sh` 会自动设 `DISPLAY=:0` 走 WSLg。

### 路径配置

**PVF**：`SF85_PVF` 环境变量 > 项目设置 `sf85/pvf` > `res://assets/sf85/Script.utf8.pvf`
> `/home/sunmingze/dnf_like/build/sf85.Script.utf8.pvf` > `E:/dnf-sf/...` > `/mnt/e/dnf-sf/...`

> 已把转好 UTF-8 的 85 包拷进 `assets/sf85/Script.utf8.pvf`（209 MB），
> 所以 Windows 上直接 F5 就能跑，不依赖 WSL 路径。

**NPK 目录**：`DNF_NPK_DIR` 环境变量 > 项目设置 `npk/base_dir` > 平台默认
（见 `utils/npk/README.md`）。索引里只存相对包名，所以同一份 `assets/npk-index.bin`
Windows / WSL 通用。

## 5. 实测数字

| 项 | 值 |
| --- | --- |
| 场景启动（PVF 打开 + 6 角色 + 27 贴图） | **3.6 s** |
| 索引加载 | 14 ms |
| 单帧 IMG 解码 | 1~3 ms |
| 单帧渲染耗时 | 1.7 ms |
| 贴图缓存 | 800 张 / 包句柄 12 个 |
| 索引 | 137,471 条 / 4,085 包 / 2.9 MB |

## 6. 打击判定 / 数值从哪来（全部读源文件）

> 2026-11-14 改版：一开始的「70×60 兜底盒 + 写死伤害」已全部删掉，现在每个数字都能追到 PVF 里的一个字段。
> 对应探针：`tests/probe_combat.gd`、`tests/probe_skill.gd`、`tests/probe_duel.gd`。

### 6.1 攻击盒在武器层，不在身体层

`character/swordman/animation/weaponcomboshort1.ani` 的 6 帧**一个 attack box 都没有**，
真正的判定盒在武器层：
`equipment/character/swordman/weapon/ssword/sswdc/weaponcomboshort1.ani` 第 2 帧
= `[15, -12, 44, 104, 25, 59]`。
武器层目录名来自 `.equ` 的 `[layer variation]`（当前装备是 `sswdc`）。

盒六元组语义（`docs/ANI-FORMAT.md:123` 已逐值验证）：**(相对X, 相对Y, 相对Z, 宽, 高, 深)**。
所以 `actor_sprite.gd:boxes()` 必须**跨层收集**（遍历所有图层，各取当前帧的 `attack_boxes`），
只读身体层会永远是空数组——这就是之前不得不造兜底盒的原因。

实测（三连击，玩家在 x=753.5，脚底 y=202）：

| 段 | 帧 | 判定盒（世界坐标 P / 尺寸 S） |
| --- | --- | --- |
| weaponcomboshort1 | 2 | `P(768.5, 190.0) S(104, 25)` |
| weaponcomboshort2 | 3 | 剑尖扫过的一帧，宽 104 |

### 6.2 数值来源表

| 运行时字段 | 源文件 / 字段 | 实测值 | 换算 |
| --- | --- | --- | --- |
| `hp_max` / `mp_max` | `.chr [ability category][hp max]` / `[mp max]` | 180 / 140 | 直接用（只有一个 growtype 表） |
| `attack_power` | `.chr [physical attack]` + 武器 `.equ` 物理攻击 | 7.5 + 543 = **550.5** | 直接用 |
| `speed` | `.chr [move speed] 850` | 850 → 221 px/s | `SPEED_SCALE 0.26` |
| 跳跃初速 | `.chr [jump power] 430` | 430 → 330 px/s | `JUMP_SCALE 0.767`（按跳跃高度反推） |
| 重力 | 源里没有 | 1100 px/s² | 由「跳跃力 430 对应约 44 px 抬升」标定 |
| 单段伤害 | `.atk [damage bonus]` × 面板 | 1 段 −15%、2 段 0%、3 段 +20% | `面板 × 倍率 × (1+bonus/100) × 0.03` |
| 击退 | `.atk [push aside]` | 30 / 30 / 40 | `× PUSH_SCALE 0.4` → 12/12/16 px |
| 挑飞 | `.atk [attack direction]` 含 `hit lift up` | 1、2 段无、3 段有 | `launch = direction.contains("lift up")` |
| 受击反应 | `.atk [damage reaction]` | `damage` / `down` | 决定播 `damage.ani` 还是 `down.ani` |
| 上挑消耗/冷却 | `.skl [consume mp] 6` / `[cool time] 2000` | MP 140→134、2 s | 直接用毫秒 |
| 上挑倍率 | `.skl [static data][0]` | 100% | `面板 × 1.0 × 0.03` = 16.5 两段 |
| 怪物血量 | `.mob [ability category][hp max]` 分类倍率 70 | 70 → 60 血 | `HP_SCALE 0.6`（70 倍率 ≈ 一把普攻 4 下打死） |
| 怪物移速/视野/攻速 | `.mob [move speed] 300` / `[sight] 300` / `[attack delay] 3000` | 104 px/s、300、3.0 s | 移速同 `SPEED_SCALE 0.26` |
| 怪物碰撞宽 | `.mob [width] 40 10` | 40 | 直接用（和 `.chr` 同名字段同语义） |

`.mob` 里**没有攻击力字段**（引擎按等级表算），所以怪物打到玩家目前仍是占位值
`monster.gd:ATTACK_DAMAGE 6.0`——这是已知缺口，见 §7。

### 6.3 碰撞

`[width] 40 10` 是「宽 × 深」，用作身体碰撞：
`room.gd:_physics_process` 里把玩家和怪物的 x 按 `(w1+w2)*0.5` 挤开，
`actor_sprite.gd:body_rect()` 给出 `Rect2(x-w/2, y-h, w, h)`（脚底为原点向上画）。

`F1` 打开调试层能看到全部判定：蓝框=攻击盒、黄框=玩家受击体积、绿框=怪物受击体积、红条=怪物血量。

## 7. 还没做

- 怪物 → 玩家的伤害：`.mob` 没有攻击力字段，现在是占位 6.0。
- 怪物 `[equipment]`（哥布林手里的武器/盾）没叠层。
- `[animation]` 装饰物只取第 0 帧，不播动画。
- 上挑（Z）暂时借用 `attack2` 的动画（`upperslash` 只有 `.skl`/`.atk`，没有专属 `.ani`）。
- 角色跳跃是脚本位移（`visual_offset`），不是动画自带位移。
- 天空/远景背景（`.map [background animation]` 里的 `far0.ani`/`mid1.ani`）还没接。
