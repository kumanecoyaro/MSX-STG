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
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_HP = sym["BOSS_HP"]
BOSS_HP_INIT = sym["BOSS_HP_INIT"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_FORM_SPARK = sym["BOSS_FORM_SPARK"]
BOSS_FORM_ACTIVE = sym["BOSS_FORM_ACTIVE"]
BOSS_BROKEN_HP_THRESHOLD = sym["BOSS_BROKEN_HP_THRESHOLD"]
BOSS_COLLISION_SIZE = sym["BOSS_COLLISION_SIZE"]
BOSS_BROKEN_COLLISION_SIZE = sym["BOSS_BROKEN_COLLISION_SIZE"]
BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
BOSS_EXPL_STATE_SPARK = sym["BOSS_EXPL_STATE_SPARK"]
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
BOSS_BROKEN_RECENTERING = sym["BOSS_BROKEN_RECENTERING"]
BOSS_BROKEN_RECENTER_SPEED = sym["BOSS_BROKEN_RECENTER_SPEED"]
BOSS_BROKEN_CENTER_X = sym["BOSS_BROKEN_CENTER_X"]
BOSS_BROKEN_CENTER_Y = sym["BOSS_BROKEN_CENTER_Y"]
BOSS_BROKEN_PATH_CROSS_INDEX = sym["BOSS_BROKEN_PATH_CROSS_INDEX"]
BOSS_BROKEN_PATH_INDEX = sym["BOSS_BROKEN_PATH_INDEX"]
BOSS_BROKEN_FRAME_COUNTER = sym["BOSS_BROKEN_FRAME_COUNTER"]
BOSS_BROKEN_STEPS_TO_STOP = sym["BOSS_BROKEN_STEPS_TO_STOP"]
BOSS_BROKEN_LAP_STEPS_MIN = sym["BOSS_BROKEN_LAP_STEPS_MIN"]
BOSS_BROKEN_LAP_STEPS_RANGE = sym["BOSS_BROKEN_LAP_STEPS_RANGE"]
BOSS_BROKEN_PATH_HOLD_FRAMES = sym["BOSS_BROKEN_PATH_HOLD_FRAMES"]
BOSS_BROKEN_PATH_LEN = sym["BOSS_BROKEN_PATH_LEN"]
BOSS_BROKEN_PATH_X = sym["BOSS_BROKEN_PATH_X"]
BOSS_BROKEN_PATH_Y = sym["BOSS_BROKEN_PATH_Y"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
PAT_SASAPI = sym["PAT_SASAPI"]
BOSS_COLOR = sym["BOSS_COLOR"]
BOSS_FLASH_TIMER = sym["BOSS_FLASH_TIMER"]
BOSS_POSE_COUNT = sym["BOSS_POSE_COUNT"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
SBEAM_ACT = sym["SBEAM_ACT"]
HORMING_VOLLEY_COUNT = sym["HORMING_VOLLEY_COUNT"]
GAME_TICK = sym["GAME_TICK"]
BULLET0_ACT = sym["BULLET0_ACT"]
BOSS_BROKEN_BEAM_COUNT = sym["BOSS_BROKEN_BEAM_COUNT"]
BOSS_BROKEN_BEAM_TIMER = sym["BOSS_BROKEN_BEAM_TIMER"]
BOSS_BROKEN_BEAM_POINT_COUNT = sym["BOSS_BROKEN_BEAM_POINT_COUNT"]
BOSS_BROKEN_BEAM_INTERVAL = sym["BOSS_BROKEN_BEAM_INTERVAL"]
BOSS_BROKEN_BEAM_SLOT_COUNT = sym["BOSS_BROKEN_BEAM_SLOT_COUNT"]
BOSS_BROKEN_BEAM_SPR_BASE_SLOT = sym["BOSS_BROKEN_BEAM_SPR_BASE_SLOT"]
BOSS_BROKEN_BEAM_SPRITE_ATTRS = sym["BOSS_BROKEN_BEAM_SPRITE_ATTRS"]
BOSS_BROKEN_BEAM_CODE1 = sym["BOSS_BROKEN_BEAM_CODE1"]
BOSS_BROKEN_BEAM_CODE2 = sym["BOSS_BROKEN_BEAM_CODE2"]
BOSS_BROKEN_BEAM_CODE3 = sym["BOSS_BROKEN_BEAM_CODE3"]
BOSS_BROKEN_BEAM_CODE4 = sym["BOSS_BROKEN_BEAM_CODE4"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_LIFE = sym["TANK_LIFE"]
TANK_HAZARD_IFRAMES = sym["TANK_HAZARD_IFRAMES"]
TANK_COLLISION_X_OFFSET = sym["TANK_COLLISION_X_OFFSET"]
TANK_COLLISION_Y_OFFSET = sym["TANK_COLLISION_Y_OFFSET"]
TANK_COLLISION_WIDTH = sym["TANK_COLLISION_WIDTH"]
TANK_COLLISION_HEIGHT = sym["TANK_COLLISION_HEIGHT"]
TANK_FLASH_TIMER = sym["TANK_FLASH_TIMER"]
TANK_HAZARD_IFRAME_DURATION = sym["TANK_HAZARD_IFRAME_DURATION"]
FLASH_DURATION = sym["FLASH_DURATION"]
GAME_RNG = sym["GAME_RNG"]
TICK = sym["TICK"]
BOSS_BROKEN_BEAM_COLOR = sym["BOSS_BROKEN_BEAM_COLOR"]

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


def step_toward(current, target, speed):
    """Python mirror of the asm STEP_TOWARD helper - clamps on overshoot."""
    if current == target:
        return current
    if current < target:
        return min(current + speed, target)
    return max(current - speed, target)


def trigger_broken_form(cpu, x=100, phase=0):
    """Drains HP to exactly the threshold (2 hits from threshold+2) and
    runs the SPARK burst to completion, leaving BOSS_FORM=ACTIVE and the
    RECENTERING sub-phase already 1 frame in (REVEAL_BOSS_BROKEN_FORM's
    own tail-call into UPDATE_BOSS_BROKEN_ACTIVE)."""
    make_boss(cpu, x=x, hp=BOSS_BROKEN_HP_THRESHOLD + 2, phase=phase)
    death_x, death_y = cpu.mem[BOSS_X], cpu.mem[BOSS_Y]
    hit_boss(cpu, x)
    hit_boss(cpu, x)  # triggers
    cpu.mem[BOSS_FLASH_TIMER] = 0  # isolate later color checks from the triggering hit's own flash
    for _ in range(BOSS_EXPL_SPARK_DURATION):
        call_routine(cpu, "UPDATE_BOSS_ALL")
    return death_x, death_y


check("BOSS_BROKEN_HP_THRESHOLD is 50 (corrected mid-round from an initial 200 misreading)",
      BOSS_BROKEN_HP_THRESHOLD == 50)
check("BOSS_BROKEN_QUAD_COUNT is 4 (32x32 = 2x2 quadrants, vs the old body's 16)",
      BOSS_BROKEN_QUAD_COUNT == 4)
check("BOSS_BROKEN_PATH_LEN is a power of 2 (the asm side ANDs GAME_TICK/an index against LEN-1)",
      BOSS_BROKEN_PATH_LEN & (BOSS_BROKEN_PATH_LEN - 1) == 0)
check("BOSS_COLLISION_SIZE (the old body) is still 64, unaffected by this round",
      BOSS_COLLISION_SIZE == 64)
check("BOSS_BROKEN_COLLISION_SIZE (round36-14 follow-up #3, '32x32になるよう修正') is 32",
      BOSS_BROKEN_COLLISION_SIZE == 32)

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
# back to 0, AND (round36-14 follow-up fix - real-hardware report:
# "スパーク爆発で最初からボスが消えてる...消えてしまうことがある 何ら
# かの切り替えタイミングの問題だろう") the real body sprite is brought
# BACK (DRAW_BOSS+FLUSH_BOSS_SPRITES) - a pose hides the hw sprite
# entirely (HIDE_BOSS_SPRITES at pose-entry), so a trigger landing mid-
# pose would otherwise leave the boss invisible for the whole SPARK
# burst; this exact scenario is actually the COMMON case, not an edge
# case, since the player keeps shooting through poses too. ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 1, phase=1)
call_routine(cpu, "HIDE_BOSS_SPRITES")  # simulate the real pose-entry state (sprite hidden) before the trigger
call_routine(cpu, "DRAW_SASAPI_HAND")   # actually draw it so ERASE_SASAPI_HAND has something real to undo
hit_boss(cpu, 100)
hit_boss(cpu, 100)
check("triggering mid-pose (BOSS_PHASE=1) resets BOSS_PHASE back to 0",
      cpu.mem[BOSS_PHASE] == 0)
old_body_visible = any(cpu.vram[SAT_BASE + (BOSS_SPR_BASE_SLOT + i) * 4] != 209 for i in range(16))
check("triggering mid-pose brings the real body sprite back (not left hidden from the pose) - "
      "the actual bug behind '最初からボスが消えてる'",
      old_body_visible)

# ---- the SPARK burst runs for exactly BOSS_EXPL_SPARK_DURATION frames,
# then reveals the broken form, starting the RECENTERING sub-phase
# ("その位置から始まるが一旦中央に寄せろ") ----
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_BROKEN_HP_THRESHOLD + 2)
death_x, death_y = cpu.mem[BOSS_X], cpu.mem[BOSS_Y]
hit_boss(cpu, 100)
hit_boss(cpu, 100)  # triggers - BOSS_FORM=SPARK
cpu.mem[BOSS_FLASH_TIMER] = 0  # isolate the reveal's own color from the triggering hit's own flash
for _ in range(BOSS_EXPL_SPARK_DURATION - 1):
    call_routine(cpu, "UPDATE_BOSS_ALL")
check("still SPARK 1 frame before the burst's own duration elapses",
      cpu.mem[BOSS_FORM] == BOSS_FORM_SPARK)
call_routine(cpu, "UPDATE_BOSS_ALL")  # the final frame - UBS_LAST_FRAME fires this call
check("BOSS_FORM becomes ACTIVE the instant the SPARK burst's own duration elapses",
      cpu.mem[BOSS_FORM] == BOSS_FORM_ACTIVE)
check("the shared explosion state machine is retired (DONE), not left mid-GROW",
      cpu.mem[BOSS_EXPL_STATE] == BOSS_EXPL_STATE_DONE)
check("reveal starts the RECENTERING sub-phase, not the orbit directly",
      cpu.mem[BOSS_BROKEN_RECENTERING] == 1)

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

# ---- RECENTERING: appears at the real death position, then walks
# toward the fixed BOSS_BROKEN_CENTER_X/Y point at BOSS_BROKEN_RECENTER_
# SPEED px/frame - "その位置から始まるが一旦中央に寄せろ センタリング
# するかたちで" ----
expected_x = step_toward(death_x, BOSS_BROKEN_CENTER_X, BOSS_BROKEN_RECENTER_SPEED)
expected_y = step_toward(death_y, BOSS_BROKEN_CENTER_Y, BOSS_BROKEN_RECENTER_SPEED)
check("BOSS_X after reveal's own first frame has taken exactly one RECENTER_SPEED step from the "
      "real death position toward the fixed center (not a jump to some other fixed point)",
      cpu.mem[BOSS_X] == expected_x)
check("BOSS_Y similarly takes exactly one RECENTER_SPEED step toward the fixed center",
      cpu.mem[BOSS_Y] == expected_y)

arrived = False
for _ in range(200):
    call_routine(cpu, "UPDATE_BOSS_ALL")
    if cpu.mem[BOSS_BROKEN_RECENTERING] == 0:
        arrived = True
        break
check("RECENTERING eventually clears - the body actually reaches the fixed center", arrived)
check("BOSS_X sits exactly at BOSS_BROKEN_CENTER_X once RECENTERING clears",
      cpu.mem[BOSS_X] == BOSS_BROKEN_CENTER_X)
check("BOSS_Y sits exactly at BOSS_BROKEN_CENTER_Y once RECENTERING clears",
      cpu.mem[BOSS_Y] == BOSS_BROKEN_CENTER_Y)
check("the orbit starts at the loop's own (0,0)-offset crossing point - no visual jump at the "
      "recentering->orbit handoff",
      cpu.mem[BOSS_BROKEN_PATH_INDEX] == BOSS_BROKEN_PATH_CROSS_INDEX)
check("the orbit starts already MOVING (not parked immediately on arrival)",
      cpu.mem[BOSS_BROKEN_MOVING] == 1)

# self-consistency over many frames, rather than hand-predicting an
# exact call count - every frame, BOSS_X/BOSS_Y must equal the ABSOLUTE
# path[BOSS_BROKEN_PATH_INDEX] exactly (centered on the fixed point, not
# per-death any more), and whenever the index itself changes it must
# advance by exactly 1 (wrapping at BOSS_BROKEN_PATH_LEN), never skip.
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
check("BOSS_X/BOSS_Y always match the absolute path[BOSS_BROKEN_PATH_INDEX] exactly, every "
      f"single frame across {3 * BOSS_BROKEN_PATH_HOLD_FRAMES} frames",
      consistent)
check("the path index actually advances (not stuck) while MOVING, by exactly 1 step at a time",
      advances >= 2)

# ---- a death near the screen's own edge still ends up orbiting the
# SAME fixed center, full amplitude - "今だと端で倒すと画面半分の狭い
# 起動で動いてしまってる" no longer applies since the orbit itself is no
# longer derived from the death position at all. ----
cpu = fresh_cpu()
trigger_broken_form(cpu, x=0)  # far left edge of the boss's own real patrol range
check("a death near the screen's left edge (X=0) still starts RECENTERING toward the SAME "
      "fixed center as any other death position",
      cpu.mem[BOSS_BROKEN_RECENTERING] == 1)
arrived = False
for _ in range(200):
    call_routine(cpu, "UPDATE_BOSS_ALL")
    if cpu.mem[BOSS_BROKEN_RECENTERING] == 0:
        arrived = True
        break
check("...and actually arrives at the exact same fixed center regardless of death position",
      arrived and cpu.mem[BOSS_X] == BOSS_BROKEN_CENTER_X and cpu.mem[BOSS_Y] == BOSS_BROKEN_CENTER_Y)

# ---- collision box shrinks to the real 32x32 footprint once in the
# broken form - "形態変化後に64x64のコリジョンのままになってる 32x32に
# なるよう修正" ----
boss_row = BOSS_SPAWN_Y // 8
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_HP_INIT)
make_bullet(cpu, col=(100 + 63) // 8, row=boss_row)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("normal form: a bullet at the OLD body's own far/right edge (+63) still registers a hit "
      "(64x64 box, unaffected by this round)",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT - 1)

cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_HP_INIT)
cpu.mem[BOSS_FORM] = BOSS_FORM_ACTIVE
make_bullet(cpu, col=(100 + 63) // 8, row=boss_row)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("broken form: a bullet at the OLD body's own far/right edge (+63) no longer registers - "
      "the box has genuinely shrunk to 32x32",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT)

cpu = fresh_cpu()
make_boss(cpu, x=100, hp=BOSS_HP_INIT)
cpu.mem[BOSS_FORM] = BOSS_FORM_ACTIVE
make_bullet(cpu, col=(100 + 31) // 8, row=boss_row)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("broken form: a bullet at the NEW body's own real right edge (+31) still registers a hit",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT - 1)


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
saw_centered = False
for f in range(8000):
    step_frame(cpu)
    if cpu.mem[BOSS_FORM] == BOSS_FORM_ACTIVE:
        saw_active_form = True
        if cpu.mem[BOSS_BROKEN_RECENTERING] == 0:
            saw_centered = True
            if cpu.mem[BOSS_BROKEN_MOVING]:
                saw_moving = True
            else:
                saw_stopped = True
    if saw_moving and saw_stopped:
        break
check("real MAINLOOP: the SPARK burst really does complete and reveal the broken form (BOSS_FORM=ACTIVE)",
      saw_active_form)
check("real MAINLOOP: the body actually finishes recentering and starts orbiting",
      saw_centered)
check("real MAINLOOP: the broken form is observed MOVING at some point",
      saw_moving)
check("real MAINLOOP: the broken form is observed STOPPED at some point too - "
      "round36-14 follow-up #4 ('SasapiBrokenの停止はインフィニティ軌道の1周に1回何処かで停止') "
      "replaced the old random-duration MOVING<->STOPPED cycle with a once-per-lap stop "
      "(BOSS_BROKEN_STEPS_TO_STOP counting down real path-index advances), but it's still a "
      "genuinely repeating cycle, not a one-shot freeze - see the dedicated STEPS_TO_STOP/beam "
      "sequence tests below for the actual per-lap mechanics",
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


# ============================================================
# round36-14 follow-up #4: "SasapiBrokenの停止はインフィニティ軌道の1周
# に1回何処かで停止 で、停止中にビーム攻撃をする 添付がそのキャラデータ
# 1から4までの左方向斜め下に順の角度でビーム発射" - the once-per-lap
# stop mechanic (BOSS_BROKEN_STEPS_TO_STOP) and the 4-beam stop-attack
# (ARM/UPDATE_BOSS_BROKEN_BEAM_SEQ, FIRE_BOSS_BROKEN_BEAM,
# HIDE_BOSS_BROKEN_BEAM(_ALL), CHECK_BOSS_BROKEN_BEAM_VS_TANK).
# ============================================================

# ---- ROLL_BOSS_BROKEN_LAP_STEPS: always lands in [MIN,MIN+RANGE-1],
# actually varies (RANGE is a power of 2 so the asm side is a plain AND,
# no reject-and-subtract - a wrong RANGE would silently narrow or widen
# this window without ever crashing) ----
cpu = fresh_cpu()
seen_lap_steps = set()
for i in range(400):
    cpu.mem[GAME_RNG] = (i * 73) & 0xFF
    cpu.mem[TICK] = (i * 19) & 0xFF  # ROLL_BOSS_BROKEN_LAP_STEPS reads TICK (EF00h), not GAME_TICK (F166h)
    cpu.mem[BOSS_BROKEN_PATH_INDEX] = (i * 5) & 0xFF
    call_routine(cpu, "ROLL_BOSS_BROKEN_LAP_STEPS")
    seen_lap_steps.add(cpu.a)
check(f"ROLL_BOSS_BROKEN_LAP_STEPS always lands in [{BOSS_BROKEN_LAP_STEPS_MIN},"
      f"{BOSS_BROKEN_LAP_STEPS_MIN + BOSS_BROKEN_LAP_STEPS_RANGE - 1}]",
      all(BOSS_BROKEN_LAP_STEPS_MIN <= v <= BOSS_BROKEN_LAP_STEPS_MIN + BOSS_BROKEN_LAP_STEPS_RANGE - 1
          for v in seen_lap_steps))
check("...and actually varies across different seeds, not stuck on one value",
      len(seen_lap_steps) >= 10)

# ---- ARM_BOSS_BROKEN_BEAM_SEQ: zeroes both COUNT and TIMER, arming
# beam1 to fire on the very next UPDATE_BOSS_BROKEN_BEAM_SEQ tick (same
# "0=fire immediately" idiom as ARM_HORMING_VOLLEY) ----
cpu = fresh_cpu()
cpu.mem[BOSS_BROKEN_BEAM_COUNT] = 3
cpu.mem[BOSS_BROKEN_BEAM_TIMER] = 17
call_routine(cpu, "ARM_BOSS_BROKEN_BEAM_SEQ")
check("ARM_BOSS_BROKEN_BEAM_SEQ zeroes BOSS_BROKEN_BEAM_COUNT",
      cpu.mem[BOSS_BROKEN_BEAM_COUNT] == 0)
check("ARM_BOSS_BROKEN_BEAM_SEQ zeroes BOSS_BROKEN_BEAM_TIMER",
      cpu.mem[BOSS_BROKEN_BEAM_TIMER] == 0)


# ---- BOSS_BROKEN_STEPS_TO_STOP: decrements exactly once per REAL
# path-index advance (gated by BOSS_BROKEN_PATH_HOLD_FRAMES raw frames
# per step), never on a frame where the index itself didn't move - this
# is what makes "1周に1回" actually mean "after N real orbit steps",
# not "after N raw frames" (which would make the stop point depend on
# incidental frame timing rather than lap progress) ----
cpu = fresh_cpu()
trigger_broken_form(cpu, x=100)
arrived = False
for _ in range(200):
    call_routine(cpu, "UPDATE_BOSS_ALL")
    if cpu.mem[BOSS_BROKEN_RECENTERING] == 0:
        arrived = True
        break
assert arrived, "setup failure: never finished recentering"

cpu.mem[BOSS_BROKEN_STEPS_TO_STOP] = 3
cpu.mem[BOSS_BROKEN_MOVING] = 1
cpu.mem[BOSS_BROKEN_FRAME_COUNTER] = 0
prev_idx = cpu.mem[BOSS_BROKEN_PATH_INDEX]
prev_steps = cpu.mem[BOSS_BROKEN_STEPS_TO_STOP]
consistent = True
advance_count = 0
guard = 0
while cpu.mem[BOSS_BROKEN_MOVING] == 1 and guard < 500:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    guard += 1
    idx = cpu.mem[BOSS_BROKEN_PATH_INDEX]
    steps = cpu.mem[BOSS_BROKEN_STEPS_TO_STOP]
    idx_changed = idx != prev_idx
    if idx_changed:
        advance_count += 1
        if steps != (prev_steps - 1) & 0xFF:
            consistent = False
    else:
        if steps != prev_steps:
            consistent = False
    prev_idx, prev_steps = idx, steps
check("BOSS_BROKEN_STEPS_TO_STOP only ever decrements on a frame where BOSS_BROKEN_PATH_INDEX "
      "actually advanced, and decrements by exactly 1 when it does",
      consistent)
check("...and the lap genuinely ends after exactly the 3 real advances that were armed "
      "(not early, not late)",
      advance_count == 3)
check("the instant STEPS_TO_STOP reaches 0, MOVING flips to 0 (loop's own exit condition) and the "
      "beam sequence is armed (COUNT=TIMER=0) - the handoff into '停止中にビーム攻撃' happens on "
      "the very same frame, no idle gap",
      cpu.mem[BOSS_BROKEN_MOVING] == 0
      and cpu.mem[BOSS_BROKEN_BEAM_COUNT] == 0
      and cpu.mem[BOSS_BROKEN_BEAM_TIMER] == 0)


# ---- UPDATE_BOSS_BROKEN_BEAM_SEQ: fires beams 1->4 in order, each one
# REPLACING the previous (confirmed with the user: "発射ごとに前の
# ビームは消え、常に1本のみ表示"), BOSS_BROKEN_BEAM_INTERVAL frames
# apart, then one more INTERVAL-length wait before hiding the 4th beam
# and resuming movement (MOVING=1, a fresh lap re-rolled) ----
def current_beam_code(cpu):
    """the pattern code of whatever's currently drawn in beam slot 0, or
    None if BOSS_BROKEN_BEAM_POINT_COUNT is 0 (no beam visible)."""
    if cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT] == 0:
        return None
    return cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + 2]

cpu = fresh_cpu()
cpu.mem[BOSS_X] = 96
cpu.mem[BOSS_Y] = 64
call_routine(cpu, "ARM_BOSS_BROKEN_BEAM_SEQ")
seen_codes = []  # de-duplicated sequence of "currently visible beam code"
never_two_at_once = True
for _ in range(BOSS_BROKEN_BEAM_INTERVAL * 5 + 10):
    call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
    pc = cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT]
    code = current_beam_code(cpu)
    if code is not None and (not seen_codes or seen_codes[-1] != code):
        seen_codes.append(code)
    # "常に1本のみ表示" - every slot beyond POINT_COUNT must still be
    # hidden (Y=209), i.e. no leftover points from a previous beam
    # coexisting with the new one.
    for i in range(pc, BOSS_BROKEN_BEAM_SLOT_COUNT):
        if cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] != 209:
            never_two_at_once = False
    if cpu.mem[BOSS_BROKEN_MOVING] == 1:
        break
