"""round34 ("ランダムスポーンは廃止 全てスケジュールに"): the boss reuses
Zum/BigZum/Flyer/Etank's own hw sprite slots and, for BigZum specifically,
pattern-VRAM bytes too (see BOSS_SPR_BASE_SLOT/PAT_SASAPI's own comments
in combined_test.asm) - this was always safe under the OLD design because
a single shared ENEMY_SPAWN_STOP_TICK gate blocked every ALLOC_*_SLOT a
full 49 GAME_TICKs before the boss could ever appear, giving every pool
time to naturally clear.

That shared gate is gone now - each type only ever spawns when its own
schedule entry fires, and this specific schedule (transcribed from the
uploaded Schedule2.json) places its last BigZum at tick979, only 16
ticks before the boss's own tick995. This test exists specifically to
verify - empirically, via the real Z80 emulator, not just by eyeballing
tick gaps - that every one of these 4 pools is genuinely empty at the
exact moment the boss spawns, even in the worst realistic case (a
player who never destroys anything, so nothing despawns except via its
own natural lifecycle/forced-retreat).

If this test ever fails after a future schedule edit, it means that
edit placed some enemy's own last spawn too close to the boss's own
tick for it to reliably clear in time - the fix is either to move that
spawn earlier in the schedule, or (for BigZum specifically) to check
whether BIGZUM_RETREAT_TICK still gives enough lead time.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

BOSS_ACT = sym["BOSS_ACT"]
ZUM_POOL = sym["ZUM_POOL"]
ZUM_SLOT_SIZE = sym["ZUM_SLOT_SIZE"]
ZUM_SLOT_COUNT = 2
BIGZUM_POOL = sym["BIGZUM_POOL"]
FLYER_POOL = sym["FLYER_POOL"]
ETANK_POOL = sym["ETANK_POOL"]

# Worst case: no player fire input at all, same config every other
# boss end-to-end test in this suite already uses for this exact
# reason - nothing on screen ever gets shot down, so every pool has to
# clear on its own (forced retreat for BigZum, natural lifecycle/
# schedule margin for everything else) or via the SPAWN2_STALL_LIMIT
# safety valve skipping a spawn outright rather than letting it block
# forever - see SPAWN2_SCHEDULE_CHECK's own comment.
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False

boss_spawn_frame = None
prev_act = 0
# generous upper bound - verified empirically elsewhere in this suite
# (see boss_test.py's own Test12) that the worst case for this specific
# schedule's own content is ~frame 10727.
for f in range(20000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and prev_act == 0:
        boss_spawn_frame = f
        break
    prev_act = cpu.mem[BOSS_ACT]

check("real MAINLOOP: the boss does spawn within the test's own generous frame budget "
      "(prerequisite for the rest of this file's own checks)", boss_spawn_frame is not None)

if boss_spawn_frame is not None:
    print(f"boss spawned at frame={boss_spawn_frame}")
    zum_active = [cpu.mem[ZUM_POOL + i * ZUM_SLOT_SIZE] for i in range(ZUM_SLOT_COUNT)]
    check("Zum: both slots are inactive (ACT=0) at the exact moment the boss spawns",
          all(a == 0 for a in zum_active))
    check("BigZum: inactive (ACT=0) at the exact moment the boss spawns - the code-level "
          "BIGZUM_RETREAT_TICK safety net (see UPDATE_ONE_BIGZUM's own comment) is what "
          "actually guarantees this one, independent of schedule content",
          cpu.mem[BIGZUM_POOL] == 0)
    check("Flyer: inactive (ACT=0) at the exact moment the boss spawns",
          cpu.mem[FLYER_POOL] == 0)
    check("Etank: inactive (ACT=0) at the exact moment the boss spawns",
          cpu.mem[ETANK_POOL] == 0)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
