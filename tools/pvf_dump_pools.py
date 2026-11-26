#!/usr/bin/env python3
"""一次性把内层 PVF 的字符串池导出成 mmap 友好的裸文件，供桌面阅读器使用。

产物: analysis/pvf-new/pools/{strA.bin,strW.bin,meta.json}
"""
import json, os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pvf_new_extract import NewPvf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "analysis", "pvf-new", "pools")
INNER = os.path.join(ROOT, "analysis", "pvf-new", "inner", "Script.inner.pvf")


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    meta_path = os.path.join(OUT, "meta.json")
    pvf = NewPvf(INNER)
    for name, blob in (("strA", pvf.str_a), ("strW", pvf.str_w)):
        with open(os.path.join(OUT, name + ".bin"), "wb") as f:
            f.write(blob)
        print(f"{name}: {len(blob):,} B")
    meta = {
        "inner": os.path.relpath(INNER, ROOT),
        "file_count": pvf.file_count,
        "body_off": pvf.body_off,
        "strA_size": len(pvf.str_a),
        "strW_size": len(pvf.str_w),
    }
    with open(meta_path, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    print("meta ->", meta_path)


if __name__ == "__main__":
    main()
