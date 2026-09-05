import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

# round36-14 ("ボス登場前に中身が空の透明のスプライトを4枚横に並べて
# ボス登場Y位置の上16pxからボス表示外の64pxまで高速移動 ボスが攻撃に
# 入ったら消す こうする事でボスを16px幅で消すことが出来るんで登場演出に"):
# 4 fully-transparent dummy hw sprites, placed at LOWER attribute-table
# slot indices than the boss's own body, swept vertically through the
# boss's Y range - exploiting the real TMS9918's "only the first 4
# sprites per scanline actually render" priority rule to erase 16px-wide
# vertical strips of the boss's body as they sweep past, for an entrance
# wipe effect.
#
# follow-up#20 ("次にワイプ中は初期停止状態のスプライトでワイプが終わる
# まで停止すること"): the boss no longer patrols while the wipe sweeps
# (UBA_ACTIVE freezes BOSS_X/Y/PHASE/DIR entirely while BOSS_WIPE_ACT!=0).
#
# follow-up#21 ("ボス出現時は5秒停止しワイプを繰り返すように変更"):
# replaced follow-up#20's arbitrary "N laps" stop condition with an
# explicit real-time duration after the boss's own fixed BOSS_SPAWN_TICK
# (995). GAME_TICK is NOT a raw-frame counter, though - it only advances
# once every 8 raw MAINLOOP frames (a separate byte, TICK, is the real
# per-frame counter; GAME_TICK matches the schedule editor's own
# scheduling granularity instead) - an earlier version of this feature
# wrongly assumed GAME_TICK itself ran at 60fps and used 300 directly,
# caught by this file's own real-MAINLOOP timing test actually measuring
# the mismatch. Correct: 5 real seconds = 300 raw frames / 8 = 37.5,
# rounded up to BOSS_WIPE_DURATION_TICKS=38 GAME_TICK units (>=5s, never
# under). BOSS_WIPE_ACT reverted to a plain 0/1 flag; UPDATE_BOSS_WIPE
# now compares the live GAME_TICK against the compile-time constant
# BOSS_WIPE_END_TICK (995+38=1033) every frame, same true 16-bit
# SBC HL,DE idiom as BOSS_POSE_END_TICK/NIGHT_START_TICK/etc. - no
# runtime-captured end-tick RAM needed since the spawn tick is always
# the same fixed schedule constant. This file verifies TRIGGER/UPDATE/
# DRAW/HIDE_BOSS_WIPE_*, the freeze in UBA_ACTIVE, the real end-to-end
# timing, and every call site (S2_BOSS_SPAWN, UBA_MOVE_RIGHT,
# TRIGGER_BOSS_BROKEN_FORM, INIT_BOSS_EXPLOSION) directly.

out, sym, text = get_out()
SAT_BASE = 0x1B00

