"""Assembles the tank sprite test (tank_test.asm + tank_gen.py's
generated tables) into a 32KB standalone ROM."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import tank_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402


def assemble():
    body = open(os.path.join(HERE, "tank_test.asm")).read()
    tables = tank_gen.emit_asm_tables()
    text = body + "\n" + tables + "\n"
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    mem = bytearray(32768)
    for a, b in out.items():
        mem[a - 0x4000] = b
    rom_path = os.path.join(HERE, "tank_test.rom")
    with open(rom_path, "wb") as f:
        f.write(bytes(mem))
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes), wrote {rom_path}")
    print("INIT =", hex(sym["INIT"]), "MAINLOOP =", hex(sym["MAINLOOP"]))
    return out, sym, text


if __name__ == "__main__":
    main()
