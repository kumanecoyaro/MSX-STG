"""Stage1 ボス専用レーザー+レーザー干渉+エナジーゲージ(2026-09-23)の検証。

仕様(ユーザー指示): ボス専用 / Bボタン単発撃ちは完全に置き換え / チャージは
スコア連動(1000点=1px、50px=5万点で満タン) / ゲージは行0中央 / レーザーは
ボスで1回のみ / 連打で負ければゲームオーバー / 1秒8回以上で押し返せる /
エナジーは満タンなら使用可 / ボスレーザー前に使うとポッドは壊せるが100フレで
ゲージが尽きて消え、ボスレーザーで割り込めずゲームオーバー / 発射前でも
100フレ以内ならそのまま干渉へ / ボス発射後は上下から割り込める / 干渉時は
自機をレーザー行へ固定。実際のMAINLOOPを1フレームずつ回して確認する。
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'bgm_data'))
from mini_z80asm import Assembler
from z80emu import Z80
import patch_ebuz2_mk2 as pe
text = open(os.path.join(HERE, '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
asm = Assembler(text); out = asm.assemble(); sym = asm.symtab
mem0 = bytearray(65536)
for a, v in out.items():
    mem0[a & 0xFFFF] = v & 0xFF
bank = open(os.path.join(HERE, 'bgm_data', 'bgm_bank.bin'), 'rb').read()
lay = json.load(open(os.path.join(HERE, 'bgm_data', 'bgm_layout.json')))
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def run_until_pc(z, pc, n=3000000):
    for _ in range(n):
        if z.pc == pc: return
        z.step()
    raise RuntimeError(hex(z.pc))
def call(z, name, b=None):
    if b is not None: z.b = b
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.pc = sym[name]; run_until_pc(z, 0)
def frame(z, trig_b=False):
    z.sim_trig_b = trig_b
    z.pc = sym['MAINLOOP']; z.step(); run_until_pc(z, sym['MAINLOOP'])
def rd16(z, a): return z.rd(a) | z.rd(a + 1) << 8
def set_score(z, v):
    z.wr(sym['SCORE'], v & 255); z.wr(sym['SCORE'] + 1, (v >> 8) & 255); z.wr(sym['SCORE'] + 2, v >> 16)
def score(z): return rd16(z, sym['SCORE']) | z.rd(sym['SCORE'] + 2) << 16

PH, ROW = sym['LZ_PHASE'], sym['LZ_ROW']
PL, SP, BL, BLANK = sym['LZ_PL_CODE'], sym['LZ_SPARK_CODE'], sym['LZ_BL_CODE'], sym['BLANKCODE']
def cells(z, row, c0=0, c1=26): return [z.vram[0x1800 + row * 32 + c] for c in range(c0, c1)]

_landed = None
def landed():
    """INIT→ボス出現→着地(BOSS_STATE=2)まで実際に進めた状態(1回だけ作ってコピー)"""
    global _landed
    if _landed is None:
        z = Z80(bytearray(mem0))
        off = lay['EBUZ2_MK2_CHARDATA']['bank_offset']
        for i in range(lay['EBUZ2_MK2_CHARDATA']['len']):
            z.wr(sym['EBUZ2_BLANK5'] + i, bank[off + i])
        for name, data in zip(('EBUZ2_SCRIPT_TABLE', 'EBUZ2_ALTLOOP_TABLE', 'EBUZ2_STOPSEQ_TABLE'), pe.build_tables(sym)):
            for i, b in enumerate(data): z.wr(sym[name] + i, b)
        z.pc = sym['INIT']; run_until_pc(z, sym['MAINLOOP']); z.wr(sym['SHIP_ENTRY_ACT'], 0)
        call(z, 'BOSS_SPAWN')
        for _ in range(4000):
            frame(z)
            if z.rd(sym['BOSS_STATE']) == 2: break
        assert z.rd(sym['BOSS_STATE']) == 2
        _landed = z
    import copy
    z = copy.deepcopy(_landed)
    z.wr(sym['BARRIER_HP'], 99); z.wr(sym['GAMEOVER_ENABLED'], 1)
    return z
def kill_all_pods(z):
    for i in range(8):
        if z.rd(sym['POD_HP'] + i):
            z.wr(sym['POD_HP'] + i, 1); call(z, 'POD_HIT', b=i)

# ---------------------------------------------------------------- ゲージ
def gauge_model(g):
    t = g - 1
    names = ['E' if t >= 0 else '.']
    for i in range(7):
        f = t - 8 * i
        names.append('.' if f <= 0 else ('F' if f >= 8 else 'P'))
    k = t & 7
    return ''.join(names), (0xFF ^ (0xFF >> k)) if any(n == 'P' for n in names) else None
def gauge_screen(z):
    m = {sym['GAUGE_BLANK_CODE']: '.', sym['GAUGE_EDGE_CODE']: 'E', sym['GAUGE_FULL_CODE']: 'F', sym['GAUGE_PART_CODE']: 'P'}
    return ''.join(m.get(z.vram[0x1800 + c], '?') for c in range(12, 20))
z = landed()
bad = []
for sc in (0, 9, 10, 15, 25, 79, 80, 81, 170, 250, 489, 490, 499, 500, 777, 0x10000):
    set_score(z, sc); frame(z)
    g = min(sc // 10, 50)
    want, part = gauge_model(g)
    got = gauge_screen(z)
    pat = z.vram[sym['GAUGE_PART_CODE'] * 8 + 3]
    if got != want or (part is not None and pat != part) or z.rd(sym['GAUGE_SHOWN']) != g:
        bad.append((sc, g, want, got, hex(pat)))
check(f"gauge: row0 cols12-19 = 50px bar at px103-152, 1px per 1000 points, full at 50000 (and above) {bad}", not bad)
# 1px単位で左端から伸びること(実ピクセル)
def gauge_pixels(z):
    px = []
    for c in range(12, 20):
        code = z.vram[0x1800 + c]; row = z.vram[code * 8 + 3]
        px += [(row >> (7 - b)) & 1 for b in range(8)]
    return px
bad = []
for g in range(51):
    set_score(z, g * 10); frame(z)
    p = gauge_pixels(z)
    lit = [i + 96 for i, v in enumerate(p) if v]
    if lit != list(range(103, 103 + g)): bad.append(g)
check(f"gauge: exactly g pixels lit from x=103 (centre 128 minus 25) for every g=0..50 {bad[:5]}", not bad)

# ---------------------------------------------------------------- B単発撃ちの削除
z = landed(); set_score(z, 0)
z.wr(sym['BOSS_STATE'], 0)
for f in range(6):
    frame(z, trig_b=(f % 2 == 0))
check("B button outside the boss no longer fires a normal shot (single-shot removed)",
      not any(z.rd(sym[f'BULLET{i}_ACT']) for i in range(3)) and z.rd(PH) == 0)
z = landed(); set_score(z, 100)
frame(z, trig_b=True)
check("B with the gauge not full does nothing during the boss either", z.rd(PH) == 0 and z.rd(sym['LZ_SPENT']) == 0)

# ---------------------------------------------------------------- 正規ルート: 勝ち
def to_extend(z, sc=600):
    set_score(z, sc); frame(z)
    kill_all_pods(z)
    return z.rd(PH)
z = landed()
check("last pod destroyed -> boss does NOT explode at once, boss laser starts (phase 2)",
      to_extend(z) == 2 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0)
z.wr(sym['PLAYERY'], 120)                                # 別の行で待つ
for _ in range(20): frame(z)
bf = z.rd(sym['LZ_BFRONT'])
check(f"boss laser grows left 1 cell / 4 frames from the boss's left edge (front col {bf}, cells BL)",
      bf == 21 and cells(z, ROW, bf, 26) == [BL] * (26 - bf) and cells(z, ROW, 0, bf) == [BLANK] * bf)
sc0 = score(z)
frame(z, trig_b=True); frame(z)                          # 上下から割り込み(押下は次フレームで処理)
pcol = z.rd(sym['LZ_PCOL'])
cx = z.rd(sym['LZ_CLASH_X']); c = cx >> 3
check(f"B while the boss laser is growing -> clash (phase 3), ship snapped to the laser row (PLAYERY 64), "
      f"beams meet halfway (clash col {c})",
      z.rd(PH) == 3 and z.rd(sym['PLAYERY']) == 64 and (z.rd(sym['PLAYERY']) + 8) >> 3 == ROW and pcol < c < 25)
check("clash drawn: player beam up to the clash col, spark at it, boss beam beyond",
      cells(z, ROW, pcol, 26) == [PL] * (c - pcol) + [SP] + [BL] * (25 - c))
check("gauge stays full during the clash (use does not drain it)", z.rd(sym['GAUGE_SHOWN']) == 50)
x0 = z.rd(sym['PLAYERX'])
z.sim_dir = 7                                            # 左を入れても動かない
frame(z); z.sim_dir = 0
check("ship is frozen during the clash (stick ignored)", z.rd(sym['PLAYERX']) == x0 and z.rd(sym['PLAYERY']) == 64)
z.sim_trig_a = True; frame(z); z.sim_trig_a = False
check("A shots are blocked during the clash (they would overwrite the laser row)",
      not any(z.rd(sym[f'BULLET{i}_ACT']) for i in range(3)))
def mash(z, every, frames=3000):
    for f in range(frames):
        frame(z, trig_b=(f % every == 0))
        if z.rd(PH) != 3: return f
    return None
f = mash(z, 6)                                           # 10回/秒
check(f"mashing 10 presses/s pushes the boss back and wins (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 1 and z.rd(sym['GAME_OVER']) == 0)
check("win -> the normal boss death sequence (+10000 points = 100 units)", score(z) - sc0 == 100)
check("win -> the whole laser row is erased", cells(z, ROW, 0, 26) == [BLANK] * 26)

# ---------------------------------------------------------------- 連打不足で負け
z = landed(); to_extend(z)
frame(z, trig_b=True); frame(z)
f = mash(z, 9)                                           # 6.7回/秒
check(f"mashing 6.7 presses/s loses -> game over even with barrier left (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0)
check("lose -> laser row erased", cells(z, ROW, 0, 26) == [BLANK] * 26)
z2 = landed(); to_extend(z2); frame(z2, trig_b=True); frame(z2)
# ちょうど8回/秒(7,8フレーム交互 = 7.5フレーム間隔)
fr = 0; nxt = 0; hits = 0
while z2.rd(PH) == 3 and fr < 3000:
    p = fr >= nxt
    if p: nxt += 7 if hits % 2 == 0 else 8; hits += 1
    frame(z2, trig_b=p); fr += 1
check(f"exactly 8 presses/s (7/8-frame alternation) still wins ({fr} frames)", z2.rd(PH) == 4 and z2.rd(sym['GAME_OVER']) == 0)
z = landed(); to_extend(z); frame(z, trig_b=True); frame(z); z.wr(sym['GAMEOVER_ENABLED'], 0)
mash(z, 1000)
check("GAMEOVER_ENABLED=0 (title B test mode): a lost clash does not kill, goes on to the boss death so play can continue",
      z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 0 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 1)

# ---------------------------------------------------------------- 割り込まない
z = landed(); to_extend(z); z.wr(sym['PLAYERY'], 120)
n = 0
while z.rd(PH) == 2 and n < 300: frame(z); n += 1
check(f"never cutting in: boss laser reaches the left edge -> game over ({n} frames)",
      z.rd(sym['GAME_OVER']) == 1 and 100 <= n <= 110)
z = landed(); to_extend(z); z.wr(sym['PLAYERX'], 120); z.wr(sym['PLAYERY'], 64)
n = 0
while z.rd(PH) == 2 and n < 300: frame(z); n += 1
check(f"standing in the laser row: hit when the growing laser reaches the ship ({n} frames, front col {z.rd(sym['LZ_BFRONT'])})",
      z.rd(sym['GAME_OVER']) == 1 and n < 60)
z = landed(); to_extend(z, sc=499); z.wr(sym['PLAYERY'], 120)
for f in range(30): frame(z, trig_b=(f % 3 == 0))
check("gauge short of 50000 at the boss laser: B cannot cut in", z.rd(PH) == 2 and z.rd(sym['LZ_SPENT']) == 0)

# ---------------------------------------------------------------- 早撃ち(失敗レーザー)
z = landed(); set_score(z, 600); z.wr(sym['PLAYERY'], 150); frame(z)   # row19: ポッドの軌道外
frame(z, trig_b=True); frame(z)
prow = (150 + 8) >> 3; pcol = z.rd(sym['LZ_PCOL'])
check(f"B with the gauge full before the boss laser: player laser fires on the ship's row {prow} to the right edge (phase 1)",
      z.rd(PH) == 1 and z.rd(sym['LZ_PROW']) == prow and cells(z, prow, pcol, 32) == [PL] * (32 - pcol))
gs = [z.rd(sym['GAUGE_SHOWN'])]
n = 1
while z.rd(PH) == 1 and n < 200:
    frame(z); gs.append(z.rd(sym['GAUGE_SHOWN'])); n += 1
check(f"premature laser lasts 100 frames ({n - 1}) while the gauge drains 50->0 ({gs[0]},{gs[50]},{gs[-2]})",
      n - 1 == 100 and gs[0] == 50 and gs[-2] <= 1 and all(a >= b for a, b in zip(gs, gs[1:])))
frame(z)
check("after 100 frames the laser is gone, phase back to 0, marked used, gauge 0",
      z.rd(PH) == 0 and z.rd(sym['LZ_SPENT']) == 1 and cells(z, prow, 0, 32) == [BLANK] * 32
      and z.rd(sym['GAUGE_SHOWN']) == 0)
frame(z, trig_b=True); frame(z)
check("used laser cannot be fired again", z.rd(PH) == 0)
kill_all_pods(z)
for f in range(40): frame(z, trig_b=(f % 3 == 0))
check("used before the boss laser: B cannot cut in", z.rd(PH) == 2)
while z.rd(PH) == 2: frame(z)
check("... and the boss laser kills the player (game over)", z.rd(sym['GAME_OVER']) == 1)

# ボスの行(2-17)ではボス左端(列26)で止まる
z = landed(); set_score(z, 600); z.wr(sym['PLAYERY'], 120); frame(z)
frame(z, trig_b=True); frame(z)
check("premature laser on a boss row stops at the boss's left edge (cols up to 25; the boss body is untouched)",
      z.rd(sym['LZ_PEND']) == 26 and cells(z, 16, z.rd(sym['LZ_PCOL']), 26) == [PL] * (26 - z.rd(sym['LZ_PCOL']))
      and all(c != PL for c in cells(z, 16, 26, 32)))
# 早撃ちレーザーでポッドを破壊できる
z = landed(); set_score(z, 600); frame(z)
z.wr(sym['PLAYERX'], 40); z.wr(sym['PLAYERY'], 64)
hp0 = [z.rd(sym['POD_HP'] + i) for i in range(8)]
frame(z, trig_b=True); frame(z)
for f in range(60):
    frame(z)
    if z.rd(PH) != 1: break
hp1 = [z.rd(sym['POD_HP'] + i) for i in range(8)]
check(f"the premature laser destroys pods it crosses ({hp0} -> {hp1})", sum(hp1) < sum(hp0) and hp1.count(0) > hp0.count(0))

# 早撃ちの100フレ以内にボスが撃つ → そのまま干渉
z = landed(); set_score(z, 600); z.wr(sym['PLAYERY'], 150); frame(z)
frame(z, trig_b=True); frame(z)
for _ in range(30): frame(z)
t = z.rd(sym['LZ_TIMER'])
kill_all_pods(z)
check(f"boss fires within the premature laser's 100 frames -> straight into the clash, ship moved to the laser row",
      z.rd(PH) == 3 and z.rd(sym['PLAYERY']) == 64)
frame(z)
check(f"old row {prow} laser erased; gauge frozen at the remaining energy ({z.rd(sym['GAUGE_SHOWN'])} = {t}/2)",
      cells(z, prow, 0, 32) == [BLANK] * 32 and z.rd(sym['GAUGE_SHOWN']) == t // 2)
mash(z, 6)
check("... and can still be won by mashing", z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 0)

# 干渉中に何かがレーザー行を上書きしても次フレームで戻る
z = landed(); to_extend(z); frame(z, trig_b=True); frame(z)
pcol = z.rd(sym['LZ_PCOL'])
z.vram[0x1800 + ROW * 32 + pcol] = BLANK
frame(z)
check("laser row is redrawn every frame (a hole left by something else heals next frame)",
      z.vram[0x1800 + ROW * 32 + pcol] == PL)

# ---------------------------------------------------------------- バリア必須(2026-09-23)
z = landed(); z.wr(sym['BARRIER_HP'], 0); set_score(z, 600); z.wr(sym['PLAYERY'], 150); frame(z)
frame(z, trig_b=True); frame(z)
check("no barrier left: B cannot fire the laser even with a full gauge (before the boss laser)", z.rd(PH) == 0)
z = landed(); to_extend(z); z.wr(sym['BARRIER_HP'], 0); z.wr(sym['PLAYERY'], 120)
frame(z, trig_b=True); frame(z)
check("no barrier left: B cannot cut into the boss laser either", z.rd(PH) == 2)

# ---------------------------------------------------------------- 条件未達のゲームオーバー分岐(2026-09-23)
def die_to_boss_laser(z):
    n = 0
    while z.rd(PH) == 2 and n < 300: frame(z); n += 1
    reason = z.rd(sym['LZ_FAIL_REASON'])
    n = 0
    while z.rd(sym['GAME_OVER_SEQ']) == 0 and n < 600: frame(z); n += 1   # 爆発しながら落下→完了
    return reason
for label, setup, want in (
        ("no barrier", lambda z: z.wr(sym['BARRIER_HP'], 0), 1),
        ("gauge short of 50000", lambda z: set_score(z, 499), 2),
        ("laser already used", lambda z: z.wr(sym['LZ_SPENT'], 1), 2),
        ("no barrier and not enough energy", lambda z: (z.wr(sym['BARRIER_HP'], 0), set_score(z, 100)), 3)):
    z = landed(); set_score(z, 600); frame(z); kill_all_pods(z)
    setup(z); z.wr(sym['PLAYERY'], 150)
    r = die_to_boss_laser(z)
    check(f"boss laser reaches an unqualified player ({label}): reason {r} (want {want}), after the death fall "
          f"GAME_OVER_SEQ=4 (Comb switches to the bank7 reason screen), no jingle/normal text",
          r == want and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['GAME_OVER_SEQ']) == 4)
    frame(z); frame(z)
    check(f"({label}) SEQ=4 stays put in the plain build (UPDATE_GAME_OVER_SEQUENCE ignores it)",
          z.rd(sym['GAME_OVER_SEQ']) == 4)
z = landed(); set_score(z, 600); frame(z); kill_all_pods(z); z.wr(sym['PLAYERY'], 150)
r = die_to_boss_laser(z)
check("qualified player who just never cut in: reason 0 -> normal MISSION FAILED (GAME_OVER_SEQ 1)",
      r == 0 and z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); to_extend(z); frame(z, trig_b=True); frame(z); mash(z, 1000)
n = 0
while z.rd(sym['GAME_OVER_SEQ']) == 0 and n < 600: frame(z); n += 1
check("losing the clash itself: reason 0 -> normal MISSION FAILED",
      z.rd(sym['LZ_FAIL_REASON']) == 0 and z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); z.wr(sym['LZ_FAIL_REASON'], 3); call(z, 'LZ_INIT')
check("LZ_INIT clears LZ_FAIL_REASON (restart after a reason game over)", z.rd(sym['LZ_FAIL_REASON']) == 0)

print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
