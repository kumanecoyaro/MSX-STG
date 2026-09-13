"""Stage2敵撃破時の得点付与を検証(2026-09-13、"ステージ2のエネミーの得点
ZakoIi緑100赤300Flyer500Zum500戦車1000BigZum2000ボス30000点")。

これまで全ての敵撃破が一律SCORE_PER_KILL(=1、100点)だったのを、敵種
ごとの個別スコア定数(SCORE_ZACOII_GREEN/RED、SCORE_ZUM、SCORE_FLYER、
SCORE_ETANK、SCORE_BIGZUM、SCORE_BOSS)へ差し替えた。各CHECK_HIT_PAIR_*
系を実際に呼び、そのCALL経路を通してSCOREが期待どおりの増分(ADD_SCORE
の単位=実得点/100)だけ増えることを直接検証する。

tools/stage2_combined/tests/bigzum_retreat_test.py/etank_unit.py と同じ
「banked_helpers.fresh_cpu()+call_routine、cpu.ix/cpu.iyで対象を指定」
の作法に倣う。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


SCORE = sym["SCORE"]
BULLET0_ACT = sym["BULLET0_ACT"]


def score_value(cpu):
    return cpu.mem[SCORE] | (cpu.mem[SCORE + 1] << 8) | (cpu.mem[SCORE + 2] << 16)


def check_score_delta(label, cpu_before_score, cpu, expected_units):
    delta = score_value(cpu) - cpu_before_score
    check(f"{label}: SCORE increases by exactly {expected_units} "
          f"({expected_units*100} real points)",
          delta == expected_units)


# ---------- ZacoII: green=100, red=300 ----------
ENEMY_POOL = sym["ENEMY_POOL"]
E_ACT = sym["E_ACT"]; E_X = sym["E_X"]; E_Y = sym["E_Y"]
E_VARIANT = sym["E_VARIANT"]; E_DX = sym["E_DX"]

def setup_zaco(cpu, variant, hp=None):
    cpu.mem[ENEMY_POOL + E_ACT] = 1
    cpu.mem[ENEMY_POOL + E_X] = 80
    cpu.mem[ENEMY_POOL + E_Y] = 80
    cpu.mem[ENEMY_POOL + E_VARIANT] = variant
    if hp is not None:
        cpu.mem[ENEMY_POOL + E_DX] = hp
    cpu.mem[BULLET0_ACT + 0] = 1
    cpu.mem[BULLET0_ACT + 2] = 80 // 8   # COL -> pixelX=80
    cpu.mem[BULLET0_ACT + 3] = 80 // 8   # ROW -> pixelY=80


cpu = fresh_cpu()
setup_zaco(cpu, variant=0)   # green, 1-hit-kill
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = ENEMY_POOL
call_routine(cpu, "CHECK_HIT_PAIR")
check("ZacoII green: bullet consumed and ZacoII destroyed",
      cpu.mem[BULLET0_ACT + 0] == 0 and cpu.mem[ENEMY_POOL + E_ACT] == 2)
check_score_delta("ZacoII green (100点)", before, cpu, sym["SCORE_ZACOII_GREEN"])

cpu = fresh_cpu()
setup_zaco(cpu, variant=1, hp=1)   # red, 1 hit left -> this hit kills
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = ENEMY_POOL
call_routine(cpu, "CHECK_HIT_PAIR")
check("ZacoII red (lethal hit): destroyed", cpu.mem[ENEMY_POOL + E_ACT] == 2)
check_score_delta("ZacoII red (300点)", before, cpu, sym["SCORE_ZACOII_RED"])

cpu = fresh_cpu()
setup_zaco(cpu, variant=1, hp=2)   # red, 2 hits left -> this hit survives
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = ENEMY_POOL
call_routine(cpu, "CHECK_HIT_PAIR")
check("ZacoII red (non-lethal hit): survives (still alive)", cpu.mem[ENEMY_POOL + E_ACT] == 1)
check_score_delta("ZacoII red non-lethal hit (no score yet)", before, cpu, 0)


# ---------- Zum: 500点 (rear hit only) ----------
ZUM_POOL = sym["ZUM_POOL"]
TANK_X = sym["TANK_X"]

cpu = fresh_cpu()
cpu.mem[ZUM_POOL + 0] = 1     # Z_ACT
cpu.mem[ZUM_POOL + 1] = 80    # Z_X
cpu.mem[ZUM_POOL + 2] = 80    # Z_Y
cpu.mem[ZUM_POOL + 7] = 0     # Z_RETREAT=0 (normal, facing left)
cpu.mem[TANK_X] = 200         # TANK behind Zum (TANK_X >= Z_X) -> rear hit
cpu.mem[BULLET0_ACT + 0] = 1
cpu.mem[BULLET0_ACT + 2] = 80 // 8
cpu.mem[BULLET0_ACT + 3] = 80 // 8
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = ZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_ZUM")
check("Zum rear hit: destroyed (1-hit-kill)", cpu.mem[ZUM_POOL + 0] == 2)
check_score_delta("Zum (500点)", before, cpu, sym["SCORE_ZUM"])


# ---------- Flyer: 500点 ----------
FLYER_POOL = sym["FLYER_POOL"]

cpu = fresh_cpu()
cpu.mem[FLYER_POOL + 0] = 1     # ACT
cpu.mem[FLYER_POOL + 1] = 80    # X
cpu.mem[FLYER_POOL + 2] = 80    # Y
cpu.mem[FLYER_POOL + 7] = 1     # HP=1 -> this hit kills
cpu.mem[BULLET0_ACT + 0] = 1
cpu.mem[BULLET0_ACT + 2] = 80 // 8
cpu.mem[BULLET0_ACT + 3] = 80 // 8
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = FLYER_POOL
call_routine(cpu, "CHECK_HIT_PAIR_FLYER")
check("Flyer (lethal hit): destroyed", cpu.mem[FLYER_POOL + 0] == 2)
check_score_delta("Flyer (500点)", before, cpu, sym["SCORE_FLYER"])


# ---------- Etank(戦車): 1000点 ----------
ETANK_POOL = sym["ETANK_POOL"]
ETANK_COLLISION_Y_OFFSET = sym["ETANK_COLLISION_Y_OFFSET"]

cpu = fresh_cpu()
cpu.mem[ETANK_POOL + 0] = 1     # ACT
cpu.mem[ETANK_POOL + 1] = 100   # X
cpu.mem[ETANK_POOL + 2] = 80    # Y
cpu.mem[ETANK_POOL + 6] = 1     # HP=1 -> this hit kills
cpu.mem[BULLET0_ACT + 0] = 1
cpu.mem[BULLET0_ACT + 2] = 100 // 8
cpu.mem[BULLET0_ACT + 3] = (80 + ETANK_COLLISION_Y_OFFSET) // 8
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = ETANK_POOL
call_routine(cpu, "CHECK_HIT_PAIR_ETANK")
check("Etank(戦車) (lethal hit): destroyed", cpu.mem[ETANK_POOL + 0] == 2)
check_score_delta("Etank/戦車 (1000点)", before, cpu, sym["SCORE_ETANK"])


# ---------- BigZum: 2000点 ----------
BIGZUM_POOL = sym["BIGZUM_POOL"]

cpu = fresh_cpu()
cpu.mem[BIGZUM_POOL + 0] = 1     # ACT
cpu.mem[BIGZUM_POOL + 1] = 80    # X
cpu.mem[BIGZUM_POOL + 2] = 80    # Y
cpu.mem[BIGZUM_POOL + 7] = 1     # STATE=1(jump) - bypasses front/rear split, same as bigzum_retreat_test.py's own positive control
cpu.mem[BIGZUM_POOL + 8] = 1     # HP=1 -> this hit kills
cpu.mem[BULLET0_ACT + 0] = 1
cpu.mem[BULLET0_ACT + 2] = 80 // 8
cpu.mem[BULLET0_ACT + 3] = (80 + sym["BIGZUM_COLLISION_Y_OFFSET"]) // 8   # box Y starts at BZ_Y+offset, not BZ_Y itself
before = score_value(cpu)
cpu.ix = BULLET0_ACT
cpu.iy = BIGZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_BIGZUM")
check("BigZum (lethal hit): destroyed", cpu.mem[BIGZUM_POOL + 0] == 2)
check_score_delta("BigZum (2000点)", before, cpu, sym["SCORE_BIGZUM"])


# ---------- Boss: 30000点 ----------
BOSS_ACT = sym["BOSS_ACT"]; BOSS_X = sym["BOSS_X"]; BOSS_Y = sym["BOSS_Y"]
BOSS_HP = sym["BOSS_HP"]; BOSS_FORM = sym["BOSS_FORM"]
BOSS_MATERIALIZE_ACT = sym["BOSS_MATERIALIZE_ACT"]

cpu = fresh_cpu()
cpu.mem[BOSS_ACT] = 1
cpu.mem[BOSS_FORM] = 0
cpu.mem[BOSS_MATERIALIZE_ACT] = 0   # materialize effect done - collision enabled
cpu.mem[BOSS_X] = 80
cpu.mem[BOSS_Y] = 80
cpu.mem[BOSS_HP] = 1   # 1 HP left -> this hit kills
cpu.mem[BULLET0_ACT + 0] = 1
cpu.mem[BULLET0_ACT + 2] = 80 // 8
cpu.mem[BULLET0_ACT + 3] = 80 // 8
before = score_value(cpu)
cpu.ix = BULLET0_ACT
call_routine(cpu, "CHECK_HIT_PAIR_BOSS")
check("Boss (lethal hit): destroyed (BOSS_ACT=2)", cpu.mem[BOSS_ACT] == 2)
check_score_delta("Stage2ボス (30000点)", before, cpu, sym["SCORE_BOSS"])


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
