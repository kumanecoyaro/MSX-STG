"""Verifies the "Comb" build (build_full_rom.py, round39: title screen +
Stage1 + the REAL tools/stage2_combined content) actually boots correctly
end to end in the emulator - exercises the exact production functions
(assemble_title/assemble_game/assemble_real_stage2), not a
reimplementation.

Round39 layout: bank0/1=title screen (boots here by ASCII16 hardware
convention), bank2/3=Stage1 (was 0/1 pre-round39), bank4/5=Stage2 (was
2/3 pre-round39). This test walks the WHOLE chain: title's own INIT ->
(simulated button press) -> Stage1's real MAINLOOP -> (simulated boss
kill + flyaway) -> the real Stage2's own INIT -> its own MAINLOOP,
checking the bank-select state at each hop.

The specific risk this checks, same as before round39 (now at bank4/5
instead of 2/3): combined_test.asm's own INIT does its own one-time
bank-select for window B, hardcoded as "select MY bank 1" in its own
standalone 2-bank numbering. Embedded here it's actually global bank
index 5, not 1 - assemble_real_stage2() patches that on an in-memory
copy (see build_full_rom.py's STAGE2_BANKSELECT_ANCHOR/PATCH). If that
patch were ever wrong or silently stopped applying, stage2's own INIT
would instead select bank index 1 (Stage1's OWN page2 content) for
window B, corrupting window B right at the start of stage2's boot. This
test would catch that as bankB != 5 after the switch.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
sys.path.insert(0, HERE)
import z80emu
from build_full_rom import assemble_title, assemble_game, assemble_real_stage2, assemble_gameover_bank
import bgm_bank_gen as bg


class BankedMem:
    """6-bank ASCII16 mapper emulation matching the real Comb ROM's own
    global bank numbering exactly (0=title page1, 1=title page2,
    2=Stage1 page1, 3=Stage1 page2, 4=Stage2 page1, 5=Stage2 page2) -
    same shape as verify_full.py's own BankedMem."""
    def __init__(self, banksA, banksB, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = banksA
        self.banksB = banksB
        self.bankA = 0
        self.bankB = 0
        self.portA = portA
        self.portB = portB
        self.switch_log = []

    def __getitem__(self, addr):
        addr &= 0xFFFF
        if 0x4000 <= addr <= 0x7FFF:
            return self.banksA[self.bankA][addr - 0x4000]
        if 0x8000 <= addr <= 0xBFFF:
            return self.banksB[self.bankB][addr - 0x8000]
        return self.flat[addr]

    def __setitem__(self, addr, val):
        addr &= 0xFFFF
        val &= 0xFF
        if addr == self.portA:
            self.bankA = val % len(self.banksA)
            self.switch_log.append(("A", val, self.bankA))
            return
        if addr == self.portB:
            self.bankB = val % len(self.banksB)
            self.switch_log.append(("B", val, self.bankB))
            return
        if 0x4000 <= addr <= 0xBFFF:
            return
        self.flat[addr] = val


title_bank0, title_bank1, tsym = assemble_title()
game_bank0, game_bank1, gsym = assemble_game()
bank4, bank5, s2sym = assemble_real_stage2()
gameover_bank, gosym = assemble_gameover_bank()

assert "BOSS_SPAWN_TICK" in s2sym, "stage2 symtab missing BOSS_SPAWN_TICK - not the real stage2_combined content?"
print("confirmed: bank4/bank5 are the real stage2_combined content (BOSS_SPAWN_TICK present)")

# Both lists are indexed by GLOBAL bank number (0-7), matching the real
# ROM's own file layout (build_full_rom.py's rom96 concatenation order):
# window A only ever actually selects 0/2/4/7 (title/Stage1/Stage2 page1/
# GAME_OVER bank), window B only ever actually selects 1/3/5 (title/
# Stage1/Stage2 page2) AND, round40, 6 (the new BGM data bank -
# title/Stage2's own INIT_BGM each temporarily select it for windowB
# before restoring their own real page2 bank) - the other indices in each
# list are never read by this test's own code paths and are filled with
# dummy placeholders purely so the % modulo in __setitem__ has a dense
# list to index into. bank7 (window A only, GAME_OVER bank) is real
# content in banksA but stays a dummy in banksB (it never selects
# window B itself, matching gameover_bank.asm's own "window A only"
# design - see combined_test.asm's TRIGGER_GAME_OVER).
bgm_bank, bgm_layout = bg.build_bank()
dummy = bytearray([0xFF] * 0x4000)
mem = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy, gameover_bank],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5, bytearray(bgm_bank), dummy],
)
cpu = z80emu.Z80(mem)
cpu.pc = tsym["INIT"]
cpu.sp = 0xF380  # title_test.asm's own STACKTOP

# ---- stage 0: title screen boots, sits in WAIT_FOR_START until the ----
# ---- trigger button reads pressed (simulated via z80emu's own       ----
# ---- sim_trig_a, same GTTRIG mechanism every other stage uses)       ----
WAIT_FOR_START = tsym["WAIT_FOR_START"]
steps0 = 0
while cpu.pc != WAIT_FOR_START and steps0 < 2_000_000:
    cpu.step()
    steps0 += 1
assert cpu.pc == WAIT_FOR_START, "title screen's own INIT never reached WAIT_FOR_START"
print(f"title screen reached WAIT_FOR_START after {steps0} steps, bankA={mem.bankA} bankB={mem.bankB} "
      "(expect A=0,B=1 - round40: INIT_BGM's own temporary switch to bank6 then explicit restore to bank1, "
      "no longer B=0's undefined pre-round40 default)")
assert mem.bankA == 0 and mem.bankB == 1, \
    "title screen's own boot left window B on an unexpected bank (INIT_BGM should have restored bank1)"

# round40: confirm INIT_BGM's own real windowB->bank6->bank1 copy left
# the real ALONE_FIGHTER song genuinely correct in RAM (title and Stage1
# share this exact copy - Stage1 never does its own bank-switch, see its
# own INIT_BGM comment) before moving on to the trampoline.
_af = bgm_layout["ALONE_FIGHTER"]
_period_lo = list(bgm_bank[0:bg.NUM_NOTES])
_period_hi = list(bgm_bank[bg.NUM_NOTES:2 * bg.NUM_NOTES])
_song_start = _af["bank_offset"]
_chB = bgm_bank[_song_start:_song_start + _af["chB_len"]]
_chC = bgm_bank[_song_start + _af["chB_len"]:_song_start + _af["chB_len"] + _af["chC_len"]]
_period_lo_ram = tsym["BGM_PERIOD_LO_RAM"]
_period_hi_ram = tsym["BGM_PERIOD_HI_RAM"]
_chB_ram = tsym["BGM_B_BASE"]
_chC_ram = tsym["BGM_C_BASE"]
assert [mem.flat[_period_lo_ram + i] for i in range(len(_period_lo))] == _period_lo, \
    "title's own BGM RAM copy: period table (lo) mismatch"
