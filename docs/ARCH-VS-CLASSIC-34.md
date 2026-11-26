# 34.3.13.22（2025 国服）vs 经典版：架构对比（PVF 已解开后重写）

- 新端：`dnf_latest`，`game_version 34.3.13.22`，`Script.pvf` 850,304,454 B → 6,288,780 条目、解压 7,142,625,379 B。
- 老端基准：`sf115`（经典 PVF，明文路径，1,460,792 条目 / 779,453,396 B / 均值 533 B）。
  ⚠️ 这是**老私服端**（版本约 10 年前，例如里面的 `bloodfire` 技能在当前客户端已不存在），所以"条目数 4.3 倍"混了版本差，不等于架构变动；**容器与脚本体系的差异才是架构差异**。

## 一句话结论

| 层 | 结论 |
| --- | --- |
| 资源容器（NPK/IMG） | **没变**，老工具直接可用 |
| PVF 容器 | **整体换代**：分段 AES + `sk.dat` 钥匙链 + `nkpi` + 分组 zlib + LCG 流密码 + 字符串池 |
| 脚本语言 | **Squirrel（`.nut`）被彻底移除**，客户端侧逻辑改为 **Lua（`.lua`）** |
| 文本 | 从"脚本内联字面量"改为 **`<N::key>` 引用 + `string/*.chn.str` 表**（外置本地化） |
| 内容组织 | 新增 **`contents/<年份>/<内容包>/`** 与 **`live/event/<地区>/<年份>/`** 的内容包化布局 |

## 1. 资源容器层：未变

| | 经典版 | 34.3.13.22 |
| --- | --- | --- |
| NPK 头 | `NeoplePack_Bill\0` + u32 条目数 | 相同 |
| 索引项 | 264 B：i32 off / i32 size / 256 B XOR 名 | 相同 |
| 名字 XOR 键 | `(b"puchikon@neople dungeon and fighter " + b"DNF"*256)[:255] + b"\x00"` | 相同 |
| IMG | `Neople Img File\0` + 版本 + 帧表 | 相同（`sprite.NPK` → `open_img('sprite/login.img')` v2/20 帧直接读出，`verify_ok=True`） |

## 2. PVF 容器：整体换代

| | 经典版 | 34.3.13.22 |
| --- | --- | --- |
| 外壳 | 56 B 头 + `ror32` 混淆目录树 | **`sk.dat`（23×128 B RSA）= 82 把段钥匙；每 10 MiB 段首 0x2800 B AES-256-CBC** |
| 容器头 | 明文 | `nkpi` 48 B，经 LCG 流密码 `decryptProtected("iNfO")` |
| 路径 | 索引里直接存 GBK 路径串 | **索引里没有任何路径串**：路径 = 目录名 + 文件名两个"池内指针"，池为 zlib + LCG 加密的 UTF-16 大池（`stWs` 509 MB；`stA` 空） |
| 索引 | 变长条目（fileNumber/path/长度/crc32/偏移） | 定长 24 B：`[nameOffset][pathOffset][chunkIndex][dataOffset][dataSize][dataType]` |
| 数据 | 每文件独立 zlib + crc32 | **按 chunk 分组**（96,775 组），每组 `zlib` 后再 LCG 流密码 `mAIn`；无 crc32 |
| 额外结构 | 无 | 哈希流 `HSrm`（59 MB，`[n][n×8B][m][m×4B]`）、组表 `Gidx`（96,775×8） |
| 压缩率 | ~1× | 596 MB body ↔ 7.14 GB 明文（**≈ 12×**） |

对工具链的影响：老解包器全线失效；新工具见 `docs/PVF-NEW-FORMAT-34.md`。

## 3. 脚本语言：Squirrel → Lua

| | 经典版 sf115 | 34.3.13.22 |
| --- | --- | --- |
| `.nut`（Squirrel） | **2,489** 条（`sqr/character/<job>/<skill>/*.nut` 等） | **0** |
| `.lua` | 114 | **4,496** |
| 老 `.nut` 路径在新端能否找到同 stem | — | **0 / 2,489** |

Lua 分布（按顶层）：`contents/` 3,293、`aicharacter/` 427、`monster/` 380、`live/` 370、`clientonly/` 26。

实测样例（`dataType=3`，UTF-16 文本）：

- `monster/kcontents2/siroco_raid_challenge/phase1/named/raina/ai/action.lua`
  ```lua
  local L = {};
  require("/ClientOnly/Lua/AI/AIBaseScripts.lua");
  function L.begin_pattern()
      if Patrol:isTargetAttackArea(250, 100, 100, 100) then
          if Common:getrandomIsPercent(40) then
              if Battle:isSkillCooltime(0) == false then Idle:setAction(0); return end
  ```
- `aicharacter/pvp/easyai/swordmanai_98/ai/skillcommand.lua` — `function SkillCommand.Init()`、`SubState_*` 常量表。

⇒ API 风格与 .nut 时代完全不同（`Patrol:` / `Battle:` / `Idle:` / `Common:` 命名空间 + `require`），是**换了一个脚本运行时**，不是"改了扩展名"。

**重要缺口**：老版 `sqr/character/<job>/<skill>/<skill>.nut` 里那套技能/被动行为脚本（`sq_AddSetStatePacket` 之类）在新客户端 PVF 里**完全不存在**；新端 `skill/<job>/` 只有 `.skl` / `.etc` 这类**数据**（如 `skill/swordman/berserkercancelableskilllist.etc`）。要复刻战斗逻辑，这层要么来自服务端、要么得从 `.skl` + `.act` + 客户端二进制反推。

## 4. 文本：外置本地化