check("UPDATE_BOSS_BROKEN_BEAM_SEQ fires the 4 beams in exactly the order 1->4 "
      f"(codes {BOSS_BROKEN_BEAM_CODE1},{BOSS_BROKEN_BEAM_CODE2},{BOSS_BROKEN_BEAM_CODE3},"
      f"{BOSS_BROKEN_BEAM_CODE4}), 添付キャラデータの1から4の順",
      seen_codes == [BOSS_BROKEN_BEAM_CODE1, BOSS_BROKEN_BEAM_CODE2,
                     BOSS_BROKEN_BEAM_CODE3, BOSS_BROKEN_BEAM_CODE4])
check("at no point during the whole sequence do 2 beams' worth of points coexist - every slot "
      "beyond the current beam's own POINT_COUNT stays hidden",
      never_two_at_once)
check("after the 4th beam's own hold time elapses, the sequence hides it and resumes movement "
      "(MOVING=1)",
      cpu.mem[BOSS_BROKEN_MOVING] == 1)
check("...with no beam left visible once movement resumes",
      cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT] == 0)
check("...and a fresh lap length re-rolled into STEPS_TO_STOP (in range, not left at 0)",
      BOSS_BROKEN_LAP_STEPS_MIN <= cpu.mem[BOSS_BROKEN_STEPS_TO_STOP]
      <= BOSS_BROKEN_LAP_STEPS_MIN + BOSS_BROKEN_LAP_STEPS_RANGE - 1)

