"""Stage1: MAINLOOPのリファクタリング前監査(round135follow-up15)の一環。

ユーザー指示: "またさっきの報告のように 不要なループカウントや 無限
ループに陥ってないか これは回帰テストで計測しろ"。

直前のCHECK_BOSS_TRIGGER実装(round135follow-up14)で、SCAN_POOL_ACTIVEの
Bレジスタ(スロット数)がDJNZで必ず0まで消費されるにも関わらず、2回目の
呼び出し前にリロードし忘れて256回近くループする実バグを作り込んでいた
(専用テストで発見・修正済み)。目視でのコードレビューだけでは同種の
バグを見落とす可能性があるため、実際にZ80命令実行数を計測する形で
MAINLOOP到達可能な全サブシステムを横断的に検証する。

手法: 各サブシステムのプール/フラグを可能な限り「全スロット活性化」
した最悪ケース状態を用意し、実際にstep_frame()(本物のMAINLOOP1周)を
複数フレーム走らせて命令実行数を計測、静的に見積もった妥当な上限
(全ループがDJNZ/カウンタで正しく境界されていれば収まるはずの値)を
大きく超えないことを確認する。真の無限ループならこの上限テスト自体が
タイムアウト/例外で検出でき、"256回化"のような部分的な暴走なら
命令数の異常値として検出できる。

自己検証として、round135follow-up14で実際に踏んだバグ(SCAN_POOL_ACTIVE
呼び出し間でのBレジスタ再ロード漏れ)をこの监视対象状態下で再現し、
本テストの計測方式が実際にそれを検出できることも確認する。
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


def fresh(mem=None):
    return Z80(bytearray(mem if mem is not None else mem0))


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame_counted(z, max_instr=2_000_000):
    """MAINLOOPを1周させ、実際に実行した命令数を返す。"""
    z.pc = sym["MAINLOOP"]
    n = 0
    z.step(); n += 1
    for _ in range(max_instr):
        if z.pc == sym["MAINLOOP"]:
            return n
        z.step()
        n += 1
    raise RuntimeError(f"MAINLOOP did not return within {max_instr} instructions "
                        f"(stuck/runaway at PC {z.pc:04X}, executed {n} so far)")


def wr16(z, addr, val):
    z.wr(addr, val & 0xFF)
    z.wr(addr + 1, (val >> 8) & 0xFF)


SENTINEL = 0x0000


def call_routine_counted(z, entry_addr, max_instr=300_000):
    """指定ルーチンを1回CALLし、RETでSENTINELへ戻るまでの命令数を返す。
    フルフレームに埋もれさせず、個々のサブルーチン単体の実行コストを
    直接計測することで、全体命令数では希釈されてしまう局所的なループ
    異常(全体のごく一部を占めるだけの小さいループが256回化する、等)
    にも十分な感度を持たせる。"""
    z.sp = 0xF000
    z.wr(0xF000, SENTINEL & 0xFF)
    z.wr(0xF001, (SENTINEL >> 8) & 0xFF)
    z.pc = entry_addr
    n = 0
    for _ in range(max_instr):
        if z.pc == SENTINEL:
            return n
        z.step()
        n += 1
    raise RuntimeError(f"{entry_addr:04X} did not return within {max_instr} instructions")


ENEMY_POOL = sym["ENEMY_POOL"]; ENEMY_SLOT_COUNT = sym["ENEMY_SLOT_COUNT"]; ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
ENEMY6_POOL = sym["ENEMY6_POOL"]; ENEMY6_SLOTS = sym["ENEMY6_SLOTS"]
ENEMY3_WAVE_POOL = sym["ENEMY3_WAVE_POOL"]; ENEMY3_WAVE_SLOTS = sym["ENEMY3_WAVE_SLOTS"]
ENEMY3_POOL = sym["ENEMY3_POOL"]; ENEMY3_SLOTS = sym["ENEMY3_SLOTS"]; ENEMY3_STRUCT = sym["ENEMY3_STRUCT"]
E2A_ACTIVE = sym["E2A_ACTIVE"]; E2B_ACTIVE = sym["E2B_ACTIVE"]
EBUZ_SLOT0 = sym["EBUZ_SLOT0"]; EBUZ_SLOT1 = sym["EBUZ_SLOT1"]; EBUZ_OFS_ACT = sym["EBUZ_OFS_ACT"]
EBUZ_EXPL_QUEUE_COUNT = sym["EBUZ_EXPL_QUEUE_COUNT"]
EBUZ_EXPL_QUEUE_CAPACITY = sym["EBUZ_EXPL_QUEUE_CAPACITY"]
EBULLET_POOL = sym["EBULLET_POOL"]; EBULLET_SLOTS = sym["EBULLET_SLOTS"]
PLAYER_EXPL_POOL = sym["PLAYER_EXPL_POOL"]; PLAYER_EXPL_SLOTS = sym["PLAYER_EXPL_SLOTS"]; PLAYER_EXPL_STRUCT = sym["PLAYER_EXPL_STRUCT"]
DFL0_ACT = sym["DFL0_ACT"]; DFL1_ACT = sym["DFL1_ACT"]; DFL2_ACT = sym["DFL2_ACT"]
POD_HP = sym["POD_HP"]
POD_VOLLEY_ACTIVE = sym["POD_VOLLEY_ACTIVE"]; POD_LAP_ACTIVE = sym["POD_LAP_ACTIVE"]
BOSS_STATE = sym["BOSS_STATE"]; BOSS_PHASE = sym["BOSS_PHASE"]
CLOUDW_ACTIVE = sym["CLOUDW_ACTIVE"]; CLOUDN_ACTIVE = sym["CLOUDN_ACTIVE"]
GAME_TICK = sym["GAME_TICK"]; SPAWN_NEXT_INDEX = sym["SPAWN_NEXT_INDEX"]
GAME_OVER = sym["GAME_OVER"]; STAGE_CLEAR_ACT = sym["STAGE_CLEAR_ACT"]
PLAYER_FLYAWAY = sym["PLAYER_FLYAWAY"]; PLAYER_RETREAT_ACT = sym["PLAYER_RETREAT_ACT"]
PLAYER_DEATH_FALL_ACT = sym["PLAYER_DEATH_FALL_ACT"]
BULLET0_ACT = sym["BULLET0_ACT"]; BULLET1_ACT = sym["BULLET1_ACT"]; BULLET2_ACT = sym["BULLET2_ACT"]
E2A_U0_TOP = sym["E2A_U0_TOP"]; E2A_U0_BOT = sym["E2A_U0_BOT"]
E2A_U1_TOP = sym["E2A_U1_TOP"]; E2A_U1_BOT = sym["E2A_U1_BOT"]
E2A_U2_TOP = sym["E2A_U2_TOP"]; E2A_U2_BOT = sym["E2A_U2_BOT"]
E2B_U0_TOP = sym["E2B_U0_TOP"]; E2B_U0_BOT = sym["E2B_U0_BOT"]
E2B_U1_TOP = sym["E2B_U1_TOP"]; E2B_U1_BOT = sym["E2B_U1_BOT"]
E2B_U2_TOP = sym["E2B_U2_TOP"]; E2B_U2_BOT = sym["E2B_U2_BOT"]
EBUZ_ST_FIRE = sym["EBUZ_ST_FIRE"]
EBUZ_HP_INIT = sym["EBUZ_HP_INIT"]
EBUZ_EXPL_QUEUE = sym["EBUZ_EXPL_QUEUE"]


def saturate_all_pools(z, boss_state):
    """MAINLOOPから毎フレーム無条件/準無条件に呼ばれる全主要サブシステム
    のプールを可能な限り「全スロット活性」の最悪ケースへ設定する。"""
    # ザコ敵プール群
    for i in range(ENEMY_SLOT_COUNT):
        z.wr(ENEMY_POOL + i * ENEMY_SLOT_SIZE, 1)
    for i in range(ENEMY6_SLOTS):
        z.wr(ENEMY6_POOL + i * 4, 1)
    z.wr(sym["ENEMY6_ACTIVE_COUNT"], ENEMY6_SLOTS)   # CHECK_BULLET_VS_ENEMY6の短絡ガード用
    for i in range(ENEMY3_WAVE_SLOTS):
        z.wr(ENEMY3_WAVE_POOL + i * 4, 1)
    # ENEMY3_POOLの実スキャン幅はENEMY3_WAVE_SLOTS*ENEMY3_SLOTS(64) -
    # CHECK_BULLET_VS_ENEMY3自身のLD B,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTSと同じ。
    enemy3_real_slots = ENEMY3_WAVE_SLOTS * ENEMY3_SLOTS
    for i in range(enemy3_real_slots):
        z.wr(ENEMY3_POOL + i * ENEMY3_STRUCT, 1)
    z.wr(sym["ENEMY3_ACTIVE_COUNT"], enemy3_real_slots & 0xFF)  # CHECK_BULLET_VS_ENEMY3の短絡ガード用
    # Enemy2編隊A/B(3機編隊ずつ、6ユニット)
    z.wr(E2A_ACTIVE, 1)
    z.wr(E2B_ACTIVE, 1)
    for addr in (E2A_U0_TOP, E2A_U0_BOT, E2A_U1_TOP, E2A_U1_BOT, E2A_U2_TOP, E2A_U2_BOT,
                 E2B_U0_TOP, E2B_U0_BOT, E2B_U1_TOP, E2B_U1_BOT, E2B_U2_TOP, E2B_U2_BOT):
        z.wr(addr, 1)
    # Ebuz: 両スロット活性+死亡演出キューを最大まで積む
    z.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, EBUZ_ST_FIRE)
    z.wr(EBUZ_SLOT1 + EBUZ_OFS_ACT, EBUZ_ST_FIRE)
    z.wr(EBUZ_EXPL_QUEUE_COUNT, EBUZ_EXPL_QUEUE_CAPACITY)
    for i in range(EBUZ_EXPL_QUEUE_CAPACITY):
        z.wr(EBUZ_EXPL_QUEUE + i * 2, (i * 8) & 0xFF)
        z.wr(EBUZ_EXPL_QUEUE + i * 2 + 1, (i * 8) & 0xFF)
    # 敵弾
    for i in range(EBULLET_SLOTS):
        z.wr(EBULLET_POOL + i * 4, 1)
    # 自機爆発パーティクル
    for i in range(PLAYER_EXPL_SLOTS):
        z.wr(PLAYER_EXPL_POOL + i * PLAYER_EXPL_STRUCT, 1)
    # 雲
    z.wr(CLOUDW_ACTIVE, 1)
    z.wr(CLOUDN_ACTIVE, 1)
    # 自機弾3発とも飛行中
    z.wr(BULLET0_ACT, 1)
    z.wr(BULLET1_ACT, 1)
    z.wr(BULLET2_ACT, 1)
    # ボス関連(DFL偏向弾3・8機ポッド・ボリー/ラップ)
    z.wr(DFL0_ACT, 1); z.wr(DFL1_ACT, 1); z.wr(DFL2_ACT, 1)
    for i in range(8):
        z.wr(POD_HP + i, 5)
    z.wr(POD_VOLLEY_ACTIVE, 1)
    z.wr(POD_LAP_ACTIVE, 1)
    z.wr(BOSS_STATE, boss_state)
    z.wr(BOSS_PHASE, 1)
    # 通常進行を妨げるフリーズ系フラグは全てクリア
    z.wr(GAME_OVER, 0)
    z.wr(STAGE_CLEAR_ACT, 0)
    z.wr(PLAYER_FLYAWAY, 0)
    z.wr(PLAYER_RETREAT_ACT, 0)
    z.wr(PLAYER_DEATH_FALL_ACT, 0)
    wr16(z, GAME_TICK, 1030)   # CHECK_BOSS_TRIGGERの全プール走査も踏ませる
    wr16(z, SPAWN_NEXT_INDEX, 100)


def run_saturated_frames(boss_state, n_frames=10, mem=None, max_instr_per_frame=200_000):
    z = fresh(mem)
    boot(z)
    saturate_all_pools(z, boss_state)
    counts = []
    for _ in range(n_frames):
        saturate_all_pools(z, boss_state)  # 各フレーム後も状態を維持(消費されても再充填)
        counts.append(step_frame_counted(z, max_instr=max_instr_per_frame))
    return counts


# ============================================================
# 1. 「敵不在」ベースライン(BOSS_STATE=0、全プール空)の実測値を基準に、
#    全プール最大稼働(BOSS_STATE=0/1/2それぞれ)の実測値が異常に
#    (桁違いに)大きくないことを確認する。
# ============================================================
z_idle = fresh(); boot(z_idle)
idle_counts = [step_frame_counted(z_idle) for _ in range(5)]
idle_max = max(idle_counts)
print(f"idle baseline (no enemies): {idle_counts} instructions/frame")

# 妥当な上限: 全サブシステムが正しくDJNZ/カウンタで境界されている限り、
# アイドル時の数十倍程度には収まるはず(このプロジェクトの既存ルーチン
# 規模から見て、桁違い[100倍以上]の増加は明確に異常)。
SANITY_MULTIPLIER = 60

for boss_state, label in ((0, "BOSS_STATE=0(未出現)"), (1, "BOSS_STATE=1(マテリアライズ中)"),
                           (2, "BOSS_STATE=2(戦闘中)")):
    counts = run_saturated_frames(boss_state, n_frames=8)
    mx = max(counts)
    print(f"saturated {label}: {counts} instructions/frame (max={mx}, idle_max={idle_max}, "
          f"ratio={mx/idle_max:.1f}x)")
    check(f"全プール最大稼働({label})でも1フレームの命令数がアイドル時の"
          f"{SANITY_MULTIPLIER}倍を超えない(暴走/意図せぬ多重ループの兆候なし、"
          f"実測 {mx} vs 上限 {idle_max*SANITY_MULTIPLIER})",
          mx <= idle_max * SANITY_MULTIPLIER)
    check(f"全プール最大稼働({label})でも{8}フレーム連続で命令数が"
          f"大きくブレない(フレーム間で不安定な暴走が起きていない、"
          f"最大/最小比 {mx/min(counts):.2f})",
          mx <= min(counts) * 3)  # 通常の状態変化によるブレは3倍以内に収まるはず


# ============================================================
# 2. 自己検証: round135follow-up14で実際に踏んだバグ(CHECK_BOSS_TRIGGERが
#    SCAN_POOL_ACTIVEをENEMY_POOL用→ENEMY6_POOL用と連続CALLする際、Bを
#    再ロードし忘れる)の「ループ回数が不要に膨らむ」という側面を直接
#    再現・計測する。
#    (当初、CHECK_BOSS_TRIGGER全体をbuggy版/fixed版で比較する方式を
#    試したが、Bが0のまま暴走すると256回スキャンする過程で早期に非ゼロ
#    バイトへ行き当たり"活性あり"と誤検出してBOSS_SPAWNへ進まず早期
#    RETする経路のブレに命令数が支配され、"バグがある方が命令数が少ない"
#    という逆転結果になり自己検証として機能しなかった - これ自体、
#    「命令数の単純比較だけでは判定を誤りうる」という重要な教訓。
#    真に確認すべきは「SCAN_POOL_ACTIVE呼び出し前にBが必ず再ロードされて
#    いるか」というループ回数そのものなので、SCAN_POOL_ACTIVE単体を
#    B=0[バグ時の状態]とB=ENEMY6_SLOTS[正しい状態]の両方で、確実に
#    非ゼロバイトに一切遭遇しない安全な全ゼロ領域に対して直接実行し、
#    ループ回数(=命令数)そのものを比較する。)
# ============================================================
SCAN_POOL_ACTIVE = sym["SCAN_POOL_ACTIVE"]

# INIT直後のENEMY6_POOL(32*4=128byte)は全ゼロのはず - ここを土台に、
# Bが0から始まった場合に及ぶ256回分(1024byte)が他の意味のあるRAM値と
# 衝突しない、確実に安全な全ゼロの帯を別途用意する(既存プールの実領域を
# そのまま使うと256回スキャンの過程で無関係な非ゼロ変数に行き当たり、
# 早期RET NZで終わってしまってループ回数の比較にならないため)。
SAFE_ZERO_BASE = 0xC800  # Stage1のRAMマップ上、この範囲がゲーム変数と
                          # 衝突しないことをEQU一覧から確認済み(0xC000台は
                          # このファイルが使わない領域)
z_scan = fresh(); boot(z_scan)
for i in range(1024):
    z_scan.wr(SAFE_ZERO_BASE + i, 0)


def _scan_pool_active_iterations(z, b_value):
    z.h = (SAFE_ZERO_BASE >> 8) & 0xFF
    z.l = SAFE_ZERO_BASE & 0xFF
    z.b = b_value
    z.d = 0
    z.e = 4   # ENEMY6_POOLと同じstride
    return call_routine_counted(z, SCAN_POOL_ACTIVE, max_instr=10_000)


correct_iters = _scan_pool_active_iterations(z_scan, sym["ENEMY6_SLOTS"])   # 正しい呼び出し: B=32
buggy_iters = _scan_pool_active_iterations(z_scan, 0)                        # バグ時の呼び出し: Bが未リロードで0のまま
print(f"自己検証: SCAN_POOL_ACTIVE単体のループ回数相当命令数 - "
      f"正しくB={sym['ENEMY6_SLOTS']}でリロードした場合={correct_iters}、"
      f"round135follow-up14のバグ通りB=0のまま(未リロード)呼んだ場合={buggy_iters}")
check("自己検証: SCAN_POOL_ACTIVEをBの再ロードなしで呼ぶと(DJNZがB=0を"
      "0xFFへラップする性質上)本来の32回ではなく256回分ループし、"
      "命令数が明確に(数倍以上)膨らむ - 本テストの手法が"
      "『不要なループカウント』を実際に検出できることの確認",
      buggy_iters > correct_iters * 5)

check("参考: CHECK_BOSS_TRIGGERの現在のソースは、ENEMY6_POOL用の"
      "SCAN_POOL_ACTIVE呼び出し(=毎回Bの再ロードが必要だった箇所)を"
      "round135follow-up15でO(1)のENEMY6_ACTIVE_COUNTチェックへ置き換え"
      "済みのため、そもそもここでのB未リロード系バグは構造的に発生し"
      "得なくなっている(ENEMY6_ACTIVE_COUNTチェック自体はBを使わない)。"
      "続くENEMY3_WAVE_POOL用SCAN_POOL_ACTIVE呼び出しがBを正しく"
      "再ロードしていることだけを確認する",
      "    LD HL,ENEMY3_WAVE_POOL : LD B,ENEMY3_WAVE_SLOTS : LD DE,4\n" in text)

# ============================================================
# 3. 局所ルーチン単体計測: MAINLOOPから毎フレーム(準)無条件に呼ばれる
#    主要サブシステム個々について、全プール最大稼働状態でも単体命令数が
#    「アイドル時のフル1フレーム分」を超えない(=どれか1つのサブシステム
#    だけが突出して暴走していない)ことを直接計測する。フルフレーム
#    計測(セクション1)だけでは他コストに埋もれる局所異常を、ルーチン
#    単位で計測することで確実に検出できるようにする。
# ============================================================
z_sat = fresh(); boot(z_sat)
saturate_all_pools(z_sat, boss_state=2)  # ボス関連も含め全て稼働させた状態を1回用意

ISOLATED_TARGETS = [
    "ENEMY_POOL_UPDATE_ALL", "ENEMY3_UPDATE_ALL", "ENEMY6_UPDATE_ALL",
    "EBUZ_UPDATE_ALL", "EBUZ_CHECK_CHAIN_TRIGGERS", "EBUZ_EXPL_UPDATE_QUEUE",
    "UPDATE_EBULLET_ALL", "ENEMY5_ANIM_STEP", "CLOUD_UPDATE_ALL",
    "ENEMY_COMPLEX_STEP_A", "ENEMY_COMPLEX_STEP_B",
    "VOLLEY_UPDATE", "POD_FIRE_UPDATE", "POD_COLLISION_UPDATE", "DFL_UPDATE",
    "PLAYER_EXPL_UPDATE_ALL", "CHECK_BOSS_TRIGGER",
]
for name in ISOLATED_TARGETS:
    if name not in sym:
        continue
    # 各呼び出し直前にプール状態を再充填(直前の呼び出しで消費/変化した
    # 可能性があるため、常に「最大稼働」のまま次のルーチンへ渡す)。
    saturate_all_pools(z_sat, boss_state=2)
    z_sat.b, z_sat.c = 15, 10  # CHECK_BULLET_VS_*系が引数を要求する場合に備えた無害な既定値
    try:
        n = call_routine_counted(z_sat, sym[name], max_instr=200_000)
        timed_out = False
    except RuntimeError:
        n = None
        timed_out = True
    print(f"isolated {name}: {n if n is not None else 'DID NOT RETURN'} instructions "
          f"(idle full-frame reference = {idle_max})")
    # ENEMY3_UPDATE_ALLは実スキャン幅がENEMY3_WAVE_SLOTS*ENEMY3_SLOTS(64、
    # 他の32スロット系ルーチンの倍)な上、当たり判定と違い各スロットで実際の
    # 移動/アニメーション処理を行う(ヒットテストだけの他ルーチンより単価が
    # 高い)ため、全64体フル稼働という理論上の最大値では素直にアイドル時の
    # 数倍のコストになる - これ自体はDJNZで正しく境界された正当なコストで
    # あり暴走ではないため、この1ルーチンだけ緩めの上限(アイドル時の3倍)
    # を許容する。
    limit = idle_max * 3 if name == "ENEMY3_UPDATE_ALL" else idle_max
    check(f"{name}を全プール最大稼働状態で単体呼び出ししても、"
          f"想定コスト上限(アイドル時の{'3倍' if limit != idle_max else '1倍'})を超えない"
          "(=突出して暴走しているサブシステムがない)",
          (not timed_out) and n <= limit)

for name in ["CHECK_BULLET_VS_ENEMY_POOL", "CHECK_BULLET_VS_ENEMY3", "CHECK_BULLET_VS_ENEMY6",
             "CHECK_BULLET_VS_EBUZ"]:
    if name not in sym:
        continue
    saturate_all_pools(z_sat, boss_state=2)
    z_sat.b, z_sat.c = 15, 10
    try:
        n = call_routine_counted(z_sat, sym[name], max_instr=200_000)
        timed_out = False
    except RuntimeError:
        n = None
        timed_out = True
    print(f"isolated {name}(B=15,C=10, all-miss scan): "
          f"{n if n is not None else 'DID NOT RETURN'} instructions "
          f"(idle full-frame reference = {idle_max})")
    check(f"{name}(全プール最大稼働・全弾ミスのフルスキャン)も"
          "アイドル時のフル1フレーム分の命令数を超えない",
          (not timed_out) and n <= idle_max)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
