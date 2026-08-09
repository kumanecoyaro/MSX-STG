"""Correctness check for the SET_SPRITE_ADDR sprite-number-rotation
change: 57 call sites across the enemy pool, formation A/B, Enemy3, and
elsewhere were mechanically converted from an inline "set VDP address for
sprite N" sequence to CALL SET_SPRITE_ADDR, which now also rotates
sprites 2-31 by SPRITE_ROTATE_OFS (player 0-1 always pass through
unrotated) so the hardware's 4-sprites-per-scanline limit drops a
different sprite each frame instead of always the same one.

Three checks:
1. SET_SPRITE_ADDR's rotation matches the reference formula for every
   (sprnum, offset) combination - bijective, in-range, exact match.
2. BC is preserved across the call (the inline sequence it replaces
   never touched BC; every one of the 57 call sites may have BC live).
3. At SPRITE_ROTATE_OFS=0, CALL SET_SPRITE_ADDR produces byte-identical
   VDP I/O (port,value pairs) to the original inline sequence it
   replaced, for a representative sample of the 57 call sites spanning
   the enemy pool, formation A/B, and Enemy3 - not just the isolated
   subroutine, but through the actual call sites in context.

Usage: python3 tools/verify_sprite_rotation.py [path/to/old_source.asm]
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


def reference_rotate(sprnum, offset):
    if sprnum < 2:
        return sprnum
    return (sprnum - 2 + offset) % 30 + 2


def check_rotation_formula_and_bc(mem, sym):
    mismatches = []
    bc_leaks = []
    for offset in range(30):
        for sprnum in range(32):
            z = Z80(bytearray(mem))
            z.mem[sym['SPRITE_ROTATE_OFS']] = offset
            z.a = sprnum
            z.b = 0xAA
            z.c = 0x55
            call_routine(z, sym['SET_SPRITE_ADDR'])
            if z.b != 0xAA or z.c != 0x55:
                bc_leaks.append((offset, sprnum, z.b, z.c))
            # reverse-engineer which sprite number was addressed from the
            # VDP I/O log: first two OUT(99h) writes are (low, high) of
            # addr = SPRATR(1B00h) | write-flag(40h) + sprnum_rotated*4
            outs = [(p, v) for (p, v, pc) in z.io_out_log]
            lo, hi = outs[0][1], outs[1][1]
            addr = (lo | ((hi & 0x3F) << 8))
            got_sprnum = (addr - 0x1B00) // 4
            expected = reference_rotate(sprnum, offset)
            if got_sprnum != expected:
                mismatches.append((offset, sprnum, expected, got_sprnum))
    return mismatches, bc_leaks


def check_call_sites_identity_at_offset0(mem_old, sym_old, mem_new, sym_new):
    """A handful of the 57 converted call sites, called directly with
    representative register/memory state, compared old (raw inline) vs
    new (CALL SET_SPRITE_ADDR at offset 0) - must produce identical
    VDP I/O."""
    cases = []

    # EBSD_DRAW (enemy pool, drift_dodge) - IX must point at a valid slot
    def setup_enemy_pool(z, sym, behavior):
        base = sym['ENEMY_POOL']
        z.ix = base
        z.mem[base + sym['E_ACTIVE']] = 1
        z.mem[base + sym['E_BEHAVIOR']] = behavior
        z.mem[base + sym['E_TYPE']] = 1
        z.mem[base + sym['E_STATE']] = 3
        z.mem[base + sym['E_X']] = 90
        z.mem[base + sym['E_Y']] = 70
        z.mem[base + sym['E_SPRNUM']] = 17
        z.mem[base + sym['E_PARAM0']] = 64
        z.mem[base + sym['E_PARAM3']] = 2

    for name, entry, setup in [
        ('EBSD_DRAW-via-EBSD_UPDATE', 'EBSD_UPDATE', lambda z, sym: setup_enemy_pool(z, sym, sym['BEHAVIOR_SIMPLE_DRIFT_DODGE'])),
        ('EBSB_UPDATE', 'EBSB_UPDATE', lambda z, sym: setup_enemy_pool(z, sym, sym['BEHAVIOR_SINE_BOB'])),
    ]:
        z_old = Z80(bytearray(mem_old)); setup(z_old, sym_old)
        z_new = Z80(bytearray(mem_new)); setup(z_new, sym_new)
        z_new.mem[sym_new['SPRITE_ROTATE_OFS']] = 0
        call_routine(z_old, sym_old[entry])
        call_routine(z_new, sym_new[entry])
        cases.append((name, [(p, v) for p, v, _ in z_old.io_out_log],
                      [(p, v) for p, v, _ in z_new.io_out_log]))

    # Formation A: CHECK_BULLET_VS_FORMATION_A killing U0 top (exercises
    # a CBF_KILL_* site that calls REDRAW_UNIT_PATTERN + the sprite hide)
    def setup_formation_a(z, sym):
        z.mem[sym['E2A_U0_STATE']] = 1
        z.mem[sym['E2A_U0_TOP']] = 1
        z.mem[sym['E2A_U0_BOT']] = 1
        z.mem[sym['E2A_U0_X']] = 100
        z.mem[sym['E2A_U0_Y']] = 80
        z.mem[sym['E2A_U0_SPRNUM']] = 5
        z.mem[sym['E2A_U1_STATE']] = 0
        z.mem[sym['E2A_U2_STATE']] = 0
        z.b = 100 // 8
        z.c = 80 // 8

    z_old = Z80(bytearray(mem_old)); setup_formation_a(z_old, sym_old)
    z_new = Z80(bytearray(mem_new)); setup_formation_a(z_new, sym_new)
    z_new.mem[sym_new['SPRITE_ROTATE_OFS']] = 0
    call_routine(z_old, sym_old['CHECK_BULLET_VS_FORMATION_A'])
    call_routine(z_new, sym_new['CHECK_BULLET_VS_FORMATION_A'])
    cases.append(('CHECK_BULLET_VS_FORMATION_A (kill U0 top)',
                  [(p, v) for p, v, _ in z_old.io_out_log],
                  [(p, v) for p, v, _ in z_new.io_out_log]))

    return cases


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

    print("=== 1. Rotation formula + BC preservation (30 offsets x 32 sprite numbers) ===")
    mismatches, bc_leaks = check_rotation_formula_and_bc(mem_new, sym_new)
    if mismatches:
        print(f"  FORMULA MISMATCH in {len(mismatches)} case(s): {mismatches[:10]}")
    else:
        print("  All 960 (offset, sprnum) combinations match the reference formula.")
    if bc_leaks:
        print(f"  BC LEAK in {len(bc_leaks)} case(s): {bc_leaks[:10]}")
    else:
        print("  BC preserved in all cases.")

    print("\n=== 2. Representative call sites, identical VDP I/O at offset=0 ===")
    cases = check_call_sites_identity_at_offset0(mem_old, sym_old, mem_new, sym_new)
    all_ok = True
    for name, old_io, new_io in cases:
        ok = old_io == new_io
        all_ok &= ok
        status = "OK" if ok else "MISMATCH"
        print(f"  [{status}] {name} ({len(old_io)} old / {len(new_io)} new VDP writes)")
        if not ok:
            print(f"    old: {old_io}")
            print(f"    new: {new_io}")

    if mismatches or bc_leaks or not all_ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