# each beam stays up for exactly BOSS_BROKEN_BEAM_INTERVAL frames before
# the next one replaces it (spot-check beam1 specifically).
cpu = fresh_cpu()
cpu.mem[BOSS_X] = 96
cpu.mem[BOSS_Y] = 64
call_routine(cpu, "ARM_BOSS_BROKEN_BEAM_SEQ")
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")  # fires beam1 immediately (TIMER was armed to 0)
beam1_code = current_beam_code(cpu)
check("beam1 is visible the instant the sequence starts (0=fire immediately, same idiom as "
      "ARM_HORMING_VOLLEY)", beam1_code == BOSS_BROKEN_BEAM_CODE1)
still_beam1 = True
for _ in range(BOSS_BROKEN_BEAM_INTERVAL):
    call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
    if current_beam_code(cpu) != BOSS_BROKEN_BEAM_CODE1:
        still_beam1 = False
check(f"beam1 stays the ONLY visible beam through all {BOSS_BROKEN_BEAM_INTERVAL} more frames "
      "of its own BOSS_BROKEN_BEAM_INTERVAL window (TIMER armed to INTERVAL right after firing, "
      "then checked-and-decremented once per tick, so it takes INTERVAL+1 total ticks - this one "
      "plus the firing tick itself - before the next beam fires)", still_beam1)
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
check(f"beam2 replaces beam1 exactly BOSS_BROKEN_BEAM_INTERVAL({BOSS_BROKEN_BEAM_INTERVAL}) frames "
      "after beam1 fired", current_beam_code(cpu) == BOSS_BROKEN_BEAM_CODE2)


