"""pvf_extract.py — turn Script.pvf into an analysable on-disk tree.

Commands
--------
  index    build export/_meta/index.sqlite + stats (all 1.46M entries)
  text     decode tag-stream files to <out>/<path>.txt   (the analysis tree)
  raw      dump byte-identical copies for selected extensions
  meta     stringtable.tsv / n_string.tsv / lst/*.tsv / ext-stats
  show     print one file's decoded text
  info     print one file's tree entry

Examples
--------
  python tools/pvf_extract.py index
  python tools/pvf_extract.py text --jobs 8
  python tools/pvf_extract.py text --roots skill,equipment,stackable
  python tools/pvf_extract.py show stackable/lv105_equipment/6012124.stk
"""

import argparse
import json
import os
import sqlite3
import struct
import sys
import time
from multiprocessing import Pool
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import pvf_loader as L  # noqa: E402

PVF = "data/Script.pvf"
OUT = "export"

# tag-stream PVF formats (everything that decodes through content2List)
TAG_EXTS = {
    "equ", "stk", "skl", "qst", "mob", "npc", "act", "atk", "ai", "obj", "apd",
    "etc", "dgn", "cre", "rep", "aic", "key", "map", "als", "til", "ptl", "twn",
    "ui", "sqr", "edu", "ex", "lst", "chl", "chn", "chr", "tbl", "rgn", "wdm",
}
PLAIN_EXTS = {"nut", "str"}          # plain text, no tag stream
BINARY_EXTS = {"ani", "img", "bin", "ogg", "wav", "mp3", "bik", "dds", "png", "jpg"}
SKIP_DUMP = {"stringtable.bin", "n_string.lst"}

# per-process globals
_P = None
FULL_RENDER = False   # True 时用无截断渲染（render_dict_full），默认关以免改动既有产物


def _init(pvf_path, zhconv, full=False):
    global _P, FULL_RENDER
    FULL_RENDER = full
    _P = L.load_pvf(pvf_path, zhconv=zhconv)


def _decode_one(path):
    try:
        if path.endswith(".nut"):
            raw = L.read_raw(_P, path)
            for enc in ("utf-8", "gbk", "big5"):
                try:
                    return ("text", raw.decode(enc))
                except UnicodeDecodeError:
                    continue
            return ("text", raw.decode("utf-8", "replace"))
        if path.endswith(".str"):
            raw = L.read_raw(_P, path)
            try:
                return ("text", raw.decode("big5"))
            except UnicodeDecodeError:
                return ("text", raw.decode("utf-8", "replace"))
        if path.endswith(".lst"):
            kind, payload = L.read_lst_any(_P, path, full=FULL_RENDER)
            if kind == "table":
                return ("text", "\n".join(f"{i}\t{p}" for i, p in payload))
            return ("text", payload)
        txt = L.read_text(_P, path, full=FULL_RENDER)
        if txt is None or not txt.strip():
            return ("raw", L.read_raw(_P, path))
        return ("text", txt)
    except Exception as exc:  # fall back to bytes, never lose a file
        try:
            return ("raw", L.read_raw(_P, path))
        except Exception:
            return ("error", repr(exc))


def _worker(chunk):
    out = []
    for path in chunk:
        kind, payload = _decode_one(path)
        if kind == "text":
            dest = Path(_outdir) / (path + ".txt")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(payload, encoding="utf-8", errors="replace")
            out.append((path, "text", 0))
        elif kind == "raw":
            dest = Path(_outdir) / (path + ".bin")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(payload)
            out.append((path, "raw", 0))
        else:
            out.append((path, "error", 1))
    return out


