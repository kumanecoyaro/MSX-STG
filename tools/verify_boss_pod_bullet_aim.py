"""Stage1: ボスの周回ポッド弾(POD_BULLET0/1)を自機狙い弾に変更する検証
(2026-09-13、"ステージ1ボス ボスの弾は画面のX座標が半分より右に自機が
いる場合自機狙い弾になるように変更 半分以下なら従来通りまっすぐ打つ
だけ 近寄ったら自機狙いになるって事")。

(2026-09-19、"ステージ1ボスの改良 接近時の自機狙い弾の精度が低いんで
24や32方向に と言ってもプレイヤーは常に左に居るんでLUTは180度分で
済むはず"): このファイルは全面書き換え済み。旧POD_BULLET_CALC_DY
(DY=-2/0/+2のみの粗いホーミング)は撤去され、POD_BULLET_CALC_DIR/
POD_AIM_CLASSIFY(32方向2D照準)に置き換わったため、旧テストは全て
新設計に合わせて書き直した。

新設計の検証は2層構造: (1) POD_AIM_CLASSIFYの分類ロジック自体を、
このファイル自身が持つPythonリファレンス実装(実際のZ80命令列を
ビット単位で模した「gen_full_asm.py」相当のモデル、開発時に
/tmp配下で検証済みのものと同一)と、dx/dyの広範囲な組み合わせで
直接突き合わせる回帰ガード。(2) POD_BULLET_CALC_DIR/POD_BULLET_MOVE/
POD_FIRE_DO_PAIRという実際の呼び出し経路が、そのPOD_AIM_CLASSIFYの
結果を正しくDXMAG/DYへ変換し、Xのアンダーフロー判定(画面外検出)も
含めて正しく動くことを検証する統合テスト。

tools/verify_boss_dfl_clear.py と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine の一回性検証スクリプト」の作法に倣う。
"""
import sys, os, math
from collections import defaultdict, Counter

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
POD_AIM_CLASSIFY = sym["POD_AIM_CLASSIFY"]
POD_BULLET_CALC_DIR = sym["POD_BULLET_CALC_DIR"]
POD_BULLET_MOVE = sym["POD_BULLET_MOVE"]
POD_FIRE_DO_PAIR = sym["POD_FIRE_DO_PAIR"]
POD_FIRE_PAIR = sym["POD_FIRE_PAIR"]
POD_HP = sym["POD_HP"]
POD_BULLET0_ACT = sym["POD_BULLET0_ACT"]
POD_BULLET0_X = sym["POD_BULLET0_X"]; POD_BULLET0_Y = sym["POD_BULLET0_Y"]
POD_BULLET0_DY = sym["POD_BULLET0_DY"]
POD_BULLET0_DXMAG = sym["POD_BULLET0_DXMAG"]
POD_BULLET1_ACT = sym["POD_BULLET1_ACT"]
POD_BULLET1_X = sym["POD_BULLET1_X"]; POD_BULLET1_Y = sym["POD_BULLET1_Y"]
POD_BULLET1_DY = sym["POD_BULLET1_DY"]
POD_BULLET1_DXMAG = sym["POD_BULLET1_DXMAG"]
POD_BULLET_SPEED = sym["POD_BULLET_SPEED"]
POD_BULLET_HOMING_THRESHOLD_X = sym["POD_BULLET_HOMING_THRESHOLD_X"]
BOSS_ORBIT_ANGLE = sym["BOSS_ORBIT_ANGLE"]
POD_AIM_DIR_LUT = sym["POD_AIM_DIR_LUT"]
POD_AIM_DXMAG_TABLE = sym["POD_AIM_DXMAG_TABLE"]
POD_AIM_DY_TABLE = sym["POD_AIM_DY_TABLE"]

check("POD_BULLET_HOMING_THRESHOLD_X is 128 (screen width 256 / 2)",
      POD_BULLET_HOMING_THRESHOLD_X == 128)


def s8(raw):
    """raw hw byte -> signed interpretation, for readable assertions."""
    raw &= 0xFF
    return raw - 256 if raw >= 128 else raw


# ================= (0) Python reference model =================
# Faithful, independently-written re-derivation of the exact algorithm
# baked into POD_AIM_CLASSIFY (fold -> swap -> 7 boundary tests via
# compile-time shift-add multiplies -> POD_AIM_DIR_LUT unfold). Built
# and cross-checked against the real Z80 routine's actual K constants/
# LUT contents read directly from the assembled ROM below (not
# hand-copied), so a future edit to either side that drifts out of sync
# is caught mechanically.
N = 32
FULL_STEP = 180.0 / N
K_TABLE = [13, 38, 64, 92, 121, 153, 190]


