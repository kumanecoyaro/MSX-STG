"""Builds a real 64KB(x2=128KB) ASCII16 ROM embedding the actual game
as stage 1 AND the REAL stage 2 (tools/stage2_combined/combined_test.asm
- terrain scroller, tank, full enemy roster, the Sasapi boss battle) as
stage 2 - the "Comb" build ("では一度Stage1に実Stage2をマージしてみる...
実Stage2に差し替えてみてくれ": bankswitch_poc's own throwaway simple-
enemies-only placeholder stage2 world, see build_stage2_world.py, is
retired from this script in favor of the real thing).

This is now the primary/shipped build (the old flat 32KB single-bank
ROM is retired - the game is ASCII16/64KB-based going forward).

src/CYBER SHMUP.asm itself is still NOT modified by this script: the
ASCII16-specific plumbing (RAM trampoline setup, the PLAYER_FLYAWAY==2
switch trigger, the PSG mute) is applied to an in-memory copy of the
source text at build time instead of being baked into the tracked
source. This keeps the trampoline/switch mechanics all in one place
here rather than scattered through the main source, and keeps the
tracked .asm assemblable on its own (e.g. by tools/mini_z80asm.py
directly) for debugging without ASCII16 entanglement. Same treatment
for tools/stage2_combined/combined_test.asm below (see
assemble_real_stage2()) - it stays independently assemblable/testable
via its own tools/stage2_combined/build_test.py and 629-test regression
suite, unmodified; only an in-memory copy gets retargeted for embedding
here.

Layout (before the real-hardware-required 128KB doubling - see main()):
  bank0 (file 0x0000-0x3FFF) = the real game's page1 content
      (4000h-7FFFh) + the test insertions below (RAM trampoline setup,
      diagnostic checkpoints, the PLAYER_FLYAWAY==2 switch trigger).
  bank1 (file 0x4000-0x7FFF) = the real game's page2 content
      (8000h-BFFFh), byte-for-byte what it has always been - normal
      stage-1 gameplay is completely unchanged.
  bank2 (file 0x8000-0xBFFF) = the real stage2's page1 content (its own
      INIT/MAINLOOP - same structure as bank0).
  bank3 (file 0xC000-0xFFFF) = the real stage2's page2 content.
"""
import importlib.util
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_tank"))
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
from mini_z80asm import Assembler
import bgm_bank_gen

# tools/stage2_terrain, tools/stage2_tank AND tools/stage2_combined each have
# their own unrelated "build_test.py" - a plain `import build_test` would
# resolve to whichever one's directory happens to sort first on sys.path
# rather than the one meant here, so load tools/stage2_combined's copy by
# its exact file path instead of relying on module-name search order.
_stage2_build_spec = importlib.util.spec_from_file_location(
    "stage2_combined_build_test",
    os.path.join(REPO, "tools", "stage2_combined", "build_test.py"))
stage2_build = importlib.util.module_from_spec(_stage2_build_spec)
_stage2_build_spec.loader.exec_module(stage2_build)

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

    ; --- explicit ASCII16 bank select: bank 3 for window B (8000h-  ---
    ; --- BFFFh), matching this game's own page2 content at its      ---
    ; --- round39 GLOBAL bank index (was bank1 pre-round39, before a  ---
    ; --- 3rd bank pair - the title screen, bank0/1 - was inserted    ---
    ; --- ahead of this game's own pair, shifting it from 0/1 to      ---
    ; --- 2/3). Explicit rather than relying on the mapper's power-on ---
    ; --- default, which isn't guaranteed the same across every       ---
    ; --- flashcart. The trampoline never returns via RET (it just    ---
    ; --- jumps to HL), so this sets HL to "come back here" and JPs   ---
    ; --- to it, rather than CALLing it.                              ---
    LD A,3
    LD DE,7000h
    LD HL,INIT_RESUME_AFTER_BANK_SELECT
    JP 0F200h
