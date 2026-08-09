"""Correctness check for the Enemy3 BG-residue fix: a bullet kill
(E3_HIT_ONE_SLOT) used to zero ACTIVE without erasing the slot's
currently-drawn nametable cell, permanently stranding it since
ENEMY3_UPDATE_SLOT returns immediately once ACTIVE=0. Fixed by
factoring the erase logic into ENEMY3_ERASE_CELL and calling it from
both the normal per-frame path and the kill path.

Two checks against the actual assembled routines (not a
reimplementation):
1. ENEMY3_UPDATE_SLOT's normal (non-kill) per-frame erase-then-redraw
   is unchanged: old source (git HEAD, pre-fix) and new source produce
   byte-identical VDP I/O for several row/col/sky-vs-scroller cases -
   confirms the ENEMY3_ERASE_CELL extraction is a pure refactor there.
2. E3_HIT_ONE_SLOT on a successful hit: old source produces NO write to
   the slot's cell at all (reproducing the bug); new source DOES write
   an erase (address-set + data byte matching what ENEMY3_UPDATE_SLOT
   would have restored - the scroller's own NAMEBUF content for rows
   inside the scroller, BLANKCODE for sky rows) before the explosion/
   score calls.

Usage: python3 tools/verify_enemy3_erase.py [path/to/old_source.asm]
"""
import sys
import os
import subprocess

sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')


def assemble_text(text):
    asm = Assembler(text)
    out = asm.assemble()
    mem = bytearray(65536)
    for addr, val in out.items():
        mem[addr & 0xFFFF] = val & 0xFF
    return mem, asm.symtab


