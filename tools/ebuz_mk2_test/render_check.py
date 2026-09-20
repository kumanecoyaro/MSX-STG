"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20、無印Ebuzと全く
同じ弾シーケンスに統一した版)のVRAM->PNGレンダリングスクリプト。
tools/stage1_render_check.pyのrender_full()を使い回す
(tools/ebuz_test/render_check.pyと同じ作法)。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80
from stage1_render_check import render_full  # reuse identical rendering logic


def assemble():
    with open(os.path.join(HERE, "ebuz_mk2_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def run_until_pc(z, target_pc, max_instr=8_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def main():
    mem0, sym = assemble()
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]

    run_until_pc(z, sym["EBUZ2_GUARD_DONE"])
    p0 = os.path.join(HERE, "ebuz_mk2_guard.ppm")
    render_full(bytes(z.vram), p0)
    print("guard bands only (row0=black, row20-23=white):", p0)

    run_until_pc(z, sym["EBUZ2_ENTRY_SPAWN_DONE"])
    p1 = os.path.join(HERE, "ebuz_mk2_spawn.ppm")
    render_full(bytes(z.vram), p1)
    print("spawned at row1 (full 7-row shape, no growth):", p1)

    run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_DONE"])
    p2 = os.path.join(HERE, "ebuz_mk2_centered.ppm")
    render_full(bytes(z.vram), p2)
    print("centered (row_top=9):", p2)

    run_until_pc(z, sym["EBUZ2_VOLLEY_DONE"])
    p3 = os.path.join(HERE, "ebuz_mk2_volley.ppm")
    render_full(bytes(z.vram), p3)
    print("volley fired (5 bullets, one per port, simultaneous, fixed rows):", p3)

    for i, ticks in enumerate([10, 20]):
        for _ in range(ticks):
            z.step()
            run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
        p = os.path.join(HERE, f"ebuz_mk2_flight_{i}.ppm")
        render_full(bytes(z.vram), p)
        print(f"bullets in flight, snapshot {i}:", p)

    for _ in range(60):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    p4 = os.path.join(HERE, "ebuz_mk2_idle.ppm")
    render_full(bytes(z.vram), p4)
    print("well after volley: all bullets clipped off-screen, body untouched:", p4)


if __name__ == "__main__":
    main()
