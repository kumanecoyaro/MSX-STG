"""EbuzMk2のstate2側(本体タイル遷移・継続交互発射・上下往復
[oscillation])の検証。tools/ebuz_mk2_test/verify_volley_straight.pyが
state1の開幕ボレー(斜め移動ゼロ)を検証するのに対し、こちらはその先の
流れ - state1→state2のBGタイル差し替え、砲台キャップ行(固定)からの
継続交互発射、base/up/down4段サイクルのoscillationでの本体タイルの
erase/draw正しさ - を対象とする。tools/ebuz_test/ebuz_test_verify.pyと
同じ「mini_z80asm.Assemblerで直接アセンブル+run_until_pcの一回性検証
スクリプト」の作法に倣う。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80

PASS = 0
FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f"FAIL: {msg}")


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


def run_until_pc(z, target_pc, max_instr=6_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


NAMTBL = 0x1800


def cells(z, row, col, n):
    return [z.vram[NAMTBL + row * 32 + col + i] for i in range(n)]


def main():
    mem0, sym = assemble()
    A, B, C, D = sym["EBUZ2_CODE_A"], sym["EBUZ2_CODE_B"], sym["EBUZ2_CODE_C"], sym["EBUZ2_CODE_D"]
    BL, BR = sym["BULLET_L_CODE"], sym["BULLET_R_CODE"]

    # ---------- 1. state1 body shape (5 rows, row3-7, col23-27) ----------
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]
    run_until_pc(z, sym["EBUZ2_STATE1_BG_DONE"])
    check(cells(z, 3, 23, 5) == [0, 0, A, B, C], "state1 row3 (top) = .,.,A,B,C")
    check(cells(z, 4, 23, 5) == [0, A, B, C, D], "state1 row4 = .,A,B,C,D")
    check(cells(z, 5, 23, 5) == [A, B, C, D, D], "state1 row5 (center, widest) = A,B,C,D,D")
    check(cells(z, 6, 23, 5) == [0, A, B, C, D], "state1 row6 = row4 mirrored")
    check(cells(z, 7, 23, 5) == [0, 0, A, B, C], "state1 row7 = row3 mirrored")

    # ---------- 2. state1->state2 BG transform (base position, rows2-8) ----------
    z2 = Z80(bytearray(mem0))
    z2.pc = sym["INIT"]
    run_until_pc(z2, sym["EBUZ2_STATE2_BG_DONE"])
    check(cells(z2, 2, 23, 5) == [0, 0, A, B, C], "state2 base row2 = .,.,A,B,C")
    check(cells(z2, 3, 23, 5) == [0, A, B, C, C], "state2 base row3 = .,A,B,C,C (C repeated, not D)")
    check(cells(z2, 4, 23, 5) == [0, 0, 0, 0, D], "state2 base row4 = top turret cap (D only, fire lane)")
    check(cells(z2, 5, 23, 5) == [A, B, C, D, D], "state2 base row5 (center) = A,B,C,D,D, same bytes as state1 row5")
    check(cells(z2, 6, 23, 5) == [0, 0, 0, 0, D], "state2 base row6 = bottom turret cap (D only, fire lane)")
    check(cells(z2, 7, 23, 5) == [0, A, B, C, C], "state2 base row7 = row3 mirrored")
    check(cells(z2, 8, 23, 5) == [0, 0, A, B, C], "state2 base row8 = row2 mirrored")
    # the structural center row (state1 row5 / state2 row5) must be byte-identical
    # across the transition, since it never moves (file header's anchoring claim).
    check(cells(z2, 5, 23, 5) == cells(z, 5, 23, 5),
          "the wide center row (nt row5) is pixel-identical between state1 and state2 - it never redraws")

    # ---------- 3. continuous top/bottom fire: alternates every EBUZ2_FIRE_INTERVAL ticks, ----------
    #     unconditionally (no survival check), from the fixed cap rows (4/6).
    z3 = Z80(bytearray(mem0))
    z3.pc = sym["INIT"]
    run_until_pc(z3, sym["EBUZ2_STATE2_DONE"])
    BULLET_COL = sym["EBUZ2_BULLET_COL"]
    fired_rows = []
    for i in range(8):
        z3.step()
        run_until_pc(z3, sym["EBUZ2_FRAME_TICK"])
        top = cells(z3, 4, BULLET_COL, 2)
        bot = cells(z3, 6, BULLET_COL, 2)
        if top == [BL, BR]:
            fired_rows.append("top")
        if bot == [BL, BR]:
            fired_rows.append("bottom")
    check(fired_rows == ["top", "bottom", "top", "bottom"],
          f"continuous fire alternates top/bottom every {sym['EBUZ2_FIRE_INTERVAL']} ticks starting with top, "
          f"got sequence: {fired_rows}")

    # ---------- 4. oscillation: base -> up -> base -> down -> base, 4-phase cycle ----------
    z4 = Z80(bytearray(mem0))
    z4.pc = sym["INIT"]
    run_until_pc(z4, sym["EBUZ2_STATE2_DONE"])

    run_until_pc(z4, sym["EBUZ2_OSC_SHIFT_DONE"])  # base -> up
    check(cells(z4, 1, 23, 5) == [0, 0, A, B, C], "osc UP: row1 now shows the body's row0 content")
    check(cells(z4, 4, 23, 5) == [A, B, C, D, D],
          "osc UP: nt row4 (the FIXED fire lane) now shows body's center-row art, "
          "not a turret cap - this is the documented simplification (fire lanes don't follow the body)")
    check(cells(z4, 8, 23, 5) == [0, 0, 0, 0, 0], "osc UP: nt row8 (base's bottom row) is erased/blank now")

    run_until_pc(z4, sym["EBUZ2_OSC_SHIFT_DONE"])  # up -> base
    check(cells(z4, 2, 23, 5) == [0, 0, A, B, C], "osc back to BASE: row2 restored")
    check(cells(z4, 4, 23, 5) == [0, 0, 0, 0, D], "osc back to BASE: row4 turret cap restored")
    check(cells(z4, 1, 23, 5) == [0, 0, 0, 0, 0], "osc back to BASE: row1 (UP's top row) erased")

    run_until_pc(z4, sym["EBUZ2_OSC_SHIFT_DONE"])  # base -> down
    check(cells(z4, 9, 23, 5) == [0, 0, A, B, C], "osc DOWN: row9 now shows the body's bottom row")
    check(cells(z4, 6, 23, 5) == [A, B, C, D, D], "osc DOWN: nt row6 (FIXED fire lane) shows center-row art now")

    run_until_pc(z4, sym["EBUZ2_OSC_SHIFT_DONE"])  # down -> base
    check(cells(z4, 2, 23, 5) == [0, 0, A, B, C], "osc back to BASE (2nd time): row2 restored again")
    check(cells(z4, 9, 23, 5) == [0, 0, 0, 0, 0], "osc back to BASE (2nd time): row9 (DOWN's bottom row) erased")
    check(z4.mem[sym["EBUZ2_OSC_PHASE"]] == 0, "after one full base->up->base->down->base cycle, phase wraps back to 0")

    # ---------- 5. fire lanes stay fixed at nt row4/row6 even while the body is UP/DOWN ----------
    #     (direct check of the documented simplification: continuous fire never
    #     stops or relocates just because the body moved).
    z5 = Z80(bytearray(mem0))
    z5.pc = sym["INIT"]
    run_until_pc(z5, sym["EBUZ2_STATE2_DONE"])
    run_until_pc(z5, sym["EBUZ2_OSC_SHIFT_DONE"])  # now at UP position
    saw_top_fire_while_up = False
    for i in range(4):
        z5.step()
        run_until_pc(z5, sym["EBUZ2_FRAME_TICK"])
        if cells(z5, 4, BULLET_COL, 2) == [BL, BR]:
            saw_top_fire_while_up = True
    check(saw_top_fire_while_up,
          "continuous fire keeps firing from nt row4 even while the body is visually at the UP position")

    print(f"\n{PASS} passed, {FAIL} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
