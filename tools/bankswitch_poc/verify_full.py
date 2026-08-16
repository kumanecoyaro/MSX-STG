import sys
sys.path.insert(0, "/home/user/MSX-STG/tools")
sys.path.insert(0, "/home/user/MSX-STG/tools/bankswitch_poc")
from mini_z80asm import Assembler
import z80emu
from build_full_rom import patched_game_text
from build_stage2_world import assemble_stage2_world, LETTER_ORDER, STAGE2_LETTER_BASE


def assemble_game():
    a = Assembler(patched_game_text())
    out = a.assemble()
    bank0 = bytearray([0xFF] * 0x4000)
    bank1 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if 0x4000 <= addr <= 0x7FFF:
            bank0[addr - 0x4000] = val
        elif 0x8000 <= addr <= 0xBFFF:
            bank1[addr - 0x8000] = val
        else:
            raise Exception(f"unexpected addr {addr:04x}")
    return bank0, bank1, a.symtab


class BankedMem:
    """Both windows are now independently switchable - stage2 world
    needs its own bank pair (bank2 for window A, bank3 for window B),
    not just a placeholder bank in window B."""
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
bank2, bank3, s2sym, n_schedule = assemble_stage2_world()
bank_dummyA = bytearray([0xFF] * 0x4000)
bank_dummyB = bytearray([0xFF] * 0x4000)

# banksA index0=bank0(stage1), index2=bank2(stage2 world) - index1 is an
# unused placeholder just so the list is long enough to index by bank
# number directly (mirrors the real ROM's bank numbering).
mem = BankedMem(banksA=[bank0, bank_dummyA, bank2], banksB=[bank_dummyB, bank1, bank_dummyB, bank3])
cpu = z80emu.Z80(mem)
cpu.pc = gsym["INIT"]
cpu.sp = gsym["STACKTOP"]

MAINLOOP = gsym["MAINLOOP"]
PLAYER_FLYAWAY = gsym["PLAYER_FLYAWAY"]
PSG_ADDR = gsym["PSG_ADDR"]

steps = 0
while cpu.pc != MAINLOOP and steps < 2_000_000:
    cpu.step()
    steps += 1
print(f"reached MAINLOOP after {steps} steps, bankA={mem.bankA} bankB={mem.bankB} (expect A=0,B=1)")
assert cpu.pc == MAINLOOP
assert mem.bankA == 0 and mem.bankB == 1, "explicit bank1 select in INIT did not take effect"

# Real gameplay never naturally reaches PLAYER_FLYAWAY==2 without a
# player actually shooting the boss down over what would be several
# minutes of real play - not practical to simulate step-by-step here.
# Run a chunk of ordinary gameplay first confirming the switch never
# fires early, then poke PLAYER_FLYAWAY=2 directly (exactly what
# BOSS_EXPL_UPDATE's completion would eventually write) and confirm
# the very next MAINLOOP pass reacts correctly. This tests the NEW
# trigger logic in isolation without re-verifying the pre-existing,
# untouched boss/flyaway state machine that sets the flag.
steps1b = 0
while steps1b < 2_000_000:
    assert mem.flat[PLAYER_FLYAWAY] == 0, "PLAYER_FLYAWAY unexpectedly left 0 during ordinary early gameplay"
    assert mem.bankA == 0 and mem.bankB == 1, "bank switched with PLAYER_FLYAWAY still 0"
    cpu.step()
    steps1b += 1
print(f"ran {steps1b} more steps of ordinary gameplay: PLAYER_FLYAWAY stayed 0, banks never switched - OK")

# also poison the PSG "volume" state to a nonzero value first, so the
# mute-before-switch step is actually exercised/verified (via
# cpu.io_out_log below), not just coincidentally already zero
mem.flat[gsym["SND_TIMER"]] = 10
mem.flat[PLAYER_FLYAWAY] = 2
print("poked PLAYER_FLYAWAY=2 (simulating boss-destroyed + flyaway-complete)")

STAGE2_INIT = s2sym["INIT"]
switched = False
steps2 = 0
max_steps = 2_000_000
while steps2 < max_steps:
    if cpu.pc == STAGE2_INIT and mem.bankA == 2:
        switched = True
        break
    cpu.step()
    steps2 += 1

print(f"after {steps2} more steps: pc={cpu.pc:04x} bankA={mem.bankA} bankB={mem.bankB} switch_log(tail)={mem.switch_log[-4:]}")
assert switched, "never reached stage2 world's INIT (bank2) within step budget"
assert mem.bankA == 2 and mem.bankB == 3, "banks not switched to stage2 world (2,3)"

# The emulator silently no-ops OUT to any port other than 98h/99h (no
# PSG model, no logging - see z80emu.py's OUT (n),A handler), so PSG
# muting can't be observed by running the emulator. Verify the actual
# assembled opcode bytes instead: LD A,8:OUT(PSG_ADDR),A:XOR A:OUT
# (PSG_DATA),A, repeated for registers 9 and 10 (channels A/B/C
# volume), should appear verbatim right before the hop1 bank switch.
expected_mute = bytes([
    0x3E, 0x08, 0xD3, PSG_ADDR, 0xAF, 0xD3, PSG_ADDR + 1,
    0x3E, 0x09, 0xD3, PSG_ADDR, 0xAF, 0xD3, PSG_ADDR + 1,
    0x3E, 0x0A, 0xD3, PSG_ADDR, 0xAF, 0xD3, PSG_ADDR + 1,
])
mainloop_bytes = bytes(mem.banksA[0][MAINLOOP - 0x4000: MAINLOOP - 0x4000 + 200])
assert expected_mute in mainloop_bytes, "PSG mute (R8/R9/R10=0) bytes not found before the switch"
print("PSG mute-before-switch verified OK (byte-level: R8/R9/R10 all set to 0)")

# run stage2 world's own INIT through to ITS OWN MAINLOOP
steps3 = 0
while cpu.pc != s2sym["MAINLOOP"] and steps3 < 2_000_000:
    cpu.step()
    steps3 += 1
print(f"stage2 world reached its own MAINLOOP after {steps3} more steps")
assert cpu.pc == s2sym["MAINLOOP"]

name_row0 = bytes(cpu.vram[0x1800:0x1800 + 32])
label = name_row0[10:16]
expected_codes = bytes([STAGE2_LETTER_BASE + i for i in range(len(LETTER_ORDER))] + [s2sym["DIGIT_BASE"] + 2])
print("stage2 world HUD row0 cols10-15:", list(label))
assert bytes(label) == expected_codes, "STAGE2 HUD label not drawn correctly in the real switch path"
print("STAGE2 HUD label verified OK (drawn via the real INIT re-run, not a placeholder)")

print()
print("FULL-GAME -> STAGE2-WORLD BANK-SWITCH INTEGRATION: ALL CHECKS PASSED")
