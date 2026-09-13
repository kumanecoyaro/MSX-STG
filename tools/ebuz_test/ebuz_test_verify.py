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


def run_until_pc_count(z, target_pc, max_instr=2_000_000):
    """run_until_pcと同じだが、実際に消費したステップ数を返す
    (「ラベル順序が正しいだけで実際は遅延処理が呼ばれていない」種類の
    回帰を検出するため - ラベル位置だけを見るテストではこれを検出
    できない)。"""
    steps = 0
    for _ in range(max_instr):
        if z.pc == target_pc:
            return steps
        z.step()
        steps += 1
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
# スプライトを上下から発射 1つはY位置0px 2つ目は24pxの位置")、続けて
# (2026-09-13追記その2)"まずEbuz1の時の弾の位置を左へ16px移動 この状態で
# 0.5秒維持してから発射 次に...Yが0px、24pxの位置から同時発射...弾の速度
# が早いんで半分に"、さらに"同時発射はEbuz2に変形後な 同じく0.5秒維持して
# 同時発射"。
SPRATR = 0x1B00
BULLET_FULL_CODE = sym["BULLET_FULL_CODE"]
BULLET_HALF_CODE = sym["BULLET_HALF_CODE"]
BULLET_COLOR = sym["EBUZ_BULLET_COLOR"]
BULLET1_X = sym["EBUZ_BULLET1_X"]   # state1弾: 192-16=176
BULLET23_X = sym["EBUZ_BULLET_X"]   # state2弾2枚: 192のまま
SPEED_LO = sym["EBUZ_BULLET_SPEED_LO"]
SPEED_HI = sym["EBUZ_BULLET_SPEED_HI"]
OLD_SPEED = 3   # pre-halving speed ("弾の速度が早いんで半分に"以前の3px/frame)
check(f"EBUZ_BULLET_SPEED_LO({SPEED_LO})+HI({SPEED_HI}) sums to exactly the old "
      f"pre-halving speed({OLD_SPEED}), so the 2-frame average (1.5px/frame) is "
      f"exactly half of it - pins the actual numeric values, not just their "
      f"self-consistency with the simulation below",
      SPEED_LO == 1 and SPEED_HI == 2 and SPEED_LO + SPEED_HI == OLD_SPEED)
SPR_HIDE_Y = sym["SPR_HIDE_Y"]
SPR_TERM_Y = sym["SPR_TERM_Y"]
Y1_STORED = sym["EBUZ_BULLET1_STORED_Y"]
Y2_STORED = sym["EBUZ_BULLET2_STORED_Y"]
Y3_STORED = sym["EBUZ_BULLET3_STORED_Y"]
SENTINEL = 0x0000  # never real code - safe return trap (see tools/verify_sound_duty_cycle.py)


def sprite_attr(z, slot):
    base = SPRATR + slot * 4
    return [z.vram[base + i] for i in range(4)]


def simulate_positions(x_list, n_iters):
    """Python参照実装: EBUZ_MAINLOOPの歩幅トグル(1px/2px交互、平均
    1.5px/frame=元の3px/frameのちょうど半分)をシミュレートする。
    引数x_listの各要素を同じフレームスケジュールで同時に進める
    (実装が3発とも同一ループ・同一グローバルparityで動かすのに対応)。
    戻り値は各弾の(最終X, 非表示になったか)のリスト。"""
    xs = list(x_list)
    hidden = [False] * len(xs)
    parity = 0
    for _ in range(n_iters):
        step = SPEED_LO if parity == 0 else SPEED_HI
        for i in range(len(xs)):
            if hidden[i]:
                continue
            if xs[i] < step:
                hidden[i] = True
            else:
                xs[i] -= step
        parity ^= 1
    return list(zip(xs, hidden))


def call_routine(z, addr, max_instr=2_000_000):
    """1回のCALL相当を実行し、SENTINELへ戻るまでのステップ数を返す
    (tools/verify_sound_duty_cycle.pyのcall_routine()と同じ作法)。"""
    z.sp = (z.sp - 2) & 0xFFFF
    z.wr(z.sp, SENTINEL & 0xFF)
    z.wr((z.sp + 1) & 0xFFFF, (SENTINEL >> 8) & 0xFF)
    z.pc = addr
    steps = 0
    while z.pc != SENTINEL and steps < max_instr:
        z.step()
        steps += 1
    if steps >= max_instr:
        raise RuntimeError(f"call to {addr:04x} never returned")
    return steps


