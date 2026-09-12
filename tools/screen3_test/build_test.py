"""Assembles the SCREEN3 image display test (screen3_test.asm +
screen3_gen.py's generated data tables) into a real 2-bank ASCII16
megaROM (same shape/convention as tools/title_screen/build_test.py and
tools/stage2_combined/build_test.py - see screen3_test.asm's own
comment on why this project's real hardware/flashcart requires this
exact convention: bank0=page1(4000h-7FFFh)/bank1=page2(8000h-BFFFh)
split, the 32KB result doubled to 64KB, and "ascii16" in the filename -
a plain 32KB flat image (this file's own original, WRONG approach) is
not reliably recognized as a megaROM and left window B's mapping
undefined)."""
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


def build_banks(out):
    """Splits the flat address->byte dict into bank0(page1,4000h-7FFFh)/
    bank1(page2,8000h-BFFFh) - same convention as tools/stage2_combined/
    build_test.py's own build_banks()."""
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
    # doubled to 64KB - real-hardware/flashcart-required convention this
    # project already learned the hard way (see tools/stage2_combined/
    # build_test.py's own comment): a plain 32KB image isn't reliably
    # auto-detected as an ASCII16 megaROM, leaving window B undefined.
    rom = rom32 + rom32
    rom_path = os.path.join(HERE, "Screen3Test.ascii16k.rom")
    with open(rom_path, "wb") as f:
        f.write(rom)
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes across bank0+bank1), "
          f"wrote {rom_path}: {len(rom)} bytes (doubled)")
    print("INIT =", hex(sym["INIT"]))
    return out, sym, text


if __name__ == "__main__":
    main()
