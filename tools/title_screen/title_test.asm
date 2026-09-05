; Title-screen bank test (round39, "バンクテストをしたいので...新バンク
; には必要な初期化処理を実装した上で PUSH STARTと表示しStage1とStage2
; のボスを適当に表示して ボタンが押されたらStage1へトランポリンする
; ように"). This is a genuinely new, THIRD bank pair (title/PUSH START)
; added to the existing 2-pair (Stage1, Stage2) ASCII16 layout - see
; tools/bankswitch_poc/build_full_rom.py for how the 3 pairs actually
; get laid out into one ROM and which becomes the boot target.
;
; Self-contained and independently assemblable/testable (own
; build_test.py), same convention as tools/stage2_combined/
; combined_test.asm - this file never needs Stage1/Stage2's own source
; touched, and vice versa.
;
; Boss art is NOT hand-drawn here - tools/title_screen/title_gen.py
; pulls Stage1's real BOSS_PATTERNS/BOSS_MAP (a live assemble of
; src/CYBER SHMUP.asm) and Stage2's real Sasapi hw-sprite quadrants
; (tools/stage2_combined/sasapi_gen.py) directly, so "適当に表示して"
; (display them casually) still shows the genuine shipped art, just
; positioned without any of the real games' own animation/materialize
; sequencing - a static, one-time INIT-time draw.
    ORG 4000h

INIT32   EQU 006Fh
LDIRVM   EQU 005Ch
WRTVRM   EQU 004Dh
WRTVDP   EQU 0047h
GTTRIG   EQU 00D8h
PSG_ADDR EQU 0A0h
PSG_DATA EQU 0A1h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

STACKTOP EQU 0F380h

; standard SCREEN1 VRAM layout - these are INIT32's own BIOS defaults
; (not chosen by this file), matching the exact same constants Stage1/
; Stage2 already rely on.
NAMTBL EQU 1800h
COLTBL EQU 2000h
SPRATR EQU 1B00h
SPRPAT EQU 3800h

; RAM-resident bank-switch trampoline (see tools/bankswitch_poc/
; build_full_rom.py's own TRAMPOLINE_PATCH for the identical mechanism
; Stage1 uses) - this bank is the new boot target (bank0/window A,
; bank1/window B), so it installs its OWN copy rather than relying on
; one only Stage1's INIT would otherwise set up.
BANKSWITCH_TRAMPOLINE_RAM EQU 0F200h

; global bank indices in the final ROM (see build_full_rom.py's own
; layout comment) - title=bank0/1 (this file), Stage1=bank2/3,
; Stage2=bank4/5. Stage1's own INIT lives at 4010h (same relative
; offset this file's own INIT does, and Stage2's - all 3 share the
; identical 16-byte "AB" header layout at ORG 4000h).
STAGE1_BANK_A EQU 2
STAGE1_BANK_B EQU 3
STAGE1_INIT   EQU 04010h

