; Combined test: the stage2 terrain scroller (tools/stage2_terrain)
; with the tank sprite (tools/stage2_tank) sitting on top of it, in
; one standalone 32KB ROM - the tank-only test reportedly froze on
; real hardware, and separately the terrain wasn't shown at all in
; that test even though a tank floating on nothing isn't a meaningful
; check. Border-color diagnostic checkpoints added through INIT so a
; freeze report can point at exactly which step it's stuck on (see
; the table in README.md).
;
; NOT yet physics-integrated: the tank sits at a fixed screen
; position matching the terrain's starting (tier0/flat) height. It
; does not yet track the terrain's climb/descend height changes -
; that needs the ground-height collision system, not built yet.
    ORG 4000h

INIT32  EQU 006Fh
LDIRVM  EQU 005Ch
WRTVDP  EQU 0047h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

; ---------- terrain state (see tools/stage2_terrain/terrain_test.asm) ----------
TICK          EQU 0F000h
PXCHAR_T      EQU 0F001h   ; word
ROWPHASE_T    EQU 0F003h
TERRAIN_NEXTID EQU 0F004h
IDCACHE_T0    EQU 0F010h
IDCACHE_T1    EQU 0F040h
IDCACHE_T2    EQU 0F070h
IDCACHE_T3    EQU 0F0A0h
NAMEBUF_T0    EQU 0F100h
NAMEBUF_T1    EQU 0F120h
NAMEBUF_T2    EQU 0F140h
NAMEBUF_T3    EQU 0F160h

; ---------- tank state (past terrain's own range - 0F100h-0F180h) ----------
SPRATR        EQU 1B00h
SPRPAT        EQU 3800h
TANK_COLOR    EQU 4        ; dark blue
TANK_X        EQU 40
TANK_Y        EQU 155      ; row23 top (23*8=184) - tank height(32) + landing offset(3)
SPRITE_ATTRS  EQU 0F200h   ; 16 bytes

STACKTOP      EQU 0F380h

INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32
    EI

    ; checkpoint 1: INIT started, SP set, BIOS SCREEN1 setup done
    LD B,1 : LD C,7 : CALL WRTVDP

    LD HL,TERRAIN_PATTERNS : LD DE,0000h : LD BC,TERRAIN_PATTERN_COUNT*8 : CALL LDIRVM
    LD HL,TERRAIN_COLORDATA : LD DE,2000h : LD BC,32 : CALL LDIRVM

    ; checkpoint 2: terrain patterns + color table loaded
    LD B,2 : LD C,7 : CALL WRTVDP

    LD HL,TERRAIN_BLANK_ROW : LD DE,1800h : LD BC,768 : CALL LDIRVM

    ; checkpoint 3: whole name table cleared to sky
    LD B,3 : LD C,7 : CALL WRTVDP

    LD HL,TERRAIN_ROCKY_BLANK : LD DE,TERRAIN_PATTERN_COUNT*8 : LD BC,8 : CALL LDIRVM
    LD HL,TERRAIN_ROW19 : LD DE,1A60h : LD BC,32 : CALL LDIRVM

    XOR A
    LD (TICK),A
    LD HL,0
    LD (PXCHAR_T),HL
    LD (ROWPHASE_T),A

    LD HL,TERRAIN_ROWDATA0 : LD IX,IDCACHE_T0 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA1 : LD IX,IDCACHE_T1 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA2 : LD IX,IDCACHE_T2 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA3 : LD IX,IDCACHE_T3 : CALL REFRESH_IDCACHE_33

    ; checkpoint 4: row19 filled, terrain IDCACHEs primed
    LD B,4 : LD C,7 : CALL WRTVDP

    ; 16x16 sprite mode (VDP R1 bit1=SI)
    LD B,0E2h : LD C,1 : CALL WRTVDP

    ; checkpoint 5: 16x16 sprite mode set
    LD B,5 : LD C,7 : CALL WRTVDP

    LD HL,TANK_TANKF_TL : LD DE,PAT_TANKF*8+SPRPAT : LD BC,128 : CALL LDIRVM

    ; checkpoint 6: tank pattern loaded
    LD B,6 : LD C,7 : CALL WRTVDP

    ; sprite attributes: tank sits statically at (TANK_X,TANK_Y), pose
    ; TankF (flat ground) - 4 sprites: TL,TR,BL,BR
    LD IX,SPRITE_ATTRS
    LD A,TANK_Y      : LD (IX+0),A
    LD A,TANK_X      : LD (IX+1),A
    LD A,PAT_TANKF   : LD (IX+2),A
    LD A,TANK_COLOR  : LD (IX+3),A
    LD A,TANK_Y      : LD (IX+4),A
    LD A,TANK_X+16   : LD (IX+5),A
    LD A,PAT_TANKF+4 : LD (IX+6),A
    LD A,TANK_COLOR  : LD (IX+7),A
    LD A,TANK_Y+16   : LD (IX+8),A
    LD A,TANK_X      : LD (IX+9),A
    LD A,PAT_TANKF+8 : LD (IX+10),A
    LD A,TANK_COLOR  : LD (IX+11),A
    LD A,TANK_Y+16   : LD (IX+12),A
    LD A,TANK_X+16   : LD (IX+13),A
    LD A,PAT_TANKF+12 : LD (IX+14),A
    LD A,TANK_COLOR  : LD (IX+15),A
    LD HL,SPRITE_ATTRS : LD DE,SPRATR : LD BC,16 : CALL LDIRVM

    ; hide every sprite slot past the tank's 4 (Y=0D1h is the standard
    ; MSX "stop processing sprites here" sentinel) - the VRAM's
    ; zero-initialized default otherwise leaves slot4 at Y=0/X=0/
    ; pattern=0/color=0, which happens to alias the tank's own TL
    ; pattern (PAT_TANKF=0) and renders it a second time in black at
    ; the top-left corner. Caught visually, not by any register check.
    LD A,0D1h : LD (SPR_HIDE),A
    LD HL,SPR_HIDE : LD DE,SPRATR+16 : LD BC,1 : CALL LDIRVM

    ; checkpoint 7: tank sprite attributes written - entering MAINLOOP next
    LD B,7 : LD C,7 : CALL WRTVDP

