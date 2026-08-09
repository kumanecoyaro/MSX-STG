"""Correctness check for the IDCACHE terrain-cache optimization: runs the
*actual* assembled MAINLOOP (TICK increment, the PXCHAR_G8/G4/G2/G1 gates,
and the full terrain regen block) for many consecutive simulated frames,
letting TICK/PXCHAR evolve exactly as real gameplay would, and asserts
NAMEBUF is byte-identical to the previous (pre-cache, carry-forward-only)
committed version after every single frame.

This is a temporal/stateful change - the cache is refreshed only when its
group's PXCHAR gate fires (every 8/16/32/64 frames), so a single-frame
snapshot check isn't enough; an off-by-one in the refresh timing would only
show up a few frames after a PXCHAR rollover. Runs a full 64-tick period
(the TICK AND 3Fh wrap - the slowest group, PXCHAR_G1, updates once per
period) several times over to also catch any state that only misbehaves
after wraparound.

Usage: python3 tools/verify_idcache_multiframe.py [path/to/old_source.asm]
"""
import sys
import os
import subprocess

sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
N_FRAMES = 64 * 4  # 4 full TICK periods


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


def init_state(z, sym):
    z.mem[sym['TICK']] = 0
    z.mem[sym['PXCHAR_G8']] = 0
    z.mem[sym['PXCHAR_G4']] = 0
    z.mem[sym['PXCHAR_G2']] = 0
    z.mem[sym['PXCHAR_G1']] = 0
    z.mem[sym['BOSS_STATE']] = 0  # skip boss/DFL update calls at MAINLOOP's top - not under test
    if 'IDCACHE0' in sym:
        # mirror INIT's seeding of IDCACHE0-5 for PXCHAR=0, so frame 1
        # doesn't read stale/zeroed cache RAM (same calls INIT itself makes)
        for row, cache in [(0, 'IDCACHE0'), (1, 'IDCACHE1'), (2, 'IDCACHE2'),
                            (3, 'IDCACHE3'), (4, 'IDCACHE4'), (5, 'IDCACHE5')]:
            z.sp = 0xF000
            z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
            z.sethl(sym[f'ROWDATA{row}'])
            z.ix = sym[cache]
            z.pc = sym['REFRESH_IDCACHE_33']
            run_until_pc(z, 0x0000)


def run_frame(z, sym):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = sym['MAINLOOP']
    run_until_pc(z, sym['ROWDONE_5'])


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

    z_old = Z80(bytearray(mem_old))
    z_new = Z80(bytearray(mem_new))
    init_state(z_old, sym_old)
    init_state(z_new, sym_new)

    mismatches = []
    for frame in range(N_FRAMES):
        run_frame(z_old, sym_old)
        run_frame(z_new, sym_new)
        nb_old = bytes(z_old.mem[sym_old['NAMEBUF']:sym_old['NAMEBUF'] + 192])
        nb_new = bytes(z_new.mem[sym_new['NAMEBUF']:sym_new['NAMEBUF'] + 192])
        if nb_old != nb_new:
            diffs = [i for i in range(192) if nb_old[i] != nb_new[i]]
            mismatches.append((frame, diffs[:10]))

    print(f"Ran {N_FRAMES} consecutive frames from a cold TICK=0 start "
          f"({N_FRAMES // 64} full 64-tick periods).")
    if mismatches:
        print(f"MISMATCH on {len(mismatches)} frame(s):")
        for f, diffs in mismatches[:20]:
            print(f"  frame {f}: NAMEBUF differs at offsets {diffs}")
        sys.exit(1)
    else:
        print("NAMEBUF byte-identical to the previous committed version on every frame.")


if __name__ == '__main__':
    main()
