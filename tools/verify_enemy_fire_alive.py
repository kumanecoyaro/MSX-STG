"""Stage1: (2026-09-24、"結構な頻度でE1、E2で離れた位置から弾撃ってきたり、倒した後に撃ってる
場合がある")の修正の検証。
- E2(ジグザグ編隊): 旧コードは弾を常に1機目(U0)の位置から撃っていた → U0を倒した後も見えない
  位置から撃っていた。生きている最初の機から撃ち、全滅なら撃たない(E2_FIRE_FROM_ALIVE)。
- E1(Fighter=TYPE_ENEMY4): 1発目で墜落中(E_FLAGS!=0)も自機と同じ高さで撃っていた → 撃たない。
"""
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
def call(z, name, hl=None, ix=None):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0)
    if hl is not None: z.h, z.l = hl >> 8, hl & 255
    if ix is not None: z.ix = ix
    z.pc = sym[name]
    for _ in range(300000):
        if z.pc == 0: return
        z.step()
    raise RuntimeError('stuck')
POOL, NS, ST = sym['EBULLET_POOL'], sym['EBULLET_SLOTS'], 4
def bullets(z): return [(z.rd(POOL + i * ST + 1), z.rd(POOL + i * ST + 2)) for i in range(NS) if z.rd(POOL + i * ST)]

for f in ('A', 'B'):
    U0 = sym[f'E2{f}_U0_STATE']
    def setup(alive):
        z = Z80(bytearray(mem))
        for u in range(3):
            b = U0 + u * 5
            z.wr(b, 1); z.wr(b + 1, 100 + u * 20); z.wr(b + 2, 40 + u * 10)
            z.wr(b + 3, 1 if u in alive else 0); z.wr(b + 4, 0)
        return z
    z = setup({0, 1, 2}); call(z, 'E2_FIRE_FROM_ALIVE', hl=U0)
    check(f"E2{f}: all three alive -> fires from unit 0 as before {bullets(z)}", bullets(z) == [(100, 48)])
    z = setup({1, 2}); call(z, 'E2_FIRE_FROM_ALIVE', hl=U0)
    check(f"E2{f}: unit 0 destroyed -> fires from unit 1 (not from unit 0's empty spot) {bullets(z)}", bullets(z) == [(120, 58)])
    z = setup({2}); call(z, 'E2_FIRE_FROM_ALIVE', hl=U0)
    check(f"E2{f}: only unit 2 left -> fires from unit 2 {bullets(z)}", bullets(z) == [(140, 68)])
    z = setup(set()); call(z, 'E2_FIRE_FROM_ALIVE', hl=U0)
    check(f"E2{f}: whole formation destroyed -> no shot {bullets(z)}", bullets(z) == [])
    z = setup({0, 1, 2}); z.wr(U0 + 3, 0); z.wr(U0 + 4, 1); call(z, 'E2_FIRE_FROM_ALIVE', hl=U0)
    check(f"E2{f}: a unit with only its bottom half left still counts as alive {bullets(z)}", bullets(z) == [(100, 48)])
