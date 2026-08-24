import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

# "サンダーの時点でTick840スタートでまだボスに到達してないのにサンダー
# が１回描画されてた" - a real bug found this round: several fields get
# read UNCONDITIONALLY every single MAINLOOP frame regardless of
# whether the boss has ever spawned (UPDATE_BOSS_ALL/UPDATE_THUNDER/
# CHECK_THUNDER_VS_TANK/UPDATE_SBEAM/CHECK_SBEAM_VS_TANK are all called
# with no gate at all), yet were never explicitly zeroed at boot -
# unlike every OTHER pool in this file (ENEMY/ZUM/BIGZUM/FLYER/ETANK/
# CLOUD/HORMING all get an explicit INIT-time zero). This test harness
# always boots with RAM already zeroed (fresh_cpu()'s own memory model),
# so this class of bug is invisible here no matter how many frames any
# test runs - it can only ever be caught by directly asserting the
# INIT-time zero actually happens, which is what this file does. Real
# hardware boots with genuinely random RAM; any of these fields landing
# on a nonzero garbage byte would have driven real (if nonsensical)
# game logic before the boss's own real spawn condition was ever met.
cpu = fresh_cpu()

check("BOSS_ACT is zeroed at boot (UPDATE_BOSS_ALL reads it unconditionally every frame)",
      cpu.mem[sym["BOSS_ACT"]] == 0)
check("SBEAM_ACT is zeroed at boot (UPDATE_SBEAM/CHECK_SBEAM_VS_TANK read it unconditionally)",
      cpu.mem[sym["SBEAM_ACT"]] == 0)
check("THUNDER_PENDING is zeroed at boot",
      cpu.mem[sym["THUNDER_PENDING"]] == 0)
check("THUNDER_ELIGIBLE is zeroed at boot",
      cpu.mem[sym["THUNDER_ELIGIBLE"]] == 0)

THUNDER_POOL = sym["THUNDER_POOL"]
THUNDER_SLOT_SIZE = sym["THUNDER_SLOT_SIZE"]
THUNDER_SLOT_COUNT = sym["THUNDER_SLOT_COUNT"]
for i in range(THUNDER_SLOT_COUNT):
    addr = THUNDER_POOL + i * THUNDER_SLOT_SIZE
    check(f"THUNDER_POOL slot {i}'s own ACT byte (unconditionally read/drawn every frame by "
          "UPDATE_THUNDER/CHECK_THUNDER_VS_TANK) is zeroed at boot",
          cpu.mem[addr] == 0)

# sanity: confirm the pools that were ALREADY correctly zeroed before
# this round stay that way (regression guard, not a new finding)
HORMING_POOL = sym["HORMING_POOL"]
for off in (0, 7, 14, 21):
    check(f"HORMING_POOL slot at +{off} is zeroed at boot (already correct before this round)",
          cpu.mem[HORMING_POOL + off] == 0)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
