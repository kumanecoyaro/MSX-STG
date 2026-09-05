"""Verifies the boss entrance "materialize" effect (round36-14
follow-up#22 - "ではワイプ処理はやめる 変わりに出現時の初期位置は今の
ままで 1フレームごとに左端、右端から交互に表示位置を変えながら中央
まで繰り返す 点滅しながら中央で実態化みたいな演出 その間5秒として
中央への移動量を割り出してくれ その後初期位置までまた戻って攻撃に
移る"), which replaces the earlier transparent-sprite scanline-priority
"wipe" (follow-up#18-#21, see git history / HANDOFF.md for that design -
fully retired, no dummy sprites or extra hw sprite slots involved any
more).

The boss's own real body (BOSS_X/BOSS_Y, drawn via the same DRAW_BOSS/
FLUSH_BOSS_SPRITES tail every other patrol step uses) is redrawn every
raw frame at one of two X candidates - a left one and a right one, both
converging toward BOSS_MATERIALIZE_CENTER_X as GAME_TICK advances past
BOSS_SPAWN_TICK - alternating every single raw frame via TICK's own low
bit. BOSS_Y never changes. Once converged, the boss glides back out to
BOSS_SPAWNX at ordinary BOSS_SPEED with no flicker, then hands off to
normal UBA_ACTIVE patrol.

A companion tone SFX ("G2でオクターブ下げて" from the audition page) is
retriggered periodically during the converging phase - see
SOUND_BOSS_MATERIALIZE's own comment. z80emu.py has no PSG emulation
(only the VDP ports do anything - see boss_boom_sound_test.py's own
comment for the established precedent), so what's verified is the
resulting envelope RAM state (SND_TIMER/SND_DECAY/SND_NOISE/
SND_EXPLODING/SND_BOOM_DECAY_CTR), not the actual PSG register writes -
this is also the first tone sound in the file whose period needs the
12-bit register1 high nibble (period 380 > 255), which can't be
observed at all through this harness; only the code review + a real
listen confirms that part.
"""
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


