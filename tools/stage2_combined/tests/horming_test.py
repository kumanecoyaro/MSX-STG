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
HORMING_WANDER_WIDTH = sym["HORMING_WANDER_WIDTH"]
HORMING_MAXX = sym["HORMING_MAXX"]
HORMING_HOMING_Y_OFFSET = sym["HORMING_HOMING_Y_OFFSET"]
TANK_WIDTH = sym["TANK_WIDTH"]
HORMING_SIDE_DIST = sym["HORMING_SIDE_DIST"]
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
GAME_RNG = sym["GAME_RNG"]
TICK = sym["TICK"]
FLYER_POOL = sym["FLYER_POOL"]
FLYER_SLOT_SIZE = sym["FLYER_SLOT_SIZE"]
FLYER_SLOT_COUNT = sym["FLYER_SLOT_COUNT"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]

PAT_CODE = [PAT_HORMING_SL, PAT_HORMING_DL, PAT_HORMING_DOWN, PAT_HORMING_DR, PAT_HORMING_SR]

# slot layout: +0 ACT,+1 X,+2 Y,+3 FACING(cosmetic,eased),+4 STATE(0=rise,1=wander,2=homing),+5 RISE_REMAIN,+6 TARGET_X
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
        "target_x": cpu.mem[base + 6],
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


def make_slot(cpu, slot_i, x, y, facing=0, state=2, rise_remain=0, target_x=0, tank_x=None, tank_y=None):
    base = slot_addr(slot_i)
    cpu.mem[base + 0] = 1
    cpu.mem[base + 1] = x
    cpu.mem[base + 2] = y
    cpu.mem[base + 3] = facing
    cpu.mem[base + 4] = state
    cpu.mem[base + 5] = rise_remain
    cpu.mem[base + 6] = target_x
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
check("fires facing SL(0) (cosmetic - no true upward sprite; confirmed correct as-is by the user)", s["facing"] == 0)
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

# drive it through the whole rise - transitions to state1 (wander) once
# RISE_REMAIN reaches 0, having moved exactly HORMING_RISE_DIST total
# (round6: HORMING_RISE_DIST doesn't necessarily divide evenly by
# HORMING_SPEED any more - a final PARTIAL step covers whatever's left,
# so this drives enough steps for that to complete rather than assuming
# floor(RISE_DIST/SPEED) lands exactly on state1)
cpu = fresh_cpu()
make_slot(cpu, 0, x=200, y=100, facing=0, state=0, rise_remain=HORMING_RISE_DIST)
cpu.ix = slot_addr(0)
steps = -(-HORMING_RISE_DIST // HORMING_SPEED)  # ceil division
for _ in range(steps):
    call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1 (wander) reached after ceil(HORMING_RISE_DIST/HORMING_SPEED) steps",
      s["state"] == 1)
check("total X displacement over the rise is exactly HORMING_RISE_DIST",
      s["x"] == 200 - HORMING_RISE_DIST)
check("total Y displacement over the rise is exactly HORMING_RISE_DIST",
      s["y"] == 100 - HORMING_RISE_DIST)
check("a TARGET_X inside the window is picked exactly on the rise->wander transition",
      HORMING_WANDER_MIN_X <= s["target_x"] <= HORMING_WANDER_MAX_X)


# ---- PICK_HORMING_TARGET_X: always lands in range, and actually varies ----
cpu = fresh_cpu()
seen = set()
for i in range(40):
    cpu.mem[GAME_RNG] = (cpu.mem[GAME_RNG] + 37) & 0xFF  # simulate different accumulated entropy
    cpu.mem[TICK] = i & 0xFF
    cpu.mem[slot_addr(0) + 2] = (i * 13) & 0xFF  # vary the per-slot Y mixed in too
    cpu.ix = slot_addr(0)
    call_routine(cpu, "PICK_HORMING_TARGET_X")
    tx = cpu.mem[slot_addr(0) + 6]
    check(f"PICK_HORMING_TARGET_X({i}) lands inside [MIN,MAX]",
          HORMING_WANDER_MIN_X <= tx <= HORMING_WANDER_MAX_X)
    seen.add(tx)
