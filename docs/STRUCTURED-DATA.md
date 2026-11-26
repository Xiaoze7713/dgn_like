# 结构化数据集（P0.8）

`export/text/` 是给人读的（6.2 GB、字段是「标签 + 值序列」）。做数值表、生成引擎数据、跑交叉校验时反复写正则是浪费——
`tools/pvf_structured.py` 用 `pvfReader.list2Dict` 把标签流文件直接转成**每行一个实体的 JSONL**，全部 gzip 后只有 **30 MB**。

```bash
.venv/bin/python tools/pvf_structured.py --jobs 10                 # 全部扩展名
.venv/bin/python tools/pvf_structured.py --exts chr,skl,atk --jobs 8
.venv/bin/python tools/pvf_structured.py --exts mob --limit 100 --force
```

产出 `export/structured/<ext>.jsonl.gz`，每行：

```json
{"path": "monster/casillas/casillas.mob",
 "data": {"[name]": ["征服者卡西利亞斯"], "[width]": [40, 10], "...": []}}
```

解析失败的文件落成 `{"path": ..., "error": "..."}`（一行，不中断整批）。

---

## 1. 实测规模

| 文件 | 实体数 | gz 体积 | 备注 |
|---|---|---|---|
| `act.jsonl.gz` | 77,511 | 5.5 MB | 怪物/物件动作编排 |
| `equ.jsonl.gz` | 108,645 | 8.2 MB | 装备 |
| `als.jsonl.gz` | 77,490 | 5.1 MB | 动画标记 |
| `obj.jsonl.gz` | 24,436 | 0.7 MB | 被动对象 |
| `atk.jsonl.gz` | 18,877 | 0.5 MB | 攻击属性 |
| `mob.jsonl.gz` | 4,042 | 0.7 MB | 怪物 |
| `skl.jsonl.gz` | 4,005 | 2.7 MB | 技能 |
| `qst.jsonl.gz` | 3,852 | 0.6 MB | 任务 |
| `map.jsonl.gz` | 5,800 | 1.8 MB | 房间 |
| `npc.jsonl.gz` | 811 | 0.4 MB | NPC |
| `dgn.jsonl.gz` | 625 | 0.1 MB | 副本 |
| `etc/cre/apd/twn/til/ptl/key/ui/…` | 各数百~数千 | 合计 ~7 MB | 其余 |

**总 30 MB**（vs `export/text` 6.2 GB）。错误率：`act` 1 / `als` 5 / `map` 3 / `etc` 1 / `cre` 1，其余 0。

---

## 2. 怎么查

```python
import gzip, json
def load(ext):
    return {r["path"]: r.get("data", {}) for r in
            map(json.loads, gzip.open(f"export/structured/{ext}.jsonl.gz", "rt", encoding="utf-8"))}

mob = load("mob")
d = mob["monster/goblin/goblin.mob"]
print(d["[level]"], d["[name]"])          # [1, 6] ['哥布林']
```

命令行速查（不写代码）：

```bash
# 找所有近战、等级上限 <= 20 的怪
zcat export/structured/mob.jsonl.gz | jq -c 'select(.data["[level]"][1] <= 20) | .path' | head

# dgn 6 的 boss 房坐标
zcat export/structured/dgn.jsonl.gz | jq -c 'select(.path=="dungeon/act1/sunderlandpoison.dgn") | .data["[boss map]"]'
```

---

## 3. 已知取舍（别当权威 JSON schema 用）

- `list2Dict` 会把重复标签聚成数组、并保留**标签名**（`[name]`），所以字段是「PVF 标签原文」，不是英文 schema——这正是我们要的（可回溯到 `docs/PVF-FORMAT.md` 的标签语义）。
- 嵌套子块会变成 `{"[map specification]-2": [...]}` 这类**后缀编号键**（PVF 原样，`-N` 表示同标签的第 N+1 次出现），读的时候按前缀分组。
- 值为字符串列表时保序；但**同名标签重复出现时不保证与原文位置一一对应**，需要严格顺序的场合（例如 `.act` 的事件流）请回 `export/text/` 或 `export/ani/`。
- 文本已过 stringtable / n_string 二次替换（`type 9`），所以看到的是中文而不是 `name_100113`。