assert [mem.flat[_period_hi_ram + i] for i in range(len(_period_hi))] == _period_hi, \
    "title's own BGM RAM copy: period table (hi) mismatch"
assert [mem.flat[_chB_ram + i] for i in range(len(_chB))] == list(_chB), \
    "title's own BGM RAM copy: ALONE_FIGHTER chB mismatch"
assert [mem.flat[_chC_ram + i] for i in range(len(_chC))] == list(_chC), \
    "title's own BGM RAM copy: ALONE_FIGHTER chC mismatch"
# ユーザー指示("タイトルBGMも停止 まともになるまでCombのみで"):
# RAMコピー自体はStage1用に維持するが、title自身のINIT_BGMはHTIMI_HOOK
# の設置(=BGM_TICKを実際にH.TIMI駆動する部分)は意図的にスキップする
# (タイトル画面自身は無音のまま)。
# (2026-09-07、実機フィードバック対応"Mission1でゲームオーバー処理の
# あとタイトルに遷移しない"): ただしtitleのINIT冒頭(INIT_BGMより前、
# DI直後・CALL INIGRPより前)は、Stage1/Stage2からの"タイトルへ戻る"
# トランポリン再入時に残るかもしれない古いHTIMI_HOOK(送り手側自身の
# BGM_TICKアドレス、このバンクに切り替わった今は無関係なコードを指す)
# への防御として、明示的にbare RET(0C9h)へリセットするよう変更した
# (INIT_BGM自身が設置する訳ではない点は変わらない)。よってHTIMI_HOOKは
# 0x00(未初期化)ではなく0xC9になっているはず。
assert mem.flat[tsym["HTIMI_HOOK"]] == 0xC9, \
    "title's own INIT should have defensively reset HTIMI_HOOK to a bare RET (0xC9) right " \
    "after DI (INIT_BGM itself still never arms it - title BGM stays intentionally disabled)"
print("title's own BGM RAM copy (period table + ALONE_FIGHTER chB/chC) verified byte-correct, "
      "HTIMI_HOOK defensively reset to bare RET (title BGM itself still disabled)")

# 実機フィードバック対応("ステージ1ボスもBGMをTryZに"): TitleはStage1の
# ボス曲用にTryZのchB+chCも(ALONE_FIGHTERと同じ要領で)別アドレスへ
# 一度だけコピーする。Stage1側の固定アドレス(src/CYBER SHMUP.asmの
# BGM_TRYZ_CHB/CHC_BASE)と一致することを確認。
_tryz = bgm_layout["BOSS_TRYZ"]
_tryz_start = _tryz["bank_offset"]
_tryz_chB = bgm_bank[_tryz_start:_tryz_start + _tryz["chB_len"]]
_tryz_chC = bgm_bank[_tryz_start + _tryz["chB_len"]:_tryz_start + _tryz["chB_len"] + _tryz["chC_len"]]
_tryz_chB_ram = gsym["BGM_TRYZ_CHB_BASE"]
_tryz_chC_ram = gsym["BGM_TRYZ_CHC_BASE"]
assert [mem.flat[_tryz_chB_ram + i] for i in range(len(_tryz_chB))] == list(_tryz_chB), \
    "title's own BGM RAM copy: TryZ chB mismatch (Stage1 boss BGM)"
assert [mem.flat[_tryz_chC_ram + i] for i in range(len(_tryz_chC))] == list(_tryz_chC), \
    "title's own BGM RAM copy: TryZ chC mismatch (Stage1 boss BGM)"
print("title's own BGM RAM copy of TryZ (Stage1 boss theme) verified byte-correct")

# (2026-09-06、"ではステージ1と2のスコアを加算して...これをステージ
# クリアで流して 3音使って良いんで"): TitleはStage1のステージクリア
# ジングル用にStageClearの3パート(melody=chB/bass=chC/harmony=chA)も
# TryZと同じ要領で別アドレスへ一度だけコピーする。
_sc = bgm_layout["STAGE_CLEAR"]
_sc_start = _sc["bank_offset"]
_sc_chB = bgm_bank[_sc_start:_sc_start + _sc["chB_len"]]
_sc_chC = bgm_bank[_sc_start + _sc["chB_len"]:_sc_start + _sc["chB_len"] + _sc["chC_len"]]
_sc_chA = bgm_bank[_sc_start + _sc["chB_len"] + _sc["chC_len"]:
                    _sc_start + _sc["chB_len"] + _sc["chC_len"] + _sc["chA_len"]]
_sc_chB_ram = gsym["STAGE_CLEAR_CHB_BASE"]
_sc_chC_ram = gsym["STAGE_CLEAR_CHC_BASE"]
_sc_chA_ram = gsym["STAGE_CLEAR_CHA_BASE"]
assert [mem.flat[_sc_chB_ram + i] for i in range(len(_sc_chB))] == list(_sc_chB), \
    "title's own BGM RAM copy: StageClear chB mismatch (Stage1 stage-clear jingle)"
assert [mem.flat[_sc_chC_ram + i] for i in range(len(_sc_chC))] == list(_sc_chC), \
    "title's own BGM RAM copy: StageClear chC mismatch (Stage1 stage-clear jingle)"
assert [mem.flat[_sc_chA_ram + i] for i in range(len(_sc_chA))] == list(_sc_chA), \
    "title's own BGM RAM copy: StageClear chA mismatch (Stage1 stage-clear jingle)"
print("title's own BGM RAM copy of StageClear (Stage1 stage-clear jingle) verified byte-correct")

# (2026-09-08、"ではゲームオーバーBGM...これで組み込んでくれ"): Titleは
# Stage1のゲームオーバージングル用にGAME_OVERの2パート(melody=chB/
# harmony=chC)もTryZ/StageClearと同じ要領で別アドレスへ一度だけコピー
# する。Stage1側の固定アドレス(src/CYBER SHMUP.asmのBGM_GAMEOVER_CHB/
# CHC_BASE)と一致することを確認。
_go = bgm_layout["GAME_OVER"]
_go_start = _go["bank_offset"]
_go_chB = bgm_bank[_go_start:_go_start + _go["chB_len"]]
_go_chC = bgm_bank[_go_start + _go["chB_len"]:_go_start + _go["chB_len"] + _go["chC_len"]]
_go_chB_ram = gsym["BGM_GAMEOVER_CHB_BASE"]
_go_chC_ram = gsym["BGM_GAMEOVER_CHC_BASE"]
assert [mem.flat[_go_chB_ram + i] for i in range(len(_go_chB))] == list(_go_chB), \
    "title's own BGM RAM copy: GAME_OVER chB mismatch (Stage1 game-over jingle)"
assert [mem.flat[_go_chC_ram + i] for i in range(len(_go_chC))] == list(_go_chC), \
    "title's own BGM RAM copy: GAME_OVER chC mismatch (Stage1 game-over jingle)"
