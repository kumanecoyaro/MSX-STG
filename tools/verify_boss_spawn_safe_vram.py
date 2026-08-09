"""Functional-equivalence check for replacing BOSS_SPAWN's 5 `CALL
LDIRVM` (BIOS, opaque internal timing) with `CALL SAFE_LDIRVM` (our
own explicit OUT+NOP loop, modeled on ROWXFER's proven-safe per-byte
shape). z80emu.py's LDIRVM stub is an instant, always-correct copy -
it does not model real VDP write timing/corruption at all - so this
test cannot prove the real-hardware bug is fixed (only actual
hardware/an accurate timing-level emulator can). What it DOES prove:
the new explicit routine transfers the exact same bytes to the exact
same VRAM addresses as the old BIOS-call version, i.e. the swap is a
pure timing-implementation change with no functional regression.

Usage: python3 tools/verify_boss_spawn_safe_vram.py [path/to/old_source.asm]
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


def run_until_pc(z, target_pc, max_instr=400000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=400000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


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

    # BOSS_SPAWN starts by calling BOSS_CLEAR_DYNAMIC_ENEMIES, which
    # scans ENEMY_POOL (fine with a zeroed/fresh pool) and frees sprite
    # numbers - harmless with fresh RAM. Call the whole routine.
    call_routine(z_old, sym_old['BOSS_SPAWN'])
    call_routine(z_new, sym_new['BOSS_SPAWN'])

    ok = z_old.vram == z_new.vram
    print(f"VRAM after BOSS_SPAWN identical (old LDIRVM vs new SAFE_LDIRVM): {ok}")
    if not ok:
        diffs = [i for i in range(len(z_old.vram)) if z_old.vram[i] != z_new.vram[i]]
        print(f"  {len(diffs)} differing bytes, first few: {diffs[:10]}")
        for i in diffs[:10]:
            print(f"    VRAM[{i:04X}]: old={z_old.vram[i]:#04x} new={z_new.vram[i]:#04x}")
        sys.exit(1)

    # sanity: confirm the transfer actually happened (not a vacuous
    # all-still-zero comparison) by checking a byte inside the
    # BOSS_PATTERNS destination range actually changed from the
    # pre-transfer fill value.
    changed = any(z_new.vram[i] != 0 for i in range(192 * 8, 192 * 8 + 64 * 8))
    print(f"BOSS_PATTERNS destination range actually written (non-vacuous check): {changed}")
    if not changed:
        sys.exit(1)


if __name__ == '__main__':
    main()
