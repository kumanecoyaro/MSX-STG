# Tank player sprite (standalone test)

Converts the 4 tank pose sprites (32x32, Sprite Editor JSON) into real
MSX hardware sprite data and displays them - a sprite-conversion/
composition correctness check, no movement/physics yet.

## Design

- Each 32x32 pose = 2x2 arrangement of 16x16 hardware sprites
  (top-left/top-right/bottom-left/bottom-right), matching the existing
  player ship's own convention (`SHIP_MID_PATTERN` in
  `src/CYBER SHMUP.asm`): each 16x16 sprite's 32 bytes are
  [top-left 8x8][bottom-left 8x8][top-right 8x8][bottom-right 8x8].
- 4 poses: `TankF` (straight, flat ground), `TankUp` (up+fire, 45°
  shot), `TankFGap`/`TankUGap` - same two, but tilted to follow a
  slope transition cell (see `tools/stage2_terrain/`'s Rock225
  climb/descend markers - these are the tank's matching pose for
  standing on one of those cells).
- Sprite color: solid blue (MSX color 4), no per-pixel color - sprites
  are 1-bit (transparent/color) in MSX1, unlike the multi-color
  background tiles used for terrain.

## Files

- `sprites/TankF.json`, `TankUp.json`, `TankFGap.json`,
  `TankUGap.json` - the 4 source sprites, copied into the repo.
- `tank_gen.py` - splits each 32x32 pose into 4 16x16 quadrants (TL,
  TR, BL, BR), each further split into the standard 4x8-byte sprite
  sub-pattern order, and emits `PAT_<POSE>` EQU + pattern data. Each
  pose gets 16 consecutive pattern-group slots (4 quadrants x 4).
- `tank_test.asm` - standalone test ROM: boots via the normal BIOS
  SCREEN1 path, switches to 16x16 sprite mode (VDP R1 bit1), loads all
  4 poses' pattern data, and cycles through them (one pose per ~64
  frames) as 4 real sprites at a fixed screen position.
- `build_test.py` / `verify_tank.py` - assemble + run in `z80emu.py`,
  reading back the real sprite attribute table and sprite pattern
  generator table from VRAM to composite what hardware would actually
  display (not a re-derivation of the Python source model).

## Gotcha hit during this

`mini_z80asm.py` evaluates expressions strictly left-to-right with
**no operator precedence** (documented in its own `eval_expr`
comment). Writing `SPRPAT+PAT_TANKF*8` silently evaluates as
`(SPRPAT+PAT_TANKF)*8`, not `SPRPAT+(PAT_TANKF*8)` - caught via the
sprite failing to render (DE ended up 0xC000 instead of 0x3800).
Fixed by matching the convention already used throughout
`src/CYBER SHMUP.asm`: write it as `PAT*8+SPRPAT` (multiply first).

## Next step

Movement: left/right only (no up/down), A=shot, B=jump (16px height),
landing Y-offset +3 so the tank sits on the ground rather than
floating. Not built yet - this test only proves the sprite art
converts and composites correctly.
