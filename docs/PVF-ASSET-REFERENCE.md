# PVF 资产引用关系：一个角色是怎么被拼出来的

> 本文回答三个问题：**基础人物的动作在哪、时装的图在哪、每层画在哪（偏移怎么算）**。
> 全部结论都在 sf115 的 `Script.pvf` 上逐条验证过，可用文末命令复现。

---

## 0. 一句话总览

角色 = **一副骨头（动作定义） + N 张贴图（身体 1 张 + 每个时装槽 1~2 张）**，
动作由 `character/<job>/animation/*.ani`（身体）与 `equipment/character/<job>/avatar/<part>/<层目录>/*.ani`（时装）提供，
贴图在 NPK 里，**两者通过同一个坐标系 `POS` + 图帧自带的 `(x,y)` 对齐**。

```
                    ┌─ equipment/character/swordman.lay   ← 动作模板（%s/stay.ani 这类）
  swordman.chr ─────┤
                    └─ character/swordman/animation/*.ani ← 身体动作（每帧：贴图下标+帧号+POS）
                                    │
                                    ▼
                          sprites[] = "character/swordman/.../sm_body%04d.img"
                                    │  （去掉 %04d → 由皮肤 look 决定）
                                    ▼
                     NPK 里的 .img（画布 cw×ch，每帧内容在 (x,y) 处）
                                    │
                                    ▼
                     合成：PNG 左上角 = (POS.x + img.x, POS.y + img.y)
```

时装那条线完全对称，只是根换成了 `.equ`：

```
  某个 .equ（背包里的那件时装）
      [animation job] → [swordman] → [variation] (look, color)
                                    [layer variation] (z, 层目录)
                                    [equipment ani script] → swordman.lay
                │
                ├─ 图：character/swordman/equipment/avatar/<part>/sm_<part><look:02><color:02><后缀>.img
                └─ 动作：equipment/character/swordman/avatar/<part>/<层目录>/<动作>.ani
```

---

## 1. 九个可见槽位（皮肤不算槽位）

鬼剑士的时装槽位共 **9 个**，`skin`（皮肤）不是槽位，它决定身体图集的 look（`sm_body%04d` 的 `%04d`）。

| # | 槽位（PVF 目录） | `.equ` 里的 `[equipment type]` | 默认值 | 默认 z / 层目录 |
|---|---|---|---|---|
| 1 | `pants` 裤 | `[pants avatar]` | `apants_default.equ` | 1500 `pants_a` + 1300 `pants_b` |
| 2 | `shoes` 鞋 | `[shoes avatar]` | `ashoes_default.equ` | 1400 `shoes_a` + 1200 `shoes_b` |
| 3 | `belt` 腰带 | `[waist avatar]` | **无（空槽）** | 例：1950 `belt_c` |
| 4 | `coat` 上衣 | `[coat avatar]` | `acoat_default.equ` | 1800 `coat_a` |
| 5 | `neck` 项链/披风 | `[breast avatar]` | **无（空槽）** | 例：600 `neck_d` + 1975 `neck_x`（两层！） |
| 6 | `face` 脸部 | `[face avatar]` | **无（空槽）** | 例：… |
| 7 | `hair` 头发 | `[hair avatar]` | `ahair_default.equ` | 2000 `hair_a` |
| 8 | `cap` 帽子 | `[cap avatar]` | `ahat_default.equ`（look=101，无图集→**默认不戴帽**） | 2100 `cap_a` |
| 9 | `aura` 光环 | 无 `[animation job]`（**纯特效**，不出贴图层） | 无 | — |

另有 `skin`（皮肤，280 个 `.equ`）与 `weapon`（武器，100 个条目，走 `equipment/character/<job>/weapon/` 另一套）。

**一个槽位可以拆成多层**：`[layer variation]` 里每一对 `z + 目录名` 就是一层，各有自己的 z 和图集。
最典型的是裤子和鞋（前腿/后腿两张图）与披风（内层 + 外层）。**只画第一层就会出现「一条腿是裸的」**。

---

## 2. 动作从哪来：`.lay` 是唯一模板

`equipment/character/swordman.lay` 把「语义动作」映射到「文件」，用 `%s` 占位层目录：

```
[waiting motion]      %s/stay.ani
[move motion]         %s/move.ani
[dash motion]         %s/dash.ani
[attack motion]       %s/attack1.ani
                      %s/attack2.ani
                      %s/attack3.ani
[etc motion]          %s/guard.ani
                      %s/hardattack.ani
                      %s/hitback.ani
                      ...
```

同一个 `.lay` 被所有层共用，只是 `%s` 换成各自的目录：

| 层 | `%s` = | 实际文件 |
|---|---|---|
| 身体 | `character/swordman/animation` | `character/swordman/animation/move.ani` |
| 裤子（前腿） | `equipment/character/swordman/avatar/pants/pants_a` | `.../pants_a/move.ani` |
| 上衣 | `equipment/character/swordman/avatar/coat/coat_a` | `.../coat_a/move.ani` |
| 武器 | `equipment/character/swordman/weapon/ssword/sswdb` | `.../sswdb/move.ani` |

