; Stage 2 ground/slope scroller test: a standalone, real-hardware-shaped
; ROM (own INIT, own MAINLOOP) that renders the 4-row connected
; climb/descend test track from terrain_gen.py using stage 1's exact
; REFRESH_IDCACHE_33 / cell-pair-blend engine, but with all 4 rows
; sharing ONE PXCHAR/PHASE clock (gated every 8 ticks) instead of
; stage 1's 4 independently-rated parallax tiers - this is one
; physically connected road surface, not decorative layers scrolling
; past each other at different speeds.
;
; No EI/HALT vblank pacing - this is a Python/emulator-verified data
; test, not meant to run paced on real hardware yet, so MAINLOOP just
; free-runs every step to keep emulator verification simple (no real
; HALT ever executes, so scripted stepping never risks hanging on
; z80emu.py's lack of an interrupt source).
    ORG 4000h

INIT32  EQU 006Fh
LDIRVM  EQU 005Ch
WRTVDP  EQU 0047h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

TICK          EQU 0F000h
PXCHAR_T      EQU 0F001h
ROWPHASE_T    EQU 0F002h
TERRAIN_NEXTID EQU 0F003h
IDCACHE_T0    EQU 0F010h
IDCACHE_T1    EQU 0F040h
IDCACHE_T2    EQU 0F070h
IDCACHE_T3    EQU 0F0A0h
NAMEBUF_T0    EQU 0F100h
NAMEBUF_T1    EQU 0F120h
NAMEBUF_T2    EQU 0F140h
NAMEBUF_T3    EQU 0F160h
STACKTOP      EQU 0F380h

INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32
    EI

    LD HL,TERRAIN_PATTERNS : LD DE,0000h : LD BC,TERRAIN_PATTERN_COUNT*8 : CALL LDIRVM
    LD HL,TERRAIN_COLORDATA : LD DE,2000h : LD BC,32 : CALL LDIRVM

    ; border/backdrop = black
    LD B,1 : LD C,7 : CALL WRTVDP

    ; clear the WHOLE name table (768 cells) to code0 (BLANK, sky group)
    ; first - MAINLOOP only ever touches rows 20-23 itself, so without
    ; this the other 20 rows stay whatever leftover garbage BIOS SCREEN1
    ; init left behind.
    LD HL,TERRAIN_BLANK_ROW : LD DE,1800h : LD BC,768 : CALL LDIRVM

    XOR A
    LD (TICK),A
    LD (PXCHAR_T),A
    LD (ROWPHASE_T),A

    ; prime all 4 IDCACHEs at PXCHAR_T=0 so the very first frame (before
    ; the first "every 8 ticks" gate fires) already shows real content,
    ; not leftover garbage - mirrors stage1 INIT's own priming calls.
    LD HL,TERRAIN_ROWDATA0 : LD IX,IDCACHE_T0 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA1 : LD IX,IDCACHE_T1 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA2 : LD IX,IDCACHE_T2 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA3 : LD IX,IDCACHE_T3 : CALL REFRESH_IDCACHE_33

MAINLOOP:
    LD A,(TICK) : INC A : LD (TICK),A

    AND 07h
    JR NZ,SKIP_ADVANCE
    LD A,(PXCHAR_T) : INC A : LD (PXCHAR_T),A   ; 256-cell track: byte wraps naturally
    LD HL,TERRAIN_ROWDATA0 : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE_T0 : CALL REFRESH_IDCACHE_33
    LD A,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA1 : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE_T1 : CALL REFRESH_IDCACHE_33
    LD A,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA2 : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE_T2 : CALL REFRESH_IDCACHE_33
    LD A,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA3 : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE_T3 : CALL REFRESH_IDCACHE_33
SKIP_ADVANCE:
    LD A,(TICK) : AND 07h : LD (ROWPHASE_T),A

    LD HL,IDCACHE_T0 : LD IX,NAMEBUF_T0 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T1 : LD IX,NAMEBUF_T1 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T2 : LD IX,NAMEBUF_T2 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T3 : LD IX,NAMEBUF_T3 : CALL TERRAIN_RENDER_ROW

    ; push to VRAM: name table base 1800h, rows 20-23 -> 1A80h,1AA0h,1AC0h,1AE0h
    LD HL,NAMEBUF_T0 : LD DE,1A80h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T1 : LD DE,1AA0h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T2 : LD DE,1AC0h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T3 : LD DE,1AE0h : LD BC,32 : CALL LDIRVM

    JP MAINLOOP

; Translates 33 consecutive ROWDATA bytes through TERRAIN_LUT into an
; IDCACHEn buffer - byte-for-byte the same routine as stage1's
; REFRESH_IDCACHE_33 (src/CYBER SHMUP.asm), reused verbatim; only the
; LUT content differs (identity here, since ROWDATA already stores raw
; ids, vs stage1's ASCII-terrain-letter LUT).
; Input: HL = source (ROWDATAn + PXCHAR), IX = dest (IDCACHEn).
REFRESH_IDCACHE_33:
    LD B,33
RIC_LOOP:
    LD A,(HL) : LD E,A : LD D,TERRAIN_LUT/256 : LD A,(DE)
    LD (IX+0),A
    INC HL
    INC IX
    DJNZ RIC_LOOP
    RET

; Renders one 32-cell row from an IDCACHEn buffer into a NAMEBUF row,
; blending via TERRAIN_PAIRBASE/TERRAIN_SOLOTAB at the shared
; ROWPHASE_T - byte-for-byte the same cell-blend algorithm as stage1's
; CELL_LOOP_0/2/3/5, just factored into one callable routine (stage1
; repeats it inline per row; here all 4 rows share the same shape so a
; real subroutine avoids 4x code duplication).
; Input: HL = IDCACHEn ptr, IX = NAMEBUF row ptr. Clobbers A,B,C,D,E,HL,IX.
TERRAIN_RENDER_ROW:
    LD B,32
    LD A,(HL) : LD C,A
TRR_LOOP:
    INC HL
    LD A,(HL) : LD (TERRAIN_NEXTID),A
    LD A,(ROWPHASE_T) : OR A
    JR NZ,TRR_NONZERO
    LD A,C : LD E,A : LD D,TERRAIN_SOLOTAB/256 : LD A,(DE)
    JR TRR_STORE
TRR_NONZERO:
    LD A,C : LD E,A : LD D,TERRAIN_MUL_N/256 : LD A,(DE) : LD E,A
    LD A,(TERRAIN_NEXTID) : ADD A,E
    LD E,A : LD D,TERRAIN_PAIRBASE/256 : LD A,(DE)
    LD E,A
    LD A,(ROWPHASE_T) : DEC A : ADD A,E
TRR_STORE:
    LD (IX+0),A
    INC IX
    LD A,(TERRAIN_NEXTID) : LD C,A
    DJNZ TRR_LOOP
    RET

    ALIGN 256
TERRAIN_LUT:
    DB 0,1,2,3,4,5,6,7,8,9,10
    DS 245,0

; 768 zero bytes = code0 (BLANK) repeated, used to clear the whole name
; table to sky/blank once at INIT.
TERRAIN_BLANK_ROW:
    DS 768,0

; ===== generated tables appended below by build_test.py =====
