import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from mini_z80asm import Assembler
import z80emu

def assemble_to_bytes(path, base, size):
    text = open(path, encoding="utf-8").read()
    a = Assembler(text)
    out = a.assemble()
    buf = bytearray([0xFF] * size)
    for addr, val in out.items():
        if base <= addr < base + size:
            buf[addr - base] = val
        else:
            raise Exception(f"address {addr:04x} outside expected bank window {base:04x}-{base+size-1:04x}")
    return buf, a.symtab

bankA0, symA = assemble_to_bytes(os.path.join(HERE, "bank_a.asm"), 0x4000, 0x4000)
bankB1, symB = assemble_to_bytes(os.path.join(HERE, "bank_b1.asm"), 0x8000, 0x4000)
bankB0 = bytearray([0xFF] * 0x4000)  # bank 0 for window B: deliberately blank/untouched

class BankedMem:
    """ASCII16-style mapper: writes to PORTA/PORTB select which 16KB
    bank is currently visible at 4000h-7FFFh / 8000h-BFFFh. Anywhere
    else in those windows, writes are ignored (real ROM). Everything
    outside 4000h-BFFFh is a flat, directly-writable RAM/scratch area
    (also stands in for the low 16KB BIOS area - see the INIT32 stub
    patched in below, since this emulator has no real BIOS ROM)."""
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
            return  # ROM: writes silently ignored, matches real cartridge behavior
        self.flat[addr] = val

mem = BankedMem(banksA=[bankA0], banksB=[bankB0, bankB1])
mem.flat[0x006F] = 0xC9  # stub out the BIOS INIT32 hook (006Fh) as a bare RET -
                          # this emulator has no real BIOS ROM; real hardware
                          # has the genuine SCREEN1 initializer there instead.
cpu = z80emu.Z80(mem)
cpu.pc = symA["INIT"]
cpu.sp = 0xF380

print(f"INIT = {symA['INIT']:04x}  STAGE1_END = {symA['STAGE1_END']:04x}")
print(f"STAGE2_ENTRY = {symB['STAGE2_ENTRY']:04x}  STAGE2_LOOP = {symB['STAGE2_LOOP']:04x}")

# run the real boot sequence (header parse is just data; slot hack;
# stubbed INIT32 call; then the deliberate stage1-end switch) up to
# the moment execution lands inside bank 1's entry stub
steps = 0
while cpu.pc != symB["STAGE2_ENTRY"] and steps < 2000:
    cpu.step()
    steps += 1
print(f"after {steps} steps from INIT: pc={cpu.pc:04x} bankB={mem.bankB} switch_log={mem.switch_log}")
assert cpu.pc == symB["STAGE2_ENTRY"]
assert mem.bankB == 1, "window B did not switch to bank 1"

# run the one-shot "STAGE 2" text draw, stop right at STAGE2_LOOP
# (before it ever executes HALT - this emulator has no interrupt
# source, so HALT would spin forever; that part is standard BIOS
# vblank behavior already proven throughout the real game's own code)
steps2 = 0
while cpu.pc != symB["STAGE2_LOOP"] and steps2 < 500:
    cpu.step()
    steps2 += 1
print(f"reached STAGE2_LOOP after {steps2} more steps, pc={cpu.pc:04x}")
assert cpu.pc == symB["STAGE2_LOOP"]

name_row0 = bytes(cpu.vram[0x1800:0x1808])
print("VRAM name table row0 cols0-7 (0x1800):", name_row0, [hex(b) for b in name_row0])
assert name_row0 == b"STAGE 2 ", f"unexpected text: {name_row0!r}"

pattern_row0 = bytes(cpu.vram[0:8])
print("VRAM pattern table 0-7 (should be untouched, all 0):", list(pattern_row0))
assert pattern_row0 == bytes(8), "pattern generator table was accidentally written"

counter = mem.flat[0xE000]
print(f"counter RAM (0xE000) initialized to: {counter}")
assert counter == 0

print()
print("BANK-SWITCH POC (real-hardware-shaped ROM): ALL CHECKS PASSED")
