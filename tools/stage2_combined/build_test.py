"""Assembles the combined terrain + tank test: the stage2_terrain
scroller (own INIT/MAINLOOP engine) with the tank sprite sitting on
top of it, into one standalone 32KB ROM. Border-color diagnostic
checkpoints added through INIT (see the README) since the tank-only
test reportedly froze on real hardware with no clue where.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_tank"))

import terrain_gen  # noqa: E402
import tank_gen  # noqa: E402
import bullet_gen  # noqa: E402
import enemy_gen  # noqa: E402
import bigzum_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402


def assemble():
    body = open(os.path.join(HERE, "combined_test.asm")).read()
    tables = (terrain_gen.emit_asm_tables() + "\n" + tank_gen.emit_asm_tables()
              + "\n" + bullet_gen.emit_asm_tables() + "\n" + enemy_gen.emit_asm_tables()
              + "\n" + bigzum_gen.emit_asm_tables())
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
    rom_path = os.path.join(HERE, "combined_test.rom")
    with open(rom_path, "wb") as f:
        f.write(bytes(mem))
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes), wrote {rom_path}")
    print("INIT =", hex(sym["INIT"]), "MAINLOOP =", hex(sym["MAINLOOP"]))
    return out, sym, text


if __name__ == "__main__":
    main()
