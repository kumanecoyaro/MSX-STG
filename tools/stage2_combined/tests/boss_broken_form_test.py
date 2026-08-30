import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame
import sasapi_gen

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
BOSS_BROKEN_PROJ_ACTIVE = sym["BOSS_BROKEN_PROJ_ACTIVE"]
BOSS_BROKEN_PROJ_X = sym["BOSS_BROKEN_PROJ_X"]
BOSS_BROKEN_PROJ_Y = sym["BOSS_BROKEN_PROJ_Y"]
BOSS_BROKEN_PROJ_DX = sym["BOSS_BROKEN_PROJ_DX"]
BOSS_BROKEN_PROJ_DY = sym["BOSS_BROKEN_PROJ_DY"]
BOSS_BROKEN_PROJ_CODE = sym["BOSS_BROKEN_PROJ_CODE"]
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


# ---- UPDATE_BOSS_BROKEN_BEAM_SEQ: launches beams 1->4 in order,
# BOSS_BROKEN_BEAM_INTERVAL frames apart, into 4 SEPARATE slots that now
# fly independently (round36-14 follow-up#4 3rd real-hardware feedback:
# "ビームが飛んで来ないな...発射して飛ばすんだよ" - the 2nd attempt's
# own "発射ごとに前のビームは消え、常に1本のみ表示" design is retired,
# since a static sprite parked next to the body never actually attacked
# anything; a real flying projectile needs its own persistent slot
# instead, see LAUNCH_BOSS_BROKEN_BEAM/UPDATE_BOSS_BROKEN_BEAM_FLIGHT
# below), then one more INTERVAL-length wait before resuming movement
# (the beams themselves are NOT hidden at that point - whichever ones
# are still mid-flight keep flying) ----
cpu = fresh_cpu()
cpu.mem[BOSS_X] = 96
cpu.mem[BOSS_Y] = 64
call_routine(cpu, "ARM_BOSS_BROKEN_BEAM_SEQ")
launch_order = []  # de-duplicated sequence of "which slot most recently went active"
for _ in range(BOSS_BROKEN_BEAM_INTERVAL * 5 + 10):
    call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
    for slot in range(4):
        if cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + slot] and (not launch_order or launch_order[-1] != slot):
            if slot not in launch_order:
                launch_order.append(slot)
    if cpu.mem[BOSS_BROKEN_MOVING] == 1:
        break
check("UPDATE_BOSS_BROKEN_BEAM_SEQ launches into slots 0,1,2,3 in exactly that order "
      "(matching beams 1->4, 添付キャラデータの1から4の順)",
      launch_order == [0, 1, 2, 3])
check("after the 4th beam's own hold time elapses, the sequence resumes movement (MOVING=1)",
      cpu.mem[BOSS_BROKEN_MOVING] == 1)
check("...and a fresh lap length re-rolled into STEPS_TO_STOP (in range, not left at 0)",
      BOSS_BROKEN_LAP_STEPS_MIN <= cpu.mem[BOSS_BROKEN_STEPS_TO_STOP]
      <= BOSS_BROKEN_LAP_STEPS_MIN + BOSS_BROKEN_LAP_STEPS_RANGE - 1)
check("resuming movement does NOT hide/deactivate beams still mid-flight - at least one of the "
      "4 slots launched this sequence is still active once movement resumes (a real projectile "
      "keeps flying, it isn't cut short by the boss's own stop/move cycle)",
      any(cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + i] for i in range(4)))

# beam2 launches exactly BOSS_BROKEN_BEAM_INTERVAL frames after beam1,
# and beam1's own slot is untouched by beam2 launching (no more
# "replaces the previous" - each beam type gets its own persistent slot).
cpu = fresh_cpu()
cpu.mem[BOSS_X] = 96
cpu.mem[BOSS_Y] = 64
call_routine(cpu, "ARM_BOSS_BROKEN_BEAM_SEQ")
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")  # launches beam1 (slot0) immediately (TIMER armed to 0)
check("beam1 (slot0) launches the instant the sequence starts (0=fire immediately, same idiom "
      "as ARM_HORMING_VOLLEY)", cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 0] == 1)
check("slot1 (beam2) is not yet active", cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] == 0)
still_only_slot0 = True
for _ in range(BOSS_BROKEN_BEAM_INTERVAL):
    call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
    if cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] != 0:
        still_only_slot0 = False
