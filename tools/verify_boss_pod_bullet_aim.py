"""Stage1: ボスの周回ポッド弾(POD_BULLET0/1)を自機狙い弾に変更する検証
(2026-09-13、"ステージ1ボス ボスの弾は画面のX座標が半分より右に自機が
いる場合自機狙い弾になるように変更 半分以下なら従来通りまっすぐ打つ
だけ 近寄ったら自機狙いになるって事")。

従来はPOD_BULLETnがPOD_BULLET_SPEED(12px/frame)で左へ直進するだけ
(Yはpodの発射時点のY固定)だったが、発射の瞬間(POD_FIRE_DO_PAIR)に
PLAYERXが画面の半分(POD_BULLET_HOMING_THRESHOLD_X=128)より右かどうかを
判定し、右であればその瞬間のPLAYERYへ向かう一定の縦方向速度(DY、符号
付き)を持たせる(以後は毎フレームこのDYをそのままYへ加算するだけの
予測照準方式、Stage2のBOSS_BROKEN_BEAM_TABLEと同じ「発射時に一度だけ
決める」idiom)。半分以下なら従来通りDY=0(挙動は完全不変)。

tools/verify_boss_dfl_clear.py と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine の一回性検証スクリプト」の作法に倣う。
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


PLAYERX = sym["PLAYERX"]; PLAYERY = sym["PLAYERY"]
POD_BULLET_CALC_DY = sym["POD_BULLET_CALC_DY"]
POD_BULLET_MOVE = sym["POD_BULLET_MOVE"]
POD_FIRE_DO_PAIR = sym["POD_FIRE_DO_PAIR"]
POD_FIRE_PAIR = sym["POD_FIRE_PAIR"]
POD_HP = sym["POD_HP"]
POD_BULLET0_ACT = sym["POD_BULLET0_ACT"]
POD_BULLET0_X = sym["POD_BULLET0_X"]; POD_BULLET0_Y = sym["POD_BULLET0_Y"]
POD_BULLET0_DY = sym["POD_BULLET0_DY"]
POD_BULLET1_ACT = sym["POD_BULLET1_ACT"]
POD_BULLET1_X = sym["POD_BULLET1_X"]; POD_BULLET1_Y = sym["POD_BULLET1_Y"]
POD_BULLET1_DY = sym["POD_BULLET1_DY"]
POD_BULLET_SPEED = sym["POD_BULLET_SPEED"]
POD_BULLET_HOMING_THRESHOLD_X = sym["POD_BULLET_HOMING_THRESHOLD_X"]
POD_BULLET_HOMING_DY = sym["POD_BULLET_HOMING_DY"]
BOSS_ORBIT_ANGLE = sym["BOSS_ORBIT_ANGLE"]
BOSS_STATE = sym["BOSS_STATE"]

check("POD_BULLET_HOMING_THRESHOLD_X is 128 (screen width 256 / 2)",
      POD_BULLET_HOMING_THRESHOLD_X == 128)


def sdy(raw):
    """raw hw byte -> signed interpretation, for readable assertions."""
    return raw - 256 if raw >= 128 else raw


# ---------- (1) POD_BULLET_CALC_DY: direct unit tests ----------
def calc_dy(bullet_y, player_x, player_y):
    z = fresh()
    z.wr(PLAYERX, player_x)
    z.wr(PLAYERY, player_y)
    z.a = bullet_y
    call_routine(z, POD_BULLET_CALC_DY)
    return sdy(z.a)


check("PLAYERX exactly at the left half (127): straight, DY=0",
      calc_dy(bullet_y=100, player_x=127, player_y=50) == 0)
check("PLAYERX exactly at the threshold (128): homing kicks in",
      calc_dy(bullet_y=100, player_x=128, player_y=50) == -POD_BULLET_HOMING_DY)
check("PLAYERX well left of threshold: straight, DY=0 regardless of PLAYERY",
      calc_dy(bullet_y=100, player_x=10, player_y=180) == 0)
check("PLAYERX well right of threshold, PLAYERY below bullet Y: drift down (+DY)",
      calc_dy(bullet_y=50, player_x=200, player_y=150) == POD_BULLET_HOMING_DY)
check("PLAYERX well right of threshold, PLAYERY above bullet Y: drift up (-DY)",
      calc_dy(bullet_y=150, player_x=200, player_y=50) == -POD_BULLET_HOMING_DY)
check("PLAYERX right of threshold, PLAYERY exactly level with bullet Y: DY=0 (already aligned)",
      calc_dy(bullet_y=100, player_x=200, player_y=100) == 0)


# ---------- (2) POD_BULLET_MOVE: applies DY every frame, alongside the ----------
# ---------- pre-existing X decrement, for both bullet slots            ----------
z = fresh()
z.wr(POD_BULLET0_ACT, 1)
z.wr(POD_BULLET0_X, 100); z.wr(POD_BULLET0_Y, 80)
z.wr(POD_BULLET0_DY, POD_BULLET_HOMING_DY & 0xFF)
z.wr(POD_BULLET1_ACT, 1)
z.wr(POD_BULLET1_X, 100); z.wr(POD_BULLET1_Y, 80)
z.wr(POD_BULLET1_DY, (-POD_BULLET_HOMING_DY) & 0xFF)
call_routine(z, POD_BULLET_MOVE)
check(f"POD_BULLET_MOVE: bullet0's X still decrements by POD_BULLET_SPEED({POD_BULLET_SPEED}) "
      "exactly as before",
      z.rd(POD_BULLET0_X) == 100 - POD_BULLET_SPEED)
check(f"...and its Y advances by its own stored DY (+{POD_BULLET_HOMING_DY}, drifting down)",
      z.rd(POD_BULLET0_Y) == 80 + POD_BULLET_HOMING_DY)
check("POD_BULLET_MOVE: bullet1's X also decrements normally",
      z.rd(POD_BULLET1_X) == 100 - POD_BULLET_SPEED)
check(f"...and its Y advances by its own stored DY (-{POD_BULLET_HOMING_DY}, drifting up)",
      z.rd(POD_BULLET1_Y) == 80 - POD_BULLET_HOMING_DY)

# DY=0 (the straight-shot case) must leave Y completely untouched - byte-
# identical to the pre-existing behavior.
z2 = fresh()
z2.wr(POD_BULLET0_ACT, 1)
z2.wr(POD_BULLET0_X, 100); z2.wr(POD_BULLET0_Y, 80)
z2.wr(POD_BULLET0_DY, 0)
call_routine(z2, POD_BULLET_MOVE)
check("POD_BULLET_MOVE with DY=0: Y stays completely unchanged (straight-shot compat)",
      z2.rd(POD_BULLET0_Y) == 80)


# ---------- (3) POD_FIRE_DO_PAIR: the real firing path, end to end ----------
def fire_pair(player_x, player_y, pair=0):
    z = fresh()
    z.wr(BOSS_ORBIT_ANGLE, 0)
    z.wr(POD_FIRE_PAIR, pair)
    z.wr(POD_HP + pair, 1)
    z.wr(POD_HP + pair + 1, 1)
    z.wr(PLAYERX, player_x)
    z.wr(PLAYERY, player_y)
    call_routine(z, POD_FIRE_DO_PAIR)
    return z


z = fire_pair(player_x=10, player_y=150)
check("real firing path: PLAYERX on the left half -> both bullets fire with DY=0 "
      "(unchanged straight-shot behavior)",
      z.rd(POD_BULLET0_ACT) == 1 and sdy(z.rd(POD_BULLET0_DY)) == 0 and
      z.rd(POD_BULLET1_ACT) == 1 and sdy(z.rd(POD_BULLET1_DY)) == 0)

z = fire_pair(player_x=200, player_y=250 % 256, pair=0)
# use whatever the real spawn Y turned out to be, re-derived independently
real_bullet0_y = z.rd(POD_BULLET0_Y)
real_bullet1_y = z.rd(POD_BULLET1_Y)
expected_dy0 = calc_dy(real_bullet0_y, 200, 250 % 256)
expected_dy1 = calc_dy(real_bullet1_y, 200, 250 % 256)
check("real firing path: PLAYERX on the right half -> bullet0 gets exactly the DY "
      "POD_BULLET_CALC_DY independently computes for its own real spawn Y",
      sdy(z.rd(POD_BULLET0_DY)) == expected_dy0)
check("...and bullet1 too (its own, independently different, spawn Y)",
      sdy(z.rd(POD_BULLET1_DY)) == expected_dy1)

# a pod pair where only ONE of the 2 pods is alive - the fired bullet
# still gets aimed correctly (loop-independence check).
z = fresh()
z.wr(BOSS_ORBIT_ANGLE, 0)
z.wr(POD_FIRE_PAIR, 2)
z.wr(POD_HP + 2, 1)   # pod index2 alive
z.wr(POD_HP + 3, 0)   # pod index3 dead
z.wr(PLAYERX, 200)
z.wr(PLAYERY, 30)
call_routine(z, POD_FIRE_DO_PAIR)
check("only pod0 of the pair alive: bullet0 fires and gets aimed (nonzero DY, player on the right)",
      z.rd(POD_BULLET0_ACT) == 1 and sdy(z.rd(POD_BULLET0_DY)) != 0)
check("...bullet1 (dead pod) never fires at all", z.rd(POD_BULLET1_ACT) == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
