"""扫 ImagePacks2 下所有 NPK 的索引表 -> 运行时索引

产出两份：
  analysis/sf85/npk-index.jsonl.gz   人看的（每行 {"p","npk","o","s"}）
  dnf_like/assets/npk-index.bin      Godot 侧直接 mmap 式读取（无 JSON 解析）

.bin 布局（小端）：
  "NPKIDX01"            8 B
  u32 count             条目数
  u32 blob_len          路径字符串区长度
  record[count]         24 B：u64 hash, u16 pack_id, u16 pad, u32 offset, u32 size
  u16 pack_count
  pack[pack_count]      u16 len + bytes（包文件名）

record 按 hash 升序；hash 用 FNV-1a 64（对小写路径）。全表约 3.3 MB，读进来就能二分。

不解析任何图像，只读 NPK 的 16 B magic + u32 条目数 + 每项 264 B。
"""
import gzip
import json
import os
import struct
import sys
import time

PACK = "/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2"
OUT_JSONL = "analysis/sf85/npk-index.jsonl.gz"
OUT_BIN = "/mnt/e/godot_proj/dnf_like/assets/npk-index.bin"
KEY = (b"puchikon@neople dungeon and fighter " + b"DNF" * 256)[:255] + b"\x00"
XOR_TABLE = bytes(KEY[i % 256] for i in range(256))


def fnv1a64(s):
    """FNV-1a 64 —— 只存哈希不存路径，137k 条撞车概率可忽略"""
    h = 0xCBF29CE484222325
    for c in s.encode("utf-8"):
        h = ((h ^ c) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return h


def scan():
    out = []
    packs = []
    for fn in sorted(os.listdir(PACK)):
        if not fn.lower().endswith(".npk"):
            continue
        path = os.path.join(PACK, fn)
        try:
            with open(path, "rb") as f:
                if f.read(16) != b"NeoplePack_Bill\x00":
                    continue
                cnt = struct.unpack("<I", f.read(4))[0]
                if cnt > 200000:
                    continue
                tab = f.read(cnt * 264)
        except OSError as e:
            print("skip", fn, e)
            continue
        packs.append(fn)
        pid = len(packs) - 1
        for i in range(cnt):
            off, size = struct.unpack_from("<ii", tab, i * 264)
            raw = tab[i * 264 + 8:i * 264 + 264]
            name = bytes(a ^ b for a, b in zip(raw, XOR_TABLE)).split(b"\x00")[0]
            out.append((name.decode("latin1").lower(), pid, off, size))
    return out, packs


def main():
    t0 = time.time()
    rows, packs = scan()
    rows.sort()
    os.makedirs(os.path.dirname(OUT_JSONL), exist_ok=True)
    with gzip.open(OUT_JSONL, "wt", encoding="utf-8") as g:
        for p, pid, off, size in rows:
            g.write(json.dumps({"p": p, "npk": packs[pid], "o": off, "s": size},
                               ensure_ascii=False) + "\n")

    recs = [(fnv1a64(p), pid, off, size) for p, pid, off, size in rows]
    recs.sort(key=lambda r: r[0])

    os.makedirs(os.path.dirname(OUT_BIN), exist_ok=True)
    with open(OUT_BIN, "wb") as f:
        f.write(b"NPKIDX02")
        f.write(struct.pack("<II", len(recs), 0))
        for h, pid, off, size in recs:
            f.write(struct.pack("<QHHII", h, pid, 0, off, size))
        f.write(struct.pack("<H", len(packs)))
        for name in packs:
            b = name.encode("utf-8")
            f.write(struct.pack("<H", len(b)))
            f.write(b)
    print("条目", len(recs), "包", len(packs),
          "bin", os.path.getsize(OUT_BIN), "B  用时 %.1fs" % (time.time() - t0))


if __name__ == "__main__":
    sys.exit(main())
