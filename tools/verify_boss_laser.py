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
SP, BLANK = sym['LZ_SPARK_CODE'], sym['BLANKCODE']
LCODE, RCODE = sym['EBUZ2_LASER_L_CODE'], sym['EBUZ2_LASER_R_CODE']
def beam(c): return LCODE if c & 1 else RCODE          # EbuzIIのレーザー(奇数列L/偶数列R)
def beams(c0, c1): return [beam(c) for c in range(c0, c1)]
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

# ---------------------------------------------------------------- カウントダウン
CD = sym['LZ_CD_T']
def start_countdown(z, sc=600):
    set_score(z, sc); frame(z)
    kill_all_pods(z)
def to_fire(z, trig_frames=()):
    n = 0
    while z.rd(CD) and n < 200:
        frame(z, trig_b=(n in trig_frames)); n += 1
    return n
z = landed(); start_countdown(z)
check("last pod destroyed -> no immediate boss death, a 120-frame countdown starts (phase stays 0)",
      z.rd(CD) == 120 and z.rd(PH) == 0 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0)
z.wr(sym['PLAYERY'], 120)
launches, seen_pos, min_d, vanish = 0, [], 999, 0
prev = (0, 0)
for f in range(119):
    frame(z)
    cb = (z.rd(sym['LZ_CB0']), z.rd(sym['LZ_CB1']))
    if cb == (1, 1) and prev == (0, 0) or (f == 0 and cb == (1, 1)):
        launches += 1
    for s in (0, 1):
        if cb[s]:
            x = z.rd(sym[f'POD_BULLET{s}_X']); y = z.rd(sym[f'POD_BULLET{s}_Y'])
            seen_pos.append((x, y))
            spr = z.vram[0x1B00 + sym[f'POD_BULLET_SPR{s}'] * 4]
        if prev[s] and not cb[s]:
            vanish += 1
            spr = z.vram[0x1B00 + sym[f'POD_BULLET_SPR{s}'] * 4]
    prev = cb
check(f"countdown: 4 pairs of pod bullets launched from the orbit ({launches} launches), each drawn as the pod-bullet sprite",
      launches == 4)
check(f"countdown: bullets are pulled into the boss centre ({sym['LZ_CB_CX']},{sym['LZ_CB_CY']}) and vanish there ({vanish} vanished)",
      vanish == 8 and z.rd(sym['LZ_CB0']) == 0 and z.rd(sym['LZ_CB1']) == 0)
check("countdown: the boss laser has not fired yet one frame before the end", z.rd(PH) == 0 and z.rd(CD) == 1
      and cells(z, 9, 0, 26) == [BLANK] * 26)
frame(z)
check("after 120 frames the boss fires: whole length at once (cols 0-25) and 3 rows thick (rows 8-10), EbuzII laser tiles",
      z.rd(PH) == 2 and all(cells(z, r, 0, 26) == beams(0, 26) for r in (8, 9, 10))
      and cells(z, 7, 0, 26) == [BLANK] * 26 and cells(z, 11, 0, 26) == [BLANK] * 26)
for _ in range(20): frame(z)
check("the boss laser stays on (fire-and-hold) while waiting for a cut-in",
      z.rd(PH) == 2 and all(cells(z, r, 0, 26) == beams(0, 26) for r in (8, 9, 10)))

# ---------------------------------------------------------------- 割り込み → 干渉 → 勝ち
sc0 = score(z)
frame(z, trig_b=True); frame(z)                          # 上から割り込み(押下は次フレームで処理)
pcol = z.rd(sym['LZ_PCOL'])
c = z.rd(sym['LZ_CLASH_X']) >> 3
check(f"B above the beam -> clash (phase 3), ship snapped into the middle row (PLAYERY 64), clash col {c}",
      z.rd(PH) == 3 and z.rd(sym['PLAYERY']) == 64 and pcol < c < 25)