# ---- FIRE_BOSS_BROKEN_BEAM: exact geometry, verified against an
# independent Python re-implementation of the same Bresenham algorithm
# (8-bit wraparound arithmetic, matching the Z80 SUB/JP M semantics
# exactly) rather than just spot-checking a handful of points - this is
# the kind of thing that looks right from a quick glance at 2-3 points
# but silently drifts off the true line further out. ----
# per-beam (XOFS,DXMAG,DYMAG,XDIR) transcribed directly from
# BOSS_BROKEN_BEAM_TABLE in combined_test.asm - angles read off the
# attached SBeam1-4_16x16.json centerline pixels (endpoint-to-endpoint
# exact integer ratios: beam1 -2:1, beam2 -2:5, beam3 2:5, beam4 2:1).
# NOTE on the user's own rough estimate ("多分角度は 22、77、107、129かと
# 思う 端数切捨てで"): this doesn't cleanly match any angle-measurement
# convention against these exact pixel-derived ratios under any sign/axis
# convention tried - the pixel data (reproducible, exact) was trusted
# over the user's own explicitly-hedged estimate ("かと思う", "端数切捨て
# で"); disclosed to the user rather than silently overridden.
BOSS_BROKEN_BEAM_PARAMS = [
    (-1, 2, 1, -1, BOSS_BROKEN_BEAM_CODE1),
    (0, 2, 5, -1, BOSS_BROKEN_BEAM_CODE2),
    (0, 2, 5, 1, BOSS_BROKEN_BEAM_CODE3),
    (1, 2, 1, 1, BOSS_BROKEN_BEAM_CODE4),
]


