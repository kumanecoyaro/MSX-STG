"""tools/ebuz_test/ebuz_test.asm を素の16KB MSX ROM(バンク切替不要、
ASCII16マッパー無し)としてビルドする。中身は210byte程度と極小で、
16KBに収まりきるため、標準的な16KB ROMカートリッジとしてそのまま
任意のMSX1エミュレータ/実機で動作する。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler


def assemble():
    with open(os.path.join(HERE, "ebuz_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    rom = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if not (0x4000 <= addr <= 0x7FFF):
            raise Exception(f"address {addr:04X}h outside the single 16KB page (4000h-7FFFh)")
        rom[addr - 0x4000] = val
    rom_path = os.path.join(HERE, "EbuzTest.rom")
    with open(rom_path, "wb") as f:
        f.write(rom)
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes), wrote {rom_path}: {len(rom)} bytes (plain 16KB ROM)")
    print("INIT =", hex(sym["INIT"]))
    return out, sym, text


if __name__ == "__main__":
    main()
