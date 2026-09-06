"""Verifies the boss-fight BGM switch ("ではTryZをボス曲に...メロディ1
パートベース1パートを抜き出して変換して取り込み"、続けて実機フィード
バック対応で"マテリアライズ終了後に再生 マテリアライズに入る前にそれ
までのBGMは停止"へ変更): S2_BOSS_SPAWN itself now only calls MUTE_BGM
(silences DEFEAT immediately, but leaves BGM_B/C_PTR etc completely
untouched) - SWITCH_BGM_TO_TRYZ (which overwrites the same chB/chC RAM
buffers INIT_BGM originally filled with DEFEAT's row data with TryZ's own
2-part (melody=chB, bass=chC) row data, resets BGM_B/C_PTR/TIMER/REST/
envelope state, and calls UNMUTE_BGM) is only called later, once the
entrance "materialize" effect actually finishes (UBM_RETURNING, right
before ENTER_BOSS_ATTACK_POSE) - not at spawn time any more.

The critical regression this guards is the one self-discovered while
implementing this: TryZ's own chB (melody, 741 bytes) is much longer than
DEFEAT's chB (301 bytes), so TryZ's chC (bass) row data actually starts at
a DIFFERENT RAM address than DEFEAT's chC did (CHC_RAM_BASE = CHB_RAM_BASE
+ chB_len, which depends on the CURRENTLY LOADED song's own chB length).
BGMT_UC_NEWROW's LOOP_MARK handling used to jump back to a compile-time
constant (BGM_C_BASE, DEFEAT's own chC start) on every loop restart - for
TryZ this would have jumped into the middle of TryZ's own chB data instead
of TryZ's own chC start, corrupting playback after exactly one loop. The
fix (BGM_C_LOOP_BASE, a RAM variable both INIT_BGM and SWITCH_BGM_TO_TRYZ
now set to their own song's real chC start) is exercised directly below by
running chC through more than one full loop and checking the tone period
written on the SECOND pass matches TryZ's own chC first row exactly (not
garbage from mid-chB).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
import bgm_bank_gen as bg  # noqa: E402 - cached bgm_bank.bin/bgm_layout.json only, no mido needed

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


BGM_B_PTR = sym["BGM_B_PTR"]
BGM_C_PTR = sym["BGM_C_PTR"]
BGM_B_TIMER = sym["BGM_B_TIMER"]
BGM_C_TIMER = sym["BGM_C_TIMER"]
BGM_B_REST = sym["BGM_B_REST"]
BGM_C_REST = sym["BGM_C_REST"]
BGM_B_BASE = sym["BGM_B_BASE"]
BGM_C_LOOP_BASE = sym["BGM_C_LOOP_BASE"]
BGM_B_ENV_IDX = sym["BGM_B_ENV_IDX"]
BGM_C_ENV_IDX = sym["BGM_C_ENV_IDX"]
BGM_B_DUTY_PHASE = sym["BGM_B_DUTY_PHASE"]
BGM_MUTED = sym["BGM_MUTED"]

TRYZ = bg.song_constants("BOSS_TRYZ", data_base=bg.STAGE2_DATA_BASE)
bank_image, layout = bg.build_bank()
_tryz_layout = layout["BOSS_TRYZ"]
_song_start = _tryz_layout["bank_offset"]
tryz_chB_bytes = bank_image[_song_start:_song_start + _tryz_layout["chB_len"]]
tryz_chC_bytes = bank_image[_song_start + _tryz_layout["chB_len"]:
                             _song_start + _tryz_layout["chB_len"] + _tryz_layout["chC_len"]]


# ---- constants agree with tools/bgm_data/bgm_bank_gen.py's own BOSS_TRYZ
# layout, and CHC_RAM_BASE for TryZ is NOT the same address as DEFEAT's
# (the whole reason BGM_C_LOOP_BASE exists) ----
DEFEAT = bg.song_constants("DEFEAT", data_base=bg.STAGE2_DATA_BASE)
check("sanity: TryZ's own CHC_RAM_BASE differs from DEFEAT's (this is exactly "
      "the situation BGM_C_LOOP_BASE exists to handle correctly)",
      TRYZ["CHC_RAM_BASE"] != DEFEAT["CHC_RAM_BASE"])
check("TryZ's CHB_RAM_BASE is the same fixed address as DEFEAT's (period table "
      "size alone determines it, independent of song)",
      TRYZ["CHB_RAM_BASE"] == DEFEAT["CHB_RAM_BASE"] == BGM_B_BASE)


# ---- real boot trace, then trigger the boss spawn ----
cpu = fresh_cpu()
# poison the control block first so a "happens to already be right" false
# pass can't hide a real bug (same defensive style as init_ram_poison_test.py)
for addr in (BGM_B_PTR, BGM_B_PTR + 1, BGM_C_PTR, BGM_C_PTR + 1,
             BGM_B_TIMER, BGM_C_TIMER, BGM_B_REST, BGM_C_REST,
             BGM_C_LOOP_BASE, BGM_C_LOOP_BASE + 1, BGM_B_ENV_IDX, BGM_C_ENV_IDX,
             BGM_B_DUTY_PHASE):
    cpu.mem[addr] = 0xAA

call_routine(cpu, "S2_BOSS_SPAWN")

# ---- "マテリアライズに入る前にそれまでのBGMは停止": S2_BOSS_SPAWN
# itself must only mute (R9/R10 silenced immediately), leaving the DEFEAT
# song data/pointers completely untouched until the entrance effect
# actually finishes ----
check("S2_BOSS_SPAWN mutes BGM immediately (BGM_MUTED=1) instead of "
      "switching songs itself",
      cpu.mem[BGM_MUTED] == 1)
check("S2_BOSS_SPAWN's own MUTE_BGM silenced R9/R10 (chB/chC volume) immediately",
      cpu.psg_regs.get(9) == 0 and cpu.psg_regs.get(10) == 0)
check("S2_BOSS_SPAWN does NOT touch BGM_B_PTR/BGM_C_PTR itself - still "
      "whatever was poisoned, untouched until the real song switch below",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == 0xAAAA and
      (cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)) == 0xAAAA)

# ---- "マテリアライズ終了後に再生": simulate the entrance effect
# finishing by calling SWITCH_BGM_TO_TRYZ directly (the real trigger site,
# UBM_RETURNING, is exercised end-to-end via real MAINLOOP play further
# below and in boss_materialize_test.py) ----
call_routine(cpu, "SWITCH_BGM_TO_TRYZ")

check("SWITCH_BGM_TO_TRYZ clears BGM_MUTED (playback resumes)",
      cpu.mem[BGM_MUTED] == 0)
check("SWITCH_BGM_TO_TRYZ copied TryZ's own chB (melody) row data byte-correct "
      "into the shared RAM buffer",
      [cpu.mem[BGM_B_BASE + i] for i in range(len(tryz_chB_bytes))] == list(tryz_chB_bytes))
check("SWITCH_BGM_TO_TRYZ copied TryZ's own chC (bass) row data byte-correct "
      "at TryZ's OWN chC start address (not DEFEAT's stale one)",
      [cpu.mem[TRYZ["CHC_RAM_BASE"] + i] for i in range(len(tryz_chC_bytes))] == list(tryz_chC_bytes))
check("BGM_B_PTR reset to TryZ's own chB start",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == BGM_B_BASE)
check("BGM_C_PTR reset to TryZ's own chC start (not DEFEAT's)",
      (cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)) == TRYZ["CHC_RAM_BASE"])
check("BGM_C_LOOP_BASE updated to TryZ's own chC start - this is the actual "
      "regression fix under test",
      (cpu.mem[BGM_C_LOOP_BASE] | (cpu.mem[BGM_C_LOOP_BASE + 1] << 8)) == TRYZ["CHC_RAM_BASE"])
check("BGM_B_TIMER/BGM_C_TIMER reset to 0 (first tick loads a fresh row immediately)",
      cpu.mem[BGM_B_TIMER] == 0 and cpu.mem[BGM_C_TIMER] == 0)
check("BGM_B_REST/BGM_C_REST reset to 0",
      cpu.mem[BGM_B_REST] == 0 and cpu.mem[BGM_C_REST] == 0)


# ---- drive BGM_TICK past TryZ's own chC total length (7680 ticks, well
# under chB's 7680-tick total too since both share the same file-wide
# total_ticks) so a loop-back is guaranteed, then directly check
# BGM_C_PTR still points somewhere inside TryZ's OWN chC byte range - not
# inside chB's range (which starts at a LOWER address, BGM_C_BASE=
# DEFEAT's old chC start at 0xC3A5, landing squarely inside TryZ's chB
# region) the way the pre-fix code would land on a loop-back. This directly
# targets the actual invariant the bug violated, rather than an indirect
# "did we happen to see this period value" heuristic that a repeated note
# elsewhere in the row data could pass by coincidence even with the bug
# still present (caught during self-verification - the first version of
# this check used exactly such a heuristic and did NOT fail when the fix
# was temporarily reverted).
for _ in range(8100):   # > 7680 (TryZ's own total tick length) - guarantees at least one loop-back
    call_routine(cpu, "BGM_TICK")

ptr_after_loop = cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)
chc_lo = TRYZ["CHC_RAM_BASE"]
chc_hi = TRYZ["CHC_RAM_BASE"] + _tryz_layout["chC_len"]
check("after looping past TryZ's own chC length, BGM_C_PTR still points "
      f"inside TryZ's own chC range [0x{chc_lo:04X},0x{chc_hi:04X}) - not "
      "back inside chB's range the way the pre-fix compile-time BGM_C_BASE "
      "constant (DEFEAT's stale chC start) would send it",
      chc_lo <= ptr_after_loop < chc_hi)


# ---- real end-to-end: play real MAINLOOP frames (with BGM_TICK
# interleaved manually, since this emulator has no real interrupt
# dispatch) all the way through spawn -> materialize -> attack pose, and
# confirm the mute/switch timing actually lands where the real trigger
# sites (S2_BOSS_SPAWN / UBM_RETURNING) put them - not just that the
# routines behave correctly in isolation above.
from banked_helpers import step_frame

BOSS_ACT = sym["BOSS_ACT"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_MATERIALIZE_ACT = sym["BOSS_MATERIALIZE_ACT"]
BOSS_FORM = sym["BOSS_FORM"]

cpu2 = fresh_cpu()
cpu2.sim_dir = 1
cpu2.sim_trig_a = True
cpu2.sim_trig_b = False
was_muted_during_materialize = []
saw_boss_act = False
for f in range(9000):
    step_frame(cpu2)
    if cpu2.mem[BOSS_ACT] != 0:
        saw_boss_act = True
        if cpu2.mem[BOSS_FORM] == 0 and cpu2.mem[BOSS_MATERIALIZE_ACT] != 0:
            was_muted_during_materialize.append(cpu2.mem[BGM_MUTED])
        if cpu2.mem[BOSS_PHASE] == 1 and cpu2.mem[BOSS_MATERIALIZE_ACT] == 0:
            break  # materialize finished, boss now in its first attack pose
else:
    raise AssertionError("boss never reached its attack pose within 9000 frames")

check("real MAINLOOP: boss actually spawned during this run", saw_boss_act)
check("real MAINLOOP: BGM stayed muted for every frame the entrance materialize "
      f"effect was running ({len(was_muted_during_materialize)} frames observed)",
      len(was_muted_during_materialize) > 0 and all(was_muted_during_materialize))
check("real MAINLOOP: BGM_MUTED is cleared by the time the boss reaches its "
      "attack pose (SWITCH_BGM_TO_TRYZ's own UNMUTE_BGM already ran)",
      cpu2.mem[BGM_MUTED] == 0)
check("real MAINLOOP: TryZ's own chB data is actually sitting in RAM by the "
      "time the attack pose starts (the real UBM_RETURNING trigger site, not "
      "a direct call, actually fired)",
      [cpu2.mem[BGM_B_BASE + i] for i in range(len(tryz_chB_bytes))] == list(tryz_chB_bytes))


# ---- "マテリアライズ中は自機ショット音は停止" ----
SND_TIMER = sym["SND_TIMER"]

cpu3 = fresh_cpu()
cpu3.mem[BOSS_FORM] = 0
cpu3.mem[BOSS_MATERIALIZE_ACT] = 1
cpu3.mem[SND_TIMER] = 0
cpu3.mem[sym["SND_EXPLODING"]] = 0
call_routine(cpu3, "SOUND_SHOT")
check("SOUND_SHOT is silenced while BOSS_MATERIALIZE_ACT!=0 (materializing)",
      cpu3.mem[SND_TIMER] == 0)

cpu4 = fresh_cpu()
cpu4.mem[BOSS_FORM] = 0
cpu4.mem[BOSS_MATERIALIZE_ACT] = 0
cpu4.mem[SND_TIMER] = 0
cpu4.mem[sym["SND_EXPLODING"]] = 0
call_routine(cpu4, "SOUND_SHOT")
check("...but fires normally once materialize has ended (BOSS_MATERIALIZE_ACT=0)",
      cpu4.mem[SND_TIMER] != 0)

cpu5 = fresh_cpu()
cpu5.mem[BOSS_FORM] = 1   # BOSS_FORM_SPARK - BOSS_MATERIALIZE_ACT is aliased to
                          # BOSS_EXPL_CX here and holds a real, unrelated nonzero
                          # cell coordinate - must NOT be misread as materializing
cpu5.mem[BOSS_MATERIALIZE_ACT] = 37
cpu5.mem[SND_TIMER] = 0
cpu5.mem[sym["SND_EXPLODING"]] = 0
call_routine(cpu5, "SOUND_SHOT")
check("SOUND_SHOT is NOT falsely silenced once BOSS_FORM!=0, even though the "
      "aliased BOSS_MATERIALIZE_ACT/BOSS_EXPL_CX byte holds a real nonzero "
      "cell coordinate at that point",
      cpu5.mem[SND_TIMER] != 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
