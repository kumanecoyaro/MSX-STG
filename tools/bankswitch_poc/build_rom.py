import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from mini_z80asm import Assembler


def assemble_to_bytes(path, base, size):
    text = open(path, encoding="utf-8").read()
    a = Assembler(text)
    out = a.assemble()
    buf = bytearray([0xFF] * size)
    for addr, val in out.items():
        assert base <= addr < base + size, f"{addr:04x} outside {base:04x}-{base+size-1:04x}"
        buf[addr - base] = val
    return buf


def main():
    bank0 = assemble_to_bytes(os.path.join(HERE, "bank_a.asm"), 0x4000, 0x4000)
    bank1 = assemble_to_bytes(os.path.join(HERE, "bank_b1.asm"), 0x8000, 0x4000)
    rom32 = bytes(bank0) + bytes(bank1)
    # doubled to 64KB - see the matching comment in build_full_rom.py's
    # main(): a real flashcart mirrored a 64KB image instead of
    # decoding real banks until doubled to a "regulation" size.
    rom = rom32 + rom32
    out_path = os.path.join(HERE, "BANKSWITCH_POC.rom")
    with open(out_path, "wb") as f:
        f.write(rom)
    print(f"wrote {out_path}: {len(rom)} bytes (bank0 {len(bank0)}B + bank1 {len(bank1)}B, doubled)")
    print("header:", rom[0:4].hex())


if __name__ == "__main__":
    main()
