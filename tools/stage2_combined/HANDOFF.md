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
  `python3 tests/run_all.py` for the full suite (140 checks as of this
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
- **Night-transition effect** (`CHECK_NIGHT`, `NIGHT_START_TICK`=100 in
  `GAME_TICK` units): sweeps 1 more row black every 16 `GAME_TICK`s,
  from `NIGHT_START_ROW`(1) through `NIGHT_END_ROW`(16, the SkySand
  row). `NIGHT_ROW` (RAM) tracks the current leading row — compare a
  row number against it (`NIGHT_ROW>=row` means "already darkened by
  the sweep") any time new code needs to know whether a specific row is
  currently dark. Don't gate on `GAME_TICK>=100` alone for anything
  row-specific — the sweep takes real time to reach any given row.

## Open items / things to watch

- No known open bugs as of this handoff — the last several rounds were
  bug reports against the night effect and horizontal-shot coloring,
  all resolved and verified (see README's most recent entries).
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