check(f"slot1 stays inactive through all {BOSS_BROKEN_BEAM_INTERVAL} more frames of beam1's own "
      "BOSS_BROKEN_BEAM_INTERVAL window", still_only_slot0)
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_SEQ")
check(f"beam2 (slot1) launches exactly BOSS_BROKEN_BEAM_INTERVAL({BOSS_BROKEN_BEAM_INTERVAL}) "
      "frames after beam1", cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] == 1)


# ---- LAUNCH_BOSS_BROKEN_BEAM: exact starting position + velocity ----
# round36-14 follow-up#4 3rd real-hardware feedback ("ビームが飛んで来
# ないな...今はボスの上に表示されてるだけ それで何の攻撃になる 発射し
# て飛ばすんだよ"): the 2nd attempt placed a single static sprite and
# stopped there; LAUNCH_BOSS_BROKEN_BEAM now also gives it a real per-
# frame pixel velocity (BOSS_BROKEN_PROJ_DX/DY), transcribed directly
# from BOSS_BROKEN_BEAM_TABLE in combined_test.asm: XOFS=[-1,0,0,1],
# DXMAG always 2, DYMAG=[1,5,5,1], XDIR=[-1,-1,1,1] - "Sbeam2,3は中央か
# ら出ているが 1,4は発射位置が1は右上 4が左上になっているので 1は2,3の
# 左に4は右に8pxオフセットしたX位置になる".
BOSS_BROKEN_BEAM_XOFS = [-1, 0, 0, 1]
BOSS_BROKEN_BEAM_DX = [-2, -2, 2, 2]
BOSS_BROKEN_BEAM_DY = [1, 5, 5, 1]
BOSS_BROKEN_BEAM_CODES = [BOSS_BROKEN_BEAM_CODE1, BOSS_BROKEN_BEAM_CODE2,
                          BOSS_BROKEN_BEAM_CODE3, BOSS_BROKEN_BEAM_CODE4]


def launch_beam_and_read(cpu, boss_x, boss_y, beam_idx):
    cpu.mem[BOSS_X] = boss_x
    cpu.mem[BOSS_Y] = boss_y
    cpu.mem[BOSS_BROKEN_BEAM_COUNT] = beam_idx
    call_routine(cpu, "LAUNCH_BOSS_BROKEN_BEAM")
    return {
        "active": cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + beam_idx],
        "x": cpu.mem[BOSS_BROKEN_PROJ_X + beam_idx],
        "y": cpu.mem[BOSS_BROKEN_PROJ_Y + beam_idx],
        "dx": cpu.mem[BOSS_BROKEN_PROJ_DX + beam_idx],
        "dy": cpu.mem[BOSS_BROKEN_PROJ_DY + beam_idx],
        "code": cpu.mem[BOSS_BROKEN_PROJ_CODE + beam_idx],
    }


cpu = fresh_cpu()
all_x_ok = True
all_y_ok = True
all_dx_ok = True
all_dy_ok = True
all_code_ok = True
all_active_ok = True
for boss_x, boss_y in [(96, 64), (200, 64), (96, 8), (8, 8), (200, 176), (8, 176)]:
    center_col = (boss_x >> 3) + 2
    center_row = (boss_y >> 3) + 2
    for beam_idx in range(4):
        s = launch_beam_and_read(cpu, boss_x, boss_y, beam_idx)
        expected_x = ((center_col + BOSS_BROKEN_BEAM_XOFS[beam_idx]) * 8 - 8) & 0xFF
        expected_y = (center_row * 8) & 0xFF
        if s["x"] != expected_x:
            all_x_ok = False
        if s["y"] != expected_y:
            all_y_ok = False
        if s["dx"] != (BOSS_BROKEN_BEAM_DX[beam_idx] & 0xFF):
            all_dx_ok = False
        if s["dy"] != BOSS_BROKEN_BEAM_DY[beam_idx]:
            all_dy_ok = False
        if s["code"] != BOSS_BROKEN_BEAM_CODES[beam_idx]:
            all_code_ok = False
        if s["active"] != 1:
            all_active_ok = False
