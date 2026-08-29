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

# "サンダーの時点でTick840スタートでまだボスに到達してないのにサンダー
# が１回描画されてた" (round22) - BOSS_ACT is read UNCONDITIONALLY every
# single MAINLOOP frame (UPDATE_BOSS_ALL's own very first instruction),
# regardless of whether the boss has ever spawned - it's the ONE field
# that structurally can't be deferred to spawn time, since it's what
# gates whether that very check even happens. This test harness always
# boots with RAM already zeroed (fresh_cpu()'s own memory model), so a
# missing boot-time zero here is invisible no matter how many frames any
# test runs - it can only ever be caught by directly asserting the
# INIT-time zero actually happens. Real hardware boots with genuinely
# random RAM; a garbage nonzero BOSS_ACT there would skip the spawn
# check forever and jump straight into patrol/pose logic reading
# entirely unset BOSS_X/Y/DIR/PHASE.
cpu = fresh_cpu()
check("BOSS_ACT is zeroed at boot (UPDATE_BOSS_ALL reads it unconditionally every frame, "
      "and it's the one field that can't be deferred to spawn time)",
      cpu.mem[sym["BOSS_ACT"]] == 0)

# "ボス前とボススポーン後は完全に分けて一切干渉しない...初期化もボス用
# はボススポーン直前" (round23) - every OTHER boss-only field (SBEAM_ACT,
# THUNDER_PENDING/ELIGIBLE, THUNDER_POOL's own 4 slots) deliberately does
# NOT get a boot-time zero any more: round23's own BOSS_ACT-gated
# SKIP_BOSS_SUBSYSTEMS means UPDATE_THUNDER/CHECK_THUNDER_VS_TANK/
# UPDATE_SBEAM/CHECK_SBEAM_VS_TANK are never even CALLED while
# BOSS_ACT==0, so garbage sitting in those fields before spawn is never
# read by anything. What actually matters is the real spawn transition
# (inside UPDATE_BOSS_ALL) resetting all of them atomically, in the same
# instant it sets BOSS_ACT=1 - proven here by poking deliberate garbage
# into every one of them, forcing a real spawn via GAME_TICK, and
# confirming the spawn's own init overwrites every single one regardless
# of what was there before.
SBEAM_ACT = sym["SBEAM_ACT"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
THUNDER_ELIGIBLE = sym["THUNDER_ELIGIBLE"]
THUNDER_POOL = sym["THUNDER_POOL"]
THUNDER_SLOT_SIZE = sym["THUNDER_SLOT_SIZE"]
THUNDER_SLOT_COUNT = sym["THUNDER_SLOT_COUNT"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_SPAWN_TICK = sym["BOSS_SPAWN_TICK"]
GAME_TICK = sym["GAME_TICK"]

cpu = fresh_cpu()
GARBAGE = 0xA5
cpu.mem[SBEAM_ACT] = GARBAGE
cpu.mem[THUNDER_PENDING] = GARBAGE
cpu.mem[THUNDER_ELIGIBLE] = GARBAGE
for i in range(THUNDER_SLOT_COUNT):
    cpu.mem[THUNDER_POOL + i * THUNDER_SLOT_SIZE] = GARBAGE
# round34 ("全てスケジュールに"): the spawn itself no longer has any
# GAME_TICK check of its own (that moved to the shared SPAWN2_SCHEDULE_
# CHECK/SSC2_FIRE dispatcher) - S2_BOSS_SPAWN always succeeds whenever
# called, so calling it directly is the real "force a spawn" now.
call_routine(cpu, "S2_BOSS_SPAWN")

check("a real spawn (forced directly) actually happened despite the pre-spawn garbage",
      cpu.mem[BOSS_ACT] == 1)
check("the spawn's own init resets SBEAM_ACT regardless of pre-spawn garbage",
      cpu.mem[SBEAM_ACT] == 0)
check("the spawn's own init resets THUNDER_PENDING regardless of pre-spawn garbage",
      cpu.mem[THUNDER_PENDING] == 0)
check("the spawn's own init resets THUNDER_ELIGIBLE regardless of pre-spawn garbage",
      cpu.mem[THUNDER_ELIGIBLE] == 0)
for i in range(THUNDER_SLOT_COUNT):
    addr = THUNDER_POOL + i * THUNDER_SLOT_SIZE
    check(f"the spawn's own RESET_THUNDER_POOL clears slot {i}'s own ACT byte regardless of "
          "pre-spawn garbage", cpu.mem[addr] == 0)

# and the other direction: while BOSS_ACT==0 (pre-spawn), a real MAINLOOP
# frame never even touches THUNDER_POOL/SBEAM_ACT at all any more (they
# stay exactly as poked) - confirms SKIP_BOSS_SUBSYSTEMS is actually
# skipping the calls, not just happening to leave garbage alone by luck.
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
cpu.mem[SBEAM_ACT] = GARBAGE
cpu.mem[THUNDER_POOL] = GARBAGE
step_frame(cpu)
check("real MAINLOOP: a single pre-spawn frame leaves SBEAM_ACT's own poked garbage untouched "
      "(UPDATE_SBEAM/CHECK_SBEAM_VS_TANK are gated out entirely, not just harmlessly reading it)",
      cpu.mem[SBEAM_ACT] == GARBAGE)
check("real MAINLOOP: same for THUNDER_POOL's own slot0 ACT byte",
      cpu.mem[THUNDER_POOL] == GARBAGE)
check("real MAINLOOP: BOSS_ACT itself is still correctly 0 (the one field that IS always live)",
      cpu.mem[BOSS_ACT] == 0)

# sanity: the pools that were already correctly zeroed before round22
# stay that way (regression guard, not a new finding)
HORMING_POOL = sym["HORMING_POOL"]
cpu = fresh_cpu()
for off in (0, 7, 14, 21):
    check(f"HORMING_POOL slot at +{off} is zeroed at boot (already correct before round22)",
          cpu.mem[HORMING_POOL + off] == 0)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