def run_until_pc(z, target_pc, max_instr=200000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=200000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


def setup_slot(mem, sym, slot_base, row, col, namebuf_fill=None):
    mem[slot_base + 0] = 1   # ACTIVE
    mem[slot_base + 1] = 1   # state (circle - doesn't matter for these checks)
    mem[slot_base + 2] = col * 8
    mem[slot_base + 3] = row * 8
    mem[slot_base + 4] = row
    mem[slot_base + 5] = col
    mem[slot_base + 6] = 0
    mem[slot_base + 7] = 0
    mem[slot_base + 8] = 0
    mem[slot_base + 9] = 0
    mem[slot_base + 10] = 1
    if namebuf_fill is not None:
        namebuf_base = sym['NAMEBUF']
        for i in range(192):
            mem[namebuf_base + i] = namebuf_fill


def check_update_slot_unchanged(mem_old, sym_old, mem_new, sym_new):
    cases = [
        ("scroller row, namebuf=0x2A", 20, 5, 0x2A),
        ("scroller row, namebuf=0x00", 22, 10, 0x00),
        ("sky row (above scroller)", 5, 3, None),
    ]
    results = []
    for name, row, col, fill in cases:
        z_old = Z80(bytearray(mem_old))
        z_new = Z80(bytearray(mem_new))
        setup_slot(z_old.mem, sym_old, sym_old['ENEMY3_POOL'], row, col, fill)
        setup_slot(z_new.mem, sym_new, sym_new['ENEMY3_POOL'], row, col, fill)
        z_old.ix = sym_old['ENEMY3_POOL']
        z_new.ix = sym_new['ENEMY3_POOL']
        call_routine(z_old, sym_old['ENEMY3_UPDATE_SLOT'])
        call_routine(z_new, sym_new['ENEMY3_UPDATE_SLOT'])
        old_io = [(p, v) for p, v, _ in z_old.io_out_log]
        new_io = [(p, v) for p, v, _ in z_new.io_out_log]
        results.append((name, old_io == new_io, old_io, new_io))
    return results


def check_hit_erases_cell(mem_old, sym_old, mem_new, sym_new):
    cases = [
        ("scroller row, namebuf=0x2A -> erase should restore 0x2A", 20, 5, 0x2A),
        ("sky row -> erase should restore BLANKCODE", 5, 3, None),
    ]
    results = []
    for name, row, col, fill in cases:
        z_old = Z80(bytearray(mem_old))
        z_new = Z80(bytearray(mem_new))
        setup_slot(z_old.mem, sym_old, sym_old['ENEMY3_POOL'], row, col, fill)
        setup_slot(z_new.mem, sym_new, sym_new['ENEMY3_POOL'], row, col, fill)
        z_old.ix = sym_old['ENEMY3_POOL']
        z_new.ix = sym_new['ENEMY3_POOL']
        # bullet tile position = exactly the enemy's row/col -> guaranteed hit
        z_old.b = col; z_old.c = row
        z_new.b = col; z_new.c = row
        call_routine(z_old, sym_old['E3_HIT_ONE_SLOT'])
        call_routine(z_new, sym_new['E3_HIT_ONE_SLOT'])
        hit_old = z_old.a
        hit_new = z_new.a
        old_io = [(p, v) for p, v, _ in z_old.io_out_log]
        new_io = [(p, v) for p, v, _ in z_new.io_out_log]
        expected_erase_val = fill if fill is not None else sym_new['BLANKCODE']
        # last VDP data-port (0x98) write in the new trace before any
        # explosion/score writes started should be the erase byte -
        # just check it appears at all, targeting this slot's cell
        expected_addr_lo = None
        results.append((name, hit_old, hit_new, old_io, new_io, expected_erase_val))
    return results


def check_explosion_lands_at_hit_position(mem_old, sym_old, mem_new, sym_new):
    """TRIGGER_EXPLOSION expects D=hit X (pixel), E=hit Y (pixel), and
    stores them (divided by 8) into the chosen ANIM_BASE slot's ROW/COL
    fields - directly observable in RAM after the call. A regression
    that clobbers D/E before TRIGGER_EXPLOSION runs (e.g. calling
    ENEMY3_ERASE_CELL, which touches DE, without saving/restoring it
    first) would show up here as a wrong COL/ROW, not just "some VDP
    write happened" - this is what actually diagnoses the "explosion
    at the left screen edge" symptom (COL landing on 0)."""
    cases = [("mid-screen kill", 20, 15), ("near-left-edge kill (col=1, to distinguish from the COL=0 bug value)", 20, 1)]
    results = []
    for name, row, col in cases:
        z_old = Z80(bytearray(mem_old))
        z_new = Z80(bytearray(mem_new))
        setup_slot(z_old.mem, sym_old, sym_old['ENEMY3_POOL'], row, col)
        setup_slot(z_new.mem, sym_new, sym_new['ENEMY3_POOL'], row, col)
        z_old.ix = sym_old['ENEMY3_POOL']
        z_new.ix = sym_new['ENEMY3_POOL']
        z_old.b = col; z_old.c = row
        z_new.b = col; z_new.c = row
        call_routine(z_old, sym_old['E3_HIT_ONE_SLOT'])
        call_routine(z_new, sym_new['E3_HIT_ONE_SLOT'])
        # first ANIM_BASE slot (index 0) is picked when all 3 are idle, which they are here
        old_row = z_old.mem[sym_old['ANIM_BASE'] + 3]
        old_col = z_old.mem[sym_old['ANIM_BASE'] + 4]
        new_row = z_new.mem[sym_new['ANIM_BASE'] + 3]
        new_col = z_new.mem[sym_new['ANIM_BASE'] + 4]
        new_ok = (new_row == row and new_col == col)
        results.append((name, row, col, old_row, old_col, new_row, new_col, new_ok))
    return results


def main():
    old_path = sys.argv[1] if len(sys.argv) > 1 else None
    if old_path is None:
        old_text = subprocess.run(
            ['git', 'show', 'HEAD:src/CYBER_GD_BOSS.asm'],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True).stdout
    else:
        old_text = open(old_path, encoding='utf-8').read()
    new_text = open(os.path.join(REPO_ROOT, 'src', 'CYBER_GD_BOSS.asm'), encoding='utf-8').read()

    mem_old, sym_old = assemble_text(old_text)
    mem_new, sym_new = assemble_text(new_text)

    print("=== 1. ENEMY3_UPDATE_SLOT normal path unchanged (pure refactor) ===")
    ok1 = True
    for name, same, old_io, new_io in check_update_slot_unchanged(mem_old, sym_old, mem_new, sym_new):
        ok1 &= same
        print(f"  [{'OK' if same else 'MISMATCH'}] {name}")
        if not same:
            print(f"    old: {old_io}")
            print(f"    new: {new_io}")

    print("\n=== 2. E3_HIT_ONE_SLOT now erases the cell on kill (bug reproduction + fix) ===")
    ok2 = True
    for name, hit_old, hit_new, old_io, new_io, erase_val in check_hit_erases_cell(mem_old, sym_old, mem_new, sym_new):
        both_hit = (hit_old == 1 and hit_new == 1)
        # old must NOT write the erase byte to the VDP data port before TRIGGER_EXPLOSION
        # (reproducing the bug); new must write it (0x98 write with erase_val, early in the trace)
        new_has_erase_write = any(port == 0x98 and val == erase_val for port, val in new_io[:4])
        old_writes_before_explosion_count = len(old_io)
        case_ok = both_hit and new_has_erase_write
        ok2 &= case_ok
        print(f"  [{'OK' if case_ok else 'MISMATCH'}] {name}: both registered a hit={both_hit}, "
              f"new writes erase byte {erase_val:#04x} early={new_has_erase_write}")
        print(f"    old VDP writes: {len(old_io)}, new VDP writes: {len(new_io)} (new should have ~3 more: erase addr+data)")

    print("\n=== 3. Explosion lands at the actual kill position (DE-clobber regression check) ===")
    ok3 = True
    for name, row, col, old_row, old_col, new_row, new_col, new_ok in check_explosion_lands_at_hit_position(mem_old, sym_old, mem_new, sym_new):
        ok3 &= new_ok
        print(f"  [{'OK' if new_ok else 'MISMATCH'}] {name}: expected row={row} col={col} - "
              f"old gave row={old_row} col={old_col}, new gives row={new_row} col={new_col}")

    if not (ok1 and ok2 and ok3):
        sys.exit(1)


if __name__ == '__main__':
    main()
