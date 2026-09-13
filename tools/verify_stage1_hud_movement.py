"""Stage1: 自機移動範囲の拡張("自機の移動制限範囲を8px下げて 今は8px
だと思うんで16pxに")+スコア行の黒背景化("スコアの行をブラックで埋め
て")+Tick表示の完全削除("Tick表示削除")を検証(2026-09-13)。

tools/verify_barrier.py と同じ「mini_z80asm.Assemblerで直接アセンブル
+boot()/step_frame()、GTSTCKはz.sim_dirで模擬」の作法に倣う。
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

# same INIT-shrink test-only patch as verify_barrier.py (real ROM unaffected)
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

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


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


PLAYERY = sym["PLAYERY"]
PLAYER_MINY = sym["PLAYER_MINY"]
NAME_TABLE_BASE = 0x1800
MISSION_FONT_BASE = sym["MISSION_FONT_BASE"]
DIGIT_BASE = sym["DIGIT_BASE"]
BLACK_CODE = MISSION_FONT_BASE + 5

# ---------- (1) PLAYER_MINY itself is 16 now ----------
check("PLAYER_MINY EQU is 16 (was 8)", PLAYER_MINY == 16)

# ---------- (2) the ship actually clamps at Y=16 when driven all the way up ----------
z = fresh(); boot(z)
z.sim_dir = 1   # up
for _ in range(400):
    step_frame(z)
check(f"ship clamps at PLAYERY=PLAYER_MINY({PLAYER_MINY}) when driven up for a long time",
      z.rd(PLAYERY) == PLAYER_MINY)

z.sim_dir = 1
step_frame(z)
check("...and one more frame of 'up' doesn't push it any further",
      z.rd(PLAYERY) == PLAYER_MINY)

# ---------- (3) GAME_TICK_DISPLAY is gone entirely ----------
check("GAME_TICK_DISPLAY symbol no longer exists (routine fully removed)",
      "GAME_TICK_DISPLAY" not in sym)

# ---------- (4) row0 (the score display's own row) reads solid black ----------
# right after boot, everywhere except the 8 score-digit cells (cols0-7).
z = fresh(); boot(z)
row0 = [z.vram[NAME_TABLE_BASE + col] for col in range(32)]
check("row0 cols0-7 hold real score-digit codes (DIGIT_BASE.. range), not the black filler",
      all(DIGIT_BASE <= row0[c] <= DIGIT_BASE + 9 for c in range(8)))
check("row0 cols8-28 (the empty gap between score and the old tick counter) are the black filler code",
      all(row0[c] == BLACK_CODE for c in range(8, 29)))
check("row0 cols29-31 (where GAME_TICK_DISPLAY used to draw 3 digits) are ALSO the black "
      "filler code now - confirms the tick counter draws nothing there anymore",
      all(row0[c] == BLACK_CODE for c in range(29, 32)))

# ---------- (5) that black row0 background survives many real frames of ----------
# play (score digits get redrawn each score change, but the untouched gap must
# never get clobbered back to BLANKCODE by anything else).
z = fresh(); boot(z)
for _ in range(200):
    step_frame(z)
row0_later = [z.vram[NAME_TABLE_BASE + col] for col in range(32)]
check("row0's black background (cols8-31) still holds after 200 real frames of play",
      all(row0_later[c] == BLACK_CODE for c in range(8, 32)))


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
