"""Verifies the 1:1 on/off duty-cycle volume gating (SOUND_CALC_NOISE_
GATE_VOLUME, SND_NOISE) applies to EVERY noise-channel sound effect in
this file - "ではノイズ使ってる全てのSEをデューティ比の音量操作を適用
してみて" - and specifically does NOT apply to SOUND_ZUM_DEFLECT, the
one sound here that's tone rather than noise ("キンキン", a held ping
that would read wrong chopped up on/off).

The mechanism itself (originally built boom-only, as BOSS_BOOM_CALC_
VOLUME) is exercised directly in boss_boom_sound_test.py; this file
instead checks that each individual trigger routine (SOUND_SHOT/
SOUND_DESTROY/SOUND_SPARK_CRACKLE/SOUND_BOSS_BOOM/SOUND_ZUM_DEFLECT)
sets SND_NOISE to the right value for its own channel type, and that
SOUND_UPDATE's normal (non-boom) linear-decay path actually applies the
gating live - z80emu.py has no PSG emulation (OUT only does anything
for the VDP ports), so what's verified is the RAM-level state and the
routine's own return value, not an observed PSG byte.
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
SND_NOISE = sym["SND_NOISE"]
SND_EXPLODING = sym["SND_EXPLODING"]
TICK = sym["TICK"]
SHOT_SND_PEAK = sym["SHOT_SND_PEAK"]
SHOT_SND_DECAY = sym["SHOT_SND_DECAY"]
SPARK_CRACKLE_PEAK = sym["SPARK_CRACKLE_PEAK"]
SPARK_CRACKLE_DECAY = sym["SPARK_CRACKLE_DECAY"]

# ---------------------------------------------------------------------
# 1: each trigger routine sets SND_NOISE to the right value for its own
# channel type (1=noise/gated, 0=tone/ungated).
# ---------------------------------------------------------------------
NOISE_TRIGGERS = ["SOUND_SHOT", "SOUND_DESTROY", "SOUND_SPARK_CRACKLE", "SOUND_BOSS_BOOM"]
for routine in NOISE_TRIGGERS:
    cpu = fresh_cpu()
    cpu.mem[SND_NOISE] = 0xFF  # a value neither 0 nor 1 - forces the routine to genuinely set it
    call_routine(cpu, routine)
    check(f"{routine} sets SND_NOISE=1 (noise channel - duty-cycle gated)",
          cpu.mem[SND_NOISE] == 1)

cpu = fresh_cpu()
cpu.mem[SND_NOISE] = 0xFF
call_routine(cpu, "SOUND_ZUM_DEFLECT")
check("SOUND_ZUM_DEFLECT sets SND_NOISE=0 (tone channel - NOT gated, "
      "\"ではノイズ使ってる全てのSEを...\" explicitly excludes it)",
      cpu.mem[SND_NOISE] == 0)

# ---------------------------------------------------------------------
# 2: SOUND_UPDATE's own normal (non-boom) linear path actually applies
# the gate live for a noise sound - written volume alternates between
# the (decaying) envelope and silence every frame, following TICK's own
# low bit exactly - independently re-derived, not read back from the
# ASM's own logic.
# ---------------------------------------------------------------------
def expected_gated_trace(peak, decay, frames, tick_start=0):
    timer = peak
    out = []
    for i in range(frames):
        tick = tick_start + i
        written = 0 if (tick & 1) else timer
        out.append(written)
        # SOUND_UPDATE's own linear decay, applied AFTER writing this frame
        if timer == 0:
            continue
        if timer <= decay:
            timer = 0
        else:
            timer -= decay
    return out


cpu = fresh_cpu()
call_routine(cpu, "SOUND_SHOT")
cpu.mem[TICK] = 0
written_trace = []
for i in range(6):
    # SOUND_CALC_NOISE_GATE_VOLUME is a pure function (no side effects,
    # by design - see its own comment) - calling it right before
    # SOUND_UPDATE captures the REAL value the ASM itself computes for
    # this frame, not a hand-rederivation, since SOUND_UPDATE reads the
    # exact same SND_TIMER/SND_NOISE/TICK moments later.
    call_routine(cpu, "SOUND_CALC_NOISE_GATE_VOLUME")
    written_trace.append(cpu.a)
    call_routine(cpu, "SOUND_UPDATE")
    cpu.mem[TICK] = (cpu.mem[TICK] + 1) & 0xFF
expected = expected_gated_trace(SHOT_SND_PEAK, SHOT_SND_DECAY, 6, tick_start=0)
check(f"SOUND_SHOT's own output through SOUND_UPDATE follows the expected gated/"
      f"decaying trace over 6 frames (expected {expected}, got {written_trace})",
      written_trace == expected)

# ---------------------------------------------------------------------
# 3: SOUND_ZUM_DEFLECT's own linear path is NEVER gated - the written
# value is always exactly SND_TIMER, on every frame, regardless of
# TICK's own parity.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, "SOUND_ZUM_DEFLECT")
mismatches = []
for tick in range(6):
    cpu.mem[TICK] = tick
    call_routine(cpu, "SOUND_CALC_NOISE_GATE_VOLUME")
    if cpu.a != cpu.mem[SND_TIMER]:
        mismatches.append((tick, cpu.a, cpu.mem[SND_TIMER]))
check(f"SOUND_ZUM_DEFLECT's own SND_NOISE=0 state makes SOUND_CALC_NOISE_GATE_"
      f"VOLUME always return the raw (ungated) SND_TIMER, on every TICK parity "
      f"({len(mismatches)} mismatches)",
      not mismatches)

# ---------------------------------------------------------------------
# 4: SOUND_SPARK_CRACKLE (the SPARK burst's own new sound) is gated too,
# same as SOUND_SHOT above.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, "SOUND_SPARK_CRACKLE")
crackle_trace = []
cpu.mem[TICK] = 0
for i in range(4):
    call_routine(cpu, "SOUND_CALC_NOISE_GATE_VOLUME")
    crackle_trace.append(cpu.a)
    call_routine(cpu, "SOUND_UPDATE")
    cpu.mem[TICK] = (cpu.mem[TICK] + 1) & 0xFF
expected_crackle = expected_gated_trace(SPARK_CRACKLE_PEAK, SPARK_CRACKLE_DECAY, 4, tick_start=0)
check(f"SOUND_SPARK_CRACKLE's own output through SOUND_UPDATE follows the expected "
      f"gated/decaying trace too (expected {expected_crackle}, got {crackle_trace})",
      crackle_trace == expected_crackle)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