check("PICK_HORMING_TARGET_X actually varies across different inputs, not stuck on one value - "
      "お前は1度もまともにランダム扱えてないな",
      len(seen) >= 15)

# a pure read - never mutates GAME_RNG itself (unlike every existing
# GAME_RNG consumer's own "INC A:LD(GAME_RNG),A" idiom, which is the
# root cause this round traces the "fixed"-looking wander back to)
cpu = fresh_cpu()
cpu.mem[GAME_RNG] = 123
cpu.ix = slot_addr(0)
call_routine(cpu, "PICK_HORMING_TARGET_X")
check("PICK_HORMING_TARGET_X does not mutate GAME_RNG (pure read)", cpu.mem[GAME_RNG] == 123)


# ---- state1 (wander): moves straight toward the one-shot TARGET_X, Y frozen ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=150, y=42, facing=2, state=1, target_x=100)  # target is to the left
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1 steps toward TARGET_X (target left -> steps left)", s["x"] == 150 - HORMING_SPEED)
check("state1 never changes Y - 水平移動 is literal", s["y"] == 42)
check("state1 stays in state1 while short of the target", s["state"] == 1)

cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=42, facing=2, state=1, target_x=150)  # target is to the right
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1 steps toward TARGET_X (target right -> steps right)", s["x"] == 100 + HORMING_SPEED)
check("state1 never changes Y (target-right case too)", s["y"] == 42)

# the instant X reaches TARGET_X, switches to state2 (2D pursuit) -
# "指定した範囲のランダムX位置まで水平移動後ホーミング". round5: the
# arrival frame itself now ALSO performs one forced DL step - "ホーミ
# ング開始直後は左斜下に1回だけ必ず移動 自機が右にいた場合に急激な曲
# がりを防ぐため" - so X/Y both move by HORMING_SPEED on this exact
# frame, not held in place.
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=42, facing=2, state=1, target_x=100)  # already exactly at the target
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state1->state2 transition happens the instant X reaches TARGET_X", s["state"] == 2)
check("the arrival frame's own forced DL step moves X left by HORMING_SPEED", s["x"] == 100 - HORMING_SPEED)
check("the arrival frame's own forced DL step moves Y down by HORMING_SPEED", s["y"] == 42 + HORMING_SPEED)
check("the arrival frame's own forced step shows facing DL(1) immediately, not eased", s["facing"] == 1)

# real bug caught by inspecting a rendered frame, not the unit tests:
# an ODD TARGET_X can never be reached by a missile that only ever moves
# in HORMING_SPEED-px, always-even-parity steps - a plain "step by
# HORMING_SPEED, check for exact equality" loop would oscillate 1px
# short/over forever, stuck in state1 permanently. Verify the actual
# snap-when-within-range fix: a 1px gap (well under HORMING_SPEED) lands
# exactly on the target (before the arrival frame's own forced DL step
# then moves it 1 more HORMING_SPEED from there), from both sides.
cpu = fresh_cpu()
make_slot(cpu, 0, x=101, y=42, facing=2, state=1, target_x=100)  # 1px right of an odd-parity-mismatched target
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("a sub-HORMING_SPEED gap (missile right of target) snaps onto TARGET_X then takes the forced DL step",
      s["x"] == 100 - HORMING_SPEED)
check("and transitions to state2 on that same snap frame (odd-parity target reachable at all)",
      s["state"] == 2)

cpu = fresh_cpu()
make_slot(cpu, 0, x=99, y=42, facing=2, state=1, target_x=100)  # 1px left of the target
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("a sub-HORMING_SPEED gap (missile left of target) also snaps onto TARGET_X then takes the forced DL step",
      s["x"] == 100 - HORMING_SPEED)
check("and transitions to state2 on that same snap frame (left-side case too)",
      s["state"] == 2)