# --- EBUZ_DELAY_HALF's dominant (inner-loop) work is exactly half of ---
# EBUZ_DELAY's, verified against an exact analytic step-count formula
# derived from the routines' own structure (LD D,3 outer x [LD B,n mid
# x [LD C,0 x (DEC C+JR NZ) x256 + DJNZ] + DEC D+JR NZ] + RET). Note the
# measured *ratio* is NOT bit-exact 2.0 (it's ~1.99994) because the fixed
# per-outer-iteration overhead (LD B,n / DEC D / JR NZ, 3 instructions)
# doesn't scale with the halved B-count - only the C_count=256 inner loop
# (the actual "busy work" that dominates wall-clock time) is exactly
# halved. This is expected, not a bug.
def expected_delay_steps(d, b_count, c_count=256):
    per_mid = 1 + c_count * 2 + 1          # LD C,0 + (DEC C+JR NZ)*c_count + DJNZ
    per_outer = 1 + b_count * per_mid + 2  # LD B,n + mids + DEC D+JR NZ
    return 2 + d * per_outer               # LD D,3 + outers + RET


zd = fresh()
zd.sp = 0xFE00
full_steps = call_routine(zd, sym["EBUZ_DELAY"])
zd2 = fresh()
zd2.sp = 0xFE00
half_steps = call_routine(zd2, sym["EBUZ_DELAY_HALF"])
exp_full = expected_delay_steps(d=3, b_count=256)
exp_half = expected_delay_steps(d=3, b_count=128)
check(f"EBUZ_DELAY/EBUZ_DELAY_HALF step counts exactly match the analytic "
      f"formula (full={full_steps}=={exp_full}, half={half_steps}=={exp_half}), "
      f"and the dominant inner-loop work (B_count*256*2) is exactly halved "
      f"(256*256*2={256*256*2} vs 128*256*2={128*256*2})",
      full_steps == exp_full and half_steps == exp_half)

# --- state1 BG drawn, but bullet0 not fired yet (still waiting out the 0.5s) ---
z0 = fresh()
z0.pc = sym["INIT"]
run_until_pc(z0, sym["EBUZ_STATE1_BG_DONE"])
check("state1: right after BG is drawn (before the 0.5s wait), bullet0 has NOT "
      "fired yet (still hidden) - proves the BG-then-wait-then-fire ordering",
      sprite_attr(z0, 0)[0] == SPR_HIDE_Y)

# --- an actual EBUZ_DELAY_HALF-sized wait really elapses between "BG done" and ---
# "fired" (guards against a regression where the labels are in the right order
# but the CALL EBUZ_DELAY_HALF itself is missing/short-circuited - a check that
# only compares PC label order can't catch that, since label position doesn't
# move even if the delay call in between is deleted).
half_steps_ref = call_routine(fresh(), sym["EBUZ_DELAY_HALF"])
gap1 = run_until_pc_count(z0, sym["EBUZ_STATE1_DONE"])
check(f"state1: the BG-done -> fired gap actually spends roughly one "
      f"EBUZ_DELAY_HALF's worth of steps ({gap1} >= {half_steps_ref}*0.9), not "
      f"just a few instructions",
      gap1 >= half_steps_ref * 0.9)

# --- state1 fires exactly 1 bullet (BULLET_FULL, slot0) after the 0.5s wait; ---
# slots1/2 stay hidden. Firing X is now 16px left of the old placeholder.
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["EBUZ_STATE1_DONE"])
check("EBUZ_BULLET1_X is exactly 16px left of EBUZ_BULLET_X (the shared base/"
      "state2 X), not just equal to it - pins the actual numeric relationship "
      "the user asked for rather than trusting the symbol names alone",
      BULLET1_X == BULLET23_X - 16)
