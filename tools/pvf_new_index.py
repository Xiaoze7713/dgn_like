#!/usr/bin/env python3
"""新版 PVF（inner）索引表导出器。

输入是 `tools/pvf_new_unwrap.py` 产出的 `*.inner.pvf`（每 10 MiB 段首 0x2800 已解密的等长文件）。
输出：
  <out>/records.npz      (N,6) uint32 记录矩阵：A B C D E type
  <out>/records.head.csv 前若干条明文（便于肉眼检查）
  <out>/stats.json      全表统计

记录布局（实测）：[u32 A][u32 B][u32 C][u32 D][u32 E][u32 type]，定长 24 B。
type ∈ {1,3,4}；type=1 为主体，type=3/4 集中在表尾。
"""
import argparse
import json
import os
import struct
import sys

import numpy as np

VALID_TYPES = (1, 3, 4)
REC = 24


def mmap_file(path):
    import mmap
    f = open(path, "rb")
    return mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)


def find_table(mm):
    """返回 (表起始偏移, 行数)。表在 0x2800 附近开始，按 24 B 对齐。"""
    best = None
    for base in range(0x30, 0x2800 + 1):
        # 先快速判断：连续 64 行类型合法
        ok = 0
        off = base
        for _ in range(64):
            if struct.unpack_from("<I", mm, off + 20)[0] in VALID_TYPES:
                ok += 1
                off += REC
            else:
                break
        if ok == 64:
            best = base
            break
    if best is None:
        sys.exit("找不到索引表起点（连续 64 行类型非法）")
    off = best
    n = 0
    limit = len(mm) - REC
    while off <= limit:
        if struct.unpack_from("<I", mm, off + 20)[0] not in VALID_TYPES:
            break
        off += REC
        n += 1
    return best, n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inner", help="*.inner.pvf")
    ap.add_argument("--out", default="analysis/pvf-new")
    ap.add_argument("--head", type=int, default=2000)
    args = ap.parse_args()

    mm = mmap_file(args.inner)
    size = len(mm)
    start, n = find_table(mm)
    end = start + n * REC
    print(f"{args.inner}: {size:,} B, 表起点 {start:#x}, {n:,} 条, 表止 {end:#x}, 数据区 {size - end:,} B")

    rec = np.frombuffer(mm, dtype="<u4", count=n * 6, offset=start).reshape(n, 6)
    A, B, C, D, E, T = (rec[:, i] for i in range(6))

    stats = {
        "source": os.path.abspath(args.inner),
        "file_size": size,
        "table_start": start,
        "records": int(n),
        "table_end": end,
        "data_start": end,
        "data_size": size - end,
        "types": {int(k): int(v) for k, v in zip(*np.unique(T, return_counts=True))},
        "max": {k: int(v.max()) for k, v in zip("ABCDE", (A, B, C, D, E))},
        "sum_E": int(E.sum(dtype=np.uint64)),
        "uniq_B": int(len(np.unique(B))),
        "uniq_C": int(len(np.unique(C))),
        "sentinel_B": int((B == 0xFFFFFFFF).sum()),
        "D_cumulative_ratio": float((np.diff(D.astype(np.int64)) == E[:-1].astype(np.int64)).mean()),
        "E_median": float(np.median(E)),
        "E_mean": float(E.mean()),
    }
    # 体量分布（按 E 的对数分桶）
    edges = [0, 64, 256, 1024, 4096, 16384, 65536, 1 << 20, 1 << 30]
    hist, _ = np.histogram(E, bins=edges)
    stats["E_hist"] = {f"[{edges[i]},{edges[i+1]})": int(hist[i]) for i in range(len(hist))}

    os.makedirs(args.out, exist_ok=True)
    np.savez_compressed(os.path.join(args.out, "records.npz"), records=rec)
    with open(os.path.join(args.out, "stats.json"), "w", encoding="utf-8") as f:
        json.dump(stats, f, ensure_ascii=False, indent=2)
    with open(os.path.join(args.out, "records.head.csv"), "w", encoding="utf-8") as f:
        f.write("idx,A,B,C,D,E,type\n")
        for i in range(min(args.head, n)):
            f.write(f"{i},{A[i]},{B[i]},{C[i]},{D[i]},{E[i]},{T[i]}\n")
    print(json.dumps({k: stats[k] for k in ("records", "sum_E", "uniq_B", "uniq_C", "types")}, ensure_ascii=False))
    print("写出:", args.out)


if __name__ == "__main__":
    main()
