"""Builds a real 64KB ASCII16 ROM embedding the actual game, for a
real-hardware test of the bank-switch mechanism.

IMPORTANT: src/CYBER_GD_BOSS.asm itself is NOT modified. The normal
game only ever runs as a flat 32KB ROM (no mapper) - if a bank-switch
test trigger were baked into the tracked source, the ordinary
single-bank rom/CYBER_GD_BOSS1.rom build would inherit it too, and
outside a real ASCII16 mapper "LD (7000h),A : JP 0BF00h" just jumps
into whatever garbage happens to be at 0BF00h once GAME_TICK reaches
100 - a real regression in the normal game. So the two small
insertions below (explicit "select bank1 for window B" in INIT, and
the GAME_TICK>=100 test-switch trigger at the top of MAINLOOP) are
applied to an in-memory copy of the source text, only for this test
build.

Layout:
  bank0 (file 0x0000-0x3FFF) = the real game's page1 content
      (4000h-7FFFh) + the two patched-in test insertions above.
  bank1 (file 0x4000-0x7FFF) = the real game's page2 content
      (8000h-BFFFh), byte-for-byte what it has always been - normal
      stage-1 gameplay is completely unchanged.
  bank2 (file 0x8000-0xBFFF) = the bankswitch_poc stage-2 placeholder
      (bank_b1.asm) - draws "STAGE 2" and loops a visible counter,
      entry point near the end of the window (0BF00h).
  bank3 (file 0xC000-0xFFFF) = blank (0xFF-filled) - future headroom.
"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(HERE, ".."))
from mini_z80asm import Assembler

INIT_ANCHOR = """    OUT (0A8h),A

    ; --- interrupts stay off for all of INIT's raw VDP/PSG port I/O; ---"""

INIT_PATCH = """    OUT (0A8h),A

    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- explicit ASCII16 bank select: bank 1 for window B        ---
    ; --- (8000h-BFFFh), matching the page2 content this game has  ---
    ; --- always had. Explicit rather than relying on the mapper's ---
    ; --- power-on default, which isn't guaranteed the same across ---
    ; --- every flashcart.                                          ---
    LD A,1
    LD (7000h),A

    ; --- interrupts stay off for all of INIT's raw VDP/PSG port I/O; ---"""

MAINLOOP_ANCHOR = """MAINLOOP:
    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---"""

MAINLOOP_PATCH = """MAINLOOP:
    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- TEMPORARY: once GAME_TICK reaches 100 (~13s in), simulate ---
    ; --- "stage 1 end" and switch to the stage-2 placeholder bank  ---
    ; --- (bank2). Safe here because MAINLOOP always starts at a    ---
    ; --- window-A address and every frame re-enters via            ---
    ; --- "JP MAINLOOP", so this switch (which only touches window  ---
    ; --- B) never risks changing out its own currently-executing   ---
    ; --- bank.                                                      ---
    LD HL,(GAME_TICK)
    LD DE,100
    OR A
    SBC HL,DE
    JR C,MAINLOOP_NO_TEST_SWITCH
    LD A,2
    LD (7000h),A
    JP 0BF00h
MAINLOOP_NO_TEST_SWITCH:

    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---"""


def patched_game_text():
    src_path = os.path.join(REPO, "src", "CYBER_GD_BOSS.asm")
    text = open(src_path, encoding="utf-8").read()
    assert text.count(INIT_ANCHOR) == 1, "INIT anchor not found (or not unique) - source drifted"
    assert text.count(MAINLOOP_ANCHOR) == 1, "MAINLOOP anchor not found (or not unique) - source drifted"
    text = text.replace(INIT_ANCHOR, INIT_PATCH, 1)
    text = text.replace(MAINLOOP_ANCHOR, MAINLOOP_PATCH, 1)
    return text


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
            raise Exception(f"game byte at unexpected address {addr:04x}")
    return bank0, bank1, a.symtab


def assemble_placeholder():
    text = open(os.path.join(HERE, "bank_b1.asm"), encoding="utf-8").read()
    a = Assembler(text)
    out = a.assemble()
    bank2 = bytearray([0xFF] * 0x4000)
    for addr, val in out.items():
        assert 0x8000 <= addr <= 0xBFFF, f"{addr:04x} outside 8000-BFFF"
        bank2[addr - 0x8000] = val
    return bank2, a.symtab


def main():
    bank0, bank1, game_sym = assemble_game()
    bank2, stage2_sym = assemble_placeholder()
    bank3 = bytearray([0xFF] * 0x4000)

    rom = bytes(bank0) + bytes(bank1) + bytes(bank2) + bytes(bank3)
    out_path = os.path.join(HERE, "CYBER_SUZUKA_ASCII16_TEST.rom")
    with open(out_path, "wb") as f:
        f.write(rom)

    print(f"wrote {out_path}: {len(rom)} bytes")
    print(f"  bank0 (page1, real game + test patch): {len(bank0)}B, header {bytes(bank0[0:4]).hex()}")
    print(f"  bank1 (page2, real game, unpatched): {len(bank1)}B")
    print(f"  bank2 (stage2 placeholder): {len(bank2)}B, entry @ {stage2_sym['STAGE2_ENTRY']:04x}")
    print(f"  bank3 (blank/future headroom): {len(bank3)}B")
    print(f"game MAINLOOP={game_sym['MAINLOOP']:04x} GAME_TICK={game_sym['GAME_TICK']:04x}")


if __name__ == "__main__":
    main()
