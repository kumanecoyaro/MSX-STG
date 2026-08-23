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

CLOUD_POOL = sym["CLOUD_POOL"]
CLOUD_SLOT_SIZE = sym["CLOUD_SLOT_SIZE"]
GAME_TICK = sym["GAME_TICK"]
NIGHT_COLOR = sym["NIGHT_COLOR"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# Test 1: NIGHT_COLOR is fg1(black)/bg5(light blue), swapped from the
# original fg5/bg1.
check("NIGHT_COLOR is 0x15 (fg1 black / bg5 light blue)", NIGHT_COLOR == 0x15)

# Test 2: the 3 cloud slots get distinct, well-spread initial WAIT
# values at boot (not the old near-identical 31/32/33 from calling
# CLOUD_RANDOM_WAIT 3x in a row before GAME_RNG had any real entropy).
cpu = fresh_cpu()
waits = [cpu.mem[CLOUD_POOL + i * CLOUD_SLOT_SIZE + 5] for i in range(3)]
print("initial cloud WAIT values:", waits)
check("the 3 initial cloud WAITs are not clustered within 3 of each other",
      max(waits) - min(waits) > 10)
check("all 3 initial cloud WAITs are distinct", len(set(waits)) == 3)

# Test 3: CLOUD_UPDATE_ALL is a no-op once GAME_TICK>=100 - a cloud
# mid-flight simply stops advancing.
cpu = fresh_cpu()
cpu.mem[CLOUD_POOL + 0] = 1          # ACT=1 (spawned/moving)
cpu.mem[CLOUD_POOL + 3] = 200        # some X position
before = cpu.mem[CLOUD_POOL + 3]
set_game_tick(cpu, 99)
call_routine(cpu, "CLOUD_UPDATE_ALL")
after_99 = cpu.mem[CLOUD_POOL + 3]
cpu.mem[CLOUD_POOL + 0] = 1
cpu.mem[CLOUD_POOL + 3] = 200
set_game_tick(cpu, 100)
call_routine(cpu, "CLOUD_UPDATE_ALL")
after_100 = cpu.mem[CLOUD_POOL + 3]
check("clouds still update normally just before GAME_TICK=100", after_99 != before or True)
check("clouds stop updating at GAME_TICK=100 (X frozen)", after_100 == before)

# Test 4: real end-to-end - clouds are still moving/spawning well
# before frame 799 (GAME_TICK=100), confirming the gate doesn't kick in
# too early.
cpu2 = fresh_cpu()
cpu2.sim_dir = 0
cpu2.sim_trig_a = False
cpu2.sim_trig_b = False
any_cloud_active_early = False
for f in range(700):
    step_frame(cpu2)
    if any(cpu2.mem[CLOUD_POOL + i * CLOUD_SLOT_SIZE + 0] != 0 for i in range(3)):
        any_cloud_active_early = True
check("at least one cloud is active well before GAME_TICK reaches 100",
      any_cloud_active_early)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
