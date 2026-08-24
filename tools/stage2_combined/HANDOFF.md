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

## The tearing is fixed - history of the diagnostic rounds (all reverted/superseded now)

**Current state (post boss-collision/pose rounds): `GAME_TICK` still
boots at 840** (kept as a real, ongoing testing convenience, not a
leftover - revert to `XOR A`/0 for a real shipped build) - **but the
boss's own movement is fully real again**, no longer frozen. See "Boss
patrol/attack-pose redesign" below for the current, real per-frame
behavior. Everything below this line is the historical record of how
the tearing got fixed.

- **The tearing IS confirmed fixed** ("チラツキ止まった", real
  hardware/WebMSX) after skipping the now-unused enemy systems' own
  per-frame flush once `BOSS_ACT` is set (next bullet). Root cause
  never fully isolated by the user themselves ("209クリアか 無駄な
  ルーチン呼び出しか分からんが") - not worth chasing further, "できた
  から良し".
- **Every ordinary enemy type's own per-frame update+flush is now
  permanently skipped once the boss is active** - "使われない物を呼ぶ
  のは無駄だし ボスはStage1でもそうだが それまでの処理は捨ててボス専
  用 もうザコは出ないからな". `MAINLOOP` now checks `BOSS_ACT` before
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
- **Terrain-scroll-freeze-on-boss-spawn (an earlier round) was tried,
  reported as no change in the tearing AND as causing its own visible
  corruption (no redraw-recovery logic exists for resuming terrain
  after a freeze) - reverted, unconditional again.** Not a bug per the
  user ("これはバグではないので今ははよい") since it was never meant to
  ship, just not worth chasing further.
- **`UPDATE_BOSS_ALL`'s own movement was temporarily disabled for one
  diagnostic round ("ボスは表示だけで動かさないでくれ") to isolate
  whether the tearing depended on the patrol logic itself versus the
  per-frame sprite flush alone - it was later fully restored (see "Boss
  patrol/attack-pose redesign" below) once the real fix (skipping
  unused enemy flushes) was confirmed. User's own reasoning for doubting
  a sprite-count cause at this point: 64x64 doesn't hit the per-scanline
  limit, the
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

## Boss now has real collision, HP, and a boss-only red hit-flash

- "ではボスにコリジョン 見た目通り 耐久値255 んでフラッシュ処理はホワ
  イトだと眩しいのでレッドに ボス戦だけな 通常はホワイトのままでいじ
  るな". `CHECK_BULLET_VS_BOSS`/`CHECK_HIT_PAIR_BOSS` (new) AABB-check
  every bullet against the boss's own real 64x64 box (`BOSS_COLLISION_
  SIZE`=64, `BOSS_X`..+63/`BOSS_SPAWN_Y`..+63 - the full visible
  footprint, not a smaller hitbox), only while `BOSS_ACT=1`. On a hit:
  `ERASE_BULLET_CELL` unconditionally (both F and U are guaranteed
  BG-drawn during this exact window - see the U-BG-drawing entry above
  - so no type branch is needed here, unlike `CHECK_HIT_PAIR_FLYER`/
  `_ETANK`), deactivate the bullet, decrement `BOSS_HP`, then either arm
  `BOSS_FLASH_TIMER` + play `SOUND_ZUM_DEFLECT` (non-lethal) or destroy
  the boss (HP hit 0).
- **`BOSS_FLASH_COLOR`(8, medium red) is its own dedicated constant -
  the shared global `FLASH_COLOR`(white) every OTHER entity's hit-flash
  uses is untouched, per direct instruction.** Deliberately not `BOSS_
  COLOR`'s own light red(9) either, so the flash actually reads as a
  distinct color change - confirmed by rendering an actual frame (see
  README), the boss visibly shifts to a clearly deeper/more saturated
  red on a hit, not an invisible same-color flash.
- **New `BOSS_ACT=2` state ("destroyed, permanently gone") was a real
  design necessity, not just a nice-to-have**: the existing `BOSS_ACT`
  field only had 0(not spawned)/1(active) before this round, and
  `UPDATE_BOSS_ALL`'s own spawn check runs whenever `BOSS_ACT=0` - so
  simply zeroing it on death would have looked identical to "never
  spawned yet" and the very next frame would have immediately
  re-triggered `GAME_TICK>=BOSS_SPAWN_TICK` and re-spawned it. Added a
  `CP 2/RET Z` guard at the very top of `UPDATE_BOSS_ALL`, before the
  existing active-check, so a destroyed boss is left alone forever.
  `HIDE_BOSS_SPRITES` (new, same per-quadrant DI/EI idiom as `FLUSH_
  BOSS_SPRITES` but 1 OUT/quadrant instead of 4 - only the Y byte
  matters once hidden) runs once at the exact moment of death, since
  nothing else will ever touch those 16 hw sprite slots again once
  `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` stop being called for a `BOSS_ACT=2`
  boss.
- **Scope decision, not yet requested - death is a plain disappearance,
  no explosion**: unlike every other entity's own destroy path (random
  drift, `EXPLOSION_DURATION` animation, `SOUND_DESTROY`, score add via
  `ADD_SCORE`), the boss just vanishes the instant HP hits 0 (`BOSS_
  ACT=2` + hidden). Easy to add if the user wants parity with the other
  entities' own explosion - left out since the instruction didn't ask
  for it, and what should actually happen when the boss dies (does the
  stage/game end? a victory state?) hasn't been specified at all yet.
- Verified: new `tests/boss_collision_test.py` (18 checks, including a
  real end-to-end `MAINLOOP` sweep - spawn for real, drive HP to 0 via
  repeated real hits, confirm it stays destroyed through 120 more real
  frames) all pass, plus a real `render_full` frame render confirming
  the flash color visually. Full suite: 199/206 pass, same 7 known
  failures as every round since the GAME_TICK=840/boss-frozen-movement
  diagnostics began - no new regressions.

## Boss patrol/attack-pose redesign - movement is real again, right-edge triggers an attack pose

- **The "ボスは表示だけで動かさないでくれ" diagnostic (no movement) is
  now fully REMOVED - the boss patrols for real again.** This was a
  hard prerequisite for this round's own instruction, which explicitly
  describes real patrol behavior ("右から出て左に行き反転して右端に戻
  ったら"). `UPDATE_BOSS_ALL`'s top-level dispatch changed from `JR
  NZ,UBA_DRAW` (unconditional skip straight to drawing) back to `JR
  NZ,UBA_ACTIVE` (real patrol logic runs again).
- **New instruction, in full**: "では巡回 前回はループだったが 右から
  出て左に行き反転して右端に戻ったら 添付のパターンをBGに描画しスプラ
  イトは一旦消す ようするに移動中はスプライト 停止中はBGて切り替え こ
  れは攻撃ポーズなのでその状態で32Tick停止後 また巡回 BGは消してスプ
  ライトに戻す 攻撃内容はまた今度". The LEFT-edge reversal (X=0 -> DIR=
  1, mirrored facing reload) is completely unchanged - still an
  ordinary patrol reversal. Only the RIGHT-edge return (X=BOSS_SPAWNX)
  changed: instead of immediately reversing and continuing the loop, it
  now enters a new "attack pose" phase.
- **New `BOSS_PHASE` field** (0=patrolling/hw-sprite, 1=parked in the
  pose/BG-art) drives this as a small sub-state-machine inside
  `UPDATE_BOSS_ALL`: reaching the right edge sets `BOSS_PHASE=1`, arms
  `BOSS_POSE_END_TICK` (`GAME_TICK+BOSS_POSE_TICKS`(32) at that exact
  moment, a true 16-bit `SBC HL,DE` compare - same idiom as every other
  `GAME_TICK` threshold in this file, NOT a raw-frame countdown like
  `FLASH_DURATION`/`EXPLOSION_DURATION` - "32Tick" means GAME_TICK units
  throughout this session's own instructions, e.g. Tick850/900/950/999),
  calls `HIDE_BOSS_SPRITES` (reused from the death path - hides all 16
  hw sprite slots, Y=209) and `DRAW_SASAPI_HAND` (paints the attack-pose
  art), then `RET`s directly - `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` are NOT
  called again until the pose ends. While `BOSS_PHASE=1`, `UPDATE_BOSS_
  ALL` does nothing but check the tick threshold each frame (`RET C` =
  still posing) - no per-frame redraw, since the hand art doesn't change
  while parked (matches this session's own "avoid needless per-frame
  VDP writes" theme from the tearing-fix rounds). Once the threshold
  passes: `BOSS_PHASE=0`, `BOSS_DIR=0` (resumes moving left, same as the
  very first spawn), `ERASE_SASAPI_HAND` (restores the cells to plain
  `NIGHT_CODE`), `LOAD_SASAPI_PATTERNS`(normal facing) reloaded, then
  falls through into the same `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` every
  other frame uses - sprite visible again the same frame the pose ends.
- **New art asset**: `sprites/SasapiHand_64x64.json` (user-uploaded),
  converted by new `sasapi_hand_gen.py` into 64 row-major 8x8 BG tiles
  (name-table order, NOT the TL/BL/TR/BR sprite-quadrant order `sasapi_
  gen.py`/`tank_gen.py` use - this art never becomes a hw sprite). New
  permanent BG pattern-code allocation `SASAPI_HAND_CODE_BASE`(152,
  groups19-26/152-215) - unlike the boss's own body (`SASAPI_QUADS`/
  `_L`, dynamically loaded into BigZum's reused pattern-VRAM), this is
  a genuinely NEW 512-byte block, loaded once at `INIT` (not per-spawn)
  since nothing else uses groups19-26. Colored fg9(light red)/bg1
  (black) - matches both the JSON's own header AND `BOSS_COLOR`/the sky
  band's own already-fully-night-swept color by `BOSS_SPAWN_TICK` (see
  `NIGHT_START_TICK`'s own comment for why the night sweep is always
  complete well before the boss can ever reach this pose).
  `DRAW_SASAPI_HAND`/`ERASE_SASAPI_HAND` write to 8 FIXED, compile-time-
  literal row addresses (`BOSS_SPAWNX`/`BOSS_SPAWN_Y` are both
  constants, so the whole 64-cell block's position - col24-31/row7-14,
  the screen's own last 8 columns - never needs runtime math).
- **Known, unaddressed edge case, documented in-code**: a BG-drawn
  bullet (F always, or U while `BOSS_ACT!=0` - see the U-BG-drawing
  entry above) whose cell happens to overlap col24-31/row7-14 while the
  hand is on screen WAS flagged as a locally-corrupting, unaddressed
  edge case - **confirmed real on real hardware and fixed the same
  round it was reported, see the entry right below.** Also: collision
  (`CHECK_HIT_PAIR_BOSS`) stays fully active during the pose (same
  AABB, same position) - a hit while posing still decrements HP and
  arms the flash timer, but `DRAW_BOSS` (which would normally consume/
  show that flash) isn't called again until the pose ends, so any flash
  armed mid-pose only becomes visible once sprite mode resumes - still
  unaddressed, not asked about. "攻撃内容はまた今度" - the actual
  attack/damage-to-player behavior during this pose is explicitly
  deferred to a future round.
- Verified: new `tests/boss_pose_test.py` (23 checks as of the fix
  round below - left-edge reversal unchanged, right-edge return enters
  the pose instead of reversing immediately, sprite hidden + hand codes
  drawn at the exact expected VRAM addresses the instant the pose
  starts, `BOSS_X`/`BOSS_DIR` frozen and both stay put through several
  more calls while still posing, pose exit exactly at the GAME_TICK
  threshold restores the cells/reloads the normal facing/shows the
  sprite again/resumes DIR=0, and a real end-to-end `MAINLOOP` sweep
  through a full spawn->left-edge->right-edge->pose-entry->pose-exit
  cycle) all pass. `tests/boss_test.py`'s own stale "immediate reversal
  at the right edge" assertions (2 of them) were updated to check for
  pose-entry instead, since that behavior is now intentionally
  different - not a regression, a corrected test. Also rendered a real
  frame during the pose (`render_full`) confirming the hand art actually
  displays correctly at the boss's own position while the hw sprite is
  hidden.

## Bug fix round: erase used the wrong "blank" code, and the flagged bullet-vs-hand corruption really happened

- User's report (with a real WebMSX screenshot at GAME_TICK≈1183):
  "BG復帰処理でSandskyが書き込まれてるな ブランクのブラック でお前が
  指摘してたボスBG表示欠け発生 消えないようにするか 復帰処理で対応".
  Two separate real bugs, both confirmed:
  1. **`ERASE_SASAPI_HAND`'s own `NIGHT_ROW_BLANK8` source table used
     `NIGHT_CODE`, not `HUD_ROW_BLANK_CODE`** - a real bug, not a
     naming confusion caught in review: `NIGHT_CODE` is `CHECK_NIGHT`'s
     own STRIPED leading-row tile (used for exactly 1 row at a time,
     the current sweep frontier - see its own `CN_SET_ROW` comment),
     NOT a general "already dark" restore value; `HUD_ROW_BLANK_CODE`
     (the SAME code `EBC_SKY`'s own already-swept branch already uses)
     is the actual plain solid black. Once the pose ended, the hand's
     own 8x8 cell block showed the striped tile instead of solid black
     - exactly the screenshot's own visible artifact. Fixed by
     switching `NIGHT_ROW_BLANK8` to `HUD_ROW_BLANK_CODE`.
  2. **The bullet-vs-hand-art corruption flagged (not fixed) in the
     round above really happened** - confirmed by the same screenshot.
     Fixed via "復帰処理で対応" (handle it through the recovery
     process) exactly as directed: `DRAW_SASAPI_HAND` is now called
     every frame `UBA_POSE` is still waiting (`UBA_POSE`'s own `RET C`
     early-return became `JR NC,UBAP_END` / `CALL DRAW_SASAPI_HAND :
     RET`), not just once at pose-entry - any bullet-caused corruption
     heals back to the correct tile within 1 more frame, same "restore
     the known-correct value every frame" idiom this file already uses
     for terrain/night, rather than trying to prevent the bullet's own
     write from ever landing there in the first place. A real,
     deliberate per-frame VDP write during the pose specifically (not
     the whole game) - an accepted cost for the fix to actually work,
     not a regression of the tearing-fix rounds' own "avoid needless
     per-frame writes" theme (that theme was about writes with NO
     purpose; this one has one).
  Verified: `tests/boss_pose_test.py` grew from 21 to 23 checks - the
  restore-target check switched from `NIGHT_CODE` to `HUD_ROW_BLANK_
  CODE` (was itself checking the wrong value before this fix, silently
  passing because the buggy code and the buggy test agreed), plus a new
  check that deliberately corrupts one hand cell mid-pose and confirms
  it heals back to the correct code within exactly 1 more `UPDATE_BOSS_
  ALL` call. Also re-rendered a real frame right after a pose ends,
  confirming plain solid black (not the striped tile) is what's
  actually shown. Full suite: 225/228 pass, same 3 known GAME_TICK=840-
  boot-effect failures - no new regressions.

## Hand-pose hit-flash added (asked-for clarification first, then implemented)

- "一度ボス表示欠け復帰処理の代わりにフラッシュ処理してみてくれ コス
  ト的に可能か検証 多分同一パターンの色替えを定義しなきゃならないので
  まあ地形と弾とスコア、ライフ以外は全て空きなので256パターンあれば充
  分だと思うが" - ambiguous enough (replace the corruption-healing
  redraw with something "flash"-based, or add a flash effect alongside
  it?) that it was asked via `AskUserQuestion` rather than guessed at -
  a wrong implementation here would have wasted a full round either
  way. **Answer: add a hit-flash effect for the pose, alongside the
  corruption-healing redraw (not replacing it).**
- **Important technical fact surfaced by the clarifying question
  itself, worth remembering**: BG tiles are NOT like hw sprites here -
  a hw sprite's color is a byte in its own SAT entry (free to change per
  instance, which is exactly why `BOSS_FLASH_COLOR`'s own body-flash
  costs nothing extra), but a BG tile's color is fixed per 8-code GROUP,
  shared by every code in that group. A pure color-table swap can never
  repair the corruption issue (a bullet overwriting one of the hand's
  64 cells with a DIFFERENT PATTERN CODE reference is a shape/reference
  problem, not a color problem) - only rewriting the actual name-table
  code (what `DRAW_SASAPI_HAND`'s per-frame redraw already does) can
  fix that. Keep this in mind before ever proposing "just recolor it"
  as a fix for a BG-layer content bug.
- **Implementation, reusing the existing per-entity flash idiom
  directly**: new `SASAPI_HAND_FLASH_COLORBYTE`(081h, fg8/bg1 - same
  medium-red shade as `BOSS_FLASH_COLOR`, distinct from `SASAPI_HAND_
  COLORBYTE`'s own fg9/bg1 so the flash reads as an actual color
  change) and its own 8-byte source table `SASAPI_HAND_FLASH_COLOR8`.
  `DRAW_SASAPI_HAND` (already called every frame during the pose, per
  the round above) now also resolves+applies this once per call: reads
  `BOSS_FLASH_TIMER` (the SAME shared timer `DRAW_BOSS`'s own body-
  flash uses - safe to share since only one of `DRAW_BOSS`/`DRAW_
  SASAPI_HAND` ever runs in a given frame, `BOSS_PHASE` picks which),
  decrements it once if nonzero, and writes the resolved 8-byte color
  table (normal or flash) to `2000h+19` (groups19-26, the hand's own
  exclusively-owned pattern-code groups - safe to fully recolor, no
  risk of affecting anything else) via a small DI/EI-wrapped LDIRVM.
  **Cost, as asked**: 8 extra bytes/frame during the pose (1 more small
  DI/EI-wrapped LDIRVM), on top of the 64-byte name-table redraw the
  corruption-healing fix already does every frame - negligible relative
  to that existing cost, same cost class as any other entity's own
  flash. This is the FIRST per-frame write to the 0x2000 color-table
  region in this whole file (previously only touched at `INIT`, one-
  time) - DI/EI-wrapped for the same interrupt-safety reason every
  other gameplay-time VRAM write in this file already is.
- Verified: `tests/boss_pose_test.py` grew from 23 to 27 checks -
  normal color before any hit, switches to the flash color and
  decrements the timer once per call (not once per group) when armed,
  reverts to normal once the timer reaches 0 (matches the same "check-
  before-decrement" timing every other entity's own flash timer uses -
  the frame that brings the timer to exactly 0 still shows the flash
  that frame, reverting only on the NEXT call). Also rendered a real
  frame with the flash active, visually confirming the hand shifts to
  the same deeper/more saturated red the boss's own body flash uses.
  Full suite passes with no new regressions beyond the same 3 known
  GAME_TICK=840-boot-effect failures.

## GAME_TICK boots at real 0 again; FLASH_COLOR is now red for every entity, not just the boss

- "Ok では Tickスキップを一旦戻して０に で、ほかの敵のフラッシュ処理も
  レッドに". Two changes:
  1. **The `GAME_TICK`=840 fast-iteration diagnostic (in place since the
     terrain-freeze/tearing-fix rounds) is fully reverted** - `INIT` now
     boots `GAME_TICK` to real 0 again (`XOR A`/`LD (GAME_TICK),A` /
     `LD (GAME_TICK+1),A`). **This has a real, non-obvious consequence
     for future test-writing**: any "real `MAINLOOP` sweep" test that
     waits for the boss to spawn naturally now needs to step through the
     REAL `BOSS_SPAWN_TICK*8`(7992) frames, not the ~1271 frames the 840
     boot allowed - noticeably slower in `z80emu.py`'s pure-Python
     interpreter (tens of seconds, not instant). 2 existing tests had
     hardcoded frame-loop bounds sized for the OLD 840 boot and needed
     fixing this round (see below) - **any NEW boss-related real-sweep
     test must size its own frame loop as `BOSS_SPAWN_TICK*8 + margin`,
     not a small hardcoded literal**, or it will silently under-run and
     report a false failure once GAME_TICK is at a real boot value.
  2. **`FLASH_COLOR` (the shared global hit-flash color every entity
     except the boss used) changed from white(15) to medium-red(8)** -
     the SAME shade `BOSS_FLASH_COLOR` already used, making the two
     constants numerically identical now (left as 2 separate named
     constants rather than consolidated - not asked for, and keeps
     independent tunability if they diverge again later). This
     supersedes the earlier hard instruction to leave the global white
     untouched ("通常はホワイトのままでいじるな") - that constraint no
     longer applies, the user explicitly extended red to everyone.
     No entity's own base color is red except `ETANK_COLOR`(6, dark
     red) - still a visibly distinct shade shift. **Worth knowing**:
     `TANK_COLOR_TL`(the tank's own top-left quadrant) is ALSO already
     8 (medium red) - identical to the new `FLASH_COLOR` - so that ONE
     quadrant shows no visible change during the tank's own hit-flash
     (the other 3, previously black, still clearly flip to red) - a
     real, observed quirk, not flagged as broken since the flash still
     reads clearly overall; mention if the tank's flash ever looks
     "off" on one corner specifically.
  Fixed 2 stale test assumptions this round exposed: `tests/boss_pose_
  test.py`'s own real-sweep frame bound (was a hardcoded 3200, now
  `BOSS_SPAWN_TICK*8 + margin`), and `tests/boss_collision_test.py`'s
  own `BOSS_FLASH_COLOR != FLASH_COLOR` assertion (now correctly
  expects them EQUAL, matching the new unified-red state).

## Homing missile added (boss's own attack content - fired during the pose)

- "ではボス続き 初期Tickを840に ホーミングミサイルを実装 ボスポーズで
  ボス右上あたりから発射し X軸中央辺りまで水平打ち その後ホーミング動
  作", with 5 attached JSON art assets (SL/DL/Down/DR/SR, "180度を5段
  階45度ごと") and precise bucket rules for which facing to show/how to
  move based on X-distance to the tank. `GAME_TICK` boots at 840 again
  (diagnostic, reverted from last round's real-0 boot).
- **Architecture decision, not obvious from the request alone: this is
  a BG-drawn element, NOT a hw sprite**, even though 5 separate JSON
  "sprites" were provided. Two hard reasons, both worth remembering for
  any FUTURE new enemy/projectile: (1) the hw sprite PATTERN-code budget
  (0-255, separate from BG codes) is **already at 0-251 used** (tank 0-
  127, ZacoII 128-135, explosion 136-139, BulletU 140-147, Zum 148-155,
  BigZum 156-219, Flyer 220-251) - only 4 free slots remained, nowhere
  near the 20 a 5-facing hw sprite would need (16x16-padded, 4 codes/
  facing - same "VDP already in 16x16 mode" constraint `BulletU` already
  documents). **Check this budget before ever proposing a new hw sprite
  again** - grep `combined_test.asm`/`*_gen.py` for `BASE_OFFSET`/`PAT_`
  to see current usage. (2) BG-drawing sidesteps the exact per-scanline
  hw-sprite-priority bug class that already forced `BulletU` to BG
  during the boss fight specifically - a projectile flying near the
  boss's own 4-sprites-per-scanline-band quadrants is exactly the kind
  of thing that bug already bit once. New `horming_gen.py` converts the
  5 raw 8x8 bit arrays into BG pattern data (not the TL/BL/TR/BR
  sprite-quadrant order). New permanent codes `HORMING_CODE_BASE`(216,
  group27 - the next free group after the hand's own 19-26) - fg14/bg1
  matching every uploaded JSON's own header exactly.
- **RAM layout deliberately mirrors the bullet pool's own field offsets
  (ACT@0, COL@2, ROW@3, ADDR_LO@4, ADDR_HI@5)** so `ERASE_BULLET_CELL`
  (fully generic - only ever reads those 4 fields) could be reused
  as-is for the missile instead of writing a duplicate. Single slot
  (not a pool) - a full patrol+pose cycle (~448 frames) is far longer
  than the missile's own travel time, so the previous one is always
  gone before the next pose could fire another (matches `TRY_SPAWN_
  BULLET`'s own "drop the attempt if still active" idiom if this
  assumption is ever wrong).
- **Two-phase flight, exactly as specified**: phase0 fires from `HORMING_
  SPAWN_COL/ROW`(29,8 - within the boss's own 64x64 box, its own upper-
  right) always facing SL, moving 1 col/frame straight left (matching
  bullets' own col/row-granular movement, not smooth sub-pixel motion)
  until `HORMING_COL<=HORMING_CENTER_COL`(16, screen-center) - the phase
  flip and that same frame's own movement resolve together in one
  `UPDATE_HORMING` call (worth knowing if writing a test: by the time
  `HORMING_PHASE` reads back as 1, `HORMING_COL` has already taken 1
  more homing step past center, not frozen exactly at the threshold).
  Phase1 (`RESOLVE_HORMING_FACING`) recomputes the facing FRESH every
  frame from the current `TANK_X` distance - "自機方向に追尾" - not
  just once at the phase transition: `|dx|<=TANK_WIDTH`(32) -> Down,
  `32<|dx|<64` -> diagonal (DL if missile right of tank, DR if left),
  `|dx|>=64` -> side (SL if missile right of tank, SR if left) - all 3
  threshold boundaries and both L/R directions independently unit-
  tested. Each facing has a fixed (dcol,drow) step (Down=(0,+1), DL/DR=
  (∓1,+1), SL/SR=(∓1,0)) - discretized 45-degree steps, not real vector
  math (no multiply/sqrt available cheaply on Z80, matches this file's
  general approach everywhere else).
  **Boundary quirk worth knowing**: facing SL exactly at col0 (or SR at
  col31) can't be constructed from a STATIC tank position within the
  valid 0-255 range (the math requires an impossible negative/>255
  `TANK_X`) - but IS reachable in real play if the tank moves rapidly
  away while the missile is mid-approach near an edge, so the col0/
  col31 underflow/overflow guards in `UPDATE_HORMING` are real
  defensive code, not dead code, even though a simple static-tank test
  can't trigger them directly (see `tests/horming_test.py`'s own
  comment - it calls the internal `UH_STEP_SL`/`UH_STEP_SR` labels
  directly with `HORMING_FACING` pre-set to test this specific path).
- **Collision with the tank uses `APPLY_TANK_DAMAGE`** - already
  existed, already had its own comment anticipating exactly this
  ("現在はBigZumのみだがいずれ敵弾実装予定"), no new damage/life-bar
  mechanism needed. AABB vs the tank's real 32x32 box (`TANK_X`/`TANK_
  Y_CUR`) - the missile's own Y actually matters here (unlike the
  facing-selection logic above, which is X-only per the instruction) -
  a hit also arms `TANK_FLASH_TIMER`(matching `FLASH_DURATION`) and
  plays `SOUND_ZUM_DEFLECT`, same convention as every other tank-damage
  source in this file.
- Verified: new `tests/horming_test.py` (38 checks - fire/refire-while-
  active, phase0 straight movement, the phase transition timing, all 6
  bucket-boundary cases on both sides (12 checks), all 5 facings' own
  movement deltas, both edge-underflow guards, a real hit decrementing
  `TANK_LIFE`/arming the flash/deactivating the missile, a clean miss
  registering nothing, and a real end-to-end `MAINLOOP` sweep firing
  during a real pose and confirming real frame-to-frame movement) all
  pass. Also rendered real frames (`render_full`) confirming the
  missile visually appears near the boss's own head at spawn and mid-
  flight during the straight phase - small at thumbnail scale, needed a
  cropped/zoomed render to actually see clearly, but present and
  correctly colored/shaped in both. Full suite: 267/270 pass, same 3
  known GAME_TICK=840-boot-effect failures - no new regressions.

## Homing missile round 2: BG-drawing was WRONG - corrected to a real hw-sprite 4-instance pool

- **The previous round's whole "BG not hw sprite" decision above was
  corrected by the user, hard**: "スプライトパターンそんなに使ってるか?
  自機とボスだけだぞ もしそうなら動的に書き換えしてくれ 反転パターンは
  動的に書き換え BGでは今のようにかなりの速度じゃないと動きがガタガタ
  で速すぎるんだよ スプライト必須 で、同時に4発は欲しい そのために攻
  撃中はボスをBGにしてんの まだ他にもスプライト使うが それは1パターン
  更にファンネルもやるんで". Two separate corrections in one message:
  1. **My pattern-budget analysis was incomplete.** I had only counted
     BigZum's own block as dynamically reusable (matching the boss's own
     body reusing it). The user's point: once the boss fight is active,
     ZacoII/Zum/Flyer never spawn again either (same "オールフリー"
     principle) - their ENTIRE pattern-code footprint is free too, not
     just BigZum's. There was never really a budget problem.
  2. **BG movement itself is architecturally wrong for this feature
     regardless of budget** - BG's column-granular (8px/frame) movement
     is too choppy unless moving very fast; a real hw sprite (true
     per-pixel movement) is mandatory for a homing missile that has to
     look smooth while tracking. "スプライト必須".
  Also revealed a piece of the user's own original design intent I
  hadn't been told directly: **converting the boss's own body to BG
  during the attack pose was partly deliberate specifically to free its
  own 16 hw sprite slots (10-25) for this missile volley** - "そのため
  に攻撃中はボスをBGにしてんの". Not something I inferred; the user's
  own stated reasoning.
- **Redesigned as a real 4-instance hw-sprite pool** (`HORMING_POOL`,
  `F2C2h`, 4 slots x5 bytes: ACT/X/Y/FACING/PHASE - real pixel X/Y this
  time, not COL/ROW cells, since the whole point of switching to a hw
  sprite was smooth movement). Reuses **Flyer's own whole pattern block**
  (`PAT_HORMING_SL/DL/DOWN/DR/SR EQU PAT_FLYER+0/4/8/12/16` - Flyer's own
  32 codes, 220-251) instead of a fresh permanent allocation, loaded
  dynamically **once, at boss-spawn time** (`UPDATE_BOSS_ALL`'s own spawn
  branch, alongside the existing `LOAD_SASAPI_PATTERNS` call for the
  boss's own body) - not at `INIT`, same "load once when the reused
  owner is guaranteed gone for good" idiom `LOAD_SASAPI_PATTERNS` already
  established. `horming_gen.py` was rewritten to emit 16x16-padded hw
  sprite pattern data (8x8 art embedded top-left of an otherwise-blank
  16x16 canvas, same convention as `bullet_gen.py`'s own `bullet_u_
  sprite()`) instead of raw BG tiles. Uses hw sprite slots
  `HORMING_SPR_BASE_SLOT`(10)`..+3` - the boss's own body's slots10-13,
  guaranteed free for a missile's own full screen-crossing (which takes
  far less time than a pose lasts, so the boss's own body - which would
  otherwise hold those slots - is always still hidden/BG-drawn whenever
  a missile is alive).
- **`FIRE_HORMING` now fires a full volley of all 4 slots at once** -
  "同時に4発". Spawn X is the same for all 4 (`HORMING_SPAWN_X`, 232);
  spawn Y is staggered by 8px per slot index (**inferred, not explicitly
  specified by the user** - purely so the 4 missiles are visually
  distinct instead of perfectly overlapping forever, since identical
  start position+phase would otherwise produce identical facing/movement
  every frame - flag for correction if this isn't what's wanted). Each
  slot independently drops its own fire attempt if still active from a
  previous pose (same "screen limit, drop the shot" idiom as before, now
  per-slot instead of once).
- **The 5-way discretized facing/homing algorithm itself is UNCHANGED**
  from the previous round - same bucket thresholds
  (`|dx|<=TANK_WIDTH`(32)->Down, `32<|dx|<64`->diagonal, `|dx|>=64`->
  side, direction by which side of the tank the missile is on), same
  fixed per-axis step per facing, same two-phase flight (straight until
  `HORMING_CENTER_X`(128), then continuous homing recomputed every
  frame) - only re-expressed against real pixel X instead of `COL*8`
  (actually simpler now, no `*8`/`/8` conversion needed anywhere).
  Collision still uses `APPLY_TANK_DAMAGE` unchanged.
- **A real bug this round's own tests caught before shipping**:
  `UPDATE_HORMING_ALL`'s staging loop walks `HORMING_SPRITE_ATTRS` via
  `HL`, but both `CALL UPDATE_ONE_HORMING` (which can call `APPLY_TANK_
  DAMAGE`/`SOUND_ZUM_DEFLECT` on a hit) and `CALL RESOLVE_HORMING_
  PATTERN_IX` (its own table lookup) use `HL` as scratch internally -
  without saving/restoring `HL` around both calls, the attrs buffer got
  written to whatever address either of them left `HL` pointing at
  instead, corrupting the sprite attribute staging for every slot after
  the first. Fixed with `PUSH HL`/`POP HL` around both calls. Caught by
  `tests/horming_test.py`'s own SAT-matches-pool checks, not by the
  end-to-end `MAINLOOP` sweep (the corruption didn't happen to break
  that sweep's own coarser "did it move" check) - worth remembering:
  **the fine-grained per-field checks catch bugs the coarse end-to-end
  sweep alone would miss**.
- Every far conditional branch inside the new, long `UPDATE_ONE_HORMING`
  uses `JP`, not `JR`, from the start (not as a post-hoc fix) - a
  routine of this shape/length already hit "JR/DJNZ out of range" once
  this session (`UPDATE_HORMING`'s own `UH_DEACTIVATE` branches, prior
  round) and would very likely hit it again here.
- Verified: `tests/horming_test.py` fully rewritten for the new pool/hw-
  sprite API (75 checks - volley-of-4 fire with per-slot spawn/stagger
  verification, partial-refill-only-refills-inactive-slots, phase0
  straight movement, the phase transition timing, all 6 bucket-boundary
  cases on both sides (12 checks) via the new `RESOLVE_HORMING_FACING_
  IX`, all 5 facings' own movement deltas via `UPDATE_ONE_HORMING`, both
  edge-underflow/overflow guards (same "call the internal step label
  directly" approach as before, still needed for the same reason), a
  real hit decrementing `TANK_LIFE`/arming the flash/deactivating the
  missile, a clean miss registering nothing, `UPDATE_HORMING_ALL`'s own
  SAT staging (Y/X/pattern/color per slot, hiding a deactivated slot at
  Y=209), `RESOLVE_HORMING_PATTERN_IX`'s own pattern-code lookup for all
  5 facings, and a real end-to-end `MAINLOOP` sweep confirming a real
  volley of 4 actually fires during the pose and moves frame to frame)
  all pass. Full suite: 304/307 pass, same 3 known GAME_TICK=840-boot-
  effect failures - no new regressions (`flyer_terrain_test.py` in
  particular still passes clean, confirming Flyer's own ordinary,
  pre-boss appearance is genuinely unaffected by the dynamic pattern
  reuse). Also rendered real frames: the volley of 4 missiles is clearly
  visible near the boss's own body at pose-entry (4 small gray blobs,
  vertically staggered) and mid-flight 60 frames later (moved smoothly
  left as a group, still phase0/facing-SL at that point) - visually
  confirms both the "4 simultaneous" requirement and smooth per-pixel hw
  sprite movement (not the choppy column-snapped motion BG drawing would
  have produced).
- **Not yet implemented** (explicitly flagged by the user as still to
  come): "まだ他にもスプライト使うが それは1パターン" (one more small
  hw sprite need) and "更にファンネルもやるんで" (a "funnel"-style
  attack, likely a swarm/drone type). Both reasons this round kept usage
  economical - only 20 of Flyer's own 32 reused codes are used (12
  spare), and only 4 of the boss's own freed 16 slots (10-13; 14-25
  spare).

## Homing missile round 3: full flight-arc rewrite - 3-state (rise/wander/homing) + intermittent fire

- The 4-simultaneous, straight-then-homing flight from round 2 was
  replaced by a much more detailed spec: "まず発射方法 ボスに被らない
  位置の右上 今の発射位置の16px上あたり 次に最初は左斜上に32px移動
  その後はXは左端64pxから右72pxの範囲でランダムに水平移動 その後ホー
  ミング 弾は4発同時発射ではなく間欠で4発発射 で方向を変える時は45度
  まで 自機のY位置以上で一致したら水平に自機へホーミング".
- **Spawn**: `HORMING_SPAWN_Y` raised from 64 to 48 (16px higher) so it
  clears the boss's own 64x64 box's own top edge (Y56) instead of
  spawning inside the hand art - "ボスに被らない位置の右上 今の発射位
  置の16px上あたり". `HORMING_SPAWN_X` unchanged (232).
- **3-state per-slot flight** (`HORMING_POOL`'s own `+4` field, was
  `PHASE` 0/1, now `STATE` 0/1/2), replacing the old straight-then-
  homing 2-phase flight entirely:
  - **state0 (rise)**: "最初は左斜上に32px移動" - a fixed diagonal, X
    and Y both decrease `HORMING_SPEED`/frame, tracked via a per-slot
    countdown (`RISE_REMAIN`, new `+5` field, starts at
    `HORMING_RISE_DIST`=32) so the total distance is always exactly 32px
    regardless of `HORMING_SPEED`. Cosmetic facing forced SL throughout
    - **there is no true "upward" sprite among the 5 uploaded facings**
      (they only span the lower 180 degrees), so SL (the closest
      available) is shown while the missile is actually moving up-left -
      an unavoidable art-vs-motion mismatch, not a bug, flagged here in
      case a 6th "upward" facing ever gets added.
  - **state1 (wander)**: "Xは左端64pxから右72pxの範囲でランダムに水平
    移動" - X takes a random `HORMING_SPEED` step left or right each
    frame (`GAME_RNG` coin flip, same idiom as `UOZ_PAUSE_ROLL`), forced
    back inward whenever it's at/past either edge of
    `[HORMING_WANDER_MIN_X(64),HORMING_WANDER_MAX_X(184)]` instead of
    rolling. **This window was read as an ABSOLUTE screen-relative range
    (64px from the screen's own left edge, 72px from its own right edge
    = 256-72=184), not relative to the missile's own spawn/rise-end X -
    INFERRED, flag for correction.** The alternative reading (relative
    to where the rise ends, ~X200 for this boss's own spawn X) would put
    the right bound past X255, which can't be right, so the absolute
    reading was chosen instead. Y keeps descending
    `HORMING_SPEED`/frame throughout this state - **not stated
    explicitly by the user, but required for the state2 trigger below to
    ever fire - inferred.** The instant missile_Y reaches/passes
    `TANK_Y_CUR` ("自機のY位置以上で一致したら"), advances to state2.
  - **state2 (homing)**: "水平に自機へホーミング" - purely horizontal
    now: Y is completely frozen, X steps `HORMING_SPEED`/frame toward
    `TANK_X` (holds position once aligned, rather than oscillating past
    it).
  - The old X-distance-bucket facing classifier (`RESOLVE_HORMING_
    FACING_IX`, `TANK_WIDTH`/`HORMING_SIDE_DIST`) is gone entirely -
    each state now computes its own movement directly (hardcoded per
    state, not derived from a shared classifier), since the new spec's
    3 states each have their own distinct movement rule with nothing
    left in common with the old single continuous tracking model.
- **"で方向を変える時は45度まで"**: the sprite's own shown facing is
  now a SEPARATE cosmetic value (`EASE_HORMING_FACING_IX`, a small leaf
  routine) that eases toward each state's own "desired" facing by at
  most 1 of the 5 discrete 45-degree steps per frame - never snaps
  directly across more than one step, even when the desired facing is
  further away (e.g. DL straight to SR would need 3 frames now, not 1).
  Deliberately DECOUPLED from the actual movement math (which stays
  hardcoded per state) specifically so the state1->state2 handoff's own
  facing catch-up (still easing toward SL/SR for a frame or two after
  the transition) can never reintroduce a stray vertical step during
  state2, which is supposed to be Y-frozen.
- **"弾は4発同時発射ではなく間欠で4発発射"**: no longer one `FIRE_
  HORMING` call launching all 4 at pose-entry. `ARM_HORMING_VOLLEY`
  (called at pose-entry, replacing the old call there) just resets a
  launch counter/timer; `UPDATE_HORMING_VOLLEY` (called every frame from
  `UBA_POSE`, alongside `DRAW_SASAPI_HAND`) ticks the timer down and
  fires one more missile via `FIRE_ONE_HORMING` (spawns into the first
  inactive pool slot) every `HORMING_VOLLEY_INTERVAL`(24) raw frames,
  until all 4 are out. **The interval's own exact magnitude (24 raw
  frames) was not specified by the user - inferred/tunable** - chosen so
  all 4 launches finish within the first third of the pose's own 256
  raw frames (`BOSS_POSE_TICKS`(32)*8), leaving the rest of the pose for
  them to actually fly.
- RAM: `HORMING_SLOT_SIZE` grew from 5 to 6 bytes/slot (added
  `STATE`/`RISE_REMAIN`, replacing `PHASE`), so `HORMING_POOL` grew to
  24 bytes and everything after it shifted (`HORMING_SPRITE_ATTRS` now
  at `F2DAh`, plus two new bytes `HORMING_VOLLEY_COUNT`/`HORMING_VOLLEY_
  TIMER` at `F2EAh`/`F2EBh`) - `UPDATE_HORMING_ALL`'s own field reads
  (X/Y/FACING at `+1`/`+2`/`+3`) didn't need to change since those 3
  fields kept their same offsets; only the "skip a whole slot" `INC IX`
  chains needed updating from 5 to 6 repeats.
- Verified: `tests/horming_test.py` rewritten again for the 3-state/
  intermittent-fire API (74 checks - `FIRE_ONE_HORMING`'s own single-
  slot spawn and pool-full drop, `ARM_HORMING_VOLLEY`/`UPDATE_HORMING_
  VOLLEY`'s own intermittent timing (confirmed only 1 launches per tick,
  never all 4 at once, exactly `HORMING_VOLLEY_INTERVAL` frames apart,
  exactly 4 total), state0's own exact 32px diagonal and state1
  transition, state1's own window-forcing at both edges and the Y>=tank_Y
  trigger, the 45-degree-max-turn rule both standalone
  (`EASE_HORMING_FACING_IX`) and at the state1->state2 handoff
  specifically, state2's own Y-frozen horizontal-only homing and hold-
  on-alignment, tank collision, `UPDATE_HORMING_ALL`'s own SAT staging,
  and a real end-to-end `MAINLOOP` sweep confirming exactly 4 missiles
  launch across one real pose, spread apart in time, reaching both
  state1 and state2) all pass. Full suite: 303/306 pass, same 3 known
  GAME_TICK=840-boot-effect failures, no new regressions. Rendered real
  frames across the pose: at pose-entry+20 frames a single missile is
  visible above-left of the boss mid-rise, clear of the hand art; at
  +100 frames two missiles are visible mid-wander at different heights
  (staggered by the intermittent launch timing) while a third is already
  down near the tank in state2; by +250 frames the tank's own life bar
  has dropped from 6 to 2 segments (the stationary test tank took all 4
  hits, since this sweep never moves it - a real player dodging would
  avoid most/all of them) - end-to-end confirms the full rise-wander-
  home-hit arc actually works, not just the individual state
  transitions in isolation.
- Two bug fixes caught by this round's own tests before shipping (both
  in `UOH_WANDER`'s window-forcing comparison): the boundary checks
  originally used `CP HORMING_WANDER_MIN_X`/`CP HORMING_WANDER_MAX_X+1`,
  which only forced correction 1px PAST either edge instead of AT it -
  a missile sitting exactly on `HORMING_WANDER_MAX_X` could still roll
  right via `GAME_RNG` and briefly step outside the window before being
  caught the following frame. Fixed to `CP HORMING_WANDER_MIN_X+1`/`CP
  HORMING_WANDER_MAX_X` so the force triggers deterministically at the
  boundary itself, not past it.

## Homing missile round 4: two real structural bugs fixed, plus a design correction and a new feature

- The user reported a real, live bug and pushed back hard on two claims
  from round 3's own documentation: "まずホーミングのスプライトが非表
  示待機になってるからだろうが ボス上部が常に表示欠けしている で、
  Flyerを流用だの言ってたが ホーミングスプライトは16x16だぞ 何を流用
  したんだ 次に射出後のランダム水平移動が固定されてる お前は1度もま
  ともにランダム扱えてないな 斜めに打ち出したら指定した範囲のランダム
  X位置まで水平移動後ホーミング で、打ち出しの上向きキャラは要らない
  そんな事は指定していない SLのままでいい もしそうするなら絵を用意し
  てる".
- **Confirmed root cause of the boss's own top-quadrant corruption**:
  round 2/3's own reasoning ("boss's own hw sprite slots10-25 are free
  for the entire time any missile can exist") was wrong the moment
  round 3 gave missiles a flight lasting far longer than the pose itself
  - a missile is routinely still alive/rendering AFTER the boss has
  already resumed patrolling as a real hw sprite in slots10-25 again.
  `UPDATE_HORMING_ALL` runs every `MAINLOOP` frame unconditionally and
  always ends with a flush (even an all-hidden pool writes `Y=209` to
  all 4 slots); since it's called AFTER `UPDATE_BOSS_ALL`, this made the
  missile pool's own flush the LAST write to slots10-13 every frame,
  permanently stomping the boss's own first 4 quadrants right after
  `DRAW_BOSS`/`FLUSH_BOSS_SPRITES` drew them - exactly the ordering
  invariant `BOSS_SPR_BASE_SLOT`'s own PRE-EXISTING comment already
  documents ("safe as long as `UPDATE_BOSS_ALL` is called AFTER all 4 of
  their own per-frame flushes...so the boss's own real data is always
  the LAST write") being violated by a 5th, unaccounted-for writer.
  **Fixed by moving the missile pool entirely off the boss's own body
  range** - `HORMING_SPR_BASE_SLOT` 10->6, reusing `BULLET_U_SPR_BASE_
  SLOT`'s own slots7-9 (unconditionally hidden the INSTANT `BOSS_ACT!=0`
  - airtight, not a timing estimate, since U becomes BG-drawn during the
  boss fight) plus `ENEMY_SPR_BASE_SLOT`'s own last slot(6) - same
  already-trusted "spawning stopped well before boss-spawn" reasoning
  `BOSS_SPR_BASE_SLOT`/`PAT_SASAPI` already rely on for reusing Zum/
  BigZum/Flyer/Etank's own hw sprite slots. Also added a `BOSS_ACT=0`
  guard to `UPDATE_HORMING_ALL` itself (RET Z immediately) - without it,
  slots6-9 would be stomped by the missile system's own per-frame flush
  even BEFORE the boss exists, while ZacoII/BulletU still genuinely need
  them (a second instance of the exact same class of bug, this time
  against the PRE-boss game).
- **"何を流用したんだ" was a fair challenge - the round-2 explanation
  was misleading, though the underlying mechanism turned out to be
  sound**: Flyer is a real 32x32 sprite; `flyer_gen.py`'s own
  `quadrants_from_bits`/`block16_bytes` genuinely fill all 32 of its own
  pattern codes (16 per facing x2 facings) with real art - there was
  never any "spare padding" sitting alongside it the way round 2's
  wording implied. What's actually happening is a full TAKEOVER of
  Flyer's entire block, exactly like `PAT_SASAPI`'s own takeover of
  BigZum's block for the boss's own body - safe because Flyer (like
  ZacoII/Zum) never spawns again once the boss fight starts, on the same
  already-trusted `ENEMY_SPAWN_STOP_TICK`(950)-to-`BOSS_SPAWN_TICK`(999)
  timing buffer `BOSS_SPR_BASE_SLOT`/`PAT_SASAPI` already rely on.
  Verified empirically this round (not just reasoned about): a real
  `MAINLOOP` sweep confirms no `FLYER_POOL` slot is ever active at the
  exact frame the boss spawns.
- **The "random" wander was a real, confirmed bug, and likely not the
  first time**: every existing `GAME_RNG` consumer in this file
  (`UOZ_PAUSE_ROLL` included) reads `GAME_RNG`, immediately `INC`s-and-
  stores it back, then takes the low bit of what it just read. When
  several consumers - or, in round 3's per-frame-coin-flip wander,
  several missiles within the SAME frame - do that back to back, each
  one just sees "whatever the previous reader left, +1": the low bit
  toggles in a near-deterministic pattern rather than looking random at
  all. Given the user's own "1度もまともにランダム扱えてない" (not once
  properly handled), this pattern may have been silently degrading
  `UOZ_PAUSE_ROLL`'s own Zum behavior too, just never called out before
  the missile's own much more visible per-frame wander made it obvious.
- **Redesigned per round4's own new spec**: "斜めに打ち出したら指定し
  た範囲のランダムX位置まで水平移動後ホーミング" - state1 (wander) now
  picks ONE random target X via `PICK_HORMING_TARGET_X`, called exactly
  once at the state0->state1 transition (not every frame) - a pure READ
  of `GAME_RNG` (never mutates it), mixed via XOR with `TICK` (a
  separate free-running per-frame byte nothing else reads-and-mutates)
  and the slot's own current Y (decorrelates missiles launching close
  together, which the intermittent-fire timer makes common). Verified
  this actually varies (not stuck on one value) both in a standalone
  sweep and in a real `MAINLOOP` run.
  **A second real bug this fix's own testing caught**: an ODD `TARGET_X`
  can never be reached by a missile that only ever moves in `HORMING_
  SPEED`(2)-px, always-even-parity steps - a plain "step by speed, check
  exact equality" loop oscillates 1px short/over FOREVER, stuck in
  state1 permanently (visible in a rendered frame, not caught by the
  first pass of unit tests, none of which happened to exercise a
  genuinely random - and therefore possibly odd - target). Fixed by
  snapping exactly onto `TARGET_X` whenever the remaining distance is
  `HORMING_SPEED` or less, instead of always stepping by a fixed amount.
- **The pending question from round 3 (does "ホーミング" mean horizontal-
  only or full 2D tracking) is now resolved - and the follow-up revealed
  the horizontal-only version could barely ever hit a grounded tank at
  all**, since the missile spawns near the very top of the screen (Y~16)
  and horizontal-only movement never lets Y catch up to a tank down near
  the ground. Restored the ORIGINAL 5-way `SL/DL/Down/DR/SR` distance-
  bucket tracking (`RESOLVE_HORMING_FACING_IX`, deleted in round 3,
  brought back verbatim) as state2 - real 2D pursuit, moving in both X
  and Y each frame, until missile_Y reaches a THRESHOLD, then hands off
  to state3 (locked horizontal, the old state2 body, renamed/unchanged).
  **The threshold itself isn't the tank's own exact Y**: "自機狙い水平
  移動の位置を8pxさげてくれ 水平打ちで撃ち落とせる高さ" - it's `TANK_
  Y_CUR+HORMING_HOMING_Y_OFFSET`(8), the tank's own horizontal-shot
  height, so the final horizontal approach happens at a height the
  player can actually shoot the missile down at (see below) rather than
  right in the tank's own face. **The comparison is `>=`, not exact
  match**: "以上の意味が違う...完全一致では飛んだ時にY位置が飛び越え
  てしまう場合があるからだ" - a `HORMING_SPEED`-px step can jump
  straight over one exact value, the same lesson `PICK_HORMING_TARGET_X`'s
  own parity bug already taught this round. Y is NOT re-snapped to the
  exact threshold when it fires - whatever overshoot that frame's own 2D
  step already produced is kept, by the same reasoning.
- **New feature: missiles can now be shot down by the tank's own
  bullets** - "今はミサイルに判定がないがショットで撃ち落とせるように".
  `CHECK_BULLET_VS_HORMING` (called from `MAINLOOP` right after `CHECK_
  BULLET_VS_BOSS`, same "IX=bullet, IY=pool, nested loop over 3 bullets
  x4 missiles" shape as `CHECK_BULLET_VS_ZUM`) treats the missile as an
  8x8 box (matches `UOH_COLLIDE`'s own sizing), no front/back
  distinction needed (unlike Zum - a missile has no "safe side"). Both
  bullet types (F and U) are BG-drawn cell-based during the boss fight
  (`DRAW_BULLET_CELL`'s own comment), so `ERASE_BULLET_CELL` always
  applies unconditionally here, unlike `CHECK_HIT_PAIR`'s own IX+1-gated
  version written for the pre-boss hw-sprite-U case. On a hit: erases
  the bullet's own cell, deactivates both the bullet and the missile,
  plays `SOUND_DESTROY`, awards `SCORE_PER_KILL` - same feedback as
  `CHECK_HIT_PAIR`'s own `CHP_DESTROY` path.
- **"打ち出しの上向きキャラは要らない そんな事は指定していない SLのま
  までいい"** - confirms round3's own inferred choice (show SL, the
  closest available facing, cosmetically during the rise, since none of
  the 5 uploaded sprites face upward) was correct as-is. No change
  needed; the "flag for correction" hedge in the code comments was
  removed since it's now confirmed, not speculative.
- Verified: `tests/horming_test.py` extended again (155 checks - the
  restored `RESOLVE_HORMING_FACING_IX` bucket boundaries, state2's own
  real 2D movement per facing, the Y-threshold trigger (both "not yet"
  and "exactly at" cases, confirming no re-snap), state3 unchanged
  behavior, `CHECK_BULLET_VS_HORMING`'s own hit/miss/inactive-bullet
  cases, a real `MAINLOOP` regression check that the boss's own top
  quadrant is no longer hidden while patrolling, a real sweep confirming
  no `FLYER_POOL` slot is alive at boss-spawn, `PICK_HORMING_TARGET_X`'s
  own range/variance/no-mutation checks, the parity-snap fix, and a
  real end-to-end sweep now extended long enough to observe the FULL
  arc - state1 through state3 - and confirm `TANK_LIFE` actually
  decreases, not just that the right states got visited) all pass.
  Rendered real frames across a full pose: the boss's own body is fully
  intact (no missing quadrants) both mid-pose and after returning to
  patrol; a missile is clearly visible descending in 2D toward the tank
  while later-launched missiles are still high up mid-wander, staggered
  by the intermittent-fire timing; the tank's own hit-flash and life bar
  (6->4 across one pose in this stationary no-dodge test) confirm real
  hits landing via the restored 2D pursuit.

## Homing missile round 5: per-shot randomness actually fixed, forced initial turn, no more disappearing, 2x speed

- "表示欠けは直った" - round4's boss-corruption fix confirmed working.
  Everything else in this round is a follow-up correction: "で、X位置
  ランダムはホーミング1発毎な 今は4発同じ位置になってるように見える
  更にホーミング開始直後は左斜下に1回だけ必ず移動 自機が右にいた場合
  に急激な曲がりを防ぐため で、自機狙いY位置マッチ水平移動後はホーミ
  ングせずそのまま水平移動固定で 仮に飛び越えた場合消えなくなるんで
  ミサイル速度2倍に".
- **The per-shot randomness fix from round4 had a real remaining flaw**:
  `PICK_HORMING_TARGET_X`'s own mixing included `(IX+2)`, the slot's
  current Y, intending to decorrelate missiles that launch close
  together - but every missile spawns at the identical `HORMING_SPAWN_Y`
  and runs the identical rise trajectory, so `(IX+2)` is the SAME value
  for every missile at the exact moment this runs (right when its own
  rise completes) - it contributed nothing to the mix, which is exactly
  why the user saw all 4 missiles converge to the same wander position.
  Fixed by mixing in the low byte of `IX` itself (this slot's own RAM
  address) instead - guaranteed different for every concurrently-active
  slot (`HORMING_SLOT_SIZE` apart), unlike Y which converges by
  construction. Confirmed via a rendered frame: 3 concurrent missiles'
  own `TARGET_X` now read as genuinely distinct values (96/146/179 in
  one real run) instead of clustering on one.
- **"ホーミング開始直後は左斜下に1回だけ必ず移動 自機が右にいた場合に
  急激な曲がりを防ぐため"**: the wander->state2 transition
  (`UOH_W_ARRIVED`) now performs one unconditional, forced DL (down-
  left) step - X and Y both move by `HORMING_SPEED`, and the shown
  facing snaps directly to DL(1) rather than easing toward it - before
  any real `RESOLVE_HORMING_FACING_IX`-driven tracking ever runs. This
  absorbs whatever facing swing the tank's own position would otherwise
  demand on the very first pursuit frame (e.g. a sudden DL->SR flip if
  the tank happens to be far to the right right as homing begins).
  Every later frame's own real tracking pass then eases from this DL
  baseline the same as any other transition.
- **"自機狙いY位置マッチ水平移動後はホーミングせずそのまま水平移動固
  定で 仮に飛び越えた場合消えなくなるんで"**: this was a real latent
  bug, not just reinforcement of already-correct behavior. State2's own
  Y-moving branches (`UOH_H2_STEP_DOWN`/`DL`/`DR`) still carried a
  `HORMING_MAXY`(184) bail-out from round3's own design (back when
  state1 used to descend using this same bound); if `TANK_Y_CUR+
  HORMING_HOMING_Y_OFFSET` (the state2->state3 trigger threshold) ever
  sat past 184, that old bail-out would fire FIRST and deactivate
  (vanish) the missile before it ever got a chance to level off into
  state3. Fixed by removing the `HORMING_MAXY` check from state2
  entirely (it's now a fully unused constant, deleted) - `TANK_Y_CUR` is
  always a sane on-screen value and `UOH_H2_TRIGGER` already fires the
  very same frame Y reaches the threshold, so nothing else needs to
  guard Y in state2. `HORMING_MAXX` (X off-screen) is unrelated and
  unaffected.
- **"ミサイル速度2倍に"**: `HORMING_SPEED` 2->4 - the only entity in
  this file with a doubled speed (`BOSS_SPEED`/`FLYER_SPEED`/
  `ETANK_SPEED` all stay at their own "速度は2"). Affects every phase
  uniformly (rise, wander, 2D pursuit, locked horizontal) since they all
  share the one constant - `HORMING_RISE_DIST`'s own per-slot countdown
  means the total rise distance stays exactly 32px regardless, just
  covered in half as many frames now.
- Verified: `tests/horming_test.py` updated for all of the above (157
  checks, all passing) - the arrival-frame assertions now expect the
  forced DL step's own X/Y/facing changes instead of "holds position";
  a new check confirms state2 no longer deactivates from a Down step
  deep near the bottom of the screen (the disappearing-missile fix).
  Full suite: 386/389 pass, same 3 known GAME_TICK=840-boot-effect
  failures, no new regressions. Rendered real frames confirming: 3
  concurrently-wandering missiles now show 3 distinct `TARGET_X` values,
  and the doubled speed visibly covers far more ground per rendered
  interval than before (`TANK_LIFE` dropping 6->4->2 within the same
  ~150-frame window this round's own render script uses, versus 6->4
  over a similar window last round).

## Homing missile round 6: speed tuned to 3, surfacing (and fixing) a rise-distance bug

- "速度3に" - `HORMING_SPEED` 4->3 (round5 had doubled it 2->4; this
  round dials it back down by one).
- **A real bug this exact change surfaced**: `HORMING_RISE_DIST`(32)
  had always been evenly divisible by every `HORMING_SPEED` value used
  so far (2, then 4) - 3 is the first value that doesn't divide evenly.
  `UOH_RISE`'s own termination check (`SUB HORMING_SPEED` then test for
  an exact 0) relied on that evenness: with speed 3, `RISE_REMAIN` steps
  32,29,26,...,5,2, then the next `SUB 3` underflows to 255 (a byte
  wrap, not 0) - `RISE_REMAIN` never reads back as exactly 0, so the
  missile never left state0 at all, stuck rising far past its own
  intended 32px. Fixed generally (works for ANY `HORMING_SPEED`, even
  a value nobody's tried yet): once remaining distance drops under a
  full `HORMING_SPEED`, the final step moves exactly what's left instead
  of a fixed amount - same "snap the remainder" idea `UOH_WANDER`'s own
  `TARGET_X` arrival logic already uses. Introduced (and caught by the
  test suite before shipping) a second bug in that same fix: the Y
  component of the partial final step used `ADD` instead of `SUB`,
  moving Y the wrong way (down instead of up) on the rise's own last
  partial frame - fixed to `SUB`, matching the full-step branch.
- No other code changes - the snap-when-close logic in `UOH_WANDER` and
  the `>=`-not-exact-match trigger in `UOH_H2_TRIGGER` were both already
  written to handle an arbitrary `HORMING_SPEED`/parity from round4/5's
  own fixes, so speed3 needed nothing further there.
- Verified: `tests/horming_test.py`'s own rise-completion test was
  itself relying on `HORMING_RISE_DIST // HORMING_SPEED` (floor
  division) to know how many frames to drive - correct only when it
  divides evenly. Updated to ceiling division so it drives enough frames
  to reach the final partial step regardless of `HORMING_SPEED`. 157
  checks, all pass. Full suite: 386/389, same 3 known GAME_TICK=840-
  boot-effect failures, no new regressions. Rendered a real frame
  showing correct full-arc progression at the new speed (4 missiles'
  own `TARGET_X` still genuinely distinct - 170/129/73/98 in one run -
  and `TANK_LIFE` dropping 6->5->3 across the same render window).

