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
; medium red (main body) - was dark red(6), swapped with the rock's own
; fg color - "カラー変更 Rockの文字色レッドと自機のレッドを入れ替えて"
; (see the ROCK_COLOR_SWAPPED_PATCH comment in INIT).
TANK_COLOR_TL EQU 8
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
; "違和感あるのがジャンプ ふわっと浮いて降りてるんよな...ジャンプLut
; のステップいじって速度の方をいじるしかないかもな" - felt slow/
; floaty; 49 frames (JUMP_OFFSET_TABLE below) cut to 33, same 24px
; peak, same half-sine shape (round(24*sin(pi*t/32)) for t=0..32) -
; still eased in/out with a brief peak hang (sine's own nature, more
; frames = more of it), just proportionally faster throughout. A first
; guess at "adjust the speed side" per that instruction, not a
; re-derivation of a specific target duration - easy to retune further.
JUMP_FRAMES   EQU 33       ; JUMP_OFFSET_TABLE length
; "乗っかりから降りる時の速度が速すぎてワープにみえる ここもサインLut
; 使わないとだな 自然に見せるには乗っかったらサインジャンプ前半16px
; 相当をスキップしてオートジャンプかな" - if the jump's own timer runs
; out while still standing on a Zum (see UPDATE_TANK_ZUM_STAND/
; TANK_ZUM_STANDING), UPDATE_JUMP restarts JUMP_FRAME here instead of
; ending - the table's own peak index (24px, JUMP_OFFSET_TABLE[16]) -
; so it auto-plays just the falling half of the same sine curve back
; down to 0 instead of snapping straight from the parked height to
; ground in a single frame.
JUMP_LANDING_RESTART_FRAME EQU 16
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

; ---------- shots ----------
; F (straight) stays a BG (name-table) character, not a sprite - any
; number can share a scanline with the tank with no "4 sprites per
; line" flicker (same reasoning as the player's own shots in src/CYBER
; SHMUP.asm). A shot can sit over open sky, the 4 static rows (16
; SkySand, 17-19 Sand), or the scrolling terrain (rows20-23) - erasing
; needs to restore whichever of those 4 is really there. rows16-19
; need an explicit erase write each (static, filled once at INIT);
; rows20-23 get fully redrawn from NAMEBUF every frame before the
; bullet update runs, so erasing a bullet there is a no-op - see
; UPDATE_ONE_BULLET below.
;
; U (diagonal) is now a hardware sprite instead - "弾は斜めのみスプラ
; イトに変更 水平は今のままで" - so none of the BG erase/color-matching
; machinery below applies to it anymore; ERASE_BULLET_CELL/
; DRAW_BULLET_CELL only ever run for TYPE=F now (both guard on TYPE
; before doing anything). See UPDATE_BULLET_U_SPRITES/PAT_BULLETU
; further down for U's own sprite-side setup.
BULLET_ROCK_ROW_MIN EQU 16      ; first row needing an explicit (non-sky) erase restore (16-23)
; F's own color boundary tracks wherever Sand's own light-yellow band
; actually starts (17, since Sand widened to rows17-19) - "水平打ちで
; の弾の背景色はライトイエローなのにブルーになってる 行を増やした
; 影響かも" (F was still using the old pre-widening boundary(19), so
; it showed blue/sky color over the newly-Sand rows17-18 instead of
; yellow).
BULLET_ROCK_COLOR_ROW_MIN_F EQU 17
; a diagonal/U shot decrements ROW every frame as it climbs; with no
; lower bound it could fly into rows0-1 (the HUD) and erase a glyph
; permanently instead of restoring it - "カラーバーAからF消えたぞ".
; Fixed by never letting a bullet's row go below this. Still applies
; now that U is a sprite (it's a position bound on the shared ROW/COL
; bookkeeping, not a BG-erase concern specifically).
BULLET_MIN_ROW    EQU 2
BULLET_MAXCOL     EQU 31        ; last valid name-table column (0-31)
BULLET_MUZZLE_DX  EQU 24        ; spawn column offset from TANK_X (muzzle, right side of the tank)
BULLET_MUZZLE_DX_LEFT EQU 7     ; mirrored muzzle offset for a left-facing shot (32-1-24)
SKY_BLANK_CODE    EQU 0         ; TERRAIN_BLANK_ROW's code - the permanent open-sky tile

; row16: static sprites/SkySand.json fill (own color group31, fg5/
; bg11). rows17-19: static plain Sand fill, reusing the real scrolling-
; terrain BLANK tile/group (TERRAIN_BLANK_CODE) instead of a new one -
; "下から7,8行目をSandで埋めてその上にSkysand、2行上げる" (Sand
; expanded from 1 row to 3, SkySand pushed up 2 rows to stay just above it).
SKYSAND_CODE  EQU 248
SKYSAND_COLOR EQU 05Bh   ; fg5/bg11