# a gap of exactly HORMING_SPEED (even-parity, the common case) still
# lands exactly on the target and transitions, same as before this fix
cpu = fresh_cpu()
make_slot(cpu, 0, x=100 + HORMING_SPEED, y=42, facing=2, state=1, target_x=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("a gap of exactly HORMING_SPEED lands on the target, then the forced DL step moves on from there",
      s["x"] == 100 - HORMING_SPEED and s["state"] == 2)
check("Y moves by the forced DL step's own HORMING_SPEED on the arrival frame", s["y"] == 42 + HORMING_SPEED)

# the 45-degree-max-turn rule still applies during state1 (DL/DR steps
# ease in, not snap) - "で方向を変える時は45度まで"
cpu = fresh_cpu()
make_slot(cpu, 0, x=150, y=42, facing=3, state=1, target_x=100)  # was DR(3), now stepping left (desired DL=1)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("facing eases by only 1 step (DR->Down) even though the desired facing is DL",
      slot(cpu, 0)["facing"] == 2)

# the left-edge underflow guard in UOH_WANDER's own "step left" branch
# is genuinely unreachable now (not just unlikely): it only runs when
# distance=missile_X-target_X > HORMING_SPEED, and since target_X can
# never be negative, that already forces missile_X > HORMING_SPEED at
# that point - the "CP HORMING_SPEED: JP C,UOH_DEACTIVATE" it guards
# can never see missile_X<HORMING_SPEED there. Kept as harmless
# defensive code (matches this file's general style), not tested here
# since no valid byte inputs can exercise it - unlike the round-3
# version of this same guard, which the coin-flip wander COULD reach.

# off-screen bail-out on the right edge still applies (target_X can, in
# principle, be poked past HORMING_MAXX by something other than
# PICK_HORMING_TARGET_X's own clamped draw, so this one stays a real
# defensive check, not dead code).
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_MAXX, y=42, facing=3, state=1, target_x=255)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state1 deactivates instead of overflowing off the right edge", slot(cpu, 0)["act"] == 0)


# ---- RESOLVE_HORMING_FACING_IX bucket boundaries (restored round4 -
# state2 is real 2D pursuit again, using the ORIGINAL 5-way classifier
# from the very first spec message) ----
cpu = fresh_cpu()
missile_x = 160
label_to_code = {"SL": 0, "DL": 1, "Down": 2, "DR": 3, "SR": 4}
cases_right_of_tank = [
    (0, "Down"),
    (32, "Down"),      # TANK_WIDTH, boundary -> Down
    (33, "DL"),        # diagonal
    (63, "DL"),
    (64, "SL"),        # HORMING_SIDE_DIST, boundary -> side
    (104, "SL"),
]
for dx, expected in cases_right_of_tank:
    cpu.mem[TANK_X] = max(missile_x - dx, 0)
    cpu.mem[slot_addr(0) + 1] = missile_x
    cpu.ix = slot_addr(0)
    call_routine(cpu, "RESOLVE_HORMING_FACING_IX")
    check(f"missile right of tank by {dx}px -> facing {expected}",
          cpu.mem[slot_addr(0) + 3] == label_to_code[expected])

cases_left_of_tank = [
    (0, "Down"),
    (32, "Down"),
    (33, "DR"),
    (63, "DR"),
    (64, "SR"),
    (104, "SR"),
]
for dx, expected in cases_left_of_tank:
    cpu.mem[TANK_X] = min(missile_x + dx, 255)
    cpu.mem[slot_addr(0) + 1] = missile_x
    cpu.ix = slot_addr(0)
    call_routine(cpu, "RESOLVE_HORMING_FACING_IX")
    check(f"missile left of tank by {dx}px -> facing {expected}",
          cpu.mem[slot_addr(0) + 3] == label_to_code[expected])


# ---- state2 (2D pursuit/descend): real 2D movement toward the tank ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=80, y=80, facing=2, state=2, tank_x=80 + 100, tank_y=200)  # tank far right -> SR
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 SR steps right, Y unchanged", s["x"] == 80 + HORMING_SPEED and s["y"] == 80)