## Round 7: shorter attack pose, homing missile recolored light blue

- "ポーズ停止時間を少し短く ホーミング弾の色をライトブルーに変更".
  Two small, independent tweaks, both simple constant changes.
- `BOSS_POSE_TICKS` 32->24 (a ~25% cut - "少し" didn't specify an exact
  amount, flag for correction if a different magnitude was wanted).
  Confirmed via a real render: the pose now lasts ~191 raw frames
  (24*8) instead of ~256 (32*8). No knock-on effects - the intermittent-
  fire volley (4 shots, `HORMING_VOLLEY_INTERVAL`(24) raw frames apart,
  ~72 raw frames to finish launching) still comfortably fits inside the
  shortened pose.
- `HORMING_COLOR` 14(gray, matching the uploaded JSON sprites' own
  header)->5(light blue) - same palette index this file already uses
  elsewhere for "light blue" (`NIGHT_COLOR`, `CLOUD_GROUP0_COLOR`). A hw
  sprite's own color is a free per-instance SAT byte (no group/
  background constraint the way BG tiles have), so this doesn't touch
  the uploaded art itself, just how it's tinted on screen. Confirmed via
  a rendered frame.
- Verified: `tests/horming_test.py` (157 checks) and `tests/boss_pose_
  test.py` (27 checks, all parametric on `BOSS_POSE_TICKS`/`HORMING_
  COLOR` - not hardcoded, so no test edits were needed) both pass. Full
  suite: 386/389, same 3 known GAME_TICK=840-boot-effect failures, no
  new regressions.