def sim_fire_beam(origin_col, origin_row, dxmag, dymag, xdir, slot_count):
    def u8(v):
        return v & 0xFF

    def is_neg(v):
        return (v & 0x80) != 0

    x, y = u8(origin_col), u8(origin_row)
    points = []
    if dxmag >= dymag:
        # X-major: D=DYMAG, E=DXMAG, err=DXMAG>>1; X always steps, Y
        # steps whenever err goes negative (then replenished by E).
        err = u8(dxmag) >> 1
        while not (x >= 32 or y >= 24 or len(points) >= slot_count):
            points.append((x, y))
            err = u8(err - dymag)
            if is_neg(err):
                y = u8(y + 1)
                err = u8(err + dxmag)
            x = u8(x + xdir)
    else:
        err = u8(dymag) >> 1
        while not (x >= 32 or y >= 24 or len(points) >= slot_count):
            points.append((x, y))
            err = u8(err - dxmag)
            if is_neg(err):
                x = u8(x + xdir)
                err = u8(err + dymag)
            y = u8(y + 1)
    return points


def fire_beam_and_read(cpu, boss_x, boss_y, beam_idx):
    cpu.mem[BOSS_X] = boss_x
    cpu.mem[BOSS_Y] = boss_y
    cpu.mem[BOSS_BROKEN_BEAM_COUNT] = beam_idx
    call_routine(cpu, "FIRE_BOSS_BROKEN_BEAM")
    n = cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT]
    pts = []
    for i in range(n):
        base = BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4
        pts.append((cpu.mem[base + 1] // 8, cpu.mem[base + 0] // 8))  # (col,row)
    codes = {cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4 + 2] for i in range(n)}
    colors = {cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4 + 3] for i in range(n)}
    hidden_rest = all(cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] == 209
                       for i in range(n, BOSS_BROKEN_BEAM_SLOT_COUNT))
    return pts, codes, colors, hidden_rest


