#!/usr/bin/env python3
"""从 Squirrel 头文件生成 GDScript 全局常量表 sqr_gd/sqr_consts.gd。

原始脚本里所有 .nut 共享一份全局常量（STATE_ATTACK / SKILL_... / ENUM_...），
GDScript 没有全局命名空间，所以统一放进基类 SqrConsts，
翻译脚本 `extends SqrScript`（SqrScript extends SqrConsts）后即可裸用。
"""
import collections
import os
import re

BASE = "sqr_src_utf8/sqr"
HEADERS = [
    "dnf_enum_header.nut",
    "character/common/common_header.nut",
    "character/atmage/atmage_header.nut",
    "character/creatormage/creatormage_header.nut",
    "character/priest/avenger_header.nut",
]
SLOT = re.compile(r"^\s*([A-Za-z_]\w*)\s*<-\s*(.+?)\s*(?://.*)?$")
# 源里没有、但翻译脚本引用到的宿主常量（补全，附说明）
EXTRA = {
    # 这些 APID_* 是「附加体唯一 ID」，原版由 exe 侧定义；sf85 / 110 的 sqr 导出里都找不到取值。
    # 先给互不相同的负数占位（保证互不相等，不会被误当成同一个附加体去重），值待查。
    "APID_MAGIC_SHIELD": ("-1", "值未知（sf85/110 导出里都没有定义），负数占位，仅保证互不相同"),
    "APID_RESONANCE": ("-2", "值未知，负数占位"),
    "APID_COMMON": ("-3", "值未知，负数占位"),
    "APID_SKILL_ELEMENTAL_CHANGE": ("-4", "值未知，负数占位"),
    "APID_AT_MAGE_ELEMENT_SHIELD": ("-5", "值未知，负数占位"),
}
HOST_GLOBALS = [
    "IRDSQRCharacter",      # 角色控制器全局单例
    "IRDSUltimateSkill",    # 觉醒技全局单例
    "CNSquirrelAppendage",  # 附加体工厂（sq_AppendAppendage / sq_AppendAppendageID）
    "CNAvenger",            # 复仇者专用角色类
    "IMouse",               # 鼠标输入（GetXPos() / GetYPos()）
    "CNRDObject",           # 宿主工具类（getAngleDistanceXPos / getAngleDistanceYPos）
]
HEADER = '''## 全局常量表（原 Squirrel 的 `dnf_enum_header.nut` + 各职业 `*_header.nut`）
##
## 原版所有 .nut 共享同一份全局常量（`STATE_ATTACK`、`SKILL_...`、`ENUM_...` 等），
## GDScript 没有全局命名空间，这里统一放进基类，`SqrScript extends SqrConsts` 后
## 所有翻译脚本都能直接引用，不用加前缀。
##
## 由 `tools/sqr_consts.py` 从源脚本自动生成，**不要手改**。
class_name SqrConsts
extends RefCounted

## 宿主的"全局单例"对象（原版是 C++ 暴露给脚本的全局实例）
'''


def scan_nut_slots(vals: "collections.OrderedDict[str, str]",
                   conflicts: list[tuple[str, str, str, str]]) -> int:
    """扫全部 .nut 的顶层整数 slot（`NAME <- 123`）。

    Squirrel 里所有脚本共用一个全局命名空间，所以「只在 api.nut 顶层定义一次」的常量
    对任何脚本可见；GDScript 没这个机制，只能全部搬进基类。加了文件的那些常量优先于
    头文件？不——先来后到：已在 vals 里的不覆盖（同名不同值记进 conflicts 供人工看）。
    """
    added = 0
    for dirpath, _, files in os.walk(BASE):
        for fname in sorted(files):
            if not fname.endswith(".nut"):
                continue
            path = os.path.join(dirpath, fname)
            rel = os.path.relpath(path, BASE)
            with open(path, encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    m = SLOT.match(line)
                    if not m:
                        continue
                    if not re.fullmatch(r"-?\d+", m.group(2).strip().rstrip(";").strip()):
                        continue  # 非整数 slot（数组 / 字符串 / 函数调用 / null）不进常量表
                    name, val = m.group(1), m.group(2).strip().rstrip(";").strip()
                    if name in vals:
                        if vals[name] != val:
                            conflicts.append((name, vals[name], val, rel))
                        continue
                    vals[name] = val
                    added += 1
    return added


def main() -> int:
    vals: collections.OrderedDict[str, str] = collections.OrderedDict()
    dupes: collections.Counter[str] = collections.Counter()
    for fn in HEADERS:
        with open(os.path.join(BASE, fn), encoding="utf-8") as fh:
            for line in fh:
                m = SLOT.match(line)
                if not m:
                    continue
                name, val = m.group(1), m.group(2).strip().rstrip(";").strip()
                if not re.fullmatch(r"-?\d+", val):
                    continue  # 非整数 slot（DEBUG <- isDebugMode() 之类）不进常量表
                if name in vals and vals[name] != val:
                    dupes[name] += 1
                vals[name] = val  # 同名重复定义时后者生效（Squirrel 语义）
    conflicts: list[tuple[str, str, str, str]] = []
    added = scan_nut_slots(vals, conflicts)
    print(f"另外从各 .nut 顶层补入 {added} 个常量")
    for c in conflicts:
        print(f"  ! 同名不同值 {c[0]}: 表里={c[1]} 文件里={c[2]} ({c[3]})，保留表里的")
    out = [HEADER]
    for g in HOST_GLOBALS:
        out.append(f"var {g} = null\n")
    out.append("\n")
    for name, val in vals.items():
        note = "  # 【译注】原头文件里定义了两次，取后一次的值" if name in dupes else ""
        out.append(f"const {name} := {val}{note}\n")
    for name, (val, note) in EXTRA.items():
        out.append(f"const {name} := {val}  # 【译注】{note}\n")
    with open("sqr_gd/sqr_consts.gd", "w", encoding="utf-8") as fh:
        fh.write("".join(out))
    print(f"sqr_gd/sqr_consts.gd: {len(vals)} 个常量 + {len(EXTRA)} 个补全；"
          f"同名重复 {len(dupes)} 个 {dict(dupes)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
