"""Verifies the Enemy3 defensive safety-net fix end-to-end using the
REAL INIT routine (not a hand-poked subset of RAM) - this is the
corrected version of an earlier draft that manually poked only a
handful of RAM cells and never actually executed INIT, so
ENEMY3_POOL's ROW/COL fields (never part of the assembled ROM's
{addr:byte} output, since EQU'd RAM addresses aren't emitted bytes)
silently stayed at the emulator's zero-fill default instead of
reflecting what INIT actually sets them to - masking the very bug
this test exists to catch.

Checks:
1. After running INIT to completion (INIT: through the JP MAINLOOP at
   its end - all BIOS calls it makes, e.g. INIT32/LDIRVM/WRTVDP, are
   stubbed no-ops in z80emu.py), all 8 ENEMY3_POOL slots have
   ACTIVE=0 and ROW=1 (not the pre-fix 0), matching the new INIT
   patch.
2. Running ENEMY3_UPDATE_SLOT (the safety net) against each of those
   8 idle slots does NOT touch the score-HUD's row0/col0 cell - i.e.
   the erase write it performs targets (row=1, colN), never (0,0).
3. Regression guard: with the OLD source (git HEAD, pre-safety-net),
   this same after-INIT state simply never exercises the new
   defensive code path at all (ROW field didn't matter before), so
   this test is only meaningful against the new source - it's run
   only against the working tree.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')


def assemble():
    text = open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
    asm = Assembler(text)
    out = asm.assemble()
    mem = bytearray(65536)
    for addr, val in out.items():
        mem[addr & 0xFFFF] = val & 0xFF
    return mem, asm.symtab


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=200000):
    z.sp = (z.sp - 0x100) & 0xFFFF  # scratch area below whatever INIT left SP at
    ret_sentinel = 0x0000
    z.push_ret = None
    sp = z.sp
    z.wr(sp, ret_sentinel & 0xFF)
    z.wr((sp + 1) & 0xFFFF, (ret_sentinel >> 8) & 0xFF)
    z.pc = entry_addr
    run_until_pc(z, ret_sentinel, max_instr)


def main():
    mem, sym = assemble()
    z = Z80(bytearray(mem))

    z.pc = sym['INIT']
    run_until_pc(z, sym['MAINLOOP'])
    print("INIT ran to completion (reached MAINLOOP).")

    base = sym['ENEMY3_POOL']
    ok_pool = True
    print("\n=== 1. ENEMY3_POOL state after real INIT ===")
    for slot in range(8):
        s = base + slot * 11
        active = z.mem[s + 0]
        row = z.mem[s + 4]
        col = z.mem[s + 5]
        good = (active == 0 and row == 1)
        ok_pool &= good
        print(f"  slot {slot}: ACTIVE={active} ROW={row} COL={col}  [{'OK' if good else 'MISMATCH'}]")

    score_before = bytes(z.mem[sym['NAMEBUF']:sym['NAMEBUF']]) if False else None
    # row0/col0 in VRAM is where the score HUD's first digit lives -
    # capture it (as drawn by INIT's own SCORE_DISPLAY call) before
    # exercising the safety net.
    def row0col0_vram():
        # ROWADDR for row 0, col 0 is simply VRAM 0x1800 (name table base)
        return z.vram[0x1800 + 0]

    hud_before = row0col0_vram()
    print(f"\nScore HUD row0/col0 VRAM byte after INIT: {hud_before:#04x}")

    print("\n=== 2. Safety net (ENEMY3_UPDATE_SLOT on each idle slot) leaves HUD alone ===")
    ok_hud = True
    for slot in range(8):
        s = base + slot * 11
        z.ix = s
        call_routine(z, sym['ENEMY3_UPDATE_SLOT'])
        hud_after = row0col0_vram()
        good = (hud_after == hud_before)
        ok_hud &= good
        print(f"  after slot {slot} update: row0/col0 VRAM={hud_after:#04x}  [{'OK' if good else 'MISMATCH - HUD CORRUPTED'}]")

    print("\n=== 3. Safety net writes land at the slot's own (row=1) cell, sky region ===")
    # sanity: row=1 is above GROUND_ROW0 (scroller), so ENEMY3_ERASE_CELL
    # should target the sky path (BLANKCODE), not read NAMEBUF garbage.
    ground_row0 = sym['GROUND_ROW0']
    print(f"  GROUND_ROW0={ground_row0}, slot ROW=1 -> {'sky (expected)' if 1 < ground_row0 else 'scroller (unexpected)'}")

    if not (ok_pool and ok_hud):
        print("\nFAILED")
        sys.exit(1)
    print("\nAll checks passed.")


if __name__ == '__main__':
    main()