## Round 8: Thunder (BG-drawn lightning column during patrol)

- "サンダーの実装 ホーミング攻撃後左に移動中に添付のキャラを画面2行目
  から下まで移動しながら埋める 埋め終わったら上から消す 発射位置とタ
  イミングはボスの右のX位置でボスが16px移動したら発射 そのまま左まで
  行き反転後はボスの左に発射 BGで描画" - a new attack, drawn straight
  into the name table (not a hw sprite), fired during the boss's own
  ordinary patrol movement rather than during a pose.
- New art pipeline: `sprites/Thunder_16x16.json` -> `thunder_gen.py`
  (same `tiles_row_major` shape as `sasapi_hand_gen.py`, just a 2x2 grid
  instead of 8x8) -> `THUNDER_TILES`, wired into `build_test.py`'s own
  `assemble()`. 4 new BG pattern codes, `THUNDER_CODE_BASE`=216 (group27
  - the next free BG group after the hand art's own groups19-26; group31
  is SkySand's own, so 27-30 were the only remaining free block).
  `THUNDER_COLORBYTE`=071h (fg7/cyan, bg1/black, matching the uploaded
  JSON's own header). Loaded once at `INIT`, same permanent-allocation
  idiom as `SASAPI_HAND_TILES`/`SASAPI_HAND_COLOR8`.
- Single-instance state machine (`THUNDER_ACT`/`THUNDER_COL`/
  `THUNDER_ROW`/`THUNDER_TIMER`, F2F0h-F2F3h) - only ever one column
  active at a time, one per boss movement leg. `FIRE_THUNDER` arms a
  fresh grow cycle at a given column; `UPDATE_THUNDER` (called every
  `MAINLOOP` frame) advances it `THUNDER_STEP_INTERVAL`(4, not specified
  by the user - inferred/tunable) raw frames at a time: growing draws a
  new 2x2 (16x16) block every step from `THUNDER_TOP_ROW` downward
  WITHOUT erasing previous ones (accumulates - "埋める"); once fully
  grown it flips to shrinking, which erases from `THUNDER_TOP_ROW` back
  down in the same direction ("埋め終わったら上から消す").
- **`THUNDER_TOP_ROW`** = `NIGHT_START_ROW`(1) - "画面2行目から" was read
  as the same row `NIGHT_START_ROW` already anchors to (the row right
  below the score/HUD row, the natural "2行目" in 1-indexed counting) -
  INFERRED, flag if a literal different row was meant.
- **`THUNDER_BOTTOM_ROW`** = 17, NOT the screen's near-bottom - a real
  constraint, not a cosmetic rounding choice: Thunder's own erase reuses
  `ERASE_BULLET_CELL` (the same background-aware single-cell restore
  bullets already use, avoiding a duplicate branch tree), and that
  routine itself gives up with no write at all once row>=
  `BULLET_ROCK_ROW_MIN`+4(20) - real ground/rock terrain with no generic
  BG restore path, the same boundary bullets themselves respect flying
  through there. So the column only reaches row18 out of the screen's 24
  rows (0-23); rows19-23 are deliberately left uncovered rather than
  risk drawing Thunder tiles there that could never be cleaned back up.
  **If the user wants Thunder to reach further down, that needs a new
  restore path for that band - flag this explicitly, don't just raise
  the constant.**
- Firing/timing: `CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT`, called from
  `UBA_STEP_LEFT`/`UBA_STEP_RIGHT` after `BOSS_X` updates each frame.
  Gated by `THUNDER_PENDING` (armed once per leg) and fires once the
  boss has moved `THUNDER_TRIGGER_DX`(16, `>=` not exact-match) px into
  the leg, at the boss's own CURRENT edge X at that instant - right edge
  (`BOSS_X+64`) on the leftward leg, left edge (`BOSS_X`) on the
  rightward leg - converted to a BG column via `SRL A`x3 (`/8`).
  `THUNDER_ELIGIBLE` (0 until the first attack pose ends, then
  permanently 1) gates Thunder off entirely during the boss's very
  first pre-pose patrol (spawn -> left -> reversal -> right -> first
  pose) - "ホーミング攻撃後" means after an attack, not from the very
  start. `THUNDER_LEG_START_X` is captured at `UBAP_END` (leftward leg,
  = `BOSS_SPAWNX`) and at the left-edge reversal in `UBA_MOVE_LEFT`
  (rightward leg, = 0).
- Verified: `tests/thunder_test.py` (new, 133 checks) - `FIRE_THUNDER`/
  `UPDATE_THUNDER` state transitions, `DRAW_THUNDER_BLOCK`/
  `ERASE_THUNDER_BLOCK` unit-level cell checks, a full grow cycle
  confirming blocks ACCUMULATE (earlier ones stay drawn as later ones
  appear) rather than draw-and-immediately-erase, a full shrink cycle
  confirming top-down erase order and zero leftover residue,
  `CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT` threshold/column-calc checks,
  and a real `MAINLOOP` sweep confirming Thunder stays completely silent
  through the pre-first-pose legs, then fires exactly once per leg after
  the first pose (leftward at the right edge, rightward at the left
  edge) at the correct column each time. Also confirmed visually via 4
  rendered frames (mid-grow, fully-grown/shrink-start, mid-shrink, and
  the 2nd fire on the rightward leg at the left edge) - see chat.
  Full regression suite: 519/522 passing - same 3 known
  `GAME_TICK=840`-boot-effect failures (`boss_test.py`,
  `etank_gametick_gate_test.py`, `night_effect_test.py`), no new
  regressions.
- `mini_z80asm.py`'s real `JR`/`DJNZ` range check bit again: several
  pre-existing `JR UBA_DRAW`/`JR Z,UBA_DRAW` jumps inside
  `UPDATE_BOSS_ALL` fell out of 8-bit signed-offset range once the new
  Thunder wiring code was inserted between them and their own target -
  converted to `JP` (established fix, same as prior rounds).

## Round 9: Thunder tuning - extend 1 cell, remove the step wait, fire every 32px

- "サンダーの表示開始位置はOk 終了位置はあと１セル分長く 表示ウェイト
  不要 で、端だけではなくボスが横に32px移動毎に発射" - 3 corrections to
  Round8's Thunder.
- **"終了位置はあと1セル分長く"**: added `THUNDER_EXTRA_ROW`
  (=`THUNDER_BOTTOM_ROW`+`THUNDER_ROW_STEP`=19) as one final single-row
  step past the last full 2x2 block - drawn/erased with just the
  bottom-half tiles (`DRAW_THUNDER_HALF`/`ERASE_THUNDER_HALF`, new)
  since there's no more Thunder art for a 2nd row. Row19 is still <20
  so `ERASE_BULLET_CELL` can restore it (falls into the same
  `TERRAIN_BLANK_CODE` branch as rows17-18, not plain sky - confirmed
  by a test failure that assumed sky and had to be corrected). Row20 is
  still the hard limit (`ERASE_BULLET_CELL`'s own `EBC_SKIP`, no
  restore path at all) - the column now covers rows1-19, one row short
  of that limit, not the literal screen bottom.
- **"表示ウェイト不要"**: `THUNDER_STEP_INTERVAL` 4->0. `UPDATE_THUNDER`
  reads this back into its own timer after every step, so 0 makes each
  call perform exactly one step - no restructuring needed, just the
  constant. Simplified `tests/thunder_test.py`'s own grow/shrink driving
  loop at the same time (no longer needs to poll for "did a step
  happen", since it's now deterministic 1-call-1-step).
- **"端だけではなくボスが横に32px移動毎に発射"**: the biggest change -
  Thunder used to fire once near the start of each leg then go silent
  for the rest of it; now it keeps re-arming and re-firing every
  `THUNDER_TRIGGER_DX`(16->32) px for the WHOLE leg.
  `CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT` no longer clear `THUNDER_PENDING`
  after firing (it now means "this leg is armed at all", not "hasn't
  fired yet"); instead they re-arm `THUNDER_LEG_START_X` to the boss's
  own current X right after each fire, and gate on `THUNDER_ACT==0`
  (single instance - a trigger that lands while the previous column is
  still animating is skipped that frame, not lost: the distance keeps
  accumulating against the old baseline, and it fires the instant the
  previous one finishes, at whatever the boss's CURRENT edge X is then).
  **Real observed cadence is ~40px, not exactly 32px** - a full grow
  (10 steps)+shrink(10 steps) cycle now takes 20 raw frames even with
  no wait, and at `BOSS_SPEED`(2px/frame) that's 40px of travel, longer
  than the 32px/16-frame trigger distance - so in practice each fire
  waits for the previous one to finish, landing ~40px apart rather than
  a strict 32px cadence. This is an inherent consequence of the single-
  instance constraint (never 2 columns on screen at once), not a bug -
  flagged for the user in case a faster/simultaneous look was wanted.
- Verified: `tests/thunder_test.py` rewritten for the new behavior (172
  checks) - constant sanity checks, `DRAW_THUNDER_HALF`/
  `ERASE_THUNDER_HALF` unit checks, a full grow/shrink cycle now
  including the extra half-row step, the busy-gate/re-arm/repeat-firing
  behavior of both `CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT` (including the
  "fires again immediately once idle, at the current edge, not the
  stale 32px mark" case), and a real `MAINLOOP` sweep confirming
  multiple correctly-positioned fires per leg (not just one near the
  edge) with a hard "consecutive same-leg fires are >=32px apart"
  invariant check, still silent through the pre-first-pose legs. Also
  confirmed visually via 2 new rendered frames (the column reaching the
  new row19 extra cell, and a 2nd fire mid-leg at a new leftward
  position). Full regression suite: 558/561 passing - same 3 known
  `GAME_TICK=840`-boot-effect failures (`boss_test.py`,
  `etank_gametick_gate_test.py`, `night_effect_test.py`), no new
  regressions.

## Round 10: Thunder - a real pool, reaches the actual terrain, spawns ThunderS, left-edge pause

- User feedback (verbatim, angry - a real regression against explicit
  intent, not a preference tweak): "左端は2Tick停止してから反転発射に
  反転した時にボス自身に当たってしまう で、いつからサンダーは1本しか
  出せない仕様に? そんな指示はしてねえぞ BGを使ってるのは表示制限が
  ないからだろが 勝手に仕様を決めんな お前がゲーム作ってんのか? あと
  終了位置は地形までに変更 地形に到達したら添付のキャラを地上の上に
  左右に発射 地形に沿う形で移動し画面外に出たら消せ Zumなんかと同じ
  だ" - then, after seeing the plan, corrected the ThunderS part again:
  "やっぱThunderSは2セル分でいいわ サンダーが着地したら左右同時に2セ
  ル描いて消せばおｋ 地形に沿うのは無しで" (no moving hw sprite after
  all - just 2 more static BG cells).
- **Thunder is now a real 4-instance pool** (`THUNDER_SLOT_SIZE`=4
  bytes/slot x`THUNDER_SLOT_COUNT`=4, `THUNDER_POOL`) - Round8/9's own
  single-instance design (with a busy-gate in the trigger checks) was
  never asked for; BG has no hw-sprite-style slot budget, so there was
  no real reason to serialize columns. `ALLOC_THUNDER_SLOT` (renamed
  from `FIRE_THUNDER`) finds the first inactive slot, same "pool full ->
  drop the attempt" idiom as `FIRE_ONE_HORMING`. The trigger checks no
  longer gate on any previous column finishing at all.
- **The column now grows all the way to the ACTUAL terrain surface**,
  not a fixed row: `GET_TERRAIN_ROW_FOR_COL` re-probes `IDCACHE_T0..T2`
  (the same per-column tier cache `UPDATE_TERRAIN_COLLISION`/`UOZ_
  TERRAIN_FOLLOW` already read for the tank/Zum) fresh every single grow
  step, since the terrain scrolls underneath a fixed screen column while
  a Thunder instance is alive. Growth now steps 1 row (not 2) at a time,
  stopping the instant the next row would reach the terrain row.
- **The ground/rock band (rows20-23) is no longer off-limits.** The key
  discovery: `MAINLOOP` already does an UNCONDITIONAL full 4-row LDIRVM
  redraw of rows20-23 (`TERRAIN_RENDER_ROW`x4 + LDIRVM) EVERY frame,
  before `UPDATE_THUNDER` runs - so anything Thunder draws there would
  get silently overwritten within 1 frame regardless of `ERASE_BULLET_
  CELL`'s own restore-path limits (which only ever mattered for rows
  0-19, never applied to 20-23 at all). Fix: re-assert (redraw) whatever
  of a slot's own currently-visible range falls in rows20-23 EVERY
  frame, racing that redraw - same "restore the known-correct value
  every frame" idiom as `DRAW_SASAPI_HAND`'s own per-frame healing.
  Simply STOPPING re-assertion (no explicit erase call) is then enough
  to hand a cell back to the terrain's own redraw once it's not wanted -
  no restore path is needed for that band at all, cutting the earlier
  rounds' entire `THUNDER_BOTTOM_ROW`/`THUNDER_EXTRA_ROW` machinery.
  Caught one real gap in this scheme by a test that simulates the
  terrain's own per-frame clobber precisely: the exact grow->shrink
  transition frame wasn't re-asserting the deepest main-bolt row (only
  the brand-new side cells), a real 1-frame flicker risk - fixed by
  re-drawing that row explicitly at the transition too.
- **ThunderS**: "地形に到達したら添付のキャラを地上の上に左右に発射"
  - originally planned as a moving, terrain-following hw sprite pool
    (mirroring Zum), but the user simplified this before it was built:
    "地形に沿うのは無しで...2セル分でいいわ...左右同時に2セル描いて
    消せばおｋ" - just 1 more static BG tile (`THUNDERS_CODE`, group27's
    5th code, `thunder_gen.py`'s own single-tile conversion of the
    uploaded `ThunderS_8x8.json`), drawn once at the bolt's own landing
    row, 1 column to either side, and erased together with the bolt's
    own deepest row once shrink reaches it. No hw sprite, no pool, no
    movement/despawn logic needed at all.
- **"反転した時にボス自身に当たってしまう" - two real fixes, not one**:
  (1) `CHECK_THUNDER_TRIGGER_RIGHT`'s own column math was a genuine bug
  - it used `BOSS_X` (the boss's own CURRENT left edge) directly as the
  bolt's own start column, putting the bolt's 2-column-wide art directly
  UNDER the boss's own body (both start at the same X); now uses
  `BOSS_X-16` so the bolt sits flush against the boss's own trailing
  left edge instead, entirely outside its box - mirrors how the
  leftward leg's own `BOSS_X+64` was already correct (trailing outside
  on the other side). (2) A new `BOSS_LEFT_PAUSE_TICKS`(2)-GAME_TICK
  pause at the left edge (`BOSS_PHASE`=2, a new sub-state, boss drawn
  stationary as an ordinary sprite) before the boss actually reverses -
  gives whatever Thunder column fired late in the leftward leg (which
  can end up positioned close to X=0 by the time the boss gets there) a
  beat to grow/shrink on its own before the boss starts moving back
  through that space.
- Verified: `tests/thunder_test.py` rewritten again for the pool/
  terrain-reaching/ThunderS-cells/pause design (51 checks) - pool
  alloc/reset, `GET_TERRAIN_ROW_FOR_COL`'s own tier->row mapping (all 4
  tiers), per-row draw/erase parity, a full lifecycle test against a
  SAFE terrain tier (0, everything stays <20, no reassertion needed)
  AND a DEEP tier (3, forces the ground band, with the test itself
  simulating the real per-frame terrain clobber between calls to prove
  the reassertion pass is doing real work, not a no-op - this is what
  caught the transition-frame gap above), the fixed trigger-column math
  for both legs with a real no-overlap-with-the-boss assertion, and a
  real `MAINLOOP` sweep confirming the left-edge pause's own actual
  duration, multiple concurrent columns genuinely alive at once, and a
  real ThunderS cell actually appearing on landing. Also confirmed
  visually via 3 rendered frames (two columns growing simultaneously,
  a column that reached deep into the ground band with visible
  ThunderS cells at its base, and the boss paused at the left edge with
  no visual overlap against nearby columns). Full regression suite:
  439/442 passing - same 3 known `GAME_TICK=840`-boot-effect failures
  (`boss_test.py`, `etank_gametick_gate_test.py`, `night_effect_test.py`),
  no new regressions - `boss_test.py`/`boss_pose_test.py`/`horming_
  test.py` needed real updates for the new left-edge pause (drive
  through `BOSS_PHASE=2` via a direct `GAME_TICK` bump, same pattern
  already used for `BOSS_POSE_TICKS`) and the pause's own knock-on
  shift to `GAME_RNG`'s accumulated value at first-fire time (which
  volley target a homing missile wanders to, and therefore whether it
  reaches state3 before hitting the stationary test tank, is RNG-timing
  dependent - the sweep now gets a 2nd volley's worth of chances rather
  than asserting on just the first).

