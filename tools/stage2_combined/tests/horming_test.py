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
HORMING_VOLLEY_COUNT = sym["HORMING_VOLLEY_COUNT"]
HORMING_VOLLEY_TIMER = sym["HORMING_VOLLEY_TIMER"]
HORMING_VOLLEY_INTERVAL = sym["HORMING_VOLLEY_INTERVAL"]
HORMING_SPAWN_X = sym["HORMING_SPAWN_X"]
HORMING_SPAWN_Y = sym["HORMING_SPAWN_Y"]
HORMING_SPEED = sym["HORMING_SPEED"]
HORMING_RISE_DIST = sym["HORMING_RISE_DIST"]
HORMING_WANDER_MIN_X = sym["HORMING_WANDER_MIN_X"]
HORMING_WANDER_MAX_X = sym["HORMING_WANDER_MAX_X"]
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

# slot layout: +0 ACT,+1 X,+2 Y,+3 FACING(cosmetic,eased),+4 STATE(0=rise,1=wander,2=homing),+5 RISE_REMAIN
def slot_addr(i):
    return HORMING_POOL + i * HORMING_SLOT_SIZE


def slot(cpu, i):
    base = slot_addr(i)
    return {
        "act": cpu.mem[base + 0],
        "x": cpu.mem[base + 1],
        "y": cpu.mem[base + 2],
        "facing": cpu.mem[base + 3],
        "state": cpu.mem[base + 4],
        "rise_remain": cpu.mem[base + 5],
    }


def sat_entry(cpu, hw_slot):
    # SPRATR is a VRAM address (the hw Sprite Attribute Table), not RAM -
    # FLUSH_HORMING_SPRITES writes it via VDP OUT ports.
    base = SPRATR + hw_slot * 4
    return {
        "y": cpu.vram[base + 0],
        "x": cpu.vram[base + 1],
        "pat": cpu.vram[base + 2],
        "col": cpu.vram[base + 3],
    }


def make_slot(cpu, slot_i, x, y, facing=0, state=2, rise_remain=0, tank_x=None, tank_y=None):
    base = slot_addr(slot_i)
    cpu.mem[base + 0] = 1
    cpu.mem[base + 1] = x
    cpu.mem[base + 2] = y
    cpu.mem[base + 3] = facing
    cpu.mem[base + 4] = state
    cpu.mem[base + 5] = rise_remain
    if tank_x is not None:
        cpu.mem[TANK_X] = tank_x
    if tank_y is not None:
        cpu.mem[TANK_Y_CUR] = tank_y


# ---- FIRE_ONE_HORMING: spawns into the first inactive slot ----
cpu = fresh_cpu()
cpu.ix = 0  # unused by this routine, just to be explicit nothing stale leaks in
call_routine(cpu, "FIRE_ONE_HORMING")
s = slot(cpu, 0)
check("fires into slot0 with ACT=1", s["act"] == 1)
check("fires at HORMING_SPAWN_X/Y - ボスに被らない位置の右上", s["x"] == HORMING_SPAWN_X and s["y"] == HORMING_SPAWN_Y)
check("fires facing SL(0) (cosmetic - no true upward sprite)", s["facing"] == 0)
check("fires in state0 (rise)", s["state"] == 0)
check("fires with the full HORMING_RISE_DIST still to travel", s["rise_remain"] == HORMING_RISE_DIST)
for i in range(1, HORMING_SLOT_COUNT):
    check(f"slot{i} untouched by a single FIRE_ONE_HORMING call", slot(cpu, i)["act"] == 0)

# a second call fills slot1, leaving slot0 alone
call_routine(cpu, "FIRE_ONE_HORMING")
check("a second call fires into the next free slot (slot1), not slot0 again",
      slot(cpu, 1)["act"] == 1 and slot(cpu, 0)["x"] == HORMING_SPAWN_X)

# once all 4 slots are full, drops the attempt
cpu2 = fresh_cpu()
for i in range(HORMING_SLOT_COUNT):
    call_routine(cpu2, "FIRE_ONE_HORMING")
for i in range(HORMING_SLOT_COUNT):
    check(f"slot{i} active after filling the whole pool", slot(cpu2, i)["act"] == 1)
call_routine(cpu2, "FIRE_ONE_HORMING")  # pool full - should be a no-op
check("drops the attempt once the whole pool is full (no crash, no state corruption)",
      all(slot(cpu2, i)["act"] == 1 for i in range(HORMING_SLOT_COUNT)))


# ---- ARM_HORMING_VOLLEY / UPDATE_HORMING_VOLLEY: intermittent fire ----
# "弾は4発同時発射ではなく間欠で4発発射"
cpu = fresh_cpu()
call_routine(cpu, "ARM_HORMING_VOLLEY")
check("ARM resets the launch counter to 0", cpu.mem[HORMING_VOLLEY_COUNT] == 0)
check("ARM resets the timer to 0 (fires the first shot on the very next check)",
      cpu.mem[HORMING_VOLLEY_TIMER] == 0)

