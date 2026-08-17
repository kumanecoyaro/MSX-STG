# Terrain + tank combined test

Merges `tools/stage2_terrain`'s ground scroller with
`tools/stage2_tank`'s sprite into one standalone 32KB ROM - the
tank-only test showed the tank floating on nothing, which isn't a
meaningful check, and separately reportedly froze on real hardware
with no way to tell where.

## What's here

- Terrain engine (own INIT priming + MAINLOOP scroll update) and tank
  sprite (4x 16x16 hardware sprites, pose TankF) both set up in one
  INIT, both driven from the same MAINLOOP/TICK.
- **Not physics-integrated yet**: the tank sits at a fixed screen
  position (`TANK_X=40, TANK_Y=155` - row23's top minus the tank's
  32px height plus the +3 landing offset) matching the terrain's
  starting flat tier. It does not track the terrain's climb/descend
  height changes - that needs the ground-height collision system,
  which isn't built yet.
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

## Files

- `combined_test.asm`, `build_test.py` - the merged engine + build
  script (imports both `terrain_gen.py` and `tank_gen.py`).
- `combined_test.rom` - the built ROM.
- `render_check.py` - emulator verification: boots, runs several full
  track loops with no crash/hang, and renders 2 sample frames from
  real VRAM (BG + sprites composited together) to `combined0.ppm`/
  `combined1.ppm` for visual confirmation.

## Next step

Same as before: tank movement (left/right, A=shot, B=jump 16px) and
the ground-height collision system so the tank actually follows the
terrain instead of sitting at a fixed Y.
