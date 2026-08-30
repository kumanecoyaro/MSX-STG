"""Verifies the round36-14 follow-up#5 performance fix: "かなり動作速度
が遅くなったが 無駄な処理が無いか確認 ボス戦に入っているのに ボス以外
の処理が回っていないか 逆にボスまでにボスのみの処理が回ってないか".

This file audits (and locks in with tests) MAINLOOP's own 3-tier gating
around the boss fight:
  1. before the boss spawns (BOSS_ACT=0): every ordinary enemy type
     (ZacoII/Zum/BigZum/Flyer/Etank) keeps running, boss-only subsystems
     (Homing/Thunder/SBeam/broken-form beams) are skipped - already
     established (see SKIP_ZACO_ENEMY/SKIP_OTHER_ENEMIES/SKIP_BOSS_
     SUBSYSTEMS's own comments, an earlier round's fix for the mirror-
     image complaint: "それになんで常時ボスの処理走らせてんだよ").
  2. during the boss fight, normal form (BOSS_ACT=1, BOSS_FORM=0):
     ordinary enemies stay skipped (still established); Homing/Thunder/
     SBeam stay active (correct - they're what the boss actually uses
     in this form).
  3. during the boss fight, broken form (BOSS_FORM=BOSS_FORM_ACTIVE):
     everything from tier 2 still applies (an in-flight Homing/Thunder/
     SBeam launched just before the transition must keep updating) -
     PLUS the broken form's own 4-beam attack now runs too.

The actual bug found and fixed here: CHECK_BOSS_BROKEN_BEAM_VS_TANK was
called unconditionally for the WHOLE boss fight (tier 2 AND 3), even
though its own BOSS_BROKEN_PROJ_ACTIVE flags can only ever be set by
LAUNCH_BOSS_BROKEN_BEAM, which itself only ever runs once BOSS_FORM is
already ACTIVE - so the call was a guaranteed no-op for the entire
(normally much longer) tier-2 portion of the fight. Real per-frame
waste with the exact 3-tier shape this file's own established SKIP_*
precedent already exists to eliminate, just missing this one narrower
case. Fixed by gating the call itself on BOSS_FORM==BOSS_FORM_ACTIVE.
"""
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


BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_FORM_ACTIVE = sym["BOSS_FORM_ACTIVE"]
BOSS_BROKEN_PROJ_ACTIVE = sym["BOSS_BROKEN_PROJ_ACTIVE"]
BOSS_BROKEN_PROJ_X = sym["BOSS_BROKEN_PROJ_X"]
BOSS_BROKEN_PROJ_Y = sym["BOSS_BROKEN_PROJ_Y"]
BOSS_BROKEN_PROJ_DX = sym["BOSS_BROKEN_PROJ_DX"]
BOSS_BROKEN_PROJ_DY = sym["BOSS_BROKEN_PROJ_DY"]
BOSS_BROKEN_RECENTERING = sym["BOSS_BROKEN_RECENTERING"]
BOSS_BROKEN_MOVING = sym["BOSS_BROKEN_MOVING"]
BOSS_BROKEN_FRAME_COUNTER = sym["BOSS_BROKEN_FRAME_COUNTER"]
BOSS_BROKEN_STEPS_TO_STOP = sym["BOSS_BROKEN_STEPS_TO_STOP"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_LIFE = sym["TANK_LIFE"]
TANK_HAZARD_IFRAMES = sym["TANK_HAZARD_IFRAMES"]
TANK_COLLISION_X_OFFSET = sym["TANK_COLLISION_X_OFFSET"]
TANK_COLLISION_Y_OFFSET = sym["TANK_COLLISION_Y_OFFSET"]


def setup(cpu, boss_form):
    """boss present, 1 beam slot forced active with a box placed to
    EXACTLY overlap wherever the tank's own real collision box already
    sits right now (read back from the live post-boot state, not a
    guessed constant) - so the only variable being tested is whether
    the check even RUNS this frame, not whether the overlap math itself
    is right (already covered elsewhere). DX=DY=0 (stationary) so that,
    when BOSS_FORM=ACTIVE, this same frame's own UPDATE_BOSS_BROKEN_
    BEAM_FLIGHT (which now also runs unconditionally every ACTIVE-form
    frame) doesn't move the slot away before CHECK_BOSS_BROKEN_BEAM_VS_
    TANK gets to it later in the same MAINLOOP pass."""
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = 100
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_FORM] = boss_form
    cpu.mem[TANK_HAZARD_IFRAMES] = 0
    # fresh_cpu()'s own zeroed RAM means BOSS_BROKEN_RECENTERING/MOVING/
    # STEPS_TO_STOP would otherwise default to 0 - which UPDATE_BOSS_
    # BROKEN_ACTIVE (also running this same frame once boss_form=ACTIVE)
    # would read as "already stopped, 0 steps left" and immediately ARM
    # + fire a real beam launch into slot0 via UPDATE_BOSS_BROKEN_BEAM_
    # SEQ, clobbering this test's own synthetic slot0 before the check
    # under test even runs. Parking it mid-orbit with plenty of steps
    # left avoids that entirely (real, boring "just keep orbiting" state).
    cpu.mem[BOSS_BROKEN_RECENTERING] = 0
    cpu.mem[BOSS_BROKEN_MOVING] = 1
    cpu.mem[BOSS_BROKEN_FRAME_COUNTER] = 0
    cpu.mem[BOSS_BROKEN_STEPS_TO_STOP] = 250
    px = cpu.mem[TANK_X] + TANK_COLLISION_X_OFFSET
    py = cpu.mem[TANK_Y_CUR] + TANK_COLLISION_Y_OFFSET
    cpu.mem[BOSS_BROKEN_PROJ_ACTIVE + 0] = 1
    cpu.mem[BOSS_BROKEN_PROJ_X + 0] = px
    cpu.mem[BOSS_BROKEN_PROJ_Y + 0] = py
    cpu.mem[BOSS_BROKEN_PROJ_DX + 0] = 0
    cpu.mem[BOSS_BROKEN_PROJ_DY + 0] = 0


cpu = fresh_cpu()
setup(cpu, boss_form=0)
life0 = cpu.mem[TANK_LIFE]
step_frame(cpu)
check("MAINLOOP no longer calls CHECK_BOSS_BROKEN_BEAM_VS_TANK at all while BOSS_FORM is still "
      "0 (normal form) - a synthetically-forced-active beam slot placed exactly on top of the "
      "tank (impossible in real play, but proves the CALL SITE's own gate, not just that nothing "
      "happens to be active in practice) does NOT damage the tank, because the whole check never "
      "runs this frame",
      cpu.mem[TANK_LIFE] == life0)

cpu2 = fresh_cpu()
setup(cpu2, boss_form=BOSS_FORM_ACTIVE)
life1 = cpu2.mem[TANK_LIFE]
step_frame(cpu2)
check("...but the exact same setup WITH BOSS_FORM=ACTIVE still runs the check and damages the "
      "tank - proving this is a real, working gate, not an accidental permanent disable",
      cpu2.mem[TANK_LIFE] == life1 - 1)

# the other 2 tiers (ordinary enemies skipped once BOSS_ACT!=0, boss-
# only subsystems skipped while BOSS_ACT==0) were already established
# and locked in by an earlier round - not re-derived here, this file's
# own scope is the newly-found 3rd tier (CHECK_BOSS_BROKEN_BEAM_VS_TANK
# specifically) rather than re-proving code paths another round's own
# tests already cover.


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
