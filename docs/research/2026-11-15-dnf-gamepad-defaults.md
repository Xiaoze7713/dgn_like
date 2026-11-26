# DNF 客户端手柄默认映射（官方数据）

- 期次：2026-11-15
- 作者：DSH（资源与行为研究）
- 状态：已确认（数据来自客户端，可复现）
- 关联：手柄键位方案（`docs/GAMEPAD-BINDINGS-34.md`）

## 1. 问题与范围

新作要做手柄方案。要判断的是：**DNF 客户端自己的手柄映射长什么样**，
哪些键被高频动作占用、修饰键怎么用 —— 而不是只凭手感猜。

范围：客户端手柄映射表本身；不涉及手感与设备差异。

## 2. 方法与复现

```bash
python3 - <<'PY'
import sys; sys.path.insert(0, 'tools')
import pvf_new_extract as X
p = X.NewPvf('analysis/pvf-new/inner/Script.inner.pvf')
l10n = X.L10n(p)
txt = X.decode_script(p.read_by_path('clientonly/gamepad/gamepadhotkeyinfo.co'), p.resolve, ref=l10n)
open('/tmp/gamepad.txt', 'w').write(txt)
PY
```

源文件：`Script.pvf:clientonly/gamepad/gamepadhotkeyinfo.co`（2,560 B，dtype=1 token 流）。
结构：`[raid buff key data]`、`[character data]`（`[easy dash axis] 0.95`）、
`[mouse data]`（`[x speed] 1600`、`[y speed] 1600`、`[axis keydown deadzone] 0.20`）、
`[mouse key list]`（K19–K26 映射到 mouse_up/down/left/right/click/wheel）、
`[hotkey list]` 里 66 个 `[info]` 块。

## 3. 观察（可验证事实）

- **A1** 每个 `[info]` 块 = `动作 id` + `[category]` + `[default] joy_xxx` + 可选 `[ignore combin key]`。
- **A2** 共 66 条：character 12、dungeon 20、system 23、quick(chat) 11（有动作不带 `[default]`）。
- **A3** 手柄键名用 `joy_a/b/x/y`、`joy_lshoulder/rshoulder`、`joy_ltrigger/rtrigger`、
  `joy_direct_up/right/down/left`（十字键）、`joy_back/start`、
  `joy_laxis_*` / `joy_raxis_*`（左右摇杆方向）。
- **A4** 移动 = 左摇杆（`joy_laxis_up/left/down/right`），且标了 `[ignore combin key]`。
- **A5** 战斗高频键：`I05 普通攻击`=`joy_a`、`I06 跳跃`=`joy_b`、`I07 技能`=`joy_x`、`I08 技能2`=`joy_y`。
- **A6** 技能槽：`I21–I24`(技能1–4) = `joy_x/joy_y/joy_b/joy_a`；`I25`(5)=`joy_rshoulder`；`I26`(6)=`joy_rtrigger`；
  扩展技能 `I27–I32` 与 `I21–I26` **完全同键**（说明客户端是「翻页/组合键」切扩展栏，而不是另一排物理键）。
- **A7** 物品快捷键 `I33–I38` = 十字键上、右、下、左、上、右（6 个动作挤 4 个物理键）。
- **A8** `K16 组合键1`=`joy_lshoulder`、`K17 组合键2`=`joy_ltrigger` —— **客户端明确把 LB/LT 当修饰键**。
- **A9** 系统键：`I49 关闭全部菜单`=`joy_back`、`K18 鼠标切换`=`joy_start`。
- **A10** 客户端自带「手柄模拟鼠标」：`K19–K22` 左摇杆移动光标、`K25/K26` 右摇杆滚轮、
  `K23/K24` = `joy_a`/`joy_b` 当鼠标左右键，`[axis keydown deadzone] 0.20`。
- **A11** `[easy dash axis] 0.95` —— 冲刺是「摇杆推到 95% 以上」触发，不是独立按键。

## 4. 推断（解释，标置信度）

- **B1（高）** 客户端的 8 个「技能位」是 **6 技能 + 2 个肩键位**，扩展技能靠翻页；
  这意味着「12 个技能位同时对玩家可见」在 DNF 里并不成立。
- **B2（中）** `joy_a/b` 同时被鼠标模拟占用（A10），说明手柄模式下 UI 操作也靠手柄，
  不是「手柄只管战斗、鼠标管界面」。
- **B3（中）** `[ignore combin key]` 的动作（移动/普攻/跳跃/技能 1–2/摇杆光标）**不参与组合键**，
  其余动作都可以被 LB/LT 修饰 —— 这就是我们方案里「LB+面键 = 第二排」的原始依据。
- **B4（低）** `easy dash axis 0.95` 说明客户端不使用双击方向冲刺，而用摇杆推满；新作若要手感接近，可照抄。

## 5. 与新作设计的关系

- 我们的方案在你定的方向下**有意偏离**客户端：把 RB/RT 从「技能 5/6」改成「闪避/普攻」，
  因为新作有闪避这个 DNF 没有的高频动作。
- 客户端的「LB/LT = 修饰键」结论支持我们的「LB+面键 = 第二排」，这条可以放心用。
- 客户端**没有第三排**。所以「第三排要不要」没有原作依据，属于新作自定，建议按你的待验证点实测决定。

## 6. 结论与交接

- 数据已落 `docs/GAMEPAD-BINDINGS-34.md` 的「客户端原生」预设里（代码可一键切换对照）。
- 交接建议：
  - 手柄布局的**手感结论只能实机验证**（我这台机器没有手柄），测试清单在第 6 节；
  - 若要做手柄自定义映射，`GamepadKeys` 的布局表已经是数据驱动，扩成可编辑成本很低；
  - 右摇杆的用途（瞄准 / 选目标 / 镜头）属于设计决定，需要你拍板后我再接具体逻辑。