## Round 11: Thunder tuning again - 1 cell shorter, ThunderS is 2x2 diagonal, 8-Tick pause, boss dip/rise

- User feedback (verbatim): "サンダーの到達を1セル手前に サンダーSを
  左右斜め下に で、今は左右1セルだが２セルな 斜め下1セル横に１セル
  ００１１００ ２２００２２ こういう形状 １がサンダー ２がサンダーS
  で、サンダーSを消す時も順に ２２００２２ から ２００００２ という
  具合で で、まだ反転時ボスにサンダーが当たってるんで８Tick停止に変
  更 次に右初期位置から左に移動する際に左斜下8px移動してから水平移
  動に変更 戻る時は逆に到達8px前から右斜め上に移動して初期位置に".
- **Thunder stops 1 cell earlier**: `UOT_GROW`'s own stop-line moved
  from `terrain_row` to `terrain_row-1`, so `DEEP_ROW` ends up
  `terrain_row-2` (was `terrain_row-1`).
- **ThunderS redesigned as a 4-cell diagonal shape** (2 cells per side,
  not 1): `00 11 00 / 22 00 22` - left pair at `(COL-2,COL-1)`, right
  pair at `(COL+2,COL+3)`, BOTH at row `DEEP_ROW+1` (one row below the
  bolt's own new, 1-cell-shorter stop point - visually fills back in
  almost exactly where the bolt used to reach before this round, just
  diagonally offset). Erase is now 2 explicit sub-steps spliced onto the
  end of the shrink sequence (`ROW` counts up past `DEEP_ROW` to
  `DEEP_ROW+1`/`+2`): inner cells (`COL-1`,`COL+2`) first, outer cells
  (`COL-2`,`COL+3`) one step later - "２２００２２から２００００２".
  The contested-row (>=20) reassertion pass (`UOT_REASSERT_SIDES`) now
  covers this too, including the 1-frame gap where only the outer cells
  are still meant to be visible.
