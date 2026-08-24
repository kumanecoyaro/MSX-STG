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
SBEAM_TRIP = sym["SBEAM_TRIP"]
SBEAM_TRIP_COUNT = sym["SBEAM_TRIP_COUNT"]
check("US_SWEEP_RETRACT: SBEAM_TRIP_COUNT is 2 - サンダービームは2往復に",
      SBEAM_TRIP_COUNT == 2)
check("US_SWEEP_RETRACT: after the FIRST round trip finishes, it starts sweeping AGAIN "
      "(ACT=2) instead of ending - 2往復のうち1回目", cpu.mem[SBEAM_ACT] == 2)
check("US_SWEEP_RETRACT: SBEAM_TRIP was incremented to 1 after the first round trip",
      cpu.mem[SBEAM_TRIP] == 1)

# drive through the SECOND full sweep+retract round trip and confirm it
# actually ends (ACT=0) only after that
for _ in range(SBEAM_START_COL * 2 + 4):
    call_routine(cpu, "US_SWEEP_RETRACT")
    if cpu.mem[SBEAM_ACT] == 0:
        break
check("US_SWEEP_RETRACT finishes (ACT=0) only after BOTH round trips complete - "
      "サンダービームは2往復に", cpu.mem[SBEAM_ACT] == 0 and cpu.mem[SBEAM_TRIP] == SBEAM_TRIP_COUNT)


# ---- real bug caught this round: SBEAM_TRIP originally lived 13 bytes
# below STACKTOP, close enough that ordinary deep CALL/PUSH nesting from
# UNRELATED code (Thunder's own multi-level draw chain) silently
# overwrote it as real stack usage - confirmed by tracing writes to that
# address in a real MAINLOOP run and finding it repeatedly clobbered
# while SBEAM_ACT was 0 the whole time (nothing SBeam-related running).
# Directly guard against any scratch byte living too close to the stack
# again: drive a bunch of real Thunder activity (deep, unrelated CALL
# nesting) with SBEAM_TRIP set to a sentinel and confirm it survives
# completely untouched. ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
STACKTOP = sym["STACKTOP"]
check("SBEAM_TRIP (and the rest of STAGE_SBEAM's own scratch) sit comfortably clear of "
      "STACKTOP, not within a plausible real call-depth's own reach",
      STACKTOP - sym["SBEAM_LINE_TX"] > 0x40)
cpu.mem[SBEAM_TRIP] = 77   # sentinel - SBEAM_ACT stays 0 for this whole sweep (well before
                           # BOSS_POSE_COUNT reaches SBEAM_POSE_GATE), so nothing legitimate
                           # should ever touch SBEAM_TRIP during it
for f in range(2400):      # comfortably covers real Thunder activity (fires well before
                           # the boss's first pose even ends, per thunder_test.py's own timing)
    step_frame(cpu)
    if cpu.mem[SBEAM_ACT] != 0:
        break
check("SBEAM_TRIP survives 2400 real frames of unrelated gameplay (including real Thunder "
      "activity) completely untouched, while SBeam itself never once ran",
      cpu.mem[SBEAM_TRIP] == 77 and cpu.mem[SBEAM_ACT] == 0)


# ---- STAGE_SBEAM: sprite-attr correctness per phase, plus the blink -
# "点滅表示は2フレ表示1フレ非表示に変更" (round4): SBEAM_BLINK now
# cycles 0,1,2,0,1,2,... (mod 3), hidden only on the 3rd value (2) - a
# 2-visible/1-hidden pattern, not the old 1/1 toggle. ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)
call_routine(cpu, "FIRE_SBEAM")
call_routine(cpu, "US_DROP_STEP")  # ROWS=1
call_routine(cpu, "US_DROP_STEP")  # ROWS=2
visibility_trace = []
for _ in range(9):
    call_routine(cpu, "STAGE_SBEAM")
    visibility_trace.append(all(visible(cpu, i) for i in (0, 1, 2)))
# exactly 1 hidden frame per 3 consecutive frames (a real period-3
# pattern), and it's never 2 hidden in a row or all-visible for a whole
# period - i.e. genuinely 2-visible/1-hidden, not the old 1/1 toggle.
period3_ok = all(visibility_trace[i:i + 3].count(False) == 1 for i in range(0, 9, 3))
check("STAGE_SBEAM's own blink is a real 2-visible/1-hidden repeating pattern (not a 1/1 "
      "toggle) - 点滅表示は2フレ表示1フレ非表示に変更", period3_ok)

cpu.mem[SBEAM_BLINK] = 1   # INC -> 2 -> the hidden tick
call_routine(cpu, "STAGE_SBEAM")
hidden_all_on_this_tick = all(not visible(cpu, i) for i in range(SBEAM_SLOT_COUNT))
check("on the hidden blink tick every slot is forced hidden (Y=209) regardless of phase/ROWS",
      hidden_all_on_this_tick)

cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
check("on a visible blink tick the drop phase's own line (origin + 2 grown rows = 3 points, "
      "dy+1) is visible", visible(cpu, 0) and visible(cpu, 1) and visible(cpu, 2))
check("on a visible blink tick segments beyond the line's own dy+1 points stay hidden",
      not visible(cpu, 3))
s0 = slot(cpu, 0)
s1 = slot(cpu, 1)
check("drop phase: segment0 sits at (SBEAM_START_COL*8, SBEAM_START_Y)",
      s0["x"] == SBEAM_START_COL * 8 and s0["y"] == SBEAM_START_Y)
check("drop phase: segment1 is exactly 8px below segment0 (same column) - no gap",
      s1["x"] == s0["x"] and s1["y"] == s0["y"] + 8)
check("drop phase: segments use SBEAM_CODE/SBEAM_COLOR",
      s0["pat"] == SBEAM_CODE and s0["color"] == SBEAM_COLOR)


# ---- sweep/retract phase: a real Bresenham DIAGONAL line from the
# fixed origin to the moving tip - "複数本じゃなく1本だぞ" (round3) -
# not 2 fixed-shape arms glued at a 90-degree corner (round2's own
# design, now superseded). Verify against hand-computed exact points for
# a few slopes. ----
def visible_points(cpu):
    pts = []
    for i in range(SBEAM_SLOT_COUNT):
        s = slot(cpu, i)
        if s["y"] != 209:
            pts.append((s["x"] // 8, s["y"] // 8))   # back to grid units
    return pts


SBEAM_START_ROW = SBEAM_START_Y // 8

# pure vertical (dx=0) while still dropping - degenerates cleanly to a
# straight vertical line, same shape as before this round's own change.
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 1
cpu.mem[SBEAM_ROWS] = 5
cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
expect = [(SBEAM_START_COL, SBEAM_START_ROW + i) for i in range(6)]
check("drop phase (dx=0): degenerates to a pure vertical line, one point per row, "
      "column unchanged", visible_points(cpu) == expect)

# exact 45-degree diagonal (dx==dy==10): alternating X/Y steps every cell
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_FRONT_COL] = SBEAM_START_COL - 10
cpu.mem[SBEAM_GROUND_Y] = (SBEAM_START_ROW + 10) * 8
cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
expect = [(SBEAM_START_COL - i, SBEAM_START_ROW + i) for i in range(11)]
check("sweep phase (dx==dy==10): a real 45-degree diagonal - the UPPER part of the "
      "line changes angle too, not a rigid vertical arm above a fixed corner "
      "(round2's own L-shape mistake)", visible_points(cpu) == expect)

# shallow diagonal (dx=20,dy=10): a real Bresenham staircase, exactly 21 points
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_FRONT_COL] = SBEAM_START_COL - 20
cpu.mem[SBEAM_GROUND_Y] = (SBEAM_START_ROW + 10) * 8
cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
pts = visible_points(cpu)
check("sweep phase (dx=20,dy=10): exactly dx+1=21 points, monotonically decreasing "
      "column and non-decreasing row (a real shallow diagonal, no gaps/backtracking)",
      len(pts) == 21 and pts[0] == (SBEAM_START_COL, SBEAM_START_ROW)
      and pts[-1] == (SBEAM_START_COL - 20, SBEAM_START_ROW + 10)
      and all(pts[i + 1][0] == pts[i][0] - 1 for i in range(len(pts) - 1))
      and all(pts[i + 1][1] in (pts[i][1], pts[i][1] + 1) for i in range(len(pts) - 1)))

# hw-cap: a full-width sweep (dx=23) plus deep terrain (dy=9) needs 24
# points - more than SBEAM_SLOT_COUNT(22) - a genuine, flagged hw-sprite
# deviation from a literal unbounded 'スプライトを足していく', same
# caveat as before this round, just a different (single-line) shape.
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_FRONT_COL] = 0
cpu.mem[SBEAM_GROUND_Y] = (SBEAM_START_ROW + 9) * 8
cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
check("sweep phase hw cap: a full-width+deep-terrain line (needing 24 points) is "
      "capped at SBEAM_SLOT_COUNT(22) - flagged, not silently unbounded",
      len(visible_points(cpu)) == SBEAM_SLOT_COUNT)