cpu = fresh_cpu()
make_slot(cpu, 0, x=80, y=80, facing=2, state=2, tank_x=80 - 70, tank_y=200)  # tank far left -> SL
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 SL steps left, Y unchanged", s["x"] == 80 - HORMING_SPEED and s["y"] == 80)

cpu = fresh_cpu()
make_slot(cpu, 0, x=80, y=80, facing=2, state=2, tank_x=80, tank_y=200)  # directly below -> Down
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 Down steps down, X unchanged", s["x"] == 80 and s["y"] == 80 + HORMING_SPEED)

cpu = fresh_cpu()
make_slot(cpu, 0, x=80, y=80, facing=2, state=2, tank_x=80 + 45, tank_y=200)  # diagonal, tank right -> DR
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 DR steps down-right (real 2D pursuit)", s["x"] == 80 + HORMING_SPEED and s["y"] == 80 + HORMING_SPEED)

cpu = fresh_cpu()
make_slot(cpu, 0, x=80, y=80, facing=2, state=2, tank_x=80 - 45, tank_y=200)  # diagonal, tank left -> DL
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state2 DL steps down-left (real 2D pursuit)", s["x"] == 80 - HORMING_SPEED and s["y"] == 80 + HORMING_SPEED)

# off-screen bail-out on the right edge - not reachable through
# UPDATE_ONE_HORMING with a real TANK_X (RESOLVE_HORMING_FACING_IX
# would just reclassify to Down once dx<TANK_WIDTH, and TANK_X can't
# exceed 255 to force a genuine SR facing way out at HORMING_MAXX), so
# tested by calling the internal step label directly, same "construct
# the state manually" approach already used elsewhere in this file for
# guards a static setup can't organically reach.
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_MAXX, y=80, facing=4, state=2)
cpu.ix = slot_addr(0)
call_routine(cpu, "UOH_H2_STEP_SR")
check("state2 deactivates instead of overflowing off the right edge", slot(cpu, 0)["act"] == 0)

# round5: state2's own Y-moving branches no longer bail out at all -
# "仮に飛び越えた場合消えなくなるんで" - even deep near the bottom of
# the screen, a Down step just keeps moving (UOH_H2_TRIGGER, not a
# MAXY guard, is what ends vertical movement).
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=180, facing=2, state=2, tank_x=100, tank_y=255)  # Down, deep near the bottom
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state2 no longer deactivates from a Down step near the bottom of the screen",
      slot(cpu, 0)["act"] == 1)

# --- state2->state3 trigger: missile_Y >= TANK_Y_CUR+HORMING_HOMING_Y_OFFSET
# (not TANK_Y_CUR itself) - "自機狙い水平移動の位置を8pxさげてくれ 水平
# 打ちで撃ち落とせる高さ" ---
cpu = fresh_cpu()
# directly below the tank (Down facing) so Y is the only thing moving;
# one step short of the threshold - should stay in state2
make_slot(cpu, 0, x=100, y=100 + HORMING_HOMING_Y_OFFSET - HORMING_SPEED - 1, facing=2, state=2,
          tank_x=100, tank_y=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("stays in state2 while missile_Y is still below TANK_Y_CUR+HORMING_HOMING_Y_OFFSET",
      slot(cpu, 0)["state"] == 2)

cpu = fresh_cpu()
# exactly at the threshold minus HORMING_SPEED -> this step lands
# exactly on (or past) the threshold -> should trigger state3
make_slot(cpu, 0, x=100, y=100 + HORMING_HOMING_Y_OFFSET - HORMING_SPEED, facing=2, state=2,
          tank_x=100, tank_y=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("switches to state3 (locked horizontal) once missile_Y >= TANK_Y_CUR+HORMING_HOMING_Y_OFFSET",
      s["state"] == 3)
check("Y is NOT re-snapped to the exact threshold - keeps whatever this frame's own step produced",
      s["y"] == 100 + HORMING_HOMING_Y_OFFSET)


# ---- state3 (locked horizontal): purely horizontal, Y frozen ----
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=1, state=3, tank_x=100 + 50)  # tank to the right
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state3 steps toward the tank's X (tank right -> moves right)", s["x"] == 100 + HORMING_SPEED)
check("state3 never changes Y - 水平に自機へホーミング", s["y"] == 90)

cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=3, state=3, tank_x=100 - 50)  # tank to the left
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state3 steps toward the tank's X (tank left -> moves left)", s["x"] == 100 - HORMING_SPEED)
check("state3 never changes Y (tank-left case too)", s["y"] == 90)