check("LAUNCH_BOSS_BROKEN_BEAM places the projectile's own starting X exactly 1 cell (8px) left "
      "of the body's horizontal center for beam1, centered for beam2/3, 1 cell right for beam4 - "
      "across 6 boss positions (center, both horizontal edges, both vertical edges, a corner) - "
      "'1は2,3の左に4は右に8pxオフセットしたX位置になる'",
      all_x_ok)
check("LAUNCH_BOSS_BROKEN_BEAM places the starting Y exactly at the body's vertical center, "
      "for all 4 beams and all 6 positions", all_y_ok)
check("each beam gets its own correct per-frame X velocity (signed, matching XDIR*DXMAG from "
      "the table)", all_dx_ok)
check("each beam gets its own correct per-frame Y velocity (DYMAG, always positive/down)",
      all_dy_ok)
check("each beam uses its own pattern code (BOSS_BROKEN_BEAM_CODE1-4), never a stale one",
      all_code_ok)
check("launching a beam always marks its own slot active", all_active_ok)

# BOSS_BROKEN_BEAM_COLOR itself must never have bit6 (EC/early-clock, a
# -32px X shift on real hardware) set, and must be a plain 0-15 index -
# carried over unchanged from the previous round's own fix.
check("BOSS_BROKEN_BEAM_COLOR has the EC (early clock) bit clear",
      (BOSS_BROKEN_BEAM_COLOR & 0x40) == 0)
check("BOSS_BROKEN_BEAM_COLOR is a plain color index in [0,15] (color 7 = cyan)",
      BOSS_BROKEN_BEAM_COLOR == 7)

# round36-14 follow-up#4 2nd real-hardware feedback ("全然違うぞ...
# グラフィックも壊れてる"): a single 16x16 hw sprite occupies 4
# CONSECUTIVE pattern codes (TL/BL/TR/BR), not 1 - carried over
# unchanged from the previous round's own fix, still verified both ways
# (pairwise spacing, and a direct byte-for-byte VRAM comparison against
# sasapi_gen.py's own re-computed expected pattern data).
check("BOSS_BROKEN_BEAM_CODE1-4 are pairwise spaced at least 4 codes apart (each 16x16 "
      "sprite occupies 4 consecutive TL/BL/TR/BR sub-pattern codes - anything closer "
      "silently corrupts a neighboring beam's own data)",
      BOSS_BROKEN_BEAM_CODE2 - BOSS_BROKEN_BEAM_CODE1 >= 4
      and BOSS_BROKEN_BEAM_CODE3 - BOSS_BROKEN_BEAM_CODE2 >= 4
      and BOSS_BROKEN_BEAM_CODE4 - BOSS_BROKEN_BEAM_CODE3 >= 4)

SPRPAT = sym["SPRPAT"]
cpu = fresh_cpu()
trigger_broken_form(cpu, x=100)
all_vram_ok = True
for n, code in enumerate([BOSS_BROKEN_BEAM_CODE1, BOSS_BROKEN_BEAM_CODE2,
                          BOSS_BROKEN_BEAM_CODE3, BOSS_BROKEN_BEAM_CODE4], start=1):
    expected = sasapi_gen.quadrants_from_bits(
        sasapi_gen.load_bits(f"SBeam{n}_16x16"), size=16)[0]
    base = code * 8 + SPRPAT
    actual = [cpu.vram[base + i] for i in range(32)]
    if actual != expected:
        all_vram_ok = False
check("each of the 4 beams' own pattern VRAM (SPRPAT+code*8, 32 bytes) exactly matches "
      "sasapi_gen.py's own re-computed expected bytes for that beam, right after "
      "REVEAL_BOSS_BROKEN_FORM loads all 4 - a direct byte comparison that would have "
      "caught the code-overlap corruption bug immediately",
      all_vram_ok)


# ---- UPDATE_BOSS_BROKEN_BEAM_FLIGHT: per-frame movement + off-screen
# despawn, independently per slot ----
cpu = fresh_cpu()
launch_beam_and_read(cpu, 96, 64, 0)  # beam1: DX=-2,DY=1
x0, y0 = cpu.mem[BOSS_BROKEN_PROJ_X + 0], cpu.mem[BOSS_BROKEN_PROJ_Y + 0]
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_FLIGHT")
check("a single frame of flight advances PROJ_X by exactly this beam's own DX (-2)",
      cpu.mem[BOSS_BROKEN_PROJ_X + 0] == (x0 - 2) & 0xFF)
