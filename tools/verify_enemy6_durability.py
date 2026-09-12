"""Stage1: エネミー6(回転グリフ敵)の耐久値制(2026-09-08、"ステージ1の
エネミー6の耐久値4に")の検証。tools/verify_enemy_bullets.py と同じ
「mini_z80asm.Assemblerで直接アセンブル+call_routine(センチネル0x0000
方式)」の一回性検証スクリプトの作法に倣う。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=300000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


ENEMY6_POOL = sym["ENEMY6_POOL"]
ENEMY6_STRUCT = sym["ENEMY6_STRUCT"]
ENEMY6_HP = sym["ENEMY6_HP"]
ENEMY6_HP_INIT = sym["ENEMY6_HP_INIT"]
ENEMY6_ROW_TABLE = sym["ENEMY6_ROW_TABLE"]
SPAWN_E6 = sym["SPAWN_E6"]
ENEMY6_HIT_ONE_SLOT = sym["ENEMY6_HIT_ONE_SLOT"]

check("ENEMY6_HP_INIT is 4 (\"耐久値4に\")", ENEMY6_HP_INIT == 4)


def spawn_enemy6(z, row_table_index=0, row=10):
    """Spawns via the real SPAWN_E6 entry point (HL=schedule index on
    entry - 2026-09-12: widened from A to HL so index>=256 works, see
    SPAWN_SCHEDULE_CHECK's own comment), matching SSC_FIRE's own
    calling convention."""
    z.wr(ENEMY6_ROW_TABLE + row_table_index, row)
    z.h = (row_table_index >> 8) & 0xFF
    z.l = row_table_index & 0xFF
    call_routine(z, SPAWN_E6)


def slot0():
    return ENEMY6_POOL


z = fresh()
spawn_enemy6(z)
hp0 = z.rd(ENEMY6_HP)
check(f"SPAWN_E6 initializes the new slot's HP to ENEMY6_HP_INIT ({ENEMY6_HP_INIT})",
      hp0 == ENEMY6_HP_INIT)
check("SPAWN_E6 marks the slot active (ACTIVE=1)", z.rd(slot0()) == 1)

# ---- a bullet hit 3 times (HP 4->1) must NOT destroy it - the enemy ----
# ---- stays active, but the bullet is still consumed each time (A=1). ----
IX = slot0()
row = z.rd(IX + 1)
col = z.rd(IX + 2)
bullet_col = col
bullet_row = row


def hit_test_call(z):
    """Calls ENEMY6_HIT_ONE_SLOT directly with IX=slot0, B/C=bullet col/row
    (matches the (IX,B,C) input contract documented at ENEMY6_HIT_ONE_SLOT's
    own comment) and returns A (1=hit registered)."""
    z.ix = IX
    z.b = bullet_col
    z.c = bullet_row
    call_routine(z, ENEMY6_HIT_ONE_SLOT)
    return z.a


for i in range(1, 4):
    result = hit_test_call(z)
    hp = z.rd(ENEMY6_HP)
    check(f"hit #{i}: bullet is consumed (A=1) but the enemy survives "
          f"(ACTIVE stays 1, HP={ENEMY6_HP_INIT - i})",
          result == 1 and z.rd(IX) == 1 and hp == ENEMY6_HP_INIT - i)

# 4th hit: HP reaches 0 - now it actually dies (ACTIVE=0).
result4 = hit_test_call(z)
check("hit #4 (HP reaches 0): bullet is consumed AND the enemy is finally "
      "destroyed (ACTIVE=0)",
      result4 == 1 and z.rd(IX) == 0)
check("on the killing hit, HP itself lands exactly at 0 (not wrapped/negative)",
      z.rd(ENEMY6_HP) == 0)

# ---- a hit on an already-inactive slot must be a clean no-op (A=0), ----
# ---- not decrement HP further or crash. ----
result5 = hit_test_call(z)
check("hitting an already-destroyed slot again returns A=0 (no-op, no crash)",
      result5 == 0)
check("...and does not further decrement HP below 0", z.rd(ENEMY6_HP) == 0)

# ---- a miss (bullet not overlapping) must not touch HP at all. ----
z2 = fresh()
spawn_enemy6(z2)
z2.ix = slot0()
z2.b = 0   # far away column - definitely not overlapping
z2.c = 0
call_routine(z2, ENEMY6_HIT_ONE_SLOT)
check("a clean miss leaves HP completely untouched (still ENEMY6_HP_INIT)",
      z2.rd(ENEMY6_HP) == ENEMY6_HP_INIT and z2.a == 0)

# ---- ENEMY6_HP_ADDR indexing must be correct for a non-zero slot too - ----
# ---- not just slot0 (guards against an off-by-N in the pointer math). ----
z3 = fresh()
# occupy slot0 first so the 2nd spawn lands in slot1
spawn_enemy6(z3, row_table_index=0, row=5)
spawn_enemy6(z3, row_table_index=1, row=8)
slot1 = ENEMY6_POOL + ENEMY6_STRUCT
check("2nd SPAWN_E6 call lands in slot1 (slot0 was already occupied)",
      z3.rd(slot1) == 1 and z3.rd(slot1 + 1) == 8)
check("slot1's own HP (ENEMY6_HP+1) was initialized independently of slot0's",
      z3.rd(ENEMY6_HP) == ENEMY6_HP_INIT and z3.rd(ENEMY6_HP + 1) == ENEMY6_HP_INIT)

z3.ix = slot1
z3.b = z3.rd(slot1 + 2)
z3.c = z3.rd(slot1 + 1)
call_routine(z3, ENEMY6_HIT_ONE_SLOT)
check("a hit on slot1 decrements ONLY ENEMY6_HP+1, leaving slot0's own HP "
      "(ENEMY6_HP+0) untouched - confirms ENEMY6_HP_ADDR indexes the right "
      "byte for a non-zero slot, not just slot0",
      z3.rd(ENEMY6_HP + 1) == ENEMY6_HP_INIT - 1 and z3.rd(ENEMY6_HP) == ENEMY6_HP_INIT)

# ---- INIT clears the whole ENEMY6_HP array (poison test) ----
z4 = fresh()
for i in range(32):
    z4.wr(ENEMY6_HP + i, 0xAA)
z4.pc = sym["INIT"]
# MISSION_DELAY_3SEC would blow the instruction budget in a full INIT trace -
# shrink it the same way verify_enemy_bullets.py does.
z4.wr(sym["MISSION_DELAY_3SEC"] + 1, 1)
run_until_pc(z4, sym["MAINLOOP"], max_instr=2_000_000)
check("INIT zero-clears the entire ENEMY6_HP array (all 32 bytes), not just "
      "slot0 - poisoned with 0xAA beforehand to catch a partial/short clear",
      all(z4.rd(ENEMY6_HP + i) == 0 for i in range(32)))

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
