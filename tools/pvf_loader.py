"""PVF loader wrapper around dnfpkgtool.pvfReader.

Key facts established by probing data/Script.pvf (PVF ver 53579, 1,460,792 files):
  * header : i32 uuid_len | uuid | i32 version | i32 tree_len | u32 tree_crc | u32 file_count
             followed immediately by the encrypted file tree (tree_len bytes).
  * crypto : key = crc32 ^ 0x81A79011; 4-byte little-endian word rotation (see decrypt_Bytes).
  * tree   : per file: u32 fn | u32 path_len | path | u32 len | u32 crc | u32 rel_offset.
             offsets are relative to the end of the header+tree block.
  * text   : stringtable.bin holds every non-ascii literal; strings are Big5 (Traditional
             Chinese client). Data files are tag streams (1 byte type + value) that reference
             stringtable indices with types 5/6/7/8/9.
  * n_string.lst maps type-9 ids to *.str files for secondary substitution.
"""

import struct
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "pvf_python"))

import dnfpkgtool.pvfReader as R  # noqa: E402

ZHCONV = {"on": False}
_zhconv = None

# --- mixed-encoding detection -------------------------------------------------
# This client is a merge: the 台服 base writes Big5, while private-server mods
# injected GBK (simplified) byte strings into the very same stringtable.  We
# therefore score each candidate decode against a character-frequency table
# derived from the stringtable itself (data/zh-common.txt).
_COMMON = None


def _common():
    global _COMMON
    if _COMMON is None:
        p = HERE.parent / "data" / "zh-common.txt"
        _COMMON = frozenset(p.read_text(encoding="utf-8")) if p.exists() else frozenset()
    return _COMMON


def _score(text):
    if not text:
        return 0.0
    common = _common()
    good = 0
    for ch in text:
        if ch.isascii() or ch.isdigit() or ch.isspace():
            good += 1
        elif 0x3040 <= ord(ch) <= 0x30FF:      # kana never occurs in Chinese text
            good -= 2
        elif ch in common:
            good += 1
    return good / len(text)


def decode_any(raw):
    """Decode bytes that may be Big5 (traditional) or GBK (simplified)."""
    b1 = b2 = None
    try:
        b1 = raw.decode("big5")
    except UnicodeDecodeError:
        pass
    try:
        b2 = raw.decode("gbk")
    except UnicodeDecodeError:
        pass
    if b1 is None and b2 is None:
        return raw.decode("utf-8", "replace")
    if b2 is None:
        return b1
    if b1 is None:
        return b2
    return b1 if _score(b1) >= _score(b2) else b2



def _zh(text):
    global _zhconv
    if _zhconv is None:
        from zhconv import convert
        _zhconv = convert
    return _zhconv(text, "zh-cn")


class FastStringTable:
    """Lazy Big5 stringtable with an optional zhconv pass. Avoids the 3 GB precompute."""

    def __init__(self, table_bytes, encode="big5"):
        self.length = struct.unpack("I", table_bytes[:4])[0]
        self._buf = table_bytes[4:]
        self._cache = {}

    def __getitem__(self, n):
        try:
            return self._cache[n]
        except KeyError:
            pass
        s, e = struct.unpack("<II", self._buf[n * 4:n * 4 + 8])
        v = decode_any(self._buf[s:e])
        if ZHCONV["on"]:
            v = _zh(v)
        self._cache[n] = v
        return v


def load_pvf(path, zhconv=False):
    ZHCONV["on"] = zhconv
    R.StringTable = FastStringTable
    t = time.time()
    header = R.PVFHeader(str(path))
    pvf = R.TinyPVF(header, encode="big5")
    pvf.load_Leafs()
    pvf.load_seconds = time.time() - t
    return pvf


def _join_values(seg, indent, prefix_add):
    tmp = ""
    for value in seg:
        tmp += str(value) + " "
        tmp = tmp.replace("\n", "\n" + indent + prefix_add).replace(r"%%", r"%")
    return tmp


def render_dict_full(d, prefix="", prefix_add="    ", _depth=0):
    """无截断版的标签流渲染（替代 pvfReader.dictSegment2text 的 maxSegNum=50 / depth=4 截断）。

    原实现的坑：超过 50 个值的数组会被截成「前 50 + ...」；递归时还没把 maxSegNum 传下去，
    所以嵌套块一律按默认 50 截断且 depth 只到 4。用它做数值校验会得到残缺数据。
    """
    if _depth > 64:
        return prefix + "<depth-limit>\n"
    res = ""
    for key, segment in d.items():
        res += prefix + str(key) + "\n"
        if isinstance(segment, dict):
            res += render_dict_full(segment, prefix + prefix_add, prefix_add, _depth + 1)
        else:
            res += prefix + prefix_add + _join_values(segment, prefix, prefix_add) + "\n"
    return res


def read_text(pvf, path, full=False):
    if not full:
        return pvf.read_File_In_Text(path)
    from dnfpkgtool.pvfReader import TinyPVF as _T
    lst = pvf.read_File_In_List2(path)
    d = _T.list2Dict(lst)
    return render_dict_full(d)


def read_raw(pvf, path):
    return pvf.read_File_In_Decrypted_Bin(path)


def read_lst(pvf, path):
    import io
    raw = read_raw(pvf, path)
    if not raw:
        return []
    from dnfpkgtool.pvfReader import Lst_lite2
    lst = Lst_lite2(raw, pvf, pvf.stringTable, encode="big5")
    return lst.tableList


def read_lst_any(pvf, path, full=True):
    """`.lst` 有两种形态：真正的 id→路径表（`<bIbI>` 10 字节记录），
    以及被套了 `.lst` 后缀的标签流配置（如 n_quest/epicquest.lst：`[episode]/[epic_index]`）。
    后者用 Lst_lite2 解析会在 `StrIndexIndex` 上抛 UnboundLocalError，必须走标签流渲染。
    """
    raw = read_raw(pvf, path)
    if not raw:
        return "table", []
    from dnfpkgtool.pvfReader import Lst_lite2
    try:
        return "table", Lst_lite2(raw, pvf, pvf.stringTable, encode="big5").tableList
    except Exception:
        return "text", read_text(pvf, path, full=full)


def list_files(pvf):
    return list(pvf.fileTreeDict.keys())


def stats(pvf):
    files = pvf.fileTreeDict
    exts, roots = {}, {}
    for k, v in files.items():
        e = k.rsplit(".", 1)[-1] if "." in k else "<none>"
        exts[e] = exts.get(e, 0) + 1
        roots[k.split("/")[0]] = roots.get(k.split("/")[0], 0) + 1
    return exts, roots
