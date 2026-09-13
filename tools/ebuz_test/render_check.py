"""tools/ebuz_test/ebuz_test.asm のVRAM->PNGレンダリングスクリプト。
tools/stage1_render_check.pyのrender_full()と同一ロジックを使い回し、
state1(登場直後)とstate2(変化後)の2枚を保存する。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "stage2_terrain"))

from mini_z80asm import Assembler
from z80emu import Z80
from stage1_render_check import render_full  # reuse identical rendering logic


def assemble():
    with open(os.path.join(HERE, "ebuz_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def main():
    mem0, sym = assemble()
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]

    run_until_pc(z, sym["EBUZ_STATE1_DONE"])
    p1 = os.path.join(HERE, "ebuz_state1.ppm")
    render_full(bytes(z.vram), p1)
    print("state1 rendered:", p1)
    row2 = [z.vram[0x1800 + 2 * 32 + 24 + i] for i in range(4)]
    row3 = [z.vram[0x1800 + 3 * 32 + 24 + i] for i in range(4)]
    print("  row2 cols24-27:", row2, "row3 cols24-27:", row3)

    run_until_pc(z, sym["EBUZ_STATE2_DONE"])
    p2 = os.path.join(HERE, "ebuz_state2.ppm")
    render_full(bytes(z.vram), p2)
    print("state2 rendered:", p2)
    row1 = [z.vram[0x1800 + 1 * 32 + 24 + i] for i in range(4)]
    row4 = [z.vram[0x1800 + 4 * 32 + 24 + i] for i in range(4)]
    row2 = [z.vram[0x1800 + 2 * 32 + 24 + i] for i in range(4)]
    row3 = [z.vram[0x1800 + 3 * 32 + 24 + i] for i in range(4)]
    print("  row1 cols24-27:", row1, "row2:", row2, "row3:", row3, "row4:", row4)


if __name__ == "__main__":
    main()
