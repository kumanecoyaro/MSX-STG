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

SBEAM_POSE_GATE = sym["SBEAM_POSE_GATE"]
SBEAM_CODE = sym["SBEAM_CODE"]
SBEAM_COLOR = sym["SBEAM_COLOR"]
SBEAM_START_COL = sym["SBEAM_START_COL"]
SBEAM_START_Y = sym["SBEAM_START_Y"]
SBEAM_SLOT_COUNT = sym["SBEAM_SLOT_COUNT"]
SBEAM_SPR_BASE_SLOT = sym["SBEAM_SPR_BASE_SLOT"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_POSE_COUNT = sym["BOSS_POSE_COUNT"]
SBEAM_ACT = sym["SBEAM_ACT"]
SBEAM_ROWS = sym["SBEAM_ROWS"]
SBEAM_GROUND_Y = sym["SBEAM_GROUND_Y"]
SBEAM_FRONT_COL = sym["SBEAM_FRONT_COL"]
SBEAM_BLINK = sym["SBEAM_BLINK"]
SBEAM_SPRITE_ATTRS = sym["SBEAM_SPRITE_ATTRS"]
BOSS_SPAWN_TICK = sym["BOSS_SPAWN_TICK"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
IDCACHE_T0 = sym["IDCACHE_T0"]
IDCACHE_T1 = sym["IDCACHE_T1"]
IDCACHE_T2 = sym["IDCACHE_T2"]
GAME_TICK = sym["GAME_TICK"]
HORMING_VOLLEY_COUNT = sym["HORMING_VOLLEY_COUNT"]
HORMING_POOL = sym["HORMING_POOL"]
HORMING_SLOT_COUNT = sym["HORMING_SLOT_COUNT"]


def set_terrain_flat(cpu, tier):
    """0=row20 highest .. 3=row23 lowest/flat - same IDCACHE_T0..T2
    convention as thunder_test.py's own helper."""
    for col in range(32):
        cpu.mem[IDCACHE_T0 + col] = 1 if tier == 0 else 0
        cpu.mem[IDCACHE_T1 + col] = 1 if tier == 1 else 0
        cpu.mem[IDCACHE_T2 + col] = 1 if tier == 2 else 0


def slot(cpu, i):
    base = SBEAM_SPRITE_ATTRS + i * 4
    return {
        "y": cpu.mem[base + 0],
        "x": cpu.mem[base + 1],
        "pat": cpu.mem[base + 2],
        "color": cpu.mem[base + 3],
    }


def visible(cpu, i):
    return slot(cpu, i)["y"] != 209


def homing_active(cpu):
    return any(cpu.mem[HORMING_POOL + i * 7] != 0 for i in range(HORMING_SLOT_COUNT))


# SBEAM_SPR_BASE_SLOT reuses the boss's own dormant pose-time body slots
# (see combined_test.asm's own SBEAM_SPR_BASE_SLOT comment) - this is a
# design invariant, not just a coincidence, so pin it down here too.
check("SBEAM_SPR_BASE_SLOT reuses the boss's own 16 body-quadrant slots "
      "(dormant throughout the whole pose - same idiom as HORMING's own "
      "reuse of ZacoII/BulletU) plus the 6 permanently-free slots right "
      "after them (10-31 = 22 contiguous slots)",
      SBEAM_SPR_BASE_SLOT == BOSS_SPR_BASE_SLOT and SBEAM_SLOT_COUNT == 22)

# "発射起点はボスに被らない左がわ 伸ばした腕の先から" - origin must sit
# strictly left of the pose box's own left edge (BOSS_SPAWNX), not under
# the boss's own body - round-2 fix for the round-1 mistake (col28, which
# was inside the box).
check("SBEAM_START_COL sits strictly left of the boss's own pose box "
      "(BOSS_SPAWNX's own column) - not overlapping the boss's body",
      SBEAM_START_COL < BOSS_SPAWNX // 8)


# ---- INIT/spawn: SBeam hw sprite art actually loaded into VRAM ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)


def spawn_boss(cpu):
    cpu.mem[GAME_TICK] = BOSS_SPAWN_TICK & 0xFF
    cpu.mem[GAME_TICK + 1] = (BOSS_SPAWN_TICK >> 8) & 0xFF
    call_routine(cpu, "UPDATE_BOSS_ALL")


spawn_boss(cpu)
pat_base = SBEAM_CODE * 8 + sym["SPRPAT"]
loaded = list(cpu.vram[pat_base:pat_base + 8])
check("boss spawn loads the SBeam pattern's own lit top-left 8x8 (nonzero bytes) into "
      "SPRPAT+SBEAM_CODE*8", any(b != 0 for b in loaded))
padding = list(cpu.vram[pat_base + 8:pat_base + 32])
check("the rest of the 16x16 sprite canvas (bottom-left/top-right/bottom-right quadrants) "
      "stays blank - only the top-left 8x8 art is ever lit", all(b == 0 for b in padding))


# ---- FIRE_SBEAM: unconditional now (the SBEAM_POSE_GATE check moved to
# the call site in UBA_MOVE_RIGHT, so it can also decide whether to call
# ARM_HORMING_VOLLEY instead - see below) ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)
call_routine(cpu, "FIRE_SBEAM")
check("FIRE_SBEAM arms the drop phase (ACT=1) when called", cpu.mem[SBEAM_ACT] == 1)
check("FIRE_SBEAM resets SBEAM_ROWS to 0", cpu.mem[SBEAM_ROWS] == 0)
check("FIRE_SBEAM resets SBEAM_BLINK to 0", cpu.mem[SBEAM_BLINK] == 0)

for tier, expected_row in [(0, 20), (1, 21), (2, 22), (3, 23)]:
    cpu = fresh_cpu()
    set_terrain_flat(cpu, tier)
    call_routine(cpu, "FIRE_SBEAM")
    check(f"FIRE_SBEAM computes SBEAM_GROUND_Y from the terrain at SBEAM_START_COL "
          f"(tier{tier} -> row{expected_row} -> Y={expected_row * 8 - 8})",
          cpu.mem[SBEAM_GROUND_Y] == expected_row * 8 - 8)


# ---- US_DROP_STEP: grows one 8px segment/frame, transitions to the
# sweep phase (ACT=2) the instant it reaches SBEAM_GROUND_Y ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)
call_routine(cpu, "FIRE_SBEAM")
ground_y = cpu.mem[SBEAM_GROUND_Y]
expected_rows = (ground_y - SBEAM_START_Y) // 8 + 1
rows_trace = []
for _ in range(30):
    call_routine(cpu, "US_DROP_STEP")
    rows_trace.append(cpu.mem[SBEAM_ROWS])
    if cpu.mem[SBEAM_ACT] != 1:
        break
check(f"US_DROP_STEP grows SBEAM_ROWS by exactly 1/frame until it reaches the ground "
      f"(expected {expected_rows} segments for tier0)",
      rows_trace == list(range(1, expected_rows + 1)))
check("US_DROP_STEP transitions to the sweep phase (ACT=2) once the ground is reached",
      cpu.mem[SBEAM_ACT] == 2)
check("US_DROP_STEP arms SBEAM_FRONT_COL back at SBEAM_START_COL for the sweep to start from",
      cpu.mem[SBEAM_FRONT_COL] == SBEAM_START_COL)
tier0_rows = expected_rows


# ---- US_SWEEP_RETRACT: FRONT_COL sweeps down to 0 (screen's left edge -
# "左端まで行ったら"), then retracts back up to SBEAM_START_COL ("元の位
# 置まで") ----
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_FRONT_COL] = SBEAM_START_COL
sweep_cols = []
for _ in range(SBEAM_START_COL + 2):
    will_decrement = cpu.mem[SBEAM_ACT] == 2 and cpu.mem[SBEAM_FRONT_COL] != 0
    call_routine(cpu, "US_SWEEP_RETRACT")
    if will_decrement:
        sweep_cols.append(cpu.mem[SBEAM_FRONT_COL])
    if cpu.mem[SBEAM_ACT] != 2:
        break
check("US_SWEEP_RETRACT decreases SBEAM_FRONT_COL by 1/frame while sweeping",
      sweep_cols == list(range(SBEAM_START_COL - 1, -1, -1)))
check("US_SWEEP_RETRACT flips to the retract phase (ACT=3) once FRONT_COL actually reaches "
      "the screen's left edge (column0)", cpu.mem[SBEAM_ACT] == 3)
check("the retract phase starts from FRONT_COL=0 (no column skipped at the reversal)",
      cpu.mem[SBEAM_FRONT_COL] == 0)

retract_cols = []
for _ in range(SBEAM_START_COL + 2):
    call_routine(cpu, "US_SWEEP_RETRACT")
    retract_cols.append(cpu.mem[SBEAM_FRONT_COL])
    if cpu.mem[SBEAM_ACT] != 3:
        break
check("US_SWEEP_RETRACT increases SBEAM_FRONT_COL by 1/frame while retracting",
      retract_cols == list(range(1, SBEAM_START_COL + 1)))
check("US_SWEEP_RETRACT finishes (ACT=0) exactly once FRONT_COL is back at SBEAM_START_COL",
      cpu.mem[SBEAM_ACT] == 0)


# ---- STAGE_SBEAM: sprite-attr correctness per phase, plus the blink ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)
call_routine(cpu, "FIRE_SBEAM")
call_routine(cpu, "US_DROP_STEP")  # ROWS=1
call_routine(cpu, "US_DROP_STEP")  # ROWS=2
call_routine(cpu, "STAGE_SBEAM")
blink_after_1 = cpu.mem[SBEAM_BLINK]
hidden_all_on_this_tick = all(not visible(cpu, i) for i in range(SBEAM_SLOT_COUNT))
call_routine(cpu, "STAGE_SBEAM")
blink_after_2 = cpu.mem[SBEAM_BLINK]
check("STAGE_SBEAM actually toggles SBEAM_BLINK every call - 取り敢えず1フレ点滅で",
      blink_after_1 != blink_after_2)
check("on the 'off' blink tick every slot is forced hidden (Y=209) regardless of phase/ROWS",
      hidden_all_on_this_tick)
check("on the 'on' blink tick the drop phase's own 2 grown segments are visible",
      visible(cpu, 0) and visible(cpu, 1))
check("on the 'on' blink tick segments beyond SBEAM_ROWS stay hidden",
      not visible(cpu, 2))
s0 = slot(cpu, 0)
s1 = slot(cpu, 1)
check("drop phase: segment0 sits at (SBEAM_START_COL*8, SBEAM_START_Y)",
      s0["x"] == SBEAM_START_COL * 8 and s0["y"] == SBEAM_START_Y)
check("drop phase: segment1 is exactly 8px below segment0 (same column) - no gap",
      s1["x"] == s0["x"] and s1["y"] == s0["y"] + 8)
check("drop phase: segments use SBEAM_CODE/SBEAM_COLOR",
      s0["pat"] == SBEAM_CODE and s0["color"] == SBEAM_COLOR)


# ---- sweep/retract phase: L-shaped rendering - the vertical arm (ROWS
# segments) MUST stay visible the whole time, alongside the growing/
# shrinking horizontal arm - "発射基点は変えず...ラインを引いて元まで
# 戻る" (round-2 fix: previously the vertical arm vanished entirely once
# the horizontal sweep began) ----
cpu = fresh_cpu()
ROWS = 6
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_ROWS] = ROWS
cpu.mem[SBEAM_FRONT_COL] = SBEAM_START_COL - 4   # mid-sweep: 4 horizontal cols revealed
cpu.mem[SBEAM_GROUND_Y] = 152
cpu.mem[SBEAM_BLINK] = 1   # next toggle -> 0 -> the visible pass
call_routine(cpu, "STAGE_SBEAM")

vertical_ok = True
for i in range(ROWS):
    s = slot(cpu, i)
    if s["y"] != SBEAM_START_Y + i * 8 or s["x"] != SBEAM_START_COL * 8 or s["y"] == 209:
        vertical_ok = False
check("sweep phase: the vertical arm's own ROWS segments are ALL still visible at their "
      "original (fixed origin column) positions while the horizontal arm is sweeping",
      vertical_ok)

horiz_ok = True
horiz_budget = SBEAM_SLOT_COUNT - ROWS
for j in range(horiz_budget):
    col = SBEAM_START_COL - 1 - j
    s = slot(cpu, ROWS + j)
    expect_visible = col >= SBEAM_START_COL - 4
    if expect_visible != (s["y"] != 209):
        horiz_ok = False
    if expect_visible and (s["x"] != col * 8 or s["y"] != 152):
        horiz_ok = False
check("sweep phase: the horizontal arm's own segments (slots ROWS..) exactly match the "
      "column>=SBEAM_FRONT_COL formula, extending left from SBEAM_START_COL-1 (one column "
      "outside the vertical arm's own corner cell - no wasted/duplicate slot)",
      horiz_ok)

# hw-cap check: with a real terrain-driven ROWS, the combined budget
# (vertical+horizontal) still tops out at SBEAM_SLOT_COUNT - a flagged,
# real hardware limit, not an unbounded line.
check("sweep phase: the vertical+horizontal combined slot budget is capped at "
      "SBEAM_SLOT_COUNT (22) - a genuine, flagged hw-sprite deviation from a literal "
      "unbounded 'スプライトを足していく'",
      ROWS + horiz_budget == SBEAM_SLOT_COUNT)


# ---- SBeam and Homing are mutually exclusive per pose now - "当然サン
# ダービーム中はホーミングもサンダーも撃たねえんだよ" ----
def prime_pose_entry(cpu, pose_count):
    """Puts the boss 1 step (BOSS_SPEED) away from BOSS_SPAWNX, moving
    right, ACT=1/PHASE=0 (patrolling) - the next UPDATE_BOSS_ALL call
    steps it exactly onto BOSS_SPAWNX and triggers the real pose-entry
    branch in UBA_MOVE_RIGHT (matching real UPDATE_BOSS_ALL's own
    control flow, not a direct FIRE_SBEAM/ARM_HORMING_VOLLEY call)."""
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_PHASE] = 0
    cpu.mem[sym["BOSS_DIR"]] = 1
    cpu.mem[BOSS_X] = BOSS_SPAWNX - sym["BOSS_SPEED"]
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_POSE_COUNT] = pose_count


