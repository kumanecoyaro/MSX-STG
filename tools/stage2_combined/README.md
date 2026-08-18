# Terrain + tank combined test

Merges `tools/stage2_terrain`'s ground scroller with
`tools/stage2_tank`'s sprite into one standalone 32KB ROM - the
tank-only test showed the tank floating on nothing, which isn't a
meaningful check, and separately reportedly froze on real hardware
with no way to tell where.

## What's here

- Terrain engine (own INIT priming + MAINLOOP scroll update) and tank
  sprite (4x 16x16 hardware sprites) both set up in one INIT, both
  driven from the same MAINLOOP/TICK.
- **Movement**: port1 stick, left/right only, clamped to the screen.
  Speed went 2 -> 1 -> 1.5px/frame ("自機移動速度が速い気がするんで
  速度落として", then "速度1.5に出来ないか") - since there's no
  fractional pixel, `TANK_SPEED_LO`(1) alternates with a +1 bump
  gated by `TICK` bit0 (same trick as the vertical climb easing below)
  so the step size alternates 1,2,1,2,..., averaging exactly
  1.5px/frame over any 2-frame window (verified: 30px moved over 20
  frames while holding the stick). Up alone or combined with left/right sets
  the "aim up" flag (`TANK_AIMUP`) without moving the tank vertically -
  it only switches the sprite pose (see below), matching "no up/down
  movement, left/right only" from the spec.
- **Jump**: button B, edge-triggered (a held button doesn't repeat).
  24px half-sine arc over 49 frames (`JUMP_OFFSET_TABLE`, generated as
  `round(24*sin(pi*t/48))` for t=0..48 - eased in/out, brief hang near
  the peak, per direct instruction "サインジャンプ"; supersedes an
  earlier constant-1px/frame triangular arc), applied as
  `TANK_Y_CUR = TANK_GROUND_Y - JUMP_Y_OFFSET` - `TANK_GROUND_Y` is the
  terrain-following baseline from `UPDATE_TERRAIN_COLLISION` below
  (used to be the fixed constant `TANK_Y_BASE`), so a jump arcs
  relative to whichever tier the tank is currently standing on. Not
  real gravity/physics, just a fixed-shape hop added on top of that.
- **Terrain collision** (`UPDATE_TERRAIN_COLLISION`): the tank always
  rests on whichever terrain tier is under it ("常にRockに設置") and
  switches to the Gap pose while straddling a climb/descend transition
  ("Rock225に接触したらGapスプライトに切り替えて登るように...Rock
  戻ったらノーマルに戻す"). One probe name-table column near the
  tank's right/front edge, `TANK_COL_R` (`(TANK_X+TANK_FOOT_DX)>>3` -
  "自機の右下"), scans `IDCACHE_T0`-`IDCACHE_T3` top-to-bottom for the
  first non-BLANK id at that column to find the surface tier - "下は
  Rock設置を調べ" - any non-BLANK id (steady rock or a slope-transition
  cell) counts as solid ground. `TANK_TIER_Y_TABLE` gives the found
  row-index's target Y (`TANK_TIER=3`, the track's starting/lowest
  tier, reproduces the original fixed `TANK_Y_BASE`(156) exactly; each
  row-index down is 8px higher) - note this numbering runs opposite to
  `terrain_gen.py`'s own generator "tier" (which counts up while
  climbing), since row-index0 is the *highest* screen row. No descend
  art exists yet, so both the climb (`R225_UL`/`R225_UR`) and descend
  (`R225D_UL`/`R225D_UR`) ids trigger the same Gap pose - "まだ下りの
  絵を用意してないのでGapスプライト流用".
  - `TANK_GROUND_Y` eases toward that target instead of snapping the
    full 8px in one frame, which looked like a jolt/jitter at every
    tier change - "登り降り時に一気に8px移動してるんでガタついてる
    ...滑らかに繋げて". First cut moved at a flat `TANK_CLIMB_SPEED`
    (2px/frame, 4 frames/tier) - visually smooth for one isolated
    climb, but a flat speed unrelated to the terrain's own scroll rate
    finished each climb well before the next chained one was ready,
    reading as a momentary pause between them, and as "climbing on its
    own" rather than moving with the terrain - "連続Gapだと一瞬止まっ
    てる...地形に沿って移動じゃなく地形に入ったら自分で8pxのぼって
    る...地形の移動とマッチしてない". Measured the actual gap between
    chained tier changes on this track (~16 frames) and retuned:
    `TANK_CLIMB_SPEED`(1px) is now gated to every *other* frame
    (`TICK` bit0), averaging 0.5px/frame - 16 frames for the full 8px,
    matching that pace. Verified with an emulator trace across the
    rapid-chain climb section: `TANK_GROUND_Y` now counts down
    continuously with no flat/paused frames between chained tier
    changes, and the Gap pose (see `TANK_SLOPE_HOLD` below) stays
    active for the whole stretch.
  - That ~16-frame pace was measured with the tank standing still,
    though - `TANK_COL_R` also moves when the tank itself steers, so
    moving toward oncoming terrain (especially through the rapid-chain
    section) lets the probe advance through tiers faster than the
    stationary baseline. At the slow pace alone, `TANK_GROUND_Y` then
    fell behind and the tank visibly sank into the rock for a stretch -
    "左右移動が加わるとGapに突っ込んでる...登ってはいるが地形にめり
    込んでる". A `TANK_CLIMB_CATCHUP_SPEED` fast-path (only engaging
    past `TANK_CLIMB_CATCHUP_THRESHOLD`(9px, must stay above the 8px
    every single-tier transition *starts* at, or every climb becomes
    an instant snap again - see the bug entry below) behind) narrowed
    the worst case but never fully closed it - even a single ordinary
    climb's own 8px starting gap could grow while below that
    threshold, so "まだ左右移動で地形めり込んでる" persisted. Root
    issue: the slow, terrain-matched pace only ever looked right with
    the tank standing still - once actively steering, the tank's own
    motion is already the dominant visual cue, so tracking the ground
    closely matters more than matching the terrain's own scroll rate.
    Now selects the pace by whether `TANK_DX` is 0: stationary keeps
    the slow terrain-matched easing, steering switches to
    `TANK_CLIMB_SPEED_MOVING` (ungated). Swept 2/3/4/5/6/8 holding the
    stick right through the whole track, measuring the worst-case lag
    behind target at each (6/5/4/3/2/0px) - 8 reached 0 but closes a
    full 8px gap in a single frame, reading as an instant snap instead
    of a climb ("前後移動が加わると特に前方移動で8px登りになってる").
    6 (worst-case lag 2px) still completed a climb in as few as 2
    frames, which read the same way moving forward - "前移動登りで
    8px登りになったな". Settled on 2 - the same value the very first
    easing attempt used, back when it was praised as smooth for one
    cell, before terrain-pace-matching became the goal - worst-case
    lag 6px, but spread over 4-5 frames, closer in feel to the
    stationary pace above; the Gap art offset below also means that
    6px of lag no longer reads as visibly sinking the way it used to.
  - **Gap pose art offset**: `TankFGap`/`TankUGap`'s own art extends 3
    rows further down within their 32x32 canvas than `TankF`/`TankUp`
    does (lowest non-blank sprite row 29 vs 26, measured directly from
    the source JSON) - a fixed offset baked into the art itself, not
    the dynamic ground-Y logic above, so drawing a Gap pose at the
    exact same `TANK_Y_CUR` as a Normal pose always put its own wheels
    3px lower on screen, i.e. visibly sunk into the ground even once
    `TANK_Y_CUR` itself was fully settled at the correct tier -
    reported as digging in persisting even standing still, after the
    lag-based fixes above already worked - "静止でもGapにまだ食い込ん
    でた". An earlier `+4px` offset (tried, then reverted, several
    rounds back) had pushed the *same direction* as this discrepancy,
    making it worse rather than better, which is why it read as a
    jarring dip back then. Fixed with `TANK_GAP_ART_OFFSET`(3), the
    other direction and sized from the actual art gap instead of
    guessed: `UPDATE_TANK_SPRITES` draws any Gap pose at
    `TANK_Y_CUR - 3` (`TANK_DRAW_Y`) so its wheels land at the same
    screen row Normal's would. Purely a rendering offset - collision
    and jump math still use the untouched `TANK_Y_CUR`/`TANK_GROUND_Y`.
  - **Slope check** ("Gapを調べる", sets `TANK_ON_SLOPE`) went through
    2 rounds: a separate probe 1 column *behind* `TANK_COL_R` always
    lagged the Y-tier-snap by exactly 1 column's scroll time (it was
    reading what `TANK_COL_R` had already scrolled past), which showed
    up as the tank floating above the slope for a stretch after each Y
    jump, since the Gap pose hadn't caught up yet - "判定位置の問題
    ...登ってからでは遅い". `TANK_FOOT_DX` was also pulled back twice
    (24->16->12, delaying the Y-snap itself further from the tank's
    front edge) and a rendering-only `+4px` Gap offset was tried and
    dropped (it caused a visible dip right when the pose switched,
    once it was finally lagging even further behind the Y-snap).
    Reworked to check relative to `TANK_COL_R` itself instead of a
    lagging probe: (a) is `TANK_COL_R`'s own cell, at the tier just
    found, itself a Rock225/Rock225D id (3-6, vs. plain `ROCK_L`/
    `ROCK_R`'s 1-2) - currently straddling it - or (b) is the cell
    diagonally up-right from it (1 row up - the tier *above* the one
    just found, where a climb marker actually lives, since R225 sits
    in the row "newly becoming rock" - 1 column ahead of `TANK_COL_R`)
    a marker - about to reach it - per direct instruction ("今の前の
    判定の斜め右上と同一のGapセルならGapスプライト維持で"). Either
    condition holds Gap; (b) lets the pose switch slightly *before*
    the Y-snap instead of after, so by the time Y jumps the sprite is
    already showing Gap.
  - `TANK_ON_SLOPE` also has a 2-frame hold (`TANK_SLOPE_HOLD`) after
    the last raw "yes" reading before it actually drops to 0, instead
    of following the raw per-frame probe directly - the rapid-climb
    section chains transitions with no flat run between them, and a
    single-frame gap of plain rock between 2 chained Rock225 markers
    would otherwise flicker the pose back to Normal for 1 frame, per
    direct instruction ("Gap判定が2連続なら(登ってもGap)またRockで
    ないならノーマルに切り替えずGapスプライトのままに").
- **Pose selection** (`UPDATE_POSE`): TankF (grounded, neutral),
  TankUp (grounded, aiming up), TankFGap (airborne OR on a slope,
  neutral), TankUGap (airborne OR on a slope, aiming up) - jump takes
  priority if both are somehow true at once (can't currently happen,
  since a jump's peak height stays well inside the tank's own tier
  range). The terrain-slope-following use of the Gap poses (originally
  deferred, airborne-only) is now wired up per the terrain-collision
  work above.
- **Per-quadrant sprite color**: each 32x32 pose is 4 separate 16x16
  hardware sprites (TL/TR/BL/BR), and MSX1 sprites are monochrome, so
  each quadrant gets its own color attribute instead of one flat tank
  color - TL (main body) medium red, TR/BL/BR (gun/treads) black - per
  direct instruction (initially "右上のスプライトの色をグレーに
  右下左下をブラックに", then TR changed from gray to black, then TL
  changed from dark blue to medium red to dark red over 3 rounds -
  "自機の左上のスプライトをミドルレッドに変更", then "自機の色を
  ダークレッドに").
- **Shot** (A button, edge-triggered, pool of 3 - "Stage1と同様に
  制限数画面内3発", mirroring `src/CYBER SHMUP.asm`'s own BULLET0/1/2):
  drawn as BG (name-table) characters, not sprites - same reasoning as
  the player's own shots in that file, any number can share a scanline
  with the tank/terrain sprites with no "4 sprites per line" flicker.
  Two shapes: `BulletF` (straight ahead, 1 column/frame, fixed row -
  the row it spawned at) and `BulletU` (diagonal, 1 column/frame *and*
  1 row up/frame - fired while holding up, i.e. `TANK_AIMUP`). Spawn
  row = `TANK_Y_CUR>>3`, +1 more for `BulletF` only (per direct
  instruction "BulletFのセル表示を1セル下に" - `BulletU` keeps the
  un-shifted muzzle row); spawn column = `(TANK_X+24)>>3` on the right
  side of the tank when facing right, `(TANK_X+7)>>3` (mirrored offset,
  `BULLET_MUZZLE_DX_LEFT` = 32-1-24) on the left side when facing left
  - see **Left-facing flip** below.
  - **Background compositing** ("背景色は書換先のセルを調べて合成"):
    SCREEN1 color is fixed per 8-character-code group, not per screen
    position, so a bullet can't just draw its pixels over whatever's
    already there - it needs a dedicated pattern code placed in a
    color group whose bg matches the terrain tile actually underneath.
    `terrain_gen.py`'s own color table only ever uses 2 solid colors
    total: `SKY_COLOR` for the permanent open sky, and one uniform
    `ROCK_COLOR` shared by *every* terrain code in the scrolling band
    (flat/slope/climb/still-blank alike - see that file's own comment
    on id0/BLANK) - so "row `>= BULLET_ROCK_ROW_MIN`(19)" is exactly
    (not approximately) the right test for "rock-colored", regardless
    of which tile is really at that cell.
  - `BulletF` and `BulletU` share one fg color again (both black - per
    direct instruction; briefly split into 2 separate color-group
    pairs each when only `BulletF` was black, one round earlier), so
    they share one pair of groups, split only by background:
    `BULLETF_SKY_CODE`/`BULLETU_SKY_CODE` (color group 11: fg1
    black/bg5) and `BULLETF_ROCK_CODE`/`BULLETU_ROCK_CODE` (group 12:
    fg1 black/bg10) - both groups patched onto `terrain_gen.py`'s
    generic per-group color-table slots that no real terrain code ever
    uses (codes 88-103, well past the terrain's own 0-87).
  - **Erasing** (before advancing) restores row19 explicitly (it's
    static, filled once at INIT and never touched again) or sky
    (`SKY_BLANK_CODE`), but is skipped entirely for rows 20-23 - those
    already get fully redrawn from `NAMEBUF` every frame *before* the
    bullet update runs (see `MAINLOOP`), so there's nothing for a
    bullet to restore there; writing anything would just fight with -
    and be overwritten by - that same frame's real terrain content one
    step later. Verified with an emulator sweep: a `BulletF` traveling
    the length of row20 leaves zero stray codes behind at any point.
  - Per-frame draw/erase uses the same raw `DI`-wrapped `OUT` + 8-NOP
    pattern as `UPDATE_TANK_SPRITES`/`INIT_SPRATR_CLR` (see the bug
    entries below) - this runs every frame with `EI` active too.
- **Bullet spawn row stays bounded even with a moving tank**: the
  shot background-compositing above depends on a shot's spawn row
  always being `<= BULLET_ROCK_ROW_MIN`(19) - now that the tank's own
  Y moves with the terrain instead of sitting at a fixed baseline,
  that still holds by construction: `TANK_TIER_Y_TABLE`'s highest
  entry (156, `TANK_TIER=3`, the track's lowest/starting tier) is the
  same value the old fixed `TANK_Y_BASE` used, and the track only has
  4 rows total (20-23) - there's no tier below that one for the tank
  to reach, so its Y (and therefore a spawn row = `TANK_Y_CUR>>3`)
  never exceeds 19 either.
- **Left-facing flip, auto-fire, and direction lock** (per direct
  instruction: "では次は機体の反転 今の自機と弾を左操作で左向きに
  反転パターンはそっちで生成してくれ ダメなら修正する / で弾はボタン
  押しっぱなし自動連射 3連射は同じだが間欠連射 1発打ったら1発空ける
  / 発射ボタンのAが押されてなくて左右移動ならその向きを向くように
  まあAボタンは向きのロックだな"):
  - **Generated mirror art** ("反転パターンはそっちで生成してくれ" -
    generate the flip yourself, no new source art): both `tank_gen.py`
    and `bullet_gen.py` gained an `hflip_bits` helper (row-reversal of
    the 2D bit grid, the same idea `terrain_gen.py` already used to
    derive the descend slope from the climb slope) and now emit a
    second, mirrored copy of every pose/pattern from the *same* source
    JSON. For the tank, flipping the whole 32x32 grid before splitting
    it into the usual 4 16x16-hardware-sprite quadrants makes the
    quadrant swap (screen-left becomes what was screen-right) fall out
    for free - no separate sub-tile-swap logic needed. The 4
    left-facing poses land at pattern-group numbers 64-127
    (`TANK_POSE_FLIP_OFFSET`), right after the 4 right-facing ones at
    0-63; `UPDATE_POSE` adds that offset onto whatever pose it just
    picked whenever `TANK_FACING`=1. Bullets get the same treatment:
    `BULLET_F_L_PATTERN`/`BULLET_U_L_PATTERN`, loaded into 4 more
    reused color-group codes (90/91/98/99, same sky/rock split as the
    right-facing codes) alongside the existing ones.
  - **Per-quadrant color also has to flip**: MSX1 sprite color is a
    flat per-hardware-sprite attribute, not baked into the pattern
    bytes, so mirroring the *art* alone would leave the TL quadrant
    (main body, medium red) and TR quadrant (gun, black) sitting in
    their un-mirrored screen positions even though the pixels under
    them just swapped sides. `UPDATE_TANK_SPRITES` now stages the 4
    quadrant colors into `UTS_COLOR_0-3` first, swapping TL<->TR and
    BL<->BR when `TANK_FACING`=1, and writes sprite attributes from
    those instead of the raw `TANK_COLOR_*` constants directly.
  - **Muzzle/travel direction mirrors too**: `TRY_SPAWN_BULLET` now
    branches its muzzle-column formula on `TANK_FACING` (copied into
    each bullet slot's new `+6 FACING` byte at spawn, so an
    already-flying bullet keeps its own direction even if the tank
    flips afterward), and `UPDATE_ONE_BULLET`'s per-frame column
    advance branches the same way - decrementing instead of
    incrementing for a left-facing bullet, with a new col=0 guard
    (`UOB_DEACTIVATE`) symmetric to the existing right-edge overflow
    check, since a left-moving bullet can now run off the *left* edge
    of the screen too. `DRAW_BULLET_CELL` picks among 8 pattern codes
    now instead of 4 (type x sky/rock x facing).
  - **Auto-fire** ("弾はボタン押しっぱなし自動連射...間欠連射 1発
    打ったら1発空ける"): `UPDATE_SHOT` no longer edge-triggers on A: a
    new `SHOT_COOLDOWN` byte (RAM) counts down every frame regardless
    of input, and a shot can only spawn once it hits 0, which then
    rearms it to `SHOT_COOLDOWN_FRAMES`(8) - so holding A fires
    continuously but with a gap between each shot rather than one
    every single frame, while the existing 3-bullet on-screen pool cap
    (`TRY_SPAWN_BULLET`) still applies unchanged ("3連射は同じ").
    Verified with an emulator sweep holding A for 60 frames: shots
    spawn at frames 0,9,18,27,36,45,54 - a consistent 9-frame period
    (1 fire + 8-frame cooldown). `SHOT_COOLDOWN_FRAMES` was picked
    without an exact spec and is an easy first knob to retune if the
    rate feels off.
  - **Direction lock** ("発射ボタンのAが押されてなくて左右移動なら
    その向きを向くように...まあAボタンは向きのロックだな"):
    `TANK_FACING` only updates in `UPDATE_TANK_XY` when there is
    left/right stick input (`TANK_DX`!=0) *and* A is not held; with no
    movement, or with A held, it simply keeps whatever value it last
    had - so holding A to keep firing in one direction while
    strafing/backing away doesn't spin the tank around mid-volley.
    Verified in the emulator: move left (facing->1) -> hold A + move
    right (facing stays 1, locked) -> release A + move right (facing
    ->0, follows again).
  - Verified visually as well as numerically: rendered frames of the
    tank facing left (gun correctly on the left side, colors on the
    correct swapped quadrants), a straight `BulletF` fired left and
    caught mid-flight to the left of the tank, and a diagonal
    `BulletU` fired while holding up-left (aim-up pose also mirrors,
    shot travels up-and-left) - all composited through the real
    VRAM/sprite pipeline, not just `tank_gen.py`'s standalone bit-grid
    output.
- **Score, tick counter, and a real-hardware color-calibration strip**
  (per direct instruction: "では次はスコアとカウンター Stage1の物を
  そのまま流用 でスコアの横にブランクの0から15のカラーセル表示
  カラーは実機で合わせてるんで実際見ないとわからないんで でその下に
  0からFまでで文字表示 スコアの数字流用とAからFまで新規 背景色は
  ブラックで"):
  - **Score** (row0 cols0-7) and **tick counter** (row0 cols29-31,
    `GAME_TICK`, increments every frame, mod 1000) are ported from
    `src/CYBER SHMUP.asm` essentially unchanged - same 24-bit-aware
    digit-extraction algorithm, same real_score/100-plus-forced-"00"
    trick, same digit glyphs (`DIGIT_PATTERNS_LOCAL`'s 0-9 rows are
    byte-for-byte copies of that file's own `DIGIT_PATTERNS` -
    "スコアの数字流用") ("そのまま流用"). Only the RAM addresses and
    the per-cell VRAM writer changed - this ROM's rows0-1 have no
    `NAMEBUF` (the ground scroller never touches them), so
    `WRITE_HUD_CELL` is a plain single-cell write instead of
    `WRITE_ANIM_CELL`'s NAMEBUF-mirroring version. No kill/enemy
    mechanic exists yet in this test, so `SCORE` is wired to +1 per
    shot fired (`TRY_SPAWN_BULLET` calls `ADD_SCORE`) purely so the
    display has something to exercise - swap for a real scoring event
    once one exists.
  - **Color-calibration strip** (row0 cols8-23, 16 solid cells showing
    palette index 0-15 left to right) with its **hex-label row**
    underneath (row1 cols8-23, "0123456789ABCDEF") - since SCREEN1
    color is fixed per 8-code group, each swatch cell needs its own
    dedicated group (`SWATCH_CODES` places one blank/all-zero-pattern
    code per group, groups15-30; `SWATCH_COLORS` sets each group's
    byte to `(i<<4)|i` so palette index `i` shows regardless of which
    nibble a blank glyph would draw) - between terrain (groups0-10),
    bullets (11-12), digits/hex (13-14), and this strip (15-30), only
    1 of the 32 total SCREEN1 color groups (31) is still free; a
    future feature needing its own color will have to reclaim space
    from here rather than assume there's room to spare. The point of the
    strip is purely that "カラーは実機で合わせてるんで実際見ないと
    わからないんで" - the emulator's palette is only an approximation,
    so this exists to be read directly off a real TV/monitor. The hex
    labels reuse the same 0-9 glyphs as the score/counter plus 6 new
    A-F glyphs (`DIGIT_BASE`=104 covers all 16 in 2 groups,
    104-119) - "AからFまで新規"; background black for both rows
    (`HUD_DIGIT_COLORBYTE`=0F1h, fg15 white/bg1 black, matching
    Stage1's own digit-group color exactly) - "背景色はブラックで".
- **Shot sound** (PSG noise channel A - "で、ショット音追加 ノイズ
  ｃｈで弾発射音ぽいの"): `SOUND_SHOT` (called from
  `TRY_SPAWN_BULLET` alongside the score bump above) kicks channel A's
  noise period and volume; `SOUND_UPDATE` (called every frame from
  `MAINLOOP`) counts `SND_TIMER` down to 0 each frame, writing it
  straight to the volume register so the "shot" fades out on its own -
  same technique as `src/CYBER SHMUP.asm`'s own `SOUND_SHOT`/
  `SOUND_UPDATE`, narrowed to the single channel this test uses (PSG
  mixer register7 reuses that file's own known-good `0B1h`; channels
  B/C volumes are explicitly zeroed at INIT so they stay silent rather
  than depending on undefined power-on register state). Verified in
  the emulator that `SND_TIMER` kicks to `SHOT_SND_FRAMES`(10) on each
  auto-fired shot and decays 1/frame in between - `SHOT_NOISE_PERIOD`
  and `SHOT_SND_FRAMES` were picked with no more precise spec than
  "something shot-sound-like" and are easy first knobs to retune once
  heard on real hardware.
- **Enemy (ZacoII)** (per direct instruction: "では次敵の実装
  スプライトで実装 右から左へスライド Skyのみのの位置に出現
  現状はランダム 地形も合わせてスケジュールエディタで対応予定
  移動は自機位置をみて手前で引き返す 引き返す際の左右反転キャラを
  生成 弾が当たっての爆発はStage1と同じ16x16のスプライト流用
  当たったら100点 敵の管理や制御はStage1を流用"): a pool of 3
  (`enemy_gen.py` converts the supplied `sprites/ZacoII.json`, 16x16,
  same single-hw-sprite quadrant layout as one tank quadrant), fixed
  1:1 onto hw sprite slots4-6 (tank keeps 0-3) - simpler than
  `src/CYBER SHMUP.asm`'s own flexible `ALLOC_SPRITE_NUM`/`E_TYPE`/
  `E_BEHAVIOR` dispatch, appropriate since this test only has the one
  enemy type/behavior. The slot struct (`ENEMY_SLOT_SIZE`=6:
  ACT/X/Y/RETREAT/EXPLODE_TIMER/SPRIDX) mirrors that file's own
  `ENEMY_POOL`/`E_ACT`/`E_X`/`E_Y` idiom, scaled down - no HP field
  either, since "当たったら100点" implies a single hit kills.
  - **Spawn**: right edge (`ENEMY_SPAWNX`=240, fully offscreen -
    "右から左へスライド"), Y confined to a band inside the open sky
    ("Skyのみのの位置に出現"), picked from `TICK`'s low bits masked to
    a power-of-2 span ("現状はランダム" - a placeholder; matching
    spawns to the terrain is deferred - "地形も合わせてスケジュール
    エディタで対応予定").
  - **Movement**: drifts toward `TANK_X`; once within
    `ENEMY_TURNBACK_MARGIN`(40px) it turns back before actually
    reaching the tank ("移動は自機位置をみて手前で引き返す") and
    switches to a mirrored sprite for the retreat
    (`enemy_gen.py`'s own `hflip_bits`, same technique as
    `tank_gen.py`/`bullet_gen.py`'s own flipped poses - "引き返す際の
    左右反転キャラを生成"), despawning once back off the spawn edge.
    Verified in the emulator: a spawned enemy's X decreases from 239
    down to exactly `TANK_X`(40)+40=80 before `RETREAT` flips to 1,
    then X increases back out past 240.
  - **Hit detection** (`CHECK_BULLET_VS_ENEMY`, 3 bullets x 3 enemies,
    unrolled): the same AABB 4-edge-comparison shape as
    `src/CYBER SHMUP.asm`'s own `QUAD_HIT_TEST`, just with the enemy
    side's box widened from 8x8 to 16x16. On a hit: the bullet's cell
    is erased and it's deactivated (factored `ERASE_BULLET_CELL` out
    of `UPDATE_ONE_BULLET` so both that per-frame path and this
    one-off hit path share it), the enemy switches to
    `ACT`=2 (exploding) at its current position, and `SCORE_PER_KILL`
    (=1, i.e. 100 points) is awarded via `ADD_SCORE` - "当たったら
    100点". Verified directly: an overlapping bullet+enemy pair hits
    on the very first `CHECK_BULLET_VS_ENEMY` call (enemy ACT 1->2,
    bullet ACT 1->0, score 0->1); a non-overlapping pair doesn't.
  - **Explosion**: `EXPLOSION_PATTERN`, byte-for-byte from
    `src/CYBER SHMUP.asm`'s own 16x16 sprite of that name (that file's
    *generic* per-enemy-kill explosion is actually a BG-cell animation
    instead, not a sprite - see `TRIGGER_EXPLOSION` - so this reuses
    its pod-destroy-burst sprite art instead, the closer match to
    "16x16のスプライト流用") - shown for `EXPLOSION_DURATION` frames
    on the same hw sprite slot the enemy itself was using, then
    despawned, freeing the slot for a new spawn (see the follow-up
    round below for the drift/duration/sound it since gained).
- **Enemy speed, a red variant, explosion sound + drift** (per direct
  instruction: "スピードが遅いんで早くして 自機と同じ1.5で で、10機
  出たら色替えの赤いZakoII こいつは速度2で アルゴリズムは同じ で
  爆発音追加 Stage1の爆発音流用 合わせて爆発スプライトは8フレ表示
  8方向ランダムに移動後消えるように"):
  - **Speed**: green (normal) `ZacoII` sped up from a flat 1px/frame
    to 1.5, matching the tank's own `TANK_SPEED_LO` trick exactly
    (`ENEMY_GET_STEP` alternates 1/2px on `TICK` bit0) - "自機と同じ
    1.5で". Verified: 30px moved over 20 frames.
  - **Red variant**: `ENEMY_SPAWN_COUNT` (capped at 10, never
    decremented) tracks how many enemies have spawned in total; once
    it's reached 10, every new spawn is the red variant instead of
    green (`ENEMY_RED_COLOR`=9 light red vs `ENEMY_COLOR`=12 green,
    same `ZacoII` art either way - only the sprite color attribute
    differs) at a flat 2px/frame - "10機出たら色替えの赤いZakoII
    こいつは速度2で". Movement/turn-back/hit-detection logic is
    completely shared with the green variant - "アルゴリズムは同じ" -
    `ENEMY_GET_STEP` is the only place the new per-slot `VARIANT`
    field (+6) changes anything, plus the color pick in `UOE_DRAW`.
    Verified: forcing `ENEMY_SPAWN_COUNT`=10 before a respawn produces
    `VARIANT`=1 and exactly 2px/frame movement.
  - **Explosion sound**: `SOUND_DESTROY`, byte-for-byte the same
    period(20)/timer(15) `src/CYBER SHMUP.asm`'s own routine of that
    name uses - "爆発音追加 Stage1の爆発音流用" - but retargeted to
    PSG channel B (`SND_TIMER_B`) instead of reusing the shot sound's
    channel A, since a shot fired right before its own kill would
    otherwise cut its envelope short; mixer register7 tightened from
    `0B1h` to `0E7h` (tones A/B/C off, noise A+B on) to enable it.
    Verified: `SND_TIMER_B` kicks to 15 on a hit and decays 1/frame,
    independent of `SND_TIMER`'s own decay.
  - **Explosion drift**: the explosion no longer just sits still at
    the kill position: `CHECK_HIT_PAIR` picks one of 8 compass
    directions (`EXPLODE_DIR_DX`/`DY`, `TICK`'s low 3 bits) at hit
    time, and `UOE_EXPLODE_DRIFT` adds that (dx,dy) to the enemy
    slot's own X/Y every single frame it's shown (not just on
    trigger - `UPDATE_ONE_ENEMY` runs unconditionally every frame from
    `MAINLOOP` via `UPDATE_ENEMIES`, regardless of `EXPLOSION_DURATION`'s
    length) before despawning - "8方向ランダムに移動後消えるように
    ...で移動中毎フレーム表示だよな". `EXPLOSION_DURATION` itself went
    8 -> 20 (once briefly seen while the DJNZ/B-register corruption bug
    was still silently running the enemy loop the wrong number of times
    per frame - see the Bugs section - "んー２０でいいわ") -> 8 again
    once that bug was actually fixed and 20 read as too long after all
    ("バグってたからか爆発かなり長いわ"), with the drift speed (already
    +-2px/frame the whole time, from `EXPLODE_DIR_DX`/`DY`'s own
    magnitude) explicitly confirmed alongside it this time - "8フレで
    スピードは２ｐｘでいいわ...なので爆発は１６ｐｘ移動だな" (8
    frames x 2px = 16px along a cardinal direction). Getting that exact
    16px took one more fix: `UOE_EXPLODING`'s decrement-then-check
    order meant `E_TIMER`=8 only ever produced 7 actual drift+draw
    calls (the 8th decrement landed on 0 and hid immediately, one call
    short) - swapped to check-then-decrement so all 8 counted frames
    genuinely drift before the 9th call hides it. Verified: a synthetic
    hit with `DX`=0/`DY`=-2 now drifts the enemy's Y by exactly -16px
    (8 x -2) over 8 visible frames before `ACT` returns to 0 on the
    9th, instead of the previous -14px/7-frame result.
  - **Further speed/distance tuning** once actual play was possible
    again (per direct instruction: "ZakoIIはの赤は速度３で...どちらも
    接近しすぎなので４０ｐｘ手前じゃなく６４ｐｘ手前で引き返すこと
    帰る時は倍速で"): `ENEMY_SPEED_RED` 2->3px/frame;
    `ENEMY_TURNBACK_MARGIN` 40->64px (both variants were getting too
    close to the tank before turning back); and `ENEMY_GET_STEP` now
    doubles its result while `E_RETREAT`=1, so the flight home is
    twice as fast as the approach (green 1.5->3px/frame avg, red
    3->6px/frame) instead of the same speed both ways - "帰る時は倍速
    で". Verified: green approaches at 1.5, retreats at 3; red
    approaches at 3, retreats at 6; both now turn back with roughly a
    64px gap from `TANK_X`.
- **Enemy promoted from test scaffolding to a real buffer-managed
  pool** (per direct instruction: "で、敵は仮実装じゃなく出来たら
  本採用 きちんとクラスにしてあるな? 管理もバッファ経由だぞ 個別に
  適当にやるなよ"): the previous round's enemy pool worked correctly
  but was 3 separately-named constants (`ENEMY0_ACT`/`ENEMY1_ACT`/
  `ENEMY2_ACT`) checked/updated by hand-written, individually-unrolled
  code - functionally fine, but not the genuine buffer-plus-loop shape
  `src/CYBER SHMUP.asm`'s own `ENEMY_POOL`/`ALLOC_ENEMY_SLOT`/
  `ENEMY_POOL_UPDATE_ALL` use. Reworked to match that shape exactly,
  intentionally reusing the same names (`ENEMY_POOL`, `E_ACT`/`E_X`/
  `E_Y` field-offset constants replacing bare `IX+0`/`IX+1`/`IX+2`
  everywhere) so this slots into that file's real system later with
  minimal renaming if/when it's actually merged in:
  - `ALLOC_ENEMY_SLOT` (renamed from `ENEMY_TRY_SPAWN`) scans
    `ENEMY_POOL` in an `HL`-indexed `ENEMY_SLOT_SIZE`-stride `DJNZ`
    loop for the first free slot, instead of 3 unrolled `ACT` checks.
  - `UPDATE_ENEMIES`'s `UE_UPDATE_ALL` walks the same buffer calling
    `UPDATE_ONE_ENEMY` on every slot, instead of 3 named `CALL`s -
    `PUSH HL` twice/`POP IX` once (leaving a spare copy on the stack)
    so `HL` survives `UPDATE_ONE_ENEMY`'s own heavy use of it as
    scratch, restored via `POP HL` after - same idiom
    `ENEMY_POOL_UPDATE_ALL` itself uses for the same reason.
  - `CHECK_BULLET_VS_ENEMY` keeps its 3 individually-named bullet-side
    `CALL`s (`BULLET0/1/2_ACT` weren't part of this instruction - it
    said "敵は", the enemy) but factored a new
    `CHECK_HIT_ONE_BULLET` that walks `ENEMY_POOL` the same
    `PUSH HL`-twice way (into `IY` this time) for the enemy side of
    each pair, instead of 3 unrolled `ENEMY0/1/2` checks per bullet.
  - INIT's per-slot zeroing (18 individual `LD (ENEMYn_ACT+k),A` lines)
    became a single generic `ENEMY_SLOT_SIZE*ENEMY_SLOT_COUNT`-byte
    fill loop over the whole buffer, plus a small loop to assign each
    slot's own fixed `E_SPRIDX` (0,1,2) - and likewise for
    `ENEMY_SPRITE_ATTRS`' hidden-`Y`-priming.
  - Purely structural - re-ran every check from the previous round
    against the refactored code and got identical results: all 3
    slots still spawn independently with distinct `E_SPRIDX`; green
    still averages 1.5px/frame and red 2px/frame; turn-back still
    fires at `TANK_X`+40; a hit against slot0 *and* slot2 (not just
    the first slot - confirming the loop actually reaches every slot)
    both still explode/deactivate/award score/kick the sound
    identically to before.
- **Rock/tank red swap** ("カラー変更 Rockの文字色レッドと自機の
  レッドを入れ替えて"): `terrain_gen.py`'s own `ROCK_COLOR` (fg8
  medium red) and `TANK_COLOR_TL` (fg6 dark red, the tank's main body)
  traded fg values - rock is now fg6, the tank's main body now fg8.
  Patched in `combined_test.asm`'s own `INIT` (`ROCK_COLOR_SWAPPED_PATCH`,
  31 bytes covering color groups1-31) rather than editing
  `terrain_gen.py` itself, matching the existing precedent of patching
  specific groups locally rather than changing that shared module (see
  the bullet color patch) - groups11-30 get their own unrelated colors
  patched in right after anyway, so overwriting the whole 1-31 range
  here is harmless. Verified directly against VRAM: color group1
  (and 5, 10 - representative rock groups) all read fg6/bg10, and the
  tank's TL sprite attribute reads color 8.
- Border-color diagnostic checkpoints through INIT (VDP R7), added
  specifically because the tank-only test froze on real hardware with
  no clue where:

  | Border color | Meaning |
  |---|---|
  | (never changes) | Fails before/at cartridge boot |
  | 1 | INIT started, BIOS SCREEN1 setup done |
  | 2 | Terrain patterns + color table loaded |
  | 3 | Whole name table cleared to sky |
  | 4 | Row19 filled, terrain IDCACHEs primed |
  | 5 | 16x16 sprite mode set (VDP R1) |
  | 6 | Tank pattern data loaded |
  | 7 | Tank sprite attributes written |
  | 8 | Score/counter/calibration-strip HUD + PSG set up |
  | 9 | Enemy patterns + pool set up - about to enter MAINLOOP |

  If it freezes again, report which color is showing.
- **SkySand row19** (per direct instruction, across 2 rounds: an
  initial "今イエローで埋めてる下から5行目の上にSkySandで1行埋めて"
  read "above" row19 - the flat rock top, 5th row from the bottom - as
  a brand new row18, then corrected twice: "やっぱSkysandは下から
  ５行目で ブランクセルは削除" and, once a revised source tile arrived,
  "やっぱ６行目は削除 ５行目をこのキャラで埋めて" - row19 itself
  should show SkySand, not a separate row18 above it): row19's own
  static one-time fill (never touched again after INIT, no
  `NAMEBUF`/scrolling involvement - same as always) now shows
  `sprites/SkySand.json`'s dithered sky-to-sand pattern instead of the
  old flat solid-color placeholder tile it used to use
  (`TERRAIN_PATTERN_COUNT`'s own now-unused blank slot, along with the
  `TERRAIN_ROCKY_BLANK` data that filled it, was removed entirely).
  Its own dedicated 2-tone color (fg5 light blue/bg11 light yellow,
  taken directly from the source JSON - unlike the terrain's own
  uniform-`ROCK_COLOR` tiles) needed a whole new color group - placed
  at group31 (codes248-255), the last one still free after terrain/
  bullets/digits/swatch. `ERASE_BULLET_CELL`'s existing row19 case
  (previously restoring the old blank tile) now restores
  `SKYSAND_CODE` instead, for the same reason `BULLET_MIN_ROW` exists -
  a climbing shot passing through would otherwise blank it back to
  plain sky. Verified: row18 reads as plain sky (code 0) and row19
  reads as `SKYSAND_CODE`(248) uniformly across all 32 columns, and
  400 frames of continuous up-fire aimed straight through row19 left
  it byte-for-byte unchanged afterward. The art itself went through 2
  more straight swaps after this ("Skysand差し替え" x2) -
  `SKYSAND_PATTERN`/`sprites/SkySand.json` just get overwritten with
  whatever the latest upload's bits are, no logic changes needed.
- **Sand gets its own dark-yellow-on-light-yellow color** ("でSandの
  文字色をダークイエローに", corrected once seen to "文字色ダーク
  イエロー、背景色ライトイエロー" - fg10/bg11, not fg10/bg10 as an
  earlier round mistakenly used): `terrain_gen.py`'s `BLANK_CODE`
  (Sand's steady tile) and, after 2 flicker rounds, every pair
  involving it, moved out of the shared rock color group into their
  own dedicated ones (`SAND_GROUPS` - see that file's own README entry
  for the full story, including why 1 group turned out not to be
  enough). That broke this file's own `ROCK_COLOR_SWAPPED_PATCH` from
  the color-swap round, which blindly overwrote the *entire*
  groups1-31 range - narrowed to skip `SAND_GROUPS` (group1 alone,
  then groups5-31, once `SAND_GROUPS` grew to 2-4). Verified directly
  against VRAM: groups2-4 all read `SAND_COLOR` (0xAB) while groups1/5/
  10 (genuinely rock-colored) still read the swapped `0x6A`.
- **SkySand moved to row18, row19 now plain Sand** ("今の下から5行目の
  Skysandを1行上に 空いた下から5行目にSand埋め"): `TERRAIN_ROW_SKYSAND`
  moved to 1A40h (row18); a new `TERRAIN_ROW_SAND` (32 x
  `TERRAIN_BLANK_CODE` - a new symbol `terrain_gen.py` now exports,
  reusing the scrolling terrain's own BLANK code/color, no new group
  needed) fills row19 at 1A60h. `ERASE_BULLET_CELL` now restores
  SkySand on row18 and Sand on row19. Also fixed in passing:
  `BULLET_ROCK_COLORBYTE` was still `01Ah` (bg10) from before
  `ROCK_COLOR` moved to bg11 - corrected to `01Bh`.
- **Bullet's own color stays blue over rows18-19** ("Skysandとその下の
  Sandは...背景色ブルーのままでいい...背景色イエローでやると明るい色
  なので余計に目立つ"): split the erase-boundary constant
  (`BULLET_ROCK_ROW_MIN`=18, unchanged) from the draw-color one, and
  further split *that* by shot type - a first pass shared one new
  threshold(20) between F and U, which the user hadn't asked for
  ("斜めだけって言っただろうが なんで水平ショットも変えた 水平は前に
  戻せ" - F never visits rows18-19 in normal flight, but can during a
  jump, so sharing the constant was a real behavior change, not just
  unnecessary code). Split into `BULLET_ROCK_COLOR_ROW_MIN_F`(19, back
  to its original pre-this-saga value) and `_U`(20, the new blue-over-
  18-19 rule) - `DRAW_BULLET_CELL` now picks the threshold from
  TYPE(IX+1) before comparing. Verified against actual VRAM codes,
  including a forced mid-jump F shot at row17-19 to exercise the
  boundary F normally never reaches.
- **Bullets now stop at Rock225** ("ショットは地形貫通しない 今は
  Rock225だけなんで当たったら弾は消す"): `UPDATE_ONE_BULLET`, right
  before drawing at its newly-advanced position, checks rows20-23
  against `IDCACHE_T0..T3` (same id>=3 test and same column-indexed/
  48-byte-spaced lookup `UPDATE_TERRAIN_COLLISION` already uses for
  the tank's own ground probe) and deactivates the bullet instead of
  drawing if it landed on a Rock225 id (3-6) - no score, no explosion,
  just gone, same as flying off-screen. Plain Rock/Sand still let
  shots through. Verified directly (forcing `IDCACHE_T0` to each id at
  a bullet's next column): Rock225 ids deactivate, Rock/Sand ids don't.
- **Sand widened to 3 rows, SkySand pushed up 2 more rows** ("下から
  7,8行目をSandで埋めてその上にSkysand、2行上げる" - Sand expands from
  1 row to 3, SkySand moves 2 rows higher to sit just above it): Sand
  now fills rows17-19 (was just row19), SkySand moved from row18 to
  row16 (all still static, written once at INIT, same
  `TERRAIN_BLANK_CODE`/`SKYSAND_CODE` tiles as before - no new art or
  color groups). `BULLET_ROCK_ROW_MIN` 18->16;
  `ERASE_BULLET_CELL` widened from a 2-row (18/19) branch to a 4-row
  (16 SkySand / 17-19 Sand) one, row>=20 still skipped (rows20-23 stay
  NAMEBUF-redrawn). `BULLET_ROCK_COLOR_ROW_MIN_F/_U` (bullet's own
  draw color threshold) left untouched in this round - see the bug
  entry below for the follow-up that fixed. Verified: INIT-time VRAM
  dump shows row16=248(SkySand) uniformly, rows17-19=16(Sand)
  uniformly, stable over 400 idle frames; a synthetic
  `ERASE_BULLET_CELL` call at each row14-21 restores
  sky/SkySand/Sand/skip exactly as expected.
- **F shot's own boundary retuned after the Sand widening, and U now
  skips drawing over SkySand's own row** ("弾の描画がおかしい 水平打ち
  での弾の背景色はライトイエローなのにブルーになってる 行を増やした
  影響かもな / で、斜め打ちはSkysandと重なった時弾の表示はスキップに
  Skysandより上に弾が行くと背景色ブルーの現在の弾を表示に"): see the
  Bugs section below for the F fix, and the change list entry
  immediately above this one for what triggered it. New: diagonal/U
  shots no longer draw at all while their row equals
  `BULLET_ROCK_ROW_MIN`(16, SkySand's own row) - `UPDATE_ONE_BULLET`'s
  `UOB_DRAW` skips the `DRAW_BULLET_CELL` call for TYPE=U at that one
  row (F unaffected), leaving whatever's already there (SkySand,
  correctly restored by that same frame's earlier `ERASE_BULLET_CELL`
  call on the old position) untouched; rows above 16 (plain sky) still
  draw the normal blue-bg bullet as before, and rows17-19 (Sand) are
  unaffected by this - still blue per the earlier "Skysandとその下の
  Sandは...背景色ブルーのままでいい" instruction. Verified with a
  synthetic `UPDATE_ONE_BULLET` call sequence: a U bullet advancing
  from row17 into row16 leaves row16's cell reading `SKYSAND_CODE`
  (untouched) instead of a bullet pattern code, then on the next call
  advances into row15 and draws `BULLETU_SKY_CODE` there normally.
- **U's "stays blue over Sand" rule reversed - now matches F** ("斜め
  打ちでSand埋め通過時も背景色がブルーになってるな これもライトイエ
  ローに"): supersedes the earlier "Skysandとその下のSandは...背景色
  ブルーのままでいい" instruction, now that Sand is its own 3-row band
  distinct from SkySand (which U skips drawing over entirely, per the
  entry above, so it was never actually asking about that row).
  `BULLET_ROCK_COLOR_ROW_MIN_U` 20->17, same value as F's own
  boundary - U now shows rock/yellow across rows17-19 (Sand) and
  20-23 (terrain) alike, blue only above row17. Verified: synthetic
  `DRAW_BULLET_CELL` calls for TYPE=U show sky-code through row16,
  rock-code from row17 on; the row16 SkySand skip-draw behavior itself
  is unchanged (that check runs before this color logic).
- **Flowing background clouds, 6 rows** ("Stage1でもやってる雲を上から
  3行目に4セルの雲をランダムタイミングで 4行目はから8行目まで2セルと
  4セル雲をランダムに各行で速度変化をつけて 3から5行目は最速の毎フレ
  ーム1セル移動 5から8行目は半速の2フレで1セル" - the overlapping
  "5行目" between the two speed ranges confirmed as the fast side, i.e.
  rows3-5(top) fast / rows6-8(top) half-speed, not a 4-way split):
  `CLOUD_POOL`, 6 slots (screen rows2-7, the 3rd-8th row from the top),
  buffer+DJNZ-loop driven like `ENEMY_POOL` rather than 6 individually-
  unrolled instances - each slot fixed at INIT to its own ROW (2-7),
  INTERVAL (1=every frame for rows2-4, 2=every other frame for
  rows5-7) and FIXED4 (row2's cloud is always 4-cell wide; rows3-7
  randomly pick 2 or 4 at each spawn via a new shared `CLOUD_RNG`
  counter, same idle/wait/move/erase-redraw shape as `src/CYBER
  SHMUP.asm`'s own `CLOUDW_UPDATE`/`CLOUDN_UPDATE`, generalized instead
  of duplicated). Reuses that file's own 2-tile WA/WB cloud glyph pair
  byte-for-byte ("Stage1でもやってる雲を"), placed at codes1-2 -
  genuinely unused slots within group0 (`SKY_BLANK_CODE`=0 is group0's
  only real occupant; terrain_gen.py never emits codes1-7 at all) - no
  new color group needed even though all 32 were already spoken for
  (see the color-strip entry's own note that only 1 was ever free, and
  that one's since gone to SkySand). Group0's color moved from sky-on-
  sky(0x55) to white-on-sky-blue(0xF5) for the clouds; see the Bugs
  section below for why `SKY_BLANK_CODE` itself needed a follow-up
  patch once that color changed. Verified over a 4000-frame run: cloud
  rows2-7 only ever contain codes0/1/2 (no stray leftovers from
  erase/deactivate), a synthetic same-frame-spawn test confirms the
  fast/half-speed rows move at exactly 20px/10px over 20 frames (2:1,
  matching "毎フレーム1セル" vs "2フレで1セル"), and score/HUD/
  SkySand/Sand/terrain content is all unaffected (no B/C-register
  corruption from the new DJNZ loop - the CALL inside it is PUSH BC/
  POP BC-guarded per the established precaution).
- **Both cloud speed bands halved again** ("んー早すぎかもな 3から8行
  目までどちらも更に半速で 3から5が2フレごと 6から8が4フレごとだな"):
  `CLOUD_INTERVAL_TABLE` 1,1,1,2,2,2 -> 2,2,2,4,4,4 - not just the
  already-slow band, both. Verified: a synthetic same-frame-spawn test
  (rows3/8-from-top) moves 20px/10px over 40 frames at the new
  intervals, same 2:1 ratio as before just at half the absolute speed.
- **Slow band retuned again, 4->3 frames/cell** ("4フレはガタが目立
  つんで3フレで 中途半端だが仕方ない" - accepted as an odd ratio, not
  a clean 2:1 against the fast band's 2 anymore): `CLOUD_INTERVAL_TABLE`
  ...,4,4,4 -> ...,3,3,3; rows3-5's own 2 untouched (only the slow band
  was reported as choppy). Verified: 60-frame synthetic run moves
  30px(fast, interval2)/20px(slow, interval3).
- **Diagonal/U shot moved to a hardware sprite; F unchanged** ("弾は
  斜めのみスプライトに変更 水平は今のままで 伴って斜めうちのBG関係
  の弾の処理は削除 Skysandのスキップも廃止"): U no longer draws as a
  BG name-table character at all - `bullet_gen.py`'s `BULLET_U_SPRITE`/
  `_L` embed the same 8x8 BulletU art at the top-left of an otherwise-
  blank 16x16 sprite canvas (VDP already runs in 16x16 mode for the
  tank/enemies), loaded at `PAT_BULLETU`(140)/`PAT_BULLETU_L`(144),
  fixed 1:1 onto hw sprite slots7-9 (`BULLET_U_SPR_BASE_SLOT`, right
  after the enemy pool's 4-6) - same "build in RAM, blast once"
  staging-buffer pattern as `ENEMY_SPRITE_ATTRS`/`FLUSH_ENEMY_SPRITES`,
  new `UPDATE_BULLET_U_SPRITES`/`FLUSH_BULLET_U_SPRITES`. Position
  (Y=ROW*8,X=COL*8) comes straight from the existing bullet-pool ROW/
  COL bookkeeping - unchanged movement/collision math, only the render
  backend changed. Removed along with it: every U-specific branch in
  `DRAW_BULLET_CELL` (now F-only, considerably shorter),
  `BULLETU_SKY/ROCK_CODE`+`_L` pattern-code constants,
  `BULLET_ROCK_COLOR_ROW_MIN_U`, and the SkySand row16 skip-draw
  special case in `UOB_DRAW` - a hw sprite composites over whatever's
  already there automatically, so there was nothing left to special-
  case. `ERASE_BULLET_CELL` (still needed for F, which can still visit
  rows16-19 during a jump) and `CHECK_HIT_PAIR`'s own erase-on-hit call
  are now both TYPE-guarded (F only) - a U-type slot never had anything
  drawn in the name table to erase, so calling it unconditionally would
  have stomped whatever's actually there (a cloud, Sand, sky) with a
  bogus "restore". Verified: a synthetic `UPDATE_ONE_BULLET` sweep with
  rows2-19 pre-filled with a sentinel byte shows zero BG writes from a
  6-frame U bullet flight; F's own BG draw/erase is bit-for-bit
  unchanged; a synthetic hit test confirms score/enemy-explode still
  fire correctly and the U sprite hides (Y=209) the same frame as the
  hit, not one frame late.
- **`render_check.py`'s sprite renderer stopped early on the wrong Y
  value** (caught while trying to visually verify the new bullet
  sprite, not a hardware report): its sprite loop broke out entirely
  the moment it saw `Y==0xD1`(209, this ROM's own "hidden" convention -
  `INIT_SPRATR_CLR`/`UOE_HIDE`/the new `UBUS_HIDE` all use it), instead
  of only skipping that one slot - harmless while nothing occupied hw
  sprite slots past the enemy pool's own sometimes-209 slots4-6, but
  once the new bullet sprites landed at slots7-9 right after them, an
  inactive enemy slot silently hid every later sprite from the preview
  (though not from the real VRAM/hardware sprite table, confirmed by
  reading it directly). Real VDP semantics: Y=208 is the actual early-
  terminator, any other Y>=208 just hides that one sprite. Fixed:
  break only on `y==208`, `continue` (skip, don't stop) for `y>=208`
  otherwise. Verified: re-rendering the same scene now shows both the
  tank's gun-up pose and 2 small diagonal bullet marks in flight.
- **BulletF art replaced, spawn row +1->+2 to align with the tank's
  actual gun muzzle** (new `sprites/BulletF.json` supplied directly -
  the chevron moved from the bottom of its 8x8 cell to the top;
  "BalletFを1セル下に描画 今のままだと16x16の敵を出すと当たらないと
  思うんで...(垂直位置が)狂うんで...自機の下から8ドット上に描画と
  判定が来ないと...表示と判定を一致させるため...自キャラの絵は銃が
  描かれてるがその銃口に合わせる意味もある 今は1,2pxズレてるしな"):
  with the new art's content starting right at its cell's own top row
  (no more in-cell offset, unlike the old art's rows5-7), keeping the
  spawn row at the old +1 would land the visible bullet 7-8px *above*
  where it should be - widened to +2 instead. Cross-checked against 2
  independent derivations rather than guessed: measuring `TankF.json`'s
  own gun-barrel tip directly (rows10-13, centered ~row11-12) puts the
  muzzle at TANK_Y_CUR+~11-12px; `TANK_Y_CUR>>3+2` (156 base tier) =
  row21 = pixel168, landing within ~1px of that measurement - both
  agree, and both close the previous ~2px gap the user had already
  measured on real hardware rather than making it worse. Since F's
  hitbox uses the same ROW value the visible draw does (`CHECK_HIT_PAIR`
  reads straight from the bullet slot's own ROW/COL), this also fixes
  the display/hit-test mismatch that made hits against a 16x16 enemy
  positioned at the muzzle's own height unreliable - "表示と判定を
  一致させるため". Verified: rendered close-up shows the new chevron
  sitting right at the gun's own muzzle tip; a synthetic hit test with
  an enemy box placed at the bullet's exact spawn pixel now registers;
  4000-frame zero-input sweep still shows no score drift.
- **Zum, a ground-based enemy** (per direct instruction, confirmed in
  2 follow-up rounds: "では敵を追加する 赤ZakoIIが10体で終わったら
  地形右から登場 もちろん地形は避けること 地面に設置してること 上り
  下り出来ること 自機と同じだね で上りがない地形最下部でスポーン
  速度は1で自機に64pxまで近づくと速度2で自機に突っ込んでくる お互い
  貫通せず止まること つまり何も操作しなければ敵に押される 自機が
  ジャンプで避けるとそのまま左に消える 正面からは無敵で弾は止まる
  こと 破壊条件は後ろから撃たれた場合のみ" - ZacoII keeps spawning
  unaffected ("ZakoIIは継続、Zumが追加で登場"), pool capped at 2
  concurrent ("横並び制限があるんで")): `ZUM_POOL`, `sprites/Zum.json`
  converted via `enemy_gen.py` (added to its `ENEMIES` list alongside
  ZacoII - no flip needed, Zum never reverses direction), own hw
  sprite slots10-11 and pattern group148.
  - **Spawn gate** (`ALLOC_ZUM_SLOT`): 3 conditions, all must hold -
    `ENEMY_SPAWN_COUNT>=10` (reuses the *existing* red-ZacoII
    threshold rather than a new counter), a free pool slot, and
    `ZUM_TERRAIN_OK` - the terrain at a fixed spawn column (30, under
    `ZUM_SPAWNX`=240) must read as genuinely flat ground at the lowest
    tier (IDCACHE_T0-T2 all BLANK there, IDCACHE_T3 a steady plain-rock
    id, not a Rock225 climb/descend marker) - "上りがない地形最下部で
    スポーン". Any failed condition just retries next frame rather
    than waiting a fixed interval, since the terrain condition is
    transient (the track scrolls continuously, so polling catches the
    next flat window as soon as it scrolls into place).
  - **Ground-following** ("地面に設置してること 上り下り出来ること
    自機と同じだね"): reuses the same idea as
    `UPDATE_TERRAIN_COLLISION` (probe IDCACHE_T0-T3 at its own column
    for the first non-BLANK tier, ease Z_Y toward
    `TANK_TIER_Y_TABLE[tier]` - the same table the tank's own Y
    targets) but *without* that routine's own hard-won catch-up-
    threshold refinements (born from a long tuning saga - see that
    routine's own comment) - just a flat `ZUM_CLIMB_SPEED`(2)px/frame
    ease, clamped at the target. A deliberate simplification, not a
    re-derivation of that tuning; easy to revisit if it reads as
    jittery/laggy once actually seen on real hardware.
  - **Speed/charge**: `ZUM_SPEED_SLOW`(1) normally, `ZUM_SPEED_FAST`(2)
    once within `ZUM_CHARGE_MARGIN`(64px) of `TANK_X` - "速度は1で
    自機に64pxまで近づくと速度2で自機に突っ込んでくる". The distance
    check is a plain unsigned subtraction (`Z_X-TANK_X`) with no
    special-casing for "Zum has already passed the tank" - if `Z_X <
    TANK_X` the subtraction wraps to a large value, which the
    threshold compare naturally reads as "far" (falls back to speed1)
    without any extra branch.
  - **Push collision** (`UPDATE_TANK_ZUM_PUSH`, new MAINLOOP step
    after `UPDATE_ZUM_ALL`): "お互い貫通せず止まること つまり何も
    操作しなければ敵に押される" - Zum's own X always advances at its
    own pace regardless of the tank; contact instead clamps
    `TANK_X = min(TANK_X, Z_X-TANK_PUSH_WIDTH)`, so a stationary
    player gets shoved left as Zum keeps advancing, while the player
    can still freely move away (just never *into* an active Zum).
    Entirely suspended while `JUMP_ACTIVE`=1 - "自機がジャンプで避け
    るとそのまま左に消える" - letting Zum slide underneath and
    continue off the left edge uninterrupted. Runs after the tank's
    own `UPDATE_TERRAIN_COLLISION`/`UPDATE_TANK_SPRITES` already used
    this frame's *pre*-push `TANK_X`, so a push visually lands 1 frame
    later than the contact itself - accepted as a minor lag, same
    class as every other post-tank-sprite system in this MAINLOOP
    (enemies, clouds, bullet-U sprites).
  - **Front/rear hit direction** (`CHECK_BULLET_VS_ZUM`/
    `CHECK_HIT_PAIR_ZUM`): "正面からは無敵で弾は止まること 破壊条件
    は後ろから撃たれた場合のみ". Same AABB overlap shape as
    `CHECK_HIT_PAIR` (bullet 8x8 vs enemy box widened to 15), plus a
    2nd check against Zum's own horizontal midpoint (`Z_X+8`) once
    overlap is confirmed - since Zum only ever moves left, its own
    left half is permanently its "front" (bullet absorbed: deactivated
    with no score/explosion/sound, same as flying off-screen) and its
    right half permanently its "back" (bullet kills it: same explosion/
    score/sound as a ZacoII kill), independent of which direction the
    bullet itself was travelling.
  - **Explosion**: reuses `EXPLOSION_PATTERN`/`EXPLOSION_COLOR`/
    `EXPLOSION_DURATION`/`SOUND_DESTROY`/`SCORE_PER_KILL` unchanged -
    not explicitly specified for Zum, so matched to ZacoII's own for
    consistency rather than invented from nothing; easy to split out
    a distinct value if that turns out wrong.
  - Verified: `ALLOC_ZUM_SLOT` correctly refuses to spawn below the
    count threshold and during a forced climb-marker terrain state,
    then spawns the instant both clear; speed reads 1 far away, 2 once
    within 64px, and correctly falls back to 1 once past the tank
    (wraparound case); `UOZ_TERRAIN_FOLLOW` eases toward each tier's Y
    and clamps without overshoot; the push clamp holds `TANK_X` exactly
    `TANK_PUSH_WIDTH`(32) behind an approaching Zum and is fully
    inert while `JUMP_ACTIVE`=1 (confirmed visually too - a forced
    encounter shows the tank pinned 32px behind Zum when not jumping,
    and Zum sailing straight through to X34 with `TANK_X` completely
    unchanged when jumping the whole time); a front-half hit
    deactivates the bullet with the Zum and score untouched, a
    rear-half hit at the same encounter destroys it and awards score;
    an 8000-frame varied-input stress run (movement/fire/jump cycling)
    shows no score drift and `TANK_X` staying in-bounds throughout.
- **3 Zum fixes from real testing** ("さっきのスクショでもだが地面に
  設置してないな 16px上に浮いてる で速度1だと地面と動悸してるんで
  速度1.5 加速時3で でZumと接触状態でジャンプすると自機がワープして
  しまう"):
  - **Floating 16px above the ground**: `TANK_TIER_Y_TABLE` gives the
    *tank's* own top-anchor Y for a 32px-tall sprite; Zum is only
    16px tall, so using that value directly for its own top-Y left its
    bottom 16px short of the ground line. Fixed with `ZUM_Y_OFFSET`(16)
    added both in `UOZ_TERRAIN_FOLLOW`'s target and `ALLOC_ZUM_SLOT`'s
    own spawn Y, aligning Zum's bottom with the tank's.
  - **Speed retuned**: slow speed now averages 1.5 (`ZUM_SPEED_SLOW_BASE`
    alternating with +1 on odd `TICK` frames, same trick as
    `TANK_SPEED_LO`/`ENEMY_GET_STEP`'s own green-variant 1.5 - matches
    the same "flat integer speed looks like it's fighting the terrain
    scroll" concern those already solved), was a flat 1. Charge speed
    `ZUM_SPEED_FAST` 2->3 flat.
  - **Tank teleporting when jumping while in contact**: `UPDATE_TANK_
    ZUM_PUSH`'s clamp was an unconditional snap to `Zum_X-TANK_PUSH_
    WIDTH` - harmless frame-to-frame during ordinary continuous
    contact (never more than one frame's worth of Zum movement to
    close), but the push is fully suspended for a jump's ~49 frames
    while Zum keeps moving the whole time; landing with a large
    accumulated gap snapped it shut in a single frame, reading as a
    teleport. Fixed with `ZUM_PUSH_SPEED`(3) rate-limiting the clamp -
    closes at most that many px/call, snapping only the final
    sub-`ZUM_PUSH_SPEED` remainder directly (no overshoot). Verified:
    a synthetic 22px gap (simulating a Zum that sailed past during a
    jump) closes 3px/call over 8 calls then a 1px remainder, never a
    single jump bigger than `ZUM_PUSH_SPEED`; ordinary continuous
    contact still resolves in one call per frame as before, since it
    never needs to close more than `ZUM_SPEED_FAST`'s own 3px/frame.
- **Ground offset overcorrected - now 5-6px sunk in, seen on real
  hardware** ("さっきのスクショでもだが見えにくいが今度は5,6Px地面に
  埋まってるな"): the full geometric `ZUM_Y_OFFSET`(16, exactly the
  tank/Zum sprite-height difference) overshot, because Zum's own art
  tapers off before its 16th row (see `sprites/Zum.json`) - its real
  visible bottom sits a few px higher within its canvas than the full
  height assumes. Backed off to 10 (16 minus the ~5-6px reported); an
  estimate like the tank's own empirically-tuned landing offset
  (`TANK_Y_BASE`'s own comment), not a re-derived formula - ready to
  nudge further either way if still off. Separately: pushing *into* an
  active Zum overlaps it instead of being blocked (the push clamp
  above only prevents Zum from advancing past the tank, not the other
  direction) - left as-is per direct instruction ("めり込みはこの
  ままでいいわ オモロイから" - the overlap reads as funny, not a bug
  to fix).
- **Zum "vanishing" once the tank pushed through it, and the push
  ignoring the player's own movement** ("めり込みでそのまま通過すると
  Zumは消えてしまってる で、...自機の移動量を考慮してないな"):
  `UPDATE_TANK_ZUM_PUSH`'s clamp kept firing even after `TANK_X`
  reached/passed the Zum's own X (moving right through the allowed
  overlap) - it doesn't distinguish "Zum still ahead, blocking" from
  "already passed", so it kept dragging `TANK_X` backward to chase the
  Zum's own (still-decreasing) X. Reproduced directly: holding right
  the entire time, `TANK_X` actually *decreased* from 59 to 35 over 20
  frames instead of climbing - the tank got towed along right up until
  Zum reached its own normal despawn point, reading as "Zum vanished
  right in front of the tank" when it was really just despawning
  on schedule while the tank was wrongly glued to it. Fixed by skipping
  a Zum entirely once `TANK_X>=Zum_X` (no longer ahead of the tank, so
  the block/push no longer applies) - the pre-pass-through overlap
  itself (still explicitly wanted, see the entry above) is unaffected,
  since that guard only trips *after* the tank's own X reaches the
  Zum's. Verified: the same 20-frame held-right reproduction now shows
  `TANK_X` climbing again (36->41->42) the moment it passes the Zum's
  X instead of continuing to fall; the existing approach/jump-suspend/
  rate-limited-close cases were re-checked and are all unaffected.
- **Cloud rows cut from 6 to 2, as a slowdown-diagnosis experiment**
  ("で、かなり速度落ちてるな 雲追加が原因かもな 5から8行目は削除して
  みてくれ 遅くなった原因は雲かどうか分からんが" - this MAINLOOP has
  no vsync/HALT pacing at all, so any extra per-frame work directly
  slows the whole game's real-time pace, and clouds run unconditionally
  every frame regardless of whether one's actually on screen):
  `CLOUD_SLOT_COUNT` 6->2, `CLOUD_ROW_TABLE`/`CLOUD_INTERVAL_TABLE`/
  `CLOUD_FIXED4_TABLE` trimmed to just rows2-3 (3rd-4th from the top;
  the removed rows5-8-from-top were screen rows4-7). Explicitly a
  test, not a confirmed diagnosis - the report itself said as much.
  Verified: rows4-7 stay pure sky (code0) over a 3000-frame run, no
  stray codes; rows2-3 still show clouds normally; everything else
  (score/HUD/terrain/bullets/Zum) unaffected.
- **Cloud-row experiment ruled out, restored to all 6** ("雲減らして
  も変わらんな そんなに処理増えてないはずだが"): the cut above made
  no difference to the reported real-hardware slowdown, so
  `CLOUD_SLOT_COUNT`/`CLOUD_ROW_TABLE`/`CLOUD_INTERVAL_TABLE`/
  `CLOUD_FIXED4_TABLE` are all back to their pre-experiment values
  (rows2-7, matching the earlier cloud-feature entries above). Clouds
  are ruled out as the cause; the real slowdown source is still open.
- **Zum front/back hit test could be cheesed at point-blank range**
  ("でZum貫通中にショット撃ってると背中に当たって倒してしまう"): the
  previous front/back split compared the *bullet's own* pixel X
  against Zum's midpoint - but the muzzle spawns at `TANK_X`+~24, so
  while pushing forward into the still-allowed overlap (still
  approaching from the front - see the earlier "めり込みはこのまま
  でいいわ" entry - not yet actually behind it), a bullet could
  already spawn past that midpoint purely from being at point-blank
  range, letting a shot register as a rear kill without the player
  ever genuinely maneuvering around Zum. Fixed by switching the test to
  the *tank's own* position - `TANK_X>=Zum_X`, the exact same "already
  passed" criterion `UPDATE_TANK_ZUM_PUSH` uses - so only a shot fired
  after actually getting behind Zum (not just standing close to it)
  counts as rear. Verified: a bullet landing on Zum's rear half by pure
  pixel math, fired while `TANK_X` is still in front of Zum, is now
  correctly absorbed (front) rather than killing it; a shot fired once
  `TANK_X` has genuinely passed Zum's own X still kills it regardless
  of which half the bullet's own pixel lands on.
- **Cloud rows cut for real this time, and 2 more real-hardware Zum/
  jump fixes** ("んー 雲は6から8行目は削除していいわ で、Zumにジャンプ
  で乗っかるとめり込んでくな ここはめり込まないように で、違和感ある
  のがジャンプ ふわっと浮いて降りてるんよな...ジャンプLutのステップ
  いじって速度の方をいじるしかないかもな"):
  - **Clouds**: `CLOUD_SLOT_COUNT` 6->3, keeping only the fast band
    (rows2-4, 3rd-5th from top) and permanently dropping the half-speed
    one (rows5-7, 6th-8th from top) this time - not an experiment, a
    direct instruction. Verified: rows5-7 stay pure sky over a
    3000-frame run.
  - **Zum landing-on-top**: new `UPDATE_TANK_ZUM_STAND`, called right
    after `UPDATE_JUMP` (so the same frame's sprite draw reflects it)
    and only while `JUMP_ACTIVE`=1 (grounded overlap stays the
    horizontal push's own job, unaffected) - clamps `TANK_Y_CUR` so the
    tank's own bottom never sinks below an overlapping Zum's own top
    surface, landing on top of it instead of sinking through mid-jump.
    Verified: with a Zum held fixed directly under the tank through a
    whole jump, `TANK_Y_CUR` reaches and holds at exactly the Zum's-top
    minus tank-height value for every frame the jump arc would
    otherwise have sunk it lower, instead of continuing past it; the 4
    guard conditions (overlapping+jumping+would-sink -> clamps;
    overlapping+jumping+still-clear -> untouched;
    overlapping+not-jumping -> untouched, unrelated to the horizontal
    push; jumping+no-horizontal-overlap -> untouched) all individually
    confirmed.
  - **Jump sped up**: `JUMP_FRAMES` 49->33, `JUMP_OFFSET_TABLE`
    regenerated with the same half-sine formula/24px peak
    (`round(24*sin(pi*t/32))` for t=0..32) just over fewer steps - a
    first guess at "ジャンプLutのステップいじって速度の方をいじる",
    not a re-derivation of a specific target duration/curve shape.
    Verified: the jump now completes (peaks at the same 24px, eases in/
    out the same way) in 32 frames instead of 48.
- **Zum despawned well short of the left edge** ("Zumが画面左まで行った
  際にかなり手前で止まってそのまま消えてる 左端まで到達してないぞ"):
  `ZUM_DESPAWN_MARGIN`(32) was a fixed stand-in for "close enough to
  the edge, and conveniently keeps `UPDATE_TANK_ZUM_PUSH`'s own
  `Zum_X-TANK_PUSH_WIDTH` from underflowing" - Zum was disappearing a
  visible 32px before actually reaching X=0. Removed the fixed margin;
  `UPDATE_ONE_ZUM` now only despawns once its own X can no longer
  subtract this frame's speed without underflowing (checked right
  where the speed is already known, in `UOZ_MOVE`), so it rides all
  the way down to X=0/1 before disappearing instead of stopping short.
  `UPDATE_TANK_ZUM_PUSH`'s own underflow safety no longer depends on
  the removed margin either - its existing `TANK_X>=Zum_X` "already
  passed" skip (see the earlier fix above) alone guarantees
  `Zum_X>TANK_X>=0` whenever it actually reaches that subtraction.
  Verified: a Zum moving at the slow/averaged speed now reaches X=1
  before despawning next frame (previously stopped at 32); the push
  clamp produces no bogus/wrapped `TANK_X` value in either a
  Zum-already-passed or Zum-still-approaching scenario right at the
  edge (X=1).
- **Coming down off a standing-on-Zum position snapped instantly**
  ("乗っかりから降りる時の速度が速すぎてワープにみえる ここもサイン
  Lut使わないとだな 自然に見せるには乗っかったらサインジャンプ前半
  16px相当をスキップしてオートジャンプかな"): the jump's own fixed
  33-frame timer kept advancing underneath `UPDATE_TANK_ZUM_STAND`'s
  clamp even while parked, so once it ran out (`JUMP_ACTIVE`->0),
  `TANK_Y_CUR` reverted straight to `TANK_GROUND_Y` (offset 0) in a
  single frame - a real snap from the parked height, not just a visual
  impression. New `TANK_ZUM_STANDING` (set by `UPDATE_TANK_ZUM_STAND`
  whenever it actually clamped that call, read by `UPDATE_JUMP` the
  following frame): if the jump would end while this is still set,
  `UPDATE_JUMP` restarts `JUMP_FRAME` at `JUMP_LANDING_RESTART_FRAME`
  (16, `JUMP_OFFSET_TABLE`'s own peak/24px index) instead of ending -
  auto-playing just the falling half of the same sine curve back down
  to ground, matching the suggested "skip the first half, auto-jump"
  design. While genuinely still standing this cycles harmlessly
  (the clamp keeps overriding the replayed curve's own value the whole
  time, restarting again every ~17 frames); once the Zum actually
  moves out from under or the player steps off, whatever point the
  cycle happens to be at lands smoothly. `TANK_ZUM_STANDING` inits to 0
  at boot. Verified: held fixed under a Zum, `TANK_Y_CUR` stays parked
  and `JUMP_FRAME` visibly restarts at 16 instead of `JUMP_ACTIVE`
  dropping to 0; releasing the Zum mid-cycle shows `TANK_Y_CUR` easing
  down 1-3px/frame over ~11 frames instead of jumping straight to
  ground in one; an ordinary jump with no Zum involved still ends
  cleanly after the normal 32 frames, unaffected.
- **`ZUM_Y_OFFSET` replaced with a geometric derivation instead of a
  visually-tuned fudge** ("乗っかった時に自機とZumの間に隙間が出来て
  不自然だな 5,6Px下だな 多分Zumをオフセットしたからだろう そもそも
  このオフセットは必要ないからな 位置だけ一致させると判定が狂って
  しまう原因になる 地形1番下の高さは8px Zumは16px 8px上にスプライト
  を出せば自然に設置するはず"): the previous +10 (before that, +16)
  was tuned purely to make Zum's *visible* bottom line up with the
  ground on real hardware - but every Zum-related hit/collision check
  (`UOZ_TERRAIN_FOLLOW`'s own target, the push-block height reference,
  the stand-on-top clamp, `CHECK_HIT_PAIR_ZUM`'s Y-based AABB) reads
  straight from that same value, so a fudge tuned for one visual case
  (grounded walking) skewed the geometry for another (standing on top,
  where the gap was reported). Replaced with a plain derivation: one
  terrain tier step is 8px, Zum is exactly 2 steps (16px) tall, so its
  own top-Y is the tank's own tier-Y minus 8 (`SUB`, not `ADD`, in both
  `ALLOC_ZUM_SLOT`'s spawn Y and `UOZ_TERRAIN_FOLLOW`'s per-frame
  target) - not re-tuned to visually match anything, per direct
  instruction that doing so was the actual root cause. Verified
  mechanically: spawn Y now reads 148 (156-8) for the base tier,
  matching the formula exactly; existing push-block/stand/hit-test
  behavior all still function correctly against the new value (no
  logic elsewhere assumed a particular magnitude). Real-hardware
  appearance not independently re-confirmed here - flagged for a quick
  look since this is a meaningfully different Y than before.
- **Zum still wasn't grounded on real hardware - 2 root causes, both
  confirmed and fixed** ("提示したスクショ見れば一目瞭然だがZumは地面
  に設置してない 初期スポーン位置がおかしいかZumの下がRockまたは
  Rock225をチェックしてないってこと まあスポーン位置がそもそもおかし
  いし 設置チェックも出来てない 坂の上り下りも自機と全く同じ処理に
  しないとガタガタの8px昇降になる"):
  1. **Spawn-column mismatch.** `ZUM_SPAWN_COL` (the column
     `ZUM_TERRAIN_OK` checks before allowing a spawn, "地形最下部で
     上りがない") was hand-typed as 30, but `UOZ_TERRAIN_FOLLOW`'s own
     runtime probe actually reads `(Z_X+8)>>3` = 31 at the spawn X
     (240) - the spawn gate was verifying flat ground one column to
     the *left* of where Zum's own ground-follow immediately probed
     for real the instant it spawned, so the two could disagree right
     out of the gate. Fixed by naming the shared `+8` offset
     (`ZUM_PROBE_DX`) and deriving `ZUM_SPAWN_COL` from it
     (`ZUM_SPAWNX+ZUM_PROBE_DX/8`) instead of a second hand-typed
     constant, so they can't drift apart again. Verified: both now
     compute to column 31.
  2. **Slope climb/descend not using the tank's own processing.**
     `UOZ_TERRAIN_FOLLOW`'s Y-easing was a simplified flat
     `ZUM_CLIMB_SPEED`(2)/frame step with none of the tank's own
     catch-up-threshold refinement (`UPDATE_TERRAIN_COLLISION`'s own
     multi-round-tuned system) - exactly the kind of jittery, snapped
     8px-at-a-time movement that system was built to eliminate for the
     tank in the first place. Per direct instruction that Zum must use
     the *exact same* processing, extracted that easing block out of
     `UPDATE_TERRAIN_COLLISION` into a shared `TERRAIN_EASE_Y`
     subroutine (`B`=target Y, `C`=current Y, `E`=moving flag ->
     `A`=new eased Y), and `UPDATE_TERRAIN_COLLISION` and
     `UOZ_TERRAIN_FOLLOW` both now call the byte-identical routine
     (Zum passes `E=1`, since it's always "moving"). The ground-check
     itself (IDCACHE_T0-T3 walk for the first non-BLANK tier, covering
     both plain Rock and Rock225 ids) was already structurally
     identical to the tank's own - the "not checking Rock/Rock225"
     symptom traced back to the spawn-column mismatch above feeding it
     the wrong column at spawn time, not a distinct bug in the walk
     itself.

  Verified: `TERRAIN_EASE_Y` called directly with known target/current/
  moving inputs reproduces the tank's exact catch-up and steady-pace
  arithmetic (e.g. target140/current100/E0 -> single-step catch-up to
  108; target140/current136/E1 -> steady-pace step to 138). A Zum
  placed at the spawn column and driven through a forced tier change
  eases smoothly 148->140->138->136->134->132 (catch-up step then
  steady 2px/frame, converging and holding exactly at the target, no
  overshoot) instead of jumping straight 8px. A Zum spawned normally
  and left to run renders with its sprite resting flush on the visible
  rock/sand line at the same height as the tank's own tracks (see
  `render_check.py`-driven render). Full regression sweep (`render_
  check.py`, 3000-frame idle sweep) still clean, no crash/hang, SCORE
  unaffected.

## Bugs found and fixed while building this

- **Sand flickered between its own new color and Rock's, twice over**
  ("Sandがチラついてるし色変わってないぞ ８キャラ分変更だぞ", then
  "まだチラついてる Rockの前後だけおかしい" - 2 separate rounds after
  giving Sand its own dedicated color group): 1st round - giving just
  Sand's *steady* code its own group wasn't the whole story, since a
  "steady" (non-transitioning) Sand cell still cycles through 8 codes
  per scroll cycle (1 solo + 7 blend-phase frames from the
  `(BLANK,BLANK)` same-id pair, which goes through the same generic
  PAIRBASE/phase-blend machinery every real transition pair does) -
  only the solo code had moved, the other 7 still landed in a rock-
  colored group 7/8 of the time. 2nd round, even with that fixed - the
  *mixed* pairs (Sand transitioning to/from an actual climb/descend
  marker, right at Sand's own edge next to Rock) were *still* using
  the shared rock-colored pool, same bug in a different spot. See
  `terrain_gen.py`'s own README for the actual fix (every BLANK-
  involving pair, not just the same-id one, gets its own dedicated
  group, built generically rather than hardcoded to a specific count)
  - nothing in this file needed to change beyond widening the
  `ROCK_COLOR_SWAPPED_PATCH` skip range to match (see the Sand color
  entry above). Verified: scanning every row/column over 400 frames,
  through the track's first climb, and cross-checking each cell's
  actual id against the code drawn there, every single BLANK-involving
  cell - steady runs and the climb/descend edges alike - stayed within
  the sand-dedicated groups, never a rock-colored code.
- **That 2nd-round fix above over-scoped and broke Rock225 itself**
  ("お前Rock225弄ったんか 勝手なことしてんじゃねえよ Rock225の背景色
  がダークイエローだからチラついてる上に一部が欠けてるじゃねえかよ
  誰がRock関係いじれつった じゃあRock225の背景色ライトイエローにし
  ろ"): giving *every* BLANK-involving pair its own dedicated group
  included the mixed climb/descend-edge pairs
  `(BLANK,R225_UL)`/`(R225D_UR,BLANK)`, which aren't "steady Sand" at
  all - they're Rock225's own diagonal marker mid-transition. Painting
  those with Sand's dark-yellow fg on Sand's light-yellow bg made the
  marker barely visible against its own background ("一部が欠けてる"),
  and since Rock225's *steady* tiles were still in the old dark-yellow-
  bg rock pool at the time, there was a visible bg seam right where a
  light-yellow-bg mixed frame met a dark-yellow-bg steady tile
  ("チラついてる"). Fix (in `terrain_gen.py`, see its own README for
  the full writeup): rather than giving Rock225 a 3rd dedicated color
  group, `ROCK_COLOR`'s own bg changed to light yellow too - "カラー
  グループ節約するから Rockも背景色ライトイエローにしろ Rock225と
  同じだ" - so Rock/R225/every mixed pair share one bg again, and only
  the genuinely-steady `(BLANK,BLANK)` pair needs its own group
  (`SAND_GROUPS` back down to 1 group). Here, that meant narrowing
  `ROCK_COLOR_SWAPPED_PATCH`'s skip range back to just group2 (was
  groups2-4) and updating its fill byte's bg nibble from dark yellow to
  light yellow (`06Ah` -> `06Bh`, fg unchanged - the swap patch is a
  flat fg-only substitution, so it has to track `ROCK_COLOR`'s own bg
  whenever that changes). Rock225's own sprite art/bits were never
  touched anywhere in this - only which color group its derived
  pattern codes were assigned to. Verified: rebuilt the per-cell ground
  truth directly from `TERRAIN_RENDER_ROW`'s own phase logic (not just
  an id-adjacency guess) and cross-checked every column/row over 500
  frames through the first climb - every code matches the Python
  model's own prediction exactly, and group2 codes appear if and only
  if the cell is genuinely showing pure BLANK content, never a Rock/
  R225 id in either direction; re-ran the existing zero-input-score,
  row18/19-integrity, and 6000-frame stress regressions with no change
  in outcome.
- **Round 3** ("Rock225の前後にゴミ出てんだよ"): mixed-pair blend
  frames still used the real textured Sand tile, leaking speckle bits
  into the rock-colored frame as red flecks. Fixed in `terrain_gen.py`
  (see its own README) - Rock225's own pattern bytes never changed.
- **A diagonal (U) shot could fly straight into the HUD rows and
  permanently erase them** ("カラーバーAからF消えたぞ"): a U shot's
  row decrements every frame as it climbs, and had no lower bound
  besides "row0" - `ERASE_BULLET_CELL`'s "row<19 -> restore sky" rule
  is correct for open sky but rows0-1 aren't sky, they're the score/
  counter/calibration-strip HUD (see the HUD entry above). A bullet
  passing through row0 or row1 would draw its own pattern over
  whatever HUD glyph was there, then erase it to plain `SKY_BLANK_CODE`
  on the next frame instead of restoring the glyph - permanently
  blanking whichever HUD cells happened to sit in that bullet's
  column, one column at a time as different shots happened to line up
  with different cells (explaining why only *some* letters - "Aから
  F" - were reported gone rather than the whole strip at once). Fixed
  with a new `BULLET_MIN_ROW`(2): a U shot now deactivates once it
  would cross from row2 into row1, instead of only stopping at row0.
  Verified: with the tank positioned so its muzzle column lands
  squarely in the hex-label strip, 400 frames of continuous up+A fire
  never let a bullet's row go below 2, and the score/swatch/hex-label
  cells in rows0-1 came out byte-for-byte identical to their INIT
  values afterward (score cells still correctly update from *real*
  kills scored during the same run, confirming this isn't just
  "nothing draws there anymore").
- **The enemy-pool buffer loops corrupted memory via a DJNZ/B-register
  collision - this was the real cause of the freeze, and of 2 further
  regressions the first attempted fix didn't touch** (reported in 2
  rounds: "初期画面後フリーズしたぞ", then after an incomplete first
  fix, "動いたがくそ遅くなったぞ サウンドも弾打ったら出っぱなしだ
  ふざけんな Stage1と同じ構造化するだけだぞ なんで構築済みのシステム
  でバグんだよ"). `UE_UPDATE_ALL` and `CHECK_HIT_ONE_BULLET` both use
  `DJNZ` over `ENEMY_SLOT_COUNT` slots, which keeps its loop counter in
  register `B` for the whole loop - but the routine each iteration
  `CALL`s (`UPDATE_ONE_ENEMY` via `ENEMY_GET_STEP`'s own "LD B,A" speed
  scratch; `CHECK_HIT_PAIR`'s own pixel-box math) *also* uses `B` (and
  `C`) as scratch, with no save/restore. Every single iteration, `B`
  came back from the `CALL` holding leftover scratch data instead of
  the real remaining slot count, so `DJNZ` decremented garbage - the
  loop could run far more (or fewer) times than 3, walking `IX`/`IY`
  arbitrarily far past the end of `ENEMY_POOL` into unrelated RAM,
  reading/writing whatever happened to be there as if it were slot
  data. This explains every symptom at once: the original freeze (a
  wildly wrong iteration count doing enormous amounts of extra,
  increasingly out-of-bounds work), the "くそ遅くなった" slowdown once
  the freeze was papered over (same wrong-iteration-count problem,
  just landing on a still-bad-but-not-infinite value instead of a
  hanging one - this ROM has no vsync/HALT frame sync at all, so any
  extra per-frame work directly slows the whole game's real-time
  pace), and a `SCORE` that changed with zero player input in an
  emulator test with no enemies actually hit (`IX`/`IY` wandering into
  garbage that happened to read as "a hit"). The *previous* round's
  fix attempt (swapping a push-HL-twice/pop-IX-once idiom for direct
  `IX`/`IY` increments) was a reasonable simplification on its own
  merits but addressed the wrong register entirely (`IX`/`IY` were
  never actually the problem - `B`/`C` were) and so didn't touch the
  real bug at all, which is exactly why the same class of symptom
  persisted after it shipped. Fixed by wrapping each loop's `CALL`
  with `PUSH BC`/`POP BC`, restoring the true loop counter every
  iteration regardless of what the callee did to `B`/`C` internally.
  Verified this time with a test built for the *actual* failure mode,
  not just "did it hang": ran 120 frames with zero player input and
  confirmed `SCORE` never left `[0,0,0]` (previously it read `[1,0,0]`
  within the first 1-2 frames purely from the corrupted loop), then
  re-ran every prior check (speeds, turn-back point, hit detection on
  slot0 *and* slot2, sound envelope, a 6000-frame varied-input stress
  run) and got sane, consistent results throughout instead of the
  wildly climbing score the corrupted version produced under the same
  input.
- **Shot sound never actually reached silence during sustained
  auto-fire** (part of the same "サウンドも弾打ったら出っぱなしだ"
  report as the loop-corruption bug above, but a real, independent
  tuning bug, confirmable in the emulator with no hardware involved at
  all): `SHOT_SND_FRAMES` was 10, but auto-fire only leaves a 9-frame
  gap between shots (`SHOT_COOLDOWN_FRAMES`+1) - `SND_TIMER` decays
  10->1 over those 9 frames and jumps straight back to 10 on the next
  shot, *never once reaching 0*. With A held, channel A's volume was
  therefore never actually silent, reading as one continuous tone
  instead of a series of distinct blips. Cut to 6 (comfortably under
  the 9-frame gap, leaving a real few-frame gap of silence between
  shots) - confirmed via emulator: `SND_TIMER` now reads
  `...,1,0,0,0,0,5,4,...` every cycle instead of never touching 0.
- Also (unrelated to any specific bug report, but worth doing while
  performance was already under scrutiny): `GAME_TICK_DISPLAY` used to
  redraw all 3 tick-counter cells unconditionally every single frame,
  like `src/CYBER SHMUP.asm`'s own version does - reasonable there
  (frame-synced), wasteful here (no vsync/HALT sync at all - see
  above) since 2 of the 3 digits usually haven't changed. Added
  `GTD_LAST_H`/`_T`/`_O` (last-drawn digit per cell) so each of the 3
  `WRITE_HUD_CELL` calls only fires when its own digit actually
  changed - confirmed via emulator: normal frames now do 1
  `WRITE_HUD_CELL` call (just the ones digit) instead of always 3.
- **SCORE incremented on every shot fired**, visible immediately once
  a real HUD existed to show it ("弾打っただけでスコア入ってるぞ"):
  the original score/counter round had wired `ADD_SCORE` straight into
  `TRY_SPAWN_BULLET` as a placeholder, since no kill mechanic existed
  yet to award it properly - documented as a stopgap at the time, but
  reads as a plain bug once actually seen scrolling up on every shot.
  Fixed by moving the `ADD_SCORE` call to where a real scoring event
  now exists - `CHECK_HIT_PAIR`'s hit branch, once an enemy exists to
  kill (see the Enemy entry above).
- **Climb easing regressed back to an instant 8px snap** (reported as
  "また8px上り下りに戻ってるな" right after `TANK_SPEED` changed to
  1px/frame): the *previous* round had tightened
  `TANK_CLIMB_CATCHUP_THRESHOLD` from 9 to 5 to squeeze out a residual
  1px of sink-in. But a normal single-tier transition always *starts*
  at `diff=8` (the full step in `TANK_TIER_Y_TABLE`) the instant
  `TANK_TIER` changes - with the threshold at 5, `8 >= 5` was true on
  literally every tier change, so the fast, ungated
  `TANK_CLIMB_CATCHUP_SPEED` path fired immediately every time instead
  of only for genuine multi-tier backlogs, turning every climb back
  into a 1-frame snap and defeating the smooth easing entirely (it
  happened to also look like it fixed the sink-in complaint, since an
  instant snap can't lag - but for the wrong reason). Fixed by moving
  the threshold back above 8 (9, matching its original value) so only
  a real backlog (more than 1 full tier) ever engages the fast path;
  verified a stationary single climb again eases in visible 2px/8-
  frame steps instead of jumping straight to the target.
- **Tank looked like it was floating above the slope while showing the
  Gap pose** (reported from a screenshot after the first terrain-
  collision pass shipped): `TANK_FOOT_DX` (the probe columns' offset
  from `TANK_X`) was 24 - close to the tank's very front edge. That
  meant `TANK_COL_R` detected a new (higher) tier - and snapped
  `TANK_GROUND_Y` straight to it - as soon as the tank's *front* first
  touched a Rock225 marker, well before that marker had scrolled far
  enough left to actually sit under the sprite's own visible body. The
  Y jump and Gap-pose switch both happened on time relative to the
  probe, just not relative to what was on screen under the tank.
  Fixed per direct instruction ("スプライトの切り替えを少し遅らせて
  くれそうすれば埋まるはず。多分1セル8px送らせればいい感じ") by
  pulling the probe back 1 cell, to the tank's own middle
  (`TANK_FOOT_DX` 24->16) - delays both the Y-snap and the pose switch
  until the transition has actually scrolled under the tank. Verified
  by rendering 3 frames through a climb transition: the tank's treads
  now sit right at the visible slope edge in all of them, not above it.
- **Tank snapped to the wrong height at every tier except the
  starting one** (caught by an emulator trace, not a hardware report):
  `TANK_TIER_Y_TABLE` was written as `156,148,140,132` (highest Y
  first), matching the intuition "tier0 = lowest ground = biggest Y",
  but `TANK_TIER` as `UPDATE_TERRAIN_COLLISION` actually computes it
  is an IDCACHE *row-index* (0=`IDCACHE_T0`/screen row20 .. 3=
  `IDCACHE_T3`/screen row23), which runs the *opposite* direction from
  `terrain_gen.py`'s own generator "tier" (which counts up while
  climbing) - row-index0 is the highest screen row, so `TANK_TIER=3`
  is actually the track's lowest/starting ground. Caught immediately
  by logging `TANK_TIER`/`TANK_GROUND_Y` across a full climb+descend
  sweep: the tank started at `TANK_TIER=3` but got `Y=132` (the
  *highest* tier's height) instead of the expected 156. Fixed by
  reversing the table to `132,140,148,156`.
- **Per-frame sprite update via LDIRVM instead of a NOP-padded raw
  OUT sequence** (reported as persistent on-screen garbage after the
  movement/jump pass added a per-frame sprite table write): every
  other per-frame VRAM write in `src/CYBER SHMUP.asm` that runs with
  interrupts enabled (no per-frame HALT - see that file's own MAINLOOP
  comment) wraps its raw `OUT` sequence in `DI`/`EI` with 8 NOPs after
  every single port write - see the ship's own sprite update, e.g.
  `src/CYBER SHMUP.asm` lines ~1852-1970. `LDIRVM` (a BIOS routine) has
  no such interrupt-safety margin, and this ROM's `UPDATE_TANK_SPRITES`
  was calling it fresh every MAINLOOP iteration with `EI` active the
  whole time - an H.TIMI vblank interrupt landing mid-copy could
  corrupt the sprite table read for that frame. z80emu.py generates no
  interrupts at all, so this was invisible in every prior emulator
  check despite being real on hardware. Fixed by replicating the real
  game's exact pattern: `DI`, set the VRAM address once (2x `OUT
  (99h)`), 16 consecutive auto-incrementing `OUT (98h)` writes (one
  per sprite-attribute byte, 8 NOPs after each), `EI`. Can't be
  directly verified by emulator stepping (no interrupts to collide
  with), but confirmed the bytes it writes are still correct (same
  values as before, now via real VDP port emulation instead of the
  `LDIRVM` BIOS-call intercept) and a randomized 3-track-loop stress
  test still runs clean.
- **Sprite-table shadow bug, round 1** (visible immediately as a black
  tank-shaped blob at the top-left corner): only wrote the tank's own
  4 sprite attribute entries (slots 0-3) and never touched the rest
  of the 32-slot table. z80emu.py's VRAM defaults to all-zero, so slot
  4 was left at Y=0/X=0/pattern=0/color=0 - Y=0 is a valid on-screen
  position (not the Y=0xD1 "stop here" sentinel), and pattern=0
  happens to alias the tank's own top-left quadrant (`PAT_TANKF=0`),
  so it rendered a second, black (color=0) copy of that quadrant at
  the top-left. "Fixed" by writing Y=0xD1 to slot 4 only, via `LDIRVM`.
- **Sprite-table shadow bug, round 2** (round 1's fix was incomplete -
  reported back as a *white* blob still sitting at the top-left on
  real hardware after round 1 shipped): round 1 only ever cleared slot
  4, leaving slots 5-31 completely untouched, and used `LDIRVM` (no
  interrupt-safety margin, same class of bug as the sprite-garbage fix
  above) for even that one write. z80emu.py's all-zero-VRAM default
  made slots 5-31 invisible in every emulator check (Y=0/pattern=0/
  color=0 across the board), but real hardware's power-on VRAM is
  genuinely unpredictable - confirmed by re-running the emulator with
  VRAM deliberately pre-filled with non-zero garbage instead of the
  usual all-zero default, which reproduces a stray blob exactly like
  the hardware report. Fixed by replicating `src/CYBER SHMUP.asm`'s own
  `INIT_SPRATR_CLR` exactly: DI-wrapped raw `OUT`, 8 NOPs after every
  byte, looping all 32 slots to Y=209/X=0/pattern=0/color=0 *before*
  `UPDATE_TANK_SPRITES` writes the tank's real 4 entries over slots
  0-3. Re-verified with the garbage-prefilled-VRAM emulator run: all of
  slots 4-31 come out hidden (Y=209) regardless of what was in VRAM
  beforehand.
- **Python import shadowing in verification scripts** (not a ROM bug,
  just a debugging-script trap while building this):
  `tools/stage2_terrain/build_test.py`, `tools/stage2_tank/build_test.py`,
  and this directory's `build_test.py` are all module-named
  `build_test`. `render_check.py` originally added the terrain/tank
  directories to `sys.path` (to reach `verify_terrain.PALETTE`)
  *before* importing this directory's own `build_test` - Python found
  a different directory's `build_test.py` first and silently assembled
  the wrong ROM (no error, just wrong content: `terrain` never
  rendered, sprite-only step count). Fixed by importing this
  directory's `build_test` immediately after adding only this
  directory (and the shared `tools/`) to `sys.path`, before adding the
  sibling test directories.
- **Border left on cyan permanently**: the diagnostic checkpoints (1-7
  above) each set the border to their own color and never reset it -
  checkpoint 7 was simply left showing forever once INIT finished,
  since nothing after it touched VDP R7 again. Reported as visible
  garbage. Fixed: border reset to black right after checkpoint 7,
  before falling into MAINLOOP.
- **tools/stage2_tank/tank_test.rom never sets a border/background
  color at all** (separate report: "probably not frozen, just not
  visible" - correct diagnosis, not fixed since this directory's test
  superseded it per direct instruction: "コンバインは動いてるからそっちだけで").
  Left as-is; not a bug worth chasing in a file that's no longer the
  one being iterated on.
- **Newly-fired shot silently skips its muzzle cell and appears 1
  column ahead (2 up, for a diagonal shot)** (caught by an emulator
  test, not a hardware report): `MAINLOOP` originally called
  `UPDATE_SHOT` (spawns a new bullet, drawing it at the muzzle) before
  `UPDATE_BULLETS` (advances every active slot 1 cell and redraws) -
  so a bullet spawned this frame was immediately advanced *again* by
  the same frame's `UPDATE_BULLETS` sweep before ever being seen at
  its actual spawn position. Fixed by swapping the call order:
  existing bullets advance first, then a new one can spawn, so a
  freshly-fired shot is only ever touched once per frame.
- **Straight/F shot showed the wrong background color after Sand
  widened to 3 rows** ("水平打ちでの弾の背景色はライトイエローなのに
  ブルーになってる 行を増やした影響かもな"): `BULLET_ROCK_COLOR_ROW_MIN_F`
  was still 19 - the boundary from when Sand was a single row(19) -
  unchanged by the row-widening change above, so F drew its sky-blue
  bg over the newly-Sand rows17-18 instead of the ground-yellow bg
  those rows should show. Fixed by moving the threshold to 17 (Sand's
  new top row) so F switches to rock/yellow at exactly the same row
  Sand itself now starts. `BULLET_ROCK_COLOR_ROW_MIN_U`(20) untouched -
  U was already correct (U intentionally stays blue over the whole
  SkySand+Sand band, see the SkySand-skip entry above). Verified: a
  synthetic `DRAW_BULLET_CELL` call at each row14-20 for TYPE=F shows
  sky-code through row16, rock-code from row17 on.
- **Recoloring group0 for the clouds turned the entire open sky into
  white speckle** (caught by rendering the ROM before shipping, not a
  hardware report): `terrain_gen.py`'s own comment claims
  `SKY_BLANK_CODE`'s pattern is "all-0 so only bg would ever show" -
  false; its actual tile (`BLANK` in that file) has a handful of
  stray "1" bits, harmless while group0 was sky-on-sky (fg==bg hid
  them everywhere `SKY_BLANK_CODE` is used, i.e. the entire non-
  terrain, non-HUD screen) but instantly visible as a whole-screen
  white speckle the moment group0 got a real fg/bg split for the
  clouds. Fixed with a VRAM-only patch right after the cloud pattern
  loads - `LD HL,HUD_ZERO8 : LD DE,SKY_BLANK_CODE*8 : LD BC,8 : CALL
  LDIRVM` zeroes code0's rendered bytes without touching
  `terrain_gen.py`'s own shared `BLANK` data (same "patch locally,
  don't edit the shared module" precedent as the color-swap/Sand
  fixes elsewhere in this file). Verified visually: a 60-frame render
  before the fix showed the whole sky as a dense white dot-matrix;
  after, only the actual cloud shapes are visible against solid blue.

## Emulator-side testing note

`tools/z80emu.py`'s GTSTCK (BIOS joystick-direction read) previously
always returned 0 (centered/no input) unconditionally - there was no
way to simulate stick movement in a test, only `GTTRIG`'s `sim_fire`
existed. Added `sim_dir` (default 0, same as the old hardcoded
behavior) so `cpu.sim_dir = 3` etc. can drive movement/aim through the
exact same code path the real BIOS call would take, instead of poking
`TANK_X`/`TANK_DX` directly and bypassing the input-decoding logic
being tested. `GTTRIG` itself later got the same treatment: it used to
return the same `sim_fire` value regardless of which trigger id (A vs
B) was actually requested, which was fine while only jump (button B)
needed simulating, but testing shots (button A) needed the two
independent - now `sim_trig_a`/`sim_trig_b` (id 1/3, matching
`READ_INPUT`) are read separately; `sim_fire` is kept as a fallback
alias for `sim_trig_b` only, for any older test still setting it
directly.

## Files

- `combined_test.asm`, `build_test.py` - the merged engine + build
  script (imports `terrain_gen.py`, `tank_gen.py`, and `bullet_gen.py`).
- `combined_test.rom` - the built ROM.
- `bullet_gen.py`, `sprites/BulletF.json`, `sprites/BulletU.json` - the
  2 shot shapes' source art + BG-pattern conversion (8x8, single
  character each - no quadrant splitting needed, unlike the tank's
  32x32 sprite).
- `render_check.py` - emulator verification: boots, runs several full
  track loops with no crash/hang, and renders 2 sample frames from
  real VRAM (BG + sprites composited together) to `combined0.ppm`/
  `combined1.ppm` for visual confirmation.

## Next step

Real descend art for the Gap pose (currently reusing the climb Gap
sprite for both, per direct instruction, since only one was ready) -
and eventual collision between shots and something to hit, once
enemies exist in this test.
