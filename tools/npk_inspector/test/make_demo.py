#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 web/demo_data.js：内嵌一个多版本样例 NPK（单文件版直接用，无需外部文件）。"""
import base64
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
import npk_parser as P

SF85 = '/mnt/e/dnf-sf/sf85/老牛DNF客户端'
SF115 = '/mnt/e/dnf-sf/sf115/人造神客户端'

VEH = SF85 + '/ImagePacks2/sprite_monster_vehicle.NPK'
ATLAS = SF115 + '/ImagePacks2/1A冥灵之塔补丁.NPK'
DIGIT = (SF115 + '/ImagePacks2/!'
         '                                                       sprite_common_digit_tp.NPK')
V1PACK = SF115 + '/ImagePacks2/!!!!!!!!!!!!!!!!!!整合的NPK.NPK'
V4 = (SF85 + '/ImagePacks2/sprite_character_demoniclancer_equipment_avatar_belt.NPK')
SOUND = SF115 + '/SoundPacks/sounds_pet.npk'
SKIN = SF85 + '/ImagePacks2/sprite_character_swordman_atequipment_avatar_skin.NPK'
COAT = SF85 + '/ImagePacks2/sprite_character_swordman_atequipment_avatar_coat.NPK'
WEAP = SF85 + '/ImagePacks2/sprite_character_swordman_atequipment_weapon_beamswd.NPK'

ITEMS = [
    ('sprite/monster/vehicle/battlingram.img', VEH, 'v2 普通动画：12 帧独立像素，一张一张存'),
    ('sprite/monster/vehicle/pushick.img', VEH, 'v2 / ARGB8888：每帧 4 字节真彩'),
    ('sprite/monster/vehicle/cannonball.img', VEH, 'v2 / ARGB1555：2 字节带 1bit 透明'),
    ('sprite/monster/ch_monsterface.img', ATLAS, 'v5 共享贴图：235 帧切自 4 张 DDS（本工具的重点展板）'),
    ('red_systemfont.img', DIGIT, 'v5 但没有共享大图：11 帧各自一张小 DDS'),
    ('sprite/common/commoneffect/blast1.img', V1PACK, 'v1 旧格式：36B 记录后紧跟本帧帧体，交替排列'),
    ('sprite/character/demoniclancer/equipment/avatar/belt/dl_belt0100a.img', V4,
     'v4 调色板：4 色盘 + 182 帧；zlib 帧存调色板索引，未压缩帧仍是 ARGB1555'),
    ('sounds/pet/falcon_hit.ogg', SOUND, 'NPK 里的 ogg 音频：波形 + Ogg 页表'),
    ('sprite/character/swordman/atequipment/avatar/skin/sg_body0000.img', SKIN,
     '角色身体层：v4、500×500 画布、222 帧。到「拼装」页再加衣服层看合成'),
    ('sprite/character/swordman/atequipment/avatar/coat/sg_coat0100a.img', COAT,
     '同一套动作的上衣层：也是 222 帧 / 500×500 画布，在「拼装」页叠到身体上'),
    ('sprite/character/swordman/atequipment/weapon/beamswd/sg_beamswd0000a1.img', WEAP,
     '武器层：同样 222 帧，刀光会伸到身体外；三层叠起来就是完整角色'),
]


def main():
    items = []
    for name, pack, _ in ITEMS:
        raw = P.Npk(pack).read(name)
        items.append((name, raw))
        print('%-52s %7d' % (name, len(raw)))
    blob = P.build_npk(items)
    b64 = base64.b64encode(blob).decode('ascii')
    out = os.path.join(os.path.dirname(__file__), '..', 'web', 'demo_data.js')
    with open(out, 'w', encoding='utf-8') as f:
        f.write('// 由 test/make_demo.py 生成，请勿手改\n')
        f.write('window.DEMO_NPK = {\n  name: "demo_showcase.npk",\n')
        f.write('  size: %d,\n  b64: "%s",\n' % (len(blob), b64))
        f.write('  notes: {\n')
        for name, _, note in ITEMS:
            f.write('    %s: %s,\n' % (repr(name).replace("'", '"'), repr(note).replace("'", '"')
                                        .replace('\\\\', '\\\\')))
        f.write('  },\n};\n')
    print('demo.npk %d 字节 -> %s' % (len(blob), os.path.abspath(out)))


if __name__ == '__main__':
    main()
