# Bank-switch proof of concept (ASCII16)

Standalone test of the "safe two-hop bank switch" mechanism planned for
splitting CYBER_SUZUKA into per-stage ROM banks. Not wired into the
real game yet - this is deliberately isolated so it can be verified on
its own, both in the emulator and on real hardware.

## What it does

`bank_a.asm` assembles to bank 0 (mapped at page 1, 4000h-7FFFh, where
the MSX BIOS boots any cartridge). It's a normal, real-hardware-bootable
cartridge: valid "AB" header, BIOS SCREEN1 init, the same page-2 slot
mapping belt-and-suspenders step CYBER_GD_BOSS.asm's own INIT does.
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

## Files

- `bank_a.asm`, `bank_b1.asm` - the two bank sources
- `build_rom.py` - assembles both and concatenates them into
  `BANKSWITCH_POC.rom` (32KB = bank0 + bank1)
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

## Full-game integration test

`build_full_rom.py` builds a 64KB, 4-bank ROM with the *real* game as
stage 1, for testing the switch embedded in actual gameplay instead of
an isolated stub:

- bank0 (page1 @ boot) = the real game's page1 content, plus two small
  test-only insertions applied **in memory only** - `src/CYBER_GD_BOSS.asm`
  itself is never modified. See `patched_game_text()` for exactly what's
  patched and why (baking the trigger into the tracked source would
  make it leak into the normal single-bank `rom/CYBER_GD_BOSS1.rom`
  build too, and outside a real mapper that jump has nowhere valid to
  land).
  1. INIT explicitly selects bank1 for window B (matching this game's
     existing page2 content - explicit instead of relying on the
     mapper's power-on default).
  2. MAINLOOP gets a temporary trigger at its very top: once
     PLAYER_FLYAWAY reaches 2 (boss fully destroyed AND the player's
     exit/flyaway sequence has finished - off-screen/hidden), it
     switches window B to bank2 and jumps to 0BF00h. This is the
     actual real transition point stage 2 will eventually use, not an
     arbitrary tick count - by design, nothing is left mid-animation
     in window B at this point (BOSS_CLEAR_DYNAMIC_ENEMIES already
     ran when the boss landed, and it's the boss explosion sequence's
     own completion that kicks off the flyaway in the first place).
     An earlier version of this test fired on a bare GAME_TICK>=100
     threshold, which could land mid-battle with live enemy/bullet
     state still active in window B - not a fair or safe test of the
     real transition.
- bank1 (page2 @ boot) = the real game's page2 content, byte-for-byte
  unchanged - normal stage-1 gameplay is untouched up to the trigger.
- bank2 = the same stage-2 placeholder as the standalone POC (bank_b1.asm).
- bank3 = blank, future headroom, rounds the ROM out to 64KB.

Run `python3 build_full_rom.py` to (re)build
`CYBER_SUZUKA_ASCII16_TEST.rom` from the current source. Run
`python3 verify_full.py` to re-verify in the emulator: confirms normal
gameplay never switches early (PLAYER_FLYAWAY stays 0, bank stays 1),
then pokes PLAYER_FLYAWAY=2 directly (simulating a real boss kill,
which isn't practical to step through in the emulator - see the
script for why) and confirms the very next MAINLOOP pass reacts
correctly: switch fires through the RAM trampoline, lands exactly on
the placeholder's entry point, VRAM text draw checks out.

### Expected on-screen result (full-game ROM)

Normal gameplay as usual, through the full boss fight - only once the
boss is destroyed and the player ship finishes flying off-screen does
it cut to the same "STAGE 2" + counting-digit screen as the standalone
POC. The cut itself is the thing being tested - a clean, instant
transition confirms the switch and jump both landed exactly where
intended, with no garbage/crash in between. This does mean reaching
the trigger requires actually playing through to the boss kill, not a
short fixed wait.
