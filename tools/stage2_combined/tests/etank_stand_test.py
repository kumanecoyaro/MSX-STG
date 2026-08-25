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
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
JUMP_ACTIVE = sym["JUMP_ACTIVE"]
TANK_ZUM_STANDING = sym["TANK_ZUM_STANDING"]
ETANK_COLLISION_SIZE = sym["ETANK_COLLISION_SIZE"]
ETANK_COLLISION_Y_OFFSET = sym["ETANK_COLLISION_Y_OFFSET"]
TANK_GROUND_OFFSET = sym["TANK_GROUND_OFFSET"]

# Test 1: no-op while not jumping
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
cpu.mem[ETANK_POOL+1] = 60
cpu.mem[ETANK_POOL+2] = 100
cpu.mem[TANK_X] = 60
cpu.mem[JUMP_ACTIVE] = 0
cpu.mem[TANK_Y_CUR] = 200
call_routine(cpu, "UPDATE_TANK_ETANK_STAND")
check("no-op while not jumping (JUMP_ACTIVE=0)", cpu.mem[TANK_Y_CUR] == 200 and cpu.mem[TANK_ZUM_STANDING] == 0)

# Test 2: no-op while Etank inactive
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 0
cpu.mem[JUMP_ACTIVE] = 1
cpu.mem[TANK_Y_CUR] = 200
call_routine(cpu, "UPDATE_TANK_ETANK_STAND")
check("no-op while Etank inactive", cpu.mem[TANK_Y_CUR] == 200 and cpu.mem[TANK_ZUM_STANDING] == 0)

# Test 3: no-op when horizontally clear (no overlap)
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
cpu.mem[ETANK_POOL+1] = 60
cpu.mem[ETANK_POOL+2] = 100
cpu.mem[TANK_X] = 200   # far away, no overlap with ETANK_COLLISION_SIZE(24)
cpu.mem[JUMP_ACTIVE] = 1
cpu.mem[TANK_Y_CUR] = 200
call_routine(cpu, "UPDATE_TANK_ETANK_STAND")
check("no-op when horizontally clear", cpu.mem[TANK_Y_CUR] == 200 and cpu.mem[TANK_ZUM_STANDING] == 0)

# Test 4: clamps TANK_Y_CUR and sets TANK_ZUM_STANDING when overlapping and falling through the box
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
cpu.mem[ETANK_POOL+1] = 60
cpu.mem[ETANK_POOL+2] = 100  # ET_Y (top of 32x32 canvas)
cpu.mem[TANK_X] = 65   # within ETANK_COLLISION_SIZE(24) of X=60
cpu.mem[JUMP_ACTIVE] = 1
cpu.mem[TANK_Y_CUR] = 200  # well below the stand height - should clamp up
call_routine(cpu, "UPDATE_TANK_ETANK_STAND")
expected_y = 100 + ETANK_COLLISION_Y_OFFSET - TANK_GROUND_OFFSET
check("clamps TANK_Y_CUR to the box's own top minus TANK_GROUND_OFFSET", cpu.mem[TANK_Y_CUR] == expected_y)
check("sets TANK_ZUM_STANDING", cpu.mem[TANK_ZUM_STANDING] == 1)

# Test 5: does not push TANK_Y_CUR down if already above the stand height
cpu = fresh_cpu()
cpu.mem[ETANK_POOL+0] = 1
cpu.mem[ETANK_POOL+1] = 60
cpu.mem[ETANK_POOL+2] = 100
cpu.mem[TANK_X] = 65
cpu.mem[JUMP_ACTIVE] = 1
cpu.mem[TANK_Y_CUR] = 10  # already well above (less than) the stand height
call_routine(cpu, "UPDATE_TANK_ETANK_STAND")
check("does not lower TANK_Y_CUR when already above the stand height", cpu.mem[TANK_Y_CUR] == 10)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