check("state1: bullet0(slot0) fired as BULLET_FULL at Y=16,X=176 (16px left of "
      "the old X=192 placeholder, per \"Ebuz1の時の弾の位置を左へ16px移動\") "
      "with the attached art's own color(11)",
      sprite_attr(z, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
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

# --- state2 BG transformed, but bullets1/2 not fired yet (waiting out the 0.5s) ---
z1b = fresh()
z1b.pc = sym["INIT"]
run_until_pc(z1b, sym["EBUZ_STATE2_BG_DONE"])
check("state2: right after the BG transforms (before the 0.5s wait), bullet0 is "
      "unchanged", sprite_attr(z1b, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
check("state2: right after the BG transforms (before the 0.5s wait), bullets1/2 "
      "have NOT fired yet (still hidden) - proves the transform-then-wait-then-"
      "fire ordering (\"Ebuz2に変形後...0.5秒維持して同時発射\")",
      sprite_attr(z1b, 1)[0] == SPR_HIDE_Y and sprite_attr(z1b, 2)[0] == SPR_HIDE_Y)

gap2 = run_until_pc_count(z1b, sym["EBUZ_STATE2_DONE"])
check(f"state2: the transform-done -> fired gap actually spends roughly one "
      f"EBUZ_DELAY_HALF's worth of steps ({gap2} >= {half_steps_ref}*0.9), not "
      f"just a few instructions",
      gap2 >= half_steps_ref * 0.9)

# --- state2 additionally fires 2 more bullets (BULLET_HALF, slots1/2) after the ---
# 0.5s wait, simultaneously, at the user's own literal Y=0px/24px - Y=0 was
# nudged to Y=1 to dodge this codebase's own "stored Y>=209 means hidden"
# convention colliding with the real hardware wraparound encoding for Y=0
# (stored 255) - see ebuz_test.asm's own comment.
z2 = fresh()
z2.pc = sym["INIT"]
run_until_pc(z2, sym["EBUZ_STATE2_DONE"])
check("state2: bullet0(slot0) from state1 is untouched", sprite_attr(z2, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
check("state2: bullet1(slot1) fired as BULLET_HALF at Y=1px (nudged from the "
      "requested 0px to dodge the hide-sentinel collision, see comment), X=192",
      sprite_attr(z2, 1) == [Y2_STORED, BULLET23_X, BULLET_HALF_CODE, BULLET_COLOR])
check("state2: bullet2(slot2) fired as BULLET_HALF at Y=24px exactly as "
      "requested, X=192, simultaneously with bullet1",
      sprite_attr(z2, 2) == [Y3_STORED, BULLET23_X, BULLET_HALF_CODE, BULLET_COLOR])

# --- all 3 bullets keep moving left every EBUZ_FRAME_TICK lap, at the halved ---
# speed (1px/2px alternating, average 1.5px/frame = exactly half of the old 3px/frame)
N_TICKS = 5
for _ in range(N_TICKS):
    z2.step()
    run_until_pc(z2, sym["EBUZ_FRAME_TICK"])
(exp0_x, exp0_hidden), (exp1_x, exp1_hidden), (exp2_x, exp2_hidden) = simulate_positions(
    [BULLET1_X, BULLET23_X, BULLET23_X], N_TICKS)
check(f"after {N_TICKS} frame-ticks, all 3 bullets moved left by the halved "
      f"alternating 1px/2px speed schedule exactly as simulated "
      f"(bullet0: {BULLET1_X}->{exp0_x}, bullet1/2: {BULLET23_X}->{exp1_x})",
      not exp0_hidden and not exp1_hidden and not exp2_hidden
      and sprite_attr(z2, 0)[1] == exp0_x and sprite_attr(z2, 1)[1] == exp1_x
      and sprite_attr(z2, 2)[1] == exp2_x)

# --- a bullet that reaches the left edge gets hidden, not wrapped ---
z3 = fresh()
z3.pc = sym["INIT"]
run_until_pc(z3, sym["EBUZ_STATE2_DONE"])
# figure out (via the same python reference model) how many laps bullet0
# (starting at BULLET1_X=176, the closest to the edge) needs to hide.
laps = 0
while True:
    laps += 1
    (_, hidden0), = simulate_positions([BULLET1_X], laps)
    if hidden0:
        break
laps += 2   # a couple of extra laps of margin
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
