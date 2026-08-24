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

HORMING_SLOT_COUNT = sym["HORMING_SLOT_COUNT"]
HORMING_SLOT_SIZE = sym["HORMING_SLOT_SIZE"]
HORMING_POOL = sym["HORMING_POOL"]
HORMING_SPRITE_ATTRS = sym["HORMING_SPRITE_ATTRS"]
HORMING_SPAWN_X = sym["HORMING_SPAWN_X"]
HORMING_SPAWN_Y = sym["HORMING_SPAWN_Y"]
HORMING_CENTER_X = sym["HORMING_CENTER_X"]
HORMING_SPEED = sym["HORMING_SPEED"]
TANK_WIDTH = sym["TANK_WIDTH"]
HORMING_SIDE_DIST = sym["HORMING_SIDE_DIST"]
HORMING_MAXX = sym["HORMING_MAXX"]
HORMING_MAXY = sym["HORMING_MAXY"]
HORMING_COLOR = sym["HORMING_COLOR"]
HORMING_SPR_BASE_SLOT = sym["HORMING_SPR_BASE_SLOT"]
PAT_HORMING_SL = sym["PAT_HORMING_SL"]
PAT_HORMING_DL = sym["PAT_HORMING_DL"]
PAT_HORMING_DOWN = sym["PAT_HORMING_DOWN"]
PAT_HORMING_DR = sym["PAT_HORMING_DR"]
PAT_HORMING_SR = sym["PAT_HORMING_SR"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_LIFE = sym["TANK_LIFE"]
TANK_LIFE_INIT = sym["TANK_LIFE_INIT"]
TANK_FLASH_TIMER = sym["TANK_FLASH_TIMER"]
FLASH_DURATION = sym["FLASH_DURATION"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_PHASE = sym["BOSS_PHASE"]
SPRATR = sym["SPRATR"]

PAT_CODE = [PAT_HORMING_SL, PAT_HORMING_DL, PAT_HORMING_DOWN, PAT_HORMING_DR, PAT_HORMING_SR]
label_to_code = {"SL": 0, "DL": 1, "Down": 2, "DR": 3, "SR": 4}

# slot layout: +0 ACT,+1 X,+2 Y,+3 FACING,+4 PHASE
def slot_addr(i):
    return HORMING_POOL + i * HORMING_SLOT_SIZE


def slot(cpu, i):
    base = slot_addr(i)
    return {
        "act": cpu.mem[base + 0],
        "x": cpu.mem[base + 1],
        "y": cpu.mem[base + 2],
        "facing": cpu.mem[base + 3],
        "phase": cpu.mem[base + 4],
    }


def sat_entry(cpu, hw_slot):
    # SPRATR is a VRAM address (the hw Sprite Attribute Table), not RAM -
    # FLUSH_HORMING_SPRITES writes it via VDP OUT ports, so it only shows
    # up in cpu.vram, same as HORMING_ADDR_LO/HI's old BG-cell reads did.
    base = SPRATR + hw_slot * 4
    return {
        "y": cpu.vram[base + 0],
        "x": cpu.vram[base + 1],
        "pat": cpu.vram[base + 2],
        "col": cpu.vram[base + 3],
    }


def make_active(cpu, slot_i, x, y, tank_x, phase=1):
    base = slot_addr(slot_i)
    cpu.mem[base + 0] = 1
    cpu.mem[base + 1] = x
    cpu.mem[base + 2] = y
    cpu.mem[base + 3] = 0
    cpu.mem[base + 4] = phase
    cpu.mem[TANK_X] = tank_x
    cpu.mem[TANK_Y_CUR] = 200  # far below by default - keeps height out of facing checks


# ---- FIRE_HORMING: fires a full volley of 4 ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_HORMING")
for i in range(HORMING_SLOT_COUNT):
    s = slot(cpu, i)
    check(f"slot{i} fires with ACT=1 - 同時に4発", s["act"] == 1)
    check(f"slot{i} fires with PHASE=0 (straight)", s["phase"] == 0)
    check(f"slot{i} fires facing SL(0)", s["facing"] == 0)
    check(f"slot{i} fires at HORMING_SPAWN_X - ボス右上あたり", s["x"] == HORMING_SPAWN_X)
    check(f"slot{i} spawn Y is staggered by 8px x slot index", s["y"] == HORMING_SPAWN_Y + i * 8)

# refuses to re-fire an already-active slot (drops the attempt, per slot)
x_before = [slot(cpu, i)["x"] for i in range(HORMING_SLOT_COUNT)]
call_routine(cpu, "FIRE_HORMING")
x_after = [slot(cpu, i)["x"] for i in range(HORMING_SLOT_COUNT)]
check("refuses to re-fire while all 4 slots are already active (drops the attempt)",
      x_before == x_after)

# a partially-drained pool only refills the inactive slots
cpu2 = fresh_cpu()
call_routine(cpu2, "FIRE_HORMING")
base1 = slot_addr(1)
cpu2.mem[base1 + 0] = 0  # slot1 deactivated (as if it hit or went off-screen)
cpu2.mem[base1 + 1] = 77
call_routine(cpu2, "FIRE_HORMING")
check("a re-fire only refills the inactive slot, leaving the other 3 untouched",
      cpu2.mem[base1 + 0] == 1 and cpu2.mem[base1 + 1] == HORMING_SPAWN_X)


# ---- phase0: straight left, HORMING_SPEED px/frame, always SL ----
cpu = fresh_cpu()
make_active(cpu, 0, x=200, y=64, tank_x=0, phase=0)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("steps left by HORMING_SPEED px/frame during phase0", s["x"] == 200 - HORMING_SPEED)
check("still facing SL during phase0", s["facing"] == 0)

# ---- phase transition at screen center ----
cpu = fresh_cpu()
make_active(cpu, 0, x=HORMING_CENTER_X + 1, y=64, tank_x=0, phase=0)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("still phase0 while 1px before center", s["phase"] == 0 and s["x"] == HORMING_CENTER_X + 1 - HORMING_SPEED)

cpu = fresh_cpu()
make_active(cpu, 0, x=HORMING_CENTER_X, y=64, tank_x=0, phase=0)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("phase flips to homing(1) once X reaches screen-center - X軸中央辺りまで水平打ち その後ホーミング動作",
      s["phase"] == 1)


# ---- RESOLVE_HORMING_FACING_IX bucket boundaries ----
# missile at X=160. Tank to the LEFT of missile at various distances
# ("自機より右方向に離れている時はSL、DL" - missile right of tank).
cpu = fresh_cpu()
missile_x = 160
cases_right_of_tank = [
    (0, "Down"),
    (TANK_WIDTH, "Down"),                      # dx=32, boundary -> Down
    (TANK_WIDTH + 1, "DL"),                    # dx=33 -> diagonal
    (HORMING_SIDE_DIST - 1, "DL"),             # dx=63 -> still diagonal
    (HORMING_SIDE_DIST, "SL"),                 # dx=64, boundary -> side
    (HORMING_SIDE_DIST + 40, "SL"),
]
for dx, expected in cases_right_of_tank:
    tank_x = missile_x - dx
    cpu.mem[TANK_X] = max(tank_x, 0)
    cpu.mem[slot_addr(0) + 1] = missile_x
    cpu.ix = slot_addr(0)
    call_routine(cpu, "RESOLVE_HORMING_FACING_IX")
    check(f"missile right of tank by {dx}px -> facing {expected}",
          cpu.mem[slot_addr(0) + 3] == label_to_code[expected])

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
    cpu.mem[slot_addr(0) + 1] = missile_x
    cpu.ix = slot_addr(0)
    call_routine(cpu, "RESOLVE_HORMING_FACING_IX")
    check(f"missile left of tank by {dx}px -> facing {expected}",
          cpu.mem[slot_addr(0) + 3] == label_to_code[expected])


# ---- movement deltas per facing (via UPDATE_ONE_HORMING, homing phase) ----
cpu = fresh_cpu()
make_active(cpu, 0, x=80, y=80, tank_x=80 + 100)  # tank far right -> missile left of tank -> SR
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("SR steps right, Y unchanged", s["x"] == 80 + HORMING_SPEED and s["y"] == 80)

cpu = fresh_cpu()
make_active(cpu, 0, x=80, y=80, tank_x=80 - 70)  # tank far left -> missile right of tank -> SL
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("SL steps left, Y unchanged", s["x"] == 80 - HORMING_SPEED and s["y"] == 80)

cpu = fresh_cpu()
make_active(cpu, 0, x=80, y=80, tank_x=80)  # directly below -> Down
cpu.mem[TANK_Y_CUR] = 200
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("Down steps down, X unchanged", s["x"] == 80 and s["y"] == 80 + HORMING_SPEED)

cpu = fresh_cpu()
make_active(cpu, 0, x=80, y=80, tank_x=80 + 45)  # diagonal range, tank right -> DR
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("DR steps down-right", s["x"] == 80 + HORMING_SPEED and s["y"] == 80 + HORMING_SPEED)

cpu = fresh_cpu()
make_active(cpu, 0, x=80, y=80, tank_x=80 - 45)  # diagonal range, tank left -> DL
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("DL steps down-left", s["x"] == 80 - HORMING_SPEED and s["y"] == 80 + HORMING_SPEED)


# ---- off-screen deactivation ----
# SL at a tiny X (or SR at HORMING_MAXX) can't be reached from a STATIC
# tank position within the valid 0-255 X range (the >=64px side
# threshold would need an impossible negative/>255 TANK_X at that exact
# X) - but IS reachable in real play if the tank moves rapidly away
# while the missile is mid-approach, so the underflow/overflow guard is
# real defensive code, not dead code. Tested here by calling the
# internal step label directly (bypassing RESOLVE_HORMING_FACING_IX's
# own tank-position-derived resolve) with FACING irrelevant to the step
# itself, same approach the prior (BG-based) round's test used.
cpu = fresh_cpu()
make_active(cpu, 0, x=HORMING_SPEED - 1, y=80, tank_x=0, phase=1)
cpu.ix = slot_addr(0)
call_routine(cpu, "UOH_STEP_SL")
check("deactivates instead of underflowing off the left edge", cpu.mem[slot_addr(0) + 0] == 0)

cpu = fresh_cpu()
make_active(cpu, 0, x=HORMING_MAXX, y=80, tank_x=0, phase=1)
cpu.ix = slot_addr(0)
call_routine(cpu, "UOH_STEP_SR")
check("deactivates instead of overflowing off the right edge", cpu.mem[slot_addr(0) + 0] == 0)

cpu = fresh_cpu()
make_active(cpu, 0, x=100, y=HORMING_MAXY, tank_x=100)  # Down at the bottom
cpu.mem[TANK_Y_CUR] = 200
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("deactivates instead of falling off the bottom of the screen", cpu.mem[slot_addr(0) + 0] == 0)


# ---- tank collision ----
cpu = fresh_cpu()
make_active(cpu, 0, x=100, y=80, tank_x=100)
cpu.mem[TANK_Y_CUR] = 80  # same row as the missile's own next step - guaranteed overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
life_before = cpu.mem[TANK_LIFE]
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("a real hit deactivates the missile", cpu.mem[slot_addr(0) + 0] == 0)
check("a real hit decrements TANK_LIFE - APPLY_TANK_DAMAGE", cpu.mem[TANK_LIFE] == life_before - 1)
check("a real hit arms the tank's own hit-flash", cpu.mem[TANK_FLASH_TIMER] == FLASH_DURATION)

# a clear miss (tank far away) does NOT damage the tank
cpu = fresh_cpu()
make_active(cpu, 0, x=100, y=80, tank_x=100)
cpu.mem[TANK_Y_CUR] = 200  # far below, no overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("no collision registers while the tank is far from the missile's own path",
      cpu.mem[TANK_LIFE] == TANK_LIFE_INIT and cpu.mem[slot_addr(0) + 0] == 1)


# ---- UPDATE_HORMING_ALL: staging + hw sprite flush ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_HORMING")
call_routine(cpu, "UPDATE_HORMING_ALL")
for i in range(HORMING_SLOT_COUNT):
    s = slot(cpu, i)
    sat = sat_entry(cpu, HORMING_SPR_BASE_SLOT + i)
    check(f"slot{i} SAT Y matches the pool after UPDATE_HORMING_ALL", sat["y"] == s["y"])
    check(f"slot{i} SAT X matches the pool after UPDATE_HORMING_ALL", sat["x"] == s["x"])
    check(f"slot{i} SAT pattern matches PAT_HORMING_SL (facing 0 at spawn)", sat["pat"] == PAT_HORMING_SL)
    check(f"slot{i} SAT color is HORMING_COLOR (gray, matches the uploaded sprites)", sat["col"] == HORMING_COLOR)

# an inactive slot is hidden (Y=209) in the SAT, not left stale
cpu2 = fresh_cpu()
call_routine(cpu2, "FIRE_HORMING")
cpu2.mem[slot_addr(2) + 0] = 0
call_routine(cpu2, "UPDATE_HORMING_ALL")
check("a deactivated slot is hidden (Y=209) in the SAT",
      sat_entry(cpu2, HORMING_SPR_BASE_SLOT + 2)["y"] == 209)

# pattern code follows FACING through RESOLVE_HORMING_PATTERN_IX
cpu3 = fresh_cpu()
call_routine(cpu3, "FIRE_HORMING")
for i, pat in enumerate(PAT_CODE):
    cpu3.mem[slot_addr(0) + 3] = i
    cpu3.ix = slot_addr(0)
    call_routine(cpu3, "RESOLVE_HORMING_PATTERN_IX")
    check(f"RESOLVE_HORMING_PATTERN_IX returns the right pattern for facing {i}", cpu3.a == pat)


# ---- real end-to-end: fire during a real pose, confirm a volley actually flies ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
pose_entered_at = None
saw_4_active = False
saw_move = False
first_x = [None] * HORMING_SLOT_COUNT
for f in range(3200):
    step_frame(cpu)
    if cpu.mem[BOSS_PHASE] == 1 and pose_entered_at is None:
        pose_entered_at = f
    active_count = sum(1 for i in range(HORMING_SLOT_COUNT) if cpu.mem[slot_addr(i) + 0] == 1)
    if active_count == HORMING_SLOT_COUNT:
        saw_4_active = True
    for i in range(HORMING_SLOT_COUNT):
        if cpu.mem[slot_addr(i) + 0] == 1:
            x = cpu.mem[slot_addr(i) + 1]
            if first_x[i] is None:
                first_x[i] = x
            elif x != first_x[i]:
                saw_move = True
    if pose_entered_at is not None and f - pose_entered_at > 80:
        break

check("real MAINLOOP: boss reaches the pose", pose_entered_at is not None)
check("real MAINLOOP: a real volley of 4 missiles actually fires during the pose - 同時に4発",
      saw_4_active)
check("real MAINLOOP: fired missiles actually move frame to frame",
      saw_move)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
