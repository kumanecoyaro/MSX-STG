import copy
import os
import sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/stage2_combined
sys.path.insert(0, HERE)
import build_test
from z80emu import Z80

_OUT_CACHE = None
_BOOT_SNAPSHOT = None  # a real post-boot Z80/BankedMem, cloned (not re-booted) per fresh_cpu() call


def get_out():
    global _OUT_CACHE
    if _OUT_CACHE is None:
        _OUT_CACHE = build_test.assemble()
    return _OUT_CACHE


def fresh_cpu(assert_bank_switch=True):
    """Real cold-boot simulation: bankB starts at 0 (matching real
    ASCII16 power-on default), steps through INIT's own trampoline
    code, and only reaches MAINLOOP once bank1 has genuinely been
    selected for page2 - unlike a flat-memory model, this actually
    exercises (and can catch bugs in) the real boot-time bank-switch
    itself, not just the game logic that runs after it.

    The actual instruction-by-instruction boot only ever needs to run
    ONCE per process (same assembled ROM -> same deterministic boot
    trace every time) - every call after the first returns a fresh
    deepcopy of that one real post-boot snapshot instead of re-running
    tens of thousands of cpu.step() calls, which is what made tests
    that call fresh_cpu() many times (e.g. boss_test.py, 18 cases) slow.
    deepcopy, not a shared/reset object: each caller gets its own
    independent mem.flat/vram/registers, so nothing a test does to its
    cpu can leak into another test's."""
    global _BOOT_SNAPSHOT
    if _BOOT_SNAPSHOT is None:
        out, sym, text = get_out()
        bank0, bank1 = build_test.build_banks(out)
        mem = build_test.BankedMem(bank0, bank1)
        cpu = Z80(mem)
        cpu.pc = sym["INIT"]
        mainloop = sym["MAINLOOP"]
        steps = 0
        while cpu.pc != mainloop and steps < 300000:
            cpu.step()
            steps += 1
        assert steps < 300000, "never reached MAINLOOP"
        _BOOT_SNAPSHOT = cpu
    cpu = copy.deepcopy(_BOOT_SNAPSHOT)
    if assert_bank_switch:
        assert cpu.mem.bankB == 1, f"ASCII16 bank1 was never selected for page2 (bankB={cpu.mem.bankB})"
    return cpu


def call_routine(cpu, name, sentinel=0x8000):
    out, sym, text = get_out()
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.mem[cpu.sp] = sentinel & 0xFF
    cpu.mem[cpu.sp + 1] = (sentinel >> 8) & 0xFF
    cpu.pc = sym[name]
    s = 0
    while cpu.pc != sentinel and s < 300000:
        cpu.step()
        s += 1
    assert s < 300000, f"call_routine({name}) never returned"


def step_frame(cpu):
    out, sym, text = get_out()
    mainloop = sym["MAINLOOP"]
    cpu.step()
    s = 1
    while cpu.pc != mainloop and s < 300000:
        cpu.step()
        s += 1
    return s


