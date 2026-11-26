#!/usr/bin/env python3
"""生成 analysis/00-OVERVIEW.md：从 export/_meta 汇总一份「游戏设计一览」目录。"""
import json
import sqlite3
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "export" / "_meta"
OUT = ROOT / "analysis" / "00-OVERVIEW.md"

# 注册表 → 系统说明
REGISTRY = [
    ("character__character.lst.tsv", "角色（.chr）", "职业基础属性/成长"),
    ("skill__swordmanskill.lst.tsv", "技能 · 鬼剑士", ""),
    ("skill__fighterskill.lst.tsv", "技能 · 格斗家", ""),
    ("skill__gunnerskill.lst.tsv", "技能 · 神枪手", ""),
    ("skill__mageskill.lst.tsv", "技能 · 魔法师", ""),
    ("skill__priestskill.lst.tsv", "技能 · 圣职者", ""),
    ("skill__thiefskill.lst.tsv", "技能 · 暗夜使者", ""),
    ("skill__demoniclancerskill.lst.tsv", "技能 · 魔枪士", ""),
    ("skill__demonicswordman.lst.tsv", "技能 · 黑暗武士", ""),
    ("skill__creatormage.lst.tsv", "技能 · 缔造者", ""),
    ("skill__atswordmanskill.lst.tsv", "技能 · 鬼剑士(决斗)", ""),
    ("skill__atfighterskill.lst.tsv", "技能 · 格斗家(决斗)", ""),
    ("skill__atgunnerskill.lst.tsv", "技能 · 神枪手(决斗)", ""),
    ("skill__atmageskill.lst.tsv", "技能 · 魔法师(决斗)", ""),
    ("skill__atpriestskill.lst.tsv", "技能 · 圣职者(决斗)", ""),
    ("skill__autoskill.lst.tsv", "技能 · 通用自动", ""),
    ("skill__skilllist.lst.tsv", "技能 · 总表", ""),
    ("dungeon__dungeon.lst.tsv", "副本（.dgn）", "地图组/入场条件"),
    ("map__map.lst.tsv", "地图（.map）", "房间/出生点/传送门"),
    ("monster__monster.lst.tsv", "怪物（.mob）", "属性/掉落/AI"),
    ("npc__npc.lst.tsv", "NPC（.npc）", "商店/任务/传送"),
    ("n_quest__quest.lst.tsv", "任务（.qst）", "目标/奖励/对话"),
    ("stackable__stackable.lst.tsv", "可堆叠物品（.stk）", "材料/消耗品/设计图"),
    ("equipment__equipment.lst.tsv", "装备（.equ）", "武器/防具/首饰/时装"),
    ("passiveobject__passiveobject.lst.tsv", "被动对象（.obj）", "陷阱/机关/飞行物"),
    ("appendage__appendage.lst.tsv", "附加体（.apd）", "buff/状态"),
    ("creature__creature.lst.tsv", "宠物（.cre）", ""),
    ("town__town.lst.tsv", "城镇（.twn）", ""),
    ("worldmap__worldmap.lst.tsv", "世界地图", ""),
    ("region__region.lst.tsv", "区域", ""),
    ("itemshop__itemshop.lst.tsv", "商店", ""),
    ("aicharacter__aicharacter.lst.tsv", "AI 角色（APC）", "决斗/副本站台 AI"),
    ("etc__randomoption__randomoption.lst.tsv", "随机词条", "装备洗练"),
    ("etc__independentdrop.lst.tsv", "独立掉落", ""),
    ("pvp_mission__mission.lst.tsv", "决斗任务", ""),
    ("event__bluemarble__bluemarblemap.lst.tsv", "活动 · 大富翁", ""),
]


def count_lst(name):
    p = META / "lst" / name
    if not p.exists():
        return None
    with p.open(encoding="utf-8", errors="replace") as f:
        return sum(1 for line in f if line.strip())


