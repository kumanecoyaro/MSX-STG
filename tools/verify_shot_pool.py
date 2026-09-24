"""Stage1: 自機ショットのスロット化(2026-09-24、"まず5発目標で")の検証。

旧コードは弾3発ぶんの処理(発射・移動/消去・当たり判定・ポッド判定・ボス出現中の
はじき・空の復元スタブ)を丸ごと3つ複製していた。これをBULLETC_*(作業用コピー)に
対する1本の処理+BULLET_EACH(全スロットを回す)へまとめ、BULLET_SLOTS=5にした。
BULLET_SLOTS=3にした版が旧コードと1万フレーム(道中)+4000フレーム(ボス出現〜
ポッド全滅)で画面・スコア・ポッドHP・DFLまで完全一致することは作業時に確認済み
(HANDOFF.md follow-up33)。ここでは5発での振る舞いを実際のMAINLOOPで確かめる。
"""
import sys, os, json, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'bgm_data'))
from mini_z80asm import Assembler
from z80emu import Z80
import patch_ebuz2_mk2 as pe
text = open(os.path.join(HERE, '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
asm = Assembler(text); out = asm.assemble(); sym = asm.symtab
mem0 = bytearray(65536)
for a, v in out.items(): mem0[a & 0xFFFF] = v & 0xFF
bank = open(os.path.join(HERE, 'bgm_data', 'bgm_bank.bin'), 'rb').read()
lay = json.load(open(os.path.join(HERE, 'bgm_data', 'bgm_layout.json')))
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def run_until(z, pc, n=3000000):
    for _ in range(n):
        if z.pc == pc: return
        z.step()
    raise RuntimeError(hex(z.pc))
def call(z, name):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.pc = sym[name]; run_until(z, 0)
def frame(z, fire=False):
    z.wr(sym['BARRIER_HP'], 5); z.sim_trig_a = fire
    z.pc = sym['MAINLOOP']; z.step(); run_until(z, sym['MAINLOOP'])
N = sym['BULLET_SLOTS']; P = sym['BULLET_POOL']
def acts(z): return [z.rd(P + i * 6) for i in range(N)]
def boot(poison=False):
    z = Z80(bytearray(mem0))
    if poison:
        for i in range(N * 6): z.wr(P + i, 0xAA)
    off = lay['EBUZ2_MK2_CHARDATA']['bank_offset']
    for i in range(lay['EBUZ2_MK2_CHARDATA']['len']): z.wr(sym['EBUZ2_BLANK5'] + i, bank[off + i])
    for name, data in zip(('EBUZ2_SCRIPT_TABLE', 'EBUZ2_ALTLOOP_TABLE', 'EBUZ2_STOPSEQ_TABLE'), pe.build_tables(sym)):
        for i, b in enumerate(data): z.wr(sym[name] + i, b)
    z.pc = sym['INIT']; run_until(z, sym['MAINLOOP'])
    z.wr(sym['GAMEOVER_ENABLED'], 0); z.wr(sym['SHIP_ENTRY_ACT'], 0)
    return z

check(f"BULLET_SLOTS = 5 ({N}), pool in the old ENEMY_POOL leftover area, old names are aliases of slots 0-2",
      N == 5 and sym['BULLET0_ACT'] == P and sym['BULLET1_ACT'] == P + 6 and sym['BULLET2_ACT'] == P + 12
      and P >= 0xE8ED and P + N * 6 + 11 <= 0xEACC)
z2 = boot(poison=True)
check("INIT clears every slot of the pool (pool poisoned with AAh before INIT)", all(z2.rd(P + i * 6) == 0 for i in range(N)))

z = boot()
for _ in range(20): frame(z)
prev = acts(z); spawns = []
for f in range(70):
    frame(z, True); cur = acts(z)
    if any(c and not p for c, p in zip(cur, prev)): spawns.append(f)
    prev = cur
check(f"fire held: a new shot every 2 frames until all {N} slots are busy, then a pause until the first one leaves "
      f"(spawn frames {spawns})", spawns[:N] == [0, 2, 4, 6, 8][:N] and spawns[N] > 20 and spawns[N:N + N] ==
      list(range(spawns[N], spawns[N] + 2 * N, 2)))

z = boot()
for _ in range(20): frame(z)
z.wr(sym['PLAYERY'], 64); z.wr(sym['PLAYERX'], 16)
for f in range(9): frame(z, True)
cols = [z.rd(P + i * 6 + 3) for i in range(N)]
row = z.rd(P + 4); pat = z.rd(P + 5)
drawn = [z.vram[0x1800 + row * 32 + c] for c in cols]
check(f"all {N} shots in flight on the ship's row at different columns {cols}, each drawn as its shot tile",
      all(acts(z)) and len(set(cols)) == N and all(d == pat for d in drawn))
frame(z)
cols2 = [z.rd(P + i * 6 + 3) for i in range(N)]
check("each shot advances one cell per frame and the cell it left is blanked",
      cols2 == [c + 1 for c in cols] and all(z.vram[0x1800 + row * 32 + c] == sym['BLANKCODE']
                                             for c in cols if c not in cols2))

# ボス出現中(BOSS_STATE=1)のはじき: スロット3/4はDFL0/1を使う
z = boot()
call(z, 'BOSS_SPAWN')
z.wr(sym['BOSS_STATE'], 1)
for i in range(3): z.wr(sym[f'DFL{i}_ACT'], 0)
for i in (3, 4):
    base = P + i * 6
    z.wr(base, 1); z.wr(base + 3, 25); z.wr(base + 4, 5 + i)
    z.wr(base + 1, (0x1800 + (5 + i) * 32) & 255); z.wr(base + 2, (0x1800 + (5 + i) * 32) >> 8)
call(z, 'BOSS_GUARD_UPDATE')
check("boss materializing: shots in slots 3/4 reaching col25 are deflected into DFL0/DFL1 (slot-3 mapping) and "
      "deactivated", acts(z)[3:] == [0, 0] and z.rd(sym['DFL0_ACT']) == 1 and z.rd(sym['DFL1_ACT']) == 1
      and z.rd(sym['DFL0_Y']) == 8 * 8 and z.rd(sym['DFL1_Y']) == 9 * 8)

print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
