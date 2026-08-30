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

BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_HP = sym["BOSS_HP"]
BOSS_HP_INIT = sym["BOSS_HP_INIT"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_FORM_SPARK = sym["BOSS_FORM_SPARK"]
BOSS_FORM_ACTIVE = sym["BOSS_FORM_ACTIVE"]
BOSS_BROKEN_HP_THRESHOLD = sym["BOSS_BROKEN_HP_THRESHOLD"]
BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
BOSS_EXPL_STATE_SPARK = sym["BOSS_EXPL_STATE_SPARK"]
BOSS_EXPL_STATE_GROW = sym["BOSS_EXPL_STATE_GROW"]
BOSS_EXPL_STATE_DONE = sym["BOSS_EXPL_STATE_DONE"]
BOSS_EXPL_REASON = sym["BOSS_EXPL_REASON"]
BOSS_EXPL_SPARK_DURATION = sym["BOSS_EXPL_SPARK_DURATION"]
BOSS_EXPL_CX = sym["BOSS_EXPL_CX"]
BOSS_EXPL_CY = sym["BOSS_EXPL_CY"]
BOSS_BROKEN_SPRITE_ATTRS = sym["BOSS_BROKEN_SPRITE_ATTRS"]
BOSS_BROKEN_SPR_BASE_SLOT = sym["BOSS_BROKEN_SPR_BASE_SLOT"]
BOSS_BROKEN_QUAD_COUNT = sym["BOSS_BROKEN_QUAD_COUNT"]
BOSS_BROKEN_DIR = sym["BOSS_BROKEN_DIR"]
BOSS_BROKEN_MOVING = sym["BOSS_BROKEN_MOVING"]
BOSS_BROKEN_PATH_INDEX = sym["BOSS_BROKEN_PATH_INDEX"]
BOSS_BROKEN_FRAME_COUNTER = sym["BOSS_BROKEN_FRAME_COUNTER"]
BOSS_BROKEN_PHASE_END_TICK = sym["BOSS_BROKEN_PHASE_END_TICK"]
BOSS_BROKEN_PATH_HOLD_FRAMES = sym["BOSS_BROKEN_PATH_HOLD_FRAMES"]
BOSS_BROKEN_PATH_LEN = sym["BOSS_BROKEN_PATH_LEN"]
BOSS_BROKEN_PATH_X = sym["BOSS_BROKEN_PATH_X"]
BOSS_BROKEN_PATH_Y = sym["BOSS_BROKEN_PATH_Y"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
PAT_SASAPI = sym["PAT_SASAPI"]
BOSS_COLOR = sym["BOSS_COLOR"]
BOSS_POSE_COUNT = sym["BOSS_POSE_COUNT"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
SBEAM_ACT = sym["SBEAM_ACT"]
HORMING_VOLLEY_COUNT = sym["HORMING_VOLLEY_COUNT"]
GAME_TICK = sym["GAME_TICK"]
BULLET0_ACT = sym["BULLET0_ACT"]

SAT_BASE = 0x1B00


def make_boss(cpu, x=100, hp=BOSS_HP_INIT, phase=0):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_HP] = hp
    cpu.mem[BOSS_PHASE] = phase
    cpu.mem[BOSS_FORM] = 0


def make_bullet(cpu, col, row, active=1):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = active
    cpu.mem[ix + 1] = 0
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    row_addr = 0x1800 + row * 32
    cpu.mem[ix + 4] = row_addr & 0xFF
    cpu.mem[ix + 5] = (row_addr >> 8) & 0xFF
    cpu.mem[ix + 6] = 0
    cpu.ix = ix


def hit_boss(cpu, x):
    boss_row = BOSS_SPAWN_Y // 8
    make_bullet(cpu, col=x // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")


check("BOSS_BROKEN_HP_THRESHOLD is 50 (corrected mid-round from an initial 200 misreading)",
      BOSS_BROKEN_HP_THRESHOLD == 50)
check("BOSS_BROKEN_QUAD_COUNT is 4 (32x32 = 2x2 quadrants, vs the old body's 16)",
      BOSS_BROKEN_QUAD_COUNT == 4)
check("BOSS_BROKEN_PATH_LEN is a power of 2 (the asm side ANDs GAME_TICK/an index against LEN-1)",
      BOSS_BROKEN_PATH_LEN & (BOSS_BROKEN_PATH_LEN - 1) == 0)

# ---- trigger: "ボス耐久値が50になったら" - HP reaching the threshold
# ITSELF triggers (inclusive: CP THRESHOLD+1 in CHECK_HIT_PAIR_BOSS - see
# its own comment), not just strictly below it. ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 2)
hit_boss(cpu, 100)
check("HP still strictly above the threshold after this hit does NOT trigger the form change",
      cpu.mem[BOSS_HP] == BOSS_BROKEN_HP_THRESHOLD + 1 and cpu.mem[BOSS_FORM] == 0)

cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 2)
hit_boss(cpu, 100)  # HP -> threshold+1, still form 0 (checked above)
hit_boss(cpu, 100)  # HP -> threshold exactly - inclusive, this is the trigger
check("HP reaching the threshold exactly (inclusive) arms the SPARK transition (BOSS_FORM=SPARK)",
      cpu.mem[BOSS_HP] == BOSS_BROKEN_HP_THRESHOLD and cpu.mem[BOSS_FORM] == BOSS_FORM_SPARK)
check("the boss stays ACT=1 (alive) through the transition, not ACT=2 (real death)",
      cpu.mem[BOSS_ACT] == 1)
check("BOSS_EXPL_STATE is armed to SPARK, reusing the same sub-state machine a real death uses",
      cpu.mem[BOSS_EXPL_STATE] == BOSS_EXPL_STATE_SPARK)
check("BOSS_EXPL_REASON=1 distinguishes this from a real death (0) - see UBS_LAST_FRAME's own branch",
      cpu.mem[BOSS_EXPL_REASON] == 1)

# ---- no re-trigger on further hits while already broken ----
hp_after_trigger = cpu.mem[BOSS_HP]
form_after_trigger = cpu.mem[BOSS_FORM]
hit_boss(cpu, 100)
check("a further hit still decrements HP normally", cpu.mem[BOSS_HP] == hp_after_trigger - 1)
check("a further hit does not re-arm/reset the transition (BOSS_FORM unchanged)",
      cpu.mem[BOSS_FORM] == form_after_trigger)

# ---- interrupting a mid-pose boss: hand art erased, BOSS_PHASE forced
# back to 0 (round36-14's own "即座に強制停止" - wherever UBA_ACTIVE was,
# this cuts in immediately) ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 1, phase=1)
call_routine(cpu, "DRAW_SASAPI_HAND")  # actually draw it so ERASE_SASAPI_HAND has something real to undo
hit_boss(cpu, 100)
hit_boss(cpu, 100)
check("triggering mid-pose (BOSS_PHASE=1) resets BOSS_PHASE back to 0",
      cpu.mem[BOSS_PHASE] == 0)

# ---- the SPARK burst runs for exactly BOSS_EXPL_SPARK_DURATION frames,
# then reveals the broken form ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 2)
hit_boss(cpu, 100)
hit_boss(cpu, 100)  # triggers - BOSS_FORM=SPARK
cpu.mem[sym["BOSS_FLASH_TIMER"]] = 0  # isolate the reveal's own color from the triggering hit's own flash
for _ in range(BOSS_EXPL_SPARK_DURATION - 1):
    call_routine(cpu, "UPDATE_BOSS_ALL")
check("still SPARK 1 frame before the burst's own duration elapses",
      cpu.mem[BOSS_FORM] == BOSS_FORM_SPARK)
call_routine(cpu, "UPDATE_BOSS_ALL")  # the final frame - UBS_LAST_FRAME fires this call
check("BOSS_FORM becomes ACTIVE the instant the SPARK burst's own duration elapses",
      cpu.mem[BOSS_FORM] == BOSS_FORM_ACTIVE)
check("the shared explosion state machine is retired (DONE), not left mid-GROW",
      cpu.mem[BOSS_EXPL_STATE] == BOSS_EXPL_STATE_DONE)

# the old 64x64 body's own hw sprite slots are hidden for good - except
# the 4 leading ones (10-13), which the broken body immediately reuses
# and redraws with real coordinates the instant it's revealed (see
# BOSS_BROKEN_SPR_BASE_SLOT's own comment - that's the whole point of
# reusing them, not a bug). The remaining 12 (14-25), genuinely retired,
# stay hidden. Both in the live SAT AND in the OLD body's own staging
# buffer (BOSS_SPRITE_ATTRS) - a later real death's own UBE_GROW blink
# flushes that staging buffer again, and it must not resurrect the old
# body (round36-14 follow-up fix, see REVEAL_BOSS_BROKEN_FORM's own
# comment).
all_sat_hidden = all(cpu.vram[SAT_BASE + (BOSS_SPR_BASE_SLOT + i) * 4] == 209 for i in range(4, 16))
check("the old body's own genuinely-retired 12 hw sprite slots (14-25, not the 4 reused by the "
      "broken body) are hidden (Y=209) in the live SAT",
      all_sat_hidden)
all_stage_hidden = all(cpu.mem[BOSS_SPRITE_ATTRS + i * 4] == 209 for i in range(16))
check("all 16 of the old body's own quadrants are ALSO stomped to Y=209 in their own staging buffer "
      "(BOSS_SPRITE_ATTRS) - not just the live SAT",
      all_stage_hidden)

# the new 4-quadrant broken body is drawn into slots 10-13 with a
# plausible pattern/color the instant it's revealed.
broken_slot_ys = [cpu.vram[SAT_BASE + (BOSS_BROKEN_SPR_BASE_SLOT + i) * 4] for i in range(4)]
check("the new broken body's own 4 quadrants are NOT hidden (real Y coordinates, not 209)",
      all(y != 209 for y in broken_slot_ys))
broken_slot_pats = [cpu.vram[SAT_BASE + (BOSS_BROKEN_SPR_BASE_SLOT + i) * 4 + 2] for i in range(4)]
check("the broken body's 4 quadrants use PAT_SASAPI's own first 4 pattern groups (0,4,8,12 deltas)",
      broken_slot_pats == [PAT_SASAPI + 0, PAT_SASAPI + 4, PAT_SASAPI + 8, PAT_SASAPI + 12])
broken_slot_cols = [cpu.vram[SAT_BASE + (BOSS_BROKEN_SPR_BASE_SLOT + i) * 4 + 3] for i in range(4)]
check("the broken body draws in BOSS_COLOR (no flash active right at reveal)",
      all(c == BOSS_COLOR for c in broken_slot_cols))

# ---- movement: BOSS_X/BOSS_Y follow the precomputed path LUT, one step
# every BOSS_BROKEN_PATH_HOLD_FRAMES calls while MOVING (BOSS_BROKEN_
# FRAME_COUNTER-driven, independent of the global GAME_TICK not being
# advanced by these direct UPDATE_BOSS_ALL calls) ----
check("starts already MOVING (round36-14: '起動で画面を移動' - not parked at reveal)",
      cpu.mem[BOSS_BROKEN_MOVING] == 1)
check("BOSS_X at reveal matches the path LUT's own index-0 entry",
      cpu.mem[BOSS_X] == cpu.mem[BOSS_BROKEN_PATH_X + 0])
check("BOSS_Y at reveal matches the path LUT's own index-0 entry",
      cpu.mem[BOSS_Y] == cpu.mem[BOSS_BROKEN_PATH_Y + 0])

# self-consistency over many frames, rather than hand-predicting an
# exact call count (fragile against exactly how many "extra" internal
# update calls a reveal/trigger happens to make) - every frame, BOSS_X/
# BOSS_Y must equal path[BOSS_BROKEN_PATH_INDEX] exactly, and whenever
# the index itself changes it must advance by exactly 1 (wrapping at
# BOSS_BROKEN_PATH_LEN), never skip or jump.
prev_index = cpu.mem[BOSS_BROKEN_PATH_INDEX]
consistent = True
advances = 0
for _ in range(3 * BOSS_BROKEN_PATH_HOLD_FRAMES):
    call_routine(cpu, "UPDATE_BOSS_ALL")
    idx = cpu.mem[BOSS_BROKEN_PATH_INDEX]
    if (cpu.mem[BOSS_X] != cpu.mem[BOSS_BROKEN_PATH_X + idx]
            or cpu.mem[BOSS_Y] != cpu.mem[BOSS_BROKEN_PATH_Y + idx]):
        consistent = False
    if idx != prev_index:
        advances += 1
        if idx != (prev_index + 1) % BOSS_BROKEN_PATH_LEN:
            consistent = False
    prev_index = idx
check("BOSS_X/BOSS_Y always match path[BOSS_BROKEN_PATH_INDEX] exactly, every single frame "
      f"across {3 * BOSS_BROKEN_PATH_HOLD_FRAMES} frames",
      consistent)
check("the path index actually advances (not stuck) while MOVING, by exactly 1 step at a time",
      advances >= 2)


# ---- real end-to-end: spawn, drain to the threshold, confirm the
# transition, and confirm the moving/stopped cycle genuinely repeats
# (not a one-shot freeze) over real MAINLOOP frames ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned_at = None
for f in range(20000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and boss_spawned_at is None:
        boss_spawned_at = f
    if boss_spawned_at is not None and f - boss_spawned_at > 5:
        break
check("real MAINLOOP: boss spawns before the drain-to-threshold test",
      cpu.mem[BOSS_ACT] == 1)

boss_x = cpu.mem[BOSS_X]
boss_row = BOSS_SPAWN_Y // 8
# stop 1 hit short of the (inclusive) threshold, so the "still form 0"
# check below is genuinely testing "not yet", not "already there".
while cpu.mem[BOSS_HP] > BOSS_BROKEN_HP_THRESHOLD + 1:
    make_bullet(cpu, col=boss_x // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("real boss: repeated hits drive HP down to 1 above the threshold",
      cpu.mem[BOSS_HP] == BOSS_BROKEN_HP_THRESHOLD + 1)
check("real boss: BOSS_FORM is still 0 one hit before the threshold",
      cpu.mem[BOSS_FORM] == 0)
make_bullet(cpu, col=boss_x // 8 + 1, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("real boss: the hit that reaches the threshold exactly (inclusive) triggers the transition",
      cpu.mem[BOSS_HP] == BOSS_BROKEN_HP_THRESHOLD and cpu.mem[BOSS_FORM] == BOSS_FORM_SPARK)
pose_count_at_trigger = cpu.mem[BOSS_POSE_COUNT]
horming_count_at_trigger = cpu.mem[HORMING_VOLLEY_COUNT]

# call_routine leaves cpu.pc at its own return sentinel - reset to
# MAINLOOP's own top before driving more real frames via step_frame.
cpu.pc = sym["MAINLOOP"]

saw_moving = False
saw_stopped = False
saw_active_form = False
for f in range(6000):
    step_frame(cpu)
    if cpu.mem[BOSS_FORM] == BOSS_FORM_ACTIVE:
        saw_active_form = True
        if cpu.mem[BOSS_BROKEN_MOVING]:
            saw_moving = True
        else:
            saw_stopped = True
    if saw_moving and saw_stopped:
        break
check("real MAINLOOP: the SPARK burst really does complete and reveal the broken form (BOSS_FORM=ACTIVE)",
      saw_active_form)
check("real MAINLOOP: the broken form is observed MOVING at some point",
      saw_moving)
check("real MAINLOOP: the broken form is observed STOPPED at some point too - "
      "'ランダムタイミングで停止し 少ししてまた回る' is a repeating cycle, not a one-shot freeze",
      saw_stopped)

check("real MAINLOOP: no new attack pose ever completes again after the transition "
      "(BOSS_POSE_COUNT frozen - UBA_ACTIVE, the only thing that ever touches it, never runs again)",
      cpu.mem[BOSS_POSE_COUNT] == pose_count_at_trigger)
check("real MAINLOOP: no new Horming volley is ever armed again (HORMING_VOLLEY_COUNT frozen)",
      cpu.mem[HORMING_VOLLEY_COUNT] == horming_count_at_trigger)
check("real MAINLOOP: SBeam never fires again after the transition (SBEAM_ACT stays 0)",
      cpu.mem[SBEAM_ACT] == 0)


# ---- HP reaching 0 while already in the broken form still plays "the
# final explosion" ("で、0で最後の爆発で") - CHECK_HIT_PAIR_BOSS's own
# JR Z,CHPBOSS_DESTROY is completely unaffected by BOSS_FORM ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=1)
cpu.mem[BOSS_FORM] = BOSS_FORM_ACTIVE  # simulate "already in broken form" without a full real drain
hit_boss(cpu, 100)
check("HP reaching 0 while already in the broken form still destroys the boss (BOSS_ACT=2)",
      cpu.mem[BOSS_ACT] == 2)
check("HP reaching 0 while in the broken form still arms the real SPARK->GROW->... sequence "
      "(BOSS_EXPL_STATE=SPARK, not left at broken form's own retired DONE)",
      cpu.mem[BOSS_EXPL_STATE] == BOSS_EXPL_STATE_SPARK)
check("BOSS_EXPL_REASON=0 for this real death, even though a broken-form transition (REASON=1) "
      "may have run earlier in the same fight",
      cpu.mem[BOSS_EXPL_REASON] == 0)
check("the death sequence's own center-cell capture uses the BROKEN body's +16 offset "
      "(32x32), not the old body's +32 (64x64) - CX",
      cpu.mem[BOSS_EXPL_CX] == ((100 + 16) >> 3))
check("...and CY too", cpu.mem[BOSS_EXPL_CY] == ((BOSS_SPAWN_Y + 16) >> 3))

# a normal (non-broken) death still uses the old +32 offset, unaffected
# by this round's change.
cpu2 = fresh_cpu()
make_boss(cpu2, x=100, hp=1)
hit_boss(cpu2, 100)
check("a normal (BOSS_FORM=0) death still uses the ORIGINAL +32 (64x64) center offset - CX",
      cpu2.mem[BOSS_EXPL_CX] == ((100 + 32) >> 3))
check("...and CY too", cpu2.mem[BOSS_EXPL_CY] == ((BOSS_SPAWN_Y + 32) >> 3))

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
