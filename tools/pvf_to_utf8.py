#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pvf_to_utf8.py — 把 DNF 的 PVF 里「字符串表」整体从 GBK 转成 UTF-8，产出新包

为什么只需要动字符串表：
  PVF 里所有文本（物品名、段名、脚本里的中文……）都**不内联**，而是 5 字节记录里存一个
  i32 下标，指向 `stringtable.bin` 的第 i 条。所以只把表的字节换掉、顺序不变，
  下标就全都不用改。

正文文件完全不动：不需要解密，直接按原字节复制（密文与 crc 一一对应，crc 没变就不用
重算）。目录树只需要处理路径里的 10 条非 ASCII，其余原样。

所以整包只是「字符串表变长 + 后面所有文件整体后移」，一次线性拷贝即可。

**编码是混排的（重要）**：sf115 的 Script.pvf 里同时躺着四种语言——
  简体 GBK 汉化（124,823 条）、BIG5 繁体（329,341 条，比简体还多）、
  **没被汉化的韩文原文**（CP949，14,957 条，如 `뇨뇽이` / `도와주소`）、
  **日文活动文本**（Shift-JIS，133 条，如 `今まで` / `今日のミッション`）。
  统一按 gb18030 解会把后三种全变成乱码，而 gb18030 几乎不抛异常，所以「解不开的
  条数=0」并不能证明编码猜对了。默认 --codec auto 逐条按「像不像该语言」打分挑选。

用法：
    python3 tools/pvf_to_utf8.py --src /mnt/e/dnf-sf/sf115/Script.pvf \
                                 --dst build/Script.utf8.pvf [--codec auto|gb18030|big5] [--dry-run]

