# dnf_like 项目协作入口

开始本项目的新任务或讨论时，先读取独立协作知识库中的设计基线、决策记录和相关任务/研究文档，再进行涉及玩法、范围或实现的判断：

`E:\relocated\Documents\Codex\2026-11-15\referenced-chatgpt-conversation-this-is-an\outputs\dnf-agent-collaboration`

建议先读 `README.md`、`AGENTS.md`、`design/game-design.md` 和 `design/decision-log.md`。其中“已确认”“建议”“待决策”状态必须保持区分；不得将建议或推断当成已确认需求。根据当前任务再读相关 `tasks/` 或 `research/` 文档。

该路径是当前 Windows 会话可访问的位置。除非确认共享/同步状态，不要假设它与 WSL 副本自动同步，也不要在其他副本分别维护内容。若路径不可访问，继续处理不依赖该知识库的工作，并明确说明无法读取；不要自行创建替代知识库或覆盖设计决策。

## 能力索引（2026-11-25）

- 每个实现目录维护 `README.md`，写职责、入口签名、调用链、坑与验证命令；改函数/常量时同一次改动里更新。
- 从 `game/world/README.md` 开始按层级下钻；新增目录或对外入口必须补索引。
