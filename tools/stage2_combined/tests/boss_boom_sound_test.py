"""Verifies the boss's own circle-explosion "boom" sound (SOUND_BOSS_
BOOM/SU_BOOM) - z80emu.py has no PSG emulation at all (OUT only
actually does anything for the VDP ports, 98h/99h - see its own
vdp_out() special-case), so the actual byte written to the PSG can
never be observed directly. What CAN be verified: the envelope state
(SND_TIMER/SND_DECAY/SND_BOOM_DECAY_CTR/SND_EXPLODING) evolves exactly
as intended over many simulated frames, and SOUND_CALC_NOISE_GATE_
VOLUME (kept as its own side-effect-free subroutine specifically so
it's testable this way - shared by every noise SE in this file, not
boom-only, see noise_duty_cycle_test.py for that broader coverage)
returns the right value for a given SND_TIMER/SND_NOISE/TICK
combination, independently computed here rather than re-derived from
the ASM's own logic.

User's own spec (verbatim, paraphrased): the circle explosion needs a
long noise "boom" ("どーーーーん"), too plain if just a linear noise
decay ("チャチ"), so mix in a 1:1 duty-cycle modulation - half volume or
OFF - while decaying, for a buzzy "ブリブリ" texture (later tightened to
full volume instead of half, see below).
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


SND_TIMER = sym["SND_TIMER"]
SND_DECAY = sym["SND_DECAY"]
SND_EXPLODING = sym["SND_EXPLODING"]
SND_BOOM_DECAY_CTR = sym["SND_BOOM_DECAY_CTR"]
TICK = sym["TICK"]
BOSS_BOOM_NOISE_PERIOD = sym["BOSS_BOOM_NOISE_PERIOD"]
BOSS_BOOM_DECAY_PERIOD = sym["BOSS_BOOM_DECAY_PERIOD"]
SHOT_SND_PEAK = sym["SHOT_SND_PEAK"]
SHOT_SND_DECAY = sym["SHOT_SND_DECAY"]
BOSS_EXPL_STATE = sym["BOSS_EXPL_STATE"]
STATE_GROW = sym["BOSS_EXPL_STATE_GROW"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
NIGHT_ROW = sym["NIGHT_ROW"]
NIGHT_END_ROW = sym["NIGHT_END_ROW"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
NIGHT_CODE = sym["NIGHT_CODE"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
NAME_BASE = 0x1800


def cell_addr(col, row):
    return NAME_BASE + row * 32 + col


# ---------------------------------------------------------------------
# 1: SOUND_CALC_NOISE_GATE_VOLUME itself, called with SND_NOISE=1 (the
# boom is always noise) - a pure function of SND_TIMER/TICK once gated,
# independently re-derived (not read back from the ASM's own logic).
# The SND_NOISE=0 case and the other noise SEs are covered in their own
# noise_duty_cycle_test.py, not duplicated here.
# ---------------------------------------------------------------------
SND_NOISE = sym["SND_NOISE"]


def expected_boom_volume(timer, tick):
    # round32 follow-up: "円爆発はこれが音量最大か? かなり小さいが" -
    # "on" frames are now full-strength (not halved on top of the duty
    # cycle's own silence, see SOUND_CALC_NOISE_GATE_VOLUME's own
    # comment).
    if timer == 0:
        return 0
    if tick & 1:
        return 0
    return timer


cpu = fresh_cpu()
for timer in (0, 1, 2, 15, 14, 7):
    for tick in (0, 1, 2, 3, 254, 255):
        cpu.mem[SND_TIMER] = timer
        cpu.mem[SND_NOISE] = 1
        cpu.mem[TICK] = tick
        call_routine(cpu, "SOUND_CALC_NOISE_GATE_VOLUME")
        expected = expected_boom_volume(timer, tick)
        check(f"SOUND_CALC_NOISE_GATE_VOLUME(timer={timer},noise=1,tick={tick}) == "
              f"{expected} (got {cpu.a})",
              cpu.a == expected)

# ---------------------------------------------------------------------
# 2: SOUND_BOSS_BOOM's own trigger state - "円の爆発はノイズでどー
# ーーーんって長いやつ"
# ---------------------------------------------------------------------
cpu = fresh_cpu()
cpu.mem[SND_TIMER] = 0
cpu.mem[SND_DECAY] = 7  # arbitrary non-zero "leftover" from a prior sound
cpu.mem[SND_EXPLODING] = 0
call_routine(cpu, "SOUND_BOSS_BOOM")
check("SOUND_BOSS_BOOM sets SND_TIMER to peak (15)", cpu.mem[SND_TIMER] == 15)
check("SOUND_BOSS_BOOM sets SND_DECAY to the boom-mode sentinel (0)", cpu.mem[SND_DECAY] == 0)
check("SOUND_BOSS_BOOM arms SND_BOOM_DECAY_CTR to BOSS_BOOM_DECAY_PERIOD",
      cpu.mem[SND_BOOM_DECAY_CTR] == BOSS_BOOM_DECAY_PERIOD)
check("SOUND_BOSS_BOOM sets SND_EXPLODING (protects against being cut off by a shot)",
      cpu.mem[SND_EXPLODING] == 1)

# ---------------------------------------------------------------------
# 3: the full decay envelope over many simulated frames - "長いやつ":
# SND_TIMER must NOT drop every single frame the way the shared linear
# path does (that would cap the whole sound at 15 frames, same as
# every other sound here) - it should only drop once every
# BOSS_BOOM_DECAY_PERIOD calls, and the whole thing should last
# exactly 15*BOSS_BOOM_DECAY_PERIOD frames before SND_EXPLODING clears.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, "SOUND_BOSS_BOOM")
timer_history = []
exploding_at_end = None
total_frames = 15 * BOSS_BOOM_DECAY_PERIOD
for frame in range(1, total_frames + 1):
    call_routine(cpu, "SOUND_UPDATE")
    timer_history.append(cpu.mem[SND_TIMER])

# independently-derived expected sequence: after frame f (1-indexed),
# SND_TIMER = 15 - (f // BOSS_BOOM_DECAY_PERIOD), floored at 0 - NOT
# read from the ASM's own logic, a genuine cross-check.
expected_history = [max(0, 15 - (f // BOSS_BOOM_DECAY_PERIOD)) for f in range(1, total_frames + 1)]
mismatches = [(f, exp, got) for f, (exp, got) in enumerate(zip(expected_history, timer_history), 1)
              if exp != got]
check(f"SND_TIMER follows the exact expected step-every-{BOSS_BOOM_DECAY_PERIOD}-frames "
      f"envelope for all {total_frames} frames ({len(mismatches)} mismatches)",
      not mismatches)
check(f"SND_TIMER is still nonzero after only {BOSS_BOOM_DECAY_PERIOD - 1} frames "
      "(a plain 1/frame linear decay would already be silent well before this - "
      "confirms the boom genuinely outlasts every other sound's own 15-frame cap)",
      timer_history[BOSS_BOOM_DECAY_PERIOD - 2] > 0)
check(f"SND_TIMER reaches exactly 0 after {total_frames} frames (15*{BOSS_BOOM_DECAY_PERIOD})",
      timer_history[-1] == 0)
check("SND_TIMER never went negative/wrapped (always stayed in 0-15)",
      all(0 <= v <= 15 for v in timer_history))
check("SND_EXPLODING cleared the instant SND_TIMER reached 0", cpu.mem[SND_EXPLODING] == 0)

# a few more frames past the end must be a harmless no-op (steady silence,
# no wraparound, SND_DECAY still 0 so it keeps taking the boom path)
snapshot_timer = cpu.mem[SND_TIMER]
snapshot_exploding = cpu.mem[SND_EXPLODING]
for _ in range(10):
    call_routine(cpu, "SOUND_UPDATE")
check("boom stays silent/inert for good once fully decayed (no further state change)",
      cpu.mem[SND_TIMER] == snapshot_timer == 0 and cpu.mem[SND_EXPLODING] == snapshot_exploding == 0)

# ---------------------------------------------------------------------
# 4: a shot sound fired right after the boom fully ends must work
# normally again (SND_DECAY=0 is a boom-only sentinel, not a permanent
# state) - regression guard for the sentinel design itself.
# ---------------------------------------------------------------------
call_routine(cpu, "SOUND_SHOT")
check("SND_DECAY is a real (non-zero) decay amount again once a normal sound "
      "fires after the boom - the 0-sentinel doesn't leak past the boom's own life",
      cpu.mem[SND_DECAY] == SHOT_SND_DECAY)
check("the shot sound's own peak volume is set correctly", cpu.mem[SND_TIMER] == SHOT_SND_PEAK)
call_routine(cpu, "SOUND_UPDATE")
check("SOUND_UPDATE decays the shot normally (linear path, not the boom path) "
      "right after a boom", cpu.mem[SND_TIMER] == SHOT_SND_PEAK - SHOT_SND_DECAY)

# ---------------------------------------------------------------------
# 5: a shot fired WHILE the boom is still playing must NOT cut it off -
# same SND_EXPLODING guard SOUND_DESTROY already relies on.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, "SOUND_BOSS_BOOM")
call_routine(cpu, "SOUND_SHOT")
check("a shot fired mid-boom does not cut the boom off (SND_DECAY still the "
      "boom's own 0 sentinel, not the shot's)", cpu.mem[SND_DECAY] == 0)
check("SND_TIMER is untouched by the blocked shot (still the boom's own peak)",
      cpu.mem[SND_TIMER] == 15)

# ---------------------------------------------------------------------
# 6: triggered at the right moment - "円の爆発は" (the CIRCLE explosion
# specifically, not the SPARK burst) - right at the SPARK->GROW handoff.
# ---------------------------------------------------------------------
def setup_boss(cpu, x, y=BOSS_SPAWN_Y, phase=0):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    cpu.mem[BOSS_Y] = y
    cpu.mem[BOSS_PHASE] = phase
    cpu.mem[NIGHT_ROW] = NIGHT_END_ROW
    for row in range(0, NIGHT_END_ROW):
        for col in range(32):
            cpu.vram[cell_addr(col, row)] = HUD_ROW_BLANK_CODE
    for col in range(32):
        cpu.vram[cell_addr(col, NIGHT_END_ROW)] = NIGHT_CODE
    for q in range(16):
        cpu.mem[BOSS_SPRITE_ATTRS + q * 4] = y
    call_routine(cpu, "FLUSH_BOSS_SPRITES")


cpu = fresh_cpu()
setup_boss(cpu, x=96)
call_routine(cpu, "CHPBOSS_DESTROY")
check("boom NOT triggered yet right at death (SND_TIMER untouched, still the "
      "fresh-boot 0) - it's the circle that booms, not the burst",
      cpu.mem[SND_TIMER] == 0)
SPARK_DURATION = sym["BOSS_EXPL_SPARK_DURATION"]
for _ in range(SPARK_DURATION):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
check("GROW has begun right after the SPARK burst completes (sanity check)",
      cpu.mem[BOSS_EXPL_STATE] == STATE_GROW)
check("the boom is triggered exactly at the SPARK->GROW handoff (SND_TIMER=15)",
      cpu.mem[SND_TIMER] == 15)
check("boom's own SND_DECAY sentinel (0) is set at the handoff", cpu.mem[SND_DECAY] == 0)
check("boom's own SND_EXPLODING guard is set at the handoff", cpu.mem[SND_EXPLODING] == 1)


# ---------------------------------------------------------------------
# 7: SPARK burst crackle - "爆発エフェクト中も爆発音追加". Direct check
# of SOUND_SPARK_CRACKLE's own trigger values, then a full run through
# the whole SPARK phase (interleaving UPDATE_BOSS_EXPLOSION with
# SOUND_UPDATE, same order MAINLOOP itself uses each real frame) to
# confirm it actually fires periodically, not continuously.
# ---------------------------------------------------------------------
SPARK_CRACKLE_PEAK = sym["SPARK_CRACKLE_PEAK"]
SPARK_CRACKLE_DECAY = sym["SPARK_CRACKLE_DECAY"]
SPARK_CRACKLE_PERIOD = sym["SPARK_CRACKLE_PERIOD"]

cpu = fresh_cpu()
cpu.mem[SND_TIMER] = 0
cpu.mem[SND_DECAY] = 0
call_routine(cpu, "SOUND_SPARK_CRACKLE")
check("SOUND_SPARK_CRACKLE sets SND_TIMER to its own peak",
      cpu.mem[SND_TIMER] == SPARK_CRACKLE_PEAK)
check("SOUND_SPARK_CRACKLE sets SND_DECAY to its own decay rate (a real linear "
      "decay, NOT the boom's 0 sentinel)",
      cpu.mem[SND_DECAY] == SPARK_CRACKLE_DECAY)

cpu = fresh_cpu()
setup_boss(cpu, x=96)
call_routine(cpu, "CHPBOSS_DESTROY")
trigger_frames = []
for frame in range(1, SPARK_DURATION + 1):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    if cpu.mem[SND_TIMER] == SPARK_CRACKLE_PEAK and cpu.mem[SND_DECAY] == SPARK_CRACKLE_DECAY:
        trigger_frames.append(frame)
    call_routine(cpu, "SOUND_UPDATE")

# independently-derived expected trigger frames: UBE_SPARK checks
# (SPARK_DURATION-frame) against SPARK_CRACKLE_PERIOD-1 AFTER its own
# decrement, and never runs that check at all on the very last frame
# (which branches straight to UBS_LAST_FRAME instead) - NOT read from
# the ASM's own logic, a genuine cross-check.
expected_triggers = [f for f in range(1, SPARK_DURATION)
                      if (SPARK_DURATION - f) % SPARK_CRACKLE_PERIOD == 0]
check(f"crackle fires on exactly the expected {len(expected_triggers)} frames over the "
      f"whole {SPARK_DURATION}-frame burst (every {SPARK_CRACKLE_PERIOD} frames, not "
      f"every single frame) - {trigger_frames == expected_triggers}",
      trigger_frames == expected_triggers)
check("crackle does NOT fire on the very last SPARK frame (that frame hands off "
      "to GROW instead, see UBS_LAST_FRAME)",
      SPARK_DURATION not in trigger_frames)

# crackle sound must genuinely decay back toward silence between triggers
# (not held continuously) - confirms a real periodic "crackle", not a
# drone. Needs its own frame-by-frame SND_TIMER trace (interleaved with
# SOUND_UPDATE, same order as above) to check.
cpu = fresh_cpu()
setup_boss(cpu, x=96)
call_routine(cpu, "CHPBOSS_DESTROY")
timer_trace = []
for _ in range(SPARK_DURATION):
    call_routine(cpu, "UPDATE_BOSS_EXPLOSION")
    call_routine(cpu, "SOUND_UPDATE")
    timer_trace.append(cpu.mem[SND_TIMER])
check("SND_TIMER visits 0 (fully decayed) between crackle triggers at some point "
      "during the burst - it doesn't stay perpetually loud",
      0 in timer_trace)
# each recorded value is already POST-decay (SOUND_UPDATE runs the same
# "frame" right after the trigger, same order MAINLOOP itself uses), so
# a trigger frame's own recorded value is PEAK-DECAY, not the raw PEAK.
post_trigger_value = max(0, SPARK_CRACKLE_PEAK - SPARK_CRACKLE_DECAY)
check(f"SND_TIMER reaches its crackle peak's own post-decay value ({post_trigger_value}) "
      "at some point during the burst - confirms real retriggering, not a one-shot decay",
      post_trigger_value in timer_trace)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