实测（sf115）：923,262,293 B → 938,807,789 B（+14.8 MB），耗时约 62 s，1,650,063 条全部合法 UTF-8。
产出包用 Godot 侧 PvfLoader 可以直接打开，中文不需要任何 GBK 解码器。
"""
from __future__ import annotations

import argparse
import os
import struct
import sys
import time
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PASSWORD_PVF = 0x81A79011
HEADER_SIZE = 56
STRINGTABLE = "stringtable.bin"


def ror32(v: int, n: int) -> int:
    return ((v >> n) | (v << (32 - n))) & 0xFFFFFFFF


def rol32(v: int, n: int) -> int:
    return ((v << n) | (v >> (32 - n))) & 0xFFFFFFFF


def decrypt(data: bytes, key: int) -> bytes:
    mix = (PASSWORD_PVF ^ key) & 0xFFFFFFFF
    out = bytearray(data)
    for i in range(len(out) >> 2):
        o = i << 2
        v = struct.unpack_from("<I", out, o)[0]
        struct.pack_into("<I", out, o, ror32(v ^ mix, 6))
    return bytes(out)


def encrypt(data: bytes, key: int) -> bytes:
    mix = (PASSWORD_PVF ^ key) & 0xFFFFFFFF
    out = bytearray(data)
    for i in range(len(out) >> 2):
        o = i << 2
        v = struct.unpack_from("<I", out, o)[0]
        struct.pack_into("<I", out, o, rol32(v, 6) ^ mix)
    return bytes(out)


def pad4(n: int) -> int:
    return (n + 3) & ~3


# ---------------------------------------------------------------- 编码探测
# sf115 这个包是**混排**的：既有简体/GBK 串（如「基本上衣」），也有大量繁体/BIG5 串
# （如「悲鳴洞穴里都是這種氣息」）。统一按 gb18030 解会把后者变成乱码（gb18030 几乎
# 不会抛异常，所以「解不开的条数=0」并不能证明编码猜对了）。因此逐条按「像不像正常
# 中文」打分，再从候选编码里挑分最高的。
# ---- 语言判别 ------------------------------------------------------------
# 同一段字节用不同代码页解出来常常**都合法**（GBK / BIG5 / CP949 的字节空间高度重叠），
# 只能靠「解出来的字在这门语言里常不常用」来打分。sf115 的包里混着：
#   * 简体中文（GBK/GB18030）
#   * 繁体中文（BIG5）—— 实测比简体还多
#   * 韩文（CP949/EUC-KR）—— 未汉化的原版资源，如 `뇨뇽이` / `도와주소` / `15살 쿠란`
#   * 日文（Shift-JIS）—— 活动文本，如 `今まで` / `今日のミッション`
# 只按「汉字 +2」打分会把韩文一律判成中文（韩文按 GBK 解也全是汉字），所以中文分数
# 必须区分「常用字」和「生僻字」，韩文/日文则各自计分后一起比。

# 高频汉字（简体常用 + 繁体常用），命中 +2；其余 CJK 只 +1（乱码大多是生僻字）
ZH_COMMON = frozenset(
    "的一是不了在人有我他中为上大为和以说要时就出可也你对生能子得着下自年过发里用道行所然家事成方多"
    "去法如都同现当没动面起看定天分好小些主样理心本前开但因只从想实日军者意无它与长把机十民第公此已"
    "工使情明性知全三又关点正业外将两高间由问最重并物手应战向头文体政美相被利二等或新制身果加西月话"
    "合回特代内信表化老给世位次度门任常先海通教儿原声提立及比员解水名真论处走义各入几口认条平系气题"
    "活尔更别打女变四神总何电数安少报才结反受目太量再感建务做接必场件计管期市德资命山金指克许统区保"
    "至队形社便空决治展马科司五基眼书非则听白却界达光放强即像难且权思王象完设式色路记南品住告类求据"
    "程北边死张该交规万取拉格望觉术领共确传师观清今切院让识候带争运笑飞风步改收根干造言联持组每济车"
    "亲极林服快办议往元英士证近失转夫令准布始怎呢存未远叫台单影具罗字爱击流备兵连调深商算质集百需价"
    "花党华城石级整府离况亚请技际约示复病息究线似官火断精满支视消越器容照须九增研写称企八功吗包片史"
    "委乎查轻易早曾除农找装广显阿李标谈吃图念六引历首医局突专费号尽另周较注语仅考落青随选列武红响虽"
    "推势参希古众构房半节土投某案黑维革划敌陈律足态护七兴派孩验责营星够章音跟志底站严巴例防族供效续"
    "施留讲型料终答紧黄绝奇察母京段依批群项故按河米围江织害斗双境客纪采举杀攻父苏密低朝友诉细愿千值"
    "仍男钱破网热助倒育属坐帝限船脸职速刻乐否刚威毛状率甚独球般普怕弹校苦创假久错承印晚兰试股拿脑预"
    "谁益阳若哪微尼继送急血惊伤素药适波夜省初喜卫源食险待述陆习置居劳财环排福纳欢雷警获模负云停木游"
    "龙树疑层冷洲冲射略范竟句室异激汉村哈策演简卡罪判担州静退既衣您宗积余痛检差富灵协角占配征修皮挥"
    "胜降阶审沉坚善妈刘读超免压银买皇养伊怀执副乱抗犯追帮宣佛岁航优怪香著田铁控税左右份穿艺背阵草脚"
    "概恶块顿敢守酒岛托央户烈洋哥索胡款靠评版宝座释景顾弟登货互付伯慢欧换闻危忙核暗姐介坏讨丽良序升"
    "监临亮露永呼味野架域沙掉括舰鱼杂误湾吉减编楚肯测败屋跑梦散温困剑渐封救贵枪缺楼县尚毫移娘朋画班"
    "智亦耳恩短掌恐遗固席松秘谢鲁遇康虑幸均销钟诗藏赶剧票损忽巨炮旧端探湖录叶春乡附吸予礼港雨呀板庭"
    "妇归睛饭额含顺输摇招婚脱补谓督毒油疗旅泽材灭逐莫笔亡鲜词圣择寻厂睡博勒烟授诺伦岸奥唐卖俄炸载洛"
    "健堂旁宫喝借君禁阴园谋宋避抓荣姑孙逃牙束跳顶玉镇雪午练迫爷篇肉嘴馆遍凡础洞卷坦牛宁纸诸训私庄祖"
    "丝翻暴森塔默握戏隐熟骨访弱蒙歌店鬼软典欲萨伙遭盘爸扩盖弄雄稳忘亿刺拥徒姆杨齐赛趣曲刀床迎冰虚玩"
    "析窗醒妻透购替塞努休虎扬途侵刑绿兄迅套贸毕唯谷轮库迹尤竞街促延震弃甲伟麻川申缓潜闪售灯针哲络抵"
    "朱埃抱鼓植纯夏忍页杰筑折郑贝尊吴秀混臣雅振染盛怒舞圆搞狂措姓残秋培迷诚宽宇猛摆梅毁伸摩盟末乃悲"
    "拍丁赵宾膜违悔幕佛"
    # 繁体专有字形（BIG5 解出来才对）
    "們這個說時會現動過學實點麼後裡種當無與長機關兩問間體見東聲車頭樣導機開業話給師親愛歡樂女"
    "兒媽劉讀買賣讓認識帶爭運連調質團費號盡週較註語僅隨選紅響雖參與眾構節態護興責營夠黃絕覺辦壞討"
    "麗臨監鏡鋼錢銀銅鐘閒陽陰陸陳險隊階雲電靈靜韓頁題願類風飯飲養馬驗髮鬥魚鳥齊龍龜"
)

# 韩文高频音节（约 260 个，覆盖日常韩文七成以上）；命中 +3，其余谚文音节 +1
KO_COMMON = frozenset(
    "이다는의에을를하가기니습로서도리어아자마나구대사시세스오한있없것수그저보인게요죠네야워와과"
    "만부터까지합드크트프브르므느즐슬클플블른질칠길일절설법업장점상중소금은화원개명시분초월년"
    "안밖위아래앞뒤좌우문입출반응정경계공과관광교국군권근기김나남내너노농누단달당더데덴도동두"
    "등라래러레력련렬령로록론료루류률리린마막만말망매머먹먼메며면멸명모목무묵문물미민바박반받"
    "발방배백버번벌범법벽변별병보복본봉부북분불비빈사산살삼상새생서석선설성세소속손송수숙순술"
    "스슬승시식신실심십아악안알암애액야약양어억언얼엄업에여역연열염엽영예오옥온올와완왕외요욕"
    "용우운울웅원월위유육윤율으은음읍응의이익인일임입있자작잔잠장재쟁저적전절점접정제조족존종좌"
    "죄주죽준줄중즉증지직진질집차착찬찰참창채책처천철첨첫청체초촉촌총최추축춘출충취측치칙친칠"
    "침카칼캐커컴케코콘콜쿠크큰키타탄탈탐탕태택터토통퇴투특틀티파판팔패퍼페편평포폭표품풍피필"
    "하학한할함합항해핵행향허헌험혁현혈협형혜호혹혼홍화확환황회획효후훈훼휘휴흉흑흔흥희히"
)

# 日文：全角假名是硬信号（中文按 SJIS 解只会得到半角片假名）
CODEC_CANDIDATES = (
    ("gb18030", "zh"), ("big5hkscs", "zh"), ("big5", "zh"), ("cp950", "zh"),
    ("cp949", "ko"), ("shift_jis", "ja"),
)


def _is_cjk(o: int) -> bool:
    return 0x4E00 <= o <= 0x9FFF


def score_zh(t: str) -> int:
    s = 0
    for ch in t:
        o = ord(ch)
        if 0x4E00 <= o <= 0x9FFF:
            s += 2 if ch in ZH_COMMON else 1
        elif 0x3400 <= o <= 0x4DBF:        # 扩展 A：乱码高发
            s -= 2
        elif 0x3000 <= o <= 0x303F:        # 中文标点
            s += 1
        elif 0xFF01 <= o <= 0xFF5E:        # 全角
            s += 1
        elif 0x20 <= o < 0x7F:             # 可打印 ASCII
            s += 1
        elif 0x3040 <= o <= 0x30FF:        # 假名：中文串里出现即乱码
            s -= 3
        elif 0x0370 <= o <= 0x04FF:        # 希腊/西里尔
            s -= 3
        elif o < 0x20:
            s -= 1
        else:
            s -= 2
    return s


def score_ko(t: str) -> int:
    """韩文评分：谚文音节 + CP949 里合法的汉字（Hanja）。

    注意 CP949 不只装谚文，还带 4,888 个汉字——实测 `副本`（`dc f9 dc e2`）就是
    用 CP949 的汉字区写的。所以汉字也按中文那套「常用 +2 / 生僻 +1」计分，否则
    纯汉字串一律拿到 -10000，永远比不过 GBK 的错误解。"""
    s = 0
    n_text = 0
    for ch in t:
        o = ord(ch)
        if 0xAC00 <= o <= 0xD7A3:          # 谚文音节
            n_text += 1
            s += 3 if ch in KO_COMMON else 1
        elif 0x4E00 <= o <= 0x9FFF:        # CP949 里的汉字
            n_text += 1
            s += 2 if ch in ZH_COMMON else 1
        elif 0x20 <= o < 0x7F:
            s += 1
        elif o < 0x20:
            s += 0                        # 制表符/换行：中性
        elif 0x3000 <= o <= 0x303F or 0xFF01 <= o <= 0xFF5E:
            s += 1                        # 全角标点
        elif 0x3130 <= o <= 0x318F:        # 兼容字母（乱码典型）
            s -= 3
        else:
            s -= 3
    if n_text == 0:
        return -10_000
    return s


def score_ja(t: str) -> int:
    s = 0
    n_kana = 0
    for ch in t:
        o = ord(ch)
        if 0x3041 <= o <= 0x309F or 0x30A1 <= o <= 0x30FF:   # 全角平/片假名
            n_kana += 1
            s += 3
        elif 0xFF61 <= o <= 0xFF9F:        # 半角片假名：中文按 SJIS 解的典型产物
            s -= 3
        elif 0x4E00 <= o <= 0x9FFF:
            s += 2 if ch in ZH_COMMON else 1
        elif 0x3000 <= o <= 0x303F or 0xFF01 <= o <= 0xFF5E:
            s += 1
        elif 0x20 <= o < 0x7F:
            s += 1
        elif o < 0x20:
            s += 0
        else:
            s -= 2
    if n_kana == 0:
        return -10_000
    return s


def _plausible_kr(raw: bytes) -> bool:
    """快速否掉「按 CP949 解只会得到扩展区符号」的串。

    CP949 的谚文音节要求 **trail ≥ 0xA1**（GB2312 一级汉字也是这个区间，所以两者
    在 0xB0A1–0xC8FE 完全重合，只能靠词频分）；而 GBK 的二级/扩展区汉字大量使用
    trail 0x40–0xA0，这种双字节在 CP949 里不可能是谚文，可以直接跳过。"""
    i = 0
    n = len(raw)
    while i < n:
        b = raw[i]
        if b < 0x80:
            i += 1
            continue
        if i + 1 >= n:
            return False
        if raw[i + 1] < 0xA1:
            return False
        i += 2
    return True


def detect_decode(raw: bytes):
    """返回 (文本, 编码名)；全失败返回 (None, None)。"""
    # UTF-8 先手：能通过严格校验的字节序列几乎必然是 UTF-8（GBK/BIG5 靠运气很难凑出
    # 合法的多字节 UTF-8）。必须先判，否则「UTF-8 字节按 GBK 解」得到的乱码照样全是
    # 常用汉字，打分反而更高（实测 10 条中文路径全被这样解坏）。
    try:
        return raw.decode("utf-8"), "utf-8"
    except UnicodeDecodeError:
        pass
    plausible_kr = _plausible_kr(raw)
    best = None
    for codec, lang in CODEC_CANDIDATES:
        if lang == "ko" and not plausible_kr:
            continue
        if lang == "ja" and not any(0x81 <= b <= 0x9F or 0xE0 <= b <= 0xEF for b in raw):
            continue
        try:
            t = raw.decode(codec)
        except UnicodeDecodeError:
            continue
        if lang == "zh":
            sc = score_zh(t)
        elif lang == "ko":
            sc = score_ko(t)
        else:
            sc = score_ja(t)
        # 同分时保留先出现的（中文优先），因为整包主体是中文
        if best is None or sc > best[0]:
            best = (sc, t, codec)
    if best is None:
        return None, None
    return best[1], best[2]


def decode_any(raw: bytes, forced: str = "auto"):
    if forced != "auto":
        try:
            return raw.decode(forced), forced
        except UnicodeDecodeError:
            return None, forced
    return detect_decode(raw)


class Entry:
    __slots__ = ("number", "path", "path_bytes", "length", "crc", "rel", "orig_rel")

    def __init__(self, number, path, length, crc, rel, path_bytes=b""):
        self.number, self.path, self.length, self.crc = number, path, length, crc
        self.path_bytes = path_bytes or path.encode("latin-1", "replace")
        self.rel = self.orig_rel = rel


def read_header(f) -> dict:
    f.seek(0)
    h = f.read(HEADER_SIZE)
    if len(h) != HEADER_SIZE:
        raise SystemExit("文件不足 56 字节")
    size_guid = struct.unpack_from("<i", h, 0)[0]
    if size_guid != 36:
        raise SystemExit(f"sizeGUID={size_guid}，不是 PVF")
    return {
        "guid": h[4:40],
        "version": struct.unpack_from("<i", h, 40)[0],
        "tree_len": struct.unpack_from("<i", h, 44)[0],
        "tree_crc": struct.unpack_from("<I", h, 48)[0],
        "num_files": struct.unpack_from("<i", h, 52)[0],
    }


def read_tree(f, hdr) -> list[Entry]:
    f.seek(HEADER_SIZE)
    raw = f.read(hdr["tree_len"])
    buf = decrypt(raw, hdr["tree_crc"])
    out, off = [], 0
    for _ in range(hdr["num_files"]):
        number = struct.unpack_from("<I", buf, off)[0]
        plen = struct.unpack_from("<i", buf, off + 4)[0]
        off += 8
        pb = bytes(buf[off:off + plen])
        path = pb.decode("ascii", "replace")
        off += plen
        length, crc, rel = struct.unpack_from("<iIi", buf, off)   # length:i32 crc:u32 rel:i32
        off += 12
        out.append(Entry(number, path, length, crc, rel, pb))
    return out


def build_tree(entries) -> bytes:
    buf = bytearray()
    for i, e in enumerate(entries):
        pb = e.path_bytes
        buf += struct.pack("<I", i)
        buf += struct.pack("<i", len(pb)) + pb
        buf += struct.pack("<i", e.length)
        buf += struct.pack("<I", e.crc)
        buf += struct.pack("<i", e.rel)
    while len(buf) % 4:
        buf.append(0)
    return bytes(buf)


def string_record(buf: bytes, i: int) -> bytes:
    """第 i 条字符串的原始字节（真实布局：offs[i] = 文本起点 - 4）"""
    start = struct.unpack_from("<i", buf, 4 + 4 * i)[0]
    end = struct.unpack_from("<i", buf, 4 + 4 * (i + 1))[0]
    return buf[start + 4:start + 4 + (end - start)]


def build_stringtable(strings: list[bytes]) -> bytes:
    count = len(strings)
    base = 4 + (count + 1) * 4
    offs, blob = [], bytearray()
    for s in strings:
        offs.append(base + len(blob) - 4)
        blob += s
    offs.append(base + len(blob) - 4)
    out = bytearray(struct.pack("<i", count))
    for v in offs:
        out += struct.pack("<i", v)
    out += blob
    return bytes(out)


TEXT_EXTS = {".str", ".txt"}   # 注意：.lst 多为二进制记录，不能当文本转
SKIP_TEXT = {"stringtable.bin", "n_string.lst"}


def convert_text_body(raw: bytes):
    """把纯文本类文件（*.kor.str / *.txt / *.lst）整体转成 UTF-8。

    DNF 的显示名（.equ 里的 [name]）不是存在 stringtable，而是走
    `n_string.lst` -> `*.kor.str` 的 `key>value` 文本表；这些文件是普通文本，
    不在字符串表里，所以必须单独转。先按行抽样投票定文件编码，再逐行解码，
    解不开的行回退到逐行探测、仍失败就原样保留。
    """
    if not any(b > 0x7F for b in raw):
        return None, None, 0
    # 先证明它真的是文本：有换行、前 4 KB 没有 NUL（.lst 这类二进制记录会在这里被挡掉）
    if b"\n" not in raw or b"\x00" in raw[:4096]:
        return None, None, 0
    crlf = b"\r\n" in raw
    sep = b"\r\n" if crlf else b"\n"
    lines = raw.split(sep)

    sample = [ln for ln in lines if any(b > 0x7F for b in ln)][:4000]
    if not sample:
        return None, None, 0
    votes: dict[str, int] = {}
    for ln in sample:
        _t, codec = detect_decode(ln)
        if codec:
            votes[codec] = votes.get(codec, 0) + 1
    codec = max(votes, key=lambda k: votes[k]) if votes else None

    out_lines = []
    changed = 0
    for ln in lines:
        if not any(b > 0x7F for b in ln):
            out_lines.append(ln)
            continue
        text = None
        if codec:
            try:
                text = ln.decode(codec)
            except UnicodeDecodeError:
                text = None
        if text is None:
            text, _c = detect_decode(ln)
        if text is None:
            out_lines.append(ln)
            continue
        nb = text.encode("utf-8")
        if nb != ln:
            changed += 1
        out_lines.append(nb)
    new = sep.join(out_lines)
    if new == raw:
        return None, codec, changed
    try:
        new.decode("utf-8")          # 结果必须整体合法，否则保留原文件
    except UnicodeDecodeError:
        return None, codec, changed
    return new, codec, changed


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="/mnt/e/dnf-sf/sf115/Script.pvf")
    ap.add_argument("--dst", default="build/Script.utf8.pvf")
    ap.add_argument("--codec", default="auto",
                    help="auto=逐条探测（sf115 混着 GBK/BIG5/CP949/Shift-JIS）；也可强制 gb18030/big5/cp950/cp949")
    ap.add_argument("--dry-run", action="store_true", help="只统计不写文件")
    args = ap.parse_args()

    t0 = time.time()
    f = open(args.src, "rb")
    hdr = read_header(f)
    entries = read_tree(f, hdr)
    data_start = HEADER_SIZE + hdr["tree_len"]
    print(f"源：{args.src}")
    print(f"  {hdr['num_files']} 条，版本 {hdr['version']}，目录树 {hdr['tree_len']:,} B，数据区起点 {data_start:,}")

    # ---- 1. 取字符串表并转码 ----
    st = next((e for e in entries if e.path.lower() == STRINGTABLE), None)
    if st is None:
        raise SystemExit("找不到 stringtable.bin")
    f.seek(data_start + st.rel)
    st_raw = f.read(pad4(st.length))
    # 解密必须按 pad4 的整组来：格式是「补足 4 字节后整组加密」，表尾 1~3 字节属于
    # 最后一组，只解密 floor(length/4) 组会把它们留成密文（现象：末条 .stk 变 .st*）。
    st_plain = decrypt(st_raw, st.crc)[:st.length]

    count = struct.unpack_from("<i", st_plain, 0)[0]
    print(f"  stringtable：{count:,} 条 / {st.length:,} B")

    new_strings: list[bytes] = []
    changed = failed = 0
    codec_used: dict[str, int] = {}
    for i in range(count):
        raw = string_record(st_plain, i)
        if not any(b > 0x7F for b in raw):
            new_strings.append(raw)              # 纯 ASCII：原样照抄，最快
            continue
        text, codec = decode_any(raw, args.codec)
        if text is None:
            failed += 1
            new_strings.append(raw)              # 解不开就原样保留，绝不丢数据
            continue
        codec_used[codec] = codec_used.get(codec, 0) + 1
        nb = text.encode("utf-8")
        if nb != raw:
            changed += 1
        new_strings.append(nb)

    st_plain_new = build_stringtable(new_strings)
    # 长度补到 4 的倍数：解密是「每 4 字节一组」，长度不是 4 的倍数时最后一两组
    # 会在读写两侧产生不对称，表现为表尾 1~3 个字节变成垃圾。补零后两侧完全对称，
    # 多出来的零字节在末尾、没有任何 offset 指向它，不影响任何一条字符串。
    st_plain_new += b"\x00" * (pad4(len(st_plain_new)) - len(st_plain_new))
    st_crc_new = zlib.crc32(st_plain_new) & 0xFFFFFFFF
    delta = len(st_plain_new) - st.length
    dist = "、".join(f"{k} {v:,}" for k, v in sorted(codec_used.items(), key=lambda kv: -kv[1]))
    print(f"  转码：{changed:,} 条改写，{failed} 条解不开（保留原字节）")
    print(f"  编码分布：{dist or '（无非 ASCII）'}")
    print(f"  新表：{len(st_plain_new):,} B（{delta:+,} B / {delta/1048576:+.1f} MB）")

    # ---- 1b. 文本类文件：n_string.lst 指向的 *.kor.str（显示名在这里，不在字符串表） ----
    overrides: dict[int, tuple[bytes, int]] = {}
    n_files = n_lines = 0
    for e in entries:
        lp = e.path.lower()
        if lp in SKIP_TEXT or os.path.splitext(lp)[1] not in TEXT_EXTS:
            continue
        f.seek(data_start + e.rel)
        body = decrypt(f.read(pad4(e.length)), e.crc)[:e.length]
        new, _codec, changed = convert_text_body(body)
        if new is None:
            continue
        # 必须补到 4 字节再加密/记长度：读侧按 pad4(length) 整组解密，
        # 若是「明文未补齐、长度未补齐」，最后一组会被多解一次变成垃圾（文本尾巴变 \xaa）。
        # 用换行补齐，既保持 4 对齐又不往文本里塞 NUL。
        new += b"\n" * (pad4(len(new)) - len(new))
        overrides[id(e)] = (new, zlib.crc32(new) & 0xFFFFFFFF)
        n_files += 1
        n_lines += changed
    if n_files:
        print(f"  文本文件：{n_files:,} 个 / {n_lines:,} 行改写（*.str / *.txt）")

    # ---- 2. 重排数据区：按原 rel_offset 顺序，字符串表换新块 ----
    order = sorted(entries, key=lambda e: e.rel)
    src_size = os.path.getsize(args.src)
    plan = []                                    # (entry, chunk_len)
    for idx, e in enumerate(order):
        chunk = pad4(e.length)
        if idx + 1 < len(order):
            gap = order[idx + 1].rel - e.rel
            if gap != chunk:
                raise SystemExit(f"{e.path}: 源布局不连续（gap={gap} 期望={chunk}）")
        plan.append((e, chunk))
    # 数据区末尾可能还有一点尾巴（最后一条之后），原样保留
    last = order[-1]
    trailing = (src_size - data_start) - (last.rel + pad4(last.length))
    if trailing < 0:
        raise SystemExit("最后一个条目越过文件末尾")

    rel = 0
    new_layout = []                              # (entry, rel, payload, 是否新明文)
    for e, chunk in plan:
        if e is st:
            new_layout.append((e, rel, st_plain_new, True))
            rel += pad4(len(st_plain_new))
        elif id(e) in overrides:
            body = overrides[id(e)][0]
            new_layout.append((e, rel, body, True))
            rel += pad4(len(body))
        else:
            new_layout.append((e, rel, chunk, False))
            rel += chunk
    rel += trailing

    # ---- 3. 重建目录树 ----
    for e, r, _c, _is in new_layout:
        e.rel = r
    st.length = len(st_plain_new)
    st.crc = st_crc_new
    for e, _r, payload, is_new in new_layout:
        if is_new and e is not st:
            e.length = len(payload)
            e.crc = overrides[id(e)][1]
    na_paths = [e for e in entries if any(b > 0x7F for b in e.path_bytes)]
    for e in na_paths:
        text, codec = decode_any(e.path_bytes, args.codec)
        if text is None:
            continue
        e.path = text
        e.path_bytes = text.encode("utf-8")
    if na_paths:
        print(f"  路径：{len(na_paths)} 条含非 ASCII，已按同一套探测转码")

    tree_new = build_tree([e for e, _r, _c, _i in new_layout])
    if len(tree_new) != hdr["tree_len"]:
        # 路径变长会让目录树变长；data_start = 56 + tree_len，等于整体平移，
        # 而 rel_offset 是「相对数据区起点」的，不用改。
        print(f"  目录树 {hdr['tree_len']:,} → {len(tree_new):,} B（数据区整体平移 {len(tree_new)-hdr['tree_len']:+,} B）")
    total_new = HEADER_SIZE + len(tree_new) + rel
    print(f"  新文件：{total_new:,} B（{total_new - src_size:+,} B）")
    tree_crc_new = zlib.crc32(tree_new) & 0xFFFFFFFF

    if args.dry_run:
        print("  --dry-run：不写文件")
        return

    # ---- 4. 写新包 ----
    os.makedirs(os.path.dirname(os.path.abspath(args.dst)) or ".", exist_ok=True)
    with open(args.dst, "wb") as out:
        out.write(struct.pack("<i", 36) + hdr["guid"])
        out.write(struct.pack("<i", hdr["version"]))
        out.write(struct.pack("<i", len(tree_new)))
        out.write(struct.pack("<I", tree_crc_new))
        out.write(struct.pack("<i", hdr["num_files"]))
        out.write(encrypt(tree_new, tree_crc_new))

        chunk_size = 4 << 20
        for e, _r, payload, is_new in new_layout:
            if is_new:
                out.write(encrypt(payload, e.crc))
                out.write(b"\x00" * (pad4(len(payload)) - len(payload)))
                continue
            f.seek(data_start + e.orig_rel)
            remain = payload
            while remain > 0:
                n = min(chunk_size, remain)
                out.write(f.read(n))
                remain -= n

        # 末条之后的尾巴
        f.seek(data_start + last.orig_rel + pad4(last.length))
        remain = trailing
        while remain > 0:
            n = min(chunk_size, remain)
            out.write(f.read(n))
            remain -= n

    dt = time.time() - t0
    print(f"写出 {args.dst}：{os.path.getsize(args.dst):,} B，用时 {dt:.1f}s")

    # ---- 5. 回读自检 ----
    from pvf_unpack import PvfArchive              # noqa: E402
    ar = PvfArchive(args.dst)
    print(f"  自检：{len(ar.entries)} 条，条目数 {'一致' if len(ar.entries) == hdr['num_files'] else '不一致！'}")
    for path in ("equipment/character/swordman/avatar/coat/acoat_default.equ",
                 "character/swordman/swordman.chr"):
        try:
            raw = ar.read_raw(ar.entry(path))
        except KeyError:
            continue
        print(f"  自检 {path}：{len(raw)} B")


if __name__ == "__main__":
    main()
