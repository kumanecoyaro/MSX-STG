"""Stage1: "ステージ1スタート直後...急に始まるのでなく飛び込んでくる演出
...ShipStart1の下にShipStart2を重ねて...0,0からX128、Y64まで移動して
そこからX32,Y64な"の検証(2区間構成: leg1=(0,0)→(128,64)の真っ直ぐな
斜め移動、leg2=(128,64)→(32,64)のXのみの水平移動)。他のtools/
verify_*.pyと同じ「mini_z80asm.Assemblerで直接アセンブル+step_frameの
一回性検証スクリプト」の作法だが、この演出自体を検証するため他ファイル
のboot()と違いSHIP_ENTRY_ACTを即座に0へ落とさない生のブート手順を使う。
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


STAGE1_MISSION_GAMEOVER_FONT = sym["STAGE1_MISSION_GAMEOVER_FONT"]
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "title_screen"))
import title_bg_gen as _tbg  # noqa: E402 - rle_encode/rle_decode
with open(os.path.join(REPO_ROOT, "tools", "bgm_data", "stage1_mission_gameover_font.bin"), "rb") as f:
    _real_mission_gameover_font = f.read()
_real_mgf_compressed, _real_mgf_segments = _tbg.rle_encode(_real_mission_gameover_font)
assert _tbg.rle_decode(_real_mgf_compressed, _real_mgf_segments) == _real_mission_gameover_font


def fresh():
    # (round145、ROM予算確保でMISSION/GAMEOVERフォントをRAM事前コピー
    # 方式へ変更): INIT自身がこのRAMを読むため、実機同様に起動前から
    # 圧縮済みの実データが置かれている前提を再現する。
    z = Z80(bytearray(mem0))
    for i, b in enumerate(_real_mgf_compressed):
        z.wr(STAGE1_MISSION_GAMEOVER_FONT + i, b)
    return z


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
SHIP_ENTRY_MID_X = sym["SHIP_ENTRY_MID_X"]
PLAYER_RETREAT_TARGET_X = sym["PLAYER_RETREAT_TARGET_X"]
PLAYER_INITY = sym["PLAYER_INITY"]
PLAYER_SHIP_PAT = sym["PLAYER_SHIP_PAT"]
PLAYER_ACCENT_PAT = sym["PLAYER_ACCENT_PAT"]
PAT_SHIP = sym["PAT_SHIP"]
PAT_ACCENT_BARRIER = sym["PAT_ACCENT_BARRIER"]
PAT_SHIP_ENTRY_BODY = sym["PAT_SHIP_ENTRY_BODY"]
PAT_SHIP_ENTRY_ACCENT = sym["PAT_SHIP_ENTRY_ACCENT"]
SPRPAT = sym["SPRPAT"]

# leg1: (0,0) -> (SHIP_ENTRY_MID_X, PLAYER_INITY), X speed=SHIP_ENTRY_SPEED,
# Y speed=1 (half of X's, chosen so distance ratio == speed ratio and both
# axes arrive on the exact same frame - see the ASM's own comment).
LEG1_FRAMES = SHIP_ENTRY_MID_X // SHIP_ENTRY_SPEED
assert SHIP_ENTRY_MID_X % SHIP_ENTRY_SPEED == 0
assert PLAYER_INITY // 1 == LEG1_FRAMES, "leg1 X/Y no longer arrive simultaneously - ASM's clamp-free assumption would break"
# leg2: SHIP_ENTRY_MID_X -> PLAYER_RETREAT_TARGET_X, X only, speed=SHIP_ENTRY_SPEED
LEG2_DIST = SHIP_ENTRY_MID_X - PLAYER_RETREAT_TARGET_X
assert LEG2_DIST % SHIP_ENTRY_SPEED == 0
LEG2_FRAMES = LEG2_DIST // SHIP_ENTRY_SPEED
TOTAL_FRAMES = LEG1_FRAMES + LEG2_FRAMES

# ---- 1. immediately after boot: entry armed (leg1), ship at top-left,
#         entry patterns selected (not the normal PAT_SHIP/PAT_ACCENT) ----
z = fresh()
boot_with_entry(z)
check("boot: SHIP_ENTRY_ACT=1 (armed, leg1)", z.rd(SHIP_ENTRY_ACT) == 1)
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

# ---- 2b. (round145、"自機登場演出でスプライトがズレてる"): during the
#          entry effect, ShipStart1(accent, slot0)/ShipStart2(body, slot1)
#          must be drawn at the SAME X (overlaid, per the user's original
#          request), not the normal +8px accent offset used for the
#          barrier corner decoration. Attribute table: slot1(body)=
#          SPRATR+4, slot0(accent)=SPRATR+0, byte+1 of each 4-byte entry
#          is X. ----
SPRATR = 0x1B00  # VDP sprite attribute table base (this file's own DI blocks write here)
z = fresh()
boot_with_entry(z)
step_frame(z)  # one entry frame: PLAYERX has advanced off 0, still mid-entry
body_x_during = z.vram[SPRATR + 1 * 4 + 1]
accent_x_during = z.vram[SPRATR + 0 * 4 + 1]
check("during the entry effect, the accent (ShipStart1) is drawn at the SAME X as the body "
      "(ShipStart2) - overlaid, not offset +8px like the normal barrier decoration",
      accent_x_during == body_x_during)

z2 = fresh()
boot_with_entry(z2)
for _ in range(TOTAL_FRAMES + 2):
    step_frame(z2)
body_x_after = z2.vram[SPRATR + 1 * 4 + 1]
accent_x_after = z2.vram[SPRATR + 0 * 4 + 1]
check("after the entry effect completes, the normal +8px accent offset (barrier corner "
      "decoration) is restored", (accent_x_after - body_x_after) % 256 == 8)

#         SHIP_ENTRY_SPEED/frame, Y by 1/frame, both arriving at
#         (SHIP_ENTRY_MID_X, PLAYER_INITY) on the exact same frame ----
z = fresh()
boot_with_entry(z)
xs, ys, acts = [], [], []
for _ in range(TOTAL_FRAMES + 5):
    step_frame(z)
    xs.append(z.rd(PLAYERX))
    ys.append(z.rd(PLAYERY))
    acts.append(z.rd(SHIP_ENTRY_ACT))

expected_xs, expected_ys = [], []
x, y = 0, 0
for i in range(TOTAL_FRAMES + 5):
    if i < LEG1_FRAMES:
        x += SHIP_ENTRY_SPEED
        y += 1
    elif i == LEG1_FRAMES - 1 + 1:  # unreachable, kept for clarity of the boundary
        pass
    if LEG1_FRAMES <= i < TOTAL_FRAMES:
        x -= SHIP_ENTRY_SPEED
    expected_xs.append(x)
    expected_ys.append(y)

check(f"leg1: PLAYERX advances by SHIP_ENTRY_SPEED({SHIP_ENTRY_SPEED})/frame during the first "
      f"{LEG1_FRAMES} frames, reaching SHIP_ENTRY_MID_X({SHIP_ENTRY_MID_X}) exactly on frame "
      f"{LEG1_FRAMES}",
      xs[LEG1_FRAMES - 1] == SHIP_ENTRY_MID_X)
check(f"leg1: PLAYERY advances by 1/frame (half of X's speed) during the first {LEG1_FRAMES} "
      f"frames, reaching PLAYER_INITY({PLAYER_INITY}) exactly on frame {LEG1_FRAMES} - the SAME "
      "frame as X (straight diagonal, not a bent path)",
      ys[LEG1_FRAMES - 1] == PLAYER_INITY)
check("leg1: X and Y are tick-for-tick identical to an independent Python simulation over the "
      "whole run (both legs)",
      xs == expected_xs and ys == expected_ys)
check("SHIP_ENTRY_ACT transitions from 1 (leg1) to 2 (leg2) exactly on the frame both X and Y "
      "arrive at (SHIP_ENTRY_MID_X, PLAYER_INITY)",
      acts[LEG1_FRAMES - 2] == 1 and acts[LEG1_FRAMES - 1] == 2)

# ---- 3b. (2026-09-22follow-up、"128,64から後ろに下がるときは下向きの
#          キャラに 32,64に来たらノーマルに"): during leg2, the ship
#          switches to the normal gameplay "diving" pose (PAT_SHIP_DOWN/
#          PAT_ACCENT_DOWN, the same assets JOY_STICK=down normally uses),
#          drawn with the normal +8px accent offset (not the leg1
#          ShipStart1/2 overlay-without-offset convention) ----
PAT_SHIP_DOWN = sym["PAT_SHIP_DOWN"]
PAT_ACCENT_DOWN_BARRIER = sym["PAT_ACCENT_DOWN_BARRIER"]
z_leg2 = fresh()
boot_with_entry(z_leg2)
for _ in range(LEG1_FRAMES):
    step_frame(z_leg2)  # now exactly 1 frame into leg2
check("leg2: PLAYER_SHIP_PAT switches to PAT_SHIP_DOWN (downward-facing, reused from normal "
      "diving) instead of the leg1 entry body pattern",
      z_leg2.rd(PLAYER_SHIP_PAT) == PAT_SHIP_DOWN)
check("leg2: PLAYER_ACCENT_PAT switches to PAT_ACCENT_DOWN_BARRIER (BARRIER_HP_INIT>0 from game "
      "start, same ACCFR_GOT-style barrier check as normal gameplay) instead of the leg1 entry "
      "accent pattern",
      z_leg2.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_DOWN_BARRIER)
body_x_leg2 = z_leg2.vram[SPRATR + 1 * 4 + 1]
accent_x_leg2 = z_leg2.vram[SPRATR + 0 * 4 + 1]
check("leg2: the accent is drawn with the normal +8px offset from the body (PAT_ACCENT_DOWN is a "
      "normal-gameplay asset designed for that offset, unlike leg1's ShipStart1/2 overlay pair)",
      (accent_x_leg2 - body_x_leg2) % 256 == 8)

# ---- 4. leg2: X alone retreats from SHIP_ENTRY_MID_X down to
#         PLAYER_RETREAT_TARGET_X, Y stays fixed at PLAYER_INITY ----
check(f"leg2: PLAYERY stays fixed at PLAYER_INITY({PLAYER_INITY}) for all of leg2 "
      "(only X moves in leg2)",
      all(v == PLAYER_INITY for v in ys[LEG1_FRAMES:TOTAL_FRAMES]))
check(f"leg2: PLAYERX decreases by SHIP_ENTRY_SPEED({SHIP_ENTRY_SPEED})/frame during leg2's "
      f"{LEG2_FRAMES} frames, reaching PLAYER_RETREAT_TARGET_X({PLAYER_RETREAT_TARGET_X}) exactly "
      f"on frame {TOTAL_FRAMES}",
      xs[TOTAL_FRAMES - 1] == PLAYER_RETREAT_TARGET_X)
check("SHIP_ENTRY_ACT drops to 0 exactly on the frame leg2's X reaches PLAYER_RETREAT_TARGET_X "
      "(the whole sequence's true completion)",
      acts[TOTAL_FRAMES - 2] == 2 and acts[TOTAL_FRAMES - 1] == 0)

# ---- 5. on that exact completion frame, the ship's pattern switches back
#         to the normal look, and the sequence never re-arms ----
check("PLAYER_SHIP_PAT switches back to the normal PAT_SHIP (level flight, JOY_STICK centered) "
      "on the true completion frame",
      z.rd(PLAYER_SHIP_PAT) == PAT_SHIP)
check("PLAYER_ACCENT_PAT switches back to the normal barrier-equipped accent (BARRIER_HP_INIT>0 "
      "from game start, so ACCFR_GOT correctly picks PAT_ACCENT_BARRIER, not plain PAT_ACCENT) "
      "on the true completion frame",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_BARRIER)
check("SHIP_ENTRY_ACT stays 0 for the extra frames stepped past completion (one-shot, never re-arms)",
      all(v == 0 for v in acts[TOTAL_FRAMES:]))

# ---- 6. once the entry finishes, normal joystick control genuinely
#         takes over (not frozen, not still overridden) ----
z.sim_dir = 3  # right
prev_x = z.rd(PLAYERX)
step_frame(z)
check("after the entry sequence, real joystick input actually moves PLAYERX again "
      "(normal control fully handed back)",
      z.rd(PLAYERX) > prev_x)

# ---- 7. self-verification: a regression guard against the specific bug
#         class this design is fragile to (removed the overshoot clamp
#         to save ROM, relying on exact divisibility+simultaneous arrival
#         - if that invariant were ever violated by a future constant
#         change without restoring the clamp, PLAYERX/PLAYERY would wrap
#         via 8-bit under/overflow instead of stopping). Confirm the
#         values never leave the valid 0-255 range at any point (a wrap
#         would show up as a huge back-and-forth jump). ----
check("PLAYERX/PLAYERY never show a sign of 8-bit wraparound (a huge single-frame jump) "
      "anywhere across the full sequence - the clamp-free design's key safety invariant",
      all(abs(xs[i] - xs[i - 1]) <= SHIP_ENTRY_SPEED for i in range(1, len(xs))) and
      all(abs(ys[i] - ys[i - 1]) <= SHIP_ENTRY_SPEED for i in range(1, len(ys))))


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
