# SQR（Squirrel 脚本）翻译细则

> 给子 agent 的唯一规范。开始翻译前**务必先读**：
> 1. 本文件；
> 2. 翻译样例 `sqr_gd/character/atmage/chainlightning/chainlightning.gd`（风格以它为准）；
> 3. 你负责的清单 `analysis/sqr/groups/gN.txt`（一行一个相对路径）。

## 0. 这是什么

DNF 客户端把 **Squirrel VM** 内嵌在 exe 里，把脚本放在 PVF 的 `sqr/` 目录，开机 `sq_RunScript` 加载。
脚本里调用的 `sq_*` 全是宿主（C++）注入的引擎绑定；`obj.sq_*` 是挂在对象上的绑定。
所以这不是自研 DSL，而是**一个内嵌脚本语言 + 一大堆 C++ 绑定**。

每个 `.nut` 对应**一个单位的逻辑**：

| 文件名 | 是什么 |
| --- | --- |
| `character/<职业>/<技能>/<技能>.nut` | 技能状态机（`checkExecutableSkill_*` …） |
| `character/<职业>/<技能>/po_*.nut` | 该技能生成的「被动对象」（子弹/法阵/电链），自己有 `onProc_*` |
| `character/<职业>/ap_*.nut` | 「附加体」逻辑（护盾、buff、跟随特效） |
| `character/<职业>/<职业>_common.nut` | 该职业的公共工具函数（给技能脚本调用） |
| `character/<职业>/<职业>_header.nut` | 常量/状态 ID 定义 |
| `character/<职业>/<职业>_load_state.nut` | 注册哪些函数名（`sq_AddFunctionName`） |
| `passiveobject/...`、`appendage/...`、`common.nut`、`dnf_enum_header.nut` | 同上的公共部分 |

技能脚本的回调顺序（引擎调，脚本实现）：

```
checkExecutableSkill_X(obj)   按键后问"能不能放"
checkCommandEnable_X(obj)     普攻/连招中问"能不能用这个技能打断"
onSetState_X(obj, state, datas, isResetTimer)   进状态：按 substate 选动画/算速度/发对象
prepareDraw_X(obj)            绘制前
onProc_X(obj)                 每帧（客户端+服务器都跑）
onProcCon_X(obj)              每帧（只控制端跑）
onKeyFrameFlag_X(obj, flag)   动画关键帧事件
onEndCurrentAni_X(obj)        当前动画播完
onEndState_X(obj, newState)   离开状态（清 buff/音效/进度条）
onAfterSetState_X(...)        状态设置完成后的收尾
```

一个 `STATE_X` 内部再分 `substate`，靠 `sq_IntVectPush(n)` + `sq_AddSetStatePacket(STATE_X, PRIORITY, true)` 自己切段。

## 1. 交付物

对清单里**每一个** `.nut`，产出一个 `.gd`：

```
输入：sqr/character/atmage/firepillar/firepillar.nut
输出：sqr_gd/character/atmage/firepillar/firepillar.gd
```

目录结构完全对齐（`sqr/` 前缀去掉）。**不要**产出别的路径，**不要**动别人的文件。

每个文件的结构：

```gdscript
## 源文件：sqr/character/atmage/firepillar/firepillar.nut（Squirrel / CP949）
## 功能：<2~4 句中文，说清楚"这个脚本干什么、被谁触发、产生什么效果">
## 关键点：<可选：状态机分段 / 数据通道 / 与哪个被动对象配合 / 原脚本的坑>
extends SqrScript

# ---- 常量（原脚本顶层的 slot 赋值）----
const STATE_FIREPILLAR := 260      # 说明
...

## <每个函数一句话：引擎什么时候调它、它做什么>
func onSetState_FirePillar(obj, state, datas, isResetTimer) -> void:
	...
```

## 2. 语法映射表