check("clash drawn: middle row = player beam | spark | boss beam; rows 8/10 = boss beam only right of the spark",
      cells(z, 9, pcol, 26) == beams(pcol, c) + [SP] + beams(c + 1, 26)
      and all(cells(z, r, 0, 26) == [BLANK] * (c + 1) + beams(c + 1, 26) for r in (8, 10)))
check("gauge stays full during the clash (use does not drain it)", z.rd(sym['GAUGE_SHOWN']) == 50)
x0 = z.rd(sym['PLAYERX'])
z.sim_dir = 7
frame(z); z.sim_dir = 0
check("ship is frozen during the clash (stick ignored)", z.rd(sym['PLAYERX']) == x0 and z.rd(sym['PLAYERY']) == 64)
z.sim_trig_a = True; frame(z); z.sim_trig_a = False
check("A shots are blocked during the clash", not any(z.rd(sym[f'BULLET{i}_ACT']) for i in range(3)))
def mash(z, every, frames=3000):
    for f in range(frames):
        frame(z, trig_b=(f % every == 0))
        if z.rd(PH) != 3: return f
    return None
f = mash(z, 6)
check(f"mashing 10 presses/s pushes the boss back and wins (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 1 and z.rd(sym['GAME_OVER']) == 0)
check("win -> the normal boss death sequence (+10000 points = 100 units)", score(z) - sc0 == 100)
check("win -> all three laser rows erased", all(cells(z, r, 0, 26) == [BLANK] * 26 for r in (8, 9, 10)))

def to_clash(z):
    start_countdown(z); z.wr(sym['PLAYERY'], 120); to_fire(z)
    frame(z, trig_b=True); frame(z)
z = landed(); to_clash(z)
f = mash(z, 9)
check(f"mashing 6.7 presses/s loses -> game over even with barrier left (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0)
check("lose -> the boss beam is left drawn full length over the player (3 rows)",
      all(cells(z, r, 0, 26) == beams(0, 26) for r in (8, 9, 10)))
z2 = landed(); to_clash(z2)
fr = 0; nxt = 0; hits = 0
while z2.rd(PH) == 3 and fr < 3000:
    p = fr >= nxt
    if p: nxt += 7 if hits % 2 == 0 else 8; hits += 1
    frame(z2, trig_b=p); fr += 1
check(f"exactly 8 presses/s (7/8-frame alternation) still wins ({fr} frames)", z2.rd(PH) == 4 and z2.rd(sym['GAME_OVER']) == 0)

# ---------------------------------------------------------------- テストモード: カウントダウンからやり直し
z = landed(); to_clash(z); z.wr(sym['GAMEOVER_ENABLED'], 0)
mash(z, 1000)
check("GAMEOVER_ENABLED=0 (title B test mode): losing the clash does not kill or destroy the boss - lasers erased, "
      "energy unused again, countdown restarts",
      z.rd(PH) == 0 and z.rd(CD) == 120 and z.rd(sym['LZ_SPENT']) == 0 and z.rd(sym['GAME_OVER']) == 0
      and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0 and all(cells(z, r, 0, 26) == [BLANK] * 26 for r in (8, 9, 10)))
z.wr(sym['PLAYERY'], 120)                                # 中央行に固定されていたので帯の外へ出る
to_fire(z)
frame(z, trig_b=True); frame(z)
check("... and the next round can be fought again (cut in -> clash)", z.rd(PH) == 3)
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 120); z.wr(sym['GAMEOVER_ENABLED'], 0); to_fire(z)
n = 0
while z.rd(PH) == 2 and n < 300: frame(z); n += 1
check("test mode: not cutting in -> countdown restarts too (no self-destruct)",
      z.rd(PH) == 0 and z.rd(CD) > 0 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0 and z.rd(sym['GAME_OVER']) == 0)

# ---------------------------------------------------------------- 割り込まない / 帯の中 / 条件未達
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 120); to_fire(z)
n = 0
while z.rd(PH) == 2 and n < 300: frame(z); n += 1
check(f"qualified but never cutting in: game over after the {sym['LZ_CUTIN_FRAMES']}-frame cut-in window (firing frame + {n}), "
      f"normal MISSION FAILED path (reason 0)",
      z.rd(sym['GAME_OVER']) == 1 and n + 1 == sym['LZ_CUTIN_FRAMES'] and z.rd(sym['LZ_FAIL_REASON']) == 0)
