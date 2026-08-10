; ============================================================
; CYBER_SUZUKA - multi-rate parallax ground (6-tier road)
; Z80 mnemonic source (sjasmplus-style syntax)
; MSX ROM cartridge, 16KB, page 1 (4000h-7FFFh)
; --- SCREEN 1 (GRAPHIC1 / T32) version ---
;   SCREEN2 -> SCREEN1 conversion notes:
;   - INIGRP(0072h) -> INIT32(006Fh)
;   - Name table base is 1800h in both modes -> VRAM row
;     addresses for the 6 scrolling rows are UNCHANGED.
;   - SCREEN1 has only ONE pattern generator table (0000h,
;     2048 bytes covering char codes 0-255) instead of the
;     3 banked tables of SCREEN2, so PATTERNS is loaded once.
;   - SCREEN1 color is one attribute per 8 CONSECUTIVE
;     character codes (32-entry color table at 2000h),
;     instead of SCREEN2's per-scanline-per-character color.
;     Because every pattern in the original COLORDATA used a
;     single flat color for all 8 scanlines anyway, the 48
;     pattern codes have been renumbered/grouped so each
;     8-code group is monochrome:
;       codes  0- 7 : mountain family   (color A4h)
;       codes  8-31 : diamond/slash/backslash family (C3h)
;       codes 32-47 : wedge family      (color B3h)
;     LUT and PAIRBASE were recomputed for the new numbering;
;     the terrain logic in MAINLOOP is otherwise untouched.
;   - Player ship + shots added (STG-style):
;     ship = 2 sprites side by side (16x8, from the pixel-art
;     screenshot), 8-way joystick move, A button fires up to
;     3 bullets (8 dots/frame, rightward only).
; ============================================================

    ORG 4000h

INIT32  EQU 006Fh
LDIRVM  EQU 005Ch

TICK        EQU 0E000h

; Global game tick: increments once every time the wedge row
; (screen row22, the fastest-scrolling tier - PXCHAR_G8) updates,
; i.e. once every 8 frames. 16-bit so it can run for a long time;
; only its low byte is shown on-screen (3 decimal digits, top-right).
GAME_TICK   EQU 0E4D1h   ; 2 bytes
PXCHAR_G8   EQU 0E001h
PXCHAR_G4   EQU 0E002h
PXCHAR_G2   EQU 0E003h
PXCHAR_G1   EQU 0E004h
PHASE_G8    EQU 0E005h
PHASE_G4    EQU 0E006h
PHASE_G2    EQU 0E007h
PHASE_G1    EQU 0E008h
ROWPHASE    EQU 0E009h
NEXTID      EQU 0E00Bh