print("title's own BGM RAM copy of GAME_OVER (Stage1 game-over jingle) verified byte-correct")

# (2026-09-12、実機フィードバック"アニメが指示と違う 流れは まず1から
# 6枚目を3フレ切り替え で7枚目の08を15フレ表示 ここまでを3ループ
# その後09を30フレ 11を90フレ表示してMission 1表示"): ボタン押下後は
# 本物のROMだとRUN_SCREEN3_SLIDESHOW(1-6枚目x3フレーム+Epilogue1
# x15フレームを3周+Epilogue2x30フレーム+Epilogue3x90フレーム、確認音
# SC3_CONFIRM_TICKをH.TIMI駆動でアニメーション全体を通じて再生)経由に
# なり、実時間で数秒相当のbusy-waitをPythonエミュレータで1命令ずつ
# 実行することになる。tools/title_screen/title_test.pyの「button
# press trampolines」テストと同じ手法(real ROM自体は無変更、この
# テスト用のtitle_bank0コピーだけディレイを短縮するパッチ)をここでも
# 適用する。
_RSS_MAIN_LOOP_COUNT_ADDR = tsym["RUN_SCREEN3_SLIDESHOW"] + 0x48  # "LD B,3" operand
_WAIT_3F_DE_ADDR = tsym["WAIT_3_FRAMES"] + 1                       # "LD DE,6884" operand (2 bytes)
_WAIT_1F_DE_ADDR = tsym["WAIT_1_FRAME_UNIT"] + 1                   # "LD DE,2295" operand (2 bytes)
assert mem.banksA[0][_RSS_MAIN_LOOP_COUNT_ADDR - 0x4000] == 3
assert mem.banksA[0][_WAIT_3F_DE_ADDR - 0x4000] == (6884 & 0xFF)
assert (mem.banksA[0][_WAIT_1F_DE_ADDR - 0x4000]
        | (mem.banksA[0][_WAIT_1F_DE_ADDR + 1 - 0x4000] << 8)) == 2295
mem.banksA[0][_WAIT_3F_DE_ADDR - 0x4000] = 5
mem.banksA[0][_WAIT_3F_DE_ADDR + 1 - 0x4000] = 0
mem.banksA[0][_WAIT_1F_DE_ADDR - 0x4000] = 5
mem.banksA[0][_WAIT_1F_DE_ADDR + 1 - 0x4000] = 0

cpu.sim_trig_a = True
print("simulated PUSH START (sim_trig_a=True)")

GAME_INIT = gsym["INIT"]
switched0 = False
steps0b = 0
while steps0b < 10_000_000:
    if cpu.pc == GAME_INIT and mem.bankA == 2:
        switched0 = True
        break
    cpu.step()
    steps0b += 1
assert switched0, "title screen never trampolined into Stage1's INIT (bank2) within step budget"
assert mem.bankA == 2 and mem.bankB == 3, "banks not switched to Stage1 (2,3) on entry to its INIT"
# 実機フィードバック対応("バンク切り替えに失敗してる タイトルでボタンを
# 押すとフリーズ"): title_test.asm's own WAIT_FOR_START fix - interrupts
# must already be disabled by the moment the trampoline lands here, or
# a stale H.TIMI hook could fire over window A's freshly-switched Stage1
# content before Stage1's own DI ever runs.
assert cpu.iff1 is False, \
    "interrupts still enabled on entry to Stage1's INIT - the hop1/hop2 H.TIMI race is back"
print(f"title -> Stage1 trampoline: after {steps0b} more steps, pc={cpu.pc:04x} bankA={mem.bankA} bankB={mem.bankB}")

# ---- stage 1: Stage1's own real boot (unchanged from pre-round39, ----
# ---- just relocated to bank2/3) ----
MAINLOOP = gsym["MAINLOOP"]
PLAYER_FLYAWAY = gsym["PLAYER_FLYAWAY"]

steps = 0
while cpu.pc != MAINLOOP and steps < 2_000_000:
    cpu.step()
    steps += 1
print(f"stage1 reached MAINLOOP after {steps} steps, bankA={mem.bankA} bankB={mem.bankB} (expect A=2,B=3)")
assert cpu.pc == MAINLOOP
assert mem.bankA == 2 and mem.bankB == 3, "stage1's own explicit bank select did not take effect"

# round40: Stage1 does no bank-switching or RAM copy of its own (see its
# own INIT_BGM comment) - it just re-arms HTIMI_HOOK to point at ITS OWN
# resident BGM_TICK (a different address than title's own copy) and
# trusts that the RAM title already populated (checked above, still
# untouched - Stage1 never writes BGM_B_BASE/BGM_C_BASE/BGM_PERIOD_*_RAM
# itself) is still there.
assert mem.flat[gsym["HTIMI_HOOK"]] == 0xC3 and \
    (mem.flat[gsym["HTIMI_HOOK"] + 1] | (mem.flat[gsym["HTIMI_HOOK"] + 2] << 8)) == gsym["BGM_TICK"], \
    "Stage1's own INIT_BGM did not re-arm HTIMI_HOOK -> its own BGM_TICK"
assert gsym["BGM_TICK"] != tsym["BGM_TICK"], \
    "sanity: Stage1 and title assembled to the same BGM_TICK address - HTIMI_HOOK check above would be meaningless"
assert [mem.flat[_chB_ram + i] for i in range(len(_chB))] == list(_chB), \
    "ALONE_FIGHTER chB in RAM was disturbed between title and Stage1 - Stage1 must not touch it"
print("Stage1's own INIT_BGM re-armed HTIMI_HOOK to its own BGM_TICK; title's earlier RAM copy is still intact")

mem.flat[PLAYER_FLYAWAY] = 2
print("poked PLAYER_FLYAWAY=2 (simulating boss-destroyed + flyaway-complete)")

# (2026-09-06、"ではステージ1と2のスコアを加算して...ステージで
# 引き継ぐ様に"): poke a known, distinctive Stage1 SCORE value now (RAM
# is flat/shared across bank switches, so this survives untouched all the
# way through to Stage2's own INIT further below) and confirm Stage2's
# own SCORE reads back the same value once its INIT has run.
STAGE1_SCORE = gsym["SCORE"]
_score_test_value = 0x123456
mem.flat[STAGE1_SCORE] = _score_test_value & 0xFF
mem.flat[STAGE1_SCORE + 1] = (_score_test_value >> 8) & 0xFF
mem.flat[STAGE1_SCORE + 2] = (_score_test_value >> 16) & 0xFF
print(f"poked Stage1 SCORE=0x{_score_test_value:06x} to verify stage-clear carryover into Stage2")