INIT:
    LD SP,STACKTOP

    ; --- map our own primary slot into page 2 (8000h-BFFFh) too - same ---
    ; --- as Stage1/Stage2's own INIT (see their own comment: the BIOS ---
    ; --- cartridge-boot sequence only auto-maps page 1).              ---
    IN A,(0A8h)
    LD B,A
    AND 0Ch
    ADD A,A
    ADD A,A
    LD C,A
    LD A,B
    AND 0CFh
    OR C
    OUT (0A8h),A

    DI
    CALL INIT32

    ; 16x16 sprites + VDP interrupt enable - same R1 value Stage2 uses
    ; (0E2h: 16K VRAM, display on, IE on, 16x16 sprite size).
    LD B,0E2h : LD C,1 : CALL WRTVDP

    ; border/backdrop black
    LD B,01h : LD C,7 : CALL WRTVDP

    ; install the RAM trampoline (own copy - see BANKSWITCH_TRAMPOLINE_RAM's comment)
    LD HL,BANKSWITCH_TRAMPOLINE_SRC
    LD DE,BANKSWITCH_TRAMPOLINE_RAM
    LD BC,BANKSWITCH_TRAMPOLINE_LEN
    LDIR

    ; mute all 3 PSG channels' volumes (defensive - nothing has played
    ; yet, but matches the "always leave the PSG in a known state"
    ; convention every INIT in this project already follows - same 3
    ; writes as build_full_rom.py's own pre-switch mute).
    LD A,8 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A

    ; ---------- Stage1 boss (BG, 5x16 tiles @ codes192-255 + code48) ----------
    LD HL,TITLE_STAGE1_BOSS_PATTERNS : LD DE,192*8 : LD BC,512 : CALL LDIRVM
    LD HL,TITLE_STAGE1_BLANK48_PATTERN : LD DE,48*8 : LD BC,8 : CALL LDIRVM

    ; color: groups24-31 (codes192-255) and group6 (code48) - white on
    ; black (0F1h), a plain readable placeholder ("適当に").
    LD HL,TITLE_BOSS_COLOR : LD DE,COLTBL+24 : LD BC,8 : CALL LDIRVM
    LD A,0F1h : LD HL,COLTBL+6 : CALL WRTVRM

    ; draw BOSS_MAP (5 cols x16 rows) into the name table starting at
    ; row2/col2 - 16 unrolled 5-byte LDIRVMs (source is contiguous, dest
    ; jumps by 32 bytes/row, so one big block copy can't do this).
    ; Addresses are computed in Python (title_gen.py's own
    ; emit_boss1_draw_loop) rather than via in-ASM multiplication - see
    ; that function's own comment for why.
; ===== TITLE_BOSS1_DRAW_LOOP placeholder, filled in by build_test.py =====

    ; ---------- Stage2 boss (Sasapi, 64x64 hw sprite, 16x16x16 quadrants) ----------
    LD HL,TITLE_STAGE2_BOSS_QUADS : LD DE,SPRPAT : LD BC,512 : CALL LDIRVM
    LD HL,TITLE_STAGE2_BOSS_SPRITE_ATTRS : LD DE,SPRATR : LD BC,64 : CALL LDIRVM

    ; ---------- "PUSH START" text ----------
    ; SCREEN1's default font (loaded by INIT32 itself, untouched here -
    ; this file never redefines codes32-95) already covers plain ASCII,
    ; so this is a literal ASCII string, not custom glyph data.
    LD A,0F1h
    LD HL,COLTBL+4 : CALL WRTVRM    ; group4 (codes32-39, space)
    LD HL,COLTBL+8 : CALL WRTVRM    ; group8 (codes64-71, incl. 'A')
    LD HL,COLTBL+9 : CALL WRTVRM    ; group9 (codes72-79, incl. 'H')
    LD HL,COLTBL+10 : CALL WRTVRM   ; group10 (codes80-87, incl. P/R/S/T/U)
    ; dest = NAMTBL(1800h)+20*32+11 = 1A8Bh - written as a literal, not
    ; "NAMTBL+20*32+11", because this project's own assembler
    ; (mini_z80asm.py) evaluates expressions strictly left-to-right with
    ; no operator precedence (see title_gen.py's own emit_boss1_draw_
    ; loop comment for the same class of bug this file caught once
    ; already, round36-14 follow-up#8's "BASE+N*4" precedent).
    LD HL,TITLE_PUSH_START_TEXT
    LD DE,01A8Bh
    LD BC,10
    CALL LDIRVM

    EI

; idle until the trigger button is pressed, then trampoline into
; Stage1 (bank2/3) - same 2-hop RAM-trampoline mechanism build_full_
; rom.py's own MAINLOOP_PATCH already uses for Stage1->Stage2.
WAIT_FOR_START:
    LD A,1
    CALL GTTRIG
    OR A
    JR Z,WAIT_FOR_START

    LD A,STAGE1_BANK_B
    LD DE,7000h
    LD HL,GOTO_STAGE1_HOP2
    JP BANKSWITCH_TRAMPOLINE_RAM
GOTO_STAGE1_HOP2:
    LD A,STAGE1_BANK_A
    LD DE,6000h
    LD HL,STAGE1_INIT
    JP BANKSWITCH_TRAMPOLINE_RAM

BANKSWITCH_TRAMPOLINE_SRC:
    LD (DE),A
    JP (HL)
BANKSWITCH_TRAMPOLINE_LEN EQU $ - BANKSWITCH_TRAMPOLINE_SRC

TITLE_BOSS_COLOR:
    DB 0F1h,0F1h,0F1h,0F1h,0F1h,0F1h,0F1h,0F1h

TITLE_PUSH_START_TEXT:
    DB "PUSH START"

; ===== boss art tables, generated by title_gen.py - see that file =====
