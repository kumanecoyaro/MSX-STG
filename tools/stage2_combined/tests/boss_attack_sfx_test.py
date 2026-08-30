"""Verifies the 4 new boss-attack SFX added in round36-14 follow-up#5
("ではボス攻撃にサウンドを入れる ホーミング、サンダー、サンダービーム、
ササピーレーザーそれぞれに") - SOUND_HORMING/SOUND_THUNDER/SOUND_SBEAM/
SOUND_SASAPI_LASER, each chosen by the user out of 3 auditioned Web
Audio candidates (H2/T3/S1/L3) built to mirror this exact PSG envelope
engine, then "それぞれ音量は最大で" (peak forced to 15 for all 4).

z80emu.py has no PSG emulation (OUT only actually does anything for the
VDP ports - see boss_boom_sound_test.py's own comment for the established
precedent this file follows), so what's verified is the resulting
envelope RAM state (SND_TIMER/SND_DECAY/SND_NOISE/SND_EXPLODING/
SND_BOOM_DECAY_CTR) after each routine runs, plus that the real in-game
trigger site (missile launch / thunder bolt / beam drop / broken-form
beam launch) actually calls it.
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
SND_BOOM_DECAY_CTR = sym["SND_BOOM_DECAY_CTR"]
BOSS_BOOM_DECAY_PERIOD = sym["BOSS_BOOM_DECAY_PERIOD"]
HORMING_NOISE_PERIOD = sym["HORMING_NOISE_PERIOD"]
HORMING_SND_DECAY = sym["HORMING_SND_DECAY"]
THUNDER_NOISE_PERIOD = sym["THUNDER_NOISE_PERIOD"]
SBEAM_SND_TONE_PERIOD = sym["SBEAM_SND_TONE_PERIOD"]
SBEAM_SND_DECAY = sym["SBEAM_SND_DECAY"]
SASAPI_LASER_TONE_PERIOD = sym["SASAPI_LASER_TONE_PERIOD"]
SASAPI_LASER_SND_DECAY = sym["SASAPI_LASER_SND_DECAY"]

HORMING_VOLLEY_COUNT = sym["HORMING_VOLLEY_COUNT"]
HORMING_VOLLEY_TIMER = sym["HORMING_VOLLEY_TIMER"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
THUNDER_LEG_START_X = sym["THUNDER_LEG_START_X"]
THUNDER_TRIGGER_DX = sym["THUNDER_TRIGGER_DX"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_BROKEN_BEAM_COUNT = sym["BOSS_BROKEN_BEAM_COUNT"]


def arm_silence(cpu):
    """resets the shared envelope to a known-silent state, so a test can
    tell whether the routine under test actually re-armed it."""
    cpu.mem[SND_TIMER] = 0
    cpu.mem[SND_DECAY] = 0
    cpu.mem[SND_NOISE] = 0
    cpu.mem[SND_EXPLODING] = 1  # also proves each new sound clears this itself


# ============================================================
# direct unit tests: each SOUND_* routine's own envelope setup
# ============================================================

cpu = fresh_cpu()
arm_silence(cpu)
call_routine(cpu, "SOUND_HORMING")
check("SOUND_HORMING sets peak volume to the hardware max (15) - 'それぞれ音量は最大で'",
      cpu.mem[SND_TIMER] == 15)
check(f"SOUND_HORMING sets SND_DECAY to HORMING_SND_DECAY({HORMING_SND_DECAY})",
      cpu.mem[SND_DECAY] == HORMING_SND_DECAY)
check("SOUND_HORMING is a noise sound (SND_NOISE=1, duty-gated - matches the auditioned H2 "
      "'ノイズ・ウィッシュ' candidate)", cpu.mem[SND_NOISE] == 1)
check("SOUND_HORMING clears SND_EXPLODING - a repeating attack cue, not a one-off dramatic "
      "event, so it must not block the player's own shot sound the way SOUND_DESTROY/"
      "SOUND_BOSS_BOOM deliberately do", cpu.mem[SND_EXPLODING] == 0)

cpu = fresh_cpu()
arm_silence(cpu)
call_routine(cpu, "SOUND_THUNDER")
check("SOUND_THUNDER sets peak volume to 15", cpu.mem[SND_TIMER] == 15)
check("SOUND_THUNDER uses 'boom mode' (SND_DECAY=0) - reusing SOUND_BOSS_BOOM's own long-decay "
      "mechanism unchanged, matching the auditioned T3 'long rumble' candidate",
      cpu.mem[SND_DECAY] == 0)
check(f"SOUND_THUNDER arms SND_BOOM_DECAY_CTR with the SAME BOSS_BOOM_DECAY_PERIOD"
      f"({BOSS_BOOM_DECAY_PERIOD}) SOUND_BOSS_BOOM itself uses - no new decay-pacing constant",
      cpu.mem[SND_BOOM_DECAY_CTR] == BOSS_BOOM_DECAY_PERIOD)
check("SOUND_THUNDER is a noise sound (SND_NOISE=1)", cpu.mem[SND_NOISE] == 1)
check("SOUND_THUNDER clears SND_EXPLODING (repeating attack, must not block SOUND_SHOT for its "
      "own long boom-style decay - deliberately different from SOUND_BOSS_BOOM's own choice)",
      cpu.mem[SND_EXPLODING] == 0)

cpu = fresh_cpu()
arm_silence(cpu)
call_routine(cpu, "SOUND_SBEAM")
check("SOUND_SBEAM sets peak volume to 15", cpu.mem[SND_TIMER] == 15)
check(f"SOUND_SBEAM sets SND_DECAY to SBEAM_SND_DECAY({SBEAM_SND_DECAY}) - a long ~15-frame "
      "sustain, matching the auditioned S1 'fast tremolo tone' candidate's own duration",
      cpu.mem[SND_DECAY] == SBEAM_SND_DECAY)
check("SOUND_SBEAM applies the duty gate (SND_NOISE=1) to a TONE channel, not noise - the "
      "existing 1:1 gate mechanism reused for the first time on a tone SFX, since 60fps is "
      "already the fastest amplitude modulation this engine can produce, making a bespoke "
      "'faster' gate mode pointless to add",
      cpu.mem[SND_NOISE] == 1)
check("SOUND_SBEAM clears SND_EXPLODING", cpu.mem[SND_EXPLODING] == 0)

cpu = fresh_cpu()
arm_silence(cpu)
call_routine(cpu, "SOUND_SASAPI_LASER")
check("SOUND_SASAPI_LASER sets peak volume to 15 (bumped up from Stage1's own original 12, "
      "per 'それぞれ音量は最大で')", cpu.mem[SND_TIMER] == 15)
check(f"SOUND_SASAPI_LASER sets SND_DECAY to SASAPI_LASER_SND_DECAY({SASAPI_LASER_SND_DECAY})",
      cpu.mem[SND_DECAY] == SASAPI_LASER_SND_DECAY)
check("SOUND_SASAPI_LASER applies the duty gate (SND_NOISE=1) - the L3 'デューティ版' pick, "
      "deliberately NOT matching Stage1's own original ungated SOUND_SHOT",
      cpu.mem[SND_NOISE] == 1)
check("SOUND_SASAPI_LASER clears SND_EXPLODING", cpu.mem[SND_EXPLODING] == 0)

# the 2 tone-pitch constants must match their own stated real-world
# reference exactly - SASAPI_LASER's own period is meant to be byte-for-
# byte Stage1's real SOUND_SHOT tone period (not just "close").
check("SASAPI_LASER_TONE_PERIOD is exactly 30 - src/CYBER SHMUP.asm's own SOUND_SHOT tone "
      "period value, transcribed verbatim (not re-derived/approximated)",
      SASAPI_LASER_TONE_PERIOD == 30)


# ============================================================
# integration checks: the real in-game trigger site actually calls the
# new sound, not just "the routine exists and works in isolation"
# ============================================================

cpu = fresh_cpu()
call_routine(cpu, "ARM_HORMING_VOLLEY")
arm_silence(cpu)
call_routine(cpu, "UPDATE_HORMING_VOLLEY")  # TIMER was armed to 0 - fires immediately
check("UPDATE_HORMING_VOLLEY's own first launch tick (UHV_FIRE) really does trigger "
      "SOUND_HORMING - not just a routine that exists but is never actually wired in",
      cpu.mem[SND_TIMER] == 15 and cpu.mem[SND_DECAY] == HORMING_SND_DECAY
      and cpu.mem[SND_NOISE] == 1)

# a 2nd volley tick (a later pair launching) re-triggers it again, not
# just once per whole volley. TIMER was just armed to HORMING_VOLLEY_
# INTERVAL by the first fire, so it takes exactly that many more calls
# to decrement it back to 0, plus 1 more call for the fire itself.
for _ in range(sym["HORMING_VOLLEY_INTERVAL"]):
    call_routine(cpu, "UPDATE_HORMING_VOLLEY")
arm_silence(cpu)
call_routine(cpu, "UPDATE_HORMING_VOLLEY")
check("SOUND_HORMING re-triggers on every subsequent launch tick too, not just the first",
      cpu.mem[SND_TIMER] == 15)

# CHECK_THUNDER_TRIGGER_LEFT and CHECK_THUNDER_TRIGGER_RIGHT are 2
# entirely SEPARATE routines with their own independent fire tails (only
# the RIGHT one is actually named CTTR_FIRE - a naming coincidence, not
# a shared code path) - real bug caught here during this exact test's
# own first draft: SOUND_THUNDER was only wired into CTTR_FIRE (RIGHT),
# so the LEFT-edge trigger fired silently until both were covered.
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 100 - THUNDER_TRIGGER_DX
arm_silence(cpu)
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT's own (separate) fire tail really does trigger SOUND_THUNDER "
      "when a bolt actually fires",
      cpu.mem[SND_TIMER] == 15 and cpu.mem[SND_DECAY] == 0
      and cpu.mem[SND_BOOM_DECAY_CTR] == BOSS_BOOM_DECAY_PERIOD)

cpu2 = fresh_cpu()
cpu2.mem[THUNDER_PENDING] = 1
cpu2.mem[THUNDER_LEG_START_X] = 100 - THUNDER_TRIGGER_DX
cpu2.mem[BOSS_X] = 100
arm_silence(cpu2)
call_routine(cpu2, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT's own CTTR_FIRE tail ALSO triggers SOUND_THUNDER - both "
      "directions covered independently, not just the leftward leg",
      cpu2.mem[SND_TIMER] == 15 and cpu2.mem[SND_DECAY] == 0
      and cpu2.mem[SND_BOOM_DECAY_CTR] == BOSS_BOOM_DECAY_PERIOD)

cpu = fresh_cpu()
arm_silence(cpu)
call_routine(cpu, "FIRE_SBEAM")
check("FIRE_SBEAM really does trigger SOUND_SBEAM",
      cpu.mem[SND_TIMER] == 15 and cpu.mem[SND_DECAY] == SBEAM_SND_DECAY
      and cpu.mem[SND_NOISE] == 1)

cpu = fresh_cpu()
cpu.mem[BOSS_X] = 100
cpu.mem[BOSS_Y] = 80
cpu.mem[BOSS_BROKEN_BEAM_COUNT] = 0
arm_silence(cpu)
call_routine(cpu, "LAUNCH_BOSS_BROKEN_BEAM")
check("LAUNCH_BOSS_BROKEN_BEAM really does trigger SOUND_SASAPI_LASER on every launch, not "
      "just the reveal/first beam",
      cpu.mem[SND_TIMER] == 15 and cpu.mem[SND_NOISE] == 1)
# spot-check a 2nd, different beam slot too - not hardcoded to slot0.
arm_silence(cpu)
cpu.mem[BOSS_BROKEN_BEAM_COUNT] = 3
call_routine(cpu, "LAUNCH_BOSS_BROKEN_BEAM")
check("...and again for a different beam (slot3/beam4), not just the first one",
      cpu.mem[SND_TIMER] == 15)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