# (2026-09-06、"これをステージクリアで流して"、続けて"画面をブラックで
# 埋めてMISSION 2とセンターに表示 3秒でいいかな"): the switch trigger is
# no longer PLAYER_FLYAWAY==2 directly - TRIGGER_STAGE_CLEAR now arms
# first (STAGE_CLEAR_ACT=1) and repoints BGM_B/C/A_PTR at the StageClear
# jingle; UPDATE_STAGE_CLEAR then advances 1->2 (drawing the MISSION2
# black screen + muting BGM) once its own real-time clock reaches the
# jingle's total duration, and 2->3 (the Comb-only bank-switch trigger,
# see build_full_rom.py's MAINLOOP_PATCH) once a second real-time window
# (MISSION_SCREEN_TICKS) elapses. Both windows are driven by SC_VBLANK_
# COUNT (incremented from BGM_TICK - itself only ever fired by an actual
# H.TIMI interrupt, which this raw instruction-stepping harness never
# simulates, same as every other real vblank-driven timer in this
# script). Verifying those real-time waits would need hundreds of
# simulated vblank interrupts; this script's scope is the bank-switch
# mechanics, not the jingle/MISSION2 timing (that has its own coverage in
# tools/verify_stage1_bgm.py and tools/verify_stage1_mission_screens.py),
# so after confirming TRIGGER_STAGE_CLEAR actually fired and repointed
# the BGM channels, STAGE_CLEAR_ACT is poked directly to 3 (the final,
# switch-triggering state) to exercise the rest of the trampoline exactly
# as before.
STAGE_CLEAR_ACT = gsym["STAGE_CLEAR_ACT"]
steps1b = 0
while mem.flat[STAGE_CLEAR_ACT] != 1 and steps1b < 2_000_000:
    cpu.step()
    steps1b += 1
assert mem.flat[STAGE_CLEAR_ACT] == 1, "TRIGGER_STAGE_CLEAR never fired (STAGE_CLEAR_ACT stuck at 0)"
# TRIGGER_STAGE_CLEAR sets STAGE_CLEAR_ACT=1 as its very FIRST instruction
# (before the DI/EI block that actually repoints BGM_B/C/A_PTR), so the
# loop above breaks mid-routine - run a short, generous fixed margin of
# extra steps to let the rest of the routine (and the JP DIR_DONE right
# after it) finish before checking the pointers it sets.
for _ in range(200):
    cpu.step()
BGM_B_PTR, BGM_C_PTR, BGM_A_PTR = gsym["BGM_B_PTR"], gsym["BGM_C_PTR"], gsym["BGM_A_PTR"]
_got_b = mem.flat[BGM_B_PTR] | (mem.flat[BGM_B_PTR + 1] << 8)
_got_c = mem.flat[BGM_C_PTR] | (mem.flat[BGM_C_PTR + 1] << 8)
_got_a = mem.flat[BGM_A_PTR] | (mem.flat[BGM_A_PTR + 1] << 8)
assert _got_b == gsym["STAGE_CLEAR_CHB_BASE"], "TRIGGER_STAGE_CLEAR did not repoint BGM_B_PTR at the jingle"
assert _got_c == gsym["STAGE_CLEAR_CHC_BASE"], "TRIGGER_STAGE_CLEAR did not repoint BGM_C_PTR at the jingle"
assert _got_a == gsym["STAGE_CLEAR_CHA_BASE"], "TRIGGER_STAGE_CLEAR did not repoint BGM_A_PTR at the jingle"
print(f"StageClear jingle triggered after {steps1b} steps (STAGE_CLEAR_ACT=1, "
      f"BGM_B/C/A_PTR repointed at the jingle's 3 parts)")
mem.flat[STAGE_CLEAR_ACT] = 3
print("poked STAGE_CLEAR_ACT=3 (bypassing the jingle's + MISSION2 screen's own real-time "
      "waits, see comment above)")

STAGE2_INIT = s2sym["INIT"]
switched = False
steps2 = 0
while steps2 < 2_000_000:
    if cpu.pc == STAGE2_INIT and mem.bankA == 4:
        switched = True
        break
    cpu.step()
    steps2 += 1
print(f"after {steps2} more steps: pc={cpu.pc:04x} bankA={mem.bankA} bankB={mem.bankB}")
assert switched, "never reached real stage2's INIT (bank4) within step budget"
assert mem.bankA == 4 and mem.bankB == 5, "banks not switched to real stage2 (4,5) on entry to its INIT"
# same class of race as title->Stage1 above, now guarded on the
# Stage1->Stage2 (MAINLOOP_PATCH) trampoline too - see its own DI comment.
assert cpu.iff1 is False, \
    "interrupts still enabled on entry to Stage2's INIT - the hop1/hop2 H.TIMI race is back"

# Now run stage2's OWN boot (combined_test.asm's INIT does its own
# one-time window-B bank-select as part of booting standalone - this is
# the exact spot the STAGE2_BANKSELECT patch targets). Confirm bankB is
# either 5 (its own real content) or - round40 - briefly 6 (its own
# INIT_BGM's temporary switch to the BGM data bank, patched by
# STAGE2_BGM_BANKSELECT_ANCHOR/PATCH) at every point, NEVER anything
# else (in particular never the unpatched "1", which would mean either
# patch silently stopped applying), and that it's back on 5 by the time
# MAINLOOP is reached.
steps3 = 0
bad_bankB = None
saw_bank6 = False
while cpu.pc != s2sym["MAINLOOP"] and steps3 < 2_000_000:
    cpu.step()
    steps3 += 1
    if mem.bankB == 6:
        saw_bank6 = True
    elif mem.bankB != 5:
        bad_bankB = (steps3, mem.bankB, cpu.pc)
        break
assert bad_bankB is None, (
    f"bankB took an unexpected value during stage2's own boot: {bad_bankB} "
    "(the STAGE2_BANKSELECT_ANCHOR/PATCH or STAGE2_BGM_BANKSELECT_ANCHOR/PATCH retarget likely isn't taking effect)"
)
assert saw_bank6, "stage2's own INIT_BGM never selected bank6 (BGM data bank) - the BGM copy step didn't run?"
assert mem.bankB == 5, f"stage2 reached its own MAINLOOP with bankB={mem.bankB}, expected 5"
print(f"real stage2 reached its own MAINLOOP after {steps3} more steps, bankB visited 6 (BGM copy) then settled back on 5")
assert cpu.pc == s2sym["MAINLOOP"]

# confirm the score-carryover poked above actually landed in Stage2's own
# SCORE by the time its INIT finished (see the poke's own comment above).
STAGE2_SCORE = s2sym["SCORE"]
_got_score = (mem.flat[STAGE2_SCORE] | (mem.flat[STAGE2_SCORE + 1] << 8)
              | (mem.flat[STAGE2_SCORE + 2] << 16))
