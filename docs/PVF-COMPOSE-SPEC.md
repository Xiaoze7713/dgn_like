# 组合逻辑（给 Loader 的规格说明）

> 目标：你在 Godot 里写一个 loader，**直接从 `Script.pvf` + `ImagePacks2/*.NPK` 读**，不解包到硬盘。
> 本文给出：数据结构、解析顺序、展开规则、坐标公式、坑。字段级字节格式见 `docs/PVF-FORMAT-BYTES.md`。

---

## 1. 输入与输出

**输入**：角色职业（`swordman`）、装备的物品路径列表（如 `equipment/character/swordman/avatar/pants/apants_default.equ`）、动作名（`move`）。

**输出**（每帧一张合成图 + 判定盒）：

```jsonc
{
  "motion": "move",
  "frames": [
    { "delay_ms": 100,
      "layers": [ {"img": "character/swordman/equipment/avatar/skin/sm_body0001.img",
                   "frame": 180, "x": -23, "y": -109, "z": 0}, ... ],
      "boxes": [ {"kind": "damage", "box": [-14,-5,0,27,10,107]} ] }
  ]
}
```

`x/y` 已经是**可以直接当 Sprite2D.position 用**的左上角坐标（见 §5）。

---

## 2. 解析顺序（一次启动做完，缓存起来）

```
1. 打开 PVF → 目录树解密 → 建 map<path, (offset, size, crc)>      ← 只建一次，别每次查
2. 打开 NPK 索引 → 建 map<sprite_path, (npk, offset, size)>        ← img-index.json 已有
3. 对每个装备 .equ：
      读文档 → 找 [animation job] → 本职业那一块 → (look, color) + [(z, 层目录), ...]
4. 对每个动作 motion：
      读 equipment/character/<job>.lay → [xxx motion] 里的模板串 %s/xxx.ani
5. 对每一层：ani_path = 层目录 + "/" + 模板里 %s 之后的部分
6. 解析 .ani → sprites[]（图集模板）+ frames[]（img_id, img_param, x, y, delay, boxes）
7. 展开 sprites[img_id] 的模板 → 真实 .img 路径（§4）
8. 从 NPK 取该 .img 的第 img_param 帧 → (w, h, img.x, img.y, 像素)
```

**关键点：`.ani` 自己就带着图集模板**（`sprites` 字段），不需要你按命名规则硬拼路径。

| 层 | `.ani` 里的 sprites 模板 | 填什么 |
|---|---|---|
| 身体 | `character/swordman/equipment/avatar/skin/sm_body%04d.img` | `%04d` = 皮肤 look（默认 `0000`） |
| 时装 | `.../avatar/pants/sm_pants%02d%02da.img` | `%02d` = look，第二个 `%02d` = color |
| 武器 | `.../weapon/sswd/sswd%02d%02db.img` | 同上 |

模板里的后缀字母（`a`/`b`/`c`/`x`…）**已经写死在模板里**，来自层目录名最后一位，不用你判断。

---

## 3. 层清单（谁来画、按什么顺序）

一句话：**身体 1 层 + 每个已装备槽位的每个 `[layer variation]` 各算一层**。

| 槽位 | 层目录来源 | 例子 | z |
|---|---|---|---|
| 身体 | 固定 `character/<job>/animation` | `sm_body0001` | 0 |
| 裤子 | `[layer variation]` | `pants_b`(1300) / `pants_a`(1500) | 1300/1500 |
| 鞋 | 同上 | `shoes_b`(1200) / `shoes_a`(1400) | 1200/1400 |
| 腰带 | 同上 | `belt_c`(1950) | 1950 |
| 上衣 | 同上 | `coat_a`(1800) | 1800 |
| 披风/项链 | 同上（**可两层**） | `neck_d`(600) / `neck_x`(1975) | 600/1975 |
| 脸 | 同上 | — | — |
| 头发 | 同上 | `hair_a`(2000) | 2000 |
| 帽子 | 同上 | `cap_a`(2100) | 2100 |
| 武器 | `equipment/character/<job>/weapon/<type>/<type><suffix>` | `sswdb`(650) / `sswdc`(2790) | 650/2790 |

**绘制顺序 = z 升序**。z 是数据里的值，不要自己编。

职业限制：每个 `.equ` 有 `[animation job][swordman]` / `[demonic swordman]` / `[creator mage]` 等块，**只取包含当前职业的那块**；`[usable job]` 则判断能不能穿。

---

## 4. 动作从哪来：`.lay` 的 `%s` 替换

`equipment/character/<job>.lay` 是唯一模板：

```
[waiting motion]   %s/stay.ani
[move motion]      %s/move.ani
[dash motion]      %s/dash.ani
[jump motion]      %s/jump.ani
[attack motion]    %s/attack1.ani  %s/attack2.ani  %s/attack3.ani
[etc motion]       %s/guard.ani   %s/hardattack.ani  %s/hitback.ani ...
```

`%s` = 该层的目录（`ani_dir`）：

- 身体：`character/swordman/animation` → `.../animation/move.ani`
- 时装：`equipment/character/swordman/avatar/pants/pants_a` → `.../pants_a/move.ani`
- 武器：`equipment/character/swordman/weapon/ssword/sswdb` → `.../sswdb/move.ani`

有的层缺某个动作（比如某些时装没有 `jump`），**缺就跳过这一层，不要报错**。
验证方法：该层 `.ani` 的 `frame_count` 应等于身体层的。

---

## 5. 坐标：三个数相加（最容易错的地方）

```python
draw_x = ani_frame.x + img_frame.x      # ani 的 POS + 图帧在自己画布内的位置
draw_y = ani_frame.y + img_frame.y
```

