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
sys.path.insert(0, HERE)
import z80emu
from build_full_rom import assemble_title, assemble_game, assemble_real_stage2


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

# Both lists are indexed by GLOBAL bank number (0-5), matching the real
# ROM's own file layout (build_full_rom.py's rom96 concatenation order):
# window A only ever actually selects 0/2/4 (title/Stage1/Stage2 page1),
# window B only ever actually selects 1/3/5 (title/Stage1/Stage2 page2) -
# the other indices in each list are never read by this test's own code
# paths and are filled with dummy placeholders purely so the % modulo in
# __setitem__ has a dense list to index into.
dummy = bytearray([0xFF] * 0x4000)
mem = BankedMem(
    banksA=[title_bank0, dummy, game_bank0, dummy, bank4, dummy],
    banksB=[dummy, title_bank1, dummy, game_bank1, dummy, bank5],
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
print(f"title screen reached WAIT_FOR_START after {steps0} steps, bankA={mem.bankA} bankB={mem.bankB} (expect A=0,B=0)")
assert mem.bankA == 0 and mem.bankB == 0, "title screen's own boot touched the bank-select ports unexpectedly"

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

mem.flat[PLAYER_FLYAWAY] = 2
print("poked PLAYER_FLYAWAY=2 (simulating boss-destroyed + flyaway-complete)")

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

# Now run stage2's OWN boot (combined_test.asm's INIT does its own
# one-time window-B bank-select as part of booting standalone - this is
# the exact spot the STAGE2_BANKSELECT patch targets). Confirm bankB is
# STILL 5 (not clobbered back to the unpatched "1") the whole way
# through to stage2's own MAINLOOP.
steps3 = 0
saw_bankB_drift = None
while cpu.pc != s2sym["MAINLOOP"] and steps3 < 2_000_000:
    cpu.step()
    steps3 += 1
    if mem.bankB != 5:
        saw_bankB_drift = (steps3, mem.bankB, cpu.pc)
        break
assert saw_bankB_drift is None, (
    f"bankB drifted away from 5 during stage2's own boot: {saw_bankB_drift} "
    "(the STAGE2_BANKSELECT_ANCHOR/PATCH retarget likely isn't taking effect)"
)
print(f"real stage2 reached its own MAINLOOP after {steps3} more steps, bankB stayed 5 throughout its own boot")
assert cpu.pc == s2sym["MAINLOOP"]

print()
print("COMB BUILD (TITLE -> STAGE1 -> REAL STAGE2) BANK-SWITCH INTEGRATION: ALL CHECKS PASSED")
