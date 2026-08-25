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

BIGZUM_POOL = sym["BIGZUM_POOL"]
TANK_ZUM_STANDING = sym["TANK_ZUM_STANDING"]
FRAMES = sym["BIGZUM_SHAKE_STAND_FRAMES"]

# Test 1: counter (+6) increments while standing, regardless of STATE=2 (punch)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 2   # STATE=2 punch
cpu.mem[BIGZUM_POOL+6] = 0
cpu.mem[BIGZUM_POOL+11] = 5  # PUNCH_COOLDOWN mid-value, must survive untouched by shake logic
cpu.mem[TANK_ZUM_STANDING] = 1
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UOBZ_PUNCH_MOVE")
# calling UOBZ_PUNCH_MOVE directly doesn't go through the top-of-routine shake check;
# instead call UPDATE_ONE_BIGZUM to exercise the real path
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 2   # STATE=2 punch
cpu.mem[BIGZUM_POOL+6] = 0
cpu.mem[BIGZUM_POOL+11] = 5
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[sym["TANK_X"]] = 60
cpu.mem[TANK_ZUM_STANDING] = 1
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("counter (+6) increments to 1 while STATE=2 and standing", cpu.mem[BIGZUM_POOL+6] == 1)
check("STATE stays 2 (not yet triggered - threshold now 60, not 1)", cpu.mem[BIGZUM_POOL+7] == 2)

# Test 1b: a brief jump-over touch (well under the 60-frame threshold) must
# NOT trigger - "即発火は速すぎて飛び越えも出来なくなってるから60フレくらいで"
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 2   # pin STATE=2 (punch, stuck) to avoid approach-state confounds
cpu.mem[BIGZUM_POOL+11] = 5
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[sym["TANK_X"]] = 60
cpu.ix = BIGZUM_POOL
for _ in range(10):  # 10 consecutive standing frames, well under 60
    cpu.mem[TANK_ZUM_STANDING] = 1
    call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("a brief (10-frame) touch does not trigger shake-off", cpu.mem[BIGZUM_POOL+7] != 1)

# Test 2: counter resets to 0 when not standing
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 2
cpu.mem[BIGZUM_POOL+6] = 40
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[sym["TANK_X"]] = 60
cpu.mem[TANK_ZUM_STANDING] = 0
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("counter (+6) resets to 0 when not standing", cpu.mem[BIGZUM_POOL+6] == 0)

# Test 3: reaching threshold triggers shake-off jump, from STATE=2 (the actual bug scenario)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 2   # STATE=2 punch, stuck
cpu.mem[BIGZUM_POOL+6] = FRAMES - 1
cpu.mem[BIGZUM_POOL+11] = 5  # PUNCH_COOLDOWN value (irrelevant, about to be overwritten)
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[BIGZUM_POOL+10] = 3  # stale JUMPFRAME
cpu.mem[sym["TANK_X"]] = 60
cpu.mem[TANK_ZUM_STANDING] = 1
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("threshold reached from STATE=2 -> STATE becomes 1 (jump)", cpu.mem[BIGZUM_POOL+7] == 1)
check("shake-off marker (+11) set to 1", cpu.mem[BIGZUM_POOL+11] == 1)
check("counter (+6) cleared after trigger", cpu.mem[BIGZUM_POOL+6] == 0)
check("JUMPFRAME (+10) advances to 1 (reset to 0 then UOBZ_JUMP_MOVE ran once same frame)", cpu.mem[BIGZUM_POOL+10] == 1)

# Test 4: while STATE=1 (already jumping), the check is skipped entirely -- counter untouched
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 1  # STATE=1 jumping
cpu.mem[BIGZUM_POOL+6] = 77  # arbitrary, must remain untouched (jump uses DY elsewhere only via ACT=2)
cpu.mem[BIGZUM_POOL+11] = 0  # not a shake jump
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[BIGZUM_POOL+10] = 0
cpu.mem[sym["TANK_X"]] = 60
cpu.mem[TANK_ZUM_STANDING] = 1
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE=1 (already jumping): shake check skipped, counter (+6) untouched", cpu.mem[BIGZUM_POOL+6] == 77)

# Test 5: a normal (non-shake-off) jump via UOBZ_PAUSE_DECIDE_JUMP still clears marker (+11)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+11] = 9  # stale marker
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[sym["TANK_X"]] = 60
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UOBZ_PAUSE_DECIDE_JUMP")
check("normal jump via UOBZ_PAUSE_DECIDE_JUMP clears shake marker (+11)", cpu.mem[BIGZUM_POOL+11] == 0)
check("normal jump sets STATE=1", cpu.mem[BIGZUM_POOL+7] == 1)

# Test 6: shake-off jump moves X to the right regardless of tank position (tank to the LEFT)
cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL+0] = 1
cpu.mem[BIGZUM_POOL+7] = 1
cpu.mem[BIGZUM_POOL+11] = 1  # shake-off marker set
cpu.mem[BIGZUM_POOL+1] = 60
cpu.mem[BIGZUM_POOL+10] = 0
cpu.mem[sym["TANK_X"]] = 10  # tank far to the left -- ordinary jump would move LEFT
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UOBZ_JUMP_MOVE")
check("shake-off jump moves BigZum RIGHT even though tank is to the left", cpu.mem[BIGZUM_POOL+1] > 60)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