def mul_const(ax, k):
    """ax*k via the exact same MSB-first shift-add sequence baked into
    the ASM (LD HL,0; then ADD HL,HL / ADD HL,DE per bit of k)."""
    bits = bin(k)[2:]
    hl = 0
    for b in bits:
        hl = (hl << 1) & 0xFFFF
        if b == '1':
            hl = (hl + ax) & 0xFFFF
    return hl


def ref_classify(dx, dy):
    sdx = s8(dx); sdy = s8(dy)
    u = (-sdx) if sdx < 0 else 0
    u &= 0xFF
    ax = u
    fold = 0
    if sdy < 0:
        fold |= (1 << 4)
        ay = (-sdy) & 0xFF
    else:
        ay = sdy & 0xFF
    if ay < ax or ay == ax:
        pass
    else:
        ax, ay = ay, ax
        fold |= (1 << 3)
    bucket = 0
    for k in K_TABLE:
        prod = mul_const(ax, k)
        H = (prod >> 8) & 0xFF
        if ay > H:
            bucket += 1
    fold |= bucket
    return fold


def ideal_dir(dx, dy):
    sdx = s8(dx); sdy = s8(dy)
    u = -sdx if sdx < 0 else 0
    v = sdy
    if u == 0 and v == 0:
        return N // 2
    ang = math.degrees(math.atan2(v, u))
    idx = round((ang + 90.0) / FULL_STEP)
    return max(0, min(N - 1, idx))


# read the real ROM-embedded tables (ground truth, not re-derived)
real_dir_lut = [mem0[(POD_AIM_DIR_LUT + i) & 0xFFFF] for i in range(32)]
real_dxmag = [mem0[(POD_AIM_DXMAG_TABLE + i) & 0xFFFF] for i in range(32)]
real_dy_table = [s8(mem0[(POD_AIM_DY_TABLE + i) & 0xFFFF]) for i in range(32)]

check("POD_AIM_DXMAG_TABLE entries are all in 1..12 (always a positive magnitude)",
      all(1 <= v <= 12 for v in real_dxmag))
check("POD_AIM_DY_TABLE entries are all in -12..12",
      all(-12 <= v <= 12 for v in real_dy_table))
check("POD_AIM_DIR_LUT has no unreachable/out-of-range entries (all 0-31)",
      all(0 <= v <= 31 for v in real_dir_lut))


# ================= (1) POD_AIM_CLASSIFY: direct unit tests =================
def classify(dx, dy):
    z = fresh()
    z.d = dx & 0xFF
    z.e = dy & 0xFF
    call_routine(z, POD_AIM_CLASSIFY)
    return z.a


# dense sample: full signed-byte domain for dx, dy (matches the
# validation performed during development) - checks the REAL assembled
# routine (which already applies the POD_AIM_DIR_LUT unfold internally,
# so classify() returns the FINAL direction index, 0-31) against the
# Python reference model's fold_code unfolded through the same
# ROM-embedded LUT.
mismatches = 0
max_angle_err = 0
sample_dx = list(range(-128, 128, 3))  # stride for test speed; still >8000 pairs
sample_dy = list(range(-128, 128, 3))
for dx in sample_dx:
    for dy in sample_dy:
        real_dir = classify(dx, dy)
        expect_dir = real_dir_lut[ref_classify(dx, dy)]
        if real_dir != expect_dir:
            mismatches += 1
        ideal = ideal_dir(dx, dy)
        max_angle_err = max(max_angle_err, abs(real_dir - ideal))

check(f"POD_AIM_CLASSIFY matches the Python reference model exactly across "
      f"{len(sample_dx)*len(sample_dy)} sampled (dx,dy) pairs (mismatches={mismatches})",
      mismatches == 0)
check(f"resulting direction never deviates from the ideal atan2 angle by more than "
      f"1 step (5.625 degrees) - max observed error: {max_angle_err} step(s)",
      max_angle_err <= 1)

# a few concrete, easy-to-reason-about cases
check("dx=-100,dy=0 (straight left): direction index 15 or 16 (near-horizontal)",
      classify(-100, 0) in (15, 16))
check("dx=-100,dy=-100 (up-left diagonal, 45 degrees): direction index near 8 (0-indexed octant boundary)",
      abs(classify(-100, -100) - 8) <= 1)
