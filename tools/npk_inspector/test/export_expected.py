#!/usr/bin/env python3
"""用 Python 参考实现导出期望值（索引 + 帧字段 + 像素 SHA-256 + OGG 信息）。"""
import sys, os, json, hashlib
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import npk_parser as P
import npk_v1_walk as V1

SF85 = '/mnt/e/dnf-sf/sf85/老牛DNF客户端/ImagePacks2'
SF115 = '/mnt/e/dnf-sf/sf115/人造神客户端'

CASES = [
    ('vehicle',   SF85 + '/sprite_monster_vehicle.NPK', 'sprite/monster/vehicle/battlingram.img'),
    ('pushick',   SF85 + '/sprite_monster_vehicle.NPK', 'sprite/monster/vehicle/pushick.img'),
    ('cannonball', SF85 + '/sprite_monster_vehicle.NPK', 'sprite/monster/vehicle/cannonball.img'),
    ('face_atlas', SF115 + '/ImagePacks2/1A冥灵之塔补丁.NPK', 'sprite/monster/ch_monsterface.img'),
    ('sysfont',   '/mnt/e/dnf-sf/sf115/人造神客户端/ImagePacks2/!                                                       sprite_common_digit_tp.NPK',
                  'red_systemfont.img'),
]

def main():
    out = {'npks': {}, 'imgs': {}, 'oggs': {}}
    # v4 对齐用例（Python 参考实现对 v4 未压缩 0x0E 帧按 1B/px 走会错位，
    # 这里只记录文件路径，由 JS 端做“体长精确到文件尾”的对齐断言）
    out['v4pack'] = {'path': SF85 + '/sprite_character_demoniclancer_equipment_avatar_belt.NPK',
                     'size': os.path.getsize(SF85 + '/sprite_character_demoniclancer_equipment_avatar_belt.NPK')}
    # 索引整体对拍
    for key, path in [('vehicle', SF85 + '/sprite_monster_vehicle.NPK'),
                      ('atlas', SF115 + '/ImagePacks2/1A冥灵之塔补丁.NPK'),
                      ('v1pack', SF115 + '/ImagePacks2/!!!!!!!!!!!!!!!!!!整合的NPK.NPK')]:
        n = P.Npk(path)
        out['npks'][key] = {'path': path, 'fileSize': n.file_size,
                            'entries': [[e.name, e.offset, e.size] for e in n.entries]}

    for key, path, entry in CASES:
        n = P.Npk(path)
        raw = n.read(entry)
        im = P.Img(raw)
        item = {'path': path, 'entry': entry, 'size': len(raw), 'version': im.version,
                'frameCount': len(im.frames), 'paletteSizes': [len(p) for p in im.palettes],
                'dds': [], 'frames': []}
        for d in getattr(im, 'dds_table', []) or []:
            item['dds'].append({k: d.get(k) for k in ('title', 'pixel_format', 'full_length', 'length', 'width', 'height')})
        for i, f in enumerate(im.frames):
            w, h, x, y, px = im.frame_image(i)
            item['frames'].append({
                'type': f.type, 'compressed': f.compressed, 'w': f.width, 'h': f.height,
                'x': f.x, 'y': f.y, 'cw': f.frame_width, 'ch': f.frame_height,
                'length': f.length, 'ref': f.reference, 'dds': f.dds_index,
                'crop': [f.left, f.up, f.right, f.down],
                'ow': w, 'oh': h, 'sha256': hashlib.sha256(px).hexdigest(),
            })
        out['imgs'][key] = item
        print('%s: v%d %d frames, %d bytes' % (key, im.version, len(im.frames), len(raw)), file=sys.stderr)

    for key, path, entry in [
        ('ui_acc', SF115 + '/SoundPacks/! sounds_equip_acc.npk', 'sounds/equip/acc/assist_touch.ogg'),
        ('pet', SF115 + '/SoundPacks/sounds_pet.npk', 'sounds/pet/falcon_hit.ogg'),
    ]:
        try:
            n = P.Npk(path)
            raw = n.read(entry)
        except Exception as e:
            print('skip ogg %s: %s' % (key, e), file=sys.stderr)
            continue
        # 第一页 body 紧跟页头(27B)+段表
        segs = raw[26]
        b = 27 + segs
        assert raw[:4] == b'OggS' and raw[b] == 1 and raw[b+1:b+7] == b'vorbis'
        info = {'channels': raw[b+11], 'sample_rate': int.from_bytes(raw[b+12:b+16], 'little')}
        out['oggs'][key] = {'path': path, 'entry': entry, 'size': len(raw),
                            'channels': info.get('channels'), 'sampleRate': info.get('sample_rate'),
                            'sha256': hashlib.sha256(raw).hexdigest()}
    # v1 用例（Python 的 Img 不支持 v1，用独立 v1 工具对拍）
    v1path = SF115 + '/ImagePacks2/!!!!!!!!!!!!!!!!!!整合的NPK.NPK'
    v1entry = 'sprite/common/commoneffect/blast1.img'
    v1raw = P.Npk(v1path).read(v1entry)
    ver, fc, recs, end = V1.parse_v1(v1raw)
    frames = []
    resolved = []
    for i, (kind, data) in enumerate(recs):
        if kind == 'ref':
            resolved.append(data[0]); continue
        resolved.append(i)
    for i, (kind, data) in enumerate(recs):
        if kind == 'ref':
            real = resolved[i]
            f = recs[real][1]
            frames.append({'type': 0x11, 'ref': data[0], 'ow': f[2], 'oh': f[3],
                           'sha256': hashlib.sha256(V1.to_rgba(V1.frame_bytes(v1raw, f), f[0], f[2], f[3])).hexdigest()})
            continue
        t, c, w, h, length, x, y, fw, fh, off = data
        px = V1.to_rgba(V1.frame_bytes(v1raw, data), t, w, h)
        frames.append({'type': t, 'compressed': c, 'w': w, 'h': h, 'x': x, 'y': y,
                       'cw': fw, 'ch': fh, 'length': length, 'ref': -1, 'dds': -1,
                       'crop': [0, 0, 0, 0], 'ow': w, 'oh': h,
                       'sha256': hashlib.sha256(px).hexdigest()})
    out['imgs']['blast_v1'] = {'path': v1path, 'entry': v1entry, 'size': len(v1raw),
                               'version': ver, 'frameCount': fc, 'paletteSizes': [],
                               'dds': [], 'frames': frames, 'align': end == len(v1raw)}
    json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'expected.json'), 'w'),
              ensure_ascii=False, indent=0)
    print('wrote expected.json', file=sys.stderr)

if __name__ == '__main__':
    main()
