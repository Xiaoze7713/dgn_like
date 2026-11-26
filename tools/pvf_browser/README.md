# PVF 34 浏览器（本地 web UI）

不用装任何依赖，浏览最新国服客户端的 `Script.pvf` 全量内容（6,288,780 条）。

## 起来

```bash
cd /home/sunmingze/dnf_like
bash tools/pvf_browser/start.sh          # 起在 http://127.0.0.1:8770
```

Windows 侧的浏览器直接开 `http://127.0.0.1:8770`（WSL2 的 localhost 转发）。开不通就用
`python3 tools/pvf_browser/serve.py --host 0.0.0.0 --decode`，然后用 WSL 的 IP 访问。

## 能干什么

- 左侧按目录浏览（520,799 个目录，6,288,780 个文件），目录带递归条目数/字节数
- 点文件看内容：`dtype=1` 的 token 流自动解码成标签文本（`[name]` / `[grade]` …），
  带本地化引用自动还原（`<13::name_10000039>` → `使徒卡恩 卡片`）；`dtype=3` 按 UTF-16 解；
  二进制可以切「原始」看 hexdump
- 搜索：**路径**（子串）或**内容**（正文子串，如 `isSkillCooltime`、`[executable states]`）
- 右侧可一键复制路径（贴给 Codex 或自己写脚本用）

## 三个文件

| 文件 | 作用 |
|---|---|
| `serve.py` | HTTP 服务 + 4 个 JSON 接口（`/api/stats`、`/api/tree`、`/api/file`、`/api/search`） |
| `index.html` | 前端（原生 JS，无 CDN） |
| `build_tree.py` | 从条目表派生目录索引 `pvf34.tree.sqlite`（42 秒，只在重建库后需要跑一次） |

## 依赖的数据（已生成）

- `analysis/pvf-new/pvf34.sqlite` —— 全量条目 + 解压后数据（12 GB）
- `analysis/pvf-new/pvf34.tree.sqlite` —— 目录索引（1.5 GB）
- `analysis/pvf-new/inner/Script.inner.pvf` —— 解完外层的 PVF（850 MB），`--decode` 时读它的字符串池

这些都能重建，见 `docs/PVF-NEW-FORMAT-34.md`：先 `tools/pvf_new_unwrap.py` 解外层，
再 `tools/pvf_new_db.py` 建库，再 `build_tree.py` 建索引。

## 命令行替代品

不想开界面时：

```bash
python3 tools/pvf_q.py ls skill/gunner            # 列目录
python3 tools/pvf_q.py cat skill/gunner/activation.skl
python3 tools/pvf_q.py find crouchex              # 按路径找
python3 tools/pvf_q.py grep 'isSkillCooltime'     # 按内容找
python3 tools/pvf_q.py sql "select ..."           # 直接 SQL
python3 tools/pvf_new_extract.py --prefix skill/ --extract out/   # 批量导出
```
