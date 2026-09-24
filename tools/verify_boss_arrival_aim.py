"""Stage1: (2026-09-23) "Ebuzのスコアを500点から2000点に"・"ボス到達時に
5万点を下回った場合どこに居てもポッド弾は自機狙いになるように チェックは
到達時にのみ行え メインで回すな" の検証。
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



SCORE = sym["SCORE"]
FLAG = sym["POD_AIM_NORMAL"]   # 0=6万4千点未満(旧5万点)で常時自機狙い


def set_score(z, real):
    v = real // 100
    z.wr(SCORE, v & 0xFF); z.wr(SCORE + 1, (v >> 8) & 0xFF); z.wr(SCORE + 2, (v >> 16) & 0xFF)


def rd_score(z):
    return (z.rd(SCORE) | (z.rd(SCORE + 1) << 8) | (z.rd(SCORE + 2) << 16)) * 100


# ---- Ebuz撃破スコア ----
z = fresh(); set_score(z, 0)
call_routine(z, sym["ADD_SCORE_2000"])
check("ADD_SCORE_2000 adds exactly 2000 points", rd_score(z) == 2000)
check("Ebuz kill path calls ADD_SCORE_2000 (and no ADD_SCORE_500 remains)",
      "CALL ADD_SCORE_2000" in text and "ADD_SCORE_500" not in text)

# ---- ボス到達時判定(BOSS_SPAWN内、到達時の1回だけ) ----
import re
bs = text.index("BOSS_SPAWN:\n")
seg = text[bs:text.index("BS_AIM_STORE:", bs) + 60]
check("POD_AIM_NORMAL is written only inside BOSS_SPAWN (not in the main loop)",
      text.count("(POD_AIM_NORMAL),A") == 1 and "(POD_AIM_NORMAL),A" in seg)
# BOSS_SPAWNの判定部分だけを実行する(先頭〜BS_AIM_STOREの格納直後まで)
start = sym["BOSS_SPAWN"]
store = sym["BS_AIM_STORE"]
# (2026-09-24) 境目は6万4千点(旧5万点)
for real, force in [(0, True), (50000, True), (63900, True), (64000, False), (64100, False),
                    (6553600, False), (6553600 + 100, False)]:
    z = fresh(); set_score(z, real); z.wr(FLAG, 0x55)
    # BOSS_CLEAR_DYNAMIC_ENEMIESのCALL(3byte)を飛ばして判定コードから実行
    z.sp = 0xF000; z.pc = start + 3
    run_until_pc(z, store); z.step()   # LD (POD_AIM_NORMAL),A を実行
    check(f"arrival check: score {real} -> forced aim={force}", (z.rd(FLAG) == 0) == force)

# ---- ポッド弾の照準 ----
import math
def calc_dir(normal, playerx, playery, podx, pody):
    z = fresh(); z.wr(FLAG, normal)
    z.wr(sym["PLAYERX"], playerx); z.wr(sym["PLAYERY"], playery)
    z.d = podx; z.e = pody
    call_routine(z, sym["POD_BULLET_CALC_DIR"])
    c = z.c - 256 if z.c >= 128 else z.c
    return z.b, c

straight = (sym["POD_BULLET_SPEED"], 0)
check("normal, player on left half: straight shot (unchanged)",
      calc_dir(0xFF, 40, 150, 200, 60) == straight)

worst = 0.0
bad = []
for px in range(0, 256, 8):
    for py in range(8, 184, 16):
        for podx, pody in [(176, 40), (200, 80), (232, 120), (216, 160)]:
            if px >= podx:
                continue
            b, c = calc_dir(0, px, py, podx, pody)
            want = math.atan2(py - pody, px - podx)
            got = math.atan2(c, -b)
            err = abs((math.degrees(want - got) + 180) % 360 - 180)
            worst = max(worst, err)
            if err > 12:
                bad.append((px, py, podx, pody, b, c, round(err, 1)))
check(f"forced aim: from ANY player X (incl. far left, dx<-128) the bullet heads at the "
      f"player within 12 deg (worst {worst:.1f} deg)", not bad)
if bad:
    print("  examples:", bad[:5])
b, c = calc_dir(0, 180, 150, 150, 60)
check("forced aim, player right of pod (dx>=0): straight fallback (bullets only fly left)",
      (b, c) == straight)
b, c = calc_dir(0xFF, 160, 150, 220, 60)
check("normal, player on right half: still aimed (unchanged gating)", (b, c) != straight and c > 0)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
