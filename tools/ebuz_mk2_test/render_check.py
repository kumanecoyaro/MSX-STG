"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20、Ebuz Mk2-1[閉状態]
が「揃うまで下にシフトする」方式で登場(2倍速)→中央で5門1斉発射→
リコイル(1セル右へ→戻る)→Mk2-2[開状態、7行]へ変形→中央発射→内側2門→
外側2門の順に間隔を空けて発射、以後は内側2門と外側2門が交互発射しつつ
本体が上下に往復、1往復完了で上下動・交互連射とも停止し、15Tick後に
中央から1発発射して静止する、という版)のVRAM->PNGレンダリングスクリプト。
tools/stage1_render_check.pyのrender_full()を使い回す。
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
        print(f"growth step {i} ({i+1}/5 rows visible, belt-shifted down each step):", p)

    run_until_pc(z, sym["EBUZ2_ENTRY_GROWTH_DONE"])
    p1 = os.path.join(HERE, "ebuz_mk2_growth_done.ppm")
    render_full(bytes(z.vram), p1)
    print("growth complete, all 5 rows assembled (top row at row1):", p1)

    run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_DONE"])
    p2 = os.path.join(HERE, "ebuz_mk2_centered.ppm")
    render_full(bytes(z.vram), p2)
    print("centered (row_top=9), still Mk2-1, no deformation:", p2)

    run_until_pc(z, sym["EBUZ2_VOLLEY_DONE"])
    p3 = os.path.join(HERE, "ebuz_mk2_volley.ppm")
    render_full(bytes(z.vram), p3)
    print("1st volley: all 5 closed-body rows fire simultaneously:", p3)

    run_until_pc(z, sym["EBUZ2_RECOIL_DONE"])
    p3b = os.path.join(HERE, "ebuz_mk2_recoil_done.ppm")
    render_full(bytes(z.vram), p3b)
    print("recoil done: body moved 1 cell right then back to center:", p3b)

    run_until_pc(z, sym["EBUZ2_TRANSFORM_DONE"])
    p3c = os.path.join(HERE, "ebuz_mk2_transform_done.ppm")
    render_full(bytes(z.vram), p3c)
    print("transformed to Mk2-2 (open state, 7 rows):", p3c)

    run_until_pc(z, sym["EBUZ2_VOLLEY2_WAVE_C_DONE"])
    p3d1 = os.path.join(HERE, "ebuz_mk2_volley2_center.ppm")
    render_full(bytes(z.vram), p3d1)
    print("2nd volley wave 1/3: center fires alone:", p3d1)

    run_until_pc(z, sym["EBUZ2_VOLLEY2_WAVE_INNER_DONE"])
    p3d2 = os.path.join(HERE, "ebuz_mk2_volley2_inner.ppm")
    render_full(bytes(z.vram), p3d2)
    print("2nd volley wave 2/3: inner 2 ports fire together:", p3d2)

    run_until_pc(z, sym["EBUZ2_VOLLEY2_DONE"])
    p3d = os.path.join(HERE, "ebuz_mk2_volley2.ppm")
    render_full(bytes(z.vram), p3d)
    print("2nd volley wave 3/3: outer 2 ports fire together:", p3d)

    # 「内2門と外2門の交互発射」: 本体固定のまま内側/外側ペアが交代
    # 発射しつつ本体は上下に往復する(1往復するまで)。その2巡目
    # (2回目の内側・外側発射)を確認する。
    run_until_pc(z, sym["EBUZ2_VOLLEY2_ALT_INNER_DONE"])
    p3e1 = os.path.join(HERE, "ebuz_mk2_volley2_alt_inner2.ppm")
    render_full(bytes(z.vram), p3e1)
    print("alternating fire (until 1 round-trip), 2nd cycle inner pair:", p3e1)

    run_until_pc(z, sym["EBUZ2_VOLLEY2_ALT_OUTER_DONE"])
    p3e2 = os.path.join(HERE, "ebuz_mk2_volley2_alt_outer2.ppm")
    render_full(bytes(z.vram), p3e2)
    print("alternating fire (until 1 round-trip), 2nd cycle outer pair:", p3e2)

    for _ in range(60):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    p4 = os.path.join(HERE, "ebuz_mk2_idle.ppm")
    render_full(bytes(z.vram), p4)
    print("still oscillating/firing, body drifting up/down, old bullets unaffected:", p4)

    # (2026-09-20「では一往復したら上下動停止して 交互連射も停止
    # 15Tick停止したら 中央から1発発射」対応)
    run_until_pc(z, sym["EBUZ2_S2_STOP_SEQUENCE"])
    p5 = os.path.join(HERE, "ebuz_mk2_roundtrip_stop.ppm")
    render_full(bytes(z.vram), p5)
    print("1 round-trip complete: up-down movement AND alternating fire both stop:", p5)

    run_until_pc(z, sym["EBUZ2_S2_FINAL_DONE"])
    p6 = os.path.join(HERE, "ebuz_mk2_final_shot.ppm")
    render_full(bytes(z.vram), p6)
    print("after 15-tick pause: single shot fired from center, then holds forever:", p6)


if __name__ == "__main__":
    main()
