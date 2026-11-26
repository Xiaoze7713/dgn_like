#!/usr/bin/env python3
"""新版 PVF 外层「wrapper」解密器（国服 34.3.13.22 实测通过）。

流程（实测复现自 gitgud.io RicardoLz/115 文档 + 本机验证）：
  1. 从 DNF.exe 里抓 '-----BEGIN PRIVATE KEY-----' PEM（RSA-1024）与其后
     0x200 窗口内首个 64 位大写 hex（= wrapKey，AES-256）。
  2. sk.dat: 每 128 B 一块 → RSA/PKCS1v15 私钥解密 → 得 117 B 明文块；
     拼回 L 字节 → 前 L-(L%256) 字节 AES-256-CBC(零 IV, 无填充) 解密，
     尾部原样 → N*32 字节密钥链。
  3. Script.pvf: 按 10,485,760 B(0xa00000) 切段，每段前 0x2800 B 用
     chain[i] AES-256-CBC(零 IV, 无填充) 原地解密 → *inner.pvf（等长）。

用法:
  python3 tools/pvf_new_unwrap.py --exe dnf_latest/DNF.exe \
      --sk dnf_latest/sk.dat --pvf dnf_latest/Script.pvf \
      --out /tmp/Script.inner.pvf --chain-out /tmp/chain.bin
"""
import argparse
import re
import struct
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

SEG = 0xA00000          # 10 MiB
HDR = 0x2800            # 每段头部密文长度
RSA_BLOCK = 128         # RSA-1024
CHUNK = 117             # PKCS#1 v1.5 单块可承载明文（128-11）


def derive_keys(exe_path):
    """返回 (pem_bytes, private_key, wrap_key_bytes, aes_hex)。"""
    data = open(exe_path, 'rb').read()
    hits = []
    for m in re.finditer(rb'-----BEGIN (?:RSA )?PRIVATE KEY-----', data):
        end = data.find(b'-----END', m.start())
        if end < 0:
            continue
        end = data.find(b'-----', end + 9) + 5
        pem = data[m.start():end]
        window = data[end:end + 0x200]
        h = re.search(rb'(?<![0-9A-Fa-f])[0-9A-F]{64}(?![0-9A-Fa-f])', window)
        hits.append((m.start(), pem, h.group(0).decode() if h else None))
    if not hits:
        sys.exit('DNF.exe 内没有 PRIVATE KEY')
    ok = None
    for off, pem, aes_hex in hits:
        if not aes_hex:
            continue
        try:
            key = serialization.load_pem_private_key(pem, password=None)
        except Exception as e:            # noqa: BLE001
            print(f'  [-] PEM@{off} 载入失败: {e}')
            continue
        print(f'  [+] PEM@{off} 可用, wrapKey={aes_hex}')
        ok = (pem, key, bytes.fromhex(aes_hex), aes_hex)
        break
    if ok is None:
        sys.exit('没有同时带 AES 候选的 PEM')
    return ok


def unwrap_skdat(sk_path, priv, wrap_key):
    blob = open(sk_path, 'rb').read()
    n = len(blob) // RSA_BLOCK
    print(f'  sk.dat {len(blob)} B = {n} 块 RSA')
    plain = b''.join(
        priv.decrypt(blob[i * RSA_BLOCK:(i + 1) * RSA_BLOCK], padding.PKCS1v15())
        for i in range(n)
    )
    L = len(plain)
    pre = L - (L % 256)
    dec = Cipher(algorithms.AES(wrap_key), modes.CBC(bytes(16))).decryptor()
    chain = dec.update(plain[:pre]) + dec.finalize() + plain[pre:]
    print(f'  链: {L} B → {len(chain)} B = {len(chain) // 32} 把钥匙')
    return chain


def unwrap_pvf(pvf_path, out_path, chain):
    import os
    size = os.path.getsize(pvf_path)
    segs = (size + SEG - 1) // SEG
    print(f'  {pvf_path}: {size} B → {segs} 段, 链 {len(chain) // 32} 把')
    if segs > len(chain) // 32:
        sys.exit(f'钥匙不够: 需要 {segs}, 只有 {len(chain) // 32}')
    with open(pvf_path, 'rb') as src, open(out_path, 'wb') as dst:
        for i in range(segs):
            hdr = src.read(HDR)
            dec = Cipher(algorithms.AES(chain[i * 32:(i + 1) * 32]),
                         modes.CBC(bytes(16))).decryptor()
            dst.write(dec.update(hdr) + dec.finalize())
            left = min(size - (i * SEG + HDR), SEG - HDR)
            while left > 0:
                b = src.read(min(left, 1 << 22))
                if not b:
                    break
                dst.write(b)
                left -= len(b)
            print(f'    段 {i + 1}/{segs}', end='\r', flush=True)
    print(f'\n  → {out_path}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--exe', required=True)
    ap.add_argument('--sk', required=True)
    ap.add_argument('--pvf', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--chain-out')
    a = ap.parse_args()
    print('[*] 提取私钥 / wrapKey')
    _pem, priv, wrap_key, _hex = derive_keys(a.exe)
    print('[*] 解 sk.dat')
    chain = unwrap_skdat(a.sk, priv, wrap_key)
    if a.chain_out:
        open(a.chain_out, 'wb').write(chain)
        print(f'  链已存 {a.chain_out}')
    print('[*] 解 PVF wrapper')
    unwrap_pvf(a.pvf, a.out, chain)


if __name__ == '__main__':
    main()