assert _got_score == _score_test_value, (
    f"Stage2's own SCORE (0x{_got_score:06x}) does not match the Stage1 SCORE carried over "
    f"(expected 0x{_score_test_value:06x}) - Stage2's INIT-time STAGE1_SCORE carryover copy is broken"
)
print(f"score carryover verified: Stage2's own SCORE == Stage1's SCORE (0x{_got_score:06x})")

# round40: confirm Stage2's own independent BGM copy (DEFEAT, at its own
# STAGE2_DATA_BASE=0xC200 - a different address range than title/Stage1's
# shared 0xC000, so there's no timing dependency on the earlier copy)
# left the real DEFEAT song genuinely correct in RAM, and armed HTIMI_HOOK
# to its own (3rd distinct) BGM_TICK address.
_defeat = bgm_layout["DEFEAT"]
_d_song_start = _defeat["bank_offset"]
_d_chB = bgm_bank[_d_song_start:_d_song_start + _defeat["chB_len"]]
_d_chC = bgm_bank[_d_song_start + _defeat["chB_len"]:_d_song_start + _defeat["chB_len"] + _defeat["chC_len"]]
assert [mem.flat[s2sym["BGM_PERIOD_LO_RAM"] + i] for i in range(len(_period_lo))] == _period_lo, \
    "Stage2's own BGM RAM copy: period table (lo) mismatch"
assert [mem.flat[s2sym["BGM_B_BASE"] + i] for i in range(len(_d_chB))] == list(_d_chB), \
    "Stage2's own BGM RAM copy: DEFEAT chB mismatch"
assert [mem.flat[s2sym["BGM_C_BASE"] + i] for i in range(len(_d_chC))] == list(_d_chC), \
    "Stage2's own BGM RAM copy: DEFEAT chC mismatch"
assert mem.flat[s2sym["HTIMI_HOOK"]] == 0xC3 and \
    (mem.flat[s2sym["HTIMI_HOOK"] + 1] | (mem.flat[s2sym["HTIMI_HOOK"] + 2] << 8)) == s2sym["BGM_TICK"], \
    "Stage2's own INIT_BGM did not arm HTIMI_HOOK -> its own BGM_TICK"
assert len({tsym["BGM_TICK"], gsym["BGM_TICK"], s2sym["BGM_TICK"]}) == 3, \
    "sanity: title/Stage1/Stage2 should all have distinct BGM_TICK addresses (3 separate assemblies)"
print("Stage2's own independent BGM RAM copy (DEFEAT) verified byte-correct, HTIMI_HOOK armed to its own BGM_TICK")

# (2026-09-07、実機フィードバック対応"Mission1でゲームオーバー処理の
# あとタイトルに遷移しない"): 上のメインチェーンはTitle->Stage1->Stage2
# しか辿らず、Stage1のGAME_OVER_SEQ==3->title復帰トランポリン(round59で
# 新規追加、build_full_rom.pyのMAINLOOP_PATCH参照)は一度もこのファイルで
# 検証されていなかった - この欠落自体がバグを見逃す一因だった。独立した
# 2周目のTitle->Stage1シーケンスを新たに走らせ、実際にBARRIER_HP=0の
# 状態でPLAYER_TAKE_HITを呼び、GAME_OVER_SEQが1(MISSION FAILED表示)に
# 上がることを確認した上で、実時間の3秒/10秒待ち自体は他の実時間タイマー
# 同様このハーネスでは検証しない(H.TIMI割り込みを一切発生させないため -
# UPDATE_GAME_OVER_SEQUENCE自身の単体ロジックはtools/verify_stage1_
# mission_screens.pyで別途カバー済み)方針を踏襲しつつ、GAME_OVER_SEQを
# 直接2へポークしてボタン押下(sim_trig_a)を模擬し、実際にtitleのINITへ
# 正しく2ホップトランポリンで戻ることを確認する。
print()
print("---- Stage1 GAME_OVER_SEQ==3 -> title trampoline (round59, previously untested here) ----")
mem2 = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5, bytearray(bgm_bank)],
)
cpu2 = z80emu.Z80(mem2)
cpu2.pc = tsym["INIT"]
cpu2.sp = 0xF380

steps_g0 = 0
while cpu2.pc != WAIT_FOR_START and steps_g0 < 2_000_000:
    cpu2.step()
    steps_g0 += 1
assert cpu2.pc == WAIT_FOR_START, "title screen (2nd run) never reached WAIT_FOR_START"

cpu2.sim_trig_a = True
steps_g1 = 0
switched_g1 = False
# 2026-09-12のSCREEN3スライドショー統合によりtitle_bank0(mem/mem2/mem3/
# mem4全てで共有される同一bytearray)は既に上のmemセクションでディレイ
# 短縮パッチ済み - それでも1周分(main_loop_count=1でもPLAY_CONFIRM_BEEP
# 複数回分)は依然として旧来の2,000,000を超えるため予算を拡大する。
while steps_g1 < 10_000_000:
    if cpu2.pc == GAME_INIT and mem2.bankA == 2:
        switched_g1 = True
        break
    cpu2.step()
    steps_g1 += 1
assert switched_g1, "title -> Stage1 (2nd run, for the game-over scenario) never trampolined"
cpu2.sim_trig_a = False

steps_g2 = 0
while cpu2.pc != MAINLOOP and steps_g2 < 2_000_000:
    cpu2.step()
    steps_g2 += 1
assert cpu2.pc == MAINLOOP, "Stage1 (2nd run) never reached its own MAINLOOP"

BARRIER_HP = gsym["BARRIER_HP"]
GAME_OVER_SEQ = gsym["GAME_OVER_SEQ"]
mem2.flat[BARRIER_HP] = 0
PLAYER_TAKE_HIT = gsym["PLAYER_TAKE_HIT"]
cpu2.sp -= 2
mem2.flat[cpu2.sp] = 0x00
mem2.flat[cpu2.sp + 1] = 0x00
cpu2.pc = PLAYER_TAKE_HIT
steps_g3 = 0
while cpu2.pc != 0x0000 and steps_g3 < 300000:
    cpu2.step()
    steps_g3 += 1
PLAYER_DEATH_FALL_ACT = gsym["PLAYER_DEATH_FALL_ACT"]
PLAYERY = gsym["PLAYERY"]
assert mem2.flat[PLAYER_DEATH_FALL_ACT] == 1, \
    "PLAYER_TAKE_HIT with BARRIER_HP=0 did not arm the death-fall sequence"
assert mem2.flat[GAME_OVER_SEQ] == 0, \
    "GAME_OVER_SEQ armed immediately - should be deferred until the death-fall finishes (round62-follow-up)"
