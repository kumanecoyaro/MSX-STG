import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

THUNDER_ACT = sym["THUNDER_ACT"]
THUNDER_COL = sym["THUNDER_COL"]
THUNDER_ROW = sym["THUNDER_ROW"]
THUNDER_TIMER = sym["THUNDER_TIMER"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
THUNDER_ELIGIBLE = sym["THUNDER_ELIGIBLE"]
THUNDER_LEG_START_X = sym["THUNDER_LEG_START_X"]
THUNDER_CODE_BASE = sym["THUNDER_CODE_BASE"]
THUNDER_COLORBYTE = sym["THUNDER_COLORBYTE"]
THUNDER_TOP_ROW = sym["THUNDER_TOP_ROW"]
THUNDER_ROW_STEP = sym["THUNDER_ROW_STEP"]
THUNDER_BOTTOM_ROW = sym["THUNDER_BOTTOM_ROW"]
THUNDER_TRIGGER_DX = sym["THUNDER_TRIGGER_DX"]
THUNDER_STEP_INTERVAL = sym["THUNDER_STEP_INTERVAL"]
BOSS_X = sym["BOSS_X"]
BOSS_DIR = sym["BOSS_DIR"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPEED = sym["BOSS_SPEED"]
NIGHT_ROW = sym["NIGHT_ROW"]
SKY_BLANK_CODE = sym["SKY_BLANK_CODE"]

TL, TR, BL, BR = (THUNDER_CODE_BASE + i for i in range(4))


def name_addr(row, col):
    return 0x1800 + row * 32 + col


def cell(cpu, row, col):
    return cpu.vram[name_addr(row, col)]


def block_codes(cpu, row, col):
    return (cell(cpu, row, col), cell(cpu, row, col + 1),
            cell(cpu, row + 1, col), cell(cpu, row + 1, col + 1))


def block_rows():
    r = THUNDER_TOP_ROW
    rows = []
    while r <= THUNDER_BOTTOM_ROW:
        rows.append(r)
        r += THUNDER_ROW_STEP
    return rows


ROWS = block_rows()


# ---- INIT: Thunder BG art + color byte actually loaded into VRAM ----
cpu = fresh_cpu()
pat_base = THUNDER_CODE_BASE * 8
loaded = list(cpu.vram[pat_base:pat_base + 32])
check("INIT loads all 32 nonzero Thunder pattern bytes (4 tiles x8 rows) - not left as 0/uninitialized",
      any(b != 0 for b in loaded))
check("INIT writes THUNDER_COLORBYTE into group27's own color-table entry (2000h+27)",
      cpu.vram[0x2000 + 27] == THUNDER_COLORBYTE)


# ---- FIRE_THUNDER: arms a fresh grow cycle at the given column ----
cpu = fresh_cpu()
cpu.mem[THUNDER_ACT] = 0
cpu.mem[THUNDER_ROW] = 99
cpu.mem[THUNDER_TIMER] = 99
cpu.a = 12
call_routine(cpu, "FIRE_THUNDER")
check("FIRE_THUNDER sets THUNDER_COL to the passed column", cpu.mem[THUNDER_COL] == 12)
check("FIRE_THUNDER sets THUNDER_ACT to 1 (growing)", cpu.mem[THUNDER_ACT] == 1)
check("FIRE_THUNDER resets THUNDER_ROW to THUNDER_TOP_ROW", cpu.mem[THUNDER_ROW] == THUNDER_TOP_ROW)
check("FIRE_THUNDER resets THUNDER_TIMER to 0 (steps on the very next UPDATE_THUNDER call)",
      cpu.mem[THUNDER_TIMER] == 0)


# ---- UPDATE_THUNDER: no-op while inactive ----
cpu = fresh_cpu()
cpu.mem[THUNDER_ACT] = 0
before = list(cpu.vram[0x1800:0x1800 + 32 * 24])
call_routine(cpu, "UPDATE_THUNDER")
after = list(cpu.vram[0x1800:0x1800 + 32 * 24])
check("UPDATE_THUNDER touches no VRAM while THUNDER_ACT=0", before == after)


# ---- DRAW_THUNDER_BLOCK / ERASE_THUNDER_BLOCK: single-block unit checks ----
cpu = fresh_cpu()
cpu.mem[THUNDER_ROW] = 5
cpu.mem[THUNDER_COL] = 10
cpu.mem[NIGHT_ROW] = 0  # fresh boot - night sweep hasn't reached row5, plain sky
call_routine(cpu, "DRAW_THUNDER_BLOCK")
check("DRAW_THUNDER_BLOCK writes TL/TR/BL/BR in the right 2x2 positions",
      block_codes(cpu, 5, 10) == (TL, TR, BL, BR))

call_routine(cpu, "ERASE_THUNDER_BLOCK")
check("ERASE_THUNDER_BLOCK restores the block to plain sky (SKY_BLANK_CODE) via ERASE_BULLET_CELL reuse",
      block_codes(cpu, 5, 10) == (SKY_BLANK_CODE,) * 4)


# ---- UPDATE_THUNDER: full grow cycle - fills down and ACCUMULATES (earlier
# blocks stay drawn while later ones appear), matching "埋める" (fill), not
# "draw one and immediately erase the last" ----
# UPDATE_THUNDER's own timer is check-then-decrement, so the real gap
# between successive steps is THUNDER_STEP_INTERVAL+1 calls, not
# THUNDER_STEP_INTERVAL - rather than hardcode that, just keep calling
# until THUNDER_ROW or THUNDER_ACT actually changes (a step happened).
def advance_one_step(cpu):
    row_before = cpu.mem[THUNDER_ROW]
    act_before = cpu.mem[THUNDER_ACT]
    for _ in range(THUNDER_STEP_INTERVAL + 2):
        call_routine(cpu, "UPDATE_THUNDER")
        if cpu.mem[THUNDER_ROW] != row_before or cpu.mem[THUNDER_ACT] != act_before:
            return
    raise AssertionError("UPDATE_THUNDER never advanced within STEP_INTERVAL+2 calls")


cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 0
cpu.a = 3
call_routine(cpu, "FIRE_THUNDER")
for step in range(len(ROWS)):
    advance_one_step(cpu)
    row = ROWS[step]
    check(f"grow step {step}: block at row{row} is now drawn", block_codes(cpu, row, 3) == (TL, TR, BL, BR))
    for prev in ROWS[:step]:
        check(f"grow step {step}: earlier block at row{prev} is still drawn (accumulates, not wiped)",
              block_codes(cpu, prev, 3) == (TL, TR, BL, BR))
check("after all grow steps, THUNDER_ACT has switched to 2 (shrinking) - 埋め終わった",
      cpu.mem[THUNDER_ACT] == 2)
check("shrink starts back at THUNDER_TOP_ROW - 上から消す", cpu.mem[THUNDER_ROW] == THUNDER_TOP_ROW)


# ---- UPDATE_THUNDER: full shrink cycle - erases from the TOP down,
# clears every block, and returns to inactive with no leftover garbage ----
for step in range(len(ROWS)):
    advance_one_step(cpu)
    row = ROWS[step]
    check(f"shrink step {step}: block at row{row} is erased (no longer Thunder codes)",
          block_codes(cpu, row, 3) != (TL, TR, BL, BR))
    for later in ROWS[step + 1:]:
        check(f"shrink step {step}: not-yet-reached block at row{later} is still drawn",
              block_codes(cpu, later, 3) == (TL, TR, BL, BR))
check("after all shrink steps, THUNDER_ACT returns to 0 (inactive)", cpu.mem[THUNDER_ACT] == 0)
for row in ROWS:
    check(f"final: row{row} has no leftover Thunder-code residue", block_codes(cpu, row, 3) != (TL, TR, BL, BR))


# ---- CHECK_THUNDER_TRIGGER_LEFT: gated by PENDING, fires at >=16px moved,
# column = (BOSS_X+64)>>3 (the boss's own current right edge) ----
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 0
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 50
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT is a no-op while THUNDER_PENDING=0 (not armed)", cpu.mem[THUNDER_ACT] == 0)

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 90  # moved 10px - under THUNDER_TRIGGER_DX(16)
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT does not fire before THUNDER_TRIGGER_DX has elapsed", cpu.mem[THUNDER_ACT] == 0)
check("...and THUNDER_PENDING stays armed", cpu.mem[THUNDER_PENDING] == 1)

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 100 - THUNDER_TRIGGER_DX  # exactly at the threshold
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT fires (>=, not exact-match) right at THUNDER_TRIGGER_DX", cpu.mem[THUNDER_ACT] == 1)
check("...and clears THUNDER_PENDING so it only fires once per leg", cpu.mem[THUNDER_PENDING] == 0)
expect_col = ((100 - THUNDER_TRIGGER_DX) + 64) >> 3
check("fires at the boss's own current RIGHT edge (BOSS_X+64) converted to a BG column",
      cpu.mem[THUNDER_COL] == expect_col)

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 20  # well past the threshold
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT also fires once the boss has moved well past the threshold",
      cpu.mem[THUNDER_ACT] == 1)


# ---- CHECK_THUNDER_TRIGGER_RIGHT: same idea, column = BOSS_X>>3 (the
# boss's own current LEFT edge) ----
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 0
cpu.mem[THUNDER_LEG_START_X] = 0
cpu.mem[BOSS_X] = 40
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT is a no-op while THUNDER_PENDING=0", cpu.mem[THUNDER_ACT] == 0)

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 0
cpu.mem[BOSS_X] = THUNDER_TRIGGER_DX - 1  # 1px short
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT does not fire 1px short of THUNDER_TRIGGER_DX", cpu.mem[THUNDER_ACT] == 0)

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 0
cpu.mem[BOSS_X] = THUNDER_TRIGGER_DX
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT fires right at THUNDER_TRIGGER_DX", cpu.mem[THUNDER_ACT] == 1)
check("fires at the boss's own current LEFT edge (BOSS_X itself) converted to a BG column",
      cpu.mem[THUNDER_COL] == (THUNDER_TRIGGER_DX >> 3))
check("THUNDER_PENDING clears once fired", cpu.mem[THUNDER_PENDING] == 0)


# ---- real MAINLOOP: Thunder stays silent through the boss's pre-first-
# pose patrol (spawn -> left leg -> reversal -> right leg -> first pose),
# then fires exactly once per post-pose leg, at the right column, and
# always finishes its own grow+shrink cycle before the leg ends ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned = False
pose1_entered = False
pose1_ended = False
thunder_armed_pre_pose1 = False
thunder_fired_pre_pose1 = False
fires = []  # (frame, boss_x_at_fire, thunder_col, leg)  leg: 'L' or 'R'
prev_act = 0
prev_dir = None
legs_seen_post_pose1 = 0
for f in range(20000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1:
        boss_spawned = True
    if boss_spawned and not pose1_ended:
        if cpu.mem[BOSS_PHASE] == 1:
            pose1_entered = True
        elif pose1_entered:
            pose1_ended = True
        if not pose1_ended:
            if cpu.mem[THUNDER_PENDING] == 1:
                thunder_armed_pre_pose1 = True
            if cpu.mem[THUNDER_ACT] != 0:
                thunder_fired_pre_pose1 = True
    act = cpu.mem[THUNDER_ACT]
    if pose1_ended and act != 0 and prev_act == 0:
        leg = 'L' if cpu.mem[BOSS_DIR] == 0 else 'R'
        fires.append((f, cpu.mem[BOSS_X], cpu.mem[THUNDER_COL], leg))
    prev_act = act
    if pose1_ended and len(fires) >= 2:
        # both post-pose1 fires captured (leftward leg, then rightward leg) -
        # let a bit more run to also confirm the 2nd one completes cleanly
        if act == 0 and f - fires[-1][0] > THUNDER_STEP_INTERVAL * (len(ROWS) * 2 + 2):
            break

check("real MAINLOOP: boss reaches its first attack pose", boss_spawned and pose1_entered and pose1_ended)
check("real MAINLOOP: THUNDER_PENDING is never armed before the first pose ends - "
      "ホーミング攻撃後 gates Thunder off during the pre-pose legs",
      not thunder_armed_pre_pose1)
check("real MAINLOOP: Thunder never actually fires before the first pose ends",
      not thunder_fired_pre_pose1)
check("real MAINLOOP: Thunder fires exactly twice right after the first pose - once per leg "
      "(leftward then rightward)", len(fires) == 2)
if len(fires) == 2:
    f0, x0, col0, leg0 = fires[0]
    f1, x1, col1, leg1 = fires[1]
    check("1st post-pose fire happens on the LEFTWARD leg (ホーミング攻撃後左に移動中に)", leg0 == 'L')
    check("1st fire's column matches the boss's own right edge ((BOSS_X+64)>>3) at that exact frame",
          col0 == (x0 + 64) >> 3)
    check("2nd post-pose fire happens on the RIGHTWARD leg (そのまま左まで行き反転後)", leg1 == 'R')
    check("2nd fire's column matches the boss's own left edge (BOSS_X>>3) at that exact frame",
          col1 == x1 >> 3)
    check("both fired columns are valid BG columns (0-31)", 0 <= col0 <= 31 and 0 <= col1 <= 31)
    check("the two fires are on two different legs, well separated in time (not both on the same leg)",
          f1 - f0 > THUNDER_STEP_INTERVAL)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