| Squirrel | GDScript | 备注 |
| --- | --- | --- |
| `X <- 0`（顶层） | `const X := 0` | 顶层 slot 都是常量；若脚本里改过它就用 `var X := 0` |
| `local x = 1` | `var x = 1` | 不要加类型标注（原脚本是动态类型） |
| `function f(a, b)` | `func f(a, b) -> void:` / `-> bool` / `-> Variant` | 有 `return false/true` 用 `-> bool`，有 `return 值` 用 `-> Variant`，纯副作用用 `-> void` |
| `if (a) { ... } else { ... }` | `if a:\n\t...\nelse:\n\t...` | 去掉括号，用缩进 |
| `for (local i = 0; i < n; i++)` | `for i in range(n):` | 递增 1 的常见形式 |
| `for (local i = 0; i < n; i += 2)` | `for i in range(0, n, 2):` | 步长非 1 |
| `foreach (v in arr)` / `foreach (k, v in tbl)` | `for v in arr:` / `for k in tbl:` | 6 处 |
| `while (a) { }` | `while a:` | |
| `a && b` / `a \|\| b` / `!a` | `a and b` / `a or b` / `not a` | |
| `a == null` / `if (!a)` | `a == null` / `if not a:` | |
| `arr.len()` / `str.len()` | `arr.size()` / `str.length()` | |
| `arr.append(x)` / `arr.push(x)` | `arr.append(x)` / `arr.push_back(x)` | 原地改，别改语义 |
| `delete tbl[k]` | `tbl.erase(k)` | 1 处 |
| `switch (x) { case 1: ... }` | `match x:\n\t1:\n\t\t...` | 6 处；注意 Squirrel 的 `case` **不贯穿**，`match` 也不贯穿，等价 |
| `a ? b : c` | `b if a else c` | 12 处，注意优先级 |
| `x.tofloat()` / `x.tointeger()` | `float(x)` / `int(x)` | |
| `"a" + b`（拼串） | `"a" + str(b)` | Squirrel 会自动转字符串 |
| `format("%d", x)` | `"%d" % x` | |
| `print("x: %d" + x)` | `print("x: %d" % x)` | **原脚本这里其实是 bug**（`%d` 早被格式化掉），保留行为并加注释 |
| `this.x` | `x`（同类内）或 `self.x` | 3 处 |
| `base.foo(x)` | `xg.foo(self, x)` + 注释 `# 原: base.foo(x)（Squirrel 父类调用）` | 1 处 |
| `setTimer(t)`（71 处！） | `xg.setTimer(self, t)` + 注释 | 引擎的延时回调，不是标准库 |
| `::CONST` / 全局常量 | 原样大写常量名 | 都在 `dnf_enum_header.nut` |
| `assert(...)` | `assert(...)` | 保留 |

**不要**给函数参数加类型（`obj: Sf85Player` 之类）——原脚本操作的是引擎对象，加了类型反而编译不过。

## 3. 注释规范（这是本任务的核心价值）

1. **文件头**必须有 `## 源文件：`、`## 功能：`（2~4 句中文），必要时 `## 关键点：`。
2. **每个函数**上方一行 `##` 注释：说清「谁调用它 / 什么时候 / 干什么」。
3. **韩文注释**：必须译成中文；原文另起一行保留：
   ```gdscript
   # 首次锁定目标时的 Y 轴范围（上下都算）
   # 原: 처음 타겟팅시 Y축 범위 (상하 포함)
   ```
4. **英文注释**：译成中文，原文用行尾 `（原: ...）` 附上（短的就直接译）。
5. **没有注释但逻辑不直白的地方**（位运算打包、`IntVect` 传参顺序、`getVar()` 槽位用途、
   魔数 ID、被动对象 ID、音效句柄），补一行 `# 【译注】...` 说明。这是重点：
   **宁可多解释一句，也不要读者去猜**。
6. **原脚本明显写错/可疑的地方**（下标用错常量、条件恒真、复制粘贴残留），
   保留原逻辑，用 `# 【原文 bug】...` 标出来。
7. 无用的分支（`// SUB_STATE_X 서브스테이트 작업` 这类空壳）→ `pass` 并保留翻译：
   ```gdscript
   elif substate == 3:
       pass   # 原: SUB_STATE_..._3 서브스테이트 작업（此处未实现）
   ```

## 4. 绝对不能做的事

- ❌ 改标识符名（`SUB_STATE_ATCHAINLIGHTNING_0`、`SKL_CL_SD_1` 都要原样保留）。
- ❌ 改字符串字面量：音效标签 `"MW_CHAINLIGHT"`、动画名、`%04d` 模板、路径、`"nograb"` 之类的
  var 组名 —— 一律原样。
- ❌ 改数字：技能 ID、被动对象 ID（`24241`）、`7576` 音效句柄、状态优先级。
- ❌ 「优化」逻辑：不合并函数、不删死代码、不提前 return、不改循环边界。
- ❌ 引入 `class_name`、`@export`、`preload`、类型标注、`await`。
- ❌ 加 `xg.` 前缀：跨文件调用**原样写**（如 `addElementalChain_ATMage(obj, ENUM_ELEMENT_LIGHT)`），
  后续有统一的后处理脚本负责加前缀。