- **Real bug caught and fixed while building this**: every ThunderS
  helper (`UOT_DRAW_SIDES`/`UOT_ERASE_SIDES_INNER`/`_OUTER`/`UOT_
  REASSERT_SIDES_OUTER`) originally cached the target row once in
  register `D` before looping over 2-4 cells - but `WRITE_THUNDERS_
  CELL`/`ERASE_ONE_THUNDER_CELL` both call `NIGHT_ROW_ADDR` internally,
  which returns its own result in `DE`, silently clobbering that cached
  row for every cell after the first. Fixed by re-reading `(IX+3)+1`
  fresh immediately before each individual cell write/erase instead of
  caching it - caught by a real test (not inspection) checking all 4
  cells actually appear, not just the first.
- **`BOSS_LEFT_PAUSE_TICKS` 2->8** - "まだ反転時ボスにサンダーが当た
  ってるんで" - round9's own 2-tick pause wasn't long enough.
- **The boss's own patrol gained a diagonal dip/rise** at each end -
  "右初期位置から左に移動する際に左斜下8px移動してから水平移動に変更
  戻る時は逆に到達8px前から右斜め上に移動して初期位置に". New
  `BOSS_DIP_DIST`(8, divides evenly by `BOSS_SPEED`(2) - no partial-step
  remainder to handle) and a genuinely dynamic `BOSS_Y` RAM variable
  (was a fixed `BOSS_SPAWN_Y` constant everywhere - `DRAW_BOSS` and the
  collision box both needed updating to read it). `UBA_MOVE_LEFT` now
  steps diagonally (both axes) until `BOSS_Y` reaches `BOSS_SPAWN_Y+
  BOSS_DIP_DIST`, then falls through to the pre-existing horizontal-only
  logic unchanged; `UBA_MOVE_RIGHT` mirrors this for the final
  `BOSS_DIP_DIST` px before `BOSS_SPAWNX`, clamping `BOSS_Y` back to
  exactly `BOSS_SPAWN_Y` the instant `BOSS_X` reaches `BOSS_SPAWNX`
  (same frame the pose begins - the hand-pose art's own fixed VRAM
  addresses assume `BOSS_Y` is always exactly `BOSS_SPAWN_Y` there, so
  this clamp matters). `CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT` are only
  called from the horizontal-only branches, same as before - Thunder
  doesn't fire during the diagonal segments.