# (2026-09-07、"操作無効の上爆発しながら右斜め下に落下しMission Failed
# 表示に"、続けて"斜め下に落下したらそのまま画面外に消えるように変更"、
# さらに"墜落速度が速いんで半分の速度に"でPLAYER_DEATH_FALL_SPEEDが
# 2->1へ半減): PLAYER_TAKE_HITはもうGAME_OVER_SEQを即座には起動しない -
# PLAYERYが実際に画面外(199)へ到達した瞬間(固定フレーム数ではなく、
# 開始位置からの距離で決まる可変長 - tools/verify_stage1_mission_
# screens.pyで単体検証済み)を経て初めて起動する。この統合テストでは
# 実時間同様、その待ち自体を短縮(あと1フレーム[速度1px/frame]で
# 到達する198へPLAYERYをポーク)した上で1フレームだけ実MAINLOOPを
# 回し、演出完了時の遷移が実バンク構成でも正しく配線されていることだけ
# を確認する。
mem2.flat[PLAYERY] = 198
cpu2.pc = MAINLOOP
cpu2.step()
steps_g3b = 0
while cpu2.pc != MAINLOOP and steps_g3b < 300000:
    cpu2.step()
    steps_g3b += 1
assert mem2.flat[GAME_OVER_SEQ] == 1, \
    "death-fall completion did not arm GAME_OVER_SEQ=1 (MISSION FAILED display)"
print("Stage1 (2nd run): real PLAYER_TAKE_HIT with BARRIER_HP=0 -> death-fall -> GAME_OVER_SEQ=1, as on real hardware")

# bypass the real-time 3s-text/10s-timeout waits (this harness never fires
# H.TIMI on its own, same limitation noted throughout this file for every
# other real-time state - see e.g. the STAGE_CLEAR_ACT poke above) and
# simulate a button press to move 2->3, matching UPDATE_GAME_OVER_
# SEQUENCE's own unit-tested transition (tools/verify_stage1_mission_
# screens.py already covers that transition's logic in isolation).
mem2.flat[GAME_OVER_SEQ] = 2
cpu2.sim_trig_a = True

TITLE_INIT = tsym["INIT"]
steps_g4 = 0
switched_back = False
while steps_g4 < 2_000_000:
    if cpu2.pc == TITLE_INIT and mem2.bankA == 0:
        switched_back = True
        break
    cpu2.step()
    steps_g4 += 1
assert switched_back, "Stage1's GAME_OVER_SEQ==3 trampoline never reached title's own INIT (bank0)"
assert mem2.bankA == 0 and mem2.bankB == 1, "banks not switched back to title (0,1) on game-over return"
assert cpu2.iff1 is False, \
    "interrupts still enabled on entry to title's INIT via the game-over trampoline - " \
    "the hop1/hop2 H.TIMI race is back"
print(f"Stage1 -> title (game-over trampoline) verified: bankA={mem2.bankA} bankB={mem2.bankB}, "
      f"interrupts correctly disabled on landing")

# the actual bug this round's investigation found: title's own INIT used
# to leave a STALE HTIMI_HOOK (still pointing at Stage1's own BGM_TICK,
# an address that's now meaningless once window A is re-mapped to title)
# untouched all the way to its own first EI, since title's INIT_BGM
# intentionally never arms/clears the hook itself (title stays silent).
# Confirm the defensive reset (added this round, right after INIT's own
# DI and before CALL INIGRP) actually landed by running a few more steps
# past the trampoline and checking the hook value.
for _ in range(300):
    cpu2.step()
assert mem2.flat[tsym["HTIMI_HOOK"]] == 0xC9, \
    "title's own INIT did not reset the stale HTIMI_HOOK (left over from Stage1's own BGM_TICK) " \
    "to a safe bare RET after being re-entered via the game-over trampoline"
print("title's own INIT correctly reset the stale HTIMI_HOOK (inherited from Stage1) to a safe bare RET")

# (2026-09-07、実機フィードバック対応"次にスタート2の自機爆発処理が
# おかしい"): Stage2自身のTANK_LIFE==0 -> TRIGGER_GAME_OVER ->
# GAME_OVERバンク(global bank7)ワンホップ切替 -> GO_TO_TITLEでtitleへ
# 2ホップ復帰、という一連の流れもこのファイルでは一度も検証されて
# いなかった(gameover_bank_test.pyはこのバンク単体のみ、combined_
# test.asm側のTRIGGER_GAME_OVER自体との統合は未検証だった)。3周目の
# 独立したTitle->Stage1->Stage2シーケンスを新たに走らせ、実際に
# TANK_LIFE=0でAPPLY_TANK_DAMAGEを呼んでGAME_OVERバンクへ切り替わる
# ことを確認した上で、GO_WAIT_LOOPのボタン待ちだけsim_trig_aで即座に
# 通過させ(GO_DELAY_SHORT/TINYはH.TIMI非依存の純粋なビジーウェイトの
# ため、原理上は最後まで実ステップ実行で通しきれるが、10秒分のCPU
# ステップは非現実的に重いため)、最終的にtitleのINITへ戻ることまで
# 一気通貫で確認する。
print()
print("---- Stage2 TANK_LIFE==0 -> GAME_OVER bank -> title trampoline (round59/round42, "
      "previously untested here) ----")
mem3 = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy, gameover_bank],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5, bytearray(bgm_bank), dummy],
)
cpu3 = z80emu.Z80(mem3)
cpu3.pc = tsym["INIT"]
cpu3.sp = 0xF380

steps_s2g0 = 0
while cpu3.pc != WAIT_FOR_START and steps_s2g0 < 2_000_000:
    cpu3.step()
    steps_s2g0 += 1
assert cpu3.pc == WAIT_FOR_START, "title screen (3rd run) never reached WAIT_FOR_START"

cpu3.sim_trig_a = True
steps_s2g1 = 0
switched_s2g1 = False
# (title_bank0のディレイ短縮パッチについては上のmem2セクションのコメント参照)
while steps_s2g1 < 10_000_000:
    if cpu3.pc == GAME_INIT and mem3.bankA == 2:
        switched_s2g1 = True
        break
    cpu3.step()
    steps_s2g1 += 1
assert switched_s2g1, "title -> Stage1 (3rd run, for the Stage2 game-over scenario) never trampolined"

steps_s2g2 = 0
while cpu3.pc != MAINLOOP and steps_s2g2 < 2_000_000:
    cpu3.step()
    steps_s2g2 += 1
assert cpu3.pc == MAINLOOP, "Stage1 (3rd run) never reached its own MAINLOOP"

mem3.flat[PLAYER_FLYAWAY] = 2
mem3.flat[STAGE_CLEAR_ACT] = 3
cpu3.sim_trig_a = False

steps_s2g3 = 0
switched_s2g3 = False
while steps_s2g3 < 2_000_000:
    if cpu3.pc == STAGE2_INIT and mem3.bankA == 4:
        switched_s2g3 = True
        break
    cpu3.step()
    steps_s2g3 += 1
assert switched_s2g3, "Stage1 -> real Stage2 (3rd run) never trampolined"

steps_s2g4 = 0
while cpu3.pc != s2sym["MAINLOOP"] and steps_s2g4 < 2_000_000:
    cpu3.step()
    steps_s2g4 += 1
