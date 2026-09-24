"""Stage1: (2026-09-24、"EbuzとEbuzIIの耐久値を倍に") Ebuz 24→48、EbuzII 128→256。
EbuzIIのHPは1byteのままなので初期値0で256を表す(被弾ごとにDEC、0で撃破)。
実際の被弾処理(CHECK_BULLET_VS_EBUZ2)を何発目で撃破になるか数えて確かめる。
Ebuzの48発はverify_ebuz_integration.pyがEBUZ_HP_INIT発数で撃破を確かめている。"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from z80emu import Z80
a = Assembler(open(os.path.join(HERE, '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read())
out = a.assemble(); sym = a.symtab
mem = bytearray(65536)
for k, v in out.items(): mem[k & 0xFFFF] = v & 0xFF
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def call(z, name, b, c):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.b, z.c = b, c; z.pc = sym[name]
    for _ in range(3000000):
        if z.pc == 0: return z.a
        z.step()
    raise RuntimeError('stuck')
check(f"EBUZ_HP_INIT = 48 ({sym['EBUZ_HP_INIT']})", sym['EBUZ_HP_INIT'] == 48)
z = Z80(bytearray(mem))
z.wr(sym['EBUZ2_ACT'], 1); z.wr(sym['EBUZ2_PHASE'], 1); z.wr(sym['EBUZ2_ROW_CUR'], 5)
z.wr(sym['EBUZ2_HP'], sym['EBUZ2_HP_INIT'])
n = 0
while z.rd(sym['EBUZ2_PHASE']) != 2 and n < 400:
    r = call(z, 'CHECK_BULLET_VS_EBUZ2', 24, 7); n += 1
    if r != 1: break
check(f"EbuzII is defeated by exactly the 256th hit (took {n})", n == 256 and z.rd(sym['EBUZ2_PHASE']) == 2)
print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