- Verified: `tests/thunder_test.py` extended again (69 checks - the new
  1-cell-shorter stop line, the 4-cell diagonal shape and its 2-step
  erase order including the outer-only gap, and new unit + real-
  `MAINLOOP` checks for the dip/rise's own exact stepping and timing),
  plus `tests/boss_test.py`/`tests/boss_pose_test.py` (already updated
  for the pause in Round10) needed no further changes - they drive
  through movement with `while`-loops robust to a few extra dip/rise
  frames - `boss_collision_test.py` DID need a real fix (its own
  `make_boss` test helper bypasses the real spawn branch entirely by
  poking `BOSS_ACT` directly, so it never set the new `BOSS_Y` either -
  fixed by having it also set `BOSS_Y=BOSS_SPAWN_Y`, matching what real
  spawn now does). Also confirmed visually via 3 new rendered frames
  (the boss visibly lower right after spawning, mid-dip; a landed bolt
  with the new diagonal ThunderS cells at its base; and the boss paused
  at the now-lower left-edge Y with no overlap against nearby columns).
  Full regression suite: 457/460 passing - same 3 known
  `GAME_TICK=840`-boot-effect failures (`boss_test.py`,
  `etank_gametick_gate_test.py`, `night_effect_test.py`), no new
  regressions.

## Round 12: SBeam (サンダービーム) - a new real hw-sprite attack, added after 2 completed poses

- User feedback (verbatim, with attached `SBeam_8x8.json`): "Ok 次はサ
  ンダービーム ホーミングとサンダー2セット終わったら 添付キャラをスプ
  ライトで描画 ボスポーズで手の先からまず真下にライン上に並べる で地
  上に到達したら左へラインのまま移動 左端まで行ったら元の位置まで同じ
  ラインで描画 長さは伸びていくがその分スプライトを足していく ライン
  が途切れないように 薙ぎ払いビームって感じで で、点滅で表示で 取り
  敢えず1フレ点滅で".
- **A brand-new attack, unlike Thunder**: a real hw sprite pool (not
  BG-drawn), reusing `SBEAM_CODE`(252) - the last genuinely free hw
  sprite pattern code (Thunder/ThunderS's own block is BG-only, so it
  never touched this budget) - and `SBEAM_SPR_BASE_SLOT`=`BOSS_SPR_
  BASE_SLOT`(10), i.e. the boss's own 16 body-quadrant hw sprite slots,
  which `HIDE_BOSS_SPRITES` already guarantees sit parked off-screen
  for the WHOLE pose (same "reuse a dormant owner's slots" idiom as
  Homing's own reuse of ZacoII/BulletU) - `UBAP_END` now also forcibly
  clears `SBEAM_ACT` before the boss's own body redraw reclaims those
  slots, so a still-mid-animation beam can never fight the boss's real
  body art for them.
- **Trigger gate - INFERRED**: "ホーミングとサンダー2セット終わったら"
  read as `BOSS_POSE_COUNT>=SBEAM_POSE_GATE(2)` at pose-ENTRY time (a
  new counter, incremented in `UBAP_END` every time a pose actually
  ends) - SBeam starts firing from the 3rd pose onward, alongside the
  existing homing volley (not replacing it). Flag if "2セット" meant
  something else (e.g. 2 successful Thunder shots specifically, rather
  than 2 completed poses).
- **Hand-tip anchor - INFERRED**: `SBEAM_START_COL`=28, derived from
  `SasapiHand_64x64.json`'s own lowest lit row (columns22-49 of 64,
  center~35), snapped to the nearest 8px tile column from the pose
  box's own left edge (`BOSS_SPAWNX`=192->column24, +4=28).
  `SBEAM_START_Y`=`BOSS_SPAWN_Y+64`(120, the pose box's own bottom
  edge). Flag if a different point on the hand art was actually meant.
- **3-phase state machine** (`SBEAM_ACT`: 1=drop, 2=sweep, 3=retract,
  0=idle), driven every raw frame from `MAINLOOP` (`UPDATE_SBEAM`,
  alongside `UPDATE_THUNDER`) - it deliberately does NOTHING to VRAM at
  all while `SBEAM_ACT=0`, since it shares slots with the boss's own
  real body art and must never touch them outside a pose:
  - **Drop** (`US_DROP_STEP`): grows `SBEAM_ROWS` by one 8px segment/
    frame straight down from the hand tip, using `GET_TERRAIN_ROW_FOR_
    COL` (same terrain-cache walk Thunder's own `ALLOC_THUNDER_SLOT`
    uses) to find the real ground pixel Y at `SBEAM_START_COL`, fixed
    once at fire-time. Transitions to sweep the instant the ground is
    reached.
  - **Sweep** (`US_SWEEP_RETRACT`, ACT=2): "で地上に到達したら左へライ
    ンのまま移動" - the vertical line is REPLACED by (not overlaid
    with) a horizontal one at the fixed ground Y, growing left one 8px
    column/frame via `SBEAM_FRONT_COL` decreasing, until it reaches the
    screen's actual left edge (column0) - "左端まで行ったら".
  - **Retract** (same routine, ACT=3): "元の位置まで同じラインで描画"
    read as a SHRINK-back (not a symmetric regrow), `SBEAM_FRONT_COL`
    increasing back toward `SBEAM_START_COL`; done (ACT=0) once home.
    No vertical re-retraction on the way back - the user's own message
    only describes a horizontal round trip.
  - Both drop and sweep/retract space segments 8px apart (matching
    `SBEAM_SPRITE`'s own top-left-8x8-lit convention from
    `sbeam_gen.py` - the unlit 3/4 of each 16x16 sprite box harmlessly
    overlaps its neighbor) so the line has no visible gaps -
    "ラインが途切れないように".
  - `STAGE_SBEAM`'s own rendering is a SINGLE unified formula for both
    sweep and retract: segment `i` sits at column `SBEAM_START_COL-i`,
    visible iff that column `>= SBEAM_FRONT_COL` - only the direction
    `SBEAM_FRONT_COL` itself moves differs between the two phases.
