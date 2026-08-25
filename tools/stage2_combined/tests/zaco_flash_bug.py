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

ENEMY_POOL = sym["ENEMY_POOL"]
E_ACT = sym["E_ACT"]; E_X = sym["E_X"]; E_Y = sym["E_Y"]
E_TIMER = sym["E_TIMER"]; E_DY = sym["E_DY"]; E_RETREAT = sym["E_RETREAT"]

# Reproduce the exact bug scenario: a slot's previous occupant died mid-
# explosion with a nonzero E_DY (vertical drift), the slot frees up
# (E_ACT->0) without E_DY ever being cleared, then a fresh enemy spawns
# into that same slot - before the fix, it would inherit the stale E_DY
# and immediately render white (hit-flash) for that many frames.
cpu = fresh_cpu()
IX = ENEMY_POOL
cpu.mem[IX+E_ACT] = 2       # exploding
cpu.mem[IX+E_TIMER] = 1     # about to finish (1 more frame)
cpu.mem[IX+E_DY] = 2        # nonzero vertical explosion drift, left behind
cpu.ix = IX
call_routine(cpu, "UPDATE_ONE_ENEMY")  # E_TIMER hits 0 next call -> hides, E_ACT=0
call_routine(cpu, "UPDATE_ONE_ENEMY")
check("slot freed up (E_ACT=0) after explosion finishes", cpu.mem[IX+E_ACT] == 0)
check("E_DY still holds the stale leftover explosion-drift value before respawn", cpu.mem[IX+E_DY] == 2)

# Now spawn a fresh enemy into this exact freed slot.
cpu.mem[sym["GAME_RNG"]] = 0
call_routine(cpu, "ALLOC_ENEMY_SLOT")
check("fresh spawn lands in the reused slot", cpu.mem[IX+E_ACT] == 1)
check("E_DY (hit-flash timer while alive) is cleared at spawn - no phantom white flash", cpu.mem[IX+E_DY] == 0)

# Draw it and confirm the color resolves to the normal variant color, not FLASH_COLOR.
cpu.mem[IX+sym["E_VARIANT"]] = 0  # green
call_routine(cpu, "UOE_DRAW")
ENEMY_SPRITE_ATTRS = sym["ENEMY_SPRITE_ATTRS"]
spridx = cpu.mem[IX+sym["E_SPRIDX"]]
color = cpu.mem[ENEMY_SPRITE_ATTRS + spridx*4 + 3]
check("drawn color is the normal green ENEMY_COLOR, not FLASH_COLOR(white)", color == sym["ENEMY_COLOR"])
check("drawn color is not FLASH_COLOR", color != sym["FLASH_COLOR"])

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
