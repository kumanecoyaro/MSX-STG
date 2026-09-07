"""Stage1: 敵撃破爆発を単一セル2フェーズ色替えフリッカーから、添付
ExpAnim_24x24.jsonベースの3フレーム/複数セル左シフトアニメーションへ
全面差し替え(round69 follow-up)の検証。tools/verify_enemy_bullets.py
と同じ「mini_z80asm.Assemblerで直接アセンブル+call_routine(センチネル
0xF000/0x0000方式)」の作法に倣う。

frame1=中心タイル(EXP_CODE_THIN)のみ / frame2=3タイル(THIN,THICK,THIN、
中心から2列左を起点) / frame3=1列空けて外側2タイル(THIN、中心から3列
左を起点、中央列は背景に復元) - GIFプレビューでユーザー確認済みの設計。
色は常に旧ANIM2_BLUE(group15、fg赤/bg青、COLORDATA無変更)固定 - 地上
での水平打ち破壊も同じ経路を通るため自動的に同じ色になる。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=300000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


TRIGGER_EXPLOSION = sym["TRIGGER_EXPLOSION"]
UPDATE_ONE_EXPLOSION = sym["UPDATE_ONE_EXPLOSION"]
ANIM_BASE = sym["ANIM_BASE"]
ANIM_RR = sym["ANIM_RR"]
ANIM_FRAME_LEN = sym["ANIM_FRAME_LEN"]
EXP_CODE_THIN = sym["EXP_CODE_THIN"]
EXP_CODE_THICK = sym["EXP_CODE_THICK"]
EXPLOSION_SAVED_CM3 = sym["EXPLOSION_SAVED_CM3"]
GROUND_ROW0 = sym["GROUND_ROW0"]
BLANKCODE = sym["BLANKCODE"]
NAMEBUF = sym["NAMEBUF"]

NAMTBL = 0x1800


def cell(z, row, col):
    return z.vram[NAMTBL + row * 32 + col]


def trigger(z, x, y):
    z.d = x
    z.e = y
    call_routine(z, TRIGGER_EXPLOSION)


def advance_one_slot(z, slot):
    z.ix = ANIM_BASE + slot * 8
    z.b = slot
    call_routine(z, UPDATE_ONE_EXPLOSION)


def advance_all_slots(z):
    for slot in range(3):
        advance_one_slot(z, slot)


# ---- basic frame1 layout ----
z = fresh()
boot(z)
row, col = 10, 16
trigger(z, col * 8, row * 8)
check("frame1: draws EXP_CODE_THIN at column C only",
      cell(z, row, col) == EXP_CODE_THIN)
check("frame1: columns C-1,C-2,C-3 untouched (still show pre-explosion sky background)",
      cell(z, row, col - 1) == BLANKCODE and cell(z, row, col - 2) == BLANKCODE
      and cell(z, row, col - 3) == BLANKCODE)
check("ACTIVE/FRAME/TIMER set for slot0 (round-robin picks slot0 first)",
      (z.rd(ANIM_BASE + 0), z.rd(ANIM_BASE + 1), z.rd(ANIM_BASE + 2)) == (1, 1, ANIM_FRAME_LEN))

# ---- advance to frame2 ----
for _ in range(ANIM_FRAME_LEN):
    advance_one_slot(z, 0)
check("frame2: draws THIN,THICK,THIN across columns C-2,C-1,C",
      (cell(z, row, col - 2), cell(z, row, col - 1), cell(z, row, col))
      == (EXP_CODE_THIN, EXP_CODE_THICK, EXP_CODE_THIN))
check("frame2: column C-3 still untouched",
      cell(z, row, col - 3) == BLANKCODE)
check("FRAME field advanced to 2", z.rd(ANIM_BASE + 1) == 2)

# ---- advance to frame3 ----
for _ in range(ANIM_FRAME_LEN):
    advance_one_slot(z, 0)
check("frame3: column C restored to background (no longer drawn)",
      cell(z, row, col) == BLANKCODE)
check("frame3: column C-2 (frame2's own center) restored to background too",
      cell(z, row, col - 2) == BLANKCODE)
check("frame3: draws THIN at the 2 outer columns C-3 and C-1",
      (cell(z, row, col - 3), cell(z, row, col - 1)) == (EXP_CODE_THIN, EXP_CODE_THIN))
check("FRAME field advanced to 3", z.rd(ANIM_BASE + 1) == 3)

# ---- finish: all 4 columns restored, slot deactivated ----
for _ in range(ANIM_FRAME_LEN):
    advance_one_slot(z, 0)
check("finish: all 4 columns (C,C-1,C-2,C-3) restored to background",
      all(cell(z, row, c) == BLANKCODE for c in (col, col - 1, col - 2, col - 3)))
check("finish: ACTIVE cleared back to 0", z.rd(ANIM_BASE + 0) == 0)


# ---- ground-row kill: exact same tiles/color as sky (no more per-row branching) ----
z = fresh()
boot(z)
ground_row = GROUND_ROW0 + 1  # a "green" row under the old design
col2 = 20
trigger(z, col2 * 8, ground_row * 8)
check("ground-row kill: still uses EXP_CODE_THIN (identical to a sky kill, no row-based color anymore)",
      cell(z, ground_row, col2) == EXP_CODE_THIN)


# ---- ground-row kill: SAVED must come from (and restore into) NAMEBUF, ----
# ---- not just BLANKCODE, and must reflect what's actually drawn there ----
z = fresh()
boot(z)
ground_row = GROUND_ROW0 + 2
col3 = 15
nb_off = (ground_row - GROUND_ROW0) * 32
poked = [77, 78, 79, 80]  # arbitrary distinct "terrain" codes at C-3..C
for i, v in enumerate(poked):
    z.wr(NAMEBUF + nb_off + col3 - 3 + i, v)
    z.wr(NAMTBL + ground_row * 32 + col3 - 3 + i, v)
trigger(z, col3 * 8, ground_row * 8)
for _ in range(3 * ANIM_FRAME_LEN):
    advance_one_slot(z, 0)
check("ground-row kill: after the full animation finishes, all 4 columns are "
      "restored to their real NAMEBUF-derived terrain codes (not BLANKCODE)",
      [cell(z, ground_row, col3 - 3 + i) for i in range(4)] == poked)
check("ground-row kill: NAMEBUF mirror itself still holds the same original values "
      "(WRITE_ANIM_CELL's restore-writes didn't corrupt the mirror it reads from)",
      [z.rd(NAMEBUF + nb_off + col3 - 3 + i) for i in range(4)] == poked)


# ---- re-triggering a still-active slot fully restores its OLD footprint ----
# TRIGGER_EXPLOSION only falls back to round-robin reuse once all 3 slots
# are already active (it otherwise always prefers a genuinely free slot) -
# so all 3 must be filled first before a 4th trigger actually forces reuse.
z = fresh()
boot(z)
row = 8
col_a, col_b, col_c = 6, 14, 22  # 8 columns apart - frame2's 3-wide footprints never overlap
trigger(z, col_a * 8, row * 8)   # -> slot0
trigger(z, col_b * 8, row * 8)   # -> slot1 (unrelated, far away)
trigger(z, col_c * 8, row * 8)   # -> slot2 (unrelated, far away)
for _ in range(ANIM_FRAME_LEN):
    advance_all_slots(z)  # all 3 now showing frame2 (3-column footprint each)
new_row, new_col = 8, 28  # far enough away that footprints don't overlap slot0's old one
trigger(z, new_col * 8, new_row * 8)  # ANIM_RR wraps back to slot0 as the 4th trigger - see the trace in this file's own comment history
check("re-trigger reused slot0 (ANIM_RR round-robin, all 3 slots were active)",
      (z.rd(ANIM_BASE + 3), z.rd(ANIM_BASE + 4)) == (new_row, new_col))
check("re-trigger doesn't corrupt: slot0's old frame2 footprint (col_a-2..col_a) is "
      "fully restored to background before being overwritten by the new explosion",
      all(cell(z, row, c) == BLANKCODE for c in (col_a - 2, col_a - 1, col_a)))
check("re-trigger: new explosion's frame1 tile is drawn at the new position",
      cell(z, new_row, new_col) == EXP_CODE_THIN)
check("re-trigger: the OTHER 2 unrelated slots (slot1/2) are untouched, still mid-animation",
      cell(z, row, col_b) != BLANKCODE and cell(z, row, col_c) != BLANKCODE)


# ---- 3 concurrent slots (round robin) don't clobber each other ----
z = fresh()
boot(z)
positions = [(6, 10), (12, 20), (18, 25)]
for r, c in positions:
    trigger(z, c * 8, r * 8)
for i, (r, c) in enumerate(positions):
    check(f"concurrent slot{i}: frame1 tile visible at its own position",
          cell(z, r, c) == EXP_CODE_THIN)
for _ in range(ANIM_FRAME_LEN):
    advance_all_slots(z)
for i, (r, c) in enumerate(positions):
    check(f"concurrent slot{i}: reached frame2 (3-column footprint) independently",
          (cell(z, r, c - 2), cell(z, r, c - 1), cell(z, r, c))
          == (EXP_CODE_THIN, EXP_CODE_THICK, EXP_CODE_THIN))


# ---- left-edge clamp: an explosion near column0 must not wrap/crash ----
z = fresh()
boot(z)
row, col = 10, 1  # C=1, so C-2/C-3 would go negative without clamping
trigger(z, col * 8, row * 8)
for _ in range(3 * ANIM_FRAME_LEN):
    advance_one_slot(z, 0)
check("left-edge clamp: explosion near column0 runs to completion without wrapping "
      "into a bogus high column (would show as corruption far to the right)",
      z.rd(ANIM_BASE + 0) == 0)
check("left-edge clamp: column0 itself ends up restored to background (clamped "
      "writes/restores at 0 are harmless no-ops, not corruption)",
      cell(z, row, 0) == BLANKCODE)


# ---- INIT explicitly zero-clears EXPLOSION_SAVED_CM3 (round36-14 follow-up#14's ----
# ---- "RAM初期化漏れ" lesson - must not rely on emulator's zero-init RAM) ----
z = fresh()
for i in range(3):
    z.wr(EXPLOSION_SAVED_CM3 + i, 0xAA)
z.pc = sym["INIT"]
run_until_pc(z, sym["MAINLOOP"])
check("INIT explicitly zero-clears all 3 EXPLOSION_SAVED_CM3 bytes (poisoned "
      "0xAA beforehand, must not survive INIT)",
      all(z.rd(EXPLOSION_SAVED_CM3 + i) == 0 for i in range(3)))


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