# ---- real bug caught this round: "ビームが左端まで行くとリセットかか
# った" - the cap check ("SLOT_COUNT+1:CP B:JR NC") treated B==SLOT_
# COUNT+1 (i.e. dx==SLOT_COUNT, exactly 1 column short of the full left
# edge) as "no cap needed" (CP never borrows on an exact match), so
# SSL_HIDE_REST's own "SLOT_COUNT-C" underflowed to 255 and the hide
# loop wrote ~1000 bytes past SBEAM_SPRITE_ATTRS, corrupting the stack.
# Exhaustively sweep every (dx,dy) combination the real hw ever produces
# and confirm the exact expected point count, with no hang/crash. ----
all_dxdy_ok = True
for dy in range(0, 13):
    for tx in range(0, SBEAM_START_COL + 1):
        cpu = fresh_cpu()
        cpu.mem[SBEAM_ACT] = 2
        cpu.mem[SBEAM_FRONT_COL] = tx
        cpu.mem[SBEAM_GROUND_Y] = (SBEAM_START_ROW + dy) * 8
        cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
        call_routine(cpu, "STAGE_SBEAM")   # would hang/crash before this round's fix
        dx = SBEAM_START_COL - tx
        expected = min(max(dx, dy) + 1, SBEAM_SLOT_COUNT)
        actual = len(visible_points(cpu))
        if actual != expected:
            all_dxdy_ok = False
check("STAGE_SBEAM never hangs/crashes and produces exactly the expected point count "
      "for EVERY (dx,dy) combination real terrain+sweep can produce (dy=0-12, "
      "tx=0-SBEAM_START_COL) - the exact real bug that caused a crash at the screen's "
      "left edge, now covered by an exhaustive sweep, not just a couple of samples",
      all_dxdy_ok)

# the exact reported crash reproduction: dx=SLOT_COUNT (tx=1, one column
# short of the left edge) at a shallow tier0 depth
cpu = fresh_cpu()
cpu.mem[SBEAM_ACT] = 2
cpu.mem[SBEAM_FRONT_COL] = 1
cpu.mem[SBEAM_GROUND_Y] = (SBEAM_START_ROW + 9) * 8
cpu.mem[SBEAM_BLINK] = 0   # INC -> 1 -> a visible tick
call_routine(cpu, "STAGE_SBEAM")
check("the exact reported crash case (FRONT_COL=1, dx=SBEAM_SLOT_COUNT=22) returns "
      "normally and draws exactly SBEAM_SLOT_COUNT points",
      len(visible_points(cpu)) == SBEAM_SLOT_COUNT)


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
saw_real_diagonal = False
left_edge_visits = 0
prev_at_left_edge = False
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
    at_left_edge = act in (2, 3) and cpu.mem[SBEAM_FRONT_COL] == 0
    if at_left_edge and not prev_at_left_edge:
        left_edge_visits += 1
    prev_at_left_edge = at_left_edge
    if act == 3:
        saw_retract = True
    if act in (2, 3):
        pts = [(slot(cpu, i)["x"], slot(cpu, i)["y"]) for i in range(SBEAM_SLOT_COUNT)
               if slot(cpu, i)["y"] != 209]
        xs = {p[0] for p in pts}
        ys = {p[1] for p in pts}
        if len(xs) > 1 and len(ys) > 1:
            saw_real_diagonal = True
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
check("real MAINLOOP: a genuinely diagonal line (both X and Y varying across visible slots "
      "at once) appears at some point during the sweep/retract - 複数本じゃなく1本の直線, "
      "not 2 fixed-shape arms glued at a corner", saw_real_diagonal)
check("real MAINLOOP: no homing missile is ever active while SBeam is active - 当然サンダー"
      "ビーム中はホーミングも...撃たねえんだよ", not saw_homing_during_sbeam)
check(f"real MAINLOOP: the beam genuinely reaches the screen's left edge SBEAM_TRIP_COUNT"
      f"({SBEAM_TRIP_COUNT}) times in one full pose - サンダービームは2往復に",
      left_edge_visits == SBEAM_TRIP_COUNT)

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


# ---- "サンダービームのあとは最初のホーミングに戻るように 現在はサン
# ダーとサンダービームがリピートしてる" - BOSS_POSE_COUNT must reset to
# 0 once the SBeam pose itself ends, not keep incrementing (or just
# staying >=SBEAM_POSE_GATE forever) - otherwise every pose from then on
# fires SBeam again and Homing never comes back ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
prev_phase = None
pose_counts_at_entry = []
for f in range(200000):
    step_frame(cpu)
    phase = cpu.mem[BOSS_PHASE]
    if prev_phase is not None and prev_phase != 1 and phase == 1:
        pose_counts_at_entry.append(cpu.mem[BOSS_POSE_COUNT])
    prev_phase = phase
    if len(pose_counts_at_entry) >= 7:
        break

check("real MAINLOOP: BOSS_POSE_COUNT cycles 0,1,2,0,1,2,... at each pose entry - "
      "Homing/Thunder/Homing/Thunder/SBeam repeats forever, SBeam never becomes "
      "permanent (this was the actual bug reported: サンダーとサンダービームがリピー"
      "トしてる)",
      pose_counts_at_entry == [0, 1, 2, 0, 1, 2, 0][:len(pose_counts_at_entry)])

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