check("...and PROJ_Y by exactly this beam's own DY (+1)",
      cpu.mem[BOSS_BROKEN_PROJ_Y + 0] == (y0 + 1) & 0xFF)
check("the slot stays active after a normal (non-edge) step",
      cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 0] == 1)
base0 = BOSS_BROKEN_BEAM_SPRITE_ATTRS
check("the sprite staging entry is redrawn at the new position with the right code/color",
      cpu.mem[base0 + 0] == cpu.mem[BOSS_BROKEN_PROJ_Y + 0]
      and cpu.mem[base0 + 1] == cpu.mem[BOSS_BROKEN_PROJ_X + 0]
      and cpu.mem[base0 + 2] == BOSS_BROKEN_BEAM_CODE1
      and cpu.mem[base0 + 3] == BOSS_BROKEN_BEAM_COLOR)

# a beam actually crosses the whole screen and despawns exactly once it
# would go negative/off either horizontal edge or past the bottom -
# never silently wraps around to look like it teleported (the actual
# risk an 8-bit unsigned X/Y coordinate has without this routine's own
# direction-aware bounds check).
for beam_idx, edge_name in [(0, "left"), (2, "right")]:
    cpu = fresh_cpu()
    launch_beam_and_read(cpu, 96, 64, beam_idx)
    seen_x = []
    wrapped = False
    steps = 0
    while cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + beam_idx] and steps < 300:
        call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_FLIGHT")
        steps += 1
        x = cpu.mem[BOSS_BROKEN_PROJ_X + beam_idx]
        if seen_x and abs(x - seen_x[-1]) > 32:  # a real step is only ever 2px - a jump this big means it wrapped
            wrapped = True
        seen_x.append(x)
    check(f"beam (slot{beam_idx}, heading {edge_name}) eventually despawns on its own "
          f"(went inactive within 300 frames, not stuck flying forever)",
          not cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + beam_idx])
    check(f"...and its own X coordinate never jumps/wraps while doing so (each step is only "
          f"ever a small, monotonic +-2px move toward the {edge_name} edge)",
          not wrapped)
    check(f"...and the sprite is actually hidden (Y=209) once despawned",
          cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + beam_idx * 4] == 209)

# bottom-edge despawn (all 4 beams eventually fall off the bottom if
# they don't exit a side first - beam2/3 are steep enough that this is
# actually the common case).
cpu = fresh_cpu()
launch_beam_and_read(cpu, 96, 64, 1)  # beam2: DX=-2,DY=5 (steep)
steps = 0
while cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] and steps < 300:
    call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_FLIGHT")
    steps += 1
check("a steep beam (large DY) despawns within a reasonable number of frames too",
      not cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] and steps < 300)

# multiple slots move independently and simultaneously - a real
# consequence of "4方向にそれぞれ打ち出す" now that beams no longer
# replace each other.
cpu = fresh_cpu()
launch_beam_and_read(cpu, 96, 64, 0)
launch_beam_and_read(cpu, 96, 64, 3)  # beam4: DX=+2,DY=1 (opposite X direction from beam1)
x0_before, x3_before = cpu.mem[BOSS_BROKEN_PROJ_X + 0], cpu.mem[BOSS_BROKEN_PROJ_X + 3]
call_routine(cpu, "UPDATE_BOSS_BROKEN_BEAM_FLIGHT")
check("slot0 (beam1) and slot3 (beam4) both move on the same UPDATE_BOSS_BROKEN_BEAM_FLIGHT "
      "call, each along its own direction",
      cpu.mem[BOSS_BROKEN_PROJ_X + 0] == (x0_before - 2) & 0xFF
      and cpu.mem[BOSS_BROKEN_PROJ_X + 3] == (x3_before + 2) & 0xFF)
check("slots 1 and 2 (never launched) stay inactive and hidden throughout",
      cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] == 0 and cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 2] == 0
      and cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + 1 * 4] == 209
      and cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + 2 * 4] == 209)


# ---- HIDE_BOSS_BROKEN_BEAM_ALL ----
cpu = fresh_cpu()
for i in range(4):
    launch_beam_and_read(cpu, 96, 64, i)
