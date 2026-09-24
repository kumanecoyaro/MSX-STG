; ============================================================
; CYBER SHMUP - multi-rate parallax ground (6-tier road)
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
WRTVRM  EQU 004Dh   ; BIOS: 1byte VRAM write(HL=VRAM addr,A=value) - Ebuz(2026-09-14組み込み)が使用

TICK        EQU 0E000h

; Global game tick: increments once every time the wedge row
; (screen row23, the fastest-scrolling tier - PXCHAR_G8) updates,
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
PHASE_MINUS1 EQU 0E00Ah  ; CELL_LOOP_0/2/3/5's own scratch - ROWPHASE-1, precomputed once per row instead of every one of its 32 loop iterations (ported from tools/stage2_combined/combined_test.asm's own TERRAIN_RENDER_ROW fix, round26/27 there)
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

PAT_SHIP    EQU 0       ; 16x16 sprite pattern number (32 bytes at SPRPAT+0);
                        ; holds SHIP_MID_PATTERN (level flight) - see PLAYER_SHIP_PAT
PAT_ACCENT  EQU 16      ; 16x16 accent overlay, drawn at ship_X+8 (32 bytes at SPRPAT+128);
                        ; holds ACCENT_MID_PATTERN - see PLAYER_ACCENT_PAT
PAT_ACCENT_DOWN EQU 20  ; ACCENT_DOWN_PATTERN, shown while diving (32 bytes at SPRPAT+160;
                        ; free range right after PAT_ACCENT's own 16-19)
PAT_ACCENT_BARRIER      EQU 128 ; ACCENT_MID_BARRIER_PATTERN, shown instead of PAT_ACCENT
                                ; while the barrier is equipped (32 bytes at SPRPAT+1024;
                                ; codes128-255 confirmed genuinely free via emulator VRAM
                                ; survey - nothing else in this file ever LDIRVMs there)
PAT_ACCENT_DOWN_BARRIER EQU 132 ; ACCENT_DOWN_BARRIER_PATTERN, same idea for the DOWN pose
; (follow-up28) 満タンの間、バリア付きアクセント(128 MID / 132 DOWN)を右半分だけ
; 左右反転した絵(156 / 160)と2フレームごとに切り替える。
PAT_ACCENT_BARRIER_M EQU 156
GAUGE_MAX EQU 64               ; レーザーのエナジーゲージ満タン(px、1000点=1px、6万4千点)
PAT_PLAYER_EXPLOSION EQU 136    ; PLAYER_EXPL_PATTERN (16x16 hw-sprite burst
                                 ; glyph for PLAYER_EXPL_UPDATE_ALL), always
                                 ; loaded at INIT unlike the boss's own lazy-
                                 ; loaded EXPLOSION_PATTERN (codes108-111,
                                 ; boss-only) - codes136-139 confirmed
                                 ; genuinely free via emulator VRAM survey
                                 ; (32 bytes at SPRPAT+1056)
PAT_SHIP_UP   EQU 112   ; SHIP_UP_PATTERN, shown while climbing (32 bytes at SPRPAT+896;
                        ; free range between EXPLOSION_PATNUM's 108-111 and PAT_PARTICLE's 120)
PAT_SHIP_DOWN EQU 116   ; SHIP_DOWN_PATTERN, shown while diving (32 bytes at SPRPAT+928)

; (2026-09-21、"ステージ1スタート直後...飛び込んでくる演出"): 開始直後の
; 飛び込み演出専用の2枚(ShipStart1/2)。codes140-255はブート直後・
; 549件スケジュール完走+ステージクリア一周後のいずれも実VRAM調査で
; 空きと確認済み(16000フレームの実プレイシミュレーション)。
PAT_SHIP_ENTRY_BODY   EQU 140  ; SHIP_ENTRY_BODY_PATTERN(ShipStart2、赤)
PAT_SHIP_ENTRY_ACCENT EQU 144  ; SHIP_ENTRY_ACCENT_PATTERN(ShipStart1、白)

SPR_RED     EQU 08h     ; sprite color: red
SPR_WHITE   EQU 0Fh     ; sprite color: white
SPR_BLACK   EQU 01h     ; sprite color: black
SPR_LIGHTGREEN EQU 03h  ; sprite color: light green (TMS9918 index3)
SPR_LIGHTRED   EQU 09h  ; sprite color: light red (TMS9918 index9)
SPR_PURPLE     EQU 0Dh  ; sprite color: dark magenta/purple (TMS9918 index13)
SPR_YELLOW     EQU 0Bh  ; sprite color: light yellow (TMS9918 index11) -
                         ; round64追加分、"自機爆発にイエロー加えた爆発に"
SPR_TERM_Y  EQU 208     ; special Y value: stop sprite processing here

PLAYER_SPEED EQU 2     ; was raised to 4 to compensate for the (now-removed)
                        ; per-frame HALT slowdown; back to its original value
PLAYER_MINX  EQU 0
PLAYER_MAXX  EQU 240    ; 256-16 (ship is 16 dots wide)
; "自機の移動制限範囲を8px下げて 今は8pxだと思うんで16pxに"(2026-09-13):
; 8→16(2 char rows down, clears row0 score display by a full extra row).
PLAYER_MINY  EQU 16
PLAYER_MAXY  EQU 150    ; keeps the ship out of the whole 4-row ground
                        ; scroller (screen rows 20-23), with an extra
                        ; PLAYER_SPEED(2)-dot margin on top of the usual
                        ; -8 non-bottom-aligned offset (see PLAYER_SPEED/
                        ; the "SUB 8" before each sprite Y OUT below):
                        ; 150 = GROUND_ROW0*8-8-2 = 160-8-2. This also
                        ; pushes the shot spawn row - (PLAYERY+8)>>3 -
                        ; below GROUND_ROW0 at every reachable PLAYERY,
                        ; so shots can never land on/over the ground
                        ; scroller either; see BULLET_PAT_BLUE below.
PLAYER_INITX EQU 16
PLAYER_INITY EQU 64

; --- shots are background characters, not sprites, so any number ---
; --- can be on the same scanline as the ship with no "4 sprites  ---
; --- per line" flicker. 8x8, single cell: since PLAYER_SPEED=2,   ---
; --- PLAYERY mod 8 only ever takes the even values 0,2,4,6, so the---
; --- shape (2 rows tall) is placed starting at row=phase - this   ---
; --- spans a 6-dot range (0..6) and always fits inside the 8-row  ---
; --- cell with no clipping.                                       ---
; --- Only one color variant now (blue/sky): shots can never reach   ---
; --- the ground scroller (see PLAYER_MAXY), so the green/white/     ---
; --- brown variants that used to exist alongside this one were      ---
; --- removed. Codes 56-63 = blue, phase-indexed 0-7, only the even  ---
; --- slots hold real content.                                       ---
BULLET_PAT_BLUE  EQU 56
BULLET_MAXCOL EQU 31    ; last valid column (32-wide name table, 0-31)
GROUND_ROW0   EQU 20    ; first screen row of the 4-row ground scroller
                        ; (was 5 rows/GROUND_ROW0=19; TIER5_BACKSLASH's own
                        ; row was deleted to cut per-frame VDP/CPU load,
                        ; and TIER1_MOUNTAIN/TIER3_DIAMOND/TIER4_SLASH each
                        ; now draw one row lower, filling the gap, while
                        ; TIER6_WEDGE stays fixed at screen row23, the
                        ; bottom of the screen; was 6 rows/GROUND_ROW0=18
                        ; before that, when TIER2_DIAMOND's own row was
                        ; similarly deleted)

; --- flowing background clouds: purely decorative, drawn as BG      ---
; --- (name table) characters on the two sky rows just below the     ---
; --- score line, independent of the 4-row ground scroller. Both     ---
; --- rows use the same 2-tile (WA/WB) cloud glyph pair - row2 shows  ---
; --- it twice back to back (4 cells total), row3 shows it once (2   ---
; --- cells). Movement is whole-character-cell (no sub-pixel rotation---
; --- needed, unlike the ground scroller's LUT-driven smooth scroll) ---
; --- - see CLOUD_UPDATE_ALL. Codes 25-26 reuse 2 of the freed        ---
; --- backslash-family slots (24-31, formerly dead TIER5_BACKSLASH    ---
; --- data - see PATTERNS); their color group (group3, codes 24-31)   ---
; --- was already fg=white/bg=blue in COLORDATA, matching the         ---
; --- requested look with no COLORDATA change needed. Suspended       ---
; --- entirely while BOSS_STATE!=0 - the boss's own nametable map     ---
; --- (BOSS_MAP) is drawn at screen row1 col26 onward across 16 rows, ---
; --- so it overlaps both cloud rows; continuing to erase/redraw      ---
; --- clouds through that area would corrupt the boss art.            ---
CLOUD_WA_CODE EQU 25    ; wide cloud glyph pair, left half (screen rows 1/2)
CLOUD_WB_CODE EQU 26    ; wide cloud glyph pair, right half (screen rows 1/2)
CLOUDW_ROW      EQU 1   ; screen row2 (0-indexed row1): 2x(WA,WB) = 4 cells
CLOUDN_ROW      EQU 2   ; screen row3 (0-indexed row2): 1x(WA,WB) = 2 cells
CLOUDW_INTERVAL EQU 2   ; frames per 1-cell move (row2)
CLOUDN_INTERVAL EQU 3   ; frames per 1-cell move (row3)
CLOUD_SPAWN_COL EQU 32  ; leftmost cell starts one column past the right edge

FIRE_COOLDOWN EQU 0E3D2h ; frames to wait before another shot can spawn
FIRE_COOLDOWN_LEN EQU 1  ; "1 cycle" gap between shots (see fire logic)
TEMP_ERASE_BYTE EQU 0E3D6h ; scratch: byte to restore when erasing a shot
M_TMP EQU 0E3D7h ; scratch: PLAYERY mod 8 during spawn calc

PLAYERX      EQU 0E3C0h
PLAYERY      EQU 0E3C1h
PLAYER_SHIP_PAT EQU 0EF11h ; this frame's ship sprite pattern number (PAT_SHIP/
                            ; PAT_SHIP_UP/PAT_SHIP_DOWN) - set from JOY_STICK
                            ; right after the movement dispatch, read back at
                            ; the sprite-attribute write further down
PLAYER_ACCENT_PAT EQU 0EF12h ; same idea for the accent overlay (PAT_ACCENT/
                              ; PAT_ACCENT_DOWN only - no up-frame for this one)
REDRAW_SRC_PATTERN EQU 0EF13h ; 2 bytes: which 8x8 glyph REDRAW_UNIT_PATTERN
                               ; copies into a unit's TL/BR quadrant this call -
                               ; set by the caller (see SET_REDRAW_SRC_FROM_SEQ)
                               ; right before every CALL, since it's shared/
                               ; global state read by a routine with no spare
                               ; register free to pass it directly
ENEMY5_ANIM_SEQ   EQU 0EF15h  ; enemy5's shared (all-instances-synced) 1,2,3,2
                               ; quadrant-anim index - see ENEMY5_ANIM_STEP
ENEMY5_ANIM_TIMER EQU 0EF16h
EBSD_DRAW_PAT   EQU 0EF17h    ; EBSD_DRAW's precomputed pattern#/color for
EBSD_DRAW_COLOR EQU 0EF18h    ; this frame - computed outside the DI-timed
                               ; VDP write block below, since a TYPE_ENEMY4
                               ; branch there would disturb the fixed NOP
                               ; spacing (see EBSD_DRAW)
; --- flowing background clouds (see CLOUD_UPDATE_ALL) ---
CLOUDW_ACTIVE EQU 0EF19h
CLOUDW_COL    EQU 0EF1Ah   ; signed (two's complement): leftmost of row2's 4-cell cloud
CLOUDW_TIMER  EQU 0EF1Bh   ; frames left until next 1-cell move
CLOUDW_WAIT   EQU 0EF1Ch   ; frames left until next spawn attempt, while inactive
CLOUDN_ACTIVE EQU 0EF1Dh
CLOUDN_COL    EQU 0EF1Eh   ; signed (two's complement): leftmost of row3's 2-cell cloud
CLOUDN_TIMER  EQU 0EF1Fh
CLOUDN_WAIT   EQU 0EF20h
; each bullet: ACT(active flag), ADDR(2 bytes: VRAM address of its
; row's column0, low byte then high byte so LD HL,(ADDR) loads
; both), COL(0-31, current column), ROW(0-23, fixed at spawn - used
; to know whether to restore ground terrain or sky blank on erase,
; and whether to use the blue or green shot color), PAT (character
; code to draw, fixed at spawn)
; (2026-09-24、"まず5発目標で"): 3発ぶん丸ごと複製していた弾の処理を、
; BULLETC(作業用コピー)に対する1本の処理+BULLET_EACH(全スロットを回す)へ
; まとめ、スロット数をBULLET_SLOTSで変えられるようにした。本体は旧ENEMY_POOLの
; 32スロット時代の跡地(E8ED-EACB、未使用)へ移した。1スロット6byte:
; +0 ACT, +1/+2 ADDR, +3 COL, +4 ROW, +5 PAT。
BULLET_SLOTS EQU 5
; (2026-09-24、"ギャップ埋めのウェイトを"): 空いているスロット1つにつき、弾1発を
; 処理したのと同じくらい空回りして、撃っている時と撃っていない時の速さの差を埋める。
; 実測の弾1発の重さは約2,300〜6,500T(敵が多いほど重い)。実機で調整する値。
BULLET_IDLE_T     EQU 3000
BULLET_IDLE_LOOPS EQU BULLET_IDLE_T/26      ; BIP_WAITの1周=26T
BULLET_POOL  EQU 0E8F0h   ; BULLET_SLOTS*6 = 30 bytes (E8F0h-E90Dh)
BULLETC_ACT  EQU 0E90Eh   ; 処理中のスロットのコピー(6 bytes、E90Eh-E913h)
BULLETC_ADDR EQU 0E90Fh
BULLETC_COL  EQU 0E911h
BULLETC_ROW  EQU 0E912h
BULLETC_PAT  EQU 0E913h
BULLET_CUR_PTR EQU 0E914h ; 処理中のスロットの番地(2 bytes)
BULLET_CUR_IDX EQU 0E916h ; 処理中のスロット番号(0..BULLET_SLOTS-1)
BULLET_EACH_FN EQU 0E917h ; BULLET_EACHが呼ぶ処理(2 bytes)
BULLET0_ACT  EQU BULLET_POOL      ; テスト等が参照する旧名(スロット0-2)
BULLET0_ADDR EQU BULLET_POOL+1
BULLET0_COL  EQU BULLET_POOL+3
BULLET0_ROW  EQU BULLET_POOL+4
BULLET0_PAT  EQU BULLET_POOL+5
BULLET1_ACT  EQU BULLET_POOL+6
BULLET1_ADDR EQU BULLET_POOL+7
BULLET1_COL  EQU BULLET_POOL+9
BULLET1_ROW  EQU BULLET_POOL+10
BULLET1_PAT  EQU BULLET_POOL+11
BULLET2_ACT  EQU BULLET_POOL+12
BULLET2_ADDR EQU BULLET_POOL+13
BULLET2_COL  EQU BULLET_POOL+15
BULLET2_ROW  EQU BULLET_POOL+16
BULLET2_PAT  EQU BULLET_POOL+17

; --- enemy: one slow left-moving 16x16 sprite (sprite slot 1). ---
; --- Pattern is a solid diagonal (top-left+bottom-right filled, ---
; --- top-right+bottom-left transparent), gray. It enters from   ---
; --- the right edge, exits off the left edge (or is destroyed   ---
; --- by a shot), then respawns alternating between two fixed Y  ---
; --- positions (16 dots from the top, and 16 dots above the     ---
; --- 4-row ground scroller).                                    ---
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

; --- destroyed-quadrant explosion (background-character animation) ---
; 3 slots (round-robin), 8 bytes each: ACTIVE,FRAME,TIMER,ROW,COL,
; SAVED_C,SAVED_Cm1,SAVED_Cm2 (round69 follow-up: FRAME replaces the
; old 2-phase PHASE field with a 1/2/3 frame counter; SAVED_Cm1/Cm2
; repurpose what used to be the old per-slot CODE1/CODE2 color-select
; bytes - no longer needed now that the new animation always uses one
; fixed color group [see EXP_CODE_THIN/THICK below] - to instead hold
; the pre-explosion background of the 2 nearest columns the wider
; frame2/frame3 footprints touch. The 4th column [C-3] doesn't fit in
; this 8-byte stride without shifting ANIM_RR/ANIM_TMP_*/SND_TIMER/... -
; a cascade of otherwise-unrelated fixed RAM addresses this project has
; been burned by before - so it lives in its own small EXPLOSION_SAVED_
; CM3 array instead (see its own EQU comment).
ANIM_BASE       EQU 0E409h
ANIM_RR         EQU 0E421h
ANIM_TMP_ROW    EQU 0E422h
ANIM_TMP_COL    EQU 0E423h
ANIM_TMP_VAL    EQU 0E424h
ANIM_ADDR_TMP   EQU 0E425h   ; 2 bytes
; (2026-09-07、実機フィードバック対応、"新爆発の表示時間は半分でいい
; 長すぎ"): 8->4へ半減。3フレームアニメの1コマあたりの表示時間が
; 半分になる(合計の再生時間も半分)、フレーム構成(1個→3個→2個の
; セル配置)自体は無変更。
ANIM_FRAME_LEN  EQU 4
; round69 follow-up ("爆発処理の変更...元の爆発パターンは削除して空きに"):
; the old 8-color-class ANIM1_x/ANIM2_x flicker (2 phases x 4 row-based
; colors) is gone. The new 3-frame/multi-cell animation uses exactly 2
; distinct 8x8 tiles, ALWAYS in the same fixed color group - reusing
; the OLD explosion's own "anim2-blue" group (group15, codes120-127,
; COLORDATA byte 084h = fg8/bg4, decoded straight from COLORDATA's own
; comment: "group15=anim2-blue(red/blue)") completely unchanged, per
; the user's own confirmation this group should be directly reusable.
; Ground-row kills intentionally get the exact same blue-background
; tiles as sky kills now (no more per-row white/green/brown branching) -
; same simplification this file's own player-shot BG glyph already
; makes ("shot character patterns...blue only").
EXP_CODE_THIN  EQU 120   ; 2-row bar (frame1's only tile; frame2/3's side tiles)
EXP_CODE_THICK EQU 121   ; 4-row bar (frame2's own center tile only)
; 4th saved-background byte per anim slot (background originally at
; column C-3, only ever touched by frame3) - kept in its own small
; array rather than extending ANIM_BASE's 8-byte stride, since that
; would force ANIM_RR/ANIM_TMP_*/SND_TIMER/ENEMY_MODE/... (all
; contiguous fixed literal addresses laid out by hand, not computed
; relative to each other) to all shift too - the exact kind of RAM-
; collision cascade this project has hit (and documented at length)
; multiple times before. This tail-of-RAM region (right after
; PLAYER_DEATH_FALL_ACT, ~330 bytes clear of STACKTOP) is the same
; pocket several earlier rounds already used for exactly this kind of
; small standalone addition.
EXPLOSION_SAVED_CM3 EQU 0F237h   ; 3 bytes, one per anim slot

; ENEMY6の耐久値配列(ENEMY6_SLOTS個、1スロット1バイト) - 同じ「tail-of-
; RAM pocket」に新設(2026-09-08、"ステージ1のエネミー6の耐久値4に"、
; 詳細な経緯はENEMY6_STRUCT自身のコメント参照)。
ENEMY6_HP EQU 0F23Ah   ; 32 bytes (F23Ah-F259h)

; --- PSG (noise channel) shot/destroy sound effects ---
PSG_ADDR EQU 0A0h
PSG_DATA EQU 0A1h
SND_TIMER EQU 0E427h
; 実機フィードバック対応("そもそもchB、Cは空けてあってSE類はchAのみで
; 鳴らすはず"): 従来チャンネルC/Bにそれぞれ分けていたSOUND_SHOT/
; SOUND_POD_HIT(旧SND_TIMER_C)とSOUND_POD_FIRE(旧SND_TIMER_B)を、
; 全てチャンネルA(トーン)へ統合したことに伴い1本のタイマーへ統合。
; 3者とも元々「ゲート無しの単純な1フレーム1減衰」という同じ性質だった
; ため(周期はトリガー時にR0/R1へ即書き込むので、この統合タイマーは
; 音量エンベロープの長さにのみ影響)、統合しても個々の音色は一切変化
; しない。複数が短時間に重なった場合は後着が上書きする形になるが、
; 「SEの被りで上書きされるのは問題ない」とユーザー確認済み。
SND_TONE_TIMER EQU 0E4D0h

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
; (2026-09-13、"ボスの弾は...自機狙い弾になるように変更"): per-frame
; signed Y velocity for POD_BULLET1 - see POD_BULLET0_DY's own comment
; for the full design (this is just the 2nd bullet's own copy of the
; same field). Placed at 0E7ABh, the single confirmed-free byte between
; POD_LOOP_ALIVE_SNAPSHOT and POD_LAP_CYCLE (verified via a direct grep
; for "0E7ABh" across the whole file before use - genuinely untouched).
POD_BULLET1_DY   EQU 0E7ABh
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
; (2026-09-06、"一旦左端まで下がってから飛び去る様に変更"): ボス撃破直後、
; 従来は直接PLAYER_FLYAWAY_WAITを起動していたが、その前に自機を画面
; 左端(X=0)まで後退させる新規サブフェーズを追加。0E823hは空きバイト
; 確認済み(直前のBOSS_EXPL_SPRIDX・直後のBOSS_EXPL_ROWいずれも別用途の
; 1byteスカラーで隣接利用のみ、シンボルテーブル上でも他に一切参照なし)。
PLAYER_RETREAT_ACT  EQU 0E823h   ; 0=inactive, 1=retreating to X=0 before flyaway
BOSS_EXPL_ROW       EQU 0E824h   ; scratch: this pop's boss-map row
BOSS_EXPL_COL       EQU 0E825h   ; scratch: this pop's boss-map col
PLAYER_FLYAWAY      EQU 0E828h   ; 0=normal control, 1=auto-flying right, 2=off-screen/hidden
PLAYER_FLYAWAY_SPD  EQU 0E82Ah   ; current flyaway speed
PLAYER_FLYAWAY_DIST EQU 0E839h   ; total px traveled since flyaway started (accel curve)
PLAYER_RETREAT_SPEED EQU 2       ; px/frame while retreating to PLAYER_RETREAT_TARGET_X
; round142("下がり過ぎでパーティクルが右から出てしまってるんで下がるのは
; 左から32pxまでに"): 元は左端X=0まで後退させていたが、PLAYER_PARTICLE_
; FADE(下記)のPARTICLE_X更新はクランプなしの単純なADD(X+=DX、DX=-4/frame)
; のため、Xが0付近まで下がった状態で新しいパーティクルがX=0近辺で
; spawnすると数フレームで8bitアンダーフローし右端(252等)へラップして
; 見えてしまっていた(実測: 寿命8フレーム*DX(-4px/frame)=32pxちょうど
; 移動しきったところで消える設計のため、開始Xが32以上あれば寿命が
; 尽きるまでX=0に到達しない=アンダーフローが起こり得ない)。後退の目標
; XをPARTICLE寿命*|DX|とちょうど一致する32へ変更して解消。
PLAYER_RETREAT_TARGET_X EQU 32   ; px from the left edge the retreat stops at
PARTICLE_SPAWN_COOLDOWN EQU 0E83Ah  ; frames until the next spawn is allowed

; (2026-09-21、"ステージ1スタート直後...急に始まるのでなく飛び込んで
; くる演出...0,0からX128、Y64まで移動してそこからX32,Y64な"): 開始
; 直後の飛び込み演出、2区間構成。leg1(ACT=1): (0,0)→(SHIP_ENTRY_MID_X,
; PLAYER_INITY)、leg2(ACT=2): そこから→(PLAYER_RETREAT_TARGET_X,
; PLAYER_INITY)。最終位置・巡航高度はPLAYER_RETREAT_TARGET_X(32)/
; PLAYER_INITY(64、既存の通常巡航高度)をそのまま再利用。0F332hは
; PARTICLE_DY(0F32Eh、4byte)直後・STACKTOP(0F380h)手前の既存の空き
; 領域("0F22Bh-0F37Fhの341バイトの空き領域")内。
SHIP_ENTRY_ACT   EQU 0F332h  ; 0=通常/1=leg1中/2=leg2中
; (2026-09-23、"ボス到達時に5万点を下回った場合どこに居てもポッド弾は自機
; 狙いになるように チェックは到達時にのみ行え メインで回すな"):
; BOSS_SPAWNで1回だけ判定・格納(0=5万点未満で常時自機狙い、非0=従来
; 通り)。POD_BULLET_CALC_DIR(POD_AIM_PREP)はこれを読むだけ。
POD_AIM_NORMAL   EQU 0F333h
SHIP_ENTRY_SPEED EQU 2       ; px/frame、PLAYER_RETREAT_SPEEDと同じ考え方
SHIP_ENTRY_MID_X EQU 128     ; leg1の目標X(画面中央)

; --- Enemy1: one-time diagonal dodge toward the player when     ---
; --- crossing screen-center X. Per-instance now: E_PARAM0 (done?),  ---
; --- E_PARAM1 (remain), E_PARAM2 (dir) on the unified ENEMY_POOL.   ---
ENEMY_CENTER_X   EQU 128     ; screen-center X threshold for the dodge
ENEMY_DODGE_DIST EQU 16      ; total px moved diagonally, 1px/frame, per flight

; --- enemy-fired bullet (new): a small shared hw-sprite pool, fired  ---
; --- by Enemy4/TYPE_ENEMY4(=Enemy7, Y-aligned) and by Enemy1(=the   ---
; --- same TYPE_ENEMY4 entity, its own diagonal-dodge window)/Enemy2 ---
; --- (diagonal exit-dive window)/Enemy5(TYPE_ENEMY1_LOOK, screen-   ---
; --- center X as its own stand-in "diagonal" trigger point - see    ---
; --- EBSB_UPDATE's own comment) - "パターンはFlyerレーザーを流用    ---
; --- カラーはライトレッド". Pattern reused from Stage2's own        ---
; --- FlyerLaser bitmap (tools/stage2_combined/flyerlaser_gen.py's   ---
; --- own 8x8 horizontal-bar tile) - Stage1 is a completely separate ---
; --- bank/build from Stage2, so the raw bitmap bytes are redefined  ---
; --- here from scratch (EBULLET_PATTERN), not shared/imported.      ---
EBULLET_SLOTS  EQU 6
EBULLET_STRUCT EQU 4         ; +0 ACTIVE,+1 X,+2 Y,+3 SPRNUM
; (2026-09-13、"ステージ1の敵弾のプライオリティを自機とバリアの次に"):
; hw sprite priority on real TMS9918 hardware is purely slot-number order
; (lower slot = drawn on top). Slot0=barrier accent/slot1=ship body are
; already fixed (see PLAYER_ACCENT_PAT's own draw site's "redraw ship:
; slot1=body, slot0=accent overlay" comment) - EBULLET previously shared
; the generic ALLOC_SPRITE_NUM pool (slot2-31, first-come-first-served)
; with every other enemy type, so its priority relative to them was
; whatever order things happened to spawn in, not guaranteed to be right
; after the player. Given a fixed, dedicated slot range instead (one
; slot per EBULLET_POOL index, matching the Stage2 BOSS_SPR_BASE_SLOT-
; style "index IS the hw sprite number" convention), it's now always
; drawn above every other non-player/non-barrier sprite. Verified safe
; via a full-schedule real-MAINLOOP simulation of peak concurrent
; ALLOC_SPRITE_NUM usage EXCLUDING EBULLET's own slots (peak observed:
; 12 of the pool's now-24 remaining slots, well within budget) before
; shrinking ALLOC_SPRITE_NUM's own scan range to skip this reservation
; (see its own comment).
EBULLET_SPR_BASE_SLOT EQU 2  ; slots 2-7 (EBULLET_SLOTS=6), right after slot0/1
EBULLET_SPEED  EQU 6         ; dots/frame, left (faster than any enemy's own drift)
PAT_EBULLET    EQU 124       ; 4 patterns 124-127 (32 bytes at SPRPAT+992) - free range, see survey
E4_ALIGN_FIRE_COOLDOWN EQU 90 ; frames between Enemy7's own re-fires once Y keeps matching - untuned placeholder
ENEMY1_ANIM_FRAME_LEN EQU 4  ; frames per 1,2,3,2 quadrant-anim step while
                              ; dodging - 4 steps x 4 frames = the full
                              ; ENEMY_DODGE_DIST(16)-frame dodge, one cycle

; --- per-frame dodge progress: REMAIN counts down 16->0 (1px/frame),---
; --- DIR is the signed per-frame Y step (+1 or -1, set once when   ---
; --- the dodge triggers). Per-instance now: E_PARAM1/E_PARAM2 on    ---
; --- the unified ENEMY_POOL (see ENEMY_CENTER_X above).             ---
POD_VOLLEY_COLOR_TEST EQU 0E829h ; trial: +1 every frame while pods are launched, wraps 2-14

; --- rainbow particle trail during the flyaway: 4 slots (round142,
; --- "パーティクルの数も増やしたい" - up from 2), reusing pod-
; --- explosion sprite numbers 22-25 (of EXPLOSION_SPR_BASE's 8,
; --- 22-29 - all guaranteed free by the time the flyaway runs, the
; --- boss and its pods are long gone). Each particle actually
; --- travels (small random angle off due-left) and despawns after
; --- ~32px. round142: moved off the old tightly-packed E82B-E836
; --- block (zero slack before PLAYER_FLYAWAY_WAIT) into the known
; --- free pocket documented at PLAYER_EXPL_POOL/GAME_OVER_SEQ
; --- ("0F22Bh-0F37Fhの341バイトの空き領域") to make room for the
; --- extra 2 slots without shifting every RAM symbol after it.
PARTICLE_SLOTS       EQU 4
PARTICLE_ACT         EQU 0F31Ah  ; 4 bytes: 0=inactive, else frames of life left
PARTICLE_X           EQU 0F31Eh  ; 4 bytes
PARTICLE_Y           EQU 0F322h  ; 4 bytes
PARTICLE_COL         EQU 0F326h  ; 4 bytes
PARTICLE_DX          EQU 0F32Ah  ; 4 bytes, signed
PARTICLE_DY          EQU 0F32Eh  ; 4 bytes, signed
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

; --- on-screen score digits (row0, cols0-7 - see SCORE_DISPLAY) ---
DIGIT_BASE EQU 176   ; digit0 code; digitN = DIGIT_BASE+N (groups22-23)
; (2026-09-13、"Tick表示削除") - the on-screen GAME_TICK counter
; (GAME_TICK_DISPLAY, row0 cols29-31) itself is gone; DIGIT_BASE lives
; on as SCORE_DISPLAY's own digit codes.

; (2026-09-06、"STAGE1も2と同じで一旦画面をブラックで埋めてMISSION 1と
; 3秒表示してから"、"画面をブラックで埋めてMISSION 2とセンターに表示
; 3秒でいいかな"): "MISSION 1"/"MISSION 2"共有の8x8ドット文字専用
; パターンコード。コード64-87(group8-10、"shot-green"/"shot-white"/
; "shot-brown"用に色だけ予約されビットマップは一度も実装されなかった、
; COLORDATA自身のコメント参照)がLDIRVM/WRTVRM全呼び出し元の横断的な
; 洗い出し+エミュレータでの実VRAM調査(boot直後・6000フレーム実プレイ
; 後の両方でcodes64-87が全バイト0のまま)の両方で実際に空きと確認済み。
; (2026-09-07、"Mission表示のフォントは添付ファイルで"): ユーザー添付
; Font_24x24_1.json(CYBER_SUZUKA)から機械抽出したM,I,S,O,N,1,2の7グリフ
; +spaceの計8グリフへ差し替え(tools/pixel_font_8x8.py参照)。旧5x7
; フォント+DIGIT_BASE+1/+2再利用方式から、この8グリフだけで完結する
; 方式へ変更(group8のcode64-71をちょうど使い切る)。
MISSION_FONT_BASE EQU 64   ; M=64,I=65,S=66,O=67,N=68,space=69,1=70,2=71 (group8内)
; (2026-09-07、"ゲームオーバーは画面中央にGAME OVERと表示"): GAME OVER
; 表示専用の追加5文字(G,A,E,V,R - M/space/Oは上のMISSION_FONT_BASE側を
; 共用)。同じ調査で空きと確認済みのgroup9(codes72-79)先頭5コードへ配置、
; tools/pixel_font_8x8.pyの新規描き起こし文字(添付フォントと同じ書体
; スタイル)。
GAMEOVER_FONT_BASE EQU 72   ; G=72,A=73,E=74,V=75,R=76 (group9内)
; 3秒 @ 60Hz real vblank(SC_VBLANK_COUNT基準、GFEnding[Stage2]の
; ENDING_WAIT_TICKS=600[10秒@60Hz]と同じ換算)。
MISSION_SCREEN_TICKS EQU 180

; --- tick-based enemy spawn schedule: measured roughly every 30    ---
; --- ticks in order enemy1,enemy1,enemy2,enemy2,enemy3 (enemy3     ---
; --- lands around tick120). One-shot - once all 5 have fired,      ---
; --- nothing more triggers automatically (no looping).             ---
; --- 2026-09-12: 397エントリ(>255)のスケジュールを表現するため2byteへ
; --- 拡張、旧1byteの0E4D4hから独立した空き領域(0F25Ah、ENEMY6_HP末尾
; --- [0F259h]の直後・STACKTOP[0F380h]の手前)へ移設。0E4D4hはもう
; --- 誰も参照しない(旧アドレスの値の移行は不要、常にINITでゼロ
; --- クリアされるカウンタのため)。詳細はSPAWN_SCHEDULE_CHECK自身の
; --- コメント参照。
SPAWN_NEXT_INDEX EQU 0F25Ah    ; 2 bytes (0F25Ah-0F25Bh)
SPAWN_E1_Y EQU 0E506h          ; Y chosen for the next independent Enemy1 spawn
NEXT_SPRITE_NUM EQU 0E507h     ; rotating sprite attribute slot allocator (1-31, 0=player reserved)

; --- score: enemy1=100pts, enemy2=200pts, enemy3=300pts per kill -    ---
; --- always a multiple of 100, so SCORE stores real_score/100 rather  ---
; --- than the real score itself: a 24-bit binary counter (low word at ---
; --- SCORE, high byte at SCORE+2), incremented by 1/2/3 per kill      ---
; --- instead of 100/200/300 (see ADD_SCORE_100/200/300). This is what ---
; --- lets the display reach 6 significant digits (real score up to   ---
; --- 99,999,900) instead of the old plain-16-bit SCORE's ~65535      ---
; --- ceiling (which silently wrapped past it - no overflow check on  ---
; --- a bare ADD HL,DE). Displayed as a fixed 8-digit nametable string ---
; --- top-left (row0, cols0-7): 6 real digits (cols0-5) then a fixed   ---
; --- "00" (cols6-7, the two low decimal digits that are always zero). ---
SCORE        EQU 0E4D5h   ; 3 bytes: low word at +0, high byte at +2
; 実機フィードバック対応("WebMSXでフリーズやリセットがかかる これは実機
; も同様"の調査中にopenMSX上で発見・修正): 元は0E4D8hに置かれていたが、
; この付近(0E400h台、SND_TIMER/GAME_TICK/ANIM_*と同じクラスタ)は通常時は
; 安全でも、BGM_TICK(H.TIMI経由の割り込みハンドラ)がINIT完了直後の
; まだ不安定な期間に何度も発火する特定の状況下でSPが一時的にここまで
; 深く落ち込みうることをopenMSXでの実機再現で確認した(スタック上の
; リターンアドレスとSCORE_DIGITSが物理的に同じ番地を指してしまい、
; SCORE_DISPLAY自身の書き込みが自分自身の戻り先を破壊してPC=0への
; 暴走ジャンプ・疑似リセットを引き起こした)。深いSP低下そのものの
; 根本原因(何が毎割り込みごとに約24バイトずつ消費しているか)は未解明
; だが、この6バイトのスクラッチバッファ自体をSTACKTOP(0F380h)近くの
; 安全な未使用領域(0F22Bh-0F37Fh、PLAYER_EXPL_SPAWN_TIMERの直後、
; 341バイトの空き)へ移設することで、この特定の衝突経路は原理的に
; 発生しなくなる(SPがここまで浅い341バイト以内に収まる限り安全)。
SCORE_DIGITS EQU 0F22Bh   ; 6 bytes (hundred-thousands..ones, of SCORE - i.e. real score/100)

; "SE優先でショットは消す仕様に SE発声中はショット音は鳴らない" -
; SND_TONE_TIMERはSOUND_SHOT/SOUND_POD_HIT/SOUND_POD_FIREの3者が共有する
; 単一のデコイタイマー(round32以降の統合)なので、単に非0かどうかだけでは
; 「今鳴っているのはショット自身の減衰か、それとも優先されるべきSEの
; 減衰か」を区別できない。このフラグで「現在SND_TONE_TIMERを保持して
; いるのはSE(POD_HIT/POD_FIRE)側である」ことだけを記録し、SOUND_SHOT側は
; (SND_TONE_TIMER!=0 かつ このフラグ!=0)の間だけ発射自体を握りつぶす
; (PSGにもタイマーにも一切触れない)。SND_TONE_TIMERが0まで減衰すれば
; このフラグの値に関わらず次のショットは通る(フラグの明示クリアは
; 不要、SOUND_SHOT成功時に0へ戻すのみ)。SCORE_DIGITSの直後(0F22Bh-
; 0F37Fhの341バイトの空き領域内)に配置。
SND_TONE_IS_SE EQU 0F231h

; --- direct/raw PSG joystick read (BIOS GTTRIG's trigger B never  ---
; --- worked on real hardware; a raw PSG read was confirmed correct---
; --- there, so joystick input now goes through this instead of    ---
; --- GTSTCK/GTTRIG). R15 bit6=0 selects joystick port1's pins onto ---
; --- R14: bit0=up,bit1=down,bit2=left,bit3=right,bit4=trigA,       ---
; --- bit5=trigB, all active-LOW.                                   ---
JOY_PSG_ADDR EQU 0A0h
JOY_PSG_DATA EQU 0A1h
JOY_PSG_READ EQU 0A2h
JOY_RAW EQU 0E4DEh
JOY_STICK EQU 0E4E1h  ; BIOS GTSTCK result (0-8 direction code)
JOY_TRIG EQU 0E4E2h   ; BIOS GTTRIG result, trigger A (0=released, FFh=pressed)
JOY_TRIGB EQU 0E4DFh      ; BIOS GTTRIG result, trigger B (0=released, FFh=pressed)
JOY_TRIGB_PREV EQU 0E4E0h ; trigger B state, previous frame (for edge detection)
FIREB_EDGE EQU 0E4E3h     ; 1 = trigger B was just pressed this frame

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
ENEMY2_ANIM_FRAME_LEN EQU 4  ; frames per 1,2,3,2 quadrant-anim step while
                              ; diving/climbing (ECS_S7_A/B's diagonal phase)
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
; --- bottom), then exits diagonally toward the lower-right. Each  ---
; --- spawning wave (see ENEMY3_WAVE_POOL) owns its own dedicated  ---
; --- ENEMY3_SLOTS-instance slice of ENEMY3_POOL, recycled until   ---
; --- that wave's own budget runs out - waves never contend with   ---
; --- each other for a slot, so several running at once each show  ---
; --- up to ENEMY3_SLOTS of their own members on screen.           ---
; --- Destroyed by shots using the same shared explosion/sound.    ---
ENEMY3_CODE1  EQU 152          ; pattern1 (gray/blue), group19
ENEMY3_CODE2  EQU 160          ; pattern2 (gray/blue), group20
ENEMY3_CODE3  EQU 168          ; pattern3 (gray/red),  group21
ANIM3_PACE    EQU 6            ; frames held per pulse-animation frame
; Concurrent instances PER WAVE (its own dedicated slice). BG-tile
; instances aren't sprite-limited, so this is not a "safe count" cap -
; see ENEMY3_UPDATE_SLOT/CHECK_BULLET_VS_ENEMY3 for the actual per-
; instance cost reduction (skip the erase+redraw VDP writes when a
; slot's cell hasn't moved since last frame) that makes a high count
; affordable instead.
ENEMY3_SLOTS  EQU 8
; (2026-09-13、"エネミー3が左から出てくる時がある"のRAM衝突バグ修正で
; 11->12。旧CENTERX(byte12)はENEMY3_CENTERX_TABLEという「ENEMY3_POOLと
; 同じ704byteストライドの並行配列」として外出しされていたが、実際に
; 使うのは1byte/slotだけなのに704byte分(64byte分の payload に対し
; 640byte超過)を予約領域として占有しており、その未使用の大半
; (EE98h-F157h)へPLAYER_SHIP_PAT/PLAYER_ACCENT_PAT/REDRAW_SRC_PATTERN/
; ENEMY5_ANIM_SEQ・TIMER/EBSD_DRAW_PAT・COLOR/CLOUDW_*/CLOUDN_*が
; 何重にも誤って配置されてしまっていた(過去にも一度EF00hで同型の
; 衝突が発覚しENEMY6_POOLをF158hへ退避した経緯があるが、テーブル
; 自体の過大な footprint は温存されたままだった)。今回はCENTERXを
; ENEMY3_STRUCT自身の12番目のフィールドとして畳み込み、外出しテーブル
; ごと廃止(ENEMY3_CENTERX_TABLE/ENEMY3_CENTERX_ADDRは削除)することで
; 衝突を構造的に解消、副産物としてRAMも640byte解放。
ENEMY3_STRUCT EQU 12           ; ACTIVE,PHASE,X,Y,ROW,COL,ANGLEIDX,STEPCNT,REVCNT,ANIMIDX,ANIMTIMER,CENTERX
ENEMY3_SPAWN_X EQU 200
ENEMY3_SPAWN_Y EQU 8
ENEMY3_CENTER_X EQU 128
ENEMY3_CENTER_Y EQU 80
ENEMY3_DIAG_SPEED EQU 2
ENEMY3_STEP_FRAMES EQU 2       ; frames held per LUT angle step
ENEMY3_TOTAL_STEPS EQU 36      ; 24 LUT points x 1.5 revolutions
ENEMY3_START_ANGLE EQU 6       ; LUT index for the top of the circle
ENEMY3_EXIT_SPEED EQU 3
; Row 17 sits just above GROUND_ROW0(20) - i.e. above the scrolling
; ground entirely, in the plain sky.
ENEMY3_EXIT_TARGET_Y EQU 136       ; row 17 pixel Y (17*8): exit levels off
                                    ; here, above the scroller, then flies
                                    ; right off-screen
ENEMY3_SPAWN_INTERVAL EQU 8    ; frames between spawns WITHIN one wave's own budget
                                ; ("1 count" - matches the schedule tick unit).

ENEMY3_SPAWN_COUNT EQU 0E4CEh  ; how many spawned so far in total (resume enemy1/2 at 32)
; Each schedule trigger (SPAWN_E3_WAVE) claims its own ENEMY3_WAVE_POOL
; slot and runs its own independent budget/timer/offset from there on -
; and now also its own dedicated ENEMY3_SLOTS-instance slice of
; ENEMY3_POOL (wave slot N's units live at ENEMY3_POOL+N*ENEMY3_SLOTS*
; ENEMY3_STRUCT), so nothing is shared between waves at all - several
; triggers firing close together never fight over each other's state OR
; each other's visible slots. A wave's offset is just "how much to add
; on top of the CIRCLE_LUT position" (see E3_CIRCLE_POS/E3_DIAG) - one
; fixed value for every member that wave spawns, nothing more.
; (2026-09-23、メインループ監査、"Enemy3も同じように調べて減らして"): 8→3。
; ボスまでスケジュールを通した実測(撃つ/撃たない両条件)で同時に動く
; ウェーブは最大2本(wave0/1のみ使用)、1ウェーブ内は8体フル使用。余裕1本
; を残して3本に。SPAWN_E3_WAVE/ENEMY3_TRY_SPAWNの展開もこの数に合わせる
; こと(4本以上同時に来るとそのトリガーは無言でドロップされる)。
ENEMY3_WAVE_SLOTS EQU 3
ENEMY3_WAVE_POOL   EQU 0EBB7h  ; ENEMY3_WAVE_SLOTS*4 bytes: ACTIVE,BUDGET,TIMER,OFFSET
; How many ENEMY3_POOL instances are alive right now, across every wave
; (incremented in ENEMY3_DO_SPAWN, decremented in E3_DEACTIVATE and
; E3_HIT_ONE_SLOT's kill - the only two places a unit goes inactive).
; CHECK_BULLET_VS_ENEMY3 checks this first and bails out immediately
; when it's 0 instead of paying for a full 64-slot scan on every
; bullet, every frame, for a wave that isn't even running.
ENEMY3_ACTIVE_COUNT EQU 0EBD7h
; ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS*ENEMY3_STRUCT = 288 bytes (旧768), laid out as
; ENEMY3_WAVE_SLOTS consecutive ENEMY3_SLOTS-instance slices (one per
; wave slot, same order). Each instance's 12th field (offset+11) is its
; OWN circle-center X pixel offset, copied at spawn time from its owning
; wave's OFFSET - this used to live in a separate ENEMY3_CENTERX_TABLE
; parallel array (see git history / HANDOFF.md Round109 if that name
; still turns up anywhere), which was removed after it turned out to
; alias several unrelated live variables (see ENEMY3_STRUCT's own
; comment for the full story).
ENEMY3_POOL          EQU 0EBD8h

; --- enemy6: new BG-cell enemy (16x16, drawn as a 2x2 block of        ---
; --- nametable cells, same as enemy3's single-cell approach just      ---
; --- wider) - straight left drift, stepping one column (8px) every    ---
; --- ENEMY6_STEP_FRAMES frames. Glyph is NEWENEMY_CODE_TL/TR/BL/BR    ---
; --- (see their own comment, near NEWENEMY_PATTERN_*) - already       ---
; --- loaded into VRAM at boot. Spawns from the schedule now (SPAWN_E6,---
; --- any row via ENEMY6_ROW_TABLE - same "any row" idea as SPAWN_E4/  ---
; --- SPAWN_BASEY_TABLE, just a raw row number instead of a pixel      ---
; --- baseY since ENEMY6_POOL already tracks ROW as a row, not a Y).   ---
; --- It's BG cells, not hardware sprites, so it isn't subject to the  ---
; --- MSX1 sprite-per-scanline limits Enemy3 (also BG-cell) already    ---
; --- gets to ignore - matches ENEMY3_SLOTS's budget-32 headroom.      ---
ENEMY6_SLOTS  EQU 32
ENEMY6_STRUCT EQU 4             ; ACTIVE,ROW,COL,PHASE (COL = left column of the 2-wide glyph;
                                 ; PHASE = 0/1/2/3, index into ENEMY6_ANIM_CODES - advances
                                 ; one step every 1-cell move, see ENEMY6_STEP_ONE)
; round135follow-up15("打つたびに当たってもないのに敵の処理をしてないか
; 探しながら弾を飛ばすとかな"): CHECK_BULLET_VS_ENEMY6は、ENEMY3が既に
; 持っているENEMY3_ACTIVE_COUNTのような「そもそも1体も居なければ即RET」
; という短絡が無く、Enemy6が画面上に1体も居なくても毎回ENEMY6_SLOTS(32)
; 全スロットのACTフラグを律儀に読みに行っていた実測ムダ(実測:
; 空プールでも202命令/回、フル32体稼働時は1834命令/回 - 発射中の弾ごと・
; 毎フレーム発生するため自機ショット時の重さに直結していたと判明)。
; ENEMY3と全く同じ「専用カウンタで0体なら丸ごとスキップ」方式を追加。
; 空きバイト0F285h(旧EBUZ_SPAWN_TICK_INDEX跡地、EBUZ_CUR_ROW_ADDRからの
; 既存一括ゼロクリア範囲[42byte]に元々含まれているため新規INIT処理は
; 不要)を再利用、新規RAM確保ゼロで実装。
ENEMY6_ACTIVE_COUNT EQU 0F285h
; "ステージ1のエネミー6の耐久値4に"(2026-09-08) - 従来は被弾即死
; だったのを耐久値制へ変更(ENEMY4_HP/E_HPと同じ「hits to destroy」の
; 考え方)。ENEMY6_STRUCT自体は4バイトのまま拡張しない - 既存のROW(+1)/
; COL(+2)/PHASE(+3)オフセットは(IX+n)で直参照されている箇所が多く、
; 構造体を伸ばすとENEMY6_POOL自体のサイズも128->160byteに増え、
; すぐ後ろのEBULLET_POOL/BARRIER_HP等(F1D9h以降、F200h-F201hのComb
; バンク切替トランポリン専用領域を挟んで詰めて配置済み)を全て玉突きで
; 再配置する必要が生じ、過去に実際に踏んだRAM衝突バグ(round37
; follow-up7参照)の再発リスクが高いと判断。代わりにHPだけを完全に
; 独立した並列配列(ENEMY6_HP、スロットindexで対応)として、確実に
; 空きと確認済みのEXPLOSION_SAVED_CM3(F237h-F239h)直後の領域へ新設
; する(ENEMY6_HP_ADDRがIXから所属スロットのindexを逆算する)。
; (2026-09-13、"エネミー6 耐久値8"): 4→8。
ENEMY6_HP_INIT EQU 8
; Relocated off EF00h (originally right after the old ENEMY3_CENTERX_
; TABLE) to F158h, clear of that table's real footprint - the old table
; was addressed by (slot ptr - ENEMY3_POOL) + ENEMY3_CENTERX_TABLE, i.e.
; it spanned the SAME 704 bytes as ENEMY3_POOL itself (EE98h-F157h), not
; just the 64 bytes its data actually needed - EF00h sat inside that
; span, byte-aliasing this pool against whichever enemy3 wave/unit's own
; X-offset landed on the same byte. Growing this pool 4->32 slots would
; only have made that collision worse, so it moved out to genuinely free
; RAM instead of just resizing in place. (2026-09-13追記: the old
; ENEMY3_CENTERX_TABLE itself was later removed entirely - see
; ENEMY3_STRUCT's comment - but ENEMY6_POOL stays right here, no reason
; to move it back now that its old neighbor is gone.)
ENEMY6_POOL   EQU 0F158h        ; ENEMY6_SLOTS*ENEMY6_STRUCT = 128 bytes (F158h-F1D7h)
ENEMY6_SPAWN_COL    EQU 30      ; matches ENEMY_SPAWNX/ENEMY4_SPAWNX(240) = col30
; "エネミー6の速度を半分に"(2026-09-12): 1→2(2フレームに1回1列進む =
; 従来の半分の速度)。
; "エネミー6の速度を全速に戻して"(2026-09-13): 2→1(元の全速へ復帰)。
ENEMY6_STEP_FRAMES  EQU 1
ENEMY6_STEP_TIMER   EQU 0F1D8h  ; shared countdown to the next 1-column step
; enemy-fired bullet pool (new) - genuinely free RAM right after
; ENEMY6_STEP_TIMER (nothing else claims F1D9h+ up to STACKTOP=F380h).
EBULLET_POOL  EQU 0F1D9h        ; EBULLET_SLOTS*EBULLET_STRUCT = 24 bytes (F1D9h-F1F0h)
; --- IMPORTANT: 0F200h-0F201h is NOT free, despite being inside this  ---
; --- same "F1D9h+ up to STACKTOP" gap - tools/bankswitch_poc/         ---
; --- build_full_rom.py's Comb-build-only patch copies a 2-byte bank-  ---
; --- switch trampoline there at runtime (RAM, not part of this        ---
; --- tracked source, so it's invisible from in here). Everything      ---
; --- below was found silently corrupting it once it grew past F1F8h,  ---
; --- hanging the Comb build's boss->stage2 bank switch (verify_comb.py---
; --- caught it: stuck spinning, never reached stage2's own INIT) -    ---
; --- so new RAM here starts at F210h instead, well clear of it.       ---
BARRIER_HP    EQU 0F210h        ; player's barrier durability, 0-5; equipped from game
                                 ; start (INIT sets 5); accent overlay shows the barrier
                                 ; pattern while nonzero, reverts to the normal accent at 0.
                                 ; No damage/collision exists yet - nothing decrements this
                                 ; today (see PLAYER_ACCENT_PAT selection, INIT).
; (2026-09-13、"バリア耐久値9に"): 5→9。
BARRIER_HP_INIT EQU 9
GAME_OVER       EQU 0F211h  ; 0=playing, 1=game over. "現状ゲームオーバー
                             ; 処理は残しておくが ゲームは止めないでくれ" -
                             ; MAINLOOP does NOT freeze on this (tracked
                             ; only; see PLAYER_DAMAGE_CHECK/PTH_GAMEOVER).
BARRIER_IFRAMES EQU 0F212h  ; frames left of post-hit invulnerability, so one
                             ; overlapping frame with an enemy/bullet can't
                             ; drain more than 1 barrier HP before they
                             ; separate again - untuned placeholder value
BARRIER_IFRAMES_INIT EQU 60
PLAYER_ACCENT_COLOR EQU 0F213h ; this frame's accent color (SPR_WHITE/
                                 ; SPR_PURPLE, see the accent-select logic)
; 実機フィードバック対応でチャンネルC→チャンネルAへ移設(旧SND_C_DUTY_
; TIMER、アドレスは同じ0F214hのまま・シンボル名のみ実態に合わせて改名)。
SND_BARRIER_DUTY_TIMER EQU 0F214h ; 0=通常のchA再生(SOUND_SHOT/POD_HIT/
                                 ; POD_FIRE=SND_TONE_TIMER側は無関係);
                                 ; 非0なら8->1で減衰、デューティゲート -
                                 ; SOUND_BARRIER_HIT/SOUND_UPDATE参照
PLAYER_EXPL_SLOTS  EQU 4
PLAYER_EXPL_STRUCT EQU 5        ; +0 ACTIVE,+1 X,+2 Y,+3 TIMER,+4 SPRNUM
PLAYER_EXPL_POOL   EQU 0F215h   ; 4*5 = 20 bytes (F215h-F228h)
PLAYER_EXPL_TOTAL_TIMER EQU 0F229h  ; frames left in the whole ~2s burst
                                     ; sequence (0=inactive)
PLAYER_EXPL_SPAWN_TIMER EQU 0F22Ah  ; frames until the next single-instance
                                     ; spawn attempt
PLAYER_EXPL_LIFE EQU 20             ; frames each burst instance lives -
                                     ; untuned placeholder
PLAYER_EXPL_SPAWN_INTERVAL EQU 8    ; frames between spawn attempts -
                                     ; untuned placeholder (~15 bursts over
                                     ; the full ~2s sequence)
PLAYER_EXPL_TOTAL_LEN EQU 120       ; ~2 seconds at 60fps - untuned placeholder

; (2026-09-07、"ゲームオーバー表示は3秒表示してボタンが押されるか
; 10秒経過でタイトル画面に" - 前の"ゲームは止めないでくれ"方針からの
; 明示的な方針転換、ユーザー自身の新指示で上書き)。安全な未使用領域
; (0F232h-0F37Fh、SND_TONE_IS_SEの直後、上記コメントと同じ実測済みの
; 空き帯)に配置。
GAME_OVER_SEQ       EQU 0F232h  ; 0=未発生/1=MISSION FAILED表示中(3秒
                                 ; 待ち)/2=ボタンorタイムアウト待ち
                                 ; (最大10秒)/3=タイトルへ戻る準備完了
                                 ; (build_full_rom.pyのComb限定
                                 ; MAINLOOP_PATCHがこれを見てタイトルへの
                                 ; バンク切替へ進む、このファイル自身は
                                 ; バンク切替を一切行わない設計 - 既存の
                                 ; STAGE_CLEAR_ACTと同じ考え方)
GAME_OVER_START_TICK EQU 0F233h  ; 2 bytes: SC_VBLANK_COUNTのスナップショット
                                 ; (フェーズ切替のたびに再スナップショット、
                                 ; UPDATE_STAGE_CLEARと同じ実時間クロック
                                 ; 再利用パターン)
GAME_OVER_TEXT_TICKS    EQU 180  ; 3秒 @ 60Hz real vblank
GAME_OVER_TIMEOUT_TICKS EQU 600  ; 10秒 @ 60Hz real vblank
; (2026-09-07、"タイトル画面でAボタンスタートならゲームオーバーあり、
; Bボタンならゲームオーバー無しに"): tools/title_screen/title_test.asm
; のWAIT_FOR_STARTが同じ物理アドレスへ直接書き込む(値は必ず一致させる
; こと)。RAM(0xC000-0xFFFF)がバンク切替を跨いで物理的に共有される
; フラットな領域であることを利用した直接参照 - このファイル自身の
; INITでは絶対にクリアしないこと(Titleが設定した値を上書きしてしまう)。
GAMEOVER_ENABLED EQU 0F235h  ; 0=ゲームオーバー無効(バリア0後の被弾は
                              ; 無視、"今は0になっても死なない"の従来
                              ; 挙動)/1=ゲームオーバー有効(通常)

; (2026-09-07、"ステージ1の自機爆発演出追加 操作無効の上爆発しながら
; 右斜め下に落下しMission Failed表示に"): PTH_GAMEOVERが即座にMISSION
; FAILEDテキストを出していた従来の挙動を、まず自機を操作不能にして
; 右斜め下へ落下させながら爆発(既存のPLAYER_EXPL_POOLバーストをその
; まま流用 - PEUA_TRY_SPAWNは毎回PLAYERX/PLAYERYを直接読むため、
; 落下で動く自機の位置に自動的に追従する)させ、この演出が終わって
; 初めてMISSION FAILEDを表示する2段階へ変更。GAMEOVER_ENABLEDの
; すぐ後、同じ実測済みの空き帯に配置。
; (2026-09-07追記、"斜め下に落下したらそのまま画面外に消えるように
; 変更"): 固定フレーム数(旧PLAYER_DEATH_FALL_TIMER/DURATION、45フレーム
; で強制的に非表示コーナーへテレポートしていた)を廃止し、PLAYERY自身が
; 実際に画面外(199 = ENEMY_HIDE_Yの逆算値、このファイル全体で確立済みの
; 非表示コーナー)へ達するまで等速で落下し続ける方式へ変更。開始位置が
; 画面上のどこであっても、実際に画面外へ落ちきった瞬間が完了条件になる
; (近ければ短く・遠ければ長く、時間ではなく距離で終了が決まる)。
PLAYER_DEATH_FALL_ACT   EQU 0F236h  ; 0=非活性/1=落下中(PLAYERYが199に
                                     ; 達した瞬間に自動的に0へ戻る)
; (2026-09-07、実機フィードバック対応"墜落速度が速いんで半分の速度に"):
; 2→1へ半減。
PLAYER_DEATH_FALL_SPEED    EQU 1    ; px/frame、斜め45度(X,Yとも同値) -
                                     ; PLAYER_RETREAT_SPEEDと同じ考え方

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

    ; --- BGM (round40) - 実機フィードバック対応("WebMSXでフリーズや
    ; --- リセットがかかる これは実機も同様"、続けて"実機、WebMSX、
    ; --- BlueMSX全てでタイトルでボタン押下後フリーズ"): このDIの直後、
    ; --- INITの中で一番最初に呼ぶ。**一度は「CALL INIT32の直後」へ
    ; --- 動かして試したが、それは誤診断だった**: `tools/z80emu.py`の
    ; --- `bios_call()`はINIT32(target==0x006F)を単純に"return True"
    ; --- する完全なno-opとして扱っており(WRTVDP等も同様)、実際の
    ; --- BIOSがSCREEN1初期化(INIGRP/CHGMOD相当)の中で内部的に行う
    ; --- vblank待ち(実機のBIOSがEI+HALTでVDPの垂直帰線を待つ、この
    ; --- 種の画面モード変更では一般的な実装)を一切シミュレートしない -
    ; --- つまりこのファイルのテスト環境(z80emu.py・それを使う
    ; --- verify_comb.py)は、INIT32の前後どちらにCALL INIT_BGMを
    ; --- 置いても「INIT32自体が原因で壊れるかどうか」を検証できて
    ; --- いなかった。当時verify_comb.pyがFAILしたのは別の原因
    ; --- (round40より前からの遺物1行がH.TIMIフックを踏み潰していた -
    ; --- 該当箇所は完全に削除済み、下記HANDOFF.md参照)で、INIT32の
    ; --- せいではなかったと判明。むしろ逆に、CALL INIT32を実機で
    ; --- 呼んだ時点でTitleの自身が設置した古いH.TIMIフック(window A
    ; --- の中身は既にStage1のコードに切り替わっている)がまだ生きた
    ; --- ままだと、INIT32内部のvblank待ちで割り込みが1回でも発火した
    ; --- 瞬間に暴走する - これが実機・WebMSX・BlueMSXで再現していた
    ; --- 真因である可能性が高いと考え直し、CALL INIT_BGM(BGM_B/C_PTR
    ; --- 等のRAM変数初期化+H.TIMIフックの上書きのみで、VDP/VRAM初期化
    ; --- 前でも安全に呼べる)をCALL INIT32より**前**、このDIの直後
    ; --- という最も早い位置へ戻した。詳細・検証状況はHANDOFF.md参照
    ; --- (この時点でまだ実機・WebMSX・BlueMSXでの再検証待ち)。
    CALL INIT_BGM

    CALL INIT32

    ; (2026-09-06、実機フィードバック対応 "ただMission表示するだけでよ
    ; ステージとMission表示は別のフェーズだろうが なんでMission表示して
    ; 同時にステージスタートさせてんだ"): 以前はこのMISSION1ブロックが
    ; INITの中盤(背景/スプライトパターンのVRAM転送・スプライト属性
    ; クリア・敵プール初期化等、"本編のステージ開始処理"の真っ只中)に
    ; 挟まっており、Mission1画面を表示している間もステージ側の初期化が
    ; 半分終わった状態のままという、フェーズが全く分離されていない
    ; 設計になっていた。SCREEN1モード確立(CALL INIT32)に必要な最小限
    ; (Mission1文字のフォントパターン+色だけ)を読み込んだ直後、ここで
    ; 独立した完結フェーズとしてMission1を表示・待機・消去し、それが
    ; 完全に終わってから初めて"ステージ開始処理"(この直後のborder色
    ; 設定〜PSG R7ミキサー設定〜UNMUTE_BGMまでの一連)を開始する。
    ; (2026-09-07、"Mission表示のフォントは添付ファイルで"): MISSION_FONT_
    ; PATTERNSをユーザー添付Font_24x24_1.json(CYBER_SUZUKA、M/I/S/O/N/
    ; 1/2の8x8グリフ)へ差し替え、8グリフ(M,I,S,O,N,space,1,2)構成に
    ; 拡張(旧6グリフ+DIGIT_BASE+1/+2への依存を解消)。同じcode64-71の
    ; group8内に収まるため追加コードは不要。
    ; round145(ROM予算確保): MISSION_FONT_PATTERNS+GAMEOVER_FONT_PATTERNS
    ; はVRAM上でcodes64-79の連続128byteなので1回のLDIRVMへ統合した上で
    ; 自前RLEで圧縮(128byte->114byte、データ自体もSTAGE1_MISSION_
    ; GAMEOVER_FONTとしてbank6へオフロード済み)。GAME OVER表示用
    ; (G,A,E,V,R、code72-76、group9内、tools/pixel_font_8x8.pyの新規
    ; 描き起こし文字)もここで一緒にロードする - GAME OVERはステージ
    ; 本編プレイ中いつでも発生しうるため、本編初期化が終わる前のこの
    ; 早い段階で必ず用意しておく必要がある。
    LD DE,MISSION_FONT_BASE*8
    LD A,E : OUT (99h),A
    LD A,D : OR 40h : OUT (99h),A
    LD HL,STAGE1_MISSION_GAMEOVER_FONT
    LD DE,STAGE1_MISSION_GAMEOVER_FONT_SEGMENTS
    CALL DECOMPRESS_RLE_TO_VRAM
    LD HL,MISSION_FONT_COLOR : LD DE,2008h : LD BC,1 : CALL LDIRVM
    LD HL,GAMEOVER_FONT_COLOR : LD DE,2009h : LD BC,1 : CALL LDIRVM
    LD HL,MISSION1_MSG
    CALL DRAW_MISSION_SCREEN
    DI    ; DRAW_MISSION_SCREEN's own internal EI (harmless - HTIMI_HOOK is
          ; already valid but BGM_MUTED=1 keeps it silent - but re-DI here
          ; keeps INIT silent/deterministic through the delay below)
    CALL MISSION_DELAY_3SEC
    CALL ERASE_MISSION_TEXT

    ; --- border/backdrop color (VDP R7, low nibble) = black. This is ---
    ; --- the true overscan border, separate from the in-screen sky   ---
    ; --- (BLANKCODE's color group), which stays blue.                ---
    LD B,01h : LD C,7 : CALL WRTVDP

    ; (2026-09-19) PATTERNSはRLE圧縮済み(PATTERNS自身のコメント参照)。
    XOR A : OUT (99h),A : LD A,40h : OUT (99h),A
    LD HL,PATTERNS_A : LD DE,PATTERNS_A_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM
    LD HL,PATTERNS_B : LD DE,PATTERNS_B_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM   ; 続き(同じVRAMアドレスから連続)
    LD HL,COLORDATA : LD DE,2000h : LD BC,COLOR_LEN : CALL LDIRVM
    ; COLORDATAはgroup8(codes64-71、2008h)も含む32グループ全体を上書き
    ; するため、Mission1表示のために上で先に書いたMISSION_FONT_COLOR
    ; (白文字/黒背景)がここで消されてしまう。MISSION2(ステージクリア
    ; 演出)はゲーム本編の実行中に同じフォント・同じ色を再利用するため、
    ; ここで再度書き直して確定させておく(Mission1自身は既に表示・消去
    ; 済みなのでこの再書き込みの影響を受けない)。
    LD HL,MISSION_FONT_COLOR : LD DE,2008h : LD BC,1 : CALL LDIRVM
    ; GAME OVER用フォント色(group9)も同じ理由で再書き直しが必要。
    LD HL,GAMEOVER_FONT_COLOR : LD DE,2009h : LD BC,1 : CALL LDIRVM
    LD HL,BLANK_PATTERN : LD DE,BLANKCODE*8 : LD BC,8 : CALL LDIRVM   ; BLANKCODE's glyph was never written before - defaulted to leftover VRAM garbage
    ; DIGIT_PATTERNS(digit glyphs 0-9、スコア表示等が使う本来の用途)は
    ; ここが本来のロード位置(round56/57時点ではMission1表示の直前へ
    ; 一時的に移設されていたが、今回MISSION1_MSG/MISSION2_MSGが添付
    ; フォントの'1'/'2'グリフ[MISSION_FONT_BASE+6/+7]を使うようになり
    ; digitグリフへの依存が解消されたため、本来のこの位置へ復元)。
    LD HL,DIGIT_PATTERNS : LD DE,DIGIT_BASE*8 : LD BC,80 : CALL LDIRVM

    XOR A
    LD (TICK),A : LD (PXCHAR_G8),A : LD (PXCHAR_G4),A
    LD (PXCHAR_G2),A : LD (PXCHAR_G1),A

    ; Seed the 4 remaining IDCACHEn buffers (row1/IDCACHE1 no longer
    ; used - TIER2_DIAMOND's own row was dropped, see GROUND_ROW0; row4/
    ; IDCACHE4, TIER5_BACKSLASH's own buffer, was removed entirely
    ; along with ROWDATA4 when that row was dropped too) for PXCHAR=0
    ; (the gates in MAINLOOP that call REFRESH_IDCACHE_33 only fire
    ; once their group's PXCHAR actually advances - every 8/16/32/64
    ; frames - so without this, frame 1 would render from stale/zeroed
    ; cache RAM).
    ; round136: ROWDATA0/2/3/5はもうROMリテラルではなくRAMバッファ
    ; (上のEQUコメント参照) - IDCACHEへ読ませる前に一度だけ内容を
    ; 生成しておく。
    LD HL,ROWDATA0 : LD (HL),4Dh : LD DE,ROWDATA0+1 : LD BC,127 : LDIR  ; 'M'
    LD HL,ROWDATA2 : LD (HL),44h : LD DE,ROWDATA2+1 : LD BC,127 : LDIR  ; 'D'
    LD HL,ROWDATA3 : LD (HL),53h : LD DE,ROWDATA3+1 : LD BC,127 : LDIR  ; 'S'
    LD HL,ROWDATA5 : LD B,64
RD5_FILL:
    LD (HL),41h : INC HL   ; 'A'
    LD (HL),42h : INC HL   ; 'B'
    DJNZ RD5_FILL

    LD HL,ROWDATA0 : LD IX,IDCACHE0 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA2 : LD IX,IDCACHE2 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA3 : LD IX,IDCACHE3 : CALL REFRESH_IDCACHE_33
    LD HL,ROWDATA5 : LD IX,IDCACHE5 : CALL REFRESH_IDCACHE_33

    LD HL,PREVBUF : LD (HL),0FFh
    LD DE,PREVBUF+1 : LD BC,127 : LDIR

    ; Clear the background rows (screen rows 0-19, 20*32=640 bytes,
    ; i.e. everything above the 4-row scroller which now sits at
    ; screen rows 20-23) to BLANKCODE, whose color group is set to
    ; fg=bg=blue in COLORDATA so it reads as solid blue regardless
    ; of pattern content.
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    LD A,58h : OUT (99h),A
    NOP
    NOP
    LD A,BLANKCODE
    LD B,00h
    EI
FILLBG_1:
    DI
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ FILLBG_1
    LD B,00h
FILLBG_2:
    DI
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ FILLBG_2
    LD B,128
FILLBG_3:
    DI
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ FILLBG_3

    ; "スコアの行をブラックで埋めて"(2026-09-13) - row0 (the score
    ; display's own row) just got painted BLANKCODE (blue) above like
    ; every other sky row; re-paint just this one row's 32 cells with
    ; MISSION_FONT_BASE+5 (the SPACE/all-blank glyph on group8, already
    ; loaded+colored white-fg/black-bg a few lines up - the same code
    ; DRAW_MISSION_SCREEN itself uses "黒埋め用") so it reads solid
    ; black instead - SCORE_DISPLAY's own white-on-black digit cells
    ; (cols0-7) then draw on top of this, and the rest of the row
    ; (cols8-31, including where the now-removed GAME_TICK_DISPLAY used
    ; to sit at cols29-31) stays a plain black backdrop.
    DI
    LD A,00h : OUT (99h),A
    NOP
    NOP
    LD A,58h : OUT (99h),A      ; write address = 1800h (name table row0)
    NOP
    NOP
    LD A,MISSION_FONT_BASE+5
    LD B,32
    EI
FILLBG_ROW0_BLACK:
    DI
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ FILLBG_ROW0_BLACK

    ; --- sprite pattern generator table (VRAM 3800h): ship/accent are ---
    ; --- static 16x16 patterns (loaded further down, alongside their  ---
    ; --- UP/DOWN animation frames - see SHIP_MID_PATTERN/ACCENT_MID_  ---
    ; --- PATTERN); the 3 enemy-formation units' patterns are          ---
    ; --- generated at runtime (see REDRAW_UNIT_PATTERN / ENEMY_RESPAWN) ---
    ; --- since each asterisk quadrant can be independently shot out.   ---

    ; --- shot character patterns (8 vertical phases, blue only), VRAM 0000h+56*8 ---
    ; 1C0h = BULLET_PAT_BLUE(56)*8。(2026-09-19) RLE圧縮済み。
    LD A,0C0h : OUT (99h),A : LD A,41h : OUT (99h),A
    LD HL,BULLET_PATTERNS : LD DE,BULLET_PATTERNS_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM

    ; --- destroy-animation character patterns (round69 follow-up, 2 ---
    ; --- tiles only - see EXP_CODE_THIN/THICK's own comment), VRAM  ---
    ; --- 3C0h = EXP_CODE_THIN(120)*8 ---
    LD HL,EXPLOSION_TILES : LD DE,EXP_CODE_THIN*8 : LD BC,16 : CALL LDIRVM

    ; --- temp assembly-sprite patterns, VRAM SPRPAT+C0h = PAT_TEMP_TOP(24)*8 ---
    ; (2026-09-19) RLE圧縮済み(TEMP_SPRITE_PATTERNS自身のコメント参照)。
    LD A,0C0h : OUT (99h),A : LD A,78h : OUT (99h),A
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,TEMP_SPRITE_PATTERNS_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM
    ; --- E2A_TT/E2A_TB (pattern44-51) and E2B_TT/E2B_TB (pattern64-71) ---
    ; --- never had this loaded before - the fly-in phase (states 0-5, ---
    ; --- before the formation assembles) used these pattern codes but ---
    ; --- they were blank VRAM, so nothing was visible until merge.    ---
    LD A,60h : OUT (99h),A : LD A,79h : OUT (99h),A
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,TEMP_SPRITE_PATTERNS_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM
    XOR A : OUT (99h),A : LD A,7Ah : OUT (99h),A
    LD HL,TEMP_SPRITE_PATTERNS : LD DE,TEMP_SPRITE_PATTERNS_SEGMENTS : CALL DECOMPRESS_RLE_TO_VRAM

    ; --- enemy3 pulse-animation patterns, codes 152/160/168 ---
    LD HL,ENEMY3_PATTERN1 : LD DE,ENEMY3_CODE1*8 : LD BC,8 : CALL LDIRVM
    LD HL,ENEMY3_PATTERN2 : LD DE,ENEMY3_CODE2*8 : LD BC,8 : CALL LDIRVM
    LD HL,ENEMY3_PATTERN3 : LD DE,ENEMY3_CODE3*8 : LD BC,8 : CALL LDIRVM

    ; --- enemy6's 4 quadrant glyphs, at ENEMY3_CODE1's group's spare  ---
    ; --- codes 153-156 (152 itself untouched) - see the pattern       ---
    ; --- data's own comment. No longer also drawn at a fixed test     ---
    ; --- cell here - SPAWN_E6/ENEMY6_DRAW place and move it for real  ---
    ; --- for real now (see the ENEMY6_* routines, near                ---
    ; --- CHECK_BULLET_VS_ENEMY3).                                     ---
    LD HL,NEWENEMY_PATTERN_TL : LD DE,NEWENEMY_CODE_TL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN_TR : LD DE,NEWENEMY_CODE_TR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN_BL : LD DE,NEWENEMY_CODE_BL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN_BR : LD DE,NEWENEMY_CODE_BR*8 : LD BC,8 : CALL LDIRVM
    ; --- enemy6's 90/180/270-degree spin-animation quadrants (see  ---
    ; --- their own comment, near NEWENEMY_PATTERN90_TL)             ---
    LD HL,NEWENEMY_PATTERN90_TL : LD DE,NEWENEMY_CODE90_TL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN90_TR : LD DE,NEWENEMY_CODE90_TR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN90_BL : LD DE,NEWENEMY_CODE90_BL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN90_BR : LD DE,NEWENEMY_CODE90_BR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN180_TL : LD DE,NEWENEMY_CODE180_TL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN180_TR : LD DE,NEWENEMY_CODE180_TR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN180_BL : LD DE,NEWENEMY_CODE180_BL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN180_BR : LD DE,NEWENEMY_CODE180_BR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN270_TL : LD DE,NEWENEMY_CODE270_TL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN270_TR : LD DE,NEWENEMY_CODE270_TR*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN270_BL : LD DE,NEWENEMY_CODE270_BL*8 : LD BC,8 : CALL LDIRVM
    LD HL,NEWENEMY_PATTERN270_BR : LD DE,NEWENEMY_CODE270_BR*8 : LD BC,8 : CALL LDIRVM

    ; --- Ebuz(2026-09-14組み込み)本体4タイル+弾2タイル ---
    ; (round135follow-up8、"Ebuz1の左から1つ目のセルは背景ライトブルーで
    ; 文字色グレー 2セル目は背景ブラック文字色レッド 3セル目、背景
    ; ブラック文字色グレー 4セル目、背景グレー文字色ブラック"): A/B/C/D
    ; を4色ばらばらにする指示を受け、それまで4タイル共有だったgroup16を
    ; 撤去し、A/B/C/Dを別々のgroup(11-14)へ1コードずつ分離
    ; (SCREEN1のカラーテーブルは8連続コード単位で色1個共有というハード
    ; 制約があるため、コードごとに違う色を持たせるには別グループに
    ; 置くしかない)。group11-14は旧ANIM1_x flicker(round69で「元の
    ; 爆発パターンは削除して空きに」と廃止済み)専用だった空きグループ、
    ; group16-17(旧ANIM2_white/green専用)は本体色の一括共有だった名残で
    ; 本体側は不要になったが弾(group17)は引き続き使用
    ; (COLORDATA自身のコメント"groups 6-31...unused by this scroller"
    ; および全LDIRVM呼び出し元の横断チェックで確認済み)。EBUZ_CODE_A-Dは
    ; どこにも連続前提の範囲チェックが無いことも確認済み(単純なVRAM
    ; タイルコードとしてDBテーブル・LDIRVM元アドレス計算にのみ使用)。
    LD HL,EBUZ_TILE_A : LD DE,EBUZ_CODE_A*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_B : LD DE,EBUZ_CODE_B*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_C : LD DE,EBUZ_CODE_C*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_D : LD DE,EBUZ_CODE_D*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_BULLET_L_TILE : LD DE,EBUZ_BULLET_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_BULLET_R_TILE : LD DE,EBUZ_BULLET_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_COLOR_A : LD DE,200Bh : LD BC,1 : CALL LDIRVM           ; 200Bh=COLTBL+group11(88/8)
    LD HL,EBUZ_COLOR_B : LD DE,200Ch : LD BC,1 : CALL LDIRVM           ; 200Ch=COLTBL+group12(96/8)
    LD HL,EBUZ_COLOR_C : LD DE,200Dh : LD BC,1 : CALL LDIRVM           ; 200Dh=COLTBL+group13(104/8)
    LD HL,EBUZ_COLOR_D : LD DE,200Eh : LD BC,1 : CALL LDIRVM           ; 200Eh=COLTBL+group14(112/8)
    LD HL,EBUZ_BULLET_COLOR_BYTE : LD DE,2011h : LD BC,1 : CALL LDIRVM ; 2011h=COLTBL+group17(136/8)

    ; Ebuz Mk2専用: レーザーのみ新規タイル2枚+専用カラー1組(本体・弾は
    ; 上のEbuz本体タイルをそのまま流用、新規ロード不要 - "キャラは
    ; レーザー以外流用で")。group18(144-151)は実プレイ長時間監視で
    ; 空きと確認済み(EBUZ2_LASER_L/R_CODE自身のコメント参照)。
    LD HL,EBUZ2_LASER_L_TILE : LD DE,EBUZ2_LASER_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_LASER_R_TILE : LD DE,EBUZ2_LASER_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_LASER_COLOR_BYTE : LD DE,2012h : LD BC,1 : CALL LDIRVM ; 2012h=COLTBL+group18(144/8)
    XOR A : LD (EBUZ2_ACT),A   ; RAM初期化漏れ防止(follow-up#14の教訓)
    LD (EBUZ2_DEFEATED),A

    ; (DIGIT_PATTERNS[digit glyphs 0-9]/MISSION_FONT_PATTERNS・COLORの
    ; 読み込みはここではなく、このINITの冒頭・CALL INIT32の直後、
    ; Mission1表示の直前へ移設済み - 上記参照)

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
    LD HL,SKY_FAST_H : LD (SKY_VEC_H),HL
    LD HL,SKY_FAST_E : LD (SKY_VEC_E),HL
    LD HL,0 : LD (GAME_TICK),HL
    LD HL,0 : LD (SCORE),HL
    XOR A : LD (SCORE+2),A
    CALL SCORE_DISPLAY

    ; --- enemy3 pool: idle at boot - waves start as the tick schedule ---
    ; --- reaches each trigger (see SPAWN_SCHEDULE_CHECK)               ---
    XOR A : LD (ENEMY3_SPAWN_COUNT),A
    XOR A : LD (ENEMY3_ACTIVE_COUNT),A
    ; Full 704-byte clear (all 64 slots, not just each slot's ACTIVE     ---
    ; byte) - ENEMY3_UPDATE_SLOT's inactive-slot safety net (see its own
    ; comment) reads ROW/COL (bytes 4/5) even for never-yet-spawned
    ; slots, and an uninitialized (0,0) would blank row0/col0 - the
    ; score display's first digit - every frame until the first real spawn.
    LD HL,ENEMY3_POOL : LD (HL),0
    LD DE,ENEMY3_POOL+1 : LD BC,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS*ENEMY3_STRUCT-1 : LDIR
    ; ROW=1 (sky, matches ENEMY3_SPAWN_Y>>3) for every slot - never HUD row0
    LD HL,ENEMY3_POOL+4 : LD B,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS
E3INIT_ROW_LOOP:
    LD (HL),1
    LD DE,ENEMY3_STRUCT
    ADD HL,DE
    DJNZ E3INIT_ROW_LOOP
    ; CENTERX(byte12/offset+11) is part of this same struct now (folded
    ; in 2026-09-13, see ENEMY3_STRUCT's comment) - the full-pool clear
    ; above already zeroed it, no separate clear needed here anymore.
    ; All wave slots idle (ACTIVE=0, byte 0 of each 4-byte slot) - see
    ; ENEMY3_WAVE_POOL.
    LD HL,ENEMY3_WAVE_POOL : LD (HL),0
    LD DE,ENEMY3_WAVE_POOL+1 : LD BC,ENEMY3_WAVE_SLOTS*4-1 : LDIR

    ; --- enemy6 pool: idle at boot - spawned from the schedule (SPAWN_E6) ---
    XOR A : LD (ENEMY6_STEP_TIMER),A
    LD HL,ENEMY6_POOL : LD (HL),0
    LD DE,ENEMY6_POOL+1 : LD BC,ENEMY6_SLOTS*ENEMY6_STRUCT-1 : LDIR
    ; ENEMY6_HP(独立配列、詳細はENEMY6_STRUCT自身のコメント参照)も
    ; 同様にゼロクリア - SPAWN_E6が実際にスロットを使うたびに
    ; ENEMY6_HP_INITで上書きするので初期値自体は0で構わない。
    LD HL,ENEMY6_HP : LD (HL),0
    LD DE,ENEMY6_HP+1 : LD BC,ENEMY6_SLOTS-1 : LDIR

    ; --- Ebuz(2026-09-14 follow-up: マルチインスタンス化[最大2体同時 ---
    ; 生存])のワークエリアを明示的にゼロ/番兵で初期化(RAM初期化漏れ
    ; 防止 - このプロジェクトが何度も踏んできた教訓、詳細はEBUZ_SLOT0
    ; 等自身のコメント参照)。EBUZ_SPAWN_STAGE=0(未スポーン)なので、
    ; 実際にチェーンが開始する(EBUZ_SPAWN_CHAIN_START)までこの
    ; サブシステムは完全に無害。
    LD HL,EBUZ_CUR_ROW_ADDR : LD (HL),0
    LD DE,EBUZ_CUR_ROW_ADDR+1 : LD BC,41 : LDIR
    LD HL,EBUZ_SLOT0+0 : LD (HL),0
    LD DE,EBUZ_SLOT0+1 : LD BC,16 : LDIR
    LD HL,EBUZ_SLOT0+EBUZ_OFS_TOP_COLS : LD (HL),EBUZ_SLOT_EMPTY
    LD DE,EBUZ_SLOT0+EBUZ_OFS_TOP_COLS+1 : LD BC,15 : LDIR
    LD HL,EBUZ_SLOT0+EBUZ_OFS_TOP_NEXT : LD (HL),0
    LD DE,EBUZ_SLOT0+EBUZ_OFS_TOP_NEXT+1 : LD BC,2 : LDIR
    LD HL,EBUZ_SLOT1+0 : LD (HL),0
    LD DE,EBUZ_SLOT1+1 : LD BC,16 : LDIR
    LD HL,EBUZ_SLOT1+EBUZ_OFS_TOP_COLS : LD (HL),EBUZ_SLOT_EMPTY
    LD DE,EBUZ_SLOT1+EBUZ_OFS_TOP_COLS+1 : LD BC,15 : LDIR
    LD HL,EBUZ_SLOT1+EBUZ_OFS_TOP_NEXT : LD (HL),0
    LD DE,EBUZ_SLOT1+EBUZ_OFS_TOP_NEXT+1 : LD BC,2 : LDIR

    ; --- flowing background clouds: idle at boot, each with its own ---
    ; --- random initial wait before first appearing (see CLOUD_UPDATE_ALL) ---
    XOR A : LD (CLOUDW_ACTIVE),A
    CALL CLOUD_RANDOM_WAIT : LD (CLOUDW_WAIT),A
    XOR A : LD (CLOUDN_ACTIVE),A
    CALL CLOUD_RANDOM_WAIT : LD (CLOUDN_WAIT),A

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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD B,32
    EI
INIT_SPRATR_CLR:
    DI
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ INIT_SPRATR_CLR

    ; (Mission1表示・待機・消去は、このINITの冒頭・CALL INIT32の直後へ
    ; 移設済み - "ステージとMission表示は別のフェーズだろうが なんで
    ; Mission表示して同時にステージスタートさせてんだ"という実機
    ; フィードバック対応、詳細は上記参照。以前はこの位置[背景/スプライト
    ; パターンVRAM転送・このスプライト属性クリアループ等、ステージ
    ; 本編の初期化処理の真っ只中]にあったため、Mission1表示中も
    ; ステージ側の初期化が半分終わった状態のままだった)。

    ; --- player initial state ---
    ; (2026-09-21、"急に始まるのでなく飛び込んでくる演出"): 通常の
    ; PLAYER_INITX/Y・PAT_SHIP/PAT_ACCENTでは始めず、画面左上(0,0)・
    ; 飛び込み専用パターンでスタートし、SHIP_ENTRY_ACT=1を立てる。
    ; 到達後は下記の毎フレーム処理(PFA_NO_DEATH_FALLより手前)が自動で
    ; PLAYER_INITY相当・PLAYER_RETREAT_TARGET_X(32)・通常パターンへ
    ; 切り替える。
    XOR A : LD (PLAYERX),A : LD (PLAYERY),A
    LD A,PAT_SHIP_ENTRY_BODY : LD (PLAYER_SHIP_PAT),A
    LD A,PAT_SHIP_ENTRY_ACCENT : LD (PLAYER_ACCENT_PAT),A
    LD A,1 : LD (SHIP_ENTRY_ACT),A
    LD A,BARRIER_HP_INIT : LD (BARRIER_HP),A   ; barrier equipped from game start
    XOR A : LD (GAME_OVER),A : LD (BARRIER_IFRAMES),A
    LD (SND_BARRIER_DUTY_TIMER),A
    ; GAME_OVER_SEQ/GAME_OVER_START_TICK(round36-14 follow-up#14の教訓
    ; 通り、新規RAMは明示的にゼロクリア - 実機の電源投入直後は不定値)。
    ; GAMEOVER_ENABLEDは意図的にここでクリアしない(Titleが設定した
    ; 値をそのまま保持する必要があるため、上記EQU自身のコメント参照)。
    LD (GAME_OVER_SEQ),A
    LD (GAME_OVER_START_TICK),A : LD (GAME_OVER_START_TICK+1),A
    LD (PLAYER_DEATH_FALL_ACT),A
    LD HL,PLAYER_EXPL_POOL : LD (HL),A
    LD DE,PLAYER_EXPL_POOL+1 : LD BC,21 : LDIR   ; zeroes the pool +
                                                   ; PLAYER_EXPL_TOTAL_TIMER/
                                                   ; SPAWN_TIMER (all 3 contiguous)
    XOR A
    LD HL,BULLET_POOL : LD B,BULLET_SLOTS*6
INIT_BULLET_CLR:
    LD (HL),A
    INC HL
    DJNZ INIT_BULLET_CLR
    LD (JOY_TRIGB_PREV),A
    ; (2026-09-23、監査で発見): 飛び込み演出中は入力読み取りを丸ごと飛ばすため
    ; JOY_TRIG/FIREB_EDGE/JOY_STICKは前回プレイ(ゲームオーバー後の再スタート)や
    ; 電源投入時の不定値のまま残り、「押されている」値だと演出中に勝手に撃っていた。
    LD (JOY_TRIG),A : LD (FIREB_EDGE),A : LD (JOY_STICK),A
    ; --- clear the sprite-number free-list (all 32 bytes; 0-1 are  ---
    ; --- never scanned by the allocator, so they don't need to be  ---
    ; --- marked used separately) ---
    XOR A
    LD HL,SPRITE_USED : LD (HL),A
    LD DE,SPRITE_USED+1 : LD BC,31 : LDIR
    LD A,1 : LD (NEXT_SPRITE_NUM),A

    ; --- 実機フィードバック対応(2026-09-07、"スケジュール上でみれば
    ; --- 235から304までエネミー4までの敵がリスタートでは出ない 普通に
    ; --- 考えてリスタートでの初期化ミスだろ"): SIMPLE_PATTERN_USED
    ; --- (BEHAVIOR_SIMPLE_DRIFT_DODGE/Enemy5用の6枠だけの共有VRAM
    ; --- パターンプール、ALLOC_PATTERN_SLOT/FREE_PATTERN_SLOTが管理)
    ; --- が、SPRITE_USEDと同じ"free-list"方式でありながらINITで一度も
    ; --- 明示的にクリアされていなかった実バグ。ゲームオーバーが
    ; --- Enemy1/Enemy5/Enemy4B(TYPE_ENEMY1_LOOK)のいずれかが画面上に
    ; --- 残っている瞬間に発生すると、その枠を解放するFREE_PATTERN_SLOT
    ; --- (通常は画面外退出・撃破時に呼ばれる)が一度も呼ばれないまま
    ; --- ゲームが停止するため、SIMPLE_PATTERN_USEDの対応バイトが1
    ; --- (使用中)のまま残留する - RAMは電源投入直後こそ不定値だが、
    ; --- 一度でも完走した後は必ずこの残留が起こりうる。次の周回の
    ; --- INITはこれを一度もクリアしないため、6枠のうち残留した分だけ
    ; --- プールが目減りしたまま再スタートし、tick235-304に密集する
    ; --- SPAWN_E4B(TYPE_ENEMY1_LOOK)のバーストがALLOC_PATTERN_SLOT
    ; --- 失敗で次々ドロップされていた(ENEMY4_CLAIM_ANY/E4CA_SB_GOTPAT
    ; --- のコメント通り、失敗時はスケジュール自体は正常に進みつつ
    ; --- スポーンだけ静かにdropされる設計のため、SPAWN_NEXT_INDEXの
    ; --- 進行だけを見ても異常が見えなかった)。SPRITE_USEDと同型の
    ; --- 明示的ゼロクリアを追加して解消。
    XOR A
    LD HL,SIMPLE_PATTERN_USED : LD (HL),A
    LD DE,SIMPLE_PATTERN_USED+1 : LD BC,SIMPLE_PATTERN_SLOTS-1 : LDIR

    ; --- fully clear E2A/E2B's entire state blocks (98 bytes each),  ---
    ; --- not just ACTIVE. CHECK_BULLET_VS_FORMATION_A/B gates on     ---
    ; --- U0/1/2_STATE (not ACTIVE), so any stale non-zero STATE left ---
    ; --- over from a previous run (RAM isn't hardware-cleared by a   ---
    ; --- reset) would keep reacting to bullets at its old stale X/Y  ---
    ; --- using its old stale SPRNUM - exactly the leftover-sprite    ---
    ; --- garbage seen after a warm/hot reset.                        ---
    XOR A
    LD HL,E2A_SEQ_STATE : LD (HL),A
    LD DE,E2A_SEQ_STATE+1 : LD BC,99 : LDIR   ; +2 to also clear E2A_ANIM_SEQ/TIMER
    LD HL,E2B_SEQ_STATE : LD (HL),A
    LD DE,E2B_SEQ_STATE+1 : LD BC,99 : LDIR   ; +2 to also clear E2B_ANIM_SEQ/TIMER
    CALL ENEMY_POOL_INIT
    CALL EBULLET_POOL_INIT
    LD HL,E1_FIRE_COUNTDOWN : CALL RANDOM_3_5 : LD (HL),A
    LD HL,E5_FIRE_COUNTDOWN : CALL RANDOM_3_5 : LD (HL),A
    LD HL,E2_FIRE_COUNTDOWN : CALL RANDOM_3_5 : LD (HL),A
    XOR A : LD (E4_FIRED_THIS_FRAME),A
    LD HL,ENEMY4_PATTERN : LD DE,PAT_ENEMY4*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ENEMY4_PATTERN_2 : LD DE,PAT_ENEMY4_2*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,EBULLET_PATTERN : LD DE,PAT_EBULLET*8+SPRPAT : LD BC,32 : CALL LDIRVM
    CALL LOAD_SHIP_ENTRY_PATTERNS
    LD HL,SHIP_MID_PATTERN : LD DE,PAT_SHIP*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,SHIP_UP_PATTERN : LD DE,PAT_SHIP_UP*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,SHIP_DOWN_PATTERN : LD DE,PAT_SHIP_DOWN*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_MID_PATTERN : LD DE,PAT_ACCENT*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_DOWN_PATTERN : LD DE,PAT_ACCENT_DOWN*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_MID_BARRIER_PATTERN : LD DE,PAT_ACCENT_BARRIER*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_DOWN_BARRIER_PATTERN : LD DE,PAT_ACCENT_DOWN_BARRIER*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,PLAYER_EXPL_PATTERN : LD DE,PAT_PLAYER_EXPLOSION*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,E1A_PATTERN : LD DE,PAT_ENEMY1*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,PARTICLE_PATTERN : LD DE,PAT_PARTICLE*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD A,1 : LD (ENEMY1_LOOK_FLAGS),A : LD (ENEMY1_LOOK_FLAGS+1),A
    XOR A : LD (ENEMY5_ANIM_SEQ),A : LD (ENEMY5_ANIM_TIMER),A
    LD HL,ASTERISK_PATTERN : LD (REDRAW_SRC_PATTERN),HL
    LD HL,PAT_ENEMY1_LOOK*8+SPRPAT : LD DE,ENEMY1_LOOK_FLAGS : LD IX,ENEMY1_LOOK_FLAGS+1
    CALL REDRAW_UNIT_PATTERN
    XOR A : LD (BOSS_EXPL_ACTIVE),A
    XOR A : LD (BOSS_EXPL_STARTED),A
    XOR A : LD (PLAYER_FLYAWAY),A
    XOR A : LD (PLAYER_RETREAT_ACT),A
    XOR A : LD (PLAYER_FLYAWAY_WAIT),A
    XOR A : LD (PLAYER_FLYAWAY_DIST),A
    XOR A : LD (PARTICLE_SPAWN_COOLDOWN),A
    LD A,2 : LD (POD_VOLLEY_COLOR_TEST),A
    LD HL,PARTICLE_ACT : LD (HL),0
    LD DE,PARTICLE_ACT+1 : LD BC,23 : LDIR   ; round142: 4 slots * 6 arrays = 24 bytes
    XOR A
    LD (FIRE_COOLDOWN),A

    ; --- round40以前はここで強制的にH.TIMI(BIOSのvblankフック、RAM)を
    ; --- bare RETへ書き換えていた(「MSXの唯一の割り込み源はVDPなので、
    ; --- 下のEI+HALTがVDPステータスをポーリングするより安価・正確な
    ; --- vblank待ちになる」という理由)。実機フィードバック対応
    ; --- ("WebMSXでフリーズやリセットがかかる これは実機も同様"、
    ; --- openMSXで実際にH.TIMI経由のPC=0への暴走ジャンプを再現・特定):
    ; --- round40のBGM_TICK導入後、この行がINIT_BGM(このINITの先頭
    ; --- 付近、CALL INIT32の直後に移動済み - 上記コメント参照)が設置
    ; --- したフックをここで無条件に踏み潰してしまい、この行より後に
    ; --- 実行される全てのローカルEI(WRITE_ANIM_CELL等)がH.TIMIを
    ; --- 発火させるたび、Stage2/TitleのBGM_TICKと違い"BIOSデフォルトの
    ; --- 無害なRET"のつもりが実際には毎回この行が書き込んだbare RETで
    ; --- 上書かれ続け一見無害に見えたが、Title→Stage1の切替直後は逆に
    ; --- (この行が実行される前の一瞬)Titleの古いフックがまだ生きて
    ; --- いる区間があり、そこでH.TIMIが発火すると暴走した。Stage2/
    ; --- Titleは元々この種の行を持たない(HTIMI_HOOKはINIT_BGMでのみ
    ; --- 書く)ため、この行自体を完全に削除しStage2/Titleと同型に統一。
    ; --- 削除後は直前のCALL INIT_BGMが設置したBGM_TICKが最後まで有効な
    ; --- ままになり、下のEI+HALTは(BGM再生中なので)vblankごとに本物の
    ; --- 音楽ドライバ処理を経由してから続行する - 元のコメントが言う
    ; --- "cheap, exact vblank wait"では無くなるが、INITからMAINLOOPへの
    ; --- 移行点で一度きりのHALTなので実害は無い。

    ; --- enemy formation initial state: SPAWN_SCHEDULE_CHECK handles ---
    ; --- every spawn (including the first) from index0 onward.       ---
    XOR A
    LD (ENEMY_CYCLE),A
    LD (ENEMY_MODE),A
    LD (ANIM_RR),A
    LD (ANIM_BASE+0),A : LD (ANIM_BASE+8),A : LD (ANIM_BASE+16),A
    LD (EXPLOSION_SAVED_CM3),A : LD (EXPLOSION_SAVED_CM3+1),A : LD (EXPLOSION_SAVED_CM3+2),A
    LD (SND_TIMER),A
    LD (SND_TONE_TIMER),A
    LD (SND_TONE_IS_SE),A
    LD (SPAWN_NEXT_INDEX),A : LD (SPAWN_NEXT_INDEX+1),A

    ; --- PSG: 実機フィードバック対応("そもそもchB、Cは空けてあってSE類は
    ; --- chAのみで鳴らすはず") - 全SE(破壊音=ノイズ、ショット/ポッド
    ; --- 発射/ポッドヒット/バリアヒット=トーン)をチャンネルAへ統合し、
    ; --- チャンネルB/CはBGM専用に解放。AY-3-8910はチャンネルごとに
    ; --- トーン/ノイズを独立した有効ビットで持ち、片方を有効にしても
    ; --- もう片方が消えるわけではない(1chで最大4音同時合成のうちの
    ; --- 1音扱い) - 旧来「チャンネルA=ノイズ専用」だった設定(0B1h)から
    ; --- トーンAの有効ビット(bit0)だけを追加で立て、ノイズA/トーンB/
    ; --- トーンC/ノイズB/ノイズCは全て従来のまま変更しない(0B1h→0B0h、
    ; --- 差分はbit0の1ビットのみ)。
    ; --- R7's upper 2 bits MUST be '10' (portA=input,portB=output) - ---
    ; --- portB drives the joystick-port select strobe; leaving it as ---
    ; --- input (our old 0x33) floats that line and makes joystick    ---
    ; --- reads unstable on real PSG-based hardware.                  ---
    ; --- DI/EI wraps every reg-select+data pair: an interrupt firing  ---
    ; --- between the two OUTs would leave the wrong PSG register     ---
    ; --- selected, corrupting both this write and (since the BIOS's  ---
    ; --- keyboard/joystick scan also uses the PSG) joystick reads.   ---
    LD A,7 : OUT (PSG_ADDR),A
    LD A,0B0h : OUT (PSG_DATA),A

    ; --- sprite attribute table (VRAM 1B00h): ship body (16x16, slot1), ---
    ; --- accent overlay (16x16, slot0, drawn on top, at ship_X+8) ---
    DI
    LD A,04h : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,PLAYER_INITY : SUB 8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PLAYER_INITX : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_SHIP   : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_RED    : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP

    LD A,00h : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,PLAYER_INITY : SUB 8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PLAYER_INITX : ADD A,8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_ACCENT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_WHITE  : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC C
    EI
    DJNZ INIT_HIDE_SLOT_LOOP
    NOP

    ; --- BGM (round40) - INIT_BGM自体はもうここでは呼ばない。以前は
    ; --- ここ(INITの本当に最後、この直前のEIの直前)へ移設していたが、
    ; --- それは「H.TIMIフックはBGM_TICKが設置されるまでBIOSデフォルトの
    ; --- 無害なRETのまま」という誤った前提に基づいていた - 実際には
    ; --- Title→Stage1(またはStage1→Stage2)のバンク切替トランポリンで
    ; --- 着地した直後のH.TIMIフックは、直前のステージが最後に設置した
    ; --- 「そのステージ自身のBGM_TICKアドレスを指す古いフック」がまだ
    ; --- 生きたまま残っている。このINITの先頭付近にある複数のローカルな
    ; --- DI/EIペア(このEIを含む、上のスプライトアトリビュート設定・
    ; --- 30スロット非表示ループ・WRITE_ANIM_CELL経由のSCORE_DISPLAY等)
    ; --- 自身のEIが、INIT_BGMがこのファイル自身のBGM_TICKへフックを
    ; --- 上書きするより前に一瞬だけ割り込みを再許可してしまうと、window
    ; --- Aの中身が既に切り替わった後のこのステージのコード空間へ、前の
    ; --- ステージのバンク内アドレスのままH.TIMIがJPしてしまい、たまたま
    ; --- そこにあるバイト列を命令として誤実行する(実害はPC=0への
    ; --- 暴走ジャンプ→MSXの起動ロゴが再表示される疑似リセットとして
    ; --- 観測された)。「移設先をどこにずらしても、それより前に1つでも
    ; --- ローカルEIが残っていれば同じ問題が起きる」ため、根本的には
    ; --- 逆に「このINITの先頭、最初のDIの直後」へ移設し、以後に続く
    ; --- 全てのローカルEIが発生する前にH.TIMIフックを自分自身の正しい
    ; --- BGM_TICKへ上書き済みにしておくことで解消した(openMSXの外部
    ; --- 制御プロトコルでPC=0への着地を直接観測し、この移設で再現しなく
    ; --- なることを確認済み - 詳細はHANDOFF.md参照)。呼び出し箇所は
    ; --- このファイル冒頭、"DI" の直後(CALL INIT32の前)。

    ; INIT_BGMはBGM_MUTED=1(ミュート)で初期化する設計に変更済み
    ; (このINIT冒頭のMISSION1表示中に万一H.TIMIが発火してもchB/chCへ
    ; 音を出させないため)。ステージ本編の初期化が全て完了したこの
    ; 時点で初めてUNMUTE_BGMを呼び、以後MAINLOOPで通常通りBGMが鳴る。
    CALL LZ_INIT
    CALL UNMUTE_BGM

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

    ; GAME_OVER_SEQ状態機械は毎フレーム無条件に呼ぶ(STAGE_CLEAR_ACTの
    ; フリーズ有無に関わらず - UPDATE_STAGE_CLEAR自身のフリーズ判定
    ; より前に置くことで両立させる)。詳細はUPDATE_GAME_OVER_SEQUENCE
    ; 自身のコメント参照。
    CALL UPDATE_GAME_OVER_SEQUENCE

    ; (2026-09-06、"画面をブラックで埋めてMISSION 2とセンターに表示
    ; 3秒でいいかな"): STAGE_CLEAR_ACTが2(MISSION2黒画面表示中)以上に
    ; なった以後は、地形スクロール・敵更新・HUD再描画等、通常フレームの
    ; 処理を丸ごとスキップする。理由: DRAW_MISSION_SCREENは生VRAM書き
    ; 込みでNAMEBUF/PREVBUFの内部キャッシュを経由しないため、これらを
    ; 素通りしたまま通常のMAINLOOPを続行させると、地形スクロールが
    ; 毎フレームのNAMEBUF/PREVBUF差分検出経由で黒画面の上に地形を
    ; 再描画してしまい、MISSION2表示が一瞬で破壊される(この直前の
    ; GAME_OVERを止めない方針とは別種の判断 - あちらは「実機で検証
    ; できないから」フリーズさせない、こちらは「ユーザーから明示的に
    ; 依頼された、実時間3秒で必ず終わる」cutscene用の一時停止)。
    ; UPDATE_STAGE_CLEAR自身は毎フレーム呼び続ける必要がある
    ; (ACT==2→3への実時間3秒判定を進めるため)。
    LD A,(STAGE_CLEAR_ACT)
    CP 2
    JR C,STAGE_CLEAR_NOT_FROZEN
    CALL UPDATE_STAGE_CLEAR
    JP MAINLOOP
STAGE_CLEAR_NOT_FROZEN:

    ; "現状ゲームオーバー処理は残しておくが ゲームは止めないでくれ
    ; チェックできないからな" - GAME_OVER itself is still tracked
    ; (PLAYER_TAKE_HIT still sets it) but MAINLOOP no longer freezes
    ; on it - play continues so the feature can actually be tested.
    ; (Previous round's freeze-the-whole-loop gate lived right here;
    ; deliberately removed, not just disabled, per this instruction.)

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
    CALL LZ_FRAME    ; レーザーゲージ(毎フレーム)+ボスレーザー干渉(BOSS_STATE==2のみ)

    LD A,(TICK) : AND 07h
    JR NZ,SKIP_G8
    LD A,(PXCHAR_G8) : INC A : AND 3Fh : LD (PXCHAR_G8),A
    LD HL,ROWDATA5 : LD A,(PXCHAR_G8) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE5 : CALL REFRESH_IDCACHE_33
    ; round135follow-up5("今のハードコードしたEbuzスケジュールは削除
    ; しといて 意図と違ってるんで"): 2026-09-14に導入した「Ebuz出現中は
    ; GAME_TICK自体を凍結しSPAWN_SCHEDULE_CHECKも呼ばない」仕組み
    ; (EBUZ_ANY_ACTIVE判定+固定tickテーブルでのEBUZ_SPAWN_CHAIN_START
    ; 自動発火)を全面撤去し、GAME_TICKの単純な無条件インクリメント+
    ; SPAWN_SCHEDULE_CHECK呼び出しへ復元(Ebuz導入前の元の形)。
    ; round135follow-up11("止めると言うのは新規スポーンを阻止する意味
    ; じゃないぞ Tickを進めてしまったらEbuz出現中の敵がキャンセルされて
    ; しまうからな Tickカウントをとめるのが合理的だろう"): follow-up10で
    ; 試したSSC_FIRE側だけのディスパッチ一時停止(GAME_TICKは進め続ける)
    ; は、Ebuz生存中に経過したtick分のエントリが全てしきい値超過済みに
    ; なり、Ebuz消滅の瞬間にまとめて連続発火する(本来のスケジュール間隔が
    ; 潰れてバーストになる)問題があった - ユーザーの指摘通り、時計自体を
    ; 止めるほうが正しい。上記follow-up5の「単純な無条件インクリメント」を
    ; 撤回し、EBUZ_ANY_ACTIVEガードでGAME_TICKの加算とSPAWN_SCHEDULE_
    ; CHECK呼び出し自体を丸ごとスキップする、follow-up5以前と全く同じ
    ; 凍結構造を再度導入した(ただしEbuz自身のトリガー機構は、follow-up5
    ; で撤去した固定tickテーブルの自動発火ではなく、follow-up9で配線した
    ; SSC_FIRE経由のスケジュール駆動[Schedule_2_1.jsonの"ebuz"配置]の
    ; ままで変更なし - 凍結中はSPAWN_SCHEDULE_CHECK自体を呼ばないため、
    ; Ebuz自身の次のトリガーも他のエントリと同様に自然に足止めされる)。
    ; follow-up10で追加したSSC_FIRE冒頭の同種ガードは、この凍結により
    ; SPAWN_SCHEDULE_CHECKごと呼ばれなくなるため冗長になった - 二重の
    ; 仕組みを残さず撤去(下記SSC_FIRE参照)。
    CALL EBUZ_ANY_ACTIVE
    OR A
    JR NZ,SKIP_SCHEDULE_TICK
    ; round138(実機フィードバック対応、"ブランクが地形のデータに化けてる"の
    ; 真因): 上のEBUZ_ANY_ACTIVE(無印Ebuz生存中はスケジュール凍結)と同じ
    ; 扱いをEbuz Mk2(EBUZ2_ACT)にも適用しないと、Mk2の一体制スクリプト
    ; 戦闘中もSPAWN_SCHEDULE_CHECKが素通りで走り続け、スケジュール上の
    ; 無印Ebuz("ebuz"配置)を含む通常エネミーがMk2と同時に湧いてしまう
    ; (実機報告の「地形データに化けてる」の実体は、無印Ebuzの弾
    ; [EBUZ_BULLET_L/R_CODE=136/137、色0B4h=水色地に黄]がMk2戦闘中に
    ; 普通に飛んでいるだけだった - 実機起動シミュレーションでのVRAM
    ; レンダリング調査により、この弾が正常に1px/frameで左へ飛び続けて
    ; いる[消し忘れではない]ことを確認済み)。既存のEBUZ_ANY_ACTIVE
    ; ルーチン自体([無印Ebuz固有のコード)には一切触れず、この汎用
    ; ディスパッチゲート側にEBUZ2_ACTチェックを追加するだけで対応
    ; (独立性を保つ - "独立出来るなら独立させろ"の指示に沿う)。
    LD A,(EBUZ2_ACT)
    OR A
    JR NZ,SKIP_SCHEDULE_TICK
    ; (2026-09-23、"スタート演出中はTickはカウントスタートすんな"):
    ; 飛び込み演出中はGAME_TICKを進めずスケジュールも回さない。
    LD A,(SHIP_ENTRY_ACT)
    OR A
    JR NZ,SKIP_SCHEDULE_TICK
    LD HL,(GAME_TICK) : INC HL : LD (GAME_TICK),HL
    ; round135follow-up16("ボスでは居ないはずのEbuzが出てる スポーン
    ; 条件をすり抜けてるな"): CHECK_BOSS_TRIGGERはGAME_TICK>=1024+
    ; 全プール瞬間空という条件だけで発火し(follow-up13の設計)、
    ; SPAWN_NEXT_INDEXがスケジュール末尾に達しているかは一切見ない
    ; ため、まだ未消化のエントリを残したままボスが出現しうる。この
    ; SPAWN_SCHEDULE_CHECK呼び出し自体はBOSS_STATEを一切見ておらず、
    ; ボス出現後もGAME_TICKが進み続ける限り毎フレーム呼ばれ続けて
    ; いたため、ボス戦中に残りのスケジュール(Ebuzを含む)がすり抜けて
    ; 発火していた。GAME_TICK自体はPOD_FIRE_START(ボス出現時点の
    ; GAME_TICKからの相対ターゲット)の比較に必要なため凍結できない -
    ; ディスパッチ側(SPAWN_SCHEDULE_CHECK呼び出し)だけをBOSS_STATE==0
    ; の間に限定して解消。
    LD A,(BOSS_STATE)
    OR A
    CALL Z,SPAWN_SCHEDULE_CHECK
SKIP_SCHEDULE_TICK:
SKIP_G8:
    CALL CHECK_BOSS_TRIGGER
    LD A,(TICK) : AND 07h : LD (PHASE_G8),A

    LD A,(TICK) : AND 0Fh
    JR NZ,SKIP_G4
    LD A,(PXCHAR_G4) : INC A : AND 3Fh : LD (PXCHAR_G4),A
    LD HL,ROWDATA3 : LD A,(PXCHAR_G4) : LD E,A : LD D,0 : ADD HL,DE
    LD IX,IDCACHE3 : CALL REFRESH_IDCACHE_33
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

    ; --- row 0: screen row 20 (TIER1_MOUNTAIN), group PXCHAR_G1 ---
    ; --- (was screen row 19 - moved down 1 row to fill the gap left by ---
    ; --- deleting TIER5_BACKSLASH's own row, see GROUND_ROW0) ---
    LD A,(PHASE_G1) : LD (ROWPHASE),A
    LD HL,IDCACHE0                       ; pre-translated ids - see IDCACHE0 comment
    LD IX,NAMEBUF+0
    ; ROWPHASE is loop-invariant for the whole 32-cell row (set once just
    ; above, never touched mid-row) - re-testing "ROWPHASE==0" (and, in
    ; the nonzero case, re-reading ROWPHASE a SECOND time for the final
    ; "-1" blend offset) on every one of the 32 iterations was pure
    ; waste. Split into 2 loop bodies, selected ONCE here instead -
    ; ported from tools/stage2_combined/combined_test.asm's own
    ; TERRAIN_RENDER_ROW fix (round26/27 there: this exact code shape,
    ; measured there at 43.57% of a whole frame's own T-state budget
    ; before the fix). Pure loop-invariant code motion - output is bit-
    ; for-bit identical to the old single-loop version for every input,
    ; verified by tools/verify_cell_loop_hoist.py.
    LD A,(ROWPHASE)
    OR A
    JR NZ,NONZERO_ENTRY_0
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_ZERO_0:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A
    DJNZ CELL_LOOP_ZERO_0
    JR CELL_ROW_DONE_0
NONZERO_ENTRY_0:
    DEC A : LD (PHASE_MINUS1),A
    LD B,32
    ; --- prime C = curr_id for cell 0; each cell's "next" is the following---
    ; --- cell's "curr" (HL only advances by 1/cell), so C carries it       ---
    ; --- forward every iteration instead of re-reading it. ---
    LD A,(HL) : LD C,A
CELL_LOOP_0:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(PHASE_MINUS1) : ADD A,E       ; + (phase-1), precomputed once
STORE_0:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_0
CELL_ROW_DONE_0:

    ; --- row 2: screen row 21 (TIER3_DIAMOND), group PXCHAR_G2 ---
    ; --- (was screen row 20 - moved down 1 row, see GROUND_ROW0) ---
    LD A,(PHASE_G2) : LD (ROWPHASE),A
    LD HL,IDCACHE2
    LD IX,NAMEBUF+32
    ; loop-invariant branch hoist - see CELL_LOOP_0's own comment above.
    LD A,(ROWPHASE)
    OR A
    JR NZ,NONZERO_ENTRY_2
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_ZERO_2:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A
    DJNZ CELL_LOOP_ZERO_2
    JR CELL_ROW_DONE_2
NONZERO_ENTRY_2:
    DEC A : LD (PHASE_MINUS1),A
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_2:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(PHASE_MINUS1) : ADD A,E       ; + (phase-1), precomputed once
STORE_2:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_2
CELL_ROW_DONE_2:

    ; --- row 3: screen row 22 (TIER4_SLASH), group PXCHAR_G4 ---
    ; --- (was screen row 21 - moved down 1 row, see GROUND_ROW0) ---
    LD A,(PHASE_G4) : LD (ROWPHASE),A
    LD HL,IDCACHE3
    LD IX,NAMEBUF+64
    ; loop-invariant branch hoist - see CELL_LOOP_0's own comment above.
    LD A,(ROWPHASE)
    OR A
    JR NZ,NONZERO_ENTRY_3
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_ZERO_3:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A
    DJNZ CELL_LOOP_ZERO_3
    JR CELL_ROW_DONE_3
NONZERO_ENTRY_3:
    DEC A : LD (PHASE_MINUS1),A
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_3:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(PHASE_MINUS1) : ADD A,E       ; + (phase-1), precomputed once
STORE_3:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_3
CELL_ROW_DONE_3:

    ; --- row 5: screen row 23 (TIER6_WEDGE), group PXCHAR_G8 - ---
    ; --- stays fixed at the bottom of the screen; NAMEBUF slot ---
    ; --- shifted from +128 to +96 now that TIER5_BACKSLASH's   ---
    ; --- own row/slot is gone, see GROUND_ROW0 ---
    LD A,(PHASE_G8) : LD (ROWPHASE),A
    LD HL,IDCACHE5
    LD IX,NAMEBUF+96
    ; loop-invariant branch hoist - see CELL_LOOP_0's own comment above.
    LD A,(ROWPHASE)
    OR A
    JR NZ,NONZERO_ENTRY_5
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_ZERO_5:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,SOLOTAB/256 : LD A,(DE)
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A
    DJNZ CELL_LOOP_ZERO_5
    JR CELL_ROW_DONE_5
NONZERO_ENTRY_5:
    DEC A : LD (PHASE_MINUS1),A
    LD B,32
    LD A,(HL) : LD C,A
CELL_LOOP_5:
    INC HL
    LD A,(HL) : LD (NEXTID),A
    LD A,C : LD E,A : LD D,MUL6/256 : LD A,(DE) : LD E,A  ; E = curr_id*6
    LD A,(NEXTID) : ADD A,E             ; A = pairid = curr_id*6+next_id
    LD E,A : LD D,PAIRBASE/256 : LD A,(DE)  ; A = PAIRBASE[pairid]
    LD E,A
    LD A,(PHASE_MINUS1) : ADD A,E       ; + (phase-1), precomputed once
STORE_5:
    LD (IX+0),A
    INC IX
    LD A,(NEXTID) : LD C,A              ; carry next_id forward as next cell's curr_id
    DJNZ CELL_LOOP_5
CELL_ROW_DONE_5:

    ; --- push each row to VRAM, skipping rows unchanged since last frame ---
    ; (Name table base is 1800h in SCREEN1 too, so these VRAM
    ;  addresses are identical to the SCREEN2 version.)

    ; row 0 -> VRAM 1A80h (screen row 20 - moved down from 1A60h/row19,
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
    LD A,80h : OUT (99h),A
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_0:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_0
ROWDONE_0:

    ; row 2 -> VRAM 1AA0h (screen row 21 - moved down from 1A80h/row20,
    ; see GROUND_ROW0)
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
    LD A,A0h : OUT (99h),A
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_2:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_2
ROWDONE_2:

    ; row 3 -> VRAM 1AC0h (screen row 22 - moved down from 1AA0h/row21,
    ; see GROUND_ROW0)
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
    LD A,C0h : OUT (99h),A
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_3:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL : DEC B
    EI
    JP NZ,ROWXFER_3
ROWDONE_3:

    ; row 5 -> VRAM 1AE0h (screen row 23, bottom row of screen -
    ; stays fixed, TIER6_WEDGE doesn't move) - NAMEBUF slot shifted
    ; from +128 to +96 now that TIER5_BACKSLASH's own row/slot is
    ; gone, see GROUND_ROW0
    LD HL,NAMEBUF+96 : LD DE,PREVBUF+96 : LD B,32
DIFF_LOOP_5:
    LD A,(DE) : CP (HL)
    JR NZ,DIFFERENT_5
    INC HL : INC DE
    DJNZ DIFF_LOOP_5
    JR ROWDONE_5
DIFFERENT_5:
    LD HL,NAMEBUF+96 : LD DE,PREVBUF+96 : LD BC,32 : LDIR
    LD HL,NAMEBUF+96
    DI
    LD A,E0h : OUT (99h),A
    NOP
    NOP
    LD A,5Ah : OUT (99h),A
    NOP
    NOP
    LD C,98h
    LD B,32
    EI
ROWXFER_5:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    ; (2026-09-21、"ステージ1スタート直後...急に始まるのでなく飛び込んで
    ; くる演出...左上から斜め右下に移動 Y中央まで来たら通常時の絵にして
    ; Xが32pxの位置に"): 全サブフェーズの中で最も手前(GAME_OVERより前)
    ; でチェック - ステージ開始直後にしか起こり得ないため。ジョイス
    ; ティック入力は無視し、PLAYERX/PLAYERYをそれぞれ独立にPLAYER_
    ; RETREAT_TARGET_X(32)/PLAYER_INITY(64)へSHIP_ENTRY_SPEEDずつ近づけ、
    ; 両方到達したらSHIP_ENTRY_ACTを落として以後の通常チェーンへ引き継ぐ。
    ; (ROM予算のALIGN-256境界の関係で、実処理はUPDATE_SHIP_ENTRY[後方の
    ; 安全なコード領域]へ切り出し、ここはCALLのみに留めている)
    LD A,(SHIP_ENTRY_ACT)
    OR A
    JR Z,PFA_NO_ENTRY
    CALL UPDATE_SHIP_ENTRY
    JP DIR_DONE
PFA_NO_ENTRY:
    ; (2026-09-07、"ステージ1の自機爆発演出追加 操作無効の上爆発しながら
    ; 右斜め下に落下しMission Failed表示に"、続けて"落下したら自機は
    ; 画面外に消えるように"、さらに"斜め下に落下したらそのまま画面外に
    ; 消えるように変更"): 上記のPLAYER_RETREAT_ACT(ステージクリア専用)
    ; より更に手前でチェックする新規サブフェーズ - GAME_OVERをマスター
    ; ゲートとして使う(PTH_GAMEOVERが唯一の書き込み元で、必ず同時に
    ; PLAYER_DEATH_FALL_TRIGGERも呼ぶため、GAME_OVER=1は「まだ落下中」か
    ; 「落下完了後、画面外に隠れたまま」のどちらかしかありえない)。
    ; GAME_OVER=1の間は以後二度と(このゲームが続く限り永久に)
    ; PFA_NO_DEATH_FALL以降の通常入力チェーンへ落ちない。
    LD A,(GAME_OVER)
    OR A
    JR Z,PFA_NO_DEATH_FALL
    LD A,(PLAYER_DEATH_FALL_ACT)
    OR A
    JR NZ,PFA_DEATH_FALL_STEP
    ; 落下完了後: 毎フレーム、ENEMY_HIDE_Yと全く同じ「(255,191)の
    ; 右下コーナー」慣習(このファイル全体で確立済みの非表示トリック)
    ; へPLAYERX/PLAYERYを強制し続ける - 自機スプライトは実際にPLAYERY
    ; -8した値を描画するため、ここでは199を書いて実際の描画Yが191に
    ; なるよう逆算している。ジョイスティック入力は一切読まない。
    LD A,255 : LD (PLAYERX),A
    LD A,199 : LD (PLAYERY),A
    JP DIR_DONE
PFA_DEATH_FALL_STEP:
    ; まだ落下中: ジョイスティック入力を完全に無視してPLAYERX/PLAYERYを
    ; 両方PLAYER_DEATH_FALL_SPEEDずつ加算し続ける(右斜め下への等速落下、
    ; 8bitオーバーフローでラップして左端へワープしないようキャリーで
    ; 255クランプ)。この間も既存のPLAYER_EXPL_UPDATE_ALL(PEUA_TRY_
    ; SPAWNが毎回PLAYERX/PLAYERYを直接読む設計)がそのまま自機の新しい
    ; 位置に追従して爆発バーストを継続するため、爆発しながら落下する
    ; 見た目になる。固定フレーム数のタイマーは持たず、PLAYERYが実際に
    ; 画面外の値(199、非表示コーナーの逆算値)へ達した瞬間だけ完了
    ; 処理(MISSION FAILEDテキスト描画・GAME_OVER_SEQ起動)を行う -
    ; 開始位置からの距離がそのまま落下時間になる、自然な連続落下。
    LD A,(PLAYERX) : ADD A,PLAYER_DEATH_FALL_SPEED
    JR NC,PDF_X_OK
    LD A,255
PDF_X_OK:
    LD (PLAYERX),A
    LD A,(PLAYERY) : ADD A,PLAYER_DEATH_FALL_SPEED
    JR NC,PDF_Y_ADDED
    LD A,255                 ; オーバーフロー: 画面外へ到達したのと同じ扱い
PDF_Y_ADDED:
    CP 199
    JR C,PDF_STORE_Y          ; 199未満ならまだ画面内、そのまま格納
    LD A,199                  ; 199以上/オーバーフロー -> 199へクランプ
PDF_STORE_Y:
    LD (PLAYERY),A
    CP 199
    JR NZ,PDF_NOT_DONE         ; まだ199未満 = 落下継続中
    ; 今回のフレームで初めて199(画面外)へ到達 - 以後PLAYER_DEATH_
    ; FALL_ACTが再び1になることは無い(生涯で1回だけここを通る)。
    XOR A : LD (PLAYER_DEATH_FALL_ACT),A
    LD A,255 : LD (PLAYERX),A
    ; (2026-09-23) ボス条件未達でやられた場合は通常のMISSION FAILEDを出さず、
    ; GAME_OVER_SEQ=4(Combがbank7の理由付き画面へ切り替える)。
    LD A,(LZ_FAIL_REASON) : OR A
    JR Z,PDF_NORMAL_FAIL
    LD A,4 : LD (GAME_OVER_SEQ),A
    JP DIR_DONE
PDF_NORMAL_FAIL:
    CALL TRIGGER_GAME_OVER_JINGLE
    CALL DRAW_GAMEOVER_TEXT
    LD A,1 : LD (GAME_OVER_SEQ),A
    LD HL,(SC_VBLANK_COUNT) : LD (GAME_OVER_START_TICK),HL
    JP DIR_DONE
PDF_NOT_DONE:
    JP DIR_DONE
PFA_NO_DEATH_FALL:

    ; (2026-09-06、"一旦左端まで下がってから飛び去る様に変更"): 通常の
    ; flyawayシーケンスより前にチェックする新規サブフェーズ - ボス撃破の
    ; 瞬間にPLAYER_RETREAT_ACT=1が立ち、ここでPLAYERXをPLAYER_RETREAT_
    ; SPEEDずつPLAYER_RETREAT_TARGET_Xへ近づける(ジョイスティック入力は
    ; 無視)。目標に到達したら従来通りPLAYER_FLYAWAY_WAIT/SPDを起動して
    ; 普通のflyawayへ引き継ぐ(PFA_MOVING以降のロジックは完全に無変更)。
    ; (round142、"下がり過ぎでパーティクルが右から出てしまってる"):
    ; 目標を旧来のX=0からPLAYER_RETREAT_TARGET_X(=32、PARTICLE_ACT寿命
    ; ちょうど分)へ変更、PLAYER_RETREAT_TARGET_X自身のコメント参照。
    LD A,(PLAYER_RETREAT_ACT)
    OR A
    JR Z,PFA_NO_RETREAT
    LD A,(PLAYERX)
    SUB PLAYER_RETREAT_TARGET_X   ; carry set if PLAYERX<target (safety); Z set if
    JR C,PFA_RETREAT_DONE         ; equal; else A = remaining distance to the target
    JR Z,PFA_RETREAT_DONE
    CP PLAYER_RETREAT_SPEED
    JR NC,PFA_RETREAT_STEP
    LD A,PLAYER_RETREAT_TARGET_X  ; remaining < speed: snap exactly to target
    JR PFA_RETREAT_SET
PFA_RETREAT_STEP:
    LD A,(PLAYERX)
    SUB PLAYER_RETREAT_SPEED
PFA_RETREAT_SET:
    LD (PLAYERX),A
    JP DIR_DONE
PFA_RETREAT_DONE:
    XOR A : LD (PLAYER_RETREAT_ACT),A
    LD A,40 : LD (PLAYER_FLYAWAY_WAIT),A
    LD A,1 : LD (PLAYER_FLYAWAY_SPD),A
    JP DIR_DONE
PFA_NO_RETREAT:

    ; --- post-boss flyaway: once the BG-destruction sequence      ---
    ; --- finishes, there's a short beat (PLAYER_FLYAWAY_WAIT) where---
    ; --- the ship just sits still, then it auto-flies right,      ---
    ; --- accelerating, and ignores joystick input entirely until   ---
    ; --- it's off-screen, then stays hidden. ---
    LD A,(PLAYER_FLYAWAY)
    CP 1
    JR Z,PFA_MOVING
    CP 2
    JR NZ,PFA_FLYAWAY_IDLE
    ; "ステージクリアで流して" - PLAYER_FLYAWAY==2に到達した最初の
    ; フレームでのみジングルを起動(STAGE_CLEAR_ACT==0のガード)、以後は
    ; 曲の総再生時間経過をUPDATE_STAGE_CLEARが監視する。
    LD A,(STAGE_CLEAR_ACT)
    OR A
    JR NZ,PFA_SC_ALREADY_TRIGGERED
    CALL TRIGGER_STAGE_CLEAR
    JP DIR_DONE
PFA_SC_ALREADY_TRIGGERED:
    CALL UPDATE_STAGE_CLEAR
    JP DIR_DONE
PFA_FLYAWAY_IDLE:
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
    ; (round142、"飛び去る演出のサウンドが鳴り続けてしまうバグ...何度か
    ; に一回起こる"): このPSGレジスタ選択+データの2段書き込みだけが
    ; ファイル全体で唯一DI/EI保護されていなかった - H.TIMI駆動のBGM_
    ; TICKがこの2命令の間で割り込むと、アドレスラッチがBGM側の別レジスタ
    ; を指したままこのA=18の書き込みが飛んでしまい、稀にR8(チャンネルA
    ; 音量)へエンベロープ有効ビット(bit4)付きの値が誤って書き込まれる -
    ; 一度この状態になるとSOUND_UPDATE/TRIGGER_STAGE_CLEARが後で書く
    ; 静的な音量値(0含む)が効かなくなり、ハードウェアエンベロープ任せの
    ; 音が鳴り続けてしまう。他の全PSG書き込み箇所(SOUND_DESTROY等)と
    ; 同じDI/EIで挟んで解消。
    DI
    LD A,6 : OUT (PSG_ADDR),A
    LD A,18 : OUT (PSG_DATA),A
    EI
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
    ; (2026-09-23): レーザー照射中/干渉中(LZ_PHASE 1,3)は自機固定(Bの連打は上で拾う)
    LD A,(LZ_PHASE) : AND 0FDh : DEC A : JP Z,DIR_DONE

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

    ; pick this frame's ship sprite frame from the raw stick direction
    ; (not from PLAYERY's own clamped movement, so bumping the MINY/
    ; MAXY ceiling still shows the tilt even though the ship stops
    ; moving) - done here, before the timing-critical VDP write block
    ; below, since the CP/JR chain's variable branch cost would throw
    ; off that block's fixed NOP-padded OUT spacing.
    LD A,(JOY_STICK)
    CP 1 : JR Z,SHIPFR_UP
    CP 2 : JR Z,SHIPFR_UP
    CP 8 : JR Z,SHIPFR_UP
    CP 4 : JR Z,SHIPFR_DOWN
    CP 5 : JR Z,SHIPFR_DOWN
    CP 6 : JR Z,SHIPFR_DOWN
    LD A,PAT_SHIP
    JR SHIPFR_GOT
SHIPFR_UP:
    LD A,PAT_SHIP_UP
    JR SHIPFR_GOT
SHIPFR_DOWN:
    LD A,PAT_SHIP_DOWN
SHIPFR_GOT:
    LD (PLAYER_SHIP_PAT),A

    ; same idea for the accent overlay, but it only has MID/DOWN -
    ; climbing (and everything else) keeps MID. While the barrier is
    ; equipped (BARRIER_HP>0), show the barrier-augmented variant of
    ; whichever pose would normally show instead (see ACCENT_MID_
    ; BARRIER_PATTERN/ACCENT_DOWN_BARRIER_PATTERN) - reverts to the
    ; plain accent once BARRIER_HP reaches 0.
    LD A,(JOY_STICK)
    CP 4 : JR Z,ACCFR_DOWN
    CP 5 : JR Z,ACCFR_DOWN
    CP 6 : JR Z,ACCFR_DOWN
    LD A,(BARRIER_HP) : OR A
    LD A,PAT_ACCENT
    JR Z,ACCFR_GOT
    LD A,PAT_ACCENT_BARRIER
    JR ACCFR_GOT
ACCFR_DOWN:
    LD A,(BARRIER_HP) : OR A
    LD A,PAT_ACCENT_DOWN
    JR Z,ACCFR_GOT
    LD A,PAT_ACCENT_DOWN_BARRIER
ACCFR_GOT:
    ; (follow-up28) レーザーのエナジーが満タンの間、バリアの右半分を反転した絵と
    ; 2フレームごとに交互に
    CP PAT_ACCENT_BARRIER
    JR C,ACCFR_ST
    LD B,A
    LD A,(GAUGE_SHOWN) : CP GAUGE_MAX
    LD A,(TICK)
    JR NZ,ACCFR_B
    AND 2
    LD A,B
    JR Z,ACCFR_ST
    ADD A,PAT_ACCENT_BARRIER_M-PAT_ACCENT_BARRIER
    JR ACCFR_ST
ACCFR_B:
    LD A,B
ACCFR_ST:
    LD (PLAYER_ACCENT_PAT),A

    ; (2026-09-21、飛び込み演出): 上記の通常ポーズ選択(JOY_STICK/
    ; BARRIER_HP由来)を丸ごと上書きし、飛び込み演出専用パターンへ
    ; 差し替える。色は下のDI描画ブロック側が元々SPR_RED/SPR_WHITE
    ; 固定(ACC_COLOR_GOTのBARRIER_IFRAMES分岐のみ)のため無変更 -
    ; ShipStart2=赤/ShipStart1=白と一致させて選んだ配色(EQU参照)。
    LD A,(SHIP_ENTRY_ACT)
    OR A
    CALL NZ,APPLY_SHIP_ENTRY_PAT

    ; "被弾時はバリア色のホワイトをパープルに" - flashes purple for the
    ; same window as BARRIER_IFRAMES (the post-hit invulnerability
    ; timer already tracks exactly "just got hit"), white otherwise.
    ; Precomputed here (outside the DI-timed VDP write block below) so
    ; that block's own fixed NOP spacing stays undisturbed - same
    ; reasoning as EBSD_DRAW_PAT/EBSD_DRAW_COLOR.
    LD A,(BARRIER_IFRAMES) : OR A
    LD A,SPR_WHITE
    JR Z,ACC_COLOR_GOT
    LD A,SPR_PURPLE
ACC_COLOR_GOT:
    LD (PLAYER_ACCENT_COLOR),A

    ; (2026-09-22、"自機登場演出でスプライトがズレてる"): 通常時は
    ; アクセントをbody+8pxへオフセットして描く(自機前方のバリア表示
    ; 用の意図的なズラし)が、飛び込み演出中のShipStart1/2は"重ねて"
    ; 表示する仕様(オフセット無し)のため、この描画ブロック内の
    ; "ADD A,8"をD(0か8)との加算へ差し替え、飛び込み演出中だけ0にする。
    ; DIブロックのT-state固定タイミングを崩さないよう、値はここで
    ; 事前計算(ADD A,8→ADD A,Dは1byte減・3T速くなるだけで安全側)。
    ; PLAYER_DRAW_Y_ADJ(CALLのみ挟まる)はA,BCしか触らないためD/Eは
    ; DIブロック内で使用箇所まで無傷で残る。
    ; (2026-09-22follow-up): leg2は通常資産(PAT_ACCENT_DOWN系)を流用する
    ; ため通常と同じ+8オフセットに戻す。オフセット0はleg1(ShipStart1/2の
    ; 重ね合わせ専用絵柄)の時だけ。
    LD A,(SHIP_ENTRY_ACT)
    CP 1
    LD D,8
    JR NZ,ACCENT_XOFS_GOT
    LD D,0
ACCENT_XOFS_GOT:

    ; redraw ship: slot1=body, slot0=accent overlay (priority above ---
    ; body, drawn at PLAYERX+8, PLAYERY)
    DI
    LD A,04h : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(PLAYERY) : SUB 8 : CALL PLAYER_DRAW_Y_ADJ : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(PLAYERX) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(PLAYER_SHIP_PAT) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_RED : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP

    LD A,00h : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(PLAYERY) : SUB 8 : CALL PLAYER_DRAW_Y_ADJ : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(PLAYERX) : ADD A,D : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(PLAYER_ACCENT_PAT) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(PLAYER_ACCENT_COLOR) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP

    ; ============================================================
    ; --- fire: A button (joystick1 trigger1), up to 3 shots on  ---
    ; --- screen, with a 1-frame gap enforced between spawns so  ---
    ; --- holding the button fires intermittently (shot,gap,shot)---
    ; ============================================================
    ; (round142、"弾打ちっぱなしで演出に入ると手を離しても撃ち続ける
    ; バグ"): PLAYER_RETREAT_ACT中(ボス撃破直後、flyawayより前の左端への
    ; 後退フェーズ)はPFA_NORMAL_INPUT自体を経由しない(退避専用の"JP
    ; DIR_DONE"で毎回抜ける)ため、GTTRIGでJOY_TRIGを読み直す行に一度も
    ; 到達しない - ボス撃破の瞬間にトリガーを押していると、その値が
    ; そのまま後退フェーズの間ずっと"押しっぱなし"として凍結され続け、
    ; 実際には指を離していても発射され続けていた(GAME_OVER時の死亡落下と
    ; 全く同型のバグ、round71参照)。PLAYER_FLYAWAYと同じ扱いでここに
    ; ガードを追加。
    LD A,(PLAYER_FLYAWAY)
    LD HL,PLAYER_RETREAT_ACT
    OR (HL)
    EI
    JP NZ,FIRE_DONE
    ; (2026-09-07、実機フィードバック対応、"ステージ1で画面が壊れる原因が
    ; 分かった 爆発処理で操作無効で落下していく時に弾を撃った状態で死ぬと
    ; 弾を撃ったまま画面外に出てVRAM壊してる つまり操作無効と同時に弾
    ; 打つのを停止すれば解決する"): 死亡落下(GAME_OVER=1、以後PLAYERYが
    ; 199=非表示コーナーまで直線的に増加し続ける)の間、この発射チェックだけ
    ; はPLAYER_FLYAWAYしかガードしておらず、方向入力(PFA_DEATH_FALL_STEP
    ; 参照)と違って発射自体は止まっていなかった。トリガー押しっぱなしで
    ; 死ぬと、落下で異常な値(150〜199)になった生のPLAYERYを起点に新規
    ; 弾のBULLET0_ROWが計算され、24行分[0-23]しか正当なエントリを持たない
    ; ROWADDR_LO/HIテーブルを範囲外indexで読んでしまい、結果として得られる
    ; VRAMアドレスが不定(カラーテーブル・パターンジェネレータ等、本来は
    ; 無関係な領域を指しうる)になる - 移動のたびその不正アドレスへ書き
    ; 込み続けるため、色や絵柄が広範囲に壊れて見える(スクリーンショットの
    ; ピンク背景・市松模様ノイズの直接原因)。GAME_OVER=1の間は方向入力と
    ; 同時に発射自体も完全に止め、この不正な弾の新規発生源を断つ。
    LD A,(GAME_OVER)
    OR A
    JP NZ,FIRE_DONE
    LD A,(FIRE_COOLDOWN)
    OR A
    JR Z,CHECK_FIRE
    DEC A : LD (FIRE_COOLDOWN),A
    JP FIRE_DONE
CHECK_FIRE:
    LD A,(JOY_TRIG)
    OR A : JP Z,FIRE_DONE          ; A button: fires while held
    ; (2026-09-23): Bボタン単発撃ちはボス用レーザー(LZ_FRAME)へ置き換えて削除。
    ; レーザー中(LZ_PHASE 1-3)はレーザー行を弾が上書きしないよう通常弾も撃たない。
    LD A,(LZ_PHASE) : DEC A : CP 3 : JP C,FIRE_DONE
    LD HL,BULLET_POOL : LD DE,6 : LD B,BULLET_SLOTS
CF_FIND:
    LD A,(HL)
    OR A
    JR Z,CF_FOUND
    ADD HL,DE
    DJNZ CF_FIND
    JP FIRE_DONE
CF_FOUND:
    LD (HL),1 : INC HL
    LD A,(PLAYERY) : ADD A,8 : SRL A : SRL A : SRL A : LD C,A    ; C=行
    LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD (HL),A : INC HL
    LD D,ROWADDR_HI/256 : LD A,(DE) : LD (HL),A : INC HL
    LD A,(PLAYERX) : ADD A,8
    JR NC,CF_SPAWN_OK
    LD A,255
CF_SPAWN_OK:
    SRL A : SRL A : SRL A
    LD (HL),A : INC HL             ; COL
    LD (HL),C : INC HL             ; ROW
    ; shots can never reach the ground scroller anymore (see
    ; PLAYER_MAXY) - always the sky/blue variant.
    LD A,(PLAYERY) : ADD A,8 : AND 07h
    CP 7
    JR NZ,CF_NOCLAMP
    DEC A
CF_NOCLAMP:
    ADD A,BULLET_PAT_BLUE
    LD (HL),A                      ; PAT
    LD A,FIRE_COOLDOWN_LEN : LD (FIRE_COOLDOWN),A
    CALL SOUND_SHOT
FIRE_DONE:

    ; --- Enemy2 instances A and B: each internally no-ops if not ---
    ; --- active, so calling both unconditionally every frame is  ---
    ; --- always safe and lets them run fully concurrently.       ---
    CALL ENEMY_COMPLEX_STEP_A
    CALL ENEMY_COMPLEX_STEP_B
ENEMY_SECTION_DONE:

    ; --- destroy-animation (3 slots), once per frame - see             ---
    ; --- UPDATE_ONE_EXPLOSION's own comment for the 3-frame/multi-cell ---
    ; --- design (round69 follow-up, ExpAnim_24x24.json). B carries the ---
    ; --- slot index (0-2) so the routine can address this slot's own  ---
    ; --- 4th saved-background byte in the separate EXPLOSION_SAVED_   ---
    ; --- CM3 array.                                                   ---
    LD IX,ANIM_BASE    : LD B,0 : CALL UPDATE_ONE_EXPLOSION
    LD IX,ANIM_BASE+8  : LD B,1 : CALL UPDATE_ONE_EXPLOSION
    LD IX,ANIM_BASE+16 : LD B,2 : CALL UPDATE_ONE_EXPLOSION

    ; "これは3音使って良い" - ステージクリアジングル再生中(STAGE_CLEAR_
    ; ACT==1)はchAをBGMT_UPDATE_SC_A(BGM_TICK内)が専有するため、通常の
    ; SEドライバ(SOUND_UPDATE)自体を丸ごとスキップする(GFEnding[Stage2]
    ; のENDING_ACTと全く同じ考え方)。
    ; (2026-09-07、実機フィードバック対応、"以前にも同じミスがあって
    ; 止めたのに再発してる...飛び去るノイズ音がMission 2と出ている間
    ; 鳴りっぱなし"): 旧実装は"ACT!=1なら呼ぶ"だったため、ACTが1→2へ
    ; 遷移するまさにそのフレームで(MAINLOOP冒頭のフリーズゲートより
    ; 後、この行に到達する時点では既にACTは2)SOUND_UPDATEが誤って
    ; 呼ばれてしまい、DRAW_MISSION_SCREENが同じフレーム内で直前に
    ; 書いたR8=0(エンジン音の無音化)をSOUND_UPDATE自身の音量計算で
    ; 上書きしてしまっていた。次フレーム以降はACT>=2のフリーズゲートで
    ; SOUND_UPDATE自体が二度と呼ばれなくなるため、この1フレームで
    ; 書き込まれた非ゼロ値がR8に永久に固まって鳴り続けていた
    ; (round54で直したはずの症状の再発 - 原因は同じ現象への別経路)。
    ; "ACT==0の間だけ呼ぶ"(ACT>=1なら常にスキップ)へ変更して解消。
    LD A,(STAGE_CLEAR_ACT)
    OR A
    CALL Z,SOUND_UPDATE
    LD A,(PLAYER_FLYAWAY)
    OR A
    CALL NZ,PLAYER_PARTICLE_FADE

    ; --- enemy3: spawn attempt + advance/redraw all 64 pool slots ---
    CALL ENEMY3_TRY_SPAWN
    CALL ENEMY3_UPDATE_ALL
    ; --- enemy6 now spawns from the schedule (SPAWN_E6, dispatched   ---
    ; --- from SSC_FIRE like every other enemy) instead of its own    ---
    ; --- standalone timer - only the per-frame move/erase/redraw     ---
    ; --- sweep runs unconditionally here, same as ENEMY3_UPDATE_ALL. ---
    CALL ENEMY6_UPDATE_ALL
    ; --- unified sprite-enemy buffer: advance every active slot,   ---
    ; --- regardless of which movement algorithm (BEHAVIOR) it uses ---
    CALL ENEMY_POOL_UPDATE_ALL
    CALL UPDATE_EBULLET_ALL
    CALL ENEMY5_ANIM_STEP
    CALL CLOUD_UPDATE_ALL
    CALL EBUZ_UPDATE_ALL
    CALL UPDATE_EBUZ2_ALL
    ; (2026-09-14 follow-up、"まだEbuzが敵やボス居るのにでる 出ない場合
    ; もある てことは多分また初期化してねえだろ 何回やるんだよ"):
    ; round135follow-up16はSPAWN_SCHEDULE_CHECK自体の新規ディスパッチを
    ; BOSS_STATE==0の間だけに限定したが、EBUZ_CHECK_CHAIN_TRIGGERS
    ; (このすぐ下)は全く別の独立したチェーン進行ロジックで、同じガードを
    ; 経由していなかった。CHECK_BOSS_TRIGGERはEBUZ_ANY_ACTIVE(SLOT0/1の
    ; ACT・EXPL_QUEUE_COUNTが全て0)を含む「全プール空」を要求するため、
    ; ボスが実際にスポーンできる瞬間は必ずEbuz本体が消えた直後
    ; (EBUZ_SPAWN_STAGEはまだ1か2のまま=次インスタンスの発火待ち状態が
    ; 普通に残っている)- 同一フレーム内でCHECK_BOSS_TRIGGER(この関数より
    ; 前で実行済み)がボスを出現させた直後に、このEBUZ_CHECK_CHAIN_
    ; TRIGGERSが無条件に2体目/3体目を新規スポーンしてしまっていた
    ; (「初期化漏れ」ではなく、schedule dispatch側だけを塞いでEbuz自身の
    ; 独立トリガー経路を塞ぎ忘れていた、という同種の見落とし)。
    ; SPAWN_SCHEDULE_CHECK呼び出しと同じBOSS_STATE==0ガードをこちらにも
    ; 追加して解消(ボス戦中はチェーン進行ごと凍結、ボス出現時点で
    ; EBUZ_ANY_ACTIVE=falseだったことは保証済みなので、チェーンを止めても
    ; 画面上のEbuzが中途半端に消し残ることはない)。
    LD A,(BOSS_STATE)
    OR A
    CALL Z,EBUZ_CHECK_CHAIN_TRIGGERS

    ; ============================================================
    ; --- shots: advance 1 character (8 dots) per frame. Erasing  ---
    ; --- restores whatever the ground scroller currently shows   ---
    ; --- at that cell (if the shot is over the 4-row scroller),  ---
    ; --- or the sky blank otherwise - so the shot never leaves a ---
    ; --- hole in the terrain behind it.                          ---
    ; ============================================================
    CALL BULLET_IDLE_PAD
    LD HL,BULLET_STEP
    CALL BULLET_EACH

    CALL PLAYER_DAMAGE_CHECK
    CALL PLAYER_EXPL_UPDATE_ALL
    CALL EBUZ_EXPL_UPDATE_QUEUE

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

; round142(ROM budget): PLAYER_PARTICLE_SPAWN/PLAYER_PARTICLE_FADE moved
; to the tail of the file - see their own header comment there for why
; (ALIGN 256 cliff avoidance, no functional change; both are plain
; CALLed routines so their physical file position doesn't matter).

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

; Same 4-edge overlap shape as QUAD_HIT_TEST, but with the PLAYER's own
; hitbox as the fixed box instead of a *8-multiplied grid-aligned
; bullet - the player's own X/Y are free-moving pixels, not grid-
; aligned, so it can't reuse QUAD_HIT_TEST as-is.
; "自機のヒットボックスは下側8x8に 今のバリア左だな" - shrunk from the
; full 16x16 ship body down to just its own bottom-left 8x8 quadrant:
; (PLAYERX,PLAYERY)-(+7,+7) (was (PLAYERX,PLAYERY-8)-(+15,+15)).
; Input: D,E = the OTHER (enemy-side) box's top-left (pixel). Output:
; A=1 if it overlaps the player, else 0. Trashes A,H,L only - safe to
; CALL from inside a DJNZ B-counter scan loop without saving BC.
PLAYER_HIT_BOX8:
    LD A,(PLAYERX) : LD H,A
    LD A,(PLAYERY) : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,PHB8_NO
    LD A,D : ADD A,7
    CP H
    JR C,PHB8_NO
    LD A,L : ADD A,7
    CP E
    JR C,PHB8_NO
    LD A,E : ADD A,7
    CP L
    JR C,PHB8_NO
    LD A,1
    RET
PHB8_NO:
    XOR A
    RET

; Same as PLAYER_HIT_BOX8, but the other (enemy-side) box is 16x16
; instead of 8x8 (e.g. Enemy6). Input/output/trashes: same.
PLAYER_HIT_BOX16:
    LD A,(PLAYERX) : LD H,A
    LD A,(PLAYERY) : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,PHB16_NO
    LD A,D : ADD A,15
    CP H
    JR C,PHB16_NO
    LD A,L : ADD A,7
    CP E
    JR C,PHB16_NO
    LD A,E : ADD A,15
    CP L
    JR C,PHB16_NO
    LD A,1
    RET
PHB16_NO:
    XOR A
    RET

; 実機フィードバック"それも先端の1pxで良いかな その方が少しは速いし"
; (直前の16幅x2高判定へのさらなる追加フィードバック) - 幅・高さとも
; 撤廃し、真の単一ピクセル点内包判定へ縮小。点はEBULLETの進行方向
; (常に左)における先端、かつ実際の絵(EBULLET_PATTERN、スプライト
; 原点+2行目)に合わせた(D, E+2) - Dはスプライト原点Xそのもの
; (左へ移動するため原点Xが既に先端)。
; Input/output/trashes: 従来と同じ(D,E=EBULLETのスプライト原点、その
; まま渡してよい - 内部でYへ+2する)。
PLAYER_HIT_BOX_EBULLET:
    LD A,E : ADD A,2 : LD E,A
    LD A,(PLAYERX) : LD H,A
    LD A,(PLAYERY) : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,PHBEB_NO
    LD A,D
    CP H
    JR C,PHBEB_NO
    LD A,L : ADD A,7
    CP E
    JR C,PHBEB_NO
    LD A,E
    CP L
    JR C,PHBEB_NO
    LD A,1
    RET
PHBEB_NO:
    XOR A
    RET

; Sets REDRAW_SRC_PATTERN from a 1,2,3,2-cycle sequence index (0-3),
; via ENEMY_ANIM_SEQ_TABLE. Input: HL = address of the sequence-index
; byte. Trashes A,DE,HL.
SET_REDRAW_SRC_FROM_SEQ:
    LD A,(HL)
    ADD A,A
    LD E,A : LD D,0
    LD HL,ENEMY_ANIM_SEQ_TABLE
    ADD HL,DE
    LD A,(HL) : INC HL : LD H,(HL) : LD L,A
    LD (REDRAW_SRC_PATTERN),HL
    RET

; Rewrites one unit's 32-byte 16x16 sprite pattern to match its
; current TOP/BOT alive flags: top-left shows the REDRAW_SRC_PATTERN
; glyph if TOP is alive (else blank), bottom-right shows it if BOT
; is alive (else blank); bottom-left/top-right are always blank.
; Input: HL = VRAM address of this unit's 32-byte pattern block,
;        DE = address of this unit's TOP alive-flag byte,
;        IX = address of this unit's BOT alive-flag byte.
; Caller must set REDRAW_SRC_PATTERN first (see SET_REDRAW_SRC_
; FROM_SEQ) - it's shared/global state, not an input register, since
; none were free to spare for it.
; Trashes A,B,HL.
REDRAW_UNIT_PATTERN:
    LD A,L
    DI
    OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h
    OUT (99h),A
    NOP
    NOP
    LD A,(DE)
    OR A
    EI
    JR Z,RU_TL_BLANK
    LD HL,(REDRAW_SRC_PATTERN) : LD B,8
RU_TL_LOOP:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    INC HL : DJNZ RU_TL_LOOP
    JR RU_BL
RU_TL_BLANK:
    LD B,8
RU_TL_BLANK_LOOP:
    DI
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ RU_TL_BLANK_LOOP
RU_BL:
    LD B,8
RU_BL_LOOP:
    DI
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ RU_BL_LOOP
    LD B,8
RU_TR_LOOP:
    DI
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DJNZ RU_TR_LOOP
    LD A,(IX+0)
    OR A
    JR Z,RU_BR_BLANK
    LD HL,(REDRAW_SRC_PATTERN) : LD B,8
RU_BR_LOOP:
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    INC HL : DJNZ RU_BR_LOOP
    RET
RU_BR_BLANK:
    LD B,8
RU_BR_BLANK_LOOP:
    DI
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
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
; --- round69 follow-up: sets ANIM_TMP_ROW/ANIM_TMP_COL for this slot's ---
; --- row (IX+3) and column (IX+4) minus a fixed compile-time offset   ---
; --- (0/1/2/3, one entry point each), clamped at 0 rather than        ---
; --- wrapping - the only 4 offsets the 3-frame animation ever needs   ---
; --- (frame1=C only, frame2=C-2..C, frame3=C-3..C-1). Clobbers A.     ---
EXP_POS0:
    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : LD (ANIM_TMP_COL),A
    RET
EXP_POS1:
    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : OR A : JR Z,EP1_Z : DEC A
EP1_Z:
    LD (ANIM_TMP_COL),A
    RET
EXP_POS2:
    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : CP 2 : JR NC,EP2_S : XOR A : JR EP2_D
EP2_S:
    SUB 2
EP2_D:
    LD (ANIM_TMP_COL),A
    RET
EXP_POS3:
    LD A,(IX+3) : LD (ANIM_TMP_ROW),A
    LD A,(IX+4) : CP 3 : JR NC,EP3_S : XOR A : JR EP3_D
EP3_S:
    SUB 3
EP3_D:
    LD (ANIM_TMP_COL),A
    RET

; Returns in A the background that should show at (ANIM_TMP_ROW,
; ANIM_TMP_COL) right now - BLANKCODE if above the 4-row ground
; scroller, else the NAMEBUF mirror (same rule WRITE_ANIM_CELL itself
; uses to decide whether a cell needs its NAMEBUF mirror updated too).
; Clobbers H,L,DE (not A - the return value).
EXP_READ_BG:
    LD A,(ANIM_TMP_ROW) : CP GROUND_ROW0
    JR C,ERB_SKY
    SUB GROUND_ROW0
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD L,A : LD H,0
    LD DE,NAMEBUF
    ADD HL,DE
    LD A,(ANIM_TMP_COL) : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    RET
ERB_SKY:
    LD A,BLANKCODE
    RET

; Input: D,E = destroyed quadrant's X,Y (pixel). Picks the next
; explosion-animation slot (round robin among 3, B=its index 0-2),
; snapshots the background at all 4 columns [C..C-3] the animation
; will ever touch (frame1 only ever draws column C; frame2 widens to
; C-2..C; frame3 shifts to C-3..C-1 - see UPDATE_ONE_EXPLOSION), shows
; frame1, and plays the destroy sound. Ground-row kills get the exact
; same tiles/color as sky kills now (see EXP_CODE_THIN's own comment).
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
    LD IX,ANIM_BASE : LD B,0
    JR TE_ADVANCE_RR
TE_PICK1:
    LD IX,ANIM_BASE+8 : LD B,1
    JR TE_ADVANCE_RR
TE_PICK2:
    LD IX,ANIM_BASE+16 : LD B,2
TE_ADVANCE_RR:
    LD A,(ANIM_RR)
    INC A
    CP 3
    JR C,TE_RR_OK
    XOR A
TE_RR_OK:
    LD (ANIM_RR),A

    ; if the chosen slot was still mid-animation, restore ALL 4 of its
    ; old columns now (using its still-intact old ROW/COL/SAVED*
    ; fields) before we overwrite it below - simpler than figuring out
    ; exactly which columns its current frame still has drawn, and
    ; just as correct (a column already showing its own background
    ; gets a harmless no-op rewrite).
    LD A,(IX+0)
    OR A
    JR Z,TE_NORESTORE
    PUSH DE
    CALL EXP_POS0 : LD A,(IX+5) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS1 : LD A,(IX+6) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS2 : LD A,(IX+7) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS3
    LD A,B : LD E,A : LD D,0
    LD HL,EXPLOSION_SAVED_CM3
    ADD HL,DE
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    POP DE
TE_NORESTORE:

    LD A,E : SRL A : SRL A : SRL A : LD (IX+3),A   ; ROW
    LD A,D : SRL A : SRL A : SRL A : LD (IX+4),A   ; COL (=C)

    CALL EXP_POS0 : CALL EXP_READ_BG : LD (IX+5),A
    CALL EXP_POS1 : CALL EXP_READ_BG : LD (IX+6),A
    CALL EXP_POS2 : CALL EXP_READ_BG : LD (IX+7),A
    CALL EXP_POS3 : CALL EXP_READ_BG
    PUSH AF
    LD A,B : LD E,A : LD D,0
    LD HL,EXPLOSION_SAVED_CM3
    ADD HL,DE
    POP AF
    LD (HL),A

    LD A,1 : LD (IX+1),A                ; FRAME=1
    LD A,ANIM_FRAME_LEN : LD (IX+2),A   ; TIMER
    LD A,1 : LD (IX+0),A                ; ACTIVE=1

    CALL EXP_POS0
    LD A,EXP_CODE_THIN : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL

    CALL SOUND_DESTROY
    RET

; Advances one frame of the explosion animation at IX (slot base),
; using B=this slot's index (0-2, for addressing EXPLOSION_SAVED_CM3).
; Frame layout (see ExpAnim_24x24.json / the GIF preview shown before
; implementing): frame1 draws EXP_CODE_THIN at column C only; frame2
; widens to 3 columns (C-2,C-1,C) = THIN,THICK,THIN; frame3 shifts to
; (C-3,C-2,C-1) but only draws THIN at the 2 outer ones, leaving its
; own middle column blank (restored to background) - frames are shown
; one at a time, never composited. Called once per frame from MAINLOOP
; for each of the 3 slots; no-ops immediately if this slot is inactive.
UPDATE_ONE_EXPLOSION:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IX+2)
    DEC A
    LD (IX+2),A
    RET NZ
    LD A,(IX+1)
    CP 1
    JR Z,UOE_ENTER_FRAME2
    CP 2
    JR Z,UOE_ENTER_FRAME3
    ; FRAME==3 just finished -> restore all 4 columns, deactivate
    CALL UOE_RESTORE_ALL
    XOR A : LD (IX+0),A
    RET
UOE_ENTER_FRAME2:
    LD A,2 : LD (IX+1),A
    LD A,ANIM_FRAME_LEN : LD (IX+2),A
    CALL EXP_POS2 : LD A,EXP_CODE_THIN  : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS1 : LD A,EXP_CODE_THICK : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS0 : LD A,EXP_CODE_THIN  : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    RET
UOE_ENTER_FRAME3:
    LD A,3 : LD (IX+1),A
    LD A,ANIM_FRAME_LEN : LD (IX+2),A
    ; column C (offset0) was drawn by frame2 but frame3 doesn't touch it
    CALL EXP_POS0 : LD A,(IX+5) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    ; column C-2 (offset2) was frame2's own THICK center - frame3's own
    ; middle column stays blank, so restore it
    CALL EXP_POS2 : LD A,(IX+7) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    ; frame3's own 2 outer tiles
    CALL EXP_POS3 : LD A,EXP_CODE_THIN : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS1 : LD A,EXP_CODE_THIN : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    RET

; Restores all 4 columns (C,C-1,C-2,C-3) to their pre-explosion
; background - called once when frame3's own duration expires.
UOE_RESTORE_ALL:
    CALL EXP_POS0 : LD A,(IX+5) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS1 : LD A,(IX+6) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS2 : LD A,(IX+7) : LD (ANIM_TMP_VAL),A : CALL WRITE_ANIM_CELL
    CALL EXP_POS3
    LD A,B : LD E,A : LD D,0
    LD HL,EXPLOSION_SAVED_CM3
    ADD HL,DE
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    JP WRITE_ANIM_CELL

; Writes ANIM_TMP_VAL to the nametable cell at (ANIM_TMP_ROW,
; ANIM_TMP_COL): updates the NAMEBUF mirror too if that row is
; within the 4-row ground scroller. Trashes A,H,L,DE.
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
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(ANIM_TMP_VAL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

; PSG (AY-3-8910-compatible) sound effects: 実機フィードバック対応
; ("そもそもchB、Cは空けてあってSE類はchAのみで鳴らすはず"、確認:
; "SEの被りで上書きされるのは問題ない BCはBGM専用 で、ノイズは別ch
; PSGは4音同時に鳴らせる トーンでノイズは消えない") - 全SE(破壊音+
; エンジン音=ノイズ、ショット/ポッド発射/ポッドヒット/バリアヒット=
; トーン)をチャンネルAへ統合。AY-3-8910はチャンネルごとにトーン/
; ノイズの有効ビットが独立している(INITのR7=0B0h参照)ため、同じ
; チャンネルAでトーンとノイズを同時に有効化しても互いを消し合わない -
; 「トーンでノイズは消えない」という前提通り。SND_TIMER(ノイズ側=
; 破壊音+エンジン音)/SND_TONE_TIMER(トーン側=ショット/ポッド発射/
; ポッドヒット、いずれも単純な1フレーム1減衰でゲート無し)/
; SND_BARRIER_DUTY_TIMER(バリアヒット専用の2連バズ)の3本がそれぞれ
; 独立に減衰しつつ、R8(チャンネルA音量)は毎フレームSOUND_UPDATEが
; 優先順位(バリアの2連バズ>単純トーン>ノイズ)で1つだけ選んで書く -
; 複数が同時に非0の場合、低優先度側はその瞬間R8には反映されないが
; カウントダウン自体は止まらない(短時間の重なりは自然に上書き/
; 減衰していく、"被りで上書きされるのは問題ない"を踏まえた設計)。
; チャンネルB/CはこれでBGM_TICK以外一切書き込まなくなった(完全に
; BGM専用)。
;
; round32 (ported from Stage2 - "ステージ1もデューティ比操作を適用"):
; ノイズ側(SND_TIMER)の出力はTICK低位ビットで1:1デューティゲート
; ("デューティ比1:1で減衰しながらボリューム半分かOFFをまぜてくれ
; そうすればブリブリって音になるはず")。トーン側(SND_TONE_TIMER)は
; 従来通りゲート無し(移設前の音色を一切変えないための選択)。
; round40: every PSG_ADDR/PSG_DATA select+write pair below is now DI/EI-
; wrapped, on top of the existing "protects against the BIOS's own
; keyboard/joystick PSG scan" rationale above - BGM_TICK (installed
; into H.TIMI this round) does its own PSG_ADDR-select/PSG_DATA-write
; pairs on R2-R5/R9/R10 every real VBlank, so an H.TIMI interrupt
; landing between either OUT here would leave the wrong PSG register
; selected for whichever write resumes first, same race Stage2's own
; Round38 BGM driver already documented and fixed this same way.
; "SE優先でショットは消す仕様に SE発声中はショット音は鳴らない" -
; SND_TONE_IS_SE参照(EQU直前のコメント参照)。POD_HIT/POD_FIREがまだ
; 減衰しきっていない間はショット要求そのものを無視する(PSG・タイマー
; いずれにも触れない、SEの減衰は妨げない)。
;
; 実機フィードバック対応("SEがほぼ鳴らずショット音が残る"): 当初の
; SND_TONE_IS_SEチェックだけでは不十分だった実バグを発見・修正。
; SOUND_BARRIER_HIT(バリアヒット、SND_BARRIER_DUTY_TIMERで管理・
; SOUND_UPDATEで最優先のSE)はSHOT/POD_HIT/POD_FIREと全く同じ
; チャンネルAトーン周期レジスタ(R0/R1、PSG_ADDR=0/1)を直接書く - この
; ガードがSND_TONE_TIMER/SND_TONE_IS_SEしか見ていなかったため、
; バリアヒットの減衰中(SND_BARRIER_DUTY_TIMER!=0)でも無関係な
; ショット要求がR0/R1を横取りして上書きしてしまい、SOUND_UPDATE側は
; 変わらずバリアの音量エンベロープ(最優先)を出力し続けるため
; 「バリアのリズムでショットの音程が鳴る」という壊れた合成音になって
; いた(ユーザー報告の"SEが鳴らずショットが残る"の実体)。修正:
; SND_BARRIER_DUTY_TIMERが非0の間もショット要求を握りつぶす。
; round135follow-up12("敵が爆発や発射音を発声中は自機ショット音で
; 上書きしないように 何度指示しても出来なかった"): 上記2件(バリア/
; POD)はいずれもトーン側(SND_TONE_TIMER)の内輪の優先度調整で、SOUND_
; DESTROY(破壊音)・SOUND_EBUZ_FIRE(敵の発射音)というノイズ側
; (SND_TIMER)のSEは一度もこのガードの対象になっていなかった。
; SOUND_UPDATEの優先順位(バリア>トーン>ノイズ、上記コメント参照)は
; ノイズ側より常にトーン側を優先してR8(チャンネルA音量、両者で共有)に
; 書くため、破壊音/敵弾発射音の減衰中にショットを撃つと、ノイズ生成
; 自体は止まらないもののR8がショット側の速い減衰エンベロープに
; 乗っ取られ、結果的に敵音が本来の減衰より早く・小さく聞こえてしまう
; (「自機ショット音で上書きされる」の実体、過去の指示はトーン側だけの
; 対処[SND_TONE_TIMER/SND_TONE_IS_SE/SND_BARRIER_DUTY_TIMER]に終始して
; おりノイズ側は一度も対象にしていなかったため直っていなかった)。
; 修正: SND_TIMERが非0の間(=破壊音か敵弾発射音が減衰中)もショット
; 要求そのものを握りつぶす、既存の3つと全く同じ考え方。
SOUND_SHOT:
    ; "マテリアライズ中は自機ショット音は停止" - BOSS_STATE==1の間だけ
    ; 抑制(ボス本体の点滅タイル演出中、Stage2のBOSS_MATERIALIZE_ACT
    ; ガードと同じ考え方)。
    LD A,(BOSS_STATE)
    CP 1
    RET Z
    LD A,(SND_BARRIER_DUTY_TIMER)
    OR A
    RET NZ                     ; barrier-hit SE (top priority) still decaying -> drop
    LD A,(SND_TIMER)
    OR A
    RET NZ                     ; enemy noise SE (destroy/Ebuz-fire) still decaying -> drop
    LD A,(SND_TONE_TIMER)
    OR A
    JR Z,SS_FIRE               ; timer idle -> always OK to fire
    LD A,(SND_TONE_IS_SE)
    OR A
    RET NZ                     ; SE still decaying -> drop the shot request
SS_FIRE:
    DI
    LD A,0 : OUT (PSG_ADDR),A
    LD A,30 : OUT (PSG_DATA),A    ; channel A tone period -> bright "chun" pitch
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A      ; coarse tune bits = 0
    EI
    LD A,12 : LD (SND_TONE_TIMER),A
    XOR A : LD (SND_TONE_IS_SE),A
    RET
SOUND_DESTROY:
    DI
    LD A,6 : OUT (PSG_ADDR),A
    LD A,20 : OUT (PSG_DATA),A    ; low, coarse noise period = short "boom"
    EI
    LD A,15 : LD (SND_TIMER),A
    RET

; Ebuz's own rapid-fire "machine gun" SE (round135follow-up4,
; "Ebuzの発射音欲しい マシンガンみたいなやつ...音は2番で" - ユーザーが
; "Ebuz Fire Bench"の6候補から選んだ candidate 2「ディープ・スタッター」
; [NP=14、frames=[15,12,8,4]] をそのまま実装)。既存のSOUND_DESTROYと
; 全く同じ構造(channel Aのノイズジェネレータ、SND_TIMERの-1/frame
; 直線減衰+CALC_NOISE_GATE_VOLUMEのTICK AND 1デューティゲート)を、
; 周期だけ20→14(候補のNP)に変えて再利用 - 試聴ページの手書きenvelope
; [15,12,8,4]自体はこのエンジンには無い専用テーブルを要求するが、
; EBUZ_FIRE_INTERVAL(2フレーム毎)の頻度で毎回SND_TIMERが15へ再武装
; されるため、実際に鳴る音はエンジン本来の1:1デューティゲート(30Hz)が
; そのまま「ダダダダ」という機関銃的な質感を作り出す - 候補名
; 「ディープ・スタッター」の"スタッター"要素はこのデューティゲート
; そのものが担う形になり、専用envelopeテーブルの新設は不要と判断。
SOUND_EBUZ_FIRE:
    DI
    LD A,6 : OUT (PSG_ADDR),A
    LD A,14 : OUT (PSG_DATA),A    ; noise period 14 - candidate2 "ディープ・スタッター"
    EI
    LD A,15 : LD (SND_TIMER),A
    RET

; metallic "kin" ping for a non-lethal pod hit - reuses channel A's
; tone generator (same as the player's own shot) but at a much higher
; pitch so it reads as a distinct sound.
SOUND_POD_HIT:
    DI
    LD A,0 : OUT (PSG_ADDR),A
    LD A,10 : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    EI
    LD A,10 : LD (SND_TONE_TIMER),A
    LD A,1 : LD (SND_TONE_IS_SE),A  ; SE優先: これが減衰しきるまでSOUND_SHOTは無視される
    RET

; "サウンドはブブって2回低音のデューティ比25％最大音量で" - reuses
; channel A's tone generator (shared with SOUND_SHOT/SOUND_POD_HIT/
; SOUND_POD_FIRE, same "one sound at a time per generator" tradeoff
; already accepted throughout this file) at a low period, gated through
; SND_BARRIER_DUTY_TIMER (see SOUND_UPDATE): an 8-frame window with
; exactly 2 full-volume(15) frames (at counter 8 and 4) = 2/8 = 25%
; duty, giving 2 short low buzzes.
SOUND_BARRIER_HIT:
    DI
    LD A,0 : OUT (PSG_ADDR),A
    LD A,132 : OUT (PSG_DATA),A   ; channel A tone period fine byte
    LD A,1 : OUT (PSG_ADDR),A
    LD A,3 : OUT (PSG_DATA),A     ; coarse byte -> period=900, deep low pitch
    EI
    LD A,8 : LD (SND_BARRIER_DUTY_TIMER),A
    RET

SOUND_POD_FIRE:
    DI
    LD A,0 : OUT (PSG_ADDR),A
    LD A,244 : OUT (PSG_DATA),A   ; channel A tone period fine byte
    LD A,1 : OUT (PSG_ADDR),A
    LD A,2 : OUT (PSG_DATA),A     ; coarse byte -> period=756, much lower "don"
    EI
    LD A,15 : LD (SND_TONE_TIMER),A
    LD A,1 : LD (SND_TONE_IS_SE),A  ; SE優先: これが減衰しきるまでSOUND_SHOTは無視される
    RET
; out: A = this frame's noise-side channel-A output volume - duty-cycle
; gated (silent if TICK's own low bit is set, else the raw SND_TIMER
; envelope). Pure function, no side effects (doesn't touch the PSG or
; step SND_TIMER itself) - kept standalone specifically so it's
; directly testable without needing to observe an actual PSG register
; write (z80emu.py has no PSG emulation at all, same reasoning as
; Stage2's own SOUND_CALC_NOISE_GATE_VOLUME).
CALC_NOISE_GATE_VOLUME:
    LD A,(TICK) : AND 1
    JR NZ,CNGV_SILENT
    LD A,(SND_TIMER)
    RET
CNGV_SILENT:
    XOR A
    RET

; out: A = this frame's duty-gated channel-A volume while SND_BARRIER_
; DUTY_TIMER is active (15 on the 2 "buzz" frames - counter values 8 and
; 4 out of the 8-frame window = 2/8 = 25% duty - else 0). Pure function,
; no side effects (doesn't touch the PSG or SND_BARRIER_DUTY_TIMER
; itself) - kept standalone specifically so it's directly testable
; without needing to observe an actual PSG register write, same
; reasoning as CALC_NOISE_GATE_VOLUME above.
CALC_DUTY_GATE_VOLUME:
    LD A,(SND_BARRIER_DUTY_TIMER)
    CP 8
    JR Z,CDGV_ON
    CP 4
    JR Z,CDGV_ON
    XOR A
    RET
CDGV_ON:
    LD A,15
    RET

; channel A now carries every SE this file has (see the long comment
; above SOUND_SHOT) - R8 is written exactly once per frame, picking
; whichever of the 3 independent envelopes (SND_BARRIER_DUTY_TIMER >
; SND_TONE_TIMER > SND_TIMER, highest priority first) is currently
; active; a timer left "masked" behind a higher-priority one keeps
; counting down in the background regardless (same "one at a time,
; collisions just resolve by priority/overwrite" tradeoff already
; documented above). Channels B/C are now BGM_TICK's alone - this
; routine never touches R9/R10 at all.
SOUND_UPDATE:
    LD A,(SND_BARRIER_DUTY_TIMER)
    OR A
    JR Z,SU_CHECK_TONE
    CALL CALC_DUTY_GATE_VOLUME
    LD B,A
    DI
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    EI
    LD A,(SND_BARRIER_DUTY_TIMER) : DEC A : LD (SND_BARRIER_DUTY_TIMER),A
    RET
SU_CHECK_TONE:
    LD A,(SND_TONE_TIMER)
    OR A
    JR Z,SU_NOISE
    LD B,A
    DI
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    EI
    DEC A
    LD (SND_TONE_TIMER),A
    RET
SU_NOISE:
    CALL CALC_NOISE_GATE_VOLUME
    LD B,A
    DI
    LD A,8 : OUT (PSG_ADDR),A     ; R8 = channel A volume (duty-cycle gated)
    LD A,B : OUT (PSG_DATA),A
    EI
    LD A,(SND_TIMER)
    OR A
    RET Z
    DEC A
    LD (SND_TIMER),A
    RET

; ---------- BGM driver (Vsync駆動、Round40 "タイトル含めて各ステージに
; ドライバを配置しRAMにコピーしてステージスタート") ----------
; tools/stage2_combined/combined_test.asmの同名ドライバと完全に同型
; (chB/chC独立ポインタ・タイマー、H.TIMI(0FD9Fh)フック、詳細な設計理由は
; そちらの長いコメント参照)。実機フィードバック対応("そもそもchB、Cは
; 空けてあってSE類はchAのみで鳴らすはず")で全SEをチャンネルAへ統合
; したことにより、このファイルがStage2と違って抱えていた「チャンネル
; B/Cを既存SFXと共有している」という制約自体が解消済み - よって
; BGMT_UPDATE_B/CはStage2/Titleと同じ「SFX優先の譲渡チェック無し、
; 常にBGM側が無条件でR9/R10を書く」設計にできる(過去に存在した
; SND_TIMER_B/SND_TIMER_C/SND_C_DUTY_TIMERへのチェックは全廃止)。
;
; 「ドライバ自体は各バンクに配置しRAMにコピーしてステージスタート」の
; うち後半(バンク切替・RAMコピー)はこのファイルでは行わない: この
; ファイルは元々ASCII16のバンク切替を一切必要としない単純な32KB
; プログラムとして書かれており(Comb ROM内でのみbank2/3として存在、
; 単体版ROMは廃止済み)、既存の大量の回帰テスト(tools/verify_*.py)が
; フラットな64KBメモリ(バンク概念なし)でこのファイルを直接アセンブル・
; 実行する前提になっている - このファイル自身に新規のバンク切替命令を
; 追加すると、それらのテストのフラットメモリモデル上では「ROM領域への
; 書き込みがそのままそのアドレスのコード/データを破壊する」という
; 実機と異なる副作用を引き起こしかねない。そこで、Title(このファイルへ
; トランポリンする直前に必ず一度だけ起動される)が起動時に一度だけ
; ALONE_FIGHTERをRAM(BGM_B_BASE/BGM_C_BASE、tools/title_screen/
; title_test.asmのINIT_BGMコメント参照)へコピー済みという前提のもと、
; このファイルのINIT_BGMはそのRAMを読むだけにしてある。R7ミキサーは
; 既にINIT側で0B0h(tone A/B/C enable、noise A enable)を書き済み
; (このファイル自身の恒久設定、SOUND_UPDATE同様1度だけ)なのでここでは
; 触らない。
HTIMI_HOOK        EQU 0FD9Fh
BGM_NOTE_REST     EQU 0FFh
BGM_LOOP_MARK     EQU 0FEh
; (2026-09-08、GAME_OVERジングル追加で新規使用) 一度きり再生して以後
; 無音を保持し続ける終端マーク - Stage2のBGM_END_MARKと同じ値
; (tools/bgm_data/midi_to_psg.pyのEND_MARKと一致させること)。
BGM_END_MARK      EQU 0FDh
; (2026-09-06、TryZ/GFEnding追加でNUM_NOTES35→60へ拡張、周期テーブルが
; 伸びた分だけ以下のRAMオフセットが後方へシフト - Titleが書き込む
; アドレスと一致させること、tools/title_screen/title_test.asmの同名
; EQU参照)
BGM_PERIOD_LO_RAM EQU 0C000h
BGM_PERIOD_HI_RAM EQU 0C03Ch
BGM_B_BASE        EQU 0C078h    ; ALONE_FIGHTER track0(chB)先頭 - Titleが埋める
BGM_C_BASE        EQU 0C267h    ; ALONE_FIGHTER track1(chC)先頭 - Titleが埋める
; (2026-09-06、CONTROL_OFFSET拡張0x800→0x900に伴い0xC800→0xC900へ
; シフト - bgm_bank_gen.pyのCONTROL_OFFSET自身のコメント[自己発見RAM
; 衝突バグの経緯]参照。Titleが書き込むアドレスと一致させること)
BGM_B_PTR   EQU 0C900h
BGM_C_PTR   EQU 0C902h
BGM_B_TIMER EQU 0C904h
BGM_C_TIMER EQU 0C905h
BGM_B_REST  EQU 0C906h    ; 0=音符が鳴っている行/非0=休符行
BGM_C_REST  EQU 0C907h

; 実機フィードバック対応その3("BGMが1chしかなってないと言うか 恐らく
; エンベロープの影響で発音できてないな HWエンベロープはコントロール
; 不能と判断 ソフトに切り替える...試聴ツールで決める これなら
; デューティ比にも対応できるからな"): AY-3-8910本来のHWエンベロープ
; ジェネレータ(R11-13)はチップ全体で1個しか無い共有リソースのため、
; chB/chCが独立した形・速度を同時に持てなかった(実機で「1chしか
; 鳴っていない」結果になった実体)。ここからは完全にソフトウェア側
; (BGM_TICK自身が毎tickテーブルを読んでR9/R10へ書く)でエンベロープを
; 実現する方式に切り替え、チャンネルごとに完全に独立した形・速度を
; 持てるようにした。試聴ツール(PSG BGM Bench)でユーザーが選定:
; **パート1(chB)=BELL形状+デューティ比50%、パート2(chC)=LINEAR形状+
; デューティOFF**。
;
; 各形状は「音符の頭(NEWROW)からの経過tick数」だけを見るテーブル
; ルックアップとして実装(音符自身の長さには依存しない、ピアノや
; 弦楽器が実際の物理時間で減衰するのと同じ考え方) - BGM_ENV_*_TABLE
; は(level,duration)の2byteエントリを16個並べたRLE(run-length
; encoding)形式。この行の再生自体が1tick分の消費になるという
; round40以来の慣習(BGMT_UB/UC_NEWROWのoff-by-one修正と同じ考え方)
; を各エントリの読み込みでも踏襲し、durationフィールドは「このtick
; 自体を含めた合計保持tick数」として格納・DEC Aしてから保持カウンタへ
; 積む。最終(16番目)のエントリは(level=0,duration=0)の番兵で、
; インデックスがここに達したら以後は永久にこの値を保持し続ける
; (durationを一切減算しない特別扱い)。
;
; HWエンベロープと違い、共有ジェネレータの制約自体が存在しないため
; 「chB駆動/chC追従」のような非対称設計は不要 - 両チャンネルとも
; 全く同じ構造の独立したロジックを持つ(唯一の違いはchBだけデューティ
; ゲートを重ねる点)。この設計はまた「毎フレームPSGに書き込むとHWが
; アタックだけ繰り返される」というHWエンベロープ特有の罠からも
; 無縁 - 音量そのものをソフトウェアが完全に管理しているため、毎tick
; 遠慮なくR9/R10へ書いてよい。
BGM_ENV_LAST_INDEX EQU 15     ; テーブルは0-15の16エントリ、15番目が番兵(hold forever)
BGM_B_DUTY_MASK    EQU 1      ; パート1: デューティ比50%(1/2、位相の下位1bitでON/OFF)
; 実機フィードバック"BGM音量を下げたいが現在は最大か?"→"中程度下げる
; (-4、ピーク11)": R9/R10へ書く直前に一律で減算(0未満はクランプ)。
BGM_VOL_ATTEN      EQU 4
BGM_B_ENV_LEVEL  EQU 0C908h
BGM_B_ENV_IDX    EQU 0C909h
BGM_B_ENV_CD     EQU 0C90Ah
BGM_B_DUTY_PHASE EQU 0C90Bh
BGM_C_ENV_LEVEL  EQU 0C90Ch
BGM_C_ENV_IDX    EQU 0C90Dh
BGM_C_ENV_CD     EQU 0C90Eh

; 実機フィードバック対応("ステージ1ボスもBGMをTryZに マテリアライズ
; 終了後に再生...マテリアライズに入る前にそれまでのBGMは停止"):
; Stage1はStage2と違いバンク切替を自前で一切行わない設計(単体版ROM
; 廃止済み+tools/verify_*.py群がバンク概念の無いフラット64KBメモリ
; 前提という制約 - src/CYBER SHMUP.asm自身のBGM設計の元々のコメント
; 参照)。この制約を維持したまま2曲目(TryZ)を追加するため、TryZの
; chB/chC生データもTitleが起動時に一度だけ(ALONE_FIGHTERと同じ要領で)
; RAMへコピーしておき、Stage1側はアドレスを差し替えるだけで済むように
; した - 新規バンク切替コードはStage1に一切追加していない。
; RAM配置: 制御ブロック(0xC900-0xC90E)の直後、シンボルテーブル実測で
; 0xE000(TICK)まで空きと確認済みの領域(BGM_MUTED 1byte+TryZ chB/chC
; 814byte+ループ復帰先2ch分)。
BGM_MUTED         EQU 0C90Fh
BGM_TRYZ_CHB_BASE EQU 0C910h    ; Titleが埋める(chB melody, 741byte)
BGM_TRYZ_CHC_BASE EQU 0CBF5h    ; Titleが埋める(chC bass, 73byte) - 0xC910+741
; Stage2のBGM_C_LOOP_BASEと全く同じ理由(TryZのchB長がALONE_FIGHTERとは
; 違うため、chCのループ復帰先アドレスも曲によって異なる) - ただしStage1
; はTryZをALONE_FIGHTERと別アドレスに置く設計(上書きしない)ため、chB
; 側もループ復帰先が曲によって変わる。両方ともRAM変数化する。
BGM_B_LOOP_BASE   EQU 0CC3Eh
BGM_C_LOOP_BASE   EQU 0CC40h

; (2026-09-06、"ではステージ1と2のスコアを加算して...これをステージ
; クリアで流して 3音使って良いんで"): StageClear.mid(Galaxy Force、
; Stage Clearジングル、約8.27秒)から3パート抽出(melody=chB/bass=chC/
; harmony=chA、tools/bgm_data/midi_to_psg.load_stage_clear_parts()参照)。
; TryZと全く同じ理由・同じ設計(Stage1は自前でバンク切替をしない制約 -
; 上記BGM_TRYZ_CHB/CHC_BASE自身のコメント参照)でTitleが起動時に別
; アドレスへコピー済みという前提。LOOP_MARK方式(chB/Cの既存実装
; BGMT_UPDATE_B/Cをそのまま再利用でき、新規のEND_MARK対応コードが
; 不要になる)だが、下記STAGE_CLEAR_ACT/SC_VBLANK_COUNTの実時間タイマー
; が曲の総長ちょうどでStage2へのバンク切替へ進むため、実際にループ端
; へ到達することはまず無い設計。
; (2026-09-06、実機フィードバック"クリアBGMの最初の方って多分無音に
; なってると思うんで発音までの無音部分をカットして"対応): 3パート
;共通の先頭無音(頭出し前の無音区間、3パートの最小値)をPython側で
; トリムした結果、chC(bass)/chA(harmony)がそれぞれ2byte(先頭REST行
; 1行分)短縮された(chBは先頭REST行の長さが縮んだだけで行自体は残る
; ため無変化) - 以下のアドレスは全てこの新しいサイズに基づく。
STAGE_CLEAR_CHB_BASE EQU 0CC42h  ; Titleが埋める(chB melody, 71byte)
STAGE_CLEAR_CHC_BASE EQU 0CC89h  ; Titleが埋める(chC bass, 119byte) - 0xCC42+71
STAGE_CLEAR_CHA_BASE EQU 0CD00h  ; Titleが埋める(chA harmony, 79byte) - 0xCC89+119

; chA(harmony、3声目)はStage1にとって完全に新規のBGM専用制御フィールド
; ("これは3音使って良い" - GFEnding[Stage2]と同じ考え方、下記
; STAGE_CLEAR_ACTが1の間だけ通常のSEドライバ[SOUND_UPDATE]自体を
; MAINLOOP側で丸ごとスキップするため競合しない - 自機は既にflyaway
; 完了・画面外でSEが鳴る場面自体が無い)。envelopeはLINEAR形状を流用
; (chCと同型、デューティ無し)。
BGM_A_PTR       EQU 0CD4Fh
BGM_A_TIMER     EQU 0CD51h
BGM_A_REST      EQU 0CD52h
BGM_A_ENV_LEVEL EQU 0CD53h
BGM_A_ENV_IDX   EQU 0CD54h
BGM_A_ENV_CD    EQU 0CD55h

; ステージクリア演出の状態機械: 0=未発生/1=ジングル再生中/2=完了
; (build_full_rom.pyのMAINLOOP_PATCH参照 - Comb限定でStage1→Stage2の
; バンク切替トリガーをPLAYER_FLYAWAY==2から下記STAGE_CLEAR_ACT==2へ
; 差し替える)。実時間クロックはSC_VBLANK_COUNT(BGM_TICK内、実VBlank
; 駆動 - MAINLOOPのTICKはfree-running設計で実時間に対応しない、
; GFEnding[Stage2]のVBLANK_COUNTと全く同じ考え方)。
STAGE_CLEAR_ACT         EQU 0CD56h
SC_VBLANK_COUNT         EQU 0CD57h  ; 2 bytes
SC_START_TICK           EQU 0CD59h  ; 2 bytes
; tools/bgm_data/midi_to_psg.load_stage_clear_parts()の全パート共通
; total_ticks実測値(先頭無音トリム後: melody309/bass316/harmony316)の
; 最大値に少し余裕を持たせた値。
STAGE_CLEAR_TOTAL_TICKS EQU 320

; (2026-09-08、"ではゲームオーバーBGM https://youtu.be/...この曲再現
; できる?"には著作権上の理由でお断りし、代わりにユーザー自身の
; オリジナル作曲[和音入りMIDI]を試聴確認の上で採用・"これで組み込んで
; くれ"): TryZ/StageClearと全く同じ理由(Stage1は自前でバンク切替を
; しない制約)でTitleが起動時に別アドレスへコピー済みという前提。
; 2パート(melody=chB/harmony=chC、chAは使わない)・BGM_END_MARK方式 -
; StageClearと違い外部の実時間タイマーで強制的に次のフェーズへ進める
; 設計ではなく、曲自身が終わったら以後ずっと無音を保持するだけで
; 十分なため、END_MARK対応をBGMT_UB/UC_NEWROWに新規追加した(下記
; 参照)。RAM配置はSC_START_TICKの直後、シンボルテーブル実測で
; 0xE000(TICK)まで空きと確認済みの領域。
BGM_GAMEOVER_CHB_BASE EQU 0CD5Bh  ; Titleが埋める(chB melody, 35byte)
BGM_GAMEOVER_CHC_BASE EQU 0CD7Eh  ; Titleが埋める(chC harmony, 15byte) - 0xCD5B+35

; BELL: 半減期45tickの指数減衰(15*0.5^(t/45)を4bit丸め、以後この
; カーブが完全に0へ収束するまでをRLE圧縮)。試聴ツール(#3 BELL)と
; 同一パラメータ。
BGM_ENV_BELL_TABLE:
    DB 15,3,14,4,13,5,12,6,11,6,10,6,9,7,8,9,7,9,6,11,5,13,4,16,3,22,2,33,1,71,0,0
; LINEAR: 40tickで直線的に0まで減衰(15*max(0,1-t/40))。試聴ツール
; (#5 LINEAR)と同一パラメータ。
BGM_ENV_LINEAR_TABLE:
    DB 15,2,14,3,13,2,12,3,11,2,10,3,9,3,8,3,7,2,6,3,5,3,4,2,3,3,2,2,1,3,0,0

INIT_BGM:
    LD HL,BGM_B_BASE
    LD (BGM_B_PTR),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD (BGM_B_REST),A
    LD (BGM_B_ENV_LEVEL),A
    LD (BGM_B_ENV_IDX),A
    LD (BGM_B_ENV_CD),A
    LD (BGM_B_DUTY_PHASE),A
    LD HL,BGM_C_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_TIMER),A
    LD (BGM_C_REST),A
    LD (BGM_C_ENV_LEVEL),A
    LD (BGM_C_ENV_IDX),A
    LD (BGM_C_ENV_CD),A
    LD HL,BGM_B_BASE : LD (BGM_B_LOOP_BASE),HL
    LD HL,BGM_C_BASE : LD (BGM_C_LOOP_BASE),HL
    ; "ステージクリアで流して" - chA関連+状態機械の起動時ゼロクリア
    ; (init_ram_poison_test.py型の教訓 - 新規RAMは必ずここで明示的に
    ; ゼロ初期化する)。
    LD (BGM_A_TIMER),A
    LD (BGM_A_REST),A
    LD (BGM_A_ENV_LEVEL),A
    LD (BGM_A_ENV_IDX),A
    LD (BGM_A_ENV_CD),A
    LD (STAGE_CLEAR_ACT),A
    LD (SC_VBLANK_COUNT),A : LD (SC_VBLANK_COUNT+1),A
    LD (SC_START_TICK),A : LD (SC_START_TICK+1),A
    LD A,0C3h                     ; JP nn opcode
    LD (HTIMI_HOOK),A
    LD HL,BGM_TICK
    LD (HTIMI_HOOK+1),HL
    ; 実機フィードバック対応(2026-09-06、"だからまだ設定前のPSGが解放
    ; されてノイズ状態の音がなってんだろうが"): HTIMI_HOOKはこの直前で
    ; 既にBGM_TICKを指すため、この後INITの残り(VRAM転送ループの合間の
    ; 短いEIウィンドウ等)で万一H.TIMIが1回でも発火すると、まだBGM再生
    ; 開始として意図していないタイミングでchB/chCへPSG書き込みが走って
    ; しまう。以前はBGM_MUTED=0(即アンミュート)で初期化していたが、
    ; ここを1(ミュート)にしてBGM_TICK自身のchB/chC更新を丸ごとスキップ
    ; させ、INITの本当に最後(EI+HALT+JP MAINLOOPの直前)でUNMUTE_BGMを
    ; 呼ぶまでは何が起きても鳴らないようにする(MUTE_BGM/UNMUTE_BGMは
    ; 既存のボスマテリアライズ/ステージクリア演出と同じ設計を再利用)。
    LD A,1 : LD (BGM_MUTED),A
    RET

; "マテリアライズに入る前にそれまでのBGMは停止" - Stage2のMUTE_BGMと
; 全く同じ設計(BGM_B/C_PTR等の内部状態には一切触れず、BGM_TICK自身の
; chB/chC更新をBGM_MUTEDフラグ1本で丸ごとスキップさせつつ、今鳴って
; いる音を即座に切るためR9/R10を明示的に0へ)。

MUTE_BGM:
    LD A,1 : LD (BGM_MUTED),A
    DI
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    EI
    RET

UNMUTE_BGM:
    XOR A : LD (BGM_MUTED),A
    RET

; (2026-09-06、"MISSION 1"導入演出・"MISSION 2"ステージクリア演出の
; 共有描画ルーチン): 画面全体(row0-23、768byte)をSPACEグリフ
; (MISSION_FONT_BASE+5、全ドット消灯、group8=白文字/黒背景0F1h)で
; 埋めて黒画面にし、HLが指す9byteのメッセージ(row12/col11、画面中央)を
; 描画、念のためスプライトも全て隠す(Y=209は"この枠以降の全スプライトを
; 隠す"というMSX標準のセンチネル、この直前のINIT_SPRATR_CLRと同じ手法)、
; 加えてPSGチャンネルA(SE)も明示的に無音化(下記参照)。VDPへの連続転送は
; 手動のOUT+DJNZループのみ(CLAUDE.md「実機ハードウェア制約」の恒久
; ルール通り、`OTIR`等のブロックI/O命令は絶対に使わない)。
; (2026-09-06、実機フィードバック対応の顛末 - 撤回済み): 一時期row20-23
; (「4-row ground scroller」、GROUND_ROW0=20、NAMEBUF/PREVBUFミラー
; 0E200h/0E300h経由の差分描画キャッシュ管理下)を「生VRAM書き込みで
; 触れるとキャッシュと不整合を起こす」という仮説のもと避ける実装
; (row0-19の640byteのみ埋める)にしていたが、**この仮説は誤りだったと
; 判明**(ユーザー指摘"なんでスクロールを避ける必要がある Mission2は
; その手順で問題なく動いてるだろうが"、および自己検証: NAMEBUF+0/32/
; 64/96は毎フレーム無条件にPHASE_G1〜G4とIDCACHE0/2/3/5から再計算
; される設計[固定値ではなく地形の実位置に応じて変化]なので、たとえ
; 一時的にVRAMだけ書き換えてもNAMEBUFとの差分は次の実フレームで
; 正しく検出され自然に復旧する。実際に旧コミット(row0-19縮小版)と
; 現コミットの両方でエミュレータ上2500フレーム分のVRAM内容を比較した
; ところ完全に同一で、この仮説はエミュレータ上では一切裏付けられ
; なかった)。Mission2の実装(Stage2への実バンク切替を伴う)と全く同型の
; シンプルな768byte全埋めへ復元。実機で報告されているscroller帯の
; ノイズ自体は本ラウンドの変更と無関係な別要因(実機/H.TIMI割り込み
; タイミング等、z80emu.pyでは検出不能な種類)である可能性が高く、
; 引き続き別途調査が必要(下記コメント・HANDOFF.md参照)。
; (2026-09-06、実機フィードバック"Mission1、2表示でビーって音が鳴って
; る"対応): PSGチャンネルB/C(BGM)はMUTE_BGMで無音化済みだが、チャンネル
; A(SE)は無音化していなかったため、この画面に入る直前にたまたま鳴って
; いたSE(MISSION1側はBIOSキークリック音等の残留、MISSION2側は自機
; flyaway中の"エンジン音"がSOUND_UPDATE停止と同時に鳴りっぱなしで
; 固まる)がこの間ずっと鳴り続けていた。R8(チャンネルA音量)を明示的に
; 0へ書き込むことで解消(実機再検証待ち)。
; Input: HL=9byteメッセージへのポインタ。Trashes: AF,BC,DE,HL。
DRAW_MISSION_SCREEN:
    DI
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A   ; channel A (SE) volume=0, kill any stuck tone/noise

    LD A,0 : OUT (99h),A
    NOP
    NOP
    LD A,58h : OUT (99h),A      ; write address = 1800h (name table top-left)
    NOP
    NOP
    LD A,MISSION_FONT_BASE+5    ; SPACE glyph(全ドット消灯) - 黒埋め用
    LD C,3
DMS_FILL_OUTER:
    LD B,0
DMS_FILL_INNER:
    OUT (98h),A
    DJNZ DMS_FILL_INNER
    DEC C
    JR NZ,DMS_FILL_OUTER

    LD A,08Bh : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 198Bh (row12,col11 - screen center)
    NOP
    NOP
    LD B,9
DMS_MSG_LOOP:
    LD A,(HL) : OUT (98h),A
    INC HL
    DJNZ DMS_MSG_LOOP

    LD A,0 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A      ; write address = SPRATR(1B00h)
    NOP
    NOP
    LD A,209 : OUT (98h),A
    EI
    RET

; MISSION1導入演出の終了時に呼ばれる - DRAW_MISSION_SCREENが書いた
; 9byteのメッセージ領域(row12/col11)だけをSPACEグリフへ戻す
; ("MISSION 1"は3秒間だけ表示し、その後は消えて通常のゲーム画面へ"
; という意図通りの終了処理。MISSION2はこの直後にStage2への実バンク
; 切替が起きるため、Stage2自身のINITが画面を丸ごと描き直す=自動的に
; 消える。MISSION1はバンク切替を伴わずそのままStage1のMAINLOOPへ
; 続くため、明示的にこの後始末が必要)。row0-19の残り(実際のゲーム
; 背景)は、この後に続くINIT自身の通常描画がそのまま担当する。
; Trashes: AF,BC,HL(呼び出し元はHLの値に依存しないこと)。
ERASE_MISSION_TEXT:
    DI
    LD A,08Bh : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 198Bh (row12,col11)
    NOP
    NOP
    LD A,MISSION_FONT_BASE+5    ; SPACE glyph
    LD B,9
EMT_LOOP:
    OUT (98h),A
    DJNZ EMT_LOOP
    EI
    RET

; (2026-09-07、"ゲームオーバーは画面中央にGAME OVERと表示"、直後に
; "表示もGAME OVERではなくMISSION FAILEDに変更"): PTH_GAMEOVERから
; 1回だけ呼ばれる。DRAW_MISSION_SCREENと違い、スプライト全消去・PSG
; 無音化は一切行わない - 死亡直後もゲーム画面は普通に動き続けるため
; (下記UPDATE_GAMEOVER_SEQUENCE参照)。row12はground scroller
; (row20-23、NAMEBUF/PREVBUF差分描画キャッシュ管理下)の範囲外かつ、
; row0-19自体もBLANKCODEで塗った固定背景(敵/弾は全てスプライト
; レイヤーで描画されBGネームテーブル自体は動的に書き換わらない)
; なので、以後何かに上書きされて消える心配はない。CLAUDE.md
; 「実機ハードウェア制約」の恒久ルール通り、VDPへの連続転送はOTIR等を
; 使わず手動OUT+DJNZループのみ。
; (2026-09-07、実機フィードバック対応"ステージ1のMission Failedも
; ステージ2と同じで行をブラックで埋める"): 当初(直上の削除済みコメント
; 参照)はメッセージの14セル以外は死亡直前の背景をそのまま透けさせる
; "テキストのみオーバーレイ"方式だったが、Stage2のgameover_bank.asm
; 側で先に対応した「MISSION FAILEDの行全体を黒でブランク埋めしてから
; 表示」と統一するようユーザーから指示 - row12全体(32セル)をMISSION_
; FONT_BASE+5(SPACE、全ドット消灯、group8=白文字/黒背景0F1hなので
; 黒く塗りつぶされる、DRAW_MISSION_SCREEN自身の黒埋めと同じグリフ)で
; 先に埋めてから、その中央にメッセージを上書きする2パス方式に変更。
; Trashes: AF,BC,HL.
DRAW_GAMEOVER_TEXT:
    DI
    LD A,080h : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 1980h (row12,col0)
    NOP
    NOP
    LD A,MISSION_FONT_BASE+5   ; SPACE glyph(全ドット消灯) - 黒埋め用
    LD B,32
DGT_BLANK_LOOP:
    OUT (98h),A
    DJNZ DGT_BLANK_LOOP

    LD A,089h : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 1989h (row12,col9)
    NOP
    NOP
    LD HL,GAME_OVER_MSG
    LD B,GAME_OVER_MSG_LEN
DGT_MSG_LOOP:
    LD A,(HL) : OUT (98h),A
    INC HL
    DJNZ DGT_MSG_LOOP
    EI
    RET

; "MISSION 1"導入演出専用: 約3秒間のZ80クロック直接カウントによる
; ビジーウェイト(H.TIMI/SC_VBLANK_COUNTには依存しない - この時点では
; まだBIOSのINIT32[SCREEN1初期化]すら呼ばれておらず、割り込みに頼れる
; 保証が無いため)。MSXのZ80クロックは3.579545MHz固定(NTSC/PALの
; リフレッシュレートに非依存)、目標T-state数10,738,635(=3.579545M*3)に
; 対しD=10回のB×C(256×256)ネストループ(約10,524,340T-state、
; 約2.94秒)で近似 - "3秒でいいかな"という要望自体が厳密さを求めて
; いないため、これで十分と判断。Trashes: AF,BC,DE.
MISSION_DELAY_3SEC:
    LD D,10
MISSION_DELAY_OUTER:
    LD B,0
MISSION_DELAY_MID:
    LD C,0
MISSION_DELAY_INNER:
    DEC C
    JR NZ,MISSION_DELAY_INNER
    DJNZ MISSION_DELAY_MID
    DEC D
    JR NZ,MISSION_DELAY_OUTER
    RET

; "ではTryZをボス曲に...マテリアライズ終了後に再生" - BOSS_UPDATE_BODY
; がBOSS_STATE=2(マテリアライズ完了)へ遷移する直前に1回だけ呼ばれる。
; Stage2と違いバンク切替は一切行わない(このファイル自身の設計制約 -
; 上記BGM_TRYZ_CHB/CHC_BASEの自身のコメント参照) - TryZの生データは
; Titleが起動時に別アドレスへ既にコピー済みという前提のもと、単に
; BGM_B/C_PTR等をそちらへ差し替えるだけで済む。DI/EIで全体を保護
; (Stage2のSWITCH_BGM_TO_TRYZと同じ理由 - 複数命令にまたがる状態遷移
; の途中でH.TIMI[BGM_TICK]に割り込まれるのを防ぐ)。
SWITCH_BGM_TO_TRYZ:
    DI
    LD HL,BGM_TRYZ_CHB_BASE
    LD (BGM_B_PTR),HL
    LD (BGM_B_LOOP_BASE),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD (BGM_B_REST),A
    LD (BGM_B_ENV_LEVEL),A
    LD (BGM_B_ENV_IDX),A
    LD (BGM_B_ENV_CD),A
    LD (BGM_B_DUTY_PHASE),A
    LD HL,BGM_TRYZ_CHC_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_LOOP_BASE),HL
    LD (BGM_C_TIMER),A
    LD (BGM_C_REST),A
    LD (BGM_C_ENV_LEVEL),A
    LD (BGM_C_ENV_IDX),A
    LD (BGM_C_ENV_CD),A
    EI
    CALL UNMUTE_BGM
    RET

; "ではゲームオーバーBGM...これで組み込んでくれ" - PFA_DEATH_FALL_STEPが
; PLAYERYの画面外到達を検出した瞬間(MISSION FAILEDテキストを初めて
; 描画するのと同じフレーム)に1回だけ呼ばれる。TRIGGER_STAGE_CLEAR/
; SWITCH_BGM_TO_TRYZと同じDI/EI保護でchB/chCを差し替え、念のため
; CALL UNMUTE_BGMも同様に行う(通常は死亡時点でBGM_MUTED=0のはずだが、
; もしボスのマテリアライズ中[BGM_MUTED=1]に被弾して即死した場合でも
; ジングルが無音化されたままにならないための安全策、TRIGGER_STAGE_
; CLEARと同じ考え方)。BGM_END_MARK方式(上のBGMT_UB/UC_NEWROW参照)
; なので、曲の終わりに達したら以後ずっと無音を保持するだけで、
; StageClear/TryZのようなループ復帰先の更新も不要(BGM_B/C_LOOP_BASE
; には一切触れない)。
TRIGGER_GAME_OVER_JINGLE:
    DI
    LD HL,BGM_GAMEOVER_CHB_BASE
    LD (BGM_B_PTR),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD (BGM_B_REST),A
    LD (BGM_B_ENV_LEVEL),A
    LD (BGM_B_ENV_IDX),A
    LD (BGM_B_ENV_CD),A
    LD (BGM_B_DUTY_PHASE),A
    LD HL,BGM_GAMEOVER_CHC_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_TIMER),A
    LD (BGM_C_REST),A
    LD (BGM_C_ENV_LEVEL),A
    LD (BGM_C_ENV_IDX),A
    LD (BGM_C_ENV_CD),A
    EI
    CALL UNMUTE_BGM
    RET

; "ではステージ1と2のスコアを加算して...これをステージクリアで流して
; 3音使って良いんで" - PLAYER_FLYAWAYがちょうど2に到達した最初の
; フレームで1回だけ呼ばれる(下のPFA_FLYAWAY_IDLE周りの分岐参照)。
; SWITCH_BGM_TO_TRYZと同じくDI/EIで全体を保護しつつchB/chCを差し替え、
; 加えてchA(harmony)も新規に起動する。
; (2026-09-07、実機フィードバック対応、"またステージ1クリア後の音が
; 止まってない 何回やるんだよ" - round54/round67で直したはずの症状の
; 3度目の再発、今度は別経路): SOUND_UPDATEはSTAGE_CLEAR_ACT==0の間だけ
; 呼ばれる(上のMAINLOOP側ガード参照)ため、STAGE_CLEAR_ACTがここで1に
; なった瞬間からSOUND_UPDATEは二度と呼ばれなくなる。それまでflyawayの
; エンジン音("goooo"、PFA_STILLGOING参照)がR8(チャンネルA音量)へ
; 毎フレーム再武装していたSND_TIMERの最後の値が、SOUND_UPDATE経由の
; 減衰を受けられないままR8に固まって鳴り続けていた - DRAW_MISSION_
; SCREENのR8=0書き込み(round54)はジングル再生完了後(STAGE_CLEAR_ACT
; ==1→2の遷移時)にしか実行されないため、ジングル再生中(最大
; STAGE_CLEAR_TOTAL_TICKS=約5秒)ずっと鳴りっぱなしになる窓が残って
; いた。SOUND_UPDATEが止まるのと同じこのタイミングでR8を明示的に
; ゼロへ落とし、この窓を閉じる。
TRIGGER_STAGE_CLEAR:
    LD A,1 : LD (STAGE_CLEAR_ACT),A
    LD HL,(SC_VBLANK_COUNT) : LD (SC_START_TICK),HL
    DI
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A   ; channel A (SE) volume=0 - SOUND_UPDATE won't run again to do this itself
    LD HL,STAGE_CLEAR_CHB_BASE
    LD (BGM_B_PTR),HL
    LD (BGM_B_LOOP_BASE),HL
    XOR A
    LD (BGM_B_TIMER),A
    LD (BGM_B_REST),A
    LD (BGM_B_ENV_LEVEL),A
    LD (BGM_B_ENV_IDX),A
    LD (BGM_B_ENV_CD),A
    LD (BGM_B_DUTY_PHASE),A
    LD HL,STAGE_CLEAR_CHC_BASE
    LD (BGM_C_PTR),HL
    LD (BGM_C_LOOP_BASE),HL
    LD (BGM_C_TIMER),A
    LD (BGM_C_REST),A
    LD (BGM_C_ENV_LEVEL),A
    LD (BGM_C_ENV_IDX),A
    LD (BGM_C_ENV_CD),A
    LD HL,STAGE_CLEAR_CHA_BASE
    LD (BGM_A_PTR),HL
    LD (BGM_A_TIMER),A
    LD (BGM_A_REST),A
    LD (BGM_A_ENV_LEVEL),A
    LD (BGM_A_ENV_IDX),A
    LD (BGM_A_ENV_CD),A
    EI
    CALL UNMUTE_BGM
    RET

; PLAYER_FLYAWAY==2の間、毎フレーム呼ばれる(下のPFA_FLYAWAY_IDLE周り
; 参照)。ジングルの総再生時間(STAGE_CLEAR_TOTAL_TICKS、実時間クロック
; SC_VBLANK_COUNT基準)が経過した瞬間に1回だけSTAGE_CLEAR_ACTを2へ
; 進める - build_full_rom.pyのMAINLOOP_PATCH(Comb限定)がこれを見て
; Stage2へのバンク切替へ進む(このファイル自身はバンク切替を一切
; 行わない設計、上記BGM_TRYZ_CHB/CHC_BASE自身のコメント参照)。
; (2026-09-06、"画面をブラックで埋めてMISSION 2とセンターに表示
; 3秒でいいかな"): STAGE_CLEAR_ACTを2状態から4状態(0=未発生/1=ジングル
; 再生中/2=MISSION2黒画面表示中、実時間3秒待ち/3=完了、Comb限定の
; MAINLOOP_PATCHがこれを見てStage2へのバンク切替へ進む)へ拡張。
; ACT==1→2の遷移で新たにMUTE_BGM+DRAW_MISSION_SCREEN(MISSION2_MSG)を
; 行い、SC_START_TICKを再スナップショットして3秒タイマーを再利用する
; (GFEnding[Stage2]のVBLANK_COUNTと同じ「同じ実時間クロックを複数の
; フェーズで使い回す」設計)。
UPDATE_STAGE_CLEAR:
    LD A,(STAGE_CLEAR_ACT)
    CP 1
    JR Z,USC_CHECK_JINGLE
    CP 2
    JR Z,USC_CHECK_MISSION2
    RET
USC_CHECK_JINGLE:
    LD HL,(SC_VBLANK_COUNT)
    LD DE,(SC_START_TICK)
    OR A : SBC HL,DE
    LD DE,STAGE_CLEAR_TOTAL_TICKS
    OR A : SBC HL,DE
    RET C
    ; ACT=2を最初に確定させ、以後BGMT_UPDATE_SC_A(chA/ジングル和音)が
    ; 二度と起動しないようにしてから、MUTE_BGM/DRAW_MISSION_SCREEN
    ; (どちらも内部でEIするため割り込みが再度有効になる)を呼ぶ。
    ; 逆順だとDRAW_MISSION_SCREENのR8=0書き込み直後にBGM_TICKが
    ; もう一度chAへ書き込み、それがACT遷移で永久に固まる
    ; (ジングルの和音が鳴りっぱなしになる)レースがあった。
    LD A,2 : LD (STAGE_CLEAR_ACT),A
    CALL MUTE_BGM
    LD HL,MISSION2_MSG
    CALL DRAW_MISSION_SCREEN
    LD HL,(SC_VBLANK_COUNT)
    LD (SC_START_TICK),HL
    RET
USC_CHECK_MISSION2:
    LD HL,(SC_VBLANK_COUNT)
    LD DE,(SC_START_TICK)
    OR A : SBC HL,DE
    LD DE,MISSION_SCREEN_TICKS
    OR A : SBC HL,DE
    RET C
    LD A,3 : LD (STAGE_CLEAR_ACT),A
    RET

; (2026-09-07、"ゲームオーバー表示は3秒表示してボタンが押されるか
; 10秒経過でタイトル画面に"): PTH_GAMEOVERがGAME_OVER_SEQ=1で起動、
; 以後MAINLOOP冒頭から毎フレーム無条件に呼ばれる(UPDATE_STAGE_CLEARと
; 同じ「フリーズしていても呼び続ける」設計 - ただしGAME_OVER自体は
; 引き続き"ゲームを止めない"、MAINLOOP本体はそのまま進み続ける)。
;   1(MISSION FAILED表示中、3秒待ち) -> 2(ボタンorタイムアウト待ち、
;   最大10秒) -> 3(タイトルへ戻る準備完了、build_full_rom.pyのComb限定
;   MAINLOOP_PATCHがこれを見てタイトルへのバンク切替へ進む、このファイル
;   自身はバンク切替を一切行わない)
; (2026-09-07、"Mission Failed表示は毎フレーム表示 BG系の処理が入ると
; 上書きで消えてしまうため"): DRAW_GAMEOVER_TEXTは元々死亡演出完了の
; 瞬間に1回だけ描画していたが、"テキストのみオーバーレイ"方式(背景の
; 上に直接描くだけで保護機構は無い)のため、地形スクロール等の他のBG
; 書き込みが同じVRAM名前テーブル領域を後から上書きすると消えてしまう。
; GAME_OVER_SEQが1か2の間(=タイトルへ切り替わる直前まで)、この
; UPDATE_GAME_OVER_SEQUENCE自体が毎フレーム無条件に呼ばれる性質を
; 利用し、毎フレーム無条件に描き直すことで、他の何に上書きされても
; 次のフレームで必ず復元されるようにする。
UPDATE_GAME_OVER_SEQUENCE:
    LD A,(GAME_OVER_SEQ)
    OR A
    RET Z
    CP 3
    JR NC,UGOS_DISPATCH
    CALL DRAW_GAMEOVER_TEXT
UGOS_DISPATCH:
    LD A,(GAME_OVER_SEQ)
    CP 1
    JR Z,UGOS_CHECK_TEXT_TIMER
    CP 2
    JR Z,UGOS_CHECK_BUTTON_OR_TIMEOUT
    RET
UGOS_CHECK_TEXT_TIMER:
    LD HL,(SC_VBLANK_COUNT)
    LD DE,(GAME_OVER_START_TICK)
    OR A : SBC HL,DE
    LD DE,GAME_OVER_TEXT_TICKS
    OR A : SBC HL,DE
    RET C
    LD HL,(SC_VBLANK_COUNT)
    LD (GAME_OVER_START_TICK),HL
    LD A,2 : LD (GAME_OVER_SEQ),A
    RET
UGOS_CHECK_BUTTON_OR_TIMEOUT:
    LD A,1
    CALL GTTRIG
    OR A
    JR NZ,UGOS_GOTO_TITLE
    LD HL,(SC_VBLANK_COUNT)
    LD DE,(GAME_OVER_START_TICK)
    OR A : SBC HL,DE
    LD DE,GAME_OVER_TIMEOUT_TICKS
    OR A : SBC HL,DE
    RET C
UGOS_GOTO_TITLE:
    LD A,3 : LD (GAME_OVER_SEQ),A
    RET

BGM_TICK:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    ; ステージクリアジングル用の実時間クロック("ステージクリアで
    ; 流して" - 曲の総再生時間を実時間で判定する必要があるため。
    ; H.TIMIは実VBlank駆動の本物の割り込みなので、MAINLOOPのTICK
    ; (free-running、実時間との対応が無い)とは違いこれ自体が実時間の
    ; 基準になる。GFEnding[Stage2]のVBLANK_COUNTと全く同じ考え方。
    ; 16bit、オーバーフローは現実的な猶予時間内では発生しないため無視。
    LD HL,(SC_VBLANK_COUNT) : INC HL : LD (SC_VBLANK_COUNT),HL
    LD A,(BGM_MUTED)
    OR A
    JR NZ,BGMT_SKIP_BC
    CALL BGMT_UPDATE_B
    CALL BGMT_UPDATE_C
BGMT_SKIP_BC:
    LD A,(STAGE_CLEAR_ACT)
    CP 1
    CALL Z,BGMT_UPDATE_SC_A
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; チャンネルB(R2/R3 tone、R9 volume、BELL形状+デューティ50%) - 実機
; フィードバック対応で全SEがチャンネルAへ移設済みのため、このチャンネル
; はBGM専用。
BGMT_UPDATE_B:
    LD A,(BGM_B_TIMER)
    OR A
    JR Z,BGMT_UB_NEWROW
    DEC A
    LD (BGM_B_TIMER),A
    JR BGMT_UB_ENV_STEP
BGMT_UB_NEWROW:
    LD HL,(BGM_B_PTR)
    LD A,(HL)
    CP BGM_END_MARK
    JR Z,BGMT_UB_SETREST    ; GAME_OVERジングル専用: 一度きりの終了 - PTRを進めず無音を保持し続ける
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UB_GOT
    LD HL,(BGM_B_LOOP_BASE)   ; ALONE_FIGHTER/TryZどちらの曲でも正しい復帰先(BGM_B_LOOP_BASE参照)
    LD A,(HL)
BGMT_UB_GOT:
    LD C,A                         ; C = note index (or REST), survives the INC HL below
    INC HL
    LD A,(HL)                      ; duration
    INC HL
    LD (BGM_B_PTR),HL
    ; round40 実機フィードバック対応: off-by-one修正(tools/stage2_
    ; combined/combined_test.asmの同じ箇所の長いコメント参照) - 読み
    ; 込みtick自体も1tick分の再生になるため、DEC Aで合計durationぴったり
    ; に補正する。
    DEC A
    LD (BGM_B_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_UB_SETREST
    XOR A
    LD (BGM_B_REST),A
    LD E,C : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,2 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,3 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    ; エンベロープをテーブル先頭(index0)からリトリガー - この行の
    ; エントリ自体が今tick分の再生になるため、durationはDEC Aしてから
    ; カウントダウンへ積む(音符行のoff-by-one修正と同じ考え方)。
    LD HL,BGM_ENV_BELL_TABLE
    LD A,(HL) : LD (BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (BGM_B_ENV_CD),A
    XOR A : LD (BGM_B_ENV_IDX),A
    LD A,BGM_B_DUTY_MASK : LD (BGM_B_DUTY_PHASE),A
    JR BGMT_UB_ENV_WRITE
BGMT_UB_SETREST:
    LD A,1
    LD (BGM_B_REST),A
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
BGMT_UB_ENV_STEP:
    LD A,(BGM_B_REST)
    OR A
    RET NZ                          ; 休符中は何もしない(R9は既にSETRESTで0)
    LD A,(BGM_B_ENV_CD)
    OR A
    JR Z,BGMT_UB_ENV_ADVANCE
    DEC A
    LD (BGM_B_ENV_CD),A
    JR BGMT_UB_ENV_WRITE
BGMT_UB_ENV_ADVANCE:
    LD A,(BGM_B_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,BGMT_UB_ENV_WRITE           ; 番兵に到達済み - 以後は永久にこの値を保持
    INC A
    LD (BGM_B_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL                        ; インデックス*2 = テーブルオフセット(2byte/エントリ)
    LD DE,BGM_ENV_BELL_TABLE
    ADD HL,DE
    LD A,(HL) : LD (BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,BGMT_UB_ENV_WRITE            ; duration=0(番兵)- CDは0のまま(=永久保持)
    DEC A
    LD (BGM_B_ENV_CD),A
BGMT_UB_ENV_WRITE:
    LD A,(BGM_B_DUTY_PHASE)
    INC A
    LD (BGM_B_DUTY_PHASE),A
    AND BGM_B_DUTY_MASK
    LD B,0
    JR NZ,BGMT_UB_ENV_OUT
    LD A,(BGM_B_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,BGMT_UB_ATTEN_OK
    XOR A                            ; 減算でアンダーフローしたら0にクランプ
BGMT_UB_ATTEN_OK:
    LD B,A
BGMT_UB_ENV_OUT:
    LD A,9 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    RET

; チャンネルC(R4/R5 tone、R10 volume、LINEAR形状+デューティOFF)。
BGMT_UPDATE_C:
    LD A,(BGM_C_TIMER)
    OR A
    JR Z,BGMT_UC_NEWROW
    DEC A
    LD (BGM_C_TIMER),A
    JR BGMT_UC_ENV_STEP
BGMT_UC_NEWROW:
    LD HL,(BGM_C_PTR)
    LD A,(HL)
    CP BGM_END_MARK
    JR Z,BGMT_UC_SETREST    ; GAME_OVERジングル専用: 一度きりの終了 - PTRを進めず無音を保持し続ける
    CP BGM_LOOP_MARK
    JR NZ,BGMT_UC_GOT
    LD HL,(BGM_C_LOOP_BASE)   ; ALONE_FIGHTER/TryZどちらの曲でも正しい復帰先(BGM_C_LOOP_BASE参照)
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
    JR Z,BGMT_UC_SETREST
    XOR A
    LD (BGM_C_REST),A
    LD E,C : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,4 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,5 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,BGM_ENV_LINEAR_TABLE
    LD A,(HL) : LD (BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (BGM_C_ENV_CD),A
    XOR A : LD (BGM_C_ENV_IDX),A
    JR BGMT_UC_ENV_WRITE
BGMT_UC_SETREST:
    LD A,1
    LD (BGM_C_REST),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
BGMT_UC_ENV_STEP:
    LD A,(BGM_C_REST)
    OR A
    RET NZ
    LD A,(BGM_C_ENV_CD)
    OR A
    JR Z,BGMT_UC_ENV_ADVANCE
    DEC A
    LD (BGM_C_ENV_CD),A
    JR BGMT_UC_ENV_WRITE
BGMT_UC_ENV_ADVANCE:
    LD A,(BGM_C_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,BGMT_UC_ENV_WRITE
    INC A
    LD (BGM_C_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,BGM_ENV_LINEAR_TABLE
    ADD HL,DE
    LD A,(HL) : LD (BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,BGMT_UC_ENV_WRITE
    DEC A
    LD (BGM_C_ENV_CD),A
BGMT_UC_ENV_WRITE:
    LD A,10 : OUT (PSG_ADDR),A
    LD A,(BGM_C_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,BGMT_UC_ATTEN_OK
    XOR A                            ; 減算でアンダーフローしたら0にクランプ
BGMT_UC_ATTEN_OK:
    OUT (PSG_DATA),A
    RET

; チャンネルA(R0/R1 tone、R8 volume、LINEAR形状+デューティOFF、chCと
; 同型) - ステージクリアジングルの3声目("これは3音使って良い" -
; STAGE_CLEAR_ACT==1の間だけ呼ばれる、通常ゲーム中のSEドライバ
; [SOUND_UPDATE]とは競合しない、MAINLOOP側もSTAGE_CLEAR_ACT==1の間は
; CALL SOUND_UPDATE自体を丸ごとスキップする)。R7は既にINITでtone A
; 有効(0B0h)のまま変更不要(Stage2のENDING_ACTと違い、Stage1のchAは
; 元々常時tone A有効設計 - "そもそもchB、Cは空けてあってSE類はchA
; のみで鳴らすはず"のRound41統合以来)。LOOP_MARK方式だが、外部の
; STAGE_CLEAR_ACT/SC_VBLANK_COUNTタイマーが曲の総長ちょうどでバンク
; 切替へ進むため実際にループ端へ到達することはまず無い。
BGMT_UPDATE_SC_A:
    LD A,(BGM_A_TIMER)
    OR A
    JR Z,BGMT_USCA_NEWROW
    DEC A
    LD (BGM_A_TIMER),A
    JR BGMT_USCA_ENV_STEP
BGMT_USCA_NEWROW:
    LD HL,(BGM_A_PTR)
    LD A,(HL)
    CP BGM_LOOP_MARK
    JR NZ,BGMT_USCA_GOT
    LD HL,STAGE_CLEAR_CHA_BASE
    LD A,(HL)
BGMT_USCA_GOT:
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (BGM_A_PTR),HL
    DEC A
    LD (BGM_A_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,BGMT_USCA_SETREST
    XOR A
    LD (BGM_A_REST),A
    LD E,C : LD D,0
    LD HL,BGM_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,BGM_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,0 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,BGM_ENV_LINEAR_TABLE
    LD A,(HL) : LD (BGM_A_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (BGM_A_ENV_CD),A
    XOR A : LD (BGM_A_ENV_IDX),A
    JR BGMT_USCA_ENV_WRITE
BGMT_USCA_SETREST:
    LD A,1
    LD (BGM_A_REST),A
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
BGMT_USCA_ENV_STEP:
    LD A,(BGM_A_REST)
    OR A
    RET NZ
    LD A,(BGM_A_ENV_CD)
    OR A
    JR Z,BGMT_USCA_ENV_ADVANCE
    DEC A
    LD (BGM_A_ENV_CD),A
    JR BGMT_USCA_ENV_WRITE
BGMT_USCA_ENV_ADVANCE:
    LD A,(BGM_A_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,BGMT_USCA_ENV_WRITE
    INC A
    LD (BGM_A_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,BGM_ENV_LINEAR_TABLE
    ADD HL,DE
    LD A,(HL) : LD (BGM_A_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,BGMT_USCA_ENV_WRITE
    DEC A
    LD (BGM_A_ENV_CD),A
BGMT_USCA_ENV_WRITE:
    LD A,8 : OUT (PSG_ADDR),A
    LD A,(BGM_A_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,BGMT_USCA_ATTEN_OK
    XOR A
BGMT_USCA_ATTEN_OK:
    OUT (PSG_DATA),A
    RET

; Extracts SCORE's 6 decimal digits (hundred-thousands..ones, of the
; SCORE value itself - i.e. real_score/100, see SCORE's own comment)
; into SCORE_DIGITS, then draws all 8 display cells at row0, cols0-7:
; those 6, followed by a fixed "00" (real score's low 2 digits, always
; zero).
;
; The hundred-thousands AND ten-thousands digits both need the full
; 24-bit value (A:HL, A=SCORE+2's high byte): a remainder just under
; 100000 (up to 99999) still doesn't fit in HL alone since 99999 >
; 65535 - only once the ten-thousands digit is extracted is the
; remainder guaranteed < 10000 < 65536, letting the remaining 4 digits
; use plain 16-bit HL like the original 5-digit version did for all of
; its digits. Each 24-bit-aware digit uses the standard multi-byte
; subtract idiom (OR A : SBC HL,DE : SBC A,n, where the second SBC
; folds in the first one's borrow to get the true 24-bit borrow-out in
; its own carry) and, on the "done, restore" arm, the exact-inverse add
; to undo the last (over-)subtraction without losing track of A - this
; mini-assembler has no ADC, so the restore does ADD HL,DE (whose own
; carry-out doubles as the borrow that needs folding back into A) then
; a plain ADD A,n plus a conditional INC A for that carry. Dropping A's
; restore after the hundred-thousands digit (as an earlier version of
; this did) leaves A holding garbage that the ten-thousands digit
; silently ignores, corrupting every digit after it whenever the true
; remainder was ever >= 65536 (i.e. real score between roughly
; 6,553,600 and 9,999,900).
SCORE_DISPLAY:
    LD HL,(SCORE)
    LD A,(SCORE+2)
    LD B,0
SD_HT:
    LD DE,86A0h           ; 100000's low word (high byte is the 01h below)
    OR A
    SBC HL,DE
    SBC A,01h
    JR C,SD_HT_DONE
    INC B
    JR SD_HT
SD_HT_DONE:
    LD DE,86A0h
    ADD HL,DE              ; this ADD's own carry-out doubles as the borrow to add back into A -
    JR NC,SD_HT_RESTORE_A   ; this mini-assembler has no ADC, so fold it in with a plain INC first
    INC A
SD_HT_RESTORE_A:
    ADD A,01h
    PUSH AF
    LD A,B : LD (SCORE_DIGITS+0),A
    POP AF

    LD B,0
SD_TT:
    LD DE,10000
    OR A
    SBC HL,DE
    SBC A,00h
    JR C,SD_TT_DONE
    INC B
    JR SD_TT
SD_TT_DONE:
    LD DE,10000
    ADD HL,DE
    LD A,B : LD (SCORE_DIGITS+1),A

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
    LD A,B : LD (SCORE_DIGITS+2),A

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
    LD A,B : LD (SCORE_DIGITS+3),A

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
    LD A,B : LD (SCORE_DIGITS+4),A

    LD A,L : LD (SCORE_DIGITS+5),A

    XOR A : LD (ANIM_TMP_ROW),A
    LD A,0 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+0) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,1 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+1) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,2 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+2) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,3 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+3) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,4 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+4) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,5 : LD (ANIM_TMP_COL),A
    LD A,(SCORE_DIGITS+5) : ADD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,6 : LD (ANIM_TMP_COL),A
    LD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    XOR A : LD (ANIM_TMP_ROW),A
    LD A,7 : LD (ANIM_TMP_COL),A
    LD A,DIGIT_BASE : LD (ANIM_TMP_VAL),A
    CALL WRITE_ANIM_CELL
    RET

; Score-award helpers, one per enemy type's per-kill value - SCORE is
; real_score/100, so these add 1/2/3 (not 100/200/300) now.
ADD_SCORE_100:
    LD HL,1
    JR ADD_SCORE_COMMON
ADD_SCORE_200:
    LD HL,2
    JR ADD_SCORE_COMMON
ADD_SCORE_300:
    LD HL,3
    JR ADD_SCORE_COMMON
; Ebuz(2026-09-14組み込み、耐久値12のミニボス的存在)の撃破報酬。
; (2026-09-23、"Ebuzのスコアを500点から2000点に")。
ADD_SCORE_2000:
    LD HL,20
ADD_SCORE_COMMON:
    LD DE,(SCORE)
    ADD HL,DE
    LD (SCORE),HL
    JR NC,ASC_NO_CARRY
    LD HL,SCORE+2 : INC (HL)
ASC_NO_CARRY:
    CALL SCORE_DISPLAY
    RET

; Awards the right formation-kill score (enemy1=100 while
; ENEMY_CYCLE is 0/1, enemy2=200 while it's >=2 - always exactly 2
; now that top/bottom no longer uses 2 vs 3, see E2_SPAWN_Y).
AWARD_FORMATION_SCORE:
    LD A,(ENEMY_CYCLE)
    CP 2
    JR NC,AWARD_ENEMY2
    JP ADD_SCORE_100
AWARD_ENEMY2:
    JP ADD_SCORE_200

; Enemy2 spawn Y, passed in by the SPAWN_E2_TOP_*/BOT_* stubs (see
; their own comment) instead of ENEMY_START_COMPLEX_A/B hardcoding it
; from ENEMY_CYCLE. ENEMY_CYCLE itself is still set to 2 on every
; Enemy2 spawn - not to distinguish top/bottom anymore (that's now
; just this Y value), only so AWARD_FORMATION_SCORE's cycle>=2 check
; still recognizes a complex-formation kill as the 200pt Enemy2 case.
; (2026-09-23、メインループ監査): 旧0E84EhはENEMY_POOLスロット0の
; E_TYPEと同じ番地で、Zigzag出現のたびにスロット0の敵の種類を上書き
; していた。ENEMY_POOL縮小で空いた旧プール跡地へ移設。
E2_SPAWN_Y EQU 0EACCh

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
E2A_ANIM_SEQ EQU 0E662h    ; shared (all 3 units) 1,2,3,2 quadrant-anim index,
                           ; free RAM right after E2A_ACTIVE - see ECS_S7_A
E2A_ANIM_TIMER EQU 0E663h
; "E1,E2,E5はランダムに3から5機に一度発射 ただし斜め移動中のみ" -
; per-type shared "how many more spawns until the next one is the
; designated shooter" countdowns (seeded to a random 3-5 at INIT,
; reseeded to a fresh random 3-5 by DECIDE_FIRE_SHOOTER every time it
; picks a shooter - see that routine's own comment), plus Enemy2's own
; per-formation-instance flag (0=not this spawn's shooter,1=shooter/
; not yet fired,2=fired) since. E2A/E2B are 2 concurrent formations
; and each needs its own flag. Free RAM right after E2A_ANIM_TIMER,
; before E2B_SEQ_STATE (E664h-E67Fh unused until now).
E1_FIRE_COUNTDOWN EQU 0E664h   ; TYPE_ENEMY4(=Enemy1=Enemy7) shared spawn counter
E5_FIRE_COUNTDOWN EQU 0E665h   ; TYPE_ENEMY1_LOOK(Enemy5) shared spawn counter
E2_FIRE_COUNTDOWN EQU 0E666h   ; Enemy2 A+B shared spawn counter
E2A_FIRE_FLAG      EQU 0E667h
; 実機フィードバック対応(2026-09-07、"敵弾のレーザーが1回の自機への
; 被弾で複数回ダメージ食らってる場合がある"): EBSD_UPDATE自身の既存
; コメントが明言する通り、TYPE_ENEMY4の"Y軸一致発射"(EBSD_E4_TRY_
; ALIGN)と"斜めドッジ発動時のランダム発射"(EBSD_DIAG_DIR_SET)は
; 互いに独立してトリガーされ、同一フレームで両方の条件を満たすと
; co-occur(同時発生)しうる設計だった - 実際に両方が発火すると、
; どちらも同じ(IX+E_X),(IX+E_Y)(このフレームの移動後の敵本体
; 座標、ダイブによるY変化はこの後で起こるため両方とも未変化)を
; そのままSPAWN_EBULLETへ渡すため、完全に同一座標から2発の
; EBULLETが同時に発射されてしまう(シミュレーションで再現・確認
; 済み)。この1バイトは「このフレーム、このTYPE_ENEMY4インスタンス
; は既にEBULLETを発射したか」を一時的に記録するフラグ - EBSD_
; UPDATE冒頭で毎回0クリアし、align-fire発火時に1を立て、
; dodge-fire側はSPAWN_EBULLET呼び出し直前にこれを見て、既に
; 発射済みならスキップする(DECIDE_FIRE_SHOOTER自体は通常通り
; 呼ぶので"3-5機に1回"のカウントダウン消費・斜めドッジの動き
; 自体には一切影響しない、弾の二重発射だけを防ぐ)。
E4_FIRED_THIS_FRAME EQU 0E668h
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
E2B_ANIM_SEQ EQU 0E6E2h    ; same idea as E2A_ANIM_SEQ, free RAM after E2B_ACTIVE
E2B_ANIM_TIMER EQU 0E6E3h
E2B_FIRE_FLAG EQU 0E6E4h   ; B's own copy of E2A_FIRE_FLAG - see its own comment (free RAM after E2B_ANIM_TIMER)

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
; "E4にアニメ追加 上下移動中に適用" - 2nd pose, shown alternating with
; PAT_ENEMY4 while diving (see EBSD_DIAG_E4/EBSD_DRAW_E4). Free code
; range (92-95, confirmed unused elsewhere in this file).
PAT_ENEMY4_2   EQU 92         ; patterns92-95 (32 bytes at SPRPAT+736)
E4_ANIM_FRAME_LEN EQU 4       ; frames per pose toggle while diving - same pacing as ENEMY1_ANIM_FRAME_LEN
; round141("エネミー4...耐久値2だが1発当たったら左斜め下に墜落 自機の
; 墜落の逆向きだな 爆発エフェクトも自機と同じだがサウンドは無しで"):
; 被弾でE_FLAGS(未使用フィールド、TYPE_ENEMY4流用)を1にし、以後
; EBSD_DIAG_E4がこの間隔でPEUA_TRY_SPAWN_AT(自機爆発と同じ
; PLAYER_EXPL_POOL、2026-09-23からSOUND_DESTROYも)を撃つ - PLAYER_EXPL_
; SPAWN_INTERVALと同じ未調整の初期値。
ENEMY4_CRASH_SPAWN_INTERVAL EQU 8
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
; (2026-09-23、メインループ監査B、ユーザー指示"8で実装して"): 32→8。
; ボスまでスケジュールを通した実測で同時最大7体(撃つ/撃たない両条件、
; 使用スロット0-6)。毎フレーム弾数+2回の全走査が1/4になる。スケジュール
; 変更で9体以上同時に出る場面ができると9体目以降は無言でドロップされる
; ので、その場合は計測し直すこと。
ENEMY_SLOT_COUNT EQU 8
ENEMY_POOL       EQU 0E84Dh   ; 8*20 = 160 bytes (E84D-E8EC)。E8ED-EACCは32スロット時代の跡地(空き)

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
    DB PAT_ENEMY4, SPR_BLACK, ENEMY4_HP, 2       ; TYPE_ENEMY4
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
SKY_VEC_H EQU 0E713h   ; 弾が当たって消える時の空の復元先(FAST/SLOW)
SKY_VEC_E EQU 0E715h   ; 弾が進む時の空の復元先(0E717h-0E71Eh は旧2-3発目用の跡地)

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
; (2026-09-19、32方向照準の分類計算用の一時スクラッチ): POD_XY_X/Yは
; GET_POD_XY呼び出し直後にPOD_BULLETn_X/Yへコピーされ、その後
; POD_BULLET_CALC_DIR/POD_AIM_CLASSIFYが呼ばれるまでの間は完全に不要
; (次のGET_POD_XY呼び出しまで参照されない)と確認済みのため、そのまま
; 一時スクラッチとして再利用(新規RAM確保なし)。
PAC_AX           EQU POD_XY_X
PAC_AY           EQU POD_XY_Y
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
; (2026-09-13、"ステージ1ボス ボスの弾は画面のX座標が半分より右に自機が
; いる場合自機狙い弾になるように変更 半分以下なら従来通りまっすぐ打つ
; だけ 近寄ったら自機狙いになるって事"): POD_BULLETn used to fly purely
; horizontal (X decrements by POD_BULLET_SPEED every frame, Y frozen at
; the firing pod's own Y forever). Decided once at the exact moment each
; bullet is launched (POD_FIRE_DO_PAIR), not re-evaluated in flight
; (predictive aim, same idiom as every other fixed-trajectory shot in
; this file, e.g. Stage2's BOSS_BROKEN_BEAM_TABLE) - if PLAYERX is
; already past the screen's own halfway point at that instant, the
; bullet used to get a small constant per-frame Y nudge only (see
; below, this 3-value scheme is now superseded).
;
; (2026-09-19、"接近時の自機狙い弾の精度が低いんで24や32方向に と言っても
; プレイヤーは常に左に居るんでLUTは180度分で済むはず"): the crude
; DY=-2/0/+2-only homing above is replaced by a real 32-direction 2D aim
; (POD_BULLET_CALC_DIR/POD_AIM_CLASSIFY, defined near POD_BULLET_MOVE).
; Still gated by POD_BULLET_HOMING_THRESHOLD_X exactly as before (straight
; shot, DXMAG=POD_BULLET_SPEED/DY=0, when PLAYERX hasn't crossed the
; halfway point yet) - only the "aim" branch's precision changed.
POD_BULLET_HOMING_THRESHOLD_X EQU 128  ; screen width(256)/2
; per-frame signed Y velocity for POD_BULLET0/1 (unchanged fields, now
; populated by the 32-direction table lookup instead of the old +-2
; constant). Placed at 0E739h/0E7ABh, the single confirmed-free byte in
; each of their own regions (POD_BULLET0_DY between POD_RECOIL[8 bytes,
; E731-E738] and DFL_RNG[E73Ah]; POD_BULLET1_DY between POD_LOOP_ALIVE_
; SNAPSHOT and POD_LAP_CYCLE) - verified via direct grep before use,
; unchanged from the original round.
POD_BULLET0_DY   EQU 0E739h

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

; Y comes straight from the caller's parameter now (see E2_SPAWN_Y).
; Exit direction is decided dynamically, same comparison idiom as
; EBSD_UPDATE's Enemy1 dodge-direction pick: spawning at/below the
; player (spawnY >= PLAYERY) climbs UP (EXITTYPE=1); spawning above
; the player (spawnY < PLAYERY) dives DOWN (EXITTYPE=0) - see
; ECS_S7_A's use of E2A_EXITTYPE for what each value actually does.
ENEMY_START_COMPLEX_A:
    LD A,(E2_SPAWN_Y) : LD (E2A_Y),A
    LD C,A
    LD A,(PLAYERY) : LD B,A
    LD A,C
    CP B
    JR C,ESC_EXIT_DOWN_A        ; spawnY < PLAYERY (above the player)
    LD A,1 : LD (E2A_EXITTYPE),A
    JR ESC_COMPLEX_INIT_A
ESC_EXIT_DOWN_A:
    XOR A : LD (E2A_EXITTYPE),A
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    XOR A : LD (E2A_ANIM_SEQ),A : LD (E2A_ANIM_TIMER),A
    LD HL,ASTERISK_PATTERN : LD (REDRAW_SRC_PATTERN),HL
    LD HL,SPRPAT+256 : LD DE,E2A_U0_TOP : LD IX,E2A_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+288 : LD DE,E2A_U1_TOP : LD IX,E2A_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+320 : LD DE,E2A_U2_TOP : LD IX,E2A_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    LD A,1
    LD (E2A_U0_STATE),A : LD (E2A_U1_STATE),A : LD (E2A_U2_STATE),A
    ; "エネミー2のジグザグの合体...Y座標8pxずつずらして合体に変更 1機目
    ; -8で3機目+8"(2026-09-12): 合体(states0-5)中だけU0を-8/U2を+8にずらし、
    ; V字型に寄ってくる見た目にする。U1(2機目)は無変更。(2026-09-23、"合体
    ; 後も1セルズレたまま移動させたい"): 合体後のドリフト・退出中もこのズレを
    ; 保つ(ENEMY_DRAW_ALL_COMPLEX_A/ECS_S7_RECORD_A参照)。
    LD A,(E2A_Y) : SUB 8 : LD (E2A_U0_Y),A
    LD A,(E2A_Y) : LD (E2A_U1_Y),A
    LD A,(E2A_Y) : ADD A,8 : LD (E2A_U2_Y),A   ; keep hit-test Y in sync with the drawn Y during assembly (states 0-5), not just from state6 onward
    XOR A
    LD (E2A_SEQ_STATE),A : LD (E2A_PROGRESS),A
    LD A,ENEMY_SPAWNX : LD (E2A_U0_X),A
    DI
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,1 : LD (E2A_ACTIVE),A
    EI
    ; "E2はランダムに3から5機に一度発射" - decided once per formation
    ; spawn, here (SPAWN_E2 dispatches to exactly one of A/B per spawn -
    ; see its own comment). Checked/consumed in ECS_S7_A.
    LD HL,E2_FIRE_COUNTDOWN
    CALL DECIDE_FIRE_SHOOTER
    LD (E2A_FIRE_FLAG),A
    RET

; See ENEMY_START_COMPLEX_A's comment - same idea, instance B.
ENEMY_START_COMPLEX_B:
    LD A,(E2_SPAWN_Y) : LD (E2B_Y),A
    LD C,A
    LD A,(PLAYERY) : LD B,A
    LD A,C
    CP B
    JR C,ESC_EXIT_DOWN_B        ; spawnY < PLAYERY (above the player)
    LD A,1 : LD (E2B_EXITTYPE),A
    JR ESC_COMPLEX_INIT_B
ESC_EXIT_DOWN_B:
    XOR A : LD (E2B_EXITTYPE),A
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    XOR A : LD (E2B_ANIM_SEQ),A : LD (E2B_ANIM_TIMER),A
    LD HL,ASTERISK_PATTERN : LD (REDRAW_SRC_PATTERN),HL
    LD HL,SPRPAT+416 : LD DE,E2B_U0_TOP : LD IX,E2B_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+448 : LD DE,E2B_U1_TOP : LD IX,E2B_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+480 : LD DE,E2B_U2_TOP : LD IX,E2B_U2_BOT
    CALL REDRAW_UNIT_PATTERN
    LD A,1
    LD (E2B_U0_STATE),A : LD (E2B_U1_STATE),A : LD (E2B_U2_STATE),A
    ; See ENEMY_START_COMPLEX_A's own comment on the same pattern - instance B.
    LD A,(E2B_Y) : SUB 8 : LD (E2B_U0_Y),A
    LD A,(E2B_Y) : LD (E2B_U1_Y),A
    LD A,(E2B_Y) : ADD A,8 : LD (E2B_U2_Y),A   ; keep hit-test Y in sync with the drawn Y during assembly (states 0-5), not just from state6 onward
    XOR A
    LD (E2B_SEQ_STATE),A : LD (E2B_PROGRESS),A
    LD A,ENEMY_SPAWNX : LD (E2B_U0_X),A
    DI
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,1 : LD (E2B_ACTIVE),A
    EI
    ; "E2はランダムに3から5機に一度発射" - see ENEMY_START_COMPLEX_A's
    ; own comment. Checked/consumed in ECS_S7_B.
    LD HL,E2_FIRE_COUNTDOWN
    CALL DECIDE_FIRE_SHOOTER
    LD (E2B_FIRE_FLAG),A
    RET

; Checked once per game tick (every 8 frames). Fires each scheduled
; spawn exactly once, in order, as GAME_TICK reaches its threshold -
; not when the previous one finishes. SPAWN_THRESHOLDS is a 16-bit
; (DW) array so thresholds aren't capped at 255. Boss is the final
; entry, index479 (2026-09-14 Schedule_2_1.json replacement, 480
; entries - also the first schedule where "ebuz" placements are wired
; through this same dispatch instead of the now-removed hardcoded
; GAME_TICK-freezing trigger, see EBUZ_HP_INIT's own comment).
; One-shot: once all 480 have fired, this just returns immediately
; forever after, so nothing loops.
SPAWN_SCHEDULE_CHECK:
    ; --- 2026-09-12 修正: 397エントリ(>255)になったため、8bitの A
    ; --- レジスタだけでは指標(0-396)を表現しきれない - 旧実装は
    ; --- "CP 397"という8bit即値比較が397&0FFh=141に切り詰められ、
    ; --- SPAWN_NEXT_INDEXが141に達した瞬間"スケジュール終了"と誤認して
    ; --- 即RETし続け、以後tick580以降のスポーン・ボスが一切発生しない
    ; --- 実バグになっていた(実機/エミュレータ両方で100%再現)。
    ; --- SPAWN_NEXT_INDEXを2byteのRAM(0-396を表現可能)へ拡張し、以後
    ; --- このチェック・SSC_FIRE・各SPAWN_*ハンドラのテーブル添字は全て
    ; --- HLによる16bit演算で行う(Aは8bit範囲のCP比較にのみ使う)。
    ; --- 2026-09-12追記: 549エントリ(index0-548)への再差し替えで
    ; --- H(index上位byte)が0/1の2値では足りず0/1/2の3値になったため、
    ; --- SSC_FIREのブロック分岐をH値に応じた可変本数のCPチェーンへ
    ; --- 一般化した(下記SSC_FIRE参照)。
    ; --- 2026-09-13追記: Schedule_2.jsonへの再差し替えで576エントリに
    ; --- なったが、H=0/1/2の3ブロック構成のまま(576<768)対応できた -
    ; --- 上記の一般化のおかげでSSC_FIRE側の分岐本数自体は無変更。
    ; --- 2026-09-13追記その2: 別のSchedule_3.json(501エントリ、
    ; --- ファイル名は前回と同名だが中身は別物)へ再々差し替え、501<512
    ; --- のためH=0/1の2ブロック構成に戻った(同じ一般化のおかげで
    ; --- SSC_FIRE側は各ブロックの本数を数え直すだけで済んだ)。
    ; --- 2026-09-13追記その3: Schedule_5.json(同じ501エントリ、
    ; --- enemy2/enemy4/enemy5の一部の行だけ微調整)へさらに差し替え -
    ; --- 件数・ブロック構成は無変更。
    ; --- 2026-09-14追記: Schedule.json(479エントリ)へ再差し替え -
    ; --- 479<512のためH=0/1の2ブロック構成のまま(SSC_FIRE参照)。
    ; --- 2026-09-14追記その2: Schedule_1.json(476エントリ、末尾付近の
    ; --- simple数件をenemy4へ変更)へさらに差し替え - 476<512のため
    ; --- H=0/1の2ブロック構成のまま(SSC_FIRE参照)。
    ; --- 2026-09-14追記その3(round135follow-up9、"ではこのスケジュール
    ; --- に差し替え"): Schedule_2_1.json(480エントリ)へ差し替え -
    ; --- 480<512のためH=0/1の2ブロック構成のまま。このJSONには初めて
    ; --- type="ebuz"の配置(4件)が含まれており、round135follow-up5で
    ; --- 撤去したハードコードGAME_TICK凍結トリガーの代わりに、SSC_FIRE
    ; --- から他のSPAWN_*ハンドラと全く同じ形でEBUZ_SPAWN_CHAIN_STARTへ
    ; --- 直接ディスパッチする(EBUZ_SPAWN_CHAIN_START自体がRETで終わる
    ; --- ため専用のラッパーは不要、JP先として直接指定できる)。
    ; --- round135follow-up13("ボススポーン条件は固定Tickではなく3体目が
    ; --- 消えたあとにしなきゃダメ...Tick1000以上かつ敵が画面のこってない
    ; --- 事"): ボス自身のスケジュールエントリ(旧index479、閾値992)を
    ; --- 撤去し、N=480→479へ変更。ボス出現は本ルーチンの固定Tick駆動を
    ; --- 完全に離れ、独立したCHECK_BOSS_TRIGGER(MAINLOOP、SKIP_G8直後)が
    ; --- 毎フレーム判定する。
    LD HL,(SPAWN_NEXT_INDEX)
    LD DE,341
    OR A
    SBC HL,DE
    RET NC                      ; index >= N -> schedule finished
    ADD HL,DE                   ; undo the SBC - HL = index again (index-N+N)
    ADD HL,HL                   ; HL = index*2 (word-table stride)
    LD DE,SPAWN_THRESHOLDS
    ADD HL,DE
    LD E,(HL) : INC HL : LD D,(HL)
    LD HL,(GAME_TICK)
    OR A
    SBC HL,DE
    RET C

    ; round136(Schedule_2_2.json、345エントリへ差し替え): Enemy2スポーン
    ; (SPAWN_E2)はAとBのどちらも稼働中なら今回は何もせず戻る(次フレーム
    ; で同じ番号を再チェック)。片方でも空いていればSPAWN_E2がそちらを
    ; 自動選択するので、この各インデックスはもう「Aだけ待つ/Bだけ待つ」を
    ; 区別しない - どちらの枠が空いても即発火。インデックス番号は新JSONで
    ; type=enemy2の位置そのまま(全て255未満、H!=0なら丸ごとスキップ)。
    LD A,(SPAWN_NEXT_INDEX+1)
    OR A
    JR NZ,SSC_FIRE              ; index >= 256 -> can't be any of the (all <256) enemy2 waits
    LD A,(SPAWN_NEXT_INDEX)
    CP 93 : JR Z,SSC_BUSY_E2
    CP 98 : JR Z,SSC_BUSY_E2
    CP 105 : JR Z,SSC_BUSY_E2
    CP 111 : JR Z,SSC_BUSY_E2
    CP 143 : JR Z,SSC_BUSY_E2
    CP 144 : JR Z,SSC_BUSY_E2
    CP 174 : JR Z,SSC_BUSY_E2
    CP 175 : JR Z,SSC_BUSY_E2
    CP 176 : JR Z,SSC_BUSY_E2
    CP 177 : JR Z,SSC_BUSY_E2
    JR SSC_FIRE
SSC_BUSY_E2:
    LD A,(E2A_ACTIVE) : OR A : JR Z,SSC_FIRE   ; A is free -> go (SPAWN_E2 will claim it)
    LD A,(E2B_ACTIVE) : OR A : RET NZ          ; both busy -> wait

SSC_FIRE:
    LD HL,(SPAWN_NEXT_INDEX)
    PUSH HL
    INC HL
    LD (SPAWN_NEXT_INDEX),HL
    POP HL                       ; HL = old index (pre-increment)
    LD A,H
    CP 0 : JP Z,SSC_FIRE_BLK0
    JP SSC_FIRE_BLK1

SSC_FIRE_BLK0:
    LD A,L                       ; H=0, so L = index-0; default handler for this block is SPAWN_SIMPLE
    CP 30   : JP Z,EBUZ_SPAWN_CHAIN_START
    ; range-merged: 31-32 (was 2 individual CP/JP Z entries)
    SUB 31
    CP 2
    JP C,SPAWN_E3_WAVE
    LD A,L
    ; range-merged: 40-41 (was 2 individual CP/JP Z entries)
    SUB 40
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 51-52 (was 2 individual CP/JP Z entries)
    SUB 51
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 54-55 (was 2 individual CP/JP Z entries)
    SUB 54
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 57-58 (was 2 individual CP/JP Z entries)
    SUB 57
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 60-61 (was 2 individual CP/JP Z entries)
    SUB 60
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 63-64 (was 2 individual CP/JP Z entries)
    SUB 63
    CP 2
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 68-69 (was 2 individual CP/JP Z entries)
    SUB 68
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    ; range-merged: 73-74 (was 2 individual CP/JP Z entries)
    SUB 73
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 76   : JP Z,SPAWN_E4B
    CP 78   : JP Z,SPAWN_E4B
    ; range-merged: 80-81 (was 2 individual CP/JP Z entries)
    SUB 80
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 83   : JP Z,SPAWN_E4B
    CP 89   : JP Z,EBUZ_SPAWN_CHAIN_START
    CP 90   : JP Z,SPAWN_E3_WAVE
    CP 92   : JP Z,SPAWN_E4B
    CP 93   : JP Z,SPAWN_E2
    CP 94   : JP Z,SPAWN_E4B
    CP 98   : JP Z,SPAWN_E2
    ; range-merged: 99-101 (was 3 individual CP/JP Z entries)
    SUB 99
    CP 3
    JP C,SPAWN_E4B
    LD A,L
    ; range-merged: 102-104 (was 3 individual CP/JP Z entries)
    SUB 102
    CP 3
    JP C,SPAWN_E4
    LD A,L
    CP 105   : JP Z,SPAWN_E2
    CP 111   : JP Z,SPAWN_E2
    ; range-merged: 120-121 (was 2 individual CP/JP Z entries)
    SUB 120
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 124   : JP Z,SPAWN_E4B
    CP 126   : JP Z,SPAWN_E4B
    CP 128   : JP Z,SPAWN_E4B
    CP 130   : JP Z,SPAWN_E4B
    ; range-merged: 132-133 (was 2 individual CP/JP Z entries)
    SUB 132
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 135   : JP Z,SPAWN_E4B
    CP 142   : JP Z,SPAWN_E4B
    ; range-merged: 143-144 (was 2 individual CP/JP Z entries)
    SUB 143
    CP 2
    JP C,SPAWN_E2
    LD A,L
    CP 145   : JP Z,SPAWN_E4B
    ; range-merged: 146-150 (was 5 individual CP/JP Z entries)
    SUB 146
    CP 5
    JP C,SPAWN_E4
    LD A,L
    CP 151   : JP Z,SPAWN_E4B
    CP 153   : JP Z,SPAWN_E4B
    CP 155   : JP Z,SPAWN_E4B
    ; range-merged: 157-158 (was 2 individual CP/JP Z entries)
    SUB 157
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 160   : JP Z,SPAWN_E4B
    CP 162   : JP Z,SPAWN_E4
    ; range-merged: 163-164 (was 2 individual CP/JP Z entries)
    SUB 163
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 167   : JP Z,SPAWN_E4B
    CP 169   : JP Z,EBUZ_SPAWN_CHAIN_START
    ; range-merged: 174-177 (was 4 individual CP/JP Z entries)
    SUB 174
    CP 4
    JP C,SPAWN_E2
    LD A,L
    ; range-merged: 178-180 (was 3 individual CP/JP Z entries)
    SUB 178
    CP 3
    JP C,SPAWN_E4B
    LD A,L
    ; range-merged: 188-190 (was 3 individual CP/JP Z entries)
    SUB 188
    CP 3
    JP C,SPAWN_E4B
    LD A,L
    ; range-merged: 191-193 (was 3 individual CP/JP Z entries)
    SUB 191
    CP 3
    JP C,SPAWN_E4
    LD A,L
    ; range-merged: 194-195 (was 2 individual CP/JP Z entries)
    SUB 194
    CP 2
    JP C,SPAWN_E4B
    LD A,L
    CP 205   : JP Z,SPAWN_E4B
    CP 208   : JP Z,SPAWN_E4B
    CP 211   : JP Z,SPAWN_E4B
    ; range-merged: 214-215 (was 2 individual CP/JP Z entries)
    SUB 214
    CP 2
    JP C,SPAWN_E6
    LD A,L
    ; range-merged: 217-218 (was 2 individual CP/JP Z entries)
    SUB 217
    CP 2
    JP C,SPAWN_E6
    LD A,L
    ; range-merged: 220-221 (was 2 individual CP/JP Z entries)
    SUB 220
    CP 2
    JP C,SPAWN_E6
    LD A,L
    ; range-merged: 223-224 (was 2 individual CP/JP Z entries)
    SUB 223
    CP 2
    JP C,SPAWN_E6
    LD A,L
    ; range-merged: 226-227 (was 2 individual CP/JP Z entries)
    SUB 226
    CP 2
    JP C,SPAWN_E6
    LD A,L
    ; range-merged: 229-231 (was 3 individual CP/JP Z entries)
    SUB 229
    CP 3
    JP C,SPAWN_E6
    LD A,L
    CP 232   : JP Z,SPAWN_E4
    ; range-merged: 233-235 (was 3 individual CP/JP Z entries)
    SUB 233
    CP 3
    JP C,SPAWN_E6
    LD A,L
    CP 236   : JP Z,SPAWN_E4
    ; range-merged: 237-239 (was 3 individual CP/JP Z entries)
    SUB 237
    CP 3
    JP C,SPAWN_E6
    LD A,L
    CP 240   : JP Z,SPAWN_E4
    ; range-merged: 241-243 (was 3 individual CP/JP Z entries)
    SUB 241
    CP 3
    JP C,SPAWN_E6
    LD A,L
    CP 244   : JP Z,SPAWN_E4
    ; range-merged: 245-247 (was 3 individual CP/JP Z entries)
    SUB 245
    CP 3
    JP C,SPAWN_E6
    LD A,L
    CP 248   : JP Z,SPAWN_E4
    ; range-merged: 249-252 (was 4 individual CP/JP Z entries)
    SUB 249
    CP 4
    JP C,SPAWN_E6
    LD A,L
    CP 253   : JP Z,SPAWN_E4
    ; range-merged: 254-255 (was 2 individual CP/JP Z entries)
    SUB 254
    CP 2
    JP C,SPAWN_E6
    JP SPAWN_SIMPLE

SSC_FIRE_BLK1:
    LD A,L                       ; H=1, so L = index-256; default handler for this block is SPAWN_E6
    CP 2   : JP Z,SPAWN_E4
    CP 7   : JP Z,SPAWN_E4
    CP 11   : JP Z,SPAWN_E4
    CP 17   : JP Z,SPAWN_E4
    CP 22   : JP Z,SPAWN_E4
    CP 27   : JP Z,SPAWN_E4
    CP 34   : JP Z,SPAWN_E4
    CP 39   : JP Z,SPAWN_E4
    CP 44   : JP Z,SPAWN_E4
    CP 49   : JP Z,SPAWN_E4
    CP 53   : JP Z,SPAWN_E4
    CP 56   : JP Z,SPAWN_E4
    CP 59   : JP Z,SPAWN_E4
    CP 62   : JP Z,SPAWN_E4
    CP 65   : JP Z,SPAWN_E4
    CP 68   : JP Z,SPAWN_E4
    CP 71   : JP Z,SPAWN_E4
    CP 74   : JP Z,SPAWN_E4
    CP 77   : JP Z,SPAWN_E4
    CP 80   : JP Z,SPAWN_E4
    CP 83   : JP Z,SPAWN_E4
    CP 84   : JP Z,EBUZ_SPAWN_CHAIN_START
    JP SPAWN_E6
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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

; round135follow-up13("ボススポーン条件は固定Tickではなく3体目が消えた
; あとにしなきゃダメって事だな Tick1000以上かつ敵が画面のこってない事
; だな 残っていないかのチェックは常にやったら無駄なんで1000を超えて
; スポーン条件が満たされたら初めて敵が居ないか調べろ"): MAINLOOPから
; 毎フレーム無条件に呼ばれる(SKIP_G8直後)。BOSS_STATE(0=未出現、
; BOSS_SPAWNが1にセット)がそのまま一回性のラッチを兼ねるので、二重
; スポーン防止の追加フラグは不要。GAME_TICKの上位byteが4未満
; (GAME_TICK<1024)の間は各プールの走査自体を一切行わない("1000を
; 超えて...初めて")。EBULLET_POOL(敵弾/投射物)は指示の「敵」に
; 含めず対象外。
CHECK_BOSS_TRIGGER:
    LD A,(BOSS_STATE)
    OR A
    RET NZ
    LD A,(GAME_TICK+1)
    CP 4
    RET C
    LD HL,ENEMY_POOL : LD B,ENEMY_SLOT_COUNT : LD DE,ENEMY_SLOT_SIZE
    CALL SCAN_POOL_ACTIVE
    RET NZ
    ; round135follow-up15: ENEMY6は専用のENEMY6_ACTIVE_COUNT(CHECK_
    ; BULLET_VS_ENEMY6と同じ短絡最適化)を持つため、ここも32スロットの
    ; SCAN_POOL_ACTIVE呼び出しを経由せずO(1)で判定できる。
    LD A,(ENEMY6_ACTIVE_COUNT)
    OR A
    RET NZ
    ; DE must be set explicitly here now (was previously inherited from
    ; the ENEMY6 SCAN_POOL_ACTIVE call's own LD DE,4 before that call was
    ; replaced by the O(1) ENEMY6_ACTIVE_COUNT check above - DE no longer
    ; happens to already be 4 at this point).
    LD HL,ENEMY3_WAVE_POOL : LD B,ENEMY3_WAVE_SLOTS : LD DE,4
    CALL SCAN_POOL_ACTIVE
    RET NZ
    LD A,(E2A_ACTIVE)
    OR A
    RET NZ
    LD A,(E2B_ACTIVE)
    OR A
    RET NZ
    CALL EBUZ_ANY_ACTIVE
    OR A
    RET NZ
    JP EBUZ2_ON_BOSS_TRIGGER

; Input: HL=pool base, B=slot count, DE=stride (each slot's own first
; byte is treated as its active flag). Output: A=0(Z) if every slot is
; inactive, A=1(NZ) on the first active slot found. Trashes A,B,HL.
SCAN_POOL_ACTIVE:
    LD A,(HL)
    OR A
    RET NZ
    ADD HL,DE
    DJNZ SCAN_POOL_ACTIVE
    RET

; (2026-09-14、round137follow-up、"キャラデータはかなり圧縮ができる筈
; RLEで十分だろう"): tools/title_screen/title_bg_gen.pyのrle_encode/
; rle_decode(制御バイトbit7=0がリテラル run・bit7=1が反復run、終端は
; ストリームに埋め込まず別途渡すセグメント数down-counterで判定)と
; 完全に同じフォーマットのZ80側デコーダ。Stage2のLOAD_SASAPI_PATTERNS
; 用DECOMPRESS_RLE_TO_VRAMと同一実装(このファイルはバンク切替を
; 一切行わないためHLはROM/RAMどちらでも同じ命令列で読める)。
; CLAUDE.md恒久ルール通りOTIR等のブロックI/O命令は使わず、DJNZによる
; 手動OUTループのみで実装。
; in: HL=RLE圧縮データの先頭、DE=セグメント数。呼び出し前にVDP書き込み
; アドレス(オートインクリメント)を2回のOUT (99h)で設定しておくこと。
; 破壊: A,B,DE,HL。
DECOMPRESS_RLE_TO_VRAM:
    LD A,(HL) : INC HL
    OR A
    JP M,DRTV_RUN                   ; bit7=1(符号ビット) -> 反復セグメント
    AND 7Fh
    INC A
    LD B,A
DRTV_LIT_LOOP:
    LD A,(HL) : INC HL
    OUT (98h),A
    DJNZ DRTV_LIT_LOOP
    JR DRTV_NEXT
DRTV_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
DRTV_RUN_LOOP:
    OUT (98h),A
    DJNZ DRTV_RUN_LOOP
DRTV_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,DECOMPRESS_RLE_TO_VRAM
    RET

BOSS_SPAWN:
    CALL BOSS_CLEAR_DYNAMIC_ENEMIES
    ; ボス到達時に1回だけ点数判定(2026-09-24から6万4千点、旧5万点): SCORE(実得点/100)
    ; <GAUGE_MAX*10ならPOD_AIM_NORMAL=0(上位byte!=0ならそのまま非0を格納、それ以外は
    ; 640以上でSBC A,A=FFh)
    LD A,(SCORE+2) : OR A
    JR NZ,BS_AIM_STORE
    LD HL,(SCORE) : LD DE,-640 : ADD HL,DE   ; C=1 if SCORE>=640
    SBC A,A
BS_AIM_STORE:
    LD (POD_AIM_NORMAL),A
    ; --- load boss pattern data now, just in time - not preloaded ---
    ; --- at INIT (that permanently claimed codes192-255, which    ---
    ; --- the terrain scroller actually needs some of - see INIT). ---
    ; (2026-09-14) BOSS_PATTERNSはRLE圧縮済み - DECOMPRESS_RLE_TO_VRAM
    ; 自身のコメント参照。
    LD DE,192*8
    LD A,E : OUT (99h),A
    LD A,D : OR 40h : OUT (99h),A
    LD HL,BOSS_PATTERNS
    LD DE,BOSS_PATTERNS_SEGMENTS
    CALL DECOMPRESS_RLE_TO_VRAM
    ; round145("先端1pxの判定を入れてくれ"対応作業のROM予算確保):
    ; BOSS_HEX/ORBIT_PATTERN・DFL_BULLET_PATTERN・EXPLOSION_PATTERNは
    ; VRAM上でcodes96-111の連続128byteなので、旧来の4回の32byte
    ; LDIRVMを1回へ統合した上で、BOSS_PATTERNSと同じ自前RLEで圧縮
    ; (128byte->72byte、DECOMPRESS_RLE_TO_VRAM経由)。
    LD DE,96*8+SPRPAT
    LD A,E : OUT (99h),A
    LD A,D : OR 40h : OUT (99h),A
    LD HL,BOSS_MISC_PATTERNS
    LD DE,BOSS_MISC_PATTERNS_SEGMENTS
    CALL DECOMPRESS_RLE_TO_VRAM
    XOR A : LD (BOSS_ROW),A
    XOR A : LD (BOSS_COL),A
    LD A,1 : LD (BOSS_PHASE),A
    ; (2026-09-23、監査で発見): DFL_UPDATEはマテリアライズ中(BOSS_STATE=1)から
    ; 動くが、DFL0-2_ACTのクリアは着地時(DFL_FORCE_CLEAR)にしかなかった -
    ; INIT未初期化/前回プレイの残りの偏向弾が出現直後に不定座標で描かれていた。
    CALL DFL_FORCE_CLEAR
    LD A,1 : LD (BOSS_STATE),A
    CALL MUTE_BGM   ; "マテリアライズに入る前にそれまでのBGMは停止"
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
    ; "マテリアライズ中のショットの反射弾が残ってる 前はそんな事なく
    ; 消えてた" - DFL0-2(偏向弾)が着地の瞬間まだ生存していると、直後の
    ; BOSS_ORBIT_DRAW_ALLが同じハードウェアスプライトスロット(9-11)を
    ; 周回ポッドとして奪い合ってしまう(DFL_FORCE_CLEAR自身のコメント
    ; 参照)。周回ポッドがスロットを専有する前に強制的に片付ける。
    CALL DFL_FORCE_CLEAR
    LD A,2 : LD (BOSS_STATE),A
    CALL SWITCH_BGM_TO_TRYZ   ; "ではTryZをボス曲に...マテリアライズ終了後に再生"
    ; --- boss has landed - repoint the 6 dispatch vectors at the  ---
    ; --- BOSS_MAP-aware routines instead of BLANKCODE. Just a     ---
    ; --- 2-byte pointer write each, once, here - not on every     ---
    ; --- bullet-erase call.                                       ---
    LD HL,SKY_SLOW_H : LD (SKY_VEC_H),HL
    LD HL,SKY_SLOW_E : LD (SKY_VEC_E),HL
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
    XOR A : LD (POD_BULLET0_DY),A
    XOR A : LD (POD_BULLET1_DY),A
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
    ; (2026-09-07、Round60系の再起動時RAM初期化漏れ監査で併せて発見):
    ; DFL0-2_ACT(ボス偏向弾3スロット)もこのボス専用サブシステム群の
    ; 一員でありながら、この一括初期化ブロックに含まれていなかった。
    ; 直前のプレイ(ゲームオーバーで中断された場合)がボス戦中に終了
    ; していれば、次のボス出現時に前回の偏向弾の残骸がそのまま復活
    ; しうる潜在バグ。他のPOD_*と同じくボススポーン時点で毎回
    ; アトミックにゼロクリアする設計に合わせる。
    XOR A : LD (DFL0_ACT),A
    LD (DFL1_ACT),A
    LD (DFL2_ACT),A
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

; sets the fixed boss-effect sprite's Y (15+row*8) and X (208+col*8 -
; directly over the 8x8 cell about to be redrawn), pattern (fixed),
; and color=white, for the start of a new tile.
BOSS_SETUP_TILE_SPRITE:
    LD A,(BOSS_ROW)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,15
    LD (BOSS_YTMP),A
    LD A,(BOSS_COL)
    ADD A,A : ADD A,A : ADD A,A
    ADD A,208
    LD (BOSS_XTMP),A
    CALL BOSS_SPR_SET_YXP
    LD A,15 : CALL BOSS_SPR_SET_COLOR
    RET

; draws the single current tile (BOSS_ROW,BOSS_COL) into the
; nametable: dest = 185Ah + row*32 + col, source = BOSS_MAP + row*5 + col
; Raw OUT sequence (not LDIRVM) with extra NOP padding - testing
; whether the terrain corruption is a VDP-timing issue (2 NOPs is
; normally enough everywhere else in this file, but this write
; happens via a different code path than the established one, so
; bumping the margin here specifically to check).
BOSS_DRAW_CUR_TILE:
    LD A,(BOSS_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,185Ah
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
    LD A,D : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_TILETMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_CTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,71
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_ORBIT_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_CTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD HL,CHECK_BULLETC_VS_PODS
    JP BULLET_EACH

CHECK_BULLETC_VS_PODS:
    LD A,(BULLETC_COL) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_X),A
    LD A,(BULLETC_ROW) : ADD A,A : ADD A,A : ADD A,A
    LD (POD_XY_Y),A
    LD B,0
CBC_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,CBC_SKIP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CBC_SKIP
    CP 141
    JR NC,CBC_SKIP
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,CBC_SKIP
    CP 141
    JR NC,CBC_SKIP
    CALL POD_HIT
    POP BC
    JP CBC_ERASE
CBC_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JP NZ,CBC_LOOP
    RET
CBC_ERASE:
    LD A,(BULLETC_ROW) : SUB 2 : CP 16 : JR NC,CBC_ERASE_FAST
    LD B,A : LD A,(BULLETC_COL) : SUB 26 : CP 5 : JR NC,CBC_ERASE_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    LD (TEMP_ERASE_BYTE),A
    LD A,(BULLETC_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLETC_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : LD (BULLETC_ACT),A
    EI
    RET
CBC_ERASE_FAST:
    LD A,(BULLETC_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLETC_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,BLANKCODE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : LD (BULLETC_ACT),A
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    ; (2026-09-23、ボスレーザー干渉): 最後のポッド撃破で即爆発せず、ボスの
    ; 中央レーザー→干渉へ(LZ_BOSS_FIRE)。勝てばLZ_WINがSTART_BOSS_DEATHを呼ぶ。
    CALL LZ_BOSS_FIRE
    JR PHD_SKIP_BOSSEXPL
START_BOSS_DEATH:
    ; "ステージ1ボスは10000点"(2026-09-13) - fires exactly once, right
    ; alongside BOSS_EXPL_STARTED's own one-shot guard above (the last
    ; pod's own destroy is what triggers the boss's death sequence in
    ; this game - see this routine's own comment). ADD_SCORE_COMMON
    ; units are real_points/100 (see ADD_SCORE_100/200/300's own
    ; comment), so 100 = 10000 real points.
    LD HL,100 : CALL ADD_SCORE_COMMON
    CALL BOSS_EXPL_BUILD_LUT
    ; --- bullets erasing themselves over the (now emptying) boss   ---
    ; --- area were "restoring" BOSS_MAP tiles we'd already popped  ---
    ; --- (SKY_SLOW_* repaints from BOSS_MAP). Switch back to the   ---
    ; --- plain-sky vectors so an erase just leaves blank sky.      ---
    LD HL,SKY_FAST_H : LD (SKY_VEC_H),HL
    LD HL,SKY_FAST_E : LD (SKY_VEC_E),HL
    RET
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,EXPLOSION_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    ; (2026-09-06、"一旦左端まで下がってから飛び去る様に変更"): 従来は
    ; ここで直接PLAYER_FLYAWAY_WAITを起動していたが、その前に自機を
    ; 画面左端(X=0)まで後退させる(PLAYER_RETREAT_ACT、下のPFA_NO_
    ; RETREAT周り参照) - PLAYER_FLYAWAY_WAIT/SPDの起動自体はPFA_
    ; RETREAT_DONEへ移動、ここでは起動しない。
    LD A,1 : LD (PLAYER_RETREAT_ACT),A
    XOR A : LD (SND_TONE_TIMER),A
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
    LD DE,185Ah
    ADD HL,DE
    LD A,(BOSS_EXPL_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,BLANKCODE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP

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
    LD HL,BOSS_EXPL_INDEX : INC (HL)
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
    LD A,71
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
    LD A,(POD_BULLET0_X) : LD D,A
    LD A,(POD_BULLET0_Y) : LD E,A
    PUSH BC                       ; save pod-pair index (B) across the call
    CALL POD_BULLET_CALC_DIR      ; D,E in -> B=dxmag(1-12),C=dy(signed)
    LD A,B : LD (POD_BULLET0_DXMAG),A
    LD A,C : LD (POD_BULLET0_DY),A
    POP BC
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
    LD A,(POD_BULLET1_X) : LD D,A
    LD A,(POD_BULLET1_Y) : LD E,A
    PUSH BC                       ; save pod-pair index (B) across the call
    CALL POD_BULLET_CALC_DIR      ; D,E in -> B=dxmag(1-12),C=dy(signed)
    LD A,B : LD (POD_BULLET1_DXMAG),A
    LD A,C : LD (POD_BULLET1_DY),A
    POP BC
    LD HL,POD_RECOIL : LD D,0 : LD E,B : ADD HL,DE
    LD (HL),POD_RECOIL_DURATION
    CALL POD_BULLET_DRAW1
PFDP_SKIP1:
    RET

; (2026-09-19、"ステージ1ボスの改良 接近時の自機狙い弾の精度が低いん
; で24や32方向に と言ってもプレイヤーは常に左に居るんでLUTは180度分
; で済むはず"): 旧POD_BULLET_CALC_DYの「DY=-2/0/+2のみ、Xは常に固定
; 速度」という粗いホーミングを、実際の(dx,dy)を32方向に量子化して
; 狙う本物の2D照準へ全面書き換え。プレイヤーは常にpodより左に居る
; という前提(ユーザー指示)を活かし、360度分ではなく180度分(半円)の
; LUTだけで済ませている - dxは常に負(またはゼロ)として畳み込み、
; fy(dyの符号)とsw(オクタント内での軸入れ替え)の2ビットのみで半円
; 全体をカバーする(2^2 x 8方向刻み=32方向)。
;
; 乗算・除算命令が無いZ80のため、各方向境界の判定は「ay > (ax*Kの
; 上位byte)」(Kは256*tan(境界角)を四捨五入した8bit固定小数点定数、
; POD_AIM_MUL8で8x8→16bit乗算のみ使用、除算は一切不使用)という形に
; 単純化。fold_code=(fy<<4)|(sw<<3)|bucket(0-7、7回の境界判定の
; 合格数)をPOD_AIM_DIR_LUT(高密度サンプリングで決定、ebullet_gen.py
; のDIR16_LUTと同じ「手作業の折り畳み代数はミスしやすいため機械的に
; 決定する」手法)で最終的な方向index(0-31)へ変換する。
;
; 全ての定数・分類ロジックは、実際のZ80命令列をPython側でビット単位で
; シミュレートした上で(dx,dy)の全域(signed byte全組み合わせ)に対する
; 高密度サンプリングにより検証済み - 理想角度(atan2)との誤差は最大でも
; 1方向ステップ(5.625度)に収まることを確認している。
;
; Input: D=podX, E=podY(発射の瞬間の値)。Output: B=dxmag(1-12、常に
; 正の絶対値、元の固定POD_BULLET_SPEEDと同じ「Xから毎フレーム減算し
; アンダーフローで画面外判定」のidiomをそのまま維持するため)、
; C=dy(符号付き、-12〜+12、0=水平)。POD_BULLET_HOMING_THRESHOLD_X
; ゲート(PLAYERXが半分を超えるまでは直進)は変更なし。呼び出し元
; (POD_FIRE_DO_PAIR)は自身のpod-pair index(B)をこの呼び出し前後で
; 自分でPUSH/POPすること(この関数はB/Cを出力に使うため)。
POD_BULLET_CALC_DIR:
    ; (2026-09-23): 照準ゲート+dx/dy計算はPOD_AIM_PREP(ファイル末尾)へ。
    ; C=直進、NC=自機狙い(D=dx/2,E=dy/2、符号付き)。
    CALL POD_AIM_PREP
    JR C,PBCDIR_STRAIGHT
    ; (round145follow-up、"ボスの自機狙いポッド弾が左から出てしまう事が
    ; ある"): dx>=0(podが自機より左)は弾が左にしか飛ばないため直進へ
    ; フォールバック(POD_AIM_PREP内)。
    CALL POD_AIM_CLASSIFY           ; A = 方向index(0-31)
    LD C,A                          ; C = 方向indexを一時保持
    LD H,0 : LD L,A
    LD DE,POD_AIM_DXMAG_TABLE
    ADD HL,DE
    LD B,(HL)                       ; B = dxmag
    LD H,0 : LD L,C
    LD DE,POD_AIM_DY_TABLE
    ADD HL,DE
    LD A,(HL)
    LD C,A                          ; C = dy(符号付き) - 方向indexは
                                     ; もう不要なので上書き
    RET
PBCDIR_STRAIGHT:
    LD B,POD_BULLET_SPEED
    LD C,0
    RET

; Input: D=dx(signed, PLAYERX-podX), E=dy(signed, PLAYERY-podY)
; Output: A = 方向index(0-31)。Clobbers: A,B,C,D,E,H,L(全て)。
; (2026-09-19、mini_z80asm.pyがNEG/SET/SLA/RL命令を一切サポートして
; いないと判明したため、以下は全てLD/INC/DEC/ADD/SUB/AND/XOR/OR/CP/
; SRL/JR/JP/CALL/RET/PUSH/POPのみで書き直し済み。NEGの代替は
; 「XOR A:SUB r」(0-r=2の補数の負数)、SET n,rの代替は
; 「LD A,r:OR (1<<n):LD r,A」で代用。乗算(ay*K)はSLA/RLによる
; ランタイムシフトループの代わりに、K(コンパイル時定数)ごとに
; ADD HL,HL(倍加)/ADD HL,DE(axを加算)だけを使う「定数乗算の
; シフト&加算展開」(2進数表現をMSBから辿るだけ、除算・ランタイム
; ループ一切不要)で実装 - Pythonで機械生成し(HANDOFF.md参照)、
; 生成結果をそのままここに貼り付け。)
POD_AIM_CLASSIFY:
    LD A,D
    OR A
    JP M,PAC_NEGDX
    XOR A                            ; dx>=0(通常発生しない想定の
    JR PAC_UDONE                     ; 端数ケース) -> u=0
PAC_NEGDX:
    XOR A : SUB D                    ; A = 0-dx = -dx = u
PAC_UDONE:
    LD B,A                           ; B = ax候補(u)
    LD C,0                           ; fold蓄積用
    LD A,E
    OR A
    JP P,PAC_DYPOS
    LD A,C : OR 10h : LD C,A         ; fy=1(dyが負=上方向)
    XOR A : SUB E                    ; A = 0-dy = |dy|
    JR PAC_AYDONE
PAC_DYPOS:
    LD A,E                           ; dyは既に0以上
PAC_AYDONE:
    CP B
    JR C,PAC_FOLD_DONE               ; ay<ax: swapなし
    JR Z,PAC_FOLD_DONE               ; ay==ax: swapなし
    LD D,A                           ; ay>ax: swap. D = ay候補(旧)
    LD A,B                           ; A = ax候補(旧) -> これがay(最終)になる
    LD B,D                           ; B = ay候補(旧) -> これがax(最終)になる
    LD D,A                           ; D = ay(最終)を退避(次のOR 08hで
                                     ; Aを潰す前に、Dはもう空いている
                                     ; ので安全に再利用)
    LD A,C : OR 08h : LD C,A         ; sw=1
    LD A,D                           ; ay(最終)をAへ復元
    JR PAC_AY_A_READY
PAC_FOLD_DONE:
    ; A = ay(最終)のまま
PAC_AY_A_READY:
    ; A = ay(最終), B = ax(最終)
    LD (PAC_AY),A
    LD A,B
    LD (PAC_AX),A

    ; boundary test 0: K=13
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S0
    JR Z,PAC_S0
    INC C
PAC_S0:
    ; boundary test 1: K=38
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S1
    JR Z,PAC_S1
    INC C
PAC_S1:
    ; boundary test 2: K=64
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S2
    JR Z,PAC_S2
    INC C
PAC_S2:
    ; boundary test 3: K=92
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S3
    JR Z,PAC_S3
    INC C
PAC_S3:
    ; boundary test 4: K=121
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S4
    JR Z,PAC_S4
    INC C
PAC_S4:
    ; boundary test 5: K=153
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S5
    JR Z,PAC_S5
    INC C
PAC_S5:
    ; boundary test 6: K=190
    LD A,(PAC_AX) : LD E,A : LD D,0
    LD HL,0
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    ADD HL,DE
    ADD HL,HL
    LD A,(PAC_AY)
    CP H
    JR C,PAC_S6
    JR Z,PAC_S6
    INC C
PAC_S6:
    ; C = fold_code(0-31、bit4=fy,bit3=sw,bit0-2=bucket 0-7。7回の
    ; INCのみでbit0-2は最大7[0b111]までしか到達しないためbit3への
    ; 桁上げは起きない)
    LD H,0 : LD L,C
    LD DE,POD_AIM_DIR_LUT
    ADD HL,DE
    LD A,(HL)
    RET

; fold_code(0-31)->方向index(0-31)変換表。高密度サンプリングで決定
; (手作業の折り畳み代数は符号・swapの組み合わせでミスしやすいため、
; ebullet_gen.pyのDIR16_LUTと同じ手法をPython側で適用し多数決で
; 決定、詳細はHANDOFF.md参照)。
POD_AIM_DIR_LUT:
    DB 16,17,18,19,20,21,22,23,31,31,30,29,28,27,26,25
    DB 16,15,14,13,12,11,10,9,0,1,2,3,4,5,6,7
; 方向index(0-31)ごとのX速度絶対値(1-12、常にXから減算)
POD_AIM_DXMAG_TABLE:
    DB 1,2,3,4,5,6,7,8,9,10,10,11,11,12,12,12
    DB 12,12,12,11,11,10,10,9,8,7,6,5,4,3,2,1
; 方向index(0-31)ごとのY速度(符号付き、-12〜+12)
POD_AIM_DY_TABLE:
    DB 0F4h,0F4h,0F4h,0F5h,0F5h,0F6h,0F6h,0F7h,0F8h,0F9h,0FAh,0FBh,0FCh,0FDh,0FEh,0FFh   ; -12,-12,-12,-11,-11,-10,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1
    DB 001h,002h,003h,004h,005h,006h,007h,008h,009h,00Ah,00Ah,00Bh,00Bh,00Ch,00Ch,00Ch   ; 1,2,3,4,5,6,7,8,9,10,10,11,11,12,12,12

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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,15 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

LAP_MARKER_HIDE:
    LD A,LAP_MARKER_SPR : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

LAP_MARKER_DRAW2:
    LD A,LAP_MARKER_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,15 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

LAP_MARKER_HIDE2:
    LD A,LAP_MARKER_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_YTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(BOSS_ORBIT_XTMP) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_ORBIT_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(POD_VOLLEY_COLOR_TEST) : AND 0Fh : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

POD_BULLET_MOVE:
    LD A,(POD_BULLET0_ACT)
    OR A
    JR Z,PBM_B1
    ; (2026-09-19、32方向照準化): Xの減算量はPOD_BULLET0_DXMAG(1-12、
    ; 発射時にPOD_BULLET_CALC_DIRが決定)を使う - 直進時は常に
    ; POD_BULLET_SPEED(12)が入っているため、アンダーフロー判定
    ; (JR NC)のロジック自体は元のまま完全に維持される。
    LD A,(POD_BULLET0_DXMAG) : LD B,A
    LD A,(POD_BULLET0_X)
    SUB B
    JR NC,PBM_B0_OK
PBM_B0_OFF:
    XOR A : LD (POD_BULLET0_ACT),A
    CALL POD_BULLET_HIDE0
    JR PBM_B1
PBM_B0_OK:
    LD (POD_BULLET0_X),A
    ; (2026-09-13、"ボスの弾は...自機狙い弾になるように変更"): apply the
    ; per-frame Y velocity decided once at fire time (POD_BULLET_CALC_DIR)
    ; - 0 here is byte-identical to the old straight-shot behavior.
    LD A,(POD_BULLET0_Y) : LD B,A
    LD A,(POD_BULLET0_DY) : ADD A,B
    ; (2026-09-23、実機報告"ステージ1ボスでまだ後ろからポッド弾が出てくる"):
    ; 自機狙いの縦成分(最大±12px/frame)で画面の上下端を越えると、Yが8bitで
    ; 回り込んで反対側から再出現していた(途中Y=208はスプライト終端の意味にも
    ; なる)。X方向と同じく、可視範囲(Y<192)を外れたら消す。
    CP 192
    JR NC,PBM_B0_OFF
    LD (POD_BULLET0_Y),A
    CALL POD_BULLET_DRAW0
PBM_B1:
    LD A,(POD_BULLET1_ACT)
    OR A
    RET Z
    LD A,(POD_BULLET1_DXMAG) : LD B,A
    LD A,(POD_BULLET1_X)
    SUB B
    JR NC,PBM_B1_OK
PBM_B1_OFF:
    XOR A : LD (POD_BULLET1_ACT),A
    CALL POD_BULLET_HIDE1
    RET
PBM_B1_OK:
    LD (POD_BULLET1_X),A
    LD A,(POD_BULLET1_Y) : LD B,A
    LD A,(POD_BULLET1_DY) : ADD A,B
    CP 192
    JR NC,PBM_B1_OFF
    LD (POD_BULLET1_Y),A
    CALL POD_BULLET_DRAW1
    RET

POD_BULLET_DRAW0:
    LD A,POD_BULLET_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(POD_BULLET0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(POD_BULLET0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,15 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

POD_BULLET_DRAW1:
    LD A,POD_BULLET_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(POD_BULLET1_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(POD_BULLET1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,BOSS_HEX_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,15 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

POD_BULLET_HIDE0:
    LD A,POD_BULLET_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

POD_BULLET_HIDE1:
    LD A,POD_BULLET_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

; called every frame while BOSS_STATE==1 (materializing only - once
; landed, the SKY_VEC dispatch already handles restoring boss BG
; correctly, so no guard is needed there). Checks each of the
; BULLET_SLOTS player shots; any that reaches col25 (row1-16) is deflected
; before it can ever touch the boss's own cols26-30, which used to
; leave permanent gaps (the erase there was writing BLANKCODE over
; boss cells that hadn't been safely handled yet).
BOSS_GUARD_UPDATE:
    LD HL,BOSS_GUARD_ONE
    JP BULLET_EACH
BOSS_GUARD_ONE:
    LD A,(BULLETC_ROW) : SUB 2 : CP 16 : RET NC
    LD A,(BULLETC_COL) : CP 25 : RET C
    ; fall through
; erases the shot's current BG cell (safe here - col25 is still
; outside the boss's own cols26-30), deactivates it, and spawns a
; deflected sprite in its place with a random left-biased vector.
DEFLECT_BULLETC:
    LD A,(BULLETC_ROW)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h
    ADD HL,DE
    LD A,(BULLETC_COL)
    LD D,0 : LD E,A
    ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,BLANKCODE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : LD (BULLETC_ACT),A
    ; スロット0-2はDFL0-2、3-4はDFL0-1(ボス出現中の演出用、同時に来たら上書き)
    LD A,(BULLET_CUR_IDX) : CP 3
    JR C,DB_DFL
    SUB 3
DB_DFL:
    LD C,A
    ADD A,A : ADD A,A : ADD A,C : LD E,A : LD D,0
    LD HL,DFL0_ACT : ADD HL,DE     ; DFLn: +0 ACT,+1 X,+2 Y,+3 VEC,+4 LIFE
    LD (HL),1 : INC HL
    LD A,(BULLETC_COL) : ADD A,A : ADD A,A : ADD A,A : LD (HL),A : INC HL
    LD A,(BULLETC_ROW) : ADD A,A : ADD A,A : ADD A,A : LD (HL),A : INC HL
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A : AND 7 : LD (HL),A : INC HL
    LD (HL),DFL_LIFESPAN
    EI
    LD A,C
    OR A
    JP Z,DFL_DRAW0
    DEC A
    JP Z,DFL_DRAW1
    JP DFL_DRAW2

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

; (2026-09-07、実機フィードバック対応、"マテリアライズ中のショットの
; 反射弾が残ってる 前はそんな事なく消えてた"): DFL0-2はDFL_SPR0-2=9,10,11
; という固定ハードウェアスプライトスロットを使っており、これは
; 「マテリアライズ中に(DFL_LIFESPAN=40フレームで)消え切っている前提で、
; 着地後に専有するスロット6-13の周回ポッドと安全に重複できる」という
; 設計だった(DFL_SPR0のEQU直前コメント参照)。しかし着地の瞬間に
; たまたま生存中の偏向弾が1体でも残っていると、直後のBOSS_ORBIT_
; DRAW_ALL(周回ポッド8機、スロット6-13を使用)がDFL用スロット9-11を
; 奪い合い、壊れた/凍りついた見た目のまま残留し続けるバグだった
; (DFL_UPDATE自体はBOSS_STATE!=0の間ずっと呼ばれ続けるが、スロットが
; 別の絵で上書きされ続けるため正しく消せない)。着地の瞬間(周回ポッドが
; スロットを専有し始める前)に強制的に非表示化・非アクティブ化して
; この競合自体を発生させない。
DFL_FORCE_CLEAR:
    XOR A
    LD (DFL0_ACT),A
    LD (DFL1_ACT),A
    LD (DFL2_ACT),A
    CALL DFL_HIDE0
    CALL DFL_HIDE1
    CALL DFL_HIDE2
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

DFL_DRAW1:
    LD A,DFL_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL1_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

DFL_DRAW2:
    LD A,DFL_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,1 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(DFL2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,2 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,DFL_BULLET_PATNUM : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,E : ADD A,3 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,8 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

DFL_HIDE0:
    LD A,DFL_SPR0 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

DFL_HIDE1:
    LD A,DFL_SPR1 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

DFL_HIDE2:
    LD A,DFL_SPR2 : ADD A,A : ADD A,A : LD E,A : LD D,0
    DI
    LD A,E : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
; index (SSC_FIRE's CP-dispatch leaves the pre-increment index in HL,
; 16bit since 2026-09-12 - see SPAWN_SCHEDULE_CHECK's own comment),
; used to look up this spawn's Y in SPAWN_SIMPLE_Y_TABLE.
SPAWN_SIMPLE:
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

; true free-list sprite-number allocator: scans SPRITE_USED[8..31]
; for the first byte still 0 (free), claims it (sets 1), returns its
; number in A. Unlike the old blind round-robin counter, this can
; never hand out a number that's still in use elsewhere, which is
; what was corrupting a still-displayed enemy's VDP attribute entry
; (stray white Y=0 sprites - the two writers were racing on the same
; attribute-table slot). Returns A=0 if all 24 are taken (should not
; happen - current max concurrent users is well under 24); callers
; don't currently check for this since it can't occur in practice.
; (2026-09-13、"敵弾のプライオリティを自機とバリアの次に"): slots 2-7
; (EBULLET_SPR_BASE_SLOT..+EBULLET_SLOTS-1) are no longer part of this
; shared pool - EBULLET now owns them as a fixed dedicated range (see
; EBULLET_SPR_BASE_SLOT's own comment), so this scan starts at 8 instead
; of 2 and covers 24 slots instead of 30. A real full-schedule MAINLOOP
; simulation confirmed peak concurrent non-EBULLET usage never exceeds
; 12, well within the new 24-slot budget.
ALLOC_SPRITE_NUM:
    LD HL,SPRITE_USED+8
    LD B,24
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

; Output: A = a pseudo-random value in 3-5 inclusive, off the shared
; free-running counter (see DFL_RNG) - same "for now, plain range off
; DFL_RNG" idiom as CLOUD_RANDOM_WAIT. AND 3 gives 0-3 (4 outcomes);
; folding the rare 3 back to 0 keeps the result in {3,4,5} (a slight
; bias toward 3, acceptable for a pseudo-random spawn-count gate, same
; looseness this codebase already accepts elsewhere). Trashes A.
RANDOM_3_5:
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 3
    CP 3
    JR NZ,R35_OK
    XOR A
R35_OK:
    ADD A,3
    RET

; "E1,E2,E5はランダムに3から5機に一度発射" - shared "designated
; shooter" gate. Input: HL = address of a per-type countdown byte
; (pre-seeded to RANDOM_3_5 at INIT). Call once per new spawn of that
; type. Output: A=1 if THIS spawn is the designated shooter (the
; countdown just reached 0 and has been reseeded to a fresh random
; 3-5), A=0 otherwise (countdown just decremented). Trashes A.
DECIDE_FIRE_SHOOTER:
    LD A,(HL)
    DEC A
    LD (HL),A
    JR NZ,DFS_NO
    CALL RANDOM_3_5
    LD (HL),A
    LD A,1
    RET
DFS_NO:
    XOR A
    RET

; Zeroes every slot of the enemy-bullet pool (ACTIVE=0). Called once
; from INIT, same idiom as ENEMY_POOL_INIT.
EBULLET_POOL_INIT:
    LD HL,EBULLET_POOL
    LD DE,EBULLET_POOL+1
    LD BC,EBULLET_SLOTS*EBULLET_STRUCT-1
    LD (HL),0
    LDIR
    RET

; Claims a free EBULLET_POOL slot, then arms it to fly. Input: D=X,E=Y
; (spawn position, sprite top-left). If the pool is full, silently drops
; the shot - same "pool exhaustion -> drop" idiom as ENEMY4_CLAIM_ANY's
; own pattern-slot exhaustion handling. Preserves the caller's own IX
; (used internally, restored before RET) so this is safe to call from
; inside another entity's own IX-indexed update. Trashes A,B,DE,HL.
; (2026-09-13、"敵弾のプライオリティを自機とバリアの次に"): the hw
; sprite number is now a FIXED dedicated slot (EBULLET_SPR_BASE_SLOT +
; this pool slot's own index), not an ALLOC_SPRITE_NUM allocation from
; the shared pool - see EBULLET_SPR_BASE_SLOT's own comment. This can
; never fail/exhaust (unlike the old ALLOC_SPRITE_NUM call), so the
; "no hw sprite available" drop path is gone.
SPAWN_EBULLET:
    PUSH IX
    LD HL,EBULLET_POOL
    LD B,EBULLET_SLOTS
SEB_SCAN:
    LD A,(HL)
    OR A
    JR Z,SEB_FOUND
    PUSH DE
    LD DE,EBULLET_STRUCT
    ADD HL,DE
    POP DE
    DJNZ SEB_SCAN
    POP IX
    RET                      ; pool full - drop
SEB_FOUND:
    PUSH HL : POP IX
    LD A,EBULLET_SLOTS : SUB B : ADD A,EBULLET_SPR_BASE_SLOT
    LD (IX+3),A              ; SPRNUM (fixed - see header comment)
    LD (IX+1),D              ; X
    ; 実機フィードバック"敵弾(横棒レーザー)が敵との位置が上すぎるんで
    ; 8px下げて" - 全呼び出し元が発射元エネミーの生Y座標をそのまま
    ; 渡しているため、ここ1箇所で+8することで全パターン(Fighter/E1
    ; 整列撃ち・E2編隊・E5サインボブ・E1斜めドッジ)に一括で効く。
    LD A,E : ADD A,8 : LD E,A
    LD (IX+2),E              ; Y
    LD A,1 : LD (IX+0),A     ; ACTIVE
    POP IX
    RET

; Advances every active enemy-bullet slot left by EBULLET_SPEED,
; hiding+freeing+deactivating on exit past the left edge, else
; redrawing it (pattern/color are fixed - see PAT_EBULLET/SPR_
; LIGHTRED). Same DI/EI-wrapped, fixed-NOP VDP-write idiom as every
; other sprite draw in this file. Called once per frame from MAINLOOP,
; alongside ENEMY_POOL_UPDATE_ALL. Preserves the caller's own IX.
; Trashes A,B,DE,HL.
UPDATE_EBULLET_ALL:
    PUSH IX
    LD HL,EBULLET_POOL
    LD B,EBULLET_SLOTS
UEA_LOOP:
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+0)
    OR A
    JR Z,UEA_NEXT
    LD A,(IX+1)
    CP EBULLET_SPEED
    JR NC,UEA_MOVEOK
    ; exiting past the left edge: hide + deactivate. The hw sprite number
    ; itself is a fixed dedicated slot now (EBULLET_SPR_BASE_SLOT's own
    ; comment), not a shared ALLOC_SPRITE_NUM allocation, so there is no
    ; FREE_SPRITE_NUM to call - the slot stays reserved for this same
    ; EBULLET_POOL index permanently.
    LD A,(IX+3)
    DI
    ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    XOR A : LD (IX+0),A
    JR UEA_NEXT
UEA_MOVEOK:
    SUB EBULLET_SPEED
    LD (IX+1),A
    DI
    LD A,(IX+3) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(IX+2) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(IX+1) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DI
    LD A,PAT_EBULLET : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    ; "ステージ1の敵弾の色をライトイエローに変更"(2026-09-08) - 元は
    ; SPR_LIGHTRED(round37の初期実装値)、SPR_YELLOWへ変更。
    LD A,SPR_YELLOW : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
UEA_NEXT:
    POP HL
    LD DE,EBULLET_STRUCT
    ADD HL,DE
    DJNZ UEA_LOOP
    POP IX
    RET

; ============================================================
; --- player damage: contact with any enemy or enemy bullet  ---
; --- costs 1 barrier HP; at 0 HP the next hit ends the game ---
; --- (see PLAYER_DAMAGE_CHECK/PLAYER_TAKE_HIT below).       ---
; ============================================================

; Player-vs-ENEMY_POOL(Fighter/Wave) contact check. Output: A=1 if the
; player's own hitbox overlaps ANY active instance's live hitbox
; (TYPE_ENEMY4: single box8 at (E_X,E_Y+8), matching EBSD_HT_ENEMY4;
; else TOP/BOT quadrant box8es at (E_X,E_Y)/(E_X+8,E_Y+8), matching
; EBSB_HIT_TEST/EBSD_HIT_TEST) - same source-of-truth geometry as the
; existing player-bullet-vs-enemy hit tests, just tested against the
; player's own hitbox instead of a bullet's. Does NOT damage/destroy
; the enemy - contact only costs the player a barrier HP (see
; PLAYER_DAMAGE_CHECK), the enemy itself is untouched and keeps flying.
PDC_CHECK_ENEMY_POOL:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
PDCEP_LOOP:
    LD A,(HL)
    OR A
    JR Z,PDCEP_SKIP
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR Z,PDCEP_E4
    LD A,(IX+E_TOP)
    OR A
    JR Z,PDCEP_CHECKBOT
    LD A,(IX+E_X) : LD D,A
    LD A,(IX+E_Y) : LD E,A
    CALL PLAYER_HIT_BOX8
    OR A
    JR NZ,PDCEP_HIT
PDCEP_CHECKBOT:
    LD A,(IX+E_BOT)
    OR A
    JR Z,PDCEP_MISS
    LD A,(IX+E_X) : ADD A,8 : LD D,A
    LD A,(IX+E_Y) : ADD A,8 : LD E,A
    CALL PLAYER_HIT_BOX8
    OR A
    JR Z,PDCEP_MISS
    JR PDCEP_HIT
PDCEP_E4:
    LD A,(IX+E_X) : LD D,A
    LD A,(IX+E_Y) : ADD A,8 : LD E,A
    CALL PLAYER_HIT_BOX8
    OR A
    JR Z,PDCEP_MISS
PDCEP_HIT:
    POP HL
    LD A,1
    RET
PDCEP_MISS:
    POP HL
PDCEP_SKIP:
    LD DE,ENEMY_SLOT_SIZE
    ADD HL,DE
    DJNZ PDCEP_LOOP
    XOR A
    RET

; Shared player-contact scan for one Enemy2 (Zigzag) formation - 3
; units, each a STATE/X/Y/TOP/BOT quintet (E2A_U0_STATE.../E2B_U0_
; STATE... share this exact 5-byte stride - see CHECK_BULLET_VS_
; FORMATION_A/B). Input: HL = the formation's own U0_STATE address.
; Output: A=1 on contact, else 0. Does not kill/redraw anything.
PDC_CHECK_E2_FORMATION:
    LD B,3
PDCE2_LOOP:
    PUSH HL
    LD A,(HL) : CP 1
    JR NZ,PDCE2_SKIP
    INC HL : LD A,(HL) : LD D,A    ; X
    INC HL : LD A,(HL) : LD E,A    ; Y
    INC HL : LD A,(HL)             ; TOP
    OR A
    JR Z,PDCE2_CHECKBOT
    PUSH DE
    PUSH HL                        ; (2026-09-23、監査で発見): PLAYER_HIT_BOX8はH,Lを
    CALL PLAYER_HIT_BOX8           ; PLAYERX/PLAYERYで上書きする - 退避しないと下の
    POP HL                         ; BOT読み出しが無関係な番地(自機座標)を読んでいた
    POP DE
    OR A
    JR NZ,PDCE2_HIT
PDCE2_CHECKBOT:
    INC HL : LD A,(HL)             ; BOT
    OR A
    JR Z,PDCE2_SKIP
    LD A,D : ADD A,8 : LD D,A
    LD A,E : ADD A,8 : LD E,A
    CALL PLAYER_HIT_BOX8
    OR A
    JR Z,PDCE2_SKIP
PDCE2_HIT:
    POP HL
    LD A,1
    RET
PDCE2_SKIP:
    POP HL
    LD DE,5
    ADD HL,DE
    DJNZ PDCE2_LOOP
    XOR A
    RET

; Player-vs-ENEMY3(ground/BG enemy) contact check. Mirrors E3_HIT_
; ONE_SLOT/CHECK_BULLET_VS_ENEMY3's own ACTIVE-count short-circuit and
; COL/ROW*8 pixel-box geometry ((IX+5)=COL->X, (IX+4)=ROW->Y, box8).
; (2026-09-23、監査: Enemy3は生きている個体をENEMY3_ACTIVE_COUNT体見つけた
; 時点で走査を打ち切る。空いたウェーブの後方スロットを調べない)
PDC_CHECK_ENEMY3:
    LD A,(ENEMY3_ACTIVE_COUNT)
    OR A
    JR Z,PDCE3_NONE
    LD C,A                         ; C = まだ見つけていない生存数
    LD HL,ENEMY3_POOL
    LD B,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS
PDCE3_LOOP:
    LD A,(HL)
    OR A
    JR Z,PDCE3_SKIP
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+5) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL PLAYER_HIT_BOX8
    POP HL
    OR A
    JR NZ,PDCE3_HIT
    DEC C
    JR Z,PDCE3_NONE                ; 生存個体を全部調べた
PDCE3_SKIP:
    LD DE,ENEMY3_STRUCT
    ADD HL,DE
    DJNZ PDCE3_LOOP
PDCE3_NONE:
    XOR A
    RET
PDCE3_HIT:
    LD A,1
    RET

; Player-vs-ENEMY6(spin glyph) contact check. Mirrors ENEMY6_HIT_
; ONE_SLOT's own geometry ((IX+2)=COL->X,(IX+1)=ROW->Y, box16 - Enemy6
; is a 16x16 entity, unlike ENEMY3/ENEMY_POOL's 8x8 quads).
PDC_CHECK_ENEMY6:
    ; (2026-09-23、メインループ監査): 1体も居ない時は走査しない(A=0=非被弾)
    LD A,(ENEMY6_ACTIVE_COUNT)
    OR A
    RET Z
    LD HL,ENEMY6_POOL
    LD B,ENEMY6_SLOTS
PDCE6_LOOP:
    LD A,(HL)
    OR A
    JR Z,PDCE6_SKIP
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+1) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL PLAYER_HIT_BOX16
    POP HL
    OR A
    JR NZ,PDCE6_HIT
PDCE6_SKIP:
    LD DE,ENEMY6_STRUCT
    ADD HL,DE
    DJNZ PDCE6_LOOP
    XOR A
    RET
PDCE6_HIT:
    LD A,1
    RET

; Player-vs-boss-pod contact check (only meaningful once the boss has
; landed, BOSS_STATE==2 - same gate MAINLOOP already uses for POD_
; COLLISION_UPDATE/POD_FIRE_UPDATE). Reuses POD_HP/POD_CUR_X/POD_CUR_Y
; (each pod's own live position cache) and the exact same signed-
; delta-window overlap test as CHECK_BULLET0_VS_PODS (SUB+128+range-
; check), just against the player's own position instead of a
; bullet's. Does NOT call POD_HIT - contact only costs the player, the
; pod itself is untouched (mirrors the enemy-body checks above).
PDC_CHECK_PODS:
    LD A,(BOSS_STATE)
    CP 2
    JR NZ,PDCP_BULLETS_ONLY
    LD A,(PLAYERX)
    LD (POD_XY_X),A
    LD A,(PLAYERY)
    LD (POD_XY_Y),A
    LD B,0
PDCP_LOOP:
    PUSH BC
    LD HL,POD_HP : LD D,0 : LD E,B : ADD HL,DE
    LD A,(HL)
    OR A
    JR Z,PDCP_SKIP
    LD HL,POD_CUR_X : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_X)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,PDCP_SKIP
    CP 141
    JR NC,PDCP_SKIP
    LD HL,POD_CUR_Y : LD D,0 : LD E,B : ADD HL,DE
    LD A,(POD_XY_Y)
    SUB (HL)
    ADD A,128
    CP 116
    JR C,PDCP_SKIP
    CP 141
    JR NC,PDCP_SKIP
    POP BC
    LD A,1
    RET
PDCP_SKIP:
    POP BC
    INC B
    LD A,B
    CP 8
    JR NZ,PDCP_LOOP
    ; round145("ステージ1ボスもポッドから発射される弾にコリジョンが
    ; ない...先端1pxの判定を入れてくれ"): ポッド本体(上記)とは独立に
    ; POD_BULLET0/1(発射された弾自体)も自機と判定する。実処理は
    ; ROM予算のALIGN-256境界回避策でファイル末尾のPDC_CHECK_POD_
    ; BULLETSへ切り出し、ここでは最小のJPスタブのみ。
PDCP_BULLETS_ONLY:
    JP PDC_CHECK_POD_BULLETS

; Player-vs-enemy-bullet contact check. Unlike the enemy-body checks
; above, a bullet that touches the player IS consumed (deactivated +
; hidden + its sprite number freed - mirrors UPDATE_EBULLET_ALL's own
; exit-left-edge cleanup) so it doesn't linger or re-trigger next frame.
PDC_CHECK_EBULLET:
    LD HL,EBULLET_POOL
    LD B,EBULLET_SLOTS
PDCEB_LOOP:
    LD A,(HL)
    OR A
    JR Z,PDCEB_SKIP
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+1) : LD D,A
    LD A,(IX+2) : LD E,A
    CALL PLAYER_HIT_BOX_EBULLET
    OR A
    JR Z,PDCEB_MISS
    LD A,(IX+3)
    DI
    ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,(IX+3) : CALL FREE_SPRITE_NUM
    XOR A : LD (IX+0),A
    POP HL
    LD A,1
    RET
PDCEB_MISS:
    POP HL
PDCEB_SKIP:
    LD DE,EBULLET_STRUCT
    ADD HL,DE
    DJNZ PDCEB_LOOP
    XOR A
    RET

; Called once/frame from the tail of MAINLOOP (after all enemies/
; bullets/player movement have updated for this frame). Tests the
; player's own hitbox against every enemy-side entity currently in the
; game (Fighter/Wave, both Zigzag formations, the ground enemy, the
; spin-glyph enemy, boss pods, enemy bullets) in turn, stopping at the
; first overlap found. On a hit: if the barrier still has HP, it
; absorbs the hit (BARRIER_HP-1, then a short invulnerability window
; starts - see BARRIER_IFRAMES - so one overlapping frame can't drain
; more than 1 HP before the entity/player separate again); at 0 HP the
; next hit ends the game (GAME_OVER=1 + an explosion at the player's
; own position - MAINLOOP freezes itself from the very top on the next
; iteration once GAME_OVER is set, so this frame's explosion glyph is
; the last thing left on screen).
; No collision check runs while GAME_OVER is already set, or during
; the post-boss flyaway (PLAYER_FLYAWAY!=0 - the ship is leaving the
; screen, not meaningfully "in" the playfield anymore).
PLAYER_DAMAGE_CHECK:
    LD A,(GAME_OVER)
    OR A
    RET NZ
    LD A,(PLAYER_FLYAWAY)
    OR A
    RET NZ
    LD A,(BARRIER_IFRAMES)
    OR A
    JR Z,PDC_GO
    DEC A : LD (BARRIER_IFRAMES),A
    RET
PDC_GO:
    CALL PDC_CHECK_ENEMY_POOL
    OR A : JP NZ,PLAYER_TAKE_HIT
    LD HL,E2A_U0_STATE : CALL PDC_CHECK_E2_FORMATION
    OR A : JP NZ,PLAYER_TAKE_HIT
    LD HL,E2B_U0_STATE : CALL PDC_CHECK_E2_FORMATION
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_ENEMY3
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_ENEMY6
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_PODS
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL LZ_BARRAGE_HIT            ; ボスの乱射レーザー(条件未達時、LZ_PHASE=5)
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_EBULLET
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_EBUZ
    OR A : JP NZ,PLAYER_TAKE_HIT
    CALL PDC_CHECK_EBUZ2
    OR A
    RET Z
    JP PLAYER_TAKE_HIT

PLAYER_TAKE_HIT:
    LD A,(BARRIER_HP)
    OR A
    JR NZ,PTH_HAS_BARRIER
    ; (2026-09-07、実機フィードバック対応、"画面外に出る処理で壊れたと
    ; 思われる"の調査で自己発見・修正): GAME_OVER=1の間(落下演出中〜
    ; MISSION FAILED表示中を問わず、以後永久に)は、これ以上何度被弾
    ; しても完全に無視する。旧実装はここにガードが無く、既に死亡演出中
    ; でも敵弾に当たるたびPTH_GAMEOVERを何度でも再実行してしまい
    ; (PLAYER_EXPL_TRIGGER/PLAYER_DEATH_FALL_TRIGGER/SOUND_DESTROYを
    ; 都度再発火)、round65で死亡落下の実時間が可変化(最長で旧45フレーム
    ; の2倍以上)したことでこの再トリガーが起こる機会そのものが大幅に
    ; 増えていた。単発の再トリガー自体はメモリ破壊を直接引き起こさない
    ; はずだが、無関係な描画異常の切り分けを容易にするため、そもそも
    ; 「死亡が確定した後の被弾は完全な無効イベント」という一番自然な
    ; 仕様に合わせて先に塞いでおく。
    LD A,(GAME_OVER)
    OR A
    RET NZ
    ; (2026-09-07、"Bボタンならゲームオーバー無しに"): GAMEOVER_ENABLED
    ; ==0の間はバリア枯渇後の被弾を無視する("今は0になっても死なない"、
    ; round37時点の従来挙動と同じ)。
    LD A,(GAMEOVER_ENABLED)
    OR A
    JR Z,PTH_NO_GAMEOVER
    JP PTH_GAMEOVER
PTH_NO_GAMEOVER:
    RET
PTH_HAS_BARRIER:
    DEC A : LD (BARRIER_HP),A
    LD A,BARRIER_IFRAMES_INIT : LD (BARRIER_IFRAMES),A
    ; "次にヒットエフェクトは爆発ではなくカラーチェンジで / 被弾時は
    ; バリア色のホワイトをパープルに / サウンドはブブって2回..." - the
    ; purple flash itself is driven by BARRIER_IFRAMES (just armed
    ; above) in the accent-color-select logic; here just the sound.
    JP SOUND_BARRIER_HIT   ; tail call
PTH_GAMEOVER:
    LD A,1 : LD (GAME_OVER),A
    ; "バリアが無くなったあとの被弾は 16x16のスプライトの爆発パターン
    ; で 自機を起点に複数派手に2秒ほど" - NOT the BG-based TRIGGER_
    ; EXPLOSION (still used for regular enemy kills) - see PLAYER_
    ; EXPL_TRIGGER/PLAYER_EXPL_UPDATE_ALL.
    CALL PLAYER_EXPL_TRIGGER
    ; (2026-09-07、"操作無効の上爆発しながら右斜め下に落下しMission
    ; Failed表示に"): MISSION FAILEDテキストの表示・GAME_OVER_SEQ
    ; 状態機械の起動は、この落下演出が終わった瞬間(UPDATE_PLAYER_
    ; DEATH_FALL、PDF_FINISH参照)まで先送りする - ここでは落下演出の
    ; 起動のみ。
    CALL PLAYER_DEATH_FALL_TRIGGER
    JP SOUND_DESTROY   ; tail call - same "boom" as everything else that dies

; Arms the death-fall sequence (see the player-input block's own
; PFA_DEATH_FALL_STEP, called every frame) - just sets the flag, the
; actual per-frame movement/completion logic lives there. Completion
; is now driven purely by PLAYERY reaching the off-screen threshold
; (199), not a separate frame-count timer.
PLAYER_DEATH_FALL_TRIGGER:
    LD A,1 : LD (PLAYER_DEATH_FALL_ACT),A
    RET

; Kicks off the ~2s player-death burst sequence (see PLAYER_EXPL_
; UPDATE_ALL). Just arms the 2 master timers - the pool itself starts
; genuinely empty (INIT already zeroed it) and gets populated by
; PEUA_TRY_SPAWN as the sequence runs.
PLAYER_EXPL_TRIGGER:
    LD A,PLAYER_EXPL_TOTAL_LEN : LD (PLAYER_EXPL_TOTAL_TIMER),A
    XOR A : LD (PLAYER_EXPL_SPAWN_TIMER),A   ; spawn the first burst right away
    ; (2026-09-23、"ボス時に自機の爆破処理がないな"): ボス出現時に
    ; BOSS_CLEAR_DYNAMIC_ENEMIESがスプライト番号8-31を全部ボス用に予約する
    ; ため、ボス戦中の死亡ではALLOC_SPRITE_NUMが常に失敗して爆発が1つも
    ; 出ていなかった。ボス戦中ならポッド爆発用の26-29を空けて使わせる。
    LD A,(BOSS_STATE) : OR A
    RET Z
FREE_SCATTER_SPRITES:
    XOR A
    LD HL,SPRITE_USED+LZ_SCATTER_SPR : LD B,4
FSS_LOOP:
    LD (HL),A
    INC HL
    DJNZ FSS_LOOP
    RET

; Called unconditionally every frame from MAINLOOP's own tail -
; deliberately NOT gated on GAME_OVER, since "ゲームは止めないでくれ
; チェックできないからな" means play continues normally after death, so
; this has to keep animating on its own regardless of what else is
; happening. A no-op every frame once PLAYER_EXPL_TOTAL_TIMER reaches 0
; and every instance has expired.
;
; Two independent halves: (1) while the master timer is running, spawn
; a new burst instance every PLAYER_EXPL_SPAWN_INTERVAL frames at a
; small pseudo-random offset from the player's own position ("自機を
; 起点に"); (2) unconditionally tick/redraw/expire every already-
; active instance (so already-spawned bursts keep animating even after
; the master timer itself reaches 0 and stops spawning new ones).
; Colors alternate white/light-red by each instance's own timer parity
; for a "派手に" strobing look.
PLAYER_EXPL_UPDATE_ALL:
    LD A,(PLAYER_EXPL_TOTAL_TIMER)
    OR A
    JR Z,PEUA_INSTANCES
    DEC A : LD (PLAYER_EXPL_TOTAL_TIMER),A
    LD A,(PLAYER_EXPL_SPAWN_TIMER)
    OR A
    JR NZ,PEUA_SPAWN_TICK
    LD A,PLAYER_EXPL_SPAWN_INTERVAL : LD (PLAYER_EXPL_SPAWN_TIMER),A
    CALL PEUA_TRY_SPAWN
    JR PEUA_INSTANCES
PEUA_SPAWN_TICK:
    DEC A : LD (PLAYER_EXPL_SPAWN_TIMER),A
PEUA_INSTANCES:
    LD HL,PLAYER_EXPL_POOL
    LD B,PLAYER_EXPL_SLOTS
PEUA_LOOP:
    LD A,(HL)
    OR A
    JP Z,PEUA_NEXT           ; JR out of range now that the color-cycle
                              ; branch logic below made the loop body
                              ; longer (same JP-instead-of-JR fix as
                              ; PEUA_LOOP's own tail jump uses)
    PUSH HL
    PUSH HL : POP IX
    LD A,(IX+3) : DEC A
    JR NZ,PEUA_STILL_ALIVE
    ; expired: hide, free the sprite number, deactivate (mirrors
    ; UPDATE_EBULLET_ALL's own exit cleanup)
    LD A,(IX+4)
    DI
    ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,(IX+4) : CALL FREE_SPRITE_NUM
    XOR A : LD (IX+0),A
    JR PEUA_POP_NEXT
PEUA_STILL_ALIVE:
    LD (IX+3),A
    DI
    LD A,(IX+4) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(IX+2) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(IX+1) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    DI
    LD A,PAT_PLAYER_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    ; (2026-09-07、"ステージ1と同じようにイエローを加えた爆発に"):
    ; 従来の白/ライトレッド2色(タイマーの最下位ビットで交互)から、
    ; タイマー下位2bit(0-3)で白/ライトレッド/イエローの3色サイクルへ
    ; 拡張(2は正確な周期ではないが、視覚的な色サイクル効果自体には
    ; 厳密な均等割りは不要と判断)。値の算出は次のOUT(98h)より前に
    ; 完結するため、既存のVDP書き込み間タイミング(PUSH BC:POP BC:
    ; NOP:NOP、OUT同士の間隔)には一切影響しない。
    LD A,(IX+3) : AND 3
    OR A
    JR Z,PEUA_COLOR_WHITE
    DEC A
    JR Z,PEUA_COLOR_LIGHTRED
    LD A,SPR_YELLOW
    JR PEUA_COLOR_GOT
PEUA_COLOR_WHITE:
    LD A,SPR_WHITE
    JR PEUA_COLOR_GOT
PEUA_COLOR_LIGHTRED:
    LD A,SPR_LIGHTRED
PEUA_COLOR_GOT:
    OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
PEUA_POP_NEXT:
    POP HL
PEUA_NEXT:
    LD DE,PLAYER_EXPL_STRUCT
    ADD HL,DE
    DEC B                    ; DJNZ itself can't reach PEUA_LOOP (loop
    JP NZ,PEUA_LOOP           ; body >127 bytes) - same effect via DEC+JP
    RET

; Finds a free pool slot + a free hw sprite number and spawns one new
; burst instance there; silently does nothing if either is unavailable
; (matches SPAWN_EBULLET's own "pool/sprite exhaustion -> drop" idiom -
; the game keeps running post-death, so other systems can still be
; actively using sprite slots concurrently). Trashes A,B,D,E,H,L,IX.
PEUA_TRY_SPAWN:
    LD HL,PLAYER_EXPL_POOL
    LD B,PLAYER_EXPL_SLOTS
PETS_LOOP:
    LD A,(HL)
    OR A
    JR Z,PETS_FOUND
    LD DE,PLAYER_EXPL_STRUCT
    ADD HL,DE
    DJNZ PETS_LOOP
    RET
PETS_FOUND:
    ; convert to IX BEFORE calling ALLOC_SPRITE_NUM - it trashes HL/B
    ; itself (scans SPRITE_USED with its own loop), so our own scan
    ; pointer has to survive the call some other way (mirrors
    ; SPAWN_EBULLET's own PUSH HL:POP IX before this exact call).
    PUSH HL : POP IX
    CALL ALLOC_SPRITE_NUM
    OR A
    RET Z
    LD (IX+4),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 0Fh : SUB 8 : LD B,A          ; -8..+7 pseudo-random X jitter
    LD A,(PLAYERX) : ADD A,B
    LD (IX+1),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 0Fh : SUB 8 : LD B,A          ; -8..+7 pseudo-random Y jitter
    LD A,(PLAYERY) : SUB 8 : ADD A,B
    LD (IX+2),A
    LD A,PLAYER_EXPL_LIFE : LD (IX+3),A
    LD A,1 : LD (IX+0),A
    ; (2026-09-07、"自機爆破でサウンド追加...ボスの爆発音でいい"):
    ; PTH_GAMEOVER自身の末尾は死亡の瞬間に1回だけSOUND_DESTROYを
    ; tail-callするが、それだけだとボスの死(BEU_FIRE、71回のポップ
    ; それぞれでSOUND_DESTROYを呼ぶ)と違い、その後の約2秒間続く
    ; バーストの残り約14回のスポーンには一切音が伴っていなかった -
    ; 「ボスの爆発音でいい」はこの"ポップごとに毎回鳴る"連続的な
    ; 爆発音の作り方自体を指すと解釈し、BEU_FIREと全く同じ呼び出し
    ; パターン(バースト1回のスポーンごとに1回)をここにも適用する。
    CALL SOUND_DESTROY
    RET

; Same as PEUA_TRY_SPAWN but spawns at an explicit fixed pixel position
; (EBUZ_EXPL_POS_X/Y) instead of a jittered offset from the player -
; used by EBUZ_EXPL_UPDATE_QUEUE for Ebuz's 8-cell death burst
; (2026-09-14、"爆発エフェクトはEbuzセル毎に1回...自機爆発のサウンドと
; スプライトを流用")。
; round141("エネミー4...爆発エフェクトも自機と同じだがサウンドは無しで"):
; 共通部分をPEUA_TRY_SPAWN_AT_COREへ切り出し、SOUND_DESTROY呼び出しの
; 有無だけを2つの薄いラッパー(PEUA_TRY_SPAWN_AT/_QUIET、_QUIETは2026-09-23に廃止)で分岐させる形に
; 分割 - COREはA=1(成功)/0(失敗、プール満杯 or スプライト枯渇)を返す
; だけで一切RETせずに戻るため、呼び出し元(CALL)が成否に応じてサウンドを
; 鳴らすかどうかを選べる。Trashes A,B,D,E,H,L,IX.
PEUA_TRY_SPAWN_AT_CORE:
    LD HL,PLAYER_EXPL_POOL
    LD B,PLAYER_EXPL_SLOTS
PETSA_LOOP:
    LD A,(HL)
    OR A
    JR Z,PETSA_FOUND
    LD DE,PLAYER_EXPL_STRUCT
    ADD HL,DE
    DJNZ PETSA_LOOP
    XOR A
    RET
PETSA_FOUND:
    PUSH HL : POP IX
    CALL ALLOC_SPRITE_NUM
    OR A
    RET Z
    LD (IX+4),A
    LD A,(EBUZ_EXPL_POS_X) : LD (IX+1),A
    LD A,(EBUZ_EXPL_POS_Y) : LD (IX+2),A
    LD A,PLAYER_EXPL_LIFE : LD (IX+3),A
    LD A,1 : LD (IX+0),A
    LD A,1
    RET

PEUA_TRY_SPAWN_AT:
    CALL PEUA_TRY_SPAWN_AT_CORE
    OR A
    RET Z
    JP SOUND_DESTROY


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
; pattern from its current TOP/BOT flags and its own E_PARAM4 (1,2,3,2
; quadrant-anim index - see ASTERISK_PATTERN2/3, EBSD_UPDATE) (mirrors
; the legacy per-unit REDRAW_UNIT_PATTERN call sites). Input: HL =
; slot base address (absolute), A = that slot's pattern-slot index
; (E_PARAM3). Tail-calls into REDRAW_UNIT_PATTERN, which itself takes
; IX as an input (the BOT-flag address) - callers that still need
; their own IX/slot pointer afterward must save it themselves (see
; SIMPLE_SLOT_SCRATCH use in EBSD_HIT_TEST). Trashes A,B,D,E,H,L,IX.
SIMPLE_REDRAW:
    LD (SIMPLE_SLOT_SCRATCH),HL
    PUSH AF
    LD HL,(SIMPLE_SLOT_SCRATCH) : LD DE,E_PARAM4 : ADD HL,DE
    CALL SET_REDRAW_SRC_FROM_SEQ
    POP AF
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

; Single Enemy2 spawn stub for schedule indices 18/19/20/24. Y is now
; just this placement's own row from SPAWN_BASEY_TABLE (same any-row
; mechanism as SPAWN_E4 - see its comment), not a top/bottom preset;
; exit direction (mirrored-Z dive vs normal-Z climb) is computed
; dynamically from PLAYERY once that Y is known, in
; ENEMY_START_COMPLEX_A/B (same idea as EBSD_UPDATE's dodge-direction
; pick for Enemy1). Instance selection (A vs B, i.e. which of the 2
; concurrent complex-formation RAM slots this uses) is no longer tied
; to which stub was called either - it's picked here, whichever is
; currently free (SPAWN_SCHEDULE_CHECK's SSC_BUSY_E2 guard already
; guarantees at least one of them is). A pure capacity/concurrency
; detail like this has no reason to be a choice the schedule editor
; has to make - same reasoning as ENEMY4_CLAIM_ANY picking "any" free
; ENEMY_POOL slot instead of the caller naming one.
SPAWN_E2:
    LD DE,SPAWN_BASEY_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (E2_SPAWN_Y),A
    LD A,2 : LD (ENEMY_CYCLE),A
    LD A,(E2A_ACTIVE)
    OR A
    JP Z,ENEMY_START_COMPLEX_A
    JP ENEMY_START_COMPLEX_B
; A holds this schedule index on entry (SSC_FIRE's CP-dispatch convention -
; see SPAWN_SIMPLE/SPAWN_E4 for the same pattern) - used to look up this
; trigger's own offset in SPAWN_E3_OFFSET_TABLE.
;
; Claims a free ENEMY3_WAVE_POOL slot and arms it with a fresh
; budget/timer/offset of its own - completely independent of every
; other wave slot, so multiple triggers firing close together never
; share or overwrite each other's state (each just runs its own
; ENEMY3_SPAWN_INTERVAL countdown against its own budget). If every
; slot is already claimed, this trigger is dropped.
SPAWN_E3_WAVE:
    LD DE,SPAWN_E3_OFFSET_TABLE
    ADD HL,DE
    LD A,(HL) : LD B,A             ; B = this trigger's own offset (px)

    LD IX,ENEMY3_WAVE_POOL         : LD A,(IX+0) : OR A : JR Z,E3W_FOUND
    LD IX,ENEMY3_WAVE_POOL+4       : LD A,(IX+0) : OR A : JR Z,E3W_FOUND
    LD IX,ENEMY3_WAVE_POOL+8       : LD A,(IX+0) : OR A : JR Z,E3W_FOUND
    RET                              ; no free wave slot - drop this trigger
E3W_FOUND:
    LD A,1 : LD (IX+0),A            ; ACTIVE
    LD A,32 : LD (IX+1),A           ; BUDGET
    LD A,1 : LD (IX+2),A            ; TIMER (fires its first member next frame)
    LD A,B : LD (IX+3),A            ; OFFSET
    XOR A : LD (ENEMY3_SPAWN_COUNT),A
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
    ; (2026-09-23、"合体後も1セルズレたまま移動させたい"): 合体後(ドリフト)も
    ; 1機目-8/3機目+8のまま(横並び回避)。
    LD A,(E2A_Y) : LD (E2A_U1_Y),A : SUB 8 : LD (E2A_U0_Y),A : ADD A,16 : LD (E2A_U2_Y),A
    DI
    LD A,(E2A_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U1_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_EDS_Y0) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_EDS_Y1) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_EDS_Y2) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,2 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_U1_X),A
    EI
    RET
ECS_S1_DRAW_A:
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,4 : LD (E2A_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2A_U2_X),A
    EI
    RET
ECS_S3_DRAW_A:
    DI
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2A_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2A_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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

; Resets E2A_ANIM_SEQ to 0 (base frame) if it wasn't already, and
; redraws all 3 units to match - called once the dive/climb ends.
; Trashes A,B,D,E,H,L,IX.
ECS_S7_A_ANIM_RESET:
    LD A,(E2A_ANIM_SEQ)
    OR A
    RET Z
    XOR A : LD (E2A_ANIM_SEQ),A
    JP E2A_ANIM_REDRAW_ALL

; Rebuilds all 3 of instance A's unit sprite patterns from the
; current E2A_ANIM_SEQ frame. Trashes A,B,D,E,H,L,IX.
E2A_ANIM_REDRAW_ALL:
    LD HL,E2A_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
    LD HL,SPRPAT+256 : LD DE,E2A_U0_TOP : LD IX,E2A_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+288 : LD DE,E2A_U1_TOP : LD IX,E2A_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+320 : LD DE,E2A_U2_TOP : LD IX,E2A_U2_BOT
    CALL REDRAW_UNIT_PATTERN
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
    JP NZ,ECS_S7_HORIZ_A

    ; "E2はランダムに3から5機に一度発射 ただし斜め移動中のみ" - phase0
    ; (this branch) IS Enemy2's own one diagonal-movement window (climb/
    ; dive before leveling to horizontal exit). E2A_FIRE_FLAG was
    ; decided once at spawn (ENEMY_START_COMPLEX_A); 1=shooter/not yet
    ; fired, fires exactly once then flips to 2 (fired). Uses U0's own
    ; position (the formation leader) as the bullet's spawn origin.
    LD A,(E2A_FIRE_FLAG)
    CP 1
    JR NZ,ECS_S7_A_FIRE_DONE
    LD A,2 : LD (E2A_FIRE_FLAG),A
    LD HL,E2A_U0_STATE : CALL E2_FIRE_FROM_ALIVE
ECS_S7_A_FIRE_DONE:

    ; quadrant-glyph animation (1,2,3,2 repeating), shared across all
    ; 3 units - see ECS_S7_RECORD_A's own trail-replay, they move
    ; together with only a delay. Advances once every ENEMY2_ANIM_
    ; FRAME_LEN frames while actively diving/climbing.
    LD A,(E2A_ANIM_TIMER)
    OR A
    JR NZ,ECS_S7_A_ANIM_TICK
    LD A,ENEMY2_ANIM_FRAME_LEN : LD (E2A_ANIM_TIMER),A
    LD A,(E2A_ANIM_SEQ) : INC A : AND 3 : LD (E2A_ANIM_SEQ),A
    CALL E2A_ANIM_REDRAW_ALL
    JR ECS_S7_A_ANIM_DONE
ECS_S7_A_ANIM_TICK:
    DEC A : LD (E2A_ANIM_TIMER),A
ECS_S7_A_ANIM_DONE:

    LD A,(E2A_U0_X) : ADD A,EXIT_SPEED : LD (E2A_U0_X),A
    LD A,(E2A_EXITTYPE)
    OR A
    JR Z,ECS_S7_DOWN_A
    ; climb UP toward TOP_Y - clamp exactly on arrival instead of the
    ; exact-equality check this used to be. That only ever worked
    ; because the old fixed spawn-Y presets (32/128) were always
    ; exactly EXIT_SPEED*16 apart; E2_SPAWN_Y now comes from any row
    ; (SPAWN_BASEY_TABLE), so the remaining distance isn't guaranteed
    ; to be a multiple of EXIT_SPEED - an exact match could get
    ; stepped over entirely, leaving this searching forever and the
    ; leader (and its trailing units) drifting off Y=0 unbounded.
    LD A,(E2A_U0_Y) : SUB TOP_Y      ; A = distance still above TOP_Y
    CP EXIT_SPEED
    JR NC,ECS_S7_UPSTEP_A
    LD A,TOP_Y : LD (E2A_U0_Y),A
    LD A,1 : LD (E2A_EXIT_PHASE),A
    CALL ECS_S7_A_ANIM_RESET
    JR ECS_S7_RECORD_A
ECS_S7_UPSTEP_A:
    LD A,(E2A_U0_Y) : SUB EXIT_SPEED : LD (E2A_U0_Y),A
    JR ECS_S7_RECORD_A
ECS_S7_DOWN_A:
    LD A,ENEMY_Y1 : LD B,A
    LD A,(E2A_U0_Y) : LD C,A
    LD A,B : SUB C                   ; A = distance still below ENEMY_Y1
    CP EXIT_SPEED
    JR NC,ECS_S7_DOWNSTEP_A
    LD A,ENEMY_Y1 : LD (E2A_U0_Y),A
    LD A,1 : LD (E2A_EXIT_PHASE),A
    CALL ECS_S7_A_ANIM_RESET
    JR ECS_S7_RECORD_A
ECS_S7_DOWNSTEP_A:
    LD A,(E2A_U0_Y) : ADD A,EXIT_SPEED : LD (E2A_U0_Y),A
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
    LD A,(HL) : ADD A,8 : LD (E2A_U1_Y),A    ; 退出中も1機目(軌跡の元)から+8/+16のズレを保つ

    LD A,(E2A_TRAIL_WIDX)
    SUB TRAIL_DELAY*2
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2A_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2A_U2_X),A
    INC HL
    LD A,(HL) : ADD A,16 : LD (E2A_U2_Y),A

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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2A_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    ; (2026-09-23、"合体後も1セルズレたまま移動させたい"): 合体後(ドリフト)も
    ; 1機目-8/3機目+8のまま(横並び回避)。
    LD A,(E2B_Y) : LD (E2B_U1_Y),A : SUB 8 : LD (E2B_U0_Y),A : ADD A,16 : LD (E2B_U2_Y),A
    DI
    LD A,(E2B_U0_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U1_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_EDS_Y0) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_EDS_Y1) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_EDS_Y2) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U0_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B0 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,2 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_U1_X),A
    EI
    RET
ECS_S1_DRAW_B:
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U0_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B1 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,4 : LD (E2B_SEQ_STATE),A
    LD A,ENEMY_SPAWNX : LD (E2B_U2_X),A
    EI
    RET
ECS_S3_DRAW_B:
    DI
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TT : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B2 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(E2B_U2_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_E2B_TB : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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

; Resets E2B_ANIM_SEQ to 0 (base frame) if it wasn't already, and
; redraws all 3 units to match - called once the dive/climb ends.
; Trashes A,B,D,E,H,L,IX.
ECS_S7_B_ANIM_RESET:
    LD A,(E2B_ANIM_SEQ)
    OR A
    RET Z
    XOR A : LD (E2B_ANIM_SEQ),A
    JP E2B_ANIM_REDRAW_ALL

; Rebuilds all 3 of instance B's unit sprite patterns from the
; current E2B_ANIM_SEQ frame. Trashes A,B,D,E,H,L,IX.
E2B_ANIM_REDRAW_ALL:
    LD HL,E2B_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
    LD HL,SPRPAT+416 : LD DE,E2B_U0_TOP : LD IX,E2B_U0_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+448 : LD DE,E2B_U1_TOP : LD IX,E2B_U1_BOT
    CALL REDRAW_UNIT_PATTERN
    LD HL,SPRPAT+480 : LD DE,E2B_U2_TOP : LD IX,E2B_U2_BOT
    CALL REDRAW_UNIT_PATTERN
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
    JP NZ,ECS_S7_HORIZ_B

    ; see ECS_S7_A's own comment - same idea, instance B.
    LD A,(E2B_FIRE_FLAG)
    CP 1
    JR NZ,ECS_S7_B_FIRE_DONE
    LD A,2 : LD (E2B_FIRE_FLAG),A
    LD HL,E2B_U0_STATE : CALL E2_FIRE_FROM_ALIVE
ECS_S7_B_FIRE_DONE:

    ; quadrant-glyph animation - see ECS_S7_A's own comment.
    LD A,(E2B_ANIM_TIMER)
    OR A
    JR NZ,ECS_S7_B_ANIM_TICK
    LD A,ENEMY2_ANIM_FRAME_LEN : LD (E2B_ANIM_TIMER),A
    LD A,(E2B_ANIM_SEQ) : INC A : AND 3 : LD (E2B_ANIM_SEQ),A
    CALL E2B_ANIM_REDRAW_ALL
    JR ECS_S7_B_ANIM_DONE
ECS_S7_B_ANIM_TICK:
    DEC A : LD (E2B_ANIM_TIMER),A
ECS_S7_B_ANIM_DONE:

    LD A,(E2B_U0_X) : ADD A,EXIT_SPEED : LD (E2B_U0_X),A
    LD A,(E2B_EXITTYPE)
    OR A
    JR Z,ECS_S7_DOWN_B
    ; See ECS_S7_A's comment - same clamp-on-arrival fix, instance B.
    LD A,(E2B_U0_Y) : SUB TOP_Y      ; A = distance still above TOP_Y
    CP EXIT_SPEED
    JR NC,ECS_S7_UPSTEP_B
    LD A,TOP_Y : LD (E2B_U0_Y),A
    LD A,1 : LD (E2B_EXIT_PHASE),A
    CALL ECS_S7_B_ANIM_RESET
    JR ECS_S7_RECORD_B
ECS_S7_UPSTEP_B:
    LD A,(E2B_U0_Y) : SUB EXIT_SPEED : LD (E2B_U0_Y),A
    JR ECS_S7_RECORD_B
ECS_S7_DOWN_B:
    LD A,ENEMY_Y1 : LD B,A
    LD A,(E2B_U0_Y) : LD C,A
    LD A,B : SUB C                   ; A = distance still below ENEMY_Y1
    CP EXIT_SPEED
    JR NC,ECS_S7_DOWNSTEP_B
    LD A,ENEMY_Y1 : LD (E2B_U0_Y),A
    LD A,1 : LD (E2B_EXIT_PHASE),A
    CALL ECS_S7_B_ANIM_RESET
    JR ECS_S7_RECORD_B
ECS_S7_DOWNSTEP_B:
    LD A,(E2B_U0_Y) : ADD A,EXIT_SPEED : LD (E2B_U0_Y),A
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
    LD A,(HL) : ADD A,8 : LD (E2B_U1_Y),A    ; 退出中も1機目(軌跡の元)から+8/+16のズレを保つ

    LD A,(E2B_TRAIL_WIDX)
    SUB TRAIL_DELAY*2
    AND TRAIL_BUFLEN-1
    LD H,0 : LD L,A : ADD HL,HL
    LD DE,E2B_TRAIL_HIST
    ADD HL,DE
    LD A,(HL) : LD (E2B_U2_X),A
    INC HL
    LD A,(HL) : ADD A,16 : LD (E2B_U2_Y),A

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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U1_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_U2_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(E2B_TEMP_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD DE,SPAWN_BASEY_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (E4_SPAWN_BASEY),A
    LD A,TYPE_ENEMY1_LOOK : LD (E4_SPAWN_TYPE),A
    JP ENEMY4_CLAIM_ANY

; Claims a free slot from the unified ENEMY_POOL for a fresh spawn:
; right-edge X, TYPE (and its HP) from E4_SPAWN_TYPE. TYPE_ENEMY4
; moves with BEHAVIOR_SIMPLE_DRIFT_DODGE (Enemy1's straight-drift +
; one-shot diagonal dodge) while keeping its own static look/HP - see
; EBSD_UPDATE/EBSD_DRAW/EBSD_HIT_TEST/EBSD_EXIT_LEFT's own TYPE_
; ENEMY4 branches; its Y is set directly (E_Y) rather than via the
; BASEY+sine-LUT scheme, and it never claims one of the 6 physical
; asterisk pattern slots (nothing here does for it, and nothing
; frees one for it either).
;
; Every other TYPE (currently just TYPE_ENEMY1_LOOK, "Enemy5") keeps
; the original BEHAVIOR_SINE_BOB spawn, BASEY going to E_PARAM0 as
; before - but now ALSO claims one of the same 6 physical pattern
; slots Enemy1 (SPAWN_SIMPLE/ENEMY1_CLAIM_ANY) uses, with both quadrant
; flags (E_TOP/E_BOT) starting alive and an initial SIMPLE_REDRAW, so
; it gets Enemy1's own independent top/bottom hit judgment (see
; EBSB_HIT_TEST) instead of the old single whole-sprite hitbox - a
; bullet through just the top (or bottom) asterisk now kills only
; that one, same as Enemy1/Enemy2's formations. This means Enemy5
; now competes with Enemy1 for the same 6-slot pool; if it's already
; exhausted, the spawn is dropped (rolling back the ENEMY_POOL claim)
; same as any other pool-exhaustion drop in this game.
ENEMY4_CLAIM_ANY:
    CALL ALLOC_ENEMY_SLOT
    OR A
    RET Z
    LD A,(E4_SPAWN_TYPE) : LD (IX+E_TYPE),A
    CP TYPE_ENEMY4
    JR NZ,E4CA_SINEBOB
    LD A,BEHAVIOR_SIMPLE_DRIFT_DODGE : LD (IX+E_BEHAVIOR),A
    XOR A : LD (IX+E_PARAM0),A            ; DIAG_DONE=0, dodge not yet triggered
    LD A,(E4_SPAWN_BASEY) : LD (IX+E_Y),A
    JR E4CA_COMMON
E4CA_SINEBOB:
    CALL ALLOC_PATTERN_SLOT
    CP 0FFh
    JR NZ,E4CA_SB_GOTPAT
    CALL FREE_ENEMY_SLOT
    XOR A
    RET
E4CA_SB_GOTPAT:
    LD (IX+E_PARAM3),A
    LD A,1 : LD (IX+E_TOP),A : LD (IX+E_BOT),A
    LD A,BEHAVIOR_SINE_BOB : LD (IX+E_BEHAVIOR),A
    LD A,(E4_SPAWN_BASEY) : LD (IX+E_PARAM0),A
    ; "E5はランダムに3から5機に一度発射" - decided once per spawn, here.
    ; See EBSB_UPDATE's own comment for E_PARAM1/2's use.
    PUSH HL
    LD HL,E5_FIRE_COUNTDOWN
    CALL DECIDE_FIRE_SHOOTER
    LD (IX+E_PARAM1),A
    POP HL
E4CA_COMMON:
    LD A,ENEMY_SPAWNX : LD (IX+E_X),A
    CALL ALLOC_SPRITE_NUM : LD (IX+E_SPRNUM),A
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    LD DE,ETT_HP : ADD HL,DE
    LD A,(HL) : LD (IX+E_HP),A
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY1_LOOK
    RET NZ
    PUSH IX : POP HL
    LD A,(IX+E_PARAM3)
    JP SIMPLE_REDRAW

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

; Enemy5 (TYPE_ENEMY1_LOOK) shares one static VRAM pattern block
; (PAT_ENEMY1_LOOK) across every simultaneously-active instance - see
; its own comment - so it can't have a per-instance 1,2,3,2 quadrant
; anim the way Enemy1/2 do; instead every live Enemy5 shows the same
; frame in lockstep, driven by this one global timer/index (unlike
; Enemy1/2, this isn't gated on "currently moving vertically" -
; BEHAVIOR_SINE_BOB is always bobbing whenever alive, so it just
; free-runs continuously; a few redraws while no Enemy5 is on screen
; are harmless). Called once/frame from MAINLOOP, not from EBSB_
; UPDATE (which also drives ordinary Enemy4 - touching that would
; wrongly animate Enemy4 too). Trashes A,B,D,E,H,L,IX.
ENEMY5_ANIM_STEP:
    LD A,(ENEMY5_ANIM_TIMER)
    OR A
    JR NZ,E5AS_TICK
    LD A,ENEMY2_ANIM_FRAME_LEN : LD (ENEMY5_ANIM_TIMER),A
    LD A,(ENEMY5_ANIM_SEQ) : INC A : AND 3 : LD (ENEMY5_ANIM_SEQ),A
    LD HL,ENEMY5_ANIM_SEQ : CALL SET_REDRAW_SRC_FROM_SEQ
    LD HL,PAT_ENEMY1_LOOK*8+SPRPAT : LD DE,ENEMY1_LOOK_FLAGS : LD IX,ENEMY1_LOOK_FLAGS+1
    CALL REDRAW_UNIT_PATTERN
    RET
E5AS_TICK:
    DEC A : LD (ENEMY5_ANIM_TIMER),A
    RET

; Purely decorative flowing background clouds - two independent
; whole-character-cell movers on the sky rows just below the score
; line (see CLOUDW_ROW/CLOUDN_ROW), unrelated to the 4-row ground
; scroller. Both use the same 2-tile (WA/WB) glyph pair; row2 repeats
; it twice back to back (4 cells), row3 shows it once (2 cells), at
; their own move interval. Each cloud is either idle (counting down a
; random wait before its next spawn) or active and sliding left,
; using ordinary WRITE_ANIM_CELL erase/redraw rather than the ground
; scroller's per-pixel rotated-pattern trick, since movement here is
; a full cell every CLOUDW_INTERVAL/CLOUDN_INTERVAL frames, never a
; sub-cell offset. COL is a signed (two's complement) column: DEC/INC
; across the 0/255 wrap naturally tracks positions just off either
; edge, the same trick used by ENEMY4_SINE_LUT's relative Y offsets.
; Suspended entirely while the boss is up (BOSS_STATE!=0) - BOSS_MAP
; is drawn at screen row1 col26 onward across 16 rows, overlapping
; both cloud rows, so continuing to erase/redraw clouds through that
; area would corrupt the boss art. Called once/frame from MAINLOOP.
CLOUD_UPDATE_ALL:
    LD A,(BOSS_STATE)
    OR A
    RET NZ
    CALL CLOUDW_UPDATE
    JP CLOUDN_UPDATE

; Wide cloud, screen row CLOUDW_ROW: 2x(WA,WB) = 4 cells.
CLOUDW_UPDATE:
    LD A,(CLOUDW_ACTIVE)
    OR A
    JR NZ,CLOUDW_MOVE
    LD A,(CLOUDW_WAIT)
    OR A
    JR Z,CLOUDW_SPAWN
    DEC A : LD (CLOUDW_WAIT),A
    RET
CLOUDW_SPAWN:
    LD A,1 : LD (CLOUDW_ACTIVE),A
    LD A,CLOUD_SPAWN_COL : LD (CLOUDW_COL),A
    LD A,CLOUDW_INTERVAL : LD (CLOUDW_TIMER),A
    RET
CLOUDW_MOVE:
    LD A,(CLOUDW_TIMER)
    DEC A
    LD (CLOUDW_TIMER),A
    RET NZ
    LD A,CLOUDW_INTERVAL : LD (CLOUDW_TIMER),A
    ; erase all 4 cells at the current (about-to-move-away-from) position
    LD A,(CLOUDW_COL) : LD B,A
    CALL CLOUDW_ERASE_CELL
    LD A,(CLOUDW_COL) : INC A : LD B,A
    CALL CLOUDW_ERASE_CELL
    LD A,(CLOUDW_COL) : ADD A,2 : LD B,A
    CALL CLOUDW_ERASE_CELL
    LD A,(CLOUDW_COL) : ADD A,3 : LD B,A
    CALL CLOUDW_ERASE_CELL
    ; advance one cell left
    LD A,(CLOUDW_COL) : DEC A : LD (CLOUDW_COL),A
    CP 0FCh                      ; -4: all 4 cells now fully off the left edge
    JR NZ,CLOUDW_DRAW
    XOR A : LD (CLOUDW_ACTIVE),A
    CALL CLOUD_RANDOM_WAIT
    LD (CLOUDW_WAIT),A
    RET
CLOUDW_DRAW:
    LD A,(CLOUDW_COL) : LD B,A : LD C,CLOUD_WA_CODE
    CALL CLOUDW_DRAW_CELL
    LD A,(CLOUDW_COL) : INC A : LD B,A : LD C,CLOUD_WB_CODE
    CALL CLOUDW_DRAW_CELL
    LD A,(CLOUDW_COL) : ADD A,2 : LD B,A : LD C,CLOUD_WA_CODE
    CALL CLOUDW_DRAW_CELL
    LD A,(CLOUDW_COL) : ADD A,3 : LD B,A : LD C,CLOUD_WB_CODE
    CALL CLOUDW_DRAW_CELL
    RET

; Input: B = column (signed). No-ops if off-screen (col<0 or col>31 -
; both read as >=32 unsigned, covering the two's-complement negatives
; too). Trashes A,DE,HL.
CLOUDW_ERASE_CELL:
    LD A,B
    CP 32
    RET NC
    LD (ANIM_TMP_COL),A
    LD A,CLOUDW_ROW : LD (ANIM_TMP_ROW),A
    LD A,BLANKCODE : LD (ANIM_TMP_VAL),A
    JP WRITE_ANIM_CELL

; Input: B = column (signed), C = character code to draw.
CLOUDW_DRAW_CELL:
    LD A,B
    CP 32
    RET NC
    LD (ANIM_TMP_COL),A
    LD A,CLOUDW_ROW : LD (ANIM_TMP_ROW),A
    LD A,C : LD (ANIM_TMP_VAL),A
    JP WRITE_ANIM_CELL

; Narrow cloud, screen row CLOUDN_ROW: 1x(WA,WB) = 2 cells - same
; shape as CLOUDW_UPDATE, just half as wide and its own interval.
CLOUDN_UPDATE:
    LD A,(CLOUDN_ACTIVE)
    OR A
    JR NZ,CLOUDN_MOVE
    LD A,(CLOUDN_WAIT)
    OR A
    JR Z,CLOUDN_SPAWN
    DEC A : LD (CLOUDN_WAIT),A
    RET
CLOUDN_SPAWN:
    LD A,1 : LD (CLOUDN_ACTIVE),A
    LD A,CLOUD_SPAWN_COL : LD (CLOUDN_COL),A
    LD A,CLOUDN_INTERVAL : LD (CLOUDN_TIMER),A
    RET
CLOUDN_MOVE:
    LD A,(CLOUDN_TIMER)
    DEC A
    LD (CLOUDN_TIMER),A
    RET NZ
    LD A,CLOUDN_INTERVAL : LD (CLOUDN_TIMER),A
    LD A,(CLOUDN_COL) : LD B,A
    CALL CLOUDN_ERASE_CELL
    LD A,(CLOUDN_COL) : INC A : LD B,A
    CALL CLOUDN_ERASE_CELL
    LD A,(CLOUDN_COL) : DEC A : LD (CLOUDN_COL),A
    CP 0FEh                      ; -2: both cells now fully off the left edge
    JR NZ,CLOUDN_DRAW
    XOR A : LD (CLOUDN_ACTIVE),A
    CALL CLOUD_RANDOM_WAIT
    LD (CLOUDN_WAIT),A
    RET
CLOUDN_DRAW:
    LD A,(CLOUDN_COL) : LD B,A : LD C,CLOUD_WA_CODE
    CALL CLOUDN_DRAW_CELL
    LD A,(CLOUDN_COL) : INC A : LD B,A : LD C,CLOUD_WB_CODE
    CALL CLOUDN_DRAW_CELL
    RET

CLOUDN_ERASE_CELL:
    LD A,B
    CP 32
    RET NC
    LD (ANIM_TMP_COL),A
    LD A,CLOUDN_ROW : LD (ANIM_TMP_ROW),A
    LD A,BLANKCODE : LD (ANIM_TMP_VAL),A
    JP WRITE_ANIM_CELL

CLOUDN_DRAW_CELL:
    LD A,B
    CP 32
    RET NC
    LD (ANIM_TMP_COL),A
    LD A,CLOUDN_ROW : LD (ANIM_TMP_ROW),A
    LD A,C : LD (ANIM_TMP_VAL),A
    JP WRITE_ANIM_CELL

; Input: none. Output: A = a pseudo-random frame count (30-157) used
; as the idle wait before a cloud's next spawn - "for now" just a
; plain range off the shared free-running counter (see DFL_RNG),
; same source/pattern the boss-shield deflect directions already use.
; Trashes A.
CLOUD_RANDOM_WAIT:
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 7Fh
    ADD A,30
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP

    ; "サインの頂点と下限ではLut参照を停止して横に16px動き上下の動きは
    ; 無くすということ つまりサイン移動で頂点まで行き16pxドリフト
    ; その後サイン移動で下限まで行き16pxドリフト この繰り返し" -
    ; E_PARAM5 (genuinely unused by this BEHAVIOR - E_PARAM4 is NOT
    ; free, it's shared with SIMPLE_REDRAW's glyph-sequence index for
    ; this slot's quadrant-kill visuals, and must stay in [0,3] at all
    ; times or a quadrant kill corrupts the drawn pattern) is a
    ; "frozen-drift frames remaining" countdown, armed to 16 the instant
    ; E_STATE reaches the peak(7)/trough(23) plateau in ENEMY4_SINE_LUT.
    ; While nonzero, E_STATE is NOT advanced at all (so the LUT lookup -
    ; and therefore Y - stays pinned exactly where it was: "Lut参照を
    ; 停止") and X alone steps 1px/frame instead of the normal
    ; ENEMY4_SPEED - exactly 16 frozen frames = 16px purely horizontal,
    ; then normal sine-follow motion resumes from that same state,
    ; continuing the curve away from the extreme it just paused at.
    LD A,(IX+E_PARAM5)
    OR A
    JR NZ,EBSB_CHECK_FROZEN_EXIT
    LD A,(IX+E_X)
    CP ENEMY4_SPEED
    EI
    JR NC,EBSB_MOVEOK
    JP EBSB_EXIT_LEFT
EBSB_CHECK_FROZEN_EXIT:
    LD A,(IX+E_X)
    OR A
    EI
    JR NZ,EBSB_MOVEOK_FROZEN
    JP EBSB_EXIT_LEFT
EBSB_MOVEOK:
    SUB ENEMY4_SPEED
    LD (IX+E_X),A

    LD A,(IX+E_STATE) : INC A : CP ENEMY4_LUT_LEN : JR C,EBSB_PHASEOK
    XOR A
EBSB_PHASEOK:
    LD (IX+E_STATE),A
    CP 7
    JR Z,EBSB_ARM_FREEZE
    CP 23
    JR NZ,EBSB_DRAW_FROM_LUT
EBSB_ARM_FREEZE:
    LD A,16 : LD (IX+E_PARAM5),A
    JR EBSB_DRAW_FROM_LUT
EBSB_MOVEOK_FROZEN:
    ; A already holds E_X (loaded above, untouched by the OR A/JR) -
    ; the X!=0 check just above already guards against underflow here.
    DEC A : LD (IX+E_X),A
    LD A,(IX+E_PARAM5) : DEC A : LD (IX+E_PARAM5),A
EBSB_DRAW_FROM_LUT:
    LD A,(IX+E_STATE)
    LD E,A : LD D,0
    LD HL,ENEMY4_SINE_LUT
    ADD HL,DE
    DI
    LD A,(IX+E_PARAM0) : ADD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(IX+E_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    ; Draws from this instance's own pattern slot (E_PARAM3), not a
    ; TYPE lookup - same reasoning as EBSD_DRAW's SIMPLE_PATTERN_NUM
    ; use: each instance's pattern is independently mutable (top/bottom
    ; quadrants killed one at a time - see EBSB_HIT_TEST/SIMPLE_REDRAW).
    ; This BEHAVIOR is currently only ever TYPE_ENEMY1_LOOK (TYPE_ENEMY4
    ; is BEHAVIOR_SIMPLE_DRIFT_DODGE - see ENEMY4_CLAIM_ANY), so there's
    ; no other TYPE to branch on here; color is just the fixed SPR_GRAY
    ; every asterisk quadrant already uses.
    LD A,(IX+E_PARAM3) : CALL SIMPLE_PATTERN_NUM
    DI
    OUT (98h),A                      ; pattern
    PUSH BC : POP BC : NOP : NOP
    LD A,SPR_GRAY : OUT (98h),A      ; color
    PUSH BC : POP BC : NOP : NOP
    EI
    ; "E1,E2,E5はランダムに3から5機に一度発射 ただし斜め移動中のみ" -
    ; this BEHAVIOR (continuous left-drift + sine-wave bob) has no
    ; discrete diagonal phase, unlike Enemy1's one-shot dodge or
    ; Enemy2's exit dive - it's always moving on both axes at once. As
    ; a stand-in "diagonal" trigger point, this uses the SAME screen-
    ; center X threshold Enemy1's own dodge uses (ENEMY_CENTER_X), for
    ; consistency across all 3 gated types. E_PARAM1 (shooter flag, set
    ; once at spawn - see E4CA_SINEBOB)/E_PARAM2 (already fired, 0/1)
    ; are both otherwise unused by this BEHAVIOR. Y is recomputed here
    ; (baseY+LUT[state]) rather than read from E_Y, which this BEHAVIOR
    ; never writes back (see the DI/EI block above - it's written
    ; straight to the VDP, not stored).
    LD A,(IX+E_PARAM1)
    OR A
    JR Z,EBSB_FIRE_DONE
    LD A,(IX+E_PARAM2)
    OR A
    JR NZ,EBSB_FIRE_DONE
    LD A,(IX+E_X)
    CP ENEMY_CENTER_X
    JR NC,EBSB_FIRE_DONE
    LD A,1 : LD (IX+E_PARAM2),A
    LD A,(IX+E_STATE) : LD L,A : LD H,0
    LD DE,ENEMY4_SINE_LUT
    ADD HL,DE
    LD A,(IX+E_PARAM0) : ADD A,(HL)
    LD E,A
    LD A,(IX+E_X) : LD D,A
    CALL FIRE_FROM_QUAD
EBSB_FIRE_DONE:
    RET

; Drifted off the left edge: hide the sprite, restore its type's
; pattern/color (matches the legacy Enemy4 exit write - vestigial now
; that Enemy5 flies with its own pattern slot, but harmless: the
; sprite is already hidden off-screen by the time this runs), frees
; this instance's pattern slot (see ENEMY4_CLAIM_ANY), then the slot.
; No score, no explosion - this is an exit, not a kill.
EBSB_EXIT_LEFT:
    DI
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,(IX+E_PARAM3) : CALL FREE_PATTERN_SLOT
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
    ; "エネミー7はY軸が自機に合ったら発射" - TYPE_ENEMY4-only Y-aligned
    ; fire, independent of the diagonal-dodge random fire below (still
    ; can co-occur in the same frame - E4_FIRED_THIS_FRAME below is
    ; what prevents that from becoming a double-spawn - see its own
    ; comment). E_PARAM3 is otherwise unused by TYPE_ENEMY4 (see
    ; EBSD_EXIT_LEFT's own "TYPE_ENEMY4 never claimed a pattern slot"
    ; comment) - repurposed here as a per-instance re-fire cooldown.
    ; Only TYPE_ENEMY4 currently runs this BEHAVIOR at all, but the
    ; type check is kept explicit anyway, matching this same routine's
    ; own existing EBSD_EXIT_LEFT/EBSD_DRAW precedent.
    XOR A : LD (E4_FIRED_THIS_FRAME),A
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR NZ,EBSD_E4_FIRE_DONE
    ; (2026-09-24、"倒した後に撃ってる場合がある"): 1発目を受けて墜落中(E_FLAGS!=0)は
    ; もう撃たない(以前は自機と同じ高さになると墜落中でも撃っていた)。
    LD A,(IX+E_FLAGS)
    OR A
    JR NZ,EBSD_E4_FIRE_DONE
    LD A,(IX+E_PARAM3)
    OR A
    JR Z,EBSD_E4_TRY_ALIGN
    DEC A : LD (IX+E_PARAM3),A
    JR EBSD_E4_FIRE_DONE
EBSD_E4_TRY_ALIGN:
    LD A,(PLAYERY) : LD B,A
    LD A,(IX+E_Y)
    CP B
    JR NZ,EBSD_E4_FIRE_DONE
    LD A,E4_ALIGN_FIRE_COOLDOWN : LD (IX+E_PARAM3),A
    LD D,(IX+E_X) : LD E,(IX+E_Y)
    CALL SPAWN_EBULLET
    LD A,1 : LD (E4_FIRED_THIS_FRAME),A
EBSD_E4_FIRE_DONE:
    LD A,(IX+E_PARAM0)          ; DIAG_DONE
    OR A
    JR NZ,EBSD_DIAG_SKIP_TRIGGER
    LD A,(IX+E_X)
    CP ENEMY_CENTER_X
    JR NC,EBSD_DIAG_SKIP_TRIGGER
    LD A,1 : LD (IX+E_PARAM0),A
    ; "Eは一度上下移動に入ったらそのまま通常のドリフトには戻さず移動
    ; して消えるように" - TYPE_ENEMY4 no longer uses PARAM1 as a
    ; remaining-distance countdown (the dive never expires now - see
    ; EBSD_DIAG_E4 below); it's repurposed as this type's own pose-
    ; toggle animation timer instead, starting at 0 (toggle pose on
    ; the very first diving frame). Any other type sharing this
    ; trigger-arm block keeps the original ENEMY_DODGE_DIST countdown
    ; (only TYPE_ENEMY4 uses this BEHAVIOR today - see ENEMY4_CLAIM_
    ; ANY - but the branch is kept explicit for the same reason
    ; EBSD_EXIT_LEFT/EBSD_DRAW already do).
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR Z,EBSD_ARM_E4_PARAM1
    LD A,ENEMY_DODGE_DIST : LD (IX+E_PARAM1),A   ; DIAG_REMAIN
    JR EBSD_ARM_PARAM1_DONE
EBSD_ARM_E4_PARAM1:
    XOR A : LD (IX+E_PARAM1),A
EBSD_ARM_PARAM1_DONE:
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
    ; "E1,E2,E5はランダムに3から5機に一度発射 ただし斜め移動中のみ" -
    ; this IS the "斜め移動中" trigger point for BEHAVIOR_SIMPLE_
    ; DRIFT_DODGE (the one-shot diagonal dodge just armed above). Fires
    ; immediately, synchronously, right here - no separate per-instance
    ; "designated shooter" flag needed, since DECIDE_FIRE_SHOOTER is
    ; called fresh at the exact moment each instance's own one dodge
    ; begins. DECIDE_FIRE_SHOOTER's own countdown is always consumed
    ; here regardless (so the "3-5機に1回" cadence isn't disturbed) -
    ; only the actual SPAWN_EBULLET call below is guarded by
    ; E4_FIRED_THIS_FRAME, to avoid a same-frame double-spawn with the
    ; Y-aligned fire above (see that flag's own comment - this used to
    ; let a single EBULLET-firing trigger spawn 2 bullets stacked at
    ; the exact same (X,Y), reported as "1回の被弾で複数回ダメージ").
    PUSH HL
    LD HL,E1_FIRE_COUNTDOWN
    CALL DECIDE_FIRE_SHOOTER
    OR A
    JR Z,EBSD_E1_NOFIRE
    LD A,(E4_FIRED_THIS_FRAME)
    OR A
    JR NZ,EBSD_E1_NOFIRE
    LD D,(IX+E_X) : LD E,(IX+E_Y)
    CALL FIRE_FROM_QUAD
EBSD_E1_NOFIRE:
    POP HL
    XOR A : LD (IX+E_PARAM4),A : LD (IX+E_PARAM5),A  ; reset quadrant-anim seq/timer for this dodge
EBSD_DIAG_SKIP_TRIGGER:
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR Z,EBSD_DIAG_E4

    LD A,(IX+E_PARAM1)
    OR A
    JP Z,EBSD_DRAW
    DEC A : LD (IX+E_PARAM1),A
    LD A,(IX+E_PARAM2) : LD B,A
    LD A,(IX+E_Y)
    ADD A,B
    LD (IX+E_Y),A

    ; quadrant-glyph animation (1,2,3,2 repeating - see ASTERISK_
    ; PATTERN/2/3, ENEMY_ANIM_SEQ_TABLE), advances once every
    ; ENEMY1_ANIM_FRAME_LEN frames while actively dodging, snaps
    ; back to the base frame (seq0/ASTERISK_PATTERN) the instant the
    ; dodge ends. TYPE_ENEMY4 no longer reaches this path at all - it
    ; has its own permanent-dive/animation handling, EBSD_DIAG_E4.
    LD A,(IX+E_PARAM1)
    JR NZ,EBSD_ANIM_STEP
    LD A,(IX+E_PARAM4)
    OR A
    JP Z,EBSD_DRAW
    XOR A : LD (IX+E_PARAM4),A
    JR EBSD_ANIM_REDRAW
EBSD_ANIM_STEP:
    LD A,(IX+E_PARAM5)
    OR A
    JR NZ,EBSD_ANIM_TICK
    LD A,(IX+E_PARAM4) : INC A : AND 3 : LD (IX+E_PARAM4),A
    JR EBSD_ANIM_REDRAW
EBSD_ANIM_TICK:
    DEC A : LD (IX+E_PARAM5),A
    JP EBSD_DRAW
EBSD_ANIM_REDRAW:
    LD A,ENEMY1_ANIM_FRAME_LEN : LD (IX+E_PARAM5),A
    PUSH IX
    PUSH IX : POP HL
    LD A,(IX+E_PARAM3)
    CALL SIMPLE_REDRAW
    POP IX
    JP EBSD_DRAW

; "Eは一度上下移動に入ったらそのまま通常のドリフトには戻さず移動して
; 消えるように" - once triggered (E_PARAM0=1), TYPE_ENEMY4's dive
; never expires: it just keeps drifting diagonally (X via the
; unconditional ENEMY_SPEED drift already applied above, Y here) for
; the rest of its life, until it exits off *some* edge via the
; existing EBSD_EXIT_LEFT check (X reaching the left edge) - the
; horizontal drift never stops regardless of this vertical motion, so
; no separate off-screen check is needed for "moves until it
; disappears".
EBSD_DIAG_E4:
    ; not diving yet (dodge never triggered this instance) - stay on
    ; the static pose (E_PARAM4 untouched, still 0 from ALLOC_ENEMY_
    ; SLOT's own zero-fill) and don't move Y at all.
    LD A,(IX+E_PARAM0)
    OR A
    JP Z,EBSD_DRAW
    LD A,(IX+E_PARAM2) : LD B,A
    LD A,(IX+E_Y)
    ADD A,B
    LD (IX+E_Y),A

    ; round141: 被弾クラッシュ中(E_FLAGS!=0、EBSD_HT_ENEMY4参照)のみ、
    ; 自機爆発と同じPLAYER_EXPL_POOLバーストをこのインスタンス自身の
    ; (E_X,E_Y)起点でENEMY4_CRASH_SPAWN_INTERVALごとに1個ポップ(音無し)。
    ; 自然な回避ダイブ(被弾せずセンターXを越えただけ)ではE_FLAGSは0の
    ; ままなのでこのブロックは完全に素通りする。
    LD A,(IX+E_FLAGS)
    OR A
    JR Z,EBSD_E4_CRASH_FX_DONE
    LD A,(IX+E_TRAIL_DELAY)
    OR A
    JR NZ,EBSD_E4_CRASH_FX_TICK
    LD A,ENEMY4_CRASH_SPAWN_INTERVAL : LD (IX+E_TRAIL_DELAY),A
    PUSH IX
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 0Fh : SUB 8 : LD B,A          ; -8..+7 pseudo-random X jitter
    LD A,(IX+E_X) : ADD A,B
    LD (EBUZ_EXPL_POS_X),A
    LD A,(DFL_RNG) : INC A : LD (DFL_RNG),A
    AND 0Fh : SUB 8 : LD B,A          ; -8..+7 pseudo-random Y jitter
    LD A,(IX+E_Y) : ADD A,B
    LD (EBUZ_EXPL_POS_Y),A
    CALL PEUA_TRY_SPAWN_AT          ; (2026-09-23 "やっぱ音つけて": 自機爆発の音も)
    POP IX
    JR EBSD_E4_CRASH_FX_DONE
EBSD_E4_CRASH_FX_TICK:
    DEC A : LD (IX+E_TRAIL_DELAY),A
EBSD_E4_CRASH_FX_DONE:

    ; "ファイターのアニメは上下移動に入ったら戻さない 今は繰り返しに
    ; なってるな" - ONE-TIME pose switch, not a repeating toggle:
    ; E4_ANIM_FRAME_LEN frames after the dive begins, flips from
    ; PAT_ENEMY4 to PAT_ENEMY4_2 (E_PARAM4 0->1, read by EBSD_DRAW_E4)
    ; and then stays there permanently for the rest of this dive.
    ; E_PARAM1 is the one-shot countdown to that switch (repurposed
    ; away from the old "remaining px" countdown - see EBSD_ARM_E4_
    ; PARAM1); once E_PARAM4=1 this whole block is skipped every frame.
    LD A,(IX+E_PARAM4)
    OR A
    JR NZ,EBSD_DRAW
    LD A,(IX+E_PARAM1)
    OR A
    JR NZ,EBSD_E4_ANIM_TICK
    LD A,E4_ANIM_FRAME_LEN : LD (IX+E_PARAM1),A
    JR EBSD_DRAW
EBSD_E4_ANIM_TICK:
    DEC A
    JR NZ,EBSD_E4_ANIM_STORE
    LD A,1 : LD (IX+E_PARAM4),A
    JR EBSD_DRAW
EBSD_E4_ANIM_STORE:
    LD (IX+E_PARAM1),A
EBSD_DRAW:
    DI
    LD A,(IX+E_SPRNUM) : ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(IX+E_Y) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(IX+E_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    ; Pattern#/color are precomputed here, outside the DI-timed VDP
    ; write block below, since a TYPE_ENEMY4 branch inside it would
    ; disturb the fixed NOP spacing - see EBSD_DRAW_PAT/EBSD_DRAW_COLOR.
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR Z,EBSD_DRAW_E4
    LD A,(IX+E_PARAM3) : CALL SIMPLE_PATTERN_NUM
    LD (EBSD_DRAW_PAT),A
    LD A,SPR_GRAY
    LD (EBSD_DRAW_COLOR),A
    JR EBSD_DRAW_GO
EBSD_DRAW_E4:
    ; "E4にアニメ追加 上下移動中に適用" - E_PARAM4(0/1) selects the
    ; pose, toggled by EBSD_DIAG_E4 while diving; stays 0 (PAT_ENEMY4)
    ; the rest of the time (E_PARAM4 is only ever touched inside
    ; EBSD_DIAG_E4/the trigger-arm reset, both dive-only).
    LD A,(IX+E_PARAM4)
    OR A
    JR Z,EBSD_DRAW_E4_POSE0
    LD A,PAT_ENEMY4_2
    JR EBSD_DRAW_E4_GOT
EBSD_DRAW_E4_POSE0:
    LD A,PAT_ENEMY4
EBSD_DRAW_E4_GOT:
    LD (EBSD_DRAW_PAT),A
    ; "エネミー7の色を変更 現在ブラックだがライトグリーンに"
    LD A,SPR_LIGHTGREEN
    LD (EBSD_DRAW_COLOR),A
EBSD_DRAW_GO:
    DI
    LD A,(EBSD_DRAW_PAT) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(EBSD_DRAW_COLOR) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    POP AF : CALL FREE_SPRITE_NUM
    ; TYPE_ENEMY4 never claimed a pattern slot (see EBSD_DRAW/
    ; ENEMY4_CLAIM_ANY) - its E_PARAM3 is stale, so freeing it here
    ; would corrupt the 6-slot pattern allocator's bookkeeping.
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JR Z,EBSD_EXIT_LEFT_NOFREEPAT
    LD A,(IX+E_PARAM3) : CALL FREE_PATTERN_SLOT
EBSD_EXIT_LEFT_NOFREEPAT:
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

; Input: IX = slot base (already confirmed ACTIVE+BEHAVIOR_SINE_BOB,
; i.e. TYPE_ENEMY1_LOOK/"Enemy5" - the only TYPE this BEHAVIOR has
; right now, see ENEMY4_CLAIM_ANY), B = bullet col, C = bullet row.
; Output: A = 1 if the bullet destroyed a quadrant, else 0. Same
; independent TOP/BOT quadrant system as EBSD_HIT_TEST (see its own
; comment for the full rationale) - only the quadrants' current
; position differs, since this one bobs along the sine LUT each frame
; instead of sitting at a stored E_Y. Like EBSD_HIT_TEST, a
; fully-gutted (both quadrants dead) unit is NOT freed early - it
; keeps flying invisibly until EBSB_EXIT_LEFT.
EBSB_HIT_TEST:
    LD A,(IX+E_TOP) : OR A : JR Z,EBSB_HT_CHECKBOT
    LD A,(IX+E_STATE) : LD E,A : LD D,0
    LD HL,ENEMY4_SINE_LUT : ADD HL,DE
    LD A,(IX+E_PARAM0) : ADD A,(HL) : LD E,A
    LD A,(IX+E_X) : LD D,A
    CALL QUAD_HIT_TEST
    OR A
    JR NZ,EBSB_HT_KILL_TOP
EBSB_HT_CHECKBOT:
    LD A,(IX+E_BOT) : OR A : JR Z,EBSBH_NO
    LD A,(IX+E_STATE) : LD E,A : LD D,0
    LD HL,ENEMY4_SINE_LUT : ADD HL,DE
    LD A,(IX+E_PARAM0) : ADD A,(HL) : ADD A,8 : LD E,A
    LD A,(IX+E_X) : ADD A,8 : LD D,A
    CALL QUAD_HIT_TEST
    OR A
    JR Z,EBSBH_NO
    XOR A : LD (IX+E_BOT),A
    JR EBSB_HT_REDRAW
EBSB_HT_KILL_TOP:
    XOR A : LD (IX+E_TOP),A
EBSB_HT_REDRAW:
    ; --- stash the score selector (IX-relative) BEFORE calling        ---
    ; --- SIMPLE_REDRAW/TRIGGER_EXPLOSION, both of which trash IX -    ---
    ; --- nothing below this may rely on IX afterward.                 ---
    PUSH DE                      ; hit X,Y, needed later for TRIGGER_EXPLOSION
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    LD DE,ETT_SCORESEL : ADD HL,DE
    LD A,(HL)
    LD (ENEMY_SCORE_SEL_TMP),A
    PUSH IX : POP HL
    LD A,(IX+E_PARAM3)
    CALL SIMPLE_REDRAW
    POP DE
    PUSH BC
    CALL TRIGGER_EXPLOSION
    LD A,(ENEMY_SCORE_SEL_TMP)
    CALL ENEMY_AWARD_SCORE_SEL
    POP BC
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
    ; TYPE_ENEMY4 keeps its own single HP-based hitbox (matching
    ; EBSB_HIT_TEST) instead of the TOP/BOT quadrant system below -
    ; see EBSD_DRAW/ENEMY4_CLAIM_ANY.
    LD A,(IX+E_TYPE)
    CP TYPE_ENEMY4
    JP Z,EBSD_HT_ENEMY4
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

; TYPE_ENEMY4 on BEHAVIOR_SIMPLE_DRIFT_DODGE: single hitbox at the
; bottom half of the 16x16 sprite (mirroring EBSB_HIT_TEST's offset).
; round141("エネミー4...耐久値2だが1発当たったら左斜め下に墜落 自機の
; 墜落の逆向きだな 爆発エフェクトも自機と同じだがサウンドは無しで")、
; round141 follow-up("エネミー4は墜落で無敵にはならない 2発目が
; 当たったら爆発するように"): 旧来のE_HP 2段階ダメージを撤回した上で
; 2段階の被弾を再導入 - ただし段階の意味が異なる。1発目
; (E_FLAGS==0)は「クラッシュ開始」のみ(左斜め下への永久ダイブを
; 強制発動、まだ撃破せずスコアも入らない)。クラッシュ中も無敵には
; ならず、2発目(E_FLAGS!=0の状態への被弾)で実際に撃破 - スプライトを
; 隠しスロットを解放しスコアを加算、その瞬間に自機と同じPLAYER_EXPL_
; POOLバースト(無音)を1個追加でポップする。クラッシュ中の継続的な
; 煙エフェクト自体はEBSD_DIAG_E4のE_FLAGS!=0ゲートが既に処理しており、
; 1発目〜2発目の間もそのまま鳴らず光らず飛び続ける(無変更)。
EBSD_HT_ENEMY4:
    LD A,(IX+E_Y) : ADD A,8 : LD E,A   ; +8: art/hitbox is the bottom half only
    LD A,(IX+E_X) : LD D,A
    CALL QUAD_HIT_TEST
    OR A
    JR Z,EBSD_HT_NO
    LD A,(IX+E_FLAGS)
    OR A
    JR NZ,EBSD_HT_ENEMY4_KILL
    ; --- 1発目: クラッシュ開始のみ(まだ無敵にはしない、まだ撃破しない) ---
    LD A,1 : LD (IX+E_FLAGS),A         ; crashing=1(以後EBSD_DIAG_E4のFXトリガー)
    LD A,1 : LD (IX+E_PARAM0),A        ; DIAG_DONE=1(未発動でも強制発動)
    LD A,1 : LD (IX+E_PARAM2),A        ; DIAG_DIR=+1(必ず下方向)
    XOR A : LD (IX+E_TRAIL_DELAY),A    ; 最初の爆発パーティクルは即スポーン
    LD A,1
    RET
; --- 2発目(クラッシュ中への被弾): 実際に撃破 ---
; D,E はQUAD_HIT_TESTの入力のまま(E_X,E_Y+8) - PEUA_TRY_SPAWN_ATの
; 起点にそのまま流用する。
EBSD_HT_ENEMY4_KILL:
    LD A,D : LD (EBUZ_EXPL_POS_X),A
    LD A,E : LD (EBUZ_EXPL_POS_Y),A
    LD A,(IX+E_SPRNUM)
    DI
    ADD A,A : ADD A,A : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    PUSH IX
    CALL PEUA_TRY_SPAWN_AT          ; (2026-09-23 "やっぱ音つけて": 自機爆発の音も)
    POP IX
    LD A,(IX+E_TYPE) : CALL ENEMY_TYPE_LOOKUP
    LD DE,ETT_SCORESEL : ADD HL,DE
    LD A,(HL)
    CALL ENEMY_AWARD_SCORE_SEL
    CALL FREE_ENEMY_SLOT
    LD A,1
    RET

; 32-entry sine LUT of RELATIVE Y offsets (amplitude 16): each
; slot's actual Y = its BASEY (set at spawn from the wave) + this
; offset for the current phase. offset = round(16*sin(2*pi*i/32)),
; negative values stored as their 8-bit two's complement (ADD A,n
; wraps correctly either way).
ENEMY4_SINE_LUT:
    DB 0,3,6,9,11,13,15,16,16,16,15,13,11,9,6,3
    DB 0,253,250,247,245,243,241,240,240,240,241,243,245,247,250,253

; Advances all ENEMY3_WAVE_SLOTS wave slots by one frame - see
; ENEMY3_TRY_SPAWN_SLOT for the actual per-slot logic. Each slot is
; fully independent (own ACTIVE/BUDGET/TIMER/OFFSET) AND owns its own
; dedicated ENEMY3_SLOTS-instance slice of ENEMY3_POOL (passed in as
; HL), so several waves running at once never share or contend over
; anything - each can have up to ENEMY3_SLOTS of its own members alive
; at once regardless of what any other wave is doing.
; Per-wave slice offsets are ENEMY3_SLOTS*ENEMY3_STRUCT(=96, since the
; 2026-09-13 CENTERX fold-in grew ENEMY3_STRUCT 11->12) * wave index -
; literal here (this assembler evaluates left-to-right with no operator
; precedence, so a one-line expression would silently mis-parse; see
; the ENEMY3_STRUCT comment for why these needed updating from the old
; 11-byte-stride values of 88/176/264/352/440/528/616).
ENEMY3_TRY_SPAWN:
    LD IX,ENEMY3_WAVE_POOL    : LD HL,ENEMY3_POOL     : CALL ENEMY3_TRY_SPAWN_SLOT
    LD IX,ENEMY3_WAVE_POOL+4  : LD HL,ENEMY3_POOL+96  : CALL ENEMY3_TRY_SPAWN_SLOT
    LD IX,ENEMY3_WAVE_POOL+8  : LD HL,ENEMY3_POOL+192 : JP ENEMY3_TRY_SPAWN_SLOT   ; ENEMY3_WAVE_SLOTS=3

; Input: IX = one wave slot (ACTIVE,BUDGET,TIMER,OFFSET), HL = base of
; this wave's own dedicated ENEMY3_SLOTS-instance slice of ENEMY3_POOL.
; Counts down this slot's OWN timer; when it expires, claims a free
; unit slot from THIS WAVE'S OWN slice (see ENEMY3_FIND_FREE_SLOT) and
; spawns it using THIS wave's fixed OFFSET - not read from any table or
; cycled, just a plain constant for every member this wave produces.
; Decrements this wave's own budget and deactivates the slot once it
; reaches 0.
;
; On a FAILED claim (this wave's own slice is full - its own earlier
; members haven't died yet), the retry is rearmed for the VERY NEXT
; frame instead of waiting out the full ENEMY3_SPAWN_INTERVAL again, so
; this wave's own turnover feels immediate once a slot of its own frees up.
ENEMY3_TRY_SPAWN_SLOT:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IX+2)
    DEC A
    LD (IX+2),A
    RET NZ
    LD A,(IX+3) : LD B,A       ; B = this wave's offset, grabbed before IX changes
    PUSH IX                     ; save this wave slot's address
    PUSH BC                     ; save B (offset) - ENEMY3_FIND_FREE_SLOT clobbers B/DE/HL
    CALL ENEMY3_FIND_FREE_SLOT  ; HL(in)=this wave's own slice; IX(out)=free unit slot
    POP BC                       ; restore B (offset) - A (the found/not-found flag) survives
    OR A
    JR NZ,E3TSS_GOTUNIT
    POP IX                       ; no free unit slot in this wave's own slice - retry next frame
    LD (IX+2),1
    RET
E3TSS_GOTUNIT:
    LD (IX+11),B                ; CENTERX field, folded into the struct itself
    CALL ENEMY3_DO_SPAWN        ; spawns the unit at IX (its own RET returns here)
    POP HL                       ; HL = this wave slot's address again
    PUSH HL : POP IX             ; IX = wave slot, so (IX+n) offsets work below
    LD A,ENEMY3_SPAWN_INTERVAL
    LD (IX+2),A                  ; this attempt succeeded - resume normal pacing
    LD A,(IX+1) : DEC A : LD (IX+1),A
    RET NZ
    LD (IX+0),0                  ; budget exhausted - deactivate this wave
    RET

; Input: HL = base of an ENEMY3_SLOTS-instance slice of ENEMY3_POOL
; (one wave's own dedicated slice - see ENEMY3_TRY_SPAWN). Output: A=1
; and IX=slot base if a free (inactive) slot was found within that
; slice, else A=0. Clobbers: A, B, DE, HL, IX.
ENEMY3_FIND_FREE_SLOT:
    LD B,ENEMY3_SLOTS
E3FFS_LOOP:
    LD A,(HL)
    OR A
    JR Z,E3FFS_FOUND
    LD DE,ENEMY3_STRUCT
    ADD HL,DE
    DJNZ E3FFS_LOOP
    XOR A
    RET
E3FFS_FOUND:
    PUSH HL : POP IX
    LD A,1
    RET

ENEMY3_DO_SPAWN:
    LD A,1 : LD (IX+0),A
    XOR A : LD (IX+1),A
    LD A,(IX+11)                  ; this slot's centerx offset was just written by
                                   ; the caller - apply it to the entry point too, so
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
    LD HL,ENEMY3_SPAWN_COUNT : INC (HL)
    LD HL,ENEMY3_ACTIVE_COUNT : INC (HL)
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

; Advances/redraws every one of the ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS (64)
; pool slots, one frame each - called once per frame from the mainloop
; instead of unrolling 64 individual LD IX,.../CALL pairs. Every slot
; still needs visiting to check its ACTIVE flag, but ENEMY3_UPDATE_SLOT
; returns immediately (cheap) for inactive ones - see its own comment.
; ENEMY3_ACTIVE_COUNT==0 means every one of the 64 is inactive right
; now (spawning itself is ENEMY3_TRY_SPAWN's job, not this one's), so
; skip the scan entirely rather than pay ~150 T-states/slot to find
; that out the slow way.
; (2026-09-23、監査: Enemy3は生きている個体をENEMY3_ACTIVE_COUNT体見つけた
; 時点で走査を打ち切る。空いたウェーブの後方スロットを調べない)
ENEMY3_UPDATE_ALL:
    LD A,(ENEMY3_ACTIVE_COUNT)
    OR A
    RET Z
    LD C,A                         ; C = まだ見つけていない生存数
    LD HL,ENEMY3_POOL
    LD B,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS
E3UA_LOOP:
    ; ACTIVE is offset 0, so check it straight off HL before paying for
    ; PUSH/POP/CALL (same reasoning as ENEMY_POOL_UPDATE_ALL's EPUA_LOOP) -
    ; the ACTIVE_COUNT check above only skips the whole scan when EVERY
    ; slot is idle; most slots stay idle even while a few are active, so
    ; this per-slot check is still needed to keep those idle ones cheap.
    LD A,(HL)
    OR A
    JR Z,E3UA_SKIP
    PUSH BC
    PUSH HL
    PUSH HL : POP IX
    CALL ENEMY3_UPDATE_SLOT
    POP HL
    POP BC
    DEC C
    RET Z                          ; 生存個体を全部処理した
E3UA_SKIP:
    LD DE,ENEMY3_STRUCT
    ADD HL,DE
    DJNZ E3UA_LOOP
    RET

ENEMY3_UPDATE_SLOT:
    LD A,(IX+0)
    OR A
    RET Z    ; inactive - every deactivation path (E3_DEACTIVATE, E3_HIT_ONE_SLOT's
             ; kill) already erased this slot's cell exactly once at the moment it
             ; went inactive, so there's nothing left to do here. This used to
             ; unconditionally re-erase (a VDP write) every idle slot every single
             ; frame as a blanket safety net for a stray-sprite leak that E3_DEACTIVATE
             ; turned out to be the real source of (see its own comment) - at
             ; ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS (64) slots that blanket cost alone ran
             ; ~40000 T-states/frame (over half the whole frame budget) even with
             ; nothing on screen, which is what made the game unplayably slow.
    ; The erase-old-cell VDP write moved from here into E3_DRAW, which is
    ; the only place that knows the NEW row/col and can compare it
    ; against the still-untouched OLD row/col at (IX+4)/(IX+5) - most
    ; frames don't actually cross into a new nametable cell (DIAG/EXIT
    ; move only 2-3px/frame, well under one 8px cell, and CIRCLE holds
    ; its LUT position for ENEMY3_STEP_FRAMES-1 out of every
    ; ENEMY3_STEP_FRAMES frames), so this skips a whole VDP write
    ; (~177 T-states) on every one of those frames instead of paying
    ; for an erase+redraw pair when nothing actually moved.

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
; by (IX+11), its own CENTERX field, same offset the circle phase
; orbits - so a trio's members separate horizontally from spawn onward,
; not just once circling starts.
E3_DIAG:
    LD A,(IX+11) : ADD A,ENEMY3_CENTER_X : LD B,A
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
    LD A,(IX+11) : ADD A,ENEMY3_CENTER_X : ADD A,C : LD (IX+2),A
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
    CALL ENEMY3_ERASE_CELL   ; erase the last-drawn cell now, at the exact moment
                              ; this slot goes inactive - previously missing here,
                              ; the one real gap ENEMY3_UPDATE_SLOT's blanket
                              ; every-frame safety net was masking (see its comment)
    XOR A : LD (IX+0),A
    LD A,(ENEMY3_ACTIVE_COUNT) : DEC A : LD (ENEMY3_ACTIVE_COUNT),A
    RET

; (IX+4)/(IX+5) still hold LAST frame's row/col here - DIAG/CIRCLE/EXIT
; only touch X/Y (IX+2/+3). Erase the old cell ONLY if the new one
; differs - DIAG/EXIT move just 2-3px/frame (under one 8px cell most
; frames) and CIRCLE holds its LUT position for ENEMY3_STEP_FRAMES-1
; out of every ENEMY3_STEP_FRAMES frames, so most frames land on the
; SAME cell and can skip a whole VDP write (~177 T-states) instead of
; erasing something that's about to be overwritten with new content anyway.
E3_DRAW:
    LD A,(IX+3) : SRL A : SRL A : SRL A : LD B,A   ; B = new row
    LD A,(IX+2) : SRL A : SRL A : SRL A : LD C,A   ; C = new col
    LD A,(IX+4) : CP B : JR NZ,E3_DRAW_MOVED
    LD A,(IX+5) : CP C : JR Z,E3_DRAW_SAMECELL
E3_DRAW_MOVED:
    PUSH BC
    CALL ENEMY3_ERASE_CELL   ; still reads the OLD row/col off (IX+4)/(IX+5)
    POP BC
E3_DRAW_SAMECELL:
    LD A,B : LD (IX+4),A
    LD A,C : LD (IX+5),A
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
    LD A,(ENEMY3_ACTIVE_COUNT) : DEC A : LD (ENEMY3_ACTIVE_COUNT),A
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
; B/C are saved to scratch RAM across the scan (same ENEMY_HIT_COL/ROW
; used by CHECK_BULLET_VS_ENEMY_POOL) so the loop can use B as its
; counter over all ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS (64) slots.
;
; Called once per active bullet, every frame. ENEMY3_ACTIVE_COUNT bails
; out immediately when NOTHING is alive anywhere. But that alone wasn't
; enough: once even one wave is running, the loop used to pay full
; PUSH/POP/CALL overhead for EVERY one of the 64 slots regardless of
; whether that particular slot was active, costing ~13600 T-states/bullet
; even with just 1 real instance among the 64 (confirmed via the
; emulator's T-state counter) - since the schedule's clustered
; enemy3_wave triggers keep at least one wave alive for a long stretch
; of ticks, this made firing slow for most of that stretch even when
; the player wasn't looking at an Enemy3 at that exact instant. ACTIVE
; is offset 0, so it's checked straight off HL first (same idiom as
; CHECK_BULLET_VS_ENEMY_POOL/ENEMY_POOL_UPDATE_ALL) and only genuinely
; active slots pay for the PUSH/POP/CALL dance.
; (2026-09-23、監査: Enemy3は生きている個体をENEMY3_ACTIVE_COUNT体見つけた
; 時点で走査を打ち切る。空いたウェーブの後方スロットを調べない)
CHECK_BULLET_VS_ENEMY3:
    LD A,(ENEMY3_ACTIVE_COUNT)
    OR A
    JR Z,CBVE3_NONE
    LD D,A                         ; 生存数(下でCへ)
    LD A,B : LD (ENEMY_HIT_COL),A
    LD A,C : LD (ENEMY_HIT_ROW),A
    LD C,D                         ; C = まだ見つけていない生存数
    LD HL,ENEMY3_POOL
    LD B,ENEMY3_WAVE_SLOTS*ENEMY3_SLOTS
CBVE3_LOOP:
    LD A,(HL)
    OR A
    JR Z,CBVE3_SKIP
    ; (2026-09-23、監査): 弾もEnemy3も8px格子上の8x8なので、行(+4=ROW)が
    ; 違えばQUAD_HIT_TESTは必ず外れる - 呼び出し前に行だけ比べて弾く。
    PUSH HL
    LD DE,4 : ADD HL,DE
    LD A,(ENEMY_HIT_ROW) : CP (HL)
    POP HL
    JR NZ,CBVE3_NEXT_LIVE
    PUSH HL
    PUSH BC
    PUSH HL : POP IX
    LD A,(ENEMY_HIT_COL) : LD B,A
    LD A,(ENEMY_HIT_ROW) : LD C,A
    CALL E3_HIT_ONE_SLOT
    POP BC
    POP HL
    OR A
    JR NZ,CBVE3_HIT
CBVE3_NEXT_LIVE:
    DEC C
    JR Z,CBVE3_NONE                ; 生存個体を全部調べた
CBVE3_SKIP:
    LD DE,ENEMY3_STRUCT
    ADD HL,DE
    DJNZ CBVE3_LOOP
CBVE3_NONE:
    XOR A
    RET
CBVE3_HIT:
    LD A,1
    RET

; ============================================================
; enemy6: new BG-cell enemy (16x16 = 2x2 nametable cells), straight
; left drift. See the ENEMY6_* EQUs (near ENEMY3_POOL) for
; the pool layout/timing, and NEWENEMY_PATTERN_*/NEWENEMY_CODE_* (near
; the end of the file) for the glyph itself.
; ============================================================

; A holds this schedule index on entry (SSC_FIRE's CP-dispatch
; convention - see SPAWN_SIMPLE/SPAWN_E4 for the same pattern). Looks
; up this trigger's own row in ENEMY6_ROW_TABLE (any row, from the
; schedule editor - same idea as SPAWN_E4/SPAWN_BASEY_TABLE, just a raw
; row number here since ENEMY6_POOL already stores ROW directly, not a
; pixel baseY). Claims a free ENEMY6_POOL slot and draws it immediately
; there - drops the trigger silently if the pool (4 slots) is already full.
SPAWN_E6:
    LD DE,ENEMY6_ROW_TABLE
    ADD HL,DE
    LD A,(HL) : LD C,A           ; C = this trigger's row
    LD HL,ENEMY6_POOL
    LD B,ENEMY6_SLOTS
E6TS_LOOP:
    LD A,(HL)
    OR A
    JR Z,E6TS_FOUND
    LD DE,ENEMY6_STRUCT
    ADD HL,DE
    DJNZ E6TS_LOOP
    RET                          ; pool full - drop this trigger
E6TS_FOUND:
    PUSH HL : POP IX
    LD (IX+0),1
    LD A,C
    LD (IX+1),A
    LD A,ENEMY6_SPAWN_COL
    LD (IX+2),A
    XOR A : LD (IX+3),A          ; PHASE=0 (straight-on, unrotated)
    ; "ステージ1のエネミー6の耐久値4に"(2026-09-08) - スポーン時に
    ; このスロットのHPをENEMY6_HP_INITへ初期化(詳細はENEMY6_STRUCT
    ; 自身のコメント参照)。
    PUSH IX
    CALL ENEMY6_HP_ADDR
    LD A,ENEMY6_HP_INIT : LD (HL),A
    POP IX
    LD HL,ENEMY6_ACTIVE_COUNT : INC (HL)
    JP ENEMY6_DRAW

; Input: IX = ENEMY6_POOL slot base. Output: HL = &ENEMY6_HP[slot index]
; (slot index = (IX-ENEMY6_POOL)/ENEMY6_STRUCT、ENEMY6_STRUCT=4なので
; 2回の右シフトで求まる)。ENEMY6_HPが完全に独立した配列である理由は
; ENEMY6_STRUCT自身のコメント参照。Trashes: AF,DE,HL.
ENEMY6_HP_ADDR:
    PUSH IX : POP HL
    LD DE,ENEMY6_POOL
    OR A
    SBC HL,DE                    ; HL = byte offset from pool start (0-124, H always 0 -
                                  ; this assembler has no RR, so a 16-bit shift isn't
                                  ; needed anyway; the offset always fits in L alone)
    LD A,L
    SRL A : SRL A                 ; A = offset/ENEMY6_STRUCT(4) = slot index
    LD D,0 : LD E,A
    LD HL,ENEMY6_HP
    ADD HL,DE
    RET

; Advances the shared column-step timer; when it fires, moves every
; active slot left by one column (erase old 2x2 block, draw new one),
; or deactivates it once it reaches the left edge. On non-step frames
; this is a no-op - the BG cells already drawn stay put in VRAM
; without any CPU/VDP work, same reasoning as ENEMY3_UPDATE_SLOT's
; moved-cell check.
ENEMY6_UPDATE_ALL:
    LD A,(ENEMY6_STEP_TIMER)
    DEC A
    LD (ENEMY6_STEP_TIMER),A
    RET NZ
    LD A,ENEMY6_STEP_FRAMES
    LD (ENEMY6_STEP_TIMER),A
    ; (2026-09-23、メインループ監査): 1体も居ない時は32スロットの走査を
    ; 丸ごと省略(CHECK_BULLET_VS_ENEMY6と同じENEMY6_ACTIVE_COUNTゲート)。
    ; 歩進タイマー自体は従来どおり回す。
    LD A,(ENEMY6_ACTIVE_COUNT)
    OR A
    RET Z
    LD HL,ENEMY6_POOL
    LD B,ENEMY6_SLOTS
E6UA_LOOP:
    LD A,(HL)
    OR A
    JR Z,E6UA_SKIP
    PUSH BC
    PUSH HL
    PUSH HL : POP IX
    CALL ENEMY6_STEP_ONE
    POP HL
    POP BC
E6UA_SKIP:
    LD DE,ENEMY6_STRUCT
    ADD HL,DE
    DJNZ E6UA_LOOP
    RET

; Input: IX = slot base (ACTIVE,ROW,COL,PHASE). One column-step: erase
; the old 2x2 block, then either advance PHASE to the next spin frame
; and draw the new block one column left, or (if already at col0)
; deactivate instead of stepping off the nametable.
ENEMY6_STEP_ONE:
    CALL ENEMY6_ERASE
    LD A,(IX+2)
    OR A
    JR Z,E6SO_EXIT
    DEC A
    LD (IX+2),A
    LD A,(IX+3) : INC A : AND 3 : LD (IX+3),A   ; next spin frame (0/90/180/270)
    JP ENEMY6_DRAW
E6SO_EXIT:
    XOR A
    LD (IX+0),A
    LD HL,ENEMY6_ACTIVE_COUNT : DEC (HL)
    RET

; Input: IX = slot base (ROW at IX+1, COL at IX+2). Blanks this slot's
; current 2x2 nametable block back to sky (BLANKCODE) - unlike
; ENEMY3_ERASE_CELL this never restores ground-scroller content, so
; ENEMY6_ROW_TABLE entries (row and its +1 partner) need to stay above
; GROUND_ROW0 - same any-row-but-mind-the-ground responsibility the
; schedule editor already has for every other enemy. Clobbers A,DE,HL.
ENEMY6_ERASE:
    LD A,BLANKCODE : LD (ANIM_TMP_VAL),A
    LD A,(IX+1) : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    LD A,(IX+1) : INC A : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    LD A,(IX+1) : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : INC A : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    LD A,(IX+1) : INC A : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : INC A : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    RET

; Input: IX = slot base (ROW at IX+1, COL at IX+2, PHASE at IX+3).
; Draws this slot's current spin frame's 4 quadrant codes (from
; ENEMY6_ANIM_CODES(PHASE)) at its current position. Clobbers A,DE,HL.
ENEMY6_DRAW:
    LD A,(IX+3) : ADD A,A : ADD A,A : LD E,A : LD D,0   ; E = PHASE*4
    LD HL,ENEMY6_ANIM_CODES
    ADD HL,DE
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    LD A,(IX+1) : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : LD (ANIM_TMP_COL),A
    PUSH HL
    CALL WRITE_ANIM_CELL
    POP HL : INC HL
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    LD A,(IX+1) : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : INC A : LD (ANIM_TMP_COL),A
    PUSH HL
    CALL WRITE_ANIM_CELL
    POP HL : INC HL
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    LD A,(IX+1) : INC A : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : LD (ANIM_TMP_COL),A
    PUSH HL
    CALL WRITE_ANIM_CELL
    POP HL : INC HL
    LD A,(HL) : LD (ANIM_TMP_VAL),A
    LD A,(IX+1) : INC A : LD (ANIM_TMP_ROW),A
    LD A,(IX+2) : INC A : LD (ANIM_TMP_COL),A
    CALL WRITE_ANIM_CELL
    RET

; Input: B = bullet column (0-31), C = bullet row (0-23), D = target
; box's X (top-left, 16 wide), E = target box's Y (top-left, 16 tall).
; Output: A = 1 if the bullet's 8x8 cell overlaps the 16x16 box, else
; A = 0. Same edge-comparison idea as QUAD_HIT_TEST, just widened for
; enemy6's 2x2-cell glyph. Trashes H,L.
ENEMY6_HIT_TEST:
    LD A,B : ADD A,A : ADD A,A : ADD A,A : LD H,A
    LD A,C : ADD A,A : ADD A,A : ADD A,A : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,E6HT_NO
    LD A,D : ADD A,15
    CP H
    JR C,E6HT_NO
    LD A,L : ADD A,7
    CP E
    JR C,E6HT_NO
    LD A,E : ADD A,15
    CP L
    JR C,E6HT_NO
    LD A,1
    RET
E6HT_NO:
    XOR A
    RET

; Input: IX = slot base, B = bullet col, C = bullet row. Output: A=1 if
; this active instance overlapped the bullet (destroyed: erased +
; shared explosion/sound + score), else A=0 (inactive or no overlap).
; Same shape as E3_HIT_ONE_SLOT.
ENEMY6_HIT_ONE_SLOT:
    LD A,(IX+0)
    OR A
    JR Z,E6H_NO
    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+1) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL ENEMY6_HIT_TEST
    OR A
    JR Z,E6H_NO
    ; "ステージ1のエネミー6の耐久値4に"(2026-09-08) - 被弾即死から
    ; ENEMY4_HP/E_HPと同じ「耐久値制」へ変更(詳細はENEMY6_STRUCT自身の
    ; コメント参照)。HPが残っていれば弾は消費するが破壊はしない
    ; (EBSD_HT_ENEMY4のEBSD_HT_E4_DAMAGEDと同じ挙動)。
    PUSH DE                  ; D,E = hit X,Y - ENEMY6_HP_ADDR自体は保存不要だがPOP対称のため
    CALL ENEMY6_HP_ADDR
    LD A,(HL) : DEC A : LD (HL),A
    POP DE
    JR NZ,E6H_DAMAGED
    CALL E6SO_EXIT            ; deactivate slot + ENEMY6_ACTIVE_COUNT-- (shares ENEMY6_STEP_ONE's exit tail, byte budget)
    PUSH DE                  ; D,E = hit X,Y for TRIGGER_EXPLOSION below - ENEMY6_ERASE clobbers DE
    CALL ENEMY6_ERASE
    POP DE
    PUSH BC
    CALL TRIGGER_EXPLOSION
    CALL ADD_SCORE_300
    POP BC
    LD A,1
    RET
E6H_DAMAGED:
    ; --- still alive - bullet is consumed (caller stops it here) but ---
    ; --- the enemy keeps spinning/drifting, no explosion/score yet.  ---
    LD A,1
    RET
E6H_NO:
    XOR A
    RET

; Input: B = bullet col, C = bullet row. Output: A=1 if the bullet
; destroyed an ENEMY6 instance, else 0. ENEMY6_ACTIVE_COUNT (round135
; follow-up15, same idiom as ENEMY3_ACTIVE_COUNT) bails out immediately
; when nothing is alive anywhere, so the ENEMY6_SLOTS(32)-slot scan below
; only actually runs while at least one instance is on screen. Preserves
; the caller's B,C across the whole scan (its own loop reuses B as the
; DJNZ counter).
CHECK_BULLET_VS_ENEMY6:
    LD A,(ENEMY6_ACTIVE_COUNT)
    OR A
    RET Z                     ; A is already 0 here = correct "no hit" value
    PUSH BC
    LD A,B : LD (ENEMY_HIT_COL),A
    LD A,C : LD (ENEMY_HIT_ROW),A
    LD HL,ENEMY6_POOL
    LD B,ENEMY6_SLOTS
CBVE6_LOOP:
    LD A,(HL)
    OR A
    JR Z,CBVE6_SKIP
    PUSH HL
    PUSH BC
    PUSH HL : POP IX
    LD A,(ENEMY_HIT_COL) : LD B,A
    LD A,(ENEMY_HIT_ROW) : LD C,A
    CALL ENEMY6_HIT_ONE_SLOT
    POP BC
    POP HL
    OR A
    JR NZ,CBVE6_HIT
CBVE6_SKIP:
    LD DE,ENEMY6_STRUCT
    ADD HL,DE
    DJNZ CBVE6_LOOP
    POP BC
    XOR A
    RET
CBVE6_HIT:
    POP BC
    LD A,1
    RET

; ============================================================
; --- Ebuz: HP制の新エネミー(単発ミニボス的存在)。tools/ebuz_test/  ---
; --- で検証済みのstate1(初弾ホールド→発射)→state2(変形)→継続      ---
; --- 交互発射という一連の流れ(HANDOFF.md Round114-129参照)を本編へ ---
; --- 統合。(2026-09-14、ユーザー指示: "じゃあ組み込む バグらない    ---
; --- ように慎重に実装しろ 100Tickでスポーン 位置はY中央で 上から   ---
; --- 中央まで移動してシーケンススタート Ebuz出現中はスケジュール   ---
; --- エネミーは一旦停止 生存時間は15秒 時間になったら右に移動して  ---
; --- 消える 耐久値12")。プロトタイプと異なり本編のMAINLOOPは        ---
; --- 実時間の1フレームごとに1回だけ呼ばれる設計のため、プロトタイプ ---
; --- 自身のビジーウェイト(EBUZ_FRAME_WAIT/EBUZ_WAIT_TICKS)は一切    ---
; --- 持ち込まず、「1ティック=1回のCALL EBUZ_UPDATE(=1実フレーム)」 ---
; --- という素直な対応に置き換えている(タイミング定数[ホールド10/45  ---
; --- ティック等]の意味は不変)。弾も本体もプロトタイプと同じく完全に ---
; --- BGタイルのみで構成、新規HWスプライトは一切使わない。            ---
; ============================================================
EBUZ_ST_ENTER  EQU 1   ; 上から中央行まで降下中(本体2行のみ表示)
EBUZ_ST_STATE1 EQU 2   ; 中央到着、初弾ホールド→飛行中(本体2行のまま)
EBUZ_ST_STATE2 EQU 3   ; 変形直後、一斉発射前ホールド中(本体4行)
EBUZ_ST_FIRE   EQU 4   ; 継続交互発射中(本体4行)
EBUZ_ST_EXIT   EQU 5   ; 右へ移動して画面外へ消える(本体4行)

; (round135follow-up5、"今のハードコードしたEbuzスケジュールは削除
; しといて 意図と違ってるんで"): GAME_TICKが固定tick(100/256/512/
; 768/950)に達するたびEBUZ_SPAWN_CHAIN_STARTを自動発火するハード
; コード式トリガー(EBUZ_SPAWN_TICK_TABLE/COUNT/INDEX+MAINLOOP側の
; GAME_TICK凍結・比較ロジック)を全面撤去。
; (round135follow-up9、Schedule_2_1.json差し替えで解決): schedule-
; editor.htmlの"ebuz"パレットエントリ(round135follow-up3で追加済み)
; 経由でユーザーが実際に配置したスケジュールJSONを受け取り、他の
; エネミー同様SSC_FIRE(SPAWN_SCHEDULE_CHECK)のディスパッチから直接
; EBUZ_SPAWN_CHAIN_STARTを呼ぶ形へ再配線済み(SPAWN_THRESHOLDS参照)。
; Ebuz自身のチェーン進行ロジック(EBUZ_SPAWN_CHAIN_START/EBUZ_CHECK_
; CHAIN_TRIGGERS/EBUZ_ANY_ACTIVE等)自体は一切変更していない。
; (2026-09-14 follow-up、"耐久値24に"): 12→24。全インスタンス共通。
; (2026-09-24、"EbuzとEbuzIIの耐久値を倍に"): 24→48。
EBUZ_HP_INIT             EQU 48
; (2026-09-14 follow-up3、"Ebuz生存時間を5秒に"): 900(15秒)→300(5秒)。
; 60Hz想定、GAME_OVER_TIMEOUT_TICKS[600=10秒]等既存の実フレーム
; カウンタと同じ換算基準。
EBUZ_LIFETIME_FRAMES     EQU 300
; (2026-09-14follow-up2、"登場の上から降りてくる速度を倍に"): 6→3。
EBUZ_DESCEND_ROW_FRAMES  EQU 3     ; 降下速度: 1行あたりのフレーム数
; (2026-09-14follow-up2、"3体目出現を2体目の5秒後に"): 60Hz想定で
; 5秒=300フレーム(EBUZ_LIFETIME_FRAMESと同じ換算基準)。従来の
; "2体目がFIRE状態に達した瞬間"トリガーを置き換える。
EBUZ_INST3_DELAY_FRAMES  EQU 300
; (2026-09-14 follow-up、"スポーンでRow0のブラックの行を破壊してる
; Rowは避けRow1から描画するように"): 0→1。row0は画面上端のHUD/スコア
; 行のため、Ebuzの2行本体がここを跨ぐと破壊してしまっていた。
EBUZ_ENTER_START_ROW     EQU 1     ; "上から登場"(ただしrow0は避ける)
; (2026-09-14 follow-up、マルチインスタンス化): 単一のEBUZ_CENTER_ROW
; 定数を廃止し、インスタンスごとの中央行を3つ用意。実際にどのスロット
; がどの行を使うかはEBUZ_SPAWN_INSTANCE呼び出し時にAで渡す(各スロット
; のEBUZ_OFS_CENTER_ROWフィールドへ実行時に格納)。
EBUZ_ROW_INST1           EQU 9     ; 1体目("位置はY中央で")
EBUZ_ROW_INST2           EQU 12    ; 2体目("スポーン位置2体目がRow12")
EBUZ_ROW_INST3           EQU 5     ; 3体目("3体目Row5")
EBUZ_SPAWN_COL           EQU 24    ; 本体の固定列(X=192px、プロトタイプ踏襲)
EBUZ_BULLET1_COL         EQU 22    ; 初弾/継続弾の発射列(プロトタイプ踏襲)
EBUZ_EXIT_COL_FRAMES     EQU 3     ; 退出速度: 1列あたりのフレーム数(未調整の初期値)
; EBUZ_EXIT_COL_MAX(2026-09-14自己発見バグ経由での訂正): 翼帯行は
; 5列幅(col+0..+4)のため、name tableが32列/行である以上、COLが27を
; 超えるとcol+4が31を超えて次の行へ「折り返し」、隣接行(row9/10)の
; 左端セルを誤って上書きする実害バグになる(自己検証テストで実際に
; row8/row11の書き込みがrow9/row10の左端セルを破壊することを発見)。
; 32(画面右端ぴったり)ではなく28(=27+1、翼帯の右端col+4が常に31以内
; に収まる最後の安全なCOL)に設定 - 退出アニメーションはやや短くなる
; (画面完全外まで移動しきる前に非活性化)が、隣接行破壊という実害の
; 方がはるかに深刻なため安全側に倒した。
EBUZ_EXIT_COL_MAX        EQU 28
EBUZ_LANE_POOL_SIZE      EQU 8
EBUZ_SLOT_EMPTY          EQU 255
EBUZ_FIRE_INTERVAL       EQU 2     ; "2フレ交代"
EBUZ_RECOIL_DURATION     EQU 1
EBUZ_BULLET0_HOLD_TICKS  EQU 10
EBUZ_PREACT_HOLD_TICKS   EQU 45

; BGパターンコード: 本体4枚はA=group11(88)/B=group12(96)/C=group13(104)/
; D=group14(112)、各グループの先頭コードを1個だけ使用(round135
; follow-up8でA/B/C/Dを個別4色にするため、旧来の共有group16から分離。
; SCREEN1のカラーテーブルは8連続コード単位で色1個共有のため、コード
; ごとに違う色を持たせるには別グループに置くしかない - 残り7コード
; ずつ[89-95/97-103/105-111/113-119]は今後の予備)。弾2枚は引き続き
; group17(136-137、本体と別グループなのは元々本体と弾で色を変える
; ためだった、今回の変更で本体側も個別色になったが弾側の設計は無変更)。
; いずれも旧ANIM1_x/ANIM2_white/green専用だった削除済みの空きグループ
; (round69 follow-upのコメント、COLORDATA自身の"groups 6-31...unused
; by this scroller"、およびこのファイルの全LDIRVM呼び出し元横断
; チェックで空きを確認済み)。
EBUZ_CODE_A        EQU 88
EBUZ_CODE_B        EQU 96
EBUZ_CODE_C        EQU 104
EBUZ_CODE_D        EQU 112
EBUZ_BULLET_L_CODE EQU 136
EBUZ_BULLET_R_CODE EQU 137

; (round135follow-up8、"Ebuz1の左から1つ目のセルは背景ライトブルーで
; 文字色グレー 2セル目は背景ブラック文字色レッド 3セル目、背景ブラック
; 文字色グレー 4セル目、背景グレー文字色ブラック"): A=gray(14)/
; lightblue(5)、B=red(8)/black(1)、C=gray(14)/black(1)、D=black(1)/
; gray(14) - Ebuz1(ENTER時の単一行A,B,C,D)・Ebuz2(変形後の翼帯形態)は
; どちらも同じ4タイルを共有しているだけなので、コード単位で色を決めれば
; 両方に自動的に反映される(ユーザー提示のプレビュー画像で確認済み)。
; 弾色は無変更: fg11(SPR_YELLOWと同じ光黄色)/bg4(空と同じ青)。
EBUZ_COLOR_A_VAL           EQU 0E5h
EBUZ_COLOR_B_VAL           EQU 081h
EBUZ_COLOR_C_VAL           EQU 0E1h
EBUZ_COLOR_D_VAL           EQU 01Eh
EBUZ_BULLET_COLOR_BYTE_VAL EQU 0B4h

; (2026-09-14 follow-up、マルチインスタンス化): 従来のEBUZ_TOPBAND_ROW
; 等の「row0基準の固定行番号/固定VRAMアドレス」定数は、中央行が
; インスタンスごとに異なる(9/12/5)以上もはや意味を持たないため全廃。
; 代わりに各スロットが自分のEBUZ_OFS_CENTER_ROWフィールドを持ち、
; TOPBAND_ROW=CENTER_ROW-1/ROW9=CENTER_ROW/ROW10=CENTER_ROW+1/
; BOTBAND_ROW=CENTER_ROW+2を実行時にEBUZ_ADDR_*ヘルパー群(後述)で
; 都度計算する。EBUZ_SPAWN_COL(24)は全インスタンス共通の固定列の
; ため引き続きコンパイル時定数のまま。

; スロット構造体オフセット(2インスタンス[EBUZ_SLOT0/EBUZ_SLOT1]が
; 共有する1本のコード列をIXレジスタ経由で走らせる設計 - このアセン
; ブラは`ADD IX,DE`非対応のため、フィールドアドレスが必要な箇所は
; 都度`PUSH IX:POP HL`+オフセット加算[EBUZ_FIELD_ADDR]で求める、
; ENEMY_POOL等このプロジェクト既存の多インスタンスパターンを踏襲)。
EBUZ_OFS_ACT              EQU 0    ; 0=非活性、1-5=EBUZ_ST_*
EBUZ_OFS_ROW              EQU 1    ; 現在の本体上段行(降下中のみ変化、以後CENTER_ROW固定)
EBUZ_OFS_COL              EQU 2    ; 現在の本体左列(EXIT中のみ変化、それ以外EBUZ_SPAWN_COL固定)
EBUZ_OFS_HP               EQU 3
EBUZ_OFS_LIFE_TIMER       EQU 4    ; 2 bytes (4-5)
EBUZ_OFS_LIFE_TIMER_HI    EQU 5
EBUZ_OFS_DESCEND_COUNTER  EQU 6
EBUZ_OFS_EXIT_COUNTER     EQU 7
EBUZ_OFS_B0_ACTIVE        EQU 8
EBUZ_OFS_B0_HOLDING       EQU 9
EBUZ_OFS_B0_COL           EQU 10
EBUZ_OFS_B0_HOLD_COUNTER  EQU 11
EBUZ_OFS_PREACT_COUNTER   EQU 12
EBUZ_OFS_FIRE_SIDE        EQU 13
EBUZ_OFS_FIRE_COUNTDOWN   EQU 14
EBUZ_OFS_RECOIL_SIDE      EQU 15
EBUZ_OFS_RECOIL_COUNTDOWN EQU 16
EBUZ_OFS_TOP_COLS         EQU 17   ; 8 bytes (17-24)
EBUZ_OFS_BOTTOM_COLS      EQU 25   ; 8 bytes (25-32)
EBUZ_OFS_TOP_NEXT         EQU 33
EBUZ_OFS_BOTTOM_NEXT      EQU 34
EBUZ_OFS_CENTER_ROW       EQU 35   ; このインスタンスの中央行(9/12/5)、スポーン時に確定
EBUZ_SLOT_SIZE            EQU 36

; グローバルスクラッチ(top/bottomプール更新中のみ使用、両スロットの
; 処理が時間的に重ならないため1本の共有バッファで安全)+チェーン進行
; 状態+8セル死亡演出の待ち行列(EBUZ_QUEUE_EXPLOSIONS参照)。
EBUZ_CUR_ROW_ADDR     EQU 0F25Ch  ; 2 bytes: ADDR_TOPBAND/BOTBANDのキャッシュ+EBUZ_UPDATE_BULLET0のROW9キャッシュ共用
EBUZ_SPAWN_STAGE      EQU 0F25Eh  ; 0=未スポーン/1=1体目消化待ち/2=2体目消化中/3=3体目トリガー済み
EBUZ_EXPL_QUEUE       EQU 0F25Fh  ; 16 entries * 2 bytes (X,Y) = 32 bytes
EBUZ_EXPL_QUEUE_COUNT EQU 0F27Fh
; (2026-09-14follow-up、ROM容量節約のためLIFO化): 旧EBUZ_EXPL_QUEUE_HEAD
; (FIFO環状バッファ用)は不要になったため、2体目スポーンから3体目
; スポーンまでの実時間(5秒)をカウントする16bitタイマーへ転用
; (EBUZ_CHECK_CHAIN_TRIGGERSのSTAGE==2区間で使用)。
EBUZ_CHAIN_TIMER      EQU 0F280h  ; 2 bytes
EBUZ_EXPL_SPAWN_TIMER EQU 0F282h
EBUZ_EXPL_POS_X       EQU 0F283h
EBUZ_EXPL_POS_Y       EQU 0F284h
EBUZ_EXPL_QUEUE_CAPACITY EQU 16   ; 2の冪(ENQUEUE/UPDATE_QUEUEの容量チェック用)
EBUZ_EXPL_SPAWN_INTERVAL EQU 4    ; 未調整の初期値、8セル連続ポップの間隔(フレーム)
; 0F285hは旧EBUZ_SPAWN_TICK_INDEX(round135follow-up5で撤去済みの
; ハードコードスケジュール機構専用だった1byte) - INIT側の一括ゼロ
; クリア(EBUZ_CUR_ROW_ADDRから42byte、EBUZ_SLOT0の直前まで)の範囲内
; にそのまま残っているだけの未使用パディング、新規に使ってよい。

EBUZ_SLOT0 EQU 0F286h
EBUZ_SLOT1 EQU EBUZ_SLOT0+EBUZ_SLOT_SIZE

; (2026-09-19、"ステージ1ボスの接近時自機狙い弾を32方向LUT化"): pod
; bullets' per-frame X speed magnitude(1-12、常にXから減算する値。元の
; 固定POD_BULLET_SPEEDと同じ「Xがアンダーフローしたら画面外」判定を
; そのまま使うため符号なしの絶対値のまま持つ)。方向ごとに値が変わる
; ようになったため新規に1byte/bulletが必要になった。EBUZ_SLOT1の直後
; (0F286h+36+36=0F2CEh)からSTACKTOP(0F380h)まで実測178byte空きと
; ファイル全体のEQUアドレスを横断的に洗い出した上で確認済み、2byte
; 消費しても176byte残る(このファイルにはStage2のstack_safety_test.py
; に相当する自動マージン検証は無いため、この178byteという数字は手動の
; ギャップ監査に基づく一度きりの確認であり、継続的な回帰保護は無い点に
; 留意)。
POD_BULLET0_DXMAG EQU 0F2CEh
POD_BULLET1_DXMAG EQU 0F2CFh

; VRAMの連続2byteへ書き込む(左セル・右セル)。tools/ebuz_test/
; ebuz_test.asmのEBUZ_WRITE2と同一設計。
EBUZ_WRITE2:
    LD A,B
    CALL WRTVRM
    INC HL
    LD A,C
    CALL WRTVRM
    RET

; Input: A=row(0-23), C=col(0-31). Output: DE=NAMTBL上の該当セル
; アドレス(このファイル既存のROWADDR_LO/HIテーブルを再利用、
; BULLET0_ADDR計算等と同じ規約)。Trashes A,H,L.
EBUZ_CELL_ADDR:
    LD H,A
    LD E,A : LD D,ROWADDR_LO/256 : LD A,(DE) : LD L,A
    LD A,H : LD E,A : LD D,ROWADDR_HI/256 : LD A,(DE) : LD H,A
    LD D,0 : LD E,C
    ADD HL,DE
    LD D,H : LD E,L
    RET

; Input: IX=スロット先頭、A=スロット先頭からのバイトオフセット。
; Output: HL=IX+A(絶対アドレス)。A自体は保持される(内部ではD,Eしか
; 破壊しない)。ENEMY_POOL等このプロジェクト既存のIX多インスタンス
; パターンと同じ「ADD IX,DE非対応の代替」慣用句。Trashes D,E.
EBUZ_FIELD_ADDR:
    PUSH IX : POP HL
    LD E,A : LD D,0
    ADD HL,DE
    RET

; Input: A=row(0-23), C=col(0-31)。Output: HL=NAMTBL上の該当セル
; アドレス(EBUZ_CELL_ADDRのDE出力をHLへコピーするだけの共有テール、
; 下の8種のEBUZ_ADDR_*ヘルパーから共有され、ROM容量節約のため重複
; コードをここへ集約する)。Trashes A,D,E,H,L.
EBUZ_ADDR_CORE:
    CALL EBUZ_CELL_ADDR
    LD H,D : LD L,E
    RET

; IX=スロット先頭。中央行(EBUZ_OFS_CENTER_ROW)から実行時に導出した
; TOPBAND_ROW(=CENTER_ROW-1)/ROW9(=CENTER_ROW)/ROW10(=CENTER_ROW+1)/
; BOTBAND_ROW(=CENTER_ROW+2)の col0 または col=EBUZ_SPAWN_COL 地点の
; VRAMアドレスをHLで返す8種のヘルパー(2026-09-14follow-up、マルチ
; インスタンス化に伴い旧来のEBUZ_TOPBAND_ADDR等コンパイル時定数を
; 置換)。共通の末尾処理はEBUZ_ADDR_COREへ集約。Trashes A,D,E,H,L.
EBUZ_ADDR_TOPBAND:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : DEC A
    LD C,0
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_ROW9:
    LD A,(IX+EBUZ_OFS_CENTER_ROW)
    LD C,0
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_ROW10:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A
    LD C,0
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_BOTBAND:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A : INC A
    LD C,0
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_TOPBAND_FIRE:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : DEC A
    LD C,EBUZ_SPAWN_COL
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_ROW9_FIRE:
    LD A,(IX+EBUZ_OFS_CENTER_ROW)
    LD C,EBUZ_SPAWN_COL
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_ROW10_FIRE:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A
    LD C,EBUZ_SPAWN_COL
    JP EBUZ_ADDR_CORE
EBUZ_ADDR_BOTBAND_FIRE:
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A : INC A
    LD C,EBUZ_SPAWN_COL
    JP EBUZ_ADDR_CORE

; IX=スロット先頭。現在の(IX+ROW)(および+1)の2行x4列ぶんをHLが指す
; 4byteテーブルで一括書き込みする(ENTER中の降下ステップの消去/描画、
; 撃破時[span2]の消去に使う共有ヘルパー)。列は常にEBUZ_SPAWN_COL固定
; (ENTER中はCOLが変化しないため定数のままでよい)。
; Input: HL=4byteソーステーブル(EBUZ_ROW_ABCD/EBUZ_ROW_ABCD_BLANK)。
; Trashes A,B,C,D,E,H,L。
EBUZ_BODY2_WRITE:
    PUSH HL
    LD A,(IX+EBUZ_OFS_ROW)
    LD C,EBUZ_SPAWN_COL
    CALL EBUZ_CELL_ADDR
    POP HL
    PUSH HL
    LD BC,4
    CALL LDIRVM
    POP HL
    PUSH HL
    LD A,(IX+EBUZ_OFS_ROW) : INC A
    LD C,EBUZ_SPAWN_COL
    CALL EBUZ_CELL_ADDR
    POP HL
    LD BC,4
    CALL LDIRVM
    RET

; 共有5byte/4byte書き込みヘルパー3種(2026-09-14follow-up、ROM容量
; 節約 - EBUZ_ENTER_STATE2/EBUZ_UPDATE_TOPBOTTOM_FIREで計8回重複していた
; 「LD D,H:LD E,L:LD HL,データ:LD BC,n:CALL LDIRVM」を集約)。
; Input: HL=EBUZ_ADDR_*_FIRE系が返すセルアドレス(HL出力)。
; Trashes A,B,C,D,E,H,L。
; (JP LDIRVMによる末尾呼び出しにしない理由: tools/z80emu.pyのBIOS
; コールインターセプトはCALL命令[opcode 0xCD]でのみ発火しJPでは効かない
; ため、実機では等価でもこのテスト環境では暴走する - CALL+RETで統一)
EBUZ_WRITE5_REST:
    LD D,H : LD E,L
    LD HL,EBUZ_ROW_BAND_REST : LD BC,5
    CALL LDIRVM
    RET
EBUZ_WRITE5_RECOIL:
    LD D,H : LD E,L
    LD HL,EBUZ_ROW_BAND_RECOIL : LD BC,5
    CALL LDIRVM
    RET
EBUZ_WRITE4_DONLY:
    LD D,H : LD E,L
    LD HL,EBUZ_ROW_D_ONLY : LD BC,4
    CALL LDIRVM
    RET
EBUZ_WRITE5_BLANK:
    LD D,H : LD E,L
    LD HL,EBUZ_ROW_BAND_BLANK : LD BC,5
    CALL LDIRVM
    RET
EBUZ_WRITE4_BLANK:
    LD D,H : LD E,L
    LD HL,EBUZ_ROW_D_BLANK : LD BC,4
    CALL LDIRVM
    RET

; プール(上/下共通)の1スロット分の更新。IN: IX=スロット先頭、
; E=スロット先頭からのTOP_COLS/BOTTOM_COLS内バイトオフセット
; (EBUZ_FIELD_ADDRの計算をここへ融合し、呼び出し元ごとの個別CALLを
; 省く - ROM容量節約、tools/ebuz_test/ebuz_test.asmのEBUZ_UPDATE_SLOT
; と設計思想は同一)。EBUZ_CUR_ROW_ADDR=このプールが使う行の先頭
; アドレス(呼び出し元がCALL直前にセット)。Trashes A,B,C,D,E,H,L.
EBUZ_UPDATE_SLOT:
    PUSH IX : POP HL
    LD D,0
    ADD HL,DE
    LD A,(HL)
    CP EBUZ_SLOT_EMPTY
    RET Z
    PUSH HL
    PUSH AF
    LD E,A : LD D,0
    LD HL,(EBUZ_CUR_ROW_ADDR)
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE
    CALL EBUZ_WRITE2
    POP AF
    OR A
    JR Z,EBUZ_US_OFF
    DEC A
    POP HL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,(EBUZ_CUR_ROW_ADDR)
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET
EBUZ_US_OFF:
    POP HL
    LD (HL),EBUZ_SLOT_EMPTY
    RET

; IX=スロット先頭、E=バイトオフセット(上記EBUZ_UPDATE_SLOTと同じ
; 呼び出し規約)。対象のレーンスロットを、現在位置に関わらず強制的に
; 消去・非活性化する(EBUZ_UPDATE_SLOTと違い列を進めない) - EXIT開始時
; /撃破時の一斉消去専用。EBUZ_CUR_ROW_ADDRは呼び出し元がCALL直前に
; セット。Trashes A,D,E,H,L.
EBUZ_CLEAR_SLOT:
    PUSH IX : POP HL
    LD D,0
    ADD HL,DE
    LD A,(HL)
    CP EBUZ_SLOT_EMPTY
    RET Z
    PUSH HL
    LD E,A : LD D,0
    LD HL,(EBUZ_CUR_ROW_ADDR)
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE
    CALL EBUZ_WRITE2
    POP HL
    LD (HL),EBUZ_SLOT_EMPTY
    RET

; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_UPDATE_TOP_POOL:
    CALL EBUZ_ADDR_TOPBAND
    LD (EBUZ_CUR_ROW_ADDR),HL
    LD E,EBUZ_OFS_TOP_COLS+0 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+1 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+2 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+3 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+4 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+5 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+6 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_TOP_COLS+7 : CALL EBUZ_UPDATE_SLOT
    RET

; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_UPDATE_BOTTOM_POOL:
    CALL EBUZ_ADDR_BOTBAND
    LD (EBUZ_CUR_ROW_ADDR),HL
    LD E,EBUZ_OFS_BOTTOM_COLS+0 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+1 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+2 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+3 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+4 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+5 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+6 : CALL EBUZ_UPDATE_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+7 : CALL EBUZ_UPDATE_SLOT
    RET

; 上レーンへ1発、無条件で新規発射する(生存チェックなし、ローテー
; ションでプールの次のスロットを使う - tools/ebuz_test/ebuz_test.asm
; と同一設計)。
; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_FIRE_TOP_BULLET:
    LD A,(IX+EBUZ_OFS_TOP_NEXT)
    LD B,A
    INC A
    CP EBUZ_LANE_POOL_SIZE
    JR C,EBUZ_FTB_OK
    XOR A
EBUZ_FTB_OK:
    LD (IX+EBUZ_OFS_TOP_NEXT),A
    LD A,EBUZ_OFS_TOP_COLS
    ADD A,B
    CALL EBUZ_FIELD_ADDR
    LD A,EBUZ_BULLET1_COL
    LD (HL),A
    CALL EBUZ_ADDR_TOPBAND
    LD E,EBUZ_BULLET1_COL : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET

; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_FIRE_BOTTOM_BULLET:
    LD A,(IX+EBUZ_OFS_BOTTOM_NEXT)
    LD B,A
    INC A
    CP EBUZ_LANE_POOL_SIZE
    JR C,EBUZ_FBB_OK
    XOR A
EBUZ_FBB_OK:
    LD (IX+EBUZ_OFS_BOTTOM_NEXT),A
    LD A,EBUZ_OFS_BOTTOM_COLS
    ADD A,B
    CALL EBUZ_FIELD_ADDR
    LD A,EBUZ_BULLET1_COL
    LD (HL),A
    CALL EBUZ_ADDR_BOTBAND
    LD E,EBUZ_BULLET1_COL : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET

; 上下弾の継続発射処理(tools/ebuz_test/ebuz_test.asmのEBUZ_UPDATE_
; TOPBOTTOM_FIREと同一設計、行アドレスのみ本編の値に置換)。
; EBUZ_ST_FIREの間、EBUZ_UPDATEから毎フレーム呼ばれる。
; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_UPDATE_TOPBOTTOM_FIRE:
    LD A,(IX+EBUZ_OFS_RECOIL_COUNTDOWN)
    OR A
    JR Z,EUTF_SKIP_REVERT
    DEC A
    LD (IX+EBUZ_OFS_RECOIL_COUNTDOWN),A
    JR NZ,EUTF_SKIP_REVERT
    LD A,(IX+EBUZ_OFS_RECOIL_SIDE)
    OR A
    JR NZ,EUTF_REVERT_BOTTOM
    CALL EBUZ_ADDR_TOPBAND_FIRE
    CALL EBUZ_WRITE5_REST
    JR EUTF_SKIP_REVERT
EUTF_REVERT_BOTTOM:
    CALL EBUZ_ADDR_BOTBAND_FIRE
    CALL EBUZ_WRITE5_REST
EUTF_SKIP_REVERT:
    LD A,(IX+EBUZ_OFS_FIRE_COUNTDOWN)
    DEC A
    LD (IX+EBUZ_OFS_FIRE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ_FIRE_INTERVAL
    LD (IX+EBUZ_OFS_FIRE_COUNTDOWN),A
    LD A,(IX+EBUZ_OFS_FIRE_SIDE)
    OR A
    JR NZ,EUTF_FIRE_BOTTOM
    CALL EBUZ_ADDR_TOPBAND_FIRE
    CALL EBUZ_WRITE5_RECOIL
    CALL EBUZ_FIRE_TOP_BULLET
    JR EUTF_FIRE_DONE
EUTF_FIRE_BOTTOM:
    CALL EBUZ_ADDR_BOTBAND_FIRE
    CALL EBUZ_WRITE5_RECOIL
    CALL EBUZ_FIRE_BOTTOM_BULLET
EUTF_FIRE_DONE:
    ; round135follow-up4: both the TOP and BOTTOM fire paths above fall
    ; through to here, so a single CALL covers every shot (does not touch
    ; IX - safe, the (IX+...) reads right below still need it).
    CALL SOUND_EBUZ_FIRE
    LD A,(IX+EBUZ_OFS_FIRE_SIDE)
    LD (IX+EBUZ_OFS_RECOIL_SIDE),A
    LD A,EBUZ_RECOIL_DURATION
    LD (IX+EBUZ_OFS_RECOIL_COUNTDOWN),A
    LD A,(IX+EBUZ_OFS_FIRE_SIDE)
    XOR 1
    LD (IX+EBUZ_OFS_FIRE_SIDE),A
    RET

; 初弾(bullet0)の更新: ホールド中は静止表示のまま、ホールド解除後は
; 毎フレーム1列ずつ左へ飛び続け、画面外で非活性化する
; (tools/ebuz_test/ebuz_test.asmのEBUZ_TICK冒頭部分と同一設計)。
; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
; (2026-09-14follow-up、ROM容量節約): CALL EBUZ_ADDR_ROW9/ROW10自体は
; colを一切読まないため、呼び出し前にAへ退避してPUSH/POP AFで呼び出し
; 跨ぎ保持する必要はない - colはこの間(IX+EBUZ_OFS_B0_COL)のメモリ上で
; 不変なので、呼び出し後に直接LD E,(IX+d)で読み直す方が短い。
EBUZ_UPDATE_BULLET0:
    LD A,(IX+EBUZ_OFS_B0_ACTIVE)
    OR A
    RET Z
    LD A,(IX+EBUZ_OFS_B0_HOLDING)
    OR A
    RET NZ
    CALL EBUZ_ADDR_ROW9
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE : CALL EBUZ_WRITE2
    CALL EBUZ_ADDR_ROW10
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE : CALL EBUZ_WRITE2
    LD A,(IX+EBUZ_OFS_B0_COL)
    OR A
    JR Z,EBUZ_B0_OFF
    DEC A
    LD (IX+EBUZ_OFS_B0_COL),A
    CALL EBUZ_ADDR_ROW9
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE : CALL EBUZ_WRITE2
    CALL EBUZ_ADDR_ROW10
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE : CALL EBUZ_WRITE2
    RET
EBUZ_B0_OFF:
    XOR A
    LD (IX+EBUZ_OFS_B0_ACTIVE),A
    RET

; 生存中のbullet0+上下レーン全弾を強制消去する共有ヘルパー
; (EBUZ_BEGIN_EXIT/EBUZ_DESTROY共通)。
; IX=スロット先頭。Trashes A,B,C,D,E,H,L.
EBUZ_CLEAR_ALL_BULLETS:
    LD A,(IX+EBUZ_OFS_B0_ACTIVE)
    OR A
    JR Z,ECAB_B0_DONE
    CALL EBUZ_ADDR_ROW9
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE : CALL EBUZ_WRITE2
    CALL EBUZ_ADDR_ROW10
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,BLANKCODE : LD C,BLANKCODE : CALL EBUZ_WRITE2
    XOR A : LD (IX+EBUZ_OFS_B0_ACTIVE),A
ECAB_B0_DONE:
    CALL EBUZ_ADDR_TOPBAND
    LD (EBUZ_CUR_ROW_ADDR),HL
    LD E,EBUZ_OFS_TOP_COLS+0 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+1 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+2 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+3 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+4 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+5 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+6 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_TOP_COLS+7 : CALL EBUZ_CLEAR_SLOT
    CALL EBUZ_ADDR_BOTBAND
    LD (EBUZ_CUR_ROW_ADDR),HL
    LD E,EBUZ_OFS_BOTTOM_COLS+0 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+1 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+2 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+3 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+4 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+5 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+6 : CALL EBUZ_CLEAR_SLOT
    LD E,EBUZ_OFS_BOTTOM_COLS+7 : CALL EBUZ_CLEAR_SLOT
    RET

; IX=スロット先頭。state2形成後(継続発射開始前)へ遷移。BG変形+
; ホールドカウンタ初期化。
EBUZ_ENTER_STATE2:
    LD A,EBUZ_ST_STATE2
    LD (IX+EBUZ_OFS_ACT),A
    CALL EBUZ_ADDR_TOPBAND_FIRE
    CALL EBUZ_WRITE5_REST
    CALL EBUZ_ADDR_ROW9_FIRE
    CALL EBUZ_WRITE4_DONLY
    CALL EBUZ_ADDR_ROW10_FIRE
    CALL EBUZ_WRITE4_DONLY
    CALL EBUZ_ADDR_BOTBAND_FIRE
    CALL EBUZ_WRITE5_REST
    LD A,EBUZ_PREACT_HOLD_TICKS
    LD (IX+EBUZ_OFS_PREACT_COUNTER),A
    RET

; IX=スロット先頭。中央到着直後、state1(初弾ホールド)へ遷移。
; bullet0を表示・ホールド開始する。
EBUZ_ENTER_STATE1:
    LD A,EBUZ_ST_STATE1
    LD (IX+EBUZ_OFS_ACT),A
    LD A,1 : LD (IX+EBUZ_OFS_B0_ACTIVE),A
    LD A,1 : LD (IX+EBUZ_OFS_B0_HOLDING),A
    LD A,EBUZ_BULLET1_COL : LD (IX+EBUZ_OFS_B0_COL),A
    LD A,EBUZ_BULLET0_HOLD_TICKS : LD (IX+EBUZ_OFS_B0_HOLD_COUNTER),A
    CALL EBUZ_ADDR_ROW9
    LD E,EBUZ_BULLET1_COL : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE : CALL EBUZ_WRITE2
    CALL EBUZ_ADDR_ROW10
    LD E,(IX+EBUZ_OFS_B0_COL) : LD D,0
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE : CALL EBUZ_WRITE2
    RET

; IX=スロット先頭。ENTER: 6フレームに1回、1行降下。中央行
; ((IX+EBUZ_OFS_CENTER_ROW))に到達したらstate1へ遷移。
EBUZ_DO_ENTER:
    LD A,(IX+EBUZ_OFS_DESCEND_COUNTER)
    INC A
    CP EBUZ_DESCEND_ROW_FRAMES
    JR C,EBUZ_ENTER_WAIT
    XOR A
    LD (IX+EBUZ_OFS_DESCEND_COUNTER),A
    LD HL,EBUZ_ROW_ABCD_BLANK
    CALL EBUZ_BODY2_WRITE
    LD A,(IX+EBUZ_OFS_ROW) : INC A : LD (IX+EBUZ_OFS_ROW),A
    LD HL,EBUZ_ROW_ABCD
    CALL EBUZ_BODY2_WRITE
    LD D,(IX+EBUZ_OFS_CENTER_ROW)
    LD A,(IX+EBUZ_OFS_ROW)
    CP D
    RET NZ
    JP EBUZ_ENTER_STATE1
EBUZ_ENTER_WAIT:
    LD (IX+EBUZ_OFS_DESCEND_COUNTER),A
    RET

; IX=スロット先頭。STATE1: bullet0のホールドカウントダウン。0になったら
; ホールド解除(次フレームからEBUZ_UPDATE_BULLET0が自動的に飛ばし
; 始める)、同時に(待ちなしで)state2へ変形。
EBUZ_DO_STATE1:
    LD A,(IX+EBUZ_OFS_B0_HOLD_COUNTER)
    DEC A
    LD (IX+EBUZ_OFS_B0_HOLD_COUNTER),A
    RET NZ
    XOR A
    LD (IX+EBUZ_OFS_B0_HOLDING),A
    JP EBUZ_ENTER_STATE2

; IX=スロット先頭。STATE2: 一斉発射前ホールドのカウントダウン。0に
; なったら継続交互発射を開始。
EBUZ_DO_STATE2:
    LD A,(IX+EBUZ_OFS_PREACT_COUNTER)
    DEC A
    LD (IX+EBUZ_OFS_PREACT_COUNTER),A
    RET NZ
    LD A,EBUZ_ST_FIRE
    LD (IX+EBUZ_OFS_ACT),A
    XOR A : LD (IX+EBUZ_OFS_FIRE_SIDE),A
    LD A,1 : LD (IX+EBUZ_OFS_FIRE_COUNTDOWN),A
    RET

; FIRE: 継続交互発射処理そのもの。IX=スロット先頭。
EBUZ_DO_FIRE:
    JP EBUZ_UPDATE_TOPBOTTOM_FIRE

; IX=スロット先頭。現在の(IX+EBUZ_OFS_COL)における本体4行footprintを
; 消去する(EXIT移動の各ステップ、および撃破[state2以降]で共用)。
EBUZ_EXIT_ERASE:
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : DEC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE5_BLANK
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW)
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE4_BLANK
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE4_BLANK
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A : INC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE5_BLANK
    RET

; IX=スロット先頭。現在の(IX+EBUZ_OFS_COL)における本体4行footprint
; (REST/D-only)を描画する(EXIT移動の各ステップ専用 - 反動は出さない、
; 発射も止まっている)。
EBUZ_EXIT_DRAW:
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : DEC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE5_REST
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW)
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE4_DONLY
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE4_DONLY
    LD C,(IX+EBUZ_OFS_COL)
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : INC A : INC A
    CALL EBUZ_ADDR_CORE
    CALL EBUZ_WRITE5_REST
    RET

; IX=スロット先頭。生存時間15秒が経過した瞬間に呼ばれる: 発射停止+
; 残存弾を全消去してEXIT状態へ(本体自体はまだ現在の見た目のまま、
; EBUZ_DO_EXITが実際に動かす)。
EBUZ_BEGIN_EXIT:
    CALL EBUZ_CLEAR_ALL_BULLETS
    XOR A
    LD (IX+EBUZ_OFS_EXIT_COUNTER),A
    LD A,EBUZ_ST_EXIT
    LD (IX+EBUZ_OFS_ACT),A
    RET

; IX=スロット先頭。EXIT: 3フレームに1回、1列右へ移動(消去→列+1→
; 再描画)。EBUZ_EXIT_COL_MAXに達したら完全非活性化(=このスロットが
; 空くことでチェーンの次段階トリガーが発火する)。
EBUZ_DO_EXIT:
    LD A,(IX+EBUZ_OFS_EXIT_COUNTER)
    INC A
    CP EBUZ_EXIT_COL_FRAMES
    JR C,EBUZ_EXIT_WAIT
    XOR A
    LD (IX+EBUZ_OFS_EXIT_COUNTER),A
    CALL EBUZ_EXIT_ERASE
    LD A,(IX+EBUZ_OFS_COL) : INC A : LD (IX+EBUZ_OFS_COL),A
    CP EBUZ_EXIT_COL_MAX
    JR NC,EBUZ_EXIT_DEACTIVATE
    CALL EBUZ_EXIT_DRAW
    RET
EBUZ_EXIT_WAIT:
    LD (IX+EBUZ_OFS_EXIT_COUNTER),A
    RET
EBUZ_EXIT_DEACTIVATE:
    XOR A
    LD (IX+EBUZ_OFS_ACT),A
    RET

; IX=スロット先頭。撃破処理: 8セル分の死亡演出をキューへ積んでから
; (EBUZ_QUEUE_EXPLOSIONS)現在の本体形状(2行/4行)を消去し、生存中の
; 弾を全消去して完全に非活性化する(このスロットが空くことでチェーンの
; 次段階トリガーが発火する)。
EBUZ_DESTROY:
    CALL EBUZ_QUEUE_EXPLOSIONS
    LD A,(IX+EBUZ_OFS_ACT)
    CP EBUZ_ST_STATE2
    JR NC,EBDX_SPAN4
    LD HL,EBUZ_ROW_ABCD_BLANK
    CALL EBUZ_BODY2_WRITE
    JR EBDX_BULLETS
EBDX_SPAN4:
    CALL EBUZ_EXIT_ERASE
EBDX_BULLETS:
    CALL EBUZ_CLEAR_ALL_BULLETS
    XOR A
    LD (IX+EBUZ_OFS_ACT),A
    RET

; IX=スロット先頭、A=このインスタンスの中央行(EBUZ_ROW_INST1/2/3の
; いずれか)。スロットを丸ごと(再利用時の汚染防止のため防御的に全
; フィールド)初期化してENTER状態でスポーンする。Trashes A,B,C,D,E,H,L.
EBUZ_SPAWN_INSTANCE:
    LD (IX+EBUZ_OFS_CENTER_ROW),A
    LD A,EBUZ_ST_ENTER
    LD (IX+EBUZ_OFS_ACT),A
    LD A,EBUZ_ENTER_START_ROW
    LD (IX+EBUZ_OFS_ROW),A
    LD A,EBUZ_SPAWN_COL
    LD (IX+EBUZ_OFS_COL),A
    LD A,EBUZ_HP_INIT
    LD (IX+EBUZ_OFS_HP),A
    LD HL,EBUZ_LIFETIME_FRAMES
    LD (IX+EBUZ_OFS_LIFE_TIMER),L
    LD (IX+EBUZ_OFS_LIFE_TIMER_HI),H
    XOR A
    LD (IX+EBUZ_OFS_DESCEND_COUNTER),A
    LD (IX+EBUZ_OFS_EXIT_COUNTER),A
    LD (IX+EBUZ_OFS_B0_ACTIVE),A
    LD (IX+EBUZ_OFS_B0_HOLDING),A
    LD (IX+EBUZ_OFS_FIRE_SIDE),A
    LD (IX+EBUZ_OFS_FIRE_COUNTDOWN),A
    LD (IX+EBUZ_OFS_RECOIL_SIDE),A
    LD (IX+EBUZ_OFS_RECOIL_COUNTDOWN),A
    ; TOP_COLS/BOTTOM_COLS/TOP_NEXT/BOTTOM_NEXTは明示的に再初期化しない
    ; (ROM容量の都合上、正しさの根拠をコメントに残す): このスロットの
    ; 前インスタンスがACT=0(=このEBUZ_SPAWN_INSTANCE自体が呼ばれる
    ; 前提条件)に至る経路は、EXIT完了[EBUZ_EXIT_DEACTIVATE、EBUZ_BEGIN_
    ; EXITが既にEBUZ_CLEAR_ALL_BULLETSを呼んでいる]か撃破[EBUZ_DESTROY
    ; 自身がEBUZ_CLEAR_ALL_BULLETSを呼ぶ]のいずれかしかなく、どちらも
    ; TOP_COLS/BOTTOM_COLSを必ずEBUZ_SLOT_EMPTYまで戻してから終わる
    ; (Round130の単一インスタンス設計でも同様に無再初期化だった)。
    ; TOP_NEXT/BOTTOM_NEXTはローテーションindex(0-7の任意値で開始して
    ; よい)のため、そもそも0への固定は不要。
    LD HL,EBUZ_ROW_ABCD
    CALL EBUZ_BODY2_WRITE
    RET

; チェーン(1体目→2体目→3体目)を1回開始するエントリポイント。
; (round135follow-up5、"ハードコードしたEbuzスケジュールは削除"):
; 従来はMAINLOOPがGAME_TICKをEBUZ_SPAWN_TICK_TABLEの固定値
; (100/256/512/768/950)と比較して自動的にここを呼んでいたが、その
; 仕組み自体を撤去した。
; (round135follow-up9): 呼び出し元はSSC_FIRE(SPAWN_SCHEDULE_CHECK)の
; ディスパッチから、他のSPAWN_*ハンドラと全く同じCP+JP Zの形で直接
; 呼ばれる(専用ラッパー不要 - このルーチン自体がRETで終わるため)。
; 詳細はEBUZ_HP_INIT直前のコメント・SPAWN_THRESHOLDS参照。
; 1体目をSLOT0(中央行EBUZ_ROW_INST1)へスポーンし
; EBUZ_SPAWN_STAGEを1にする(前回のチェーンが3[終端]のままでも無条件に
; 上書きし新しいチェーンを開始する)。2体目・3体目のスポーンは
; EBUZ_CHECK_CHAIN_TRIGGERSが毎フレーム進行させる("2体目のスポーンは
; 1体目が消えたら[撤退/撃破いずれも]"、"3体目出現を2体目の5秒後に")。
EBUZ_SPAWN_CHAIN_START:
    LD IX,EBUZ_SLOT0
    LD A,EBUZ_ROW_INST1
    CALL EBUZ_SPAWN_INSTANCE
    LD A,1
    LD (EBUZ_SPAWN_STAGE),A
    RET

; MAINLOOPから毎フレーム無条件に呼ばれる(EBUZ_UPDATE_ALLの直後)。
; EBUZ_SPAWN_STAGEを見て2体目/3体目のスポーンタイミングを判定する。
; 1体目・2体目は同じSLOT0を使い回す(1体目が完全に消えてから2体目が
; 湧くため同時生存しない)、3体目はSLOT1(2体目とは同時生存しうる、
; 2026-09-14follow-up2で"2体目のスポーンから5秒後"の実時間トリガーへ
; 変更 - Stage1は1フレーム=1/60秒の生フレーム駆動のため300フレーム)。
EBUZ_CHECK_CHAIN_TRIGGERS:
    LD A,(EBUZ_SPAWN_STAGE)
    CP 1
    JR NZ,ECCT_CHECK2
    LD A,(EBUZ_SLOT0+EBUZ_OFS_ACT)
    OR A
    RET NZ                        ; 1体目はまだ生存中(撤退/撃破いずれも未完了)
    LD IX,EBUZ_SLOT0
    LD A,EBUZ_ROW_INST2
    CALL EBUZ_SPAWN_INSTANCE
    LD A,2 : LD (EBUZ_SPAWN_STAGE),A
    XOR A
    LD (EBUZ_CHAIN_TIMER),A
    LD (EBUZ_CHAIN_TIMER+1),A
    RET
ECCT_CHECK2:
    CP 2
    RET NZ
    LD HL,(EBUZ_CHAIN_TIMER)
    INC HL
    LD (EBUZ_CHAIN_TIMER),HL
    LD DE,EBUZ_INST3_DELAY_FRAMES
    OR A
    SBC HL,DE
    RET C                          ; まだ5秒(300フレーム)経過していない
    LD IX,EBUZ_SLOT1
    LD A,EBUZ_ROW_INST3
    CALL EBUZ_SPAWN_INSTANCE
    LD A,3 : LD (EBUZ_SPAWN_STAGE),A
    RET

; Output: A=1でSLOT0/SLOT1いずれかが現在アクティブ。
; (round135follow-up11、"Tickカウントをとめるのが合理的だろう"):
; MAINLOOP側のGAME_TICKインクリメント直前のゲートから呼ばれる
; (follow-up10で一度試したSSC_FIRE側だけのディスパッチ一時停止
; [時計は進め続ける]は、Ebuz消滅の瞬間に経過tick分のエントリが
; まとめて連続発火するバーストを生むため撤回、時計自体を止める
; follow-up5以前と同じ構造に戻した)。2体・3体のチェーン全体を通して
; 1回も途切れないよう2スロットを見る。
; (round135follow-up14、"3体目が消えたらポーズ解除な": EBUZ_DESTROY
; [プレイヤーが撃破した場合]は8セル分の死亡演出をEBUZ_EXPL_QUEUEへ
; 積んだ直後にACTを即0クリアしていたため、そのキューがまだ画面上で
; 再生中[EBUZ_EXPL_UPDATE_QUEUEが間隔を置いて1個ずつポップしている
; 最中]でも「非活性」と誤判定し、爆発演出が終わる前にスケジュールの
; 凍結が解除されてしまっていた実バグ。EBUZ_EXPL_QUEUE_COUNTが0に
; 戻るまで[退避エフェクトが全てPLAYER_EXPL_POOLへポップし終わるまで]
; もアクティブ扱いに含める)。
; Trashes A.
EBUZ_ANY_ACTIVE:
    LD A,(EBUZ_SLOT0+EBUZ_OFS_ACT)
    OR A
    JR NZ,EAA_YES
    LD A,(EBUZ_SLOT1+EBUZ_OFS_ACT)
    OR A
    JR NZ,EAA_YES
    LD A,(EBUZ_EXPL_QUEUE_COUNT)
    OR A
    JR NZ,EAA_YES
    XOR A
    RET
EAA_YES:
    LD A,1
    RET

; Ebuz1インスタンス分のメインエントリ。IX=スロット先頭で呼ぶこと
; (EBUZ_ACT=0の間は即RET)。生存時間タイマはEXIT中を除く全状態で
; 毎フレーム減算され、0に達したら他の処理より先にEXITへ遷移する。
EBUZ_UPDATE_ONE:
    LD A,(IX+EBUZ_OFS_ACT)
    OR A
    RET Z
    CP EBUZ_ST_EXIT
    JR Z,EBUZ_SKIP_LIFETIMER
    LD L,(IX+EBUZ_OFS_LIFE_TIMER)
    LD H,(IX+EBUZ_OFS_LIFE_TIMER_HI)
    LD A,H : OR L
    JR Z,EBUZ_SKIP_LIFETIMER
    DEC HL
    LD (IX+EBUZ_OFS_LIFE_TIMER),L
    LD (IX+EBUZ_OFS_LIFE_TIMER_HI),H
    LD A,H : OR L
    JR NZ,EBUZ_SKIP_LIFETIMER
    JP EBUZ_BEGIN_EXIT
EBUZ_SKIP_LIFETIMER:
    CALL EBUZ_UPDATE_BULLET0
    CALL EBUZ_UPDATE_TOP_POOL
    CALL EBUZ_UPDATE_BOTTOM_POOL
    LD A,(IX+EBUZ_OFS_ACT)
    CP EBUZ_ST_ENTER
    JP Z,EBUZ_DO_ENTER
    CP EBUZ_ST_STATE1
    JP Z,EBUZ_DO_STATE1
    CP EBUZ_ST_STATE2
    JP Z,EBUZ_DO_STATE2
    CP EBUZ_ST_FIRE
    JP Z,EBUZ_DO_FIRE
    CP EBUZ_ST_EXIT
    JP Z,EBUZ_DO_EXIT
    RET

; MAINLOOPから毎フレーム無条件に呼ばれる、両スロットを明示的に2回
; CALLする(project既存のUPDATE_ENEMIES等と同じ固定スロット数の展開
; 呼び出しパターン)。
EBUZ_UPDATE_ALL:
    LD IX,EBUZ_SLOT0
    CALL EBUZ_UPDATE_ONE
    LD IX,EBUZ_SLOT1
    CALL EBUZ_UPDATE_ONE
    RET

; Input: D=row(0-23), E=col(0-31)。1セル分の爆発待ち行列エントリを
; EBUZ_EXPL_QUEUEへ追加(X=col*8,Y=row*8としてpush)。キューが
; EBUZ_EXPL_QUEUE_CAPACITY(16、両インスタンス8セルずつの最悪ケースを
; 収容)に達している場合は静かにdrop(このプロジェクト標準の
; 「プール枯渇時はdrop」慣用句)。呼び出し元がD,Eをインクリメントし
; ながら連続呼び出しできるようD,Eは保持する。
; (2026-09-14follow-up、ROM容量節約のためLIFO[スタック]方式へ簡略化:
; 死亡演出のポップ順序は視覚的に無関係なため、EBUZ_EXPL_QUEUE_HEADに
; よるFIFO環状バッファ[mod演算が必要]をやめ、常にCOUNT位置へpush/
; そこからpopするだけの単純なスタックにした - HEADフィールド自体と
; AND演算が丸ごと不要になる)。Trashes A,B,C,H,L.
EBUZ_EXPL_ENQUEUE_CELL:
    LD A,(EBUZ_EXPL_QUEUE_COUNT)
    CP EBUZ_EXPL_QUEUE_CAPACITY
    RET NC
    ADD A,A
    LD C,A : LD B,0
    PUSH HL
    LD HL,EBUZ_EXPL_QUEUE
    ADD HL,BC
    LD A,E : ADD A,A : ADD A,A : ADD A,A
    LD (HL),A
    INC HL
    LD A,D : ADD A,A : ADD A,A : ADD A,A
    LD (HL),A
    POP HL
    LD A,(EBUZ_EXPL_QUEUE_COUNT) : INC A : LD (EBUZ_EXPL_QUEUE_COUNT),A
    RET

; IX=撃破されたスロットの先頭(ACT/ROW/COL/CENTER_ROWがまだ生きている
; うちに呼ぶこと - EBUZ_DESTROYが最初に呼ぶ)。可視本体セル8個ぶんの
; 位置をEBUZ_EXPL_QUEUEへ積む(2026-09-14 follow-up、"爆発エフェクトは
; Ebuzセル毎に1回 8セルだから8回エフェクトとサウンド")。span2
; (ENTER/STATE1、ABCD4タイル×2行=8セル)とspan4(STATE2以降、
; 翼帯3セル×2+中央D柱1セル×2=8セル)のいずれでもちょうど8個。
; Trashes A,B,C,D,E,H,L.
EBUZ_QUEUE_EXPLOSIONS:
    LD A,(IX+EBUZ_OFS_ACT)
    CP EBUZ_ST_STATE2
    JR NC,EQE_SPAN4
    LD D,(IX+EBUZ_OFS_ROW)
    CALL EQE_ROW4
    LD D,(IX+EBUZ_OFS_ROW) : INC D
    CALL EQE_ROW4
    RET
EQE_SPAN4:
    LD D,(IX+EBUZ_OFS_CENTER_ROW) : DEC D
    CALL EQE_ROW3
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : ADD A,2 : LD D,A
    CALL EQE_ROW3
    LD D,(IX+EBUZ_OFS_CENTER_ROW)
    CALL EQE_ROW1
    LD D,(IX+EBUZ_OFS_CENTER_ROW) : INC D
    CALL EQE_ROW1
    RET

; D=row(呼び出し元が設定、EBUZ_EXPL_ENQUEUE_CELL自体はD,Eを保持するため
; ここでも保持される)。span2の1行ぶん(4セル、col=COL..COL+3)を積む。
EQE_ROW4:
    LD E,(IX+EBUZ_OFS_COL)
    CALL EBUZ_EXPL_ENQUEUE_CELL
    INC E : CALL EBUZ_EXPL_ENQUEUE_CELL
    INC E : CALL EBUZ_EXPL_ENQUEUE_CELL
    INC E : CALL EBUZ_EXPL_ENQUEUE_CELL
    RET

; D=row。span4の翼帯1本ぶん(3セル、col=COL+1..COL+3)を積む。
EQE_ROW3:
    LD E,(IX+EBUZ_OFS_COL) : INC E
    CALL EBUZ_EXPL_ENQUEUE_CELL
    INC E : CALL EBUZ_EXPL_ENQUEUE_CELL
    INC E : CALL EBUZ_EXPL_ENQUEUE_CELL
    RET

; D=row。span4の中央D柱1セル(col=COL+3)を積む。
EQE_ROW1:
    LD A,(IX+EBUZ_OFS_COL) : ADD A,3 : LD E,A
    JP EBUZ_EXPL_ENQUEUE_CELL

; 毎フレーム無条件に呼ばれる(MAINLOOP、PLAYER_EXPL_UPDATE_ALLの直後)。
; EBUZ_EXPL_QUEUEを一定間隔(EBUZ_EXPL_SPAWN_INTERVAL)で1個ずつ消化し、
; PLAYER_EXPL_POOLの1バーストパーティクルとしてポップさせる
; (PEUA_TRY_SPAWN_AT、"自機爆発のサウンドとスプライトを流用" -
; 実際の飛散アニメーション・色サイクル・消去は既存のPLAYER_EXPL_
; UPDATE_ALL[PEUA_INSTANCESループ]がそのまま面倒を見る、ここでは
; スポーンのみ担当)。Trashes A,B,C,D,E,H,L.
EBUZ_EXPL_UPDATE_QUEUE:
    LD A,(EBUZ_EXPL_QUEUE_COUNT)
    OR A
    RET Z
    LD A,(EBUZ_EXPL_SPAWN_TIMER)
    OR A
    JR Z,EEUQ_FIRE
    DEC A
    LD (EBUZ_EXPL_SPAWN_TIMER),A
    RET
EEUQ_FIRE:
    LD A,EBUZ_EXPL_SPAWN_INTERVAL
    LD (EBUZ_EXPL_SPAWN_TIMER),A
    ; LIFO方式(EBUZ_EXPL_ENQUEUE_CELL自身のコメント参照): 常に現在の
    ; COUNT-1番目(=直近pushされた要素)をpopする。
    LD A,(EBUZ_EXPL_QUEUE_COUNT) : DEC A
    LD (EBUZ_EXPL_QUEUE_COUNT),A
    ADD A,A
    LD C,A : LD B,0
    LD HL,EBUZ_EXPL_QUEUE
    ADD HL,BC
    LD A,(HL) : LD (EBUZ_EXPL_POS_X),A
    INC HL
    LD A,(HL) : LD (EBUZ_EXPL_POS_Y),A
    JP PEUA_TRY_SPAWN_AT

; Input: D,E=自機と比較する箱の左上ピクセル座標、B=高さ-1(15=2行分/
; 31=4行分、幅は常に32px[4列]固定)。Output: A=1で自機ヒットボックス
; と重なる。Trashes A,H,L.
PLAYER_HIT_BOX_EBUZ:
    LD A,(PLAYERX) : LD H,A
    LD A,(PLAYERY) : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,PHBEZ_NO
    LD A,D : ADD A,31
    CP H
    JR C,PHBEZ_NO
    LD A,L : ADD A,7
    CP E
    JR C,PHBEZ_NO
    LD A,E : ADD A,B
    CP L
    JR C,PHBEZ_NO
    LD A,1
    RET
PHBEZ_NO:
    XOR A
    RET

; (2026-09-14follow-up2、"Ebuzの弾の判定は1pxに 他もすべて1px"):
; bullet0・上下レーン弾で共用する1px判定(従来はbullet0=16x16の
; PLAYER_HIT_BOX16、レーン弾=16x8の専用箱だったが、いずれも箱を
; 使わず基準座標(D,E)そのものを点として扱う統一ヘルパーへ差し替え)。
; Input: D,E=弾の基準ピクセル座標。Output: A=1で自機ヒットボックスと
; 重なる。Trashes A,H,L.
PLAYER_HIT_BOX_EBUZ_1PX:
    LD A,(PLAYERX) : LD H,A
    LD A,(PLAYERY) : LD L,A
    LD A,H : ADD A,7
    CP D
    JR C,PHBEZ1_NO
    LD A,D
    CP H
    JR C,PHBEZ1_NO
    LD A,L : ADD A,7
    CP E
    JR C,PHBEZ1_NO
    LD A,E
    CP L
    JR C,PHBEZ1_NO
    LD A,1
    RET
PHBEZ1_NO:
    XOR A
    RET

; Input: B=bullet col, C=bullet row. Output: A=1 if the bullet hit
; either Ebuz instance(damaged or destroyed either way - bullet is
; consumed), else 0. B,Cを読むだけで書き換えないため、呼び出し元の
; CHECK_BULLET_VS_ENEMY_POOL(B,Cがそのまま生き残っている前提)への
; 影響はない(両スロットをチェーンしてもMISS経路は一貫してB,Cを
; 保持するため契約は保たれる)。
CHECK_BULLET_VS_EBUZ:
    LD IX,EBUZ_SLOT0
    CALL CHECK_BULLET_VS_EBUZ_ONE
    OR A
    RET NZ
    LD IX,EBUZ_SLOT1
    JP CHECK_BULLET_VS_EBUZ_ONE

; IX=スロット先頭、B=bullet col, C=bullet row。Output: A=1でヒット。
CHECK_BULLET_VS_EBUZ_ONE:
    LD A,(IX+EBUZ_OFS_ACT)
    OR A
    JR Z,CBVEZ_MISS
    LD D,(IX+EBUZ_OFS_COL)
    LD A,B : SUB D
    CP 4
    JR NC,CBVEZ_MISS
    LD A,(IX+EBUZ_OFS_ACT)
    CP EBUZ_ST_STATE2
    JR C,CBVEZ_SPAN2
    LD D,(IX+EBUZ_OFS_CENTER_ROW) : DEC D
    LD A,C : SUB D
    CP 4
    JR NC,CBVEZ_MISS
    JR CBVEZ_HIT
CBVEZ_SPAN2:
    LD D,(IX+EBUZ_OFS_ROW)
    LD A,C : SUB D
    CP 2
    JR NC,CBVEZ_MISS
CBVEZ_HIT:
    LD A,(IX+EBUZ_OFS_HP) : DEC A : LD (IX+EBUZ_OFS_HP),A
    JR NZ,CBVEZ_DAMAGED
    CALL EBUZ_DESTROY
    CALL ADD_SCORE_2000
    LD A,1
    RET
CBVEZ_DAMAGED:
    LD A,1
    RET
CBVEZ_MISS:
    XOR A
    RET

; Ebuz本体・弾(bullet0+上下レーン)との接触判定(両スロット)。Ebuz自身
; へのダメージ処理はここでは行わない(それはCHECK_BULLET_VS_EBUZ側の
; 役割 - 既存のPDC_CHECK_*群と同じ「接触のみ検出、相手[Ebuz]は無傷」
; という設計)。Output: A=1で接触。
PDC_CHECK_EBUZ:
    LD IX,EBUZ_SLOT0
    CALL PDC_CHECK_EBUZ_ONE
    OR A
    RET NZ
    LD IX,EBUZ_SLOT1
    JP PDC_CHECK_EBUZ_ONE

; IX=スロット先頭。Output: A=1で接触。
PDC_CHECK_EBUZ_ONE:
    LD A,(IX+EBUZ_OFS_ACT)
    OR A
    JR Z,PDCEZ_MISS
    LD A,(IX+EBUZ_OFS_COL) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+EBUZ_OFS_ACT)
    CP EBUZ_ST_STATE2
    JR C,PDCEZ_SPAN2
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : DEC A
    ADD A,A : ADD A,A : ADD A,A : LD E,A
    LD B,31
    JR PDCEZ_BODY_TEST
PDCEZ_SPAN2:
    LD A,(IX+EBUZ_OFS_ROW)
    ADD A,A : ADD A,A : ADD A,A : LD E,A
    LD B,15
PDCEZ_BODY_TEST:
    CALL PLAYER_HIT_BOX_EBUZ
    OR A
    JR NZ,PDCEZ_HIT
    LD A,(IX+EBUZ_OFS_B0_ACTIVE)
    OR A
    JR Z,PDCEZ_SKIP_B0
    LD A,(IX+EBUZ_OFS_B0_COL) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    OR A
    JR NZ,PDCEZ_HIT
PDCEZ_SKIP_B0:
    LD A,EBUZ_OFS_TOP_COLS : CALL EBUZ_FIELD_ADDR
    LD B,EBUZ_LANE_POOL_SIZE
    LD C,(IX+EBUZ_OFS_CENTER_ROW) : DEC C
    CALL PDCEZ_SCAN_LANE
    OR A
    JR NZ,PDCEZ_HIT
    LD A,EBUZ_OFS_BOTTOM_COLS : CALL EBUZ_FIELD_ADDR
    LD B,EBUZ_LANE_POOL_SIZE
    LD A,(IX+EBUZ_OFS_CENTER_ROW) : ADD A,2 : LD C,A
    CALL PDCEZ_SCAN_LANE
    OR A
    RET Z
PDCEZ_HIT:
    LD A,1
    RET
PDCEZ_MISS:
    XOR A
    RET

; 上/下レーン共通スキャン。Input: HL=プール先頭、B=スロット数、
; C=そのレーンの行番号。Output: A=1でヒット。
PDCEZ_SCAN_LANE:
PDCEZ_SL_LOOP:
    LD A,(HL)
    CP EBUZ_SLOT_EMPTY
    JR Z,PDCEZ_SL_SKIP
    PUSH HL
    ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,C : ADD A,A : ADD A,A : ADD A,A : LD E,A
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    POP HL
    OR A
    JR NZ,PDCEZ_SL_HIT
PDCEZ_SL_SKIP:
    INC HL
    DJNZ PDCEZ_SL_LOOP
    XOR A
    RET
PDCEZ_SL_HIT:
    LD A,1
    RET

EBUZ_ROW_ABCD:
    DB EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C,EBUZ_CODE_D
EBUZ_ROW_ABCD_BLANK:
    DB BLANKCODE,BLANKCODE,BLANKCODE,BLANKCODE
; state2の翼帯(col+0..+4、5byte): 静止時REST=[空,A,B,C,空]、反動時
; RECOIL=[空,空,A,B,C](tools/ebuz_test/ebuz_test.asmと同一パターン、
; 0→BLANKCODEへ変更のみ)。
EBUZ_ROW_BAND_REST:
    DB BLANKCODE,EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C,BLANKCODE
EBUZ_ROW_BAND_RECOIL:
    DB BLANKCODE,BLANKCODE,EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C
EBUZ_ROW_BAND_BLANK:
    DB BLANKCODE,BLANKCODE,BLANKCODE,BLANKCODE,BLANKCODE
; state2の中央2行(col+0..+3、4byte): Dタイルだけが右端に残る。
EBUZ_ROW_D_ONLY:
    DB BLANKCODE,BLANKCODE,BLANKCODE,EBUZ_CODE_D
EBUZ_ROW_D_BLANK:
    DB BLANKCODE,BLANKCODE,BLANKCODE,BLANKCODE

; 4つの8x8タイル(tools/ebuz_test/ebuz_test.asmと同一データ、添付
; Ebuz1_32x32.jsonから機械抽出済み)。
EBUZ_TILE_A:
    DB 126,191,1,63,63,1,191,126
EBUZ_TILE_B:
    DB 255,84,42,126,126,42,84,255
EBUZ_TILE_C:
    DB 126,195,189,181,173,189,195,126
EBUZ_TILE_D:
    DB 255,65,127,127,127,127,65,255

; 弾の8x8タイル2枚(tools/ebuz_test/ebuz_test.asmと同一データ)。
EBUZ_BULLET_L_TILE:
    DB 0,0,127,255,255,127,0,0
EBUZ_BULLET_R_TILE:
    DB 0,0,254,255,255,254,0,0

EBUZ_COLOR_A:
    DB EBUZ_COLOR_A_VAL
EBUZ_COLOR_B:
    DB EBUZ_COLOR_B_VAL
EBUZ_COLOR_C:
    DB EBUZ_COLOR_C_VAL
EBUZ_COLOR_D:
    DB EBUZ_COLOR_D_VAL
EBUZ_BULLET_COLOR_BYTE:
    DB EBUZ_BULLET_COLOR_BYTE_VAL

; ============================================================================
; Ebuz Mk2: ボス出現の直前に一度だけ現れるスクリプト敵(2026-09-20、
; tools/ebuz_mk2_test/ebuz_mk2_test.asmで詰めた「5門斉射→リコイル→
; 変形(7行open)→内外交互連射→上下往復1周ごとにレーザー発射→無限
; ループ」という一連のシーケンスをそのまま移植)。"キャラはレーザー
; 以外流用で"の指示通り、本体4タイル(EBUZ_CODE_A-D/EBUZ_COLOR_A-D)・
; 弾2タイル(EBUZ_BULLET_L/R_CODE)・低レベルヘルパー(EBUZ_WRITE2/
; EBUZ_CELL_ADDR/SOUND_EBUZ_FIRE/PLAYER_HIT_BOX_EBUZ系)は無印Ebuzの
; ものをそのまま参照し、新規に用意するのはレーザーのタイル2枚+専用
; カラー1組のみ。ここでしか出現しない単一インスタンスのため、無印
; Ebuzのような複数インスタンス用IX構造体は使わず絶対アドレスで直接
; 扱う(ROM容量節約)。
;
; スポーンはCHECK_BOSS_TRIGGER末尾のJP BOSS_SPAWNを横取りする形で
; 実装(このセクション末尾EBUZ2_ON_BOSS_TRIGGER参照) - Mk2撃破まで
; 実ボスは出現しない。
; ============================================================================
EBUZ2_LASER_L_CODE EQU 144   ; group18(144-151)。実プレイ6000フレーム
EBUZ2_LASER_R_CODE EQU 145   ; 監視で実際に空きと確認済み(旧ANIM2-brown
                              ; 跡地、COLORDATAのプレースホルダー色のみ
                              ; 残存)。
EBUZ2_LASER_COLOR  EQU 074h  ; fg7(cyan)/bg4(blue、無印Ebuzの弾と同じ
                              ; 空色 - EBUZ_BULLET_COLOR_BYTE_VAL=0B4hの
                              ; 下位ニブルと同一)

; (2026-09-24、"EbuzとEbuzIIの耐久値を倍に"): 128→256。1byteのままなので0で256を表す
; (被弾ごとにDECして0で撃破 → 0,255,...,1,0の256発目で撃破)。
EBUZ2_HP_INIT EQU 0
EBUZ2_SLOT_EMPTY EQU 255
EBUZ2_V2_SLOT_COUNT EQU 4

EBUZ2_ENTRY_START_ROW  EQU 1   ; row0はHUD行のため避ける(無印Ebuzと同じ規約)
EBUZ2_ENTRY_TARGET_ROW EQU 9   ; 閉状態(5行)の中央到達行
EBUZ2_S2_ROW_TOP       EQU 8   ; 開状態(7行)の描画開始行(中心行を閉状態と揃える)

EBUZ2_ENTRY_HOLD_TICKS EQU 4
EBUZ2_RECOIL_HOLD_TICKS EQU 1
EBUZ2_VOLLEY1_HOLD_TICKS EQU 15
EBUZ2_VOLLEY2_WAVE_HOLD_TICKS EQU 2
EBUZ2_VOLLEY2_PRE_FIRE_HOLD_TICKS EQU 5
EBUZ2_VOLLEY2_ALT_START_HOLD_TICKS EQU 20
EBUZ2_LAP_STOP_HOLD_TICKS EQU 15
EBUZ2_LASER_HOLD_TICKS EQU 4
EBUZ2_POST_DEFEAT_WAIT_TICKS EQU 50  ; round138follow-up4"EbuzII撃破後50Tickウェイト追加"
; round138follow-up5("変形後1発撃つがこれを削除...20Tick交互連射して
; から上下動作に...ビーム発射後は20Tick静止連射してからまた下に動く"):
; 変形直後・ビーム発射後のループリセット直後の両方で共通して使う
; 「上下移動を開始する前に静止したまま交互連射する」tick数。
EBUZ2_STATIC_FIRE_TICKS EQU 20

EBUZ2_MOVE_INTERVAL_TICKS EQU 4
; round138(実機フィードバック対応): 移植元tools/ebuz_mk2_test/ebuz_mk2_test.asm
; ではMOVE_MIN_ROW=1・MOVE_MAX_ROW=13だったが、Stage1移植時に誤って2/14
; (1セル下)へずれていた。これが「上下移動が1セル下にズレてる」の直接
; 原因。加えてMAX_ROW=14だとS2本体(7行、row_top+6)がrow20(GROUND_ROW0、
; 4-row ground scrollerの先頭行、NAMEBUF/PREVBUF差分キャッシュ経由でしか
; 再描画されない領域)まで到達し、Mk2の生VRAM書き込みがこのキャッシュを
; 素通りして地形を破損させていた(round54と同型のバグ、「ブランクが
; 地形のデータに化けてる」の実体)。1/13へ戻すことで両方解消(MAX_ROW=13
; ならS2本体の最下行はrow19までで、row20には一切到達しない)。
EBUZ2_MOVE_MIN_ROW EQU 1
EBUZ2_MOVE_MAX_ROW EQU 13

EBUZ2_OUTER_COL EQU 24
EBUZ2_INNER_COL EQU 23
EBUZ2_CENTER_COL EQU 22
EBUZ2_S2_FIRE_COL_INNER EQU 22
EBUZ2_S2_FIRE_COL_OUTER EQU 23

; row*ベースアドレス(閉状態5列、EBUZ_CELL_ADDR経由で毎回計算するため
; コンパイル時定数は不要 - 無印Ebuzと同じ設計)。

; ---- RAM(単一インスタンス、絶対アドレス。EBUZ_SLOT1直後の空き
; 領域[実測176byte、POD_BULLET1_DXMAGコメント参照]の先頭から68byte
; だけを使用、STACKTOPまで100byte超の余裕を残す) ----
EBUZ2_ACT              EQU 0F2D0h
EBUZ2_PHASE            EQU 0F2D1h  ; 0=登場中/1=スクリプト進行中(テーブル駆動)/2=撃破演出中
EBUZ2_HP               EQU 0F2D2h
EBUZ2_ROW_CUR          EQU 0F2D3h
EBUZ2_MOVE_DIR         EQU 0F2D4h
EBUZ2_MOVE_ACTIVE      EQU 0F2D5h
EBUZ2_MOVE_COUNTDOWN   EQU 0F2D6h
EBUZ2_MOVE_R_MAX       EQU 0F2D7h
EBUZ2_MOVE_R_MIN       EQU 0F2D8h
EBUZ2_MOVE_RTRIP       EQU 0F2D9h
EBUZ2_SEQ_PTR          EQU 0F2DAh  ; 2 bytes
EBUZ2_SEQ_TIMER        EQU 0F2DCh
EBUZ2_LASER_ACT        EQU 0F2DDh
EBUZ2_LASER_ROW        EQU 0F2DEh
EBUZ2_LASER_UNIT       EQU 0F2DFh
EBUZ2_LASER_HOLD       EQU 0F2E0h
; round138follow-up3: EBUZ2_EXPL_TIMER(旧・撃破後の固定30tick待ち)は
; EBUZ_EXPL_QUEUE_COUNT==0待ちへ置き換えたため削除、0xF2E1は
; round138follow-up4のEBUZ2_POST_DEFEAT_WAITへ再利用。
EBUZ2_POST_DEFEAT_WAIT EQU 0F2E1h
EBUZ2_TMP_A            EQU 0F2E2h
EBUZ2_TMP_OFS          EQU 0F2E3h
EBUZ2_TMP_ADDR         EQU 0F2E4h  ; 2 bytes
EBUZ2_V1_STRUCT        EQU 0F2E6h  ; 5レーン x [ACT,COL] = 10 bytes (F2E6-F2EF)
EBUZ2_V2_COLS          EQU 0F2F0h  ; 4門 x 4スロット = 16 bytes (F2F0-F2FF)
EBUZ2_V2_ROWS          EQU 0F300h  ; 16 bytes (F300-F30F、V2_COLSと+16
                                    ; 固定オフセット規約 - 変更しないこと)
EBUZ2_V2_NEXT          EQU 0F310h  ; 4 bytes (F310-F313)
EBUZ2_DEFEATED         EQU 0F314h  ; 0=未撃破(未スポーンor戦闘中)/1=撃破済み
                                    ; (HPは初回未スポーン時も0のため、"未
                                    ; スポーン"と"撃破済み"の区別にHP単独
                                    ; では使えない - 専用フラグが必要)
EBUZ2_TMP_CNT          EQU 0F315h  ; round136(ROM圧縮): EBUZ2_DRAW_N_ROWS/
EBUZ2_TMP_W            EQU 0F316h  ; EBUZ2_ERASE_N_ROWS専用の残り行数/幅/列
EBUZ2_TMP_COL          EQU 0F317h  ; ワーク(旧・行ごとの展開コードを置換)
; round138follow-up5: 変形直後・ビーム発射後のループリセット直後で
; 共通して使う「20tick静止交互連射してから上下移動を開始する」ための
; 状態(STACKTOP=0F380hまで100byte超の余裕がある空き領域を使用)。
EBUZ2_MOVE_PENDING     EQU 0F318h  ; 1=静止連射中(移動未開始)、DELAYが0で移動開始
EBUZ2_MOVE_START_DELAY EQU 0F319h  ; 残りtick数

; round136(ROM圧縮、Ebuz Mk2用予算確保): 本体形状データ+レーザー
; タイルはStage2/Title共有バンク(Comb bank6、tools/bgm_data/
; bgm_bank_gen.pyのEBUZ2_MK2_CHARDATAエントリ、計227byte)へ移設し、
; Titleが起動時にここへ一括コピーする(BOSS_PATTERNS等と全く同じ
; 方式)。ROM上には二度と実体を持たず、Stage1側は下記EQUアドレスを
; 直接読むだけ(0xD0C0起点、tools/title_screen/title_test.asm
; INIT_BGMのLDIR先と一致させること)。
;
; round138(実機フィードバック対応、"ブランクが地形のデータに化けてる"):
; 移植元tools/ebuz_mk2_test/ebuz_mk2_test.asm(スタンドアロンのテスト
; ROM)では本体形状データの「空白セル」を生値0で表していたが、Stage1
; ではパターンコード0は空白ではなく(BIOSのデフォルトフォント由来と
; 思われる)実グラフィックが残っており、Stage1全体で「空のセル」を
; 表す唯一の正しい規約はBLANKCODE(=48、行1の定義参照、row0-19の
; 空模様(sky)全体がこのコードで塗られている)。移植時にこの規約差を
; 見落とし0のまま持ち込んだ結果、Mk2本体の隙間セル・BLANK5/BLANK6
; (消去用)がことごとくコード0(=非空白の残留グラフィック、色は白/
; 濃紺で見た目は不規則な斑模様)を書き込んでしまい、「本体の隙間や
; 消去跡がまだら状の異物に化けて見える」実機バグになっていた。
; tools/bgm_data/bgm_bank.bin側でEBUZ2_MK2_CHARDATAの該当領域
; (EBUZ2_BLANK5〜EBUZ2_LASER_L_TILE直前、107byte)の値0を全てBLANKCODE
; (48)へ置換して解消(レーザータイル本体[EBUZ2_LASER_L/R_TILE、
; パターンジェネレータへ読み込むビットマップそのもの]は名前テーブル
; コードではないため対象外)。
EBUZ2_BLANK5                 EQU D0C0h
EBUZ2_BLANK6                 EQU D0C5h
EBUZ2_ROW_0                  EQU D0CBh
EBUZ2_ROW_1                  EQU D0D0h
EBUZ2_ROW_2                  EQU D0D5h
EBUZ2_ROW_3                  EQU D0DAh
EBUZ2_ROW_4                  EQU D0DFh
EBUZ2_ROW_S2_0               EQU D0E4h
EBUZ2_ROW_S2_1               EQU D0E9h
EBUZ2_ROW_S2_2               EQU D0EEh
EBUZ2_ROW_S2_3               EQU D0F3h
EBUZ2_ROW_S2_4               EQU D0F8h
EBUZ2_ROW_S2_5               EQU D0FDh
EBUZ2_ROW_S2_6               EQU D102h
EBUZ2_ROW_S2_OUTER_REST      EQU D107h
EBUZ2_ROW_S2_OUTER_RECOIL    EQU D10Dh
EBUZ2_ROW_S2_INNER_REST      EQU D113h
EBUZ2_ROW_S2_INNER_RECOIL    EQU D119h
EBUZ2_ROW_S2_CENTER_REST     EQU D11Fh
EBUZ2_ROW_S2_CENTER_RECOIL   EQU D125h
EBUZ2_LASER_L_TILE           EQU D12Bh
EBUZ2_LASER_R_TILE           EQU D133h
EBUZ2_LASER_COLOR_BYTE       EQU D13Bh

; ----------------------------------------------------------------------
; 汎用アドレス計算: A=row(0-23), C=col(0-31) -> HL=VRAMアドレス。
; 無印EbuzのEBUZ_CELL_ADDR(出力DE)をHLへ持ち替えるだけの薄いラッパー
; (EBUZ_WRITE2/LDIRVMがHLを取るため)。Trashes A,D,E,H,L.
; ----------------------------------------------------------------------
EBUZ2_ADDR:
    CALL EBUZ_CELL_ADDR
    LD D,H : LD E,L
    RET

; round136(ROM圧縮、"3KBも使ってんのか"を踏まえた追加圧縮): 旧DRAW_
; BODY_AT等4ルーチン(行ごとに全展開、計448byte)を、行データポインタ表
; (EBUZ2_BODY_TABLE/EBUZ2_S2_BODY_TABLE)+汎用ループ2本へ置換。挙動は
; 完全に同一(1行ずつEBUZ_CELL_ADDRで宛先計算→LDIRVM)、列(23 or
; リコイル用24)はEBUZ2_TMP_COL経由で呼び出し側が指定する。
; ----------------------------------------------------------------------
; IN: A=row_top, HL=行データポインタ表(DW×B個), B=行数, C=1行のbyte幅。
; EBUZ2_TMP_COLは呼び出し側が先に設定しておくこと。
EBUZ2_DRAW_N_ROWS:
    LD (EBUZ2_TMP_A),A
    LD (EBUZ2_TMP_ADDR),HL
    LD A,B : LD (EBUZ2_TMP_CNT),A
    LD A,C : LD (EBUZ2_TMP_W),A
EBUZ2_DNR_LOOP:
    LD HL,(EBUZ2_TMP_ADDR)
    LD E,(HL) : INC HL : LD D,(HL) : INC HL
    LD (EBUZ2_TMP_ADDR),HL
    PUSH DE
    LD A,(EBUZ2_TMP_COL) : LD C,A
    LD A,(EBUZ2_TMP_A)
    CALL EBUZ_CELL_ADDR
    LD D,H : LD E,L
    POP HL
    LD A,(EBUZ2_TMP_W) : LD C,A : LD B,0
    CALL LDIRVM
    LD A,(EBUZ2_TMP_A) : INC A : LD (EBUZ2_TMP_A),A
    LD A,(EBUZ2_TMP_CNT) : DEC A : LD (EBUZ2_TMP_CNT),A
    JR NZ,EBUZ2_DNR_LOOP
    RET

; round136(ROM圧縮): この4つのポインタ表(行データ表+"全行同じ場所を
; 指す"消去用ダミー表、EBUZ2_ERASE_N_ROWS撤去の代替)も、参照先の行
; データ本体と一緒にEBUZ2_MK2_CHARDATA(Comb bank6経由でRAMへ事前
; コピー)へ移設済み。ROM上には実体を持たない。
EBUZ2_BODY_TABLE     EQU D173h
EBUZ2_S2_BODY_TABLE  EQU D17Dh
EBUZ2_BLANK5_TABLE   EQU D18Bh
EBUZ2_BLANK6_TABLE   EQU D195h

; ----------------------------------------------------------------------
; 本体形状の描画/消去(閉状態5行/開状態7行、col23起点)。IN: A=row_top。
; ----------------------------------------------------------------------
EBUZ2_DRAW_BODY_AT:
    PUSH AF : LD A,23 : LD (EBUZ2_TMP_COL),A : POP AF
    LD HL,EBUZ2_BODY_TABLE : LD B,5 : LD C,5
    JP EBUZ2_DRAW_N_ROWS

EBUZ2_ERASE_BODY_AT:
    PUSH AF : LD A,23 : LD (EBUZ2_TMP_COL),A : POP AF
    LD HL,EBUZ2_BLANK5_TABLE : LD B,5 : LD C,5
    JP EBUZ2_DRAW_N_ROWS

EBUZ2_DRAW_S2_BODY_AT:
    PUSH AF : LD A,23 : LD (EBUZ2_TMP_COL),A : POP AF
    LD HL,EBUZ2_S2_BODY_TABLE : LD B,7 : LD C,5
    JP EBUZ2_DRAW_N_ROWS

EBUZ2_ERASE_S2_BODY_AT:
    PUSH AF : LD A,23 : LD (EBUZ2_TMP_COL),A : POP AF
    LD HL,EBUZ2_BLANK6_TABLE : LD B,7 : LD C,6
    JP EBUZ2_DRAW_N_ROWS

; 単一行6byte(col23-28)の描画: IN: A=row, HL=ソースデータ(6byte)。
; リコイル(外側/内側/中央ペアの1セル右シフト)で共用。
EBUZ2_DRAW_ROW6_AT:
    PUSH HL
    LD C,23 : CALL EBUZ2_ADDR
    LD D,H : LD E,L
    POP HL
    LD BC,6
    CALL LDIRVM
    RET

; ----------------------------------------------------------------------
; リコイル(内側/外側/中央ペア、無印Ebuzの反動と同じ「1セル右へずらし
; てから戻す」)。内側=ROW_CUR+1(IT)/+5(IB)、外側=ROW_CUR+0(OT)/+6(OB)、
; 中央=ROW_CUR+3。内側/外側のSHIFTは移動を一時停止(REST側で復帰)、
; 中央は無制限交互連射停止後[移動も既に停止済み]専用のため不要。
; ----------------------------------------------------------------------
EBUZ2_RECOIL_INNER_SHIFT:
    XOR A : LD (EBUZ2_MOVE_ACTIVE),A
    LD A,(EBUZ2_ROW_CUR) : ADD A,1
    LD HL,EBUZ2_ROW_S2_INNER_RECOIL : CALL EBUZ2_DRAW_ROW6_AT
    LD A,(EBUZ2_ROW_CUR) : ADD A,5
    LD HL,EBUZ2_ROW_S2_INNER_RECOIL : CALL EBUZ2_DRAW_ROW6_AT
    RET
EBUZ2_RECOIL_INNER_REST:
    LD A,(EBUZ2_ROW_CUR) : ADD A,1
    LD HL,EBUZ2_ROW_S2_INNER_REST : CALL EBUZ2_DRAW_ROW6_AT
    LD A,(EBUZ2_ROW_CUR) : ADD A,5
    LD HL,EBUZ2_ROW_S2_INNER_REST : CALL EBUZ2_DRAW_ROW6_AT
    JP EBUZ2_RESTORE_MOVE_ACTIVE
EBUZ2_RECOIL_OUTER_SHIFT:
    XOR A : LD (EBUZ2_MOVE_ACTIVE),A
    LD A,(EBUZ2_ROW_CUR)
    LD HL,EBUZ2_ROW_S2_OUTER_RECOIL : CALL EBUZ2_DRAW_ROW6_AT
    LD A,(EBUZ2_ROW_CUR) : ADD A,6
    LD HL,EBUZ2_ROW_S2_OUTER_RECOIL : CALL EBUZ2_DRAW_ROW6_AT
    RET
; (2026-09-23、メインループ監査): どこからも参照されていなかった
; EBUZ2_RECOIL_OUTER_REST(19byte)を削除。
EBUZ2_RECOIL_CENTER_SHIFT:
    LD A,(EBUZ2_ROW_CUR) : ADD A,3
    LD HL,EBUZ2_ROW_S2_CENTER_RECOIL : JP EBUZ2_DRAW_ROW6_AT
EBUZ2_RECOIL_CENTER_REST:
    LD A,(EBUZ2_ROW_CUR) : ADD A,3
    LD HL,EBUZ2_ROW_S2_CENTER_REST : JP EBUZ2_DRAW_ROW6_AT

; リコイル演出中に一時停止していた上下移動を復帰する。ただし既に1周
; 完了(EBUZ2_MOVE_RTRIP=1)している場合は再起動しない。また
; round138follow-up5: EBUZ2_MOVE_PENDING=1(20tick静止連射待ち中)の
; 間はまだ移動を再開してはならない - これが無いとEBUZ2_ACT_LOOP_RESET
; がMOVE_RTRIPを0クリアした直後の次のリコイル休止サイクルでここが
; 即座にMOVE_ACTIVEを1に戻してしまい、20tick待ちが素通りされる。
EBUZ2_RESTORE_MOVE_ACTIVE:
    LD A,(EBUZ2_MOVE_PENDING)
    OR A
    RET NZ
    LD A,(EBUZ2_MOVE_RTRIP)
    OR A
    RET NZ
    LD A,1
    LD (EBUZ2_MOVE_ACTIVE),A
    RET

; ----------------------------------------------------------------------
; 閉状態一斉発射(volley1)のリコイル(5行まとめて1セル右へ、col24)。
; EBUZ2_DRAW_N_ROWS/EBUZ2_ERASE_N_ROWSをcol=24・row=ENTRY_TARGET_ROW
; 固定で再利用(round136、旧DRAW_ROW5_AT24+5行展開を置換)。
; ----------------------------------------------------------------------
EBUZ2_RECOIL_CLOSED_SHIFT:
    LD A,EBUZ2_ENTRY_TARGET_ROW
    CALL EBUZ2_ERASE_BODY_AT
    LD A,24 : LD (EBUZ2_TMP_COL),A
    LD A,EBUZ2_ENTRY_TARGET_ROW
    LD HL,EBUZ2_BODY_TABLE : LD B,5 : LD C,5
    JP EBUZ2_DRAW_N_ROWS
EBUZ2_RECOIL_CLOSED_REST:
    LD A,24 : LD (EBUZ2_TMP_COL),A
    LD A,EBUZ2_ENTRY_TARGET_ROW
    LD HL,EBUZ2_BLANK5_TABLE : LD B,5 : LD C,5
    CALL EBUZ2_DRAW_N_ROWS
    LD A,EBUZ2_ENTRY_TARGET_ROW
    JP EBUZ2_DRAW_BODY_AT

; ----------------------------------------------------------------------
; 変形: 閉状態(row=ENTRY_TARGET_ROW)を消去し、開状態(row=S2_ROW_TOP)を
; 描画してEBUZ2_ROW_CURを確定させる。
; ----------------------------------------------------------------------
EBUZ2_TRANSFORM:
    LD A,EBUZ2_ENTRY_TARGET_ROW
    CALL EBUZ2_ERASE_BODY_AT
    LD A,EBUZ2_S2_ROW_TOP
    LD (EBUZ2_ROW_CUR),A
    JP EBUZ2_DRAW_S2_BODY_AT

; ----------------------------------------------------------------------
; round138follow-up5: 上下移動を開始する前の「20tick静止交互連射」
; 待ち(EBUZ2_MOVE_PENDING=1の間)を消化する。EBUZ2_UPDATE_MOVEは
; UPDATE_EBUZ2_ALLから毎frame無条件に呼ばれているため、ここで
; カウントダウンし0に達したら実際にEBUZ2_MOVE_ACTIVEを立てて上下移動を
; 開始する(この間もALTLOOP_TABLE自体は独立してEBUZ2_SEQ_TICK経由で
; 進行し続けるため、交互連射は普通に続く - 動くのを遅らせるだけ)。
; ----------------------------------------------------------------------
EBUZ2_CHECK_MOVE_PENDING:
    LD A,(EBUZ2_MOVE_PENDING)
    OR A
    RET Z
    LD A,(EBUZ2_MOVE_START_DELAY)
    DEC A
    LD (EBUZ2_MOVE_START_DELAY),A
    RET NZ
    XOR A
    LD (EBUZ2_MOVE_PENDING),A
    LD (EBUZ2_MOVE_DIR),A
    LD A,EBUZ2_MOVE_INTERVAL_TICKS
    LD (EBUZ2_MOVE_COUNTDOWN),A
    LD A,1
    LD (EBUZ2_MOVE_ACTIVE),A
    RET

; ----------------------------------------------------------------------
; 上下移動(EBUZ2_MOVE_ACTIVE=1の間、毎tick呼ぶ)。中央出発→下端→
; 上端→中央到達で1周完了・自動停止(無印Ebuz Mk2テストROMと同一仕様)。
; ----------------------------------------------------------------------
EBUZ2_UPDATE_MOVE:
    CALL EBUZ2_CHECK_MOVE_PENDING
    LD A,(EBUZ2_MOVE_ACTIVE)
    OR A
    RET Z
    LD A,(EBUZ2_MOVE_COUNTDOWN)
    DEC A
    LD (EBUZ2_MOVE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ2_MOVE_INTERVAL_TICKS
    LD (EBUZ2_MOVE_COUNTDOWN),A
    LD A,(EBUZ2_ROW_CUR)
    CALL EBUZ2_ERASE_S2_BODY_AT
    LD A,(EBUZ2_MOVE_DIR)
    OR A
    JR Z,EBUZ2_UM_DOWN
    LD A,(EBUZ2_ROW_CUR) : DEC A
    LD (EBUZ2_ROW_CUR),A
    CP EBUZ2_MOVE_MIN_ROW
    JR NZ,EBUZ2_UM_DRAW
    LD A,1 : LD (EBUZ2_MOVE_R_MIN),A
    XOR A : LD (EBUZ2_MOVE_DIR),A
    JR EBUZ2_UM_DRAW
EBUZ2_UM_DOWN:
    LD A,(EBUZ2_ROW_CUR) : INC A
    LD (EBUZ2_ROW_CUR),A
    LD B,A
    LD A,(EBUZ2_MOVE_R_MIN)
    OR A
    JR Z,EBUZ2_UM_MAXCHECK
    LD A,B
    CP EBUZ2_S2_ROW_TOP
    JR NZ,EBUZ2_UM_DRAW
    LD A,1 : LD (EBUZ2_MOVE_RTRIP),A
    XOR A : LD (EBUZ2_MOVE_ACTIVE),A
    JR EBUZ2_UM_DRAW
EBUZ2_UM_MAXCHECK:
    LD A,B
    CP EBUZ2_MOVE_MAX_ROW
    JR NZ,EBUZ2_UM_DRAW
    LD A,1
    LD (EBUZ2_MOVE_DIR),A
    LD (EBUZ2_MOVE_R_MAX),A
EBUZ2_UM_DRAW:
    LD A,(EBUZ2_ROW_CUR)
    JP EBUZ2_DRAW_S2_BODY_AT

; ----------------------------------------------------------------------
; レーザー(中央、1周ごとに発射)。発射時に列1-22を一括描画、発射位置側
; (col21-22)から順に1tick1ユニット(2列)ずつ消去する。
; ----------------------------------------------------------------------
EBUZ2_FIRE_LASER:
    LD A,(EBUZ2_ROW_CUR) : ADD A,3
    LD (EBUZ2_LASER_ROW),A
    LD B,A
    LD C,1
EBUZ2_FL_LOOP:
    PUSH BC
    LD A,B : LD C,C
    CALL EBUZ2_ADDR
    LD B,EBUZ2_LASER_L_CODE : LD C,EBUZ2_LASER_R_CODE
    CALL EBUZ_WRITE2
    POP BC
    LD A,C : ADD A,2 : LD C,A
    CP 23
    JR NZ,EBUZ2_FL_LOOP
    LD A,10 : LD (EBUZ2_LASER_UNIT),A
    LD A,EBUZ2_LASER_HOLD_TICKS : LD (EBUZ2_LASER_HOLD),A
    LD A,1 : LD (EBUZ2_LASER_ACT),A
    RET

EBUZ2_UPDATE_LASER:
    LD A,(EBUZ2_LASER_ACT)
    OR A
    RET Z
    LD A,(EBUZ2_LASER_HOLD)
    OR A
    JR Z,EBUZ2_UL_RETRACT
    DEC A
    LD (EBUZ2_LASER_HOLD),A
    RET
EBUZ2_UL_RETRACT:
    LD A,(EBUZ2_LASER_UNIT)
    ADD A,A : ADD A,1 : LD C,A
    LD A,(EBUZ2_LASER_ROW) : LD B,A
    CALL EBUZ2_ADDR
    ; round138 follow-up2(実機フィードバック対応、"ちゃんとやれよ"):
    ; 移植元テストROMは"消去=生値0"だったが、Stage1ではパターンコード0は
    ; 空白ではなく非空白の残留グラフィックが残っている(BLANK5/6と同じ
    ; 規約違反、こちらはBGM共有バンクのデータではなくコード自体に直接
    ; 埋め込まれていたため前回のBLANKCODE修正で見落としていた)。1フレーム
    ; ごとに弾/レーザーが通過した跡のセルへ非空白なコード0を書き込み
    ; 続けるため、画面上に消えない残留物が延々と蓄積していた -
    ; 「タン色の横棒が変わらず残る」の真因。BLANKCODEへ修正。
    LD B,BLANKCODE : LD C,BLANKCODE
    CALL EBUZ_WRITE2
    LD A,(EBUZ2_LASER_UNIT)
    OR A
    JR Z,EBUZ2_UL_DONE
    DEC A
    LD (EBUZ2_LASER_UNIT),A
    RET
EBUZ2_UL_DONE:
    XOR A
    LD (EBUZ2_LASER_ACT),A
    RET

; ----------------------------------------------------------------------
; volley1(閉状態5門、単発のみ・回転プール不要 - このシーケンス中
; 一度しか発射しないため)。EBUZ2_V1_STRUCT: 5レーン x [ACT,COL]。
; row baseはEBUZ_CELL_ADDR経由で都度計算(コンパイル時定数不要)。
; ----------------------------------------------------------------------
; round136(ROM圧縮): EBUZ2_V1_ROWBASE(旧:テーブル)は"ENTRY_TARGET_ROW+
; lane"という単純な線形加算なので、各参照箇所で"ADD A,EBUZ2_ENTRY_
; TARGET_ROW"へ置換しテーブル自体を廃止(3箇所の参照コードも同時に圧縮)。
EBUZ2_V1_FIRECOL EQU D13Ch  ; RAM移設済み(EBUZ2_MK2_CHARDATA)

EBUZ2_FIRE_ALL_V1:
    XOR A
EBUZ2_FAV1_LOOP:
    PUSH AF
    LD (EBUZ2_TMP_A),A                ; lane number (0-4)
    ; round138follow-up5("初弾はセンター無しで4発に"): lane2(中央、
    ; ENTRY_TARGET_ROW+2)は発射しない - V1_STRUCT[2].ACTは0のまま
    ; (TRIGGER_EBUZ2_ENCOUNTERの一括ゼロクリアで既に0)なので
    ; EBUZ2_UPDATE_V1_ONEも自然にこのレーンを無視する。
    CP 2
    JR Z,EBUZ2_FAV1_SKIP
    LD D,0 : LD E,A
    LD HL,EBUZ2_V1_FIRECOL : ADD HL,DE
    LD A,(HL) : LD (EBUZ2_TMP_OFS),A   ; this lane's fire col
    LD A,(EBUZ2_TMP_A) : ADD A,A       ; round136バグ修正: V1_STRUCTは
    LD H,0 : LD L,A                    ; [ACT,COL]の2byteペア×5レーン
    LD DE,EBUZ2_V1_STRUCT : ADD HL,DE  ; なのでlane*2でなければならない
    LD (HL),1                          ; (旧コードはlaneをそのまま使い
    INC HL                             ; レーン3/4が永久に更新されない
    LD A,(EBUZ2_TMP_OFS)               ; バグになっていた)
    LD (HL),A
    LD A,(EBUZ2_TMP_A)
    ADD A,EBUZ2_ENTRY_TARGET_ROW
    LD B,A
    LD A,(EBUZ2_TMP_OFS)
    LD C,A
    LD A,B
    CALL EBUZ2_ADDR
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
EBUZ2_FAV1_SKIP:
    POP AF
    INC A
    LD (EBUZ2_TMP_A),A
    CP 5
    JP NZ,EBUZ2_FAV1_LOOP
    RET

; 各レーン(0-4)の更新: EBUZ2_V1_STRUCT[lane*2]=ACT、+1=COL。
; 行はEBUZ2_V1_ROWBASE[lane](固定)。IN: A=lane(0-4)。
EBUZ2_UPDATE_V1_ONE:
    LD (EBUZ2_TMP_A),A
    ADD A,A
    LD H,0 : LD L,A
    LD DE,EBUZ2_V1_STRUCT : ADD HL,DE
    LD A,(HL)
    OR A
    RET Z
    INC HL
    LD C,(HL)                        ; C=col
    PUSH HL
    LD A,(EBUZ2_TMP_A)
    ADD A,EBUZ2_ENTRY_TARGET_ROW       ; A=row
    CALL EBUZ2_ADDR
    ; round138 follow-up2: 消去はBLANKCODE規約(上のLASER_RETRACTと同じ理由)
    LD B,BLANKCODE : LD C,BLANKCODE
    CALL EBUZ_WRITE2
    POP HL                              ; HL=&COL
    LD A,(HL)
    OR A
    JR Z,EBUZ2_UV1O_OFF
    DEC A
    LD (HL),A
    LD C,A
    PUSH HL
    LD A,(EBUZ2_TMP_A)
    ADD A,EBUZ2_ENTRY_TARGET_ROW
    CALL EBUZ2_ADDR
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    POP HL
    RET
EBUZ2_UV1O_OFF:
    DEC HL
    LD (HL),0
    RET

EBUZ2_UPDATE_V1_ALL:
    XOR A
EBUZ2_UV1_LOOP:
    PUSH AF
    CALL EBUZ2_UPDATE_V1_ONE
    POP AF
    INC A
    CP 5
    JR NZ,EBUZ2_UV1_LOOP
    RET

; ----------------------------------------------------------------------
; volley2以降の4門(外側上/内側上/内側下/外側下、無印Ebuzの上下2門を
; 内外2ペア4門へ拡張)。各門4スロットの回転プール、行オフセットと
; 発射列はポート別テーブル参照。
; port0=OT(行+0,外側列) port1=IT(行+1,内側列)
; port2=IB(行+5,内側列) port3=OB(行+6,外側列)
; ----------------------------------------------------------------------
EBUZ2_V2_ROWOFS   EQU 0D141h  ; RAM移設済み(EBUZ2_MK2_CHARDATA)
EBUZ2_V2_FIRECOL  EQU 0D145h  ; RAM移設済み(EBUZ2_MK2_CHARDATA)

; IN: A=port(0-3)。
EBUZ2_FIRE_V2_PORT:
    LD (EBUZ2_TMP_A),A
    LD H,0 : LD L,A
    LD DE,EBUZ2_V2_NEXT : ADD HL,DE
    LD A,(HL) : LD B,A
    INC A : CP EBUZ2_V2_SLOT_COUNT : JR C,EBUZ2_FV2_OK
    XOR A
EBUZ2_FV2_OK:
    LD (HL),A
    LD A,(EBUZ2_TMP_A)
    ADD A,A : ADD A,A : LD C,A       ; port*4
    LD A,B : ADD A,C : LD (EBUZ2_TMP_OFS),A  ; ofs = port*4+slot
    LD A,(EBUZ2_TMP_A)
    LD H,0 : LD L,A
    LD DE,EBUZ2_V2_FIRECOL : ADD HL,DE
    LD A,(HL) : LD C,A
    LD A,(EBUZ2_TMP_OFS)
    LD H,0 : LD L,A
    LD DE,EBUZ2_V2_COLS : ADD HL,DE
    LD (HL),C
    LD A,(EBUZ2_TMP_A)
    LD H,0 : LD L,A
    LD DE,EBUZ2_V2_ROWOFS : ADD HL,DE
    LD A,(HL) : LD B,A
    LD A,(EBUZ2_ROW_CUR) : ADD A,B : LD B,A
    PUSH BC
    LD A,(EBUZ2_TMP_OFS)
    LD H,0 : LD L,A
    LD DE,EBUZ2_V2_ROWS : ADD HL,DE
    POP BC
    LD (HL),B
    LD A,B
    CALL EBUZ2_ADDR
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET

EBUZ2_FIRE_INNER_PAIR:
    LD A,1 : CALL EBUZ2_FIRE_V2_PORT
    LD A,2 : CALL EBUZ2_FIRE_V2_PORT
    JP SOUND_EBUZ_FIRE
EBUZ2_FIRE_OUTER_PAIR:
    LD A,0 : CALL EBUZ2_FIRE_V2_PORT
    LD A,3 : CALL EBUZ2_FIRE_V2_PORT
    JP SOUND_EBUZ_FIRE
EBUZ2_FIRE_INNER_PAIR_AND_SHIFT:
    CALL EBUZ2_FIRE_INNER_PAIR
    JP EBUZ2_RECOIL_INNER_SHIFT
EBUZ2_FIRE_OUTER_PAIR_AND_SHIFT:
    CALL EBUZ2_FIRE_OUTER_PAIR
    JP EBUZ2_RECOIL_OUTER_SHIFT

; IN: HL=&COLS[ofs]. 対応するROWSは&COLS[ofs+16](EBUZ2_V2_ROWS =
; EBUZ2_V2_COLS+16の規約 - 変更しないこと)。
EBUZ2_UPDATE_V2_SLOT:
    LD A,(HL)
    CP EBUZ2_SLOT_EMPTY
    RET Z
    PUSH HL
    PUSH AF
    LD DE,16 : ADD HL,DE
    LD A,(HL)
    LD C,0
    CALL EBUZ2_ADDR
    LD (EBUZ2_TMP_ADDR),HL
    POP AF
    PUSH AF
    LD E,A : LD D,0
    LD HL,(EBUZ2_TMP_ADDR)
    ADD HL,DE
    ; round138 follow-up2: 消去はBLANKCODE規約(上のLASER_RETRACTと同じ理由)
    LD B,BLANKCODE : LD C,BLANKCODE
    CALL EBUZ_WRITE2
    POP AF
    OR A
    JR Z,EBUZ2_UV2S_OFF
    DEC A
    POP HL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,(EBUZ2_TMP_ADDR)
    ADD HL,DE
    LD B,EBUZ_BULLET_L_CODE : LD C,EBUZ_BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET
EBUZ2_UV2S_OFF:
    POP HL
    LD (HL),EBUZ2_SLOT_EMPTY
    RET

EBUZ2_UPDATE_V2_ALL:
    LD HL,EBUZ2_V2_COLS
    LD B,16
EBUZ2_UV2_LOOP:
    PUSH BC
    PUSH HL
    CALL EBUZ2_UPDATE_V2_SLOT
    POP HL
    INC HL
    POP BC
    DJNZ EBUZ2_UV2_LOOP
    RET

; ----------------------------------------------------------------------
; テーブル駆動シーケンスエンジン(1行=[DW action, DB wait])。
; EBUZ2_SEQ_TICKが毎frame呼ばれ、タイマーが尽きたら次の行のactionを
; CALLしてから新しいwaitをセットする。JP (HL)経由の間接CALL。
; ----------------------------------------------------------------------
EBUZ2_CALL_HL:
    JP (HL)

EBUZ2_SEQ_ADVANCE:
    LD HL,(EBUZ2_SEQ_PTR)
    LD E,(HL) : INC HL : LD D,(HL) : INC HL
    LD A,(HL) : INC HL
    LD (EBUZ2_SEQ_PTR),HL
    LD (EBUZ2_SEQ_TIMER),A
    LD H,D : LD L,E
    CALL EBUZ2_CALL_HL
    RET

EBUZ2_SEQ_TICK:
    LD A,(EBUZ2_SEQ_TIMER)
    OR A
    JP Z,EBUZ2_SEQ_ADVANCE
    DEC A
    LD (EBUZ2_SEQ_TIMER),A
    RET

; (2026-09-23、メインループ監査): 未参照のEBUZ2_ACT_NOP(1byte)を削除。

; --- テーブル本体(round136、ROM圧縮のためRAM移設済み-
; EBUZ2_MK2_CHARDATA、内容は[DW action_addr:DB wait]×7行、実データは
; tools/bgm_data/bgm_bank_gen.py参照) ---
EBUZ2_SCRIPT_TABLE EQU D149h
; ここから先はEBUZ2_ACT_START_MOVEMENTがEBUZ2_ALTLOOP_TABLEへ
; ポインタを差し替えるため、これ以降の行は到達しない。

; 「では次に外側ペア発射→無制限交互ループへ」の橋渡し(volley2の
; 外側ペアはaltループと共有しない専用発射、そのあとaltloopへ)。
; round138follow-up5: 変形直後は即座に交互連射(ALTLOOP)へ入るが、
; 上下移動はEBUZ2_STATIC_FIRE_TICKS(20)静止連射してから開始する
; (EBUZ2_MOVE_ACTIVEを直接立てず、EBUZ2_MOVE_PENDING経由でEBUZ2_
; CHECK_MOVE_PENDINGに委譲)。
EBUZ2_ACT_START_MOVEMENT:
    CALL EBUZ2_FIRE_OUTER_PAIR
    XOR A
    LD (EBUZ2_MOVE_ACTIVE),A
    LD A,EBUZ2_STATIC_FIRE_TICKS
    LD (EBUZ2_MOVE_START_DELAY),A
    LD A,1
    LD (EBUZ2_MOVE_PENDING),A
    LD HL,EBUZ2_ALTLOOP_TABLE
    LD (EBUZ2_SEQ_PTR),HL
    RET

EBUZ2_ALTLOOP_TABLE EQU D15Eh  ; RAM移設済み(EBUZ2_MK2_CHARDATA)

EBUZ2_ACT_ALT_TOP:
    LD A,(EBUZ2_MOVE_RTRIP)
    OR A
    JR Z,EBUZ2_ALT_CONTINUE
    LD HL,EBUZ2_STOPSEQ_TABLE
    LD (EBUZ2_SEQ_PTR),HL
    LD A,EBUZ2_LAP_STOP_HOLD_TICKS
    LD (EBUZ2_SEQ_TIMER),A
    RET
EBUZ2_ALT_CONTINUE:
    JP EBUZ2_FIRE_INNER_PAIR_AND_SHIFT

EBUZ2_ACT_ALT_LOOP_BACK:
    LD HL,EBUZ2_ALTLOOP_TABLE
    LD (EBUZ2_SEQ_PTR),HL
    RET

EBUZ2_STOPSEQ_TABLE EQU D16Ah  ; RAM移設済み(EBUZ2_MK2_CHARDATA)

EBUZ2_FIRE_LASER_AND_SHIFT:
    CALL EBUZ2_FIRE_LASER
    CALL SOUND_EBUZ_FIRE
    JP EBUZ2_RECOIL_CENTER_SHIFT

; round138follow-up5("ビーム発射後は20Tick静止連射してからまた下に
; 動く"): ここも即座にEBUZ2_MOVE_ACTIVEを立てず、ACT_START_MOVEMENTと
; 同じ「20tick静止連射してから移動開始」をEBUZ2_MOVE_PENDING経由で
; 委譲する(交互連射自体はEBUZ2_ALTLOOP_TABLEへ切替済みなので即座に
; 再開する)。
EBUZ2_ACT_LOOP_RESET:
    XOR A
    LD (EBUZ2_MOVE_DIR),A
    LD (EBUZ2_MOVE_R_MAX),A
    LD (EBUZ2_MOVE_R_MIN),A
    LD (EBUZ2_MOVE_RTRIP),A
    LD (EBUZ2_MOVE_ACTIVE),A
    LD A,EBUZ2_STATIC_FIRE_TICKS
    LD (EBUZ2_MOVE_START_DELAY),A
    LD A,1
    LD (EBUZ2_MOVE_PENDING),A
    LD HL,EBUZ2_ALTLOOP_TABLE
    LD (EBUZ2_SEQ_PTR),HL
    RET

; ----------------------------------------------------------------------
; 登場(閉状態、剛体のまま上からEBUZ2_ENTRY_TARGET_ROWへ並進移動)。
; PHASE=0の間、毎tick呼ばれる。到達したらvolley1斉射→PHASE=1へ。
; ----------------------------------------------------------------------
EBUZ2_UPDATE_ENTRY:
    LD A,(EBUZ2_ROW_CUR)
    CP EBUZ2_ENTRY_TARGET_ROW
    JP Z,EBUZ2_ENTER_SCRIPT
    LD A,(EBUZ2_MOVE_COUNTDOWN)
    DEC A
    LD (EBUZ2_MOVE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ2_ENTRY_HOLD_TICKS
    LD (EBUZ2_MOVE_COUNTDOWN),A
    LD A,(EBUZ2_ROW_CUR)
    CALL EBUZ2_ERASE_BODY_AT
    LD A,(EBUZ2_ROW_CUR) : INC A
    LD (EBUZ2_ROW_CUR),A
    JP EBUZ2_DRAW_BODY_AT

EBUZ2_ENTER_SCRIPT:
    CALL EBUZ2_FIRE_ALL_V1
    CALL SOUND_EBUZ_FIRE
    LD A,1
    LD (EBUZ2_PHASE),A
    LD HL,EBUZ2_SCRIPT_TABLE
    LD (EBUZ2_SEQ_PTR),HL
    LD A,EBUZ2_VOLLEY1_HOLD_TICKS
    LD (EBUZ2_SEQ_TIMER),A
    RET

; ----------------------------------------------------------------------
; round138follow-up3("Ebuziiの爆発処理、Ebuzと同じ"): 現在のS2本体
; (EBUZ2_ROW_CUR起点、col23、行データEBUZ2_S2_BODY_TABLE経由)の非空白
; セルを、無印EbuzのEBUZ_QUEUE_EXPLOSIONSと全く同じ仕組み(共有の
; EBUZ_EXPL_QUEUE/EBUZ_EXPL_ENQUEUE_CELL/EBUZ_EXPL_UPDATE_QUEUE、1個
; ポップごとにPLAYER_EXPL_POOLのバースト+SOUND_DESTROY)へそのまま積む -
; 専用の爆発演出コードを新設せず、無印Ebuzの既存インフラを流用するのみ
; (無印Ebuz自身のコードは無変更、Mk2生存中は無印Ebuzと共存しないため
; キューの奪い合いは起きない)。キュー容量(EBUZ_EXPL_QUEUE_CAPACITY=16)
; を超えるセルは無印Ebuzの他インスタンスと同じ規約で静かにdropされる。
; Trashes A,B,C,D,E,H,L.
; ----------------------------------------------------------------------
EBUZ2_QUEUE_EXPLOSIONS:
    LD A,(EBUZ2_ROW_CUR)
    LD (EBUZ2_TMP_A),A
    LD HL,EBUZ2_S2_BODY_TABLE
    LD B,7
EBUZ2_QE_ROW_LOOP:
    PUSH BC
    LD E,(HL) : INC HL : LD D,(HL) : INC HL
    PUSH HL
    LD H,D : LD L,E
    LD B,5
    LD C,23
EBUZ2_QE_COL_LOOP:
    LD A,(HL)
    CP BLANKCODE
    JR Z,EBUZ2_QE_SKIP
    PUSH HL : PUSH BC
    LD A,(EBUZ2_TMP_A) : LD D,A
    LD E,C
    CALL EBUZ_EXPL_ENQUEUE_CELL
    POP BC : POP HL
EBUZ2_QE_SKIP:
    INC HL : INC C
    DJNZ EBUZ2_QE_COL_LOOP
    POP HL
    LD A,(EBUZ2_TMP_A) : INC A : LD (EBUZ2_TMP_A),A
    POP BC
    DJNZ EBUZ2_QE_ROW_LOOP
    RET

; ----------------------------------------------------------------------
; 撃破演出(その場で消滅、本体セルごとの爆発バーストはEBUZ_EXPL_QUEUE
; 経由で無印Ebuzと共通の仕組みが毎フレーム自動的にポップし続ける -
; MAINLOOP末尾のCALL EBUZ_EXPL_UPDATE_QUEUEはEBUZ2の生死に関わらず
; 常時呼ばれている)。
; ----------------------------------------------------------------------
EBUZ2_TRIGGER_DEFEAT:
    LD A,2 : LD (EBUZ2_PHASE),A
    ; (2026-09-23、実機報告"倒す直前に中央のレーザーが発射されていると
    ; 爆発処理に即移行してレーザーが消えないまま"→"消去するのではなく本来の
    ; 処理で終了するように"): ここでEBUZ2_LASER_ACTを落とすと描画済みの
    ; レーザーを引っ込める処理が二度と走らない。撃破後もUPDATE_EBUZ2_ALLが
    ; 毎フレームEBUZ2_UPDATE_LASERを呼ぶので、レーザーは触らず本来の
    ; 保持→引っ込めで終わらせる(EBUZ2_UPDATE_DEFEATはその完了を待つ)。
    XOR A
    LD (EBUZ2_MOVE_ACTIVE),A
    LD A,(EBUZ2_ROW_CUR)
    CALL EBUZ2_ERASE_S2_BODY_AT
    CALL EBUZ2_QUEUE_EXPLOSIONS
    ; round138follow-up4("EbuzII撃破後50Tickウェイト追加"): 爆発が
    ; 全てポップし終わった後、実ボスへ引き継ぐ前に50tick静止させる。
    LD A,EBUZ2_POST_DEFEAT_WAIT_TICKS
    LD (EBUZ2_POST_DEFEAT_WAIT),A
    RET

; 無印EbuzのEBUZ_ANY_ACTIVEと同じ考え方: 爆発バーストが全てポップし
; 終わる(EBUZ_EXPL_QUEUE_COUNT=0)まで待ち、さらにEBUZ2_POST_DEFEAT_
; WAIT_TICKS(50)経過してから最終消滅させる。
EBUZ2_UPDATE_DEFEAT:
    LD A,(EBUZ_EXPL_QUEUE_COUNT)
    OR A
    RET NZ
    LD A,(EBUZ2_LASER_ACT)         ; 発射中のレーザーが本来の処理で引っ込み終わるまで待つ
    OR A                           ; (先にEBUZ2_ACTを落とすと更新が止まり取り残される)
    RET NZ
    LD A,(EBUZ2_POST_DEFEAT_WAIT)
    OR A
    JR Z,EBUZ2_DEFEAT_DONE
    DEC A
    LD (EBUZ2_POST_DEFEAT_WAIT),A
    RET
EBUZ2_DEFEAT_DONE:
    XOR A
    LD (EBUZ2_ACT),A
    LD A,1
    LD (EBUZ2_DEFEATED),A
    JP BOSS_SPAWN

; ----------------------------------------------------------------------
; トップレベル・ディスパッチ(MAINLOOPから毎frame無条件に呼ぶ、
; EBUZ2_ACT=0の間は即RET)。
; ----------------------------------------------------------------------
UPDATE_EBUZ2_ALL:
    LD A,(EBUZ2_ACT)
    OR A
    RET Z
    CALL EBUZ2_UPDATE_V1_ALL
    CALL EBUZ2_UPDATE_V2_ALL
    CALL EBUZ2_UPDATE_LASER
    LD A,(EBUZ2_PHASE)
    CP 2
    JP Z,EBUZ2_UPDATE_DEFEAT
    OR A
    JP Z,EBUZ2_UPDATE_ENTRY
    CALL EBUZ2_UPDATE_MOVE
    JP EBUZ2_SEQ_TICK

; ----------------------------------------------------------------------
; スポーン。ボスの直前(CHECK_BOSS_TRIGGER末尾のJP BOSS_SPAWN、後方で
; フックする)から一度だけ呼ばれる。
; ----------------------------------------------------------------------
TRIGGER_EBUZ2_ENCOUNTER:
    LD A,1 : LD (EBUZ2_ACT),A
    LD A,EBUZ2_HP_INIT : LD (EBUZ2_HP),A
    XOR A
    LD (EBUZ2_PHASE),A
    LD (EBUZ2_MOVE_DIR),A
    LD (EBUZ2_MOVE_ACTIVE),A
    LD (EBUZ2_MOVE_R_MAX),A
    LD (EBUZ2_MOVE_R_MIN),A
    LD (EBUZ2_MOVE_RTRIP),A
    LD (EBUZ2_LASER_ACT),A
    LD (EBUZ2_MOVE_PENDING),A
    ; round136(ROM圧縮): V1_STRUCT(10byte)+V2_COLS(16byte)+V2_ROWS
    ; (16byte、未使用)+V2_NEXT(4byte)は連続46byte(F2E6-F313)なので
    ; まとめて0で埋め(旧・個別9個のLD (addr),A展開を置換)、直後に
    ; V2_COLSだけSLOT_EMPTYで上書きする。
    LD HL,EBUZ2_V1_STRUCT : LD B,46
EBUZ2_TE_ZLOOP:
    LD (HL),A : INC HL : DJNZ EBUZ2_TE_ZLOOP
    LD A,EBUZ2_ENTRY_HOLD_TICKS
    LD (EBUZ2_MOVE_COUNTDOWN),A
    LD A,EBUZ2_SLOT_EMPTY
    LD HL,EBUZ2_V2_COLS : LD B,16
EBUZ2_TE_ELOOP:
    LD (HL),A : INC HL : DJNZ EBUZ2_TE_ELOOP
    LD A,EBUZ2_ENTRY_START_ROW
    LD (EBUZ2_ROW_CUR),A
    JP EBUZ2_DRAW_BODY_AT

; ----------------------------------------------------------------------
; 衝突判定。自機弾→Mk2(HPを減らす、CHECK_BULLET_VS_EBUZと同型)。
; Mk2本体→自機(既存PDC_CHECK_EBUZ系と同型、PLAYER_HIT_BOX_EBUZ/_1PX
; をそのまま再利用)。
; ----------------------------------------------------------------------
CHECK_BULLET_VS_EBUZ2:
    LD A,(EBUZ2_ACT)
    OR A
    JR Z,CBVE2_MISS
    LD A,(EBUZ2_PHASE)
    CP 2
    JR Z,CBVE2_MISS
    LD D,23
    LD A,B : SUB D
    CP 6
    JR NC,CBVE2_MISS
    LD A,(EBUZ2_ROW_CUR)
    LD D,A
    LD A,C : SUB D
    CP 7
    JR NC,CBVE2_MISS
    LD A,(EBUZ2_HP) : DEC A : LD (EBUZ2_HP),A
    JR NZ,CBVE2_DAMAGED
    CALL EBUZ2_TRIGGER_DEFEAT
    LD HL,50                     ; round141 follow-up: EbuzIIの撃破報酬を5000点に(50*100)
    CALL ADD_SCORE_COMMON
    LD A,1
    RET
CBVE2_DAMAGED:
    LD A,1
    RET
CBVE2_MISS:
    XOR A
    RET

PDC_CHECK_EBUZ2:
    LD A,(EBUZ2_ACT)
    OR A
    JR Z,EBUZ2_PDC_MISS
    LD A,(EBUZ2_PHASE)
    CP 2
    JR Z,EBUZ2_PDC_MISS
    LD A,(EBUZ2_ROW_CUR) : ADD A,A : ADD A,A : ADD A,A : LD E,A
    LD D,23*8
    LD B,55
    CALL PLAYER_HIT_BOX_EBUZ
    OR A
    JR NZ,EBUZ2_PDC_HIT
    ; round145("EbuzIIで敵の弾やビームにコリジョンがない"): 本体(上記)は
    ; 従来通り。volley1/volley2/レーザーは新規追加(PDC_CHECK_EBUZ2_
    ; PROJECTILES、ファイル末尾)。
    JP PDC_CHECK_EBUZ2_PROJECTILES
EBUZ2_PDC_HIT:
    LD A,1
    RET
EBUZ2_PDC_MISS:
    XOR A
    RET

; ----------------------------------------------------------------------
; CHECK_BOSS_TRIGGERの末尾から横取りする実スポーン起点。1回目の到達で
; Mk2をスポーンして実ボスは出さない。Mk2生存中は素通り(実ボスも
; スポーンしない、次フレームもCHECK_BOSS_TRIGGER自体がBOSS_STATE==0の
; 間毎フレーム呼び直すためこれで足りる)。実際の「Mk2撃破→実ボスへ」
; 遷移はEBUZ2_DEFEAT_DONEがBOSS_SPAWNを直接呼ぶため、ここでの
; EBUZ2_DEFEATEDチェックは通常到達しない防御的フォールバックに過ぎない
; (HP自体は初回未スポーン時も0のため、"未スポーン"と"撃破済み"の
; 区別に専用フラグEBUZ2_DEFEATEDが必要)。
; ----------------------------------------------------------------------
EBUZ2_ON_BOSS_TRIGGER:
    LD A,(EBUZ2_ACT)
    OR A
    RET NZ                       ; 既にスポーン済み・生存中 - 何もしない
    LD A,(EBUZ2_DEFEATED)
    OR A
    JP NZ,BOSS_SPAWN               ; 撃破済み(防御的フォールバック)
    JP TRIGGER_EBUZ2_ENCOUNTER     ; 初回到達 - Mk2をスポーン

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

; ---- (2026-09-23、ROM詰め直し) SOLOTABのページ残りへ末尾区間から移設 ----

; (2026-09-19、"あと圧縮はボスだけじゃなく全てのキャラデータだぞ"):
; PATTERNSはINIT時に1回だけLDIRVMされる純粋な静的パターンジェネレータ
; データ(以後CPUから直接読まれることは無い)のため、ボス本体データと
; 同じ自前RLEで圧縮。384byte->341byte(呼び出し1箇所分のオーバーヘッド
; を差し引いても実質+25byte節約)。以下はRLE圧縮済みバイト列 - 元の
; 生データの意味(codes0-7=mountain/8-15=diamond/16-23=slash/24=unused/
; 25-26=flowing cloud左右半分/27-31=unused/32-47=wedge)は無変更、
; 展開後のVRAM内容は圧縮前と完全に一致することをPython側でround-trip
; 検証済み(tools/内のスクラッチ検証、tools/verify_*.py群でも回帰
; テストを追加)。
; (2026-09-23、ROM詰め直し): 末尾区間を減らすため、ALIGN 256ページの空白へ
; 収まるよう展開前データ(384byte)を293byte目で2分割して各々RLE圧縮し直した
; (A=SOLOTABページの残り、B=MUL6ページの残りに配置)。INITは同じVRAMアドレス
; から続けて2回DECOMPRESS_RLE_TO_VRAMを呼ぶ(VDPアドレスは自動で進むので
; 展開結果は分割前と完全に同一)。
PATTERNS_A:
    DB 127,94,235,254,155,101,254,75,189,188,215,253,55,202,253,150
    DB 123,121,175,251,110,149,251,45,246,242,95,247,220,43,247,90
    DB 237,229,190,239,185,86,239,180,219,203,125,223,115,172,223,105
    DB 183,151,250,191,230,89,191,210,111,47,245,127,205,178,127,165
    DB 222,94,235,254,155,101,254,75,189,188,215,253,55,202,253,150
    DB 123,121,175,251,110,149,251,45,246,242,95,247,220,43,247,90
    DB 237,229,190,239,185,86,239,180,219,203,125,223,115,172,223,105
    DB 183,151,250,191,230,89,191,210,111,47,245,127,205,178,127,165
    DB 222,63,94,235,254,155,101,254,75,189,188,215,253,55,202,253
    DB 150,123,121,175,251,110,149,251,45,246,242,95,247,220,43,247
    DB 90,237,229,190,239,185,86,239,180,219,203,125,223,115,172,223
    DB 105,183,151,250,191,230,89,191,210,111,47,245,127,205,178,127
    DB 165,222,135,0,4,6,111,254,27,4,131,0,4,216,180,239
    DB 176,96,169,0,36,125,231,223,126,185,199,190,95,246,219,190
    DB 255,91,229,190,125,251,207,191,253,114,143,125,190,247,159,126
    DB 251,229,31,250,125,239,62,253,247,202
PATTERNS_A_SEGMENTS EQU 8
PATTERNS_LEN EQU 384

    ALIGN 256
; MUL6: base id (0-5) -> id*6. Optimization: avoids a previous
; 5x(LD/ADD/LD) repeated-addition chain used to multiply curr_id
; by 6 when computing the PAIRBASE index (curr*6+next). A single
; table lookup replaces roughly 15 instructions with 4 per cell.
MUL6:
    DB 0,6,12,18,24,30

; ---- (2026-09-23、ROM詰め直し) MUL6のページ残りへ末尾区間から移設 ----

; round142(ROM budget): PLAYER_PARTICLE_SPAWN/PLAYER_PARTICLE_FADE
; (called from PFA_MOVING/MAINLOOP, formerly right after PLAYER_DIR_
; ADJUST near the top of the file) relocated down here. Reason: the
; terrain LUT tables (REFRESH_IDCACHE_33's "ALIGN 256" right before
; LUT:) were sitting EXACTLY on a 256-byte boundary already (zero
; slack) - round142's bug fixes (retreat-target rewrite/fire gate
; PLAYER_RETREAT_ACT check/PSG DI-EI protection, all upstream of that
; ALIGN) pushed the file's byte count past it by only ~19 bytes, but
; because ALIGN always rounds up to the FULL next 256-byte boundary,
; even that tiny overage cost a full extra 256 bytes of padding -
; enough to blow the Comb build's 32768-byte budget (assemble_game()
; started raising "game byte at unexpected address c000"). Moving
; these two routines (pure CALL targets, so their physical position
; in the file has no functional effect) past ALL of this file's
; remaining ALIGN directives removes ~300 bytes from before that
; cliff, restoring comfortable slack without shrinking any of the
; actual bug-fix logic itself.
PLAYER_PARTICLE_SPAWN:
    LD A,(PARTICLE_SPAWN_COOLDOWN)
    OR A
    JR Z,PPS_COOLDOWN_OK
    DEC A : LD (PARTICLE_SPAWN_COOLDOWN),A
    RET
PPS_COOLDOWN_OK:
    LD B,PARTICLE_SLOTS
    LD HL,PARTICLE_ACT
PPS_FIND_SLOT:
    LD A,(HL)
    OR A
    JR Z,PPS_SLOT_FOUND
    INC HL
    DJNZ PPS_FIND_SLOT
    RET                          ; every slot busy this frame
PPS_SLOT_FOUND:
    LD A,PARTICLE_SLOTS : SUB B : LD C,A   ; C = slot index found
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

; SCREEN1 color table: 1 byte per 8 CONSECUTIVE character codes.
; Only groups 0,1,2,3,4,5 (codes 0-47) are meaningful here;
; groups 6-31 (codes 48-255, unused by this scroller) are filled
; with a harmless placeholder color.
COLORDATA:
    DB 0F4h    ; group0 codes  0- 7 mountain family (white/blue, cloud design)
    DB 0F4h    ; group1 codes  8-15 diamond family (white/blue, cloud design)
    DB 0F4h    ; group2 codes 16-23 slash family (white/blue, cloud design)
    DB 0F4h    ; group3 codes 24-31 backslash family (unused, matched anyway)
    DB 0F4h    ; group4 codes 32-39 wedge family (white/blue, cloud design)
    DB 0F4h    ; group5 codes 40-47 wedge family (white/blue, cloud design)
    DB 44h,0F4h,0D3h,0DFh,0DAh,0F4h,0FFh,0F3h,0FAh,084h  ; group6=BLANKCODE, group7=shot(2026-09-24から白/青、旧0D4h), group8=shot-green, group9=shot-white, group10=shot-brown, group11=anim1-blue(white/blue, DEBUG was yellow), group12=anim1-white(white/white, DEBUG), group13=anim1-green(white/lightgreen, DEBUG), group14=anim1-brown(white/brown, DEBUG), group15=anim2-blue(red/blue)
    DB 08Fh,083h,08Ah,0E4h,0E4h,0E8h,0F1h,0F1h,0E4h,0E4h  ; group16=anim2-white, group17=anim2-green, group18=anim2-brown, group19=enemy3-pat1(gray/blue), group20=enemy3-pat2(gray/blue), group21=enemy3-pat3(gray/red), group22=digits0-7(white/black), group23=digits8-9(white/black), group24=BOSS gray/blue, group25=BOSS gray/blue
    DB 0E4h,0E4h,014h,014h,014h,084h                       ; group26=BOSS gray/blue, group27=BOSS gray/blue, group28-30=BOSS black/blue, group31=BOSS red/blue
COLOR_LEN EQU 32

; round136(Ebuz Mk2用ROM予算確保、ユーザー指摘"まず地形データがかなり
; あるはず、これは開始前に基本パターンから生成可能"): ROWDATA0/2/3/5は
; いずれも同一文字の128byte単純反復(ROWDATA5のみ2文字交互)で、
; PXCHAR_G1/G2/G4/G8はAND 3Fhで0-63にしか動かず、REFRESH_IDCACHE_33の
; 33byte読み取り幅を足しても最大96byte分しか実際には参照されない
; (128byteの元サイズには32byteの余裕があった)。内容が固定パターン
; なのでROMにリテラルで128byte×4=512byte持つ必要はなく、RAM上に
; 同サイズのバッファを確保してINIT時に生成する(以後の参照コードは
; 完全に無変更、ROWDATA0等のラベルが指す先がROMからRAMに変わるだけ)。
; 配置先はBOSS_PATTERNS(0xCD8Dから290byte、Titleが起動時に埋める)の
; 直後の空きRAM(次の既知シンボルTICKが0xE000までのため大きな余裕あり、
; リテラル16進アドレス参照が無いことも横断検索で確認済み)。
ROWDATA0 EQU 0CEB0h  ; 128 bytes RAM(INITで'M'を充填)
ROWDATA2 EQU 0CF30h  ; 128 bytes RAM(INITで'D'を充填)
ROWDATA3 EQU 0CFB0h  ; 128 bytes RAM(INITで'S'を充填)
ROWDATA5 EQU 0D030h  ; 128 bytes RAM(INITで'A','B'交互に充填)
; PATTERNS_Aの続き(上のPATTERNS_Aのコメント参照)
PATTERNS_B:
    DB 90,63,245,251,223,125,251,239,149,126,235,247,190,251,247,223
    DB 43,252,215,239,125,246,239,191,86,249,175,223,251,237,223,127
    DB 173,242,95,190,236,183,125,254,183,203,125,250,217,111,251,253
    DB 110,151,250,245,179,223,246,251,221,46,245,234,103,190,237,247
    DB 187,92,235,213,207,124,219,239,119,184,215,171,159,249,183,223
    DB 238,113,175,87,62,243,111,191,220,227,95,175
PATTERNS_B_SEGMENTS EQU 1



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

; 16x16 sprite byte order in the pattern generator table (VRAM 3800h):
; [top-left 8x8][bottom-left 8x8][top-right 8x8][bottom-right 8x8].
; Ship body: see SHIP_MID_PATTERN/SHIP_UP_PATTERN/SHIP_DOWN_PATTERN
; below. Accent overlay (slot0, priority above the ship body in
; slot1, drawn at ship_X+8, ship_Y): see ACCENT_MID_PATTERN/
; ACCENT_DOWN_PATTERN right below.

; (2026-09-21、"急に始まるのでなく飛び込んでくる演出...ShipStart1の下に
; ShipStart2を重ねて"): 開始直後の飛び込み演出専用の2枚。ShipStart1
; (白、slot0/accent)・ShipStart2(赤、slot1/body)は既存のSPR_WHITE/
; SPR_RED描画コードと同じ色を使うため、色バイト自体は無変更(通常の
; body/accent描画ブロックをそのまま流用、PLAYER_SHIP_PAT/PLAYER_
; ACCENT_PATだけ一時的にこちらへ差し替える設計、下記SHIP_ENTRY_ACT
; 参照)。
SHIP_ENTRY_BODY_PATTERN:  ; ShipStart2 (fg=8=SPR_RED, bg=1)
    DB 0C0h,0F0h,0FEh,7Fh,0FFh,0FFh,0FFh,7Fh   ; top-left
    DB 0FFh,0FFh,0FFh,7Fh,0FEh,0F0h,0C0h,00h   ; bottom-left
    DB 00h,00h,00h,80h,0E0h,0F8h,0FEh,0FFh     ; top-right
    DB 0FEh,0F8h,0E0h,80h,00h,00h,00h,00h      ; bottom-right

; (2026-09-22follow-up、"ステージ1のスタート演出の自機のShipStart1を
; 添付ファイルに差し替え"): ShipStart1_16x16_1.jsonの内容へ差し替え。
SHIP_ENTRY_ACCENT_PATTERN:  ; ShipStart1 (fg=15=SPR_WHITE, bg=1)
    DB 00h,00h,00h,40h,0FEh,0A1h,0A0h,7Fh      ; top-left
    DB 0A0h,0A1h,0FEh,40h,00h,00h,00h,00h      ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,0B8h,7Ch        ; top-right
    DB 0B8h,00h,00h,00h,00h,00h,00h,00h        ; bottom-right

; Accent overlay animation, 2 frames (ShipMidW/ShipDownW from the
; Sprite Editor): MID shows with no vertical movement, DOWN shows
; while diving - no separate up-frame, climbing keeps MID. Picked
; alongside the ship body's own frame - see PLAYER_ACCENT_PAT.
ACCENT_MID_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 30h,08h,00h,00h,00h,00h,00h,00h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; bottom-right (blank)

ACCENT_DOWN_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 70h,38h,00h,00h,00h,00h,00h,00h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; bottom-right (blank)

; "装備中はどちらのパターンにも追加 / 右下の8x8ドットのエリアがバリア
; の絵だからそれを未提出のアクセントに追記" - the barrier glyph is just
; the bottom-right 8x8 quadrant of the uploaded Acsent_16x16.json (the
; rest of that 16x16 canvas was blank); added into the BR quadrant of
; BOTH accent poses (that quadrant was unused/blank in both originals),
; leaving TL/BL/TR exactly as ACCENT_MID_PATTERN/ACCENT_DOWN_PATTERN
; above. Selected instead of the plain accent while BARRIER_HP>0 - see
; PLAYER_ACCENT_PAT's selection logic.
ACCENT_MID_BARRIER_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 30h,08h,00h,00h,00h,00h,00h,00h   ; bottom-left (same as ACCENT_MID_PATTERN)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 0Ch,22h,55h,99h,99h,0AAh,44h,30h  ; bottom-right (barrier glyph)

ACCENT_DOWN_BARRIER_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left (blank)
    DB 70h,38h,00h,00h,00h,00h,00h,00h   ; bottom-left (same as ACCENT_DOWN_PATTERN)
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right (blank)
    DB 0Ch,22h,55h,99h,99h,0AAh,44h,30h  ; bottom-right (barrier glyph)

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
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left
    DB 30h,64h,FFh,07h,01h,2Ah,15h,00h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right
    DB 01h,06h,9Ch,FFh,FEh,7Ch,0Eh,03h   ; bottom-right

; "E4にアニメ追加 上下移動中に適用" - 2nd pose (user-supplied
; E42_16x16.json, fg=3=SPR_LIGHTGREEN matching Fighter's own color;
; replaces the earlier E4_2_16x16.json revision), switched to (once,
; permanently) with ENEMY4_PATTERN while diving - see EBSD_DIAG_E4.
ENEMY4_PATTERN_2:
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-left
    DB 00h,7Ch,0FFh,07h,00h,2Ah,00h,00h  ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right
    DB 01h,06h,9Eh,0F5h,0AAh,54h,0Ah,01h ; bottom-right

; enemy-fired bullet (new) - "パターンはFlyerレーザーを流用". Stage2's
; own FlyerLaser art (tools/stage2_combined/flyerlaser_gen.py) is just
; an 8x8 horizontal bar across rows2-3 (bytes 00,00,FF,FF,00,00,00,00);
; reused verbatim here in both left/right top quadrants to form a
; 16px-wide bar across the sprite's own upper half (bottom-left/right
; left blank) - Stage1 is a separate bank/build from Stage2, so these
; bytes are redefined from scratch, not shared.
EBULLET_PATTERN:
    DB 00h,00h,0FFh,0FFh,00h,00h,00h,00h   ; top-left: the bar
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-left: blank
    DB 00h,00h,0FFh,0FFh,00h,00h,00h,00h   ; top-right: the bar
    DB 00h,00h,00h,00h,00h,00h,00h,00h     ; bottom-right: blank

; 2x2 lit block, top-left corner of the 16x16 - the flyaway trail
; particle. Small but clearly visible, unlike a single dot.
PARTICLE_PATTERN:
    DB 0C0h,0C0h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h
    DB 00h,00h,00h,00h,00h,00h,00h,00h

ASTERISK_PATTERN:
    DB 7Fh   ; .XXXXXXX
    DB 9Eh   ; X..XXXX.
    DB 04h   ; .....X..
    DB 1Bh   ; ...XX.XX
    DB 1Bh   ; ...XX.XX
    DB 04h   ; .....X..
    DB 9Eh   ; X..XXXX.
    DB 7Fh   ; .XXXXXXX

; Enemy1/2/5's shared quadrant animation, frame2 of 3 (from E1Anim.json,
; top-right quadrant) - see ENEMY_ANIM_SEQ_TABLE for the 1,2,3,2 cycle.
ASTERISK_PATTERN2:
    DB 00h,7Eh,0FFh,1Bh,1Bh,0FFh,7Eh,00h

; frame3 of 3 (E1Anim.json, bottom-left quadrant).
ASTERISK_PATTERN3:
    DB 00h,00h,00h,0FFh,0FFh,00h,00h,00h

; Sequence index (0-3) -> glyph address, for the shared "1,2,3,2"
; quadrant animation cycle: seq0=base, seq1=frame2, seq2=frame3,
; seq3=frame2 again (then wraps back to seq0=base). Read via
; SET_REDRAW_SRC_FROM_SEQ.
ENEMY_ANIM_SEQ_TABLE:
    DW ASTERISK_PATTERN, ASTERISK_PATTERN2, ASTERISK_PATTERN3, ASTERISK_PATTERN2

; Enemy1 4-frame animation pattern
E1A_PATTERN:
    DB 7Fh,9Eh,04h,1Bh,1Bh,04h,9Eh,7Fh   ; top-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; top-right
    DB 00h,00h,00h,00h,00h,00h,00h,00h   ; bottom-right

; Ship animation patterns (from the Sprite Editor's newer ship design).
; MID/UP/DOWN load into PAT_SHIP/PAT_SHIP_UP/PAT_SHIP_DOWN at INIT;
; PLAYER_SHIP_PAT picks which one to draw each frame from JOY_STICK
; (see DIR_DONE, just before the sprite-attribute redraw block).
SHIP_UP_PATTERN:
    DB 00h,00h,00h,00h,F0h,7Eh,1Fh,7Fh   ; top-left
    DB AFh,D5h,AAh,D5h,AAh,D7h,68h,30h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,80h,E0h   ; top-right
    DB F8h,54h,AAh,5Fh,E1h,00h,00h,00h   ; bottom-right

SHIP_MID_PATTERN:
    DB 00h,00h,E0h,38h,7Ch,0Fh,3Fh,FFh   ; top-left
    DB 80h,7Fh,D5h,80h,7Fh,B0h,00h,00h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,C0h,F0h   ; top-right
    DB C8h,74h,BEh,1Fh,F1h,00h,00h,00h   ; bottom-right

SHIP_DOWN_PATTERN:
    DB 00h,00h,00h,E0h,78h,FEh,F3h,87h   ; top-left
    DB FFh,FFh,81h,7Eh,7Fh,8Ch,F0h,C0h   ; bottom-left
    DB 00h,00h,00h,00h,00h,00h,00h,C0h   ; top-right
    DB 88h,C4h,FEh,FFh,01h,00h,00h,00h   ; bottom-right

; Destroyed-quadrant explosion (round69 follow-up, ExpAnim_24x24.json):
; 2 distinct 8x8 tiles only, reused across all 3 sequential frames -
; see EXP_CODE_THIN/THICK's own EQU comment for the color-group reuse
; rationale, and TRIGGER_EXPLOSION/UPDATE_ONE_EXPLOSION for the frame
; layout. Loaded at EXP_CODE_THIN(120)*8 - the old ANIM_PATTERNS
; 512-byte/64-code blob this replaced only ever used its own 8 group-
; leader codes (the other 56 were always-zero unused padding), so this
; frees the remaining 6 codes (122-127) of the same group15 too.
EXPLOSION_TILES:
    DB 00h,00h,00h,0FFh,0FFh,00h,00h,00h   ; EXP_CODE_THIN  (2-row bar)
    DB 00h,00h,0FFh,0FFh,0FFh,0FFh,00h,00h ; EXP_CODE_THICK (4-row bar)

; Static sprite patterns used only while a quadrant is "flying in"
; during formation assembly: PAT_TEMP_TOP shows just the top-left
; asterisk (used by the real unit slot while its first quadrant
; arrives), PAT_TEMP_BOT shows just the bottom-right one (used by a
; spare/transient sprite slot for the second quadrant's arrival).
; (2026-09-19、"あと圧縮はボスだけじゃなく全てのキャラデータだぞ"):
; RLE圧縮済み(PATTERNS自身のコメント参照)。元の生データはtop-left=
; ASTERISK_PATTERN's new art(8byte)+24byteゼロ+24byteゼロ+
; bottom-right=同じ絵柄(8byte)、計64byte。この1ブロックが3箇所
; (SPRPAT+0C0h/160h/200h)へ同じ内容のままロードされる。
TEMP_SPRITE_PATTERNS:
    DB 2,127,158,4,129,27,2,4,158,127,175,0,2,127,158,4
    DB 129,27,2,4,158,127
TEMP_SPRITE_PATTERNS_SEGMENTS EQU 7

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

; New BG enemy's 16x16 glyph, split into 4 8x8 quadrants (TL/TR/BL/BR,
; drawn as 4 adjacent nametable cells - not a hardware sprite). Pixel
; data confirmed directly by hand-editing an on-screen grid (image-based
; transcription wasn't reliable enough for this shape). Placed at
; ENEMY3_CODE1's group (19) spare codes 153-156, so it uses Enemy3's
; existing gray/blue color - no new color-table group needed, and
; ENEMY3_CODE1(152) itself is untouched.
NEWENEMY_CODE_TL EQU 153
NEWENEMY_CODE_TR EQU 154
NEWENEMY_CODE_BL EQU 155
NEWENEMY_CODE_BR EQU 156
NEWENEMY_PATTERN_TL:
    DB 00h,2Ah,6Ah,0Ah,7Ah,02h,7Eh,00h
NEWENEMY_PATTERN_TR:
    DB 00h,0AAh,0AEh,0AEh,0BEh,0BEh,0FEh,0FEh
NEWENEMY_PATTERN_BL:
    DB 7Fh,03h,7Fh,0Fh,7Fh,3Fh,7Fh,00h
NEWENEMY_PATTERN_BR:
    DB 7Eh,0BEh,0DEh,0EEh,0F6h,0FAh,0FCh,00h

; enemy6's 90/180/270-degree rotations of the same 16x16 glyph above
; (bit-rotated the source grid itself, then re-split into quadrants -
; not just a quadrant shuffle), for the spin animation ENEMY6_DRAW
; cycles through one step at a time. Codes: group19's 3 remaining
; spares (157-159) + group20's first spare (161) for 90-degrees,
; group20's next 4 spares (162-165) for 180-degrees - both groups
; share Enemy3's gray/blue color, so those two stay on-color. Only
; group21's spares were left for 270-degrees, and that group is
; gray/RED (Enemy3's pattern3 color) - so the spin flashes red for
; that one quarter-turn instead of staying blue. SCREEN1's 8-codes-
; share-1-color-pair layout leaves no untouched all-blue group large
; enough for all 3 rotations; 270-degrees drew the short straw.
NEWENEMY_CODE90_TL  EQU 157
NEWENEMY_CODE90_TR  EQU 158
NEWENEMY_CODE90_BL  EQU 159
NEWENEMY_CODE90_BR  EQU 161
NEWENEMY_CODE180_TL EQU 162
NEWENEMY_CODE180_TR EQU 163
NEWENEMY_CODE180_BL EQU 164
NEWENEMY_CODE180_BR EQU 165
NEWENEMY_CODE270_TL EQU 169
NEWENEMY_CODE270_TR EQU 170
NEWENEMY_CODE270_BL EQU 171
NEWENEMY_CODE270_BR EQU 172
NEWENEMY_PATTERN90_TL:
    DB 00h,57h,77h,77h,7Fh,7Fh,7Dh,7Dh
NEWENEMY_PATTERN90_TR:
    DB 00h,54h,56h,50h,5Eh,40h,7Eh,00h
NEWENEMY_PATTERN90_BL:
    DB 7Eh,7Dh,7Bh,77h,6Fh,5Fh,3Fh,00h
NEWENEMY_PATTERN90_BR:
    DB 0FEh,0C0h,0EEh,0F0h,0FEh,0F4h,0F6h,00h
NEWENEMY_PATTERN180_TL:
    DB 00h,3Fh,5Fh,6Fh,77h,7Bh,7Dh,7Eh
NEWENEMY_PATTERN180_TR:
    DB 00h,0FEh,0FCh,0FEh,0F0h,0FEh,3Eh,0FEh
NEWENEMY_PATTERN180_BL:
    DB 7Fh,7Fh,7Dh,79h,15h,75h,55h,00h
NEWENEMY_PATTERN180_BR:
    DB 00h,7Eh,40h,5Eh,50h,56h,54h,00h
NEWENEMY_PATTERN270_TL:
    DB 00h,6Fh,2Fh,7Fh,0Fh,77h,03h,7Fh
NEWENEMY_PATTERN270_TR:
    DB 00h,0FCh,0FAh,0F6h,0EEh,0DEh,0BEh,7Eh
NEWENEMY_PATTERN270_BL:
    DB 00h,7Eh,02h,7Ah,0Ah,6Ah,2Ah,00h
NEWENEMY_PATTERN270_BR:
    DB 0BEh,0BEh,0FEh,0FEh,0EEh,0EEh,0EAh,00h

; Per-phase code quads (TL,TR,BL,BR), phase order 0/90/180/270 -
; indexed by ENEMY6_DRAW using (IX+3)*4. Must stay in this order.
ENEMY6_ANIM_CODES:
    DB NEWENEMY_CODE_TL,    NEWENEMY_CODE_TR,    NEWENEMY_CODE_BL,    NEWENEMY_CODE_BR
    DB NEWENEMY_CODE90_TL,  NEWENEMY_CODE90_TR,  NEWENEMY_CODE90_BL,  NEWENEMY_CODE90_BR
    DB NEWENEMY_CODE180_TL, NEWENEMY_CODE180_TR, NEWENEMY_CODE180_BL, NEWENEMY_CODE180_BR
    DB NEWENEMY_CODE270_TL, NEWENEMY_CODE270_TR, NEWENEMY_CODE270_BL, NEWENEMY_CODE270_BR

; Full schedule, 480 entries (indices 0-479, Schedule_2_1.json,
; 2026-09-14), imported directly from the schedule editor's exported
; JSON (tick/row/type per placement) - see
; SSC_FIRE for the per-index dispatch this drives. Every tick here is
; a 16-bit word since thresholds run well past 255. Simple-formation,
; Enemy2, and Enemy4/Enemy5 spawns pull their actual Y/baseY from
; SPAWN_SIMPLE_Y_TABLE/SPAWN_BASEY_TABLE (row*8 from the editor),
; Enemy6 from ENEMY6_ROW_TABLE (raw row, from the editor), Enemy3-Wave
; from SPAWN_E3_OFFSET_TABLE (offset, from the editor's own field),
; Ebuz/Boss need no table (fixed position, row/tick are editor-only).
; round136(Schedule_2_2.json、346エントリへ差し替え、ユーザー提供 -
; "10KB減らした"。ROM予算確保のためEbuz Mk2追加と合わせて実施)。
; 16bit thresholds - N=345エントリ。
SPAWN_THRESHOLDS:
    DW 11,13,15,26,28,30,43,45,47,56,58,60,68,70,72,74
    DW 76,78,80,88,98,100,102,104,106,108,110,112,114,116,118,120
    DW 130,139,141,143,145,147,153,157,160,162,164,166,168,170,172,183
    DW 185,187,188,190,193,195,198,200,202,207,209,211,214,217,219,222
    DW 225,230,232,234,236,238,245,247,249,252,254,262,267,268,270,275
    DW 279,286,290,292,299,302,304,307,314,317,331,352,357,359,368,371
    DW 373,375,381,386,388,392,401,406,411,423,428,430,433,435,437,442
    DW 445,447,449,451,453,455,457,459,461,463,465,467,483,485,489,491
    DW 493,498,505,507,509,514,520,527,531,533,535,537,539,541,551,558
    DW 566,573,590,600,605,607,609,611,613,613,616,619,619,623,626,628
    DW 630,632,634,640,642,644,647,650,650,668,675,677,679,681,683,683
    DW 702,702,707,709,712,716,718,721,723,725,730,733,739,741,744,747
    DW 751,755,768,774,788,794,798,803,804,809,815,818,822,825,827,830
    DW 833,835,838,840,843,847,851,851,852,853,853,854,855,855,856,857
    DW 857,858,859,859,860,861,861,863,863,863,865,865,866,867,867,869
    DW 869,869,871,871,872,873,873,875,875,875,877,877,879,879,879,881
    DW 881,883,883,883,885,885,887,887,887,889,889,890,891,891,893,893
    DW 895,895,895,897,897,899,899,899,901,901,903,903,903,905,905,907
    DW 907,909,909,909,911,911,913,913,913,915,915,917,917,917,919,919
    DW 921,921,921,923,923,924,925,925,926,927,927,928,929,929,930,931
    DW 931,932,933,933,934,935,935,936,937,937,938,939,939,940,941,941
    DW 942,943,943,944,945

; (2026-09-23、ROM予算): 旧SPAWN_SIMPLE_Y_TABLE/SPAWN_BASEY_TABLE/SPAWN_E3_OFFSET_
; TABLE/ENEMY6_ROW_TABLE(各341byte)を1本にまとめた。スケジュールの各エントリは
; SSC_FIREでちょうど1つのSPAWN_*へ振り分けられ、各SPAWN_*は4表のうち1つしか読まない
; (SIMPLE→Y、E2/E4/E4B→BASEY、E3_WAVE→E3_OFFSET、E6→ROW)ので、エントリごとに
; そのハンドラが読む表の値だけを残せば挙動は同じ(tools/verify_spawn_param_merge.py
; が全エントリについて旧4表との一致を確認)。スケジュールを差し替える時はこの形で
; 生成し直すこと。
SPAWN_SIMPLE_Y_TABLE:
    DB 40,32,24,136,128,120,32,24,16,128,120,112,24,40,56,72,88
    DB 104,120,120,120,112,104,96,88,80,72,64,56,48,0,0,3,88
    DB 96,104,112,120,120,120,88,120,120,112,104,96,88,48,40,32,136
    DB 64,88,48,72,112,56,72,104,56,72,96,64,72,96,144,128,112
    DB 96,80,104,112,120,72,88,104,72,128,88,80,104,56,72,112,64
    DB 56,48,120,64,0,0,24,96,40,104,48,40,32,96,24,64,48
    DB 16,72,112,32,56,48,40,32,24,112,136,128,120,112,104,96,88
    DB 80,64,80,104,112,112,64,56,120,72,64,48,112,64,64,56,96
    DB 112,104,96,88,80,72,96,32,120,32,64,64,88,72,56,112,64
    DB 128,96,72,120,80,96,72,56,120,80,80,112,64,88,72,120,0
    DB 16,24,32,48,32,104,32,104,72,80,104,96,88,88,88,80,80
    DB 72,72,80,104,120,88,56,64,96,104,88,80,72,48,88,88,80
    DB 64,64,80,64,64,80,72,64,72,72,1,18,72,5,12,80,6
    DB 13,88,7,14,96,8,15,96,9,15,1,96,18,9,15,96,9
    DB 15,8,88,15,7,14,80,6,13,5,64,12,4,11,3,48,10
    DB 2,9,1,48,18,3,11,5,72,13,7,15,88,8,15,7,16
    DB 1,96,18,7,16,6,80,14,5,13,4,64,12,1,11,5,12
    DB 6,72,14,7,15,8,88,14,8,14,1,88,18,7,14,6,80
    DB 13,7,14,80,7,13,80,7,13,80,7,13,80,7,13,80,7
    DB 13,80,7,13,80,7,13,80,7,13,80,7,13,80,7,13,80
    DB 0
; (このアセンブラはEQUの前方参照を0と評価するので、別名は必ず表の後ろに置く)
SPAWN_BASEY_TABLE     EQU SPAWN_SIMPLE_Y_TABLE
SPAWN_E3_OFFSET_TABLE EQU SPAWN_SIMPLE_Y_TABLE
ENEMY6_ROW_TABLE      EQU SPAWN_SIMPLE_Y_TABLE




; --- Boss BG (nametable) graphics, generated from
; --- dotpict_20260806_173500 (12x37 dot art), resized directly
; --- to 40x128 dots (5x16 tiles) and quantized to black/gray/red/blue.
; --- (No pure-blue-free / 2-non-blue-color tiles this size - every
; --- tile's minority pixels just fold into bg=blue, so only 3
; --- color pairs are needed: K/B, G/B, R/B - keeps us to exactly
; --- the 8 free groups, codes 192-255.)
; (round145、"ではボスポッド弾・EbuzII弾ビームに1pxコリジョン"対応の
; ROM予算確保): BOSS_HEX_PATTERN/BOSS_ORBIT_PATTERN/DFL_BULLET_PATTERN/
; EXPLOSION_PATTERN(元は4個の32byte DBブロック、計128byte)は、
; BOSS_PATTERNS(上記)と全く同じ「BOSS_SPAWNで1回だけLDIRVMされる
; 純粋な静的パターンデータ、以後CPUから直接読まれない」条件を満たす。
; round135follow-up16の時点ではbank6の空きが足りず移設を見送っていたが
; (このファイル自身の上のコメント参照)、以後の曲・データ追加で
; bank6側の空きを再計測した結果468byte確保できていたため、今回まとめて
; オフロード(BOSS_PATTERNSと同じくTitleが起動時にRAM[BOSS_MISC_
; PATTERNS]へ事前コピー、Stage1側はそのRAMを直接LDIRVMのソースにする
; だけ)。4個のラベルは廃止し1個のEQUへ統合(元の並び・オフセットは
; 保持: +0=HEX,+32=ORBIT,+64=DFL_BULLET,+96=EXPLOSION)。さらに
; STAGE1_MISSION_GAMEOVER_FONT追加分と合わせるとbank6の空きを15byte
; オーバーしたため、BOSS_PATTERNSと同じ自前RLEで圧縮(128byte->72byte)。
BOSS_MISC_PATTERNS EQU 0D20Ah  ; 72byte(RLE圧縮済み)、シンボルテーブル
                                ; 実測で完全に空きと確認済みの領域
                                ; (EBUZ2_MK2_CHARDATA[D0C0h-D1A3h、
                                ; 227byte]の直後)。
BOSS_MISC_PATTERNS_SEGMENTS EQU 22  ; tools/bgm_data/bgm_bank_gen.py
                                ; STAGE1_BOSS_MISC_PATTERNSの'segments'
                                ; と一致させること。

; Same scattered-spark burst glyph as EXPLOSION_PATTERN above (no new
; art was supplied for this - reusing the existing "explosion" visual
; language rather than inventing a new one), just loaded permanently
; at INIT under its own always-available code (PAT_PLAYER_EXPLOSION)
; instead of EXPLOSION_PATTERN's own lazy/boss-only loading - see
; PLAYER_EXPL_UPDATE_ALL.
PLAYER_EXPL_PATTERN:
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

BOSS_PATTERNS EQU 0CD8Dh  ; 290byte(RLE圧縮済み)、Titleが起動時にここへ埋める
BOSS_PATTERNS_SEGMENTS EQU 126  ; tools/bgm_data/bgm_bank_gen.py STAGE1_BOSS_CHARDATAの'segments'と一致させること
; round135follow-up16("ボスを別バンクに移してくれ だいぶ削減出来る
; はずだ"): ボス本体64x64のグラフィックデータ(旧: ここに直接DB展開
; されていた512byte)は、BOSS_SPAWN内の1回のLDIRVM呼び出しでしか
; 参照されない(ボス出現の瞬間に1回だけVRAMへ転送、以後CPUから直接
; 読まれることはない)ため、Stage2のSASAPI_CHARDATA(round64)と全く
; 同じ「一度きりのロード専用データ」条件を満たす。ただしStage1は
; (Round40の判断により)自分ではバンク切替を一切行わない設計を維持
; するため、Stage2方式(実行時にwindow Bを一時切替)ではなく、Title
; 起動時にBGM/TryZ/ジングルと同じ「共有バンク(Comb bank6、tools/
; bgm_data/bgm_bank_gen.pyのSTAGE1_BOSS_CHARDATA)からStage1専用RAM
; へ事前コピー」方式を踏襲する(tools/title_screen/title_test.asmの
; INIT_BGM参照)。BOSS_HEX_PATTERN/BOSS_ORBIT_PATTERN/DFL_BULLET_
; PATTERN/EXPLOSION_PATTERN(計128byte)は、このバンクの実際の空き
; 容量(522byte)がBOSS_PATTERNS込みの640byte全部には足りなかった
; ため、今回は移設対象から外し引き続きROM側に残している。
; (2026-09-14、"キャラデータはかなり圧縮ができる筈 RLEで十分だろう
; 逐次読み込みはステージ1も2もボスくらいのはず なので初期状態で
; キャラデータはVramに転送済みのはずなんで圧縮展開しても問題は無い
; はず"): ここでさらにRLE圧縮(512byte->290byte、title_screen/
; title_bg_gen.pyのrle_encode/rle_decodeと同じ自前フォーマット)。
; TitleはコピーAT起動時に圧縮バイトのままRAM(BOSS_PATTERNS)へ
; コピーするだけ(コピー量も減りRAMも節約)、実際の展開はStage1自身の
; BOSS_SPAWNがVRAM書き込み時に1回だけ行う(DECOMPRESS_RLE_TO_VRAM、
; Stage2のLOAD_SASAPI_PATTERNS用と全く同じ手法をStage1にも複製 -
; Stage1はバンク切替をしないためRAM上の圧縮データを直接ソースに
; できる、Z80命令列自体はROM/RAMどちらが入力でも同一)。ボス出現は
; ゲーム中1回だけのため、展開コストが毎フレームの処理に影響することは
; 無い("逐次読み込みはステージ1も2もボスくらいのはず"という前提通り)。

; boss nametable map: 5 cols x 16 rows of character codes
; (48=BLANKCODE/solid-blue, 192-252=boss tiles above)

; --- sky-erase stub templates (copied into the RAM stubs at INIT ---
; --- and again when the boss lands - see SKY_STUB_* above).       ---
; --- FAST: original behavior, just BLANKCODE.                     ---
SKY_FAST_H:
    LD A,BLANKCODE
    JP BULLETC_HITERASE_GOT
SKY_FAST_E:
    LD A,BLANKCODE
    JP BULLETC_ERASE_GOT
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
SKY_SLOW_H:
    LD A,(BULLETC_ROW) : SUB 2 : CP 16 : JR NC,SSH_FAST
    LD B,A : LD A,(BULLETC_COL) : SUB 26 : CP 5 : JR NC,SSH_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLETC_HITERASE_GOT
SSH_FAST:
    LD A,BLANKCODE
    JP BULLETC_HITERASE_GOT
SKY_SLOW_H_END:

SKY_SLOW_E:
    LD A,(BULLETC_ROW) : SUB 2 : CP 16 : JR NC,SSE_FAST
    LD B,A : LD A,(BULLETC_COL) : SUB 26 : CP 5 : JR NC,SSE_FAST
    LD H,0 : LD L,B : LD D,H : LD E,L
    ADD HL,HL : ADD HL,HL : ADD HL,DE
    LD D,0 : LD E,A : ADD HL,DE
    LD DE,BOSS_MAP : ADD HL,DE
    LD A,(HL)
    JP BULLETC_ERASE_GOT
SSE_FAST:
    LD A,BLANKCODE
    JP BULLETC_ERASE_GOT
SKY_SLOW_E_END:

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

; digit glyphs 0-9 for the on-screen score display (code DIGIT_BASE+N)
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

; (round145、ROM予算確保のためオフロード): "MISSION 1"/"MISSION 2"共有
; フォント(M,I,S,O,N,space,1,2、codes64-71)+GAME OVER("MISSION FAILED")
; 用フォント(G,A,E,V,R,F,L,D、codes72-79)は、いずれもINIT冒頭で1回だけ
; LDIRVMされ以後CPUから直接読まれない静的データ(元は2個の64byte DB
; ブロック、計128byte)。BOSS_MISC_PATTERNSと同じ理由でbank6(Comb共有
; バンク)へオフロード、Titleが起動時にRAM[STAGE1_MISSION_GAMEOVER_
; FONT]へ事前コピーする。元のグリフデータ・並び順(M,I,S,O,N,space,1,2,
; G,A,E,V,R,F,L,D)はtools/bgm_data/stage1_mission_gameover_font.binに
; そのまま保持。BOSS_MISC_PATTERNSと合わせるとbank6の空きを15byte
; オーバーしたため、こちらも自前RLEで圧縮(128byte->114byte)。
STAGE1_MISSION_GAMEOVER_FONT EQU 0D28Ah  ; 114byte(RLE圧縮済み)、
                                ; シンボルテーブル実測で完全に空きと
                                ; 確認済みの領域(BOSS_MISC_PATTERNS
                                ; [D20Ah-D28Ah、72byte確保だが元の
                                ; 128byte分の枠を維持]の直後)。
STAGE1_MISSION_GAMEOVER_FONT_SEGMENTS EQU 39  ; tools/bgm_data/
                                ; bgm_bank_gen.py STAGE1_MISSION_
                                ; GAMEOVER_FONTの'segments'と一致させること。

; group8(codes64-71)の色を白文字/黒背景(0F1h)へ上書き - 元は"shot-green"
; 用に予約されただけで実際のビットマップが一度も無かった色(0D3h)。
MISSION_FONT_COLOR:
    DB 0F1h

; group9(codes72-79)の色も白文字/黒背景(0F1h)へ - 元は"shot-white"用に
; 予約されただけで実際のビットマップが一度も無かった色(0DFh)。
GAMEOVER_FONT_COLOR:
    DB 0F1h

; "MISSION 1"/"MISSION 2" - M,I,S,S,I,O,N,space,digit(9byte、row12/col11
; center)。digitは添付フォントの"1"/"2"グリフ(MISSION_FONT_BASE+6/+7、
; 白/黒0F1hで既に着色済み、フォント色と一致)。
MISSION1_MSG:
    DB MISSION_FONT_BASE+0,MISSION_FONT_BASE+1,MISSION_FONT_BASE+2,MISSION_FONT_BASE+2
    DB MISSION_FONT_BASE+1,MISSION_FONT_BASE+3,MISSION_FONT_BASE+4,MISSION_FONT_BASE+5
    DB MISSION_FONT_BASE+6   ; '1'
MISSION2_MSG:
    DB MISSION_FONT_BASE+0,MISSION_FONT_BASE+1,MISSION_FONT_BASE+2,MISSION_FONT_BASE+2
    DB MISSION_FONT_BASE+1,MISSION_FONT_BASE+3,MISSION_FONT_BASE+4,MISSION_FONT_BASE+5
    DB MISSION_FONT_BASE+7   ; '2'

; (2026-09-07、"表示もGAME OVERではなくMISSION FAILEDに変更"): 元の
; "GAME OVER"(9byte)から"MISSION FAILED"(14byte、row12/col9 center -
; 14byteを画面幅32セルの中央に置くには(32-14)/2=9列目から)へ変更。
; M,I,S,S,I,O,N,spaceはMISSION_FONT_BASE側(group8)、F,A,L,E,Dは
; GAMEOVER_FONT_BASE側(group9)を混在参照する。
GAME_OVER_MSG:
    DB MISSION_FONT_BASE+0                   ; M
    DB MISSION_FONT_BASE+1                   ; I
    DB MISSION_FONT_BASE+2                   ; S
    DB MISSION_FONT_BASE+2                   ; S
    DB MISSION_FONT_BASE+1                   ; I
    DB MISSION_FONT_BASE+3                   ; O
    DB MISSION_FONT_BASE+4                   ; N
    DB MISSION_FONT_BASE+5                   ; space
    DB GAMEOVER_FONT_BASE+5                  ; F
    DB GAMEOVER_FONT_BASE+1                  ; A
    DB MISSION_FONT_BASE+1                   ; I
    DB GAMEOVER_FONT_BASE+6                  ; L
    DB GAMEOVER_FONT_BASE+2                  ; E
    DB GAMEOVER_FONT_BASE+7                  ; D
GAME_OVER_MSG_LEN EQU $ - GAME_OVER_MSG

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
; (2026-09-19、"あと圧縮はボスだけじゃなく全てのキャラデータだぞ"):
; RLE圧縮済み(PATTERNS自身のコメント参照)。GREEN/WHITE/BROWN variants
; removed - shots can never reach the ground scroller anymore (see
; PLAYER_MAXY), so only BLUE is loaded. 元の生データはBLUE M=0-6の
; 対角線ストリーク(M=7は未使用スロット)。
BULLET_PATTERNS:
    DB 1,102,51,134,0,1,102,51,134,0,1,102,51,134,0,1
    DB 102,51,134,0,1,102,51,134,0,1,102,51,134,0,1,102
    DB 51,135,0
BULLET_PATTERNS_SEGMENTS EQU 14

; ---- (2026-09-23、ROM詰め直し) ROWADDR_LO手前のページ残りへ末尾区間から移設 ----

; ----------------------------------------------------------------------
; round145("EbuzIIで敵の弾やビームにコリジョンがない...いずれも先端1px
; の判定を入れてくれ"): volley1(V1、5レーン)/volley2(V2、4門x4スロット)/
; レーザーの3種、いずれも自機との接触判定が丸ごと欠けていた(本体
; [EBUZ_CELL_ADDR経由]のみ判定していた)ため新規追加。呼び出し元
; (PDC_CHECK_EBUZ2)が既にEBUZ2_ACT!=0・EBUZ2_PHASE!=2を確認済みのため
; ここでは再チェックしない。PLAYER_HIT_BOX_EBUZ_1PXは名前に反し汎用の
; 「点(D,E、px単位)が自機8x8ヒットボックスと重なるか」判定のため
; そのまま再利用する(EBUZ以外の弾でも使える設計)。Output: A=1でヒット。
; ROM予算の都合(Round144由来のALIGN 256境界回避策)でファイル末尾に配置。
; ----------------------------------------------------------------------
PDC_CHECK_EBUZ2_PROJECTILES:
    CALL PDC_CHECK_EBUZ2_V1
    OR A
    RET NZ
    CALL PDC_CHECK_EBUZ2_V2
    OR A
    RET NZ
    JP PDC_CHECK_EBUZ2_LASER

; V1(volley1、5レーン閉状態弾): EBUZ2_V1_STRUCT[lane]=[ACT,COL](2byte
; ペア×5)、行はlane+EBUZ2_ENTRY_TARGET_ROW(固定・非保持)。
PDC_CHECK_EBUZ2_V1:
    LD IX,EBUZ2_V1_STRUCT
    LD B,0
PCEV1_LOOP:
    LD A,(IX+0)
    OR A
    JR Z,PCEV1_SKIP
    LD A,(IX+1) : ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,B : ADD A,EBUZ2_ENTRY_TARGET_ROW
    ADD A,A : ADD A,A : ADD A,A : LD E,A
    PUSH BC
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    POP BC
    OR A
    JR NZ,PCEV1_HIT
PCEV1_SKIP:
    INC IX : INC IX
    INC B
    LD A,B
    CP 5
    JR NZ,PCEV1_LOOP
    XOR A
    RET
PCEV1_HIT:
    LD A,1
    RET

; V2(volley2、4門x4スロットの回転プール): EBUZ2_V2_COLS[16]/
; EBUZ2_V2_ROWS[16](=COLS+16の規約)、非アクティブはEBUZ2_SLOT_EMPTY。
PDC_CHECK_EBUZ2_V2:
    LD HL,EBUZ2_V2_COLS
    LD B,16
PCEV2_LOOP:
    LD A,(HL)
    CP EBUZ2_SLOT_EMPTY
    JR Z,PCEV2_SKIP
    ADD A,A : ADD A,A : ADD A,A
    PUSH AF
    PUSH HL
    LD DE,16 : ADD HL,DE
    LD A,(HL)
    POP HL
    ADD A,A : ADD A,A : ADD A,A : LD E,A
    POP AF : LD D,A
    PUSH BC
    PUSH HL
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    POP HL
    POP BC
    OR A
    JR NZ,PCEV2_HIT
PCEV2_SKIP:
    INC HL
    DJNZ PCEV2_LOOP
    XOR A
    RET
PCEV2_HIT:
    LD A,1
    RET

; レーザー(先端1pxのみ判定): HOLD中(発射直後、全長固定22列)は先端を
; 固定col22とし、retract中はEBUZ2_LASER_UNITから毎tick縮む先端位置を
; 再計算する(EBUZ2_UL_RETRACTの消去列計算[UNIT*2+1]と同じ考え方、
; +1して消去前の"まだ残っている"側の外側1列を先端とする)。
PDC_CHECK_EBUZ2_LASER:
    LD A,(EBUZ2_LASER_ACT)
    OR A
    JR Z,PCEL_MISS
    LD A,(EBUZ2_LASER_HOLD)
    OR A
    LD A,22
    JR NZ,PCEL_GOTCOL
    LD A,(EBUZ2_LASER_UNIT)
    ADD A,A : ADD A,2
PCEL_GOTCOL:
    ADD A,A : ADD A,A : ADD A,A : LD D,A
    LD A,(EBUZ2_LASER_ROW)
    ADD A,A : ADD A,A : ADD A,A : LD E,A
    JP PLAYER_HIT_BOX_EBUZ_1PX
PCEL_MISS:
    XOR A
    RET

; (2026-09-21、飛び込み演出): CALL経由のみで使う一式。ROM予算の
; ALIGN-256境界の関係で、PLAYER_PARTICLE_SPAWN/FADEと同じくファイル
; 末尾(全ALIGN境界より後ろ)に配置(実測により、この位置以外では
; Comb組み込み側の追加パッチぶんでALIGN境界を超え+256byteの余分な
; パディングが発生することを確認済み)。
; (2026-09-21、"0,0からX128、Y64まで移動してそこからX32,Y64な"):
; leg1のY速度をX速度の半分(1、Xは2)にすることで、距離比128:64=2:1と
; 速度比2:1が一致し、X/Yが"完全に同時"(64フレーム)に(SHIP_ENTRY_MID_X,
; PLAYER_INITY)へ到達する真っ直ぐな斜め移動になる(レンダリングで直線
; 移動を確認済み)。両軸とも到達後は二度と呼ばれない(到達した瞬間に
; ACT遷移する)ため、クランプ判定そのものが不要 - ROM予算の都合で
; いずれもCALL先を作らずインライン化(Y速度=1は"INC A"1byteで済む
; ことも利用)。**この前提(距離が速度で割り切れる/両軸が同時到達する)
; を変える場合は必ずクランプ判定を復元すること**(でないと8bitアンダー
; /オーバーフローでラップし、自機が瞬間移動する重大なバグになる)。
; 呼び出し元(MAINLOOP側のCALL直前)が既にSHIP_ENTRY_ACTをAへ読み込み
; 済み(OR A/JR Zで消費されない)なので、ここでの再読み込みは省略。
; ACTは1(leg1)か2(leg2)のいずれかしかあり得ない(0ならBlock Aの
; OR A/JR Zで既に弾かれている)ため、CP 2の代わりにDEC A:JR NZで
; 判定(A-1!=0 <=> A==2)。PLAYERX/PLAYERYが隣接アドレスなのを利用し
; HLをINCで使い回す。
UPDATE_SHIP_ENTRY:
    DEC A
    LD HL,PLAYERX
    JR NZ,SEU_LEG2
    LD A,(HL) : ADD A,SHIP_ENTRY_SPEED : LD (HL),A
    INC HL
    LD A,(HL) : INC A : LD (HL),A
    CP PLAYER_INITY : RET NZ
    LD A,2 : LD (SHIP_ENTRY_ACT),A
    RET
SEU_LEG2:
    ; leg2(X:128→32)。距離96(=SHIP_ENTRY_MID_X-PLAYER_RETREAT_TARGET_X)が
    ; SHIP_ENTRY_SPEEDでちょうど割り切れ、到達後は二度と呼ばれないため
    ; クランプ不要。
    LD A,(HL) : SUB SHIP_ENTRY_SPEED : LD (HL),A
    CP PLAYER_RETREAT_TARGET_X : RET NZ
    XOR A : LD (SHIP_ENTRY_ACT),A
    RET

; (2026-09-22follow-up、"128,64から後ろに下がるときは下向きのキャラに
; 32,64に来たらノーマルに"): leg1(ACT=1、突入)はShipStart2/1の専用絵柄
; のまま、leg2(ACT=2、後退)は通常ゲームプレイの「下向き」ポーズ
; (PAT_SHIP_DOWN/PAT_ACCENT_DOWN、JOY_STICK下入力時と同一資産)を流用。
; 呼び出し元はCALL直前にSHIP_ENTRY_ACTを既にAへ読み込み済み(OR Aで
; 消費されない)ため、ここでの再読み込みは省略しそのままCPで分岐する。
APPLY_SHIP_ENTRY_PAT:
    CP 2
    JR Z,ASEP_LEG2
    LD A,PAT_SHIP_ENTRY_BODY : LD (PLAYER_SHIP_PAT),A
    LD A,PAT_SHIP_ENTRY_ACCENT : LD (PLAYER_ACCENT_PAT),A
    RET
ASEP_LEG2:
    LD A,PAT_SHIP_DOWN : LD (PLAYER_SHIP_PAT),A
    LD A,(BARRIER_HP) : OR A
    LD A,PAT_ACCENT_DOWN
    JR Z,ASEP_LEG2_ACC_GOT
    LD A,PAT_ACCENT_DOWN_BARRIER
ASEP_LEG2_ACC_GOT:
    LD (PLAYER_ACCENT_PAT),A
    RET

; SHIP_ENTRY_BODY/ACCENT_PATTERNはソース側32byte連続、コード140-147
; (PAT_SHIP_ENTRY_BODY=140の4コード+PAT_SHIP_ENTRY_ACCENT=144の4コード)
; もVRAM上で連続なため、1回のLDIRVM(64byte)にまとめられる。
LOAD_SHIP_ENTRY_PATTERNS:
    LD HL,SHIP_ENTRY_BODY_PATTERN : LD DE,PAT_SHIP_ENTRY_BODY*8+SPRPAT : LD BC,64 : CALL LDIRVM
    RET

    ALIGN 256
; VRAM address (low byte) of the start of each of the 24 screen
; rows in the name table (1800h + row*32), used to place a shot
; character at (row, col) without doing 16-bit multiply at runtime.
ROWADDR_LO:
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h
    DB 00h,20h,40h,60h,80h,0A0h,0C0h,0E0h

; ---- (2026-09-23、ROM詰め直し) ROWADDR_LOのページ残りへ末尾区間から移設 ----

; Called every frame, unconditionally: ages, moves, and redraws
; every active particle slot, hiding one the instant its life
; reaches 0. Runs regardless of PLAYER_FLYAWAY so already-spawned
; particles keep travelling/fading even after the ship itself has
; gone hidden. Bails out immediately (before touching the VDP at
; all) if every slot is idle, which is the case for the entire rest
; of the game outside the flyaway - important, since this is called
; unconditionally every single frame.
PLAYER_PARTICLE_FADE:
    LD B,PARTICLE_SLOTS
    LD HL,PARTICLE_ACT
PPF_ANYACT_LOOP:
    LD A,(HL) : OR A : JR NZ,PPF_ANYACT_FOUND
    INC HL : DJNZ PPF_ANYACT_LOOP
    RET
PPF_ANYACT_FOUND:

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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP

    LD HL,PARTICLE_ACT : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL)
    OR A
    EI
    JR NZ,PPF_VISIBLE
    DI
    LD A,ENEMY_HIDE_Y : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,255 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    JP PPF_SKIP
PPF_VISIBLE:
    LD HL,PARTICLE_Y : LD D,0 : LD E,C : ADD HL,DE
    DI
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD HL,PARTICLE_X : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_PARTICLE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD HL,PARTICLE_COL : LD D,0 : LD E,C : ADD HL,DE
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
PPF_SKIP:
    INC C
    LD A,C
    CP PARTICLE_SLOTS
    JP NZ,PPF_LOOP
    RET

; round145("ステージ1ボスもポッドから発射される弾にコリジョンがない
; ...先端1pxの判定を入れてくれ"): PDC_CHECK_PODS(ポッド本体判定)から
; ジャンプしてくる。ポッド本体とは別にPOD_BULLET0/1(発射された弾)を
; 自機と判定、命中してもポッド本体同様に消費しない(既存のPDC_CHECK_*
; 群の「接触検出のみ、対象は無傷」という設計を踏襲)。ROM予算の都合
; (Round144由来のALIGN 256境界回避策)でファイル末尾に配置。
PDC_CHECK_POD_BULLETS:
    LD A,(POD_BULLET0_ACT)
    OR A
    JR Z,PCPB_SKIP0
    LD A,(POD_BULLET0_X) : LD D,A
    LD A,(POD_BULLET0_Y) : LD E,A
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    OR A
    JR NZ,PCPB_HIT
PCPB_SKIP0:
    LD A,(POD_BULLET1_ACT)
    OR A
    JR Z,PCPB_MISS
    LD A,(POD_BULLET1_X) : LD D,A
    LD A,(POD_BULLET1_Y) : LD E,A
    CALL PLAYER_HIT_BOX_EBUZ_1PX
    OR A
    RET
PCPB_HIT:
    LD A,1
    RET
PCPB_MISS:
    XOR A
    RET

BLANK_PATTERN:
    DB 00h,00h,00h,00h,00h,00h,00h,00h    ; BLANKCODE's actual glyph: truly blank

    ALIGN 256
ROWADDR_HI:
    DB 18h,18h,18h,18h,18h,18h,18h,18h
    DB 19h,19h,19h,19h,19h,19h,19h,19h
    DB 1Ah,1Ah,1Ah,1Ah,1Ah,1Ah,1Ah,1Ah

; (2026-09-23、"ボス到達時に5万点を下回った場合どこに居てもポッド弾は
; 自機狙いになるように チェックは到達時にのみ行え メインで回すな"):
; POD_BULLET_CALC_DIRの照準ゲート+dx/dy計算。In: D=podX,E=podY。
; Out: C=直進、NC=自機狙い(D=dx,E=dy、どちらも9bit差分を1/2にした符号付き
; 8bit - 自機が左端寄りだとdxが-128を下回り8bitに収まらないため。方向は
; 保たれる)。POD_AIM_NORMAL=0(ボス到達時5万点未満)ならPLAYERXに関係なく
; 自機狙い。(ALIGN 256境界[LUT手前]の予算の都合でファイル末尾に配置)
POD_AIM_PREP:
    LD A,(POD_AIM_NORMAL) : OR A
    JR Z,PAP_AIM
    LD A,(PLAYERX)
    CP POD_BULLET_HOMING_THRESHOLD_X
    RET C                          ; 半分以下: 直進
PAP_AIM:
    LD A,(PLAYERX) : SUB D         ; C=1 if 自機がpodより左(正常)
    JR C,PAP_DX
    XOR A : CP 1                   ; dx>=0: 直進(C=1)
    RET
PAP_DX:
    SRL A : OR 80h : LD D,A        ; dx/2(常に負)
    LD A,(PLAYERY) : SUB E : LD E,A
    SBC A,A : AND 80h              ; dyの符号bit
    SRL E : OR E : LD E,A          ; dy/2(算術シフト)、OR後C=0
    RET

; ============================================================================
; (2026-09-23) ボス専用レーザー+レーザー干渉+エナジーゲージ。
; "ポッド撃破後中央からレーザーを撃つ...レーザー干渉をし連打で押し返す...
; Bボタン...敵の撃破数で自機レーザーエナジーがチャージ"、続けて仕様:
; "ボス専用 / Bボタン単発発射は完全に置き換え / チャージはスコア連動
; (5万点縛りと連動) / ゲージは画面上部黒帯中央 50px、1000点1px /
; レーザーはボスで1回のみ / 連打で負ければゲームオーバー / 8連射以上で
; 押し返し / エナジーは満たされていれば使用可(使用で減らない) / ボス
; レーザー前に使うと干渉できずボス発射でゲームオーバー / 失敗レーザーは
; ポッドを破壊できるが100フレでゲージが尽きて無くなる"。補足回答:
; "発射時に自機をレーザー行へ固定" "ボス発射後上下から割り込める、発射前
; であっても100フレ以内に間に合えば干渉動作に移行できる" "1秒8回以上"
; "仮絵で実装、後で差し替え"。
;
; (2026-09-23 改訂) "ボスレーザーは打ちっぱなしに 幅も3セルに 4フレは遅いので
; EbuzIIと同じでよい なのでほぼ正面から撃ち合いは出来ない ただしカウントダウン
; 動作あり ポッド弾がボス中央に集まって来る これはポッド弾発射そのものを流用
; ただし中央で消える" "レーザーは仮実装でEbuzIIのレーザーを流用"。回答: テスト
; モードで負けたらカウントダウンからやり直し / 発射後は上下から割り込み可・制限
; 時間でゲームオーバー / 軌道8箇所から2発ずつ約2秒 / ボスだけ3行、自機は1行。
;
; 流れ: 最後のポッド撃破 → カウントダウン(LZ_CD_T 120→0フレーム。30フレーム
; ごとにポッドの軌道上の2箇所からポッド弾を出し、ボス中央へ吸い込ませて消す)
; → 発射: 一瞬で全長(列0-25、行8-10の3行)・出しっぱなし。
;   ・自機レーザー照射中(カウントダウン中に撃っていた)なら即干渉。
;   ・条件未達(バリア0/エナジー不足/使用済み)なら即ゲームオーバー(理由付き)。
;   ・それ以外はLZ_PHASE=2: 3行の帯に入ったら即死、上下からBで割り込めば干渉、
;     LZ_CUTIN_FRAMESのうちに割り込まなければゲームオーバー。
; LZ_PHASE: 0=待機 1=自機レーザー単独照射(100フレで消滅→使用済み)
;           2=ボスレーザー照射中(割り込み待ち) 3=干渉(B連打) 4=終了
; ゲージ値(0-64px、2026-09-24から。旧0-50px) = 照射/干渉中はLZ_TIMERを64px幅へ、
; 使用済みは0、それ以外はmin(SCORE/10,64)(SCOREは実得点/100単位 → 1000点=10=1px)。
; 干渉: ボスは毎フレーム1px押し込み(60px/秒)、B1回で8px押し返す("8連射に戻して":
; 8回/秒=64px/秒でわずかに上回る、7回/秒=56px/秒では押し負ける)。撃つのを止めると
; (LZ_STOP_FRAMES押さない)ボスの押し込みは倍。開始点は自機とボスの射出口の中間。干渉点が列25
; (ボス左端)に届けば勝ち→START_BOSS_DEATH、自機の先端列まで押し戻されたら
; 負け→ゲームオーバー(バリア残量に関係なく、ボスレーザーを全長で残す)。
; 干渉中、ボスの3行のうち上下の行は干渉点より右だけ残る。
; GAMEOVER_ENABLED=0(タイトルBスタートのテスト用)で負けた場合は死なない
; ので、レーザーを消し、エナジーを未使用に戻してカウントダウンからやり直す。
; レーザーの絵はEbuzIIのレーザー(144/145)を仮に流用し、L/Rの2セル弾を途切れず
; 撃ち続ける流れとして描く(毎フレーム1セル送り、先端も1列/フレームで伸びる)。
; 干渉点のセルは空白(両方の弾がそこで消える)で、その上に自機爆発の絵のスプライト
; (22)、まわりに自機爆発の飛び散り(PLAYER_EXPL、26-29、音も自機爆発)。
; ボスレーザーの右端(列26-27)には16x24のスプライト(23/24)。ボスは干渉点を
; 毎フレーム1px押し込み、LZ_STOP_FRAMES押さなければ2px。
; ゲージは行0(group23、白/黒、codes186-188)。
; ============================================================================
LZ_PHASE     EQU 0F334h
LZ_SPENT     EQU 0F335h   ; 1=自機レーザー使用済み
LZ_TIMER     EQU 0F336h   ; 照射残りフレーム(ゲージ表示にも使う)
LZ_TICK      EQU 0F337h
LZ_PROW      EQU 0F338h   ; 単独照射の行
LZ_PCOL      EQU 0F339h   ; 自機レーザー先頭列(LZ_PENDと連続させること)
LZ_PEND      EQU 0F33Ah   ; 単独照射の終端列(含まない)
LZ_CD_T      EQU 0F33Bh   ; カウントダウン残りフレーム(0=停止中)
LZ_CLASH_X   EQU 0F33Ch   ; 干渉点のX(px)
GAUGE_SHOWN  EQU 0F33Dh   ; 画面に描画済みのゲージ値
LZ_BLANKING  EQU 0F33Eh   ; 非0: LZ_DRAWが空白で塗る(消去)
; (2026-09-23) ボスレーザーに割り込めずにやられた時の条件未達理由。bit0=バリア
; 無し、bit1=エナジー不足(使用済み含む)。非0なら死亡落下の完了時に通常の
; MISSION FAILEDではなくGAME_OVER_SEQ=4にし、Combがbank7(tools/gameover_bank/
; gameover_bank.asmのS1_FAIL_INIT、同じ番地をS1_FAIL_REASONとして読む)へ切り替えて
; 理由付きで表示する。
LZ_FAIL_REASON EQU 0F33Fh
; 乱射(フェーズ5)のレーザーLZ_BR_SLOTS本。1本LZ_BR_SIZE byte: +0 先端列(26以上は
; まだ画面に出ていない)、+1 伸び切ってからの残りフレーム、+2..+27 列0-25の行。
LZ_BR_BASE   EQU 0E919h   ; LZ_BR_SLOTS*LZ_BR_SIZE = 168 bytes (E919h-E9C0h)
LZ_BR_CUR    EQU 0E9C1h   ; 処理中の1本の番地(2 bytes)
LZ_BR_K      EQU 0E9C3h   ; 残り本数(ループ用)
LZ_BR_CNT    EQU 0E9C4h

LZ_ROW        EQU 9       ; ボス中央(BOSS_MAP row7、画面row9)。ボスは8-10の3行
LZ_SOLO_FRAMES EQU 100
LZ_CD_FRAMES  EQU 120     ; カウントダウン(30フレームごとに2発ずつ、4組)
LZ_CUTIN_FRAMES EQU 100   ; 発射後、割り込みを待つフレーム数
LZ_CB_CX      EQU 210     ; ポッド軌道の中心(GET_POD_XY)=ポッド弾の吸い込み先
LZ_CB_CY      EQU 71
LZ_CB0        EQU POD_BULLET0_DXMAG   ; 吸い込み中フラグ(ポッド全滅後は未使用の番地)
LZ_CB1        EQU POD_BULLET1_DXMAG
LZ_PUSH_PX    EQU 8       ; 1回押すごとの押し返し。ボスは毎フレーム1px(60px/秒)
                          ; なので1秒8回でほぼ互角
LZ_BR_SLOTS   EQU 3       ; 乱射レーザーの同時本数
LZ_BR_SIZE    EQU 28
LZ_BR_SPEED   EQU 4       ; 乱射レーザーの伸びる速さ(列/フレーム)
; ("3フレは短いな6フレくらいでいいかな" → "寿命はそのままでいい ... 1本1本打ってることは
; 見せたい"): 新しい1本は6フレームごと、寿命は元の長さ(伸びる7+11=18=3本×6)。
LZ_BR_HOLD    EQU 11      ; 伸び切ってから消えて次を撃つまでのフレーム数
LZ_BR_STAGGER EQU 24      ; 乱射開始時、各本の撃ち始めをずらす量(列ぶん=6フレーム)
LZ_STOP_FRAMES EQU 15     ; これだけ押さないと「撃つのを止めた」扱いでボスが2px/フレーム
LZ_WIN_X      EQU 200     ; 列25(ボス左端)
LZ_BFRONT     EQU LZ_CLASH_X  ; 照射中(2)はボスレーザーの先端列(26→0へ1列/フレーム)
; スプライト(ボス戦中は8-31が全部ボスの固定番号として予約済み。ポッド全滅後の
; レーザー中はポッド爆発の22-29が空いている)。
LZ_CLASH_SPR  EQU 22      ; 干渉点(自機爆発の絵)
LZ_END_SPR    EQU 23      ; 23/24: ボスレーザーの右端(射出口との隙間2セルを埋める16x24)
LZ_END_PAT    EQU 148     ; 148-155(スプライトパターンの空き)
LZ_SCATTER_SPR EQU 26     ; 26-29: 干渉中だけSPRITE_USEDを空けて飛び散りに使わせる
; (follow-up28) ゲージは空きのgroup16(codes128-135、旧ANIM2-white)へ移し、色を
; グループごと切り替える: 溜め中は白、満タンで赤(旧group23はスコアの数字8/9と共用で
; 色を変えられなかった)。
GAUGE_FULL_CODE EQU 128
GAUGE_PART_CODE EQU 129   ; 端数1セル分、値が変わるたびパターン自体を書き換える
GAUGE_COLOR_ADDR EQU 2010h   ; COLTBL+group16
GAUGE_COLOR      EQU 0F1h    ; 白/黒
GAUGE_FULL_COLOR EQU 081h    ; 赤/黒

GAUGE_BLANK_CODE EQU MISSION_FONT_BASE+5   ; 行0の黒埋めと同じ空白

; B1beam_24x24.json(16x24、シアン)。上16行=スプライト23、下8行=24
LZ_END_TILES:
    DB 0C0h,60h,98h,0EEh,33h,9Dh,2Fh,1Bh,85h,61h,9Ah,65h,0DBh,65h,9Ah,61h
    DB 00h,00h,00h,00h,00h,0C0h,60h,0B8h,5Eh,0ABh,77h,0EFh,0AFh,0F7h,6Bh,0DEh
    DB 8Bh,17h,3Dh,5Fh,0B6h,6Ch,0F0h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h
    DB 0B8h,60h,0C0h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h,00h
BARRIER_GLYPH_M:                               ; バリアのグリフ(0Ch,22h,55h,99h,99h,0AAh,44h,30h)の左右反転
    DB 30h,44h,0AAh,99h,99h,55h,22h,0Ch
GAUGE_TILES:
    DB 00h,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,00h  ; 128 満
    DB 00h,00h,00h,00h,00h,00h,00h,00h        ; 129 端数(動的)

LZ_INIT:
    LD HL,LZ_END_TILES : LD DE,LZ_END_PAT*8+SPRPAT : LD BC,64 : CALL LDIRVM
    LD HL,GAUGE_TILES : LD DE,GAUGE_FULL_CODE*8 : LD BC,16 : CALL LDIRVM
    LD HL,GAUGE_COLOR_ADDR : LD A,GAUGE_COLOR : CALL WRTVRM
    ; 反転バリア: 元の32byteを写し、右下8x8だけ反転グリフで上書き
    LD HL,ACCENT_MID_BARRIER_PATTERN : LD DE,PAT_ACCENT_BARRIER_M*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ACCENT_DOWN_BARRIER_PATTERN : LD DE,PAT_ACCENT_BARRIER_M+4*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BARRIER_GLYPH_M : LD DE,PAT_ACCENT_BARRIER_M*8+SPRPAT+24 : LD BC,8 : CALL LDIRVM
    LD HL,BARRIER_GLYPH_M : LD DE,PAT_ACCENT_BARRIER_M+4*8+SPRPAT+24 : LD BC,8 : CALL LDIRVM
    XOR A
    LD (LZ_PHASE),A : LD (LZ_SPENT),A : LD (GAUGE_SHOWN),A : LD (LZ_BLANKING),A
    LD (LZ_FAIL_REASON),A : LD (LZ_CD_T),A
    RET

; Out: A=ゲージ値(0-GAUGE_MAX)。(2026-09-24、"チャージを64px64000点に"): 1000点=1px、
; 64px=6万4千点で満タン。照射/干渉中はLZ_TIMER(100→0)を64px幅へ
; (T/2+T/8+T/32、64で頭打ち)。
GAUGE_VALUE:
    LD A,(LZ_PHASE) : AND 0FDh : DEC A
    JR NZ,GV_NOTIMER
    LD A,(LZ_TIMER) : SRL A : LD B,A     ; T/2
    SRL A : SRL A : LD C,A               ; T/8
    SRL A : SRL A                        ; T/32
    ADD A,B : ADD A,C
    CP GAUGE_MAX+1
    RET C
    LD A,GAUGE_MAX
    RET
GV_NOTIMER:
    LD A,(LZ_SPENT) : OR A
    LD A,0
    RET NZ
    LD A,(SCORE+2) : OR A
    JR NZ,GV_FULL
    LD HL,(SCORE) : LD DE,-640 : ADD HL,DE
    JR C,GV_FULL
    LD HL,(SCORE) : LD DE,-10 : LD A,0FFh
GV_DIV:
    INC A : ADD HL,DE
    JR C,GV_DIV
    RET
GV_FULL:
    LD A,GAUGE_MAX
    RET

; 行0中央(px96-159=cols12-19)へゲージを描く。値が変わった時だけ。
GAUGE_UPDATE:
    CALL GAUGE_VALUE
    LD HL,GAUGE_SHOWN
    CP (HL)
    RET Z
    LD (HL),A
    LD C,A
    CP GAUGE_MAX                   ; 満タンなら赤
    LD A,GAUGE_COLOR
    JR NZ,GU_COL
    LD A,GAUGE_FULL_COLOR
GU_COL:
    LD HL,GAUGE_COLOR_ADDR : CALL WRTVRM
    LD A,C                         ; C=g
    AND 7 : LD B,A : LD A,0FFh     ; 端数パターン: 左からk px
    JR Z,GU_PMASK
GU_SHIFT:
    SRL A
    DJNZ GU_SHIFT
GU_PMASK:
    XOR 0FFh
    LD HL,GAUGE_PART_CODE*8+1 : LD B,6
GU_PROW:
    CALL WRTVRM
    INC HL
    DJNZ GU_PROW
    LD HL,1800h+12-1
    LD B,8                         ; cols12-19: f=C-8i
GU_CELL:
    INC HL
    LD A,C : ADD A,A
    LD A,GAUGE_BLANK_CODE
    JR C,GU_PUT
    INC C : DEC C : JR Z,GU_PUT
    LD A,C : CP 8
    LD A,GAUGE_FULL_CODE
    JR NC,GU_PUT                   ; f>=8: 満
    LD A,GAUGE_PART_CODE
GU_PUT:
    CALL WRTVRM
    LD A,C : SUB 8 : LD C,A
    DJNZ GU_CELL
    RET

; Z=撃てる状態(未使用+バリア1枚以上+ゲージ満タン)
; ("バリアが1枚でも残っていないとレーザーは使用できない")
LZ_QUALIFIED:
    LD A,(LZ_SPENT) : OR A
    RET NZ
    ; (2026-09-23、"無敵でチェックしたらレーザー撃ってこなくて予備動作のポッド弾収束で
    ; 無限ループした"): テストモード(GAMEOVER_ENABLED=0、タイトルBスタート)では死なない
    ; ため、条件未達だと「撃たれた瞬間に負け→カウントダウンからやり直し」を永久に
    ; 繰り返していた。テストモードではバリア・エナジーの条件を外す(1回だけは残す)。
    LD A,(GAMEOVER_ENABLED) : OR A
    RET Z
    LD A,(BARRIER_HP) : OR A
    JR Z,LZQ_NO
    CALL GAUGE_VALUE
    CP GAUGE_MAX
    RET
LZQ_NO:
    INC A                          ; NZ
    RET

; Z=Bで発射可(今フレーム押下+LZ_QUALIFIED)
LZ_CAN_FIRE:
    LD A,(FIREB_EDGE) : DEC A
    RET NZ
    JR LZ_QUALIFIED

; 毎フレーム(MAINLOOP)。ゲージ更新+BOSS_STATE==2の間だけレーザー処理。
LZ_FRAME:
    CALL GAUGE_UPDATE
    LD A,(BOSS_STATE) : CP 2
    RET NZ
    LD A,(GAME_OVER) : OR A
    JR Z,LZF_ALIVE
    XOR A : LD (LZ_CD_T),A         ; 自機死亡: カウントダウンを止め、
    LD A,(LZ_PHASE) : OR A         ; 出ているレーザー(1-3、5)を消して終了
    RET Z
    CP 4
    RET Z
    JP LZ_END
LZF_ALIVE:
    LD A,(LZ_CD_T) : OR A
    CALL NZ,LZ_COUNTDOWN
    LD A,(LZ_PHASE)
    CP 5 : JP Z,LZ_BARRAGE
    OR A : JR Z,LZ_IDLE
    DEC A : JP Z,LZ_SOLO
    DEC A : JP Z,LZ_HOLD
    DEC A : RET NZ
    ; --- 3: 干渉 ---
    ; LZ_TICK=最後にBを押してからのフレーム数(LZ_STOP_FRAMESで頭打ち)
    LD HL,LZ_TICK
    LD A,(FIREB_EDGE) : OR A
    JR Z,LZC_NOPUSH
    LD (HL),0
    LD A,(LZ_CLASH_X) : ADD A,LZ_PUSH_PX : LD (LZ_CLASH_X),A
    CALL SOUND_POD_HIT
    JR LZC_BOSS
LZC_NOPUSH:
    LD A,(HL) : CP LZ_STOP_FRAMES
    JR NC,LZC_BOSS
    INC (HL)
LZC_BOSS:
    LD A,(LZ_TICK) : CP LZ_STOP_FRAMES   ; ボスの押し込み 1px/フレーム、
    LD HL,LZ_CLASH_X                     ; 撃つのを止めていたら倍
    DEC (HL)
    JR C,LZC_SCATTER
    DEC (HL)
LZC_SCATTER:
    ; 干渉点のまわりへ4フレームごとに自機爆発を1つ(音も自機爆発)
    LD A,(TICK) : AND 3
    JR NZ,LZC_JUDGE
    CALL LZ_RND : AND 1Fh : SUB 24 : ADD A,(HL)   ; X: 干渉点-24..+7
    LD (EBUZ_EXPL_POS_X),A
    CALL LZ_RND : AND 1Fh : ADD A,LZ_ROW*8-20     ; Y: 行の中心-16..+15(左上基準)
    LD (EBUZ_EXPL_POS_Y),A
    CALL PEUA_TRY_SPAWN_AT
LZC_JUDGE:
    LD A,(LZ_CLASH_X)
    CP LZ_WIN_X
    JP NC,LZ_WIN
    SRL A : SRL A : SRL A : LD B,A
    LD A,(LZ_PCOL) : CP B
    JP NC,LZ_LOSE                  ; 干渉点が自機の先端列まで戻された
    JP LZ_DRAW_CURRENT

LZ_IDLE:
    CALL LZ_CAN_FIRE
    RET NZ
    LD A,(PLAYERY) : ADD A,8 : SRL A : SRL A : SRL A : LD (LZ_PROW),A
    CALL LZ_CALC_PCOL
    LD (LZ_PEND),A                 ; 先端は自機の前から1列/フレームで伸ばす
    LD A,LZ_SOLO_FRAMES : LD (LZ_TIMER),A
    LD A,1 : LD (LZ_PHASE),A : LD (LZ_SPENT),A
    CALL SOUND_POD_FIRE
    JP LZ_DRAW_CURRENT

LZ_SOLO:
    LD HL,LZ_TIMER : DEC (HL)
    JR NZ,LZS_ON
    CALL LZ_ERASE                  ; 100フレで尽きて消滅(使用済みのまま待機へ)
    XOR A : LD (LZ_PHASE),A
    RET
LZS_ON:
    LD A,(LZ_PROW) : CP 18         ; 先端を1列伸ばす。ボスの行(2-17)は
    LD A,26                        ; ボス左端(列26)、それより下は画面端まで
    JR C,LZS_END
    LD A,32
LZS_END:
    LD HL,LZ_PEND
    CP (HL)
    JR Z,LZS_HIT
    INC (HL)
LZS_HIT:
    CALL LZ_HIT_PODS               ; 最後のポッドを壊すとカウントダウンが始まる
    JP LZ_DRAW_CURRENT

; --- 2: ボスレーザー照射中。上下からBで割り込み、帯に入ったら即死、
; --- LZ_CUTIN_FRAMESのうちに割り込まなければゲームオーバー。
LZ_HOLD:
    CALL LZ_CAN_FIRE
    JR NZ,LZH_WAIT
    LD A,LZ_SOLO_FRAMES : LD (LZ_TIMER),A : LD (LZ_SPENT),A
    CALL LZ_START_CLASH
    JP LZ_DRAW_CURRENT
LZH_WAIT:
    LD HL,LZ_BFRONT                ; ボスレーザーの先端を1列/フレームで左へ
    LD A,(HL) : OR A
    JR Z,LZH_FULL
    DEC (HL)
LZH_FULL:
    CALL LZ_IN_BEAM
    JR C,LZ_LOSE_EXT
    LD HL,LZ_TICK : DEC (HL)
    JR Z,LZ_LOSE_EXT
    JP LZ_DRAW_CURRENT

; C=自機の当たり判定(PLAYERX,PLAYERY)-(+7,+7)がボスレーザーの帯
; (x=先端列*8-207, y64-87=行8-10)に重なっている
LZ_IN_BEAM:
    LD A,(LZ_BFRONT) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(PLAYERX) : CP 208
    JR NC,LZIB_NO
    ADD A,7 : CP B
    JR C,LZIB_NO
    LD A,(PLAYERY) : SUB 57        ; y+7>=64 かつ y<=87
    CP 31
    RET                            ; C=帯の中
LZIB_NO:
    OR A                           ; NC
    RET

LZ_WIN:
    CALL LZ_END
    JP START_BOSS_DEATH

; ボスレーザーに届かれた(割り込めなかった): 条件未達の理由を記録してから負け処理。
; (干渉で押し負けた場合はLZ_LOSEへ直接来るので理由0=通常のMISSION FAILED)
LZ_LOSE_EXT:
    CALL LZ_SET_REASON
    JR LZ_LOSE
; 条件未達の理由をLZ_FAIL_REASONへ(bit0 バリア無し、bit1 エナジー不足/使用済み)
LZ_SET_REASON:
    LD B,0
    LD A,(BARRIER_HP) : OR A
    JR NZ,LZLE_SHIELD
    INC B                          ; bit0: バリア無し
LZLE_SHIELD:
    PUSH BC
    CALL GAUGE_VALUE               ; 使用済みなら0を返す
    POP BC
    CP GAUGE_MAX
    JR Z,LZLE_ENERGY
    LD A,B : OR 2 : LD B,A         ; bit1: エナジー不足
LZLE_ENERGY:
    LD A,B : LD (LZ_FAIL_REASON),A
    RET
LZ_LOSE:
    CALL LZ_ERASE
    LD A,(GAMEOVER_ENABLED) : OR A
    JR NZ,LZL_DIE
    ; テストモード(タイトルBスタート): 死なないので、エナジーを未使用に戻して
    ; カウントダウンからやり直す(何度でも撃ち合える)。
    XOR A : LD (LZ_SPENT),A : LD (LZ_FAIL_REASON),A : LD (LZ_PHASE),A
    JP LZ_BOSS_FIRE
LZL_DIE:
    XOR A : LD (LZ_BFRONT),A
    LD A,2 : LD (LZ_PHASE),A       ; ボスレーザーを全長で描いたまま残す
    CALL LZ_DRAW_CURRENT
    LD A,4 : LD (LZ_PHASE),A
    XOR A : LD (BARRIER_HP),A      ; バリア残量に関係なくゲームオーバー
    JP PLAYER_TAKE_HIT
LZ_END:
    CALL LZ_ERASE
    LD A,4 : LD (LZ_PHASE),A
    RET

LZ_ERASE:
    LD A,1 : LD (LZ_BLANKING),A
    CALL LZ_DRAW_CURRENT
    XOR A : LD (LZ_BLANKING),A
    RET

; 現在のLZ_PHASEのレーザーを丸ごと描き直す(毎フレーム - 途中で何かに
; 上書きされても次のフレームで元に戻る)。
LZ_DRAW_CURRENT:
    LD A,(LZ_PHASE)
    CP 5 : JP Z,LZDC_5
    DEC A : JR NZ,LZDC_2
    LD A,(LZ_PROW) : LD E,A        ; 1: 自機レーザー(1行)
    LD HL,(LZ_PCOL)                ; L=PCOL,H=PEND
    LD D,255
    JP LZ_DRAW
LZDC_2:
    DEC A : JR NZ,LZDC_3
    LD A,(LZ_BFRONT) : LD L,A : LD H,26   ; 2: ボスレーザー(3行、先端-列25)
    LD D,255
    LD E,LZ_ROW-1 : CALL LZ_DRAW
    INC E : CALL LZ_DRAW
    INC E : CALL LZ_DRAW
    JR LZ_SPRITES
LZDC_3:
    DEC A : RET NZ
    LD A,(LZ_CLASH_X) : SRL A : SRL A : SRL A : LD D,A
    LD A,(LZ_PCOL) : LD L,A : LD H,26
    LD E,LZ_ROW : CALL LZ_DRAW     ; 3: 中央行 = 自機|干渉点|ボス
    LD A,(LZ_BLANKING) : PUSH AF   ; 上下の行 = 干渉点より右だけボス
    OR A : JR NZ,LZDC3_SIDE
    LD A,2 : LD (LZ_BLANKING),A
LZDC3_SIDE:
    LD E,LZ_ROW-1 : CALL LZ_DRAW
    LD E,LZ_ROW+1 : CALL LZ_DRAW
    POP AF : LD (LZ_BLANKING),A
; ボスレーザー(2/3)に付くスプライト: 右端の16x24、干渉中(3)は干渉点。
; LZ_BLANKING=1(消去)なら隠す。
LZ_SPRITES:
    LD A,(LZ_BLANKING) : DEC A
    JR Z,LZSP_HIDE
    LD BC,63*256+208 : LD DE,LZ_END_PAT*256+7
    LD A,LZ_END_SPR : CALL LZ_SPR
    LD BC,79*256+208 : LD DE,LZ_END_PAT+4*256+7
    LD A,LZ_END_SPR+1 : CALL LZ_SPR
    LD A,(LZ_PHASE) : CP 3
    RET NZ
    LD A,(LZ_CLASH_X) : AND 0F8h : SUB 4 : LD C,A
    LD B,LZ_ROW*8-5
    LD A,(TICK) : AND 1
    LD E,SPR_WHITE
    JR Z,LZSP_COL
    LD E,SPR_YELLOW
LZSP_COL:
    LD D,PAT_PLAYER_EXPLOSION
    LD A,LZ_CLASH_SPR
    JR LZ_SPR
LZSP_HIDE:
    LD BC,ENEMY_HIDE_Y*256+255
    LD A,LZ_CLASH_SPR : CALL LZ_SPR
    LD A,LZ_END_SPR : CALL LZ_SPR
    LD A,LZ_END_SPR+1
; A=スプライト番号, B=Y, C=X, D=パターン, E=色
LZ_SPR:
    ADD A,A : ADD A,A : LD L,A : LD H,SPRATR/256
    LD A,B : CALL WRTVRM : INC HL
    LD A,C : CALL WRTVRM : INC HL
    LD A,D : CALL WRTVRM : INC HL
    LD A,E : CALL WRTVRM           ; (JPで末尾呼び出しするとz80emuのBIOSスタブが効かない)
    RET

; Out: A=DFL_RNG←DFL_RNG*5+1(8bit、周期256)
LZ_RND:
    LD A,(DFL_RNG) : LD B,A
    ADD A,A : ADD A,A : ADD A,B : INC A
    LD (DFL_RNG),A
    RET

; E=行, L=開始列, H=終端列(含まない), D=干渉点の列。絵はEbuzIIのレーザー
; (L/Rの2セル弾)を途切れず撃ち続ける流れ: 毎フレーム1セルずつ送るので、
; 列の偶奇とTICKの偶奇でL/Rが入れ替わる。D列(干渉点)は空白 - 両方の弾が
; そこで消える。LZ_BLANKING: 1=全部空白(消去)、2=D列以下を空白(干渉中の
; 上下の行)。
LZ_DRAW:
    LD C,L
LZD_LOOP:
    LD A,C : CP H
    RET NC
    LD A,(TICK) : ADD A,C
    AND 1 : LD B,A
    LD A,EBUZ2_LASER_R_CODE : SUB B : LD B,A
    LD A,(LZ_BLANKING) : OR A
    JR Z,LZD_MAIN
    DEC A : JR Z,LZD_BLANK
    LD A,C : CP D
    JR C,LZD_BLANK
    JR Z,LZD_BLANK
    JR LZD_W
LZD_MAIN:
    LD A,C : CP D
    JR NZ,LZD_W
LZD_BLANK:
    LD B,BLANKCODE
LZD_W:
    PUSH DE : PUSH HL
    LD A,E : CALL EBUZ2_ADDR
    LD A,B : CALL WRTVRM
    POP HL : POP DE
    INC C
    JR LZD_LOOP

; 単独照射中(1)にボスが撃った/照射中(2)にBで割り込んだ → 干渉(3)。
; 自機をレーザー行へ固定し、自機の先端とボス左端(列26)の中間から始める。
LZ_START_CLASH:
    CALL LZ_ERASE
    LD A,PLAYER_INITY : LD (PLAYERY),A    ; (PLAYERY+8)>>3 = LZ_ROW
    CALL LZ_CALC_PCOL
    ADD A,A : ADD A,A : ADD A,4+104       ; (PCOL*8+8)/2 + 26*8/2
    LD (LZ_CLASH_X),A
    LD A,3 : LD (LZ_PHASE),A
    XOR A : LD (LZ_TICK),A
    CALL FREE_SCATTER_SPRITES      ; 飛び散り(PLAYER_EXPL)が26-29を確保できるように
    JP SOUND_EBUZ_FIRE

; 最後のポッド撃破時(POD_HIT_DESTROY)、およびテストモードでのやり直し:
; カウントダウン開始。飛んでいる通常のポッド弾は消す。
LZ_BOSS_FIRE:
    XOR A
    LD (POD_BULLET0_ACT),A : LD (POD_BULLET1_ACT),A
    LD (LZ_CB0),A : LD (LZ_CB1),A
    CALL POD_BULLET_HIDE0
    CALL POD_BULLET_HIDE1
    LD A,LZ_CD_FRAMES : LD (LZ_CD_T),A
    RET

; カウントダウン1フレーム分。T=120,90,60,30でポッド軌道上の2箇所(2k,2k+1)
; からポッド弾を出し、毎フレーム中央へ1/4ずつ寄せて、着いたら消す。T=0で発射。
LZ_COUNTDOWN:
    LD C,3
LZCD_FIND:
    SUB 30
    JR C,LZCD_MOVE
    JR Z,LZCD_LAUNCH
    DEC C
    JR LZCD_FIND
LZCD_LAUNCH:
    LD A,C : ADD A,A : PUSH AF
    CALL GET_POD_XY
    LD A,(POD_XY_X) : LD (POD_BULLET0_X),A
    LD A,(POD_XY_Y) : LD (POD_BULLET0_Y),A
    POP AF : INC A
    CALL GET_POD_XY
    LD A,(POD_XY_X) : LD (POD_BULLET1_X),A
    LD A,(POD_XY_Y) : LD (POD_BULLET1_Y),A
    LD A,1 : LD (LZ_CB0),A : LD (LZ_CB1),A
    CALL SOUND_POD_FIRE
LZCD_MOVE:
    LD A,(LZ_CB0) : OR A
    JR Z,LZCD_B1
    LD HL,POD_BULLET0_X : CALL LZ_CB_MOVE
    OR A
    JR Z,LZCD_D0
    XOR A : LD (LZ_CB0),A
    CALL POD_BULLET_HIDE0
    JR LZCD_B1
LZCD_D0:
    CALL POD_BULLET_DRAW0
LZCD_B1:
    LD A,(LZ_CB1) : OR A
    JR Z,LZCD_TICK
    LD HL,POD_BULLET1_X : CALL LZ_CB_MOVE
    OR A
    JR Z,LZCD_D1
    XOR A : LD (LZ_CB1),A
    CALL POD_BULLET_HIDE1
    JR LZCD_TICK
LZCD_D1:
    CALL POD_BULLET_DRAW1
LZCD_TICK:
    LD HL,LZ_CD_T : DEC (HL)
    RET NZ
    ; --- 発射 ---
    CALL SOUND_EBUZ_FIRE
    LD A,(LZ_PHASE) : DEC A
    JP Z,LZ_START_CLASH            ; 自機レーザー照射中 → そのまま干渉
    LD A,2 : LD (LZ_PHASE),A
    LD A,26 : LD (LZ_BFRONT),A     ; 先端は射出口(列26)から伸びていく
    LD A,LZ_CUTIN_FRAMES : LD (LZ_TICK),A
    CALL LZ_QUALIFIED
    RET Z
    LD A,(GAMEOVER_ENABLED) : OR A ; テストモード(ここへ来るのは使用済みだけ):
    JP Z,LZ_LOSE_EXT               ; 死なないので従来どおりカウントダウンからやり直し
    ; (2026-09-24、"条件未達時の即ゲームオーバーを変更 3本レーザーを1本にするが
    ; 画面Row1からRow19まで ボス中央からランダムにレーザー乱射 セルでラインを描く
    ; 感じで 特に特別処理は入れず自然に死ぬように"): 条件未達なら即ゲームオーバーに
    ; せず乱射(フェーズ5)へ。当たりはPLAYER_DAMAGE_CHECKの普通の被弾(LZ_BARRAGE_HIT)で、
    ; 死ねば理由付きの画面(LZ_FAIL_REASON)になる。
    CALL LZ_SET_REASON
    LD A,5 : LD (LZ_PHASE),A
    JP LZ_BR_START

; HL=POD_BULLETn_X(次のbyteがY)。X,Yをそれぞれ中心へ差の1/4ずつ寄せる。
; Out: A=FFh 両軸とも着いた(寄せ量0か-1)、0 まだ。
LZ_CB_MOVE:
    LD C,LZ_CB_CX : CALL LZ_APPROACH
    SBC A,A : PUSH AF
    INC HL
    LD C,LZ_CB_CY : CALL LZ_APPROACH
    SBC A,A
    POP BC
    AND B
    RET
; (HL)をCへ(C-(HL))/4(符号付き、9bit差分)だけ寄せる。Out: CF=寄せ量が0か-1(着いた)
LZ_APPROACH:
    LD B,(HL)
    LD A,C : SUB B : LD D,A
    SBC A,A : AND 0C0h : LD E,A    ; 負なら上位2bitを1で埋める
    LD A,D : SRL A : SRL A : OR E
    LD D,A
    ADD A,B : LD (HL),A
    LD A,D : INC A : CP 2
    RET

; Out: A=LZ_PCOL=(PLAYERX+16)>>3(最大20 - 干渉開始直後の勝ち判定を避ける)
LZ_CALC_PCOL:
    LD A,(PLAYERX) : ADD A,16
    JR NC,LZCP_1
    LD A,255
LZCP_1:
    SRL A : SRL A : SRL A
    CP 21 : JR C,LZCP_2
    LD A,20
LZCP_2:
    LD (LZ_PCOL),A
    RET

; 単独照射中: レーザー行に重なり先頭より右にあるポッドへ毎フレーム1ダメージ。
LZ_HIT_PODS:
    LD A,(LZ_PROW) : ADD A,A : ADD A,A : ADD A,A : LD (POD_XY_Y),A
    LD A,(LZ_PCOL) : ADD A,A : ADD A,A : ADD A,A : LD (POD_XY_X),A
    LD A,(LZ_PEND) : ADD A,A : ADD A,A : ADD A,A   ; C=先端のX(列32なら255)
    JR NC,LZHP_FRONT
    LD A,255
LZHP_FRONT:
    LD C,A
    LD B,0
LZHP_LOOP:
    PUSH BC
    LD D,0 : LD E,B
    LD HL,POD_HP : ADD HL,DE
    LD A,(HL) : OR A
    JR Z,LZHP_SKIP
    LD HL,POD_CUR_Y : ADD HL,DE
    LD A,(POD_XY_Y) : SUB (HL) : ADD A,128
    CP 116 : JR C,LZHP_SKIP
    CP 141 : JR NC,LZHP_SKIP
    LD HL,POD_CUR_X : ADD HL,DE
    LD A,(HL) : CP C               ; まだ先端が届いていない
    JR NC,LZHP_SKIP
    ADD A,12
    JR C,LZHP_HIT
    LD HL,POD_XY_X
    CP (HL) : JR C,LZHP_SKIP
LZHP_HIT:
    CALL POD_HIT
LZHP_SKIP:
    POP BC
    INC B
    LD A,B : CP 8
    JR NZ,LZHP_LOOP
    RET

; ============================================================================
; (2026-09-24) 自機ショット1発ぶんの処理(旧"shot 0"〜"shot 2"の3つの複製を1本に)。
; BULLET_EACHがBULLETC_*へスロットをコピーしてから呼び、終わったら書き戻す。
; ============================================================================
; IN: HL=各スロットで呼ぶ処理。ACT!=0のスロットだけ、BULLETC_*へコピー→CALL→書き戻し。
BULLET_EACH:
    LD (BULLET_EACH_FN),HL
    LD HL,BULLET_POOL
    XOR A
BE_LOOP:
    LD (BULLET_CUR_IDX),A
    LD (BULLET_CUR_PTR),HL
    LD A,(HL)
    OR A
    JR Z,BE_NEXT
    LD DE,BULLETC_ACT : LD BC,6 : LDIR
    CALL BE_CALL
    LD HL,BULLETC_ACT : LD DE,(BULLET_CUR_PTR) : LD BC,6 : LDIR
BE_NEXT:
    LD HL,(BULLET_CUR_PTR) : LD DE,6 : ADD HL,DE
    LD A,(BULLET_CUR_IDX) : INC A : CP BULLET_SLOTS
    JR C,BE_LOOP
    RET
BE_CALL:
    LD HL,(BULLET_EACH_FN)
    JP (HL)

; --- shots: advance 1 character (8 dots) per frame (see MAINLOOP) ---
BULLET_STEP:
    LD A,(BULLETC_COL) : LD B,A
    LD A,(BULLETC_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_A
    OR A
    JR NZ,BS_ISHIT
    LD A,(BULLETC_COL) : LD B,A
    LD A,(BULLETC_ROW) : LD C,A
    CALL CHECK_BULLET_VS_FORMATION_B
    OR A
    JR NZ,BS_ISHIT
    CALL CHECK_BULLET_VS_ENEMY3
    OR A
    JR NZ,BS_ISHIT
    LD A,(BULLETC_COL) : LD B,A
    LD A,(BULLETC_ROW) : LD C,A
    CALL CHECK_BULLET_VS_ENEMY6
    OR A
    JR NZ,BS_ISHIT
    CALL CHECK_BULLET_VS_EBUZ
    OR A
    JR NZ,BS_ISHIT
    CALL CHECK_BULLET_VS_EBUZ2
    OR A
    JR NZ,BS_ISHIT
    CALL CHECK_BULLET_VS_ENEMY_POOL
    OR A
    JR Z,BS_NOHIT
BS_ISHIT:
    ; a shot's row can never reach the ground scroller (see
    ; PLAYER_MAXY) - always restore sky on erase.
    LD HL,(SKY_VEC_H) : PUSH HL : RET
BULLETC_HITERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLETC_ADDR)
    LD A,(BULLETC_COL) : LD E,A : LD D,0 : ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : LD (BULLETC_ACT),A
    EI
    RET
BS_NOHIT:
    LD HL,(SKY_VEC_E) : PUSH HL : RET
BULLETC_ERASE_GOT:
    LD (TEMP_ERASE_BYTE),A
    LD HL,(BULLETC_ADDR)
    LD A,(BULLETC_COL) : LD E,A : LD D,0 : ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(TEMP_ERASE_BYTE) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(BULLETC_COL) : INC A : LD (BULLETC_COL),A
    CP BULLET_MAXCOL+1
    EI
    JR NC,BS_OFF
    LD HL,(BULLETC_ADDR)
    LD A,(BULLETC_COL) : LD E,A : LD D,0 : ADD HL,DE
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(BULLETC_PAT) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET
BS_OFF:
    XOR A : LD (BULLETC_ACT),A
    RET

; 空いているスロット1つにつきBULLET_IDLE_T(約)だけ空回りする(BULLET_IDLE_Tの説明参照)。
BULLET_IDLE_PAD:
    LD HL,BULLET_POOL : LD DE,6 : LD A,BULLET_SLOTS
BIP_LOOP:
    PUSH AF
    LD A,(HL)
    OR A
    JR NZ,BIP_NEXT
    LD BC,BULLET_IDLE_LOOPS
BIP_WAIT:
    DEC BC
    LD A,B
    OR C
    JR NZ,BIP_WAIT
BIP_NEXT:
    ADD HL,DE
    POP AF
    DEC A
    JR NZ,BIP_LOOP
    RET

; ============================================================================
; (2026-09-24) 条件未達時のボスの乱射(LZ_PHASE=5)。ボス中央(列25、行LZ_ROW)から
; 画面左端(列0)まで、行1-19のランダムな行へ向けて1本幅のレーザーをセルで線を
; 引くように伸ばす。"もっと間を置かず 1本うち終わり待つのではなく レーザーで埋め
; 尽くす感じで": LZ_BR_SLOTS本を撃ち始めをずらして同時に回し、1本が伸び切って
; LZ_BR_HOLDフレームで消えたらその場で次を撃つ。
; ============================================================================
LZ_BR_START:
    LD HL,LZ_BR_BASE : LD (LZ_BR_CUR),HL
    LD A,LZ_BR_SLOTS : LD (LZ_BR_K),A
    LD C,26
LBS_LOOP:
    PUSH BC
    CALL LZ_BR_NEW
    POP BC
    LD HL,(LZ_BR_CUR) : LD (HL),C  ; 撃ち始めをずらす(先端26以上=まだ画面外)
    LD A,C : ADD A,LZ_BR_STAGGER : LD C,A
    CALL LZ_BR_NEXT
    JR NZ,LBS_LOOP
    JP LZ_DRAW_CURRENT

; LZ_BR_CURを次の1本へ。Out: Z=全部終わった(LZ_BR_CURは先頭へ戻る)
LZ_BR_NEXT:
    LD HL,(LZ_BR_CUR) : LD DE,LZ_BR_SIZE : ADD HL,DE : LD (LZ_BR_CUR),HL
    LD HL,LZ_BR_K : DEC (HL)
    RET NZ
    LD HL,LZ_BR_BASE : LD (LZ_BR_CUR),HL
    LD A,LZ_BR_SLOTS : LD (LZ_BR_K),A
    XOR A
    RET

LZ_BARRAGE:
LZB_LOOP:
    LD HL,(LZ_BR_CUR)
    LD A,(HL) : OR A
    JR Z,LZB_HOLD
    SUB LZ_BR_SPEED
    JR NC,LZB_SETF
    XOR A
LZB_SETF:
    LD (HL),A
    JR LZB_NEXT
LZB_HOLD:
    INC HL : DEC (HL)
    JR NZ,LZB_NEXT
    LD A,1 : LD (LZ_BLANKING),A    ; 伸び切って時間切れ: 消してすぐ次を撃つ
    CALL LZ_BR_DRAW1
    XOR A : LD (LZ_BLANKING),A
    CALL LZ_BR_NEW
LZB_NEXT:
    CALL LZ_BR_NEXT
    JR NZ,LZB_LOOP
    JP LZ_DRAW_CURRENT             ; 全部描き直す(消した線と重なっていたセルも戻る)

; LZ_BR_CURの1本を新しく: 目標の行(1-19)を決め、列25→0の各列の行をブレゼンハムで
; +2..+27へ(|行の差|<=10<25なので1列に最大1行ずつ)。
LZ_BR_NEW:
    CALL LZ_RND : LD C,A           ; 乱数(下位bitの周期が短いのでTICKを混ぜ、19の余り)
    LD A,(TICK) : ADD A,A : ADD A,A : ADD A,C
LBN_MOD:
    SUB 19
    JR NC,LBN_MOD
    ADD A,19+1                     ; 1..19
    SUB LZ_ROW
    LD C,1
    JR NC,LBN_ABS
    XOR 0FFh : INC A
    LD C,0FFh
LBN_ABS:
    LD B,A                         ; B=|行の差|, C=±1
    LD HL,(LZ_BR_CUR) : LD DE,2+25 : ADD HL,DE
    LD D,LZ_ROW                    ; 行
    LD E,12                        ; 誤差
    LD A,26 : LD (LZ_BR_CNT),A
LBN_LOOP:
    LD (HL),D
    DEC HL
    LD A,E : SUB B
    JR NC,LBN_NOSTEP
    ADD A,25
    LD E,A
    LD A,D : ADD A,C : LD D,A
    JR LBN_NEXT
LBN_NOSTEP:
    LD E,A
LBN_NEXT:
    LD A,(LZ_BR_CNT) : DEC A : LD (LZ_BR_CNT),A
    JR NZ,LBN_LOOP
    LD HL,(LZ_BR_CUR)
    LD (HL),26 : INC HL
    LD (HL),LZ_BR_HOLD
    JP SOUND_EBUZ_FIRE

; 乱射レーザーを全部描く(LZ_BLANKING=1なら消す)。
LZDC_5:
    CALL LZ_BR_DRAW1
    CALL LZ_BR_NEXT
    JR NZ,LZDC_5
    JP LZ_SPRITES
; LZ_BR_CURの1本を先端列から列25まで1セルずつ
LZ_BR_DRAW1:
    LD HL,(LZ_BR_CUR) : LD A,(HL)
LBD_LOOP:
    CP 26
    RET NC
    PUSH AF
    LD HL,(LZ_BR_CUR) : INC HL : INC HL : LD E,A : LD D,0 : ADD HL,DE : LD E,(HL)
    POP AF
    PUSH AF
    LD L,A : LD H,A : INC H : LD D,255
    CALL LZ_DRAW
    POP AF
    INC A
    JR LBD_LOOP

; PLAYER_DAMAGE_CHECKから: 乱射中(5)、描かれたレーザーのセルが自機の当たり判定
; (PLAYERX,PLAYERY)-(+7,+7)に重なっていればA!=0。
LZ_BARRAGE_HIT:
    LD A,(LZ_PHASE) : CP 5
    JR NZ,LZBH_NO
LZBH_SLOT:
    LD A,(PLAYERX) : SRL A : SRL A : SRL A
    CALL LZBH_COL
    JR NZ,LZBH_HIT
    LD A,(PLAYERX) : ADD A,7
    JR C,LZBH_SKIP
    SRL A : SRL A : SRL A
    CALL LZBH_COL
    JR NZ,LZBH_HIT
LZBH_SKIP:
    CALL LZ_BR_NEXT
    JR NZ,LZBH_SLOT
LZBH_NO:
    XOR A
    RET
LZBH_HIT:
    LD HL,LZ_BR_BASE : LD (LZ_BR_CUR),HL     ; 途中で抜けるのでループ位置を戻す
    LD A,LZ_BR_SLOTS : LD (LZ_BR_K),A
    LD A,1 : OR A
    RET
; A=列。LZ_BR_CURの1本がその列に描かれていて、その行が自機の行範囲に入っていればNZ
LZBH_COL:
    CP 26
    JR NC,LZBH_ZERO
    LD HL,(LZ_BR_CUR)
    CP (HL)
    JR C,LZBH_ZERO
    INC HL : INC HL : LD E,A : LD D,0 : ADD HL,DE : LD B,(HL)
    LD A,(PLAYERY) : SRL A : SRL A : SRL A : LD C,A    ; 自機の上の行
    LD A,B : SUB C
    JR C,LZBH_ZERO
    LD D,A
    LD A,(PLAYERY) : ADD A,7 : SRL A : SRL A : SRL A : SUB C   ; 下の行-上の行
    CP D
    JR C,LZBH_ZERO
    LD A,1 : OR A
    RET
LZBH_ZERO:
    XOR A
    RET

; (2026-09-24、"E2で離れた位置から弾撃ってきたり、倒した後に撃ってる"): 旧コードは編隊の
; 弾を常に1機目(U0)の位置から撃っており、U0を倒した後も見えない位置から撃っていた。
; HL=編隊のU0_STATE(STATE,X,Y,TOP,BOTの5byte×3機)。生きている最初の機(STATE=1かつ
; TOP/BOTのどちらかが残っている)の位置から撃つ。全滅なら撃たない。
E2_FIRE_FROM_ALIVE:
    LD B,3
EFA_LOOP:
    LD A,(HL) : DEC A
    JR NZ,EFA_NEXT
    PUSH HL
    INC HL : LD D,(HL)
    INC HL : LD E,(HL)
    INC HL : LD A,(HL)
    INC HL : OR (HL)
    POP HL
    JP NZ,SPAWN_EBULLET
EFA_NEXT:
    LD DE,5 : ADD HL,DE
    DJNZ EFA_LOOP
    RET

; (2026-09-24、"ウェーブは?"): 上下2パーツ(E_TOP=左上8x8、E_BOT=右下8x8)の敵は両方倒しても
; 消えずに見えないまま左端まで飛び続けるので、撃つ時は残っているパーツを見る。
; IN: IX=敵、D,E=左上のX,Y。上が残っていれば(D,E)、下だけなら(D+8,E+8)から撃つ。
; 両方倒されていれば撃たない。
; Fighter(TYPE_ENEMY4)は上下パーツではなく耐久値で管理していて(E_TOP/E_BOTは0のまま)、
; 撃破すれば枠ごと消えるので、パーツを見ずにそのまま撃つ。
FIRE_FROM_QUAD:
    LD A,(IX+E_TYPE) : CP TYPE_ENEMY4
    JP Z,SPAWN_EBULLET
    LD A,(IX+E_TOP) : OR A
    JP NZ,SPAWN_EBULLET
    LD A,(IX+E_BOT) : OR A
    RET Z
    LD A,D : ADD A,8 : LD D,A
    LD A,E : ADD A,8 : LD E,A
    JP SPAWN_EBULLET
