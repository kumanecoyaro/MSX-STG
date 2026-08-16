"""Runs many real frames of MAINLOOP with a live Enemy3 wave and
occasional bullet kills, tracking every NAMEBUF write attributable to
Enemy3/explosion code (by intercepting calls to WRITE_ANIM_CELL and
recording the caller). For every (row,col) cell written by this code,
checks whether it is ever left in a state that doesn't match either
"pure sky" (BLANKCODE, for row<GROUND_ROW0) or the terrain's own
CELL_LOOP output (for row>=GROUND_ROW0) once no Enemy3/explosion
activity remains - i.e. hunts for a cell nobody ever cleans back up.
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


def run_until(z, target, max_instr=400000):
    for _ in range(max_instr):
        if z.pc == target:
            return
        z.step()
    raise RuntimeError(f"never reached {target:04X}, stuck at {z.pc:04X}")


def run_full_frame(z, max_instr=400000):
    """Runs from wherever z.pc is (expected: MAINLOOP) all the way
    through the entire per-frame body to the HALT at its end - this is
    the only way ENEMY3_TRY_SPAWN/ENEMY3_UPDATE_SLOT/the bullet-vs-
    ENEMY3 hit tests actually run; stopping at ANIM2_DONE (an earlier
    version of this script's mistake) skips all of them, since
    ENEMY3_TRY_SPAWN is CALLed right after ANIM2_DONE."""
    z.halted = False
    for _ in range(max_instr):
        if z.halted:
            return
        z.step()
    raise RuntimeError(f"never halted, stuck at {z.pc:04X}")


def main():
    mem, sym = assemble()
    z = Z80(bytearray(mem))

    wac_addr = sym['WRITE_ANIM_CELL']
    # ANIM0/1/2 finish/write blocks (the destroy-animation lifecycle) are
    # inlined in MAINLOOP, not a routine - identify them by return-address
    # range. Everything else that calls WRITE_ANIM_CELL is reported by its
    # raw return address (ENEMY3_ERASE_CELL, TRIGGER_EXPLOSION, E3_DRAW,
    # the score/tick HUD digit writers, etc.) since there are enough
    # distinct callers that mapping every one by name isn't worth it -
    # the address is enough to tell them apart in the output.
    anim_block_lo = sym['ENEMY_SECTION_DONE']
    anim_block_hi = sym['ANIM2_DONE']

    def label_for_return_pc(ret_pc):
        if anim_block_lo <= ret_pc <= anim_block_hi:
            return 'ANIM0/1/2-destroy-block'
        return f'caller@{ret_pc:04X}'

    writes = []  # (frame, row, col, val, caller)
    frame_counter = [0]

    orig_step = z.step
    def traced_step():
        if z.pc == wac_addr:
            # about to execute WRITE_ANIM_CELL; peek its RET target (top of stack)
            ret_pc = z.rd(z.sp) | (z.rd((z.sp + 1) & 0xFFFF) << 8)
            row = z.mem[sym['ANIM_TMP_ROW']]
            col = z.mem[sym['ANIM_TMP_COL']]
            val = z.mem[sym['ANIM_TMP_VAL']]
            writes.append((frame_counter[0], row, col, val, label_for_return_pc(ret_pc)))
        orig_step()
    z.step = traced_step

    # --- run the actual INIT routine (not a hand-rolled subset) - it now
    # also blanks the whole sky to BLANKCODE, which the garbage-watch
    # freeze-dump at the bottom of MAINLOOP relies on; a partial init
    # that skips that would false-trigger the watch on frame 0. ---
    z.pc = sym['INIT']
    run_until(z, sym['MAINLOOP'])
    z.mem[sym['ENEMY3_BUDGET']] = 40
    z.mem[sym['ENEMY3_SPAWN_TIMER']] = 1
    z.mem[sym['PLAYERX']] = 16
    z.mem[sym['PLAYERY']] = 64

    # Force multiple Enemy3 instances to be perpetually "in flight" by
    # periodically re-triggering spawns (budget refill) so several are
    # concurrently active, matching real gameplay pressure.
    N_FRAMES = 500
    kill_every = 23  # arbitrary, not synced to any internal cadence

    # MAINLOOP's player-direction dispatch reads the joystick via a BIOS
    # call that z80emu's bios_call always stubs to "centered/no input",
    # so a bare MAINLOOP run never actually moves the player - the
    # reported repro needs the player actively moving vertically at the
    # moment of a kill, so call MOVE_UP/MOVE_DOWN directly each frame
    # (bypassing the joystick read) to simulate that.
    move_toggle = 0

    for f in range(N_FRAMES):
        frame_counter[0] = f
        if f % 60 == 0:
            z.mem[sym['ENEMY3_BUDGET']] = 40  # keep the wave going

        # alternate a few frames of holding up, a few of holding down,
        # so kills happen mid-movement in both directions
        move_toggle = (move_toggle + 1) % 16
        z.sp = 0xF200; z.wr(0xF200, 0); z.wr(0xF201, 0)
        z.pc = sym['MOVE_UP'] if move_toggle < 8 else sym['MOVE_DOWN']
        run_until(z, 0)

        z.sp = sym['STACKTOP']
        z.pc = sym['MAINLOOP']
        run_full_frame(z)

        # Let several instances accumulate (don't kill for a stretch),
        # then kill everything active in one frame - stress-tests
        # TRIGGER_EXPLOSION's 3-slot round-robin reuse path (restore-
        # still-animating-slot-before-reuse) with genuinely concurrent
        # kills, which "kill immediately on spawn" never exercised since
        # only ever one instance was alive at a time.
        if f % 90 == 45:
            for slot in range(8):
                base = sym['ENEMY3_POOL'] + slot * 11
                if z.mem[base + 0]:
                    row, col = z.mem[base + 4], z.mem[base + 5]
                    z.ix = base
                    z.b = col; z.c = row
                    z.sp = 0xF100; z.wr(0xF100, 0); z.wr(0xF101, 0)
                    z.pc = sym['E3_HIT_ONE_SLOT']
                    run_until(z, 0)

    print(f"Simulated {N_FRAMES} frames. Total WRITE_ANIM_CELL calls attributable to "
          f"Enemy3/explosion code: {len(writes)}")

    # Group by (row,col): for cells only ever touched by Enemy3/explosion
    # code (never by the terrain scroller, i.e. row<GROUND_ROW0/sky),
    # the LAST write's value should be BLANKCODE (fully cleaned up) if
    # nothing is active there anymore by the end of the run.
    from collections import defaultdict
    by_cell = defaultdict(list)
    for frame, row, col, val, caller in writes:
        by_cell[(row, col)].append((frame, val, caller))

    ground_row0 = sym['GROUND_ROW0']
    blankcode = sym['BLANKCODE']
    # row0 col0-7 is the 8-digit score display, row0 col29-31 is
    # GAME_TICK_DISPLAY's 3-digit tick counter (top-right HUD) - both go
    # through WRITE_ANIM_CELL and legitimately never return to BLANKCODE
    # (always showing a digit), so neither is a residue candidate and
    # they'd otherwise dominate the "suspicious" list.
    hud_cells = ({(0, c) for c in range(8)} | {(0, 29), (0, 30), (0, 31)} |
                 {(0, 16), (0, 17), (0, 18)} | {(0, 20), (0, 21), (0, 22)})
    suspicious = []
    for (row, col), events in by_cell.items():
        if (row, col) in hud_cells:
            continue
        last_frame, last_val, last_caller = events[-1]
        if row < ground_row0:
            # sky cell: should end up BLANKCODE unless something is still
            # actively drawn there at the very end of the run
            still_something_active = any(z.mem[sym['ENEMY3_POOL'] + s*11 + 4] == row and
                                          z.mem[sym['ENEMY3_POOL'] + s*11 + 5] == col and
                                          z.mem[sym['ENEMY3_POOL'] + s*11] for s in range(8))
            explosion_still_there = any(
                z.mem[sym['ANIM_BASE'] + s*8] and
                z.mem[sym['ANIM_BASE'] + s*8 + 3] == row and
                z.mem[sym['ANIM_BASE'] + s*8 + 4] == col
                for s in range(3))
            if last_val != blankcode and not still_something_active and not explosion_still_there:
                suspicious.append((row, col, last_frame, last_val, last_caller, len(events)))

    print(f"\nSky cells (row<{ground_row0}) touched by Enemy3/explosion code: {len(by_cell)}")
    print(f"Suspicious (ended non-blank with nothing live there): {len(suspicious)}")
    for row, col, frame, val, caller, n in suspicious[:30]:
        print(f"  (row={row},col={col}): last write at frame {frame} by {caller}, "
              f"value={val:#04x} (expected BLANKCODE={blankcode:#04x}), {n} total writes to this cell")


if __name__ == '__main__':
    main()