INIT_RESUME_AFTER_BANK_SELECT:
    ; --- DIAGNOSTIC checkpoint: border color 4 = "bank3 select via  ---
    ; --- RAM trampoline returned successfully".                     ---
    LD B,4 : LD C,7 : CALL WRTVDP

    ; --- interrupts stay off for all of INIT's raw VDP/PSG port I/O; ---"""

MAINLOOP_ANCHOR = """MAINLOOP:
    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---"""

MAINLOOP_PATCH = """MAINLOOP:
    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- Once PLAYER_FLYAWAY reaches 2 (boss fully destroyed AND     ---
    ; --- the player's exit/flyaway sequence has finished - off-      ---
    ; --- screen/hidden), switch to the real stage2 (see              ---
    ; --- tools/stage2_combined/combined_test.asm, assembled here via ---
    ; --- assemble_real_stage2() as GLOBAL bank4/bank5 - round39 added ---
    ; --- a 3rd bank pair (title screen, bank0/1) ahead of this game's ---
    ; --- own bank2/3, shifting stage2 from 2/3 to 4/5, see main()'s   ---
    ; --- own layout comment) via a real re-init, not a static         ---
    ; --- placeholder screen. Safe here because MAINLOOP always starts ---
    ; --- at a window-A address and every frame re-enters via          ---
    ; --- "JP MAINLOOP".                                                ---
    LD A,(PLAYER_FLYAWAY)
    CP 2
    JR NZ,MAINLOOP_NO_TEST_SWITCH

    ; --- 実機フィードバック対応("バンク切り替えに失敗してる タイトルで  ---
    ; --- ボタンを押すとフリーズ", title_test.asm's own WAIT_FOR_START     ---
    ; --- fix has the full rationale): same class of race exists here -    ---
    ; --- interrupts stay enabled (BGM_TICK armed via H.TIMI) all the way   ---
    ; --- through hop1/hop2 and however many instructions run before        ---
    ; --- Stage2's own INIT gets to its own early DI, during which the      ---
    ; --- stale hook (this file's own BGM_TICK address) could fire over     ---
    ; --- whatever bytes now occupy window A (Stage2's code, not this       ---
    ; --- file's). DI here on the sending side closes the whole gap         ---
    ; --- regardless of how much runs on the receiving side before its      ---
    ; --- own DI.                                                            ---
    DI

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
    ; --- (8000h-BFFFh) to bank5 (stage2 world's page2, GLOBAL index   ---
    ; --- - see round39's own 3-pair layout comment in main()), then   ---
    ; --- return to MAINLOOP_HOP2 - still window A, still bank2/stage1, ---
    ; --- completely unaffected by the window-B switch.                ---
    LD A,5
    LD DE,7000h
    LD HL,MAINLOOP_HOP2
    JP 0F200h
MAINLOOP_HOP2:
    ; --- hop 2: switch window A (4000h-7FFFh) to bank4 (stage2       ---
    ; --- world's page1, GLOBAL index) and jump straight to its own    ---
    ; --- INIT (0x4010 - same relative address as this game's own      ---
    ; --- INIT, since it's the identical ORG/layout). This is what     ---
    ; --- makes it "just initialization" rather than a bespoke         ---
    ; --- patchwork of screen-clear/color-table/sprite-hide fixes:     ---
    ; --- stage2 world's INIT does the exact same full boot sequence   ---
    ; --- stage 1's own INIT already does (BIOS SCREEN1 setup,         ---
    ; --- pattern/color/digit loads, RAM/sprite/schedule reset),       ---
    ; --- which naturally clears and redraws everything from scratch.  ---
    LD A,4
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
"""

