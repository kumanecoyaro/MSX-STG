"""Correctness check for the TERRAIN_RENDER_ROW loop-invariant-hoist
optimization ("処理が遅いんだよな...アルゴリズムで高速か可能なものは
ないか"): assembles both the pre-change source (git HEAD, the old
single-loop-with-per-iteration-branch version) and the current working
tree (the new split-loop version), runs the actual TERRAIN_RENDER_ROW
routine from each against a wide sweep of IDCACHE content and every
ROWPHASE_T value (0-7), and asserts identical NAMEBUF output byte-for-
byte in every case - not a reimplementation, the real assembled code
from both versions.
"""
import os
import random
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STAGE2 = os.path.dirname(HERE)
sys.path.insert(0, STAGE2)
sys.path.insert(0, os.path.join(STAGE2, "..", ".."))
sys.path.insert(0, os.path.join(STAGE2, "..", ".."))
sys.path.insert(0, "/home/user/msx-stg/tools")

from mini_z80asm import Assembler
from z80emu import Z80
import build_test

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
        body = open(os.path.join(STAGE2, "combined_test.asm")).read()
    else:
        body = subprocess.run(
            ["git", "show", f"{git_ref}:tools/stage2_combined/combined_test.asm"],
            cwd=os.path.join(STAGE2, "..", ".."), capture_output=True, text=True, check=True,
        ).stdout
    import terrain_gen, tank_gen, bullet_gen, enemy_gen, bigzum_gen, flyer_gen
    import etank_gen, sasapi_gen, sasapi_hand_gen, horming_gen, thunder_gen, sbeam_gen
    tables = (terrain_gen.emit_asm_tables() + "\n" + tank_gen.emit_asm_tables()
              + "\n" + bullet_gen.emit_asm_tables() + "\n" + enemy_gen.emit_asm_tables()
              + "\n" + bigzum_gen.emit_asm_tables() + "\n" + flyer_gen.emit_asm_tables()
              + "\n" + etank_gen.emit_asm_tables() + "\n" + sasapi_gen.emit_asm_tables()
              + "\n" + sasapi_hand_gen.emit_asm_tables() + "\n" + horming_gen.emit_asm_tables()
              + "\n" + thunder_gen.emit_asm_tables() + "\n" + sbeam_gen.emit_asm_tables())
    return body + "\n" + tables + "\n"


mem_old, sym_old = assemble_flat(build_source("HEAD"))
mem_new, sym_new = assemble_flat(build_source(None))


def call_terrain_render_row(mem, sym, idcache_bytes, rowphase):
    z = Z80(bytearray(mem))
    z.mem[sym["ROWPHASE_T"]] = rowphase
    src = sym["IDCACHE_T0"]
    dst = sym["NAMEBUF_T0"]
    for i, b in enumerate(idcache_bytes):
        z.mem[src + i] = b
    z.sethl(src)
    z.ix = dst
    z.sp = 0xFE00
    z.wr(0xFE00, 0x00); z.wr(0xFE01, 0x00)
    z.pc = sym["TERRAIN_RENDER_ROW"]
    steps = 0
    while z.pc != 0x0000 and steps < 200000:
        z.step()
        steps += 1
    assert steps < 200000, "TERRAIN_RENDER_ROW never returned"
    return bytes(z.mem[dst:dst + 32])


random.seed(20260825)
mismatches = 0
total = 0
for rowphase in range(8):
    for trial in range(20):
        idcache = [random.randint(0, 10) for _ in range(33)]  # 33 bytes: 32 cells + 1 lookahead
        out_old = call_terrain_render_row(mem_old, sym_old, idcache, rowphase)
        out_new = call_terrain_render_row(mem_new, sym_new, idcache, rowphase)
        total += 1
        if out_old != out_new:
            mismatches += 1
            if mismatches <= 3:
                print(f"  MISMATCH rowphase={rowphase} idcache={idcache[:8]}...")
                print(f"    old: {list(out_old)}")
                print(f"    new: {list(out_new)}")

check(f"TERRAIN_RENDER_ROW: new split-loop version matches the old single-loop version "
      f"byte-for-byte across all 8 ROWPHASE_T values x 20 random IDCACHE fills ({total} cases)",
      mismatches == 0)

# edge cases: all-same-id row (common on flat terrain), and the two
# ROWPHASE_T boundary values (0 and 7)
for rowphase in (0, 7):
    idcache = [3] * 33
    out_old = call_terrain_render_row(mem_old, sym_old, idcache, rowphase)
    out_new = call_terrain_render_row(mem_new, sym_new, idcache, rowphase)
    check(f"flat terrain (all id=3), rowphase={rowphase}: matches old version",
          out_old == out_new)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
