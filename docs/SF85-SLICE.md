# sf85 垂直切片：幽暗密林一个房间

目标：验证「DNF 的资产能不能按原样搬到 Godot 里跑」——不是做游戏，是把
`Script.pvf` + `ImagePacks2` 里的东西原封不动变成一个能走、能砍、有怪的场景。

数据源全部来自 85 版客户端：

| 项 | 路径 |
| --- | --- |
| 脚本包 | `/mnt/e/dnf-sf/sf85/老牛DNF客户端/Script.pvf`（205,695,984 B / 370,666 条） |
| 转码后的包 | `build/sf85.Script.utf8.pvf`（209,076,192 B，中文可直接读） |
| 图包 | `/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2`（8.7 GB / 4,085 个 NPK） |

## 1. 三段式：索引 → 导出 → 运行时

```
ImagePacks2 (4085 NPK)          Script.pvf (370,666 条)
        │                              │
        ├─ npk-index.jsonl.gz ─┐       │
        │   137,471 条 img     │       │
        │   {"p","npk","o","s"}│       │
        │                      ▼       ▼
        └────────────► tools/sf85_export.py
                              │
                              ▼
              assets/sf85/{png/*.png, index.json}
                              │
                              ▼
                  Godot: Sf85Assets → 房间/角色
```

### 1.1 图包索引（一次，9.4 秒）

```bash
python3 tools/mk_npk_index.py        # 产出 analysis/sf85/npk-index.jsonl.gz（1.79 MB）
```

只读每个 NPK 的 16 B magic、u32 条目数、每项 264 B（`i32 offset, i32 size, 256 B XOR 名字`），
不解任何图像。137,471 条 `img` 全部登记。

> 包内的名字一律带 `sprite/` 前缀（`sprite/character/...`），PVF 里引用时不带，查表要补。

### 1.2 导出器（一次，2.3 秒 / 一个房间）

```bash
python3 tools/sf85_export.py \
  --room map/mirkwood/n201.map \
  --weapon equipment/character/swordman/weapon/ssword/sswd_shockwave.equ \
  --out client/assets/sf85
```

它做的事：

| 输入 | 解析 | 输出 |
| --- | --- | --- |
| `.ani` | 帧的 `path` / `img_param`(帧号) / `x` / `y` / `delay` / `attack_box` / `damage_box` | 每帧 `{png, w, h, x, y, delay, boxes}`，`x = ani.x + img.x`、`y = ani.y + img.y` |
| `.equ` | `[variation]` look/color + `[layer variation]` z/层目录 | 图集路径 `sm_<part><look:02d><color:02d><后缀>.img` |
| 武器 `.equ` | 同上；并自动补同级 `sswdb`（刀身，z=650）与 `sswdc`（刀光，z=2790）两层 | 7 层玩家 |
| `.mob` | `[waiting motion]`/`[move motion]`/`[attack motion]`/… | 怪物动作表 |
| `.map` | `[tile]`×8、`[monster]`、`[background animation]`、`[animation]` 装饰 | 房间地板 / 怪物落位 / 远景 / 花草 |
| `.til` | `[image]` img+帧号、`[pass type]` 420 格 | 224×480 地板分片 + 通行表 |

产物（当前）：

- `png/f_*.png` 564 张 + `png/rooms/*.png` 8 张
- `index.json` 88,500 B

`index.json` 形状：

```jsonc
{
  "actors": {
    "player": {"layers": [
      {"name": "skin",        "z": 0,    "anims": {"stay": {"frames": [...], "loop": true, "total_ms": 720}}},
      {"name": "shoes_shoes_a","z": 1400, "anims": {...}},
      {"name": "weapon_sswdb","z": 650,  "anims": {...}}
    ]},
    "monster/goblin/goblin.mob": {"name": "哥布林", "layers": [{"name": "body", "z": 0, "anims": {...}}]},
    "bg:far0":  {"layers": [{"name": "back", "anims": {"stay": {"frames": [...]}}}]},
    "deco:flower2@711,318": {...}
  },
  "rooms": {
    "map/mirkwood/n201.map": {
      "tiles": [{"png": "png/rooms/n201_0.png", "w": 224, "h": 480, "cell_x": 0, "ix": 0, "iy": 245}],
      "pass":  [[420 个 0/2] × 8],
      "monsters": [{"mob": "monster/goblin/goblin.mob", "x": 1259, "y": 221, "count": 1}],
      "backgrounds": [{"actor": "bg:far0", "layer": "distantback", "order": "below"}],
      "decos": [{"actor": "deco:flower2@711,318", "layer": "normal", "x": 711, "y": 318, "order": 0}],
      "width": 1792, "height": 480
    }
  }
}
```

## 2. 运行时：按需加载

Godot 侧三个文件，都在 `game/sf85/`：

