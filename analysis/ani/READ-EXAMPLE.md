# 怎么用 `.ani` 帧表数据集（5 分钟上手）

数据：`export/ani/*.jsonl`（185 个分片，按 PVF 根目录切；最大 `equipment__character.jsonl` 649 MiB）
一条记录 = 一个 `.ani` 的完整时间轴。**没有"一帧一个文件"**（Godot 导入会超线性爆炸，见 `docs/ANI-FORMAT.md` §7）。

## 0. 记录长什么样

```json
{"src":"monster/casillas/animation/attack1.ani","ani_frames":6,"images":["Monster/Casillas/Body/casillas.img"],
 "total_ms":780,
 "frames":[
   {"i":0,"x":-220,"y":-294,"d":80,"t":0,"img":[["Monster/Casillas/Body/casillas.img",12]],
    "db":[[-28,-7,0,58,14,152]]},
   {"i":2,"x":-220,"y":-294,"d":80,"t":240,"img":[["Monster/Casillas/Body/casillas.img",14]],
    "ab":[[170,-20,41,90,40,155],[-20,-20,10,200,40,142]],
    "db":[[-28,-7,0,58,14,152]]}]}
```

| 键 | 含义 |
|---|---|
| `src` | PVF 内路径（`export/text/<src>.bin` 即原始字节） |
| `ani_frames` | 帧数（= `.ani` 头部的 `[FRAME MAX]`） |
| `images` | 文件头声明的 `.img` 候选表（帧里的 `img` 是它的下标） |
| `total_ms` | 整段时长（各帧 `d` 之和） |
| `frames[].i` | 帧号 0-based |
| `frames[].t` | 该帧**开始时刻**（ms，累加 `d`） |
| `frames[].d` | 该帧持续（`[DELAY]`，ms） |
| `frames[].x/y` | 该帧图像相对角色原点的偏移（`[IMAGE POS]`） |
| `frames[].img` | `[[img路径, img内帧号], ...]`；**键缺失 = 该帧不画图**（空图像帧，仍有判定盒） |
| `frames[].ab` | 攻击盒列表，每个 `[相对X, 相对Y, 相对Z, 宽, 高, 深]`（`[ATTACK BOX]`） |
| `frames[].db` | 伤害盒列表，同六元组（`[DAMAGE BOX]`，通常是"被击体积"，常整段不变） |
| `frames[].flag` | **`[FLAG]` flagIndex（int）**：该帧的"关键帧 flag"，等同脚本传给 `sq_SetCurrentAnimation` 的 flag 实参；**键缺失 = 该帧无 flag，不触发回调** |
| `frames[].fx` | 可选表现：`rate`(2 float)、`rotate`、`rgba`、`gfx`(枚举名)、`dmg_type`、`interp`… |
| `clean:false` | 只有此字段出现时表示"尾部有残留"（帧数据仍可用） |
| `{"src","error"}` | 解析失败行（4.64%），**加载时跳过即可**，不要抛异常中断整包 |

> 关键区分（实测 `monster/casillas/animation/attack1.ani`）：**`0x0e` = 伤害盒**（常整段不变，如上例
> `[-28,-7,0,58,14,152]` 6 帧全同）；**`0x0f` = 攻击盒**（按帧出现、可一帧多个，如上例索引 2 处一帧两个）。
> 这就是"为什么单文件里 6 个整数看起来恒定"的答案。

---

## 1. 用 Python 读一个分片（不需要第三方库）

```python
import json

PATH = 'export/ani/monster__casillas.jsonl'

def iter_records(path):
    """逐行读；失败行没有 frames，直接跳过。1.05M 条全程可流式处理，内存 O(1)。"""
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            rec = json.loads(line)
            if 'error' in rec:          # 4.64% 的坏文件
                continue
            yield rec

for rec in iter_records(PATH):
    print(rec['src'], rec['ani_frames'], rec['total_ms'], rec['images'][:1])
```

**分片选择**：只加载你需要的根目录。做角色就 `character.jsonl` + `equipment__character.jsonl`，
做怪就 `monster__*.jsonl`，做被动对象/特效就 `passiveobject__*.jsonl`。
不要一次性 `glob('export/ani/*.jsonl')` 全读（1.66 GiB）。

---

## 2. 查"某角色 / 某动作"的帧表

`src` 是 PVF 路径，所以按前缀/后缀过滤最快；动作名就是文件名（`attack1`、`stay`、`dash`…）。

```python
import json, glob

def find_ani(root_file, needle):
    """needle 例：'casillas/animation/attack1' 或 'swordman/animation/attack1'"""
    for line in open(root_file, encoding='utf-8'):
        if needle not in line:          # 先做廉价字符串预筛，避免对 64 万行都做 json.loads
            continue
        rec = json.loads(line)
        if rec.get('src', '').endswith(needle + '.ani'):
            return rec
    return None

rec = find_ani('export/ani/monster__casillas.jsonl', 'casillas/animation/attack1')
print(rec['src'], rec['ani_frames'], rec['total_ms'])
for f in rec['frames']:
    print(' frame', f['i'], 't=%dms' % f['t'], 'dur=%dms' % f['d'],
          'pos=(%d,%d)' % (f['x'], f['y']), 'img=%s' % (f.get('img'),),
          'ATK=%s' % (f.get('ab'),), 'DMG=%s' % (f.get('db'),))
```

