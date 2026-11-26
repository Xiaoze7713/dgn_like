# 落地说明 01：移动与动画播放

> 目标：一次打通 **输入 → 状态切换 → 帧表 → 图集矩形 → 屏幕像素** 这条管线。
> 这段通了，攻击/受击/技能都只是在这条管线上加分支。
> 数据全部来自 sf115 实测，不是推测；标「自定」的地方是真没有数据。

---

## 1. 一个角色动起来需要几个动画

鬼剑士（未转职）的移动相关动画写在 `export/text/character/swordman/swordman.chr.txt` 的 motion 字段里：

| 字段 | 值 | 说明 |
|---|---|---|
| `[waiting motion]` | `Animation/Stay.ani` | 待机（idle） |
| `[move motion]` | `Animation/Move.ani` | 走路/跑动循环 |
| `[sit motion]` | `Animation/Sit.ani` | 坐下 |
| `[damage motion 1]` | `Animation/Damage1.ani` | 受击 |
| `[back motion]` | `Animation/Attack3.ani` | 后退（就是攻击3，复用） |
| `[simple move motion]` | `Animation/SIMPLE_Move.ani` | 简化走路（小地图/表演用） |

**路径规则**：字段里的 `Animation/Stay.ani` 是**相对该 `.chr` 所在目录**的，实际文件是
`character/swordman/animation/stay.ani`（PVF 内全部小写）。

**⚠️ 第一号坑**：`.ani` 有双份副本，解析顺序必须是
`character/swordman/animation/` → `equipment/.../weaponmaster/` → 全局同名。
只有 chr 根那份带 `[ATTACK BOX]`，副本的盒数是 0。按文件名裸搜还会撞到 `monster/`、`mage/` 的同名 ani。

---

## 2. 实测帧数据（这几个数可以直接抄）

| 动画 | 帧数 | 单帧时长 | 总时长 | 循环 | 攻击盒 | 伤害盒 |
|---|---|---|---|---|---|---|
| `stay.ani` | 6 | 120 ms | 720 ms | ✅ | 0 | 12 |
| `move.ani` | 8 | 100 ms | 800 ms | ✅ | 0 | 8 |
| `dash.ani` | 8 | 100 ms | 800 ms | ❌（一次性） | 0 | 29 |
| `jump.ani` | 16 | 50–10000 ms | 可变 | ❌ | 0 | 33 |
| `simple_move.ani` | 8 | 100 ms | 800 ms | ✅ | 0 | 0 |

`jump.ani` 的 `delay` 跨 50–10000 ms，因为起跳到落地是**靠脚本停帧**的，不能当固定时长循环播。

---

## 3. 帧表 JSON 长什么样

`export/ani/*.jsonl` 每行一个 `.ani` 的完整时间轴。以 `move.ani` 为例（节选）：

```json
{
  "src": "character/swordman/animation/move.ani",
  "ani_frames": 8,
  "images": ["Character/Swordman/Equipment/Avatar/skin/sm_body%04d.img"],
  "total_ms": 800,
  "frames": [
    { "i": 0, "x": -232, "y": -333, "d": 100, "t": 0,
      "img": [["Character/Swordman/Equipment/Avatar/skin/sm_body%04d.img", 180]],
      "db":  [[-14, -5, 0, 27, 10, 107]] },
    { "i": 1, "x": -232, "y": -333, "d": 100, "t": 100, "img": [["...", 181]], "db": [...] }
  ]
}
```

字段含义：

| 字段 | 含义 |
|---|---|
| `src` | 源 `.ani` 路径（坏文件这一行是 `{"src","error"}`，**跳过即可**） |
| `frames[].i` | 帧序 0 基 |
| `frames[].x/y` | 该帧 `[IMAGE POS]`，相对角色原点的偏移 |
| `frames[].d` | 该帧停留毫秒 |
| `frames[].t` | 累计时间轴起点（= 前面所有 `d` 之和） |
| `frames[].img` | `[[img 路径, 帧号], ...]`，**可以有多个**（身体 + 武器 + 特效分层） |
| `frames[].ab` | 攻击盒数组，`[x,y,z,w,h,d]`；无盒时字段缺失或空 |
| `frames[].db` | 伤害盒数组，同上（受击用） |
| `frames[].flag` | 脚本回调帧标记；`65534` 是「无 flag」哨兵，**不是真 flag** |

---

## 4. 坐标系：三条铁律

### 4.1 偏移直接相加

```
draw_top_left = (ani.x + img.x, ani.y + img.y)
```

`.ani` 的 `[IMAGE POS]` 与 `.img` 帧记录里的 `(x, y)` **同一个坐标系，直接相加**。
`img` 里的 `frameWidth/frameHeight`（常见 500×500）只是**编辑器画布大小，不参与定位**。

已用 `attack1.ani` + `sm_body0000.img` 叠 8 帧验证：脚落在原点（`y_bottom≈5`）、水平居中（`x_center≈-7.5`）。
**按「画布中心」算会整体上浮 250 px**。

### 4.2 Y 轴向下

DNF 的世界是屏幕坐标，`y` 增大 = 向下 = 屏幕里更靠前。
Godot 的 `CanvasItem` 也是 y 向下，所以**不用翻**。但如果你之后做 3D 位移或深度排序，注意「y 大的盖住 y 小的」。

### 4.3 朝左镜像

```
flip_h = true 时：  draw_x = -(ani.x + img.x) - img_w
```

也就是**先算正常位置，再把 x 关于原点镜像**（不是简单取反，要减宽度，否则整体偏一个身位）。

