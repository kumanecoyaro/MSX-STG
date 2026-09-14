"""Stage1: 新エネミー"Ebuz"の本編組み込み(2026-09-14 Round130)+
マルチインスタンス化follow-up(同日)の検証。

follow-upでのユーザー指示: "まず スポーンでRow0のブラックの行を破壊してる
Rowは避けRow1から描画するように 耐久値24に 次に2体目 スポーンは1体目が
消えたら 撤退するか倒されるか スポーン位置2体目がRow12 3体目Row5
3体目は2体目が連射したくらいのタイミング 爆発エフェクトはEbuzセル毎に
1回 8セルだから8回エフェクトとサウンド 自機爆発のサウンドとスプライト
を流用"。

Round130の単一インスタンス設計(EBUZ_ACT/EBUZ_ROW等のフラットなEQU)を、
IX相対の2スロット構造体(EBUZ_SLOT0/EBUZ_SLOT1、フィールドはEBUZ_OFS_*
オフセット)へ全面再設計した。1体目・2体目は同じSLOT0を使い回す
(1体目が完全に消えてから2体目が湧くため同時生存しない)、3体目は
SLOT1(2体目とは同時生存しうる)。

tools/verify_player_damage.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+boot()/step_frame()による実MAINLOOP駆動」の作法に倣う。
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
    z.pc = sym["MAINLOOP"]
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
    """呼び出し前後でスタックポインタが一致することも検証する(このRound
    で「call_routine後にz.pcが宙に浮いたまま次のstep_frameを呼ぶと
    address0から実行が始まってしまう」というテストハーネス側の罠を
    自己発見したため、以後は必ずこのヘルパー経由でPCも明示的に戻す)。"""
    sp_before = z.sp
    z.push(0x0000)
    z.pc = entry_addr
    for _ in range(max_instr):
        if z.pc == 0x0000:
            if z.sp != sp_before:
                raise RuntimeError(f"stack imbalance after call: {sp_before:04X}->{z.sp:04X}")
            z.pc = sym["MAINLOOP"]  # PCを宙に浮かせない(0のまま次のstep_frameに入らない)
            return
        z.step()
    raise RuntimeError("call_routine did not return")


def sa(base, field):
    """スロット先頭base + EBUZ_OFS_<field>の絶対アドレス。"""
    return base + sym[f"EBUZ_OFS_{field}"]


def swr(z, base, field, val):
    z.wr(sa(base, field), val)


def srd(z, base, field):
    return z.rd(sa(base, field))


def swr16(z, base, field, val):
    wr16(z, sa(base, field), val)


def srd16(z, base, field):
    return rd16(z, sa(base, field))


S0 = sym["EBUZ_SLOT0"]
S1 = sym["EBUZ_SLOT1"]
BC = sym["BLANKCODE"]
A_, B_, C_, D_ = sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"], sym["EBUZ_CODE_D"]
BL, BR = sym["EBUZ_BULLET_L_CODE"], sym["EBUZ_BULLET_R_CODE"]
ABCD = [A_, B_, C_, D_]

# ============================================================
# 1. RAM初期化漏れ防止(Round36-14 follow#14以来の教訓) - 新設計の
#    グローバルスクラッチ+両スロットを横断的にpoison→INITでゼロ/番兵化
# ============================================================
z = fresh()
poison_lo = sym["EBUZ_CUR_ROW_ADDR"]
poison_hi = S1 + sym["EBUZ_SLOT_SIZE"]
for a in range(poison_lo, poison_hi):
    z.wr(a, 0xAA)
boot(z)
check("INIT: EBUZ_SPAWN_STAGEは0(未スポーン、poison後もゼロ化)",
      z.rd(sym["EBUZ_SPAWN_STAGE"]) == 0)
check("INIT: EBUZ_EXPL_QUEUE_COUNT/CHAIN_TIMER/SPAWN_TIMERは全て0",
      z.rd(sym["EBUZ_EXPL_QUEUE_COUNT"]) == 0 and
      z.rd(sym["EBUZ_CHAIN_TIMER"]) == 0 and
      z.rd(sym["EBUZ_CHAIN_TIMER"] + 1) == 0 and
      z.rd(sym["EBUZ_EXPL_SPAWN_TIMER"]) == 0)
for slot, name in ((S0, "SLOT0"), (S1, "SLOT1")):
    check(f"INIT: {name}.ACTは0",
          srd(z, slot, "ACT") == 0)
    check(f"INIT: {name}のTOP_COLS/BOTTOM_COLSは全てEBUZ_SLOT_EMPTY(255)",
          all(z.rd(sa(slot, "TOP_COLS") + i) == 255 for i in range(8)) and
          all(z.rd(sa(slot, "BOTTOM_COLS") + i) == 255 for i in range(8)))
    check(f"INIT: {name}のTOP_NEXT/BOTTOM_NEXT/CENTER_ROWは全て0",
          srd(z, slot, "TOP_NEXT") == 0 and srd(z, slot, "BOTTOM_NEXT") == 0 and
          srd(z, slot, "CENTER_ROW") == 0)
    check(f"INIT: {name}のB0_ACTIVE/HOLDING/COL/HOLD_COUNTERは全て0",
          srd(z, slot, "B0_ACTIVE") == 0 and srd(z, slot, "B0_HOLDING") == 0 and
          srd(z, slot, "B0_COL") == 0 and srd(z, slot, "B0_HOLD_COUNTER") == 0)

# ============================================================
# 2. スポーントリガー: EBUZ_SPAWN_CHAIN_STARTを呼んだ瞬間に1体目が
#    SLOT0へ、中央行EBUZ_ROW_INST1(9)でスポーンする
#    (round135follow-up5、"ハードコードしたEbuzスケジュールは削除
#    しといて 意図と違ってるんで": 旧来のGAME_TICK==100固定トリガー+
#    「Ebuz出現中はGAME_TICK凍結」機構は全面撤去済み。このテストも
#    直接EBUZ_SPAWN_CHAIN_STARTをcall_routine()する形に変更、GAME_TICK
#    は一切関与しない)。
# ============================================================
z = fresh()
boot(z)
row0_before_spawn = [vrd(z, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
call_routine(z, sym["EBUZ_SPAWN_CHAIN_START"])
check("EBUZ_SPAWN_CHAIN_START呼び出し直後、EBUZ_SPAWN_STAGEが1になる",
      z.rd(sym["EBUZ_SPAWN_STAGE"]) == 1)
check("EBUZ_SPAWN_CHAIN_START呼び出し直後、SLOT0.ACTがEBUZ_ST_ENTERになる",
      srd(z, S0, "ACT") == sym["EBUZ_ST_ENTER"])
check("SLOT1はまだ完全に非活性のまま",
      srd(z, S1, "ACT") == 0)
check("(2026-09-14 follow-up、'Row0のブラックの行を破壊してる Rowは"
      "避けRow1から描画するように'): スポーン直後、SLOT0.ROWは"
      "EBUZ_ENTER_START_ROW(1、0ではない)",
      srd(z, S0, "ROW") == 1 and sym["EBUZ_ENTER_START_ROW"] == 1)
check("スポーン直後、SLOT0.COLはEBUZ_SPAWN_COL(24)",
      srd(z, S0, "COL") == sym["EBUZ_SPAWN_COL"])
check("(2026-09-14 follow-up、'耐久値24に'): スポーン直後、SLOT0.HPは"
      "EBUZ_HP_INIT(24、12ではない)",
      srd(z, S0, "HP") == sym["EBUZ_HP_INIT"] == 24)
check("スポーン直後、SLOT0.CENTER_ROWはEBUZ_ROW_INST1(9)",
      srd(z, S0, "CENTER_ROW") == sym["EBUZ_ROW_INST1"] == 9)
check("スポーン直後(まだEBUZ_UPDATE_ONEは一度も動いていない)、"
      "SLOT0.LIFE_TIMERはEBUZ_LIFETIME_FRAMESそのまま",
      srd16(z, S0, "LIFE_TIMER") == sym["EBUZ_LIFETIME_FRAMES"])
row0 = [vrd(z, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
row1 = [vrd(z, cell(1, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
check("(row0破壊回避の直接確認) スポーン直後、row0のcol24-27はスポーン前"
      "から一切変化していない(HUD/スコア行を破壊しない、INIT自体が"
      "row0に何か描いていても構わないので'0のはず'ではなく'不変のはず'"
      "を検証する)",
      row0 == row0_before_spawn)
check("スポーン直後、row1のcol24-27に本体4タイル(A,B,C,D)が描画される"
      "(\"上から登場\"だがrow1から)",
      row1 == ABCD)

# ============================================================
# 3. 降下(ENTER): EBUZ_DESCEND_ROW_FRAMESフレームに1回、中央行まで
#    1行ずつ移動。クリーンな状態(SLOT0、カウンタ0、ROW=1)から独立に検証。
# ============================================================
z = fresh()
boot(z)
swr(z, S0, "ACT", sym["EBUZ_ST_ENTER"])
swr(z, S0, "ROW", 1)
swr(z, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z, S0, "DESCEND_COUNTER", 0)
swr(z, S0, "HP", sym["EBUZ_HP_INIT"])
swr16(z, S0, "LIFE_TIMER", sym["EBUZ_LIFETIME_FRAMES"])
for i in range(4):
    z.vram[cell(1, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = ABCD[i]
    z.vram[cell(2, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = ABCD[i]

DF = sym["EBUZ_DESCEND_ROW_FRAMES"]
for _ in range(DF - 1):
    step_frame(z)
check(f"降下: {DF-1}フレームではまだ次の行へ進まない(ROW=1のまま)",
      srd(z, S0, "ROW") == 1)
step_frame(z)
check(f"降下: ちょうど{DF}フレーム目で1行進む(ROW=2)",
      srd(z, S0, "ROW") == 2)
check("降下: 古い行(row1)は消去され、新しい行(row2/row3)にABCDが描画",
      [vrd(z, cell(1, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == [BC, BC, BC, BC] and
      [vrd(z, cell(2, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == ABCD and
      [vrd(z, cell(3, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == ABCD)

remaining_rows = sym["EBUZ_ROW_INST1"] - 2
for _ in range(remaining_rows * DF):
    step_frame(z)
check(f"降下: 合計でCENTER_ROW({sym['EBUZ_ROW_INST1']})にちょうど到達",
      srd(z, S0, "ROW") == sym["EBUZ_ROW_INST1"])
check("中央到達と同時にEBUZ_ST_STATE1へ遷移",
      srd(z, S0, "ACT") == sym["EBUZ_ST_STATE1"])
check("state1到達時、bullet0がactive+holding、列はEBUZ_BULLET1_COL(22)、"
      "ホールドカウンタはEBUZ_BULLET0_HOLD_TICKS",
      srd(z, S0, "B0_ACTIVE") == 1 and srd(z, S0, "B0_HOLDING") == 1 and
      srd(z, S0, "B0_COL") == sym["EBUZ_BULLET1_COL"] and
      srd(z, S0, "B0_HOLD_COUNTER") == sym["EBUZ_BULLET0_HOLD_TICKS"])
r9 = sym["EBUZ_ROW_INST1"]
r10 = r9 + 1
check("state1到達時、bullet0がrow9/row10のcol22-23にBULLET_L/R_CODEで描画",
      [vrd(z, cell(r9, 22)), vrd(z, cell(r9, 23))] == [BL, BR] and
      [vrd(z, cell(r10, 22)), vrd(z, cell(r10, 23))] == [BL, BR])
check("row9/row10のcol24-27は依然として本体4タイル(A,B,C,D)のまま",
      [vrd(z, cell(r9, 24 + i)) for i in range(4)] == ABCD and
      [vrd(z, cell(r10, 24 + i)) for i in range(4)] == ABCD)

# ============================================================
# 4. state1ホールド: 初弾ホールドを10フレ、直後にstate2へ即遷移
# ============================================================
HT = sym["EBUZ_BULLET0_HOLD_TICKS"]
for _ in range(HT - 1):
    step_frame(z)
check(f"ホールド中は{HT-1}フレーム経過してもbullet0はcol22のまま静止",
      srd(z, S0, "B0_COL") == sym["EBUZ_BULLET1_COL"] and
      srd(z, S0, "B0_HOLDING") == 1 and
      srd(z, S0, "ACT") == sym["EBUZ_ST_STATE1"])
step_frame(z)  # ちょうどHT回目
check(f"{HT}フレーム目でホールド解除", srd(z, S0, "B0_HOLDING") == 0)
check("ホールド解除と同時に(待ちなしで)state2へ即遷移",
      srd(z, S0, "ACT") == sym["EBUZ_ST_STATE2"])
top_band = [vrd(z, cell(8, 24 + i)) for i in range(5)]
bot_band = [vrd(z, cell(11, 24 + i)) for i in range(5)]
mid9 = [vrd(z, cell(9, 24 + i)) for i in range(4)]
mid10 = [vrd(z, cell(10, 24 + i)) for i in range(4)]
check("state2形成: row8(新設上段)=[空,A,B,C,空]", top_band == [BC, A_, B_, C_, BC])
check("state2形成: row11(新設下段)=[空,A,B,C,空]", bot_band == [BC, A_, B_, C_, BC])
check("state2形成: row9/row10(元の本体行)はA,B,Cが消えDだけ残る",
      mid9 == [BC, BC, BC, D_] and mid10 == [BC, BC, BC, D_])
check("state2形成直後、一斉発射前ホールドカウンタはEBUZ_PREACT_HOLD_TICKS",
      srd(z, S0, "PREACT_COUNTER") == sym["EBUZ_PREACT_HOLD_TICKS"])

b0col_before = srd(z, S0, "B0_COL")
step_frame(z)
check("state2形成後もbullet0は毎フレーム1列ずつ左へ飛び続ける",
      srd(z, S0, "B0_COL") == b0col_before - 1)

# ============================================================
# 5. state2ホールド(45フレ)→継続交互発射開始
# ============================================================
PT = sym["EBUZ_PREACT_HOLD_TICKS"]
for _ in range(PT - 2):
    step_frame(z)
check(f"一斉発射前ホールド中は{PT-1}フレーム経過してもまだstate2のまま"
      "(発射なし)",
      srd(z, S0, "ACT") == sym["EBUZ_ST_STATE2"] and
      all(z.rd(sa(S0, "TOP_COLS") + i) == 255 for i in range(8)) and
      all(z.rd(sa(S0, "BOTTOM_COLS") + i) == 255 for i in range(8)))
step_frame(z)
check(f"{PT}フレーム目でEBUZ_ST_FIREへ遷移", srd(z, S0, "ACT") == sym["EBUZ_ST_FIRE"])

step_frame(z)
check("FIRE突入1フレーム目: 上レーンへ1発発射",
      any(z.rd(sa(S0, "TOP_COLS") + i) == sym["EBUZ_BULLET1_COL"] for i in range(8)))
check("発射直後、上翼帯はRECOIL形状[空,空,A,B,C]",
      [vrd(z, cell(8, 24 + i)) for i in range(5)] == [BC, BC, A_, B_, C_])
step_frame(z)
check("発射1フレーム後、上翼帯はREST形状[空,A,B,C,空]に戻る",
      [vrd(z, cell(8, 24 + i)) for i in range(5)] == [BC, A_, B_, C_, BC])
step_frame(z)
check("次の発射(2フレーム後)は下レーンへ(交互発射)",
      any(z.rd(sa(S0, "BOTTOM_COLS") + i) == sym["EBUZ_BULLET1_COL"] for i in range(8)))

# ============================================================
# 6. 生存時間(EBUZ_LIFETIME_FRAMES) - 満了で強制EXIT、残存弾は全消去
# ============================================================
z2 = fresh()
boot(z2)
swr(z2, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z2, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z2, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z2, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z2, S0, "TOP_COLS", sym["EBUZ_BULLET1_COL"])
swr(z2, S0, "BOTTOM_COLS", sym["EBUZ_BULLET1_COL"])
swr(z2, S0, "B0_ACTIVE", 1)
swr(z2, S0, "B0_HOLDING", 0)
swr(z2, S0, "B0_COL", 10)
swr(z2, S0, "FIRE_COUNTDOWN", 200)
swr16(z2, S0, "LIFE_TIMER", 2)
step_frame(z2)
check("生存時間2->1経過ではまだEXITしない", srd(z2, S0, "ACT") == sym["EBUZ_ST_FIRE"])
step_frame(z2)
check("生存時間がちょうど0になった瞬間、EBUZ_ST_EXITへ強制遷移",
      srd(z2, S0, "ACT") == sym["EBUZ_ST_EXIT"])
check("EXIT開始時、bullet0・上下レーンの残存弾は全て強制消去される",
      srd(z2, S0, "B0_ACTIVE") == 0 and
      all(z2.rd(sa(S0, "TOP_COLS") + i) == 255 for i in range(8)) and
      all(z2.rd(sa(S0, "BOTTOM_COLS") + i) == 255 for i in range(8)))

swr(z2, S0, "EXIT_COUNTER", 0)
timer_after_exit = srd16(z2, S0, "LIFE_TIMER")
for _ in range(min(20, (sym["EBUZ_EXIT_COL_MAX"] - sym["EBUZ_SPAWN_COL"]) * sym["EBUZ_EXIT_COL_FRAMES"] - 1)):
    step_frame(z2)
check("EXIT中(画面外到達前)は生存時間タイマがこれ以上動かない"
      "(0で固定、アンダーフローしない)",
      srd16(z2, S0, "LIFE_TIMER") == timer_after_exit == 0 and
      srd(z2, S0, "ACT") == sym["EBUZ_ST_EXIT"])

# ============================================================
# 7. EXIT: EBUZ_EXIT_COL_FRAMESフレームに1回、1列ずつ右へ移動し、
#    画面外で完全非活性化。クリーンな状態から独立に検証する。
# ============================================================
XF = sym["EBUZ_EXIT_COL_FRAMES"]
z2 = fresh()
boot(z2)
swr(z2, S0, "ACT", sym["EBUZ_ST_EXIT"])
swr(z2, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z2, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z2, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z2, S0, "EXIT_COUNTER", 0)
swr16(z2, S0, "LIFE_TIMER", 0)
for i in range(5):
    z2.vram[cell(8, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
    z2.vram[cell(11, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
for i in range(4):
    z2.vram[cell(9, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, BC, BC, D_][i]
    z2.vram[cell(10, sym["EBUZ_SPAWN_COL"] + i) & 0x3FFF] = [BC, BC, BC, D_][i]

start_col = srd(z2, S0, "COL")
for _ in range(XF - 1):
    step_frame(z2)
check(f"EXIT: {XF-1}フレームではまだ列は動かない", srd(z2, S0, "COL") == start_col)
step_frame(z2)
check(f"EXIT: {XF}フレーム目で1列右へ移動", srd(z2, S0, "COL") == start_col + 1)
check("EXIT移動後、本体の新しい位置(footprint)にREST形状が描画される",
      [vrd(z2, cell(8, start_col + 1 + i)) for i in range(5)] == [BC, A_, B_, C_, BC] and
      [vrd(z2, cell(11, start_col + 1 + i)) for i in range(5)] == [BC, A_, B_, C_, BC])
check("EXIT移動後、新footprintに含まれなくなった元の左端列"
      "(start_col列)は正しくBLANKCODEへ消去される(消し残しなし)",
      all(vrd(z2, cell(r, start_col)) == BC for r in (8, 9, 10, 11)))

wr16(z2, sym["GAME_TICK"], 500)
wr16(z2, sym["SPAWN_NEXT_INDEX"], 0)
steps_to_offscreen = (sym["EBUZ_EXIT_COL_MAX"] - (start_col + 1)) * XF
for _ in range(steps_to_offscreen):
    step_frame(z2)
check("EXIT完了(EBUZ_EXIT_COL_MAX到達)でSLOT0.ACTが0(完全非活性)に戻る",
      srd(z2, S0, "ACT") == 0)
check("EXIT完了後、最後に居た列付近のfootprintはBLANKCODE(消し残しなし、"
      "かつ隣接行への書き込み折り返しも無い)",
      all(vrd(z2, cell(r, c)) == BC for r in (8, 9, 10, 11) for c in range(24, 32)))

SENTINEL = 200


def _regress_exit_col_max_wraps_into_next_row():
    broken_mem = bytearray(mem0)
    idx = bytes(broken_mem).find(bytes([0xFE, 28]))
    if idx < 0:
        raise RuntimeError("CP 28 opcode not found for self-verification")
    broken_mem[idx + 1] = 32
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    zz.wr(sa(S0, "ACT"), sym["EBUZ_ST_EXIT"])
    zz.wr(sa(S0, "ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "COL"), 27)
    zz.wr(sa(S0, "CENTER_ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "EXIT_COUNTER"), 0)
    wr16(zz, sa(S0, "LIFE_TIMER"), 0)
    zz.vram[cell(9, 0) & 0x3FFF] = SENTINEL
    for _ in range(XF):
        zz.pc = sym["MAINLOOP"]; zz.step(); run_until_pc(zz, sym["MAINLOOP"])
    return vrd(zz, cell(9, 0)) == SENTINEL


check("自己検証: EBUZ_EXIT_COL_MAXを32(修正前の値)に戻すと、COL=28への"
      "移動時に翼帯行(5列幅)の書き込みがcol32を跨いでrow9,col0を"
      "破壊する - 現在の28では発生しないことの対比確認",
      _regress_exit_col_max_wraps_into_next_row() == False)

# ============================================================
# 8. 衝突: 自機弾がEbuzに当たるとHPが減り、0で撃破
#    (爆発キュー投入+スコア+全消去、耐久値24)
# ============================================================
z3 = fresh()
boot(z3)
swr(z3, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z3, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z3, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z3, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z3, S0, "HP", sym["EBUZ_HP_INIT"])
for i in range(5):
    z3.vram[cell(8, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
    z3.vram[cell(11, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
score0 = rd16(z3, sym["SCORE"])


def hit_ebuz(z, col, row):
    z.b = col
    z.c = row
    call_routine(z, sym["CHECK_BULLET_VS_EBUZ"])
    return z.a


check(f"耐久値{sym['EBUZ_HP_INIT']}: 中心セル(row9,col25)への1発目はHPを"
      f"{sym['EBUZ_HP_INIT']-1}に減らし、まだ生存(A=1,消費されるが破壊は"
      "しない)",
      hit_ebuz(z3, 25, 9) == 1 and srd(z3, S0, "HP") == sym["EBUZ_HP_INIT"] - 1)
for _ in range(sym["EBUZ_HP_INIT"] - 2):
    hit_ebuz(z3, 25, 9)
check(f"{sym['EBUZ_HP_INIT']-1}発目まででHPは1、まだ生存中",
      srd(z3, S0, "HP") == 1 and srd(z3, S0, "ACT") == sym["EBUZ_ST_FIRE"])
check("撃破前、EBUZ_EXPL_QUEUE_COUNTはまだ0", z3.rd(sym["EBUZ_EXPL_QUEUE_COUNT"]) == 0)
last_hit = hit_ebuz(z3, 25, 9)
check(f"耐久値ちょうど{sym['EBUZ_HP_INIT']}発目でHPが0になり撃破 - "
      "SLOT0.ACTが0に戻る(完全消去+スケジュール再開)",
      last_hit == 1 and srd(z3, S0, "ACT") == 0)
check("撃破でスコアが加算される(ADD_SCORE_500)", rd16(z3, sym["SCORE"]) > score0)
check("(2026-09-14 follow-up、'爆発エフェクトはEbuzセル毎に1回 8セルだ"
      "から8回エフェクトとサウンド'): 撃破の瞬間、span4(state2以降)の"
      "8セル分がEBUZ_EXPL_QUEUEへ積まれる",
      z3.rd(sym["EBUZ_EXPL_QUEUE_COUNT"]) == 8)
check("撃破後、本体の4行footprintは全てBLANKCODEへ消去されている"
      "(2026-09-14follow-up: 旧来のTRIGGER_EXPLOSION[BGアニメ1コマ]呼び"
      "出しは廃止され、8セル分はPLAYER_EXPL_POOL側のキュー経由で描画"
      "されるため、BG側footprintは1コマも残さず完全に消える)",
      all(vrd(z3, cell(r, 24 + i)) == BC for r in (8, 9, 10, 11) for i in range(4 if r in (9, 10) else 5)))

# 列/行が外れていれば当たらないことも確認(誤検出防止)。
z4 = fresh()
boot(z4)
swr(z4, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z4, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z4, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z4, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z4, S0, "HP", sym["EBUZ_HP_INIT"])
check("本体の列範囲(24-27)より1列左(23)は外れ判定",
      hit_ebuz(z4, 23, 9) == 0 and srd(z4, S0, "HP") == sym["EBUZ_HP_INIT"])
check("本体の行範囲(state2は8-11)より1行下(12)は外れ判定",
      hit_ebuz(z4, 25, 12) == 0 and srd(z4, S0, "HP") == sym["EBUZ_HP_INIT"])
swr(z4, S0, "ACT", sym["EBUZ_ST_STATE1"])
check("state1(2行のみ、span2)の間は、state2の翼帯行(8)にはまだ本体が"
      "無いので外れ判定",
      hit_ebuz(z4, 25, 8) == 0 and srd(z4, S0, "HP") == sym["EBUZ_HP_INIT"])

# B,Cが呼び出し元に対して破壊されないことを直接確認(両スロットの
# MISS経路が連続しても保たれること)。
z5 = fresh()
boot(z5)
swr(z5, S0, "ACT", 0)
swr(z5, S1, "ACT", 0)
z5.b, z5.c = 0x11, 0x22
call_routine(z5, sym["CHECK_BULLET_VS_EBUZ"])
check("両スロットとも非活性(即MISS)でもB,Cレジスタは呼び出し元のため"
      "保持される",
      z5.b == 0x11 and z5.c == 0x22)
z5b = fresh()
boot(z5b)
swr(z5b, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z5b, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z5b, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z5b, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z5b, S0, "HP", sym["EBUZ_HP_INIT"])
z5b.b, z5b.c = 25, 9
call_routine(z5b, sym["CHECK_BULLET_VS_EBUZ"])
check("SLOT0がヒットを検出した場合でもB,C(col,row)は変更されない",
      z5b.b == 25 and z5b.c == 9)

z5c = fresh()
boot(z5c)
swr(z5c, S0, "ACT", 0)  # SLOT0はMISSで抜ける
swr(z5c, S1, "ACT", sym["EBUZ_ST_FIRE"])
swr(z5c, S1, "ROW", sym["EBUZ_ROW_INST3"])
swr(z5c, S1, "COL", sym["EBUZ_SPAWN_COL"])
swr(z5c, S1, "CENTER_ROW", sym["EBUZ_ROW_INST3"])
swr(z5c, S1, "HP", sym["EBUZ_HP_INIT"])
r9_3 = sym["EBUZ_ROW_INST3"]
check("SLOT0がMISSでもSLOT1側が正しくチェックされる(2スロット"
      "ディスパッチの後段が機能する)",
      hit_ebuz(z5c, 25, r9_3) == 1 and srd(z5c, S1, "HP") == sym["EBUZ_HP_INIT"] - 1)

# 自己検証: HP減算そのものを一時的に無効化する。
def _regress_no_hp_decrement():
    broken_mem = bytearray(mem0)
    hp_field_ofs = sym["EBUZ_OFS_HP"]
    # LD A,(IX+EBUZ_OFS_HP)=DD 7E ofs / DEC A=3D / LD (IX+EBUZ_OFS_HP),A=DD 77 ofs
    pat = bytes([0xDD, 0x7E, hp_field_ofs & 0xFF, 0x3D, 0xDD, 0x77, hp_field_ofs & 0xFF])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("pattern not found for self-verification")
    broken_mem[idx + 3] = 0x00  # DEC A -> NOP(HPが一切減らなくなる)
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    zz.wr(sa(S0, "ACT"), sym["EBUZ_ST_FIRE"])
    zz.wr(sa(S0, "ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "COL"), sym["EBUZ_SPAWN_COL"])
    zz.wr(sa(S0, "CENTER_ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "HP"), sym["EBUZ_HP_INIT"])
    zz.b, zz.c = 25, 9
    for _ in range(sym["EBUZ_HP_INIT"]):
        sp_before = zz.sp
        zz.push(0x0000)
        zz.pc = sym["CHECK_BULLET_VS_EBUZ"]
        for _ in range(300000):
            if zz.pc == 0x0000:
                break
            zz.step()
        zz.pc = sym["MAINLOOP"]
    return zz.rd(sa(S0, "ACT")) == 0


check("自己検証: HP減算命令を無効化すると、24発当てても撃破に至らず"
      "SLOT0.ACTが0にならない(=正しい実装ではHPが実際に効いている"
      "ことの確認)",
      _regress_no_hp_decrement() == False)

# ============================================================
# 9. 衝突: Ebuz本体・弾との接触で自機がダメージを受ける
#     (PDC_CHECK_EBUZ、既存のPDC_CHECK_*群と同じ「相手は無傷」設計)
# ============================================================
def pdc_check_ebuz(z):
    call_routine(z, sym["PDC_CHECK_EBUZ"])
    return z.a


z6 = fresh()
boot(z6)
swr(z6, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z6, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z6, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z6, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
z6.wr(sym["PLAYERX"], 200)
z6.wr(sym["PLAYERY"], 72)
check("自機が本体(state2、32x32)に重なると接触検出", pdc_check_ebuz(z6) == 1)
check("PDC_CHECK_EBUZは相手(Ebuz)にダメージを与えない",
      srd(z6, S0, "ACT") == sym["EBUZ_ST_FIRE"])
z6.wr(sym["PLAYERX"], 0)
z6.wr(sym["PLAYERY"], 0)
check("自機が本体から大きく離れていれば接触なし", pdc_check_ebuz(z6) == 0)

z7 = fresh()
boot(z7)
swr(z7, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z7, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z7, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z7, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z7, S0, "B0_ACTIVE", 1)
swr(z7, S0, "B0_COL", 10)
z7.wr(sym["PLAYERX"], 80)
z7.wr(sym["PLAYERY"], 72)
check("(2026-09-14 follow-up2、'Ebuzの弾の判定は1pxに'): "
      "自機がbullet0の基準点(row9,col10)にちょうど重なると接触検出",
      pdc_check_ebuz(z7) == 1)
z7.wr(sym["PLAYERX"], 88)  # 旧16x16判定なら依然ヒットする範囲(+8px)
z7.wr(sym["PLAYERY"], 72)
check("自己検証: bullet0基準点から8px右では1px判定によりMISS"
      "(旧16x16判定ならHITしていたはずの範囲)",
      pdc_check_ebuz(z7) == 0)

z8 = fresh()
boot(z8)
swr(z8, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(z8, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(z8, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(z8, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(z8, S0, "TOP_COLS", 5)
z8.wr(sym["PLAYERX"], 40)
z8.wr(sym["PLAYERY"], (sym["EBUZ_ROW_INST1"] - 1) * 8)  # TOPBAND_ROW = CENTER_ROW-1
check("(2026-09-14 follow-up2、'他もすべて1px'): "
      "自機が上レーン弾の基準点(row8,col5)にちょうど重なると接触検出",
      pdc_check_ebuz(z8) == 1)
z8.wr(sym["PLAYERX"], 40)
z8.wr(sym["PLAYERY"], (sym["EBUZ_ROW_INST1"] - 1) * 8 + 7)  # 旧16x8判定なら依然ヒットする範囲
check("自己検証: 上レーン弾基準点から7px下では1px判定によりMISS"
      "(旧16x8判定ならHITしていたはずの範囲)",
      pdc_check_ebuz(z8) == 0)

z9 = fresh()
boot(z9)
swr(z9, S0, "ACT", 0)
swr(z9, S1, "ACT", sym["EBUZ_ST_FIRE"])
swr(z9, S1, "ROW", sym["EBUZ_ROW_INST3"])
swr(z9, S1, "COL", sym["EBUZ_SPAWN_COL"])
swr(z9, S1, "CENTER_ROW", sym["EBUZ_ROW_INST3"])
z9.wr(sym["PLAYERX"], 200)
z9.wr(sym["PLAYERY"], sym["EBUZ_ROW_INST3"] * 8 - 4)
check("SLOT0が非活性でも、SLOT1本体との接触がPDC_CHECK_EBUZで検出される",
      pdc_check_ebuz(z9) == 1)

# ============================================================
# 10. マルチインスタンスチェーン(2026-09-14 follow-up、本Roundの中心):
#     1体目撃破→(同一SLOT0で)2体目スポーン(Row12)→2体目がFIRE到達→
#     3体目スポーン(SLOT1、Row5、2体目と同時生存)
# ============================================================
def spawn_ebuz_chain(z):
    """boot()した上でEBUZ_SPAWN_CHAIN_STARTを直接呼びチェーンを開始する。
    旧名spawn_chain_to_tick100(GAME_TICK==100固定トリガー依存)から
    round135follow-up5でリネーム - ハードコードスケジュール機構の撤去
    により、もうどのtick値にも紐付かない。"""
    boot(z)
    call_routine(z, sym["EBUZ_SPAWN_CHAIN_START"])


def advance_until(z, pred, max_frames=3000):
    return run_until(z, pred, max_frames=max_frames)


zc = fresh()
spawn_ebuz_chain(zc)
check("チェーン開始: STAGE=1、SLOT0が1体目(CENTER_ROW=9)としてスポーン",
      zc.rd(sym["EBUZ_SPAWN_STAGE"]) == 1 and
      srd(zc, S0, "CENTER_ROW") == sym["EBUZ_ROW_INST1"])

# 1体目をFIREまで進めてから24発当てて撃破する。
advance_until(zc, lambda z: srd(z, S0, "ACT") == sym["EBUZ_ST_FIRE"], max_frames=2000)
col1 = srd(zc, S0, "COL")
center1 = srd(zc, S0, "CENTER_ROW")
for _ in range(sym["EBUZ_HP_INIT"]):
    hit_ebuz(zc, col1 + 1, center1)
check("1体目を24発で撃破: SLOT0.ACTが0に戻る",
      srd(zc, S0, "ACT") == 0)
# hit_ebuz()はCHECK_BULLET_VS_EBUZを直接call_routine()するテスト用
# ショートカットであり、実MAINLOOPのフレームループの外側にあるため、
# EBUZ_CHECK_CHAIN_TRIGGERS自体はまだ一度も走っていない。実ゲームでは
# 自機弾ヒットも必ずMAINLOOPの1フレーム内で処理されるため、この直後に
# 1回step_frame()するのが実際の流れに対応する(その1フレーム内で
# EBUZ_CHECK_CHAIN_TRIGGERSが呼ばれ、即座に2体目がスポーンする)。
row0_before_spawn_c = [vrd(zc, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)]
step_frame(zc)
check("(2026-09-14 follow-up、'次に2体目 スポーンは1体目が消えたら'):"
      "撃破を検出した次のフレームでSTAGE=2、SLOT0に2体目がスポーンする"
      "(同じSLOT0を再利用)",
      zc.rd(sym["EBUZ_SPAWN_STAGE"]) == 2 and srd(zc, S0, "ACT") == sym["EBUZ_ST_ENTER"])
check("(2026-09-14 follow-up、'スポーン位置2体目がRow12'): 2体目の"
      "CENTER_ROWはEBUZ_ROW_INST2(12)",
      srd(zc, S0, "CENTER_ROW") == sym["EBUZ_ROW_INST2"] == 12)
check("2体目スポーン時、HPは24(EBUZ_HP_INIT)にリセットされる",
      srd(zc, S0, "HP") == sym["EBUZ_HP_INIT"])
check("2体目スポーン時もrow0は一切変化しない(row1から描画開始、"
      "row0破壊なし)",
      [vrd(zc, cell(0, sym["EBUZ_SPAWN_COL"] + i)) for i in range(4)] == row0_before_spawn_c)

# (2026-09-14 follow-up2、'3体目出現を2体目の5秒後に'): 2体目スポーンの
# 瞬間(直前のstep_frame(zc))にEBUZ_CHAIN_TIMERが0にリセットされている。
# 以後EBUZ_INST3_DELAY_FRAMES(300、60Hz想定で5秒)フレーム経過した瞬間、
# 同一フレーム内で3体目がSLOT1へトリガーされる
# (2体目はまだSLOT0で生存中=同時生存)。
delay = sym["EBUZ_INST3_DELAY_FRAMES"]
for _ in range(delay - 1):
    step_frame(zc)
check(f"3体目トリガーはまだ({delay-1}フレーム経過時点でSTAGE=2のまま)",
      zc.rd(sym["EBUZ_SPAWN_STAGE"]) == 2)
step_frame(zc)
check("(2026-09-14 follow-up2、'3体目出現を2体目の5秒後に'):"
      f"2体目スポーンから{delay}フレーム(5秒)後、同フレームでSTAGE=3、"
      "SLOT1に3体目がスポーンする",
      zc.rd(sym["EBUZ_SPAWN_STAGE"]) == 3 and srd(zc, S1, "ACT") == sym["EBUZ_ST_ENTER"])
check("(2026-09-14 follow-up、'3体目Row5'): 3体目のCENTER_ROWは"
      "EBUZ_ROW_INST3(5)",
      srd(zc, S1, "CENTER_ROW") == sym["EBUZ_ROW_INST3"] == 5)
check("3体目トリガー時点で、2体目(SLOT0)はまだ生存中"
      "(=2体目と3体目が画面上で同時生存する、'撤退するか倒される"
      "まで待たない'仕様の直接確認)",
      srd(zc, S0, "ACT") != 0)
check("チェーンはSTAGE=3で完了(以後、新たな追加トリガーは発火しない)",
      True)

# STAGE=3以降、さらに何フレーム進めてもSTAGE=3のまま固定されることを
# 確認(二重発火防止)。
for _ in range(50):
    step_frame(zc)
check("STAGE=3到達後、50フレーム進めてもSTAGE=3のまま(二重発火なし)",
      zc.rd(sym["EBUZ_SPAWN_STAGE"]) == 3)

# ============================================================
# 11. チェーン: 1体目が(撃破ではなく)自然EXITで消えた場合も
#     2体目が正しくトリガーされる("撤退するか倒されるか"の両方)
# ============================================================
zd = fresh()
spawn_ebuz_chain(zd)
swr16(zd, S0, "LIFE_TIMER", 1)  # 1フレームでEXITへ強制遷移させる
advance_until(zd, lambda z: srd(z, S0, "ACT") == sym["EBUZ_ST_EXIT"], max_frames=10)
check("1体目が生存時間切れでEXITへ遷移", srd(zd, S0, "ACT") == sym["EBUZ_ST_EXIT"])
# (2026-09-14 follow-up設計の直接確認): EBUZ_DO_EXITがEXIT完了で
# SLOT0.ACTを0に戻すのと、EBUZ_CHECK_CHAIN_TRIGGERSがそれを検出して
# 2体目をスポーンさせるのは同一フレーム内で連続して起こるため、
# "ACT==0"という状態がフレームをまたいで観測されることはない
# (即座に2体目のACT==ENTER[1]へ上書きされる) - よって「ACT==0」を
# 待つのではなく「もはやEXITではない(=完了した)」ことを待ってから、
# 直接2体目の状態を確認する。
advance_until(zd, lambda z: srd(z, S0, "ACT") != sym["EBUZ_ST_EXIT"], max_frames=200)
check("(EXIT[撤退]経路でも同様に)1体目のEXIT完了と同フレームでSTAGE=2、"
      "SLOT0に2体目(Row12)がスポーンする(待ちフレーム無しの即時遷移)",
      zd.rd(sym["EBUZ_SPAWN_STAGE"]) == 2 and
      srd(zd, S0, "ACT") == sym["EBUZ_ST_ENTER"] and
      srd(zd, S0, "CENTER_ROW") == sym["EBUZ_ROW_INST2"])

# ============================================================
# 12. 8セル死亡演出(2026-09-14 follow-up、"爆発エフェクトはEbuzセル毎に
#     1回 8セルだから8回エフェクトとサウンド 自機爆発のサウンドと
#     スプライトを流用"): EBUZ_EXPL_QUEUEがPLAYER_EXPL_POOLを介して
#     正しく8回分ポップ+SOUND_DESTROYされることを検証する。
# ============================================================
ze = fresh()
boot(ze)
swr(ze, S0, "ACT", sym["EBUZ_ST_FIRE"])
swr(ze, S0, "ROW", sym["EBUZ_ROW_INST1"])
swr(ze, S0, "COL", sym["EBUZ_SPAWN_COL"])
swr(ze, S0, "CENTER_ROW", sym["EBUZ_ROW_INST1"])
swr(ze, S0, "HP", 1)  # 次の1発で即撃破
for i in range(5):
    ze.vram[cell(8, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]
    ze.vram[cell(11, 24 + i) & 0x3FFF] = [BC, A_, B_, C_, BC][i]

pool = sym["PLAYER_EXPL_POOL"]
struct = sym["PLAYER_EXPL_STRUCT"]
slots = sym["PLAYER_EXPL_SLOTS"]


def expl_pool_active_count(z):
    return sum(1 for i in range(slots) if z.rd(pool + i * struct + 0) != 0)


check("撃破前、PLAYER_EXPL_POOLは全スロット非活性",
      expl_pool_active_count(ze) == 0)
hit_ebuz(ze, 25, 9)
check("撃破の瞬間、EBUZ_EXPL_QUEUE_COUNTがちょうど8になる",
      ze.rd(sym["EBUZ_EXPL_QUEUE_COUNT"]) == 8)

# キューの8セル分の(X,Y)を直接検算する: span4の内訳は
# 上翼帯3セル(col+1..+3)+下翼帯3セル(col+1..+3)+row9のD柱1セル(col+3)+
# row10のD柱1セル(col+3)。
col = sym["EBUZ_SPAWN_COL"]
center = sym["EBUZ_ROW_INST1"]
expect_cells = []
for c_ in range(1, 4):
    expect_cells.append(((col + c_) * 8, (center - 1) * 8))  # 上翼帯
for c_ in range(1, 4):
    expect_cells.append(((col + c_) * 8, (center + 2) * 8))  # 下翼帯
expect_cells.append(((col + 3) * 8, center * 8))       # row9 D柱
expect_cells.append(((col + 3) * 8, (center + 1) * 8))  # row10 D柱
qbase = sym["EBUZ_EXPL_QUEUE"]
actual_cells = [(ze.rd(qbase + i * 2), ze.rd(qbase + i * 2 + 1)) for i in range(8)]
check("8セル分のキュー内容(X,Y)が、span4の実座標(上下翼帯3+3、"
      "row9/row10のD柱各1)と完全一致",
      actual_cells == expect_cells)

# EBUZ_EXPL_UPDATE_QUEUEがEBUZ_EXPL_SPAWN_INTERVALごとに1個ずつ
# PLAYER_EXPL_POOLへポップしていくことを確認。
seen_counts = []
for _ in range(40):
    step_frame(ze)
    seen_counts.append(expl_pool_active_count(ze))
check("8セル分が段階的にPLAYER_EXPL_POOLへポップされる"
      "(最大同時アクティブ数がPLAYER_EXPL_SLOTS[4]を超えない)",
      max(seen_counts) <= slots and max(seen_counts) >= 1)
check("40フレーム経過後、EBUZ_EXPL_QUEUE_COUNTは0(8個全て消化済み)",
      ze.rd(sym["EBUZ_EXPL_QUEUE_COUNT"]) == 0)


def _regress_explosion_queue_not_drained():
    """EBUZ_EXPL_UPDATE_QUEUEの呼び出し自体を無効化すると、キューが
    いつまでも消化されずCOUNT=8のまま残ることを確認する自己検証。"""
    broken_mem = bytearray(mem0)
    target = sym["EBUZ_EXPL_UPDATE_QUEUE"]
    pat = bytes([0xCD, target & 0xFF, (target >> 8) & 0xFF])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("CALL EBUZ_EXPL_UPDATE_QUEUE not found")
    broken_mem[idx] = 0x00
    broken_mem[idx + 1] = 0x00
    broken_mem[idx + 2] = 0x00
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    zz.wr(sa(S0, "ACT"), sym["EBUZ_ST_FIRE"])
    zz.wr(sa(S0, "ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "COL"), sym["EBUZ_SPAWN_COL"])
    zz.wr(sa(S0, "CENTER_ROW"), sym["EBUZ_ROW_INST1"])
    zz.wr(sa(S0, "HP"), 1)
    zz.b, zz.c = 25, 9
    sp_before = zz.sp
    zz.push(0x0000)
    zz.pc = sym["CHECK_BULLET_VS_EBUZ"]
    for _ in range(300000):
        if zz.pc == 0x0000:
            break
        zz.step()
    zz.pc = sym["MAINLOOP"]
    for _ in range(40):
        zz.pc = sym["MAINLOOP"]; zz.step(); run_until_pc(zz, sym["MAINLOOP"])
    return zz.rd(sym["EBUZ_EXPL_QUEUE_COUNT"])


check("自己検証: EBUZ_EXPL_UPDATE_QUEUEの呼び出しを無効化すると、"
      "40フレーム経過してもキューが全く消化されない(COUNT=8のまま)"
      "=このRoundの新機構が実際に効いていることの確認",
      _regress_explosion_queue_not_drained() == 8)

# ============================================================
# 13. round135follow-up4「Ebuzの発射音欲しい マシンガンみたいなやつ
#     ...音は2番で」: 発射のたびSOUND_EBUZ_FIRE(候補2「ディープ・
#     スタッター」、noise period=14)が実際に呼ばれる。SND_TIMERは
#     同じフレーム内でSOUND_UPDATE自身がすぐ1減算するため(既存の
#     SOUND_DESTROY系テスト[verify_player_damage.py]と同じ理由で)
#     ここではPSGレジスタ6(ノイズ周期)の書き込みだけを発射の証拠と
#     して見る - EBUZ_FIRE_INTERVAL(2)フレーム以内に必ず1回は発射
#     されるはずなので、直前に毎フレームpoisonしながら実際にR6=14が
#     現れるかを確認する。
# ============================================================
def _ebuz_fires_sound(fire_side):
    zj = fresh()
    spawn_ebuz_chain(zj)
    advance_until(zj, lambda z: srd(z, S0, "ACT") == sym["EBUZ_ST_FIRE"], max_frames=2000)
    swr(zj, S0, "FIRE_SIDE", fire_side)
    for _ in range(sym["EBUZ_FIRE_INTERVAL"] + 1):
        zj.psg_regs.pop(6, None)
        step_frame(zj)
        if zj.psg_regs.get(6) == 14:
            return True
    return False


check("Ebuzの発射(FIRE_SIDE=0、上レーン)のたびSOUND_EBUZ_FIREが実際に呼ばれる "
      "(PSGレジスタ6にノイズ周期14が書き込まれる)",
      _ebuz_fires_sound(0))
check("Ebuzの発射(FIRE_SIDE=1、下レーン)でも同様に呼ばれる",
      _ebuz_fires_sound(1))


def _regress_ebuz_fire_sound_not_called():
    """EUTF_FIRE_DONEへ挿入したCALL SOUND_EBUZ_FIREを一時的にNOP化する
    自己検証(上2件のPASSがこの1行によって成立していることの裏取り)。"""
    broken_mem = bytearray(mem0)
    target = sym["SOUND_EBUZ_FIRE"]
    pat = bytes([0xCD, target & 0xFF, (target >> 8) & 0xFF])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("pattern not found for self-verification")
    broken_mem[idx] = 0x00
    broken_mem[idx + 1] = 0x00
    broken_mem[idx + 2] = 0x00
    zk = Z80(broken_mem)
    zk.pc = sym["INIT"]
    run_until_pc(zk, sym["MAINLOOP"])
    spawn_ebuz_chain(zk)
    advance_until(zk, lambda z: srd(z, S0, "ACT") == sym["EBUZ_ST_FIRE"], max_frames=2000)
    for _ in range(sym["EBUZ_FIRE_INTERVAL"] * 4):
        zk.psg_regs.pop(6, None)
        step_frame(zk)
        if zk.psg_regs.get(6) == 14:
            return True
    return False


check("自己検証: CALL SOUND_EBUZ_FIREを取り除くと、発射を何度繰り返しても"
      "R6=14は一度も現れない(=上2件が本当にこの呼び出しを検証していること"
      "の確認)",
      _regress_ebuz_fire_sound_not_called() == False)

# ============================================================
# 14. round135follow-up10「GAME_TICKは進めるが新規スポーンだけ止める」:
#     Ebuzが1体でも生存中は、SSC_FIREの新規スポーンディスパッチだけが
#     一時停止する(GAME_TICK自体・SPAWN_SCHEDULE_CHECKの呼び出し自体は
#     普段通り)。停止中はSPAWN_NEXT_INDEXも増えない(発火の取りこぼし
#     なし)、Ebuz消滅の瞬間に即座に再開する。
# ============================================================
zn = fresh()
boot(zn)
wr16(zn, sym["GAME_TICK"], 999)  # 全thresholdを確実に超過させる
wr16(zn, sym["SPAWN_NEXT_INDEX"], 0)
swr(zn, S0, "ACT", sym["EBUZ_ST_ENTER"])  # SLOT0のみアクティブ
gt_before = game_tick(zn)
for _ in range(40):
    step_frame(zn)
check("Ebuz(SLOT0)生存中は40フレーム経過してもSPAWN_NEXT_INDEXが"
      "全く進まない(新規スポーンのディスパッチが一時停止している)",
      rd16(zn, sym["SPAWN_NEXT_INDEX"]) == 0)
check("...その間もGAME_TICKは普段通り進み続けている"
      "(止まっているのはスポーンのディスパッチだけ、時計は止めない)",
      game_tick(zn) > gt_before)
swr(zn, S0, "ACT", 0)  # Ebuz消滅
for _ in range(8):
    step_frame(zn)
check("Ebuz消滅後は即座にディスパッチが再開し、SPAWN_NEXT_INDEXが"
      "0から進み始める(取りこぼしなく、待たされていた分から順に発火)",
      rd16(zn, sym["SPAWN_NEXT_INDEX"]) > 0)

zn2 = fresh()
boot(zn2)
wr16(zn2, sym["GAME_TICK"], 999)
wr16(zn2, sym["SPAWN_NEXT_INDEX"], 0)
swr(zn2, S1, "ACT", sym["EBUZ_ST_FIRE"])  # SLOT1側だけがアクティブでも同様に止まる
for _ in range(40):
    step_frame(zn2)
check("SLOT1だけがアクティブ(SLOT0は非活性)でも同様にディスパッチが"
      "一時停止する(EBUZ_ANY_ACTIVEが両スロットを見ている)",
      rd16(zn2, sym["SPAWN_NEXT_INDEX"]) == 0)


def _regress_no_spawn_pause_check():
    """SSC_FIRE冒頭のEBUZ_ANY_ACTIVEガードを無効化する(CALL直後のOR A:
    RET NZを潰す)自己検証。"""
    broken_mem = bytearray(mem0)
    target = sym["EBUZ_ANY_ACTIVE"]
    pat = bytes([0xCD, target & 0xFF, (target >> 8) & 0xFF, 0xB7, 0xC0])
    idx = bytes(broken_mem).find(pat)
    if idx < 0:
        raise RuntimeError("pattern not found for self-verification")
    broken_mem[idx + 3] = 0x00  # OR A -> NOP
    broken_mem[idx + 4] = 0x00  # RET NZ -> NOP(1バイト目のみ潰し、Zフラグに依存させない)
    zz = Z80(broken_mem)
    zz.pc = sym["INIT"]
    run_until_pc(zz, sym["MAINLOOP"])
    wr16(zz, sym["GAME_TICK"], 999)
    wr16(zz, sym["SPAWN_NEXT_INDEX"], 0)
    zz.wr(S0 + sym["EBUZ_OFS_ACT"], sym["EBUZ_ST_ENTER"])
    for _ in range(40):
        zz.pc = sym["MAINLOOP"]; zz.step(); run_until_pc(zz, sym["MAINLOOP"])
    return rd16(zz, sym["SPAWN_NEXT_INDEX"]) == 0


check("自己検証: SSC_FIRE冒頭の新規スポーン一時停止ガードを無効化すると、"
      "上と同じ40フレーム経過チェックが正しくFAILに転じる"
      "(=このガードが実際に効いていることの確認)",
      _regress_no_spawn_pause_check() == False)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