# 実際の発射箇所(ECS_S7_A/B)がE2_FIRE_FROM_ALIVEを使っていること
text = open(os.path.join(HERE, '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
check("ECS_S7_A/B fire through E2_FIRE_FROM_ALIVE (no more raw U0_X/U0_Y shots)",
      text.count("LD HL,E2A_U0_STATE : CALL E2_FIRE_FROM_ALIVE") == 1 and
      text.count("LD HL,E2B_U0_STATE : CALL E2_FIRE_FROM_ALIVE") == 1)

# E1(Fighter): 自機と同じ高さで撃つ。墜落中は撃たない。
E = sym['ENEMY_POOL']
def fighter(flags):
    z = Z80(bytearray(mem))
    z.wr(E + sym['E_ACTIVE'], 1); z.wr(E + sym['E_TYPE'], sym['TYPE_ENEMY4'])
    z.wr(E + sym['E_BEHAVIOR'], sym['BEHAVIOR_SIMPLE_DRIFT_DODGE'])
    z.wr(E + sym['E_X'], 200); z.wr(E + sym['E_Y'], 80); z.wr(E + sym['E_SPRNUM'], 9)
    z.wr(E + sym['E_PARAM3'], 0); z.wr(E + sym['E_FLAGS'], flags)
    z.wr(sym['PLAYERY'], 80); z.wr(sym['PLAYERX'], 20)
    call(z, 'EBSD_UPDATE', ix=E)
    return bullets(z)
b0 = fighter(0); b1 = fighter(1)
check(f"Fighter level with the player fires as before {b0}", len(b0) == 1)
check(f"Fighter already crashing (hit once, E_FLAGS=1) no longer fires even when level with the player {b1}", b1 == [])

# (2026-09-24、"ウェーブは?"): 上下2パーツの敵(ウェーブ/E1型)は残っているパーツから撃つ
def quad(top, bot, typ=None):
    z = Z80(bytearray(mem))
    z.wr(E + sym['E_TYPE'], typ if typ is not None else sym['TYPE_ENEMY1_LOOK'])
    z.wr(E + sym['E_TOP'], top); z.wr(E + sym['E_BOT'], bot)
    z.d, z.e = 100, 50
    call(z, 'FIRE_FROM_QUAD', ix=E)
    return bullets(z)
check(f"two-part enemy, both parts alive -> fires from the top-left part {quad(1, 1)}", quad(1, 1) == [(100, 58)])
check(f"only the bottom-right part left -> fires from it (+8,+8) {quad(0, 1)}", quad(0, 1) == [(108, 66)])
check(f"both parts destroyed (it keeps flying invisibly) -> no shot {quad(0, 0)}", quad(0, 0) == [])
check(f"Fighter (TYPE_ENEMY4, tracked by HP, E_TOP/E_BOT stay 0) still fires {quad(0, 0, sym['TYPE_ENEMY4'])}",
      quad(0, 0, sym['TYPE_ENEMY4']) == [(100, 58)])
check("Wave (EBSB) and the E1-type dodge shot both fire through FIRE_FROM_QUAD",
      text.count("CALL FIRE_FROM_QUAD") == 2)
# 実際のウェーブの発射処理で: 両パーツ撃破済みなら撃たない
def wave(top, bot):
    z = Z80(bytearray(mem))
    z.wr(E + sym['E_ACTIVE'], 1); z.wr(E + sym['E_TYPE'], sym['TYPE_ENEMY1_LOOK'])
    z.wr(E + sym['E_X'], sym['ENEMY_CENTER_X'] - 2); z.wr(E + sym['E_PARAM0'], 60); z.wr(E + sym['E_STATE'], 0)
    z.wr(E + sym['E_PARAM1'], 1); z.wr(E + sym['E_PARAM2'], 0); z.wr(E + sym['E_SPRNUM'], 9)
    z.wr(E + sym['E_TOP'], top); z.wr(E + sym['E_BOT'], bot)
    call(z, 'EBSB_UPDATE', ix=E)
    return bullets(z)
w11, w00 = wave(1, 1), wave(0, 0)
check(f"real Wave update crossing the centre as the chosen shooter: fires when alive {w11}, not when both parts are "
      f"already destroyed {w00}", len(w11) == 1 and w00 == [])

# (2026-09-24、"じゃあシンプルもチェック"): スケジュールのSPAWN_SIMPLE(ENEMY1_CLAIM_ANY、E_TYPE=0、
# 上下2パーツ)は画面中央を越えて回避を始める瞬間に撃つ(射手に選ばれた時だけ)。実際のEBSD_UPDATEで。
def simple(top, bot):
    z = Z80(bytearray(mem))
    z.wr(sym['E1_FIRE_COUNTDOWN'], 1)          # この回避を射手に選ばせる
    z.wr(E + sym['E_ACTIVE'], 1); z.wr(E + sym['E_TYPE'], 0)
    z.wr(E + sym['E_BEHAVIOR'], sym['BEHAVIOR_SIMPLE_DRIFT_DODGE'])
    z.wr(E + sym['E_X'], sym['ENEMY_CENTER_X'] + sym['ENEMY_SPEED'] - 1); z.wr(E + sym['E_Y'], 70)
    z.wr(E + sym['E_SPRNUM'], 9); z.wr(E + sym['E_PARAM0'], 0)
    z.wr(E + sym['E_TOP'], top); z.wr(E + sym['E_BOT'], bot)
    z.wr(sym['PLAYERY'], 150)
    call(z, 'EBSD_UPDATE', ix=E)
    return bullets(z), z.rd(E + sym['E_X'])
(s11, x), (s01, _), (s00, _) = simple(1, 1), simple(0, 1), simple(0, 0)
check(f"Simple enemy (SPAWN_SIMPLE) dodging at the centre as the chosen shooter: both parts alive -> fires from the "
      f"top-left part {s11}", s11 == [(x, 78)])
check(f"Simple enemy with only the bottom part left -> fires from it {s01}", s01 == [(x + 8, 86)])
check(f"Simple enemy with both parts destroyed (still flying invisibly) -> no shot {s00}", s00 == [])
print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