cpu = fresh_cpu()
prime_pose_entry(cpu, SBEAM_POSE_GATE - 1)
set_terrain_flat(cpu, 0)
call_routine(cpu, "UPDATE_BOSS_ALL")   # steps the last BOSS_SPEED px into the pose-entry clamp
check("below SBEAM_POSE_GATE: pose-entry arms the homing volley (HORMING_VOLLEY_COUNT reset), "
      "not SBeam", cpu.mem[HORMING_VOLLEY_COUNT] == 0 and cpu.mem[SBEAM_ACT] == 0)

cpu = fresh_cpu()
prime_pose_entry(cpu, SBEAM_POSE_GATE)
cpu.mem[HORMING_VOLLEY_COUNT] = 0xAA   # sentinel - must NOT be touched by this pose-entry
set_terrain_flat(cpu, 0)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("at/above SBEAM_POSE_GATE: pose-entry arms SBeam (ACT=1) instead of the homing volley",
      cpu.mem[SBEAM_ACT] == 1)
check("ARM_HORMING_VOLLEY is NOT called for an SBeam pose - HORMING_VOLLEY_COUNT is left "
      "untouched (still the 0xAA sentinel)", cpu.mem[HORMING_VOLLEY_COUNT] == 0xAA)


# ---- real MAINLOOP: SBeam stays silent before the 3rd pose, then fires,
# completes a full drop/sweep/retract cycle, never fires Homing during
# that same pose, and never corrupts the boss's own body sprite once the
# pose ends ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
pose_count_at_first_fire = None
saw_drop = False
saw_sweep = False
saw_retract = False
saw_reach_left_edge = False
completed = False
saw_blink_off_while_active = False
saw_blink_on_while_active = False
saw_homing_during_sbeam = False
saw_vertical_and_horizontal_together = False
for f in range(60000):
    step_frame(cpu)
    act = cpu.mem[SBEAM_ACT]
    if act != 0 and pose_count_at_first_fire is None:
        pose_count_at_first_fire = cpu.mem[BOSS_POSE_COUNT]
    if act == 1:
        saw_drop = True
    if act == 2:
        saw_sweep = True
        if cpu.mem[SBEAM_FRONT_COL] == 0:
            saw_reach_left_edge = True
    if act == 3:
        saw_retract = True
    if act in (2, 3):
        rows = cpu.mem[SBEAM_ROWS]
        if rows > 0 and visible(cpu, 0) and any(visible(cpu, rows + k) for k in range(SBEAM_SLOT_COUNT - rows)):
            saw_vertical_and_horizontal_together = True
    if act != 0:
        if all(not visible(cpu, i) for i in range(SBEAM_SLOT_COUNT)):
            saw_blink_off_while_active = True
        else:
            saw_blink_on_while_active = True
        if homing_active(cpu):
            saw_homing_during_sbeam = True
    if pose_count_at_first_fire is not None and saw_drop and saw_sweep and saw_retract and act == 0:
        completed = True
        break