cpu = fresh_cpu()
all_geometry_ok = True
all_codes_ok = True
all_colors_ok = True
all_hidden_rest_ok = True
for boss_x, boss_y in [(96, 64), (200, 64), (96, 8), (8, 8), (200, 176), (8, 176)]:
    for beam_idx, (xofs, dxmag, dymag, xdir, code) in enumerate(BOSS_BROKEN_BEAM_PARAMS):
        origin_col = (boss_x >> 3) + 2 + xofs
        origin_row = (boss_y >> 3) + 2
        expected = sim_fire_beam(origin_col, origin_row, dxmag, dymag, xdir, BOSS_BROKEN_BEAM_SLOT_COUNT)
        pts, codes, colors, hidden_rest = fire_beam_and_read(cpu, boss_x, boss_y, beam_idx)
        if pts != expected:
            all_geometry_ok = False
        if codes and codes != {code}:
            all_codes_ok = False
        if colors and colors != {BOSS_BROKEN_BEAM_COLOR}:
            all_colors_ok = False
        if not hidden_rest:
            all_hidden_rest_ok = False
check("FIRE_BOSS_BROKEN_BEAM's drawn points exactly match an independent Python re-implementation "
      "of the same Bresenham algorithm, for all 4 beams across 6 boss positions (center, both "
      "horizontal edges, both vertical edges, and a corner) - covers the exact angle, the correct "
      "X-major/Y-major branch selection per beam, per-beam XOFS, screen-edge early termination, "
      "and the BOSS_BROKEN_BEAM_SLOT_COUNT cap all at once",
      all_geometry_ok)