MAINLOOP:
    LD A,(TICK) : INC A : LD (TICK),A

    AND 07h
    JR NZ,SKIP_ADVANCE
    LD HL,(PXCHAR_T) : INC HL
    LD (PXCHAR_T),HL
    LD DE,TERRAIN_TRACK_LEN
    OR A : SBC HL,DE
    JR NZ,PXT_NOWRAP
    LD HL,0
    LD (PXCHAR_T),HL
PXT_NOWRAP:
    LD DE,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA0 : ADD HL,DE
    LD IX,IDCACHE_T0 : CALL REFRESH_IDCACHE_33
    LD DE,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA1 : ADD HL,DE
    LD IX,IDCACHE_T1 : CALL REFRESH_IDCACHE_33
    LD DE,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA2 : ADD HL,DE
    LD IX,IDCACHE_T2 : CALL REFRESH_IDCACHE_33
    LD DE,(PXCHAR_T)
    LD HL,TERRAIN_ROWDATA3 : ADD HL,DE
    LD IX,IDCACHE_T3 : CALL REFRESH_IDCACHE_33
SKIP_ADVANCE:
    LD A,(TICK) : AND 07h : LD (ROWPHASE_T),A

    LD HL,IDCACHE_T0 : LD IX,NAMEBUF_T0 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T1 : LD IX,NAMEBUF_T1 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T2 : LD IX,NAMEBUF_T2 : CALL TERRAIN_RENDER_ROW
    LD HL,IDCACHE_T3 : LD IX,NAMEBUF_T3 : CALL TERRAIN_RENDER_ROW

    LD HL,NAMEBUF_T0 : LD DE,1A80h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T1 : LD DE,1AA0h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T2 : LD DE,1AC0h : LD BC,32 : CALL LDIRVM
    LD HL,NAMEBUF_T3 : LD DE,1AE0h : LD BC,32 : CALL LDIRVM

    JP MAINLOOP

REFRESH_IDCACHE_33:
    LD B,33
RIC_LOOP:
    LD A,(HL) : LD E,A : LD D,TERRAIN_LUT/256 : LD A,(DE)
    LD (IX+0),A
    INC HL
    INC IX
    DJNZ RIC_LOOP
    RET

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

TERRAIN_BLANK_ROW:
    DS 768,0

TERRAIN_ROCKY_BLANK:
    DS 8,0
TERRAIN_ROW19:
    DS 32,TERRAIN_PATTERN_COUNT

SPR_HIDE:
    DS 1,0

; ===== generated tables (terrain + tank) appended below by build_test.py =====
