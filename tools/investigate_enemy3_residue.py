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
    text = open(os.path.join(REPO_ROOT, 'src', 'CYBER_GD_BOSS.asm'), encoding='utf-8').read()
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

    # --- init like real INIT ---
    z.mem[sym['TICK']] = 0
    for g in ['PXCHAR_G8', 'PXCHAR_G4', 'PXCHAR_G2', 'PXCHAR_G1']:
        z.mem[sym[g]] = 0
    for row in range(6):
        z.sp = 0xFF00; z.wr(0xFF00, 0); z.wr(0xFF01, 0)
        z.sethl(sym[f'ROWDATA{row}']); z.ix = sym[f'IDCACHE{row}']
        z.pc = sym['REFRESH_IDCACHE_33']
        run_until(z, 0)
    z.mem[sym['BOSS_STATE']] = 0
    z.mem[sym['ENEMY3_BUDGET']] = 40
    z.mem[sym['ENEMY3_SPAWN_TIMER']] = 1
    z.mem[sym['PLAYERX']] = 16
    z.mem[sym['PLAYERY']] = 64

    # Force multiple Enemy3 instances to be perpetually "in flight" by
    # periodically re-triggering spawns (budget refill) so several are
    # concurrently active, matching real gameplay pressure.
    N_FRAMES = 500
    kill_every = 23  # arbitrary, not synced to any internal cadence

    for f in range(N_FRAMES):
        frame_counter[0] = f
        if f % 60 == 0:
            z.mem[sym['ENEMY3_BUDGET']] = 40  # keep the wave going

        z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0)
        z.pc = sym['MAINLOOP']
        run_until(z, sym['ANIM2_DONE'])

        # occasionally "fire a bullet" that kills whichever Enemy3 slot
        # is active, wherever it currently is - exercises E3_HIT_ONE_SLOT
        # repeatedly across many different live positions/speeds
        if f % kill_every == 0:
            for slot in range(8):
                base = sym['ENEMY3_POOL'] + slot * 11
                if z.mem[base + 0]:
                    row, col = z.mem[base + 4], z.mem[base + 5]
                    z.ix = base
                    z.b = col; z.c = row
                    z.sp = 0xF100; z.wr(0xF100, 0); z.wr(0xF101, 0)
                    z.pc = sym['E3_HIT_ONE_SLOT']
                    run_until(z, 0)
                    break

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
    # row0 col29-31 is GAME_TICK_DISPLAY's 3-digit tick counter (top-right
    # HUD) - it also goes through WRITE_ANIM_CELL and legitimately never
    # returns to BLANKCODE (it's always showing a digit), so it's not a
    # residue candidate and would otherwise dominate the "suspicious" list.
    hud_cells = {(0, 29), (0, 30), (0, 31)}
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
