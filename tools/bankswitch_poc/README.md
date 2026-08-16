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

## Expected on-screen result

Boots straight to a mostly-blank SCREEN1, "STAGE 2" text appears near
the top-left almost immediately, and a single digit below it counts
0-9 repeating, roughly twice a second.