POSTINIT32_PATCH = """    CALL INIT32

    ; --- [bankswitch_poc TEST PATCH, not in the tracked source] ---
    ; --- DIAGNOSTIC checkpoint: border color 6 = "INIT32 (BIOS      ---
    ; --- SCREEN1 setup) returned successfully". Gets immediately    ---
    ; --- overwritten by the game's own border color=1 write right   ---
    ; --- below - only visible if execution froze exactly here.      ---
    LD B,6 : LD C,7 : CALL WRTVDP
"""


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


# combined_test.asm assembles standalone (tools/stage2_combined/build_test.py)
# as a self-contained 2-bank ASCII16 ROM: bank0=window A(page1)/bank1=window
# B(page2) IN ITS OWN NUMBERING, so its own INIT hardcodes "select bank 1 for
# window B" as part of its own one-time boot bank-select (see combined_test.asm
# around BANKSWITCH_TRAMPOLINE_RAM). Embedded here, that content instead
# occupies GLOBAL bank indices 4 (window A) and 5 (window B) - round39 added a
# 3rd bank pair (title screen) ahead of this game's own pair, so stage2 shifted
# from 2/3 to 4/5 (see main()'s own layout comment) - by the time this file's
# own INIT runs, MAINLOOP_PATCH's own HOP1/HOP2 have already selected window
# A=bank4/window B=bank5 to get here at all, so if this file's own INIT went
# on to redundantly select "its own bank 1" for window B, that would overwrite
# the correct selection with STAGE 1's page2 content instead (global bank
# index 3) - silently breaking stage2 right at its own boot. Retargeted to
# bank index 5 on an in-memory copy only, same as build_full_rom.py's own
# game-source patching above; combined_test.asm itself, and its own
# standalone build/tests, are untouched.
STAGE2_BANKSELECT_ANCHOR = """    LD A,1
    LD DE,7000h
    LD HL,INIT_RESUME_AFTER_BANK_SELECT
    JP BANKSWITCH_TRAMPOLINE_RAM"""

STAGE2_BANKSELECT_PATCH = """    LD A,5
    LD DE,7000h
    LD HL,INIT_RESUME_AFTER_BANK_SELECT
    JP BANKSWITCH_TRAMPOLINE_RAM"""

# round40 ("ではBGMを実装する...タイトル含めて各ステージにドライバを配置し
# RAMにコピーしてステージスタート"): combined_test.asm's own INIT_BGM
# selects the standalone bgm-data bank (index2 in ITS OWN 3-bank
# numbering: own bank0/1 + bgm-data bank2) then restores window B to its
# own bank1 (standalone) - both literals need the same GLOBAL-bank-index
# retargeting STAGE2_BANKSELECT_PATCH above already does for the OTHER
# (cross-stage trampoline) bank-select in this file: bgm-data bank2 ->
# GLOBAL bank6 (the new dedicated bank main() below builds from
# tools/bgm_data/bgm_bank_gen.py, replacing the old inert 0xFF filler),
# own bank1 -> GLOBAL bank5 (same as STAGE2_BANKSELECT_PATCH's own target -
# combined_test.asm's own INIT_BGM runs AFTER the real page2 content is
# already selected as bank1/GLOBAL5, so restoring to "1" would silently
# undo that and repoint page2 at STAGE1's own content instead).
STAGE2_BGM_BANKSELECT_ANCHOR = """    LD A,2                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C200h : LD BC,046h : LDIR   ; 周期テーブル(35note*2)
    LD HL,0866Eh : LD DE,0C246h : LD BC,0792h : LDIR  ; DEFEAT chB+chC
    LD A,1                       ; standalone own bank1(Combでは5へパッチ)
    LD (7000h),A"""

STAGE2_BGM_BANKSELECT_PATCH = """    LD A,6                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C200h : LD BC,046h : LDIR   ; 周期テーブル(35note*2)
    LD HL,0866Eh : LD DE,0C246h : LD BC,0792h : LDIR  ; DEFEAT chB+chC
    LD A,5                       ; standalone own bank1(Combでは5へパッチ)
    LD (7000h),A"""


