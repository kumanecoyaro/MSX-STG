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

    ; ---------- BGM (round40, "タイトル含めて各ステージにドライバを配置し
    ; RAMにコピーしてステージスタート") ----------
    ; ここまで一切windowB(8000h-BFFFh)の内容を読んでいない(直前のPSG
    ; mute writeはVDP/PSGポートのみ)ので、bgm-dataバンクへの一時切替は
    ; 退避不要 - コピー後にこのファイル自身のbank1(標準ビルド=1、Comb=
    ; build_full_rom.py側のパッチで実際は変わらず1のまま、titleはComb
    ; でもbank0/1のまま)へ明示的に復帰してから続行する。
    CALL INIT_BGM

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

; ---------- BGM driver (Round40) ----------
; tools/stage2_combined/combined_test.asmの同名ドライバと同型(chB/chC
; 独立ポインタ・タイマー、詳細な設計理由はそちらの長いコメント参照)。
; このファイルは他に一切PSGを使わない(自機/敵/SFXが存在しない)ため、
; Stage2と違いR7の毎tick read-modify-writeは不要 - R7は下のINIT_BGM内で
; 一度だけ0B1h(tone B/C enable、Stage1が実際に使っている値と同一 -
; GTTRIGが依存するportA/B方向ビットを含め安全な値と分かっている)を書く。
; 曲はALONE_FIGHTER("Alone_Fighter.mid")、トランポリンでStage1へ移動した
; 後もStage1側は同じ曲をこのファイルがコピーしたRAMからそのまま読む
; (src/CYBER SHMUP.asm自身のBGM_TICKコメント参照 - Stage1はPSGチャンネル
; B/Cを既存SFXと共有しているため自分ではバンク切替もRAMコピーもしない)。
HTIMI_HOOK      EQU 0FD9Fh
BGM_VOLUME      EQU 10
BGM_NOTE_REST   EQU 0FFh
BGM_LOOP_MARK   EQU 0FEh
BGM_PERIOD_LO_RAM EQU 0C000h
BGM_PERIOD_HI_RAM EQU 0C023h
BGM_B_BASE        EQU 0C046h    ; ALONE_FIGHTER track0(chB)先頭
BGM_C_BASE        EQU 0C235h    ; ALONE_FIGHTER track1(chC)先頭
BGM_B_PTR   EQU 0C800h
BGM_C_PTR   EQU 0C802h
BGM_B_TIMER EQU 0C804h
BGM_C_TIMER EQU 0C805h

INIT_BGM:
    LD A,2                       ; standalone bgm-dataバンク(Combでは6へパッチ)
    LD (7000h),A
    LD HL,08000h : LD DE,0C000h : LD BC,046h : LDIR   ; 周期テーブル(35note*2)
    LD HL,08046h : LD DE,0C046h : LD BC,0628h : LDIR  ; ALONE_FIGHTER chB+chC
    LD A,1                       ; このファイル自身のbank1(Comb/standaloneとも1のまま)
    LD (7000h),A

    LD HL,BGM_B_BASE
    LD (BGM_B_PTR),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD HL,BGM_C_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_TIMER),A

    LD A,7 : OUT (PSG_ADDR),A
    LD A,0B1h : OUT (PSG_DATA),A  ; tone B/C enable, tone A + noise B/C disable, portA=in/portB=out

    LD A,0C3h
    LD (HTIMI_HOOK),A
    LD HL,BGM_TICK
    LD (HTIMI_HOOK+1),HL
    RET

BGM_TICK:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    CALL BGMT_UPDATE_B
    CALL BGMT_UPDATE_C
    POP HL
    POP DE
    POP BC
    POP AF
    RET

BGMT_UPDATE_B:
    LD A,(BGM_B_TIMER)
    OR A
    JR Z,BGMT_UB_NEWROW
    DEC A
    LD (BGM_B_TIMER),A
    RET
BGMT_UB_NEWROW:
    LD HL,(BGM_B_PTR)
    LD A,(HL)
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UB_GOT
    LD HL,BGM_B_BASE
    LD A,(HL)
BGMT_UB_GOT:
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (BGM_B_PTR),HL
    ; round40 実機フィードバック対応: off-by-one修正(combined_test.asm
    ; の同じ箇所の長いコメント参照) - 読み込みtick自体も1tick分の
    ; 再生になるため、DEC Aで合計durationぴったりに補正する。
    DEC A
    LD (BGM_B_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_UB_REST
    LD E,A : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,2 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,3 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A
    LD A,BGM_VOLUME : OUT (PSG_DATA),A
    RET
BGMT_UB_REST:
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET

BGMT_UPDATE_C:
    LD A,(BGM_C_TIMER)
    OR A
    JR Z,BGMT_UC_NEWROW
    DEC A
    LD (BGM_C_TIMER),A
    RET
BGMT_UC_NEWROW:
    LD HL,(BGM_C_PTR)
    LD A,(HL)
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UC_GOT
    LD HL,BGM_C_BASE
    LD A,(HL)
BGMT_UC_GOT:
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (BGM_C_PTR),HL
    ; round40 実機フィードバック対応: BGMT_UB_NEWROWの同じoff-by-one
    ; 修正コメント参照。
    DEC A
    LD (BGM_C_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_UC_REST
    LD E,A : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,4 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,5 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A
    LD A,BGM_VOLUME : OUT (PSG_DATA),A
    RET
BGMT_UC_REST:
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET

; ===== boss art tables, generated by title_gen.py - see that file =====