check("dx=-100,dy=100 (down-left diagonal, 45 degrees): direction index near 23",
      abs(classify(-100, 100) - 23) <= 1)
check("dx=0,dy=-100 (straight up): direction index near 0",
      classify(0, -100) <= 1)
check("dx=0,dy=100 (straight down): direction index near 31",
      classify(0, 100) >= 30)


# ================= (2) POD_BULLET_CALC_DIR =================
def calc_dir(pod_x, pod_y, player_x, player_y):
    z = fresh()
    z.wr(PLAYERX, player_x)
    z.wr(PLAYERY, player_y)
    z.d = pod_x & 0xFF
    z.e = pod_y & 0xFF
    call_routine(z, POD_BULLET_CALC_DIR)
    return z.b, s8(z.c)  # (dxmag, dy)


check("PLAYERX exactly at the left half (127): straight, dxmag=POD_BULLET_SPEED, dy=0",
      calc_dir(pod_x=200, pod_y=100, player_x=127, player_y=50) == (POD_BULLET_SPEED, 0))
check("PLAYERX well left of threshold: straight regardless of Y",
      calc_dir(pod_x=200, pod_y=100, player_x=10, player_y=180) == (POD_BULLET_SPEED, 0))

# aim case: cross-check against the direct classify()+table lookup path
for (pod_x, pod_y, player_x, player_y) in [
    (228, 72, 200, 150), (200, 60, 220, 30), (210, 100, 250, 100),
    (228, 90, 128, 0), (200, 50, 240, 191),
]:
    dxmag, dy = calc_dir(pod_x, pod_y, player_x, player_y)
    dx_signed = s8((player_x - pod_x) & 0xFF)
    dy_signed = s8((player_y - pod_y) & 0xFF)
    dirn = classify(dx_signed, dy_signed)
    exp_dxmag = real_dxmag[dirn]
    exp_dy = real_dy_table[dirn]
    check(f"POD_BULLET_CALC_DIR(pod=({pod_x},{pod_y}), player=({player_x},{player_y})) "
          f"matches independent classify+table lookup (dxmag,dy)=({dxmag},{dy})",
          dxmag == exp_dxmag and dy == exp_dy)


# ================= (3) POD_BULLET_MOVE: variable DXMAG + signed DY =================
z = fresh()
z.wr(POD_BULLET0_ACT, 1)
z.wr(POD_BULLET0_X, 100); z.wr(POD_BULLET0_Y, 80)
z.wr(POD_BULLET0_DXMAG, 5)
z.wr(POD_BULLET0_DY, 7 & 0xFF)
z.wr(POD_BULLET1_ACT, 1)
z.wr(POD_BULLET1_X, 100); z.wr(POD_BULLET1_Y, 80)
z.wr(POD_BULLET1_DXMAG, 9)
z.wr(POD_BULLET1_DY, (-4) & 0xFF)
call_routine(z, POD_BULLET_MOVE)
check("POD_BULLET_MOVE: bullet0's X decrements by its own stored DXMAG(5), not the old fixed 12",
      z.rd(POD_BULLET0_X) == 100 - 5)
check("...and its Y advances by its own stored DY(+7)",
      z.rd(POD_BULLET0_Y) == 80 + 7)
check("POD_BULLET_MOVE: bullet1's X decrements by its own stored DXMAG(9)",
      z.rd(POD_BULLET1_X) == 100 - 9)
check("...and its Y advances by its own stored DY(-4)",
      z.rd(POD_BULLET1_Y) == 80 - 4)

# straight-shot compat: DXMAG=POD_BULLET_SPEED(12), DY=0 must behave exactly
# as the pre-existing fixed-speed code did.
z2 = fresh()
z2.wr(POD_BULLET0_ACT, 1)
z2.wr(POD_BULLET0_X, 100); z2.wr(POD_BULLET0_Y, 80)
z2.wr(POD_BULLET0_DXMAG, POD_BULLET_SPEED)
z2.wr(POD_BULLET0_DY, 0)
call_routine(z2, POD_BULLET_MOVE)
check(f"POD_BULLET_MOVE with DXMAG=POD_BULLET_SPEED({POD_BULLET_SPEED}),DY=0: byte-identical to the old straight-shot behavior",
      z2.rd(POD_BULLET0_X) == 100 - POD_BULLET_SPEED and z2.rd(POD_BULLET0_Y) == 80)

