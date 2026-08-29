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

ETANK_POOL = sym["ETANK_POOL"]
BIGZUM_POOL = sym["BIGZUM_POOL"]
FLYER_POOL = sym["FLYER_POOL"]
ZUM_POOL = sym["ZUM_POOL"]
ZUM_SLOT_SIZE = sym["ZUM_SLOT_SIZE"]
TANK_X = sym["TANK_X"]
IDCACHE_T0 = sym["IDCACHE_T0"]; IDCACHE_T1 = sym["IDCACHE_T1"]
IDCACHE_T2 = sym["IDCACHE_T2"]; IDCACHE_T3 = sym["IDCACHE_T3"]

def prime_apex_terrain(cpu):
    col = sym["ETANK_SPAWN_COL"]
    cpu.mem[IDCACHE_T0+col] = 1  # steady flat rock (apex)

def set_game_tick(cpu, val):
    cpu.mem[sym["GAME_TICK"]] = val & 0xFF
    cpu.mem[sym["GAME_TICK"]+1] = (val >> 8) & 0xFF

def spawn_etank(cpu, force_terrain=True):
    set_game_tick(cpu, 70)
    if force_terrain:
        prime_apex_terrain(cpu)
    call_routine(cpu, "ALLOC_ETANK_SLOT")

# Test 1: does not spawn when apex terrain isn't present (T0 blank)
cpu = fresh_cpu()
set_game_tick(cpu, 70)
cpu.mem[IDCACHE_T0+sym["ETANK_SPAWN_COL"]] = 0
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("does not spawn when apex terrain (IDCACHE_T0) is blank", cpu.mem[ETANK_POOL+0] == 0)

# Test 2: does not spawn on a climb/descend marker (id>=3)
cpu = fresh_cpu()
set_game_tick(cpu, 70)
cpu.mem[IDCACHE_T0+sym["ETANK_SPAWN_COL"]] = 3
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("does not spawn on a climb/descend marker (id 3)", cpu.mem[ETANK_POOL+0] == 0)

# Test 3: spawns cleanly on steady apex flat terrain
cpu = fresh_cpu()
spawn_etank(cpu)
check("spawns on steady apex flat terrain", cpu.mem[ETANK_POOL+0] == 1)
check("spawns at ETANK_SPAWNX (off the right edge)", cpu.mem[ETANK_POOL+1] == sym["ETANK_SPAWNX"])
check("Y fixed from TANK_TIER_Y_TABLE index0 (apex) minus the tank-art-padding fudge",
      cpu.mem[ETANK_POOL+2] == cpu.mem[sym["TANK_TIER_Y_TABLE"]] - sym["ETANK_Y_OFFSET"])
check("HP initialized to 8", cpu.mem[ETANK_POOL+6] == sym["ETANK_HP_INIT"] == 8)

# Test 4: does not spawn while BigZum is active (bidirectional exclusion)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
spawn_etank(cpu)
check("refuses to spawn while BigZum is active", cpu.mem[ETANK_POOL+0] == 0)

# Test 5: BigZum refuses to spawn while Etank is active (the OTHER direction)
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
col = sym["BIGZUM_SPAWN_COL"]
cpu.mem[IDCACHE_T0+col]=0; cpu.mem[IDCACHE_T1+col]=0; cpu.mem[IDCACHE_T2+col]=0; cpu.mem[IDCACHE_T3+col]=1
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("BigZum refuses to spawn while Etank is active (bidirectional)", cpu.mem[BIGZUM_POOL+0] == 0)

# Test 5b: does not spawn while EITHER Zum slot is active (new bidirectional exclusion)
cpu = fresh_cpu()
cpu.mem[ZUM_POOL+0] = 1
spawn_etank(cpu)
check("refuses to spawn while Zum slot0 is active", cpu.mem[ETANK_POOL+0] == 0)

cpu = fresh_cpu()
cpu.mem[ZUM_POOL+ZUM_SLOT_SIZE+0] = 1
spawn_etank(cpu)
check("refuses to spawn while Zum slot1 is active", cpu.mem[ETANK_POOL+0] == 0)

# Test 5c: Zum refuses to spawn while Etank is active (the OTHER direction)
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
zcol = sym["ZUM_SPAWN_COL"]
cpu.mem[IDCACHE_T0+zcol] = 1
call_routine(cpu, "ALLOC_ZUM_SLOT")
check("Zum refuses to spawn while Etank is active (bidirectional)",
      cpu.mem[ZUM_POOL+0] == 0 and cpu.mem[ZUM_POOL+ZUM_SLOT_SIZE+0] == 0)

# Test 5d: Flyer and BigZum/Etank may now coexist (exclusion relaxed)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
call_routine(cpu, "ALLOC_FLYER_SLOT")
check("Flyer CAN spawn while BigZum is active (relaxed)", cpu.mem[FLYER_POOL+0] == 1)

cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
col = sym["BIGZUM_SPAWN_COL"]
cpu.mem[IDCACHE_T0+col]=0; cpu.mem[IDCACHE_T1+col]=0; cpu.mem[IDCACHE_T2+col]=0; cpu.mem[IDCACHE_T3+col]=1
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("BigZum CAN spawn while Flyer is active (relaxed)", cpu.mem[BIGZUM_POOL+0] == 1)

# Test 6: straight-line movement at flat speed 2, no terrain following
cpu = fresh_cpu()
spawn_etank(cpu)
x0 = cpu.mem[ETANK_POOL+1]
y0 = cpu.mem[ETANK_POOL+2]
cpu.ix = ETANK_POOL
call_routine(cpu, "UPDATE_ONE_ETANK")
check("moves left by exactly ETANK_SPEED(2) per frame", cpu.mem[ETANK_POOL+1] == x0 - 2)
check("Y never changes (no slope-following)", cpu.mem[ETANK_POOL+2] == y0)

# Test 7: despawns at the left edge instead of going negative
cpu = fresh_cpu()
spawn_etank(cpu)
cpu.mem[ETANK_POOL+1] = 1  # about to go negative on the next 2px step
cpu.ix = ETANK_POOL
call_routine(cpu, "UPDATE_ONE_ETANK")
check("despawns (ACT=0) instead of wrapping negative at the left edge", cpu.mem[ETANK_POOL+0] == 0)

# Test 8: Zum-style continuous push while in contact, suspended during JUMP_ACTIVE
cpu = fresh_cpu()
spawn_etank(cpu)
cpu.mem[ETANK_POOL+1] = 60
cpu.mem[TANK_X] = 50   # well within ETANK_COLLISION_SIZE(24) of X=60
cpu.mem[sym["JUMP_ACTIVE"]] = 0
call_routine(cpu, "UPDATE_TANK_ETANK_PUSH")
check("pushes TANK_X left while in contact", cpu.mem[TANK_X] == 50 - sym["ETANK_PUSH_SPEED"])

cpu2 = fresh_cpu()
spawn_etank(cpu2)
cpu2.mem[ETANK_POOL+1] = 60
cpu2.mem[TANK_X] = 50
cpu2.mem[sym["JUMP_ACTIVE"]] = 1
call_routine(cpu2, "UPDATE_TANK_ETANK_PUSH")
check("push suspended entirely while JUMP_ACTIVE", cpu2.mem[TANK_X] == 50)

# Test 9: omnidirectional bullet damage - HP decrements regardless of hit side, flashes, dies at 0
cpu = fresh_cpu()
spawn_etank(cpu)
cpu.mem[ETANK_POOL+1] = 100
cpu.mem[ETANK_POOL+6] = 1  # 1 HP left - next hit kills
BULLET0_ACT = sym["BULLET0_ACT"]
cpu.mem[BULLET0_ACT+0] = 1
et_y = cpu.mem[ETANK_POOL+2]
cell_row = (et_y + sym["ETANK_COLLISION_Y_OFFSET"]) // 8
cell_col = 100 // 8
cpu.mem[BULLET0_ACT+2] = cell_col
cpu.mem[BULLET0_ACT+3] = cell_row
cpu.ix = BULLET0_ACT
cpu.iy = ETANK_POOL
call_routine(cpu, "CHECK_HIT_PAIR_ETANK")
check("bullet hit at HP=1 destroys Etank (ACT->2 exploding)", cpu.mem[ETANK_POOL+0] == 2)
check("bullet consumed on hit", cpu.mem[BULLET0_ACT+0] == 0)

# non-lethal hit flashes and survives
cpu = fresh_cpu()
spawn_etank(cpu)
cpu.mem[ETANK_POOL+1] = 100
cpu.mem[ETANK_POOL+6] = 5
cpu.mem[BULLET0_ACT+0] = 1
et_y = cpu.mem[ETANK_POOL+2]
cpu.mem[BULLET0_ACT+2] = 100 // 8
cpu.mem[BULLET0_ACT+3] = (et_y + sym["ETANK_COLLISION_Y_OFFSET"]) // 8
cpu.ix = BULLET0_ACT
cpu.iy = ETANK_POOL
call_routine(cpu, "CHECK_HIT_PAIR_ETANK")
check("non-lethal hit decrements HP", cpu.mem[ETANK_POOL+6] == 4)
check("non-lethal hit sets hit-flash timer", cpu.mem[ETANK_POOL+7] == sym["FLASH_DURATION"])
check("survives non-lethal hit (still ACT=1)", cpu.mem[ETANK_POOL+0] == 1)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
