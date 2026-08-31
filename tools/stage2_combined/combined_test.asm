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
TICK          EQU EF00h
PXCHAR_T      EQU EF01h   ; word
ROWPHASE_T    EQU EF03h
TERRAIN_NEXTID EQU EF04h
TRR_PHASE_MINUS1 EQU EF05h  ; TERRAIN_RENDER_ROW's own scratch - ROWPHASE_T-1, precomputed once per call instead of every one of its 32 loop iterations (see TERRAIN_RENDER_ROW's own comment)
IDCACHE_T0    EQU EF10h
IDCACHE_T1    EQU EF40h
IDCACHE_T2    EQU EF70h
IDCACHE_T3    EQU EFA0h
NAMEBUF_T0    EQU F000h
NAMEBUF_T1    EQU F020h
NAMEBUF_T2    EQU F040h
NAMEBUF_T3    EQU F060h

; ---------- tank state (past terrain's own range - F000h-F080h) ----------
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
SPRITE_ATTRS  EQU F100h   ; 16 bytes

TANK_X        EQU F120h
TANK_Y_CUR    EQU F121h
TANK_DX       EQU F122h   ; 1=right, 0FFh=left, 0=none
TANK_AIMUP    EQU F123h   ; 1 while holding up (diagonal-aim pose)
JOY_DIR       EQU F124h
JOY_TRIGB     EQU F125h
PREV_TRIGB    EQU F126h
JUMP_ACTIVE   EQU F127h
JUMP_FRAME    EQU F128h
JUMP_Y_OFFSET EQU F129h
CUR_POSE_PAT  EQU F12Ah

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
; lower bound it could fly into row0 (the HUD/score row) and erase a
; glyph permanently instead of restoring it - "カラーバーAからF消え
; たぞ". Fixed by never letting a bullet's row go below this. Still
; applies now that U is a sprite (it's a position bound on the shared
; ROW/COL bookkeeping, not a BG-erase concern specifically). Was 2
; (guarding rows0-1, back when row1 still held calibration-strip
; content); row1 is ordinary sky now (see NIGHT_START_ROW's own
; comment on that same row) - "斜めショットのガードが今は上から2行に
; なってるが1行目だけに変更" - only row0 itself needs guarding.
BULLET_MIN_ROW    EQU 1
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

; Bullet BG pattern codes.
; round36-9 ("自機ショットらしきゴミ" reported next to a Rock225 descend
; edge): this used to sit at codes88/96 (groups11-12), "well past every
; real terrain code (0-87)" - but that terrain-code ceiling was never a
; hard guarantee, just whatever the CURRENT tier profile happened to
; need at the time this comment was written. Once the user's own edited
; terrain (Schedule2_7.json) grew terrain_gen.py's own MAX_CODE to 93
; (more distinct climb/descend transitions -> more distinct blend-pair
; code blocks - see terrain_gen.py's own PAIRS/PAIRBASE), it silently
; started overlapping codes88-93, and whichever of terrain's own pattern
; upload / this bullet pattern upload ran later in INIT clobbered the
; other's VRAM pattern-generator data at those shared codes - showing
; the bullet's own glyph, in the bullet's own color, inside terrain
; cells. Moved to codes224-247 (groups28-30) instead: verified free by
; grepping every EQU literal in that whole numeric range - nothing else
; in this file uses codes there (everything nearby that LOOKS like a
; pattern code is actually an unrelated 0-255 pixel X-coordinate
; constant, e.g. BIGZUM_MAX_X/ENEMY_SPAWNX/HORMING_SPAWN_X, easy to
; confuse with a code at a glance since both are small plain decimals -
; see this file's own git history for the exact audit). This also isn't
; adjacent to terrain's own budget at all any more, so normal further
; terrain edits (the whole point of schedule-editor.html's own terrain
; tool) can't silently collide with it again the way codes88-93 did.
;
; round36-11 ("水平打ちを3パターンに分けてローテーション"): F (straight,
; always BG) grew from 1 pose to 3 (BulletFU/FM/FL - see bullet_gen.py's
; own VARIANT_NAMES_F). Each of sky/rock/night now needs 3 codes per
; facing instead of 1: 3(variant)x2(facing)=6 codes per color, x3 colors
; =18 codes - all 24 free codes were about to run out (18 for F alone,
; +18 more if U's own BG-cell fallback below also rotated - 36 total
; against a 24-code budget, 12 short - confirmed with the user directly:
; "ショットパターンは今の6つと反転なので12パターンだろ" / "普段プレイも
; 動的書き換えで妥協" settled it). Fit found: F rotates fully (18 codes),
; U's own BG-cell fallback (used only while BOSS_ACT!=0 - a rare,
; secondary path, see its own comment below) stays a SINGLE
; non-rotating pose (6 codes) - 18+6=24, exactly the free budget, zero
; waste. Each color now spans a WHOLE 8-code group on its own (6 F-slots
; + 2 U-slots = 8, exactly one SCREEN1 color group) instead of F/U
; interleaved 2-and-2 sharing 3 groups the way the single-pose version
; did - group28=sky(224-231), group29=rock(232-239), group30=night
; (240-247, moved off its old dedicated group18 - see BULLET_NIGHT_
; COLORADDR below - freeing group18 back up entirely, unused for now).
BULLETF_SKY_CODE0  EQU 224   ; BulletFU (1st shot)
BULLETF_L_SKY_CODE0  EQU 225
BULLETF_SKY_CODE1  EQU 226   ; BulletFM (2nd shot)
BULLETF_L_SKY_CODE1  EQU 227
BULLETF_SKY_CODE2  EQU 228   ; BulletFL (3rd shot, then back to FU)
BULLETF_L_SKY_CODE2  EQU 229
BULLETU_SKY_CODE    EQU 230  ; single non-rotating BG-cell pose (BulletUM) - boss fight only, see below
BULLETU_L_SKY_CODE  EQU 231

BULLETF_ROCK_CODE0  EQU 232
BULLETF_L_ROCK_CODE0  EQU 233
BULLETF_ROCK_CODE1  EQU 234
BULLETF_L_ROCK_CODE1  EQU 235
BULLETF_ROCK_CODE2  EQU 236
BULLETF_L_ROCK_CODE2  EQU 237
BULLETU_ROCK_CODE    EQU 238
BULLETU_L_ROCK_CODE  EQU 239

; color table (VRAM 2000h+group, 1 byte/group, hi nibble=fg/lo=bg -
; see terrain_gen.py's own SKY_COLOR/ROCK_COLOR): group28 (codes
; 224-231) = fgE gray/bg5 light blue, matching the sky's own bg5;
; group29 (codes 232-239) = fgE gray/bg11 light yellow, matching the
; rock tier's own bg (terrain_gen.py's ROCK_COLOR=0x8B) - both groups
; patched over terrain_gen.py's generic per-group defaults (unused by
; any real terrain code) rather than by changing that shared module.
; ROCK_COLORBYTE's bg nibble must track ROCK_COLOR's own bg whenever
; that changes (was 01Ah/bg10 - missed when ROCK_COLOR moved to bg11,
; fixed alongside the row18/19 change below). fg was black(1), then
; gray(14/0xE) - "バレットUとFの変更 カラーもグレーに" - now light
; red(9) - "バレットカラーをライトレッドに変更".
BULLET_SKY_COLORADDR  EQU 201Ch
BULLET_ROCK_COLORADDR EQU 201Dh
BULLET_SKY_COLORBYTE  EQU 095h
BULLET_ROCK_COLORBYTE EQU 09Bh
; night-black variant of the sky glyph above - "スクロールしていない
; 行の弾の水平打ちの背景色がライトブルーのままになってる...ショット
; を夜に打った場合はショットの背景色をブラックに" - own dedicated
; group (round36-11: group30, 240-247 - moved off the old group18 to
; make room for F's own night rotation, see this section's own top
; comment) since BULLETF_SKY_CODE*'s own group28 can't be conditionally
; recolored per-row (SCREEN1 color is per 8-code group, not per screen
; position - same constraint bullet_gen.py's own comment on
; BULLETF_SKY_CODE/ROCK_CODE already explains). Same fg9(light red) as
; the day glyph, bg1(black) instead of bg5. Applies across the whole
; sky+SkySand band (rows0-16, same range DRAW_BULLET_CELL's own sky/
; rock split already covers) once CHECK_NIGHT's own sweep has darkened
; that specific row - "Skysandとその上の行でショットの背景色をブラッ
; クにすれば良い" (an earlier, narrower row0-14 cutoff excluding
; SkySand itself was wrong - corrected here). rows17-19 (Sand) and
; 20-23 (scrolling terrain) are unaffected either way - the ground
; itself never darkens.
BULLETF_NIGHT_CODE0  EQU 240
BULLETF_L_NIGHT_CODE0  EQU 241
BULLETF_NIGHT_CODE1  EQU 242
BULLETF_L_NIGHT_CODE1  EQU 243
BULLETF_NIGHT_CODE2  EQU 244
BULLETF_L_NIGHT_CODE2  EQU 245
BULLETU_NIGHT_CODE    EQU 246
BULLETU_L_NIGHT_CODE  EQU 247
BULLET_NIGHT_COLORADDR EQU 201Eh   ; group30 (240-247)
BULLET_NIGHT_COLORBYTE EQU 091h   ; fg9 light red / bg1 black

; U's own BG-cell codes, used only while BOSS_ACT!=0 - "自機ショットで
; 消えてしまう問題があるので ボス戦になったら斜めショットをBG描画に変更"
; (U's own hw sprite slots7-9 were reported disappearing during the boss
; fight - switches back to the same BG-cell approach F always used,
; DRAW_BULLET_CELL/ERASE_BULLET_CELL, instead of a hw sprite, for this
; specific window only; F itself is untouched). Placed in the SAME
; groups (28/29/30) F's own rotation claimed and colored, using the 2
; slots per group F's own 6-of-8 usage leaves free - no new SCREEN1
; color-table writes needed, just more pattern data loaded into
; already-colored slots. Does NOT rotate (round36-11, see this
; section's own top comment for the exact budget math) - always the
; single BulletUM pose (bullet_gen.py's own BOSS_BG_VARIANT), same
; pattern data for every boss-fight shot regardless of the normal-play
; rotation counter.

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
; round36-11 ("斜めもUU、UM、ULで切り替えてローテーション"): U grew from
; 1 pose to 3 (BulletUU/UM/UL) the same way F did, but unlike F's own BG
; codes (which had 24 free codes to grow into), the hw sprite pattern
; table has ZERO free slots anywhere in the entire 0-255 range - every
; single 4-slot (16x16) or wider block, from the tank at 0 through
; SBeam's own 252-255, is already claimed with no gaps (confirmed by
; auditing every generator file's own BASE_OFFSET/PAT_* constant, same
; kind of full-budget audit as the BG side - see this file's own git
; history). Carving out 4 more dedicated 4-slot blocks (3 variants x2
; facings, minus the 1 pair already here) isn't possible without a
; large renumbering across tank_gen.py/bigzum_gen.py/flyer_gen.py/etc,
; each independently tuned over many earlier rounds - confirmed with
; the user directly not worth the risk ("普段プレイも動的書き換えで妥
; 協(推奨)"). PAT_BULLETU/PAT_BULLETU_L themselves stay exactly where
; they always were (still just 1 pair, not 3) - what changes is that
; TRY_SPAWN_BULLET now rewrites their VRAM pattern-generator bytes on
; every new diagonal shot spawn (WRITE_BULLETU_SPRITE_VARIANT), instead
; of the pattern being loaded once at INIT and left alone. This gives
; the "3 pattern rotation" the user asked for, with one accepted visual
; compromise: if 2+ diagonal shots are on screen at once, they all show
; whichever variant was most recently written (the shared VRAM slot has
; no way to hold more than 1 bitmap at a time) - no other sprite's
; display is affected either way, this is purely a shot-vs-shot
; distinctness tradeoff.
PAT_BULLETU    EQU 140          ; right after PAT_EXPLOSION(136-139) - still just 1 pair, see above
PAT_BULLETU_L  EQU 144
BULLET_U_COLOR EQU 9            ; light red, same fg BulletF's BG version now uses - "バレットカラーをライトレッドに変更" (was gray/14)
BULLET_U_SPRITE_ATTRS EQU F1E0h   ; 12 bytes: Y,X,pat,col x3, staged same as ENEMY_SPRITE_ATTRS

JOY_TRIGA     EQU F12Bh
; "耐久値を持つ敵や自機がダメージを食らったら一瞬ホワイトに光るように" -
; the tank's only discrete "took damage" moment is BigZum's own punch
; connecting (UPDATE_TANK_BIGZUM_PUNCH) - Zum's own push is a smooth
; continuous shove with no single hit instant, so nothing sets this
; from there. Same FLASH_DURATION-driven countdown/FLASH_COLOR
; override as every other HP-bearing entity's own flash - see
; UPDATE_TANK_SPRITES.
TANK_FLASH_TIMER EQU F12Ch
; "自機のライフは6 ダメージで1減少...現在はBigZumのみだがいずれ敵弾
; 実装予定 今は0になっても死なない" - real tank-HP now exists (the gap
; the comment above used to note is closed); same discrete-damage
; moment as TANK_FLASH_TIMER (BigZum's punch connecting), decremented
; alongside it in UPDATE_TANK_BIGZUM_PUNCH, floored at 0 with no
; death/game-over handling yet - future enemy-bullet damage sources
; will feed the same counter once they exist. See LIFE_DISPLAY.
TANK_LIFE EQU F12Dh
; "ライフ初期値を10に" (was 6).
TANK_LIFE_INIT EQU 10
; "サンダーやサンダービームで連続ダメージを受けてしまうんで自機に当た
; ったら30フレ当たり判定を停止" - FLASH_DURATION(6, the shared visual-
; flash length every entity's own hit-flash uses) was too short to
; actually prevent repeat hits from an environmental hazard the tank can
; just stand inside for many consecutive frames - a dedicated, longer
; invulnerability window for Thunder/SBeam specifically (not the shared
; flash timer, which stays FLASH_DURATION as before for every other hit
; source - Homing/BigZum don't have this problem: Homing consumes itself
; on hit, BigZum's punch already has its own real per-instance cooldown).
TANK_HAZARD_IFRAMES EQU F13Ah
TANK_HAZARD_IFRAME_DURATION EQU 30
; ---------- dash ("上下左右入力の下を入れたままジャンプのBボタンを押
; すと今向いてる方向に倍速で64px移動") ----------
; holding DOWN (JOY_DIR==5 - INFERRED as pure down only, not a down-
; diagonal, since the instruction just says "下") and pressing jump (B,
; same JOY_TRIGB/PREV_TRIGB edge-detected press UPDATE_JUMP itself uses)
; fires a fixed 64px dash in the tank's own current TANK_FACING
; direction, at DASH_SPEED(3px/frame - "倍速", literally double
; TANK_SPEED_LO's own 1.5px/frame average) instead of a jump.
; UPDATE_DASH runs BEFORE UPDATE_JUMP (see MAINLOOP) so a dash-starting
; press can't ALSO start a jump the same frame (UPDATE_JUMP's own first
; action is bailing out while DASH_ACTIVE) - mutually exclusive, not
; simultaneous. UPDATE_TANK_XY also bails out while DASH_ACTIVE, so
; ordinary joystick movement/facing input is fully suppressed for the
; dash's own duration - "今向いてる方向に" only makes sense read as a
; FROZEN direction, not one that could change mid-dash.
DASH_ACTIVE     EQU F12Eh   ; 0=not dashing, 1=dashing
DASH_DIR        EQU F12Fh   ; frozen TANK_FACING at dash-start (0=right,1=left)
DASH_REMAINING  EQU F130h   ; px still left to travel this dash
DASH_DIST EQU 64            ; "64px移動"
DASH_SPEED EQU 3            ; px/frame, flat (double TANK_SPEED_LO's own 1.5px/frame average)
; "自機スプライトの上部32x16のスプライトを下に5px下げる" - the tank's
; own TL/TR quadrants (the top half of its 32x32 hw-sprite body - see
; UPDATE_TANK_SPRITES) are pushed down 5px while dashing; BL/BR are left
; alone, so the top visibly slides toward the bottom instead of the
; whole body just moving down.
DASH_SPRITE_Y_SHIFT EQU 5
TANK_TOP_DRAW_Y EQU F131h   ; UPDATE_TANK_SPRITES scratch: TANK_DRAW_Y, +DASH_SPRITE_Y_SHIFT while dashing - TL/TR only, BL/BR stay at TANK_DRAW_Y+16 unshifted
; frames left before another shot can fire while A is held ("間欠連射
; ...1発打ったら1発空ける" - hold-to-auto-fire, but rate-limited
; rather than one every single frame) - see UPDATE_SHOT. Tunable;
; picked with no more precise spec than "leave a gap" ("ダメなら修正
; する" - happy to retune if this cadence isn't right).
SHOT_COOLDOWN EQU F14Eh
SHOT_COOLDOWN_FRAMES EQU 8
; 3 shot slots, 7 bytes each: +0 ACT, +1 TYPE(0=F straight,1=U
; diagonal), +2 COL, +3 ROW, +4 ADDR_LO, +5 ADDR_HI (name-table row
; base address, from BULLET_ROWADDR_LO/HI), +6 FACING(0=right,1=left,
; copied from TANK_FACING at spawn) - same pool-of-3 design as
; BULLET0/1/2 in src/CYBER SHMUP.asm ("Stage1と同様に制限数画面内3発").
BULLET0_ACT   EQU F150h
BULLET1_ACT   EQU F157h
BULLET2_ACT   EQU F15Eh
BULLET_TEMP_BYTE EQU F165h

; ---------- terrain collision: ground-height following + slope       ----------
; ---------- (Rock225) detection - see UPDATE_TERRAIN_COLLISION below. ----------
; probe column offset from TANK_X - was 24 (near the tank's very front
; edge, made the tank snap to a new tier before the marker had
; scrolled under its own visual body - reported as floating), then 16
; (1 cell back). Still switching too early, so pulled back another 4px
; per direct instruction ("もっとGapスプライト切り替えを遅らせるべき
; あと4Px遅れるようにしてくれ").
TANK_FOOT_DX  EQU 12
TANK_GROUND_Y EQU F140h    ; current ground-follow baseline Y (tier-dependent) - UPDATE_JUMP
                            ; subtracts JUMP_Y_OFFSET from this instead of the fixed TANK_Y_BASE
TANK_ON_SLOPE EQU F141h    ; 1 while straddling a Rock225/Rock225D marker -> Gap pose
TANK_TIER     EQU F142h    ; 0-3, current ground tier (screen row 23-TANK_TIER) under the tank
TANK_ROWPTR   EQU F143h    ; word: IDCACHE_Tn base address for the surface tier's row
TANK_COL_R    EQU F145h    ; probe column (name-table column, 0-31)
TANK_SLOPE_HOLD EQU F147h  ; frames left before TANK_ON_SLOPE actually drops to 0 - see UPDATE_TERRAIN_COLLISION
TANK_DRAW_Y   EQU F148h    ; TANK_Y_CUR, -TANK_GAP_ART_OFFSET while a Gap pose is showing - see UPDATE_TANK_SPRITES
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
TANK_FACING   EQU F149h    ; 0=right, 1=left
UTS_COLOR_0   EQU F14Ah    ; UPDATE_TANK_SPRITES scratch: per-slot color, swapped when facing left
UTS_COLOR_1   EQU F14Bh
UTS_COLOR_2   EQU F14Ch
UTS_COLOR_3   EQU F14Dh

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
GAME_TICK     EQU F166h   ; 2 bytes
SCORE         EQU F168h   ; 3 bytes: low word at +0, high byte at +2 (real score = SCORE*100)
SCORE_DIGITS  EQU F16Bh   ; 6 bytes
HUD_ROW       EQU F171h   ; WRITE_HUD_CELL scratch
HUD_COL       EQU F172h
HUD_VAL       EQU F173h
HUD_TEMP_BYTE EQU F174h
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
SND_TIMER     EQU F175h
SND_DECAY     EQU F176h
; last-drawn hundreds/tens/ones digit for GAME_TICK_DISPLAY - unlike
; src/CYBER SHMUP.asm (which can afford an unconditional redraw every
; frame), this ROM has no vsync/HALT frame sync at all, so every extra
; per-frame VRAM write directly slows the whole game's real-time pace
; down (more T-states/iteration = fewer iterations/second = everything
; TICK-paced runs slower) - redrawing 3 cells every single frame when
; usually only the ones digit actually changed was real, avoidable
; cost. Init to 0FFh (never a real digit) so the very first call still
; draws all 3 - see GAME_TICK_DISPLAY.
GTD_LAST_H    EQU F177h
GTD_LAST_T    EQU F178h
GTD_LAST_O    EQU F179h
; "爆発音はショット音で消えるとまずいんで爆発音は鳴り終わるまで継続
; しショット音で消えないように" - the shared-channel-A design lets any
; sound cut off whatever's currently playing, but an explosion in
; particular shouldn't lose to a shot fired right after a kill. Set by
; SOUND_DESTROY, checked (and left alone) by SOUND_SHOT's own early-
; exit, cleared by SOUND_UPDATE the instant the explosion's own
; SND_TIMER actually reaches 0, and cleared by SOUND_ZUM_DEFLECT too
; (that one's still allowed to cut an explosion off, same as always -
; only the shot sound is singled out here).
SND_EXPLODING EQU F17Ah
; round32: "円の爆発はノイズでどーーーーんって長いやつ" - the boss's own
; circle-explosion boom needs a MUCH longer envelope than the shared
; SND_TIMER/SND_DECAY mechanism above can express on its own (SND_TIMER
; doubles as the volume, 0-15, so a plain "decay by SND_DECAY every
; frame" caps out at 15 frames total - nowhere near "long"). Reuses
; SND_TIMER/SND_DECAY anyway rather than a fully separate envelope
; (SOUND_UPDATE's own SU_BOOM branch, selected by SND_DECAY==0 - no
; ordinary sound ever sets that, see SOUND_UPDATE's own comment) - this
; one extra byte just counts frames between volume steps, stretching a
; still-15-step decay out over many more real frames. The only genuinely
; free gap left below STACKTOP (see STACK_SAFETY_MARGIN's own comment -
; every other candidate spot is either actively used throughout the
; whole boss fight or would need pushing the topmost variable even
; closer to the required 0x60 headroom, which is already at its exact
; limit) - F17Bh-F17Fh, right after this byte, before ENEMY_POOL(F180h).
SND_BOOM_DECAY_CTR EQU F17Bh
; round32 follow-up: "ではノイズ使ってる全てのSEをデューティ比の音量
; 操作を適用してみて" - the 1:1 on/off duty-cycle gating originally built
; just for the boom (see SOUND_CALC_NOISE_GATE_VOLUME below) is now
; shared by every noise-channel sound in this file (SHOT/DESTROY/SPARK_
; CRACKLE/BOSS_BOOM). SOUND_ZUM_DEFLECT is the one sound here that's
; TONE, not noise ("キンキン" - a held ping reads wrong if gated on/off)
; - this flag is how SOUND_UPDATE tells which behavior the CURRENTLY
; playing sound wants: each trigger routine sets it (1=noise/gated,
; 0=tone/ungated) alongside its own peak/decay. Next byte in the same
; free gap as SND_BOOM_DECAY_CTR above.
SND_NOISE EQU F17Ch
; digit0 code; digitN = DIGIT_BASE+N for N=0-9 (score/counter, glyphs
; copied byte-for-byte from src/CYBER SHMUP.asm's own DIGIT_PATTERNS -
; "スコアの数字流用") - the old N=10-15=A-F hex-label glyphs (added for
; the now-removed calibration strip, see LIFE_CODE's own comment) are
; still loaded (harmless, unused) rather than ripping out DIGIT_
; PATTERNS_LOCAL's own shared table.
DIGIT_BASE       EQU 104
HUD_DIGIT_COLORBYTE EQU 0F1h   ; fg15 white/bg1 black - same as Stage1's own digit groups ("背景色はブラックで")
SCORE_PER_KILL   EQU 1         ; ADD_SCORE units of 100 real points - "当たったら100点"
; "次にカラーバーやその下の数値は削除 変わりに画面最上部にライフバーを
; 追加...スコアから１セル空けた位置" - the old calibration strip
; (SWATCH_CODES/HEXLABEL_CODES, groups15-30) is gone; group15's own
; single code is reused as a plain blank-black filler for the whole
; top HUD row ("最上部の行はブラックで初期化"), group16's own single
; code holds the new life-bar tile (sprites/Life_8x8.json, fg3/bg5 -
; own dedicated color group, distinct from the row-blank filler).
HUD_ROW_BLANK_CODE  EQU 120       ; group15 (120-127)
HUD_ROW_BLANK_COLOR EQU 011h      ; fg1/bg1 - irrelevant fg, blank pattern
LIFE_CODE           EQU 128       ; group16 (128-135)
; "ライフ表示の背景色をブラックに" - bg nibble 5(purple, Life_8x8.json's
; own uploaded bg) -> 1(black), same bg1 convention HUD_ROW_BLANK_COLOR
; above already uses; fg3 (the bar's own fill color) unchanged.
LIFE_COLOR          EQU 031h
LIFE_BAR_ROW        EQU 0
LIFE_BAR_COL0       EQU 9         ; 1 blank cell past the score's own 8 (cols0-7) - "スコアから１セル空けた位置"
; matches TANK_LIFE_INIT(10) - was a hardcoded 6-cell bar, now sized to
; the real life total (cols9-18, still well clear of GAME_TICK_DISPLAY's
; own cols29-31).
LIFE_BAR_CELL_COUNT EQU TANK_LIFE_INIT
; "夜になっていく演出" - once GAME_TICK reaches NIGHT_START_TICK(850),
; every NIGHT_INTERVAL(8) further GAME_TICKs, one more sky row (top
; down, NIGHT_START_ROW(1, "スコアの下の行から" - the row right below
; the score/life-bar row0, off-by-one vs an earlier "2行目"=row-index-2
; misreading, fixed once shown a real screenshot of it starting 1 row
; too late) through NIGHT_END_ROW(16, the SkySand row - "下から8行目" -
; see SKYSAND_CODE's own comment, same row either way this is counted)
; darkens:
; the new leading row gets NIGHT_CODE's own striped tile (a fresh copy
; of SKYSAND_PATTERN's own bits - the same "横縞" (horizontal-stripe)
; look, recolored fg5(light blue)/bg1(black) instead of SkySand's own
; fg5/bg11 - own dedicated group17, distinct from SKYSAND_CODE's own
; group31 so recoloring one never touches the other), and the row that
; was the leading edge last time solidifies to HUD_ROW_BLANK_CODE
; (already black-on-black, reused as-is - no new code needed for the
; "done" rows). Stops once NIGHT_END_ROW itself becomes the leading
; row - the SkySand row is never itself blackened over, since nothing
; requested darkening the ground/terrain, only the sky above it.
NIGHT_START_TICK EQU 850
NIGHT_INTERVAL   EQU 8
NIGHT_START_ROW  EQU 1
NIGHT_END_ROW    EQU 16
NIGHT_CODE       EQU 136       ; group17 (136-143)
; 実機フィードバック対応(round36-14 follow-up#12その3、"じゃあホワイト
; で ライトブルーにホワイトは使えるんだな"): group17 is also FlyerLaser's
; own home now (see FLYER_LASER_PATTERN_CODE's own comment) - bg5(light
; blue) matching a real laser's own fg15(white) is a combination that
; DOES already exist elsewhere (group0, CLOUD_GROUP0_COLOR) but group0
; itself has zero free codes (terrain's own dynamic 0-93 range owns all
; of it), so the only way to actually deliver white-on-blue is to
; repaint group17's own shared color to match it - fg1->fg15, bg5
; unchanged. This DOES recolor NIGHT_CODE itself (this constant's own
; previous value, 015h, was itself a direct earlier user correction -
; "ブラックとブルーの文字色と背景色を逆に" - so night now reads white-
; on-blue instead of black-on-blue) and MINE1_CODE/MINE2_CODE (Mine's
; own black parts also become white) - both flagged directly to the
; user alongside a render, same "found a real conflict, made the call,
; showed the result" precedent as every other VRAM-reuse decision this
; session.
NIGHT_COLOR      EQU 0F5h      ; fg15 white / bg5 light blue (was fg1/bg5, see comment above)
; endgame GAME_TICK timeline: night sweep starts at NIGHT_START_TICK
; (850) above; the boss spawns once at BOSS_SPAWN_TICK - see its own
; comment further down. round34 ("ランダムスポーンは廃止 全てスケジュ
; ールに"): ordinary enemies (ZacoII/Zum/BigZum/Flyer/Etank) no longer
; have a shared "stop spawning at tick X" gate at all - each one only
; ever spawns when its own schedule entry fires (SPAWN2_THRESHOLDS),
; and the schedule itself simply has no entries left after its own last
; one, so there's nothing left to gate. The one surviving GAME_TICK
; threshold from that old shared mechanism is BigZum's own forced-
; retreat-before-boss safety net (below), renamed from ENEMY_SPAWN_
; STOP_TICK to reflect its real, narrower remaining purpose - BigZum is
; the only enemy that shares hw sprite slots/pattern VRAM with the boss
; (see BOSS_SPR_BASE_SLOT/PAT_SASAPI's own comments), so it alone still
; needs to be forced off-screen ahead of the boss's own spawn,
; independent of when it happened to spawn.
BIGZUM_RETREAT_TICK EQU 950
; round35 (real-hardware feedback: "Bigzumは4回以上スケジュールしてる
; が1回しか出てない...恐らくEtankでスキップされてるな...排他制御はあく
; まで仮実装の仕様 これはエディットでコントロールするんで要らない"):
; direct investigation found NO Etank exclusion anywhere in the current
; code (ALLOC_BIGZUM_SLOT/ALLOC_ETANK_SLOT don't check each other's
; pool - see ALLOC_BIGZUM_SLOT's own comment; that check was genuinely
; removed back in round34-2). The real cause, confirmed by direct
; emulator instrumentation of a full worst-case playthrough: BIGZUM_
; RETREAT_TICK used to be the ONLY thing that could ever clear a live
; BigZum out of its own single slot (BIGZUM_SLOT_COUNT=1, "BigZumは１
; 体のみ") - nothing in its own approach/pause/jump/punch state machine
; naturally despawns it. So the FIRST BigZum to successfully spawn
; occupied the only slot continuously for the rest of the game (up to
; ~460 ticks in that playthrough), silently dropping every later
; schedule entry as "pool full" regardless of terrain or anything else
; - not a hardcoded exclusion against another enemy type, just this one
; enemy blocking its own later spawns. Fixed by making the retreat
; PER-INSTANCE (see BIGZUM_SLOT_SIZE's own +13/+14 field, computed once
; at spawn in ALLOC_BIGZUM_SLOT) instead of one shared global tick, so
; each BigZum clears out on its own after a bounded engagement window
; and later schedule entries get a real chance - this constant now
; serves only as the hard ceiling every instance's own retreat is
; clamped to, guaranteeing the pre-boss safety net (boss_vram_safety_
; test.py) still holds regardless of engagement duration.
; untuned first guess, easy to retune - "スケジュール自体の実プレイでの
; 難易度・ペーシング調整" is still an explicitly deferred/pending task
; (see CLAUDE.md), this just makes the engagement window PER-INSTANCE
; and finite instead of "forever until 950", the actual bug being fixed
; here.
BIGZUM_ENGAGEMENT_DURATION EQU 100
; ---------- boss (Sasapi): spawns once at BOSS_SPAWN_TICK, then ----------
; patrols left<->right forever - "Tick999でスポーン Skysandの８ｐｘ上
; あたり 右から出現し左へ 左端に着いたら反転 右端に 以降繰り返し 耐久
; 値は255で 速度は2". No collision/HP-depletion wired yet - BOSS_HP is
; just stored, no spec given yet for what damages it or what happens at
; 0; no despawn either, matching "反転...以降繰り返し" describing an
; unending patrol, not a one-shot pass. round34: this used to be its own
; independent EQU(999), checked directly inside UPDATE_BOSS_ALL every
; frame; now it's just documentation matching the schedule's own final
; SPAWN2_THRESHOLDS entry (995, "全てスケジュールに") - the actual
; runtime trigger is SSC2_FIRE's own unconditional fallthrough to
; S2_BOSS_SPAWN once every earlier entry has fired, same convention as
; Stage1's own SSC_FIRE/BOSS_SPAWN (src/CYBER SHMUP.asm).
BOSS_SPAWN_TICK EQU 995
BOSS_SPAWNX     EQU 192     ; 256-64: off/at the right edge, sprite fully inside the screen the instant it spawns - same "screen_width - sprite_width" shape as ENEMY_SPAWNX(240=256-16), just for a 64px-wide sprite instead of 16px
; "Skysandの８ｐｘ上あたり" - read as the sprite's own BOTTOM edge
; sitting 8px above SkySand's top row (NIGHT_END_ROW=16, pixel row
; 16*8=128): bottom at 128-8=120, so this (top-left) Y = 120-64=56.
; Revisit from a screenshot if that's not the intended anchor - same
; "correct from what's actually shown" precedent as NIGHT_START_ROW's
; own history.
BOSS_SPAWN_Y    EQU 56
BOSS_SPEED      EQU 2       ; px/frame, flat (not the tank's 1.5px alternating trick) - "速度は2", same units/convention as FLYER_SPEED's own "速度は2"
; "右初期位置から左に移動する際に左斜下8px移動してから水平移動に変更
; 戻る時は逆に到達8px前から右斜め上に移動して初期位置に" (round11) - the
; boss now dips 8px down at the START of the leftward leg (diagonal,
; both axes at BOSS_SPEED/frame - 8 divides evenly by BOSS_SPEED(2), no
; partial-step remainder to handle) before going purely horizontal, and
; symmetrically rises back up over the FINAL 8px of the rightward leg,
; landing exactly back at BOSS_SPAWN_Y right as it re-enters the pose.
BOSS_DIP_DIST EQU 8
; ---------- SBeam ("サンダービーム", a real hw sprite this time -
; unlike Thunder's own BG bolt) ----------
; "ホーミングとサンダー2セット終わったら 添付キャラをスプライトで描画
; ボスポーズで手の先からまず真下にライン上に並べる で地上に到達したら
; 左へラインのまま移動 左端まで行ったら元の位置まで同じラインで描画
; 長さは伸びていくがその分スプライトを足していく ラインが途切れない
; ように 薙ぎ払いビームって感じで で、点滅で表示で 取り敢えず1フレ
; 点滅で". "2セット" (2 completed pose cycles) - INFERRED as
; BOSS_POSE_COUNT>=2 at pose-ENTRY time (see UBA_MOVE_RIGHT), i.e. SBeam
; starts firing from the 3rd pose onward.
; Round-2 correction (verbatim): "誰がボスの直下でしかも1回だけ設置な
; んて指示したよ おまえほんの一瞬たった8pxしか描画されないのに見える
; かよ どこが薙ぎ払いビームなんだ まず発射起点はボスに被らない左がわ
; 伸ばした腕の先から 真下にラインをスプライトで引き 発射基点は変えず
; 左端まで移動しながらスプライトでラインを引いて元まで戻る 当然サン
; ダービーム中はホーミングもサンダーも撃たねえんだよ" - 3 real fixes:
; (1) the origin was wrong (see SBEAM_START_COL/_Y below); (2) the
; vertical drop must stay connected to the growing sweep, not vanish the
; instant the sweep begins (round2's own L-shaped-line fix, superseded
; by round3 below); (3) SBeam and Homing are now mutually exclusive per
; pose (see UBA_MOVE_RIGHT) - Thunder already can't newly trigger during
; a pose (its own trigger checks only run mid-patrol), so no separate
; change was needed there; any Thunder bolt already mid-flight when the
; pose begins is left to finish its own existing shrink animation rather
; than force-erased (force-clearing the pool would leave orphaned BG
; cells behind with no slot left to erase them - a worse bug than a few
; overlapping frames).
; Round-3 correction (verbatim, with a hand-drawn diagram - a fan of
; lines all meeting at the boss's own hand, fanning out to different
; points along the ground toward the tank): "取り敢えずは動いたな しか
; し真下だけじゃなくそのまま左へスプライトのラインを描きながら左に先
; 端を移動するんだよ で、左まで行ったら折り返して最初の真下を描いて
; 終了 意味わからんか? 絵を描いたからこんな感じだ 青の線な 複数本じ
; ゃなく1本だぞ" - round2's own L-shape (a RIGID vertical arm plus a
; SEPARATE horizontal arm meeting at a 90-degree corner) was still
; wrong: "複数本じゃなく1本" (one line, not several) plus the diagram's
; own fan-of-diagonals (each one a straight shot from the SAME point
; near the hand out to a DIFFERENT point along the ground) means this
; is ONE straight line from the FIXED origin to a MOVING tip, not two
; fixed-shape arms glued at a corner. The tip's own path is unchanged
; from round1 (down to the ground, then left along it, then back), but
; the LINE ITSELF is now the real straight (Bresenham) segment from the
; origin to wherever the tip currently is - purely vertical while the
; tip is still descending (dx=0 degenerates cleanly to the old vertical
; rendering), then increasingly diagonal as the tip sweeps left (the
; UPPER portion of the line changes angle too, not just staying rigidly
; vertical above a fixed corner) - see STAGE_SBEAM's own line-drawing
; algorithm below.
SBEAM_POSE_GATE EQU 2
SBEAM_TRIP_COUNT EQU 2   ; "サンダービームは2往復に" - 2 full sweep+retract round trips per pose
; free hw sprite pattern code - group27/THUNDERS_CODE's own block is BG,
; not hw-sprite, so codes 252-255 (the last free block after PAT_FLYER's
; own 220-251) are still entirely untouched.
SBEAM_CODE EQU 252
; fg7(cyan), matching the uploaded JSON's own header.
SBEAM_COLOR EQU 7
; "伸ばした腕の先から...発射起点はボスに被らない左がわ" - re-examined
; SasapiHand_64x64.json's own bitmap directly (not just its lowest row,
; which was the round-1 mistake - that picked up the legs, not the
; reaching arm): the reaching hand/fingers are the ONLY feature that
; touches local column0 (the sprite box's own left edge), at local rows
; 23-26 and 33-34 (of 64) - clearly a separate reaching-arm shape, not
; the body. That puts the arm's own tip right at the pose box's left
; edge (BOSS_SPAWNX, column24) - still technically ON the boss's own
; box boundary, so the origin is placed 1 full column further left
; (column23) to genuinely clear the boss's own silhouette, matching
; "ボスに被らない". Y snapped to the nearest 8px row inside the hand's
; own local y23-26 cluster (local y24 -> BOSS_SPAWN_Y+24).
SBEAM_START_COL EQU 23
SBEAM_START_Y EQU BOSS_SPAWN_Y+24
SBEAM_START_ROW EQU SBEAM_START_Y/8   ; origin in 8px-row grid units, for STAGE_SBEAM's own line algorithm
; hw sprite slots: BOSS_SPR_BASE_SLOT(10)..+15 (the boss's own dormant
; pose-time body, see below) PLUS slots26-31, the only 6 hw sprite slots
; in the whole file that are NEVER claimed by ANY entity at all (tank0-3,
; ZacoII/Homing4-9, boss/Zum/BigZum/Flyer/Etank all top out at 25) -
; contiguous with the boss's own block, so 10-31 is one 22-slot run.
; Reusing the boss's own slots is safe ONLY while the pose is active
; (BOSS_PHASE=1), the exact same window HIDE_BOSS_SPRITES already
; guarantees the boss's own 16 quadrant sprites are parked off-screen
; and untouched until the pose ends - same "reuse a dormant owner's
; slots" idiom as HORMING's own reuse of ZacoII/BulletU. UBAP_END
; forcibly clears SBEAM_ACT so a still-mid-animation beam can never
; collide with the boss's own sprite resuming there once the pose
; actually ends. The extra 26-31 slots need no such care - nothing else
; ever touches them, pose or not.
; 22 slots is a real, honest hw-sprite-budget cap on the line's own
; maximum length (a straight line from the origin to the far left edge
; can need up to ~24 8px cells) - "スプライトを足していく" holds up to
; this limit, not literally without bound (MSX1 has only 32 hw sprite
; slots total). Flagged for the user, not silently reinterpreted.
SBEAM_SLOT_COUNT EQU 22
SBEAM_SPR_BASE_SLOT EQU BOSS_SPR_BASE_SLOT
BOSS_HP_INIT    EQU 255     ; "耐久値は255で"
BOSS_COLOR      EQU 9       ; from sprites/Sasapi.json's own fg (light red)
; "ボスにコリジョン 見た目通り" - the boss's own real 64x64 visible
; footprint, full AABB against BOSS_X/BOSS_SPAWN_Y (see CHECK_HIT_PAIR_
; BOSS) - not a smaller hitbox.
BOSS_COLLISION_SIZE EQU 64
; round36-14 follow-up #3: the broken form's own real 32x32 footprint -
; see CHECK_HIT_PAIR_BOSS's own comment for how this gets picked at
; runtime.
BOSS_BROKEN_COLLISION_SIZE EQU 32

; round36-14 Part C ("ボス耐久値が50になったらスパーク爆発しSasapiBroken
; に変化して インフィニティ起動で回って ランダムタイミングで停止し 少し
; てまた回る これがシーケンスで で、0で最後の爆発で" - corrected mid-
; round from an initial "200" misreading; HP is 255-based, threshold is
; genuinely 50, not 200) - BOSS_FORM is orthogonal to BOSS_ACT/
; BOSS_PHASE: 0=normal(old 64x64 body, existing UBA_ACTIVE patrol/pose/
; attacks), 1=SPARK-only transition burst (reuses UPDATE_BOSS_
; EXPLOSION's own SPARK sub-state machine - see BOSS_EXPL_REASON),
; 2=broken form active (new 32x32 body, repeating figure-8-drift/random-
; stop/resume cycle - see UPDATE_BOSS_BROKEN_ACTIVE). Once BOSS_FORM!=0,
; UPDATE_BOSS_ALL never calls UBA_ACTIVE again (see its own dispatch) -
; this alone is what permanently stops Horming/Thunder/SBeam from ever
; arming a NEW attack again (every arm site - ARM_HORMING_VOLLEY/
; FIRE_SBEAM/CHECK_THUNDER_TRIGGER_LEFT/_RIGHT - only exists inside the
; UBA_ACTIVE tree), confirmed by direct code-path tracing rather than a
; new guard added inside each of those routines. Already-launched
; missiles/bolts/beam keep animating to their own natural end regardless
; (UPDATE_HORMING_ALL/UPDATE_HORMING_BG_ALL/UPDATE_THUNDER/UPDATE_SBEAM
; are called unconditionally from MAINLOOP whenever BOSS_ACT!=0, entirely
; independent of BOSS_FORM/UBA_ACTIVE) - "既に発射済みの弾は飛び続ける
; が、新規発射だけ止める", per direct confirmation this round. HP
; reaching 0 (whether in the normal or the broken form) is unaffected by
; any of this - CHECK_HIT_PAIR_BOSS's own JR Z,CHPBOSS_DESTROY runs
; exactly as before regardless of BOSS_FORM ("0で最後の爆発で" - the
; user's own words confirm this is the intended "final" explosion, not
; an unwanted side effect) - see INIT_BOSS_EXPLOSION's own BOSS_FORM
; check for the one adjustment a broken-form death still needs (the
; smaller body's own center offset).
BOSS_BROKEN_HP_THRESHOLD EQU 50
BOSS_FORM_SPARK  EQU 1
BOSS_FORM_ACTIVE EQU 2
; the broken body only needs 4 quadrants (2x2, 32x32) vs the old body's
; 16 (4x4, 64x64) - reuses the SAME 4 leading hw sprite slots the old
; body's own first row already occupied (BOSS_SPR_BASE_SLOT..+3, i.e.
; 10-13); HIDE_BOSS_SPRITES (called once on reveal) permanently parks
; the other 12 old-body slots (14-25) off-screen, and they're never
; touched again once BOSS_FORM=2 - see REVEAL_BOSS_BROKEN_FORM.
BOSS_BROKEN_SPR_BASE_SLOT EQU BOSS_SPR_BASE_SLOT
BOSS_BROKEN_QUAD_COUNT    EQU 4
; "インフィニティ起動で回って...これがシーケンスで" - a REPEATING
; moving<->stopped cycle (not a one-shot move-then-freeze-forever).
; round36-14 follow-up #4 ("SasapiBrokenの停止はインフィニティ軌道の1周
; に１回何処かで停止") replaced the original GAME_TICK-random-duration
; timing with a step-counted one tied to actual loop distance traveled -
; see BOSS_BROKEN_STEPS_TO_STOP's own comment. BOSS_BROKEN_LAP_STEPS_MIN/
; _RANGE is the window (in path-index steps) re-rolled every time
; movement resumes; RANGE is a power of 2 so the asm side can fold it
; with a plain AND, no reject-and-subtract needed. Centered on
; BOSS_BROKEN_PATH_LEN(64) so it averages out to "about 1 lap" per stop,
; matching "1周に１回" without being mechanically exact every single lap
; (見た目のランダム性を保つため、厳密に64固定にはしていない).
; Untuned initial placeholder values, like BIGZUM_ENGAGEMENT_DURATION's
; own comment - real pacing/difficulty tuning deferred.
BOSS_BROKEN_LAP_STEPS_MIN   EQU 48
BOSS_BROKEN_LAP_STEPS_RANGE EQU 32   ; power of 2 - AND 1Fh
; how many raw frames the figure-8 path LUT holds each of its
; BOSS_BROKEN_PATH_LEN(64) points for while MOVING - untuned placeholder,
; same as the tick windows above.
BOSS_BROKEN_PATH_HOLD_FRAMES EQU 4

; round36-14 follow-up #4 ("で、停止中にビーム攻撃をする 添付がその
; キャラデータ 1から4までの左方向斜め下に順の角度でビーム発射 角度は
; 絵から判断") - 4 fixed-angle diagonal beams, fired one at a time in
; sequence 1->4 (originally "each replaces the previous", but see the
; 3rd real-hardware feedback below - each now flies independently once
; launched, so up to all 4 can be in flight at once).
; real-hardware feedback round 1 ("全然絵が違うな...で、繋げる必要は
; ない 取り敢えず16x16で4本扇状に今の感じでいい"): the 1st attempt drew
; each beam as a Bresenham line, repeating the 16x16 pattern as a
; tileable unit toward the screen edge (STAGE_SBEAM's own idiom) - but
; the attached art is a single COMPLETE picture of one whole beam, so
; tiling it produced a garbled blob. Redesigned to a single hw sprite
; per beam using the already-loaded pattern, no repetition.
; real-hardware feedback round 2 ("ビームが飛んで来ないな...今はボスの
; 上に表示されてるだけ それで何の攻撃になる 発射して飛ばすんだよ"):
; the 2nd attempt over-corrected "繋げる必要はない" into "doesn't need
; to move at all" and just parked one static sprite next to the body -
; but the beam is still supposed to be a real projectile that travels
; ("画面端まで伸びる" - confirmed earlier as a genuine, damaging attack,
; not a decoration). Fixed by giving each fired beam real per-frame
; velocity (BOSS_BROKEN_PROJ_DX/DY) so it actually flies off toward the
; screen edge - see LAUNCH_BOSS_BROKEN_BEAM/UPDATE_BOSS_BROKEN_BEAM_
; FLIGHT. 4 hw sprite slots now (1 per simultaneously-in-flight beam),
; right after the broken body's own 10-13 - genuinely free at this
; point in the fight (old body/Homing/Thunder/old SBeam are all retired
; the instant BOSS_FORM leaves 0).
; Angles read directly off the attached SBeam1-4_16x16.json pixel data
; (centerline endpoint-to-endpoint, exact integer ratios - baked into
; each beam's own art AND now doubling as its own per-frame velocity
; ratio): beam1 dx:dy=-2:1 (shallow, down-left), beam2 -2:5 (steep,
; down-left), beam3 2:5 (steep, down-right), beam4 2:1 (shallow,
; down-right) - a symmetric fan skipping straight-down. The shallow
; pair (beam1/4) therefore drifts noticeably slower (~2.2px/frame) than
; the steep pair (beam2/3, ~5.4px/frame) - an untuned side effect of
; reusing the art's own ratio directly as px/frame rather than
; normalizing all 4 to one speed; left as-is pending real-play feedback.
BOSS_BROKEN_BEAM_SLOT_COUNT    EQU 4
BOSS_BROKEN_BEAM_SPR_BASE_SLOT EQU 14
; a hw sprite's own color attribute byte is NOT the BG-style packed
; fg/bg nibble pair (unlike the BG pattern color table) - it's a plain
; color index in bits0-3, with bit6 as the EC (early clock, -32px X
; shift) flag. The first attempt wrongly copied the BG fg/bg convention
; (071h = EC-shifted + color1/black), which explains BOTH real-hardware
; complaints at once: the wrong (black, not cyan) color AND the beams
; rendering 32px away from where they were actually positioned. Fixed
; to a plain color 7 (cyan, matching the attached art's own fg), no EC.
BOSS_BROKEN_BEAM_COLOR         EQU 07h
; raw frames between each beam firing in the 1->4 sequence, and between
; the 4th firing and hiding it/resuming movement - untuned placeholder.
BOSS_BROKEN_BEAM_INTERVAL EQU 20

; death/explosion sequence (see INIT_BOSS_EXPLOSION/UPDATE_BOSS_EXPLOSION
; below) - "倒した位置のボス中心から...半径48ｐｘの円に段々で塗りつぶす
; ...円を小さくして行き1セルになったら...最後の1セルを120フレ点滅させ
; 消滅". The circle is rasterized at CELL (8px) resolution, not real
; pixels - "1セルを1ｐｘと見做して" - so the algorithm's own radius unit
; is cells, and the requested 48px target becomes 48/8=6 cells.
BOSS_EXPL_MAXR EQU 6
; frames held per radius step (grow AND shrink both use this) - not
; specified by the instruction, a judgment call: 6 frames/step over 7
; steps each way (radius 0->6->0) is ~1.4s total for the whole grow+
; shrink, a deliberately slow/readable "ta-da" pace for a boss kill
; rather than a fast enemy-death blip. Revisit if it reads as too slow/
; fast once seen in motion.
BOSS_EXPL_STEP_FRAMES EQU 6
; blink cycle length (half on/half off) for both the boss-sprite blink
; during growth and the final single-cell blink - also a judgment call,
; not specified; 16 frames (8 on/8 off) is slow enough to read clearly
; as "blinking" rather than a flicker/strobe.
BOSS_EXPL_BLINK_PERIOD EQU 16
BOSS_EXPL_FINAL_FLASH_FRAMES EQU 120   ; "最後の1セルを120フレ点滅させ消滅" - exact, given
; the attack-pose hand art (SASAPI_HAND_CODE_BASE, group19) is retired
; for good the instant the boss dies (INIT_BOSS_EXPLOSION erases it/
; resets BOSS_PHASE if it was showing - "ボスがBG描画される右端で倒され
; た場合はスプライトに戻す" - and nothing ever re-enters BOSS_PHASE=1
; once BOSS_ACT=2), so its own code range is safe to repurpose as the
; explosion's solid-white fill tile instead of allocating a fresh one.
BOSS_EXPL_WHITE_CODE EQU SASAPI_HAND_CODE_BASE
BOSS_EXPL_WHITE_GROUP EQU 19
BOSS_EXPL_WHITE_COLORBYTE EQU 0F1h   ; fg15 white/bg1 black - same convention as HUD_DIGIT_COLORBYTE
; "ステージ1ボスのような爆発エフェクトをボスの範囲でランダムに...スプラ
; イトで描画すると消えてしまうんでBGで...ボスの範囲から外側に4セルラン
; ダムにエフェクトを飛ばしてくれ ウェイトなしで派手に沢山 3秒くらい"
; (round32) - a NEW phase (BOSS_EXPL_STATE_SPARK) that runs FIRST, before
; the existing circle/line sequence. No per-spark timer/duration
; tracking - see UBE_SPARK's own comment for why that's fine here. 180
; frames = 3 real seconds at this project's assumed 60fps (same "frames"
; unit FLASH_DURATION/EXPLOSION_DURATION already use elsewhere), 3/frame
; is a judgment call for "沢山" (not specified numerically).
;
; round32 follow-up fix #1: "そういう事じゃない ボックス範囲で消去もして
; ないから飛んでるかどうかもわからない ただ６４ｘ６４がBGで埋まってる
; だけだ じゃあボスの中心の３２ｘ３２の範囲でランダムに で、爆発キャラ
; は８ｘ８のほうではなく１６ｘ１６のほうで ランダムで混ぜてもいいがな" -
; the first version only ever ADDED sparks (never erased any until the
; whole phase ended), so once the small scatter area filled up it just
; read as one static solid block, not "flying" sparks.
;
; round32 follow-up fix #2 (correcting fix #1's own misreading of "32x32"):
; "爆発範囲を元の６４ｘ６４に てかこれはエフェクトが飛ぶ範囲ではなく
; 原点だからな そこからランダム方向に4セル飛ぶんだぞ" - the 64x64 figure
; was never the TOTAL scatter extent, it's the ORIGIN area (the boss's own
; body) each spark launches FROM; from that origin it then flies further,
; up to BOSS_EXPL_FLIGHT_RANGE cells, in a random direction. Two
; independent random draws (origin, then flight) stacked, not one flat
; box - naturally denser near the boss body and thinner further out,
; same shape as the "8方向ランダムに移動" idiom already established
; elsewhere in this file for enemy-death sprites, just axis-independent
; instead of 8-compass.
;
; Precise per-spark position tracking (not a blanket-sweep erase) is
; what makes the EVERY-FRAME erase from fix #1 affordable at this larger
; scale - see BOSS_EXPL_SPARK_SLOT's own comment: sweeping the whole
; possible box every frame would be far more VDP writes than are ever
; actually live at once, a real T-state concern this file has cared
; about before (see the VDP wait-state rounds).
;
; round32 follow-up fix #3: "悪くはないが飛びすぎたな 1から3セルランダ
; ムで" - fix #2's own flight offset (independent per-axis -4..+3) let
; the flight distance range anywhere from 0 (no flight at all) up to a
; diagonal ~5.7 cells (both axes near their own max magnitude at once) -
; wider and less controlled than intended. Replaced with an explicit
; direction+distance draw via BOSS_EXPL_FLIGHT_TABLE (8 compass
; directions - same convention as this file's own EXPLODE_DIR_DX/DY -
; times distance 1-3, precomputed as a 24-entry LUT rather than computed
; at runtime since Z80 has no multiply instruction) - "1から3セルランダ
; ムで" is now the flight's own EXACT distance range, never 0 and never
; more than 3 in any direction.
;
; round32 follow-up fix #4: "今でも飛びすぎなんで やはり原点をボス中心
; ３２ｘ３２に 前はお前が勘違いしてたからな" - even with the flight
; distance capped at fix #3, the TOTAL reach (origin's own 64x64 body +
; up to 3 more cells of flight) still read as too far. Shrunk the origin
; itself from the boss's full 64x64 body down to a 32x32/4-cell box
; centered on the boss (offsets -2..+1, same AND/SUB shape as the
; flight-less single-box fix #1 originally used for the WHOLE scatter
; area, now scoped to just the origin half of the two-stage draw).
BOSS_EXPL_ORIGIN_RANGE EQU 2      ; boss-center 32x32/4-cell box - offsets -2..+1
BOSS_EXPL_FLIGHT_MIN_DIST EQU 1   ; "1から3セルランダムで" - BOSS_EXPL_FLIGHT_TABLE below must match if this ever changes
BOSS_EXPL_FLIGHT_MAX_DIST EQU 3
BOSS_EXPL_SPARK_DURATION EQU 180
BOSS_EXPL_SPARK_PER_FRAME EQU 3   ; tied directly to the 3 hardcoded slots in UBE_SPARK - changing this needs matching slot blocks added/removed there, not just this constant
; another retired-hand-art code, group20 (160-167) - same safety
; argument as BOSS_EXPL_WHITE_CODE's own comment, just a different
; group so this can have its own distinct color. All 4 codes share this
; one group/color (no separate upload needed per quadrant). Pattern is
; EXPLOSION_PATTERN in full (already-established "explosion" art
; elsewhere in this file, reused instead of drawing something new) -
; "爆発キャラは８ｘ８のほうではなく１６ｘ１６のほうで" - the 16x16
; 4-quadrant version, TL/BL/TR/BR in the same plane order EXPLOSION_
; PATTERN's own data already uses. "ランダムで混ぜてもいいがな" - each
; spark independently rolls 8x8 (just the TL quadrant alone) vs the full
; 16x16 (all 4) 50/50, see BOSS_EXPL_SPARK_SLOT.
BOSS_EXPL_SPARK_CODE_TL EQU 160
BOSS_EXPL_SPARK_CODE_BL EQU 161
BOSS_EXPL_SPARK_CODE_TR EQU 162
BOSS_EXPL_SPARK_CODE_BR EQU 163
BOSS_EXPL_SPARK_GROUP EQU 20
BOSS_EXPL_SPARK_COLORBYTE EQU 081h   ; fg8(EXPLOSION_COLOR)/bg1 black - "近い色" to BOSS_COLOR(9), same value as SASAPI_HAND_FLASH_COLORBYTE (coincidental, not reused by name)
BOSS_EXPL_STATE_SPARK  EQU 4
BOSS_EXPL_STATE_GROW   EQU 0
BOSS_EXPL_STATE_SHRINK EQU 1
BOSS_EXPL_STATE_FLASH  EQU 2
BOSS_EXPL_STATE_DONE   EQU 3
; "フラッシュ処理はホワイトだと眩しいのでレッドに ボス戦だけな 通常は
; ホワイトのままでいじるな" - a BOSS-ONLY override of the hit-flash
; color; the shared global FLASH_COLOR(white) every other entity uses
; is untouched. Medium red(8), same shade EXPLOSION_COLOR already uses
; in this file for damage/destruction feedback - deliberately NOT
; BOSS_COLOR's own light red(9), so the flash actually reads as a
; distinct color change against the boss's own base color instead of
; disappearing into it.
BOSS_FLASH_COLOR EQU 8
; "右から出て左に行き反転して右端に戻ったら 添付のパターンをBGに描画し
; スプライトは一旦消す ようするに移動中はスプライト 停止中はBGて切り
; 替え これは攻撃ポーズなのでその状態で32Tick停止後 また巡回" - "Tick"
; means GAME_TICK throughout this session's own instructions (Tick850/
; 900/950/999 etc.), so this is a true 16-bit GAME_TICK duration, not a
; raw-frame countdown like FLASH_DURATION/EXPLOSION_DURATION - see
; BOSS_POSE_END_TICK's own comment.
; "ポーズ停止時間を少し短く" (round7: was 32) - exact amount not
; specified, a modest ~25% cut chosen as "少し" - flag for correction if
; a different magnitude was wanted.
BOSS_POSE_TICKS EQU 24
; "左端は2Tick停止してから反転発射に 反転した時にボス自身に当たって
; しまう" (round9), then "まだ反転時ボスにサンダーが当たってるんで8
; Tick停止に変更" (round11, 2->8) - a brief stationary pause at the left
; edge before actually reversing, same true 16-bit GAME_TICK-duration
; idiom as BOSS_POSE_TICKS (see UBA_LEFT_PAUSE).
BOSS_LEFT_PAUSE_TICKS EQU 8
; the attack-pose hand art is drawn straight into the name table, not a
; hw sprite - needs its own 64 BG pattern codes (groups19-26, 152-215 -
; the next free block after group18/BULLETF's own night codes, per
; HANDOFF's "groups19-30 still free" note) since it's a genuinely
; different 64x64 image from the boss's own body (SASAPI_QUADS).
SASAPI_HAND_CODE_BASE EQU 152
; same fg9(light red)/bg1(black) as sprites/SasapiHand_64x64.json's own
; header - matches BOSS_COLOR's own light red, and bg1/black matches
; the sky band's own already-fully-night-swept color by BOSS_SPAWN_TICK
; (see NIGHT_START_TICK's own comment - the sweep always completes well
; before the boss can ever reach this pose).
SASAPI_HAND_COLORBYTE EQU 091h
; hit-flash color for the hand's own BG art while posing - "ポーズ中の
; 被弾フラッシュ演出を追加(復帰処理とは別に併用)". BG color is fixed
; per 8-code group (unlike a hw sprite's own per-instance SAT color
; byte, which is how BOSS_FLASH_COLOR flashes the body for free) - but
; since the hand's own 8 groups (19-26) are exclusively its own art,
; nothing else shares them, a full group recolor is just as cheap here
; (8 bytes, one LDIRVM) as a sprite's own color-byte swap, with zero
; risk of recoloring anything unrelated. Same medium-red shade as
; BOSS_FLASH_COLOR(8) - fg8/bg1, not fg9(BOSS_COLOR)'s own light red -
; so it reads as the same flash, not a different color entirely.
SASAPI_HAND_FLASH_COLORBYTE EQU 081h
; "スプライトパターンそんなに使ってるか? 自機とボスだけだぞ もしそう
; なら動的に書き換えしてくれ...BGでは...動きがガタガタで速すぎるんだ
; よ スプライト必須" - a REAL hw sprite after all, not BG (round-2
; correction of the previous round's BG-drawing decision - BG's own
; column-granular movement was too coarse for a fast, smooth-tracking
; missile).
; "ホーミングスプライトは16x16だぞ 何を流用したんだ" - round-4
; correction of round-2's own explanation: this is NOT reusing "spare
; padding" inside Flyer's own block (there isn't any - Flyer is a real
; 32x32 sprite, and flyer_gen.py's own quadrants_from_bits/block16_bytes
; genuinely fill all 32 of its own codes, 16 for each of its 2 facings,
; with real art). It's a full TAKEOVER of Flyer's entire block, exactly
; like PAT_SASAPI's own takeover of BigZum's block for the boss's own
; body a few lines below - once the boss fight starts, Flyer (like
; ZacoII/Zum) never spawns again ("オールフリー"), so overwriting its
; pattern data outright is fine, on the SAME already-trusted timing
; precedent BOSS_SPR_BASE_SLOT/PAT_SASAPI already rely on. round34
; ("全てスケジュールに"): this used to be a code-level guarantee (a
; shared ENEMY_SPAWN_STOP_TICK gate blocked every ALLOC_*_SLOT well
; before the boss), now it's a property of the schedule's own content
; instead - each type's own LAST scheduled spawn just needs enough of a
; gap before the boss's own tick to naturally finish (explode/despawn)
; first. BigZum is the one exception with an explicit code-level
; safety net regardless of schedule content (BIGZUM_RETREAT_TICK forces
; it off-screen - see UPDATE_ONE_BIGZUM's own comment); the other 4
; types rely on the schedule author leaving a wide enough gap - see
; tools/stage2_combined/HANDOFF.md's own round34 entry for this
; specific schedule's own margins and how they were verified.
;
; Loaded dynamically at boss spawn time, not INIT - Flyer needs its own
; real pattern data intact
; for ordinary gameplay before that. 5 facings x4 codes each (16x16-
; padded, TL/BL/TR/BR - same "VDP already in 16x16 mode" constraint as
; every other hw sprite here) = 20 of Flyer's own 32 codes actually
; written; the remaining 12 (Flyer_L's own tail) are untouched only
; because nothing currently needs them, not because they were ever kept
; separately reserved for Flyer itself.
PAT_HORMING_SL   EQU PAT_FLYER+0
PAT_HORMING_DL   EQU PAT_FLYER+4
PAT_HORMING_DOWN EQU PAT_FLYER+8
PAT_HORMING_DR   EQU PAT_FLYER+12
PAT_HORMING_SR   EQU PAT_FLYER+16
; "ホーミング弾の色をライトブルーに変更" (round7: was fg14 gray,
; matching the 5 uploaded JSON sprites' own header - a hw sprite's own
; color is a free per-instance SAT byte, no group/background constraint
; the way BG tiles have, so overriding it here doesn't touch the
; uploaded art itself). fg5 light blue - same palette index this file
; already uses elsewhere for "light blue" (NIGHT_COLOR, CLOUD_GROUP0_
; COLOR).
HORMING_COLOR EQU 5
; round36-12: BG pattern codes for the new BG-drawn 4-instance pool
; (HORMING_BG_POOL) - group18 (144-151), freed up entirely by round36-
; 11's own move of the bullet night-glyph codes off this group. Only 5
; of its 8 codes used (one per facing, no separate _L/mirror - the 5
; source sprites already cover every direction the missile actually
; faces, unlike the tank's own bullets which need a true left/right
; mirror). This is the SKY-band table (rows above the terrain, same
; range ERASE_HORMING_BG_CELL's own EHBC_SKY branch covers). Originally
; reused BULLET_SKY_COLORBYTE (fg9/bg5 light blue), reasoning sky is the
; dominant case; round36-13 correction ("BGホーミングの背景色をブラックに
; 今はブルーになってる") - changed to bg1 (black) instead, fg9 kept.
HORMING_BG_SL_CODE   EQU 144
HORMING_BG_DL_CODE   EQU 145
HORMING_BG_DOWN_CODE EQU 146
HORMING_BG_DR_CODE   EQU 147
HORMING_BG_SR_CODE   EQU 148
HORMING_BG_COLORADDR EQU 2012h   ; 2000h+group18
HORMING_BG_COLORBYTE EQU 091h    ; fg9 light red / bg1 black (round36-13, was bg5 light blue)
; round36-14 ("BGホーミングが地形に入ったときはSandの背景色になるように
; ブラックのままだと目立つんで"): a second, terrain-band table for the
; same 5 facings, picked by DRAW_HORMING_BG_CELL once the missile's own
; row reaches BULLET_ROCK_ROW_MIN (16) - same threshold ERASE_HORMING_
; BG_CELL already uses to leave EHBC_SKY.
;
; round36-14 follow-up (real-hardware report: "スクロールの地形のSandが
; ほかのパターンに書き換わってる 前のROMでは正常だった") - the FIRST
; attempt placed these in codes18-22, reasoning group2's BLEND_BASE(24)
; meant only 2 of its 8 codes were "actually used". That reasoning missed
; the SAME-ID (Sand,Sand) pair's own 7-frame blend block (terrain_gen.py's
; own BLANK_PAIR_BASE comment literally says "7 blend phases" - codes
; 17-23, not just 17 alone; every one of 16-23 is real, load-bearing
; terrain animation data) - confirmed directly:
; `python3 -c "import terrain_gen as tg; print([tg.pair_block_code(p)+k
; for p in tg.PAIRS for k in range(7)])"` includes 18-23. Relocated to
; codes96-100 (group12) instead, verified genuinely empty (all-zero
; pattern bytes) both at boot AND ~2000 frames into a real boss fight via
; direct emulator VRAM inspection - not a static-reasoning claim this
; time. Group12 IS one of the groups ROCK_COLOR_SWAPPED_PATCH's own bulk
; write covers (groups3-31), so - unlike the group2 attempt - this DOES
; need its own explicit color write (HORMING_BG_SAND_COLORADDR/
; COLORBYTE below), placed after that patch runs.
HORMING_BG_SAND_SL_CODE   EQU 96
HORMING_BG_SAND_DL_CODE   EQU 97
HORMING_BG_SAND_DOWN_CODE EQU 98
HORMING_BG_SAND_DR_CODE   EQU 99
HORMING_BG_SAND_SR_CODE   EQU 100
HORMING_BG_SAND_COLORADDR EQU 200Ch   ; 2000h+group12
HORMING_BG_SAND_COLORBYTE EQU 0ABh    ; SAND_COLOR (fg10 dark yellow/bg11 light yellow) - matches terrain's real Sand color exactly
; round 4 fix: "ホーミングのスプライトが非表示待機になってるからだろ
; うが ボス上部が常に表示欠けしている" - a real, confirmed bug. The
; previous round's reasoning ("boss's own slots10-25 are free while any
; missile can exist, since the pose empties them") was WRONG: missiles
; now (round3) fly for far longer than the pose itself (rise+wander+
; home can easily outlast BOSS_POSE_TICKS), so a missile is routinely
; still alive/rendering AFTER the boss has already resumed patrolling as
; a real hw sprite in slots10-25 again. UPDATE_HORMING_ALL runs every
; MAINLOOP frame unconditionally and always ends by flushing (even an
; all-hidden pool writes Y=209 to all 4 slots) - since it's called AFTER
; UPDATE_BOSS_ALL, this made the missile pool's own flush the LAST write
; to slots10-13 every single frame, permanently stomping the boss's own
; first 4 quadrants right after DRAW_BOSS/FLUSH_BOSS_SPRITES drew them -
; exactly BOSS_SPR_BASE_SLOT's own documented invariant ("safe as long
; as UPDATE_BOSS_ALL is called AFTER all 4 of their own per-frame
; flushes...so the boss's own real data is always the LAST write") being
; violated by a 5th, unaccounted-for late writer.
; Fixed by moving the missile pool OFF the boss's own body range
; entirely - reuses BULLET_U_SPR_BASE_SLOT's own slots7-9 (UBUS_ONE
; already unconditionally hides them the INSTANT BOSS_ACT!=0, since U
; becomes BG-drawn during the boss fight - airtight, not a timing
; estimate) plus ENEMY_SPR_BASE_SLOT's own LAST slot (6) - "自機以外は
; もうスポーンしないんで オールフリー", same already-trusted "spawning
; stopped well before boss-spawn, so by the time this is ever read the
; pool is empty" reasoning BOSS_SPR_BASE_SLOT/PAT_SASAPI already rely on
; for reusing Zum/BigZum/Flyer/Etank's own hw sprite slots10-25 (and
; already proven out by every passing boss test). UPDATE_HORMING_ALL now
; also RET Z's immediately whenever BOSS_ACT=0 (see its own comment) -
; without that guard, slots6-9 would be stomped by the missile system's
; own per-frame flush even BEFORE the boss exists, while ZacoII/BulletU
; still genuinely need them.
HORMING_SPR_BASE_SLOT EQU 6
; hw sprite slots10-25 (16 quadrants, one per 16x16 cell of the 4x4
; grid making up the 64x64 sprite) - reuses Zum/BigZum/Flyer/Etank's
; own ranges (10-11/12-19/20-23/24-25) rather than a fresh permanent
; allocation (would overflow the 32-slot budget outright) - "自機以外
; はもうスポーンしないんで オールフリー": round34 ("全てスケジュール
; に") moved this from a code-level guarantee to a schedule-content
; property - see PAT_HORMING_SL's own comment above for the full
; explanation and BigZum's own remaining code-level exception. Safe as
; long as the schedule's own last spawn of each type leaves enough of a
; gap to naturally clear before the boss, and as long as UPDATE_BOSS_ALL
; is called AFTER all 4 of their own per-frame flushes in MAINLOOP (so
; the boss's own real data is always the last write to these slots each
; frame, not overwritten a moment later by an old, now-permanently-empty
; pool's own routine flushing Y=209-hidden over it) - it is, right
; before CLOUD_UPDATE_ALL.
BOSS_SPR_BASE_SLOT EQU 10
; reuses BigZum's own whole pattern-code footprint (156-219, PAT_BIGZUM
; below) rather than a new permanent block - Sasapi's 16 quadrants x4
; patterns = exactly 64 slots, exactly BigZum's entire footprint (all 4
; of its pose/facing groups). Same "オールフリー" reasoning as the hw
; sprite slots above, plus there simply isn't 64 more spare slots above
; Flyer's own last group (ends at 251, only 4 free) for a permanent 5th
; allocation. Loaded fresh into VRAM once, at boss-spawn time (not at
; INIT) - see LOAD_SASAPI_PATTERNS.
PAT_SASAPI      EQU PAT_BIGZUM
; round36-14 follow-up#4 ("停止中にビーム攻撃をする") - the 4 broken-
; form beam sprites' own hw sprite pattern codes, PAT_SASAPI+16/+20/+24/
; +28 (see BOSS_BROKEN_BEAM_TABLE's own comment for why these codes
; specifically). Defined HERE, immediately after PAT_SASAPI itself,
; rather than down near BOSS_BROKEN_BEAM_TABLE where they're actually
; used (which is this assembler's normal convention) - round36-14
; follow-up#4's 2nd real-hardware feedback ("全然違うぞ...グラフィック
; も壊れてる") traced back to a genuine mini_z80asm.py forward-reference
; bug: REVEAL_BOSS_BROKEN_FORM (far above BOSS_BROKEN_BEAM_TABLE in the
; file) referenced these EQUs before their old definition point, and the
; chained expression "BOSS_BROKEN_BEAM_CODE1*8+SPRPAT" silently resolved
; PAT_SASAPI as 0 in that context - loading all 4 beams into codes
; 16/20/24/28 relative to VRAM address 0 instead of PAT_SASAPI(156)+16/
; 20/24/28, landing on top of the OLD 64x64 body's own still-resident
; leftover pattern data (never overwritten by anything else, so it just
; sat there as visual noise). Confirmed via direct emulator VRAM
; inspection (per this project's own standing "verify empirically"
; practice) that the beam codes' true destination addresses in the
; assembled ROM did NOT match PAT_SASAPI+16/20/24/28 until moved here.
; Moving the definition above the only other place in the file that
; references these EQUs before their own (still-canonical, still used
; by BOSS_BROKEN_BEAM_TABLE/FIRE_BOSS_BROKEN_BEAM below) definition
; sidesteps the assembler bug entirely, without needing to fix the
; assembler itself.
BOSS_BROKEN_BEAM_CODE1 EQU PAT_SASAPI+16
BOSS_BROKEN_BEAM_CODE2 EQU PAT_SASAPI+20
BOSS_BROKEN_BEAM_CODE3 EQU PAT_SASAPI+24
BOSS_BROKEN_BEAM_CODE4 EQU PAT_SASAPI+28
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
; "円の爆発はノイズでどーーーーんって長いやつ" - lowest noise period the
; AY-3-8910 supports (0-31, 5 bits) for the deepest/most "boom"-like
; rumble available, clearly distinct in pitch from the shot(8)/regular-
; destroy(20) sounds. "で、素のノイズの減衰ではチャチなので デューティ
; 比1:1で減衰しながらボリューム半分かOFFをまぜてくれ そうすればブリブ
; リって音になるはず" - SOUND_UPDATE's own SU_BOOM branch alternates
; between full-strength and silent every frame (TICK's own low bit - a
; free-running per-frame flip, no dedicated toggle byte needed) as the
; underlying envelope steps down, giving the buzzy/pulsing texture a
; plain linear noise fade wouldn't have - see BOSS_BOOM_CALC_VOLUME's
; own comment for why "on" frames are full-strength, not halved (round32
; follow-up: "音量最大か? かなり小さいが" - halving on top of the 1:1
; duty cycle's own silence made every frame quieter than the hardware's
; real max). Peak 15 stepping down 1 every
; BOSS_BOOM_DECAY_PERIOD frames = a real 75-frame decay (15*5, ~1.25s
; @60fps) - deliberately close to the circle explosion's own GROW+SHRINK
; length (BOSS_EXPL_STEP_FRAMES*BOSS_EXPL_MAXR*2=72 frames) so the boom
; roughly tracks the visual, not an exact sync (not specified that
; precisely) - a judgment call, easy to retune via this one constant.
BOSS_BOOM_NOISE_PERIOD EQU 31
BOSS_BOOM_DECAY_PERIOD EQU 5
; "爆発エフェクト中も爆発音追加" (round32) - the SPARK burst itself
; (before the circle even starts, see BOSS_EXPL_STATE_SPARK) had no
; sound at all until now. Not specified beyond "add one" - a repeating
; short, high-pitched "crackle" (distinct pitch from shot(8)/regular-
; destroy(20)/boom(31)) matches the burst's own visual character
; ("ウェイトなしで派手に沢山") better than one single sustained tone
; would, so UBE_SPARK retriggers SOUND_SPARK_CRACKLE once every
; SPARK_CRACKLE_PERIOD frames (a judgment call, easy to retune) rather
; than every single frame (which would just reset the same envelope
; over and over into a continuous drone, not a "crackle"). No new RAM -
; the trigger cadence reads straight off BOSS_EXPL_TIMER's own low bits
; (it's already counting down every SPARK frame for an unrelated
; reason - see INIT_BOSS_EXPLOSION's own comment), and this shares the
; same SND_TIMER/SND_DECAY envelope bytes as every other short sound in
; this file - no SND_EXPLODING guard, same casual/frequent-sound
; treatment SOUND_SHOT already gets, not treated as "the important one"
; the way the boom itself is.
SPARK_CRACKLE_PERIOD EQU 4   ; must be a power of 2 - UBE_SPARK's own trigger check ANDs BOSS_EXPL_TIMER against this-1
SPARK_CRACKLE_NOISE_PERIOD EQU 14
SPARK_CRACKLE_PEAK EQU 15   ; round32 follow-up: "スパーク爆発も音量最大か? でなければ最大に" - was 8, now the PSG's own real hardware max (register8's volume field is 4 bits/16 steps, same as every other sound's own peak here)
SPARK_CRACKLE_DECAY EQU 3

; ---------- boss attack SFX (round36-14 follow-up#5, "ではボス攻撃に
; サウンドを入れる ホーミング、サンダー、サンダービーム、ササピーレー
; ザーそれぞれに") - chosen by the user out of 3 auditioned candidates
; each, via a Web Audio prototype page built to model this exact same
; PSG envelope/gating engine (period/peak/decay values below are
; transcribed straight from that prototype's own reference numbers, not
; re-derived) - "ホーミングはH2 サンダーはT3 サンダービームはS1
; ササピーレーザーはL3で" then "それぞれ音量は最大で" (peak 15,
; overriding whatever each candidate's own preview peak happened to be).
; All 4 share the exact same channel-A envelope engine (SND_TIMER/
; SND_DECAY/SND_NOISE/SOUND_UPDATE) every existing SFX in this file
; already uses - no new engine code, same "shared channel, latest
; trigger wins" tradeoff as SOUND_SHOT/SOUND_ZUM_DEFLECT.
; ホーミング「バシュバシュ」(H2, ノイズ・ウィッシュ) - short, bright,
; fast-decaying noise burst; SHOT_NOISE_PERIOD(8) より少し明るいピッチ。
HORMING_NOISE_PERIOD EQU 6
HORMING_SND_DECAY EQU 4
; サンダー「雷鳴」(T3, 長い轟き) - SOUND_BOSS_BOOM と全く同じ「デューティ
; ゲート+BOSS_BOOM_DECAY_PERIODで1段ずつゆっくり減衰」の仕組みをそのまま
; 流用(新規メカニズム不要)、ピッチのみ別の定数で変える。「低すぎて聞こ
; えない」というユーザーからのフィードバックを受けて当初案(31相当)より
; 高いピッチに改訂済み。SND_EXPLODING は立てない - BOSS_BOOMやDESTROYの
; ような一回性の演出と違い、戦闘中に何度も鳴る通常攻撃なので、自機ショッ
; ト音を長時間ブロックしてしまうのは望ましくないという判断(SOUND_SHOT
; 自身の"RET NZ"ガードの対象から外す)。
THUNDER_NOISE_PERIOD EQU 18
; サンダービーム「ビビビー」(S1, 速いトレモロトーン) - プロトタイプでは
; 専用の2-on:1-offパターンを試作したが、60fps更新である以上「標準の1:1
; デューティゲート(SND_NOISE=1)をノイズではなくトーンchに適用する」のが
; 実質同じ「ブリブリ」感を最も安価に再現できると判断し、そちらを採用
; (新規ゲートモード追加は不要)。トーンchへのデューティ適用はSOUND_
; ZUM_DEFLECTの逆(あちらは意図的にデューティ無し)。
SBEAM_SND_TONE_PERIOD EQU 20
SBEAM_SND_DECAY EQU 1
; ササピーレーザー(L3, デューティ版) - 指示通りsrc/CYBER SHMUP.asmの
; SOUND_SHOTを流用、トーンピッチ(period30)はStage1の実値そのまま。L3の
; 選定通りデューティゲートを追加(Stage1本来はゲート無し)、ピークは
; "それぞれ音量は最大で"によりStage1の実値12から15へ引き上げ。
SASAPI_LASER_TONE_PERIOD EQU 30
SASAPI_LASER_SND_DECAY EQU 1

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
ENEMY_POOL    EQU F180h   ; ENEMY_SLOT_SIZE*ENEMY_SLOT_COUNT = 27 bytes
; round34 ("ランダムスポーンは廃止 全てスケジュールに") repurposes this
; byte: was ENEMY_SPAWN_TIMER (frame countdown to the next random-timer
; spawn attempt), now the schedule's own walk pointer - see
; SPAWN2_SCHEDULE_CHECK/SPAWN2_NEXT_INDEX's own comment further down.
SPAWN2_NEXT_INDEX   EQU F19Bh
; round34: was ENEMY_SPAWN_COUNT (total spawned so far, capped at 10,
; drove the old "first 10 green, then 50/50 red/green" coinflip - see
; ALLOC_ENEMY_SLOT's own history in git blame). The schedule now picks
; green vs red explicitly per placement (s2_zacoii vs s2_zacoii_red), so
; that whole counter/coinflip is gone; this byte is repurposed as
; S2_SPAWN_Y - the CURRENT firing schedule entry's own pixel Y (row*8),
; staged by SSC2_FIRE just before dispatch, consumed by whichever
; ALLOC_*_SLOT the CP-chain calls (ignored by the 3 ground types, whose
; own Y always comes from the terrain/tier logic instead - see each
; ALLOC_*_SLOT's own comment).
S2_SPAWN_Y   EQU F19Ch
; staging buffer for the 3 enemy hw sprite slots (4-6, right after the
; tank's own 0-3) - same "build in RAM, blast once" pattern as
; SPRITE_ATTRS/UTS_OUT_LOOP, just a separate buffer so the two flushes
; stay independent.
ENEMY_SPRITE_ATTRS EQU F19Dh   ; 12 bytes: Y,X,pat,col x3
ENEMY_SPR_BASE_SLOT EQU 4       ; hw sprite index slot0 uses; slotN -> ENEMY_SPR_BASE_SLOT+N

; green (normal) variant speed: "自機と同じ1.5で" - same alternating
; 1/2-px-per-frame trick as TANK_SPEED_LO (see UTX_DO_RIGHT/LEFT),
; averaging 1.5px/frame - was a flat 1 ("スピードが遅いんで早くして").
ENEMY_SPEED_LO  EQU 1
ENEMY_SPEED_RED EQU 3   ; red variant: flat 3px/frame - "ZakoIIはの赤は速度３で" (was 2)
; "ZakoII赤の耐久２" - red now takes 2 hits instead of the usual 1;
; green is unaffected (still 1-hit, see CHECK_HIT_PAIR's own variant
; check). Tracked in E_DX (offset+7) while alive - that field is
; otherwise unused until E_ACT=2 (explosion drift only reads/writes it
; once actually destroyed), so no new pool field/slot-size growth (and
; no cascading RAM-address renumbering downstream of ENEMY_POOL) is
; needed - same "repurpose an otherwise-idle field" precedent as Zum's
; own Z_TIMER doing double duty for explosion timer/pause countdown.
ENEMY_RED_HP EQU 2
; "耐久値を持つ敵や自機がダメージを食らったら一瞬ホワイトに光るように
; スプライトのカラー指定だな" - every HP-bearing entity (ZacoII red,
; BigZum, and later any other durability-bearing enemy) and the tank
; itself gets the same mechanism: a per-slot countdown field, set to
; FLASH_DURATION on a non-lethal damaging hit, that overrides the
; sprite's normal color attribute(s) to FLASH_COLOR while nonzero and
; ticks down by 1 once per drawn frame. ZacoII's own 1-hit-kill green
; variant and every entity's own final, destroying hit never flash
; (they explode the same frame instead - nothing to flash). Both
; values are untuned/inferred - "一瞬" (an instant) suggested a short
; flicker, not a held glow.
; "ほかの敵のフラッシュ処理もレッドに" - was white(15), too bright per
; the same complaint that led to the boss's own dedicated BOSS_FLASH_
; COLOR; now the same medium-red(8) shade globally, for every entity
; that shares this one constant (tank, ZacoII, Zum, BigZum, Flyer,
; Etank). No entity's own base color is red except Etank(6, dark red) -
; still a visibly distinct shade shift, same as every other entity's
; own color->8 change.
FLASH_COLOR    EQU 8    ; medium red
FLASH_DURATION EQU 6    ; frames
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
; round34: was "Skyのみのの位置に出現...現状はランダム" - a TICK-derived
; pseudo-random Y band (ENEMY_SKY_Y_MIN/MASK), explicitly a placeholder
; ("地形も合わせてスケジュールエディタで対応予定"). Now superseded: Y
; comes straight from the schedule's own row (S2_SPAWN_Y, row*8), no
; random band needed - see ALLOC_ENEMY_SLOT.
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
ZUM_POOL       EQU F1ECh   ; ZUM_SLOT_SIZE*ZUM_SLOT_COUNT = 14 bytes
; "ZUM_SLOT_SIZE*ZUM_SLOT_COUNT = 14 bytes" (this comment's own original
; value, before Z_RETREAT - see ZUM_SLOT_SIZE's own comment - grew the
; struct from 7 to 8 fields/14 to 16 bytes total without this address
; ever being pushed forward to compensate): overlapped the LAST 2 bytes
; of ZUM_POOL's own slot1 (Z_DY/Z_RETREAT) with THIS buffer's own first
; 2 bytes (Y,X of hw sprite0) - found via a full systematic RAM-overlap
; audit across every pool in this file (the only one found - everything
; Etank/Flyer/BigZum touched this session is clean). Every RAM address
; from here through BANKSWITCH_TRAMPOLINE_RAM shifted +2 bytes to
; actually clear ZUM_POOL's real 16-byte span.
ZUM_SPRITE_ATTRS EQU F1FCh ; 8 bytes: Y,X,pat,col x2 - same staging-buffer pattern as ENEMY_SPRITE_ATTRS
; round34: was ZUM_SPAWN_TIMER (random-interval countdown, now removed -
; "ランダムスポーンは廃止"). Repurposed as S2_SPAWN_VARIANT (0=green/
; 1=red), staged by SPAWN_S2_ZACOII/SPAWN_S2_ZACOII_RED just before
; calling the shared ALLOC_ENEMY_SLOT - see S2_SPAWN_Y's own comment.
S2_SPAWN_VARIANT  EQU F204h
; "乗っかりから降りる時の速度が速すぎてワープにみえる" - set by
; UPDATE_TANK_ZUM_STAND (1 if it actually clamped TANK_Y_CUR against a
; Zum this call, else 0); read by UPDATE_JUMP the following frame to
; auto-land smoothly instead of snapping straight to ground the
; instant the jump timer runs out while still parked - see
; JUMP_LANDING_RESTART_FRAME below.
TANK_ZUM_STANDING EQU F205h
; "乗っかり中にジャンプできないんで オートジャンプ中でも出来るように" -
; UPDATE_JUMP normally refuses a new press whenever JUMP_ACTIVE is
; already set, which while parked on a Zum is *always* true (the
; auto-land cycle above never clears it, only restarts JUMP_FRAME).
; JUMP_STAND_BASELINE holds the current stand-elevation above true
; ground (TANK_GROUND_Y-TANK_Y_CUR) at the moment a fresh jump is
; honored while parked, so the new jump's own arc adds on top of
; where the tank already is instead of first snapping down to
; TANK_GROUND_Y and jumping from there - see UPDATE_JUMP.
JUMP_STAND_BASELINE EQU F206h
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
; used (Z_X+8)>>3 = 31 at X=240 - the OLD spawn-time flat-ground gate
; (ZUM_TERRAIN_OK, removed in round35 - "地形も仮実装だから平地条件
; いらない" - terrain movement following itself is unaffected) was
; checking one column to the *left* of where Zum actually stands the
; instant it spawns, so it didn't match what UOZ_TERRAIN_FOLLOW
; immediately probed for real. ZUM_SPAWN_COL is still shared with UOZ_
; TERRAIN_FOLLOW's own per-frame probe below, so they can't drift apart
; again even with the spawn-time gate itself gone.
ZUM_PROBE_DX EQU 8
; the column Zum's own horizontal center lands on at spawn - derived,
; not hand-typed, so it always matches UOZ_TERRAIN_FOLLOW's own probe.
ZUM_SPAWN_COL EQU ZUM_SPAWNX+ZUM_PROBE_DX/8
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
; "Zumのコリジョンは24x24 今のままだと飛び越えるのが困難 絵も24x24
; くらいになってるんで" - Zum's OWN collision footprint (distinct from
; TANK_PUSH_WIDTH above, which is the tank's own width) is now this
; explicit, correctly-sized box instead of the mismatched mix that was
; there before: UPDATE_TANK_ZUM_STAND's own stand-on-top overlap test
; used to pair Zum's real 16px sprite width on one side against the
; tank's own (larger, 32px) TANK_PUSH_WIDTH on the other - an
; asymmetric combined window (up to 48px wide) that made a clean
; jump-over needlessly hard to time. Now used symmetrically everywhere
; Zum's own collision extent matters: the push-contact boundary
; (UPDATE_TANK_ZUM_PUSH), the stand-on-top overlap test (UPDATE_TANK_
; ZUM_STAND), the spawn-time overlap resolution (ALLOC_ZUM_SLOT), and
; the bullet hit-box (CHECK_HIT_PAIR_ZUM, both X and Y). Zum-specific.
ZUM_COLLISION_SIZE EQU 24
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
; same spawn gating as Zum (originally ENEMY_SPAWN_COUNT>=10 plus a
; flat-ground probe at its own spawn column, both long since removed -
; see ALLOC_BIGZUM_SLOT's own comment for the current, schedule-driven
; gating: a free slot, nothing else) and the same approach/decel/pause
; shape (reuses
; ZUM_DETECT_RANGE/ZUM_MID_RANGE/ZUM_SPEED_BASE/ZUM_ACCEL_TABLE/
; ZUM_DECEL_TABLE/ZUM_PAUSE_FRAMES outright - "アルゴリズムもほぼ同じ"
; means literally reusing those tables/constants, not re-deriving new
; ones). The 2 post-pause branches replace Zum's push-vs-flee with
; punch-vs-jump-on:
;   BZ_STATE=2 (punching) - closes any remaining gap (same ZUM_ACCEL_
;     TABLE ease Zum's own charge uses), then holds position once
;     within BIGZUM_COLLISION_SIZE and throws a punch (BIGZUM_PUNCH_
;     INTERVAL frame cadence) instead of Zum's continuous 1:1 push - see
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
; rear hit only decrements BZ_HP (init BIGZUM_HP_INIT=5 - see its own
; comment for the full history) and only actually destroys it once that
; reaches 0.
; grew 12->13 for +12 FLASH_TIMER (hit-flash countdown - see FLASH_
; DURATION's own comment), then 13->15 (round35) for +13/+14 OWN_
; RETREAT_TICK (see BIGZUM_ENGAGEMENT_DURATION's own comment) - still
; fits inside the original 24-byte (BIGZUM_SLOT_SIZE(12, old)*BIGZUM_
; SLOT_COUNT(2, old)) RAM reservation even at 15 bytes/slot, since only
; 1 slot is ever actually used now (BIGZUM_SLOT_COUNT=1 below) - no
; address renumbering of anything downstream of BIGZUM_POOL needed.
BIGZUM_SLOT_SIZE  EQU 15   ; +0 ACT,+1 X,+2 Y,+3 TIMER(explosion/pause countdown/punch-pose-frames - all mutually exclusive across states),+4 SPRIDX,+5/+6 DX/DY(explosion drift while ACT=2; +6 doubles as the shake-off stand-timer while ACT=1 - see BIGZUM_SHAKE_STAND_FRAMES),+7 STATE(0=approach,3=pause,1=jump,2=punch),+8 HP,+9 FACING(0=normal facing left,1=flipped facing right),+10 JUMPFRAME,+11 PUNCH_COOLDOWN(STATE=2)/shake-off-jump marker(STATE=1),+12 FLASH_TIMER,+13/+14 OWN_RETREAT_TICK(16-bit, this instance's own forced-retreat GAME_TICK, computed once at spawn - see BIGZUM_ENGAGEMENT_DURATION's own comment)
; "BigZumは１体のみ 横並びあるから" - was 2 (mistakenly assumed to
; match Zum's own concurrent limit just because "スポーン条件は同じ" -
; corrected: BigZum's own side-by-side limit is 1, distinct from
; Zum's). Reserved pool/attr-buffer space (below) is left sized for
; the old count rather than shrunk - harmless, the unused tail simply
; never gets written/flushed once only 1 slot is ever iterated.
BIGZUM_SLOT_COUNT EQU 1
BIGZUM_POOL       EQU 0F207h  ; BIGZUM_SLOT_SIZE*BIGZUM_SLOT_COUNT = 24 bytes reserved (only the first 12 actually used now - see BIGZUM_SLOT_COUNT)
; round34: was BIGZUM_SPAWN_TIMER (random-interval countdown, now
; removed). round34-2 briefly repurposed 0F21Fh as SPAWN2_STALL_COUNT
; for a retry-with-timeout spawn design; round34-3 replaced that design
; entirely with Stage1's own unconditional-advance/drop-on-failure
; SSC_FIRE model (see SPAWN2_SCHEDULE_CHECK's own comment), so this
; byte is unused again - left unclaimed rather than repurposed further.
; staging buffer for BIGZUM_SLOT_COUNT*4 hw sprite slots (4 per
; instance - a 32x32 BigZum is 2x2 of 16x16 hw sprites, same quadrant
; convention as the tank's own SPRITE_ATTRS/UPDATE_TANK_SPRITES, just
; per-pool-slot via BZ_SPRIDX instead of a single fixed instance).
BIGZUM_SPRITE_ATTRS EQU 0F220h   ; BIGZUM_SLOT_COUNT*16 = 32 bytes: (Y,X,pat,col)x4 per instance
BIGZUM_DRAW_TEMP  EQU 0F240h     ; scratch byte, UOBZ_DRAW's own chosen pattern base
BIGZUM_DRAW_COLOR EQU 0F241h     ; scratch byte, UOBZ_DRAW's own resolved color (BIGZUM_COLOR or FLASH_COLOR) - still well under the real 0F380h BIOS-work-area boundary (see STACKTOP's own comment)
; hw sprite slots12-19 reserved for 2 instances x4 (right after Zum's
; own 10-11), but BIGZUM_SLOT_COUNT=1 means FLUSH_BIGZUM_SPRITES only
; ever actually writes 12-15 - slots16-19 were genuinely dead space.
; round35 ("FlyerのスロットをC2に"): FLYER_SPR_BASE_SLOT now claims
; 16-19 as its own 2nd instance's hw slots (see its own comment) -
; if BIGZUM_SLOT_COUNT is ever raised back to 2, THIS is the collision
; to check first, not just "shrunk to save space".
BIGZUM_SPR_BASE_SLOT EQU 12      ; hw sprite slots12-15 actually used (12-19 nominally reserved, but 16-19 now belongs to Flyer - see FLYER_SPR_BASE_SLOT's own comment)
; PAT_BIGZUM/PAT_BIGZUMP/_L (bigzum_gen.py) - BASE_OFFSET=156 there,
; right after Zum's own PAT_ZUM_FLIP(152-155); 2 poses x2 facings x4
; quadrant-groups x4 sub-patterns = 64 total codes, 156-219.
BIGZUM_COLOR      EQU 13   ; from sprites/BigZum.json's own fg (same magenta as Zum)
; "足元が地面に数px めり込んでる ただ地形の上に表示するだけがなぜこう
; なるか調べて修正" - BigZum's own Y anchor directly reused TANK_TIER_Y_
; TABLE (see BIGZUM_SLOT_SIZE's own comment: "shares the tank's own 32px
; anchor convention, no offset needed") without noticing that table's
; own values are NOT a pure geometric anchor - TANK_Y_BASE's own
; derivation ("row23 top(184) - tank height(32) + landing offset(3+1)")
; bakes in a +4 fudge specifically compensating for the TANK's own
; sprite art having ~5px of blank/transparent rows at its own bottom
; (`sprites/TankF.json`: ink stops at row26 of 32, confirmed directly) -
; without that +4, the tank's own visible pixels would float a few px
; above the true ground line. BigZum's own art has NO such gap - its
; ink runs all the way to row31 (see the comment above), so reusing the
; tank's own already-compensated anchor pushes BigZum's real, un-padded
; feet that same ~4px BELOW the true ground line instead - sinking in
; by exactly the margin the tank's own fudge was adding for a padding
; gap BigZum's own art never had. Subtracted back out wherever BigZum's
; own Y is derived from TANK_TIER_Y_TABLE (UOBZ_GET_GROUND_Y - the
; single shared source for both UOBZ_TERRAIN_FOLLOW's own easing target
; and UOBZ_JUMP_MOVE's own jump-arc ground reference - and ALLOC_
; BIGZUM_SLOT's own spawn-time init).
BIGZUM_Y_OFFSET EQU 4
; "BigZumは32x32だが絵は左下24x24 コリジョンも同じでそうなってるか" -
; confirmed against both sprite JSONs directly (ink spans rows8-31,
; cols~0-24 of the 32x32 canvas for both poses) - the canvas has 8
; blank rows on top and ~8 blank columns on the right, art hugging the
; bottom-left corner. It was NOT reflected in the collision before
; this - CHECK_HIT_PAIR_BIGZUM's own bullet hit-box and every push/
; punch-contact range check (ALLOC_BIGZUM_SLOT, UOBZ_PUNCH_MOVE,
; UPDATE_TANK_BIGZUM_PUNCH) were all using the full 32x32 canvas (via
; TANK_PUSH_WIDTH/hardcoded 31) instead of the drawn art's real
; footprint. BIGZUM_COLLISION_SIZE(24, unchanged) is the box's width.
;
; "飛び越えられない原因わかった 接触状態ではパンチでノックバックされ
; 元々自機ジャンプ頂点のみなので飛び越える条件が成立しない なので
; シンプルにBigZumのコリジョンを２４ｘ１６に" - the box's HEIGHT was
; still the art's own full 24px (exactly matching the tank's own 24px
; jump peak, `JUMP_OFFSET_TABLE`), leaving zero real margin to clear it
; even once the punch-vs-jump `JUMP_ACTIVE` race was fixed - a bare tie
; between "how high the tank can jump" and "how tall the thing is"
; isn't a usable window in practice. Deliberately shrunk to 16
; (BIGZUM_COLLISION_HEIGHT) for gameplay, past what the raw art pixels
; alone would justify - a real jump now clears with 8px to spare.
; BIGZUM_COLLISION_Y_OFFSET(16, was 8) moves with it, keeping the box
; flush with the sprite's own bottom row (32-16=16) - the "physical
; standing" footprint a jump needs to clear, not literally hugging the
; ink's own topmost pixel line anymore. No X offset needed either way
; - the art's left edge already sits flush with BZ_X (col0).
BIGZUM_COLLISION_SIZE   EQU 24   ; width
BIGZUM_COLLISION_HEIGHT EQU 16   ; height - "コリジョンを24x16に"
BIGZUM_COLLISION_Y_OFFSET EQU 32-BIGZUM_COLLISION_HEIGHT
BIGZUM_SPAWNX     EQU ZUM_SPAWNX          ; same off-right-edge spawn X as Zum - "スポーン条件は同じ"
BIGZUM_PROBE_DX   EQU 16                  ; horizontal-center probe offset for a 32px-wide sprite (vs Zum's 8, for its 16px width) - still used by UOBZ_TERRAIN_FOLLOW's own per-frame probe
; round35: BIGZUM_SPAWN_COL (BIGZUM_SPAWNX+BIGZUM_PROBE_DX/8) removed -
; it only ever fed BIGZUM_TERRAIN_OK, itself removed the same round
; ("地形も仮実装だから平地条件いらない"). Unlike ZUM_SPAWN_COL, nothing
; else referenced it.
BIGZUM_HP_INIT    EQU 5    ; "合わせてBigZum耐久値5に変更" (was 8, briefly; 5 before that)
; jump arc: same half-sine construction as the tank's own JUMP_OFFSET_
; TABLE (round(H*sin(pi*t/32)) for t=0..32), just H=32 instead of 24 -
; "ジャンプは自機より高く32ｐｘ サインジャンプ". Same 33-frame duration
; as the tank's own jump (no duration was specified, only height - see
; BIGZUM_JUMP_TABLE below).
BIGZUM_JUMP_FRAMES EQU 33
BIGZUM_JUMP_XSPEED EQU ZUM_SPEED_BASE     ; horizontal travel speed while airborne, same as the ordinary approach cruise
; right-edge clamp for BigZum's own rightward chase (FACING=1, moving
; toward increasing X while circling behind or re-approaching from
; behind) - same 32px-sprite-width margin convention as the tank's own
; UTX_DO_RIGHT bound (224 = 256-32).
BIGZUM_MAX_X EQU 224
; "離れたら接近戦モードにループして" - once a punch commitment's own
; target distance grows past this, BigZum gives up and reverts to
; STATE=0 to re-detect/re-approach/re-roll from scratch, rather than
; endlessly chasing or endlessly holding a stale contact - see UOBZ_
; PUNCH_MOVE. Reuses Zum's own detection range rather than a new
; untuned number - not directly specified, an inferred choice.
BIGZUM_GIVEUP_RANGE EQU ZUM_DETECT_RANGE
; "次にBigZumが通過してパンチかジャンプかまで時間をおいてくれ" - a
; fully motionless beat right after a give-up (the tank slipping past,
; or running far enough away), before STATE=0's own approach logic
; even starts - on top of, not instead of, the ordinary ZUM_PAUSE_
; FRAMES pre-decision pause once back in near-tank range. Reuses that
; same magnitude rather than a new untuned number.
BIGZUM_GIVEUP_PAUSE_FRAMES EQU ZUM_PAUSE_FRAMES
; "BigZumが反転する場合は少し動きを止めてから反転し改めて接近モードに
; ループ ６フレとまること すぐに反転して向かってくると自機から離れ
; なくなる" (then "停止を１０フレに") - whenever STATE=0's own approach
; logic would flip FACING (BigZum's own side relative to the tank), it
; stops motionless for this many frames first instead of committing to
; the new facing and moving toward it the very same frame - see
; UOBZ_FLIP_PAUSE_MOVE.
BIGZUM_FLIP_PAUSE_FRAMES EQU 10
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
; "BigZumの上に自機が乗ったそのまま動かないとずっと乗りっぱなしなので
; 右にジャンプして振り払うように" - UPDATE_TANK_BIGZUM_STAND's own
; auto-land-on-top clamp (JUMP_LANDING_RESTART_FRAME) keeps JUMP_ACTIVE
; perpetually re-engaged while the tank stays parked, and nothing on
; BigZum's own side ever reacted to that - a player who just sits there
; could ride forever. Tracked in +6 (DY, explosion drift - fully idle
; here, only read/written during ACT=2) as a running "how many
; consecutive frames has the tank been standing on me" counter, checked
; at the very top of UPDATE_ONE_BIGZUM regardless of STATE (a 1st
; attempt scoped this to STATE=0 only and never actually fired in
; practice - "振り払いが発生しないな" - see UPDATE_ONE_BIGZUM's own
; comment for why). Once it reaches this many frames, forces STATE=1
; (jump) with a distinct "shake-off" marker in +11 (PUNCH_COOLDOWN,
; otherwise idle outside STATE=2, so this doesn't collide with its own
; real duty there) that makes the arc always move right regardless of
; the tank's own position, instead of the ordinary chase-toward-the-
; tank jump - jumping straight up while the tank sits centered on top
; wouldn't actually carry it anywhere. Originally 90 (untuned guess -
; "そのまま動かないと" didn't give a specific duration), then dropped
; to 1 ("ただ振り払いに入るのが遅いな 乗っかられたら直ぐでいい") -
; but instant-on-touch turned out to be the wrong extreme too:
; "即発火は速すぎて飛び越えも出来なくなってるから60フレくらいで" - a
; deliberate brief jump-and-land-on-top (to clear BigZum) now itself
; reads as "parked" and gets shaken off before the player can carry on,
; since even a 1-frame touch instantly meets threshold=1. 60 frames
; (~1s) gives a real jump-over enough slack to land, stand a moment,
; and move on without triggering, while still shaking off a truly
; stationary rider reasonably quickly.
BIGZUM_SHAKE_STAND_FRAMES EQU 60
; ---------- Flyer flying enemy (see UPDATE_FLYER_ALL) ----------
; test implementation, reimplemented from scratch after a full rollback
; of a previous, more ambitious round (Etank + Flyer + hit-flash all at
; once) that kept surfacing new real-hardware-only bugs faster than
; they could be pinned down - "1つずつ実装し直す". At the time this
; block was written, Etank did not exist yet - deliberately skipped
; that round ("3をスキップ") - only Flyer, singleton at the time
; (FLYER_SLOT_COUNT=1, since grown to 2 - see its own comment) and with
; its own dedicated permanent pattern allocation (no VRAM-sharing
; scheme, unlike Etank's own dynamic BigZum-pattern-sharing).
; Etank has since been reimplemented (see ETANK_SLOT_SIZE below), and
; BigZum itself restored after a diagnostic removal (see the BigZum
; entry above) once the real bug turned out to be unrelated to it.
;
; "BigZum出現時はFlyerは出ない 速度は2 右から出て画面左まで行き反転
; 自機に向かって降りてくる" - spawn gate mirrors ALLOC_ZUM_SLOT's own
; "BigZum出現中にZumは出さない" precedent (refuses while BIGZUM_POOL is
; active) - and, once the first test-implementation round showed BigZum
; and Flyer visibly coexisting anyway ("で、BigZumが同時に出てきてる"),
; made properly BIDIRECTIONAL: ALLOC_BIGZUM_SLOT also refuses to spawn
; while FLYER_POOL is active - "全ての敵はスポーン条件外はそもそも登録
; しない" (every enemy's own registration must always go through its
; real spawn gate, no exceptions) is the general principle this
; enforces. Speed is an explicit 2px/frame ("速度は2").
;
; Movement tracked in +8 PHASE: 0=cruise (straight left at a fixed
; height, normal-facing art) until it reaches the screen's own left
; edge; 1=home; 2=exit. A first attempt at PHASE=1 re-aimed at the
; tank's CURRENT position every single frame (a true heat-seeking
; track) - corrected per direct instruction: "Flyerは反転時に自機には
; 向かうが 一度方向を決定したら自機は追跡しない" - the homing DIRECTION
; is decided ONCE, at the instant of reversal (a fixed vertical step
; sign toward wherever the tank was at that moment, stashed in +6 -
; idle while alive, same "repurpose an otherwise-idle field" precedent
; as ZacoII's own E_DX/E_DY), then held constant every frame after -
; Flyer flies a straight diagonal line, not a continuously-retargeting
; missile. "自機に被らないY位置まで来たら右に消える" - once Flyer's own
; Y clears the tank's by more than FLYER_CLEAR_Y px in either
; direction (no longer visually overlapping it), PHASE advances to 2
; (exit): straight right only, ignoring the tank entirely, until off
; the right edge, then despawns.
FLYER_SLOT_SIZE  EQU 11  ; +0 ACT,+1 X,+2 Y,+3 TIMER(explosion),+4 SPRIDX,+5 DX(explosion drift)/+6 DY(explosion drift while ACT=2, locked vertical homing step while ACT=1),+7 HP,+8 PHASE(0=cruise,1=home,2=exit),+9 FACING(0=left-facing,1=right-facing/flipped),+10 FLASH_TIMER
; round35 ("FlyerのスロットをC2に" - direct instruction, found while
; investigating "全然スケジュールに従ってない"): was 1, now 2 - lets 2
; Flyer instances be alive at once, same shape as Zum's own
; FLYER_SLOT_COUNT-style pool. This means FLYER_POOL/FLYER_SPRITE_ATTRS
; grow past their old single-instance size.
FLYER_SLOT_COUNT EQU 2
; round35: relocated off the tightly-packed F2xxh block entirely rather
; than growing in place (which would have forced renumbering every
; symbol after it, all the way down through BOSS_EXPL_*/STACKTOP's own
; safety margin) - same "reuse the otherwise-completely-unused
; C000h-EEFFh region" idiom SBEAM_SPRITE_ATTRS's own comment already
; established, placed right after that block (C000h-C057h) so nothing
; else needs to move. The old F242h-F25Dh addresses are simply retired,
; not reused by anything.
FLYER_POOL         EQU 0C058h  ; FLYER_SLOT_SIZE*FLYER_SLOT_COUNT = 22 bytes (C058h-C06Dh)
FLYER_SPRITE_ATTRS EQU 0C06Eh  ; FLYER_SLOT_COUNT*16 = 32 bytes: (Y,X,pat,col)x4 per instance (C06Eh-C08Dh)
; round36-11 ("ローテーションさせる"): each F-type bullet slot needs to
; remember which of the 3 pattern variants it was drawn with, so a
; frame that redraws it later (UPDATE_ONE_BULLET) picks the same code
; instead of whatever the rotation counter has advanced to since spawn.
; The 7-byte-per-slot BULLET0/1/2_ACT struct (BULLET0_ACT=F150h,
; BULLET1_ACT=F157h - zero slack, BULLET_TEMP_BYTE sits immediately
; after at F165h) has no room to grow without renumbering the whole
; tightly-packed F1xxh RAM map that follows it, so this lives here in
; the same C000h+ free region FLYER_POOL/FLYER_SPRITE_ATTRS already
; established as the place to put new state instead - 3 standalone
; bytes, looked up by GET_BULLET_VARIANT/SET_BULLET_VARIANT comparing
; IX against BULLET0_ACT/1/2_ACT (see their own comments) rather than
; IX-relative addressing into the struct itself.
BULLET0_VARIANT EQU 0C08Eh
BULLET1_VARIANT EQU 0C08Fh
BULLET2_VARIANT EQU 0C090h
; independent rotation counters (0-2, wrapping) for F-type and U-type
; shots - "1発目水平撃ちBulletFU、2発目FM、3発目FL...斜めも同様に" reads
; as each shot TYPE cycling on its own, not a single counter shared
; between them.
BULLETF_ROT_COUNTER EQU 0C091h
BULLETU_ROT_COUNTER EQU 0C092h
; round34: FLYER_SPAWN_TIMER(F25Dh, the old pre-relocation address)
; removed - random-interval spawning is gone. round35: FLYER_POOL/
; FLYER_SPRITE_ATTRS moved away entirely (see their own comment above),
; so this whole F242h-F25Dh range is now unclaimed, not just this byte.
FLYER_DRAW_TEMP  EQU F25Eh    ; scratch byte, UOFL_DRAW's own chosen pattern base - stays put, shared scratch reused across both instances in the draw loop, doesn't need to scale with FLYER_SLOT_COUNT
FLYER_DRAW_COLOR EQU F25Fh    ; scratch byte, UOFL_DRAW's own resolved color (FLYER_COLOR or FLASH_COLOR) - same, stays put
; FLYER_DRAW_TEMP/_COLOR end at F25Fh - well clear of the 0F380h
; boundary (FLYER_POOL/FLYER_SPRITE_ATTRS themselves live at C000h+
; now, see their own comment).
; round35: was 20 (hw sprite slots20-23, 1 instance x4). Growing to
; FLYER_SLOT_COUNT=2 needs 8 contiguous hw slots - extending past 23
; into 24-27 would collide with Etank's own 24-25, and past 25 would
; eat into SBEAM_SLOT_COUNT's own hard-reserved 26-31 (see its own
; comment: "the only 6 hw sprite slots in the whole file that are NEVER
; claimed by ANY entity at all" - SBeam's line algorithm genuinely needs
; all of them during the boss fight). Moved to 16 instead, reusing
; BigZum's own reserved-but-never-actually-flushed 16-19 (see BIGZUM_
; SPR_BASE_SLOT's own comment) - this keeps the boss's own 16-quadrant
; reuse block (BOSS_SPR_BASE_SLOT(10)..+15, i.e. hw slots10-25) exactly
; intact: Zum(2)+BigZum(4 actual)+Flyer(8)+Etank(2)=16, still summing to
; the same 16 slots 10-25, still all guaranteed empty at boss spawn
; (boss_vram_safety_test.py) - and leaves Etank untouched at 24-25 and
; SBeam's own 26-31 untouched too.
FLYER_SPR_BASE_SLOT EQU 16     ; hw sprite slots16-23 (2 instances x4) - slots16-19 reused from BigZum's own idle reserve, 20-23 unchanged from before
FLYER_COLOR EQU 7              ; cyan - sprites/Flyer.json's own fg
FLYER_SPAWNX   EQU 240
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): Flyer's own Y
; used to be picked per-spawn via PICK_FLYER_SPAWN_Y (a real random roll
; in [FLYER_SPAWN_Y_MIN, FLYER_SPAWN_Y_MIN+FLYER_SPAWN_Y_SPAN) - itself
; a real bugfix earlier in this project's own history for a Y that had
; gone fixed/stuck, see git log for that whole saga). Now it comes
; straight from the schedule's own row (S2_SPAWN_Y, row*8) like every
; other free-Y type - PICK_FLYER_SPAWN_Y and its own FLYER_SPAWN_Y_MIN/
; SPAN range constants are gone; the sky/SkySand-clearance concerns
; those constants existed for are the schedule author's own
; responsibility now, same as ZacoII's own row.
FLYER_SPEED    EQU 2    ; px/frame, both cruise and homing legs - "速度は2"
FLYER_VY       EQU 1    ; px/frame vertical homing step, locked at reversal - untuned/inferred, no vertical speed was specified
FLYER_CLEAR_Y  EQU 32   ; px vertical clearance from the tank before switching to exit - untuned/inferred, matches both sprites' own 32px height ("自機に被らない" read as "no longer overlapping" in that sense)
; hard cap on how far a descending Flyer is ever allowed to sink,
; independent of the tank's own current tier - "右端に帰ってく時に地形
; に突っ込んでる 地形に入らないように". Flyer_Y+32(its own sprite
; height)=144 stays comfortably above the highest possible terrain
; ground line (160, tier0 - see TANK_GROUND_OFFSET's own ground_line=
; (20+tier)*8 derivation) with margin, even though the tank-relative
; FLYER_CLEAR_Y check alone could otherwise push a descending Flyer as
; deep as Tank_Y(156, tier3)+32=188, well past the ground - see UOFL_
; HOME_MOVE's own comment for the full story.
FLYER_DESCEND_LIMIT_Y EQU 112
FLYER_HP_INIT  EQU 4    ; carried over from the original (reverted) request's own "耐久値4", not contradicted this round
FLYER_COLLISION_SIZE EQU 32  ; full 32x32 canvas - no shrink specified

; ---------- Etank ground enemy (see UPDATE_ETANK_ALL) ----------
; reimplemented after the full rollback, per direct instruction giving
; a complete fresh spec (movement/terrain-specific details corrected
; from before the rollback; everything else - HP, collision, color,
; push mechanic - carried over from that prior (reverted, not itself
; buggy on its own) design, still visible in git history at commit
; 8f8d046):
; "ETank 右からでて左に消える 速度は2 Zumと同じで接触で自機を押す
; 坂の昇降はしないんで マップに長い平地を設置 速度２なら１２８カウン
; トで端から端まで行けるはずなので１５０の平地は欲しいな"
;
; Unlike Zum, Etank never follows terrain elevation at all: its own Y
; is set once at spawn (from TANK_TIER_Y_TABLE's own index0, the
; apex/highest tier) and never re-probed - straight horizontal line,
; "坂の昇降はしない". Originally it only ever spawned while the apex
; tier was the CURRENT surface (ETANK_TERRAIN_OK, checking IDCACHE_T0) -
; round35 removed that gate entirely ("地形も仮実装だから平地条件いらな
; い", the terrain system itself being just a placeholder), so Etank can
; now spawn regardless of what tier is actually current, and may
; visually sit above/below the real (placeholder) ground for its whole
; crossing if the apex tier isn't actually underneath it - accepted per
; explicit instruction. terrain_gen.py's own dedicated 150-tile-plus
; flat run at the apex tier (ETANK_APEX_FLAT_RUN, see its own comment
; there) predates this and is no longer load-bearing for Etank's own
; spawn gating, just still there as extra flat track.
;
; Collision is 24(W)x16(H), anchored at the bottom-left of the 32x32
; canvas ("キャラ位置は32x32の内左下24x16" - the raw art itself only
; occupies that same bottom-left region, confirmed directly against
; sprites/Etank.json: rows0-15 and cols24-31 are fully blank), so only
; the BL/BR quadrant hw sprites are ever drawn - TL/TR stay hidden
; permanently, same "don't allocate hw sprites for a permanently-blank
; quadrant" precedent as nothing else in this file needed until now.
;
; "BigZumもEtankも出現しない...VDPのスプライト操作でミスがあるはず" -
; BigZum was removed entirely as a diagnostic isolation step for one
; round ("BigZumのコードは全て一旦削除 変わりにEtankと差し替えてEtank
; 周りが正常動作するか確認する") to rule out any interaction with its
; own code, giving Etank a permanent pattern allocation in the range
; BigZum's own 64 codes used to occupy - the ghost persisted even with
; only Etank active, and the real cause turned out to be unrelated to
; either entity (see STACKTOP's own comment: the stack itself had too
; little headroom below it, corrupting whichever scratch RAM happened
; to sit closest). With BigZum now restored ("BigZumがでないままに
; なってるからもとに戻せ"), the pattern-code budget is tight again, so
; Etank goes back to its ORIGINAL design: dynamically sharing BigZum's
; own PAT_BIGZUM BL/BR pattern-VRAM groups at spawn time (ALLOC_ETANK_
; SLOT), restored whenever BigZum itself next spawns (ALLOC_BIGZUM_
; SLOT's own reload). At the time this was written, that sharing was
; safe ONLY because the 2 were spawn-gated bidirectionally exclusive
; (both ALLOC routines checked the other's pool - "EtankとBigZumは同時
; には存在しない"). **This is no longer true** - round34-2 ("排他制御
; は削除") removed that mutual check per explicit instruction, and
; round34-3 confirmed neither ALLOC_BIGZUM_SLOT nor ALLOC_ETANK_SLOT
; references the other's pool any more. A BigZum and an Etank CAN be
; alive at the same time now; if that ever visibly corrupts either
; one's BL/BR quadrant art, the real fix is giving Etank its own
; dedicated pattern codes instead of borrowing BigZum's, not re-adding
; a hardcoded exclusion - pacing/spacing between them is the schedule
; editor's own job now, not this file's ("排他制御はあくまで仮実装の
; 仕様 これはエディットでコントロールするんで要らない").
;
; HP10 ("耐久値10"), omnidirectional bullet damage (no front/rear
; invulnerability rule like Zum - nothing about facing/direction was
; specified for Etank), dark red color (6, not sprites/Etank.json's
; own fg), Zum-style continuous push while in contact ("Zumと同じで
; 接触で自機を押す" - same UPDATE_TANK_ZUM_PUSH shape/speed, suspended
; entirely while JUMP_ACTIVE so the box stays cleanly jumpable).
; Despawns once it reaches the left edge ("左に消える").
ETANK_SLOT_SIZE  EQU 8   ; +0 ACT,+1 X,+2 Y(fixed at spawn, never re-probed),+3 TIMER(explosion),+4/+5 DX/DY(explosion drift),+6 HP,+7 FLASH_TIMER
ETANK_SLOT_COUNT EQU 1
; strictly below the real 0F380h MSX BIOS-work-area boundary (see
; STACKTOP's own comment).
ETANK_POOL         EQU F260h  ; ETANK_SLOT_SIZE*ETANK_SLOT_COUNT = 8 bytes
ETANK_SPRITE_ATTRS EQU F268h  ; ETANK_SLOT_COUNT*8 = 8 bytes: (Y,X,pat,col)x2 - BL/BR only, TL/TR always hidden
; round34: ETANK_SPAWN_TIMER(F270h) removed - random-interval spawning
; is gone, this byte is simply unused now.
; ASCII16 bank-switch RAM trampoline (see INIT's own comment) - 4 bytes
; ("LD (DE),A"=3, "JP (HL)"=1), same real-hardware-confirmed idea as
; bankswitch_poc's own F100h (SPRITE_ATTRS already owns that address
; in this file, so a different free gap is used here).
BANKSWITCH_TRAMPOLINE_RAM EQU F271h
; scratch byte, UOET_DRAW's own resolved color (ETANK_COLOR or
; FLASH_COLOR) - its own byte rather than reusing BIGZUM_DRAW_COLOR
; (as before the diagnostic round) since RAM is no longer the tight
; resource pattern-code space still is, and a dedicated byte removes
; any "never runs interleaved" assumption between the two. Still well
; under the real 0F380h BIOS-work-area boundary.
ETANK_DRAW_COLOR EQU F275h
; night-transition state (see NIGHT_START_TICK's own comment). NIGHT_ROW
; is 0 before the effect starts, then the current leading (striped) row
; NIGHT_START_ROW-NIGHT_END_ROW; once it reaches NIGHT_END_ROW, done.
; NIGHT_NEXT_TICK (2 bytes, 16-bit like GAME_TICK itself) is the next
; GAME_TICK value that advances it, starting at NIGHT_START_TICK.
NIGHT_ROW        EQU F276h
NIGHT_NEXT_TICK  EQU F277h   ; 2 bytes
; boss (Sasapi) state - see BOSS_SPAWN_TICK's own comment. BOSS_ACT:
; 0=not spawned yet, 1=active (patrolling - no exploding/dead state this
; round). BOSS_DIR: 0=moving left (X decreasing), 1=moving right.
; BOSS_SPRITE_ATTRS is the 16-quadrant staging buffer FLUSH_BOSS_SPRITES
; blasts to the real hw sprite table, same staging-then-flush shape as
; every other enemy's own *_SPRITE_ATTRS - still well under the real
; 0F380h BIOS-work-area boundary (see STACKTOP's own comment).
BOSS_ACT           EQU F279h
BOSS_X             EQU F27Ah
BOSS_DIR           EQU F27Bh
BOSS_HP            EQU F27Ch
BOSS_SPRITE_ATTRS  EQU F27Dh   ; 16 quadrants x4 bytes (Y,X,pat,col) = 64 bytes
BOSS_FLASH_TIMER   EQU F2BDh   ; hit-flash countdown, same FLASH_DURATION-driven mechanism as every other HP-bearing entity's own flash timer
BOSS_DRAW_COLOR    EQU F2BEh   ; scratch byte, DRAW_BOSS's own resolved color (BOSS_COLOR or BOSS_FLASH_COLOR) - feeds all 16 quadrant writes so the timer only ticks down once per frame, not 16 times
BOSS_PHASE          EQU F2BFh  ; 0=patrolling(hw sprite), 1=parked in the attack pose(BG art) - "移動中はスプライト 停止中はBGて切り替え", 2=left-edge pause (round9, see UBA_LEFT_PAUSE) - stationary sprite, not the BG pose
BOSS_POSE_END_TICK  EQU F2C0h  ; 2 bytes - GAME_TICK value the pose ends at (GAME_TICK+BOSS_POSE_TICKS, captured once at pose-entry), compared via true 16-bit SBC HL,DE every frame while BOSS_PHASE=1, same idiom as every other GAME_TICK threshold in this file (BOSS_SPAWN_TICK/NIGHT_START_TICK/etc.)

; ---------- homing missile (4-instance pool, fired as a volley once ----------
; ---------- per attack pose) ----------
; "ホーミングミサイルを実装 ボスポーズでボス右上あたりから発射し X軸
; 中央辺りまで水平打ち その後ホーミング動作...同時に4発は欲しい".
; A real hw sprite pool now (see PAT_HORMING_SL's own comment for why -
; BG's own column-granular movement was too choppy at any speed fast
; enough to be threatening). Real pixel coordinates (X/Y), not COL/ROW
; cells - the whole reason for switching to a hw sprite was smooth,
; fast, non-choppy movement, so cell-snapped position would defeat the
; point.
; round 3: the straight-then-homing flight above was replaced by the
; user with a 3-phase flight and intermittent (not simultaneous) firing
; - "まず発射方法 ボスに被らない位置の右上 今の発射位置の16px上あたり
; 次に最初は左斜上に32px移動 その後はXは左端64pxから右72pxの範囲でラ
; ンダムに水平移動 その後ホーミング 弾は4発同時発射ではなく間欠で4発
; 発射 で方向を変える時は45度まで 自機のY位置以上で一致したら水平に
; 自機へホーミング". See UPDATE_ONE_HORMING's own comment for the full
; state machine.
HORMING_SLOT_COUNT EQU 4
HORMING_SLOT_SIZE  EQU 7   ; +0 ACT,+1 X,+2 Y,+3 FACING(cosmetic,eased 45 deg/step: 0=SL,1=DL,2=Down,3=DR,4=SR),+4 STATE(0=rise,1=wander,2=homing),+5 RISE_REMAIN,+6 TARGET_X (round4: the ONE random X picked at rise-completion - see PICK_HORMING_TARGET_X)
HORMING_POOL EQU F2C2h   ; 4 slots x7 bytes = 28 bytes
HORMING_SPRITE_ATTRS EQU F2DEh   ; 4 slots x4 bytes (Y,X,pattern,color), staged same as ENEMY_SPRITE_ATTRS
HORMING_VOLLEY_COUNT EQU F2EEh   ; how many of this pose's 4 have launched so far - see UPDATE_HORMING_VOLLEY
HORMING_VOLLEY_TIMER EQU F2EFh   ; raw frames remaining until the next intermittent launch
; round36-12 ("ホーミングは弾数を増やす 今はスプライトのみだがBGも合わ
; せて使用する 4発追加"): a SECOND, parallel 4-instance pool, BG-cell
; drawn instead of hw-sprite - not just "4 more of the same". Both hw
; sprite pattern-code budget (PAT_HORMING_SL's own comment: reuses
; Flyer's whole 32-code block, only 12 codes spare - not enough for a
; 2nd full 5-facing set) AND hw sprite ATTRIBUTE slot budget (all 32
; already accounted for during the boss fight: body16+SBeam's own hard
; 26-31+tank/enemy-pool/bullet/current-Horming's shared 0-9 - confirmed
; zero free slots) were audited and found fully exhausted - see
; HANDOFF.md round36-12 for the numbers. This directly contradicts
; horming_gen.py's own documented history ("BGでは...動きがガタガタで
; 速すぎるんだよ スプライト必須" - BG was tried once, rejected, redone
; as sprites) - confirmed directly with the user this round that the
; NEW 4 should go BG anyway, given sprite capacity is genuinely gone;
; the ORIGINAL 4 (HORMING_POOL/HORMING_SLOT_COUNT above) are completely
; untouched, still hw-sprite, still smooth. Same 7-byte struct layout
; as HORMING_POOL (UPDATE_ONE_HORMING itself is fully generic over IX,
; reused as-is for both pools) but a SEPARATE array, not a grown
; HORMING_POOL - the F2xxh region above is packed with zero slack
; (HORMING_VOLLEY_TIMER sits immediately after with nothing spare), so
; this lives in the C000h+ free region instead, same precedent as
; round35's own FLYER_POOL relocation and round36-11's own BULLET0/1/2_
; VARIANT bytes.
HORMING_BG_SLOT_COUNT EQU 4
HORMING_BG_SLOT_SIZE  EQU 7   ; same field layout as HORMING_SLOT_SIZE
HORMING_BG_POOL EQU 0C093h   ; 4 slots x7 bytes = 28 bytes (C093h-C0AEh)
; "4発追加" doubles the total launched per pose/volley from 4 to 8 - one
; missile into EACH pool (sprite+BG) per intermittent tick (round36-13,
; see UPDATE_HORMING_VOLLEY's own comment for why simultaneous, not
; sequential blocks) - 4 ticks x2 missiles = 8 total, same
; HORMING_VOLLEY_INTERVAL cadence as before.
; round36-14 Part C: boss form-change state - see BOSS_FORM's own EQU
; comment. Lives here (C000h+) rather than the dedicated F314h-F320h
; boss-explosion RAM block since that block is already sized to leave
; exactly STACK_SAFETY_MARGIN below STACKTOP with nothing spare (see its
; own comment) - same "pick the C000h+ free region instead of squeezing
; the packed F2xx/F3xx block" precedent as HORMING_BG_POOL itself.
BOSS_FORM EQU 0C0AFh
; which sequence armed the shared SPARK sub-state machine (BOSS_EXPL_
; STATE/_TIMER/_SLOTn) - 0=a real death (INIT_BOSS_EXPLOSION, chains into
; GROW once the burst ends), 1=this round's HP<=200 transition
; (TRIGGER_BOSS_BROKEN_FORM, chains into REVEAL_BOSS_BROKEN_FORM instead
; - see UBS_LAST_FRAME). The two can never run concurrently (one is only
; ever armed while BOSS_ACT=2, the other only while BOSS_ACT=1), so
; sharing the same SPARK state bytes for both is safe.
BOSS_EXPL_REASON EQU 0C0B0h
BOSS_BROKEN_SPRITE_ATTRS EQU 0C0B1h   ; 4 quadrants x4 bytes (Y,X,pat,col) = 16 bytes (C0B1h-C0C0h), same staging-then-flush shape as BOSS_SPRITE_ATTRS
BOSS_BROKEN_DIR EQU 0C0C3h            ; last-loaded facing (0=SASAPI_BROKEN_QUADS,1=_L, same convention as BOSS_DIR) - reload the 128-byte pattern only when this actually changes, same "reload on change only" idiom as LOAD_SASAPI_PATTERNS itself. 0FFh sentinel forces the very first UPDATE_BOSS_BROKEN_ACTIVE frame to load regardless.
BOSS_BROKEN_MOVING EQU 0C0C4h         ; 0=stopped(frozen at the current path point),1=drifting - see UPDATE_BOSS_BROKEN_ACTIVE
BOSS_BROKEN_PATH_INDEX EQU 0C0C5h     ; 0..BOSS_BROKEN_PATH_LEN-1, only advances while MOVING - position/facing are always re-derived from this same index, so a stop-then-resume continues from exactly where it left off rather than jumping
BOSS_BROKEN_FRAME_COUNTER EQU 0C0C6h  ; 0..BOSS_BROKEN_PATH_HOLD_FRAMES-1, counts raw frames between path-index steps while MOVING
; round36-14 follow-up #2 ("インフィニティ軌道はその位置から始まるが一旦
; 中央に寄せろ センタリングするかたちで 今だと端で倒すと画面半分の狭い
; 起動で動いてしまってる") - round36-14 follow-up #1 had the figure-8
; loop orbit around wherever the boss actually died (clamped so it never
; left the screen), which is exactly what produced this complaint: dying
; near an edge clamped the loop's own center near that edge too, so the
; visible loop was lopsided/cramped against the edge instead of using the
; screen's own full width. Fixed by splitting into 2 sub-phases instead:
; 1) RECENTERING - the body appears exactly where the old one died (still
; correct - "その位置から始まる"), then walks toward a FIXED screen-
; center point (BOSS_BROKEN_CENTER_X/Y, sasapi_gen.py) at BOSS_BROKEN_
; RECENTER_SPEED px/frame ("一旦中央に寄せろ センタリングするかたちで").
; 2) once arrived, the orbit itself resumes being ABSOLUTE, centered on
; that same fixed point (BOSS_BROKEN_PATH_X/_Y, back to sasapi_gen.py's
; original absolute-coordinate table shape, just with a fixed center
; instead of one derived from wherever the boss happened to die) - always
; the same full-amplitude loop regardless of death position, never
; clamped/narrowed. BOSS_BROKEN_RECENTERING=1 selects sub-phase 1;
; UPDATE_BOSS_BROKEN_ACTIVE clears it exactly once, at the moment BOSS_X/
; BOSS_Y both reach the center exactly, and starts the orbit at BOSS_
; BROKEN_PATH_CROSS_INDEX (the loop's own (0,0)-offset crossing point,
; sasapi_gen.py) so there's no visual jump at the handoff. No more per-
; death ORIGIN capture/clamp needed - see TRIGGER_BOSS_BROKEN_FORM's own
; comment for why BOSS_X/BOSS_Y already hold the right starting point for
; free, with nothing new to capture.
BOSS_BROKEN_RECENTERING EQU 0C0C7h    ; 1=still walking toward BOSS_BROKEN_CENTER_X/Y, 0=orbiting
BOSS_BROKEN_RECENTER_SPEED EQU 2      ; px/frame while recentering, same pace as the old body's own BOSS_SPEED
; round36-14 follow-up #3 ("形態変化後に64x64のコリジョンのままになって
; る 32x32になるよう修正") - CHECK_HIT_PAIR_BOSS's own AABB half-width
; needs to shrink to match the real 32x32 broken body; see that routine's
; own comment for how (a runtime-computed scratch byte, since the size is
; now conditional on BOSS_FORM rather than a single compile-time EQU).
CHPB_SIZE_SCRATCH EQU 0C0C8h
; round36-14 follow-up #4 ("SasapiBrokenの停止はインフィニティ軌道の1周
; に１回何処かで停止 で、停止中にビーム攻撃をする") - replaces the old
; GAME_TICK-random-duration MOVING/STOPPED cycle (BOSS_BROKEN_PHASE_
; END_TICK, removed) with a step-counted one: BOSS_BROKEN_STEPS_TO_STOP
; decrements once per path-index advance while MOVING (not per raw
; frame), so "stop once per lap" is tied directly to how far around the
; loop the body has actually traveled, not wall-clock time - reaching 0
; stops it and arms the 4-beam sequence below. Re-rolled (see ROLL_
; BOSS_BROKEN_LAP_STEPS) once the sequence finishes and movement resumes.
BOSS_BROKEN_STEPS_TO_STOP EQU 0C0C9h
; the 4-beam sequence itself, per-frame timer/counter idiom copied
; directly from UPDATE_HORMING_VOLLEY's own COUNT/TIMER pair (see ARM_
; BOSS_BROKEN_BEAM_SEQ/UPDATE_BOSS_BROKEN_BEAM_SEQ). COUNT reaching 4
; (all fired) plus one more TIMER-gated wait is what ends the stop and
; resumes movement.
BOSS_BROKEN_BEAM_COUNT EQU 0C0CAh
BOSS_BROKEN_BEAM_TIMER EQU 0C0CBh
; round36-14 follow-up#4 3rd real-hardware feedback ("ビームが飛んで
; 来ないな...今はボスの上に表示されてるだけ それで何の攻撃になる 発射
; して飛ばすんだよ"): the 2nd attempt (a single static hw sprite parked
; next to the body, "繋げる必要はない" mis-read as "doesn't need to
; move") never actually traveled - fixed by making each fired beam a
; genuine moving projectile (see BOSS_BROKEN_PROJ_* below and LAUNCH_
; BOSS_BROKEN_BEAM/UPDATE_BOSS_BROKEN_BEAM_FLIGHT), independent of the
; other 3 once launched. BOSS_BROKEN_BEAM_POINT_COUNT (the old single-
; slot "is a beam shown" flag) is gone, unused now that each of the 4
; slots tracks its own BOSS_BROKEN_PROJ_ACTIVE.
; 4 independent in-flight projectile slots (struct-of-arrays: index i
; is beam-type i's own instance, 0-3) - up to all 4 can be flying at
; once, since the firing SEQUENCE (1->4, BOSS_BROKEN_BEAM_INTERVAL
; apart) no longer waits for the previous one to finish before firing
; the next ("発射タイミングは今でいいが" - kept unchanged).
BOSS_BROKEN_PROJ_ACTIVE EQU 0C0CCh   ; 0/1 x4 (C0CCh-C0CFh)
BOSS_BROKEN_PROJ_X      EQU 0C0D0h   ; pixel X (top-left of the 16x16 sprite) x4 (C0D0h-C0D3h)
BOSS_BROKEN_PROJ_Y      EQU 0C0D4h   ; pixel Y x4 (C0D4h-C0D7h)
BOSS_BROKEN_PROJ_DX     EQU 0C0D8h   ; signed per-frame X velocity (px/frame) x4 (C0D8h-C0DBh)
BOSS_BROKEN_PROJ_DY     EQU 0C0DCh   ; per-frame Y velocity (px/frame, always positive - all 4 beams point down) x4 (C0DCh-C0DFh)
BOSS_BROKEN_PROJ_CODE   EQU 0C0E0h   ; this instance's own hw sprite pattern code x4 (C0E0h-C0E3h)
; hw sprite staging buffer, 1 per in-flight slot (BOSS_BROKEN_BEAM_
; SLOT_COUNT(4)*4 = 16 bytes) - same staging-then-flush shape as every
; other hw sprite pool in this file.
BOSS_BROKEN_BEAM_SPRITE_ATTRS EQU 0C0E4h
; UPDATE_BOSS_BROKEN_BEAM_FLIGHT's own loop-index scratch (0-3) - always
; re-read fresh before every PROJ_* array access rather than mutated in
; a register across the whole routine, see that routine's own comment.
UBBBF_SLOT EQU 0C0F4h
; Thunder's own state - a real POOL now (round9 fix: "いつからサンダー
; は1本しか出せない仕様に? そんな指示はしてねえぞ...BGを使ってるのは
; 表示制限がないからだろが" - BG has no hw-sprite-style display limit,
; so multiple columns can and should coexist, same idea as the terrain-
; scroller's own always-on redraw having no slot budget at all).
THUNDER_SLOT_SIZE  EQU 4    ; +0 ACT(0=inactive,1=growing,2=shrinking),+1 COL,+2 ROW(grow/shrink frontier),+3 DEEP_ROW(deepest row reached - valid once shrinking; see UPDATE_ONE_THUNDER)
THUNDER_SLOT_COUNT EQU 4
THUNDER_POOL EQU F2F0h   ; THUNDER_SLOT_SIZE*THUNDER_SLOT_COUNT = 16 bytes (F2F0h-F2FFh)
; per-boss-leg trigger tracking - "ボスが横に32px移動毎に発射" - repeats
; for the whole leg, not just once, and (round9) no longer gated on any
; previous column finishing first - see CHECK_THUNDER_TRIGGER_LEFT/_
; RIGHT's own comment.
THUNDER_PENDING       EQU F300h   ; 1=this leg is eligible/armed (stays 1 the whole leg); 0=not armed at all - see THUNDER_ELIGIBLE
THUNDER_ELIGIBLE      EQU F301h   ; 0 until the first attack pose ever completes, then permanently 1 - "ホーミング攻撃後" gates Thunder off entirely during the boss's own pre-first-pose patrol legs
THUNDER_LEG_START_X   EQU F302h   ; BOSS_X captured at the start of the current leg (pose-end for the leftward leg, left-edge reversal for the rightward leg)
; scratch record shaped to match ERASE_BULLET_CELL's own IX+2(COL)/+3
; (ROW)/+4(ADDR_LO)/+5(ADDR_HI) field expectations, reused as-is so
; Thunder's own erase gets the exact same background-aware restore
; (sky/skysand/rock) bullets already have, instead of a hand-rolled
; duplicate - see ERASE_ONE_THUNDER_ROW's own comment. +0/+1 unused
; (ERASE_BULLET_CELL never reads them). Shared/reused across every
; slot's own erase calls (safe - erases happen synchronously, one cell
; at a time, never interleaved across slots within a single call).
THUNDER_ERASE_BASE    EQU F303h   ; +2=COL,+3=ROW,+4=ADDR_LO,+5=ADDR_HI (6 bytes, F303h-F308h)
; transient scratch pair for the contested-row (>=20) reassertion pass -
; see UOT_REASSERT_GROW/_SHRINK/UOT_MAYBE_DRAW's own comments. Reloaded
; fresh before each of the (at most 4) row checks since DRAW_ONE_
; THUNDER_ROW's own NIGHT_ROW_ADDR call trashes DE - only 1 slot is
; ever being reasserted at a time, no reentrancy risk.
THUNDER_VIS_LOW  EQU F309h
THUNDER_VIS_HIGH EQU F30Ah
; "左端は2Tick停止してから反転発射に" (round9) - GAME_TICK value the
; left-edge pause ends at, same 2-byte/true-16-bit-compare shape as
; BOSS_POSE_END_TICK.
BOSS_LEFT_PAUSE_END_TICK EQU F30Bh
; "左斜下8px移動してから水平移動に変更 戻る時は逆に..." (round11) - the
; boss's own real, DYNAMIC current Y - was a fixed BOSS_SPAWN_Y constant
; everywhere until now (horizontal-only patrol); DRAW_BOSS and the
; collision box both need to read this instead now. Always resets to
; BOSS_SPAWN_Y exactly at spawn and again the instant the diagonal rise
; completes (right before entering the pose).
BOSS_Y EQU F30Dh
; persists across the whole boss fight (only reset at spawn) - "ホーミ
; ングとサンダー2セット終わったら" - counts completed pose cycles so
; SBeam knows when it's eligible (see SBEAM_POSE_GATE).
BOSS_POSE_COUNT EQU F30Eh
; SBeam's own single-instance state (only one beam ever active at a
; time - fired once per eligible pose).
SBEAM_ACT       EQU F30Fh   ; 0=inactive,1=dropping(vertical, from the hand),2=sweeping left(horizontal),3=retracting(horizontal, back toward SBEAM_START_COL)
SBEAM_ROWS      EQU F310h   ; drop phase: how many vertical segments drawn so far
SBEAM_GROUND_Y  EQU F311h   ; drop phase target / sweep+retract's own fixed Y (pixel), computed once when the drop starts
SBEAM_FRONT_COL EQU F312h   ; sweep/retract phase: the beam's own current leading-edge column (decreases while sweeping, increases while retracting)
SBEAM_BLINK     EQU F313h   ; toggled every frame - "点滅で表示で 取り敢えず1フレ点滅で"

; boss death/explosion sequence state - F314h-F320h (13 bytes), the free
; gap right after SBEAM_BLINK, kept deliberately lean so the highest
; byte used still leaves the STACK_SAFETY_MARGIN(0x60)
; `tests/stack_safety_test.py` requires below STACKTOP(F380h).
BOSS_EXPL_STATE   EQU F314h   ; BOSS_EXPL_STATE_GROW/_SHRINK/_FLASH/_DONE
BOSS_EXPL_RADIUS  EQU F315h   ; current circle radius, cells (0=just the center cell .. BOSS_EXPL_MAXR)
BOSS_EXPL_TIMER   EQU F316h   ; frames until the next radius step (grow/shrink) or the final-flash countdown
BOSS_EXPL_CX      EQU F317h   ; center cell column, captured once at death (BOSS_X stops being meaningful once hidden)
BOSS_EXPL_CY      EQU F318h   ; center cell row, captured once at death
BOSS_EXPL_BLINK   EQU F319h   ; 0..BOSS_EXPL_BLINK_PERIOD-1 cycling counter, boss-sprite blink (grow) and final-cell blink (flash)
BOSS_EXPL_ROWTMP  EQU F31Ah   ; BOSS_EXPL_APPLY_RING's own current cell's absolute row, unsigned-wraps if negative (caught by the same CP 24/JP NC clip as a real >=24 row)
BOSS_EXPL_COLTMP  EQU F31Bh   ; same, current absolute column
BOSS_EXPL_RING_MODE   EQU F31Ch   ; BOSS_EXPL_APPLY_RING's own mode: 0=draw white(GROW), 1=restore true background(SHRINK)
BOSS_EXPL_RING_RADIUS EQU F31Dh   ; which radius's own ring table entry to walk (0-6)
BOSS_EXPL_RING_REMAIN EQU F31Eh   ; cells left to process in the current ring walk
BOSS_EXPL_RING_PTR    EQU F31Fh   ; 2 bytes - current read position in BOSS_EXPL_RING_DATA
; round32 follow-up #2: SPARK's own 3 live-spark "slots" (row,col pairs,
; one per BOSS_EXPL_SPARK_PER_FRAME spark) - remembers exactly where each
; currently-live spark sits so UBE_SPARK can erase precisely those cells
; next frame instead of sweeping the whole scatter box (see BOSS_EXPL_
; ORIGIN_RANGE's own comment for why that matters at this box size).
; Reuses the SAME GROW/SHRINK-only ring-walk bytes above (RADIUS/RING_
; MODE/RING_RADIUS/RING_REMAIN/RING_PTR) - all genuinely idle throughout
; SPARK (GROW hasn't started yet), and every one gets explicitly
; re-initialized for its OWN GROW-phase meaning at the SPARK->GROW
; handoff (see UBS_LAST_FRAME), strictly AFTER this phase is done reading
; them as slot storage - no new persistent bytes needed for this either.
; A row byte of 0FFh is the "nothing live yet" sentinel (valid rows are
; 0-23) - set once by INIT_BOSS_EXPLOSION so the very first frame doesn't
; try to erase stale/garbage data from a previous fight.
BOSS_EXPL_SPARK_SLOT0_ROW EQU BOSS_EXPL_RADIUS
BOSS_EXPL_SPARK_SLOT0_COL EQU BOSS_EXPL_RING_MODE
BOSS_EXPL_SPARK_SLOT1_ROW EQU BOSS_EXPL_RING_RADIUS
BOSS_EXPL_SPARK_SLOT1_COL EQU BOSS_EXPL_RING_REMAIN
BOSS_EXPL_SPARK_SLOT2_ROW EQU BOSS_EXPL_RING_PTR
BOSS_EXPL_SPARK_SLOT2_COL EQU BOSS_EXPL_RING_PTR+1

; staging buffer for SBEAM_SLOT_COUNT*4 hw sprite slots (4 bytes each:
; Y,X,pattern,color), same shape as HORMING_SPRITE_ATTRS - flushed via
; FLUSH_SBEAM_SPRITES.
; "スタックが溢れてないかチェック" - relocated away from F314h (only
; 20 bytes below STACKTOP=F380h, F314h-F36Bh) after a direct per-
; instruction SP trace (z80emu.py, active input, through boss spawn)
; found real nested CALLs alone (no interrupts simulated) already
; dipping SP to F36Ah - INSIDE this array's own last byte (F36Bh). This
; is exactly the same class of bug an earlier round already fixed once
; (see STACKTOP's own comment: "shifting every OTHER RAM address...
; down by 100h...256+ bytes of genuinely free headroom") - SBeam's own
; block was added later and never respected that same margin. Moved to
; C000h, deep in the otherwise-completely-unused C000h-EEFFh region
; (nothing else in this file uses any address below EF00h), well clear
; of STACKTOP regardless of how much deeper a real interrupt handler's
; own stack usage (never simulated by this test harness at all) might
; push things beyond what could be measured here.
SBEAM_SPRITE_ATTRS EQU 0C000h   ; SBEAM_SLOT_COUNT*4 = 88 bytes (C000h-C057h)
; scratch bytes for STAGE_SBEAM's own Bresenham line algorithm (round3 -
; "複数本じゃなく1本だぞ", one real diagonal line from the fixed origin
; to the moving tip, not 2 fixed-shape arms) - all in 8px-grid units
; (columns/rows), recomputed fresh every frame, never read outside
; STAGE_SBEAM itself, EXCEPT SBEAM_TRIP (round4, must persist across
; many frames - see its own comment).
; round4 bug (real, found from a live report): these originally lived at
; F36Ch-F373h, only 13 bytes below STACKTOP(F380h) - close enough that
; ordinary deep CALL/PUSH nesting elsewhere in the game (Thunder's own
; multi-level draw chain, unrelated to SBeam) silently overwrote them as
; real stack usage. SBEAM_TRIP specifically needs to SURVIVE across many
; unrelated frames (Thunder can easily fire in between), so it was
; getting clobbered to garbage well before SBeam ever read it again -
; confirmed by directly tracing writes to F373h in a real MAINLOOP run
; and finding it repeatedly overwritten (with SBEAM_ACT=0 the whole
; time, i.e. genuinely nothing SBeam-related running) while Thunder was
; active. The other SBEAM_LINE_* scratch bytes are transient (written
; and consumed within the same STAGE_SBEAM call, no other code runs
; between the two, so proximity to the stack never actually mattered for
; them) but moved along anyway for a uniform, comfortably-clear-of-the-
; stack home in the TANK_LIFE/DASH block's own free gap instead.
SBEAM_LINE_TX   EQU F132h   ; target (tip) column
SBEAM_LINE_TY   EQU F133h   ; target (tip) row
SBEAM_LINE_DX   EQU F134h   ; SBEAM_START_COL - TX (>=0)
SBEAM_LINE_DY   EQU F135h   ; TY - SBEAM_START_ROW (>=0)
SBEAM_LINE_ERR  EQU F136h   ; Bresenham error accumulator
SBEAM_LINE_X    EQU F137h   ; walking cursor column (starts at the origin)
SBEAM_LINE_Y    EQU F138h   ; walking cursor row (starts at the origin)
SBEAM_TRIP      EQU F139h   ; how many full sweep+retract round trips completed so far this pose - see SBEAM_TRIP_COUNT

; "ボスに被らない位置の右上 今の発射位置の16px上あたり" - same X as
; before (still within the boss's own 64x64 box's own column range,
; X192-255), Y raised 16px from the previous round's 64 so it clears the
; box's own top edge (Y56) instead of spawning inside the hand art.
HORMING_SPAWN_X EQU 232
HORMING_SPAWN_Y EQU 48
; px/frame, flat per-axis (not a normalized diagonal distance) - "速度
; 3に" (round6: was 4/round5's "2倍に", before that 2, matching BOSS_
; SPEED/FLYER_SPEED/ETANK_SPEED's own "速度は2" convention - the
; missile is the only one of these tuned away from 2). Odd, unlike
; every previous value here - the snap-when-close logic in UOH_WANDER
; and the >=-not-exact-match trigger in UOH_H2_TRIGGER were both
; already written to handle an arbitrary HORMING_SPEED/parity, not just
; even values, so this needed no other code changes.
HORMING_SPEED EQU 3
; "最初は左斜上に32px移動" - state0's own fixed diagonal rise, tracked
; as a per-slot countdown (RISE_REMAIN) rather than a fixed frame count,
; so it stays exact regardless of HORMING_SPEED.
HORMING_RISE_DIST EQU 32
; "Xは左端64pxから右72pxの範囲でランダムに水平移動" - read as an
; ABSOLUTE screen-relative window (not relative to the missile's own
; spawn/rise-end X): 64px from the screen's own left edge, and 72px from
; the screen's own right edge (256-72=184) - INFERRED reading of an
; ambiguous phrase; the alternative (a window relative to wherever the
; rise phase ends) would put the right bound past X255 given this
; boss's own spawn X, which can't be right, so the absolute-screen
; reading was chosen. Flag for correction if this isn't what's meant.
HORMING_WANDER_MIN_X EQU 64
HORMING_WANDER_MAX_X EQU 184
; window width, used by PICK_HORMING_TARGET_X's own range-fold.
HORMING_WANDER_WIDTH EQU HORMING_WANDER_MAX_X-HORMING_WANDER_MIN_X+1
; off-screen bail-out, X side - 256px-wide screen minus the sprite's own
; 8px width, same "screen_dim - 8" convention used elsewhere in this
; file. (No Y-side equivalent any more - round5 removed state2's own
; HORMING_MAXY bail-out entirely, see UOH_H2_STEP_DOWN's own comment;
; nothing else in this feature ever moves Y downward without also being
; bounded by UOH_H2_TRIGGER first.)
HORMING_MAXX EQU 248
; "まず自機のコリジョンは32x32ではなく16x16pxに ただし絵の問題で左下
; 16x16ではなくYが2pxオフセットされた16x16に変更 多分地形や乗っかりで
; ズレるんで再調整" - shrinks the tank's own real damage hitbox (used by
; every enemy-vs-tank AABB check: Homing/Thunder/SBeam) from the full
; 32x32 sprite box down to 16x16. Width/X unchanged from "左下" (left-
; aligned, X_OFFSET=0); TANK_COLLISION_Y_OFFSET is a genuine INFERENCE -
; "bottom-left" alone would put it flush at the sprite's own bottom edge
; (32-16=16), but the user explicitly said NOT that, offset by 2px
; instead, without saying which direction. Guessed UP (14, 2px shy of
; flush-bottom) since a hitbox sitting exactly flush with the sprite's
; own bottom edge is the more common source of "misaligned on terrain/
; standing" clipping the user is already anticipating - flag/flip this
; if it turns out backwards.
TANK_COLLISION_WIDTH    EQU 16
TANK_COLLISION_HEIGHT   EQU 16
TANK_COLLISION_X_OFFSET EQU 0
TANK_COLLISION_Y_OFFSET EQU 14
; "弾は4発同時発射ではなく間欠で4発発射" - raw frames between each of
; the 4 launches (magnitude not specified by the user - inferred/
; tunable; the whole pose lasts BOSS_POSE_TICKS(32)*8=256 raw frames, so
; 24 spreads all 4 shots across the first third of it, leaving the rest
; of the pose for them to actually fly).
HORMING_VOLLEY_INTERVAL EQU 24
; round4: state2 (after the wander's own random-X arrival) is real 2D
; pursuit again, restored from the very first spec message - "自機のX
; との距離が自機幅より外にある時は斜めのミサイルへ Downは自機幅内に
; 収まっている時 SL、SRは自機から64px以上Xが離れている時 自機より右方
; 向に離れている時はSL、DL 左ならSR、DR" - the tank's own real sprite
; width (tank_gen.py's poses are all 32x32).
TANK_WIDTH EQU 32
; "SL、SRは自機から64px以上Xが離れている時"
HORMING_SIDE_DIST EQU 64
; "自機狙い水平移動の位置を8pxさげてくれ 水平打ちで撃ち落とせる高さ" -
; state2's own 2D pursuit locks onto pure horizontal movement (state3)
; once missile_Y reaches TANK_Y_CUR+this, not exactly TANK_Y_CUR - so
; the final horizontal approach happens at the tank's own horizontal-
; shot height, giving the player a real window to shoot the missile
; down before it ever reaches the tank itself (see CHECK_BULLET_VS_
; HORMING). Magnitude given directly by the user, not inferred.
HORMING_HOMING_Y_OFFSET EQU 8
; ---------- Thunder (BG-drawn lightning column, fired during patrol) ----------
; "サンダーの実装 ホーミング攻撃後左に移動中に添付のキャラを画面2行目
; から下まで移動しながら埋める 埋め終わったら上から消す 発射位置とタ
; イミングはボスの右のX位置でボスが16px移動したら発射 そのまま左まで
; 行き反転後はボスの左に発射 BGで描画", plus round9's corrections:
; "端だけではなくボスが横に32px移動毎に発射"(a real pool, not 1-shot-
; per-leg), "終了位置は地形までに変更 地形に到達したら添付のキャラを
; 地上の上に左右に発射"(grows all the way to the actual terrain surface,
; then drops 2 ThunderS cells beside it - see UPDATE_ONE_THUNDER),
; "表示ウェイト不要"(no step delay).
; 5 new BG pattern codes (2x2 grid for the bolt itself + 1 for ThunderS,
; group27 - the next free BG group after SASAPI_HAND's own groups19-26,
; group31 is SkySand's own, so 27-30 were the remaining candidates).
THUNDER_CODE_BASE EQU 216
THUNDERS_CODE EQU THUNDER_CODE_BASE+4   ; group27's 5th code (216-223 has 8 total, only 5 used)
; fg7(cyan)/bg1(black), matching both uploaded JSONs' own header exactly
; - THUNDERS_CODE shares this same group/color, no separate color-table
; write needed for it.
THUNDER_COLORBYTE EQU 071h
; "画面2行目から" - INFERRED to mean the same row NIGHT_START_ROW(1)
; already anchors to ("スコアの下の行から" - the row right below the
; HUD/score row is the natural "2行目" in 1-indexed counting where row0
; is "1行目") - reusing that landmark rather than a separate literal
; row-index-2 reading, which would be one row further down than where
; the sky itself is considered to start.
THUNDER_TOP_ROW EQU NIGHT_START_ROW
; "ボスが横に32px移動毎に発射" - re-checked continuously through the
; whole leg now (round9), not just once near the edge.
THUNDER_TRIGGER_DX EQU 32
; "サンダー攻撃で自機が画面左端にいると当たらない 明らかに直撃してる"
; fix - see CHECK_THUNDER_TRIGGER_RIGHT's own comment: the rightward
; leg's FIRST trigger only needs the boss to have moved 16px (just
; enough to keep the bolt, placed at BOSS_X-16, clear of the boss's own
; [BOSS_X,BOSS_X+64) body) rather than the full THUNDER_TRIGGER_DX(32)
; every other trigger in the leg waits for - waiting for 32 pushed that
; first bolt's own leftmost reach to column2/pixel16, which can never
; overlap a tank pinned at the screen's absolute left edge (TANK_X=0,
; TANK_COLLISION_WIDTH-wide hitbox [0,15]) no matter how the player
; positions themselves. Confirmed via a real MAINLOOP sweep through a
; full patrol that column2 truly was the minimum column ever allocated
; under the old single-threshold code.
THUNDER_EDGE_TRIGGER_DX EQU 16
; round35: unchanged at 24 despite Flyer growing to 2 instances -
; Flyer's new 2nd instance was placed at 16-19 (BigZum's own idle
; reserve) specifically so it would NOT need to push into this range -
; see FLYER_SPR_BASE_SLOT's own comment.
ETANK_SPR_BASE_SLOT EQU 24     ; hw sprite slots24-25 (BL/BR only x1 instance)
; "カラーはダークレッド" - NOT sprites/Etank.json's own fg, overridden
; directly here (same "override the JSON's own fg" precedent as
; BULLET_U_COLOR/BULLET_SKY_COLORBYTE elsewhere in this file).
ETANK_COLOR EQU 6
ETANK_SPAWNX EQU 240           ; off the right edge, same convention as every other enemy's own spawn-X
; round35: ETANK_PROBE_DX/ETANK_SPAWN_COL removed - both only ever fed
; ETANK_TERRAIN_OK, itself removed the same round ("地形も仮実装だから
; 平地条件いらない"). Etank never re-probes terrain during movement
; (straight horizontal line, no terrain-follow - see UPDATE_ONE_ETANK's
; own comment), so nothing else referenced them.
ETANK_SPEED EQU 2               ; px/frame, flat - "速度は2"
ETANK_COLLISION_SIZE     EQU 24  ; width
ETANK_COLLISION_HEIGHT   EQU 16  ; height - "キャラ位置は32x32の内左下24x16"
ETANK_COLLISION_Y_OFFSET EQU 32-ETANK_COLLISION_HEIGHT  ; =16
ETANK_HP_INIT EQU 7   ; "Etankの耐久値-1" (was 10, then 8)
ETANK_PUSH_SPEED EQU ZUM_PUSH_SPEED  ; "Zumと同じで接触で自機を押す" - same push mechanic/speed as Zum's own UPDATE_TANK_ZUM_PUSH
; "Etankの位置がおかしい また自機基準でオフセットしてねえだろうな
; 毎回同じミスしてる 自機だけジャンプの関係でやってるだけで特殊" - same
; bug class as BIGZUM_Y_OFFSET before it: ALLOC_ETANK_SLOT copied
; TANK_TIER_Y_TABLE's value onto Etank's own Y directly, without
; correcting for the +4 landing-offset fudge TANK_Y_BASE's own
; derivation bakes in specifically for the TANK's own art (which has
; ~5 blank rows at its own bottom - ink stops at row26 of 32,
; `stage2_tank/sprites/TankF.json`). Confirmed directly against
; `sprites/Etank.json`: ink runs all the way to row31 (bottom-left
; 24x16 region, no gap at all - same as BigZum's own art before it),
; so reusing the tank's already-compensated anchor sinks Etank's real,
; un-padded feet ~4px below the true ground line. Subtracted back out
; wherever Etank's own Y is derived from TANK_TIER_Y_TABLE.
ETANK_Y_OFFSET EQU 4
; the 2 BigZum pattern-groups Etank dynamically borrows (see ALLOC_
; ETANK_SLOT/UOET_DRAW) - named here rather than written inline as
; PAT_BIGZUM+8/+12 everywhere it's used. Re-derived directly from
; UOBZ_DRAW's own actual quadrant addressing (TL=+0,TR=+4,BL=+8,BR=+12
; - each 16x16-mode hw sprite code needs its own 4-code group) - see
; the "Etank実装で根本的なバグがある" history in git for the
; PAT_BIGZUM+2/+3 mistake this was originally corrected from.
PAT_ETANK_BL EQU PAT_BIGZUM+8
PAT_ETANK_BR EQU PAT_BIGZUM+12

; ---------- EBullet (ZacoII/Flyer enemy bullet, hw sprite, 16-direction
; aim) ---------- round36-14 follow-up#11 ("ザコ敵の弾発射実装 ZakoII2種
; は反転時に添付データEBullet発射 コリジョンは左上4x4ドット 発射タイミ
; ングの瞬間の自機を狙って直進 発射は16方向 Flyerは画面左端まで行き反転
; 後発射"): fired once by ZacoII at the exact frame it turns back
; (E_RETREAT 0->1, both green/red variants - see UPDATE_ONE_ENEMY) and
; once by Flyer at the exact frame it reaches the left edge and reverses
; into homing (PHASE 0->1 - see UPDATE_ONE_FLYER), aimed at the tank's
; own position at that exact instant then flying dead straight (not
; homing) until off-screen.
;
; This round's own first empirical hw sprite budget survey (booted +
; ~6000 pre-boss frames of real simulated play, checking every one of
; the 256 sprite pattern codes' own VRAM bytes for non-zero content)
; found ATTRIBUTE slots26-31 (6 slots) genuinely never touched during
; normal (non-boss) play - that part held up. But the SAME survey
; wrongly read pattern codes234-238/251-255 as "free": a real-hardware
; report ("EBulletが全く違うパターン") caught what the survey actually
; missed - PAT_FLYER(220-235)/PAT_FLYER_L(236-251) each reserve a full
; 16-code/128-byte block for multiple poses, but only SOME of those 16
; codes have real (non-zero) art; the REST are legitimately blank-but-
; RESERVED filler, indistinguishable from genuinely free codes by a
; simple "is it non-zero" check (the same blind spot HUD_ROW_BLANK_
; CODE's own all-zero-on-purpose tile already illustrates elsewhere in
; this file - "空きに見える" isn't the same as "空き"). A full symbol-
; table-driven audit (every PAT_*/*_CODE EQU cross-referenced against
; its own real LDIRVM byte count, not just VRAM content) found codes
; 0-255 have ZERO genuinely free space anywhere - the entire range is
; claimed, with deliberate SAFE overlaps existing only between
; temporally-exclusive systems (e.g. HORMING's own codes220-239 reuse
; Flyer's, exactly like ATTRIBUTE slot reuse elsewhere in this file -
; safe because Flyer is provably inactive whenever Horming's own boss-
; only code runs).
;
; Fixed by reusing SBEAM_CODE(252-255) the same documented way - SBeam
; ("サンダービーム") is itself a boss-exclusive attack, its own pattern
; loaded once at TRIGGER_BOSS time, well after ZacoII/Flyer (and so
; EBullet's own firing) have already stopped for good (same BOSS_ACT
; gate - see SKIP_ZACO_ENEMY/SKIP_OTHER_ENEMIES). EBullet's own INIT-
; time load holds this code safely for the whole non-boss game, then
; SBeam's own later load simply overwrites it once the boss exists -
; identical in spirit to HORMING_SPR_BASE_SLOT's own ATTRIBUTE-slot
; reuse trick, just applied to pattern codes instead.
EBULLET_SLOT_SIZE  EQU 5    ; +0 ACT,+1 X,+2 Y,+3 DX(signed px/frame),+4 DY(signed px/frame)
EBULLET_SLOT_COUNT EQU 4
EBULLET_POOL          EQU 0C0F5h   ; 4 slots x5 bytes = 20 bytes (C0F5h-C108h)
EBULLET_SPRITE_ATTRS  EQU 0C109h   ; 4 slots x4 bytes (Y,X,pat,col) = 16 bytes (C109h-C118h)
; staging bytes the firer writes its own (IX+E_X)/(IX+E_Y) (or Flyer's
; own (IX+1)/(IX+2)) into just before CALL LAUNCH_EBULLET - LAUNCH_
; EBULLET's own IX gets repurposed to walk EBULLET_POOL looking for a
; free slot, so the firer's origin can't stay in IX/the firer's own
; struct fields across that call.
EBULLET_ORIGIN_X EQU 0C119h
EBULLET_ORIGIN_Y EQU 0C11Ah
EBULLET_CUR_SLOT EQU 0C120h   ; scratch: which of the 4 pool slots UPDATE_ONE_EBULLET is currently working on (0-3) - see UPDATE_EBULLET_ALL
EBULLET_SPR_BASE_SLOT EQU 26   ; hw sprite ATTRIBUTE slots26-29 (this part of the survey held up - see comment above)
PAT_EBULLET EQU SBEAM_CODE      ; TL=252(real art)/BL=253/TR=254/BR=255(blank) - boss-exclusive reuse, see comment above
EBULLET_COLOR EQU 9             ; sprites/Ebullet_16x16.json's own fg (light red) - hw sprite color is a single index, no bg half like BG cells

; ---------- EtankBullet (Etank's own bullet, BG cell, left-only) ----------
; "Etankはスポーン後左へ32px移動したら発射し方向は左直進のみ 弾はBG使用
; ファイルEtankBullet". Same erase-then-move-then-draw BG-cell technique
; as HORMING_BG_POOL (see UPDATE_HORMING_BG_ALL/DRAW_HORMING_BG_CELL/
; ERASE_HORMING_BG_CELL) - only ever 1 concurrent instance needed
; (ETANK_SLOT_COUNT=1 itself, and this bullet only ever fires once per
; Etank spawn), so flat globals instead of a real N-slot pool.
;
; Unlike EBullet, this round's own BG color-table survey (same
; methodology, all 32 groups' own 1-shared-color-per-8-codes entries at
; 0x2000+group) found every one of the 32 groups already color-claimed -
; there is no fully free group left to assign EtankBullet's own source
; art color (fg8/bg11) to without changing an actively-used group's
; shared color. group31(codes248-255, SKYSAND_CODE=248's own group) has
; 7 of its 8 codes genuinely pattern-free AND its own bg nibble(11,
; light yellow) already matches the source art's own bg exactly - only
; fg differs (art wants 8/medium red, group31 is fixed at 5/light blue).
; Per direct user confirmation ("では背景色一致は必要なので文字色が近い
; ものを使ってくれ" - bg match required, use whichever fg is close) this
; bullet renders in group31's own existing fg5/bg11 unchanged - no new
; color write at all, SKYSAND(248) itself is completely untouched.
ETANK_BULLET_ACT   EQU 0C11Bh
ETANK_BULLET_X     EQU 0C11Ch
ETANK_BULLET_Y     EQU 0C11Dh
ETANK_SPAWN_X      EQU 0C11Eh   ; this instance's own spawn-time X, captured once by ALLOC_ETANK_SLOT - lets UPDATE_ONE_ETANK detect "moved 32px" without needing a separate distance counter
ETANK_BULLET_FIRED EQU 0C11Fh   ; 0/1 - this Etank instance has already fired its 1 shot (prevents refiring every frame once past the 32px threshold)
ETANK_BULLET_SPEED EQU 3        ; px/frame, left-only
ETANK_BULLET_PATTERN_CODE EQU 249   ; group31, verified free above

; ---------- FlyerLaser (Flyer's own post-descent horizontal shot, BG
; cell, right-only) ---------- round36-14 follow-up#12: "その後
; FlyerLaser発射 つまり右斜め下移動後に発射 自機は狙わず右方向水平撃ち
; のみ BG使用". Fired once, from UOFL_HOME_MOVE's own descending exit
; (see its own comment for the full reasoning + the paired -8px Y fix),
; not aimed - always straight right, same "flies through/past, no self-
; deactivate on hit" tank-collision convention as EtankBullet's own
; bullet. Same erase-then-move-then-draw BG-cell technique (ACT/X/Y at
; +0/+1/+2, ERASE_HORMING_BG_CELL/HORMING_BG_CELL_ADDR/WRITE_BULLET_
; BYTE_HL reused directly unchanged) - only 1 concurrent instance ever
; needed (1 Flyer instance only ever reaches this exit once per spawn).
; 実機フィードバック対応の変遷 ("FlyerLaserのBG背景色がイエローに
; なってる 背景と同じくライトブルーだぞ レーザー自体はシアン" →
; "流石にブラックはレーザーに見えない" → "じゃあホワイトで ライト
; ブルーにホワイトは使えるんだな"): group31(bg11 yellow, 1st)→
; group27(fg7 cyan/bg1 black, 2nd)を経て、最終的にgroup17へ戻し
; NIGHT_COLOR自体をfg15白/bg5に塗り替える方式に決着(NIGHT_COLOR's own
; comment for the full reasoning) - group0が実際に持っているfg15/bg5
; の組み合わせを、空きコードのあるgroup17に複製する形。背景(bg5)・
; 文字色(fg15白)とも実在の組み合わせで、レーザーらしい白いビームが
; 空の色に完全一致する背景の上に乗る。Pattern code139(Mine1/2の直後)。
FLYER_LASER_ACT   EQU 0C121h
FLYER_LASER_X     EQU 0C122h
FLYER_LASER_Y     EQU 0C123h
FLYER_LASER_SPEED EQU 3          ; px/frame, right-only - untuned initial value
FLYER_LASER_DESPAWN_X EQU 248    ; last on-screen column (32 cols x8px=256) - off past this, despawn
FLYER_LASER_PATTERN_CODE EQU 139 ; group17, see NIGHT_COLOR's own comment

; ---------- Mine (Flyer's own dropped landmine) ---------- round36-14
; follow-up#12: "まずスポーンから32px左に移動したら 添付データのMineを
; 放物線で投下 着地や自機への被弾で16x16ｐｘの爆発エフェクトとサウンド
; 右からしか出ないので左向き放物線のみ Mine1と2のアニメで 取り敢えず
; スプライトだがBGに変更するかも". A full sprite-space pattern-code
; audit this round (same symbol-table cross-reference methodology as
; EBullet/EtankBullet's own - every PAT_*/*_CODE EQU resolved via the
; real assembler's own symbol table, cross-referenced against every
; CALL LDIRVM site's own byte count) found sprite-space codes0-255
; genuinely 100% claimed with NO safe temporal-reuse candidate left at
; all (every boss-exclusive range - PAT_FLYER/_L's own HORMING reuse,
; PAT_BIGZUMP's own BOSS_BROKEN_BEAM reuse, SBEAM_CODE's own EBullet
; reuse - is already claimed at least once, and none of them are safe to
; triple-claim: BigZum/Flyer/Mine can all legitimately coexist, unlike
; the boss itself which is genuinely exclusive with every regular
; enemy). So despite the user's own tentative sprite framing, Mine is
; BG-rendered from the start here (flagged back to the user alongside
; the pre-ship render, same "found a real conflict, made the call,
; showed the result" precedent as EtankBullet's own BG decision earlier
; this same session) - falling/animating as a BG cell exactly like
; EtankBullet, only borrowing a real hw sprite ATTRIBUTE slot (see
; MINE_EXPL_SPR_BASE_SLOT below) for its own brief death animation.
MINE_SLOT_SIZE  EQU 8  ; +0 ACT(0=idle,1=falling,2=exploding),+1 X,+2 Y,+3 VY(signed, gravity-accumulated),+4 ANIM_TIMER,+5 SPRIDX(0/1, which hw ATTRIBUTE slot this instance's own explosion uses),+6 EXPL_TIMER,+7 GRAVITY_COUNTER(0..MINE_GRAVITY_INTERVAL-1, see its own comment)
MINE_SLOT_COUNT EQU 2   ; matches FLYER_SLOT_COUNT - at most 1 falling mine per live Flyer instance
MINE_POOL         EQU 0C124h   ; MINE_SLOT_SIZE*MINE_SLOT_COUNT = 16 bytes (C124h-C133h)
MINE_ORIGIN_X     EQU 0C134h   ; staging bytes the firer (Flyer) writes its own drop point into just before CALL ALLOC_MINE_SLOT - same convention as EBULLET_ORIGIN_X/Y
MINE_ORIGIN_Y     EQU 0C135h
MINE_SPRITE_ATTRS EQU 0C136h   ; MINE_SLOT_COUNT*4 = 8 bytes (Y,X,pat,col)x2 - explosion-only, see MINE_EXPL_SPR_BASE_SLOT
; 実機フィードバック対応 ("Mine投下速度が早すぎる...放物線も出てない"):
; the original "VY += MINE_GRAVITY every single frame" fell so fast
; (~11-15 frames from a typical altitude) that the leftward MINE_VX=1
; drift never accumulated enough px to read as a parabola - it just
; looked like a straight vertical drop. Gravity now only actually
; increments VY once every MINE_GRAVITY_INTERVAL frames (+7 counts up
; to that, wraps and bumps VY) - same magnitude per bump, just spread
; over ~3x more real frames - while VX (now doubled) keeps applying
; every frame regardless, so the same total fall now covers roughly
; 30-60px of visible leftward drift over ~15-30 frames instead of
; 10-15px over ~10 frames. Still untuned initial values.
MINE_GRAVITY EQU 1            ; px/frame^2 per bump - unchanged magnitude
MINE_GRAVITY_INTERVAL EQU 4   ; frames between bumps - was implicitly 1
; 実機フィードバック対応 ("Mine投下の放物線をもう少しX方向に広げて
; 前に投下するように"): was 2 - widened alongside the new MINE_DROP_
; LEAD_X-based trigger (see its own comment) so the drop's own X spread
; roughly matches the 64px lead distance the trigger now fires at
; (Pythonsim: ~45-93px of horizontal drift by landing, depending on
; drop altitude - see this round's own HANDOFF.md entry).
MINE_VX      EQU 3       ; px/frame leftward drift, constant - untuned initial value ("右からしか出ないので左向き放物線のみ")
; 実機フィードバック対応 ("自機位置を見て自機の64px手前に来たら投下"):
; the drop trigger is no longer a fixed "32px from spawn" distance (a
; compile-time constant, tank-unaware) - it now reads TANK_X live every
; frame (see UOFL_CRUISE_STEP) and fires once Flyer's own X has closed
; to within this many px of the tank's own current X (Flyer approaches
; from the right, so "手前" = still this far to the tank's own right).
MINE_DROP_LEAD_X EQU 64
MINE_ANIM_INTERVAL EQU 4 ; frames per animation pose - untuned initial value
; fixed landing line, terrain-independent - same "hard cap regardless of
; the tank's own current tier, never sink into terrain" precedent as
; FLYER_DESCEND_LIMIT_Y (地形も仮実装のため, terrain per-column height
; querying doesn't exist for arbitrary X - only the tank's own column
; does, via TANK_GROUND_Y). tier0's own ground_line=(20+0)*8=160 is the
; shallowest possible real terrain surface; landing at 160-8(this
; entity's own 8px cell height)=152 means Mine's own bottom edge never
; sinks below any real terrain, worst case floating slightly above a
; deeper tier - same accepted approximation as Etank's own terrain-
; independent spawn (see "保留中タスク" in CLAUDE.md).
MINE_LANDING_Y EQU 152
MINE1_CODE EQU 137   ; group17 (NIGHT_CODE=136's own group) - see mine_gen.py's own comment for the exact fg1/bg5 color match
MINE2_CODE EQU 138
; borrowed only during ACT=2 (exploding) - Mine itself is a pure BG
; entity while falling, consuming zero ATTRIBUTE slots, so these are
; free for the rest of Mine's own lifecycle. slots30-31 are the last 2
; of the only 6 hw sprite ATTRIBUTE slots ever verified genuinely free
; during normal (non-boss) play (see EBULLET_SPR_BASE_SLOT's own
; comment - EBullet already claims 26-29, leaving exactly 30-31, a
; perfect 1-per-instance fit for MINE_SLOT_COUNT=2).
MINE_EXPL_SPR_BASE_SLOT EQU 30

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
CLOUD_POOL    EQU F1A9h   ; CLOUD_SLOT_SIZE*CLOUD_SLOT_COUNT bytes (27, was 54 with all 6 rows)
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
GAME_RNG     EQU F1DFh
CLOUD_SPAWN_COL EQU 32     ; leftmost cell starts one column past the right edge
; codes1-2: genuinely unused pattern-code slots within group0 (see the
; INIT-time load below) - reuses src/CYBER SHMUP.asm's own CLOUD_WA/
; WB_CODE art byte-for-byte, just renumbered since Stage2's own code
; map is unrelated to Stage1's.
CLOUD_A_CODE  EQU 1
CLOUD_B_CODE  EQU 2
CLOUD_GROUP0_COLOR EQU 0F5h   ; fg15 white / bg5 light blue (group0 was 0x55 sky-on-sky)

; 0F380h+ is real MSX BIOS work-area territory (VDP register shadows
; etc., serviced by the H.TIMI interrupt handler every VBlank on real
; hardware, entirely independent of this ROM's own no-HALT design -
; interrupts still fire even though this code never waits on one), NOT
; free RAM - a prior round briefly grew this past 0F380h to make room
; for new enemy pools and got a real-hardware freeze with garbled
; graphics that no emulator run ever reproduced (z80emu.py has no
; interrupt/BIOS simulation at all, so it read back exactly what the
; game itself last wrote there). Any new RAM belongs strictly BELOW
; this line, never at or above it.
;
; "白いEtankがでて右側にゴミ...過去の例では使用する変数やRamが初期化
; されてなくて誤動作したり スタックの扱いをミスってたりな Push Pop
; 不整合だ" - this earlier fix (keeping our OWN variables below 0F380h)
; was necessary but NOT sufficient: it only protects against variables
; growing UP into BIOS territory, it says nothing about the STACK
; (which starts AT 0F380h and grows DOWN) needing enough of its own
; headroom before it reaches back down into OUR variables. Measured
; directly in z80emu.py (tracking SP on every single instruction
; step, not just at frame boundaries): ordinary nested CALLs during a
; single MAINLOOP frame - no interrupts involved at all - already
; dipped SP to 0F374h (12 bytes below STACKTOP), which used to be
; INSIDE BANKSWITCH_TRAMPOLINE_RAM and only 1 byte from ETANK_DRAW_
; COLOR - with the H.TIMI interrupt overhead this same comment already
; warned about on top of that (a real save-registers-then-work ISR
; easily needs several times that many bytes), a live game variable
; getting clobbered mid-frame by an ordinary PUSH is entirely
; plausible, exactly matching "白いEtankが...スポーンで描画されてる
; わけじゃない" (garbage showing up with no real spawn behind it) and
; explaining why the SAME symptom tracked whichever entity's own scratch
; RAM happened to sit closest to STACKTOP (BigZum's own DRAW_COLOR
; before its removal, Etank's own DRAW_COLOR after). Not a PUSH/POP
; mismatch (every push in this file was re-audited and balances - SP
; always returns exactly to STACKTOP at the top of every frame), just
; too little real distance between "everything we use" and "where the
; stack lives" for a system whose interrupt overhead this file's own
; test harness cannot simulate at all. Fixed by shifting every OTHER
; RAM address in this file down by 100h (256 bytes, TICK now at
; 0EF00h instead of 0F000h) - STACKTOP itself is untouched (still the
; correct real BIOS boundary), but now has 256+ bytes of genuinely
; free headroom below it before reaching our own topmost variable,
; comfortably past anything a real interrupt handler plus our own
; deepest measured call nesting could plausibly need.
STACKTOP      EQU 0F380h

INIT:
    LD SP,STACKTOP

    ; checkpoint P1 (border color 11): INIT reached, SP set.
    LD B,11 : LD C,7 : CALL WRTVDP

    ; "フリーズはしてないがグリッチ ボーダーはブラックだな" - even
    ; checkpoint P1 above (literally the first 2 real instructions in
    ; INIT) never showed on the board that reported this, which rules
    ; out the previous fix's own logic (already re-verified byte-for-
    ; byte correct against its own reference) and confirms this specific
    ; flashcart genuinely can't boot a >16KB image without a real
    ; ASCII16 mapper - MSX-internal slot routing was never going to be
    ; enough. "ASCII16バンク実装でも構わないが...本番形式でやってみろ
    ; 64KBだからな" - this is now the SAME real, production ASCII16
    ; bank-switch mechanism `tools/bankswitch_poc/build_full_rom.py`'s
    ; own `patched_game_text()` injects into the actually-shipped game
    ; (not the simpler standalone POC in `bank_a.asm`, and not the bare
    ; `CYBER SHMUP.asm` source, which - confirmed by grepping it - has
    ; only the PPI slot-mapping step below, no trampoline at all; that
    ; step's own "confirmed working on real hardware" history predates
    ; the ASCII16 migration and evidently doesn't hold for whatever
    ; flashcart is being used to test this file). Copied verbatim from
    ; that real, currently-shipped mechanism, not reconstructed from
    ; memory - RAM trampoline source below, called with A=bank number,
    ; DE=mapper select address (6000h=window A/page1, 7000h=window
    ; B/page2), HL=address to resume at afterward. Only ONE switch is
    ; ever needed here (bank1 into window B, once, at boot, then left
    ; selected permanently - this file has no real second phase of
    ; content the way the main game's stage1->stage2 transition does,
    ; just needs more than 16KB total), so window A (page1, where this
    ; INIT itself lives) is never touched.
    JP BANKSWITCH_TRAMPOLINE_END
BANKSWITCH_TRAMPOLINE_SRC:
    LD (DE),A
    JP (HL)
BANKSWITCH_TRAMPOLINE_LEN EQU $ - BANKSWITCH_TRAMPOLINE_SRC
BANKSWITCH_TRAMPOLINE_END:

    ; same "map our own primary slot into page2" PPI step `CYBER
    ; SHMUP.asm`'s own INIT already has (kept, not replaced - the real
    ; shipped game keeps both this AND the ASCII16 trampoline together,
    ; per `build_full_rom.py`'s own patch, so this does too) - belt-
    ; and-suspenders for a flashcart that doesn't auto-map page2 to the
    ; same OUTER slot as page1, independent of the mapper's own INNER
    ; bank selection handled below.
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

    ; checkpoint P2 (border color 12): slot register write done.
    LD B,12 : LD C,7 : CALL WRTVDP

    LD HL,BANKSWITCH_TRAMPOLINE_SRC
    LD DE,BANKSWITCH_TRAMPOLINE_RAM
    LD BC,BANKSWITCH_TRAMPOLINE_LEN
    LDIR

    ; checkpoint P3 (border color 13): trampoline copied to RAM.
    LD B,13 : LD C,7 : CALL WRTVDP

    LD A,1
    LD DE,7000h
    LD HL,INIT_RESUME_AFTER_BANK_SELECT
    JP BANKSWITCH_TRAMPOLINE_RAM
INIT_RESUME_AFTER_BANK_SELECT:
    ; checkpoint P4 (border color 14): bank1 select via the RAM
    ; trampoline returned successfully - page2 should now show this
    ; ROM's own real bank1 content.
    LD B,14 : LD C,7 : CALL WRTVDP

    DI
    CALL INIT32
    EI

    ; checkpoint 1: INIT started, SP set, ASCII16 bank1 selected for
    ; page2, BIOS SCREEN1 setup done
    LD B,1 : LD C,7 : CALL WRTVDP

    LD HL,TERRAIN_PATTERNS : LD DE,0000h : LD BC,TERRAIN_PATTERN_COUNT*8 : CALL LDIRVM
    LD HL,TERRAIN_COLORDATA : LD DE,2000h : LD BC,32 : CALL LDIRVM

    ; EtankBullet BG pattern (round36-14 follow-up#11) - group31's own
    ; free tail, code249 - see ETANK_BULLET_PATTERN_CODE's own comment.
    ; No color write: reuses group31's own existing fg5/bg11 unchanged.
    LD HL,ETANK_BULLET_PATTERN : LD DE,ETANK_BULLET_PATTERN_CODE*8+0000h : LD BC,8 : CALL LDIRVM

    ; FlyerLaser BG pattern (round36-14 follow-up#12) - group31's own
    ; tail, code250 - see FLYER_LASER_PATTERN_CODE's own comment. No
    ; color write: reuses group31's own existing fg5/bg11 unchanged.
    LD HL,FLYER_LASER_PATTERN : LD DE,FLYER_LASER_PATTERN_CODE*8+0000h : LD BC,8 : CALL LDIRVM

    ; Mine BG pattern, 2-frame anim (round36-14 follow-up#12) - group17's
    ; own free tail, codes137-138 - see MINE1_CODE/MINE2_CODE's own
    ; comment. No color write: reuses group17's own existing fg1/bg5
    ; unchanged (exact match to both source images).
    LD HL,MINE1_PATTERN : LD DE,MINE1_CODE*8+0000h : LD BC,8 : CALL LDIRVM
    LD HL,MINE2_PATTERN : LD DE,MINE2_CODE*8+0000h : LD BC,8 : CALL LDIRVM

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
    ; round36-12 tried changing this byte's own bg (see git history);
    ; round36-13 reverted it back to the original bg11 - "Rock225もイジ
    ; ったな Rock225の背景色は前に戻せ" - this one patch colors Rock AND
    ; every R225 variant identically (they share group1/the blend-pair
    ; groups by construction), so it can't be changed for "just Rock"
    ; without a much larger restructuring - see ROCK_COLOR_SWAPPED_
    ; PATCH's own comment for the full reasoning.
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

    ; F's own BG pattern: round36-11 grew from 1 pose to 3 (BulletFU/FM/
    ; FL, bullet_gen.py's own BULLET_F_PATTERN0/1/2) - each loaded once
    ; per background color group it can appear over (see BULLETF_SKY_
    ; CODE0 etc. above), and the mirrored (left-facing) shape the same
    ; way at its own codes.
    LD HL,BULLET_F_PATTERN0 : LD DE,BULLETF_SKY_CODE0*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN1 : LD DE,BULLETF_SKY_CODE1*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN2 : LD DE,BULLETF_SKY_CODE2*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN0 : LD DE,BULLETF_ROCK_CODE0*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN1 : LD DE,BULLETF_ROCK_CODE1*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN2 : LD DE,BULLETF_ROCK_CODE2*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN0 : LD DE,BULLETF_L_SKY_CODE0*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN1 : LD DE,BULLETF_L_SKY_CODE1*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN2 : LD DE,BULLETF_L_SKY_CODE2*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN0 : LD DE,BULLETF_L_ROCK_CODE0*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN1 : LD DE,BULLETF_L_ROCK_CODE1*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN2 : LD DE,BULLETF_L_ROCK_CODE2*8 : LD BC,8 : CALL LDIRVM

    ; F's own bullet color groups: patch over terrain_gen.py's generic
    ; per-group defaults for the 2 groups its codes live in - see
    ; BULLET_SKY_COLORADDR/BULLET_ROCK_COLORADDR above.
    LD A,BULLET_SKY_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_SKY_COLORADDR : LD BC,1 : CALL LDIRVM
    LD A,BULLET_ROCK_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,BULLET_ROCK_COLORADDR : LD BC,1 : CALL LDIRVM

    ; F's own night-black glyph (see BULLETF_NIGHT_CODE0's own comment) -
    ; same shapes as the day glyph, own dedicated color group (round36-11:
    ; moved to group30, BULLET_NIGHT_COLORADDR, from the old fixed
    ; "2000h+18" literal - see that EQU's own comment).
    LD HL,BULLET_F_PATTERN0   : LD DE,BULLETF_NIGHT_CODE0*8   : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN1   : LD DE,BULLETF_NIGHT_CODE1*8   : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_PATTERN2   : LD DE,BULLETF_NIGHT_CODE2*8   : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN0 : LD DE,BULLETF_L_NIGHT_CODE0*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN1 : LD DE,BULLETF_L_NIGHT_CODE1*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_F_L_PATTERN2 : LD DE,BULLETF_L_NIGHT_CODE2*8 : LD BC,8 : CALL LDIRVM
    LD A,BULLET_NIGHT_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,BULLET_NIGHT_COLORADDR : LD BC,1 : CALL LDIRVM

    ; U's own BG-cell pattern (see BULLETU_SKY_CODE's own comment) - a
    ; single non-rotating pose (BulletUM), loaded into F's already-
    ; colored groups28/29/30, no new color-table writes needed.
    LD HL,BULLET_U_PATTERN   : LD DE,BULLETU_SKY_CODE*8    : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_L_PATTERN : LD DE,BULLETU_L_SKY_CODE*8  : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN   : LD DE,BULLETU_ROCK_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_L_PATTERN : LD DE,BULLETU_L_ROCK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_PATTERN   : LD DE,BULLETU_NIGHT_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_U_L_PATTERN : LD DE,BULLETU_L_NIGHT_CODE*8 : LD BC,8 : CALL LDIRVM

    ; U's own hw sprite pattern (16x16, right after PAT_EXPLOSION) -
    ; primed here with variant0 (BulletUU) purely as a sane INIT-time
    ; default so the pattern slot never holds garbage before the first
    ; shot; TRY_SPAWN_BULLET's own WRITE_BULLETU_SPRITE_VARIANT
    ; overwrites this same slot with the correct rotating variant at
    ; every actual diagonal shot spawn (see BULLET_U_SPR_BASE_SLOT's own
    ; comment for why there's only ever 1 resident bitmap here).
    LD HL,BULLET_U_SPRITE0 : LD DE,PAT_BULLETU*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BULLET_U_SPRITE0_L : LD DE,PAT_BULLETU_L*8+SPRPAT : LD BC,32 : CALL LDIRVM
    XOR A : LD (BULLETF_ROT_COUNTER),A : LD (BULLETU_ROT_COUNTER),A

    ; round36-12: the new BG-drawn Horming pool's own 5 facing patterns
    ; and single shared color group (group18, 144-151 - see HORMING_BG_
    ; SL_CODE's own comment). Loaded once here at INIT, unlike the hw
    ; sprite version's own patterns (which wait for boss-spawn time to
    ; take over Flyer's still-in-use block) - nothing else in this game
    ; ever needs codes144-151 at any point, so there's no "guaranteed
    ; dead owner" timing dependency to wait for.
    LD HL,HORMING_BG_SL_PATTERN   : LD DE,HORMING_BG_SL_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DL_PATTERN   : LD DE,HORMING_BG_DL_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DOWN_PATTERN : LD DE,HORMING_BG_DOWN_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DR_PATTERN   : LD DE,HORMING_BG_DR_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_SR_PATTERN   : LD DE,HORMING_BG_SR_CODE*8   : LD BC,8 : CALL LDIRVM
    LD A,HORMING_BG_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,HORMING_BG_COLORADDR : LD BC,1 : CALL LDIRVM

    ; round36-14 (relocated to group12/codes96-100 after the group2/
    ; codes18-22 attempt turned out to collide with real terrain blend
    ; data - see HORMING_BG_SAND_SL_CODE's own comment): same 5 facing
    ; bitmaps again, plus this time a real, needed color write (group12
    ; is NOT a group terrain leaves alone the way group2's SAND_GROUPS
    ; carve-out is).
    LD HL,HORMING_BG_SL_PATTERN   : LD DE,HORMING_BG_SAND_SL_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DL_PATTERN   : LD DE,HORMING_BG_SAND_DL_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DOWN_PATTERN : LD DE,HORMING_BG_SAND_DOWN_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_DR_PATTERN   : LD DE,HORMING_BG_SAND_DR_CODE*8   : LD BC,8 : CALL LDIRVM
    LD HL,HORMING_BG_SR_PATTERN   : LD DE,HORMING_BG_SAND_SR_CODE*8   : LD BC,8 : CALL LDIRVM
    LD A,HORMING_BG_SAND_COLORBYTE : LD (BULLET_TEMP_BYTE),A
    LD HL,BULLET_TEMP_BYTE : LD DE,HORMING_BG_SAND_COLORADDR : LD BC,1 : CALL LDIRVM

    ; Sasapi's own attack-pose hand art (BG pattern, not a hw sprite -
    ; see SASAPI_HAND_CODE_BASE's own comment) - a permanent allocation
    ; loaded once here, unlike the boss's own body (SASAPI_QUADS/_L,
    ; loaded dynamically by LOAD_SASAPI_PATTERNS at spawn/reversal since
    ; it reuses BigZum's own pattern-VRAM budget instead of a fresh
    ; block). 512 bytes, DI/EI-wrapped same as LOAD_SASAPI_PATTERNS's
    ; own 512-byte load - not a per-frame write, so a single wrap
    ; (rather than FLUSH_BOSS_SPRITES's own per-quadrant chunking) is
    ; enough.
    DI
    LD HL,SASAPI_HAND_TILES : LD DE,SASAPI_HAND_CODE_BASE*8 : LD BC,64*8 : CALL LDIRVM
    EI
    LD HL,SASAPI_HAND_COLOR8 : LD DE,2000h+19 : LD BC,8 : CALL LDIRVM

    ; Thunder's own BG art (group27, see THUNDER_CODE_BASE's own
    ; comment) - same permanent-allocation idiom as the hand art above.
    DI
    LD HL,THUNDER_TILES : LD DE,THUNDER_CODE_BASE*8 : LD BC,4*8 : CALL LDIRVM
    LD HL,THUNDERS_TILE : LD DE,THUNDERS_CODE*8 : LD BC,1*8 : CALL LDIRVM
    EI
    LD A,THUNDER_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+27 : LD BC,1 : CALL LDIRVM

    ; homing missile's own hw sprite patterns are NOT loaded here - round-
    ; 2 correction moved them to a dynamically-reused block (Flyer's own,
    ; PAT_HORMING_SL etc.) loaded at boss-spawn time instead (see
    ; UPDATE_BOSS_ALL's own spawn branch) - Flyer needs its own real
    ; pattern data intact for ordinary gameplay before the boss ever
    ; appears, same timing constraint LOAD_SASAPI_PATTERNS already
    ; follows for the boss's own body reusing BigZum's block.

    ; checkpoint 6: tank + bullet patterns loaded
    LD B,6 : LD C,7 : CALL WRTVDP

    ; --- explicitly clear the WHOLE sprite attribute table (32       ---
    ; --- entries x 4 bytes = 128 bytes) to a fully hidden, known      ---
    ; --- state (Y=209/0D1h - past the Y=208 stop-sentinel - X/pattern/---
    ; --- color=0), matching src/CYBER SHMUP.asm's own INIT_SPRATR_CLR ---
    ; --- exactly (raw OUT, DI/EI-wrapped NOP-padded OUT around every single byte (99h address-setup trimmed to 2 NOPs, 98h data write kept at 8 - see WRITE_BULLET_BYTE_HL's own comment for the real VDP timing this follows) -  ---
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
    LD (TANK_FLASH_TIMER),A
    LD (TANK_HAZARD_IFRAMES),A
    LD (DASH_ACTIVE),A
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

    ; life bar (see LIFE_CODE's own comment): HUD_ROW_BLANK_CODE's own
    ; pattern (blank) + color (black), LIFE_CODE's own pattern (Life_
    ; 8x8.json) + color (fg3/bg5).
    LD HL,HUD_ZERO8 : LD DE,HUD_ROW_BLANK_CODE*8 : LD BC,8 : CALL LDIRVM
    LD A,HUD_ROW_BLANK_COLOR : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+15 : LD BC,1 : CALL LDIRVM
    LD HL,LIFE_PATTERN : LD DE,LIFE_CODE*8 : LD BC,8 : CALL LDIRVM
    LD A,LIFE_COLOR : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+16 : LD BC,1 : CALL LDIRVM

    ; night-transition tile: SKYSAND_PATTERN's own bits (the striped
    ; look), own dedicated group17 colored fg5/bg1 instead of SkySand's
    ; own fg5/bg11 - see NIGHT_START_TICK's own comment.
    LD HL,SKYSAND_PATTERN : LD DE,NIGHT_CODE*8 : LD BC,8 : CALL LDIRVM
    LD A,NIGHT_COLOR : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+17 : LD BC,1 : CALL LDIRVM
    XOR A : LD (NIGHT_ROW),A
    LD HL,NIGHT_START_TICK : LD (NIGHT_NEXT_TICK),HL

    ; "最上部の行はブラックで初期化" - the whole top HUD row (32 cells)
    ; to HUD_ROW_BLANK_CODE first; SCORE_DISPLAY/LIFE_DISPLAY/
    ; GAME_TICK_DISPLAY overwrite their own specific cells afterward.
    LD HL,HUD_BLACKROW32 : LD DE,1800h : LD BC,32 : CALL LDIRVM

    LD A,TANK_LIFE_INIT : LD (TANK_LIFE),A
    CALL LIFE_DISPLAY

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

    ; "でTick0に" - reverting the old "初期Tickを840に" fast-iteration
    ; diagnostic boot value back to a real 0 boot, exactly as this
    ; comment's own note always said to do for a real shipped build. This
    ; also removes the root cause behind the 3 long-standing known
    ; regression failures (boss_test.py/etank_gametick_gate_test.py/
    ; night_effect_test.py) that assumed a genuine GAME_TICK=0 boot -
    ; those should now pass for real; if any genuinely doesn't, that's a
    ; real bug worth its own look, not the same "known" excuse as before.
    LD HL,0 : LD (GAME_TICK),HL
    XOR A
    LD (HORMING_POOL+0),A
    LD (HORMING_POOL+7),A
    LD (HORMING_POOL+14),A
    LD (HORMING_POOL+21),A
    LD (HORMING_BG_POOL+0),A
    LD (HORMING_BG_POOL+7),A
    LD (HORMING_BG_POOL+14),A
    LD (HORMING_BG_POOL+21),A
    ; "こう言ったゲームってのは全てスケジュールで動くんだよ...ボス前と
    ; ボススポーン後は完全に分けて一切干渉しない 当然ボスまでは一切関連
    ; ルーチンも呼ばんし最初にメモリを確保したりしない...初期化もボス用
    ; はボススポーン直前" (round23) - BOSS_ACT is the ONE necessary
    ; exception: UPDATE_BOSS_ALL's own very first instruction is `LD A,
    ; (BOSS_ACT) : CP 2 : RET Z : OR A : JP NZ,UBA_ACTIVE`, and that call
    ; itself can't be deferred to spawn time - it's the ONLY thing that
    ; ever checks GAME_TICK against BOSS_SPAWN_TICK, so it has to run
    ; every frame from boot. A garbage nonzero BOSS_ACT there would skip
    ; the spawn check forever and jump straight into patrol/pose logic
    ; reading entirely unset BOSS_X/Y/DIR/PHASE - the real round22 bug.
    ; Every OTHER boss-only field (SBEAM_ACT, THUNDER_PENDING/ELIGIBLE,
    ; THUNDER_POOL's own 4 slots) does NOT need a boot-time zero any
    ; more: round23's own BOSS_ACT-gated SKIP_BOSS_SUBSYSTEMS means
    ; UPDATE_THUNDER/CHECK_THUNDER_VS_TANK/UPDATE_SBEAM/CHECK_SBEAM_VS_
    ; TANK are never even CALLED while BOSS_ACT==0 - and the real spawn
    ; transition below (UBA_ACTIVE's own sibling branch) already zeroes
    ; all of them itself, atomically, in the same instant it sets
    ; BOSS_ACT=1, before anything downstream could ever read them. No
    ; window for garbage to matter any more - removing the redundant
    ; boot-time zeros for those, matching "道中は道中 ボスはボス".
    LD (BOSS_ACT),A
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

    ; EBullet (ZacoII/Flyer enemy bullet - round36-14 follow-up#11) - own
    ; verified-free 4-code group, see PAT_EBULLET's own comment.
    LD HL,EBULLET_SPRITE : LD DE,PAT_EBULLET*8+SPRPAT : LD BC,32 : CALL LDIRVM
    ; pool + RAM staging buffer both need priming, same 2-part reasoning
    ; as ENEMY_SPRITE_ATTRS's own comment just above (IESA_LOOP) - the
    ; real VRAM SAT is already hidden via the earlier full 32-slot clear,
    ; but EBULLET_SPRITE_ATTRS itself starts blank (Y=0) and would show
    ; garbage at the top of the screen on the very first FLUSH_EBULLET_
    ; SPRITES call otherwise. Found and fixed via a direct fresh_cpu()
    ; test this same round (boot-state SAT bytes for slots26-29 checked
    ; before vs after a real MAINLOOP frame) - see this round's own
    ; HANDOFF entry.
    LD HL,EBULLET_POOL
    LD B,EBULLET_SLOT_SIZE*EBULLET_SLOT_COUNT
    XOR A
IEBZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IEBZ_LOOP
    LD HL,EBULLET_SPRITE_ATTRS
    LD B,EBULLET_SLOT_COUNT
IEBSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IEBSA_LOOP

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

    ; Flyer's own pattern (flyer_gen.py) - permanent allocation, both
    ; facings, right after BigZum's own last group.
    LD HL,FLYER_TL   : LD DE,PAT_FLYER*8+SPRPAT   : LD BC,128 : CALL LDIRVM
    LD HL,FLYER_L_TL : LD DE,PAT_FLYER_L*8+SPRPAT : LD BC,128 : CALL LDIRVM

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
    LD (SPAWN2_NEXT_INDEX),A
    LD (S2_SPAWN_Y),A

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
    LD (S2_SPAWN_VARIANT),A

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

    ; Flyer pool: same generic zero-then-assign-SPRIDX shape as the
    ; pools above.
    LD HL,FLYER_POOL
    LD B,FLYER_SLOT_SIZE*FLYER_SLOT_COUNT
    XOR A
IFLZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IFLZ_LOOP

    LD HL,FLYER_POOL
    LD B,FLYER_SLOT_COUNT
    LD C,0
IFLSP_LOOP:
    PUSH HL
    POP IX
    LD A,C : LD (IX+4),A
    INC C
    LD DE,FLYER_SLOT_SIZE : ADD HL,DE
    DJNZ IFLSP_LOOP

    LD HL,FLYER_SPRITE_ATTRS
    LD B,FLYER_SLOT_COUNT*4
IFLSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IFLSA_LOOP

    ; Etank pool: no per-slot SPRIDX assignment needed (ETANK_SLOT_COUNT
    ; =1, its own draw code writes ETANK_SPRITE_ATTRS directly - see
    ; UOET_DRAW). No pattern-VRAM load here either - Etank dynamically
    ; borrows BigZum's own PAT_BIGZUM BL/BR groups only at its own spawn
    ; time (see ALLOC_ETANK_SLOT).
    LD HL,ETANK_POOL
    LD B,ETANK_SLOT_SIZE*ETANK_SLOT_COUNT
    XOR A
IETZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IETZ_LOOP

    LD HL,ETANK_SPRITE_ATTRS
    LD B,ETANK_SLOT_COUNT*2
IETSA_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ IETSA_LOOP

    ; boss (Sasapi): just BOSS_ACT=0 (not spawned) plus the rest of its
    ; own state zeroed alongside it - no pattern-VRAM load and no hw
    ; sprite hide-init here either, same reasoning as Etank just above
    ; (borrows its hw slots AND pattern-VRAM only at its own spawn time,
    ; see BOSS_SPR_BASE_SLOT/PAT_SASAPI's own comments - the slots it
    ; will reuse are already hidden by Zum/BigZum/Flyer/Etank's own
    ; INIT code above, and stay correctly hidden every frame until the
    ; boss spawns since UPDATE_BOSS_ALL is a no-op with BOSS_ACT=0).
    LD HL,BOSS_ACT
    LD B,4
    XOR A
IBOZ_LOOP:
    LD (HL),A
    INC HL
    DJNZ IBOZ_LOOP

    ; cloud pool: each of the 6 slots gets its own fixed ROW (2-7,
    ; CLOUD_ROW_TABLE)/INTERVAL/FIXED4/initial WAIT from the 4 lookup
    ; tables below, ROWADDR precomputed once (row*32 fits an 8-bit low
    ; byte for rows0-7, so the high byte is always 18h - no per-frame
    ; lookup needed later). The initial WAIT is a fixed per-slot stagger
    ; (CLOUD_INIT_WAIT_TABLE), NOT CLOUD_RANDOM_WAIT - see that table's
    ; own comment for why a real RNG call here produced 3 near-identical
    ; values and all 3 clouds spawning bunched together the first time.
    ; C is the table index (0-5); PUSH BC around the CALL protects both
    ; it and the outer DJNZ counter B, same precaution as every other
    ; pool loop in this file after the enemy-pool DJNZ/B-clobber bug
    ; (see README).
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
    LD A,C : LD E,A : LD D,0
    LD HL,CLOUD_INIT_WAIT_TABLE : ADD HL,DE : LD A,(HL)
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

    ; "Stage1は地形書き換え8回に1回カウントする作り すべての基準は
    ; このカウント これはスケジュールエディタで指定するため カウント
    ; 表示をStage1と同様に修正" - GAME_TICK previously incremented
    ; every single MAINLOOP pass (see the old unconditional INC further
    ; down, now removed), 8x faster than the actual terrain-scroll-step
    ; rate - this branch only runs once per 8 raw TICKs (the same
    ; AND 07h gate the terrain rewrite above already uses), so moving
    ; the increment+redraw here syncs the displayed count to the same
    ; unit Stage1's own schedule editor actually schedules events
    ; against, instead of a rate 8x too fast to mean anything as a
    ; scheduling unit.
    ; round34-2 first attempt ("Tickは999終了で繰り返さない") capped the
    ; real GAME_TICK counter itself here - wrong fix, reverted: the
    ; boss's own internal timers (BOSS_LEFT_PAUSE_END_TICK/BOSS_POSE_
    ; END_TICK, both "GAME_TICK+some small constant, armed at whatever
    ; moment the boss happens to reach that state") need GAME_TICK to
    ; keep advancing normally for as long as the boss fight is running -
    ; freezing it here made both of those targets permanently
    ; unreachable once the boss's own patrol first touched the left
    ; edge or the pose-entry point AFTER the freeze had already kicked
    ; in (which it reliably had, since the boss itself doesn't even
    ; spawn until close to tick995), softlocking the whole fight
    ; (BOSS_PHASE stuck at 2 forever - caught by boss_pose_test.py's own
    ; real-MAINLOOP checks). GAME_TICK is a free-running 16-bit counter
    ; again, same as always; what's actually capped now is only the
    ; on-screen 3-digit readout (GAME_TICK_DISPLAY's own MOD1000
    ; conversion, see its own comment) - the real "見た目上999で止まる、
    ; 繰り返して見えない" (looks like it stops at 999, doesn't look like
    ; it repeats) the user actually asked for, without breaking any
    ; real timing math that depends on the true value still advancing.
    LD HL,(GAME_TICK) : INC HL : LD (GAME_TICK),HL
    CALL GAME_TICK_DISPLAY
    CALL CHECK_NIGHT
    ; round34 ("ランダムスポーンは廃止 全てスケジュールに") - see
    ; SPAWN2_SCHEDULE_CHECK's own comment. Same call-site convention as
    ; src/CYBER SHMUP.asm's own SPAWN_SCHEDULE_CHECK: once per GAME_TICK
    ; increment, right alongside it.
    CALL SPAWN2_SCHEDULE_CHECK
SKIP_ADVANCE:
    ; 地形スクロール停止テストは「表示が崩れる(復帰処理未実装)」で
    ; バグではないが今回はやめる、に戻す - always runs again, unconditional.
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
    CALL UPDATE_DASH
    CALL UPDATE_TANK_XY
    CALL UPDATE_TERRAIN_COLLISION
    CALL UPDATE_JUMP
    CALL UPDATE_TANK_ZUM_STAND
    CALL UPDATE_TANK_BIGZUM_STAND
    CALL UPDATE_TANK_ETANK_STAND
    CALL UPDATE_POSE
    CALL UPDATE_TANK_SPRITES
    ; bullets advance before a new one can spawn, so a shot fired this
    ; frame gets drawn once (at the muzzle) instead of being advanced
    ; a 2nd time by this same frame's UPDATE_BULLETS sweep.
    CALL UPDATE_BULLETS
    CALL UPDATE_SHOT
    ; "使われない物を呼ぶのは無駄だし ボスはStage1でもそうだが それまでの
    ; 処理は捨ててボス専用 もうザコは出ないからな" - once the boss has
    ; spawned, every ordinary enemy type's own per-frame update+flush
    ; (ZacoII/Zum/BigZum/Flyer/Etank, plus their own bullet-collision and
    ; tank-push/punch reactions) is skipped entirely instead of running
    ; unconditionally against an already-fully-inactive pool every single
    ; frame - was real, needless per-frame VDP write volume (each of
    ; these has its own DI/EI-wrapped FLUSH_*_SPRITES burst) stacking on
    ; top of the boss's own 16-quadrant writes for the rest of the game.
    ; UPDATE_BULLET_U_SPRITES is NOT part of this - it's the player's own
    ; shot rendering (BULLET0/1/2_ACT), not an enemy system, and must
    ; keep running regardless of the boss.
    LD A,(BOSS_ACT) : OR A
    JR NZ,SKIP_ZACO_ENEMY
    CALL UPDATE_ENEMIES
    CALL CHECK_BULLET_VS_ENEMY
    ; EBullet (round36-14 follow-up#11) - fired by both ZacoII (above)
    ; and Flyer (SKIP_OTHER_ENEMIES block below), but updated/collision-
    ; checked from just this one gate since both firers share the exact
    ; same BOSS_ACT condition - an EBullet in flight when the boss spawns
    ; (ZacoII/Flyer themselves stop firing new ones, per this same gate)
    ; would freeze mid-flight rather than despawn, same known low-
    ; probability edge case as EBULLET_SLOT_SIZE's own comment already
    ; flags for the pattern-code/sprite-slot side of this feature.
    CALL UPDATE_EBULLET_ALL
    CALL CHECK_EBULLET_VS_TANK
SKIP_ZACO_ENEMY:
    CALL UPDATE_BULLET_U_SPRITES
    LD A,(BOSS_ACT) : OR A
    JR NZ,SKIP_OTHER_ENEMIES
    CALL UPDATE_ZUM_ALL
    CALL CHECK_BULLET_VS_ZUM
    CALL UPDATE_TANK_ZUM_PUSH
    CALL UPDATE_BIGZUM_ALL
    CALL CHECK_BULLET_VS_BIGZUM
    CALL UPDATE_TANK_BIGZUM_PUNCH
    CALL UPDATE_FLYER_ALL
    CALL CHECK_BULLET_VS_FLYER
    CALL UPDATE_ETANK_ALL
    CALL CHECK_BULLET_VS_ETANK
    CALL UPDATE_TANK_ETANK_PUSH
    CALL UPDATE_ETANK_BULLET_ALL
    CALL CHECK_ETANK_BULLET_VS_TANK
    ; Mine/FlyerLaser (round36-14 follow-up#12) - both Flyer-sourced,
    ; same BOSS_ACT gate as Flyer itself.
    CALL UPDATE_MINE_ALL
    CALL CHECK_MINE_VS_TANK
    CALL UPDATE_FLYER_LASER_ALL
    CALL CHECK_FLYER_LASER_VS_TANK
SKIP_OTHER_ENEMIES:
    ; UPDATE_BOSS_ALL itself must stay unconditional - it's the ONLY
    ; thing that ever checks GAME_TICK against BOSS_SPAWN_TICK and
    ; performs the actual spawn, so it can't be gated on BOSS_ACT (that
    ; would be circular - nothing would ever set it nonzero). But
    ; "それになんで常時ボスの処理走らせてんだよ...Tick999まで1回も使わ
    ; れないだろうが 速度無制限じゃねえぞ ボスはボス 道中は道中" - every
    ; OTHER boss-only subsystem (Homing/Thunder/SBeam and their own
    ; tank-collision checks) has nothing to do until the boss has
    ; actually spawned, and was being called every single frame of the
    ; whole ~7992-raw-frame pre-spawn journey for no reason - real,
    ; needless per-frame overhead on real hardware (this test harness's
    ; own "unlimited speed" simulation never surfaced the cost). Same
    ; "skip the whole group while not relevant" shape as SKIP_ZACO_ENEMY/
    ; SKIP_OTHER_ENEMIES above, just gated the opposite way (skip while
    ; BOSS_ACT==0, not while nonzero).
    CALL UPDATE_BOSS_ALL
    LD A,(BOSS_ACT) : OR A
    JR Z,SKIP_BOSS_SUBSYSTEMS
    CALL CHECK_BULLET_VS_BOSS
    CALL CHECK_BULLET_VS_HORMING
    CALL UPDATE_HORMING_ALL
    CALL UPDATE_HORMING_BG_ALL
    CALL UPDATE_THUNDER
    CALL CHECK_THUNDER_VS_TANK
    CALL UPDATE_SBEAM
    CALL CHECK_SBEAM_VS_TANK
    ; round36-14 follow-up #4: the broken form's own 4-beam stop-attack.
    ; Firing/hiding itself already happens inside UPDATE_BOSS_ALL (via
    ; UPDATE_BOSS_BROKEN_ACTIVE's own beam-sequence dispatch, called
    ; above), so only the tank-collision check needs its own call here -
    ; same split as UPDATE_SBEAM(draw)/CHECK_SBEAM_VS_TANK(collision).
    ; round36-14 follow-up#5 real-hardware feedback ("かなり動作速度が
    ; 遅くなったが 無駄な処理が無いか確認...逆にボスまでにボスのみの
    ; 処理が回ってないか") - unlike Homing/Thunder/SBeam just above
    ; (which can have an in-flight instance launched BEFORE the broken-
    ; form transition that still needs updating afterward, so they can't
    ; be gated on BOSS_FORM), BOSS_BROKEN_PROJ_ACTIVE can ONLY ever be
    ; set by LAUNCH_BOSS_BROKEN_BEAM, which itself only ever runs from
    ; inside UPDATE_BOSS_BROKEN_ACTIVE (already gated on BOSS_FORM=
    ; ACTIVE, see UPDATE_BOSS_ALL's own dispatch) - so this call was
    ; provably a guaranteed no-op (all 4 slots always inactive) for the
    ; entire normal-form portion of the boss fight, same class of "運の
    ; 悪い全域無駄ループ" this file's own SKIP_ZACO_ENEMY/SKIP_BOSS_
    ; SUBSYSTEMS precedent already exists to eliminate - just gated the
    ; wrong way (missing a 3rd, narrower tier: boss-active-but-not-yet-
    ; broken). Skipping it here is a pure removal of dead work, not a
    ; behavior change (real reasoning above, not just plausible).
    LD A,(BOSS_FORM)
    CP BOSS_FORM_ACTIVE
    JR NZ,SKIP_BOSS_BROKEN_BEAM_CHECK
    CALL CHECK_BOSS_BROKEN_BEAM_VS_TANK
SKIP_BOSS_BROKEN_BEAM_CHECK:
SKIP_BOSS_SUBSYSTEMS:
    CALL CLOUD_UPDATE_ALL
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
    ; ordinary joystick movement/facing is fully suppressed while
    ; dashing (UPDATE_DASH drives TANK_X directly) - see DASH_ACTIVE's
    ; own comment.
    LD A,(DASH_ACTIVE)
    OR A
    RET NZ
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

; ---------- dash (down + B button, edge-triggered, 64px straight run) ----------
; "上下左右入力の下を入れたままジャンプのBボタンを押すと今向いてる方向
; に倍速で64px移動" - called BEFORE UPDATE_JUMP so a dash-starting press
; consumes this frame's "new B press" before UPDATE_JUMP's own edge-
; detection ever sees it (UPDATE_JUMP's own first action bails out
; while DASH_ACTIVE - see its own comment).
UPDATE_DASH:
    LD A,(DASH_ACTIVE)
    OR A
    JR NZ,UD_CONTINUE
    LD A,(JOY_TRIGB)
    LD HL,PREV_TRIGB
    CP (HL)
    RET Z                        ; no change - not a new press
    OR A
    RET Z                        ; released (0), not pressed - not a new press
    ; "斜め下でもダッシュできるように 現在は真下のみなんで" (round28) -
    ; widened from pure-down(5) only to also accept the 2 down-diagonals
    ; (4=downright,6=downleft), matching JOY_DIR's own compass numbering
    ; (0=none,1=up,2=upright,3=right,4=downright,5=down,6=downleft,
    ; 7=left,8=upleft). The dash's own MOVEMENT direction still comes
    ; from TANK_FACING below, unchanged - it's always a horizontal-only
    ; 64px run regardless of which "down" variant triggered it, exactly
    ; as before for pure-down.
    LD A,(JOY_DIR)
    CP 4 : JR Z,UD_DOWN_OK
    CP 5 : JR Z,UD_DOWN_OK
    CP 6 : JR Z,UD_DOWN_OK
    RET
UD_DOWN_OK:
    LD A,(JUMP_ACTIVE)
    OR A
    RET NZ                       ; already mid-jump - don't also start a dash
    LD A,1 : LD (DASH_ACTIVE),A
    LD A,(TANK_FACING) : LD (DASH_DIR),A
    LD A,DASH_DIST : LD (DASH_REMAINING),A
    RET
UD_CONTINUE:
    ; keep UPDATE_TERRAIN_COLLISION's own "actively steering" climb-
    ; easing engaged for the dash's own duration too, matching DASH_DIR
    ; (TANK_DX would otherwise sit stale at whatever it was the instant
    ; before the dash started).
    LD A,(DASH_DIR)
    OR A
    JR Z,UD_DX_RIGHT
    LD A,0FFh : LD (TANK_DX),A
    JR UD_DX_DONE
UD_DX_RIGHT:
    LD A,1 : LD (TANK_DX),A
UD_DX_DONE:
    LD A,(DASH_REMAINING) : LD B,A
    LD A,DASH_SPEED
    CP B
    JR C,UD_STEP_PARTIAL          ; DASH_SPEED < remaining - a normal mid-dash step
    ; final step - move exactly the remaining distance, then end
    LD A,B
    CALL UD_MOVE
    XOR A : LD (DASH_ACTIVE),A
    LD (TANK_DX),A
    LD A,(JOY_TRIGB) : LD (PREV_TRIGB),A   ; resync - a still-held B mustn't phantom-trigger a jump
    RET
UD_STEP_PARTIAL:
    LD A,DASH_SPEED
    CALL UD_MOVE
    LD A,(DASH_REMAINING) : SUB DASH_SPEED : LD (DASH_REMAINING),A
    RET

; A = px to move this step, DASH_DIR = direction. Clamps against the
; same screen edges ordinary movement respects (UTX_DO_RIGHT/_LEFT's own
; 224/underflow guards) so a dash can't run the tank off-screen.
UD_MOVE:
    LD B,A
    LD A,(DASH_DIR)
    OR A
    JR NZ,UD_MOVE_LEFT
    LD A,(TANK_X) : ADD A,B
    CP 225
    JR C,UD_MOVE_RIGHT_OK
    LD A,224
UD_MOVE_RIGHT_OK:
    LD (TANK_X),A
    RET
UD_MOVE_LEFT:
    LD A,(TANK_X)
    CP B
    JR NC,UD_MOVE_LEFT_OK
    XOR A : LD (TANK_X),A
    RET
UD_MOVE_LEFT_OK:
    SUB B : LD (TANK_X),A
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
    ; jump and dash are mutually exclusive - a dash-starting press must
    ; never ALSO start a jump the same frame (UPDATE_DASH runs first and
    ; sets DASH_ACTIVE before this routine's own edge-detection would
    ; otherwise see the same press) - see DASH_ACTIVE's own comment.
    LD A,(DASH_ACTIVE)
    OR A
    RET NZ
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
    ; "自機スプライトの上部32x16のスプライトを下に5px下げる" - TL/TR
    ; only, while dashing; BL/BR keep using TANK_DRAW_Y+16 unshifted
    ; below (see IX+8/IX+12) so the top visibly slides toward the
    ; bottom instead of the whole body moving down.
    LD A,(DASH_ACTIVE)
    OR A
    JR Z,UTS_TOPY_NORMAL
    LD A,(TANK_DRAW_Y) : ADD A,DASH_SPRITE_Y_SHIFT
    LD (TANK_TOP_DRAW_Y),A
    JR UTS_TOPY_DONE
UTS_TOPY_NORMAL:
    LD A,(TANK_DRAW_Y) : LD (TANK_TOP_DRAW_Y),A
UTS_TOPY_DONE:

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
    ; hit-flash: BigZum's own punch connecting is the tank's only
    ; discrete damage moment (see TANK_FLASH_TIMER's own comment) -
    ; overrides all 4 quadrant colors to white for the flash duration,
    ; same mechanism as every other HP-bearing entity's own flash.
    LD A,(TANK_FLASH_TIMER)
    OR A
    JR Z,UTS_FLASH_DONE
    DEC A : LD (TANK_FLASH_TIMER),A
    LD A,FLASH_COLOR
    LD (UTS_COLOR_0),A
    LD (UTS_COLOR_1),A
    LD (UTS_COLOR_2),A
    LD (UTS_COLOR_3),A
UTS_FLASH_DONE:
    ; TANK_HAZARD_IFRAMES' own once-per-frame countdown - see CHECK_
    ; THUNDER_VS_TANK's own comment for what this gates.
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    JR Z,UTS_HAZARD_DONE
    DEC A : LD (TANK_HAZARD_IFRAMES),A
UTS_HAZARD_DONE:

    LD IX,SPRITE_ATTRS
    LD A,(TANK_TOP_DRAW_Y) : LD (IX+0),A
    LD A,(TANK_X)     : LD (IX+1),A
    LD A,(CUR_POSE_PAT) : LD (IX+2),A
    LD A,(UTS_COLOR_0) : LD (IX+3),A

    LD A,(TANK_TOP_DRAW_Y) : LD (IX+4),A
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
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,SPRITE_ATTRS
    LD B,16
UTS_OUT_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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

    ; round36-11 ("1発目水平撃ちBulletFU、2発目FM、3発目FL...斜めも同様に
    ; UU、UM、ULで切り替え"): F and U each advance their own independent
    ; 0/1/2 rotation counter on every new shot of that type. F's variant
    ; is remembered per-slot (BULLET0/1/2_VARIANT, via SET_BULLET_
    ; VARIANT - DRAW_BULLET_CELL reads it back every time this slot
    ; redraws, not just at spawn) since up to 3 F shots can be on screen
    ; simultaneously, each showing its own distinct pose. U has no such
    ; per-slot memory - see WRITE_BULLETU_SPRITE_VARIANT's own comment
    ; for why (VRAM budget forced a single shared sprite pattern slot).
    LD A,(IX+1)
    OR A
    JR NZ,TSB_ROT_U
    LD A,(BULLETF_ROT_COUNTER)
    CALL SET_BULLET_VARIANT
    LD A,(BULLETF_ROT_COUNTER) : INC A : CP 3 : JR C,TSB_ROT_F_OK
    XOR A
TSB_ROT_F_OK:
    LD (BULLETF_ROT_COUNTER),A
    JR TSB_ROT_DONE
TSB_ROT_U:
    LD A,(BULLETU_ROT_COUNTER)
    CALL WRITE_BULLETU_SPRITE_VARIANT
    LD A,(BULLETU_ROT_COUNTER) : INC A : CP 3 : JR C,TSB_ROT_U_OK
    XOR A
TSB_ROT_U_OK:
    LD (BULLETU_ROT_COUNTER),A
TSB_ROT_DONE:

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

    ; F draws its BG cell immediately; U is normally a hw sprite instead
    ; (own position set later this frame by UPDATE_BULLET_U_SPRITES), but
    ; while BOSS_ACT!=0 U also draws its BG cell here immediately, same
    ; as F - "ボス戦になったら斜めショットをBG描画に変更".
    LD A,(IX+1)
    OR A
    JR Z,TSB_DRAW_F
    LD A,(BOSS_ACT)
    OR A
    JR Z,TSB_SPAWN_U
TSB_DRAW_F:
    CALL DRAW_BULLET_CELL
TSB_SPAWN_U:
    CALL SOUND_SHOT
    RET

; IX = bullet slot base (BULLET0_ACT/BULLET1_ACT/BULLET2_ACT), A = this
; slot's own F-rotation variant (0-2) to remember - see BULLET0_VARIANT's
; own comment for why this is 3 standalone bytes instead of a 4th slot
; field. IX is always exactly one of the 3 known constants here, so a
; plain 2-way compare (falling through to "must be slot2" otherwise) is
; enough - no general N-way dispatch needed.
SET_BULLET_VARIANT:
    PUSH HL
    PUSH DE
    PUSH IX : POP HL
    LD DE,BULLET0_ACT
    OR A : SBC HL,DE
    JR Z,SBV_0
    PUSH IX : POP HL
    LD DE,BULLET1_ACT
    OR A : SBC HL,DE
    JR Z,SBV_1
    LD (BULLET2_VARIANT),A
    JR SBV_DONE
SBV_0:
    LD (BULLET0_VARIANT),A
    JR SBV_DONE
SBV_1:
    LD (BULLET1_VARIANT),A
SBV_DONE:
    POP DE
    POP HL
    RET

; IX = bullet slot base - returns this slot's own remembered F-rotation
; variant (0-2) in A. Called every time DRAW_BULLET_CELL redraws an
; F-type bullet (not just at spawn), so a shot keeps showing the same
; pose for its whole flight instead of drifting onto whatever variant
; the rotation counter has advanced to since it spawned.
GET_BULLET_VARIANT:
    PUSH HL
    PUSH DE
    PUSH IX : POP HL
    LD DE,BULLET0_ACT
    OR A : SBC HL,DE
    JR Z,GBV_0
    PUSH IX : POP HL
    LD DE,BULLET1_ACT
    OR A : SBC HL,DE
    JR Z,GBV_1
    LD A,(BULLET2_VARIANT)
    JR GBV_DONE
GBV_0:
    LD A,(BULLET0_VARIANT)
    JR GBV_DONE
GBV_1:
    LD A,(BULLET1_VARIANT)
GBV_DONE:
    POP DE
    POP HL
    RET

; A = variant to make resident (0-2, BulletUU/UM/UL) - overwrites the
; single shared PAT_BULLETU/PAT_BULLETU_L hw sprite pattern slot in
; VRAM with that variant's 32-byte bitmap (both facings). See
; BULLET_U_SPR_BASE_SLOT's own comment for why there's only ever 1
; resident bitmap rather than 3 dedicated slots - this is what actually
; makes U's rotation visible, called once per diagonal shot spawn (not
; every frame), same DI/EI-wrapped LDIRVM-is-not-interrupt-safe
; precaution as this file's own LOAD_SASAPI_PATTERNS (which reloads a
; similarly shared/reused 64-slot range on boss facing changes).
WRITE_BULLETU_SPRITE_VARIANT:
    OR A
    JR Z,WBSV_0
    CP 1
    JR Z,WBSV_1
    DI
    LD HL,BULLET_U_SPRITE2 : LD DE,PAT_BULLETU*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BULLET_U_SPRITE2_L : LD DE,PAT_BULLETU_L*8+SPRPAT : LD BC,32 : CALL LDIRVM
    EI
    RET
WBSV_0:
    DI
    LD HL,BULLET_U_SPRITE0 : LD DE,PAT_BULLETU*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BULLET_U_SPRITE0_L : LD DE,PAT_BULLETU_L*8+SPRPAT : LD BC,32 : CALL LDIRVM
    EI
    RET
WBSV_1:
    DI
    LD HL,BULLET_U_SPRITE1 : LD DE,PAT_BULLETU*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BULLET_U_SPRITE1_L : LD DE,PAT_BULLETU_L*8+SPRPAT : LD BC,32 : CALL LDIRVM
    EI
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
    JR Z,UOB_DO_ERASE
    LD A,(BOSS_ACT)
    OR A
    JR Z,UOB_SKIP_ERASE
UOB_DO_ERASE:
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
    ; F always draws its BG cell here; U normally doesn't (positioned
    ; separately every frame by UPDATE_BULLET_U_SPRITES as a hw sprite
    ; instead), except while BOSS_ACT!=0 - "ボス戦になったら斜めショッ
    ; トをBG描画に変更".
    LD A,(IX+1)
    OR A
    JR Z,UOBD_DRAW
    LD A,(BOSS_ACT)
    OR A
    RET Z
UOBD_DRAW:
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
; "Sandskyのラインも夜対応に 今は夜の前に復元されてる" - once
; CHECK_NIGHT's own sweep reaches NIGHT_END_ROW(16, this same row),
; it overwrites row16's real on-screen content with NIGHT_CODE (the
; striped leading tile - see NIGHT_START_TICK's own comment, "stops
; once NIGHT_END_ROW itself becomes the leading row") and leaves it
; that way permanently - restoring the old SKYSAND_CODE unconditionally
; here was stale from that point on, leaving a wrong-tile patch behind
; a passing shot.
EBC_SKYSAND:
    LD A,(NIGHT_ROW)
    CP NIGHT_END_ROW
    JR C,EBC_SKYSAND_DAY   ; sweep hasn't reached row16 yet - still the real SkySand tile
    LD A,NIGHT_CODE
    JR EBC_WRITE
EBC_SKYSAND_DAY:
    LD A,SKYSAND_CODE
    JR EBC_WRITE
; "ショット水平打ちのBG復元カラーを夜になったらブラックに変更" - once
; CHECK_NIGHT's own sweep has already darkened this particular row
; (NIGHT_ROW>=this row - not just "is it night at all", since the
; sweep only covers 1 more row every 16 GAME_TICKs and a bullet could
; be flying through a row the sweep hasn't reached yet), restore
; HUD_ROW_BLANK_CODE(black) instead of the ordinary SKY_BLANK_CODE so
; an erased shot trail doesn't leave a stray blue patch in the
; already-dark sky.
EBC_SKY:
    LD A,(IX+3) : LD B,A
    LD A,(NIGHT_ROW)
    CP B
    JR C,EBC_SKY_BLUE      ; NIGHT_ROW<row - not reached by the sweep yet
    LD A,HUD_ROW_BLANK_CODE
    JR EBC_WRITE
EBC_SKY_BLUE:
    LD A,SKY_BLANK_CODE
EBC_WRITE:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    CALL WRITE_BULLET_BYTE_HL
EBC_SKIP:
    RET

; IX = slot base. F always; U too while BOSS_ACT!=0 (see TRY_SPAWN_BULLET/
; UPDATE_ONE_BULLET's own call-site gating - "ボス戦になったら斜めショ
; ットをBG描画に変更"). Picks the pattern code for (background-under-
; current-row x FACING x bullet TYPE) and writes it at ADDR+COL.
DRAW_BULLET_CELL:
    LD A,(IX+3)
    CP BULLET_ROCK_COLOR_ROW_MIN_F
    JR NC,DBC_ROCK

    ; "Skysandとその上の行でショットの背景色をブラックにすれば良い" -
    ; night-black glyph for the whole sky+SkySand band (rows0-16, same
    ; range this branch already covers) once the sweep has darkened
    ; this specific row - see BULLETF_NIGHT_CODE's own comment.
    LD A,(IX+3) : LD B,A
    LD A,(NIGHT_ROW)
    CP B
    JR C,DBC_SKY            ; NIGHT_ROW<row - not dark here yet
    LD A,(IX+1)
    OR A
    JR NZ,DBC_NIGHT_U
    CALL GET_BULLET_VARIANT
    LD B,A
    LD A,(IX+6)
    OR A
    JR NZ,DBC_NIGHT_LEFT
    LD HL,BULLETF_NIGHT_CODE_TABLE
    JR DBC_NIGHT_PICK
DBC_NIGHT_LEFT:
    LD HL,BULLETF_L_NIGHT_CODE_TABLE
DBC_NIGHT_PICK:
    CALL PICK_VARIANT_CODE
    JR DBC_CODE_SET
DBC_NIGHT_U:
    LD A,(IX+6)
    OR A
    JR NZ,DBC_NIGHT_U_LEFT
    LD A,BULLETU_NIGHT_CODE
    JR DBC_CODE_SET
DBC_NIGHT_U_LEFT:
    LD A,BULLETU_L_NIGHT_CODE
    JR DBC_CODE_SET

; round36-11 ("ローテーションさせる"): F's own sky/rock code now depends
; on which of the 3 rotation variants this slot was spawned with (see
; GET_BULLET_VARIANT's own comment) - looked up via PICK_VARIANT_CODE
; against a 3-byte table instead of a single fixed EQU. U's own BG-cell
; fallback (used only while BOSS_ACT!=0) is unaffected - still a single
; non-rotating code, same as before round36-11 - see BULLETU_SKY_CODE's
; own comment for why.
DBC_SKY:
    LD A,(IX+1)
    OR A
    JR NZ,DBC_SKY_U
    CALL GET_BULLET_VARIANT
    LD B,A
    LD A,(IX+6)
    OR A
    JR NZ,DBC_SKY_LEFT
    LD HL,BULLETF_SKY_CODE_TABLE
    JR DBC_SKY_PICK
DBC_SKY_LEFT:
    LD HL,BULLETF_L_SKY_CODE_TABLE
DBC_SKY_PICK:
    CALL PICK_VARIANT_CODE
    JR DBC_CODE_SET
DBC_SKY_U:
    LD A,(IX+6)
    OR A
    JR NZ,DBC_SKY_U_LEFT
    LD A,BULLETU_SKY_CODE
    JR DBC_CODE_SET
DBC_SKY_U_LEFT:
    LD A,BULLETU_L_SKY_CODE
    JR DBC_CODE_SET

DBC_ROCK:
    LD A,(IX+1)
    OR A
    JR NZ,DBC_ROCK_U
    CALL GET_BULLET_VARIANT
    LD B,A
    LD A,(IX+6)
    OR A
    JR NZ,DBC_ROCK_LEFT
    LD HL,BULLETF_ROCK_CODE_TABLE
    JR DBC_ROCK_PICK
DBC_ROCK_LEFT:
    LD HL,BULLETF_L_ROCK_CODE_TABLE
DBC_ROCK_PICK:
    CALL PICK_VARIANT_CODE
    JR DBC_CODE_SET
DBC_ROCK_U:
    LD A,(IX+6)
    OR A
    JR NZ,DBC_ROCK_U_LEFT
    LD A,BULLETU_ROCK_CODE
    JR DBC_CODE_SET
DBC_ROCK_U_LEFT:
    LD A,BULLETU_L_ROCK_CODE
DBC_CODE_SET:
    LD (BULLET_TEMP_BYTE),A
    LD L,(IX+4) : LD H,(IX+5)
    LD E,(IX+2) : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL

; B = variant (0-2), HL = 3-byte code table base for this color+facing.
; Returns the picked code in A. B is a plain 0-2 index (GET_BULLET_
; VARIANT's own range), so a direct add is enough - no bounds check.
PICK_VARIANT_CODE:
    LD A,B
    LD E,A : LD D,0
    ADD HL,DE
    LD A,(HL)
    RET

BULLETF_SKY_CODE_TABLE:
    DB BULLETF_SKY_CODE0,BULLETF_SKY_CODE1,BULLETF_SKY_CODE2
BULLETF_L_SKY_CODE_TABLE:
    DB BULLETF_L_SKY_CODE0,BULLETF_L_SKY_CODE1,BULLETF_L_SKY_CODE2
BULLETF_ROCK_CODE_TABLE:
    DB BULLETF_ROCK_CODE0,BULLETF_ROCK_CODE1,BULLETF_ROCK_CODE2
BULLETF_L_ROCK_CODE_TABLE:
    DB BULLETF_L_ROCK_CODE0,BULLETF_L_ROCK_CODE1,BULLETF_L_ROCK_CODE2
BULLETF_NIGHT_CODE_TABLE:
    DB BULLETF_NIGHT_CODE0,BULLETF_NIGHT_CODE1,BULLETF_NIGHT_CODE2
BULLETF_L_NIGHT_CODE_TABLE:
    DB BULLETF_L_NIGHT_CODE0,BULLETF_L_NIGHT_CODE1,BULLETF_L_NIGHT_CODE2

; writes (BULLET_TEMP_BYTE) to VRAM address HL - raw DI-wrapped OUT
; (same pattern as UPDATE_TANK_SPRITES/INIT_SPRATR_CLR above), since
; this runs every frame with EI active (no per-frame HALT - see
; MAINLOOP) and LDIRVM has no interrupt-safety margin for that.
; "98hは表示中アクセスでは29T必要なのでNOPは8回 しかし99hは8Tで良いこ
; とになってるのでNOPは2回で問題ない 表示期間非常時期間とも同一" -
; real TMS9918 VDP timing: the 99h control-port writes (setting the
; VRAM address, 2 bytes) only need 8T of recovery, not the 29T the 98h
; data-port write itself needs - was uniformly 8 NOPs for both ports
; everywhere in this file (a real, if harmless, waste - every single
; raw VDP write anywhere in the game paid the data port's own stricter
; margin twice over for its own address-setup bytes too), trimmed the
; 99h ones to 2 NOPs. Same for both the active-display and blanking
; periods (no separate rule for either), so no per-call branching
; needed - just a flat NOP-count change, verified against a fixed
; T-state budget by tests/vdp_wait_test.py (counts real NOPs per OUT,
; not just "does the game still behave the same" - a wrong count here
; would be invisible to every other test in this whole file, since none
; of them model VDP access timing at all, only the actual byte written).
;
; The 98h data-port write itself still genuinely needs the full 29T,
; but "現在Nopx8つだがこれをサイズの小さいダミー命令に置き換える...29T
; に近くなる影響がほぼ無い命令の組み合わせで フラグ変化がある場合は周
; 辺のチェック" (round27) - 8 NOPs is 8 bytes for 32T (already 3T more
; than needed, by the user's own count). First attempt used `PUSH BC :
; POP BC : INC HL : DEC HL` (11+10+6+6=33T) - correctly caught as an
; actual regression ("33Tでは現状の32Tより遅くなるじゃねえか" - 33T is
; SLOWER than the 32T it was replacing, missing the entire point of a
; speed optimization even though it did shrink the byte count). Fixed:
; `PUSH BC : POP BC : NOP : NOP` (11+10+4+4=29T EXACTLY - the true
; minimum, 3T faster than the original 8-NOP version) - same 4 bytes,
; now genuinely both smaller AND faster. None of these 4 opcodes touch
; any flag on real Z80 (PUSH/POP never do; NOP obviously doesn't), and
; PUSH BC/POP BC nets to an exactly restored BC value via the stack
; round-trip - transparent to whatever the surrounding code holds in
; either register, regardless of call site. PUSH/POP BC specifically
; (not raw SP+-1) so a real NMI landing mid-sequence can't leave SP
; pointing at a garbage slot - PUSH/POP always keeps the stack self-
; consistent even if something interjects on top of it. `EX (SP),HL`
; would have been an even denser single-opcode 19T/1-byte pair (2 of
; them = 38T/2 bytes, though that's actually MORE T-states than this 4-
; byte/29T solution, not fewer) but isn't implemented in this project's
; own mini_z80asm.py/z80emu.py toolchain anyway, so moot either way.
; Verified equivalence (T-state count AND that BC/HL/flags really do
; come out identical to their pre-sequence values) by tests/
; vdp_wait_test.py; the shrink from 8 to 4 bytes at every one of the 20
; sites (80 bytes total) also lets the assembler naturally re-resolve
; any JR/DJNZ that's now back in range where it wasn't before - see
; mini_z80asm.py's own real 8-bit-signed-offset range check, which
; would simply fail the build if anything drifted OUT of range instead.
WRITE_BULLET_BYTE_HL:
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(BULLET_TEMP_BYTE) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    RET

; writes HUD_VAL to the name-table cell at (HUD_ROW,HUD_COL) - row0/1
; only, so unlike WRITE_ANIM_CELL in src/CYBER SHMUP.asm there's no
; NAMEBUF mirror to keep in sync (the ground scroller only ever
; touches rows20-23). Same raw DI-wrapped NOP-padded OUT pattern as
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
    LD A,H : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,(HUD_VAL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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

; draws TANK_LIFE(0-LIFE_BAR_CELL_COUNT) at row LIFE_BAR_ROW, cols
; LIFE_BAR_COL0..+LIFE_BAR_CELL_COUNT-1 - always redraws all cells (same
; "just redraw everything" shape as SCORE_DISPLAY, not an incremental
; diff like GAME_TICK_DISPLAY - life
; only changes on a discrete hit, not every frame, so there's no
; per-frame cost to worry about). Filled cells are always the LEFTMOST
; `life` of the 6 - blank ones peel off from the right as life drops,
; "表示は右から減ってくように".
LIFE_DISPLAY:
    LD A,(TANK_LIFE) : LD B,A
    LD C,0
LFD_LOOP:
    LD A,LIFE_BAR_ROW : LD (HUD_ROW),A
    LD A,C : ADD A,LIFE_BAR_COL0 : LD (HUD_COL),A
    LD A,C : CP B
    JR NC,LFD_BLANK
    LD A,LIFE_CODE : LD (HUD_VAL),A
    JR LFD_SET
LFD_BLANK:
    LD A,HUD_ROW_BLANK_CODE : LD (HUD_VAL),A
LFD_SET:
    CALL WRITE_HUD_CELL
    INC C
    LD A,C : CP LIFE_BAR_CELL_COUNT
    JR C,LFD_LOOP
    RET

; decrements TANK_LIFE by 1, floored at 0 ("今は0になっても死なない" -
; no death handling yet, just stop counting down), then redraws the
; life bar. Called from both of UPDATE_TANK_BIGZUM_PUNCH's own hit
; branches (front/behind) - "現在はBigZumのみだがいずれ敵弾実装予定"
; (future enemy-bullet damage sources will call this same routine).
APPLY_TANK_DAMAGE:
    LD A,(TANK_LIFE)
    OR A
    RET Z
    DEC A : LD (TANK_LIFE),A
    JP LIFE_DISPLAY

; Converts GAME_TICK to 3 decimal digits and draws them at row0
; cols29-31 - ported from src/CYBER SHMUP.asm's own GAME_TICK_DISPLAY
; (called every frame there too, same as here), but no longer a MOD
; 1000 wrap once GAME_TICK exceeds 999. round34-2 ("Tickは999終了で
; 繰り返さない"): the real GAME_TICK keeps counting normally past 999
; forever (its own internal timing math - boss pause/pose end-ticks
; etc - needs that, see the real GAME_TICK increment's own comment),
; but a plain MOD 1000 readout would visibly wrap the on-screen counter
; back to "000" and keep climbing again past that - exactly the "また
; スタートから出てきてしまってる" (looks like it started over) symptom
; reported, since GAME_TICK can push past 1000 well before the boss's
; own late-schedule threshold is reached.
; Clamps the DISPLAY at 999 once GAME_TICK reaches/exceeds 1000 -
; "見た目上999で止まる" - purely cosmetic, the real counter and every
; tick-threshold comparison elsewhere are completely unaffected.
GAME_TICK_DISPLAY:
    LD HL,(GAME_TICK)
    LD DE,1000
    OR A
    SBC HL,DE
    JR C,GTD_UNDER1000
    LD HL,999
    LD B,0
    JR GTD_H100
GTD_UNDER1000:
    ADD HL,DE   ; undo the SBC above - HL was GAME_TICK-1000, +1000 restores GAME_TICK (0-999)
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

; advances the night-transition by at most 1 row per call - called
; once every 8 raw frames alongside GAME_TICK_DISPLAY itself (same
; cadence GAME_TICK advances on), so it can never skip a 16-tick
; boundary. See NIGHT_START_TICK's own comment for the full design.
CHECK_NIGHT:
    LD A,(NIGHT_ROW)
    CP NIGHT_END_ROW
    RET Z                      ; already reached the final row - done for good
    LD HL,(GAME_TICK)
    LD DE,(NIGHT_NEXT_TICK)
    OR A
    SBC HL,DE
    RET C                      ; not yet time for the next row

    LD A,(NIGHT_ROW)
    OR A
    JR Z,CN_FIRST
    ; solidify the previous leading row to plain black
    CALL NIGHT_ROW_ADDR
    LD HL,HUD_BLACKROW32 : LD BC,32 : CALL LDIRVM
    LD A,(NIGHT_ROW) : INC A
    JR CN_SET_ROW
CN_FIRST:
    LD A,NIGHT_START_ROW
CN_SET_ROW:
    LD (NIGHT_ROW),A
    CALL NIGHT_ROW_ADDR
    LD HL,NIGHT_STRIPEROW32 : LD BC,32 : CALL LDIRVM

    LD HL,(NIGHT_NEXT_TICK) : LD DE,NIGHT_INTERVAL : ADD HL,DE
    LD (NIGHT_NEXT_TICK),HL
    RET

; A=row(0-23) -> DE=1800h+row*32, the name-table address of that row's
; own first column. Trashes HL.
NIGHT_ROW_ADDR:
    LD L,A : LD H,0
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL   ; *32
    LD DE,1800h : ADD HL,DE
    LD D,H : LD E,L
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
    LD A,1 : LD (SND_NOISE),A
    RET

; short "crackle" blip for the SPARK burst - "爆発エフェクト中も爆発音
; 追加" (see SPARK_CRACKLE_PERIOD's own comment). Same casual-sound
; shape as SOUND_SHOT above (no SND_EXPLODING guard/set - this doesn't
; protect itself from being cut off by anything, nor does it protect
; anything else from being cut off by it).
SOUND_SPARK_CRACKLE:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,SPARK_CRACKLE_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,SPARK_CRACKLE_PEAK : LD (SND_TIMER),A
    LD A,SPARK_CRACKLE_DECAY : LD (SND_DECAY),A
    LD A,1 : LD (SND_NOISE),A
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
    LD A,1 : LD (SND_NOISE),A
    RET

; "キンキン" metallic ping for a bullet absorbed by Zum's own front
; invincibility - "Zumの前面無敵に弾が当たったらキンキンと言うサウンド
; 追加 これはStage1のボスの弾き音流用". Channel A tone period(10) still
; byte-for-byte src/CYBER SHMUP.asm's own SOUND_POD_HIT (registers 0/1
; instead of that routine's own 4/5, since this now plays on channel A
; rather than a dedicated C). Peak 15 (was 12, then 12 again - "キンキン
; 音量アップ" - now the PSG's own hardware max, register8's volume
; field only has 4 bits/16 steps so there's no higher to go), decays
; 1/frame. TONE, not noise - "ではノイズ使ってる全てのSEをデューティ比
; の音量操作を適用してみて" (round32) explicitly scopes the on/off
; gating to noise sounds; a held metallic ping reads wrong chopped up
; on/off, so this is the one sound that sets SND_NOISE=0 (see that
; byte's own comment).
SOUND_ZUM_DEFLECT:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_TONE_A : OUT (PSG_DATA),A
    LD A,0 : OUT (PSG_ADDR),A
    LD A,10 : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    LD A,1 : LD (SND_DECAY),A
    XOR A : LD (SND_EXPLODING),A
    XOR A : LD (SND_NOISE),A
    RET

; "円の爆発はノイズでどーーーーんって長いやつ" - the boss's own circle-
; explosion boom, triggered once at the SPARK->GROW handoff (see UBS_
; LAST_FRAME) - right as the circle itself starts growing. Channel A,
; noise, same shared-envelope bytes (SND_TIMER/SND_DECAY) every other
; sound here uses, but SND_DECAY=0 is a sentinel no ordinary sound ever
; sets (SHOT/DESTROY/DEFLECT all use 1 or 2) that switches SOUND_UPDATE
; over to its own SU_BOOM branch - see that routine's own comment for
; the actual long-decay mechanism (the duty-cycle gating itself is now
; shared by every noise sound, see SOUND_CALC_NOISE_GATE_VOLUME below).
; Same SND_EXPLODING guard as SOUND_DESTROY (blocks the shot sound from
; cutting it off early).
SOUND_BOSS_BOOM:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,BOSS_BOOM_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    XOR A : LD (SND_DECAY),A
    LD A,BOSS_BOOM_DECAY_PERIOD : LD (SND_BOOM_DECAY_CTR),A
    LD A,1 : LD (SND_EXPLODING),A
    LD A,1 : LD (SND_NOISE),A
    RET

; single shared channel-A envelope for every sound above - writes
; SOUND_CALC_NOISE_GATE_VOLUME's own output (register8, 0-15) every
; frame, then steps SND_TIMER toward 0 by SND_DECAY (clamped so it can't
; undershoot past 0 - see SOUND_SHOT/SOUND_DESTROY/SOUND_ZUM_DEFLECT for
; how each sound picks its own peak/decay pair when triggered).
; SND_DECAY==0 means "boom mode" instead (see SOUND_BOSS_BOOM's own
; comment) - branches into SU_BOOM below rather than this linear path.
SOUND_UPDATE:
    LD A,(SND_DECAY)
    OR A
    JR Z,SU_BOOM

    CALL SOUND_CALC_NOISE_GATE_VOLUME
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

; out: A = this frame's output volume, gated by the 1:1 on/off duty
; cycle if the CURRENTLY playing sound is noise (SND_NOISE=1), or just
; the raw envelope if it's tone (SND_NOISE=0, SOUND_ZUM_DEFLECT only) -
; "ではノイズ使ってる全てのSEをデューティ比の音量操作を適用してみて"
; (round32) - originally boom-only (as BOSS_BOOM_CALC_VOLUME), now
; shared by every noise sound in this file. "デューティ比1:1で減衰し
; ながらボリューム半分かOFFをまぜてくれ そうすればブリブリって音になる
; はず" - gated frames alternate every single frame between the FULL
; current envelope and silence, using TICK's own low bit as the toggle
; (a free-running per-frame flip - no dedicated toggle byte needed);
; "半分" (half) was tried and dropped (round32 follow-up: "音量最大か?
; かなり小さいが" - halving on top of the duty cycle's own 50% silent
; time never reached the hardware's real max on any frame). A pure
; function of SND_TIMER/SND_NOISE/TICK only - no side effects, doesn't
; touch the PSG or step the envelope itself - kept standalone
; specifically so it's directly testable without needing to observe an
; actual PSG register write (z80emu.py has no PSG emulation at all).
SOUND_CALC_NOISE_GATE_VOLUME:
    LD A,(SND_NOISE)
    OR A
    JR Z,SCNGV_RAW
    LD A,(TICK) : AND 1
    JR NZ,SCNGV_SILENT
SCNGV_RAW:
    LD A,(SND_TIMER)
    RET
SCNGV_SILENT:
    XOR A
    RET

; boom-mode envelope (SND_DECAY==0, see SOUND_BOSS_BOOM's own comment) -
; writes SOUND_CALC_NOISE_GATE_VOLUME's own output every frame, then
; steps the underlying envelope down by 1 every BOSS_BOOM_DECAY_PERIOD
; frames (not every frame, unlike the linear path above) - stretching a
; still-15-step decay out over many more real frames - "長いやつ".
SU_BOOM:
    CALL SOUND_CALC_NOISE_GATE_VOLUME
    LD B,A
    LD A,8 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A

    LD A,(SND_TIMER)
    OR A
    RET Z

    LD A,(SND_BOOM_DECAY_CTR) : DEC A : LD (SND_BOOM_DECAY_CTR),A
    RET NZ
    LD A,BOSS_BOOM_DECAY_PERIOD : LD (SND_BOOM_DECAY_CTR),A
    LD A,(SND_TIMER) : DEC A : LD (SND_TIMER),A
    OR A
    RET NZ
    LD (SND_EXPLODING),A
    RET

; ---------- boss attack SFX (round36-14 follow-up#5) ----------
; ホーミング発射音「バシュ」- ノイズ、短く明るく、ゲート有り。
; UPDATE_HORMING_VOLLEY's own UHV_FIRE calls this once per tick (a pair
; of missiles launches together, sprite pool + BG pool), not once per
; individual FIRE_ONE_HORMING/_BG call - calling it from both would just
; re-arm the identical envelope twice on the same frame for no audible
; difference, so the shared dispatch point is the cleaner call site.
SOUND_HORMING:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,HORMING_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    LD A,HORMING_SND_DECAY : LD (SND_DECAY),A
    XOR A : LD (SND_EXPLODING),A
    LD A,1 : LD (SND_NOISE),A
    RET

; サンダー発射音「雷鳴」- SOUND_BOSS_BOOM と全く同じ「boomモード」
; (SND_DECAY=0、BOSS_BOOM_DECAY_PERIODで1段ずつ減衰)を再利用、ノイズ
; ピッチのみ差し替え。SND_EXPLODING は立てない(自身のコメント参照)。
SOUND_THUNDER:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,THUNDER_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    XOR A : LD (SND_DECAY),A
    LD A,BOSS_BOOM_DECAY_PERIOD : LD (SND_BOOM_DECAY_CTR),A
    XOR A : LD (SND_EXPLODING),A
    LD A,1 : LD (SND_NOISE),A
    RET

; サンダービーム発射音「ビビビー」- トーンch(SOUND_ZUM_DEFLECTと同じ
; MIXER_TONE_A)に、通常はノイズ専用のデューティゲート(SND_NOISE=1)を
; あえて適用 - 60fps更新の下で作れる最速の振幅変調がこの1:1ゲートその
; ものなので、新規のゲートモードを増やさずそのまま流用するだけで
; プロトタイプのS1が狙っていた「ビビビー」感を再現できる。
SOUND_SBEAM:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_TONE_A : OUT (PSG_DATA),A
    LD A,0 : OUT (PSG_ADDR),A
    LD A,SBEAM_SND_TONE_PERIOD : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    LD A,SBEAM_SND_DECAY : LD (SND_DECAY),A
    XOR A : LD (SND_EXPLODING),A
    LD A,1 : LD (SND_NOISE),A
    RET

; ササピーレーザー(SasapiBroken停止中4方向ビーム)発射音 - 指示通り
; src/CYBER SHMUP.asmのSOUND_SHOTを流用、トーンピッチ(period30)は実値
; そのまま。L3の選定通りデューティゲートを追加(Stage1本来は無し)、
; ピークは"それぞれ音量は最大で"により15。
SOUND_SASAPI_LASER:
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_TONE_A : OUT (PSG_DATA),A
    LD A,0 : OUT (PSG_ADDR),A
    LD A,SASAPI_LASER_TONE_PERIOD : OUT (PSG_DATA),A
    LD A,1 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    LD A,15 : LD (SND_TIMER),A
    LD A,SASAPI_LASER_SND_DECAY : LD (SND_DECAY),A
    XOR A : LD (SND_EXPLODING),A
    LD A,1 : LD (SND_NOISE),A
    RET

; ---------- Stage2 spawn schedule (round34, "全てスケジュールに") ----------
; table-driven spawning, ported from src/CYBER SHMUP.asm's own
; SPAWN_THRESHOLDS/SPAWN_NEXT_INDEX/SSC_FIRE/SPAWN_SCHEDULE_CHECK
; (Stage1). SPAWN2_THRESHOLDS/SPAWN2_Y_TABLE are transcribed directly,
; index-for-index, from the schedule editor's own exported Stage2 JSON
; (tools/schedule-editor.html, Schedule2.json - "Schedule2_7.json" as
; supplied for round36-9, "これで組み込んでみてくれ" - the user's own
; edited schedule+terrain, replacing round34-3's "Schedule2_2.json"),
; sorted by tick then row exactly like the editor's own currentJSON()
; already sorts it. SPAWN2_Y_TABLE holds
; each entry's own row*8 (pixel Y) - consumed by the 2 free-Y types
; (ZacoII/Flyer, via S2_SPAWN_Y) and simply ignored by the 3 ground
; types (Zum/BigZum/Etank, whose own Y always comes from the terrain/
; tier-follow logic instead - see each ALLOC_*_SLOT's own comment).
;
; GAME_TICK only advances once per 8 raw frames (see its own INIT-area
; comment) - SPAWN2_SCHEDULE_CHECK is called once there, right
; alongside it (MAINLOOP), same cadence Stage1's own SPAWN_SCHEDULE_
; CHECK uses.
;
; round34-3 (real-hardware feedback: "Tick500あたりから100Tick以上敵が
; 出てこない/Bigzumが一度も出てこない/ボスも999になっても出ない/やって
; ることはStage1と全く同じ処理だぞ"): the previous round's own
; SPAWN2_STALL_LIMIT safety valve was the actual bug, not a fix - it was
; built to solve a problem that a DIFFERENT round34-2 change (removing
; the ground-lane exclusion) already made moot, but its own 60-tick
; timeout turned out far too short for the terrain-gated types (Zum/
; BigZum/Etank - see their own TERRAIN_OK checks), whose own flat-ground
; window can legitimately take longer than 60 ticks to cycle back around
; as the track scrolls. Every BigZum entry landing on an unlucky terrain
; window got silently force-skipped before its own condition ever had a
; real chance to become true - "BigZumが一度も出てこない" exactly, and 2
; adjacent BigZum entries (this schedule's own tick487/500) each burning
; the full 60-tick timeout accounts for the reported ~100-tick dead
; stretch around tick500 too (nothing else in the schedule could fire
; either, since SPAWN2_NEXT_INDEX was stuck on those 2 in turn).
;
; Correct fix, and the literal answer to "同じ処理をしろ": SSC2_FIRE now
; matches Stage1's own SSC_FIRE byte-for-byte in shape - SPAWN2_NEXT_
; INDEX advances UNCONDITIONALLY, before dispatch, every single time an
; entry comes due, exactly like Stage1's own `INC A:LD(SPAWN_NEXT_
; INDEX),A:DEC A` idiom. A spawn that can't happen this instant (pool
; full/terrain not flat) is simply DROPPED, not retried - the schedule
; itself never waits on anything, so nothing can ever stall it, and
; nothing later (down to the boss, the very last entry) can ever be held
; hostage by an earlier one. No timeout, no stall counter, no separate
; "force skip" path needed - it's the same one unconditional advance
; every time. This is strictly simpler than the previous 2 rounds' own
; retry-until-success design, not just a bugfix.
SPAWN2_SCHEDULE_CHECK:
    LD A,(SPAWN2_NEXT_INDEX)
    CP SPAWN2_COUNT
    RET NC
    LD H,0 : LD L,A
    ADD HL,HL
    LD DE,SPAWN2_THRESHOLDS
    ADD HL,DE
    LD E,(HL) : INC HL : LD D,(HL)
    LD HL,(GAME_TICK)
    OR A
    SBC HL,DE
    RET C
    JP SSC2_FIRE

; unconditionally advances SPAWN2_NEXT_INDEX (same "INC, dispatch on the
; OLD value" idiom as Stage1's own SSC_FIRE), stages this firing's own
; pixel Y before dispatch (harmless for the 3 ground types, which never
; read S2_SPAWN_Y), then dispatches on the pre-increment index. Whatever
; ALLOC_*_SLOT/SPAWN_S2_* is dispatched to just RETs when it's done,
; success or not - the index has already moved on regardless, so there's
; nothing left for it to signal. The very last entry (boss) needs no CP
; at all - once every earlier index has fired (dropped or not), SPAWN2_
; NEXT_INDEX can only be SPAWN2_COUNT-1 here, so dispatch just jumps
; unconditionally to S2_BOSS_SPAWN at the end of the CP chain below,
; same convention as Stage1's own SSC_FIRE/BOSS_SPAWN (there a physical
; fallthrough since BOSS_SPAWN sits right after the CP chain in that
; file; here an explicit JP, since S2_BOSS_SPAWN lives elsewhere, inside
; UPDATE_BOSS_ALL's own section).
SSC2_FIRE:
    LD A,(SPAWN2_NEXT_INDEX)
    INC A
    LD (SPAWN2_NEXT_INDEX),A
    DEC A
    LD H,0 : LD L,A
    LD DE,SPAWN2_Y_TABLE
    ADD HL,DE
    LD A,(HL)
    LD (S2_SPAWN_Y),A
    LD A,(SPAWN2_NEXT_INDEX)
    DEC A
; SSC2_FIRE dispatch chain body (excludes the last/boss entry, jumped
; to unconditionally at the end of this chain instead - see above)
    CP 0   : JP Z,SPAWN_S2_ZACOII
    CP 1   : JP Z,SPAWN_S2_ZACOII
    CP 2   : JP Z,SPAWN_S2_ZACOII
    CP 3   : JP Z,SPAWN_S2_ZACOII
    CP 4   : JP Z,SPAWN_S2_ZACOII
    CP 5   : JP Z,ALLOC_FLYER_SLOT
    CP 6   : JP Z,ALLOC_FLYER_SLOT
    CP 7   : JP Z,SPAWN_S2_ZACOII
    CP 8   : JP Z,SPAWN_S2_ZACOII
    CP 9   : JP Z,SPAWN_S2_ZACOII
    CP 10  : JP Z,SPAWN_S2_ZACOII
    CP 11  : JP Z,SPAWN_S2_ZACOII
    CP 12  : JP Z,SPAWN_S2_ZACOII
    CP 13  : JP Z,SPAWN_S2_ZACOII_RED
    CP 14  : JP Z,ALLOC_ZUM_SLOT
    CP 15  : JP Z,ALLOC_ZUM_SLOT
    CP 16  : JP Z,ALLOC_FLYER_SLOT
    CP 17  : JP Z,ALLOC_ZUM_SLOT
    CP 18  : JP Z,SPAWN_S2_ZACOII
    CP 19  : JP Z,SPAWN_S2_ZACOII
    CP 20  : JP Z,SPAWN_S2_ZACOII
    CP 21  : JP Z,ALLOC_ETANK_SLOT
    CP 22  : JP Z,SPAWN_S2_ZACOII
    CP 23  : JP Z,SPAWN_S2_ZACOII
    CP 24  : JP Z,ALLOC_FLYER_SLOT
    CP 25  : JP Z,SPAWN_S2_ZACOII
    CP 26  : JP Z,SPAWN_S2_ZACOII
    CP 27  : JP Z,SPAWN_S2_ZACOII
    CP 28  : JP Z,ALLOC_BIGZUM_SLOT
    CP 29  : JP Z,SPAWN_S2_ZACOII
    CP 30  : JP Z,SPAWN_S2_ZACOII
    CP 31  : JP Z,SPAWN_S2_ZACOII
    CP 32  : JP Z,ALLOC_FLYER_SLOT
    CP 33  : JP Z,ALLOC_FLYER_SLOT
    CP 34  : JP Z,ALLOC_ZUM_SLOT
    CP 35  : JP Z,SPAWN_S2_ZACOII_RED
    CP 36  : JP Z,ALLOC_ZUM_SLOT
    CP 37  : JP Z,ALLOC_ZUM_SLOT
    CP 38  : JP Z,ALLOC_ETANK_SLOT
    CP 39  : JP Z,SPAWN_S2_ZACOII
    CP 40  : JP Z,SPAWN_S2_ZACOII
    CP 41  : JP Z,SPAWN_S2_ZACOII
    CP 42  : JP Z,SPAWN_S2_ZACOII
    CP 43  : JP Z,SPAWN_S2_ZACOII
    CP 44  : JP Z,SPAWN_S2_ZACOII
    CP 45  : JP Z,SPAWN_S2_ZACOII
    CP 46  : JP Z,SPAWN_S2_ZACOII
    CP 47  : JP Z,ALLOC_FLYER_SLOT
    CP 48  : JP Z,ALLOC_FLYER_SLOT
    CP 49  : JP Z,ALLOC_BIGZUM_SLOT
    CP 50  : JP Z,SPAWN_S2_ZACOII
    CP 51  : JP Z,SPAWN_S2_ZACOII
    CP 52  : JP Z,SPAWN_S2_ZACOII
    CP 53  : JP Z,SPAWN_S2_ZACOII
    CP 54  : JP Z,SPAWN_S2_ZACOII
    CP 55  : JP Z,SPAWN_S2_ZACOII
    CP 56  : JP Z,SPAWN_S2_ZACOII
    CP 57  : JP Z,SPAWN_S2_ZACOII
    CP 58  : JP Z,SPAWN_S2_ZACOII
    CP 59  : JP Z,SPAWN_S2_ZACOII_RED
    CP 60  : JP Z,ALLOC_FLYER_SLOT
    CP 61  : JP Z,SPAWN_S2_ZACOII
    CP 62  : JP Z,SPAWN_S2_ZACOII
    CP 63  : JP Z,SPAWN_S2_ZACOII
    CP 64  : JP Z,SPAWN_S2_ZACOII
    CP 65  : JP Z,SPAWN_S2_ZACOII
    CP 66  : JP Z,SPAWN_S2_ZACOII
    CP 67  : JP Z,SPAWN_S2_ZACOII
    CP 68  : JP Z,ALLOC_ZUM_SLOT
    CP 69  : JP Z,ALLOC_ZUM_SLOT
    CP 70  : JP Z,ALLOC_ETANK_SLOT
    CP 71  : JP Z,ALLOC_BIGZUM_SLOT
    CP 72  : JP Z,ALLOC_FLYER_SLOT
    CP 73  : JP Z,ALLOC_FLYER_SLOT
    CP 74  : JP Z,SPAWN_S2_ZACOII
    CP 75  : JP Z,SPAWN_S2_ZACOII
    CP 76  : JP Z,SPAWN_S2_ZACOII
    CP 77  : JP Z,SPAWN_S2_ZACOII
    CP 78  : JP Z,SPAWN_S2_ZACOII
    CP 79  : JP Z,SPAWN_S2_ZACOII
    CP 80  : JP Z,SPAWN_S2_ZACOII
    CP 81  : JP Z,SPAWN_S2_ZACOII
    CP 82  : JP Z,SPAWN_S2_ZACOII
    CP 83  : JP Z,SPAWN_S2_ZACOII_RED
    CP 84  : JP Z,ALLOC_FLYER_SLOT
    CP 85  : JP Z,SPAWN_S2_ZACOII
    CP 86  : JP Z,ALLOC_FLYER_SLOT
    CP 87  : JP Z,SPAWN_S2_ZACOII
    CP 88  : JP Z,SPAWN_S2_ZACOII
    CP 89  : JP Z,SPAWN_S2_ZACOII
    CP 90  : JP Z,SPAWN_S2_ZACOII
    CP 91  : JP Z,SPAWN_S2_ZACOII
    CP 92  : JP Z,SPAWN_S2_ZACOII
    CP 93  : JP Z,SPAWN_S2_ZACOII
    CP 94  : JP Z,ALLOC_ZUM_SLOT
    CP 95  : JP Z,ALLOC_ZUM_SLOT
    CP 96  : JP Z,ALLOC_ZUM_SLOT
    CP 97  : JP Z,ALLOC_ETANK_SLOT
    CP 98  : JP Z,SPAWN_S2_ZACOII
    CP 99  : JP Z,SPAWN_S2_ZACOII
    CP 100 : JP Z,SPAWN_S2_ZACOII
    CP 101 : JP Z,SPAWN_S2_ZACOII
    CP 102 : JP Z,SPAWN_S2_ZACOII
    CP 103 : JP Z,SPAWN_S2_ZACOII
    CP 104 : JP Z,SPAWN_S2_ZACOII
    CP 105 : JP Z,SPAWN_S2_ZACOII
    CP 106 : JP Z,SPAWN_S2_ZACOII
    CP 107 : JP Z,SPAWN_S2_ZACOII
    CP 108 : JP Z,SPAWN_S2_ZACOII
    CP 109 : JP Z,ALLOC_FLYER_SLOT
    CP 110 : JP Z,ALLOC_BIGZUM_SLOT
    CP 111 : JP Z,ALLOC_FLYER_SLOT
    CP 112 : JP Z,ALLOC_FLYER_SLOT
    CP 113 : JP Z,ALLOC_FLYER_SLOT
    CP 114 : JP Z,SPAWN_S2_ZACOII_RED
    CP 115 : JP Z,SPAWN_S2_ZACOII
    CP 116 : JP Z,SPAWN_S2_ZACOII
    CP 117 : JP Z,SPAWN_S2_ZACOII
    CP 118 : JP Z,SPAWN_S2_ZACOII
    CP 119 : JP Z,SPAWN_S2_ZACOII
    CP 120 : JP Z,SPAWN_S2_ZACOII
    CP 121 : JP Z,SPAWN_S2_ZACOII
    CP 122 : JP Z,SPAWN_S2_ZACOII
    CP 123 : JP Z,SPAWN_S2_ZACOII
    CP 124 : JP Z,ALLOC_ZUM_SLOT
    CP 125 : JP Z,ALLOC_ZUM_SLOT
    CP 126 : JP Z,ALLOC_ZUM_SLOT
    CP 127 : JP Z,ALLOC_BIGZUM_SLOT
    CP 128 : JP Z,ALLOC_FLYER_SLOT
    CP 129 : JP Z,ALLOC_FLYER_SLOT
    CP 130 : JP Z,SPAWN_S2_ZACOII
    CP 131 : JP Z,SPAWN_S2_ZACOII
    CP 132 : JP Z,SPAWN_S2_ZACOII
    CP 133 : JP Z,SPAWN_S2_ZACOII
    CP 134 : JP Z,SPAWN_S2_ZACOII
    CP 135 : JP Z,SPAWN_S2_ZACOII
    CP 136 : JP Z,SPAWN_S2_ZACOII
    CP 137 : JP Z,SPAWN_S2_ZACOII
    CP 138 : JP Z,SPAWN_S2_ZACOII
    CP 139 : JP Z,SPAWN_S2_ZACOII_RED
    CP 140 : JP Z,ALLOC_FLYER_SLOT
    CP 141 : JP Z,ALLOC_FLYER_SLOT
    CP 142 : JP Z,ALLOC_FLYER_SLOT
    CP 143 : JP Z,ALLOC_FLYER_SLOT
    CP 144 : JP Z,SPAWN_S2_ZACOII
    CP 145 : JP Z,SPAWN_S2_ZACOII
    CP 146 : JP Z,SPAWN_S2_ZACOII_RED
    CP 147 : JP Z,SPAWN_S2_ZACOII
    CP 148 : JP Z,SPAWN_S2_ZACOII
    ; index149 (the last entry, boss) needs no CP of its own - by this
    ; point SPAWN2_NEXT_INDEX can only be 149, same "falls through"
    ; convention Stage1's own SSC_FIRE uses, just an explicit JP here
    ; since S2_BOSS_SPAWN isn't physically adjacent in this file (it
    ; lives inside UPDATE_BOSS_ALL's own section, unlike Stage1 where
    ; BOSS_SPAWN happens to sit right after SSC_FIRE's own CP chain).
    JP S2_BOSS_SPAWN

SPAWN2_COUNT EQU 150

SPAWN2_THRESHOLDS:
    DW 12,15,27,34,46,57,67,78
    DW 80,84,95,98,100,110,124,139
    DW 145,155,157,160,164,169,182,185
    DW 196,207,209,209,219,220,221,225
    DW 232,242,259,260,263,267,279,280
    DW 284,292,295,298,307,309,310,316
    DW 326,330,334,335,344,355,355,355
    DW 362,363,363,372,386,395,397,401
    DW 403,407,411,413,428,442,464,500
    DW 517,524,535,535,539,546,546,550
    DW 555,556,560,565,577,580,587,591
    DW 597,604,604,604,613,613,624,628
    DW 632,659,675,677,682,684,688,691
    DW 693,697,700,701,705,712,724,725
    DW 736,747,760,768,770,774,777,779
    DW 783,784,786,789,830,835,841,850
    DW 866,869,877,878,882,885,887,890
    DW 897,898,902,908,915,920,928,932
    DW 938,940,942,947,947,995

SPAWN2_Y_TABLE:
    DB 104,56,88,32,72,80,40,104,72,24,112,80
    DB 40,72,136,120,48,128,88,64,24,128,72,40
    DB 72,88,24,56,136,88,64,24,80,48,144,48
    DB 144,144,136,88,56,96,64,24,104,72,32,72
    DB 32,144,88,16,64,24,48,80,32,64,96,80
    DB 32,80,24,104,64,16,96,48,136,128,128,128
    DB 80,32,64,88,24,56,88,24,96,56,24,56
    DB 88,32,32,104,56,24,72,112,40,80,128,128
    DB 128,128,88,56,88,56,24,96,56,24,104,64
    DB 32,80,112,24,88,40,64,104,72,32,104,64
    DB 24,104,72,32,128,128,128,120,88,48,104,72
    DB 40,112,80,40,120,88,40,72,88,32,88,32
    DB 112,40,64,8,96,104


; ---------- enemy (ZacoII): all 3 slots (spawning is schedule-driven - ----------
; ---------- see SPAWN2_SCHEDULE_CHECK/SSC2_FIRE, not polled here) ----------
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): this used to
; poll a fixed-interval countdown (ENEMY_SPAWN_TIMER) here every frame,
; trying ALLOC_ENEMY_SLOT once it hit 0. That whole trigger is gone -
; ALLOC_ENEMY_SLOT is only ever called from SSC2_FIRE now, when the
; schedule's own next entry comes due.
UPDATE_ENEMIES:
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
; round36-14 follow-up#9 ("Update enemyに絞って実測してくれ"): unrolled
; the slot-walk itself (ENEMY_SLOT_COUNT=3, fixed) - UPDATE_ONE_ENEMY's
; own body is untouched/still shared (called 3x via CALL, not
; duplicated), so this costs nothing in extra ROM for the routine's own
; logic, only for this thin wrapper. Removes, per slot: the PUSH BC/
; POP BC pair (21T, only needed to protect DJNZ's own loop counter from
; UPDATE_ONE_ENEMY's internal B/C scratch use - no counter, nothing to
; protect), the 9x INC IX walk (90T - this assembler has no ADD IX,DE/
; ADD IX,n, so advancing by ENEMY_SLOT_SIZE could only ever be done one
; byte at a time; a compile-time-constant LD IX,ENEMY_POOL+9/+18 costs
; the same 14T as the very first LD IX,ENEMY_POOL always did, instead
; of paying incrementally), and DJNZ itself (13T taken/8T not). T-state
; measured via fresh_cpu()+cpu.reset_stats()+call_routine(): 3446T->
; 3100T(-10.0%, 3 active slots)/1484T->1138T(-23.3%, 0 active). Unlike
; the SasapiBroken beam routines (round36-14 follow-up#8), this wrapper
; actually got SMALLER too (35->25 bytes) - nothing here was duplicated
; (UPDATE_ONE_ENEMY's own body is unchanged/still shared via CALL), so
; there was no unroll-vs-size tradeoff to make, only pure waste to cut.
UE_UPDATE_ALL:
    LD IX,ENEMY_POOL
    CALL UPDATE_ONE_ENEMY
    LD IX,ENEMY_POOL+ENEMY_SLOT_SIZE
    CALL UPDATE_ONE_ENEMY
    LD IX,ENEMY_POOL+ENEMY_SLOT_SIZE+ENEMY_SLOT_SIZE
    CALL UPDATE_ONE_ENEMY
    CALL FLUSH_ENEMY_SPRITES
    RET

; scans ENEMY_POOL for the first E_ACT=0 slot and spawns a ZacoII into
; it - named/shaped like src/CYBER SHMUP.asm's own ALLOC_ENEMY_SLOT
; (walks the buffer, doesn't check 3 named slots by hand). Called only
; from SSC2_FIRE (via the SPAWN_S2_ZACOII/SPAWN_S2_ZACOII_RED wrappers
; below, both plain tail-jumps, not CALLs - the return address SSC2_
; FIRE's own caller left on the stack stays valid all the way through),
; never polled - round34 ("ランダムスポーンは廃止 全てスケジュール
; に"). On entry: S2_SPAWN_Y = this firing's own pixel Y (row*8, staged
; by SSC2_FIRE), S2_SPAWN_VARIANT = 0(green)/1(red), staged by
; whichever wrapper jumped here. round34-3 ("Stage1と全く同じ処理をし
; ろ"): SSC2_FIRE already advanced SPAWN2_NEXT_INDEX unconditionally
; before dispatching here (see its own comment) - if all 3 slots happen
; to be busy this just RETs having done nothing, exactly like Stage1's
; own ENEMY1_CLAIM_ANY "drops the spawn (rolling back any partial
; claim) if either pool is full" - a dropped ZacoII simply doesn't
; happen this time, the schedule itself never waits on it.
ALLOC_ENEMY_SLOT:
    LD HL,ENEMY_POOL
    LD B,ENEMY_SLOT_COUNT
AES_LOOP:
    LD A,(HL)
    OR A
    JR Z,AES_FOUND
    LD DE,ENEMY_SLOT_SIZE : ADD HL,DE
    DJNZ AES_LOOP
    RET             ; no free slot - this spawn is simply dropped
AES_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+E_ACT),A
    LD A,ENEMY_SPAWNX : LD (IX+E_X),A
    LD A,(S2_SPAWN_Y) : LD (IX+E_Y),A
    ; "ZakoIIの変色バグ 多分フラッシュ処理実装で出たと思う どちらか分から
    ; んが最初からホワイトで出てくる場合がある" - E_DY (offset+8) doubles
    ; as the hit-flash countdown while alive (UOE_DRAW: nonzero -> render
    ; FLASH_COLOR/white) and the explosion drift value while exploding
    ; (set fresh from EXPLODE_DIR_DY on each kill - see CHECK_HIT_PAIR).
    ; A slot's E_DY was never reset here on respawn, so it kept whatever
    ; its previous occupant's LAST explosion-drift value happened to be
    ; (that value stays in E_DY untouched from the moment the explosion
    ; finishes and E_ACT resets to 0, all the way until the slot is
    ; reused) - a fresh spawn landing in a slot whose last occupant had
    ; a nonzero vertical drift direction immediately read as mid-flash
    ; and rendered white from frame 1, counting down and fading back to
    ; normal a few frames later - exactly the intermittent (depends on
    ; which slot + that slot's own last explosion direction) white-on-
    ; spawn glitch reported. Zeroed here alongside E_RETREAT/E_TIMER.
    XOR A : LD (IX+E_RETREAT),A : LD (IX+E_TIMER),A : LD (IX+E_DY),A

    LD A,(S2_SPAWN_VARIANT)
    LD (IX+E_VARIANT),A
    ; red-only hit counter (E_DX, see ENEMY_RED_HP's own comment) -
    ; green never reads this, so it's left alone (whatever the slot's
    ; last occupant left there - harmless, matches this same field's own
    ; established "don't bother clearing what's never read" precedent).
    OR A
    JR Z,AES_DONE
    LD A,ENEMY_RED_HP : LD (IX+E_DX),A
AES_DONE:
    RET

; SSC2_FIRE dispatch targets for s2_zacoii/s2_zacoii_red - stage the
; variant flag ALLOC_ENEMY_SLOT reads, then tail-jump into it (not
; CALL - see ALLOC_ENEMY_SLOT's own comment for why that's safe here).
SPAWN_S2_ZACOII:
    XOR A : LD (S2_SPAWN_VARIANT),A
    JP ALLOC_ENEMY_SLOT

SPAWN_S2_ZACOII_RED:
    LD A,1 : LD (S2_SPAWN_VARIANT),A
    JP ALLOC_ENEMY_SLOT

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
    JP Z,UOE_EXPLODING
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
    ; "ZakoII2種は反転時に添付データEBullet発射" - round36-14 follow-up
    ; #11: fires exactly once, right at this transition, aimed at the
    ; tank's own position this same instant. LAUNCH_EBULLET uses only
    ; direct addressing (no IX), so IX (this ZacoII's own struct base)
    ; survives the CALL untouched - no save/restore needed.
    LD A,(IX+E_X) : LD (EBULLET_ORIGIN_X),A
    LD A,(IX+E_Y) : LD (EBULLET_ORIGIN_Y),A
    CALL LAUNCH_EBULLET
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
    ; hit-flash: E_DY(offset+8, idle while alive - see FLASH_DURATION's
    ; own comment) doubles as a white-flash countdown. Checked before
    ; the ordinary variant color so a flashing red ZacoII still reads as
    ; a hit even though its own color is already the brighter of the 2.
    LD A,(IX+E_DY)
    OR A
    JR Z,UOE_COLOR_NORMAL
    DEC A : LD (IX+E_DY),A
    LD A,FLASH_COLOR
    JR UOE_COLOR_SET
UOE_COLOR_NORMAL:
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
; NOP-padded, auto-incrementing-VDP-pointer pattern as UPDATE_TANK_SPRITES'
; own UTS_OUT_LOOP, just a different attribute-table address and slot
; count.
FLUSH_ENEMY_SPRITES:
    DI
    LD A,ENEMY_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,ENEMY_SPRITE_ATTRS
    LD B,12
FES_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
; round36-14 follow-up#9: same unroll as UE_UPDATE_ALL above (see its
; own comment) - CHECK_HIT_PAIR itself untouched/shared, only this
; wrapper's slot-walk changes. T-state: 3259T->2221T(-31.9%, 3x3 all-
; miss)/1756T->718T(-59.1%, 0 active) - a bigger relative win than
; UE_UPDATE_ALL since CHECK_HIT_PAIR's own body is much smaller than
; UPDATE_ONE_ENEMY's, so the wrapper's own now-removed overhead was a
; larger fraction of the total per-call cost. Bytes: 32->22 (also
; smaller, not bigger - see UE_UPDATE_ALL's own comment).
CHECK_HIT_ONE_BULLET:
    LD IY,ENEMY_POOL
    CALL CHECK_HIT_PAIR
    LD IY,ENEMY_POOL+ENEMY_SLOT_SIZE
    CALL CHECK_HIT_PAIR
    LD IY,ENEMY_POOL+ENEMY_SLOT_SIZE+ENEMY_SLOT_SIZE
    CALL CHECK_HIT_PAIR
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

    ; "ZakoII赤の耐久２" - red needs a 2nd rear... any hit, since
    ; ZacoII has no front/rear distinction, only variant. Green
    ; destroys immediately as before; red decrements its own E_DX hit
    ; counter (see ENEMY_RED_HP) and only actually explodes once it
    ; reaches 0 - a surviving hit just consumes the bullet with a
    ; lighter "hit but not destroyed" cue (SOUND_ZUM_DEFLECT) instead
    ; of the full destroy sequence.
    LD A,(IY+E_VARIANT)
    OR A
    JR Z,CHP_DESTROY
    LD A,(IY+E_DX) : DEC A : LD (IY+E_DX),A
    JR Z,CHP_DESTROY
    LD A,FLASH_DURATION : LD (IY+E_DY),A   ; hit-flash - see FLASH_DURATION's own comment (E_DY idle while alive)
    CALL SOUND_ZUM_DEFLECT
    RET

CHP_DESTROY:
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

; ---------- EBullet (ZacoII/Flyer enemy bullet, hw sprite, 16-direction
; aim - see EBULLET_SLOT_SIZE's own comment for the full spec/budget
; background) ----------
; D=dx(signed),E=dy(signed) on entry. Returns A=direction index(0-15).
; Clobbers B,C,D,E,H,L. Folds (dx,dy) to the first 45-degree octant via
; sign-strip(fx,fy)+conditional-swap(sw), picks the octant's own near-0
; vs near-22.5-degree half via the cheap "2*minor>major" integer test
; (no multiply/divide anywhere), then unfolds via a 16-entry LUT built by
; ebullet_gen.py (see its own comment for why a lookup table beats
; hand-derived reflection algebra here).
EBULLET_DIR16:
    LD C,0                          ; C accumulates the 4-bit fold code: bit3=fx,bit2=fy,bit1=sw,bit0=half
    LD A,D
    OR A
    JP P,ED16_DX_POS
    XOR A : SUB D : LD D,A          ; D = |dx|
    LD A,C : ADD A,8 : LD C,A
ED16_DX_POS:
    LD A,E
    OR A
    JP P,ED16_DY_POS
    XOR A : SUB E : LD E,A          ; E = |dy|
    LD A,C : ADD A,4 : LD C,A
ED16_DY_POS:
    ; D=|dx|,E=|dy|
    LD A,D
    CP E
    JP NC,ED16_NOSWAP                ; |dx|>=|dy| - already the dominant axis, no swap
    LD A,D : LD B,A                  ; swap D,E
    LD A,E : LD D,A
    LD A,B : LD E,A
    LD A,C : ADD A,2 : LD C,A
ED16_NOSWAP:
    ; D=major(ax),E=minor(ay), major>=minor. Threshold is 5*minor>major
    ; (approximates tan(11.25deg), the true midpoint between the fold's
    ; own 2 candidate directions - see ebullet_gen.py's own comment for
    ; why this specific constant matters), computed as (minor<<2)+minor
    ; with an overflow check (CF) after each step - if it ever overflows
    ; past 255, 5*minor already exceeds every possible 8-bit major.
    LD A,E
    LD B,A                           ; B = minor, kept for the final +minor step
    ADD A,A                          ; A=2*minor
    JR C,ED16_HALF1
    ADD A,A                          ; A=4*minor
    JR C,ED16_HALF1
    ADD A,B                          ; A=5*minor
    JR C,ED16_HALF1
    CP D
    JR C,ED16_HALF0                  ; 5*minor < major
    JR Z,ED16_HALF0                  ; 5*minor == major - not strictly greater, stays "half0" (matches the Python reference's own strict '>' test)
ED16_HALF1:
    LD A,C : ADD A,1 : LD C,A
ED16_HALF0:
    LD A,C
    LD E,A : LD D,0
    LD HL,EBULLET_DIR16_LUT : ADD HL,DE
    LD A,(HL)
    RET

; scans EBULLET_POOL for a free slot; if found, aims from EBULLET_ORIGIN_X/
; Y (set by the caller - see EBULLET_ORIGIN_X's own comment) toward the
; tank's CURRENT position and launches. Silently drops the shot if the
; pool is full (same "no retry, no stall" convention as every spawn in
; this file - ALLOC_ENEMY_SLOT etc).
LAUNCH_EBULLET:
    LD A,(EBULLET_POOL+0)
    OR A
    JP Z,LEB_FOUND0
    LD A,(EBULLET_POOL+5)
    OR A
    JP Z,LEB_FOUND1
    LD A,(EBULLET_POOL+10)
    OR A
    JP Z,LEB_FOUND2
    LD A,(EBULLET_POOL+15)
    OR A
    RET NZ                           ; all 4 slots busy - drop this shot
    LD DE,15
    JP LEB_LAUNCH
LEB_FOUND0:
    LD DE,0
    JP LEB_LAUNCH
LEB_FOUND1:
    LD DE,5
    JP LEB_LAUNCH
LEB_FOUND2:
    LD DE,10
LEB_LAUNCH:
    PUSH DE                          ; DE = this slot's own byte offset into EBULLET_POOL - saved across EBULLET_DIR16's own DE clobber
    LD A,(TANK_X) : LD B,A
    LD A,(EBULLET_ORIGIN_X) : LD C,A
    LD A,B : SUB C : LD D,A          ; D = dx = TANK_X - origin_X
    LD A,(TANK_Y_CUR) : LD B,A
    LD A,(EBULLET_ORIGIN_Y) : LD C,A
    LD A,B : SUB C : LD E,A          ; E = dy = TANK_Y_CUR - origin_Y
    CALL EBULLET_DIR16               ; A = direction 0-15
    LD E,A : LD D,0
    LD HL,EBULLET_DX_TABLE : ADD HL,DE : LD A,(HL) : LD B,A   ; B = this shot's own DX
    LD HL,EBULLET_DY_TABLE : ADD HL,DE : LD A,(HL) : LD C,A   ; C = this shot's own DY
    POP DE                           ; DE = slot offset again
    LD HL,EBULLET_POOL
    ADD HL,DE
    LD (HL),1 : INC HL                              ; ACT=1
    LD A,(EBULLET_ORIGIN_X) : LD (HL),A : INC HL     ; X
    LD A,(EBULLET_ORIGIN_Y) : LD (HL),A : INC HL     ; Y
    LD (HL),B : INC HL                               ; DX
    LD (HL),C                                        ; DY
    RET

; per-frame move for one active EBullet slot. IX=slot base, A=(EBULLET_
; CUR_SLOT) already set by the caller (0-3, used only for the sprite-
; attrs offset - EBULLET_POOL's own slot index isn't otherwise derivable
; from IX alone without ADD IX,DE, which this assembler doesn't support).
; Direction-aware X/Y bounds check before adding, same "check before you
; wrap a small unsigned byte past 0" shape as UPDATE_BOSS_BROKEN_BEAM_
; FLIGHT's own UBBBF_X_RIGHT/UBBBF_X_LEFT - extended here to BOTH axes
; since (unlike the boss's own downward-only beams) an EBullet's own DY
; can be negative too (aimed anywhere in a full 360-degree spread).
UPDATE_ONE_EBULLET:
    LD A,(IX+0)
    OR A
    RET Z                            ; inactive - already hidden from a previous frame, nothing to do

    LD A,(IX+3)                      ; DX
    OR A
    JP M,UOEB_X_LEFT
UOEB_X_RIGHT:
    LD C,A
    LD A,239 : SUB C : LD D,A
    LD A,(IX+1)
    CP D
    JP NC,UOEB_OFFSCREEN
    ADD A,C : LD (IX+1),A
    JP UOEB_Y
UOEB_X_LEFT:
    LD C,A
    XOR A : SUB C : LD D,A
    LD A,(IX+1)
    CP D
    JP C,UOEB_OFFSCREEN
    ADD A,C : LD (IX+1),A

UOEB_Y:
    LD A,(IX+4)                      ; DY
    OR A
    JP M,UOEB_Y_UP
UOEB_Y_DOWN:
    LD C,A
    LD A,191 : SUB C : LD D,A
    LD A,(IX+2)
    CP D
    JP NC,UOEB_OFFSCREEN
    ADD A,C : LD (IX+2),A
    JP UOEB_DRAW
UOEB_Y_UP:
    LD C,A
    XOR A : SUB C : LD D,A
    LD A,(IX+2)
    CP D
    JP C,UOEB_OFFSCREEN
    ADD A,C : LD (IX+2),A

UOEB_DRAW:
    LD A,(EBULLET_CUR_SLOT) : ADD A,A : ADD A,A : LD E,A : LD D,0
    LD HL,EBULLET_SPRITE_ATTRS : ADD HL,DE
    LD A,(IX+2) : LD (HL),A : INC HL   ; Y
    LD A,(IX+1) : LD (HL),A : INC HL   ; X
    LD A,PAT_EBULLET : LD (HL),A : INC HL
    LD A,EBULLET_COLOR : LD (HL),A
    RET

UOEB_OFFSCREEN:
    XOR A
    LD (IX+0),A
    LD A,(EBULLET_CUR_SLOT) : ADD A,A : ADD A,A : LD E,A : LD D,0
    LD HL,EBULLET_SPRITE_ATTRS : ADD HL,DE
    LD (HL),209 : INC HL
    XOR A
    LD (HL),A : INC HL : LD (HL),A : INC HL : LD (HL),A
    RET

UPDATE_EBULLET_ALL:
    XOR A : LD (EBULLET_CUR_SLOT),A
    LD IX,EBULLET_POOL
    CALL UPDATE_ONE_EBULLET
    LD A,1 : LD (EBULLET_CUR_SLOT),A
    LD IX,EBULLET_POOL+EBULLET_SLOT_SIZE
    CALL UPDATE_ONE_EBULLET
    LD A,2 : LD (EBULLET_CUR_SLOT),A
    LD IX,EBULLET_POOL+EBULLET_SLOT_SIZE+EBULLET_SLOT_SIZE
    CALL UPDATE_ONE_EBULLET
    LD A,3 : LD (EBULLET_CUR_SLOT),A
    LD IX,EBULLET_POOL+EBULLET_SLOT_SIZE+EBULLET_SLOT_SIZE+EBULLET_SLOT_SIZE
    CALL UPDATE_ONE_EBULLET
    CALL FLUSH_EBULLET_SPRITES
    RET

; blasts EBULLET_SPRITE_ATTRS (4 slots x4 bytes=16) to hw sprite slots
; EBULLET_SPR_BASE_SLOT.. - same raw DI-wrapped NOP-padded OUT idiom as
; every other FLUSH_*_SPRITES in this file.
FLUSH_EBULLET_SPRITES:
    DI
    LD A,EBULLET_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,EBULLET_SPRITE_ATTRS
    LD B,16
FEBS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FEBS_LOOP
    EI
    RET

; AABB check, 4 slots fully unrolled with compile-time-constant addresses
; from the start (same technique as CHECK_BOSS_BROKEN_BEAM_VS_TANK -
; round36-14 follow-up#8/#9 - applied here directly rather than needing a
; later round to retrofit it, since this check runs essentially every
; frame throughout normal (non-boss) play once any ZacoII/Flyer exists).
; "コリジョンは左上4x4ドット" - box is 4px wide/tall at the bullet's own
; X,Y (its sprite's own top-left corner), same shared TANK_HAZARD_
; IFRAMES/APPLY_TANK_DAMAGE/SOUND_ZUM_DEFLECT hit shape as every other
; tank hazard in this file.
CHECK_EBULLET_VS_TANK:
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD B,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD C,A

CEBVT_SLOT0:
    LD A,(EBULLET_POOL+0)
    OR A
    JP Z,CEBVT_SLOT1
    LD A,(EBULLET_POOL+1)
    LD D,A
    ADD A,3
    CP B
    JP C,CEBVT_SLOT1
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CEBVT_SLOT1
    LD A,(EBULLET_POOL+2)
    LD D,A
    ADD A,3
    CP C
    JP C,CEBVT_SLOT1
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CEBVT_SLOT1
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CEBVT_SLOT1:
    LD A,(EBULLET_POOL+5)
    OR A
    JP Z,CEBVT_SLOT2
    LD A,(EBULLET_POOL+6)
    LD D,A
    ADD A,3
    CP B
    JP C,CEBVT_SLOT2
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CEBVT_SLOT2
    LD A,(EBULLET_POOL+7)
    LD D,A
    ADD A,3
    CP C
    JP C,CEBVT_SLOT2
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CEBVT_SLOT2
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CEBVT_SLOT2:
    LD A,(EBULLET_POOL+10)
    OR A
    JP Z,CEBVT_SLOT3
    LD A,(EBULLET_POOL+11)
    LD D,A
    ADD A,3
    CP B
    JP C,CEBVT_SLOT3
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CEBVT_SLOT3
    LD A,(EBULLET_POOL+12)
    LD D,A
    ADD A,3
    CP C
    JP C,CEBVT_SLOT3
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CEBVT_SLOT3
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CEBVT_SLOT3:
    LD A,(EBULLET_POOL+15)
    OR A
    RET Z
    LD A,(EBULLET_POOL+16)
    LD D,A
    ADD A,3
    CP B
    RET C
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    RET C
    LD A,(EBULLET_POOL+17)
    LD D,A
    ADD A,3
    CP C
    RET C
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    RET C
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

; ---------- Zum: spawn timer, then all slots (see ZUM_SLOT_SIZE above) ----------
UPDATE_ZUM_ALL:
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): spawning is
; schedule-driven now (ALLOC_ZUM_SLOT is only ever called from
; SSC2_FIRE), so this just walks the pool every frame - no more polled
; interval timer here.
; round36-14 follow-up#10 ("ではそれらも検討し実測", ZUM/Flyer): same
; unrolled-slot-walk treatment as UE_UPDATE_ALL (round36-14 follow-up#9,
; see its own comment for the general rationale) - ZUM_SLOT_COUNT=2 is
; fixed, UPDATE_ONE_ZUM's own body untouched/shared via CALL.
    LD IX,ZUM_POOL
    CALL UPDATE_ONE_ZUM
    LD IX,ZUM_POOL+ZUM_SLOT_SIZE
    CALL UPDATE_ONE_ZUM
    CALL FLUSH_ZUM_SPRITES
    RET

; round35 (real-hardware feedback, after seeing the actual per-tick
; terrain-flatness log: "スポーン条件も要らないぞ 地形も仮実装だから平地
; 条件いらない"): the ZUM_TERRAIN_OK gate below is REMOVED - the terrain
; system itself is still a placeholder implementation, not the real
; thing, so gating a schedule-driven spawn on it was never meaningful in
; the first place. Direct instrumentation this same round found this
; gate was silently dropping the majority of BigZum's own schedule
; entries at ticks where the (placeholder) terrain simply wasn't flat by
; coincidence - same root class of problem here for Zum, just not yet
; reported. Only remaining gate now: a free slot (pool of ZUM_SLOT_
; COUNT=2). round34-2 ("排他制御は削除") already removed the BigZum/
; Etank ground-lane exclusion that used to sit here too - see ALLOC_
; BIGZUM_SLOT/ALLOC_ETANK_SLOT's own matching comments. round34 itself
; already dropped the older ENEMY_SPAWN_COUNT>=10 gate - "赤ZakoIIが10
; 体で終わったら" was purely about pacing the old random-timer spawner,
; superseded by the schedule's own explicit ordering. round34-3 ("Stage1
; と全く同じ処理をしろ"): SSC2_FIRE already advanced SPAWN2_NEXT_INDEX
; unconditionally before dispatching here - a failure below (both slots
; busy) just drops this one spawn attempt, exactly like Stage1's own
; SPAWN_SIMPLE.
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

    ; "自機が右端にいたら押してスポーンするように" - if the tank is
    ; already within push range of this brand-new Zum, resolve the
    ; overlap immediately instead of waiting for the next few frames of
    ; UPDATE_TANK_ZUM_PUSH's own rate-limited clamp to catch up - closes
    ; the window a same-frame slip-through could happen in, without
    ; blocking the spawn itself the way the previous round's distance
    ; gate did.
    LD A,ZUM_SPAWNX-ZUM_COLLISION_SIZE : LD B,A   ; target TANK_X
    LD A,(TANK_X)
    CP B
    JR NC,AZS_RESOLVE_PUSH   ; TANK_X >= target - resolve overlap
    RET                      ; TANK_X already < target - nothing to resolve
AZS_RESOLVE_PUSH:
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
; ZUM_SPR_BASE_SLOT..+1 - same raw DI-wrapped NOP-padded OUT pattern as
; FLUSH_ENEMY_SPRITES/FLUSH_BULLET_U_SPRITES.
FLUSH_ZUM_SPRITES:
    DI
    LD A,ZUM_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,ZUM_SPRITE_ATTRS
    LD B,8
FZS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
    SUB ZUM_COLLISION_SIZE
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
    ; horizontal overlap: TANK_X < Zum_X+ZUM_COLLISION_SIZE AND
    ; Zum_X < TANK_X+ZUM_COLLISION_SIZE - symmetric 24px box on both
    ; sides now (was an asymmetric 16/TANK_PUSH_WIDTH(32) mix - see
    ; ZUM_COLLISION_SIZE's own comment on why that made jumping over
    ; needlessly hard to time).
    LD A,(IX+1) : ADD A,ZUM_COLLISION_SIZE : LD D,A
    LD A,(TANK_X)
    CP D
    JR NC,UTZS_NEXT
    LD A,(TANK_X) : ADD A,ZUM_COLLISION_SIZE : LD D,A
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

; "もちろん自機が乗っかった場合はZumと同じでオートジャンプ" - same
; stand-on-top clamp as UPDATE_TANK_ZUM_STAND, against BigZum's own
; (now 24x16) collision box instead, reusing the SAME TANK_ZUM_STANDING
; flag - UPDATE_JUMP doesn't care which enemy the tank is parked on,
; only whether that flag is set, so no separate auto-land plumbing is
; needed. Deliberately does NOT clear TANK_ZUM_STANDING to 0 on its
; own (only ever sets it to 1) - UPDATE_TANK_ZUM_STAND, called right
; before this every frame, already did that reset once for the whole
; frame (including "not jumping at all"); this routine only ever adds
; a positive result on top of that, so standing on either enemy (or
; neither) comes out correct regardless of which one actually landed
; on. Same 1-frame-stale precedent as UPDATE_TANK_ZUM_STAND itself
; (BIGZUM_POOL's position is last frame's, since UPDATE_BIGZUM_ALL
; hasn't run yet this frame).
UPDATE_TANK_BIGZUM_STAND:
    LD A,(JUMP_ACTIVE)
    OR A
    RET Z
    LD IX,BIGZUM_POOL
    LD A,(IX+0)
    OR A
    RET Z
    ; horizontal overlap: TANK_X<BZ_X+BIGZUM_COLLISION_SIZE AND
    ; BZ_X<TANK_X+BIGZUM_COLLISION_SIZE - same symmetric-box shape as
    ; Zum's own post-fix stand check.
    LD A,(IX+1) : ADD A,BIGZUM_COLLISION_SIZE : LD D,A
    LD A,(TANK_X)
    CP D
    RET NC
    LD A,(TANK_X) : ADD A,BIGZUM_COLLISION_SIZE : LD D,A
    LD A,(IX+1)
    CP D
    RET NC
    ; overlap confirmed - clamp so the tank's own bottom rests on the
    ; collision box's own top (BZ_Y+BIGZUM_COLLISION_Y_OFFSET, not
    ; BZ_Y itself - the box no longer starts flush with the sprite's
    ; own top), same TANK_GROUND_OFFSET anchor-to-surface convention
    ; as standing on ordinary terrain or on Zum.
    LD A,(IX+2) : ADD A,BIGZUM_COLLISION_Y_OFFSET : SUB TANK_GROUND_OFFSET : LD D,A
    LD A,(TANK_Y_CUR)
    CP D
    RET C
    LD A,D : LD (TANK_Y_CUR),A
    LD A,1 : LD (TANK_ZUM_STANDING),A
    RET

; "Etankも地上機なんで乗っかれるように 32x32の内24x16の左下の範囲で
; まあ今のコリジョンと同じはずだが" - same stand-on-top clamp as
; UPDATE_TANK_ZUM_STAND/UPDATE_TANK_BIGZUM_STAND, against Etank's own
; existing 24x16 collision box (ETANK_COLLISION_SIZE/_Y_OFFSET - the
; same box CHECK_HIT_PAIR_ETANK/UPDATE_TANK_ETANK_PUSH already use, per
; direct confirmation it's unchanged), reusing the same shared
; TANK_ZUM_STANDING flag - UPDATE_JUMP doesn't care which enemy the
; tank is parked on. No shake-off mechanic (that was BigZum-specific,
; never requested for Etank).
UPDATE_TANK_ETANK_STAND:
    LD A,(JUMP_ACTIVE)
    OR A
    RET Z
    LD IX,ETANK_POOL
    LD A,(IX+0)
    OR A
    RET Z
    ; horizontal overlap: TANK_X<ET_X+ETANK_COLLISION_SIZE AND
    ; ET_X<TANK_X+ETANK_COLLISION_SIZE - same symmetric-box shape as
    ; Zum/BigZum's own post-fix stand checks.
    LD A,(IX+1) : ADD A,ETANK_COLLISION_SIZE : LD D,A
    LD A,(TANK_X)
    CP D
    RET NC
    LD A,(TANK_X) : ADD A,ETANK_COLLISION_SIZE : LD D,A
    LD A,(IX+1)
    CP D
    RET NC
    ; overlap confirmed - clamp so the tank's own bottom rests on the
    ; collision box's own top (ET_Y+ETANK_COLLISION_Y_OFFSET, not ET_Y
    ; itself), same TANK_GROUND_OFFSET anchor-to-surface convention as
    ; standing on ordinary terrain, Zum, or BigZum.
    LD A,(IX+2) : ADD A,ETANK_COLLISION_Y_OFFSET : SUB TANK_GROUND_OFFSET : LD D,A
    LD A,(TANK_Y_CUR)
    CP D
    RET C
    LD A,D : LD (TANK_Y_CUR),A
    LD A,1 : LD (TANK_ZUM_STANDING),A
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

; round36-14 follow-up#10: same unroll as above.
CHECK_HIT_ONE_BULLET_ZUM:
    LD IY,ZUM_POOL
    CALL CHECK_HIT_PAIR_ZUM
    LD IY,ZUM_POOL+ZUM_SLOT_SIZE
    CALL CHECK_HIT_PAIR_ZUM
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

    ; box widened to ZUM_COLLISION_SIZE-1(23) - was a hardcoded 15
    ; (matching Zum's own 16px sprite width) - see ZUM_COLLISION_SIZE's
    ; own comment.
    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,ZUM_COLLISION_SIZE-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,ZUM_COLLISION_SIZE-1 : CP C : RET C

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
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): spawning is
; schedule-driven now (ALLOC_BIGZUM_SLOT is only ever called from
; SSC2_FIRE), so this just walks the pool every frame - no more polled
; interval timer here.
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

; same gate as ALLOC_ZUM_SLOT plus the same instant-overlap resolution
; at spawn - "スポーン条件は同じ". round34-2 ("排他制御は削除") removed
; the Etank exclusion that used to sit here too - **this one is a real,
; known VRAM-sharing risk, not just a design preference**: Etank
; dynamically overwrites PAT_BIGZUM's own BL/BR quadrant pattern bytes
; with its own art (see PAT_ETANK_BL's own comment / ALLOC_ETANK_SLOT's
; own LDIRVM call), so a BigZum and an Etank genuinely alive at the same
; time WILL corrupt whichever one spawned first's own BL/BR quadrant art
; - this is not hypothetical, it was the whole reason this exclusion
; existed. Removed anyway per explicit instruction; if this shows up as
; visible garbled sprite art, the real fix is giving Etank its own
; dedicated pattern codes instead of borrowing BigZum's, not re-adding
; this exclusion. round34-3 ("Stage1と全く同じ処理をしろ"): SSC2_FIRE
; already advanced SPAWN2_NEXT_INDEX unconditionally before dispatching
; here - a failure below (the one slot busy) just drops this spawn
; attempt, exactly like Stage1's own SPAWN_SIMPLE.
; round35 (real-hardware feedback, direct instrumentation of the actual
; per-tick terrain-flatness log: "スポーン条件も要らないぞ 地形も仮実装
; だから平地条件いらない"): the BIGZUM_TERRAIN_OK gate that used to sit
; here is REMOVED - it's what was ACTUALLY silently dropping most of
; this schedule's own 6 BigZum entries even after round35's own
; pool-occupancy fix (BIGZUM_ENGAGEMENT_DURATION) freed the slot back up
; in time; the terrain system itself being only a placeholder means that
; gate was never meaningful to begin with. Only remaining gate now: a
; free slot.
ALLOC_BIGZUM_SLOT:
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
    LD A,TANK_Y_BASE-BIGZUM_Y_OFFSET : LD (IX+2),A   ; tier3's own Y, minus the tank-art-padding fudge that doesn't apply to BigZum's own art (see BIGZUM_Y_OFFSET's own comment)
    XOR A
    LD (IX+3),A
    LD (IX+5),A
    LD (IX+6),A
    LD (IX+7),A
    LD (IX+9),A
    LD (IX+10),A
    LD (IX+11),A
    LD (IX+12),A
    LD A,BIGZUM_HP_INIT : LD (IX+8),A

    ; restore BigZum's own real BL/BR pattern bytes - undoes whatever
    ; Etank's own dynamic VRAM-sharing may have left behind from an
    ; earlier appearance (see ETANK_SLOT_SIZE's own comment). No
    ; exclusion prevents the 2 from being active at the same time any
    ; more (round34-2, "排他制御は削除") - this reload runs every
    ; single BigZum spawn regardless, so it fixes up stale bytes
    ; whether Etank ran recently or not (cheap/harmless either way -
    ; same 128-byte LDIRVM INIT already does once for this same
    ; pattern).
    LD HL,BIGZUM_BIGZUM_TL : LD DE,PAT_BIGZUM*8+SPRPAT : LD BC,128 : CALL LDIRVM

    ; round35: this instance's own forced-retreat tick, min(spawn tick +
    ; BIGZUM_ENGAGEMENT_DURATION, BIGZUM_RETREAT_TICK) - see BIGZUM_
    ; ENGAGEMENT_DURATION's own comment for why this is per-instance now
    ; instead of one shared global tick.
    LD HL,(GAME_TICK)
    LD DE,BIGZUM_ENGAGEMENT_DURATION
    ADD HL,DE                  ; HL = candidate retreat tick
    PUSH HL
    LD DE,BIGZUM_RETREAT_TICK
    OR A
    SBC HL,DE                  ; candidate - ceiling; C set iff candidate < ceiling
    POP DE                     ; DE = candidate again
    JR C,ABZS_RETREAT_TICK_SET ; candidate already under the ceiling - use it as-is
    LD DE,BIGZUM_RETREAT_TICK  ; candidate would exceed the ceiling - clamp to it
ABZS_RETREAT_TICK_SET:
    LD (IX+13),E : LD (IX+14),D

    LD A,BIGZUM_SPAWNX-BIGZUM_COLLISION_SIZE : LD B,A
    LD A,(TANK_X)
    CP B
    JR NC,ABZS_RESOLVE_PUSH
    RET
ABZS_RESOLVE_PUSH:
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

    ; "Tick950でBigZumが居たら左へ撤退し消す" - originally BIGZUM_
    ; RETREAT_TICK was ONE shared tick every BigZum retreated at,
    ; whenever it spawned. round35 (real-hardware feedback: "Bigzumは4
    ; 回以上スケジュールしてるが1回しか出てない") found that design let
    ; the first successful spawn occupy the only slot for the rest of
    ; the game, silently dropping every later schedule entry - fixed by
    ; making this PER-INSTANCE (IX+13/+14, computed once at spawn - see
    ; BIGZUM_ENGAGEMENT_DURATION's own comment), so each BigZum retreats
    ; on its own bounded schedule instead of squatting until 950. Same
    ; true 16-bit compare either way (same bug class as CLOUD_UPDATE_ALL
    ; if this were an 8-bit CP), forcing any still-active BigZum into a
    ; dedicated retreat state (5) that overrides whatever it was doing
    ; (approach/pause/punch/jump/flip-pause alike), before any of that
    ; logic below gets a chance to run - this is what makes the boss's
    ; own reuse of BigZum's hw sprite slots/pattern VRAM (see BOSS_SPR_
    ; BASE_SLOT/PAT_SASAPI's own comments) actually safe rather than
    ; just an assumption. This check runs every single frame regardless
    ; of when GAME_TICK crossed the threshold, so even a BigZum the
    ; schedule spawns AFTER its own computed retreat tick has already
    ; passed (its own spawn-time clamp to BIGZUM_RETREAT_TICK guarantees
    ; that can only happen this close to the boss anyway) still gets
    ; forced into retreat from its very first live frame - not just ones
    ; already on screen when the tick was crossed.
    LD A,(IX+7)
    CP 5
    JP Z,UOBZ_RETREAT_MOVE      ; already retreating
    LD HL,(GAME_TICK)
    LD E,(IX+13) : LD D,(IX+14)
    OR A
    SBC HL,DE
    JR C,UOBZ_NOT_RETREAT_TIME
    LD A,5 : LD (IX+7),A       ; STATE=5 (forced retreat)
    XOR A : LD (IX+9),A        ; FACING=0 (normal art, facing left)
    JP UOBZ_RETREAT_MOVE
UOBZ_NOT_RETREAT_TIME:

    ; "BigZumの上に自機が乗ったそのまま動かないとずっと乗りっぱなしな
    ; ので右にジャンプして振り払うように" - see BIGZUM_SHAKE_STAND_
    ; FRAMES's own comment. TANK_ZUM_STANDING is already fresh for this
    ; frame (UPDATE_TANK_BIGZUM_STAND runs earlier in MAINLOOP).
    ;
    ; "振り払いが発生しないな" - the first attempt scoped this check to
    ; STATE=0 (approach) only, reusing +11(PUNCH_COOLDOWN) as the
    ; counter there - but the tank can end up parked on top while
    ; BigZum is in ANY state, and once it lands during STATE=2 (punch),
    ; UOBZ_PUNCH_MOVE's own "already in contact - hold" branch keeps it
    ; there indefinitely (an overlapping tank never separates far enough
    ; to trip the give-up-range check), so the STATE=0-only version
    ; simply never got a chance to run at all in that case - the most
    ; likely real scenario, since punch range and stand-on-top range
    ; overlap almost entirely. Moved to the very top of this routine,
    ; before ANY state dispatch, so it can preempt approach/pause/punch/
    ; flip-pause alike - only skipped while STATE is already 1 (jumping)
    ; so an in-progress jump (shake-off or ordinary) is never interrupted
    ; mid-arc. Also moved off +11 onto +6 (DY, explosion drift - fully
    ; idle here, only read/written during ACT=2) so it no longer
    ; conflicts with +11's own real job as PUNCH_COOLDOWN during STATE=2
    ; - +11 now serves only as the shake-off-jump-in-progress marker,
    ; set at the transition below and read by UOBZ_JUMP_MOVE, decoupled
    ; from the counter that leads up to it.
    LD A,(IX+7)
    CP 1
    JR Z,UOBZ_SHAKE_CHECK_DONE
    ; "振り払いが発生しないな" (round 2) - even after the STATE-scoping fix
    ; above, TANK_ZUM_STANDING itself isn't held at 1 continuously while
    ; genuinely parked: UPDATE_JUMP's own auto-land replay
    ; (JUMP_LANDING_RESTART_FRAME) bounces JUMP_Y_OFFSET back up to the
    ; table's peak and eases it back down every ~17 frames, and the
    ; BigZum-stand clamp (UPDATE_TANK_BIGZUM_STAND) only sets
    ; TANK_ZUM_STANDING=1 for the handful of frames near the bottom of
    ; each bounce - traced as a repeating "11111110000000000" pattern,
    ; ~7-8 standing frames out of every ~17. A reset-the-counter-on-any-
    ; miss design (as below) never got anywhere close to
    ; BIGZUM_SHAKE_STAND_FRAMES(90) before the very next non-standing
    ; frame zeroed it again. JUMP_ACTIVE, not the per-frame
    ; TANK_ZUM_STANDING flag, is the codebase's own existing definition
    ; of "still parked" (see UPDATE_JUMP's own landing-restart comment) -
    ; it stays 1 continuously across the whole bounce cycle, only
    ; dropping to 0 once the tank truly leaves. So: reset the counter
    ; only when JUMP_ACTIVE is 0; while JUMP_ACTIVE stays 1 but this
    ; particular frame isn't clamped, just hold the counter instead of
    ; losing progress, so it still accumulates across bounce cycles.
    LD A,(TANK_ZUM_STANDING)
    OR A
    JR Z,UOBZ_SHAKE_MAYBE_RESET
    LD A,(IX+6) : INC A : LD (IX+6),A
    CP BIGZUM_SHAKE_STAND_FRAMES
    JR C,UOBZ_SHAKE_CHECK_DONE
    LD A,1 : LD (IX+7),A           ; STATE=1 (jump)
    XOR A : LD (IX+10),A           ; JUMPFRAME=0
    LD (IX+6),A                    ; counter done its job - clear it (A=0 from the XOR above)
    LD A,1 : LD (IX+11),A          ; shake-off marker, checked by UOBZ_JUMP_MOVE
    JP UOBZ_JUMP_MOVE
UOBZ_SHAKE_MAYBE_RESET:
    LD A,(JUMP_ACTIVE)
    OR A
    JR NZ,UOBZ_SHAKE_CHECK_DONE     ; still mid bounce-cycle - hold, don't lose progress
    XOR A : LD (IX+6),A             ; genuinely not parked at all - reset
UOBZ_SHAKE_CHECK_DONE:

    LD A,(IX+7)
    CP 1
    JP Z,UOBZ_JUMP_MOVE

    CALL UOBZ_TERRAIN_FOLLOW

    LD A,(IX+7)
    CP 3
    JP Z,UOBZ_PAUSE_MOVE
    CP 2
    JP Z,UOBZ_PUNCH_MOVE
    CP 4
    JP Z,UOBZ_FLIP_PAUSE_MOVE

    ; STATE=0: approaching - identical distance-indexed decel to Zum's
    ; own charge leg (ZUM_DETECT_RANGE/ZUM_MID_RANGE/ZUM_DECEL_TABLE) -
    ; "アルゴリズムもほぼ同じ" - now bidirectional (was assumed BZ_X>=
    ; TANK_X always, i.e. only ever approaching from the right): FACING
    ; is recomputed fresh here every frame from whichever side BigZum
    ; is currently on, so re-entering this state from behind (after a
    ; punch bout gives up because the tank ran off - see UOBZ_PUNCH_
    ; MOVE's own "離れたら接近戦モードにループして") approaches
    ; correctly instead of assuming it's still on the original side.
    ;
    ; "次にBigZumが通過してパンチかジャンプかまで時間をおいてくれ" -
    ; +3(TIMER, otherwise idle in this state) doubles as a give-up
    ; cooldown here: UOBZP_GIVE_UP sets it on the way in, so a BigZum
    ; that just had the tank slip past it sits fully motionless for
    ; BIGZUM_GIVEUP_PAUSE_FRAMES before this state's own approach logic
    ; (and therefore the eventual pause->reroll into punch/jump again)
    ; starts running at all - a beat on TOP of the ordinary pre-decision
    ; pause (ZUM_PAUSE_FRAMES), not a replacement for it.
    LD A,(IX+3)
    OR A
    JR Z,UOBZ_APPROACH_START
    DEC A : LD (IX+3),A
    JP UOBZ_DRAW
UOBZ_APPROACH_START:
    LD A,(IX+1) : LD D,A          ; D = BZ_X
    LD A,(TANK_X) : LD E,A        ; E = TANK_X
    LD A,D : CP E
    JR C,UOBZ_APPROACH_SIDE_BEHIND ; BZ_X<TANK_X - on the far/behind side
    LD C,0                         ; C = the side BigZum is currently on (0=front/right)
    JR UOBZ_APPROACH_CHECK_FLIP
UOBZ_APPROACH_SIDE_BEHIND:
    LD C,1                         ; C = behind/left
UOBZ_APPROACH_CHECK_FLIP:
    ; only actually WRITE +9(FACING) via the flip-pause commit below -
    ; if it already matches the side just computed, nothing to do here.
    LD A,(IX+9)
    CP C
    JR Z,UOBZ_APPROACH_NOFLIP

    LD A,C : LD (IX+5),A           ; stash the pending facing (+5/DX, idle outside an explosion)
    LD A,4 : LD (IX+7),A           ; STATE=4 (flip-pause)
    LD A,BIGZUM_FLIP_PAUSE_FRAMES : LD (IX+3),A
    JP UOBZ_DRAW

UOBZ_APPROACH_NOFLIP:
    LD A,C
    OR A
    JR NZ,UOBZ_APPROACH_DIST_BEHIND
    LD A,D : SUB E
    JR UOBZ_APPROACH_DIST
UOBZ_APPROACH_DIST_BEHIND:
    LD A,E : SUB D
UOBZ_APPROACH_DIST:
    LD D,A                        ; D = distance, either side
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
    ; B = speed magnitude this frame; direction to apply it comes from
    ; FACING (already set above) - 0 moves left/toward decreasing X,
    ; 1 moves right/toward increasing X. Clamped at each screen edge
    ; instead of despawning either way - BigZum never just vanishes
    ; except by being destroyed (no flee/exit condition, unlike Zum).
    LD B,A
    LD A,(IX+9)
    OR A
    JR NZ,UOBZ_MOVE_ADD
    LD A,(IX+1)
    CP B
    JR NC,UOBZ_MOVE_SUB_OK
    XOR A : LD (IX+1),A
    JP UOBZ_DRAW
UOBZ_MOVE_SUB_OK:
    LD A,(IX+1) : SUB B : LD (IX+1),A
    JP UOBZ_DRAW
UOBZ_MOVE_ADD:
    LD A,(IX+1) : ADD A,B
    CP BIGZUM_MAX_X+1
    JR C,UOBZ_MOVE_ADD_OK
    LD A,BIGZUM_MAX_X
UOBZ_MOVE_ADD_OK:
    LD (IX+1),A
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
    LD (IX+11),A                   ; not a shake-off jump - see UOBZ_JUMP_MOVE's own marker check
    JP UOBZ_JUMP_MOVE

; flip-pause (STATE=4): motionless for BIGZUM_FLIP_PAUSE_FRAMES (+3,
; same reused-countdown-field convention as every other BigZum pause),
; then commits the pending facing stashed in +5 by UOBZ_APPROACH_
; CHECK_FLIP and hands back to STATE=0 to resume approaching from
; there - "BigZumが反転する場合は少し動きを止めてから反転し改めて接近
; モードにループ".
UOBZ_FLIP_PAUSE_MOVE:
    LD A,(IX+3)
    OR A
    JR Z,UOBZ_FLIP_COMMIT
    DEC A : LD (IX+3),A
    JP UOBZ_DRAW
UOBZ_FLIP_COMMIT:
    LD A,(IX+5) : LD (IX+9),A
    XOR A : LD (IX+7),A
    JP UOBZ_DRAW

; punching (STATE=2): "パンチに入ったら色々おかしい 自機が突き抜けて
; しまうし かなり離れてもずっとパンチしてきてノックバックが続く
; Zumのパンチ判定を確認 反転非反転で自機が接触範囲周辺にいるか で反転
; 後パンチは変わらないが 離れたら接近戦モードにループしてまた飛ぶか
; 突っ込んでパンチするか選択して倒されるまでループ" - closes any
; remaining gap via ZUM_ACCEL_TABLE (same ease Zum's own charge uses,
; now working from either side via FACING, not just the front), then
; holds once within BIGZUM_COLLISION_SIZE - the actual punch delivery
; (knockback + pose timer) is UPDATE_TANK_BIGZUM_PUNCH's own job, same
; separation of concerns as UPDATE_TANK_ZUM_PUSH (that routine now has
; its own matching upper-bound fix - see its own comment - the missing
; upper bound there, not this routine, was the direct cause of the
; tank passing straight through with knockback never actually
; stopping). 2 conditions give up the current commitment and revert to
; STATE=0 (fresh re-approach/pause/reroll, exactly "接近戦モードに
; ループして...また...選択して"): the tank slipping clean past to the
; opposite side (checked BEFORE the distance itself, since a stale
; positive "distance" computed the wrong way would otherwise read as
; still-in-range) - this is the actual fix for "自機が突き抜けて
; しまう"; or the distance simply growing past BIGZUM_GIVEUP_RANGE
; while still on the expected side (genuinely ran away, not just
; ordinary post-knockback separation within contact-chasing range).
UOBZ_PUNCH_MOVE:
    LD A,(IX+3)
    OR A
    JR Z,UOBZP_TIMER_DONE
    DEC A : LD (IX+3),A
UOBZP_TIMER_DONE:
    LD A,(IX+1) : LD D,A          ; D = BZ_X
    LD A,(TANK_X) : LD E,A        ; E = TANK_X

    LD A,(IX+9)
    OR A
    JR NZ,UOBZP_BEHIND

    ; FACING=0 (front): tank should still be on the left (TANK_X<=BZ_X)
    LD A,D : CP E
    JP C,UOBZP_GIVE_UP             ; BZ_X<TANK_X - tank slipped past to the right
    LD A,D : SUB E                 ; A = distance
    JR UOBZP_CHECK_DIST
UOBZP_BEHIND:
    ; FACING=1 (behind): tank should still be on the right (TANK_X>=BZ_X)
    LD A,E : CP D
    JP C,UOBZP_GIVE_UP             ; TANK_X<BZ_X - tank slipped past to the left
    LD A,E : SUB D                 ; A = distance

UOBZP_CHECK_DIST:
    CP BIGZUM_GIVEUP_RANGE
    JP NC,UOBZP_GIVE_UP
    CP BIGZUM_COLLISION_SIZE+1
    JP C,UOBZ_DRAW                  ; already in contact - hold, draw as-is
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
    LD A,(IX+9)
    OR A
    JR NZ,UOBZP_MOVE_ADD
    LD A,(IX+1)
    CP B
    JR NC,UOBZP_MOVE_SUB_OK
    XOR A : LD (IX+1),A
    JP UOBZ_DRAW
UOBZP_MOVE_SUB_OK:
    LD A,(IX+1) : SUB B : LD (IX+1),A
    JP UOBZ_DRAW
UOBZP_MOVE_ADD:
    LD A,(IX+1) : ADD A,B
    CP BIGZUM_MAX_X+1
    JR C,UOBZP_MOVE_ADD_OK
    LD A,BIGZUM_MAX_X
UOBZP_MOVE_ADD_OK:
    LD (IX+1),A
    JP UOBZ_DRAW

UOBZP_GIVE_UP:
    XOR A : LD (IX+7),A            ; STATE=0 - resume approach/pause/reroll fresh
    LD A,BIGZUM_GIVEUP_PAUSE_FRAMES : LD (IX+3),A
    JP UOBZ_DRAW

; jumping (STATE=1): sine arc via BIGZUM_JUMP_TABLE while still
; advancing toward the tank at BIGZUM_JUMP_XSPEED. If the arc
; completes while BigZum's own X still hasn't reached/passed the
; tank's (would land ON/in front of it), the arc simply restarts from
; frame0 instead of ending - "自機に設置したら連続ジャンプで飛び越え".
; Only once an arc completes with BigZum's X already at or past the
; tank's own X (genuinely cleared, landed behind) does it switch to
; STATE=2/FACING=1 - "自機の後ろを取って地上に降りたら後ろからパンチ".
;
; Unless +11 holds the "shake-off" marker (see BIGZUM_SHAKE_STAND_
; FRAMES's own comment) - then X always moves RIGHT at BIGZUM_JUMP_
; XSPEED regardless of the tank's own position (chasing toward it, as
; the ordinary case does, wouldn't move BigZum out from under a tank
; parked directly on top of it at all), and the arc always lands
; straight back into STATE=0 once complete - no "didn't clear yet,
; chain again" retry, no punch transition, marker cleared.
UOBZ_JUMP_MOVE:
    LD A,(IX+11)
    CP 1
    JR Z,UOBZJ_SHAKE_XMOVE

    LD A,(IX+1) : LD D,A
    LD A,(TANK_X) : LD E,A
    LD A,D : CP E
    JR C,UOBZJ_NO_XMOVE
    LD A,D : SUB BIGZUM_JUMP_XSPEED
    JR NC,UOBZJ_XSET
    XOR A
UOBZJ_XSET:
    LD (IX+1),A
    JR UOBZJ_NO_XMOVE
UOBZJ_SHAKE_XMOVE:
    LD A,(IX+1) : ADD A,BIGZUM_JUMP_XSPEED
    CP BIGZUM_MAX_X+1
    JR C,UOBZJ_SHAKE_XSET
    LD A,BIGZUM_MAX_X
UOBZJ_SHAKE_XSET:
    LD (IX+1),A
UOBZJ_NO_XMOVE:

    LD A,(IX+10) : INC A
    CP BIGZUM_JUMP_FRAMES
    JR C,UOBZJ_FRAME_OK

    LD A,(IX+11)
    CP 1
    JR Z,UOBZJ_SHAKE_LAND

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
UOBZJ_SHAKE_LAND:
    XOR A : LD (IX+7),A            ; STATE=0 - back to ordinary approach
    XOR A : LD (IX+11),A           ; clear the shake-off marker
    JP UOBZ_DRAW
UOBZJ_FRAME_OK:
    LD (IX+10),A
UOBZJ_APPLY:
    LD A,(IX+10) : LD E,A : LD D,0
    LD HL,BIGZUM_JUMP_TABLE : ADD HL,DE
    LD A,(HL) : LD B,A             ; B = jump offset this frame
    PUSH BC
    CALL UOBZ_GET_GROUND_Y         ; A = current tier's own ground Y - live every frame, not a fixed tier3 guess (see its own comment)
    POP BC
    SUB B
    LD (IX+2),A
    JP UOBZ_DRAW

; IX = slot base. Returns the current tier's ground Y (TANK_TIER_Y_
; TABLE[tier]) in A, probing IDCACHE_T0..T3 at BigZum's own column
; ((BZ_X+BIGZUM_PROBE_DX)>>3) - same walk UPDATE_TERRAIN_COLLISION and
; Zum's own UOZ_TERRAIN_FOLLOW use. Trashes D,E,HL. Shared by UOBZ_
; TERRAIN_FOLLOW (eases toward it while grounded) and UOBZ_JUMP_MOVE
; (uses it directly, live every frame, as the jump arc's own ground
; reference) - "まずジャンプで地面に潜り込む場合がある": the arc used
; to subtract its own offset from one fixed value (tier3's own Y,
; TANK_Y_BASE) regardless of which tier BigZum actually stood over
; while jumping - tier3 is the LOWEST tier (its own Y is the largest
; of the 4 TANK_TIER_Y_TABLE entries, since higher screen tiers have
; smaller Y), so jumping from any higher tier read as sinking below
; that tier's own, numerically smaller real ground line.
UOBZ_GET_GROUND_Y:
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZGY_T0
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZGY_T1
    LD A,(IX+1) : ADD A,BIGZUM_PROBE_DX : SRL A : SRL A : SRL A
    LD E,A : LD D,0
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,UOBZGY_T2
    LD A,3
    JR UOBZGY_TIER_SET
UOBZGY_T0:
    XOR A
    JR UOBZGY_TIER_SET
UOBZGY_T1:
    LD A,1
    JR UOBZGY_TIER_SET
UOBZGY_T2:
    LD A,2
UOBZGY_TIER_SET:
    LD E,A : LD D,0
    LD HL,TANK_TIER_Y_TABLE : ADD HL,DE : LD A,(HL)
    SUB BIGZUM_Y_OFFSET   ; see BIGZUM_Y_OFFSET's own comment - undoes the tank-art-specific padding fudge baked into this table
    RET

; IX = slot base. Eases Z_Y toward the current tier's ground line
; (UOBZ_GET_GROUND_Y) via the shared TERRAIN_EASE_Y routine - identical
; to Zum's own UOZ_TERRAIN_FOLLOW, just no ZUM_Y_OFFSET-style add
; (BigZum is 32px tall like the tank itself, so TANK_TIER_Y_TABLE
; [tier] is already its own correct top-anchor - see BIGZUM_SLOT_
; SIZE's comment).
UOBZ_TERRAIN_FOLLOW:
    CALL UOBZ_GET_GROUND_Y
    LD B,A
    LD A,(IX+2) : LD C,A
    LD E,1
    CALL TERRAIN_EASE_Y
    LD (IX+2),A
    RET

; STATE=5 (forced retreat, see UPDATE_ONE_BIGZUM's own top-of-function
; check): walks left at BIGZUM_JUMP_XSPEED (the same "approach cruise"
; speed used elsewhere), no terrain-follow (Y just stays put - it was
; already grounded the moment retreat started, and this is a straight
; horizontal exit, not a walk requiring an updated ground height) and
; no give-up/pause/punch logic - clamps and deactivates once it would
; go negative, same "CP speed: step else clamp-and-stop" idiom as
; UPDATE_BOSS_ALL's own edge clamps.
UOBZ_RETREAT_MOVE:
    LD A,(IX+1)
    CP BIGZUM_JUMP_XSPEED
    JR NC,UOBZ_RETREAT_STEP
    XOR A : LD (IX+0),A        ; off the left edge - deactivate ("消す")
    CALL UOBZ_HIDE
    RET
UOBZ_RETREAT_STEP:
    SUB BIGZUM_JUMP_XSPEED : LD (IX+1),A
    JP UOBZ_DRAW

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

    ; hit-flash color resolve, once per draw call - see FLASH_DURATION's
    ; own comment. BIGZUM_DRAW_COLOR feeds all 4 quadrant writes below
    ; instead of BIGZUM_COLOR directly so the timer only ticks down once
    ; per frame, not 4 times.
    LD A,(IX+12)
    OR A
    JR Z,UOBZD_COLOR_NORMAL
    DEC A : LD (IX+12),A
    LD A,FLASH_COLOR
    JR UOBZD_COLOR_SET
UOBZD_COLOR_NORMAL:
    LD A,BIGZUM_COLOR
UOBZD_COLOR_SET:
    LD (BIGZUM_DRAW_COLOR),A

    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,BIGZUM_SPRITE_ATTRS : ADD HL,BC

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,4 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,8 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_TEMP) : ADD A,12 : LD (HL),A : INC HL
    LD A,(BIGZUM_DRAW_COLOR) : LD (HL),A
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
; BIGZUM_SPR_BASE_SLOT..+7 - same raw DI-wrapped NOP-padded OUT pattern
; as FLUSH_ZUM_SPRITES.
FLUSH_BIGZUM_SPRITES:
    DI
    LD A,BIGZUM_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,BIGZUM_SPRITE_ATTRS
    LD B,BIGZUM_SLOT_COUNT*16
FBZS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
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
;
; "自機が突き抜けてしまうし かなり離れてもずっとパンチしてきてノック
; バックが続く Zumのパンチ判定を確認" - the contact test used to be a
; lower bound only (TANK_X>=BZ_X-SIZE), with no upper bound at all, so
; once the tank slipped past BigZum to the OTHER side (or was simply
; far away on the correct side but past SIZE), TANK_X still trivially
; satisfied that single inequality and kept "in contact" forever -
; exactly the reported symptom, and the same "already passed" case
; Zum's own UPDATE_TANK_ZUM_PUSH explicitly guards against. Both
; bounds are now folded into one signed-safe distance calc per side
; (subtraction with the CPU's own carry flag standing in for "would
; underflow", i.e. "the tank is on the wrong side of this comparison"
; - reused for both the reject check and the in-range distance itself,
; not 2 separate computations).
UPDATE_TANK_BIGZUM_PUNCH:
    ; "自機がBigZumを飛び越えられない ２４ｐｘなら飛び越えられるはず
    ; 自機と速度が噛み合って全くバックが取れない" - missing the same
    ; JUMP_ACTIVE guard UPDATE_TANK_ZUM_PUSH already has: the knockback
    ; kept firing every single frame regardless of whether the tank was
    ; airborne, so a jump attempt just got punched right back down/away
    ; before it could ever clear BigZum's own (now correctly 24px-tall)
    ; collision box - the tank could never open enough separation to
    ; even line a jump up. Suspended entirely while jumping, exactly
    ; like Zum's own push - BigZum keeps closing in underneath
    ; regardless (only the knockback itself pauses, not its approach).
    LD A,(JUMP_ACTIVE)
    OR A
    RET NZ
    LD IX,BIGZUM_POOL
    LD B,BIGZUM_SLOT_COUNT
UTBP_LOOP:
    LD A,(IX+0)
    OR A
    JP Z,UTBP_NEXT
    LD A,(IX+7)
    CP 2
    JP NZ,UTBP_NEXT

    LD A,(IX+1) : LD D,A          ; D = BZ_X
    LD A,(TANK_X) : LD E,A        ; E = TANK_X

    LD A,(IX+9)
    OR A
    JR NZ,UTBP_BEHIND

    ; FACING=0 (front): contact only while TANK_X<=BZ_X (else already
    ; passed through) AND BZ_X-TANK_X<=BIGZUM_COLLISION_SIZE
    LD A,D : CP E
    JP C,UTBP_NEXT                 ; BZ_X<TANK_X - already passed through, no contact
    LD A,D : SUB E                 ; A = distance
    CP BIGZUM_COLLISION_SIZE+1
    JP NC,UTBP_NEXT                ; out of range

    ; hard "can't clip through" wall, every frame regardless of the
    ; punch-cooldown-gated knockback pulse below - "パンチ中に自機を
    ; BigZum方向に押すとすり抜けが起こってる パンチモーション中にガー
    ; ドされてないからだな" - the periodic knockback alone left a full
    ; BIGZUM_COLLISION_SIZE(24)-wide gap uncontested between pulses
    ; (BIGZUM_PUNCH_INTERVAL(16) frames x the tank's own ~1.5px/frame
    ; average speed = 24px - exactly wide enough to cross the whole box
    ; in a single cooldown gap and come out "already passed" the other
    ; side), same continuous-clamp shape UPDATE_TANK_ZUM_PUSH already
    ; uses - pins TANK_X flush at BigZum's own outer collision boundary
    ; every single frame it's in range, independent of the punch
    ; cadence itself.
    LD A,D : SUB BIGZUM_COLLISION_SIZE : LD C,A
    LD A,(TANK_X)
    CP C
    JR C,UTBP_FRONT_WALL_OK
    LD A,C : LD (TANK_X),A
UTBP_FRONT_WALL_OK:

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
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    JP UTBP_NEXT
UTBP_FRONT_DEC:
    DEC A : LD (IX+11),A
    JP UTBP_NEXT

UTBP_BEHIND:
    ; FACING=1 (behind): contact only while TANK_X>=BZ_X (else already
    ; passed through the other way) AND TANK_X-BZ_X<=BIGZUM_COLLISION_SIZE
    LD A,E : CP D
    JP C,UTBP_NEXT                 ; TANK_X<BZ_X - already passed through, no contact
    LD A,E : SUB D                 ; A = distance
    CP BIGZUM_COLLISION_SIZE+1
    JP NC,UTBP_NEXT                ; out of range

    ; same hard wall as the FRONT branch above, mirrored - pins TANK_X
    ; flush at BigZum's own outer boundary on this side instead.
    LD A,D : ADD A,BIGZUM_COLLISION_SIZE : LD C,A
    LD A,(TANK_X)
    CP C
    JR NC,UTBP_BEHIND_WALL_OK
    LD A,C : LD (TANK_X),A
UTBP_BEHIND_WALL_OK:

    LD A,(IX+11)
    OR A
    JR NZ,UTBP_BEHIND_DEC
    LD A,(TANK_X) : ADD A,BIGZUM_PUNCH_KNOCKBACK
    CP BIGZUM_MAX_X+1
    JR C,UTBP_BEHIND_SET
    LD A,BIGZUM_MAX_X
UTBP_BEHIND_SET:
    LD (TANK_X),A
    LD A,BIGZUM_PUNCH_INTERVAL : LD (IX+11),A
    LD A,BIGZUM_PUNCH_POSE_FRAMES : LD (IX+3),A
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    CALL APPLY_TANK_DAMAGE
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
    ; "この時は弾が居ても貫通しコリジョン無効に" - STATE=5 (forced
    ; retreat, see UPDATE_ONE_BIGZUM's own comment) is a scripted exit,
    ; not something a shot should be able to interrupt or score against.
    LD A,(IY+7)
    CP 5
    RET Z

    ; AABB against the (deliberately shrunk-for-gameplay) collision box
    ; - BIGZUM_COLLISION_SIZE(24) wide starting at BZ_X (left edge, no
    ; offset needed) and BIGZUM_COLLISION_Y_OFFSET(16) down from BZ_Y -
    ; see BIGZUM_COLLISION_SIZE's own comment.
    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(IY+1) : LD D,A
    LD A,(IY+2) : ADD A,BIGZUM_COLLISION_Y_OFFSET : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,BIGZUM_COLLISION_SIZE-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,BIGZUM_COLLISION_HEIGHT-1 : CP C : RET C

    ; "BigZumジャンプ中は前面攻撃無効が解除されてヒットするように" -
    ; while airborne (STATE=1), the front/rear split is suspended
    ; entirely - any hit, from either side, counts as a rear hit. Only
    ; while STATE=1; grounded states (approach/pause/punch/flip-pause)
    ; keep the ordinary front-invincible/rear-vulnerable rule below.
    LD A,(IY+7)
    CP 1
    JR Z,CHPBZ_REAR

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

    ; "BigZumにダメージ入った場合はキンキン音は無しで" - a rear hit
    ; that damages but doesn't destroy it plays no sound at all now
    ; (was reusing SOUND_ZUM_DEFLECT, the same "kin-kin" front-deflect
    ; cue); only the final, destroying hit still plays SOUND_DESTROY
    ; below. Front hits (still fully absorbed, no damage) are untouched
    ; - CHPBZ_FRONT keeps its own SOUND_ZUM_DEFLECT call.
    LD A,(IY+8) : DEC A : LD (IY+8),A
    JR Z,CHPBZ_DESTROY
    LD A,FLASH_DURATION : LD (IY+12),A   ; hit-flash - see FLASH_DURATION's own comment
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

; ---------- Flyer: spawn/update/draw (see FLYER_SLOT_SIZE's own ----------
; ---------- comment block above for the full design rationale)   ----------
UPDATE_FLYER_ALL:
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): spawning is
; schedule-driven now (ALLOC_FLYER_SLOT is only ever called from
; SSC2_FIRE), so this just walks the pool every frame - no more polled
; interval timer here.
; round36-14 follow-up#10: same unrolled-slot-walk treatment as
; UE_UPDATE_ALL (round36-14 follow-up#9) - FLYER_SLOT_COUNT=2 fixed,
; UPDATE_ONE_FLYER's own body untouched/shared via CALL. FLYER_SLOT_SIZE
; (11) is the largest per-slot stride of any pool in this file, so the
; INC IX walk this replaces was the most expensive of the 4 candidates
; identified this round.
    LD IX,FLYER_POOL
    CALL UPDATE_ONE_FLYER
    LD IX,FLYER_POOL+FLYER_SLOT_SIZE
    CALL UPDATE_ONE_FLYER
    CALL FLUSH_FLYER_SPRITES
    RET

; airborne - no terrain gate at all, just a free slot. NOT gated
; against BigZum/Etank/Zum any more - "FlyerとBigZum、Flyerと
; Etankは同時存在して良い" (was excluded against BigZum bidirectionally
; before; both halves removed). Called only from SSC2_FIRE, which has
; already advanced SPAWN2_NEXT_INDEX unconditionally BEFORE dispatching
; here (round34-3, matching Stage1's real SSC_FIRE: "やってることは
; Stage1と全く同じ処理だぞ") - a full pool just returns and the spawn is
; simply dropped, exactly like Stage1's ENEMY1_CLAIM_ANY does when its
; own pools are full. No retry, no stall counter. round34: Y used to be
; PICK_FLYER_SPAWN_Y's own random roll (now gone, see FLYER_SPAWNX's own
; comment) - comes straight from S2_SPAWN_Y (the schedule's own row*8),
; staged by SSC2_FIRE.
ALLOC_FLYER_SLOT:
    LD HL,FLYER_POOL
    LD B,FLYER_SLOT_COUNT
AFLS_LOOP:
    LD A,(HL)
    OR A
    JR Z,AFLS_FOUND
    LD DE,FLYER_SLOT_SIZE : ADD HL,DE
    DJNZ AFLS_LOOP
    RET
AFLS_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+0),A
    LD A,FLYER_SPAWNX : LD (IX+1),A
    LD A,(S2_SPAWN_Y) : LD (IX+2),A
    XOR A
    LD (IX+3),A
    LD (IX+5),A
    LD (IX+6),A
    LD (IX+8),A
    LD (IX+9),A
    LD (IX+10),A
    LD A,FLYER_HP_INIT : LD (IX+7),A
    RET

; IX = slot base. ACT=2: same drift-then-hide explosion shape as every
; other exploding entity here. ACT=1: dispatches on PHASE(+8) - see
; FLYER_SLOT_SIZE's own comment for the full 3-phase overview.
UPDATE_ONE_FLYER:
    LD A,(IX+0)
    CP 2
    JP Z,UOFL_EXPLODING
    OR A
    RET Z

    LD A,(IX+8)
    CP 2
    JP Z,UOFL_EXIT_MOVE
    CP 1
    JP Z,UOFL_HOME_MOVE

; PHASE=0: cruise left at a fixed height/speed, normal (left-facing)
; art - "右から出て画面左まで行き". Once it can no longer subtract this
; frame's own step without underflowing, clamp to X=0 and reverse into
; homing instead of despawning - "反転". Locks the vertical homing
; direction (+6) from the tank's own Y at this exact instant, once -
; "一度方向を決定したら自機は追跡しない" - never recomputed again after
; this, even though PHASE=1 keeps reading it every frame.
UOFL_CRUISE_MOVE:
    LD A,(IX+1)
    CP FLYER_SPEED
    JR NC,UOFL_CRUISE_STEP
    XOR A : LD (IX+1),A
    LD A,1 : LD (IX+8),A
    ; round36-14 follow-up#11 originally fired an EBullet here, right at
    ; this cruise->home reversal ("Flyerは画面左端まで行き反転後発射").
    ; 実機フィードバック対応 (follow-up#12, "反転時のBullet発射は削除"):
    ; removed now that Flyer has its own Mine-drop (UOFL_CRUISE_STEP)
    ; and FlyerLaser (UOFL_HOME_DESCEND_EXIT) attacks instead - ZacoII's
    ; own EBullet firing (UPDATE_ONE_ENEMY) is untouched.
    LD A,(IX+2) : LD D,A
    LD A,(TANK_Y_CUR)
    CP D
    JR Z,UOFL_LOCK_DY_ZERO
    JR C,UOFL_LOCK_DY_UP
    LD A,FLYER_VY
    JR UOFL_LOCK_DY_SET
UOFL_LOCK_DY_UP:
    XOR A : SUB FLYER_VY
    JR UOFL_LOCK_DY_SET
UOFL_LOCK_DY_ZERO:
    XOR A
UOFL_LOCK_DY_SET:
    LD (IX+6),A
    JP UOFL_DRAW
; round36-14 follow-up#12 ("まずスポーンから32px左に移動したら...Mineを
; 放物線で投下"): FLYER_SPAWNX is a fixed constant for every instance
; (see ALLOC_FLYER_SLOT's own "LD A,FLYER_SPAWNX : LD (IX+1),A"), so the
; 32px-from-spawn threshold is just the compile-time constant FLYER_
; SPAWNX-32 - no per-instance spawn-X tracking field needed. Guarded by
; +6 (idle throughout PHASE=0 - only ever written once, at the reversal
; into PHASE=1, by UOFL_LOCK_DY_SET above - same "repurpose an otherwise
; -idle field" precedent as E_DX/E_DY) so the drop fires exactly once
; per instance; +6 gets safely overwritten with the real locked DY value
; moments later at the reversal, this guard's own job already done by
; then.
; 実機フィードバック対応 ("自機位置を見て自機の64px手前に来たら投下"):
; the fixed FLYER_SPAWNX-32 threshold this used originally is gone -
; the trigger now reads TANK_X live every frame and fires once Flyer's
; own X has closed to within MINE_DROP_LEAD_X of it. TANK_X can reach
; up to ~226 (see UTX_DO_RIGHT's own "CP 224" cap) - TANK_X+
; MINE_DROP_LEAD_X+1 can overflow past 255, which would otherwise wrap
; into a tiny, nonsense threshold; JR C below catches that case and
; fires immediately instead (an overflowed threshold means "every
; reachable Flyer_X already satisfies it").
UOFL_CRUISE_STEP:
    LD A,(IX+1) : SUB FLYER_SPEED : LD (IX+1),A
    LD A,(IX+6)
    OR A
    JR NZ,UOFLC_MINE_DONE
    LD A,(TANK_X) : ADD A,MINE_DROP_LEAD_X+1
    JR C,UOFLC_MINE_FIRE
    LD B,A
    LD A,(IX+1)
    CP B
    JR NC,UOFLC_MINE_DONE
UOFLC_MINE_FIRE:
    LD A,1 : LD (IX+6),A
    ; 実機フィードバック対応 ("投下位置も本体の左に来てない"): drop
    ; origin is Flyer's own raw top-left X (its body's own LEFT edge,
    ; not the +16 center this used originally) - Y stays centered
    ; (+16). "本体の左"読み.
    LD A,(IX+1) : LD (MINE_ORIGIN_X),A
    LD A,(IX+2) : ADD A,16 : LD (MINE_ORIGIN_Y),A
    ; 実機フィードバック対応 ("Mine投下直後か直前 一瞬違う位置にFlyerが
    ; 表示されてる"): ALLOC_MINE_SLOT itself loads IX (walks MINE_POOL
    ; looking for a free slot, same as LAUNCH_EBULLET's own comment
    ; warns about) - unlike LAUNCH_EBULLET, which was written to never
    ; touch IX at all, ALLOC_MINE_SLOT does reassign it, so this firing
    ; Flyer's own IX (still needed by UOFL_DRAW right below, for THIS
    ; SAME frame) must be saved/restored around the call - the missing
    ; PUSH/POP here was the exact bug: for 1 frame, UOFL_DRAW ran with
    ; IX still pointing at MINE_POOL instead of FLYER_POOL, drawing
    ; garbage position/pose data as if it were Flyer's own.
    PUSH IX
    CALL ALLOC_MINE_SLOT
    POP IX
UOFLC_MINE_DONE:
    JP UOFL_DRAW

; PHASE=1: fly a straight diagonal line - X always rightward at
; FLYER_SPEED, Y by the FIXED step locked in +6 at reversal time (never
; re-read from TANK_Y_CUR again) - "一度方向を決定したら自機は追跡しな
; い". Once it has flown PAST the tank's own Y (in the locked travel
; direction) by more than FLYER_CLEAR_Y, "自機に被らないY位置まで来た
; ら右に消える" - advance to PHASE=2.
;
; "Flyerが下に降りてこないぞ" - the first attempt at this exit check
; compared plain absolute |Flyer_Y-Tank_Y| against FLYER_CLEAR_Y with no
; regard for direction, so it fired the very FIRST frame of PHASE=1
; (that raw distance is just as large right after reversing, before any
; descent has happened at all, as it is after actually flying past and
; clearing the tank) - Flyer exited almost immediately, reading as "it
; never comes down" since it barely moved 1px before leaving. Fixed by
; checking the correct SIDE of the tank's own Y for the locked travel
; direction instead of raw distance: descending (+6 positive) needs
; Flyer_Y>=Tank_Y+FLYER_CLEAR_Y (passed BELOW and cleared it); ascending
; (+6 negative, stored as 0-FLYER_VY) needs Flyer_Y<=Tank_Y-FLYER_CLEAR_Y
; (passed ABOVE and cleared it) - either way this can only become true
; after actually crossing the tank's own Y in that direction, not before.
;
; "右端に帰ってく時に地形に突っ込んでる 地形に入らないように" - the fix
; above let a descending Flyer overshoot to Tank_Y+FLYER_CLEAR_Y before
; exiting, but the tank's own lowest tier sits at Y=156 - +32 lands at
; Y=188, already past the true ground line (max 184, see TANK_GROUND_
; OFFSET's own derivation: ground_line=(20+tier)*8, worst case 184) -
; PHASE=2's own fixed-Y rightward flight then stayed AT that sunk-in-
; terrain depth the whole way to the edge. Descending is now additionally
; hard-capped at FLYER_DESCEND_LIMIT_Y(112) regardless of the tank's own
; Y - Flyer_Y+32(its own sprite height)=144, still comfortably above the
; highest possible ground line(160, tier0) with margin - so a descending
; Flyer always exits at a safe sky altitude no matter which tier the
; tank happens to be standing on. Ascending is unaffected (moving away
; from the ground, into the sky, never at any terrain risk) and keeps
; the original tank-relative check. DY=0 (tank exactly level with Flyer
; at the reversal instant - a rare, near-impossible tie) now also exits
; immediately instead of looping PHASE=1 forever with X silently
; wrapping past 255 - not itself reported, but the same class of bug.
;
; No signed-flag branch (JP M/P) here - this assembler only implements
; Z/NZ/C/NC - so the sign of +6 is read via "CP 128" instead (FLYER_VY
; is always a small positive magnitude, so its negative two's-complement
; encoding is always >=128 and the positive encoding always <128).
UOFL_HOME_MOVE:
    LD A,1 : LD (IX+9),A          ; right-facing while homing
    LD A,(IX+1) : ADD A,FLYER_SPEED : LD (IX+1),A
    LD A,(IX+2) : LD B,A : LD A,(IX+6) : ADD A,B : LD (IX+2),A

    LD A,(IX+6)
    OR A
    JR Z,UOFL_HOME_DO_EXIT        ; DY=0 (tank was level at lock time) - nothing left to descend/ascend through, exit now
    CP 128
    JR NC,UOFL_HOME_CHECK_UP      ; DY stored >=128 -> negative -> ascending

    ; descending: hard sky-altitude cap first (terrain safety, tier-
    ; independent), then the ordinary tank-relative clear check.
    LD A,(IX+2)
    CP FLYER_DESCEND_LIMIT_Y+1
    JR C,UOFL_HOME_CHECK_DOWN_TANK
    LD A,FLYER_DESCEND_LIMIT_Y : LD (IX+2),A
    JR UOFL_HOME_DESCEND_EXIT
UOFL_HOME_CHECK_DOWN_TANK:
    LD A,(TANK_Y_CUR) : ADD A,FLYER_CLEAR_Y : LD D,A
    LD A,(IX+2)
    CP D
    JR C,UOFL_HOME_NO_EXIT        ; Flyer_Y still < Tank_Y+CLEAR - hasn't cleared below yet
    JR UOFL_HOME_DESCEND_EXIT
UOFL_HOME_CHECK_UP:
    LD A,(TANK_Y_CUR) : SUB FLYER_CLEAR_Y : LD D,A
    LD A,(IX+2)
    CP D
    JR NC,UOFL_HOME_NO_EXIT       ; Flyer_Y still >= Tank_Y-CLEAR - hasn't cleared above yet
    JR UOFL_HOME_DO_EXIT
; round36-14 follow-up#12 ("現在はFlyer帰還でSandskyに被ってしまってる
; ので帰還時の右移動のY位置を8px上に 右斜め下移動の最終Y座標って事ね
; その後FlyerLaser発射 つまり右斜め下移動後に発射"): only the DESCENDING
; leg ever visually overlaps SandSky (ascending moves away from the
; ground, into open sky, never at any risk) - both descending exits
; above (the hard sky-altitude cap AND the ordinary tank-relative clear)
; land here instead of jumping straight to the shared UOFL_HOME_DO_EXIT,
; so the -8px raise and the laser fire only ever happen on this leg, at
; whatever Y this frame's own descent already landed on (its own
; "final Y").
UOFL_HOME_DESCEND_EXIT:
    LD A,(IX+2) : SUB 8 : LD (IX+2),A
    CALL LAUNCH_FLYER_LASER
UOFL_HOME_DO_EXIT:
    LD A,2 : LD (IX+8),A
UOFL_HOME_NO_EXIT:
    JP UOFL_DRAW

; PHASE=2: straight right only, ignoring the tank entirely, until off
; the right edge, then despawns - same "CP FLYER_SPAWNX" convention as
; UOZ_FLEE_MOVE's own off-right-edge despawn.
UOFL_EXIT_MOVE:
    LD A,1 : LD (IX+9),A
    LD A,(IX+1) : ADD A,FLYER_SPEED : LD (IX+1),A
    CP FLYER_SPAWNX
    JP C,UOFL_DRAW
    XOR A : LD (IX+0),A
    CALL UOFL_HIDE
    RET

UOFL_DRAW:
    LD A,(IX+9)
    OR A
    JR Z,UOFLD_NORMAL
    LD A,PAT_FLYER_L : JR UOFLD_BASE_SET
UOFLD_NORMAL:
    LD A,PAT_FLYER
UOFLD_BASE_SET:
    LD (FLYER_DRAW_TEMP),A

    LD A,(IX+10)
    OR A
    JR Z,UOFLD_COLOR_NORMAL
    DEC A : LD (IX+10),A
    LD A,FLASH_COLOR
    JR UOFLD_COLOR_SET
UOFLD_COLOR_NORMAL:
    LD A,FLYER_COLOR
UOFLD_COLOR_SET:
    LD (FLYER_DRAW_COLOR),A

    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,FLYER_SPRITE_ATTRS : ADD HL,BC

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_TEMP) : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_TEMP) : ADD A,4 : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_TEMP) : ADD A,8 : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_TEMP) : ADD A,12 : LD (HL),A : INC HL
    LD A,(FLYER_DRAW_COLOR) : LD (HL),A
    RET

UOFL_EXPLODING:
    LD A,(IX+3)
    OR A
    JR Z,UOFL_EXPLODE_HIDE
    DEC A : LD (IX+3),A
    LD A,(IX+1) : LD B,A : LD A,(IX+5) : ADD A,B : LD (IX+1),A
    LD A,(IX+2) : LD B,A : LD A,(IX+6) : ADD A,B : LD (IX+2),A

    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,FLYER_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A : INC HL
    LD B,3
UOFLE_HIDE_REST:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ UOFLE_HIDE_REST
    RET
UOFL_EXPLODE_HIDE:
    XOR A : LD (IX+0),A
    CALL UOFL_HIDE
    RET

UOFL_HIDE:
    LD A,(IX+4) : ADD A,A : ADD A,A : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,FLYER_SPRITE_ATTRS : ADD HL,BC
    LD B,4
UOFLH_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    DJNZ UOFLH_LOOP
    RET

; blasts FLYER_SPRITE_ATTRS (FLYER_SLOT_COUNT*16 bytes) to hw sprite
; slots FLYER_SPR_BASE_SLOT.. - same raw DI-wrapped NOP-padded OUT pattern
; as FLUSH_BIGZUM_SPRITES.
FLUSH_FLYER_SPRITES:
    DI
    LD A,FLYER_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,FLYER_SPRITE_ATTRS
    LD B,FLYER_SLOT_COUNT*16
FFLS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FFLS_LOOP
    EI
    RET

; ---------- bullet x Flyer collision: plain omnidirectional HP------------
; ---------- decrement, full 32x32 box (no shrink specified)   ----------
CHECK_BULLET_VS_FLYER:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET_FLYER
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET_FLYER
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET_FLYER
    RET

; round36-14 follow-up#10: same unroll as above.
CHECK_HIT_ONE_BULLET_FLYER:
    LD IY,FLYER_POOL
    CALL CHECK_HIT_PAIR_FLYER
    LD IY,FLYER_POOL+FLYER_SLOT_SIZE
    CALL CHECK_HIT_PAIR_FLYER
    RET

CHECK_HIT_PAIR_FLYER:
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
    LD A,D : ADD A,FLYER_COLLISION_SIZE-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,FLYER_COLLISION_SIZE-1 : CP C : RET C

    LD A,(IX+1)
    OR A
    JR NZ,CHPFL_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPFL_SKIP_ERASE:
    XOR A : LD (IX+0),A

    LD A,(IY+7) : DEC A : LD (IY+7),A
    JR Z,CHPFL_DESTROY
    LD A,FLASH_DURATION : LD (IY+10),A
    CALL SOUND_ZUM_DEFLECT
    RET
CHPFL_DESTROY:
    LD A,2 : LD (IY+0),A
    LD A,EXPLOSION_DURATION : LD (IY+3),A

    LD A,(TICK) : AND 7 : LD C,A : LD B,0
    LD HL,EXPLODE_DIR_DX : ADD HL,BC : LD A,(HL) : LD (IY+5),A
    LD HL,EXPLODE_DIR_DY : ADD HL,BC : LD A,(HL) : LD (IY+6),A

    CALL SOUND_DESTROY
    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; ---------- Etank ground enemy: spawn/update/draw (see ETANK_SLOT_ ----------
; ---------- SIZE's own comment block for the full design rationale) ----------
UPDATE_ETANK_ALL:
; round34 ("ランダムスポーンは廃止 全てスケジュールに"): spawning is
; schedule-driven now (ALLOC_ETANK_SLOT is only ever called from
; SSC2_FIRE), so this just walks the pool every frame - no more polled
; interval timer here.
    LD IX,ETANK_POOL
    LD B,ETANK_SLOT_COUNT
UETAU_LOOP:
    PUSH BC
    CALL UPDATE_ONE_ETANK
    POP BC
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UETAU_LOOP
    CALL FLUSH_ETANK_SPRITES
    RET

; round34 ("ランダムスポーンは廃止 全てスケジュールに") dropped the
; old GAME_TICK>=70 floor - itself only ever a safety margin for the
; old random-timer spawner, redundant now that the schedule's own
; first Etank entry has its own explicit, always->=70 tick anyway.
; round34-2 ("排他制御は削除") removed the BigZum/Zum ground-lane
; exclusion that used to sit here too. **The BigZum half is a real,
; known VRAM-sharing risk, not just a design preference** - Etank
; dynamically overwrites PAT_BIGZUM's own BL/BR quadrant pattern bytes
; below with its own art, so a BigZum and an Etank genuinely alive at
; the same time WILL corrupt whichever spawned first's own BL/BR
; quadrant art (see ALLOC_BIGZUM_SLOT's own matching comment - this
; exclusion used to be the only thing preventing that). Removed anyway
; per explicit instruction. Called only from SSC2_FIRE, which has
; already advanced SPAWN2_NEXT_INDEX unconditionally BEFORE dispatching
; here (round34-3, matching Stage1's real SSC_FIRE: "やってることは
; Stage1と全く同じ処理だぞ") - a failure here (full pool) just returns
; and the spawn is simply dropped, no retry, no stall counter.
; round35 (real-hardware feedback, direct instrumentation of the actual
; per-tick terrain-flatness log: "スポーン条件も要らないぞ 地形も仮実装
; だから平地条件いらない"): the ETANK_TERRAIN_OK gate that used to sit
; here (checking the apex tier was the CURRENT surface - see ETANK_
; SLOT_SIZE's own comment for why Etank cared, since it never re-probes
; its own Y after spawn) is REMOVED. Only remaining gate now: a free
; slot. Note this means Etank can now spawn while the terrain ISN'T at
; the apex tier - since its own Y still comes unchanged from the apex
; tier's fixed value regardless (see AETS_FOUND below), it can visually
; sit above/below the actual (placeholder) ground until the real terrain
; system replaces this one - accepted per explicit instruction, not an
; oversight.
ALLOC_ETANK_SLOT:
    LD HL,ETANK_POOL
    LD B,ETANK_SLOT_COUNT
AETS_LOOP:
    LD A,(HL)
    OR A
    JR Z,AETS_FOUND
    LD DE,ETANK_SLOT_SIZE : ADD HL,DE
    DJNZ AETS_LOOP
    RET
AETS_FOUND:
    PUSH HL
    POP IX
    LD A,1 : LD (IX+0),A
    LD A,ETANK_SPAWNX : LD (IX+1),A
    LD A,(TANK_TIER_Y_TABLE) : SUB ETANK_Y_OFFSET : LD (IX+2),A   ; apex tier's own Y minus the tank-art-padding fudge (see ETANK_Y_OFFSET's own comment) - fixed for Etank's whole lifetime, never re-probed (see ETANK_SLOT_SIZE's own comment)
    XOR A
    LD (IX+3),A
    LD (IX+4),A
    LD (IX+5),A
    LD (IX+7),A
    LD A,ETANK_HP_INIT : LD (IX+6),A

    ; "スポーン後左へ32px移動したら発射" - round36-14 follow-up#11:
    ; captures this instance's own spawn X (always ETANK_SPAWNX, a fixed
    ; constant, but stored per-instance for a clear, self-contained
    ; "moved 32px" test in UPDATE_ONE_ETANK rather than hardcoding the
    ; same constant again there) and clears the one-shot fired flag.
    LD A,ETANK_SPAWNX : LD (ETANK_SPAWN_X),A
    XOR A : LD (ETANK_BULLET_FIRED),A

    ; dynamic pattern-VRAM share: overwrite BigZum's own BL/BR groups
    ; (PAT_BIGZUM+8/+12) with Etank's own art - safe only while BigZum
    ; is inactive (already gated above), restored whenever BigZum
    ; itself next spawns (see ALLOC_BIGZUM_SLOT's own reload).
    LD HL,ETANK_BL : LD DE,PAT_ETANK_BL*8+SPRPAT : LD BC,64 : CALL LDIRVM

    ; "自機はZumと同じで接触で自機を押す" - same instant overlap
    ; resolution at spawn as ALLOC_ZUM_SLOT.
    LD A,ETANK_SPAWNX-ETANK_COLLISION_SIZE : LD B,A
    LD A,(TANK_X)
    CP B
    JR NC,AETS_RESOLVE_PUSH
    RET
AETS_RESOLVE_PUSH:
    LD A,B : LD (TANK_X),A
    RET

; IX = slot base. ACT=1: fixed Y (never re-probed), advances X left at
; a flat ETANK_SPEED(2px/frame - "速度は2") every frame, straight-line,
; no terrain following at all ("坂の昇降はしない"). Despawns once X can
; no longer subtract the speed without underflow, i.e. off the left
; edge ("右からでて左に消える"). ACT=2: same drift-then-hide explosion
; shape as every other enemy here.
UPDATE_ONE_ETANK:
    LD A,(IX+0)
    CP 2
    JP Z,UOET_EXPLODING
    OR A
    RET Z

    LD A,(IX+1)
    CP ETANK_SPEED
    JR NC,UOET_MOVE_OK
    XOR A : LD (IX+0),A
    CALL UOET_HIDE
    RET
UOET_MOVE_OK:
    LD A,(IX+1) : SUB ETANK_SPEED : LD (IX+1),A

    ; "スポーン後左へ32px移動したら発射し方向は左直進のみ" - round36-14
    ; follow-up#11: one-shot, guarded by ETANK_BULLET_FIRED so later
    ; frames (still well past the 32px line) don't refire.
    LD A,(ETANK_BULLET_FIRED)
    OR A
    JR NZ,UOET_DRAW
    LD A,(ETANK_SPAWN_X) : LD B,A
    LD A,(IX+1) : LD C,A
    LD A,B : SUB C            ; distance moved so far (spawn_x - current_x; Etank only ever moves left, so this never underflows)
    CP 32
    JR C,UOET_DRAW             ; not moved 32px yet
    LD A,1 : LD (ETANK_BULLET_FIRED),A
    CALL LAUNCH_ETANK_BULLET

UOET_DRAW:
    ; hit-flash color resolve, once per draw call (see FLASH_DURATION's
    ; own comment) - both hw sprite slots (BL/BR) share the one result.
    LD A,(IX+7)
    OR A
    JR Z,UOETD_COLOR_NORMAL
    DEC A : LD (IX+7),A
    LD A,FLASH_COLOR
    JR UOETD_COLOR_SET
UOETD_COLOR_NORMAL:
    LD A,ETANK_COLOR
UOETD_COLOR_SET:
    LD (ETANK_DRAW_COLOR),A

    LD HL,ETANK_SPRITE_ATTRS
    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL   ; BL: Y+16 (bottom half of the 32px canvas), X+0
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_ETANK_BL : LD (HL),A : INC HL
    LD A,(ETANK_DRAW_COLOR) : LD (HL),A : INC HL

    LD A,(IX+2) : ADD A,16 : LD (HL),A : INC HL   ; BR: Y+16, X+16
    LD A,(IX+1) : ADD A,16 : LD (HL),A : INC HL
    LD A,PAT_ETANK_BR : LD (HL),A : INC HL
    LD A,(ETANK_DRAW_COLOR) : LD (HL),A
    RET

UOET_EXPLODING:
    LD A,(IX+3)
    OR A
    JR Z,UOET_EXPLODE_HIDE
    DEC A : LD (IX+3),A
    LD A,(IX+1) : LD B,A : LD A,(IX+4) : ADD A,B : LD (IX+1),A
    LD A,(IX+2) : LD B,A : LD A,(IX+5) : ADD A,B : LD (IX+2),A
    LD HL,ETANK_SPRITE_ATTRS
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A : INC HL
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL : LD (HL),A : INC HL : LD (HL),A
    RET
UOET_EXPLODE_HIDE:
    XOR A : LD (IX+0),A
    CALL UOET_HIDE
    RET

UOET_HIDE:
    LD HL,ETANK_SPRITE_ATTRS
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL : LD (HL),A : INC HL : LD (HL),A : INC HL
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL : LD (HL),A : INC HL : LD (HL),A
    RET

; blasts ETANK_SPRITE_ATTRS (8 bytes) to hw sprite slots
; ETANK_SPR_BASE_SLOT..+1 - same raw DI-wrapped NOP-padded OUT pattern as
; FLUSH_FLYER_SPRITES.
FLUSH_ETANK_SPRITES:
    DI
    LD A,ETANK_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,ETANK_SPRITE_ATTRS
    LD B,ETANK_SLOT_COUNT*8
FETS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FETS_LOOP
    EI
    RET

; "Zumと同じで接触で自機を押す" - same shape as UPDATE_TANK_ZUM_PUSH:
; run after UPDATE_ETANK_ALL (this frame's already-advanced X),
; JUMP_ACTIVE suspends it entirely (same reasoning as Zum's own - stays
; cleanly jumpable), skips once the tank has already passed through,
; otherwise shoves TANK_X left by ETANK_PUSH_SPEED every frame it's in
; contact.
UPDATE_TANK_ETANK_PUSH:
    LD A,(JUMP_ACTIVE)
    OR A
    RET NZ
    LD IX,ETANK_POOL
    LD B,ETANK_SLOT_COUNT
UTETP_LOOP:
    LD A,(IX+0)
    CP 1
    JR NZ,UTETP_NEXT
    LD A,(IX+1)
    LD D,A
    LD A,(TANK_X)
    CP D
    JR NC,UTETP_NEXT             ; TANK_X>=Etank_X - already passed, no longer blocks
    LD A,D
    SUB ETANK_COLLISION_SIZE
    LD C,A
    LD A,(TANK_X)
    CP C
    JR C,UTETP_NEXT              ; TANK_X already < target - no overlap
    LD A,(TANK_X)
    CP ETANK_PUSH_SPEED
    JR NC,UTETP_STEP
    XOR A : LD (TANK_X),A
    JR UTETP_NEXT
UTETP_STEP:
    LD A,(TANK_X) : SUB ETANK_PUSH_SPEED : LD (TANK_X),A
UTETP_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ UTETP_LOOP
    RET

; ---------- bullet x Etank collision: plain omnidirectional HP ----------
; ---------- decrement against the 24x16 collision box            ----------
CHECK_BULLET_VS_ETANK:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET_ETANK
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET_ETANK
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET_ETANK
    RET

CHECK_HIT_ONE_BULLET_ETANK:
    LD IY,ETANK_POOL
    LD B,ETANK_SLOT_COUNT
CHOBET_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR_ETANK
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOBET_LOOP
    RET

CHECK_HIT_PAIR_ETANK:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+0)
    CP 1
    RET NZ

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(IY+1) : LD D,A
    LD A,(IY+2) : ADD A,ETANK_COLLISION_Y_OFFSET : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,ETANK_COLLISION_SIZE-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,ETANK_COLLISION_HEIGHT-1 : CP C : RET C

    LD A,(IX+1)
    OR A
    JR NZ,CHPET_SKIP_ERASE
    CALL ERASE_BULLET_CELL
CHPET_SKIP_ERASE:
    XOR A : LD (IX+0),A

    LD A,(IY+6) : DEC A : LD (IY+6),A
    JR Z,CHPET_DESTROY
    LD A,FLASH_DURATION : LD (IY+7),A
    CALL SOUND_ZUM_DEFLECT
    RET
CHPET_DESTROY:
    LD A,2 : LD (IY+0),A
    LD A,EXPLOSION_DURATION : LD (IY+3),A

    LD A,(TICK) : AND 7 : LD C,A : LD B,0
    LD HL,EXPLODE_DIR_DX : ADD HL,BC : LD A,(HL) : LD (IY+4),A
    LD HL,EXPLODE_DIR_DY : ADD HL,BC : LD A,(HL) : LD (IY+5),A

    CALL SOUND_DESTROY
    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; ---------- EtankBullet (Etank's own bullet, BG cell, left-only - see
; ETANK_BULLET_ACT's own comment for the full spec/color-budget
; background) ----------
; IX = ETANK_POOL (the firing Etank's own struct - (IX+1)=X,(IX+2)=Y),
; called from UPDATE_ONE_ETANK right at the 32px-moved transition.
; round36-14 follow-up#11 実機フィードバック対応: (IX+2) is Etank's own
; raw Y field, but Etank's real ART only occupies the BOTTOM half of a
; hypothetical 32x32 canvas ("Etankはそもそも32x16しか使っていない" -
; UOET_DRAW's own BL/BR quadrants are drawn at (IX+2)+16, TL/TR always
; hidden - see ETANK_COLLISION_Y_OFFSET's own "=16" comment for the same
; fact from the collision side). Using the raw (IX+2) here (as the first
; version of this routine did) spawned the bullet 16px/2 cells above
; where Etank is actually drawn.
LAUNCH_ETANK_BULLET:
    LD A,1 : LD (ETANK_BULLET_ACT),A
    LD A,(IX+1) : LD (ETANK_BULLET_X),A
    LD A,(IX+2) : ADD A,16 : LD (ETANK_BULLET_Y),A
    RET

; ETANK_BULLET_ACT/X/Y sit at consecutive addresses (+0/+1/+2), the same
; relative layout ERASE_HORMING_BG_CELL/HORMING_BG_CELL_ADDR already
; expect from their own IX - both are reused directly here unchanged
; (IX=ETANK_BULLET_ACT for this call), rather than duplicating the same
; row/col-address math and sky/skysand/sand/terrain-row restore logic a
; 2nd time for a single-instance BG bullet that needs exactly the same
; background-restoration behavior Horming's own BG bullets already have.
DRAW_ETANK_BULLET_CELL:
    LD A,ETANK_BULLET_PATTERN_CODE
    LD (BULLET_TEMP_BYTE),A
    CALL HORMING_BG_CELL_ADDR
    JP WRITE_BULLET_BYTE_HL

; erase-then-move-then-draw, same per-frame shape as UPDATE_HORMING_BG_
; ALL - called every frame alongside UPDATE_ETANK_ALL (same BOSS_ACT
; guard). Only 1 concurrent instance ever needed (ETANK_SLOT_COUNT=1
; itself, and this bullet only ever fires once per Etank spawn), so a
; flat single-instance routine instead of a real pool loop.
UPDATE_ETANK_BULLET_ALL:
    LD A,(ETANK_BULLET_ACT)
    OR A
    RET Z
    LD IX,ETANK_BULLET_ACT
    CALL ERASE_HORMING_BG_CELL
    LD A,(ETANK_BULLET_X)
    CP ETANK_BULLET_SPEED
    JR NC,UEBA_MOVE_OK
    XOR A : LD (ETANK_BULLET_ACT),A   ; off the left edge - already erased above, nothing left to draw
    RET
UEBA_MOVE_OK:
    SUB ETANK_BULLET_SPEED
    LD (ETANK_BULLET_X),A
    CALL DRAW_ETANK_BULLET_CELL
    RET

; AABB check (8x8 box, matching the bullet's own single BG cell) - same
; shared TANK_HAZARD_IFRAMES/APPLY_TANK_DAMAGE/SOUND_ZUM_DEFLECT hit
; shape as every other tank hazard in this file. A hit does NOT
; deactivate the bullet - it keeps flying through/past the tank, same
; "one hit per frame is enough, hazard survives" convention as CHECK_
; BOSS_BROKEN_BEAM_VS_TANK's own beams.
CHECK_ETANK_BULLET_VS_TANK:
    LD A,(ETANK_BULLET_ACT)
    OR A
    RET Z
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD B,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD C,A
    LD A,(ETANK_BULLET_X)
    LD D,A
    ADD A,7
    CP B
    RET C
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    RET C
    LD A,(ETANK_BULLET_Y)
    LD D,A
    ADD A,7
    CP C
    RET C
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    RET C
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

; ---------- FlyerLaser: launch/update/draw/collision (see FLYER_LASER_
; ACT's own comment for the full design rationale) ----------
; called from UOFL_HOME_DESCEND_EXIT with IX still = the firing Flyer's
; own FLYER_POOL slot base, untouched throughout - same "IX untouched by
; it" convention as LAUNCH_EBULLET. Not aimed - always straight right
; ("自機は狙わず右方向水平撃ちのみ").
LAUNCH_FLYER_LASER:
    LD A,1 : LD (FLYER_LASER_ACT),A
    LD A,(IX+1) : ADD A,32 : LD (FLYER_LASER_X),A
    LD A,(IX+2) : ADD A,19 : LD (FLYER_LASER_Y),A
    RET

; FLYER_LASER_ACT/X/Y sit at consecutive addresses (+0/+1/+2), the same
; relative layout ERASE_HORMING_BG_CELL/HORMING_BG_CELL_ADDR already
; expect - reused directly unchanged, same precedent as DRAW_ETANK_
; BULLET_CELL above.
DRAW_FLYER_LASER_CELL:
    LD A,FLYER_LASER_PATTERN_CODE
    LD (BULLET_TEMP_BYTE),A
    CALL HORMING_BG_CELL_ADDR
    JP WRITE_BULLET_BYTE_HL

; erase-then-move-then-draw, same per-frame shape as UPDATE_ETANK_
; BULLET_ALL. Only 1 concurrent instance ever needed (1 Flyer instance
; only ever reaches UOFL_HOME_DESCEND_EXIT once per spawn).
UPDATE_FLYER_LASER_ALL:
    LD A,(FLYER_LASER_ACT)
    OR A
    RET Z
    LD IX,FLYER_LASER_ACT
    CALL ERASE_HORMING_BG_CELL
    LD A,(FLYER_LASER_X) : ADD A,FLYER_LASER_SPEED
    CP FLYER_LASER_DESPAWN_X+1
    JR C,UFLA_MOVE_OK
    XOR A : LD (FLYER_LASER_ACT),A   ; off the right edge - already erased above, nothing left to draw
    RET
UFLA_MOVE_OK:
    LD (FLYER_LASER_X),A
    CALL DRAW_FLYER_LASER_CELL
    RET

; AABB check (8x8 box, matching the laser's own single BG cell) - same
; shared TANK_HAZARD_IFRAMES/APPLY_TANK_DAMAGE/SOUND_ZUM_DEFLECT hit
; shape as CHECK_ETANK_BULLET_VS_TANK, including "flies through, doesn't
; self-deactivate on hit".
CHECK_FLYER_LASER_VS_TANK:
    LD A,(FLYER_LASER_ACT)
    OR A
    RET Z
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD B,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD C,A
    LD A,(FLYER_LASER_X)
    LD D,A
    ADD A,7
    CP B
    RET C
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    RET C
    LD A,(FLYER_LASER_Y)
    LD D,A
    ADD A,7
    CP C
    RET C
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    RET C
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

; ---------- Mine: alloc/update/draw/explode/collision (see MINE_SLOT_
; SIZE's own comment for the full design rationale) ----------
; called from UOFLC_MINE_DONE with MINE_ORIGIN_X/Y already staged - same
; "stash origin in scratch bytes, consumed once inside ALLOC" convention
; as EBULLET_ORIGIN_X/Y. A full pool just returns and the drop is
; dropped, same "no retry, no stall counter" convention as ALLOC_FLYER_
; SLOT.
ALLOC_MINE_SLOT:
    LD IX,MINE_POOL
    LD A,(IX+0)
    OR A
    JR Z,AMS_FOUND
    LD IX,MINE_POOL+MINE_SLOT_SIZE
    LD A,(IX+0)
    OR A
    RET NZ
    LD A,1 : LD (IX+5),A
    JR AMS_INIT
AMS_FOUND:
    XOR A : LD (IX+5),A
AMS_INIT:
    LD A,1 : LD (IX+0),A
    LD A,(MINE_ORIGIN_X) : LD (IX+1),A
    LD A,(MINE_ORIGIN_Y) : LD (IX+2),A
    XOR A
    LD (IX+3),A
    LD (IX+4),A
    LD (IX+7),A
    RET

UPDATE_MINE_ALL:
    LD IX,MINE_POOL
    CALL UPDATE_ONE_MINE
    LD IX,MINE_POOL+MINE_SLOT_SIZE
    CALL UPDATE_ONE_MINE
    RET

DRAW_MINE_CELL:
    LD A,MINE1_CODE : LD B,A
    LD A,(IX+4)
    CP MINE_ANIM_INTERVAL
    JR C,DMC_SET
    LD A,MINE2_CODE : LD B,A
DMC_SET:
    LD A,B
    LD (BULLET_TEMP_BYTE),A
    CALL HORMING_BG_CELL_ADDR
    JP WRITE_BULLET_BYTE_HL

; IX = MINE_POOL slot base, (IX+2) already at its final resting Y
; (landing clamp, or wherever a tank hit caught it mid-air - either way,
; "wherever it actually was" is the death spot, same convention as every
; sprite-based entity's own explosion). Wipes the BG cell (no BG cell
; exists during ACT=2) then arms the shared PAT_EXPLOSION/EXPLOSION_
; COLOR hw sprite convention, same "16x16pxの爆発エフェクトとサウンド"
; every other entity's own death animation already provides - reused
; here rather than building new explosion art, only newly needing an
; ATTRIBUTE slot assignment since Mine itself (a BG entity) doesn't
; otherwise have one.
TRIGGER_MINE_EXPLOSION:
    CALL ERASE_HORMING_BG_CELL
    LD A,2 : LD (IX+0),A
    LD A,EXPLOSION_DURATION : LD (IX+6),A
    CALL SOUND_DESTROY
    RET

; IX = MINE_POOL slot base. ACT=2: counts down (IX+6), drawing the
; shared PAT_EXPLOSION sprite at this instance's own dedicated
; ATTRIBUTE slot (MINE_EXPL_SPR_BASE_SLOT+SPRIDX, (IX+5)) every frame
; until it reaches 0, then hides that slot (Y=209) and returns to idle.
; No drift (EXPLODE_DIR_DX/DY) - a landmine's own impact point doesn't
; move, unlike every other entity's own mid-air kill.
UOM_EXPLODING:
    LD A,(IX+6)
    OR A
    JR Z,UOM_EXPL_HIDE
    DEC A : LD (IX+6),A
    LD A,(IX+5) : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,MINE_SPRITE_ATTRS : ADD HL,BC
    LD A,(IX+2) : LD (HL),A : INC HL
    LD A,(IX+1) : LD (HL),A : INC HL
    LD A,PAT_EXPLOSION : LD (HL),A : INC HL
    LD A,EXPLOSION_COLOR : LD (HL),A
    CALL FLUSH_MINE_SPRITES
    RET
UOM_EXPL_HIDE:
    XOR A : LD (IX+0),A
    LD A,(IX+5) : ADD A,A : ADD A,A
    LD C,A : LD B,0
    LD HL,MINE_SPRITE_ATTRS : ADD HL,BC
    LD A,209 : LD (HL),A
    CALL FLUSH_MINE_SPRITES
    RET

; IX = MINE_POOL slot base. ACT=2: dispatches to the explosion phase
; above. ACT=1: falls (VY accumulates by MINE_GRAVITY once every
; MINE_GRAVITY_INTERVAL frames, see its own comment - "放物線で投下" -
; VX applies every frame regardless, a constant leftward drift,
; "右からしか出ないので左向き放物線のみ"), animates between MINE1_CODE/
; MINE2_CODE, and lands (fixed MINE_LANDING_Y - see its own comment)
; into an explosion exactly like a tank hit does (TRIGGER_MINE_
; EXPLOSION).
UPDATE_ONE_MINE:
    LD A,(IX+0)
    CP 2
    JP Z,UOM_EXPLODING
    OR A
    RET Z

    CALL ERASE_HORMING_BG_CELL
    LD A,(IX+7) : INC A
    CP MINE_GRAVITY_INTERVAL
    JR C,UOM_GRAVITY_HOLD
    XOR A
    LD (IX+7),A
    LD A,(IX+3) : ADD A,MINE_GRAVITY : LD (IX+3),A
    JR UOM_GRAVITY_DONE
UOM_GRAVITY_HOLD:
    LD (IX+7),A
UOM_GRAVITY_DONE:
    LD A,(IX+2) : LD D,A
    LD A,(IX+3) : LD E,A
    LD A,D : ADD A,E : LD (IX+2),A

    LD A,(IX+2)
    CP MINE_LANDING_Y+1
    JR C,UOM_STILL_FALLING
    LD A,MINE_LANDING_Y : LD (IX+2),A
    CALL TRIGGER_MINE_EXPLOSION
    RET
UOM_STILL_FALLING:
    LD A,(IX+1)
    CP MINE_VX
    JR NC,UOM_MOVE_OK
    XOR A : LD (IX+0),A              ; off the left edge - already erased above, nothing left to draw
    RET
UOM_MOVE_OK:
    SUB MINE_VX : LD (IX+1),A
    LD A,(IX+4) : INC A
    CP MINE_ANIM_INTERVAL*2
    JR C,UOM_ANIM_SET
    XOR A
UOM_ANIM_SET:
    LD (IX+4),A
    CALL DRAW_MINE_CELL
    RET

; blasts MINE_SPRITE_ATTRS (8 bytes) to hw sprite slots MINE_EXPL_SPR_
; BASE_SLOT..+1 - same raw DI-wrapped NOP-padded OUT pattern as FLUSH_
; ETANK_SPRITES.
FLUSH_MINE_SPRITES:
    DI
    LD A,MINE_EXPL_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,MINE_SPRITE_ATTRS
    LD B,MINE_SLOT_COUNT*4
FMS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FMS_LOOP
    EI
    RET

; AABB check (8x8 box) against a still-falling mine only (ACT=1) - a
; hit TERMINATES it into the same explosion a landing would (unlike
; every other tank hazard here, a landmine doesn't fly through).
CHECK_ONE_MINE_VS_TANK:
    LD A,(IX+0)
    CP 1
    RET NZ
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD B,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD C,A
    LD A,(IX+1)
    LD D,A
    ADD A,7
    CP B
    RET C
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    RET C
    LD A,(IX+2)
    LD D,A
    ADD A,7
    CP C
    RET C
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    RET C
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL TRIGGER_MINE_EXPLOSION
    RET

CHECK_MINE_VS_TANK:
    LD IX,MINE_POOL
    CALL CHECK_ONE_MINE_VS_TANK
    LD IX,MINE_POOL+MINE_SLOT_SIZE
    CALL CHECK_ONE_MINE_VS_TANK
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
; it's an active U-type shot - also hidden while BOSS_ACT!=0, since U
; is BG-drawn instead during the boss fight (see DRAW_BULLET_CELL) and
; the hw sprite would otherwise sit uselessly on top of it, still
; costing a per-frame VDP write for nothing.
UBUS_ONE:
    LD HL,BULLET_U_SPRITE_ATTRS : ADD HL,DE
    LD A,(IX+0)
    OR A
    JR Z,UBUS_HIDE
    LD A,(IX+1)
    OR A
    JR Z,UBUS_HIDE
    LD A,(BOSS_ACT)
    OR A
    JR NZ,UBUS_HIDE
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
; BULLET_U_SPR_BASE_SLOT..+2 - same raw DI-wrapped NOP-padded,
; auto-incrementing-VDP-pointer pattern as FLUSH_ENEMY_SPRITES.
FLUSH_BULLET_U_SPRITES:
    DI
    LD A,BULLET_U_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,BULLET_U_SPRITE_ATTRS
    LD B,12
FBUS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FBUS_LOOP
    EI
    RET

; ---------- boss (Sasapi) ----------
; per-quadrant (Y-delta,X-delta,pattern-delta) for the 4x4 grid of
; 16x16 quadrants making up the 64x64 sprite, row-major (TL of the
; whole boss first, then rightward, then down a row) - same order
; sasapi_gen.py's own quadrants_from_bits walks, so pattern-delta here
; (quadrant_index*4, one pattern group per quadrant) lines up with
; where that quadrant's own 4 bytes actually landed in SASAPI_QUADS.
BOSS_QUAD_OFFSETS:
    DB 0,0,0,     0,16,4,     0,32,8,     0,48,12
    DB 16,0,16,   16,16,20,   16,32,24,   16,48,28
    DB 32,0,32,   32,16,36,   32,32,40,   32,48,44
    DB 48,0,48,   48,16,52,   48,32,56,   48,48,60

; blasts HL (caller sets SASAPI_QUADS or SASAPI_QUADS_L - both 512
; bytes, sasapi_gen.py) into PAT_SASAPI's own VRAM slot range in one
; shot. Called only when BOSS_DIR actually changes (spawn, and each
; edge-reversal - see UPDATE_BOSS_ALL), not every frame: both facings
; share this same 64-slot range rather than each getting its own (no
; 2nd free 64-slot block exists anywhere in the pattern-code budget -
; see PAT_SASAPI's own comment), so whichever one is "in" has to be
; reloaded on every facing change.
;
; DI/EI-wrapped: LDIRVM (a BIOS routine) has no interrupt-safety margin
; of its own (see UPDATE_TANK_SPRITES' own comment on this exact class
; of bug) - an H.TIMI interrupt landing mid-copy could run its own VDP
; port writes, clobbering the VDP's own internal write-address counter
; this 512-byte transfer relies on auto-incrementing, and corrupt
; whatever unrelated VRAM the interrupt handler's own address happened
; to land on next. Only called a handful of times per game (not every
; frame, unlike FLUSH_BOSS_SPRITES), so a plain DI/EI wrap around the
; whole call is enough here - no need to chunk it into smaller pieces
; the way a genuinely per-frame write would.
LOAD_SASAPI_PATTERNS:
    DI
    LD DE,PAT_SASAPI*8+SPRPAT : LD BC,16*32 : CALL LDIRVM
    EI
    RET

; spawns once via SSC2_FIRE's own unconditional fallthrough (the
; schedule's own final entry - "全てスケジュールに", round34), then
; patrols X between 0 and BOSS_SPAWNX, reversing at the LEFT edge
; same as always - "右から出現し左へ 左端に着いたら反転 右端に". Once
; back at the RIGHT edge, though (BOSS_SPAWNX), it no longer just
; reverses and keeps looping: "右から出て左に行き反転して右端に戻った
; ら 添付のパターンをBGに描画しスプライトは一旦消す ようするに移動中は
; スプライト 停止中はBGて切り替え これは攻撃ポーズなのでその状態で32
; Tick停止後 また巡回 BGは消してスプライトに戻す" - see BOSS_PHASE's
; own comment for the pose sub-state-machine this adds. Y never changes
; (BOSS_SPAWN_Y, horizontal patrol only). Reloads the matching facing's
; pattern data (see LOAD_SASAPI_PATTERNS's own comment) at spawn and at
; each reversal, never mid-step.
UPDATE_BOSS_ALL:
    ; BOSS_ACT=2 = destroyed by CHECK_HIT_PAIR_BOSS (HP reached 0) - the
    ; boss itself never spawns/moves/draws again, but the death/explosion
    ; sequence (INIT_BOSS_EXPLOSION/UPDATE_BOSS_EXPLOSION - a separate
    ; state machine keyed off BOSS_EXPL_STATE, not BOSS_ACT/BOSS_PHASE)
    ; still needs a frame update. Checked before the ACT!=0 check below,
    ; which would otherwise treat 2 the same as 1 (active) and keep
    ; drawing/re-spawning the boss itself forever.
    LD A,(BOSS_ACT)
    CP 2
    JP Z,UPDATE_BOSS_EXPLOSION
    OR A
    RET Z                      ; not yet spawned - SSC2_FIRE's job, not ours
    ; round36-14 Part C: BOSS_FORM dispatch, orthogonal to the ACT check
    ; above - see BOSS_FORM's own EQU comment. FORM=0 is the overwhelming
    ; majority of the boss fight (unchanged UBA_ACTIVE below); FORM=
    ; SPARK reuses the SAME UPDATE_BOSS_EXPLOSION dispatcher a real death
    ; uses (it dispatches purely off BOSS_EXPL_STATE, which TRIGGER_BOSS_
    ; BROKEN_FORM already set to SPARK - no 2nd copy of the spark-frame
    ; logic needed).
    LD A,(BOSS_FORM)
    OR A
    JP Z,UBA_ACTIVE
    CP BOSS_FORM_SPARK
    JP Z,UPDATE_BOSS_EXPLOSION
    JP UPDATE_BOSS_BROKEN_ACTIVE

; the one-shot spawn itself - SSC2_FIRE's own dispatch chain falls
; through to this directly once every earlier schedule entry has
; fired (same convention as Stage1's own SSC_FIRE/BOSS_SPAWN, src/
; CYBER SHMUP.asm). round34-3: SSC2_FIRE already advanced SPAWN2_
; NEXT_INDEX unconditionally BEFORE dispatching here (it's the last
; entry either way), so unlike Stage1's own file this has no separate
; advance call to make at all - no SSC2_ADVANCE routine exists any
; more, the increment happens once, up front, in SSC2_FIRE itself.
S2_BOSS_SPAWN:
    LD HL,SASAPI_QUADS : CALL LOAD_SASAPI_PATTERNS   ; DIR=0 facing below
    ; homing missile's own 5 facings, loaded once here (not at INIT) into
    ; Flyer's own now-permanently-dormant pattern block - "スプライトパ
    ; ターンそんなに使ってるか? 自機とボスだけだぞ...動的に書き換えして
    ; くれ 反転パターンは動的に書き換え" - Flyer never spawns again once
    ; the boss fight starts, so this is safe exactly once, right here,
    ; same "load once when the reused owner is guaranteed gone for good"
    ; idiom as LOAD_SASAPI_PATTERNS's own BigZum-block reuse above. 5x32
    ; bytes (16x16-padded), DI/EI-wrapped same as that call.
    DI
    LD HL,HORMING_SL_SPRITE   : LD DE,PAT_HORMING_SL*8+SPRPAT   : LD BC,32 : CALL LDIRVM
    LD HL,HORMING_DL_SPRITE   : LD DE,PAT_HORMING_DL*8+SPRPAT   : LD BC,32 : CALL LDIRVM
    LD HL,HORMING_DOWN_SPRITE : LD DE,PAT_HORMING_DOWN*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,HORMING_DR_SPRITE   : LD DE,PAT_HORMING_DR*8+SPRPAT   : LD BC,32 : CALL LDIRVM
    LD HL,HORMING_SR_SPRITE   : LD DE,PAT_HORMING_SR*8+SPRPAT   : LD BC,32 : CALL LDIRVM
    ; SBeam's own hw sprite art - SBEAM_CODE(252) is a genuinely free
    ; pattern code (not reused from any other entity's own block), but
    ; loaded here alongside HORMING's for the same one-time-at-spawn
    ; convenience rather than a separate INIT-time block.
    LD HL,SBEAM_SPRITE : LD DE,SBEAM_CODE*8+SPRPAT : LD BC,32 : CALL LDIRVM
    EI
    LD A,1 : LD (BOSS_ACT),A
    LD A,BOSS_SPAWNX : LD (BOSS_X),A
    LD A,BOSS_SPAWN_Y : LD (BOSS_Y),A
    XOR A : LD (BOSS_DIR),A    ; 0 = moving left first - "右から出現し左へ"
    LD A,BOSS_HP_INIT : LD (BOSS_HP),A
    XOR A : LD (BOSS_FLASH_TIMER),A
    XOR A : LD (BOSS_PHASE),A  ; 0 = patrolling/sprite
    XOR A : LD (BOSS_FORM),A   ; round36-14: normal form (not yet broken)
    CALL RESET_THUNDER_POOL
    XOR A : LD (THUNDER_PENDING),A
    XOR A : LD (THUNDER_ELIGIBLE),A   ; not eligible until the first pose ends - see UBAP_END
    XOR A : LD (BOSS_POSE_COUNT),A
    XOR A : LD (SBEAM_ACT),A
    JP UBA_DRAW
UBA_ACTIVE:
    LD A,(BOSS_PHASE)
    CP 1
    JP Z,UBA_POSE
    CP 2
    JP Z,UBA_LEFT_PAUSE
    LD A,(BOSS_DIR)
    OR A
    JR NZ,UBA_MOVE_RIGHT
; "右初期位置から左に移動する際に左斜下8px移動してから水平移動に変更"
; (round11) - the leg starts with a diagonal dip (both axes BOSS_SPEED/
; frame) until BOSS_Y reaches BOSS_SPAWN_Y+BOSS_DIP_DIST, THEN goes
; purely horizontal (the pre-existing logic below, unchanged).
UBA_MOVE_LEFT:
    LD A,(BOSS_Y)
    CP BOSS_SPAWN_Y+BOSS_DIP_DIST
    JR Z,UBA_MOVE_LEFT_HORIZ
    LD A,(BOSS_X) : SUB BOSS_SPEED : LD (BOSS_X),A
    LD A,(BOSS_Y) : ADD A,BOSS_SPEED : LD (BOSS_Y),A
    JP UBA_DRAW
UBA_MOVE_LEFT_HORIZ:
    LD A,(BOSS_X)
    CP BOSS_SPEED
    JR NC,UBA_STEP_LEFT
    XOR A : LD (BOSS_X),A      ; clamp to the left edge
    ; "左端は2Tick停止してから反転発射に 反転した時にボス自身に当たっ
    ; てしまう" (round9) - pause here instead of reversing immediately;
    ; UBA_LEFT_PAUSE below does the actual reversal once it elapses.
    LD A,2 : LD (BOSS_PHASE),A
    LD HL,(GAME_TICK) : LD DE,BOSS_LEFT_PAUSE_TICKS : ADD HL,DE
    LD (BOSS_LEFT_PAUSE_END_TICK),HL
    JP UBA_DRAW
UBA_STEP_LEFT:
    SUB BOSS_SPEED : LD (BOSS_X),A
    CALL CHECK_THUNDER_TRIGGER_LEFT
    JP UBA_DRAW
; waits BOSS_LEFT_PAUSE_TICKS(2) GAME_TICKs at the left edge (true
; 16-bit compare, same idiom as BOSS_POSE_END_TICK) before actually
; reversing - gives whatever Thunder column fired late in the leftward
; leg (positioned near the boss's own right edge, which can be close to
; X=0 by then) a beat to grow/shrink on its own before the boss starts
; moving back into that space. Boss stays drawn as an ordinary
; stationary sprite throughout (unlike the attack pose's own BG art).
UBA_LEFT_PAUSE:
    LD HL,(GAME_TICK)
    LD DE,(BOSS_LEFT_PAUSE_END_TICK)
    OR A
    SBC HL,DE
    JP C,UBA_DRAW              ; still pausing
    LD A,1 : LD (BOSS_DIR),A   ; 反転 - now heads right
    XOR A : LD (BOSS_PHASE),A
    LD HL,SASAPI_QUADS_L : CALL LOAD_SASAPI_PATTERNS
    ; arm this rightward leg's own Thunder trigger - "そのまま左まで行き
    ; 反転後はボスの左に発射". Only once THUNDER_ELIGIBLE(set permanently
    ; at the first UBAP_END) - not during the boss's very first pre-pose
    ; patrol leg.
    LD A,(THUNDER_ELIGIBLE)
    OR A
    JP Z,UBA_DRAW
    XOR A : LD (THUNDER_LEG_START_X),A   ; BOSS_X is 0 here
    LD A,1 : LD (THUNDER_PENDING),A
    JP UBA_DRAW
; "戻る時は逆に到達8px前から右斜め上に移動して初期位置に" (round11) -
; the FINAL BOSS_DIP_DIST px of the rightward leg rise back up
; diagonally (both axes BOSS_SPEED/frame), landing exactly back at
; BOSS_SPAWN_Y right as BOSS_X reaches BOSS_SPAWNX and the pose begins.
; Everything before that point is unchanged, purely horizontal.
UBA_MOVE_RIGHT:
    LD A,(BOSS_X)
    CP BOSS_SPAWNX-BOSS_DIP_DIST
    JR C,UBA_STEP_RIGHT_HORIZ
    LD A,(BOSS_X) : ADD A,BOSS_SPEED
    CP BOSS_SPAWNX
    JR C,UBA_STEP_RIGHT_DIAG
    LD A,BOSS_SPAWNX : LD (BOSS_X),A   ; clamp to the right edge
    LD A,BOSS_SPAWN_Y : LD (BOSS_Y),A   ; clamp the diagonal rise exactly too
    ; enter the attack pose instead of reversing/continuing the patrol
    ; loop - "右端に戻ったら...BGに描画しスプライトは一旦消す". Not
    ; drawn/flushed as a sprite again until the pose ends (UBA_POSE
    ; below), so RET directly here rather than falling into UBA_DRAW.
    LD A,1 : LD (BOSS_PHASE),A
    LD HL,(GAME_TICK) : LD DE,BOSS_POSE_TICKS : ADD HL,DE
    LD (BOSS_POSE_END_TICK),HL
    CALL HIDE_BOSS_SPRITES
    CALL DRAW_SASAPI_HAND
    ; "当然サンダービーム中はホーミングもサンダーも撃たねえんだよ" -
    ; SBeam and the homing volley are mutually exclusive per pose now,
    ; not both armed together: once BOSS_POSE_COUNT reaches SBEAM_POSE_
    ; GATE this pose fires SBeam ONLY (Thunder can't newly trigger
    ; during a pose anyway - its own trigger checks only run mid-patrol,
    ; see CHECK_THUNDER_TRIGGER_LEFT/_RIGHT's own callers).
    LD A,(BOSS_POSE_COUNT)
    CP SBEAM_POSE_GATE
    JR C,UBAMR_ARM_HORMING
    CALL FIRE_SBEAM
    JR UBAMR_POSE_ENTERED
UBAMR_ARM_HORMING:
    CALL ARM_HORMING_VOLLEY
UBAMR_POSE_ENTERED:
    RET
UBA_STEP_RIGHT_DIAG:
    LD (BOSS_X),A
    LD A,(BOSS_Y) : SUB BOSS_SPEED : LD (BOSS_Y),A
    JP UBA_DRAW
UBA_STEP_RIGHT_HORIZ:
    LD A,(BOSS_X) : ADD A,BOSS_SPEED : LD (BOSS_X),A
    CALL CHECK_THUNDER_TRIGGER_RIGHT
    JP UBA_DRAW
; parked at the right edge, hand art on screen, sprite hidden - waits
; for BOSS_POSE_TICKS(32) GAME_TICKs (a true 16-bit SBC HL,DE compare
; against the target captured at pose-entry, same idiom as every other
; GAME_TICK threshold in this file - NOT a raw-frame countdown like
; FLASH_DURATION/EXPLOSION_DURATION, see BOSS_POSE_TICKS' own comment).
; "でお前が指摘してたボスBG表示欠け発生 消えないようにするか 復帰処理
; で対応" - a BG-drawn bullet (F, or U while BOSS_ACT!=0) passing
; through col24-31/row7-14 while posing locally overwrites part of the
; hand art; rather than trying to prevent that write in the first place
; (would need DRAW_BULLET_CELL itself to know about the boss's own
; screen region), DRAW_SASAPI_HAND is now called every frame while
; posing too, not just once at entry - any such corruption gets healed
; back to the correct tile within 1 frame, same "restore the known-
; correct value every frame" idiom this file already uses for terrain/
; night. A real, deliberate per-frame VDP write during the pose only
; (not the whole game) - accepted cost for the fix actually working.
UBA_POSE:
    LD HL,(GAME_TICK)
    LD DE,(BOSS_POSE_END_TICK)
    OR A
    SBC HL,DE
    JR NC,UBAP_END
    CALL DRAW_SASAPI_HAND
    CALL UPDATE_HORMING_VOLLEY
    RET                        ; still posing
UBAP_END:
    ; count this completed pose (SBeam's own SBEAM_POSE_GATE eligibility
    ; check in FIRE_SBEAM) - "サンダービームのあとは最初のホーミングに
    ; 戻るように" (round-6): once the pose that JUST ended was itself an
    ; SBeam pose (BOSS_POSE_COUNT was already >=SBEAM_POSE_GATE at this
    ; pose's own entry, since nothing else touches BOSS_POSE_COUNT mid-
    ; pose), reset the whole cycle back to 0 instead of incrementing
    ; further - otherwise every pose from here on stays >=SBEAM_POSE_GATE
    ; forever and Homing never fires again ("現在はサンダーとサンダー
    ; ビームがリピートしてる"). Below the gate, increment as before.
    LD A,(BOSS_POSE_COUNT)
    CP SBEAM_POSE_GATE
    JR C,UBAP_INC_POSE_COUNT
    XOR A : LD (BOSS_POSE_COUNT),A
    JR UBAP_POSE_COUNT_DONE
UBAP_INC_POSE_COUNT:
    INC A : LD (BOSS_POSE_COUNT),A
UBAP_POSE_COUNT_DONE:
    ; forcibly clear any still-mid-animation beam - UBA_DRAW below
    ; (DRAW_BOSS+FLUSH_BOSS_SPRITES) is about to reclaim SBEAM_SPR_BASE_
    ; SLOT.. for the boss's own real body art again, so SBeam must never
    ; touch those slots past this point.
    XOR A : LD (SBEAM_ACT),A
    ; "また巡回 BGは消してスプライトに戻す" - resume the patrol, moving
    ; left again from the right edge, exactly like the very first spawn.
    XOR A : LD (BOSS_PHASE),A
    XOR A : LD (BOSS_DIR),A
    CALL ERASE_SASAPI_HAND
    LD HL,SASAPI_QUADS : CALL LOAD_SASAPI_PATTERNS
    ; arm this leftward leg's own Thunder trigger - "ホーミング攻撃後左
    ; に移動中に...ボスの右のX位置でボスが16px移動したら発射". BOSS_X is
    ; BOSS_SPAWNX here (just reset to the right edge to resume patrol).
    LD A,(BOSS_X) : LD (THUNDER_LEG_START_X),A
    LD A,1 : LD (THUNDER_PENDING),A
    LD A,1 : LD (THUNDER_ELIGIBLE),A   ; permanently true from here on
UBA_DRAW:
    CALL DRAW_BOSS
    CALL FLUSH_BOSS_SPRITES
    RET

; fills BOSS_SPRITE_ATTRS (16 quadrants x4 bytes) from BOSS_QUAD_OFFSETS
; - a loop over 16 entries rather than 16 hand-unrolled blocks (unlike
; BigZum/Flyer's own draw routines, which only ever had 2-4 quadrants to
; write): plain RAM writes here, no VDP port access, so none of the
; DI/NOP interrupt-safety margin FLUSH_BOSS_SPRITES needs applies to
; this stage. ADD A,(IX+d) isn't a form this assembler supports (see
; mini_z80asm.py's own enc_alu_a - only r8/mHL/imm sources), so each
; delta is loaded into B first and added from there instead.
; hit-flash color resolve, once per draw call (not once per quadrant) -
; same mechanism as every other HP-bearing entity's own flash (see
; UOBZD_COLOR_SET's own comment), but BOSS_FLASH_COLOR instead of the
; shared global FLASH_COLOR - "フラッシュ処理はホワイトだと眩しいので
; レッドに ボス戦だけな 通常はホワイトのままでいじるな".
DRAW_BOSS:
    LD A,(BOSS_FLASH_TIMER)
    OR A
    JR Z,DRB_COLOR_NORMAL
    DEC A : LD (BOSS_FLASH_TIMER),A
    LD A,BOSS_FLASH_COLOR
    JR DRB_COLOR_SET
DRB_COLOR_NORMAL:
    LD A,BOSS_COLOR
DRB_COLOR_SET:
    LD (BOSS_DRAW_COLOR),A

    LD IX,BOSS_QUAD_OFFSETS
    LD HL,BOSS_SPRITE_ATTRS
    LD B,16
DRB_LOOP:
    LD A,(IX+0) : LD C,A
    LD A,(BOSS_Y) : ADD A,C
    LD (HL),A : INC HL
    LD A,(IX+1) : LD C,A
    LD A,(BOSS_X) : ADD A,C
    LD (HL),A : INC HL
    LD A,(IX+2) : LD C,A
    LD A,PAT_SASAPI : ADD A,C
    LD (HL),A : INC HL
    LD A,(BOSS_DRAW_COLOR) : LD (HL),A : INC HL
    INC IX : INC IX : INC IX
    DJNZ DRB_LOOP
    RET

; blasts BOSS_SPRITE_ATTRS (64 bytes) to hw sprite slots
; BOSS_SPR_BASE_SLOT.. as 16 INDEPENDENT per-quadrant DI/EI-wrapped
; mini-bursts (4 bytes each - own address set + own EI/DI pair), not
; one 64-byte burst under a single DI.
;
; "チラツキ...ティアリングに近い...関係のない場所で1pxくらいの
; ゴミも" - a single DI blocks H.TIMI for the WHOLE burst's duration;
; MAINLOOP never HALTs for vblank (same "no per-frame HALT" design as
; every other per-frame VRAM write in this file), so the VDP's own
; raster can land on this exact VRAM range mid-write on any given frame
; regardless of burst size - but a 64-byte burst (this file's single
; largest per-frame sprite write by a wide margin: BigZum's own, the
; next biggest, is half this at 32 bytes) blocks interrupts, and keeps
; the table in a torn state if the raster DOES land there, for a
; stretch several times longer than anything else here ever does,
; making a torn frame far more likely to actually show up than for any
; other entity - not a difference in KIND from every other sprite write
; in this file, just a big enough difference in DEGREE to actually
; become visible. Shrinking each individual DI-protected window back
; down to the same ~4-byte scale everything else in this file already
; uses (Zum's own whole update is this same size) removes the outlier
; without touching the "no per-frame HALT" architecture this whole file
; is built on. Total OUT count goes up (each quadrant re-sets its own
; VRAM address rather than relying on one shared auto-increment run),
; a deliberate trade for many short interrupt-safe windows instead of
; one long unsafe one.
;
; Not directly verifiable by emulator stepping - z80emu.py has no
; interrupt simulation at all (same limitation as UPDATE_TANK_SPRITES'
; own identically-shaped bug/fix - see that comment for the precedent)
; - only that the bytes each mini-burst writes are still correct.
FLUSH_BOSS_SPRITES:
    LD HL,BOSS_SPRITE_ATTRS
    LD C,BOSS_SPR_BASE_SLOT*4
    LD B,16
FBOS_LOOP:
    DI
    LD A,C : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,C : ADD A,4 : LD C,A
    DJNZ FBOS_LOOP
    RET

; called once, the instant the boss is destroyed (HP reaches 0) - hides
; all 16 hw sprite slots permanently (Y=209, same hide convention as
; every other entity). Needed because UPDATE_BOSS_ALL stops calling
; DRAW_BOSS/FLUSH_BOSS_SPRITES entirely once BOSS_ACT=2 (see its own
; CP 2/RET Z guard), so nothing would ever refresh or hide these slots
; again otherwise - only the Y byte of each quadrant needs writing (X/
; pattern/color no longer matter once hidden), so 1 OUT per quadrant
; instead of FLUSH_BOSS_SPRITES's own 4.
HIDE_BOSS_SPRITES:
    LD C,BOSS_SPR_BASE_SLOT*4
    LD B,16
HBOS_LOOP:
    DI
    LD A,C : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,C : ADD A,4 : LD C,A
    DJNZ HBOS_LOOP
    RET

; ---------- boss broken form (round36-14 Part C) ----------
; per-quadrant (Y-delta,X-delta,pattern-delta) for the 2x2 grid of 16x16
; quadrants making up the 32x32 broken body - same row-major "TL first,
; then rightward, then down" walk as BOSS_QUAD_OFFSETS, just 4 entries
; instead of 16 (sasapi_gen.py's own quadrants_from_bits, size=32).
BOSS_BROKEN_QUAD_OFFSETS:
    DB 0,0,0,   0,16,4
    DB 16,0,8,  16,16,12

; blasts HL (caller sets SASAPI_BROKEN_QUADS or SASAPI_BROKEN_QUADS_L,
; both 128 bytes, sasapi_gen.py) into PAT_SASAPI's own VRAM slot range -
; same base as the old 64x64 body (LOAD_SASAPI_PATTERNS), just the first
; 4 of its 16 reused pattern groups, since the old body's own pattern
; data is permanently retired the instant REVEAL_BOSS_BROKEN_FORM runs
; (DRAW_BOSS/FLUSH_BOSS_SPRITES never run again once BOSS_FORM!=0 - see
; UPDATE_BOSS_ALL's own dispatch) - "本体についても...予算は解放される".
; DI/EI-wrapped for the same reason LOAD_SASAPI_PATTERNS itself is (see
; its own comment) - only called on an actual facing change, not per
; frame.
LOAD_SASAPI_BROKEN_PATTERNS:
    DI
    LD DE,PAT_SASAPI*8+SPRPAT : LD BC,BOSS_BROKEN_QUAD_COUNT*32 : CALL LDIRVM
    EI
    RET

; the SPARK->broken-form handoff (UBS_LAST_FRAME, once REASON=1) - the
; board is already clean (all 3 sparks erased by the caller), so this
; just needs to retire the old body for good and bring up the new one.
REVEAL_BOSS_BROKEN_FORM:
    CALL HIDE_BOSS_SPRITES          ; parks the old 16-quadrant body's own slots (10-25) off-screen for good - DRAW_BOSS/FLUSH_BOSS_SPRITES never run again once BOSS_FORM!=0, so nothing would otherwise ever refresh/hide them again
    ; round36-14 follow-up ("で、0で最後の爆発で" - a death CAN still
    ; happen after this, reusing the same real INIT_BOSS_EXPLOSION/UBE_
    ; GROW path as any other death): UBE_GROW's own boss-sprite blink
    ; toggles between FLUSH_BOSS_SPRITES and HIDE_BOSS_SPRITES using
    ; BOSS_SPRITE_ATTRS' OWN staging buffer, which HIDE_BOSS_SPRITES
    ; above never touches (it only writes the live hw SAT directly) - so
    ; a later blink's own FLUSH_BOSS_SPRITES call would resurrect the
    ; stale OLD 64x64 body from whatever it last held. Stomping every
    ; quadrant's own Y byte to 209 in the STAGING buffer too makes that
    ; later flush a harmless no-op (still hidden) instead of a visual bug.
    LD HL,BOSS_SPRITE_ATTRS
    LD B,16
RBBF_HIDE_STAGE:
    LD (HL),209 : INC HL : INC HL : INC HL : INC HL
    DJNZ RBBF_HIDE_STAGE
    LD A,BOSS_EXPL_STATE_DONE : LD (BOSS_EXPL_STATE),A   ; retire the shared SPARK/GROW/etc state machine - UPDATE_BOSS_ALL never dispatches to it again anyway once BOSS_FORM leaves SPARK, this just keeps it inert if anything ever reread it
    LD HL,SASAPI_BROKEN_QUADS : CALL LOAD_SASAPI_BROKEN_PATTERNS
    XOR A : LD (BOSS_BROKEN_DIR),A   ; matches the unmirrored QUADS just loaded above - UPDATE_BOSS_BROKEN_ACTIVE's own RECENTERING branch corrects this on its very first frame if the real direction toward center differs
    ; round36-14 follow-up #4 ("で、停止中にビーム攻撃をする"): load the
    ; 4 fixed beam-angle patterns once here too, same "load once when the
    ; reused owner is guaranteed gone for good" idiom as LOAD_SASAPI_
    ; BROKEN_PATTERNS itself - see BOSS_BROKEN_BEAM_TABLE's own comment
    ; for why these 4 codes (PAT_SASAPI+16/+20/+24/+28, each spanning 4
    ; consecutive sub-pattern codes) rather than reusing old SBeam's own
    ; SBEAM_CODE.
    DI
    LD HL,BOSS_BROKEN_BEAM1_SPRITE : LD DE,BOSS_BROKEN_BEAM_CODE1*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BOSS_BROKEN_BEAM2_SPRITE : LD DE,BOSS_BROKEN_BEAM_CODE2*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BOSS_BROKEN_BEAM3_SPRITE : LD DE,BOSS_BROKEN_BEAM_CODE3*8+SPRPAT : LD BC,32 : CALL LDIRVM
    LD HL,BOSS_BROKEN_BEAM4_SPRITE : LD DE,BOSS_BROKEN_BEAM_CODE4*8+SPRPAT : LD BC,32 : CALL LDIRVM
    EI
    CALL HIDE_BOSS_BROKEN_BEAM_ALL
    CALL FLUSH_BOSS_BROKEN_BEAM_SPRITES
    ; round36-14 follow-up #2 ("インフィニティ軌道はその位置から始まる
    ; が一旦中央に寄せろ センタリングするかたちで") - appear right where
    ; the old body died (BOSS_X/BOSS_Y already hold that, untouched since
    ; TRIGGER_BOSS_BROKEN_FORM), then walk toward the fixed orbit center
    ; before the figure-8 loop itself starts - see BOSS_BROKEN_
    ; RECENTERING's own comment.
    LD A,1 : LD (BOSS_BROKEN_RECENTERING),A
    LD A,BOSS_FORM_ACTIVE : LD (BOSS_FORM),A
    ; same "draw once immediately, don't wait a whole extra frame for the
    ; very first real position/sprite" convention S2_BOSS_SPAWN's own
    ; tail (JP UBA_DRAW) already uses - without this, slots 10-13 would
    ; sit at their stale zeroed reset state for exactly 1 frame.
    JP UPDATE_BOSS_BROKEN_ACTIVE

; A = a random "how many path-index steps until the next lap-stop" value
; - see BOSS_BROKEN_LAP_STEPS_MIN/_RANGE's own comment. Same GAME_RNG^
; TICK^live-position-byte mixing idiom as PICK_HORMING_TARGET_X; RANGE
; is a power of 2 so a plain AND folds it, no reject-and-subtract
; needed. A leaf routine (only touches A/B), safe to CALL from anywhere
; without saving other registers.
ROLL_BOSS_BROKEN_LAP_STEPS:
    LD A,(GAME_RNG) : LD B,A
    LD A,(TICK) : XOR B : LD B,A
    LD A,(BOSS_BROKEN_PATH_INDEX) : XOR B
    AND BOSS_BROKEN_LAP_STEPS_RANGE-1
    ADD A,BOSS_BROKEN_LAP_STEPS_MIN
    RET

; A=current value, B=target, C=step size. Steps A by C toward B (up or
; down, whichever direction is needed), clamped so it never overshoots
; past B - repeated calls converge exactly onto B and stay there. A leaf
; routine (only touches A/B/C), used by UPDATE_BOSS_BROKEN_ACTIVE's own
; RECENTERING sub-phase for both axes.
STEP_TOWARD:
    CP B
    RET Z
    JR C,STW_UP
    SUB C
    CP B
    RET NC
    LD A,B
    RET
STW_UP:
    ADD A,C
    CP B
    RET C
    LD A,B
    RET

; round36-14 Part C's own per-frame update, dispatched from UPDATE_BOSS_
; ALL once BOSS_FORM=ACTIVE(2) (in place of UBA_ACTIVE). Two sub-phases -
; see BOSS_BROKEN_RECENTERING's own comment for why: 1) RECENTERING (set
; by REVEAL_BOSS_BROKEN_FORM) walks BOSS_X/BOSS_Y from wherever the old
; body actually died toward the fixed BOSS_BROKEN_CENTER_X/Y point at
; BOSS_BROKEN_RECENTER_SPEED px/frame; 2) once arrived, the orbit itself
; runs - "インフィニティの起動で画面を移動しランダムタイミングで停止し
; 少ししてまた回る これがシーケンスで" - a repeating MOVING<->stopped
; cycle, each phase's own random duration re-rolled at the moment it's
; entered (compared every frame via the same true-16-bit-SBC-HL,DE idiom
; as BOSS_POSE_END_TICK), walking a precomputed figure-8 (lemniscate)
; path LUT (BOSS_BROKEN_PATH_X/_Y/_DIR, BOSS_BROKEN_PATH_LEN points,
; sasapi_gen.py, ABSOLUTE coordinates centered on that same fixed point)
; via an explicit BOSS_BROKEN_PATH_INDEX that only advances while MOVING
; (one step every BOSS_BROKEN_PATH_HOLD_FRAMES raw frames) - unlike a
; value derived straight from GAME_TICK, an explicit index naturally
; freezes in place while stopped and resumes from the exact same point
; once moving again, with no separate "frozen index" bookkeeping needed.
UPDATE_BOSS_BROKEN_ACTIVE:
    ; round36-14 follow-up#4 3rd real-hardware feedback ("ビームが飛んで
    ; 来ないな...発射して飛ばすんだよ") - in-flight beam projectiles now
    ; animate every single frame, independently of RECENTERING/MOVING/
    ; STOPPED below (a beam launched right before the boss resumes
    ; orbiting must keep flying, not freeze or vanish).
    CALL UPDATE_BOSS_BROKEN_BEAM_FLIGHT
    CALL FLUSH_BOSS_BROKEN_BEAM_SPRITES
    LD A,(BOSS_BROKEN_RECENTERING)
    OR A
    JR Z,UBBA_ORBIT

    ; --- sub-phase 1: RECENTERING ---
    LD A,(BOSS_X) : LD B,BOSS_BROKEN_CENTER_X : LD C,BOSS_BROKEN_RECENTER_SPEED
    CALL STEP_TOWARD
    LD (BOSS_X),A
    LD A,(BOSS_Y) : LD B,BOSS_BROKEN_CENTER_Y : LD C,BOSS_BROKEN_RECENTER_SPEED
    CALL STEP_TOWARD
    LD (BOSS_Y),A
    ; face toward the center horizontally while still walking (same
    ; BOSS_DIR convention as the orbit's own table: B=0 normal/left-
    ; facing QUADS, B=1 mirrored/right-facing QUADS_L)
    LD A,(BOSS_X)
    CP BOSS_BROKEN_CENTER_X
    JR Z,UBBA_RC_KEEPDIR
    JR C,UBBA_RC_RIGHT
    LD B,0
    JR UBBA_RC_HAVE_DIR
UBBA_RC_RIGHT:
    LD B,1
    JR UBBA_RC_HAVE_DIR
UBBA_RC_KEEPDIR:
    LD A,(BOSS_BROKEN_DIR) : LD B,A
UBBA_RC_HAVE_DIR:
    ; arrived at the center exactly on both axes? hand off to the orbit,
    ; starting at the loop's own (0,0)-offset crossing point so there's
    ; no visual jump at the handoff.
    LD A,(BOSS_X) : CP BOSS_BROKEN_CENTER_X
    JP NZ,UBBA_APPLY_DIR   ; JR range exceeded - ORBIT's own block sits between here and the shared tail
    LD A,(BOSS_Y) : CP BOSS_BROKEN_CENTER_Y
    JP NZ,UBBA_APPLY_DIR
    XOR A : LD (BOSS_BROKEN_RECENTERING),A
    LD A,BOSS_BROKEN_PATH_CROSS_INDEX : LD (BOSS_BROKEN_PATH_INDEX),A
    XOR A : LD (BOSS_BROKEN_FRAME_COUNTER),A
    LD A,1 : LD (BOSS_BROKEN_MOVING),A
    PUSH BC
    CALL ROLL_BOSS_BROKEN_LAP_STEPS
    LD (BOSS_BROKEN_STEPS_TO_STOP),A
    POP BC
    JP UBBA_APPLY_DIR

    ; --- sub-phase 2: ORBIT ---
; round36-14 follow-up #4 ("SasapiBrokenの停止はインフィニティ軌道の1周
; に１回何処かで停止 で、停止中にビーム攻撃をする") - MOVING=1 walks the
; path index (as before); reaching 0 on BOSS_BROKEN_STEPS_TO_STOP (only
; decremented on a REAL path-index advance, not every raw frame - see
; its own comment) parks it and hands off to the 4-beam sequence
; (UBBA_BEAM_SEQ/UPDATE_BOSS_BROKEN_BEAM_SEQ), which flips MOVING back
; to 1 and re-rolls STEPS_TO_STOP once all 4 beams have fired and the
; last one's own hold time elapses.
UBBA_ORBIT:
    LD A,(BOSS_BROKEN_MOVING)
    OR A
    JP Z,UBBA_BEAM_SEQ

    LD A,(BOSS_BROKEN_FRAME_COUNTER) : INC A
    CP BOSS_BROKEN_PATH_HOLD_FRAMES
    JR C,UBBA_FC_SAVE
    XOR A
    PUSH AF
    LD A,(BOSS_BROKEN_PATH_INDEX) : INC A
    AND BOSS_BROKEN_PATH_LEN-1
    LD (BOSS_BROKEN_PATH_INDEX),A
    POP AF
    ; a real step happened this frame - count it toward this lap's stop.
    LD HL,BOSS_BROKEN_STEPS_TO_STOP
    DEC (HL)
    JR NZ,UBBA_FC_SAVE
    XOR A : LD (BOSS_BROKEN_MOVING),A
    CALL ARM_BOSS_BROKEN_BEAM_SEQ
UBBA_FC_SAVE:
    LD (BOSS_BROKEN_FRAME_COUNTER),A
    JR UBBA_POS

UBBA_BEAM_SEQ:
    CALL UPDATE_BOSS_BROKEN_BEAM_SEQ

UBBA_POS:
    LD A,(BOSS_BROKEN_PATH_INDEX)
    LD E,A : LD D,0
    LD HL,BOSS_BROKEN_PATH_X : ADD HL,DE : LD A,(HL) : LD (BOSS_X),A
    LD HL,BOSS_BROKEN_PATH_Y : ADD HL,DE : LD A,(HL) : LD (BOSS_Y),A
    LD HL,BOSS_BROKEN_PATH_DIR : ADD HL,DE : LD A,(HL) : LD B,A

UBBA_APPLY_DIR:
    LD A,(BOSS_BROKEN_DIR)
    CP B
    JR Z,UBBA_DRAW
    LD A,B : LD (BOSS_BROKEN_DIR),A
    OR A
    JR NZ,UBBA_LOAD_L
    LD HL,SASAPI_BROKEN_QUADS : CALL LOAD_SASAPI_BROKEN_PATTERNS
    JR UBBA_DRAW
UBBA_LOAD_L:
    LD HL,SASAPI_BROKEN_QUADS_L : CALL LOAD_SASAPI_BROKEN_PATTERNS
UBBA_DRAW:
    CALL DRAW_BOSS_BROKEN
    CALL FLUSH_BOSS_BROKEN_SPRITES
    RET

; fills BOSS_BROKEN_SPRITE_ATTRS (4 quadrants x4 bytes) from BOSS_BROKEN_
; QUAD_OFFSETS - same shape/hit-flash handling as DRAW_BOSS, just 4
; quadrants instead of 16 (and reusing the exact same BOSS_FLASH_TIMER/
; BOSS_DRAW_COLOR/BOSS_COLOR/BOSS_FLASH_COLOR the old body used - DRAW_
; BOSS itself never runs again once BOSS_FORM!=0, so there's no risk of
; the two decrementing BOSS_FLASH_TIMER twice in the same frame).
DRAW_BOSS_BROKEN:
    LD A,(BOSS_FLASH_TIMER)
    OR A
    JR Z,DRBB_COLOR_NORMAL
    DEC A : LD (BOSS_FLASH_TIMER),A
    LD A,BOSS_FLASH_COLOR
    JR DRBB_COLOR_SET
DRBB_COLOR_NORMAL:
    LD A,BOSS_COLOR
DRBB_COLOR_SET:
    LD (BOSS_DRAW_COLOR),A

    LD IX,BOSS_BROKEN_QUAD_OFFSETS
    LD HL,BOSS_BROKEN_SPRITE_ATTRS
    LD B,BOSS_BROKEN_QUAD_COUNT
DRBB_LOOP:
    LD A,(IX+0) : LD C,A
    LD A,(BOSS_Y) : ADD A,C
    LD (HL),A : INC HL
    LD A,(IX+1) : LD C,A
    LD A,(BOSS_X) : ADD A,C
    LD (HL),A : INC HL
    LD A,(IX+2) : LD C,A
    LD A,PAT_SASAPI : ADD A,C
    LD (HL),A : INC HL
    LD A,(BOSS_DRAW_COLOR) : LD (HL),A : INC HL
    INC IX : INC IX : INC IX
    DJNZ DRBB_LOOP
    RET

; blasts BOSS_BROKEN_SPRITE_ATTRS (16 bytes) to hw sprite slots
; BOSS_BROKEN_SPR_BASE_SLOT.. as 4 independent per-quadrant DI/EI-wrapped
; mini-bursts - same shape/reasoning as FLUSH_BOSS_SPRITES's own comment
; (many short interrupt-safe windows instead of one long one), just 4
; quadrants instead of 16.
FLUSH_BOSS_BROKEN_SPRITES:
    LD HL,BOSS_BROKEN_SPRITE_ATTRS
    LD C,BOSS_BROKEN_SPR_BASE_SLOT*4
    LD B,BOSS_BROKEN_QUAD_COUNT
FBBS_LOOP:
    DI
    LD A,C : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    LD A,(HL) : OUT (98h),A : INC HL
    PUSH BC : POP BC : NOP : NOP
    EI
    LD A,C : ADD A,4 : LD C,A
    DJNZ FBBS_LOOP
    RET

; ---------- boss broken form: 4-beam stop-attack (round36-14 follow-up
; #4, "SasapiBrokenの停止はインフィニティ軌道の1周に１回何処かで停止
; で、停止中にビーム攻撃をする 添付がそのキャラデータ 1から4までの左方
; 向斜め下に順の角度でビーム発射") ----------
; per-beam (XOFS,CODE) - dispatched by BOSS_BROKEN_BEAM_COUNT(0-3). XOFS
; is a signed CELL offset from the body's own horizontal center (BOSS_X's
; own top-left +2 cells/16px) - "Sbeam2,3は中央から出ているが 1,4は発射
; 位置が1は右上 4が左上になっているので 1は2,3の左に4は右に8pxオフセッ
; トしたX位置になる" (2/3 fire from the body's own center; 1 is 8px/1
; cell left of it, 4 is 8px/1 cell right). CODE is the hw sprite pattern
; each beam's own art was loaded into (BOSS_BROKEN_BEAM_CODE1-4,
; PAT_SASAPI+16/+20/+24/+28 - see that constant's own comment for why
; these codes specifically, not old SBeam's own SBEAM_CODE) - each beam
; is now a single already-complete 16x16 picture (see FIRE_BOSS_BROKEN_
; BEAM's own comment for why there's no longer a slope/direction to
; store here: the angle is baked into the art itself, not computed at
; runtime).
; round36-14 follow-up#4 2nd real-hardware feedback ("全然違うぞ...
; グラフィックも壊れてる"): a single 16x16 hw sprite occupies 4
; CONSECUTIVE pattern codes (TL,BL,TR,BR - same convention BOSS_BROKEN_
; QUAD_OFFSETS' own 0/4/8/12 deltas already use for the body), not 1 -
; the first attempt spaced these 4 beam codes only 1 apart (16,17,18,19),
; so each beam's own 32-byte LDIRVM load silently overwrote 3 of the
; PREVIOUS beam's own 4 sub-pattern codes. Fixed by spacing them 4 apart
; (16,20,24,28) - but that alone didn't fix the real-hardware symptom,
; because a SEPARATE assembler forward-reference bug (see BOSS_BROKEN_
; BEAM_CODE1's own comment, now up near PAT_SASAPI's own definition
; where these EQUs actually live) meant REVEAL_BOSS_BROKEN_FORM's own
; LDIRVM calls used the wrong destination addresses regardless of the
; spacing fix. Both bugs are now fixed.
; per-beam (XOFS,DXMAG,DYMAG,XDIR,CODE), 5 bytes/entry - restored from
; the 1st attempt's own table shape (round36-14 follow-up#4 3rd real-
; hardware feedback: a static single sprite isn't a real projectile,
; see LAUNCH_BOSS_BROKEN_BEAM's own comment). XOFS is a signed CELL
; offset from the body's own horizontal center (only used at launch, to
; place the projectile's own starting point); DXMAG/DYMAG/XDIR are now
; each beam's own per-frame PIXEL velocity (not a Bresenham-line-draw
; ratio any more - see BOSS_BROKEN_BEAM_SLOT_COUNT's own comment for
; the resulting per-beam speed difference).
BOSS_BROKEN_BEAM_TABLE:
    DB -1, 2, 1, -1, BOSS_BROKEN_BEAM_CODE1
    DB  0, 2, 5, -1, BOSS_BROKEN_BEAM_CODE2
    DB  0, 2, 5,  1, BOSS_BROKEN_BEAM_CODE3
    DB  1, 2, 1,  1, BOSS_BROKEN_BEAM_CODE4

; zeroes the sequence's own count/timer - 0 timer fires beam1 on the
; very next UPDATE_BOSS_BROKEN_BEAM_SEQ tick, same "0=fire immediately"
; idiom as ARM_HORMING_VOLLEY.
ARM_BOSS_BROKEN_BEAM_SEQ:
    XOR A
    LD (BOSS_BROKEN_BEAM_COUNT),A
    LD (BOSS_BROKEN_BEAM_TIMER),A
    RET

; per-frame tick while BOSS_BROKEN_MOVING=0 (stopped) - same COUNT/TIMER
; countdown idiom as UPDATE_HORMING_VOLLEY, unchanged ("発射タイミングは
; 今でいいが" - the 1->4 firing order and BOSS_BROKEN_BEAM_INTERVAL
; spacing between shots stayed exactly as before). What changed (round
; 36-14 follow-up#4 3rd real-hardware feedback, "ビームが飛んで来ない
; な...発射して飛ばすんだよ") is what "fire" actually does: each shot
; now LAUNCHes an independent flying projectile (LAUNCH_BOSS_BROKEN_
; BEAM) into its own slot instead of replacing a single static sprite -
; so firing beam2 no longer hides beam1, and the final wait before
; resuming movement no longer hides whichever beam is still mid-flight
; (UPDATE_BOSS_BROKEN_BEAM_FLIGHT, called every frame regardless of
; BOSS_BROKEN_MOVING, keeps animating/colliding all in-flight beams
; independently of this sequencer and of the orbit's own stop/move
; cycle).
UPDATE_BOSS_BROKEN_BEAM_SEQ:
    LD A,(BOSS_BROKEN_BEAM_COUNT)
    CP 4
    JR NZ,UBBBS_FIRING
    LD A,(BOSS_BROKEN_BEAM_TIMER)
    OR A
    JR Z,UBBBS_RESUME
    DEC A : LD (BOSS_BROKEN_BEAM_TIMER),A
    RET
UBBBS_RESUME:
    LD A,1 : LD (BOSS_BROKEN_MOVING),A
    CALL ROLL_BOSS_BROKEN_LAP_STEPS
    LD (BOSS_BROKEN_STEPS_TO_STOP),A
    RET
UBBBS_FIRING:
    LD A,(BOSS_BROKEN_BEAM_TIMER)
    OR A
    JR Z,UBBBS_FIRE
    DEC A : LD (BOSS_BROKEN_BEAM_TIMER),A
    RET
UBBBS_FIRE:
    CALL LAUNCH_BOSS_BROKEN_BEAM
    LD A,(BOSS_BROKEN_BEAM_COUNT) : INC A : LD (BOSS_BROKEN_BEAM_COUNT),A
    LD A,BOSS_BROKEN_BEAM_INTERVAL : LD (BOSS_BROKEN_BEAM_TIMER),A
    RET

; called once, at REVEAL_BOSS_BROKEN_FORM time - parks all 4 of the
; beam-attack's own hw sprite slots off-screen up front AND clears every
; slot's own BOSS_BROKEN_PROJ_ACTIVE flag, so nothing stale (a previous
; game's own leftover state, or uninitialized RAM) could show/fly before
; the first beam is ever actually launched - same "explicit up-front
; init" precedent as every other hw sprite pool's own boot-time hide.
HIDE_BOSS_BROKEN_BEAM_ALL:
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS
    LD B,BOSS_BROKEN_BEAM_SLOT_COUNT
HBBBA_LOOP:
    LD (HL),209 : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    DJNZ HBBBA_LOOP
    LD HL,BOSS_BROKEN_PROJ_ACTIVE
    LD B,BOSS_BROKEN_BEAM_SLOT_COUNT
HBBBA_ACT_LOOP:
    XOR A : LD (HL),A : INC HL
    DJNZ HBBBA_ACT_LOOP
    RET

; launches whichever of the 4 fixed-angle beams BOSS_BROKEN_BEAM_COUNT
; (0-3) selects as an independent flying projectile - its own slot
; (same index as BOSS_BROKEN_BEAM_COUNT, since each of the 4 beam types
; only ever launches once per stop-sequence) gets a starting position
; (body's own center cell +XOFS, same placement math as the 2nd
; attempt's static sprite) and a per-frame pixel velocity (DXMAG/DYMAG
; from the table, signed by XDIR) - UPDATE_BOSS_BROKEN_BEAM_FLIGHT then
; advances and redraws it every frame from here on, independently of
; this routine and of the other 3 beams' own slots. round36-14 follow-
; up#4 3rd real-hardware feedback ("ビームが飛んで来ないな...発射して
; 飛ばすんだよ") - the previous version stopped here (a single static
; placement); this one hands off to an ongoing per-frame update instead.
LAUNCH_BOSS_BROKEN_BEAM:
    LD A,(BOSS_BROKEN_BEAM_COUNT)
    LD E,A : LD D,0                                ; DE = this beam's own slot index (0-3) - also used to index the PROJ_* arrays below, unaffected by ADD HL,DE
    LD HL,BOSS_BROKEN_BEAM_TABLE
    ADD HL,DE : ADD HL,DE : ADD HL,DE : ADD HL,DE : ADD HL,DE   ; HL = this beam's own 5-byte table entry (*5 via repeated add - no multiply instruction)

    LD A,(HL) : INC HL : LD B,A                    ; XOFS (signed cells)
    LD A,(BOSS_X) : SRL A : SRL A : SRL A           ; body's own top-left column
    ADD A,2 : ADD A,B                               ; +2 cells (body's own horizontal center) + this beam's own XOFS
    ADD A,A : ADD A,A : ADD A,A                     ; back to pixels - the CENTER column's own left edge
    SUB 8                                            ; recenter: the sprite is 16px wide, so its own left edge sits 8px left of that column
    PUSH HL                                          ; save the table cursor (now pointing at DXMAG) - HL is about to be reused
    LD HL,BOSS_BROKEN_PROJ_X : ADD HL,DE : LD (HL),A
    POP HL

    LD A,(BOSS_Y) : SRL A : SRL A : SRL A
    ADD A,2                                          ; body's own vertical center row
    ADD A,A : ADD A,A : ADD A,A                      ; pixels - this beam's own starting top edge
    PUSH HL
    LD HL,BOSS_BROKEN_PROJ_Y : ADD HL,DE : LD (HL),A
    POP HL

    LD A,(HL) : INC HL : LD B,A                     ; DXMAG (unsigned magnitude)
    LD A,(HL) : INC HL : LD C,A                     ; DYMAG (unsigned, always applied as +down)
    LD A,(HL) : INC HL                              ; XDIR (+1 or -1)
    OR A
    JP P,LBBB_DX_POS
    XOR A : SUB B                                    ; A = -DXMAG (XDIR was negative)
    JR LBBB_DX_SET
LBBB_DX_POS:
    LD A,B
LBBB_DX_SET:
    PUSH HL
    LD HL,BOSS_BROKEN_PROJ_DX : ADD HL,DE : LD (HL),A
    POP HL
    LD A,C
    PUSH HL
    LD HL,BOSS_BROKEN_PROJ_DY : ADD HL,DE : LD (HL),A
    POP HL

    LD A,(HL)                                        ; CODE (5th and last field)
    LD HL,BOSS_BROKEN_PROJ_CODE : ADD HL,DE : LD (HL),A
    LD A,1
    LD HL,BOSS_BROKEN_PROJ_ACTIVE : ADD HL,DE : LD (HL),A
    CALL SOUND_SASAPI_LASER
    RET

; per-frame update for all 4 potentially-in-flight beam projectiles -
; called unconditionally from UPDATE_BOSS_BROKEN_ACTIVE (every frame
; while BOSS_FORM=ACTIVE, regardless of RECENTERING/MOVING/STOPPED sub-
; phase), independently of the firing sequencer above. Each active slot
; steps by its own BOSS_BROKEN_PROJ_DX/DY (signed 8-bit add - a real Z80
; ADD A,r, so this only works correctly because DX/DY are always small
; enough that wraparound never legitimately occurs before the bounds
; check below catches it) and is deactivated the instant it leaves the
; visible screen area in any direction (all 4 beams point downward, so
; only the bottom edge, plus whichever horizontal edge XDIR sends it
; toward, are ever actually reached in practice).
; round36-14 follow-up#8 ("ではループ展開を検討"): fully loop-unrolled
; (4 straight-line copies, one per slot, BOSS_BROKEN_PROJ_*+0..+3 baked
; in as compile-time constant addresses) - the previous round
; (follow-up#7) had already tightened the shared 4-iteration loop body
; to compute its own DE-index once per slot instead of re-deriving it
; per field access, but every field access still paid for a runtime
; ADD HL,DE (11T) on top of the LD HL,nn/LD A,(HL) pair. With the slot
; known at compile time, that whole indexing step disappears - a single
; read becomes a plain LD A,(nn) (13T, replacing LD HL,nn+ADD HL,DE+
; LD A,(HL) = 28T), and a read-modify-write pair (very common in this
; routine - X/Y bounds-check-then-move) drops from 53T to 44T at the
; SAME byte count, because Z80's JP cc,nn costs a fixed 10T whether
; taken or not (unlike the register-shuffling this saves elsewhere).
; The 4 slots' own control flow (X_RIGHT/X_LEFT/OFFSCREEN/HIDE_SLOT
; branches) is necessarily duplicated 4x now instead of shared via the
; loop - the real cost of unrolling - but this assembler's `LD A,(nn)`/
; `LD (nn),A` direct-addressing forms turned out cheap enough per-access
; that the net ROM cost for this routine was only +277 bytes (158->435).
; T-state win measured via the same fresh_cpu()+cpu.reset_stats()+
; call_routine() methodology as follow-up#7: 4-active 2227T->1292T
; (-42%), 0-active 839T->370T(-56%). See CHECK_BOSS_BROKEN_BEAM_VS_TANK
; below for the same treatment applied to the tank-collision check.
; NOTE for future edits to either unrolled routine: this assembler's
; eval_expr has NO operator precedence (left-to-right only) - an
; expression like `BASE+N*4` parses as `(BASE+N)*4`, not `BASE+(N*4)`;
; any per-slot multiply (e.g. BOSS_BROKEN_BEAM_SPRITE_ATTRS+N*4) MUST
; be written as a single already-multiplied literal (`+0`/`+4`/`+8`/
; `+12`) - this bug was actually hit and caught by boss_broken_form_
; test.py during development (4 failures, all sprite-attrs-related)
; before being fixed this same round.
UPDATE_BOSS_BROKEN_BEAM_FLIGHT:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+0)
    OR A
    JP Z,UBBBF_HIDE0

    LD A,(BOSS_BROKEN_PROJ_DX+0)
    OR A
    JP M,UBBBF_XL0
UBBBF_XR0:
    LD B,A
    LD A,239 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+0)
    CP C
    JP NC,UBBBF_OFFS0
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+0),A
    JP UBBBF_Y0
UBBBF_XL0:
    LD B,A
    XOR A : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+0)
    CP C
    JP C,UBBBF_OFFS0
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+0),A

UBBBF_Y0:
    LD A,(BOSS_BROKEN_PROJ_DY+0) : LD B,A
    LD A,191 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_Y+0)
    CP C
    JP NC,UBBBF_OFFS0
    ADD A,B
    LD (BOSS_BROKEN_PROJ_Y+0),A

    LD A,(BOSS_BROKEN_PROJ_Y+0) : LD B,A
    LD A,(BOSS_BROKEN_PROJ_X+0) : LD C,A
    LD A,(BOSS_BROKEN_PROJ_CODE+0)
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+0
    LD (HL),B : INC HL
    LD (HL),C : INC HL
    LD (HL),A : INC HL
    LD A,BOSS_BROKEN_BEAM_COLOR : LD (HL),A
    JP UBBBF_SLOT1

UBBBF_OFFS0:
    XOR A
    LD (BOSS_BROKEN_PROJ_ACTIVE+0),A
UBBBF_HIDE0:
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+0
    LD (HL),209 : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A

UBBBF_SLOT1:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+1)
    OR A
    JP Z,UBBBF_HIDE1

    LD A,(BOSS_BROKEN_PROJ_DX+1)
    OR A
    JP M,UBBBF_XL1
UBBBF_XR1:
    LD B,A
    LD A,239 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+1)
    CP C
    JP NC,UBBBF_OFFS1
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+1),A
    JP UBBBF_Y1
UBBBF_XL1:
    LD B,A
    XOR A : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+1)
    CP C
    JP C,UBBBF_OFFS1
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+1),A

UBBBF_Y1:
    LD A,(BOSS_BROKEN_PROJ_DY+1) : LD B,A
    LD A,191 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_Y+1)
    CP C
    JP NC,UBBBF_OFFS1
    ADD A,B
    LD (BOSS_BROKEN_PROJ_Y+1),A

    LD A,(BOSS_BROKEN_PROJ_Y+1) : LD B,A
    LD A,(BOSS_BROKEN_PROJ_X+1) : LD C,A
    LD A,(BOSS_BROKEN_PROJ_CODE+1)
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+4
    LD (HL),B : INC HL
    LD (HL),C : INC HL
    LD (HL),A : INC HL
    LD A,BOSS_BROKEN_BEAM_COLOR : LD (HL),A
    JP UBBBF_SLOT2

UBBBF_OFFS1:
    XOR A
    LD (BOSS_BROKEN_PROJ_ACTIVE+1),A
UBBBF_HIDE1:
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+4
    LD (HL),209 : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A

UBBBF_SLOT2:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+2)
    OR A
    JP Z,UBBBF_HIDE2

    LD A,(BOSS_BROKEN_PROJ_DX+2)
    OR A
    JP M,UBBBF_XL2
UBBBF_XR2:
    LD B,A
    LD A,239 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+2)
    CP C
    JP NC,UBBBF_OFFS2
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+2),A
    JP UBBBF_Y2
UBBBF_XL2:
    LD B,A
    XOR A : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+2)
    CP C
    JP C,UBBBF_OFFS2
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+2),A

UBBBF_Y2:
    LD A,(BOSS_BROKEN_PROJ_DY+2) : LD B,A
    LD A,191 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_Y+2)
    CP C
    JP NC,UBBBF_OFFS2
    ADD A,B
    LD (BOSS_BROKEN_PROJ_Y+2),A

    LD A,(BOSS_BROKEN_PROJ_Y+2) : LD B,A
    LD A,(BOSS_BROKEN_PROJ_X+2) : LD C,A
    LD A,(BOSS_BROKEN_PROJ_CODE+2)
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+8
    LD (HL),B : INC HL
    LD (HL),C : INC HL
    LD (HL),A : INC HL
    LD A,BOSS_BROKEN_BEAM_COLOR : LD (HL),A
    JP UBBBF_SLOT3

UBBBF_OFFS2:
    XOR A
    LD (BOSS_BROKEN_PROJ_ACTIVE+2),A
UBBBF_HIDE2:
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+8
    LD (HL),209 : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A

UBBBF_SLOT3:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+3)
    OR A
    JP Z,UBBBF_HIDE3

    LD A,(BOSS_BROKEN_PROJ_DX+3)
    OR A
    JP M,UBBBF_XL3
UBBBF_XR3:
    LD B,A
    LD A,239 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+3)
    CP C
    JP NC,UBBBF_OFFS3
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+3),A
    JP UBBBF_Y3
UBBBF_XL3:
    LD B,A
    XOR A : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_X+3)
    CP C
    JP C,UBBBF_OFFS3
    ADD A,B
    LD (BOSS_BROKEN_PROJ_X+3),A

UBBBF_Y3:
    LD A,(BOSS_BROKEN_PROJ_DY+3) : LD B,A
    LD A,191 : SUB B : LD C,A
    LD A,(BOSS_BROKEN_PROJ_Y+3)
    CP C
    JP NC,UBBBF_OFFS3
    ADD A,B
    LD (BOSS_BROKEN_PROJ_Y+3),A

    LD A,(BOSS_BROKEN_PROJ_Y+3) : LD B,A
    LD A,(BOSS_BROKEN_PROJ_X+3) : LD C,A
    LD A,(BOSS_BROKEN_PROJ_CODE+3)
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+12
    LD (HL),B : INC HL
    LD (HL),C : INC HL
    LD (HL),A : INC HL
    LD A,BOSS_BROKEN_BEAM_COLOR : LD (HL),A
    RET

UBBBF_OFFS3:
    XOR A
    LD (BOSS_BROKEN_PROJ_ACTIVE+3),A
UBBBF_HIDE3:
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS+12
    LD (HL),209 : INC HL
    XOR A
    LD (HL),A : INC HL
    LD (HL),A : INC HL
    LD (HL),A
    RET

FLUSH_BOSS_BROKEN_BEAM_SPRITES:
    DI
    LD A,BOSS_BROKEN_BEAM_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,BOSS_BROKEN_BEAM_SPRITE_ATTRS
    LD B,BOSS_BROKEN_BEAM_SLOT_COUNT*4
FBBBS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FBBBS_LOOP
    EI
    RET

; AABB-checks each of the up to 4 in-flight beam projectiles' own 16x16
; box against the tank - same 4-compare shape/i-frame gate as CHECK_
; SBEAM_VS_TANK, walking every ACTIVE slot (round36-14 follow-up#4 3rd
; real-hardware feedback: beams are real moving projectiles now, not a
; single static sprite - see UPDATE_BOSS_BROKEN_BEAM_FLIGHT's own
; comment). Stops (RET) on the first hit rather than checking the
; remaining slots, same "one hit per frame is enough" shape as every
; other tank-hazard check in this file - a hit does NOT deactivate that
; beam's own slot, it keeps flying through/past the tank exactly like
; every other projectile in this game that isn't itself destroyed by
; contact.
; round36-14 follow-up#8 ("ではループ展開を検討"): fully loop-unrolled,
; same treatment as UPDATE_BOSS_BROKEN_BEAM_FLIGHT above (see that
; routine's own comment for the general rationale/assembler gotcha).
; The tank's own X+offset/Y+offset stay in B/C for the whole routine
; (unchanged from follow-up#6/#7's own tightening - still true and
; still useful even unrolled, since D is now free to hold a per-slot
; scratch value instead). One extra wrinkle specific to this routine:
; `CP (HL)` (comparing A against an indexed projectile field) has no
; direct-addressing equivalent (`CP (nn)` doesn't exist on real Z80,
; and this assembler's `LD r,(nn)` only supports r=A) - so each of the
; 2 read-modify-compare pairs (X-vs-tank-right, Y-vs-tank-bottom) now
; does `LD A,(PROJ_field+N):LD D,A` first to stash the projectile's own
; value in D, computes the tank-edge value into A as before, then
; `CP D`. Slots fall straight through into the next slot's own label on
; a miss (no shared NEXT/loop-back), and the last slot (3) uses RET
; directly instead of a trailing JP+fallthrough. T-state win (same
; measurement methodology as follow-up#7): 4-active-miss 745T->326T
; (-56%), 0-active 549T->179T(-67%) - a bigger relative win than the
; flight routine, because this routine's checks are almost entirely
; single-field reads/compares (the case direct addressing helps most)
; rather than read-modify-writes. ROM cost: +129 bytes (110->239).
CHECK_BOSS_BROKEN_BEAM_VS_TANK:
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD B,A   ; B = tank X+offset (stable all routine)
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD C,A ; C = tank Y+offset (stable all routine)

CBBBVT_SLOT0:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+0)
    OR A
    JP Z,CBBBVT_SLOT1
    LD A,(BOSS_BROKEN_PROJ_X+0)
    LD D,A
    ADD A,15
    CP B
    JP C,CBBBVT_SLOT1
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CBBBVT_SLOT1
    LD A,(BOSS_BROKEN_PROJ_Y+0)
    LD D,A
    ADD A,15
    CP C
    JP C,CBBBVT_SLOT1
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CBBBVT_SLOT1
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CBBBVT_SLOT1:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+1)
    OR A
    JP Z,CBBBVT_SLOT2
    LD A,(BOSS_BROKEN_PROJ_X+1)
    LD D,A
    ADD A,15
    CP B
    JP C,CBBBVT_SLOT2
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CBBBVT_SLOT2
    LD A,(BOSS_BROKEN_PROJ_Y+1)
    LD D,A
    ADD A,15
    CP C
    JP C,CBBBVT_SLOT2
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CBBBVT_SLOT2
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CBBBVT_SLOT2:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+2)
    OR A
    JP Z,CBBBVT_SLOT3
    LD A,(BOSS_BROKEN_PROJ_X+2)
    LD D,A
    ADD A,15
    CP B
    JP C,CBBBVT_SLOT3
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    JP C,CBBBVT_SLOT3
    LD A,(BOSS_BROKEN_PROJ_Y+2)
    LD D,A
    ADD A,15
    CP C
    JP C,CBBBVT_SLOT3
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    JP C,CBBBVT_SLOT3
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

CBBBVT_SLOT3:
    LD A,(BOSS_BROKEN_PROJ_ACTIVE+3)
    OR A
    RET Z
    LD A,(BOSS_BROKEN_PROJ_X+3)
    LD D,A
    ADD A,15
    CP B
    RET C
    LD A,B : ADD A,TANK_COLLISION_WIDTH-1
    CP D
    RET C
    LD A,(BOSS_BROKEN_PROJ_Y+3)
    LD D,A
    ADD A,15
    CP C
    RET C
    LD A,C : ADD A,TANK_COLLISION_HEIGHT-1
    CP D
    RET C
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

BOSS_EXPL_WHITE_PATTERN:
    DB 0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh,0FFh

; the spark phase's own BG tile art - EXPLOSION_PATTERN itself (see
; BOSS_EXPL_SPARK_CODE_TL's own comment - round32 switched from just its
; top-left 8x8 quadrant to the full 16x16, so no separate table is
; needed here anymore; INIT_BOSS_EXPLOSION uploads EXPLOSION_PATTERN's
; own 32 bytes directly to BOSS_EXPL_SPARK_CODE_TL*8).

; flight LUT (round32 follow-up #3, "1から3セルランダムで") - 8 compass
; directions (N,NE,E,SE,S,SW,W,NW, same order/sign convention as this
; file's own EXPLODE_DIR_DX/DY) x distance 1-3, precomputed rather than
; multiplied at runtime (Z80 has no multiply instruction) - 24 (dx,dy)
; pairs, 2 bytes each. BOSS_EXPL_PICK_FLIGHT picks one entry uniformly at
; random. Must stay in sync with BOSS_EXPL_FLIGHT_MIN_DIST/_MAX_DIST if
; either ever changes.
BOSS_EXPL_FLIGHT_TABLE:
    DB 0,-1,  0,-2,  0,-3     ; N
    DB 1,-1,  2,-2,  3,-3     ; NE
    DB 1,0,   2,0,   3,0      ; E
    DB 1,1,   2,2,   3,3      ; SE
    DB 0,1,   0,2,   0,3      ; S
    DB -1,1,  -2,2,  -3,3     ; SW
    DB -1,0,  -2,0,  -3,0     ; W
    DB -1,-1, -2,-2, -3,-3    ; NW

; "更に円の塗りつぶしは固定処理なのでLutでやってくれ たった半径6セルだ
; からわずかなサイズだろう 一々計算は不要 なので円の1周終了を1パターン
; として記録し 描画はそれらをアニメ処理すればよい" - the circle's own
; shape never changes (only its center does, a plain translation), so
; instead of computing disk membership at runtime (the old dx^2+dy^2<=
; radius^2 half-width-table approach - see git history), each radius's
; own RING (the cells newly added growing from radius-1 to radius; the
; same list is also exactly the cells removed shrinking radius back down
; by 1) is precomputed once, offline, into a fixed table - "1周" (one
; lap/step) = one fixed pattern, and GROW/SHRINK just walk it
; (BOSS_EXPL_APPLY_RING below), same idea as animating through sprite
; frames. Computed via a one-off Python script (disk(r)-disk(r-1) for
; each dx^2+dy^2<=r^2), not by hand - 226 bytes total across all 7
; radii, sorted by dx then dy, each cell as (dx+MAXR,dy+MAXR) so every
; value is a plain 0-12 byte (no sign handling needed to embed the
; table itself - the sign only matters again once it's added back to
; the real center at draw time, in BOSS_EXPL_APPLY_RING).
;
; This also directly fixes "不要な書き込みはしないこと 円描画するセル
; のみで": the old box-redraw approach touched every cell in the whole
; 13x13 bounding box on every step, including ones that were never part
; of the circle at all - which silently clobbered real background
; (SkySand/terrain) sitting in the box's own corners with a blank tile
; that then never got restored (see BOSS_EXPL_BG_CODE_FOR_ROW's own
; comment for the real fix to THAT). Walking only the ring's own cells
; means cells outside the circle are never touched in the first place -
; nothing to restore there because nothing ever disturbed them.
BOSS_EXPL_RING_OFFSETS:
    DB 0,2,10,26,58,98,162
BOSS_EXPL_RING_COUNT:
    DB 1,4,8,16,20,32,32
BOSS_EXPL_RING_DATA:
    DB 6,6,5,6,6,5,6,7,7,6,4,6,5,5,5,7
    DB 6,4,6,8,7,5,7,7,8,6,3,6,4,4,4,5
    DB 4,7,4,8,5,4,5,8,6,3,6,9,7,4,7,8
    DB 8,4,8,5,8,7,8,8,9,6,2,6,3,4,3,5
    DB 3,7,3,8,4,3,4,9,5,3,5,9,6,2,6,10
    DB 7,3,7,9,8,3,8,9,9,4,9,5,9,7,9,8
    DB 10,6,1,6,2,3,2,4,2,5,2,7,2,8,2,9
    DB 3,2,3,3,3,9,3,10,4,2,4,10,5,2,5,10
    DB 6,1,6,11,7,2,7,10,8,2,8,10,9,2,9,3
    DB 9,9,9,10,10,3,10,4,10,5,10,7,10,8,10,9
    DB 11,6,0,6,1,3,1,4,1,5,1,7,1,8,1,9
    DB 2,2,2,10,3,1,3,11,4,1,4,11,5,1,5,11
    DB 6,0,6,12,7,1,7,11,8,1,8,11,9,1,9,11
    DB 10,2,10,10,11,3,11,4,11,5,11,7,11,8,11,9
    DB 12,6

; row->true-background-code, matching ERASE_BULLET_CELL's own day/night-
; aware restore rules exactly (row<16 sky, row==16 SkySand/NIGHT_CODE,
; 17-19 TERRAIN_BLANK_CODE) - a separate copy rather than a shared call
; site, since ERASE_BULLET_CELL is IX-indexed (bullet-slot shaped) and
; this is plain row-in/code-out. "Sandskyとその下のラインは更新しない
; 1度書きなので復元しないとスクショのように欠けてしまう" - real-hardware/
; screenshot finding: the OLD box-redraw's blanket "everything outside
; the circle is HUD_ROW_BLANK_CODE" assumption only held for pure sky
; (rows0-15); SkySand(16) and the Sand band(17-19) are each drawn ONCE
; at INIT and never redrawn per-frame the way sky/night is, so treating
; them the same as sky left a permanent black hole exactly where they'd
; been overwritten - the explosion's own box realistically DOES reach
; that far (BOSS_SPAWN_Y=56 -> center row~11, +BOSS_EXPL_MAXR(6) ->
; row17, squarely inside the Sand band). Row>=20 (the scrolling terrain,
; self-healing every frame already) is out of realistic reach at
; MAXR=6 from a center row around 11-12, but still falls back to
; TERRAIN_BLANK_CODE defensively rather than being left undefined.
BOSS_EXPL_BG_CODE_FOR_ROW:
    CP BULLET_ROCK_ROW_MIN
    JR C,BEBCFR_SKY
    CP BULLET_ROCK_ROW_MIN+4
    JR NC,BEBCFR_TERRAIN_BLANK
    CP BULLET_ROCK_ROW_MIN
    JR Z,BEBCFR_SKYSAND
BEBCFR_TERRAIN_BLANK:
    LD A,TERRAIN_BLANK_CODE
    RET
BEBCFR_SKYSAND:
    LD A,(NIGHT_ROW)
    CP NIGHT_END_ROW
    JR C,BEBCFR_SKYSAND_DAY
    LD A,NIGHT_CODE
    RET
BEBCFR_SKYSAND_DAY:
    LD A,SKYSAND_CODE
    RET
BEBCFR_SKY:
    LD B,A
    LD A,(NIGHT_ROW)
    CP B
    JR C,BEBCFR_SKY_BLUE
    LD A,HUD_ROW_BLANK_CODE
    RET
BEBCFR_SKY_BLUE:
    LD A,SKY_BLANK_CODE
    RET

; walks the ring table for radius A, writing each on-screen cell -
; (BOSS_EXPL_RING_MODE) selects what: 0=BOSS_EXPL_WHITE_CODE (GROW,
; drawing a newly-grown ring), 1=the true per-row background via
; BOSS_EXPL_BG_CODE_FOR_ROW (SHRINK, restoring a ring being removed -
; NOT a blanket blank, see that routine's own comment on why).
;
; "円の描画とラインの描画順の問題でラインが円の範囲で消えてる" - during
; SHRINK specifically, dy=0 cells (the ring's own points on the center
; row) are skipped entirely rather than restored - that row belongs to
; the still-solid full-width line (drawn once at the grow->shrink
; transition) until BOSS_EXPL_ERASE_LINE's own single clean sweep;
; restoring them mid-shrink would eat into the middle of the line early,
; the exact bug reported. GROW draws dy=0 normally (no line exists yet).
BOSS_EXPL_APPLY_RING:
    LD (BOSS_EXPL_RING_RADIUS),A
    LD HL,BOSS_EXPL_RING_COUNT : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL) : LD (BOSS_EXPL_RING_REMAIN),A
    OR A
    RET Z
    LD A,(BOSS_EXPL_RING_RADIUS)
    LD HL,BOSS_EXPL_RING_OFFSETS : LD E,A : LD D,0 : ADD HL,DE
    LD A,(HL)
    LD HL,BOSS_EXPL_RING_DATA : LD E,A : LD D,0 : ADD HL,DE
    LD (BOSS_EXPL_RING_PTR),HL
BEAR_LOOP:
    LD HL,(BOSS_EXPL_RING_PTR)
    LD A,(HL) : SUB BOSS_EXPL_MAXR : LD B,A   ; B = dx (signed, 2's-complement wraparound)
    INC HL
    LD A,(HL) : SUB BOSS_EXPL_MAXR : LD C,A   ; C = dy
    INC HL
    LD (BOSS_EXPL_RING_PTR),HL

    LD A,(BOSS_EXPL_RING_MODE)
    OR A
    JR Z,BEAR_ROW_OK
    LD A,C
    OR A
    JP Z,BEAR_SKIP_CELL   ; SHRINK + dy=0 - the line's own row, leave it alone
BEAR_ROW_OK:

    LD A,(BOSS_EXPL_CY) : ADD A,C : LD (BOSS_EXPL_ROWTMP),A
    LD A,(BOSS_EXPL_CX) : ADD A,B : LD (BOSS_EXPL_COLTMP),A

    ; off-screen row/col - either wrapped negative or genuinely too big;
    ; each single unsigned check catches both directions at once.
    LD A,(BOSS_EXPL_ROWTMP)
    CP 24
    JP NC,BEAR_SKIP_CELL
    LD A,(BOSS_EXPL_COLTMP)
    CP 32
    JP NC,BEAR_SKIP_CELL

    LD A,(BOSS_EXPL_RING_MODE)
    OR A
    JR NZ,BEAR_RESTORE
    LD A,BOSS_EXPL_WHITE_CODE
    JR BEAR_GOT_CODE
BEAR_RESTORE:
    LD A,(BOSS_EXPL_ROWTMP) : CALL BOSS_EXPL_BG_CODE_FOR_ROW
BEAR_GOT_CODE:
    LD (BULLET_TEMP_BYTE),A
    LD A,(BOSS_EXPL_ROWTMP) : CALL NIGHT_ROW_ADDR
    LD H,D : LD L,E
    LD A,(BOSS_EXPL_COLTMP) : LD E,A : LD D,0
    ADD HL,DE
    CALL WRITE_BULLET_BYTE_HL

BEAR_SKIP_CELL:
    LD A,(BOSS_EXPL_RING_REMAIN) : DEC A : LD (BOSS_EXPL_RING_REMAIN),A
    JP NZ,BEAR_LOOP
    RET

; called once, the instant the boss is destroyed (from CHPBOSS_DESTROY,
; right after HIDE_BOSS_SPRITES) - sets up everything the death/
; explosion sequence needs and draws its very first frame (a 1-cell
; circle at the boss's own center).
;
; "まずボスがBG描画される右端で倒された場合はスプライトに戻す" - if the
; kill happened while parked in the attack pose (BOSS_PHASE=1, hand art
; on screen, real sprite already hidden), erase that BG art and reset
; BOSS_PHASE back to 0 first, then explicitly re-show the real sprite
; (DRAW_BOSS/FLUSH_BOSS_SPRITES) right here - round32: SPARK now needs
; the boss VISIBLE the instant it starts ("消さないでくれ BGでやってる
; 意味がない"), not just "not still BG art"; the patrol-death case
; already has a visible sprite from its own last real frame so it needs
; no extra draw, but the pose-death case's own sprite was left hidden by
; whatever put it into the pose to begin with (see BOSS_PHASE=1 entry,
; its own HIDE_BOSS_SPRITES call) and nothing else would ever re-show it.
INIT_BOSS_EXPLOSION:
    LD A,(BOSS_PHASE)
    CP 1
    JR NZ,IBE_NO_HAND
    CALL ERASE_SASAPI_HAND
    XOR A : LD (BOSS_PHASE),A
    CALL DRAW_BOSS
    CALL FLUSH_BOSS_SPRITES
IBE_NO_HAND:
    ; "倒した位置のボス中心から" - capture the center CELL now, once,
    ; while BOSS_X/BOSS_Y still mean something (nothing updates them
    ; again after this - the boss itself is done moving for good).
    ; BOSS_X/BOSS_Y are the sprite's own top-left pixel; center is half
    ; its width/height; pixel->cell is /8. round36-14 ("で、0で最後の
    ; 爆発で" - a death CAN now happen while BOSS_FORM=ACTIVE too): the
    ; broken body is 32x32 (center offset +16), not the original 64x64
    ; (+32) - using the wrong one here would center this whole sequence
    ; 16px off from where the visible broken body actually is.
    LD A,32 : LD B,A
    LD A,(BOSS_FORM)
    CP BOSS_FORM_ACTIVE
    JR NZ,IBE_CENTER_OFS_SET
    LD B,16
IBE_CENTER_OFS_SET:
    LD A,(BOSS_X) : ADD A,B : SRL A : SRL A : SRL A : LD (BOSS_EXPL_CX),A
    LD A,(BOSS_Y) : ADD A,B : SRL A : SRL A : SRL A : LD (BOSS_EXPL_CY),A

    ; one-time repurpose of the (now permanently retired) hand-art code
    ; range - see BOSS_EXPL_WHITE_CODE's own comment for why this is safe.
    ; Both the circle's own white tile and the spark phase's own tile are
    ; prepared here upfront, not deferred to whichever phase needs them
    ; first - one DI/EI-wrapped burst instead of two smaller ones later.
    DI
    LD HL,BOSS_EXPL_WHITE_PATTERN : LD DE,BOSS_EXPL_WHITE_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EXPLOSION_PATTERN : LD DE,BOSS_EXPL_SPARK_CODE_TL*8 : LD BC,32 : CALL LDIRVM
    EI
    LD A,BOSS_EXPL_WHITE_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+BOSS_EXPL_WHITE_GROUP : LD BC,1 : CALL LDIRVM
    LD A,BOSS_EXPL_SPARK_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+BOSS_EXPL_SPARK_GROUP : LD BC,1 : CALL LDIRVM

    ; SPARK runs first (see its own header comment) - GROW's own init
    ; (radius=0, ring(0) drawn) happens later, at the SPARK->GROW
    ; transition (UBS_LAST_FRAME), not here - BOSS_EXPL_RADIUS itself is
    ; reused as SLOT0's own row storage throughout SPARK (see BOSS_EXPL_
    ; SPARK_SLOT0_ROW's own comment), not zeroed here.
    XOR A : LD (BOSS_EXPL_REASON),A   ; round36-14: a real death - see UBS_LAST_FRAME/TRIGGER_BOSS_BROKEN_FORM's own comments
    CALL ARM_BOSS_EXPL_SPARK
    RET

; round36-14: the SPARK sub-state's own arm sequence (state/timer/blink/
; live-spark-slot sentinels) - factored out of INIT_BOSS_EXPLOSION so
; TRIGGER_BOSS_BROKEN_FORM can share it exactly rather than duplicating
; these 3 writes a 2nd time (everything ABOVE this point in INIT_BOSS_
; EXPLOSION - hand-art cleanup, center-cell capture, white/spark tile
; upload - genuinely differs between the two callers, so only this
; common tail is shared).
ARM_BOSS_EXPL_SPARK:
    LD A,BOSS_EXPL_STATE_SPARK : LD (BOSS_EXPL_STATE),A
    LD A,BOSS_EXPL_SPARK_DURATION : LD (BOSS_EXPL_TIMER),A   ; reused as SPARK's own countdown - see its own comment
    XOR A : LD (BOSS_EXPL_BLINK),A   ; reused as SPARK's own decorrelation salt - see BOSS_EXPL_RANDOM_BYTE's own comment
    ; all 3 slots start empty - "nothing live yet" sentinel (0FFh, see
    ; the slot bytes' own comment) so frame 1 doesn't try to erase stale
    ; data from a previous boss fight.
    LD A,0FFh
    LD (BOSS_EXPL_SPARK_SLOT0_ROW),A
    LD (BOSS_EXPL_SPARK_SLOT1_ROW),A
    LD (BOSS_EXPL_SPARK_SLOT2_ROW),A
    RET

; per-frame update for the death/explosion sequence, called from
; UPDATE_BOSS_ALL in place of DRAW_BOSS/FLUSH_BOSS_SPRITES once
; BOSS_ACT=2. 4 states (BOSS_EXPL_STATE_GROW/_SHRINK/_FLASH/_DONE) - see
; each state's own block below for what it does; DONE is a permanent
; no-op (the whole sequence only ever runs once per boss).
UPDATE_BOSS_EXPLOSION:
    LD A,(BOSS_EXPL_STATE)
    CP BOSS_EXPL_STATE_DONE
    RET Z
    CP BOSS_EXPL_STATE_SPARK
    JP Z,UBE_SPARK
    CP BOSS_EXPL_STATE_GROW
    JP Z,UBE_GROW
    CP BOSS_EXPL_STATE_SHRINK
    JP Z,UBE_SHRINK
    JP UBE_FLASH

; draws ONE mixed random byte (pure READ of GAME_RNG, XORed with TICK and
; an incrementing per-call salt - same PICK_HORMING_TARGET_X-style anti-
; correlation idiom used throughout this file). Round-1 fix: the original
; version called this TWICE per spark (once for dx, once for dy), each
; call only advancing the salt by 1 - with GAME_RNG/TICK unchanged within
; the same frame, that made dx and dy literally consecutive integers
; (dy=dx+1 mod 16), so every spark landed on the SAME short diagonal line
; instead of scattering in 2D (caught by boss_explosion_test.py's own
; "genuinely scattered" check, not just a test-only artifact - the exact
; same correlation exists in real gameplay too, just partly masked by
; GAME_RNG/TICK actually changing frame to frame there). Fixed by drawing
; ONE byte per spark and splitting it into independent nibbles for dx/dy
; below - a raster-style sweep (low nibble cycles every draw, high nibble
; only advances on nibble-carry) that covers the whole box far more
; evenly than a single shared linear counter ever could.
BOSS_EXPL_RANDOM_BYTE:
    LD A,(BOSS_EXPL_BLINK) : INC A : LD (BOSS_EXPL_BLINK),A : LD B,A
    LD A,(GAME_RNG) : XOR B : LD B,A
    LD A,(TICK) : XOR B
    RET

; writes (BULLET_TEMP_BYTE) at (BOSS_EXPL_COLTMP+C, BOSS_EXPL_ROWTMP+B)
; - B/C(in) are simple 0/1 cell offsets from that base, used to place
; each of a 16x16 spark's 4 quadrants (or just (0,0) alone for an 8x8
; one). Screen-clipped per cell (silently skips off-screen, same
; unsigned CP trick as BOSS_EXPL_APPLY_RING). Clobbers A/D/E/H/L only -
; B/C are read-only inputs, never written, so a caller can freely reuse
; the same B or C across several calls without reloading it.
BOSS_EXPL_WRITE_SPARK_CELL:
    LD A,(BOSS_EXPL_ROWTMP) : ADD A,B
    CP 24
    RET NC
    PUSH AF
    LD A,(BOSS_EXPL_COLTMP) : ADD A,C
    LD C,A
    CP 32
    JR NC,BEWSC_OOB
    POP AF
    CALL NIGHT_ROW_ADDR
    LD H,D : LD L,E
    LD A,C : LD E,A : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL
BEWSC_OOB:
    POP AF
    RET

; in: A=old row (or 0FFh sentinel = nothing live to erase), C=old col.
; erases that spark's 4-cell footprint, restoring the real per-row
; background (BOSS_EXPL_BG_CODE_FOR_ROW - the SkySand/Sand fix from
; earlier this same round, reused here). ALWAYS 4 cells regardless of
; whether the actual spark there was 8x8 or 16x16 - the "extra" cells
; for an 8x8 spark just restore already-correct background, harmless,
; since every slot's own OLD spark is erased before ANY slot's NEW spark
; is drawn each frame (see UBE_SPARK) - this can never clip a sibling
; slot's still-current spark. Saves needing to persist which size the
; old spark was, so 2 bytes/slot (row,col) is enough.
BOSS_EXPL_ERASE_ONE_SPARK:
    CP 0FFh
    RET Z
    LD (BOSS_EXPL_ROWTMP),A
    LD A,C : LD (BOSS_EXPL_COLTMP),A
    LD B,0 : LD C,0 : CALL BOSS_EXPL_ERASE_SPARK_CELL
    LD B,1 : LD C,0 : CALL BOSS_EXPL_ERASE_SPARK_CELL
    LD B,0 : LD C,1 : CALL BOSS_EXPL_ERASE_SPARK_CELL
    LD B,1 : LD C,1 : CALL BOSS_EXPL_ERASE_SPARK_CELL
    RET

; same shape/inputs as BOSS_EXPL_WRITE_SPARK_CELL (B/C=0/1 offsets from
; BOSS_EXPL_ROWTMP/COLTMP, same screen clip) but computes the real
; per-row background itself instead of writing a fixed code.
BOSS_EXPL_ERASE_SPARK_CELL:
    LD A,(BOSS_EXPL_ROWTMP) : ADD A,B
    CP 24
    RET NC
    PUSH AF
    LD A,(BOSS_EXPL_COLTMP) : ADD A,C
    LD C,A
    CP 32
    JR NC,BEESC_OOB
    POP AF
    PUSH AF
    CALL BOSS_EXPL_BG_CODE_FOR_ROW
    LD (BULLET_TEMP_BYTE),A
    POP AF
    CALL NIGHT_ROW_ADDR
    LD H,D : LD L,E
    LD A,C : LD E,A : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL
BEESC_OOB:
    POP AF
    RET

; picks one of the 24 (dx,dy) entries in BOSS_EXPL_FLIGHT_TABLE uniformly
; at random - "1から3セルランダムで": distance is always exactly 1, 2, or
; 3 cells in a random compass direction, never 0 and never further than
; 3. 24 isn't a power of 2, so a plain AND can't land exactly in range -
; masks to 0-31 (next power of 2 above 24) and folds anything >=24 back
; down by subtracting 24 once (31-24=7<24, one subtraction is always
; enough, same fold-back idiom PICK_HORMING_TARGET_X already established
; for its own non-power-of-2 window). Out: C=dx, B=dy. Trashes A/D/E/H/L.
BOSS_EXPL_PICK_FLIGHT:
    CALL BOSS_EXPL_RANDOM_BYTE
    AND 31
    CP 24
    JR C,BEPF_OK
    SUB 24
BEPF_OK:
    ADD A,A                              ; *2 - 2 bytes/entry
    LD L,A : LD H,0
    LD DE,BOSS_EXPL_FLIGHT_TABLE
    ADD HL,DE
    LD A,(HL) : LD C,A
    INC HL
    LD A,(HL) : LD B,A
    RET

; in: A=this slot's OLD row (or 0FFh sentinel), C=old col. out: A=new
; row, C=new col (caller persists these into the slot's own bytes for
; next frame's erase). Erases the old spark (BOSS_EXPL_ERASE_ONE_SPARK
; above), then spawns a fresh one - "爆発範囲を元の64x64に てかこれは
; エフェクトが飛ぶ範囲ではなく原点だからな そこからランダム方向に1から
; 3セル飛ぶんだぞ": picks a random ORIGIN cell within the boss's own
; 64x64 body (BOSS_EXPL_ORIGIN_RANGE), then flies further in a random
; compass direction by a random 1-3 cell distance (BOSS_EXPL_PICK_
; FLIGHT) - two stacked random draws, not one flat box, so results
; naturally cluster near the boss body and thin out further away. 50/50
; lone 8x8 TL tile vs the full 16x16 (all 4 quadrants) - "爆発キャラは
; ...16x16のほうで ランダムで混ぜてもいいがな" - decided right after its
; own random draw and branched on immediately (no need to preserve the
; choice across the drawing calls that follow, unlike a value that would
; have to survive in a register through them).
BOSS_EXPL_SPARK_SLOT:
    CALL BOSS_EXPL_ERASE_ONE_SPARK

    ; --- origin: random cell within the boss-center 32x32 box ---
    CALL BOSS_EXPL_RANDOM_BYTE
    LD D,A
    AND BOSS_EXPL_ORIGIN_RANGE*2-1 : SUB BOSS_EXPL_ORIGIN_RANGE : LD C,A   ; origin dx
    LD A,D
    SRL A : SRL A
    AND BOSS_EXPL_ORIGIN_RANGE*2-1 : SUB BOSS_EXPL_ORIGIN_RANGE : LD B,A   ; origin dy
    LD A,(BOSS_EXPL_CY) : ADD A,B : LD (BOSS_EXPL_ROWTMP),A
    LD A,(BOSS_EXPL_CX) : ADD A,C : LD (BOSS_EXPL_COLTMP),A

    ; --- flight: fly further, random compass direction, 1-3 cells ---
    CALL BOSS_EXPL_PICK_FLIGHT
    LD A,(BOSS_EXPL_ROWTMP) : ADD A,B : LD (BOSS_EXPL_ROWTMP),A
    LD A,(BOSS_EXPL_COLTMP) : ADD A,C : LD (BOSS_EXPL_COLTMP),A

    ; --- size: 8x8 or 16x16, then draw ---
    CALL BOSS_EXPL_RANDOM_BYTE
    AND 1
    JR Z,BESS_DRAW_8

BESS_DRAW_16:
    LD A,BOSS_EXPL_SPARK_CODE_TL : LD (BULLET_TEMP_BYTE),A
    LD B,0 : LD C,0 : CALL BOSS_EXPL_WRITE_SPARK_CELL
    LD A,BOSS_EXPL_SPARK_CODE_BL : LD (BULLET_TEMP_BYTE),A
    LD B,1 : LD C,0 : CALL BOSS_EXPL_WRITE_SPARK_CELL
    LD A,BOSS_EXPL_SPARK_CODE_TR : LD (BULLET_TEMP_BYTE),A
    LD B,0 : LD C,1 : CALL BOSS_EXPL_WRITE_SPARK_CELL
    LD A,BOSS_EXPL_SPARK_CODE_BR : LD (BULLET_TEMP_BYTE),A
    LD B,1 : LD C,1 : CALL BOSS_EXPL_WRITE_SPARK_CELL
    JR BESS_DRAW_DONE

BESS_DRAW_8:
    LD A,BOSS_EXPL_SPARK_CODE_TL : LD (BULLET_TEMP_BYTE),A
    LD B,0 : LD C,0 : CALL BOSS_EXPL_WRITE_SPARK_CELL

BESS_DRAW_DONE:
    LD A,(BOSS_EXPL_COLTMP) : LD C,A
    LD A,(BOSS_EXPL_ROWTMP)
    RET

; "ウェイトなしで派手に沢山" - every single frame (no per-spark or
; per-batch wait), each of the BOSS_EXPL_SPARK_PER_FRAME(3) slots erases
; its own previous spark and drops a fresh one (BOSS_EXPL_SPARK_SLOT).
; Unrolled 3x (not a DJNZ loop) since each slot's own storage is a
; distinct pair of reused RAM bytes, not an indexable array - see those
; bytes' own comment. The countdown (BOSS_EXPL_TIMER) is checked FIRST:
; once it reaches 0 every slot just erases its own last spark with
; nothing new spawned (UBS_LAST_FRAME), leaving a clean board right
; before GROW's own ring(0) draws.
UBE_SPARK:
    LD A,(BOSS_EXPL_TIMER) : DEC A : LD (BOSS_EXPL_TIMER),A
    JP Z,UBS_LAST_FRAME

    ; "爆発エフェクト中も爆発音追加" - a crackle every SPARK_CRACKLE_
    ; PERIOD frames, not every single frame - see that constant's own
    ; comment for why.
    AND SPARK_CRACKLE_PERIOD-1
    CALL Z,SOUND_SPARK_CRACKLE

    LD A,(BOSS_EXPL_SPARK_SLOT0_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT0_ROW)
    CALL BOSS_EXPL_SPARK_SLOT
    LD (BOSS_EXPL_SPARK_SLOT0_ROW),A
    LD A,C : LD (BOSS_EXPL_SPARK_SLOT0_COL),A

    LD A,(BOSS_EXPL_SPARK_SLOT1_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT1_ROW)
    CALL BOSS_EXPL_SPARK_SLOT
    LD (BOSS_EXPL_SPARK_SLOT1_ROW),A
    LD A,C : LD (BOSS_EXPL_SPARK_SLOT1_COL),A

    LD A,(BOSS_EXPL_SPARK_SLOT2_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT2_ROW)
    CALL BOSS_EXPL_SPARK_SLOT
    LD (BOSS_EXPL_SPARK_SLOT2_ROW),A
    LD A,C : LD (BOSS_EXPL_SPARK_SLOT2_COL),A
    RET

; phase over - erase whatever each slot last drew (no respawn), then
; start the circle sequence exactly as INIT_BOSS_EXPLOSION used to start
; it directly. Slot bytes are read here BEFORE BOSS_EXPL_RADIUS/RING_
; MODE/etc. get reinitialized for their own real GROW-phase meaning just
; below (same bytes - see the slot bytes' own comment).
UBS_LAST_FRAME:
    LD A,(BOSS_EXPL_SPARK_SLOT0_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT0_ROW)
    CALL BOSS_EXPL_ERASE_ONE_SPARK
    LD A,(BOSS_EXPL_SPARK_SLOT1_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT1_ROW)
    CALL BOSS_EXPL_ERASE_ONE_SPARK
    LD A,(BOSS_EXPL_SPARK_SLOT2_COL) : LD C,A
    LD A,(BOSS_EXPL_SPARK_SLOT2_ROW)
    CALL BOSS_EXPL_ERASE_ONE_SPARK

    ; round36-14: REASON=1 (TRIGGER_BOSS_BROKEN_FORM's own transition
    ; burst, not a real death) skips GROW/SHRINK/FLASH entirely - "スパ
    ; ークフェーズのみ" (confirmed with the user) - and reveals the
    ; broken form directly instead once the board above is clean.
    LD A,(BOSS_EXPL_REASON)
    OR A
    JP NZ,REVEAL_BOSS_BROKEN_FORM

    XOR A : LD (BOSS_EXPL_RADIUS),A
    LD A,BOSS_EXPL_STATE_GROW : LD (BOSS_EXPL_STATE),A
    LD A,BOSS_EXPL_STEP_FRAMES : LD (BOSS_EXPL_TIMER),A
    XOR A : LD (BOSS_EXPL_BLINK),A
    XOR A : LD (BOSS_EXPL_RING_MODE),A
    XOR A : CALL BOSS_EXPL_APPLY_RING
    CALL SOUND_BOSS_BOOM   ; "円の爆発はノイズでどーーーーんって長いやつ" - right as the circle itself starts growing
    RET

; "この時当然BGはボスの後ろに隠れてしまうんでボスは点滅表示" - while the
; circle grows, the boss's own last-drawn sprite (BOSS_SPRITE_ATTRS,
; frozen since DRAW_BOSS never runs again post-death) blinks on/off via
; FLUSH_BOSS_SPRITES/HIDE_BOSS_SPRITES - no redraw needed, just toggling
; whether the existing attrs get flushed to hw OAM or not.
UBE_GROW:
    LD A,(BOSS_EXPL_BLINK) : INC A
    CP BOSS_EXPL_BLINK_PERIOD
    JR C,UBE_G_BLINK_NOWRAP
    XOR A
UBE_G_BLINK_NOWRAP:
    LD (BOSS_EXPL_BLINK),A
    CP BOSS_EXPL_BLINK_PERIOD/2
    JR NC,UBE_G_BLINK_HIDE
    CALL FLUSH_BOSS_SPRITES
    JR UBE_G_BLINK_DONE
UBE_G_BLINK_HIDE:
    CALL HIDE_BOSS_SPRITES
UBE_G_BLINK_DONE:

    LD A,(BOSS_EXPL_TIMER) : DEC A : LD (BOSS_EXPL_TIMER),A
    RET NZ
    LD A,BOSS_EXPL_STEP_FRAMES : LD (BOSS_EXPL_TIMER),A

    LD A,(BOSS_EXPL_RADIUS)
    CP BOSS_EXPL_MAXR
    JR NC,UBE_GROW_DONE
    INC A : LD (BOSS_EXPL_RADIUS),A
    XOR A : LD (BOSS_EXPL_RING_MODE),A   ; 0=white (clobbers A - reload the radius after)
    LD A,(BOSS_EXPL_RADIUS)
    CALL BOSS_EXPL_APPLY_RING            ; draw just the newly-grown ring
    RET
; "その後円中心から左右に画面幅のBGラインを引いてボス表示は終了" -
; growth just reached its max radius: draw the full-width line, hide the
; boss sprite for good (no more blinking - the explosion continues
; without it from here on), and switch to shrinking.
UBE_GROW_DONE:
    CALL HIDE_BOSS_SPRITES
    CALL BOSS_EXPL_DRAW_LINE
    LD A,BOSS_EXPL_STATE_SHRINK : LD (BOSS_EXPL_STATE),A
    LD A,BOSS_EXPL_STEP_FRAMES : LD (BOSS_EXPL_TIMER),A
    RET

; "円を小さくして行き1セルになったら画面幅のラインを消す" - same
; per-step redraw as growth, just decrementing instead of incrementing;
; once radius reaches 0 (the single center cell), erase the line and
; move on to the final flash.
UBE_SHRINK:
    LD A,(BOSS_EXPL_TIMER) : DEC A : LD (BOSS_EXPL_TIMER),A
    RET NZ
    LD A,BOSS_EXPL_STEP_FRAMES : LD (BOSS_EXPL_TIMER),A

    LD A,(BOSS_EXPL_RADIUS)
    OR A
    JR Z,UBE_SHRINK_DONE
    ; erase the CURRENT radius's own ring (the outermost shell about to
    ; be removed) BEFORE decrementing - that ring IS the delta between
    ; this radius and the next-smaller one.
    LD A,1 : LD (BOSS_EXPL_RING_MODE),A   ; 1=restore true background
    LD A,(BOSS_EXPL_RADIUS)
    CALL BOSS_EXPL_APPLY_RING
    LD A,(BOSS_EXPL_RADIUS) : DEC A : LD (BOSS_EXPL_RADIUS),A
    OR A
    RET NZ
UBE_SHRINK_DONE:
    ; BOSS_EXPL_ERASE_LINE blanks the WHOLE row uniformly, including the
    ; center cell that's supposed to survive into the flash (radius=0's
    ; own circle draw already put it there, but that happened on a PRIOR
    ; step - the erase here would otherwise silently take it right back
    ; out on this same frame). Restore it explicitly, after the erase.
    CALL BOSS_EXPL_ERASE_LINE
    LD A,BOSS_EXPL_WHITE_CODE : CALL BOSS_EXPL_WRITE_CENTER_CELL
    LD A,BOSS_EXPL_STATE_FLASH : LD (BOSS_EXPL_STATE),A
    LD A,BOSS_EXPL_FINAL_FLASH_FRAMES : LD (BOSS_EXPL_TIMER),A
    XOR A : LD (BOSS_EXPL_BLINK),A
    RET

; "最後の1セルを120フレ点滅させ消滅" - just the center cell, toggling
; white/blank on the same BOSS_EXPL_BLINK_PERIOD cadence as the boss's
; own grow-phase blink, for BOSS_EXPL_FINAL_FLASH_FRAMES frames total,
; then erased for good and the whole sequence marked done.
UBE_FLASH:
    LD A,(BOSS_EXPL_BLINK) : INC A
    CP BOSS_EXPL_BLINK_PERIOD
    JR C,UBE_F_BLINK_NOWRAP
    XOR A
UBE_F_BLINK_NOWRAP:
    LD (BOSS_EXPL_BLINK),A
    LD B,BOSS_EXPL_WHITE_CODE
    CP BOSS_EXPL_BLINK_PERIOD/2
    JR C,UBE_F_HAVE_CODE
    LD B,HUD_ROW_BLANK_CODE
UBE_F_HAVE_CODE:
    LD A,B
    CALL BOSS_EXPL_WRITE_CENTER_CELL

    LD A,(BOSS_EXPL_TIMER) : DEC A : LD (BOSS_EXPL_TIMER),A
    RET NZ
    LD A,HUD_ROW_BLANK_CODE : CALL BOSS_EXPL_WRITE_CENTER_CELL
    LD A,BOSS_EXPL_STATE_DONE : LD (BOSS_EXPL_STATE),A
    RET

; writes A (a name-table code) to the single cell at (BOSS_EXPL_CX,
; BOSS_EXPL_CY) - the final flash's own single-cell toggle, and also
; BOSS_EXPL_DRAW_CIRCLE's own radius=0 case draws just this one cell
; (so no special-casing needed there either).
BOSS_EXPL_WRITE_CENTER_CELL:
    LD (BULLET_TEMP_BYTE),A
    LD A,(BOSS_EXPL_CY) : CALL NIGHT_ROW_ADDR
    LD H,D : LD L,E
    LD A,(BOSS_EXPL_CX) : LD E,A : LD D,0
    ADD HL,DE
    JP WRITE_BULLET_BYTE_HL

; fills the WHOLE row (all 32 columns, not just the ±MAXR box) at
; BOSS_EXPL_CY with A (a name-table code) - BOSS_EXPL_DRAW_LINE/
; _ERASE_LINE below just set A and fall through here; "画面幅の" already
; means every column, so unlike BOSS_EXPL_DRAW_CIRCLE this needs no
; per-column clipping (0-31 is the whole valid range already). A is
; stashed straight into BULLET_TEMP_BYTE (not a dedicated scratch byte -
; see the BOSS_EXPL_* RAM block's own comment on staying lean) - nothing
; else touches it for the rest of this loop, only reads it.
BOSS_EXPL_FILL_LINE:
    LD (BULLET_TEMP_BYTE),A
    LD A,(BOSS_EXPL_CY) : CALL NIGHT_ROW_ADDR
    LD H,D : LD L,E
    LD B,32
BEFL_LOOP:
    PUSH HL
    PUSH BC
    CALL WRITE_BULLET_BYTE_HL
    POP BC
    POP HL
    INC HL
    DJNZ BEFL_LOOP
    RET

BOSS_EXPL_DRAW_LINE:
    LD A,BOSS_EXPL_WHITE_CODE
    JP BOSS_EXPL_FILL_LINE
; row-aware restore (BOSS_EXPL_BG_CODE_FOR_ROW), not a hardcoded blank -
; CY is realistically always pure sky in practice, but this stays
; correct even if a future change ever moves the boss's own row.
BOSS_EXPL_ERASE_LINE:
    LD A,(BOSS_EXPL_CY) : CALL BOSS_EXPL_BG_CODE_FOR_ROW
    JP BOSS_EXPL_FILL_LINE

; the 8x8 grid of hand-art name-table codes (SASAPI_HAND_CODE_BASE..
; +63, sequential, row-major) - reused unmodified as DRAW_SASAPI_HAND's
; own LDIRVM source every time the attack pose is entered.
SASAPI_HAND_NAME_CODES:
    DB SASAPI_HAND_CODE_BASE+0,SASAPI_HAND_CODE_BASE+1,SASAPI_HAND_CODE_BASE+2,SASAPI_HAND_CODE_BASE+3,SASAPI_HAND_CODE_BASE+4,SASAPI_HAND_CODE_BASE+5,SASAPI_HAND_CODE_BASE+6,SASAPI_HAND_CODE_BASE+7
    DB SASAPI_HAND_CODE_BASE+8,SASAPI_HAND_CODE_BASE+9,SASAPI_HAND_CODE_BASE+10,SASAPI_HAND_CODE_BASE+11,SASAPI_HAND_CODE_BASE+12,SASAPI_HAND_CODE_BASE+13,SASAPI_HAND_CODE_BASE+14,SASAPI_HAND_CODE_BASE+15
    DB SASAPI_HAND_CODE_BASE+16,SASAPI_HAND_CODE_BASE+17,SASAPI_HAND_CODE_BASE+18,SASAPI_HAND_CODE_BASE+19,SASAPI_HAND_CODE_BASE+20,SASAPI_HAND_CODE_BASE+21,SASAPI_HAND_CODE_BASE+22,SASAPI_HAND_CODE_BASE+23
    DB SASAPI_HAND_CODE_BASE+24,SASAPI_HAND_CODE_BASE+25,SASAPI_HAND_CODE_BASE+26,SASAPI_HAND_CODE_BASE+27,SASAPI_HAND_CODE_BASE+28,SASAPI_HAND_CODE_BASE+29,SASAPI_HAND_CODE_BASE+30,SASAPI_HAND_CODE_BASE+31
    DB SASAPI_HAND_CODE_BASE+32,SASAPI_HAND_CODE_BASE+33,SASAPI_HAND_CODE_BASE+34,SASAPI_HAND_CODE_BASE+35,SASAPI_HAND_CODE_BASE+36,SASAPI_HAND_CODE_BASE+37,SASAPI_HAND_CODE_BASE+38,SASAPI_HAND_CODE_BASE+39
    DB SASAPI_HAND_CODE_BASE+40,SASAPI_HAND_CODE_BASE+41,SASAPI_HAND_CODE_BASE+42,SASAPI_HAND_CODE_BASE+43,SASAPI_HAND_CODE_BASE+44,SASAPI_HAND_CODE_BASE+45,SASAPI_HAND_CODE_BASE+46,SASAPI_HAND_CODE_BASE+47
    DB SASAPI_HAND_CODE_BASE+48,SASAPI_HAND_CODE_BASE+49,SASAPI_HAND_CODE_BASE+50,SASAPI_HAND_CODE_BASE+51,SASAPI_HAND_CODE_BASE+52,SASAPI_HAND_CODE_BASE+53,SASAPI_HAND_CODE_BASE+54,SASAPI_HAND_CODE_BASE+55
    DB SASAPI_HAND_CODE_BASE+56,SASAPI_HAND_CODE_BASE+57,SASAPI_HAND_CODE_BASE+58,SASAPI_HAND_CODE_BASE+59,SASAPI_HAND_CODE_BASE+60,SASAPI_HAND_CODE_BASE+61,SASAPI_HAND_CODE_BASE+62,SASAPI_HAND_CODE_BASE+63

; 8 bytes all HUD_ROW_BLANK_CODE (plain solid black) - reused as
; ERASE_SASAPI_HAND's own LDIRVM source for every one of the 8 rows.
; "BG復帰処理でSandskyが書き込まれてるな ブランクのブラック" - this
; used to write NIGHT_CODE here, which is WRONG: NIGHT_CODE is the
; striped LEADING-ROW tile CHECK_NIGHT's own sweep uses only for the
; single row currently being darkened (see its own CN_SET_ROW comment),
; not a general "already dark" restore value - real hardware showed the
; striped tile instead of solid black once the pose ended, exactly this
; bug. By BOSS_SPAWN_TICK the whole sky band (rows0-16, covers rows7-14
; the hand occupies) is always already fully night-swept (see NIGHT_
; START_TICK's own comment for why), so HUD_ROW_BLANK_CODE - the SAME
; solid-black code EBC_SKY's own already-dark branch uses elsewhere in
; this file - is the actually-correct restore value here.
NIGHT_ROW_BLANK8:
    DB HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE,HUD_ROW_BLANK_CODE

; 8 bytes all SASAPI_HAND_COLORBYTE - INIT's own LDIRVM source, colors
; groups19-26 (the hand's own 8 pattern-code groups) in one shot.
SASAPI_HAND_COLOR8:
    DB SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE,SASAPI_HAND_COLORBYTE

; same 8 bytes, but SASAPI_HAND_FLASH_COLORBYTE - DRAW_SASAPI_HAND's
; own LDIRVM source while the hit-flash is active.
SASAPI_HAND_FLASH_COLOR8:
    DB SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE,SASAPI_HAND_FLASH_COLORBYTE

; draws the attack-pose hand art straight into the name table at the
; boss's own parked position - BOSS_SPAWNX/BOSS_SPAWN_Y are both
; compile-time constants (192,56), so every name-table address here is
; a fixed literal (col24-31 x row7-14 - the last 8 columns of the
; screen, exactly the boss's own 64px width at its right-edge parked X)
; rather than anything computed at runtime. DI/EI-wrapped as a whole,
; not per-row chunked like FLUSH_BOSS_SPRITES needs - the whole pose is
; a rare, short window (BOSS_POSE_TICKS), not the kind of every-frame-
; for-the-whole-game write FLUSH_BOSS_SPRITES had to chunk.
; Called every frame while UBA_POSE is waiting, not just once at
; pose-entry: "でお前が指摘してたボスBG表示欠け発生 消えないようにす
; るか 復帰処理で対応" - a BG-drawn bullet (F always, or U while
; BOSS_ACT!=0 - see DRAW_BULLET_CELL's own boss-only entry) whose cell
; overlaps col24-31/row7-14 while the hand is on screen locally
; overwrites part of it; redrawing every frame heals that back to the
; correct tile within 1 frame instead of leaving a lasting gap, same
; "restore the known-correct value every frame" idiom this file already
; uses for terrain/night.
; Also resolves+applies the hit-flash color (see SASAPI_HAND_FLASH_
; COLORBYTE's own comment) once per call, same BOSS_FLASH_TIMER this
; file's own body-flash (DRAW_BOSS) already uses - safe to share since
; only one of DRAW_BOSS/DRAW_SASAPI_HAND ever runs in a given frame
; (gated by BOSS_PHASE), so whichever draw path is active that frame is
; the one that consumes the timer.
DRAW_SASAPI_HAND:
    DI
    LD HL,SASAPI_HAND_NAME_CODES+0  : LD DE,18F8h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+8  : LD DE,1918h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+16 : LD DE,1938h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+24 : LD DE,1958h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+32 : LD DE,1978h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+40 : LD DE,1998h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+48 : LD DE,19B8h : LD BC,8 : CALL LDIRVM
    LD HL,SASAPI_HAND_NAME_CODES+56 : LD DE,19D8h : LD BC,8 : CALL LDIRVM
    EI

    LD A,(BOSS_FLASH_TIMER)
    OR A
    JR Z,DSH_COLOR_NORMAL
    DEC A : LD (BOSS_FLASH_TIMER),A
    LD HL,SASAPI_HAND_FLASH_COLOR8
    JR DSH_COLOR_SET
DSH_COLOR_NORMAL:
    LD HL,SASAPI_HAND_COLOR8
DSH_COLOR_SET:
    DI
    LD DE,2000h+19 : LD BC,8 : CALL LDIRVM
    EI
    RET

; restores the same 8x8 cell block back to plain night-black - "BGは
; 消してスプライトに戻す". Same fixed addresses as DRAW_SASAPI_HAND.
ERASE_SASAPI_HAND:
    DI
    LD HL,NIGHT_ROW_BLANK8 : LD DE,18F8h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,1918h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,1938h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,1958h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,1978h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,1998h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,19B8h : LD BC,8 : CALL LDIRVM
    LD HL,NIGHT_ROW_BLANK8 : LD DE,19D8h : LD BC,8 : CALL LDIRVM
    EI
    RET

; ---------- Thunder (BG-drawn lightning column, a real pool now - see
; THUNDER_SLOT_SIZE's own comment) ----------
; the 4 Thunder codes, TL/TR/BL/BR - row-major, matching thunder_gen.py's
; own tiles_row_major output order (top row first: TL,TR then BL,BR).
THUNDER_NAME_CODES:
    DB THUNDER_CODE_BASE+0,THUNDER_CODE_BASE+1,THUNDER_CODE_BASE+2,THUNDER_CODE_BASE+3

; zeroes every slot's own ACT byte - called at boss spawn.
RESET_THUNDER_POOL:
    LD B,THUNDER_SLOT_COUNT
    LD IX,THUNDER_POOL
RTP_LOOP:
    XOR A : LD (IX+0),A
    INC IX : INC IX : INC IX : INC IX
    DJNZ RTP_LOOP
    RET

; A = starting BG column (0-31, already resolved by the caller from the
; boss's own current right/left edge). Finds the first inactive slot
; and arms a fresh grow cycle there - "いつからサンダーは1本しか出せな
; い仕様に? そんな指示はしてねえぞ...BGを使ってるのは表示制限がない
; からだろが" (round9: a real pool, THUNDER_SLOT_COUNT concurrent
; columns, not an invented 1-at-a-time cap) - same "pool full -> drop
; the attempt" idiom as FIRE_ONE_HORMING.
ALLOC_THUNDER_SLOT:
    LD C,A                      ; C = col, preserved across the scan
    LD B,THUNDER_SLOT_COUNT
    LD IX,THUNDER_POOL
ATS_LOOP:
    LD A,(IX+0)
    OR A
    JR Z,ATS_SPAWN
    INC IX : INC IX : INC IX : INC IX
    DJNZ ATS_LOOP
    RET                          ; pool full - drop the attempt
ATS_SPAWN:
    LD A,1 : LD (IX+0),A
    LD A,C : LD (IX+1),A
    LD A,THUNDER_TOP_ROW : LD (IX+2),A
    RET

; A = column (0-31). Returns A = the terrain surface ROW (20-23) at
; that column - same IDCACHE_T0..T3 top-to-bottom walk UPDATE_TERRAIN_
; COLLISION/UOZ_TERRAIN_FOLLOW already use for the tank/Zum, just
; indexed directly by a BG column (already in column units) instead of
; a pixel X needing its own /8 first. Re-probed fresh every step (not
; cached at fire-time) since the terrain scrolls underneath a fixed
; screen column while a Thunder instance is alive.
GET_TERRAIN_ROW_FOR_COL:
    LD E,A : LD D,0
    LD HL,IDCACHE_T0 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,GTRC_T0
    LD HL,IDCACHE_T1 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,GTRC_T1
    LD HL,IDCACHE_T2 : ADD HL,DE : LD A,(HL)
    OR A
    JR NZ,GTRC_T2
    LD A,23
    RET
GTRC_T0:
    LD A,20
    RET
GTRC_T1:
    LD A,21
    RET
GTRC_T2:
    LD A,22
    RET

; A=row,B=col. Writes the correct tile pair (ODD row=TL/TR - a block-
; top row, EVEN row=BL/BR - a block-bottom row; THUNDER_TOP_ROW(1) is
; itself odd so this parity holds for every row the bolt ever visits)
; at (row,col)/(row,col+1) in one 2-byte LDIRVM. NIGHT_ROW_ADDR trashes
; A, so the row is stashed via PUSH/POP AF across that call rather than
; reloaded from anywhere (this routine only ever receives it via A).
DRAW_ONE_THUNDER_ROW:
    PUSH AF
    CALL NIGHT_ROW_ADDR              ; DE = this row's own base address
    LD A,B : LD L,A : LD H,0
    ADD HL,DE
    LD D,H : LD E,L
    POP AF
    AND 1
    JR Z,DOTR_BLBR
    DI
    LD HL,THUNDER_NAME_CODES+0 : LD BC,2 : CALL LDIRVM
    EI
    RET
DOTR_BLBR:
    DI
    LD HL,THUNDER_NAME_CODES+2 : LD BC,2 : CALL LDIRVM
    EI
    RET

; A=row,B=col. Writes 1 THUNDERS_CODE cell at (row,col) - "地形に到達
; したら添付のキャラを地上の上に左右に発射...サンダーが着地したら左右
; 同時に2セル描いて消せばおｋ 地形に沿うのは無しで" (round9: a static
; BG cell, not a moving hw sprite).
WRITE_THUNDERS_CELL:
    CALL NIGHT_ROW_ADDR
    LD A,B : LD L,A : LD H,0
    ADD HL,DE
    LD D,H : LD E,L
    LD A,THUNDERS_CODE : LD (HUD_TEMP_BYTE),A
    DI
    LD HL,HUD_TEMP_BYTE : LD BC,1 : CALL LDIRVM
    EI
    RET

; A=row,B=col. Restores 1 cell via ERASE_BULLET_CELL - a no-op for
; row>=20 (real ground/rock terrain - TERRAIN_RENDER_ROW's own
; UNCONDITIONAL full-row redraw, called every MAINLOOP frame before the
; boss/Thunder update, naturally reclaims it within 1 frame once
; nothing keeps re-asserting it there - see UOT_REASSERT_GROW/_SHRINK's
; own comment; no separate restore path is needed for that band at
; all). PUSH/POP IX around the ERASE_BULLET_CELL call since that
; routine needs IX pointed at THUNDER_ERASE_BASE for its own field
; reads, but the CALLER's own IX (a Thunder slot pointer) must survive
; this call intact.
ERASE_ONE_THUNDER_CELL:
    CP 20
    RET NC
    LD (THUNDER_ERASE_BASE+3),A
    CALL NIGHT_ROW_ADDR
    LD A,E : LD (THUNDER_ERASE_BASE+4),A
    LD A,D : LD (THUNDER_ERASE_BASE+5),A
    LD A,B : LD (THUNDER_ERASE_BASE+2),A
    PUSH IX
    LD IX,THUNDER_ERASE_BASE
    CALL ERASE_BULLET_CELL
    POP IX
    RET

; A=row,B=col. Restores both cells (col,col+1).
ERASE_ONE_THUNDER_ROW:
    PUSH AF
    PUSH BC
    CALL ERASE_ONE_THUNDER_CELL
    POP BC
    POP AF
    INC B
    CALL ERASE_ONE_THUNDER_CELL
    RET

; A=row candidate,B=col. Draws only if THUNDER_VIS_LOW<=row<=THUNDER_
; VIS_HIGH (reloaded fresh from scratch each call, not passed via
; registers - DRAW_ONE_THUNDER_ROW's own NIGHT_ROW_ADDR call trashes
; DE, so a register-passed bound wouldn't survive across the 4 calls
; UOT_REASSERT_4 makes).
UOT_MAYBE_DRAW:
    LD C,A
    LD A,(THUNDER_VIS_LOW) : LD D,A
    LD A,C
    CP D
    RET C                          ; row<low
    LD A,(THUNDER_VIS_HIGH) : LD E,A
    LD A,E
    CP C
    RET C                          ; high<row
    LD A,C
    CALL DRAW_ONE_THUNDER_ROW
    RET

; IX=slot, THUNDER_VIS_LOW/_HIGH already set. Redraws whichever of
; rows20-23 fall within [LOW,HIGH] - only 4 possible rows, so just
; unrolled rather than a real loop.
UOT_REASSERT_4:
    LD B,(IX+1) : LD A,20 : CALL UOT_MAYBE_DRAW
    LD B,(IX+1) : LD A,21 : CALL UOT_MAYBE_DRAW
    LD B,(IX+1) : LD A,22 : CALL UOT_MAYBE_DRAW
    LD B,(IX+1) : LD A,23 : CALL UOT_MAYBE_DRAW
    RET

; IX=slot. GROW's own visible range is always [20,ROW-1] (low fixed at
; 20 - growth only ever extends downward during this phase, never
; retracts mid-grow).
UOT_REASSERT_GROW:
    LD A,(IX+2) : DEC A
    CP 20
    RET C
    LD (THUNDER_VIS_HIGH),A
    LD A,20 : LD (THUNDER_VIS_LOW),A
    JP UOT_REASSERT_4

; IX=slot. SHRINK's own visible range is [ROW,DEEP_ROW] (both move as
; erasing marches down from the top).
UOT_REASSERT_SHRINK:
    LD A,(IX+3)
    CP 20
    RET C
    LD (THUNDER_VIS_HIGH),A
    LD A,(IX+2) : LD (THUNDER_VIS_LOW),A
    JP UOT_REASSERT_4

; IX=slot. Draws all 4 ThunderS cells diagonally below the bolt's own
; deepest row - "サンダーSを左右斜め下に...斜め下1セル横に1セル...
; 2セルな" (round11): 00 11 00 / 22 00 22 shape - left pair at
; (COL-2,COL-1), right pair at (COL+2,COL+3), all at row DEEP_ROW+1 (1
; row below the bolt's own last row - the "斜め下" step). Skips a side
; that would fall outside the 0-31 column range (defensive).
; NOTE: the ThunderS row (DEEP_ROW+1) is deliberately RE-READ fresh from
; (IX+3) before every single WRITE_THUNDERS_CELL/ERASE_ONE_THUNDER_CELL
; call below, rather than cached once in a register - both of those
; routines call NIGHT_ROW_ADDR internally, which returns its own result
; in DE, clobbering any row value a caller had stashed in D across
; multiple calls (a real bug caught by inspection: the 2nd/3rd/4th cell
; in a 4-cell run silently used a corrupted row otherwise).
UOT_DRAW_SIDES:
    LD A,(IX+1)
    CP 2
    JR C,UDS_SKIP_LEFT
    SUB 2 : LD B,A                   ; B = COL-2
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
    LD A,(IX+1) : DEC A : LD B,A     ; B = COL-1
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
UDS_SKIP_LEFT:
    LD A,(IX+1)
    CP 29
    JR NC,UDS_SKIP_RIGHT
    ADD A,2 : LD B,A                  ; B = COL+2
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
    LD A,(IX+1) : ADD A,3 : LD B,A     ; B = COL+3
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
UDS_SKIP_RIGHT:
    RET

; IX=slot. Erases just the 2 INNER ThunderS cells (COL-1,COL+2) - round
; 11's own 2-step erase order: "２２００２２から２００００２" (inner
; first, outer stays a beat longer).
UOT_ERASE_SIDES_INNER:
    LD A,(IX+1)
    OR A
    JR Z,UESI_SKIP_LEFT
    DEC A : LD B,A
    LD A,(IX+3) : INC A
    CALL ERASE_ONE_THUNDER_CELL
UESI_SKIP_LEFT:
    LD A,(IX+1)
    CP 30
    JR NC,UESI_SKIP_RIGHT
    ADD A,2 : LD B,A
    LD A,(IX+3) : INC A
    CALL ERASE_ONE_THUNDER_CELL
UESI_SKIP_RIGHT:
    RET

; IX=slot. Erases the 2 OUTER ThunderS cells (COL-2,COL+3) - the 2nd
; and final step of the side-cell erase sequence.
UOT_ERASE_SIDES_OUTER:
    LD A,(IX+1)
    CP 2
    JR C,UESO_SKIP_LEFT
    SUB 2 : LD B,A
    LD A,(IX+3) : INC A
    CALL ERASE_ONE_THUNDER_CELL
UESO_SKIP_LEFT:
    LD A,(IX+1)
    CP 29
    JR NC,UESO_SKIP_RIGHT
    ADD A,3 : LD B,A
    LD A,(IX+3) : INC A
    CALL ERASE_ONE_THUNDER_CELL
UESO_SKIP_RIGHT:
    RET

; IX=slot. Redraws just the 2 OUTER ThunderS cells - used by the
; contested-row (>=20) reassertion pass once the inner cells have
; already been erased but the outer ones haven't yet (the 1-frame gap
; between the 2 erase sub-steps).
UOT_REASSERT_SIDES_OUTER:
    LD A,(IX+1)
    CP 2
    JR C,URSO_SKIP_LEFT
    SUB 2 : LD B,A
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
URSO_SKIP_LEFT:
    LD A,(IX+1)
    CP 29
    JR NC,URSO_SKIP_RIGHT
    ADD A,3 : LD B,A
    LD A,(IX+3) : INC A
    CALL WRITE_THUNDERS_CELL
URSO_SKIP_RIGHT:
    RET

; IX=slot. Re-asserts whichever ThunderS cells should currently still
; be visible, if their own row (DEEP_ROW+1) falls in the contested band
; (>=20) - same "restore every frame" idiom as the main bolt's own
; reassertion. Only relevant while ACT=2 (sides only ever exist during
; shrink, drawn at the very moment growth transitions into it).
UOT_REASSERT_SIDES:
    LD A,(IX+0)
    CP 2
    RET NZ
    LD A,(IX+3) : INC A
    CP 20
    RET C
    LD A,(IX+2) : LD D,A          ; D = ROW (shrink frontier, current)
    LD A,(IX+3) : LD E,A          ; E = DEEP_ROW
    LD A,D : CP E
    JR C,URS_ALL                   ; ROW<=DEEP_ROW - sides untouched yet, all 4 still visible
    JR Z,URS_ALL
    LD A,D : SUB E                  ; A = ROW-DEEP_ROW (1 or 2 at this point)
    CP 2
    JR Z,URS_OUTER_ONLY
URS_ALL:
    CALL UOT_DRAW_SIDES              ; idempotent - redrawing an already-correct cell is harmless
    RET
URS_OUTER_ONLY:
    CALL UOT_REASSERT_SIDES_OUTER
    RET

; IX = slot base (+0 ACT,+1 COL,+2 ROW,+3 DEEP_ROW). Advances this
; slot's own grow/shrink cycle by exactly 1 row (表示ウェイト不要 - no
; pacing), then re-asserts whatever of its own visible range currently
; falls in the ground/rock band (row>=20) - "終了位置は地形までに変更"
; means the bolt can now reach real ground rows, which TERRAIN_RENDER_
; ROW's own UNCONDITIONAL full-row redraw (see MAINLOOP, runs every
; single frame before this routine) would otherwise silently overwrite
; within 1 frame; re-asserting every frame here (racing that redraw,
; same "restore the known-correct value every frame" idiom as DRAW_
; SASAPI_HAND's own per-frame healing) keeps it visible for as long as
; it's still supposed to be, and simply STOPPING re-assertion (rather
; than any explicit erase) is enough to hand the cell back to the
; terrain's own redraw once it's not wanted any more - no separate
; restore path needed for that band at all.
UPDATE_ONE_THUNDER:
    LD A,(IX+0)
    OR A
    RET Z
    CP 1
    JR Z,UOT_DISPATCH_GROW
    CALL UOT_SHRINK
    JR UOT_DISPATCH_SIDES
UOT_DISPATCH_GROW:
    CALL UOT_GROW
UOT_DISPATCH_SIDES:
    CALL UOT_REASSERT_SIDES
    RET

; "サンダーの到達を1セル手前に" (round11) - stops 1 row short of where
; it used to (terrain_row-1 instead of terrain_row), so DEEP_ROW ends up
; terrain_row-2.
UOT_GROW:
    LD A,(IX+1) : CALL GET_TERRAIN_ROW_FOR_COL
    DEC A                         ; terrain_row-1 - the new, 1-cell-earlier stop line
    LD B,A
    LD A,(IX+2)                  ; A = current ROW
    CP B
    JR C,UOT_GROW_STEP           ; ROW < stop line - safe to draw here
    ; reached the (now 1-cell-earlier) stop line - stop growing, drop
    ; the 4 ThunderS cells beside the bolt, and start shrinking.
    DEC A : LD (IX+3),A          ; DEEP_ROW = last row actually drawn (ROW-1)
    ; re-draw DEEP_ROW's own main-bolt row too (not just the new side
    ; cells): it was drawn on a PREVIOUS frame, so if it's in the
    ; contested band (>=20) this exact frame's own terrain redraw
    ; (which already ran earlier in MAINLOOP, before UPDATE_THUNDER)
    ; could have just clobbered it, and UOT_REASSERT_GROW/_SHRINK don't
    ; cover this one specific transition frame (growth's own reassert
    ; already happened for the PREVIOUS row before this call; shrink's
    ; own reassert doesn't start until next frame) - caught by a real
    ; test simulating that exact per-frame clobber.
    LD B,(IX+1)
    CALL DRAW_ONE_THUNDER_ROW
    CALL UOT_DRAW_SIDES
    LD A,THUNDER_TOP_ROW : LD (IX+2),A
    LD A,2 : LD (IX+0),A
    RET
UOT_GROW_STEP:
    LD B,(IX+1)                  ; B = col
    CALL DRAW_ONE_THUNDER_ROW
    LD A,(IX+2) : INC A : LD (IX+2),A
    CALL UOT_REASSERT_GROW
    RET

; shrink now runs 2 extra "virtual" steps past DEEP_ROW for the 2-stage
; ThunderS erase (round11: "サンダーSを消す時も順に...という具合で") -
; ROW==DEEP_ROW+1 erases the INNER side cells, ROW==DEEP_ROW+2 erases
; the OUTER ones and finishes.
UOT_SHRINK:
    LD A,(IX+3) : LD D,A          ; D = DEEP_ROW
    LD A,(IX+2) : LD E,A          ; E = ROW
    CP D
    JR Z,UOT_SHRINK_MAIN
    JR C,UOT_SHRINK_MAIN
    LD A,E : SUB D                  ; A = ROW-DEEP_ROW (1 or 2 - anything else is unreachable)
    CP 1
    JR Z,UOT_SHRINK_INNER
    CALL UOT_ERASE_SIDES_OUTER
    XOR A : LD (IX+0),A
    RET
UOT_SHRINK_INNER:
    CALL UOT_ERASE_SIDES_INNER
    LD A,(IX+2) : INC A : LD (IX+2),A
    RET
UOT_SHRINK_MAIN:
    LD B,(IX+1)                   ; B = COL
    LD A,E                          ; A = ROW
    CALL ERASE_ONE_THUNDER_ROW
    LD A,(IX+2) : INC A : LD (IX+2),A
    CALL UOT_REASSERT_SHRINK
    RET

; called every MAINLOOP frame - advances every active Thunder slot by
; exactly 1 row, independently of the boss/trigger state that armed
; them (same "keeps going even after the trigger that started it" idea
; as the homing missile's own flight).
UPDATE_THUNDER:
    LD B,THUNDER_SLOT_COUNT
    LD IX,THUNDER_POOL
UT_LOOP:
    PUSH BC
    CALL UPDATE_ONE_THUNDER
    POP BC
    INC IX : INC IX : INC IX : INC IX
    DJNZ UT_LOOP
    RET

; "サンダーやサンダービームも自機が当たるとダメージ食らうように 判定
; は先端部だけでいいだろう" - only the bolt's own current LEADING edge
; is a hazard, not its whole trailing length: while growing (ACT=1) that's
; ROW-1 (the deepest row actually drawn so far - ROW itself is always one
; PAST the last draw, see UOT_GROW_STEP's own comment); while shrinking
; (ACT=2) it's DEEP_ROW, which stays fixed and still fully drawn for
; nearly the whole shrink (UOT_SHRINK erases from the TOP down, so the
; bolt's own deepest cell is the LAST thing to go). Same AABB shape as
; UOH_COLLIDE (tank's own real 32x32 box), 16px wide for the tip (the
; bolt is drawn 2 name-table columns wide - see DRAW_ONE_THUNDER_ROW).
; "サンダーやサンダービームで連続ダメージを受けてしまうんで自機に当た
; ったら30フレ当たり判定を停止" (round-2 fix) - `TANK_FLASH_TIMER` alone
; (`FLASH_DURATION`=6 frames) was too short a gate: standing in a bolt/
; beam for consecutive frames still drained `TANK_LIFE` roughly every 6
; frames, unlike every other damage source in this file (BigZum's own
; punch has a real per-instance cooldown; Homing simply consumes itself
; on hit). `TANK_HAZARD_IFRAMES` is a real, dedicated 30-frame
; invulnerability window for exactly these two hazards - set alongside
; (not instead of) `TANK_FLASH_TIMER`, which still only controls the
; visual flash's own short duration.
CHECK_THUNDER_VS_TANK:
    LD IX,THUNDER_POOL
    LD B,THUNDER_SLOT_COUNT
CTVT_LOOP:
    PUSH BC
    CALL CHECK_ONE_THUNDER_VS_TANK
    POP BC
    INC IX : INC IX : INC IX : INC IX
    DJNZ CTVT_LOOP
    RET

CHECK_ONE_THUNDER_VS_TANK:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(IX+0)
    CP 1
    JR Z,CTVT_GROWING
    LD A,(IX+3) : LD C,A          ; C = DEEP_ROW (shrinking - tip stays put)
    JR CTVT_HAVE_ROW
CTVT_GROWING:
    LD A,(IX+2) : DEC A : LD C,A  ; C = ROW-1 (deepest row drawn so far)
CTVT_HAVE_ROW:
    LD A,C : ADD A,A : ADD A,A : ADD A,A : LD C,A   ; C = tip pixel Y
    LD A,(IX+1) : ADD A,A : ADD A,A : ADD A,A : LD B,A  ; B = tip pixel X
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD D,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD E,A

    LD A,B : ADD A,15 : CP D : RET C
    LD A,D : ADD A,TANK_COLLISION_WIDTH-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,TANK_COLLISION_HEIGHT-1 : CP C : RET C

    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

; checks whether the leftward leg's own 32px-moved trigger should fire
; Thunder this frame - called from UBA_STEP_LEFT, after BOSS_X has
; already been updated for this frame. Repeats for the WHOLE leg
; (round9: "端だけではなくボスが横に32px移動毎に発射"), no longer
; gated on any previous column finishing - ALLOC_THUNDER_SLOT is a real
; pool now (see its own comment).
CHECK_THUNDER_TRIGGER_LEFT:
    LD A,(THUNDER_PENDING)
    OR A
    RET Z
    LD A,(THUNDER_LEG_START_X) : LD B,A
    LD A,(BOSS_X) : LD C,A
    LD A,B : SUB C                  ; distance moved = start - current (X decreases moving left)
    CP THUNDER_TRIGGER_DX
    RET C
    LD A,(BOSS_X) : LD (THUNDER_LEG_START_X),A   ; re-arm baseline for the next THUNDER_TRIGGER_DX
    LD A,(BOSS_X) : ADD A,64        ; boss's own current right edge - trailing behind it as it moves left, no overlap
    SRL A : SRL A : SRL A            ; X -> BG column
    CALL ALLOC_THUNDER_SLOT
    CALL SOUND_THUNDER
    RET

; same idea for the rightward leg (after the left-edge reversal) -
; called from UBA_STEP_RIGHT, after BOSS_X has already been updated for
; this frame. Fires trailing behind the boss here too (its own left
; side, as it moves right) - "反転した時にボス自身に当たってしまう":
; the old code used BOSS_X itself (the boss's own CURRENT left edge) as
; the column start, putting the bolt's own 2-column-wide art directly
; UNDER the boss's own body (both start at the same X); BOSS_X-16
; instead positions it flush against the boss's own trailing left edge
; (column range [BOSS_X-16,BOSS_X), entirely outside the boss's own
; [BOSS_X,BOSS_X+64) box), mirroring the leftward leg's own BOSS_X+64
; (entirely outside on the other side). No underflow risk: the first
; rightward fire can't happen before BOSS_X>=THUNDER_TRIGGER_DX(32).
CHECK_THUNDER_TRIGGER_RIGHT:
    LD A,(THUNDER_PENDING)
    OR A
    RET Z
    LD A,(BOSS_X) : LD B,A
    LD A,(THUNDER_LEG_START_X) : LD C,A
    LD A,B : SUB C                  ; distance moved = current - start
    LD D,A
    ; leg's own FIRST trigger (THUNDER_LEG_START_X still 0, the left-
    ; edge reversal value - never 0 again once this fires, since it's
    ; re-armed to a nonzero BOSS_X right below) only needs
    ; THUNDER_EDGE_TRIGGER_DX(16) - see that constant's own comment for
    ; why. Every later trigger in the leg keeps the normal
    ; THUNDER_TRIGGER_DX(32) cadence.
    LD A,C
    OR A
    JR NZ,CTTR_MID_LEG
    LD A,D
    CP THUNDER_EDGE_TRIGGER_DX
    RET C
    JR CTTR_FIRE
CTTR_MID_LEG:
    LD A,D
    CP THUNDER_TRIGGER_DX
    RET C
CTTR_FIRE:
    LD A,(BOSS_X) : LD (THUNDER_LEG_START_X),A
    LD A,(BOSS_X) : SUB 16           ; boss's own current left edge, minus the bolt's own 16px width
    SRL A : SRL A : SRL A
    CALL ALLOC_THUNDER_SLOT
    CALL SOUND_THUNDER
    RET

; ---------- homing missile (4-instance hw-sprite pool) ----------
; round 3: fired INTERMITTENTLY now, not as one simultaneous volley -
; "弾は4発同時発射ではなく間欠で4発発射". ARM_HORMING_VOLLEY is called
; once at pose-entry (replacing the old FIRE_HORMING call there) and
; only resets the launch counter/timer; UPDATE_HORMING_VOLLEY (called
; every frame from UBA_POSE, alongside DRAW_SASAPI_HAND) ticks the timer
; and fires one more missile via FIRE_ONE_HORMING every
; HORMING_VOLLEY_INTERVAL raw frames until all 4 are out.
ARM_HORMING_VOLLEY:
    XOR A
    LD (HORMING_VOLLEY_COUNT),A
    LD (HORMING_VOLLEY_TIMER),A   ; 0 - fires the first shot on the very next check
    RET

; round36-12 first fired the BG pool's own 4 only after the sprite
; pool's own 4 were already all out (sequential blocks) - round36-13
; correction: "ホーミングはBGとスプライト交互に発射 と言うか同時だな
; そうでなきゃBGやスプライトで分けてる意味がない" - sequential blocks
; meant the BG pool never added any real concurrent capacity during the
; first half of a volley, defeating the entire point of having 2 pools
; (more missiles on screen AT ONCE than 4). Now fires one INTO EACH pool
; on the very same tick - HORMING_VOLLEY_COUNT counts PAIRS (0-4, not
; 0-8), capped at HORMING_SLOT_COUNT (both pools are the same size, so
; either constant works as the pair cap - HORMING_SLOT_COUNT chosen
; since it's the original, always-true-4 one). Still one intermittent
; tick every HORMING_VOLLEY_INTERVAL frames - "間欠で4発発射" - just 2
; missiles per tick now instead of 1, 4 ticks total instead of 8.
; ARM_HORMING_VOLLEY resets this the same way regardless.
UPDATE_HORMING_VOLLEY:
    LD A,(HORMING_VOLLEY_COUNT)
    CP HORMING_SLOT_COUNT
    RET NC                      ; all 4 pairs (8 missiles) already launched this pose
    LD A,(HORMING_VOLLEY_TIMER)
    OR A
    JR Z,UHV_FIRE
    DEC A : LD (HORMING_VOLLEY_TIMER),A
    RET
UHV_FIRE:
    CALL FIRE_ONE_HORMING
    CALL FIRE_ONE_HORMING_BG
    CALL SOUND_HORMING
    LD A,(HORMING_VOLLEY_COUNT) : INC A : LD (HORMING_VOLLEY_COUNT),A
    LD A,HORMING_VOLLEY_INTERVAL : LD (HORMING_VOLLEY_TIMER),A
    RET

; fires exactly one missile into the first inactive pool slot - drops
; the attempt if the pool is somehow already full (shouldn't normally
; happen; same defensive "screen limit, drop the shot" idiom as before,
; now per-shot instead of per-volley). Spawns at HORMING_SPAWN_X/Y
; ("ボスに被らない位置の右上 今の発射位置の16px上あたり"), state0
; (rise), full HORMING_RISE_DIST(32) still to travel, cosmetic facing
; SL (closest available art - no true "upward" sprite exists among the
; 5 uploaded facings, since state0 is the only phase that ever moves
; upward).
FIRE_ONE_HORMING:
    LD B,HORMING_SLOT_COUNT
    LD IX,HORMING_POOL
FOH_LOOP:
    LD A,(IX+0)
    OR A
    JR Z,FOH_SPAWN
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ FOH_LOOP
    RET                          ; pool full - drop the attempt
FOH_SPAWN:
    LD A,1 : LD (IX+0),A
    LD A,HORMING_SPAWN_X : LD (IX+1),A
    LD A,HORMING_SPAWN_Y : LD (IX+2),A
    XOR A
    LD (IX+3),A                  ; facing SL (cosmetic)
    LD (IX+4),A                  ; state 0 = rise
    LD A,HORMING_RISE_DIST : LD (IX+5),A
    RET

; round36-12: mirrors FIRE_ONE_HORMING exactly, targeting HORMING_BG_
; POOL/HORMING_BG_SLOT_COUNT instead. No separate "draw immediately at
; spawn" step needed the way TRY_SPAWN_BULLET has for F-type bullets -
; see ERASE_HORMING_BG_CELL's own comment for why the very next
; UPDATE_HORMING_BG_ALL pass handles this slot's first real draw with
; no special-casing required.
FIRE_ONE_HORMING_BG:
    LD B,HORMING_BG_SLOT_COUNT
    LD IX,HORMING_BG_POOL
FOHB_LOOP:
    LD A,(IX+0)
    OR A
    JR Z,FOHB_SPAWN
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    DJNZ FOHB_LOOP
    RET
FOHB_SPAWN:
    LD A,1 : LD (IX+0),A
    LD A,HORMING_SPAWN_X : LD (IX+1),A
    LD A,HORMING_SPAWN_Y : LD (IX+2),A
    XOR A
    LD (IX+3),A
    LD (IX+4),A
    LD A,HORMING_RISE_DIST : LD (IX+5),A
    RET

; IX = slot base. A = hw sprite pattern code for this slot's CURRENT
; FACING (0=SL,1=DL,2=Down,3=DR,4=SR) - flat table lookup, same order as
; PAT_HORMING_SL's own comment (5 facings x4 codes each, all inside
; Flyer's dynamically-reused block).
RESOLVE_HORMING_PATTERN_IX:
    LD A,(IX+3)
    LD E,A : LD D,0
    LD HL,HORMING_PATTERN_TABLE
    ADD HL,DE
    LD A,(HL)
    RET
HORMING_PATTERN_TABLE:
    DB PAT_HORMING_SL,PAT_HORMING_DL,PAT_HORMING_DOWN,PAT_HORMING_DR,PAT_HORMING_SR

; IX = slot base. Picks ONE random target X within [HORMING_WANDER_
; MIN_X,HORMING_WANDER_MAX_X] and stores it at (IX+6) - called exactly
; once, right when a missile's own rise completes (UOH_RISE's own state
; transition), NOT re-rolled every frame.
; Round-4 fix: "射出後のランダム水平移動が固定されてる お前は1度もまと
; もにランダム扱えてないな". Every existing GAME_RNG consumer in this
; file (UOZ_PAUSE_ROLL and this feature's own round-3 ancestor included)
; reads GAME_RNG, immediately INCs-and-stores it back, then takes the
; low bit of what it just read. When several consumers (or, in round
; 3's case, several missiles within the SAME frame) do that back to
; back, each one just sees "whatever the previous reader left, +1" - the
; low bit ends up toggling in a near-deterministic pattern rather than
; looking random at all, which is almost certainly why the wander read
; as "fixed". Fixed two ways: (1) drawing ONCE per missile instead of
; every frame removes nearly all opportunity for that correlation to
; ever show up visually; (2) this draw is a pure READ of GAME_RNG - it
; never mutates it - mixed via XOR with TICK (a separate free-running
; per-frame byte nothing else reads-and-mutates the way GAME_RNG is).
; HORMING_WANDER_WIDTH(121) isn't a power of 2, so there's no cheap
; AND-mask that lands exactly in range - masks to 0-127 (the next power
; of 2 above the window width) and folds anything >=121 back down by
; subtracting 121 once (127-121=6 < 121, so one subtraction is always
; enough, no loop needed).
; Round-5 fix: "X位置ランダムはホーミング1発毎な 今は4発同じ位置になっ
; てるように見える" - the round-4 version also mixed in (IX+2), this
; slot's own current Y, intending to decorrelate missiles that launch
; close together - but every missile fires from the identical HORMING_
; SPAWN_Y and runs the identical rise trajectory, so (IX+2) is the SAME
; value for every missile at the exact moment this runs (right when its
; own rise completes) - it contributed nothing. Replaced with the low
; byte of IX itself (this slot's own RAM address) - guaranteed different
; for every concurrently-active slot (HORMING_SLOT_SIZE apart), unlike
; Y which converges by construction.
PICK_HORMING_TARGET_X:
    LD A,(GAME_RNG)
    LD B,A
    LD A,(TICK)
    XOR B
    LD B,A
    PUSH IX
    POP HL
    LD A,L
    XOR B
    AND 7Fh
    CP HORMING_WANDER_WIDTH
    JP C,PHTX_OK
    SUB HORMING_WANDER_WIDTH
PHTX_OK:
    ADD A,HORMING_WANDER_MIN_X
    LD (IX+6),A
    RET

; IX = slot base. B = desired facing (0-4, SL..SR). Eases (IX+3) toward
; B by at most 1 of the 5 discrete 45-degree steps - "方向を変える時は
; 45度まで" - never snaps directly across more than one step even if the
; desired facing is further away (e.g. DL straight to SR). A leaf
; routine (only touches A/B and (IX+3)) so it's safe to CALL from
; anywhere without needing to save HL/DE/BC around it.
EASE_HORMING_FACING_IX:
    LD A,(IX+3)
    CP B
    RET Z
    JR C,EHF_UP
    DEC A : LD (IX+3),A
    RET
EHF_UP:
    INC A : LD (IX+3),A
    RET

; IX = slot base. Runs one frame of movement + tank-collision for one
; ACTIVE missile. 4-state flight, per the user's own spec across all
; rounds:
;   state0 (rise): "最初は左斜上に32px移動" - fixed diagonal, X and Y
;     both decrease HORMING_SPEED/frame until RISE_REMAIN(started at
;     HORMING_RISE_DIST=32) reaches 0, then advances to state1 (and
;     picks that state's own one-shot random target X - see
;     PICK_HORMING_TARGET_X). Facing is forced SL throughout (cosmetic
;     only - "打ち出しの上向きキャラは要らない...SLのままでいい" - no
;     upward-facing art was ever requested, SL stays the shown facing
;     the whole time the missile is actually moving up-left, confirmed
;     correct as-is).
;   state1 (wander): "斜めに打ち出したら指定した範囲のランダムX位置ま
;     で水平移動後ホーミング" - picks ONE random target X inside
;     [HORMING_WANDER_MIN_X,HORMING_WANDER_MAX_X] the instant state0
;     completes (not re-rolled every frame - a per-frame coin-flip was
;     round-3's own bug, see PICK_HORMING_TARGET_X's own comment for
;     why), then steps HORMING_SPEED/frame straight toward it. Y is
;     completely frozen throughout this state - "水平移動" is literal.
;     The instant X reaches the target, advances to state2.
;   state2 (2D pursuit/descend): round-4's own follow-up correction -
;     "ホーミング" here means the ORIGINAL 5-way SL/DL/Down/DR/SR
;     distance-bucket tracking from the very first spec message,
;     restored via RESOLVE_HORMING_FACING_IX (moves in both X and Y
;     each frame - the only way this missile, launched near the top of
;     the screen, could ever actually reach a grounded tank). Every
;     frame, also checks whether missile_Y has reached TANK_Y_CUR+
;     HORMING_HOMING_Y_OFFSET(8) - NOT the tank's own exact Y - "自機
;     狙い水平移動の位置を8pxさげてくれ 水平打ちで撃ち落とせる高さ":
;     the final horizontal approach happens at the tank's own
;     horizontal-shot height, so the player gets a real chance to shoot
;     the missile down (CHECK_BULLET_VS_HORMING) before it ever reaches
;     the tank. Uses >=, not exact equality - "完全一致では飛んだ時に
;     Y位置が飛び越えてしまう場合があるからだ" (a HORMING_SPEED-px step
;     can jump straight over one exact value - same lesson as PICK_
;     HORMING_TARGET_X's own parity bug) - and does NOT re-snap Y to
;     the exact threshold when it fires, keeping whatever overshoot
;     that frame's own step already produced, by the same reasoning.
;   state3 (locked horizontal): "水平に自機へホーミング" - once state2's
;     own Y-threshold triggers, Y freezes at wherever it was and the
;     missile continues purely horizontally toward TANK_X from then on.
; In every state, the sprite's own shown facing is a SEPARATE cosmetic
; value eased toward that state's "desired" facing via
; EASE_HORMING_FACING_IX ("方向を変える時は45度まで") - decoupled from
; the actual movement math (which is hardcoded/table-driven per state,
; not derived FROM the eased facing) so a facing that's still catching
; up after a state transition can never accidentally reintroduce a step
; on an axis that state isn't supposed to move on.
; May clear (IX+0) to 0 on an off-screen bail-out or a tank hit; the
; caller (UPDATE_HORMING_ALL) re-checks that right after this returns,
; before drawing. Every early-exit/state-dispatch branch uses JP, not
; JR - this routine is long enough that a JR would risk "JR/DJNZ out of
; range" (already hit once this session in a routine of similar shape).
UPDATE_ONE_HORMING:
    LD A,(IX+4)
    OR A
    JP Z,UOH_RISE
    CP 1
    JP Z,UOH_WANDER
    CP 2
    JP Z,UOH_HOMING2
    JP UOH_LOCKED

; round6 fix: "速度3に" - HORMING_RISE_DIST(32) doesn't divide evenly by
; an odd HORMING_SPEED, so always subtracting a full HORMING_SPEED and
; checking for an EXACT zero (as this used to) would step clean past 0
; and underflow (32,29,...,2,-1=255) - RISE_REMAIN would never read
; back as 0, leaving the missile stuck rising far past its own intended
; 32px forever. Fixed to handle any HORMING_SPEED/parity generally: the
; final step, once remaining distance is under a full HORMING_SPEED,
; moves exactly what's left instead of a fixed amount, so the total
; rise stays exactly HORMING_RISE_DIST regardless of divisibility -
; same "snap the remainder instead of a fixed step" idea as UOH_WANDER's
; own TARGET_X arrival logic. Costs nothing extra on the still-common
; evenly-divisible case (checked first, transitions the same frame
; RISE_REMAIN reads back as 0, same as before this fix).
UOH_RISE:
    XOR A : LD (IX+3),A            ; facing SL (cosmetic)
    LD A,(IX+5)
    OR A
    JP Z,UOH_RISE_ARRIVED           ; already exactly 0 - previous frame's step landed on it
    CP HORMING_SPEED
    JP NC,UOH_RISE_FULL_STEP        ; remain >= HORMING_SPEED - normal full step
    ; 0 < remain < HORMING_SPEED - final partial step, move exactly
    ; what's left rather than a fixed HORMING_SPEED.
    LD B,A
    LD A,(IX+1) : SUB B : LD (IX+1),A
    LD A,(IX+2) : SUB B : LD (IX+2),A
    XOR A : LD (IX+5),A
UOH_RISE_ARRIVED:
    LD A,1 : LD (IX+4),A           ; rise complete -> wander
    CALL PICK_HORMING_TARGET_X     ; picks (IX+6) once, right at the transition
    JP UOH_COLLIDE
UOH_RISE_FULL_STEP:
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+1),A
    LD A,(IX+2)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+2),A
    LD A,(IX+5) : SUB HORMING_SPEED : LD (IX+5),A
    JP UOH_COLLIDE

; steps straight toward this slot's own one-shot TARGET_X(IX+6) - see
; PICK_HORMING_TARGET_X. Y never changes here (state1 is purely
; horizontal - "水平移動"). Transitions to state2 the instant X arrives.
; Snaps exactly to TARGET_X (rather than always stepping by a fixed
; HORMING_SPEED) whenever the remaining distance is HORMING_SPEED or
; less - PICK_HORMING_TARGET_X's own random draw can land on either
; parity, but the missile's own X only ever moves in HORMING_SPEED(2)
; steps from an even starting point, so an exact-equality check alone
; would let an odd TARGET_X be stepped past every frame without ever
; landing on it exactly - a real bug this exact snap-when-close fix
; closes (caught by inspecting a rendered frame, not by the unit tests -
; none of them exercised a genuinely random, possibly-odd target).
UOH_WANDER:
    LD A,(IX+1) : LD B,A            ; B = missile_X
    LD A,(IX+6) : LD C,A            ; C = target_X
    LD A,B : SUB C                   ; A = missile_X-target_X; CF=1 iff missile_X<target_X
    JP NC,UOH_W_AT_OR_RIGHT          ; missile_X>=target_X - A already holds the exact distance
    ; target is to the right - distance = target_X-missile_X
    LD A,C : SUB B
    CP HORMING_SPEED+1
    JP C,UOH_W_SNAP
    LD A,(IX+1) : ADD A,HORMING_SPEED
    CP HORMING_MAXX
    JP NC,UOH_DEACTIVATE
    LD (IX+1),A
    LD B,3                           ; desired facing DR
    JP UOH_W_EASE
UOH_W_AT_OR_RIGHT:
    OR A
    JP Z,UOH_W_ARRIVED               ; already an exact match
    CP HORMING_SPEED+1
    JP C,UOH_W_SNAP
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+1),A
    LD B,1                           ; desired facing DL
    JP UOH_W_EASE
UOH_W_SNAP:
    LD A,(IX+6) : LD (IX+1),A        ; within reach - land on it exactly, this frame
UOH_W_ARRIVED:
    ; "ホーミング開始直後は左斜下に1回だけ必ず移動 自機が右にいた場合に
    ; 急激な曲がりを防ぐため" - one forced DL step, unconditional, the
    ; instant state2 begins, before any real tracking happens - absorbs
    ; whatever facing swing the tank's own position would otherwise
    ; demand on the very first pursuit frame. Shown facing snaps to DL
    ; immediately (not eased) - this one deliberate step is meant to be
    ; seen, not gradually caught up to; every following frame's own real
    ; RESOLVE_HORMING_FACING_IX/EASE_HORMING_FACING_IX pass then eases
    ; from this DL baseline same as any other transition.
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+1),A
    LD A,(IX+2) : ADD A,HORMING_SPEED : LD (IX+2),A
    LD A,1 : LD (IX+3),A             ; facing DL, shown immediately
    LD A,2 : LD (IX+4),A             ; now in state2 (2D pursuit)
    JP UOH_COLLIDE
UOH_W_EASE:
    CALL EASE_HORMING_FACING_IX
    JP UOH_COLLIDE

; IX = slot base. Sets FACING (0=SL,1=DL,2=Down,3=DR,4=SR) from the
; CURRENT horizontal pixel distance to the tank - restored in round4
; (deleted in round3, brought back now that state2 needs real 2D
; pursuit again) - "自機のXとの距離が自機幅より外にある時は斜めのミサ
; イルへ Downは自機幅内に収まっている時 SL、SRは自機から64px以上Xが
; 離れている時 自機より右方向に離れている時はSL、DL 左ならSR、DR"
; (from the very first spec message). Checked fresh every frame - "自
; 機方向に追尾".
RESOLVE_HORMING_FACING_IX:
    LD A,(IX+1) : LD B,A        ; missile_X
    LD A,(TANK_X) : LD C,A

    LD A,B : SUB C
    JR NC,RHFI_RIGHT     ; missile_X>=TANK_X, no borrow - missile is right of the tank
    LD A,C : SUB B         ; TANK_X-missile_X - missile is LEFT of the tank
    LD D,A
    JR RHFI_LEFT_SIDE
RHFI_RIGHT:
    LD D,A                  ; A already = missile_X-TANK_X
RHFI_RIGHT_SIDE:
    LD A,D
    CP TANK_WIDTH+1
    JR C,RHFI_DOWN
    CP HORMING_SIDE_DIST
    JR NC,RHFI_SET_SL
    LD A,1 : LD (IX+3),A    ; DL - missile right of tank, needs to head left
    RET
RHFI_SET_SL:
    XOR A : LD (IX+3),A     ; SL
    RET
RHFI_LEFT_SIDE:
    LD A,D
    CP TANK_WIDTH+1
    JR C,RHFI_DOWN
    CP HORMING_SIDE_DIST
    JR NC,RHFI_SET_SR
    LD A,3 : LD (IX+3),A    ; DR - missile left of tank, needs to head right
    RET
RHFI_SET_SR:
    LD A,4 : LD (IX+3),A    ; SR
    RET
RHFI_DOWN:
    LD A,2 : LD (IX+3),A
    RET

; state2: real 2D pursuit toward the tank (both X and Y move together,
; per RESOLVE_HORMING_FACING_IX's own 5-way facing) until missile_Y
; reaches TANK_Y_CUR+HORMING_HOMING_Y_OFFSET, then hands off to state3
; (locked horizontal) - see UPDATE_ONE_HORMING's own comment.
UOH_HOMING2:
    CALL RESOLVE_HORMING_FACING_IX
    LD A,(IX+3)
    OR A
    JP Z,UOH_H2_STEP_SL
    CP 1
    JP Z,UOH_H2_STEP_DL
    CP 2
    JP Z,UOH_H2_STEP_DOWN
    CP 3
    JP Z,UOH_H2_STEP_DR
    JP UOH_H2_STEP_SR

UOH_H2_STEP_SL:
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+1),A
    JP UOH_H2_TRIGGER
UOH_H2_STEP_SR:
    LD A,(IX+1) : ADD A,HORMING_SPEED
    CP HORMING_MAXX
    JP NC,UOH_DEACTIVATE
    LD (IX+1),A
    JP UOH_H2_TRIGGER
; "自機狙いY位置マッチ水平移動後はホーミングせずそのまま水平移動固定
; で 仮に飛び越えた場合消えなくなるんで" - state2's own Y-moving
; branches (Down/DL/DR) no longer bail out on HORMING_MAXY at all
; (round5 fix) - TANK_Y_CUR is always a sane on-screen value and
; UOH_H2_TRIGGER fires the very same frame Y reaches TANK_Y_CUR+
; HORMING_HOMING_Y_OFFSET, so the old MAXY guard could only ever fire
; BEFORE that trigger if the threshold itself sat past HORMING_MAXY(184)
; - deactivating (vanishing) a missile that should instead have leveled
; off into state3. X off-screen bail-outs (HORMING_MAXX) are unrelated
; and stay.
UOH_H2_STEP_DOWN:
    LD A,(IX+2) : ADD A,HORMING_SPEED : LD (IX+2),A
    JP UOH_H2_TRIGGER
UOH_H2_STEP_DL:
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    LD A,(IX+2) : ADD A,HORMING_SPEED : LD (IX+2),A
    LD A,(IX+1) : SUB HORMING_SPEED : LD (IX+1),A
    JP UOH_H2_TRIGGER
UOH_H2_STEP_DR:
    LD A,(IX+1) : ADD A,HORMING_SPEED
    CP HORMING_MAXX
    JP NC,UOH_DEACTIVATE
    LD B,A
    LD A,(IX+2) : ADD A,HORMING_SPEED : LD (IX+2),A
    LD A,B : LD (IX+1),A

; --- trigger: missile_Y >= TANK_GROUND_Y+HORMING_HOMING_Y_OFFSET - see
; UPDATE_ONE_HORMING's own comment for why this is an inequality (not
; exact match) and why it targets bullet height, not the tank itself.
; round36-12 (実機フィードバック "ホーミングがたまに自機の上あたりに
; 残る事がある 多分ジャンプしたとき"): uses TANK_GROUND_Y (the terrain-
; tier-following resting Y, updated every frame regardless of jump
; state - see its own comment) instead of TANK_Y_CUR (the actually-
; drawn Y, which dips below TANK_GROUND_Y while JUMP_ACTIVE - see
; UPDATE_JUMP's own "TANK_Y_CUR = TANK_GROUND_Y - JUMP_Y_OFFSET").
; State3 is deliberately locked once triggered ("自機狙いY位置マッチ
; 水平移動後はホーミングせずそのまま水平移動固定で" - round5's own
; direct instruction, not something to relax) - the bug wasn't the lock
; itself, it was locking in at whatever height the tank's OWN sprite
; happened to be at that exact instant. If that instant landed mid-jump,
; TANK_Y_CUR was transiently smaller (higher on screen) than the tank's
; real resting height, so the missile locked in above where the tank
; would be once it landed - and then just stayed there, since state3
; never re-checks. TANK_GROUND_Y is immune to this because it tracks
; the terrain-following resting height continuously, jump or not, so
; the lock-in height no longer depends on whether the tank happened to
; be airborne the instant the threshold was crossed.
UOH_H2_TRIGGER:
    LD A,(TANK_GROUND_Y) : ADD A,HORMING_HOMING_Y_OFFSET : LD B,A
    LD A,(IX+2)
    CP B
    JP C,UOH_COLLIDE                  ; still above the threshold - stay in state2
    LD A,3 : LD (IX+4),A              ; threshold reached/passed - lock horizontal (state3)
    JP UOH_COLLIDE

; state3: locked horizontal - Y stays exactly wherever state2's own
; trigger left it, X steps toward TANK_X only - "水平に自機へホーミン
; グ". Holds position/facing once aligned rather than oscillating.
UOH_LOCKED:
    LD A,(IX+1) : LD B,A            ; missile_X
    LD A,(TANK_X)
    CP B
    JP Z,UOH_H_ALIGNED
    JP C,UOH_H_DESIRED_SL           ; tank_X < missile_X -> missile right of tank -> move left
    LD A,(IX+1) : ADD A,HORMING_SPEED
    CP HORMING_MAXX
    JP NC,UOH_DEACTIVATE
    LD (IX+1),A
    LD B,4                          ; desired SR
    JP UOH_H_EASE
UOH_H_DESIRED_SL:
    LD A,(IX+1)
    CP HORMING_SPEED
    JP C,UOH_DEACTIVATE
    SUB HORMING_SPEED : LD (IX+1),A
    LD B,0                           ; desired SL
    JP UOH_H_EASE
UOH_H_ALIGNED:
    LD A,(IX+3) : LD B,A             ; already lined up - hold facing, no X step
UOH_H_EASE:
    CALL EASE_HORMING_FACING_IX
    JP UOH_COLLIDE

; AABB vs the tank's own real TANK_COLLISION_WIDTH x_HEIGHT box - missile
; is 8x8. Same shape as every other hit-pair test in this file (see
; CHECK_HIT_PAIR_BOSS).
UOH_COLLIDE:
    LD A,(IX+1) : LD B,A        ; mx
    LD A,(IX+2) : LD C,A        ; my
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD D,A      ; tx
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD E,A  ; ty

    LD A,B : ADD A,7 : CP D : JR C,UOH_NO_HIT
    LD A,D : ADD A,TANK_COLLISION_WIDTH-1 : CP B : JR C,UOH_NO_HIT
    LD A,C : ADD A,7 : CP E : JR C,UOH_NO_HIT
    LD A,E : ADD A,TANK_COLLISION_HEIGHT-1 : CP C : JR C,UOH_NO_HIT

    ; hit - matches APPLY_TANK_DAMAGE's own documented future-use comment
    ; ("いずれ敵弾実装予定") - this is exactly that.
    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    XOR A : LD (IX+0),A
    RET

UOH_NO_HIT:
    RET

UOH_DEACTIVATE:
    XOR A : LD (IX+0),A
    RET

; "今はミサイルに判定がないがショットで撃ち落とせるように" - the
; tank's own bullets (F or U - both are BG-drawn cell-based during the
; boss fight, see DRAW_BULLET_CELL's own comment, so ERASE_BULLET_CELL
; always applies here unconditionally, unlike CHECK_HIT_PAIR's own
; IX+1-gated version written for the pre-boss hw-sprite-U case) can now
; shoot a missile down - loops all 3 bullet slots against all 4 missile
; slots, same "IX=bullet, IY=pool, nested loop" shape as CHECK_BULLET_
; VS_ZUM. Missile is treated as an 8x8 box (matches UOH_COLLIDE's own
; sizing), no front/back distinction needed (unlike Zum) since a
; missile has no "safe side". On a hit: erase the bullet's own BG cell,
; deactivate both the bullet and the missile, same destroy/score/sound
; feedback as CHECK_HIT_PAIR's own CHP_DESTROY path.
CHECK_BULLET_VS_HORMING:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_ONE_BULLET_HORMING
    LD IX,BULLET1_ACT : CALL CHECK_HIT_ONE_BULLET_HORMING
    LD IX,BULLET2_ACT : CALL CHECK_HIT_ONE_BULLET_HORMING
    RET

; round36-12: also checks the new BG-drawn pool, right after the
; original hw-sprite pool - a bullet can shoot down either kind of
; missile equally (see CHECK_HIT_PAIR_HORMING_BG's own comment for the
; one real difference: a BG-drawn kill also has to erase the missile's
; own cell, not just deactivate it).
CHECK_HIT_ONE_BULLET_HORMING:
    LD IY,HORMING_POOL
    LD B,HORMING_SLOT_COUNT
CHOBH_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR_HORMING
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOBH_LOOP
    LD IY,HORMING_BG_POOL
    LD B,HORMING_BG_SLOT_COUNT
CHOBH_BG_LOOP:
    PUSH BC
    CALL CHECK_HIT_PAIR_HORMING_BG
    POP BC
    INC IY : INC IY : INC IY : INC IY : INC IY : INC IY : INC IY
    DJNZ CHOBH_BG_LOOP
    RET

CHECK_HIT_PAIR_HORMING:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+0)
    OR A
    RET Z

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A   ; bullet pixel X = COL*8
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A   ; bullet pixel Y = ROW*8
    LD A,(IY+1) : LD D,A     ; missile_X
    LD A,(IY+2) : LD E,A     ; missile_Y

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,7 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,7 : CP C : RET C

    CALL ERASE_BULLET_CELL
    XOR A : LD (IX+0),A
    LD (IY+0),A
    CALL SOUND_DESTROY
    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; IX = bullet slot, IY = HORMING_BG_POOL slot - same AABB test as
; CHECK_HIT_PAIR_HORMING, but a hit here must ALSO erase the missile's
; OWN BG cell (ERASE_HORMING_BG_CELL takes IX=its own slot base, so IY's
; value is swapped into IX via the stack - PUSH/POP through a register
; pair is the standard way to move a value between the 2 index
; registers, Z80 has no direct IX<->IY transfer) before just zeroing its
; ACT byte - the sprite-pool version doesn't need this because
; UPDATE_HORMING_ALL's own per-frame hide path (Y=209) already "erases"
; a deactivated sprite for free; a BG cell has no such implicit erase,
; so skipping this would leave the missile's last-drawn glyph frozen on
; screen forever.
CHECK_HIT_PAIR_HORMING_BG:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(IY+0)
    OR A
    RET Z

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A   ; bullet pixel X = COL*8
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A   ; bullet pixel Y = ROW*8
    LD A,(IY+1) : LD D,A     ; missile_X
    LD A,(IY+2) : LD E,A     ; missile_Y

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,7 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,7 : CP C : RET C

    CALL ERASE_BULLET_CELL
    PUSH IX
    PUSH IY : POP IX
    CALL ERASE_HORMING_BG_CELL
    POP IX
    XOR A : LD (IX+0),A
    LD (IY+0),A
    CALL SOUND_DESTROY
    LD HL,SCORE_PER_KILL
    CALL ADD_SCORE
    RET

; called every frame regardless of pose state (once the boss exists) - a
; missile in flight keeps flying even if the pose that fired it has
; already ended (see UPDATE_ONE_HORMING's own comment). Walks
; HORMING_POOL (IX, 7 bytes/slot) and HORMING_SPRITE_ATTRS (HL, 4
; bytes/slot) in lockstep - inactive slots are hidden (Y=209), active
; ones updated then staged, then the whole 4-slot buffer is flushed to
; hw sprite slots6-9 once at the end (not per-slot - same "one flush
; after N stages" shape as FLUSH_ZUM_SPRITES's own callers).
; RET Z's immediately while BOSS_ACT=0 - the missile pool can never have
; anything active before the boss exists (nothing can fire), but slots
; 6-9 still genuinely belong to ZacoII/BulletU pre-boss; touching VRAM
; here at all before the boss spawns would stomp their own real data
; every frame (see HORMING_SPR_BASE_SLOT's own comment for the related
; bug this exact unconditional-flush shape caused against the boss's
; own body).
UPDATE_HORMING_ALL:
    LD A,(BOSS_ACT)
    OR A
    RET Z
    LD IX,HORMING_POOL
    LD HL,HORMING_SPRITE_ATTRS
    LD B,HORMING_SLOT_COUNT
UHA_LOOP:
    PUSH BC
    LD A,(IX+0)
    OR A
    JR Z,UHA_HIDE
    ; HL is this loop's own walking pointer into HORMING_SPRITE_ATTRS -
    ; UPDATE_ONE_HORMING (via APPLY_TANK_DAMAGE/SOUND_ZUM_DEFLECT on a
    ; hit) and RESOLVE_HORMING_PATTERN_IX (its own table lookup) both use
    ; HL as scratch, so it must be saved/restored around both calls or
    ; the attrs buffer gets written to whatever address either of them
    ; left HL pointing at instead.
    PUSH HL
    CALL UPDATE_ONE_HORMING
    POP HL
    LD A,(IX+0)
    OR A
    JR Z,UHA_HIDE
    LD A,(IX+2) : LD (HL),A : INC HL      ; Y
    LD A,(IX+1) : LD (HL),A : INC HL      ; X
    PUSH HL
    CALL RESOLVE_HORMING_PATTERN_IX
    POP HL
    LD (HL),A : INC HL
    LD A,HORMING_COLOR : LD (HL),A : INC HL
    JR UHA_NEXT
UHA_HIDE:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
UHA_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    POP BC
    DJNZ UHA_LOOP
    CALL FLUSH_HORMING_SPRITES
    RET

; blasts HORMING_SPRITE_ATTRS (4 slots x4 bytes = 16 bytes) to hw sprite
; slots HORMING_SPR_BASE_SLOT..+3 - same single DI/EI-wrapped raw OUT +
; NOP-padded loop as FLUSH_ZUM_SPRITES/FLUSH_ENEMY_SPRITES (small enough for
; one wrap, unlike FLUSH_BOSS_SPRITES's own per-quadrant DI/EI chunking).
FLUSH_HORMING_SPRITES:
    DI
    LD A,HORMING_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,HORMING_SPRITE_ATTRS
    LD B,16
FHS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FHS_LOOP
    EI
    RET

; ---------- homing missile, BG-cell pool (round36-12, "弾数を増やす")
; ---------- see HORMING_BG_POOL's own comment for why this exists as a
; second, separate pool instead of just growing HORMING_SLOT_COUNT.
; IX = HORMING_BG_POOL slot base (+1 X,+2 Y, pixel coords). Computes
; this frame's own name-table VRAM address fresh from (IX+1)/(IX+2)
; every time it's needed (COL=X>>3, ROW=Y>>3, address = BULLET_ROWADDR_
; LO/HI[ROW]+COL - the same row-address tables TRY_SPAWN_BULLET/
; UPDATE_ONE_BULLET already use, reused directly since they're pure
; row->VRAM-address conversion, nothing bullet-specific about them).
; Unlike the bullet pool, HORMING_BG_POOL has no spare struct field to
; cache this in (same shape as HORMING_POOL, shared generically by
; UPDATE_ONE_HORMING) - recomputing it is cheap and avoids growing the
; struct at all. Returns the address in HL.
HORMING_BG_CELL_ADDR:
    LD A,(IX+2) : SRL A : SRL A : SRL A   ; ROW
    LD E,A : LD D,0
    LD HL,BULLET_ROWADDR_LO : ADD HL,DE : LD A,(HL) : LD C,A
    LD HL,BULLET_ROWADDR_HI : ADD HL,DE : LD A,(HL) : LD B,A
    LD A,(IX+1) : SRL A : SRL A : SRL A   ; COL
    LD L,A : LD H,0
    LD D,B : LD E,C
    ADD HL,DE
    RET

; IX = HORMING_BG_POOL slot base, NOT yet advanced by this frame's own
; UPDATE_ONE_HORMING call (so (IX+1)/(IX+2) still hold wherever this
; slot was actually drawn last frame, or its spawn position on a brand
; new slot's very first active frame). Restores the true background at
; that cell - same row-threshold logic as ERASE_BULLET_CELL (sky/
; skysand/sand/skip-entirely-once-inside-the-scrolling-terrain-band,
; rows20-23 - "already got fully redrawn from NAMEBUF earlier this same
; MAINLOOP iteration, so there's nothing to restore"), reused directly
; since it describes screen geometry, not anything bullet-specific.
; Safe to call even before this slot has ever actually been drawn -
; erasing just repaints whatever the ONE true background already is
; for that cell, a harmless no-op in that case rather than a special
; case needing its own guard (unlike the sprite pool, which needs an
; explicit hide/Y=209 step - a BG cell has no such concept, restoring
; the real background already "un-shows" it).
ERASE_HORMING_BG_CELL:
    LD A,(IX+2) : SRL A : SRL A : SRL A   ; ROW
    LD B,A
    CP BULLET_ROCK_ROW_MIN
    JR C,EHBC_SKY
    CP BULLET_ROCK_ROW_MIN+4
    JR NC,EHBC_SKIP
    CP BULLET_ROCK_ROW_MIN
    JR Z,EHBC_SKYSAND
    LD A,TERRAIN_BLANK_CODE
    JR EHBC_WRITE
EHBC_SKYSAND:
    LD A,(NIGHT_ROW)
    CP NIGHT_END_ROW
    JR C,EHBC_SKYSAND_DAY
    LD A,NIGHT_CODE
    JR EHBC_WRITE
EHBC_SKYSAND_DAY:
    LD A,SKYSAND_CODE
    JR EHBC_WRITE
EHBC_SKY:
    LD A,(NIGHT_ROW)
    CP B
    JR C,EHBC_SKY_BLUE
    LD A,HUD_ROW_BLANK_CODE
    JR EHBC_WRITE
EHBC_SKY_BLUE:
    LD A,SKY_BLANK_CODE
EHBC_WRITE:
    LD (BULLET_TEMP_BYTE),A
    CALL HORMING_BG_CELL_ADDR
    CALL WRITE_BULLET_BYTE_HL
EHBC_SKIP:
    RET

; IX = HORMING_BG_POOL slot base, already advanced to this frame's new
; position by UPDATE_ONE_HORMING; (IX+2)=Y, (IX+3)=FACING(0-4). round36-
; 14 ("BGホーミングが地形に入ったときはSandの背景色になるように"): picks
; between 2 color-group tables by row, same threshold ERASE_HORMING_BG_
; CELL's own EHBC_SKY branch uses (BULLET_ROCK_ROW_MIN) - black/group18
; above it (sky), Sand-colored/group12 at or below it (terrain) - see
; HORMING_BG_SAND_SL_CODE's own comment for the group2->group12
; relocation history.
DRAW_HORMING_BG_CELL:
    LD A,(IX+2) : SRL A : SRL A : SRL A   ; ROW
    CP BULLET_ROCK_ROW_MIN
    JR NC,DHBC_SAND
    LD HL,HORMING_BG_PATTERN_TABLE
    JR DHBC_PICK
DHBC_SAND:
    LD HL,HORMING_BG_SAND_PATTERN_TABLE
DHBC_PICK:
    LD A,(IX+3)
    LD E,A : LD D,0
    ADD HL,DE
    LD A,(HL)
    LD (BULLET_TEMP_BYTE),A
    CALL HORMING_BG_CELL_ADDR
    JP WRITE_BULLET_BYTE_HL
HORMING_BG_PATTERN_TABLE:
    DB HORMING_BG_SL_CODE,HORMING_BG_DL_CODE,HORMING_BG_DOWN_CODE,HORMING_BG_DR_CODE,HORMING_BG_SR_CODE
HORMING_BG_SAND_PATTERN_TABLE:
    DB HORMING_BG_SAND_SL_CODE,HORMING_BG_SAND_DL_CODE,HORMING_BG_SAND_DOWN_CODE,HORMING_BG_SAND_DR_CODE,HORMING_BG_SAND_SR_CODE

; called every frame alongside UPDATE_HORMING_ALL (same BOSS_ACT guard
; and "runs every frame once the boss exists, regardless of pose state"
; reasoning - see UPDATE_HORMING_ALL's own comment). Erase-then-move-
; then-draw per active slot, same per-frame shape UPDATE_ONE_BULLET
; already uses for F-type bullets: erase happens BEFORE UPDATE_ONE_
; HORMING moves X/Y (at wherever this slot was actually drawn last
; frame), draw happens AFTER (at the new position), only if the slot is
; still active (a frame that hits the tank or leaves the screen
; deactivates it mid-call - already erased, nothing left to draw).
UPDATE_HORMING_BG_ALL:
    LD A,(BOSS_ACT)
    OR A
    RET Z
    LD IX,HORMING_BG_POOL
    LD B,HORMING_BG_SLOT_COUNT
UHBGA_LOOP:
    PUSH BC
    LD A,(IX+0)
    OR A
    JR Z,UHBGA_NEXT
    CALL ERASE_HORMING_BG_CELL
    CALL UPDATE_ONE_HORMING
    LD A,(IX+0)
    OR A
    JR Z,UHBGA_NEXT
    CALL DRAW_HORMING_BG_CELL
UHBGA_NEXT:
    INC IX : INC IX : INC IX : INC IX : INC IX : INC IX : INC IX
    POP BC
    DJNZ UHBGA_LOOP
    RET

; ---------- SBeam ("サンダービーム", real hw sprite pool reusing the
; boss's own dormant pose-time body slots - see SBEAM_SPR_BASE_SLOT's
; own comment) ----------
; called once, at pose-entry, from UBA_MOVE_RIGHT, ONLY when the
; SBEAM_POSE_GATE(2) eligibility check there already passed (UBA_MOVE_
; RIGHT branches between this and ARM_HORMING_VOLLEY - "当然サンダー
; ビーム中はホーミングも...撃たねえんだよ", the two are mutually
; exclusive per pose, so the gate check lives at the call site, not
; here). Arms the drop phase (SBEAM_ACT=1) and pre-computes the ground
; pixel Y for the fixed column SBEAM_START_COL via GET_TERRAIN_ROW_FOR_
; COL (same terrain-cache walk Thunder's own ALLOC_THUNDER_SLOT uses) -
; row*8-8 so the drop's own last 8x8-lit segment sits flush just above
; the terrain surface.
FIRE_SBEAM:
    LD A,1 : LD (SBEAM_ACT),A
    XOR A : LD (SBEAM_ROWS),A
    XOR A : LD (SBEAM_BLINK),A
    XOR A : LD (SBEAM_TRIP),A
    LD A,SBEAM_START_COL
    CALL GET_TERRAIN_ROW_FOR_COL
    ADD A,A : ADD A,A : ADD A,A   ; row -> pixel Y (row*8)
    SUB 8
    LD (SBEAM_GROUND_Y),A
    CALL SOUND_SBEAM
    RET

; called every frame (from MAINLOOP, alongside UPDATE_THUNDER) - does
; nothing while SBEAM_ACT=0 (no VRAM touch at all, since slots
; SBEAM_SPR_BASE_SLOT.. are the boss's OWN body slots and must be left
; alone whenever SBeam isn't actively using them - see SBEAM_SPR_BASE_
; SLOT's own comment; UBAP_END's own DRAW_BOSS/FLUSH_BOSS_SPRITES already
; reclaims/overwrites those slots with the real body art the instant the
; pose ends, so no extra cleanup is needed here beyond UBAP_END forcibly
; clearing SBEAM_ACT itself).
UPDATE_SBEAM:
    LD A,(SBEAM_ACT)
    OR A
    RET Z
    CP 1
    JR Z,US_STEP_DROP
    CALL US_SWEEP_RETRACT
    JR US_STAGE
US_STEP_DROP:
    CALL US_DROP_STEP
US_STAGE:
    CALL STAGE_SBEAM
    CALL FLUSH_SBEAM_SPRITES
    RET

; "サンダーやサンダービームも自機が当たるとダメージ食らうように 判定
; は先端部だけでいいだろう" - SBeam's own "tip" is already tracked as a
; single point (SBEAM_LINE_TX/TY, in 8px-grid units) by STAGE_SBEAM's
; own line algorithm every frame this is active - reused directly rather
; than recomputed, so this MUST run after UPDATE_SBEAM's own CALL within
; the same frame (see MAINLOOP). Same AABB shape as CHECK_ONE_THUNDER_
; VS_TANK/UOH_COLLIDE (tank's own real 32x32 box), 8px wide/tall for the
; tip (SBeam's own lit art is a single 8x8 cell - see sbeam_gen.py).
; TANK_HAZARD_IFRAMES gates repeat hits (see CHECK_THUNDER_VS_TANK's own
; comment for why the shared TANK_FLASH_TIMER alone wasn't long enough).
CHECK_SBEAM_VS_TANK:
    LD A,(SBEAM_ACT)
    OR A
    RET Z
    LD A,(TANK_HAZARD_IFRAMES)
    OR A
    RET NZ
    LD A,(SBEAM_LINE_TY) : ADD A,A : ADD A,A : ADD A,A : LD C,A   ; C = tip pixel Y
    LD A,(SBEAM_LINE_TX) : ADD A,A : ADD A,A : ADD A,A : LD B,A   ; B = tip pixel X
    LD A,(TANK_X) : ADD A,TANK_COLLISION_X_OFFSET : LD D,A
    LD A,(TANK_Y_CUR) : ADD A,TANK_COLLISION_Y_OFFSET : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : ADD A,TANK_COLLISION_WIDTH-1 : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : ADD A,TANK_COLLISION_HEIGHT-1 : CP C : RET C

    LD A,FLASH_DURATION : LD (TANK_FLASH_TIMER),A
    LD A,TANK_HAZARD_IFRAME_DURATION : LD (TANK_HAZARD_IFRAMES),A
    CALL APPLY_TANK_DAMAGE
    CALL SOUND_ZUM_DEFLECT
    RET

; drop phase (SBEAM_ACT=1): grows SBEAM_ROWS by one 8px-tall segment per
; frame (matching the art's own top-left-8x8-lit convention - see
; STAGE_SBEAM's own comment for why 8px steps, not 16px, avoid gaps),
; from SBEAM_START_Y downward. Transitions to the sweep phase (ACT=2,
; SBEAM_FRONT_COL reset to SBEAM_START_COL) the instant the newest
; segment reaches SBEAM_GROUND_Y - all the real geometry here (max ~7
; segments to the terrain) stays well under the SBEAM_SLOT_COUNT(16) hw
; cap, but that cap is still checked first as a hard safety backstop.
US_DROP_STEP:
    LD A,(SBEAM_ROWS)
    CP SBEAM_SLOT_COUNT
    RET NC                       ; safety cap - never overrun the pool
    LD B,A                       ; B = index of the segment about to be added
    ADD A,A : ADD A,A : ADD A,A  ; A = index*8
    ADD A,SBEAM_START_Y          ; A = this new segment's own Y
    LD C,A
    LD A,(SBEAM_GROUND_Y) : LD D,A
    LD A,B : INC A : LD (SBEAM_ROWS),A   ; commit the new row count
    LD A,C
    CP D
    RET C                        ; not at the ground yet - still growing
    LD A,2 : LD (SBEAM_ACT),A    ; reached the ground - start the sweep
    LD A,SBEAM_START_COL : LD (SBEAM_FRONT_COL),A
    RET

; sweep(ACT=2)/retract(ACT=3) phase step - SBEAM_FRONT_COL decreases
; toward 0 while sweeping ("左端まで行ったら"), then, once it's actually
; reached 0, flips to retracting and increases back toward SBEAM_START_
; COL ("元の位置まで同じラインで描画"); done (ACT=0) once it's back home.
; STAGE_SBEAM's own single rendering formula (column>=SBEAM_FRONT_COL)
; serves both directions unchanged - only which way FRONT_COL itself
; moves differs.
; "サンダービームは2往復に" - SBEAM_TRIP_COUNT full sweep+retract round
; trips before actually finishing, not just 1.
US_SWEEP_RETRACT:
    LD A,(SBEAM_ACT)
    CP 2
    JR Z,USR_SWEEP
    LD A,(SBEAM_FRONT_COL) : INC A : LD (SBEAM_FRONT_COL),A
    CP SBEAM_START_COL
    RET C                        ; still retracting
    ; fully home - either start another round trip or actually finish
    LD A,(SBEAM_TRIP) : INC A : LD (SBEAM_TRIP),A
    CP SBEAM_TRIP_COUNT
    JR NC,USR_ALL_TRIPS_DONE
    LD A,2 : LD (SBEAM_ACT),A    ; another round trip
    RET
USR_ALL_TRIPS_DONE:
    XOR A : LD (SBEAM_ACT),A     ; back home - done
    RET
USR_SWEEP:
    LD A,(SBEAM_FRONT_COL)
    OR A
    JR Z,USR_REVERSE             ; already at the screen's left edge
    DEC A : LD (SBEAM_FRONT_COL),A
    RET
USR_REVERSE:
    LD A,3 : LD (SBEAM_ACT),A
    RET

; fills SBEAM_SPRITE_ATTRS (SBEAM_SLOT_COUNT slots x4 bytes) with a
; single Bresenham line from the FIXED origin (SBEAM_START_COL,
; SBEAM_START_ROW) to a MOVING tip - "複数本じゃなく1本だぞ" (round3) -
; not 2 fixed-shape arms glued at a corner. Own hidden-slot idiom is
; IDENTICAL to STAGE_HORMING's own (Y=209, rest 0). "点滅で表示で 取り
; 敢えず1フレ点滅で" - a plain 1-frame on/1-frame off toggle: on an
; "off" tick every slot is forced hidden regardless of phase, same as
; ACT=0's own idle state.
; The tip is (SBEAM_START_COL,SBEAM_GROUND_Y/8) while dropping (fixed
; column, growing row - via SBEAM_ROWS) or (SBEAM_FRONT_COL,SBEAM_
; GROUND_Y/8) while sweeping/retracting (fixed row, moving column) -
; same state SBEAM_ACT/_ROWS/_FRONT_COL/_GROUND_Y already tracked before
; this round, only the RENDERING changed. All Bresenham work happens in
; 8px-grid units (columns/rows), converted to pixels only at the very
; last step (ADD A,A x3 = *8) when writing each slot.
; "点滅表示は2フレ表示1フレ非表示に変更" - SBEAM_BLINK now cycles
; 0,1,2,0,1,2,... (mod 3) instead of a plain 0/1 toggle; hidden only on
; the 3rd value (2), visible on the other two - a 2-frames-on/1-frame-
; off flicker instead of the old 1-on/1-off.
STAGE_SBEAM:
    LD A,(SBEAM_BLINK) : INC A
    CP 3
    JR C,SS_BLINK_NOWRAP
    XOR A
SS_BLINK_NOWRAP:
    LD (SBEAM_BLINK),A
    CP 2
    JP Z,SS_ALL_HIDDEN
    LD A,(SBEAM_ACT)
    OR A
    JP Z,SS_ALL_HIDDEN
    CP 1
    JR Z,SSL_TARGET_DROP
    LD A,(SBEAM_FRONT_COL) : LD (SBEAM_LINE_TX),A
    LD A,(SBEAM_GROUND_Y) : SRL A : SRL A : SRL A : LD (SBEAM_LINE_TY),A
    JR SSL_HAVE_TARGET
SSL_TARGET_DROP:
    LD A,SBEAM_START_COL : LD (SBEAM_LINE_TX),A
    LD A,(SBEAM_ROWS) : ADD A,SBEAM_START_ROW : LD (SBEAM_LINE_TY),A
SSL_HAVE_TARGET:
    ; dx = SBEAM_START_COL - TX (>=0, TX never exceeds the origin column)
    LD A,(SBEAM_LINE_TX) : LD B,A
    LD A,SBEAM_START_COL : SUB B
    LD (SBEAM_LINE_DX),A
    ; dy = TY - SBEAM_START_ROW (>=0, TY never sits above the origin row)
    LD A,(SBEAM_LINE_TY) : SUB SBEAM_START_ROW
    LD (SBEAM_LINE_DY),A
    LD A,SBEAM_START_COL : LD (SBEAM_LINE_X),A
    LD A,SBEAM_START_ROW : LD (SBEAM_LINE_Y),A
    ; branch on dx>=dy (shallow, step X every iter) vs dx<dy (steep, step Y every iter)
    LD A,(SBEAM_LINE_DY) : LD B,A
    LD A,(SBEAM_LINE_DX)
    CP B
    JR C,SSL_Y_BRANCH
SSL_X_BRANCH:
    LD A,(SBEAM_LINE_DY) : LD D,A          ; D = dy (loop-invariant)
    LD A,(SBEAM_LINE_DX) : LD E,A          ; E = dx (loop-invariant)
    SRL A : LD (SBEAM_LINE_ERR),A          ; err = dx/2
    LD A,E : INC A : LD B,A                ; B = dx+1 (iteration count)
    ; cap B at SBEAM_SLOT_COUNT when it would otherwise exceed it - real
    ; bug caught here (round4): "SBEAM_SLOT_COUNT+1:CP B:JR NC" treats
    ; B==SLOT_COUNT+1 as "no carry" (CP never borrows on an EXACT match),
    ; so the one case that most needed capping (dx=SLOT_COUNT, B=SLOT_
    ; COUNT+1) slipped through uncapped - SSL_HIDE_REST's own "SLOT_
    ; COUNT-C" then underflowed to 255, and the hide loop wrote ~1000
    ; bytes past SBEAM_SPRITE_ATTRS, corrupting the stack - the real
    ; cause of "ビームが左端まで行くとリセットかかった". Comparing
    ; against SLOT_COUNT itself (not +1) and branching on the CARRY from
    ; "SLOT_COUNT-B" (set exactly when B>SLOT_COUNT) covers B==SLOT_
    ; COUNT+1 correctly too.
    LD A,SBEAM_SLOT_COUNT : CP B
    JR NC,SSL_X_NOCAP
    LD B,SBEAM_SLOT_COUNT                  ; hw sprite budget cap - see SBEAM_SLOT_COUNT's own comment
SSL_X_NOCAP:
    LD C,B
    LD IX,SBEAM_SPRITE_ATTRS
SSL_X_LOOP:
    LD A,(SBEAM_LINE_Y) : ADD A,A : ADD A,A : ADD A,A : LD (IX+0),A
    LD A,(SBEAM_LINE_X) : ADD A,A : ADD A,A : ADD A,A : LD (IX+1),A
    LD A,SBEAM_CODE : LD (IX+2),A
    LD A,SBEAM_COLOR : LD (IX+3),A
    INC IX : INC IX : INC IX : INC IX
    LD A,(SBEAM_LINE_ERR) : SUB D : LD (SBEAM_LINE_ERR),A
    JP M,SSL_X_YSTEP
    JR SSL_X_XSTEP
SSL_X_YSTEP:
    LD A,(SBEAM_LINE_Y) : INC A : LD (SBEAM_LINE_Y),A
    LD A,(SBEAM_LINE_ERR) : ADD A,E : LD (SBEAM_LINE_ERR),A
SSL_X_XSTEP:
    LD A,(SBEAM_LINE_X) : DEC A : LD (SBEAM_LINE_X),A
    DJNZ SSL_X_LOOP
    JR SSL_HIDE_REST
SSL_Y_BRANCH:
    LD A,(SBEAM_LINE_DX) : LD E,A          ; E = dx (loop-invariant)
    LD A,(SBEAM_LINE_DY) : LD D,A          ; D = dy (loop-invariant)
    SRL A : LD (SBEAM_LINE_ERR),A          ; err = dy/2
    LD A,D : INC A : LD B,A                ; B = dy+1 (iteration count, always <=SBEAM_SLOT_COUNT in practice)
    LD C,B
    LD IX,SBEAM_SPRITE_ATTRS
SSL_Y_LOOP:
    LD A,(SBEAM_LINE_Y) : ADD A,A : ADD A,A : ADD A,A : LD (IX+0),A
    LD A,(SBEAM_LINE_X) : ADD A,A : ADD A,A : ADD A,A : LD (IX+1),A
    LD A,SBEAM_CODE : LD (IX+2),A
    LD A,SBEAM_COLOR : LD (IX+3),A
    INC IX : INC IX : INC IX : INC IX
    LD A,(SBEAM_LINE_ERR) : SUB E : LD (SBEAM_LINE_ERR),A
    JP M,SSL_Y_XSTEP
    JR SSL_Y_YSTEP
SSL_Y_XSTEP:
    LD A,(SBEAM_LINE_X) : DEC A : LD (SBEAM_LINE_X),A
    LD A,(SBEAM_LINE_ERR) : ADD A,D : LD (SBEAM_LINE_ERR),A
SSL_Y_YSTEP:
    LD A,(SBEAM_LINE_Y) : INC A : LD (SBEAM_LINE_Y),A
    DJNZ SSL_Y_LOOP
SSL_HIDE_REST:
    LD A,SBEAM_SLOT_COUNT : SUB C : LD B,A
    LD A,B : OR A
    RET Z                        ; the line already used the whole budget
SSL_HIDE_LOOP:
    LD A,209 : LD (IX+0),A
    XOR A : LD (IX+1),A
    XOR A : LD (IX+2),A
    XOR A : LD (IX+3),A
    INC IX : INC IX : INC IX : INC IX
    DJNZ SSL_HIDE_LOOP
    RET
SS_ALL_HIDDEN:
    LD HL,SBEAM_SPRITE_ATTRS
    LD B,SBEAM_SLOT_COUNT
SSAH_LOOP:
    LD A,209 : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    XOR A : LD (HL),A : INC HL
    DJNZ SSAH_LOOP
    RET

; blasts SBEAM_SPRITE_ATTRS (SBEAM_SLOT_COUNT*4=88 bytes) to hw sprite
; slots SBEAM_SPR_BASE_SLOT.. - same single DI/EI-wrapped raw NOP-padded OUT
; idiom as FLUSH_HORMING_SPRITES, just B=88 instead of 16 (loop body
; itself unchanged, so its own JR/DJNZ range is identical/known-good).
FLUSH_SBEAM_SPRITES:
    DI
    LD A,SBEAM_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD HL,SBEAM_SPRITE_ATTRS
    LD B,SBEAM_SLOT_COUNT*4
FSS_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ FSS_LOOP
    EI
    RET

CHECK_BULLET_VS_BOSS:
    LD IX,BULLET0_ACT : CALL CHECK_HIT_PAIR_BOSS
    LD IX,BULLET1_ACT : CALL CHECK_HIT_PAIR_BOSS
    LD IX,BULLET2_ACT : CALL CHECK_HIT_PAIR_BOSS
    RET

; IX = bullet slot base. AABB vs the boss's own real footprint (BOSS_X..
; +size-1, BOSS_Y..+size-1) - "ボスにコリジョン 見た目通り" - same shape
; as CHECK_HIT_PAIR_FLYER/ETANK, just with the boss's own fixed-Y/full-
; size box. Only ever matters while BOSS_ACT=1 (checked first) - by that
; same point every ordinary enemy has stopped spawning, and BOTH bullet
; types (F and U - see DRAW_BULLET_CELL's own boss-only U-BG-drawing
; entry) are guaranteed BG-drawn, not a hw sprite, so ERASE_BULLET_CELL
; is called unconditionally on a hit here, with no IX+1(TYPE) branch
; needed (unlike CHECK_HIT_PAIR_FLYER/ETANK, written back when U was
; always a hw sprite outside this exact window).
;
; round36-14 follow-up #3 ("形態変化後に64x64のコリジョンのままになって
; る 32x32になるよう修正") - size-1 (63 for the old 64x64 body, 31 for
; the broken form's real 32x32 one) is no longer a single compile-time
; literal: computed into CHPB_SIZE_SCRATCH once per call based on
; BOSS_FORM, then added via ADD A,(HL) (this assembler has no ADD A,n+r8
; form, only r8/mHL/imm sources - see mini_z80asm.py's own enc_alu_a).
CHECK_HIT_PAIR_BOSS:
    LD A,(IX+0)
    OR A
    RET Z
    LD A,(BOSS_ACT)
    CP 1
    RET NZ

    LD A,(BOSS_FORM)
    CP BOSS_FORM_ACTIVE
    LD A,BOSS_COLLISION_SIZE-1
    JR NZ,CHPB_SIZE_SET
    LD A,BOSS_BROKEN_COLLISION_SIZE-1
CHPB_SIZE_SET:
    LD (CHPB_SIZE_SCRATCH),A

    LD A,(IX+2) : ADD A,A : ADD A,A : ADD A,A : LD B,A
    LD A,(IX+3) : ADD A,A : ADD A,A : ADD A,A : LD C,A
    LD A,(BOSS_X) : LD D,A
    LD A,(BOSS_Y) : LD E,A

    LD A,B : ADD A,7 : CP D : RET C
    LD A,D : LD HL,CHPB_SIZE_SCRATCH : ADD A,(HL) : CP B : RET C
    LD A,C : ADD A,7 : CP E : RET C
    LD A,E : LD HL,CHPB_SIZE_SCRATCH : ADD A,(HL) : CP C : RET C

    CALL ERASE_BULLET_CELL
    XOR A : LD (IX+0),A

    LD A,(BOSS_HP) : DEC A : LD (BOSS_HP),A
    JR Z,CHPBOSS_DESTROY
    ; round36-14 Part C: HP<=200 triggers the form-change once (never
    ; re-triggers - guarded on BOSS_FORM still being 0 - see TRIGGER_
    ; BOSS_BROKEN_FORM's own comment). CP THRESHOLD+1 so this catches
    ; the crossing hit itself (A==200 included), not just strictly below.
    CP BOSS_BROKEN_HP_THRESHOLD+1
    JR NC,CHPBOSS_NORMAL_HIT
    LD A,(BOSS_FORM)
    OR A
    JR NZ,CHPBOSS_NORMAL_HIT
    CALL TRIGGER_BOSS_BROKEN_FORM
CHPBOSS_NORMAL_HIT:
    LD A,FLASH_DURATION : LD (BOSS_FLASH_TIMER),A
    ; round36-14 follow-up#5 real-hardware feedback ("ボス戦のみボスの
    ; ダメージ音(キンキン音)カットで ボス攻撃音と被ってしまうんで") -
    ; this CALL SOUND_ZUM_DEFLECT only ever runs while BOSS_ACT=1 (see
    ; CHECK_HIT_PAIR_BOSS's own guard at its own top), i.e. only during
    ; the boss fight - exactly the one context where SOUND_HORMING/
    ; SOUND_THUNDER/SOUND_SBEAM/SOUND_SASAPI_LASER now also compete for
    ; this same shared channel-A envelope, and the player hits the boss
    ; far more often/rapidly than any other SOUND_ZUM_DEFLECT trigger
    ; (Zum's own front-invincibility bounce, or the tank taking a hit) -
    ; so it was constantly stomping the new attack SFX right as they
    ; started. Dropped here only - every other SOUND_ZUM_DEFLECT call
    ; site (Zum bounce, tank hit by Homing/Thunder/SBeam) is unchanged;
    ; the boss's own hit-flash (BOSS_FLASH_TIMER, just above) still
    ; fires normally, this is audio-only.
    RET
; round32 fix: "なぜ爆発エフェクト中にボス消してる 消さないでくれ BGで
; やってる意味がない" - this used to HIDE_BOSS_SPRITES immediately on
; death, before the new SPARK burst even got a chance to run - the whole
; point of drawing the burst in BG instead of as a sprite was for it to
; sit "behind" a still-VISIBLE boss ("裏になるが近い色なので見た目は気に
; ならないはず"), so hiding the boss the instant it dies defeated that
; entirely. No longer hides here - the boss sprite simply stays exactly
; as it last looked (DRAW_BOSS/FLUSH_BOSS_SPRITES never runs again once
; BOSS_ACT=2, see UPDATE_BOSS_ALL) all the way through SPARK; GROW's own
; existing blink logic (see UBE_GROW) is what starts actually toggling
; it, unchanged from before.
CHPBOSS_DESTROY:
    LD A,2 : LD (BOSS_ACT),A
    CALL INIT_BOSS_EXPLOSION
    RET

; round36-14 Part C: fires exactly once per boss fight, the instant HP
; reaches BOSS_BROKEN_HP_THRESHOLD (50, inclusive) - CHPBOSS_NORMAL_HIT's
; own BOSS_FORM!=0 guard is what prevents a 2nd call on every subsequent hit.
; "即座に強制停止" - interrupts whatever UBA_ACTIVE was doing this exact
; frame (mid-patrol, mid-pose, mid-left-pause) unconditionally; nothing
; here waits for the current attack/pose to finish first.
TRIGGER_BOSS_BROKEN_FORM:
    ; if a hand-art pose happened to be up at this exact instant, erase
    ; it and bring the real body sprite back (matches INIT_BOSS_
    ; EXPLOSION's own IBE_NO_HAND branch exactly - see its own comment
    ; for why: pose-time hides the hw sprite entirely via HIDE_BOSS_
    ; SPRITES at pose-entry, so without this the boss would just stay
    ; invisible through the whole SPARK burst and straight into the
    ; broken form reveal). round36-14 follow-up (real-hardware report:
    ; "スパーク爆発で最初からボスが消えてる...消えてしまうことがある
    ; 何らかの切り替えタイミングの問題だろう" - exactly this: the FIRST
    ; version of this routine only erased the hand art and reset BOSS_
    ; PHASE, but forgot the DRAW_BOSS/FLUSH_BOSS_SPRITES call INIT_BOSS_
    ; EXPLOSION's own equivalent branch has, so a trigger that happened
    ; to land mid-pose left the sprite hidden for the rest of the fight).
    ; XOR-to-0 the phase unconditionally afterward too (not just on the
    ; branch that erased it) - a real 2nd death later, after the broken
    ; form's own further HP loss, still routes through the SAME INIT_
    ; BOSS_EXPLOSION as any other death (see BOSS_EXPL_REASON's own
    ; comment - that path is deliberately left as-is, out of this
    ; round's scope), and its own IBE_NO_HAND check needs BOSS_PHASE to
    ; genuinely be 0 by then, not a stale 1 frozen from the moment of
    ; this interruption.
    LD A,(BOSS_PHASE)
    CP 1
    JR NZ,TBBF_NO_HAND
    CALL ERASE_SASAPI_HAND
    XOR A : LD (BOSS_PHASE),A
    CALL DRAW_BOSS
    CALL FLUSH_BOSS_SPRITES
    JR TBBF_PHASE_DONE
TBBF_NO_HAND:
    XOR A : LD (BOSS_PHASE),A
TBBF_PHASE_DONE:
    LD A,BOSS_FORM_SPARK : LD (BOSS_FORM),A
    ; capture center cell + arm the spark burst - same setup INIT_BOSS_
    ; EXPLOSION's own SPARK entry uses (see ARM_BOSS_EXPL_SPARK), minus
    ; the white-fill tile/color upload - GROW/SHRINK/FLASH never run for
    ; this REASON, so that tile is never needed here (see UBS_LAST_FRAME).
    LD A,(BOSS_X) : ADD A,32 : SRL A : SRL A : SRL A : LD (BOSS_EXPL_CX),A
    LD A,(BOSS_Y) : ADD A,32 : SRL A : SRL A : SRL A : LD (BOSS_EXPL_CY),A
    ; round36-14 follow-up #2 ("インフィニティ軌道はその位置から始まる
    ; が一旦中央に寄せろ") - nothing to capture here any more: BOSS_X/
    ; BOSS_Y already hold exactly the position the old body just died
    ; at, untouched by anything from this point through REVEAL_BOSS_
    ; BROKEN_FORM, so the broken form's own reveal naturally starts from
    ; the right spot for free - REVEAL_BOSS_BROKEN_FORM/UPDATE_BOSS_
    ; BROKEN_ACTIVE's own RECENTERING sub-phase is what walks it toward
    ; the fixed screen-center orbit point from there (see BOSS_BROKEN_
    ; RECENTERING's own comment).
    DI
    LD HL,EXPLOSION_PATTERN : LD DE,BOSS_EXPL_SPARK_CODE_TL*8 : LD BC,32 : CALL LDIRVM
    EI
    LD A,BOSS_EXPL_SPARK_COLORBYTE : LD (HUD_TEMP_BYTE),A
    LD HL,HUD_TEMP_BYTE : LD DE,2000h+BOSS_EXPL_SPARK_GROUP : LD BC,1 : CALL LDIRVM
    CALL ARM_BOSS_EXPL_SPARK
    LD A,1 : LD (BOSS_EXPL_REASON),A
    RET

; walks CLOUD_POOL (IX-indexed, 9x INC IX per slot - this assembler has
; no ADD IX,DE, same as UE_UPDATE_ALL) calling UPDATE_ONE_CLOUD on every
; slot. PUSH/POP BC around the CALL: UPDATE_ONE_CLOUD's own cell-write
; helpers use B/C as scratch, which would otherwise corrupt this loop's
; DJNZ counter - same precaution as every other pool loop in this file.
; once GAME_TICK>=NIGHT_START_TICK(900), clouds stop moving/spawning/
; drawing entirely for the rest of the run - whatever cell each one
; last drew stays frozen until CHECK_NIGHT's own sweep overwrites that
; row anyway, so nothing lingers once night actually reaches it. A real
; 16-bit compare (SBC HL,DE, same idiom CHECK_NIGHT's own timer check
; uses) - NIGHT_START_TICK is well past 255, so the old single-byte
; `CP NIGHT_START_TICK` this used to be (correct only while the
; constant fit in 8 bits) would silently compare against just its low
; byte instead, firing 768 GAME_TICKs early.
CLOUD_UPDATE_ALL:
    LD HL,(GAME_TICK)
    LD DE,NIGHT_START_TICK
    OR A
    SBC HL,DE
    RET NC
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
; of the same DI-wrapped NOP-padded OUT block.
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

; ROWPHASE_T is loop-invariant for the whole 32-cell scan (it's set once
; per frame in MAINLOOP, never touched mid-row) - the old single-loop
; version re-tested "ROWPHASE_T==0" on every one of the 32 iterations
; even though the outcome could never change within one call, and in
; the nonzero case re-read ROWPHASE_T a SECOND time (for the "-1" used
; in the final ADD) every iteration too. Real, measured cost (T-state
; profiling this round, "処理が遅いんだよな...アルゴリズムで高速か可能
; なものはないか"): TERRAIN_RENDER_ROW alone was 43.57% of a whole
; frame's T-state budget, more than any other single routine in the
; game. Splitting into 2 loop bodies - selected ONCE at entry instead
; of every iteration - removes that per-iteration branch+re-read
; entirely (~29-36 T-states/iteration depending on path, ~128
; iterations/frame across all 4 tiers). Output is bit-for-bit identical
; to the old single-loop version for every input - this is pure loop-
; invariant code motion, not an algorithm change (see
; tests/terrain_render_perf_test.py's own equivalence sweep against the
; git HEAD-before-this-round version).
TERRAIN_RENDER_ROW:
    LD A,(ROWPHASE_T)
    OR A
    JR NZ,TRR_NONZERO_ENTRY
    LD B,32
    LD A,(HL) : LD C,A
TRR_LOOP_ZERO:
    INC HL
    LD A,(HL) : LD (TERRAIN_NEXTID),A
    LD A,C : LD E,A : LD D,TERRAIN_SOLOTAB/256 : LD A,(DE)
    LD (IX+0),A
    INC IX
    LD A,(TERRAIN_NEXTID) : LD C,A
    DJNZ TRR_LOOP_ZERO
    RET
TRR_NONZERO_ENTRY:
    DEC A : LD (TRR_PHASE_MINUS1),A
    LD B,32
    LD A,(HL) : LD C,A
TRR_LOOP_NONZERO:
    INC HL
    LD A,(HL) : LD (TERRAIN_NEXTID),A
    LD A,C : LD E,A : LD D,TERRAIN_MUL_N/256 : LD A,(DE) : LD E,A
    LD A,(TERRAIN_NEXTID) : ADD A,E
    LD E,A : LD D,TERRAIN_PAIRBASE/256 : LD A,(DE)
    LD E,A
    LD A,(TRR_PHASE_MINUS1) : ADD A,E
    LD (IX+0),A
    INC IX
    LD A,(TERRAIN_NEXTID) : LD C,A
    DJNZ TRR_LOOP_NONZERO
    RET

    ALIGN 256
TERRAIN_LUT:
    DB 0,1,2,3,4,5,6,7,8,9,10
    DS 245,0

TERRAIN_BLANK_ROW:
    DS 768,0

; sprites/Life_8x8.json, converted by hand (single static 8x8 tile) -
; see the LIFE_CODE comment above. cols0-6 filled, col7 blank -> every
; row is 11111110b = 254.
LIFE_PATTERN:
    DB 254,254,254,254,254,254,254,254

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

HUD_ZERO8:
    DS 8,0
HUD_BLACKROW32:
    DS 32,HUD_ROW_BLANK_CODE
NIGHT_STRIPEROW32:
    DS 32,NIGHT_CODE

; fg6 (dark red, was the tank's) / bg11 (light yellow - "カラーグルー
; プ節約するから Rockも背景色ライトイエローにしろ Rock225と同じだ")
; x31 - see the color-swap patch in INIT above.
; round36-12 attempted bg1(black) here ("Rockの背景色をダークレッドに"),
; then round36-13 reverted it back to bg11 - "まずRock225もイジったな
; Rock225の背景色は前に戻せ": this ONE byte colors group1(codes8-15),
; which is NOT just plain Rock - terrain_gen.py's own STEADY_BASE packs
; ROCK_L/ROCK_R AND all 4 R225 climb/descend variants (R225_UL/UR/
; R225D_UL/UR) into this exact same group (codes8-13, see STEADY_CODE),
; and most of the blend/transition pair codes involving them share it
; too (BLEND_BASE's own "every mixed pair stays in the ordinary rock-
; colored pool" consolidation - ROCK_COLOR_SWAPPED_PATCH itself blankets
; groups1,3-31, not just group1). Rock and Rock225 are not two
; independently-colorable things in the current design - they are the
; literal same VRAM color byte - so "change Rock's bg without touching
; Rock225" is not achievable without relocating R225's own ids to a
; separate group and re-deriving its own blend-pair coloring, a much
; larger change than a byte tweak and one with real precedent for
; reintroducing exactly the flicker/seam bugs this same consolidation
; was built to fix ("まだチラついてる Rockの前後だけおかしい" et al. -
; see terrain_gen.py's own SAND_GROUPS/BLEND_BASE comments for that
; history). Not attempted here without being asked for it directly.
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
; "一番最初の雲が3行必ず固まって出てくる 1回目が多分ランダム前の初期
; 値使ってるだろ" - confirmed: ICL_LOOP's own INIT-time CLOUD_RANDOM_
; WAIT calls ran before a single real MAINLOOP frame had ever executed,
; so GAME_RNG was still its own fresh-boot value each time - 3
; consecutive CALLs just INC it 3 times in a row (0->1->2->3), giving
; slots 0-2 nearly identical WAIT values(31/32/33) instead of a real
; spread, so all 3 clouds spawned in lockstep the very first time.
; Fixed the same way CLOUD_ROW_TABLE/INTERVAL/FIXED4 already are: a
; fixed per-slot table for this one INIT-time use only, spread across
; CLOUD_RANDOM_WAIT's own real 30-157 range. UPDATE_ONE_CLOUD's own
; later respawn-time CLOUD_RANDOM_WAIT call is untouched - by then
; GAME_RNG has plenty of real accumulated entropy from actual gameplay
; frames, so it's genuinely random from the 2nd spawn on.
CLOUD_INIT_WAIT_TABLE:
    DB 30,72,114

; src/CYBER SHMUP.asm's own CLOUD_WA_CODE/CLOUD_WB_CODE pattern bytes,
; copied byte-for-byte ("Stage1でもやってる雲を").
CLOUD_A_PATTERN:
    DB 06h,6Fh,0FEh,1Bh,04h,00h,00h,00h
CLOUD_B_PATTERN:
    DB 00h,0D8h,0B4h,0EFh,0B0h,60h,00h,00h

; ===== generated tables (terrain + tank) appended below by build_test.py =====
