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
ENEMY_SPAWN_STOP_TICK = sym["ENEMY_SPAWN_STOP_TICK"]
ENEMY_POOL = sym["ENEMY_POOL"]
FLYER_POOL = sym["FLYER_POOL"]
ETANK_POOL = sym["ETANK_POOL"]
IDCACHE_T0 = sym["IDCACHE_T0"]
ETANK_SPAWN_COL = sym["ETANK_SPAWN_COL"]

ASM_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "combined_test.asm")
ASM_SOURCE = open(ASM_PATH, encoding="utf-8").read()


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# Test 1-3: SPAWN_STOPPED itself - a true 16-bit compare against
# ENEMY_SPAWN_STOP_TICK, same idiom (and same regression risk) as
# CLOUD_UPDATE_ALL's own GAME_TICK gate this session.
cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK - 1)
call_routine(cpu, "SPAWN_STOPPED")
check("SPAWN_STOPPED: Carry set (still allowed) just before the threshold",
      (cpu.f & 1) == 1)

cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK & 0xFF)   # truncated-8-bit false trigger
call_routine(cpu, "SPAWN_STOPPED")
check("SPAWN_STOPPED: does NOT stop at the truncated-8-bit low byte of ENEMY_SPAWN_STOP_TICK",
      (cpu.f & 1) == 1)

cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK)
call_routine(cpu, "SPAWN_STOPPED")
check("SPAWN_STOPPED: Carry clear (stopped) at the threshold itself",
      (cpu.f & 1) == 0)

# Test 4-5: ALLOC_ENEMY_SLOT (ZacoII) - no extra precondition besides a
# free pool slot, which fresh_cpu() already has.
cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK - 1)
call_routine(cpu, "ALLOC_ENEMY_SLOT")
check("ALLOC_ENEMY_SLOT (ZacoII) still spawns just before ENEMY_SPAWN_STOP_TICK",
      cpu.mem[ENEMY_POOL + 0] == 1)

cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK)
call_routine(cpu, "ALLOC_ENEMY_SLOT")
check("ALLOC_ENEMY_SLOT (ZacoII) refuses at ENEMY_SPAWN_STOP_TICK",
      cpu.mem[ENEMY_POOL + 0] == 0)

# Test 6-7: ALLOC_FLYER_SLOT - same shape, no extra precondition.
cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK - 1)
call_routine(cpu, "ALLOC_FLYER_SLOT")
check("ALLOC_FLYER_SLOT still spawns just before ENEMY_SPAWN_STOP_TICK",
      cpu.mem[FLYER_POOL + 0] == 1)

cpu = fresh_cpu()
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK)
call_routine(cpu, "ALLOC_FLYER_SLOT")
check("ALLOC_FLYER_SLOT refuses at ENEMY_SPAWN_STOP_TICK",
      cpu.mem[FLYER_POOL + 0] == 0)

# Test 8-9: ALLOC_ETANK_SLOT - has its own older GAME_TICK>=70 gate too;
# confirm the NEW stop-gate still applies on top of it (terrain primed,
# GAME_TICK well past 70, but also past ENEMY_SPAWN_STOP_TICK).
def prime_apex_terrain(cpu):
    cpu.mem[IDCACHE_T0 + ETANK_SPAWN_COL] = 1

cpu = fresh_cpu()
prime_apex_terrain(cpu)
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK - 1)
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("ALLOC_ETANK_SLOT still spawns just before ENEMY_SPAWN_STOP_TICK",
      cpu.mem[ETANK_POOL + 0] == 1)

cpu = fresh_cpu()
prime_apex_terrain(cpu)
set_game_tick(cpu, ENEMY_SPAWN_STOP_TICK)
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("ALLOC_ETANK_SLOT refuses at ENEMY_SPAWN_STOP_TICK despite its own GAME_TICK>=70 gate being satisfied",
      cpu.mem[ETANK_POOL + 0] == 0)

# Test 10-11: ALLOC_ZUM_SLOT and ALLOC_BIGZUM_SLOT both gate on
# ENEMY_SPAWN_COUNT>=10 plus their own overlap/terrain checks before
# ever reaching a free-slot scan - rather than reconstructing every one
# of those preconditions just to prove the new gate fires, confirm
# structurally that both routines call SPAWN_STOPPED as their very
# first instruction (identical idiom already proven behaviorally above
# on ZacoII/Flyer/Etank).
for label in ("ALLOC_ZUM_SLOT", "ALLOC_BIGZUM_SLOT"):
    idx = ASM_SOURCE.index(f"\n{label}:\n")
    next_line = ASM_SOURCE[idx:].split("\n")[2].strip()
    check(f"{label}'s first instruction is the SPAWN_STOPPED guard",
          next_line == "CALL SPAWN_STOPPED : RET NC")

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
