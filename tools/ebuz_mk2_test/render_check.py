"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20、Ebuz Mk2-1[閉状態]
がrow1で静止したまま下段→中央→上段の順に1行ずつ組み上がり、揃って
から中央へ移動→5門同時1斉発射する版)のVRAM->PNGレンダリング
スクリプト。tools/stage1_render_check.pyのrender_full()を使い回す。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80
from stage1_render_check import render_full


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
    print("guard bands only:", p0)

    hold = sym["EBUZ2_ENTRY_STEP_HOLD_TICKS"]
    for i in range(5):
        for _ in range(hold):
            run_until_pc(z, sym["EBUZ2_TICK"])
            z.step()
        p = os.path.join(HERE, f"ebuz_mk2_growth_{i}.ppm")
        render_full(bytes(z.vram), p)
        print(f"growth step {i} (row stays at row1, {i+1}/5 rows visible):", p)

    run_until_pc(z, sym["EBUZ2_ENTRY_GROWTH_DONE"])
    p1 = os.path.join(HERE, "ebuz_mk2_growth_done.ppm")
    render_full(bytes(z.vram), p1)
    print("growth complete, all 5 rows assembled at row1:", p1)

    run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_DONE"])
    p2 = os.path.join(HERE, "ebuz_mk2_centered.ppm")
    render_full(bytes(z.vram), p2)
    print("centered (row_top=9), still Mk2-1, no deformation:", p2)

    run_until_pc(z, sym["EBUZ2_VOLLEY_DONE"])
    p3 = os.path.join(HERE, "ebuz_mk2_volley.ppm")
    render_full(bytes(z.vram), p3)
    print("all 5 rows fire simultaneously:", p3)

    for _ in range(60):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    p4 = os.path.join(HERE, "ebuz_mk2_idle.ppm")
    render_full(bytes(z.vram), p4)
    print("well after volley: bullets clipped off-screen, body untouched:", p4)


if __name__ == "__main__":
    main()
