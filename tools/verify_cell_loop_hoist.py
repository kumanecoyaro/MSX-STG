"""Correctness check for the CELL_LOOP_0/2/3/5 loop-invariant-hoist
optimization ported from tools/stage2_combined/combined_test.asm's own
TERRAIN_RENDER_ROW fix (round26/27 there): assembles both the pre-change
source (git HEAD) and the current working tree, runs the real assembled
MAINLOOP segment from SKIP_G1 through DIFF_LOOP_0 (the exact "recompute
all 4 rows' own NAMEBUF content" segment, before any VDP push) from each,
against a wide sweep of IDCACHE content and every ROWPHASE value (0-7,
driven via TICK's own low 3 bits, matching how SKIP_G1 derives PHASE_G1/
G2/G4/G8 for real), and asserts identical NAMEBUF output byte-for-byte in
every case - not a reimplementation, the real assembled code from both
versions. Same methodology as tools/profile_hotpaths.py's own
scenario_namebuf_regen, but comparing 2 real source versions instead of
profiling one.
"""
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(HERE, "..")
SRC_REL = "src/CYBER SHMUP.asm"

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def assemble_flat(text):
    asm = Assembler(text)
    out = asm.assemble()
    mem = bytearray(65536)
    for addr, val in out.items():
        mem[addr & 0xFFFF] = val & 0xFF
    return mem, asm.symtab


def build_source(git_ref=None):
    if git_ref is None:
        return open(os.path.join(REPO_ROOT, SRC_REL), encoding="utf-8").read()
    return subprocess.run(
        ["git", "show", f"{git_ref}:{SRC_REL}"],
        cwd=REPO_ROOT, capture_output=True, text=True, check=True,
    ).stdout


mem_old, sym_old = assemble_flat(build_source("HEAD"))
mem_new, sym_new = assemble_flat(build_source(None))


def run_row_recompute(mem, sym, idcache_by_row, tick):
    z = Z80(bytearray(mem))
    for row, bytes_ in idcache_by_row.items():
        base = sym[f"IDCACHE{row}"]
        for i, b in enumerate(bytes_):
            z.mem[base + i] = b
    z.mem[sym["TICK"]] = tick & 0xFF
    z.sp = 0xFE00
    z.wr(0xFE00, 0x00); z.wr(0xFE01, 0x00)
    z.pc = sym["SKIP_G1"]
    stop = sym["DIFF_LOOP_0"]
    steps = 0
    while z.pc != stop and steps < 400000:
        z.step()
        steps += 1
    assert steps < 400000, "never reached DIFF_LOOP_0"
    return bytes(z.mem[sym["NAMEBUF"]:sym["NAMEBUF"] + 128])


random.seed(20260825)
mismatches = 0
total = 0
for tick in range(0, 256, 17):  # sweep every ROWPHASE value (tick&7) several times over
    for trial in range(5):
        idcache = {
            row: [random.randint(0, 5) for _ in range(33)]
            for row in (0, 2, 3, 5)
        }
        out_old = run_row_recompute(mem_old, sym_old, idcache, tick)
        out_new = run_row_recompute(mem_new, sym_new, idcache, tick)
        total += 1
        if out_old != out_new:
            mismatches += 1
            if mismatches <= 3:
                print(f"  MISMATCH tick={tick} rowphase={tick & 7}")
                print(f"    old: {list(out_old)[:16]}...")
                print(f"    new: {list(out_new)[:16]}...")

check(f"CELL_LOOP_0/2/3/5: new split-loop version matches the old single-loop version "
      f"byte-for-byte across all 8 ROWPHASE values x 5 random IDCACHE fills each "
      f"({total} cases, real assembled MAINLOOP segment SKIP_G1->DIFF_LOOP_0)",
      mismatches == 0)

# edge cases: flat terrain (all id=3, common on level ground), rowphase 0 and 7
for tick in (0, 7):
    idcache = {row: [3] * 33 for row in (0, 2, 3, 5)}
    out_old = run_row_recompute(mem_old, sym_old, idcache, tick)
    out_new = run_row_recompute(mem_new, sym_new, idcache, tick)
    check(f"flat terrain (all id=3), rowphase={tick & 7}: matches old version",
          out_old == out_new)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
