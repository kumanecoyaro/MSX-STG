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

NIGHT_ROW = sym["NIGHT_ROW"]
NIGHT_END_ROW = sym["NIGHT_END_ROW"]
NIGHT_CODE = sym["NIGHT_CODE"]
SKYSAND_CODE = sym["SKYSAND_CODE"]
BULLETF_SKY_CODE = sym["BULLETF_SKY_CODE"]
BULLETF_L_SKY_CODE = sym["BULLETF_L_SKY_CODE"]
BULLETF_ROCK_CODE = sym["BULLETF_ROCK_CODE"]
BULLETF_NIGHT_CODE = sym["BULLETF_NIGHT_CODE"]
BULLETF_L_NIGHT_CODE = sym["BULLETF_L_NIGHT_CODE"]
BULLET0_ACT = sym["BULLET0_ACT"]
BULLET_TEMP_BYTE = sym["BULLET_TEMP_BYTE"]
BULLET_ROCK_COLOR_ROW_MIN_F = sym["BULLET_ROCK_COLOR_ROW_MIN_F"]


def make_bullet_slot(cpu, row, facing=0, col=10, addr=0x1800 + 5 * 32):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = 1
    cpu.mem[ix + 1] = 0
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    cpu.mem[ix + 4] = addr & 0xFF
    cpu.mem[ix + 5] = (addr >> 8) & 0xFF
    cpu.mem[ix + 6] = facing
    return ix


# ---- EBC_SKYSAND (ERASE_BULLET_CELL's row16 restore) ----

# before the sweep reaches row16: still restores the real SkySand tile
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 10
ix = make_bullet_slot(cpu, row=NIGHT_END_ROW)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("EBC_SKYSAND restores SKYSAND_CODE before the sweep reaches row16",
      cpu.mem[BULLET_TEMP_BYTE] == SKYSAND_CODE)

# once the sweep has reached row16: restores NIGHT_CODE instead (row16's
# real on-screen content once CHECK_NIGHT gets there)
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = NIGHT_END_ROW
ix = make_bullet_slot(cpu, row=NIGHT_END_ROW)
cpu.ix = ix
call_routine(cpu, "ERASE_BULLET_CELL")
check("EBC_SKYSAND restores NIGHT_CODE once the sweep has reached row16",
      cpu.mem[BULLET_TEMP_BYTE] == NIGHT_CODE)

# ---- DRAW_BULLET_CELL's night-black glyph ----
# "Skysandとその上の行でショットの背景色をブラックにすれば良い" - the
# whole sky+SkySand band (rows0-16) gets the night glyph once the
# sweep has reached that row - no row15/16 exclusion (an earlier,
# narrower row0-14 cutoff was wrong, corrected here).

# row5, sweep hasn't reached it yet -> ordinary day glyph
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 0
ix = make_bullet_slot(cpu, row=5, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL uses the ordinary day glyph before the sweep reaches this row",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_SKY_CODE)

# row5, sweep has reached it -> night glyph (facing right)
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 5
ix = make_bullet_slot(cpu, row=5, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL uses the night glyph once the sweep has reached this row (facing right)",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_NIGHT_CODE)

# row5, facing left -> night glyph, left variant
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 5
ix = make_bullet_slot(cpu, row=5, facing=1)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL uses the left-facing night glyph",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_L_NIGHT_CODE)

# row15 - once the sweep has reached it, night glyph too (no longer
# excluded)
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 15
ix = make_bullet_slot(cpu, row=15, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL row15 uses the night glyph once the sweep has reached it",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_NIGHT_CODE)

# row16 (SkySand) - once the sweep has reached it, night glyph too
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = NIGHT_END_ROW
ix = make_bullet_slot(cpu, row=NIGHT_END_ROW, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL row16 (SkySand) uses the night glyph once the sweep has reached it",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_NIGHT_CODE)

# row16, sweep NOT yet reached it -> still the ordinary day glyph
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 10
ix = make_bullet_slot(cpu, row=NIGHT_END_ROW, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL row16 uses the ordinary day glyph before the sweep reaches it",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_SKY_CODE)

# row17 (Sand, ground) - always the rock-style glyph, night-independent
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = NIGHT_END_ROW
ix = make_bullet_slot(cpu, row=BULLET_ROCK_COLOR_ROW_MIN_F, facing=0)
cpu.ix = ix
call_routine(cpu, "DRAW_BULLET_CELL")
check("DRAW_BULLET_CELL row17 (Sand) always uses the rock glyph, unaffected by night",
      cpu.mem[BULLET_TEMP_BYTE] == BULLETF_ROCK_CODE)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
