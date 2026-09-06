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
from build_full_rom import assemble_title, assemble_game, assemble_real_stage2
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

assert "BOSS_SPAWN_TICK" in s2sym, "stage2 symtab missing BOSS_SPAWN_TICK - not the real stage2_combined content?"
print("confirmed: bank4/bank5 are the real stage2_combined content (BOSS_SPAWN_TICK present)")

# Both lists are indexed by GLOBAL bank number (0-6), matching the real
# ROM's own file layout (build_full_rom.py's rom96 concatenation order):
# window A only ever actually selects 0/2/4 (title/Stage1/Stage2 page1),
# window B only ever actually selects 1/3/5 (title/Stage1/Stage2 page2)
# AND, round40, 6 (the new BGM data bank - title/Stage2's own INIT_BGM
# each temporarily select it for windowB before restoring their own real
# page2 bank) - the other indices in each list are never read by this
# test's own code paths and are filled with dummy placeholders purely so
# the % modulo in __setitem__ has a dense list to index into.
bgm_bank, bgm_layout = bg.build_bank()
dummy = bytearray([0xFF] * 0x4000)
mem = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5, bytearray(bgm_bank)],
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
# RAMコピー自体はStage1用に維持するが、title自身のHTIMI_HOOK設置は
# 意図的にスキップするよう変更済み(タイトル画面自身は無音)。よって
# HTIMI_HOOKはtitleのINIT_BGM通過時点で一切書き換わっていないはず。
assert mem.flat[tsym["HTIMI_HOOK"]] == 0x00, \
    "title's own INIT_BGM should NOT arm HTIMI_HOOK anymore (title BGM intentionally disabled)"
print("title's own BGM RAM copy (period table + ALONE_FIGHTER chB/chC) verified byte-correct, "
      "HTIMI_HOOK intentionally left unarmed (title BGM disabled)")

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

cpu.sim_trig_a = True
print("simulated PUSH START (sim_trig_a=True)")

GAME_INIT = gsym["INIT"]
switched0 = False
steps0b = 0
while steps0b < 2_000_000:
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

print()
print("COMB BUILD (TITLE -> STAGE1 -> REAL STAGE2) BANK-SWITCH INTEGRATION: ALL CHECKS PASSED")