# does NOT fire all 4 at once - only 1 launches on the first tick
call_routine(cpu, "UPDATE_HORMING_VOLLEY")
active_count = sum(1 for i in range(HORMING_SLOT_COUNT) if slot(cpu, i)["act"] == 1)
check("the first UPDATE_HORMING_VOLLEY tick launches exactly 1 missile, not 4 - 間欠で4発発射",
      active_count == 1)
check("HORMING_VOLLEY_COUNT is now 1", cpu.mem[HORMING_VOLLEY_COUNT] == 1)
check("the timer is reset to HORMING_VOLLEY_INTERVAL after a launch",
      cpu.mem[HORMING_VOLLEY_TIMER] == HORMING_VOLLEY_INTERVAL)

# ticking again before the interval elapses does NOT fire another
call_routine(cpu, "UPDATE_HORMING_VOLLEY")
active_count = sum(1 for i in range(HORMING_SLOT_COUNT) if slot(cpu, i)["act"] == 1)
check("still only 1 active right after the interval-reset tick (timer hasn't reached 0 yet)",
      active_count == 1)

# tick through the whole interval - a 2nd missile launches right on
# schedule. The "ticking again" call above already consumed 1 of the
# INTERVAL decrements (timer went INTERVAL->INTERVAL-1); it takes
# INTERVAL more calls from there for the timer to count down through 0
# AND be read as 0 on a following call (the decrement that reaches 0
# doesn't itself fire - the NEXT call, seeing 0, does).
for _ in range(HORMING_VOLLEY_INTERVAL):
    call_routine(cpu, "UPDATE_HORMING_VOLLEY")
active_count = sum(1 for i in range(HORMING_SLOT_COUNT) if slot(cpu, i)["act"] == 1)
check("a 2nd missile launches exactly HORMING_VOLLEY_INTERVAL ticks after the 1st",
      active_count == 2)

# drive it all the way through - exactly 4 launch total, never more
cpu2 = fresh_cpu()
call_routine(cpu2, "ARM_HORMING_VOLLEY")
for _ in range(HORMING_VOLLEY_INTERVAL * 6):
    call_routine(cpu2, "UPDATE_HORMING_VOLLEY")
active_count = sum(1 for i in range(HORMING_SLOT_COUNT) if slot(cpu2, i)["act"] == 1)
check("exactly 4 launch in total over enough ticks, never more than the pool size",
      active_count == HORMING_SLOT_COUNT)


# ---- state0 (rise): diagonal up-left, exactly HORMING_RISE_DIST total ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=200, y=100, facing=0, state=0, rise_remain=HORMING_RISE_DIST)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state0 steps left by HORMING_SPEED - 最初は左斜上に32px移動", s["x"] == 200 - HORMING_SPEED)
check("state0 steps up by HORMING_SPEED (same frame, diagonal)", s["y"] == 100 - HORMING_SPEED)
check("state0 counts RISE_REMAIN down by HORMING_SPEED", s["rise_remain"] == HORMING_RISE_DIST - HORMING_SPEED)
check("still state0 (rise) with distance left to travel", s["state"] == 0)
check("facing stays SL(0) throughout state0 (cosmetic)", s["facing"] == 0)

# drive it through the whole rise - transitions to state1 (wander) exactly
# when RISE_REMAIN reaches 0, having moved exactly HORMING_RISE_DIST total
cpu = fresh_cpu()
make_slot(cpu, 0, x=200, y=100, facing=0, state=0, rise_remain=HORMING_RISE_DIST)
cpu.ix = slot_addr(0)
steps = HORMING_RISE_DIST // HORMING_SPEED
for _ in range(steps):
    call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1 (wander) reached after exactly HORMING_RISE_DIST/HORMING_SPEED steps",
      s["state"] == 1)
check("total X displacement over the rise is exactly HORMING_RISE_DIST",
      s["x"] == 200 - HORMING_RISE_DIST)
check("total Y displacement over the rise is exactly HORMING_RISE_DIST",
      s["y"] == 100 - HORMING_RISE_DIST)


# ---- state1 (wander): random horizontal within the window, continuous descent ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=(HORMING_WANDER_MIN_X + HORMING_WANDER_MAX_X) // 2, y=20, facing=2, state=1)
cpu.mem[TANK_Y_CUR] = 200  # keep the trigger far away for this check
cpu.ix = slot_addr(0)
x_before = slot(cpu, 0)["x"]
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1 moves X by exactly HORMING_SPEED (either direction), never stands still",
      abs(s["x"] - x_before) == HORMING_SPEED)