; Bullet BG pattern codes - F (straight) only now, U moved to a hw
; sprite (see PAT_BULLETU below): needs one code per background color
; group it can appear over (SCREEN1 colors are fixed per 8-code group,
; not per screen position - see bullet_gen.py's own comment). Placed
; at codes88/96 (groups11-12), well past every real terrain code
; (0-87, groups0-10 - see terrain_gen.py's STEADY_BASE/BLEND_BASE) so
; nothing else ever references them. Codes89/97 (ex-BULLETU_SKY/ROCK_
; CODE) are simply unused now, not renumbered - no reason to renumber
; F's own codes just because U vacated its neighbors.
BULLETF_SKY_CODE  EQU 88
BULLETF_ROCK_CODE EQU 96
; left-facing (mirrored) shot pattern, same 2 color groups (color
; doesn't depend on facing, only the pattern shape does) - "今の自機
; と弾を左操作で左向きに...反転パターンはそっちで生成してくれ".
BULLETF_L_SKY_CODE  EQU 90
BULLETF_L_ROCK_CODE EQU 98
; color table (VRAM 2000h+group, 1 byte/group, hi nibble=fg/lo=bg -
; see terrain_gen.py's own SKY_COLOR/ROCK_COLOR): group11 (codes
; 88-95) = fg1 black/bg5 light blue, matching the sky's own bg5;
; group12 (codes 96-103) = fg1 black/bg11 light yellow, matching the
; rock tier's own bg (terrain_gen.py's ROCK_COLOR=0x8B) - both groups
; patched over terrain_gen.py's generic per-group defaults (unused by
; any real terrain code) rather than by changing that shared module.
; ROCK_COLORBYTE's bg nibble must track ROCK_COLOR's own bg whenever
; that changes (was 01Ah/bg10 - missed when ROCK_COLOR moved to bg11,
; fixed alongside the row18/19 change below).
BULLET_SKY_COLORADDR  EQU 200Bh
BULLET_ROCK_COLORADDR EQU 200Ch
BULLET_SKY_COLORBYTE  EQU 015h
BULLET_ROCK_COLORBYTE EQU 01Bh

; ---------- diagonal/U shot, now a hardware sprite ----------
; "で、弾は斜のみスプライトに変更 水平は今のままで 伴って斜めうちの
; BG関係の弾の処理は削除 Skysandのスキップも廃止": bullet_gen.py's
; own BULLET_U_SPRITE/_L embeds the same 8x8 BulletU art at the
; top-left of an otherwise-blank 16x16 sprite canvas (VDP is already
; in 16x16 mode for the tank/enemies), 1 hw sprite slot per pool slot
; (fixed 1:1, same convention as ENEMY_SPR_BASE_SLOT), Y/X set straight
; from the pool's own ROW*8/COL*8 - the exact same anchor point the
; old BG cell used, so no position-math changes needed elsewhere. A hw
; sprite composites over whatever's already drawn (terrain, clouds,
; sky) automatically, which is what made the SkySand skip-draw special
; case (and the whole sky/rock BG color-matching dance) unnecessary -
; it's simply gone now, not replaced by anything.
BULLET_U_SPR_BASE_SLOT EQU 7    ; hw sprite slots7-9, right after the enemy pool's 4-6
PAT_BULLETU    EQU 140          ; right after PAT_EXPLOSION(136-139)
PAT_BULLETU_L  EQU 144
BULLET_U_COLOR EQU 1            ; black, same fg BulletF's BG version already used
BULLET_U_SPRITE_ATTRS EQU 0F2E0h   ; 12 bytes: Y,X,pat,col x3, staged same as ENEMY_SPRITE_ATTRS

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
; "サウンドはノイズｃｈ使用音は別にしなくていいぞ どうせ被れば消える
; PSGは3ch+ノイズ1chが仕様 2chはBGM用に常に空けておきたいしな" -
; SOUND_SHOT/SOUND_DESTROY/SOUND_ZUM_DEFLECT all share this single
; channel A now (previously spread across A/B/C to keep them from
; ever fighting each other's envelope) - only the AY-3-8910's single
; shared noise generator was ever truly exclusive anyway, so 3
; separate channels never actually bought independent *sounds*, just
; independent volume envelopes; letting a later trigger simply cut off
; whatever's still fading is an accepted, direct simplification, and
; leaves channels B/C completely untouched for BGM. SND_TIMER doubles
; as both the frame countdown and channel A's volume (0-15, see
; SOUND_UPDATE); SND_DECAY (below) is how much it drops per frame -
; each sound sets both when triggered, so one shared decay loop in
; SOUND_UPDATE handles every sound's own pacing.
SND_TIMER     EQU 0F275h
SND_DECAY     EQU 0F276h
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
; "爆発音はショット音で消えるとまずいんで爆発音は鳴り終わるまで継続
; しショット音で消えないように" - the shared-channel-A design lets any
; sound cut off whatever's currently playing, but an explosion in
; particular shouldn't lose to a shot fired right after a kill. Set by
; SOUND_DESTROY, checked (and left alone) by SOUND_SHOT's own early-
; exit, cleared by SOUND_UPDATE the instant the explosion's own
; SND_TIMER actually reaches 0, and cleared by SOUND_ZUM_DEFLECT too
; (that one's still allowed to cut an explosion off, same as always -
; only the shot sound is singled out here).
SND_EXPLODING EQU 0F27Ah
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
; mixer (R7) values for channel A only - tone/noise B and C always
; off, leaving those 2 channels genuinely untouched for BGM. bit
; layout: 0=tone A,1=tone B,2=tone C,3=noise A,4=noise B,5=noise C
; (0=enabled,1=disabled), bits6-7 unused here (kept 1).
MIXER_NOISE_A EQU 0F7h   ; noise A on, everything else off - shot/explosion
MIXER_TONE_A  EQU 0FEh   ; tone A on, everything else off - "kin" deflect
; short/high-pitched noise burst for a shot "pyu" - "ノイズｃｈで弾
; 発射音ぽいの" (noise channel, shot-sound-like); period/fade picked
; with no more precise spec than that, easy to retune.
SHOT_NOISE_PERIOD EQU 8
; peak volume ("自機ショット音も多分8だと思うんで10に") must still
; fully decay before the next auto-fire shot (SHOT_COOLDOWN_FRAMES+1 =
; 9 frames later) or held-fire sounds permanently "on" instead of a
; series of distinct blips - "サウンドも弾打ったら出っぱなしだ", a bug
; already hit once before. At the old decay-by-1/frame pace, peak 10
; would take 10 frames - too slow. SHOT_SND_DECAY(2) instead of the
; usual 1 gets it to 0 in 5 frames (10,8,6,4,2,0), comfortably inside
; the gap, so the louder peak doesn't reopen that bug.
SHOT_SND_PEAK  EQU 10
SHOT_SND_DECAY EQU 2

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
ENEMY_SPEED_RED EQU 3   ; red variant: flat 3px/frame - "ZakoIIはの赤は速度３で" (was 2)
ENEMY_SPAWNX      EQU 240   ; off the right edge (16px sprite, so fully offscreen at spawn) - "右から左へスライド"
; "移動は自機位置をみて手前で引き返す" - turns back once within this
; many px of the tank, short of actually reaching it. Was 40 - "どちら
; も接近しすぎなので４０ｐｘ手前じゃなく６４ｐｘ手前で引き返すこと"
; (both variants were getting too close).
ENEMY_TURNBACK_MARGIN EQU 64
; "ZukuIIにもサイン減速 で、反転して帰っていく際はサイン加速 速度は
; 今のままでいい" - width (px) of the sine-eased zone straddling the
; turnback pivot on both sides: the last ENEMY_RAMP_RANGE px of the
; approach ease down to a stop right at the pivot, and the first
; ENEMY_RAMP_RANGE px of the retreat ease back up to full retreat
; speed - see ENEMY_GET_STEP_RAMPED. Outside this zone (i.e. most of
; the actual travel, on both legs) nothing changes - still the exact
; same flat/TICK-averaged cruise speed ENEMY_GET_STEP always gave, per
; "速度は今のままでいい".
ENEMY_RAMP_RANGE EQU 32
; "Skyのみのの位置に出現...現状はランダム" - Y confined to a band
; safely inside the open sky (below the HUD rows0-1 at y0-15, well
; above row19's ground top at y152) using a TICK-derived pseudo-random
; low byte (AND with a power-of-2 span so it's a plain mask, no
; divide) - a placeholder until terrain-aware spawning exists ("地形も
; 合わせてスケジュールエディタで対応予定").
ENEMY_SKY_Y_MIN   EQU 24
ENEMY_SKY_Y_MASK  EQU 3Fh   ; span 64 -> Y in [24,88), sprite bottom never past y151
ENEMY_SPAWN_INTERVAL EQU 90 ; frames between spawns while a slot is free - untuned
ENEMY_COLOR       EQU 3     ; light green - "ZakoIIの色をライトグリーンに" (was 12, dark green, sprites/ZacoII.json's own original fg)
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

; ---------- Zum ground enemy (see UPDATE_ZUM_ALL) ----------
; "では敵を追加する 赤ZakoIIが10体で終わったら地形右から登場 もちろん
; 地形は避けること 地面に設置してること 上り下り出来ること 自機と
; 同じだね で上りがない地形最下部でスポーン 速度は1で自機に64pxまで
; 近づくと速度2で自機に突っ込んでくる お互い貫通せず止まること つまり
; 何も操作しなければ敵に押される 自機がジャンプで避けるとそのまま
; 左に消える 正面からは無敵で弾は止まること 破壊条件は後ろから撃たれ
; た場合のみ" - confirmed in 2 follow-up rounds: ZacoII keeps spawning
; as usual (Zum is additive, not a replacement once the red-variant
; threshold hits), and up to 2 Zum can be on screen at once ("横並び
; 制限があるんで").
;
; Ground-following reuses the same idea UPDATE_TERRAIN_COLLISION uses
; for the tank itself ("自機と同じだね") - probe IDCACHE_T0..T3 at
; this enemy's own column, walk down for the first non-BLANK tier,
; ease Z_Y toward TANK_TIER_Y_TABLE[tier] (the same table the tank's
; own Y targets, since Zum is meant to stand at the same height class).
; Originally a simplified flat-speed ease WITHOUT the tank's own hard-
; won catch-up-threshold refinements, which read as jittery/laggy 8px
; steps on real hardware exactly as expected - "坂の上り下りも自機と
; 全く同じ処理にしないとガタガタの8px昇降になる". UOZ_TERRAIN_FOLLOW
; now calls the tank's own easing routine directly (TERRAIN_EASE_Y,
; factored out of UPDATE_TERRAIN_COLLISION) instead of a second,
; simpler copy of that tuning.
; "自機の前まで減速したら押してくるやつと反転して逃げるやつをランダ
; ムに 引き返しもサイン移動で" - once a Zum's own approach decelerates
; down into the near-tank zone (distance<ZUM_MID_RANGE), it rolls once
; (per approach) between continuing in to push (the existing behavior)
; or reversing and fleeing back off the right edge, sine-accelerating
; away just like ZacoII's own retreat leg - see UOZ_MOVE/ZUM_FLEE_
; TABLE. +7 Z_RETREAT tracks this: 0=undecided (still approaching,
; hasn't reached the roll point yet), 3=pausing (reached it, sitting
; motionless for ZUM_PAUSE_FRAMES before actually rolling - "少し止ま
; ってから反転するか突っ込むかに変更", reusing +3 Z_TIMER as the
; countdown since it's otherwise unused while alive), 1=fleeing (rolled
; away), 2=charging (rolled to push, decided - skips the roll on later
; frames).
ZUM_SLOT_SIZE  EQU 8    ; +0 Z_ACT,+1 Z_X,+2 Z_Y,+3 Z_TIMER(explosion)/pause countdown while alive,+4 Z_SPRIDX,+5/+6 Z_DX/Z_DY(explosion drift),+7 Z_RETREAT
ZUM_SLOT_COUNT EQU 2
ZUM_POOL       EQU 0F2ECh   ; ZUM_SLOT_SIZE*ZUM_SLOT_COUNT = 14 bytes
ZUM_SPRITE_ATTRS EQU 0F2FAh ; 8 bytes: Y,X,pat,col x2 - same staging-buffer pattern as ENEMY_SPRITE_ATTRS
ZUM_SPAWN_TIMER  EQU 0F302h
; "乗っかりから降りる時の速度が速すぎてワープにみえる" - set by
; UPDATE_TANK_ZUM_STAND (1 if it actually clamped TANK_Y_CUR against a
; Zum this call, else 0); read by UPDATE_JUMP the following frame to
; auto-land smoothly instead of snapping straight to ground the
; instant the jump timer runs out while still parked - see
; JUMP_LANDING_RESTART_FRAME below.
TANK_ZUM_STANDING EQU 0F303h
; "乗っかり中にジャンプできないんで オートジャンプ中でも出来るように" -
; UPDATE_JUMP normally refuses a new press whenever JUMP_ACTIVE is
; already set, which while parked on a Zum is *always* true (the
; auto-land cycle above never clears it, only restarts JUMP_FRAME).
; JUMP_STAND_BASELINE holds the current stand-elevation above true
; ground (TANK_GROUND_Y-TANK_Y_CUR) at the moment a fresh jump is
; honored while parked, so the new jump's own arc adds on top of
; where the tank already is instead of first snapping down to
; TANK_GROUND_Y and jumping from there - see UPDATE_JUMP.
JUMP_STAND_BASELINE EQU 0F304h
ZUM_SPR_BASE_SLOT EQU 10    ; hw sprite slots10-11, right after the bullet pool's own 7-9
PAT_ZUM EQU 148             ; right after PAT_BULLETU_L(144-147)
; mirrored Zum art, generated by enemy_gen.py from day one but unused
; until now ("Zum never reverses direction...its own flip output is
; simply unused" - enemy_gen.py's own comment, no longer true - see
; UOZ_DRAW/the flee-roll above).
PAT_ZUM_FLIP EQU 152
ZUM_COLOR EQU 13            ; from sprites/Zum.json's own fg
ZUM_SPAWNX EQU 240          ; off the right edge, same "fully offscreen at 16px" convention as ENEMY_SPAWNX
; horizontal-center probe offset shared by ZUM_SPAWN_COL below and
; UOZ_TERRAIN_FOLLOW's own per-frame probe - "初期スポーン位置がおかし
; いか Zumの下がRockまたはRock225をチェックしてないってこと" traced to
; ZUM_SPAWN_COL being hand-typed as 30 while the runtime probe actually
; used (Z_X+8)>>3 = 31 at X=240 - the spawn gate was checking one column
; to the *left* of where Zum actually stands the instant it spawns, so
; ZUM_TERRAIN_OK's "flat ground" check didn't match what UOZ_TERRAIN_
; FOLLOW immediately probed for real. Named here and reused by both so
; they can't drift apart again.
ZUM_PROBE_DX EQU 8
; the column Zum's own horizontal center lands on at spawn - derived,
; not hand-typed, so it always matches UOZ_TERRAIN_FOLLOW's own probe.
ZUM_SPAWN_COL EQU ZUM_SPAWNX+ZUM_PROBE_DX/8
ZUM_SPAWN_INTERVAL EQU 90   ; same untuned-but-reasonable value as ENEMY_SPAWN_INTERVAL
; "Zumの加速は必要だぞ その前提で考えてるんだから ただロジック的に
; 両立出来ないんで 出現時速度３で右から出てきたら 80pxで自機を検知
; して速度1にサイン減速 減速終了で速度3までサイン加速して自機に突っ
; 込む" - supersedes the previous decel-only design (which dropped to a
; slower flat cruise and stayed there - missing the re-acceleration
; the actual premise called for). Now: flat ZUM_SPEED_BASE(3) cruise
; beyond ZUM_DETECT_RANGE(80) of the tank; within it, the 80px zone
; splits into two 40px (ZUM_MID_RANGE) halves - the outer half sine-
; decelerates 3->1 (ZUM_DECEL_TABLE), the inner half sine-accelerates
; back 1->3 (ZUM_ACCEL_TABLE), reaching full charge speed again right
; as it reaches the tank. Both tables are indexed directly by current
; distance-to-tank (not elapsed frames) - self-correcting every frame
; regardless of how the tank itself moves meanwhile, no extra per-slot
; ramp state needed - and, like the ZacoII ramp tables, every entry is
; floored at 1 during generation so distance always shrinks by at
; least 1px/frame (a literal-0 entry would freeze distance-to-tank,
; and therefore the table index, forever - see ENEMY_DECEL_TABLE_
; GREEN's own comment for how this was first caught). Generated via
; error-diffusion walked high-index->low-index in both tables, matching
; the direction Zum actually traverses each half as it approaches.
ZUM_SPEED_BASE EQU 3
ZUM_DETECT_RANGE EQU 80
ZUM_MID_RANGE EQU 40    ; assumed split point (half of ZUM_DETECT_RANGE) - not itself specified
; "ツッコミと反転の分岐時に少し止まってから反転するか突っ込むかに変更
; 今のカウンター基準だと4フレ停止かな" (then "停止を8フレに") - Zum
; now comes to a full, motionless stop for this many frames right at
; the roll point (the instant distance first drops under ZUM_MID_
; RANGE), instead of deciding and moving on the very same frame - see
; Z_RETREAT=3 (pausing) in UOZ_MOVE/UOZ_PAUSE_MOVE.
ZUM_PAUSE_FRAMES EQU 8
; flee cruise speed once clear of the tank - "反転時の速度が速いので
; 落としてくれ もしかして2倍にしてないか": it was exactly that, ZacoII's
; own "帰る時は倍速で" retreat-doubling convention borrowed without a
; real basis (no equivalent number was ever given for Zum's own flee)
; - dropped back to a flat match of ZUM_SPEED_BASE(3) instead of
; doubling it. ZUM_FLEE_TABLE (below) sine-accelerates from wherever
; the flee roll happened (near the decel trough, ~1.5) up to this over
; ZUM_MID_RANGE(40), indexed by growing distance-from-tank exactly
; like ZacoII's own ACCEL tables - "引き返しもサイン移動で".
ZUM_FLEE_SPEED EQU ZUM_SPEED_BASE
; "地面に設置してないな 16px上に浮いてる" - TANK_TIER_Y_TABLE gives
; the tank's own (32px-tall sprite) top-anchor Y for each tier; Zum is
; only 16px tall, so using that value directly for Zum's own top-Y
; left its bottom 16px short of the ground line (see
; UOZ_TERRAIN_FOLLOW). Went through 2 empirically-tuned ADD offsets
; (+16, then backed off to +10 after "今度は5,6Px地面に埋まってるな")
; trying to visually match the tank's own bottom - "位置だけ一致させ
; ると判定が狂ってしまう原因になる" (matching the *visual* position
; alone is exactly what made the collision geometry wrong - Zum's own
; hit-box, the push-block height, and the stand-on-top target all read
; straight from this same Y, so fudging it to look right under
; UPDATE_ONE_ZUM's own gravity broke standing-on-top - "乗っかった時
; に自機とZumの間に隙間が出来て...多分Zumをオフセットしたからだろう
; そもそもこのオフセットは必要ないからな"). First replaced with a
; plain SUB from TANK_TIER_Y_TABLE per direct instruction ("地形1番下
; の高さは8px Zumは16px 8px上にスプライトを出せば自然に設置するはず")
; - but that treated TANK_TIER_Y_TABLE[tier] itself as the ground
; line, which it is NOT: TANK_TIER_Y_TABLE[i] is the TANK's own 32px-
; sprite top-anchor, already offset 28px *above* the true ground line
; by TANK_Y_BASE's own documented derivation ("row23 top (23*8=184) -
; tank height(32) + landing offset(3+1)" -> 184-32+4=156 -> ground_
; line=TANK_TIER_Y_TABLE[i]+28, confirmed to hold for all 4 tiers:
; 132+28=160=20*8, 140+28=168=21*8, 148+28=176=22*8, 156+28=184=23*8).
; SUB 8 from that anchor undershot the real ground line by ~20px
; instead of the intended 0 - still floating, confirmed at that
; magnitude by this exact report ("16px以上浮いてる").
;
; Corrected derivation, still geometric (not re-tuned by eye): the
; true ground line for a tier is ground_line=(20+tier)*8 - the actual
; top pixel row of the solid rock/Rock225 BG tile there, unrelated to
; the tank's own sprite-anchor fudging. Zum is exactly 2 terrain steps
; (16px) tall and its own art fills essentially the whole 16 rows (no
; large blank-bottom padding like the tank's own 32px canvas has -
; sprites/Zum.json has real pixels through its very last row), so no
; separate landing-offset fudge is needed: Zum's bottom should simply
; BE the ground line, i.e. Zum_top=ground_line-16=TANK_TIER_Y_TABLE
; [tier]+28-16=TANK_TIER_Y_TABLE[tier]+12 (ADD, not SUB, below).
ZUM_Y_OFFSET EQU 12
; despawn margin removed - "Zumが画面左まで行った際にかなり手前で
; 止まってそのまま消えてる 左端まで到達してないぞ": a fixed 32px
; margin (matching TANK_PUSH_WIDTH, to keep UPDATE_TANK_ZUM_PUSH's own
; "Z_X-TANK_PUSH_WIDTH" from underflowing) stopped Zum visibly short of
; the actual edge. UPDATE_ONE_ZUM now despawns right at the last frame
; it can still subtract its own speed without underflowing X (see
; UOZ_MOVE) - reaches X=0 before disappearing instead of stopping 32px
; short. UPDATE_TANK_ZUM_PUSH no longer depends on this invariant for
; its own underflow safety either - it already skips entirely once
; TANK_X>=Zum_X (see its own "already passed" fix), which alone
; guarantees Zum_X>TANK_X>=0 whenever it actually reaches that
; subtraction.
TANK_PUSH_WIDTH EQU 32      ; tank's own collision width for the Zum push-block below
; how far the tank's own top-anchor Y sits above whatever it's
; standing on - tank height(32) minus the same landing offset(4) baked
; into TANK_Y_BASE/TANK_TIER_Y_TABLE's own derivation ("row23 top
; (23*8=184) - tank height(32) + landing offset(3+1)" -> the anchor is
; always groundline-28, never groundline-32). Used by UPDATE_TANK_ZUM_
; STAND below so standing on top of Zum uses the exact same anchor-to-
; surface relationship as standing on ordinary terrain - previously
; that code subtracted TANK_PUSH_WIDTH(32) instead (an unrelated
; *horizontal* collision-width constant that just happened to also be
; 32), landing the tank 4px higher than it should sit and reproducing
; almost exactly the "5,6px隙間" gap once blamed on ZUM_Y_OFFSET.
TANK_GROUND_OFFSET EQU 28
; "Zumと接触状態でジャンプすると自機がワープしてしまう" - the push
; below was an unconditional snap to Zum's exact position; harmless
; frame-to-frame during ordinary continuous contact (the gap it has to
; close each frame is always small), but the push is fully suspended
; for the ~49 frames of a jump ("自機がジャンプで避けると") while Zum
; keeps moving the whole time - by landing, the accumulated gap could
; be huge, and snapping it shut in a single frame reads as the tank
; teleporting. Capped at this many px/frame - at or above Zum's own
; max speed so ordinary continuous-contact pushing (which never needs
; to close more than one frame's worth of Zum movement) still resolves
; in a single frame.
;
; "無操作でも押してはくるが弱いんで 自機が押してるのと同じ押し量で" -
; measured directly: while idle this clamp reliably moves TANK_X by
; the full 3px/frame every frame, but while actively steering *into*
; Zum the tank's own forward step (1-2px/frame) fights the same clamp
; each frame, netting only ~1px/frame of actual backward drift -
; numerically the *idle* push was already the stronger of the two, not
; the weaker one; confirmed with the user before changing anything
; (raise the idle number further, not match it down to the resisted-
; push feel). Raised to match ZUM_FLEE_SPEED(6) - Zum's fastest speed
; anywhere in this file - rather than ZUM_SPEED_BASE(3), its ordinary
; cruise.
ZUM_PUSH_SPEED EQU 6

; ---------- BigZum ground enemy (see UPDATE_BIGZUM_ALL) ----------
; "次BigZumの実装 Zumとスポーン条件は同じ アルゴリズムもほぼ同じ 違う
; のは停止後引き返さずパンチするかジャンプして乗っかってくる ジャンプ
; は自機より高く32ｐｘ サインジャンプ 自機に設置したら連続ジャンプで
; 飛び越え 自機の後ろを取って地上に降りたら後ろからパンチ なので添付
; のデータは反転も生成 攻撃判定も同じで後ろしか当たらない 耐久5" -
; same spawn gating as Zum (ENEMY_SPAWN_COUNT>=10, flat-ground probe at
; its own spawn column, free-slot check - see BIGZUM_TERRAIN_OK/
; ALLOC_BIGZUM_SLOT) and the same approach/decel/pause shape (reuses
; ZUM_DETECT_RANGE/ZUM_MID_RANGE/ZUM_SPEED_BASE/ZUM_ACCEL_TABLE/
; ZUM_DECEL_TABLE/ZUM_PAUSE_FRAMES outright - "アルゴリズムもほぼ同じ"
; means literally reusing those tables/constants, not re-deriving new
; ones). The 2 post-pause branches replace Zum's push-vs-flee with
; punch-vs-jump-on:
;   BZ_STATE=2 (punching) - closes any remaining gap (same ZUM_ACCEL_
;     TABLE ease Zum's own charge uses), then holds position once
;     within TANK_PUSH_WIDTH and throws a punch (BIGZUM_PUNCH_INTERVAL
;     frame cadence) instead of Zum's continuous 1:1 push - see
;     UPDATE_TANK_BIGZUM_PUNCH. Shows BigZumP (punch pose) for
;     BIGZUM_PUNCH_POSE_FRAMES after each punch lands.
;   BZ_STATE=1 (jumping) - a sine-arc jump (BIGZUM_JUMP_TABLE, 32px
;     peak - "自機より高く32ｐｘ サインジャンプ", vs the tank's own
;     24px JUMP_OFFSET_TABLE) while still advancing toward the tank.
;     If the arc completes while BigZum still hasn't cleared past the
;     tank's own X (would land ON it), the jump simply restarts from
;     frame0 instead of ending - "自機に設置したら連続ジャンプで飛び
;     越え" (chain another full arc rather than landing on top). Once
;     an arc completes with BigZum's own X already past (left of) the
;     tank's, it's genuinely landed behind - "自機の後ろを取って地上に
;     降りたら" - switches to BZ_STATE=2 with BZ_FACING=1 (flipped
;     art, now facing right toward the tank) and starts punching from
;     there instead - "後ろからパンチ".
;
; BZ_FACING doubles as CHECK_HIT_PAIR_BIGZUM's own front/rear split -
; "攻撃判定も同じで後ろしか当たらない" reuses CHECK_HIT_PAIR_ZUM's
; exact front(invincible)/rear(vulnerable) geometry, just keyed off
; BZ_FACING instead of Z_RETREAT==1 (front is whichever side BigZum is
; currently oriented toward - TANK_X<BZ_X while FACING=0/approaching
; from the right, TANK_X>=BZ_X once FACING=1/behind-the-tank and
; facing right - same "mirrors when it turns around" rule Zum's own
; CHPZ_ORIENT_FLEE already established). Unlike Zum's 1-hit kill, a
; rear hit only decrements BZ_HP (init BIGZUM_HP_INIT=5 - "耐久5") and
; only actually destroys it once that reaches 0.
BIGZUM_SLOT_SIZE  EQU 12   ; +0 ACT,+1 X,+2 Y,+3 TIMER(explosion/pause countdown/punch-pose-frames - all mutually exclusive across states),+4 SPRIDX,+5/+6 DX/DY(explosion drift),+7 STATE(0=approach,3=pause,1=jump,2=punch),+8 HP,+9 FACING(0=normal facing left,1=flipped facing right),+10 JUMPFRAME,+11 PUNCH_COOLDOWN
BIGZUM_SLOT_COUNT EQU 2    ; same "横並び制限" concurrent-count convention as Zum - "スポーン条件は同じ"
BIGZUM_POOL       EQU 0F305h  ; BIGZUM_SLOT_SIZE*BIGZUM_SLOT_COUNT = 24 bytes
BIGZUM_SPAWN_TIMER EQU 0F31Dh
; staging buffer for BIGZUM_SLOT_COUNT*4 hw sprite slots (4 per
; instance - a 32x32 BigZum is 2x2 of 16x16 hw sprites, same quadrant
; convention as the tank's own SPRITE_ATTRS/UPDATE_TANK_SPRITES, just
; per-pool-slot via BZ_SPRIDX instead of a single fixed instance).
BIGZUM_SPRITE_ATTRS EQU 0F31Eh   ; BIGZUM_SLOT_COUNT*16 = 32 bytes: (Y,X,pat,col)x4 per instance
BIGZUM_DRAW_TEMP  EQU 0F33Eh     ; scratch byte, UOBZ_DRAW's own chosen pattern base
BIGZUM_SPR_BASE_SLOT EQU 12      ; hw sprite slots12-19 (2 instances x4), right after Zum's own 10-11
; PAT_BIGZUM/PAT_BIGZUMP/_L (bigzum_gen.py) - BASE_OFFSET=156 there,
; right after Zum's own PAT_ZUM_FLIP(152-155); 2 poses x2 facings x4
; quadrant-groups x4 sub-patterns = 64 total codes, 156-219.
BIGZUM_COLOR      EQU 13   ; from sprites/BigZum.json's own fg (same magenta as Zum)
BIGZUM_SPAWNX     EQU ZUM_SPAWNX          ; same off-right-edge spawn X as Zum - "スポーン条件は同じ"
BIGZUM_PROBE_DX   EQU 16                  ; horizontal-center probe offset for a 32px-wide sprite (vs Zum's 8, for its 16px width)
BIGZUM_SPAWN_COL  EQU BIGZUM_SPAWNX+BIGZUM_PROBE_DX/8
BIGZUM_SPAWN_INTERVAL EQU ZUM_SPAWN_INTERVAL
BIGZUM_HP_INIT    EQU 5    ; "耐久5"
; jump arc: same half-sine construction as the tank's own JUMP_OFFSET_
; TABLE (round(H*sin(pi*t/32)) for t=0..32), just H=32 instead of 24 -
; "ジャンプは自機より高く32ｐｘ サインジャンプ". Same 33-frame duration
; as the tank's own jump (no duration was specified, only height - see
; BIGZUM_JUMP_TABLE below).
BIGZUM_JUMP_FRAMES EQU 33
BIGZUM_JUMP_XSPEED EQU ZUM_SPEED_BASE     ; horizontal travel speed while airborne, same as the ordinary approach cruise
; ground reference used throughout a jump arc is the flat spawn tier
; (TANK_Y_BASE) rather than a live per-frame terrain probe - the jump
; is a short, self-contained maneuver that starts from the guaranteed-
; flat spawn ground ("上りがない地形最下部でスポーン", same spawn-
; terrain guarantee Zum itself relies on), so this is a reasonable
; simplification rather than a tuned/confirmed value - flagged the
; same way Zum's own Y-offset derivation went through several rounds
; of correction, in case real play crosses a tier boundary mid-jump.
BIGZUM_PUNCH_INTERVAL EQU 16      ; frames between punches once in contact - untuned, easy to retune
BIGZUM_PUNCH_POSE_FRAMES EQU 8    ; how long BigZumP (punch pose) shows after each punch - same magnitude as EXPLOSION_DURATION
; "パンチ" effect on the tank: no tank-HP/damage system exists anywhere
; in this codebase, so interpreted as a single stronger, discrete
; knockback pulse (vs. Zum's smooth continuous ZUM_PUSH_SPEED shove) -
; an inference, not confirmed with the user; easy to redirect into a
; real damage system later if one gets added.
BIGZUM_PUNCH_KNOCKBACK EQU 12

; ---------- flowing background clouds (see CLOUD_UPDATE_ALL) ----------
; "Stage1でもやってる雲を上から3行目に4セルの雲をランダムタイミングで
; 4行目はから8行目まで2セルと4セル雲をランダムに各行で速度変化をつけて
; 3から5行目は最速の毎フレーム1セル移動 5から8行目は半速の2フレで1セル"
; (5行目は最速側 - confirmed directly). 6 independent generators, one
; per screen row2-7 (3rd-8th row from the top), buffer+DJNZ-loop driven
; like ENEMY_POOL, not individually unrolled - same "管理もバッファ経由
; だぞ" precedent. Reuses src/CYBER SHMUP.asm's own CLOUDW/CLOUDN idea
; (idle/wait/move/erase-redraw, 2-tile WA/WB glyph pair) generalized to
; N rows with a per-slot ROW/INTERVAL/FIXED4 instead of 2 hardcoded
; instances.
;
; slot layout (CLOUD_SLOT_SIZE=9): +0 ACT, +1 INTERVAL (frames per
; 1-cell move, fixed per row), +2 FIXED4 (1=row2's cloud is always
; 4-cell wide, 0=every other row randomly picks 2 or 4 at spawn),
; +3 COL (signed, leftmost cell), +4 TIMER (frames left to next
; move), +5 WAIT (frames left to next spawn attempt while inactive),
; +6 WIDTH (2 or 4, chosen at spawn), +7/+8 ROWADDR_LO/HI (this slot's
; fixed name-table row base address, precomputed once at INIT).
CLOUD_SLOT_SIZE  EQU 9
; briefly cut to 2 (rows2-3 only) as a slowdown-diagnosis experiment
; ("5から8行目は削除してみてくれ") - ruled out ("雲減らしても変わらん
; な そんなに処理増えてないはずだが"), restored to all 6, then
; permanently trimmed to 3 ("雲は6から8行目は削除していいわ") - keeps
; just the fast band (rows2-4, 3rd-5th from top), drops the half-speed
; one (rows5-7, 6th-8th from top) for good this time, not an experiment.
CLOUD_SLOT_COUNT EQU 3
CLOUD_POOL    EQU 0F2A9h   ; CLOUD_SLOT_SIZE*CLOUD_SLOT_COUNT bytes (27, was 54 with all 6 rows)
; shared free-running counter, same idea as Stage1's DFL_RNG - used by
; every "random-ish" draw in this file (cloud timing/width, ZacoII's
; own spawn Y and red/green pick, Zum's flee/charge roll). "気になっ
; てたのが雲とZakoIIのランダムパラメータ 一定で固定されてるときがあ
; る 特に雲は最初の方がかたまって出てくる" - traced to resonance: a
; plain "read, +1, store" counter only gains 1 unit of real entropy
; per read, so a consumer with its own perfectly regular cadence (like
; a fixed-interval spawn timer) sees the exact same fixed delta every
; time, cycling through a short, fully deterministic, repeating
; sequence (or landing on a single fixed value outright if that delta
; happens to be a multiple of the consumer's own mask+1) - worst right
; at the start of a run, before anything else with irregular timing
; has had a chance to interleave reads and break the pattern up, which
; is exactly when clouds are first establishing their own spacing.
; Fixed by also advancing this every single frame in MAINLOOP,
; unconditionally, by the current TICK value (not a flat +1) - the
; cumulative sum of 1+2+3+...+TICK grows non-linearly, so no fixed-
; interval consumer ever sees a constant delta between reads again.
GAME_RNG     EQU 0F2DFh
CLOUD_SPAWN_COL EQU 32     ; leftmost cell starts one column past the right edge
; codes1-2: genuinely unused pattern-code slots within group0 (see the
; INIT-time load below) - reuses src/CYBER SHMUP.asm's own CLOUD_WA/
; WB_CODE art byte-for-byte, just renumbered since Stage2's own code
; map is unrelated to Stage1's.
CLOUD_A_CODE  EQU 1
CLOUD_B_CODE  EQU 2
CLOUD_GROUP0_COLOR EQU 0F5h   ; fg15 white / bg5 light blue (group0 was 0x55 sky-on-sky)

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

    ; "カラー変更 Rockの文字色レッドと自機のレッドを入れ替えて" - swap
    ; the rock's own fg color (terrain_gen.py's ROCK_COLOR, fg8 medium
    ; red) with the tank's TL/main-body color (TANK_COLOR_TL, fg6 dark
    ; red - see the tank sprite color patch below). Patched here rather
    ; than editing terrain_gen.py itself (shared with the other stage2
    ; tests) - same "patch over the shared module's defaults" approach
    ; already used for the bullet colors below. Groups1-31 all used to
    ; start out ROCK_COLOR-uniform, so one blind overwrite of the whole
    ; range was harmless; group2 (terrain_gen.py's own SAND_GROUPS -
    ; just BLANK_CODE's dedicated solo/self-blend group now, see that
    ; file's own comment on BLANK_PAIR_BASE) is explicitly skipped
    ; here, since group1/3-31 are the only groups still genuinely
    ; rock-colored (11-30 - bullets/digits/swatch - get their own,
    ; unrelated colors patched in further down anyway, so touching
    ; them here or not makes no difference).
    LD HL,ROCK_COLOR_SWAPPED_PATCH : LD DE,2001h : LD BC,1 : CALL LDIRVM
    LD HL,ROCK_COLOR_SWAPPED_PATCH : LD DE,2003h : LD BC,29 : CALL LDIRVM

    ; flowing background clouds: 2-tile glyph pair at codes1-2, genuinely
    ; unused slots within group0 (SKY_BLANK_CODE=0 is group0's only real
    ; occupant per terrain_gen.py - codes1-7 are never emitted by the
    ; terrain generator at all). Group0's color becomes white-on-sky-
    ; blue instead of sky-on-sky.
    LD HL,CLOUD_A_PATTERN : LD DE,CLOUD_A_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,CLOUD_B_PATTERN : LD DE,CLOUD_B_CODE*8 : LD BC,8 : CALL LDIRVM
    LD A,CLOUD_GROUP0_COLOR : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h : LD BC,1 : CALL LDIRVM
    ; SKY_BLANK_CODE(0)'s own pattern actually has a few stray "1" bits
    ; (terrain_gen.py's BLANK tile, some faint speckle never meant to
    ; be visible) - harmless while group0 was sky-on-sky (fg==bg hid
    ; them), but they'd show through as a whole-screen fg-white speckle
    ; the instant group0 gets a real fg/bg split (caught by rendering
    ; the ROM and comparing against the intended cloud-only look).
    ; Zeroed here (VRAM-only patch, terrain_gen.py's own BLANK data
    ; untouched) so plain open sky stays genuinely blank.
    LD HL,HUD_ZERO8 : LD DE,SKY_BLANK_CODE*8 : LD BC,8 : CALL LDIRVM

    ; checkpoint 2: terrain patterns + color table loaded
    LD B,2 : LD C,7 : CALL WRTVDP

    LD HL,TERRAIN_BLANK_ROW : LD DE,1800h : LD BC,768 : CALL LDIRVM

    ; checkpoint 3: whole name table cleared to sky
    LD B,3 : LD C,7 : CALL WRTVDP

    ; row16: SkySand pattern + its own dedicated color group, static
    ; one-time fill. rows17-19: plain Sand fill (TERRAIN_BLANK_CODE, the
    ; scrolling terrain's own BLANK code/color - no new group needed).
    LD HL,SKYSAND_PATTERN : LD DE,SKYSAND_CODE*8 : LD BC,8 : CALL LDIRVM
    LD A,SKYSAND_COLOR : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+31 : LD BC,1 : CALL LDIRVM
    LD HL,TERRAIN_ROW_SKYSAND : LD DE,1A00h : LD BC,32 : CALL LDIRVM
    LD HL,TERRAIN_ROW_SAND : LD DE,1A20h : LD BC,32 : CALL LDIRVM
    LD HL,TERRAIN_ROW_SAND : LD DE,1A40h : LD BC,32 : CALL LDIRVM
    LD HL,TERRAIN_ROW_SAND : LD DE,1A60h : LD BC,32 : CALL LDIRVM

    XOR A
    LD (TICK),A
    LD HL,0
    LD (PXCHAR_T),HL
    LD (ROWPHASE_T),A

    LD HL,TERRAIN_ROWDATA0 : LD IX,IDCACHE_T0 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA1 : LD IX,IDCACHE_T1 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA2 : LD IX,IDCACHE_T2 : CALL REFRESH_IDCACHE_33
    LD HL,TERRAIN_ROWDATA3 : LD IX,IDCACHE_T3 : CALL REFRESH_IDCACHE_33

    ; checkpoint 4: rows16-19 filled, terrain IDCACHEs primed
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

    ; F's own BG pattern: loaded twice, once per background color group
    ; it can appear over (see BULLETF_SKY_CODE etc. above), and the
    ; mirrored (left-facing) shape the same way at its own codes.
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN : LD DE,BULLETF_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN : LD DE,BULLETF_L_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN : LD DE,BULLETF_L_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM

    ; F's own bullet color groups: patch over terrain_gen.py's generic
    ; per-group defaults for the 2 groups its codes live in - see
    ; BULLET_SKY_COLORADDR/BULLET_ROCK_COLORADDR above.
    LD A,BULLET_SKY_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_SKY_COLORADDR : LD BC,1 : CALL LDIRVM
    LD A,BULLET_ROCK_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_ROCK_COLORADDR : LD BC,1 : CALL LDIRVM

    ; U's own hw sprite pattern (16x16, right after PAT_EXPLOSION).
    LD HL,BULLET_U_SPRITE : LD DE,PAT_BULLETU*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BULLET_U_SPRITE_L : LD DE,PAT_BULLETU_L*8+SPRPAT : LD BC,32 : CALL LDIRVM

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
    LD (TANK_ZUM_STANDING),A
    LD (JUMP_STAND_BASELINE),A
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

    ; PSG: everything (shot, explosion, "kin" deflect) lives on channel
    ; A only now - "サウンドはノイズｃｈ使用音は別にしなくていいぞ
    ; どうせ被れば消える PSGは3ch+ノイズ1chが仕様 2chはBGM用に常に空け
    ; ておきたいしな" - channels B/C stay silent and completely untouched
    ; from here on (volume 0, never written again) so they're free for
    ; future BGM. Each SOUND_* routine sets mixer R7 itself when
    ; triggered (MIXER_NOISE_A for shot/explosion, MIXER_TONE_A for the
    ; deflect ping) since channel A now has to switch between noise and
    ; tone mode depending on which sound last fired; this just primes a
    ; silent boot state (SND_TIMER=0 makes R8=0 regardless of mixer
    ; mode).
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    XOR A : LD (SND_TIMER),A : LD (SND_DECAY),A : LD (SND_EXPLODING),A
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

    ; Zum's own pattern (enemy_gen.py, generated alongside ZacoII's -
    ; no flip needed, it never reverses direction).
    LD HL,ENEMY_ZUM : LD DE,PAT_ZUM*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,ENEMY_ZUM_FLIP : LD DE,PAT_ZUM_FLIP*8+SPRPAT : LD BC,32 : CALL LDIRVM

    ; BigZum's own patterns (bigzum_gen.py) - both poses, both facings,
    ; 128 bytes each (4 quadrants x32 bytes, same per-pose size as the
    ; tank's own loads above) - "なので添付のデータは反転も生成".
    LD HL,BIGZUM_BIGZUM_TL    : LD DE,PAT_BIGZUM*8+SPRPAT    : LD BC,128 : CALL LDIRVM
    LD HL,BIGZUM_BIGZUMP_TL   : LD DE,PAT_BIGZUMP*8+SPRPAT   : LD BC,128 : CALL LDIRVM
    LD HL,BIGZUM_BIGZUM_L_TL  : LD DE,PAT_BIGZUM_L*8+SPRPAT  : LD BC,128 : CALL LDIRVM
    LD HL,BIGZUM_BIGZUMP_L_TL : LD DE,PAT_BIGZUMP_L*8+SPRPAT : LD BC,128 : CALL LDIRVM

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

    ; same priming for BULLET_U_SPRITE_ATTRS (hw sprite slots7-9) - the
    ; VRAM attribute table itself is already hidden by INIT_SPRATR_CLR's
    ; full 32-slot clear, but this RAM staging buffer starts blank.
    LD HL,BULLET_U_SPRITE_ATTRS
    LD B,3
IBSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IBSA_LOOP

    ; Zum pool: same generic zero-then-assign-Z_SPRIDX shape as the
    ; enemy pool above, plus its own sprite-attrs priming.
    LD HL,ZUM_POOL
    LD B,ZUM_SLOT_SIZE*ZUM_SLOT_COUNT
    XOR A
IZZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IZZ_LOOP
    LD (ZUM_SPAWN_TIMER),A

    LD HL,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
    LD C,0
IZSP_LOOP:
    PUSH HL
    POP IX
    LD A,C : LD (IX+4),A
    INC C
    LD DE,ZUM_SLOT_SIZE : ADD HL,DE
    DJNZ IZSP_LOOP

    LD HL,ZUM_SPRITE_ATTRS
    LD B,ZUM_SLOT_COUNT
IZSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IZSA_LOOP

    ; BigZum pool: same generic zero-then-assign-SPRIDX shape as the
    ; Zum pool above, plus its own sprite-attrs priming (BIGZUM_SLOT_
    ; COUNT*4 hw sprite entries this time, not 1 per slot - see
    ; BIGZUM_SPRITE_ATTRS's own comment).
    LD HL,BIGZUM_POOL
    LD B,BIGZUM_SLOT_SIZE*BIGZUM_SLOT_COUNT
    XOR A
IBZZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IBZZ_LOOP
    LD (BIGZUM_SPAWN_TIMER),A

    LD HL,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
    LD C,0
IBZSP_LOOP:
    PUSH HL
    POP IX
    LD A,C : LD (IX+4),A
    INC C
    LD DE,BIGZUM_SLOT_SIZE : ADD HL,DE
    DJNZ IBZSP_LOOP

    LD HL,BIGZUM_SPRITE_ATTRS
    LD B,BIGZUM_SLOT_COUNT*4
IBZSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IBZSA_LOOP

    ; cloud pool: each of the 6 slots gets its own fixed ROW (2-7,
    ; CLOUD_ROW_TABLE)/INTERVAL/FIXED4 from the 3 lookup tables below,
    ; ROWADDR precomputed once (row*32 fits an 8-bit low byte for
    ; rows0-7, so the high byte is always 18h - no per-frame lookup
    ; needed later), and a random initial WAIT so all 6 don't spawn in
    ; lockstep - same idea as CLOUDW/CLOUDN's own idle-at-boot random
    ; wait in src/CYBER SHMUP.asm. C is the table index (0-5); PUSH BC
    ; around the CALL protects both it and the outer DJNZ counter B,
    ; same precaution as every other pool loop in this file after the
    ; enemy-pool DJNZ/B-clobber bug (see README).
    LD HL,CLOUD_POOL
    LD B,CLOUD_SLOT_COUNT
    LD C,0
ICL_LOOP:
    PUSH HL
    POP IX
    XOR A : LD (IX+0),A                       ; ACT=0

    PUSH BC
    LD A,C : LD E,A : LD D,0
    LD HL,CLOUD_ROW_TABLE : ADD HL,DE : LD A,(HL)
    ADD A,A : ADD A,A : ADD A,A : ADD A,A : ADD A,A   ; row*32 (row<=7, fits in 8 bits)
    LD (IX+7),A
    LD A,18h : LD (IX+8),A
    LD A,C : LD E,A : LD D,0
    LD HL,CLOUD_INTERVAL_TABLE : ADD HL,DE : LD A,(HL) : LD (IX+1),A
    LD A,C : LD E,A : LD D,0
    LD HL,CLOUD_FIXED4_TABLE : ADD HL,DE : LD A,(HL) : LD (IX+2),A
    CALL CLOUD_RANDOM_WAIT
    LD (IX+5),A
    POP BC

    PUSH IX
    POP HL
    LD DE,CLOUD_SLOT_SIZE : ADD HL,DE
    INC C
    DJNZ ICL_LOOP

    ; checkpoint 9: enemy patterns + pool set up - about to enter MAINLOOP
    LD B,9 : LD C,7 : CALL WRTVDP

    ; border back to black - checkpoints 1-9 above were diagnostic
    ; only, leaving it on whatever the last one was (blue) would
    ; otherwise sit there as a permanent, confusing border color.
    LD B,1 : LD C,7 : CALL WRTVDP

MAINLOOP:
    LD A,(TICK) : INC A : LD (TICK),A

    ; GAME_RNG += TICK, every single frame, unconditionally - see
    ; GAME_RNG's own comment for why a flat +1-per-read counter wasn't
    ; enough to break resonance with fixed-interval consumers.
    LD B,A
    LD A,(GAME_RNG) : ADD A,B : LD (GAME_RNG),A
    LD A,(TICK)

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
    CALL UPDATE_TANK_ZUM_STAND
    CALL UPDATE_POSE
    CALL UPDATE_TANK_SPRITES
    ; bullets advance before a new one can spawn, so a shot fired this
    ; frame gets drawn once (at the muzzle) instead of being advanced
    ; a 2nd time by this same frame's UPDATE_BULLETS sweep.
    CALL UPDATE_BULLETS
    CALL UPDATE_SHOT
    CALL UPDATE_ENEMIES
    CALL CHECK_BULLET_VS_ENEMY
    CALL UPDATE_BULLET_U_SPRITES
    CALL UPDATE_ZUM_ALL
    CALL CHECK_BULLET_VS_ZUM
    CALL UPDATE_TANK_ZUM_PUSH
    CALL UPDATE_BIGZUM_ALL
    CALL CHECK_BULLET_VS_BIGZUM
    CALL UPDATE_TANK_BIGZUM_PUNCH
    CALL CLOUD_UPDATE_ALL

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

    ; move TANK_GROUND_Y toward the tier's target Y via the shared
    ; TERRAIN_EASE_Y easing routine (below) instead of snapping
    ; straight there - see TERRAIN_EASE_Y's own comment for the full
    ; history of why (jolt-on-tier-change, terrain-scroll pace
    ; matching, the moving-vs-stationary split, the catch-up
    ; threshold). E=1 while actively steering (TANK_DX!=0), else 0.
    LD A,(TANK_TIER) : LD E,A : LD D,0
    LD HL,TANK_TIER_Y_TABLE : ADD HL,DE
    LD A,(HL) : LD B,A            ; B = target Y
    LD A,(TANK_GROUND_Y) : LD C,A ; C = current (smoothed) Y
    LD A,(TANK_DX) : OR A
    LD E,0
    JR Z,UTC_EASE_CALL
    LD E,1
UTC_EASE_CALL:
    CALL TERRAIN_EASE_Y
    LD (TANK_GROUND_Y),A

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

; ---------- shared terrain-Y easing (tank & Zum) ----------
; Input: B=target Y, C=current Y, E=1 if actively steering/moving
; (else 0). Output: A=new eased Y. Trashes D.
;
; Factored out of UPDATE_TERRAIN_COLLISION so Zum's own ground-follow
; (UOZ_TERRAIN_FOLLOW) can call the byte-identical routine the tank
; uses, per direct instruction: "坂の上り下りも自機と全く同じ処理に
; しないとガタガタの8px昇降になる". Was previously a second, simpler
; copy (flat ZUM_CLIMB_SPEED/frame, no catch-up threshold) which read
; as exactly that kind of jitter on real hardware.
;
; Moves toward the target at TANK_CLIMB_SPEED instead of snapping
; straight there - snapping the full 8px in one frame looked like a
; jolt/jitter at every tier change, per direct instruction ("登り降り
; 時に一気に8px移動してるんでガタついてる...滑らかに繋げて"). A flat
; 2px/frame finished each climb in 4 frames - much faster than the
; terrain itself actually scrolls a transition by (measured ~16 frames
; between chained tier changes with the tank stationary), so the climb
; looked detached from the terrain's own motion and, chained back-to-
; back, visibly paused waiting for the next tier - "連続Gapだと一瞬
; 止まってる...地形に沿って移動じゃなく地形に入ったら自分で8pxのぼっ
; てる...地形の移動とマッチしてない". Gated to every other frame
; (TICK bit0) so 1px/step averages 0.5px/frame, matching that ~16-
; frame pace.
;
; That pace was measured with the tank standing still, though - the
; probe column also moves when actively steering, so moving toward
; oncoming terrain lets the probe advance through tiers faster than
; the stationary baseline (especially through the rapid-chain section,
; where consecutive markers are close together) - at the slow pace
; alone, the eased Y then falls behind by more than one tier and the
; tank visibly sinks into the rock for a stretch - "左右移動が加わると
; Gapに突っ込んでる...登ってはいるが地形にめり込んでる". Once
; TANK_CLIMB_CATCHUP_THRESHOLD behind, switch to catching up at
; TANK_CLIMB_CATCHUP_SPEED every frame (no gate) instead - once back
; under the threshold, the smooth slow pace above takes back over for
; the final approach. Still sinking in slightly with the original
; threshold(9)/speed(4) - "まだ少しだがめり込んでる" - so the
; threshold is tighter (5) and the catch-up itself faster (8, enough
; to close any realistic single-frame gap in one step) to stamp out
; the residual lag. And while actively steering (E=1), the moving-
; speed pace (TANK_CLIMB_SPEED_MOVING, ungated) is used below the
; threshold instead of the terrain-matched slow one - a single
; ordinary climb's own diff=8 start could otherwise grow before the
; slow pace closes it, reading as sinking into the rock - "まだ左右
; 移動で地形めり込んでるな...速度1.5の影響っぽい".
TERRAIN_EASE_Y:
    LD A,C
    CP B
    JR Z,TEY_DONE
    JR C,TEY_DIFF_BELOW
    LD A,C : SUB B                ; diff = current-target (current>target)
    JR TEY_DIFF_READY
TEY_DIFF_BELOW:
    LD A,B : SUB C                ; diff = target-current (current<target)
TEY_DIFF_READY:
    CP TANK_CLIMB_CATCHUP_THRESHOLD
    JR C,TEY_BELOW_THRESHOLD      ; diff below threshold: not a multi-tier backlog
    LD D,TANK_CLIMB_CATCHUP_SPEED
    JR TEY_STEP
TEY_BELOW_THRESHOLD:
    LD A,E
    OR A
    JR NZ,TEY_MOVING
    LD A,(TICK) : AND 1
    JR NZ,TEY_DONE_KEEP
    LD D,TANK_CLIMB_SPEED
    JR TEY_STEP
TEY_MOVING:
    LD D,TANK_CLIMB_SPEED_MOVING
TEY_STEP:
    LD A,C
    CP B
    JR C,TEY_RISE
    ; current > target (numerically lower on screen, i.e. climbing) -
    ; step down toward it, clamping so it can't undershoot past it
    SUB D
    CP B
    JR NC,TEY_RET
    LD A,B
    RET
TEY_RISE:
    ; current < target (descending) - step up toward it, clamping so
    ; it can't overshoot past it
    LD A,C : ADD A,D
    CP B
    JR C,TEY_RET
    LD A,B
TEY_RET:
    RET
TEY_DONE_KEEP:
    LD A,C
    RET
TEY_DONE:
    LD A,B
    RET

; ---------- jump (B button, edge-triggered, 24px half-sine arc) ----------
; "乗っかり中にジャンプできないんでオートジャンプ中でも出来るように" -
; a new press was always refused whenever JUMP_ACTIVE was already set,
; which is continuously true the entire time the tank is parked on a
; Zum (the auto-land cycle above never actually clears JUMP_ACTIVE,
; only rewinds JUMP_FRAME - see JUMP_LANDING_RESTART_FRAME). Now also
; honored while TANK_ZUM_STANDING is set, so a fresh press works from
; a parked-on-Zum stand exactly like from ordinary ground - an
; ordinary *mid-air* jump (JUMP_ACTIVE set, not parked) still can't be
; re-triggered, unchanged.
UPDATE_JUMP:
    LD A,(JOY_TRIGB)
    LD HL,PREV_TRIGB
    CP (HL)
    JR Z,UJ_NO_NEW_PRESS
    OR A
    JR Z,UJ_NO_NEW_PRESS
    LD A,(JUMP_ACTIVE)
    OR A
    JR Z,UJ_START_FRESH
    LD A,(TANK_ZUM_STANDING)
    OR A
    JR Z,UJ_NO_NEW_PRESS
    ; re-jumping from a parked stand: capture the current elevation
    ; above true ground ("ジャンプが加算されて地面までの距離が変わり")
    ; so the new arc adds on top of where the tank already is instead
    ; of first snapping down to TANK_GROUND_Y and jumping from there.
    LD A,(TANK_GROUND_Y) : LD B,A
    LD A,(TANK_Y_CUR)
    LD C,A
    LD A,B : SUB C : LD (JUMP_STAND_BASELINE),A
    XOR A : LD (JUMP_FRAME),A
    JR UJ_NO_NEW_PRESS
UJ_START_FRESH:
    LD A,1 : LD (JUMP_ACTIVE),A
    XOR A : LD (JUMP_FRAME),A
    LD (JUMP_STAND_BASELINE),A
UJ_NO_NEW_PRESS:
    LD A,(JOY_TRIGB) : LD (PREV_TRIGB),A

    LD A,(JUMP_ACTIVE)
    OR A
    JR Z,UJ_DONE
    LD A,(JUMP_FRAME) : INC A : LD (JUMP_FRAME),A
    CP JUMP_FRAMES
    JR C,UJ_STILL_JUMPING
    ; would end here - if still parked on a Zum (see TANK_ZUM_STANDING
    ; above), auto-land instead: restart from the table's own peak so
    ; it eases back down to ground instead of snapping. This is also
    ; where a table "overflow" past its last entry is always avoided -
    ; JUMP_FRAME never advances past this check without either
    ; restarting at JUMP_LANDING_RESTART_FRAME or ending (below), so
    ; UJ_DONE's own table read is never out of bounds even across a
    ; re-jump.
    LD A,(TANK_ZUM_STANDING)
    OR A
    JR Z,UJ_END_NORMALLY
    LD A,JUMP_LANDING_RESTART_FRAME : LD (JUMP_FRAME),A
    JR UJ_STILL_JUMPING
UJ_END_NORMALLY:
    XOR A
    LD (JUMP_ACTIVE),A
    LD (JUMP_FRAME),A
    LD (JUMP_STAND_BASELINE),A
UJ_STILL_JUMPING:
UJ_DONE:
    LD A,(JUMP_FRAME) : LD E,A : LD D,0
    LD HL,JUMP_OFFSET_TABLE : ADD HL,DE
    LD A,(HL) : LD B,A
    LD A,(JUMP_STAND_BASELINE) : ADD A,B
    LD (JUMP_Y_OFFSET),A

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

    ; ROW = TANK_Y_CUR >> 3 (name-table row), +2 more for a straight/F
    ; shot only - U (diagonal) keeps the un-shifted muzzle row. Was +1
    ; ("BulletFのセル表示を1セル下に"), widened to +2 to match the new
    ; BulletF.json art (its chevron moved from the bottom of its 8x8
    ; cell to the top) - "自機の下から8ドット上に描画と判定が来ないと
    ; 16x16の敵を...当たらない...表示と判定を一致させるため...銃口に
    ; 合わせる意味もある". With the new art's content starting at the
    ; cell's own top row (no in-cell offset, unlike the old art's
    ; rows5-7), +1 alone would land 7-8px above TankF.json's actual gun
    ; muzzle (measured from that file's own bits: barrel tip rows10-13,
    ; centered ~row11-12) - +2 lands within 1px of it instead. Grounded
    ; F therefore lands 2 rows past the tank's own row (row19->21),
    ; inside the scrolling band - fine, see BULLET_ROCK_ROW_MIN above.
    LD A,(TANK_Y_CUR)
    SRL A
    SRL A
    SRL A
    LD B,A
    LD A,(IX+1)
    OR A
    JR NZ,TSB_ROW_SET
    INC B
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

    ; F draws its BG cell immediately; U is a hw sprite now - its own
    ; position gets set by UPDATE_BULLET_U_SPRITES (called later this
    ; same frame, after TRY_SPAWN_BULLET's caller returns), not here.
    LD A,(IX+1)
    OR A
    JR NZ,TSB_SPAWN_U
    CALL DRAW_BULLET_CELL
TSB_SPAWN_U:
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
; For F (BG), erases the current cell (restoring sky/SkySand/Sand,
; whichever this bullet is actually over) - U is a hw sprite now, so
; there's nothing drawn in the name table to erase for it (skipping
; this for U also keeps a bullet from stomping a cloud/Sand/etc cell
; it's merely flying over). Then advances 1 column (toward FACING -
; right or left) and, for a diagonal/U shot, 1 row up too, then
; redraws (F only) at the new position - or deactivates if it just
; left the name table's top, left, or right edge.
UPDATE_ONE_BULLET:
    LD A,(IX+0)
    OR A
    RET Z

    LD A,(IX+1)
    OR A
    JR NZ,UOB_SKIP_ERASE
    CALL ERASE_BULLET_CELL
UOB_SKIP_ERASE:

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

    ; "ショットは地形貫通しない 今はRock225だけなんで当たったら弾は
    ; 消す" - only the scrolling terrain band (rows20-23) can hold
    ; Rock225 content; same id>=3 test as UPDATE_TERRAIN_COLLISION's
    ; own slope check (ids3-6 = R225/R225D, vs plain ROCK/BLANK's 0-2).
    ; IDCACHE_T0..T3 are indexed by screen column directly and spaced
    ; 48 bytes apart (see UPDATE_TERRAIN_COLLISION's own comment).
    LD A,(IX+3)
    CP 20
    JR C,UOB_DRAW
    SUB 20
    LD B,A
    LD A,(IX+2) : LD E,A : LD D,0
    LD A,B
    OR A
    JR NZ,UOB_TC1
    LD HL,IDCACHE_T0 : JR UOB_TC_ADD
UOB_TC1:
    CP 1
    JR NZ,UOB_TC2
    LD HL,IDCACHE_T1 : JR UOB_TC_ADD
UOB_TC2:
    CP 2
    JR NZ,UOB_TC3
    LD HL,IDCACHE_T2 : JR UOB_TC_ADD
UOB_TC3:
    LD HL,IDCACHE_T3
UOB_TC_ADD:
    ADD HL,DE
    LD A,(HL)
    CP 3
    JR NC,UOB_DEACTIVATE

UOB_DRAW:
    ; F only - U is a hw sprite, positioned separately every frame by
    ; UPDATE_BULLET_U_SPRITES (the old SkySand skip-draw special case
    ; is gone along with the rest of U's BG handling - a sprite just
    ; composites over whatever's there, nothing to special-case).
    LD A,(IX+1)
    OR A
    RET NZ
    CALL DRAW_BULLET_CELL
    RET
UOB_DEACTIVATE:
    XOR A : LD (IX+0),A
    RET

; IX = slot base. row<16 sky, row==16 SkySand restore, rows17-19 Sand
; restore (all static, only ever written at INIT), row>19 skip
; entirely - rows20-23 already got fully redrawn from NAMEBUF earlier
; this same MAINLOOP iteration, so there's nothing to restore. Shared
; by UPDATE_ONE_BULLET's own per-frame erase-before-advance and
; CHECK_BULLET_VS_ENEMY (a bullet that hits an enemy needs the exact
; same cell restored immediately, not left to redraw stale next frame).
ERASE_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_ROW_MIN
    JR C,EBC_SKY
    CP BULLET_ROCK_ROW_MIN+4
    JR NC,EBC_SKIP
    CP BULLET_ROCK_ROW_MIN
    JR Z,EBC_SKYSAND
    LD A,TERRAIN_BLANK_CODE
    JR EBC_WRITE
EBC_SKYSAND:
    LD A,SKYSAND_CODE
    JR EBC_WRITE
EBC_SKY:
    LD A,SKY_BLANK_CODE
EBC_WRITE:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    CALL WRITE_BULLET_BYTE_HL
EBC_SKIP:
    RET

; IX = slot base. F only now (U is a hw sprite - see
; UPDATE_BULLET_U_SPRITES). Picks the pattern code for (background-
; under-current-row x FACING) and writes it at ADDR+COL.
DRAW_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_COLOR_ROW_MIN_F
    JR NC,DBC_ROCK
    LD A,(IX+6)
    OR A
    JR NZ,DBC_SKY_LEFT
    LD A,BULLETF_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_LEFT:
    LD A,BULLETF_L_SKY_CODE
    JR DBC_CODE_SET
DBC_ROCK:
    LD A,(IX+6)
    OR A
    JR NZ,DBC_ROCK_LEFT
    LD A,BULLETF_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_LEFT:
    LD A,BULLETF_L_ROCK_CODE
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
; countdown and channel A's volume (0-15, see SOUND_UPDATE); SND_DECAY
; is how fast it counts down - see SHOT_SND_PEAK/SHOT_SND_DECAY's own
; comment for why this decays faster than the others below. Sets the
; mixer to noise-A mode itself since channel A now also carries the
; deflect ping's tone sound - "サウンドはノイズｃｈ使用音は別にしなく
; ていいぞ どうせ被れば消える" (whichever sound fires most recently
; simply overwrites SND_TIMER/SND_DECAY/the mixer, cutting off
; whatever was still playing - accepted, not a bug).
; "爆発音はショット音で消えるとまずいんで爆発音は鳴り終わるまで継続
; しショット音で消えないように" - refuses to fire at all while
; SND_EXPLODING is set, leaving the explosion's own SND_TIMER/mixer
; completely undisturbed instead of overwriting them.
SOUND_SHOT:
    LD A,(SND_EXPLODING)
    OR A
    RET NZ
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,SHOT_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,SHOT_SND_PEAK : LD (SND_TIMER),A
    LD A,SHOT_SND_DECAY : LD (SND_DECAY),A
    RET

; explosion sound - channel A, noise-only, byte-for-byte the same
; period(20)/timer(15) src/CYBER SHMUP.asm's own SOUND_DESTROY uses -
; "爆発音追加 Stage1の爆発音流用". Decays 1/frame (15 frames) same as
; that file's own pacing - no held-fire-style concern like the shot
; sound's own faster decay, explosions don't repeat rapidly enough to
; matter, and overlapping with a shot/deflect sound is fine to just
; cut off per the shared-channel design above.
SOUND_DESTROY:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,20 : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    LD A,1 : LD (SND_DECAY),A
    LD A,1 : LD (SND_EXPLODING),A
    RET

; "キンキン" metallic ping for a bullet absorbed by Zum's own front
; invincibility - "Zumの前面無敵に弾が当たったらキンキンと言うサウンド
; 追加 これはStage1のボスの弾き音流用". Channel A tone period(10) still
; byte-for-byte src/CYBER SHMUP.asm's own SOUND_POD_HIT (registers 0/1
; instead of that routine's own 4/5, since this now plays on channel A
; rather than a dedicated C). Peak 12, decays 1/frame - "音が小さいな
; 12くらいに上げてくれ".
SOUND_ZUM_DEFLECT:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_TONE_A : OUT (PSG_DATA),A
    LD A,0 : OUT (PSG_ADDR),A
    LD A,10 : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,12 : LD (SND_TIMER),A
    LD A,1 : LD (SND_DECAY),A
    XOR A : LD (SND_EXPLODING),A
    RET

; single shared channel-A envelope for every sound above - writes
; SND_TIMER's own current value as the volume (register8, 0-15), then
; steps it toward 0 by SND_DECAY (clamped so it can't undershoot past
; 0 - see SOUND_SHOT/SOUND_DESTROY/SOUND_ZUM_DEFLECT for how each
; sound picks its own peak/decay pair when triggered).
SOUND_UPDATE:
    LD A,(SND_TIMER)
    LD B,A
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,(SND_TIMER)
    OR A
    RET Z
    LD A,(SND_DECAY) : LD C,A
    LD A,(SND_TIMER)
    CP C
    JR NC,SU_STEP
    XOR A : LD (SND_TIMER),A : LD (SND_EXPLODING),A
    RET
SU_STEP:
    SUB C : LD (SND_TIMER),A
    OR A
    RET NZ
    LD (SND_EXPLODING),A
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
    ; GAME_RNG instead of raw TICK - "ZakoIIの...ランダムパラメータ
    ; 一定で固定されてるときがある" traced to TICK being sampled at a
    ; perfectly regular phase (this spawn timer always reloads to the
    ; same fixed ENEMY_SPAWN_INTERVAL), so its own masked low bits
    ; cycled through the same short, fully predictable sequence every
    ; time - see GAME_RNG's own comment.
    LD A,(GAME_RNG) : AND ENEMY_SKY_Y_MASK : ADD A,ENEMY_SKY_Y_MIN : LD (IX+E_Y),A
    XOR A : LD (IX+E_RETREAT),A : LD (IX+E_TIMER),A

    ; "あとZakoIIが10機でたら(Zumと同じタイミング)あとは赤ZakoIIと緑
    ; ZakoIIランダムで" - once the threshold is reached, every further
    ; spawn is a 50/50 coin flip instead of permanently red.
    LD A,(ENEMY_SPAWN_COUNT)
    CP 10
    JR C,AES_VARIANT_GREEN
    LD A,(GAME_RNG) : INC A : LD (GAME_RNG),A
    AND 1
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
; (E_VARIANT=1) is a flat ENEMY_SPEED_RED - "ZakoIIはの赤は速度３で";
; green is ENEMY_SPEED_LO alternating with +1 on odd TICK frames (same
; trick as TANK_SPEED_LO/UTX_DO_RIGHT), averaging 1.5px/frame - "自機
; と同じ1.5で". Either way, while retreating (E_RETREAT=1) the result
; is doubled before returning - "帰る時は倍速で" (green -> 3px/frame
; avg, red -> 6px/frame flat home). Shared by both the approach and
; retreat branches in UPDATE_ONE_ENEMY below.
ENEMY_GET_STEP:
    LD A,(IX+E_VARIANT)
    OR A
    JR NZ,EGS_RED
    LD A,(TICK) : AND 1 : LD B,A
    LD A,ENEMY_SPEED_LO : ADD A,B
    JR EGS_BASE_DONE
EGS_RED:
    LD A,ENEMY_SPEED_RED
EGS_BASE_DONE:
    LD B,A
    LD A,(IX+E_RETREAT)
    OR A
    JR Z,EGS_RETURN_BASE
    LD A,B : ADD A,B
    RET
EGS_RETURN_BASE:
    LD A,B
    RET

; IX = slot base. Distance-ramped wrapper around ENEMY_GET_STEP, used
; near the turnback pivot on both legs - "ZukuIIにもサイン減速 で、
; 反転して帰っていく際はサイン加速 速度は今のままでいい". Outside
; ENEMY_RAMP_RANGE px of the pivot on either side, falls straight
; through to plain ENEMY_GET_STEP unchanged (the "速度は今のままでいい"
; cruise speed, both legs) - only the last ENEMY_RAMP_RANGE px of the
; approach (easing down to a stop right at the pivot) and the first
; ENEMY_RAMP_RANGE px of the retreat (easing back up to full retreat
; speed) read ENEMY_DECEL_TABLE_*/ENEMY_ACCEL_TABLE_* instead, indexed
; directly by distance-to-pivot (not elapsed frames) - self-correcting
; every frame regardless of how TANK_X itself moves meanwhile.
ENEMY_GET_STEP_RAMPED:
    LD A,(IX+E_RETREAT)
    OR A
    JR NZ,EGSR_RETREAT

EGSR_APPROACH:
    ; approaching: E_X is always >= TANK_X+MARGIN while E_RETREAT=0
    ; (that's exactly the condition that keeps E_RETREAT at 0), so this
    ; subtraction never underflows here.
    LD A,(TANK_X) : ADD A,ENEMY_TURNBACK_MARGIN : LD B,A
    LD A,(IX+E_X) : SUB B
    CP ENEMY_RAMP_RANGE
    JR NC,EGSR_FULL
    LD C,A
    LD A,(IX+E_VARIANT)
    OR A
    LD HL,ENEMY_DECEL_TABLE_GREEN
    JR Z,EGSR_ADD
    LD HL,ENEMY_DECEL_TABLE_RED
    JR EGSR_ADD

EGSR_RETREAT:
    ; retreating: E_X can still be slightly short of TANK_X+MARGIN
    ; right after the flip (this frame's approach overshot it by a few
    ; px before the flip was noticed) - clamp that underflow to 0
    ; (right at the pivot) rather than treating it as "far away".
    LD A,(TANK_X) : ADD A,ENEMY_TURNBACK_MARGIN : LD B,A
    LD A,(IX+E_X) : SUB B
    JR NC,EGSR_RETREAT_POS
    XOR A
EGSR_RETREAT_POS:
    CP ENEMY_RAMP_RANGE
    JR NC,EGSR_FULL
    LD C,A
    LD A,(IX+E_VARIANT)
    OR A
    LD HL,ENEMY_ACCEL_TABLE_GREEN
    JR Z,EGSR_ADD
    LD HL,ENEMY_ACCEL_TABLE_RED

EGSR_ADD:
    LD A,C : LD E,A : LD D,0
    ADD HL,DE
    LD A,(HL)
    RET

EGSR_FULL:
    JP ENEMY_GET_STEP

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

    CALL ENEMY_GET_STEP_RAMPED : LD B,A
    LD A,(IX+E_X) : SUB B : LD (IX+E_X),A
    LD A,(TANK_X) : ADD A,ENEMY_TURNBACK_MARGIN : LD B,A
    LD A,(IX+E_X)
    CP B
    JR NC,UOE_DRAW
    LD A,1 : LD (IX+E_RETREAT),A
    JR UOE_DRAW

UOE_RETREAT:
    CALL ENEMY_GET_STEP_RAMPED : LD B,A
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

    ; F needs its BG cell restored immediately on a hit; U is a hw
    ; sprite (nothing drawn in the name table to erase) - UPDATE_
    ; BULLET_U_SPRITES will hide it once it sees ACT=0 below.
    LD A,(IX+1)
    OR A
    JR NZ,CHP_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHP_SKIP_ERASE:
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

; ---------- Zum: spawn timer, then all slots (see ZUM_SLOT_SIZE above) ----------
UPDATE_ZUM_ALL:
    LD A,(ZUM_SPAWN_TIMER)
    OR A
    JR Z,UZA_TRY_SPAWN
    DEC A : LD (ZUM_SPAWN_TIMER),A
    JR UZA_UPDATE_ALL
UZA_TRY_SPAWN:
    CALL ALLOC_ZUM_SLOT
UZA_UPDATE_ALL:
    LD IX,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
UZAU_LOOP:
    PUSH BC
    CALL UPDATE_ONE_ZUM
    POP BC
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UZAU_LOOP
    CALL FLUSH_ZUM_SPRITES
    RET

; A=1 if the terrain at ZUM_SPAWN_COL is genuinely flat ground at the
; lowest tier (IDCACHE_T0/T1/T2 all BLANK there - nothing above tier3
; yet - and IDCACHE_T3 is a steady plain-rock id, not a Rock225 climb/
; descend marker), else 0 - "上りがない地形最下部でスポーン". Same
; walk-down-tiers probe UPDATE_TERRAIN_COLLISION uses, just as a
; boolean test at a fixed column instead of driving TANK_TIER. Trashes
; A,DE,HL.
ZUM_TERRAIN_OK:
    LD A,ZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,ZTO_FAIL
    LD A,ZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,ZTO_FAIL
    LD A,ZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,ZTO_FAIL
    LD A,ZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T3 : ADD HL,DE : LD A,(HL)
    CP 3
    JR NC,ZTO_FAIL
    OR A
    JR Z,ZTO_FAIL
    LD A,1
    RET
ZTO_FAIL:
    XOR A
    RET

; gated on 3 things, all must hold: the red-ZacoII threshold reached
; ("赤ZakoIIが10体で終わったら" - reuses ENEMY_SPAWN_COUNT, ZacoII's
; own spawning keeps running unaffected - "ZakoIIは継続"), the terrain
; is currently flat at the spawn column (ZUM_TERRAIN_OK), and a slot
; is free (pool of ZUM_SLOT_COUNT=2 - "横並び制限"). Any failure just
; retries next frame (ZUM_SPAWN_TIMER stays 0) rather than waiting out
; a fixed interval - the terrain condition is transient (the track
; scrolls continuously) so polling every frame catches the next flat
; window as soon as it appears.
;
; NOT gated on tank distance any more - "しかしスポーンキャンセルでは
; 自機が右端に居続けると永遠にスポーンできない 自機が右端にいたら
; 押してスポーンするように": a previous round refused to spawn at all
; while the tank was within ZUM_DETECT_RANGE of the spawn point, to
; stop a fresh Zum from spawning too close and sliding through instead
; of pushing - but that meant Zum could never spawn again if the tank
; simply stayed near the right edge, a real softlock for this enemy
; type specifically. Replaced with AZS_FOUND's own instant overlap
; resolution below instead of refusing the spawn.
ALLOC_ZUM_SLOT:
    LD A,(ENEMY_SPAWN_COUNT)
    CP 10
    RET C
    CALL ZUM_TERRAIN_OK
    OR A
    RET Z

    LD HL,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
AZS_LOOP:
    LD A,(HL)
    OR A
    JR Z,AZS_FOUND
    LD DE,ZUM_SLOT_SIZE : ADD HL,DE
    DJNZ AZS_LOOP
    RET
AZS_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+0),A
    LD A,ZUM_SPAWNX : LD (IX+1),A
    LD A,TANK_Y_BASE : ADD A,ZUM_Y_OFFSET : LD (IX+2),A   ; tier3's own Y, +12 for Zum's own ground-line math (see ZUM_Y_OFFSET)
    XOR A : LD (IX+3),A : LD (IX+7),A
    LD A,ZUM_SPAWN_INTERVAL : LD (ZUM_SPAWN_TIMER),A

    ; "自機が右端にいたら押してスポーンするように" - if the tank is
    ; already within push range of this brand-new Zum, resolve the
    ; overlap immediately instead of waiting for the next few frames of
    ; UPDATE_TANK_ZUM_PUSH's own rate-limited clamp to catch up - closes
    ; the window a same-frame slip-through could happen in, without
    ; blocking the spawn itself the way the previous round's distance
    ; gate did.
    LD A,ZUM_SPAWNX-TANK_PUSH_WIDTH : LD B,A   ; target TANK_X
    LD A,(TANK_X)
    CP B
    RET C          ; TANK_X already < target - clear, nothing to resolve
    LD A,B : LD (TANK_X),A
    RET

; IX = slot base. E_ACT=1: probes the terrain under its own column and
; eases Z_Y toward the target tier, then advances Z_X - flat ZUM_SPEED_
; BASE while farther than ZUM_DETECT_RANGE from the tank; inside it,
; sine-decelerates through ZUM_DECEL_TABLE. Once decelerated all the
; way into the near-tank zone (distance<ZUM_MID_RANGE) with Z_RETREAT
; still undecided(0), rolls once between charging in (sine-accelerates
; back up through ZUM_ACCEL_TABLE, same as before - Z_RETREAT=2) or
; fleeing back off the right edge (sine-accelerates away through ZUM_
; FLEE_TABLE - Z_RETREAT=1) - "自機の前まで減速したら押してくるやつ
; と反転して逃げるやつをランダムに 引き返しもサイン移動で". All 3
; speed tables are indexed directly by distance, not elapsed frames.
; Unsigned-subtraction wraparound naturally also keeps an undecided/
; charging Zum at full ZUM_SPEED_BASE if TANK_X briefly reads higher
; (already passed). E_ACT=2: same drift-then-hide explosion shape as
; UPDATE_ONE_ENEMY's own UOE_EXPLODING, reusing EXPLOSION_DURATION/
; PATTERN/COLOR.
UPDATE_ONE_ZUM:
    LD A,(IX+0)
    CP 2
    JP Z,UOZ_EXPLODING
    OR A
    RET Z

    CALL UOZ_TERRAIN_FOLLOW

UOZ_MOVE:
    LD A,(IX+7)
    CP 1
    JP Z,UOZ_FLEE_MOVE
    CP 3
    JP Z,UOZ_PAUSE_MOVE

    LD A,(IX+1) : LD B,A
    LD A,(TANK_X)
    LD C,A
    LD A,B : SUB C            ; Z_X-TANK_X; wraps large if Z_X<TANK_X (already passed) - falls through to full speed below either way
    LD D,A                     ; D = distance, preserved across the branches below
    CP ZUM_DETECT_RANGE
    JR NC,UOZ_SPEED_FULL
    CP ZUM_MID_RANGE
    JR NC,UOZ_SPEED_DECEL      ; distance in [40,79]: outer half, sine-decelerating

    ; distance<40: near-tank zone
    LD A,(IX+7)
    OR A
    JR NZ,UOZ_SPEED_ACCEL      ; already decided to charge (2) - proceed as before

    ; still undecided - enter the pause state instead of rolling and
    ; moving on this same frame - "ツッコミと反転の分岐時に少し止まっ
    ; てから反転するか突っ込むかに変更". UOZ_PAUSE_MOVE (below) rolls
    ; once ZUM_PAUSE_FRAMES of standing still have elapsed.
    LD A,3 : LD (IX+7),A
    LD A,ZUM_PAUSE_FRAMES : LD (IX+3),A
    JP UOZ_PAUSE_MOVE

UOZ_SPEED_ACCEL:
    LD A,D : LD E,A : LD D,0   ; index=distance directly
    LD HL,ZUM_ACCEL_TABLE : ADD HL,DE
    LD A,(HL)
    JR UOZ_SPEED_SET
UOZ_SPEED_DECEL:
    LD A,D : SUB ZUM_MID_RANGE ; index=distance-40
    LD E,A : LD D,0
    LD HL,ZUM_DECEL_TABLE : ADD HL,DE
    LD A,(HL)
    JR UOZ_SPEED_SET
UOZ_SPEED_FULL:
    LD A,ZUM_SPEED_BASE
UOZ_SPEED_SET:
    LD B,A
    ; despawn only once X can no longer subtract this frame's own speed
    ; without underflowing - covers both "自機がジャンプで避けると
    ; そのまま左に消える" (nothing blocked it, it just kept going) and
    ; the normal off-screen exit, reaching X=0 before disappearing
    ; instead of a fixed margin short of the edge (see the constant
    ; block's own comment above).
    LD A,(IX+1)
    CP B
    JR NC,UOZ_MOVE_OK
    XOR A : LD (IX+0),A
    CALL UOZ_HIDE
    RET
UOZ_MOVE_OK:
    LD A,(IX+1) : SUB B : LD (IX+1),A
    JR UOZ_DRAW

; fleeing (Z_RETREAT=1): moves away (increasing X) instead of toward
; the tank, sine-accelerating via ZUM_FLEE_TABLE - same distance-
; indexed shape as the approach tables, just indexed by *growing*
; distance from the tank (like ZacoII's own retreat leg) instead of
; shrinking. Despawns once it reaches back off the spawn edge, same
; "CP ZUM_SPAWNX" convention as UOE_RETREAT.
UOZ_FLEE_MOVE:
    LD A,(IX+1) : LD B,A
    LD A,(TANK_X)
    LD C,A
    LD A,B : SUB C
    JR NC,UOZ_FLEE_GAP_OK
    XOR A                      ; underflow (Zum_X<TANK_X) - clamp to 0, right at the tank
UOZ_FLEE_GAP_OK:
    CP ZUM_MID_RANGE
    JR NC,UOZ_FLEE_SPEED_FULL
    LD E,A : LD D,0
    LD HL,ZUM_FLEE_TABLE : ADD HL,DE
    LD A,(HL)
    JR UOZ_FLEE_SPEED_SET
UOZ_FLEE_SPEED_FULL:
    LD A,ZUM_FLEE_SPEED
UOZ_FLEE_SPEED_SET:
    LD B,A
    LD A,(IX+1) : ADD A,B : LD (IX+1),A
    CP ZUM_SPAWNX
    JR C,UOZ_DRAW
    XOR A : LD (IX+0),A
    CALL UOZ_HIDE
    RET

; pausing (Z_RETREAT=3): motionless for ZUM_PAUSE_FRAMES (counted down
; in +3, reused from the explosion timer field since it's otherwise
; idle while alive), then rolls once between charging (2, ZUM_ACCEL_
; TABLE) and fleeing (1, UOZ_FLEE_MOVE) - "少し止まってから反転するか
; 突っ込むかに変更". Distance is recomputed fresh here rather than
; carried over from UOZ_MOVE's own dispatch, since this can also be
; reached fresh next frame while still counting down.
UOZ_PAUSE_MOVE:
    LD A,(IX+3)
    OR A
    JR Z,UOZ_PAUSE_ROLL
    DEC A : LD (IX+3),A
    JR UOZ_DRAW
UOZ_PAUSE_ROLL:
    LD A,(GAME_RNG) : INC A : LD (GAME_RNG),A
    AND 1
    JR NZ,UOZ_PAUSE_DECIDE_CHARGE
    LD A,1 : LD (IX+7),A
    JP UOZ_FLEE_MOVE
UOZ_PAUSE_DECIDE_CHARGE:
    LD A,2 : LD (IX+7),A
    LD A,(IX+1) : LD B,A
    LD A,(TANK_X)
    LD C,A
    LD A,B : SUB C
    LD D,A
    JP UOZ_SPEED_ACCEL

UOZ_DRAW:
    LD A,(IX+4) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ZUM_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(IX+7) : CP 1
    JR Z,UOZ_DRAW_FLIP
    LD A,PAT_ZUM : JR UOZ_DRAW_PAT_SET
UOZ_DRAW_FLIP:
    LD A,PAT_ZUM_FLIP
UOZ_DRAW_PAT_SET:
    LD (HL),A : INC HL
    LD A,ZUM_COLOR : LD (HL),A
    RET

UOZ_EXPLODING:
    LD A,(IX+3)
    OR A
    JR Z,UOZ_EXPLODE_HIDE
    DEC A : LD (IX+3),A
    LD A,(IX+1) : LD B,A : LD A,(IX+5) : ADD A,B : LD (IX+1),A
    LD A,(IX+2) : LD B,A : LD A,(IX+6) : ADD A,B : LD (IX+2),A
UOZ_DRAW_EXPLOSION:
    LD A,(IX+4) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ZUM_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A
    RET
UOZ_EXPLODE_HIDE:
    XOR A : LD (IX+0),A
    CALL UOZ_HIDE
    RET

UOZ_HIDE:
    LD A,(IX+4) : ADD A,A : ADD A,A : LD C,A : LD B,0
    LD HL,ZUM_SPRITE_ATTRS : ADD HL,BC
    LD A,209 : LD (HL),A
    RET

; IX = slot base. Probes IDCACHE_T0..T3 at this Zum's own column
; ((Z_X+ZUM_PROBE_DX)>>3, its horizontal center) for the first non-BLANK
; tier, same walk as UPDATE_TERRAIN_COLLISION, then eases Z_Y toward
; TANK_TIER_Y_TABLE[tier] via the SAME TERRAIN_EASE_Y subroutine the
; tank's own UPDATE_TERRAIN_COLLISION uses - "坂の上り下りも自機と全く
; 同じ処理にしないとガタガタの8px昇降になる": this used to be its own
; simplified flat ZUM_CLIMB_SPEED/frame ease (no catch-up-threshold
; refinement), which is exactly the "ガタガタの8px昇降" the tank's own
; climb code went through several rounds to eliminate - reusing the
; tank's exact routine instead of re-deriving a second copy of that
; tuning.
UOZ_TERRAIN_FOLLOW:
    LD A,(IX+1) : ADD A,ZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTF_T0
    LD A,(IX+1) : ADD A,ZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTF_T1
    LD A,(IX+1) : ADD A,ZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UTF_T2
    LD A,3
    JR UTF_TIER_SET
UTF_T0:
    XOR A
    JR UTF_TIER_SET
UTF_T1:
    LD A,1
    JR UTF_TIER_SET
UTF_T2:
    LD A,2
UTF_TIER_SET:
    LD E,A : LD D,0
    LD HL,TANK_TIER_Y_TABLE : ADD HL,DE : LD A,(HL)
    ADD A,ZUM_Y_OFFSET          ; ground-line-matched target for a 16px sprite - see ZUM_Y_OFFSET
    LD B,A                     ; B = target Y
    LD A,(IX+2) : LD C,A       ; C = current Z_Y
    LD E,1                     ; Zum is always "moving" (never stands idle)
    CALL TERRAIN_EASE_Y
    LD (IX+2),A
    RET

; blasts ZUM_SPRITE_ATTRS (8 bytes) to hw sprite slots
; ZUM_SPR_BASE_SLOT..+1 - same raw DI-wrapped OUT + 8-NOP pattern as
; FLUSH_ENEMY_SPRITES/FLUSH_BULLET_U_SPRITES.
FLUSH_ZUM_SPRITES:
    DI
    LD A,ZUM_SPR_BASE_SLOT*4 : OUT (99h),A
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
    LD HL,ZUM_SPRITE_ATTRS
    LD B,8
FZS_LOOP:
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
    DJNZ FZS_LOOP
    EI
    RET

; "自機がジャンプで避けるとそのまま左に消える" - suspended entirely
; while airborne, letting a Zum slide underneath uninterrupted. Must
; run after UPDATE_ZUM_ALL (uses each Zum's already-advanced X this
; frame) - one frame later than TANK_X's own terrain-collision/sprite-
; draw for this same frame, so a push only visually lands next frame;
; accepted as a minor lag, same class as every other post-tank-sprite
; system in this MAINLOOP (enemies, clouds).
; "お互い貫通せず止まること つまり何も操作しなければ敵に押される" -
; the Zum's own X always advances at its own pace regardless (computed
; above, unaffected by the tank); contact instead clamps TANK_X to stay
; flush with whichever Zum is nearest, so a stationary player gets
; shoved left as the enemy keeps coming - the player can still move
; freely away, just never *into* an active Zum.
UPDATE_TANK_ZUM_PUSH:
    LD A,(JUMP_ACTIVE)
    OR A
    RET NZ
    LD IX,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
UTZP_LOOP:
    LD A,(IX+0)
    CP 1
    JR NZ,UTZP_NEXT
    ; "めり込みでそのまま通過するとZumは消えてしまってる...自機の
    ; 移動量を考慮してないな" - once TANK_X reaches/passes Zum's own X
    ; (moving right through it, the overlap left as-is per direct
    ; instruction), the clamp below used to keep firing anyway,
    ; dragging TANK_X backward to chase Zum's own X - it kept doing
    ; this even while the player held right the entire time (verified:
    ; TANK_X actually *decreased* from 59 to 35 over 20 frames of
    ; continuous right input), reading as Zum "vanishing" right in
    ; front of the tank once both converged near its normal despawn
    ; point instead of the tank passing cleanly through. The clamp
    ; only makes sense while Zum is still ahead of the tank (approaching
    ; from the right) - once passed, skip this slot entirely.
    LD A,(IX+1)
    LD D,A
    LD A,(TANK_X)
    CP D
    JR NC,UTZP_NEXT             ; TANK_X>=Zum_X - already passed, no longer blocks
    LD A,D
    SUB TANK_PUSH_WIDTH
    LD C,A                     ; C = target TANK_X (flush against this Zum)
    LD A,(TANK_X)
    CP C
    JR C,UTZP_NEXT             ; TANK_X already < target - no overlap, nothing to do
    ; in contact - apply the FULL push speed unconditionally every
    ; frame instead of clamping/snapping toward the target boundary -
    ; "無操作時の押し量が変わってない...パラメータを変えても変わって
    ; ないのでバグだろうな": the old snap-to-target-when-close branch
    ; made the tank converge to exactly gap=32 and then just track that
    ; target 1:1 forever after - once locked on, TANK_X's *sustained*
    ; rate of movement was actually whatever Zum's own current speed
    ; happened to be (often as low as 1, near the decel trough), not
    ; ZUM_PUSH_SPEED at all - which is exactly why raising that
    ; constant had no visible effect. Now the tank gets shoved the full
    ; ZUM_PUSH_SPEED every single frame it's in contact, independent of
    ; Zum's own pace, overshooting past the nominal 32px buffer on
    ; purpose (contact simply disengages for a frame or two until Zum
    ; catches back up, then pushes again) instead of settling into a
    ; perfectly smooth, barely-there 1:1 tracking.
    LD A,(TANK_X)
    CP ZUM_PUSH_SPEED
    JR NC,UTZP_STEP
    XOR A : LD (TANK_X),A       ; underflow floor at 0
    JR UTZP_NEXT
UTZP_STEP:
    LD A,(TANK_X) : SUB ZUM_PUSH_SPEED : LD (TANK_X),A
UTZP_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UTZP_LOOP
    RET

; "Zumにジャンプで乗っかるとめり込んでくな ここはめり込まないように" -
; while airborne and horizontally overlapping an active Zum, clamp
; TANK_Y_CUR so the tank's own bottom never sinks below Zum's own top
; surface - landing on top instead of sinking through. Only while
; JUMP_ACTIVE (grounded overlap is the horizontal push's own job above,
; not this - unguarded here would make the tank appear to stand on
; Zum even while normally grounded and merely pushing into it). Runs
; right after UPDATE_JUMP (before UPDATE_TANK_SPRITES) so this same
; frame's sprite draw reflects it, but against ZUM_POOL's position
; from last frame - Zum's own move for this frame hasn't run yet, same
; 1-frame-stale precedent as UPDATE_TANK_ZUM_PUSH.
UPDATE_TANK_ZUM_STAND:
    LD A,(JUMP_ACTIVE)
    OR A
    JR NZ,UTZS_START
    XOR A : LD (TANK_ZUM_STANDING),A
    RET
UTZS_START:
    ; TANK_ZUM_STANDING accumulates to 1 below the moment any slot
    ; actually clamps this call, read by UPDATE_JUMP next frame to
    ; auto-land instead of snapping - see JUMP_LANDING_RESTART_FRAME.
    XOR A : LD (TANK_ZUM_STANDING),A
    LD IX,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
UTZS_LOOP:
    LD A,(IX+0)
    CP 1
    JR NZ,UTZS_NEXT
    ; horizontal overlap: TANK_X < Zum_X+16 AND Zum_X < TANK_X+TANK_PUSH_WIDTH
    LD A,(IX+1) : ADD A,16 : LD D,A
    LD A,(TANK_X)
    CP D
    JR NC,UTZS_NEXT
    LD A,(TANK_X) : ADD A,TANK_PUSH_WIDTH : LD D,A
    LD A,(IX+1)
    CP D
    JR NC,UTZS_NEXT
    ; overlap confirmed - clamp so the tank's bottom rests on Zum's own top,
    ; using the same anchor-to-surface offset as standing on ordinary
    ; terrain (TANK_GROUND_OFFSET, not the horizontal TANK_PUSH_WIDTH -
    ; see TANK_GROUND_OFFSET's own comment)
    LD A,(IX+2) : SUB TANK_GROUND_OFFSET : LD D,A
    LD A,(TANK_Y_CUR)
    CP D
    JR C,UTZS_NEXT              ; TANK_Y_CUR already above (less than) the stand height - still clear
    LD A,D : LD (TANK_Y_CUR),A
    LD A,1 : LD (TANK_ZUM_STANDING),A
UTZS_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UTZS_LOOP
    RET

; ---------- bullet x Zum collision: front (left half) absorbs the ----------
; ---------- shot with no effect, rear (right half) destroys it       ----------
; "正面からは無敵で弾は止まること 破壊条件は後ろから撃たれた場合の
; み" - Zum only ever moves left, so its own left half is permanently
; its "front" and its right half its "back", independent of which way
; the bullet itself was travelling. Same AABB shape as CHECK_HIT_PAIR
; (enemy box widened to 15); the front/back split is a 2nd check on
; top of that, against the Zum's own horizontal midpoint.
CHECK_BULLET_VS_ZUM:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET_ZUM
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET_ZUM
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET_ZUM
    RET

CHECK_HIT_ONE_BULLET_ZUM:
    LD IY,ZUM_POOL
    LD B,ZUM_SLOT_COUNT
CHOBZ_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR_ZUM
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOBZ_LOOP
    RET

CHECK_HIT_PAIR_ZUM:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+0)
    CP 1
    RET NZ

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(IY+1) : LD D,A
    LD A,(IY+2) : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,15 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,15 : CP C : RET C

    ; front/back is decided by the TANK's own position relative to
    ; Zum (TANK_X>=Zum_X - the same "already passed" test
    ; UPDATE_TANK_ZUM_PUSH uses), not the bullet's own pixel position -
    ; "でZum貫通中にショット撃ってると背中に当たって倒してしまう": the
    ; muzzle spawns at TANK_X+~24, so while pushing forward into the
    ; still-allowed overlap (still approaching from the front, hasn't
    ; actually gotten behind it), a bullet could already spawn past
    ; Zum's own midpoint on pure spawn-position math alone, letting a
    ; point-blank shot cheese the "must attack from behind" rule
    ; without ever actually maneuvering around it. Tying this to the
    ; tank's own position instead means only genuinely being behind
    ; Zum (same criterion the push-block already uses) ever counts.
    ;
    ; Inverted while fleeing (Z_RETREAT=1): a fleeing Zum has turned to
    ; face right (PAT_ZUM_FLIP, moving away), so its own front is now
    ; its right side - TANK_X>Zum_X is in front of it, TANK_X<Zum_X is
    ; now its exposed back.
    LD A,(IY+1) : LD D,A              ; D = Zum_X
    LD A,(IY+7)
    CP 1
    JR Z,CHPZ_ORIENT_FLEE
    LD A,(TANK_X)
    CP D
    JR NC,CHPZ_REAR
    JR CHPZ_FRONT
CHPZ_ORIENT_FLEE:
    LD A,(TANK_X)
    CP D
    JR NC,CHPZ_FRONT
    JR CHPZ_REAR

CHPZ_FRONT:

    ; front: absorb only - erase F's own BG cell (U has nothing to
    ; erase), deactivate the bullet, no score/explosion - "キンキン"
    ; deflect sound only (SOUND_ZUM_DEFLECT).
    LD A,(IX+1)
    OR A
    JR NZ,CHPZ_FRONT_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPZ_FRONT_SKIP_ERASE:
    XOR A : LD (IX+0),A
    CALL SOUND_ZUM_DEFLECT
    RET

CHPZ_REAR:
    LD A,(IX+1)
    OR A
    JR NZ,CHPZ_REAR_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPZ_REAR_SKIP_ERASE:
    XOR A : LD (IX+0),A

    LD A,2 : LD (IY+0),A
    LD A,EXPLOSION_DURATION : LD (IY+3),A

    LD A,(TICK) : AND 7 : LD C,A : LD B,0
    LD HL,EXPLODE_DIR_DX : ADD HL,BC : LD A,(HL) : LD (IY+5),A
    LD HL,EXPLODE_DIR_DY : ADD HL,BC : LD A,(HL) : LD (IY+6),A

    CALL SOUND_DESTROY

    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; ---------- BigZum: spawn/update/draw (see BIGZUM_SLOT_SIZE's own ----------
; ---------- comment block for the state machine overview)           ----------
UPDATE_BIGZUM_ALL:
    LD A,(BIGZUM_SPAWN_TIMER)
    OR A
    JR Z,UBZA_TRY_SPAWN
    DEC A : LD (BIGZUM_SPAWN_TIMER),A
    JR UBZA_UPDATE_ALL
UBZA_TRY_SPAWN:
    CALL ALLOC_BIGZUM_SLOT
UBZA_UPDATE_ALL:
    LD IX,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
UBZAU_LOOP:
    PUSH BC
    CALL UPDATE_ONE_BIGZUM
    POP BC
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UBZAU_LOOP
    CALL FLUSH_BIGZUM_SPRITES
    RET

; same flat-ground probe as ZUM_TERRAIN_OK, just at BigZum's own wider
; (32px) spawn column.
BIGZUM_TERRAIN_OK:
    LD A,BIGZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,BZTO_FAIL
    LD A,BIGZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,BZTO_FAIL
    LD A,BIGZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,BZTO_FAIL
    LD A,BIGZUM_SPAWN_COL : LD E,A : LD D,0
    LD HL,IDCACHE_T3 : ADD HL,DE : LD A,(HL)
    CP 3
    JR NC,BZTO_FAIL
    OR A
    JR Z,BZTO_FAIL
    LD A,1
    RET
BZTO_FAIL:
    XOR A
    RET

; same 3-condition gate as ALLOC_ZUM_SLOT (spawn-count threshold, flat
; terrain, free slot) plus the same instant-overlap resolution at
; spawn - "スポーン条件は同じ".
ALLOC_BIGZUM_SLOT:
    LD A,(ENEMY_SPAWN_COUNT)
    CP 10
    RET C
    CALL BIGZUM_TERRAIN_OK
    OR A
    RET Z

    LD HL,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
ABZS_LOOP:
    LD A,(HL)
    OR A
    JR Z,ABZS_FOUND
    LD DE,BIGZUM_SLOT_SIZE : ADD HL,DE
    DJNZ ABZS_LOOP
    RET
ABZS_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+0),A
    LD A,BIGZUM_SPAWNX : LD (IX+1),A
    LD A,TANK_Y_BASE : LD (IX+2),A   ; tier3's own Y - BigZum shares the tank's own 32px anchor convention, no offset needed (see BIGZUM_SLOT_SIZE's own comment block)
    XOR A
    LD (IX+3),A
    LD (IX+5),A
    LD (IX+6),A
    LD (IX+7),A
    LD (IX+9),A
    LD (IX+10),A
    LD (IX+11),A
    LD A,BIGZUM_HP_INIT : LD (IX+8),A
    LD A,BIGZUM_SPAWN_INTERVAL : LD (BIGZUM_SPAWN_TIMER),A

    LD A,BIGZUM_SPAWNX-TANK_PUSH_WIDTH : LD B,A
    LD A,(TANK_X)
    CP B
    RET C
    LD A,B : LD (TANK_X),A
    RET

; IX = slot base. ACT=2: same drift-then-hide explosion shape as
; UOZ_EXPLODING (reuses EXPLOSION_DURATION/PATTERN/COLOR/EXPLODE_DIR),
; just showing the single 16x16 explosion sprite on quadrant-slot0 and
; hiding the other 3 quadrant hw sprites for this instance. ACT=1:
; dispatches on STATE (+7) - jumping (1) skips the ordinary terrain
; follow entirely (its own Y comes from BIGZUM_JUMP_TABLE instead),
; every other state calls it first exactly like Zum's own UOZ_MOVE.
UPDATE_ONE_BIGZUM:
    LD A,(IX+0)
    CP 2
    JP Z,UOBZ_EXPLODING
    OR A
    RET Z

    LD A,(IX+7)
    CP 1
    JP Z,UOBZ_JUMP_MOVE

    CALL UOBZ_TERRAIN_FOLLOW

    LD A,(IX+7)
    CP 3
    JP Z,UOBZ_PAUSE_MOVE
    CP 2
    JP Z,UOBZ_PUNCH_MOVE

    ; STATE=0: approaching - identical distance-indexed decel to Zum's
    ; own charge leg (ZUM_DETECT_RANGE/ZUM_MID_RANGE/ZUM_DECEL_TABLE) -
    ; "アルゴリズムもほぼ同じ".
    LD A,(IX+1) : LD D,A
    LD A,(TANK_X) : LD E,A
    LD A,D : SUB E
    LD D,A                      ; D = distance (BZ_X-TANK_X)
    CP ZUM_DETECT_RANGE
    JR NC,UOBZ_SPEED_FULL
    CP ZUM_MID_RANGE
    JR NC,UOBZ_SPEED_DECEL

    ; near-tank zone, still undecided - pause before rolling punch-vs-
    ; jump, same "少し止まってから" pause Zum itself uses.
    LD A,3 : LD (IX+7),A
    LD A,ZUM_PAUSE_FRAMES : LD (IX+3),A
    JP UOBZ_PAUSE_MOVE

UOBZ_SPEED_DECEL:
    LD A,D : SUB ZUM_MID_RANGE
    LD E,A : LD D,0
    LD HL,ZUM_DECEL_TABLE : ADD HL,DE
    LD A,(HL)
    JR UOBZ_SPEED_SET
UOBZ_SPEED_FULL:
    LD A,ZUM_SPEED_BASE
UOBZ_SPEED_SET:
    LD B,A
    LD A,(IX+1)
    CP B
    JR NC,UOBZ_MOVE_OK
    XOR A : LD (IX+0),A
    CALL UOBZ_HIDE
    RET
UOBZ_MOVE_OK:
    LD A,(IX+1) : SUB B : LD (IX+1),A
    JP UOBZ_DRAW

; pausing (STATE=3): motionless for ZUM_PAUSE_FRAMES (reusing +3 as
; the countdown, same as Zum), then rolls once between punching (2)
; and jumping (1) - "違うのは停止後引き返さずパンチするかジャンプ
; して乗っかってくる".
UOBZ_PAUSE_MOVE:
    LD A,(IX+3)
    OR A
    JR Z,UOBZ_PAUSE_ROLL
    DEC A : LD (IX+3),A
    JP UOBZ_DRAW
UOBZ_PAUSE_ROLL:
    LD A,(GAME_RNG) : INC A : LD (GAME_RNG),A
    AND 1
    JR NZ,UOBZ_PAUSE_DECIDE_JUMP
    LD A,2 : LD (IX+7),A
    JP UOBZ_PUNCH_MOVE
UOBZ_PAUSE_DECIDE_JUMP:
    LD A,1 : LD (IX+7),A
    XOR A : LD (IX+10),A
    JP UOBZ_JUMP_MOVE

; punching (STATE=2): closes any remaining gap via ZUM_ACCEL_TABLE
; (same ease Zum's own charge uses), then holds position once within
; TANK_PUSH_WIDTH - the actual punch delivery (knockback + pose timer)
; is UPDATE_TANK_BIGZUM_PUNCH's own job, run once per frame from
; MAINLOOP after every BigZum has moved, same separation of concerns
; as UPDATE_TANK_ZUM_PUSH. FACING=1 (already landed behind the tank)
; always holds - it's already in punch range the instant it lands
; (see UOBZ_JUMP_MOVE's own landing check).
UOBZ_PUNCH_MOVE:
    LD A,(IX+3)
    OR A
    JR Z,UOBZP_TIMER_DONE
    DEC A : LD (IX+3),A
UOBZP_TIMER_DONE:
    LD A,(IX+9)
    OR A
    JR NZ,UOBZP_HOLD
    LD A,(IX+1) : LD D,A
    LD A,(TANK_X) : LD E,A
    LD A,D : CP E
    JR C,UOBZP_HOLD
    LD A,D : SUB E
    LD D,A
    CP TANK_PUSH_WIDTH
    JR C,UOBZP_HOLD
    CP ZUM_MID_RANGE
    JR NC,UOBZP_SPEED_FULL
    LD E,A : LD D,0
    LD HL,ZUM_ACCEL_TABLE : ADD HL,DE
    LD A,(HL)
    JR UOBZP_SPEED_SET
UOBZP_SPEED_FULL:
    LD A,ZUM_SPEED_BASE
UOBZP_SPEED_SET:
    LD B,A
    LD A,(IX+1) : SUB B : LD (IX+1),A
    JP UOBZ_DRAW
UOBZP_HOLD:
    JP UOBZ_DRAW

; jumping (STATE=1): sine arc via BIGZUM_JUMP_TABLE while still
; advancing toward the tank at BIGZUM_JUMP_XSPEED. If the arc
; completes while BigZum's own X still hasn't reached/passed the
; tank's (would land ON/in front of it), the arc simply restarts from
; frame0 instead of ending - "自機に設置したら連続ジャンプで飛び越え".
; Only once an arc completes with BigZum's X already at or past the
; tank's own X (genuinely cleared, landed behind) does it switch to
; STATE=2/FACING=1 - "自機の後ろを取って地上に降りたら後ろからパンチ".
UOBZ_JUMP_MOVE:
    LD A,(IX+1) : LD D,A
    LD A,(TANK_X) : LD E,A
    LD A,D : CP E
    JR C,UOBZJ_NO_XMOVE
    LD A,D : SUB BIGZUM_JUMP_XSPEED
    JR NC,UOBZJ_XSET
    XOR A
UOBZJ_XSET:
    LD (IX+1),A
UOBZJ_NO_XMOVE:

    LD A,(IX+10) : INC A
    CP BIGZUM_JUMP_FRAMES
    JR C,UOBZJ_FRAME_OK

    LD A,(IX+1) : LD D,A
    LD A,(TANK_X)
    CP D
    JR C,UOBZJ_CHAIN
    LD A,2 : LD (IX+7),A
    LD A,1 : LD (IX+9),A
    LD A,BIGZUM_PUNCH_INTERVAL : LD (IX+11),A
    XOR A : LD (IX+3),A
    JP UOBZ_DRAW
UOBZJ_CHAIN:
    XOR A : LD (IX+10),A
    JP UOBZJ_APPLY
UOBZJ_FRAME_OK:
    LD (IX+10),A
UOBZJ_APPLY:
    LD A,(IX+10) : LD E,A : LD D,0
    LD HL,BIGZUM_JUMP_TABLE : ADD HL,DE
    LD A,(HL) : LD B,A
    LD A,TANK_Y_BASE : SUB B     ; ground reference - see BIGZUM_JUMP_FRAMES's own comment on this simplification
    LD (IX+2),A
    JP UOBZ_DRAW

; IX = slot base. Probes IDCACHE_T0..T3 at BigZum's own column
; ((BZ_X+BIGZUM_PROBE_DX)>>3) and eases toward TANK_TIER_Y_TABLE
; [tier] via the shared TERRAIN_EASE_Y routine - identical to Zum's
; own UOZ_TERRAIN_FOLLOW, just no ZUM_Y_OFFSET-style add (BigZum is
; 32px tall like the tank itself, so TANK_TIER_Y_TABLE[tier] is
; already its own correct top-anchor - see BIGZUM_SLOT_SIZE's comment).
UOBZ_TERRAIN_FOLLOW:
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZTF_T0
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZTF_T1
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZTF_T2
    LD A,3
    JR UOBZTF_TIER_SET
UOBZTF_T0:
    XOR A
    JR UOBZTF_TIER_SET
UOBZTF_T1:
    LD A,1
    JR UOBZTF_TIER_SET
UOBZTF_T2:
    LD A,2
UOBZTF_TIER_SET:
    LD E,A : LD D,0
    LD HL,TANK_TIER_Y_TABLE : ADD HL,DE : LD A,(HL)
    LD B,A
    LD A,(IX+2) : LD C,A
    LD E,1
    CALL TERRAIN_EASE_Y
    LD (IX+2),A
    RET

; picks the current pattern base (PAT_BIGZUM/PAT_BIGZUMP x normal/_L)
; from STATE/+3(pose-timer)/FACING, then writes all 4 quadrant hw
; sprite entries into this instance's own slice of BIGZUM_SPRITE_ATTRS
; - same TL/TR/BL/BR layout and +4/+8/+12 pattern-offset convention as
; UPDATE_TANK_SPRITES.
UOBZ_DRAW:
    LD A,(IX+7)
    CP 2
    JR NZ,UOBZD_WALK
    LD A,(IX+3)
    OR A
    JR Z,UOBZD_WALK
    LD A,(IX+9)
    OR A
    JR Z,UOBZD_SET_BIGZUMP
    LD A,PAT_BIGZUMP_L : JR UOBZD_BASE_SET
UOBZD_SET_BIGZUMP:
    LD A,PAT_BIGZUMP : JR UOBZD_BASE_SET
UOBZD_WALK:
    LD A,(IX+9)
    OR A
    JR Z,UOBZD_SET_BIGZUM
    LD A,PAT_BIGZUM_L : JR UOBZD_BASE_SET
UOBZD_SET_BIGZUM:
    LD A,PAT_BIGZUM
UOBZD_BASE_SET:
    LD (BIGZUM_DRAW_TEMP),A

    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,BIGZUM_SPRITE_ATTRS : ADD HL,BC

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : LD (HL),A : INC HL
    LD A,BIGZUM_COLOR : LD (HL),A : INC HL

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,4 : LD (HL),A : INC HL
    LD A,BIGZUM_COLOR : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,8 : LD (HL),A : INC HL
    LD A,BIGZUM_COLOR : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,12 : LD (HL),A : INC HL
    LD A,BIGZUM_COLOR : LD (HL),A
    RET

UOBZ_EXPLODING:
    LD A,(IX+3)
    OR A
    JR Z,UOBZ_EXPLODE_HIDE
    DEC A : LD (IX+3),A
    LD A,(IX+1) : LD B,A : LD A,(IX+5) : ADD A,B : LD (IX+1),A
    LD A,(IX+2) : LD B,A : LD A,(IX+6) : ADD A,B : LD (IX+2),A

    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,BIGZUM_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A : INC HL
    LD B,3
UOBZE_HIDE_REST:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ UOBZE_HIDE_REST
    RET
UOBZ_EXPLODE_HIDE:
    XOR A : LD (IX+0),A
    CALL UOBZ_HIDE
    RET

UOBZ_HIDE:
    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,BIGZUM_SPRITE_ATTRS : ADD HL,BC
    LD B,4
UOBZH_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ UOBZH_LOOP
    RET

; blasts BIGZUM_SPRITE_ATTRS (32 bytes) to hw sprite slots
; BIGZUM_SPR_BASE_SLOT..+7 - same raw DI-wrapped OUT + 8-NOP pattern
; as FLUSH_ZUM_SPRITES.
FLUSH_BIGZUM_SPRITES:
    DI
    LD A,BIGZUM_SPR_BASE_SLOT*4 : OUT (99h),A
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
    LD HL,BIGZUM_SPRITE_ATTRS
    LD B,BIGZUM_SLOT_COUNT*16
FBZS_LOOP:
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
    DJNZ FBZS_LOOP
    EI
    RET

; delivers the actual punch effect (BIGZUM_PUNCH_INTERVAL-frame
; cadence knockback + BigZumP pose timer) for any BigZum currently in
; STATE=2 contact range - separated from UOBZ_PUNCH_MOVE the same way
; UPDATE_TANK_ZUM_PUSH is separated from Zum's own per-frame move, and
; run after it in MAINLOOP for the same 1-frame-stale-contact reason.
; FACING=0 (approaching from the front/right) knocks the tank left;
; FACING=1 (landed behind) knocks it right instead - "後ろからパンチ".
UPDATE_TANK_BIGZUM_PUNCH:
    LD IX,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
UTBP_LOOP:
    LD A,(IX+0)
    OR A
    JP Z,UTBP_NEXT
    LD A,(IX+7)
    CP 2
    JP NZ,UTBP_NEXT

    LD A,(IX+9)
    OR A
    JR NZ,UTBP_BEHIND

    LD A,(IX+1) : LD D,A
    LD A,D : SUB TANK_PUSH_WIDTH
    LD C,A
    LD A,(TANK_X)
    CP C
    JP C,UTBP_NEXT
    LD A,(IX+11)
    OR A
    JR NZ,UTBP_FRONT_DEC
    LD A,(TANK_X)
    CP BIGZUM_PUNCH_KNOCKBACK
    JR NC,UTBP_FRONT_APPLY
    XOR A : LD (TANK_X),A
    JR UTBP_FRONT_DONE
UTBP_FRONT_APPLY:
    LD A,(TANK_X) : SUB BIGZUM_PUNCH_KNOCKBACK : LD (TANK_X),A
UTBP_FRONT_DONE:
    LD A,BIGZUM_PUNCH_INTERVAL : LD (IX+11),A
    LD A,BIGZUM_PUNCH_POSE_FRAMES : LD (IX+3),A
    CALL SOUND_ZUM_DEFLECT
    JP UTBP_NEXT
UTBP_FRONT_DEC:
    DEC A : LD (IX+11),A
    JP UTBP_NEXT

UTBP_BEHIND:
    LD A,(IX+1) : LD D,A
    LD A,D : ADD A,TANK_PUSH_WIDTH
    LD C,A
    LD A,(TANK_X)
    CP C
    JP NC,UTBP_NEXT
    LD A,(IX+11)
    OR A
    JR NZ,UTBP_BEHIND_DEC
    LD A,(TANK_X) : ADD A,BIGZUM_PUNCH_KNOCKBACK
    CP 224
    JR C,UTBP_BEHIND_SET
    LD A,224
UTBP_BEHIND_SET:
    LD (TANK_X),A
    LD A,BIGZUM_PUNCH_INTERVAL : LD (IX+11),A
    LD A,BIGZUM_PUNCH_POSE_FRAMES : LD (IX+3),A
    CALL SOUND_ZUM_DEFLECT
    JP UTBP_NEXT
UTBP_BEHIND_DEC:
    DEC A : LD (IX+11),A
UTBP_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DEC B : JP NZ,UTBP_LOOP
    RET

; ---------- bullet x BigZum collision: same front-invincible/rear- ----------
; ---------- vulnerable shape as CHECK_HIT_PAIR_ZUM, keyed off        ----------
; ---------- BZ_FACING instead of Z_RETREAT, plus HP instead of a     ----------
; ---------- 1-hit kill - "攻撃判定も同じで後ろしか当たらない 耐久5". ----------
CHECK_BULLET_VS_BIGZUM:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET_BIGZUM
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET_BIGZUM
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET_BIGZUM
    RET

CHECK_HIT_ONE_BULLET_BIGZUM:
    LD IY,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
CHOBBZ_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR_BIGZUM
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOBBZ_LOOP
    RET

CHECK_HIT_PAIR_BIGZUM:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+0)
    CP 1
    RET NZ

    ; AABB, box widened to 31 (32px BigZum vs the bullet's own 8px cell)
    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(IY+1) : LD D,A
    LD A,(IY+2) : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,31 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,31 : CP C : RET C

    LD A,(IY+1) : LD D,A
    LD A,(IY+9)
    CP 1
    JR Z,CHPBZ_ORIENT_FLIP
    LD A,(TANK_X)
    CP D
    JR NC,CHPBZ_REAR
    JR CHPBZ_FRONT
CHPBZ_ORIENT_FLIP:
    LD A,(TANK_X)
    CP D
    JR NC,CHPBZ_FRONT
    JR CHPBZ_REAR

CHPBZ_FRONT:
    LD A,(IX+1)
    OR A
    JR NZ,CHPBZ_FRONT_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPBZ_FRONT_SKIP_ERASE:
    XOR A : LD (IX+0),A
    CALL SOUND_ZUM_DEFLECT
    RET

CHPBZ_REAR:
    LD A,(IX+1)
    OR A
    JR NZ,CHPBZ_REAR_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPBZ_REAR_SKIP_ERASE:
    XOR A : LD (IX+0),A

    LD A,(IY+8) : DEC A : LD (IY+8),A
    JR Z,CHPBZ_DESTROY
    CALL SOUND_ZUM_DEFLECT
    RET
CHPBZ_DESTROY:
    LD A,2 : LD (IY+0),A
    LD A,EXPLOSION_DURATION : LD (IY+3),A

    LD A,(TICK) : AND 7 : LD C,A : LD B,0
    LD HL,EXPLODE_DIR_DX : ADD HL,BC : LD A,(HL) : LD (IY+5),A
    LD HL,EXPLODE_DIR_DY : ADD HL,BC : LD A,(HL) : LD (IY+6),A

    CALL SOUND_DESTROY
    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; U's own hw sprite position: builds BULLET_U_SPRITE_ATTRS (3 slots x
; 4 bytes: Y,X,pat,col) straight from the bullet pool's own ROW/COL
; (same row*8/col*8 anchor the old BG cell used - no new position math
; needed) and flushes it to hw sprite slots BULLET_U_SPR_BASE_SLOT..+2
; (7-9). Bullet side stays 3 individually-named CALLs, same "not part
; of this instruction" precedent as CHECK_BULLET_VS_ENEMY's own bullet
; loop - only the enemy/cloud pools are genuine buffer+loop here.
UPDATE_BULLET_U_SPRITES:
    LD IX,BULLET0_ACT : LD DE,0 : CALL UBUS_ONE
    LD IX,BULLET1_ACT : LD DE,4 : CALL UBUS_ONE
    LD IX,BULLET2_ACT : LD DE,8 : CALL UBUS_ONE
    CALL FLUSH_BULLET_U_SPRITES
    RET

; IX = bullet slot base, DE = byte offset into BULLET_U_SPRITE_ATTRS
; (0/4/8). Hides the slot (Y=209, same convention as UOE_HIDE) unless
; it's an active U-type shot.
UBUS_ONE:
    LD HL,BULLET_U_SPRITE_ATTRS : ADD HL,DE
    LD A,(IX+0)
    OR A
    JR Z,UBUS_HIDE
    LD A,(IX+1)
    OR A
    JR Z,UBUS_HIDE
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD (HL),A : INC HL   ; Y = ROW*8
    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD (HL),A : INC HL   ; X = COL*8
    LD A,(IX+6)
    OR A
    JR NZ,UBUS_PAT_L
    LD A,PAT_BULLETU
    JR UBUS_PAT_SET
UBUS_PAT_L:
    LD A,PAT_BULLETU_L
UBUS_PAT_SET:
    LD (HL),A : INC HL
    LD A,BULLET_U_COLOR : LD (HL),A
    RET
UBUS_HIDE:
    LD A,209 : LD (HL),A
    RET

; blasts BULLET_U_SPRITE_ATTRS (12 bytes) to hw sprite slots
; BULLET_U_SPR_BASE_SLOT..+2 - same raw DI-wrapped OUT + 8-NOP,
; auto-incrementing-VDP-pointer pattern as FLUSH_ENEMY_SPRITES.
FLUSH_BULLET_U_SPRITES:
    DI
    LD A,BULLET_U_SPR_BASE_SLOT*4 : OUT (99h),A
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
    LD HL,BULLET_U_SPRITE_ATTRS
    LD B,12
FBUS_LOOP:
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
    DJNZ FBUS_LOOP
    EI
    RET

; walks CLOUD_POOL (IX-indexed, 9x INC IX per slot - this assembler has
; no ADD IX,DE, same as UE_UPDATE_ALL) calling UPDATE_ONE_CLOUD on every
; slot. PUSH/POP BC around the CALL: UPDATE_ONE_CLOUD's own cell-write
; helpers use B/C as scratch, which would otherwise corrupt this loop's
; DJNZ counter - same precaution as every other pool loop in this file.
CLOUD_UPDATE_ALL:
    LD IX,CLOUD_POOL
    LD B,CLOUD_SLOT_COUNT
CUA_LOOP:
    PUSH BC
    CALL UPDATE_ONE_CLOUD
    POP BC
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ CUA_LOOP
    RET

; IX = slot base. Idle (counting down WAIT) -> spawn at the right edge
; (picking WIDTH: forced 4 if FIXED4, else random 2/4) -> move 1 cell
; left every INTERVAL frames (erase old position, redraw new) -> once
; fully off the left edge, deactivate and pick a new random WAIT. Same
; shape as src/CYBER SHMUP.asm's own CLOUDW_UPDATE/CLOUDN_UPDATE.
UPDATE_ONE_CLOUD:
    LD A,(IX+0)
    OR A
    JR NZ,UOC_MOVE
    LD A,(IX+5)
    OR A
    JR Z,UOC_SPAWN
    DEC A : LD (IX+5),A
    RET
UOC_SPAWN:
    LD A,1 : LD (IX+0),A
    LD A,CLOUD_SPAWN_COL : LD (IX+3),A
    LD A,(IX+1) : LD (IX+4),A
    LD A,(IX+2)
    OR A
    JR NZ,UOC_SPAWN_W4
    CALL CLOUD_RANDOM_WIDTH
    JR UOC_SPAWN_WSET
UOC_SPAWN_W4:
    LD A,4
UOC_SPAWN_WSET:
    LD (IX+6),A
    RET
UOC_MOVE:
    LD A,(IX+4)
    DEC A
    LD (IX+4),A
    RET NZ
    LD A,(IX+1) : LD (IX+4),A
    CALL UOC_ERASE_CELLS
    LD A,(IX+3) : DEC A : LD (IX+3),A
    LD B,A
    LD A,(IX+6)
    CP 4
    JR Z,UOC_CHECKW4
    LD A,B
    CP 0FEh                      ; -2: both cells now fully off the left edge
    JR Z,UOC_DEACT
    JR UOC_DRAW
UOC_CHECKW4:
    LD A,B
    CP 0FCh                      ; -4: all 4 cells now fully off the left edge
    JR Z,UOC_DEACT
UOC_DRAW:
    CALL UOC_DRAW_CELLS
    RET
UOC_DEACT:
    XOR A : LD (IX+0),A
    CALL CLOUD_RANDOM_WAIT
    LD (IX+5),A
    RET

UOC_ERASE_CELLS:
    LD A,(IX+3) : LD B,A : LD C,SKY_BLANK_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+3) : INC A : LD B,A : LD C,SKY_BLANK_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+6)
    CP 4
    RET NZ
    LD A,(IX+3) : ADD A,2 : LD B,A : LD C,SKY_BLANK_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+3) : ADD A,3 : LD B,A : LD C,SKY_BLANK_CODE
    CALL UOC_WRITE_CELL
    RET

UOC_DRAW_CELLS:
    LD A,(IX+3) : LD B,A : LD C,CLOUD_A_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+3) : INC A : LD B,A : LD C,CLOUD_B_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+6)
    CP 4
    RET NZ
    LD A,(IX+3) : ADD A,2 : LD B,A : LD C,CLOUD_A_CODE
    CALL UOC_WRITE_CELL
    LD A,(IX+3) : ADD A,3 : LD B,A : LD C,CLOUD_B_CODE
    CALL UOC_WRITE_CELL
    RET

; B = column (signed two's-complement; a negative or >31 value reads
; as >=32 unsigned, so it's simply skipped - same clipping idiom as
; src/CYBER SHMUP.asm's own CLOUDW_ERASE_CELL/DRAW_CELL), C = code to
; write, IX = slot base (for its precomputed ROWADDR_LO/HI). Reuses
; WRITE_BULLET_BYTE_HL (a plain "write byte at VRAM address HL" raw
; DI/OUT primitive, not actually bullet-specific) instead of a 3rd copy
; of the same DI-wrapped OUT+8-NOP block.
UOC_WRITE_CELL:
    LD A,B
    CP 32
    RET NC
    LD A,C
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+7) : LD H,(IX+8)
    LD E,B : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL

; Output: A = a pseudo-random frame count (30-157) used as the idle
; wait before a cloud's next spawn - same range/shape as src/CYBER
; SHMUP.asm's own CLOUD_RANDOM_WAIT. Trashes A.
CLOUD_RANDOM_WAIT:
    LD A,(GAME_RNG) : INC A : LD (GAME_RNG),A
    AND 7Fh
    ADD A,30
    RET

; Output: A = 2 or 4 (random cloud width for a non-FIXED4 slot).
; Trashes A.
CLOUD_RANDOM_WIDTH:
    LD A,(GAME_RNG) : INC A : LD (GAME_RNG),A
    AND 1
    JR Z,CRW_2
    LD A,4
    RET
CRW_2:
    LD A,2
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

; sprites/SkySand.json, converted by hand (single static 8x8 tile, no
; blending/quadrants needed) - see the SKYSAND_CODE comment above.
SKYSAND_PATTERN:
    DB 255,0,255,255,0,255,0,255
TERRAIN_ROW_SKYSAND:
    DS 32,SKYSAND_CODE
TERRAIN_ROW_SAND:
    DS 32,TERRAIN_BLANK_CODE

; 33 entries (jump frame 0-32): a half-sine arc, offset(t) =
; round(24 * sin(pi*t/32)) - 24px peak at t=16, eased in/out (fast
; launch and landing, brief hang near the peak) instead of the
; earlier triangular (constant 1px/frame) ramp, per direct
; instruction ("サインジャンプ"). Sped up from the original 49-entry
; table (see JUMP_FRAMES above) - "ふわっと浮いて降りてる" felt too
; slow/floaty. JUMP_FRAMES above must match this table's length.
JUMP_OFFSET_TABLE:
    DB 0,2,5,7,9,11,13,15,17,19,20,21,22,23,24,24,24,24,24,23,22,21,20,19,17,15,13,11,9,7,5,2,0

; BigZum's own jump-on arc - same half-sine construction as
; JUMP_OFFSET_TABLE above (round(H*sin(pi*t/32)) for t=0..32), H=32
; instead of 24 - "ジャンプは自機より高く32ｐｘ サインジャンプ".
; BIGZUM_JUMP_FRAMES above must match this table's length.
BIGZUM_JUMP_TABLE:
    DB 0,3,6,9,12,15,18,20,23,25,27,28,30,31,31,32,32,32,31,31,30,28,27,25,23,20,18,15,12,9,6,3,0

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

; distance-to-tank-indexed sine eases, ZUM_MID_RANGE(40) entries each -
; see ZUM_SPEED_BASE's own comment. ZUM_DECEL_TABLE covers the outer
; half (distance 40-79, index=distance-40): index0 (d=40, closest point
; of this half) reads ~1.5, index39 (d=79, the detection edge) reads
; ~3. ZUM_ACCEL_TABLE covers the inner half (distance 0-39, index=
; distance directly): index0 (d=0, at the tank) reads ~3, index39
; (d=39, right where DECEL leaves off) reads ~1.5 - so the two tables
; meet at a matching ~1.5 in the middle of the 80px zone. Trough was
; originally a full stop-reading 1 - "減速目標を1から1.5に変更 1だと
; 止まって見えてしまうんで" (1 read as a dead stop, not a slowdown).
ZUM_DECEL_TABLE:
    DB 2,1,2,1,2,2,2,2,2,2,2,2,2,2,3,2
    DB 2,3,2,3,2,3,3,2,3,3,3,3,2,3,3,3
    DB 3,3,3,3,3,3,3,3
ZUM_ACCEL_TABLE:
    DB 3,3,3,3,2,3,3,2,3,2,3,2,2,3,2,2
    DB 2,2,2,2,2,2,2,2,1,2,2,1,2,2,1,2
    DB 1,2,1,2,1,2,1,2
; growing-distance-indexed sine ease for a fleeing Zum (index0=right
; at the tank, ~1.5; index39=edge of the ramp, full ZUM_FLEE_SPEED) -
; see ZUM_FLEE_SPEED's own comment. Same construction as the tables
; above (error-diffused, floored at 1).
ZUM_FLEE_TABLE:
    DB 2,1,2,1,2,2,2,2,2,2,2,2,2,2,3,2
    DB 2,3,2,3,2,3,3,2,3,3,3,3,2,3,3,3
    DB 3,3,3,3,3,3,3,3

; distance-from-pivot-indexed sine eases for ZacoII, ENEMY_RAMP_RANGE
; (32) entries each - see ENEMY_GET_STEP_RAMPED. DECEL tables ease the
; *approach* cruise speed down to 0 as ZacoII nears the turnback pivot
; (index0=at the pivot/stopped, index31=edge of the ramp zone/full
; cruise); ACCEL tables ease back up from 0 to the *retreat* cruise
; speed (already doubled, unchanged - "速度は今のままでいい") as it
; pulls away (index0=at the pivot/stopped, index31=edge of the ramp
; zone/full retreat speed). Generated via the same error-diffusion
; approach as ZUM_DECEL_TABLE, walked in the direction each table is
; actually traversed during play (DECEL: far->near, i.e. index31->0;
; ACCEL: near->far, i.e. index0->31).
; every entry in all 4 tables below is >=1 - guaranteed, not
; coincidental. A table entry of 0 would make the enemy freeze in
; place (distance-to-pivot unchanged next frame -> the same 0 entry
; read again -> forever), so unlike ZUM_DECEL_TABLE (whose whole
; range, 1.5-2.0, is naturally >=1), the DECEL tables here are floored
; at 1 instead of the pure eased curve's own true 0 at the pivot -
; ZacoII always creeps forward at least 1px/frame even at its slowest,
; guaranteeing it actually reaches and crosses the pivot to retreat.
ENEMY_DECEL_TABLE_GREEN:
    DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
    DB 1,2,1,1,1,2,1,1,2,1,2,1,2,1,1,2
ENEMY_DECEL_TABLE_RED:
    DB 1,1,1,1,1,1,1,2,1,1,1,2,2,2,2,2
    DB 2,2,2,3,2,3,3,3,2,3,3,3,3,3,3,3
ENEMY_ACCEL_TABLE_GREEN:
    DB 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2
    DB 2,3,2,3,2,3,2,3,3,3,3,3,3,3,3,3
ENEMY_ACCEL_TABLE_RED:
    DB 1,1,1,1,1,1,1,1,3,2,3,4,3,4,4,4
    DB 4,5,4,5,5,6,5,5,6,6,6,5,6,6,6,6

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

; fg6 (dark red, was the tank's) / bg11 (light yellow - "カラーグルー
; プ節約するから Rockも背景色ライトイエローにしろ Rock225と同じだ")
; x31 - see the color-swap patch in INIT above.
ROCK_COLOR_SWAPPED_PATCH:
    DS 31,06Bh

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

; per-slot fixed setup for CLOUD_POOL's rows (screen rows2-4, the
; 3rd-5th row from the top, all in the "fast" band) - row2 is the
; "3行目" special case (always 4-cell wide); rows3-4 randomly pick 2
; or 4 at each spawn.
; "3から5行目は最速の毎フレーム1セル移動 5から8行目は半速の2フレで
; 1セル" (5行目は最速側). rows5-8(top) (screen rows4-7, the half-speed
; band) were briefly dropped as a slowdown-diagnosis experiment
; ("5から8行目は削除してみてくれ") and restored once ruled out
; ("雲減らしても変わらんな"), then permanently cut ("雲は6から8行目は
; 削除していいわ" - screen rows5-7 this time, i.e. everything past the
; fast band) - only rows2-4 remain now.
CLOUD_ROW_TABLE:
    DB 2,3,4
; "んー早すぎかもな 3から8行目までどちらも更に半速で 3から5が2フレ
; ごと 6から8が4フレごとだな" - both bands halved again from the
; original 1/2, not just the slow one (now moot - the slow band itself
; is gone, see above). Then "4フレはガタが目立つんで 3フレで 中途半端
; だが仕方ない" - 4 read as choppy, dropped to 3 for that band (also
; moot now).
CLOUD_INTERVAL_TABLE:
    DB 2,2,2
CLOUD_FIXED4_TABLE:
    DB 1,0,0

; src/CYBER SHMUP.asm's own CLOUD_WA_CODE/CLOUD_WB_CODE pattern bytes,
; copied byte-for-byte ("Stage1でもやってる雲を").
CLOUD_A_PATTERN:
    DB 06h,6Fh,0FEh,1Bh,04h,00h,00h,00h
CLOUD_B_PATTERN:
    DB 00h,0D8h,0B4h,0EFh,0B0h,60h,00h,00h

; ===== generated tables (terrain + tank) appended below by build_test.py =====
