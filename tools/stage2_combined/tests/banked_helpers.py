import os
import sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/stage2_combined
sys.path.insert(0, HERE)
import build_test
from z80emu import Z80

_OUT_CACHE = None


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
    itself, not just the game logic that runs after it."""
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
    if assert_bank_switch:
        assert mem.bankB == 1, f"ASCII16 bank1 was never selected for page2 (bankB={mem.bankB})"
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


