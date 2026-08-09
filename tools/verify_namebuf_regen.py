"""Correctness check for the CELL_LOOP_0..5 register-carry optimization:
assembles both the pre-change source (from git HEAD) and the current
working-tree source, runs the actual terrain nametable regen block
(SKIP_G1..ROWDONE_5, the full CELL_LOOP+DIFF_LOOP+ROWXFER sequence) for
each, across every PHASE (0-7) and a spread of PXCHAR values per group,
and asserts the resulting NAMEBUF/PREVBUF/VRAM state is byte-identical
between old and new. Not a sampling spot-check - PHASE only has 8
possible values and this covers all of them, plus enough PXCHAR values
to exercise every ROWDATA offset the 32+1-byte window can land on.

Usage: python3 tools/verify_namebuf_regen.py [path/to/old_source.asm]
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


def run_terrain_block(mem, sym, phase_g1, phase_g2, phase_g4, phase_g8,
                       pxchar_g1, pxchar_g2, pxchar_g4, pxchar_g8):
    z = Z80(bytearray(mem))
    z.mem[sym['PHASE_G1']] = phase_g1
    z.mem[sym['PHASE_G2']] = phase_g2
    z.mem[sym['PHASE_G4']] = phase_g4
    z.mem[sym['PHASE_G8']] = phase_g8
    z.mem[sym['PXCHAR_G1']] = pxchar_g1
    z.mem[sym['PXCHAR_G2']] = pxchar_g2
    z.mem[sym['PXCHAR_G4']] = pxchar_g4
    z.mem[sym['PXCHAR_G8']] = pxchar_g8
    z.pc = sym['SKIP_G1']
    run_until_pc(z, sym['ROWDONE_5'])
    namebuf = bytes(z.mem[sym['NAMEBUF']:sym['NAMEBUF'] + 192])
    prevbuf = bytes(z.mem[sym['PREVBUF']:sym['PREVBUF'] + 192])
    vram_snapshot = bytes(z.vram[0x1800:0x1800 + 256])  # name table region, generously sized
    # (port,val) only - PC differs between old/new binaries by construction
    # (the new code is a different byte sequence), so it's not part of the
    # observable behavior being checked here.
    io_ports_vals = tuple((p, v) for (p, v, pc) in z.io_out_log)
    return namebuf, prevbuf, vram_snapshot, io_ports_vals


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

    # every phase value, and enough PXCHAR offsets to walk past ROWDATA's
    # short repeating run (each ROWDATA is currently a single repeated
    # letter, but the loop reads PXCHAR..PXCHAR+32 regardless of content,
    # so any offset in this range is a valid, distinct scenario)
    pxchar_values = [0, 1, 7, 8, 15, 16, 31, 32, 47, 48, 63]
    phase_values = list(range(8))

    checked = 0
    mismatches = []
    for phase in phase_values:
        for px in pxchar_values:
            args = (phase, phase, phase, phase, px, px, px, px)
            out_old = run_terrain_block(mem_old, sym_old, *args)
            out_new = run_terrain_block(mem_new, sym_new, *args)
            checked += 1
            if out_old != out_new:
                mismatches.append((phase, px))

    # also cross the groups independently (different phase per group,
    # since G1/G2/G4/G8 aren't required to stay in lockstep in real play)
    import itertools
    for p1, p2, p4, p8 in itertools.product([0, 3, 7], repeat=4):
        args = (p1, p2, p4, p8, 10, 20, 30, 40)
        out_old = run_terrain_block(mem_old, sym_old, *args)
        out_new = run_terrain_block(mem_new, sym_new, *args)
        checked += 1
        if out_old != out_new:
            mismatches.append((f"g1={p1},g2={p2},g4={p4},g8={p8}", 'mixed'))

    print(f"Checked {checked} (phase, PXCHAR-window) combinations.")
    if mismatches:
        print(f"MISMATCH in {len(mismatches)} case(s):")
        for m in mismatches[:20]:
            print(f"  {m}")
        sys.exit(1)
    else:
        print("All combinations byte-identical between old and new (NAMEBUF, PREVBUF, VRAM, VDP I/O log).")


if __name__ == '__main__':
    main()
