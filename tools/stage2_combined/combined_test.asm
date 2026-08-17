; Combined test: the stage2 terrain scroller (tools/stage2_terrain)
; with the tank sprite (tools/stage2_tank) on top of it, now with
; left/right movement, a B-button jump, and pose switching (up+aim
; and airborne/Gap poses). Border-color diagnostic checkpoints through
; INIT so a freeze report can point at exactly which step it's stuck
; on (see the table in README.md).
;
; STILL not physics-integrated with the terrain: the tank's resting Y
; is a fixed baseline (matching the terrain's starting flat tier), not
; tracking the terrain's climb/descend height - that needs the
; ground-height collision system, not built yet (per direct
; instruction, deferred along with the terrain-slope Gap pose - the
; Gap poses are wired up for the jump only right now).
    ORG 4000h

INIT32  EQU 006Fh
LDIRVM  EQU 005Ch
WRTVDP  EQU 0047h
GTSTCK  EQU 00D5h
GTTRIG  EQU 00D8h

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
TANK_X_INIT   EQU 40
TANK_Y_BASE   EQU 155      ; row23 top (23*8=184) - tank height(32) + landing offset(3)
TANK_SPEED    EQU 2        ; px/frame, left/right
JUMP_PEAK     EQU 16       ; px, per spec
SPRITE_ATTRS  EQU 0F200h   ; 16 bytes

TANK_X        EQU 0F220h
TANK_Y_CUR    EQU 0F221h
TANK_DX       EQU 0F222h   ; 1=right, 0FFh=left, 0=none
TANK_AIMUP    EQU 0F223h   ; 1 while holding up (diagonal-aim pose)
JOY_DIR       EQU 0F224h
JOY_TRIGB     EQU 0F225h
PREV_TRIGB    EQU 0F226h
JUMP_ACTIVE   EQU 0F227h
JUMP_FRAME    EQU 0F228h
JUMP_Y_OFFSET EQU 0F229h
CUR_POSE_PAT  EQU 0F22Ah

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

    LD HL,TANK_TANKF_TL    : LD DE,PAT_TANKF*8+SPRPAT    : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUP_TL   : LD DE,PAT_TANKUP*8+SPRPAT   : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKFGAP_TL : LD DE,PAT_TANKFGAP*8+SPRPAT : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUGAP_TL : LD DE,PAT_TANKUGAP*8+SPRPAT : LD BC,128 : CALL LDIRVM

    ; checkpoint 6: tank pattern loaded
    LD B,6 : LD C,7 : CALL WRTVDP

    ; tank state: centered start, grounded, facing/aiming neutral
    LD A,TANK_X_INIT : LD (TANK_X),A
    LD A,TANK_Y_BASE : LD (TANK_Y_CUR),A
    XOR A
    LD (TANK_DX),A
    LD (TANK_AIMUP),A
    LD (PREV_TRIGB),A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
    LD (JUMP_Y_OFFSET),A
    LD A,PAT_TANKF : LD (CUR_POSE_PAT),A

    CALL UPDATE_TANK_SPRITES

    ; hide every sprite slot past the tank's 4 (Y=0D1h is the standard
    ; MSX "stop processing sprites here" sentinel) - the VRAM's
    ; zero-initialized default otherwise leaves slot4 at Y=0/X=0/
    ; pattern=0/color=0, which happens to alias the tank's own TL
    ; pattern (PAT_TANKF=0) and renders it a second time in black at
    ; the top-left corner. Caught visually, not by any register check.
    LD A,0D1h : LD (SPR_HIDE),A
    LD HL,SPR_HIDE : LD DE,SPRATR+16 : LD BC,1 : CALL LDIRVM

    ; checkpoint 7: tank sprite attributes written
    LD B,7 : LD C,7 : CALL WRTVDP

    ; border back to black - checkpoints 1-7 above were diagnostic
    ; only, leaving it on whatever the last one was (cyan) would
    ; otherwise sit there as a permanent, confusing border color.
    LD B,1 : LD C,7 : CALL WRTVDP

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

    CALL READ_INPUT
    CALL UPDATE_TANK_XY
    CALL UPDATE_JUMP
    CALL UPDATE_POSE
    CALL UPDATE_TANK_SPRITES

    JP MAINLOOP

; ---------- input ----------
; port1 stick -> JOY_DIR (0-8 compass, 0=none,1=up,2=upright,3=right,
; 4=downright,5=down,6=downleft,7=left,8=upleft); port1 trigger B
; (jump) -> JOY_TRIGB (0/FFh).
READ_INPUT:
    LD A,1 : CALL GTSTCK
    LD (JOY_DIR),A
    LD A,3 : CALL GTTRIG
    LD (JOY_TRIGB),A
    RET

; ---------- horizontal movement + aim-up flag ----------
UPDATE_TANK_XY:
    XOR A
    LD (TANK_DX),A
    LD (TANK_AIMUP),A

    LD A,(JOY_DIR)
    CP 2 : JR Z,UTX_RIGHT
    CP 3 : JR Z,UTX_RIGHT
    CP 4 : JR Z,UTX_RIGHT
    CP 6 : JR Z,UTX_LEFT
    CP 7 : JR Z,UTX_LEFT
    CP 8 : JR Z,UTX_LEFT
    JR UTX_DIR_DONE