def assemble_real_stage2():
    text = stage2_build.combined_text()
    assert text.count(STAGE2_BANKSELECT_ANCHOR) == 1, \
        "stage2 bank-select anchor not found (or not unique) - combined_test.asm drifted"
    text = text.replace(STAGE2_BANKSELECT_ANCHOR, STAGE2_BANKSELECT_PATCH, 1)
    assert text.count(STAGE2_BGM_BANKSELECT_ANCHOR) == 1, \
        "stage2 BGM bank-select anchor not found (or not unique) - combined_test.asm drifted"
    text = text.replace(STAGE2_BGM_BANKSELECT_ANCHOR, STAGE2_BGM_BANKSELECT_PATCH, 1)
    a = Assembler(text)
    out = a.assemble()
    bank4, bank5 = stage2_build.build_banks(out)
    return bank4, bank5, a.symtab


# round39 ("ではバンクテストをしたいので...新バンクには必要な初期化処理を
# 実装した上で PUSH STARTと表示しStage1とStage2のボスを適当に表示して
# ボタンが押されたらStage1へトランポリンするように"): a genuinely new 3rd
# bank pair, tools/title_screen/title_test.asm - self-contained/independently
# assemblable/testable, same treatment as combined_test.asm above. Its own
# INIT hardcodes "select bank2/window A, bank3/window B, jump to 0x4010" for
# the button-press trampoline into Stage1 (see title_test.asm's own
# STAGE1_BANK_A/STAGE1_BANK_B/STAGE1_INIT) - no in-memory patching needed
# here, unlike Stage1/Stage2 above, since this file was written knowing its
# own global bank numbers from the start.
_title_build_spec = importlib.util.spec_from_file_location(
    "title_screen_build_test",
    os.path.join(REPO, "tools", "title_screen", "build_test.py"))
title_build = importlib.util.module_from_spec(_title_build_spec)
_title_build_spec.loader.exec_module(title_build)


# round40: title_test.asm's own INIT_BGM selects the standalone bgm-data
# bank (index2) then restores window B to its own bank1 - title's OWN
# bank1 stays GLOBAL bank1 in the Comb build too (round39 put title at
# bank0/1 unconditionally), so only the bgm-data bank literal needs
# retargeting to GLOBAL bank6, same as Stage2's own analogous patch above.
TITLE_BGM_BANKSELECT_ANCHOR = """    LD A,2                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C000h : LD BC,046h : LDIR   ; 周期テーブル(35note*2)
    LD HL,08046h : LD DE,0C046h : LD BC,0628h : LDIR  ; ALONE_FIGHTER chB+chC
    LD A,1                       ; このファイル自身のbank1(Comb/standaloneとも1のまま)
    LD (7000h),A"""

TITLE_BGM_BANKSELECT_PATCH = """    LD A,6                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C000h : LD BC,046h : LDIR   ; 周期テーブル(35note*2)
    LD HL,08046h : LD DE,0C046h : LD BC,0628h : LDIR  ; ALONE_FIGHTER chB+chC
    LD A,1                       ; このファイル自身のbank1(Comb/standaloneとも1のまま)
    LD (7000h),A"""


def assemble_title():
    text = title_build.combined_text()
    assert text.count(TITLE_BGM_BANKSELECT_ANCHOR) == 1, \
        "title BGM bank-select anchor not found (or not unique) - title_test.asm drifted"
    text = text.replace(TITLE_BGM_BANKSELECT_ANCHOR, TITLE_BGM_BANKSELECT_PATCH, 1)
    a = Assembler(text)
    out = a.assemble()
    bank0, bank1 = title_build.build_banks(out)
    return bank0, bank1, a.symtab


