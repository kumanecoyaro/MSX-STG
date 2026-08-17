; Combined test: the stage2 terrain scroller (tools/stage2_terrain)
; with the tank sprite (tools/stage2_tank) on top of it, now with
; left/right movement, a B-button jump, pose switching (up+aim and
; airborne/Gap poses), shots, and terrain ground-height collision (see
; UPDATE_TERRAIN_COLLISION) - the tank always rests on whichever
; terrain tier is under it and shows the Gap pose while straddling a
; climb/descend transition. Border-color diagnostic checkpoints
; through INIT so a freeze report can point at exactly which step it's
; stuck on (see the table in README.md).
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
TANK_COLOR_TL EQU 6        ; dark red (main body)
TANK_COLOR_TR EQU 1        ; black
TANK_COLOR_BL EQU 1        ; black
TANK_COLOR_BR EQU 1        ; black
TANK_X_INIT   EQU 40
TANK_Y_BASE   EQU 156      ; row23 top (23*8=184) - tank height(32) + landing offset(3+1)
; px/frame, left/right - was 2, slowed to 1 per direct instruction
; ("自機移動速度が速い気がするんで速度落として"), then asked for 1.5
; ("速度1.5に出来ないか") - alternates 1,2,1,2,... (gated by TICK
; bit0, same trick as the vertical climb easing) since there's no
; fractional pixel; averages to 1.5px/frame over any 2-frame window.
TANK_SPEED_LO EQU 1
TANK_CLIMB_SPEED EQU 1     ; px/step, gated to every OTHER frame (see UPDATE_TERRAIN_COLLISION) -
                           ; 0.5px/frame effective, matching the terrain's own ~16-frame climb pace,
                           ; used only while the tank is standing still (TANK_DX=0)
