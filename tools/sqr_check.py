#!/usr/bin/env python3
"""翻译自检：检查一个 .gd 是否符合 analysis/sqr/PORT-SPEC.md。

用法：
    python3 tools/sqr_check.py sqr_gd/character/atmage/x/x.gd
退出码 0 = 通过，1 = 有问题（问题逐条打印）。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ROOT = os.path.join(ROOT, "sqr_src_utf8")

KOREAN = re.compile(r"[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]")


def src_path_of(gd_path: str) -> str:
    rel = os.path.relpath(os.path.abspath(gd_path), os.path.join(ROOT, "sqr_gd"))
    return os.path.join(SRC_ROOT, "sqr", rel[:-3] + ".nut")


def check(gd_path: str) -> list[str]:
    errs: list[str] = []
    if not os.path.exists(gd_path):
        return [f"文件不存在：{gd_path}"]
    text = open(gd_path, encoding="utf-8").read()
    lines = text.splitlines()

    # 1. 头部
    head = "\n".join(lines[:12])
    if "## 源文件：" not in head:
        errs.append("缺少头部注释 `## 源文件：`")
    if "## 功能：" not in head:
        errs.append("缺少头部注释 `## 功能：`")
    if "\nextends SqrScript" not in text:
        errs.append("缺少 `extends SqrScript`")
    if "class_name" in text:
        errs.append("不允许使用 `class_name`")

    # 2. 语法残留
    code_lines = []
    for ln in lines:
        # 去掉行内注释（简单处理：不在引号内的 # 之后）
        in_str = None
        cut = len(ln)
        for i, ch in enumerate(ln):
            if in_str:
                if ch == in_str:
                    in_str = None
            elif ch in "\"'":
                in_str = ch
            elif ch == "#":
                cut = i
                break
        code_lines.append(ln[:cut])
    code = "\n".join(code_lines)

    for pat, msg in [
        (r"<-", "残留 Squirrel 的 `<-` 赋值"),
        (r"\blocal\s+\w", "残留 `local`"),
        (r"^\s*function\s+\w+", "残留 `function` 关键字"),
        (r"&&", "`&&` 应改成 `and`"),
        (r"\|\|", "`||` 应改成 `or`"),
        (r"\.len\(\)", "`.len()` 应改成 `.size()` / `.length()`"),
        (r"\.tofloat\(\)", "`.tofloat()` 应改成 `float()`"),
        (r"\.tointeger\(\)", "`.tointeger()` 应改成 `int()`"),
        (r"\bforeach\s*\(", "残留 `foreach`"),
        (r"\bswitch\s*\(", "残留 `switch`"),
        (r"\bdelete\s+\w", "残留 `delete`"),
        (r"::\w", "Squirrel 的 `::` 引用"),
    ]:
        for m in re.finditer(pat, code, re.M):
            ln = code[: m.start()].count("\n") + 1
            errs.append(f"第 {ln} 行：{msg}（{m.group(0).strip()}）")

    # 3. 括号/引号配平（只看代码部分，忽略三引号与跨行字符串）
    for a, b, name in [("(", ")", "小括号"), ("[", "]", "中括号"), ("{", "}", "大括号")]:
        if code.count(a) != code.count(b):
            errs.append(f"{name}不配平：{code.count(a)} 个 {a} vs {code.count(b)} 个 {b}")
    for q in ('"""',):
        if code.count(q) % 2:
            errs.append("三引号不配平")
    for q in ('"', "'"):
        n = len(re.findall(r"(?<!\\\\)" + re.escape(q), code))
        # 三引号已被上面统计过，这里跳过 """ 的情况
    # 单引号在 GDScript 里合法，但成对性同样要查（跳过缩写的三引号）
    single = len(re.findall(r"(?<![\\\w])'(?![\\'])", code))
    if single % 2:
        errs.append("单引号疑似不配平")

    # 4. 韩文原文保留（纯文档文件豁免：没有 func 的说明性文件，注释本身就在正文里）
    src = src_path_of(gd_path)
    doc_only = not re.search(r"^func\s", text, re.M)
    if os.path.exists(src) and not doc_only:
        s_text = open(src, encoding="utf-8").read()
        # 只看**去重后**的韩文注释（原文里大量重复的占位注释不算分母）
        k_set = set()
        for l in s_text.splitlines():
            if KOREAN.search(l) and "//" in l:
                k_set.add(l.split("//", 1)[1].strip())
        kept = len(re.findall(r"#\s*原[:：]", text))
        need = max(1, int(len(k_set) * 0.2)) if k_set else 0
        if kept < need:
            errs.append(
                f"韩文原文只保留了 {kept} 行（不同韩文注释 {len(k_set)} 条，"
                f"至少要保留 {need} 条用 `# 原:` 另起一行）"
            )
    elif not os.path.exists(src):
        errs.append(f"找不到源文件：{src}（文件名/目录是否与 .nut 一致？）")

    # 5. 函数注释（每个 func 上方 1 行内要有 ## 注释）
    flines = text.splitlines()
    for i, ln in enumerate(flines):
        if ln.startswith("func "):
            prev = [x for x in flines[max(0, i - 3): i] if x.strip()]
            if not prev or not prev[-1].lstrip().startswith("##"):
                errs.append(f"第 {i + 1} 行 `{ln.strip()[:40]}` 上方缺少 `##` 功能注释")
    return errs


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    bad = 0
    for p in sys.argv[1:]:
        errs = check(p)
        if errs:
            bad += 1
            print(f"✗ {p}")
            for e in errs:
                print(f"    - {e}")
        else:
            print(f"✓ {p}")
    print(f"\n{bad} 个文件有问题 / 共 {len(sys.argv) - 1} 个")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
