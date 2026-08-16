import sys
sys.path.insert(0, "/home/user/MSX-STG/tools")
sys.path.insert(0, "/home/user/MSX-STG/tools/bankswitch_poc")
from mini_z80asm import Assembler
import z80emu
from build_full_rom import patched_game_text


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


def assemble_placeholder():
    text = open("/home/user/MSX-STG/tools/bankswitch_poc/bank_b1.asm", encoding="utf-8").read()
    a = Assembler(text)
    out = a.assemble()
    bank2 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        assert 0x8000 <= addr <= 0xBFFF
        bank2[addr - 0x8000] = val
    return bank2, a.symtab


class BankedMem:
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
bank2, ssym = assemble_placeholder()
bank_dummy0 = bytearray([0xFF] * 0x4000)

mem = BankedMem(banksA=[bank0], banksB=[bank_dummy0, bank1, bank2])
cpu = z80emu.Z80(mem)
cpu.pc = gsym["INIT"]
cpu.sp = gsym["STACKTOP"]

MAINLOOP = gsym["MAINLOOP"]
GAME_TICK = gsym["GAME_TICK"]
STAGE2_ENTRY = ssym["STAGE2_ENTRY"]

steps = 0
while cpu.pc != MAINLOOP and steps < 2_000_000:
    cpu.step()
    steps += 1
print(f"reached MAINLOOP after {steps} steps, bankB={mem.bankB} (expect 1)")
assert cpu.pc == MAINLOOP
assert mem.bankB == 1, "explicit bank1 select in INIT did not take effect"

last_tick = -1
switched = False
steps2 = 0
max_steps = 30_000_000
while steps2 < max_steps:
    tick = mem.flat[GAME_TICK] | (mem.flat[GAME_TICK + 1] << 8)
    if tick != last_tick:
        if tick < 100:
            assert mem.bankB == 1, f"bank switched early at tick={tick}"
        last_tick = tick
    if cpu.pc == STAGE2_ENTRY:
        switched = True
        break
    cpu.step()
    steps2 += 1

print(f"after {steps2} more steps: pc={cpu.pc:04x} tick={last_tick} bankB={mem.bankB} switch_log(tail)={mem.switch_log[-3:]}")
assert switched, "never reached STAGE2_ENTRY within step budget"
assert mem.bankB == 2, "window B not switched to bank2 (stage2 placeholder)"
assert last_tick >= 100, f"switched too early, tick={last_tick}"

steps3 = 0
while cpu.pc != ssym["STAGE2_LOOP"] and steps3 < 500:
    cpu.step()
    steps3 += 1
assert cpu.pc == ssym["STAGE2_LOOP"]
name_row0 = bytes(cpu.vram[0x1800:0x1808])
print("VRAM name table row0:", name_row0)
assert name_row0 == b"STAGE 2 "

print()
print("FULL-GAME BANK-SWITCH INTEGRATION (build-time patch, tracked source untouched): ALL CHECKS PASSED")
