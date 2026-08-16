# Bank-switch mechanism (ASCII16)

This directory started as a standalone, isolated test of the "safe
two-hop bank switch" mechanism for splitting CYBER SHMUP into
per-stage ROM banks (`bank_a.asm`/`bank_b1.asm`/`build_rom.py`/
`run_poc.py` below, kept for reference). That mechanism is now proven
on real hardware and BlueMSX/WebMSX and is the real, permanent build:
`build_full_rom.py` builds `rom/CYBER SHMUP [ASCII16].rom`, the
game's one and only shipped ROM (the old flat 32KB single-bank ROM is
retired). See "Full-game integration test" below for the real build;
the standalone POC section further down is historical/lower-priority.

## What it does

`bank_a.asm` assembles to bank 0 (mapped at page 1, 4000h-7FFFh, where
the MSX BIOS boots any cartridge). It's a normal, real-hardware-bootable
cartridge: valid "AB" header, BIOS SCREEN1 init, the same page-2 slot
mapping belt-and-suspenders step CYBER SHMUP.asm's own INIT does.
Right after boot (simulating "stage 1 just ended") it does the whole
switch in 3 instructions:

```
LD A,1
LD (7000h),A   ; ASCII16: select bank 1 for page 2 (8000h-BFFFh)
JP 0BF00h      ; jump straight into it
```

`bank_b1.asm` assembles to bank 1 (page 2, 8000h-BFFFh). Its entry
point is deliberately placed near the *end* of the 16KB window
(0BF00h) rather than the head, so that as real stage-2 content is
added later - growing upward from 8000h - it never has to move: the
jump target stays fixed. It draws "STAGE 2" on screen (BIOS default
font, no custom patterns loaded) and then loops forever, incrementing
a counter once every ~30 vblanks and showing it as a digit on row 1 -
proof the bank actually stayed live and running, not just a frozen
crash screen.

Mapper convention used: ASCII16 (16KB pages, memory-mapped bank
selects at 6000h for page 1 / 7000h for page 2 - a normal Z80 memory
write, not an OUT to an I/O port). If your flashcart/loader asks for a
mapper type, pick ASCII16.

**Real-hardware findings, in order:**

1. The very first version jumped straight from the bank-select write
   to the target address with no delay in between. On a real flashcart
   (ASCII16 correctly selected) that produced a garbled, unreadable
   screen that then froze - while the *first* switch (bank0->bank1,
   done once at boot with a lot of unrelated code executing before it
   was ever read) worked fine. Hypothesis at the time: the flashcart's
   flash chip needs a short settle time after a bank-select write
   before it presents the new bank's data. Fix tried: 16 NOPs between
   the select write and the jump.
2. That NOP fix alone did not hold up: the next real-hardware test (now
   triggering on the actual boss-kill event instead of an arbitrary
   tick, see below) froze again at the switch point - and so did
   BlueMSX, a cycle-accurate emulator with no flash-chip timing quirks
   of its own, which argues against "flash settle time" as the real
   root cause and points at something more fundamental instead.
   Adopted the standard, maximally-defensive MSX bank-switch pattern:
   a tiny "LD (7000h),A : JP (HL)" trampoline, copied into RAM
   (0xF200, a confirmed-free gap between ENEMY6_STEP_TIMER (0F1D8h)
   and STACKTOP (0F380h)) once at boot. Every switch now goes
   `LD A,<bank> : LD HL,<target> : JP 0F200h` instead of switching and
   jumping directly from ROM - the actual "LD (7000h),A" now always
   executes from RAM, so it can never itself be invalidated by the
   very bank switch it's performing, regardless of which ROM window
   issued the call. (This needed `JP (HL)` support added to
   `tools/mini_z80asm.py`/`tools/z80emu.py` - not previously used
   anywhere else in this codebase.)
3. Two more findings from the RAM-trampoline version:
   - Real hardware: froze immediately at the boot screen - a
     regression, since the pre-trampoline version had booted and run
     stage 1 fine for 13+ seconds. Root cause not yet identified.
     Added border-color checkpoints (VDP register 7) through INIT's
     new code (colors 1-4 through the trampoline setup/first select,
     color 6 right after the BIOS SCREEN1 call returns) so a report of
     "which color froze on screen" pinpoints exactly where boot stops,
     instead of guessing further blind.
   - BlueMSX (mapper correctly recognized as ASCII16): got further -
     reached the switch, drew "STAGE 2" - but in garbled/wrong colors,
     then froze. Root cause: the placeholder bank never set up its own
     color table; it was drawing real ASCII text into the color table
     the *real game* left behind from its own INIT (loaded for its own
     custom graphics, not for readable text). Fixed by having
     `STAGE2_ENTRY` paint the whole 32-group color table a single
     readable color (white on blue, 0xF4) before drawing any text.
     Confirmed in the emulator: all 32 groups read back as 0xF4.
     Whether this also explains the freeze, or the freeze is a second,
     separate issue, isn't known yet.
