"""tools/ebuz_test/ebuz_test.asm(新エネミー"Ebuz"のプロトタイプ)の
検証(2026-09-13)。専用の空SCREEN1環境でstate1出現→state2変化という
2状態だけを確認する、本編未組み込みの独立テスト。

tools/verify_*.py群と同じ「mini_z80asm.Assemblerで直接アセンブル+
run_until_pcの一回性検証スクリプト」の作法に倣う。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80

with open(os.path.join(HERE, "ebuz_test.asm"), encoding="utf-8") as f:
    text = f.read()
asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


A, B, C, D = sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"], sym["EBUZ_CODE_D"]
NAMTBL = 0x1800


def cells(z, row, col, n):
    return [z.vram[NAMTBL + row * 32 + col + i] for i in range(n)]


# ---------- state1: 2 tile rows, both identical (A,B,C,D), at row2/col24 ----------
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["EBUZ_STATE1_DONE"])
check("state1 row2 (top) is A,B,C,D at col24-27", cells(z, 2, 24, 4) == [A, B, C, D])
check("state1 row3 (bottom) is also A,B,C,D (identical to row2)", cells(z, 3, 24, 4) == [A, B, C, D])
check("state1: row1 (above) is untouched (still blank/code0)", cells(z, 1, 24, 4) == [0, 0, 0, 0])
check("state1: row4 (below) is untouched (still blank/code0)", cells(z, 4, 24, 4) == [0, 0, 0, 0])
check("EBUZ's 4 pattern codes actually loaded into VRAM pattern generator "
      "(non-blank bitmaps)",
      all(any(z.vram[code * 8 + i] for i in range(8)) for code in (A, B, C, D)))

# ---------- state2 (corrected, from Ebuz3): A,B,C band splits away from the ----------
# original 2 rows to new top/bottom bands, leaving only D behind in the middle.
z2 = fresh()
z2.pc = sym["INIT"]
run_until_pc(z2, sym["EBUZ_STATE2_DONE"])
check("state2 row1 (new top band) is blank,A,B,C at col24-27", cells(z2, 1, 24, 4) == [0, A, B, C])
check("state2 row4 (new bottom band) is blank,A,B,C at col24-27", cells(z2, 4, 24, 4) == [0, A, B, C])
check("state2 row2 (was A,B,C,D): A,B,C have moved away, only D remains", cells(z2, 2, 24, 4) == [0, 0, 0, D])
check("state2 row3 (was A,B,C,D): A,B,C have moved away, only D remains", cells(z2, 3, 24, 4) == [0, 0, 0, D])

# ---------- the 4 tiles genuinely reconstruct Ebuz3.json byte-for-byte (see ebuz_gen.py) ----------
import ebuz_gen
a, b, c, d = ebuz_gen.extract_tiles()
ok_recon, mismatch = ebuz_gen.verify_against_ebuz3(a, b, c, d)
check("the 4 extracted tiles (A,B,C,D) reconstruct the uploaded Ebuz3.json exactly "
      "(confirms Ebuz3 - the corrected state2 art - is just a rearrangement of "
      "Ebuz1's own tiles, no new art)",
      ok_recon)


# ---------- bullets ("Okこれでいい ではEbuz1で登場した時に添付ファイルの弾を ----------
# 左へ発射 スプライトで で、Ebuz2に変化したら添付ファイルの16x8部分だけの
# スプライトを上下から発射 1つはY位置0px 2つ目は24pxの位置")
SPRATR = 0x1B00
BULLET_FULL_CODE = sym["BULLET_FULL_CODE"]
BULLET_HALF_CODE = sym["BULLET_HALF_CODE"]
BULLET_COLOR = sym["EBUZ_BULLET_COLOR"]
BULLET_X = sym["EBUZ_BULLET_X"]
BULLET_SPEED = sym["EBUZ_BULLET_SPEED"]
SPR_HIDE_Y = sym["SPR_HIDE_Y"]
SPR_TERM_Y = sym["SPR_TERM_Y"]
Y1_STORED = sym["EBUZ_BULLET1_STORED_Y"]
Y2_STORED = sym["EBUZ_BULLET2_STORED_Y"]
Y3_STORED = sym["EBUZ_BULLET3_STORED_Y"]


def sprite_attr(z, slot):
    base = SPRATR + slot * 4
    return [z.vram[base + i] for i in range(4)]


# --- state1 fires exactly 1 bullet (BULLET_FULL, slot0); slots1/2 stay hidden ---
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["EBUZ_STATE1_DONE"])
check("state1: bullet0(slot0) fired as BULLET_FULL at the documented placeholder "
      "position (Y=16,X=192) with the attached art's own color(11)",
      sprite_attr(z, 0) == [Y1_STORED, BULLET_X, BULLET_FULL_CODE, BULLET_COLOR])
check("state1: bullet1(slot1) not fired yet (still hidden)", sprite_attr(z, 1)[0] == SPR_HIDE_Y)
check("state1: bullet2(slot2) not fired yet (still hidden)", sprite_attr(z, 2)[0] == SPR_HIDE_Y)
check("SAT terminator (slot3) written once at boot", sprite_attr(z, 3)[0] == SPR_TERM_Y)
check("BULLET_FULL's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z.vram[0x3800 + BULLET_FULL_CODE * 8 + i] for i in range(32)))
check("BULLET_HALF's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z.vram[0x3800 + BULLET_HALF_CODE * 8 + i] for i in range(32)))
# NOTE: ebuz_test.asm sets 16x16 sprite mode via the WRTVDP BIOS call
# (0047h), which tools/z80emu.py implements as a pure no-op stub (register
# state not tracked) - so z.vdp_regs never gains an entry for R1 this way.
# Verify indirectly instead: RG1SAV (the BIOS RAM mirror WRTVDP is
# documented to update) must show bit1 set, since ebuz_test.asm ORs it in
# before the WRTVDP call.
check("16x16 sprite size mode enabled (RG1SAV mirror bit1/SI set)",
      z.mem[sym["RG1SAV"]] & 0x02 != 0)

# --- state2 additionally fires 2 more bullets (BULLET_HALF, slots1/2), at the ---
# user's own literal Y=0px/24px - Y=0 was nudged to Y=1 to dodge this codebase's
# own "stored Y>=209 means hidden" convention colliding with the real hardware
# wraparound encoding for Y=0 (stored 255) - see ebuz_test.asm's own comment.
z2 = fresh()
z2.pc = sym["INIT"]
run_until_pc(z2, sym["EBUZ_STATE2_DONE"])
check("state2: bullet0(slot0) from state1 is untouched", sprite_attr(z2, 0) == [Y1_STORED, BULLET_X, BULLET_FULL_CODE, BULLET_COLOR])
check("state2: bullet1(slot1) fired as BULLET_HALF at Y=1px (nudged from the "
      "requested 0px to dodge the hide-sentinel collision, see comment)",
      sprite_attr(z2, 1) == [Y2_STORED, BULLET_X, BULLET_HALF_CODE, BULLET_COLOR])
check("state2: bullet2(slot2) fired as BULLET_HALF at Y=24px exactly as requested",
      sprite_attr(z2, 2) == [Y3_STORED, BULLET_X, BULLET_HALF_CODE, BULLET_COLOR])

# --- all 3 bullets keep moving left every EBUZ_FRAME_TICK lap ---
for _ in range(5):
    z2.step()
    run_until_pc(z2, sym["EBUZ_FRAME_TICK"])
expected_x = BULLET_X - 5 * BULLET_SPEED
check(f"after 5 frame-ticks, all 3 bullets moved left by exactly 5*{BULLET_SPEED}px "
      f"(X: {BULLET_X}->{expected_x})",
      sprite_attr(z2, 0)[1] == expected_x and sprite_attr(z2, 1)[1] == expected_x
      and sprite_attr(z2, 2)[1] == expected_x)

# --- a bullet that reaches the left edge (X < speed) gets hidden, not wrapped ---
z3 = fresh()
z3.pc = sym["INIT"]
run_until_pc(z3, sym["EBUZ_STATE2_DONE"])
# BULLET_X(192) / BULLET_SPEED(3) = 64 laps to reach X=0, one more to go negative
laps = BULLET_X // BULLET_SPEED + 2
for _ in range(laps):
    z3.step()
    run_until_pc(z3, sym["EBUZ_FRAME_TICK"])
check("a bullet that would go off the left edge is hidden (Y=SPR_HIDE_Y), not "
      "wrapped to a huge positive X", sprite_attr(z3, 0)[0] == SPR_HIDE_Y)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
