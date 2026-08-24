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
THUNDER_EXTRA_ROW = sym["THUNDER_EXTRA_ROW"]
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

check("THUNDER_STEP_INTERVAL is 0 - 表示ウェイト不要", THUNDER_STEP_INTERVAL == 0)
check("THUNDER_TRIGGER_DX is 32 - ボスが横に32px移動毎に発射", THUNDER_TRIGGER_DX == 32)
check("THUNDER_EXTRA_ROW is exactly one row-step past THUNDER_BOTTOM_ROW - あと1セル分長く",
      THUNDER_EXTRA_ROW == THUNDER_BOTTOM_ROW + THUNDER_ROW_STEP)


def name_addr(row, col):
    return 0x1800 + row * 32 + col


def cell(cpu, row, col):
    return cpu.vram[name_addr(row, col)]


def block_codes(cpu, row, col):
    return (cell(cpu, row, col), cell(cpu, row, col + 1),
            cell(cpu, row + 1, col), cell(cpu, row + 1, col + 1))


def half_codes(cpu, row, col):
    return (cell(cpu, row, col), cell(cpu, row, col + 1))


def full_block_rows():
    r = THUNDER_TOP_ROW
    rows = []
    while r <= THUNDER_BOTTOM_ROW:
        rows.append(r)
        r += THUNDER_ROW_STEP
    return rows


ROWS = full_block_rows()  # full 2x2 blocks only, NOT the trailing half row


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


# ---- DRAW_THUNDER_HALF / ERASE_THUNDER_HALF: the extra 1-cell-row unit checks ----
cpu = fresh_cpu()
cpu.mem[THUNDER_ROW] = THUNDER_EXTRA_ROW
cpu.mem[THUNDER_COL] = 10
cpu.mem[NIGHT_ROW] = 0
call_routine(cpu, "DRAW_THUNDER_HALF")
check("DRAW_THUNDER_HALF writes only the bottom-half tiles (BL/BR), one row",
      half_codes(cpu, THUNDER_EXTRA_ROW, 10) == (BL, BR))

TERRAIN_BLANK_CODE = sym["TERRAIN_BLANK_CODE"]
call_routine(cpu, "ERASE_THUNDER_HALF")
check("ERASE_THUNDER_HALF restores the extra row (row19, the TERRAIN_BLANK_CODE band per "
      "ERASE_BULLET_CELL's own row17-19 branch, not plain sky)",
      half_codes(cpu, THUNDER_EXTRA_ROW, 10) == (TERRAIN_BLANK_CODE, TERRAIN_BLANK_CODE))


# ---- UPDATE_THUNDER: full grow cycle - fills down and ACCUMULATES (earlier
# blocks stay drawn while later ones appear), matching "埋める" (fill), not
# "draw one and immediately erase the last" - with THUNDER_STEP_INTERVAL=0
# every single UPDATE_THUNDER call performs exactly one draw step now
# (表示ウェイト不要), so no per-step waiting/polling is needed any more. ----
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 0
cpu.a = 3
call_routine(cpu, "FIRE_THUNDER")
for step in range(len(ROWS)):
    call_routine(cpu, "UPDATE_THUNDER")
    row = ROWS[step]
    check(f"grow step {step}: block at row{row} is now drawn", block_codes(cpu, row, 3) == (TL, TR, BL, BR))
    for prev in ROWS[:step]:
        check(f"grow step {step}: earlier block at row{prev} is still drawn (accumulates, not wiped)",
              block_codes(cpu, prev, 3) == (TL, TR, BL, BR))
# the final "1セル分長く" extra half-row step
call_routine(cpu, "UPDATE_THUNDER")
check("grow's final step draws the extra half-row at THUNDER_EXTRA_ROW - あと1セル分長く",
      half_codes(cpu, THUNDER_EXTRA_ROW, 3) == (BL, BR))
for prev in ROWS:
    check(f"after the extra half-row step, earlier block at row{prev} is still drawn",
          block_codes(cpu, prev, 3) == (TL, TR, BL, BR))
check("after all grow steps (full blocks + the extra half-row), THUNDER_ACT switches to 2 (shrinking) - "
      "埋め終わった", cpu.mem[THUNDER_ACT] == 2)
check("shrink starts back at THUNDER_TOP_ROW - 上から消す", cpu.mem[THUNDER_ROW] == THUNDER_TOP_ROW)


# ---- UPDATE_THUNDER: full shrink cycle - erases from the TOP down (full
# blocks first, the extra half-row last, same order as growth), clears
# every block, and returns to inactive with no leftover garbage ----
for step in range(len(ROWS)):
    call_routine(cpu, "UPDATE_THUNDER")
    row = ROWS[step]
    check(f"shrink step {step}: block at row{row} is erased (no longer Thunder codes)",
          block_codes(cpu, row, 3) != (TL, TR, BL, BR))
    for later in ROWS[step + 1:]:
        check(f"shrink step {step}: not-yet-reached block at row{later} is still drawn",
              block_codes(cpu, later, 3) == (TL, TR, BL, BR))
    check(f"shrink step {step}: not-yet-reached extra half-row is still drawn",
          half_codes(cpu, THUNDER_EXTRA_ROW, 3) == (BL, BR))
call_routine(cpu, "UPDATE_THUNDER")  # erases the extra half-row, finishes the cycle
check("shrink's final step erases the extra half-row", half_codes(cpu, THUNDER_EXTRA_ROW, 3) != (BL, BR))
check("after all shrink steps, THUNDER_ACT returns to 0 (inactive)", cpu.mem[THUNDER_ACT] == 0)
for row in ROWS:
    check(f"final: row{row} has no leftover Thunder-code residue", block_codes(cpu, row, 3) != (TL, TR, BL, BR))


