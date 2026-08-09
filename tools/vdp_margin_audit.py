"""Comprehensive VDP-port access-margin audit: hooks every OUT/IN to
ports 98h/99h during a broad natural-gameplay simulation (terrain
scroll, Enemy3 spawn/circle/exit/kill, bullets, HUD digits, boss),
using z80emu.py's own exact T-state accounting (self.tstates,
incremented per-instruction to real Z80 timing), and reports every
consecutive pair of VDP-port accesses whose real gap is below the
~29 T-state minimum VRAM access interval the datasheet requires (the
same figure already used earlier in this investigation for the
terrain ROWXFER NOP-margin experiments).

This directly tests the "insufficient margin somewhere in the frame"
theory in a way no single manual code inspection can: it walks the
CPU's *actual* executed access sequence, in true chronological/T-state
order, across many different subsystems in the same run, rather than
guessing which routine to eyeball.
"""
import sys
import os

sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
SAFE_MARGIN = 29


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

    accesses = []  # (tstates_start, port, direction, pc_after_fetch, frame)
    frame_counter = [0]

    orig_out = z.vdp_out
    orig_in = z.vdp_in

    def traced_out(port, val):
        accesses.append((z.tstates, port, 'OUT', val, z.pc, frame_counter[0]))
        return orig_out(port, val)

    def traced_in(port):
        r = orig_in(port)
        accesses.append((z.tstates, port, 'IN', r, z.pc, frame_counter[0]))
        return r

    z.vdp_out = traced_out
    z.vdp_in = traced_in

    z.pc = sym['INIT']
    run_until(z, sym['MAINLOOP'])

    z.mem[sym['ENEMY3_BUDGET']] = 40
    z.mem[sym['ENEMY3_SPAWN_TIMER']] = 1
    z.mem[sym['PLAYERX']] = 16
    z.mem[sym['PLAYERY']] = 64
    z.mem[sym['BOSS_STATE']] = 0

    N_FRAMES = 400
    move_toggle = 0
    for f in range(N_FRAMES):
        frame_counter[0] = f
        if f % 60 == 0:
            z.mem[sym['ENEMY3_BUDGET']] = 40

        move_toggle = (move_toggle + 1) % 16
        z.sp = 0xF200
        z.wr(0xF200, 0)
        z.wr(0xF201, 0)
        z.pc = sym['MOVE_UP'] if move_toggle < 8 else sym['MOVE_DOWN']
        run_until(z, 0)

        z.sp = sym['STACKTOP']
        z.pc = sym['MAINLOOP']
        run_full_frame(z)

        if f % 90 == 45:
            for slot in range(8):
                base = sym['ENEMY3_POOL'] + slot * 11
                if z.mem[base + 0]:
                    z.ix = base
                    z.b = z.mem[base + 5]
                    z.c = z.mem[base + 4]
                    z.sp = 0xF100
                    z.wr(0xF100, 0)
                    z.wr(0xF101, 0)
                    z.pc = sym['E3_HIT_ONE_SLOT']
                    run_until(z, 0)

        # occasional simulated shot fire, to exercise bullet VDP writes too
        if f % 17 == 0:
            z.mem[sym['FIRE_COOLDOWN']] = 0

    print(f"Simulated {N_FRAMES} frames + kills + fire; total VDP port accesses: {len(accesses)}")

    # PC ranges to identify which routine an access belongs to, for reporting
    def owner(pc):
        # best-effort: find nearest preceding label from symtab (labels only,
        # not EQUs - approximate by just scanning all numeric symtab entries)
        best = None
        best_addr = -1
        for name, addr in sym.items():
            if isinstance(addr, int) and 0x4000 <= addr <= 0x9400 and addr <= pc and addr > best_addr:
                best_addr = addr
                best = name
        return best or '?'

    violations = []
    for i in range(1, len(accesses)):
        t_prev, port_prev, dir_prev, val_prev, pc_prev, f_prev = accesses[i - 1]
        t_cur, port_cur, dir_cur, val_cur, pc_cur, f_cur = accesses[i]
        # end of previous access = its start + 11 T (OUT/IN (n),A is 11T)
        gap = t_cur - (t_prev + 11)
        if gap < SAFE_MARGIN:
            violations.append((f_cur, gap, port_prev, dir_prev, pc_prev, port_cur, dir_cur, pc_cur))

    print(f"Consecutive VDP-port-access pairs with gap < {SAFE_MARGIN}T: {len(violations)}")

    # group by (pc_prev, pc_cur) - the actual code location pair - since the
    # same code runs every frame, distinct violating locations matter far
    # more than the raw per-frame count.
    from collections import Counter
    loc_counts = Counter((v[4], v[7]) for v in violations)
    print(f"\nDistinct violating (pc_prev -> pc_cur) location pairs: {len(loc_counts)}")
    for (pc_prev, pc_cur), n in loc_counts.most_common(40):
        sample = next(v for v in violations if v[4] == pc_prev and v[7] == pc_cur)
        f_cur, gap, port_prev, dir_prev, _, port_cur, dir_cur, _ = sample
        print(f"  {owner(pc_prev):30s} @{pc_prev:04X} ({dir_prev} {port_prev:02X}h) -> "
              f"{owner(pc_cur):30s} @{pc_cur:04X} ({dir_cur} {port_cur:02X}h)  "
              f"gap={gap}T  hits={n}  (e.g. frame {f_cur})")


if __name__ == '__main__':
    main()
