"""tools/ebuz_mk2_test/ebuz_mk2_test.asm のVRAM->PNGレンダリング
スクリプト(2026-09-20全面訂正版: 5門砲台+連続oscillation+state1は
中央のみ発射)。tools/stage1_render_check.pyのrender_full()を使い回す
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

    run_until_pc(z, sym["EBUZ2_STATE1_BG_DONE"])
    p1 = os.path.join(HERE, "ebuz_mk2_state1.ppm")
    render_full(bytes(z.vram), p1)
    print("state1 rendered:", p1)

    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])
    p2 = os.path.join(HERE, "ebuz_mk2_center_shot_fired.ppm")
    render_full(bytes(z.vram), p2)
    print("state1 release: center tube fires 1 shot:", p2)

    # state1->state2 has no wait (instant relocation to Row9), so jump
    # straight there.
    run_until_pc(z, sym["EBUZ2_STATE2_BG_DONE"])
    p3 = os.path.join(HERE, "ebuz_mk2_state2_row9.ppm")
    render_full(bytes(z.vram), p3)
    print("state2 body relocated to Row9:", p3)

    run_until_pc(z, sym["EBUZ2_STATE2_DONE"])
    p4 = os.path.join(HERE, "ebuz_mk2_state2_active.ppm")
    render_full(bytes(z.vram), p4)
    print("state2, sequential fire (center->inner->outer) + oscillation activated:", p4)

    # advance through a good chunk of the continuous oscillation sweep,
    # capturing a few snapshots along the way (mainloop runs via
    # EBUZ2_FRAME_TICK, not EBUZ2_WAIT_TICK_DONE, once past STATE2_DONE).
    for i, ticks in enumerate([40, 80, 160]):
        for _ in range(ticks):
            z.step()
            run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
        p = os.path.join(HERE, f"ebuz_mk2_sweep_{i}.ppm")
        render_full(bytes(z.vram), p)
        print(f"oscillation sweep snapshot {i} (OSC_ROW={z.mem[sym['EBUZ2_OSC_ROW']]}):", p)


if __name__ == "__main__":
    main()
