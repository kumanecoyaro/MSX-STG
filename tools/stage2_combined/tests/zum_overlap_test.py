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

ZUM_POOL = sym["ZUM_POOL"]
ZUM_SLOT_SIZE = sym["ZUM_SLOT_SIZE"]
ZUM_SPRITE_ATTRS = sym["ZUM_SPRITE_ATTRS"]

check("ZUM_POOL and ZUM_SPRITE_ATTRS no longer overlap",
      ZUM_POOL + ZUM_SLOT_SIZE * 2 <= ZUM_SPRITE_ATTRS)

# Reproduce the actual bug scenario: slot1's own Z_DY/Z_RETREAT
# (offsets +6/+7 within slot1, i.e. ZUM_POOL+14/+15) must survive
# UOZ_DRAW writing slot0's own hw sprite Y/X into ZUM_SPRITE_ATTRS's
# first 2 bytes - before the fix, those were the SAME 2 physical bytes.
cpu = fresh_cpu()
slot1_base = ZUM_POOL + ZUM_SLOT_SIZE
cpu.mem[slot1_base + 0] = 1     # Z_ACT=1 (alive)
cpu.mem[slot1_base + 6] = 0xAA  # Z_DY sentinel
cpu.mem[slot1_base + 7] = 0xBB  # Z_RETREAT sentinel
cpu.mem[ZUM_POOL + 4] = 0       # slot0's own Z_SPRIDX=0 -> writes ZUM_SPRITE_ATTRS+0
cpu.mem[ZUM_POOL + 1] = 111     # slot0's own Z_Y (arbitrary)
cpu.mem[ZUM_POOL + 2] = 222     # wait: field order is +1 X,+2 Y - UOZ_DRAW writes (IX+2) then (IX+1)
cpu.ix = ZUM_POOL
call_routine(cpu, "UOZ_DRAW")
check("Zum slot1's Z_DY (ZUM_POOL+14) survives UOZ_DRAW writing slot0's sprite attrs", cpu.mem[slot1_base + 6] == 0xAA)
check("Zum slot1's Z_RETREAT (ZUM_POOL+15) survives UOZ_DRAW writing slot0's sprite attrs", cpu.mem[slot1_base + 7] == 0xBB)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