; Per-row cache of ROWDATAn[PXCHARgroup..PXCHARgroup+32] already translated
; through LUT (ASCII terrain letter -> 0-5 id). CELL_LOOP_0-5 read straight
; from here instead of re-deriving each id from ROWDATA+LUT every frame;
; REFRESH_IDCACHE_33 repopulates a row's slice only when its group's
; PXCHAR actually advances (every 8/16/32/64 frames - see the PXCHAR_G8/
; G4/G2/G1 gates in MAINLOOP), plus once at INIT to seed frame 1.
; 33 bytes/row (32 cells + 1 lookahead byte for the last cell's "next").
IDCACHE0    EQU 0E00Ch
IDCACHE1    EQU 0E02Dh
IDCACHE2    EQU 0E04Eh
IDCACHE3    EQU 0E06Fh
IDCACHE4    EQU 0E090h
IDCACHE5    EQU 0E0B1h
NAMEBUF     EQU 0E200h
PREVBUF     EQU 0E300h
STACKTOP    EQU 0F380h
BLANKCODE   EQU 48    ; unused pattern code reused as a solid "blue" filler

GTSTCK      EQU 00D5h   ; BIOS: read joystick direction (A=id -> A=0-8)
GTTRIG      EQU 00D8h   ; BIOS: read trigger button (A=id -> A=0/FFh)
WRTVDP      EQU 0047h   ; BIOS: write VDP register (C=reg#, B=data)
RG1SAV      EQU 0F3E0h  ; RAM mirror of VDP register 1

SPRATR      EQU 1B00h   ; sprite attribute table (VRAM, BIOS default for SCREEN1)
SPRPAT      EQU 3800h   ; sprite pattern generator table (VRAM, BIOS default)

PAT_SHIP    EQU 0       ; 16x16 sprite pattern number (32 bytes at SPRPAT+0)
PAT_ACCENT  EQU 16      ; 16x16 accent overlay, drawn at ship_X+8 (32 bytes at SPRPAT+128)

SPR_RED     EQU 08h     ; sprite color: red
SPR_WHITE   EQU 0Fh     ; sprite color: white
SPR_TERM_Y  EQU 208     ; special Y value: stop sprite processing here

PLAYER_SPEED EQU 2     ; was raised to 4 to compensate for the (now-removed)
                        ; per-frame HALT slowdown; back to its original value
PLAYER_MINX  EQU 0
PLAYER_MAXX  EQU 240    ; 256-16 (ship is 16 dots wide)
PLAYER_MINY  EQU 8      ; one char row (8px) down, clears row0 score/tick display
PLAYER_MAXY  EQU 176    ; keeps the ship out of local row 5 (wedge, screen
                        ; row 23) only - the very bottom row of the 5-row
                        ; scroller; rows 0-3 (mountain/diamond/slash/
                        ; backslash, screen rows 19-22) are now reachable.
PLAYER_INITX EQU 16
PLAYER_INITY EQU 64

; --- shots are background characters, not sprites, so any number ---
; --- can be on the same scanline as the ship with no "4 sprites  ---
; --- per line" flicker. 8x8, single cell: since PLAYER_SPEED=2,   ---
; --- PLAYERY mod 8 only ever takes the even values 0,2,4,6, so the---
; --- shape (2 rows tall) is placed starting at row=phase - this   ---
; --- spans a 6-dot range (0..6) and always fits inside the 8-row  ---
; --- cell with no clipping.                                       ---
; --- Two color variants are needed because the shot may fly over  ---
; --- the sky (blue bg) or over the diamond/slash terrain (light   ---
; --- green bg, screen rows 19-21): codes 56-63 = blue variant,     ---
; --- codes 64-71 = green variant (both phase-indexed 0-7, only the ---
; --- even slots hold real content).                                ---
BULLET_PAT_BLUE  EQU 56
BULLET_PAT_GREEN EQU 64
BULLET_MAXCOL EQU 31    ; last valid column (32-wide name table, 0-31)
GROUND_ROW0   EQU 19    ; first screen row of the 5-row ground scroller
                        ; (was 6 rows/GROUND_ROW0=18; TIER2_DIAMOND's own
                        ; processing was removed to cut per-frame VDP/CPU
                        ; load, and TIER1_MOUNTAIN now draws one row lower,
                        ; at screen row19, to fill the gap)

FIRE_COOLDOWN EQU 0E3D2h ; frames to wait before another shot can spawn
FIRE_COOLDOWN_LEN EQU 1  ; "1 cycle" gap between shots (see fire logic)
TEMP_ERASE_BYTE EQU 0E3D6h ; scratch: byte to restore when erasing a shot
M_TMP EQU 0E3D7h ; scratch: PLAYERY mod 8 during spawn calc

PLAYERX      EQU 0E3C0h
PLAYERY      EQU 0E3C1h
; each bullet: ACT(active flag), ADDR(2 bytes: VRAM address of its
; row's column0, low byte then high byte so LD HL,(ADDR) loads
; both), COL(0-31, current column), ROW(0-23, fixed at spawn - used
; to know whether to restore ground terrain or sky blank on erase,
; and whether to use the blue or green shot color), PAT (character
; code to draw, fixed at spawn)
BULLET0_ACT  EQU 0E3C2h
BULLET0_ADDR EQU 0E3C3h   ; +0 low, +1 high
BULLET0_COL  EQU 0E3C5h
BULLET0_ROW  EQU 0E3C6h
BULLET0_PAT  EQU 0E3C7h
BULLET1_ACT  EQU 0E3C8h
BULLET1_ADDR EQU 0E3C9h
BULLET1_COL  EQU 0E3CBh
BULLET1_ROW  EQU 0E3CCh
BULLET1_PAT  EQU 0E3CDh
BULLET2_ACT  EQU 0E3CEh
BULLET2_ADDR EQU 0E3CFh
BULLET2_COL  EQU 0E3D1h
BULLET2_ROW  EQU 0E3D3h
BULLET2_PAT  EQU 0E3D4h

; --- enemy: one slow left-moving 16x16 sprite (sprite slot 1). ---
; --- Pattern is a solid diagonal (top-left+bottom-right filled, ---
; --- top-right+bottom-left transparent), gray. It enters from   ---
; --- the right edge, exits off the left edge (or is destroyed   ---
; --- by a shot), then respawns alternating between two fixed Y  ---
; --- positions (16 dots from the top, and 16 dots above the     ---
; --- 5-row ground scroller).                                    ---
ENEMY_Y       EQU 0E3D9h   ; shared Y of the whole formation
ENEMY_X       EQU 0E3DAh   ; shared group X, used once the complex formation is fully assembled (drift/exit)

; Each unit is a 16x16 sprite showing a diagonal pair of asterisks
; (top-left + bottom-right, each its own 8x8 "enemy"); bottom-left
; and top-right are always blank. Each asterisk (quadrant) is
; tracked/killed independently (E_TOP/E_BOT, 1=alive/0=dead) - a
; bullet passes through a quadrant that's already dead. Migrated onto
; the unified ENEMY_POOL as BEHAVIOR_SIMPLE_DRIFT_DODGE; see
; SIMPLE_PATTERN_NUMS/EBSD_UPDATE/EBSD_HIT_TEST below.

ENEMY_SPEED   EQU 4         ; dots/frame
ENEMY_SPAWNX  EQU 240        ; right edge (256-16, sprite is 16 wide)
ENEMY_HIDE_Y  EQU 191        ; bottom-right corner (255,191): paired with X=255
                             ; at every hide site below, so a hidden sprite is
                             ; clipped off-screen by X as well as Y - not just
                             ; the single Y=200-below-the-192-line-screen check
                             ; this used to rely on alone. Still not 208, the
                             ; special "end of sprite list" terminator value,
                             ; so a hidden unit doesn't blank out units after it.
ENEMY_Y0      EQU 16         ; cycle0 spawn Y: 16 dots from the top
ENEMY_Y1      EQU 128        ; cycle1/3 spawn Y: 16 dots above ground row0 (18*8-16)
ENEMY_Y2      EQU 32         ; cycle2 spawn Y: 32 dots from the top
PAT_ENEMY0    EQU 4          ; unit0: patterns 4-7  (32 bytes at SPRPAT+32)
PAT_ENEMY1    EQU 8          ; unit1: patterns 8-11 (32 bytes at SPRPAT+64)
PAT_ENEMY2    EQU 12         ; unit2: patterns12-15 (32 bytes at SPRPAT+96)
PAT_E1U3      EQU 72         ; unit3: patterns72-75 (32 bytes at SPRPAT+576)
PAT_E1U4      EQU 76         ; unit4: patterns76-79 (32 bytes at SPRPAT+608)
PAT_E1U5      EQU 80         ; unit5: patterns80-83 (32 bytes at SPRPAT+640)
SPR_GRAY      EQU 0Eh
SPR_LTGREEN   EQU 03h     ; sprite color: light green

; --- destroyed-quadrant explosion (background-character animation) ---
; 3 slots (round-robin), 8 bytes each: ACTIVE,PHASE,TIMER,ROW,COL,SAVED,CODE1,CODE2
ANIM_BASE       EQU 0E409h
ANIM_RR         EQU 0E421h
ANIM_TMP_ROW    EQU 0E422h
ANIM_TMP_COL    EQU 0E423h
ANIM_TMP_VAL    EQU 0E424h
ANIM_ADDR_TMP   EQU 0E425h   ; 2 bytes
ANIM_FRAME_LEN  EQU 8
ANIM1_BLUE  EQU 88
ANIM1_WHITE EQU 96
ANIM1_GREEN EQU 104
ANIM1_BROWN EQU 112
ANIM2_BLUE  EQU 120
ANIM2_WHITE EQU 128
ANIM2_GREEN EQU 136
ANIM2_BROWN EQU 144

; --- PSG (noise channel) shot/destroy sound effects ---
PSG_ADDR EQU 0A0h
PSG_DATA EQU 0A1h
SND_TIMER EQU 0E427h
SND_TIMER_C EQU 0E4D0h
SND_TIMER_B EQU 0E739h

; --- boss shield: while the boss is materializing (BOSS_STATE==1  ---
; --- only - not needed once landed, see below), any player shot   ---
; --- that reaches col25 (just before the boss's own cols26-30) is ---
; --- deflected instead of being allowed to fly through and get    ---
; --- erased over a not-yet-drawn boss cell (which was leaving     ---
; --- permanent gaps in the boss art). Deflected shots become      ---
; --- small sprites bouncing off in one of 8 fixed, left-biased    ---
; --- directions (never back toward the boss).                     ---
DFL_RNG   EQU 0E73Ah  ; free-running counter, low 3 bits used as the "random" pick
DFL0_ACT  EQU 0E73Bh
DFL0_X    EQU 0E73Ch
DFL0_Y    EQU 0E73Dh
DFL0_VEC  EQU 0E73Eh
DFL0_LIFE EQU 0E73Fh
DFL1_ACT  EQU 0E740h
DFL1_X    EQU 0E741h
DFL1_Y    EQU 0E742h
DFL1_VEC  EQU 0E743h
DFL1_LIFE EQU 0E744h
DFL2_ACT  EQU 0E745h
DFL2_X    EQU 0E746h
DFL2_Y    EQU 0E747h
DFL2_VEC  EQU 0E748h
DFL2_LIFE EQU 0E749h
DFL_SPR0  EQU 9        ; fixed sprite numbers - materialize-only (boss-shield deflection),
DFL_SPR1  EQU 10        ; done well before landing, so safe to not overlap the
DFL_SPR2  EQU 11        ; landed-only pod/bullet/explosion sprites below
DFL_SPEED EQU 3
DFL_LIFESPAN EQU 40    ; frames before a deflected shot just despawns
DFL_BULLET_PATNUM EQU 104

; --- pod destruction effect: a single sprite (not a BG write -    ---
; --- that was leaving permanent leftover enemy3-pattern debris    ---
; --- since it never got cleaned up), a 16x16 burst made of 4      ---
; --- copies of the anim2 spark pattern scattered around the tile  ---
; --- rather than aligned to the four 8x8 quadrants.                ---
EXPLOSION_SPR_BASE EQU 22     ; 8 consecutive sprite numbers, one per pod index
EXPLOSION_PATNUM  EQU 108
EXPLOSION_DURATION EQU 20
EXPLOSION_ACT    EQU 0E786h  ; 8 bytes, indexed by pod number (0-7)
EXPLOSION_X      EQU 0E78Eh  ; 8 bytes
EXPLOSION_Y      EQU 0E796h  ; 8 bytes
EXPLOSION_TIMER  EQU 0E79Eh  ; 8 bytes

; --- difficulty scaling: as pods die, the remaining ones orbit    ---
; --- faster and fire more often. Recomputed once each time a pod  ---
; --- is destroyed (POD_HIT), not every frame.                     ---
BOSS_ORBIT_SPEED_CUR  EQU 0E7A6h  ; angle steps advanced per frame (was always 1)
POD_FIRE_INTERVAL_CUR EQU 0E7A7h  ; frames between pair-fires (was always POD_FIRE_INTERVAL)

; --- intentional "enrage" behavior: before the all-fire volley, a  ---
; --- marker does one full lap around the pods' own orbit path;    ---
; --- once it completes the lap, the volley fires. If that volley  ---
; --- doesn't cost the boss a pod (checked by comparing alive count ---
; --- before vs after), the whole lap+fire sequence repeats         ---
; --- immediately - forever, until the player actually lands a     ---
; --- kill, at which point it drops back to the normal pair-fire   ---
; --- cycle.                                                        ---
POD_LAP_ACTIVE   EQU 0E7A8h
POD_LAP_STEP     EQU 0E7A9h  ; angular step 0-7 within the current lap
POD_LOOP_ALIVE_SNAPSHOT EQU 0E7AAh
POD_LAP_CYCLE    EQU 0E7ACh  ; which of the 3 laps we're on

; --- sprite-number free-list: 32 bytes, index=hardware sprite number ---
; --- (0-31), value 0=free/1=in-use. Indices 0-1 (player) are never  ---
; --- touched by the allocator, which only scans 2-31. Replaces the  ---
; --- old blind round-robin NEXT_SPRITE_NUM counter, which hand out  ---
; --- a number without checking whether it was still in use - the    ---
; --- cause of the stray white Y=0 garbage sprites. ---
SPRITE_USED      EQU 0E7ADh  ; 32 bytes (E7AD-E7CC)

; --- boss BG-destruction sequence: once all 8 pods are dead, every  ---
; --- non-blank BOSS_MAP cell (71 of them) gets popped one at a      ---
; --- time, in a fixed order (BOSS_EXPL_LUT_DATA, precomputed once   ---
; --- offline - same pattern every single playthrough, no runtime    ---
; --- RNG involved), each pop pairing a nametable erase with a       ---
; --- reused pod-explosion sprite and a noise-channel boom. ---
BOSS_EXPL_COUNT     EQU 71       ; fixed length of BOSS_EXPL_LUT_DATA
BOSS_EXPL_INDEX     EQU 0E81Eh   ; how many popped so far
BOSS_EXPL_ACTIVE    EQU 0E81Fh   ; 1 while the pop sequence is running
BOSS_EXPL_STARTED   EQU 0E820h   ; latches so the sequence only ever triggers once
BOSS_EXPL_TIMER     EQU 0E821h   ; frames until the next pop
BOSS_EXPL_SPRIDX    EQU 0E822h   ; round-robin 0-7 into the now-unused pod explosion sprite slots
BOSS_EXPL_ROW       EQU 0E824h   ; scratch: this pop's boss-map row
BOSS_EXPL_COL       EQU 0E825h   ; scratch: this pop's boss-map col
PLAYER_FLYAWAY      EQU 0E828h   ; 0=normal control, 1=auto-flying right, 2=off-screen/hidden
PLAYER_FLYAWAY_SPD  EQU 0E82Ah   ; current flyaway speed
PLAYER_FLYAWAY_DIST EQU 0E839h   ; total px traveled since flyaway started (accel curve)
PARTICLE_SPAWN_COOLDOWN EQU 0E83Ah  ; frames until the next spawn is allowed

; --- Enemy1: one-time diagonal dodge toward the player when     ---
; --- crossing screen-center X. Per-instance now: E_PARAM0 (done?),  ---
; --- E_PARAM1 (remain), E_PARAM2 (dir) on the unified ENEMY_POOL.   ---
ENEMY_CENTER_X   EQU 128     ; screen-center X threshold for the dodge
ENEMY_DODGE_DIST EQU 16      ; total px moved diagonally, 1px/frame, per flight

; --- per-frame dodge progress: REMAIN counts down 16->0 (1px/frame),---
; --- DIR is the signed per-frame Y step (+1 or -1, set once when   ---
; --- the dodge triggers). Per-instance now: E_PARAM1/E_PARAM2 on    ---
; --- the unified ENEMY_POOL (see ENEMY_CENTER_X above).             ---
POD_VOLLEY_COLOR_TEST EQU 0E829h ; trial: +1 every frame while pods are launched, wraps 2-14

; --- rainbow particle trail during the flyaway: 2 slots (sprite    ---
; --- scanline budget - only 2 to spare), reusing pod-explosion     ---
; --- sprite numbers 22-23. Each particle actually travels (small   ---
; --- random angle off due-left) and despawns after ~32px. ---
PARTICLE_ACT         EQU 0E82Bh  ; 2 bytes: 0=inactive, else frames of life left
PARTICLE_X           EQU 0E82Dh  ; 2 bytes
PARTICLE_Y           EQU 0E82Fh  ; 2 bytes
PARTICLE_COL         EQU 0E831h  ; 2 bytes
PARTICLE_DX          EQU 0E833h  ; 2 bytes, signed
PARTICLE_DY          EQU 0E835h  ; 2 bytes, signed
PLAYER_FLYAWAY_WAIT  EQU 0E838h  ; frames left in the pre-flyaway pause
LAP_MARKER_SPR   EQU 30
LAP_MARKER_SPR2  EQU 31
LAP_CYCLES       EQU 3       ; 3 full laps
; --- no hold/delay at all - one step every single frame, 8 steps ---
; --- per lap x 3 laps = 24 frames total. Two markers, offset 8px ---
; --- in front of two opposite pods (index and index+4), blinking ---
; --- as they advance together - not accumulating, never lighting ---
; --- the pods themselves.                                         ---
POD_FIRE_INTERVAL_MIN EQU 6       ; floor - never fires faster than this

; --- every 3rd full pair-cycle (7 pairs = 1 cycle), instead of    ---
; --- continuing pair-by-pair, the orbit freezes and all 8 pods    ---
; --- fire at once. After a pause the volley clears, then the      ---
; --- orbit/pair-cycle resumes normally from pair0.                ---
POD_CYCLE_COUNT   EQU 0E74Ah
POD_VOLLEY_ACTIVE EQU 0E74Bh
POD_VOLLEY_TIMER  EQU 0E74Ch
VOLLEY_PHASE      EQU 0E74Dh  ; 8 bytes: 0=flying left (outbound), 1=returning right
VOLLEY_X          EQU 0E755h  ; 8 bytes
VOLLEY_Y          EQU 0E75Dh  ; 8 bytes
VOLLEY_START_X    EQU 0E765h  ; 8 bytes: each pod's launch X, the round-trip's return target
; VOLLEY_SPR_BASE retired - the volley now launches the pods'
; own sprites directly (see LAUNCH_DRAW) instead of separate
; bullet sprites, so this range is unused.
VOLLEY_CYCLES_BEFORE EQU 3    ; fire the volley every 3rd full cycle
VOLLEY_PAUSE      EQU 100     ; (unused now - completion is dynamic, see CHECK_ALL_ARRIVED)
LAUNCH_SPEED      EQU 12      ; px/frame the launched pods fly left and back
POD_VOLLEY_WINDUP EQU 0E76Dh  ; frames left in the pre-fire pause (pods visibly stop before firing)
POD_VOLLEY_WINDUP_FRAMES EQU 15

; --- pod HP/collision: each pod has POD_HP_MAX hit points; player  ---
; --- shots that touch a pod (checked against its live position,   ---
; --- cached here every frame by whichever routine is currently    ---
; --- driving it - orbit draw or launch/volley draw) knock off 1.  ---
; --- At 0, the pod explodes (sound + a one-shot BG mark) and stops ---
; --- being drawn/targeted from then on.                            ---
POD_HP        EQU 0E76Eh  ; 8 bytes
POD_CUR_X     EQU 0E776h  ; 8 bytes - live position cache for collision checks
POD_CUR_Y     EQU 0E77Eh  ; 8 bytes
POD_HP_MAX    EQU 8
POD_HIT_RANGE EQU 12       ; px - how close a shot needs to be to register a hit

; --- on-screen game-tick counter (3 decimal digits, top-right) ---
DIGIT_BASE EQU 176   ; digit0 code; digitN = DIGIT_BASE+N (groups22-23)
GTD_ONES_TMP EQU 0E4D3h

; --- tick-based enemy spawn schedule: measured roughly every 30    ---
; --- ticks in order enemy1,enemy1,enemy2,enemy2,enemy3 (enemy3     ---
; --- lands around tick120). One-shot - once all 5 have fired,      ---
; --- nothing more triggers automatically (no looping).             ---
SPAWN_NEXT_INDEX EQU 0E4D4h
SPAWN_E1_Y EQU 0E506h          ; Y chosen for the next independent Enemy1 spawn
NEXT_SPRITE_NUM EQU 0E507h     ; rotating sprite attribute slot allocator (1-31, 0=player reserved)

; --- score: enemy1=100pts, enemy2=200pts, enemy3=300pts per kill. ---
; --- 16-bit binary (score never realistically exceeds ~65535 in   ---
; --- this game), displayed as a fixed 8-digit nametable string     ---
; --- top-left (row0, cols0-7); the top 3 digits are always '0'.    ---
SCORE        EQU 0E4D5h   ; 2 bytes
SCORE_DIGITS EQU 0E4D7h   ; 5 bytes (ten-thousands..ones)

; --- direct/raw PSG joystick read (BIOS GTTRIG's trigger B never  ---
; --- worked on real hardware; a raw PSG read was confirmed correct---
; --- there, so joystick input now goes through this instead of    ---
; --- GTSTCK/GTTRIG). R15 bit6=0 selects joystick port1's pins onto ---
; --- R14: bit0=up,bit1=down,bit2=left,bit3=right,bit4=trigA,       ---
; --- bit5=trigB, all active-LOW.                                   ---
JOY_PSG_ADDR EQU 0A0h
JOY_PSG_DATA EQU 0A1h
JOY_PSG_READ EQU 0A2h
JOY_RAW EQU 0E4DCh
JOY_STICK EQU 0E4DFh  ; BIOS GTSTCK result (0-8 direction code)
JOY_TRIG EQU 0E4E0h   ; BIOS GTTRIG result, trigger A (0=released, FFh=pressed)
JOY_TRIGB EQU 0E4DDh      ; BIOS GTTRIG result, trigger B (0=released, FFh=pressed)
JOY_TRIGB_PREV EQU 0E4DEh ; trigger B state, previous frame (for edge detection)
FIREB_EDGE EQU 0E4E1h     ; 1 = trigger B was just pressed this frame

; --- formation entrance/exit sequence (4-cycle: simple@Y0, simple@Y1, ---
; --- complex@Y2 mirrored-Z exit, complex@Y1 normal-Z exit, loop)      ---
ENEMY_MODE      EQU 0E428h   ; 0=simple per-unit drift, 1=complex assembly/drift/exit
ENEMY_CYCLE     EQU 0E429h   ; 0-3, which spawn behavior is next
ENEMY_EXITTYPE  EQU 0E42Ah   ; 0=mirrored-Z, 1=normal-Z (complex mode only)
ENEMY_SEQ_STATE EQU 0E42Bh   ; complex-mode substate 0-8
ENEMY_PROGRESS  EQU 0E42Ch   ; generic distance counter (drift/exit phases)
TEMP_X          EQU 0E42Dh   ; X of the transient "flying quadrant" sprite
FASTJUMP      EQU 10          ; px/frame while a quadrant flies into formation
TARGETX0      EQU 112        ; unit0 assembly X (unit1=+16,unit2=+32) - roughly centered
DRIFT_LEN     EQU 32         ; slow drift distance once assembled
EXIT_SPEED    EQU 6          ; px/frame during the fast Z exit
EXIT_SEGLEN   EQU 32         ; length of each of the Z's 3 segments
PAT_TEMP_TOP  EQU 24         ; static pattern: top-left asterisk only  (patterns24-27)
PAT_TEMP_BOT  EQU 28         ; static pattern: bottom-right asterisk only (patterns28-31)
TEMP_SLOT_OFFSET EQU 16      ; sprite attribute slot4 (terminator moves to slot5)

; --- per-unit Y (kept in sync with ENEMY_Y during assembly/drift so ---
; --- collision code can always just use these; diverge during the  ---
; --- snake-trail exit phase, where each unit has its own Y)        ---
ENEMY0_Y EQU 0E42Eh
ENEMY1_Y EQU 0E42Fh
ENEMY2_Y EQU 0E430h

; --- exit phase 2: leader dives/climbs diagonally to the opposite  ---
; --- vertical extreme, then flattens out to a horizontal exit left;---
; --- units 1/2 don't keep formation - they trail the leader's own  ---
; --- past path (like Gradius Options), read out of a small ring    ---
; --- buffer of the leader's recent (X,Y) history.                  ---
ENEMY_EXIT_PHASE EQU 0E431h   ; 0=diagonal,1=horizontal (within state7)
ENEMY0_EXITED EQU 0E500h      ; state7 trail exit: unit hidden independently
ENEMY1_EXITED EQU 0E501h      ; once IT reaches the left edge, instead of
ENEMY2_EXITED EQU 0E502h      ; waiting for all 3 (same as ENEMY2 in simple mode)
EDS_Y0 EQU 0E503h             ; ENEMY_DRAW_SNAKE: precomputed effective Y
EDS_Y1 EQU 0E504h             ; (real Y, or ENEMY_HIDE_Y if that unit has
EDS_Y2 EQU 0E505h             ; already exited) - computed before the NOP-padded write section, not branched into it
WEDGE_Y      EQU 184          ; ground row0+5's pixel Y (23*8)
TOP_Y        EQU 32           ; matches ENEMY_Y2
TRAIL_DELAY  EQU 8            ; frames unit1 trails the leader by (unit2 = 2x)
TRAIL_BUFLEN EQU 32           ; ring buffer size (power of 2 -> cheap AND-mask wrap)
TRAIL_WIDX   EQU 0E432h
TRAIL_HIST   EQU 0E433h       ; TRAIL_BUFLEN*2 = 64 bytes (X,Y pairs)

; --- enemy3: nametable-only 8x8 dot, 3-frame pulse animation      ---
; --- (pattern order 1,2,3,2 repeating). Enters diagonally from    ---
; --- upper-right to center, orbits a LUT-defined radius-24 circle ---
; --- CCW starting from the top, 1.5 revolutions (ends at the      ---
; --- bottom), then exits diagonally toward the lower-right. A     ---
; --- pool of ENEMY3_SLOTS concurrent instances is recycled until  ---
; --- ENEMY3_BUDGET (total spawns) runs out; each instance is      ---
; --- fully independent so overlapping cells never affect tracking.---
; --- Destroyed by shots using the same shared explosion/sound.    ---
ENEMY3_CODE1  EQU 152          ; pattern1 (gray/blue), group19
ENEMY3_CODE2  EQU 160          ; pattern2 (gray/blue), group20
ENEMY3_CODE3  EQU 168          ; pattern3 (gray/red),  group21
ANIM3_PACE    EQU 6            ; frames held per pulse-animation frame
ENEMY3_SLOTS  EQU 8
ENEMY3_STRUCT EQU 11           ; ACTIVE,PHASE,X,Y,ROW,COL,ANGLEIDX,STEPCNT,REVCNT,ANIMIDX,ANIMTIMER
ENEMY3_SPAWN_X EQU 200
ENEMY3_SPAWN_Y EQU 8
ENEMY3_CENTER_X EQU 128
ENEMY3_CENTER_Y EQU 80
ENEMY3_DIAG_SPEED EQU 2
ENEMY3_STEP_FRAMES EQU 2       ; frames held per LUT angle step
ENEMY3_TOTAL_STEPS EQU 36      ; 24 LUT points x 1.5 revolutions
ENEMY3_START_ANGLE EQU 6       ; LUT index for the top of the circle
ENEMY3_EXIT_SPEED EQU 3
; Row 17 = 7th row from the bottom (23,22,21,20,19,18,17) and sits just
; above GROUND_ROW0(18) - i.e. above the scrolling ground entirely, in
; the plain sky.
ENEMY3_EXIT_TARGET_Y EQU 136       ; row 17 pixel Y (17*8): exit levels off
                                    ; here, above the scroller, then flies
                                    ; right off-screen
ENEMY3_SPAWN_INTERVAL EQU 8    ; frames between EVERY spawn in the budget-32 stream
                                ; ("1 count" - matches the schedule tick unit).

ENEMY3_BUDGET      EQU 0E473h
ENEMY3_SPAWN_TIMER EQU 0E474h
ENEMY3_SPAWN_COUNT EQU 0E4CEh  ; how many spawned so far this wave (resume enemy1/2 at 32)
ENEMY3_POOL        EQU 0E475h  ; 8*11 = 88 bytes
ENEMY3_CURRENT_OFFSET EQU 0EB5Eh ; this wave's circle-center X pixel offset - set by
                                ; SPAWN_E3_WAVE from SPAWN_E3_OFFSET_TABLE (per-trigger,
                                ; from the schedule editor's own "offset" field on that
                                ; placement) and applied to every spawn until the next
                                ; SPAWN_E3_WAVE call changes it
ENEMY3_CENTERX_TABLE EQU 0EB5Fh ; 8*11=88 bytes, parallel to ENEMY3_POOL: each slot's
                                ; OWN circle-center X pixel offset, copied from
                                ; ENEMY3_CURRENT_OFFSET at spawn time - lets each
                                ; instance orbit its own horizontally-offset center
                                ; instead of sharing one circle

; --- shot background-color variants: blue(sky), white(mountain, ---
; --- screen row 18), green(diamond/slash/backslash, rows 19-22), ---
; --- brown(wedge, row 23) - same treatment as the existing green ---
; --- variant, just matching each row's own dominant fill color.  ---
BULLET_PAT_WHITE EQU 72
BULLET_PAT_BROWN EQU 80

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

INIT:
    LD SP,STACKTOP

    ; --- map our own primary slot into page 2 (8000h-BFFFh) as    ---
    ; --- well - the BIOS cartridge-boot sequence only auto-maps   ---
    ; --- page 1 (4000h-7FFFh), which is where execution starts.   ---
    ; --- Since this ROM is now bigger than 16KB (needs a Plain/   ---
    ; --- Linear 32K mapper, not a bank-switching one), anything   ---
    ; --- placed past 8000h is unreachable - reads as whatever the ---
    ; --- page was previously mapped to (in practice: garbage, or  ---
    ; --- a mirror of page 1) - until this runs. This must be the  ---
    ; --- very first thing that happens, before any code or data   ---
    ; --- past 8000h could possibly be touched.                    ---
    ; --- NOTE: this copies page 1's PRIMARY slot into page 2's    ---
    ; --- primary slot select bits only - correct for an unexpanded ---
    ; --- slot (true for essentially all simple flash carts). A    ---
    ; --- cartridge slot with sub-slots (expanded) would also need ---
    ; --- its secondary slot register handled, which this doesn't. ---
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

    ; --- interrupts stay off for all of INIT's raw VDP/PSG port I/O; ---
    ; --- see the matching EI just before falling into MAINLOOP. This ---
    ; --- also protects IX, which the MSX BIOS's own timer interrupt ---
    ; --- handler uses internally and does not preserve - letting an ---
    ; --- interrupt land mid-sequence while IX holds one of our      ---
    ; --- pointers would silently corrupt it.                        ---
    DI
    CALL INIT32

    ; --- border/backdrop color (VDP R7, low nibble) = black. This is ---
    ; --- the true overscan border, separate from the in-screen sky   ---
    ; --- (BLANKCODE's color group), which stays blue.                ---
    LD B,01h : LD C,7 : CALL WRTVDP

    LD HL,PATTERNS  : LD DE,0000h : LD BC,PATTERNS_LEN : CALL LDIRVM
    LD HL,COLORDATA : LD DE,2000h : LD BC,COLOR_LEN : CALL LDIRVM
    LD HL,BLANK_PATTERN : LD DE,BLANKCODE*8 : LD BC,8 : CALL LDIRVM   ; BLANKCODE's glyph was never written before - defaulted to leftover VRAM garbage

    XOR A
    LD (TICK),A : LD (PXCHAR_G8),A : LD (PXCHAR_G4),A
    LD (PXCHAR_G2),A : LD (PXCHAR_G1),A

    ; Seed the 5 remaining IDCACHEn buffers (row1/IDCACHE1 no longer used -
    ; TIER2_DIAMOND's processing was dropped, see GROUND_ROW0) for
    ; PXCHAR=0 (the gates in MAINLOOP that call REFRESH_IDCACHE_33 only
    ; fire once their group's PXCHAR actually advances - every 8/16/32/64
    ; frames - so without this, frame 1 would render from stale/zeroed
    ; cache RAM).
    LD HL,ROWDATA0 : LD IX,IDCACHE0 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA2 : LD IX,IDCACHE2 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA3 : LD IX,IDCACHE3 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA4 : LD IX,IDCACHE4 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA5 : LD IX,IDCACHE5 : CALL REFRESH_IDCACHE_33

    LD HL,PREVBUF : LD (HL),0FFh
    LD DE,PREVBUF+1 : LD BC,159 : LDIR

    ; Clear the background rows (screen rows 0-18, 19*32=608 bytes,
    ; i.e. everything above the 5-row scroller which now sits at
    ; screen rows 19-23) to BLANKCODE, whose color group is set to
    ; fg=bg=blue in COLORDATA so it reads as solid blue regardless
    ; of pattern content.
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,58h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,BLANKCODE
    LD B,00h
    EI
FILLBG_1:
    DI
    OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    DJNZ FILLBG_1
    LD B,00h
FILLBG_2:
    DI
    OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    DJNZ FILLBG_2
    LD B,96
FILLBG_3:
    DI
    OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    DJNZ FILLBG_3

    ; --- sprite pattern generator table (VRAM 3800h): ship is a static ---
    ; --- 16x16 pattern; the 3 enemy-formation units' patterns are      ---
    ; --- generated at runtime (see REDRAW_UNIT_PATTERN / ENEMY_RESPAWN) ---
    ; --- since each asterisk quadrant can be independently shot out.   ---
    LD HL,SPRITE_PATTERNS : LD DE,SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_PATTERN : LD DE,SPRPAT+80h : LD BC,32 : CALL LDIRVM

    ; --- shot character patterns (8 vertical phases x4 color variants), VRAM 0000h+56*8 ---
    LD HL,BULLET_PATTERNS : LD DE,1C0h : LD BC,256 : CALL LDIRVM  ; 1C0h = BULLET_PAT_BLUE(56)*8

    ; --- destroy-animation character patterns, VRAM 2C0h = ANIM1_BLUE(88)*8 ---
    LD HL,ANIM_PATTERNS : LD DE,2C0h : LD BC,512 : CALL LDIRVM

    ; --- temp assembly-sprite patterns, VRAM SPRPAT+C0h = PAT_TEMP_TOP(24)*8 ---
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,SPRPAT+0C0h : LD BC,64 : CALL LDIRVM
    ; --- E2A_TT/E2A_TB (pattern44-51) and E2B_TT/E2B_TB (pattern64-71) ---
    ; --- never had this loaded before - the fly-in phase (states 0-5, ---
    ; --- before the formation assembles) used these pattern codes but ---
    ; --- they were blank VRAM, so nothing was visible until merge.    ---
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,SPRPAT+160h : LD BC,64 : CALL LDIRVM
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,SPRPAT+200h : LD BC,64 : CALL LDIRVM

    ; --- enemy3 pulse-animation patterns, codes 152/160/168 ---
    LD HL,ENEMY3_PATTERN1 : LD DE,ENEMY3_CODE1*8 : LD BC,8 : CALL LDIRVM
    LD HL,ENEMY3_PATTERN2 : LD DE,ENEMY3_CODE2*8 : LD BC,8 : CALL LDIRVM
    LD HL,ENEMY3_PATTERN3 : LD DE,ENEMY3_CODE3*8 : LD BC,8 : CALL LDIRVM

    ; --- digit glyphs (0-9) for the on-screen game-tick counter ---
    LD HL,DIGIT_PATTERNS : LD DE,DIGIT_BASE*8 : LD BC,80 : CALL LDIRVM

    ; --- boss BG/sprite character patterns are NOT preloaded here ---
    ; --- anymore - the terrain scroller actually uses more of the ---
    ; --- 256 pattern codes than codes192-255 looked "free" for    ---
    ; --- (8 phase-shifted composite patterns per row display, 16  ---
    ; --- for the bottom paired row), so permanently claiming that ---
    ; --- range for the whole game collided with it. Loaded just   ---
    ; --- in time instead, in BOSS_SPAWN, right when the boss      ---
    ; --- timer actually fires.                                    ---
    XOR A : LD (BOSS_STATE),A
    ; --- sky-erase dispatch vectors start pointed at the fast      ---
    ; --- (BLANKCODE) routines; repointed at the boss-aware ones    ---
    ; --- once it lands - see BOSS_UPDATE_BODY.                     ---
    LD HL,SKY_FAST_0H : LD (SKY_VEC_0H),HL
    LD HL,SKY_FAST_0E : LD (SKY_VEC_0E),HL
    LD HL,SKY_FAST_1H : LD (SKY_VEC_1H),HL
    LD HL,SKY_FAST_1E : LD (SKY_VEC_1E),HL
    LD HL,SKY_FAST_2H : LD (SKY_VEC_2H),HL
    LD HL,SKY_FAST_2E : LD (SKY_VEC_2E),HL
    LD HL,0 : LD (GAME_TICK),HL
    CALL GAME_TICK_DISPLAY
    LD HL,0 : LD (SCORE),HL
    CALL SCORE_DISPLAY

    ; --- enemy3 pool: idle at boot - the wave starts when the tick ---
    ; --- schedule reaches it (see SPAWN_SCHEDULE_CHECK)              ---
    XOR A : LD (ENEMY3_BUDGET),A
    XOR A : LD (ENEMY3_SPAWN_COUNT),A
    LD A,1 : LD (ENEMY3_SPAWN_TIMER),A
    ; Full 88-byte clear (all 8 slots, not just each slot's ACTIVE byte) -
    ; ENEMY3_UPDATE_SLOT's inactive-slot safety net (see its own comment)
    ; reads ROW/COL (bytes 4/5) even for never-yet-spawned slots, and an
    ; uninitialized (0,0) would blank row0/col0 - the score display's
    ; first digit - every frame until the first real spawn.
    LD HL,ENEMY3_POOL : LD (HL),0
    LD DE,ENEMY3_POOL+1 : LD BC,88-1 : LDIR
    LD A,1                          ; ROW=1 (sky, matches ENEMY3_SPAWN_Y>>3) - never HUD row0
    LD (ENEMY3_POOL+4),A  : LD (ENEMY3_POOL+15),A : LD (ENEMY3_POOL+26),A
    LD (ENEMY3_POOL+37),A : LD (ENEMY3_POOL+48),A : LD (ENEMY3_POOL+59),A
    LD (ENEMY3_POOL+70),A : LD (ENEMY3_POOL+81),A
    XOR A : LD (ENEMY3_CURRENT_OFFSET),A
    LD HL,ENEMY3_CENTERX_TABLE : LD (HL),0
    LD DE,ENEMY3_CENTERX_TABLE+1 : LD BC,88-1 : LDIR

    ; --- switch sprites to 16x16 mode (VDP R1 bit1=SI), keep other bits ---
    LD A,(RG1SAV) : OR 02h : LD (RG1SAV),A
    LD B,A : LD C,1 : CALL WRTVDP

    ; --- explicitly clear the WHOLE sprite attribute table (32       ---
    ; --- entries x 4 bytes = 128 bytes) to a fully hidden, known     ---
    ; --- state (Y=209 - past the Y=208 stop-sentinel - X/pattern/    ---
    ; --- color=0). Until now, any sprite number not yet touched      ---
    ; --- this session held whatever was in VRAM before: leftover     ---
    ; --- from a previous run/warm-reset, or the emulator's/hardware's---
    ; --- power-on VRAM content. A slot with a real leftover pattern+ ---
    ; --- color but a not-yet-hidden Y is exactly the reported white  ---
    ; --- asterisk near the score, which then "moves" once real game  ---
    ; --- code finally claims that number and overwrites it for real. ---
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

    ; --- player initial state ---
    LD A,PLAYER_INITX : LD (PLAYERX),A
    LD A,PLAYER_INITY : LD (PLAYERY),A
    XOR A
    LD (BULLET0_ACT),A : LD (BULLET1_ACT),A : LD (BULLET2_ACT),A
    LD (JOY_TRIGB_PREV),A
    ; --- clear the sprite-number free-list (all 32 bytes; 0-1 are  ---
    ; --- never scanned by the allocator, so they don't need to be  ---
    ; --- marked used separately) ---
    XOR A
    LD HL,SPRITE_USED : LD (HL),A
    LD DE,SPRITE_USED+1 : LD BC,31 : LDIR
    LD A,1 : LD (NEXT_SPRITE_NUM),A

    ; --- fully clear E2A/E2B's entire state blocks (98 bytes each),  ---
    ; --- not just ACTIVE. CHECK_BULLET_VS_FORMATION_A/B gates on     ---
    ; --- U0/1/2_STATE (not ACTIVE), so any stale non-zero STATE left ---
    ; --- over from a previous run (RAM isn't hardware-cleared by a   ---
    ; --- reset) would keep reacting to bullets at its old stale X/Y  ---
    ; --- using its old stale SPRNUM - exactly the leftover-sprite    ---
    ; --- garbage seen after a warm/hot reset.                        ---
    XOR A
    LD HL,E2A_SEQ_STATE : LD (HL),A
    LD DE,E2A_SEQ_STATE+1 : LD BC,97 : LDIR
    LD HL,E2B_SEQ_STATE : LD (HL),A
    LD DE,E2B_SEQ_STATE+1 : LD BC,97 : LDIR
    CALL ENEMY_POOL_INIT
    LD HL,ENEMY4_PATTERN : LD DE,PAT_ENEMY4*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,PARTICLE_PATTERN : LD DE,PAT_PARTICLE*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD A,1 : LD (ENEMY1_LOOK_FLAGS),A : LD (ENEMY1_LOOK_FLAGS+1),A
    LD HL,PAT_ENEMY1_LOOK*8+SPRPAT : LD DE,ENEMY1_LOOK_FLAGS : LD IX,ENEMY1_LOOK_FLAGS+1
    CALL REDRAW_UNIT_PATTERN
    XOR A : LD (BOSS_EXPL_ACTIVE),A
    XOR A : LD (BOSS_EXPL_STARTED),A
    XOR A : LD (PLAYER_FLYAWAY),A
    XOR A : LD (PLAYER_FLYAWAY_WAIT),A
    XOR A : LD (PLAYER_FLYAWAY_DIST),A
    XOR A : LD (PARTICLE_SPAWN_COOLDOWN),A
    LD A,2 : LD (POD_VOLLEY_COLOR_TEST),A
    LD HL,PARTICLE_ACT : LD (HL),0
    LD DE,PARTICLE_ACT+1 : LD BC,11 : LDIR
    XOR A
    LD (FIRE_COOLDOWN),A

    ; --- force the BIOS vblank hook (H.TIMI, RAM) to a bare RET. MSX's ---
    ; --- only interrupt source is the VDP, so this makes EI+HALT below ---
    ; --- a cheap, exact vblank wait instead of polling VDP status: the ---
    ; --- IM1 handler still runs its own short prologue/epilogue, but   ---
    ; --- does nothing else before HALT resumes right after vblank.    ---
    LD A,0C9h : LD (0FD9Fh),A

    ; --- enemy formation initial state: SPAWN_SCHEDULE_CHECK handles ---
    ; --- every spawn (including the first) from index0 onward.       ---
    XOR A
    LD (ENEMY_CYCLE),A
    LD (ENEMY_MODE),A
    LD (ANIM_RR),A
    LD (ANIM_BASE+0),A : LD (ANIM_BASE+8),A : LD (ANIM_BASE+16),A
    LD (SND_TIMER),A
    LD (SND_TIMER_C),A
    LD (SPAWN_NEXT_INDEX),A

    ; --- PSG: channel A = noise-only (destroy), channel B = tone-only ---
    ; --- (pod-fire "don"), channel C = tone-only (shot) ---
    ; --- R7's upper 2 bits MUST be '10' (portA=input,portB=output) - ---
    ; --- portB drives the joystick-port select strobe; leaving it as ---
    ; --- input (our old 0x33) floats that line and makes joystick    ---
    ; --- reads unstable on real PSG-based hardware.                  ---
    ; --- DI/EI wraps every reg-select+data pair: an interrupt firing  ---
    ; --- between the two OUTs would leave the wrong PSG register     ---
    ; --- selected, corrupting both this write and (since the BIOS's  ---
    ; --- keyboard/joystick scan also uses the PSG) joystick reads.   ---
    LD A,7 : OUT (PSG_ADDR),A
    LD A,0B1h : OUT (PSG_DATA),A

    ; --- sprite attribute table (VRAM 1B00h): ship body (16x16, slot1), ---
    ; --- accent overlay (16x16, slot0, drawn on top, at ship_X+8) ---
    DI
    LD A,04h : OUT (99h),A
    NOP
    NOP
    NOP
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
    NOP
    NOP
    NOP
    LD A,PLAYER_INITY : SUB 8 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PLAYER_INITX : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_SHIP   : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_RED    : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP

    LD A,00h : OUT (99h),A
    NOP
    NOP
    NOP
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
    NOP
    NOP
    NOP
    LD A,PLAYER_INITY : SUB 8 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PLAYER_INITX : ADD A,8 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_ACCENT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_WHITE  : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    ; --- dynamic sprite numbering means enemies can land on any slot ---
    ; --- 2-31 in any order, so the old "write a terminator right     ---
    ; --- after the last sequential write" trick no longer works.     ---
    ; --- Explicitly hide every slot 1-31 up front instead; inactive  ---
    ; --- enemy slots get re-hidden every frame anyway, this just     ---
    ; --- guarantees nothing is ever left at a random boot-time Y     ---
    ; --- that could accidentally be the VDP's Y=208 stop value and   ---
    ; --- block every slot after it.
    LD B,30
    LD C,2
    EI
INIT_HIDE_SLOT_LOOP:
    DI
    LD A,C : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    NOP
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
    NOP
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC C
    EI
    DJNZ INIT_HIDE_SLOT_LOOP
    NOP

    EI
    HALT
    JP MAINLOOP

MAINLOOP:
    ; --- free-running: no per-frame DI/EI/HALT. The vblank-gated DI/    ---
    ; --- EI/HALT design (wait for a fresh vblank every frame) caused a  ---
    ; --- large real-hardware slowdown once a frame's body ran long      ---
    ; --- enough to occasionally miss its vblank window. Interrupts stay ---
    ; --- enabled throughout (needed for the BIOS's interrupt-driven     ---
    ; --- keyboard/joystick scan - GTSTCK/GTTRIG read state that only    ---
    ; --- H.KEYI, called from the vblank ISR, keeps fresh); per-write    ---
    ; --- NOP margins are what keep individual VDP OUT sequences safe    ---
    ; --- from an interrupt landing mid-sequence, not DI.                ---
    LD A,(TICK) : INC A : AND 3Fh : LD (TICK),A
    LD A,(BOSS_STATE)
    CP 1
    CALL Z,BOSS_UPDATE_BODY
    LD A,(BOSS_STATE)
    CP 2
    CALL Z,BOSS_ORBIT_UPDATE
    LD A,(BOSS_STATE)
    CP 2
    CALL Z,POD_FIRE_UPDATE
    LD A,(BOSS_STATE)
    CP 2
    CALL Z,POD_COLLISION_UPDATE
    LD A,(BOSS_STATE)
    CP 2
    CALL Z,EXPLOSION_UPDATE
    LD A,(BOSS_STATE)
    CP 2
    CALL Z,BOSS_EXPL_UPDATE
    LD A,(BOSS_STATE)
    CP 1
    CALL Z,BOSS_GUARD_UPDATE
    LD A,(BOSS_STATE)
    OR A
    CALL NZ,DFL_UPDATE

    LD A,(TICK) : AND 07h
    JR NZ,SKIP_G8
    LD A,(PXCHAR_G8) : INC A : AND 3Fh : LD (PXCHAR_G8),A
    LD HL,ROWDATA5 : LD A,(PXCHAR_G8) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE5 : CALL REFRESH_IDCACHE_33
    LD HL,(GAME_TICK) : INC HL : LD (GAME_TICK),HL
    CALL GAME_TICK_DISPLAY
    CALL SPAWN_SCHEDULE_CHECK
SKIP_G8:
    LD A,(TICK) : AND 07h : LD (PHASE_G8),A

    LD A,(TICK) : AND 0Fh
    JR NZ,SKIP_G4
    LD A,(PXCHAR_G4) : INC A : AND 3Fh : LD (PXCHAR_G4),A
    LD HL,ROWDATA3 : LD A,(PXCHAR_G4) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE3 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA4 : LD A,(PXCHAR_G4) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE4 : CALL REFRESH_IDCACHE_33
SKIP_G4:
    LD A,(TICK) : SRL A : AND 07h : LD (PHASE_G4),A

    LD A,(TICK) : AND 1Fh
    JR NZ,SKIP_G2
    LD A,(PXCHAR_G2) : INC A : AND 3Fh : LD (PXCHAR_G2),A
    LD HL,ROWDATA2 : LD A,(PXCHAR_G2) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE2 : CALL REFRESH_IDCACHE_33
SKIP_G2:
    LD A,(TICK) : SRL A : SRL A : AND 07h : LD (PHASE_G2),A

    LD A,(TICK) : AND 3Fh
    JR NZ,SKIP_G1
    LD A,(PXCHAR_G1) : INC A : AND 3Fh : LD (PXCHAR_G1),A
    LD HL,ROWDATA0 : LD A,(PXCHAR_G1) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE0 : CALL REFRESH_IDCACHE_33
SKIP_G1:
    LD A,(TICK) : SRL A : SRL A : SRL A : AND 07h : LD (PHASE_G1),A

    ; --- row 0: screen row 19 (TIER1_MOUNTAIN), group PXCHAR_G1 ---
    ; --- (was screen row 18 - moved down 1 row to fill the gap left by ---
    ; --- deleting TIER2_DIAMOND's own row, see GROUND_ROW0) ---
    LD A,(PHASE_G1) : LD (ROWPHASE),A
    LD HL,IDCACHE0                       ; pre-translated ids - see IDCACHE0 comment
    LD IX,NAMEBUF+0
    LD B,32
    ; --- prime C = curr_id for cell 0; each cell's "next" is the following---
    ; --- cell's "curr" (HL only advances by 1/cell), so C carries it       ---
    ; --- forward every iteration instead of re-reading it. ---
    LD A,(HL) : LD C,A
CELL_LOOP_0:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,(ROWPHASE) : OR A
    JR NZ,NONZERO_0
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    JR STORE_0
NONZERO_0:
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(ROWPHASE) : DEC A : ADD A,E   ; + (phase-1)
STORE_0:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_0

    ; --- row 2: screen row 20 (TIER3_DIAMOND), group PXCHAR_G2 ---
    ; --- (NAMEBUF slot shifted from +64 to +32 - row1/TIER2_DIAMOND's ---
    ; --- slot was deleted, see GROUND_ROW0) ---
    LD A,(PHASE_G2) : LD (ROWPHASE),A
    LD HL,IDCACHE2
    LD IX,NAMEBUF+32
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_2:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,(ROWPHASE) : OR A
    JR NZ,NONZERO_2
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    JR STORE_2
NONZERO_2:
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(ROWPHASE) : DEC A : ADD A,E   ; + (phase-1)
STORE_2:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_2

    ; --- row 3: screen row 21 (TIER4_SLASH), group PXCHAR_G4 ---
    ; --- (NAMEBUF slot shifted from +96 to +64) ---
    LD A,(PHASE_G4) : LD (ROWPHASE),A
    LD HL,IDCACHE3
    LD IX,NAMEBUF+64
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_3:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,(ROWPHASE) : OR A
    JR NZ,NONZERO_3
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    JR STORE_3
NONZERO_3:
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(ROWPHASE) : DEC A : ADD A,E   ; + (phase-1)
STORE_3:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_3

    ; --- row 4: screen row 22 (TIER5_BACKSLASH), group PXCHAR_G4 ---
    ; --- (NAMEBUF slot shifted from +128 to +96) ---
    LD A,(PHASE_G4) : LD (ROWPHASE),A
    LD HL,IDCACHE4
    LD IX,NAMEBUF+96
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_4:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,(ROWPHASE) : OR A
    JR NZ,NONZERO_4
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    JR STORE_4
NONZERO_4:
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(ROWPHASE) : DEC A : ADD A,E   ; + (phase-1)
STORE_4:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_4

    ; --- row 5: screen row 23 (TIER6_WEDGE), group PXCHAR_G8 ---
    ; --- (NAMEBUF slot shifted from +160 to +128) ---
    LD A,(PHASE_G8) : LD (ROWPHASE),A
    LD HL,IDCACHE5
    LD IX,NAMEBUF+128
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_5:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,(ROWPHASE) : OR A
    JR NZ,NONZERO_5
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    JR STORE_5
NONZERO_5:
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(ROWPHASE) : DEC A : ADD A,E   ; + (phase-1)
STORE_5:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_5

    ; --- push each row to VRAM, skipping rows unchanged since last frame ---
    ; (Name table base is 1800h in SCREEN1 too, so these VRAM
    ;  addresses are identical to the SCREEN2 version.)

    ; row 0 -> VRAM 1A60h (screen row 19 - moved down from 1A40h/row18,
    ; see GROUND_ROW0)
    LD HL,NAMEBUF+0 : LD DE,PREVBUF+0 : LD B,32
DIFF_LOOP_0:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_0
    INC HL : INC DE
    DJNZ DIFF_LOOP_0
    JR ROWDONE_0
DIFFERENT_0:
    LD HL,NAMEBUF+0 : LD DE,PREVBUF+0 : LD BC,32 : LDIR
    LD HL,NAMEBUF+0
    DI
    LD A,60h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_0:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_0
ROWDONE_0:

    ; row 2 -> VRAM 1A80h (screen row 20) - NAMEBUF slot shifted from
    ; +64 to +32 (row1/TIER2_DIAMOND's slot removed, see GROUND_ROW0)
    LD HL,NAMEBUF+32 : LD DE,PREVBUF+32 : LD B,32
DIFF_LOOP_2:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_2
    INC HL : INC DE
    DJNZ DIFF_LOOP_2
    JR ROWDONE_2
DIFFERENT_2:
    LD HL,NAMEBUF+32 : LD DE,PREVBUF+32 : LD BC,32 : LDIR
    LD HL,NAMEBUF+32
    DI
    LD A,80h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_2:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_2
ROWDONE_2:

    ; row 3 -> VRAM 1AA0h (screen row 21) - NAMEBUF slot shifted from +96 to +64
    LD HL,NAMEBUF+64 : LD DE,PREVBUF+64 : LD B,32
DIFF_LOOP_3:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_3
    INC HL : INC DE
    DJNZ DIFF_LOOP_3
    JR ROWDONE_3
DIFFERENT_3:
    LD HL,NAMEBUF+64 : LD DE,PREVBUF+64 : LD BC,32 : LDIR
    LD HL,NAMEBUF+64
    DI
    LD A,A0h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_3:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_3
ROWDONE_3:

    ; row 4 -> VRAM 1AC0h (screen row 22) - NAMEBUF slot shifted from +128 to +96
    LD HL,NAMEBUF+96 : LD DE,PREVBUF+96 : LD B,32
DIFF_LOOP_4:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_4
    INC HL : INC DE
    DJNZ DIFF_LOOP_4
    JR ROWDONE_4
DIFFERENT_4:
    LD HL,NAMEBUF+96 : LD DE,PREVBUF+96 : LD BC,32 : LDIR
    LD HL,NAMEBUF+96
    DI
    LD A,C0h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_4:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_4
ROWDONE_4:

    ; row 5 -> VRAM 1AE0h (screen row 23, bottom row of screen) -
    ; NAMEBUF slot shifted from +160 to +128
    LD HL,NAMEBUF+128 : LD DE,PREVBUF+128 : LD B,32
DIFF_LOOP_5:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_5
    INC HL : INC DE
    DJNZ DIFF_LOOP_5
    JR ROWDONE_5
DIFFERENT_5:
    LD HL,NAMEBUF+128 : LD DE,PREVBUF+128 : LD BC,32 : LDIR
    LD HL,NAMEBUF+128
    DI
    LD A,E0h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_5:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_5
ROWDONE_5:

    ; ============================================================
    ; --- player ship: read joystick (BIOS), move, redraw ---
    ; --- full register save/restore around the BIOS calls: IX-only ---
    ; --- protection wasn't enough to stop VDP/sprite corruption,   ---
    ; --- so BC/DE/HL/IX/IY are all preserved this time.            ---
    ; ============================================================
    ; --- post-boss flyaway: once the BG-destruction sequence      ---
    ; --- finishes, there's a short beat (PLAYER_FLYAWAY_WAIT) where---
    ; --- the ship just sits still, then it auto-flies right,      ---
    ; --- accelerating, and ignores joystick input entirely until   ---
    ; --- it's off-screen, then stays hidden. ---
    LD A,(PLAYER_FLYAWAY)
    CP 1
    JR Z,PFA_MOVING
    CP 2
    JP Z,DIR_DONE
    LD A,(PLAYER_FLYAWAY_WAIT)
    OR A
    JR Z,PFA_NORMAL_INPUT
    DEC A
    LD (PLAYER_FLYAWAY_WAIT),A
    JR NZ,PFA_WAIT_STILL
    LD A,1 : LD (PLAYER_FLYAWAY),A
    XOR A : LD (PLAYER_FLYAWAY_DIST),A
PFA_WAIT_STILL:
    JP DIR_DONE
PFA_MOVING:
    ; gentle ramp for the first 32px: speed 1 for px0-7, 2 for 8-15,
    ; 3 for 16-23, 4 for 24-31 - then straight to cruise speed 8 for
    ; the rest of the flight.
    LD A,(PLAYER_FLYAWAY_DIST)
    CP 32
    JR NC,PFA_CRUISE
    LD B,1
    CP 8
    JR C,PFA_SPD_SET
    INC B
    CP 16
    JR C,PFA_SPD_SET
    INC B
    CP 24
    JR C,PFA_SPD_SET
    INC B
PFA_SPD_SET:
    LD A,B
    LD (PLAYER_FLYAWAY_SPD),A
    JR PFA_SPD_OK
PFA_CRUISE:
    LD A,8
    LD (PLAYER_FLYAWAY_SPD),A
PFA_SPD_OK:
    LD B,A
    LD A,(PLAYER_FLYAWAY_DIST) : ADD A,B : LD (PLAYER_FLYAWAY_DIST),A
    LD A,(PLAYERX)
    ADD A,B
    CP 248
    JR C,PFA_STILLGOING
    LD A,2 : LD (PLAYER_FLYAWAY),A
    LD A,248
PFA_STILLGOING:
    LD (PLAYERX),A
    ; engine "goooo" - low noise rumble on channel A, re-armed every
    ; frame so it stays sustained instead of decaying like a normal
    ; sound effect; left alone (and so left to decay away naturally)
    ; once the ship goes fully hidden.
    LD A,6 : OUT (PSG_ADDR),A
    LD A,18 : OUT (PSG_DATA),A
    LD A,10 : LD (SND_TIMER),A
    CALL PLAYER_PARTICLE_SPAWN
    JP DIR_DONE
PFA_NORMAL_INPUT:
    PUSH BC
    PUSH DE
    PUSH HL
    PUSH IX
    PUSH IY
    LD A,1 : CALL GTSTCK          ; port1 direction: 0=none,1=up,2=up-right,
                                   ; 3=right,4=down-right,5=down,6=down-left,
                                   ; 7=left,8=up-left
    LD (JOY_STICK),A
    LD A,1 : CALL GTTRIG          ; port1 trigger A (button A): 0=released, FFh=pressed
    LD (JOY_TRIG),A
    LD A,3 : CALL GTTRIG          ; port1 trigger B (button B): 0=released, FFh=pressed
    LD (JOY_TRIGB),A
    POP IY
    POP IX
    POP HL
    POP DE
    POP BC

    ; button B (bit5) fires once per press (rising edge), not while held
    XOR A : LD (FIREB_EDGE),A
    LD A,(JOY_TRIGB)
    OR A
    JR Z,FIREB_NOTPRESSED
    LD A,(JOY_TRIGB_PREV)
    OR A
    JR NZ,FIREB_NOTPRESSED
    LD A,1 : LD (FIREB_EDGE),A
FIREB_NOTPRESSED:
    LD A,(JOY_TRIGB) : LD (JOY_TRIGB_PREV),A

    LD A,(JOY_STICK)
    CP 1 : JR Z,DIR_UP
    CP 2 : JR Z,DIR_UPRIGHT
    CP 3 : JR Z,DIR_RIGHT
    CP 4 : JR Z,DIR_DOWNRIGHT
    CP 5 : JR Z,DIR_DOWN
    CP 6 : JR Z,DIR_DOWNLEFT
    CP 7 : JR Z,DIR_LEFT
    CP 8 : JR Z,DIR_UPLEFT
    JR DIR_DONE
DIR_UP:
    CALL MOVE_UP
    JR DIR_DONE
DIR_UPRIGHT:
    CALL MOVE_UP : CALL MOVE_RIGHT
    JR DIR_DONE
DIR_RIGHT:
    CALL MOVE_RIGHT
    JR DIR_DONE
DIR_DOWNRIGHT:
    CALL MOVE_DOWN : CALL MOVE_RIGHT
    JR DIR_DONE
DIR_DOWN:
    CALL MOVE_DOWN
    JR DIR_DONE
DIR_DOWNLEFT:
    CALL MOVE_DOWN : CALL MOVE_LEFT
    JR DIR_DONE
DIR_LEFT:
    CALL MOVE_LEFT
    JR DIR_DONE
DIR_UPLEFT:
    CALL MOVE_UP : CALL MOVE_LEFT
DIR_DONE:

    ; redraw ship: slot1=body, slot0=accent overlay (priority above ---
    ; body, drawn at PLAYERX+8, PLAYERY)
    DI
    LD A,04h : OUT (99h),A
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
    LD A,(PLAYERY) : SUB 8 : CALL PLAYER_DRAW_Y_ADJ : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(PLAYERX) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_SHIP : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_RED : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP

    LD A,00h : OUT (99h),A
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
    LD A,(PLAYERY) : SUB 8 : CALL PLAYER_DRAW_Y_ADJ : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(PLAYERX) : ADD A,8 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_ACCENT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_WHITE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP

    ; ============================================================
    ; --- fire: A button (joystick1 trigger1), up to 3 shots on  ---
    ; --- screen, with a 1-frame gap enforced between spawns so  ---
    ; --- holding the button fires intermittently (shot,gap,shot)---
    ; ============================================================
    LD A,(PLAYER_FLYAWAY)
    OR A
    EI
    JP NZ,FIRE_DONE
    LD A,(FIRE_COOLDOWN)
    OR A
    JR Z,CHECK_FIRE
    DEC A : LD (FIRE_COOLDOWN),A
    JP FIRE_DONE
CHECK_FIRE:
    LD A,(JOY_TRIG)
    OR A : JR NZ,FIRE_REQUESTED   ; A button: fires while held
    LD A,(FIREB_EDGE)
    OR A : JP Z,FIRE_DONE          ; B button: fires only on press edge
FIRE_REQUESTED:
    LD A,(BULLET0_ACT)
    OR A
    JR NZ,TRY_BULLET1
    LD A,1 : LD (BULLET0_ACT),A
    LD A,(PLAYERY) : ADD A,8 : SRL A : SRL A : SRL A : LD (BULLET0_ROW),A
    LD A,(PLAYERY) : ADD A,8 : AND 07h : LD (M_TMP),A
    CP 7
    JR NZ,BULLET0_NOCLAMP
    LD A,6 : LD (M_TMP),A
BULLET0_NOCLAMP:
    LD A,(BULLET0_ROW) : CP GROUND_ROW0
    JR C,BULLET0_BLUE
    JR Z,BULLET0_WHITE
    CP GROUND_ROW0+4
    JR Z,BULLET0_BROWN
    JR C,BULLET0_GREEN
    JR BULLET0_BLUE
BULLET0_GREEN:
    LD A,BULLET_PAT_GREEN
    JR BULLET0_GOTBASE
BULLET0_WHITE:
    LD A,BULLET_PAT_WHITE
    JR BULLET0_GOTBASE
BULLET0_BROWN:
    LD A,BULLET_PAT_BROWN
    JR BULLET0_GOTBASE
BULLET0_BLUE:
    LD A,BULLET_PAT_BLUE
BULLET0_GOTBASE:
    LD E,A
    LD A,(M_TMP) : ADD A,E
    LD (BULLET0_PAT),A
    LD A,(BULLET0_ROW) : LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD (BULLET0_ADDR),A
    LD A,(BULLET0_ROW) : LD E,A : LD D,ROWADDR_HI/256 : LD A,(DE) : LD (BULLET0_ADDR+1),A
    LD A,(PLAYERX) : ADD A,8
    JR NC,BULLET0_SPAWN_OK
    LD A,255
BULLET0_SPAWN_OK:
    SRL A : SRL A : SRL A
    LD (BULLET0_COL),A
    LD A,FIRE_COOLDOWN_LEN : LD (FIRE_COOLDOWN),A
    CALL SOUND_SHOT
    JP FIRE_DONE
TRY_BULLET1:
    LD A,(BULLET1_ACT)
    OR A
    JR NZ,TRY_BULLET2
    LD A,1 : LD (BULLET1_ACT),A
    LD A,(PLAYERY) : ADD A,8 : SRL A : SRL A : SRL A : LD (BULLET1_ROW),A
    LD A,(PLAYERY) : ADD A,8 : AND 07h : LD (M_TMP),A
    CP 7
    JR NZ,BULLET1_NOCLAMP
    LD A,6 : LD (M_TMP),A
BULLET1_NOCLAMP:
    LD A,(BULLET1_ROW) : CP GROUND_ROW0
    JR C,BULLET1_BLUE
    JR Z,BULLET1_WHITE
    CP GROUND_ROW0+4
    JR Z,BULLET1_BROWN
    JR C,BULLET1_GREEN
    JR BULLET1_BLUE
BULLET1_GREEN:
    LD A,BULLET_PAT_GREEN
    JR BULLET1_GOTBASE
BULLET1_WHITE:
    LD A,BULLET_PAT_WHITE
    JR BULLET1_GOTBASE
BULLET1_BROWN:
    LD A,BULLET_PAT_BROWN
    JR BULLET1_GOTBASE
BULLET1_BLUE:
    LD A,BULLET_PAT_BLUE
BULLET1_GOTBASE:
    LD E,A
    LD A,(M_TMP) : ADD A,E
    LD (BULLET1_PAT),A
    LD A,(BULLET1_ROW) : LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD (BULLET1_ADDR),A
    LD A,(BULLET1_ROW) : LD E,A : LD D,ROWADDR_HI/256 : LD A,(DE) : LD (BULLET1_ADDR+1),A
    LD A,(PLAYERX) : ADD A,8
    JR NC,BULLET1_SPAWN_OK
    LD A,255
BULLET1_SPAWN_OK:
    SRL A : SRL A : SRL A
    LD (BULLET1_COL),A
    LD A,FIRE_COOLDOWN_LEN : LD (FIRE_COOLDOWN),A
    CALL SOUND_SHOT
    JP FIRE_DONE
TRY_BULLET2:
    LD A,(BULLET2_ACT)
    OR A
    JP NZ,FIRE_DONE
    LD A,1 : LD (BULLET2_ACT),A
    LD A,(PLAYERY) : ADD A,8 : SRL A : SRL A : SRL A : LD (BULLET2_ROW),A
    LD A,(PLAYERY) : ADD A,8 : AND 07h : LD (M_TMP),A
    CP 7
    JR NZ,BULLET2_NOCLAMP
    LD A,6 : LD (M_TMP),A
BULLET2_NOCLAMP:
    LD A,(BULLET2_ROW) : CP GROUND_ROW0
    JR C,BULLET2_BLUE
    JR Z,BULLET2_WHITE
    CP GROUND_ROW0+4
    JR Z,BULLET2_BROWN
    JR C,BULLET2_GREEN
    JR BULLET2_BLUE
BULLET2_GREEN:
    LD A,BULLET_PAT_GREEN
    JR BULLET2_GOTBASE
BULLET2_WHITE:
    LD A,BULLET_PAT_WHITE
    JR BULLET2_GOTBASE
BULLET2_BROWN:
    LD A,BULLET_PAT_BROWN
    JR BULLET2_GOTBASE
BULLET2_BLUE:
    LD A,BULLET_PAT_BLUE
BULLET2_GOTBASE:
    LD E,A
    LD A,(M_TMP) : ADD A,E
    LD (BULLET2_PAT),A
    LD A,(BULLET2_ROW) : LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD (BULLET2_ADDR),A
    LD A,(BULLET2_ROW) : LD E,A : LD D,ROWADDR_HI/256 : LD A,(DE) : LD (BULLET2_ADDR+1),A
    LD A,(PLAYERX) : ADD A,8
    JR NC,BULLET2_SPAWN_OK
    LD A,255
BULLET2_SPAWN_OK:
    SRL A : SRL A : SRL A
    LD (BULLET2_COL),A
    LD A,FIRE_COOLDOWN_LEN : LD (FIRE_COOLDOWN),A
    CALL SOUND_SHOT
FIRE_DONE:

    ; --- Enemy2 instances A and B: each internally no-ops if not ---
    ; --- active, so calling both unconditionally every frame is  ---
    ; --- always safe and lets them run fully concurrently.       ---
    CALL ENEMY_COMPLEX_STEP_A
    CALL ENEMY_COMPLEX_STEP_B
ENEMY_SECTION_DONE:

    ; --- destroy-animation (3 slots) and sound fade, once per frame ---
    LD A,(ANIM_BASE+0)
    OR A
    JP Z,ANIM0_DONE
    LD A,(ANIM_BASE+2)
    DEC A
    LD (ANIM_BASE+2),A
    JP NZ,ANIM0_DONE
    LD A,(ANIM_BASE+1)
    CP 1
    JR NZ,ANIM0_FINISH
    LD A,2 : LD (ANIM_BASE+1),A
    LD A,ANIM_FRAME_LEN : LD (ANIM_BASE+2),A
    LD A,(ANIM_BASE+7) : LD (ANIM_TMP_VAL),A
    JR ANIM0_WRITE
ANIM0_FINISH:
    LD A,(ANIM_BASE+5) : LD (ANIM_TMP_VAL),A
    XOR A : LD (ANIM_BASE+0),A
ANIM0_WRITE:
    LD A,(ANIM_BASE+3) : LD (ANIM_TMP_ROW),A
    LD A,(ANIM_BASE+4) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
ANIM0_DONE:

    LD A,(ANIM_BASE+8)
    OR A
    JP Z,ANIM1_DONE
    LD A,(ANIM_BASE+10)
    DEC A
    LD (ANIM_BASE+10),A
    JP NZ,ANIM1_DONE
    LD A,(ANIM_BASE+9)
    CP 1
    JR NZ,ANIM1_FINISH
    LD A,2 : LD (ANIM_BASE+9),A
    LD A,ANIM_FRAME_LEN : LD (ANIM_BASE+10),A
    LD A,(ANIM_BASE+15) : LD (ANIM_TMP_VAL),A
    JR ANIM1_WRITE
ANIM1_FINISH:
    LD A,(ANIM_BASE+13) : LD (ANIM_TMP_VAL),A
    XOR A : LD (ANIM_BASE+8),A
ANIM1_WRITE:
    LD A,(ANIM_BASE+11) : LD (ANIM_TMP_ROW),A
    LD A,(ANIM_BASE+12) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
ANIM1_DONE:

    LD A,(ANIM_BASE+16)
    OR A
    JP Z,ANIM2_DONE
    LD A,(ANIM_BASE+18)
    DEC A
    LD (ANIM_BASE+18),A
    JP NZ,ANIM2_DONE
    LD A,(ANIM_BASE+17)
    CP 1
    JR NZ,ANIM2_FINISH
    LD A,2 : LD (ANIM_BASE+17),A
    LD A,ANIM_FRAME_LEN : LD (ANIM_BASE+18),A
    LD A,(ANIM_BASE+23) : LD (ANIM_TMP_VAL),A
    JR ANIM2_WRITE
ANIM2_FINISH:
    LD A,(ANIM_BASE+21) : LD (ANIM_TMP_VAL),A
    XOR A : LD (ANIM_BASE+16),A
ANIM2_WRITE:
    LD A,(ANIM_BASE+19) : LD (ANIM_TMP_ROW),A
    LD A,(ANIM_BASE+20) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
ANIM2_DONE:

    CALL SOUND_UPDATE
    LD A,(PLAYER_FLYAWAY)
    OR A
    CALL NZ,PLAYER_PARTICLE_FADE

    ; --- enemy3: spawn attempt + advance/redraw all 8 pool slots ---
    CALL ENEMY3_TRY_SPAWN
    LD IX,ENEMY3_POOL    : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+11 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+22 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+33 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+44 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+55 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+66 : CALL ENEMY3_UPDATE_SLOT
    LD IX,ENEMY3_POOL+77 : CALL ENEMY3_UPDATE_SLOT
    ; --- unified sprite-enemy buffer: advance every active slot,   ---
    ; --- regardless of which movement algorithm (BEHAVIOR) it uses ---
    CALL ENEMY_POOL_UPDATE_ALL

    ; ============================================================
    ; --- shots: advance 1 character (8 dots) per frame. Erasing  ---
    ; --- restores whatever the ground scroller currently shows   ---
    ; --- at that cell (if the shot is over the 5-row scroller),  ---
    ; --- or the sky blank otherwise - so the shot never leaves a ---
    ; --- hole in the terrain behind it.                          ---
    ; ============================================================
    ; shot 0
    LD A,(BULLET0_ACT)
    OR A
    JP Z,BULLET0_NEXT
    LD A,(BULLET0_COL) : LD B,A
    LD A,(BULLET0_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_A
    OR A
    JR NZ,BULLET0_ISHIT
    LD A,(BULLET0_COL) : LD B,A
    LD A,(BULLET0_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_B
    OR A
    JR NZ,BULLET0_ISHIT
    CALL CHECK_BULLET_VS_ENEMY3
    OR A
    JR NZ,BULLET0_ISHIT
    CALL CHECK_BULLET_VS_ENEMY_POOL
    OR A
    JR Z,BULLET0_NOHIT
BULLET0_ISHIT:
    LD A,(BULLET0_ROW) : CP GROUND_ROW0
    JR C,BULLET0_HITERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET0_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET0_HITERASE_GOT
BULLET0_HITERASE_SKY:
    LD HL,(SKY_VEC_0H) : PUSH HL : RET
BULLET0_HITERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET0_ADDR)
    LD A,(BULLET0_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET0_ACT),A
    EI
    JP BULLET0_NEXT
BULLET0_NOHIT:
    LD A,(BULLET0_ROW) : CP GROUND_ROW0
    JR C,BULLET0_ERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET0_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET0_ERASE_GOT
BULLET0_ERASE_SKY:
    LD HL,(SKY_VEC_0E) : PUSH HL : RET
BULLET0_ERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET0_ADDR)
    LD A,(BULLET0_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(BULLET0_COL) : INC A : LD (BULLET0_COL),A
    CP BULLET_MAXCOL+1
    EI
    JR NC,BULLET0_OFF
    LD HL,(BULLET0_ADDR)
    LD A,(BULLET0_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(BULLET0_PAT) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    JP BULLET0_NEXT
BULLET0_OFF:
    XOR A : LD (BULLET0_ACT),A
BULLET0_NEXT:

    ; shot 1
    LD A,(BULLET1_ACT)
    OR A
    JP Z,BULLET1_NEXT
    LD A,(BULLET1_COL) : LD B,A
    LD A,(BULLET1_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_A
    OR A
    JR NZ,BULLET1_ISHIT
    LD A,(BULLET1_COL) : LD B,A
    LD A,(BULLET1_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_B
    OR A
    JR NZ,BULLET1_ISHIT
    CALL CHECK_BULLET_VS_ENEMY3
    OR A
    JR NZ,BULLET1_ISHIT
    CALL CHECK_BULLET_VS_ENEMY_POOL
    OR A
    JR Z,BULLET1_NOHIT
BULLET1_ISHIT:
    LD A,(BULLET1_ROW) : CP GROUND_ROW0
    JR C,BULLET1_HITERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET1_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET1_HITERASE_GOT
BULLET1_HITERASE_SKY:
    LD HL,(SKY_VEC_1H) : PUSH HL : RET
BULLET1_HITERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET1_ADDR)
    LD A,(BULLET1_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET1_ACT),A
    EI
    JP BULLET1_NEXT
BULLET1_NOHIT:
    LD A,(BULLET1_ROW) : CP GROUND_ROW0
    JR C,BULLET1_ERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET1_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET1_ERASE_GOT
BULLET1_ERASE_SKY:
    LD HL,(SKY_VEC_1E) : PUSH HL : RET
BULLET1_ERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET1_ADDR)
    LD A,(BULLET1_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(BULLET1_COL) : INC A : LD (BULLET1_COL),A
    CP BULLET_MAXCOL+1
    EI
    JR NC,BULLET1_OFF
    LD HL,(BULLET1_ADDR)
    LD A,(BULLET1_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(BULLET1_PAT) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    JP BULLET1_NEXT
BULLET1_OFF:
    XOR A : LD (BULLET1_ACT),A
BULLET1_NEXT:

    ; shot 2
    LD A,(BULLET2_ACT)
    OR A
    JP Z,BULLET2_NEXT
    LD A,(BULLET2_COL) : LD B,A
    LD A,(BULLET2_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_A
    OR A
    JR NZ,BULLET2_ISHIT
    LD A,(BULLET2_COL) : LD B,A
    LD A,(BULLET2_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_B
    OR A
    JR NZ,BULLET2_ISHIT
    CALL CHECK_BULLET_VS_ENEMY3
    OR A
    JR NZ,BULLET2_ISHIT
    CALL CHECK_BULLET_VS_ENEMY_POOL
    OR A
    JR Z,BULLET2_NOHIT
BULLET2_ISHIT:
    LD A,(BULLET2_ROW) : CP GROUND_ROW0
    JR C,BULLET2_HITERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET2_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET2_HITERASE_GOT
BULLET2_HITERASE_SKY:
    LD HL,(SKY_VEC_2H) : PUSH HL : RET
BULLET2_HITERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET2_ADDR)
    LD A,(BULLET2_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET2_ACT),A
    EI
    JP BULLET2_NEXT
BULLET2_NOHIT:
    LD A,(BULLET2_ROW) : CP GROUND_ROW0
    JR C,BULLET2_ERASE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF : ADD HL,DE
    LD A,(BULLET2_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR BULLET2_ERASE_GOT
BULLET2_ERASE_SKY:
    LD HL,(SKY_VEC_2E) : PUSH HL : RET
BULLET2_ERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLET2_ADDR)
    LD A,(BULLET2_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(BULLET2_COL) : INC A : LD (BULLET2_COL),A
    CP BULLET_MAXCOL+1
    EI
    JR NC,BULLET2_OFF
    LD HL,(BULLET2_ADDR)
    LD A,(BULLET2_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(BULLET2_PAT) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    JP BULLET2_NEXT
BULLET2_OFF:
    XOR A : LD (BULLET2_ACT),A
BULLET2_NEXT:

    JP MAINLOOP

; ============================================================
; player movement helpers (called from the dispatch above)
; ============================================================
MOVE_UP:
    LD A,(PLAYERY)
    SUB PLAYER_MINY
    CP PLAYER_SPEED
    JR C,MOVE_UP_CLAMP
    LD A,(PLAYERY)
    SUB PLAYER_SPEED
    LD (PLAYERY),A
    RET
MOVE_UP_CLAMP:
    LD A,PLAYER_MINY
    LD (PLAYERY),A
    RET

MOVE_DOWN:
    LD A,(PLAYERY)
    ADD A,PLAYER_SPEED
    CP PLAYER_MAXY+1
    JR C,MOVE_DOWN_OK
    LD A,PLAYER_MAXY
MOVE_DOWN_OK:
    LD (PLAYERY),A
    RET

MOVE_LEFT:
    LD A,(PLAYERX)
    CP PLAYER_SPEED
    JR C,MOVE_LEFT_CLAMP
    SUB PLAYER_SPEED
    LD (PLAYERX),A
    RET
MOVE_LEFT_CLAMP:
    XOR A
    LD (PLAYERX),A
    RET

MOVE_RIGHT:
    LD A,(PLAYERX)
    ADD A,PLAYER_SPEED
    CP PLAYER_MAXX+1
    JR C,MOVE_RIGHT_OK
    LD A,PLAYER_MAXX
MOVE_RIGHT_OK:
    LD (PLAYERX),A
    RET

; Input: A = the normal Y draw value. Output: A = 209 (fully
; off-screen, past the Y=208 stop-sentinel) once the post-boss
; flyaway has finished; otherwise A is passed through unchanged.
PLAYER_DRAW_Y_ADJ:
    PUSH BC
    LD B,A
    LD A,(PLAYER_FLYAWAY)
    CP 2
    JR NZ,PDYA_NORMAL
    LD A,209
    JR PDYA_DONE
PDYA_NORMAL:
    LD A,B
PDYA_DONE:
    POP BC
    RET

; Called every frame while the ship is actively flying away. Looks
; for a free slot (0 or 1) and, if one's free, launches a new
; particle from the ship's back at a small random angle around
; due-left (a 3-way DY spread table approximates +-30 deg at this
; pixel resolution) - DX is fixed at -2/frame, DY in {-1,0,1}, so
; each particle covers its ~32px lifetime in 16 frames. With only 2
; slots and a 16-frame life, actual spawns end up gated by whichever
; slot frees up next, even though this is called every frame.
PLAYER_PARTICLE_SPAWN:
    LD A,(PARTICLE_SPAWN_COOLDOWN)
    OR A
    JR Z,PPS_COOLDOWN_OK
    DEC A : LD (PARTICLE_SPAWN_COOLDOWN),A
    RET
PPS_COOLDOWN_OK:
    LD A,(PARTICLE_ACT+0)
    OR A
    JR Z,PPS_USE0
    LD A,(PARTICLE_ACT+1)
    OR A
    RET NZ
    LD C,1
    JR PPS_SPAWN
PPS_USE0:
    LD C,0
PPS_SPAWN:
    LD A,4 : LD (PARTICLE_SPAWN_COOLDOWN),A
    LD HL,PARTICLE_ACT : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),8

    LD A,(PLAYERX)
    SUB 4
    JR NC,PPS_XOK
    XOR A
PPS_XOK:
    LD HL,PARTICLE_X : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),A

    LD A,(PLAYERY)
    LD HL,PARTICLE_Y : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),A

    LD A,0FCh                        ; dx = -4, straight back, fast
    LD HL,PARTICLE_DX : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),A

    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 3
    CP 3 : JR NZ,PPS_DYIDX_OK
    XOR A
PPS_DYIDX_OK:
    LD D,0 : LD E,A
    LD HL,PARTICLE_DY_TABLE : ADD HL,DE
    LD A,(HL)
    LD HL,PARTICLE_DY : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),A

    LD A,SPR_WHITE
    LD HL,PARTICLE_COL : LD D,0 : LD E,C : ADD HL,DE
    LD (HL),A
    RET

; -1/0/+1, indexed by a small random pick - the +-30ish degree
; spread around due-left (DX=-2 is the dominant component).
PARTICLE_DY_TABLE:
    DB 0FFh,00h,01h

; Called every frame, unconditionally: ages, moves, and redraws
; every active particle slot, hiding one the instant its life
; reaches 0. Runs regardless of PLAYER_FLYAWAY so already-spawned
; particles keep travelling/fading even after the ship itself has
; gone hidden. Bails out immediately (before touching the VDP at
; all) if both slots are idle, which is the case for the entire rest
; of the game outside the flyaway - important, since this is called
; unconditionally every single frame.
PLAYER_PARTICLE_FADE:
    LD A,(PARTICLE_ACT+0)
    LD B,A
    LD A,(PARTICLE_ACT+1)
    OR B
    RET Z

    LD C,0
PPF_LOOP:
    LD HL,PARTICLE_ACT : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL)
    OR A
    JP Z,PPF_SKIP
    DEC A : LD (HL),A

    LD HL,PARTICLE_DX : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : LD B,A
    LD HL,PARTICLE_X : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : ADD A,B : LD (HL),A
    LD HL,PARTICLE_DY : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : LD B,A
    LD HL,PARTICLE_Y : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : ADD A,B : LD (HL),A

    LD A,EXPLOSION_SPR_BASE : ADD A,C
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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

    LD HL,PARTICLE_ACT : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL)
    OR A
    EI
    JR NZ,PPF_VISIBLE
    DI
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    JP PPF_SKIP
PPF_VISIBLE:
    LD HL,PARTICLE_Y : LD D,0 : LD E,C : ADD HL,DE
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,PARTICLE_X : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_PARTICLE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,PARTICLE_COL : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
PPF_SKIP:
    INC C
    LD A,C
    CP 2
    JP NZ,PPF_LOOP
    RET

; ============================================================
; enemy formation helpers
; ============================================================
; Input: B = bullet column (0-31), C = bullet row (0-23),
;        D = target quadrant's X (top-left, 8 wide),
;        E = target quadrant's Y (top-left, 8 tall)
; Output: A = 1 if the bullet's 8x8 cell overlaps the 8x8
; quadrant, else A = 0. Trashes H,L.
QUAD_HIT_TEST:
    LD A,B : ADD A,A : ADD A,A : ADD A,A : LD H,A   ; H = bullet left edge (col*8)
    LD A,C : ADD A,A : ADD A,A : ADD A,A : LD L,A   ; L = bullet top edge (row*8)
    LD A,H : ADD A,7
    CP D
    JR C,QUAD_HIT_NO       ; bullet's right edge is left of quad's left edge
    LD A,D : ADD A,7
    CP H
    JR C,QUAD_HIT_NO       ; quad's right edge is left of bullet's left edge
    LD A,L : ADD A,7
    CP E
    JR C,QUAD_HIT_NO       ; bullet's bottom edge is above quad's top edge
    LD A,E : ADD A,7
    CP L
    JR C,QUAD_HIT_NO       ; quad's bottom edge is above bullet's top edge
    LD A,1
    RET
QUAD_HIT_NO:
    XOR A
    RET

; Rewrites one unit's 32-byte 16x16 sprite pattern to match its
; current TOP/BOT alive flags: top-left shows the asterisk if TOP
; is alive (else blank), bottom-right shows it if BOT is alive
; (else blank); bottom-left/top-right are always blank.
; Input: HL = VRAM address of this unit's 32-byte pattern block,
;        DE = address of this unit's TOP alive-flag byte,
;        IX = address of this unit's BOT alive-flag byte
; Trashes A,B,HL.
REDRAW_UNIT_PATTERN:
    LD A,L
    DI
    OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,H : OR 40h
    OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(DE)
    OR A
    EI
    JR Z,RU_TL_BLANK
    LD HL,ASTERISK_PATTERN : LD B,8
RU_TL_LOOP:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    INC HL : DJNZ RU_TL_LOOP
    JR RU_BL
RU_TL_BLANK:
    LD B,8
RU_TL_BLANK_LOOP:
    DI
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
    DJNZ RU_TL_BLANK_LOOP
RU_BL:
    LD B,8
RU_BL_LOOP:
    DI
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
    DJNZ RU_BL_LOOP
    LD B,8
RU_TR_LOOP:
    DI
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
    DJNZ RU_TR_LOOP
    LD A,(IX+0)
    OR A
    JR Z,RU_BR_BLANK
    LD HL,ASTERISK_PATTERN : LD B,8
RU_BR_LOOP:
    DI
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    INC HL : DJNZ RU_BR_LOOP
    RET
RU_BR_BLANK:
    LD B,8
RU_BR_BLANK_LOOP:
    DI
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
    DJNZ RU_BR_BLANK_LOOP
    RET

CHECK_BULLET_VS_FORMATION_A:
    LD A,(E2A_U0_STATE) : CP 1 : JR NZ,CBF_SKIP2_A
    LD A,(E2A_U0_TOP) : OR A : JR Z,CBF_SKIP1_A
    LD A,(E2A_U0_X) : LD D,A
    LD A,(E2A_U0_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U0_TOP_A
CBF_SKIP1_A:
    LD A,(E2A_U0_BOT) : OR A : JR Z,CBF_SKIP2_A
    LD A,(E2A_U0_X) : ADD A,8 : LD D,A
    LD A,(E2A_U0_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U0_BOT_A
CBF_SKIP2_A:
    LD A,(E2A_U1_STATE) : CP 1 : JR NZ,CBF_SKIP4_A
    LD A,(E2A_U1_TOP) : OR A : JR Z,CBF_SKIP3_A
    LD A,(E2A_U1_X) : LD D,A
    LD A,(E2A_U1_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U1_TOP_A
CBF_SKIP3_A:
    LD A,(E2A_U1_BOT) : OR A : JR Z,CBF_SKIP4_A
    LD A,(E2A_U1_X) : ADD A,8 : LD D,A
    LD A,(E2A_U1_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U1_BOT_A
CBF_SKIP4_A:
    LD A,(E2A_U2_STATE) : CP 1 : JP NZ,CBF_MISS_A
    LD A,(E2A_U2_TOP) : OR A : JR Z,CBF_SKIP5_A
    LD A,(E2A_U2_X) : LD D,A
    LD A,(E2A_U2_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U2_TOP_A
CBF_SKIP5_A:
    LD A,(E2A_U2_BOT) : OR A : JP Z,CBF_MISS_A
    LD A,(E2A_U2_X) : ADD A,8 : LD D,A
    LD A,(E2A_U2_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP Z,CBF_MISS_A
CBF_KILL_U2_BOT_A:
    XOR A : LD (E2A_U2_BOT),A
    PUSH DE
    LD HL,SPRPAT+320 : LD DE,E2A_U2_TOP : LD IX,E2A_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U0_TOP_A:
    XOR A : LD (E2A_U0_TOP),A
    PUSH DE
    LD HL,SPRPAT+256 : LD DE,E2A_U0_TOP : LD IX,E2A_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U0_BOT_A:
    XOR A : LD (E2A_U0_BOT),A
    PUSH DE
    LD HL,SPRPAT+256 : LD DE,E2A_U0_TOP : LD IX,E2A_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U1_TOP_A:
    XOR A : LD (E2A_U1_TOP),A
    PUSH DE
    LD HL,SPRPAT+288 : LD DE,E2A_U1_TOP : LD IX,E2A_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U1_BOT_A:
    XOR A : LD (E2A_U1_BOT),A
    PUSH DE
    LD HL,SPRPAT+288 : LD DE,E2A_U1_TOP : LD IX,E2A_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U2_TOP_A:
    XOR A : LD (E2A_U2_TOP),A
    PUSH DE
    LD HL,SPRPAT+320 : LD DE,E2A_U2_TOP : LD IX,E2A_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_MISS_A:
    XOR A
    RET

CHECK_BULLET_VS_FORMATION_B:
    LD A,(E2B_U0_STATE) : CP 1 : JR NZ,CBF_SKIP2_B
    LD A,(E2B_U0_TOP) : OR A : JR Z,CBF_SKIP1_B
    LD A,(E2B_U0_X) : LD D,A
    LD A,(E2B_U0_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U0_TOP_B
CBF_SKIP1_B:
    LD A,(E2B_U0_BOT) : OR A : JR Z,CBF_SKIP2_B
    LD A,(E2B_U0_X) : ADD A,8 : LD D,A
    LD A,(E2B_U0_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U0_BOT_B
CBF_SKIP2_B:
    LD A,(E2B_U1_STATE) : CP 1 : JR NZ,CBF_SKIP4_B
    LD A,(E2B_U1_TOP) : OR A : JR Z,CBF_SKIP3_B
    LD A,(E2B_U1_X) : LD D,A
    LD A,(E2B_U1_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U1_TOP_B
CBF_SKIP3_B:
    LD A,(E2B_U1_BOT) : OR A : JR Z,CBF_SKIP4_B
    LD A,(E2B_U1_X) : ADD A,8 : LD D,A
    LD A,(E2B_U1_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U1_BOT_B
CBF_SKIP4_B:
    LD A,(E2B_U2_STATE) : CP 1 : JP NZ,CBF_MISS_B
    LD A,(E2B_U2_TOP) : OR A : JR Z,CBF_SKIP5_B
    LD A,(E2B_U2_X) : LD D,A
    LD A,(E2B_U2_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP NZ,CBF_KILL_U2_TOP_B
CBF_SKIP5_B:
    LD A,(E2B_U2_BOT) : OR A : JP Z,CBF_MISS_B
    LD A,(E2B_U2_X) : ADD A,8 : LD D,A
    LD A,(E2B_U2_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JP Z,CBF_MISS_B
CBF_KILL_U2_BOT_B:
    XOR A : LD (E2B_U2_BOT),A
    PUSH DE
    LD HL,SPRPAT+480 : LD DE,E2B_U2_TOP : LD IX,E2B_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U0_TOP_B:
    XOR A : LD (E2B_U0_TOP),A
    PUSH DE
    LD HL,SPRPAT+416 : LD DE,E2B_U0_TOP : LD IX,E2B_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U0_BOT_B:
    XOR A : LD (E2B_U0_BOT),A
    PUSH DE
    LD HL,SPRPAT+416 : LD DE,E2B_U0_TOP : LD IX,E2B_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U1_TOP_B:
    XOR A : LD (E2B_U1_TOP),A
    PUSH DE
    LD HL,SPRPAT+448 : LD DE,E2B_U1_TOP : LD IX,E2B_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U1_BOT_B:
    XOR A : LD (E2B_U1_BOT),A
    PUSH DE
    LD HL,SPRPAT+448 : LD DE,E2B_U1_TOP : LD IX,E2B_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_KILL_U2_TOP_B:
    XOR A : LD (E2B_U2_TOP),A
    PUSH DE
    LD HL,SPRPAT+480 : LD DE,E2B_U2_TOP : LD IX,E2B_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    POP DE
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    LD A,1
    RET
CBF_MISS_B:
    XOR A
    RET

; Input: D = destroyed quadrant's X (pixel), E = destroyed quadrant's
; Y (pixel). Picks the next explosion-animation slot (round robin
; among 3), snapshots what's currently at that nametable cell (so it
; can be restored later), resolves the yellow/red x row-color codes,
; shows frame 1, and plays the destroy sound.
TRIGGER_EXPLOSION:
    LD A,(ANIM_BASE+0)
    OR A
    JR Z,TE_PICK0
    LD A,(ANIM_BASE+8)
    OR A
    JR Z,TE_PICK1
    LD A,(ANIM_BASE+16)
    OR A
    JR Z,TE_PICK2
    LD A,(ANIM_RR)
    OR A
    JR Z,TE_PICK0
    CP 1
    JR Z,TE_PICK1
    JR TE_PICK2
TE_PICK0:
    LD IX,ANIM_BASE
    JR TE_ADVANCE_RR
TE_PICK1:
    LD IX,ANIM_BASE+8
    JR TE_ADVANCE_RR
TE_PICK2:
    LD IX,ANIM_BASE+16
TE_ADVANCE_RR:
    LD A,(ANIM_RR)
    INC A
    CP 3
    JR C,TE_RR_OK
    XOR A
TE_RR_OK:
    LD (ANIM_RR),A

    ; if the chosen slot was still mid-animation, restore its old
    ; cell now (using its still-intact old ROW/COL/SAVED) before we
    ; overwrite it below - otherwise that cell would be left showing
    ; a stale anim frame forever.
    LD A,(IX+0)
    OR A
    JR Z,TE_NORESTORE
    PUSH DE
    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : LD (ANIM_TMP_COL),A
    LD A,(IX+5) : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    POP DE
TE_NORESTORE:

    LD A,E : SRL A : SRL A : SRL A : LD (IX+3),A   ; ROW
    LD A,D : SRL A : SRL A : SRL A : LD (IX+4),A   ; COL

    ; SAVED = current value at that cell (BLANKCODE if above the
    ; 5-row ground scroller, else the NAMEBUF mirror)
    LD A,(IX+3) : CP GROUND_ROW0
    JR C,TE_SAVE_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD L,A : LD H,0
    LD DE,NAMEBUF
    ADD HL,DE
    LD A,(IX+4) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR TE_SAVE_GOT
TE_SAVE_SKY:
    LD A,BLANKCODE
TE_SAVE_GOT:
    LD (IX+5),A

    ; resolve CODE1/CODE2 from the row's color class (same split as shots)
    LD A,(IX+3) : CP GROUND_ROW0
    JR C,TE_BLUE
    JR Z,TE_WHITE
    CP GROUND_ROW0+4
    JR Z,TE_BROWN
    JR C,TE_GREEN
    JR TE_BLUE
TE_GREEN:
    LD A,ANIM1_GREEN : LD (IX+6),A
    LD A,ANIM2_GREEN : LD (IX+7),A
    JR TE_GOTCOLOR
TE_WHITE:
    LD A,ANIM1_WHITE : LD (IX+6),A
    LD A,ANIM2_WHITE : LD (IX+7),A
    JR TE_GOTCOLOR
TE_BROWN:
    LD A,ANIM1_BROWN : LD (IX+6),A
    LD A,ANIM2_BROWN : LD (IX+7),A
    JR TE_GOTCOLOR
TE_BLUE:
    LD A,ANIM1_BLUE : LD (IX+6),A
    LD A,ANIM2_BLUE : LD (IX+7),A
TE_GOTCOLOR:
    LD A,1 : LD (IX+1),A                ; PHASE=1
    LD A,ANIM_FRAME_LEN : LD (IX+2),A    ; TIMER (halved back down from ANIM_FRAME_LEN*2)
    LD A,1 : LD (IX+0),A                ; ACTIVE=1

    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : LD (ANIM_TMP_COL),A
    LD A,(IX+6) : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL

    CALL SOUND_DESTROY
    RET

; Writes ANIM_TMP_VAL to the nametable cell at (ANIM_TMP_ROW,
; ANIM_TMP_COL): updates the NAMEBUF mirror too if that row is
; within the 5-row ground scroller. Trashes A,H,L,DE.
; --- DEBUG: shows BIOS joystick results at row0 (top-center):        ---
; --- col15 = JOY_STICK (GTSTCK, 0=none..8=up-left), col17 = JOY_TRIG ---
; --- (GTTRIG, 0=released/1=pressed). Remove this call + routine     ---
; --- once the trigger issue is diagnosed.                           ---
WRITE_ANIM_CELL:
    LD A,(ANIM_TMP_ROW)
    CP GROUND_ROW0
    JR C,WAC_SKIPBUF
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF
    ADD HL,DE
    LD A,(ANIM_TMP_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(ANIM_TMP_VAL)
    LD (HL),A
WAC_SKIPBUF:
    LD A,(ANIM_TMP_ROW) : LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD (ANIM_ADDR_TMP),A
    LD A,(ANIM_TMP_ROW) : LD E,A : LD D,ROWADDR_HI/256 : LD A,(DE) : LD (ANIM_ADDR_TMP+1),A
    LD HL,(ANIM_ADDR_TMP)
    LD A,(ANIM_TMP_COL) : LD E,A : LD D,0 : ADD HL,DE
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
    LD A,(ANIM_TMP_VAL) : OUT (98h),A
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

; PSG (AY-3-8910-compatible) sound effects: channel A = noise-only
; (destroy "boom"), channel C = tone-only (shot "chun" blip), both
; enabled once at INIT. SND_TIMER/SND_TIMER_C double as both the
; frame countdown and that channel's volume (0-15), so each sound
; fades out on its own as it counts down to 0.
SOUND_SHOT:
    LD A,4 : OUT (PSG_ADDR),A
    LD A,30 : OUT (PSG_DATA),A    ; channel C tone period -> bright "chun" pitch
    LD A,5 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A      ; coarse tune bits = 0
    LD A,12 : LD (SND_TIMER_C),A
    RET
SOUND_DESTROY:
    LD A,6 : OUT (PSG_ADDR),A
    LD A,20 : OUT (PSG_DATA),A    ; low, coarse noise period = short "boom"
    LD A,15 : LD (SND_TIMER),A
    RET
; metallic "kin" ping for a non-lethal pod hit - reuses channel C
; (same as the player's own shot) but at a much higher pitch so it
; reads as a distinct sound.
SOUND_POD_HIT:
    LD A,4 : OUT (PSG_ADDR),A
    LD A,10 : OUT (PSG_DATA),A
    LD A,5 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,10 : LD (SND_TIMER_C),A
    RET

SOUND_POD_FIRE:
    LD A,2 : OUT (PSG_ADDR),A
    LD A,244 : OUT (PSG_DATA),A   ; channel B tone period fine byte
    LD A,3 : OUT (PSG_ADDR),A
    LD A,2 : OUT (PSG_DATA),A     ; coarse byte -> period=756, much lower "don"
    LD A,15 : LD (SND_TIMER_B),A
    RET
SOUND_UPDATE:
    LD A,(SND_TIMER)
    LD B,A
    LD A,8 : OUT (PSG_ADDR),A     ; R8 = channel A volume
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER)
    OR A
    JR Z,SOUND_UPDATE_B
    DEC A
    LD (SND_TIMER),A
SOUND_UPDATE_B:
    LD A,(SND_TIMER_B)
    LD B,A
    LD A,9 : OUT (PSG_ADDR),A     ; R9 = channel B volume
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER_B)
    OR A
    JR Z,SOUND_UPDATE_C
    DEC A
    LD (SND_TIMER_B),A
SOUND_UPDATE_C:
    LD A,(SND_TIMER_C)
    LD B,A
    LD A,10 : OUT (PSG_ADDR),A    ; R10 = channel C volume
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER_C)
    OR A
    RET Z
    DEC A
    LD (SND_TIMER_C),A
    RET

; Converts GAME_TICK (mod 1000) to 3 decimal digits and draws them
; at the top-right of the screen (row0, cols29-31).
GAME_TICK_DISPLAY:
    LD HL,(GAME_TICK)
GTD_MOD1000:
    LD DE,1000
    OR A
    SBC HL,DE
    JR NC,GTD_MOD1000
    ADD HL,DE

    LD B,0
GTD_H100:
    LD DE,100
    OR A
    SBC HL,DE
    JR C,GTD_H100_DONE
    INC B
    JR GTD_H100
GTD_H100_DONE:
    ADD HL,DE

    LD C,0
GTD_T10:
    LD DE,10
    OR A
    SBC HL,DE
    JR C,GTD_T10_DONE
    INC C
    JR GTD_T10
GTD_T10_DONE:
    ADD HL,DE
    LD A,L : LD (GTD_ONES_TMP),A   ; save before WRITE_ANIM_CELL clobbers HL below

    XOR A : LD (ANIM_TMP_ROW),A
    LD A,29 : LD (ANIM_TMP_COL),A
    LD A,B : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,30 : LD (ANIM_TMP_COL),A
    LD A,C : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,31 : LD (ANIM_TMP_COL),A
    LD A,(GTD_ONES_TMP) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    RET

; Extracts SCORE's 5 low decimal digits (ten-thousands..ones) into
; SCORE_DIGITS, then draws all 8 digits (3 fixed leading zeros +
; those 5) at row0, cols0-7 (top-left, fixed width).
SCORE_DISPLAY:
    LD HL,(SCORE)
    LD B,0
SD_TT:
    LD DE,10000
    OR A
    SBC HL,DE
    JR C,SD_TT_DONE
    INC B
    JR SD_TT
SD_TT_DONE:
    ADD HL,DE
    LD A,B : LD (SCORE_DIGITS+0),A

    LD B,0
SD_TH:
    LD DE,1000
    OR A
    SBC HL,DE
    JR C,SD_TH_DONE
    INC B
    JR SD_TH
SD_TH_DONE:
    ADD HL,DE
    LD A,B : LD (SCORE_DIGITS+1),A

    LD B,0
SD_H:
    LD DE,100
    OR A
    SBC HL,DE
    JR C,SD_H_DONE
    INC B
    JR SD_H
SD_H_DONE:
    ADD HL,DE
    LD A,B : LD (SCORE_DIGITS+2),A

    LD B,0
SD_T:
    LD DE,10
    OR A
    SBC HL,DE
    JR C,SD_T_DONE
    INC B
    JR SD_T
SD_T_DONE:
    ADD HL,DE
    LD A,B : LD (SCORE_DIGITS+3),A

    LD A,L : LD (SCORE_DIGITS+4),A

    XOR A : LD (ANIM_TMP_ROW),A
    LD A,0 : LD (ANIM_TMP_COL),A
    LD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,1 : LD (ANIM_TMP_COL),A
    LD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,2 : LD (ANIM_TMP_COL),A
    LD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,3 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+0) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,4 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+1) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,5 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+2) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,6 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+3) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,7 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+4) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    RET

; Score-award helpers, one per enemy type's per-kill value.
ADD_SCORE_100:
    LD HL,100
    JR ADD_SCORE_COMMON
ADD_SCORE_200:
    LD HL,200
    JR ADD_SCORE_COMMON
ADD_SCORE_300:
    LD HL,300
ADD_SCORE_COMMON:
    LD DE,(SCORE)
    ADD HL,DE
    LD (SCORE),HL
    CALL SCORE_DISPLAY
    RET

; Awards the right formation-kill score (enemy1=100 while
; ENEMY_CYCLE is 0/1, enemy2=200 while it's 2/3).
AWARD_FORMATION_SCORE:
    LD A,(ENEMY_CYCLE)
    CP 2
    JR NC,AWARD_ENEMY2
    JP ADD_SCORE_100
AWARD_ENEMY2:
    JP ADD_SCORE_200

; ===== Enemy2 instance A/B state (independent complex-mode formations) =====
E2A_SEQ_STATE EQU 0E600h
E2A_EXIT_PHASE EQU 0E601h
E2A_EXITTYPE EQU 0E602h
E2A_PROGRESS EQU 0E603h
E2A_Y EQU 0E604h
E2A_X EQU 0E605h
E2A_TEMP_X EQU 0E606h
E2A_TRAIL_WIDX EQU 0E607h
E2A_TRAIL_HIST EQU 0E608h
E2A_U0_STATE EQU 0E648h
E2A_U0_X EQU 0E649h
E2A_U0_Y EQU 0E64Ah
E2A_U0_TOP EQU 0E64Bh
E2A_U0_BOT EQU 0E64Ch
E2A_U1_STATE EQU 0E64Dh
E2A_U1_X EQU 0E64Eh
E2A_U1_Y EQU 0E64Fh
E2A_U1_TOP EQU 0E650h
E2A_U1_BOT EQU 0E651h
E2A_U2_STATE EQU 0E652h
E2A_U2_X EQU 0E653h
E2A_U2_Y EQU 0E654h
E2A_U2_TOP EQU 0E655h
E2A_U2_BOT EQU 0E656h
E2A_U0_EXITED EQU 0E657h
E2A_U1_EXITED EQU 0E658h
E2A_U2_EXITED EQU 0E659h
E2A_EDS_Y0 EQU 0E65Ah
E2A_EDS_Y1 EQU 0E65Bh
E2A_EDS_Y2 EQU 0E65Ch
E2A_U0_SPRNUM EQU 0E65Dh
E2A_U1_SPRNUM EQU 0E65Eh
E2A_U2_SPRNUM EQU 0E65Fh
E2A_TEMP_SPRNUM EQU 0E660h
E2A_ACTIVE EQU 0E661h
E2B_SEQ_STATE EQU 0E680h
E2B_EXIT_PHASE EQU 0E681h
E2B_EXITTYPE EQU 0E682h
E2B_PROGRESS EQU 0E683h
E2B_Y EQU 0E684h
E2B_X EQU 0E685h
E2B_TEMP_X EQU 0E686h
E2B_TRAIL_WIDX EQU 0E687h
E2B_TRAIL_HIST EQU 0E688h
E2B_U0_STATE EQU 0E6C8h
E2B_U0_X EQU 0E6C9h
E2B_U0_Y EQU 0E6CAh
E2B_U0_TOP EQU 0E6CBh
E2B_U0_BOT EQU 0E6CCh
E2B_U1_STATE EQU 0E6CDh
E2B_U1_X EQU 0E6CEh
E2B_U1_Y EQU 0E6CFh
E2B_U1_TOP EQU 0E6D0h
E2B_U1_BOT EQU 0E6D1h
E2B_U2_STATE EQU 0E6D2h
E2B_U2_X EQU 0E6D3h
E2B_U2_Y EQU 0E6D4h
E2B_U2_TOP EQU 0E6D5h
E2B_U2_BOT EQU 0E6D6h
E2B_U0_EXITED EQU 0E6D7h
E2B_U1_EXITED EQU 0E6D8h
E2B_U2_EXITED EQU 0E6D9h
E2B_EDS_Y0 EQU 0E6DAh
E2B_EDS_Y1 EQU 0E6DBh
E2B_EDS_Y2 EQU 0E6DCh
E2B_U0_SPRNUM EQU 0E6DDh
E2B_U1_SPRNUM EQU 0E6DEh
E2B_U2_SPRNUM EQU 0E6DFh
E2B_TEMP_SPRNUM EQU 0E6E0h
E2B_ACTIVE EQU 0E6E1h

; --- Enemy4: sine-wave vertical bob while moving left fast, using ---
; --- the same asterisk sprite look as Enemy1/2 (built at spawn    ---
; --- time via REDRAW_UNIT_PATTERN, just like they do). Spawned in ---
; --- 2 waves of 3 via SPAWN_THRESHOLDS/SPAWN_SCHEDULE_CHECK (same ---
; --- mechanism as Enemy1/2, right after Enemy2 in the schedule).  ---
; --- Now lives in the unified ENEMY_POOL as BEHAVIOR_SINE_BOB/    ---
; --- TYPE_ENEMY4 - see ENEMY_POOL_UPDATE_ALL and friends below.   ---
ENEMY4_SPEED   EQU 3          ; dots/frame, left (faster than Enemy1's 2)
ENEMY4_SPAWNX  EQU 240
ENEMY4_HP      EQU 2          ; hits to destroy - trial run of the durability system
ENEMY4_LUT_LEN EQU 32
PAT_ENEMY4     EQU 84         ; patterns84-87 (32 bytes at SPRPAT+672)
PAT_PARTICLE   EQU 120        ; single-dot trail particle (32 bytes at SPRPAT+960)
E4_SPAWN_BASEY EQU 0E709h ; scratch: this wave's base Y, set right before ENEMY4_CLAIM_ANY
PAT_ENEMY1_LOOK EQU 88     ; test: Enemy1's asterisk look, static (32 bytes at SPRPAT+704),
                            ; run on BEHAVIOR_SINE_BOB (Enemy4's movement) instead of
                            ; BEHAVIOR_SIMPLE_DRIFT_DODGE - proves TYPE/BEHAVIOR are
                            ; independent (see TYPE_ENEMY1_LOOK / SPAWN_E4B)

; ===== Unified sprite-enemy buffer (target for the ENEMY0/1/2, E2A/E2B ===
; and ENEMY4 migration - ENEMY3 stays separate since it's BG/nametable  ===
; drawn and isn't limited by the 32-sprite hardware budget). Each of    ===
; the 32 slots is a generic struct; a slot's BEHAVIOR field selects     ===
; which movement algorithm runs it and is independent of its TYPE       ===
; field (which selects the sprite pattern/color/HP/score to draw and    ===
; award), so e.g. Enemy2's look can run on Enemy4's movement.           ===
; Slot layout (20 bytes):
;   +0  ACTIVE      0=free, 1=in use
;   +1  TYPE        display id (pattern/color/HP/score lookup)
;   +2  BEHAVIOR    movement algorithm id (dispatch)
;   +3  STATE       algorithm substate/sequence step
;   +4  X
;   +5  Y
;   +6  TOP         sprite pattern number (top half, REDRAW_UNIT_PATTERN-style)
;   +7  BOT         sprite pattern number (bottom half)
;   +8  SPRNUM      hardware sprite number (via ALLOC_SPRITE_NUM/FREE_SPRITE_NUM)
;   +9  FLAGS       bit0=EXITED (off left edge, formation-exit bookkeeping)
;   +10 PARAM0       algorithm scratch (e.g. DIAG_REMAIN / group PROGRESS)
;   +11 PARAM1       algorithm scratch (e.g. DIAG_DIR / group EXIT_PHASE)
;   +12 PARAM2       algorithm scratch (e.g. EXITTYPE)
;   +13 PARAM3       algorithm scratch (e.g. group TEMP_X)
;   +14 TRAIL_CHAN   0=none, else 1-based index into ENEMY_TRAIL_CHANS
;   +15 TRAIL_DELAY  frames this slot trails its channel's writer by
;   +16 DELAY        generic countdown (e.g. staggered spawn delay)
;   +17 HP           remaining hit points
;   +18 PARAM4       spare algorithm scratch
;   +19 PARAM5       spare algorithm scratch
ENEMY_SLOT_SIZE  EQU 20
ENEMY_SLOT_COUNT EQU 32
ENEMY_POOL       EQU 0E84Dh   ; 32*20 = 640 bytes (E84D-EACC)

; field offsets, for readable (IX+E_xxx) access
E_ACTIVE      EQU 0
E_TYPE        EQU 1
E_BEHAVIOR    EQU 2
E_STATE       EQU 3
E_X           EQU 4
E_Y           EQU 5
E_TOP         EQU 6
E_BOT         EQU 7
E_SPRNUM      EQU 8
E_FLAGS       EQU 9
E_PARAM0      EQU 10
E_PARAM1      EQU 11
E_PARAM2      EQU 12
E_PARAM3      EQU 13
E_TRAIL_CHAN  EQU 14
E_TRAIL_DELAY EQU 15
E_DELAY       EQU 16
E_HP          EQU 17
E_PARAM4      EQU 18
E_PARAM5      EQU 19

; 2 shared trail-history ring buffers (TRAIL_BUFLEN*2 = 64 bytes each,
; same X/Y-pair layout as the legacy E2A/E2B_TRAIL_HIST), for the
; formation-leader/follower movement algorithm to be generalized onto
; this buffer in a later migration step. A slot with E_TRAIL_CHAN=0 is
; not part of a trail (most enemies); channels are claimed by whichever
; slot is currently acting as a formation's leader.
ENEMY_TRAIL_CHANS   EQU 0EACDh  ; 2*64 = 128 bytes (EACD-EB4C)
ENEMY_TRAIL_CH_WIDX EQU 0EB4Dh  ; 2 bytes, one write-index per channel
ENEMY_HIT_COL       EQU 0EB4Fh  ; scratch: bullet col/row, saved across the
ENEMY_HIT_ROW       EQU 0EB50h  ; pool scan so B/C are free for the loop counter
ENEMY_SCORE_SEL_TMP EQU 0EB51h  ; scratch: score selector, stashed across TRIGGER_EXPLOSION (clobbers IX)
SIMPLE_PATTERN_USED EQU 0EB52h  ; 6 bytes: which of the 6 physical pattern slots are claimed
SIMPLE_SLOT_SCRATCH EQU 0EB58h  ; 2 bytes: ENEMY_POOL slot base, saved across REDRAW_UNIT_PATTERN
                                 ; (which itself takes IX as an input parameter - see SIMPLE_REDRAW)
E4_SPAWN_TYPE     EQU 0EB5Ah    ; scratch: TYPE to assign, set right before ENEMY4_CLAIM_ANY
ENEMY1_LOOK_FLAGS EQU 0EB5Bh    ; 2 bytes: permanently 1,1 (this look is never quadrant-
                                 ; damaged under BEHAVIOR_SINE_BOB) - built once at INIT

; A slot's TYPE (1-based) indexes this table for its display+stats,
; independent of its BEHAVIOR (movement). 4 bytes/entry:
;   +0 sprite pattern number, +1 sprite color, +2 initial HP,
;   +3 score selector (0=100,1=200,2=300 via ENEMY_AWARD_SCORE_SEL)
ENEMY_TYPE_ENTRYSIZE EQU 4
ETT_PATTERN  EQU 0
ETT_COLOR    EQU 1
ETT_HP       EQU 2
ETT_SCORESEL EQU 3
TYPE_ENEMY4       EQU 1
TYPE_ENEMY1_LOOK  EQU 2   ; test: Enemy1's asterisk look running on Enemy4's movement
ENEMY_TYPE_TABLE:
    DB PAT_ENEMY4, SPR_LTGREEN, ENEMY4_HP, 2   ; TYPE_ENEMY4
    DB PAT_ENEMY1_LOOK, SPR_GRAY, 1, 0         ; TYPE_ENEMY1_LOOK: 1-hit kill, 100pt score

; movement algorithm ids, dispatched by ENEMY_POOL_UPDATE_ALL and
; CHECK_BULLET_VS_ENEMY_POOL.
BEHAVIOR_SINE_BOB EQU 1          ; Enemy4-style: drift left, sine-wave vertical bob
BEHAVIOR_SIMPLE_DRIFT_DODGE EQU 2 ; Enemy1-style: straight drift + one-shot diagonal dodge

; BEHAVIOR_SIMPLE_DRIFT_DODGE needs its own mutable 32-byte VRAM
; sprite pattern per instance (TOP/BOT quadrants independently show/
; hide an asterisk as each is destroyed - see SIMPLE_REDRAW), unlike
; TYPE-based static patterns. Only 6 physical pattern buffers exist
; (matches the schedule's max of 6 concurrent: 3 top-wave + 3
; bottom-wave), so this BEHAVIOR is capped at 6 concurrent regardless
; of the 32-slot ENEMY_POOL's own capacity - same ceiling as before
; migration, just enforced via a separate small allocator
; (ALLOC_PATTERN_SLOT/FREE_PATTERN_SLOT) instead of 6 hardcoded units.
; A slot using this BEHAVIOR stores its claimed pattern-slot index
; (0-5) in E_PARAM3.
SIMPLE_PATTERN_SLOTS EQU 6     ; briefly lowered to 4 as a VBlank-budget
                                ; experiment before the real DI/EI timing
                                ; bug was found/fixed - back to the
                                ; original 6 now that it's unnecessary
SIMPLE_PATTERN_NUMS:
    DB PAT_ENEMY0,PAT_ENEMY1,PAT_ENEMY2,PAT_E1U3,PAT_E1U4,PAT_E1U5
SIMPLE_PATTERN_VRAM:
    DW SPRPAT+32,SPRPAT+64,SPRPAT+96,SPRPAT+576,SPRPAT+608,SPRPAT+640

; --- boss materialize effect state (non-blocking: BOSS_UPDATE is  ---
; --- called once per frame from MAINLOOP and returns immediately  ---
; --- most frames - it never loops/HALTs internally itself, so     ---
; --- MAINLOOP's own per-frame work, incl. the terrain scroller,   ---
; --- keeps running normally throughout the whole sequence)        ---
BOSS_STATE       EQU 0E70Ah  ; 0=idle, 1=materializing, 2=done
BOSS_ROW         EQU 0E70Bh  ; current row 0-15
BOSS_COL         EQU 0E70Ch  ; current tile column within the row, 0-4
BOSS_PHASE       EQU 0E70Dh  ; 0=showing gray, 1=showing white (then draws the tile and advances)
BOSS_YTMP        EQU 0E70Eh  ; scratch: sprite Y byte being written
BOSS_XTMP        EQU 0E70Fh  ; scratch: sprite X byte being written (moves per tile)
BOSS_CTMP        EQU 0E710h  ; scratch: sprite color byte being written
BOSS_SPR_ADDRLO  EQU 0E711h  ; scratch: this sprite's attribute-table offset
BOSS_TILETMP     EQU 0E712h  ; scratch: the tile byte being written to VRAM

; --- sky-erase dispatch vectors: each of the 6 bullet sky-erase   ---
; --- sites does an indirect jump through one of these 2-byte      ---
; --- pointers, instead of the work being inline. Normally each    ---
; --- points at the SKY_FAST_* routine (plain BLANKCODE, in ROM);  ---
; --- once the boss lands, BOSS_UPDATE_BODY repoints all 6 at the  ---
; --- SKY_SLOW_* routine instead (BOSS_MAP-aware restore, also in  ---
; --- ROM - nothing is ever copied/written into ROM, just this     ---
; --- 2-byte RAM pointer, once, at the moment the boss lands).      ---
SKY_VEC_0H EQU 0E713h
SKY_VEC_0E EQU 0E715h
SKY_VEC_1H EQU 0E717h
SKY_VEC_1E EQU 0E719h
SKY_VEC_2H EQU 0E71Bh
SKY_VEC_2E EQU 0E71Dh

; --- boss ring orbit pods: 8 small sprites (fixed numbers 20-27) ---
; --- orbiting the boss ring in a vertical ellipse, starting once ---
; --- the boss lands (BOSS_STATE==2). Evenly spaced (2 of the     ---
; --- 16 LUT steps apart = 45 degrees), color follows which half  ---
; --- of the ellipse they're currently on (black=left, gray=right, ---
; --- matching the ring itself).                                   ---
BOSS_ORBIT_ANGLE   EQU 0E71Fh  ; current rotation, 0-15 (index into the LUT)
BOSS_ORBIT_HOLD    EQU 0E720h  ; frames until the next angle step
BOSS_ORBIT_BASE    EQU 12       ; first of 8 consecutive fixed sprite numbers
BOSS_ORBIT_PATNUM  EQU 100     ; sprite pattern-table unit (free range)
BOSS_ORBIT_CX      EQU 228     ; ellipse center X (screen)
BOSS_ORBIT_CY      EQU 72      ; ellipse center Y (screen)
BOSS_ORBIT_SPEED   EQU 4       ; frames held per angle step
BOSS_ORBIT_XTMP    EQU 0E721h
BOSS_ORBIT_YTMP    EQU 0E722h
BOSS_ORBIT_CTMP    EQU 0E723h

; --- pod bullet firing: starting 30 ticks after the boss lands,   ---
; --- adjacent pod pairs (1,2)(2,3)...(7,8) fire in sequence, one  ---
; --- pair every POD_FIRE_INTERVAL frames, looping back to (1,2)   ---
; --- after (7,8). Bullets reuse the hex-icon sprite (BOSS_HEX_PATNUM) ---
; --- and just fly left off-screen.                                ---
POD_FIRE_ACTIVE  EQU 0E724h  ; 0=waiting for the initial delay, 1=firing sequence running
POD_FIRE_START   EQU 0E725h  ; 2 bytes: target GAME_TICK to begin
POD_FIRE_PAIR    EQU 0E727h  ; 0-6 (pair index: 0=pods1&2 ... 6=pods7&8)
POD_FIRE_TIMER   EQU 0E728h  ; frames left until the next pair fires
POD_BULLET0_ACT  EQU 0E729h
POD_BULLET0_X    EQU 0E72Ah
POD_BULLET0_Y    EQU 0E72Bh
POD_BULLET1_ACT  EQU 0E72Ch
POD_BULLET1_X    EQU 0E72Dh
POD_BULLET1_Y    EQU 0E72Eh
POD_XY_X         EQU 0E72Fh  ; scratch: GET_POD_XY's result
POD_XY_Y         EQU 0E730h
POD_RECOIL       EQU 0E731h  ; 8 bytes, one per pod - frames left of +8px recoil kick
POD_RECOIL_DURATION EQU 8
POD_FIRE_DELAY_TICKS EQU 10
POD_FIRE_INTERVAL    EQU 20   ; frames between each pair firing
POD_BULLET_SPEED     EQU 12   ; px/frame, leftward - fast enough to clear
                               ; the screen well within POD_FIRE_INTERVAL,
                               ; since only 2 bullet slots are reused each
                               ; firing (not a full pool)
POD_BULLET_SPR0      EQU 20   ; fixed sprite numbers, right after the 8 orbit pods (6-13)
POD_BULLET_SPR1      EQU 21
BOSS_SPR_BASE    EQU 8       ; fixed hardware sprite number, reused throughout
BOSS_HEX_PATNUM  EQU 96      ; sprite pattern-table unit (free range)

; Enemy2 instance A/B sprite pattern codes (sprite pattern table is a
; separate 256-code space from the background PATTERNS table, so
; these don't collide with anything there)
PAT_E2A0 EQU 32
PAT_E2A1 EQU 36
PAT_E2A2 EQU 40
PAT_E2A_TT EQU 44
PAT_E2A_TB EQU 48
PAT_E2B0 EQU 52
PAT_E2B1 EQU 56
PAT_E2B2 EQU 60
PAT_E2B_TT EQU 64
PAT_E2B_TB EQU 68

ENEMY_START_COMPLEX_A:
    LD A,(ENEMY_CYCLE)
    CP 2
    JR NZ,ESC_COMPLEX_CYCLE3_A
    LD A,ENEMY_Y2 : LD (E2A_Y),A
    XOR A : LD (E2A_EXITTYPE),A
    JR ESC_COMPLEX_INIT_A
ESC_COMPLEX_CYCLE3_A:
    LD A,ENEMY_Y1 : LD (E2A_Y),A
    LD A,1 : LD (E2A_EXITTYPE),A
ESC_COMPLEX_INIT_A:
    LD A,1
    LD (E2A_U0_TOP),A : LD (E2A_U0_BOT),A
    LD (E2A_U1_TOP),A : LD (E2A_U1_BOT),A
    LD (E2A_U2_TOP),A : LD (E2A_U2_BOT),A
    CALL ALLOC_SPRITE_NUM : LD (E2A_U0_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2A_U1_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2A_U2_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2A_TEMP_SPRNUM),A
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,SPRPAT+256 : LD DE,E2A_U0_TOP : LD IX,E2A_U0_BOT
    EI
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+288 : LD DE,E2A_U1_TOP : LD IX,E2A_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+320 : LD DE,E2A_U2_TOP : LD IX,E2A_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    LD A,1
    LD (E2A_U0_STATE),A : LD (E2A_U1_STATE),A : LD (E2A_U2_STATE),A
    LD A,(E2A_Y) : LD (E2A_U0_Y),A : LD (E2A_U1_Y),A : LD (E2A_U2_Y),A   ; keep hit-test Y in sync with the drawn Y during assembly (states 0-5), not just from state6 onward
    XOR A
    LD (E2A_SEQ_STATE),A : LD (E2A_PROGRESS),A
    LD A,ENEMY_SPAWNX : LD (E2A_U0_X),A
    DI
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,1 : LD (E2A_ACTIVE),A
    EI
    RET

ENEMY_START_COMPLEX_B:
    LD A,(ENEMY_CYCLE)
    CP 2
    JR NZ,ESC_COMPLEX_CYCLE3_B
    LD A,ENEMY_Y2 : LD (E2B_Y),A
    XOR A : LD (E2B_EXITTYPE),A
    JR ESC_COMPLEX_INIT_B
ESC_COMPLEX_CYCLE3_B:
    LD A,ENEMY_Y1 : LD (E2B_Y),A
    LD A,1 : LD (E2B_EXITTYPE),A
ESC_COMPLEX_INIT_B:
    LD A,1
    LD (E2B_U0_TOP),A : LD (E2B_U0_BOT),A
    LD (E2B_U1_TOP),A : LD (E2B_U1_BOT),A
    LD (E2B_U2_TOP),A : LD (E2B_U2_BOT),A
    CALL ALLOC_SPRITE_NUM : LD (E2B_U0_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2B_U1_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2B_U2_SPRNUM),A
    CALL ALLOC_SPRITE_NUM : LD (E2B_TEMP_SPRNUM),A
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,SPRPAT+416 : LD DE,E2B_U0_TOP : LD IX,E2B_U0_BOT
    EI
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+448 : LD DE,E2B_U1_TOP : LD IX,E2B_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+480 : LD DE,E2B_U2_TOP : LD IX,E2B_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    LD A,1
    LD (E2B_U0_STATE),A : LD (E2B_U1_STATE),A : LD (E2B_U2_STATE),A
    LD A,(E2B_Y) : LD (E2B_U0_Y),A : LD (E2B_U1_Y),A : LD (E2B_U2_Y),A   ; keep hit-test Y in sync with the drawn Y during assembly (states 0-5), not just from state6 onward
    XOR A
    LD (E2B_SEQ_STATE),A : LD (E2B_PROGRESS),A
    LD A,ENEMY_SPAWNX : LD (E2B_U0_X),A
    DI
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,1 : LD (E2B_ACTIVE),A
    EI
    RET

; Checked once per game tick (every 8 frames). Fires each scheduled
; spawn exactly once, in order, as GAME_TICK reaches its threshold -
; not when the previous one finishes. SPAWN_THRESHOLDS is a 16-bit
; (DW) array so thresholds aren't capped at 255. One-shot: once all
; entries have fired, this just returns immediately forever after.
SPAWN_SCHEDULE_CHECK:
    LD A,(SPAWN_NEXT_INDEX)
    CP 6
    RET NC
    LD H,0 : LD L,A
    ADD HL,HL
    LD DE,SPAWN_THRESHOLDS
    ADD HL,DE
    LD E,(HL) : INC HL : LD D,(HL)
    LD HL,(GAME_TICK)
    OR A
    SBC HL,DE
    RET C

    ; --- E2インスタンスがまだ稼働中なら、インデックスを進めずに
    ;     今回は何もしないで戻る(次フレームで同じ番号を再チェック)。
    ;     これにより取りこぼし(無駄)なく、ACTIVEが0に戻った
    ;     瞬間に確実に発火する ---
    LD A,(SPAWN_NEXT_INDEX)
    CP 20 : JR Z,SSC_BUSY_A
    CP 22 : JR Z,SSC_BUSY_A
    CP 21 : JR Z,SSC_BUSY_B
    CP 24 : JR Z,SSC_BUSY_B
    JR SSC_FIRE
SSC_BUSY_A:
    LD A,(E2A_ACTIVE) : OR A : RET NZ
    JR SSC_FIRE
SSC_BUSY_B:
    LD A,(E2B_ACTIVE) : OR A : RET NZ

SSC_FIRE:
    LD A,(SPAWN_NEXT_INDEX)
    INC A
    LD (SPAWN_NEXT_INDEX),A
    DEC A
    ; --- TEMPORARY: focused Enemy3-offset test schedule, 6 enemy3_wave  ---
    ; --- triggers only (tick8..23, offsets 0/2/4/6/8/10 cells), from    ---
    ; --- the schedule editor's test JSON. The previous full 75-entry    ---
    ; --- level schedule this replaced is preserved in git history.      ---
    CP 0  : JP Z,SPAWN_E3_WAVE
    CP 1  : JP Z,SPAWN_E3_WAVE
    CP 2  : JP Z,SPAWN_E3_WAVE
    CP 3  : JP Z,SPAWN_E3_WAVE
    CP 4  : JP Z,SPAWN_E3_WAVE
    JP SPAWN_E3_WAVE  ; index 5 (last)

; --- saved (disabled) boss-only fast-iteration schedule - kept for  ---
; --- quickly testing boss-only features again later. Not active.   ---
;SPAWN_SCHEDULE_CHECK_BOSSONLY_SAVED:
;    LD A,(SPAWN_NEXT_INDEX)
;    CP 1
;    RET NC
;    LD H,0 : LD L,A
;    ADD HL,HL
;    LD DE,SPAWN_THRESHOLDS
;    ADD HL,DE
;    LD E,(HL) : INC HL : LD D,(HL)
;    LD HL,(GAME_TICK)
;    OR A
;    SBC HL,DE
;    RET C
;
;    LD A,(SPAWN_NEXT_INDEX)
;    INC A
;    LD (SPAWN_NEXT_INDEX),A
;    JP BOSS_SPAWN

; --- boss materialize effect (non-blocking version) ---
; BOSS_SPAWN (called once, from SSC_FIRE at tick10): just sets up
; state for row0/col0 and returns immediately - does NOT loop or
; HALT itself. BOSS_UPDATE (called every frame from MAINLOOP, right
; after DI at the top, same as every other per-frame system) does
; the actual stepping.
;
; One BG tile (8x8) at a time: the sprite only ever needed its
; top-left 8x8 quadrant defined (the other 3 are blank/transparent)
; - which tile it's covering, quadrant, doesn't matter, since it's
; moved to sit exactly over each BG cell right before that cell is
; rewritten. No extra hold - gray for 1 frame, white for 1 frame,
; draw the tile, move on to the next of the 5x16=80 tiles.
; --- called once, right when the boss spawns. The boss's fixed     ---
; --- sprite numbers (8-31: hex icon, shield deflection, orbit pods, ---
; --- pod bullets, explosions, lap markers) overlap the dynamic      ---
; --- allocator's whole 2-31 scan range. Any Enemy1/2/4 still alive  ---
; --- at that instant would otherwise keep its already-allocated     ---
; --- number, which the boss's fixed-number code writes to directly  ---
; --- every frame without ever checking SPRITE_USED - a straight     ---
; --- collision (this was making Enemy2 vanish mid-formation, and    ---
; --- part of the remaining garbage-sprite reports). Fix: force-hide ---
; --- and free every dynamic enemy right here, THEN permanently      ---
; --- reserve 8-31 so the allocator can never hand one out again.    ---
BOSS_CLEAR_DYNAMIC_ENEMIES:
    ; E2A/E2B: reuse their own full-teardown (hides all4, frees all4,
    ; clears ACTIVE) - safe to call unconditionally even if idle,
    ; since ENEMY_COMPLEX_STEP_A/B already gate everything else on
    ; ACTIVE, and by the time the boss can spawn (last schedule
    ; entry) each has always completed at least one real spawn, so
    ; its SPRNUM vars hold a previously-valid (if now free) number,
    ; never the RAM-cleared 0.
    CALL ECS_S8_A
    CALL ECS_S8_B

    CALL BCDE_CLEAR_ENEMY_POOL

    ; permanently reserve 8-31 for the boss's fixed sprites
    LD HL,SPRITE_USED+8
    LD B,24
BCDE_RESERVE:
    LD A,1 : LD (HL),A
    INC HL
    DJNZ BCDE_RESERVE
    RET

; Input: A = sprite number to hide+free. Writes Y=ENEMY_HIDE_Y,
; X=255 to that VDP attribute slot, then frees it.
BCDE_HIDE1:
    PUSH AF
    DI
    ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    POP AF
    CALL FREE_SPRITE_NUM
    RET

; Force-hides+frees every active unified-pool slot (currently just the
; BEHAVIOR_SINE_BOB/Enemy4-type ones - more BEHAVIORs join this sweep
; as they migrate in). Called once, right before the boss spawns.
BCDE_CLEAR_ENEMY_POOL:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
BCEP_LOOP:
    PUSH BC
    PUSH HL           ; BCDE_HIDE1/FREE_SPRITE_NUM below reuse HL - save our scan pointer
    PUSH HL : POP IX
    LD A,(IX+E_ACTIVE)
    OR A
    JR Z,BCEP_SKIP
    LD A,(IX+E_BEHAVIOR)
    CP BEHAVIOR_SIMPLE_DRIFT_DODGE
    JR NZ,BCEP_NOT_SIMPLE
    LD A,(IX+E_PARAM3) : CALL FREE_PATTERN_SLOT
BCEP_NOT_SIMPLE:
    LD A,(IX+E_SPRNUM) : CALL BCDE_HIDE1
    XOR A : LD (IX+E_ACTIVE),A
BCEP_SKIP:
    POP HL
    POP BC
    LD DE,ENEMY_SLOT_SIZE
    ADD HL,DE
    DJNZ BCEP_LOOP
    RET

BOSS_SPAWN:
    CALL BOSS_CLEAR_DYNAMIC_ENEMIES
    ; --- load boss pattern data now, just in time - not preloaded ---
    ; --- at INIT (that permanently claimed codes192-255, which    ---
    ; --- the terrain scroller actually needs some of - see INIT). ---
    LD HL,BOSS_PATTERNS : LD DE,192*8 : LD BC,64*8 : CALL LDIRVM
    LD HL,BOSS_HEX_PATTERN : LD DE,96*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BOSS_ORBIT_PATTERN : LD DE,100*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,DFL_BULLET_PATTERN : LD DE,104*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,EXPLOSION_PATTERN : LD DE,108*8+SPRPAT : LD BC,32 : CALL LDIRVM
    XOR A : LD (BOSS_ROW),A
    XOR A : LD (BOSS_COL),A
    LD A,1 : LD (BOSS_PHASE),A
    LD A,1 : LD (BOSS_STATE),A
    CALL BOSS_SETUP_TILE_SPRITE
    RET

; called only while BOSS_STATE==1 (materializing) - the check now
; lives in MAINLOOP itself (CALL Z,BOSS_UPDATE_BODY), so this never
; even gets a CALL/RET's worth of overhead on the vast majority of
; frames where the boss isn't doing anything.
BOSS_UPDATE_BODY:
    LD A,(BOSS_PHASE)
    OR A
    JP NZ,BOSS_HOLD_WHITE
    ; phase 0: draw this tile, then advance
    CALL BOSS_DRAW_CUR_TILE
    LD A,(BOSS_COL) : INC A : LD (BOSS_COL),A
    CP 5
    JP NZ,BOSS_ADV_NEXTTILE
    XOR A : LD (BOSS_COL),A
    LD A,(BOSS_ROW) : INC A : LD (BOSS_ROW),A
    CP 16
    JP NZ,BOSS_ADV_NEXTTILE
    CALL BOSS_HIDE_SPRITE
    LD A,2 : LD (BOSS_STATE),A
    ; --- boss has landed - repoint the 6 dispatch vectors at the  ---
    ; --- BOSS_MAP-aware routines instead of BLANKCODE. Just a     ---
    ; --- 2-byte pointer write each, once, here - not on every     ---
    ; --- bullet-erase call.                                       ---
    LD HL,SKY_SLOW_0H : LD (SKY_VEC_0H),HL
    LD HL,SKY_SLOW_0E : LD (SKY_VEC_0E),HL
    LD HL,SKY_SLOW_1H : LD (SKY_VEC_1H),HL
    LD HL,SKY_SLOW_1E : LD (SKY_VEC_1E),HL
    LD HL,SKY_SLOW_2H : LD (SKY_VEC_2H),HL
    LD HL,SKY_SLOW_2E : LD (SKY_VEC_2E),HL
    ; --- start the 8 orbiting ring pods ---
    ; --- BOSS_ORBIT_DRAW_ALL reads POD_HP (hide-if-dead check) and     ---
    ; --- POD_RECOIL (kick offset) for every pod it draws - it MUST run ---
    ; --- after those are initialized, not before (real uninitialized-  ---
    ; --- RAM bug, confirmed via poisoned-RAM testing).                 ---
    XOR A : LD (BOSS_ORBIT_ANGLE),A
    ; --- arm the pod-fire sequence: starts POD_FIRE_DELAY_TICKS ---
    ; --- ticks from now ---
    XOR A : LD (POD_FIRE_ACTIVE),A
    XOR A : LD (POD_FIRE_PAIR),A
    XOR A : LD (POD_BULLET0_ACT),A
    XOR A : LD (POD_BULLET1_ACT),A
    LD HL,POD_RECOIL : LD B,8
BSPAWN_CLEARRECOIL:
    LD (HL),0 : INC HL : DJNZ BSPAWN_CLEARRECOIL
    XOR A : LD (POD_CYCLE_COUNT),A
    XOR A : LD (POD_VOLLEY_ACTIVE),A
    LD HL,VOLLEY_PHASE : LD B,8
BSPAWN_CLEARVOLLEY:
    LD (HL),0 : INC HL : DJNZ BSPAWN_CLEARVOLLEY
    LD HL,POD_HP : LD B,8
BSPAWN_INITHP:
    LD (HL),POD_HP_MAX : INC HL : DJNZ BSPAWN_INITHP
    CALL BOSS_ORBIT_DRAW_ALL
    LD HL,EXPLOSION_ACT : LD B,8
BSPAWN_CLEAREXPL:
    LD (HL),0 : INC HL : DJNZ BSPAWN_CLEAREXPL
    LD A,1 : LD (BOSS_ORBIT_SPEED_CUR),A
    LD A,POD_FIRE_INTERVAL : LD (POD_FIRE_INTERVAL_CUR),A
    XOR A : LD (POD_LAP_ACTIVE),A
    LD HL,(GAME_TICK)
    LD DE,POD_FIRE_DELAY_TICKS
    ADD HL,DE
    LD (POD_FIRE_START),HL
    RET
BOSS_ADV_NEXTTILE:
    CALL BOSS_SETUP_TILE_SPRITE
    LD A,1 : LD (BOSS_PHASE),A
    RET
BOSS_HOLD_WHITE:
    XOR A : LD (BOSS_PHASE),A
    RET

; sets the fixed boss-effect sprite's Y (7+row*8) and X (208+col*8 -
; directly over the 8x8 cell about to be redrawn), pattern (fixed),
; and color=white, for the start of a new tile.
BOSS_SETUP_TILE_SPRITE:
    LD A,(BOSS_ROW)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,7
    LD (BOSS_YTMP),A
    LD A,(BOSS_COL)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,208
    LD (BOSS_XTMP),A
    CALL BOSS_SPR_SET_YXP
    LD A,15 : CALL BOSS_SPR_SET_COLOR
    RET

; draws the single current tile (BOSS_ROW,BOSS_COL) into the
; nametable: dest = 183Ah + row*32 + col, source = BOSS_MAP + row*5 + col
; Raw OUT sequence (not LDIRVM) with extra NOP padding - testing
; whether the terrain corruption is a VDP-timing issue (2 NOPs is
; normally enough everywhere else in this file, but this write
; happens via a different code path than the established one, so
; bumping the margin here specifically to check).
BOSS_DRAW_CUR_TILE:
    LD A,(BOSS_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,183Ah
    ADD HL,DE
    LD A,(BOSS_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    LD D,H : LD E,L
    PUSH DE
    LD A,(BOSS_ROW)
    LD H,0 : LD L,A
    LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL
    ADD HL,DE
    LD DE,BOSS_MAP
    ADD HL,DE
    LD A,(BOSS_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    LD A,(HL) : LD (BOSS_TILETMP),A
    POP DE
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,D : OR 40h : OUT (99h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(BOSS_TILETMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    CALL SOUND_POD_HIT
    RET

; writes Y (from BOSS_YTMP), X (from BOSS_XTMP - the current chunk's
; position) and pattern (fixed) for the fixed boss-effect sprite
; number, and stashes its attribute-table offset for
; BOSS_SPR_SET_COLOR.
BOSS_SPR_SET_YXP:
    LD A,BOSS_SPR_BASE : ADD A,A : ADD A,A : LD E,A : LD D,0
    LD A,E : LD (BOSS_SPR_ADDRLO),A
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
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
    NOP
    NOP
    LD A,(BOSS_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
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
    NOP
    NOP
    LD A,(BOSS_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
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
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    NOP
    NOP
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

; writes the color byte (passed in A) for the fixed boss-effect
; sprite, reusing the offset BOSS_SPR_SET_YXP just stashed.
BOSS_SPR_SET_COLOR:
    LD (BOSS_CTMP),A
    LD A,(BOSS_SPR_ADDRLO) : LD E,A : LD D,0
    DI
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
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
    NOP
    NOP
    LD A,(BOSS_CTMP) : OUT (98h),A
    NOP
    NOP
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

; parks the boss-effect sprite off-screen (Y=209: past the visible
; area and past the Y=208 stop sentinel) once the last row lands.
BOSS_HIDE_SPRITE:
    LD A,BOSS_SPR_BASE : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
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
    NOP
    NOP
    LD A,209 : OUT (98h),A
    NOP
    NOP
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

; called every frame once BOSS_STATE==2 (landed) - advances the
; rotation by one of 256 LUT steps every frame, for smooth,
; continuous ferris-wheel-style motion (no hold/skip needed at
; this resolution).
BOSS_ORBIT_UPDATE:
    LD A,(POD_VOLLEY_ACTIVE)
    OR A
    RET NZ
    LD A,(BOSS_ORBIT_ANGLE)
    LD B,A
    LD A,(BOSS_ORBIT_SPEED_CUR)
    ADD A,B
    LD (BOSS_ORBIT_ANGLE),A
    JP BOSS_ORBIT_DRAW_ALL

; writes all 8 orbit pods' sprite attributes for the current
; BOSS_ORBIT_ANGLE - each pod is 32 of the 256 LUT steps apart (45
; degrees), color follows which half of the ellipse it's on
; (negative dx = left = black, else gray).
BOSS_ORBIT_DRAW_ALL:
    LD B,0
BOD_LOOP:
    LD A,B
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A
    LD A,(BOSS_ORBIT_ANGLE)
    ADD A,C
    LD E,A : LD D,0
    PUSH BC
    LD HL,LUT_DX : ADD HL,DE
    LD A,(HL)
    LD C,A
    OR A
    LD A,14
    JP P,BOD_GRAY
    LD A,1
BOD_GRAY:
    LD (BOSS_ORBIT_CTMP),A
    LD A,210
    ADD A,C
    LD (BOSS_ORBIT_XTMP),A
    LD HL,LUT_DY : ADD HL,DE
    LD A,63
    ADD A,(HL)
    LD (BOSS_ORBIT_YTMP),A
    POP BC
    ; --- dead pods (POD_HP==0) just stay hidden, not drawn at all ---
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JP Z,BOD_NEXT
    ; --- if pod B just fired, kick it +8px right for a few frames ---
    LD HL,POD_RECOIL : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,BOD_NORECOIL
    DEC (HL)
    LD A,(BOSS_ORBIT_XTMP)
    ADD A,8
    LD (BOSS_ORBIT_XTMP),A
BOD_NORECOIL:
    ; --- cache this pod's live position for collision checks ---
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(BOSS_ORBIT_XTMP) : LD (HL),A
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(BOSS_ORBIT_YTMP) : LD (HL),A
    LD A,BOSS_ORBIT_BASE
    ADD A,B
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_ORBIT_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_CTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
BOD_NEXT:
    INC B
    LD A,B
    CP 8
    JP NZ,BOD_LOOP
    RET

; computes pod A's (0-7) current X/Y (screen X, VDP Y register
; value) from the orbit LUT into POD_XY_X/POD_XY_Y. Same formula as
; BOSS_ORBIT_DRAW_ALL's loop body, factored out here for pod-fire's
; use (grabbing a specific pod's current position when it fires).
; called every frame while BOSS_STATE==2. Checks each active player
; shot against all 8 pods' cached live positions (POD_CUR_X/Y, kept
; current by whichever routine is drawing that pod - orbit or
; launch/volley). Dead pods (HP==0) are skipped automatically since
; their HP check fails first.
POD_COLLISION_UPDATE:
    LD A,(BULLET0_ACT)
    OR A
    CALL NZ,CHECK_BULLET0_VS_PODS
    LD A,(BULLET1_ACT)
    OR A
    CALL NZ,CHECK_BULLET1_VS_PODS
    LD A,(BULLET2_ACT)
    OR A
    CALL NZ,CHECK_BULLET2_VS_PODS
    RET

CHECK_BULLET0_VS_PODS:
    LD A,(BULLET0_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_X),A
    LD A,(BULLET0_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_Y),A
    LD B,0
CB0_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,CB0_SKIP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB0_SKIP
    CP 141
    JR NC,CB0_SKIP
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB0_SKIP
    CP 141
    JR NC,CB0_SKIP
    CALL POD_HIT
    POP BC
    JP CB0_ERASE
CB0_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JP NZ,CB0_LOOP
    RET
CB0_ERASE:
    LD A,(BULLET0_ROW) : SUB 1 : CP 16 : JR NC,CB0_ERASE_FAST
    LD B,A : LD A,(BULLET0_COL) : SUB 26 : CP 5 : JR NC,CB0_ERASE_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    LD (TEMP_ERASE_BYTE),A
    LD A,(BULLET0_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET0_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET0_ACT),A
    EI
    RET
CB0_ERASE_FAST:
    LD A,(BULLET0_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET0_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET0_ACT),A
    EI
    RET

CHECK_BULLET1_VS_PODS:
    LD A,(BULLET1_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_X),A
    LD A,(BULLET1_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_Y),A
    LD B,0
CB1_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,CB1_SKIP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB1_SKIP
    CP 141
    JR NC,CB1_SKIP
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB1_SKIP
    CP 141
    JR NC,CB1_SKIP
    CALL POD_HIT
    POP BC
    JP CB1_ERASE
CB1_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JP NZ,CB1_LOOP
    RET
CB1_ERASE:
    LD A,(BULLET1_ROW) : SUB 1 : CP 16 : JR NC,CB1_ERASE_FAST
    LD B,A : LD A,(BULLET1_COL) : SUB 26 : CP 5 : JR NC,CB1_ERASE_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    LD (TEMP_ERASE_BYTE),A
    LD A,(BULLET1_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET1_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET1_ACT),A
    EI
    RET
CB1_ERASE_FAST:
    LD A,(BULLET1_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET1_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET1_ACT),A
    EI
    RET

CHECK_BULLET2_VS_PODS:
    LD A,(BULLET2_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_X),A
    LD A,(BULLET2_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_Y),A
    LD B,0
CB2_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,CB2_SKIP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB2_SKIP
    CP 141
    JR NC,CB2_SKIP
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CB2_SKIP
    CP 141
    JR NC,CB2_SKIP
    CALL POD_HIT
    POP BC
    JP CB2_ERASE
CB2_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JP NZ,CB2_LOOP
    RET
CB2_ERASE:
    LD A,(BULLET2_ROW) : SUB 1 : CP 16 : JR NC,CB2_ERASE_FAST
    LD B,A : LD A,(BULLET2_COL) : SUB 26 : CP 5 : JR NC,CB2_ERASE_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    LD (TEMP_ERASE_BYTE),A
    LD A,(BULLET2_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET2_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET2_ACT),A
    EI
    RET
CB2_ERASE_FAST:
    LD A,(BULLET2_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET2_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET2_ACT),A
    EI
    RET

; B = pod index (0-7) - knocks 1 HP off; at 0, destroys it (sound,
; hides its sprite for good, and marks a one-shot BG explosion cell
; near its last position).
POD_HIT:
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    DEC (HL)
    LD A,(HL)
    OR A
    JR NZ,POD_HIT_PING
    JP POD_HIT_DESTROY
POD_HIT_PING:
    CALL SOUND_POD_HIT
    RET
POD_HIT_DESTROY:
    PUSH BC
    PUSH BC
    CALL UPDATE_DIFFICULTY
    POP BC
    CALL SOUND_DESTROY
    LD A,BOSS_ORBIT_BASE : ADD A,B
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    LD HL,EXPLOSION_X : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),A
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    LD HL,EXPLOSION_Y : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),A
    LD HL,EXPLOSION_ACT : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),1
    LD HL,EXPLOSION_TIMER : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),EXPLOSION_DURATION
    EI
    CALL EXPLOSION_DRAW

    CALL COUNT_ALIVE_PODS
    OR A
    JR NZ,PHD_SKIP_BOSSEXPL
    LD A,(BOSS_EXPL_STARTED)
    OR A
    JR NZ,PHD_SKIP_BOSSEXPL
    LD A,1 : LD (BOSS_EXPL_STARTED),A
    CALL BOSS_EXPL_BUILD_LUT
    ; --- bullets erasing themselves over the (now emptying) boss   ---
    ; --- area were "restoring" BOSS_MAP tiles we'd already popped  ---
    ; --- (SKY_SLOW_* repaints from BOSS_MAP). Switch back to the   ---
    ; --- plain-sky vectors so an erase just leaves blank sky.      ---
    LD HL,SKY_FAST_0H : LD (SKY_VEC_0H),HL
    LD HL,SKY_FAST_0E : LD (SKY_VEC_0E),HL
    LD HL,SKY_FAST_1H : LD (SKY_VEC_1H),HL
    LD HL,SKY_FAST_1E : LD (SKY_VEC_1E),HL
    LD HL,SKY_FAST_2H : LD (SKY_VEC_2H),HL
    LD HL,SKY_FAST_2E : LD (SKY_VEC_2E),HL
PHD_SKIP_BOSSEXPL:
    POP BC
    RET

; draws pod B's destroy burst sprite (its own dedicated slot) at
; its EXPLOSION_X/Y.
; B = pod index (0-7) - draws that pod's own explosion slot.
EXPLOSION_DRAW:
    LD HL,EXPLOSION_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_XTMP),A
    LD HL,EXPLOSION_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_YTMP),A
    LD A,EXPLOSION_SPR_BASE : ADD A,B
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,EXPLOSION_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,8 : OUT (98h),A
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

; B = pod index (0-7)
EXPLOSION_HIDE:
    LD A,EXPLOSION_SPR_BASE : ADD A,B
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

; called every frame while BOSS_STATE==2 - counts down the burst's
; visible duration, then hides it.
EXPLOSION_UPDATE:
    LD B,0
EU_LOOP:
    PUSH BC
    LD HL,EXPLOSION_ACT : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,EU_SKIP
    LD HL,EXPLOSION_TIMER : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    DEC A
    LD (HL),A
    JR NZ,EU_SKIP
    LD HL,EXPLOSION_ACT : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),0
    CALL EXPLOSION_HIDE
EU_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JR NZ,EU_LOOP
    RET

; recomputes BOSS_ORBIT_SPEED_CUR and POD_FIRE_INTERVAL_CUR from
; how many pods are still alive. Called once whenever a pod is
; destroyed, not every frame.
UPDATE_DIFFICULTY:
    CALL COUNT_ALIVE_PODS
    LD B,A
    LD A,8
    SUB B
    LD C,A
    SRL A
    ADD A,1
    LD (BOSS_ORBIT_SPEED_CUR),A
    LD A,C
    ADD A,A
    LD B,A
    LD A,POD_FIRE_INTERVAL
    SUB B
    CP POD_FIRE_INTERVAL_MIN
    JR NC,UD_OK
    LD A,POD_FIRE_INTERVAL_MIN
UD_OK:
    LD (POD_FIRE_INTERVAL_CUR),A
    RET

; returns the number of pods with HP>0 (0-8) in A.
COUNT_ALIVE_PODS:
    LD HL,POD_HP
    LD B,8
    LD C,0
CAP_LOOP:
    LD A,(HL)
    OR A
    JR Z,CAP_SKIP
    INC C
CAP_SKIP:
    INC HL
    DJNZ CAP_LOOP
    LD A,C
    RET

; Precomputed once (offline, not on-device) so the pop order is the
; exact same every single playthrough - no runtime RNG involved, so
; there's no way for it to ever come out different or incomplete.
; These are the 71 non-blank BOSS_MAP cell indices (0-79, row*5+col)
; in their fixed pop order.
BOSS_EXPL_LUT_DATA:
    DB 41,60,23,64,67,33,50,54,66,39,40,12,21,61,32,76
    DB 10,51,38,43,7,16,29,9,1,55,49,2,25,34,31,46
    DB 44,47,27,63,58,35,71,59,45,48,6,42,15,72,19,20
    DB 36,78,3,56,37,24,11,65,68,8,77,28,74,69,26,30
    DB 18,73,70,14,5,53,13

; Arms the pop sequence, right when the last pod dies. The LUT is
; already fixed ROM data (BOSS_EXPL_LUT_DATA) - nothing to build.
BOSS_EXPL_BUILD_LUT:
    XOR A : LD (BOSS_EXPL_INDEX),A
    LD A,1 : LD (BOSS_EXPL_TIMER),A
    XOR A : LD (BOSS_EXPL_SPRIDX),A
    LD A,1 : LD (BOSS_EXPL_ACTIVE),A
    RET

; Called every frame while BOSS_STATE==2. Pops one BOSS_MAP cell
; every few frames once active: erases the nametable tile, fires a
; sprite explosion at that cell's pixel position (round-robining
; through the 8 pod-explosion slots, all free by now since every pod
; is dead), and plays the noise-channel destroy sound - a rapid
; string of bangs as the whole boss body is stripped away.
BOSS_EXPL_UPDATE:
    LD A,(BOSS_EXPL_ACTIVE)
    OR A
    RET Z

    LD A,(BOSS_EXPL_TIMER)
    DEC A
    LD (BOSS_EXPL_TIMER),A
    RET NZ

    LD A,(BOSS_EXPL_INDEX)
    LD B,A
    LD A,BOSS_EXPL_COUNT
    CP B
    JR NZ,BEU_FIRE
    XOR A : LD (BOSS_EXPL_ACTIVE),A
    LD A,40 : LD (PLAYER_FLYAWAY_WAIT),A
    LD A,1 : LD (PLAYER_FLYAWAY_SPD),A
    XOR A : LD (SND_TIMER_C),A
    RET
BEU_FIRE:
    LD A,B
    LD H,0 : LD L,A
    LD DE,BOSS_EXPL_LUT_DATA
    ADD HL,DE
    LD A,(HL)

    LD B,0
BEU_DECODE:
    CP 5
    JR C,BEU_DECODE_DONE
    SUB 5
    INC B
    JR BEU_DECODE
BEU_DECODE_DONE:
    LD (BOSS_EXPL_COL),A
    LD A,B
    LD (BOSS_EXPL_ROW),A

    LD H,0 : LD L,B
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,183Ah
    ADD HL,DE
    LD A,(BOSS_EXPL_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP

    LD A,(BOSS_EXPL_ROW)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,7
    LD B,A
    LD A,(BOSS_EXPL_COL)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,208
    LD C,A

    LD A,(BOSS_EXPL_SPRIDX)
    LD H,0 : LD L,A
    EI
    PUSH HL
    LD DE,EXPLOSION_Y
    ADD HL,DE
    LD A,B
    LD (HL),A
    POP HL
    PUSH HL
    LD DE,EXPLOSION_X
    ADD HL,DE
    LD A,C
    LD (HL),A
    POP HL
    PUSH HL
    LD DE,EXPLOSION_ACT
    ADD HL,DE
    LD (HL),1
    POP HL
    LD DE,EXPLOSION_TIMER
    ADD HL,DE
    LD (HL),EXPLOSION_DURATION

    LD A,(BOSS_EXPL_SPRIDX)
    LD B,A
    CALL EXPLOSION_DRAW
    CALL SOUND_DESTROY

    LD A,(BOSS_EXPL_SPRIDX) : INC A : AND 7 : LD (BOSS_EXPL_SPRIDX),A
    LD A,(BOSS_EXPL_INDEX) : INC A : LD (BOSS_EXPL_INDEX),A
    LD A,2 : LD (BOSS_EXPL_TIMER),A
    RET

GET_POD_XY:
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A
    LD A,(BOSS_ORBIT_ANGLE)
    ADD A,C
    LD E,A : LD D,0
    LD HL,LUT_DX : ADD HL,DE
    LD A,(HL)
    LD C,A
    LD A,210
    ADD A,C
    LD (POD_XY_X),A
    LD HL,LUT_DY : ADD HL,DE
    LD A,63
    ADD A,(HL)
    LD (POD_XY_Y),A
    RET

; called every frame once BOSS_STATE==2. Waits for
; POD_FIRE_DELAY_TICKS after landing, then fires one adjacent pod
; pair every POD_FIRE_INTERVAL frames, cycling (1,2)(2,3)...(7,8)
; and back to (1,2). Also moves/erases the (at most 2) live bullets
; every frame regardless.

POD_FIRE_UPDATE:
    CALL POD_BULLET_MOVE
    CALL VOLLEY_UPDATE
    LD A,(POD_VOLLEY_ACTIVE)
    OR A
    RET NZ
    LD A,(POD_FIRE_ACTIVE)
    OR A
    JR NZ,PFU_RUNNING
    LD HL,(GAME_TICK)
    LD DE,(POD_FIRE_START)
    OR A
    SBC HL,DE
    RET C
    LD A,1 : LD (POD_FIRE_ACTIVE),A
    XOR A : LD (POD_FIRE_TIMER),A
PFU_RUNNING:
    LD A,(POD_FIRE_TIMER)
    DEC A
    LD (POD_FIRE_TIMER),A
    RET P
    LD A,(POD_FIRE_INTERVAL_CUR) : LD (POD_FIRE_TIMER),A
    CALL POD_FIRE_DO_PAIR
    LD A,(POD_FIRE_PAIR) : INC A
    CP 7
    JR NZ,PFU_KEEPPAIR
    XOR A : LD (POD_FIRE_PAIR),A
    LD A,(POD_CYCLE_COUNT) : INC A : LD (POD_CYCLE_COUNT),A
    CP VOLLEY_CYCLES_BEFORE
    RET NZ
    XOR A : LD (POD_CYCLE_COUNT),A
    LD A,(POD_BULLET0_ACT)
    OR A
    JR Z,PFU_NOB0
    XOR A : LD (POD_BULLET0_ACT),A
    CALL POD_BULLET_HIDE0
PFU_NOB0:
    LD A,(POD_BULLET1_ACT)
    OR A
    JR Z,PFU_NOB1
    XOR A : LD (POD_BULLET1_ACT),A
    CALL POD_BULLET_HIDE1
PFU_NOB1:
    CALL COUNT_ALIVE_PODS
    LD (POD_LOOP_ALIVE_SNAPSHOT),A
    LD A,1 : LD (POD_VOLLEY_ACTIVE),A
    LD A,1 : LD (POD_LAP_ACTIVE),A
    XOR A : LD (POD_LAP_STEP),A
    XOR A : LD (POD_LAP_CYCLE),A
    RET
PFU_KEEPPAIR:
    LD (POD_FIRE_PAIR),A
    RET

; fires the current pair (POD_FIRE_PAIR = 0-6, pods P and P+1),
; spawning both bullets at those pods' current orbit positions.
POD_FIRE_DO_PAIR:
    LD A,(POD_FIRE_PAIR)
    LD B,A
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,PFDP_SKIP0
    CALL SOUND_POD_FIRE
    LD A,B
    CALL GET_POD_XY
    LD A,(POD_XY_X) : LD (POD_BULLET0_X),A
    LD A,(POD_XY_Y) : LD (POD_BULLET0_Y),A
    LD A,1 : LD (POD_BULLET0_ACT),A
    LD HL,POD_RECOIL : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),POD_RECOIL_DURATION
    CALL POD_BULLET_DRAW0
PFDP_SKIP0:
    LD A,(POD_FIRE_PAIR) : INC A
    LD B,A
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,PFDP_SKIP1
    CALL SOUND_POD_FIRE
    LD A,B
    CALL GET_POD_XY
    LD A,(POD_XY_X) : LD (POD_BULLET1_X),A
    LD A,(POD_XY_Y) : LD (POD_BULLET1_Y),A
    LD A,1 : LD (POD_BULLET1_ACT),A
    LD HL,POD_RECOIL : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),POD_RECOIL_DURATION
    CALL POD_BULLET_DRAW1
PFDP_SKIP1:
    RET

; called every frame from POD_FIRE_UPDATE. While POD_VOLLEY_ACTIVE,
; moves the 8 launched pods and counts down POD_VOLLEY_TIMER; once
; it hits 0, clears the pause (BOSS_ORBIT_UPDATE then resumes and
; naturally redraws them back at their orbit position/color on its
; very next call - no explicit "restore" needed here).
VOLLEY_UPDATE:
    LD A,(POD_VOLLEY_ACTIVE)
    OR A
    RET Z
    LD A,(POD_LAP_ACTIVE)
    OR A
    JP Z,VU_FIRING
    ; lap phase: two markers, 8px in front of two opposite pods
    ; (step and step+4), advancing one step every single frame - no
    ; hold/delay at all. 8 steps per lap x 3 laps = 24 frames total.
VU_LAP_DOSTEP:
    XOR A : LD (POD_XY_X),A
    LD A,(POD_LAP_STEP)
    LD C,A
    LD HL,POD_HP : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,VU_LAP_HIDE_A
    LD A,1 : LD (POD_XY_X),A
    LD HL,POD_CUR_X : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : SUB 8 : LD (BOSS_ORBIT_XTMP),A
    LD HL,POD_CUR_Y : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_YTMP),A
    CALL LAP_MARKER_DRAW
    JR VU_LAP_STEP_B
VU_LAP_HIDE_A:
    CALL LAP_MARKER_HIDE
VU_LAP_STEP_B:
    LD A,(POD_LAP_STEP)
    ADD A,4
    AND 7
    LD C,A
    LD HL,POD_HP : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,VU_LAP_HIDE_B
    LD A,1 : LD (POD_XY_X),A
    LD HL,POD_CUR_X : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : SUB 8 : LD (BOSS_ORBIT_XTMP),A
    LD HL,POD_CUR_Y : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_YTMP),A
    CALL LAP_MARKER_DRAW2
    JR VU_LAP_STEP_DONE
VU_LAP_HIDE_B:
    CALL LAP_MARKER_HIDE2
VU_LAP_STEP_DONE:
    LD A,(POD_XY_X)
    OR A
    CALL NZ,SOUND_POD_FIRE
    LD A,(POD_LAP_STEP) : INC A
    LD (POD_LAP_STEP),A
    CP 4
    RET C
    XOR A : LD (POD_LAP_STEP),A
    LD A,(POD_LAP_CYCLE) : INC A : LD (POD_LAP_CYCLE),A
    CP LAP_CYCLES
    RET C
    ; all 3 laps done
    XOR A : LD (POD_LAP_ACTIVE),A
    CALL LAP_MARKER_HIDE
    CALL LAP_MARKER_HIDE2
    CALL VOLLEY_FIRE_ALL
    RET
VU_FIRING:
    CALL LAUNCH_MOVE_ALL
    CALL CHECK_ALL_ARRIVED
    RET NZ
    ; round trip done - did this volley cost the boss a pod?
    CALL COUNT_ALIVE_PODS
    LD HL,POD_LOOP_ALIVE_SNAPSHOT
    CP (HL)
    JR NZ,VU_PODLOST
    ; no - loop straight back into another lap+fire, forever
    LD A,1 : LD (POD_LAP_ACTIVE),A
    XOR A : LD (POD_LAP_STEP),A
    XOR A : LD (POD_LAP_CYCLE),A
    RET
VU_PODLOST:
    XOR A : LD (POD_VOLLEY_ACTIVE),A
    LD A,(POD_FIRE_INTERVAL_CUR) : LD (POD_FIRE_TIMER),A
    RET

; B = unused - draws the pre-fire lap marker at POD_LAP_ANGLE's
; position on the shared orbit LUT (a small white hex icon).
; draws the lap marker at whatever's currently in BOSS_ORBIT_XTMP/YTMP
; (the caller fills these in via GET_POD_XY before calling this).

LAP_MARKER_DRAW:
    LD A,LAP_MARKER_SPR : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,15 : OUT (98h),A
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

LAP_MARKER_HIDE:
    LD A,LAP_MARKER_SPR : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

LAP_MARKER_DRAW2:
    LD A,LAP_MARKER_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,15 : OUT (98h),A
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

LAP_MARKER_HIDE2:
    LD A,LAP_MARKER_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

; sets Z if all 8 pods have finished their round trip (phase==1
; AND back at their own VOLLEY_START_X). NZ if any are still
; outbound or still on the way back.
CHECK_ALL_ARRIVED:
    XOR A : LD (POD_XY_X),A
    LD B,0
CAA_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,CAA_OK
    LD HL,VOLLEY_PHASE : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    CP 1
    JR NZ,CAA_NOTYET
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    LD HL,VOLLEY_START_X : LD D,0 : LD E,B : ADD HL,DE
    CP (HL)
    JR Z,CAA_OK
CAA_NOTYET:
    LD A,1 : LD (POD_XY_X),A
CAA_OK:
    POP BC
    INC B
    LD A,B
    CP 8
    JR NZ,CAA_LOOP
    LD A,(POD_XY_X)
    OR A
    RET

; launches all 8 pods at once (in place of firing separate bullet
; sprites, which were hitting some rendering issue - reusing the
; pods' own already-working sprite slots sidesteps it entirely).
; Captures each pod's current orbit position as its launch start,
; then LAUNCH_MOVE_ALL carries it left every frame for the rest of
; the pause.
VOLLEY_FIRE_ALL:
    LD HL,POD_HP
    LD A,(HL) : INC HL
    OR (HL) : INC HL
    OR (HL) : INC HL
    OR (HL) : INC HL
    OR (HL) : INC HL
    OR (HL) : INC HL
    OR (HL) : INC HL
    OR (HL)
    JR Z,VFA_NOSOUND
    CALL SOUND_POD_FIRE
VFA_NOSOUND:
    LD B,0
VFA_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,VFA_SKIP
    LD A,B
    CALL GET_POD_XY
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X) : LD (HL),A
    LD HL,VOLLEY_START_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X) : LD (HL),A
    LD HL,VOLLEY_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y) : LD (HL),A
    LD HL,VOLLEY_PHASE : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),0
    POP BC
    CALL LAUNCH_DRAW
    JR VFA_NEXT
VFA_SKIP:
    POP BC
VFA_NEXT:
    INC B
    LD A,B
    CP 8
    JP NZ,VFA_LOOP
    RET

; moves all 8 launched pods straight left every frame - no
; individual off-screen tracking needed, since they all revert to
; orbiting together the moment POD_VOLLEY_TIMER runs out.
LAUNCH_MOVE_ALL:
    LD A,(POD_VOLLEY_COLOR_TEST) : INC A
    CP 15
    JR C,LMA_COLOR_OK
    LD A,2
LMA_COLOR_OK:
    LD (POD_VOLLEY_COLOR_TEST),A
    LD B,0
LMA_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JP Z,LMA_SKIP
    LD HL,VOLLEY_PHASE : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR NZ,LMA_RETURNING
    ; outbound: flying left
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    CP LAUNCH_SPEED
    JR NC,LMA_OUT_MOVE
    ; hit the left edge - flip to the return leg
    LD HL,VOLLEY_PHASE : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),1
    JR LMA_DRAW
LMA_OUT_MOVE:
    SUB LAUNCH_SPEED
    LD (HL),A
    JR LMA_DRAW
LMA_RETURNING:
    ; return leg: flying right, back toward this pod's own start X
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    ADD A,LAUNCH_SPEED
    LD (HL),A
    LD HL,VOLLEY_START_X : LD D,0 : LD E,B : ADD HL,DE
    LD C,(HL)
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    CP C
    JR C,LMA_DRAW
    LD (HL),C
LMA_DRAW:
    POP BC
    CALL LAUNCH_DRAW
    INC B
    LD A,B
    CP 8
    JP NZ,LMA_LOOP
    RET
LMA_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JP NZ,LMA_LOOP
    RET

; B = pod index (0-7) - draws pod B (its own sprite slot,
; BOSS_ORBIT_BASE+B) at its launched position, in white, still
; using its normal orbit-pod pattern (only the color changes).
LAUNCH_DRAW:
    LD HL,VOLLEY_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_XTMP),A
    LD HL,VOLLEY_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL) : LD (BOSS_ORBIT_YTMP),A
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(BOSS_ORBIT_XTMP) : LD (HL),A
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(BOSS_ORBIT_YTMP) : LD (HL),A
    LD A,BOSS_ORBIT_BASE : ADD A,B
    ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_ORBIT_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,(POD_VOLLEY_COLOR_TEST) : AND 0Fh : OUT (98h),A
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

POD_BULLET_MOVE:
    LD A,(POD_BULLET0_ACT)
    OR A
    JR Z,PBM_B1
    LD A,(POD_BULLET0_X)
    SUB POD_BULLET_SPEED
    JR NC,PBM_B0_OK
    XOR A : LD (POD_BULLET0_ACT),A
    CALL POD_BULLET_HIDE0
    JR PBM_B1
PBM_B0_OK:
    LD (POD_BULLET0_X),A
    CALL POD_BULLET_DRAW0
PBM_B1:
    LD A,(POD_BULLET1_ACT)
    OR A
    RET Z
    LD A,(POD_BULLET1_X)
    SUB POD_BULLET_SPEED
    JR NC,PBM_B1_OK
    XOR A : LD (POD_BULLET1_ACT),A
    CALL POD_BULLET_HIDE1
    RET
PBM_B1_OK:
    LD (POD_BULLET1_X),A
    CALL POD_BULLET_DRAW1
    RET

POD_BULLET_DRAW0:
    LD A,POD_BULLET_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(POD_BULLET0_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(POD_BULLET0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,15 : OUT (98h),A
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

POD_BULLET_DRAW1:
    LD A,POD_BULLET_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(POD_BULLET1_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(POD_BULLET1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,15 : OUT (98h),A
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

POD_BULLET_HIDE0:
    LD A,POD_BULLET_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

POD_BULLET_HIDE1:
    LD A,POD_BULLET_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

; called every frame while BOSS_STATE==1 (materializing only - once
; landed, the SKY_VEC dispatch already handles restoring boss BG
; correctly, so no guard is needed there). Checks each of the 3
; player shots; any that reaches col25 (row1-16) is deflected
; before it can ever touch the boss's own cols26-30, which used to
; leave permanent gaps (the erase there was writing BLANKCODE over
; boss cells that hadn't been safely handled yet).
BOSS_GUARD_UPDATE:
    LD A,(BULLET0_ACT)
    OR A
    JR Z,BGU_1
    LD A,(BULLET0_ROW) : SUB 1 : CP 16 : JR NC,BGU_1
    LD A,(BULLET0_COL) : CP 25 : JR C,BGU_1
    CALL DEFLECT_BULLET0
BGU_1:
    LD A,(BULLET1_ACT)
    OR A
    JR Z,BGU_2
    LD A,(BULLET1_ROW) : SUB 1 : CP 16 : JR NC,BGU_2
    LD A,(BULLET1_COL) : CP 25 : JR C,BGU_2
    CALL DEFLECT_BULLET1
BGU_2:
    LD A,(BULLET2_ACT)
    OR A
    RET Z
    LD A,(BULLET2_ROW) : SUB 1 : CP 16 : RET NC
    LD A,(BULLET2_COL) : CP 25 : RET C
    CALL DEFLECT_BULLET2
    RET

; erases the shot's current BG cell (safe here - col25 is still
; outside the boss's own cols26-30), deactivates it, and spawns a
; deflected sprite in its place with a random left-biased vector.
DEFLECT_BULLET0:
    LD A,(BULLET0_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET0_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET0_ACT),A
    LD A,(BULLET0_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL0_X),A
    LD A,(BULLET0_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL0_Y),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A : AND 7
    LD (DFL0_VEC),A
    LD A,1 : LD (DFL0_ACT),A
    LD A,DFL_LIFESPAN : LD (DFL0_LIFE),A
    EI
    CALL DFL_DRAW0
    RET

DEFLECT_BULLET1:
    LD A,(BULLET1_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET1_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET1_ACT),A
    LD A,(BULLET1_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL1_X),A
    LD A,(BULLET1_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL1_Y),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A : AND 7
    LD (DFL1_VEC),A
    LD A,1 : LD (DFL1_ACT),A
    LD A,DFL_LIFESPAN : LD (DFL1_LIFE),A
    EI
    CALL DFL_DRAW1
    RET

DEFLECT_BULLET2:
    LD A,(BULLET2_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLET2_COL)
    LD D,0 : LD E,A
    ADD HL,DE
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
    LD A,BLANKCODE : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    XOR A : LD (BULLET2_ACT),A
    LD A,(BULLET2_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL2_X),A
    LD A,(BULLET2_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (DFL2_Y),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A : AND 7
    LD (DFL2_VEC),A
    LD A,1 : LD (DFL2_ACT),A
    LD A,DFL_LIFESPAN : LD (DFL2_LIFE),A
    EI
    CALL DFL_DRAW2
    RET

; moves all 3 deflected shots (called every frame from state1 on),
; despawning (hiding) any whose lifespan has run out.
DFL_UPDATE:
    LD A,(DFL0_ACT)
    OR A
    JR Z,DU_1
    CALL DFL_MOVE0
DU_1:
    LD A,(DFL1_ACT)
    OR A
    JR Z,DU_2
    CALL DFL_MOVE1
DU_2:
    LD A,(DFL2_ACT)
    OR A
    RET Z
    CALL DFL_MOVE2
    RET

DFL_MOVE0:
    LD A,(DFL0_LIFE) : DEC A : LD (DFL0_LIFE),A
    JR NZ,DM0_GO
    XOR A : LD (DFL0_ACT),A
    CALL DFL_HIDE0
    RET
DM0_GO:
    LD A,(DFL0_VEC) : LD E,A : LD D,0
    LD HL,DFL_VEC_DX : ADD HL,DE
    LD A,(DFL0_X) : ADD A,(HL) : LD (DFL0_X),A
    LD HL,DFL_VEC_DY : ADD HL,DE
    LD A,(DFL0_Y) : ADD A,(HL) : LD (DFL0_Y),A
    CALL DFL_DRAW0
    RET

DFL_MOVE1:
    LD A,(DFL1_LIFE) : DEC A : LD (DFL1_LIFE),A
    JR NZ,DM1_GO
    XOR A : LD (DFL1_ACT),A
    CALL DFL_HIDE1
    RET
DM1_GO:
    LD A,(DFL1_VEC) : LD E,A : LD D,0
    LD HL,DFL_VEC_DX : ADD HL,DE
    LD A,(DFL1_X) : ADD A,(HL) : LD (DFL1_X),A
    LD HL,DFL_VEC_DY : ADD HL,DE
    LD A,(DFL1_Y) : ADD A,(HL) : LD (DFL1_Y),A
    CALL DFL_DRAW1
    RET

DFL_MOVE2:
    LD A,(DFL2_LIFE) : DEC A : LD (DFL2_LIFE),A
    JR NZ,DM2_GO
    XOR A : LD (DFL2_ACT),A
    CALL DFL_HIDE2
    RET
DM2_GO:
    LD A,(DFL2_VEC) : LD E,A : LD D,0
    LD HL,DFL_VEC_DX : ADD HL,DE
    LD A,(DFL2_X) : ADD A,(HL) : LD (DFL2_X),A
    LD HL,DFL_VEC_DY : ADD HL,DE
    LD A,(DFL2_Y) : ADD A,(HL) : LD (DFL2_Y),A
    CALL DFL_DRAW2
    RET

DFL_DRAW0:
    LD A,DFL_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(DFL0_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(DFL0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,8 : OUT (98h),A
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

DFL_DRAW1:
    LD A,DFL_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(DFL1_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(DFL1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,8 : OUT (98h),A
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

DFL_DRAW2:
    LD A,DFL_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,(DFL2_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,1 : OUT (99h),A
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
    LD A,(DFL2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,2 : OUT (99h),A
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
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,E : ADD A,3 : OUT (99h),A
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
    LD A,8 : OUT (98h),A
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

DFL_HIDE0:
    LD A,DFL_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

DFL_HIDE1:
    LD A,DFL_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

DFL_HIDE2:
    LD A,DFL_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
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
    LD A,209 : OUT (98h),A
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

; 8 fixed deflection vectors, all leftward-biased (dx always
; negative - never sends a shot back toward the boss). Doubled
; magnitude for faster movement.
DFL_VEC_DX:
    DB 0FAh,0FAh,0FAh,0FAh,0FAh,0FCh,0FCh,0FEh   ; -6,-6,-6,-6,-6,-4,-4,-2
DFL_VEC_DY:
    DB 0FCh,0FEh,00h,02h,04h,0FAh,06h,0FCh        ; -4,-2,0,2,4,-6,6,-4

; Picks a free unified-pool slot and spawns ONE Enemy1-style unit
; there (BEHAVIOR_SIMPLE_DRIFT_DODGE) at the Y implied by
; SPAWN_NEXT_INDEX's position in its wave (1-3=top,4-6=bottom,
; 7-9=top,10-12=bottom). Each spawn is independent - not a
; synchronized group. If the pool (or the 6 physical sprite-pattern
; slots this BEHAVIOR needs, see ALLOC_PATTERN_SLOT) is exhausted,
; the spawn is simply dropped, same as before.
; Enemy1 needs only one type: its dodge direction is already decided
; dynamically at screen center from PLAYERY vs its own Y (see
; EBSD_UPDATE), not from which spawn slot it came from - so it isn't
; restricted to 2 fixed rows (ENEMY_Y0/ENEMY_Y1) like the old TOP/BOT
; split implied. A can spawn at any Y. On entry A = this schedule
; index (SSC_FIRE's CP-dispatch leaves the pre-increment index in A),
; used to look up this spawn's Y in SPAWN_SIMPLE_Y_TABLE.
SPAWN_SIMPLE:
    LD H,0 : LD L,A
    LD DE,SPAWN_SIMPLE_Y_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (SPAWN_E1_Y),A
    JR ENEMY1_CLAIM_ANY

; Claims a free ENEMY_POOL slot AND a free physical sprite-pattern
; slot (this BEHAVIOR needs its own mutable 32-byte VRAM pattern per
; instance, for the independent TOP/BOT quadrant redraw - see
; SIMPLE_REDRAW) for a fresh BEHAVIOR_SIMPLE_DRIFT_DODGE spawn at the
; right edge, Y from SPAWN_E1_Y, both quadrants alive. Drops the
; spawn (rolling back any partial claim) if either pool is full.
ENEMY1_CLAIM_ANY:
    CALL ALLOC_PATTERN_SLOT
    CP 0FFh
    RET Z
    PUSH AF
    CALL ALLOC_ENEMY_SLOT
    OR A
    JR NZ,E1CA_GOTSLOT
    POP AF
    CALL FREE_PATTERN_SLOT
    RET
E1CA_GOTSLOT:
    POP AF
    LD (IX+E_PARAM3),A
    LD A,BEHAVIOR_SIMPLE_DRIFT_DODGE : LD (IX+E_BEHAVIOR),A
    LD A,ENEMY_SPAWNX : LD (IX+E_X),A
    LD A,(SPAWN_E1_Y) : LD (IX+E_Y),A
    LD A,1 : LD (IX+E_TOP),A : LD (IX+E_BOT),A
    CALL ALLOC_SPRITE_NUM : LD (IX+E_SPRNUM),A
    PUSH IX : POP HL
    LD A,(IX+E_PARAM3)
    JP SIMPLE_REDRAW

; true free-list sprite-number allocator: scans SPRITE_USED[2..31]
; for the first byte still 0 (free), claims it (sets 1), returns its
; number in A. Unlike the old blind round-robin counter, this can
; never hand out a number that's still in use elsewhere, which is
; what was corrupting a still-displayed enemy's VDP attribute entry
; (stray white Y=0 sprites - the two writers were racing on the same
; attribute-table slot). Returns A=0 if all 30 are taken (should not
; happen - current max concurrent users is well under 30); callers
; don't currently check for this since it can't occur in practice.
ALLOC_SPRITE_NUM:
    LD HL,SPRITE_USED+2
    LD B,30
ASN_SCAN:
    LD A,(HL)
    OR A
    JR Z,ASN_FOUND
    INC HL
    DJNZ ASN_SCAN
    XOR A
    RET
ASN_FOUND:
    LD A,1 : LD (HL),A
    LD A,32
    SUB B
    RET

; releases a sprite number back to the free pool once its owner is
; done with it (destroyed or exited off-screen). Input: A = the
; number to free. Must be called exactly once per successful
; ALLOC_SPRITE_NUM, at the moment that number stops being drawn.
FREE_SPRITE_NUM:
    LD HL,SPRITE_USED
    LD D,0 : LD E,A
    ADD HL,DE
    XOR A : LD (HL),A
    RET

; Clears every slot of the unified enemy buffer (ACTIVE=0) and resets
; both shared trail-channel write indices. Called once from INIT.
ENEMY_POOL_INIT:
    LD HL,ENEMY_POOL
    LD DE,ENEMY_POOL+1
    LD BC,ENEMY_SLOT_SIZE*ENEMY_SLOT_COUNT-1
    LD (HL),0
    LDIR
    XOR A
    LD (ENEMY_TRAIL_CH_WIDX+0),A
    LD (ENEMY_TRAIL_CH_WIDX+1),A
    RET

; Scans the unified enemy buffer for a free (ACTIVE=0) slot. On
; success: IX = that slot's base address (zeroed first, so every field
; starts at 0 without each movement algorithm having to clear its own
; scratch fields), (IX+E_ACTIVE) is set to 1, and A=1. On failure
; (buffer full): A=0, IX is undefined. Uses HL to scan (the assembler
; here has no ADD IX,rr), then PUSH HL:POP IX once a slot is found.
; Trashes A,B,DE,HL,IX.
ALLOC_ENEMY_SLOT:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
AES_SCAN:
    LD A,(HL)
    OR A
    JR Z,AES_FOUND
    LD DE,ENEMY_SLOT_SIZE
    ADD HL,DE
    DJNZ AES_SCAN
    XOR A
    RET
AES_FOUND:
    PUSH HL : POP IX
    LD (HL),0
    LD D,H : LD E,L : INC DE
    LD BC,ENEMY_SLOT_SIZE-1
    LDIR
    LD (IX+E_ACTIVE),1
    LD A,1
    RET

; Releases a slot back to the free pool: frees its hardware sprite
; number (if any) and zeroes ACTIVE. Input: IX = slot base address.
; Does not hide the sprite on screen - the caller must do that (hide
; at the offscreen Y, same as the legacy per-type EXIT paths) before
; freeing, since a freed sprite number may be reassigned to a new
; owner as soon as the next ALLOC_SPRITE_NUM runs.
FREE_ENEMY_SLOT:
    LD A,(IX+E_ACTIVE)
    OR A
    RET Z
    LD A,(IX+E_SPRNUM)
    OR A
    CALL NZ,FREE_SPRITE_NUM
    XOR A
    LD (IX+E_ACTIVE),A
    RET

; Claims one of the 6 physical sprite-pattern slots BEHAVIOR_SIMPLE_
; DRIFT_DODGE needs (see the comment above SIMPLE_PATTERN_NUMS).
; Output: A = claimed index (0-5), or A=0FFh if all 6 are taken.
ALLOC_PATTERN_SLOT:
    LD HL,SIMPLE_PATTERN_USED
    LD B,SIMPLE_PATTERN_SLOTS
APS_SCAN:
    LD A,(HL)
    OR A
    JR Z,APS_FOUND
    INC HL
    DJNZ APS_SCAN
    LD A,0FFh
    RET
APS_FOUND:
    LD A,1 : LD (HL),A
    LD A,SIMPLE_PATTERN_SLOTS
    SUB B
    RET

; Input: A = pattern-slot index (0-5) to release.
FREE_PATTERN_SLOT:
    LD HL,SIMPLE_PATTERN_USED
    LD D,0 : LD E,A
    ADD HL,DE
    XOR A : LD (HL),A
    RET

; Input: A = pattern-slot index (0-5). Output: HL = that slot's VRAM
; pattern address. Trashes A,D,E.
SIMPLE_PATTERN_LOOKUP:
    ADD A,A : LD E,A : LD D,0
    LD HL,SIMPLE_PATTERN_VRAM
    ADD HL,DE
    LD A,(HL) : INC HL : LD H,(HL) : LD L,A
    RET

; Input: A = pattern-slot index (0-5). Output: A = that slot's sprite
; pattern number (for the OUT (98h) attribute write). Trashes H,L,D,E.
SIMPLE_PATTERN_NUM:
    LD E,A : LD D,0
    LD HL,SIMPLE_PATTERN_NUMS
    ADD HL,DE
    LD A,(HL)
    RET

; Rebuilds a BEHAVIOR_SIMPLE_DRIFT_DODGE slot's owned VRAM sprite
; pattern from its current TOP/BOT flags (mirrors the legacy per-unit
; REDRAW_UNIT_PATTERN call sites). Input: HL = slot base address
; (absolute), A = that slot's pattern-slot index (E_PARAM3). Tail-
; calls into REDRAW_UNIT_PATTERN, which itself takes IX as an input
; (the BOT-flag address) - callers that still need their own IX/slot
; pointer afterward must save it themselves (see SIMPLE_SLOT_SCRATCH
; use in EBSD_HIT_TEST). Trashes A,B,D,E,H,L,IX.
SIMPLE_REDRAW:
    LD (SIMPLE_SLOT_SCRATCH),HL
    CALL SIMPLE_PATTERN_LOOKUP        ; A(idx) -> HL = vram addr
    PUSH HL
    LD HL,(SIMPLE_SLOT_SCRATCH)
    LD DE,E_TOP : ADD HL,DE
    PUSH HL : POP DE                  ; DE = TOP-flag address
    LD HL,(SIMPLE_SLOT_SCRATCH)
    LD BC,E_BOT : ADD HL,BC
    PUSH HL : POP IX                  ; IX = BOT-flag address
    POP HL                            ; HL = vram addr
    JP REDRAW_UNIT_PATTERN

SPAWN_E2_TOP_A:
    LD A,2 : LD (ENEMY_CYCLE),A
    JP ENEMY_START_COMPLEX_A
SPAWN_E2_BOT_A:
    LD A,3 : LD (ENEMY_CYCLE),A
    JP ENEMY_START_COMPLEX_B
SPAWN_E2_TOP_B:
    LD A,2 : LD (ENEMY_CYCLE),A
    JP ENEMY_START_COMPLEX_A
SPAWN_E2_BOT_B:
    LD A,3 : LD (ENEMY_CYCLE),A
    JP ENEMY_START_COMPLEX_B
; A holds this schedule index on entry (SSC_FIRE's CP-dispatch convention -
; see SPAWN_SIMPLE/SPAWN_E4 for the same pattern) - used to look up this
; trigger's own offset in SPAWN_E3_OFFSET_TABLE.
SPAWN_E3_WAVE:
    LD H,0 : LD L,A
    LD DE,SPAWN_E3_OFFSET_TABLE
    ADD HL,DE
    LD A,(HL) : LD (ENEMY3_CURRENT_OFFSET),A
    LD A,32 : LD (ENEMY3_BUDGET),A
    XOR A : LD (ENEMY3_SPAWN_COUNT),A
    LD A,1 : LD (ENEMY3_SPAWN_TIMER),A
    RET

; Draws all 3 units together from the shared ENEMY_X/ENEMY_Y group
; position (unit1=+16,unit2=+32), always visible - used once the
; complex sequence has fully assembled (drift + Z-exit phases).
; Also keeps ENEMY0_X/1_X/2_X in sync so collision detection (which
; always reads those, regardless of mode) stays correct.
ENEMY_DRAW_ALL_COMPLEX_A:
    LD A,(E2A_X) : LD (E2A_U0_X),A
    ADD A,16 : LD (E2A_U1_X),A
    LD A,(E2A_X) : ADD A,32 : LD (E2A_U2_X),A
    LD A,(E2A_Y) : LD (E2A_U0_Y),A : LD (E2A_U1_Y),A : LD (E2A_U2_Y),A
    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

; Draws all 3 units at their OWN independent (X,Y) - used during the
; snake-trail exit phase, where unit1/unit2 no longer share the
; leader's position/offset but instead follow its recorded path.
ENEMY_DRAW_SNAKE_A:
    LD A,(E2A_U0_EXITED) : OR A
    JR Z,EDS_U0_REAL_A
    LD A,ENEMY_HIDE_Y
    JR EDS_U0_SET_A
EDS_U0_REAL_A:
    LD A,(E2A_U0_Y)
EDS_U0_SET_A:
    LD (E2A_EDS_Y0),A

    LD A,(E2A_U1_EXITED) : OR A
    JR Z,EDS_U1_REAL_A
    LD A,ENEMY_HIDE_Y
    JR EDS_U1_SET_A
EDS_U1_REAL_A:
    LD A,(E2A_U1_Y)
EDS_U1_SET_A:
    LD (E2A_EDS_Y1),A

    LD A,(E2A_U2_EXITED) : OR A
    JR Z,EDS_U2_REAL_A
    LD A,ENEMY_HIDE_Y
    JR EDS_U2_SET_A
EDS_U2_REAL_A:
    LD A,(E2A_U2_Y)
EDS_U2_SET_A:
    LD (E2A_EDS_Y2),A

    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_EDS_Y0) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_EDS_Y1) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_EDS_Y2) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

; Complex-mode per-frame state machine (E2A_SEQ_STATE 0-8):
; 0/1 = unit0's top-quadrant/bottom-quadrant fly in fast (8px/frame)
;       from the right edge to TARGETX0 and merge into slot1
; 2/3 = same for unit1 at TARGETX0+16 (slot2)
; 4/5 = same for unit2 at TARGETX0+32 (slot3)
; 6   = whole formation drifts left slowly (ENEMY_SPEED) for DRIFT_LEN
; 7   = fast Z (or mirrored-Z) exit off the left edge
; 8   = sequence finished -> back to simple mode, advance cycle
ENEMY_COMPLEX_STEP_A:
    LD A,(E2A_ACTIVE)
    OR A
    RET Z
    LD A,(E2A_SEQ_STATE)
    CP 0 : JP Z,ECS_S0_A
    CP 1 : JP Z,ECS_S1_A
    CP 2 : JP Z,ECS_S2_A
    CP 3 : JP Z,ECS_S3_A
    CP 4 : JP Z,ECS_S4_A
    CP 5 : JP Z,ECS_S5_A
    CP 6 : JP Z,ECS_S6_A
    CP 7 : JP Z,ECS_S7_A
    JP ECS_S8_A

ECS_S0_A:
    LD A,(E2A_U0_X)
    CP TARGETX0
    JR Z,ECS_S0_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0
    JR NC,ECS_S0_SAVE_A
    LD A,TARGETX0
ECS_S0_SAVE_A:
    LD (E2A_U0_X),A
    JR ECS_S0_DRAW_A
ECS_S0_ARRIVED_A:
    LD A,1 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_TEMP_X),A
ECS_S0_DRAW_A:
    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S1_A:
    LD A,(E2A_TEMP_X)
    CP TARGETX0
    JR Z,ECS_S1_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0
    JR NC,ECS_S1_SAVE_A
    LD A,TARGETX0
ECS_S1_SAVE_A:
    LD (E2A_TEMP_X),A
    JP ECS_S1_DRAW_A
ECS_S1_ARRIVED_A:
    LD A,1 : LD (E2A_U0_STATE),A
    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,2 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_U1_X),A
    EI
    RET
ECS_S1_DRAW_A:
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S2_A:
    LD A,(E2A_U1_X)
    CP TARGETX0+16
    JR Z,ECS_S2_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0+16
    JR NC,ECS_S2_SAVE_A
    LD A,TARGETX0+16
ECS_S2_SAVE_A:
    LD (E2A_U1_X),A
    JR ECS_S2_DRAW_A
ECS_S2_ARRIVED_A:
    LD A,3 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_TEMP_X),A
ECS_S2_DRAW_A:
    DI
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S3_A:
    LD A,(E2A_TEMP_X)
    CP TARGETX0+16
    JR Z,ECS_S3_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0+16
    JR NC,ECS_S3_SAVE_A
    LD A,TARGETX0+16
ECS_S3_SAVE_A:
    LD (E2A_TEMP_X),A
    JP ECS_S3_DRAW_A
ECS_S3_ARRIVED_A:
    LD A,1 : LD (E2A_U1_STATE),A
    DI
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,4 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_U2_X),A
    EI
    RET
ECS_S3_DRAW_A:
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S4_A:
    LD A,(E2A_U2_X)
    CP TARGETX0+32
    JR Z,ECS_S4_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0+32
    JR NC,ECS_S4_SAVE_A
    LD A,TARGETX0+32
ECS_S4_SAVE_A:
    LD (E2A_U2_X),A
    JR ECS_S4_DRAW_A
ECS_S4_ARRIVED_A:
    LD A,5 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_TEMP_X),A
ECS_S4_DRAW_A:
    DI
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S5_A:
    LD A,(E2A_TEMP_X)
    CP TARGETX0+32
    JR Z,ECS_S5_ARRIVED_A
    SUB FASTJUMP
    CP TARGETX0+32
    JR NC,ECS_S5_SAVE_A
    LD A,TARGETX0+32
ECS_S5_SAVE_A:
    LD (E2A_TEMP_X),A
    JP ECS_S5_DRAW_A
ECS_S5_ARRIVED_A:
    LD A,1 : LD (E2A_U2_STATE),A
    DI
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,TARGETX0 : LD (E2A_X),A
    XOR A : LD (E2A_PROGRESS),A
    LD A,6 : LD (E2A_SEQ_STATE),A
    EI
    RET
ECS_S5_DRAW_A:
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2A_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S6_A:
    LD A,(E2A_X)
    SUB ENEMY_SPEED
    LD (E2A_X),A
    LD A,(E2A_PROGRESS)
    ADD A,ENEMY_SPEED
    LD (E2A_PROGRESS),A
    CP DRIFT_LEN
    JR C,ECS_S6_DRAW_A
    XOR A : LD (E2A_PROGRESS),A
    LD A,7 : LD (E2A_SEQ_STATE),A
ECS_S6_DRAW_A:
    CALL ENEMY_DRAW_ALL_COMPLEX_A
    LD A,(E2A_SEQ_STATE)
    CP 7
    RET NZ
    ; --- just switched to state7: set up the diagonal+snake exit ---
    XOR A : LD (E2A_EXIT_PHASE),A
    XOR A : LD (E2A_U0_EXITED),A : LD (E2A_U1_EXITED),A : LD (E2A_U2_EXITED),A
    LD A,(E2A_U0_X) : LD C,A
    LD A,(E2A_U0_Y) : LD D,A
    LD HL,E2A_TRAIL_HIST
    LD B,TRAIL_BUFLEN
ECS_S6_PREFILL_A:
    LD A,C : LD (HL),A : INC HL
    LD A,D : LD (HL),A : INC HL
    DJNZ ECS_S6_PREFILL_A
    XOR A : LD (E2A_TRAIL_WIDX),A
    RET

; Once assembled and drifted, the formation stops moving as a rigid
; block: the leader (unit0) dives/climbs diagonally to the opposite
; vertical extreme, then flattens into a horizontal exit; units1/2
; don't keep the box formation - they trail the leader's own past
; path (like Gradius Options), read out of a ring buffer of its
; recent (X,Y) history.
ECS_S7_A:
    LD A,(E2A_EXIT_PHASE)
    OR A
    JR NZ,ECS_S7_HORIZ_A

    LD A,(E2A_U0_X) : ADD A,EXIT_SPEED : LD (E2A_U0_X),A
    LD A,(E2A_EXITTYPE)
    OR A
    JR Z,ECS_S7_DOWN_A
    LD A,(E2A_U0_Y) : SUB EXIT_SPEED : LD (E2A_U0_Y),A
    LD A,TOP_Y
    JR ECS_S7_CHECKY_A
ECS_S7_DOWN_A:
    LD A,(E2A_U0_Y) : ADD A,EXIT_SPEED : LD (E2A_U0_Y),A
    LD A,ENEMY_Y1
ECS_S7_CHECKY_A:
    LD B,A
    LD A,(E2A_U0_Y)
    CP B
    JR NZ,ECS_S7_RECORD_A
    LD A,1 : LD (E2A_EXIT_PHASE),A
    JR ECS_S7_RECORD_A

ECS_S7_HORIZ_A:
    LD A,(E2A_U0_X)
    CP EXIT_SPEED
    JR C,ECS_S7_LEADER_STOP_A
    SUB EXIT_SPEED
    LD (E2A_U0_X),A
    JR ECS_S7_RECORD_A
ECS_S7_LEADER_STOP_A:
    XOR A : LD (E2A_U0_X),A

ECS_S7_RECORD_A:
    LD A,(E2A_TRAIL_WIDX)
    INC A
    AND TRAIL_BUFLEN-1
    LD (E2A_TRAIL_WIDX),A
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2A_TRAIL_HIST
    ADD HL,DE
    LD A,(E2A_U0_X) : LD (HL),A : INC HL
    LD A,(E2A_U0_Y) : LD (HL),A

    LD A,(E2A_TRAIL_WIDX)
    SUB TRAIL_DELAY
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2A_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2A_U1_X),A
    INC HL
    LD A,(HL) : LD (E2A_U1_Y),A

    LD A,(E2A_TRAIL_WIDX)
    SUB TRAIL_DELAY*2
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2A_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2A_U2_X),A
    INC HL
    LD A,(HL) : LD (E2A_U2_Y),A

    ; each unit hides independently the moment IT reaches the left
    ; edge (same as ENEMY2 in simple mode) instead of all 3 waiting
    ; for each other
    LD A,(E2A_U0_EXITED) : OR A : JR NZ,ECS_S7_U0_DONE_A
    LD A,(E2A_U0_X) : CP EXIT_SPEED : JR NC,ECS_S7_U0_DONE_A
    LD A,1 : LD (E2A_U0_EXITED),A
ECS_S7_U0_DONE_A:
    LD A,(E2A_U1_EXITED) : OR A : JR NZ,ECS_S7_U1_DONE_A
    LD A,(E2A_U1_X) : CP EXIT_SPEED : JR NC,ECS_S7_U1_DONE_A
    LD A,1 : LD (E2A_U1_EXITED),A
ECS_S7_U1_DONE_A:
    LD A,(E2A_U2_EXITED) : OR A : JR NZ,ECS_S7_U2_DONE_A
    LD A,(E2A_U2_X) : CP EXIT_SPEED : JR NC,ECS_S7_U2_DONE_A
    LD A,1 : LD (E2A_U2_EXITED),A
ECS_S7_U2_DONE_A:

    LD A,(E2A_U0_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_A
    LD A,(E2A_U1_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_A
    LD A,(E2A_U2_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_A
    CALL ENEMY_HIDE_ALL3_A
    JP ECS_S7_OFFSCREEN_A
ECS_S7_STILLGOING_A:
    CALL ENEMY_DRAW_SNAKE_A
    RET

; Hides all 3 formation-unit sprite slots (Y=ENEMY_HIDE_Y).
ENEMY_HIDE_ALL3_A:
    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
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

ECS_S7_OFFSCREEN_A:
    LD A,8 : LD (E2A_SEQ_STATE),A
    RET

ECS_S8_A:
    CALL ENEMY_HIDE_ALL3_A
    LD A,2
    LD (E2A_U0_STATE),A : LD (E2A_U1_STATE),A : LD (E2A_U2_STATE),A
    LD A,(E2A_U0_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2A_U1_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2A_U2_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2A_TEMP_SPRNUM) : CALL FREE_SPRITE_NUM
    XOR A : LD (E2A_ACTIVE),A
    RET

ENEMY_DRAW_ALL_COMPLEX_B:
    LD A,(E2B_X) : LD (E2B_U0_X),A
    ADD A,16 : LD (E2B_U1_X),A
    LD A,(E2B_X) : ADD A,32 : LD (E2B_U2_X),A
    LD A,(E2B_Y) : LD (E2B_U0_Y),A : LD (E2B_U1_Y),A : LD (E2B_U2_Y),A
    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

; Draws all 3 units at their OWN independent (X,Y) - used during the
; snake-trail exit phase, where unit1/unit2 no longer share the
; leader's position/offset but instead follow its recorded path.
ENEMY_DRAW_SNAKE_B:
    LD A,(E2B_U0_EXITED) : OR A
    JR Z,EDS_U0_REAL_B
    LD A,ENEMY_HIDE_Y
    JR EDS_U0_SET_B
EDS_U0_REAL_B:
    LD A,(E2B_U0_Y)
EDS_U0_SET_B:
    LD (E2B_EDS_Y0),A

    LD A,(E2B_U1_EXITED) : OR A
    JR Z,EDS_U1_REAL_B
    LD A,ENEMY_HIDE_Y
    JR EDS_U1_SET_B
EDS_U1_REAL_B:
    LD A,(E2B_U1_Y)
EDS_U1_SET_B:
    LD (E2B_EDS_Y1),A

    LD A,(E2B_U2_EXITED) : OR A
    JR Z,EDS_U2_REAL_B
    LD A,ENEMY_HIDE_Y
    JR EDS_U2_SET_B
EDS_U2_REAL_B:
    LD A,(E2B_U2_Y)
EDS_U2_SET_B:
    LD (E2B_EDS_Y2),A

    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_EDS_Y0) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_EDS_Y1) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_EDS_Y2) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

; Complex-mode per-frame state machine (E2B_SEQ_STATE 0-8):
; 0/1 = unit0's top-quadrant/bottom-quadrant fly in fast (8px/frame)
;       from the right edge to TARGETX0 and merge into slot1
; 2/3 = same for unit1 at TARGETX0+16 (slot2)
; 4/5 = same for unit2 at TARGETX0+32 (slot3)
; 6   = whole formation drifts left slowly (ENEMY_SPEED) for DRIFT_LEN
; 7   = fast Z (or mirrored-Z) exit off the left edge
; 8   = sequence finished -> back to simple mode, advance cycle
ENEMY_COMPLEX_STEP_B:
    LD A,(E2B_ACTIVE)
    OR A
    RET Z
    LD A,(E2B_SEQ_STATE)
    CP 0 : JP Z,ECS_S0_B
    CP 1 : JP Z,ECS_S1_B
    CP 2 : JP Z,ECS_S2_B
    CP 3 : JP Z,ECS_S3_B
    CP 4 : JP Z,ECS_S4_B
    CP 5 : JP Z,ECS_S5_B
    CP 6 : JP Z,ECS_S6_B
    CP 7 : JP Z,ECS_S7_B
    JP ECS_S8_B

ECS_S0_B:
    LD A,(E2B_U0_X)
    CP TARGETX0
    JR Z,ECS_S0_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0
    JR NC,ECS_S0_SAVE_B
    LD A,TARGETX0
ECS_S0_SAVE_B:
    LD (E2B_U0_X),A
    JR ECS_S0_DRAW_B
ECS_S0_ARRIVED_B:
    LD A,1 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_TEMP_X),A
ECS_S0_DRAW_B:
    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S1_B:
    LD A,(E2B_TEMP_X)
    CP TARGETX0
    JR Z,ECS_S1_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0
    JR NC,ECS_S1_SAVE_B
    LD A,TARGETX0
ECS_S1_SAVE_B:
    LD (E2B_TEMP_X),A
    JP ECS_S1_DRAW_B
ECS_S1_ARRIVED_B:
    LD A,1 : LD (E2B_U0_STATE),A
    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B0 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,2 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_U1_X),A
    EI
    RET
ECS_S1_DRAW_B:
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S2_B:
    LD A,(E2B_U1_X)
    CP TARGETX0+16
    JR Z,ECS_S2_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0+16
    JR NC,ECS_S2_SAVE_B
    LD A,TARGETX0+16
ECS_S2_SAVE_B:
    LD (E2B_U1_X),A
    JR ECS_S2_DRAW_B
ECS_S2_ARRIVED_B:
    LD A,3 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_TEMP_X),A
ECS_S2_DRAW_B:
    DI
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S3_B:
    LD A,(E2B_TEMP_X)
    CP TARGETX0+16
    JR Z,ECS_S3_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0+16
    JR NC,ECS_S3_SAVE_B
    LD A,TARGETX0+16
ECS_S3_SAVE_B:
    LD (E2B_TEMP_X),A
    JP ECS_S3_DRAW_B
ECS_S3_ARRIVED_B:
    LD A,1 : LD (E2B_U1_STATE),A
    DI
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B1 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,4 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_U2_X),A
    EI
    RET
ECS_S3_DRAW_B:
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S4_B:
    LD A,(E2B_U2_X)
    CP TARGETX0+32
    JR Z,ECS_S4_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0+32
    JR NC,ECS_S4_SAVE_B
    LD A,TARGETX0+32
ECS_S4_SAVE_B:
    LD (E2B_U2_X),A
    JR ECS_S4_DRAW_B
ECS_S4_ARRIVED_B:
    LD A,5 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_TEMP_X),A
