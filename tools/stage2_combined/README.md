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
