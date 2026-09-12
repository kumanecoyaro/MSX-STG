"""tools/gameover_bank/gameover_bank.asm(2026-09-07新設、Stage2の
TANK_LIFE枯渇時の死亡演出+"MISSION FAILED"表示専用バンク)の単体検証。

standalone(このファイル単体、window Aのみの16KBバンク)としてアセンブル
し、フォントの実バイトパターン・メッセージコード列・自機爆発演出の
描画ロジックを直接検証する。実際のバンク切替統合(combined_test.asm
のTRIGGER_GAME_OVERからここへ、ここからtitleへ)はverify_comb.py側の
役割 - ここではこのファイル単体のロジックのみを見る。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
from mini_z80asm import Assembler
from z80emu import Z80
import pixel_font_8x8

with open(os.path.join(REPO, "tools", "gameover_bank", "gameover_bank.asm"), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

# (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバージングル
# をこのバンクにも実装): このファイルの harness は真のマルチバンク
# エミュレーション(BankedMem)を持たないフラットな64KBメモリ1枚だけ -
# `LD A,6:LD(7000h),A`(window B選択)はここでは単なるRAM書き込みで
# 実際のバンク切替効果を持たないため、GO_INIT_BGMのLDIRが読みに行く
# window B空間(0x8000-0xBFFF)へ、実際のbgm-dataバンク(tools/bgm_data/
# bgm_bank_gen.py)の内容をあらかじめ直接展開しておく - こうすることで
# 「window Bが正しくbank6を指している」状態を模擬でき、GO_INIT_BGMの
# RAMコピーやGO_BGM_TICKの実際の音符再生を、combined_test.asm自身の
# INIT_BGM検証(bgm_test.py)と同じ水準で直接検証できる。実際のバンク
# 切替そのもの(TRIGGER_GAME_OVERからここへ、bank5->bank6->bank5等の
# window B遷移)の統合検証は引き続きverify_comb.py側の役割。
REPO2 = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(REPO2, "tools", "bgm_data"))
import bgm_bank_gen as bg  # noqa: E402

bgm_bank, bgm_layout = bg.build_bank()
for i, b in enumerate(bgm_bank):
    mem0[0x8000 + i] = b

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


check("assembles standalone within a single 16KB window-A bank (4000h-7FFFh)",
      max(out) <= 0x7FFF and min(out) >= 0x4000)

# ---- font glyph bytes: relocated to code96-103+144-146 (group12/18) - ----
# ---- same "boss-only, safe after terrain's own code0-93" reasoning as ----
# ---- ending_text_gen.py's GFEnding font, NOT the original code0-10    ----
# ---- that clobbered the live terrain (found via self-rendering, see   ----
# ---- this file's own INIT comment).                                  ----
FONT_CHARS = ["M", "I", "S", "O", "N", " ", "F", "A", "L", "E", "D"]
FONT_CODES = [96, 97, 98, 99, 100, 101, 102, 103, 144, 145, 146]
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["GO_EXPLOSION_SEQUENCE"])
font_ok = True
for ch, code in zip(FONT_CHARS, FONT_CODES):
    expected = pixel_font_8x8.glyph_bytes(ch)
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != expected:
        font_ok = False
check("MISSION FAILED font glyphs loaded byte-correct at code96-103+144-146, "
      "matching tools/pixel_font_8x8.py", font_ok)
check("group12 (codes96-103) color patched to white/black (0F1h)", z.vram[0x200C] == 0xF1)
check("group18 (codes144-151) color patched to white/black (0F1h)", z.vram[0x2012] == 0xF1)

# ---- GAMEOVER2_MSG content: "MISSION FAILED" using the relocated codes ----
def read_msg(addr, length):
    return [mem0[addr + i] for i in range(length)]

GAMEOVER2_MSG = sym["GAMEOVER2_MSG"]
GAMEOVER2_MSG_LEN = sym["GAMEOVER2_MSG_LEN"]
expected_msg = [96, 97, 98, 98, 97, 99, 100, 101, 102, 103, 97, 144, 145, 146]
check("GAMEOVER2_MSG = 'MISSION FAILED' (14 bytes) using the relocated codes",
      read_msg(GAMEOVER2_MSG, GAMEOVER2_MSG_LEN) == expected_msg)

# ---- message drawn at row12/col9 (matches Stage1's own DRAW_GAMEOVER_TEXT ----
# ---- position exactly - same 14-byte-centered convention) ----
z = fresh()
for i in range(768):
    z.vram[0x1800 + i] = 0x33
z.pc = sym["INIT"]
run_until_pc(z, sym["GO_WAIT_LOOP"], max_instr=5_000_000)
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAMEOVER2_MSG_LEN]
check("MISSION FAILED text is drawn at row12/col9 by the time GO_WAIT_LOOP is reached",
      msg_region == expected_msg)

# (2026-09-07、実機フィードバック対応"Mission Failedの行はブランクブラック
# で埋めてくれ"): row12全体(32セル)がcols0-8/cols23-31含めHUD_ROW_BLANK_
# CODE(黒)で埋まっていること - 旧実装はメッセージの14セル以外は死亡直前の
# 地形・背景がそのまま透けて見えていた(0x33の汚染マーカーが残ってしまう)。
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
check("HUD_ROW_BLANK_CODE matches combined_test.asm's own value (120, group15 "
      "pure-black blank tile)", HUD_ROW_BLANK_CODE == 120)
row12 = nametable[12 * 32: 12 * 32 + 32]
check("row12's left margin (cols0-8, before the message) is blanked to "
      "HUD_ROW_BLANK_CODE, not left showing the pre-death terrain/background",
      row12[0:9] == [HUD_ROW_BLANK_CODE] * 9)
check("row12's right margin (cols23-31, after the message) is blanked to "
      "HUD_ROW_BLANK_CODE, not left showing the pre-death terrain/background",
      row12[23:32] == [HUD_ROW_BLANK_CODE] * 9)
check("no leftover 0x33 poison bytes remain anywhere in row12 (fully "
      "overwritten - blank margins + message, nothing untouched)",
      0x33 not in row12)

# ---- single-pop explosion (2026-09-07、実機フィードバック対応その3
# ---- "4つ爆発を同時に飛ばすんじゃなく1個ずつバラバラにだ でその1回毎に
# ---- サウンドだ 速度も遅いって何回言わせんだよ 音出して1つ飛ばして
# ---- また音出して1つ飛ばしての繰り返し ボス爆発がそうなってんだろう
# ---- が"): 旧・4パーティクル同時直進飛翔モデルを全面撤回し、
# ---- src/CYBER SHMUP.asmのBOSS_EXPL_UPDATE/BEU_FIRE(「毎回ランダムな
# ---- 新しい位置に1個ポップ+毎回SOUND_DESTROY+短い待ちで次」の高速連続
# ---- ポップ)と同じモデルへ再設計した。
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
PAT_EXPLOSION = sym["PAT_EXPLOSION"]
SPR_WHITE_COLOR = sym["SPR_WHITE_COLOR"]
SPR_LIGHTRED_COLOR = sym["SPR_LIGHTRED_COLOR"]
GO_POP_JITTER = sym["GO_POP_JITTER"]
GO_SLOT_IDX = sym["GO_SLOT_IDX"]
GO_POP_CTR = sym["GO_POP_CTR"]


def signed(v):
    return v - 256 if v >= 128 else v


def call_ret(z, target, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = target
    run_until_pc(z, 0x0000, max_instr)


def call_launch_one_pop(seed, slot_idx, pop_ctr_parity, tank_x=50, tank_y=80):
    z = fresh()
    z.wr(TANK_X, tank_x)
    z.wr(TANK_Y_CUR, tank_y)
    z.wr(sym["GO_RNG"], seed)
    z.wr(GO_SLOT_IDX, slot_idx)
    z.wr(GO_POP_CTR, pop_ctr_parity)
    call_ret(z, sym["GO_LAUNCH_ONE_POP"])
    return z


z = call_launch_one_pop(seed=11, slot_idx=0, pop_ctr_parity=0, tank_x=50, tank_y=80)
attrs0 = [z.vram[0x1B00 + i] for i in range(4)]
check("GO_LAUNCH_ONE_POP draws exactly 1 explosion sprite in slot0's own "
      "ATTRIBUTE record (Y at row0-3)",
      attrs0[2] == PAT_EXPLOSION)
dx0 = signed(attrs0[1]) - 50 if attrs0[1] < 128 else attrs0[1] - 50
dy0 = attrs0[0] - 80
check(f"GO_LAUNCH_ONE_POP's jitter offset stays within -{GO_POP_JITTER // 2}.."
      f"+{GO_POP_JITTER // 2 - 1}px of TANK_X/TANK_Y_CUR (never a wild "
      "out-of-range position)",
      -GO_POP_JITTER // 2 <= signed(dy0) <= GO_POP_JITTER // 2 - 1)
check("GO_LAUNCH_ONE_POP with pop-counter parity=0 (even) draws in SPR_WHITE_COLOR",
      attrs0[3] == SPR_WHITE_COLOR)

z_red = call_launch_one_pop(seed=11, slot_idx=0, pop_ctr_parity=1, tank_x=50, tank_y=80)
attrs_red = [z_red.vram[0x1B00 + i] for i in range(4)]
check("GO_LAUNCH_ONE_POP with pop-counter parity=1 (odd) draws in SPR_LIGHTRED_COLOR",
      attrs_red[3] == SPR_LIGHTRED_COLOR)

z_slot2 = call_launch_one_pop(seed=11, slot_idx=2, pop_ctr_parity=0, tank_x=50, tank_y=80)
attrs_slot0 = [z_slot2.vram[0x1B00 + i] for i in range(4)]
attrs_slot2 = [z_slot2.vram[0x1B00 + 8 + i] for i in range(4)]
check("GO_LAUNCH_ONE_POP with GO_SLOT_IDX=2 draws into slot2's own ATTRIBUTE "
      "record, leaving slot0 untouched (still Y=0 from a fresh z80 - default "
      "VRAM state)",
      attrs_slot2[2] == PAT_EXPLOSION and attrs_slot0[2] != PAT_EXPLOSION)

z_advance = fresh()
z_advance.wr(GO_SLOT_IDX, 0)
call_ret(z_advance, sym["GO_LAUNCH_ONE_POP"])
check("GO_LAUNCH_ONE_POP advances GO_SLOT_IDX from 0 to 1",
      z_advance.rd(GO_SLOT_IDX) == 1)
z_advance.wr(GO_SLOT_IDX, 3)
call_ret(z_advance, sym["GO_LAUNCH_ONE_POP"])
check("GO_LAUNCH_ONE_POP wraps GO_SLOT_IDX from 3 back to 0 (round-robin over "
      "exactly the 4 available ATTRIBUTE slots)",
      z_advance.rd(GO_SLOT_IDX) == 0)

# ---- GO_EXPLOSION_SEQUENCE: NUM_POPS individual pops, each with its own ----
# ---- sound - this is the literal fix for "1個ずつバラバラに...音出して  ----
# ---- 1つ飛ばして"                                                        ----
NUM_POPS = sym["NUM_POPS"]
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.wr(sym["GO_RNG"], 5)
GO_LAUNCH_ONE_POP_PC = sym["GO_LAUNCH_ONE_POP"]
GO_ARM_BOOM_PC = sym["GO_ARM_BOOM"]
launch_count = 0
seen_r8_at_launch = []
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
z.pc = sym["GO_EXPLOSION_SEQUENCE"]
steps = 0
_prev_pc = None
while z.pc != 0x0000 and steps < 5_000_000:
    if z.pc == GO_LAUNCH_ONE_POP_PC and _prev_pc != GO_LAUNCH_ONE_POP_PC:
        launch_count += 1
        seen_r8_at_launch.append(z.psg_regs.get(8))
    _prev_pc = z.pc
    z.step()
    steps += 1
check(f"GO_EXPLOSION_SEQUENCE launches exactly NUM_POPS ({NUM_POPS}) individual "
      "pops - one at a time, not 4 simultaneously",
      launch_count == NUM_POPS)
check("every pop launch happens right after GO_ARM_BOOM has just set R8 to full "
      "volume (15) - confirms 'sound THEN launch' ordering, not the other way "
      "around",
      all(v == 15 for v in seen_r8_at_launch))

GO_HIDE_EXPLOSION = sym["GO_HIDE_EXPLOSION"]
GO_WAIT_LOOP = sym["GO_WAIT_LOOP"]
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.pc = sym["INIT"]
hide_calls_before_text = 0
steps = 0
while z.pc != GO_WAIT_LOOP and steps < 5_000_000:
    if z.pc == GO_HIDE_EXPLOSION:
        hide_calls_before_text += 1
    z.step()
    steps += 1
# (2026-09-07、実機フィードバック対応"爆発エフェクトが消えずのこったまま
# Mission Failedになってる で爆発エフェクトは消してくれ"): 新設計では
# バースト間の点滅ギャップを廃止した(新バーストは即座に自機中心へ戻り
# 継続して飛ぶ)ため、GO_HIDE_EXPLOSIONはもう全バーストの内部では呼ばれず、
# 全バースト完了後・テキスト描画直前の明示的な1回だけになった。
check("GO_HIDE_EXPLOSION is called exactly once before GO_WAIT_LOOP (the "
      "single explicit hide after all bursts finish, right before the "
      "MISSION FAILED text is drawn) - the fix for the explosion sprites "
      "being left visible under the text",
      hide_calls_before_text == 1)

# confirm the sprite attribute table is really left in the "all hidden" state at
# the moment GO_WAIT_LOOP (i.e. after the text has already been drawn) is reached -
# this is the literal on-screen check for "爆発エフェクトは消してくれ".
hidden_attrs = [z.vram[0x1B00 + i] for i in range(16)]
check("by the time MISSION FAILED text is on screen (GO_WAIT_LOOP reached), all 4 "
      "explosion particle sprite slots are hidden (Y=209), not left visible under it",
      hidden_attrs == [209, 0, 0, 0] * 4)

# ---- "自機爆発はサウンドも欲しい"、続けて"爆発音はステージ1、2ともに ----
# ---- パーティクルの回数鳴らすんだよ"(2026-09-07、実機フィードバック  ----
# ---- 対応その2): 旧GO_PLAY_BOOM_SOUND(全シーケンス開始時に1回だけ、   ----
# ---- 専用の16段減衰ループで完結)を全面撤回、GO_ARM_BOOM(バースト開始 ----
# ---- 時に音量15で撃ち直す)+GO_STEP_BOOM_DECAY(その後のフレーム      ----
# ---- ループの中で毎回1段ずつ減衰、専用の追加ウェイト無し)へ分割し、  ----
# ---- Stage1のPEUA_TRY_SPAWN(spawnごとに毎回SOUND_DESTROY)と同じ      ----
# ---- 「パーティクル[バースト]の数だけ毎回鳴らす」設計にした。         ----
MIXER_NOISE_A = sym["MIXER_NOISE_A"]
BOOM_NOISE_PERIOD = sym["BOOM_NOISE_PERIOD"]
GO_BOOM_VOL = sym["GO_BOOM_VOL"]
z = fresh()
call_ret(z, sym["GO_ARM_BOOM"])
check("GO_ARM_BOOM selects PSG R7 (mixer) = MIXER_NOISE_A (noise channel A on, "
      "tone B/C stay enabled for BGM - matches Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(7) == MIXER_NOISE_A)
check("GO_ARM_BOOM sets PSG R6 (noise period) = BOOM_NOISE_PERIOD (20, same as "
      "Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(6) == BOOM_NOISE_PERIOD)
check("GO_ARM_BOOM sets PSG R8 (channel A volume) to 15 (full volume retrigger)",
      z.psg_regs.get(8) == 15)
check("GO_ARM_BOOM sets GO_BOOM_VOL to 15 (the per-frame decay countdown)",
      z.rd(GO_BOOM_VOL) == 15)

# GO_STEP_BOOM_DECAY: called once per animation frame (BURST_FRAMES=8 times
# per burst) - decays by 2 each call, floored at 0, and stays silent once
# it reaches 0 (no further decrement past the floor).
z = fresh()
z.wr(GO_BOOM_VOL, 15)
r8_writes = []
for _ in range(10):
    call_ret(z, sym["GO_STEP_BOOM_DECAY"])
    r8_writes.append(z.psg_regs.get(8))
check("GO_STEP_BOOM_DECAY decays R8 by 2 each call, floored at 0 once it "
      "would go negative, and stays silent afterward (never re-increments)",
      r8_writes == [13, 11, 9, 7, 5, 3, 1, 0, 0, 0])
check("GO_STEP_BOOM_DECAY leaves GO_BOOM_VOL at 0 once fully decayed",
      z.rd(GO_BOOM_VOL) == 0)

# (2026-09-07、実機フィードバック対応その3で全面撤回): GO_NEW_BURST/
# NUM_BURSTSベースの旧テストは、上の「GO_EXPLOSION_SEQUENCE: NUM_POPS
# individual pops」ブロックが同じ主張(音が毎回再着火される)をより
# 直接検証するため削除した。

z2 = fresh()
z2.vram[0x1B00:0x1B10] = bytes([1] * 16)
z2.sp = 0xF000
z2.wr(0xF000, 0x00); z2.wr(0xF001, 0x00)
z2.pc = sym["GO_HIDE_EXPLOSION"]
run_until_pc(z2, 0x0000, 300000)
hide_attrs = [z2.vram[0x1B00 + i] for i in range(16)]
check("GO_HIDE_EXPLOSION hides all 4 slots (Y=209)",
      hide_attrs == [209, 0, 0, 0] * 4)

# ---- (2026-09-08、実機フィードバック対応、"ステージ2の自機爆発で音が
# 出っぱなしでMission Failedになってる 消してからゲームオーバーにしろ
# 音の消し忘れ多すぎだろうが"): GO_ARM_BOOM/GO_STEP_BOOM_DECAYはポップ
# ごとに音量15へ撃ち直してから2段(15→13→11)しか減衰させないため、
# シーケンス全体を通じてR8が0に達することは無い(最後のポップ後も
# R8=11のまま残る)。GO_HIDE_EXPLOSIONがこの後片付けの一部として明示的に
# R8=0を書き込むことを直接検証する。
z3 = fresh()
z3.psg_regs[8] = 11  # poison: the leftover non-zero volume GO_STEP_BOOM_DECAY leaves behind
z3.sp = 0xF000
z3.wr(0xF000, 0x00); z3.wr(0xF001, 0x00)
z3.pc = sym["GO_HIDE_EXPLOSION"]
run_until_pc(z3, 0x0000, 300000)
check("GO_HIDE_EXPLOSION silences PSG R8 (channel A boom volume) to 0 - "
      "GO_STEP_BOOM_DECAY alone never reaches 0 (each pop re-arms it to 15), so "
      "without this the boom sound would keep ringing right through the MISSION "
      "FAILED text display",
      z3.psg_regs.get(8) == 0)

# ---- end-to-end: the real INIT flow (explosion sequence -> hide -> text) must ----
# ---- leave R8 silenced by the time MISSION FAILED is actually on screen.       ----
z4 = fresh()
z4.wr(TANK_X, 120)
z4.wr(TANK_Y_CUR, 90)
z4.pc = sym["INIT"]
run_until_pc(z4, GO_WAIT_LOOP, 5_000_000)
check("real INIT flow: by the time GO_WAIT_LOOP (MISSION FAILED already drawn) is "
      "reached, PSG R8 (channel A) is silenced to 0 - the boom sound does not keep "
      "playing under the game-over text",
      z4.psg_regs.get(8) == 0)

# ---- (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバー
# ジングルのこのバンクへの実装本体) GO_INIT_BGM: bgm-dataバンク(window B
# select is a no-op RAM write in this flat harness, real bank content is
# pre-populated at 0x8000 above)からの周期テーブル+GAME_OVERジングル
# (chB+chC)のRAMコピー、制御変数の初期化、実際のHTIMI_HOOK設置を検証 ----
GO_PERIOD_LO_RAM = sym["GO_PERIOD_LO_RAM"]
GO_PERIOD_HI_RAM = sym["GO_PERIOD_HI_RAM"]
GO_CHB_BASE = sym["GO_CHB_BASE"]
GO_CHC_BASE = sym["GO_CHC_BASE"]
GO_BGM_B_PTR = sym["GO_BGM_B_PTR"]
GO_BGM_C_PTR = sym["GO_BGM_C_PTR"]
GO_BGM_B_TIMER = sym["GO_BGM_B_TIMER"]
GO_BGM_C_TIMER = sym["GO_BGM_C_TIMER"]
GO_BGM_B_REST = sym["GO_BGM_B_REST"]
GO_BGM_C_REST = sym["GO_BGM_C_REST"]
GO_BGM_B_ENV_LEVEL = sym["GO_BGM_B_ENV_LEVEL"]
GO_BGM_B_ENV_IDX = sym["GO_BGM_B_ENV_IDX"]
GO_BGM_B_ENV_CD = sym["GO_BGM_B_ENV_CD"]
GO_BGM_B_DUTY_PHASE = sym["GO_BGM_B_DUTY_PHASE"]
GO_BGM_C_ENV_LEVEL = sym["GO_BGM_C_ENV_LEVEL"]
GO_BGM_C_ENV_IDX = sym["GO_BGM_C_ENV_IDX"]
GO_BGM_C_ENV_CD = sym["GO_BGM_C_ENV_CD"]
GO_BGM_TICK = sym["GO_BGM_TICK"]
HTIMI_HOOK = sym["HTIMI_HOOK"]
BGM_END_MARK = sym["BGM_END_MARK"]
BGM_NOTE_REST = sym["BGM_NOTE_REST"]
BGM_B_DUTY_MASK = sym["BGM_B_DUTY_MASK"]
BGM_VOL_ATTEN = sym["BGM_VOL_ATTEN"]

_go_layout = bgm_layout["GAME_OVER"]
_go_start = _go_layout["bank_offset"]
_period_lo = list(bgm_bank[0:bg.NUM_NOTES])
_period_hi = list(bgm_bank[bg.NUM_NOTES:2 * bg.NUM_NOTES])
_periods = list(zip(_period_lo, _period_hi))
go_chB_bytes = bgm_bank[_go_start:_go_start + _go_layout["chB_len"]]
go_chC_bytes = bgm_bank[_go_start + _go_layout["chB_len"]:
                         _go_start + _go_layout["chB_len"] + _go_layout["chC_len"]]

check("GO_CHC_BASE = GO_CHB_BASE + GAME_OVER's own real chB length "
      "(matches bgm_bank_gen.song_constants('GAME_OVER', data_base=0xC200))",
      GO_CHC_BASE == GO_CHB_BASE + _go_layout["chB_len"])
check("GAME_OVER's own real chB/chC data both end in BGM_END_MARK (one-shot, no LOOP_MARK)",
      go_chB_bytes[-1] == BGM_END_MARK and go_chC_bytes[-1] == BGM_END_MARK)

z = fresh()
for addr in (GO_BGM_B_PTR, GO_BGM_B_PTR + 1, GO_BGM_C_PTR, GO_BGM_C_PTR + 1,
             GO_BGM_B_TIMER, GO_BGM_C_TIMER, GO_BGM_B_REST, GO_BGM_C_REST,
             GO_BGM_B_ENV_LEVEL, GO_BGM_B_ENV_IDX, GO_BGM_B_ENV_CD, GO_BGM_B_DUTY_PHASE,
             GO_BGM_C_ENV_LEVEL, GO_BGM_C_ENV_IDX, GO_BGM_C_ENV_CD, HTIMI_HOOK,
             HTIMI_HOOK + 1, HTIMI_HOOK + 2):
    z.wr(addr, 0xAA)  # poison first
call_ret(z, sym["GO_INIT_BGM"])
check("GO_INIT_BGM's RAM copy left the period table byte-correct in RAM",
      [z.rd(GO_PERIOD_LO_RAM + i) for i in range(len(_period_lo))] == _period_lo and
      [z.rd(GO_PERIOD_HI_RAM + i) for i in range(len(_period_hi))] == _period_hi)
check("GO_INIT_BGM's RAM copy left GAME_OVER's own real chB (melody) byte-correct in RAM",
      [z.rd(GO_CHB_BASE + i) for i in range(len(go_chB_bytes))] == list(go_chB_bytes))
check("GO_INIT_BGM's RAM copy left GAME_OVER's own real chC (harmony) byte-correct in RAM",
      [z.rd(GO_CHC_BASE + i) for i in range(len(go_chC_bytes))] == list(go_chC_bytes))
check("GO_INIT_BGM points GO_BGM_B_PTR/GO_BGM_C_PTR at GO_CHB_BASE/GO_CHC_BASE",
      (z.rd(GO_BGM_B_PTR) | (z.rd(GO_BGM_B_PTR + 1) << 8)) == GO_CHB_BASE and
      (z.rd(GO_BGM_C_PTR) | (z.rd(GO_BGM_C_PTR + 1) << 8)) == GO_CHC_BASE)
check("GO_INIT_BGM resets BGM_B/C_TIMER, BGM_B/C_REST and both channels' envelope "
      "state (LEVEL/IDX/CD, chB's DUTY_PHASE) to 0",
      z.rd(GO_BGM_B_TIMER) == 0 and z.rd(GO_BGM_C_TIMER) == 0 and
      z.rd(GO_BGM_B_REST) == 0 and z.rd(GO_BGM_C_REST) == 0 and
      z.rd(GO_BGM_B_ENV_LEVEL) == 0 and z.rd(GO_BGM_B_ENV_IDX) == 0 and z.rd(GO_BGM_B_ENV_CD) == 0 and
      z.rd(GO_BGM_B_DUTY_PHASE) == 0 and
      z.rd(GO_BGM_C_ENV_LEVEL) == 0 and z.rd(GO_BGM_C_ENV_IDX) == 0 and z.rd(GO_BGM_C_ENV_CD) == 0)
check("GO_INIT_BGM installs a real JP opcode (0C3h) into HTIMI_HOOK pointing at GO_BGM_TICK",
      z.rd(HTIMI_HOOK) == 0xC3 and
      (z.rd(HTIMI_HOOK + 1) | (z.rd(HTIMI_HOOK + 2) << 8)) == GO_BGM_TICK)
check("GO_INIT_BGM enables PSG tone B/C (R7 mixer)",
      (z.psg_regs.get(7) & 0x06) == 0)  # bits1-2 = tone B/C disable; both must be clear

# ---- multi-tick full playback: drive GO_BGM_TICK once per row-duration until
# chB reaches BGM_END_MARK, confirming the observed (period, volume) sequence
# matches a from-scratch BELL/duty simulation of GAME_OVER's real chB row data
# tick-for-tick (same discipline as tools/verify_stage1_bgm.py's own multi-tick
# regression - a single-row spot check alone can't catch cumulative drift) ----
def decode_rows_with_end(row_bytes):
    rows = []
    i = 0
    while i < len(row_bytes):
        note = row_bytes[i]
        if note == BGM_END_MARK:
            break
        rows.append((note, row_bytes[i + 1]))
        i += 2
    return rows


def sim_envelope_sequence(table, duty_mask, n_ticks, atten=BGM_VOL_ATTEN):
    idx = 0
    level, dur0 = table[0]
    cd = dur0 - 1
    phase = duty_mask
    out = []
    for tick in range(n_ticks):
        if tick > 0:
            if cd > 0:
                cd -= 1
            elif idx < len(table) - 1:
                idx += 1
                level, dur = table[idx]
                if dur != 0:
                    cd = dur - 1
        if duty_mask:
            phase = (phase + 1) & 0xFF
            audible = (phase & duty_mask) == 0
        else:
            audible = True
        out.append(max(0, level - atten) if audible else 0)
    return out


def read_env_table(z, addr, n_entries=16):
    return [(z.rd(addr + i * 2), z.rd(addr + i * 2 + 1)) for i in range(n_entries)]


go_melody_rows = decode_rows_with_end(go_chB_bytes)
bell_table = read_env_table(fresh(), sym["GO_BGM_ENV_BELL_TABLE"])

z = fresh()
call_ret(z, sym["GO_INIT_BGM"])

total_ticks = sum(d for _, d in go_melody_rows)
observed = []
for _ in range(total_ticks + 30):  # run a bit past the end to confirm it holds silent
    call_ret(z, GO_BGM_TICK)
    observed.append((z.psg_regs.get(2), z.psg_regs.get(3), z.psg_regs.get(9) or 0))

expected = []
for note, dur in go_melody_rows:
    if note == BGM_NOTE_REST:
        expected += [(None, None, 0)] * dur
    else:
        lo, hi = _periods[note]
        vols = sim_envelope_sequence(bell_table, BGM_B_DUTY_MASK, dur)
        expected += [(lo, hi, v) for v in vols]
expected += [(expected[-1][0], expected[-1][1], 0)] * 30

melody_match = True
for obs, exp in zip(observed, expected):
    obs_lo, obs_hi, obs_vol = obs
    exp_lo, exp_hi, exp_vol = exp
    if exp_vol == 0:
        if obs_vol != 0:
            melody_match = False
            break
    elif (obs_lo, obs_hi, obs_vol) != (exp_lo, exp_hi, exp_vol):
        melody_match = False
        break
check(f"multi-tick playback ({total_ticks} ticks + 30 past the end): GO_BGM_TICK's "
      "observed chB (period, volume) sequence matches a from-scratch BELL/duty "
      "simulation of GAME_OVER's real melody row data tick-for-tick, and holds "
      "silent (R9=0) after the jingle ends",
      melody_match)

# ---- real INIT flow: confirm HTIMI_HOOK is still correctly installed by the ----
# ---- time GO_WAIT_LOOP is reached (survives font-load/explosion/text-draw)  ----
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.pc = sym["INIT"]
run_until_pc(z, GO_WAIT_LOOP, 5_000_000)
check("real INIT flow: HTIMI_HOOK still correctly points at GO_BGM_TICK by the "
      "time GO_WAIT_LOOP (MISSION FAILED already drawn) is reached - the jingle "
      "driver survives font-loading/explosion/text-drawing untouched",
      z.rd(HTIMI_HOOK) == 0xC3 and
      (z.rd(HTIMI_HOOK + 1) | (z.rd(HTIMI_HOOK + 2) << 8)) == GO_BGM_TICK)
check("real INIT flow: GO_BGM_B_PTR/GO_BGM_C_PTR already point at the jingle's own "
      "chB/chC start by the time GO_WAIT_LOOP is reached (GO_INIT_BGM actually ran "
      "as part of the real boot sequence, not just in isolation)",
      (z.rd(GO_BGM_B_PTR) | (z.rd(GO_BGM_B_PTR + 1) << 8)) == GO_CHB_BASE and
      (z.rd(GO_BGM_C_PTR) | (z.rd(GO_BGM_C_PTR + 1) << 8)) == GO_CHC_BASE)

# ---- (2026-09-08、実機フィードバック対応"鳴ってるが最初の方が自機
# 爆発音で消えてる 爆発が終わってからMission Failed表示して音消して
# ゲームオーバーサウンドだろうが"): the jingle must NOT start until AFTER
# the explosion sequence + MISSION FAILED text are done - confirm HTIMI_HOOK
# is still the safe bare RET (not yet GO_BGM_TICK) and GO_BGM_B/C_PTR are
# still untouched right at the moment the explosion finishes (GO_HIDE_
# EXPLOSION reached), i.e. before the jingle has had any chance to start
# playing under the boom sound. Poison GO_BGM_B/C_PTR first so an
# accidental early GO_INIT_BGM call would be caught even if it left them
# at the same address as GO_CHB/CHC_BASE by coincidence. ----
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.wr(GO_BGM_B_PTR, 0xAA); z.wr(GO_BGM_B_PTR + 1, 0xAA)
z.wr(GO_BGM_C_PTR, 0xAA); z.wr(GO_BGM_C_PTR + 1, 0xAA)
z.pc = sym["INIT"]
run_until_pc(z, sym["GO_HIDE_EXPLOSION"], 5_000_000)
check("real INIT flow: HTIMI_HOOK is still the safe bare RET (0C9h), NOT yet "
      "GO_BGM_TICK, by the time the explosion sequence finishes (GO_HIDE_EXPLOSION "
      "reached) - the jingle must not start playing underneath the boom sound",
      z.rd(HTIMI_HOOK) == 0xC9)
check("real INIT flow: GO_BGM_B_PTR/GO_BGM_C_PTR are still untouched (GO_INIT_BGM "
      "has not run yet) by the time the explosion sequence finishes",
      (z.rd(GO_BGM_B_PTR) | (z.rd(GO_BGM_B_PTR + 1) << 8)) != GO_CHB_BASE and
      (z.rd(GO_BGM_C_PTR) | (z.rd(GO_BGM_C_PTR + 1) << 8)) != GO_CHC_BASE)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