# once aligned, holds position and facing rather than oscillating
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=90, facing=0, state=3, tank_x=100)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
s = slot(cpu, 0)
check("state3 holds X once aligned with the tank, no overshoot/oscillation", s["x"] == 100)
check("state3 holds facing once aligned", s["facing"] == 0)

# off-screen bail-outs still apply in state3
cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_SPEED - 1, y=90, facing=0, state=3, tank_x=0)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state3 deactivates instead of underflowing off the left edge", slot(cpu, 0)["act"] == 0)

cpu = fresh_cpu()
make_slot(cpu, 0, x=HORMING_MAXX, y=90, facing=4, state=3, tank_x=255)
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("state3 deactivates instead of overflowing off the right edge", slot(cpu, 0)["act"] == 0)


# ---- tank collision (applies in every state) ----
# tank's own real hitbox is TANK_COLLISION_WIDTH/_HEIGHT (16x16) offset by
# TANK_COLLISION_Y_OFFSET from TANK_Y_CUR, not the full 32x32 sprite box -
# TANK_Y_CUR itself must be set so the box actually overlaps the missile.
TANK_COLLISION_Y_OFFSET = sym["TANK_COLLISION_Y_OFFSET"]
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=80, facing=0, state=3, tank_x=100)
cpu.mem[TANK_Y_CUR] = 80 - TANK_COLLISION_Y_OFFSET  # box top lands exactly on the missile's own row
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
life_before = cpu.mem[TANK_LIFE]
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("a real hit deactivates the missile", slot(cpu, 0)["act"] == 0)
check("a real hit decrements TANK_LIFE - APPLY_TANK_DAMAGE", cpu.mem[TANK_LIFE] == life_before - 1)
check("a real hit arms the tank's own hit-flash", cpu.mem[TANK_FLASH_TIMER] == FLASH_DURATION)

# a clear miss (tank far away) does NOT damage the tank
cpu = fresh_cpu()
make_slot(cpu, 0, x=100, y=80, facing=0, state=3, tank_x=100)
cpu.mem[TANK_Y_CUR] = 200  # far below, no overlap
cpu.mem[TANK_LIFE] = TANK_LIFE_INIT
cpu.ix = slot_addr(0)
call_routine(cpu, "UPDATE_ONE_HORMING")
check("no collision registers while the tank is far from the missile's own path",
      cpu.mem[TANK_LIFE] == TANK_LIFE_INIT and slot(cpu, 0)["act"] == 1)


# ---- CHECK_BULLET_VS_HORMING: shootdown - "今はミサイルに判定がない
# がショットで撃ち落とせるように" ----
BULLET0_ACT = sym["BULLET0_ACT"]
SCORE = sym["SCORE"]

def make_bullet(cpu, act=1, is_u=0, col=10, row=10):
    cpu.mem[BULLET0_ACT + 0] = act
    cpu.mem[BULLET0_ACT + 1] = is_u
    cpu.mem[BULLET0_ACT + 2] = col
    cpu.mem[BULLET0_ACT + 3] = row

cpu = fresh_cpu()
make_bullet(cpu, act=1, col=10, row=10)      # pixel (80,80)
make_slot(cpu, 0, x=80, y=80, facing=0, state=2)  # same pixel box - guaranteed overlap
call_routine(cpu, "CHECK_BULLET_VS_HORMING")
check("a bullet hit deactivates the missile - 撃ち落とせる", slot(cpu, 0)["act"] == 0)
check("a bullet hit also consumes the bullet itself", cpu.mem[BULLET0_ACT + 0] == 0)