def main():
    db = sqlite3.connect(META / "index.sqlite")
    cur = db.cursor()
    roots = cur.execute(
        "select root, count(*), sum(size) from (select substr(path,1,"
        "case when instr(path,'/')>0 then instr(path,'/')-1 else length(path) end) root, size from files)"
        " group by root order by 2 desc"
    ).fetchall()
    exts = cur.execute("select ext, count(*), sum(size) from files group by ext order by 2 desc limit 24").fetchall()
    total, total_size = cur.execute("select count(*), sum(size) from files").fetchone()
    db.close()

    lines = []
    w = lines.append
    w("# DNF 数据一览（sf115 · 人造神）")
    w("")
    w(f"> 自动生成于 {time.strftime('%Y-%m-%d %H:%M')}。数据源 `data/Script.pvf`（923MB，{total:,} 个文件，{total_size/1024/1024:.0f}MB 解压后）。")
    w("> 本文是**索引**：告诉你在哪找、怎么查、每个系统多少量。深度分析见 `analysis/01-*.md` 起。")
    w("")
    w("## 1. 怎么看")
    w("")
    w("```bash")
    w("export/text/          # 全量可读目录树，路径与 PVF 内一致（追加 .txt）")
    w("export/text/skill/    #   例：技能")
    w("export/_meta/         # 索引/注册表/字符串表")
    w("export/_meta/index.sqlite   # 全量索引，可用 SQL 查")
    w("```")
    w("")
    w("三种查法：")
    w("")
    w("```bash")
    w("# ① 按目录浏览（.txt 就是 PVF 里的标签流原文）")
    w("ls export/text/skill/swordman | head")
    w("")
    w("# ② 全文搜索标签/数值（例：找所有带 [cooltime] 的技能）")
    w("rg -l '^\\[cooltime\\]' export/text/skill --glob '*.skl.txt' | head")
    w("")
    w("# ③ SQL 查索引（例：某目录下最大的文件）")
    w("sqlite3 export/_meta/index.sqlite \"select path,size from files where path like 'monster/casillas/%' order by size desc limit 5\"")
    w("```")
    w("")
    w("## 2. 规模")
    w("")
    w("| 根目录 | 文件数 | 内容 |")
    w("|---|---:|---|")
    desc = {
        "equipment": "装备与时装（.equ）及其动画",
        "monster": "怪物数据 + 动作脚本 + AI + 攻击盒",
        "passiveobject": "被动对象（陷阱/机关/召唤物）",
        "character": "14 个职业的骨架、动画、攻击信息",
        "map": "地图房间（.map）与地块图集（.til）",
        "stackable": "材料/消耗品/设计图（.stk）",
        "creature": "宠物",
        "aicharacter": "APC（决斗/副本站台 AI）",
        "common": "公共特效",
        "skin": "皮肤",
        "sqr": "Squirrel 脚本",
        "n_quest": "任务",
        "skill": "技能（.skl）",
        "appendage": "buff/状态（.apd）",
        "npc": "NPC",
        "ui": "界面",
        "etc": "杂项配置",
        "dungeon": "副本（.dgn）",
        "uniquebeast": "唯一兽",
        "worldmap": "世界地图",
        "localization": "本地化特效",
        "town": "城镇",
        "itemshop": "商店",
        "pvp_mission": "决斗任务",
        "event": "活动",
        "region": "区域",
        "chatemoticon": "聊天表情",
        "clientonly": "客户端专用",
        "aura": "光环",
        "cashshop": "商城",
    }
    for root, n, size in roots:
        w(f"| `{root}` | {n:,} | {desc.get(root, '')} |")
    w("")
    w("扩展名分布（top 24）：")
    w("")
    w("| 扩展名 | 文件数 | 合计字节 | 性质 |")
    w("|---|---:|---:|---|")
    kind = {
        "ani": "二进制动画（待 P0.5）", "equ": "标签流", "act": "标签流（动作脚本）",
        "als": "标签流（动作链接）", "stk": "标签流", "obj": "标签流", "atk": "标签流",
        "ai": "标签流", "til": "标签流", "ptl": "标签流", "key": "标签流", "map": "标签流",
        "mob": "标签流", "skl": "标签流", "qst": "标签流", "apd": "标签流", "nut": "明文脚本",
        "npc": "标签流", "cre": "标签流", "dgn": "标签流", "etc": "标签流", "aic": "标签流",
        "rep": "标签流", "ui": "标签流", "twn": "标签流", "lst": "id→路径注册表",
        "str": "本地化文本", "tbl": "标签流", "chr": "标签流",
    }
    for ext, n, size in exts:
        w(f"| `.{ext}` | {n:,} | {size:,} | {kind.get(ext, '')} |")
    w("")
    w("## 3. 系统入口（注册表）")
    w("")
    w("每个系统都有一个 `.lst` 把 id 映射到路径。想按 id 找东西，先查这里。")
    w("")
    w("| 系统 | 注册表 | 条目 |")
    w("|---|---|---:|")
    for name, label, _note in REGISTRY:
        n = count_lst(name)
        if n:
            w(f"| {label} | `export/_meta/lst/{name.replace('.tsv','')}` | {n:,} |")
    w("")
    w("## 4. 职业与技能量")
    w("")
    w("14 个职业树。技能注册表条目 = 该职业可用技能数（含转职前后与 TP/被动）。")
    w("")
    w("| 职业树 | 中文 | 技能注册表条目 | character/ 下文本文件 |")
    w("|---|---|---:|---:|")
    classes = [
        ("swordman", "鬼剑士", "skill__swordmanskill.lst.tsv"),
        ("fighter", "格斗家", "skill__fighterskill.lst.tsv"),
        ("gunner", "神枪手", "skill__gunnerskill.lst.tsv"),
        ("mage", "魔法师", "skill__mageskill.lst.tsv"),
        ("priest", "圣职者", "skill__priestskill.lst.tsv"),
        ("thief", "暗夜使者", "skill__thiefskill.lst.tsv"),
        ("demoniclancer", "魔枪士", "skill__demoniclancerskill.lst.tsv"),
        ("demonicswordman", "黑暗武士", "skill__demonicswordman.lst.tsv"),
        ("creatormage", "缔造者", "skill__creatormage.lst.tsv"),
        ("gunblader", "枪剑士", None),
        ("expertjob", "外传职业", None),
    ]
    for d, cn, lst in classes:
        p2 = ROOT / "export" / "text" / "character" / d
        n_txt = sum(1 for _ in p2.rglob("*.txt")) if p2.exists() else 0
        n_skl = count_lst(lst) if lst else None
        skl_s = f"{n_skl:,}" if n_skl else "—"
        w(f"| `{d}` | {cn} | {skl_s} | {n_txt:,} |")
    w("")
    w("## 5. 副本清单（前 40，共见注册表）")
    w("")
    dgn = META / "lst" / "dungeon__dungeon.lst.tsv"
    if dgn.exists():
        rows = [l.rstrip("\n").split("\t") for l in dgn.open(encoding="utf-8", errors="replace") if l.strip()]
        w("| id | 路径 |")
        w("|---:|---|")
        for r in rows[:40]:
            w(f"| {r[0]} | `{r[1]}` |")
        w(f"| … | 共 {len(rows)} 条 |")
    w("")
    w("## 6. 下一步")
    w("")
    w("- `.ani` 二进制还没解（106 万文件），动画帧/攻击盒取不出来 → **P0.5**")
    w("- 图片在客户端 `ImagePacks2/*.NPK`（33GB），需要 NPK 解码 → **P0.6**")
    w("- 引用图（技能→动作→动画→图片）是分析骨架 → **P0.7**")
    w("- 各系统深度分析文档 → **P1**（按垂直切片优先级）")
    w("")
    w("字段含义速查：`docs/PVF-FORMAT.md`；阶段计划：`docs/ROADMAP.md`。")
    w("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"-> {OUT}  ({len(lines)} lines)")


if __name__ == "__main__":
    main()
