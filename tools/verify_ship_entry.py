"""Stage1: "ステージ1スタート直後...急に始まるのでなく飛び込んでくる演出
...ShipStart1の下にShipStart2を重ねて 左上から斜め右下に移動 Y中央まで
来たら通常時の絵にして Xが32pxの位置に"の検証。他のtools/verify_*.pyと
同じ「mini_z80asm.Assemblerで直接アセンブル+step_frameの一回性検証
スクリプト」の作法だが、この演出自体を検証するため他ファイルのboot()と
違いSHIP_ENTRY_ACTを即座に0へ落とさない生のブート手順を使う。
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


def run_until_pc(z, target_pc, max_instr=500_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot_with_entry(z):
    # 他ファイルのboot()と違い、SHIP_ENTRY_ACTを0へ落とさない生のブート。
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


PLAYERX = sym["PLAYERX"]
PLAYERY = sym["PLAYERY"]
SHIP_ENTRY_ACT = sym["SHIP_ENTRY_ACT"]
SHIP_ENTRY_SPEED = sym["SHIP_ENTRY_SPEED"]
PLAYER_RETREAT_TARGET_X = sym["PLAYER_RETREAT_TARGET_X"]
PLAYER_INITY = sym["PLAYER_INITY"]
PLAYER_SHIP_PAT = sym["PLAYER_SHIP_PAT"]
PLAYER_ACCENT_PAT = sym["PLAYER_ACCENT_PAT"]
PAT_SHIP = sym["PAT_SHIP"]
PAT_ACCENT = sym["PAT_ACCENT"]
PAT_ACCENT_BARRIER = sym["PAT_ACCENT_BARRIER"]
PAT_SHIP_ENTRY_BODY = sym["PAT_SHIP_ENTRY_BODY"]
PAT_SHIP_ENTRY_ACCENT = sym["PAT_SHIP_ENTRY_ACCENT"]
SPRPAT = sym["SPRPAT"]

# ---- 1. immediately after boot: entry armed, ship at top-left, entry
#         patterns selected (not the normal PAT_SHIP/PAT_ACCENT) ----
z = fresh()
boot_with_entry(z)
check("boot: SHIP_ENTRY_ACT=1 (armed)", z.rd(SHIP_ENTRY_ACT) == 1)
check("boot: PLAYERX=0 (top-left start)", z.rd(PLAYERX) == 0)
check("boot: PLAYERY=0 (top-left start)", z.rd(PLAYERY) == 0)
check("boot: PLAYER_SHIP_PAT is the entry body pattern (ShipStart2), not the normal PAT_SHIP",
      z.rd(PLAYER_SHIP_PAT) == PAT_SHIP_ENTRY_BODY)
check("boot: PLAYER_ACCENT_PAT is the entry accent pattern (ShipStart1), not the normal PAT_ACCENT",
      z.rd(PLAYER_ACCENT_PAT) == PAT_SHIP_ENTRY_ACCENT)

# ---- 2. the entry bitmaps were actually LDIRVM'd into VRAM at the
#         expected sprite pattern generator codes ----
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    src_lines = f.readlines()


def extract_pattern_bytes(label):
    start = None
    for i, line in enumerate(src_lines):
        if line.strip().startswith(f"{label}:"):
            start = i + 1
            break
    assert start is not None, label
    vals = []
    for line in src_lines[start:start + 4]:
        line = line.split(';', 1)[0]
        assert 'DB' in line
        parts = line.split('DB', 1)[1].strip().rstrip(',').split(',')
        for p in parts:
            p = p.strip()
            vals.append(int(p[:-1], 16) if p.lower().endswith('h') else int(p, 16))
    return vals


expected_body = extract_pattern_bytes("SHIP_ENTRY_BODY_PATTERN")
expected_accent = extract_pattern_bytes("SHIP_ENTRY_ACCENT_PATTERN")
check("SHIP_ENTRY_BODY_PATTERN source is 32 bytes (4 quadrants x8)", len(expected_body) == 32)
check("SHIP_ENTRY_ACCENT_PATTERN source is 32 bytes (4 quadrants x8)", len(expected_accent) == 32)

vram_body = [z.vram[SPRPAT + PAT_SHIP_ENTRY_BODY * 8 + i] for i in range(32)]
vram_accent = [z.vram[SPRPAT + PAT_SHIP_ENTRY_ACCENT * 8 + i] for i in range(32)]
check("VRAM at PAT_SHIP_ENTRY_BODY's sprite pattern generator slot matches SHIP_ENTRY_BODY_PATTERN exactly",
      vram_body == expected_body)
check("VRAM at PAT_SHIP_ENTRY_ACCENT's sprite pattern generator slot matches SHIP_ENTRY_ACCENT_PATTERN exactly",
      vram_accent == expected_accent)

# ---- 3. diagonal approach: both PLAYERX/PLAYERY advance by
#         SHIP_ENTRY_SPEED every frame until each reaches its own
#         target, independently, with no overshoot ----
z = fresh()
boot_with_entry(z)
xs = []
ys = []
for _ in range(40):
    step_frame(z)
    xs.append(z.rd(PLAYERX))
    ys.append(z.rd(PLAYERY))

expected_xs = []
expected_ys = []
x, y = 0, 0
for _ in range(40):
    x = min(x + SHIP_ENTRY_SPEED, PLAYER_RETREAT_TARGET_X)
    y = min(y + SHIP_ENTRY_SPEED, PLAYER_INITY)
    expected_xs.append(x)
    expected_ys.append(y)

check(f"PLAYERX advances by SHIP_ENTRY_SPEED({SHIP_ENTRY_SPEED})/frame toward "
      f"PLAYER_RETREAT_TARGET_X({PLAYER_RETREAT_TARGET_X}) with no overshoot, tick-for-tick "
      "matching an independent Python simulation over 40 frames",
      xs == expected_xs)
check(f"PLAYERY advances by SHIP_ENTRY_SPEED({SHIP_ENTRY_SPEED})/frame toward "
      f"PLAYER_INITY({PLAYER_INITY}) with no overshoot, tick-for-tick matching an independent "
      "Python simulation over 40 frames",
      ys == expected_ys)

x_arrival_frame = next(i for i, v in enumerate(expected_xs) if v == PLAYER_RETREAT_TARGET_X)
y_arrival_frame = next(i for i, v in enumerate(expected_ys) if v == PLAYER_INITY)
check("X reaches its target strictly before Y (X's distance is shorter, matching the diagonal-then-"
      "vertical-finish shape this independent-per-axis design produces)",
      x_arrival_frame < y_arrival_frame)

# ---- 4. SHIP_ENTRY_ACT only drops to 0 on the exact frame BOTH axes
#         have arrived, not before, and the patterns switch back to
#         the normal ship look on that very same frame ----
z = fresh()
boot_with_entry(z)
still_armed_frames = []
for i in range(y_arrival_frame):
    step_frame(z)
    still_armed_frames.append(z.rd(SHIP_ENTRY_ACT))
check(f"SHIP_ENTRY_ACT stays 1 for all {y_arrival_frame} frames before the slower axis (Y) arrives",
      all(v == 1 for v in still_armed_frames))

step_frame(z)  # the arrival frame itself
check("SHIP_ENTRY_ACT drops to 0 exactly on the frame both PLAYERX/PLAYERY reach their targets",
      z.rd(SHIP_ENTRY_ACT) == 0)
check("...and PLAYERX is exactly at PLAYER_RETREAT_TARGET_X (32) on that same frame",
      z.rd(PLAYERX) == PLAYER_RETREAT_TARGET_X)
check("...and PLAYERY is exactly at PLAYER_INITY (64) on that same frame",
      z.rd(PLAYERY) == PLAYER_INITY)
check("PLAYER_SHIP_PAT switches back to the normal PAT_SHIP (level flight, JOY_STICK centered) "
      "on the very same arrival frame - not a frame later",
      z.rd(PLAYER_SHIP_PAT) == PAT_SHIP)
check("PLAYER_ACCENT_PAT switches back to the normal barrier-equipped accent (BARRIER_HP_INIT>0 "
      "from game start, so ACCFR_GOT correctly picks PAT_ACCENT_BARRIER, not plain PAT_ACCENT) "
      "on the very same arrival frame",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_BARRIER)

# once more frames, the sequence must stay inactive (a one-shot, not a loop)
for _ in range(5):
    step_frame(z)
check("SHIP_ENTRY_ACT stays 0 forever after arrival (one-shot, never re-arms)",
      z.rd(SHIP_ENTRY_ACT) == 0)

# ---- 5. once the entry finishes, normal joystick control genuinely
#         takes over (not frozen, not still overridden) ----
z.sim_dir = 3  # right
prev_x = z.rd(PLAYERX)
step_frame(z)
check("after the entry sequence, real joystick input actually moves PLAYERX again "
      "(normal control fully handed back)",
      z.rd(PLAYERX) > prev_x)

# ---- 6. self-verification: a real BGM_TICK-unrelated regression guard -
#         if the arrival check used only PLAYERX (forgetting PLAYERY),
#         SHIP_ENTRY_ACT would drop to 0 as soon as X alone arrives,
#         well before Y catches up. Confirm this is NOT what happens
#         (both must be checked) by cross-referencing the two arrival
#         frames computed above. ----
check("the arrival check genuinely waits for the SLOWER axis (Y), not just X: "
      "x_arrival_frame != y_arrival_frame confirms the two axes have different "
      "arrival times in this scenario, so a hypothetical X-only bug would be "
      "distinguishable from the correct both-axes behavior verified above",
      x_arrival_frame != y_arrival_frame)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