所以「哪个动作存在」是**一层一层自己带的**：身体层没有的动作，时装层也可能没有。
验证方法：把 `.ani` 解析出来看 `frame_count` 是否等于身体层的。

`[attack motion]` 里那三条 `attack1/2/3` 就是普攻的三段**来源**（只是候选，实际用哪条由技能/引擎决定）。

---

## 3. 偏移怎么放：三个数相加

每一层在每一帧上有三个来源的位置信息：

| 来源 | 字段 | 含义 |
|---|---|---|
| `.ani` 帧 | `x, y`（POS） | **画布**左上角在角色坐标系的位置（越大越靠左下...实际 y 轴向下） |
| `.img` 帧 | `x, y`（img.x / img.y） | 该帧**内容**在 `.img` 画布（`cw×ch`）内的位置 |
| `.equ` | `z` | 绘制顺序，越大越靠前 |

合成公式（已在 4 个动画、8 帧上验证，脚底抖动从 20px 降到 1px）：

```
draw_x = ani.x + img.x
draw_y = ani.y + img.y        # y 轴向下
按 z 升序依次 alpha 合成
```

实测数据（`sm_body0001` 走路）：`POS = (-232, -333)`，帧内容 `ix/iy ≈ (209~216, 224~225)`，
所以画到 `(-16, -109) ~ (-23, -108)`；裤子同帧 `POS` 相同、`iy≈262~298`，正好落在腰部以下。

> **不要**把 `POS` 当成「脚的坐标」或「角色中心」——它是**画布原点**，
> 画布内还有一圈透明边距（`sm_body0001` 的画布是 500×500 里的一小块）。

---

## 4. 图集命名规则

```
sm_<part><look:2><color:2><后缀>.img
     │      │        │      └─ 层/体型后缀：a/b/c/d/f/g/x（来自层目录名最后一位）
     │      │        └─ 染色号（0~6 常见）
     │      └─ 款式号（同款不同件）
     └─ 部位名
```

例子：

| `.equ` 里的 variation | 层目录 | 图集 |
|---|---|---|
| belt `38 2` | `belt_c` | `sm_belt3802c.img` |
| neck `127 1` | `neck_d`、`neck_x` | `sm_neck1271d.img`、`sm_neck1271x.img` |
| coat `0 0` | `coat_a` | `sm_coat0000a.img` |

身体不走这个规则：`sm_body%04d.img`，`%04d` = 皮肤的 look（默认 `0000`；
本仓库用 `0001` 这张 242 帧的基础皮肤做验证，`0180` 是放大档活动皮肤，**混用会「身高差一截」**）。

---

## 5. 一条完整链路的例子（默认套装，走路第 185 帧）

```
character/swordman/swordman.chr
  → equipment/character/swordman.lay  [move motion] %s/move.ani
  → character/swordman/animation/move.ani   frame[5]: img_id=0 img_param=185 pos=(-232,-333) delay=100
  → sprites[0] = character/swordman/equipment/avatar/skin/sm_body%04d.img
  → 皮肤 look=0 → sm_body0000.img（缺则退回同目录帧数最多的那张）
  → NPK: sprite_character_swordman_equipment_avatar_skin.NPK 里的 .img 帧 185
  → PNG 左上角 = (-232 + 213, -333 + 224)

时装同理：
apants_default.equ → variation(0,0) → 层 [1500 pants_a][1300 pants_b]
  → sm_pants0000a.img / sm_pants0000b.img 的帧 185 → 同一个 POS(-232,-333)
```

---

## 6. 复现命令

```bash
# 看某个 .equ 解出来的全部层（含图集路径）
python3 tools/make_outfit.py show

# 换装：任意槽位塞一件
python3 tools/make_outfit.py gif --motion move \
    --equ belt=equipment/character/swordman/avatar/belt/abelt_upripebana.equ \
    --equ neck=equipment/character/swordman/avatar/neck/chn_equ_special_avatar_swordman_neck_101520617.equ \
    --out dnf_demo/verify/12_outfit9_move.gif

# 查一个动作的原始帧（POS / img_param / delay / 判定盒）
python3 tools/pvf_unpack.py cat equipment/character/swordman/avatar/pants/pants_a/move.ani
```

产物示例：`dnf_demo/verify/12_outfit9_move.png`（默认套装 + 香蕉腰带 + 海军披风，8 帧走路）。

---

## 7. 还没解出来的

1. **`[avatar type select] 7 0 0 1100`** 这串数的语义（疑似 允许的体型/层/优先级/上限），未验证。
2. **武器层**如何绑定到具体武器物品（`weapon 100` 个条目 vs `equipment/weapon/*.equ` 的 id 映射）。
3. **aura（光环）**：没有 `[animation job]`，实际由引擎按 `[avatar func filter]` 播特效，未接。
4. **染色系统**：`color` 号与调色板的关系（图集里颜色是烘死的，还是运行期调色）。
