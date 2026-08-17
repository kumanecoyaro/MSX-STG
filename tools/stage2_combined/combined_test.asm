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
; a diagonal/U shot decrements ROW every frame as it climbs and had no
; upper bound beyond "row0", letting it fly straight into rows0-1 -
; where the score/counter/calibration-strip HUD lives - drawing a
; bullet pattern over a HUD cell, then erasing it to plain sky on the
; next frame (see ERASE_BULLET_CELL's "row<19 -> sky" rule, correct
; for open sky but not for permanent HUD content) instead of restoring
; whatever HUD glyph was actually there. Reported as the calibration
; strip's hex labels vanishing one cell at a time - "カラーバーAから
; F消えたぞ" - exactly the columns a bullet happened to pass through
; while climbing. Fixed by simply never letting a bullet's row go
; below this (rows0-1 are permanently off-limits, gameplay starts at
; row2).
BULLET_MIN_ROW    EQU 2
BULLET_MAXCOL     EQU 31        ; last valid name-table column (0-31)
BULLET_MUZZLE_DX  EQU 24        ; spawn column offset from TANK_X (muzzle, right side of the tank)
BULLET_MUZZLE_DX_LEFT EQU 7     ; mirrored muzzle offset for a left-facing shot (32-1-24)
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
; left-facing (mirrored) shot patterns, same 2 color groups (color
; doesn't depend on facing, only the pattern shape does) - "今の自機
; と弾を左操作で左向きに...反転パターンはそっちで生成してくれ".
BULLETF_L_SKY_CODE  EQU 90
BULLETU_L_SKY_CODE  EQU 91
BULLETF_L_ROCK_CODE EQU 98
BULLETU_L_ROCK_CODE EQU 99
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
; frames left before another shot can fire while A is held ("間欠連射
; ...1発打ったら1発空ける" - hold-to-auto-fire, but rate-limited
; rather than one every single frame) - see UPDATE_SHOT. Tunable;
; picked with no more precise spec than "leave a gap" ("ダメなら修正
; する" - happy to retune if this cadence isn't right).
SHOT_COOLDOWN EQU 0F24Eh
SHOT_COOLDOWN_FRAMES EQU 8
; 3 shot slots, 7 bytes each: +0 ACT, +1 TYPE(0=F straight,1=U
; diagonal), +2 COL, +3 ROW, +4 ADDR_LO, +5 ADDR_HI (name-table row
; base address, from BULLET_ROWADDR_LO/HI), +6 FACING(0=right,1=left,
; copied from TANK_FACING at spawn) - same pool-of-3 design as
; BULLET0/1/2 in src/CYBER SHMUP.asm ("Stage1と同様に制限数画面内3発").
BULLET0_ACT   EQU 0F250h
BULLET1_ACT   EQU 0F257h
BULLET2_ACT   EQU 0F25Eh
BULLET_TEMP_BYTE EQU 0F265h

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

; ---------- facing (left/right flip) ----------
; "今の自機と弾を左操作で左向きに...発射ボタンのAが押されてなくて
; 左右移動ならその向きを向くように...Aボタンは向きのロックだな" -
; see UPDATE_TANK_XY (updates this), UPDATE_POSE/UPDATE_TANK_SPRITES
; (consume it for the tank), TRY_SPAWN_BULLET (consumes it for shots).
TANK_FACING   EQU 0F249h    ; 0=right, 1=left
UTS_COLOR_0   EQU 0F24Ah    ; UPDATE_TANK_SPRITES scratch: per-slot color, swapped when facing left
UTS_COLOR_1   EQU 0F24Bh
UTS_COLOR_2   EQU 0F24Ch
UTS_COLOR_3   EQU 0F24Dh

; ---------- score/counter + calibration HUD (row0-1) ----------
; "スコアとカウンター Stage1の物をそのまま流用" - SCORE/SCORE_DIGITS/
; SCORE_DISPLAY and GAME_TICK/GAME_TICK_DISPLAY are ported from
; src/CYBER SHMUP.asm essentially unchanged (same 24-bit-aware digit
; algorithm, same real_score/100 + forced-"00" trick, same row0
; cols0-7/cols29-31 layout) - only the RAM addresses and the per-cell
; VRAM writer (WRITE_HUD_CELL, below - this ROM has no NAMEBUF for
; rows0-1 since the ground scroller never touches them, so it's a
; plain single-cell write, unlike WRITE_ANIM_CELL's NAMEBUF mirroring).
; Originally wired to +1 per shot fired (no enemy existed yet to
; award it properly) - reported as wrong once it was actually visible
; ("弾打っただけでスコア入ってるぞ"), and fixed here now that a real
; scoring event (a hit) exists - see ENEMY_HIT_CHECK/SCORE_PER_KILL.
;
; Between the score and the counter, row0 cols8-23 show 16 solid color
; cells (palette index 0-15, left to right) and row1 cols8-23 show
; their hex labels "0123456789ABCDEF" underneath - a calibration strip
; since the actual colors can only be judged on real hardware
; ("カラーは実機で合わせてるんで実際見ないとわからないんで").
GAME_TICK     EQU 0F266h   ; 2 bytes
SCORE         EQU 0F268h   ; 3 bytes: low word at +0, high byte at +2 (real score = SCORE*100)
SCORE_DIGITS  EQU 0F26Bh   ; 6 bytes
HUD_ROW       EQU 0F271h   ; WRITE_HUD_CELL scratch
HUD_COL       EQU 0F272h
HUD_VAL       EQU 0F273h
HUD_TEMP_BYTE EQU 0F274h
SND_TIMER     EQU 0F275h   ; shot-sound fade countdown/volume (channel A, noise)
; explosion-sound fade countdown/volume - its own channel (B) rather
; than reusing channel A, since a shot fired right before a kill would
; otherwise fight the same envelope/timer - "爆発音追加 Stage1の
; 爆発音流用" (SOUND_DESTROY below reuses that file's exact
; period(20)/timer(15) values, just retargeted to channel B).
SND_TIMER_B   EQU 0F276h
; last-drawn hundreds/tens/ones digit for GAME_TICK_DISPLAY - unlike
; src/CYBER SHMUP.asm (which can afford an unconditional redraw every
; frame), this ROM has no vsync/HALT frame sync at all, so every extra
; per-frame VRAM write directly slows the whole game's real-time pace
; down (more T-states/iteration = fewer iterations/second = everything
; TICK-paced runs slower) - redrawing 3 cells every single frame when
; usually only the ones digit actually changed was real, avoidable
; cost. Init to 0FFh (never a real digit) so the very first call still
; draws all 3 - see GAME_TICK_DISPLAY.
GTD_LAST_H    EQU 0F277h
GTD_LAST_T    EQU 0F278h
GTD_LAST_O    EQU 0F279h
; digit0 code; digitN = DIGIT_BASE+N for N=0-9 (score/counter, glyphs
; copied byte-for-byte from src/CYBER SHMUP.asm's own DIGIT_PATTERNS -
; "スコアの数字流用") and N=10-15 = A-F (new art, "AからFまで新規",
; for the calibration strip's hex labels) - all 16 fit in exactly 2
; groups (13-14), so one base covers the whole 0-F range.
DIGIT_BASE       EQU 104
HUD_DIGIT_COLORBYTE EQU 0F1h   ; fg15 white/bg1 black - same as Stage1's own digit groups ("背景色はブラックで")
SCORE_PER_KILL   EQU 1         ; ADD_SCORE units of 100 real points - "当たったら100点"
SWATCH_ROW       EQU 0
SWATCH_COL0      EQU 8
HEXLABEL_ROW     EQU 1
HEXLABEL_COL0    EQU 8
PSG_ADDR         EQU 0A0h
PSG_DATA         EQU 0A1h
; short/high-pitched noise burst for a shot "pyu" - "ノイズｃｈで弾
; 発射音ぽいの" (noise channel, shot-sound-like); period/fade picked
; with no more precise spec than that, easy to retune.
SHOT_NOISE_PERIOD EQU 8
; must stay LESS than the auto-fire period (SHOT_COOLDOWN_FRAMES+1 = 9
; frames between shots) - was 10, which never actually reached 0
; (decays 10->1 over the 9-frame gap, then jumps straight back to 10)
; so held-fire sounded permanently "on" instead of a series of
; distinct blips - "サウンドも弾打ったら出っぱなしだ".
SHOT_SND_FRAMES   EQU 6

; ---------- enemy (ZacoII) ----------
; "では次敵の実装 スプライトで実装 右から左へスライド Skyのみのの
; 位置に出現 現状はランダム 地形も合わせてスケジュールエディタで
; 対応予定 移動は自機位置をみて手前で引き返す 引き返す際の左右反転
; キャラを生成 弾が当たっての爆発はStage1と同じ16x16のスプライト
; 流用 当たったら100点 敵の管理や制御はStage1を流用" - later promoted
; from test scaffolding to the real thing ("敵は仮実装じゃなく出来た
; ら本採用 きちんとクラスにしてあるな? 管理もバッファ経由だぞ 個別に
; 適当にやるなよ"): a genuine ENEMY_POOL buffer (base address +
; ENEMY_SLOT_SIZE stride x ENEMY_SLOT_COUNT slots), walked with a
; single HL-indexed DJNZ loop everywhere (ALLOC_ENEMY_SLOT scanning for
; a free one, UPDATE_ENEMIES iterating all of them, CHECK_BULLET_VS_
; ENEMY's own enemy-side loop) - not 3 separately-named slots checked/
; called individually by hand. Field access goes through named E_xxx
; offset constants (below), the same idiom and even the same names as
; src/CYBER SHMUP.asm's own ENEMY_POOL/E_ACT/E_X/E_Y/ALLOC_ENEMY_SLOT -
; intentionally, so this slots into that file's real system later with
; minimal renaming. Still scaled down to what one behavior/type needs
; (no E_TYPE/E_BEHAVIOR dispatch table, no HP - "当たったら100点"
; implies a single hit kills), and still fixed 1:1 onto hw sprite
; slots4-6 rather than that file's flexible ALLOC_SPRITE_NUM (this
; test only ever has 3 enemies on screen at once, so a fixed mapping
; needs no separate allocator - E_SPRIDX is simply set once at INIT).
E_ACT     EQU 0   ; 0=off,1=alive,2=exploding
E_X       EQU 1
E_Y       EQU 2
E_RETREAT EQU 3   ; 0/1 - see ENEMY_TURNBACK_MARGIN
E_TIMER   EQU 4   ; EXPLODE_TIMER while E_ACT=2
E_SPRIDX  EQU 5   ; 0..ENEMY_SLOT_COUNT-1, fixed hw sprite pool index (set once at INIT)
E_VARIANT EQU 6   ; 0=green,1=red - see ENEMY_SPAWN_COUNT below, "10機出たら色替えの赤いZakoII"
E_DX      EQU 7   ; signed, post-hit explosion drift - see EXPLODE_DIR_DX/DY
E_DY      EQU 8
ENEMY_SLOT_SIZE  EQU 9
ENEMY_SLOT_COUNT EQU 3   ; same "3 concurrent" convention as the bullet pool
ENEMY_POOL    EQU 0F280h   ; ENEMY_SLOT_SIZE*ENEMY_SLOT_COUNT = 27 bytes
ENEMY_SPAWN_TIMER   EQU 0F29Bh
; total enemies spawned so far (capped at 10, never decremented) -
; "で、10機出たら色替えの赤いZakoII...アルゴリズムは同じ": once this
; reaches 10, every spawn after is the red variant instead of green -
; same movement/turn-back logic either way (ENEMY_GET_STEP is the only
; place VARIANT changes behavior, for speed; UOE_DRAW picks the color).
ENEMY_SPAWN_COUNT   EQU 0F29Ch
; staging buffer for the 3 enemy hw sprite slots (4-6, right after the
; tank's own 0-3) - same "build in RAM, blast once" pattern as
; SPRITE_ATTRS/UTS_OUT_LOOP, just a separate buffer so the two flushes
; stay independent.
ENEMY_SPRITE_ATTRS EQU 0F29Dh   ; 12 bytes: Y,X,pat,col x3
ENEMY_SPR_BASE_SLOT EQU 4       ; hw sprite index slot0 uses; slotN -> ENEMY_SPR_BASE_SLOT+N

; green (normal) variant speed: "自機と同じ1.5で" - same alternating
; 1/2-px-per-frame trick as TANK_SPEED_LO (see UTX_DO_RIGHT/LEFT),
; averaging 1.5px/frame - was a flat 1 ("スピードが遅いんで早くして").
ENEMY_SPEED_LO  EQU 1
ENEMY_SPEED_RED EQU 2   ; red variant: flat 2px/frame - "こいつは速度2で"
ENEMY_SPAWNX      EQU 240   ; off the right edge (16px sprite, so fully offscreen at spawn) - "右から左へスライド"
; "移動は自機位置をみて手前で引き返す" - turns back once within this
; many px of the tank, short of actually reaching it. Picked with no
; more precise spec than "before reaching" - easy to retune.
ENEMY_TURNBACK_MARGIN EQU 40
; "Skyのみのの位置に出現...現状はランダム" - Y confined to a band
; safely inside the open sky (below the HUD rows0-1 at y0-15, well
; above row19's ground top at y152) using a TICK-derived pseudo-random
; low byte (AND with a power-of-2 span so it's a plain mask, no
; divide) - a placeholder until terrain-aware spawning exists ("地形も
; 合わせてスケジュールエディタで対応予定").
ENEMY_SKY_Y_MIN   EQU 24
ENEMY_SKY_Y_MASK  EQU 3Fh   ; span 64 -> Y in [24,88), sprite bottom never past y151
ENEMY_SPAWN_INTERVAL EQU 90 ; frames between spawns while a slot is free - untuned
ENEMY_COLOR       EQU 12    ; green, from sprites/ZacoII.json's own fg
ENEMY_RED_COLOR   EQU 9     ; light red - "色替えの赤いZakoII" (kept distinct from the explosion's own medium red)
; PAT_ZACO/_FLIP (enemy_gen.py) and PAT_EXPLOSION (below) each need 4
; consecutive hw sprite pattern numbers (32 bytes / 8 = 4, 16x16 mode)
; - placed right after the tank's own 128 (4 poses x 2 facings x 16 -
; see tank_gen.py's POSE_FLIP_OFFSET), aligned to 4 as convention. The
; red variant reuses the SAME art (only its color attribute differs -
; "アルゴリズムは同じ" applies to the sprite too, not just movement).
PAT_ZACO          EQU 128
PAT_ZACO_FLIP     EQU 132
PAT_EXPLOSION     EQU 136
EXPLOSION_COLOR    EQU 8    ; medium red - same color src/CYBER SHMUP.asm uses for EXPLOSION_PATTERN
; frames - briefly cut to 8, reverted to 20 (src/CYBER SHMUP.asm's own
; value) once seen ("んー２０でいいわ"), but that read was made while
; the DJNZ/B-register corruption bug (see README) was still silently
; running the enemy loop a wrong number of times per frame - once that
; was actually fixed, 20 read as too long after all ("バグってたから
; か爆発かなり長いわ"), settling back on 8 with the drift speed
; (EXPLODE_DIR_DX/DY's own +-2px/frame magnitude, unchanged throughout
; all of this) explicitly confirmed too - "8フレでスピードは２ｐｘで
; いいわ" - for a total drift of 8*2=16px along a cardinal direction
; ("なので爆発は１６ｐｘ移動だな"). UOE_EXPLODE_DRIFT/UOE_DRAW_EXPLOSION
; still run every single frame this counts down (not just on trigger) -
; see UPDATE_ONE_ENEMY/UPDATE_ENEMIES, called unconditionally from
; MAINLOOP each frame - so the drift stays smooth regardless of length.
EXPLOSION_DURATION EQU 8

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
    ; mirrored (left-facing) poses - "反転パターンはそっちで生成して
    ; くれ" (tank_gen.py's own POSE_FLIP_OFFSET quadrants).
    LD HL,TANK_TANKF_L_TL    : LD DE,PAT_TANKF_L*8+SPRPAT    : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUP_L_TL   : LD DE,PAT_TANKUP_L*8+SPRPAT   : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKFGAP_L_TL : LD DE,PAT_TANKFGAP_L*8+SPRPAT : LD BC,128 : CALL LDIRVM
    LD HL,TANK_TANKUGAP_L_TL : LD DE,PAT_TANKUGAP_L*8+SPRPAT : LD BC,128 : CALL LDIRVM

    ; bullet BG patterns: each loaded twice, once per background color
    ; group it can appear over (see BULLETF_SKY_CODE etc. above), and
    ; the mirrored (left-facing) shapes the same way at their own codes.
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN : LD DE,BULLETU_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN : LD DE,BULLETU_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN : LD DE,BULLETF_L_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_L_PATTERN : LD DE,BULLETU_L_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN : LD DE,BULLETF_L_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_L_PATTERN : LD DE,BULLETU_L_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM

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
    LD (TANK_FACING),A
    LD (PREV_TRIGB),A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
    LD (JUMP_Y_OFFSET),A
    LD A,PAT_TANKF : LD (CUR_POSE_PAT),A
    XOR A
    LD (SHOT_COOLDOWN),A
    LD (BULLET0_ACT),A
    LD (BULLET1_ACT),A
    LD (BULLET2_ACT),A

    ; overwrites slots 0-3 (the tank's own) with real data; slots 4-31
    ; stay hidden from the full clear above.
    CALL UPDATE_TANK_SPRITES

    ; checkpoint 7: tank sprite attributes written
    LD B,7 : LD C,7 : CALL WRTVDP

    ; digit/hex glyphs (16 consecutive codes, DIGIT_BASE=104-119) and
    ; their shared color (groups13-14, both white/black).
    LD HL,DIGIT_PATTERNS_LOCAL : LD DE,DIGIT_BASE*8 : LD BC,128 : CALL LDIRVM
    LD A,HUD_DIGIT_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+13 : LD BC,1 : CALL LDIRVM
    LD A,HUD_DIGIT_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+14 : LD BC,1 : CALL LDIRVM

    ; color-cell strip: one representative code per group (120,128,...,
    ; 240 - groups15-30), pattern left blank (all-zero) so only that
    ; group's own color-table byte shows; SWATCH_COLORS below sets each
    ; group's byte to (i<<4)|i so fg/bg both read as palette index i
    ; regardless of which nibble a blank glyph would have shown.
    LD HL,HUD_ZERO8 : LD DE,120*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,128*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,136*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,144*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,152*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,160*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,168*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,176*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,184*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,192*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,200*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,208*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,216*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,224*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,232*8 : LD BC,8 : CALL LDIRVM
    LD HL,HUD_ZERO8 : LD DE,240*8 : LD BC,8 : CALL LDIRVM
    LD HL,SWATCH_COLORS : LD DE,2000h+15 : LD BC,16 : CALL LDIRVM

    ; name-table: swatch codes at row0 cols8-23, hex labels at row1 cols8-23
    LD HL,SWATCH_CODES : LD DE,1800h+SWATCH_COL0 : LD BC,16 : CALL LDIRVM
    LD HL,HEXLABEL_CODES : LD DE,1800h+32+HEXLABEL_COL0 : LD BC,16 : CALL LDIRVM

    ; PSG: channel A = noise-only (shot sound), channel B = noise-only
    ; too (explosion sound - its own channel so a shot's envelope never
    ; fights an overlapping explosion's, see SND_TIMER_B); channel C
    ; left silent (volume 0) since nothing here uses it. Mixer 0E7h =
    ; tones A/B/C all off, noise A+B on, noise C off (was 0B1h, tone
    ; B/C left enabled but silent via volume=0 - tightened now that
    ; channel B actually carries a sound).
    LD A,7 : OUT (PSG_ADDR),A
    LD A,0E7h : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    XOR A : LD (SND_TIMER),A : LD (SND_TIMER_B),A
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A

    XOR A
    LD (GAME_TICK),A : LD (GAME_TICK+1),A
    LD (SCORE),A : LD (SCORE+1),A : LD (SCORE+2),A
    LD A,0FFh : LD (GTD_LAST_H),A : LD (GTD_LAST_T),A : LD (GTD_LAST_O),A
    CALL SCORE_DISPLAY
    CALL GAME_TICK_DISPLAY

    ; checkpoint 8: HUD (score/counter/calibration strip) + PSG set up
    LD B,8 : LD C,7 : CALL WRTVDP

    ; enemy (ZacoII) sprite patterns + explosion, one hw sprite pattern
    ; slot each (128/132/136 - right after the tank's own 0-127).
    LD HL,ENEMY_ZACOII : LD DE,PAT_ZACO*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ENEMY_ZACOII_FLIP : LD DE,PAT_ZACO_FLIP*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,EXPLOSION_PATTERN : LD DE,PAT_EXPLOSION*8+SPRPAT : LD BC,32 : CALL LDIRVM

    ; enemy pool: zero the whole buffer generically (all slots inactive,
    ; all other fields 0) rather than naming each slot - "管理もバッファ
    ; 経由だぞ 個別に適当にやるなよ" - then a 2nd pass sets each slot's
    ; own fixed E_SPRIDX (never touched again, see ENEMY_SPR_BASE_SLOT).
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_SIZE*ENEMY_SLOT_COUNT
    XOR A
IEZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IEZ_LOOP
    LD (ENEMY_SPAWN_TIMER),A
    LD (ENEMY_SPAWN_COUNT),A

    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
    LD C,0
IESP_LOOP:
    PUSH HL
    POP IX
    LD A,C : LD (IX+E_SPRIDX),A
    INC C
    LD DE,ENEMY_SLOT_SIZE : ADD HL,DE
    DJNZ IESP_LOOP

    ; the hw sprite attribute table itself is already hidden for
    ; slots4-6 too (the earlier full 32-slot clear covers them along
    ; with the tank's own 0-3), but ENEMY_SPRITE_ATTRS (the RAM staging
    ; buffer UPDATE_ENEMIES blasts from every frame) starts blank, so
    ; it must be primed with the same hidden Y or the first flush
    ; would show garbage at Y=0.
    LD HL,ENEMY_SPRITE_ATTRS
    LD B,ENEMY_SLOT_COUNT
IESA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IESA_LOOP

    ; checkpoint 9: enemy patterns + pool set up - about to enter MAINLOOP
    LD B,9 : LD C,7 : CALL WRTVDP

    ; border back to black - checkpoints 1-9 above were diagnostic
    ; only, leaving it on whatever the last one was (blue) would
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
    CALL UPDATE_ENEMIES
    CALL CHECK_BULLET_VS_ENEMY

    LD HL,(GAME_TICK) : INC HL : LD (GAME_TICK),HL
    CALL GAME_TICK_DISPLAY
    CALL SOUND_UPDATE

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

    ; facing: follows movement direction, unless A (fire) is held -
    ; "発射ボタンのAが押されてなくて左右移動ならその向きを向くように
    ; ...Aボタンは向きのロックだな" - only updates on actual movement
    ; input (TANK_DX!=0); with no movement (or A held), facing simply
    ; stays whatever it last was.
    LD A,(JOY_TRIGA)
    OR A
    JR NZ,UTX_FACING_DONE
    LD A,(TANK_DX)
    OR A
    JR Z,UTX_FACING_DONE
    CP 1
    JR NZ,UTX_FACE_LEFT
    XOR A : LD (TANK_FACING),A
    JR UTX_FACING_DONE
UTX_FACE_LEFT:
    LD A,1 : LD (TANK_FACING),A
UTX_FACING_DONE:

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
    ; TANK_POSE_FLIP_OFFSET (64, from tank_gen.py) reaches the mirrored
    ; left-facing version of whichever pose was just picked -
    ; "今の自機と弾を左操作で左向きに...反転パターンはそっちで生成
    ; してくれ".
    LD A,(TANK_FACING)
    OR A
    RET Z
    LD A,(CUR_POSE_PAT) : ADD A,TANK_POSE_FLIP_OFFSET : LD (CUR_POSE_PAT),A
    RET

; ---------- writes the 4 sprite attribute entries from TANK_X/ ----------
; TANK_Y_CUR/CUR_POSE_PAT. Called once from INIT, then every frame.
UPDATE_TANK_SPRITES:
    LD A,(CUR_POSE_PAT)
    CP PAT_TANKFGAP
    JR Z,UTS_GAP_OFFSET
    CP PAT_TANKUGAP
    JR Z,UTS_GAP_OFFSET
    CP PAT_TANKFGAP_L
    JR Z,UTS_GAP_OFFSET
    CP PAT_TANKUGAP_L
    JR Z,UTS_GAP_OFFSET
    LD A,(TANK_Y_CUR)
    JR UTS_DRAW_Y_SET
UTS_GAP_OFFSET:
    LD A,(TANK_Y_CUR) : SUB TANK_GAP_ART_OFFSET
UTS_DRAW_Y_SET:
    LD (TANK_DRAW_Y),A

    ; quadrant colors: facing left mirrors the PATTERN content (its
    ; own screen-left quadrant now holds what was originally drawn on
    ; the right, and vice versa - see tank_gen.py's flip), so the
    ; COLOR assigned to each screen-position slot has to swap the same
    ; way, or the body/gun colors would land on the wrong quadrant.
    LD A,(TANK_FACING)
    OR A
    JR Z,UTS_COLOR_NORMAL
    LD A,TANK_COLOR_TR : LD (UTS_COLOR_0),A
    LD A,TANK_COLOR_TL : LD (UTS_COLOR_1),A
    LD A,TANK_COLOR_BR : LD (UTS_COLOR_2),A
    LD A,TANK_COLOR_BL : LD (UTS_COLOR_3),A
    JR UTS_COLOR_DONE
UTS_COLOR_NORMAL:
    LD A,TANK_COLOR_TL : LD (UTS_COLOR_0),A
    LD A,TANK_COLOR_TR : LD (UTS_COLOR_1),A
    LD A,TANK_COLOR_BL : LD (UTS_COLOR_2),A
    LD A,TANK_COLOR_BR : LD (UTS_COLOR_3),A
UTS_COLOR_DONE:

    LD IX,SPRITE_ATTRS
    LD A,(TANK_DRAW_Y) : LD (IX+0),A
    LD A,(TANK_X)     : LD (IX+1),A
    LD A,(CUR_POSE_PAT) : LD (IX+2),A
    LD A,(UTS_COLOR_0) : LD (IX+3),A

    LD A,(TANK_DRAW_Y) : LD (IX+4),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+5),A
    LD A,(CUR_POSE_PAT) : ADD A,4 : LD (IX+6),A
    LD A,(UTS_COLOR_1) : LD (IX+7),A

    LD A,(TANK_DRAW_Y) : ADD A,16 : LD (IX+8),A
    LD A,(TANK_X)     : LD (IX+9),A
    LD A,(CUR_POSE_PAT) : ADD A,8 : LD (IX+10),A
    LD A,(UTS_COLOR_2) : LD (IX+11),A

    LD A,(TANK_DRAW_Y) : ADD A,16 : LD (IX+12),A
    LD A,(TANK_X) : ADD A,16 : LD (IX+13),A
    LD A,(CUR_POSE_PAT) : ADD A,12 : LD (IX+14),A
    LD A,(UTS_COLOR_3) : LD (IX+15),A

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

; ---------- shots: auto-fire while A is held, rate-limited ----------
; "弾はボタン押しっぱなし自動連射 3連射は同じだが間欠連射 1発打っ
; たら1発空ける" - holding A keeps firing (no more edge-triggering),
; but not every single frame: SHOT_COOLDOWN counts down every frame
; regardless of input, and a shot can only spawn once it reaches 0,
; which then rearms it to SHOT_COOLDOWN_FRAMES. The 3-on-screen pool
; limit (TRY_SPAWN_BULLET) is unchanged - "3連射は同じ".
UPDATE_SHOT:
    LD A,(SHOT_COOLDOWN)
    OR A
    JR Z,US_CAN_FIRE
    DEC A : LD (SHOT_COOLDOWN),A
    RET
US_CAN_FIRE:
    LD A,(JOY_TRIGA)
    OR A
    RET Z
    CALL TRY_SPAWN_BULLET
    LD A,SHOT_COOLDOWN_FRAMES : LD (SHOT_COOLDOWN),A
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
    LD A,(TANK_FACING) : LD (IX+6),A

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

    ; COL = (TANK_X + muzzle offset) >> 3, clamped to the last column -
    ; the muzzle offset mirrors to the tank's left side when facing
    ; left (BULLET_MUZZLE_DX_LEFT = 32-1-BULLET_MUZZLE_DX).
    LD A,(IX+6)
    OR A
    JR NZ,TSB_MUZZLE_LEFT
    LD A,(TANK_X) : ADD A,BULLET_MUZZLE_DX
    JR TSB_MUZZLE_SHIFT
TSB_MUZZLE_LEFT:
    LD A,(TANK_X) : ADD A,BULLET_MUZZLE_DX_LEFT
TSB_MUZZLE_SHIFT:
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

    CALL SOUND_SHOT
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

; IX = slot base (+0 ACT,+1 TYPE,+2 COL,+3 ROW,+4/+5 ADDR,+6 FACING).
; Erases the current cell (restoring sky or row19's rock top,
; whichever this bullet is actually over), advances 1 column (toward
; FACING - right or left) and, for a diagonal/U shot, 1 row up too,
; then redraws at the new position - or deactivates if it just left
; the name table's top, left, or right edge.
UPDATE_ONE_BULLET:
    LD A,(IX+0)
    OR A
    RET Z

    CALL ERASE_BULLET_CELL

    ; --- advance: column (direction from FACING), row too (upward) for a diagonal/U shot ---
    LD A,(IX+6)
    OR A
    JR NZ,UOB_ADV_LEFT
    LD A,(IX+2) : INC A : LD (IX+2),A
    JR UOB_ADV_ROW
UOB_ADV_LEFT:
    LD A,(IX+2)
    OR A
    JR Z,UOB_DEACTIVATE   ; already at col0 - one more "left" would leave the screen
    DEC A
    LD (IX+2),A
UOB_ADV_ROW:

    LD A,(IX+1)
    OR A
    JR Z,UOB_ADV_DONE
    LD A,(IX+3)
    CP BULLET_MIN_ROW+1
    JR C,UOB_DEACTIVATE   ; already at (or somehow below) BULLET_MIN_ROW - one more "up" would enter the HUD rows
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

; IX = slot base. row<19 sky, row==19 explicit rock restore (row19 is
; static, only ever written at INIT), row>19 skip entirely - rows
; 20-23 already got fully redrawn from NAMEBUF earlier this same
; MAINLOOP iteration (see the comment on BULLET_ROCK_ROW_MIN above),
; so there's nothing to restore. Shared by UPDATE_ONE_BULLET's own
; per-frame erase-before-advance and CHECK_BULLET_VS_ENEMY (a bullet
; that hits an enemy needs the exact same cell restored immediately,
; not just left to redraw stale next frame since it's now inactive).
ERASE_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_ROW_MIN
    JR NC,EBC_ROCKBAND
    LD A,SKY_BLANK_CODE
    JR EBC_WRITE
EBC_ROCKBAND:
    JR NZ,EBC_SKIP
    LD A,TERRAIN_PATTERN_COUNT
EBC_WRITE:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    CALL WRITE_BULLET_BYTE_HL
EBC_SKIP:
    RET

; IX = slot base. Picks the pattern code for (TYPE x background-under-
; current-row x FACING) and writes it at ADDR+COL.
DRAW_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_ROW_MIN
    JR NC,DBC_ROCK
    LD A,(IX+6)
    OR A
    JR NZ,DBC_SKY_LEFT
    LD A,(IX+1)
    OR A
    JR NZ,DBC_SKY_U
    LD A,BULLETF_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_U:
    LD A,BULLETU_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_LEFT:
    LD A,(IX+1)
    OR A
    JR NZ,DBC_SKY_U_L
    LD A,BULLETF_L_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_U_L:
    LD A,BULLETU_L_SKY_CODE
    JR DBC_CODE_SET
DBC_ROCK:
    LD A,(IX+6)
    OR A
    JR NZ,DBC_ROCK_LEFT
    LD A,(IX+1)
    OR A
    JR NZ,DBC_ROCK_U
    LD A,BULLETF_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_U:
    LD A,BULLETU_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_LEFT:
    LD A,(IX+1)
    OR A
    JR NZ,DBC_ROCK_U_L
    LD A,BULLETF_L_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_U_L:
    LD A,BULLETU_L_ROCK_CODE
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

; writes HUD_VAL to the name-table cell at (HUD_ROW,HUD_COL) - row0/1
; only, so unlike WRITE_ANIM_CELL in src/CYBER SHMUP.asm there's no
; NAMEBUF mirror to keep in sync (the ground scroller only ever
; touches rows20-23). Same raw DI-wrapped OUT + 8-NOP pattern as
; WRITE_BULLET_BYTE_HL above, for the same reason (runs every frame
; under EI, no per-frame HALT).
WRITE_HUD_CELL:
    LD HL,1800h
    LD A,(HUD_ROW)
    OR A
    JR Z,WHC_ROW_OK
    LD DE,32
    ADD HL,DE
WHC_ROW_OK:
    LD A,(HUD_COL) : LD E,A : LD D,0
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
    LD A,(HUD_VAL) : OUT (98h),A
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

; Adds HL to the 24-bit SCORE (low word +0, high byte +2) and redraws
; it - ported from src/CYBER SHMUP.asm's ADD_SCORE_COMMON, simplified
; to a single delta-in-HL entry point since this test only ever adds
; SCORE_PER_KILL (no 100/200/300 enemy-kill tiers to pick between yet).
ADD_SCORE:
    LD DE,(SCORE)
    ADD HL,DE
    LD (SCORE),HL
    JR NC,AS_NO_CARRY
    LD A,(SCORE+2) : INC A : LD (SCORE+2),A
AS_NO_CARRY:
    CALL SCORE_DISPLAY
    RET

; Extracts SCORE's 6 decimal digits (hundred-thousands..ones, of SCORE
; itself - i.e. real_score/100) into SCORE_DIGITS, then draws all 8
; display cells at row0 cols0-7: those 6, followed by a fixed "00"
; (real score's low 2 digits, always zero) - ported from
; src/CYBER SHMUP.asm's own SCORE_DISPLAY; see that file's comment on
; SCORE_DIGITS for why the hundred-thousands/ten-thousands digits need
; the full 24-bit A:HL subtract idiom.
SCORE_DISPLAY:
    LD HL,(SCORE)
    LD A,(SCORE+2)
    LD B,0
SD_HT:
    LD DE,86A0h
    OR A
    SBC HL,DE
    SBC A,01h
    JR C,SD_HT_DONE
    INC B
    JR SD_HT
SD_HT_DONE:
    LD DE,86A0h
    ADD HL,DE
    JR NC,SD_HT_RESTORE_A
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

    XOR A : LD (HUD_ROW),A
    LD A,0 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+0) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,1 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+1) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,2 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+2) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,3 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+3) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,4 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+4) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,5 : LD (HUD_COL),A
    LD A,(SCORE_DIGITS+5) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,6 : LD (HUD_COL),A
    LD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    XOR A : LD (HUD_ROW),A
    LD A,7 : LD (HUD_COL),A
    LD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
    RET

; Converts GAME_TICK (mod 1000) to 3 decimal digits and draws them at
; row0 cols29-31 - ported from src/CYBER SHMUP.asm's own
; GAME_TICK_DISPLAY (called every frame there too, same as here).
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
    LD A,L : LD (HUD_TEMP_BYTE),A

    LD A,B : LD HL,GTD_LAST_H : CP (HL) : JR Z,GTD_SKIP_H
    LD (HL),A
    XOR A : LD (HUD_ROW),A
    LD A,29 : LD (HUD_COL),A
    LD A,B : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
GTD_SKIP_H:
    LD A,C : LD HL,GTD_LAST_T : CP (HL) : JR Z,GTD_SKIP_T
    LD (HL),A
    XOR A : LD (HUD_ROW),A
    LD A,30 : LD (HUD_COL),A
    LD A,C : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
GTD_SKIP_T:
    LD A,(HUD_TEMP_BYTE) : LD HL,GTD_LAST_O : CP (HL) : JR Z,GTD_SKIP_O
    LD (HL),A
    XOR A : LD (HUD_ROW),A
    LD A,31 : LD (HUD_COL),A
    LD A,(HUD_TEMP_BYTE) : ADD A,DIGIT_BASE : LD (HUD_VAL),A
    CALL WRITE_HUD_CELL
GTD_SKIP_O:
    RET

; PSG (AY-3-8910-compatible) shot sound: channel A, noise-only -
; "ノイズｃｈで弾発射音ぽいの". SND_TIMER doubles as both the frame
; countdown and channel A's volume (0-15, see SOUND_UPDATE), so the
; sound fades out on its own as it counts down to 0 - same technique
; as src/CYBER SHMUP.asm's own SOUND_SHOT/SOUND_UPDATE, just narrowed
; to the one channel this test actually uses.
SOUND_SHOT:
    LD A,6 : OUT (PSG_ADDR),A
    LD A,SHOT_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,SHOT_SND_FRAMES : LD (SND_TIMER),A
    RET

; explosion sound - channel B, noise-only, byte-for-byte the same
; period(20)/timer(15) src/CYBER SHMUP.asm's own SOUND_DESTROY uses
; for its channel A - "爆発音追加 Stage1の爆発音流用". Register6 (the
; noise period) is shared hardware-wide across every channel with
; noise enabled, so triggering this while a shot is still fading
; retunes both to this same pitch for the rest of their decay - a
; minor, hardware-inherent quirk, not a bug (each channel keeps its
; OWN independent volume/timer either way, so one never cuts the other
; off - the actual goal here).
SOUND_DESTROY:
    LD A,6 : OUT (PSG_ADDR),A
    LD A,20 : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER_B),A
    RET

SOUND_UPDATE:
    LD A,(SND_TIMER)
    LD B,A
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER)
    OR A
    JR Z,SU_CHAN_B
    DEC A : LD (SND_TIMER),A
SU_CHAN_B:
    LD A,(SND_TIMER_B)
    LD B,A
    LD A,9 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER_B)
    OR A
    RET Z
    DEC A : LD (SND_TIMER_B),A
    RET

; ---------- enemy (ZacoII): spawn timer, then all 3 slots ----------
UPDATE_ENEMIES:
    LD A,(ENEMY_SPAWN_TIMER)
    OR A
    JR Z,UE_TRY_SPAWN
    DEC A : LD (ENEMY_SPAWN_TIMER),A
    JR UE_UPDATE_ALL
UE_TRY_SPAWN:
    CALL ALLOC_ENEMY_SLOT

; walks ENEMY_POOL (HL-indexed, ENEMY_SLOT_SIZE stride, DJNZ over
; ENEMY_SLOT_COUNT) calling UPDATE_ONE_ENEMY on every slot - same idiom
; as src/CYBER SHMUP.asm's own ENEMY_POOL_UPDATE_ALL, not 3 individually
; named CALLs. HL is pushed twice/popped once into IX so the 2nd copy
; survives UPDATE_ONE_ENEMY's own (heavy) use of HL as scratch, then
; restored after.
; IX walks the buffer directly (9x INC IX per slot, matching
; ENEMY_SLOT_SIZE - this assembler has no ADD IX,DE) rather than
; carrying the pointer in HL across the CALL via a push/pop dance:
; UPDATE_ONE_ENEMY and everything it calls only ever READS through IX
; (IX+E_xxx), never reassigns the register itself, so it survives the
; CALL on its own with nothing to preserve.
; PUSH/POP BC around the CALL: DJNZ's loop counter lives in B, and
; UPDATE_ONE_ENEMY (via ENEMY_GET_STEP's own "LD B,A" speed-step scratch,
; and UOE_DRAW's "LD C,A" sprite-offset scratch) clobbers both B and C -
; without saving/restoring it, DJNZ decrements whatever garbage B was
; left holding instead of the real remaining count, so the loop runs a
; wrong (often huge) number of times and IX walks off the end of the
; buffer into unrelated RAM. This was the real freeze/corruption cause
; from the previous 2 rounds, not the push-HL-vs-direct-IX question -
; see the README bug entry.
UE_UPDATE_ALL:
    LD IX,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
UEUA_LOOP:
    PUSH BC
    CALL UPDATE_ONE_ENEMY
    POP BC
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UEUA_LOOP
    CALL FLUSH_ENEMY_SPRITES
    RET

; scans ENEMY_POOL for the first E_ACT=0 slot and spawns into it -
; named/shaped like src/CYBER SHMUP.asm's own ALLOC_ENEMY_SLOT (walks
; the buffer, doesn't check 3 named slots by hand). If every slot is
; already active, spawning is simply retried next frame (the timer is
; only reset on an actual spawn) - same pool-of-3 idea as
; TRY_SPAWN_BULLET.
ALLOC_ENEMY_SLOT:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
AES_LOOP:
    LD A,(HL)
    OR A
    JR Z,AES_FOUND
    LD DE,ENEMY_SLOT_SIZE : ADD HL,DE
    DJNZ AES_LOOP
    RET   ; no free slot - try again next frame
AES_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+E_ACT),A
    LD A,ENEMY_SPAWNX : LD (IX+E_X),A
    LD A,(TICK) : AND ENEMY_SKY_Y_MASK : ADD A,ENEMY_SKY_Y_MIN : LD (IX+E_Y),A
    XOR A : LD (IX+E_RETREAT),A : LD (IX+E_TIMER),A

    LD A,(ENEMY_SPAWN_COUNT)
    CP 10
    JR C,AES_VARIANT_GREEN
    LD A,1
    JR AES_VARIANT_SET
AES_VARIANT_GREEN:
    XOR A
AES_VARIANT_SET:
    LD (IX+E_VARIANT),A

    LD A,(ENEMY_SPAWN_COUNT)
    CP 10
    JR NC,AES_COUNT_DONE
    INC A : LD (ENEMY_SPAWN_COUNT),A
AES_COUNT_DONE:
    LD A,ENEMY_SPAWN_INTERVAL : LD (ENEMY_SPAWN_TIMER),A
    RET

; IX = slot base. Returns this frame's movement step in A: red variant
; (IX+6=1) is a flat ENEMY_SPEED_RED - "こいつは速度2で"; green is
; ENEMY_SPEED_LO alternating with +1 on odd TICK frames (same trick as
; TANK_SPEED_LO/UTX_DO_RIGHT), averaging 1.5px/frame - "自機と同じ
; 1.5で". Shared by both the approach and retreat branches below.
ENEMY_GET_STEP:
    LD A,(IX+E_VARIANT)
    OR A
    JR NZ,EGS_RED
    LD A,(TICK) : AND 1 : LD B,A
    LD A,ENEMY_SPEED_LO : ADD A,B
    RET
EGS_RED:
    LD A,ENEMY_SPEED_RED
    RET

; IX = slot base. E_ACT=1 (alive): moves toward the tank, turns back
; (E_RETREAT=1, mirrored sprite) once within ENEMY_TURNBACK_MARGIN of
; TANK_X - "移動は自機位置をみて手前で引き返す" - then despawns once
; back off the spawn edge. E_ACT=2 (exploding, set by
; CHECK_BULLET_VS_ENEMY): drifts by E_DX/E_DY, counts E_TIMER down to
; 0 then despawns. Either way, stages this slot's 4 attribute bytes
; into ENEMY_SPRITE_ATTRS at its own fixed E_SPRIDX offset - inactive
; slots RET immediately and leave the buffer holding whatever hidden
; (Y=209) bytes it already had.
UPDATE_ONE_ENEMY:
    LD A,(IX+E_ACT)
    CP 2
    JR Z,UOE_EXPLODING
    OR A
    RET Z

    LD A,(IX+E_RETREAT)
    OR A
    JR NZ,UOE_RETREAT

    CALL ENEMY_GET_STEP : LD B,A
    LD A,(IX+E_X) : SUB B : LD (IX+E_X),A
    LD A,(TANK_X) : ADD A,ENEMY_TURNBACK_MARGIN : LD B,A
    LD A,(IX+E_X)
    CP B
    JR NC,UOE_DRAW
    LD A,1 : LD (IX+E_RETREAT),A
    JR UOE_DRAW

UOE_RETREAT:
    CALL ENEMY_GET_STEP : LD B,A
    LD A,(IX+E_X) : ADD A,B : LD (IX+E_X),A
    CP ENEMY_SPAWNX
    JR C,UOE_DRAW
    XOR A : LD (IX+E_ACT),A
    CALL UOE_HIDE
    RET

UOE_DRAW:
    LD A,(IX+E_SPRIDX) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ENEMY_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+E_Y) : LD (HL),A : INC HL
    LD A,(IX+E_X) : LD (HL),A : INC HL
    LD A,(IX+E_RETREAT)
    OR A
    JR Z,UOE_PAT_NORMAL
    LD A,PAT_ZACO_FLIP
    JR UOE_PAT_SET
UOE_PAT_NORMAL:
    LD A,PAT_ZACO
UOE_PAT_SET:
    LD (HL),A : INC HL
    LD A,(IX+E_VARIANT)
    OR A
    JR Z,UOE_COLOR_GREEN
    LD A,ENEMY_RED_COLOR
    JR UOE_COLOR_SET
UOE_COLOR_GREEN:
    LD A,ENEMY_COLOR
UOE_COLOR_SET:
    LD (HL),A
    RET

; checks-before-decrementing (not the more usual decrement-then-check)
; so E_TIMER=EXPLOSION_DURATION(8) actually produces exactly 8
; drift+draw calls, not 7 - decrement-then-check would fire the 8th
; DEC straight to 0 and hide on that same call, one short of the "8フレ
; で...なので爆発は１６ｐｘ移動だな" spec (8 steps x 2px/step, from
; EXPLODE_DIR_DX/DY's own magnitude).
UOE_EXPLODING:
    LD A,(IX+E_TIMER)
    OR A
    JR Z,UOE_EXPLODE_HIDE
    DEC A : LD (IX+E_TIMER),A
; "8方向ランダムに移動後消えるように" - drift by the (dx,dy) picked at
; hit time (see CHECK_HIT_PAIR/EXPLODE_DIR_DX/DY) every frame it's
; shown, instead of holding still at the kill position.
    LD A,(IX+E_X) : LD B,A : LD A,(IX+E_DX) : ADD A,B : LD (IX+E_X),A
    LD A,(IX+E_Y) : LD B,A : LD A,(IX+E_DY) : ADD A,B : LD (IX+E_Y),A
UOE_DRAW_EXPLOSION:
    LD A,(IX+E_SPRIDX) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ENEMY_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+E_Y) : LD (HL),A : INC HL
    LD A,(IX+E_X) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A
    RET
UOE_EXPLODE_HIDE:
    XOR A : LD (IX+E_ACT),A
    CALL UOE_HIDE
    RET

UOE_HIDE:
    LD A,(IX+E_SPRIDX) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ENEMY_SPRITE_ATTRS : ADD HL,BC
    LD A,209 : LD (HL),A
    RET

; blasts ENEMY_SPRITE_ATTRS (12 bytes: Y,X,pat,col x3) to hw sprite
; slots ENEMY_SPR_BASE_SLOT..+2 (4-6) - same raw DI-wrapped OUT +
; 8-NOP, auto-incrementing-VDP-pointer pattern as UPDATE_TANK_SPRITES'
; own UTS_OUT_LOOP, just a different attribute-table address and slot
; count.
FLUSH_ENEMY_SPRITES:
    DI
    LD A,ENEMY_SPR_BASE_SLOT*4 : OUT (99h),A
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
    LD HL,ENEMY_SPRITE_ATTRS
    LD B,12
FES_LOOP:
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
    DJNZ FES_LOOP
    EI
    RET

; ---------- bullet x enemy collision ----------
; "当たったら100点" - on a hit: erase the bullet's cell + deactivate
; it (same ERASE_BULLET_CELL a normal per-frame advance would use -
; this bullet just never gets that later, since it's going inactive
; right now), switch the enemy to E_ACT=2 (exploding, see
; UPDATE_ONE_ENEMY) at its current position, and award SCORE_PER_KILL.
; The bullet side stays 3 individually-named CALLs (BULLET0/1/2 weren't
; part of this round's "make it a real buffer" instruction - only the
; enemy side loops over ENEMY_POOL genuinely, same as everywhere else
; in this file that touches it).
CHECK_BULLET_VS_ENEMY:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET
    RET

; IX = bullet slot base (untouched throughout - CHECK_HIT_PAIR only
; reads through it). IY walks ENEMY_POOL directly (9x INC IY per slot,
; same reasoning as UE_UPDATE_ALL - CHECK_HIT_PAIR never reassigns IY
; either, so there's nothing to preserve across the CALL) testing this
; one bullet against every enemy slot. PUSH/POP BC around the CALL for
; the same reason as UEUA_LOOP - CHECK_HIT_PAIR's own AABB math uses
; both B and C as scratch, which would otherwise corrupt this loop's
; DJNZ counter.
CHECK_HIT_ONE_BULLET:
    LD IY,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
CHOB_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOB_LOOP
    RET

; IX = bullet slot base, IY = enemy slot base. AABB overlap test
; (bullet's 8x8 cell box vs the enemy's 16x16 pixel box) - same 4-edge-
; comparison shape as src/CYBER SHMUP.asm's own QUAD_HIT_TEST, just
; with the enemy side's box widened from 7 to 15.
CHECK_HIT_PAIR:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+E_ACT)
    CP 1
    RET NZ

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(IY+E_X) : LD D,A
    LD A,(IY+E_Y) : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,15 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,15 : CP C : RET C

    CALL ERASE_BULLET_CELL
    XOR A : LD (IX+0),A

    LD A,2 : LD (IY+E_ACT),A
    LD A,EXPLOSION_DURATION : LD (IY+E_TIMER),A

    ; "8方向ランダムに移動後消えるように" - pick one of 8 drift
    ; directions (TICK's low 3 bits, 0-7) for UOE_EXPLODE_DRIFT to
    ; apply each frame the explosion is shown.
    LD A,(TICK) : AND 7 : LD C,A : LD B,0
    LD HL,EXPLODE_DIR_DX : ADD HL,BC : LD A,(HL) : LD (IY+E_DX),A
    LD HL,EXPLODE_DIR_DY : ADD HL,BC : LD A,(HL) : LD (IY+E_DY),A

    CALL SOUND_DESTROY

    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
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

; digit glyphs 0-9, byte-for-byte from src/CYBER SHMUP.asm's own
; DIGIT_PATTERNS ("スコアの数字流用" - reuse the score's numerals),
; followed by A-F (new art, "AからFまで新規" - same weight/style as
; the reused digits, no source glyph existed for these).
DIGIT_PATTERNS_LOCAL:
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
    DB 18h,3Ch,66h,66h,7Eh,66h,66h,00h   ; A
    DB 7Ch,66h,66h,7Ch,66h,66h,7Ch,00h   ; B
    DB 3Ch,66h,60h,60h,60h,66h,3Ch,00h   ; C
    DB 78h,6Ch,66h,66h,66h,6Ch,78h,00h   ; D
    DB 7Eh,60h,60h,78h,60h,60h,7Eh,00h   ; E
    DB 7Eh,60h,60h,78h,60h,60h,60h,00h   ; F

; calibration strip: 16 name-table codes (one per color group15-30,
; see the INIT block that loads these) and their hex-label codes -
; "スコアの横にブランクの0から15のカラーセル表示...でその下に0から
; Fまでで文字表示".
SWATCH_CODES:
    DB 120,128,136,144,152,160,168,176,184,192,200,208,216,224,232,240
; group N's color byte = (i<<4)|i for i=0-15 (palette index i in both
; nibbles - the blank glyph never draws a fg pixel, so only bg would
; normally show, but setting both means it's right either way).
SWATCH_COLORS:
    DB 000,017,034,051,068,085,102,119,136,153,170,187,204,221,238,255
HEXLABEL_CODES:
    DB 104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119
HUD_ZERO8:
    DS 8,0

; explosion sprite (16x16), byte-for-byte from src/CYBER SHMUP.asm's
; own EXPLOSION_PATTERN (its pod-destroy-burst spark shape) - "弾が
; 当たっての爆発はStage1と同じ16x16のスプライト流用". That file uses
; it differently (4 scattered copies for a pod burst); here it's just
; shown once, drifting from the killed enemy's own position for
; EXPLOSION_DURATION(8) frames (see UPDATE_ONE_ENEMY/EXPLODE_DIR_DX -
; "爆発スプライトは8フレ表示 8方向ランダムに移動後消えるように") -
; a single static pattern, not an animation (Stage1's own generic
; per-enemy-kill explosion is a BG-cell animation instead, not a
; sprite at all - see TRIGGER_EXPLOSION - so there was no closer
; "real" explosion sprite to borrow from for a straightforward reuse).
EXPLOSION_PATTERN:
    DB 84h,48h,00h,02h,49h,84h,20h,03h     ; top-left
    DB 13h,09h,20h,00h,09h,10h,04h,00h     ; bottom-left
    DB 00h,00h,40h,10h,20h,10h,8Ch,68h     ; top-right
    DB 90h,82h,48h,0C4h,20h,80h,00h,00h    ; bottom-right

; 8-compass-direction (dx,dy) steps for the explosion's post-hit drift
; - "8方向ランダムに移動後消えるように" - index picked at hit time
; from TICK's low 3 bits (see CHECK_HIT_PAIR). N,NE,E,SE,S,SW,W,NW.
EXPLODE_DIR_DX:
    DB 0,2,2,2,0,-2,-2,-2
EXPLODE_DIR_DY:
    DB -2,-2,0,2,2,2,0,-2

; ===== generated tables (terrain + tank) appended below by build_test.py =====
