"""Stage1: 自機バリア装備の検証(耐久値5・初期装備・アクセント差し替え・
0で通常アクセントに復帰)。まだダメージ/衝突は未実装(ユーザー指示により
意図的にスコープ外)なので、ここでは「表示の差し替え」だけを検証する。
tools/verify_enemy_bullets.py と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine/run_until_pcの一回性検証スクリプト」の作法に倣う。
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

# (2026-09-06、MISSION 1導入演出): INIT内のMISSION_DELAY_3SEC(実機では
# 約3秒のZ80クロック直接カウントのビジーウェイト、LD D,10で約130万
# 命令)がこのファイルのboot()呼び出し全てに乗ってしまい、既存の
# run_until_pcの命令数上限を軽く超えてしまう。実ROMは変更せず、この
# テストプロセス内でのみLD D,10の即値(MISSION_DELAY_3SEC+1)を1へ
# 縮小(約13万命令、既存の上限内に収まる)。
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


BARRIER_HP = sym["BARRIER_HP"]; BARRIER_HP_INIT = sym["BARRIER_HP_INIT"]
PAT_ACCENT = sym["PAT_ACCENT"]; PAT_ACCENT_DOWN = sym["PAT_ACCENT_DOWN"]
PAT_ACCENT_BARRIER = sym["PAT_ACCENT_BARRIER"]; PAT_ACCENT_DOWN_BARRIER = sym["PAT_ACCENT_DOWN_BARRIER"]
PLAYER_ACCENT_PAT = sym["PLAYER_ACCENT_PAT"]; JOY_STICK = sym["JOY_STICK"]
SPRPAT = sym["SPRPAT"]

# barrier glyph = bottom-right 8x8 quadrant of the uploaded Acsent_16x16.json
# (rows8-15, cols8-15), independently re-derived here from the raw bits
# (not just copy-pasted from the ASM) so this test actually catches a
# transcription mistake in the DB bytes.
import json
UPLOAD = "/root/.claude/uploads/d26705dd-4692-5b41-b8ac-14b567625ef8/804d2569-Acsent_16x16.json"
with open(UPLOAD, encoding="utf-8") as f:
    barrier_json = json.load(f)
bits = barrier_json["bits"]
expected_br = []
for row in range(8, 16):
    byte = 0
    for col in range(8, 16):
        byte = (byte << 1) | bits[row][col]
    expected_br.append(byte)


# ---------- (1) BARRIER_HP is equipped (=5) from game start, no pickup needed ----------
z = fresh(); boot(z)
check("BARRIER_HP is initialized to BARRIER_HP_INIT(5) at boot, equipped from the start",
      z.rd(BARRIER_HP) == BARRIER_HP_INIT == 5)


# ---------- (2) ACCENT_MID_BARRIER_PATTERN / ACCENT_DOWN_BARRIER_PATTERN VRAM content ----------
def quad_bytes(code, quad):
    # quad: 0=TL,1=BL,2=TR,3=BR (this codebase's own DB ordering).
    # VRAM is a separate address space from main RAM - read via z.vram[],
    # not z.rd() (which reads Z80 main memory).
    base = SPRPAT + code * 8 + quad * 8
    return [z.vram[base + i] for i in range(8)]


check("ACCENT_MID_BARRIER's TL quadrant is blank (same as ACCENT_MID_PATTERN)",
      quad_bytes(PAT_ACCENT_BARRIER, 0) == [0] * 8)
check("ACCENT_MID_BARRIER's BL quadrant is untouched - matches the plain ACCENT_MID_PATTERN's own BL",
      quad_bytes(PAT_ACCENT_BARRIER, 1) == quad_bytes(PAT_ACCENT, 1) == [0x30, 0x08, 0, 0, 0, 0, 0, 0])
check("ACCENT_MID_BARRIER's TR quadrant is blank",
      quad_bytes(PAT_ACCENT_BARRIER, 2) == [0] * 8)
check("ACCENT_MID_BARRIER's BR quadrant is the barrier glyph (bottom-right 8x8 of the uploaded art)",
      quad_bytes(PAT_ACCENT_BARRIER, 3) == expected_br)

check("ACCENT_DOWN_BARRIER's BL quadrant is untouched - matches the plain ACCENT_DOWN_PATTERN's own BL",
      quad_bytes(PAT_ACCENT_DOWN_BARRIER, 1) == quad_bytes(PAT_ACCENT_DOWN, 1) == [0x70, 0x38, 0, 0, 0, 0, 0, 0])
check("ACCENT_DOWN_BARRIER's TL/TR quadrants are blank",
      quad_bytes(PAT_ACCENT_DOWN_BARRIER, 0) == [0] * 8 and quad_bytes(PAT_ACCENT_DOWN_BARRIER, 2) == [0] * 8)
check("ACCENT_DOWN_BARRIER's BR quadrant is the same barrier glyph as the MID variant",
      quad_bytes(PAT_ACCENT_DOWN_BARRIER, 3) == expected_br)


# ---------- (3) live selection: equipped (BARRIER_HP>0) shows the barrier variant ----------
# JOY_STICK is overwritten every frame by "LD A,1:CALL GTSTCK:LD (JOY_STICK),A"
# (GTSTCK simulated via z.sim_dir in z80emu.py, default 0=centered when unset) -
# writing JOY_STICK directly before step_frame() would just get clobbered by
# that BIOS-read simulation, so drive it via sim_dir instead.
z = fresh(); boot(z)
z.sim_dir = 0   # not diving
step_frame(z)
check("equipped (BARRIER_HP=5 from boot), level flight: PLAYER_ACCENT_PAT = PAT_ACCENT_BARRIER",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_BARRIER)

z.sim_dir = 4   # down-right (one of the 3 "diving" directions - see GTSTCK comment)
step_frame(z)
check("equipped, diving (dir=4/down-right): PLAYER_ACCENT_PAT = PAT_ACCENT_DOWN_BARRIER",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_DOWN_BARRIER)


# ---------- (4) depleted (BARRIER_HP=0) reverts to the plain accent ----------
z = fresh(); boot(z)
z.wr(BARRIER_HP, 0)
z.sim_dir = 0
step_frame(z)
check("depleted (BARRIER_HP=0), level flight: PLAYER_ACCENT_PAT reverts to PAT_ACCENT",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT)

z.sim_dir = 4
step_frame(z)
check("depleted, diving: PLAYER_ACCENT_PAT reverts to PAT_ACCENT_DOWN",
      z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_DOWN)

# also check the other 2 "diving" directions (5=down,6=down-left) still work equipped
z = fresh(); boot(z)
for dv in (5, 6):
    z.sim_dir = dv
    step_frame(z)
    check(f"equipped, diving (dir={dv}): PLAYER_ACCENT_PAT = PAT_ACCENT_DOWN_BARRIER",
          z.rd(PLAYER_ACCENT_PAT) == PAT_ACCENT_DOWN_BARRIER)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
