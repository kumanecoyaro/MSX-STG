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
  24px triangular arc over 49 frames (`JUMP_OFFSET_TABLE`: 0,1,2,...,24
  at frame 24, then 23,...,0 - 1px/frame, slower than an earlier
  16px/16-frame version per direct instruction), applied as
  `TANK_Y_CUR = TANK_Y_BASE - JUMP_Y_OFFSET`. Not real gravity/physics,
  just a fixed-shape hop - fine for now since there's no ground-height
  variation to land on
  yet anyway.
- **Pose selection** (`UPDATE_POSE`): TankF (grounded, neutral),
  TankUp (grounded, aiming up), TankFGap (airborne, neutral), TankUGap
  (airborne, aiming up). Per direct instruction, the Gap poses are
  wired up for "airborne" only right now - the terrain-slope-following
  use of the same poses is deferred.
- **Not physics-integrated with the terrain yet**: `TANK_Y_BASE=156`
  (row23's top minus the tank's 32px height plus a +4 landing offset)
  is a fixed constant matching the terrain's starting flat tier -
  jumps arc relative to it, but the tank does not track the terrain's
  own climb/descend height changes. That needs the ground-height
  collision system, still not built.
- Shot (A button) not implemented yet either - out of scope for this
  pass, movement + jump only.
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
- **Sprite-table shadow bug** (visible immediately as a black
  tank-shaped blob at the top-left corner): only wrote the tank's own
  4 sprite attribute entries (slots 0-3) and never touched the rest
  of the 32-slot table. z80emu.py's VRAM defaults to all-zero, so slot
  4 was left at Y=0/X=0/pattern=0/color=0 - Y=0 is a valid on-screen
  position (not the Y=0xD1 "stop here" sentinel), and pattern=0
  happens to alias the tank's own top-left quadrant (`PAT_TANKF=0`),
  so it rendered a second, black (color=0) copy of that quadrant at
  the top-left. Fixed by explicitly writing Y=0xD1 to slot 4 right
  after the tank's own 4 entries - real hardware's own sprite RAM
  contents at boot are unpredictable, so this isn't just an emulator-
  cleanliness fix, it's required either way.
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

## Emulator-side testing note

`tools/z80emu.py`'s GTSTCK (BIOS joystick-direction read) previously
always returned 0 (centered/no input) unconditionally - there was no
way to simulate stick movement in a test, only `GTTRIG`'s `sim_fire`
existed. Added `sim_dir` (default 0, same as the old hardcoded
behavior) so `cpu.sim_dir = 3` etc. can drive movement/aim through the
exact same code path the real BIOS call would take, instead of poking
`TANK_X`/`TANK_DX` directly and bypassing the input-decoding logic
being tested.

## Files

- `combined_test.asm`, `build_test.py` - the merged engine + build
  script (imports both `terrain_gen.py` and `tank_gen.py`).
- `combined_test.rom` - the built ROM.
- `render_check.py` - emulator verification: boots, runs several full
  track loops with no crash/hang, and renders 2 sample frames from
  real VRAM (BG + sprites composited together) to `combined0.ppm`/
  `combined1.ppm` for visual confirmation.

## Next step

A=shot, and the ground-height collision system so the tank actually
follows the terrain instead of sitting at a fixed Y (which is also
when the Gap poses' terrain-slope use gets wired up, deferred from
this pass).
