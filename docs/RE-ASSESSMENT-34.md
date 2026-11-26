# 关于「要不要逆向 DNF.exe」的可行性评估（34.3.13.22）

结论：**不要逆 dnf.exe，收益/风险都不划算**，而且复刻游戏逻辑根本不需要它。下面是实测依据。

## 1. 客户端二进制现状（实测）

| 文件 | 大小 | 保护 |
|---|---|---|
| `DNF.exe` | 280,795,768 B | 10 个段**全部命名为 `.std`**，虚拟大小是文件体积的数倍 ⇒ 整体加壳/压缩；`nkpi`（101,233,494）、`mAIn`（21,770,831）两处命中都夹在高熵数据里，是压缩块里的巧合串 |
| `DNFBase.dll` | 38,170,512 B | 常规段 + **`.tvm0`（29 MB）= VMProtect**；无 `iNfO/mAIn/stAs/stWs/Gidx/HSrm/nkpi` 任何明文 |
| `nengine.dll` | 651,264 B | 干净 PE，纯图像/动画引擎（`CNImagePack`/`NeoplePack_Bill`/zlib/png） |
| `AntiCheatExpert/` | 约 170 MB | 腾讯 ACE：`ACE-BASE.sys` 4.1 MB、`ACE-CORE.sys` 3.9 MB、`ACE-CORE.sys2/sysa/sysa2`、`ACE-Base64.dll` 83 MB、`ACE-DFS64.dll` 31.6 MB… **内核驱动级** |

- 静态 RE 成本：VMProtect 虚拟化 + 280 MB 加壳主程序，个人级别基本不可行（要写/买 devirtualizer，且要能定位到具体 handler）。
- 动态 RE 成本：ACE 是内核态、带反调试/反内存读写，附加调试器 = 触发反作弊（封号），不是"技术上能不能"的问题。
- 法务成本：国服用户协议 + 反不正当竞争，改动/逆向客户端比"读数据 + 自己写实现"风险高得多。

## 2. 关键判断：复刻逻辑不需要 exe

PVF 已经给出 6,288,780 个条目 / 解压 7.1 GB 的**全部策划与逻辑数据**，其中：

- 数值/行为参数：`.equ`（装备）、`.stk`、`.skl`（技能）、`.act`（动作）、`.atk`（攻击判定）、`.ani`（动画）—— 标签式文本，tag 名自带语义。
- **AI 逻辑**：`.ai` 24,644 个（词条式行为树，已解码成可读文本）、`.lua` 4,496 个（状态机脚本），连框架与枚举都在 PVF 里（`clientonly/lua/ai/*`）。
- 文本/本地化：38 张 `string/*.chn.str`（535 MB）。

exe 里真正"没有写进数据"的只有三样：**伤害公式的最终实现细节、物理/硬直常数、网络协议**。这三点有更便宜的替代：

1. **录像 oracle**：客户端自带 `Replay/` 5,833 个 `.rep`。回放 = 输入流 + 结果，可用来反推公式与常数，零风险。
2. **开源服务端**：`gitgud.io/RicardoLz/115`（dfo-lan，公开）是一套 110us 谱系的**完整 Go 服务端**，含 `game / world / dungeon / character / inventory / loot / quest / pvp / npcpresence / accountname / cashshop …` 等业务包——客户端↔服务端协议这块已经被别人做过一轮，可按它的结构搭骨架，再按国服版本差调整。
3. **数据自证**：`.atk/.act` 里本来就写着攻击框、伤害倍率、硬直/浮空参数，公式里的"魔法数字"大多能直接读到。

## 3. 建议的路线

| 优先级 | 做什么 | 收益 |
|---|---|---|
| P0 | 用 `analysis/pvf-new/pvf34.sqlite` 把 `.equ/.skl/.stk/.mob/.act/.atk` 解析成结构化表 | 复刻的 90% 素材 |
| P0 | 照 `clientonly/lua/ai/*` + `boss_spiderprince` 样例包实现 AIBridge/MyInfo/EnemyInfo，直接跑官方 AI 脚本 | 怪物行为 1:1 |
| P1 | 解析 `Replay/*.rep` 做数值回归 | 校验公式，不用碰 exe |
| P2 | 参考 dfo-lan 服务端做协议层 | 联机骨架 |
| ✗ | 逆 `DNF.exe` / 绕过 ACE | 成本极高、风险极大、且非必需 |

一句话：**数据层已经完全打开，逻辑层（AI 框架 + 行为树）是可读的，剩下的实现细节用录像和开源服务端补，比啃 VMProtect 便宜两个数量级。**