assert cpu3.pc == s2sym["MAINLOOP"], "Stage2 (3rd run) never reached its own MAINLOOP"
print("Stage2 (3rd run): reached its own MAINLOOP, ready to drive a real TANK_LIFE==0 death")

TANK_LIFE = s2sym["TANK_LIFE"]
APPLY_TANK_DAMAGE = s2sym["APPLY_TANK_DAMAGE"]
mem3.flat[TANK_LIFE] = 1
cpu3.sp -= 2
mem3.flat[cpu3.sp] = 0x00
mem3.flat[cpu3.sp + 1] = 0x00
cpu3.pc = APPLY_TANK_DAMAGE
GAMEOVER_INIT = gosym["INIT"]
steps_s2g5 = 0
switched_s2g5 = False
while steps_s2g5 < 2_000_000:
    if cpu3.pc == GAMEOVER_INIT and mem3.bankA == 7:
        switched_s2g5 = True
        break
    cpu3.step()
    steps_s2g5 += 1
assert switched_s2g5, "APPLY_TANK_DAMAGE with TANK_LIFE=1 never trampolined into the GAME_OVER bank (bank7)"
assert mem3.bankB == 5, "window B should be untouched (still Stage2's own page2) by the GAME_OVER bank's one-way windowA-only switch"
assert cpu3.iff1 is False, \
    "interrupts still enabled on entry to the GAME_OVER bank's own INIT - the windowA-only switch race is back"
print(f"Stage2 -> GAME_OVER bank trampoline verified: bankA={mem3.bankA} bankB={mem3.bankB} "
      f"(window B correctly left untouched), interrupts correctly disabled on landing")

# skip the real ~10s button-or-timeout wait via sim_trig_a, same technique
# as every other real-time wait in this file - GO_WAIT_LOOP itself is a
# pure Z80-clock busy-wait (no H.TIMI dependency, unlike Stage1/Stage2's
# own GAME_OVER_SEQ/STAGE_CLEAR_ACT), so in principle it COULD be driven
# to completion with real steps, but 10 real seconds' worth of busy-wait
# instructions is prohibitively slow for a test.
GO_WAIT_LOOP = gosym["GO_WAIT_LOOP"]
steps_s2g6 = 0
while cpu3.pc != GO_WAIT_LOOP and steps_s2g6 < 3_000_000:
    cpu3.step()
    steps_s2g6 += 1
assert cpu3.pc == GO_WAIT_LOOP, "GAME_OVER bank never reached its own GO_WAIT_LOOP (blink sequence + text draw stuck?)"

# (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバージングルを
# GAME_OVERバンクにも実装): GO_INIT_BGM(gameover_bank.asm)がここまでの
# 過程で実際にwindow Bをbgm-dataバンク(global6)へ切り替え、周期テーブル+
# GAME_OVERジングルのchB/chCをこのファイル自身のRAM(GO_PERIOD_LO/HI_RAM・
# GO_CHB/CHC_BASE、combined_test.asm自身のBGM RAMと物理的に同じアドレス、
# Stage2本編がもう二度と実行されないため安全に再利用)へコピー済みで
# あることを確認する。ここは実際のマルチバンクエミュレーション(mem3=
# BankedMem)上でのテストのため、gameover_bank_test.py側のフラットメモリ
# harness(window Bのバンク切替を模擬できない)とは違い、本物のwindow B
# 切替を経た実バイトを直接検証できる。
_go = bgm_layout["GAME_OVER"]
_go_start = _go["bank_offset"]
_go_chB = bgm_bank[_go_start:_go_start + _go["chB_len"]]
_go_chC = bgm_bank[_go_start + _go["chB_len"]:_go_start + _go["chB_len"] + _go["chC_len"]]
_go_period_lo = list(bgm_bank[0:bg.NUM_NOTES])
_go_period_hi = list(bgm_bank[bg.NUM_NOTES:2 * bg.NUM_NOTES])
assert mem3.bankB == 6, \
    "GAME_OVER bank's own GO_INIT_BGM should have left window B on the bgm-data bank (6) - " \
    "it never restores window B afterward since it has no further use for it"
assert [mem3.flat[gosym["GO_PERIOD_LO_RAM"] + i] for i in range(len(_go_period_lo))] == _go_period_lo, \
    "GAME_OVER bank's own BGM RAM copy: period table (lo) mismatch"
assert [mem3.flat[gosym["GO_PERIOD_HI_RAM"] + i] for i in range(len(_go_period_hi))] == _go_period_hi, \
    "GAME_OVER bank's own BGM RAM copy: period table (hi) mismatch"
assert [mem3.flat[gosym["GO_CHB_BASE"] + i] for i in range(len(_go_chB))] == list(_go_chB), \
    "GAME_OVER bank's own BGM RAM copy: chB (melody) mismatch"
assert [mem3.flat[gosym["GO_CHC_BASE"] + i] for i in range(len(_go_chC))] == list(_go_chC), \
    "GAME_OVER bank's own BGM RAM copy: chC (harmony) mismatch"
_go_hook_target = mem3.flat[gosym["HTIMI_HOOK"] + 1] | (mem3.flat[gosym["HTIMI_HOOK"] + 2] << 8)
assert mem3.flat[gosym["HTIMI_HOOK"]] == 0xC3 and _go_hook_target == gosym["GO_BGM_TICK"], \
    "GAME_OVER bank's own INIT did not install its HTIMI_HOOK pointing at GO_BGM_TICK"
print("GAME_OVER bank's own BGM RAM copy (period table + GAME_OVER jingle chB/chC) verified "
      "byte-correct via a real window B bank switch, HTIMI_HOOK armed to its own GO_BGM_TICK")

cpu3.sim_trig_a = True
steps_s2g7 = 0
switched_s2g7 = False
while steps_s2g7 < 2_000_000:
    if cpu3.pc == TITLE_INIT and mem3.bankA == 0:
        switched_s2g7 = True
        break
    cpu3.step()
    steps_s2g7 += 1
assert switched_s2g7, "GAME_OVER bank's GO_TO_TITLE trampoline never reached title's own INIT (bank0)"
assert mem3.bankA == 0 and mem3.bankB == 1, "banks not switched back to title (0,1) on Stage2 game-over return"
assert cpu3.iff1 is False, \
    "interrupts still enabled on entry to title's INIT via the GAME_OVER bank's own trampoline"
print(f"GAME_OVER bank -> title trampoline verified: bankA={mem3.bankA} bankB={mem3.bankB}, "
      f"interrupts correctly disabled on landing")

for _ in range(300):
    cpu3.step()
assert mem3.flat[tsym["HTIMI_HOOK"]] == 0xC9, \
    "title's own INIT did not reset the stale HTIMI_HOOK after being re-entered via the " \
    "GAME_OVER bank's own trampoline"