check("setup: all 4 slots are active before testing HIDE_BOSS_BROKEN_BEAM_ALL",
      all(cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + i] for i in range(4)))
call_routine(cpu, "HIDE_BOSS_BROKEN_BEAM_ALL")
check("HIDE_BOSS_BROKEN_BEAM_ALL deactivates all 4 slots at once (boot-time-style init, called "
      "once from REVEAL_BOSS_BROKEN_FORM)",
      all(cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + i] == 0 for i in range(4)))
check("...and hides all 4 slots' own hw sprite staging entries (Y=209)",
      all(cpu.mem[BOSS_BROKEN_BEAM_SPRITE_ATTRS + i * 4] == 209 for i in range(4)))


# ---- CHECK_BOSS_BROKEN_BEAM_VS_TANK: real damage (confirmed with the
# user: "本物の攻撃、既存SBeamのように画面端まで伸びる"), same AABB/
# i-frame shape as CHECK_SBEAM_VS_TANK but a 16x16 box (the beam's own
# real sprite size) per active slot, walked in a loop now that up to 4
# can be flying at once ----
cpu = fresh_cpu()
s = launch_beam_and_read(cpu, 96, 64, 1)  # beam2
cpu.mem[TANK_X] = s["x"] - TANK_COLLISION_X_OFFSET
cpu.mem[TANK_Y_CUR] = s["y"] - TANK_COLLISION_Y_OFFSET
life0 = cpu.mem[TANK_LIFE]
call_routine(cpu, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("tank overlapping an in-flight beam's own box takes damage",
      cpu.mem[TANK_LIFE] == life0 - 1)
check("a hit sets TANK_FLASH_TIMER", cpu.mem[TANK_FLASH_TIMER] > 0)
check(f"a hit sets TANK_HAZARD_IFRAMES to TANK_HAZARD_IFRAME_DURATION({TANK_HAZARD_IFRAME_DURATION})",
      cpu.mem[TANK_HAZARD_IFRAMES] == TANK_HAZARD_IFRAME_DURATION)
check("a hit does NOT deactivate the beam's own slot - it keeps flying through/past the tank, "
      "same as every other projectile in this game that isn't itself destroyed by contact",
      cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 1] == 1)

life1 = cpu.mem[TANK_LIFE]
call_routine(cpu, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("no repeat damage on the very next check while TANK_HAZARD_IFRAMES is still active",
      cpu.mem[TANK_LIFE] == life1)

cpu2 = fresh_cpu()
cpu2.mem[TANK_X] = 4
cpu2.mem[TANK_Y_CUR] = 4
life2 = cpu2.mem[TANK_LIFE]
call_routine(cpu2, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("no beam active in any slot never damages the tank - this is the routine's own no-op "
      "case, exercised every frame while the boss is orbiting/not stopped",
      cpu2.mem[TANK_LIFE] == life2)

cpu3 = fresh_cpu()
launch_beam_and_read(cpu3, 96, 64, 0)
cpu3.mem[TANK_X] = 300  # far away, off every active beam's own box entirely
cpu3.mem[TANK_Y_CUR] = 4
life3 = cpu3.mem[TANK_LIFE]
call_routine(cpu3, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("a tank far from every active beam's own box takes no damage", cpu3.mem[TANK_LIFE] == life3)

# multiple simultaneous beams: only the one actually overlapping the
# tank triggers, and an inactive/miss slot earlier in the loop doesn't
# block detection of a hit in a later slot.
cpu4 = fresh_cpu()
launch_beam_and_read(cpu4, 96, 64, 0)  # slot0: far from the tank (set below)
s3 = launch_beam_and_read(cpu4, 96, 64, 3)  # slot3: this one will overlap the tank
cpu4.mem[TANK_X] = s3["x"] - TANK_COLLISION_X_OFFSET
cpu4.mem[TANK_Y_CUR] = s3["y"] - TANK_COLLISION_Y_OFFSET
life4 = cpu4.mem[TANK_LIFE]
call_routine(cpu4, "CHECK_BOSS_BROKEN_BEAM_VS_TANK")
check("with slot0 active-but-missing and slot3 active-and-overlapping, the tank still takes "
      "damage from slot3 (an earlier active-but-missing slot doesn't short-circuit the loop)",
      cpu4.mem[TANK_LIFE] == life4 - 1)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
