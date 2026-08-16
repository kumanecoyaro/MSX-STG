"""Builds a real 64KB(x2=128KB) ASCII16 ROM embedding the actual game
as stage 1 AND a full "stage 2 world" (see build_stage2_world.py) as
stage 2, for a real-hardware test of the bank-switch mechanism against
genuine, fully-playable content on both sides - not a static
placeholder screen.

This is now the primary/shipped build (the old flat 32KB single-bank
ROM is retired - the game is ASCII16/64KB-based going forward).

src/CYBER SHMUP.asm itself is still NOT modified by this script: the
ASCII16-specific plumbing (RAM trampoline setup, the PLAYER_FLYAWAY==2
switch trigger, the PSG mute) is applied to an in-memory copy of the
source text at build time instead of being baked into the tracked
source. This keeps the trampoline/switch mechanics all in one place
here rather than scattered through the main source, and keeps the
tracked .asm assemblable on its own (e.g. by tools/mini_z80asm.py
directly) for debugging without ASCII16 entanglement.

Layout (before the real-hardware-required 128KB doubling - see main()):
  bank0 (file 0x0000-0x3FFF) = the real game's page1 content
      (4000h-7FFFh) + the test insertions below (RAM trampoline setup,
      diagnostic checkpoints, the PLAYER_FLYAWAY==2 switch trigger).
  bank1 (file 0x4000-0x7FFF) = the real game's page2 content
      (8000h-BFFFh), byte-for-byte what it has always been - normal
      stage-1 gameplay is completely unchanged.
  bank2 (file 0x8000-0xBFFF) = stage2 world's page1 content (its own
      INIT/MAINLOOP - same structure as bank0, simple-only enemies).
  bank3 (file 0xC000-0xFFFF) = stage2 world's page2 content.
"""
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from build_stage2_world import assemble_stage2_world

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
    LD DE,7000h
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
    ; --- finished - off-screen/hidden), switch to the full stage2   ---
    ; --- world (see build_stage2_world.py - an exact port of stage  ---
    ; --- 1's own engine/graphics, just with a simple-only enemy      ---
    ; --- roster and a permanent "STAGE2" HUD label) via a real       ---
    ; --- re-init, not a static placeholder screen. This is the       ---
    ; --- actual real transition point stage 2 will eventually use.  ---
    ; --- Safe here because MAINLOOP always starts at a window-A      ---
    ; --- address and every frame re-enters via "JP MAINLOOP".        ---
    LD A,(PLAYER_FLYAWAY)
    CP 2
    JR NZ,MAINLOOP_NO_TEST_SWITCH

    ; --- DIAGNOSTIC checkpoint: border color 7 = "about to switch". ---
    LD B,7 : LD C,7 : CALL WRTVDP

    ; --- mute all 3 PSG channels before switching away - real-hw     ---
    ; --- finding: the player flyaway sequence's sustained "engine    ---
    ; --- goooo" noise (channel A, re-armed every frame while moving, ---
    ; --- decays naturally only once fully hidden) was still mid-     ---
    ; --- volume the instant PLAYER_FLYAWAY hit 2 - since MAINLOOP     ---
    ; --- (and the SOUND_UPDATE decay it drives) never runs again      ---
    ; --- after the switch, it was never given the chance to fade,    ---
    ; --- leaving it stuck on indefinitely.                            ---
    LD A,8 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A

    ; --- hop 1 (through the RAM trampoline, so this is safe          ---
    ; --- regardless of which window issues it): switch window B      ---
    ; --- (8000h-BFFFh) to bank3 (stage2 world's page2), then return   ---
    ; --- to MAINLOOP_HOP2 - still window A, still bank0/stage1,       ---
    ; --- completely unaffected by the window-B switch.                ---
    LD A,3
    LD DE,7000h
    LD HL,MAINLOOP_HOP2
    JP 0F200h
MAINLOOP_HOP2:
    ; --- hop 2: switch window A (4000h-7FFFh) to bank2 (stage2       ---
    ; --- world's page1) and jump straight to its own INIT (0x4010 -  ---
    ; --- same relative address as this game's own INIT, since it's   ---
    ; --- the identical ORG/layout). This is what makes it "just       ---
    ; --- initialization" rather than a bespoke patchwork of screen-   ---
    ; --- clear/color-table/sprite-hide fixes: stage2 world's INIT     ---
    ; --- does the exact same full boot sequence stage 1's own INIT    ---
    ; --- already does (BIOS SCREEN1 setup, pattern/color/digit loads, ---
    ; --- RAM/sprite/schedule reset), which naturally clears and       ---
    ; --- redraws everything from scratch.                             ---
    LD A,2
    LD DE,6000h
    LD HL,04010h
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
    ; --- to 0xF200 below. Call/jump to it with A=bank number,       ---
    ; --- DE=the mapper's memory-mapped select address to write it   ---
    ; --- to (6000h for window A/page1, 7000h for window B/page2),   ---
    ; --- HL=address to jump to afterward. Executing the actual      ---
    ; --- "LD (DE),A" from RAM instead of ROM means it can never     ---
    ; --- itself be affected by the very bank switch it's performing, ---
    ; --- regardless of which ROM window issued the call OR which    ---
    ; --- window is being switched (needed once stage2 world - its   ---
    ; --- own full bank pair, not a single placeholder bank - has to  ---
    ; --- switch window A too, not just window B).                    ---
    JP BANKSWITCH_TRAMPOLINE_END
BANKSWITCH_TRAMPOLINE_SRC:
    LD (DE),A
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
    src_path = os.path.join(REPO, "src", "CYBER SHMUP.asm")
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


def main():
    bank0, bank1, game_sym = assemble_game()
    bank2, bank3, stage2_sym, n_schedule = assemble_stage2_world()

    rom64 = bytes(bank0) + bytes(bank1) + bytes(bank2) + bytes(bank3)
    # --- Real-hardware finding: this specific flashcart mirrors a    ---
    # --- 64KB ASCII16 image instead of decoding it as 4 real banks   ---
    # --- unless the file is a "regulation" size for its mapper       ---
    # --- detection - doubling it to 128KB (banks 0-3 again at        ---
    # --- 4-7, i.e. the whole 64KB image simply repeated once) fixed  ---
    # --- a real-hardware boot freeze that the emulator never showed. ---
    # --- Only banks 0-3 (the first half) are ever actually selected  ---
    # --- by this ROM's own code, so the duplicate second half is     ---
    # --- inert padding, not a second, different level.               ---
    rom = rom64 + rom64
    out_path = os.path.join(REPO, "rom", "CYBER SHMUP [ASCII16].rom")
    with open(out_path, "wb") as f:
        f.write(rom)

    print(f"wrote {out_path}: {len(rom)} bytes (banks 0-3 real content, doubled to 128KB - see comment)")
    print(f"  bank0 (page1, real game + test patch): {len(bank0)}B, header {bytes(bank0[0:4]).hex()}")
    print(f"  bank1 (page2, real game, unpatched): {len(bank1)}B")
    print(f"  bank2 (stage2 world page1): {len(bank2)}B, header {bytes(bank2[0:4]).hex()}")
    print(f"  bank3 (stage2 world page2): {len(bank3)}B")
    print(f"game MAINLOOP={game_sym['MAINLOOP']:04x} GAME_TICK={game_sym['GAME_TICK']:04x}")
    print(f"stage2 world INIT={stage2_sym['INIT']:04x} MAINLOOP={stage2_sym['MAINLOOP']:04x} schedule entries={n_schedule}")


if __name__ == "__main__":
    main()