UTX_RIGHT:
    LD A,1 : LD (TANK_DX),A
    JR UTX_DIR_DONE
UTX_LEFT:
    LD A,0FFh : LD (TANK_DX),A
UTX_DIR_DONE:

    LD A,(JOY_DIR)
    CP 1 : JR Z,UTX_AIMUP
    CP 2 : JR Z,UTX_AIMUP
    CP 8 : JR Z,UTX_AIMUP
    JR UTX_MOVE
UTX_AIMUP:
    LD A,1 : LD (TANK_AIMUP),A

UTX_MOVE:
    LD A,(TANK_DX)
    CP 1
    JR Z,UTX_DO_RIGHT
    CP 0FFh
    JR Z,UTX_DO_LEFT
    RET
UTX_DO_RIGHT:
    LD A,(TANK_X)
    CP 224
    RET NC
    ADD A,TANK_SPEED : LD (TANK_X),A
    RET
UTX_DO_LEFT:
    LD A,(TANK_X)
    CP TANK_SPEED
    RET C
    SUB TANK_SPEED : LD (TANK_X),A
    RET

; ---------- jump (B button, edge-triggered, 16px triangular arc) ----------
UPDATE_JUMP:
    LD A,(JOY_TRIGB)
    LD HL,PREV_TRIGB
    CP (HL)
    JR Z,UJ_NO_NEW_PRESS
    OR A
    JR Z,UJ_NO_NEW_PRESS
    LD A,(JUMP_ACTIVE)
    OR A
    JR NZ,UJ_NO_NEW_PRESS
    LD A,1 : LD (JUMP_ACTIVE),A
    XOR A : LD (JUMP_FRAME),A
UJ_NO_NEW_PRESS:
    LD A,(JOY_TRIGB) : LD (PREV_TRIGB),A

    LD A,(JUMP_ACTIVE)
    OR A
    JR Z,UJ_DONE
    LD A,(JUMP_FRAME) : INC A : LD (JUMP_FRAME),A
    CP 16
    JR C,UJ_STILL_JUMPING
    XOR A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
UJ_STILL_JUMPING:
UJ_DONE:
    LD A,(JUMP_FRAME) : LD E,A : LD D,0
    LD HL,JUMP_OFFSET_TABLE : ADD HL,DE
    LD A,(HL) : LD (JUMP_Y_OFFSET),A

    LD A,TANK_Y_BASE
    LD HL,JUMP_Y_OFFSET
    SUB (HL)
    LD (TANK_Y_CUR),A
    RET

; ---------- pose: ground/air x neutral/aim-up ----------
UPDATE_POSE:
    LD A,(JUMP_ACTIVE)
    OR A
    JR Z,UP_GROUND
    LD A,(TANK_AIMUP)
    OR A
    JR Z,UP_FGAP
    LD A,PAT_TANKUGAP : JR UP_SET
UP_FGAP:
    LD A,PAT_TANKFGAP : JR UP_SET
UP_GROUND:
    LD A,(TANK_AIMUP)
    OR A
    JR Z,UP_F
    LD A,PAT_TANKUP : JR UP_SET
UP_F:
    LD A,PAT_TANKF
UP_SET:
    LD (CUR_POSE_PAT),A
    RET

; ---------- writes the 4 sprite attribute entries from TANK_X/ ----------
; TANK_Y_CUR/CUR_POSE_PAT. Called once from INIT, then every frame.
UPDATE_TANK_SPRITES:
    LD IX,SPRITE_ATTRS
    LD A,(TANK_Y_CUR) : LD (IX+0),A
    LD A,(TANK_X)     : LD (IX+1),A
    LD A,(CUR_POSE_PAT) : LD (IX+2),A
    LD A,TANK_COLOR   : LD (IX+3),A

    LD A,(TANK_Y_CUR) : LD (IX+4),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+5),A
    LD A,(CUR_POSE_PAT) : ADD A,4 : LD (IX+6),A
    LD A,TANK_COLOR   : LD (IX+7),A

    LD A,(TANK_Y_CUR) : ADD A,16 : LD (IX+8),A
    LD A,(TANK_X)     : LD (IX+9),A
    LD A,(CUR_POSE_PAT) : ADD A,8 : LD (IX+10),A
    LD A,TANK_COLOR   : LD (IX+11),A

    LD A,(TANK_Y_CUR) : ADD A,16 : LD (IX+12),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+13),A
    LD A,(CUR_POSE_PAT) : ADD A,12 : LD (IX+14),A
    LD A,TANK_COLOR   : LD (IX+15),A

    LD HL,SPRITE_ATTRS : LD DE,SPRATR : LD BC,16 : CALL LDIRVM
    RET

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

; 17 entries (jump frame 0-16): 0,2,4,...,16,...,4,2,0 - a triangular
; 16px-peak arc, matching the spec height exactly regardless of frame
; count (change this table's shape, not the frame-count logic, if the
; arc needs to feel different later).
JUMP_OFFSET_TABLE:
    DB 0,2,4,6,8,10,12,14,16,14,12,10,8,6,4,2,0

; ===== generated tables (terrain + tank) appended below by build_test.py =====
