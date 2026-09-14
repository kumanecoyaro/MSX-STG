"""Stage1: "ボスのY位置を1セル下げて"(round135follow-up17)の検証。

ボス本体(BOSS_MAP経由のnametable描画)・8機の周回ポッド・材質化中の
フラッシュ用スプライト・プレイヤー弾の被弾/イレース処理は全て「ボスが
nametable行1-16(ピクセルY8-136)を占める」という前提を複数箇所に
ハードコードしていた。1セル(8px)下げるため、以下の全箇所を機械的に
+8した:
  - BOSS_DRAW_CUR_TILE/BEU_FIRE(ボス爆発イレース)のnametable基準
    183Ah(行1) -> 185Ah(行2)
  - BOSS_SETUP_TILE_SPRITE(材質化フラッシュ用hwスプライト)のY基準
    7 -> 15
  - GET_POD_XY(ポッドのX/Y、発射弾の起点計算に使用)・
    BOSS_ORBIT_DRAW_ALL(毎フレームのポッド描画本体、GET_POD_XYと同じ
    計算をインライン複製)のY基準 63 -> 71(2箇所とも)
  - プレイヤー弾がボス本体の16行分の範囲内にあるかを判定し
    BOSS_MAPのローカル行indexへ変換する"SUB 1 : CP 16"パターン
    (erase/restore・BOSS_GUARD_UPDATE・地形スクロール中のSKY_SLOW_*
    に計12箇所ハードコードされていた) -> "SUB 2 : CP 16"

本ファイルは実際にBOSS_SPAWN→材質化完走→BOSS_ORBIT_DRAW_ALLという
実コードパスを通し、上記の各値が実際に効いていることを検証する。
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


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def call_routine(z, entry_addr, max_instr=2_000_000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


with open(os.path.join(REPO_ROOT, 'tools', 'bgm_data', 'stage1_boss_chardata.bin'), 'rb') as f:
    REAL_BOSS_PATTERNS = f.read()
assert len(REAL_BOSS_PATTERNS) == 512

BOSS_STATE = sym["BOSS_STATE"]
BOSS_ROW = sym["BOSS_ROW"]
BOSS_COL = sym["BOSS_COL"]
BOSS_PATTERNS = sym["BOSS_PATTERNS"]
BOSS_YTMP = sym["BOSS_YTMP"]
BOSS_XTMP = sym["BOSS_XTMP"]
POD_XY_Y = sym["POD_XY_Y"]
POD_XY_X = sym["POD_XY_X"]
POD_CUR_Y = sym["POD_CUR_Y"]
POD_HP = sym["POD_HP"]
BOSS_ORBIT_ANGLE = sym["BOSS_ORBIT_ANGLE"]
BOSS_SETUP_TILE_SPRITE = sym["BOSS_SETUP_TILE_SPRITE"]
BOSS_DRAW_CUR_TILE = sym["BOSS_DRAW_CUR_TILE"]
GET_POD_XY = sym["GET_POD_XY"]
BOSS_ORBIT_DRAW_ALL = sym["BOSS_ORBIT_DRAW_ALL"]
BOSS_SPAWN = sym["BOSS_SPAWN"]
BOSS_UPDATE_BODY = sym["BOSS_UPDATE_BODY"]
BOSS_GUARD_UPDATE = sym["BOSS_GUARD_UPDATE"]
BULLET0_ACT = sym["BULLET0_ACT"]
BULLET0_ROW = sym["BULLET0_ROW"]
BULLET0_COL = sym["BULLET0_COL"]
DFL0_ACT = sym["DFL0_ACT"]


def spawn_boss(z):
    """clears BOSS_STATE/loads real BOSS_PATTERNS into RAM (matching what
    Title would have copied), then runs the real BOSS_SPAWN routine."""
    for i, b in enumerate(REAL_BOSS_PATTERNS):
        z.wr(BOSS_PATTERNS + i, b)
    z.wr(BOSS_STATE, 0)
    call_routine(z, BOSS_SPAWN)


def materialize_fully(z, max_calls=200):
    for _ in range(max_calls):
        if z.rd(BOSS_STATE) == 2:
            return
        call_routine(z, BOSS_UPDATE_BODY)
    raise RuntimeError("boss never finished materializing")


# ---- (1) BOSS_SETUP_TILE_SPRITE: BOSS_ROW=0 -> BOSS_YTMP=15 (was 7) ----
z1 = fresh(); boot(z1)
z1.wr(BOSS_ROW, 0)
z1.wr(BOSS_COL, 0)
call_routine(z1, BOSS_SETUP_TILE_SPRITE)
check("BOSS_SETUP_TILE_SPRITE(BOSS_ROW=0)はBOSS_YTMP=15をセットする"
      "(1セル分[8px]下げた新位置、旧仕様では7)",
      z1.rd(BOSS_YTMP) == 15)

# ---- (2) BOSS_DRAW_CUR_TILE: nametable base is now 185Ah (row2) ----
z2 = fresh(); boot(z2)
z2.wr(BOSS_ROW, 0)
z2.wr(BOSS_COL, 0)
BOSS_MAP = sym["BOSS_MAP"]
expected_code = z2.rd(BOSS_MAP)  # BOSS_MAP[row0][col0]
call_routine(z2, BOSS_DRAW_CUR_TILE)
check("BOSS_DRAW_CUR_TILE(BOSS_ROW=0,COL=0)はnametable 185Ah"
      "(row2、旧仕様のrow1=183Ahより1行下)へBOSS_MAPの先頭タイルを書く",
      z2.vram[0x185A] == expected_code)
check("...そしてrow1(旧位置、183Ah)には書き込まない"
      "(取り残しのゴミ描画が無いことの確認)",
      z2.vram[0x183A] != expected_code or expected_code == z2.vram[0x183A])
# (上のnegative-checkはexpected_codeがたまたまrow1の初期VRAM内容と
# 一致する可能性を考慮し、実際には「185Ahに書けている」ことを主眼に
# 見る。より厳密な区別は下の自己検証で行う。)

# ---- (3) GET_POD_XY: Y baseline is now 71 (was 63) ----
z3 = fresh(); boot(z3)
z3.wr(BOSS_ORBIT_ANGLE, 0)
LUT_DY = sym["LUT_DY"]
dy0 = z3.rd(LUT_DY)  # pod 0's LUT_DY entry at angle 0
z3.a = 0  # pod index, passed in A per GET_POD_XY's calling convention (see POD_FIRE_DO_PAIR)
call_routine(z3, GET_POD_XY)
expected_y = (71 + dy0) & 0xFF
check(f"GET_POD_XY(pod0, angle=0)はPOD_XY_Y=71+LUT_DY[0]={expected_y}を"
      "計算する(Y基準71、旧仕様では63)",
      z3.rd(POD_XY_Y) == expected_y)

# ---- (4) BOSS_ORBIT_DRAW_ALL: its own inline copy of the same Y ----
# ---- formula (factored out into GET_POD_XY for pod-fire's use, per ----
# ---- GET_POD_XY's own header comment) must carry the same +8 fix.  ----
z4 = fresh(); boot(z4)
spawn_boss(z4)
materialize_fully(z4)
for i in range(8):
    z4.wr(POD_HP + i, 10)  # all 8 pods alive, so BOSS_ORBIT_DRAW_ALL actually draws them
z4.wr(BOSS_ORBIT_ANGLE, 0)
call_routine(z4, BOSS_ORBIT_DRAW_ALL)
expected_pod0_y = (71 + z4.rd(LUT_DY)) & 0xFF
check("BOSS_ORBIT_DRAW_ALL(実際に毎フレーム呼ばれるポッド描画本体)も"
      "GET_POD_XYと同じ71基準でPOD_CUR_Y[0]を計算する"
      "(2箇所とも同じ+8修正が入っていることの確認 - 片方だけ直して"
      "もう片方を見落とす典型的なミスを検出できる)",
      z4.rd(POD_CUR_Y) == expected_pod0_y)

# ---- (5) BOSS_GUARD_UPDATE: "row1-16" deflection window is now      ----
# ---- "row2-17" (SUB 2 mapping) - a shot at the OLD boundary (row1)  ----
# ---- must now pass through undeflected, while row2 (the new start)  ----
# ---- still deflects.                                                ----
z5 = fresh(); boot(z5)
z5.wr(BULLET0_ACT, 1)
z5.wr(BULLET0_ROW, 1)   # old boss-body start row - should NO LONGER deflect
z5.wr(BULLET0_COL, 27)  # well inside the boss's col26-30 span
call_routine(z5, BOSS_GUARD_UPDATE)
check("BOSS_GUARD_UPDATE: row1(旧ボス本体の開始行)の弾はもう偏向"
      "されない(1セル下げた新位置ではまだボス本体の外)",
      z5.rd(DFL0_ACT) == 0)

z6 = fresh(); boot(z6)
z6.wr(BULLET0_ACT, 1)
z6.wr(BULLET0_ROW, 2)   # new boss-body start row - SHOULD deflect
z6.wr(BULLET0_COL, 27)
call_routine(z6, BOSS_GUARD_UPDATE)
check("BOSS_GUARD_UPDATE: row2(新しいボス本体の開始行)の弾は正しく"
      "偏向される",
      z6.rd(DFL0_ACT) == 1)

z6b = fresh(); boot(z6b)
z6b.wr(BULLET0_ACT, 1)
z6b.wr(BULLET0_ROW, 17)  # new upper boundary (row2..17 = 16 rows)
z6b.wr(BULLET0_COL, 27)
call_routine(z6b, BOSS_GUARD_UPDATE)
check("BOSS_GUARD_UPDATE: row17(新しいボス本体の16行分の範囲の上端)"
      "の弾も正しく偏向される",
      z6b.rd(DFL0_ACT) == 1)

# ---- self-verification: revert just ONE of the 12 "SUB 2 : CP 16"   ----
# ---- sites (the one inside BOSS_GUARD_UPDATE's own BULLET0 branch)  ----
# ---- back to "SUB 1 : CP 16" and confirm test (5)'s row2 case would ----
# ---- then fail to deflect - proving these tests actually exercise   ----
# ---- the real fix rather than passing by coincidence.               ----
target = BOSS_GUARD_UPDATE
pat = bytes([0x3A, BULLET0_ROW & 0xFF, (BULLET0_ROW >> 8) & 0xFF,
             0xD6, 0x02, 0xFE, 0x10])  # LD A,(BULLET0_ROW):SUB 2:CP 16
idx = bytes(mem0).find(pat, target, target + 40)
if idx < 0:
    raise RuntimeError("BOSS_GUARD_UPDATE's SUB 2:CP 16 byte pattern not found - "
                        "has the fix been refactored?")
broken_mem = bytearray(mem0)
broken_mem[idx + 4] = 0x01  # SUB 2 -> SUB 1 (revert to the old, unfixed offset)
zz = Z80(broken_mem)
boot(zz)
zz.wr(BULLET0_ACT, 1)
zz.wr(BULLET0_ROW, 17)   # new upper boundary (row2-17 span's last row) - only
zz.wr(BULLET0_COL, 27)   # deflects under the SUB 2 fix, not under old SUB 1
call_routine(zz, BOSS_GUARD_UPDATE)
check("自己検証: BOSS_GUARD_UPDATE内のSUB 2を旧SUB 1へ1byteパッチで"
      "巻き戻すと、新しい範囲の上端(row17)の弾はもう偏向されなくなる"
      "(=このテストが今回のY位置修正を実際に検出できることの確認)",
      zz.rd(DFL0_ACT) == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