| | 经典版 sf115 | 34.3.13.22 |
| --- | --- | --- |
| `[name]` 等字段 | **内联字面量**（老端实测该条是 `混沌 · 使徒卡恩 卡片`） | **`<N::key>` 引用**，如 `<13::name_10015138>` |
| 文本表 | 分散的 `<目录>/<目录>.chn.str`（Big5，很小，如 `stackable/stackable.chn.str` 仅 204 B，只覆盖个别 key）+ `stringtable.bin` | **集中** `list/n_string.lst` → 38 张 `string/<Name>.chn.str`（UTF-16，`key>文本`，`string/stackable.chn.str` 单个 **38,399,008 B**） |
| 语义 | 字面量为主，`.chn.str` 只是汉化覆盖表 | 字面量**全部移除**，文本只能经引用号取表 |
| 新增 token | — | tag 流新增 **type 8**（值字符串；服务端 Go 实现里尚未处理） |

实测：`stackable/10015001/10015138.stk` 的 `[name]` 在老端是字面量 `混沌 · 使徒卡恩 卡片`，新端是 `<13::name_10015138>`，查 `string/stackable.chn.str` 得 `使徒卡恩 卡片`。

⇒ 好处：一份数据多语言；代价：脚本必须连表才能读（`tools/pvf_new_extract.py` 已内建）。

实测解析覆盖率（导出 40,000 个脚本、`127,297` 处反引号字符串）：**残留在结果里的未命中引用只有 3,919 个（≈1–3%）**，主要来自 `string/skill.chn.str`（2,283）与 `string/stackable.chn.str`（1,326）。未命中原因是**表与脚本的键不同步**（例：脚本里是 `crouch_ex2_name`，表里只有 `crouch_ex_name`），不是算法问题；客户端遇到这种键同样取不到文本。

## 5. 内容组织：内容包化

- 新端最大顶层目录是 **`contents`（2,948,079 条）**，二级是**年份**：2026 861,852 / 2022 591,786 / 2025 578,518 / 2024 453,652 / 2023 258,144 / 2021 196,037 / system 4,675 / arcadecenter 3,415。
- 三级是**内容包名**：`monstercolosseum_ver3` 156,972、`fallensaintmichaela` 149,204、`aradodyssey` 135,224、`roadofdomination` 85,350、`memoryoffeat2` 53,116、`normaldungeon` 45,290、`apocalypse` 40,748、`skyofthousandseas_scenario` 31,751 ……
- 另有 `live/event/chn/<年份>/<日期_活动名>/...`（如 `live/event/chn/2021/0617_flyingshipstory/...`）。
- 老端没有这两个体系（老端最大是 `equipment` 694,560 / `monster` 369,169 / `passiveobject` 192,420）。

## 6. 数量对比（同口径）

| 后缀 | sf115（老） | 34.3.13.22（新） |
| --- | --- | --- |
| `.ani` | 1,058,561 | 4,241,248 |
| `.act` | 77,511 | 538,737 |
| `.als` | 77,490 | 330,266 |
| `.equ` | 108,645 | 388,146 |
| `.stk` | 28,794 | 199,043 |
| `.skl` | 4,005 | 6,739 |
| `.lst` | 58 | 611 |
| `.nut` | 2,489 | **0** |
| `.lua` | 114 | **4,496** |
| 合计条目 | 1,460,792 | **6,288,780** |
| 明文体量 | 779,453,396 B | **7,142,625,379 B** |

路径交集：**433,689**（占新端 6.9%）；仅新端 5,855,091；仅老端 1,027,103。⇒ 文件名/目录名体系大改（内容包化 + 本地化外置 + 动画集 `.ani.als` 双后缀）。

## 7. 客户端外壳（与 PVF 相关的变化）

| 新增/变化 | 说明 |
| --- | --- |
| `sk.dat` 2,944 B | 82 把段钥匙的 RSA 封装 |
| `dstr.dat` 1,975,200 B | 15,431 个 128 B RSA 块（两种私钥分别解 11,567 / 13,136 块），解出仍随机，用途未定 |
| `config.vfs` 10,272 B | `vfs ` + `daeh` + zlib，启动器/更新器 ini/xml |
| `DolphinPathHdiff/apollo_reslist.flist.gen` | 8,360,112 B，头 u32 = 27,867 = 客户端文件数，正体加密 |
| `audio.xml` 15,433,300 B | 音频表从 PVF 挪到根目录 XML（老端 PVF 里只有 7 个 xml） |
| `nengine.dll` 651,264 B | 图像/动画引擎（`CNImagePack`），**不含 PVF 解析** |
| `OneUp/` 537、`Pandora/` 49、`TCLS/` 38、`AntiCheatExpert/` 35 | Electron 启动器 + 新组件 |
| `DNF.exe` 280 MB / `DNFBase.dll` 38 MB | 均加壳（`.std` 段 / `.tvm0` = VMProtect） |

## 8. 「游戏设计有没有大改」现在能回答到什么程度

有直接证据的：

- **数值/条目层面**可以逐字段 diff 了（`.equ` / `.stk` / `.skl` / `.mob` / `.npc` / `.qst` 全部可读）。
- **战斗脚本层**换运行时（Squirrel → Lua），且客户端不再携带技能/被动行为脚本。
- **文本层**全面外置本地化。
- **内容生产**改为按年份/内容包分目录组织（利于分包更新/热更）。

不能回答的（诚实边界）：

- 老端是 10 年前的私服端，条目数差异主要是版本积累，不能据此说"设计重构"。
- 想要"同一版本的经典格式 vs 新格式"对比，需要一份 34.x 时期的经典格式端（目前手头 `sf110.08` / `sf115` 都是经典格式旧端）。
