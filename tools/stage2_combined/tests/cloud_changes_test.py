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
NIGHT_START_TICK = sym["NIGHT_START_TICK"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# Test 1: NIGHT_COLOR was fg1(black)/bg5(light blue) (swapped from the
# original fg5/bg1), then round36-14 follow-up#12(その3) 実機フィード
# バック対応 ("じゃあホワイトで") repainted it again to fg15(white)/bg5
# (light blue) - group17 is also FlyerLaser's own home now, and white-
# on-blue is the only way to give the laser a real, already-used-
# elsewhere color combination (see NIGHT_COLOR's own comment).
check("NIGHT_COLOR is 0xF5 (fg15 white / bg5 light blue)", NIGHT_COLOR == 0xF5)

# Test 2: the 3 cloud slots get distinct, well-spread initial WAIT
# values at boot (not the old near-identical 31/32/33 from calling
# CLOUD_RANDOM_WAIT 3x in a row before GAME_RNG had any real entropy).
cpu = fresh_cpu()
waits = [cpu.mem[CLOUD_POOL + i * CLOUD_SLOT_SIZE + 5] for i in range(3)]
print("initial cloud WAIT values:", waits)
check("the 3 initial cloud WAITs are not clustered within 3 of each other",
      max(waits) - min(waits) > 10)
check("all 3 initial cloud WAITs are distinct", len(set(waits)) == 3)

# Test 3: CLOUD_UPDATE_ALL is a no-op once GAME_TICK>=NIGHT_START_TICK - a
# cloud mid-flight simply stops advancing. The comparison must be a true
# 16-bit one (NIGHT_START_TICK is well above 255) - also checked directly
# at the old 8-bit-truncated low byte of NIGHT_START_TICK (what a
# `CP NIGHT_START_TICK`-style compare would have wrongly matched against,
# since Z80's CP only ever takes an 8-bit immediate) to guard against that
# exact class of bug reappearing.
cpu = fresh_cpu()
def arm_cloud(cpu):
    cpu.mem[CLOUD_POOL + 0] = 1          # ACT=1 (spawned/moving)
    cpu.mem[CLOUD_POOL + 3] = 200        # some X position
    cpu.mem[CLOUD_POOL + 4] = 1          # per-frame speed countdown=1, forces a move this call

arm_cloud(cpu)
before = cpu.mem[CLOUD_POOL + 3]
set_game_tick(cpu, NIGHT_START_TICK - 1)
call_routine(cpu, "CLOUD_UPDATE_ALL")
after_before_start = cpu.mem[CLOUD_POOL + 3]
arm_cloud(cpu)
set_game_tick(cpu, NIGHT_START_TICK & 0xFF)   # the truncated-8-bit false trigger
call_routine(cpu, "CLOUD_UPDATE_ALL")
after_truncated = cpu.mem[CLOUD_POOL + 3]
arm_cloud(cpu)
set_game_tick(cpu, NIGHT_START_TICK)
call_routine(cpu, "CLOUD_UPDATE_ALL")
after_start = cpu.mem[CLOUD_POOL + 3]
check("clouds still update normally just before NIGHT_START_TICK", after_before_start != before)
check("clouds do NOT stop at the truncated-8-bit low byte of NIGHT_START_TICK",
      after_truncated != before)
check("clouds stop updating at GAME_TICK=NIGHT_START_TICK (X frozen)", after_start == before)

# Test 4: real end-to-end - clouds are still moving/spawning well before
# GAME_TICK reaches NIGHT_START_TICK, confirming the gate doesn't kick in
# too early.
cpu2 = fresh_cpu()
cpu2.sim_dir = 0
cpu2.sim_trig_a = False
cpu2.sim_trig_b = False
any_cloud_active_early = False
for f in range(min(700, NIGHT_START_TICK * 8 - 50)):
    step_frame(cpu2)
    if any(cpu2.mem[CLOUD_POOL + i * CLOUD_SLOT_SIZE + 0] != 0 for i in range(3)):
        any_cloud_active_early = True
check("at least one cloud is active well before GAME_TICK reaches NIGHT_START_TICK",
      any_cloud_active_early)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