- ❌ 一次读很多文件：**按清单一个个读、一个个写**。大文件（>20 KB）用
  `read` 的 `offset`/`limit` 分段读，别整篇灌进上下文。

## 5. 自检（每个文件写完都要做）

```bash
cd /home/sunmingze/dnf_like
python3 tools/sqr_check.py sqr_gd/<相对路径>.gd
```

`tools/sqr_check.py` 会检查：文件头三行是否齐全、是否有 `extends SqrScript`、
括号/引号是否配平、是否残留 `<-` / `local ` / `function ` / `&&` / `||` / `!` 、
是否把韩文原文丢掉了（原文保留行数 ≥ 韩文注释行数才通过）。
**红了的文件必须修到绿**；确实无法修的（比如需要人工判断的原脚本 bug），在报告里写清楚。

## 6. 报告

每个 agent 产出 `analysis/sqr/reports/<组名>.md`：

```markdown
# <组名> 翻译报告
完成：N/N 个文件
## 文件对照
| 文件 | 一句话功能 | 难点/坑 |
| --- | --- | --- |
## 发现的跨文件依赖
- `firepillar.nut` 调用 `xg.` 之外的公共函数：`addElementalChain_ATMage`（来自 atmage_common.nut）
## 需要人看的点
- ...
```

## 7. 顺序建议

清单里先做**小的、结构简单的**（`po_*.nut`、`ap_*.nut`，200~2000 B），
再做大的（`*_common.nut` 30~60 KB，要分段读）。这样前面几份就能校准风格。

## 8. 后处理（agent 不用做，统一由脚本跑）

按顺序，每批翻译完在仓库根目录执行：

```bash
python3 tools/sqr_dedupe_consts.py   # 删掉与 SqrConsts 重名的 const（会报 already exists）
python3 tools/sqr_stubs.py           # 重新生成 sqr_script.gd 的宿主桩表（479 个，16 参）
python3 tools/sqr_xref.py            # 给跨文件公共函数调用补 xg. 前缀 + var xg := SqrGlobals.new()
rsync -a --delete --exclude '.godot' sqr_gd/ client//sqr_gd/
XDG_DATA_HOME="$PWD/.tmp_udata" GODOT_PROJECT=$PWD/client \
  ./tools/godot.sh --headless --script res://tests/check_sqr.gd   # 权威判据：失败数必须为 0
```

**判据只看 `tests/check_sqr.gd` 的「失败 0 个」。** `--editor --quit` 日志里的
`Could not resolve class "SqrScript": Cyclic reference` / `Identifier "STATE_*" not declared`
是导入顺序造成的假阳性（脚本在 class cache 建成前被加载），运行时逐个 `load()` 正常。

## 9. 已知坑（翻译时照着避）

| 现象 | 处理 |
| --- | --- |
| `local var = obj.getVar()` | `var` 是 GDScript 关键字 → 改名 `sq_var` |
| 同一函数里第二个同名 `local` | 改成普通赋值（不加 `var`） |
| 文件里自己 `const` 了 `STATE_*`/`SKILL_*`（**头文件里的**） | 常量都在基类 `SqrConsts` 里，删掉（后处理也会删） |
| 文件顶层自定义常量（`HSS_SUB_STATE_*`、`ENUM_PIC_*` 这类本文件专属的） | **必须保留声明**，基类里没有，删了会报 `Identifier not declared` |
| 定义了与 `sq_` 宿主绑定同名的函数（`sq_AddFunctionName` 等） | 照原样定义，基类刻意不提供同名桩 |
| 引擎入口函数与桩同名（如 `sq_InitFrameIndices`） | 改名 `entry_sq_InitFrameIndices(obj)` + `# 【译注】` |
| 顶层可执行语句（`loadstate.nut` 这种） | 包进 `func _init()` + `# 【译注】` |
| 小写错拼的绑定（`sq_isMyControlObject`/`sq_setShake`/`sq_ani_IsEnd`/`sq_SetCurrentAttacknUpForce`） | 原样保留，不纠正拼写（宿主两套都要有） |
| `CNSquirrelAppendage.xxx(...)` / `IRDSQRCharacter` | 宿主全局对象，原样写，已在 `SqrConsts` 里占位 |
