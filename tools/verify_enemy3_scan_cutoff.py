"""Stage1 Enemy3走査の打ち切り(2026-09-23、監査): CHECK_BULLET_VS_ENEMY3/
ENEMY3_UPDATE_ALL/PDC_CHECK_ENEMY3は、生きている個体をENEMY3_ACTIVE_COUNT体
見つけた時点で走査を打ち切る。(1)最後尾スロットの個体も必ず処理されること、
(2)前方スロットだけに居る時は後方を調べず早く抜けること、を検証。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80
text = open(os.path.join(os.path.dirname(__file__), '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
asm = Assembler(text); out = asm.assemble(); sym = asm.symtab
mem0 = bytearray(65536)
for a, v in out.items():
    mem0[a & 0xFFFF] = v & 0xFF
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def run_until_pc(z, pc, n=500000):
    for _ in range(n):
        if z.pc == pc: return
        z.step()
    raise RuntimeError(hex(z.pc))
def call(z, name, **regs):
    for k, v in regs.items(): setattr(z, k, v)
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.pc = sym[name]
    t0 = z.tstates; run_until_pc(z, 0); return z.tstates - t0

POOL = sym["ENEMY3_POOL"]; ST = sym["ENEMY3_STRUCT"]
LAST = sym["ENEMY3_WAVE_SLOTS"] * sym["ENEMY3_SLOTS"] - 1

def world(slots):
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]; run_until_pc(z, sym["MAINLOOP"], 5000000)
    for i in range(LAST + 1):
        z.wr(POOL + i * ST, 0)
    for i, (row, col) in slots.items():
        b = POOL + i * ST
        z.wr(b + 0, 1); z.wr(b + 1, 0); z.wr(b + 2, col * 8); z.wr(b + 3, row * 8)
        z.wr(b + 4, row); z.wr(b + 5, col); z.wr(b + 11, 0)
    z.wr(sym["ENEMY3_ACTIVE_COUNT"], len(slots))
    return z

# (1) 最後尾スロット(ウェーブ2の8体目)だけに居る個体: 弾が当たる/自機に当たる
z = world({LAST: (10, 12)})
call(z, "CHECK_BULLET_VS_ENEMY3", b=12, c=10)
check(f"bullet hits a unit that lives only in the last slot ({LAST})", z.a == 1)
z = world({LAST: (10, 12)})
z.wr(sym["PLAYERX"], 12 * 8); z.wr(sym["PLAYERY"], 10 * 8)
call(z, "PDC_CHECK_ENEMY3")
check("player-damage check still finds a unit in the last slot", z.a == 1)
# 前方にも居る場合(2体)、後方の個体にも当たる
z = world({0: (3, 3), LAST: (10, 12)})
call(z, "CHECK_BULLET_VS_ENEMY3", b=12, c=10)
check("with 2 units (slot0 + last slot) the last-slot unit is still hittable", z.a == 1)

# (2) 前方(スロット0)だけに居る時は後方の空スロットを調べず早く抜ける
z0 = world({0: (3, 3)}); t_front = call(z0, "CHECK_BULLET_VS_ENEMY3", b=20, c=20)
z1 = world({LAST: (3, 3)}); t_back = call(z1, "CHECK_BULLET_VS_ENEMY3", b=20, c=20)
check(f"a miss with the only unit in slot0 exits early ({t_front}T) vs last slot ({t_back}T)",
      t_front + 1000 < t_back)
z0 = world({0: (3, 3)}); t_front = call(z0, "PDC_CHECK_ENEMY3")
z1 = world({LAST: (3, 3)}); t_back = call(z1, "PDC_CHECK_ENEMY3")
check(f"PDC_CHECK_ENEMY3 exits early too ({t_front}T vs {t_back}T)", t_front + 1000 < t_back)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail); sys.exit(1)
