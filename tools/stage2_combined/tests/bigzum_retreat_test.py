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
BIGZUM_RETREAT_TICK = sym["BIGZUM_RETREAT_TICK"]
BIGZUM_POOL = sym["BIGZUM_POOL"]
BIGZUM_JUMP_XSPEED = sym["BIGZUM_JUMP_XSPEED"]
BULLET0_ACT = sym["BULLET0_ACT"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def spawn_bigzum(cpu, x=100, y=132, state=0):
    cpu.mem[BIGZUM_POOL + 0] = 1     # ACT
    cpu.mem[BIGZUM_POOL + 1] = x
    cpu.mem[BIGZUM_POOL + 2] = y
    cpu.mem[BIGZUM_POOL + 7] = state
    cpu.mem[BIGZUM_POOL + 8] = 100   # HP
    cpu.mem[BIGZUM_POOL + 9] = 1     # FACING=1 (flipped), so the transition to 0 is observable


# Test 1: not yet forced into retreat before BIGZUM_RETREAT_TICK.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK - 1)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE not forced to 5 just before BIGZUM_RETREAT_TICK",
      cpu.mem[BIGZUM_POOL + 7] != 5)

# Test 2: does NOT force retreat at the truncated-8-bit low byte of
# BIGZUM_RETREAT_TICK - same regression shape as the cloud/enemy-spawn
# fixes this same session.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK & 0xFF)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE not forced to 5 at the truncated-8-bit low byte of BIGZUM_RETREAT_TICK",
      cpu.mem[BIGZUM_POOL + 7] != 5)

# Test 3-4: forced into STATE=5 at BIGZUM_RETREAT_TICK, FACING reset
# to 0 (normal, facing left), overriding an in-progress punch (STATE=2).
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=2)   # mid-punch
set_game_tick(cpu, BIGZUM_RETREAT_TICK)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE forced to 5 (retreat) at BIGZUM_RETREAT_TICK, overriding STATE=2 (punch)",
      cpu.mem[BIGZUM_POOL + 7] == 5)
check("FACING reset to 0 (normal, facing left) on forced retreat",
      cpu.mem[BIGZUM_POOL + 9] == 0)

# Test 5: steps left by BIGZUM_JUMP_XSPEED per call while retreating.
x0 = cpu.mem[BIGZUM_POOL + 1]
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("steps left by BIGZUM_JUMP_XSPEED per call while retreating",
      cpu.mem[BIGZUM_POOL + 1] == x0 - BIGZUM_JUMP_XSPEED)

# Test 6: drives all the way off the left edge - deactivates and hides.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=BIGZUM_JUMP_XSPEED * 3, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK)
cpu.ix = BIGZUM_POOL
steps = 0
while cpu.mem[BIGZUM_POOL + 0] != 0 and steps < 50:
    call_routine(cpu, "UPDATE_ONE_BIGZUM")
    steps += 1
check("deactivates (ACT=0) once retreated off the left edge - 消す", cpu.mem[BIGZUM_POOL + 0] == 0)
sprite_y = cpu.mem[sym["BIGZUM_SPRITE_ATTRS"]]
check("hw sprite hidden (Y=209) after deactivating", sprite_y == 209)

# Test 7-8: collision disabled during forced retreat - "この時は弾が
# 居ても貫通しコリジョン無効に". Positive control first (STATE=1/jump,
# which bypasses the front/rear-facing split entirely so any AABB
# overlap registers a hit) confirms the box geometry below genuinely
# overlaps and WOULD register a hit outside of STATE=5.
def setup_hit_pair(cpu, state):
    cpu.mem[BIGZUM_POOL + 0] = 1
    cpu.mem[BIGZUM_POOL + 1] = 80    # BZ_X
    cpu.mem[BIGZUM_POOL + 2] = 80    # BZ_Y
    cpu.mem[BIGZUM_POOL + 7] = state
    cpu.mem[BIGZUM_POOL + 8] = 100   # HP
    cpu.mem[BULLET0_ACT + 0] = 1     # bullet ACT
    cpu.mem[BULLET0_ACT + 1] = 0     # TYPE=F
    cpu.mem[BULLET0_ACT + 2] = 10    # COL -> pixelX=80, matches BZ_X
    cpu.mem[BULLET0_ACT + 3] = 12    # ROW -> pixelY=96, matches BZ_Y+16 (BIGZUM_COLLISION_Y_OFFSET)


cpu = fresh_cpu()
setup_hit_pair(cpu, state=1)   # STATE=1 (jump) - positive control
cpu.ix = BULLET0_ACT
cpu.iy = BIGZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_BIGZUM")
check("positive control: overlapping bullet registers a hit while STATE=1 (bullet consumed)",
      cpu.mem[BULLET0_ACT + 0] == 0)

cpu = fresh_cpu()
setup_hit_pair(cpu, state=5)   # STATE=5 (forced retreat)
cpu.ix = BULLET0_ACT
cpu.iy = BIGZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_BIGZUM")
check("same overlap does NOT register while STATE=5 (retreat) - bullet passes through",
      cpu.mem[BULLET0_ACT + 0] == 1)
check("HP unchanged while STATE=5", cpu.mem[BIGZUM_POOL + 8] == 100)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