BOSS_WIPE_SPR_BASE_SLOT = sym["BOSS_WIPE_SPR_BASE_SLOT"]
BOSS_WIPE_SLOTS = sym["BOSS_WIPE_SLOTS"]
BOSS_WIPE_START_Y = sym["BOSS_WIPE_START_Y"]
BOSS_WIPE_END_Y = sym["BOSS_WIPE_END_Y"]
BOSS_WIPE_SPEED = sym["BOSS_WIPE_SPEED"]
BOSS_WIPE_DURATION_TICKS = sym["BOSS_WIPE_DURATION_TICKS"]
BOSS_WIPE_END_TICK = sym["BOSS_WIPE_END_TICK"]
BOSS_WIPE_ACT = sym["BOSS_WIPE_ACT"]
BOSS_WIPE_Y = sym["BOSS_WIPE_Y"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_SPAWN_TICK = sym["BOSS_SPAWN_TICK"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_DIR = sym["BOSS_DIR"]
BOSS_HP = sym["BOSS_HP"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_BROKEN_HP_THRESHOLD = sym["BOSS_BROKEN_HP_THRESHOLD"]
GAME_TICK = sym["GAME_TICK"]

STEPS_PER_LAP = -(-(BOSS_WIPE_END_Y - BOSS_WIPE_START_Y) // BOSS_WIPE_SPEED)  # ceil div


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def get_game_tick(cpu):
    return cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)


check("BOSS_WIPE_SLOTS is 4 (one dummy per 16px band, matching the boss's "
      "own 64px-wide body)", BOSS_WIPE_SLOTS == 4)
check("BOSS_WIPE_START_Y is 16px above BOSS_SPAWN_Y",
      BOSS_WIPE_START_Y == BOSS_SPAWN_Y - 16)
check("BOSS_WIPE_END_Y is past the boss's own 64px-tall body plus a further "
      "64px of clearance", BOSS_WIPE_END_Y == BOSS_SPAWN_Y + 64 + 64)
check("BOSS_WIPE_DURATION_TICKS is 38 GAME_TICK units (38*8=304 raw frames, "
      ">=5 seconds @ this project's assumed 60fps and GAME_TICK's own real "
      "1-per-8-raw-frames rate - NOT 300, which would assume GAME_TICK itself "
      "ran at 60fps)", BOSS_WIPE_DURATION_TICKS == 38)
check("BOSS_WIPE_END_TICK is exactly BOSS_SPAWN_TICK + BOSS_WIPE_DURATION_TICKS "
      "(a compile-time constant, not a captured runtime value)",
      BOSS_WIPE_END_TICK == BOSS_SPAWN_TICK + BOSS_WIPE_DURATION_TICKS)


def slot_bytes(cpu, slot):
    base = SAT_BASE + slot * 4
    return tuple(cpu.vram[base + i] for i in range(4))


# ---- TRIGGER_BOSS_WIPE: plain 0/1 flag again ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 0
cpu.mem[BOSS_WIPE_Y] = 0
call_routine(cpu, "TRIGGER_BOSS_WIPE")
check("TRIGGER_BOSS_WIPE sets BOSS_WIPE_ACT=1", cpu.mem[BOSS_WIPE_ACT] == 1)
check("TRIGGER_BOSS_WIPE resets BOSS_WIPE_Y to BOSS_WIPE_START_Y",
      cpu.mem[BOSS_WIPE_Y] == BOSS_WIPE_START_Y & 0xFF)

# ---- DRAW_BOSS_WIPE_SPRITES / WRITE_BOSS_WIPE_ALL: correct slots/X/Y,
# fully transparent (pattern=0, color=0) ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_Y] = 77
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
expected_x = [(BOSS_SPAWNX + 16 * i) & 0xFF for i in range(4)]
all_slots_ok = True
for i in range(4):
    y, x, pat, col = slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)
    if y != 77 or x != expected_x[i] or pat != 0 or col != 0:
        all_slots_ok = False
check("DRAW_BOSS_WIPE_SPRITES writes all 4 slots (4..7) with the current Y, "
      "16px-apart X columns starting at BOSS_SPAWNX, and fully transparent "
      "pattern=0/color=0", all_slots_ok)

# a slot outside the 4 dummy sprites must be untouched - it's part of
# BULLET_U_SPR_BASE_SLOT's own pool (slot8 = BULLET_U_SPR_BASE_SLOT+1),
# already hidden (Y=209) by boot init, same as any other idle diagonal-
# shot slot; the only claim being tested here is that DRAW_BOSS_WIPE_
# SPRITES leaves it exactly as boot left it, not that it's all-zero.
cpu2 = fresh_cpu()
before = slot_bytes(cpu2, BOSS_WIPE_SPR_BASE_SLOT + 4)
call_routine(cpu2, "DRAW_BOSS_WIPE_SPRITES")
after = slot_bytes(cpu2, BOSS_WIPE_SPR_BASE_SLOT + 4)
check("DRAW_BOSS_WIPE_SPRITES does not touch the slot right after its own "
      "4 (BOSS_WIPE_SPR_BASE_SLOT+4, part of BULLET_U's own pool)",
      before == after)

# ---- HIDE_BOSS_WIPE_SPRITES: Y=209 (off-screen), same convention as
# every other hidden hw sprite in this file (e.g. HIDE_BOSS_SPRITES) ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_Y] = 100
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
call_routine(cpu, "HIDE_BOSS_WIPE_SPRITES")
all_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("HIDE_BOSS_WIPE_SPRITES sets all 4 slots' Y to 209 (off-screen)", all_hidden)
check("HIDE_BOSS_WIPE_SPRITES does not touch BOSS_WIPE_Y itself (only the "
      "VRAM attribute table)", cpu.mem[BOSS_WIPE_Y] == 100)

# ---- UPDATE_BOSS_WIPE: no-op while inactive ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 0
cpu.mem[BOSS_WIPE_Y] = 55
call_routine(cpu, "UPDATE_BOSS_WIPE")
check("UPDATE_BOSS_WIPE does nothing while BOSS_WIPE_ACT=0 (Y untouched)",
      cpu.mem[BOSS_WIPE_Y] == 55)

# ---- UPDATE_BOSS_WIPE: advances Y by BOSS_WIPE_SPEED and draws while
# still well within the 5-second window ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = BOSS_WIPE_START_Y & 0xFF
call_routine(cpu, "UPDATE_BOSS_WIPE")
check("UPDATE_BOSS_WIPE advances BOSS_WIPE_Y by BOSS_WIPE_SPEED while still "
      "well within the 5-second window",
      cpu.mem[BOSS_WIPE_Y] == (BOSS_WIPE_START_Y + BOSS_WIPE_SPEED) & 0xFF)
check("UPDATE_BOSS_WIPE does not touch BOSS_WIPE_ACT while still active",
      cpu.mem[BOSS_WIPE_ACT] == 1)
mid_slots_ok = all(
    slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == (BOSS_WIPE_START_Y + BOSS_WIPE_SPEED) & 0xFF
    for i in range(4))
check("UPDATE_BOSS_WIPE actually redraws all 4 slots to the new Y mid-sweep",
      mid_slots_ok)

# ---- UPDATE_BOSS_WIPE: keeps wrapping back to BOSS_WIPE_START_Y for as
# many laps as fit within the 5-second window - "1回だけではなく...継続
# してループ" (follow-up#19) still holds under the duration-based design.
# GAME_TICK must be advanced by hand between calls here (call_routine
# alone never advances it - only real MAINLOOP/step_frame does) ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = BOSS_WIPE_START_Y & 0xFF
lap_ys = []
for lap in range(3):
    for _ in range(STEPS_PER_LAP):
        call_routine(cpu, "UPDATE_BOSS_WIPE")
        set_game_tick(cpu, get_game_tick(cpu) + 1)
    lap_ys.append(cpu.mem[BOSS_WIPE_Y])
check(f"each of 3 laps takes the expected number of UPDATE_BOSS_WIPE calls "
      f"({STEPS_PER_LAP}) and wraps back to BOSS_WIPE_START_Y instead of "
      "stopping (well within the 5-second window so far)",
      all(y == BOSS_WIPE_START_Y & 0xFF for y in lap_ys))
check("BOSS_WIPE_ACT is still 1 after 3 laps - the duration window, not lap "
      "count, is what eventually stops this", cpu.mem[BOSS_WIPE_ACT] == 1)
still_visible = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == BOSS_WIPE_START_Y & 0xFF
                     for i in range(4))
check("the 4 dummy sprites are still being drawn (not hidden) mid-window",
      still_visible)

# ---- once GAME_TICK reaches BOSS_WIPE_END_TICK, UPDATE_BOSS_WIPE stops
# itself for good regardless of where in a lap it is - no separate
# STOP_BOSS_WIPE call needed ----
set_game_tick(cpu, BOSS_WIPE_END_TICK)
call_routine(cpu, "UPDATE_BOSS_WIPE")
check("BOSS_WIPE_ACT reaches exactly 0 once GAME_TICK reaches BOSS_WIPE_END_TICK",
      cpu.mem[BOSS_WIPE_ACT] == 0)
final_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("UPDATE_BOSS_WIPE hides all 4 slots (Y=209) itself the instant the "
      "5-second window elapses", final_hidden)
set_game_tick(cpu, get_game_tick(cpu) + 1)
call_routine(cpu, "UPDATE_BOSS_WIPE")
stays_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("UPDATE_BOSS_WIPE does not resurrect the sprites on a later frame "
      "(BOSS_WIPE_ACT=0 gate holds, GAME_TICK only ever increases so this "
      "branch can never fire again either)", stays_hidden)

# ---- STOP_BOSS_WIPE: force-stops early, regardless of the duration window ----
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = 90
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
call_routine(cpu, "STOP_BOSS_WIPE")
check("STOP_BOSS_WIPE clears BOSS_WIPE_ACT even well within the 5-second window",
      cpu.mem[BOSS_WIPE_ACT] == 0)
stopped_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("STOP_BOSS_WIPE hides all 4 slots (Y=209)", stopped_hidden)

# ---- S2_BOSS_SPAWN triggers the wipe as part of the real spawn sequence ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 0
call_routine(cpu, "S2_BOSS_SPAWN")
check("S2_BOSS_SPAWN itself calls TRIGGER_BOSS_WIPE (BOSS_WIPE_ACT=1 right "
      "after spawning)", cpu.mem[BOSS_WIPE_ACT] == 1)
check("S2_BOSS_SPAWN's own boss-activation flag is also set, confirming this "
      "is really the real spawn routine and not some other path",
      cpu.mem[BOSS_ACT] == 1)

# ---- follow-up#20 core behavior: UBA_ACTIVE freezes the boss completely
# (position, phase, direction all untouched) for as long as BOSS_WIPE_ACT
# is nonzero - "初期停止状態のスプライトでワイプが終わるまで停止" ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
x0, y0, phase0, dir0 = cpu.mem[BOSS_X], cpu.mem[BOSS_Y], cpu.mem[BOSS_PHASE], cpu.mem[BOSS_DIR]
check("BOSS_WIPE_ACT is nonzero right after spawn (the freeze should be in "
      "effect)", cpu.mem[BOSS_WIPE_ACT] != 0)
for _ in range(50):
    call_routine(cpu, "UBA_ACTIVE")
frozen_ok = (cpu.mem[BOSS_X] == x0 and cpu.mem[BOSS_Y] == y0
             and cpu.mem[BOSS_PHASE] == phase0 and cpu.mem[BOSS_DIR] == dir0)
check("UBA_ACTIVE leaves BOSS_X/BOSS_Y/BOSS_PHASE/BOSS_DIR completely "
      "untouched across 50 calls while the wipe is still active (the boss "
      "stays parked in its initial spawn pose)", frozen_ok)
check("BOSS_WIPE_ACT itself is untouched by UBA_ACTIVE (only UPDATE_BOSS_WIPE "
      "advances it - UBA_ACTIVE only reads it)", cpu.mem[BOSS_WIPE_ACT] == 1)

# ---- once the wipe naturally finishes (the 5-second window elapses on its
# own), UBA_ACTIVE resumes normal patrol movement ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 0   # simulate the wipe having already finished
call_routine(cpu, "UBA_ACTIVE")
check("UBA_ACTIVE actually moves the boss once BOSS_WIPE_ACT is 0 (BOSS_X "
      "changes from its spawn value - patrol has resumed)",
      cpu.mem[BOSS_X] != BOSS_SPAWNX or cpu.mem[BOSS_Y] != BOSS_SPAWN_Y)

# ---- end-to-end real-time confirmation: a real MAINLOOP run from spawn
# through the full window, confirming the boss stays frozen for just
# short of BOSS_WIPE_DURATION_TICKS*8 raw frames after spawning and has
# resumed patrolling shortly after - the actual "5秒停止" claim measured
# in real raw frames, not just the isolated GAME_TICK-level unit tests
# above (this is exactly the kind of check that caught the original
# GAME_TICK-isn't-a-raw-frame-counter bug - see BOSS_WIPE_DURATION_TICKS'
# own comment). RAW_FRAMES_PER_GAME_TICK=8 matches MAINLOOP's own
# `AND 07h` gate around its GAME_TICK advance. UBA_ACTIVE runs BEFORE
# UPDATE_BOSS_WIPE in MAINLOOP's own call order, so BOSS_WIPE_ACT
# clearing and BOSS_X actually starting to move land on two DIFFERENT
# frames (confirmed empirically below), not the same one - the exact
# unfreeze frame is a call-order detail, not part of the "5 seconds"
# spec itself, so this checks "still frozen with margin to spare" and
# "unfrozen with margin to spare" rather than one single exact frame. ----
RAW_FRAMES_PER_GAME_TICK = 8
EXPECTED_UNFREEZE_RAW_FRAMES = BOSS_WIPE_DURATION_TICKS * RAW_FRAMES_PER_GAME_TICK  # 304

cpu = fresh_cpu()
spawned_at = None
for i in range(9000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and spawned_at is None:
        spawned_at = i
        x_at_spawn = cpu.mem[BOSS_X]
        break
check("real MAINLOOP: boss spawns", spawned_at is not None)
for _ in range(EXPECTED_UNFREEZE_RAW_FRAMES - 1):
    step_frame(cpu)
check(f"real MAINLOOP: the boss is STILL frozen at its spawn X just short of "
      f"the expected ~{EXPECTED_UNFREEZE_RAW_FRAMES}-raw-frame window "
      "(BOSS_WIPE_ACT still nonzero)",
      cpu.mem[BOSS_WIPE_ACT] != 0 and cpu.mem[BOSS_X] == x_at_spawn)
for _ in range(3):
    step_frame(cpu)
check("real MAINLOOP: the boss has unfrozen and started patrolling (BOSS_X "
      "has moved away from its spawn value) shortly after the expected "
      "window elapses", cpu.mem[BOSS_WIPE_ACT] == 0 and cpu.mem[BOSS_X] != x_at_spawn)

# ---- UBA_MOVE_RIGHT (first-attack pose entry) still force-stops the wipe
# as a safety net - now normally redundant (the wipe finishes long before
# the boss can ever reach this point while frozen), but still correct if
# ever reached with the window not yet elapsed ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = 90
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
call_routine(cpu, "UBA_MOVE_RIGHT")
safety_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("UBA_MOVE_RIGHT (the boss's first attack-pose entry point) hides the 4 "
      "wipe dummy sprites even mid-sweep, so they can never survive into the "
      "attack phase", safety_hidden)
check("UBA_MOVE_RIGHT also clears BOSS_WIPE_ACT (not just a visual hide)",
      cpu.mem[BOSS_WIPE_ACT] == 0)

# ---- follow-up#20 real-hardware bug fix ("爆発のキャラが消えてる"):
# TRIGGER_BOSS_BROKEN_FORM (HP threshold) and INIT_BOSS_EXPLOSION (HP=0)
# both write BOSS_EXPL_CX/CY, which alias BOSS_WIPE_ACT/BOSS_WIPE_Y - both
# must force-stop the wipe FIRST, or a kill landing while the wipe is
# still sweeping corrupts whichever byte the wipe was still writing ----
BOSS_EXPL_CX = sym["BOSS_EXPL_CX"]
BOSS_EXPL_CY = sym["BOSS_EXPL_CY"]
assert BOSS_EXPL_CX == BOSS_WIPE_ACT and BOSS_EXPL_CY == BOSS_WIPE_Y, \
    "test assumption (BOSS_WIPE_ACT/Y alias BOSS_EXPL_CX/CY) no longer holds"

# NOTE: BOSS_WIPE_ACT/Y ARE BOSS_EXPL_CX/CY (same bytes) - once either
# trigger runs to completion it legitimately overwrites them again with
# the real center-cell coordinate (not necessarily 0), so the only thing
# actually checkable from outside is the dummy sprites' own hidden state
# (STOP_BOSS_WIPE's own visible side effect) - a nonzero recomputed
# BOSS_EXPL_CX afterward is correct, not a regression.
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 1   # wipe still actively sweeping
cpu.mem[BOSS_WIPE_Y] = 90
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
cpu.mem[BOSS_HP] = BOSS_BROKEN_HP_THRESHOLD  # about to cross the threshold
call_routine(cpu, "TRIGGER_BOSS_BROKEN_FORM")
wipe_sprites_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("TRIGGER_BOSS_BROKEN_FORM force-stops the wipe before it repurposes "
      "BOSS_EXPL_CX/CY for its own center-cell coordinate, even when called "
      "while the wipe is still mid-sweep (the 4 dummy sprites end up hidden, "
      "not left showing a stale mid-sweep Y)", wipe_sprites_hidden)

cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = 90
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
call_routine(cpu, "INIT_BOSS_EXPLOSION")
death_wipe_sprites_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("INIT_BOSS_EXPLOSION (the real-death path) also force-stops the wipe "
      "first, for the same reason", death_wipe_sprites_hidden)

# ---- the deeper half of the same real-hardware bug fix: STOP_BOSS_WIPE
# alone is NOT enough. TRIGGER_BOSS_BROKEN_FORM goes on to legitimately
# WRITE a real (near-certainly nonzero) cell coordinate into BOSS_EXPL_CX
# right after stopping the wipe - UPDATE_BOSS_WIPE is still called
# unconditionally every frame from MAINLOOP (gated only on BOSS_ACT!=0,
# with no regard for BOSS_FORM), so without its own BOSS_FORM!=0 gate it
# would see that nonzero byte on the very next frame and think the wipe
# had somehow reactivated, then spend the rest of the fight stomping
# BOSS_EXPL_CY with sweep values every single frame - this is the actual
# "爆発のキャラが消えてる" symptom (corrupted center-cell -> BG writes
# land at garbage addresses). Drive many real frames PAST the trigger
# and confirm BOSS_EXPL_CY is never touched again by anything wipe-
# related once BOSS_FORM has left 0. ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = 90
cpu.mem[BOSS_HP] = BOSS_BROKEN_HP_THRESHOLD
call_routine(cpu, "TRIGGER_BOSS_BROKEN_FORM")
check("BOSS_FORM actually left 0 (SPARK) after the trigger - the gate this "
      "test is exercising only matters once this is true",
      cpu.mem[BOSS_FORM] != 0)
cy_after_trigger = cpu.mem[BOSS_EXPL_CY]
stayed_stable = True
for _ in range(60):
    call_routine(cpu, "UPDATE_BOSS_WIPE")
    if cpu.mem[BOSS_EXPL_CY] != cy_after_trigger:
        stayed_stable = False
        break
check("UPDATE_BOSS_WIPE never touches BOSS_EXPL_CY again once BOSS_FORM!=0, "
      "across 60 more direct calls, even though BOSS_EXPL_CX (its own alias "
      "of BOSS_WIPE_ACT) is now a legitimate nonzero cell coordinate that "
      "used to be misread as \"wipe reactivated\"", stayed_stable)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
