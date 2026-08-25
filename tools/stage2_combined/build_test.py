"""Assembles the combined terrain + tank test: the stage2_terrain
scroller (own INIT/MAINLOOP engine) with the tank sprite sitting on
top of it. Border-color diagnostic checkpoints through INIT (see the
README) since the tank-only test reportedly froze on real hardware
with no clue where.

Now a real ASCII16 MegaROM (bank0=page1/4000h-7FFFh, bank1=page2/
8000h-BFFFh, RAM-trampoline bank-select in INIT), not a flat 32KB
image - "フリーズはしてないがグリッチ ボーダーはブラックだな...
ASCII16の本番形式でやってみろ 64KBだからな": once content grew past
16KB, the flashcart being tested on evidently can't boot a plain
linear image at all (confirmed on real hardware: didn't even reach
INIT's own first instruction), the same real, production mechanism
`tools/bankswitch_poc/build_full_rom.py` already uses for the shipped
game. Since this file has no genuine second PHASE of content the way
the main game's stage1->stage2 transition does - just needs more than
16KB total for one continuous program - bank1 is selected exactly
once, at boot, and left selected permanently; unlike bankswitch_poc's
own multi-bank build, there's no later mid-game switch to test.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_tank"))

import terrain_gen  # noqa: E402
import tank_gen  # noqa: E402
import bullet_gen  # noqa: E402
import enemy_gen  # noqa: E402
import bigzum_gen  # noqa: E402
import flyer_gen  # noqa: E402
import etank_gen  # noqa: E402
import sasapi_gen  # noqa: E402
import sasapi_hand_gen  # noqa: E402
import horming_gen  # noqa: E402
import thunder_gen  # noqa: E402
import sbeam_gen  # noqa: E402
from mini_z80asm import Assembler  # noqa: E402


def assemble():
    body = open(os.path.join(HERE, "combined_test.asm")).read()
    tables = (terrain_gen.emit_asm_tables() + "\n" + tank_gen.emit_asm_tables()
              + "\n" + bullet_gen.emit_asm_tables() + "\n" + enemy_gen.emit_asm_tables()
              + "\n" + bigzum_gen.emit_asm_tables() + "\n" + flyer_gen.emit_asm_tables()
              + "\n" + etank_gen.emit_asm_tables() + "\n" + sasapi_gen.emit_asm_tables()
              + "\n" + sasapi_hand_gen.emit_asm_tables() + "\n" + horming_gen.emit_asm_tables()
              + "\n" + thunder_gen.emit_asm_tables() + "\n" + sbeam_gen.emit_asm_tables())
    text = body + "\n" + tables + "\n"
    asm = Assembler(text)
    out = asm.assemble()
    return out, asm.symtab, text


def build_banks(out):
    """Splits the flat address->byte dict from assemble() into bank0
    (page1, 4000h-7FFFh) and bank1 (page2, 8000h-BFFFh) - same 0xFF-
    padded-unused-space convention as bankswitch_poc's own
    assemble_to_bytes(). Raises if anything landed outside 4000h-
    BFFFh (the 32KB-per-bank-pair budget)."""
    bank0 = bytearray([0xFF] * 0x4000)
    bank1 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        if 0x4000 <= addr <= 0x7FFF:
            bank0[addr - 0x4000] = val
        elif 0x8000 <= addr <= 0xBFFF:
            bank1[addr - 0x8000] = val
        else:
            raise Exception(f"address {addr:04X}h outside 4000h-BFFFh (bank0+bank1 budget exceeded)")
    return bank0, bank1


class BankedMem:
    """ASCII16-style mapper emulation for testing in z80emu.py - a
    plain flat bytearray would let the trampoline's own write to
    6000h/7000h silently corrupt whatever live program byte happens to
    sit at that address (confirmed: 0x7000 held a real opcode byte in
    this file's own current layout), producing misleading results.
    Writes to `portA`(6000h)/`portB`(7000h) select which bank is
    currently visible at page1/page2; any other write within 4000h-
    BFFFh is silently ignored (real ROM, matches actual cartridge
    behavior); everything outside 4000h-BFFFh is flat, directly-
    writable RAM (also where the BIOS's own low-memory area lives,
    same as z80emu.py's own bios_call() stubs already assume). Same
    shape as bankswitch_poc's own BankedMem (run_poc.py/verify_full.py)
    - banksB index0 is an unused blank placeholder purely so "A=1
    selects index1" lines up with the real bank-select convention this
    file's own INIT actually uses.
    """
    def __init__(self, bank0, bank1, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = [bank0]
        self.banksB = [bytearray([0xFF] * 0x4000), bank1]
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
            return  # ROM: writes silently ignored
        self.flat[addr] = val


def main():
    out, sym, text = assemble()
    lo, hi = min(out), max(out)
    bank0, bank1 = build_banks(out)
    rom32 = bytes(bank0) + bytes(bank1)
    # doubled to 64KB - same real-hardware-required convention as
    # bankswitch_poc/build_rom.py (a real flashcart mirrored a 32KB
    # image instead of decoding real ASCII16 banks until doubled to a
    # "regulation" size for its own mapper auto-detection).
    rom = rom32 + rom32
    # "またお前は忘れてるがファイル名に[ASCII16]を含めろと過去に指示し
    # てる リセットはそのせいだった" - real-hardware testing was never
    # actually the method here; verification is via WebMSX, which
    # auto-detects the mapper type from the FILENAME (matching the real
    # shipped ROM's own "CYBER SHMUP [ASCII16].rom" convention - see
    # bankswitch_poc/build_full_rom.py), not from file content/size the
    # way this session had been assuming throughout the whole page2-
    # mapping investigation. Without the tag, WebMSX evidently fell
    # back to some other ROM-type guess for both the 32KB and 64KB
    # builds - explaining the instant reset on the 64KB file (wrong
    # type for that size) and, per direct confirmation, the SAME
    # glitch on both the pre- and post-ASCII16 versions (meaning the
    # bank-switch code was very likely never actually being exercised
    # at all before now - the glitch itself is apparently unrelated to
    # any of the page2/bank-switch work and still needs its own real
    # root cause once this file is finally loaded under its correct
    # mapper type for the first time).
    # "ここで貼るROMファイル名を Stage1はCyberS S1.ascii16k.rom Stage2は
    # CyberS S2.ascii16k.rom として出力" (round28) - renamed from
    # "combined_test [ASCII16].rom". Still contains "ascii16" as a
    # substring (just lowercase, no brackets, trailing "k") - per this
    # file's own comment history just above, WebMSX's mapper auto-
    # detection keys off the filename itself, not ROM content/size, so
    # this rename needs the same real-hardware/WebMSX confirmation any
    # filename change here always has before trusting it.
    rom_path = os.path.join(HERE, "CyberS S2.ascii16k.rom")
    with open(rom_path, "wb") as f:
        f.write(rom)
    print(f"assembled {lo:04X}h-{hi:04X}h ({hi-lo+1} bytes across bank0+bank1), wrote {rom_path}: {len(rom)} bytes (doubled)")
    print("INIT =", hex(sym["INIT"]), "MAINLOOP =", hex(sym["MAINLOOP"]))
    return out, sym, text


if __name__ == "__main__":
    main()
