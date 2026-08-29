"""round34 ("ランダムスポーンは廃止 全てスケジュールに"): covers the new
table-driven Stage2 spawn schedule itself (SPAWN2_THRESHOLDS/SPAWN2_
NEXT_INDEX/SSC2_FIRE/SPAWN2_SCHEDULE_CHECK - ported from src/CYBER
SHMUP.asm's own SPAWN_THRESHOLDS/SPAWN_NEXT_INDEX/SSC_FIRE/SPAWN_
SCHEDULE_CHECK), replacing what enemy_spawn_stop_test.py used to cover
for the old interval-timer/ENEMY_SPAWN_STOP_TICK mechanism (deleted
this round - that whole mechanism is gone).

round34-3 (real-hardware feedback: "Tick500あたりから100Tick以上敵が
出てこない/Bigzumが一度も出てこない/ボスも999になっても出ない/やって
ることはStage1と全く同じ処理だぞ"): the retry-with-SPAWN2_STALL_LIMIT
design this file used to cover (round34-2) was itself the bug - a
blocked entry used to sit and retry the SAME index for up to 60 ticks
before being force-skipped, which is both far too short for the
terrain-gated types' own legitimate wait (silently dropping BigZum
almost every time) and completely unlike Stage1's real SSC_FIRE. That
whole stall-limit mechanism (SPAWN2_STALL_COUNT/SPAWN2_STALL_LIMIT) is
gone now, and with it every symbol/test below that referenced it.
SSC2_FIRE instead now matches Stage1's own SSC_FIRE byte-for-byte in
shape: SPAWN2_NEXT_INDEX advances UNCONDITIONALLY, before dispatch,
every single time an entry comes due; a spawn that can't happen right
then (pool full / terrain not flat) is simply DROPPED, never retried.
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
# Test 4 (round34-3, replaces the old "blocked entry retries" test):
# a blocked entry (pool full) now advances SPAWN2_NEXT_INDEX anyway -
# the spawn is dropped, not retried, exactly like Stage1's own
# ENEMY1_CLAIM_ANY when its pools are full. This is the literal fix for
# "Bigzumが一度も出てこない"/"Tick500あたりから100Tick以上敵が出てこない":
# a blocked entry must never hold up anything behind it.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
for i in range(ENEMY_SLOT_COUNT):
    cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] = 1
set_game_tick(cpu, t0)
call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
check("a blocked entry (pool full) advances SPAWN2_NEXT_INDEX anyway - dropped, not retried",
      cpu.mem[SPAWN2_NEXT_INDEX] == 1)
check("the dropped entry never actually spawned (pool still shows only the original full slots)",
      all(cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] == 1 for i in range(ENEMY_SLOT_COUNT)))

# ---------------------------------------------------------------------
# Test 5 (round34-3, replaces the old SPAWN2_STALL_LIMIT test): with
# every pool permanently full (so NOTHING can ever actually spawn),
# jump GAME_TICK far past the whole schedule and call
# SPAWN2_SCHEDULE_CHECK repeatedly (each call = one more due entry
# getting checked/dispatched, same as one real GAME_TICK step) - every
# single call must advance the index by exactly 1, with zero retries
# and zero stalls, all the way to SPAWN2_COUNT. This is the direct
# regression guard for "Tick500あたりから100Tick以上敵が出てこない": no
# entry may ever cost more than one check to resolve, however many
# entries in a row are blocked.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
for i in range(ENEMY_SLOT_COUNT):
    cpu.mem[ENEMY_POOL + i * ENEMY_SLOT_SIZE + E_ACT] = 1
set_game_tick(cpu, threshold(SPAWN2_COUNT - 1))
for i in range(SPAWN2_COUNT):
    call_routine(cpu, "SPAWN2_SCHEDULE_CHECK")
    check(f"call {i+1}/{SPAWN2_COUNT} with every pool full advances SPAWN2_NEXT_INDEX to {i+1} "
          f"(no stall, no retry)",
          cpu.mem[SPAWN2_NEXT_INDEX] == i + 1)

# ---------------------------------------------------------------------
# Test 6: the boss - the very last entry (index SPAWN2_COUNT-1) needs
# no CP of its own in SSC2_FIRE's dispatch chain; once every earlier
# index has fired, dispatch jumps unconditionally to S2_BOSS_SPAWN
# (same convention as Stage1's own SSC_FIRE/BOSS_SPAWN). SSC2_FIRE
# advances SPAWN2_NEXT_INDEX before this dispatch too, same as every
# other entry - no separate advance call happens inside S2_BOSS_SPAWN
# itself any more (round34-3).
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
