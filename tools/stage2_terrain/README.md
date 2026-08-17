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
  its bit pattern is used - the JSON's own fg/bg are ignored. The
  numeric id (0) is unchanged, so `combined_test.asm`'s own terrain-
  collision code (which scans for "the first non-BLANK id" using that
  exact value as its sentinel) is entirely unaffected by any of this -
  only the rendered art/color ever changed, not the id semantics.
  - **Sand's own color** ("Sandの文字色をダークイエローに", later
    corrected to "文字色ダークイエロー、背景色ライトイエロー" - fg10
    dark yellow, bg11 light yellow, `SAND_COLOR`=0xAB - an earlier
    round used the same dark yellow for both by mistake) needed
    independence from Rock's own fg, which SCREEN1 can't give 2 tiles
    sharing one 8-code color group. Getting this genuinely flicker-free
    took 2 rounds: giving just `BLANK_CODE`(16)'s own *solo* tile its
    own group2 wasn't enough, because a "steady" Sand cell still
    cycles through 8 codes per scroll cycle (1 solo + 7 blend-phase
    frames from the `(BLANK,BLANK)` same-id pair, which goes through
    the same generic PAIRBASE/phase-blend machinery every real
    transition pair does) - only the solo code had moved, so the other
    7 still landed in a rock-colored group 7 out of 8 frames -
    "Sandがチラついてるし色変わってないぞ ８キャラ分変更だぞ". Then,
    even with `(BLANK,BLANK)` fixed, the genuinely *mixed* transition
    pairs (BLANK<->R225_UL/R225D_UR - the exact climb/descend moment at
    Sand's own edge) were *still* landing in a rock-colored group -
    "まだチラついてる Rockの前後だけおかしい".
  - **`BLANK_PAIR_BASE`, round 1 (later found to be over-scoped)**:
    every pair with `BLANK_ID` on either side (not just the same-id
    one) got its own dedicated, group-aligned 8-code block - `SAND_
    GROUPS` grew to 3 groups (2-4), all painted `SAND_COLOR`.
  - **This broke Rock225 itself**: giving the *mixed* transition pairs
    `(BLANK,R225_UL)`/`(R225D_UR,BLANK)` (the actual climb/descend edge
    right at Sand's own border - not steady Sand, and not steady Rock
    either) `SAND_COLOR` painted Rock225's own diagonal marker with
    Sand's dark-yellow fg on Sand's light-yellow bg - low-contrast,
    reading as "part missing" - while Rock225's *steady* tiles (still
    in the shared rock pool, dark-yellow bg at the time) sat right next
    to those newly light-yellow-bg mixed frames, a visible bg seam at
    every climb/descent - direct correction: "お前Rock225弄ったんか
    勝手なことしてんじゃねえよ Rock225の背景色がダークイエローだから
    チラついてる上に一部が欠けてるじゃねえかよ 誰がRock関係いじれつっ
    た じゃあRock225の背景色ライトイエローにしろ" (did you touch
    Rock225? don't do things unasked - its bg is dark yellow, that's
    why it flickers AND part of it is missing - who told you to touch
    Rock stuff - make Rock225's bg light yellow).
  - **The actual fix turned out simpler than a 3rd dedicated color**:
    rather than giving Rock225 its own separate group, `ROCK_COLOR`
    itself changed bg from dark yellow(10) to light yellow(11) -
    "カラーグループ節約するから Rockも背景色ライトイエローにしろ
    Rock225と同じだ" (to save color groups, make plain Rock's bg light
    yellow too, same as Rock225). With Rock/R225/every mixed transition
    pair all sharing one bg, the whole "BLANK-involving pairs need
    their own group" premise no longer applies except to genuinely
    *steady* Sand - so `BLANK_PAIR_BASE` was reverted back to just the
    `(BLANK,BLANK)` same-id pair (the one case with real *temporal*
    flicker within a single physical cell, unrelated to Rock at all),
    and every mixed pair went back into the ordinary rock-colored pool,
    where its diagonal edge reads in Rock's own red fg again instead of
    sand-on-sand. `SAND_GROUPS` shrank back to 1 group (just group2),
    `MAX_CODE` dropped to 79. **Rock225's own art/bits were never
    touched at any point in this whole saga** - only which color group
    its derived pattern/blend codes landed in.
  - Verified: rebuilt the per-cell ground truth directly from
    `TERRAIN_RENDER_ROW`'s own phase==0/phase!=0 logic (not just an
    id-adjacency heuristic, which produces false positives once a
    phase-0 solo-BLANK cell borders a differing next id) and cross-
    checked every column/row over 500 frames through the first climb:
    every emitted code exactly matches the Python model's own
    `SOLOTAB`/`PAIRBASE` prediction, and a code lands in group2 if and
    only if the cell is genuinely showing pure BLANK content (solo, or
    the `(BLANK,BLANK)` blend pair) - never for a Rock/R225 id, steady
    or mid-transition, in either direction.
  - **Round 3** ("Rock225の前後にゴミ出てんだよ"): mixed-pair blend
    frames still used the real textured Sand tile, so its speckle bits
    leaked into the rock-colored frame as red flecks. `_blend_tile()`
    swaps in a flat placeholder for BLANK's side in mixed pairs only;
    steady Sand is untouched. Rock225's own pattern bytes never
    changed.
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
