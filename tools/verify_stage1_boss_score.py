"""Stage1: ボス撃破時の得点付与を検証(2026-09-13、"ステージ1ボスは
10000点")。

POD_HIT_DESTROY(最後のポッドが破壊された瞬間、BOSS_EXPL_STARTEDの
一度きりガードと共にボスの死亡シーケンス[BOSS_EXPL_BUILD_LUT]を起動
する箇所)へ、SCORE(実得点/100の24bitカウンタ)へ100(=10000実点)を
一度だけ加算する処理を追加した。tools/verify_boss_pod_bullet_aim.py と
同じ「mini_z80asm.Assemblerで直接アセンブル+call_routineの一回性
検証スクリプト」の作法に倣う。
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


POD_HIT = sym["POD_HIT"]
POD_HP = sym["POD_HP"]
BOSS_EXPL_STARTED = sym["BOSS_EXPL_STARTED"]
SCORE = sym["SCORE"]


def score_value(z):
    return z.rd(SCORE) | (z.rd(SCORE + 1) << 8) | (z.rd(SCORE + 2) << 16)


def hit_pod(z, index):
    z.b = index
    call_routine(z, POD_HIT)


# ---------- (1) destroying the last pod awards exactly 10000 points, once ----------
z = fresh()
for i in range(8):
    z.wr(POD_HP + i, 1)
before = score_value(z)
for i in range(7):
    hit_pod(z, i)
check("after killing 7 of 8 pods: BOSS_EXPL_STARTED not yet armed",
      z.rd(BOSS_EXPL_STARTED) == 0)
check("...and no score awarded yet", score_value(z) == before)

hit_pod(z, 7)   # the last pod - (2026-09-23) now starts the boss laser (LZ_BOSS_FIRE)
check("BOSS_EXPL_STARTED latched after the last pod dies", z.rd(BOSS_EXPL_STARTED) == 1)
check("(2026-09-23 boss laser) last pod starts the boss-laser countdown (LZ_CD_T), no score yet",
      z.rd(sym["LZ_CD_T"]) == sym["LZ_CD_FRAMES"] and score_value(z) == before)
call_routine(z, sym["START_BOSS_DEATH"])   # 干渉に勝った時(LZ_WIN)の撃破開始
check("SCORE increases by exactly 100 units (10000 real points) when the boss death starts",
      score_value(z) - before == 100)

# ---------- (2) one-shot: further pod hits (there are none left, but the ----------
# ---------- BOSS_EXPL_STARTED guard itself) never awards the boss score twice ----------
before2 = score_value(z)
z.wr(BOSS_EXPL_STARTED, 1)   # already latched from above; re-assert defensively
z.wr(POD_HP, 1)              # pretend a pod is somehow still alive/hittable
hit_pod(z, 0)
check("BOSS_EXPL_STARTED guard: no further boss-score award once already latched",
      score_value(z) - before2 == 0)

# ---------- (3) a non-lethal pod hit (pod survives) never awards score ----------
z = fresh()
z.wr(POD_HP + 3, 5)
before3 = score_value(z)
hit_pod(z, 3)
check("non-lethal pod hit (HP 5->4): pod survives", z.rd(POD_HP + 3) == 4)
check("...and awards no score at all", score_value(z) - before3 == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