check("state1 keeps descending by HORMING_SPEED/frame - Y is 20+speed",
      s["y"] == 20 + HORMING_SPEED)
check("state1's own eased facing is DL or DR (never SL/Down/SR) - matches a diagonal step",
      s["facing"] in (1, 3))

# forced back inside the window when below HORMING_WANDER_MIN_X
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_WANDER_MIN_X, y=20, facing=2, state=1, tank_y=200)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("forced rightward when at/below HORMING_WANDER_MIN_X - stays inside the window",
      slot(cpu, 0)["x"] == HORMING_WANDER_MIN_X + HORMING_SPEED)

# forced back inside the window when at/above HORMING_WANDER_MAX_X
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_WANDER_MAX_X, y=20, facing=2, state=1, tank_y=200)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("forced leftward when at/above HORMING_WANDER_MAX_X - stays inside the window",
      slot(cpu, 0)["x"] == HORMING_WANDER_MAX_X - HORMING_SPEED)

# the 45-degree-max-turn rule: facing eases by only 1 step per call, even
# if the desired facing keeps flipping between DL(1) and DR(3) - "で方向
# を変える時は45度まで"
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_WANDER_MIN_X + 20, y=20, facing=1, state=1, tank_y=200)  # starts at DL
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("facing never jumps more than 1 step even toward the opposite (DR) desired direction",
      abs(s["facing"] - 1) <= 1)

# state2 trigger: once missile_Y >= TANK_Y_CUR, switches to homing -
# "自機のY位置以上で一致したら水平に自機へホーミング"
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=100 - HORMING_SPEED, facing=2, state=1, tank_y=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("switches to state2 (homing) the instant missile_Y reaches TANK_Y_CUR",
      slot(cpu, 0)["state"] == 2)

cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=50, facing=2, state=1, tank_y=200)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("stays in state1 while missile_Y is still well above TANK_Y_CUR",
      slot(cpu, 0)["state"] == 1)

# off-screen bottom bail-out during the wander's own descent
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=HORMING_MAXY, facing=2, state=1, tank_y=255)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state1 deactivates instead of falling off the bottom of the screen",
      slot(cpu, 0)["act"] == 0)


# ---- state2 (homing): purely horizontal, Y frozen ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=1, state=2, tank_x=100 + 50)  # tank to the right
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 steps toward the tank's X (tank right -> moves right)", s["x"] == 100 + HORMING_SPEED)
check("state2 never changes Y - 水平に自機へホーミング", s["y"] == 90)

cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=3, state=2, tank_x=100 - 50)  # tank to the left
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 steps toward the tank's X (tank left -> moves left)", s["x"] == 100 - HORMING_SPEED)
check("state2 never changes Y (tank-left case too)", s["y"] == 90)

# once aligned, holds position and facing rather than oscillating
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=0, state=2, tank_x=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 holds X once aligned with the tank, no overshoot/oscillation", s["x"] == 100)
check("state2 holds facing once aligned", s["facing"] == 0)

# the 45-degree easing also applies at the state1->state2 handoff (DL/DR
# -> SL/SR is exactly 1 step, so it should complete in a single call)
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=1, state=2, tank_x=100 + 50)  # was DL(1), tank now demands SR(4)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("facing eases by only 1 step toward SR even though DL->SR would be a 3-step jump",
      slot(cpu, 0)["facing"] == 2)  # DL(1) -> Down(2), one step closer to SR(4)

# off-screen bail-outs still apply in state2
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_SPEED - 1, y=90, facing=0, state=2, tank_x=0)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state2 deactivates instead of underflowing off the left edge", slot(cpu, 0)["act"] == 0)

cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_MAXX, y=90, facing=4, state=2, tank_x=255)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state2 deactivates instead of overflowing off the right edge", slot(cpu, 0)["act"] == 0)


# ---- tank collision (applies in every state) ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=80, facing=0, state=2, tank_x=100)
cpu.mem[TANK_Y_CUR] = 80  # same row - guaranteed overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
life_before = cpu.mem[TANK_LIFE]
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("a real hit deactivates the missile", slot(cpu, 0)["act"] == 0)
check("a real hit decrements TANK_LIFE - APPLY_TANK_DAMAGE", cpu.mem[TANK_LIFE] == life_before - 1)
check("a real hit arms the tank's own hit-flash", cpu.mem[TANK_FLASH_TIMER] == FLASH_DURATION)

# a clear miss (tank far away) does NOT damage the tank
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=80, facing=0, state=2, tank_x=100)
cpu.mem[TANK_Y_CUR] = 200  # far below, no overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("no collision registers while the tank is far from the missile's own path",
      cpu.mem[TANK_LIFE] == TANK_LIFE_INIT and slot(cpu, 0)["act"] == 1)


