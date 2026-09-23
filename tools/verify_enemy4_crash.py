"""Stage1: round141("エネミー4...耐久値2だが1発当たったら左斜め下に墜落
自機の墜落の逆向きだな 爆発エフェクトも自機と同じだがサウンドは無しで")、
続く訂正("エネミー4は墜落で無敵にはならない 2発目が当たったら爆発する
ように")の検証。TYPE_ENEMY4(Fighter)を手動でENEMY_POOLへ配置し、実際の
CHECK_BULLET_VS_ENEMY_POOL経由の被弾で: 1発目はクラッシュ(E_FLAGS=1、
E_PARAM0/2を強制的にdown-diveへ)をトリガーするのみでスコア加算も撃破も
しないこと、以後の被弾には無敵にならず2発目も普通にヒット判定される
こと、2発目で実際に撃破(スプライト非表示・スロット解放・スコア加算・
PLAYER_EXPL_POOLのバースト追加ポップ)されること、1発目〜2発目の
間もENEMY_POOL_UPDATE_ALLを回すと実際に左斜め下へドリフトし続け、
PLAYER_EXPL_POOL(自機爆発と共通のバースト)が自機爆発の音付きでポップし続けることを
直接検証する(2026-09-23までは音無しだった)。
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
SPRITE_USED = sym["SPRITE_USED"]
SCORE = sym["SCORE"]

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def read_score(z):
    return z.rd(SCORE) | (z.rd(SCORE + 1) << 8) | (z.rd(SCORE + 2) << 16)


# ============================================================
# 1. 1発目: 被弾で即座にクラッシュ(down-dive)がトリガーされる。
#    まだスコアは入らず、スロットも解放されない(墜落継続)。
# ============================================================
z = fresh()
slot = ENEMY_POOL  # slot 0
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
START_X = 100
START_Y = 80
SPRNUM = 5
z.wr(slot + E_X, START_X)
z.wr(slot + E_Y, START_Y)
z.wr(slot + E_SPRNUM, SPRNUM)
z.wr(SPRITE_USED + SPRNUM, 1)

# bullet position to hit: EBSD_HT_ENEMY4 passes D=E_X, E=E_Y+8 into
# QUAD_HIT_TEST; the bullet box there is col*8/row*8. CHECK_BULLET_VS_
# ENEMY_POOL's actual INPUT is B=col/C=row (ENEMY_HIT_COL/ROW are just
# its own internal scratch copies written from B/C in its prologue).
col = START_X // 8
row = (START_Y + 8) // 8

score_before_hit1 = read_score(z)
call_routine_bc(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], col, row)
check(f"first hit registers as a hit (A={z.a})", z.a == 1)
check(f"E_FLAGS set to 1 (crashing) after first hit (={z.rd(slot+E_FLAGS)})", z.rd(slot+E_FLAGS) == 1)
check(f"E_PARAM0 forced to 1 (dive armed even if not naturally triggered yet) (={z.rd(slot+E_PARAM0)})",
      z.rd(slot+E_PARAM0) == 1)
check(f"E_PARAM2 forced to 1 (down direction, never up) (={z.rd(slot+E_PARAM2)})", z.rd(slot+E_PARAM2) == 1)
check(f"E_ACTIVE still 1 after first hit (not destroyed yet, keeps flying, ={z.rd(slot+E_ACTIVE)})",
      z.rd(slot+E_ACTIVE) == 1)
check(f"SPRITE_USED slot still claimed after first hit (={z.rd(SPRITE_USED+SPRNUM)})",
      z.rd(SPRITE_USED+SPRNUM) == 1)
check(f"score unchanged after first hit ({score_before_hit1} -> {read_score(z)})",
      read_score(z) == score_before_hit1)

# --- run a few frames of real ENEMY_POOL_UPDATE_ALL between hit1 and hit2:
#     confirm it drifts down-left and the quiet trickle FX keeps popping. ---
xs = []
ys = []
for i in range(20):
    call_routine(z, sym["ENEMY_POOL_UPDATE_ALL"])
    xs.append(z.rd(slot + E_X))
    ys.append(z.rd(slot + E_Y))
check(f"X decreases over 20 frames between hit1 and hit2 (drifting left, {START_X}->{xs[-1]})",
      xs[-1] < START_X)
check(f"Y increases over 20 frames between hit1 and hit2 (falling down, {START_Y}->{ys[-1]})",
      ys[-1] > START_Y)

any_active = any(z.rd(PLAYER_EXPL_POOL + i * PLAYER_EXPL_STRUCT) != 0 for i in range(PLAYER_EXPL_SLOTS))
check("PLAYER_EXPL_POOL(自機と共通の爆発バースト)へ、1発目〜2発目の間も"
      "実際にパーティクルが1個以上ポップされる(クラッシュ中、EBSD_DIAG_E4のFXトリガー経由)", any_active)


# ============================================================
# 2. 2発目: クラッシュ中でも無敵にならず普通にヒット判定される。
#    実際に撃破(スプライト非表示・スロット解放・スコア加算)される。
# ============================================================
col2 = z.rd(slot + E_X) // 8
row2 = (z.rd(slot + E_Y) + 8) // 8
score_before_hit2 = read_score(z)
call_routine_bc(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], col2, row2)
check(f"second hit on an already-crashing instance still registers as a hit (not immune, A={z.a})", z.a == 1)
check(f"E_ACTIVE cleared after second hit (slot freed, ={z.rd(slot+E_ACTIVE)})", z.rd(slot+E_ACTIVE) == 0)
check(f"SPRITE_USED slot released after second hit (={z.rd(SPRITE_USED+SPRNUM)})",
      z.rd(SPRITE_USED+SPRNUM) == 0)
check(f"score increased after second hit ({score_before_hit2} -> {read_score(z)})",
      read_score(z) > score_before_hit2)

any_active_after_kill = any(z.rd(PLAYER_EXPL_POOL + i * PLAYER_EXPL_STRUCT) != 0 for i in range(PLAYER_EXPL_SLOTS))
check("2発目の撃破時にもPLAYER_EXPL_POOLへ追加のバーストが実際にポップされる", any_active_after_kill)


# ============================================================
# 3. (2026-09-23、"エネミー4は墜落や爆破で無音になってるけど やっぱ音つけて")
#    墜落中のポップ・2発目の撃破とも、自機爆発と同じくSOUND_DESTROYが鳴る。
#    実際の被弾/更新経路を1命令ずつ回し、SOUND_DESTROYへ入った回数を数える。
# ============================================================
def count_sound(z, entry, b=None, c=None):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0)
    if b is not None: z.b = b; z.c = c
    z.pc = entry; n = 0
    for _ in range(300000):
        if z.pc == 0: return n
        if z.pc == sym["SOUND_DESTROY"]: n += 1
        z.step()
    raise RuntimeError("stuck")
z = fresh()
z.wr(slot + E_ACTIVE, 1); z.wr(slot + E_TYPE, TYPE_ENEMY4); z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, START_X); z.wr(slot + E_Y, START_Y); z.wr(slot + E_SPRNUM, SPRNUM); z.wr(SPRITE_USED + SPRNUM, 1)
call_routine_bc(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], col, row)
n_crash = sum(count_sound(z, sym["ENEMY_POOL_UPDATE_ALL"]) for _ in range(20))
check(f"墜落中の爆発ポップで自機爆発の音(SOUND_DESTROY)が鳴る(20フレームで{n_crash}回)", n_crash >= 2)
n_kill = count_sound(z, sym["CHECK_BULLET_VS_ENEMY_POOL"], z.rd(slot + E_X) // 8, (z.rd(slot + E_Y) + 8) // 8)
check(f"2発目の撃破でも自機爆発の音が鳴る({n_kill}回)", n_kill == 1 and z.rd(slot + E_ACTIVE) == 0)
check("無音版PEUA_TRY_SPAWN_AT_QUIETは廃止", "PEUA_TRY_SPAWN_AT_QUIET" not in sym)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f_ in fail:
        print(" -", f_)
    sys.exit(1)