- `ani_frame.x/y`：画布左上角在角色坐标系的位置，实测身体/时装/武器都是 `(-232, -333)`。
- `img_frame.x/y`：帧内容在 `.img` 画布（如 500×500）内的大片透明边距中的位置。
- **不要**把 POS 当脚底或角色中心。
- 所有层共用同一个角色坐标系，所以**层与层之间不需要任何额外偏移**——`z` 只管前后，不改变位置。

验证过的例子（`sm_body0001` 走路帧 185）：`POS(-232,-333) + img(216,224) = (-16,-109)`，脚底落在 `y≈+3`。

---

## 6. 判定盒（碰撞）

`.ani` 每帧带 `boxes`，直接读：

```jsonc
{"kind": "damage"|"attack", "box": [x, y, z, w, h, d]}   // 6 个 i32
```

- `damage box` = 挨打盒（几乎所有帧都有）；`attack box` = 攻击盒（**普攻第 1/2 段没有**，只有 attack3/dashattack/weaponcomboblade 等有）。
- 坐标系与绘制坐标相同（相对角色原点），`z` 是纵深，2D 里可忽略。
- 普攻的伤害判定不在动画里：要么引擎按武器类型给默认盒，要么来自 `.atk` 的 `[hit info]`。**这块目前未定论**，见 `dnf_demo/VERIFY-ANIM.md` §3。

---

## 7. Godot 侧建议

```gdscript
# 每层一个 Sprite2D（或 AnimatedSprite2D + SpriteFrames）
# 帧数据 = 一次性解析出来的 Array[Dict]
var f = layers_data[i]           # { img, frame, x, y, z }
sprite.texture = get_img_texture(f.img, f.frame)   # 自己按 (img,frame) 缓存
sprite.offset = Vector2(f.x, f.y)                  # 左上角 → 用 offset/top_left
sprite.z_index = f.z
```

- 纹理缓存 key 用 `"%s#%d" % [img, frame]`，一帧一张 `ImageTexture`（或把整张 `.img` 做成 `AtlasTexture`）。
- **别把 21 万个 `.img` 都导成资源**；按需从 NPK 解码（见 `docs/NPK-FRAME-BYTES.md`：magic → 帧表 → zlib 解压 → B,G,R,A 像素）。
- `.img` 的 8888 像素是 **B,G,R,A**，不是 R,G,B,A（`docs/NPK-FRAME-BYTES.md` §7 有三条证据）。

---

## 8. 复现 / 校验

```bash
python3 tools/make_outfit.py show      # 打印层清单（z / 图集 / 动作目录）
python3 tools/make_outfit.py gif --motion move \
    --weapon equipment/character/swordman/weapon/ssword/5003219.equ \
    --out dnf_demo/verify/2x_weapon_move.gif
```

自检清单（我在 Python 里已经跑过）：

1. 每层 `frame_count` 与身体层一致 → 否则该动作这层缺；
2. 同帧「内容底边」`y + img.y + h` 在动画内波动 ≤ 2px → 坐标公式对；
3. 武器层要在身体之后（z 大）画，刀才会盖住手。

---

## 9. 运行时怎么读（不解包到硬盘）

**不要**把 PVF 解成 21 万个文件（之前 `dnf_demo/text` 101 MB + `dnf_demo/pvf` 87 MB 已删）。
两种读法，选一种：

### A. 直接用 PVF（推荐，零额外文件）

PVF 里就有索引：56 B 头 + 加密目录树。启动时解一次目录树，得到 `path → (abs_offset, length, crc)`：

```gdscript
# 1) 头：sizeGUID(4) + GUID(36) + fileVersion(4) + dirTreeLength(4) + checksum(4) + numFiles(4)
# 2) 读 dirTreeLength 字节，按 u32 解密：
#      v = ror32(v ^ 0x81A79011 ^ checksum, 6)
# 3) 顺序读条目：u32 fileNumber, i32 pathLen, path[pathLen], i32 length, u32 crc, i32 relOffset
#    abs_offset = 56 + dirTreeLength + relOffset
# 4) 读文件体：length→按 4 字节对齐 (length+3)&~3，再同样公式解密，去掉尾部填充
```

Python 参考实现：`tools/pvf_unpack.py` 的 `PvfArchive._parse_header/_parse_dir_tree/decrypt`。
sf115 实测：146 万条目、目录树 141 MB、解密+解析约 7 秒（Python；GDScript 会更慢，可放线程）。

### B. 用预生成的索引（省掉目录树解密）

```bash
python3 tools/pvf_index.py build      # → analysis/pvf/index/pvf-index.jsonl.gz（37.9 MB，146 万条）
python3 tools/pvf_index.py query monster/goblin/
```

每行 `{"p":"路径","o":文件体内绝对偏移,"s":长度}`，配 `pvf-index.meta.json`（含 `file_version`、
`data_start`、`dir_tree_length`、`sha1_head`）。Godot 侧把 jsonl 读成 `Dictionary[String → Vector2i]`，
按路径查 offset，再按同一套 `decrypt` 读文件体即可 —— **完全不需要解压任何东西**。

> 校验：`meta.sha1_head` 是 PVF 前 4 KB 的 SHA1，换了档要重新 build。

### 贴图那条线同理

`.img` 从 NPK 按需读（`img-index.json` 已有 198,704 个 `sprite路径 → (npk, offset, size)`），
解码见 `docs/NPK-FRAME-BYTES.md`（magic → 帧表 → zlib → B,G,R,A）。**不必预导出 PNG。**
