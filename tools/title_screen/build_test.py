"""Assembles the title-screen bank test standalone (own ASCII16 2-bank
image, same convention as tools/stage2_combined/build_test.py) so it can
be verified on its own before wiring into tools/bankswitch_poc/
build_full_rom.py's own bigger 3-pair ROM.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import title_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402

DRAW_LOOP_PLACEHOLDER = "; ===== TITLE_BOSS1_DRAW_LOOP placeholder, filled in by build_test.py ====="


def combined_text():
    body = open(os.path.join(HERE, "title_test.asm")).read()
    assert body.count(DRAW_LOOP_PLACEHOLDER) == 1, "draw-loop placeholder not found (or not unique) - source drifted"
    draw_loop = title_gen.emit_boss1_draw_loop(namtbl=0x1800, start_row=2, start_col=2)
    body = body.replace(DRAW_LOOP_PLACEHOLDER, draw_loop, 1)
    return body + "\n" + title_gen.emit_asm_tables() + "\n"


def assemble():
    text = combined_text()
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def build_banks(out):
    bank0 = bytearray([0xFF] * 0x4000)
    bank1 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if 0x4000 <= addr <= 0x7FFF:
            bank0[addr - 0x4000] = val
        elif 0x8000 <= addr <= 0xBFFF:
            bank1[addr - 0x8000] = val
        else:
            raise Exception(f"address {addr:04X}h outside 4000h-BFFFh (bank0+bank1 budget exceeded)")
    return bank0, bank1


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    bank0, bank1 = build_banks(out)
    rom32 = bytes(bank0) + bytes(bank1)
    rom = rom32 + rom32  # doubled to 64KB - same real-hardware convention as stage2_combined
    rom_path = os.path.join(HERE, "CyberS Title.ascii16k.rom")
    with open(rom_path, "wb") as f:
        f.write(rom)
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes across bank0+bank1), wrote {rom_path}: {len(rom)} bytes (doubled)")
    print("INIT =", hex(sym["INIT"]))
    return out, sym, text


if __name__ == "__main__":
    main()