ECS_S4_DRAW_B:
    DI
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S5_B:
    LD A,(E2B_TEMP_X)
    CP TARGETX0+32
    JR Z,ECS_S5_ARRIVED_B
    SUB FASTJUMP
    CP TARGETX0+32
    JR NC,ECS_S5_SAVE_B
    LD A,TARGETX0+32
ECS_S5_SAVE_B:
    LD (E2B_TEMP_X),A
    JP ECS_S5_DRAW_B
ECS_S5_ARRIVED_B:
    LD A,1 : LD (E2B_U2_STATE),A
    DI
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B2 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,TARGETX0 : LD (E2B_X),A
    XOR A : LD (E2B_PROGRESS),A
    LD A,6 : LD (E2B_SEQ_STATE),A
    EI
    RET
ECS_S5_DRAW_B:
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(E2B_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

ECS_S6_B:
    LD A,(E2B_X)
    SUB ENEMY_SPEED
    LD (E2B_X),A
    LD A,(E2B_PROGRESS)
    ADD A,ENEMY_SPEED
    LD (E2B_PROGRESS),A
    CP DRIFT_LEN
    JR C,ECS_S6_DRAW_B
    XOR A : LD (E2B_PROGRESS),A
    LD A,7 : LD (E2B_SEQ_STATE),A
ECS_S6_DRAW_B:
    CALL ENEMY_DRAW_ALL_COMPLEX_B
    LD A,(E2B_SEQ_STATE)
    CP 7
    RET NZ
    ; --- just switched to state7: set up the diagonal+snake exit ---
    XOR A : LD (E2B_EXIT_PHASE),A
    XOR A : LD (E2B_U0_EXITED),A : LD (E2B_U1_EXITED),A : LD (E2B_U2_EXITED),A
    LD A,(E2B_U0_X) : LD C,A
    LD A,(E2B_U0_Y) : LD D,A
    LD HL,E2B_TRAIL_HIST
    LD B,TRAIL_BUFLEN
ECS_S6_PREFILL_B:
    LD A,C : LD (HL),A : INC HL
    LD A,D : LD (HL),A : INC HL
    DJNZ ECS_S6_PREFILL_B
    XOR A : LD (E2B_TRAIL_WIDX),A
    RET

; Once assembled and drifted, the formation stops moving as a rigid
; block: the leader (unit0) dives/climbs diagonally to the opposite
; vertical extreme, then flattens into a horizontal exit; units1/2
; don't keep the box formation - they trail the leader's own past
; path (like Gradius Options), read out of a ring buffer of its
; recent (X,Y) history.
ECS_S7_B:
    LD A,(E2B_EXIT_PHASE)
    OR A
    JR NZ,ECS_S7_HORIZ_B

    LD A,(E2B_U0_X) : ADD A,EXIT_SPEED : LD (E2B_U0_X),A
    LD A,(E2B_EXITTYPE)
    OR A
    JR Z,ECS_S7_DOWN_B
    LD A,(E2B_U0_Y) : SUB EXIT_SPEED : LD (E2B_U0_Y),A
    LD A,TOP_Y
    JR ECS_S7_CHECKY_B
ECS_S7_DOWN_B:
    LD A,(E2B_U0_Y) : ADD A,EXIT_SPEED : LD (E2B_U0_Y),A
    LD A,ENEMY_Y1
ECS_S7_CHECKY_B:
    LD B,A
    LD A,(E2B_U0_Y)
    CP B
    JR NZ,ECS_S7_RECORD_B
    LD A,1 : LD (E2B_EXIT_PHASE),A
    JR ECS_S7_RECORD_B

ECS_S7_HORIZ_B:
    LD A,(E2B_U0_X)
    CP EXIT_SPEED
    JR C,ECS_S7_LEADER_STOP_B
    SUB EXIT_SPEED
    LD (E2B_U0_X),A
    JR ECS_S7_RECORD_B
ECS_S7_LEADER_STOP_B:
    XOR A : LD (E2B_U0_X),A

ECS_S7_RECORD_B:
    LD A,(E2B_TRAIL_WIDX)
    INC A
    AND TRAIL_BUFLEN-1
    LD (E2B_TRAIL_WIDX),A
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2B_TRAIL_HIST
    ADD HL,DE
    LD A,(E2B_U0_X) : LD (HL),A : INC HL
    LD A,(E2B_U0_Y) : LD (HL),A

    LD A,(E2B_TRAIL_WIDX)
    SUB TRAIL_DELAY
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2B_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2B_U1_X),A
    INC HL
    LD A,(HL) : LD (E2B_U1_Y),A

    LD A,(E2B_TRAIL_WIDX)
    SUB TRAIL_DELAY*2
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2B_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2B_U2_X),A
    INC HL
    LD A,(HL) : LD (E2B_U2_Y),A

    ; each unit hides independently the moment IT reaches the left
    ; edge (same as ENEMY2 in simple mode) instead of all 3 waiting
    ; for each other
    LD A,(E2B_U0_EXITED) : OR A : JR NZ,ECS_S7_U0_DONE_B
    LD A,(E2B_U0_X) : CP EXIT_SPEED : JR NC,ECS_S7_U0_DONE_B
    LD A,1 : LD (E2B_U0_EXITED),A