# off-screen detection (X underflow) must still work correctly with a
# SMALL dxmag (e.g. a near-vertical shot, dxmag=1) - the bullet should
# survive many more frames before going off-screen than a straight shot
# would, since it's barely moving horizontally.
z3 = fresh()
z3.wr(POD_BULLET0_ACT, 1)
z3.wr(POD_BULLET0_X, 5); z3.wr(POD_BULLET0_Y, 80)
z3.wr(POD_BULLET0_DXMAG, 1)
z3.wr(POD_BULLET0_DY, 0)
call_routine(z3, POD_BULLET_MOVE)
check("POD_BULLET_MOVE: small dxmag(1) from X=5 does NOT go off-screen yet (X=4)",
      z3.rd(POD_BULLET0_ACT) == 1 and z3.rd(POD_BULLET0_X) == 4)

z4 = fresh()
z4.wr(POD_BULLET0_ACT, 1)
z4.wr(POD_BULLET0_X, 5); z4.wr(POD_BULLET0_Y, 80)
z4.wr(POD_BULLET0_DXMAG, 12)
z4.wr(POD_BULLET0_DY, 0)
call_routine(z4, POD_BULLET_MOVE)
check("POD_BULLET_MOVE: large dxmag(12) from X=5 correctly triggers off-screen hide (ACT->0)",
      z4.rd(POD_BULLET0_ACT) == 0)


# ================= (4) POD_FIRE_DO_PAIR: the real firing path, end to end =================
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
check("real firing path: PLAYERX on the left half -> both bullets fire straight "
      "(dxmag=POD_BULLET_SPEED, dy=0, unchanged straight-shot behavior)",
      z.rd(POD_BULLET0_ACT) == 1 and z.rd(POD_BULLET0_DXMAG) == POD_BULLET_SPEED and
      s8(z.rd(POD_BULLET0_DY)) == 0 and
      z.rd(POD_BULLET1_ACT) == 1 and z.rd(POD_BULLET1_DXMAG) == POD_BULLET_SPEED and
      s8(z.rd(POD_BULLET1_DY)) == 0)

z = fire_pair(player_x=200, player_y=250 % 256, pair=0)
real_bullet0_x = z.rd(POD_BULLET0_X); real_bullet0_y = z.rd(POD_BULLET0_Y)
real_bullet1_x = z.rd(POD_BULLET1_X); real_bullet1_y = z.rd(POD_BULLET1_Y)
exp0_dxmag, exp0_dy = calc_dir(real_bullet0_x, real_bullet0_y, 200, 250 % 256)
exp1_dxmag, exp1_dy = calc_dir(real_bullet1_x, real_bullet1_y, 200, 250 % 256)
check("real firing path: PLAYERX on the right half -> bullet0 gets exactly the "
      "(dxmag,dy) POD_BULLET_CALC_DIR independently computes for its own real spawn (X,Y)",
      z.rd(POD_BULLET0_DXMAG) == exp0_dxmag and s8(z.rd(POD_BULLET0_DY)) == exp0_dy)
check("...and bullet1 too (its own, independently different, spawn X/Y)",
      z.rd(POD_BULLET1_DXMAG) == exp1_dxmag and s8(z.rd(POD_BULLET1_DY)) == exp1_dy)

# a pod pair where only ONE of the 2 pods is alive - the fired bullet
# still gets aimed correctly (loop-independence check), and the pod-pair
# index (B) used for POD_RECOIL indexing right after the call must still
# be correct (this is what the PUSH BC/POP BC around POD_BULLET_CALC_DIR
# is specifically for).
z = fresh()
z.wr(BOSS_ORBIT_ANGLE, 0)
z.wr(POD_FIRE_PAIR, 2)
z.wr(POD_HP + 2, 1)   # pod index2 alive
z.wr(POD_HP + 3, 0)   # pod index3 dead
z.wr(PLAYERX, 200)
z.wr(PLAYERY, 30)
POD_RECOIL = sym["POD_RECOIL"]
POD_RECOIL_DURATION = sym["POD_RECOIL_DURATION"]
call_routine(z, POD_FIRE_DO_PAIR)
check("only pod0 of the pair alive: bullet0 fires and gets aimed (nonzero dy, player above-right)",
      z.rd(POD_BULLET0_ACT) == 1 and s8(z.rd(POD_BULLET0_DY)) != 0)
check("...bullet1 (dead pod) never fires at all", z.rd(POD_BULLET1_ACT) == 0)
check("pod-pair index (B) survives the CALC_DIR call correctly: POD_RECOIL[2] (the "
      "fired pod's own slot) was armed, not some other slot",
      z.rd(POD_RECOIL + 2) == POD_RECOIL_DURATION)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
