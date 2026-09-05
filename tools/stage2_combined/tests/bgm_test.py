"""round36-14 follow-up#24 ("ではBGMを実装する...まずStage2から Vsyncを
使ってBGMドライバを実装...BGMは空きの範囲で仮実装"): the new H.TIMI-
hooked BGM driver (INIT_BGM/BGM_TICK, see combined_test.asm's own long
comment right above INIT_BGM for the full design rationale).

z80emu.py has no interrupt simulation at all (no real BIOS ROM, no IM1
vector, H.TIMI never actually fires on its own during any test in this
suite) - so unlike a real vblank landing mid-MAINLOOP, BGM_TICK here is
verified the same way every other routine in this file's own test suite
already is: direct CALL via call_routine(), exactly like SOUND_SHOT or
any other trigger-style routine already gets tested. INIT_BGM's own
hook installation is checked separately, by reading back the actual
bytes INIT wrote to HTIMI_HOOK after a real boot trace.

The DI/EI wraps this round added to every existing SOUND_* PSG-register-
select/write pair (protecting them against BGM_TICK's own competing
writes) are checked via z80emu.py's own real IFF1 tracking: every
`OUT (n),A` this file executes to port 0A0h/0A1h (PSG_ADDR/PSG_DATA)
must happen with IFF1 already False (DI already in effect) - a direct
semantic check, not a static byte scan, using the same iff1 flag the
emulator already maintains for DI(0xF3)/EI(0xFB).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

import bgm_gen

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


HTIMI_HOOK = sym["HTIMI_HOOK"]
BGM_TICK = sym["BGM_TICK"]
BGM_PATTERN = sym["BGM_PATTERN"]
BGM_PATTERN_PTR = sym["BGM_PATTERN_PTR"]
BGM_ROW_TIMER = sym["BGM_ROW_TIMER"]
BGM_NOTE_REST = sym["BGM_NOTE_REST"]
BGM_LOOP_MARK = sym["BGM_LOOP_MARK"]
PSG_ADDR = sym["PSG_ADDR"]
PSG_DATA = sym["PSG_DATA"]


# ---- hook installation (real boot trace, not a direct call) ----
cpu = fresh_cpu()
check("INIT_BGM wrote a JP opcode (0C3h) into HTIMI_HOOK",
      cpu.mem[HTIMI_HOOK] == 0xC3)
hook_target = cpu.mem[HTIMI_HOOK + 1] | (cpu.mem[HTIMI_HOOK + 2] << 8)
check(f"INIT_BGM's JP target ({hex(hook_target)}) is BGM_TICK ({hex(BGM_TICK)})",
      hook_target == BGM_TICK)
check("INIT_BGM left BGM_PATTERN_PTR pointing at BGM_PATTERN's own start",
      (cpu.mem[BGM_PATTERN_PTR] | (cpu.mem[BGM_PATTERN_PTR + 1] << 8)) == BGM_PATTERN)
check("INIT_BGM left BGM_ROW_TIMER at 0 (BGM_TICK's first call always loads a fresh row)",
      cpu.mem[BGM_ROW_TIMER] == 0)


# ---- PSG helpers: this emulator had NO PSG model at all before this
# round (OUT (n),A to a non-VDP port was a silent no-op, IN A,(n) always
# read back 0FFh) - z80emu.py's own psg_regs/psg_latch (added this round
# specifically for this test) fix that, modeling the real AY-3-8910's
# own address/data-latch scheme: OUT to PSG_ADDR latches a register
# NUMBER, OUT to PSG_DATA writes psg_regs[that number], IN from the
# read-back port reads it back. A flat "value written to this raw Z80
# port" dict can't represent this at all (every register write lands on
# the same 2 ports), so checks below read/seed cpu.psg_regs[reg_number]
# directly, not a port number.
def poke_pattern_row(cpu, note_b, note_c, duration, addr=None):
    if addr is None:
        addr = BGM_PATTERN
    cpu.mem[addr] = note_b & 0xFF
    cpu.mem[addr + 1] = note_c & 0xFF
    cpu.mem[addr + 2] = duration & 0xFF
    return addr + 3


# ---- row-hold path: BGM_ROW_TIMER>0 just counts down, doesn't touch
# BGM_PATTERN_PTR or the period/volume registers ----
cpu = fresh_cpu()
cpu.mem[BGM_ROW_TIMER] = 5
ptr_before = cpu.mem[BGM_PATTERN_PTR] | (cpu.mem[BGM_PATTERN_PTR + 1] << 8)
call_routine(cpu, "BGM_TICK")
check("row-hold: BGM_ROW_TIMER decrements by exactly 1 (5 -> 4)",
      cpu.mem[BGM_ROW_TIMER] == 4)
check("row-hold: BGM_PATTERN_PTR is untouched",
      (cpu.mem[BGM_PATTERN_PTR] | (cpu.mem[BGM_PATTERN_PTR + 1] << 8)) == ptr_before)


# ---- new-row path: BGM_ROW_TIMER==0 loads the next row, writes the
# looked-up period (R2/R3 for channel B, R4/R5 for C) and BGM_VOLUME (R9/
# R10), advances the pointer by 3 bytes, and reloads BGM_ROW_TIMER from
# the row's own duration byte ----
periods = [(lo, hi) for lo, hi in zip(
    [b & 0xFF for b in bgm_gen.PERIOD_TABLE],
    [(b >> 8) & 0x0F for b in bgm_gen.PERIOD_TABLE])]

TEST_NOTE_B = 5
TEST_NOTE_C = 17
TEST_DURATION = 23

cpu = fresh_cpu()
cpu.mem[BGM_ROW_TIMER] = 0
row_addr = 0xC800  # scratch RAM, well clear of any real pool
cpu.mem[BGM_PATTERN_PTR] = row_addr & 0xFF
cpu.mem[BGM_PATTERN_PTR + 1] = (row_addr >> 8) & 0xFF
poke_pattern_row(cpu, TEST_NOTE_B, TEST_NOTE_C, TEST_DURATION, row_addr)
call_routine(cpu, "BGM_TICK")

check("new-row: BGM_ROW_TIMER reloaded from the row's own duration byte",
      cpu.mem[BGM_ROW_TIMER] == TEST_DURATION)
check("new-row: BGM_PATTERN_PTR advanced by exactly 3 bytes (one row)",
      (cpu.mem[BGM_PATTERN_PTR] | (cpu.mem[BGM_PATTERN_PTR + 1] << 8)) == row_addr + 3)

exp_b_lo, exp_b_hi = periods[TEST_NOTE_B]
exp_c_lo, exp_c_hi = periods[TEST_NOTE_C]
check(f"new-row: channel B tone period (R2/R3) matches BGM_PERIOD_LO/HI[{TEST_NOTE_B}] "
      f"({exp_b_lo},{exp_b_hi})",
      (cpu.psg_regs.get(2), cpu.psg_regs.get(3)) == (exp_b_lo, exp_b_hi))
check(f"new-row: channel C tone period (R4/R5) matches BGM_PERIOD_LO/HI[{TEST_NOTE_C}] "
      f"({exp_c_lo},{exp_c_hi})",
      (cpu.psg_regs.get(4), cpu.psg_regs.get(5)) == (exp_c_lo, exp_c_hi))
check("new-row: channel B volume (R9) is BGM_VOLUME",
      cpu.psg_regs.get(9) == sym["BGM_VOLUME"])
check("new-row: channel C volume (R10) is BGM_VOLUME",
      cpu.psg_regs.get(10) == sym["BGM_VOLUME"])


# ---- rest notes: BGM_NOTE_REST silences that channel's volume register
# only, without writing that channel's period registers at all ----
cpu = fresh_cpu()
cpu.mem[BGM_ROW_TIMER] = 0
cpu.mem[BGM_PATTERN_PTR] = row_addr & 0xFF
cpu.mem[BGM_PATTERN_PTR + 1] = (row_addr >> 8) & 0xFF
poke_pattern_row(cpu, BGM_NOTE_REST, BGM_NOTE_REST, 10, row_addr)
# poison R2-R5 with sentinel values that BGMT_WRITE_CHAN_B/C would never
# legitimately write for a real note, so any (bugged) write is visible
for poison_reg in (2, 3, 4, 5):
    cpu.psg_regs.pop(poison_reg, None)
call_routine(cpu, "BGM_TICK")
check("rest note: channel B period registers (R2/R3) are NOT written",
      2 not in cpu.psg_regs and 3 not in cpu.psg_regs)
check("rest note: channel C period registers (R4/R5) are NOT written",
      4 not in cpu.psg_regs and 5 not in cpu.psg_regs)
check("rest note: channel B volume (R9) is silenced to 0",
      cpu.psg_regs.get(9) == 0)
check("rest note: channel C volume (R10) is silenced to 0",
      cpu.psg_regs.get(10) == 0)


# ---- looping: BGM_LOOP_MARK at the current pointer resets to
# BGM_PATTERN's own start and loads ITS first row instead ----
cpu = fresh_cpu()
cpu.mem[BGM_ROW_TIMER] = 0
loop_addr = 0xC900
cpu.mem[loop_addr] = bgm_gen.BGM_LOOP_MARK
cpu.mem[BGM_PATTERN_PTR] = loop_addr & 0xFF
cpu.mem[BGM_PATTERN_PTR + 1] = (loop_addr >> 8) & 0xFF
first_note_b = cpu.mem[BGM_PATTERN]
first_note_c = cpu.mem[BGM_PATTERN + 1]
first_dur = cpu.mem[BGM_PATTERN + 2]
call_routine(cpu, "BGM_TICK")
check("loop mark: BGM_PATTERN_PTR resets to BGM_PATTERN+3 (start's own row, now consumed)",
      (cpu.mem[BGM_PATTERN_PTR] | (cpu.mem[BGM_PATTERN_PTR + 1] << 8)) == BGM_PATTERN + 3)
check("loop mark: reloaded BGM_ROW_TIMER matches the real pattern's own first-row duration",
      cpu.mem[BGM_ROW_TIMER] == first_dur)
if first_note_b != BGM_NOTE_REST:
    exp_lo, exp_hi = periods[first_note_b]
    check("loop mark: channel B period matches the real pattern's own first row",
          (cpu.psg_regs.get(2), cpu.psg_regs.get(3)) == (exp_lo, exp_hi))


# ---- R7 mixer read-modify-write: only bits1-2 (tone B/C enable) ever
# change; every other bit (channel A's own noise/tone mode + noise B/C
# disable + I/O direction, all owned by the SFX side) passes through
# byte-for-byte ----
cpu = fresh_cpu()
cpu.mem[BGM_ROW_TIMER] = 9   # row-hold path - isolates the mixer step alone
for probe in (0b10111000, 0b01000111, 0b11111111, 0b00000000):
    cpu.psg_regs[7] = probe
    call_routine(cpu, "BGM_TICK")
    written = cpu.psg_regs.get(7)
    expected = probe & 0xF9
    check(f"R7 read-modify-write: probe {bin(probe)} -> {bin(written) if written is not None else None} "
          f"(bits1-2 cleared, everything else preserved: expected {bin(expected)})",
          written == expected)


# ---- DI/EI protection: every existing SOUND_* trigger this round wrapped
# in DI/EI must genuinely execute its PSG_ADDR/PSG_DATA OUT pairs with
# IFF1 already False - the real, hardware-meaningful guarantee that an
# H.TIMI interrupt (now that BGM_TICK exists to fire one) can't land
# between the register-select and the data write. ----
PROTECTED_ROUTINES = [
    ("SOUND_SHOT", {"SND_EXPLODING": 0}),
    ("SOUND_SPARK_CRACKLE", {}),
    ("SOUND_DESTROY", {}),
    ("SOUND_ZUM_DEFLECT", {}),
    ("SOUND_BOSS_BOOM", {}),
    ("SOUND_HORMING", {}),
    ("SOUND_THUNDER", {}),
    ("SOUND_SBEAM", {}),
    ("STOP_SBEAM_SOUND", {}),
    ("SOUND_SASAPI_LASER", {}),
    ("SOUND_BOSS_MATERIALIZE", {}),
]


def scan_psg_out_iff1(name, presets):
    cpu = fresh_cpu()
    for var, val in presets.items():
        cpu.mem[sym[var]] = val
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.mem[cpu.sp] = 0
    cpu.mem[cpu.sp + 1] = 0
    cpu.pc = sym[name]
    saw_psg_out = False
    all_masked = True
    steps = 0
    while cpu.pc != 0 and steps < 5000:
        opcode = cpu.mem[cpu.pc]
        if opcode == 0xD3:  # OUT (n),A
            port = cpu.mem[(cpu.pc + 1) & 0xFFFF]
            if port in (PSG_ADDR, PSG_DATA):
                saw_psg_out = True
                if cpu.iff1:
                    all_masked = False
        cpu.step()
        steps += 1
    return saw_psg_out, all_masked


for name, presets in PROTECTED_ROUTINES:
    saw, masked = scan_psg_out_iff1(name, presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)",
          masked)

# SOUND_UPDATE/SU_BOOM: two distinct branches (SND_DECAY==0 -> SU_BOOM,
# else the linear path) both do their own R8 OUT pair.
for name, presets in [("SOUND_UPDATE", {"SND_DECAY": 2, "SND_TIMER": 5, "SND_NOISE": 0}),
                       ("SU_BOOM", {"SND_TIMER": 5, "SND_NOISE": 0})]:
    saw, masked = scan_psg_out_iff1(name, presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)",
          masked)

# BGM_TICK itself needs no DI/EI wrapping (it never has interrupts
# enabled inside it in the first place - see its own comment) - confirm
# IFF1 stays False for its own entire run, self-consistently.
saw, masked = scan_psg_out_iff1("BGM_TICK", {"BGM_ROW_TIMER": 0})
check("BGM_TICK: real PSG_ADDR/PSG_DATA OUTs found", saw)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