print("title's own INIT correctly reset the stale HTIMI_HOOK (inherited from the GAME_OVER bank) "
      "to a safe bare RET")

# (2026-09-12、"ではこの画像をMission completed表示後10秒したら表示
# ボタンが押されたらスタート画面へ"): Stage2 ENDING_ACT==4(最終画像
# 表示+ボタン待ち)->titleトランポリンは、ENDING_SHOW_FINAL_IMAGE自身の
# 挙動(実VRAM内容・windowB切替/復帰・ボタン待ちループ)は
# ending_final_image_test.py(standaloneの簡易3スロットBankedMem)で
# 既に検証済みだが、そちらでは検証できない2点(a)Comb実レイアウトでの
# SWITCH_TO_CHARDATA_BANKのパッチ済みバンク番号(6)が本物の共有bgm_bank
# 内容へ実際にルーティングされること、(b)ボタン押下トランポリンが実際に
# title(global bank0/1)のINITへ正しく着地すること、を本物の4バンク配置
# (GAME_OVERバンクと同じ一気通貫スタイル)で確認する。ENDING_ACT 0->1->
# 2->3->4の状態遷移自体はending_sequence_test.pyで既に別途検証済みの
# ため、ここでは実ボス撃破シーケンスを再現せずENDING_ACT=4へ直接poke
# して(GAME_OVERシナリオのSTAGE_CLEAR_ACT=3直接pokeと同じ手法)本題
# (バンク切替の一気通貫)に絞る。
print()
print("---- Stage2 ENDING_ACT==4 -> final image -> button press -> title trampoline "
      "(round80follow-up, previously untested here) ----")
mem4 = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy, gameover_bank],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5, bytearray(bgm_bank), dummy],
)
cpu4 = z80emu.Z80(mem4)
cpu4.pc = tsym["INIT"]
cpu4.sp = 0xF380

steps_e0 = 0
while cpu4.pc != WAIT_FOR_START and steps_e0 < 2_000_000:
    cpu4.step()
    steps_e0 += 1
assert cpu4.pc == WAIT_FOR_START, "title screen (4th run) never reached WAIT_FOR_START"

cpu4.sim_trig_a = True
steps_e1 = 0
switched_e1 = False
# (title_bank0のディレイ短縮パッチについては上のmem2セクションのコメント参照)
while steps_e1 < 10_000_000:
    if cpu4.pc == GAME_INIT and mem4.bankA == 2:
        switched_e1 = True
        break
    cpu4.step()
    steps_e1 += 1
assert switched_e1, "title -> Stage1 (4th run, for the ending scenario) never trampolined"

steps_e2 = 0
while cpu4.pc != MAINLOOP and steps_e2 < 2_000_000:
    cpu4.step()
    steps_e2 += 1
assert cpu4.pc == MAINLOOP, "Stage1 (4th run) never reached its own MAINLOOP"

mem4.flat[PLAYER_FLYAWAY] = 2
mem4.flat[STAGE_CLEAR_ACT] = 3
cpu4.sim_trig_a = False

steps_e3 = 0
switched_e3 = False
while steps_e3 < 2_000_000:
    if cpu4.pc == STAGE2_INIT and mem4.bankA == 4:
        switched_e3 = True
        break
    cpu4.step()
    steps_e3 += 1
assert switched_e3, "Stage1 -> real Stage2 (4th run) never trampolined"

STAGE2_MAINLOOP = s2sym["MAINLOOP"]
steps_e4 = 0
while cpu4.pc != STAGE2_MAINLOOP and steps_e4 < 2_000_000:
    cpu4.step()
    steps_e4 += 1
assert cpu4.pc == STAGE2_MAINLOOP, "Stage2 (4th run) never reached its own MAINLOOP"
print("Stage2 (4th run): reached its own MAINLOOP, ready to drive ENDING_ACT==4")

ENDING_ACT = s2sym["ENDING_ACT"]
ENDING_WAIT_FINAL_BUTTON = s2sym["ENDING_WAIT_FINAL_BUTTON"]
mem4.flat[ENDING_ACT] = 4
steps_e5 = 0
while cpu4.pc != ENDING_WAIT_FINAL_BUTTON and steps_e5 < 600_000:
    cpu4.step()
    steps_e5 += 1
assert cpu4.pc == ENDING_WAIT_FINAL_BUTTON, \
    "ENDING_ACT==4 (4th run, real Comb bank layout) never reached ENDING_WAIT_FINAL_BUTTON"
assert mem4.bankB == 5, \
    "window B should be restored to Stage2's own page2 (5) after borrowing the real shared " \
    "bgm-data bank (6, SWITCH_TO_CHARDATA_BANK's Comb-patched value) to decompress the final image"

sys.path.insert(0, os.path.join(REPO, "tools", "title_screen"))
import title_bg_gen
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_combined"))
import ending_image_gen
_ending_payload = ending_image_gen.load_payload()
_ending_vram = bytes(cpu4.vram[0:title_bg_gen.PAYLOAD_LEN])
_ending_payload_minus_sprattr0 = (_ending_payload[:0x1B00] + bytes([_ending_vram[0x1B00]])
                                  + _ending_payload[0x1B01:])
assert _ending_vram == _ending_payload_minus_sprattr0, \
    "final-image VRAM doesn't match EndingImage.SC2's real payload - the real shared bgm_bank " \
    "(global bank6) content didn't decompress correctly through the Comb-patched " \
    "SWITCH_TO_CHARDATA_BANK"
print("final-image VRAM verified byte-correct via a real window B switch to the shared "
      "bgm-data/chardata bank (global bank6)")

cpu4.sim_trig_a = True
steps_e6 = 0
switched_e6 = False
while steps_e6 < 2_000_000:
    if cpu4.pc == TITLE_INIT and mem4.bankA == 0:
        switched_e6 = True
        break
    cpu4.step()
    steps_e6 += 1
assert switched_e6, "ENDING_FINAL_BUTTON_PRESSED trampoline never reached title's own INIT (bank0)"
assert mem4.bankA == 0 and mem4.bankB == 1, "banks not switched back to title (0,1) on ending return"
assert cpu4.iff1 is False, \
    "interrupts still enabled on entry to title's INIT via the ending's own trampoline"
print(f"final-image -> title trampoline verified: bankA={mem4.bankA} bankB={mem4.bankB}, "
      f"interrupts correctly disabled on landing")

for _ in range(300):
    cpu4.step()
assert mem4.flat[tsym["HTIMI_HOOK"]] == 0xC9, \
    "title's own INIT did not reset the stale HTIMI_HOOK after being re-entered via the " \
    "ending's own trampoline"
print("title's own INIT correctly reset the stale HTIMI_HOOK (inherited from Stage2's ending) "
      "to a safe bare RET")

print()
print("COMB BUILD (TITLE -> STAGE1 -> REAL STAGE2) BANK-SWITCH INTEGRATION: ALL CHECKS PASSED")
