#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生产版：把全量 `.ani` 解析成「帧表」数据集（P0.5 收尾）。

输入：`export/text/**/*.ani.bin`（PVF 原样二进制）
输出：`export/ani/<shard>.jsonl`（每行一个 ani 的帧表，字段见 docs/ANI-FORMAT.md §7）
      每帧含 `i/x/y/d/t/img/ab/db/flag/fx`；`flag` = `[FLAG]` flagIndex（i32），缺省 = 该帧无 flag 事件。

为什么用 JSONL 而不是 sqlite：
  * 引擎/GDScript 侧零依赖：`FileAccess` 逐行读 + `JSON.parse_string` 即可，不需要 sqlite 绑定；
  * 按分片并行/按需加载（实现组只关心 `monster/` 时就只读那几个分片）；
  * 追加写 + 断点续跑天然友好（写坏一行不会毁整个库）。
  体积代价可接受：实测约 1.6 KB/文件（≈1.66 GiB 全量），仍小于原始二进制。
  若将来需要随机查询（"给我某 ani 的第 3 帧"），再从 JSONL 建一次 sqlite 索引即可。

断点续跑：每个 chunk 写成 `export/ani/.parts/<shard>__<idx>.part`（先写 .tmp 再 rename，
所以半截文件不会被误认为完成）。重跑时已存在的 part 直接跳过，只补没跑完的 chunk。

用法：
  # 全量导出（10 进程）
  .venv/bin/python tools/export_ani_tables.py --run --jobs 10
  # 只跑某个根目录
  .venv/bin/python tools/export_ani_tables.py --run --only monster --jobs 8
  # 体检（不写盘）
  .venv/bin/python tools/export_ani_tables.py --stats-only --jobs 10
  # 把 part 汇总成分片文件（--run 结束会自动做）
  .venv/bin/python tools/export_ani_tables.py --finalize