- **A real, deliberate hardware cap - flagged, not silently
  reinterpreted**: MSX1 only has 32 hw sprite slots total, and only 16
  of them (the boss's own dormant body slots) are ever safely reusable
  here, so `SBEAM_SLOT_COUNT`=16. A full sweep needs up to 29 columns
  (`SBEAM_START_COL`+1 down to 0); the unified rendering formula means
  only the 16 columns closest to `SBEAM_START_COL` (28 down to 13) ever
  actually get a sprite - `SBEAM_FRONT_COL` itself keeps tracking all
  the way down to 0 for timing purposes, but columns 12 down to 0 never
  visibly extend. This is a genuine deviation from a literal
  "スプライトを足していく...ラインが途切れないように" (add sprites
  without limit) - the beam's own visible reach is capped at 16 cells
  (128px) from the hand's own column, not the full screen width.
- **Blink**: "点滅で表示で 取り敢えず1フレ点滅で" - `STAGE_SBEAM` toggles
  `SBEAM_BLINK` every call; on the "off" tick every slot is forced
  hidden (Y=209) regardless of phase, a plain 1-frame-on/1-frame-off
  flicker.
- Verified: new `tests/sbeam_test.py` (36 checks - the pattern actually
  loaded at boss-spawn time alongside Homing's own reuse of Flyer's
  block, the `BOSS_POSE_COUNT` gate, `SBEAM_GROUND_Y` computed correctly
  against all 4 terrain tiers, the drop's own exact per-frame growth and
  drop->sweep transition, the sweep/retract's own exact `SBEAM_FRONT_
  COL` stepping and both phase transitions, `STAGE_SBEAM`'s own sprite-
  attr correctness for every phase including the blink toggle and the
  hw-cap formula, and a real `MAINLOOP` sweep confirming SBeam stays
  silent before the 3rd pose, actually fires from it, completes a full
  drop/sweep/retract cycle in real play, and `SBEAM_ACT` is always back
  to 0 whenever the boss is patrolling - i.e. it never fights the boss's
  own body sprite for `SBEAM_SPR_BASE_SLOT..`). Full regression suite:
  493/496 passing - same 3 known `GAME_TICK=840`-boot-effect failures
  (`boss_test.py`, `etank_gametick_gate_test.py`, `night_effect_test.py`),
  no new regressions. Also confirmed visually via 4 rendered frames (the
  drop growing from the hand toward the ground next to 2 unrelated
  Thunder bolts of the same color; the sweep as a horizontal line along
  the ground; the sweep at the hw-cap's own full 16-sprite extent once
  it reaches the left edge; the retract with its far/left end already
  shrunk back while the near/origin end is still lit).

## Round 13: SBeam round-2 fixes - wrong origin, vanishing vertical arm, and Homing/Thunder exclusivity

- User feedback (verbatim, after being sent a diagnostic build that fired
  on the 1st pose in bright white to isolate whether the mechanism itself
  ever renders): "なるほど 言っていた実装と全く違ってた訳だ 誰がボス
  の直下でしかも1回だけ設置なんて指示したよ おまえほんの一瞬たった8px
  しか描画されないのに見えるかよ どこが薙ぎ払いビームなんだ まず発射
  起点はボスに被らない左がわ 伸ばした腕の先から 真下にラインをスプラ
  イトで引き 発射基点は変えず左端まで移動しながらスプライトでライン
  を引いて元まで戻る 当然サンダービーム中はホーミングもサンダーも撃
  たねえんだよ". The diagnostic build confirmed the FIRE/render mechanism
  itself was never broken - `FIRE_SBEAM` fired reliably from the 3rd pose
  onward in every emulator sweep tried (deterministic, 15+ cycles, with
  and without simulated player fire), so the earlier "発火しない" report
  was real but wasn't a firing bug - the beam WAS firing, just badly
  positioned and too short-lived to read as anything.
- **Root cause 1 - wrong origin ("ボスの直下")**: round-1's anchor
  (`SBEAM_START_COL=28`) was derived from `SasapiHand_64x64.json`'s own
  LOWEST row, which turned out to be the boss's own legs, not the
  reaching arm - and column28 sits INSIDE the pose box (`BOSS_SPAWNX`
  column24 through 31), directly under/behind the boss's own large body
  sprite. Re-examined the bitmap directly this round: the reaching hand/
  fingers are the only feature that touches the sprite's own local
  column0 (the box's left edge), at local rows23-26/33-34 - a clearly
  separate shape from the body. `SBEAM_START_COL` moved to 23 (one full
  column left of the box, genuinely clear of the boss's silhouette -
  "ボスに被らない左がわ"), `SBEAM_START_Y` to `BOSS_SPAWN_Y+24`(80,
  aligned with the hand's own vertical position - previously `BOSS_
  SPAWN_Y+64`, the box's bottom edge, nowhere near the actual hand).
- **Root cause 2 - the vertical arm vanished the instant the sweep began
  ("1回だけ設置...たった8pxしか描画されない...どこが薙ぎ払いビームなん
  だ")**: `STAGE_SBEAM`'s own `SS_SWEEP` branch REPLACED the drop's own
  rendering entirely once `SBEAM_ACT` moved from 1(dropping) to 2
  (sweeping) - the vertical line that took several frames to grow was
  thrown away in a single frame, leaving only the horizontal line, which
  itself started at zero length. From the player's own perspective this
  reads as two separate, brief, disconnected blips rather than one
  continuous sweeping beam. Fixed by rewriting `SS_SWEEP` to draw an
  L-SHAPED line: the vertical arm (`SBEAM_ROWS` segments, fixed the
  instant the drop finishes) stays on screen for the ENTIRE sweep AND
  retract, while the horizontal arm grows/shrinks alongside it from a
  SEPARATE pool of slots - "発射基点は変えず...ラインを引いて元まで戻
  る" (the origin end must stay visibly connected the whole time, not
  disappear).
- **hw sprite budget, revisited**: splitting the existing 16-slot budget
  between a now much taller vertical arm (10-13 segments, since the real
  hand anchor is far higher up than the round-1 guess) and a horizontal
  arm left almost no room for the sweep to read as a real "薙ぎ払い".
  Re-audited the FULL 32-slot hw sprite table and found slots26-31 (6
  slots) are the ONLY ones in the entire file NEVER claimed by anything -
  contiguous right after the boss's own 16-slot block (10-25), making
  `SBEAM_SPR_BASE_SLOT`(10) through 31 one 22-slot run. `SBEAM_SLOT_
  COUNT` 16->22 - these 6 extra slots need no "only during the pose" care
  the boss's own reused 16 need, since nothing else ever touches them.
  The combined vertical+horizontal cap is still real and still flagged
  (22 total, not literally unbounded), just less punishing than before.
- **SBeam/Homing exclusivity ("当然サンダービーム中はホーミングもサン
  ダーも撃たねえんだよ")**: `UBA_MOVE_RIGHT`'s pose-entry now BRANCHES
  on the `SBEAM_POSE_GATE` check instead of calling both `ARM_HORMING_
  VOLLEY` and `FIRE_SBEAM` unconditionally - below the gate, only Homing
  arms (as before); at/above it, only SBeam arms, and Homing is skipped
  entirely for that pose. `FIRE_SBEAM` itself lost its own internal gate
  check (moved to the call site, since the call site now needs the same
  answer to decide which routine to call). Thunder needed no separate
  change: its own trigger checks (`CHECK_THUNDER_TRIGGER_LEFT`/`_RIGHT`)
  only run from the patrol-leg code paths, never during a pose, so it
  already can't newly fire "during" SBeam by construction. A Thunder bolt
  already mid-flight from the JUST-FINISHED patrol leg is deliberately
  left to finish its own existing shrink animation rather than force-
  cleared - `RESET_THUNDER_POOL` only zeroes each slot's own ACT byte,
  it does NOT erase whatever's already drawn on the BG name table, so
  force-clearing mid-animation would leave orphaned lightning cells on
  screen with no slot left to ever erase them - a strictly worse bug than
  a few overlapping frames of an already-fading bolt.
- Verified: `tests/sbeam_test.py` rewritten for the new design (42
  checks) - the corrected origin position and its "left of the box"
  invariant, `FIRE_SBEAM` now unconditional, the L-shaped rendering's own
  exact per-slot correctness (vertical arm slots0..ROWS-1 unchanged
  throughout, horizontal arm slotsROWS.. extending from `SBEAM_START_
  COL-1`), the combined 22-slot cap, the new pose-entry branch (Homing
  armed below the gate / SBeam at-or-above it, with `HORMING_VOLLEY_
  COUNT` proven untouched via a sentinel value during an SBeam pose), and
  a real `MAINLOOP` sweep confirming the vertical and horizontal arms are
  genuinely visible TOGETHER at some point (not just sequentially) and
  that no homing missile is ever active while SBeam is active anywhere in
  a full real playthrough. Full regression suite re-run after this round
  - see the actual pass/fail counts in this round's own commit/report,
  same 3 pre-existing known failures expected, no new regressions.
  Confirmed visually via 4 re-rendered frames at the corrected anchor -
  the drop now clearly separate from the boss's own body (previously
  overlapping it) and, most importantly, the sweep/retract frames now
  show the full connected L-shape (vertical hand-to-ground arm PLUS
  horizontal ground-hugging arm) simultaneously, not two disconnected
  blips.

## Round 14: SBeam round-3 - a real diagonal line, not an L-shape

- User feedback (verbatim, with a hand-drawn diagram - a fan of curved
  lines all meeting near the boss's own hand, fanning out to different
  points along the ground toward the tank): "取り敢えずは動いたな しか
  し真下だけじゃなくそのまま左へスプライトのラインを描きながら左に先
  端を移動するんだよ で、左まで行ったら折り返して最初の真下を描いて
  終了 意味わからんか? 絵を描いたからこんな感じだ 青の線な 複数本じ
  ゃなく1本だぞ". Round13's own L-shape (a rigid vertical arm plus a
  separate horizontal arm meeting at a 90-degree corner) was itself
  still wrong - "複数本じゃなく1本" (one line, not several) plus the
  diagram's own fan-of-diagonals (each stroke a straight shot from the
  SAME point near the hand to a DIFFERENT point along the ground) means
  this is ONE real diagonal line from the fixed origin to a moving tip,
  not two fixed-shape arms glued at a corner.
- **Redesigned `STAGE_SBEAM` around a real Bresenham line algorithm**:
  the tip's own PATH is unchanged from round12 (state-wise, still just
  `SBEAM_ROWS` growing during the drop and `SBEAM_FRONT_COL` moving
  during sweep/retract - `US_DROP_STEP`/`US_SWEEP_RETRACT` needed ZERO
  changes this round), but the RENDERED LINE is now the real straight
  segment from the fixed origin `(SBEAM_START_COL,SBEAM_START_ROW)` to
  the tip's current grid position, computed fresh every frame via a
  classic integer error-accumulator Bresenham walk (`SSL_X_BRANCH`/
  `SSL_Y_BRANCH`, picked by whether `dx>=dy`) - all in 8px-grid units,
  converted to pixels only when writing each slot. This degenerates
  cleanly to a pure vertical line while `dx=0` (still dropping - same
  visual as before), and becomes a genuine, increasingly-shallow
  diagonal as the tip sweeps left (the UPPER portion of the line, near
  the origin, changes angle too - it does NOT stay rigidly vertical
  above a fixed corner the way round13's own L-shape did).
- New RAM scratch bytes (`SBEAM_LINE_TX/_TY/_DX/_DY/_ERR/_X/_Y`,
  F36Ch-F372h) hold the Bresenham state - all recomputed fresh every
  `STAGE_SBEAM` call, never read anywhere else. `SBEAM_START_ROW`
  (`SBEAM_START_Y/8`) is a new compile-time constant for the origin's
  own grid-row.
- Slot budget: the algorithm naturally produces `max(dx,dy)+1` points
  for a line from the origin to the tip - up to 24 in the worst case
  (full-width sweep at the deepest terrain), still capped at
  `SBEAM_SLOT_COUNT`(22) exactly as before, same honest hw-sprite-budget
  caveat, just applied to one line's own length instead of 2 arms'
  combined length.
- Verified: `tests/sbeam_test.py`'s own sweep/retract checks rewritten
  around exact hand-computed Bresenham output (a pure-vertical dx=0
  case, an exact 45-degree dx==dy==10 case with a fully-enumerated
  expected point list, a shallow dx=20/dy=10 case checking monotonic
  column/row progression, and the dx=23/dy=9 worst-case hw-cap check),
  plus a real `MAINLOOP` sweep confirming a genuinely diagonal line
  (both X and Y varying across the visible slots at once) actually
  appears during real play. 43 checks, all passing. Full regression
  suite re-run after this round - same 3 pre-existing known failures
  expected, no new regressions (see this round's own commit for the
  exact pass/fail counts). Confirmed visually via 4 re-rendered frames -
  the sweep and retract frames in particular now show a single
  unbroken diagonal line from the boss's own hand down to the ground and
  out toward the tank, closely matching the user's own hand-drawn
  reference diagram, instead of the previous round's rigid right-angle
  L-shape.

## Round 15: real crash fix - SBeam froze/reset the whole game at the screen's left edge

- User feedback (verbatim): "サンダービームで左端まではOk しかしビーム
  が左端まで行くとリセットかかった" - the beam's own diagonal-line
  rendering (Round14) was correct up to the left edge, but reaching it
  crashed the whole game (a hard reset, not a visual glitch).
- **Root cause - a real off-by-one in `STAGE_SBEAM`'s own hw-sprite cap
  check**: `SSL_X_BRANCH`'s cap logic was `LD A,SBEAM_SLOT_COUNT+1 : CP
  B : JR NC,SSL_X_NOCAP` (B = dx+1, the line's own natural point count).
  `CP` only sets CARRY on a strict borrow, so when B landed EXACTLY on
  `SLOT_COUNT+1` (i.e. dx==SLOT_COUNT==22, one column short of the
  screen's actual left edge) the subtraction `23-23` produced ZERO, not
  a borrow - `JR NC` treated that as "no cap needed" and let B=23
  through uncapped, one past the real budget. `SSL_HIDE_REST` then
  computed `SLOT_COUNT-C` = `22-23` = -1, which as an unsigned byte is
  255 - the "hide the rest" loop then ran 255 times instead of "0 or a
  few", walking `IX` about 1000 bytes past `SBEAM_SPRITE_ATTRS`'s own
  88-byte allocation and overwriting whatever real RAM sat there
  (including, eventually, the stack) - a real, reproducible crash, not
  a rare/theoretical one: `tests/banked_helpers.py`'s own `call_routine`
  hit its 300000-step safety limit and asserted, confirming the routine
  genuinely never returned once this exact case was hit directly.
- **Fix**: compare against `SBEAM_SLOT_COUNT` itself (not `+1`) and
  branch on the CARRY from `SLOT_COUNT-B` (set exactly when `B>SLOT_
  COUNT`, covering the `B==SLOT_COUNT+1` case the old check missed).
  `SSL_Y_BRANCH` never needed this cap (its own natural point count -
  `dy+1` - tops out around 13, always well under `SBEAM_SLOT_COUNT`).
- Verified: `tests/sbeam_test.py` gained an EXHAUSTIVE sweep over every
  `(dx,dy)` combination the real terrain+sweep geometry can ever
  produce (dy=0-12, tx=0-`SBEAM_START_COL`), checking both the exact
  expected point count AND that `STAGE_SBEAM` actually returns (would
  have hung/asserted before this fix), plus the EXACT reported crash
  case (`FRONT_COL=1`, `dx=SBEAM_SLOT_COUNT`) as its own explicit check -
  45 checks total, all passing. This is the kind of boundary bug a
  couple of hand-picked sample values (what Round14's own tests used)
  can hide entirely - worth remembering for any future per-frame
  cap/clamp logic in this file: sweep the FULL input range, not just a
  few representative points, especially right at the boundary itself.
  Full regression suite re-run after this round - same 3 pre-existing
  known failures expected, no new regressions (see this round's own
  commit for the exact pass/fail counts).

## Round 16: SBeam tuning (2 round trips, 2-on/1-off blink) + a real stack-corruption bug + the tank's own new dash

- User feedback (verbatim): "Ok ではサンダービームは2往復に で、点滅表
  示は2フレ表示1フレ非表示に変更 次に自機にダッシュを追加 上下左右入
  力の下を入れたままジャンプのBボタンを押すと今向いてる方向に倍速で
  64px移動 その時は自機スプライトの上部32x16のスプライトを下に5px下
  げるように ダッシュが終われば元の状態に". 3 independent asks - 2
  SBeam tweaks plus a genuinely new tank feature.

### SBeam: 2 round trips, 2-on/1-off blink

- **2 round trips** ("サンダービームは2往復に"): new `SBEAM_TRIP`
  counter, incremented in `US_SWEEP_RETRACT` every time a full sweep+
  retract cycle finishes; if it hasn't reached `SBEAM_TRIP_COUNT`(2)
  yet, the state machine goes back to sweeping (ACT=2) instead of
  ending - the beam now visibly reaches the screen's left edge twice per
  pose before actually finishing.
- **Blink 2-visible/1-hidden** ("点滅表示は2フレ表示1フレ非表示に変
  更"): `STAGE_SBEAM`'s own `SBEAM_BLINK` now cycles 0,1,2,0,1,2,...
  (mod 3) instead of a plain 0/1 toggle, hidden only on the 3rd value -
  a real period-3 pattern (2 frames on, 1 off), not the old 1-on/1-off.

### A real bug found and fixed while building this: SBEAM_TRIP corrupted by ordinary gameplay

While adding `SBEAM_TRIP` (which, unlike the rest of `STAGE_SBEAM`'s own
scratch bytes, needs to SURVIVE across many unrelated frames rather than
being fully recomputed every call), it landed at `F373h` - only 13 bytes
below `STACKTOP`(`F380h`). That's close enough that ORDINARY deep
CALL/PUSH nesting from code with nothing to do with SBeam (Thunder's own
multi-level draw chain: `UPDATE_THUNDER`->`UPDATE_ONE_THUNDER`->
`DRAW_ONE_THUNDER_ROW`/`WRITE_THUNDERS_CELL`->`NIGHT_ROW_ADDR`, plus
whatever `PUSH`/`CALL` overhead those routines carry) reaches down far
enough during real play to silently overwrite it as genuine stack usage.
Found by directly tracing every write to that address across a real
`MAINLOOP` run and seeing it repeatedly clobbered with garbage (106,
242, ...) while `SBEAM_ACT` was 0 the entire time - i.e. nothing SBeam-
related was running at all. Fixed by moving `SBEAM_TRIP` and the rest of
`STAGE_SBEAM`'s own Bresenham scratch bytes (`SBEAM_LINE_TX/TY/DX/DY/
ERR/X/Y`) to the free gap right after `TANK_LIFE`(`F132h`-`F139h`),
comfortably clear of the stack. The other scratch bytes were never
actually AT RISK in practice (fully written and consumed within a
single `STAGE_SBEAM` call with nothing else running in between), but
moved along anyway for one consistent, safely-away-from-the-stack home.
New regression coverage: a direct sentinel test that sets `SBEAM_TRIP`
and drives 2400 real frames of ordinary gameplay (including real
Thunder activity) confirming it survives completely untouched.

### New: tank dash (down + jump button, 64px straight run)

- **Trigger** ("上下左右入力の下を入れたままジャンプのBボタンを押す
  と"): `UPDATE_DASH`, a new routine called BEFORE `UPDATE_JUMP` from
  `MAINLOOP`, edge-detects a fresh `JOY_TRIGB` press (same mechanism
  `UPDATE_JUMP` itself already uses) while `JOY_DIR==5` - INFERRED as
  pure down only, not a down-diagonal, since the instruction just says
  "下". Also refuses to start while already mid-jump.
- **Mutually exclusive with jump, same frame included**: since
  `UPDATE_DASH` runs first and sets `DASH_ACTIVE` before `UPDATE_JUMP`
  even reads `JOY_TRIGB`, and `UPDATE_JUMP`'s own very first action is
  bailing out while `DASH_ACTIVE`, the SAME down+B press can never also
  start a jump. `UPDATE_TANK_XY` gets the same `DASH_ACTIVE` guard, so
  ordinary joystick movement/facing input is fully suppressed for the
  dash's own duration.
- **Fixed 64px, `DASH_SPEED`(3px/frame flat) run** ("今向いてる方向に
  倍速で64px移動"): "倍速" read literally as double `TANK_SPEED_LO`'s
  own 1.5px/frame average. `DASH_DIR` freezes `TANK_FACING` at the
  instant the dash starts (matches "今向いてる方向に" - the direction
  can't change mid-dash since normal input is suppressed anyway).
  Clamped against the same screen edges (`TANK_X<=224`, no underflow)
  ordinary movement already respects - not explicitly requested, but a
  sensible default rather than letting the tank dash off-screen.
- **Visual**: "自機スプライトの上部32x16のスプライトを下に5px下げるよ
  うに" - `UPDATE_TANK_SPRITES` pushes just the TL/TR quadrants (the
  tank's own top half, per its existing 4-quadrant 32x32 hw-sprite
  layout) down by `DASH_SPRITE_Y_SHIFT`(5) while `DASH_ACTIVE`; BL/BR
  are left completely alone, so the top visibly slides down toward/into
  the bottom instead of the whole body moving. Reverts automatically
  the instant `DASH_ACTIVE` clears - "ダッシュが終われば元の状態に".
- No terrain-collision/obstacle checking during the dash itself (still
  runs `UPDATE_TERRAIN_COLLISION` for vertical ground-following, just no
  special horizontal-obstacle handling) - not requested, kept simple.
- Verified: new `tests/dash_test.py` (28 checks - trigger gating
  including "no down", "already jumping", "not a new press", the same-
  frame jump-exclusion, the exact 64px/`DASH_SPEED` stepping in both
  directions, the screen-edge clamps, `UPDATE_TANK_XY`/`UPDATE_JUMP`
  both confirmed inert while dashing, the TL/TR-only sprite shift and
  its reversion, and a real `MAINLOOP` sweep confirming an actual dash
  happens end-to-end with the visual shift genuinely appearing on
  screen). `tests/sbeam_test.py` extended to 51 checks (the 2-round-trip
  state machine, the 2-on/1-off blink as a period-3 property check
  rather than a fragile hardcoded sequence, and the `SBEAM_TRIP`
  stack-safety regression test). Full regression suite: see this
  round's own commit for the exact pass/fail counts - same 3
  pre-existing known failures expected, no new regressions. Confirmed
  visually via 2 rendered frames (the tank's own top half visibly
  compressed down into the bottom half mid-dash vs. its normal pose).

## Round 17: pose-cycle reset, life bar background, and real Flyer spawn randomness

- User feedback (verbatim, 3 separate items in one message): "Ok では
  サンダービームは2往復に で、点滅表示は2フレ表示1フレ非表示に変更
  次に自機にダッシュを追加..." (Round16's own dash/2-trip/blink work,
  already covered above) "...サンダービームのあとは最初のホーミングに
  戻るように 現在はサンダーとサンダービームがリピートしてる ライフ表示
  の背景色をブラックに Flyerのスポーン位置はランダムで指示してたはず
  だが固定されてしまってる 画面上部8pxからSandsky上部までのランダムで".
- **Pose-cycle reset ("サンダービームのあとは最初のホーミングに戻る
  ように")**: `UBAP_END` incremented `BOSS_POSE_COUNT` unconditionally
  every pose, forever - once it first reached `SBEAM_POSE_GATE`(2), it
  only ever grew further (3,4,5...), so EVERY pose from then on kept
  re-arming SBeam and Homing never came back - "現在はサンダーとサン
  ダービームがリピートしてる" was real, not a misreading. Fixed by
  checking, at the moment a pose ends, whether `BOSS_POSE_COUNT` was
  ALREADY `>=SBEAM_POSE_GATE` at that pose's own entry (i.e. the pose
  that just ended WAS the SBeam pose) - if so, reset to 0 instead of
  incrementing, restarting the whole Homing/Thunder/Homing/Thunder/SBeam
  cycle. Verified with a real `MAINLOOP` sweep checking `BOSS_POSE_COUNT`
  at 7 consecutive pose entries lands exactly on `[0,1,2,0,1,2,0]`.
- **Life bar background ("ライフ表示の背景色をブラックに")**: `LIFE_
  COLOR`'s own bg nibble was 5 (the uploaded `Life_8x8.json`'s own
  purple bg, never actually questioned before) - changed to 1 (black),
  matching `HUD_ROW_BLANK_COLOR`'s own existing bg1 convention for the
  "peeled off" empty cells right next to it.
- **Flyer spawn Y ("Flyerのスポーン位置はランダムで指示してたはずだが
  固定されてしまってる")**: `ALLOC_FLYER_SLOT` was spawning every Flyer
  at a single fixed `FLYER_CRUISE_Y`(64) constant, whose own comment
  even said "untuned/inferred, no height was specified" - genuinely
  wrong regardless of whether an earlier random-Y instruction actually
  existed and got lost, or the user is recalling ZacoII's own established
  random-Y idiom (`ENEMY_SKY_Y_MIN`/`_MASK`) and expecting the same
  treatment for Flyer. Replaced with `PICK_FLYER_SPAWN_Y`, a new routine
  copying `PICK_HORMING_TARGET_X`'s own proven GAME_RNG idiom exactly
  (read-only, XOR `TICK` + the slot's own low address byte for cross-
  slot decorrelation, `AND 7Fh` then fold-subtract once since the
  121-value span isn't a power of 2) - same round4/5 lesson as Homing's
  own wander fix: a naive "read GAME_RNG and INC it" correlates across
  back-to-back callers and reads as fixed. Range: `FLYER_SPAWN_Y_MIN`(8,
  "画面上部8px") through `FLYER_SPAWN_Y_MIN+FLYER_SPAWN_Y_SPAN-1`(128,
  SkySand's own top row pixel, `16*8`) inclusive.
- Verified: `tests/sbeam_test.py` gained a 7-pose real-`MAINLOOP` sweep
  confirming the `[0,1,2,0,1,2,0]` cycle; `tests/life_bar_test.py`
  gained a check on `LIFE_COLOR`'s own bg nibble and that INIT actually
  writes it into the right color-table group; `tests/flyer_terrain_
  test.py` gained a `PICK_FLYER_SPAWN_Y` unit sweep (range + real
  variance + GAME_RNG left unmutated) plus a real-`MAINLOOP` check that
  several consecutive natural spawns land at different Y values. Full
  regression suite: see this round's own commit for the exact pass/fail
  counts - same 3 pre-existing known failures expected, no new
  regressions.

## Round 18: Thunder and SBeam now damage the tank (tip-only collision)

- User feedback (verbatim): "サンダーやサンダービームも自機が当たると
  ダメージ食らうように 判定は先端部だけでいいだろう". Neither attack
  had ever damaged the tank before this round (Homing already did, via
  `UOH_COLLIDE`, the precedent this round copies).
- **"先端部だけ" (tip only, not the whole line/bolt)**: for Thunder,
  the tip is `ROW-1` while growing (`ROW` is always one past the last
  row actually drawn - see `UOT_GROW_STEP`'s own comment) or `DEEP_ROW`
  while shrinking (fixed - `UOT_SHRINK` erases from the TOP down, so the
  bolt's own deepest cell is the last thing to disappear, staying "live"
  for nearly the entire shrink). For SBeam, the tip is exactly `SBEAM_
  LINE_TX`/`_TY`, the same single grid point `STAGE_SBEAM`'s own line
  algorithm already tracks every frame - reused directly rather than
  recomputed, so `CHECK_SBEAM_VS_TANK` must run after `UPDATE_SBEAM`
  within the same frame (it does, see `MAINLOOP`).
- **AABB shape**: same tank-side box as Homing's own `UOH_COLLIDE`
  (`TANK_X`/`TANK_Y_CUR`, real 32x32), 16px wide for Thunder's own tip
  (the bolt is drawn 2 name-table columns wide) and 8px for SBeam's
  (its own lit art is a single 8x8 cell).
- **Repeat-hit gating**: unlike Homing (a projectile that consumes
  itself on hit) or BigZum's punch (its own per-instance cooldown byte),
  Thunder/SBeam are environmental hazards with no natural "consumed on
  hit" moment and no spare per-slot byte to add a cooldown to cheaply -
  reused `TANK_FLASH_TIMER` itself as a shared "just got hit, briefly
  immune" gate (checked before applying a new hit, same `FLASH_DURATION`
  window already used for the visual flash) rather than adding new
  state - standing in a bolt/beam now costs 1 life on contact, then
  nothing more until the flash window (and the flash animation itself)
  ends.
- Verified: `tests/thunder_test.py` (+11 checks - growing-bolt tip hit,
  the trailing-body/tip distinction, shrinking-bolt tip hit, the flash-
  gated no-repeat-hit, far-away/inactive no-hits, and a real `MAINLOOP`
  check that parking the tank on a live bolt's own tip actually costs
  life) and `tests/sbeam_test.py` (+6 checks - same shape for the single-
  point tip, plus its own real `MAINLOOP` check). Full regression suite:
  see this round's own commit for the exact pass/fail counts - same 3
  pre-existing known failures expected, no new regressions.

## Round 19: real tank hitbox (16x16, Y+14) + a genuine Tick0 boot (fixed the 3 "known" failures for real)

- User feedback (verbatim): "まず自機のコリジョンは32x32ではなく16x16px
  に ただし絵の問題で左下16x16ではなくYが2pxオフセットされた16x16に変
  更 多分地形や乗っかりでズレるんで再調整 でTick0に". Two separate
  changes bundled in one message.
- **Tank hitbox 32x32 -> 16x16, Y-offset**: every real AABB check against
  the tank (`UOH_COLLIDE` for Homing, `CHECK_ONE_THUNDER_VS_TANK`,
  `CHECK_SBEAM_VS_TANK` - added Round18) used the tank's own full 32x32
  sprite box. New `TANK_COLLISION_WIDTH/_HEIGHT`(16/16) and `TANK_
  COLLISION_X_OFFSET/_Y_OFFSET`(0/14) constants replace it everywhere -
  `X_OFFSET=0` matches "左下" (left-aligned, unchanged). `Y_OFFSET` is a
  genuine INFERENCE: "bottom-left" alone would be `32-16=16` (flush with
  the sprite's own bottom edge), but the user explicitly said NOT that,
  offset 2px instead, without saying which direction. Guessed UP
  (`Y_OFFSET=14`, 2px shy of flush-bottom) since a hitbox sitting exactly
  flush with the sprite's own bottom edge is the more common source of
  the "地形や乗っかりでズレる" clipping the user is already anticipating
  - flag/flip (`14`<->`18`) if it turns out backwards once actually
  tested. `HORMING_COLLISION_SIZE`(the old 32-only constant) is gone,
  replaced entirely by the new shared constants.
- **"でTick0に"**: reverted the long-standing `LD HL,840:LD(GAME_TICK),HL`
  "初期Tickを840に" fast-iteration diagnostic boot (present since early
  in this file's own history, explicitly commented "Revert to XOR A / 0
  for a real shipped build" but never actually reverted until now) to a
  real `LD HL,0:LD(GAME_TICK),HL` boot. This was ALSO the real root cause
  behind the 3 "known pre-existing failures" this session kept reporting
  every single round (`boss_test.py`/`etank_gametick_gate_test.py`/
  `night_effect_test.py`) - all 3 now pass for real, confirmed via a full
  regression run. Not a coincidence: those tests were written assuming a
  genuine 0 boot and were catching a real discrepancy the whole time,
  just one that got waved off as "known" instead of fixed.
- **Ripple effect, entirely expected and worked through methodically**:
  removing the 840-tick head start means `BOSS_SPAWN_TICK`(999)*8=7992
  raw frames are now genuinely needed before the boss ever spawns (vs.
  needing only `(999-840)*8=1272` before) - several existing tests' own
  real-`MAINLOOP` sweep frame budgets, sized around the old fast boot,
  were no longer enough to observe the boss reaching its first pose at
  all, which cascaded into every pose-dependent check in the same sweep
  failing too. Bumped `horming_test.py`'s own 3 affected loops (6000/
  6000/8000 -> 12000/9000/12000). Separately (and unrelated to Tick0),
  every existing direct-hit collision unit test in `thunder_test.py`/
  `sbeam_test.py`/`horming_test.py` that set `TANK_Y_CUR` to exactly
  match a tip's own row assumed the OLD flush 32x32 box - genuinely
  broke against the new 16x16/Y+14 box (a real, correct test failure,
  not a false one) and needed `- TANK_COLLISION_Y_OFFSET` added to each.
- Verified: all 3 previously-failing files fixed in place rather than
  left as "known" (`horming_test.py` 157/157, `thunder_test.py` 77/77,
  `sbeam_test.py` 58/58, each individually re-run to completion before
  trusting the full suite). Full regression suite: see this round's own
  commit for the exact pass/fail counts - expect 0 known failures now,
  genuinely 0/N rather than "N-3 known".

## Round 20: 30-frame hazard invulnerability, Flyer/SkySand overlap, life 10

- User feedback (verbatim): "Ok ズレは特に感じなかった 次にサンダーや
  サンダービームで連続ダメージを受けてしまうんで自機に当たったら30フレ
  当たり判定を停止 でFlyerの出現位置がSandskyに被ってる場合がある ラン
  ダム範囲を16px狭く 帰還時もSandskyに被らないように ライフ初期値を10
  に". First line confirms Round19's own `TANK_COLLISION_Y_OFFSET=14`
  guess (up, not down) reads fine in practice - no flip needed.
- **30-frame hazard invulnerability**: `TANK_FLASH_TIMER` alone
  (`FLASH_DURATION`=6 frames) was too short a gate for Thunder/SBeam -
  standing in one for consecutive frames still drained `TANK_LIFE`
  roughly every 6 frames. New `TANK_HAZARD_IFRAMES` (dedicated RAM byte,
  own once-per-frame countdown added to `UPDATE_TANK_SPRITES` right next
  to `TANK_FLASH_TIMER`'s own) with `TANK_HAZARD_IFRAME_DURATION`=30 -
  set alongside (not instead of) `TANK_FLASH_TIMER` on a hit, so the
  visual flash keeps its own established short duration for every other
  damage source (BigZum/Homing) while Thunder/SBeam specifically gate
  repeat hits on the new, longer timer.
- **Flyer/SkySand overlap ("Flyerの出現位置がSandskyに被ってる場合があ
  る ランダム範囲を16px狭く")**: Round17's own spawn-Y range topped out
  at 128 (SkySand's own top row pixel) for the sprite's TOP-LEFT corner,
  letting the real 32x32 body reach well past SkySand at low rolls -
  `FLYER_SPAWN_Y_SPAN` 121->105 (16px narrower, the user's own explicit
  number), new max top-left Y=112. "帰還時も" (the exit phase too) needed
  no separate fix: `UOFL_EXIT_MOVE` never touches Y at all (only X, see
  its own comment) - the exit's own Y is always whatever the spawn or the
  home/pursuit phase last left it at, and pursuit's own ascending ceiling
  (`TANK_Y_CUR-FLYER_CLEAR_Y`, `TANK_Y_CUR` never below ~132 even at the
  jump's own peak) already sits well under 112 - so the one spawn-range
  fix covers both.
- **Life 10** ("ライフ初期値を10に", was 6): `TANK_LIFE_INIT` 6->10.
  `LIFE_DISPLAY`'s own bar was a hardcoded 6-cell loop - new `LIFE_BAR_
  CELL_COUNT`(=`TANK_LIFE_INIT`) constant sizes it to the real life total
  instead (cols9-18, still clear of `GAME_TICK_DISPLAY`'s own cols29-31).
- Verified: `tests/thunder_test.py`/`tests/sbeam_test.py` each gained a
  real 30-frame-countdown check (refused through all 29 intermediate
  frames, allowed again exactly on the 30th) rather than just re-checking
  "still gated somewhere". `tests/flyer_terrain_test.py` updated for the
  new span/max. `tests/life_bar_test.py` rewritten to read `TANK_LIFE_
  INIT`/`LIFE_BAR_CELL_COUNT` dynamically instead of hardcoding 6
  anywhere, so a future life-total change won't silently desync the test
  from the game again. Full regression suite: see this round's own commit
  for the exact pass/fail counts - expect 0 failures, matching Round19's
  now-genuinely-clean baseline.

## Round 21: Thunder now actually reaches the screen's left edge

- User feedback (verbatim): "サンダー攻撃で自機が画面左端にいると当たら
  ない 明らかに直撃してる".
- **Root cause, confirmed empirically (not guessed)**: on the rightward
  leg (after the left-edge reversal), `CHECK_THUNDER_TRIGGER_RIGHT`
  places each bolt at column `(BOSS_X-16)/8`, trailing behind the boss's
  own left edge (Round9's own anti-self-overlap fix). Its FIRST trigger
  of the leg waited for the same `THUNDER_TRIGGER_DX`(32) cadence as
  every later trigger, but the leg always starts with `BOSS_X=0` (the
  reversal point) - so the first bolt could never fire before
  `BOSS_X>=32`, putting its own leftmost reach at column2/pixel16. A
  real MAINLOOP sweep through a full patrol (`min col ever seen`)
  confirmed column2 really was the minimum ever allocated under the old
  code - it can never go lower, in any real play sequence, not just the
  synthetic unit tests. Meanwhile the tank's own Round19 hitbox
  (`TANK_COLLISION_WIDTH`=16, `_X_OFFSET`=0) at `TANK_X=0` (the screen's
  actual leftmost clamp) covers pixels[0,15] only - one pixel short of
  ever touching a bolt at pixel16. Adjacent, not overlapping: a real,
  reproducible dead zone exactly at the screen's left edge, matching the
  report precisely ("画面左端にいると" - specifically there, nowhere
  else, since everywhere else the player has room to shift right into
  the overlap).
- Ruled out first: `CHECK_ONE_THUNDER_VS_TANK`'s own AABB arithmetic
  (swept tank_x in [0,1,2,8,15,16] x bolt_col in [0,1,2,3] directly
  against the built ROM - every case matched the expected overlap
  formula exactly, including tank_x=0) and 8-bit underflow in the
  trigger's own column math (structurally impossible - the leg can't
  even reach its first trigger before `BOSS_X>=THUNDER_TRIGGER_DX`,
  well clear of underflow). Also considered whether the ThunderS side-
  flare cells (drawn diagonally beside the bolt's own tip, up to
  COL-2..COL+3) were the mismatch instead - rejected: the user's own
  prior explicit instruction ("判定は先端部だけでいいだろう", Round18)
  deliberately excludes them from collision, so a miss there is by
  design, not a bug to fix.
- **Fix**: new `THUNDER_EDGE_TRIGGER_DX`(16) - the true minimum distance
  needed to keep the bolt (`BOSS_X-16`) clear of the boss's own
  `[BOSS_X,BOSS_X+64)` body, independent of the 32px pacing cadence.
  `CHECK_THUNDER_TRIGGER_RIGHT` now uses this narrower threshold ONLY
  for the leg's very first trigger (detected via `THUNDER_LEG_START_X
  ==0`, a value that only ever occurs right after the left-edge
  reversal - never again mid-leg, since it's re-armed to a nonzero
  `BOSS_X` the instant that first bolt fires). Every subsequent trigger
  in the leg still uses the full `THUNDER_TRIGGER_DX`(32) cadence,
  unchanged - "ボスが横に32px移動毎に発射" (Round9) still holds for the
  whole leg except this one earlier first shot. At `BOSS_X=16` the first
  bolt now lands at column0 (pixel0-15) - the ONE column that can
  actually overlap a tank sitting at `TANK_X=0`.
- The leftward leg was checked too and needs no equivalent fix: its own
  bolts trail behind the boss's right edge (`BOSS_X+64`), so as `BOSS_X`
  decreases toward the left-edge reversal the column only ever gets
  LARGER, never smaller - the sweep's own leftward-leg minimum (column8/
  pixel64) is nowhere near the edge and was never the reported problem.
- Verified: `tests/thunder_test.py` gained a direct
  `CHECK_THUNDER_TRIGGER_RIGHT` unit test at the new 16px threshold
  (fires exactly at 16, not 1px short; lands at column0; still clear of
  the boss's own body; the 2nd trigger in the leg still needs the full
  32px, not another 16), a direct `CHECK_THUNDER_VS_TANK` integration
  check (a column0 bolt actually damages a tank at `TANK_X=0` - the
  exact reported scenario), and a real MAINLOOP sweep asserting a
  genuine column0 bolt is reached during an actual patrol (not just
  constructible by hand). 89/89 passed. Full regression
  (`tests/run_all.py` + every individual file): **592 passed, 0
  failed** - no regressions from Round20's own clean baseline.

## Round 22: real-hardware-only freeze - 2 confirmed root causes (uninitialized boot state + a stack/array collision)

- User report chain (verbatim, in order): "サンダーの問題は修正されたが
  実機で確認すると起動直後にブラックアウトする WebMSXは動く BlueMSXは画
  面右端のBG一列が乱れてた" → (after back-and-forth) "初期画面は描画さ
  れたあと 全画面でブラックアウトしてフリーズしてるな そのコードが怪し
  いかもな" → "だからボス関係ないって言ってんだろ 起動してステージ２の
  頭 Tick0の段階でブラックアウト 何回いやわかんだよおまえ" → "このバグ
  り方で怪しいのは RAM、スタック、バンクだな まあバンクはとっくに16KB
  超えてたと思うが RAMが8KBに収まってるか スタックが溢れてないかチェッ
  ク" → "多分原因はボスだな ホーミング、サンダー実装あたりまでは動いて
  る ただサンダーの時点でTick840スタートでまだボスに到達してないのにサ
  ンダーが１回描画されてた". Real hardware only - WebMSX unaffected; BlueMSX
  showed a distinct rightmost-BG-column glitch.
- **A whole-session blind spot found along the way**: `z80emu.py` (this
  file's own test CPU) never fires interrupts at all - confirmed by
  reading its own `step()` (only tracks the `iff1` flag for DI/EI, never
  actually delivers one). Combined with this ROM's own deliberate "no
  per-frame HALT, rely on H.TIMI" architecture, every "real MAINLOOP"
  regression test this entire session (600+ checks) has been structurally
  blind to any interrupt-timing bug. Flagged, not fixed (fixing the
  emulator itself is a much bigger, separate undertaking) - worth
  remembering next time a real-hardware-only bug shows up.
- **Root cause 1, confirmed by direct code audit (not guessed)**:
  `BOSS_ACT`, `SBEAM_ACT`, `THUNDER_PENDING`, `THUNDER_ELIGIBLE`, and all
  4 `THUNDER_POOL` slot ACT bytes were NEVER zeroed at boot - the ONLY
  such fields in the whole file that weren't. Every other pool (ENEMY/
  ZUM/BIGZUM/FLYER/ETANK/CLOUD/HORMING) gets an explicit INIT-time zero;
  Thunder only had `RESET_THUNDER_POOL`, called once, but only at the
  boss's own real spawn (`BOSS_SPAWN_TICK`), not at boot. Yet
  `UPDATE_BOSS_ALL`/`UPDATE_THUNDER`/`CHECK_THUNDER_VS_TANK`/
  `UPDATE_SBEAM`/`CHECK_SBEAM_VS_TANK` are ALL called unconditionally
  every single MAINLOOP frame from frame1, regardless of whether the
  boss has ever spawned. This test harness always boots with RAM
  zeroed, so the bug was invisible to every test all session; real
  hardware boots with genuinely random RAM. A garbage nonzero
  `BOSS_ACT` at boot sends `UPDATE_BOSS_ALL` straight into its own
  "already active" branch, reading `BOSS_X/Y/DIR/PHASE/POSE_COUNT/
  POSE_END_TICK` - none of which have ever been written - and a garbage
  `BOSS_PHASE` could plausibly route into the patrol/Thunder-trigger
  branches with equally-garbage `BOSS_X`, arming and firing a REAL
  Thunder shot well before the boss's own real spawn condition, which
  matches "Tick840スタートでまだボスに到達してないのにサンダーが１回
  描画されてた" precisely. Fixed: `BOSS_ACT`/`SBEAM_ACT`/
  `THUNDER_PENDING`/`THUNDER_ELIGIBLE`/all 4 `THUNDER_POOL` ACT bytes
  now explicitly zeroed in `INIT`, matching every other pool's own
  established convention.
- **Root cause 2, confirmed empirically**: a direct per-instruction SP
  trace (`z80emu.py`, active input - movement+firing - through boss
  spawn, tracking `cpu.sp` on every single step, not just at frame
  boundaries) found ordinary nested `CALL`s alone (no interrupts
  involved, which this harness can't simulate anyway) dipping SP to
  `F36Ah` - genuinely inside `SBEAM_SPRITE_ATTRS`'s own last byte
  (`F36Bh`). `SBEAM_SPRITE_ATTRS` (88 bytes) sat at `F314h`, only 20
  bytes below `STACKTOP`(`F380h`) - the exact same bug class an earlier
  round already fixed once for `SBEAM_TRIP` alone (see STACKTOP's own
  comment: "shifting every OTHER RAM address...down by 100h...256+
  bytes of genuinely free headroom"), but SBeam's own sprite-attrs
  block was added later and never got the same margin. Relocated to
  `C000h`, deep in the otherwise-completely-unused `C000h`-`EEFFh`
  region (confirmed nothing else in the file uses any address below
  `EF00h`). `STACKTOP` itself was deliberately left untouched (per its
  own comment, it's "the correct real BIOS boundary") - the fix moves
  the colliding array away, not the stack.
- **A temporary real-hardware diagnostic was also added**: border-color
  checkpoints (`LD B,n : LD C,7 : CALL WRTVDP`) bracket every top-level
  `CALL` in one `MAINLOOP` pass, reusing the same idiom `INIT` already
  has for its own boot sequence. Left in for this round's ROM as a
  safety net in case the 2 fixes above don't fully resolve the freeze -
  whichever border color the screen is frozen on pinpoints exactly which
  call never returned. Remove once real-hardware testing confirms the
  freeze is gone (flagged in-source as "TEMPORARY...not meant to ship").
- Verified: 2 new test files this round -
  `tests/boot_init_test.py` (12 checks: every one of the newly-zeroed
  fields, plus a regression guard confirming HORMING_POOL's own
  already-correct zero stays that way) and `tests/stack_safety_test.py`
  (4 checks: a static proximity margin for the highest-address RAM
  variable, confirmation `SBEAM_SPRITE_ATTRS` is out of the old danger
  zone, and 2 real per-instruction-SP-trace checks through a real boss-
  spawn playthrough). Full regression (`tests/run_all.py`): 608 passed,
  0 failed (up from 592 - the 16 new checks across both files).
- 3 bisection ROMs were sent along the way to help localize this
  (`A_before_thunder_fix`, `B_before_tick0_fix`, `C_before_sbeam`) -
  the user's own testing narrowed it down to "works through Homing/
  Thunder implementation" before the RAM/stack hypothesis and the
  `THUNDER_POOL` boot-zero gap were found and confirmed by code audit.

## Open items / things to watch

- **RAM addresses that need to persist across frames must stay clear of
  `STACKTOP`(`F380h`)** - Round16's own real bug (see above): a scratch
  byte at `F373h` (13 bytes below `STACKTOP`) got silently overwritten
  by ordinary deep CALL/PUSH nesting from unrelated code during real
  play. A byte that's fully written-then-read within one routine call
  (nothing else runs in between) is safe regardless of proximity to the
  stack; anything meant to survive across frames should live somewhere
  with real headroom below `STACKTOP` instead - the `TANK_LIFE`/`DASH_*`
  block's own free gap (`F132h`-`F13Fh`ish) has been a proven-safe
  choice for that this round. Worth a deliberate proximity check
  (`STACKTOP - address`) any time a NEW persistent RAM variable is added
  near the high end of the `F3xx` range.

- **SBeam's own 22-sprite hw cap** (16 from the boss's own dormant pose-
  time body + 6 genuinely free elsewhere - see Round13 above) now bounds
  ONE diagonal Bresenham line's own length (Round14) - `max(dx,dy)+1`
  points, up to 24 in the worst case (full-width sweep, deepest
  terrain), capped at 22. `SBEAM_FRONT_COL` still tracks all the way to
  the screen's left edge for timing even though the line's own far end
  may get truncated by the cap in that worst case - if a future
  instruction implies the beam should visibly reach the FULL screen
  width regardless of terrain depth, that needs more slots, not a
  rendering change - 22 is the real ceiling (32 hw sprites total minus
  tank/enemy/bullet's own permanent 10).

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
