"""Verifies the "Comb" build (build_full_rom.py embedding the REAL
tools/stage2_combined content as bank2/bank3, replacing the old
build_stage2_world.py placeholder) actually boots correctly end to end
in the emulator - exercises the exact production functions
(assemble_game/assemble_real_stage2), not a reimplementation.

The specific risk this checks: combined_test.asm's own INIT does its
own one-time bank-select for window B, hardcoded as "select MY bank 1"
in its own standalone 2-bank numbering. Embedded here it's actually
global bank index 3, not 1 - assemble_real_stage2() patches that on an
in-memory copy (see build_full_rom.py's STAGE2_BANKSELECT_ANCHOR/
PATCH). If that patch were ever wrong or silently stopped applying
(e.g. combined_test.asm's own text drifting past the anchor - though
that would fail loudly at build time via the assert in
assemble_real_stage2() first), stage2's own INIT would instead select
bank index 1 (stage 1's OWN page2 content) for window B, corrupting
window B right at the start of stage2's boot. This test would catch
that as bankB != 3 after the switch, well before it got anywhere near
game logic reading nonsense.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, HERE)
import z80emu
from build_full_rom import assemble_game, assemble_real_stage2


class BankedMem:
    """4-bank ASCII16 mapper emulation matching the real Comb ROM's own
    global bank numbering exactly (0=stage1 page1, 1=stage1 page2,
    2=stage2 page1, 3=stage2 page2) - same shape as verify_full.py's
    own BankedMem."""
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


bank0, bank1, gsym = assemble_game()
bank2, bank3, s2sym = assemble_real_stage2()

# Sanity check this is genuinely tools/stage2_combined's real content,
# not somehow still the old simple-enemies placeholder (which has no
# boss and therefore no BOSS_SPAWN_TICK symbol at all).
assert "BOSS_SPAWN_TICK" in s2sym, "stage2 symtab missing BOSS_SPAWN_TICK - not the real stage2_combined content?"
print("confirmed: bank2/bank3 are the real stage2_combined content (BOSS_SPAWN_TICK present)")

bank_dummyA = bytearray([0xFF] * 0x4000)
bank_dummyB = bytearray([0xFF] * 0x4000)
mem = BankedMem(banksA=[bank0, bank_dummyA, bank2], banksB=[bank_dummyB, bank1, bank_dummyB, bank3])
cpu = z80emu.Z80(mem)
cpu.pc = gsym["INIT"]
cpu.sp = gsym["STACKTOP"]

MAINLOOP = gsym["MAINLOOP"]
PLAYER_FLYAWAY = gsym["PLAYER_FLYAWAY"]

steps = 0
while cpu.pc != MAINLOOP and steps < 2_000_000:
    cpu.step()
    steps += 1
print(f"stage1 reached MAINLOOP after {steps} steps, bankA={mem.bankA} bankB={mem.bankB} (expect A=0,B=1)")
assert cpu.pc == MAINLOOP
assert mem.bankA == 0 and mem.bankB == 1, "stage1's own explicit bank1 select in INIT did not take effect"

mem.flat[PLAYER_FLYAWAY] = 2
print("poked PLAYER_FLYAWAY=2 (simulating boss-destroyed + flyaway-complete)")

STAGE2_INIT = s2sym["INIT"]
switched = False
steps2 = 0
while steps2 < 2_000_000:
    if cpu.pc == STAGE2_INIT and mem.bankA == 2:
        switched = True
        break
    cpu.step()
    steps2 += 1
print(f"after {steps2} more steps: pc={cpu.pc:04x} bankA={mem.bankA} bankB={mem.bankB}")
assert switched, "never reached real stage2's INIT (bank2) within step budget"
assert mem.bankA == 2 and mem.bankB == 3, "banks not switched to real stage2 (2,3) on entry to its INIT"

# Now run stage2's OWN boot (combined_test.asm's INIT does its own
# one-time window-B bank-select as part of booting standalone - this is
# the exact spot the STAGE2_BANKSELECT patch targets). Confirm bankB is
# STILL 3 (not clobbered back to the unpatched "1") the whole way
# through to stage2's own MAINLOOP.
steps3 = 0
saw_bankB_drift = None
while cpu.pc != s2sym["MAINLOOP"] and steps3 < 2_000_000:
    cpu.step()
    steps3 += 1
    if mem.bankB != 3:
        saw_bankB_drift = (steps3, mem.bankB, cpu.pc)
        break
assert saw_bankB_drift is None, (
    f"bankB drifted away from 3 during stage2's own boot: {saw_bankB_drift} "
    "(the STAGE2_BANKSELECT_ANCHOR/PATCH retarget likely isn't taking effect)"
)
print(f"real stage2 reached its own MAINLOOP after {steps3} more steps, bankB stayed 3 throughout its own boot")
assert cpu.pc == s2sym["MAINLOOP"]

print()
print("COMB BUILD (STAGE1 -> REAL STAGE2) BANK-SWITCH INTEGRATION: ALL CHECKS PASSED")
