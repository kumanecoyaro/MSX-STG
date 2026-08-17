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
- **Movement**: port1 stick, left/right only (`TANK_SPEED=2` px/frame,
  clamped to the screen). Up alone or combined with left/right sets
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
  un-shifted muzzle row); spawn column = `(TANK_X+24)>>3` (muzzle,
  right side of the tank - the tank only ever faces right, there's no
  flip/left-facing state anywhere in this test).
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
  | 7 | Tank sprite attributes written - about to enter MAINLOOP |

  If it freezes again, report which color is showing.

## Bugs found and fixed while building this

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