; px/frame (no gate), used instead of TANK_CLIMB_SPEED while the tank
; is actively steering (TANK_DX!=0) - see UPDATE_TERRAIN_COLLISION.
; Swept 2/3/4/5/6/8 holding the stick right through the whole track and
; measured the worst-case lag behind TANK_TIER_Y_TABLE's target at
; each: 6/5/4/3/2/0px. 8 fully eliminated the lag ("食い込みはなく
; なった") but closes a full 8px gap in 1 frame, reading as an instant
; snap instead of a climb; 6 (worst-case lag 2px) still completed a
; climb in as few as 2 frames, which read the same way moving forward
; - "前移動登りで8px登りになったな". Settled on 2 (same value the
; very first easing attempt used, back when it was praised as "smooth
; for one cell" before terrain-pace-matching became the goal) -
; worst-case lag 6px, but spread over 4-5 frames, closer in feel to
; the stationary pace above; the Gap art offset below also means that
; 6px of lag no longer reads as visibly sinking the way it used to.
TANK_CLIMB_SPEED_MOVING EQU 2
TANK_CLIMB_CATCHUP_SPEED EQU 8  ; px/frame (no gate) once TANK_CLIMB_CATCHUP_THRESHOLD behind - see UPDATE_TERRAIN_COLLISION
; a normal single-tier transition always starts at diff=8 (the full
; TANK_TIER_Y_TABLE step) - a threshold of 5 (briefly tried) meant
; EVERY tier change immediately qualified for the fast catch-up path,
; turning every climb back into an instant 8px snap ("また8px上り
; 下りに戻ってるな") instead of only genuine multi-tier backlogs.
; Threshold must stay > 8 for the smooth slow pace to ever run at all.
TANK_CLIMB_CATCHUP_THRESHOLD EQU 9  ; px
JUMP_PEAK     EQU 24       ; px
JUMP_FRAMES   EQU 49       ; JUMP_OFFSET_TABLE length (0-24 rise, 23-0 fall)
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

; ---------- shots: BG (name-table) characters, not sprites - any     ----------
; ---------- number can share a scanline with the tank with no       ----------
; ---------- "4 sprites per line" flicker (same reasoning as the      ----------
; ---------- player's own shots in src/CYBER SHMUP.asm). The tank     ----------
; ---------- sits right at the terrain's own row19 (TANK_Y_BASE=156,  ----------
; ---------- row19 spans y152-159), unlike that game's ship which     ----------
; ---------- never reaches its own ground scroller - so a shot fired  ----------
; ---------- from here really can be sitting on top of two DIFFERENT  ----------
; ---------- backgrounds: open sky above row19, or the "rock" tier    ----------
; ---------- (row19's own static flat top, or rows 20-23's scrolling  ----------
; ---------- terrain) - and erasing/drawing needs to put back the      ----------
; ---------- right one. terrain_gen.py's own color table only ever    ----------
; ---------- uses 2 solid colors total: SKY_COLOR for the permanent    ----------
; ---------- open sky, and ONE uniform ROCK_COLOR shared by literally  ----------
; ---------- every terrain code in the scrolling band (flat/slope/     ----------
; ---------- climb/still-blank alike - see that file's own comment on  ----------
; ---------- id0/BLANK) - so "row>=BULLET_ROCK_ROW_MIN" is exactly     ----------
; ---------- (not approximately) the right test for "rock-colored",    ----------
; ---------- regardless of which exact terrain tile is really there.   ----------
; ---------- Only row19 itself needs an explicit erase write (it's     ----------
; ---------- static, filled once at INIT, never touched again);        ----------
; ---------- rows 20-23 get fully redrawn from NAMEBUF every frame      ----------
; ---------- BEFORE the bullet update runs (see MAINLOOP), so erasing   ----------
; ---------- a bullet there is a no-op - skipped entirely, see          ----------
; ---------- UPDATE_ONE_BULLET below.                                   ----------
BULLET_ROCK_ROW_MIN EQU 19      ; first row where the "rock" bg applies (19-23)
BULLET_MAXCOL     EQU 31        ; last valid name-table column (0-31)
BULLET_MUZZLE_DX  EQU 24        ; spawn column offset from TANK_X (muzzle, right side of the tank)
SKY_BLANK_CODE    EQU 0         ; TERRAIN_BLANK_ROW's code - the permanent open-sky tile
; TERRAIN_PATTERN_COUNT (generated by terrain_gen.py, defined in the
; appended tables) is row19's own "flat rock top" tile code - reused
; here as the "restore rock" erase code, same tile row19 was filled
; with at INIT.

; Bullet BG pattern codes: each bullet's art needs one code per
; background color group it can appear over (SCREEN1 colors are fixed
; per 8-code group, not per screen position - see bullet_gen.py's own
; comment). BulletF and BulletU share the same fg color again (both
; black, per direct instruction - briefly split into 2 separate color
; groups each when only BulletF was black), so they go back to
; sharing one pair of groups, split only by background. Placed at
; codes 88-103 (groups 11-12), well past every real terrain code
; (0-87, groups 0-10 - see terrain_gen.py's STEADY_BASE/BLEND_BASE) so
; nothing else ever references them.
BULLETF_SKY_CODE  EQU 88
BULLETU_SKY_CODE  EQU 89
BULLETF_ROCK_CODE EQU 96
BULLETU_ROCK_CODE EQU 97
; color table (VRAM 2000h+group, 1 byte/group, hi nibble=fg/lo=bg -
; see terrain_gen.py's own SKY_COLOR/ROCK_COLOR): group11 (codes
; 88-95) = fg1 black/bg5 light blue, matching the sky's own bg5;
; group12 (codes 96-103) = fg1 black/bg10 dark yellow, matching the
; rock tier's own bg10 (terrain_gen.py's ROCK_COLOR=0x8A) - both
; groups patched over terrain_gen.py's generic per-group defaults
; (unused by any real terrain code) rather than by changing that
; shared module.
BULLET_SKY_COLORADDR  EQU 200Bh
BULLET_ROCK_COLORADDR EQU 200Ch
BULLET_SKY_COLORBYTE  EQU 015h
BULLET_ROCK_COLORBYTE EQU 01Ah

JOY_TRIGA     EQU 0F22Bh
PREV_TRIGA    EQU 0F22Ch
; 3 shot slots, 6 bytes each: +0 ACT, +1 TYPE(0=F straight,1=U
; diagonal), +2 COL, +3 ROW, +4 ADDR_LO, +5 ADDR_HI (name-table row
; base address, from BULLET_ROWADDR_LO/HI) - same pool-of-3 design as
; BULLET0/1/2 in src/CYBER SHMUP.asm ("Stage1と同様に制限数画面内3発").
BULLET0_ACT   EQU 0F22Dh
BULLET1_ACT   EQU 0F233h
BULLET2_ACT   EQU 0F239h
BULLET_TEMP_BYTE EQU 0F23Fh

; ---------- terrain collision: ground-height following + slope       ----------
; ---------- (Rock225) detection - see UPDATE_TERRAIN_COLLISION below. ----------
; probe column offset from TANK_X - was 24 (near the tank's very front
; edge, made the tank snap to a new tier before the marker had
; scrolled under its own visual body - reported as floating), then 16
; (1 cell back). Still switching too early, so pulled back another 4px
; per direct instruction ("もっとGapスプライト切り替えを遅らせるべき
; あと4Px遅れるようにしてくれ").
TANK_FOOT_DX  EQU 12
TANK_GROUND_Y EQU 0F240h    ; current ground-follow baseline Y (tier-dependent) - UPDATE_JUMP
                            ; subtracts JUMP_Y_OFFSET from this instead of the fixed TANK_Y_BASE
TANK_ON_SLOPE EQU 0F241h    ; 1 while straddling a Rock225/Rock225D marker -> Gap pose
TANK_TIER     EQU 0F242h    ; 0-3, current ground tier (screen row 23-TANK_TIER) under the tank
TANK_ROWPTR   EQU 0F243h    ; word: IDCACHE_Tn base address for the surface tier's row
TANK_COL_R    EQU 0F245h    ; probe column (name-table column, 0-31)
TANK_SLOPE_HOLD EQU 0F247h  ; frames left before TANK_ON_SLOPE actually drops to 0 - see UPDATE_TERRAIN_COLLISION
TANK_DRAW_Y   EQU 0F248h    ; TANK_Y_CUR, -TANK_GAP_ART_OFFSET while a Gap pose is showing - see UPDATE_TANK_SPRITES
; TankFGap/TankUGap's own art extends 3 rows further down within their
; fixed 32x32 canvas than TankF/TankUp does (lowest non-blank sprite
; row 29 vs 26, measured directly from the source JSON) - a fixed
; offset baked into the art itself, not the dynamic ground-Y logic, so
; drawing a Gap pose at the exact same TANK_Y_CUR as a Normal pose
; always put its own wheels 3px lower on screen than Normal's, i.e.
; visibly sunk into the ground even once TANK_Y_CUR itself is fully
; settled at the correct tier - "静止でもGapにまだ食い込んでた". (An
; earlier +4 offset tried here made this worse, not better - it pushed
; further in the same already-too-low direction; reverted for looking
; like a jarring dip. This is -3, the other direction, sized from the
; actual art discrepancy rather than guessed.)
TANK_GAP_ART_OFFSET EQU 3

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

    ; bullet BG patterns: each loaded twice, once per background color
    ; group it can appear over (see BULLETF_SKY_CODE etc. above).
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN : LD DE,BULLETU_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN : LD DE,BULLETU_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM

    ; bullet color groups: patch over terrain_gen.py's generic per-
    ; group defaults for the 4 groups the bullet codes above live in -
    ; see BULLET_SKY_COLORADDR/BULLET_ROCK_COLORADDR above.
    LD A,BULLET_SKY_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_SKY_COLORADDR : LD BC,1 : CALL LDIRVM
    LD A,BULLET_ROCK_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_ROCK_COLORADDR : LD BC,1 : CALL LDIRVM

    ; checkpoint 6: tank + bullet patterns loaded
    LD B,6 : LD C,7 : CALL WRTVDP

    ; --- explicitly clear the WHOLE sprite attribute table (32       ---
    ; --- entries x 4 bytes = 128 bytes) to a fully hidden, known      ---
    ; --- state (Y=209/0D1h - past the Y=208 stop-sentinel - X/pattern/---
    ; --- color=0), matching src/CYBER SHMUP.asm's own INIT_SPRATR_CLR ---
    ; --- exactly (raw OUT, DI/EI + 8 NOPs around every single byte -  ---
    ; --- LDIRVM has no such interrupt-safety margin, matching this   ---
    ; --- file's own UPDATE_TANK_SPRITES fix). The previous version of ---
    ; --- this only hid slot 4 (aliasing PAT_TANKF's own TL quadrant   ---
    ; --- via the emulator's all-zero VRAM default, so only ONE extra  ---
    ; --- black blob ever showed up in emulator testing) and used      ---
    ; --- LDIRVM for even that one write - slots 5-31 were never       ---
    ; --- touched at all, left holding whatever real hardware's        ---
    ; --- genuinely unpredictable power-on VRAM happened to contain,    ---
    ; --- which is exactly the stray white blob reported on real       ---
    ; --- hardware that the emulator could never reproduce.
    DI
    LD A,0 : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD B,32
    EI
INIT_SPRATR_CLR:
    DI
    LD A,209 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    DJNZ INIT_SPRATR_CLR

    ; tank state: centered start, grounded, facing/aiming neutral
    LD A,TANK_X_INIT : LD (TANK_X),A
    LD A,TANK_Y_BASE : LD (TANK_Y_CUR),A
    LD A,TANK_Y_BASE : LD (TANK_GROUND_Y),A
    XOR A
    LD (TANK_DX),A
    LD (TANK_AIMUP),A
    LD (TANK_ON_SLOPE),A
    LD (TANK_SLOPE_HOLD),A
    LD (PREV_TRIGB),A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
    LD (JUMP_Y_OFFSET),A
    LD A,PAT_TANKF : LD (CUR_POSE_PAT),A
    XOR A
    LD (PREV_TRIGA),A
    LD (BULLET0_ACT),A
    LD (BULLET1_ACT),A
    LD (BULLET2_ACT),A

    ; overwrites slots 0-3 (the tank's own) with real data; slots 4-31
    ; stay hidden from the full clear above.
    CALL UPDATE_TANK_SPRITES

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
    CALL UPDATE_TERRAIN_COLLISION
    CALL UPDATE_JUMP
    CALL UPDATE_POSE
    CALL UPDATE_TANK_SPRITES
    ; bullets advance before a new one can spawn, so a shot fired this
    ; frame gets drawn once (at the muzzle) instead of being advanced
    ; a 2nd time by this same frame's UPDATE_BULLETS sweep.
    CALL UPDATE_BULLETS
    CALL UPDATE_SHOT

    JP MAINLOOP

; ---------- input ----------
; port1 stick -> JOY_DIR (0-8 compass, 0=none,1=up,2=upright,3=right,
; 4=downright,5=down,6=downleft,7=left,8=upleft); port1 trigger B
; (jump) -> JOY_TRIGB (0/FFh); port1 trigger A (shot) -> JOY_TRIGA
; (0/FFh).
READ_INPUT:
    LD A,1 : CALL GTSTCK
    LD (JOY_DIR),A
    LD A,3 : CALL GTTRIG
    LD (JOY_TRIGB),A
    LD A,1 : CALL GTTRIG
    LD (JOY_TRIGA),A
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
    LD A,(TICK) : AND 1 : LD B,A
    LD A,TANK_SPEED_LO : ADD A,B   ; step = 1 or 2, alternating
    LD C,A
    LD A,(TANK_X) : ADD A,C
    LD (TANK_X),A
    RET
UTX_DO_LEFT:
    LD A,(TICK) : AND 1 : LD B,A
    LD A,TANK_SPEED_LO : ADD A,B   ; step = 1 or 2, alternating
    LD C,A
    LD A,(TANK_X)
    CP C
    RET C                          ; X < step - don't move (avoid underflow)
    SUB C
    LD (TANK_X),A
    RET

; ---------- terrain collision: ground-height following + slope check ----------
; 2 probe name-table columns near the tank's right/front edge:
; TANK_COL_R (directly under, "下") finds the ground tier by scanning
; IDCACHE_T0-T3 top-to-bottom for the first non-BLANK id at that
; column - "常にRockに設置" (always rest on whichever tier has
; content, be it plain rock or a slope-transition cell - both are
; solid ground).
;
; Slope check ("Gapを調べる", to flag TANK_ON_SLOPE): checking a probe
; 1 column BEHIND TANK_COL_R (as an earlier version of this did) meant
; the Gap-pose signal always lagged the Y-tier-snap signal by exactly
; 1 column's scroll time, since it was reading what TANK_COL_R itself
; had already scrolled past - "判定位置の問題...登ってからでは遅い".
; Reworked to check relative to TANK_COL_R itself instead: (a) is
; TANK_COL_R's OWN cell (at the tier just found) a Rock225/Rock225D id
; (3-6, vs. plain ROCK_L/ROCK_R's 1-2) - i.e. is the front foot
; currently straddling the marker - or (b) is the cell diagonally
; up-right from it (1 row up - the tier ABOVE the one just found,
; where a climb marker actually lives, since R225 sits in the row
; "newly becoming rock" - and 1 column ahead of TANK_COL_R) a marker -
; i.e. is one about to be reached - "今の前の判定の斜め右上と同一の
; Gapセルなら". Either one holds Gap.
;
; TANK_ON_SLOPE also has 2 frames of hold after the last raw "yes"
; reading (TANK_SLOPE_HOLD) before it actually drops to 0 - the rapid-
; climb section chains transitions with no flat run between them, and
; a single-frame gap of plain rock between 2 chained Rock225 markers
; would otherwise flicker the pose back to Normal for 1 frame -
; "Gap判定が2連続なら(登ってもGap)またRockでないならノーマルに
; 切り替えずGapスプライトのままに".
UPDATE_TERRAIN_COLLISION:
    LD A,(TANK_X) : ADD A,TANK_FOOT_DX
    SRL A
    SRL A
    SRL A
    LD (TANK_COL_R),A

    ; find the surface tier: first non-BLANK row, IDCACHE_T0 (highest)
    ; downward - row-index3 (screen row23) is guaranteed non-BLANK
    ; across the whole track (terrain_gen.py's build_track() always
    ; keeps ground_i(tier)<=3), so no explicit check needed for it.
    LD A,(TANK_COL_R) : LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTC_TIER0
    LD A,(TANK_COL_R) : LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTC_TIER1
    LD A,(TANK_COL_R) : LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTC_TIER2
    JR UTC_TIER3
UTC_TIER0:
    XOR A : LD (TANK_TIER),A
    LD HL,IDCACHE_T0 : LD (TANK_ROWPTR),HL
    JR UTC_TIER_DONE
UTC_TIER1:
    LD A,1 : LD (TANK_TIER),A
    LD HL,IDCACHE_T1 : LD (TANK_ROWPTR),HL
    JR UTC_TIER_DONE
UTC_TIER2:
    LD A,2 : LD (TANK_TIER),A
    LD HL,IDCACHE_T2 : LD (TANK_ROWPTR),HL
    JR UTC_TIER_DONE
UTC_TIER3:
    LD A,3 : LD (TANK_TIER),A
    LD HL,IDCACHE_T3 : LD (TANK_ROWPTR),HL
UTC_TIER_DONE:

    ; move TANK_GROUND_Y toward the tier's target Y at TANK_CLIMB_SPEED
    ; instead of snapping straight there - snapping the full 8px in
    ; one frame looked like a jolt/jitter at every tier change, per
    ; direct instruction ("登り降り時に一気に8px移動してるんでガタ
    ; ついてる...滑らかに繋げて"). A flat 2px/frame finished each climb
    ; in 4 frames - much faster than the terrain itself actually
    ; scrolls a transition by (measured ~16 frames between chained
    ; tier changes with the tank stationary), so the climb looked
    ; detached from the terrain's own motion and, chained back-to-
    ; back, visibly paused waiting for the next tier - "連続Gapだと
    ; 一瞬止まってる...地形に沿って移動じゃなく地形に入ったら自分で
    ; 8pxのぼってる...地形の移動とマッチしてない". Gated to every
    ; other frame (TICK bit0) so 1px/step averages 0.5px/frame,
    ; matching that ~16-frame pace.
    ;
    ; That pace was measured with the tank standing still, though -
    ; TANK_COL_R (the probe column) also moves when the tank itself
    ; steers left/right, so moving toward oncoming terrain lets the
    ; probe advance through tiers faster than the stationary baseline
    ; (especially through the rapid-chain section, where consecutive
    ; markers are close together) - at the slow pace alone,
    ; TANK_GROUND_Y then falls behind by more than one tier and the
    ; tank visibly sinks into the rock for a stretch - "左右移動が
    ; 加わるとGapに突っ込んでる...登ってはいるが地形にめり込んでる".
    ; Once TANK_CLIMB_CATCHUP_THRESHOLD behind, switch to catching up
    ; at TANK_CLIMB_CATCHUP_SPEED every frame (no gate) instead - once
    ; back under the threshold, the smooth slow pace above takes back
    ; over for the final approach. Still sinking in slightly with the
    ; original threshold(9)/speed(4) - "まだ少しだがめり込んでる" -
    ; so the threshold is now tighter (5) and the catch-up itself
    ; faster (8, enough to close any realistic single-frame gap in one
    ; step) to stamp out the residual lag.
    LD A,(TANK_TIER) : LD E,A : LD D,0
    LD HL,TANK_TIER_Y_TABLE : ADD HL,DE
    LD A,(HL) : LD B,A            ; B = target Y
    LD A,(TANK_GROUND_Y)
    LD C,A                        ; C = current (smoothed) Y
    CP B
    JR Z,UTC_GROUND_Y_DONE
    JR C,UTC_GROUND_Y_DIFF_BELOW
    LD A,C : SUB B                ; diff = current-target (current>target)
    JR UTC_GROUND_Y_DIFF_READY
UTC_GROUND_Y_DIFF_BELOW:
    LD A,B : SUB C                ; diff = target-current (current<target)
UTC_GROUND_Y_DIFF_READY:
    CP TANK_CLIMB_CATCHUP_THRESHOLD
    JR C,UTC_GROUND_Y_BELOW_THRESHOLD  ; diff below threshold: not a multi-tier backlog
    LD D,TANK_CLIMB_CATCHUP_SPEED
    JR UTC_GROUND_Y_STEP
UTC_GROUND_Y_BELOW_THRESHOLD:
    ; while actively steering, use the faster ungated pace instead of
    ; the terrain-matched slow one - TANK_COL_R moves with TANK_X, so
    ; even a single ordinary climb's own diff=8 start can grow before
    ; the slow pace closes it, reading as sinking into the rock -
    ; "まだ左右移動で地形めり込んでるな...速度1.5の影響っぽい". The
    ; slow pace's terrain-matched feel was validated with the tank
    ; standing still (see above); once moving, the tank's own motion
    ; is already the dominant visual cue, so tracking the ground
    ; closely matters more here than matching the terrain's scroll.
    LD A,(TANK_DX)
    OR A
    JR NZ,UTC_GROUND_Y_MOVING
    LD A,(TICK) : AND 1
    JR NZ,UTC_GROUND_Y_DONE
    LD D,TANK_CLIMB_SPEED
    JR UTC_GROUND_Y_STEP
UTC_GROUND_Y_MOVING:
    LD D,TANK_CLIMB_SPEED_MOVING
UTC_GROUND_Y_STEP:
    LD A,C
    CP B
    JR C,UTC_GROUND_Y_RISE
    ; current > target (numerically lower on screen, i.e. climbing) -
    ; step down toward it, clamping so it can't undershoot past it
    SUB D
    CP B
    JR NC,UTC_GROUND_Y_SET
    LD A,B
    JR UTC_GROUND_Y_SET
UTC_GROUND_Y_RISE:
    ; current < target (descending) - step up toward it, clamping so
    ; it can't overshoot past it
    LD A,C : ADD A,D
    CP B
    JR C,UTC_GROUND_Y_SET
    LD A,B
UTC_GROUND_Y_SET:
    LD (TANK_GROUND_Y),A
UTC_GROUND_Y_DONE:

    ; slope check (a): TANK_COL_R's own cell at the tier just found
    LD A,(TANK_COL_R) : LD E,A : LD D,0
    LD HL,(TANK_ROWPTR) : ADD HL,DE
    LD A,(HL)
    CP 3
    JR NC,UTC_SLOPE_RAW_YES

    ; slope check (b): 1 row up from the tier just found (skip if
    ; TANK_TIER is already 0 - the topmost row, nothing above it),
    ; 1 column ahead of TANK_COL_R. IDCACHE_T0..T3 are evenly spaced
    ; 48 bytes apart, so "1 row up" is simply TANK_ROWPTR-48.
    LD A,(TANK_TIER)
    OR A
    JR Z,UTC_SLOPE_RAW_NO
    LD HL,(TANK_ROWPTR)
    LD DE,-48
    ADD HL,DE
    LD A,(TANK_COL_R) : INC A : LD E,A : LD D,0
    ADD HL,DE
    LD A,(HL)
    CP 3
    JR C,UTC_SLOPE_RAW_NO
UTC_SLOPE_RAW_YES:
    ; raw slope detected this frame - (re)arm the 2-frame hold
    LD A,2 : LD (TANK_SLOPE_HOLD),A
    LD A,1 : LD (TANK_ON_SLOPE),A
    RET
UTC_SLOPE_RAW_NO:
    LD A,(TANK_SLOPE_HOLD)
    OR A
    JR Z,UTC_SLOPE_EXPIRED
    DEC A : LD (TANK_SLOPE_HOLD),A
    LD A,1 : LD (TANK_ON_SLOPE),A
    RET
UTC_SLOPE_EXPIRED:
    XOR A : LD (TANK_ON_SLOPE),A
    RET

; ---------- jump (B button, edge-triggered, 24px half-sine arc) ----------
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
    CP JUMP_FRAMES
    JR C,UJ_STILL_JUMPING
    XOR A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
UJ_STILL_JUMPING:
UJ_DONE:
    LD A,(JUMP_FRAME) : LD E,A : LD D,0
    LD HL,JUMP_OFFSET_TABLE : ADD HL,DE
    LD A,(HL) : LD (JUMP_Y_OFFSET),A

    LD A,(TANK_GROUND_Y)
    LD HL,JUMP_Y_OFFSET
    SUB (HL)
    LD (TANK_Y_CUR),A
    RET

; ---------- pose: ground/air x neutral/aim-up ----------
; airborne OR straddling a climb/descend (Rock225/Rock225D) marker both
; use the Gap pose - "Rock225に接触したらGapスプライトに切り替えて
; 登るように", and (no descend art yet) "Gapスプライト流用" for the
; descend case too, both handled the same way since TANK_ON_SLOPE
; doesn't distinguish which (see UPDATE_TERRAIN_COLLISION).
UPDATE_POSE:
    LD A,(JUMP_ACTIVE)
    OR A
    JR NZ,UP_GAP
    LD A,(TANK_ON_SLOPE)
    OR A
    JR Z,UP_GROUND
UP_GAP:
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
    LD A,(CUR_POSE_PAT)
    CP PAT_TANKFGAP
    JR Z,UTS_GAP_OFFSET
    CP PAT_TANKUGAP
    JR Z,UTS_GAP_OFFSET
    LD A,(TANK_Y_CUR)
    JR UTS_DRAW_Y_SET
UTS_GAP_OFFSET:
    LD A,(TANK_Y_CUR) : SUB TANK_GAP_ART_OFFSET
UTS_DRAW_Y_SET:
    LD (TANK_DRAW_Y),A

    LD IX,SPRITE_ATTRS
    LD A,(TANK_DRAW_Y) : LD (IX+0),A
    LD A,(TANK_X)     : LD (IX+1),A
    LD A,(CUR_POSE_PAT) : LD (IX+2),A
    LD A,TANK_COLOR_TL : LD (IX+3),A

    LD A,(TANK_DRAW_Y) : LD (IX+4),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+5),A
    LD A,(CUR_POSE_PAT) : ADD A,4 : LD (IX+6),A
    LD A,TANK_COLOR_TR : LD (IX+7),A

    LD A,(TANK_DRAW_Y) : ADD A,16 : LD (IX+8),A
    LD A,(TANK_X)     : LD (IX+9),A
    LD A,(CUR_POSE_PAT) : ADD A,8 : LD (IX+10),A
    LD A,TANK_COLOR_BL : LD (IX+11),A

    LD A,(TANK_DRAW_Y) : ADD A,16 : LD (IX+12),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+13),A
    LD A,(CUR_POSE_PAT) : ADD A,12 : LD (IX+14),A
    LD A,TANK_COLOR_BR : LD (IX+15),A

    ; --- write to VRAM via raw NOP-padded OUT (address set once, then ---
    ; --- 16 consecutive auto-incrementing OUT (98h) writes), matching ---
    ; --- src/CYBER SHMUP.asm's own per-frame sprite update exactly    ---
    ; --- (DI-wrapped there too) instead of LDIRVM. LDIRVM's BIOS      ---
    ; --- internals have no such interrupt-safety margin, and this     ---
    ; --- write runs with EI active every single frame (no per-frame   ---
    ; --- HALT - see MAINLOOP), so an H.TIMI interrupt landing mid-copy---
    ; --- could corrupt the sprite table. Real-hardware-reported       ---
    ; --- garbage that z80emu.py can never reproduce (no interrupts at ---
    ; --- all), so this can't be verified by emulator stepping - only  ---
    ; --- that the bytes it writes are correct (see verify script).
    DI
    LD A,0 : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,SPRITE_ATTRS
    LD B,16
UTS_OUT_LOOP:
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL
    DJNZ UTS_OUT_LOOP
    EI
    RET

; ---------- shots: fire (A button, edge-triggered) ----------
UPDATE_SHOT:
    LD A,(JOY_TRIGA)
    LD HL,PREV_TRIGA
    CP (HL)
    JR Z,US_NO_NEW_PRESS
    OR A
    JR Z,US_NO_NEW_PRESS
    CALL TRY_SPAWN_BULLET
US_NO_NEW_PRESS:
    LD A,(JOY_TRIGA) : LD (PREV_TRIGA),A
    RET

; claims the first inactive slot (BULLET0, else 1, else 2) and spawns
; a shot there; if all 3 are already active, the new shot is dropped
; (screen limit of 3, matching src/CYBER SHMUP.asm's own BULLET0/1/2
; pool - "Stage1と同様に制限数画面内3発").
TRY_SPAWN_BULLET:
    LD A,(BULLET0_ACT)
    OR A
    JR NZ,TSB_TRY1
    LD IX,BULLET0_ACT
    JR TSB_DO_SPAWN
TSB_TRY1:
    LD A,(BULLET1_ACT)
    OR A
    JR NZ,TSB_TRY2
    LD IX,BULLET1_ACT
    JR TSB_DO_SPAWN
TSB_TRY2:
    LD A,(BULLET2_ACT)
    OR A
    RET NZ
    LD IX,BULLET2_ACT
TSB_DO_SPAWN:
    LD A,1 : LD (IX+0),A
    LD A,(TANK_AIMUP) : LD (IX+1),A

    ; ROW = TANK_Y_CUR >> 3 (name-table row), +1 more for a straight/F
    ; shot only (per direct instruction "BulletFのセル表示を1セル下に") -
    ; U (diagonal) keeps the un-shifted muzzle row. Grounded F therefore
    ; lands 1 row past BULLET_ROCK_ROW_MIN(19), inside the scrolling
    ; band - fine, see the comment on BULLET_ROCK_ROW_MIN above for why
    ; that's still handled correctly.
    LD A,(TANK_Y_CUR)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD A,(IX+1)
    OR A
    JR NZ,TSB_ROW_SET
    INC B
TSB_ROW_SET:
    LD A,B
    LD (IX+3),A

    ; COL = (TANK_X + BULLET_MUZZLE_DX) >> 3, clamped to the last column
    LD A,(TANK_X) : ADD A,BULLET_MUZZLE_DX
    SRL A
    SRL A
    SRL A
    CP BULLET_MAXCOL+1
    JR C,TSB_COL_OK
    LD A,BULLET_MAXCOL
TSB_COL_OK:
    LD (IX+2),A

    LD A,(IX+3) : LD E,A : LD D,0
    LD HL,BULLET_ROWADDR_LO : ADD HL,DE : LD A,(HL) : LD (IX+4),A
    LD HL,BULLET_ROWADDR_HI : ADD HL,DE : LD A,(HL) : LD (IX+5),A

    CALL DRAW_BULLET_CELL
    RET

; ---------- shots: advance all 3 slots 1 column/frame ----------
UPDATE_BULLETS:
    LD IX,BULLET0_ACT
    CALL UPDATE_ONE_BULLET
    LD IX,BULLET1_ACT
    CALL UPDATE_ONE_BULLET
    LD IX,BULLET2_ACT
    CALL UPDATE_ONE_BULLET
    RET

; IX = slot base (+0 ACT,+1 TYPE,+2 COL,+3 ROW,+4/+5 ADDR). Erases the
; current cell (restoring sky or row19's rock top, whichever this
; bullet is actually over), advances 1 column (and, for a diagonal/U
; shot, 1 row up too), then redraws at the new position - or
; deactivates if it just left the name table's top or right edge.
UPDATE_ONE_BULLET:
    LD A,(IX+0)
    OR A
    RET Z

    ; --- erase: row<19 sky, row==19 explicit rock restore (row19 is    ---
    ; --- static, only ever written at INIT), row>19 skip entirely -    ---
    ; --- rows 20-23 already got fully redrawn from NAMEBUF earlier      ---
    ; --- this same MAINLOOP iteration (see the comment on               ---
    ; --- BULLET_ROCK_ROW_MIN above), so there's nothing to restore.     ---
    LD A,(IX+3)
    CP BULLET_ROCK_ROW_MIN
    JR NC,UOB_ERASE_ROCKBAND
    LD A,SKY_BLANK_CODE
    JR UOB_ERASE_WRITE
UOB_ERASE_ROCKBAND:
    JR NZ,UOB_ERASE_SKIP
    LD A,TERRAIN_PATTERN_COUNT
UOB_ERASE_WRITE:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    CALL WRITE_BULLET_BYTE_HL
UOB_ERASE_SKIP:

    ; --- advance: column always, row too (upward) for a diagonal/U shot ---
    LD A,(IX+2) : INC A : LD (IX+2),A

    LD A,(IX+1)
    OR A
    JR Z,UOB_ADV_DONE
    LD A,(IX+3)
    OR A
    JR Z,UOB_DEACTIVATE   ; already at row0 - one more "up" would leave the screen
    DEC A
    LD (IX+3),A
UOB_ADV_DONE:

    LD A,(IX+2)
    CP BULLET_MAXCOL+1
    JR NC,UOB_DEACTIVATE

    ; recompute ADDR from the (possibly new) row
    LD A,(IX+3) : LD E,A : LD D,0
    LD HL,BULLET_ROWADDR_LO : ADD HL,DE : LD A,(HL) : LD (IX+4),A
    LD HL,BULLET_ROWADDR_HI : ADD HL,DE : LD A,(HL) : LD (IX+5),A

    CALL DRAW_BULLET_CELL
    RET
UOB_DEACTIVATE:
    XOR A : LD (IX+0),A
    RET

; IX = slot base. Picks the pattern code for (TYPE x background-under-
; current-row) and writes it at ADDR+COL.
DRAW_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_ROW_MIN
    JR NC,DBC_ROCK
    LD A,(IX+1)
    OR A
    JR NZ,DBC_SKY_U
    LD A,BULLETF_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_U:
    LD A,BULLETU_SKY_CODE
    JR DBC_CODE_SET
DBC_ROCK:
    LD A,(IX+1)
    OR A
    JR NZ,DBC_ROCK_U
    LD A,BULLETF_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_U:
    LD A,BULLETU_ROCK_CODE
DBC_CODE_SET:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL

; writes (BULLET_TEMP_BYTE) to VRAM address HL - raw DI-wrapped OUT
; with 8 NOPs after every byte (same pattern as UPDATE_TANK_SPRITES/
; INIT_SPRATR_CLR above), since this runs every frame with EI active
; (no per-frame HALT - see MAINLOOP) and LDIRVM has no interrupt-
; safety margin for that.
WRITE_BULLET_BYTE_HL:
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(BULLET_TEMP_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
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

; 49 entries (jump frame 0-48): a half-sine arc, offset(t) =
; round(24 * sin(pi*t/48)) - 24px peak at t=24, eased in/out (fast
; launch and landing, brief hang near the peak) instead of the
; earlier triangular (constant 1px/frame) ramp, per direct
; instruction ("サインジャンプ"). JUMP_FRAMES above must match this
; table's length.
JUMP_OFFSET_TABLE:
    DB 0,2,3,5,6,8,9,11,12,13,15,16,17,18,19,20,21,22,22,23,23,24,24,24,24,24,24,24,23,23,22,22,21,20,19,18,17,16,15,13,12,11,9,8,6,5,3,2,0

; name-table row base address (1800h + row*32), rows 0-23 - shared by
; every bullet slot to turn a ROW byte back into a VRAM address
; without a multiply.
BULLET_ROWADDR_LO:
    DB 0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224,0,32,64,96,128,160,192,224
BULLET_ROWADDR_HI:
    DB 24,24,24,24,24,24,24,24,25,25,25,25,25,25,25,25,26,26,26,26,26,26,26,26

; ground Y indexed by TANK_TIER (the IDCACHE row-index UPDATE_TERRAIN_
; COLLISION found content in, 0=IDCACHE_T0/screen row20 .. 3=IDCACHE_
; T3/screen row23) - NOT the same numbering as terrain_gen.py's own
; generator "tier" (which counts UP while climbing; row-index0 is the
; HIGHEST screen row, so it's the opposite: TANK_TIER=3 is the
; track's starting/lowest ground, reproducing the original fixed
; TANK_Y_BASE(156) exactly - each row-index down means 8px higher.
TANK_TIER_Y_TABLE:
    DB 132,140,148,156

; ===== generated tables (terrain + tank) appended below by build_test.py =====