ECS_S7_U0_DONE_B:
    LD A,(E2B_U1_EXITED) : OR A : JR NZ,ECS_S7_U1_DONE_B
    LD A,(E2B_U1_X) : CP EXIT_SPEED : JR NC,ECS_S7_U1_DONE_B
    LD A,1 : LD (E2B_U1_EXITED),A
ECS_S7_U1_DONE_B:
    LD A,(E2B_U2_EXITED) : OR A : JR NZ,ECS_S7_U2_DONE_B
    LD A,(E2B_U2_X) : CP EXIT_SPEED : JR NC,ECS_S7_U2_DONE_B
    LD A,1 : LD (E2B_U2_EXITED),A
ECS_S7_U2_DONE_B:

    LD A,(E2B_U0_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_B
    LD A,(E2B_U1_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_B
    LD A,(E2B_U2_EXITED) : OR A : JR Z,ECS_S7_STILLGOING_B
    CALL ENEMY_HIDE_ALL3_B
    JP ECS_S7_OFFSCREEN_B
ECS_S7_STILLGOING_B:
    CALL ENEMY_DRAW_SNAKE_B
    RET

; Hides all 3 formation-unit sprite slots (Y=ENEMY_HIDE_Y).
ENEMY_HIDE_ALL3_B:
    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
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

ECS_S7_OFFSCREEN_B:
    LD A,8 : LD (E2B_SEQ_STATE),A
    RET

ECS_S8_B:
    CALL ENEMY_HIDE_ALL3_B
    LD A,2
    LD (E2B_U0_STATE),A : LD (E2B_U1_STATE),A : LD (E2B_U2_STATE),A
    LD A,(E2B_U0_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2B_U1_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2B_U2_SPRNUM) : CALL FREE_SPRITE_NUM
    LD A,(E2B_TEMP_SPRNUM) : CALL FREE_SPRITE_NUM
    XOR A : LD (E2B_ACTIVE),A
    RET


; ============================================================
; enemy3: nametable-only pulsing dot, LUT circular orbit
; ============================================================

; Called from SPAWN_SCHEDULE_CHECK, once per tick, 3 times per wave
; (9 calls total: ticks140-142 at Y32, 150-152 at Y64, 160-162 at
; Y72 - same mechanism as Enemy1/2, right after Enemy2 in the
; schedule). Each call claims ONE free pool slot, if any; if all 3
; are still busy the spawn is simply dropped (same skip-if-busy
; behavior as Enemy1's SOE1_TOP/BOT).
; baseY used to be one of 3 presets (32/64/72) picked by which of
; SPAWN_E4_Y16/Y32/Y48 was called. Now reads any baseY from
; SPAWN_BASEY_TABLE (indexed the same way as SPAWN_SIMPLE_Y_TABLE -
; A holds this schedule index on entry, from SSC_FIRE's CP-dispatch)
; so a wave can be placed at any row, not just the 3 fixed ones - the
; schedule editor's row is honored directly, same as Enemy1.
SPAWN_E4:
    LD H,0 : LD L,A
    LD DE,SPAWN_BASEY_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (E4_SPAWN_BASEY),A
    LD A,TYPE_ENEMY4 : LD (E4_SPAWN_TYPE),A
    JP ENEMY4_CLAIM_ANY

; Test: same BEHAVIOR_SINE_BOB movement as Enemy4, but spawns
; TYPE_ENEMY1_LOOK instead - proves TYPE (display) and BEHAVIOR
; (movement) are independent. Same any-row baseY lookup as SPAWN_E4.
SPAWN_E4B:
    LD H,0 : LD L,A
    LD DE,SPAWN_BASEY_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (E4_SPAWN_BASEY),A
    LD A,TYPE_ENEMY1_LOOK : LD (E4_SPAWN_TYPE),A
    JP ENEMY4_CLAIM_ANY

; Claims a free slot from the unified ENEMY_POOL for a fresh
; BEHAVIOR_SINE_BOB spawn: right-edge X, fresh LUT phase, this wave's
; base Y (from E4_SPAWN_BASEY), TYPE (and its HP) from E4_SPAWN_TYPE.
; If the pool is full the spawn is simply dropped (same skip-if-busy
; behavior as before).
ENEMY4_CLAIM_ANY:
    CALL ALLOC_ENEMY_SLOT
    OR A
    RET Z
    LD A,(E4_SPAWN_TYPE) : LD (IX+E_TYPE),A
    LD A,BEHAVIOR_SINE_BOB : LD (IX+E_BEHAVIOR),A
    LD A,ENEMY_SPAWNX : LD (IX+E_X),A
    LD A,(E4_SPAWN_BASEY) : LD (IX+E_PARAM0),A
    CALL ALLOC_SPRITE_NUM : LD (IX+E_SPRNUM),A
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    LD DE,ETT_HP : ADD HL,DE
    LD A,(HL) : LD (IX+E_HP),A
    RET

; Given A = TYPE (1-based), returns HL = pointer to that TYPE's
; ENEMY_TYPE_TABLE entry (see layout comment above the table).
; Trashes A,DE,HL.
ENEMY_TYPE_LOOKUP:
    DEC A
    ADD A,A : ADD A,A   ; *ENEMY_TYPE_ENTRYSIZE(4)
    LD E,A : LD D,0
    LD HL,ENEMY_TYPE_TABLE
    ADD HL,DE
    RET

; Input: A = score selector (0/1/2, from ETT_SCORESEL). Awards
; 100/200/300 and refreshes the score display, same as the
; formation/Enemy3 kill-score helpers.
ENEMY_AWARD_SCORE_SEL:
    OR A
    JP Z,ADD_SCORE_100
    CP 1
    JP Z,ADD_SCORE_200
    JP ADD_SCORE_300

; Advances every active slot in the unified enemy buffer, dispatching
; on BEHAVIOR. Currently only BEHAVIOR_SINE_BOB (Enemy4) lives here;
; more movement algorithms join this dispatch as they migrate in.
ENEMY_POOL_UPDATE_ALL:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
EPUA_LOOP:
    ; E_ACTIVE is offset 0, so check it straight off HL before paying for
    ; PUSH HL:POP IX (there's no direct HL->IX move on Z80) - most slots
    ; are idle most of the time, so this skips ~48 T-states/slot for
    ; every one of them instead of always converting to IX first.
    LD A,(HL)
    OR A
    JR Z,EPUA_SKIP
    PUSH BC
    PUSH HL           ; EBSB_UPDATE reuses HL for LUT/type-table lookups - save our scan pointer
    PUSH HL : POP IX
    LD A,(IX+E_BEHAVIOR)
    CP BEHAVIOR_SINE_BOB
    CALL Z,EBSB_UPDATE
    LD A,(IX+E_BEHAVIOR)
    CP BEHAVIOR_SIMPLE_DRIFT_DODGE
    CALL Z,EBSD_UPDATE
    POP HL
    POP BC
EPUA_SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD HL,DE
    DJNZ EPUA_LOOP
    RET

; BEHAVIOR_SINE_BOB: moves left at a fixed speed, steps a 32-entry
; sine LUT for a vertical bob around E_PARAM0 (this slot's base Y,
; fixed at spawn), and draws using E_TYPE's pattern/color - same
; movement as the original Enemy4, just type-agnostic now. Exits
; (deactivates, no score) once it drifts off the left edge.
; Input: IX = slot base (already confirmed ACTIVE).
EBSB_UPDATE:
    DI
    LD A,(IX+E_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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

    LD A,(IX+E_X)
    CP ENEMY4_SPEED
    EI
    JR NC,EBSB_MOVEOK
    JP EBSB_EXIT_LEFT
EBSB_MOVEOK:
    SUB ENEMY4_SPEED
    LD (IX+E_X),A

    LD A,(IX+E_STATE) : INC A : CP ENEMY4_LUT_LEN : JR C,EBSB_PHASEOK
    XOR A
EBSB_PHASEOK:
    LD (IX+E_STATE),A
    LD E,A : LD D,0
    LD HL,ENEMY4_SINE_LUT
    ADD HL,DE
    DI
    LD A,(IX+E_PARAM0) : ADD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(IX+E_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    DI
    LD A,(HL) : OUT (98h),A          ; pattern
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    INC HL
    LD A,(HL) : OUT (98h),A          ; color
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

; Drifted off the left edge: hide the sprite, restore its type's
; pattern/color (matches the legacy Enemy4 exit write), and free the
; slot. No score, no explosion - this is an exit, not a kill.
EBSB_EXIT_LEFT:
    DI
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    DI
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
    LD A,(HL) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    CALL FREE_ENEMY_SLOT
    RET

; BEHAVIOR_SIMPLE_DRIFT_DODGE: drifts left at a fixed speed; once past
; screen-center X, makes one diagonal dodge (toward/away from the
; player's current Y, ENEMY_DODGE_DIST px total, 1px/frame) and then
; continues straight. Draws from its own pattern slot (E_PARAM3) -
; not a TYPE lookup, since each instance's pattern is independently
; mutable (see SIMPLE_REDRAW). Exits (no score) off the left edge.
; Input: IX = slot base (already confirmed ACTIVE).
EBSD_UPDATE:
    LD A,(IX+E_X)
    CP ENEMY_SPEED
    JR NC,EBSD_MOVEOK
    JP EBSD_EXIT_LEFT
EBSD_MOVEOK:
    SUB ENEMY_SPEED
    LD (IX+E_X),A
    LD A,(IX+E_PARAM0)          ; DIAG_DONE
    OR A
    JR NZ,EBSD_DIAG_SKIP_TRIGGER
    LD A,(IX+E_X)
    CP ENEMY_CENTER_X
    JR NC,EBSD_DIAG_SKIP_TRIGGER
    LD A,1 : LD (IX+E_PARAM0),A
    LD A,ENEMY_DODGE_DIST : LD (IX+E_PARAM1),A   ; DIAG_REMAIN
    LD A,(PLAYERY) : LD B,A
    LD A,(IX+E_Y)
    CP B
    JR NC,EBSD_DIAG_DIR_UP
    LD A,1
    JR EBSD_DIAG_DIR_SET
EBSD_DIAG_DIR_UP:
    LD A,0FFh
EBSD_DIAG_DIR_SET:
    LD (IX+E_PARAM2),A          ; DIAG_DIR
EBSD_DIAG_SKIP_TRIGGER:
    LD A,(IX+E_PARAM1)
    OR A
    JR Z,EBSD_DRAW
    DEC A : LD (IX+E_PARAM1),A
    LD A,(IX+E_PARAM2) : LD B,A
    LD A,(IX+E_Y)
    ADD A,B
    LD (IX+E_Y),A
EBSD_DRAW:
    DI
    LD A,(IX+E_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,(IX+E_Y) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,(IX+E_X) : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    LD A,(IX+E_PARAM3) : CALL SIMPLE_PATTERN_NUM
    DI
    OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,SPR_GRAY : OUT (98h),A
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

; Drifted off the left edge: hide the sprite, then free its sprite
; number, pattern slot and pool slot. No score, no explosion - this
; is an exit, not a kill (matches the legacy U*_EXIT paths, which
; only ever freed on edge-exit, never on a quadrant kill - see
; EBSD_HIT_TEST).
EBSD_EXIT_LEFT:
    LD A,(IX+E_SPRNUM) : PUSH AF
    DI
    ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    EI
    POP AF : CALL FREE_SPRITE_NUM
    LD A,(IX+E_PARAM3) : CALL FREE_PATTERN_SLOT
    CALL FREE_ENEMY_SLOT
    RET

; Input: B = bullet col, C = bullet row.
; Output: A = 1 if the bullet hit (and possibly destroyed) a unified
; enemy-pool slot, else 0. Scans every active slot, dispatching the
; actual hitbox test/damage on BEHAVIOR. B/C are saved to scratch RAM
; across the scan so the loop can use B as its counter; QUAD_HIT_TEST
; itself doesn't touch B/C.
CHECK_BULLET_VS_ENEMY_POOL:
    LD A,B : LD (ENEMY_HIT_COL),A
    LD A,C : LD (ENEMY_HIT_ROW),A
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
CBVEP_LOOP:
    ; E_ACTIVE is offset 0, so check it straight off HL before paying for
    ; PUSH HL:POP IX - see ENEMY_POOL_UPDATE_ALL's EPUA_LOOP for why.
    LD A,(HL)
    OR A
    JR Z,CBVEP_SKIP
    PUSH BC
    PUSH HL           ; EBSB_HIT_TEST reuses HL for LUT/type-table lookups - save our scan pointer
    PUSH HL : POP IX
    LD A,(IX+E_BEHAVIOR)
    CP BEHAVIOR_SINE_BOB
    JR NZ,CBVEP_TRY_SIMPLE
    LD A,(ENEMY_HIT_COL) : LD B,A
    LD A,(ENEMY_HIT_ROW) : LD C,A
    CALL EBSB_HIT_TEST
    JR CBVEP_CHECK_HIT
CBVEP_TRY_SIMPLE:
    LD A,(IX+E_BEHAVIOR)
    CP BEHAVIOR_SIMPLE_DRIFT_DODGE
    JR NZ,CBVEP_NOHIT_ACTIVE
    LD A,(ENEMY_HIT_COL) : LD B,A
    LD A,(ENEMY_HIT_ROW) : LD C,A
    CALL EBSD_HIT_TEST
CBVEP_CHECK_HIT:
    OR A
    JR Z,CBVEP_NOHIT_ACTIVE
    POP HL
    POP BC
    LD A,1
    RET
CBVEP_NOHIT_ACTIVE:
    POP HL
    POP BC
CBVEP_SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD HL,DE
    DJNZ CBVEP_LOOP
    XOR A
    RET

; Input: IX = slot base (already confirmed ACTIVE+BEHAVIOR_SINE_BOB),
; B = bullet col, C = bullet row. Output: A = 1 if the bullet hit this
; slot (consumed either way - damaged or destroyed), else A = 0.
EBSB_HIT_TEST:
    LD A,(IX+E_STATE) : LD E,A : LD D,0
    LD HL,ENEMY4_SINE_LUT
    ADD HL,DE
    LD A,(IX+E_PARAM0) : ADD A,(HL) : ADD A,8 : LD E,A   ; +8: art/hitbox is the bottom half only
    LD A,(IX+E_X) : LD D,A
    CALL QUAD_HIT_TEST
    OR A
    JR Z,EBSBH_NO
    LD A,(IX+E_HP) : DEC A : LD (IX+E_HP),A
    OR A
    JR NZ,EBSBH_DAMAGED
    ; --- HP reached 0: fully destroy ---
    DI
    LD A,(IX+E_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
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
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LD A,255 : OUT (98h),A
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    ; --- stash the score selector and free the slot BEFORE calling  ---
    ; --- TRIGGER_EXPLOSION, which reuses IX for its own ANIM_BASE   ---
    ; --- bookkeeping - nothing below this may rely on IX afterward. ---
    EI
    PUSH DE                     ; TRIGGER_EXPLOSION needs D,E = hit X,Y - the type/score
                                 ; lookup below (ENEMY_TYPE_LOOKUP, LD DE,ETT_SCORESEL) reuses DE
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    LD DE,ETT_SCORESEL : ADD HL,DE
    LD A,(HL)
    LD (ENEMY_SCORE_SEL_TMP),A
    CALL FREE_ENEMY_SLOT
    POP DE
    PUSH BC
    CALL TRIGGER_EXPLOSION
    LD A,(ENEMY_SCORE_SEL_TMP)
    CALL ENEMY_AWARD_SCORE_SEL
    POP BC
    LD A,1
    RET
EBSBH_DAMAGED:
    ; --- still alive - bullet is consumed (caller stops it here) ---
    ; --- but the enemy keeps flying, no explosion/score yet.      ---
    LD A,1
    RET
EBSBH_NO:
    XOR A
    RET

; Input: IX = slot base (already confirmed ACTIVE+BEHAVIOR_SIMPLE_
; DRIFT_DODGE), B = bullet col, C = bullet row. Output: A = 1 if the
; bullet destroyed a quadrant, else 0. Each of the 2 quadrants
; (TOP-left at X,Y and BOT-right at X+8,Y+8) is independently
; destructible - killing one just redraws the pattern with that
; asterisk dropped and scores; it does NOT free the slot even once
; both are gone (matches the legacy behavior exactly: a fully-gutted,
; now-invisible unit keeps flying/dodging until it exits off the left
; edge - see EBSD_EXIT_LEFT). An already-dead quadrant is skipped, so
; a bullet passes straight through it.
EBSD_HIT_TEST:
    LD A,(IX+E_TOP) : OR A : JR Z,EBSD_HT_CHECKBOT
    LD A,(IX+E_X) : LD D,A
    LD A,(IX+E_Y) : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JR NZ,EBSD_HT_KILL_TOP
EBSD_HT_CHECKBOT:
    LD A,(IX+E_BOT) : OR A : JR Z,EBSD_HT_NO
    LD A,(IX+E_X) : ADD A,8 : LD D,A
    LD A,(IX+E_Y) : ADD A,8 : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JR Z,EBSD_HT_NO
    XOR A : LD (IX+E_BOT),A
    JR EBSD_HT_REDRAW
EBSD_HT_KILL_TOP:
    XOR A : LD (IX+E_TOP),A
EBSD_HT_REDRAW:
    PUSH DE                     ; TRIGGER_EXPLOSION needs D,E = hit X,Y - SIMPLE_REDRAW below reuses DE
    PUSH IX : POP HL
    LD A,(IX+E_PARAM3)
    CALL SIMPLE_REDRAW
    POP DE
    PUSH BC
    CALL TRIGGER_EXPLOSION
    CALL AWARD_FORMATION_SCORE
    POP BC
    LD A,1
    RET
EBSD_HT_NO:
    XOR A
    RET

; 32-entry sine LUT of RELATIVE Y offsets (amplitude 16): each
; slot's actual Y = its BASEY (set at spawn from the wave) + this
; offset for the current phase. offset = round(16*sin(2*pi*i/32)),
; negative values stored as their 8-bit two's complement (ADD A,n
; wraps correctly either way).
ENEMY4_SINE_LUT:
    DB 0,3,6,9,11,13,15,16,16,16,15,13,11,9,6,3
    DB 0,253,250,247,245,243,241,240,240,240,241,243,245,247,250,253

; Spawns one unit every ENEMY3_SPAWN_INTERVAL frames, a uniform pace for
; the whole budget-32 formation, giving each spawn the wave's current
; offset (ENEMY3_CURRENT_OFFSET - set once by SPAWN_E3_WAVE from this
; trigger's own SPAWN_E3_OFFSET_TABLE entry, not cycled per spawn). All
; members of one wave share that offset; different waves (schedule
; triggers) get different offsets by each setting their own value.
ENEMY3_TRY_SPAWN:
    LD A,(ENEMY3_BUDGET)
    OR A
    RET Z
    LD A,(ENEMY3_SPAWN_TIMER)
    DEC A
    LD (ENEMY3_SPAWN_TIMER),A
    RET NZ
    LD A,ENEMY3_SPAWN_INTERVAL
    LD (ENEMY3_SPAWN_TIMER),A
    CALL ENEMY3_FIND_FREE_SLOT
    OR A
    RET Z
    LD A,(ENEMY3_CURRENT_OFFSET)
    PUSH AF
    CALL ENEMY3_CENTERX_ADDR
    POP AF
    LD (HL),A
    JP ENEMY3_DO_SPAWN

; Input: IX = slot base address (within ENEMY3_POOL). Output: HL =
; address of this slot's entry in ENEMY3_CENTERX_TABLE (same stride,
; parallel array). Clobbers: HL, DE, A.
ENEMY3_CENTERX_ADDR:
    PUSH IX
    POP HL
    LD DE,ENEMY3_POOL
    OR A : SBC HL,DE
    LD DE,ENEMY3_CENTERX_TABLE
    ADD HL,DE
    RET

; Output: A=1 and IX=slot base if a free (inactive) slot was found,
; else A=0. Clobbers: A, IX.
ENEMY3_FIND_FREE_SLOT:
    LD IX,ENEMY3_POOL             : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+11          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+22          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+33          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+44          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+55          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+66          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    LD IX,ENEMY3_POOL+77          : LD A,(IX+0) : OR A : JR Z,E3FS_FOUND
    XOR A
    RET
E3FS_FOUND:
    LD A,1
    RET

ENEMY3_DO_SPAWN:
    LD A,1 : LD (IX+0),A
    XOR A : LD (IX+1),A
    CALL ENEMY3_CENTERX_ADDR      ; this slot's centerx offset was just written by
    LD A,(HL)                     ; the caller - apply it to the entry point too, so
    ADD A,ENEMY3_SPAWN_X          ; the trio visibly separates from the first frame
    JR NC,E3DS_XOK                ; instead of only once DIAG converges on the center.
    LD A,254                      ; A large offset can push this past 255 - an 8-bit wrap
E3DS_XOK:                         ; would silently re-enter from the LEFT edge, so
    LD (IX+2),A                   ; saturate at the right edge instead. Must stay EVEN
                                   ; (254, not 255): E3_DIAG only detects "arrived" on
                                   ; exact equality with its target (128+offset, always
                                   ; even), stepping +-2/frame - an odd entry X can never
                                   ; land on an even target and oscillates forever,
                                   ; stuck in DIAG (see the offset 64/80 lockup this fixed).
    LD A,ENEMY3_SPAWN_Y : LD (IX+3),A
    LD A,ENEMY3_SPAWN_Y : SRL A : SRL A : SRL A : LD (IX+4),A
    LD A,(IX+2) : SRL A : SRL A : SRL A : LD (IX+5),A
    XOR A : LD (IX+6),A : LD (IX+7),A : LD (IX+8),A : LD (IX+9),A
    LD A,ANIM3_PACE : LD (IX+10),A
    LD A,(ENEMY3_BUDGET) : DEC A : LD (ENEMY3_BUDGET),A
    LD A,(ENEMY3_SPAWN_COUNT) : INC A : LD (ENEMY3_SPAWN_COUNT),A
    RET

; Input: IX = slot base address. Advances one frame of that slot's
; spawn/diagonal/circle/exit sequence and its 1,2,3,2 pulse
; animation, then redraws it (erasing its previous cell first).
; Input: IX = slot base (row at IX+4, col at IX+5). Restores whatever
; should be showing at that nametable cell - the scroller's own
; content if the row is within the scroller (read back from NAMEBUF),
; else BLANKCODE (sky) - i.e. erases this slot's currently-drawn cell.
; Shared by ENEMY3_UPDATE_SLOT's per-frame erase-before-redraw and
; E3_HIT_ONE_SLOT's kill path: a bullet kill used to only zero ACTIVE
; and skip this entirely, permanently stranding whatever cell was
; drawn at the moment of the kill. Clobbers: A, DE, HL.
ENEMY3_ERASE_CELL:
    LD A,(IX+4) : CP GROUND_ROW0
    JR C,E3EC_SKY
    LD A,(IX+4) : SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD E,A : LD D,0
    LD HL,NAMEBUF
    ADD HL,DE
    LD A,(IX+5) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    JR E3EC_GOT
E3EC_SKY:
    LD A,BLANKCODE
E3EC_GOT:
    LD (ANIM_TMP_VAL),A
    LD A,(IX+4) : LD (ANIM_TMP_ROW),A
    LD A,(IX+5) : LD (ANIM_TMP_COL),A
    JP WRITE_ANIM_CELL

ENEMY3_UPDATE_SLOT:
    LD A,(IX+0)
    OR A
    JR NZ,E3US_ACTIVE
    ; --- defensive safety net: real gameplay showed a stray Enemy3     ---
    ; --- pattern surviving indefinitely at this slot's last-drawn      ---
    ; --- cell despite extensive logic-level simulation never           ---
    ; --- reproducing a leak - so instead of a precise fix, keep        ---
    ; --- forcing this inactive slot's last-known cell back to blank    ---
    ; --- every frame. Whatever path is failing to erase it on          ---
    ; --- deactivation, this guarantees the stray content can't survive ---
    ; --- more than one frame once the slot goes inactive.              ---
    JP ENEMY3_ERASE_CELL   ; tail-call - WRITE_ANIM_CELL's own RET returns to our caller
E3US_ACTIVE:
    CALL ENEMY3_ERASE_CELL

    LD A,(IX+10)
    DEC A
    LD (IX+10),A
    JR NZ,E3_ANIMDONE
    LD A,ANIM3_PACE
    LD (IX+10),A
    LD A,(IX+9)
    INC A
    CP 4
    JR C,E3_ANIMIDXOK
    XOR A
E3_ANIMIDXOK:
    LD (IX+9),A
E3_ANIMDONE:

    LD A,(IX+1)
    CP 0 : JP Z,E3_DIAG
    CP 1 : JP Z,E3_CIRCLE
    JP E3_EXIT

; Each slot's diagonal approach targets its OWN circle center - X offset
; by ENEMY3_CENTERX_TABLE(slot), same offset the circle phase orbits -
; so a trio's members separate horizontally from spawn onward, not just
; once circling starts.
E3_DIAG:
    CALL ENEMY3_CENTERX_ADDR
    LD A,(HL) : ADD A,ENEMY3_CENTER_X : LD B,A
    LD A,(IX+2) : CP B
    JR Z,E3_DIAG_XOK
    JR C,E3_DIAG_XLOW
    SUB ENEMY3_DIAG_SPEED
    LD (IX+2),A
    JR E3_DIAG_XOK
E3_DIAG_XLOW:
    ADD A,ENEMY3_DIAG_SPEED
    LD (IX+2),A
E3_DIAG_XOK:
    LD A,(IX+3) : CP ENEMY3_CENTER_Y
    JR Z,E3_DIAG_YOK
    JR C,E3_DIAG_YLOW
    SUB ENEMY3_DIAG_SPEED
    LD (IX+3),A
    JR E3_DIAG_YOK
E3_DIAG_YLOW:
    ADD A,ENEMY3_DIAG_SPEED
    LD (IX+3),A
E3_DIAG_YOK:
    LD A,(IX+2) : CP B
    JP NZ,E3_DRAW
    LD A,(IX+3) : CP ENEMY3_CENTER_Y
    JP NZ,E3_DRAW
    LD A,1 : LD (IX+1),A
    LD A,ENEMY3_START_ANGLE : LD (IX+6),A
    XOR A : LD (IX+7),A : LD (IX+8),A
    JP E3_DRAW

E3_CIRCLE:
    LD A,(IX+7)
    INC A
    CP ENEMY3_STEP_FRAMES
    JR C,E3_CIRCLE_HOLD
    XOR A : LD (IX+7),A
    LD A,(IX+6) : INC A : CP 24 : JR C,E3_CIRCLE_IDXOK
    XOR A
E3_CIRCLE_IDXOK:
    LD (IX+6),A
    LD A,(IX+8) : INC A : LD (IX+8),A
    CP ENEMY3_TOTAL_STEPS
    JR C,E3_CIRCLE_POS
    LD A,2 : LD (IX+1),A
    JR E3_CIRCLE_POS
E3_CIRCLE_HOLD:
    LD (IX+7),A
E3_CIRCLE_POS:
    LD A,(IX+6)
    ADD A,A
    LD E,A : LD D,0
    LD HL,CIRCLE_LUT
    ADD HL,DE
    LD A,(HL) : LD C,A
    INC HL
    LD A,(HL) : ADD A,ENEMY3_CENTER_Y : LD (IX+3),A
    CALL ENEMY3_CENTERX_ADDR
    LD A,(HL) : ADD A,ENEMY3_CENTER_X : ADD A,C : LD (IX+2),A
    JP E3_DRAW

; Exit sequence: always drift right; drop toward ENEMY3_EXIT_TARGET_Y
; (just above the wedge row) while still short of it, then hold that
; height once reached - so the tail end of the exit is a level flight
; to the right over the wedge, not a dive into the bottom edge.
E3_EXIT:
    LD A,(IX+2)
    ADD A,ENEMY3_EXIT_SPEED
    LD (IX+2),A
    CP 252
    JR NC,E3_DEACTIVATE
    LD A,(IX+3)
    CP ENEMY3_EXIT_TARGET_Y
    JR NC,E3_EXIT_YHOLD
    ADD A,ENEMY3_EXIT_SPEED
    CP ENEMY3_EXIT_TARGET_Y
    JR C,E3_EXIT_YSTORE
    LD A,ENEMY3_EXIT_TARGET_Y
E3_EXIT_YSTORE:
    LD (IX+3),A
E3_EXIT_YHOLD:
    JP E3_DRAW
E3_DEACTIVATE:
    XOR A : LD (IX+0),A
    RET

E3_DRAW:
    LD A,(IX+3) : SRL A : SRL A : SRL A : LD (IX+4),A
    LD A,(IX+2) : SRL A : SRL A : SRL A : LD (IX+5),A
    LD A,(IX+9) : LD E,A : LD D,0
    LD HL,ANIM3_SEQ
    ADD HL,DE
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    LD A,(IX+4) : LD (ANIM_TMP_ROW),A
    LD A,(IX+5) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    RET

; Input: IX = slot base address, B = bullet col, C = bullet row.
; Output: A = 1 if this active instance overlapped the bullet
; (destroyed: deactivated + shared explosion/sound triggered),
; else A = 0 (inactive or no overlap).
E3_HIT_ONE_SLOT:
    LD A,(IX+0)
    OR A
    JR Z,E3H_NO
    LD A,(IX+5) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL QUAD_HIT_TEST
    OR A
    JR Z,E3H_NO
    XOR A : LD (IX+0),A
    PUSH DE                  ; D,E = hit X,Y for TRIGGER_EXPLOSION below - ENEMY3_ERASE_CELL clobbers DE
    CALL ENEMY3_ERASE_CELL   ; the kill freezes this slot's cell forever otherwise - see ENEMY3_ERASE_CELL
    POP DE
    PUSH BC
    CALL TRIGGER_EXPLOSION
    CALL ADD_SCORE_300
    POP BC
    LD A,1
    RET
E3H_NO:
    XOR A
    RET

; Input: B = bullet col, C = bullet row.
; Output: A = 1 if the bullet destroyed an enemy3 instance, else 0.
CHECK_BULLET_VS_ENEMY3:
    LD IX,ENEMY3_POOL    : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+11 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+22 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+33 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+44 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+55 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+66 : CALL E3_HIT_ONE_SLOT : OR A : RET NZ
    LD IX,ENEMY3_POOL+77
    JP E3_HIT_ONE_SLOT

; Translates 33 consecutive ROWDATA bytes (ASCII terrain letter) through
; LUT into an IDCACHEn buffer - used to refresh a row's cache only when
; its group's PXCHAR actually advances (see the PXCHAR_G8/G4/G2/G1 gates
; in MAINLOOP), instead of re-deriving every id from ROWDATA+LUT every
; single frame in CELL_LOOP_0-5.
; Input: HL = source (ROWDATAn + PXCHARgroup), IX = dest (IDCACHEn).
; Clobbers: A, B, D, E, HL, IX.
REFRESH_IDCACHE_33:
    LD B,33
RIC_LOOP:
    LD A,(HL) : LD E,A : LD D,LUT/256 : LD A,(DE)
    LD (IX+0),A
    INC HL
    INC IX
    DJNZ RIC_LOOP
    RET



; ============================================================
; Data tables
; ============================================================

    ALIGN 256
; LUT: ASCII terrain letter -> base id (0-5)
;   'M'=0(mountain) 'D'=1(diamond) 'S'=2(slash) 'K'=3(backslash)
;   'A'=4(wedgeA)   'B'=5(wedgeB)
; NOTE: this must stay 0-5 (small ids), because it is used BOTH
; as the index into PAIRBASE's "curr*6+next" formula AND (via
; SOLOTAB below) to get the actual steady-state character code.
; Storing the final 0-47 character code here directly (as an
; earlier draft did) breaks the curr*6+next arithmetic and was
; the cause of rows 2-4 intermittently showing mountain shapes
; and row 6 losing its second wedge character during scroll.
LUT:
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,04h,05h,00h,01h,00h,00h,00h,00h,00h,00h,03h,00h,00h,00h,00h
    DB 00h,00h,00h,02h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

    ALIGN 256
; SOLOTAB: base id (0-5) -> steady-state character code (0-47).
; Used only on the ROWPHASE=0 path, to translate the small base
; id into the renumbered SCREEN1 code space.
SOLOTAB:
    DB 00h,08h,10h,18h,20h,21h

    ALIGN 256
; MUL6: base id (0-5) -> id*6. Optimization: avoids a previous
; 5x(LD/ADD/LD) repeated-addition chain used to multiply curr_id
; by 6 when computing the PAIRBASE index (curr*6+next). A single
; table lookup replaces roughly 15 instructions with 4 per cell.
MUL6:
    DB 0,6,12,18,24,30


    ALIGN 256
; PAIRBASE[curr*6+next] = starting character code (0-47) of the
; 7-step transition sequence used while ROWPHASE<>0.
; Only the pairs that actually occur in ROWDATA0-5 are non-zero:
;   (M,M)=idx0 ->1   (mountain^2, codes 1-7)
;   (D,D)=idx7 ->9   (diamond^2,  codes 9-15)
;   (S,S)=idx14->17  (slash^2,    codes 17-23)
;   (K,K)=idx21->25  (backslash^2,codes 25-31)
;   (A,B)=idx29->34  (wedgeA->wedgeB, codes 34-40)
;   (B,A)=idx34->41  (wedgeB->wedgeA, codes 41-47)
PAIRBASE:
    DB 01h,00h,00h,00h,00h,00h,00h,09h,00h,00h,00h,00h,00h,00h,11h,00h
    DB 00h,00h,00h,00h,00h,19h,00h,00h,00h,00h,00h,00h,00h,22h,00h,00h
    DB 00h,00h,29h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h

; Sprite pattern (32 bytes) for one 16x16 sprite in the pattern
; generator table at VRAM 3800h. 16x16 sprite byte order is:
; [top-left 8x8][bottom-left 8x8][top-right 8x8][bottom-right 8x8].
; Reconstructed from 自機.png (16x16 grid, black=transparent):
SPRITE_PATTERNS:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 0C4h  ; bottom-left row0
    DB 76h   ; bottom-left row1
    DB 37h   ; bottom-left row2
    DB 0Fh   ; bottom-left row3
    DB 1Fh   ; bottom-left row4
    DB 70h   ; bottom-left row5
    DB 0C0h  ; bottom-left row6
    DB 00h   ; bottom-left row7
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 00h   ; bottom-right row0
    DB 00h   ; bottom-right row1
    DB 0C0h  ; bottom-right row2
    DB 0F8h  ; bottom-right row3
    DB 0FEh  ; bottom-right row4
    DB 40h   ; bottom-right row5
    DB 3Eh   ; bottom-right row6
    DB 00h   ; bottom-right row7

; Accent overlay (from 通常.png), drawn as its own sprite (slot0,
; priority above the ship body in slot1) at ship_X+8, ship_Y.
ACCENT_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 00h,00h,00h,18h,00h,00h,00h,00h   ; bottom-left (small mark)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; bottom-right (blank)

; 8x8 asterisk glyph: each enemy-formation quadrant that's still
; alive is drawn with this shape (not a solid fill). One asterisk
; = one enemy; each unit's 16x16 pattern is built at runtime by
; REDRAW_UNIT_PATTERN, placing this in the top-left and/or
; bottom-right 8x8 quadrant depending on which half is still alive
; (top-right/bottom-left stay blank always).
; Enemy4's fixed 16x16 pattern (from user pixel art). Content only in
; the bottom 8 rows - top-left/top-right quadrants stay blank so the
; top half is fully transparent. Loaded once at INIT (not per-spawn -
; unlike the shared asterisk quadrant system, this is a static image).
ENEMY4_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 1Fh,2Fh,77h,F8h,77h,2Ah,1Fh,0Ah   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB F8h,F4h,EEh,15h,FFh,AAh,FCh,A8h   ; bottom-right

; 2x2 lit block, top-left corner of the 16x16 - the flyaway trail
; particle. Small but clearly visible, unlike a single dot.
PARTICLE_PATTERN:
    DB 0C0h,0C0h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h

ASTERISK_PATTERN:
    DB 00h   ; ........
    DB 18h   ; ...XX...
    DB 99h   ; X..XX..X
    DB 5Ah   ; .X.XX.X.
    DB 3Ch   ; ..XXXX..
    DB 5Ah   ; .X.XX.X.
    DB 99h   ; X..XX..X
    DB 00h   ; ........

; Destroyed-quadrant explosion: 2 static 8x8 frames (anim1 then
; anim2), each replicated into 4 character-code groups so its
; background color can match whichever of the 5-row scroller's
; terrain types (or sky) it lands over - same idea as the shot's
; blue/white/green/brown variants. Only the group's first code is
; actually used; the other 7 slots in each 8-code group are unused.
ANIM_PATTERNS:
    ; anim1 (yellow), blue/white/green/brown backgrounds
    DB 00h,00h,10h,04h,20h,08h,00h,00h
    DS 56,0
    DB 00h,00h,10h,04h,20h,08h,00h,00h
    DS 56,0
    DB 00h,00h,10h,04h,20h,08h,00h,00h
    DS 56,0
    DB 00h,00h,10h,04h,20h,08h,00h,00h
    DS 56,0
    ; anim2 (red), blue/white/green/brown backgrounds
    DB 08h,42h,24h,80h,01h,24h,42h,10h
    DS 56,0
    DB 08h,42h,24h,80h,01h,24h,42h,10h
    DS 56,0
    DB 08h,42h,24h,80h,01h,24h,42h,10h
    DS 56,0
    DB 08h,42h,24h,80h,01h,24h,42h,10h
    DS 56,0

; Static sprite patterns used only while a quadrant is "flying in"
; during formation assembly: PAT_TEMP_TOP shows just the top-left
; asterisk (used by the real unit slot while its first quadrant
; arrives), PAT_TEMP_BOT shows just the bottom-right one (used by a
; spare/transient sprite slot for the second quadrant's arrival).
TEMP_SPRITE_PATTERNS:
    DB 00h,18h,99h,5Ah,3Ch,5Ah,99h,00h   ; top-left = asterisk
    DS 24,0
    DS 24,0
    DB 00h,18h,99h,5Ah,3Ch,5Ah,99h,00h   ; bottom-right = asterisk

; enemy3: 3-frame pulsing animation, gray fg. Patterns1/2 use a
; fixed sky-blue bg (they never need row-matching since the whole
; flight path stays over the sky); pattern3 uses a red bg, giving
; the "gray frame with a red 2x2 dot in the middle" look.
ENEMY3_PATTERN1:
    DB 00h,00h,00h,0FFh,0FFh,00h,00h,00h
ENEMY3_PATTERN2:
    DB 00h,00h,0FFh,0FFh,0FFh,0FFh,00h,00h
ENEMY3_PATTERN3:
    DB 0FFh,0FFh,0FFh,0E7h,0E7h,0FFh,0FFh,0FFh

; TEMPORARY: focused Enemy3-offset test schedule, 6 entries (indices
; 0-5), all enemy3_wave, imported directly from the schedule editor's
; test JSON. The previous full 75-entry level schedule is preserved in
; git history (see the "Add two early Enemy3 waves..." commit onward) -
; restore it here (and in SSC_FIRE/SPAWN_SCHEDULE_CHECK) once this test
; is done.
SPAWN_THRESHOLDS:
    DW 8,11,14,17,20,23

; --- saved (disabled) boss-only single-entry schedule, used ---
; --- while iterating quickly on boss features - not deleted: ---
;SPAWN_THRESHOLDS_BOSSONLY_SAVED:
;    DW 10

; Spawn Y for each SPAWN_SIMPLE schedule index (see SSC_FIRE/SPAWN_
; SIMPLE) - one byte per index, same length/order as SPAWN_THRESHOLDS,
; row*8 from the schedule editor. Only indices that actually dispatch
; to SPAWN_SIMPLE are read; the rest are unused placeholders (0).
SPAWN_SIMPLE_Y_TABLE:
    DB 0,0,0,0,0,0

; Same idea as SPAWN_SIMPLE_Y_TABLE but for Enemy4/Enemy5 (SPAWN_E4/
; SPAWN_E4B) baseY - row*8 from the schedule editor, any row, not
; just the old 3 fixed presets (32/64/72). Unused elsewhere (0).
SPAWN_BASEY_TABLE:
    DB 0,0,0,0,0,0

; This trigger's own ENEMY3_CURRENT_OFFSET (px = cells*8), one byte per
; SPAWN_THRESHOLDS index, from the schedule editor's per-placement
; "offset" field - see SPAWN_E3_WAVE.
SPAWN_E3_OFFSET_TABLE:
    DB 0,16,32,48,64,80

; --- Boss BG (nametable) graphics, generated from
; --- dotpict_20260806_173500 (12x37 dot art), resized directly
; --- to 40x128 dots (5x16 tiles) and quantized to black/gray/red/blue.
; --- (No pure-blue-free / 2-non-blue-color tiles this size - every
; --- tile's minority pixels just fold into bg=blue, so only 3
; --- color pairs are needed: K/B, G/B, R/B - keeps us to exactly
; --- the 8 free groups, codes 192-255.)
; --- BOSS_HEX_PATTERN: single 16x16 sprite pattern (32 bytes),
; --- art only in the top-left 8x8 quadrant (the other 3 quadrants
; --- are blank/transparent) - matches the uploaded hex-icon shape.
; --- Reused at two different sprite-attribute colors (gray/white)
; --- for the flash effect - see BOSS_SPAWN/BOSS_UPDATE.
BOSS_HEX_PATTERN:
    DB 3Ch,7Eh,FFh,FFh,FFh,FFh,7Eh,3Ch    ; top-left (the icon)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; bottom-left (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; top-right (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; bottom-right (blank)

; --- BOSS_ORBIT_PATTERN: single 16x16 sprite pattern (32 bytes),
; --- a small lens/capsule shape spanning the full 16px width but
; --- only 8px tall (top half) - matches the uploaded pod shape.
; --- Used by all 8 orbit pods (color set dynamically per pod).
BOSS_ORBIT_PATTERN:
    DB 3Fh,7Fh,7Fh,0FFh,0FFh,7Fh,7Fh,3Fh   ; top-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-left (blank)
    DB 0FCh,0FEh,0FEh,0FFh,0FFh,0FEh,0FEh,0FCh  ; top-right
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-right (blank)

; --- deflected boss-shield shots reuse the player's own shot shape ---
; --- (the small diagonal streak from BULLET_PATTERNS' M=0 frame), ---
; --- as a 16x16 sprite (only the top-left 8x8 has any art).       ---
DFL_BULLET_PATTERN:
    DB 66h,33h,00h,00h,00h,00h,00h,00h     ; top-left (matches player shot M=0)
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-left (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; top-right (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-right (blank)

; --- pod-destroy burst: 4 copies of the anim2 spark shape         ---
; --- (08h,42h,24h,80h,01h,24h,42h,10h), scattered at overlapping,  ---
; --- non-grid-aligned offsets across the full 16x16 area.          ---
EXPLOSION_PATTERN:
    DB 84h,48h,00h,02h,49h,84h,20h,03h     ; top-left
    DB 13h,09h,20h,00h,09h,10h,04h,00h     ; bottom-left
    DB 00h,00h,40h,10h,20h,10h,8Ch,68h     ; top-right
    DB 90h,82h,48h,0C4h,20h,80h,00h,00h    ; bottom-right

; --- vertical-ellipse orbit LUT, 256 steps, signed byte offsets  ---
; --- from the boss ring's center. Asymmetric egg shape: top     ---
; --- half uses ry=57 (top vertex at Y15), bottom half uses      ---
; --- ry=65 (bottom vertex extended 8px further, to Y137) - both ---
; --- meet smoothly at dy=0 on the sides, no seam. rx=15 both    ---
; --- sides (narrowed so gray/right's reach matches black/left). ---
; --- Index0 = top. 256 steps for smooth ferris-wheel motion.    ---
LUT_DX:
    DB 00h,00h,01h,01h,01h,02h,02h,03h,03h,03h,04h,04h,04h,05h,05h,05h
    DB 06h,06h,06h,07h,07h,07h,08h,08h,08h,09h,09h,09h,0Ah,0Ah,0Ah,0Ah
    DB 0Bh,0Bh,0Bh,0Bh,0Ch,0Ch,0Ch,0Ch,0Ch,0Dh,0Dh,0Dh,0Dh,0Dh,0Eh,0Eh
    DB 0Eh,0Eh,0Eh,0Eh,0Eh,0Eh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh
    DB 0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Eh,0Eh,0Eh,0Eh,0Eh
    DB 0Eh,0Eh,0Eh,0Dh,0Dh,0Dh,0Dh,0Dh,0Ch,0Ch,0Ch,0Ch,0Ch,0Bh,0Bh,0Bh
    DB 0Bh,0Ah,0Ah,0Ah,0Ah,09h,09h,09h,08h,08h,08h,07h,07h,07h,06h,06h
    DB 06h,05h,05h,05h,04h,04h,04h,03h,03h,03h,02h,02h,01h,01h,01h,00h
    DB 00h,00h,FFh,FFh,FFh,FEh,FEh,FDh,FDh,FDh,FCh,FCh,FCh,FBh,FBh,FBh
    DB FAh,FAh,FAh,F9h,F9h,F9h,F8h,F8h,F8h,F7h,F7h,F7h,F6h,F6h,F6h,F6h
    DB F5h,F5h,F5h,F5h,F4h,F4h,F4h,F4h,F4h,F3h,F3h,F3h,F3h,F3h,F2h,F2h
    DB F2h,F2h,F2h,F2h,F2h,F2h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h
    DB F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F1h,F2h,F2h,F2h,F2h,F2h
    DB F2h,F2h,F2h,F3h,F3h,F3h,F3h,F3h,F4h,F4h,F4h,F4h,F4h,F5h,F5h,F5h
    DB F5h,F6h,F6h,F6h,F6h,F7h,F7h,F7h,F8h,F8h,F8h,F9h,F9h,F9h,FAh,FAh
    DB FAh,FBh,FBh,FBh,FCh,FCh,FCh,FDh,FDh,FDh,FEh,FEh,FFh,FFh,FFh,00h
LUT_DY:
    DB C7h,C7h,C7h,C7h,C7h,C7h,C8h,C8h,C8h,C8h,C9h,C9h,C9h,CAh,CAh,CBh
    DB CBh,CCh,CCh,CDh,CEh,CEh,CFh,D0h,D1h,D1h,D2h,D3h,D4h,D5h,D6h,D7h
    DB D8h,D9h,DAh,DBh,DCh,DDh,DEh,DFh,E0h,E2h,E3h,E4h,E5h,E6h,E8h,E9h
    DB EAh,EBh,EDh,EEh,EFh,F1h,F2h,F4h,F5h,F6h,F8h,F9h,FAh,FCh,FDh,FFh
    DB 00h,02h,03h,05h,06h,08h,0Ah,0Bh,0Dh,0Eh,10h,11h,13h,14h,16h,17h
    DB 19h,1Ah,1Ch,1Dh,1Fh,20h,21h,23h,24h,25h,27h,28h,29h,2Ah,2Ch,2Dh
    DB 2Eh,2Fh,30h,31h,32h,33h,34h,35h,36h,37h,38h,39h,39h,3Ah,3Bh,3Bh
    DB 3Ch,3Dh,3Dh,3Eh,3Eh,3Fh,3Fh,3Fh,40h,40h,40h,41h,41h,41h,41h,41h
    DB 41h,41h,41h,41h,41h,41h,40h,40h,40h,3Fh,3Fh,3Fh,3Eh,3Eh,3Dh,3Dh
    DB 3Ch,3Bh,3Bh,3Ah,39h,39h,38h,37h,36h,35h,34h,33h,32h,31h,30h,2Fh
    DB 2Eh,2Dh,2Ch,2Ah,29h,28h,27h,25h,24h,23h,21h,20h,1Fh,1Dh,1Ch,1Ah
    DB 19h,17h,16h,14h,13h,11h,10h,0Eh,0Dh,0Bh,0Ah,08h,06h,05h,03h,02h
    DB 00h,FFh,FDh,FCh,FAh,F9h,F8h,F6h,F5h,F4h,F2h,F1h,EFh,EEh,EDh,EBh
    DB EAh,E9h,E8h,E6h,E5h,E4h,E3h,E2h,E0h,DFh,DEh,DDh,DCh,DBh,DAh,D9h
    DB D8h,D7h,D6h,D5h,D4h,D3h,D2h,D1h,D1h,D0h,CFh,CEh,CEh,CDh,CCh,CCh
    DB CBh,CBh,CAh,CAh,C9h,C9h,C9h,C8h,C8h,C8h,C8h,C7h,C7h,C7h,C7h,C7h

BOSS_PATTERNS:
; group24 codes 192-199 color=('G', 'B') byte=E4h
    DB 00h,00h,01h,03h,07h,0Fh,1Ch,30h    ; code 192 tile#0
    DB 7Eh,FFh,FFh,FFh,FFh,FFh,7Fh,1Fh    ; code 193 tile#1
    DB 00h,00h,80h,C0h,E0h,F0h,F8h,FCh    ; code 194 tile#2
    DB 0Fh,0Fh,17h,27h,27h,43h,43h,81h    ; code 195 tile#5
    DB FEh,FEh,FFh,FFh,FFh,FFh,FFh,FFh    ; code 196 tile#6
    DB 00h,00h,00h,00h,80h,80h,80h,C0h    ; code 197 tile#7
    DB 81h,81h,00h,00h,00h,00h,00h,00h    ; code 198 tile#10
    DB FFh,FFh,FFh,FFh,7Fh,7Fh,7Fh,7Fh    ; code 199 tile#11
; group25 codes 200-207 color=('G', 'B') byte=E4h
    DB C0h,E0h,E0h,E0h,E0h,F0h,F0h,F0h    ; code 200 tile#12
    DB 3Fh,3Fh,3Fh,3Fh,1Fh,1Fh,1Fh,1Fh    ; code 201 tile#15
    DB F0h,F8h,F8h,F8h,F8h,F8h,F8h,F8h    ; code 202 tile#16
    DB 1Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh    ; code 203 tile#19
    DB F8h,F8h,F8h,F8h,F8h,FCh,FCh,FCh    ; code 204 tile#20
    DB 07h,07h,07h,07h,07h,07h,07h,07h    ; code 205 tile#24
    DB FCh,FCh,FCh,FCh,FCh,FCh,FCh,FCh    ; code 206 tile#25
    DB 07h,07h,07h,03h,03h,03h,03h,03h    ; code 207 tile#29
; group26 codes 208-215 color=('G', 'B') byte=E4h
    DB FEh,FEh,FEh,FEh,FEh,FEh,FEh,FEh    ; code 208 tile#30
    DB 03h,03h,03h,03h,03h,03h,03h,03h    ; code 209 tile#33
    DB 03h,03h,03h,03h,03h,07h,07h,07h    ; code 210 tile#37
    DB 0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,0Fh,1Fh    ; code 211 tile#40
    DB FCh,FCh,FCh,F8h,F8h,F8h,F8h,F8h    ; code 212 tile#41
    DB 1Fh,1Fh,1Fh,1Fh,3Fh,3Fh,3Fh,3Fh    ; code 213 tile#44
    DB F8h,F8h,F8h,F8h,F8h,F8h,F8h,F0h    ; code 214 tile#45
    DB 00h,00h,00h,00h,00h,00h,81h,81h    ; code 215 tile#48
; group27 codes 216-223 color=('G', 'B') byte=E4h
    DB 7Fh,7Fh,7Fh,7Fh,FFh,FFh,FFh,FFh    ; code 216 tile#49
    DB F0h,F0h,F0h,E0h,E0h,E0h,E0h,C0h    ; code 217 tile#50
    DB 81h,43h,43h,27h,27h,17h,0Fh,0Fh    ; code 218 tile#53
    DB FFh,FFh,FFh,FFh,FFh,FFh,FEh,FEh    ; code 219 tile#54
    DB C0h,80h,80h,80h,00h,00h,00h,00h    ; code 220 tile#55
    DB 30h,1Ch,0Fh,07h,03h,01h,00h,00h    ; code 221 tile#56
    DB 1Fh,7Fh,FFh,FFh,FFh,FFh,FFh,7Eh    ; code 222 tile#57
    DB FCh,F8h,F0h,E0h,C0h,80h,00h,00h    ; code 223 tile#58
; group28 codes 224-231 color=('K', 'B') byte=14h
    DB 00h,00h,00h,00h,01h,01h,01h,03h    ; code 224 tile#3
    DB 7Fh,7Fh,FFh,FFh,FFh,FFh,FFh,FFh    ; code 225 tile#4
    DB 03h,07h,07h,07h,07h,0Fh,0Fh,0Fh    ; code 226 tile#8
    DB FFh,FFh,FEh,FEh,FCh,FCh,FCh,FCh    ; code 227 tile#9
    DB 0Fh,1Fh,1Fh,1Fh,1Fh,1Fh,3Fh,3Fh    ; code 228 tile#13
    DB FCh,FCh,FCh,FCh,F8h,F8h,F8h,F8h    ; code 229 tile#14
    DB 3Fh,3Fh,3Fh,3Fh,3Fh,7Fh,7Fh,7Fh    ; code 230 tile#17
    DB F8h,F0h,F0h,F0h,F0h,F0h,F0h,F0h    ; code 231 tile#18
; group29 codes 232-239 color=('K', 'B') byte=14h
    DB 7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh,7Fh    ; code 232 tile#21
    DB E0h,E0h,E0h,E0h,E0h,E0h,E0h,E0h    ; code 233 tile#22
    DB FFh,FFh,FFh,FFh,FFh,FFh,FFh,FFh    ; code 234 tile#26
    DB E0h,E0h,E0h,C0h,C0h,C0h,C0h,C0h    ; code 235 tile#27
    DB C0h,C0h,C0h,C0h,C0h,C0h,C0h,C0h    ; code 236 tile#31
    DB C0h,C0h,C0h,C0h,C0h,E0h,E0h,E0h    ; code 237 tile#35
    DB 7Fh,7Fh,7Fh,3Fh,3Fh,3Fh,3Fh,3Fh    ; code 238 tile#38
    DB F0h,F0h,F0h,F0h,F0h,F0h,F0h,F8h    ; code 239 tile#39
; group30 codes 240-247 color=('K', 'B') byte=14h
    DB 3Fh,3Fh,1Fh,1Fh,1Fh,1Fh,1Fh,0Fh    ; code 240 tile#42
    DB F8h,F8h,F8h,F8h,FCh,FCh,FCh,FCh    ; code 241 tile#43
    DB 0Fh,0Fh,0Fh,07h,07h,07h,07h,03h    ; code 242 tile#46
    DB FCh,FCh,FCh,FCh,FEh,FEh,FFh,FFh    ; code 243 tile#47
    DB 03h,01h,01h,01h,00h,00h,00h,00h    ; code 244 tile#51
    DB FFh,FFh,FFh,FFh,FFh,FFh,7Fh,7Fh    ; code 245 tile#52
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; code 246 (unused)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; code 247 (unused)
; group31 codes 248-255 color=('R', 'B') byte=84h
    DB 00h,00h,00h,00h,00h,18h,38h,78h    ; code 248 tile#23
    DB 78h,D8h,DCh,9Ch,8Ch,0Eh,0Eh,0Eh    ; code 249 tile#28
    DB 0Fh,3Fh,E7h,07h,07h,C7h,77h,1Fh    ; code 250 tile#32
    DB 07h,07h,0Fh,0Eh,8Eh,8Ch,DCh,D8h    ; code 251 tile#34
    DB 78h,78h,30h,30h,00h,00h,00h,00h    ; code 252 tile#36
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; code 253 (unused)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; code 254 (unused)
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; code 255 (unused)

; boss nametable map: 5 cols x 16 rows of character codes
; (48=BLANKCODE/solid-blue, 192-252=boss tiles above)

; --- sky-erase stub templates (copied into the RAM stubs at INIT ---
; --- and again when the boss lands - see SKY_STUB_* above).       ---
; --- FAST: original behavior, just BLANKCODE.                     ---
SKY_FAST_0H:
    LD A,BLANKCODE
    JP BULLET0_HITERASE_GOT
SKY_FAST_0E:
    LD A,BLANKCODE
    JP BULLET0_ERASE_GOT
SKY_FAST_1H:
    LD A,BLANKCODE
    JP BULLET1_HITERASE_GOT
SKY_FAST_1E:
    LD A,BLANKCODE
    JP BULLET1_ERASE_GOT
SKY_FAST_2H:
    LD A,BLANKCODE
    JP BULLET2_HITERASE_GOT
SKY_FAST_2E:
    LD A,BLANKCODE
    JP BULLET2_ERASE_GOT
SKY_FAST_END:

; --- SLOW: boss has landed - restore from BOSS_MAP if this cell is ---
; --- within its 5x16 tile area, else still BLANKCODE.               ---
; Input: B = boss-local row (0-15). Restores all 5 columns of that
; row from BOSS_MAP in one shot (VDP auto-increments across the
; write). Used as a stronger safety net than the normal single-cell
; restore: whatever caused single-cell restores to sometimes miss,
; redrawing the entire row every time a bullet passes through it
; can't leave a partial gap behind. Trashes A,B,C,D,E,H,L - callers
; must re-fetch BULLET_ROW/COL fresh afterward rather than relying on
; anything surviving this call.
SKY_SLOW_0H:
    LD A,(BULLET0_ROW) : SUB 1 : CP 16 : JR NC,SS0H_FAST
    LD B,A : LD A,(BULLET0_COL) : SUB 26 : CP 5 : JR NC,SS0H_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET0_HITERASE_GOT
SS0H_FAST:
    LD A,BLANKCODE
    JP BULLET0_HITERASE_GOT
SKY_SLOW_0H_END:

SKY_SLOW_0E:
    LD A,(BULLET0_ROW) : SUB 1 : CP 16 : JR NC,SS0E_FAST
    LD B,A : LD A,(BULLET0_COL) : SUB 26 : CP 5 : JR NC,SS0E_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET0_ERASE_GOT
SS0E_FAST:
    LD A,BLANKCODE
    JP BULLET0_ERASE_GOT
SKY_SLOW_0E_END:

SKY_SLOW_1H:
    LD A,(BULLET1_ROW) : SUB 1 : CP 16 : JR NC,SS1H_FAST
    LD B,A : LD A,(BULLET1_COL) : SUB 26 : CP 5 : JR NC,SS1H_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET1_HITERASE_GOT
SS1H_FAST:
    LD A,BLANKCODE
    JP BULLET1_HITERASE_GOT
SKY_SLOW_1H_END:

SKY_SLOW_1E:
    LD A,(BULLET1_ROW) : SUB 1 : CP 16 : JR NC,SS1E_FAST
    LD B,A : LD A,(BULLET1_COL) : SUB 26 : CP 5 : JR NC,SS1E_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET1_ERASE_GOT
SS1E_FAST:
    LD A,BLANKCODE
    JP BULLET1_ERASE_GOT
SKY_SLOW_1E_END:

SKY_SLOW_2H:
    LD A,(BULLET2_ROW) : SUB 1 : CP 16 : JR NC,SS2H_FAST
    LD B,A : LD A,(BULLET2_COL) : SUB 26 : CP 5 : JR NC,SS2H_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET2_HITERASE_GOT
SS2H_FAST:
    LD A,BLANKCODE
    JP BULLET2_HITERASE_GOT
SKY_SLOW_2H_END:

SKY_SLOW_2E:
    LD A,(BULLET2_ROW) : SUB 1 : CP 16 : JR NC,SS2E_FAST
    LD B,A : LD A,(BULLET2_COL) : SUB 26 : CP 5 : JR NC,SS2E_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLET2_ERASE_GOT
SS2E_FAST:
    LD A,BLANKCODE
    JP BULLET2_ERASE_GOT
SKY_SLOW_2E_END:

BOSS_MAP:
    DB 48,192,193,194,48   ; boss row 0
    DB 224,225,195,196,197   ; boss row 1
    DB 226,227,198,199,200   ; boss row 2
    DB 228,229,48,201,202   ; boss row 3
    DB 230,231,48,203,204   ; boss row 4
    DB 232,233,248,205,206   ; boss row 5
    DB 234,235,249,207,208   ; boss row 6
    DB 234,236,250,209,208   ; boss row 7
    DB 234,236,251,209,208   ; boss row 8
    DB 234,237,252,210,208   ; boss row 9
    DB 232,233,48,205,206   ; boss row 10
    DB 238,239,48,211,212   ; boss row 11
    DB 240,241,48,213,214   ; boss row 12
    DB 242,243,215,216,217   ; boss row 13
    DB 244,245,218,219,220   ; boss row 14
    DB 48,221,222,223,48   ; boss row 15

; animation order 1,2,3,2 repeating (indexed by each slot's ANIMIDX 0-3)
ANIM3_SEQ:
    DB ENEMY3_CODE1,ENEMY3_CODE2,ENEMY3_CODE3,ENEMY3_CODE2

; digit glyphs 0-9 for the on-screen game-tick counter (code DIGIT_BASE+N)
DIGIT_PATTERNS:
    DB 3Ch,66h,6Eh,76h,66h,66h,3Ch,00h   ; 0
    DB 18h,38h,58h,18h,18h,18h,7Eh,00h   ; 1
    DB 3Ch,66h,06h,0Ch,30h,60h,7Eh,00h   ; 2
    DB 3Ch,66h,06h,1Ch,06h,66h,3Ch,00h   ; 3
    DB 0Ch,1Ch,2Ch,4Ch,7Eh,0Ch,0Ch,00h   ; 4
    DB 7Eh,60h,7Ch,06h,06h,66h,3Ch,00h   ; 5
    DB 1Ch,30h,60h,7Ch,66h,66h,3Ch,00h   ; 6
    DB 7Eh,06h,0Ch,18h,30h,30h,30h,00h   ; 7
    DB 3Ch,66h,66h,3Ch,66h,66h,3Ch,00h   ; 8
    DB 3Ch,66h,66h,3Eh,06h,0Ch,38h,00h   ; 9

; enemy3's orbit: 24-point radius-24 circle around (0,0), as signed
; (dx,dy) byte pairs, counter-clockwise on-screen. Position for LUT
; index i is (ENEMY3_CENTER_X+dx, ENEMY3_CENTER_Y+dy).
CIRCLE_LUT:
    DB 18h,00h
    DB 17h,FAh
    DB 15h,F4h
    DB 11h,EFh
    DB 0Ch,EBh
    DB 06h,E9h
    DB 00h,E8h
    DB 0FAh,0E9h
    DB 0F4h,0EBh
    DB 0EFh,0EFh
    DB 0EBh,0F4h
    DB 0E9h,0FAh
    DB 0E8h,00h
    DB 0E9h,06h
    DB 0EBh,0Ch
    DB 0EFh,11h
    DB 0F4h,15h
    DB 0FAh,17h
    DB 00h,18h
    DB 06h,17h
    DB 0Ch,15h
    DB 11h,11h
    DB 15h,0Ch
    DB 17h,06h

; Shot character patterns: 8 vertical-phase variants (character
; codes BULLET_PAT_BASE..+7), so a shot fired while the ship's Y
; is at any of the 8 sub-row pixel offsets lines up vertically.
; Each variant is the base shape shifted up by `phase` rows
; (rows shifted past the top are simply dropped, matching the
; ship's Y mod 8 at the moment of firing). Horizontal (column)
; position is not sub-pixel corrected, per current spec.
; Shot character patterns: 8x16 shape (two stacked character cells)
; so the notch can shift down across the full 8-pixel sub-row range
; without clipping at the row boundary. codes 56-63 = top cell,
; codes 64-71 = bottom cell, both indexed by phase = PLAYERY mod 8.
; phase0 matches the original single-cell design (notch at rows5-7);
; as phase increases the notch slides down and spills into the
; bottom cell for phase>=1.
; Shot character patterns, 8x8 single cell. Since PLAYER_SPEED=2,
; PLAYERY mod 8 only ever takes the even values 0,2,4,6, so a
; 2-row-tall shape starting at row=phase spans a 6-dot range and
; always stays inside the 8-row cell (0+2<=8 ... 6+2<=8), matching
; the ship's vertical position with no clipping. Odd phase slots
; are unused (kept zero-filled for safety).
; codes 56-63: blue-background variant (over sky / mountain row)
; codes 64-71: green-background variant (over diamond/slash rows)
; (slot 71, phase7, is never used as content - see BLANKCODE_GREEN)
; Shot character patterns, 8x8 single cell, updated shape/anchor
; per the reference screenshot: the dot pair now sits at the BOTTOM
; of the cell (rows6-7) for phase0 (ship at the top of a character
; row) and slides UP toward rows0-1 as phase increases to 6 (ship
; near the bottom of the row) - i.e. row_start = 6 - phase. This
; keeps the shot visually anchored near the ship's body instead of
; poking out above it. Still only even phases (0,2,4,6) are used
; since PLAYER_SPEED=2, and content is 2 rows tall so it never
; clips (row_start always in 0,2,4,6).
; Shot character pattern, 8x8 single cell, fixed at the bottom of
; the cell (rows6-7) regardless of the ship's exact sub-row phase.
; An earlier phase-indexed version (content sliding within the cell
; to track PLAYERY mod 8) had the row/phase relationship backwards
; and made the shot pop up a whole row above the ship. Per current
; spec, exact sub-pixel tracking isn't required - keeping the shot
; pinned to the bottom of whichever character row the ship is in is
; good enough (it can look slightly off right at a row boundary,
; that's acceptable).
; Shot character patterns, 8x8 single cell, 7 variants (M=0..6)
; where M = PLAYERY mod 8, content start_row = M (2 rows tall, so
; M=6 is the last position that still fits: rows 6-7). M=7 would
; need row 8, which doesn't exist, so that case is handled in code
; by drawing into the row ABOVE using the M=0 pattern instead (see
; the spawn logic) - matching: 6 dots of upward shift cover M=0..6,
; one more dot up would clip, so switch to the cell above reusing
; the initial (M=0) pattern, and one further dot up stays on that
; same cell/pattern (that IS the new "initial position").
; Shot character patterns, 8x8 single cell, 7 variants (M=0..6)
; where M = PLAYERY mod 8. M=0 (ship at the top of its character
; row - the "initial" case) anchors the shot at the BOTTOM of the
; cell (rows6-7); as M increases (ship further down within the
; row) the shot slides UP toward rows0-1 at M=6. M=7 would need a
; nonexistent row8, so that case is handled in code by drawing
; into the row ABOVE using the M=0 pattern instead - matching: 6
; steps of upward shift (M=0..6), one more dot up would clip, so
; switch to the cell above reusing the initial (M=0, bottom-
; anchored) pattern, and one further dot up stays on that same
; cell/pattern (that IS the new "initial position").
; Shot character pattern, 8x8 single cell, always fixed at the
; BOTTOM 2 dots of whichever character row it's drawn into (rows
; 6-7), matching the ship sprite's bottom edge. The earlier M-phase
; sliding version made the shot jump up/down inconsistently as the
; ship's Y sub-position changed; a single fixed pattern is
; consistent even though it can sit a few dots off from the ship's
; exact Y within that row - acceptable per spec.
; Shot character patterns, 8x8 single cell, 6 variants (M=0..5)
; where M = PLAYERY mod 8. M=0 (ship at the top of its character
; row - the "initial" case) anchors the shot at the BOTTOM of the
; cell (rows6-7); as M increases the shot slides UP a row at a
; time, reaching rows1-2 at M=5. M=6 and M=7 are NOT used directly
; (no data below) - both are handled in code by drawing into the
; row ABOVE using the M=0 (bottom-anchored) pattern instead, i.e.
; after 6 dots of upward shift, one more dot would clip, so switch
; to the cell above reusing the initial pattern; a further dot up
; stays on that same cell/pattern (that IS the new "initial
; position").
; Shot character patterns, 8x8 single cell, 7 variants (M=0..6)
; where M = PLAYERY mod 8. M=0 anchors the shot at the BOTTOM of
; the cell (rows6-7); as M increases the shot slides UP a row at a
; time, reaching rows0-1 at M=6. M=6 fits exactly (6+2=8), so no
; row-above trick is needed. M=7 just reuses the M=6 pattern (code
; clamps M to 6 - see spawn logic) since there's nowhere further
; up to go within a single 8-row cell.
; row_start = M (content at rows M,M+1), because the spawn calc now keys
; off PLAYERY+8 (the row/sub-row immediately below the ship's visible
; bottom edge) rather than PLAYERY itself - so the pattern must slide
; DOWN as M increases to stay pinned right under the ship, not up.
BULLET_PATTERNS:
    DB 66h,33h,00h,00h,00h,00h,00h,00h   ; BLUE M=0 (rows0-1)
    DB 00h,66h,33h,00h,00h,00h,00h,00h   ; BLUE M=1 (rows1-2)
    DB 00h,00h,66h,33h,00h,00h,00h,00h   ; BLUE M=2 (rows2-3)
    DB 00h,00h,00h,66h,33h,00h,00h,00h   ; BLUE M=3 (rows3-4)
    DB 00h,00h,00h,00h,66h,33h,00h,00h   ; BLUE M=4 (rows4-5)
    DB 00h,00h,00h,00h,00h,66h,33h,00h   ; BLUE M=5 (rows5-6)
    DB 00h,00h,00h,00h,00h,00h,66h,33h   ; BLUE M=6 (rows6-7)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; BLUE M=7 slot (unused, code clamps to M=6)
    DB 66h,33h,00h,00h,00h,00h,00h,00h   ; GREEN M=0 (rows0-1)
    DB 00h,66h,33h,00h,00h,00h,00h,00h   ; GREEN M=1 (rows1-2)
    DB 00h,00h,66h,33h,00h,00h,00h,00h   ; GREEN M=2 (rows2-3)
    DB 00h,00h,00h,66h,33h,00h,00h,00h   ; GREEN M=3 (rows3-4)
    DB 00h,00h,00h,00h,66h,33h,00h,00h   ; GREEN M=4 (rows4-5)
    DB 00h,00h,00h,00h,00h,66h,33h,00h   ; GREEN M=5 (rows5-6)
    DB 00h,00h,00h,00h,00h,00h,66h,33h   ; GREEN M=6 (rows6-7)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; GREEN M=7 slot (unused, code clamps to M=6)
    DB 66h,33h,00h,00h,00h,00h,00h,00h   ; WHITE M=0 (rows0-1)
    DB 00h,66h,33h,00h,00h,00h,00h,00h   ; WHITE M=1 (rows1-2)
    DB 00h,00h,66h,33h,00h,00h,00h,00h   ; WHITE M=2 (rows2-3)
    DB 00h,00h,00h,66h,33h,00h,00h,00h   ; WHITE M=3 (rows3-4)
    DB 00h,00h,00h,00h,66h,33h,00h,00h   ; WHITE M=4 (rows4-5)
    DB 00h,00h,00h,00h,00h,66h,33h,00h   ; WHITE M=5 (rows5-6)
    DB 00h,00h,00h,00h,00h,00h,66h,33h   ; WHITE M=6 (rows6-7)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; WHITE M=7 slot (unused, code clamps to M=6)
    DB 66h,33h,00h,00h,00h,00h,00h,00h   ; BROWN M=0 (rows0-1)
    DB 00h,66h,33h,00h,00h,00h,00h,00h   ; BROWN M=1 (rows1-2)
    DB 00h,00h,66h,33h,00h,00h,00h,00h   ; BROWN M=2 (rows2-3)
    DB 00h,00h,00h,66h,33h,00h,00h,00h   ; BROWN M=3 (rows3-4)
    DB 00h,00h,00h,00h,66h,33h,00h,00h   ; BROWN M=4 (rows4-5)
    DB 00h,00h,00h,00h,00h,66h,33h,00h   ; BROWN M=5 (rows5-6)
    DB 00h,00h,00h,00h,00h,00h,66h,33h   ; BROWN M=6 (rows6-7)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; BROWN M=7 slot (unused, code clamps to M=6)

    ALIGN 256
; VRAM address (low byte) of the start of each of the 24 screen
; rows in the name table (1800h + row*32), used to place a shot
; character at (row, col) without doing 16-bit multiply at runtime.
ROWADDR_LO:
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h

    ALIGN 256
ROWADDR_HI:
    DB 18h,18h,18h,18h,18h,18h,18h,18h
    DB 19h,19h,19h,19h,19h,19h,19h,19h
    DB 1Ah,1Ah,1Ah,1Ah,1Ah,1Ah,1Ah,1Ah

PATTERNS:
    ; Character codes renumbered into 3 color-uniform groups of 8:
    ;   0- 7 = mountain family        (color A4h)
    ;   8-31 = diamond/slash/backslash family (color C3h)
    ; 32-47 = wedge family            (color B3h)
    DB 0Ch,3Ah,7Fh,DFh,F7h,F7h,EFh,DFh    ; code 0  mountain (new design)
    DB 18h,74h,FEh,BFh,EFh,EFh,DFh,BFh    ; code 1  mountain^2 shift1
    DB 30h,E8h,FDh,7Fh,DFh,DFh,BFh,7Fh    ; code 2  mountain^2 shift2
    DB 60h,D1h,FBh,FEh,BFh,BFh,7Fh,FEh    ; code 3  mountain^2 shift3
    DB C0h,A3h,F7h,FDh,7Fh,7Fh,FEh,FDh    ; code 4  mountain^2 shift4
    DB 81h,47h,EFh,FBh,FEh,FEh,FDh,FBh    ; code 5  mountain^2 shift5
    DB 03h,8Eh,DFh,F7h,FDh,FDh,FBh,F7h    ; code 6  mountain^2 shift6
    DB 06h,1Dh,BFh,EFh,FBh,FBh,F7h,EFh    ; code 7  mountain^2 shift7
    DB 01h,02h,04h,08h,08h,04h,02h,01h    ; code 8  diamond
    DB 02h,04h,08h,10h,10h,08h,04h,02h    ; code 9  diamond^2 shift1
    DB 04h,08h,10h,20h,20h,10h,08h,04h    ; code 10 diamond^2 shift2
    DB 08h,10h,20h,40h,40h,20h,10h,08h    ; code 11 diamond^2 shift3
    DB 10h,20h,40h,80h,80h,40h,20h,10h    ; code 12 diamond^2 shift4
    DB 20h,40h,80h,01h,01h,80h,40h,20h    ; code 13 diamond^2 shift5
    DB 40h,80h,01h,02h,02h,01h,80h,40h    ; code 14 diamond^2 shift6
    DB 80h,01h,02h,04h,04h,02h,01h,80h    ; code 15 diamond^2 shift7
    DB 01h,02h,04h,08h,10h,20h,40h,80h    ; code 16 slash
    DB 02h,04h,08h,10h,20h,40h,80h,01h    ; code 17 slash^2 shift1
    DB 04h,08h,10h,20h,40h,80h,01h,02h    ; code 18 slash^2 shift2
    DB 08h,10h,20h,40h,80h,01h,02h,04h    ; code 19 slash^2 shift3
    DB 10h,20h,40h,80h,01h,02h,04h,08h    ; code 20 slash^2 shift4
    DB 20h,40h,80h,01h,02h,04h,08h,10h    ; code 21 slash^2 shift5
    DB 40h,80h,01h,02h,04h,08h,10h,20h    ; code 22 slash^2 shift6
    DB 80h,01h,02h,04h,08h,10h,20h,40h    ; code 23 slash^2 shift7
    DB 80h,40h,20h,10h,08h,04h,02h,01h    ; code 24 backslash
    DB 01h,80h,40h,20h,10h,08h,04h,02h    ; code 25 backslash^2 shift1
    DB 02h,01h,80h,40h,20h,10h,08h,04h    ; code 26 backslash^2 shift2
    DB 04h,02h,01h,80h,40h,20h,10h,08h    ; code 27 backslash^2 shift3
    DB 08h,04h,02h,01h,80h,40h,20h,10h    ; code 28 backslash^2 shift4
    DB 10h,08h,04h,02h,01h,80h,40h,20h    ; code 29 backslash^2 shift5
    DB 20h,10h,08h,04h,02h,01h,80h,40h    ; code 30 backslash^2 shift6
    DB 40h,20h,10h,08h,04h,02h,01h,80h    ; code 31 backslash^2 shift7
    DB 00h,18h,3Dh,77h,EFh,EFh,DFh,BFh    ; code 32 wedgeA (new design)
    DB 70h,E8h,FCh,DCh,DEh,BFh,7Dh,7Bh    ; code 33 wedgeB (new design)
    DB 00h,31h,7Bh,EFh,DFh,DFh,BEh,7Eh    ; code 34 wedgeA->wedgeB shift1
    DB 01h,63h,F7h,DFh,BFh,BEh,7Dh,FDh    ; code 35 wedgeA->wedgeB shift2
    DB 03h,C7h,EFh,BEh,7Eh,7Dh,FBh,FBh    ; code 36 wedgeA->wedgeB shift3
    DB 07h,8Eh,DFh,7Dh,FDh,FBh,F7h,F7h    ; code 37 wedgeA->wedgeB shift4
    DB 0Eh,1Dh,BFh,FBh,FBh,F7h,EFh,EFh    ; code 38 wedgeA->wedgeB shift5
    DB 1Ch,3Ah,7Fh,F7h,F7h,EFh,DFh,DEh    ; code 39 wedgeA->wedgeB shift6
    DB 38h,74h,FEh,EEh,EFh,DFh,BEh,BDh    ; code 40 wedgeA->wedgeB shift7
    DB E0h,D0h,F8h,B8h,BDh,7Fh,FBh,F7h    ; code 41 wedgeB->wedgeA shift1
    DB C0h,A0h,F0h,71h,7Bh,FFh,F7h,EEh    ; code 42 wedgeB->wedgeA shift2
    DB 80h,40h,E1h,E3h,F7h,FFh,EEh,DDh    ; code 43 wedgeB->wedgeA shift3
    DB 00h,81h,C3h,C7h,EEh,FEh,DDh,BBh    ; code 44 wedgeB->wedgeA shift4
    DB 00h,03h,87h,8Eh,DDh,FDh,BBh,77h    ; code 45 wedgeB->wedgeA shift5
    DB 00h,06h,0Fh,1Dh,BBh,FBh,77h,EFh    ; code 46 wedgeB->wedgeA shift6
    DB 00h,0Ch,1Eh,3Bh,77h,F7h,EFh,DFh    ; code 47 wedgeB->wedgeA shift7
PATTERNS_LEN EQU 384

BLANK_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; BLANKCODE's actual glyph: truly blank

; SCREEN1 color table: 1 byte per 8 CONSECUTIVE character codes.
; Only groups 0,1,2,3,4,5 (codes 0-47) are meaningful here;
; groups 6-31 (codes 48-255, unused by this scroller) are filled
; with a harmless placeholder color.
COLORDATA:
    DB 0F4h    ; group0 codes  0- 7 mountain family (white/blue, new design)
    DB C3h    ; group1 codes  8-15 diamond family
    DB C3h    ; group2 codes 16-23 slash family
    DB C3h    ; group3 codes 24-31 backslash family
    DB 0A2h    ; group4 codes 32-39 wedge family (brown/green, new design)
    DB 0A2h    ; group5 codes 40-47 wedge family (brown/green, new design)
    DB 44h,0D4h,0D3h,0DFh,0DAh,0F4h,0FFh,0F3h,0FAh,084h  ; group6=BLANKCODE, group7=shot-blue, group8=shot-green, group9=shot-white, group10=shot-brown, group11=anim1-blue(white/blue, DEBUG was yellow), group12=anim1-white(white/white, DEBUG), group13=anim1-green(white/lightgreen, DEBUG), group14=anim1-brown(white/brown, DEBUG), group15=anim2-blue(red/blue)
    DB 08Fh,083h,08Ah,0E4h,0E4h,0E8h,0F1h,0F1h,0E4h,0E4h  ; group16=anim2-white, group17=anim2-green, group18=anim2-brown, group19=enemy3-pat1(gray/blue), group20=enemy3-pat2(gray/blue), group21=enemy3-pat3(gray/red), group22=digits0-7(white/black), group23=digits8-9(white/black), group24=BOSS gray/blue, group25=BOSS gray/blue
    DB 0E4h,0E4h,014h,014h,014h,084h                       ; group26=BOSS gray/blue, group27=BOSS gray/blue, group28-30=BOSS black/blue, group31=BOSS red/blue
COLOR_LEN EQU 32

ROWDATA0:
    DB "MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM"

ROWDATA1:
    DB "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"

ROWDATA2:
    DB "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"

ROWDATA3:
    DB "SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS"

ROWDATA4:
    DB "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK"

ROWDATA5:
    DB "ABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABABAB"