4. Root cause of the real-hardware boot freeze, found by the user:
   this specific flashcart **mirrors** an image instead of decoding it
   as real independent banks unless the ROM file is a "regulation"
   size for its mapper auto-detection - 64KB wasn't one of them.
   Doubling the file to 128KB (the same 64KB image - banks 0-3 -
   simply repeated once more) fixed the boot freeze completely. Both
   `build_rom.py` and `build_full_rom.py` now emit doubled files
   (64KB and 128KB respectively) for exactly this reason; only the
   first half is ever actually addressed by this ROM's own bank-select
   code, the second half is inert padding purely to satisfy the
   flashcart's size detection. The switch-to-stage2 freeze itself is
   still unresolved even with correct sizing - added more border-color
   checkpoints (7 = about to switch, in MAINLOOP; 8 = landed at
   STAGE2_ENTRY; 9 = color fill done; 10 = text draw done, entering
   the counter loop) through the switch/STAGE2_ENTRY path to narrow
   down exactly where it's still freezing.
5. With correct sizing, real hardware turned out **not** to be frozen
   at all - just showing a confusing screen. A real-hardware photo
   showed "STAGE" readable, a garbled/noisy region where " 2 " and a
   wide band at the bottom of the screen should be, plus stage 1's
   clouds, ship sprite, and score still visible. Root cause:
   `STAGE2_ENTRY` only ever wrote its own 8 text bytes and one digit -
   it never cleared the rest of the name table or hid sprites, so all
   of stage 1's leftover graphics stayed on screen, and painting a
   single uniform color across all 32 color groups (fix 3 above) made
   those un-cleared terrain/cloud patterns - designed to be viewed
   with their own original colors - render as visual noise instead.
   Fixed: `STAGE2_ENTRY` now clears the whole name table (1800h-1AFFh,
   768 cells, filled with space) and hides every sprite (writes the
   standard MSX "stop here" Y sentinel 0D1h to sprite 0, which halts
   sprite rendering for the whole table) before doing the color fill
   and text draw. Verified in the emulator by seeding VRAM with fake
   "leftover" garbage beforehand and confirming it's fully overwritten.

## Files

- `bank_a.asm`, `bank_b1.asm` - the two bank sources
- `build_rom.py` - assembles both and concatenates them into
  `BANKSWITCH_POC.rom` (bank0 + bank1, doubled to 64KB - see finding 4 above)
- `run_poc.py` - emulator-side verification: boots from `INIT`,
  confirms PC is in window A before the switch, confirms window B's
  bank actually changes, confirms landing exactly at `STAGE2_ENTRY`,
  and checks the VRAM name-table write lands on the right bytes.
  (Stops just short of the vblank-paced counter loop - this emulator
  has no interrupt source, so a real `HALT` there would spin forever;
  that part is standard BIOS behavior already exercised throughout the
  real game's own `EI:HALT` idiom.)
- `BANKSWITCH_POC.rom` - the built ROM, ready to load on a flashcart
  or in an MSX1 emulator with ASCII16 support

## Expected on-screen result (standalone POC)

Boots straight to a mostly-blank SCREEN1, "STAGE 2" text appears near
the top-left almost immediately, and a single digit below it counts
0-9 repeating, roughly twice a second.

## Full-game integration test (stage2 world, not a placeholder)

The static "STAGE 2 + counting digit" placeholder screen turned out to
be the wrong shape of test - per direct feedback: *"Stage 1と全く同じ物
をStage 2に移植してくれ、ただ敵はシンプルのみで、これは後で作り直すか
らテストだ"* (port an exact copy of stage 1 into stage 2, enemies
simple-type only, it's a throwaway test that'll be redone later). Ad
hoc fixes for the placeholder not clearing the screen/colors/sprites
were also the wrong approach - the real fix is that the switch should
land on a **real re-init**, which naturally does all of that as a side
effect of booting properly (exactly like stage 1's own boot already
does, proven working).

`build_stage2_world.py` builds a full second copy of the real game -
same terrain/engine/graphics/HUD, same boss fight at the end - but:
- the enemy roster is trimmed to type=simple only (61 entries, filtered
  straight out of the real 253-entry schedule by tick/Y, same original
  timing, just dropping every non-simple entry) plus the same boss at
  the end (tick 992, unchanged) - see `extract_simple_only_schedule()`
- a permanent "STAGE2" label is drawn next to the score (row0,
  cols10-15), using 5 new letter glyphs (S,T,A,G,E - standard 8x8
  bitmap font bytes) loaded into pattern codes 64-68 (a confirmed-free
  range) alongside the existing digit glyphs, with color group8
  (covering those codes, previously unused/free) repointed to a
  readable white-on-black to match the digit HUD's own style

Like `build_full_rom.py`, this never touches `src/CYBER SHMUP.asm` -
it transforms an in-memory copy of the raw source text (letter glyphs
+ HUD draw + color tweak + regenerated schedule tables/dispatch chain),
independently assembled into its own bank pair.

