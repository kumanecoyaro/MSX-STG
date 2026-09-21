"""Stage1: round141("エネミー4...耐久値2だが1発当たったら左斜め下に墜落
自機の墜落の逆向きだな 爆発エフェクトも自機と同じだがサウンドは無しで")の
検証。TYPE_ENEMY4(Fighter)を手動でENEMY_POOLへ配置し、実際の
CHECK_BULLET_VS_ENEMY_POOL経由の被弾でクラッシュ(E_FLAGS=1、E_PARAM0/2を
強制的にdown-diveへ)がトリガーされること、以後の被弾には無敵になる
こと、ENEMY_POOL_UPDATE_ALLを回すと実際に左斜め下へドリフトし続ける
こと、PLAYER_EXPL_POOL(自機爆発と共通のバースト)が音無しで(PSGレジスタ
を一切書き換えずに)ポップし続けることを直接検証する。
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


def call_routine_bc(z, entry_addr, b, c, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.b = b; z.c = c
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


E_ACTIVE = sym["E_ACTIVE"]; E_TYPE = sym["E_TYPE"]; E_BEHAVIOR = sym["E_BEHAVIOR"]
E_X = sym["E_X"]; E_Y = sym["E_Y"]; E_SPRNUM = sym["E_SPRNUM"]
E_FLAGS = sym["E_FLAGS"]
E_PARAM0 = sym["E_PARAM0"]; E_PARAM2 = sym["E_PARAM2"]
ENEMY_POOL = sym["ENEMY_POOL"]
TYPE_ENEMY4 = sym["TYPE_ENEMY4"]
BEHAVIOR_SIMPLE_DRIFT_DODGE = sym["BEHAVIOR_SIMPLE_DRIFT_DODGE"]
PLAYER_EXPL_POOL = sym["PLAYER_EXPL_POOL"]; PLAYER_EXPL_SLOTS = sym["PLAYER_EXPL_SLOTS"]
PLAYER_EXPL_STRUCT = sym["PLAYER_EXPL_STRUCT"]
EBUZ_EXPL_POS_X = sym["EBUZ_EXPL_POS_X"]; EBUZ_EXPL_POS_Y = sym["EBUZ_EXPL_POS_Y"]

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


# ============================================================
# 1. 被弾で即座にクラッシュ(down-dive)がトリガーされる、以後無敵、
#    実際にENEMY_POOL_UPDATE_ALLで左斜め下へドリフトし続ける。
# ============================================================
z = fresh()
slot = ENEMY_POOL  # slot 0
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
START_X = 100
START_Y = 80
z.wr(slot + E_X, START_X)
z.wr(slot + E_Y, START_Y)
z.wr(slot + E_SPRNUM, 5)

# bullet position to hit: EBSD_HT_ENEMY4 passes D=E_X, E=E_Y+8 into
# QUAD_HIT_TEST; the bullet box there is col*8/row*8. CHECK_BULLET_VS_
# ENEMY_POOL's actual INPUT is B=col/C=row (ENEMY_HIT_COL/ROW are just
# its own internal scratch copies written from B/C in its prologue).
col = START_X // 8
row = (START_Y + 8) // 8

call_routine_bc(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], col, row)
check(f"first hit registers as a hit (A={z.a})", z.a == 1)
check(f"E_FLAGS set to 1 (crashing) after first hit (={z.rd(slot+E_FLAGS)})", z.rd(slot+E_FLAGS) == 1)
check(f"E_PARAM0 forced to 1 (dive armed even if not naturally triggered yet) (={z.rd(slot+E_PARAM0)})",
      z.rd(slot+E_PARAM0) == 1)
check(f"E_PARAM2 forced to 1 (down direction, never up) (={z.rd(slot+E_PARAM2)})", z.rd(slot+E_PARAM2) == 1)
check(f"E_ACTIVE still 1 (slot not freed, keeps flying like player's own death fall) (={z.rd(slot+E_ACTIVE)})",
      z.rd(slot+E_ACTIVE) == 1)

call_routine_bc(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], col, row)
check(f"second hit on an already-crashing instance is ignored (immune, A={z.a})", z.a == 0)

xs = []
ys = []
for i in range(60):
    call_routine(z, sym["ENEMY_POOL_UPDATE_ALL"])
    xs.append(z.rd(slot + E_X))
    ys.append(z.rd(slot + E_Y))
check(f"X decreases over 60 frames of real ENEMY_POOL_UPDATE_ALL (drifting left, {START_X}->{xs[-1]})",
      xs[-1] < START_X)
check(f"Y increases over 60 frames of real ENEMY_POOL_UPDATE_ALL (falling down, {START_Y}->{ys[-1]})",
      ys[-1] > START_Y)

any_active = any(z.rd(PLAYER_EXPL_POOL + i * PLAYER_EXPL_STRUCT) != 0 for i in range(PLAYER_EXPL_SLOTS))
check("PLAYER_EXPL_POOL(自機と共通の爆発バースト)へ実際にパーティクルが"
      "1個以上ポップされる(クラッシュ中、EBSD_DIAG_E4のFXトリガー経由)", any_active)


# ============================================================
# 2. 爆発エフェクトは自機と同じ仕組み(PEUA_TRY_SPAWN_AT_CORE)だが、
#    無音版(PEUA_TRY_SPAWN_AT_QUIET)を使っておりSOUND_DESTROYの
#    PSG書き込みが一切発生しないことを、有音版(PEUA_TRY_SPAWN_AT)との
#    直接比較で検証する。
# ============================================================
z_quiet = fresh()
z_quiet.wr(EBUZ_EXPL_POS_X, 50); z_quiet.wr(EBUZ_EXPL_POS_Y, 50)
psg_before_quiet = dict(z_quiet.psg_regs)
call_routine(z_quiet, sym["PEUA_TRY_SPAWN_AT_QUIET"])
check(f"PEUA_TRY_SPAWN_AT_QUIET はPSGレジスタを一切書き換えない(音無し、実測diff={dict(z_quiet.psg_regs)})",
      dict(z_quiet.psg_regs) == psg_before_quiet)

z_loud = fresh()
z_loud.wr(EBUZ_EXPL_POS_X, 50); z_loud.wr(EBUZ_EXPL_POS_Y, 50)
psg_before_loud = dict(z_loud.psg_regs)
call_routine(z_loud, sym["PEUA_TRY_SPAWN_AT"])
check(f"(対照) 有音版PEUA_TRY_SPAWN_AT は実際にPSGレジスタを書き換える"
      f"(SOUND_DESTROY、実測={dict(z_loud.psg_regs)})",
      dict(z_loud.psg_regs) != psg_before_loud)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f_ in fail:
        print(" -", f_)
    sys.exit(1)