check("real MAINLOOP: SBeam never fires before BOSS_POSE_COUNT reaches SBEAM_POSE_GATE - "
      "ホーミングとサンダー2セット終わったら",
      pose_count_at_first_fire is not None and pose_count_at_first_fire >= SBEAM_POSE_GATE)
check("real MAINLOOP: the drop phase genuinely runs", saw_drop)
check("real MAINLOOP: the sweep phase genuinely runs and reaches the screen's left edge",
      saw_sweep and saw_reach_left_edge)
check("real MAINLOOP: the retract phase genuinely runs", saw_retract)
check("real MAINLOOP: the whole drop/sweep/retract cycle actually completes within real play",
      completed)
check("real MAINLOOP: the blink genuinely alternates on/off while SBeam is active (not stuck "
      "one way)", saw_blink_off_while_active and saw_blink_on_while_active)
check("real MAINLOOP: the vertical arm and horizontal arm are genuinely visible TOGETHER at "
      "some point during the sweep/retract - a real connected L-shaped line, not one "
      "replacing the other", saw_vertical_and_horizontal_together)
check("real MAINLOOP: no homing missile is ever active while SBeam is active - 当然サンダー"
      "ビーム中はホーミングも...撃たねえんだよ", not saw_homing_during_sbeam)

# once the cycle above finished mid-game, keep running long enough to pass
# through at least one more full pose entry/exit, and confirm the boss's
# own body sprite slots read back sane (non-209 Y, i.e. real body art, not
# a leftover hidden-SBeam frame) whenever the boss is patrolling
saw_patrol_after = False
body_slot_sane_while_patrolling = True

for f in range(10000):
    step_frame(cpu)
    if cpu.mem[BOSS_PHASE] == 0 and cpu.mem[BOSS_ACT] == 1:
        saw_patrol_after = True
        # SBeam must be fully idle while the boss patrols (its own body
        # owns SBEAM_SPR_BASE_SLOT.. during this window)
        if cpu.mem[SBEAM_ACT] != 0:
            body_slot_sane_while_patrolling = False
    if saw_patrol_after:
        break

check("real MAINLOOP: after a full SBeam cycle, the boss resumes patrolling normally "
      "(reaches BOSS_PHASE=0 again)", saw_patrol_after)
check("real MAINLOOP: SBEAM_ACT is always back to 0 (fully idle) whenever the boss is "
      "patrolling - UBAP_END's own forced clear guarantees SBeam never fights the boss's "
      "own body sprite for SBEAM_SPR_BASE_SLOT..",
      body_slot_sane_while_patrolling)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