`build_full_rom.py` ties it together into the final ROM:
- bank0 (page1 @ boot) = the real game's page1 content, plus test-only
  insertions applied **in memory only** (see `patched_game_text()`):
  1. INIT explicitly selects bank1 for window B (matching this game's
     existing page2 content - explicit instead of relying on the
     mapper's power-on default) via the RAM trampoline.
  2. MAINLOOP gets a temporary trigger at its very top: once
     PLAYER_FLYAWAY reaches 2 (boss fully destroyed AND the player's
     exit/flyaway sequence has finished), it (a) mutes all 3 PSG
     channels - real-hardware finding: the flyaway sequence's sustained
     engine noise was still mid-volume at the exact instant of the cut
     and, since MAINLOOP (and the decay routine it drives) never runs
     again after switching away, was never given the chance to fade,
     leaving it stuck on - then (b) does a two-hop switch through the
     RAM trampoline: switch window B to bank3 (stage2 world's page2),
     return to window A (still bank0/stage1, untouched by that), then
     switch window A to bank2 (stage2 world's page1) and jump straight
     to its own INIT (0x4010 - same relative address, same ORG/layout).
     An earlier version fired on a bare GAME_TICK>=100 threshold, which
     could land mid-battle with live enemy/bullet state still active -
     not a fair or safe test of the real transition.
- bank1 (page2 @ boot) = the real game's page2 content, byte-for-byte
  unchanged - normal stage-1 gameplay is untouched up to the trigger.
- bank2/bank3 = stage2 world's own page1/page2 (see above).

The bank-switch trampoline (`BANKSWITCH_TRAMPOLINE_SRC`, copied to RAM
at 0xF200) now takes the mapper select port as a parameter too -
`LD (DE),A : JP (HL)`, called as `LD A,<bank> : LD DE,<6000h or
7000h> : LD HL,<target> : JP 0F200h` - since stage2 world needs to
switch window A as well as window B, not just window B like the old
placeholder did.

Run `python3 build_full_rom.py` to (re)build
`../../rom/CYBER SHMUP [ASCII16].rom` from the current source (this also
calls into `build_stage2_world.py`). Run `python3 verify_full.py` to
re-verify in the emulator: confirms normal gameplay never switches
early, pokes PLAYER_FLYAWAY=2 directly (simulating a real boss kill,
which isn't practical to step through in the emulator - actually
playing stage 2's own simple-enemy gameplay through to a real boss
kill would need simulated player input, so this isn't attempted either
- see the script for the full reasoning), confirms the PSG-mute bytes
are present (the emulator has no PSG model to observe at runtime, so
this is a static byte check, not an execution trace), confirms the
two-hop switch lands exactly on stage2 world's own INIT with both
banks correctly selected, then runs that INIT through to stage2
world's own MAINLOOP and confirms the "STAGE2" HUD label is drawn
correctly - i.e. drawn via a real boot, not a placeholder's one-off
VRAM poke.

### Expected on-screen result (full-game ROM)

Normal gameplay as usual, through the full boss fight - only once the
boss is destroyed and the player ship finishes flying off-screen does
the sound cut cleanly (no stuck engine noise) and the screen redraw
into what looks like an ordinary restart of the same game, except with
a permanent "STAGE2" label next to the score and only the simple
zigzag enemy type showing up (no formations, no waves, no BG-cell
enemies) until the same boss fight at the end. This does mean reaching
the trigger requires actually playing through to the boss kill, not a
short fixed wait.

### Diagnostic checkpoints (border color)

If the game freezes at boot or exactly at the stage-2 switch, the
border color (the true overscan border, not the in-screen sky) tells
you how far it got. Report back which color it's stuck on - these only
cover bank0's boot and the switch itself, not stage2 world's own boot
(which reuses the real game's already-proven INIT unmodified):

| Border color | Meaning |
|---|---|
| (BIOS/none - never changes) | Never reaches this patch's code at all - fails before/at cartridge boot |
| 1 | INIT started, stack pointer set |
| 2 | Primary-slot page-2 mapping step done |
| 3 | Bank-switch trampoline copied to RAM (0xF200) |
| 4 | Bank1 explicitly selected for window B via the RAM trampoline, back in ROM |
| 6 | BIOS SCREEN1 setup (INIT32) returned - normally instantly overwritten by the game's own border=1 (black) right after, so only visible if execution froze exactly here |
| 7 | MAINLOOP: PLAYER_FLYAWAY==2 detected, about to mute PSG and switch |

### BlueMSX ROM-type auto-detection

Once the ROM file is doubled to 128KB (see finding 4 above), BlueMSX's
own automatic mapper-type detection no longer identifies it as ASCII16
on its own. This is a BlueMSX-side heuristic quirk, not a bug in the
ROM - if BlueMSX shows the wrong/no mapper automatically, just set the
ROM type to ASCII16 manually in its cartridge settings; it then runs
correctly. Confirmed working this way on real hardware as well as
BlueMSX with the manual setting.
| (game's own colors, changing normally) | Past this patch's code, either still in stage 1 or already into stage2 world's own (already-proven) boot sequence |
