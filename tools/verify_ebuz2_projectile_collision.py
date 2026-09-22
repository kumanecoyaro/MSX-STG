"""Stage1: round145("EbuzIIで敵の弾やビームにコリジョンがない...いずれも
先端1pxの判定を入れてくれ")の検証。PDC_CHECK_EBUZ2_V1(volley1)/
PDC_CHECK_EBUZ2_V2(volley2)/PDC_CHECK_EBUZ2_LASER(レーザー先端1px)を、
他のtools/verify_*.pyと同じ「mini_z80asm.Assemblerで直接アセンブル+
call_routineの一回性検証スクリプト」の作法で直接検証する。
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
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    for _ in range(max_instr):
        if z.pc == 0x0000:
            return
        z.step()
    raise RuntimeError(f"never returned from {entry_addr:04X}, stuck at {z.pc:04X}")


PLAYERX = sym["PLAYERX"]; PLAYERY = sym["PLAYERY"]
PX, PY = 104, 112  # both multiples of 8 for exact cell-boundary math below

# ---------- PDC_CHECK_EBUZ2_V1 (volley1, 5 lanes) ----------
EBUZ2_V1_STRUCT = sym["EBUZ2_V1_STRUCT"]
EBUZ2_ENTRY_TARGET_ROW = sym["EBUZ2_ENTRY_TARGET_ROW"]

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
lane = 0
row = lane + EBUZ2_ENTRY_TARGET_ROW
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 0, 1)          # ACT
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 1, PX // 8)    # COL
z.wr(PLAYERY, row * 8)
call_routine(z, sym["PDC_CHECK_EBUZ2_V1"])
check("PDC_CHECK_EBUZ2_V1: lane0's active bullet, positioned exactly at the player, hits",
      z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
lane = 3
row = lane + EBUZ2_ENTRY_TARGET_ROW
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 0, 1)
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 1, PX // 8)
z.wr(PLAYERY, row * 8)
call_routine(z, sym["PDC_CHECK_EBUZ2_V1"])
check("PDC_CHECK_EBUZ2_V1: a different lane (3) also hits at its own row", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
for lane in range(5):
    z.wr(EBUZ2_V1_STRUCT + lane * 2 + 0, 0)  # all inactive
call_routine(z, sym["PDC_CHECK_EBUZ2_V1"])
check("PDC_CHECK_EBUZ2_V1: all lanes inactive never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBUZ2_V1_STRUCT + 0 * 2 + 0, 1)
z.wr(EBUZ2_V1_STRUCT + 0 * 2 + 1, 30)  # far column, well clear of the player
call_routine(z, sym["PDC_CHECK_EBUZ2_V1"])
check("PDC_CHECK_EBUZ2_V1: an active bullet far from the player never hits", z.a == 0)

# ---------- PDC_CHECK_EBUZ2_V2 (volley2, 4 ports x 4 slots) ----------
EBUZ2_V2_COLS = sym["EBUZ2_V2_COLS"]
EBUZ2_V2_ROWS = sym["EBUZ2_V2_ROWS"]
EBUZ2_SLOT_EMPTY = sym["EBUZ2_SLOT_EMPTY"]

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
for i in range(16):
    z.wr(EBUZ2_V2_COLS + i, EBUZ2_SLOT_EMPTY)
slot = 5
z.wr(EBUZ2_V2_COLS + slot, PX // 8)
z.wr(EBUZ2_V2_ROWS + slot, PY // 8)
call_routine(z, sym["PDC_CHECK_EBUZ2_V2"])
check("PDC_CHECK_EBUZ2_V2: an active slot positioned exactly at the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
for i in range(16):
    z.wr(EBUZ2_V2_COLS + i, EBUZ2_SLOT_EMPTY)
call_routine(z, sym["PDC_CHECK_EBUZ2_V2"])
check("PDC_CHECK_EBUZ2_V2: all slots empty (EBUZ2_SLOT_EMPTY) never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
for i in range(16):
    z.wr(EBUZ2_V2_COLS + i, EBUZ2_SLOT_EMPTY)
z.wr(EBUZ2_V2_COLS + 15, 30)  # far column, last slot
z.wr(EBUZ2_V2_ROWS + 15, 5)
call_routine(z, sym["PDC_CHECK_EBUZ2_V2"])
check("PDC_CHECK_EBUZ2_V2: an active but distant slot (including the last of 16) never hits", z.a == 0)

# ---------- PDC_CHECK_EBUZ2_LASER (tip-only, 1px) ----------
EBUZ2_LASER_ACT = sym["EBUZ2_LASER_ACT"]
EBUZ2_LASER_HOLD = sym["EBUZ2_LASER_HOLD"]
EBUZ2_LASER_UNIT = sym["EBUZ2_LASER_UNIT"]
EBUZ2_LASER_ROW = sym["EBUZ2_LASER_ROW"]

# HOLD phase (freshly fired, full length): tip is the fixed col22.
z = fresh()
z.wr(PLAYERX, 22 * 8); z.wr(PLAYERY, 7 * 8)
z.wr(EBUZ2_LASER_ACT, 1)
z.wr(EBUZ2_LASER_HOLD, 4)  # non-zero -> still holding
z.wr(EBUZ2_LASER_ROW, 7)
call_routine(z, sym["PDC_CHECK_EBUZ2_LASER"])
check("PDC_CHECK_EBUZ2_LASER: during HOLD (full length), the tip at the fixed col22 hits",
      z.a == 1)

# retract phase: tip follows EBUZ2_LASER_UNIT*2+2
z = fresh()
unit = 5
z.wr(PLAYERX, (unit * 2 + 2) * 8); z.wr(PLAYERY, 9 * 8)
z.wr(EBUZ2_LASER_ACT, 1)
z.wr(EBUZ2_LASER_HOLD, 0)  # retracting
z.wr(EBUZ2_LASER_UNIT, unit)
z.wr(EBUZ2_LASER_ROW, 9)
call_routine(z, sym["PDC_CHECK_EBUZ2_LASER"])
check("PDC_CHECK_EBUZ2_LASER: during retract, the tip follows EBUZ2_LASER_UNIT*2+2 and hits there",
      z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBUZ2_LASER_ACT, 0)
call_routine(z, sym["PDC_CHECK_EBUZ2_LASER"])
check("PDC_CHECK_EBUZ2_LASER: inactive laser never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBUZ2_LASER_ACT, 1)
z.wr(EBUZ2_LASER_HOLD, 4)
z.wr(EBUZ2_LASER_ROW, 0)  # wrong row entirely
call_routine(z, sym["PDC_CHECK_EBUZ2_LASER"])
check("PDC_CHECK_EBUZ2_LASER: active laser on a different row never hits", z.a == 0)

# ---------- PDC_CHECK_EBUZ2's own dispatch: body-miss falls through to the ----------
# ---------- new projectile checks (this is the actual wiring the user's bug ----------
# ---------- report needed; V1/V2/Laser above only prove the sub-routines work) ----------
EBUZ2_ACT = sym["EBUZ2_ACT"]; EBUZ2_PHASE = sym["EBUZ2_PHASE"]; EBUZ2_ROW_CUR = sym["EBUZ2_ROW_CUR"]

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBUZ2_ACT, 1)
z.wr(EBUZ2_PHASE, 1)       # active, not defeated (PHASE==2 would short-circuit to miss)
z.wr(EBUZ2_ROW_CUR, 0)     # body far from the player's row (won't overlap PLAYER_HIT_BOX_EBUZ)
lane = 0
row = lane + EBUZ2_ENTRY_TARGET_ROW
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 0, 1)
z.wr(EBUZ2_V1_STRUCT + lane * 2 + 1, PX // 8)
z.wr(PLAYERY, row * 8)
call_routine(z, sym["PDC_CHECK_EBUZ2"])
check("PDC_CHECK_EBUZ2 (top-level dispatch): body misses but volley1 hits - the new projectile "
      "checks are actually reachable from the real entry point, not just callable in isolation",
      z.a == 1)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
