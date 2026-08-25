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

ETANK_POOL = sym["ETANK_POOL"]
GAME_TICK = sym["GAME_TICK"]
IDCACHE_T0 = sym["IDCACHE_T0"]
ETANK_SPAWN_COL = sym["ETANK_SPAWN_COL"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def prime_apex_terrain(cpu):
    cpu.mem[IDCACHE_T0 + ETANK_SPAWN_COL] = 1


# Test 1: refuses at GAME_TICK=69
cpu = fresh_cpu()
prime_apex_terrain(cpu)
set_game_tick(cpu, 69)
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("refuses at GAME_TICK=69", cpu.mem[ETANK_POOL + 0] == 0)

# Test 2: spawns at GAME_TICK=70 (boundary)
cpu = fresh_cpu()
prime_apex_terrain(cpu)
set_game_tick(cpu, 70)
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("spawns at GAME_TICK=70 (boundary)", cpu.mem[ETANK_POOL + 0] == 1)

# Test 3: spawns when GAME_TICK's high byte is nonzero (>255, 16-bit
# safe - would wrongly refuse if only the low byte were checked and it
# happened to wrap below 70, e.g. GAME_TICK=256 -> low byte 0).
cpu = fresh_cpu()
prime_apex_terrain(cpu)
set_game_tick(cpu, 256)
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("spawns at GAME_TICK=256 (high byte nonzero, low byte=0)",
      cpu.mem[ETANK_POOL + 0] == 1)

# Test 4: real end-to-end timing - GAME_TICK only advances once per 8
# raw frames (TICK AND 07h==0), so reaching 70 takes 70*8=560 real
# MAINLOOP frames, not 70 - confirm via the real MAINLOOP, not a poke.
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
prime_apex_terrain(cpu)
etank_frame = None
tick_at_spawn = None
for f in range(700):
    step_frame(cpu)
    if cpu.mem[ETANK_POOL + 0] != 0:
        etank_frame = f
        tick_at_spawn = cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)
        break
check("does not spawn before real frame ~560 (GAME_TICK not yet 70)",
      etank_frame is not None and etank_frame >= 559)
check("GAME_TICK is genuinely >=70 at the real spawn frame",
      tick_at_spawn is not None and tick_at_spawn >= 70)
print(f"etank_frame={etank_frame} tick_at_spawn={tick_at_spawn}")

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
