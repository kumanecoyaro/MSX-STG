# Stage 2 ground/slope scroller (standalone test)

A standalone, real-hardware-shaped test ROM for Stage 2's road: a
4-tier staircase (climb 4 steps, then descend 4 steps using a
mirrored version of the same art, then loop) built from just two
hand-drawn tiles, reusing Stage 1's exact scroll-blend engine
(`REFRESH_IDCACHE_33` + the cell-pair phase-blend algorithm from
`CELL_LOOP_0/2/3/5` in `src/CYBER SHMUP.asm`) - see that file for the
original 6-terrain-type version this is modeled on.

Not wired into the real Stage 2 world yet - kept isolated here so the
terrain shape and scroll smoothness can be verified against the
actual emulated VRAM output before it's integrated.

## Design

- `sprites/Rock.json` - flat ground, 16x8 (2 cells wide x 1 cell
  tall; drawn in a 16x16 canvas but only the top 8 rows have content).
  Tiled `L,R,L,R,...` to fill a flat run, exactly like Stage 1's
  existing wedge-A/wedge-B row (`ROWDATA5`, `"ABABAB..."`).
- `sprites/Rock225.json` - the climb transition, 16x16 (2 cells wide
  x 2 rows tall): upper 8 rows = the rising diagonal edge (goes in
  the row *above* current ground), lower 8 rows = the "filled in"
  ground left behind (goes in the row that *was* ground). Always
  placed as one 2-cell-wide block, exactly like the existing
  wedge-A->wedge-B transition convention.
- Descent reuses Rock225 mirrored left-right (`hflip`, swapping which
  half is which) per direct instruction - no separate down-slope art.
- `sprites/Sand.json` (8x8) - id0/BLANK's art, i.e. the "not yet grown
  into rock" cells within the scrolling band (the rows above the
  current ground tier, still waiting their turn to become Rock as the
  track climbs/descends) - previously a flat solid-color tile (all-
  zero bits, so only the uniform rock color group's own bg showed
  through), given actual sand-speckle texture per direct instruction:
  "Rockの左右のイエローブランクにSandを設定" (put Sand in the yellow
  blanks to the left/right of Rock). Like every other tile here, only
  its bit pattern is used - the JSON's own fg/bg are ignored since the
  uniform `ROCK_COLOR` group still supplies the actual in-game color
  (see the color-table comment in `terrain_gen.py`). The numeric id
  (0) is unchanged, so `combined_test.asm`'s own terrain-collision
  code (which scans for "the first non-BLANK id" using that exact
  value as its sentinel) is entirely unaffected - only the rendered
  art changed, not the id semantics.
- The 4 rows (screen rows 20-23, i.e. `GROUND_ROW0`..+3, matching the
  4-row band Stage 1 already treats as "the ground scroller") share
  **one** PXCHAR/phase clock, gated every 8 ticks - unlike Stage 1's
  4 *independently*-rated parallax tiers (this is one physically
  connected surface, not decorative layers drifting past each other
  at different speeds; confirmed with the user before implementing).
- The 7 intermediate per-pixel scroll frames PAIRBASE needs for each
  occurring tile-pair transition are **not** hand-drawn - they're
  synthesized by horizontal bit-shift-and-OR between the two tiles
  (`blend()` in `terrain_gen.py`), since a smooth 1px/frame scroll
  between two fixed tiles is a pure mechanical pixel translation, not
  new art.
- Track is tuned to exactly 256 cells (`FLAT_RUN=24` cells per flat
  run) so `PXCHAR_T` is a single byte that wraps for free - no 16-bit
  compare-and-reset needed.

## Files

- `sprites/Rock.json`, `sprites/Rock225.json` - the two source tiles
  (Sprite Editor export format), copied into the repo so the build
  doesn't depend on the original upload path surviving.
- `terrain_gen.py` - loads the sprites, builds the 4-row test track
  (climb/descend/loop), collects every `(curr,next)` tile-pair that
  actually occurs, synthesizes the blend frames, and emits the
  `TERRAIN_*` DB/EQU tables as Z80 source text.
- `terrain_test.asm` - the standalone test ROM: boots via the normal
  BIOS SCREEN1 path, loads the generated pattern/color tables, then
  `MAINLOOP` free-runs (no `EI`/`HALT` vblank pacing - this is an
  emulator/data-correctness test, not paced for real hardware yet)
  advancing the shared clock and re-rendering all 4 rows every frame.
  `terrain_gen.py`'s generated tables get appended after this file's
  own code at build time (`mini_z80asm.py` has no `INCLUDE`).
- `build_test.py` - concatenates `terrain_test.asm` + the generated
  tables and assembles them into `terrain_test.rom` (32KB, flat, no
  mapper - this test doesn't need bank-switching).
- `verify_terrain.py` - runs the ROM in `z80emu.py`, dumps the real
  VRAM (pattern generator + name table, not a re-derivation of the
  Python model) at sampled frame counts, and renders it from those
  actual emulated bytes to confirm what the hardware would really
  draw. Verified: the macro staircase shape across a full sweep of
  the 256-cell track, and consecutive-frame smoothness around the
  first climb transition (no popping/discontinuity in the scroll).
- `terrain_test.rom` - the built test ROM.

## Next step

Wire this into `tools/bankswitch_poc/build_stage2_world.py`'s real
Stage 2 world once the design is confirmed - reserve real VRAM
pattern-code space alongside the existing STAGE2 HUD label glyphs,
extend the test track into whatever the real Stage 2 level layout
ends up being (this loop is a synthetic test shape, not final level
content), and hook the tank's ground-height collision to
`ROWPHASE_T`/current-tier state (not yet built - this test is
rendering only, nothing reads it back for physics yet).