"""
from __future__ import annotations

import argparse
import glob
import json
import multiprocessing as mp
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from tools.ani_parser import parse_ani, to_frame_table  # noqa: E402

TEXT = os.path.join(ROOT, 'export', 'text')
OUT = os.path.join(ROOT, 'export', 'ani')
PARTS = os.path.join(OUT, '.parts')
CHUNK = 4000
BIG_ROOT = 120000          # 超过这个数量的根目录，分片下沉一级（equipment/character…）

# 职业（用于 QUALITY.md 的「按职业」统计）
CLASSES = [
    'swordman', 'fighter', 'gunner', 'mage', 'priest', 'thief',
    'atswordman', 'atfighter', 'atgunner', 'atmage', 'atpriest', 'atthief',
    'demoniclancer', 'creator', 'darkknight', 'specialist', 'kunofighter', 'demonslayer',
]


# ---------------------------------------------------------------------------
# 路径工具
# ---------------------------------------------------------------------------
def iter_files():
    """产出 (pvf_path, abs_path)，按字典序遍历。"""
    for p in sorted(glob.glob(os.path.join(TEXT, '**', '*.ani.bin'), recursive=True)):
        rel = os.path.relpath(p, TEXT).replace(os.sep, '/')
        yield rel[:-4], p          # 去掉 '.bin'


def shard_of(pvf_path, depth_of):
    parts = pvf_path.split('/')
    root = parts[0]
    return '/'.join(parts[:depth_of(root)])


def version_tag(pvf_path):
    """从路径里推断「版本/世代」标签（用于按版本统计）。"""
    low = pvf_path.lower()
    segs = low.split('/')
    for s in segs[:-1]:
        if s.startswith('act') and s[3:].isdigit():
            return s                                  # act8 / act10
        if s.isdigit() and len(s) == 4 and s >= '2000':  # contents/2022/...
            return 'year' + s
        if len(s) > 5 and s[:3].isdigit() and 'level' in s:  # 110levelnormaldungeon
            return s[:3] + 'lvl'
    return 'base'


def class_tag(pvf_path):
    for seg in pvf_path.lower().split('/'):
        if seg in CLASSES:
            return seg
    return '(非职业)'


# ---------------------------------------------------------------------------
# 序列化：省略 null 的 fx 子键（体积减半；缺省即 null，见 READ-EXAMPLE.md）
# ---------------------------------------------------------------------------
def serialize_record(rec):
    frames = []
    for f in rec['frames']:
        fr = {'i': f['i'], 'x': f['x'], 'y': f['y'], 'd': f['d'], 't': f['t']}
        if f['img']:
            fr['img'] = f['img']
        if f['ab']:
            fr['ab'] = f['ab']
        if f['db']:
            fr['db'] = f['db']
        if f.get('flag') is not None:
            fr['flag'] = f['flag']
        fx = {k: v for k, v in f['fx'].items() if v is not None}
        if fx:
            fr['fx'] = fx
        frames.append(fr)
    out = {'src': rec['src'], 'ani_frames': rec['ani_frames'],
           'images': rec['images'], 'total_ms': rec['total_ms'], 'frames': frames}
    if not rec['clean']:
        out['clean'] = False
    return json.dumps(out, ensure_ascii=False, separators=(',', ':'))


def classify_error(info):
    err = info.get('error') or ''
    if not info.get('size'):
        return '空文件'
    if err.startswith('头部损坏'):
        return '头部损坏' if '越界' not in err else '截断(头部路径越界)'
    if err.startswith('无法解析帧结构'):
        return '帧文法变体/未知 id'
    return '其它'


# ---------------------------------------------------------------------------
# worker
# ---------------------------------------------------------------------------
_W = {'tpl': None}


def _init():
    _W['tpl'] = None


def process_chunk(args):
    """args = (shard, chunk_idx, [(pvf_path, abs_path), ...], write: bool)"""
    shard, idx, items, write = args
    out_lines = []
    st = {'n': 0, 'ok': 0, 'clean': 0, 'dirty': 0, 'fail': 0,
          'frames': 0, 'atk': 0, 'dmg': 0, 'img_refs': 0,
          'err': {}, 'fails': [], 'max_frames': 0, 'cls': {}, 'ver': {}}
    for pvf, abs_path in items:
        st['n'] += 1
        cls = class_tag(pvf)
        ver = version_tag(pvf)
        c = st['cls'].setdefault(cls, [0, 0, 0])      # n, ok, fail
        v = st['ver'].setdefault(ver, [0, 0, 0])
        c[0] += 1
        v[0] += 1
        try:
            data = open(abs_path, 'rb').read()
        except OSError as exc:
            st['fail'] += 1
            c[2] += 1
            v[2] += 1
            st['err']['读取失败'] = st['err'].get('读取失败', 0) + 1
            if len(st['fails']) < 3:
                st['fails'].append([pvf, '读取失败: %s' % exc])
            continue
        info = parse_ani(data)
        if not info['ok']:
            st['fail'] += 1
            c[2] += 1
            v[2] += 1
            k = classify_error(info)
            st['err'][k] = st['err'].get(k, 0) + 1
            if len(st['fails']) < 3:
                st['fails'].append([pvf, info.get('error') or 'unknown'])
            if write:
                out_lines.append(json.dumps({'src': pvf, 'error': info.get('error')},
                                            ensure_ascii=False, separators=(',', ':')))
            continue
        st['ok'] += 1
        c[1] += 1
        v[1] += 1
        st['clean' if info['clean'] else 'dirty'] += 1
        nf = len(info['frames'])
        st['frames'] += nf
        st['max_frames'] = max(st['max_frames'], nf)
        st['img_refs'] += len(info['images'])
        rec = to_frame_table(info, pvf)
        st['atk'] += sum(1 for f in info['frames'] if f['attack_boxes'])
        st['dmg'] += sum(1 for f in info['frames'] if f['damage_boxes'])
        if write:
            out_lines.append(serialize_record(rec))
    if write and out_lines:
        tmp = os.path.join(PARTS, '%s__%05d.tmp' % (shard.replace('/', '__'), idx))
        dst = os.path.join(PARTS, '%s__%05d.part' % (shard.replace('/', '__'), idx))
        with open(tmp, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(out_lines))
            fh.write('\n')
        os.replace(tmp, dst)
    return shard, idx, st


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
def build_tasks(only=None, limit=0, stats_only=False):
    files = list(iter_files())
    if only:
        only = set(o.lower() for o in only)
        files = [f for f in files if f[0].split('/')[0].lower() in only]
    if limit:
        files = files[:limit]
    counts = {}
    for pvf, _ in files:
        counts[pvf.split('/')[0]] = counts.get(pvf.split('/')[0], 0) + 1
    depth = {r: (2 if c > BIG_ROOT else 1) for r, c in counts.items()}
    buckets = {}
    write = not stats_only
    for pvf, abs_path in files:
        buckets.setdefault(shard_of(pvf, lambda r: depth[r]), []).append((pvf, abs_path))
    tasks = []
    for shard in sorted(buckets):
        items = buckets[shard]
        for i in range(0, len(items), CHUNK):
            tasks.append((shard, i // CHUNK, items[i:i + CHUNK], write))
    return files, tasks, counts


def run(args):
    os.makedirs(PARTS, exist_ok=True)
    files, tasks, counts = build_tasks(args.only, args.limit, args.stats_only)
    todo = []
    skipped = 0
    for shard, idx, items, write in tasks:
        dst = os.path.join(PARTS, '%s__%05d.part' % (shard.replace('/', '__'), idx))
        if write and os.path.exists(dst) and os.path.getsize(dst) > 0:
            skipped += 1
            continue
        todo.append((shard, idx, items, write))
    print('文件 %d 个 / 分片 %d 个 / chunk %d（已完成 %d，待跑 %d），jobs=%d'
          % (len(files), len({t[0] for t in tasks}), len(tasks), skipped, len(todo), args.jobs), flush=True)
    t0 = time.time()
    stats = {}
    done = 0
    with mp.Pool(args.jobs, initializer=_init) as pool:
        for shard, idx, st in pool.imap_unordered(process_chunk, todo, chunksize=1):
            done += 1
            s = stats.setdefault(shard, {'n': 0, 'ok': 0, 'clean': 0, 'dirty': 0, 'fail': 0,
                                         'frames': 0, 'atk': 0, 'dmg': 0, 'img_refs': 0,
                                         'err': {}, 'fails': [], 'max_frames': 0, 'chunks': 0,
                                         'cls': {}, 'ver': {}})
            s['chunks'] += 1
            for k in ('n', 'ok', 'clean', 'dirty', 'fail', 'frames', 'atk', 'dmg', 'img_refs'):
                s[k] += st[k]
            s['max_frames'] = max(s['max_frames'], st['max_frames'])
            for k, val in st['err'].items():
                s['err'][k] = s['err'].get(k, 0) + val
            for grp in ('cls', 'ver'):
                for k, val in st[grp].items():
                    cur = s[grp].setdefault(k, [0, 0, 0])
                    for i in range(3):
                        cur[i] += val[i]
            for row in st['fails']:
                if len(s['fails']) < 400:
                    s['fails'].append(row)
            if done % 20 == 0 or done == len(todo):
                el = time.time() - t0
                print('  %d/%d chunk  %.1fs  已写 %d 个 ani  (%.2f ms/文件)'
                      % (done, len(todo), el,
                         sum(x['n'] for x in stats.values()),
                         el * 1000 / max(1, sum(x['n'] for x in stats.values()))), flush=True)
    total = {'files': sum(x['n'] for x in stats.values()),
             'seconds': round(time.time() - t0, 1),
             'jobs': args.jobs, 'skipped_chunks': skipped}
    write_stats(stats, total, args)
    print('完成：%d 个 ani，%.1fs，%s' % (total['files'], total['seconds'],
          '已写盘' if not args.stats_only else '未写盘(stats)'), flush=True)
    if not args.stats_only and not args.no_finalize:
        finalize()


def write_stats(stats, total, args):
    merged = {'shards': stats, 'total': total, 'when': time.strftime('%F %T')}
    if args.stats_only:
        merged['total']['mode'] = 'stats-only'
        # 子集跑（--only/--limit）不覆盖全量权威统计
        if args.only or args.limit:
            tag = '-'.join(args.only or []) or 'limit'
            dst = os.path.join(OUT, '_stats_subset_%s_%d.json' % (tag.replace('/', '_'), args.limit))
        else:
            dst = os.path.join(OUT, '_stats_only.json')
    else:
        dst = os.path.join(OUT, '_stats.json')
    os.makedirs(OUT, exist_ok=True)
    tmp = dst + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(merged, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, dst)
    print('统计写入 %s' % dst, flush=True)


def finalize(only=None):
    """把 .parts 汇总成 export/ani/<shard>.jsonl。"""
    os.makedirs(OUT, exist_ok=True)
    groups = {}
    for p in glob.glob(os.path.join(PARTS, '*.part')):
        name = os.path.basename(p)[:-5]
        shard, _, idx = name.rpartition('__')
        groups.setdefault(shard, []).append((idx, p))
    n = 0
    for shard, parts in sorted(groups.items()):
        dst = os.path.join(OUT, shard + '.jsonl')
        tmp = dst + '.tmp'
        with open(tmp, 'w', encoding='utf-8') as out:
            for idx, p in sorted(parts):
                with open(p, encoding='utf-8') as fh:
                    while True:
                        chunk = fh.read(1 << 20)
                        if not chunk:
                            break
                        out.write(chunk)
        os.replace(tmp, dst)
        n += 1
        print('  汇总 %-40s %d part -> %.1f MB' % (shard, len(parts), os.path.getsize(dst) / 1e6))
    print('汇总完成：%d 个分片文件 -> %s' % (n, OUT), flush=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description='全量导出 .ani 帧表')
    ap.add_argument('--run', action='store_true', help='全量跑并写盘')
    ap.add_argument('--stats-only', action='store_true', help='只统计，不写盘')
    ap.add_argument('--finalize', action='store_true', help='只把 .parts 汇总成分片 JSONL')
    ap.add_argument('--jobs', type=int, default=10)
    ap.add_argument('--only', nargs='*', help='只处理这些根目录（monster equipment …）')
    ap.add_argument('--limit', type=int, default=0, help='只处理前 N 个文件（冒烟测试）')
    ap.add_argument('--no-finalize', action='store_true', help='跑完不自动汇总')
    args = ap.parse_args(argv)
    if args.finalize:
        finalize()
        return 0
    if not (args.run or args.stats_only):
        ap.print_help()
        return 2
    run(args)
    return 0


if __name__ == '__main__':
    sys.exit(main())
