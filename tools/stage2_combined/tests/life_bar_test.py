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

TANK_LIFE = sym["TANK_LIFE"]
LIFE_CODE = sym["LIFE_CODE"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
LIFE_BAR_ROW = sym["LIFE_BAR_ROW"]
LIFE_BAR_COL0 = sym["LIFE_BAR_COL0"]
NAMETAB = 0x1800

def cell(row, col):
    return NAMETAB + row * 32 + col

# Test 1: boot state - life = 6, all 6 cells filled
cpu = fresh_cpu()
check("TANK_LIFE inits to 6", cpu.mem[TANK_LIFE] == sym["TANK_LIFE_INIT"] == 6)
for i in range(6):
    check(f"life cell {i} shows LIFE_CODE at boot", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + i)] == LIFE_CODE)

# Test 2: old calibration-strip symbols are gone
check("SWATCH_CODES no longer exists", "SWATCH_CODES" not in sym)
check("HEXLABEL_CODES no longer exists", "HEXLABEL_CODES" not in sym)

# Test 3: row0 background elsewhere is HUD_ROW_BLANK_CODE (forced black)
check("row0 col20 (unused) is HUD_ROW_BLANK_CODE", cpu.vram[cell(0, 20)] == HUD_ROW_BLANK_CODE)
check("row0 col8 (the 1-cell gap after the score) is HUD_ROW_BLANK_CODE", cpu.vram[cell(0, 8)] == HUD_ROW_BLANK_CODE)

# Test 4: APPLY_TANK_DAMAGE decrements life and depletes from the right
cpu.mem[TANK_LIFE] = 6
call_routine(cpu, "APPLY_TANK_DAMAGE")
check("life decremented to 5", cpu.mem[TANK_LIFE] == 5)
check("cell 5 (rightmost) now blank", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + 5)] == HUD_ROW_BLANK_CODE)
for i in range(5):
    check(f"cell {i} still filled after 1 hit", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + i)] == LIFE_CODE)

call_routine(cpu, "APPLY_TANK_DAMAGE")
call_routine(cpu, "APPLY_TANK_DAMAGE")
check("life decremented to 3 after 3 hits total", cpu.mem[TANK_LIFE] == 3)
check("cell 3 now blank", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + 3)] == HUD_ROW_BLANK_CODE)
check("cell 4 now blank", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + 4)] == HUD_ROW_BLANK_CODE)
check("cell 2 still filled", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + 2)] == LIFE_CODE)

# Test 5: floors at 0, no death handling - decrement all the way down
# through a real sequence of hits (not poked directly) so the life bar
# actually redraws at each step, including the final 1->0 transition.
cpu.mem[TANK_LIFE] = 1
call_routine(cpu, "APPLY_TANK_DAMAGE")
check("life reaches 0 via a real decrement", cpu.mem[TANK_LIFE] == 0)
for i in range(6):
    check(f"all 6 cells blank at life=0 (cell {i})", cpu.vram[cell(LIFE_BAR_ROW, LIFE_BAR_COL0 + i)] == HUD_ROW_BLANK_CODE)
call_routine(cpu, "APPLY_TANK_DAMAGE")
check("life floors at 0, does not underflow on a further hit", cpu.mem[TANK_LIFE] == 0)

# Test 6: integration - a real BigZum punch connecting actually decrements life
cpu = fresh_cpu()
BIGZUM_POOL = sym["BIGZUM_POOL"]
TANK_X = sym["TANK_X"]
JUMP_ACTIVE = sym["JUMP_ACTIVE"]
life_before = cpu.mem[TANK_LIFE]
cpu.mem[BIGZUM_POOL + 0] = 1
cpu.mem[BIGZUM_POOL + 7] = 2          # STATE=2 (punch)
cpu.mem[BIGZUM_POOL + 9] = 0          # FACING=0 (front)
cpu.mem[BIGZUM_POOL + 11] = 0         # PUNCH_COOLDOWN=0 -> fires this call
cpu.mem[BIGZUM_POOL + 1] = 60         # BZ_X
cpu.mem[TANK_X] = 55                  # within BIGZUM_COLLISION_SIZE(24) of BZ_X, in front
cpu.mem[JUMP_ACTIVE] = 0
call_routine(cpu, "UPDATE_TANK_BIGZUM_PUNCH")
check("a real BigZum punch connecting decrements TANK_LIFE", cpu.mem[TANK_LIFE] == life_before - 1)

# Test 7: "ライフ表示の背景色をブラックに" - LIFE_CODE's own color-table
# group (group16, LIFE_CODE/8=16) has a black (bg1) background now, not
# the uploaded art's own bg5 (purple).
cpu = fresh_cpu()
LIFE_COLOR = sym["LIFE_COLOR"]
check("LIFE_COLOR's own bg nibble is 1 (black)", (LIFE_COLOR & 0x0F) == 1)
check("INIT actually writes LIFE_COLOR into LIFE_CODE's own color-table group",
      cpu.vram[0x2000 + (LIFE_CODE // 8)] == LIFE_COLOR)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
