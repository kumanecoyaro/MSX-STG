"""Stage1: 新エネミー"Ebuz"の本編組み込み(2026-09-14)の検証。

tools/ebuz_test/で確立済みの state1(初弾ホールド→発射)→state2(変形)→
継続交互発射という一連の流れ(HANDOFF.md Round114-129)を、
`src/CYBER SHMUP.asm`のMAINLOOPへ実際に組み込んだ結果を検証する。
ユーザー指示: "じゃあ組み込む バグらないように慎重に実装しろ
100Tickでスポーン 位置はY中央で 上から中央まで移動してシーケンス
スタート Ebuz出現中はスケジュールエネミーは一旦停止 生存時間は
15秒 時間になったら右に移動して消える 耐久値12"。

tools/verify_player_damage.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+boot()/step_frame()による実MAINLOOP駆動」の作法に倣う。
プロトタイプ(ebuz_test)と異なり本編は1回のstep_frame()=1実フレーム=
Ebuzの1"ティック"に対応するため、タイミング検証は単純にstep_frame()を
必要回数呼ぶだけで行える(ビジーウェイトが無いため)。

各シナリオは基本的に独立したfresh()インスタンスを使い、EBUZ_ACT/ROW/
COL等を直接pokeしてから検証する(実際のGAME_TICK==100スポーンの瞬間
「その同じフレーム内でEBUZ_UPDATEも1回動いてしまう」という相互作用を
気にせず、各フェーズの遷移条件だけをクリーンに検証するため)。実際の
スポーン経路(GAME_TICK==100トリガー)自体は専用のシナリオで別途
検証する。
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


def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


def run_until(z, predicate, max_frames=3000):
    for i in range(max_frames):
        if predicate(z):
            return i
        step_frame(z)
    raise RuntimeError("predicate never became true")


NAMTBL = 0x1800


def cell(row, col):
    return NAMTBL + row * 32 + col


def vrd(z, addr):
    """VRAM(name table等)を読む - z.rd()はZ80のRAM空間、VRAMは別配列
    z.vram[]に格納されている(z80emu.pyのLDIRVM/WRTVRM実装参照)。"""
    return z.vram[addr & 0x3FFF]


def rd16(z, addr):
    return z.rd(addr) | (z.rd(addr + 1) << 8)


def wr16(z, addr, val):
    z.wr(addr, val & 0xFF)
    z.wr(addr + 1, (val >> 8) & 0xFF)


def game_tick(z):
    return rd16(z, sym["GAME_TICK"])


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    for _ in range(max_instr):
        if z.pc == 0x0000:
            return
        z.step()
    raise RuntimeError("call_routine did not return")


BC = sym["BLANKCODE"]
A_, B_, C_, D_ = sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"], sym["EBUZ_CODE_D"]
BL, BR = sym["EBUZ_BULLET_L_CODE"], sym["EBUZ_BULLET_R_CODE"]

# ============================================================
# 1. RAM初期化漏れ防止(Round36-14 follow#14以来の教訓)
# ============================================================
z = fresh()
poison_lo, poison_hi = sym["EBUZ_ACT"], sym["EBUZ_CUR_ROW_ADDR"] + 2
for a in range(poison_lo, poison_hi):
    z.wr(a, 0xAA)
boot(z)
check("INIT: EBUZ_ACT is 0 (poisoned 0xAA beforehand)",
      z.rd(sym["EBUZ_ACT"]) == 0)
check("INIT: EBUZ_TOP_COLS/BOTTOM_COLS all EBUZ_SLOT_EMPTY(255)",
      all(z.rd(sym["EBUZ_TOP_COLS"] + i) == 255 for i in range(8)) and
      all(z.rd(sym["EBUZ_BOTTOM_COLS"] + i) == 255 for i in range(8)))
check("INIT: EBUZ_TOP_NEXT/BOTTOM_NEXT/CUR_ROW_ADDR all 0",
      z.rd(sym["EBUZ_TOP_NEXT"]) == 0 and z.rd(sym["EBUZ_BOTTOM_NEXT"]) == 0 and
      rd16(z, sym["EBUZ_CUR_ROW_ADDR"]) == 0)
check("INIT: EBUZ_B0_ACTIVE/HOLDING/COL/HOLD_COUNTER all 0",
      z.rd(sym["EBUZ_B0_ACTIVE"]) == 0 and z.rd(sym["EBUZ_B0_HOLDING"]) == 0 and
      z.rd(sym["EBUZ_B0_COL"]) == 0 and z.rd(sym["EBUZ_B0_HOLD_COUNTER"]) == 0)

# ============================================================
# 2. スケジュール凍結: EBUZ_ACT!=0の間、GAME_TICKは一切進まない
# ============================================================
z = fresh()
boot(z)
wr16(z, sym["GAME_TICK"], 500)
wr16(z, sym["SPAWN_NEXT_INDEX"], 0)
z.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
before = game_tick(z)
for _ in range(64):
    step_frame(z)
check("EBUZ_ACT!=0の間、64フレーム進めてもGAME_TICKは完全に凍結",
      game_tick(z) == before)
z.wr(sym["EBUZ_ACT"], 0)
for _ in range(8):
    step_frame(z)
check("EBUZ_ACT=0に戻ればGAME_TICKは凍結していた値から丁度1つ進む"
      "(一気に複数追いつくバーストにはならない設計)",
      game_tick(z) == before + 1)

# (自己検証: このガード自体を一時的に外して、上記2件が正しくFAILする
# ことを確認する - スケジュール凍結という最も重要な新設計のため)
def _regress_no_freeze_check():
    """MAINLOOP中のEBUZ_ACTガード('LD A,(EBUZ_ACT):OR A:JR NZ,...')を
    一時的にNOPへ潰し、"64フレーム進めても凍結"チェックが正しくFAILに
    転じることを確認する自己検証。"""
    # SKIP_SCHEDULE_TICKへの分岐命令(JR NZ,SKIP_SCHEDULE_TICK)の
    # オペコードをNOP+NOPへ差し替え - ガードそのものを無効化する。
    # 分岐命令のアドレスはEBUZ_ACT読み出し直後、シンボルテーブルには
    # 出てこないため、アセンブル済みバイト列中の該当パターンを直接
    # 探して置換する(この回だけの使い捨て自己検証、本ROMは変更しない)。
    broken_mem = bytearray(mem0)
    # LD A,(EBUZ_ACT) = 3A xx xx / OR A = B7 / JR NZ,d = 20 d
    act_lo, act_hi = sym["EBUZ_ACT"] & 0xFF, (sym["EBUZ_ACT"] >> 8) & 0xFF
    pat = bytes([0x3A, act_lo, act_hi, 0xB7, 0x20])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("pattern not found for self-verification")
    broken_mem[idx + 4] = 0x00  # JR NZ,d -> NOP (d byte neutralized... )
    broken_mem[idx + 3] = 0x00  # OR A -> NOP (Zフラグに依存させず常にfall through)
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    wr16(zz, sym["GAME_TICK"], 500)
    zz.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
    b4 = game_tick(zz)
    for _ in range(64):
        step_frame(zz)
    return game_tick(zz) == b4


check("自己検証: スケジュール凍結ガードを無効化すると、上と同じ64フレーム"
      "経過チェックが正しくFAILに転じる(=このガードが実際に効いている"
      "ことの確認)",
      _regress_no_freeze_check() == False)

# ============================================================
# 3. スポーントリガー: GAME_TICK==100の瞬間に一度だけ発火
# ============================================================
z = fresh()
boot(z)
wr16(z, sym["GAME_TICK"], 99)
run_until(z, lambda z: game_tick(z) == 100, max_frames=9)
check("GAME_TICK==100到達の瞬間、EBUZ_ACTがEBUZ_ST_ENTERになる",
      z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_ENTER"])
check("スポーン直後、EBUZ_ROWはEBUZ_ENTER_START_ROW(0)のまま"
      "(同フレーム内でEBUZ_UPDATEも走るが6フレームに1回のカウンタは"
      "まだ閾値に達しない)",
      z.rd(sym["EBUZ_ROW"]) == 0)
check("スポーン直後、EBUZ_COLはEBUZ_SPAWN_COL(24)",
      z.rd(sym["EBUZ_COL"]) == sym["EBUZ_SPAWN_COL"])
check("スポーン直後、EBUZ_HPはEBUZ_HP_INIT(12)",
      z.rd(sym["EBUZ_HP"]) == sym["EBUZ_HP_INIT"])
check("スポーン直後(かつ同フレーム内でEBUZ_UPDATEが1回動いた後)、"
      "EBUZ_LIFE_TIMERはEBUZ_LIFETIME_FRAMES-1(899)",
      rd16(z, sym["EBUZ_LIFE_TIMER"]) == sym["EBUZ_LIFETIME_FRAMES"] - 1)
row0 = [vrd(z, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
row1 = [vrd(z, cell(1, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
expect_abcd = [A_, B_, C_, D_]
check("スポーン直後、row0/row1のcol24-27に本体4タイル(A,B,C,D)が"
      "\"上から登場\"の通り即座に描画される",
      row0 == expect_abcd and row1 == expect_abcd)

# ============================================================
# 4. 降下(ENTER): EBUZ_DESCEND_ROW_FRAMESフレームに1回、中央行まで
#    1行ずつ移動。クリーンな状態(カウンタ0、ROW0)から独立に検証。
# ============================================================
z = fresh()
boot(z)
z.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_ENTER"])
z.wr(sym["EBUZ_ROW"], 0)
z.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z.wr(sym["EBUZ_DESCEND_COUNTER"], 0)
z.wr(sym["EBUZ_HP"], sym["EBUZ_HP_INIT"])
wr16(z, sym["EBUZ_LIFE_TIMER"], sym["EBUZ_LIFETIME_FRAMES"])
for i in range(4):
    z.vram[cell(0, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = expect_abcd[i]
    z.vram[cell(1, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = expect_abcd[i]

DF = sym["EBUZ_DESCEND_ROW_FRAMES"]
for _ in range(DF - 1):
    step_frame(z)
check(f"降下: {DF-1}フレームではまだ1行目へ進まない(ROW=0のまま)",
      z.rd(sym["EBUZ_ROW"]) == 0)
step_frame(z)
check(f"降下: ちょうど{DF}フレーム目で1行進む(ROW=1)",
      z.rd(sym["EBUZ_ROW"]) == 1)
check("降下: 古い行(row0)は消去され、新しい行(row1/row2)にABCDが描画",
      [vrd(z, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == [BC, BC, BC, BC] and
      [vrd(z, cell(1, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == expect_abcd and
      [vrd(z, cell(2, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == expect_abcd)

remaining_rows = sym["EBUZ_CENTER_ROW"] - 1
for _ in range(remaining_rows * DF):
    step_frame(z)
check(f"降下: 合計でEBUZ_CENTER_ROW({sym['EBUZ_CENTER_ROW']})にちょうど到達",
      z.rd(sym["EBUZ_ROW"]) == sym["EBUZ_CENTER_ROW"])
check("中央到達と同時にEBUZ_ST_STATE1へ遷移",
      z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_STATE1"])
check("state1到達時、bullet0がactive+holding、列はEBUZ_BULLET1_COL(22)、"
      "ホールドカウンタはEBUZ_BULLET0_HOLD_TICKS",
      z.rd(sym["EBUZ_B0_ACTIVE"]) == 1 and z.rd(sym["EBUZ_B0_HOLDING"]) == 1 and
      z.rd(sym["EBUZ_B0_COL"]) == sym["EBUZ_BULLET1_COL"] and
      z.rd(sym["EBUZ_B0_HOLD_COUNTER"]) == sym["EBUZ_BULLET0_HOLD_TICKS"])
r9 = sym["EBUZ_CENTER_ROW"]
r10 = r9 + 1
check("state1到達時、bullet0がrow9/row10のcol22-23にBULLET_L/R_CODEで描画",
      [vrd(z, cell(r9, 22)), vrd(z, cell(r9, 23))] == [BL, BR] and
      [vrd(z, cell(r10, 22)), vrd(z, cell(r10, 23))] == [BL, BR])
check("row9/row10のcol24-27は依然として本体4タイル(A,B,C,D)のまま",
      [vrd(z, cell(r9, 24 + i)) for i in range(4)] == expect_abcd and
      [vrd(z, cell(r10, 24 + i)) for i in range(4)] == expect_abcd)

# ============================================================
# 5. state1ホールド: 初弾ホールドを10フレ、直後にstate2へ即遷移
#    (それ以外のウェイトは入れない - ebuz_testと同じ確立済み設計)
# ============================================================
HT = sym["EBUZ_BULLET0_HOLD_TICKS"]
for _ in range(HT - 1):
    step_frame(z)
check(f"ホールド中は{HT-1}フレーム経過してもbullet0はcol22のまま静止",
      z.rd(sym["EBUZ_B0_COL"]) == sym["EBUZ_BULLET1_COL"] and
      z.rd(sym["EBUZ_B0_HOLDING"]) == 1 and
      z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_STATE1"])
step_frame(z)  # ちょうどHT回目
check(f"{HT}フレーム目でホールド解除", z.rd(sym["EBUZ_B0_HOLDING"]) == 0)
check("ホールド解除と同時に(待ちなしで)state2へ即遷移",
      z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_STATE2"])
top_band = [vrd(z, cell(8, 24 + i)) for i in range(5)]
bot_band = [vrd(z, cell(11, 24 + i)) for i in range(5)]
mid9 = [vrd(z, cell(9, 24 + i)) for i in range(4)]
mid10 = [vrd(z, cell(10, 24 + i)) for i in range(4)]
check("state2形成: row8(新設上段)=[空,A,B,C,空]", top_band == [BC, A_, B_, C_, BC])
check("state2形成: row11(新設下段)=[空,A,B,C,空]", bot_band == [BC, A_, B_, C_, BC])
check("state2形成: row9/row10(元の本体行)はA,B,Cが消えDだけ残る",
      mid9 == [BC, BC, BC, D_] and mid10 == [BC, BC, BC, D_])
check("state2形成直後、一斉発射前ホールドカウンタはEBUZ_PREACT_HOLD_TICKS",
      z.rd(sym["EBUZ_PREACT_COUNTER"]) == sym["EBUZ_PREACT_HOLD_TICKS"])

# bullet0自身はstate2形成後も独立して飛び続ける("撃った弾は画面外に
# 消えるまで戻さねえ" - Round125で確立済みの設計をそのまま踏襲)。
b0col_before = z.rd(sym["EBUZ_B0_COL"])
step_frame(z)
check("state2形成後もbullet0は毎フレーム1列ずつ左へ飛び続ける",
      z.rd(sym["EBUZ_B0_COL"]) == b0col_before - 1)

# ============================================================
# 6. state2ホールド(45フレ)→継続交互発射開始
# ============================================================
PT = sym["EBUZ_PREACT_HOLD_TICKS"]
for _ in range(PT - 2):  # 直前に1フレーム分既に消費済み(bullet0確認用)
    step_frame(z)
check(f"一斉発射前ホールド中は{PT-1}フレーム経過してもまだstate2のまま"
      "(発射なし)",
      z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_STATE2"] and
      all(z.rd(sym["EBUZ_TOP_COLS"] + i) == 255 for i in range(8)) and
      all(z.rd(sym["EBUZ_BOTTOM_COLS"] + i) == 255 for i in range(8)))
step_frame(z)  # ちょうどPT回目
check(f"{PT}フレーム目でEBUZ_ST_FIREへ遷移", z.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_FIRE"])

# 継続発射: 2フレーム交代(EBUZ_FIRE_INTERVAL)で上下交互、反動→復帰。
step_frame(z)
check("FIRE突入1フレーム目: 上レーンへ1発発射(TOP_COLSの1スロットが"
      "EBUZ_BULLET1_COLで埋まる)",
      any(z.rd(sym["EBUZ_TOP_COLS"] + i) == sym["EBUZ_BULLET1_COL"] for i in range(8)))
check("発射直後、上翼帯はRECOIL形状[空,空,A,B,C]",
      [vrd(z, cell(8, 24 + i)) for i in range(5)] == [BC, BC, A_, B_, C_])
step_frame(z)
check("発射1フレーム後、上翼帯はREST形状[空,A,B,C,空]に戻る",
      [vrd(z, cell(8, 24 + i)) for i in range(5)] == [BC, A_, B_, C_, BC])
step_frame(z)
check("次の発射(2フレーム後)は下レーンへ(交互発射)",
      any(z.rd(sym["EBUZ_BOTTOM_COLS"] + i) == sym["EBUZ_BULLET1_COL"] for i in range(8)))

# ============================================================
# 7. 生存時間15秒(900フレーム) - 満了で強制EXIT、残存弾は全消去
# ============================================================
z2 = fresh()
boot(z2)
z2.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z2.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z2.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z2.wr(sym["EBUZ_TOP_COLS"], sym["EBUZ_BULLET1_COL"])
z2.wr(sym["EBUZ_BOTTOM_COLS"], sym["EBUZ_BULLET1_COL"])
z2.wr(sym["EBUZ_B0_ACTIVE"], 1)
z2.wr(sym["EBUZ_B0_HOLDING"], 0)
z2.wr(sym["EBUZ_B0_COL"], 10)
z2.wr(sym["EBUZ_FIRE_COUNTDOWN"], 200)  # 発射処理と絡まないよう十分先に
wr16(z2, sym["EBUZ_LIFE_TIMER"], 2)
step_frame(z2)
check("生存時間2->1経過ではまだEXITしない", z2.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_FIRE"])
step_frame(z2)
check("生存時間がちょうど0になった瞬間、EBUZ_ST_EXITへ強制遷移",
      z2.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_EXIT"])
check("EXIT開始時、bullet0・上下レーンの残存弾は全て強制消去される",
      z2.rd(sym["EBUZ_B0_ACTIVE"]) == 0 and
      all(z2.rd(sym["EBUZ_TOP_COLS"] + i) == 255 for i in range(8)) and
      all(z2.rd(sym["EBUZ_BOTTOM_COLS"] + i) == 255 for i in range(8)))

# 自己検証: 生存時間ガード(EBUZ_ACT==EXITならタイマ減算をスキップする
# 分岐)が無ければ、EXIT後もタイマ減算が続き0からアンダーフローしうる。
# EXIT自体がEBUZ_EXIT_COL_MAX到達で自然終了してしまう前に確認できる
# よう、EBUZ_EXIT_COL_FRAMESを一時的に巨大値にして退出移動そのものを
# 足止めしてから確認する(この一時変更はこのzインスタンスだけ)。
z2.wr(sym["EBUZ_EXIT_COUNTER"], 0)
timer_after_exit = rd16(z2, sym["EBUZ_LIFE_TIMER"])
mem_orig = mem0[sym["EBUZ_EXIT_COL_FRAMES"]] if False else None  # (EBUZ_EXIT_COL_FRAMESはEQUでRAMではない、参照不可)
for _ in range(min(20, (sym["EBUZ_EXIT_COL_MAX"] - sym["EBUZ_SPAWN_COL"]) * sym["EBUZ_EXIT_COL_FRAMES"] - 1)):
    step_frame(z2)
check("EXIT中(画面外到達前)は生存時間タイマがこれ以上動かない"
      "(0で固定、アンダーフローしない)",
      rd16(z2, sym["EBUZ_LIFE_TIMER"]) == timer_after_exit == 0 and
      z2.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_EXIT"])

# ============================================================
# 8. EXIT: EBUZ_EXIT_COL_FRAMESフレームに1回、1列ずつ右へ移動し、
#    画面外で完全非活性化(=スケジュール自動再開)。クリーンな状態
#    から独立に検証する(section7の続きだと既にEXITの大半が進んで
#    しまっているため)。
# ============================================================
XF = sym["EBUZ_EXIT_COL_FRAMES"]
z2 = fresh()
boot(z2)
z2.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_EXIT"])
z2.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z2.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z2.wr(sym["EBUZ_EXIT_COUNTER"], 0)
wr16(z2, sym["EBUZ_LIFE_TIMER"], 0)
for i in range(5):
    z2.vram[cell(8, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
    z2.vram[cell(11, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
for i in range(4):
    z2.vram[cell(9, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, BC, BC, D_][i]
    z2.vram[cell(10, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, BC, BC, D_][i]

start_col = z2.rd(sym["EBUZ_COL"])
for _ in range(XF - 1):
    step_frame(z2)
check(f"EXIT: {XF-1}フレームではまだ列は動かない", z2.rd(sym["EBUZ_COL"]) == start_col)
step_frame(z2)
check(f"EXIT: {XF}フレーム目で1列右へ移動", z2.rd(sym["EBUZ_COL"]) == start_col + 1)
check("EXIT移動後、本体の新しい位置(footprint)にREST形状が描画される",
      [vrd(z2, cell(8, start_col + 1 + i)) for i in range(5)] == [BC, A_, B_, C_, BC] and
      [vrd(z2, cell(11, start_col + 1 + i)) for i in range(5)] == [BC, A_, B_, C_, BC])
# 消去→(1列右へ)描画の順で処理するため、footprint幅(5/4)が移動量
# (1列)より広い以上、旧footprintと新footprintは大部分重なる - 重なる
# セルは新footprintの内容が正しく「勝つ」("EXIT移動後、本体の新しい
# 位置にREST形状が描画される"で既に確認済み)。ここでは、新footprintに
# もう含まれなくなった一番左の列(start_col列そのもの)だけが正しく
# 空になっていることを確認する(=消し残しがないことのピンポイント
# 確認、重なる列まで空を期待するのは元々誤り)。
check("EXIT移動後、新footprintに含まれなくなった元の左端列"
      "(start_col列)は正しくBLANKCODEへ消去される(消し残しなし)",
      all(vrd(z2, cell(r, start_col)) == BC for r in (8, 9, 10, 11)))

wr16(z2, sym["GAME_TICK"], 500)
wr16(z2, sym["SPAWN_NEXT_INDEX"], 0)
gt_before = game_tick(z2)
steps_to_offscreen = (sym["EBUZ_EXIT_COL_MAX"] - (start_col + 1)) * XF
for _ in range(steps_to_offscreen):
    step_frame(z2)
check("EXIT完了(EBUZ_EXIT_COL_MAX到達)でEBUZ_ACTが0(完全非活性)に戻る"
      "(翼帯5列幅がname table1行[32列]の右端をラップしない安全な"
      "上限に設定されている)",
      z2.rd(sym["EBUZ_ACT"]) == 0)
check("EXIT完了後、最後に居た列付近のfootprintはBLANKCODE(消し残しなし、"
      "かつ隣接行への書き込み折り返しも無い)",
      all(vrd(z2, cell(r, c)) == BC for r in (8, 9, 10, 11) for c in range(24, 32)))
for _ in range(8):
    step_frame(z2)
check("EBUZ_ACT=0に戻った後は、GAME_TICKが再び進み始める"
      "(スケジュール自動再開)",
      game_tick(z2) == gt_before + 1)

# 自己検証: EBUZ_EXIT_COL_MAXを元の32(修正前の値)に戻すと、COLが28を
# 超えた瞬間、翼帯行(5列幅)の書き込みがcol32を跨いでrow9(次の行)の
# col0へ折り返し、無関係なセンチネル値を上書きしてしまうことを確認
# する(このラウンドで自己発見したバグの再現)。
SENTINEL = 200  # BLANKCODE(48)ともEbuzのどのタイルコードとも重ならない値


def _regress_exit_col_max_wraps_into_next_row():
    broken_mem = bytearray(mem0)
    # "CP EBUZ_EXIT_COL_MAX"のオペランド(即値28、opcode FE 1C)を
    # 修正前の32(FE 20)へ書き換える。
    idx = bytes(broken_mem).find(bytes([0xFE, 28]))
    if idx < 0:
        raise RuntimeError("CP 28 opcode not found for self-verification")
    broken_mem[idx + 1] = 32
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    zz.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_EXIT"])
    zz.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
    zz.wr(sym["EBUZ_COL"], 27)  # 次の1歩(28への移動)でcol+4=32が折り返す位置
    zz.wr(sym["EBUZ_EXIT_COUNTER"], 0)
    wr16(zz, sym["EBUZ_LIFE_TIMER"], 0)
    zz.vram[cell(9, 0) & 0x3FFF] = SENTINEL  # row9,col0 = 折り返し先セル
    for _ in range(XF):
        step_frame(zz)
    return vrd(zz, cell(9, 0)) == SENTINEL  # 折り返しが無ければ無事なはず


check("自己検証: EBUZ_EXIT_COL_MAXを32(修正前の値)に戻すと、COL=28への"
      "移動時に翼帯行(5列幅)の書き込みがcol32を跨いでrow9,col0を"
      "破壊する(=このラウンドで自己発見したバグ) - 現在の28では"
      "発生しないことの対比確認",
      _regress_exit_col_max_wraps_into_next_row() == False)

# ============================================================
# 9. 衝突: 自機弾がEbuzに当たるとHPが減り、0で撃破(爆発+スコア+
#    全消去、耐久値12)
# ============================================================
z3 = fresh()
boot(z3)
z3.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z3.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z3.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z3.wr(sym["EBUZ_HP"], sym["EBUZ_HP_INIT"])
for i in range(5):
    z3.vram[cell(8, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
    z3.vram[cell(11, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
score0 = rd16(z3, sym["SCORE"])


def hit_ebuz(z, col, row):
    z.b = col
    z.c = row
    call_routine(z, sym["CHECK_BULLET_VS_EBUZ"])
    return z.a


check("耐久値12: 中心セル(row9,col25)への1発目はHPを11に減らし、"
      "まだ生存(A=1,消費されるが破壊はしない)",
      hit_ebuz(z3, 25, 9) == 1 and z3.rd(sym["EBUZ_HP"]) == sym["EBUZ_HP_INIT"] - 1)
for _ in range(sym["EBUZ_HP_INIT"] - 2):
    hit_ebuz(z3, 25, 9)
check(f"{sym['EBUZ_HP_INIT']-1}発目まででHPは1、まだ生存中",
      z3.rd(sym["EBUZ_HP"]) == 1 and z3.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_FIRE"])
last_hit = hit_ebuz(z3, 25, 9)
check(f"耐久値ちょうど{sym['EBUZ_HP_INIT']}発目でHPが0になり撃破 - "
      "EBUZ_ACTが0に戻る(完全消去+スケジュール再開)",
      last_hit == 1 and z3.rd(sym["EBUZ_ACT"]) == 0)
check("撃破でスコアが加算される(ADD_SCORE_500)", rd16(z3, sym["SCORE"]) > score0)
check("撃破後、本体の4行footprintはBLANKCODEへ消去されている(ただし"
      "命中セルrow9,col25だけはTRIGGER_EXPLOSIONの爆発アニメ1コマ目が"
      "上書きしている - ENEMY6等の既存の撃破シーケンス"
      "[消去→TRIGGER_EXPLOSION]と同じ順序・同じ挙動)",
      all(vrd(z3, cell(r, 24 + i)) == BC for r in (8, 11) for i in range(5)) and
      all(vrd(z3, cell(r, 24 + i)) == BC for r in (9, 10) for i in range(4)
          if (r, 24 + i) != (9, 25)) and
      vrd(z3, cell(9, 25)) != BC)

# 列/行が外れていれば当たらないことも確認(誤検出防止)。
z4 = fresh()
boot(z4)
z4.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z4.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z4.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z4.wr(sym["EBUZ_HP"], sym["EBUZ_HP_INIT"])
check("本体の列範囲(24-27)より1列左(23)は外れ判定",
      hit_ebuz(z4, 23, 9) == 0 and z4.rd(sym["EBUZ_HP"]) == sym["EBUZ_HP_INIT"])
check("本体の行範囲(state2は8-11)より1行下(12)は外れ判定",
      hit_ebuz(z4, 25, 12) == 0 and z4.rd(sym["EBUZ_HP"]) == sym["EBUZ_HP_INIT"])
z4.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_STATE1"])
check("state1(2行のみ、span2)の間は、state2の翼帯行(8)にはまだ本体が"
      "無いので外れ判定",
      hit_ebuz(z4, 25, 8) == 0 and z4.rd(sym["EBUZ_HP"]) == sym["EBUZ_HP_INIT"])

# B,Cが呼び出し元(CHECK_BULLET_VS_ENEMY_POOLがそのまま使う設計)に
# 対して破壊されないことを直接確認 - 既存の3箇所の弾ディスパッチ
# チェーンが依存している契約(CHECK_BULLET_VS_ENEMY6と同じ)。
z5 = fresh()
boot(z5)
z5.wr(sym["EBUZ_ACT"], 0)  # 非活性(即MISSで抜ける経路)でもB,Cは不変のはず
z5.b, z5.c = 0x11, 0x22
call_routine(z5, sym["CHECK_BULLET_VS_EBUZ"])
check("EBUZ非活性時(即MISS)でもB,Cレジスタは呼び出し元のため保持される",
      z5.b == 0x11 and z5.c == 0x22)
z5b = fresh()
boot(z5b)
z5b.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z5b.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z5b.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z5b.wr(sym["EBUZ_HP"], sym["EBUZ_HP_INIT"])
z5b.b, z5b.c = 25, 9  # 実際にヒットするB,C
call_routine(z5b, sym["CHECK_BULLET_VS_EBUZ"])
check("EBUZがヒットを検出した場合でもB,C(col,row)は変更されない",
      z5b.b == 25 and z5b.c == 9)

# 自己検証: HP減算そのものを一時的に無効化する(EBUZ_HITのDEC Aを
# INC Aへ差し替え)と、"12発目で撃破"チェックが正しくFAILに転じる
# ことを確認する。
def _regress_no_hp_decrement():
    broken_mem = bytearray(mem0)
    hp_lo, hp_hi = sym["EBUZ_HP"] & 0xFF, (sym["EBUZ_HP"] >> 8) & 0xFF
    # LD A,(EBUZ_HP)=3A ll hh / DEC A=3D / LD (EBUZ_HP),A=32 ll hh
    pat = bytes([0x3A, hp_lo, hp_hi, 0x3D, 0x32, hp_lo, hp_hi])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("pattern not found for self-verification")
    broken_mem[idx + 3] = 0x00  # DEC A -> NOP(HPが一切減らなくなる)
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    zz.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
    zz.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
    zz.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
    zz.wr(sym["EBUZ_HP"], sym["EBUZ_HP_INIT"])
    zz.b, zz.c = 25, 9
    for _ in range(sym["EBUZ_HP_INIT"]):
        call_routine(zz, sym["CHECK_BULLET_VS_EBUZ"])
    return zz.rd(sym["EBUZ_ACT"]) == 0


check("自己検証: HP減算命令を無効化すると、12発当てても撃破に至らず"
      "EBUZ_ACTが0にならない(=正しい実装ではHPが実際に効いていることの"
      "確認)",
      _regress_no_hp_decrement() == False)

# ============================================================
# 10. 衝突: Ebuz本体・弾との接触で自機がダメージを受ける
#     (PDC_CHECK_EBUZ、既存のPDC_CHECK_*群と同じ「相手は無傷」設計)
# ============================================================
def pdc_check_ebuz(z):
    call_routine(z, sym["PDC_CHECK_EBUZ"])
    return z.a


z6 = fresh()
boot(z6)
z6.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z6.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z6.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
# 本体(state2、row8-11、col24-27、pixel: X=192-223,Y=64-95)の中心に自機を重ねる。
z6.wr(sym["PLAYERX"], 200)
z6.wr(sym["PLAYERY"], 72)
check("自機が本体(state2、32x32)に重なると接触検出", pdc_check_ebuz(z6) == 1)
check("PDC_CHECK_EBUZは相手(Ebuz)にダメージを与えない(HPフィールド"
      "自体を持たないPDC経路、CHECK_BULLET_VS_EBUZとは独立)",
      z6.rd(sym["EBUZ_ACT"]) == sym["EBUZ_ST_FIRE"])
z6.wr(sym["PLAYERX"], 0)
z6.wr(sym["PLAYERY"], 0)
check("自機が本体から大きく離れていれば接触なし", pdc_check_ebuz(z6) == 0)

z7 = fresh()
boot(z7)
z7.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z7.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z7.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z7.wr(sym["EBUZ_B0_ACTIVE"], 1)
z7.wr(sym["EBUZ_B0_COL"], 10)
z7.wr(sym["PLAYERX"], 80)
z7.wr(sym["PLAYERY"], 72)
check("自機がbullet0(row9-10,col10、16x16)に重なると接触検出",
      pdc_check_ebuz(z7) == 1)

z8 = fresh()
boot(z8)
z8.wr(sym["EBUZ_ACT"], sym["EBUZ_ST_FIRE"])
z8.wr(sym["EBUZ_ROW"], sym["EBUZ_CENTER_ROW"])
z8.wr(sym["EBUZ_COL"], sym["EBUZ_SPAWN_COL"])
z8.wr(sym["EBUZ_TOP_COLS"], 5)
z8.wr(sym["PLAYERX"], 40)
z8.wr(sym["PLAYERY"], sym["EBUZ_TOPBAND_ROW"] * 8)
check("自機が上レーン弾(row8,col5)に重なると接触検出", pdc_check_ebuz(z8) == 1)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
