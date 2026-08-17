; Tank player sprite test: standalone, real-hardware-shaped ROM that
; displays the tank as 4 real MSX hardware sprites (2x2 of 16x16,
; matching the existing ship's [top-left][bottom-left][top-right]
; [bottom-right] byte-order convention) and cycles through all 4 poses
; so each can be checked. No movement/physics yet - this is purely a
; sprite-conversion/composition correctness test.
    ORG 4000h

INIT32  EQU 006Fh
LDIRVM  EQU 005Ch
WRTVDP  EQU 0047h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

SPRATR   EQU 1B00h
SPRPAT   EQU 3800h
TANK_COLOR EQU 4      ; dark blue ("ブルー")
TANK_X   EQU 100
TANK_Y   EQU 150
TICK     EQU 0F000h
POSE_IX  EQU 0F001h    ; 0-3, cycles every ~60 frames
STACKTOP EQU 0F380h

INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32
    EI

    ; 16x16 sprite mode (VDP R1 bit1=SI) - same incantation as the real
    ; game's own INIT, just without the RG1SAV BIOS-shadow indirection
    ; (no BIOS register tracking in this standalone test).
    LD B,0E2h : LD C,1 : CALL WRTVDP

    ; load all 4 poses' patterns (128 bytes each: TL,TR,BL,BR x 32B).
    ; NOTE: mini_z80asm.py evaluates expressions strictly left-to-right
    ; with no operator precedence (by design - see eval_expr), so this
    ; must be written as PAT*8+SPRPAT (multiply first), matching the
    ; existing convention used throughout src/CYBER SHMUP.asm (e.g.
    ; "LD DE,PAT_SHIP*8+SPRPAT") - SPRPAT+PAT*8 would wrongly evaluate
    ; as (SPRPAT+PAT)*8 instead. Caught via a garbage DE value (0xC000
    ; instead of 0x3800) when the sprite failed to render.
    LD HL,TANK_TANKF_TL    : LD DE,PAT_TANKF*8+SPRPAT    : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUP_TL   : LD DE,PAT_TANKUP*8+SPRPAT   : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKFGAP_TL : LD DE,PAT_TANKFGAP*8+SPRPAT : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUGAP_TL : LD DE,PAT_TANKUGAP*8+SPRPAT : LD BC,128 : CALL LDIRVM

    XOR A
    LD (TICK),A
    LD (POSE_IX),A

MAINLOOP:
    LD A,(TICK) : INC A : LD (TICK),A
    AND 3Fh
    JR NZ,SKIP_POSE_ADV
    LD A,(POSE_IX) : INC A : CP 4 : JR NZ,NO_WRAP_POSE : XOR A
NO_WRAP_POSE:
    LD (POSE_IX),A
SKIP_POSE_ADV:

    LD A,(POSE_IX)
    ADD A,A : ADD A,A : ADD A,A : ADD A,A  ; *16 = pattern base for this pose
    LD (CUR_PAT_BASE),A

    LD IX,SPRITE_ATTRS
    LD A,TANK_Y      : LD (IX+0),A
    LD A,TANK_X      : LD (IX+1),A
    LD A,(CUR_PAT_BASE) : LD (IX+2),A
    LD A,TANK_COLOR  : LD (IX+3),A

    LD A,TANK_Y      : LD (IX+4),A
    LD A,TANK_X+16   : LD (IX+5),A
    LD A,(CUR_PAT_BASE) : ADD A,4 : LD (IX+6),A
    LD A,TANK_COLOR  : LD (IX+7),A

    LD A,TANK_Y+16   : LD (IX+8),A
    LD A,TANK_X      : LD (IX+9),A
    LD A,(CUR_PAT_BASE) : ADD A,8 : LD (IX+10),A
    LD A,TANK_COLOR  : LD (IX+11),A

    LD A,TANK_Y+16   : LD (IX+12),A
    LD A,TANK_X+16   : LD (IX+13),A
    LD A,(CUR_PAT_BASE) : ADD A,12 : LD (IX+14),A
    LD A,TANK_COLOR  : LD (IX+15),A

    LD HL,SPRITE_ATTRS : LD DE,SPRATR : LD BC,16 : CALL LDIRVM

    JP MAINLOOP

CUR_PAT_BASE:
    DS 1,0
SPRITE_ATTRS:
    DS 16,0

; ===== generated tables appended below by build_test.py =====
