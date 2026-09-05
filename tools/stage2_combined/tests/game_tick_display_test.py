"""round34-2 ("Tickは999終了で繰り返さない"): the real GAME_TICK counter
itself must keep advancing forever, unclamped - the boss's own internal
timers (BOSS_LEFT_PAUSE_END_TICK/BOSS_POSE_END_TICK, both armed as
"GAME_TICK + some small constant" at whatever moment the boss happens to
reach that state) need it to. An earlier attempt this round capped the
real counter directly and softlocked the boss fight (BOSS_PHASE stuck at
2 forever) once GAME_TICK froze before the boss's own patrol reached the
left edge - see boss_pose_test.py's own real-MAINLOOP checks for the
regression guard against that specific mistake.

The actual fix is display-only: GAME_TICK_DISPLAY (row0 cols29-31, the
on-screen 3-digit counter) clamps its own readout at 999 once the real
GAME_TICK reaches/exceeds 1000, instead of wrapping MOD 1000 back to
"000" and counting up again - which is what "また0から始まってしまう"
(looks like it started over from 0) actually was: not a real restart of
anything (SPAWN2_NEXT_INDEX only ever moves forward, never resets), just
a genuinely confusing display artifact that could occur once GAME_TICK
itself simply keeps counting past 1000 (it never stops, boss or no
boss - see the real GAME_TICK increment's own comment).
"""
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
GTD_LAST_H = sym["GTD_LAST_H"]
GTD_LAST_T = sym["GTD_LAST_T"]
HUD_TEMP_BYTE = sym["HUD_TEMP_BYTE"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def displayed_digits(cpu, real_tick):
    cpu2 = fresh_cpu()
    set_game_tick(cpu2, real_tick)
    call_routine(cpu2, "GAME_TICK_DISPLAY")
    return cpu2.mem[GTD_LAST_H], cpu2.mem[GTD_LAST_T], cpu2.mem[HUD_TEMP_BYTE]


# ---------------------------------------------------------------------
# Test 1-2: below 1000, displays the real value exactly (unchanged
# behavior from before this round - each digit is a genuine 0-9 value,
# not garbled by the clamp branch's own control flow).
# ---------------------------------------------------------------------
for real_tick, expected in ((0, (0, 0, 0)), (5, (0, 0, 5)), (247, (2, 4, 7)), (998, (9, 9, 8))):
    got = displayed_digits(None, real_tick)
    check(f"GAME_TICK={real_tick} displays as {expected[0]}{expected[1]}{expected[2]} (unclamped range)",
          got == expected)

# ---------------------------------------------------------------------
# Test 3: the exact boundary - 999 displays as 999, not yet clamped
# (nothing to clamp, it's already at the ceiling).
# ---------------------------------------------------------------------
check("GAME_TICK=999 displays as 999 (the ceiling itself, not yet over it)",
      displayed_digits(None, 999) == (9, 9, 9))

# ---------------------------------------------------------------------
# Test 4-6: at/over 1000, clamps to 999 - does NOT wrap back toward 0.
# This is the actual regression this file exists to catch: the first
# version of this clamp jumped into the hundreds-digit-extraction loop
# without initializing B first (the branch used for GAME_TICK<1000 does
# `LD B,0` right before that same loop; the new >=1000 branch jumped
# straight past it), so the "hundreds" digit came out as garbage/wrong
# (observed as B=10 instead of 9 in this exact scenario during
# development) rather than a clean 999.
# ---------------------------------------------------------------------
for real_tick in (1000, 1001, 1341, 5000, 65000):
    got = displayed_digits(None, real_tick)
    check(f"GAME_TICK={real_tick} clamps the display to 999 (not a MOD-1000 wrap back toward 0)",
          got == (9, 9, 9))

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
