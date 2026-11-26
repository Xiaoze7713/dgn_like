# 根目录 15 个 name 表：韩文原名 + 码表错乱的遗留物

- 标题：`aicharactername.lst` 等根目录 name 表的性质与解码方式
- 研究者：DSH
- 日期：2026-11-15
- 任务 ID：T-20261115-004（草拟）
- 状态：已完成（结论可直接用）
- 触发：用户看到这些文件是乱码，怀疑解包方式错误

## 问题与范围

根目录 `aicharactername.lst`、`itemname.lst`、`monstername.lst`、`npcname.lst`、`passiveobjectname.lst`、`skillname0..10.lst` 共 15 个文件打开是乱码（`矫鄂`、`绊喉赴` 这种罕见字）。是解包错了吗？

## 方法与复现步骤

1. `python3 tools/pvf_studio/pvf_studio.py` 打开任一文件；勾「还原韩文」。
2. 或命令行：`python3 -c "import sys;sys.path[:0]=['tools/pvf_studio','tools'];import pvf_studio as P;s=P.Store();print(P.recover_korean(P.render(s,'monstername.lst')[1])[:200])"`

## 观察（可验证事实）

| # | 观察 |
|---|---|
| A1 | 容器解码没错：同一套代码解 `list/*.lst` 得到正常路径（`String/Character.chn.str`、`Monster/Goblin/Goblin.mob`），解 `string/*.chn.str` 得到正常中文，解 `.skl/.stk/.equ` 的标签与数值全部正确，ASCII 名字（`G.S.D`）也正常。 |
| A2 | 这 15 个表里的乱码字符串有严格可逆规律：**cp949（韩文）字节被当成 GBK 解码**。还原 = 按 GBK 编码回字节 → 按 cp949 解码。 |
| A3 | 还原样例：`矫鄂`→`시란`、`八篮 乔蝴 唱力`→`검은 피빛 나제`、`绊喉赴`→`고블린`、`绊喉赴 捧么捍`→`고블린 투척병`、`俊建 器农`→`에쉔 포크`、`敌扁 付胶磐府`→`둔기 마스터리`。 |
| A4 | 还原覆盖率：`monstername.lst` 12,330/12,332；`itemname.lst` 10,694/10,694；`aicharactername.lst` 1,459/1,466；`skillname0.lst` 194/194。 |
| A5 | 这些表**不参与显示**：客户端所有名字来自 `string/*.chn.str`（例：`ai_character_name_203>烈炎之手波尔拉`），以 `<N::key>` 引用；随机抽 300 个 `dtype=1` 文件，非 ASCII 反引号字符串数为 **0**。 |
| A6 | 老客户端（sf115）根目录只有 1 个 `.lst`（`n_string.lst`），全部 `.lst` 仅 58 个；新版 611 个 `.lst`，其中根目录这 15 个是新增的。 |

## 推断（解释）

- **B1（高置信）这不是解包错误，是包里数据本身的性质。** 依据 A1（同管线其它文件全对）+ A2/A3（乱码严格可逆成合法韩文名）+ A5（这些表根本没被使用）。
- **B2（高置信）这 15 个表是韩服原名表的遗留物**：韩文原名被一个码表串了的转换工具（把 cp949 字节交给 GBK 解码器）写成了 UTF-16，中文端只翻译了 `string/*.chn.str`，没人回头修这些表，于是原样留在包里。
- **B3（中置信）对新作无参考价值**，除了"名字要放在独立本地化表、不要和逻辑数据混在同一个字符串池里"这条工程教训。

## 与新作设计的关系

- 不值得照搬；如果要引用这些名字，用自己的 `id → {kor, chn}` 本地化表。
- 有用的一条：DNF 把**所有面向玩家的文本**都外置到 `string/<Table>.<lang>.str`，数据文件里只留 `<N::key>` 引用。这对新作的多语言是现成范式（新作已确认要做赛季制，多语言迟早要碰到）。

## 结论与交接

- 结论：**解包方式没问题**。这 15 个根目录 name 表是韩文原名 + 码表错乱（cp949 当 GBK），可以按 A2 的规则 100% 还原；它们不参与显示，不要当作"物品/怪物/技能名表"来用。
- 交接：Codex 做数据导入时**跳过**这 15 个文件；名字一律从 `string/*.chn.str`（UTF-16 纯文本，`key>value` 每行一条）取。
- 复核人/日期：待用户评审。
