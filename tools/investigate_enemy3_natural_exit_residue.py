"""Same residue hunt as investigate_enemy3_residue.py, but with NO bullet
kills at all - every Enemy3 instance runs its full natural lifecycle
(spawn -> DIAG -> CIRCLE -> EXIT -> deactivate off-screen).

investigate_enemy3_residue.py periodically kills every active instance
every 90 frames (its "stress-test TRIGGER_EXPLOSION's slot reuse" pass).
An Enemy3's natural lifecycle (DIAG ~36f + CIRCLE 72f + EXIT ~40f) is
~150 frames, longer than that 90-frame kill interval, so in practice
every instance in that script gets shot down before it ever reaches
E3_EXIT/E3_DEACTIVATE on its own - the natural fly-away-and-vanish path
that a real-hardware report says leaves a residue cell (in the sky,
around the enemy's spawn column) was never actually exercised. This
script removes the kill pass entirely so E3_DEACTIVATE actually runs.
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


def run_full_frame(z, max_instr=400000):
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
    e3_update_addr = sym['ENEMY3_UPDATE_SLOT']
    e3_draw_addr = sym['E3_DRAW']

    writes = []  # (frame, row, col, val, caller_kind)
    frame_counter = [0]
    active_slot_ix = [None]

    orig_step = z.step
    def traced_step():
        if z.pc == e3_update_addr:
            active_slot_ix[0] = z.ix
        if z.pc == wac_addr:
            ret_pc = z.rd(z.sp) | (z.rd((z.sp + 1) & 0xFFFF) << 8)
            row = z.mem[sym['ANIM_TMP_ROW']]
            col = z.mem[sym['ANIM_TMP_COL']]
            val = z.mem[sym['ANIM_TMP_VAL']]
            kind = 'E3_DRAW' if ret_pc == e3_draw_addr + 3 else f'caller@{ret_pc:04X}'
            writes.append((frame_counter[0], row, col, val, kind, active_slot_ix[0]))
        orig_step()
    z.step = traced_step

    z.pc = sym['INIT']
    run_until(z, sym['MAINLOOP'])
    z.mem[sym['ENEMY3_BUDGET']] = 64
    z.mem[sym['ENEMY3_SPAWN_TIMER']] = 1
    z.mem[sym['PLAYERX']] = 16
    z.mem[sym['PLAYERY']] = 64

    N_FRAMES = 900  # long enough for several full natural life cycles

    deactivations = []  # (frame, slot_base, last_row, last_col)
    prev_active = {}

    for f in range(N_FRAMES):
        frame_counter[0] = f
        if f % 200 == 0:
            z.mem[sym['ENEMY3_BUDGET']] = 64  # keep the wave going, no kills ever

        z.sp = sym['STACKTOP']
        z.pc = sym['MAINLOOP']
        run_full_frame(z)

        for slot in range(8):
            base = sym['ENEMY3_POOL'] + slot * 11
            active = z.mem[base + 0]
            was_active = prev_active.get(slot, 0)
            if was_active and not active:
                deactivations.append((f, slot, z.mem[base + 4], z.mem[base + 5]))
            prev_active[slot] = active

    print(f"Simulated {N_FRAMES} frames, no kills. Total WRITE_ANIM_CELL calls: {len(writes)}")
    print(f"Natural deactivations (E3_DEACTIVATE fired): {len(deactivations)}")
    for f, slot, row, col in deactivations[:20]:
        print(f"  frame {f}: slot {slot} deactivated, last drawn cell was (row={row},col={col})")

    from collections import defaultdict
    by_cell = defaultdict(list)
    for frame, row, col, val, kind, ix in writes:
        by_cell[(row, col)].append((frame, val, kind, ix))

    ground_row0 = sym['GROUND_ROW0']
    blankcode = sym['BLANKCODE']
    hud_cells = ({(0, c) for c in range(8)} | {(0, 29), (0, 30), (0, 31)} |
                 {(0, 16), (0, 17), (0, 18)} | {(0, 20), (0, 21), (0, 22)})
    suspicious = []
    for (row, col), events in by_cell.items():
        if (row, col) in hud_cells:
            continue
        last_frame, last_val, last_kind, last_ix = events[-1]
        if row < ground_row0:
            still_something_active = any(
                z.mem[sym['ENEMY3_POOL'] + s * 11 + 4] == row and
                z.mem[sym['ENEMY3_POOL'] + s * 11 + 5] == col and
                z.mem[sym['ENEMY3_POOL'] + s * 11] for s in range(8))
            explosion_still_there = any(
                z.mem[sym['ANIM_BASE'] + s * 8] and
                z.mem[sym['ANIM_BASE'] + s * 8 + 3] == row and
                z.mem[sym['ANIM_BASE'] + s * 8 + 4] == col
                for s in range(3))
            if last_val != blankcode and not still_something_active and not explosion_still_there:
                suspicious.append((row, col, last_frame, last_val, last_kind, len(events)))

    print(f"\nSky cells touched by Enemy3/explosion code: {len(by_cell)}")
    print(f"Suspicious (ended non-blank with nothing live there): {len(suspicious)}")
    for row, col, frame, val, kind, n in suspicious:
        print(f"  (row={row},col={col}): last write at frame {frame} by {kind}, "
              f"value={val:#04x} (expected BLANKCODE={blankcode:#04x}), {n} total writes to this cell")
        # dump the full write history for this cell for manual inspection
        for wf, wrow, wcol, wval, wkind, wix in writes:
            if (wrow, wcol) == (row, col):
                print(f"      frame {wf}: val={wval:#04x} by {wkind} (ix={wix:#06x if wix else 0})"
                      if wix else f"      frame {wf}: val={wval:#04x} by {wkind}")


if __name__ == '__main__':
    main()