---

## 5. 速度从哪来

`swordman.chr` 里：

```
[move speed]     1350.0
[attack speed]   1150.0
[cast speed]     1000.0
```

**基准是 1000**，所以 1350 = 1.35× 基础速度。但**「1× 到底是每秒多少像素」不在任何 PVF 文件里**（在服务端/引擎常量）。

→ **自定**。建议：

```gdscript
const BASE_MOVE_SPEED := 180.0   # px/s，1000 基准时的速度
var speed := BASE_MOVE_SPEED * (move_speed / 1000.0)   # 1350 → 243 px/s
```

这个数和 `move.ani` 的 8 帧 × 100 ms 搭配起来观感接近原版（脚下有滑动感但不过分），先调手感再谈还原。

---

## 6. Godot 骨架（参考用，你自己改）

```gdscript
# frame_player.gd —— 手驱帧播放，不用 AnimatedSprite2D（它要预先切好 9 万个资源）
class_name FramePlayer
extends Sprite2D

var frames: Array = []          # 从 jsonl 读出的 frames
var anim_name := ""
var loop := true
var _t := 0.0                   # 已播毫秒
var _i := 0                     # 当前帧序

func play(table: Dictionary, do_loop := true) -> void:
    frames = table["frames"]
    loop = do_loop
    _t = 0.0
    _i = 0
    _apply()

func _process(delta: float) -> void:
    if frames.is_empty():
        return
    _t += delta * 1000.0
    var changed := false
    while _i < frames.size() and _t >= frames[_i]["t"] + frames[_i]["d"]:
        if _i + 1 < frames.size():
            _i += 1
            changed = true
        elif loop:
            _t -= frames[frames.size() - 1]["t"] + frames[frames.size() - 1]["d"]
            _i = 0
            changed = true
        else:
            break
    if changed:
        _apply()

func _apply() -> void:
    var f: Dictionary = frames[_i]
    # 1) 取图：img 是数组，可以是多层（身体/武器/特效），这里只画第一层
    var ent: Array = f["img"][0]
    var tex := TextureBank.get_texture(ent[0])      # img 路径 → Texture2D
    texture = tex
    var r := TextureBank.get_rect(ent[0], ent[1])    # 帧矩形 (x,y,w,h)
    region_enabled = true
    region_rect = Rect2(r[0], r[1], r[2], r[3])

    # 2) 定位：偏移直接相加
    var px: float = f["x"] + r[0]
    var py: float = f["y"] + r[1]
    if flip_h:
        px = -px - r[2]
    centered = false
    position = Vector2(px, py)

    # 3) 帧事件：判定盒 / flag
    if f.has("flag") and f["flag"] != 65534:
        emit_signal("flag_hit", f["flag"])
    if f.has("ab"):
        emit_signal("attack_box", f["ab"])
```

配套的 `TextureBank` 就是「`img 路径` + `帧号` → `Texture2D` + `Rect2`」的查表，等 t11 的图集产物出来直接接：

```gdscript
# npk_parser slice 产物（export/atlas/）大概是：
#   <img 路径>.png            整张 .img 的帧表图
#   frames.jsonl              每帧 (img, 帧号, x, y, w, h)
```

---

## 7. 常见错法清单（按踩坑概率排序）

| # | 错法 | 症状 | 正解 |
|---|---|---|---|
| 1 | 用画布中心定位 | 角色整体上浮约 250 px | `ani.x + img.x` 相加，`centered=false` |
| 2 | `.ani` 按名裸搜 | 攻击永远打不到人 / 动画跳到别的职业 | 解析顺序 chr 根优先 |
| 3 | 翻转只取反 x | 转身时角色横向瞬移一个身位 | `px = -px - w` |
| 4 | 把 `flag 65534` 当事件 | 每帧都触发回调 | 65534 = 无 flag，跳过 |
| 5 | 把 `jump.ani` 当固定时长播 | 落地前一直悬空 / 提前落地 | 起跳用 50 ms 起手，落地由状态机切回 |
| 6 | `[move speed] 1350` 当 px/s | 慢得像爬 / 快得飞起 | ÷1000 得倍率，再乘自定基数 |
| 7 | 用 `AnimatedSprite2D` 导入 PNG 序列 | 导入卡死（9 万资源） | `Sprite2D` + `region_rect` 手驱 |
| 8 | 帧表按 `t`（累计时间）直接索引 | 掉帧时跳帧 | 按 `t + d` 比较推进，见上面 `_process` |

---

## 8. 验收标准

做到这几条，这条管线就算通了：

1. 待机：`stay.ani` 循环播放，脚不动、呼吸感有。
2. 走路：按住方向键切到 `move.ani`，人物朝对应方向移动，帧循环不卡顿。
3. 转身：左右切换时**不横向跳位**，只是镜像。
4. 冲刺：按冲刺键播 `dash.ani` 一次并位移（8 帧 × 100 ms = 0.8 s）。
5. 跳跃：起跳 50 ms 起手 → 空中保持 → 落地切回待机。
6. 帧率无关：把窗口从 60 fps 改到 144 fps，动画速度不变。

---

## 9. 还缺什么（不阻塞）

- `.img` 的 PNG 与帧矩形表：t11 正在出（171 张 / 47 MB）。
- 「1× 速度 = 多少 px/s」：真没有，自定。
- `flag 65534` 之外的真实 flag 在切片里只有十字斬用到（flag 1、2），移动动画全是无 flag。
