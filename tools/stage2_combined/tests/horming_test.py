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

HORMING_ACT = sym["HORMING_ACT"]
HORMING_PHASE = sym["HORMING_PHASE"]
HORMING_COL = sym["HORMING_COL"]
HORMING_ROW = sym["HORMING_ROW"]
HORMING_FACING = sym["HORMING_FACING"]
HORMING_ADDR_LO = sym["HORMING_ADDR_LO"]
HORMING_ADDR_HI = sym["HORMING_ADDR_HI"]
HORMING_SPAWN_COL = sym["HORMING_SPAWN_COL"]
HORMING_SPAWN_ROW = sym["HORMING_SPAWN_ROW"]
HORMING_CENTER_COL = sym["HORMING_CENTER_COL"]
TANK_WIDTH = sym["TANK_WIDTH"]
HORMING_SIDE_DIST = sym["HORMING_SIDE_DIST"]
HORMING_MAXCOL = sym["HORMING_MAXCOL"]
HORMING_MAXROW = sym["HORMING_MAXROW"]
HORMING_SL_CODE = sym["HORMING_SL_CODE"]
HORMING_DL_CODE = sym["HORMING_DL_CODE"]
HORMING_DOWN_CODE = sym["HORMING_DOWN_CODE"]
HORMING_DR_CODE = sym["HORMING_DR_CODE"]
HORMING_SR_CODE = sym["HORMING_SR_CODE"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_LIFE = sym["TANK_LIFE"]
TANK_LIFE_INIT = sym["TANK_LIFE_INIT"]
TANK_FLASH_TIMER = sym["TANK_FLASH_TIMER"]
FLASH_DURATION = sym["FLASH_DURATION"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_PHASE = sym["BOSS_PHASE"]

FACING_CODE = [HORMING_SL_CODE, HORMING_DL_CODE, HORMING_DOWN_CODE, HORMING_DR_CODE, HORMING_SR_CODE]


def cur_addr(cpu):
    return cpu.mem[HORMING_ADDR_LO] | (cpu.mem[HORMING_ADDR_HI] << 8)


def cell_code(cpu):
    col = cpu.mem[HORMING_COL]
    return cpu.vram[cur_addr(cpu) + col]


# ---- FIRE_HORMING ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_HORMING")
check("fires with ACT=1", cpu.mem[HORMING_ACT] == 1)
check("fires with PHASE=0 (straight)", cpu.mem[HORMING_PHASE] == 0)
check("fires at HORMING_SPAWN_COL/ROW - ボス右上あたり",
      cpu.mem[HORMING_COL] == HORMING_SPAWN_COL and cpu.mem[HORMING_ROW] == HORMING_SPAWN_ROW)
check("fires facing SL(0)", cpu.mem[HORMING_FACING] == 0)
check("draws the SL code at the spawn cell", cell_code(cpu) == HORMING_SL_CODE)

# refuses to fire again while already active
col_before = cpu.mem[HORMING_COL]
call_routine(cpu, "FIRE_HORMING")
check("refuses to re-fire while already active (drops the attempt)",
      cpu.mem[HORMING_COL] == col_before)

# ---- phase0: straight left, 1 col/frame, always SL ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_HORMING")
c0 = cpu.mem[HORMING_COL]
call_routine(cpu, "UPDATE_HORMING")
check("steps left by 1 col/frame during phase0", cpu.mem[HORMING_COL] == c0 - 1)
check("still facing SL during phase0", cpu.mem[HORMING_FACING] == 0)

# ---- phase transition at screen center ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_HORMING")
cpu.mem[HORMING_COL] = HORMING_CENTER_COL + 1
cpu.mem[TANK_X] = 0  # keep the tank far away so it doesn't interfere with this check
steps = 0
while cpu.mem[HORMING_PHASE] == 0 and steps < 50:
    call_routine(cpu, "UPDATE_HORMING")
    steps += 1
check("phase flips to homing(1) once COL reaches screen-center - X軸中央辺りまで水平打ち その後ホーミング動作",
      cpu.mem[HORMING_PHASE] == 1)
# the transition and this frame's own movement resolve in the same
# UPDATE_HORMING call (by design - see its own comment), so by the time
# the loop above observes PHASE==1, COL has already taken 1 more
# homing step past HORMING_CENTER_COL - checked directly below instead.
cpu2 = fresh_cpu()
call_routine(cpu2, "FIRE_HORMING")
cpu2.mem[HORMING_COL] = HORMING_CENTER_COL + 1
cpu2.mem[TANK_X] = 0
call_routine(cpu2, "UPDATE_HORMING")
check("still phase0 1 col before center", cpu2.mem[HORMING_PHASE] == 0 and cpu2.mem[HORMING_COL] == HORMING_CENTER_COL)
call_routine(cpu2, "UPDATE_HORMING")
check("phase flips to homing on the exact frame COL reaches HORMING_CENTER_COL",
      cpu2.mem[HORMING_PHASE] == 1)


def make_active(cpu, col, row, tank_x):
    cpu.mem[HORMING_ACT] = 1
    cpu.mem[HORMING_PHASE] = 1
    cpu.mem[HORMING_COL] = col
    cpu.mem[HORMING_ROW] = row
    cpu.mem[TANK_X] = tank_x
    cpu.mem[TANK_Y_CUR] = 200  # keep the tank far below so height never causes an accidental hit in these facing checks


# ---- RESOLVE_HORMING_FACING bucket boundaries ----
# missile at col20 (X=160). Tank to the LEFT of missile at various distances
# ("自機より右方向に離れている時はSL、DL" - missile right of tank).
cpu = fresh_cpu()
missile_x = 20 * 8
cases_right_of_tank = [
    (0, "Down"),                                    # dx=0
    (TANK_WIDTH, "Down"),                            # dx=32, boundary -> Down
    (TANK_WIDTH + 1, "DL"),                           # dx=33 -> diagonal
    (HORMING_SIDE_DIST - 1, "DL"),                    # dx=63 -> still diagonal
    (HORMING_SIDE_DIST, "SL"),                        # dx=64, boundary -> side
    (HORMING_SIDE_DIST + 40, "SL"),                   # dx=104 -> side
]
label_to_code = {"SL": 0, "DL": 1, "Down": 2, "DR": 3, "SR": 4}
for dx, expected in cases_right_of_tank:
    tank_x = missile_x - dx
    cpu.mem[TANK_X] = max(tank_x, 0)
    cpu.mem[HORMING_COL] = 20
    call_routine(cpu, "RESOLVE_HORMING_FACING")
    check(f"missile right of tank by {dx}px -> facing {expected}",
          cpu.mem[HORMING_FACING] == label_to_code[expected])

# missile to the LEFT of the tank ("左ならSR、DR").
cases_left_of_tank = [
    (0, "Down"),
    (TANK_WIDTH, "Down"),
    (TANK_WIDTH + 1, "DR"),
    (HORMING_SIDE_DIST - 1, "DR"),
    (HORMING_SIDE_DIST, "SR"),
    (HORMING_SIDE_DIST + 40, "SR"),
]
for dx, expected in cases_left_of_tank:
    tank_x = missile_x + dx
    cpu.mem[TANK_X] = min(tank_x, 255)
    cpu.mem[HORMING_COL] = 20
    call_routine(cpu, "RESOLVE_HORMING_FACING")
    check(f"missile left of tank by {dx}px -> facing {expected}",
          cpu.mem[HORMING_FACING] == label_to_code[expected])

# ---- movement deltas per facing ----
# missile at col10 (X=80), well clear of both screen edges, so every
# tank_x offset below stays a valid 0-255 byte.
cpu = fresh_cpu()
make_active(cpu, col=10, row=10, tank_x=10 * 8 + 100)   # tank far to the right -> missile left of tank -> SR
call_routine(cpu, "UPDATE_HORMING")
check("SR steps right, row unchanged", cpu.mem[HORMING_COL] == 11 and cpu.mem[HORMING_ROW] == 10)

cpu = fresh_cpu()
make_active(cpu, col=10, row=10, tank_x=10 * 8 - 70)   # tank far to the left -> missile right of tank -> SL
call_routine(cpu, "UPDATE_HORMING")
check("SL steps left, row unchanged", cpu.mem[HORMING_COL] == 9 and cpu.mem[HORMING_ROW] == 10)

cpu = fresh_cpu()
make_active(cpu, col=10, row=10, tank_x=10 * 8)   # directly below -> Down
cpu.mem[TANK_Y_CUR] = 200
call_routine(cpu, "UPDATE_HORMING")
check("Down steps down, col unchanged", cpu.mem[HORMING_COL] == 10 and cpu.mem[HORMING_ROW] == 11)

cpu = fresh_cpu()
make_active(cpu, col=10, row=10, tank_x=10 * 8 + 45)   # diagonal range, tank to the right -> DR
call_routine(cpu, "UPDATE_HORMING")
check("DR steps down-right", cpu.mem[HORMING_COL] == 11 and cpu.mem[HORMING_ROW] == 11)

cpu = fresh_cpu()
make_active(cpu, col=10, row=10, tank_x=10 * 8 - 45)   # diagonal range, tank to the left -> DL
call_routine(cpu, "UPDATE_HORMING")
check("DL steps down-left", cpu.mem[HORMING_COL] == 9 and cpu.mem[HORMING_ROW] == 11)

# ---- off-screen deactivation ----
# Facing SL at col0 (or SR at col31) can't be reached from a STATIC
# tank position within the valid 0-255 X range (the >=64px side
# threshold would need an impossible negative/>255 TANK_X at that
# exact column) - but IS reachable in real play if the tank moves
# rapidly away while the missile is mid-approach, so the underflow/
# overflow guard is real defensive code, not dead code. Tested here by
# calling the internal step label directly (bypassing RESOLVE_HORMING_
# FACING's own tank-position-derived resolve) with FACING pre-set,
# rather than constructing an impossible static TANK_X.
cpu = fresh_cpu()
cpu.mem[HORMING_ACT] = 1
cpu.mem[HORMING_PHASE] = 1
cpu.mem[HORMING_COL] = 0
cpu.mem[HORMING_ROW] = 10
cpu.mem[HORMING_FACING] = 0   # SL
call_routine(cpu, "UH_STEP_SL")
check("deactivates instead of underflowing off the left edge", cpu.mem[HORMING_ACT] == 0)

cpu = fresh_cpu()
cpu.mem[HORMING_ACT] = 1
cpu.mem[HORMING_PHASE] = 1
cpu.mem[HORMING_COL] = HORMING_MAXCOL
cpu.mem[HORMING_ROW] = 10
cpu.mem[HORMING_FACING] = 4   # SR
call_routine(cpu, "UH_STEP_SR")
check("deactivates instead of overflowing off the right edge", cpu.mem[HORMING_ACT] == 0)

cpu = fresh_cpu()
make_active(cpu, col=20, row=HORMING_MAXROW, tank_x=20 * 8)  # Down at the bottom row
cpu.mem[TANK_Y_CUR] = 200
call_routine(cpu, "UPDATE_HORMING")
check("deactivates instead of falling off the bottom of the screen", cpu.mem[HORMING_ACT] == 0)

# ---- tank collision ----
cpu = fresh_cpu()
make_active(cpu, col=20, row=10, tank_x=20 * 8)
cpu.mem[TANK_Y_CUR] = 10 * 8   # same row as the missile's own next step - guaranteed overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
life_before = cpu.mem[TANK_LIFE]
call_routine(cpu, "UPDATE_HORMING")
check("a real hit deactivates the missile", cpu.mem[HORMING_ACT] == 0)
check("a real hit decrements TANK_LIFE - APPLY_TANK_DAMAGE", cpu.mem[TANK_LIFE] == life_before - 1)
check("a real hit arms the tank's own hit-flash", cpu.mem[TANK_FLASH_TIMER] == FLASH_DURATION)

# a clear miss (tank far away) does NOT damage the tank
cpu = fresh_cpu()
make_active(cpu, col=20, row=10, tank_x=20 * 8)
cpu.mem[TANK_Y_CUR] = 200  # far below, no overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
call_routine(cpu, "UPDATE_HORMING")
check("no collision registers while the tank is far from the missile's own path",
      cpu.mem[TANK_LIFE] == TANK_LIFE_INIT and cpu.mem[HORMING_ACT] == 1)

# ---- real end-to-end: fire during a real pose, confirm it actually flies ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned_at = None
pose_entered_at = None
saw_horming_active = False
saw_horming_move = False
first_col = None
for f in range(3200):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and boss_spawned_at is None:
        boss_spawned_at = f
    if cpu.mem[BOSS_PHASE] == 1 and pose_entered_at is None:
        pose_entered_at = f
    if cpu.mem[HORMING_ACT] == 1:
        saw_horming_active = True
        if first_col is None:
            first_col = cpu.mem[HORMING_COL]
        elif cpu.mem[HORMING_COL] != first_col:
            saw_horming_move = True
    if pose_entered_at is not None and f - pose_entered_at > 80:
        break

check("real MAINLOOP: boss reaches the pose", pose_entered_at is not None)
check("real MAINLOOP: a real missile actually fires during the pose",
      saw_horming_active)
check("real MAINLOOP: the fired missile actually moves frame to frame",
      saw_horming_move)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