期望输出（`monster/casillas/animation/attack1.ani`，6 帧 / 780 ms，可用来验证你读到的是同一份数据）：

```
frame 0 t=0ms   dur=80ms  pos=(-220,-294) img=[['Monster/Casillas/Body/casillas.img', 12]] ATK=None DMG=[[-28,-7,0,58,14,152]]
frame 2 t=240ms dur=80ms  pos=(-220,-294) img=[['Monster/Casillas/Body/casillas.img', 14]]
        ATK=[[170,-20,41,90,40,155],[-20,-20,10,200,40,142]] DMG=[[-28,-7,0,58,14,152]]
```

**从动作名找到 ani 的完整链路**（PVF 里动作是 `.act` 指的，实测例子）：
`export/text/monster/casillas/action/attack01.act.txt`：

```
[MOTION]
    [BASE ANI]
        ../despair_ani/Attack1.ani
    [SUB ANI]
        ../despair_ani/Slash/Slash1-1.ani 0 0 ../despair_ani/Slash/_Slash1-2.ani 0 0
```

→ `[BASE ANI]` 相对 `.act` 所在目录解析 → `monster/casillas/despair_ani/attack1.ani`
→ 到帧表 JSONL 里查这个 `src`。注意两点：

1. **同一动画常有多份拷贝**：casillas 的 `despair_ani/attack1.ani` 与 `animation/attack1.ani` 字节完全相同
   （384 B，6 帧，第 3 帧两个攻击盒）。按 `[BASE ANI]` 指的路径查，不要按"看着像"的目录猜。
2. `.act` 只引用 ani 路径与触发帧号，**不复制判定盒**——判定盒只存在于 `.ani`（所以帧表是唯一真源）。

---

## 3. 取第 1~4 帧的攻击盒（生成判定事件）

```python
import json

def attack_events(rec, frame_from=1, frame_to=4):
    """把这几个帧的攻击盒展开成「时间轴上的判定框事件」。
    返回 [(t_start_ms, t_end_ms, [x,y,z,w,h,depth]), ...] —— 直接喂给判定系统。"""
    ev = []
    for f in rec['frames']:
        if not (frame_from <= f['i'] <= frame_to):
            continue
        for box in f.get('ab') or []:
            ev.append((f['t'], f['t'] + f['d'], box))
    return ev

rec = find_ani('export/ani/monster__casillas.jsonl', 'casillas/animation/attack1')  # 同上
for t0, t1, box in attack_events(rec, 1, 4):
    print('%5d → %5d ms   box=%s' % (t0, t1, box))
```

实战注意 4 条：

1. **`ab` 是相对角色原点的盒子**，判定时用 `角色世界坐标 + (box[0], box[1])` 换算；`z`/`depth`
   是深度方向（2D 横版可以只用 `w/h`，但 `z` 决定"能不能打到浮空/背后的目标"）。
2. **同一帧可能有多个攻击盒**（如 casillas attack1 索引 2 处一帧两个），每个独立生成事件，命中一次即可。
3. **帧里没有 `img` 也能有 `ab`**（空图像帧 = 纯判定帧，如 `passiveobject/common/animation/noneexplosion.ani`
   只有 1 帧、无图、攻击盒 `[-65,-45,-50,130,90,100]`）。判定逻辑不要依赖"有图才判定"。
4. **用完请按 `t` 而不是帧号计时**：帧延迟不等长（上例 80/160/80…），按帧号算时间会漂移。

---

## 4. 三个坑（已经在数据里处理好了，但用的时候要知道）

| 坑 | 事实 | 你要做什么 |
|---|---|---|
| `.img` 悬空 | 977,272 条 img 引用**全部**在 `export/_meta/index.sqlite` 里查不到——因为 `.img` 不在 Script.pvf，在 `ImagePacks2/*.NPK` | P0.6 用同一路径去 NPK 找图；**别当成数据缺失** |
| `%04d` 模板 | 50.6% 的 img 是 `.../gg_body%04d.img` 这种 | 运行时按 `img内帧号` 选具体文件（帧号/图集内帧数），不是字面路径 |
| 坏文件 | 48,651 条（4.64%）`{"src","error"}` | 加载时 `continue`；统计进"缺动画"报警，不要 fatal |

---

## 5. （附）Godot 4 侧的最小读法

```gdscript
func load_ani_tables(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line()
		if line.is_empty():
			continue
		var rec = JSON.parse_string(line)
		if rec == null or rec.has("error"):
			continue                      # 坏文件/非法行直接跳过
		out[rec["src"]] = rec             # key = PVF 路径，和 .act 里的引用对得上
	return out
```

> 1.66 GiB 全量一次性进内存不现实：按需只读当前关卡/角色用到的分片，或先用 `--stats-only` 之外的
> 一个 Python 小脚本把"本关要的帧表"筛出来另存小 json。
