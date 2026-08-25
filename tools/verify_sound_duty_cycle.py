"""Verifies the round32 port of Stage2's noise-sound duty-cycle gating
into src/CYBER SHMUP.asm (Stage1) - "ステージ1もデューティ比操作を適用"
- channel A's own R8 volume write in SOUND_UPDATE now alternates every
frame between the current envelope and silence, following TICK's own
low bit, via the new CALC_NOISE_GATE_VOLUME helper. Channels B/C
(always tone in this file, unlike Stage2's shared/time-shared channel
A) are untouched.

z80emu.py has no PSG emulation at all (OUT only does anything for the
VDP ports), so the actual byte written to the PSG can never be observed
directly - same limitation Stage2's own boss_boom_sound_test.py/
noise_duty_cycle_test.py work around. What IS verified: CALC_NOISE_
GATE_VOLUME's own return value (a pure, side-effect-free function, kept
standalone specifically so it's testable this way) for a matrix of
SND_TIMER/TICK combinations, independently re-derived here rather than
read back from the ASM's own logic; that SND_TIMER itself still decays
normally through SOUND_UPDATE (the gating only affects what's WRITTEN,
not the underlying envelope); and that channels B/C's own SND_TIMER_B/
SND_TIMER_C decay completely unaffected by TICK, confirming the gate
really is scoped to channel A only.

Usage: python3 tools/verify_sound_duty_cycle.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from z80emu import Z80

SRC_PATH = os.path.join(HERE, "..", "src", "CYBER SHMUP.asm")

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


text = open(SRC_PATH, encoding="utf-8").read()
asm = Assembler(text)
out = asm.assemble()
check(f"the real file still assembles cleanly ({len(out)} bytes)", len(out) > 0)
sym = asm.symtab

TICK = sym["TICK"]
SND_TIMER = sym["SND_TIMER"]
SND_TIMER_B = sym["SND_TIMER_B"]
SND_TIMER_C = sym["SND_TIMER_C"]

mem = bytearray(65536)
for addr, val in out.items():
    mem[addr & 0xFFFF] = val & 0xFF

SENTINEL = 0x0000  # never real code - z80emu has no ROM/RAM mapped meaning there, safe as a return trap


def fresh_cpu():
    z = Z80(bytearray(mem))
    z.sp = 0xFE00
    return z


def call_routine(cpu, addr, max_instr=20000):
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.wr(cpu.sp, SENTINEL & 0xFF)
    cpu.wr((cpu.sp + 1) & 0xFFFF, (SENTINEL >> 8) & 0xFF)
    cpu.pc = addr
    steps = 0
    while cpu.pc != SENTINEL and steps < max_instr:
        cpu.step()
        steps += 1
    assert steps < max_instr, f"call to {addr:04x} never returned"


# ---------------------------------------------------------------------
# 1: CALC_NOISE_GATE_VOLUME itself, exercised directly - a pure function
# of SND_TIMER/TICK, independently re-derived (not read back from the
# ASM's own logic).
# ---------------------------------------------------------------------
def expected_gate(timer, tick):
    if tick & 1:
        return 0
    return timer


for timer in (0, 1, 7, 15, 14, 3):
    for tick in (0, 1, 2, 3, 62, 63):
        cpu = fresh_cpu()
        cpu.wr(SND_TIMER, timer)
        cpu.wr(TICK, tick)
        call_routine(cpu, sym["CALC_NOISE_GATE_VOLUME"])
        expected = expected_gate(timer, tick)
        check(f"CALC_NOISE_GATE_VOLUME(timer={timer},tick={tick}) == {expected} (got {cpu.a})",
              cpu.a == expected)

# ---------------------------------------------------------------------
# 2: SOUND_UPDATE's own channel-A envelope still decays normally over
# many frames - the gate only affects what's WRITTEN to the PSG, not
# the underlying SND_TIMER countdown itself.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_DESTROY"])
check("SOUND_DESTROY sets SND_TIMER to its own peak (15)", cpu.rd(SND_TIMER) == 15)
timer_trace = []
for frame in range(20):
    cpu.wr(TICK, frame)  # TICK's own real update (INC A:AND 3Fh) isn't run here - poked directly, same idiom as Stage2's own tests poking TICK between calls
    call_routine(cpu, sym["SOUND_UPDATE"])
    timer_trace.append(cpu.rd(SND_TIMER))
expected_trace = [max(0, 15 - f) for f in range(1, 21)]
check(f"SND_TIMER decays by exactly 1/frame through SOUND_UPDATE regardless of the "
      f"gating (expected {expected_trace}, got {timer_trace})",
      timer_trace == expected_trace)
check("SND_TIMER reaches exactly 0 after 15 frames (its own real peak, unaffected by "
      "the duty-cycle write gating)", timer_trace[14] == 0)

# ---------------------------------------------------------------------
# 3: channels B/C (always tone) decay completely independently of TICK -
# confirms the gate is scoped to channel A only.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_POD_FIRE"])  # channel B
call_routine(cpu, sym["SOUND_SHOT"])       # channel C
check("SOUND_POD_FIRE sets SND_TIMER_B to its own peak (15)", cpu.rd(SND_TIMER_B) == 15)
check("SOUND_SHOT sets SND_TIMER_C to its own peak (12)", cpu.rd(SND_TIMER_C) == 12)
b_trace = []
c_trace = []
for frame in range(13):
    cpu.wr(TICK, frame)  # alternates parity every frame - B/C must not care
    call_routine(cpu, sym["SOUND_UPDATE"])
    b_trace.append(cpu.rd(SND_TIMER_B))
    c_trace.append(cpu.rd(SND_TIMER_C))
expected_b = [max(0, 15 - f) for f in range(1, 14)]
expected_c = [max(0, 12 - f) for f in range(1, 14)]
check(f"SND_TIMER_B (channel B, tone) decays by exactly 1/frame regardless of TICK's "
      f"own parity (expected {expected_b}, got {b_trace})", b_trace == expected_b)
check(f"SND_TIMER_C (channel C, tone) decays by exactly 1/frame regardless of TICK's "
      f"own parity (expected {expected_c}, got {c_trace})", c_trace == expected_c)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
