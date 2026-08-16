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
    ; --- DIAGNOSTIC checkpoint: border color 2 = "slot hack done". ---
    LD B,2 : LD C,7 : CALL WRTVDP

    ; --- copy the bank-switch trampoline into RAM (0xF200, a       ---
    ; --- confirmed-free gap between ENEMY6_STEP_TIMER (0F1D8h) and ---
    ; --- STACKTOP (0F380h)) so any future switch executes from RAM ---
    ; --- - immune to whatever's currently mapped in either ROM      ---
    ; --- window, unlike executing the switch from ROM directly.     ---
    LD HL,BANKSWITCH_TRAMPOLINE_SRC
    LD DE,0F200h
    LD BC,BANKSWITCH_TRAMPOLINE_LEN
    LDIR

    ; --- DIAGNOSTIC checkpoint: border color 3 = "trampoline copied". ---
    LD B,3 : LD C,7 : CALL WRTVDP

    ; --- explicit ASCII16 bank select: bank 1 for window B        ---
    ; --- (8000h-BFFFh), matching the page2 content this game has  ---
    ; --- always had. Explicit rather than relying on the mapper's ---
    ; --- power-on default, which isn't guaranteed the same across ---
    ; --- every flashcart. The trampoline never returns via RET (it ---
    ; --- just jumps to HL), so this sets HL to "come back here"   ---
    ; --- and JPs to it, rather than CALLing it.                    ---
    LD A,1
    LD HL,INIT_RESUME_AFTER_BANK_SELECT
    JP 0F200h
INIT_RESUME_AFTER_BANK_SELECT:
    ; --- DIAGNOSTIC checkpoint: border color 4 = "bank1 select via  ---
    ; --- RAM trampoline returned successfully".                     ---
    LD B,4 : LD C,7 : CALL WRTVDP

    ; --- interrupts stay off for all of INIT's raw VDP/PSG port I/O; ---"""

MAINLOOP_ANCHOR = """MAINLOOP:
    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---"""

MAINLOOP_PATCH = """MAINLOOP:
    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- TEMPORARY: once PLAYER_FLYAWAY reaches 2 (boss fully       ---
    ; --- destroyed AND the player's exit/flyaway sequence has       ---
    ; --- finished - off-screen/hidden, per PLAYER_FLYAWAY's own     ---
    ; --- 0=normal/1=auto-flying/2=off-screen states), simulate       ---
    ; --- "stage 1 end" and switch to the stage-2 placeholder bank    ---
    ; --- (bank2). This is the actual real transition point stage 2  ---
    ; --- will eventually use - NOT an arbitrary tick count. At this  ---
    ; --- point the boss, its explosion sequence, and every enemy/    ---
    ; --- bullet are already long gone (BOSS_CLEAR_DYNAMIC_ENEMIES ran ---
    ; --- when the boss landed, and BOSS_EXPL_UPDATE's completion is  ---
    ; --- what kicks off the flyaway in the first place), so nothing  ---
    ; --- is left mid-animation in window B for the switch to cut off. ---
    ; --- Goes through the RAM trampoline copied in during INIT       ---
    ; --- (see BANKSWITCH_TRAMPOLINE_SRC) rather than switching and   ---
    ; --- jumping directly from ROM - both a real flashcart and       ---
    ; --- BlueMSX froze on the direct-from-ROM version.                ---
    LD A,(PLAYER_FLYAWAY)
    CP 2
    JR NZ,MAINLOOP_NO_TEST_SWITCH
    LD A,2
    LD HL,0BF00h
    JP 0F200h
MAINLOOP_NO_TEST_SWITCH:

    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---"""

TRAMPOLINE_ANCHOR = "INIT:\n    LD SP,STACKTOP"

TRAMPOLINE_PATCH = """INIT:
    LD SP,STACKTOP

    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- DIAGNOSTIC checkpoint: border color 1 = "INIT started,     ---
    ; --- SP set". If the screen never shows even this color, real   ---
    ; --- hardware is failing before/at cartridge boot itself, not   ---
    ; --- anywhere in this patch.                                    ---
    LD B,1 : LD C,7 : CALL WRTVDP

    ; --- source for the RAM-resident bank-switch trampoline, copied ---
    ; --- to 0xF200 below. Call/jump to it with A=bank number for   ---
    ; --- window B (8000h-BFFFh), HL=address to jump to afterward.  ---
    ; --- Executing the actual "LD (7000h),A" from RAM instead of   ---
    ; --- ROM means it can never itself be affected by the very     ---
    ; --- bank switch it's performing, regardless of which ROM      ---
    ; --- window issued the call.                                    ---
    JP BANKSWITCH_TRAMPOLINE_END
BANKSWITCH_TRAMPOLINE_SRC:
    LD (7000h),A
    JP (HL)
BANKSWITCH_TRAMPOLINE_LEN EQU $ - BANKSWITCH_TRAMPOLINE_SRC
BANKSWITCH_TRAMPOLINE_END:"""


def patch_trampoline_src(text):
    assert text.count(TRAMPOLINE_ANCHOR) == 1, "INIT: opening not found (or not unique) - source drifted"
    return text.replace(TRAMPOLINE_ANCHOR, TRAMPOLINE_PATCH, 1)


POSTINIT32_ANCHOR = """    CALL INIT32

    ; --- border/backdrop color"""

POSTINIT32_PATCH = """    CALL INIT32

    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- DIAGNOSTIC checkpoint: border color 6 = "INIT32 (BIOS      ---
    ; --- SCREEN1 setup) returned successfully". Gets immediately    ---
    ; --- overwritten by the game's own border color=1 write right   ---
    ; --- below - only visible if execution froze exactly here.      ---
    LD B,6 : LD C,7 : CALL WRTVDP

    ; --- border/backdrop color"""


def patch_postinit32(text):
    assert text.count(POSTINIT32_ANCHOR) == 1, "post-INIT32 anchor not found (or not unique) - source drifted"
    return text.replace(POSTINIT32_ANCHOR, POSTINIT32_PATCH, 1)


def patched_game_text():
    src_path = os.path.join(REPO, "src", "CYBER_GD_BOSS.asm")
    text = open(src_path, encoding="utf-8").read()
    assert text.count(INIT_ANCHOR) == 1, "INIT anchor not found (or not unique) - source drifted"
    assert text.count(MAINLOOP_ANCHOR) == 1, "MAINLOOP anchor not found (or not unique) - source drifted"
    text = patch_trampoline_src(text)
    text = patch_postinit32(text)
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