check("every drawn point uses the firing beam's own pattern code (BOSS_BROKEN_BEAM_CODE1-4), "
      "never a stale code from a previous beam", all_codes_ok)
check("every drawn point uses BOSS_BROKEN_BEAM_COLOR", all_colors_ok)
check("every slot beyond this beam's own POINT_COUNT is left hidden (Y=209)", all_hidden_rest_ok)

# beam1 is offset 1 cell (8px) LEFT of body center, beam4 1 cell RIGHT,
# beams2/3 exactly centered - "1は2,3の左に4は右に8pxオフセットしたX
# 位置になる"
cpu = fresh_cpu()
pts0, _, _, _ = fire_beam_and_read(cpu, 96, 64, 0)
pts1, _, _, _ = fire_beam_and_read(cpu, 96, 64, 1)
pts2, _, _, _ = fire_beam_and_read(cpu, 96, 64, 2)
pts3, _, _, _ = fire_beam_and_read(cpu, 96, 64, 3)
center_col = (96 >> 3) + 2
check("beam1's own starting column is exactly 1 cell (8px) LEFT of the body's horizontal center",
      pts0[0][0] == center_col - 1)
check("beam2's own starting column is exactly the body's horizontal center",
      pts1[0][0] == center_col)
check("beam3's own starting column is exactly the body's horizontal center too",
      pts2[0][0] == center_col)
check("beam4's own starting column is exactly 1 cell (8px) RIGHT of the body's horizontal center",
      pts3[0][0] == center_col + 1)
check("all 4 beams share the same starting row (the body's vertical center)",
      pts0[0][1] == pts1[0][1] == pts2[0][1] == pts3[0][1])

