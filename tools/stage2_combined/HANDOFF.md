# Handoff — CYBER_SUZUKA stage2 combined test

Session handoff written 2026-08-23. Read this first, then `README.md`
in this same directory for the full chronological changelog (every
round quotes the user's exact Japanese instruction).

## Where things are

- **Main source**: `combined_test.asm` (this directory). Single file,
  assembled by `build_test.py` via `../mini_z80asm.py` (a custom, non-
  standard Z80 assembler — see "Assembler quirks" below).
- **Build**: `python3 build_test.py` from this directory. Writes
  `combined_test [ASCII16].rom` (also in this directory, committed to
  git — always rebuild and re-commit it after any `.asm` change).
- **Regression suite**: `tests/` (in this directory, **just added to
  git this session** — previously these lived only in an ephemeral
  scratchpad and would NOT have survived a session handoff). Run
  `python3 tests/run_all.py` for the full suite (180 checks as of this
  commit). Each file is also independently runnable and self-reports
  `N passed, M failed`.
- **Emulator**: `../z80emu.py` — a from-scratch Z80 interpreter used
  for all verification. Known limitation: **no interrupt simulation**
  and no cycle-accurate VDP timing. This was the root cause of one real
  bug this session (see README's `STACKTOP` entry) — when a class of
  bug seems invisible to sweeps, consider measuring something more
  directly (e.g. SP depth mid-frame) rather than trusting a sweep alone.
- **Visual verification**: `render_check.py` renders VRAM state to a
  PPM image (`render_full(cpu.vram, path)`). `tests/night_visual_check.py`
  is a working example. Convert to PNG with PIL if you need to actually
  look at it (`Image.open(...).save(...)`).

## The user

Communicates in terse, often angry Japanese. Expects:
- Every change verified via the emulator (unit tests + a real
  `MAINLOOP`-driven sweep, not just static reasoning) before being
  reported as done.
- README changelog entries quoting their exact Japanese instruction
  verbatim, describing what was verified.
- A ROM sent after every round via the file-delivery mechanism.
- **Never** attribute a reported bug to their own testing, timing, or
  environment without hard, direct proof — this has caused real anger
  multiple times in the project history. If a fix seems to depend on
  "you didn't wait long enough" or similar, that reasoning needs to be
  airtight and phrased as a mechanism you found, not an excuse.
- Concise Japanese replies. No hedging language when reporting results
  — either it's verified or say plainly what's still uncertain.
- Commits use the trailer:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01GsjpWGqxCfbFmZ1YJEowym
  ```
  (Session ID may need updating for a genuinely new session — check
  with `get_session` if unsure.)

## Recently learned, non-obvious facts about this codebase

- **"カウンター" (counter) means `GAME_TICK`**, not raw frame count and
  not `ENEMY_SPAWN_COUNT`. `GAME_TICK` is the number `GAME_TICK_DISPLAY`
  draws top-right, and it only advances once every 8 raw frames (see
  its own INIT-area comment: "Stage1は地形書き換え8回に1回カウントす
  る作り すべての基準はこのカウント"). This was gotten wrong twice in
  a row before landing on the right variable — see README's "カウンタ
  ー" entries for the full story. If a future instruction mentions a
  "counter" threshold, it almost certainly means `GAME_TICK`, not
  frames and not any other internal counter.
- **Row numbering is 1-indexed in the user's own instructions** (row0 =
  "1st row", row1 = "2nd row", etc.) even though the code is obviously
  0-indexed. Confirmed via a real screenshot correction (see README's
  `NIGHT_START_ROW` entry). When an instruction says "N行目", it means
  0-indexed row `N-1`. Counting **from the bottom** ("下からN行目") is
  an ordinary ordinal count and does NOT have this ambiguity (1st from
  the bottom = the literal last row) — only counting from the top does.
- **SCREEN1 color is per 8-code group, not per screen position.** Any
  time you need two different colors for the same pattern/shape
  depending on context (day vs night, sky vs rock), you need a whole
  new pattern code (usually a byte-for-byte copy of the existing
  pattern data) in its own dedicated group — you cannot recolor a
  shared code conditionally. This session added `NIGHT_CODE` (group17)
  and `BULLETF_NIGHT_CODE`/`BULLETF_L_NIGHT_CODE` (group18) for exactly
  this reason. Groups 0-16 and 31 are taken (terrain/rock/sand/HUD/
  life-bar/digits/bullets/SkySand) — 19-30 are still free, minus
  whatever this session used most recently (check `combined_test.asm`
  for the latest `EQU ... group` comments before allocating a new one).
- **The custom assembler (`mini_z80asm.py`) is missing ordinary Z80
  instructions** — confirmed missing: `EX DE,HL` (use `LD D,H : LD E,L`
  instead). Its expression evaluator only supports `+ - * /`, left-to-
  right, no operator precedence and no parentheses — write constant
  expressions as plain literals rather than anything clever.
- **Night-transition effect** (`CHECK_NIGHT`, `NIGHT_START_TICK`=850 in
  `GAME_TICK` units as of this session, was 100 then 900): sweeps 1 more
  row black every `NIGHT_INTERVAL`(8 as of this session, was 16)
  `GAME_TICK`s, from `NIGHT_START_ROW`(1) through `NIGHT_END_ROW`(16,
  the SkySand row). `NIGHT_ROW` (RAM) tracks the current leading row —
  compare a row number against it (`NIGHT_ROW>=row` means "already
  darkened by the sweep") any time new code needs to know whether a
  specific row is currently dark. Don't gate on
  `GAME_TICK>=NIGHT_START_TICK` alone for anything row-specific — the
  sweep takes real time to reach any given row. Also: any GAME_TICK
  threshold compare MUST be a real 16-bit one (`SBC HL,DE`, the idiom
  `CHECK_NIGHT`'s own timer uses) once the threshold can exceed 255 -
  Z80's `CP` only ever takes an 8-bit immediate, and this custom
  assembler silently truncates an out-of-range one with no error
  (`n & 0xFF`, no range check) instead of failing the build. Found
  exactly this bug in `CLOUD_UPDATE_ALL`'s own cloud-stop gate when
  `NIGHT_START_TICK` moved from 100 to 900 this session — see README's
  own entry on it for the full story.
- **Endgame `GAME_TICK` timeline, all sharing one clock**:
  `NIGHT_START_TICK`(850) starts the night sweep above; `ENEMY_SPAWN_
  STOP_TICK`(950) stops every ordinary enemy type (ZacoII/Zum/BigZum/
  Flyer/Etank) from spawning again, via a shared `SPAWN_STOPPED` helper
  every `ALLOC_*_SLOT` routine calls first — don't add a 6th hand-
  rolled `GAME_TICK` compare for a new enemy type, call this instead;
  `BOSS_SPAWN_TICK`(999) spawns the boss (Sasapi) once. By direct
  instruction ("自機以外はもうスポーンしないんで オールフリー"), once
  spawning has stopped at 950 every ordinary enemy's own hw-sprite-slot
  and pattern-VRAM budget is fair game to reuse for later systems (the
  boss reuses Zum/BigZum/Flyer/Etank's hw slots10-25 and BigZum's whole
  pattern-code footprint 156-219, loaded fresh at boss-spawn time, not
  INIT) — the real budget (32 hw sprite slots, ~256 sprite pattern
  codes) doesn't have room for a 64x64 boss (16 hw-sprite quadrants, 64
  pattern codes) as a NEW permanent allocation on top of everything
  already using it.
- **Sprite pattern VRAM has a real base offset (`SPRPAT`=0x3800h) that's
  easy to forget** — a hardware sprite's pattern data lives at
  `SPRPAT+pattern*8`, NOT `pattern*8` alone (that bare form lands in the
  BG pattern table's own address space instead, silently). Missing
  `+SPRPAT` on a fresh `LDIRVM` pattern load produces a build that
  passes unit tests testing VRAM state against itself (comparing loaded
  bytes against the SAME wrong address the buggy code wrote to) but
  renders visibly wrong (leftover/garbage patterns) the moment you
  actually render a frame — caught exactly this way building the boss
  this session. Any pattern-load check needs to compare against
  `SPRPAT+PAT_xxx*8`, and any new sprite needs an actual render, not
  just unit tests, before calling it verified.

- **Any VRAM write bigger or more frequent than this file's usual small
  per-frame sprite writes needs its own DI/EI interrupt-safety check —
  don't assume an existing unprotected `LDIRVM` call is "safe
  precedent" just because nothing was reported against IT yet.** This
  file already documents the bug class once (`UPDATE_TANK_SPRITES`'s
  own comment: `LDIRVM` has no interrupt-safety margin, `MAINLOOP`
  never `HALT`s for vblank, so an H.TIMI landing mid-write can corrupt
  the VDP's own write-address counter and scribble stray bytes wherever
  the interrupt handler leaves it — real-hardware garbage `z80emu.py`
  can never reproduce, since it has no interrupt simulation at all).
  This session repeated it building the boss (`FLUSH_BOSS_SPRITES`'s
  64-byte single-`DI` burst — 2x this file's next-biggest per-frame
  sprite write, BigZum's 32 — and `LOAD_SASAPI_PATTERNS`'s wholly
  unprotected 512-byte `LDIRVM`), reported back as real "tearing, plus
  small garbage at unrelated VRAM locations" - exactly this bug's own
  signature, not a sprite-priority/scanline-count issue (that theory
  was floated first and was WRONG — see README's own correction entry).
  Fixed by chunking the per-frame write into 16 small per-quadrant
  DI/EI-wrapped mini-bursts, and wrapping the rare (not per-frame)
  512-byte load in a plain DI/EI pair. **Etank's own analogous runtime
  pattern-VRAM share (`PAT_ETANK_BL`/`_BR`, 64 bytes) still has this
  exact same unprotected-`LDIRVM` exposure and was NOT fixed this
  session** (out of scope, left as a known latent issue, not "proven
  safe") — worth fixing preemptively rather than waiting for it to get
  reported the same way.
- MSX1/TMS9918 also has a real per-scanline sprite limit (max 4,
  separate from — and much stricter than — the 32-slot total budget),
  which `z80emu.py` doesn't model either. The boss's own 4x4 quadrant
  grid was already deliberately designed around this (confirmed by
  direct instruction: "敵の出現制限も全て横並びを回避するため") — this
  was NOT the cause of the flicker reported this session, and this
  theory was already explicitly rejected — see the entry right below.
- **Do NOT touch `MAINLOOP`'s own terrain-scroller redraw
  (`NAMEBUF_T0`-`T3`) again without hard, direct evidence it's actually
  involved.** A follow-up round DI/EI-wrapped it on the theory that its
  every-frame unprotected `LDIRVM` was the real source of the boss-
  adjacent tearing/garbage report above — reasonable-sounding (it IS
  the most-exercised unprotected `LDIRVM` in the file) but was flatly
  wrong and immediately reverted: "根拠のない推測で無関係な処理に手を
  入れんな 地形スクロールなんて関係ないわ それならボスまでに問題が
  起きてるだろうが そこは非常に重要な処理だから勝手にいじってんじゃ
  ねえよ お前の実装に問題があるだけだ". The user's own logic: terrain
  redraw runs every single frame from the very start of the game, so if
  IT were the real cause, the same corruption would show up constantly
  throughout ordinary play, not specifically in boss-adjacent testing -
  it doesn't, so it isn't. The real bug is still somewhere in the
  boss's OWN code specifically (not yet found as of this handoff) - the
  `FLUSH_BOSS_SPRITES`/`LOAD_SASAPI_PATTERNS` DI/EI fixes from the
  round before this one are still in place (never shown wrong, just not
  yet confirmed as the actual full fix either) but re-examine the boss
  itself next, not adjacent systems, however plausible the theory feels
  - and don't touch terrain-scroll again on speculation alone.

## ⚠ Current build is a DIAGNOSTIC (boss display-only + enemy systems disabled)

- `GAME_TICK` boots at **840**, not 0 (`LD HL,840 : LD (GAME_TICK),HL`
  in `INIT`, ~line 1742) — night starts almost immediately and the boss
  spawns shortly after. **7 regression tests fail as a direct, expected
  consequence** of this diagnostic build, not a regression:
  - `etank_gametick_gate_test.py`/`night_effect_test.py` (1 each): the
    same known GAME_TICK=840-boot effect as every earlier diagnostic
    round this session (checks "doesn't happen before real frame X"
    against a boot-at-0 assumption).
  - `boss_test.py` (5): the patrol-movement checks (`steps left by
    BOSS_SPEED`, `reaches X=0`, `reverses to DIR=1`, `mirrored facing
    reloaded`, real-MAINLOOP spawn-timing) now correctly fail because
    the boss's movement is intentionally disabled below - not a bug.
  Revert `GAME_TICK` to `XOR A`/0 for a real shipped build.
- **Terrain-scroll-freeze-on-boss-spawn (the round right before this
  one) was tried, reported as no change in the tearing AND as causing
  its own visible corruption (no redraw-recovery logic exists for
  resuming terrain after a freeze) - reverted, unconditional again.**
  Not a bug per the user ("これはバグではないので今ははよい") since it
  was never meant to ship, just not worth chasing further right now.
- **Every ordinary enemy type's own per-frame update+flush is now
  skipped entirely once the boss is active** - "使われない物を呼ぶのは
  無駄だし ボスはStage1でもそうだが それまでの処理は捨ててボス専用
  もうザコは出ないからな". `MAINLOOP` now checks `BOSS_ACT` before
  `UPDATE_ENEMIES`/`CHECK_BULLET_VS_ENEMY` and again before `UPDATE_
  ZUM_ALL` through `UPDATE_TANK_ETANK_PUSH` (ZacoII, Zum, BigZum, Flyer,
  Etank, and their own bullet-collision/tank-push-punch reactions), all
  skipped once `BOSS_ACT!=0` - real per-frame VDP write volume removed
  (5 separate DI/EI-wrapped `FLUSH_*_SPRITES` bursts every frame,
  regardless of whether their pools had anything active). `UPDATE_
  BULLET_U_SPRITES` (the PLAYER's own shot rendering, not an enemy
  system - do not confuse the two) sits between the two gates and stays
  unconditional, unaffected. Verified: ZacoII's own hw slots (4-6, the
  only range not reused by the boss itself) go byte-identical forever
  from the instant the boss spawns - confirms the flush genuinely
  stopped running, not just "writing the same bytes as before."
- **`UPDATE_BOSS_ALL` now skips its own movement entirely once spawned
  - "ボスは表示だけで動かさないでくれ"**: `JR NZ,UBA_MOVE` (branch to
  the patrol/reversal/pattern-reload logic once already spawned)
  changed to `JR NZ,UBA_DRAW` (skip straight to the same per-frame
  `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` every other frame already does, at a
  frozen `BOSS_X`/`BOSS_DIR`) - `UBA_MOVE` and everything under it is
  now dead code, never jumped to, left in place rather than deleted
  since this is a diagnostic, not a permanent change. Isolates whether
  the tearing depends on the patrol logic itself (X update, edge-clamp,
  the 512-byte pattern reload on direction reversal) versus showing up
  purely from the same per-frame 64-byte hw-sprite-table flush
  regardless of motion. User's own reasoning for doubting a sprite-count
  cause at this point: 64x64 doesn't hit the per-scanline limit, the
  boss only uses 16 of 32 hw slots, the tank's own slot is fixed, so
  ~20 used / 12 free even together.
  Verified via `banked_helpers`: boss spawns at the expected frame,
  `BOSS_X` stays exactly at `BOSS_SPAWNX`(192) and `BOSS_DIR` never
  changes for 400+ frames after spawn - confirms the freeze itself
  works exactly as written; `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` are still
  called every frame (same as before), only the movement is gone.
  **Whether this changes the real-hardware/WebMSX tearing is NOT
  verifiable here** (`z80emu.py` has no interrupt simulation) - only the
  user can judge that from real playback.
- Prior rounds this session, all reported "no change" and reverted:
  interrupt-unsafe boss VRAM writes (fixed regardless, kept - see
  README's DI/EI entry), terrain-scroll DI/EI-wrap (wrong theory,
  explicitly rejected by the user), Flyer-art-swap and real-4-Flyer-
  instance tests ("one big op vs many small ops" theory), terrain-
  scroll-freeze (see above). The per-scanline sprite limit theory was
  also explicitly rejected early on as something already designed
  around, not the bug.
- **Y=208 (SAT early-terminator) theory checked and NOT observed**:
  raised by the user as a real TMS9918 hardware quirk (Y=0xD0 in any
  SAT slot stops the VDP from evaluating every later-numbered slot that
  frame - distinct from Y=209's own per-sprite hide idiom, which this
  file already uses consistently everywhere, confirmed by grep - no
  literal 208 exists anywhere in the source). INIT clears all 32 slots
  to 209 at boot, and a real 9200-frame `MAINLOOP` sweep (varying
  direction/A/B input every frame, spanning boot through well past
  boss-spawn) found Y=208 in **zero** of the 32 slots at **any** sampled
  frame. Rules out "ordinary game logic accidentally produces 208" as
  the cause - does NOT rule out a genuinely transient interrupt-torn
  byte landing on 208 mid-write, same "can't verify either way"
  limitation as the tearing itself (`z80emu.py` has no interrupt sim).
- **Now confirmed and fixed: every ordinary enemy type's own per-frame
  flush kept running, unconditionally, forever, even once fully
  inactive**: `FLUSH_ENEMY_SPRITES`/`FLUSH_ZUM_SPRITES`/`FLUSH_BIGZUM_
  SPRITES`/`FLUSH_FLYER_SPRITES`/`FLUSH_ETANK_SPRITES` (each its own
  DI/EI-wrapped VRAM burst) were called every single `MAINLOOP` frame
  regardless of whether their own pool had anything active -
  `ENEMY_SPAWN_STOP_TICK` only ever gated new spawns, never the
  per-frame update+flush of an already-fully-hidden pool. This meant
  real, needless per-frame VDP write volume (5 separate DI/EI bursts)
  stacking on top of the boss's own 16-quadrant writes for the entire
  rest of the game once the boss is active - see README's own entry for
  the fix (all 5 enemy types + their bullet-collision/tank-push-punch
  reactions now skipped entirely once `BOSS_ACT` is set, per direct
  instruction: "使われない物を呼ぶのは無駄だし ボスはStage1でもそうだ
  が それまでの処理は捨ててボス専用 もうザコは出ないからな").
  `UPDATE_BULLET_U_SPRITES` (the PLAYER's own shot rendering, not an
  enemy system) stays untouched, still runs every frame regardless.
  Verified: ZacoII's own hw slots (4-6, the one range not reused by the
  boss - Zum/BigZum/Flyer/Etank's own 10-25 range IS reused by the boss
  itself, so checking those wouldn't isolate anything) go byte-identical
  forever from the instant the boss spawns, confirming the flush
  genuinely stopped, not just "still writing the same bytes."

## ⚠ New feature this round: U (diagonal shot) switches to BG drawing during the boss fight

- **The tearing IS gone** ("チラツキ止まった" - confirmed by the user on
  real hardware/WebMSX) after skipping the now-unused enemy systems'
  own per-frame flush once `BOSS_ACT` is set. Cause unconfirmed either
  way by the user themselves ("209クリアか 無駄なルーチン呼び出しか分
  からんが") - could be the Y=209 boot-clear angle checked earlier, or
  simply the reduced per-frame VDP write volume, or both together. Not
  worth chasing further per the user's own "できたから良し".
- **New, separate issue reported**: "自機ショットで消えてしまう問題があ
  るので ボス戦になったら斜めショットをBG描画に変更" - U (the diagonal/
  climbing shot, `BULLET0/1/2_ACT`'s own `IX+1`=1) was disappearing
  during the boss fight while still a hw sprite (slots7-9). Per the
  file's own history (see `BULLET_U_SPR_BASE_SLOT`'s own comment), U
  used to be BG-drawn exactly like F still is, before an earlier round
  converted it to a hw sprite and DELETED the old BG-drawing code
  entirely ("弾は斜のみスプライトに変更...斜めうちのBG関係の弾の処理
  は削除"). This round rebuilds an equivalent BG-drawing path for U,
  gated to ONLY run while `BOSS_ACT!=0` - outside the boss fight, U is
  still a plain hw sprite, completely unchanged.
- **New BG pattern codes**: `BULLETU_SKY_CODE`(89)/`BULLETU_L_SKY_
  CODE`(91) (group11), `BULLETU_ROCK_CODE`(99)/`BULLETU_L_ROCK_CODE`
  (100) (group12), `BULLETU_NIGHT_CODE`(146)/`BULLETU_L_NIGHT_CODE`
  (147) (group18) - all placed in the SAME 3 groups F's own
  `BULLETF_*_CODE`s already claimed and colored (each group only had 2
  of its 8 codes used), so no new SCREEN1 color-table writes were
  needed, just `BULLET_U_PATTERN`/`BULLET_U_L_PATTERN` (new raw 8x8
  exports from `bullet_gen.py`, distinct from `BULLET_U_SPRITE`/`_L`
  which pad the same art into a 16x16 hw sprite canvas) loaded into
  these 6 codes at `INIT`.
- **`DRAW_BULLET_CELL`** (shared by F and now U) branches on `IX+1`
  (bullet TYPE) at each of its 3 background-band leaves (night-sky/day-
  sky/rock - though day-sky is provably unreachable for a `BOSS_ACT=1`
  call, since the night sweep is always fully complete well before
  `BOSS_SPAWN_TICK` - see `NIGHT_START_TICK`'s own entry - implemented
  anyway for correctness/symmetry rather than leaning on that timing
  coincidence silently). **`ERASE_BULLET_CELL` needed NO changes at
  all** - it only ever restores the background that was there
  regardless of which bullet type occupied the cell, so it already
  worked correctly for U the moment its call sites started calling it.
- **3 call sites gated on `BOSS_ACT`**: `TRY_SPAWN_BULLET` (draws
  immediately on spawn), `UPDATE_ONE_BULLET`'s own erase-before-advance
  and draw-after-advance (`UOB_SKIP_ERASE`/`UOB_DRAW`) - each now reads
  `IX+1`(TYPE) first (F always proceeds), and for U checks `BOSS_ACT`
  before falling through to the same F path. **`UBUS_ONE`** (U's own hw
  sprite positioning) now also hides the slot (Y=209) whenever
  `BOSS_ACT!=0`, even for an active U-type shot - otherwise the (already
  reported-broken) hw sprite would sit uselessly on top of the new BG
  cell, still costing a real per-frame VDP write for nothing.
- Verified: `tests/bulletu_boss_bg_test.py` (new, 8 checks - BG code
  selection for all 4 band/facing combinations, hw sprite hidden while
  `BOSS_ACT=1` vs shown normally while `BOSS_ACT=0`, and a real
  `MAINLOOP` end-to-end firing a diagonal shot after boss-spawn that
  confirms a real `BULLETU_*` code lands in VRAM during flight while the
  hw sprite slot stays hidden throughout) all pass. Full suite: 173/180
  - same 7 failures as the prior 2 diagnostic rounds (GAME_TICK=840 boot
  effect + boss's own intentionally-disabled movement), no new
  regressions from this change.

## Open items / things to watch

- No known open bugs as of this handoff — the boss's own SPRPAT bug
  (see above) was caught and fixed before shipping; the last several
  rounds before that were bug reports against the night effect and
  horizontal-shot coloring, all resolved and verified (see README's
  most recent entries). The per-scanline flicker (see above) is a real
  hardware limit, not something fixed in code.
- **The boss (Sasapi) has spawn+patrol movement (both facings, reloaded
  on direction change) only** — HP is stored (255) but nothing reads or
  decrements it, no collision box, no death/explosion state. Deliberate
  scope so far ("取り敢えず確認") — don't assume any of it exists until
  asked to add it.
- `BOSS_SPAWN_Y`(56) was read as "the sprite's own bottom edge sits 8px
  above SkySand's top row" - an interpretation, not confirmed by a
  screenshot yet. If a future instruction implies a different vertical
  position, that's the thing to revisit first, same as
  `NIGHT_START_ROW`'s own history of a wrong first guess.
- **BigZum's own STATE field now goes up to 5** (forced retreat once
  `GAME_TICK>=ENEMY_SPAWN_STOP_TICK` - see `UPDATE_ONE_BIGZUM`'s own
  top-of-function check) - any future code reading/switching on
  `BIGZUM_POOL+7` needs to account for this 6th value, not just 0-4.
- The row-range boundaries in the night-glyph work (`DRAW_BULLET_CELL`,
  `ERASE_BULLET_CELL`) went through 2 wrong guesses before landing
  correctly — re-read the last 4-5 README entries in full before
  touching that code again, the reasoning is subtle (SCREEN1 color-
  group constraints + the SkySand row's own special status).
- `tools/stage2_combined/scratchpad`-style one-off diagnostic scripts
  (sweeps, debug traces, etc.) are NOT in `tests/` and were NOT carried
  over — only the durable, README-referenced regression suite was.
  If you need to re-run a specific historical investigation, it isn't
  here; you'd write a fresh one using `tests/banked_helpers.py`.