cpu = fresh_cpu()
make_bullet(cpu, act=1, col=10, row=10)      # pixel (80,80)
make_slot(cpu, 0, x=200, y=150, facing=0, state=2)  # far away - clean miss
call_routine(cpu, "CHECK_BULLET_VS_HORMING")
check("a clear miss leaves both the bullet and the missile untouched",
      cpu.mem[BULLET0_ACT + 0] == 1 and slot(cpu, 0)["act"] == 1)

cpu = fresh_cpu()
make_bullet(cpu, act=0, col=10, row=10)      # inactive bullet
make_slot(cpu, 0, x=80, y=80, facing=0, state=2)
call_routine(cpu, "CHECK_BULLET_VS_HORMING")
check("an inactive bullet never registers a hit", slot(cpu, 0)["act"] == 1)


# ---- UPDATE_HORMING_ALL: staging + hw sprite flush ----
# (BOSS_ACT must be 1 - UPDATE_HORMING_ALL is now a no-op otherwise, see
# the dedicated BOSS_ACT=0 check further below)
cpu = fresh_cpu()
cpu.mem[BOSS_ACT] = 1
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
cpu2.mem[BOSS_ACT] = 1
call_routine(cpu2, "FIRE_ONE_HORMING")
cpu2.mem[slot_addr(0) + 0] = 0
call_routine(cpu2, "UPDATE_HORMING_ALL")
check("a deactivated slot is hidden (Y=209) in the SAT",
      sat_entry(cpu2, HORMING_SPR_BASE_SLOT + 0)["y"] == 209)

# UPDATE_HORMING_ALL is a no-op (doesn't touch VRAM at all) before the
# boss exists - round-4 fix for the same class of bug as the boss's own
# quadrant corruption: ZacoII/BulletU genuinely still need hw sprite
# slots6-9 before BOSS_ACT!=0.
cpu3 = fresh_cpu()
before = [cpu3.vram[SPRATR + (HORMING_SPR_BASE_SLOT + i) * 4] for i in range(4)]
cpu3.mem[BOSS_ACT] = 0
call_routine(cpu3, "UPDATE_HORMING_ALL")
after = [cpu3.vram[SPRATR + (HORMING_SPR_BASE_SLOT + i) * 4] for i in range(4)]
check("UPDATE_HORMING_ALL touches nothing in the SAT while BOSS_ACT=0 - ZacoII/BulletU still own those slots",
      before == after)

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