| 文件 | 职责 |
| --- | --- |
| `asset_lib.gd`（`Sf85Assets`） | 读 `index.json`；`activate_room(id)` **只把该房间的贴图读进来**；`texture(rel)` 缓存 `ImageTexture` |
| `actor_sprite.gd`（`Sf85Actor`） | 一层一个 `Sprite2D`（`centered=false`，`z_index = z/100`）；按 `delay` 推进帧；`boxes(kind)` 取判定盒 |
| `player.gd` / `monster.gd` | 状态机（idle/move/jump/attack/skill；idle→chase→attack→hit→down→dead） |
| `room.gd` | 把上面拼起来：地板、远景、装饰、怪物、玩家、相机、HUD |

**「副本没用到就不加载」** 的落点：

1. 冷启动只读 `index.json`（88 KB），不碰任何 PNG；
2. `activate_room(id)` 才把该房间的 8 张地板分片 + 该房间用到的 actors 贴图读进来；
3. 房间之间不共享的贴图不会被上一个房间拖着；
4. 真正的 DNF 整包（8.7 GB）在运行时**一次都不打开**——NPK 的解包已经提前在导出阶段做完。

也就是说：运行时完全不依赖 `Script.pvf` 和 `ImagePacks2`，只依赖 `assets/sf85/`
（当前一个房间 1.4 MB）。想加房间就再跑一次导出器。

## 3. 场景与键位

`scenes/sf85_mirkwood.tscn` → `game/sf85/room.gd`

```
Room(Node2D)
 ├ Tiles      地板 8 片 + 远景 + [bottom] 装饰
 ├ Actors(y_sort)  玩家 / 怪物 / [normal] 装饰
 ├ Camera2D(zoom 1.4, limit 到房间边界)
 └ HUD/Label  房间名 · 动作 · 怪物数 · 键位提示
```

| 键 | 动作 | 说明 |
| --- | --- | --- |
| ← → ↑ ↓ | 走 | 上/下是「景深」移动，不是跳 |
| A D W S | 同上 | |
| X | 普攻 | 三连击 `weaponcomboshort1 → 2 → 3`，每段 600/600/540 ms |
| C | 跳 | 走 `jump` 动作，16 帧；跳跃是 z 轴，不改 `position.y` |
| Z | 上挑 | `skill/swordman/upperslash.skl`（MP 6、CD 2000 ms）；**没有 `upperslash.ani`**，暂借 `attack2` 的动画 |
| F1 | 通行网格 | 调试用 |

移动前逐轴用 `is_walkable()` 校验：`.til` 的 420 格，`0 = 可走`、`2 = 墙/天空`。

## 4. 现在长什么样

`analysis/sf85/shots/`：

- `01_walk.png` — 走路（`move`）
- `02_jump.png` — 跳跃（`jump`）
- `03_attack.png` — 普攻（`weaponcomboshort1` 帧 5/6，刀身层压在身前，右侧哥布林已经贴脸）

远景（`far0` 640×375）+ 中景（`mid1`）+ 前草地 + 花草装饰 + 7 只哥布林 + 鬼剑士 7 层合成，
都是原图直出，没有手绘。

## 5. 复现

```bash
# 1) 图包索引（一次）
python3 tools/mk_npk_index.py

# 2) 导出房间
python3 tools/sf85_export.py --room map/mirkwood/n201.map \
  --weapon equipment/character/swordman/weapon/ssword/sswd_shockwave.equ \
  --out client/assets/sf85

# 3) 让 Godot 认新文件（新增脚本/贴图后必跑）
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
  ./tools/godot/godot --headless --path client/ --editor --quit

# 4) 跑
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
  ./tools/godot.sh res://scenes/sf85_mirkwood.tscn

# 5) 不接显示器出图（SF85_DEMO=1 自动走/跳/砍）
SF85_DEMO=1 XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
  ./tools/godot.sh --write-movie /tmp/mv/f.png --quit-after 380 res://scenes/sf85_mirkwood.tscn
```

## 6. 已知缺口（按优先级）

1. **上挑没有专属动画**：`upperslash.ani` 不存在，只有 `upperslashafter.ani`（收招）。
   正式做法要么用 `attack2` 前段 + `upperslashafter` 后段拼，要么去 110 包里找。
2. **判定盒只用来「打到了」，伤害公式没接**：现在 `ATTACK_DAMAGE = 12` 是常数，
   真正的 `[physic] / [weapon damage apply] / [hit info]` 还没算。
3. **怪物只在原地待机 + 追**，没有攻击判定落地、没有死亡掉落。
4. **远景不视差**：`[far sight scroll] 56` / `[middle sight scroll] 90` 已读到但没用来做滚动系数。
5. **只有 1 个房间**：`map/mirkwood/` 下还有 40 个 `.map`，`.dgn` 的迷宫（`[maze info] 3 4`）没接。
6. **没有碰撞体**：走位靠通行表，不是物理。
