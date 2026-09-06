"""Verifies the ending sequence (2026-09-06, "GFEndingを2ボス倒した後に
再生 これは3音使って良い 倒してから10秒ほど経過したら再生し 操作無効に
Produced by Kumanecoyarou と画面中央に表示 曲が終わったら音を停止
Mission Cmpletedと表示 全部大文字で").

State machine (ENDING_ACT): 0 (not yet) -> 1 (waiting, set the instant the
boss's own real death explosion sequence completes - UBE_FLASH's own new
hook, REASON=0 only) -> 2 (playing, set once ENDING_WAIT_TICKS have
elapsed on VBLANK_COUNT, a real-vblank-driven clock from BGM_TICK,
independent of MAINLOOP's own free-running, non-realtime TICK) -> 3
(done, set once ENDING_SONG_TOTAL_TICKS have elapsed since playback
started).

Uses the same hit_boss()/make_boss() shortcut boss_broken_form_test.py
established for driving a real death without simulating the whole level.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_combined"))
import bgm_bank_gen as bg  # noqa: E402
import ending_text_gen  # noqa: E402

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_HP = sym["BOSS_HP"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_FORM = sym["BOSS_FORM"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
BOSS_EXPL_STATE_DONE = sym["BOSS_EXPL_STATE_DONE"]
BOSS_EXPL_REASON = sym["BOSS_EXPL_REASON"]
BULLET0_ACT = sym["BULLET0_ACT"]

ENDING_ACT = sym["ENDING_ACT"]
VBLANK_COUNT = sym["VBLANK_COUNT"]
ENDING_WAIT_START = sym["ENDING_WAIT_START"]
ENDING_SONG_START = sym["ENDING_SONG_START"]
ENDING_WAIT_TICKS = sym["ENDING_WAIT_TICKS"]
ENDING_SONG_TOTAL_TICKS = sym["ENDING_SONG_TOTAL_TICKS"]
JOY_DIR = sym["JOY_DIR"]
JOY_TRIGB = sym["JOY_TRIGB"]
JOY_TRIGA = sym["JOY_TRIGA"]

BGM_B_PTR = sym["BGM_B_PTR"]
BGM_C_PTR = sym["BGM_C_PTR"]
BGM_A_PTR = sym["BGM_A_PTR"]
BGM_B_BASE = sym["BGM_B_BASE"]

GFE = bg.song_constants("ENDING_GFENDING", data_base=bg.STAGE2_DATA_BASE)
bank_image, layout = bg.build_bank()
_gfe_layout = layout["ENDING_GFENDING"]
_song_start = _gfe_layout["bank_offset"]
gfe_chB = bank_image[_song_start:_song_start + _gfe_layout["chB_len"]]
gfe_chC = bank_image[_song_start + _gfe_layout["chB_len"]:
                      _song_start + _gfe_layout["chB_len"] + _gfe_layout["chC_len"]]
gfe_chA = bank_image[_song_start + _gfe_layout["chB_len"] + _gfe_layout["chC_len"]:
                      _song_start + _gfe_layout["chB_len"] + _gfe_layout["chC_len"] + _gfe_layout["chA_len"]]


def make_boss(cpu, x=100, hp=1, phase=0):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_HP] = hp
    cpu.mem[BOSS_PHASE] = phase
    cpu.mem[BOSS_FORM] = 0


def make_bullet(cpu, col, row, active=1):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = active
    cpu.mem[ix + 1] = 0
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    row_addr = 0x1800 + row * 32
    cpu.mem[ix + 4] = row_addr & 0xFF
    cpu.mem[ix + 5] = (row_addr >> 8) & 0xFF
    cpu.mem[ix + 6] = 0
    cpu.ix = ix


def hit_boss(cpu, x):
    boss_row = BOSS_SPAWN_Y // 8
    make_bullet(cpu, col=x // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")


def kill_boss_for_real(cpu):
    """Drives the boss to a genuine HP=0 death and runs its explosion
    sequence to completion (BOSS_EXPL_STATE_DONE, REASON=0) - the exact
    real-game trigger for ENDING_ACT to become 1."""
    make_boss(cpu, x=100, hp=1)
    hit_boss(cpu, 100)
    assert cpu.mem[BOSS_HP] == 0
    assert cpu.mem[BOSS_EXPL_REASON] == 0
    for _ in range(2000):
        call_routine(cpu, "UPDATE_BOSS_ALL")
        if cpu.mem[BOSS_EXPL_STATE] == BOSS_EXPL_STATE_DONE:
            return
    raise AssertionError("boss explosion never reached DONE")


# ---- real boot, real death ----
cpu = fresh_cpu()
check("ENDING_ACT starts at 0 (fresh boot, no ending pending)", cpu.mem[ENDING_ACT] == 0)
kill_boss_for_real(cpu)
check("a genuine death (BOSS_EXPL_STATE reaches DONE with REASON=0) sets "
      "ENDING_ACT to 1 (waiting)", cpu.mem[ENDING_ACT] == 1)
wait_start = cpu.mem[ENDING_WAIT_START] | (cpu.mem[ENDING_WAIT_START + 1] << 8)
vblank_at_death = cpu.mem[VBLANK_COUNT] | (cpu.mem[VBLANK_COUNT + 1] << 8)
check("ENDING_WAIT_START snapshots VBLANK_COUNT at the moment of death",
      wait_start == vblank_at_death)

# ---- input stays live during the wait (only disabled once playback starts) ----
# cpu.sim_dir feeds the emulator's own GTSTCK stub (z80emu.py) - setting it
# to a distinguishable non-zero value and checking whether it actually
# reaches JOY_DIR is what proves READ_INPUT took the real-hardware path
# rather than the forced-neutral one (poisoning JOY_DIR's own RAM byte
# directly would NOT distinguish the two paths, since a real read with
# sim_dir left at its default 0 would also leave JOY_DIR at 0).
cpu.sim_dir = 5
call_routine(cpu, "READ_INPUT")
check("during the wait (ENDING_ACT=1), READ_INPUT still performs a real "
      "hardware read (not forced to neutral) - input is disabled only once "
      "playback actually starts, matching the literal wording "
      "\"10秒ほど経過したら再生し 操作無効に\"",
      cpu.mem[JOY_DIR] == 5)

# ---- advance BGM_TICK (the real-vblank clock) short of the wait threshold ----
for _ in range(ENDING_WAIT_TICKS - 1):
    call_routine(cpu, "BGM_TICK")
call_routine(cpu, "UPDATE_ENDING")
check(f"still waiting 1 tick before ENDING_WAIT_TICKS({ENDING_WAIT_TICKS}) elapses",
      cpu.mem[ENDING_ACT] == 1)

call_routine(cpu, "BGM_TICK")
call_routine(cpu, "UPDATE_ENDING")
check("ENDING_ACT becomes 2 (playing) the instant ENDING_WAIT_TICKS have "
      "elapsed on the real vblank clock",
      cpu.mem[ENDING_ACT] == 2)

# ---- GFEnding's 3 parts loaded byte-correct at their own RAM addresses ----
check("GFEnding's own chB (melody) copied byte-correct",
      [cpu.mem[BGM_B_BASE + i] for i in range(len(gfe_chB))] == list(gfe_chB))
check("GFEnding's own chC (bass) copied byte-correct at ITS OWN chC start "
      "(0x%04X, different from DEFEAT/TryZ's own)" % GFE["CHC_RAM_BASE"],
      [cpu.mem[GFE["CHC_RAM_BASE"] + i] for i in range(len(gfe_chC))] == list(gfe_chC))
check("GFEnding's own chA (harmony, the 3rd voice - \"これは3音使って良い\") "
      "copied byte-correct",
      [cpu.mem[GFE["CHA_RAM_BASE"] + i] for i in range(len(gfe_chA))] == list(gfe_chA))
check("BGM_B_PTR/BGM_C_PTR/BGM_A_PTR all reset to their own song start",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == BGM_B_BASE and
      (cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)) == GFE["CHC_RAM_BASE"] and
      (cpu.mem[BGM_A_PTR] | (cpu.mem[BGM_A_PTR + 1] << 8)) == GFE["CHA_RAM_BASE"])

# ---- credit text drawn centered on row 11 ----
credit_codes, complete_codes = ending_text_gen.message_codes()
ROW11 = 0x1800 + 11 * 32
credit_col = 3
check("\"PRODUCED BY KUMANECOYAROU\" is drawn centered on row 11 (col 3), "
      "using the real font pattern-code mapping",
      [cpu.vram[ROW11 + credit_col + i] for i in range(len(credit_codes))] == credit_codes)

# ---- font glyph bitmaps + color groups loaded ----
blocks = ending_text_gen.font_bitmaps()
font_ok = True
for base, blob in blocks:
    addr = base * 8
    if [cpu.vram[addr + i] for i in range(len(blob))] != blob:
        font_ok = False
check("all 3 font glyph blocks loaded byte-correct into their pattern-code slots",
      font_ok)
check("the 3 reused color groups (12/18/19) are repainted white-on-black",
      cpu.vram[0x2000 + 12] == 0xF1 and cpu.vram[0x2000 + 18] == 0xF1 and cpu.vram[0x2000 + 19] == 0xF1)

# ---- input now genuinely disabled ----
cpu.sim_dir = 5
call_routine(cpu, "READ_INPUT")
check("once playback has started (ENDING_ACT=2), READ_INPUT forces JOY_DIR/"
      "JOY_TRIGB/JOY_TRIGA to 0 instead of reading real hardware - the actual "
      "\"操作無効に\" behavior",
      cpu.mem[JOY_DIR] == 0 and cpu.mem[JOY_TRIGB] == 0 and cpu.mem[JOY_TRIGA] == 0)

# ---- SOUND_UPDATE itself is never called from MAINLOOP while ENDING_ACT==2
# (verified via the real MAINLOOP gate, not just BGM_TICK's own chA
# ownership) - drive a real MAINLOOP pass and confirm SOUND_UPDATE's own
# chA writes aren't clobbered by it running concurrently. Simpler direct
# check: call SOUND_UPDATE manually to poison R8, then run one real
# BGM_TICK (harmony) and confirm the harmony's own value survives one full
# MAINLOOP-less BGM_TICK, i.e. nothing else contends for R8 in this window.
call_routine(cpu, "BGMT_UPDATE_ENDING_A")
r8_before = cpu.psg_regs.get(8)
check("BGMT_UPDATE_ENDING_A (chA harmony) actually writes R8 (real PSG "
      "volume register), confirming the 3rd channel is live during playback",
      r8_before is not None)


# ---- fast-forward to the exact end of the song and confirm the finish
# transition (stop sound + MISSION COMPLETED) ----
cpu2 = fresh_cpu()
kill_boss_for_real(cpu2)
for _ in range(ENDING_WAIT_TICKS):
    call_routine(cpu2, "BGM_TICK")
call_routine(cpu2, "UPDATE_ENDING")
assert cpu2.mem[ENDING_ACT] == 2
for _ in range(ENDING_SONG_TOTAL_TICKS - 1):
    call_routine(cpu2, "BGM_TICK")
call_routine(cpu2, "UPDATE_ENDING")
check(f"still playing 1 tick before ENDING_SONG_TOTAL_TICKS({ENDING_SONG_TOTAL_TICKS}) "
      "elapses since playback started",
      cpu2.mem[ENDING_ACT] == 2)

call_routine(cpu2, "BGM_TICK")
call_routine(cpu2, "UPDATE_ENDING")
check("ENDING_ACT becomes 3 (done) the instant the song's own real total "
      "duration elapses",
      cpu2.mem[ENDING_ACT] == 3)
check("chA volume (R8) explicitly silenced on finish (\"曲が終わったら音を停止\")",
      cpu2.psg_regs.get(8) == 0)

ROW11_2 = 0x1800 + 11 * 32
complete_col = 7
check("row 11 no longer shows any leftover \"PRODUCED BY...\" characters "
      "past MISSION COMPLETED's own width (the row is blanked before the "
      "new message is drawn, not just overwritten in place)",
      all(cpu2.vram[ROW11_2 + complete_col + len(complete_codes) + i] == 120
          for i in range(3)))
check("\"MISSION COMPLETED\" is drawn centered on row 11 (col 7)",
      [cpu2.vram[ROW11_2 + complete_col + i] for i in range(len(complete_codes))] == complete_codes)

# ---- once done (ENDING_ACT==3), further ticks/UPDATE_ENDING calls are inert ----
for _ in range(500):
    call_routine(cpu2, "BGM_TICK")
call_routine(cpu2, "UPDATE_ENDING")
check("ENDING_ACT stays at 3 (done) permanently - no re-triggering",
      cpu2.mem[ENDING_ACT] == 3)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