def cmd_index(args):
    pvf = L.load_pvf(args.pvf)
    files = pvf.fileTreeDict
    meta = Path(args.out) / "_meta"
    meta.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(meta / "index.sqlite")
    db.execute("DROP TABLE IF EXISTS files")
    db.execute(
        "CREATE TABLE files(path TEXT PRIMARY KEY, ext TEXT, size INT, crc INT,"
        " offset INT, kind TEXT)"
    )
    rows = []
    for path, leaf in files.items():
        ext = path.rsplit(".", 1)[-1] if "." in path else ""
        if path in SKIP_DUMP:
            kind = "meta"
        elif ext in TAG_EXTS or ext in PLAIN_EXTS:
            kind = "text"
        else:
            kind = "binary"
        rows.append((path, ext, leaf["fileLength"], leaf["fileCrc32"],
                     leaf["relativeOffset"], kind))
    db.executemany("INSERT OR REPLACE INTO files VALUES (?,?,?,?,?,?)", rows)
    db.execute("CREATE INDEX idx_ext ON files(ext)")
    db.execute("CREATE INDEX idx_kind ON files(kind)")
    db.commit()
    exts, roots = L.stats(pvf)
    (meta / "ext-stats.tsv").write_text(
        "ext\tcount\n" + "\n".join(f"{k}\t{v}" for k, v in
                                   sorted(exts.items(), key=lambda x: -x[1])),
        encoding="utf-8")
    (meta / "roots.tsv").write_text(
        "root\tcount\n" + "\n".join(f"{k}\t{v}" for k, v in
                                    sorted(roots.items(), key=lambda x: -x[1])),
        encoding="utf-8")
    kinds = {}
    for r in rows:
        kinds[r[5]] = kinds.get(r[5], 0) + 1
    (meta / "SUMMARY.json").write_text(json.dumps({
        "pvf": args.pvf, "version": pvf.pvfHeader.PVFversion,
        "uuid": pvf.pvfHeader.uuid.decode(errors="replace"),
        "files": len(rows), "kinds": kinds, "exts": exts, "roots": roots,
        "bytes": sum(r[2] for r in rows),
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    print("indexed", len(rows), "files ->", (meta / "index.sqlite").resolve())


def cmd_text(args):
    global _outdir
    outdir = Path(args.out) / "text"
    _outdir = outdir
    pvf = L.load_pvf(args.pvf)
    paths = list(pvf.fileTreeDict)
    if args.exts:
        want = {e.strip().lstrip(".") for e in args.exts.split(",")}
        paths = [p for p in paths if (p.rsplit(".", 1)[-1] if "." in p else "") in want]
    if args.roots:
        want = {r.strip() for r in args.roots.split(",")}
        paths = [p for p in paths if p.split("/")[0] in want]
    if args.skip:
        bad = {e.strip().lstrip(".") for e in args.skip.split(",")}
        paths = [p for p in paths if (p.rsplit(".", 1)[-1] if "." in p else "") not in bad]
    if args.limit:
        paths = paths[: args.limit]
    paths.sort()
    print(f"{len(paths)} files -> {outdir}  (jobs={args.jobs}, full={getattr(args,'full',False)})")
    t0 = time.time()
    n = len(paths)
    step = (n + args.jobs - 1) // args.jobs
    chunks = [paths[i:i + step] for i in range(0, n, step)]
    counts = {"text": 0, "raw": 0, "error": 0}
    with Pool(args.jobs, initializer=_init,
              initargs=(args.pvf, args.zhconv, getattr(args, "full", False))) as pool:
        done = 0
        for res in pool.imap_unordered(_worker, chunks):
            for _, kind, _err in res:
                counts[kind] += 1
            done += len(res)
            if done % 20000 < len(res):
                print(f"  {done}/{n}  {time.time() - t0:.0f}s", flush=True)
    print("done", counts, f"{time.time() - t0:.0f}s")


def cmd_raw(args):
    global _outdir
    pvf = L.load_pvf(args.pvf)
    outdir = Path(args.out) / "raw"
    _outdir = outdir
    want = {e.strip().lstrip(".") for e in args.exts.split(",")} if args.exts else None
    n = 0
    for path in sorted(pvf.fileTreeDict):
        ext = path.rsplit(".", 1)[-1] if "." in path else ""
        if want and ext not in want:
            continue
        dest = outdir / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(L.read_raw(pvf, path))
        n += 1
        if args.limit and n >= args.limit:
            break
    print("wrote", n, "raw files ->", outdir.resolve())


def cmd_meta(args):
    pvf = L.load_pvf(args.pvf)
    meta = Path(args.out) / "_meta"
    meta.mkdir(parents=True, exist_ok=True)
    st = pvf.stringTable
    with open(meta / "stringtable.tsv", "w", encoding="utf-8") as fh:
        for i in range(st.length):
            val = st[i].replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")
            fh.write(f"{i}\t{val}\n")
    print("stringtable", st.length)
    rows = L.read_lst(pvf, "n_string.lst")
    (meta / "n_string.tsv").write_text(
        "\n".join(f"{i}\t{p}" for i, p in rows), encoding="utf-8")
    lstdir = meta / "lst"
    lstdir.mkdir(exist_ok=True)
    for path in sorted(pvf.fileTreeDict):
        if not path.endswith(".lst") or path in SKIP_DUMP:
            continue
        try:
            kind, payload = L.read_lst_any(pvf, path)
        except Exception as exc:
            print("lst fail", path, exc)
            continue
        dest = lstdir / (path.replace("/", "__") + ".tsv")
        if kind == "table":
            dest.write_text("\n".join(f"{i}\t{p}" for i, p in payload), encoding="utf-8")
        else:
            dest = lstdir / (path.replace("/", "__") + ".txt")
            dest.write_text(payload, encoding="utf-8")
            print("lst tagstream", path)
    print("lst dumps ->", lstdir.resolve())


def cmd_show(args):
    pvf = L.load_pvf(args.pvf, zhconv=args.zhconv)
    path = args.path.lower()
    if path.endswith(".nut") or path.endswith(".str"):
        raw = L.read_raw(pvf, path)
        print(raw.decode("utf-8", "replace"))
        return
    if path.endswith(".lst"):
        for i, p in L.read_lst(pvf, path):
            print(f"{i}\t{p}")
        return
    print(L.read_text(pvf, path))


def cmd_info(args):
    pvf = L.load_pvf(args.pvf)
    leaf = pvf.fileTreeDict.get(args.path.lower())
    if not leaf:
        sys.exit("not found: " + args.path)
    print(json.dumps({k: v for k, v in leaf.items() if k != "content"},
                     ensure_ascii=False, indent=2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pvf", default=PVF)
    ap.add_argument("--out", default=OUT)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("index"); p.set_defaults(func=cmd_index)

    p = sub.add_parser("text")
    p.add_argument("--jobs", type=int, default=8)
    p.add_argument("--exts", default="")
    p.add_argument("--roots", default="")
    p.add_argument("--skip", default="")
    p.add_argument("--limit", type=int, default=0)
    p.add_argument("--zhconv", action="store_true")
    p.add_argument("--full", action="store_true",
                   help="无截断渲染（替代 dictSegment2text 的 maxSegNum=50/depth=4）")
    p.set_defaults(func=cmd_text)

    p = sub.add_parser("raw")
    p.add_argument("--exts", default="ani")
    p.add_argument("--limit", type=int, default=0)
    p.set_defaults(func=cmd_raw)

    p = sub.add_parser("meta"); p.set_defaults(func=cmd_meta)

    p = sub.add_parser("show")
    p.add_argument("path")
    p.add_argument("--zhconv", action="store_true")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("info")
    p.add_argument("path")
    p.set_defaults(func=cmd_info)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
