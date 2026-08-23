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
  | 11 | INIT reached, SP set (added once the ROM grew past 16KB and needed a real ASCII16 bank-switch - see the ASCII16 entry further down) |
  | 12 | Primary slot mapped into page2 (PPI belt-and-suspenders step, kept alongside the real bank-switch) |
  | 13 | ASCII16 bank-switch trampoline copied to RAM |
  | 14 | Bank1 selected for page2 via the RAM trampoline - returned successfully |

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
- **Still floating 16px+ on real hardware after the above - the actual
  geometry bug, plus a `render_check.py` accuracy bug caught by the
  same report** ("全く変わってねえよ 地面から16px以上浮いてるだろうが
  ...自機も同じ処理してるだろうが" - with a real-hardware screenshot
  showing the tank sitting flush on the ground but Zum floating well
  clear of it, and separately noting this tool's own preview render
  has consistently shown the tank sitting 1px higher than that same
  real-hardware screenshot). Two independent bugs, both confirmed:
  1. **`ZUM_Y_OFFSET`'s SUB from the previous entry was arithmetically
     wrong.** It treated `TANK_TIER_Y_TABLE[tier]` as if it *were* the
     ground line - it isn't. `TANK_Y_BASE`'s own long-documented
     derivation ("row23 top (23*8=184) - tank height(32) + landing
     offset(3+1)" -> 156) means `TANK_TIER_Y_TABLE[i] = ground_line -
     28` (confirmed for all 4 tiers: 132+28=160=20*8, 140+28=168=21*8,
     148+28=176=22*8, 156+28=184=23*8) - the tank's own table is
     already offset 28px *above* the real ground line by its own
     32px-sprite/landing-offset math. `SUB 8` from that anchor landed
     ~20px short of the real ground line instead of on it - which is
     exactly the "16px以上浮いてる" reported here. Re-derived from the
     actual geometry instead: `ground_line=(20+tier)*8` (the literal
     top pixel row of the rock/Rock225 BG tile), Zum is exactly 2
     terrain steps (16px) tall and its own art fills essentially the
     whole 16 rows (`sprites/Zum.json` has real pixels through its
     last row, unlike the tank's own 32px canvas which has 5 blank
     rows at the bottom needing that landing-offset fudge in the first
     place) - so Zum's bottom should simply BE the ground line, no
     separate fudge needed: `Zum_top = ground_line-16 =
     TANK_TIER_Y_TABLE[tier]+28-16 = TANK_TIER_Y_TABLE[tier]+12`.
     `ZUM_Y_OFFSET` is now `12`, `ADD` (not `SUB`) in both
     `ALLOC_ZUM_SLOT` and `UOZ_TERRAIN_FOLLOW`. Verified mechanically:
     spawn Y now reads 168 (156+12), and `Z_Y+16` (Zum's own bottom)
     equals `184` (tier3's `ground_line`) exactly.
  2. **`render_check.py` itself was 1px off for every hardware sprite**
     - a real MSX1/TMS9918 VDP quirk this tool never accounted for:
     the sprite attribute table's Y byte is the actual display row
     *minus 1* (this is the only way to place a sprite flush at row 0
     - write Y=255/-1). Every hw sprite this tool has ever rendered
     (the tank itself, ZacoII, bullet U, Zum) was drawn 1 scanline
     higher than real hardware actually shows it, because the render
     loop plotted straight at the stored Y with no `+1`. Fixed in
     `render_full()` - the 208+ hide-sentinel checks still compare the
     raw stored byte (unaffected, that's VDP list-processing behavior,
     not a display-row quirk), but the actual pixel-plotting Y now
     uses `(y+1)&0xFF`. This alone doesn't explain Zum's 16px+ float
     (1px is far too small), but it does explain this tool's own
     tank-vs-real-hardware 1px mismatch, and matters for trusting any
     future pixel-level comparison against a real-hardware screenshot.

  Verified: with both fixes, a normally-spawned Zum's rendered sprite
  now rests flush on the visible rock/sand boundary at the same height
  as the tank's own tracks (re-rendered via the corrected
  `render_check.py`), and the spawn-time arithmetic check above
  confirms `Zum_bottom == ground_line` exactly, not just "looks close"
  in a render. Full regression sweep (`render_check.py`, 3000-frame
  idle sweep) still clean.
- **Ground fix confirmed working, but standing-on-top of Zum still
  didn't settle - a different bug, not the same one** ("よし修正された
  ...今度は乗っかりでZumに設置してない問題 原因はそこかと思ったが別だな
  Zumへの着地位置が間違ってると言うこと"). `UPDATE_TANK_ZUM_STAND`'s
  own vertical clamp (`LD A,(IX+2) : SUB TANK_PUSH_WIDTH : LD D,A`) was
  subtracting `TANK_PUSH_WIDTH` (32) - a *horizontal* collision-width
  constant for the separate push-block check, reused here purely
  because it happened to also equal 32, the tank's own sprite height.
  But the tank's own top-anchor never sits a full 32px above whatever
  it's standing on - same reasoning as the ground fix just above: it's
  groundline-28 (`TANK_GROUND_OFFSET`, newly named, matching `TANK_Y_
  BASE`'s own "tank height(32) - landing offset(4)" derivation), not
  groundline-32. Standing on Zum was using the wrong offset (32
  instead of 28) for a completely different reason than the ground-Y
  bug above - this one was never touched by the `ZUM_Y_OFFSET` fix at
  all, which is exactly why it needed a separate report and separate
  fix. Now uses `TANK_GROUND_OFFSET` instead, the same anchor-to-
  surface relationship as standing on ordinary terrain. Verified: a
  Zum placed directly under the tank with `TANK_Y_CUR` starting below
  the stand line clamps to exactly `Zum_top-28`, giving a 4px tank-
  bottom/Zum-top overlap (matching the same 4px landing overlap normal
  ground-standing uses) instead of the old 32-offset's implied 0px
  (which read as the reported gap). Re-rendered visually: the tank's
  own tracks now sit flush on top of Zum with no visible seam.
- **Jumping while parked on top of Zum ("乗っかり中にジャンプできない
  ")**: `UPDATE_JUMP` always refused a new press whenever `JUMP_ACTIVE`
  was already set - which, while parked on a Zum, is *permanently*
  true (the auto-land cycle from the earlier "乗っかりから降りる時の
  速度が速すぎてワープにみえる" fix never actually clears `JUMP_ACTIVE`,
  it only rewinds `JUMP_FRAME` back to `JUMP_LANDING_RESTART_FRAME`
  forever). Now a new press is also honored while `TANK_ZUM_STANDING`
  is set (an ordinary mid-air jump, not parked, still can't be
  re-triggered - verified separately, `JUMP_FRAME` just keeps
  incrementing normally on a repeat press mid-air).
  Per direct instruction ("この時ジャンプが加算されて地面までの距離が
  変わりLutがオーバーすると思うがその時はLut最終値を使い回すこと"):
  simply restarting `JUMP_FRAME` at 0 against the existing formula
  (`TANK_Y_CUR = TANK_GROUND_Y - JUMP_OFFSET_TABLE[JUMP_FRAME]`) would
  snap the tank down to true ground for one frame (table[0]=0) before
  arcing up from there - visibly wrong, since the tank is currently
  sitting on top of Zum, well above true ground. New `JUMP_STAND_
  BASELINE` byte captures the current elevation above true ground
  (`TANK_GROUND_Y-TANK_Y_CUR`) at the exact moment a re-jump is
  honored, and `JUMP_Y_OFFSET` is now `JUMP_OFFSET_TABLE[JUMP_FRAME] +
  JUMP_STAND_BASELINE` instead of the table value alone - so the new
  arc adds its own 24px on top of wherever the tank already was. Reset
  to 0 on init and whenever a jump ends normally (`UJ_END_NORMALLY`),
  so it never leaks into an unrelated later jump; an ordinary ground
  jump (never parked) always starts it at 0, so its own behavior is
  numerically unchanged (verified: peak still exactly `TANK_GROUND_Y-
  24`, lands exactly back at `TANK_GROUND_Y`, `JUMP_ACTIVE` clears at
  the end same as before). The table itself is never read out of
  bounds by any of this - `JUMP_FRAME` is already always kept within
  the existing `CP JUMP_FRAMES` guard before every table read, re-jump
  or not, so there's no separate "reuse the LUT's last entry" branch
  needed beyond what that guard (and the existing auto-restart-at-16 /
  end-normally logic) already does.
  Verified end-to-end in a full mainloop run (`UPDATE_JUMP` +
  `UPDATE_TANK_ZUM_STAND` both active, a pinned Zum directly under the
  tank): parks at `Y=140` (`Zum_top(168)-TANK_GROUND_OFFSET(28)`,
  matching the standing-fix above), a fresh press while parked peaks
  at exactly `Y=116` (`140-24`, the full jump height added on top of
  the parked elevation) and settles back into the same parked cycle
  afterward. `render_check.py` and the 3000-frame idle sweep both
  clean, SCORE unaffected.
- **Sine-eased X speed for both enemies, replacing instant speed
  switches** ("では敵のX移動にサイン移動を採用する Zumは出現時速度２
  自機に近づいたらサイン減速で速度1.5 今の時期検知は近いんでもっと
  離れた位置に で、ZukuIIにもサイン減速 で、反転して帰っていく際は
  サイン加速 速度は今のままでいい" - "ZukuII" read as ZacoII, the only
  other enemy in this file). Both enemies previously snapped between
  speed tiers in a single frame (Zum: flat 1.5-avg -> flat 3 once
  within 64px; ZacoII: flat cruise -> flat *doubled* cruise the exact
  frame it turns back) - now both ease smoothly via small sine-shaped
  tables instead, **indexed directly by current distance, not elapsed
  frames** - self-correcting every single frame regardless of how the
  tank itself moves during the approach, and needing no new per-slot
  "which frame of the ramp am I on" state at all.
  - **Zum**: flat `ZUM_SPEED_BASE`(2) cruise beyond `ZUM_DECEL_RANGE`
    of the tank, sine-eased down to a flat 1.5 avg via `ZUM_DECEL_
    TABLE` (128 entries, one per px of distance) once inside it - no
    more sudden charge speed-up, replacing `ZUM_SPEED_SLOW_BASE`/
    `ZUM_SPEED_FAST`/`ZUM_CHARGE_MARGIN` entirely. The old 64px trigger
    distance was "今の時期検知は近い" (too close) per this same
    instruction, so `ZUM_DECEL_RANGE` is double that (128) - not a
    number given directly, doubling the prior "too close" value being
    the most literal reading available; easy to retune further from
    real-hardware feedback.
  - **ZacoII**: unchanged cruise speed on both legs everywhere except
    the last `ENEMY_RAMP_RANGE`(32, an assumed value - not specified)
    px of the approach (eases down toward the turnback pivot) and the
    first 32px of the retreat (eases back up) - `ENEMY_GET_STEP_RAMPED`
    wraps the existing `ENEMY_GET_STEP` and only diverts to a table
    read within that zone, so "速度は今のままでいい" (the actual cruise
    magnitudes, including the existing 2x retreat doubling) is
    untouched by construction, not just by intent - outside the ramp
    zone it's a straight passthrough to the same code as before.
  - Every table entry across all 5 tables (`ZUM_DECEL_TABLE`,
    `ENEMY_DECEL_TABLE_GREEN/RED`, `ENEMY_ACCEL_TABLE_GREEN/RED`) is
    generated (not hand-tuned) via error-diffusion of a quarter-sine
    ease, walked in the same direction gameplay actually traverses the
    index (so any short window of consecutive frames still averages
    close to the intended continuous curve despite each entry being a
    whole px step) - same idea as `JUMP_OFFSET_TABLE`, just distance-
    indexed instead of frame-indexed.
  - **Bug caught before shipping**: a first pass let the DECEL tables'
    curve reach its true continuous 0 right at the pivot - which is a
    hard freeze, not a pause: once a table entry reads 0, distance-to-
    pivot doesn't change next frame either, so the *same* 0 entry gets
    read forever and ZacoII never actually crosses the pivot to
    retreat (caught immediately in the emulator - a green ZacoII
    parked motionlessly a few px short of the turnback line for 100+
    frames straight, `E_RETREAT` never flipping). Every DECEL/ACCEL
    table entry is now floored at 1 during generation (Zum's own table
    never needed this - its whole 1.5-2.0 range is naturally >=1) -
    ZacoII always creeps forward at least 1px/frame even at its
    slowest near the pivot, trading a true dead stop for a guaranteed
    crossing.
  Verified: a green ZacoII eases from -3px/frame cruise down through
  -1px/frame near the pivot, flips to retreat, eases +1 up to the full
  +6px/frame retreat cruise (red variant, matching the existing 2x-
  doubled target exactly), and despawns cleanly off the spawn edge -
  no stall anywhere in the sequence. Zum's own table read directly
  confirms flat 2 outside `ZUM_DECEL_RANGE` and a smooth 1-2 alternation
  averaging toward 1.5 as distance shrinks. A 4000-frame stress sweep
  (random direction/shot/jump input each frame, enemies actively
  spawning and dying) plus the standard `render_check.py` and 3000-
  frame idle sweep all ran clean, no crash/hang, SCORE incrementing
  normally from a real kill during the stress sweep.
- **Zum's re-acceleration was missing entirely - a follow-up
  correction, not a bug in the ZacoII half above** ("Zumの加速は必要
  だぞ その前提で考えてるんだから ただロジック的に両立出来ないんで
  出現時速度３で右から出てきたら 80pxで自機を検知して速度1にサイン
  減速 減速終了で速度3までサイン加速して自機に突っ込む"). The first
  pass only decelerated Zum down to a slower flat cruise (1.5) and left
  it there - dropping the re-acceleration/charge the original premise
  actually needed. Replaced with the full 3-phase profile now spelled
  out explicitly: flat `ZUM_SPEED_BASE`(3, was 2) beyond `ZUM_DETECT_
  RANGE`(80, replacing the old `ZUM_DECEL_RANGE`/64px trigger) of the
  tank; inside it, the 80px zone splits into two `ZUM_MID_RANGE`(40,
  assumed - the split point itself wasn't specified, taken as half of
  80) halves - the outer half sine-decelerates 3->1 via `ZUM_DECEL_
  TABLE` (rebuilt, 40 entries), the inner half sine-accelerates 1->3
  back up to full charge speed via a new `ZUM_ACCEL_TABLE` (40
  entries), reaching full speed again right as it reaches the tank -
  "減速終了で速度3までサイン加速して自機に突っ込む". Both tables keep
  the same distance-indexed, error-diffused, floored-at-1 construction
  as the rest of this feature (see the entry above) - no stall risk,
  no new per-slot state. Verified: a Zum released 150px out holds flat
  -3px/frame until well inside the detection zone, eases down through
  -1px/frame around the midpoint, then eases back up to a flat -3px/
  frame right up to contact - the full deceleration-then-charge shape,
  not the old single one-way ease. Full regression sweep (`render_
  check.py`, 3000-frame idle sweep, 4000-frame random-input stress
  sweep including live Zum/ZacoII spawns) still clean; also confirmed
  a Zum released far out and left completely unopposed charges all the
  way in and pushes the tank to `TANK_X=0` (no player input at all),
  matching "何も操作しなければ敵に押される" end-to-end.
- **Zum's decel trough raised from 1 to 1.5, plus a new "kin" deflect
  sound on its invincible front** ("減速目標を1から1.5に変更 1だと
  止まって見えてしまうんで で、Zumの前面無敵に弾が当たったらキンキン
  と言うサウンド追加 これはStage1のボスの弾き音流用"). `ZUM_DECEL_
  TABLE`/`ZUM_ACCEL_TABLE` regenerated with their trough at 1.5 instead
  of 1 - at a flat 1, several consecutive frames near the midpoint
  read as a dead stop rather than a slowdown; 1.5's own 1/2 dithering
  never holds still for more than a couple frames even at its slowest.
  Separately, added `SOUND_ZUM_DEFLECT` - a new PSG channel C (tone),
  byte-for-byte the same period(10)/timer(10) as `src/CYBER SHMUP.asm`'s
  own `SOUND_POD_HIT` (a metallic "kin" ping for a non-lethal boss-pod
  hit - same idea here, a bullet absorbed rather than destroyed).
  Channel C was previously unused by this file (mixer register7 had
  its tone-C bit disabled, `0E7h`) - now enabled (`0E3h`) alongside a
  new `SND_TIMER_C` fade timer and a 3rd `SOUND_UPDATE` stage, on its
  own channel so it never fights a shot or explosion sound triggered
  the same frame. Wired into `CHECK_HIT_PAIR_ZUM`'s existing front-hit
  branch (absorb-only, no score/explosion) right where the bullet gets
  deactivated. Verified: a bullet AABB-overlapping Zum with `TANK_X` <
  `Zum_X` (front) sets `SND_TIMER_C=10` and deactivates the bullet
  without touching Zum's own `Z_ACT`; the same overlap with `TANK_X` >
  `Zum_X` (rear/kill) leaves `SND_TIMER_C` untouched at 0 and instead
  sets `Z_ACT=2` (exploding) - the sound only ever fires on the
  no-effect front case, never alongside a kill. Zum's own decel/accel
  profile re-verified showing a 1-2 dithered plateau (never a flat run
  of 1s) instead of the old flat-1 stretch. Full regression sweep
  (`render_check.py`, 3000-frame idle sweep, 4000-frame random-input
  stress sweep) still clean.
- **Sound volumes raised - shot to 10, Zum deflect to 12** ("あと音が
  小さいな 12くらいに上げてくれ 自機ショット音も多分8だと思うんで
  10に" - referring to the new "kin" deflect sound and the shot sound
  respectively). `SOUND_ZUM_DEFLECT`'s `SND_TIMER_C` initial value
  raised 10->12 directly (peak volume and duration both scale with it,
  and nothing repeats fast enough for that to matter here). The shot
  sound needed more care: `SHOT_SND_FRAMES` (6) directly doubles as
  both the fade duration *and* (previously) the peak volume, and it
  has to stay under the 9-frame auto-fire gap or held-fire never
  actually reaches silence between shots - a bug already found and
  fixed earlier in this same file (see `SHOT_SND_FRAMES`'s own
  comment). Simply raising it back toward 10 to get a louder shot
  would silently reintroduce that exact bug. Split the two instead:
  new `SHOT_VOLUME_BOOST`(4) is added to `SND_TIMER`'s own value only
  while it's still counting down (never touching the silent/0 case),
  so the shot now peaks at `6+4=10` and reaches true silence at
  exactly the same frame as before - duration unchanged, only volume
  raised. Verified by single-stepping `SOUND_UPDATE` and inspecting
  the accumulator value right before each PSG write (this emulator
  doesn't actually simulate the PSG chip itself, so port writes can't
  be read back after the fact): the shot sound's register-8 write
  peaks at exactly 10 on the first update after firing and decays
  0,1,2,3,4,5 frames later to exactly 0 - not 4 (which an unconditional
  `+4` offset would have produced instead of true silence). `SND_
  TIMER`/`SND_TIMER_C` themselves (the underlying countdown, unaffected
  by the boost) still decay to 0 after exactly 6 and 12 frames
  respectively, matching their own unchanged/new duration. Full
  regression sweep clean.
- **Investigated: "Zumと自機が接触した時に押し込んでこなくなってるぞ"
  (Zum no longer pushes on contact) - could not reproduce.**
  `UPDATE_TANK_ZUM_PUSH` itself was untouched by every change in this
  session's sine-speed/sound rounds, and direct testing found it
  working in every scenario tried: a Zum released just outside push
  range still clamps `TANK_X` down to the screen edge with no player
  input; a naturally-spawned Zum (via the real spawn gate, not a
  forced position) engages the same way; holding right (steering
  *into* the approaching Zum) still gets held at the push boundary
  until the tank genuinely passes it; and parking on top of a Zum via
  a jump, then moving away before approaching a *different* Zum on the
  ground, still pushes normally afterward (`JUMP_ACTIVE` reliably
  clears within a few frames of losing overlap, so it doesn't get
  stuck suppressing `UPDATE_TANK_ZUM_PUSH`, which bails immediately
  while airborne). Flagging this rather than guessing at a fix -
  possible it's specific to real-hardware timing this emulator can't
  reproduce, or that the gentler sine approach (this session's earlier
  rounds) just makes the moment of contact read differently than the
  old instant flat-3 charge did. Would help to know: does it fail on
  literally the first contact ever, or only after some other
  interaction (jumping, a kill, standing on a Zum) first?
- **Follow-up: Zum spawning too close to the tank at the right edge -
  likely the real explanation for the "doesn't push" report above**
  ("自機が前に押してる場合は押してくるが 前に移動操作してないと押し
  込んでこないからだな あと右端でスポーン時に自機が右端のいるとすり
  抜けていく すり抜けないように 左端はすり抜けるがこれはそのままで
  いいわ"). Root cause: `ALLOC_ZUM_SLOT` set a fresh Zum's `Z_X` to
  `ZUM_SPAWNX`(240) unconditionally the instant a slot freed up, with
  no check on where the tank currently was - if the tank happened to
  already be near the right edge at that exact moment, the new Zum
  spawned effectively right on top of it, too close for `UPDATE_TANK_
  ZUM_PUSH`'s own approach-then-clamp sequence to get a normal run-up,
  reading as sliding straight through instead of pushing. This most
  naturally happens while the player *isn't* actively driving toward
  the spawn edge (an idle or drifting tank has more opportunity to
  linger there than one being actively steered elsewhere) - matching
  the "no forward input -> no push" pattern reported, without needing
  a second, separate bug in the push logic itself (which, per the
  investigation above, checks out fine on its own). Left-edge pass-
  through (the tank actively driving *through* an approaching Zum) is
  the separate, already-intentional "already passed" mechanic from
  earlier in this file and stays untouched, exactly as asked.
  `ALLOC_ZUM_SLOT` now also requires `TANK_X < ZUM_SPAWNX-ZUM_DETECT_
  RANGE` (160) before granting a spawn - same "retry next frame, no
  fixed wait" polling pattern as the existing terrain-flatness gate,
  so camping the right edge just delays the next Zum rather than
  softlocking anything. Verified: a spawn attempt with `TANK_X=223`
  (the tank's own max-right position) is refused, the same attempt
  with `TANK_X=100` succeeds, and camping right for 400 frames blocks
  spawning the whole time but a Zum spawns normally within a couple
  hundred frames of moving back out of the zone - no permanent
  spawn-lock. Full regression sweep clean.
- **"サウンドはノイズｃｈ使用音は別にしなくていいぞ どうせ被れば消
  える PSGは3ch+ノイズ1chが仕様 2chはBGM用に常に空けておきたいしな"
  - consolidated every current sound effect onto channel A alone**,
  freeing channels B and C entirely for future BGM. Previously shot/
  explosion/deflect each had their own channel specifically so they'd
  never cut each other off mid-fade; per this instruction that's an
  accepted tradeoff now, not something worth 3 channels for - the
  PSG's single shared noise generator meant the 2 noise-based sounds
  (shot, explosion) never had fully independent *sound* anyway, only
  independent volume envelopes. `SND_TIMER_B`/`SND_TIMER_C` removed;
  a single `SND_TIMER`/`SND_DECAY` pair now drives channel A for
  whichever sound fired most recently (`SOUND_SHOT`/`SOUND_DESTROY`/
  `SOUND_ZUM_DEFLECT` each set both, plus the mixer register (`MIXER_
  NOISE_A`/`MIXER_TONE_A`) since channel A now has to switch between
  noise and tone mode depending on which sound is currently playing).
  `SOUND_UPDATE` is now one generic decay loop instead of 3 near-
  identical per-channel copies. The shot sound's own peak(10)/fast-
  decay(2/frame) split from the previous round carries over unchanged
  (still needed to avoid the held-fire sustain bug); explosion and
  deflect just decay 1/frame from their own peak, matching their
  previous per-channel durations (15 and 12 frames). Verified: firing
  shot then immediately explosion shows the shot's own timer/decay
  fully overwritten (15/1, not merged or averaged with the shot's
  10/2) - a clean cutover, matching "被れば消える" exactly. Full
  regression sweep clean.
- **Right-edge spawn: refused-to-spawn softlock, replaced with an
  instant push at spawn** ("押してくるようになった しかしスポーンキャ
  ンセルでは自機が右端に居続けると永遠にスポーンできない 自機が右端
  にいたら押してスポーンするように"). The previous round's fix
  refused to spawn a Zum at all while the tank was within `ZUM_DETECT_
  RANGE` of the spawn point, to stop slip-through - but that meant a
  Zum could never spawn again if the tank simply parked near the right
  edge, a real (if narrow) softlock for this enemy type. Reverted
  `ALLOC_ZUM_SLOT` back to its original 3-condition gate (spawn count,
  terrain, free slot - no tank-distance check), and instead added an
  *instant* overlap resolution to `AZS_FOUND` itself: if `TANK_X` is
  already within `TANK_PUSH_WIDTH` of the fresh Zum's spawn X, snap it
  straight to `ZUM_SPAWNX-TANK_PUSH_WIDTH` (208) as part of spawning,
  rather than waiting for the next several frames of `UPDATE_TANK_ZUM_
  PUSH`'s own rate-limited clamp to catch up - closes the same-frame
  slip-through window without ever blocking a spawn. Verified: a spawn
  attempt with `TANK_X=223` (max-right) now succeeds *and* instantly
  resolves `TANK_X` to 208; camping right continuously for the full
  natural spawn-gate cycle (~1200 frames) still produces a Zum on
  schedule, not never.
- **Explosion sound protected from being cut off by the shot sound**
  ("爆発音はショット音で消えるとまずいんで爆発音は鳴り終わるまで継続
  しショット音で消えないように"). New `SND_EXPLODING` flag: set by
  `SOUND_DESTROY`, checked by `SOUND_SHOT` (which now refuses to fire
  at all while it's set, leaving the explosion's own `SND_TIMER`/mixer
  completely undisturbed), cleared automatically the instant the
  explosion's own `SND_TIMER` reaches 0 in `SOUND_UPDATE`. `SOUND_ZUM_
  DEFLECT` still cuts an explosion off same as any other sound - only
  the shot sound is singled out here, per the literal instruction.
  Verified: firing shot immediately after an explosion leaves `SND_
  TIMER`/`SND_DECAY` at the explosion's own 15/1 untouched; once 15
  frames of `SOUND_UPDATE` let it finish naturally, a shot fired after
  that does play normally (10/2).
- **Zum can now randomly flee instead of always charging in, sine-
  accelerating away just like ZacoII's own retreat** ("ついでに 自機
  の前まで減速したら押してくるやつと反転して逃げるやつをランダムに
  引き返しもサイン移動で"). New per-slot `Z_RETREAT` field (0=still
  approaching/undecided, 1=fleeing, 2=charging/decided) - `ZUM_SLOT_
  SIZE` 7->8. The instant a Zum's own deceleration first crosses into
  the near-tank zone (`distance<ZUM_MID_RANGE`), it rolls once (a
  simple `CLOUD_RNG`-based coin flip, the same free-running-counter
  RNG idiom clouds already use) between continuing to charge in
  (unchanged existing behavior) or reversing to flee back off the
  right edge - sine-accelerating away through a new `ZUM_FLEE_TABLE`
  (same distance-indexed, error-diffused, floored-at-1 construction as
  every other speed table in this file), cruising at `ZUM_FLEE_SPEED`
  (6 - doubled from the ordinary cruise speed, matching ZacoII's own
  established "帰る時は倍速で" retreat-doubling convention, since no
  specific number was given for Zum's own flee). Draws with `PAT_ZUM_
  FLIP` while fleeing - the mirrored Zum art `enemy_gen.py` generated
  from day one but never actually used until now. Front/rear hit
  orientation (`CHECK_HIT_PAIR_ZUM`) inverts while fleeing too: a
  fleeing Zum has turned to face right, so its exposed back is now its
  *left* side (`TANK_X<Zum_X`) instead of its right - verified
  directly (a bullet hitting a fleeing Zum from what would normally be
  its "front" side now kills it, and vice versa; a non-fleeing/
  charging Zum's orientation is confirmed unchanged). Roll outcomes
  verified 50/50 over 40 trials; the full flee sequence (roll -> sine
  ease from the decel trough up to 6 -> despawn back off the spawn
  edge) confirmed end-to-end; a render shows the mirrored sprite
  displaying correctly, sitting flush on the ground exactly like the
  normal pose.
- **Idle push strength raised 3->6px/frame** ("あと無操作でも押しては
  くるが弱いんで自機が押してるのと同じ押し量で"). Measured directly
  before changing anything, since the numbers were surprising: idle
  contact already moved `TANK_X` the full `ZUM_PUSH_SPEED`(3) every
  single frame, but steering *into* an approaching Zum netted only
  ~1px/frame of actual backward drift (the tank's own 1-2px/frame step
  fights the same clamp each frame) - numerically, idle was already
  the *stronger* push, not the weaker one. Confirmed with the user
  before touching anything: they wanted the already-stronger idle
  number raised further, not brought down to match the resisted-push
  feel. `ZUM_PUSH_SPEED` raised to `ZUM_FLEE_SPEED`(6) - Zum's fastest
  speed anywhere in this file - rather than its own ordinary cruise
  (3). Full regression sweep clean (`render_check.py`, 3000-frame idle
  sweep, 6000-frame random-input stress sweep with live Zum/ZacoII
  spawns and kills throughout).
- **The real bug behind "raising ZUM_PUSH_SPEED changed nothing" -
  found and fixed** ("で、やはり自機が前に入れて押している時より無操
  作時の押し量が変わってない 地形の左移動量のカウンター1で1pxスクロ
  ールと一致してて止まって見えるんだよ 自機が地形より下がっていかな
  いと バグなのか押し量が足りないのか判断つかないがパラメータを変え
  ても変わってないのでバグだろうな" - exactly right, and traced to a
  concrete mechanism, not just "needs a bigger number"). `UPDATE_TANK_
  ZUM_PUSH`'s old design clamped `TANK_X` *toward* a fixed target
  (`Zum_X-TANK_PUSH_WIDTH`) and snapped precisely onto it once the
  remaining gap was smaller than `ZUM_PUSH_SPEED` - which means once
  the tank actually caught up to that boundary (almost immediately),
  every later frame's movement was governed entirely by how far the
  *target itself* moved, i.e. by Zum's own current speed, completely
  independent of `ZUM_PUSH_SPEED`'s value. Directly reproduced in the
  emulator before touching any code: with a Zum forced to keep
  charging (no flee roll), steady-state contact settled into a flat
  **1px/frame** drift no matter whether `ZUM_PUSH_SPEED` was 3 or 6 -
  because Zum's own accel-table speed right around the typical contact
  distance (gap≈32) is 1. `ZUM_PUSH_SPEED` genuinely only ever
  mattered for the brief initial catch-up transient, never for
  sustained pushing - exactly matching "パラメータを変えても変わって
  ないので". Fixed by removing the snap-to-target shortcut entirely:
  `UPDATE_TANK_ZUM_PUSH` now applies the *full* `ZUM_PUSH_SPEED`
  unconditionally every single frame the tank is in contact, with no
  attempt to land precisely on the 32px boundary - this overshoots
  past it on purpose, contact simply disengages for a frame or two
  until Zum closes back in, then pushes again, instead of settling
  into an unnoticeable 1:1 tracking. The original rate-limiting itself
  (the actual anti-warp fix from a much earlier round) is untouched -
  still bounded to `ZUM_PUSH_SPEED`/frame, still never a single-frame
  snap across a large gap. Verified: the same forced-charging scenario
  now shows `TANK_X` dropping in full 6px bursts roughly every 3
  frames (~2px/frame average, a real improvement over the old flat 1)
  instead of a flat 1px/frame the whole time; a large post-contact gap
  (created by simulating a jump-suspended push) still resolves
  gradually in 6px steps, never an instant snap; full regression sweep
  clean.
- **Flee speed dropped back from doubled to flat** ("反転時の速度が速
  いので落としてくれ もしかして2倍にしてないか"). Correct guess -
  `ZUM_FLEE_SPEED` was `ZUM_SPEED_BASE*2`(6), borrowing ZacoII's own
  "帰る時は倍速で" retreat-doubling convention without a real basis
  (no number was ever given for Zum's own flee specifically). Dropped
  to a flat match of `ZUM_SPEED_BASE`(3) instead, `ZUM_FLEE_TABLE`
  regenerated to match (same 1.5->3 ease shape `ZUM_DECEL_TABLE`
  already uses, just walked in the opposite - growing-distance -
  direction).
- **A motionless pause at the charge/flee decision point** ("Okツッコ
  ミと反転の分岐時に少し止まってから反転するか突っ込むかに変更 今の
  カウンター基準だと4フレ停止かな"). Previously the coin-flip roll and
  the resulting movement (charging or fleeing) happened on the exact
  same frame the near-tank zone was first entered - no beat at all.
  New `Z_RETREAT=3` (pausing) state: the instant distance first drops
  under `ZUM_MID_RANGE`, Zum goes fully motionless for `ZUM_PAUSE_
  FRAMES`(4) - counted down in `+3` (the same byte `Z_TIMER` uses for
  the explosion countdown, otherwise idle the whole time Zum is alive)
  - then rolls exactly as before. Terrain-height easing keeps running
  throughout the pause (`UOZ_TERRAIN_FOLLOW` is called unconditionally
  ahead of the whole dispatch), and the sprite stays in its normal,
  unflipped pose the entire time (`Z_RETREAT` isn't 1 yet). Verified:
  `Z_X` sits completely flat for exactly 4 frames while `Z_RETREAT=3`
  and the countdown ticks 3,2,1,0, then resumes moving the same frame
  the roll resolves; both outcomes (flee/charge) still reachable
  roughly 50/50 after the pause. Full regression sweep clean.
- **Pause raised 4->8 frames** ("停止を8フレに").
- **The real cause of clouds/ZacoII "randomness" sometimes getting
  stuck at a fixed value - found and fixed, not just a bigger-range
  band-aid** ("気になってたのが雲とZakoIIのランダムパラメータ 一定で
  固定されてるときがある 特に雲は最初の方がかたまって出てくる").
  `CLOUD_RNG` (renamed `GAME_RNG` - it's shared by clouds, ZacoII, and
  Zum's own roll now) was a bare "read, +1, store" counter, same idea
  as Stage1's own `DFL_RNG`. That design only gains 1 unit of real
  entropy per read - fine if reads come from unpredictable, irregular
  triggers, but any consumer with its *own* perfectly regular cadence
  (a fixed-interval spawn timer, for instance) sees the exact same
  delta between consecutive reads every time, cycling through a short,
  fully deterministic sequence - or landing on one single fixed value
  outright if that delta happens to be a multiple of the consumer's
  own mask+1. ZacoII's own spawn Y (`TICK AND ENEMY_SKY_Y_MASK`, not
  even `GAME_RNG`-based) had exactly this problem: spawns always
  reload `ENEMY_SPAWN_TIMER` to the same fixed 90, so `TICK`'s value at
  each spawn advances by a constant 90 (mod 256) - with a 64-wide mask,
  that's a fixed delta of 90 mod 64 = 26, which only touches half the
  possible Y band (`gcd(26,64)=2`) in the same repeating 32-step order
  forever. Clouds "bunching up especially at the start" fits the same
  root cause from a different angle - early in a run, before any
  ZacoII/Zum have spawned to interleave *their own* reads into `GAME_
  RNG`, cloud logic is the *only* thing touching it, so its progression
  is at its most nakedly deterministic exactly when the player first
  sees the game.
  Fixed at the source rather than patched per-symptom: `GAME_RNG` now
  also advances every single frame in `MAINLOOP`, unconditionally, by
  the *current `TICK` value* (not a flat +1) - the running sum
  1+2+3+...+`TICK` grows non-linearly, so no fixed-interval consumer
  can ever see a constant delta between reads again, regardless of its
  own period. `ALLOC_ENEMY_SLOT`'s own Y draw switched from raw `TICK`
  to this same (now-fixed) shared source for consistency. Also, per
  direct instruction, ZacoII's red/green pick past the 10-spawn
  threshold is no longer permanently red - "あとZakoIIが10機でたら
  (Zumと同じタイミング)あとは赤ZakoIIと緑ZakoIIランダムで" - a 50/50
  `GAME_RNG`-based coin flip on every spawn once the threshold is
  reached, matching Zum's own timing convention. Verified: sampling
  `GAME_RNG` at the old resonant 90-frame interval now shows wildly
  varying deltas (previously would have been a flat, constant value);
  15 consecutive enemy spawns (forced past the red/green threshold)
  show 12 distinct Y values spanning the full band and a genuine mix
  of both variants, not a fixed pattern. Full regression sweep clean.
- **ZacoII recolored to light green** ("まずZakoIIの色をライトグリー
  ンに"). `ENEMY_COLOR` 12(dark green, `sprites/ZacoII.json`'s own
  original fg) -> 3(light green) - a straight sprite-color-attribute
  swap, no art/pattern change (the red variant's own `ENEMY_RED_COLOR`
  is untouched).
- **BigZum: a second, tougher ground enemy** ("次BigZumの実装 Zumと
  スポーン条件は同じ アルゴリズムもほぼ同じ 違うのは停止後引き返さず
  パンチするかジャンプして乗っかってくる ジャンプは自機より高く32ｐｘ
  サインジャンプ 自機に設置したら連続ジャンプで飛び越え 自機の後ろを
  取って地上に降りたら後ろからパンチ なので添付のデータは反転も生成
  攻撃判定も同じで後ろしか当たらない 耐久5", 2 uploaded 32x32 sprite
  JSONs - `BigZum`/normal pose, `BigZumP`/punch pose). A 32x32 sprite
  (2x2 of 16x16 hw sprites, same quadrant convention `tank_gen.py`
  established for the tank - `bigzum_gen.py`, a new generator module
  mirroring `tank_gen.py`'s own quadrant-splitting + hflip approach for
  BigZum's 2 poses instead of the tank's 4, patterns at codes156-219
  right after `PAT_ZUM_FLIP`(152-155)). Reuses Zum's own spawn gating
  outright (`ENEMY_SPAWN_COUNT>=10`, flat-ground probe at its own
  spawn column, `BIGZUM_SLOT_COUNT`=2 concurrent - "スポーン条件は同
  じ") and its exact distance-indexed decel/pause shape (`ZUM_DETECT_
  RANGE`/`ZUM_MID_RANGE`/`ZUM_SPEED_BASE`/`ZUM_ACCEL_TABLE`/`ZUM_
  DECEL_TABLE`/`ZUM_PAUSE_FRAMES` literally reused, not re-derived -
  "アルゴリズムもほぼ同じ"). The 2 post-pause branches replace Zum's
  push-vs-flee coin flip with punch-vs-jump-on:
  - **Punch** (`BZ_STATE=2`): closes any remaining gap the same way
    Zum's own charge does, then holds position once within
    `TANK_PUSH_WIDTH` and delivers a single stronger knockback pulse
    every `BIGZUM_PUNCH_INTERVAL`(16) frames instead of Zum's smooth
    continuous push - "パンチ" read as a discrete hit rather than a
    shove, since no tank-HP/damage system exists anywhere in this
    codebase to actually apply damage to (an inference, not confirmed
    - easy to redirect into real damage later). Shows the `BigZumP`
    pose for `BIGZUM_PUNCH_POSE_FRAMES`(8) after each punch lands
    (`UPDATE_TANK_BIGZUM_PUNCH`, separated from the per-frame move the
    same way `UPDATE_TANK_ZUM_PUSH` is separated from Zum's own).
  - **Jump-on** (`BZ_STATE=1`): a sine-arc jump, `BIGZUM_JUMP_TABLE` -
    same `round(H*sin(pi*t/32))` half-sine construction as the tank's
    own `JUMP_OFFSET_TABLE`, just `H`=32 instead of 24 ("ジャンプは自
    機より高く32ｐｘ サインジャンプ") - while still advancing toward
    the tank's own X. If a 33-frame arc completes while BigZum's X
    still hasn't reached/passed the tank's own (would land ON/in front
    of it), the arc simply restarts from frame0 instead of ending -
    "自機に設置したら連続ジャンプで飛び越え" (chain another full arc
    rather than landing on top; verified via a forced test with a
    99px gap - 2 chain restarts observed before it clears). Only once
    an arc completes with BigZum's X already at/past the tank's does
    it count as landed behind - "自機の後ろを取って地上に降りたら" -
    switching to `BZ_STATE=2` with `BZ_FACING=1` (flipped `BigZum_L`/
    `BigZumP_L` art, now facing right toward the tank) and punching
    from there instead - "後ろからパンチ" (verified: knocks the tank
    rightward once landed behind, vs. leftward while approaching from
    the front).
  - `BZ_FACING` also drives `CHECK_HIT_PAIR_BIGZUM`'s own front/rear
    split - "攻撃判定も同じで後ろしか当たらない" reuses `CHECK_HIT_
    PAIR_ZUM`'s exact front(invincible)/rear(vulnerable) geometry, just
    keyed off `BZ_FACING` instead of `Z_RETREAT==1` (front is whichever
    side BigZum is currently oriented toward - mirrors the same way
    Zum's own `CHPZ_ORIENT_FLEE` does when it turns around). Unlike
    Zum's 1-hit kill, a rear hit only decrements `BZ_HP` (init 5 -
    "耐久5") and only actually destroys it once that reaches 0 -
    verified via 5 forced rear hits (HP 5->4->3->2->1->0, exploding
    only on the 5th) and confirmed the front/rear split itself flips
    correctly once `BZ_FACING=1`.
  Verified: standalone `bigzum_gen.py` run (4 pattern groups emitted,
  base156/172/188/204 as expected); full build assembles clean (2
  `JR`->`JP`/`DJNZ`->`DEC B:JP NZ` conversions needed once the new
  routines grew past 8-bit relative-branch range, same recurring
  pattern as earlier in this file); `render_check.py` clean; a forced-
  state emulator test suite (not just black-box play) directly proved
  all 4 mechanics above (front punch knockback+pose, jump chain-over,
  landed-behind knockback direction, front/rear HP damage with
  orientation flip) since a black-box idle sweep alone couldn't -
  once a BigZum reaches the punch state it never despawns on its own
  (no flee/retreat exit exists for it, unlike Zum - it's meant to be
  fought, not avoided), so both pool slots fill permanently within a
  few spawns under idle input and the RNG coin-flip toward the jump
  branch specifically only got 2 real chances to land in a 12000-frame
  idle run; a 15000-frame *random*-input sweep (driving `cpu.sim_dir`/
  `sim_trig_a`/`sim_trig_b`, not raw `JOY_DIR`/`JOY_TRIGB`/`JOY_TRIGA`
  RAM pokes - those get overwritten by `READ_INPUT`'s own `GTSTCK`/
  `GTTRIG` calls before game logic ever reads them) organically hit
  every state including a full bullet-kill, with no crash/stall
  either way. A visual render (both poses, both facings, forced
  on-screen) confirmed the 32x32 quadrant assembly itself renders
  as a coherent, uncorrupted sprite.
  Several design points were genuine inferences, not directly
  specified, flagged here in case they need correcting: BigZum's own
  32px-tall vertical anchor reuses `TANK_TIER_Y_TABLE[tier]` directly
  with no offset (it shares the tank's own 32x32 convention, unlike
  Zum's 16px-tall `ZUM_Y_OFFSET` derivation); the jump's ground
  reference is the flat spawn tier (`TANK_Y_BASE`) throughout an arc
  rather than a live per-frame terrain probe (a short, self-contained
  maneuver starting from the guaranteed-flat spawn ground, same
  guarantee Zum's own spawn gate already relies on); `BIGZUM_SPAWNX`/
  `BIGZUM_SPAWN_INTERVAL` reuse Zum's own constants verbatim; and the
  punch's actual knockback magnitude (`BIGZUM_PUNCH_KNOCKBACK`=12) and
  cadence are untuned placeholders, easy to retune.
- **BigZum tuning + Zum/BigZum mutual exclusion + durability changes**
  ("BigZumは１体のみ 横並びあるから で、BigZum出現中はZumは出ないよ
  うに ZakoII赤の耐久２ BigZum耐久８に変更 で、Zumのコリジョンは２４
  ｘ２４ 今のままだと飛び越えるのが困難 絵も２４ｘ２４くらいになって
  るんで"):
  - `BIGZUM_SLOT_COUNT` 2->1 - the previous round wrongly assumed
    BigZum's own concurrent-instance limit matched Zum's just because
    "スポーン条件は同じ" (spawn *conditions*, not the count itself).
    The pool/attr-buffer RAM stays sized for the old count rather than
    shrunk (no address renumbering needed for a *smaller* footprint -
    the unused tail simply never gets touched once only 1 slot is ever
    iterated).
  - `ALLOC_ZUM_SLOT` now refuses to spawn a new Zum while any BigZum
    slot is active (`ACT!=0`, alive or mid-explosion) - "BigZum出現中
    はZumは出ないように". One-directional as specified (an already-
    active Zum isn't force-removed if a BigZum spawns after it, and
    BigZum's own spawn gate is untouched - only new Zum spawns are
    blocked). Verified: forcing `BIGZUM_POOL`'s ACT byte to 1 (with
    BigZum's own spawn timer frozen so it can't be a real spawn
    coincidentally refilling it) held Zum's pool at all-zero for 600
    frames; clearing it let a real Zum spawn again 591 frames later
    once the terrain lined up flat at its own spawn column.
  - `ENEMY_RED_HP`(2) - red ZacoII now takes 2 hits instead of the
    usual 1; green is unaffected. Tracked in `E_DX` (offset+7) while
    alive - unused until `E_ACT=2` (explosion drift only reads/writes
    it once actually destroyed), so no slot-size growth (and no
    cascading RAM-address renumbering downstream of `ENEMY_POOL`) was
    needed - same "repurpose an otherwise-idle field" precedent as
    Zum's own `Z_TIMER` doing double duty. A surviving (non-final) red
    hit still consumes the bullet, just with a lighter deflect cue
    (`SOUND_ZUM_DEFLECT`, no score) instead of the full destroy
    sequence. Verified: green explodes on hit1; red survives hit1
    (E_DX 2->1, ACT still 1), explodes on hit2.
  - `BIGZUM_HP_INIT` 5->8 - "BigZum耐久８に変更". Verified: 8 forced
    rear hits, HP counting down 7,6,5,4,3,2,1,0, exploding only on the
    8th.
  - `ZUM_COLLISION_SIZE`(24) - a new, Zum-specific collision constant
    replacing the mismatched mix that was there before: `UPDATE_TANK_
    ZUM_STAND`'s own stand-on-top overlap test used to pair Zum's real
    16px sprite width on one side against the *tank's own* (larger,
    32px) `TANK_PUSH_WIDTH` on the other - an asymmetric combined
    window up to 48px wide that made a clean jump-over needlessly hard
    to time - "今のままだと飛び越えるのが困難 絵も24x24くらいになっ
    てるんで". Now a symmetric 24px box used consistently everywhere
    Zum's own collision extent matters: the stand-on-top overlap test,
    the push-contact boundary (`UPDATE_TANK_ZUM_PUSH`), the spawn-time
    overlap resolution (`ALLOC_ZUM_SLOT`), and the bullet hit-box
    (`CHECK_HIT_PAIR_ZUM`, both axes). `TANK_PUSH_WIDTH` itself is
    untouched and still governs the tank's own collision width
    elsewhere, including BigZum's (not requested to change). Verified:
    the stand-on-top overlap now flips exactly at offset +-24 (true at
    +-23, false at +-24, both sides - was an asymmetric 16/32 split
    before); the push boundary now engages at gap=20 but not gap=25
    (was 32).
  Full regression: standalone forced-scenario tests for every item
  above pass; a 15000-frame random-input sweep across the combined
  changes shows no crash/stall and BigZum never exceeding 1 concurrent
  instance - it also shows Zum and BigZum *can* be on screen together
  (a Zum that spawned first, before BigZum's own conditions were met,
  is never force-removed once BigZum shows up on top of it - expected
  given the gate is one-directional, not a bug); `render_check.py`
  clean.
- **BigZum's collision now matches its real art footprint (bottom-left
  24x24 of the 32x32 canvas), not the full canvas** ("BigZumは３２ｘ
  ３２だが絵は左下２４ｘ２４ コリジョンも同じでそうなってるか") -
  confirmed against both sprite JSONs directly first (ink genuinely
  spans rows8-31/cols~0-24 of the 32x32 grid for both poses - 8 blank
  rows on top, ~8 blank columns on the right, no padding on the left
  or bottom), then confirmed it was NOT reflected in the collision
  code: `CHECK_HIT_PAIR_BIGZUM`'s own bullet hit-box and every push/
  punch-contact range check (`ALLOC_BIGZUM_SLOT`, `UOBZ_PUNCH_MOVE`,
  `UPDATE_TANK_BIGZUM_PUNCH`) were all still sized against the full
  32x32 canvas (`TANK_PUSH_WIDTH`/a hardcoded 31). Fixed with 2 new
  constants: `BIGZUM_COLLISION_SIZE`(24, replacing every one of those
  `TANK_PUSH_WIDTH`/31 uses) and `BIGZUM_ART_Y_OFFSET`(8, added to
  `BZ_Y` only in the bullet hit-box's own Y bound - no X offset needed
  since the art's left edge already sits flush with `BZ_X`, only the
  right ~8 blank columns and top 8 blank rows needed trimming).
  Verified via an isolated direct call into `CHECK_HIT_PAIR_BIGZUM`
  (bypassing the per-frame movement update, which would otherwise
  shift BigZum's own position mid-test and confound a precise
  boundary check): a bullet lands inside the art's own top-left
  corner and a well-inside point, but NOT in the blank top strip
  (`Y+4`) or the blank right strip (`X+28`) - the box genuinely
  tracks the drawn art now, not the padded canvas. The push/punch
  contact boundary was also confirmed to have moved from 32 to 24
  (front: triggers at gap<=24, was 32; behind: triggers at gap<=23 -
  the 1px front/behind asymmetry is an inherited comparison-direction
  quirk, same shape Zum's own push/stand-on checks already have, not
  something newly introduced here).
- **BigZum's punch state was badly broken - the tank could pass
  straight through it, and knockback never stopped no matter how far
  away the tank got** ("パンチに入ったら色々おかしい 自機が突き抜け
  てしまうし かなり離れてもずっとパンチしてきてノックバックが続く
  Zumのパンチ判定を確認 反転非反転で自機が接触範囲周辺にいるか で反転
  後パンチは変わらないが 離れたら接近戦モードにループしてまた飛ぶか
  突っ込んでパンチするか選択して倒されるまでループ"). Root cause,
  found by comparing against "Zumのパンチ判定" (i.e. Zum's own
  equivalent, `UPDATE_TANK_ZUM_PUSH`): `UPDATE_TANK_BIGZUM_PUNCH`'s
  contact test only ever checked a LOWER bound on the gap
  (`TANK_X>=BZ_X-COLLISION_SIZE`), with no upper bound at all - once
  the tank slipped past BigZum to the *other* side, or was simply far
  away but still nominally on the "right" side of that one inequality,
  it stayed "in contact" forever, exactly matching both reported
  symptoms. Fixed with a signed-safe distance calc per facing
  (subtraction + the CPU's own carry flag standing in for "wrong side
  of BigZum entirely" - reused for both the reject check and the
  in-range distance itself), giving a real bounded window on both
  sides, mirroring the "already passed -> skip entirely" guard Zum's
  own push already had.
  A 2nd, deeper problem: even with contact correctly bounded, nothing
  ever happened when the tank genuinely left that range - BigZum just
  sat there holding forever (FACING=1/behind literally skipped its own
  distance check outright and always held, unconditionally). Per
  "離れたら接近戦モードにループして...また飛ぶか突っ込んでパンチする
  か選択して倒されるまでループ", `UOBZ_PUNCH_MOVE` now handles both
  facings symmetrically and reverts fully to `STATE=0` (approaching)
  whenever either (a) the tank slips to the opposite side of whichever
  side BigZum currently expects it on (the same "passed through" case,
  now caught at the *movement* level too, not just the knockback
  level), or (b) the gap grows past `BIGZUM_GIVEUP_RANGE` (reuses
  `ZUM_DETECT_RANGE`(80), an inferred choice - genuinely "ran away" vs.
  ordinary post-knockback separation still within contact-chasing
  range). This in turn required `STATE=0`'s own approach logic to
  become bidirectional - it used to assume BigZum was always
  approaching from the right (`BZ_X>=TANK_X`), true only for the very
  first spawn approach; re-entering it after a give-up (now possibly
  from either side) needed FACING/direction recomputed fresh each
  frame instead of assumed. The old "despawn if the next step would
  underflow X" fallback (copied from Zum's own off-screen-exit logic,
  now unreachable in normal play since the pause always triggers well
  before that) was replaced with a plain clamp at each screen edge
  instead - BigZum should never simply vanish, only ever be destroyed.
  Verified via forced scenarios for both facings: teleporting the tank
  to the opposite side mid-punch stops all further knockback
  immediately (was: continued indefinitely); teleporting it far away
  on the correct side triggers a give-up, followed by BigZum visibly
  re-approaching (X trending back toward the tank) and cycling back
  through pause/reroll (states 0/3/1-or-2 all observed) rather than
  freezing in place. Full regression: 15000-frame random-input sweep,
  no crash/stall; `render_check.py` clean.
- **3 more BigZum fixes after real-hardware play: the tank genuinely
  could not jump over it, its own jump could sink into the ground, and
  it re-engaged instantly after a pass-through with no breathing
  room** ("まずジャンプで地面に潜り込む場合がある で、自機がBigZumを
  飛び越えられない ２４ｐｘなら飛び越えられるはず 次にBigZumが通過
  してパンチかジャンプかまで時間をおいてくれ 自機と速度が噛み合って
  全くバックが取れない ジャンプで越えられないのも要因だが 飛び越え
  られないので通貨はほぼ画面左端に押し込まれた時しかない状態"):
  - `UPDATE_TANK_BIGZUM_PUNCH` was missing the exact `JUMP_ACTIVE`
    guard `UPDATE_TANK_ZUM_PUSH` already has - the knockback kept
    firing every single frame regardless of whether the tank was
    airborne, so a jump attempt just got punched straight back down/
    away before it could ever clear BigZum's own (correctly 24px-tall
    since the previous round) collision box - "自機と速度が噛み合っ
    て全くバックが取れない" was this: the tank could never open enough
    separation to even line a jump up in the first place. Now
    suspended entirely while jumping, exactly like Zum's own push -
    BigZum still keeps closing in underneath regardless (only the
    knockback itself pauses, not its approach, same as Zum sliding
    under a jumping tank). Verified: knockback stays fully suspended
    for the whole duration `JUMP_ACTIVE` is set, resumes the instant
    it clears.
  - "まずジャンプで地面に潜り込む場合がある" - `UOBZ_JUMP_MOVE`'s own
    ground reference was a single fixed value (`TANK_Y_BASE`, tier3's
    own Y - the LOWEST of the 4 tiers, i.e. numerically the largest)
    used for every jump regardless of which tier BigZum actually
    stood over - jumping from any higher tier undershot that tier's
    own real (smaller-Y) ground line, reading as sinking into it.
    Extracted the tier-probe half of `UOBZ_TERRAIN_FOLLOW` into a
    shared `UOBZ_GET_GROUND_Y` (returns the CURRENT tier's own ground
    Y, probed fresh - same walk `UPDATE_TERRAIN_COLLISION`/Zum's own
    terrain-follow use) and had the jump arc read it live every frame
    instead of the fixed constant. Verified: forcing tier0 (Y=132)
    solid under a jumping BigZum (with the poke re-applied right as
    `UPDATE_BIGZUM_ALL` runs each frame, so `MAINLOOP`'s own periodic
    `IDCACHE` refresh from real terrain data can't race it) produces
    an exact symmetric 132-anchored parabola (peak Y=100, i.e.
    132-32) that never exceeds 132 - the old bug would have anchored
    to 156 (tier3) throughout instead.
  - "次にBigZumが通過してパンチかジャンプかまで時間をおいてくれ" - a
    new `BIGZUM_GIVEUP_PAUSE_FRAMES`(reuses `ZUM_PAUSE_FRAMES`) beat:
    right after a give-up (the tank slipping past, or running far
    enough away - see the previous round's own give-up entry),
    `STATE=0`'s own approach logic now sits fully motionless for this
    many frames before it starts running at all, reusing `+3`(TIMER,
    otherwise idle in this state) as the countdown - on top of, not
    instead of, the ordinary pre-decision pause once back in near-tank
    range. Verified: `BZ_X` stays frozen for exactly
    `BIGZUM_GIVEUP_PAUSE_FRAMES` frames immediately after a forced
    pass-through before it starts moving again.
  Full regression: 15000-frame random-input sweep, no crash/stall;
  `render_check.py` clean.
- **Diagnosed why the jump-over still never worked despite the
  `JUMP_ACTIVE` fix, shrunk BigZum's own collision to make it actually
  clearable, added the missing Zum-style stand-on-top auto-jump, and
  relaxed Zum's own spawn gate** ("飛び越えられない原因わかった 接触
  状態ではパンチでノックバックされ元々自機ジャンプ頂点のみなので飛び
  越える条件が成立しない なのでシンプルにBigZumのコリジョンを２４ｘ
  １６に これで飛び越えられる もちろん自機が乗っかった場合はZumと同
  じでオートジャンプ で、Zumは殆ど出ないので条件緩和する 赤緑ZakoII
  になったら何時でもスポーンできること"):
  - The collision box's own height had exactly matched the tank's own
    24px jump peak (`JUMP_OFFSET_TABLE`) - a bare tie with zero real
    margin, not a usable window even with the knockback-during-jump
    bug already fixed. `BIGZUM_COLLISION_HEIGHT`(16, was 24, same as
    the width) shrinks it for gameplay past what the raw art pixels
    alone would justify - "シンプルにBigZumのコリジョンを24x16に" -
    giving a real jump 8px of clearance instead of none.
    `BIGZUM_COLLISION_Y_OFFSET`(16, was `BIGZUM_ART_Y_OFFSET`=8) moves
    with it, keeping the box flush with the sprite's own bottom row.
    Applied to both `CHECK_HIT_PAIR_BIGZUM`'s own bullet hit-box and
    (implicitly, via the shared width constant) every push/punch
    contact check - only the height/Y-offset actually changed, the
    24px width is unaffected. Verified: the tank's own jump-peak Y
    (132, ground 156 minus the 24px jump offset) sits well above the
    collision box's own top (144 = 156+16-28) with real margin, and no
    longer trips the new stand-on-top clamp at that height.
  - "もちろん自機が乗っかった場合はZumと同じでオートジャンプ" - added
    `UPDATE_TANK_BIGZUM_STAND`, mirroring `UPDATE_TANK_ZUM_STAND`
    exactly (symmetric horizontal overlap test against the same
    `BIGZUM_COLLISION_SIZE` width, clamp `TANK_Y_CUR` to rest on the
    collision box's own top) but reusing the SAME shared
    `TANK_ZUM_STANDING` flag `UPDATE_JUMP`'s own auto-land-restart
    logic already reads - no new plumbing needed, since that logic
    doesn't care which enemy the tank is actually parked on. Careful
    ordering detail: this routine only ever SETS the flag, never
    clears it, since `UPDATE_TANK_ZUM_STAND` (called immediately
    before it every frame) already does that reset once for the whole
    frame - clearing it again here would silently undo a genuine
    Zum-stand result. Verified: standing directly on top clamps to the
    expected Y (144) and sets the flag; a clean jump over does neither.
  - "Zumは殆ど出ないので条件緩和する 赤緑ZakoIIになったら何時でも
    スポーンできること" - reversed the "BigZum active blocks new Zum
    spawns" gate added 2 rounds ago: BigZum ended up occupying the
    screen for a large enough share of playtime (especially once its
    own give-up/re-engage loop made it far more persistent) that Zum
    almost never got a spawn window at all. `ALLOC_ZUM_SLOT` no longer
    checks BigZum's own state - only the terrain/free-slot conditions
    gate a spawn attempt now, same as before that gate existed.
    Verified: forcing BigZum permanently active no longer prevents a
    real Zum spawn (observed within ~1200 frames, vs. never before).
  Full regression: 15000-frame random-input sweep, no crash/stall;
  `render_check.py` clean.
- **The previous round's "let Zum spawn even while BigZum is active"
  fix was the wrong fix - reverted, and re-diagnosed the actual
  relaxation wanted** ("BicZum出現中にZumは出さないでくれ キャラが
  消えてしまうしテスト出来ない Zum制限緩和は地形が1番下にある時と
  言う部分をやめると言うこと"):
  - `ALLOC_ZUM_SLOT`'s "refuse while BigZum is active" gate is back -
    letting both coexist caused something to visibly disappear and
    broke testing, so this direction was never the right fix for
    "Zumは殆ど出ない" in the first place.
  - The actual relaxation intended: `ZUM_TERRAIN_OK` used to require
    the terrain be flat specifically at the very LOWEST tier
    (`IDCACHE_T0/T1/T2` all BLANK, i.e. nothing climbed above tier3
    anywhere on the visible track) - "地形が1番下にある時と言う部分"
    - which is a narrow window on a track that spends plenty of time
    climbed above that. Now accepts flat, steady ground at WHICHEVER
    tier is actually on top at the spawn column (same walk-down-tiers
    probe `UPDATE_TERRAIN_COLLISION`/`UOZ_TERRAIN_FOLLOW` use, just
    checking the id found there instead of insisting it land on tier3
    specifically). Verified: forcing tier0 (the highest platform, not
    the lowest) solid and steady at the spawn column now lets a Zum
    spawn there; forcing every tier to a climb-marker id everywhere
    still correctly refuses (no regression on the "must be steady, not
    mid-climb" half of the original check).
  Full regression: 15000-frame random-input sweep, no crash/stall,
  Zum and BigZum never observed active simultaneously (as intended
  again); `render_check.py` clean.
- **A brief stop before BigZum actually reverses which side it's on**
  ("BigZumが反転する場合は少し動きを止めてから反転し改めて接近モードに
  ループ ６フレとまること すぐに反転して向かってくると自機から離れ
  なくなる"). `STATE=0`'s own approach logic recomputes FACING every
  single frame from whichever side of the tank BigZum is currently on
  (needed for the bidirectional re-approach a few rounds back), and
  used to commit + start moving toward the new side in that exact same
  frame the moment the tank crossed over - reads as BigZum reversing
  and closing back in instantly, giving the player no real window to
  put distance between themselves and it. New `STATE=4` (flip-pause):
  the moment a frame's freshly-computed side first disagrees with the
  currently-stored `FACING`, BigZum stashes the pending value (`+5`,
  idle outside an explosion) and freezes fully motionless for
  `BIGZUM_FLIP_PAUSE_FRAMES`(6) before actually committing the flip
  and handing back to `STATE=0` to resume approaching from there.
  Verified: teleporting the tank to BigZum's other side shows it enter
  `STATE=4` immediately (facing not yet changed), stay frozen in place
  through the countdown, then commit the new facing and resume moving
  only after; staying on the same side the whole time never touches
  `STATE=4` at all. Full regression: 15000-frame random-input sweep,
  no crash/stall; `render_check.py` clean.
- **Flip-pause lengthened 6->10 frames, and front-invincibility
  suspended entirely while jumping** ("停止を１０フレに でBigZumジャン
  プ中は前面攻撃無効が解除されてヒットするように変更"):
  - `BIGZUM_FLIP_PAUSE_FRAMES` 6->10.
  - `CHECK_HIT_PAIR_BIGZUM`'s own front(invincible)/rear(vulnerable)
    split is now skipped entirely whenever BigZum's own `STATE=1`
    (jumping) - any hit, from either side, counts as a rear
    (damaging) hit while airborne; the ordinary front/rear rule still
    applies in every grounded state (approach/pause/punch/flip-pause).
    Verified via a direct, isolated `CHECK_HIT_PAIR_BIGZUM` call
    (bypassing the per-frame movement update, since BigZum's own X-
    chase during a jump would otherwise drift it away from a bullet
    aimed at a fixed position before the real collision check ran,
    confounding a precise same-frame test): a front-side hit while
    `STATE=1` now damages (HP 8->7) instead of deflecting; the
    identical front-side hit while grounded (`STATE=0`) still
    deflects with no damage, confirming no regression to the ordinary
    rule; rear-side hits damage in both states as before.
  Full regression: 15000-frame random-input sweep, no crash/stall;
  `render_check.py` clean.
- **"Kin-kin" deflect sound raised to full volume, and silenced for a
  BigZum hit that damages but doesn't destroy it** ("キンキン音量アッ
  プ BigZumにダメージ入った場合はキンキン音は無しで"):
  - `SOUND_ZUM_DEFLECT`'s own peak (`SND_TIMER` init, doubling as
    channel A's volume - see `SND_TIMER`'s own comment) 12->15 - the
    PSG's own hardware ceiling (register8's volume field is 4 bits,
    0-15), nothing higher to raise it to.
  - `CHECK_HIT_PAIR_BIGZUM`'s own `CHPBZ_REAR` no longer plays
    `SOUND_ZUM_DEFLECT` on a rear hit that decrements `BZ_HP` without
    reaching 0 - that reused the same "kin-kin" cue as a front hit's
    own full-absorb deflect, and per direct instruction a genuine
    damaging hit should stay silent instead (only the final, actually-
    destroying hit still plays `SOUND_DESTROY`). Front hits (still
    fully invincible/absorbed, no HP change) are untouched - `CHPBZ_
    FRONT` keeps its own `SOUND_ZUM_DEFLECT` call. Verified via
    isolated `CHECK_HIT_PAIR_BIGZUM` calls: a damaging (non-lethal)
    rear hit leaves `SND_TIMER` at 0 (no sound fired); the lethal rear
    hit still fires `SOUND_DESTROY` (`SND_TIMER`=15); a front hit still
    fires `SOUND_ZUM_DEFLECT` at the new peak (15).
  Full regression: 15000-frame random-input sweep, no crash/stall;
  `render_check.py` clean.
- **`GAME_TICK` (the displayed HUD counter) was advancing 8x faster
  than intended - fixed to match Stage1's own cadence** ("では表示し
  てるタイマーは何の数字だ この件で気づいたがカウントがものすごく早
  い Stage1は地形書き換え8回に1回カウントする作り すべての基準はこの
  カウント これはスケジュールエディタで指定するため カウント表示を
  Stage1と同様に修正" - surfaced while investigating an unrelated
  question about frame-pacing/interrupts). `GAME_TICK` used to
  increment (and redraw) once every single `MAINLOOP` pass,
  unconditionally - but the raw per-pass `TICK` counter only actually
  advances the terrain scroll once every 8 passes (`AND 07h`, see
  `MAINLOOP`'s own terrain-rewrite gate) - the loop runs far more
  passes than real "game frames" in Stage1's own sense. Moved the
  increment+`GAME_TICK_DISPLAY` call inside that same `AND 07h==0`
  branch, so it now advances in lockstep with the actual terrain-
  scroll-step rate, matching Stage1's own design ("地形書き換え8回に1
  回カウントする作り") - this is the unit the schedule editor actually
  schedules events against, so this wasn't just cosmetic, it was
  running 8x too fast to mean anything as a scheduling reference.
  Verified: sampling `GAME_TICK` every frame over 24 raw `TICK`s now
  shows exactly 3 real increments (was 24), each landing exactly on
  the frames where raw `TICK MOD 8==0`. Full regression: 15000-frame
  random-input sweep, no crash/stall; `render_check.py` clean.
- **Full rollback of an over-ambitious round (white hit-flash + Etank +
  Flyer + BigZum HP retune, all at once), then reimplemented one piece
  at a time** - real-hardware testing on that round kept surfacing new
  problems (a `STACKTOP`/MSX-BIOS RAM collision, then a genuine Etank/
  BigZum shared-VRAM race once the first fix was in) faster than they
  could be pinned down, so per direct instruction the whole round was
  reverted back to this exact tree (commit `bfb3651`) rather than
  patched forward again - "全然変わってない バグりまくって もうむちゃ
  くちゃで原因特定できないのでロールバックしろ 1つずつ実装し直す".
  Then, per a follow-up naming which pieces to redo and in what order:
  > 1と2は問題があるとは思えないんで実装
  > なので4をテスト実装
  > BigZum出現時はFlyerは出ない
  > で、Flyerの速度は2
  > 右から出て画面左まで行き反転
  > 自機に向かって降りてくる
  ("1" = BigZum HP 8->5, "2" = the white hit-flash, "4" = Flyer -
  Etank, "3", is deliberately skipped this round; the reverted round's
  own Etank/pattern-VRAM-sharing mechanism was the direct cause of the
  worst bug, so it isn't being touched again yet).
  - **BigZum HP**: `BIGZUM_HP_INIT` 8->5, identical to the reverted
    round's own change - re-implemented byte-for-byte.
  - **White hit-flash**: `FLASH_COLOR`(15/white)/`FLASH_DURATION`(6
    frames) constants, applied to ZacoII red (reuses its own idle
    `E_DY` field), BigZum (`BIGZUM_SLOT_SIZE` grown 12->13 for a new
    `+12` field, still fits the old 24-byte reservation), and the tank
    itself (new `TANK_FLASH_TIMER`, triggered only by BigZum's own
    punch connecting - no tank-HP system exists anywhere in this
    codebase, same inference as before) - functionally identical to
    the reverted round's own implementation, since nothing about it was
    ever actually reported as broken.
  - **Flyer, reimplemented from scratch, deliberately simpler than
    before**: singleton (`FLYER_SLOT_COUNT`=1, not 2) with its OWN
    dedicated permanent pattern allocation (codes220-251, both facings)
    - no VRAM-sharing scheme this time, since that mechanism was the
    direct cause of the worst bug in the reverted round and Etank isn't
    being reimplemented yet to need it. New spawn gate, "BigZum出現時は
    Flyerは出ない" - `ALLOC_FLYER_SLOT` refuses while `BIGZUM_POOL` is
    active, same `ALLOC_ZUM_SLOT`-style precedent, one-directional only
    (Flyer has nothing for `ALLOC_BIGZUM_SLOT` to clobber, so no
    reverse gate is actually needed this time, unlike the reverted
    Etank/BigZum pair). Speed is now an explicit `FLYER_SPEED`=2
    ("速度は2") rather than an untuned guess. 2-phase movement (down
    from the reverted round's own 3): `PHASE`=0 cruises left at a fixed
    height until the screen's own left edge, clamps to X=0 and reverses
    into `PHASE`=1; homing steps toward the tank's own current X AND Y
    every frame on both axes ("自機に向かって降りてくる" - the tank can
    be anywhere vertically, not just below, so this isn't a fixed
    downward-only vector) and simply holds position once it matches -
    no exit/despawn-on-reaching-the-tank phase this round, since that
    wasn't restated and re-inventing it risked repeating the same
    "adding more than was asked" pattern that led to the rollback;
    flagged as an open question for a follow-up round. HP4 (carried
    over from the original, reverted spec, not contradicted this
    round), hit-flash included (participates in the general mechanism
    above), full 32x32 bullet-hit box (no shrink specified).
  - New RAM (`FLYER_POOL`..`FLYER_DRAW_COLOR`, 0F340h-0F35Dh, plus
    BigZum's own new `BIGZUM_DRAW_COLOR` at 0F33Fh) stays well clear of
    the real 0F380h MSX BIOS-work-area boundary this time -
    `STACKTOP` itself was left completely untouched at 0F380h, with an
    explicit warning comment added there against ever growing past it
    again (see the reverted round's own freeze postmortem, still
    recorded further down in this file).
  - New hw sprite slots: Flyer 20-23 (1 instance x4, right after
    BigZum's own 12-19) - total hw sprite usage now 0-23 of the
    hardware's own 32-slot ceiling (well down from the reverted round's
    0-29, since Etank doesn't exist and Flyer is singleton this time).
  Verified: a 30-case targeted test suite (isolated-subroutine calls)
  covering `BIGZUM_HP_INIT`=5; ZacoII red/BigZum/tank hit-flash
  (trigger, color override, timer decay, all 3 checked directly);
  `ALLOC_FLYER_SLOT`'s own BigZum-active gate; Flyer's own spawn-time
  field init; cruise movement at the correct speed; the left-edge
  clamp+phase-flip; homing on both axes in both directions (tank
  below/right AND above/left, plus the exact-match hold case); non-
  lethal hit HP-decrement+flash vs. lethal explode - all pass. A
  forced-spawn render (via the real `ALLOC_FLYER_SLOT`, not a hand-
  poked slot) shows a clean cyan Flyer sprite with no corruption. Full
  regression: 20000-frame random-input sweep (`sim_dir`/`sim_trig_a`/
  `sim_trig_b`) with no crash/stall - BigZum flash/explosion and tank
  flash all naturally observed, Flyer reached both movement phases and
  its own flash; a separate 8000-frame idle sweep also clean; `render_
  check.py` clean. **Correction to the claim just above**: that same
  sweep actually DID observe BigZum and Flyer active at the same time
  (`ALLOC_FLYER_SLOT`'s own gate only blocks a NEW Flyer while BigZum
  is active - nothing yet stopped a NEW BigZum from spawning while an
  already-active Flyer was still alive, the identical asymmetric-gate
  shape the reverted round's own Etank/BigZum bug had) - reported to
  the user as a question rather than silently left in, and addressed
  in the follow-up entry immediately below.
- **Flyer's own homing reworked from continuous tracking to a locked-
  once direction, plus BigZum/Flyer exclusivity made properly
  bidirectional** - direct follow-up correcting both of the open items
  from the entry above:
  > まあ良いだろう バグは出なかった
  > Flyerは反転時に自機には向かうが
  > 一度方向を決定したら自機は追跡しない
  > 自機に被らないY位置まで来たら右に消える
  > で、BigZumが同時に出てきてる
  > お前もしかしてまたエネミーバッファ使わず個別にやってんじゃないだろうな
  > バッファにBigZumがあったら登録しないんだぞ
  > てか全ての敵はスポーン条件外はそもそも登録しない
  > そうしないと
  > BigZumやFlayerが出続けるだろ
  - **Homing**: PHASE=1 used to re-read `TANK_X`/`TANK_Y_CUR` and
    re-aim every single frame - a true continuous heat-seeking track.
    "一度方向を決定したら自機は追跡しない" - the vertical direction is
    now decided exactly ONCE, at the instant of reversal (`UOFL_
    CRUISE_MOVE`'s own left-edge clamp), from wherever the tank's Y
    happened to be at that moment - stashed in +6 (idle while alive,
    same "repurpose an otherwise-idle field" precedent used throughout
    this file) - and simply held constant every frame afterward.
    Horizontal movement was always a flat rightward `FLYER_SPEED` once
    reversed anyway, so only the vertical axis needed the lock.
    "自機に被らないY位置まで来たら右に消える" - a 3rd `PHASE` (2=exit)
    is back: once Flyer's own Y clears the tank's own Y by more than
    `FLYER_CLEAR_Y`(32, untuned/inferred - matches both sprites' own
    32px height) in either direction, PHASE advances to 2 and Flyer
    flies straight right, ignoring the tank entirely, until off the
    right edge, then despawns - same shape the original (reverted)
    request's own exit condition had, just re-derived from this
    round's own simpler request rather than copied forward.
  - **BigZum/Flyer exclusivity, now bidirectional**: `ALLOC_BIGZUM_
    SLOT` also refuses to spawn while `FLYER_POOL` is active - the
    missing other half of "BigZum出現時はFlyerは出ない", the same fix
    already applied once for Etank/BigZum before the full rollback.
    "お前もしかしてまたエネミーバッファ使わず個別にやってんじゃないだ
    ろうな...全ての敵はスポーン条件外はそもそも登録しない" - both
    `ALLOC_*` routines already DO gate registration strictly through
    their own pool-buffer scan (no enemy has ever registered outside
    that path in this file); what was actually missing was this one
    specific cross-enemy exclusion check, now added the same way its
    Zum/BigZum and (reverted) Etank/BigZum precedents both work: each
    side's own `ALLOC_*` reads the OTHER pool's own ACT byte directly.
  Verified: 17 targeted tests (isolated-subroutine calls) covering the
  new bidirectional gate (both directions, both the refuse and the
  allowed case), the direction-lock at reversal (tank below vs. above
  at the instant of reversal, 2 separate cases), homing now ignoring a
  simulated tank move after the lock (moved the tank to the opposite
  side mid-flight and confirmed Flyer's own step didn't follow it), the
  clearance->exit transition (both the "still close, stays homing" and
  "far enough, switches to exit" cases), and exit-phase movement/
  despawn - all pass. Full regression: 20000-frame random-input sweep,
  no crash/stall, BigZum and Flyer never observed active at the same
  time this time; 8000-frame idle sweep also clean; `render_check.py`
  clean.
- **Flyer never actually appeared to descend - the clearance->exit
  check from the entry above compared raw, direction-blind distance and
  fired on the very FIRST frame of homing** ("Flyerが下に降りてこない
  ぞ"). Traced by stepping a forced Flyer spawn frame-by-frame and
  printing its own X/Y/PHASE every frame: `PHASE` flipped straight from
  1(home) to 2(exit) after a single 1px step - `|Flyer_Y-Tank_Y|` is
  just as large right after reversing (before any real descent has
  happened) as it is after actually flying past and clearing the tank,
  so the old check couldn't tell "hasn't arrived yet" from "already
  passed through" and always picked the first frame it saw a big gap,
  which is immediately. Fixed by checking the correct SIDE of the
  tank's own Y for the locked travel direction instead of raw distance
  - descending needs `Flyer_Y>=Tank_Y+FLYER_CLEAR_Y`, ascending needs
  `Flyer_Y<=Tank_Y-FLYER_CLEAR_Y` - either can only become true after
  genuinely crossing the tank's own Y in that direction. This assembler
  has no `JP M`/`JP P` (only Z/NZ/C/NC), so the locked direction's own
  sign is read via `CP 128` instead (a small positive magnitude like
  `FLYER_VY` is always <128; its two's-complement negative encoding is
  always >=128). Verified: the same frame-by-frame trace now shows
  continuous, monotonic descent from `FLYER_CRUISE_Y`(64) all the way
  past the tank's own Y before switching to exit (125 frames to fully
  cross the screen and clear the tank, vs. the old bug's 2); a forced-
  spawn render mid-flight visibly shows the sprite well below its own
  cruise altitude, approaching the tank. All 17 targeted tests (mostly
  unchanged, since the fix only changes WHEN the exit fires, not the
  other mechanics) still pass. Full regression: 20000-frame random-
  input sweep, no crash/stall; `render_check.py` clean.
- **A descending Flyer's own exit could still land it inside the
  terrain while flying back to the right edge** ("右端に帰ってく時に
  地形に突っ込んでる 地形に入らないように") - the fix above let a
  descending Flyer overshoot to `Tank_Y+FLYER_CLEAR_Y` before exiting,
  which is safe while the tank stands on a higher tier but not on its
  own lowest one: `Tank_Y`(156)+32=188 lands well past the true ground
  line there (184 at worst, `(20+tier)*8` - see `TANK_GROUND_OFFSET`'s
  own derivation), and `UOFL_EXIT_MOVE`'s own fixed-Y rightward flight
  then stayed at that sunk-in-terrain depth the whole way to the edge.
  Added `FLYER_DESCEND_LIMIT_Y`(112, tier-independent) as a hard cap on
  a descending Flyer's own Y - `Flyer_Y+32`(its own sprite height)=144
  stays comfortably above the highest possible ground line (160,
  tier0) regardless of which tier the tank actually happens to be
  standing on, so exiting always happens at a safe sky altitude. The
  ordinary tank-relative clear check still applies underneath the cap
  (whichever condition is reached first wins) so a higher-tier tank
  still gets the original, closer clearance. Ascending is untouched
  (moving away from the ground, no terrain risk either way). Also
  closed a related, not-yet-reported edge case found while re-deriving
  this: DY=0 (the tank exactly level with Flyer at the reversal
  instant, an unlikely tie) used to leave `PHASE`=1 forever with no
  exit condition ever true, silently wrapping `X` past 255 forever
  instead of ever despawning - now exits immediately instead, same as
  reaching either clearance condition. Verified: forcing the tank to
  its own worst-case lowest tier (Y=156) before a Flyer spawn and
  tracing frame-by-frame shows Y descending smoothly and then holding
  exactly at 112 (never exceeding it) for the entire rightward exit
  flight. 5 new targeted tests (the cap itself, the DY=0 fix, and that
  ascending stays unaffected in both the "still close" and "moved
  away" cases) all pass, alongside the existing 17. Full regression:
  20000-frame random-input sweep, no crash/stall; `render_check.py`
  clean.
- **2 old BigZum bugs recurring: feet sinking a few px into the ground,
  and a punch-state slip-through when pushed toward it** - "では前から
  あるバグ再発の修正 まずBigZumの表示位置 足元が地面に数ｐｘめり込ん
  でる ただ地形の上に表示するだけがなぜこうなるか調べて修正 次にまた
  BigZumパンチ中に自機をBigZum方向に押すとすり抜けが起こってる 抜け
  ないようにしろ パンチモーション中にガードされてないからだな".
  - **Feet sinking into the ground**: BigZum's own Y anchor directly
    reused `TANK_TIER_Y_TABLE` on the assumption it needed "no offset"
    (same 32px-tall convention as the tank) - but that table's own
    values are NOT a pure geometric anchor. `TANK_Y_BASE`'s own
    derivation ("row23 top(184) - tank height(32) + landing
    offset(3+1)") bakes in a +4 fudge specifically compensating for the
    TANK's own sprite art having ~5px of blank rows at its own bottom
    (`sprites/TankF.json`: ink stops at row26 of 32 - confirmed
    directly). BigZum's own art has no such gap - its own ink runs all
    the way to row31 of 32 (confirmed directly, matching the earlier
    "絵は左下24x24" finding) - so reusing the tank's already-
    compensated anchor pushed BigZum's real, un-padded feet that same
    ~4px below the true ground line. New `BIGZUM_Y_OFFSET`(4)
    subtracted wherever BigZum's own Y is derived from `TANK_TIER_Y_
    TABLE` - `UOBZ_GET_GROUND_Y` (the single shared source for both
    `UOBZ_TERRAIN_FOLLOW`'s own easing target and `UOBZ_JUMP_MOVE`'s
    own jump-arc ground reference) and `ALLOC_BIGZUM_SLOT`'s own spawn-
    time init. Verified: a forced spawn now sets Y=152 (was 156);
    `UOBZ_GET_GROUND_Y` returns the same corrected value; a forced-
    spawn render shows BigZum's own feet flush with the ground, same as
    the tank's own footing.
  - **Punch-state slip-through**: `UPDATE_TANK_BIGZUM_PUNCH`'s own
    knockback only fired once every `BIGZUM_PUNCH_INTERVAL`(16) frames
    - "パンチモーション中にガードされてないからだな" - between pulses,
    nothing stopped the tank from freely walking deeper into contact.
    16 frames x the tank's own ~1.5px/frame average speed = 24px -
    exactly `BIGZUM_COLLISION_SIZE`, wide enough to cross the entire
    box in a single uncontested gap and come out "already passed" the
    other side, after which the existing "already passed, no longer
    blocks" check (itself a real, working fix from an earlier round)
    simply let it through for good. Added a hard, unconditional
    boundary clamp - independent of the knockback cadence - that pins
    `TANK_X` flush at BigZum's own outer collision edge every single
    frame it's within range, same continuous-clamp shape `UPDATE_TANK_
    ZUM_PUSH` already uses for Zum. Verified: isolated calls confirm
    the wall fires even mid-cooldown and pulls an already-too-deep
    `TANK_X` back to the boundary in one frame, on both sides
    (`FACING`=0 and 1); a full natural-flow simulation - spawn BigZum,
    let it approach and reach `STATE`=2 on its own, then hold the stick
    toward it continuously for 1900 frames - never once let `TANK_X`
    cross past `BZ_X`, settling the tank pinned at the boundary
    (eventually against the screen's own left edge) instead. (An
    earlier attempt at this same test, forcing `STATE`=2 directly from
    far away, wasn't a valid reproduction - it immediately triggered
    `UOBZ_PUNCH_MOVE`'s own give-up-and-revert-to-STATE=0 logic since
    the forced distance exceeded `BIGZUM_GIVEUP_RANGE`, so the fix
    (STATE=2-only by design, matching the report's own "パンチモーショ
    ン中に") was never actually exercised there - the natural-flow
    version is the one that matters.) Full regression: 20000-frame
    random-input sweep, no crash/stall; `render_check.py` clean.
- **BigZum now shakes off a tank parked motionless on top of it, plus
  new BulletF/BulletU art and a gray recolor** - with 2 attached 8x8
  sprite JSONs (`BulletU_8x8.json`, `BulletF_8x8.json`, both fg14/bg1):
  > 次はBigZumの上に自機が乗ったそのまま動かないとずっと乗りっぱなし
  > なので右にジャンプして振り払うように
  >
  > バレットUとFの変更
  > カラーもグレーに
  - **Shake-off**: `UPDATE_TANK_BIGZUM_STAND`'s own auto-land-on-top
    clamp keeps `JUMP_ACTIVE` perpetually re-engaged while the tank
    stays parked (`JUMP_LANDING_RESTART_FRAME`), and nothing on
    BigZum's own side ever reacted to that - a player who just sits
    there could ride forever. New `BIGZUM_SHAKE_STAND_FRAMES`(90,
    untuned/inferred) counter in +11 (`PUNCH_COOLDOWN`, otherwise idle
    during `STATE`=0 - never both at once), incremented every frame
    `TANK_ZUM_STANDING` is set while `STATE`=0, reset to 0 otherwise.
    Once it reaches the threshold, forces `STATE`=1 (jump) with a
    distinct "shake-off" marker (also +11, repurposed the instant the
    jump starts) that makes `UOBZ_JUMP_MOVE`'s own arc always move
    RIGHT at `BIGZUM_JUMP_XSPEED` regardless of the tank's position -
    the ordinary chase-the-tank jump logic would barely move at all
    with the tank centered directly on top, since "distance to tank" is
    ~0. A shake-off jump also always lands straight back into `STATE`=0
    once the arc completes (no "didn't clear yet, chain again" retry,
    no punch transition - the point was just to relocate, not engage),
    clearing the marker. The ordinary jump-trigger (`UOBZ_PAUSE_ROLL`)
    now also explicitly clears +11 on the way in, so a stale marker
    from an earlier shake-off can never leak into a genuinely normal
    jump.
  - **Bullet art + color**: `sprites/BulletF.json`/`BulletU.json`
    replaced with the 2 attached files (`bullet_gen.py` picks them up
    automatically, no code changes needed there). Color changed black
    (1) -> gray (14) in all 3 places it's set: `BULLET_U_COLOR` (the
    diagonal shot's own hw sprite color) and both `BULLET_SKY_
    COLORBYTE`/`BULLET_ROCK_COLORBYTE` (the straight shot's own 2 BG
    color groups, matched against sky/rock backgrounds respectively) -
    "カラーもグレーに".
  Verified: 7 targeted tests (isolated-subroutine + a natural per-frame
  accumulation loop) covering the stand-timer's own increment/reset,
  the threshold-triggered transition into a shake-off jump (`STATE`=1,
  marker set, `JUMPFRAME` reset), rightward movement even with the tank
  centered directly on top (where the ordinary chase logic would move
  0px), and that a genuinely normal jump clears a stale marker - all
  pass (1 RNG-dependent sub-case skipped when that particular run
  happened to roll punch instead of jump - not itself part of this fix).
  Bullet color confirmed directly by reading the rendered VRAM color
  byte for both a live F shot (fg=14) and a live U shot (hw sprite
  color=14) after firing in each direction. Full regression: 20000-
  frame random-input sweep, no crash/stall; `render_check.py` clean.
- **Shake-off still never actually happened, plus bullet color to light
  red**:
  > 振り払いが発生しないな
  > バレットカラーをライトレッドに変更
  - **Shake-off, root cause #1 (STATE-scoping)**: the previous round's
    counter lived in +11 and was only ever incremented inside `UPDATE_
    ONE_BIGZUM`'s `STATE`=0 (approach) branch. In practice the tank
    lands on top while BigZum is in ANY state, and once it lands during
    `STATE`=2 (punch), `UOBZ_PUNCH_MOVE`'s own "already in contact -
    hold" branch keeps it there indefinitely - an overlapping tank never
    separates far enough to trip the give-up-range check - so the
    `STATE`=0-only counter simply never ran at all in what's actually
    the most common real scenario (punch range and stand-on-top range
    overlap almost entirely). Moved the whole check to the very top of
    `UPDATE_ONE_BIGZUM`, before any state dispatch (only skipped while
    already `STATE`=1/jumping, so an in-progress arc is never
    interrupted), and moved the counter off +11 onto +6 (`DY`, explosion
    drift - idle outside `ACT`=2) so it no longer collides with +11's
    real job as `PUNCH_COOLDOWN` during `STATE`=2; +11 now serves only
    as the shake-off-jump-in-progress marker.
  - **Shake-off, root cause #2 (flickering `TANK_ZUM_STANDING`)**: fixing
    #1 alone still wasn't enough - traced with a corrected natural-flow
    simulation (tank genuinely parked via real `JUMP_ACTIVE`/overlap
    conditions, BigZum pinned to `STATE`=2) and found `TANK_ZUM_STANDING`
    itself isn't held at 1 continuously while parked: `UPDATE_JUMP`'s own
    auto-land replay (`JUMP_LANDING_RESTART_FRAME`) bounces the jump
    table back to its peak and eases it down every ~17 frames, and
    `UPDATE_TANK_BIGZUM_STAND`'s clamp only sets `TANK_ZUM_STANDING`=1
    for the handful of frames near the bottom of each bounce - traced
    directly as a repeating `1111111000000000` pattern (~7-8 standing
    frames out of every ~17). The counter's own "reset to 0 on any
    non-standing frame" rule threw away all that progress every single
    cycle, long before ever reaching `BIGZUM_SHAKE_STAND_FRAMES`(90).
    Fixed by resetting the counter only when `JUMP_ACTIVE` itself drops
    to 0 (the codebase's own existing definition of "no longer parked at
    all" - see `UPDATE_JUMP`'s own landing-restart comment) rather than
    on every momentary non-standing frame; while `JUMP_ACTIVE` stays 1
    but the current frame isn't clamped, the counter just holds instead
    of losing progress, so it now accumulates cumulatively across bounce
    cycles.
  - **Bullet color**: gray(14) -> light red(9) in the same 3 places
    changed to gray last round - "バレットカラーをライトレッドに変更".
  Verified: 11 isolated-subroutine unit tests against the new field
  layout (counter increments under `STATE`=2 specifically, resets only
  when not standing in isolation, threshold trigger sets `STATE`=1/
  marker/clears counter, `STATE`=1 skips the check entirely leaving the
  counter untouched, a normal jump via `UOBZ_PAUSE_DECIDE_JUMP` still
  clears a stale marker, shake-off jump moves right regardless of tank
  position) - all pass. A corrected natural-flow simulation (BigZum
  pinned to `STATE`=2, tank genuinely parked via real `JUMP_ACTIVE`/
  overlap, no manual flag forcing) now reaches the shake-off trigger at
  frame 184 and BigZum visibly relocates right (X 63->123) - the earlier
  (now-superseded) simulation attempt was itself confounded by not
  accounting for the bounce pattern and wrongly read as "still broken."
  Full regression: 20000-frame random-input sweep, 20000-frame idle
  sweep, existing Flyer/terrain targeted suites, all no crash/stall;
  `render_check.py` clean.
- **Shake-off still too slow, plus a suspected real-hardware bank/slot
  bug from before the rollback**:
  > Ok
  > ただ振り払いに入るのが遅いな
  > 乗っかられたら直ぐでいい
  >
  > で、ロールバックする前のの実装で
  > 暴走状態になる原因に思い当たるのが
  > バンク
  > 本編組み込みでは必要ないが
  > 今のテストではバンク初期化してないと
  > 16KB超えたらバンクBが見えなくて暴走かフリーズする
  > きちんと初期化してるかと言うのと
  > 本編組み込みでは初期化処理は削除することを確認
  - **Immediate shake-off**: `BIGZUM_SHAKE_STAND_FRAMES` 90 -> 1 - "乗っ
    かられたら直ぐでいい" - the counter INCs to 1 and immediately meets
    the (now 1-frame) threshold on the very first standing frame, so
    the jump fires the instant the tank lands on top instead of after
    any delay.
  - **Suspected pre-rollback slot/bank bug**: this file assembles to a
    flat, single-content 32KB image (`ORG 4000h`, currently ~15KB used,
    all in page1) with no real second ROM bank to switch to - but
    `INIT` never explicitly mapped this cartridge's own primary slot
    into page2 (8000h-BFFFh). On real hardware, page2 isn't guaranteed
    to already point at the cartridge's own slot at boot; whatever else
    was left mapped there (RAM, BIOS, etc) would make any code/data
    that spills past 7FFFh read back as garbage - invisible to
    `z80emu.py` (no slot/page model at all) but exactly the shape of
    unexplained runaway/freeze chased earlier this session, and
    plausible pre-rollback too since that version's code was larger
    still. Confirmed via `git grep`/`grep` that no bank or primary-slot
    setup existed anywhere in this file before this fix. Added the same
    "map primary slot into page2" step `CYBER SHMUP.asm`'s own `INIT`
    and `tools/bankswitch_poc/bank_a.asm` already use and have
    confirmed working on real hardware (PPI port 0A8h: copy the page1
    slot-select bits into the page2 field, write back) - no RAM
    trampoline or mapper bank-select needed here, since unlike
    `bankswitch_poc` this file has no second bank of actual content to
    switch to, only the one slot that needs to also cover page2.
    Marked TEST-ONLY in a comment at the call site - "本編組み込みでは
    必要ない" - to be deleted once this code folds into the real game,
    which already does its own equivalent setup in `CYBER SHMUP.asm`'s
    own `INIT`. Not independently verifiable on real hardware from this
    environment; verified only that it assembles, boots to `MAINLOOP`
    in the emulator (whose own no-slot-model behavior is unchanged
    either way), and the exact byte sequence matches the real-hardware-
    confirmed pattern from `bankswitch_poc` verbatim.
  Verified: unit tests updated for the new 1-frame threshold (first
  standing frame triggers immediately, `STATE`=1, counter cleared) -
  all pass; natural-flow simulation (BigZum pinned to `STATE`=2, tank
  genuinely parked) now triggers at frame 0 instead of frame 184. Full
  regression: 20000-frame random-input sweep, 20000-frame idle sweep,
  existing Flyer/terrain targeted suites, all no crash/stall;
  `render_check.py` clean.
- **Instant shake-off was itself too aggressive**:
  > 即発火は速すぎて飛び越えも出来なくなってるから60フレくらいで
  - `BIGZUM_SHAKE_STAND_FRAMES` 1 -> 60 (~1s of accumulated standing
    time, per the counter's own `JUMP_ACTIVE`-hold accounting from the
    previous round - not raw wall-clock frames). A deliberate jump-over
    was itself briefly reading as "parked" and getting shaken off
    before the player could land and move on; 60 gives that real
    jump-over enough slack while still reacting to a genuinely
    stationary rider in about 2s of real time (the counter only
    accumulates on the ~40% of frames the auto-land bounce animation
    actually reports standing=1, so 60 counted frames takes roughly
    127 real frames in the natural-flow test below).
  Verified: unit tests updated - a brief 10-frame touch (well under the
  new 60-frame threshold) no longer triggers; reaching the threshold
  from `STATE`=2 still does - all pass. Natural-flow simulation (BigZum
  pinned to `STATE`=2, tank genuinely parked) now triggers at frame 127
  (was frame 0 with the 1-frame threshold, frame 184 before the
  `JUMP_ACTIVE`-hold fix). Full regression: 20000-frame random-input
  sweep, 20000-frame idle sweep, existing Flyer/terrain targeted
  suites, all no crash/stall; `render_check.py` clean.
- **ZacoII sometimes spawns already white**:
  > Ok
  > ではZakoIIの変色バグ
  > 多分フラッシュ処理実装で出たと思う
  > どちらか分からんが最初からホワイトで出てくる場合がある
  - Root cause: `E_DY` (enemy slot offset+8) does double duty - it's the
    hit-flash countdown while alive (`UOE_DRAW`: nonzero -> render
    `FLASH_COLOR`/white, same repurposed-idle-field precedent used
    throughout this session) and the explosion drift value while
    exploding (set fresh from `EXPLODE_DIR_DY` on every kill). Once an
    explosion finishes and the slot frees up (`E_ACT`->0), nothing ever
    reset `E_DY` back to 0 - it just sat there holding that occupant's
    last drift value until the slot got reused. `ALLOC_ENEMY_SLOT`
    already reset `E_RETREAT`/`E_TIMER` on every fresh spawn but never
    touched `E_DY`, so a new ZacoII landing in a slot whose previous
    occupant had a nonzero vertical explosion-drift direction inherited
    that stale value and immediately read as "mid-flash" - rendered
    white from frame 1, then counted down and faded to its real color a
    few frames later. Matches the report precisely: intermittent
    (depends on which pool slot + that slot's own last explosion
    direction, not on anything about the new spawn itself), and
    specifically traces back to the hit-flash feature reusing this
    field without the corresponding spawn-time reset the other 2 fields
    already got. Fixed: `E_DY` zeroed alongside `E_RETREAT`/`E_TIMER`
    in `ALLOC_ENEMY_SLOT`. (Zum has no hit-flash at all - 1-hit kill,
    no HP/durability to flash for - so no equivalent field-reuse there;
    BigZum and Flyer each already zero their own *dedicated* (not
    reused) `FLASH_TIMER` fields at spawn, confirmed by re-reading both
    `ALLOC_BIGZUM_SLOT` and `ALLOC_FLYER_SLOT` - this was ZacoII-only.)
  Verified: a new targeted test reproduces the exact mechanism directly
  - forces a slot through an explosion with a nonzero leftover `E_DY`,
    confirms the slot frees up with that stale value still sitting in
    `E_DY`, respawns a fresh enemy into that same slot, and confirms
    both `E_DY` reads 0 and the drawn sprite color resolves to the
    normal variant color rather than `FLASH_COLOR`. Re-ran this same
    test against the pre-fix code (temporarily, via `git stash`) to
    confirm it actually fails without the fix (3 of 6 checks fail,
    including the drawn-color check) before confirming it passes with
    the fix restored - not just a test that happens to pass either way.
    Full regression: 20000-frame random-input sweep, 20000-frame idle
    sweep, existing shake-off/Flyer/terrain targeted suites, all no
    crash/stall; `render_check.py` clean.
- **Etank reimplemented** (the enemy deliberately skipped, "3をスキッ
  プ", after the full rollback - now given a complete fresh spec):
  > Ok
  > ではETank
  > 右からでて左に消える
  > 速度は2
  > Zumと同じで接触で自機を押す
  > 坂の昇降はしないんで
  > マップに長い平地を設置
  > 速度２なら１２８カウントで端から端まで行けるはずなので１５０の平地は欲しいな
  - Everything about Etank NOT covered by this message (HP, collision
    box, color, dynamic BigZum-pattern-VRAM sharing) is carried over
    from the design still visible in git history at commit 8f8d046
    (the round that triggered the rollback) - not itself shown to be
    wrong, and referenced by name here as an already-established
    concept rather than something to redesign from scratch: HP10,
    24(W)x16(H) collision anchored at the art's own bottom-left
    (confirmed directly against `sprites/Etank.json` - TL/TR fully
    blank, even BL/BR's own cols24-31 are blank, matching the box),
    dark red color (6, overriding the JSON's own fg), no permanent
    pattern-code allocation (shares BigZum's own `PAT_BIGZUM` BL/BR
    groups dynamically, restored on BigZum's own next spawn).
  - **Movement**: unlike Zum/BigZum, Etank never follows terrain
    elevation - Y is set once at spawn (`TANK_TIER_Y_TABLE` index0, the
    apex/highest tier) and never re-probed, straight horizontal line at
    a flat `ETANK_SPEED`(2) px/frame - "坂の昇降はしないんで...速度は
    2". Despawns once X can't subtract the speed without underflow -
    off the left edge, "左に消える".
  - **Terrain**: since Etank can't correct for a height change
    mid-crossing, `ETANK_TERRAIN_OK` only allows it to spawn while the
    apex tier (`IDCACHE_T0`) is the CURRENT surface, and that surface
    has to stay the apex tier for its entire on-screen lifetime, not
    just at the spawn instant - "速度２なら128カウントで端から端まで
    行けるはずなので150の平地は欲しいな". `terrain_gen.py`'s own
    `build_track()` widened both apex-tier flat runs (the runtime check
    can't tell which one it's currently looking at, same "widen both
    occurrences" precedent as before the rollback) from 24 tiles to a
    new `ETANK_APEX_FLAT_RUN`(150), each merging with an adjacent
    already-apex flat run for extra margin (174 total each, confirmed
    directly: runs of 178 and 154 cells). Track length grew 264->516
    cells; the pattern/color-group budget is unaffected (widening a
    flat run repeats existing (curr,next) pairs, adds no new ones).
  - **Push**: "Zumと同じで接触で自機を押す" - `UPDATE_TANK_ETANK_PUSH`
    is `UPDATE_TANK_ZUM_PUSH`'s own shape/speed verbatim, suspended
    entirely while `JUMP_ACTIVE` so the box stays cleanly jumpable.
  - **Bidirectional exclusion with BigZum, from the start this time**:
    the previous (pre-rollback) round's Etank/BigZum spawn gate was
    only one-directional (Etank refused to spawn while BigZum was
    active, but not the reverse), and the 2 were directly observed
    active simultaneously, corrupting the pattern-VRAM they share -
    exactly the kind of bug this session's own established
    "全ての敵はスポーン条件外はそもそも登録しない" principle exists to
    prevent (already applied once this session for BigZum/Flyer).
    `ALLOC_BIGZUM_SLOT` now also refuses while `ETANK_POOL` is active,
    and reloads BigZum's own real BL/BR pattern bytes on every spawn
    (not just when Etank happened to run recently) to undo any stale
    Etank art left over from an earlier appearance.
  Verified: 18 isolated-subroutine unit tests (terrain-gate spawn
  conditions including the climb/descend-marker case, spawn field
  init, BOTH directions of the BigZum exclusion, flat 2px/frame
  movement with no Y change, despawn at the left edge instead of
  wrapping negative, Zum-style push including the `JUMP_ACTIVE`
  suspension, omnidirectional bullet damage - lethal and non-lethal,
  hit-flash, bullet consumption) - all pass. A natural-flow simulation
  on the real scrolling track (no forced state) shows Etank spawning
  on its own, crossing the full screen with zero Y change, and
  despawning cleanly after exactly 120 frames (240px÷2px/frame,
  matching the math precisely). A dedicated 20000-frame random-input
  sweep additionally confirms: Etank reaches active state, only ever
  shows Y=132 (a single value, i.e. never changes) across its entire
  observed lifetime, hit-flash fires under random bullet contact, and
  BigZum/Etank are never simultaneously active across the whole run.
  Full regression: existing shake-off/Flyer/terrain/ZacoII-flash
  targeted suites, a separate 20000-frame random-input sweep, a
  20000-frame idle sweep, all no crash/stall; `render_check.py` clean.
  Total assembled size grew past 16KB (14917->16757 bytes, now genuinely
  spilling into page2) for the first time this session - exercises the
  primary-slot page2-mapping fix added earlier specifically for this
  scenario.
- **Real hardware still glitching past 16KB, Etank not appearing at
  all**:
  > グリッチ状態
  > ロールバックしたときと同じ状況
  > 推測通り16KB超えた途端バグってると思われる
  > ちゃんとバンクの初期化が出来てないな
  > その上ETankは全く出現しない

  then, after being asked whether to invest in a real ASCII16 mapper
  instead:

  > ASCII16バンク実装でも構わないが
  > MSXは標準でも32KBリニアマップは出来る
  > BIOSではPage2がマッピングされないので初期化でマッピングするコード
  > を入れるだけ
  > 過去にも全く同じミスをお前がやらかしてて特定に時間かかった
  > 調べて実装
  - **Etank never appearing traces directly to the same overflow**:
    checked exactly where the assembler placed `ETANK_BL`/`ETANK_BR`
    (Etank's own sprite pattern data, LDIRVM'd into VRAM on every spawn)
    - `0x8135`/`0x8155`, both past `0x8000`/page2. If page2 isn't
    correctly visible, that LDIRVM copies whatever garbage is actually
    there instead of Etank's real art, independent of whether Etank's
    own spawn/movement LOGIC (which lives entirely in page1) is correct
    - not a separate bug, a direct symptom of the same root cause.
  - **Re-verified the existing page2-mapping fix against `CYBER
    SHMUP.asm`'s own INIT (the "confirmed working on real hardware"
    reference it was copied from) by every means available from this
    environment**: diffed both the source text and the actual assembled
    opcode bytes (`DB A8`/`D3 A8` for the IN/OUT, confirmed via a direct
    symbol-table dump) - byte-for-byte identical. Confirmed it runs as
    the literal first thing in `INIT` (nothing upstream could already
    be touching page2) and that nothing later in the file writes to
    port `0A8h` again to undo it. No bug found in the mapping logic
    itself through static analysis - the general approach was already
    correct, not a guess, matching the proven reference precisely.
  - Since "properly done" clearly still needs *something* more (per
    the report) and real-hardware verification isn't possible from this
    environment, 2 concrete, low-risk changes rather than a repeat
    guess:
    1. **`DI` moved to before the slot-register read-modify-write**
       (was after, matching the reference) - a real MSX BIOS interrupt
       handler can itself perform inter-slot calls that touch this same
       port `0A8h` register internally; if one fires between the `IN`
       and the `OUT`, the sequence becomes unsafe. The reference code
       doesn't guard against this either, so it may be a latent bug
       there too (interrupt-timing races are notoriously hard to
       reproduce reliably, which would explain "confirmed working"
       without actually being immune). Zero downside - this whole
       region already needs interrupts off for the raw VDP/PSG port I/O
       right after it, so widening that protected region to also cover
       this block is free.
    2. **2 new border-color diagnostic checkpoints (11 before, 12
       after)** bracketing the slot-mapping block specifically, chosen
       not to collide with the existing 1-9 sequence (deliberately not
       renumbering that already-documented table). Since the code has
       now been re-verified correct by every static means available,
       the only way to find out whether the CPU is even reaching/
       clearing this exact block on the board that's still glitching is
       to ask the board directly next time.
  - Considered and explicitly rejected: hand-rolling `EXPTBL`/`SLTTBL`/
    `ENASLT`-based expanded-slot handling (the ONE documented gap in the
    existing fix - "correct for an unexpanded slot ... not [for] a
    cartridge slot with sub-slots"). Real MSX expanded-slot secondary-
    register bit-packing needed for that is not something this session
    could verify with confidence from memory alone, and `z80emu.py` has
    no slot/page model at all to test it against even approximately - a
    wrong guess at the bit format could make a genuinely expanded-slot
    board WORSE (misdirected slot switch) than the current already-
    broken state. Not attempted without a way to verify it.
  Verified: full regression suite (existing shake-off/Flyer/terrain/
  ZacoII-flash/Etank targeted suites, 20000-frame random-input sweep,
  20000-frame idle sweep, all no crash/stall; `render_check.py` clean)
  confirms the `DI` reorder didn't regress anything already working in
  the emulator - but the emulator cannot verify the actual real-
  hardware question here (no slot/page model), so this entry is
  explicitly NOT claiming the glitch or the missing Etank are fixed,
  only that the existing fix was re-verified correct wherever
  verification is possible, hardened against one identified latent
  risk, and instrumented for a decisive answer on the next real-
  hardware test - report which border color (11, 12, both, or neither)
  is showing if it still glitches or freezes.
- **Real answer from the board: real ASCII16 bank-switching needed, not
  slot mapping** - the checkpoint instrumentation above gave a
  decisive result:
  > フリーズはしてないがグリッチ
  > ボーダーはブラックだな
  > 何故か初期化方法も分からず調べもしないようなので無理だな
  > 出来てたことなのに
  > ではASCII16の本番形式でやってみろ
  > 64KBだからな
  > 出来たら一度確認でStage1のROMにマージして確認する
  > 今はStage1終わったら実装でStage1を移植してある状態

  Border stayed black - not even checkpoint 11 (literally the first 2
  instructions in `INIT`) showed. That rules out the page2-mapping
  fix's own correctness entirely (it was never even reached) and
  confirms the flashcart being tested on genuinely can't boot a >16KB
  image without a real ASCII16 mapper - no amount of MSX-internal slot
  routing was ever going to fix it.
  - **Replaced the page2-mapping-only approach with the real,
    production ASCII16 bank-switch mechanism** - copied verbatim from
    `tools/bankswitch_poc/build_full_rom.py`'s own `patched_game_text()`
    (the mechanism the actually-shipped game uses), not reconstructed
    from memory: a RAM trampoline (`LD (DE),A : JP (HL)`, copied to a
    newly-reserved `BANKSWITCH_TRAMPOLINE_RAM`(0F36Fh, 4 bytes) since
    the real game's own 0F200h is already `SPRITE_ATTRS` in this file)
    called as `LD A,<bank> : LD DE,<select addr> : LD HL,<resume
    addr> : JP <trampoline>`. Since this file has no genuine second
    PHASE of content the way the main game's stage1->stage2 transition
    does - just needs more than 16KB total for one continuous program -
    bank1 is selected exactly once at boot (`LD A,1 : LD DE,7000h`) and
    left selected permanently; window A (page1, where `INIT` itself
    lives) is never switched. The PPI page2-mapping step from the
    previous round is kept alongside it (not removed) - the real
    shipped game keeps both together too, per `build_full_rom.py`'s own
    patch, and it's harmless belt-and-suspenders for a flashcart that
    doesn't auto-map page2 to the same outer slot as page1, independent
    of the mapper's own inner bank selection.
  - **`build_test.py` rewritten to produce a genuine bank0+bank1 ROM,
    doubled to 64KB** ("ASCII16の本番形式でやってみろ 64KBだからな") -
    same layout and doubling convention as `bankswitch_poc/build_rom.py`
    (a real flashcart mirrored a 32KB image instead of decoding real
    banks until doubled to a "regulation" size for its own mapper
    auto-detection). `build_banks()` splits the existing flat
    address->byte dict from `assemble()` by page (4000h-7FFFh vs
    8000h-BFFFh) - no reorganization of `combined_test.asm`'s own
    source needed at all, since ASCII16 addresses each bank starting
    from its own page's base exactly the same way the old flat-32KB
    layout already did (the only real difference is that page2's
    content is now behind a bank *switch* instead of being permanently,
    unconditionally wired there).
  - **Test harness rewritten to model the mapper properly, not a flat
    bytearray** - a flat memory model would let the trampoline's own
    write to `7000h` silently corrupt whatever live program byte
    happens to sit at that address in a flat 64KB emulator image
    (confirmed directly: `0x7000` held a real opcode byte in this
    file's own layout) - a real bug in the TEST HARNESS, not the game,
    but one that would have produced misleading results either way.
    New `BankedMem` class in `build_test.py` (same shape as
    `bankswitch_poc`'s own `run_poc.py`/`verify_full.py` - writes to
    `6000h`/`7000h` select which bank is visible at page1/page2,
    everything else in `4000h-BFFFh` is read-only ROM matching real
    cartridge behavior, everything outside that range is flat RAM) -
    duck-typed to `z80emu.py`'s own `Z80(mem)` constructor exactly like
    `bankswitch_poc`'s own custom memory model already is. All targeted
    test scripts (Etank/shake-off/Flyer-terrain/ZacoII-flash, the full
    regression sweeps) now boot through a REAL cold start (bankB=0,
    matching real ASCII16 power-on default) and assert bank1 actually
    gets selected via the trampoline before trusting anything past
    `MAINLOOP` - this is a strictly stronger verification than before:
    it now actually exercises (and could have caught bugs in) the real
    boot-time bank-switch logic itself, not just the game logic that
    happens to run after it.
  Verified: `render_check.py` now asserts `mem.bankB == 1` after
  reaching `MAINLOOP` from a genuine cold start and reports the
  trampoline's own switch log - passes. All existing targeted suites
  (18 Etank + 12 shake-off + 5 Flyer/terrain + 6 ZacoII-flash checks)
  re-run against the properly-banked model - all still pass, now with
  a strictly stronger guarantee than the previous flat-memory version
  ever provided. Fresh 20000-frame random-input sweep and 20000-frame
  idle sweep, both under the banked model, no crash/stall; BigZum/Etank
  never simultaneously active, Etank's own Y never changes mid-life.
  `combined_test.rom` is now 65536 bytes (bank0+bank1, doubled).
  Real-hardware confirmation is still the only way to know for certain
  whether THIS mechanism actually boots on the flashcart in question -
  not independently verifiable from this environment beyond what's
  described above. Per direct instruction, the next step once this is
  confirmed working standalone is a one-time merge into the real
  Stage1 ROM to verify there too - not attempted this round.
- **WebMSX needs the `[ASCII16]` filename tag - verification was never
  actually real hardware**: "即リセットで起動しない" (the 64KB build) -
  turned out testing has always been via WebMSX, which detects a ROM's
  mapper type from its FILENAME (same convention as the real shipped
  `rom/CYBER SHMUP [ASCII16].rom`), not from file content/size the way
  every "real hardware" theory this session had been chasing assumed.
  Renamed the build output to `combined_test [ASCII16].rom` (no other
  changes). Per direct follow-up confirmation, the pre-ASCII16 32KB
  build's own glitch was identical to the post-ASCII16 one - meaning
  the bank-switch code had likely never actually been exercised by
  WebMSX at all until this rename, and the real glitch was always
  something else entirely.
- **The real Etank bug, finally found**: "動作はしたがな Etank実装で
  根本的なバグがあるってことだが 16KB超えで起こるからバンクの問題で
  あることは明らか":
  - **First, a full systematic RAM-overlap audit across every pool in
    the file** (computed each pool's real end address from its own
    `SLOT_SIZE*SLOT_COUNT` and compared against the next pool's start,
    programmatically, not by hand) - found exactly one: `ZUM_POOL`
    (16 bytes: `ZUM_SLOT_SIZE`(8)*`ZUM_SLOT_COUNT`(2)) overlapped
    `ZUM_SPRITE_ATTRS`'s own first 2 bytes by 2 bytes. `ZUM_POOL`'s own
    comment still said "14 bytes" - `ZUM_SLOT_SIZE` grew from 7 to 8
    (Z_RETREAT added) at some point without `ZUM_SPRITE_ATTRS`'s own
    address ever being pushed forward to compensate. Predates this
    entire session (both addresses untouched by any Etank/Flyer/BigZum
    work) and isn't Etank-specific, but real - every RAM address from
    `ZUM_SPRITE_ATTRS` through `BANKSWITCH_TRAMPOLINE_RAM` shifted +2
    bytes to actually clear the real 16-byte span; everything Etank/
    Flyer/BigZum itself owns was independently confirmed already clean
    in the same audit.
  - **The actual Etank bug**: re-derived `UOBZ_DRAW`'s real quadrant
    pattern-code addressing directly from its own code (TL=+0, TR=+4,
    BL=+8, BR=+12 - each 16x16-mode hw sprite code needs its own
    4-code group; every other multi-quadrant entity in this file
    already follows this same 4-apart spacing) and compared it against
    `PAT_ETANK_BL`/`PAT_ETANK_BR` (`PAT_BIGZUM+2`/`+3` - copied
    verbatim from the pre-rollback implementation without re-deriving
    it against the CURRENT `UOBZ_DRAW`) - only 1 code apart, landing
    inside the MIDDLE of BigZum's own TL quadrant's 4-code span
    instead of at BigZum's real BL/BR quadrant bases. Etank's own
    64-byte dynamic pattern-share LDIRVM (using this wrong base)
    corrupted BigZum's TL's own last 2 sub-tiles and all of TR's, and
    Etank's own BL/BR hw sprites showed a misaligned slice of the
    wrong bytes instead of real quadrant art - garbled graphics on
    both BigZum and Etank, real visual glitching, entirely
    independent of ROM banking (the ">16KB" correlation was
    circumstantial - Etank happened to be the same feature that also
    pushed the ROM over 16KB, not a causal link). Corrected to
    BigZum's own real quadrant bases (`PAT_BIGZUM+8`/`+12`) - still
    contiguous, so the existing single 64-byte LDIRVM still covers
    both quadrants correctly with no other code change needed.
  Verified: `git stash`-based before/after testing for BOTH fixes -
  the Zum RAM-overlap regression test (3 checks: does a slot1 field
  survive a slot0 sprite-attrs write) and the new Etank pattern-VRAM
  test (8 checks: quadrant spacing, BigZum's own TL/TR untouched by
  an Etank spawn, Etank's own BL/BR VRAM matches its real source art
  byte-for-byte) both correctly fail without their respective fix (6/8
  and 3/3 failures) and pass with it - not tests that happen to pass
  either way. Full regression: all existing targeted suites (Etank/
  shake-off/Flyer-terrain/ZacoII-flash, 52 checks total) re-run clean
  under the banked model; fresh 20000-frame random-input sweep and
  20000-frame idle sweep, no crash/stall; `render_check.py` clean.

- **BigZum removed entirely as a diagnostic isolation step - reported
  glitches never reproduced in the emulator**: after the Zum RAM-
  overlap and Etank quadrant-addressing fixes above, 2 screenshots
  still showed real glitches on WebMSX: "まず１枚目 右下の地形に青や
  緑のスプライトが出てる これは地形の中なので出るはずがない これらが
  上から下に高速で点滅しながら移動してる 2枚目が左上の雲のあたりに
  白いBigZumが表示されてる". Extensive automated reproduction attempts
  (a 30000-frame BigZum-focused "ghost hunt" sweep asserting per-frame
  invariants like "quadrant color=15/white implies flash timer>0" and
  "Y never implausibly small/near the top of screen", a separate
  20000-frame sweep checking every enemy never sinks below the terrain
  line, and a frame-by-frame trace of the shake-off jump specifically)
  found nothing - 0 sunk-sprite anomalies, 0 genuine white-BigZum
  frames (the only 16 flagged were a false-positive of the detector's
  own timing, a legitimate last frame of an ordinary hit-flash), peak
  jump Y=112 (nowhere near the clouds). Asked whether the white BigZum
  appeared before or after BigZum's own real spawn gate
  (`ENEMY_SPAWN_COUNT>=10`) could first fire - "だからよ スタート直後
  から出てるって言ったろ そもそもこれはスポーンで描画されてるわけ
  じゃない バグだからな" confirmed it happens before BigZum could ever
  legitimately be alive, i.e. it is NOT BigZum's own real spawn/draw
  logic executing correctly (something is putting stray, off-spec
  sprite/color data on screen through some other path this session's
  static analysis and automated sweeps both failed to find). New
  instruction, changing the diagnostic strategy entirely: "なので方針
  を変える BigZumのコードは全て一旦削除 変わりにEtankと差し替えて
  Etank周りが正常動作するか確認する" - delete BigZum completely and
  verify Etank still works correctly on its own, to isolate whether
  the glitch lives specifically in BigZum's own code/interactions or
  is something else entirely (e.g. a WebMSX-specific VDP-timing/
  sprite-per-scanline-limit behavior unrelated to any of this file's
  own code).
  - Removed every `BIGZUM_*`/`BigZum` constant, RAM address, routine
    (`ALLOC_BIGZUM_SLOT`, `UPDATE_BIGZUM_ALL`/`UPDATE_ONE_BIGZUM` and
    all its `UOBZ_*` sub-states, `UOBZ_DRAW`, `UOBZ_EXPLODING`/
    `UOBZ_HIDE`, `UOBZ_GET_GROUND_Y`, `FLUSH_BIGZUM_SPRITES`,
    `UPDATE_TANK_BIGZUM_STAND`/`UPDATE_TANK_BIGZUM_PUNCH`,
    `CHECK_BULLET_VS_BIGZUM`/`CHECK_HIT_ONE_BULLET_BIGZUM`/
    `CHECK_HIT_PAIR_BIGZUM`, `BIGZUM_TERRAIN_OK`), pattern-loading
    LDIRVMs and RAM-clear/hide loop in `INIT`, its 4 `MAINLOOP` calls,
    the `BIGZUM_JUMP_TABLE` data, and the BigZum-side mutual-exclusion
    checks inside `ALLOC_ZUM_SLOT`/`ALLOC_FLYER_SLOT`/
    `ALLOC_ETANK_SLOT` (no longer meaningful with BigZum gone).
    `bigzum_gen.py`'s import and table concatenation removed from
    `build_test.py` - its pattern data is no longer emitted into the
    ROM at all.
  - **Etank given its own permanent pattern allocation**, since
    BigZum's removal freed up the whole 156-219 pattern-code range it
    used to dynamically borrow from: `PAT_ETANK_BL`/`PAT_ETANK_BR` are
    now fixed codes (156/160, still 4 apart per the same quadrant-
    group convention) instead of `PAT_BIGZUM+8`/`+12`, and its 64-byte
    pattern LDIRVM moved from `ALLOC_ETANK_SLOT` (dynamic, every spawn)
    to a one-time load in `INIT` (permanent, same convention as
    Flyer's own `PAT_FLYER`). `UOET_DRAW`'s scratch color byte moved
    off the now-deleted `BIGZUM_DRAW_COLOR` onto its own new
    `ETANK_DRAW_COLOR` (0F375h, still clear of the 0F380h BIOS-work-
    area boundary). `etank_gen.py`'s own docstring updated to describe
    the new permanent-allocation design instead of the old dynamic
    BigZum-sharing scheme.
  Verified: `etank_pattern_vram_test.py` rewritten for the new
  architecture (8 checks) - confirms Etank's own pattern VRAM is
  already correct right after `INIT`, before any spawn has ever
  happened (proving the permanent load actually works), and that a
  spawn no longer re-touches pattern VRAM at all (poisoned bytes
  survive `ALLOC_ETANK_SLOT`, proving the old per-spawn LDIRVM is
  really gone) - all 8 pass. `etank_unit.py`'s 2 BigZum-bidirectional-
  exclusion checks removed (no longer meaningful); its remaining 16
  checks (spawn gating, straight-line movement, despawn, push,
  omnidirectional bullet damage) still pass. All other existing
  targeted suites (Flyer-terrain 5, ZacoII-flash 6, Zum-overlap 3)
  re-run clean. Fresh 20000-frame random-input sweep and 20000-frame
  idle sweep under the properly-banked ASCII16 model, no crash/stall;
  `render_check.py` still boots clean with bank1 correctly selected.
  Rendered an Etank-only scene (`visual_check3.py`) to a PNG and
  visually confirmed it draws correctly - dark red tank shape on the
  terrain, no stray/misplaced sprites, no white ghosts near the sky.
  The user's specific reported symptoms (terrain-embedded flickering
  blue/green sprites, white BigZum near the clouds) were never
  reproduced by any means available in this emulator-based test
  harness even before this removal - whether they're now gone in
  WebMSX (confirming the cause lived specifically in BigZum's own
  code) or still present with BigZum fully deleted (pointing to
  something else, e.g. WebMSX-specific behavior unrelated to this
  file's own code) still needs real-WebMSX confirmation, not
  independently verifiable from this environment.

- **The real ghost bug, finally found: the stack had almost no headroom below `STACKTOP`** - after BigZum's removal the SAME symptom immediately reappeared, now shaped like a white Etank instead: "左上見ろ 白いEtankがでて右側にゴミ...恐らくスポーンはしてない...そもそもスポーンしてないしな". Per direct instruction ("だったら他の出現を全て停止して Etankだけだせ 他は一切表示もスポーンもしないなら 明らかなロジックのバグだろう"), shipped a diagnostic build with `ALLOC_ENEMY_SLOT`/`ALLOC_ZUM_SLOT`/`ALLOC_FLYER_SLOT` forced to `RET` immediately (only the tank and Etank could ever appear) - the ghost persisted anyway, ruling out any interaction with those 3 systems.
  - The user's own next message pointed straight at it: "過去の例では使用する変数やRamが初期化されてなくて誤動作したり...スタックの扱いをミスってたりな Push Pop不整合だ". A full audit of every `PUSH`/`POP` in Etank's own code found nothing unbalanced (every early `RET` path was already clean). But `STACKTOP`'s own comment (already in this file, from an EARLIER round of this exact class of bug) said the real thing to worry about wasn't code-level PUSH/POP balance at all: "0F380h+ is real MSX BIOS work-area territory...serviced by the H.TIMI interrupt handler every VBlank on real hardware...z80emu.py has no interrupt/BIOS simulation at all". Confirmed directly in `z80emu.py`'s own source: `iff1`/`iff2` are tracked (DI/EI update them) but nothing anywhere ever actually fires an interrupt - every one of this session's 20000+/30000+-frame sweeps ran with the real MSX vblank interrupt permanently, silently disabled.
  - Measured the real minimum SP reached, on every single instruction step (not just at frame boundaries) across thousands of frames of ordinary gameplay - **with zero interrupts involved**, plain nested `CALL`s during a single `MAINLOOP` frame already pushed SP down to `0F374h`, only 12 bytes below `STACKTOP` (`0F380h`) - which was already INSIDE `BANKSWITCH_TRAMPOLINE_RAM` (`0F371h-0F374h`) and 1 byte from `ETANK_DRAW_COLOR` (`0F375h`). SP always balanced back to exactly `0F380h` by the end of every frame (proving no PUSH/POP mismatch, exactly as the audit found), but that only proves the stack doesn't *leak* - it says nothing about how deep it dips *mid-frame*, and a real H.TIMI interrupt firing at the wrong moment (this file's own STACKTOP comment already flagged this as a real, confirmed-on-real-hardware risk) would push far deeper than 12 bytes, easily reaching `ETANK_SPAWN_TIMER`/`ETANK_SPRITE_ATTRS`/`ETANK_POOL` and beyond - a routine `PUSH` mid-interrupt overwriting `ETANK_SPRITE_ATTRS` with an arbitrary register value would get blasted straight to the real hw sprite attribute table by the very next `FLUSH_ETANK_SPRITES`, with no real spawn ever involved - exactly "白いEtankが...スポーンで描画されてるわけじゃない", and exactly why the same symptom tracked whichever entity's own scratch RAM happened to sit closest to `STACKTOP` (BigZum's own `DRAW_COLOR` before removal, Etank's own after).
  - Fixed by shifting every OTHER RAM address in the file down by `100h` (256 bytes) via a mechanical, whole-file substitution (`TICK` now at `0EF00h` instead of `0F000h`, etc.) - `STACKTOP` itself is untouched (still the same real BIOS boundary), but now has 266 bytes of genuinely free headroom below it before reaching the topmost variable (`ETANK_DRAW_COLOR`, now at `0F275h`), comfortably past both the measured call-depth dip and any realistic H.TIMI interrupt overhead. Reverted the 3 diagnostic `RET`s (Zum/Flyer/ZacoII spawning restored) now that the isolation step had already answered the question.
  Verified: full regression suite (Etank pattern-VRAM 8, Etank unit 16, ZacoII-flash 6, Zum-overlap 3, Flyer-terrain 5 - 38 checks) all still pass after the address shift; fresh 20000-frame random-input and idle sweeps under the properly-banked ASCII16 model, no crash/stall; `render_check.py` clean with bank1 correctly selected; re-measured the same SP-dip trace after the fix - the 12-byte-below-`STACKTOP` dip is unchanged (same call depth, expected), but now lands in genuinely empty RAM with 255+ bytes of margin above the nearest live variable instead of inside it. Real-WebMSX confirmation that the ghost is actually gone is still the only way to know for certain - `z80emu.py` could verify the mechanism (the dangerous dip) but, having no interrupt simulation at all, can never directly witness the corruption itself the way WebMSX's own real VDP/interrupt timing can.

- **Ghost confirmed gone; Etank's own Y-offset bug found and fixed; BigZum restored** - "ゴミは消えた やはりお前のミスじゃねえか" confirmed the stack-headroom fix actually worked. Two follow-up instructions:
  - **"Etankの位置がおかしい また自機基準でオフセットしてねえだろうな 毎回同じミスしてる 自機だけジャンプの関係でやってるだけで特殊"** - exactly the same bug class as `BIGZUM_Y_OFFSET` before it: `ALLOC_ETANK_SLOT` copied `TANK_TIER_Y_TABLE`'s value onto Etank's own Y directly, without correcting for the +4 landing-offset fudge `TANK_Y_BASE`'s own derivation bakes in specifically for the TANK's own art. Confirmed directly against `sprites/Etank.json`: ink runs all the way to row31 (no bottom padding, same as BigZum's own art), so reusing the tank's already-compensated anchor sank Etank's real feet ~4px below the true ground line. Added `ETANK_Y_OFFSET EQU 4`, subtracted the same way `BIGZUM_Y_OFFSET` already was.
  - **"BigZumがでないままになってるからもとに戻せ で、EtankとBigZumは同時には存在しない Etank用の長い平地でEtankをスポーンしてBigZumは出すなよ"** - restored BigZum's complete implementation (constants/RAM/all routines/`INIT` pattern-loading and pool-clear/`MAINLOOP` calls/`BIGZUM_JUMP_TABLE`) from git history (commit `28ba232`, the last one before its diagnostic removal), reintegrated into the current file with every RAM address shifted the same `-100h` the rest of the file's own addresses already were - it slotted back into the exact gap deliberately left behind during the removal (`JUMP_STAND_BASELINE` through `FLYER_POOL`) with zero new overlaps, confirmed by a full systematic pool-by-pool audit. Etank went back to its ORIGINAL design too - dynamically sharing BigZum's own `PAT_BIGZUM` BL/BR pattern-VRAM groups at spawn time (`PAT_ETANK_BL`/`PAT_ETANK_BR` back to `PAT_BIGZUM+8`/`+12`, no longer a fixed permanent code) - restoring the bidirectional spawn-gate exclusion in both directions (`ALLOC_ZUM_SLOT`/`ALLOC_FLYER_SLOT`/`ALLOC_ETANK_SLOT` all refuse while `BIGZUM_POOL` is active; `ALLOC_BIGZUM_SLOT` refuses while `FLYER_POOL`/`ETANK_POOL` are active) - exactly "EtankとBigZumは同時には存在しない". Kept 2 improvements from the diagnostic round that don't conflict with any of this: Etank's own dedicated `ETANK_DRAW_COLOR` scratch byte (RAM is no longer the tight resource pattern-code space still is) and the `ETANK_Y_OFFSET` fix above.
  Verified: full systematic RAM-overlap audit (31 pools/scratch-bytes, sorted and checked pairwise) - zero overlaps, 266 bytes of headroom still intact below `STACKTOP`. `etank_unit.py` (18 checks, including the Y-offset fix and both directions of the bidirectional exclusion), `etank_pattern_vram_test.py` (10 checks, rewritten back to testing the dynamic-sharing mechanism - BigZum's TL/TR untouched by an Etank spawn, Etank's BL/BR VRAM matches its own real art, BigZum's own next spawn correctly reloads and undoes Etank's borrow), `shakeoff_unit.py` (12 checks, BigZum's own shake-off mechanic - unchanged, still passes byte-for-byte identical to before the diagnostic removal), plus the existing Flyer-terrain (5)/ZacoII-flash (6)/Zum-overlap (3) suites - 54 checks total, all pass. Fresh 20000-frame random-input sweep with an explicit per-frame invariant check ("Etank and BigZum active at the same time" - 0 occurrences across the whole run) and 20000-frame idle sweep, both clean, no crash/stall; `render_check.py` boots correctly with the ASCII16 bank-switch intact; rendered Etank and BigZum separately to PNG and visually confirmed both draw correctly - Etank now sits flush on the terrain instead of sunk in, BigZum renders with no stray artifacts.

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
  script (imports `terrain_gen.py`, `tank_gen.py`, `bullet_gen.py`,
  `enemy_gen.py`, `bigzum_gen.py`, `flyer_gen.py`, and `etank_gen.py`).
- `combined_test [ASCII16].rom` - the built ROM, 64KB (bank0+bank1,
  doubled). The `[ASCII16]` filename tag is required, not cosmetic -
  WebMSX (the actual verification method used for this file - not real
  hardware) detects the mapper type from the filename, matching the
  real shipped game's own `rom/CYBER SHMUP [ASCII16].rom` convention;
  without it, WebMSX falls back to guessing some other ROM type
  regardless of the file's own real content/size.
- `bullet_gen.py`, `sprites/BulletF.json`, `sprites/BulletU.json` - the
  2 shot shapes' source art + BG-pattern conversion (8x8, single
  character each - no quadrant splitting needed, unlike the tank's
  32x32 sprite).
- `enemy_gen.py`, `sprites/ZacoII.json`, `sprites/Zum.json` - the 2
  16x16 ground/air enemy sprites' hw-pattern conversion (single hw
  sprite each, no quadrant splitting).
- `bigzum_gen.py`, `sprites/BigZum.json`, `sprites/BigZumP.json` -
  BigZum's 2 32x32 poses' hw-pattern conversion, mirroring
  `tank_gen.py`'s own quadrant-splitting + hflip approach (see the
  BigZum entry above).
- `flyer_gen.py`, `sprites/Flyer.json` - Flyer's own 32x32 hw-pattern
  conversion, permanent pattern allocation (no VRAM sharing).
- `etank_gen.py`, `sprites/Etank.json` - Etank's own 32x32 art, but
  only the bottom-left BL/BR quadrants are ever emitted (TL/TR are
  fully blank in the source art) - dynamically shares BigZum's own
  pattern-VRAM at runtime instead of a permanent allocation (see the
  Etank entry above).
- `render_check.py` - emulator verification: boots, runs several full
  track loops with no crash/hang, and renders 2 sample frames from
  real VRAM (BG + sprites composited together) to `combined0.ppm`/
  `combined1.ppm` for visual confirmation.

## Next step

Real descend art for the Gap pose (currently reusing the climb Gap
sprite for both, per direct instruction, since only one was ready) -
and eventual collision between shots and something to hit, once
enemies exist in this test.