BOSS_MATERIALIZE_CENTER_X = sym["BOSS_MATERIALIZE_CENTER_X"]
BOSS_MATERIALIZE_AMP_START = sym["BOSS_MATERIALIZE_AMP_START"]
BOSS_MATERIALIZE_STEP_PX = sym["BOSS_MATERIALIZE_STEP_PX"]
BOSS_MATERIALIZE_TICKS = sym["BOSS_MATERIALIZE_TICKS"]
BOSS_MATERIALIZE_SND_RETRIGGER = sym["BOSS_MATERIALIZE_SND_RETRIGGER"]
BOSS_MATERIALIZE_ACT = sym["BOSS_MATERIALIZE_ACT"]
BOSS_MATERIALIZE_SND_CTR = sym["BOSS_MATERIALIZE_SND_CTR"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_SPAWN_TICK = sym["BOSS_SPAWN_TICK"]
BOSS_SPEED = sym["BOSS_SPEED"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_HP = sym["BOSS_HP"]
BOSS_BROKEN_HP_THRESHOLD = sym["BOSS_BROKEN_HP_THRESHOLD"]
GAME_TICK = sym["GAME_TICK"]
TICK = sym["TICK"]
SND_TIMER = sym["SND_TIMER"]
SND_DECAY = sym["SND_DECAY"]
SND_NOISE = sym["SND_NOISE"]
SND_EXPLODING = sym["SND_EXPLODING"]
SND_BOOM_DECAY_CTR = sym["SND_BOOM_DECAY_CTR"]
BOSS_BOOM_DECAY_PERIOD = sym["BOSS_BOOM_DECAY_PERIOD"]
BOSS_EXPL_CX = sym["BOSS_EXPL_CX"]
BOSS_EXPL_CY = sym["BOSS_EXPL_CY"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_POSE_TICKS = sym["BOSS_POSE_TICKS"]
BOSS_POSE_END_TICK = sym["BOSS_POSE_END_TICK"]
BULLET0_ACT = sym["BULLET0_ACT"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def get_game_tick(cpu):
    return cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)


def expected_offset(ticks_elapsed):
    return BOSS_MATERIALIZE_AMP_START - BOSS_MATERIALIZE_STEP_PX * ticks_elapsed


assert BOSS_EXPL_CX == BOSS_MATERIALIZE_ACT and BOSS_EXPL_CY == BOSS_MATERIALIZE_SND_CTR, \
    "test assumption (BOSS_MATERIALIZE_ACT/SND_CTR alias BOSS_EXPL_CX/CY) no longer holds"

check("BOSS_MATERIALIZE_CENTER_X is BOSS_SPAWNX/2 (screen-centered X for "
      "the 64px-wide body)", BOSS_MATERIALIZE_CENTER_X == BOSS_SPAWNX // 2)
check("BOSS_MATERIALIZE_AMP_START equals BOSS_MATERIALIZE_CENTER_X (the "
      "left starting edge is X=0, so distance-to-center == center itself)",
      BOSS_MATERIALIZE_AMP_START == BOSS_MATERIALIZE_CENTER_X)
check("BOSS_MATERIALIZE_STEP_PX*BOSS_MATERIALIZE_TICKS exactly consumes "
      "BOSS_MATERIALIZE_AMP_START with zero remainder",
      BOSS_MATERIALIZE_STEP_PX * BOSS_MATERIALIZE_TICKS == BOSS_MATERIALIZE_AMP_START)


def slot_left_right(cpu, ticks_elapsed):
    off = expected_offset(ticks_elapsed)
    return BOSS_MATERIALIZE_CENTER_X - off, BOSS_MATERIALIZE_CENTER_X + off


# ---- TRIGGER_BOSS_MATERIALIZE ----
cpu = fresh_cpu()
cpu.mem[BOSS_MATERIALIZE_ACT] = 0
cpu.mem[BOSS_MATERIALIZE_SND_CTR] = 55
call_routine(cpu, "TRIGGER_BOSS_MATERIALIZE")
check("TRIGGER_BOSS_MATERIALIZE sets BOSS_MATERIALIZE_ACT=1",
      cpu.mem[BOSS_MATERIALIZE_ACT] == 1)
check("TRIGGER_BOSS_MATERIALIZE resets BOSS_MATERIALIZE_SND_CTR to 0 (forces "
      "an immediate toll on the very next UPDATE call)",
      cpu.mem[BOSS_MATERIALIZE_SND_CTR] == 0)

# ---- UPDATE_BOSS_MATERIALIZE: no-op while inactive ----
cpu = fresh_cpu()
cpu.mem[BOSS_MATERIALIZE_ACT] = 0
x0 = cpu.mem[BOSS_X]
call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
check("UPDATE_BOSS_MATERIALIZE does nothing while BOSS_MATERIALIZE_ACT=0",
      cpu.mem[BOSS_X] == x0)

# ---- phase 1: converging - BOSS_X matches the expected left/right
# candidate at several points in the window, alternating by TICK parity,
# and BOSS_Y never moves ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
cpu.mem[BOSS_MATERIALIZE_ACT] = 1
cpu.mem[BOSS_MATERIALIZE_SND_CTR] = 50
y_before = cpu.mem[BOSS_Y]
all_match = True
for ticks_elapsed in (0, 1, 5, 15, BOSS_MATERIALIZE_TICKS - 1):
    set_game_tick(cpu, BOSS_SPAWN_TICK + ticks_elapsed)
    left, right = slot_left_right(cpu, ticks_elapsed)
    for tick_parity, expected in ((0, left), (1, right)):
        cpu.mem[TICK] = tick_parity
        call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
        if cpu.mem[BOSS_X] != expected & 0xFF:
            all_match = False
            print(f"  mismatch: ticks_elapsed={ticks_elapsed} parity={tick_parity} "
                  f"expected={expected} got={cpu.mem[BOSS_X]}")
check("UPDATE_BOSS_MATERIALIZE draws BOSS_X at the exact computed left/right "
      "candidate (AMP_START-STEP_PX*ticks_elapsed offset from center) for "
      "every sampled point in the converging window, both TICK parities",
      all_match)
check("UPDATE_BOSS_MATERIALIZE never touches BOSS_Y during convergence "
      "(\"出現時の初期位置は今のままで\" - only X moves)",
      cpu.mem[BOSS_Y] == y_before)
check("BOSS_MATERIALIZE_ACT stays 1 throughout convergence (still short of "
      "BOSS_MATERIALIZE_TICKS)", cpu.mem[BOSS_MATERIALIZE_ACT] == 1)

# ---- phase 1 -> transition: at ticks_elapsed==BOSS_MATERIALIZE_TICKS, the
# boss settles EXACTLY at center (no leftover rounding) and advances to
# phase 2 ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK + BOSS_MATERIALIZE_TICKS)
cpu.mem[BOSS_MATERIALIZE_ACT] = 1
cpu.mem[BOSS_MATERIALIZE_SND_CTR] = 50
call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
check("UPDATE_BOSS_MATERIALIZE settles BOSS_X to exactly BOSS_MATERIALIZE_"
      "CENTER_X once the window elapses (no partial-pixel leftover)",
      cpu.mem[BOSS_X] == BOSS_MATERIALIZE_CENTER_X)
check("UPDATE_BOSS_MATERIALIZE advances BOSS_MATERIALIZE_ACT to 2 (returning) "
      "the instant convergence completes", cpu.mem[BOSS_MATERIALIZE_ACT] == 2)

# ---- phase 2: plain glide back to BOSS_SPAWNX at BOSS_SPEED, no flicker,
# finishing by clearing BOSS_MATERIALIZE_ACT to 0 ----
cpu = fresh_cpu()
cpu.mem[BOSS_MATERIALIZE_ACT] = 2
cpu.mem[BOSS_X] = BOSS_MATERIALIZE_CENTER_X
steps = 0
xs = []
while cpu.mem[BOSS_MATERIALIZE_ACT] != 0 and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
    xs.append(cpu.mem[BOSS_X])
    steps += 1
expected_steps = -(-(BOSS_SPAWNX - BOSS_MATERIALIZE_CENTER_X) // BOSS_SPEED)  # ceil div
check(f"the return leg takes the expected number of UPDATE_BOSS_MATERIALIZE "
      f"calls ({expected_steps}) to cover BOSS_MATERIALIZE_CENTER_X -> "
      "BOSS_SPAWNX at BOSS_SPEED", steps == expected_steps)
check("the return leg's own steps are monotonically increasing by exactly "
      "BOSS_SPEED each frame (no flicker - a single smooth glide)",
      all(xs[i] - xs[i - 1] == BOSS_SPEED for i in range(1, len(xs) - 1)))
check("BOSS_X lands exactly on BOSS_SPAWNX at the end of the return leg "
      "(clamped, not overshot)", xs[-1] == BOSS_SPAWNX)
check("BOSS_MATERIALIZE_ACT reaches exactly 0 once the boss is back at "
      "BOSS_SPAWNX", cpu.mem[BOSS_MATERIALIZE_ACT] == 0)


def slot_bytes_unused():
    pass  # no dummy hw sprites in this design - nothing to check here


# ---- toll sound retrigger cadence during phase 1 ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
cpu.mem[BOSS_MATERIALIZE_ACT] = 1
cpu.mem[BOSS_MATERIALIZE_SND_CTR] = 0   # forces an immediate toll
cpu.mem[SND_TIMER] = 0
cpu.mem[SND_DECAY] = 1
cpu.mem[SND_NOISE] = 0
cpu.mem[SND_EXPLODING] = 1
call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
check("UPDATE_BOSS_MATERIALIZE retriggers SOUND_BOSS_MATERIALIZE when "
      "SND_CTR reaches 0 (SND_TIMER re-armed to 15)", cpu.mem[SND_TIMER] == 15)
check("...boom-mode sentinel set (SND_DECAY=0)", cpu.mem[SND_DECAY] == 0)
check("...BOSS_BOOM_DECAY_PERIOD loaded into SND_BOOM_DECAY_CTR (shares the "
      "same slow-decay mechanism as SOUND_BOSS_BOOM/SOUND_THUNDER)",
      cpu.mem[SND_BOOM_DECAY_CTR] == BOSS_BOOM_DECAY_PERIOD)
check("...duty gate enabled (SND_NOISE=1 - \"デューティゲート\" applied to a "
      "TONE channel, same technique SOUND_SBEAM already uses)",
      cpu.mem[SND_NOISE] == 1)
check("...SND_EXPLODING NOT set (repeating-trigger sound, same convention "
      "as SOUND_THUNDER, not a one-shot SOUND_BOSS_BOOM-style explosion)",
      cpu.mem[SND_EXPLODING] == 0)
check("SND_CTR reloads to BOSS_MATERIALIZE_SND_RETRIGGER-1 right after a toll",
      cpu.mem[BOSS_MATERIALIZE_SND_CTR] == BOSS_MATERIALIZE_SND_RETRIGGER - 1)

# drive it forward and confirm it does NOT retrigger again until the full
# retrigger interval has elapsed
cpu2 = fresh_cpu()
set_game_tick(cpu2, BOSS_SPAWN_TICK)
cpu2.mem[BOSS_MATERIALIZE_ACT] = 1
cpu2.mem[BOSS_MATERIALIZE_SND_CTR] = 0
call_routine(cpu2, "UPDATE_BOSS_MATERIALIZE")  # consumes the first toll
retrigger_ticks = []
for _ in range(BOSS_MATERIALIZE_SND_RETRIGGER * 2):
    before = cpu2.mem[SND_TIMER]
    cpu2.mem[SND_TIMER] = 3   # simulate natural decay between calls
    call_routine(cpu2, "UPDATE_BOSS_MATERIALIZE")
    retrigger_ticks.append(cpu2.mem[SND_TIMER] == 15)
first_retrigger_at = retrigger_ticks.index(True) if True in retrigger_ticks else -1
check(f"the toll does not retrigger again until BOSS_MATERIALIZE_SND_RETRIGGER "
      f"({BOSS_MATERIALIZE_SND_RETRIGGER}) raw frames have passed (first "
      f"retrigger observed at +{first_retrigger_at + 1})",
      first_retrigger_at == BOSS_MATERIALIZE_SND_RETRIGGER - 1)

# ---- S2_BOSS_SPAWN triggers the effect as part of the real spawn sequence ----
cpu = fresh_cpu()
cpu.mem[BOSS_MATERIALIZE_ACT] = 0
call_routine(cpu, "S2_BOSS_SPAWN")
check("S2_BOSS_SPAWN itself calls TRIGGER_BOSS_MATERIALIZE (ACT=1 right "
      "after spawning)", cpu.mem[BOSS_MATERIALIZE_ACT] == 1)
check("S2_BOSS_SPAWN's own boss-activation flag is also set, confirming this "
      "is really the real spawn routine and not some other path",
      cpu.mem[BOSS_ACT] == 1)

# ---- UBA_ACTIVE freezes the boss entirely while the effect is active,
# resumes once it clears ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
check("BOSS_MATERIALIZE_ACT is nonzero right after spawn (the freeze should "
      "be in effect)", cpu.mem[BOSS_MATERIALIZE_ACT] != 0)
phase0 = cpu.mem[sym["BOSS_PHASE"]]
dir0 = cpu.mem[sym["BOSS_DIR"]]
for _ in range(10):
    call_routine(cpu, "UBA_ACTIVE")
check("UBA_ACTIVE leaves BOSS_PHASE/BOSS_DIR untouched while the effect is "
      "active (UPDATE_BOSS_MATERIALIZE owns BOSS_X on its own, separately)",
      cpu.mem[sym["BOSS_PHASE"]] == phase0 and cpu.mem[sym["BOSS_DIR"]] == dir0)

cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_MATERIALIZE_ACT] = 0   # simulate the effect having already finished
call_routine(cpu, "UBA_ACTIVE")
check("UBA_ACTIVE actually moves the boss once BOSS_MATERIALIZE_ACT is 0 "
      "(BOSS_X changes from its spawn value - patrol has resumed)",
      cpu.mem[BOSS_X] != BOSS_SPAWNX or cpu.mem[BOSS_Y] != BOSS_SPAWN_Y)

# ---- UBA_MOVE_RIGHT (first-attack pose entry) still force-stops the
# effect as a defensive safety net - expected unreachable in practice
# since UBA_ACTIVE stays frozen the whole time the effect is active ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_MATERIALIZE_ACT] = 1
call_routine(cpu, "UBA_MOVE_RIGHT")
check("UBA_MOVE_RIGHT also clears BOSS_MATERIALIZE_ACT (defensive safety net)",
      cpu.mem[BOSS_MATERIALIZE_ACT] == 0)

# ---- real-hardware bug fix carried forward from follow-up#20 ("爆発の
# キャラが消えてる"): TRIGGER_BOSS_BROKEN_FORM/INIT_BOSS_EXPLOSION both
# write BOSS_EXPL_CX/CY, which still alias BOSS_MATERIALIZE_ACT/SND_CTR -
# both must force-stop the effect FIRST, and UPDATE_BOSS_MATERIALIZE must
# never touch these bytes again once BOSS_FORM leaves 0.
# BOSS_X is deliberately forced to a MID-convergence value (not already
# sitting at BOSS_SPAWNX) before triggering: if BOSS_MATERIALIZE_ACT ends
# up holding an arbitrary nonzero cell-column value (not literally 1 or
# 2) and the BOSS_FORM gate were missing, UPDATE_BOSS_MATERIALIZE's own
# `DEC A : JR NZ,UBM_RETURNING` dispatch would misroute it into the
# "returning" phase and start stepping BOSS_X toward BOSS_SPAWNX - a
# real, visible corruption this setup can actually catch (an earlier
# draft of this test left BOSS_X already AT BOSS_SPAWNX, where that same
# misrouted "returning" step happens to self-correct back to ACT=0 on
# its very first call and silently masks the very bug it was meant to
# catch - confirmed by temporarily removing the real gate and rerunning). ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_X] = 50   # mid-convergence, well short of BOSS_SPAWNX(192)
cpu.mem[BOSS_HP] = BOSS_BROKEN_HP_THRESHOLD
call_routine(cpu, "TRIGGER_BOSS_BROKEN_FORM")
check("BOSS_FORM actually left 0 (SPARK) after the trigger - the gate this "
      "test is exercising only matters once this is true",
      cpu.mem[BOSS_FORM] != 0)
cx_after_trigger = cpu.mem[BOSS_EXPL_CX]
cy_after_trigger = cpu.mem[BOSS_EXPL_CY]
x_after_trigger = cpu.mem[BOSS_X]
stayed_stable = True
for _ in range(60):
    call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
    if (cpu.mem[BOSS_EXPL_CY] != cy_after_trigger
            or cpu.mem[BOSS_EXPL_CX] != cx_after_trigger
            or cpu.mem[BOSS_X] != x_after_trigger):
        stayed_stable = False
        break
check("UPDATE_BOSS_MATERIALIZE never touches BOSS_EXPL_CX/CY or BOSS_X "
      "again once BOSS_FORM!=0, across 60 more direct calls, even with "
      "BOSS_X left mid-convergence and BOSS_EXPL_CX now a legitimate "
      "nonzero cell coordinate that could otherwise be misread as an "
      "in-progress phase", stayed_stable)

cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
# STOP_BOSS_MATERIALIZE's own clearing is immediately overwritten again by
# this SAME routine's later BOSS_EXPL_CX/CY write (a real cell coordinate),
# so its effect isn't independently observable from a single isolated call
# like this one - what IS observable, and what actually matters, is that
# INIT_BOSS_EXPLOSION runs through to completion and produces a real,
# sane cell-row value (0-23) rather than some leftover materialize-phase
# garbage (the old wipe bug's own symptom was exactly a pixel-range value
# like 40-184 landing in this byte instead of a valid cell row).
BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
call_routine(cpu, "INIT_BOSS_EXPLOSION")
check("INIT_BOSS_EXPLOSION runs through to completion (BOSS_EXPL_STATE "
      "actually advances) after force-stopping the materialize effect first",
      cpu.mem[BOSS_EXPL_STATE] != 0)
check("BOSS_EXPL_CY ends up a sane cell-row value (0-23), not leftover "
      "materialize-phase garbage", 0 <= cpu.mem[BOSS_EXPL_CY] <= 23)

# ---- end-to-end real-time confirmation: a real MAINLOOP run from spawn
# through the full effect, confirming BOSS_Y never leaves BOSS_SPAWN_Y,
# the boss really does pass through BOSS_MATERIALIZE_CENTER_X, and it's
# back at BOSS_SPAWNX with patrol resumed well before the boss could ever
# reach its own first attack pose ----
cpu = fresh_cpu()
spawned_at = None
for i in range(9000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and spawned_at is None:
        spawned_at = i
        break
check("real MAINLOOP: boss spawns", spawned_at is not None)

saw_center = False
y_ever_moved = False
y0 = cpu.mem[BOSS_Y]
returned_at = None
for j in range(600):
    step_frame(cpu)
    if cpu.mem[BOSS_Y] != y0:
        y_ever_moved = True
    if cpu.mem[BOSS_X] == BOSS_MATERIALIZE_CENTER_X:
        saw_center = True
    if cpu.mem[BOSS_MATERIALIZE_ACT] == 0 and returned_at is None:
        returned_at = j
        break
check("real MAINLOOP: BOSS_Y never leaves BOSS_SPAWN_Y for the whole "
      "entrance sequence (\"出現時の初期位置は今のままで\" - only X moves)",
      not y_ever_moved)
check("real MAINLOOP: the boss actually passes through BOSS_MATERIALIZE_"
      "CENTER_X at some point (真に中央で実体化する)", saw_center)
check("real MAINLOOP: the effect finishes (BOSS_MATERIALIZE_ACT back to 0, "
      "boss back at BOSS_SPAWNX) within the expected window",
      returned_at is not None)
if returned_at is not None:
    check("real MAINLOOP: the boss is back exactly at BOSS_SPAWNX once the "
          "effect finishes", cpu.mem[BOSS_X] == BOSS_SPAWNX)

# ---- follow-up#23 ("まずマテリアライズ中はボスコリジョン無効") - a
# bullet that would normally hit the boss must NOT register while the
# entrance materialize effect is still running, in either phase - BOSS_X
# isn't the boss's real, stable footprint yet during that whole window,
# it's being driven every frame by UPDATE_BOSS_MATERIALIZE itself. Follows
# boss_collision_test.py's own make_boss/make_bullet + CHECK_BULLET_VS_
# BOSS pattern.
def make_boss(cpu, x=100, hp=None):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_HP] = hp if hp is not None else 255
    cpu.mem[sym["BOSS_FLASH_TIMER"]] = 0
    cpu.mem[BOSS_MATERIALIZE_ACT] = 0


def make_bullet(cpu, col, row):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = 1
    cpu.mem[ix + 1] = 0
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    row_addr = 0x1800 + row * 32
    cpu.mem[ix + 4] = row_addr & 0xFF
    cpu.mem[ix + 5] = (row_addr >> 8) & 0xFF
    cpu.mem[ix + 6] = 0


boss_row = BOSS_SPAWN_Y // 8

# control: with the effect NOT running, the existing hit behavior is
# unchanged (sanity check that make_boss/make_bullet here really do land
# a hit, before trusting the "blocked" cases below).
cpu = fresh_cpu()
make_boss(cpu, x=100)
hp_before = cpu.mem[BOSS_HP]
make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("control: a bullet inside the boss's box registers a hit when "
      "BOSS_MATERIALIZE_ACT=0 (materialize not running)",
      cpu.mem[BOSS_HP] == hp_before - 1 and cpu.mem[BULLET0_ACT] == 0)

for act, phase_name in ((1, "phase 1 (converging)"), (2, "phase 2 (returning)")):
    cpu = fresh_cpu()
    make_boss(cpu, x=100)
    cpu.mem[BOSS_MATERIALIZE_ACT] = act
    hp_before = cpu.mem[BOSS_HP]
    make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")
    check(f"a bullet that would otherwise hit is ignored while "
          f"BOSS_MATERIALIZE_ACT={act} ({phase_name}) - no HP loss, "
          f"bullet stays active", cpu.mem[BOSS_HP] == hp_before and cpu.mem[BULLET0_ACT] == 1)

# the gate doesn't leak once the effect actually ends - a hit right after
# ACT drops back to 0 registers normally again.
cpu = fresh_cpu()
make_boss(cpu, x=100)
cpu.mem[BOSS_MATERIALIZE_ACT] = 0
hp_before = cpu.mem[BOSS_HP]
make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("the collision gate does not leak past materialize's own end - a "
      "hit at ACT=0 registers normally", cpu.mem[BOSS_HP] == hp_before - 1)

# regression guard: this exact scenario hung boss_collision_test.py's own
# real end-to-end HP-drain test forever during development of this round
# - once BOSS_FORM leaves 0 (SPARK/ACTIVE), TRIGGER_BOSS_BROKEN_FORM/
# INIT_BOSS_EXPLOSION overwrite BOSS_EXPL_CX/CY (== BOSS_MATERIALIZE_ACT/
# SND_CTR) with a REAL cell coordinate - almost always nonzero - and the
# collision gate above must never mistake that for "materialize still
# running" once that's happened. BOSS_X=100 here produces a genuinely
# nonzero cell coordinate ((100+32)>>3 = 16) if this gate doesn't also
# check BOSS_FORM first.
for form_value, form_name in ((sym["BOSS_FORM_SPARK"], "SPARK"),
                               (sym["BOSS_FORM_ACTIVE"], "ACTIVE")):
    cpu = fresh_cpu()
    make_boss(cpu, x=100)
    cpu.mem[BOSS_FORM] = form_value
    cpu.mem[BOSS_EXPL_CX] = 16   # a real, nonzero cell coordinate - NOT "materialize phase 1"
    hp_before = cpu.mem[BOSS_HP]
    make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")
    check(f"a hit still registers once BOSS_FORM={form_name} even though "
          f"BOSS_EXPL_CX (aliasing BOSS_MATERIALIZE_ACT) holds a real, "
          f"nonzero cell coordinate - the collision gate must not confuse "
          f"this with materialize still running",
          cpu.mem[BOSS_HP] == hp_before - 1)


# ---- follow-up#23 ("その後初期位置に戻ったら現在は左に行って往復するが
# 往復はせず即攻撃に移るように") - the instant UPDATE_BOSS_MATERIALIZE's
# own return leg (phase 2) reaches BOSS_SPAWNX, it must jump straight into
# the attack pose (BOSS_PHASE=1, hand art armed) within that SAME call -
# never leave BOSS_PHASE=0/BOSS_DIR=0 for UBA_ACTIVE to pick up and start
# the ordinary left-edge patrol leg first.
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_MATERIALIZE_ACT] = 2   # phase 2: returning
cpu.mem[BOSS_X] = BOSS_SPAWNX - BOSS_SPEED  # one call away from arrival
cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
tick_before = get_game_tick(cpu)
call_routine(cpu, "UPDATE_BOSS_MATERIALIZE")
check("the return leg's own completing UPDATE_BOSS_MATERIALIZE call lands "
      "BOSS_X exactly on BOSS_SPAWNX", cpu.mem[BOSS_X] == BOSS_SPAWNX)
check("...and clears BOSS_MATERIALIZE_ACT back to 0",
      cpu.mem[BOSS_MATERIALIZE_ACT] == 0)
check("...and enters the attack pose (BOSS_PHASE=1) immediately, within "
      "that same call - no separate UBA_ACTIVE call needed, no ordinary "
      "left-edge patrol leg first", cpu.mem[BOSS_PHASE] == 1)
pose_end_tick = cpu.mem[BOSS_POSE_END_TICK] | (cpu.mem[BOSS_POSE_END_TICK + 1] << 8)
check("...and arms BOSS_POSE_END_TICK the same way the ordinary right-edge "
      "arrival does (GAME_TICK + BOSS_POSE_TICKS)",
      pose_end_tick == (tick_before + BOSS_POSE_TICKS) & 0xFFFF)

# a follow-up UBA_ACTIVE call while parked in this pose must stay in the
# pose (UBA_POSE), never fall into UBA_MOVE_LEFT - i.e. BOSS_X must not
# start decreasing back toward the left edge.
x_in_pose = cpu.mem[BOSS_X]
call_routine(cpu, "UBA_ACTIVE")
check("a follow-up UBA_ACTIVE call while freshly posed stays parked at "
      "BOSS_SPAWNX (still mid-pose, not starting the left-edge patrol leg)",
      cpu.mem[BOSS_X] == x_in_pose == BOSS_SPAWNX)

# end-to-end real-time confirmation: from the real MAINLOOP run, the
# instant the effect finishes, BOSS_X must never subsequently drop below
# BOSS_SPAWNX before the first attack pose actually ends (i.e. no round
# trip to the left edge is ever taken first).
cpu = fresh_cpu()
for i in range(9000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1:
        break
for j in range(600):
    step_frame(cpu)
    if cpu.mem[BOSS_MATERIALIZE_ACT] == 0:
        break
check("real MAINLOOP: the boss is already in the attack pose (BOSS_PHASE=1) "
      "the instant the materialize effect finishes",
      cpu.mem[BOSS_PHASE] == 1)
# BOSS_X must stay pinned exactly at BOSS_SPAWNX for as long as the pose
# itself lasts (UBA_POSE never touches BOSS_X) - the old bug's own
# symptom would be BOSS_X immediately decreasing here instead, since that
# means the ordinary left-edge patrol leg fired first rather than this
# pose. Stop watching the instant the pose itself ends (BOSS_PHASE
# leaves 1) - patrolling left AFTER the first attack is normal, expected
# behavior, not the round trip this test guards against.
never_left_spawn = True
pose_ended = False
for k in range(BOSS_POSE_TICKS * 8 + 16):   # comfortably past BOSS_POSE_TICKS worth of raw frames
    step_frame(cpu)
    if cpu.mem[BOSS_PHASE] != 1:
        pose_ended = True
        break
    if cpu.mem[BOSS_X] < BOSS_SPAWNX:
        never_left_spawn = False
        break
check("real MAINLOOP: the pose actually ends within the expected window "
      "(sanity check that this test observed a real pose, not a stall)",
      pose_ended)
check("real MAINLOOP: BOSS_X never drops below BOSS_SPAWNX for as long as "
      "the first pose itself lasts - the old left-edge round trip never "
      "happens before this first attack", never_left_spawn)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
