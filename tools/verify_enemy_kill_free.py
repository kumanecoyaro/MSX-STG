"""Stage1: (2026-09-24、"倒したら消すように変更して ... 倒されたら枠自体消去だ") 上下2パーツの敵
(シンプル=SPAWN_SIMPLE、ウェーブ=TYPE_ENEMY1_LOOK)は、以前は上下とも倒しても枠が残り、見えないまま
左端まで飛び続けていた。2つ目のパーツを倒した瞬間に枠ごと消える(スプライトを隠し、スプライト番号・
絵の枠・敵の枠を解放)ことを、実際の当たり判定(CHECK_BULLET_VS_ENEMY_POOL)で確かめる。"""
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
def call(z, name, b=None, c=None, ix=None):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0)
    if b is not None: z.b, z.c = b, c
    if ix is not None: z.ix = ix
    z.pc = sym[name]
    for _ in range(3000000):
        if z.pc == 0: return z.a
        z.step()
    raise RuntimeError('stuck')
E = sym['ENEMY_POOL']; SU = sym['SPRITE_USED']; PU = sym['SIMPLE_PATTERN_USED']
def score(z): return z.rd(sym['SCORE']) | z.rd(sym['SCORE'] + 1) << 8
def make(kind):
    z = Z80(bytearray(mem))
    z.pc = sym['INIT']
    for _ in range(3000000):
        if z.pc == sym['MAINLOOP']: break
        z.step()
    if kind == 'simple':
        z.wr(sym['SPAWN_E1_Y'], 60); call(z, 'ENEMY1_CLAIM_ANY')
    else:
        z.wr(sym['E4_SPAWN_TYPE'], sym['TYPE_ENEMY1_LOOK']); z.wr(sym['E4_SPAWN_BASEY'], 60); call(z, 'ENEMY4_CLAIM_ANY')
    z.wr(E + sym['E_X'], 120)
    return z
for kind in ('simple', 'wave'):
    z = make(kind)
    spr = z.rd(E + sym['E_SPRNUM']); pat = z.rd(E + sym['E_PARAM3'])
    check(f"{kind}: spawned with both parts, its sprite number {spr} and pattern slot {pat} claimed",
          z.rd(E + sym['E_ACTIVE']) == 1 and z.rd(E + sym['E_TOP']) == 1 and z.rd(E + sym['E_BOT']) == 1
          and z.rd(SU + spr) == 1 and z.rd(PU + pat) != 0)
    hits = []
    s0 = score(z)
    for row in range(2, 22):
        for col in range(10, 20):
            if z.rd(E + sym['E_ACTIVE']) == 0: break
            before = (z.rd(E + sym['E_TOP']), z.rd(E + sym['E_BOT']))
            r = call(z, 'CHECK_BULLET_VS_ENEMY_POOL', b=col, c=row)
            if r == 1: hits.append((col, row, before))
    check(f"{kind}: the second part's hit frees the slot on the spot (hits {hits})",
          len(hits) == 2 and z.rd(E + sym['E_ACTIVE']) == 0)
    check(f"{kind}: its sprite number and pattern slot are released, sprite hidden (Y={z.vram[0x1B00 + spr * 4]})",
          z.rd(SU + spr) == 0 and z.rd(PU + pat) == 0 and z.vram[0x1B00 + spr * 4] == sym['ENEMY_HIDE_Y'])
    check(f"{kind}: both hits still score ({s0} -> {score(z)})", score(z) > s0)

# ジグザグ編隊(E2 A/B): 3機とも倒したら編隊ごと終わる(スプライト番号4つ解放、ACTIVE=0で次の出現を待たせない)
for f in 'AB':
    for label, parts, want_active in (("all three units destroyed", [0] * 6, 0),
                                      ("one bottom part still left", [0, 0, 0, 0, 0, 1], 1)):
        z = make('simple')
        z.wr(sym[f'E2{f}_ACTIVE'], 1); z.wr(sym[f'E2{f}_SEQ_STATE'], 6)
        nums = []
        for u in range(3):
            n = 20 + u; z.wr(sym[f'E2{f}_U{u}_SPRNUM'], n); z.wr(SU + n, 1); nums.append(n)
            z.wr(sym[f'E2{f}_U{u}_STATE'], 1)
            z.wr(sym[f'E2{f}_U{u}_TOP'], parts[u * 2]); z.wr(sym[f'E2{f}_U{u}_BOT'], parts[u * 2 + 1])
        z.wr(sym[f'E2{f}_TEMP_SPRNUM'], 23); z.wr(SU + 23, 1); nums.append(23)
        call(z, f'ENEMY_COMPLEX_STEP_{f}')
        freed = all(z.rd(SU + n) == 0 for n in nums)
        check(f"E2{f} {label}: formation active={z.rd(sym[f'E2{f}_ACTIVE'])} (want {want_active}), sprite numbers "
              f"freed={freed}", z.rd(sym[f'E2{f}_ACTIVE']) == want_active and freed == (want_active == 0))
z = make('simple')
z.wr(sym['E2A_ACTIVE'], 1); z.wr(sym['E2A_SEQ_STATE'], 0)
for u in range(3):
    z.wr(sym[f'E2A_U{u}_STATE'], 0); z.wr(sym[f'E2A_U{u}_TOP'], 1); z.wr(sym[f'E2A_U{u}_BOT'], 1)
call(z, 'ENEMY_COMPLEX_STEP_A')
check("E2A just spawned (units not arrived yet, all parts intact) is NOT ended", z.rd(sym['E2A_ACTIVE']) == 1)
print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