# ---- UPDATE_HORMING_ALL: staging + hw sprite flush ----
cpu = fresh_cpu()
call_routine(cpu, "FIRE_ONE_HORMING")
call_routine(cpu, "UPDATE_HORMING_ALL")
s = slot(cpu, 0)
sat = sat_entry(cpu, HORMING_SPR_BASE_SLOT + 0)
check("slot0 SAT Y matches the pool after UPDATE_HORMING_ALL", sat["y"] == s["y"])
check("slot0 SAT X matches the pool after UPDATE_HORMING_ALL", sat["x"] == s["x"])
check("slot0 SAT pattern matches PAT_HORMING_SL (facing 0 at spawn)", sat["pat"] == PAT_HORMING_SL)
check("slot0 SAT color is HORMING_COLOR (gray, matches the uploaded sprites)", sat["col"] == HORMING_COLOR)
for i in range(1, HORMING_SLOT_COUNT):
    check(f"slot{i} (never fired) is hidden (Y=209) in the SAT",
          sat_entry(cpu, HORMING_SPR_BASE_SLOT + i)["y"] == 209)

# an inactive slot is hidden (Y=209) in the SAT, not left stale
cpu2 = fresh_cpu()
call_routine(cpu2, "FIRE_ONE_HORMING")
cpu2.mem[slot_addr(0) + 0] = 0
call_routine(cpu2, "UPDATE_HORMING_ALL")
check("a deactivated slot is hidden (Y=209) in the SAT",
      sat_entry(cpu2, HORMING_SPR_BASE_SLOT + 0)["y"] == 209)

# pattern code follows FACING through RESOLVE_HORMING_PATTERN_IX
cpu3 = fresh_cpu()
call_routine(cpu3, "FIRE_ONE_HORMING")
for i, pat in enumerate(PAT_CODE):
    cpu3.mem[slot_addr(0) + 3] = i
    cpu3.ix = slot_addr(0)
    call_routine(cpu3, "RESOLVE_HORMING_PATTERN_IX")
    check(f"RESOLVE_HORMING_PATTERN_IX returns the right pattern for facing {i}", cpu3.a == pat)


# ---- EASE_HORMING_FACING_IX: standalone 45-degree-max-turn checks ----
cpu = fresh_cpu()
cases = [
    (0, 4, 1),   # SL -> desired SR: eases only to DL(1), not straight to SR
    (4, 0, 3),   # SR -> desired SL: eases only to DR(3)
    (2, 2, 2),   # already at desired: no change
    (1, 3, 2),   # DL -> desired DR: eases to Down(2), one step
]
for start, desired, expected in cases:
    cpu.mem[slot_addr(0) + 3] = start
    cpu.ix = slot_addr(0)
    cpu.b = desired
    call_routine(cpu, "EASE_HORMING_FACING_IX")
    check(f"EASE_HORMING_FACING_IX({start}->{desired}) yields {expected}, not a direct jump",
          cpu.mem[slot_addr(0) + 3] == expected)


# ---- real end-to-end: fire during a real pose, confirm intermittent volley + full flight arc ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
pose_entered_at = None
pose_ended_at = None
launch_frames = []
saw_state1 = False
saw_state2 = False
prev_active = [0] * HORMING_SLOT_COUNT
for f in range(4000):
    step_frame(cpu)
    if cpu.mem[BOSS_PHASE] == 1 and pose_entered_at is None:
        pose_entered_at = f
    if pose_entered_at is not None and pose_ended_at is None and cpu.mem[BOSS_PHASE] == 0:
        pose_ended_at = f
    for i in range(HORMING_SLOT_COUNT):
        act = cpu.mem[slot_addr(i) + 0]
        if act == 1 and prev_active[i] == 0:
            launch_frames.append(f)
        prev_active[i] = act
        if act == 1:
            st = cpu.mem[slot_addr(i) + 4]
            if st == 1:
                saw_state1 = True
            elif st == 2:
                saw_state2 = True
    # stop shortly after THIS pose ends (not a fixed frame budget) so a
    # second patrol/pose cycle can't sneak a 5th launch into the count.
    if pose_ended_at is not None and f - pose_ended_at > 20:
        break

check("real MAINLOOP: boss reaches the pose", pose_entered_at is not None)
check("real MAINLOOP: exactly 4 missiles launch in total across the pose",
      len(launch_frames) == HORMING_SLOT_COUNT)
check("real MAINLOOP: the 4 launches are spread out over time, not simultaneous - 間欠で4発発射",
      len(launch_frames) < 2 or (max(launch_frames) - min(launch_frames)) >= HORMING_VOLLEY_INTERVAL)
check("real MAINLOOP: a real missile reaches state1 (wander)", saw_state1)
check("real MAINLOOP: a real missile reaches state2 (homing)", saw_state2)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
