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

NIGHT_ROW = sym["NIGHT_ROW"]
NIGHT_NEXT_TICK = sym["NIGHT_NEXT_TICK"]
NIGHT_CODE = sym["NIGHT_CODE"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
NIGHT_START_ROW = sym["NIGHT_START_ROW"]
NIGHT_END_ROW = sym["NIGHT_END_ROW"]
GAME_TICK = sym["GAME_TICK"]

R1 = NIGHT_START_ROW        # first row the sweep touches - "スコアの下の行"
R0 = NIGHT_START_ROW - 1    # the row above it (row0, the HUD/score row) - never touched
R2 = NIGHT_START_ROW + 1    # the 2nd row the sweep touches


def name_row(cpu, row):
    base = 0x1800 + row * 32
    return list(cpu.vram[base:base + 32])


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# Test 1: boot state - nothing converted yet, NIGHT_ROW=0, next trigger
# at NIGHT_START_TICK(100).
cpu = fresh_cpu()
check("NIGHT_ROW is 0 at boot (not started)", cpu.mem[NIGHT_ROW] == 0)
check("NIGHT_NEXT_TICK is 100 at boot",
      cpu.mem[NIGHT_NEXT_TICK] | (cpu.mem[NIGHT_NEXT_TICK+1] << 8) == 100)
check("NIGHT_START_ROW is right below the score row (row0)", NIGHT_START_ROW == 1)
check("the start row is untouched (not NIGHT_CODE) before the effect starts",
      NIGHT_CODE not in name_row(cpu, R1))

# Test 2: directly call CHECK_NIGHT with GAME_TICK primed to 100 - the
# start row becomes the striped leading row, nothing else touched yet.
cpu = fresh_cpu()
row0_before = name_row(cpu, R0)
set_game_tick(cpu, 100)
call_routine(cpu, "CHECK_NIGHT")
check("NIGHT_ROW advances to NIGHT_START_ROW", cpu.mem[NIGHT_ROW] == R1)
check("the start row is entirely filled with NIGHT_CODE",
      name_row(cpu, R1) == [NIGHT_CODE] * 32)
check("row0 (the score/HUD row, above the band) is byte-for-byte unchanged",
      name_row(cpu, R0) == row0_before)
check("the 2nd row (not yet reached) is untouched", NIGHT_CODE not in name_row(cpu, R2))

# Test 3: advance to the 2nd trigger (GAME_TICK=116) - the start row
# solidifies to black, the 2nd row becomes the new striped leading row.
set_game_tick(cpu, 116)
call_routine(cpu, "CHECK_NIGHT")
check("NIGHT_ROW advances to the 2nd row", cpu.mem[NIGHT_ROW] == R2)
check("the start row is now solid HUD_ROW_BLANK_CODE (black)",
      name_row(cpu, R1) == [HUD_ROW_BLANK_CODE] * 32)
check("the 2nd row is now the striped leading row",
      name_row(cpu, R2) == [NIGHT_CODE] * 32)

# Test 4: calling again at the SAME tick does nothing (not yet time
# for the 3rd trigger, which needs GAME_TICK>=132).
call_routine(cpu, "CHECK_NIGHT")
check("no further advance without GAME_TICK reaching the next threshold",
      cpu.mem[NIGHT_ROW] == R2)

# Test 5: jump straight to the final row (NIGHT_END_ROW=16) and confirm
# the effect stops there - the SkySand row itself never gets solidified
# to black (only rows ABOVE it do), and further CHECK_NIGHT calls are
# no-ops once NIGHT_ROW==NIGHT_END_ROW.
cpu2 = fresh_cpu()
cpu2.mem[NIGHT_ROW] = NIGHT_END_ROW - 1
tick_for_last = 100 + (NIGHT_END_ROW - NIGHT_START_ROW) * 16
set_game_tick(cpu2, tick_for_last)
cpu2.mem[NIGHT_NEXT_TICK] = tick_for_last & 0xFF
cpu2.mem[NIGHT_NEXT_TICK + 1] = (tick_for_last >> 8) & 0xFF
call_routine(cpu2, "CHECK_NIGHT")
check("NIGHT_ROW reaches NIGHT_END_ROW(16)", cpu2.mem[NIGHT_ROW] == NIGHT_END_ROW)
check("row16 (the SkySand row) is the striped leading row, not blackened",
      name_row(cpu2, NIGHT_END_ROW) == [NIGHT_CODE] * 32)
before = name_row(cpu2, NIGHT_END_ROW)
call_routine(cpu2, "CHECK_NIGHT")
check("further calls are a no-op once NIGHT_END_ROW is reached",
      cpu2.mem[NIGHT_ROW] == NIGHT_END_ROW and name_row(cpu2, NIGHT_END_ROW) == before)

# Test 6: full real end-to-end timing through the actual MAINLOOP -
# confirm the first row change happens at real frame ~800 (GAME_TICK
# reaches 100 at raw frame 800) and NOT before.
cpu3 = fresh_cpu()
cpu3.sim_dir = 0
cpu3.sim_trig_a = False
cpu3.sim_trig_b = False
first_change_frame = None
for f in range(850):
    step_frame(cpu3)
    if cpu3.mem[NIGHT_ROW] != 0 and first_change_frame is None:
        first_change_frame = f
check("real MAINLOOP: night effect starts at frame ~799 (GAME_TICK=100), not earlier",
      first_change_frame is not None and 795 <= first_change_frame <= 800)
print(f"first_change_frame={first_change_frame}")

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
