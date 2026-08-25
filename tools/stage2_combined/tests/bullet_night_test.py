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

BULLET_MIN_ROW = sym["BULLET_MIN_ROW"]
NIGHT_ROW = sym["NIGHT_ROW"]
SKY_BLANK_CODE = sym["SKY_BLANK_CODE"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
BULLET0_ACT = sym["BULLET0_ACT"]
BULLET_TEMP_BYTE = sym["BULLET_TEMP_BYTE"]

check("BULLET_MIN_ROW is now 1 (only row0 guarded)", BULLET_MIN_ROW == 1)

# Test: a diagonal/climbing bullet can now reach row1 (real MAINLOOP
# path, IX+1 nonzero = the climb flag).
cpu = fresh_cpu()
ix = BULLET0_ACT
cpu.mem[ix+0] = 1
cpu.mem[ix+1] = 1
cpu.mem[ix+2] = 10
cpu.mem[ix+3] = 2
cpu.mem[ix+4] = 0
cpu.mem[ix+5] = 0x1A
cpu.mem[ix+6] = 0
cpu.ix = ix
call_routine(cpu, "UPDATE_ONE_BULLET")
check("a climbing bullet can now reach row1 (was blocked at row2 before)",
      cpu.mem[ix+3] == 1 and cpu.mem[ix+0] == 1)

# Test: it still deactivates rather than ever reaching row0 (the
# score/HUD row itself stays protected).
cpu = fresh_cpu()
ix = BULLET0_ACT
cpu.mem[ix+0] = 1
cpu.mem[ix+1] = 1
cpu.mem[ix+2] = 10
cpu.mem[ix+3] = 1
cpu.mem[ix+4] = 0
cpu.mem[ix+5] = 0x18
cpu.mem[ix+6] = 0
cpu.ix = ix
call_routine(cpu, "UPDATE_ONE_BULLET")
check("deactivates instead of ever reaching row0 (still protected)",
      cpu.mem[ix+0] == 0)


def make_bullet_slot(cpu, row, col=10, addr=0x1800 + 5 * 32):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = 1        # ACT
    cpu.mem[ix + 1] = 0        # IX+1: diagonal-climb flag, 0 for horizontal(F)
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    cpu.mem[ix + 4] = addr & 0xFF
    cpu.mem[ix + 5] = (addr >> 8) & 0xFF
    cpu.mem[ix + 6] = 0
    return ix


# Test: ERASE_BULLET_CELL restores SKY_BLANK_CODE for a row the night
# sweep hasn't reached yet (NIGHT_ROW < bullet's row).
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 3
ix = make_bullet_slot(cpu, row=10)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("restores SKY_BLANK_CODE when the sweep hasn't reached this row yet (NIGHT_ROW=3, bullet row=10)",
      cpu.mem[BULLET_TEMP_BYTE] == SKY_BLANK_CODE)

# Test: ERASE_BULLET_CELL restores HUD_ROW_BLANK_CODE (black) once the
# sweep has already darkened this row (NIGHT_ROW >= bullet's row).
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 10
ix = make_bullet_slot(cpu, row=10)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("restores HUD_ROW_BLANK_CODE (black) once the sweep has already reached this row",
      cpu.mem[BULLET_TEMP_BYTE] == HUD_ROW_BLANK_CODE)

# Test: boundary - NIGHT_ROW exactly equal to the bullet's row (the
# currently-striped leading row) also restores black.
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 7
ix = make_bullet_slot(cpu, row=7)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("restores black at the exact boundary row (NIGHT_ROW==bullet row)",
      cpu.mem[BULLET_TEMP_BYTE] == HUD_ROW_BLANK_CODE)

# Test: before the night effect has started at all (NIGHT_ROW=0),
# always restores ordinary sky blue.
cpu = fresh_cpu()
ix = make_bullet_slot(cpu, row=5)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("restores SKY_BLANK_CODE before the night effect has started (NIGHT_ROW=0)",
      cpu.mem[BULLET_TEMP_BYTE] == SKY_BLANK_CODE)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
