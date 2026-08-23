import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

FLYER_POOL = sym["FLYER_POOL"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
LIMIT = sym["FLYER_DESCEND_LIMIT_Y"]

# descending Flyer near the cap: one more step would exceed it - must clamp+exit
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = LIMIT
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = sym["FLYER_VY"]
cpu.mem[TANK_Y_CUR] = 156  # worst-case lowest tier
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("Descending Flyer never exceeds FLYER_DESCEND_LIMIT_Y", cpu.mem[FLYER_POOL+2] <= LIMIT)
check("Descending Flyer exits once at the cap", cpu.mem[FLYER_POOL+8] == 2)

# DY=0 edge case (tank exactly level at lock) exits immediately, no infinite loop
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = 64
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = 0
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("DY=0 (level tie) exits immediately instead of looping forever", cpu.mem[FLYER_POOL+8] == 2)

# ascending Flyer is unaffected by the cap (moving away from ground)
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = 140   # only 16px from TANK_Y_CUR(156) - within FLYER_CLEAR_Y(32), still close
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = (256 - sym["FLYER_VY"]) & 0xFF
cpu.mem[TANK_Y_CUR] = 156
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("Ascending Flyer steps up normally, unaffected by descend cap", cpu.mem[FLYER_POOL+2] == 140 - sym["FLYER_VY"])
check("Ascending Flyer stays in PHASE=1 (still within clearance)", cpu.mem[FLYER_POOL+8] == 1)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
