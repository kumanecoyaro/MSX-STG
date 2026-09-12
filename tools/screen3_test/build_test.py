"""Assembles the SCREEN3 image display test (screen3_test.asm +
screen3_gen.py's generated RLE-compressed data tables) into a 32KB
standalone flat ROM - the exact same shape as the Round82 single-image
test that was confirmed working on real hardware ("おｋ意図通り表示
できた"): no ASCII16 bank-switching, no "ascii16" filename requirement.

(2026-09-12、実機フィードバック経緯): 6枚の生データ(16896byte)は
16KBの1バンクに収まらず、一度はASCII16バンク切替を試みたが実機で
改善しなかった("変わってないな")。ユーザー自身の指摘("この6枚で
16KBこえるのか?")を受け、バンク切替という不確実な領域へ踏み込む
代わりにRLE圧縮(12287byteまで削減)で単純に16KB以内へ収め、Round82で
既に実機確認済みの「単一バンク・バンク切替一切無し」という最も
確実な構成に戻した。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import screen3_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402


def assemble():
    body = open(os.path.join(HERE, "screen3_test.asm")).read()
    tables = screen3_gen.emit_asm_tables()
    text = body + "\n" + tables + "\n"
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    assert hi < 0x8000, f"content ({hi:04X}h) overflows the single 16KB bank (4000h-7FFFh) - RLE compression not tight enough"
    mem = bytearray(16384)
    for a, b in out.items():
        mem[a - 0x4000] = b
    rom_path = os.path.join(HERE, "Screen3Test.rom")
    with open(rom_path, "wb") as f:
        f.write(bytes(mem) * 2)  # doubled to 32KB, matches the confirmed-working Round82 convention
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes), wrote {rom_path} (32768 bytes)")
    print("INIT =", hex(sym["INIT"]))
    return out, sym, text


if __name__ == "__main__":
    main()
