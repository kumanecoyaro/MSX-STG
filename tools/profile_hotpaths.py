"""Measures real T-state cost of the per-frame hot paths that were flagged
as suspects for the game's slowdown: the unified enemy-pool update/collision
scan (heavy IX-indexed field access via ENEMY_POOL) and the 6-tier parallax
terrain nametable rebuild (CELL_LOOP_0-5 in MAINLOOP). Assembles the real
source with mini_z80asm.py, loads it into z80emu.py's Z80 core, sets up a
synthetic ENEMY_POOL population, and calls the actual routines by address -
not a reimplementation - so the numbers reflect the shipped code.

Usage: python3 tools/profile_hotpaths.py
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler, AsmError
from z80emu import Z80

NTSC_TSTATES_PER_FRAME = 3579545 / 59.94  # ~59718 T-states/frame budget


def assemble():
    text = open(os.path.join(os.path.dirname(__file__), '..', 'src', 'CYBER_GD_BOSS.asm'), encoding='utf-8').read()
    asm = Assembler(text)
    out = asm.assemble()
    mem = bytearray(65536)
    for addr, val in out.items():
        mem[addr & 0xFFFF] = val & 0xFF
    return mem, asm.symtab


def make_cpu(mem):
    z = Z80(bytearray(mem))  # fresh copy per call so slot state doesn't leak between scenarios
    return z


def call_routine(z, sym, entry_addr, sp=0xF000, max_instr=200000):
    """Runs one CALL to entry_addr to completion (RET back to a sentinel)."""
    z.sp = sp
    z.wr(sp, 0x00)
    z.wr((sp + 1) & 0xFFFF, 0x00)  # return address 0x0000 = sentinel
    z.pc = entry_addr
    for _ in range(max_instr):
        if z.pc == 0x0000:
            return
        z.step()
    raise RuntimeError(f"routine at {entry_addr:04X} did not return within {max_instr} instructions")


def populate_enemy_pool(mem, sym, active_sine_bob=0, active_drift_dodge=0):
    """Fills the first N unified-pool slots ACTIVE with a given BEHAVIOR,
    matching what CHECK_BULLET_VS_ENEMY_POOL/ENEMY_POOL_UPDATE_ALL scan -
    same shape as real gameplay: a handful of active slots among
    ENEMY_SLOT_COUNT total, not a full pool."""
    base = sym['ENEMY_POOL']
    size = sym['ENEMY_SLOT_SIZE']
    count = sym['ENEMY_SLOT_COUNT']
    for i in range(count):
        mem[base + i * size + sym['E_ACTIVE']] = 0
    idx = 0
    for _ in range(active_sine_bob):
        s = base + idx * size
        mem[s + sym['E_ACTIVE']] = 1
        mem[s + sym['E_BEHAVIOR']] = sym['BEHAVIOR_SINE_BOB']
        mem[s + sym['E_TYPE']] = 1
        mem[s + sym['E_STATE']] = 0
        mem[s + sym['E_X']] = 100
        mem[s + sym['E_Y']] = 80
        mem[s + sym['E_SPRNUM']] = idx
        mem[s + sym['E_PARAM0']] = 64
        idx += 1
    for _ in range(active_drift_dodge):
        s = base + idx * size
        mem[s + sym['E_ACTIVE']] = 1
        mem[s + sym['E_BEHAVIOR']] = sym['BEHAVIOR_SIMPLE_DRIFT_DODGE']
        mem[s + sym['E_X']] = 140
        mem[s + sym['E_Y']] = 90
        mem[s + sym['E_SPRNUM']] = idx
        mem[s + sym['E_PARAM0']] = 0
        mem[s + sym['E_PARAM1']] = 0
        mem[s + sym['E_PARAM2']] = 0
        mem[s + sym['E_PARAM3']] = idx
        idx += 1


def scenario_enemy_pool(mem, sym, active_sine_bob, active_drift_dodge, n_bullets):
    z = make_cpu(mem)
    populate_enemy_pool(z.mem, sym, active_sine_bob, active_drift_dodge)
    z.reset_stats()
    call_routine(z, sym, sym['ENEMY_POOL_UPDATE_ALL'])
    for _ in range(n_bullets):
        z.b = 100  # bullet col
        z.c = 90   # bullet row (won't overlap the synthetic enemies -> worst case, always scans to the end)
        call_routine(z, sym, sym['CHECK_BULLET_VS_ENEMY_POOL'])
    return z.stats()


def run_until_pc(z, target_pc, max_instr=200000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X} within {max_instr} instructions (stuck at {z.pc:04X})")


def scenario_namebuf_regen(mem, sym):
    """CELL_LOOP_0..5 (inlined in MAINLOOP, not a CALL target) recomputes
    the 6-tier parallax nametable buffer every frame unconditionally.
    DIFF_LOOP_0..5 then compares it against PREVBUF and, on ANY mismatch
    in a row, LDIRs the whole 32-byte row and pushes all 32 bytes to VDP
    (there's no partial-row transfer - a single differing byte forces the
    whole row out). Since ROWPHASE advances every frame, PREVBUF starting
    out different from the freshly computed NAMEBUF (real INIT sets
    PREVBUF to FFh for exactly this reason - forces a full draw on the
    first frame) approximates the common case: this is not a contrived
    worst case, it's what happens whenever a row's byte pattern isn't
    bit-for-bit identical to last frame, which continuous scrolling makes
    the norm rather than the exception.

    IDCACHE0-5 must be seeded (REFRESH_IDCACHE_33, same as real INIT)
    before this runs - CELL_LOOP now reads ids from there, not straight
    from ROWDATA+LUT, and an unseeded (all-zero) cache would make every
    row compute the same degenerate id=0 pattern, which happens to make
    NAMEBUF collide with an all-zero PREVBUF and silently skip every
    row's VDP transfer - understating the real cost.

    Runs the *actual* assembled MAINLOOP bytes from SKIP_G1 (where phase
    is computed) through ROWDONE_5 (last row's VRAM transfer done, right
    before player-input code begins) - no reimplementation.
    """
    z = make_cpu(mem)
    for row in range(6):
        z.sp = 0xFF00
        z.wr(0xFF00, 0x00); z.wr(0xFF01, 0x00)
        z.sethl(sym[f'ROWDATA{row}'])  # PXCHAR=0 at cold start, same as real INIT
        z.ix = sym[f'IDCACHE{row}']
        z.pc = sym['REFRESH_IDCACHE_33']
        run_until_pc(z, 0x0000)
    z.mem[sym['PREVBUF']:sym['PREVBUF'] + 192] = bytes([0xFF]) * 192  # matches real INIT
    start = sym['SKIP_G1']
    regen_only_stop = sym['DIFF_LOOP_0'] - 8  # 8 bytes = LD HL,nn(3)+LD DE,nn(3)+LD B,n(2) right before DIFF_LOOP_0
    assert z.rd(regen_only_stop) == 0x21, "boundary drifted - CELL_LOOP_5/DIFF_LOOP_0 preamble changed, recompute the offset"
    full_stop = sym['ROWDONE_5']

    z.pc = start
    z.reset_stats()
    run_until_pc(z, regen_only_stop)
    regen_only = dict(z.stats())

    run_until_pc(z, full_stop)
    full_total = dict(z.stats())
    return regen_only, full_total


def main():
    mem, sym = assemble()

    print(f"NTSC frame budget: ~{NTSC_TSTATES_PER_FRAME:,.0f} T-states (59.94Hz)\n")

    print("=== Unified enemy pool: update + bullet collision scan ===")
    print(f"{'active(sine_bob/drift)':<24}{'bullets':<9}{'total T':<10}{'indexed(IX) T':<16}{'IX %':<8}{'pushpop T':<11}{'instr':<8}")
    for sb, dd in [(0, 0), (3, 0), (3, 3), (9, 6)]:
        for bullets in (0, 3):
            st = scenario_enemy_pool(mem, sym, sb, dd, bullets)
            pct = 100.0 * st['tstates_indexed'] / st['tstates'] if st['tstates'] else 0
            print(f"sine_bob={sb},drift={dd:<12}{bullets:<9}{st['tstates']:<10}{st['tstates_indexed']:<16}{pct:<7.1f}{st['tstates_pushpop']:<11}{st['instr_count']:<8}")

    print()
    print("=== Reference: a fully empty pool (32 inactive slots) still gets scanned ===")
    st_empty = scenario_enemy_pool(mem, sym, 0, 0, 3)
    print(f"  update(32 idle)+3 bullet scans(32 idle each): {st_empty['tstates']} T-states, "
          f"{100.0*st_empty['tstates']/NTSC_TSTATES_PER_FRAME:.2f}% of one frame's budget, purely from walking empty slots")

    print()
    print("=== Terrain parallax: unconditional per-frame nametable rebuild ===")
    regen_only, full_total = scenario_namebuf_regen(mem, sym)
    print(f"  CELL_LOOP_0..5 only (192-cell recompute):        {regen_only['tstates']:>6} T-states "
          f"({100.0*regen_only['tstates']/NTSC_TSTATES_PER_FRAME:.2f}% of frame budget), {regen_only['instr_count']} instructions")
    print(f"  + DIFF_LOOP/ROWXFER (compare + VDP push, all rows differing): "
          f"{full_total['tstates']:>6} T-states total "
          f"({100.0*full_total['tstates']/NTSC_TSTATES_PER_FRAME:.2f}% of frame budget), {full_total['instr_count']} instructions")

    print()
    print("=== Combined: worst realistic frame (terrain + 9 enemies + 3 bullets) ===")
    st_enemy = scenario_enemy_pool(mem, sym, 6, 3, 3)
    combined = full_total['tstates'] + st_enemy['tstates']
    print(f"  terrain {full_total['tstates']} + enemy-pool {st_enemy['tstates']} = {combined} T-states "
          f"({100.0*combined/NTSC_TSTATES_PER_FRAME:.1f}% of the {NTSC_TSTATES_PER_FRAME:,.0f}-T-state frame budget)")
    print("  (this excludes boss update, player input/movement, bullet spawn/move, formation-A/B and Enemy3 scans,")
    print("   particles, and score/HUD redraw, which all also run every frame on top of this)")


if __name__ == '__main__':
    main()