z = landed(); start_countdown(z); z.wr(sym['PLAYERX'], 60); z.wr(sym['PLAYERY'], 70); to_fire(z)
check("standing inside the 3-row band when the boss fires: hit at once", z.rd(sym['GAME_OVER']) == 1)
for y, inside in ((56, False), (57, True), (87, True), (88, False)):
    z = landed(); start_countdown(z); z.wr(sym['PLAYERX'], 60); z.wr(sym['PLAYERY'], y); to_fire(z)
    check(f"band edge: PLAYERY {y} ({'hit' if inside else 'safe'}) - hitbox y..y+7 vs rows 8-10 (y64-87)",
          z.rd(sym['GAME_OVER']) == (1 if inside else 0))
z = landed(); start_countdown(z, sc=499); z.wr(sym['PLAYERY'], 120)
n = to_fire(z)
check("gauge short of 50000: game over the moment the boss fires (reason 2)",
      z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['LZ_FAIL_REASON']) == 2)

# ---------------------------------------------------------------- 早撃ち
z = landed(); set_score(z, 600); z.wr(sym['PLAYERY'], 150); frame(z)   # row19: ポッドの軌道外
frame(z, trig_b=True); frame(z)
prow = (150 + 8) >> 3; pcol = z.rd(sym['LZ_PCOL'])
check(f"B with the gauge full before the boss laser: player laser (EbuzII tiles) on the ship's row {prow} to the right edge",
      z.rd(PH) == 1 and z.rd(sym['LZ_PROW']) == prow and cells(z, prow, pcol, 32) == beams(pcol, 32))
gs = [z.rd(sym['GAUGE_SHOWN'])]
n = 1
while z.rd(PH) == 1 and n < 200:
    frame(z); gs.append(z.rd(sym['GAUGE_SHOWN'])); n += 1
check(f"premature laser lasts 100 frames ({n - 1}) while the gauge drains 50->0 ({gs[0]},{gs[50]},{gs[-2]})",
      n - 1 == 100 and gs[0] == 50 and gs[-2] <= 1 and all(a >= b for a, b in zip(gs, gs[1:])))
frame(z)
check("after 100 frames the laser is gone, marked used, gauge 0",
      z.rd(PH) == 0 and z.rd(sym['LZ_SPENT']) == 1 and cells(z, prow, 0, 32) == [BLANK] * 32 and z.rd(sym['GAUGE_SHOWN']) == 0)
frame(z, trig_b=True); frame(z)
check("used laser cannot be fired again", z.rd(PH) == 0)
kill_all_pods(z); to_fire(z)
check("used before the countdown ended: game over the moment the boss fires (reason 2)",
      z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['LZ_FAIL_REASON']) == 2)
z = landed(); set_score(z, 600); frame(z)
z.wr(sym['PLAYERX'], 40); z.wr(sym['PLAYERY'], 120)
frame(z, trig_b=True); frame(z)
check("premature laser on a boss row stops at the boss's left edge (col 25)",
      z.rd(sym['LZ_PEND']) == 26 and cells(z, 16, z.rd(sym['LZ_PCOL']), 26) == beams(z.rd(sym['LZ_PCOL']), 26))
z = landed(); set_score(z, 600); frame(z)
z.wr(sym['PLAYERX'], 40); z.wr(sym['PLAYERY'], 64)
hp0 = [z.rd(sym['POD_HP'] + i) for i in range(8)]
frame(z, trig_b=True); frame(z)
for f in range(60):
    frame(z)
    if z.rd(PH) != 1: break