# ---- round-4 regression check: the boss's own body is never hidden by
# the missile system while patrolling as a hw sprite (the actual root
# cause of "ボス上部が常に表示欠けしている") ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned = False
saw_pose = False
saw_patrol_after_pose = False
boss_quadrant_hidden_while_patrolling = False
# BOSS_SPAWN_TICK(999)*8=7992 raw frames alone, now that GAME_TICK boots
# at a real 0 ("でTick0に" - the old 840 fast-iteration diagnostic boot
# is gone) - plus real patrol/pose time on top, so these budgets are all
# well above the old ones that assumed the 840 head start.
for f in range(12000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1:
        boss_spawned = True
    if boss_spawned and cpu.mem[BOSS_PHASE] == 1:
        saw_pose = True
    if boss_spawned and saw_pose and cpu.mem[BOSS_PHASE] == 0:
        saw_patrol_after_pose = True
        if cpu.vram[SPRATR + BOSS_SPR_BASE_SLOT * 4] == 209:
            boss_quadrant_hidden_while_patrolling = True
            break
    if saw_patrol_after_pose:
        break

check("real MAINLOOP: boss spawns, poses, and resumes patrol", boss_spawned and saw_pose and saw_patrol_after_pose)
check("real MAINLOOP: the boss's own top quadrant is NOT hidden by the missile flush while patrolling - "
      "ボス上部が常に表示欠けしている(fixed)",
      not boss_quadrant_hidden_while_patrolling)

# and Flyer's own pattern block is never overwritten while a real Flyer
# is still alive - confirms the "オールフリー" timing this reuse relies
# on (same as BOSS_SPR_BASE_SLOT/PAT_SASAPI's own precedent) actually
# holds in real play, not just in theory.
cpu2 = fresh_cpu()
cpu2.sim_dir = 0
cpu2.sim_trig_a = False
cpu2.sim_trig_b = False
prev_boss_act = 0
flyer_alive_at_boss_spawn = None
for f in range(9000):
    step_frame(cpu2)
    if cpu2.mem[BOSS_ACT] == 1 and prev_boss_act == 0:
        flyer_alive_at_boss_spawn = any(
            cpu2.mem[FLYER_POOL + i * FLYER_SLOT_SIZE + 0] != 0 for i in range(FLYER_SLOT_COUNT)
        )
        break
    prev_boss_act = cpu2.mem[BOSS_ACT]
check("real MAINLOOP: no live Flyer exists at the exact moment the boss spawns - "
      "safe to overwrite its pattern block (何を流用したんだ)",
      flyer_alive_at_boss_spawn is False)


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
saw_state3 = False
target_xs = []
life_before_sweep = cpu.mem[TANK_LIFE]
prev_active = [0] * HORMING_SLOT_COUNT
prev_state = [0] * HORMING_SLOT_COUNT
for f in range(12000):
    step_frame(cpu)
    if cpu.mem[BOSS_PHASE] == 1 and pose_entered_at is None:
        pose_entered_at = f
    if pose_entered_at is not None and pose_ended_at is None and cpu.mem[BOSS_PHASE] == 0:
        pose_ended_at = f
    for i in range(HORMING_SLOT_COUNT):
        act = cpu.mem[slot_addr(i) + 0]
        # only the FIRST volley's own 4 launches/targets count toward the
        # "exactly 4"/"not all identical" checks below - the sweep itself
        # is allowed to run into a 2nd volley (round10: the boss's own
        # left-edge pause shifts GAME_RNG's accumulated value at fire-
        # time, so which TARGET_X a given volley's missiles happen to
        # wander to - and therefore whether they reach state3 before
        # colliding with the stationary test tank - is no longer the
        # same outcome it used to be; a 2nd volley gives state3 another
        # real chance without weakening the "exactly 4" per-volley check)
        if act == 1 and prev_active[i] == 0 and len(launch_frames) < HORMING_SLOT_COUNT:
            launch_frames.append(f)
        prev_active[i] = act
        if act == 1:
            st = cpu.mem[slot_addr(i) + 4]
            if st == 1:
                saw_state1 = True
                if prev_state[i] == 0 and len(target_xs) < HORMING_SLOT_COUNT:
                    target_xs.append(cpu.mem[slot_addr(i) + 6])
            elif st == 2:
                saw_state2 = True
            elif st == 3:
                saw_state3 = True
            prev_state[i] = st
    if saw_state3 and pose_ended_at is not None and f - pose_ended_at > 20:
        break
    if pose_ended_at is not None and f - pose_ended_at > 2000:
        break

check("real MAINLOOP: boss reaches the pose", pose_entered_at is not None)
check("real MAINLOOP: exactly 4 missiles launch in total across the pose",
      len(launch_frames) == HORMING_SLOT_COUNT)
check("real MAINLOOP: the 4 launches are spread out over time, not simultaneous - 間欠で4発発射",
      len(launch_frames) < 2 or (max(launch_frames) - min(launch_frames)) >= HORMING_VOLLEY_INTERVAL)
check("real MAINLOOP: a real missile reaches state1 (wander)", saw_state1)
check("real MAINLOOP: a real missile reaches state2 (2D pursuit)", saw_state2)
check("real MAINLOOP: a real missile reaches state3 (locked horizontal)", saw_state3)
check("real MAINLOOP: the 4 missiles' own TARGET_X picks are not all identical - genuinely random",
      len(target_xs) < 2 or len(set(target_xs)) >= 2)
check("real MAINLOOP: the full rise->wander->2D-pursuit->locked-horizontal arc actually lands a hit "
      "(TANK_LIFE decreased) - the stationary test tank never dodges",
      cpu.mem[TANK_LIFE] < life_before_sweep)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
