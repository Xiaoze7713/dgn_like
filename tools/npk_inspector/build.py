#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 web/ 下的 html + css + js + 内置示例打包成单个 HTML（可双击离线打开）。"""
import argparse
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
WEB = os.path.join(HERE, 'web')


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=os.path.join(HERE, 'dist', 'NpkInspector.html'))
    args = ap.parse_args()

    html = read(os.path.join(WEB, 'index.html'))
    css = read(os.path.join(WEB, 'style.css'))
    html = html.replace('<link rel="stylesheet" href="style.css">', '<style>\n' + css + '\n</style>')

    def repl(m):
        src = m.group(1)
        path = os.path.normpath(os.path.join(WEB, src))
        body = read(path)
        body = body.replace('</script', '<\\/script')
        return '<script>/* ' + os.path.basename(path) + ' */\n' + body + '\n</script>'

    html, n = re.subn(r'<script src="([^"]+)"></script>', repl, html)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as f:
        f.write(html)
    print('inlined %d scripts -> %s (%d KB)' % (n, args.out, os.path.getsize(args.out) // 1024))


if __name__ == '__main__':
    main()