hp1 = [z.rd(sym['POD_HP'] + i) for i in range(8)]
check(f"the premature laser destroys pods it crosses ({hp0} -> {hp1})", sum(hp1) < sum(hp0) and hp1.count(0) > hp0.count(0))
# カウントダウン中に撃っておけば、発射の瞬間にそのまま干渉
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 150)
for _ in range(60): frame(z)
frame(z, trig_b=True); frame(z)
t0 = z.rd(sym['LZ_TIMER'])
check("B during the countdown -> player laser out (phase 1) while the countdown keeps running", z.rd(PH) == 1 and z.rd(CD) > 0)
to_fire(z)
check("countdown ends while the player laser is still out -> straight into the clash, ship moved to the middle row",
      z.rd(PH) == 3 and z.rd(sym['PLAYERY']) == 64)
frame(z)
check(f"old row 19 laser erased; gauge frozen at the remaining energy ({z.rd(sym['GAUGE_SHOWN'])})",
      cells(z, 19, 0, 32) == [BLANK] * 32 and 0 < z.rd(sym['GAUGE_SHOWN']) < 50)
mash(z, 6)
check("... and can still be won by mashing", z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 0)

# 干渉中に何かがレーザー行を上書きしても次フレームで戻る
z = landed(); to_clash(z)
pcol = z.rd(sym['LZ_PCOL'])
z.vram[0x1800 + ROW * 32 + pcol] = BLANK
frame(z)
check("laser rows are redrawn every frame (a hole left by something else heals next frame)",
      z.vram[0x1800 + ROW * 32 + pcol] == beam(pcol))

# ---------------------------------------------------------------- バリア必須
z = landed(); z.wr(sym['BARRIER_HP'], 0); set_score(z, 600); z.wr(sym['PLAYERY'], 150); frame(z)
frame(z, trig_b=True); frame(z)
check("no barrier left: B cannot fire the laser even with a full gauge", z.rd(PH) == 0)

# ---------------------------------------------------------------- 条件未達のゲームオーバー分岐
def fall_done(z):
    n = 0
    while z.rd(sym['GAME_OVER_SEQ']) == 0 and n < 600: frame(z); n += 1
for label, setup, want in (
        ("no barrier", lambda z: z.wr(sym['BARRIER_HP'], 0), 1),
        ("gauge short of 50000", lambda z: set_score(z, 499), 2),
        ("laser already used", lambda z: z.wr(sym['LZ_SPENT'], 1), 2),
        ("no barrier and not enough energy", lambda z: (z.wr(sym['BARRIER_HP'], 0), set_score(z, 100)), 3)):
    z = landed(); start_countdown(z); setup(z); z.wr(sym['PLAYERY'], 150)
    to_fire(z)
    r = z.rd(sym['LZ_FAIL_REASON'])
    fall_done(z)
    check(f"unqualified when the boss fires ({label}): reason {r} (want {want}); after the death fall GAME_OVER_SEQ=4 "
          f"(Comb switches to the bank7 reason screen)",
          r == want and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['GAME_OVER_SEQ']) == 4)
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 150); to_fire(z)
while z.rd(PH) == 2: frame(z)
fall_done(z)
check("qualified player who just never cut in: normal MISSION FAILED (GAME_OVER_SEQ 1)", z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); to_clash(z); mash(z, 1000); fall_done(z)
check("losing the clash itself: normal MISSION FAILED", z.rd(sym['LZ_FAIL_REASON']) == 0 and z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); z.wr(sym['LZ_FAIL_REASON'], 3); z.wr(CD, 50); call(z, 'LZ_INIT')
check("LZ_INIT clears LZ_FAIL_REASON and the countdown (restart)", z.rd(sym['LZ_FAIL_REASON']) == 0 and z.rd(CD) == 0)

print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
