"""Correctness check for the "check E_ACTIVE via HL before PUSH HL:POP IX"
optimization in ENEMY_POOL_UPDATE_ALL and CHECK_BULLET_VS_ENEMY_POOL:
assembles both the pre-change source (git HEAD) and the current working
tree, populates ENEMY_POOL with a spread of active/inactive/behavior
mixes, calls the actual routines, and asserts identical ENEMY_POOL
memory, VRAM, and return value in every case - including bullet
positions chosen to hit and to miss, so both the "no hit, keep
scanning" and "found a hit, early RET" paths are exercised.

Usage: python3 tools/verify_enemy_pool_scan.py [path/to/old_source.asm]
"""
import sys
import os
import subprocess
import itertools

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


SINE_BOB = 1              # BEHAVIOR_SINE_BOB (Enemy4-style)
DRIFT_DODGE = 2           # BEHAVIOR_SIMPLE_DRIFT_DODGE (Enemy1-style)
ENEMY4_SINE_LUT0 = 0      # ENEMY4_SINE_LUT[E_STATE=0] - see src, first entry is 0


def hit_bullet_for(behavior, x, y):
    """Tile col/row (B,C into QUAD_HIT_TEST/EBSx_HIT_TEST) that lands
    inside this enemy's hitbox, given how each HIT_TEST derives its
    quad's pixel origin from E_X/E_Y (see EBSD_HIT_TEST/EBSB_HIT_TEST)."""
    if behavior == DRIFT_DODGE:
        # EBSD_HIT_TEST's TOP quad uses (E_X, E_Y) directly when E_TOP=1
        return (x // 8, y // 8)
    else:
        # EBSB_HIT_TEST: quad Y = E_PARAM0(=y here) + SINE_LUT[E_STATE] + 8, quad X = E_X
        return (x // 8, (y + ENEMY4_SINE_LUT0 + 8) // 8)


def populate(mem, sym, pattern):
    """pattern: list of (active, behavior, x, y) or None per slot index.
    x,y is E_X and (E_Y for drift_dodge / E_PARAM0 base-Y for sine_bob)."""
    base = sym['ENEMY_POOL']
    size = sym['ENEMY_SLOT_SIZE']
    count = sym['ENEMY_SLOT_COUNT']
    for i in range(count):
        mem[base + i * size + sym['E_ACTIVE']] = 0
    for i, entry in enumerate(pattern):
        if entry is None or i >= count:
            continue
        active, behavior, x, y = entry
        s = base + i * size
        mem[s + sym['E_ACTIVE']] = active
        mem[s + sym['E_BEHAVIOR']] = behavior
        mem[s + sym['E_TYPE']] = 1
        mem[s + sym['E_STATE']] = 0
        mem[s + sym['E_X']] = x
        mem[s + sym['E_Y']] = y
        mem[s + sym['E_SPRNUM']] = i
        mem[s + sym['E_PARAM0']] = y  # sine_bob's base Y - see hit_bullet_for
        mem[s + sym['E_PARAM1']] = 0
        mem[s + sym['E_PARAM2']] = 0
        mem[s + sym['E_PARAM3']] = i
        mem[s + sym['E_TOP']] = 1     # drift_dodge: both quadrants "alive" so EBSD_HIT_TEST doesn't skip them
        mem[s + sym['E_BOT']] = 1
        mem[s + sym['E_HP']] = 5      # sine_bob: nonzero so EBSB_HIT_TEST doesn't take the destroy-at-0 path oddly


def snapshot(z, sym):
    pool = bytes(z.mem[sym['ENEMY_POOL']:sym['ENEMY_POOL'] + sym['ENEMY_SLOT_SIZE'] * sym['ENEMY_SLOT_COUNT']])
    vram = bytes(z.vram)
    return pool, vram


def build_patterns():
    SB, DD = SINE_BOB, DRIFT_DODGE
    patterns = []
    patterns.append([])  # fully empty pool
    patterns.append([(1, SB, 100, 80)])  # one sine_bob active at slot 0
    patterns.append([(1, DD, 100, 80)])  # one drift_dodge active at slot 0
    patterns.append([None, None, (1, SB, 120, 60), None, (1, DD, 90, 150)])  # sparse mix
    patterns.append([(1, SB, 50, 50), (1, DD, 60, 60), (1, SB, 70, 70),
                      (1, DD, 80, 80), (1, SB, 90, 90), (1, DD, 100, 100)])  # dense mix, front-packed
    # last-slot-only active (worst case for early-exit scan behavior)
    p = [None] * 31 + [(1, SB, 111, 77)]
    patterns.append(p)
    return patterns


def bullet_positions_for(pattern):
    """A guaranteed miss, plus an exact hit for every active enemy in the
    pattern (so the early-return 'found a hit' path is genuinely exercised,
    not just the 'scanned everything, no hit' path)."""
    positions = [(24, 24)]  # a position that overlaps nothing in these patterns
    for entry in pattern:
        if entry is None:
            continue
        _, behavior, x, y = entry
        positions.append(hit_bullet_for(behavior, x, y))
    return positions


def main():
    old_path = sys.argv[1] if len(sys.argv) > 1 else None
    if old_path is None:
        old_text = subprocess.run(
            ['git', 'show', 'HEAD:src/CYBER SHMUP.asm'],
            cwd=REPO_ROOT, capture_output=True, text=True, check=True).stdout
    else:
        old_text = open(old_path, encoding='utf-8').read()
    new_text = open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()

    mem_old, sym_old = assemble_text(old_text)
    mem_new, sym_new = assemble_text(new_text)

    patterns = build_patterns()

    mismatches = []
    checked = 0
    hit_found = 0

    for pattern in patterns:
        # --- ENEMY_POOL_UPDATE_ALL ---
        z_old = Z80(bytearray(mem_old)); populate(z_old.mem, sym_old, pattern)
        z_new = Z80(bytearray(mem_new)); populate(z_new.mem, sym_new, pattern)
        call_routine(z_old, sym_old['ENEMY_POOL_UPDATE_ALL'])
        call_routine(z_new, sym_new['ENEMY_POOL_UPDATE_ALL'])
        checked += 1
        if snapshot(z_old, sym_old) != snapshot(z_new, sym_new):
            mismatches.append(('ENEMY_POOL_UPDATE_ALL', pattern, None))

        # --- CHECK_BULLET_VS_ENEMY_POOL: a miss, plus an exact hit for
        # every active enemy in this pattern (exercises both the early-
        # return-on-hit path and the scan-to-end-no-hit path) ---
        for col, row in bullet_positions_for(pattern):
            z_old = Z80(bytearray(mem_old)); populate(z_old.mem, sym_old, pattern)
            z_new = Z80(bytearray(mem_new)); populate(z_new.mem, sym_new, pattern)
            z_old.b = col; z_old.c = row
            z_new.b = col; z_new.c = row
            call_routine(z_old, sym_old['CHECK_BULLET_VS_ENEMY_POOL'])
            call_routine(z_new, sym_new['CHECK_BULLET_VS_ENEMY_POOL'])
            checked += 1
            if z_old.a == 1:
                hit_found += 1
            if z_old.a != z_new.a or snapshot(z_old, sym_old) != snapshot(z_new, sym_new):
                mismatches.append(('CHECK_BULLET_VS_ENEMY_POOL', pattern, (col, row)))

    print(f"Checked {checked} (routine, pool-pattern[, bullet-pos]) scenarios "
          f"({hit_found} of the CHECK_BULLET_VS_ENEMY_POOL cases were genuine hits).")
    assert hit_found > 0, "test is vacuous - no hit case actually landed, fix hit_bullet_for()"
    if mismatches:
        print(f"MISMATCH in {len(mismatches)} case(s):")
        for m in mismatches[:20]:
            print(f"  {m}")
        sys.exit(1)
    else:
        print("All scenarios byte-identical (ENEMY_POOL, VRAM, and A register where applicable).")


if __name__ == '__main__':
    main()