# a beam really can reach the full BOSS_BROKEN_BEAM_SLOT_COUNT cap when
# it starts far from any screen edge (proves the cap is actually
# exercised somewhere in the boss's real orbit box, not just a number
# that never comes into play).
cpu = fresh_cpu()
capped_anywhere = False
for boss_x, boss_y in [(96, 64), (120, 48), (80, 96)]:
    for beam_idx in range(4):
        pts, _, _, _ = fire_beam_and_read(cpu, boss_x, boss_y, beam_idx)
        if len(pts) == BOSS_BROKEN_BEAM_SLOT_COUNT:
            capped_anywhere = True
check(f"at least one beam/position combination actually reaches the full "
      f"BOSS_BROKEN_BEAM_SLOT_COUNT({BOSS_BROKEN_BEAM_SLOT_COUNT}) cap - not merely a theoretical "
      "ceiling that never triggers in practice",
      capped_anywhere)


# ---- HIDE_BOSS_BROKEN_BEAM / HIDE_BOSS_BROKEN_BEAM_ALL ----
cpu = fresh_cpu()
fire_beam_and_read(cpu, 96, 64, 0)
check("setup: beam1 is actually visible before testing HIDE_BOSS_BROKEN_BEAM",
      cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT] > 0)
call_routine(cpu, "HIDE_BOSS_BROKEN_BEAM")
check("HIDE_BOSS_BROKEN_BEAM resets BOSS_BROKEN_BEAM_POINT_COUNT to 0",
      cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT] == 0)
check("HIDE_BOSS_BROKEN_BEAM hides every slot the beam had actually drawn into (Y=209)",
      all(cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] == 209
          for i in range(BOSS_BROKEN_BEAM_SLOT_COUNT)))

cpu = fresh_cpu()
for i in range(BOSS_BROKEN_BEAM_SLOT_COUNT):
    cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] = 50  # garbage, simulating leftover/uninitialized RAM
call_routine(cpu, "HIDE_BOSS_BROKEN_BEAM_ALL")
check("HIDE_BOSS_BROKEN_BEAM_ALL hides all 18 slots up front (boot-time-style init, called once "
      "from REVEAL_BOSS_BROKEN_FORM)",
      all(cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] == 209
          for i in range(BOSS_BROKEN_BEAM_SLOT_COUNT)))
check("HIDE_BOSS_BROKEN_BEAM_ALL also resets BOSS_BROKEN_BEAM_POINT_COUNT to 0",
      cpu.mem[BOSS_BROKEN_BEAM_POINT_COUNT] == 0)


# ---- CHECK_BOSS_BROKEN_BEAM_VS_TANK: real damage (confirmed with the
# user: "本物の攻撃、既存SBeamのように画面端まで伸びる"), same AABB/
# i-frame shape as CHECK_SBEAM_VS_TANK but walking every drawn segment
# (a static full-length beam, not a moving single-point tip) ----
cpu = fresh_cpu()
pts, _, _, _ = fire_beam_and_read(cpu, 96, 64, 1)  # beam2, steep down-left - plenty of segments
mid_col, mid_row = pts[len(pts) // 2]
cpu.mem[TANK_X] = mid_col * 8 - TANK_COLLISION_X_OFFSET
cpu.mem[TANK_Y_CUR] = mid_row * 8 - TANK_COLLISION_Y_OFFSET
life0 = cpu.mem[TANK_LIFE]
call_routine(cpu, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("tank overlapping a MID-beam segment (not just the first point) takes damage - these are "
      "static full-length beams, any point along them is a real hazard, unlike SBeam's own "
      "tip-only check", cpu.mem[TANK_LIFE] == life0 - 1)
check("a hit sets TANK_FLASH_TIMER", cpu.mem[TANK_FLASH_TIMER] > 0)
check(f"a hit sets TANK_HAZARD_IFRAMES to TANK_HAZARD_IFRAME_DURATION({TANK_HAZARD_IFRAME_DURATION})",
      cpu.mem[TANK_HAZARD_IFRAMES] == TANK_HAZARD_IFRAME_DURATION)

life1 = cpu.mem[TANK_LIFE]
call_routine(cpu, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("no repeat damage on the very next check while TANK_HAZARD_IFRAMES is still active",
      cpu.mem[TANK_LIFE] == life1)

cpu2 = fresh_cpu()
cpu2.mem[TANK_X] = 4
cpu2.mem[TANK_Y_CUR] = 4
life2 = cpu2.mem[TANK_LIFE]
call_routine(cpu2, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("BOSS_BROKEN_BEAM_POINT_COUNT=0 (no beam currently shown) never damages the tank - this is "
      "the routine's own no-op gate, exercised every frame while the boss is orbiting/not stopped",
      cpu2.mem[TANK_LIFE] == life2)

cpu3 = fresh_cpu()
fire_beam_and_read(cpu3, 96, 64, 0)
cpu3.mem[TANK_X] = 300  # far away, off the beam's own path entirely
cpu3.mem[TANK_Y_CUR] = 4
life3 = cpu3.mem[TANK_LIFE]
call_routine(cpu3, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("a tank far from every drawn segment takes no damage", cpu3.mem[TANK_LIFE] == life3)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
