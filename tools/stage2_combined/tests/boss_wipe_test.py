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
# wipe effect. This file verifies TRIGGER/UPDATE/DRAW/HIDE_BOSS_WIPE_*
# and the two call sites (S2_BOSS_SPAWN, UBA_MOVE_RIGHT) directly.

out, sym, text = get_out()
SAT_BASE = 0x1B00

BOSS_WIPE_SPR_BASE_SLOT = sym["BOSS_WIPE_SPR_BASE_SLOT"]
BOSS_WIPE_SLOTS = sym["BOSS_WIPE_SLOTS"]
BOSS_WIPE_START_Y = sym["BOSS_WIPE_START_Y"]
BOSS_WIPE_END_Y = sym["BOSS_WIPE_END_Y"]
BOSS_WIPE_SPEED = sym["BOSS_WIPE_SPEED"]
BOSS_WIPE_ACT = sym["BOSS_WIPE_ACT"]
BOSS_WIPE_Y = sym["BOSS_WIPE_Y"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_ACT = sym["BOSS_ACT"]

check("BOSS_WIPE_SLOTS is 4 (one dummy per 16px band, matching the boss's "
      "own 64px-wide body)", BOSS_WIPE_SLOTS == 4)
check("BOSS_WIPE_START_Y is 16px above BOSS_SPAWN_Y",
      BOSS_WIPE_START_Y == BOSS_SPAWN_Y - 16)
check("BOSS_WIPE_END_Y is past the boss's own 64px-tall body plus a further "
      "64px of clearance", BOSS_WIPE_END_Y == BOSS_SPAWN_Y + 64 + 64)


def slot_bytes(cpu, slot):
    base = SAT_BASE + slot * 4
    return tuple(cpu.vram[base + i] for i in range(4))


# ---- TRIGGER_BOSS_WIPE ----
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
# still short of BOSS_WIPE_END_Y ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = BOSS_WIPE_START_Y & 0xFF
call_routine(cpu, "UPDATE_BOSS_WIPE")
check("UPDATE_BOSS_WIPE advances BOSS_WIPE_Y by BOSS_WIPE_SPEED while still "
      "short of BOSS_WIPE_END_Y",
      cpu.mem[BOSS_WIPE_Y] == (BOSS_WIPE_START_Y + BOSS_WIPE_SPEED) & 0xFF)
check("UPDATE_BOSS_WIPE stays active (BOSS_WIPE_ACT still 1) mid-sweep",
      cpu.mem[BOSS_WIPE_ACT] == 1)
mid_slots_ok = all(
    slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == (BOSS_WIPE_START_Y + BOSS_WIPE_SPEED) & 0xFF
    for i in range(4))
check("UPDATE_BOSS_WIPE actually redraws all 4 slots to the new Y mid-sweep",
      mid_slots_ok)

# ---- UPDATE_BOSS_WIPE: "1回だけではなく攻撃に移るまで継続してループ" -
# drive one full sweep to BOSS_WIPE_END_Y and confirm it does NOT stop
# there any more - it wraps back to BOSS_WIPE_START_Y and keeps
# sweeping, staying active the whole time, for several full laps in a
# row (nothing here ever clears BOSS_WIPE_ACT on its own) ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = BOSS_WIPE_START_Y & 0xFF
steps_per_lap = -(-(BOSS_WIPE_END_Y - BOSS_WIPE_START_Y) // BOSS_WIPE_SPEED)  # ceil div
lap_ys = []
for lap in range(3):
    for _ in range(steps_per_lap):
        call_routine(cpu, "UPDATE_BOSS_WIPE")
    lap_ys.append(cpu.mem[BOSS_WIPE_Y])
check(f"one full lap (BOSS_WIPE_START_Y to BOSS_WIPE_END_Y) takes the expected "
      f"number of UPDATE_BOSS_WIPE calls ({steps_per_lap}) and wraps back to "
      "BOSS_WIPE_START_Y instead of stopping",
      all(y == BOSS_WIPE_START_Y & 0xFF for y in lap_ys))
check("BOSS_WIPE_ACT is still 1 after 3 full laps - the loop never stops itself",
      cpu.mem[BOSS_WIPE_ACT] == 1)
still_visible = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == BOSS_WIPE_START_Y & 0xFF
                     for i in range(4))
check("the 4 dummy sprites are still being drawn (not hidden) after 3 laps",
      still_visible)

# ---- STOP_BOSS_WIPE: the only thing that actually ends the loop ----
call_routine(cpu, "STOP_BOSS_WIPE")
check("STOP_BOSS_WIPE clears BOSS_WIPE_ACT", cpu.mem[BOSS_WIPE_ACT] == 0)
stopped_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("STOP_BOSS_WIPE hides all 4 slots (Y=209)", stopped_hidden)
# and once stopped, UPDATE_BOSS_WIPE's own gate keeps it that way - it
# must NOT redraw over the Y=209 hide on the next frame
call_routine(cpu, "UPDATE_BOSS_WIPE")
stays_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("UPDATE_BOSS_WIPE does not resurrect the sprites on the frame right "
      "after STOP_BOSS_WIPE (BOSS_WIPE_ACT=0 gate holds)", stays_hidden)

# ---- S2_BOSS_SPAWN triggers the wipe as part of the real spawn sequence ----
cpu = fresh_cpu()
cpu.mem[BOSS_WIPE_ACT] = 0
call_routine(cpu, "S2_BOSS_SPAWN")
check("S2_BOSS_SPAWN itself calls TRIGGER_BOSS_WIPE (BOSS_WIPE_ACT=1 right "
      "after spawning)", cpu.mem[BOSS_WIPE_ACT] == 1)
check("S2_BOSS_SPAWN's own boss-activation flag is also set, confirming this "
      "is really the real spawn routine and not some other path",
      cpu.mem[BOSS_ACT] == 1)

# ---- UBA_MOVE_RIGHT (first-attack pose entry): now the ONLY thing that
# stops the loop - since UPDATE_BOSS_WIPE never stops itself any more,
# this must both hide the sprites AND clear BOSS_WIPE_ACT (via
# STOP_BOSS_WIPE), or the loop would just resurrect them on the very
# next frame ----
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
cpu.mem[BOSS_WIPE_ACT] = 1
cpu.mem[BOSS_WIPE_Y] = 90  # mid-sweep, well short of BOSS_WIPE_END_Y
call_routine(cpu, "DRAW_BOSS_WIPE_SPRITES")
call_routine(cpu, "UBA_MOVE_RIGHT")
safety_hidden = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("UBA_MOVE_RIGHT (the boss's first attack-pose entry point) hides the 4 "
      "wipe dummy sprites even mid-sweep, so they can never survive into the "
      "attack phase", safety_hidden)
check("UBA_MOVE_RIGHT also clears BOSS_WIPE_ACT (not just a visual hide) so "
      "the now-perpetual loop actually stops for good", cpu.mem[BOSS_WIPE_ACT] == 0)
call_routine(cpu, "UPDATE_BOSS_WIPE")
stays_hidden_after_pose = all(slot_bytes(cpu, BOSS_WIPE_SPR_BASE_SLOT + i)[0] == 209 for i in range(4))
check("...and stays hidden on the following frame (the loop doesn't resurrect "
      "it once the attack pose has begun)", stays_hidden_after_pose)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
