"""round34 ("ランダムスポーンは廃止 全てスケジュールに"): covers the new
table-driven Stage2 spawn schedule itself (SPAWN2_THRESHOLDS/SPAWN2_
NEXT_INDEX/SSC2_FIRE/SPAWN2_SCHEDULE_CHECK - ported from src/CYBER
SHMUP.asm's own SPAWN_THRESHOLDS/SPAWN_NEXT_INDEX/SSC_FIRE/SPAWN_
SCHEDULE_CHECK), replacing what enemy_spawn_stop_test.py used to cover
for the old interval-timer/ENEMY_SPAWN_STOP_TICK mechanism (deleted
this round - that whole mechanism is gone).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

GAME_TICK = sym["GAME_TICK"]
SPAWN2_NEXT_INDEX = sym["SPAWN2_NEXT_INDEX"]
SPAWN2_COUNT = sym["SPAWN2_COUNT"]
SPAWN2_THRESHOLDS = sym["SPAWN2_THRESHOLDS"]
SPAWN2_STALL_COUNT = sym["SPAWN2_STALL_COUNT"]
SPAWN2_STALL_LIMIT = sym["SPAWN2_STALL_LIMIT"]
ENEMY_POOL = sym["ENEMY_POOL"]
ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
ENEMY_SLOT_COUNT = sym["ENEMY_SLOT_COUNT"]
E_ACT = sym["E_ACT"]; E_X = sym["E_X"]; E_Y = sym["E_Y"]; E_VARIANT = sym["E_VARIANT"]
BOSS_ACT = sym["BOSS_ACT"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def threshold(i):
    return out[SPAWN2_THRESHOLDS + i * 2] | (out[SPAWN2_THRESHOLDS + i * 2 + 1] << 8)


# index0's own real threshold, read straight from the assembled ROM
# data (not hand-copied) - this schedule's own first entry is a ZacoII
# spawn (SPAWN_S2_ZACOII).
t0 = threshold(0)
check("index0's own threshold is a small, sane tick value (this schedule's own first entry)",
      0 < t0 < 200)

# ---------------------------------------------------------------------
# Test 1-3: SPAWN2_SCHEDULE_CHECK's own 16-bit-safe GAME_TICK gate -
# same regression shape as the old SPAWN_STOPPED/BOSS_SPAWN_TICK checks
# this round replaced, just against index0's own threshold now instead
# of a single shared constant.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
set_game_tick(cpu, t0 - 1)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("SPAWN2_SCHEDULE_CHECK: does not fire index0 just before its own threshold",
      cpu.mem[SPAWN2_NEXT_INDEX] == 0 and cpu.mem[ENEMY_POOL + E_ACT] == 0)

cpu = fresh_cpu()
set_game_tick(cpu, t0 & 0xFF)   # truncated-8-bit false trigger, same bug class as the old checks
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("SPAWN2_SCHEDULE_CHECK: does NOT fire at the truncated-8-bit low byte of index0's threshold "
      "(only relevant if t0's own high byte is nonzero - guard below)",
      t0 <= 0xFF or (cpu.mem[SPAWN2_NEXT_INDEX] == 0 and cpu.mem[ENEMY_POOL + E_ACT] == 0))

cpu = fresh_cpu()
set_game_tick(cpu, t0)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("SPAWN2_SCHEDULE_CHECK: fires index0 exactly at its own threshold",
      cpu.mem[ENEMY_POOL + E_ACT] == 1)
check("SPAWN2_NEXT_INDEX advances to 1 after a successful fire",
      cpu.mem[SPAWN2_NEXT_INDEX] == 1)
check("the spawned ZacoII lands at S2_SPAWN_Y (this entry's own row*8, staged before dispatch)",
      cpu.mem[ENEMY_POOL + E_Y] == cpu.mem[sym["S2_SPAWN_Y"]])

# ---------------------------------------------------------------------
# Test 4: blocked entry does NOT advance the index - retried next
# GAME_TICK instead of being skipped. Fill the ENEMY_POOL first so
# index0's own ALLOC_ENEMY_SLOT has nowhere to spawn.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
for i in range(ENEMY_SLOT_COUNT):
    cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] = 1
set_game_tick(cpu, t0)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("a blocked entry (pool full) does NOT advance SPAWN2_NEXT_INDEX",
      cpu.mem[SPAWN2_NEXT_INDEX] == 0)

# free a slot and retry - same index should now succeed
cpu.mem[ENEMY_POOL + 0 * ENEMY_SLOT_SIZE + E_ACT] = 0
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("retrying the same (still-due) entry once the pool frees up now succeeds",
      cpu.mem[SPAWN2_NEXT_INDEX] == 1)

# ---------------------------------------------------------------------
# Test 5: the SPAWN2_STALL_LIMIT safety valve - found necessary this
# round when a real no-player-fire-input playthrough left a ground
# enemy permanently active, which would otherwise block every later
# entry (including the boss, the very last one) forever. If an entry
# stays due-but-blocked for SPAWN2_STALL_LIMIT consecutive GAME_TICKs,
# it's force-skipped instead (SSC2_ADVANCE without ever spawning it).
# ---------------------------------------------------------------------
cpu = fresh_cpu()
for i in range(ENEMY_SLOT_COUNT):
    cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] = 1
tick = t0
for _ in range(SPAWN2_STALL_LIMIT):
    set_game_tick(cpu, tick)
    call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
    tick += 1
check(f"stays stuck at index0 for {SPAWN2_STALL_LIMIT} consecutive due-but-blocked GAME_TICKs",
      cpu.mem[SPAWN2_NEXT_INDEX] == 0)
set_game_tick(cpu, tick)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check(f"force-skips (advances without spawning) once blocked for SPAWN2_STALL_LIMIT"
      f"({SPAWN2_STALL_LIMIT}) GAME_TICKs in a row",
      cpu.mem[SPAWN2_NEXT_INDEX] == 1)
check("the force-skipped entry never actually spawned (pool still shows only the original 3 stuck slots)",
      all(cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] == 1 for i in range(ENEMY_SLOT_COUNT)))
check("SPAWN2_STALL_COUNT resets to 0 after the force-skip",
      cpu.mem[SPAWN2_STALL_COUNT] == 0)

# a still-due entry that succeeds well within the limit must NOT carry
# a stale stall count into the next entry.
cpu = fresh_cpu()
set_game_tick(cpu, t0)
for _ in range(5):
    call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")  # a few idle calls at the same not-yet-advanced tick
check("SPAWN2_STALL_COUNT resets to 0 immediately after an ordinary successful fire too",
      cpu.mem[SPAWN2_STALL_COUNT] == 0)

# ---------------------------------------------------------------------
# Test 6: the boss - the very last entry (index SPAWN2_COUNT-1) needs
# no CP of its own in SSC2_FIRE's dispatch chain; once every earlier
# index has fired, dispatch jumps unconditionally to S2_BOSS_SPAWN
# (same convention as Stage1's own SSC_FIRE/BOSS_SPAWN).
# ---------------------------------------------------------------------
cpu = fresh_cpu()
cpu.mem[SPAWN2_NEXT_INDEX] = SPAWN2_COUNT - 1
boss_tick = threshold(SPAWN2_COUNT - 1)
set_game_tick(cpu, boss_tick)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("the last schedule entry (index SPAWN2_COUNT-1) dispatches to the boss, not any ALLOC_*_SLOT",
      cpu.mem[BOSS_ACT] == 1)
check("SPAWN2_NEXT_INDEX advances past the last entry (== SPAWN2_COUNT) once the boss fires",
      cpu.mem[SPAWN2_NEXT_INDEX] == SPAWN2_COUNT)

# ---------------------------------------------------------------------
# Test 7: once every entry has fired, SPAWN2_SCHEDULE_CHECK is a
# permanent, harmless no-op (mirrors Stage1's own "one-shot" guarantee).
# ---------------------------------------------------------------------
cpu = fresh_cpu()
cpu.mem[SPAWN2_NEXT_INDEX] = SPAWN2_COUNT
set_game_tick(cpu, 60000)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("SPAWN2_SCHEDULE_CHECK never touches SPAWN2_NEXT_INDEX again once it reaches SPAWN2_COUNT",
      cpu.mem[SPAWN2_NEXT_INDEX] == SPAWN2_COUNT)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