def main():
    title_bank0, title_bank1, title_sym = assemble_title()
    game_bank0, game_bank1, game_sym = assemble_game()
    bank4, bank5, stage2_sym = assemble_real_stage2()

    # --- round39 layout: title(0,1) -> Stage1(2,3) -> Stage2(4,5). The   ---
    # --- ASCII16 mapper always boots window A into bank0/window B into  ---
    # --- bank1 by hardware convention (confirmed by this project's own  ---
    # --- real-hardware testing - see combined_test.asm's own comment on ---
    # --- window B's power-on default), so whichever content needs to    ---
    # --- run FIRST must physically occupy bank0/1 - hence title moving  ---
    # --- there and Stage1/Stage2 both shifting up by 2 banks each.      ---
    rom96 = (bytes(title_bank0) + bytes(title_bank1)
             + bytes(game_bank0) + bytes(game_bank1)
             + bytes(bank4) + bytes(bank5))
    # --- Real-hardware finding (pre-round39): this specific flashcart   ---
    # --- mirrors a 64KB ASCII16 image instead of decoding it as 4 real  ---
    # --- banks unless the file is a "regulation" size for its mapper    ---
    # --- detection - doubling the old 4-bank/64KB image to 128KB fixed  ---
    # --- a real-hardware boot freeze the emulator never showed. Adding  ---
    # --- a 3rd pair makes the raw content 96KB (6 banks), not a         ---
    # --- previously-confirmed size on its own - rather than doubling to ---
    # --- an UNTESTED 192KB, this pads with 2 banks6/7 to reach exactly  ---
    # --- the same 128KB total already confirmed to work, the more       ---
    # --- conservative choice given genuine real-hardware uncertainty    ---
    # --- here - not yet verified on real hardware, flag any boot issue  ---
    # --- immediately if this assumption turns out wrong.                ---
    # --- round40: bank6, previously pure 0xFF filler, is now the real   ---
    # --- BGM data bank (tools/bgm_data/bgm_bank_gen.py - period table + ---
    # --- both songs' 2-channel row data, ~3.5KB used of 16KB) that      ---
    # --- title/Stage2's own INIT_BGM select via windowB (7000h, index6  ---
    # --- after the STAGE2_BGM_BANKSELECT_PATCH/TITLE_BGM_BANKSELECT_    ---
    # --- PATCH retargeting above) before LDIRing their song into RAM.   ---
    # --- bank7 stays inert 0xFF filler (never selected by any code).    ---
    bgm_bank, _ = bgm_bank_gen.build_bank()
    rom = rom96 + bytes(bgm_bank) + bytes([0xFF] * 0x4000)

    out_path = os.path.join(REPO, "rom", "CyberS Comb.ascii16k.rom")
    with open(out_path, "wb") as f:
        f.write(rom)

    print(f"wrote {out_path}: {len(rom)} bytes (banks 0-6 real content + 1 inert filler bank, 128KB total)")
    print(f"  bank0 (title page1): {len(title_bank0)}B, header {bytes(title_bank0[0:4]).hex()}")
    print(f"  bank1 (title page2): {len(title_bank1)}B")
    print(f"  bank2 (Stage1 page1, real game + test patch): {len(game_bank0)}B, header {bytes(game_bank0[0:4]).hex()}")
    print(f"  bank3 (Stage1 page2, real game, unpatched): {len(game_bank1)}B")
    print(f"  bank4 (Stage2 page1, real tools/stage2_combined content): {len(bank4)}B, header {bytes(bank4[0:4]).hex()}")
    print(f"  bank5 (Stage2 page2, real tools/stage2_combined content): {len(bank5)}B")
    print(f"  bank6 (BGM data, tools/bgm_data/bgm_bank_gen.py): {len(bgm_bank)}B")
    print(f"title INIT={title_sym['INIT']:04x}")
    print(f"game MAINLOOP={game_sym['MAINLOOP']:04x} GAME_TICK={game_sym['GAME_TICK']:04x}")
    print(f"stage2 (real) INIT={stage2_sym['INIT']:04x} MAINLOOP={stage2_sym['MAINLOOP']:04x}")


if __name__ == "__main__":
    main()
