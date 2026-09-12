"""Assembles the SCREEN3 image display test (screen3_test.asm +
screen3_gen.py's generated data tables) into a 32KB standalone flat ROM
(same shape as tools/stage2_terrain/build_test.py - no ASCII16 paging
needed, the whole thing fits in one 16KB page doubled to 32KB)."""
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
    mem = bytearray(16384)
    for a, b in out.items():
        mem[a - 0x4000] = b
    rom_path = os.path.join(HERE, "Screen3Test.rom")
    with open(rom_path, "wb") as f:
        f.write(bytes(mem) * 2)  # doubled to 32KB, matches terrain_test.rom's own convention
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes), wrote {rom_path} (32768 bytes)")
    print("INIT =", hex(sym["INIT"]))
    return out, sym, text


if __name__ == "__main__":
    main()
