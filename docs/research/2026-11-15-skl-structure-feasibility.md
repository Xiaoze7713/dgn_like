# 把 `.skl` / `.equ` / `.atk` 结构化成表：可行性评估

- 标题：PVF 声明式数据的结构化方案（不实现，先评估）
- 研究者：DSH
- 日期：2026-11-15
- 任务 ID：T-20261115-003（草拟）
- 状态：待决策（是否实现、由谁实现）
- 背景：`2026-11-15-squirrel-removal.md` 已确认脚本全部移除，逻辑=数据；本文件评估"把数据读成表"的成本。

## 结论先说

**可行，而且比想象中便宜**——因为数据本身已经是 `[标签] 值` 的树，缺的只是一个通用解析器 + 一份字段表。没有需要逆向的二进制结构。

- 通用 tag 树解析器：约 2 小时（`decode_script` 已经把 token 流还原成带 `{`/`}` 的文本，正则栈走一遍即可）。
- 每类文件一份字段表（schema）：`.skl` 约 1 天、`.equ` 约半天（含 `[if]/[then]` 触发器）、`.atk` 约半天。
- 风险点只有一个：跨文件引用（技能 → 攻击信息 → 特效），需要 id 映射；不影响单表产出。

## 观察（可验证事实）

| # | 观察 |
|---|---|
| A1 | `.skl` 6,739 个、`.equ` 383,719 个、`.atk` 约 7 万个区（每文件多个 `[attack info]` 块）。全部由同一套 5 字节 token 流编码（`[1B type][i32 value]`），`tools/pvf_new_extract.py` 的 `decode_script` 已经能还原成文本。 |
| A2 | `.skl` 共 **240** 种标签。出现最多的：`[type]` 1831、`[name]` 747、`[explain]`/`[basic explain]` 726、`[static data]` 636、`[level info]` 624、`[required level]`/`[maximum level]` 596、`[skill class]` 590、`[damage group]` 577、`[icon]` 575、`[base attack]` 513、`[option group]` 460、`[multi hit]` 383、`[pvp]` 367、`[damage info]`/`[damage]` 353、`[attack list]` 353、`[cool time]` 347（800 个样本）。 |
| A3 | `.atk` 是重复的 `[attack info]` 块，块内 `[damage] 6800`、`[attack type] [physic]`、`[attack enemy] 1`、`[damage reaction] [push aside] 50`、`[hit info] [stun] 100 70 500`（概率/时间/等级）。纯数值，无表达式。 |
| A4 | `.equ` 的 `[if]…[/if][then]…[/then]` 是触发器：条件 14 种主要标签、动作 14 种主要标签（详见 appendage 报告 A6/A7）。 |
| A5 | 语言文本不在数据里：`[name]` / `[explain]` 的值是 `<13::name_10000039>` 引用，指向 `string/<Table>.chn.str`（38 张表，UTF-16）。 |
| A6 | 图形资源引用同样是文本：`[icon] 'Character/gunner/Effect/SkillIcon.img' 666` = NPK 文件 + 图标索引，和经典 NPK 一致（`tools/npk_parser.py` 可直接读）。 |

## 建议的产出物

三张表 + 一张关联表（SQLite 或 jsonl 都行）：

```
skills(id PK, job, path, type, cool_time, max_level, required_level, class, icon_npk, icon_idx, name_key)
skill_levels(skill_id, level, required_level, static_data_json)      -- [level info] 每级一行
skill_triggers(skill_id, cond_json, act_json, source_path)            -- [if]/[then]
attacks(atk_id PK, index, damage, attack_type, element, push_aside, hit_status_json)
skills_attacks(skill_id, atk_id, group, level)                        -- [damage group]/[attack list]
equip(id PK, path, slot, rarity, level, cool_time, icon_npk, icon_idx, name_key)
equip_triggers(equip_id, cond_json, act_json, appendage_ids_json)
appendages(apd_id PK, path, type, duration, buff, int_data_json, string_data_json)
```

值类型映射（唯一需要小心的地方）：`[标签]` 后面跟的行可能是
- **空**（纯开关，如 `[passive]`、`[weapon damage apply]`）；
- **整数**（`[cool time] 5000 5000`）；
- **浮点**（`[maintain MP] 1.60 17.70`）；
- **反引号字符串**（`` `[stand]` ``、`` `myself` ``）；
- **嵌套块**（`{` / `}`，例如 `[attack info]` 内部再有 `[damage reaction]`）。

所以解析器只要按行首 `[` 判标签、按 `` ` `` 判字符串、按 `{`/`}` 维护栈，就能覆盖全部 240 种标签，不需要为每个标签写特例。

## 与新作设计的关系

- 这张表是"复刻原作数值"的唯一入口：有了它，新作的技能/装备可以用原作数值做回归对照，而不需要手工抄。
- 对新作**不建议**直接照抄标签名（DNF 的 `[growtype maximum level]`、`[skill fitness growtype]` 这类是历史包袱）；建议先导出成中立 schema，再映射到已确认的设计（六大道途 / 16 槽位 / 威能）。
- 需要用户决定：先做哪一类。建议顺序 `.skl`（技能，最影响手感）→ `.equ`（装备，最重要）→ `.atk`（战斗判定细节）。

## 结论与交接

- 可做；建议交给 Codex 作为"数据导入器"实现（属工程实现），DSH 输出 schema 定义与样例校验集。
- 我可以先给一份**样例校验集**（每类 20 个文件的人工核对结果），让实现方有 ground truth。
- 未解决问题：`[static data]` 与 `[level info]` 的列含义需要逐字段对照（目前只知道是"每级一行、多列整数"）；`[damage group]` 到 `[attack list]` 的编号规则未完全拆清。