# ---- CHECK_THUNDER_TRIGGER_LEFT: gated by PENDING, fires at >=32px moved,
# column = (BOSS_X+64)>>3 (the boss's own current right edge), and now
# re-arms rather than one-shot per leg (round9) ----
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
cpu.mem[BOSS_X] = 70  # moved 30px - under THUNDER_TRIGGER_DX(32)
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
check("...and THUNDER_PENDING stays 1 (armed for the REST of the leg too - not a one-shot any more)",
      cpu.mem[THUNDER_PENDING] == 1)
check("...and THUNDER_LEG_START_X re-arms to the boss's own current X (baseline for the next 32px)",
      cpu.mem[THUNDER_LEG_START_X] == 100 - THUNDER_TRIGGER_DX)
expect_col = ((100 - THUNDER_TRIGGER_DX) + 64) >> 3
check("fires at the boss's own current RIGHT edge (BOSS_X+64) converted to a BG column",
      cpu.mem[THUNDER_COL] == expect_col)

# busy gate: a previous column still animating (THUNDER_ACT!=0) blocks a
# new fire even once the 32px threshold has been reached - single instance
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 20  # well past the threshold
cpu.mem[THUNDER_ACT] = 1  # still animating a previous column
cpu.mem[THUNDER_COL] = 77
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT skips firing while the previous column is still animating (single instance)",
      cpu.mem[THUNDER_COL] == 77)
check("...THUNDER_LEG_START_X is left untouched so distance keeps accumulating",
      cpu.mem[THUNDER_LEG_START_X] == 100)

# once no longer busy, the accumulated distance immediately fires (using
# the CURRENT edge X, not a stale one) - "32px移動毎に" continues to hold
# across the busy gate rather than being lost
cpu.mem[THUNDER_ACT] = 0
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("once idle again, the still-armed trigger fires immediately", cpu.mem[THUNDER_ACT] == 1)
check("fires at the CURRENT edge column, not the original 32px-mark position",
      cpu.mem[THUNDER_COL] == (20 + 64) >> 3)

# repeats again for a second 32px leg of travel after re-arming
cpu.mem[THUNDER_ACT] = 0  # simulate this cycle finishing
cpu.mem[BOSS_X] = 20 - THUNDER_TRIGGER_DX
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT fires AGAIN after another THUNDER_TRIGGER_DX px - not just once per leg",
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
check("THUNDER_PENDING stays armed (repeats for the rest of the leg)", cpu.mem[THUNDER_PENDING] == 1)

cpu.mem[THUNDER_ACT] = 0
cpu.mem[BOSS_X] = THUNDER_TRIGGER_DX * 2
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT also fires again after another THUNDER_TRIGGER_DX px", cpu.mem[THUNDER_ACT] == 1)


# ---- real MAINLOOP: Thunder stays silent through the boss's pre-first-
# pose patrol (spawn -> left leg -> reversal -> right leg -> first pose),
# then fires REPEATEDLY (every ~32px, round9) on each post-pose leg, at
# the right column each time, never overlapping (single instance) ----
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
legs_with_2plus_fires = set()
for f in range(30000):
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
    if pose1_ended:
        per_leg = {}
        for _, _, _, leg in fires:
            per_leg[leg] = per_leg.get(leg, 0) + 1
        legs_with_2plus_fires = {leg for leg, n in per_leg.items() if n >= 2}
        if {'L', 'R'} <= legs_with_2plus_fires and act == 0:
            break

check("real MAINLOOP: boss reaches its first attack pose", boss_spawned and pose1_entered and pose1_ended)
check("real MAINLOOP: THUNDER_PENDING is never armed before the first pose ends - "
      "ホーミング攻撃後 gates Thunder off during the pre-pose legs",
      not thunder_armed_pre_pose1)
check("real MAINLOOP: Thunder never actually fires before the first pose ends",
      not thunder_fired_pre_pose1)
check("real MAINLOOP: Thunder fires at least twice on the leftward leg - 端だけではなく32px移動毎に発射",
      'L' in legs_with_2plus_fires)
check("real MAINLOOP: Thunder fires at least twice on the rightward leg too",
      'R' in legs_with_2plus_fires)

left_fires = [f for f in fires if f[3] == 'L']
right_fires = [f for f in fires if f[3] == 'R']
if len(left_fires) >= 2:
    for (_, x0, col0, _), (_, x1, col1, _) in zip(left_fires, left_fires[1:]):
        check(f"leftward-leg fires stay correctly positioned at the boss's own right edge each time (x={x0})",
              col0 == (x0 + 64) >> 3)
        check(f"consecutive leftward-leg fires are spaced by at least THUNDER_TRIGGER_DX px (x{x0}->x{x1})",
              x0 - x1 >= THUNDER_TRIGGER_DX)
    check("last leftward-leg fire column also matches the boss's own right edge",
          left_fires[-1][2] == (left_fires[-1][1] + 64) >> 3)
if len(right_fires) >= 2:
    for (_, x0, col0, _), (_, x1, col1, _) in zip(right_fires, right_fires[1:]):
        check(f"rightward-leg fires stay correctly positioned at the boss's own left edge each time (x={x0})",
              col0 == x0 >> 3)
        check(f"consecutive rightward-leg fires are spaced by at least THUNDER_TRIGGER_DX px (x{x0}->x{x1})",
              x1 - x0 >= THUNDER_TRIGGER_DX)
    check("last rightward-leg fire column also matches the boss's own left edge",
          right_fires[-1][2] == right_fires[-1][1] >> 3)
check("all fired columns are valid BG columns (0-31)",
      all(0 <= c <= 31 for _, _, c, _ in fires))

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
