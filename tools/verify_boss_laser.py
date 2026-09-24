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
def check(label, cond, info=None):
    if info is not None and not cond: label += f" {info}"
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
    _cur[0] = z
    z.sim_trig_b = trig_b
    z.pc = sym['MAINLOOP']; z.step(); run_until_pc(z, sym['MAINLOOP'])
def sattr(z, s): return tuple(z.vram[0x1B00 + s * 4 + i] for i in range(4))
def rd16(z, a): return z.rd(a) | z.rd(a + 1) << 8
def set_score(z, v):
    z.wr(sym['SCORE'], v & 255); z.wr(sym['SCORE'] + 1, (v >> 8) & 255); z.wr(sym['SCORE'] + 2, v >> 16)
def score(z): return rd16(z, sym['SCORE']) | z.rd(sym['SCORE'] + 2) << 16

PH, ROW = sym['LZ_PHASE'], sym['LZ_ROW']
BLANK = sym['BLANKCODE']
LCODE, RCODE = sym['EBUZ2_LASER_L_CODE'], sym['EBUZ2_LASER_R_CODE']
_cur = [None]
def beam(c, z=None):
    """EbuzIIのレーザー(L/Rの2セル弾)の流れ: (TICK+列)の偶奇でL/R。描いた時点のTICK"""
    z = z or _cur[0]
    return LCODE if (z.rd(sym['TICK']) + c) & 1 else RCODE
def beams(c0, c1, z=None): return [beam(c, z) for c in range(c0, c1)]
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
    """(2026-09-24) 64px = cols12-19の8セル、左端x=96"""
    names = []
    for i in range(8):
        f = g - 8 * i
        names.append('.' if f <= 0 else ('F' if f >= 8 else 'P'))
    k = g & 7
    return ''.join(names), (0xFF ^ (0xFF >> k)) if any(n == 'P' for n in names) else None
def gauge_screen(z):
    m = {sym['GAUGE_BLANK_CODE']: '.', sym['GAUGE_FULL_CODE']: 'F', sym['GAUGE_PART_CODE']: 'P'}
    return ''.join(m.get(z.vram[0x1800 + c], '?') for c in range(12, 20))
z = landed()
bad = []
for sc in (0, 9, 10, 15, 25, 79, 80, 81, 170, 250, 499, 500, 629, 630, 639, 640, 777, 0x10000):
    set_score(z, sc); frame(z)
    g = min(sc // 10, 64)
    want, part = gauge_model(g)
    got = gauge_screen(z)
    pat = z.vram[sym['GAUGE_PART_CODE'] * 8 + 3]
    if got != want or (part is not None and pat != part) or z.rd(sym['GAUGE_SHOWN']) != g:
        bad.append((sc, g, want, got, hex(pat)))
check(f"gauge: row0 cols12-19 = 64px bar at px96-159, 1px per 1000 points, full at 64000 (and above) {bad}", not bad)
# 1px単位で左端から伸びること(実ピクセル)
def gauge_pixels(z):
    px = []
    for c in range(12, 20):
        code = z.vram[0x1800 + c]; row = z.vram[code * 8 + 3]
        px += [(row >> (7 - b)) & 1 for b in range(8)]
    return px
bad = []
for g in range(65):
    set_score(z, g * 10); frame(z)
    p = gauge_pixels(z)
    lit = [i + 96 for i, v in enumerate(p) if v]
    if lit != list(range(96, 96 + g)): bad.append(g)
check(f"gauge: exactly g pixels lit from x=96 (centre 128 minus 32) for every g=0..64 {bad[:5]}", not bad)
set_score(z, 639); frame(z); c1 = z.vram[0x2000 + sym['GAUGE_FULL_CODE'] // 8]
set_score(z, 640); frame(z); c2 = z.vram[0x2000 + sym['GAUGE_FULL_CODE'] // 8]
check(f"gauge colour: white while charging (63900 -> {c1:#x}), red once full at 64000 ({c2:#x})", c1 == 0xF1 and c2 == 0x81)

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
def start_countdown(z, sc=700):
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
fr = z.rd(sym['LZ_BFRONT'])
check(f"after 120 frames the boss fires: the front leaves the muzzle (col {fr}), 3 rows thick (rows 8-10), EbuzII tiles",
      z.rd(PH) == 2 and fr == 25 and all(cells(z, r, 0, 26) == [BLANK] * 25 + beams(25, 26) for r in (8, 9, 10))
      and cells(z, 7, 0, 26) == [BLANK] * 26 and cells(z, 11, 0, 26) == [BLANK] * 26)
fronts = [fr]
for _ in range(10): frame(z); fronts.append(z.rd(sym['LZ_BFRONT']))
check(f"the boss beam is pushed out one cell per frame {fronts}",
      fronts == list(range(25, 14, -1)) and all(cells(z, r, 0, 26) == [BLANK] * 15 + beams(15, 26) for r in (8, 9, 10)))
e = sym['LZ_END_SPR']; ep = sym['LZ_END_PAT']
check(f"16x24 end sprite fills the 2-cell gap right of the beam (cols 26-27): slots {e},{e+1} = {sattr(z, e)} {sattr(z, e + 1)}",
      sattr(z, e) == (63, 208, ep, 7) and sattr(z, e + 1) == (79, 208, ep + 4, 7))
bits = json.load(open(os.path.join(HERE, 'stage1_sprites', 'B1beam_24x24.json')))['bits']
rows_ = [r[:16] for r in bits] + [[0] * 16] * 8
def sbyte(r, x0): return sum(r[x0 + i] << (7 - i) for i in range(8))
want = [sbyte(r, x) for part in (rows_[:16], rows_[16:]) for x in (0, 8) for r in part]
check("end sprite patterns 148-155 = B1beam_24x24.json (16 wide x 24 tall)",
      list(z.vram[0x3800 + ep * 8: 0x3800 + ep * 8 + 64]) == want)
t0 = beams(15, 26); frame(z); t1 = cells(z, 9, 15, 26)
check("the stream is re-shot every frame: each cell flips L/R from one frame to the next (バリバリ)",
      all(a != b for a, b in zip(t0, t1)))
for _ in range(20): frame(z)
check("the boss laser stays on (fire-and-hold) at full length while waiting for a cut-in",
      z.rd(PH) == 2 and all(cells(z, r, 0, 26) == beams(0, 26) for r in (8, 9, 10)))

# ---------------------------------------------------------------- 割り込み → 干渉 → 勝ち
sc0 = score(z)
frame(z, trig_b=True); frame(z)                          # 上から割り込み(押下は次フレームで処理)
pcol = z.rd(sym['LZ_PCOL'])
c = z.rd(sym['LZ_CLASH_X']) >> 3
check(f"B above the beam -> clash (phase 3), ship snapped into the middle row (PLAYERY 64), clash col {c}",
      z.rd(PH) == 3 and z.rd(sym['PLAYERY']) == 64 and pcol < c < 25)
check("clash drawn: middle row = player stream | blank (both streams vanish there) | boss stream; rows 8/10 = boss "
      "stream only right of the clash cell",
      cells(z, 9, pcol, 26) == beams(pcol, c) + [BLANK] + beams(c + 1, 26)
      and all(cells(z, r, 0, 26) == [BLANK] * (c + 1) + beams(c + 1, 26) for r in (8, 10)))
cs = sattr(z, sym['LZ_CLASH_SPR'])
check(f"clash-point sprite (player-explosion pattern) centred on the clash cell: {cs}",
      cs[0] == ROW * 8 - 5 and cs[1] == c * 8 - 4 and cs[2] == sym['PAT_PLAYER_EXPLOSION'] and cs[3] in (15, 11))
check("gauge stays full during the clash (use does not drain it)", z.rd(sym['GAUGE_SHOWN']) == 64)
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
pool = sym['PLAYER_EXPL_POOL']
nact, nums, xs, snd = 0, set(), [], 0
for f in range(24):
    frame(z, trig_b=(f % 6 == 0))
    if f == 23:
        for i in range(4):
            if z.rd(pool + i * 5):
                nact += 1; nums.add(z.rd(pool + i * 5 + 4)); xs.append(z.rd(pool + i * 5 + 1))
cx = z.rd(sym['LZ_CLASH_X'])
check(f"scatter: player-explosion bursts pop around the clash point every 4 frames ({nact} alive, sprites {sorted(nums)}, "
      f"x {xs} vs clash x{cx})",
      nact >= 3 and nums <= set(range(26, 30)) and all(-24 <= x - cx <= 7 for x in xs))
f = mash(z, 6)
check(f"mashing 10 presses/s pushes the boss back and wins (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 1 and z.rd(sym['GAME_OVER']) == 0)
check("win -> the normal boss death sequence (+10000 points = 100 units)", score(z) - sc0 == 100)
check("win -> all three laser rows erased", all(cells(z, r, 0, 26) == [BLANK] * 26 for r in (8, 9, 10)))
check("win -> clash and end sprites hidden",
      all(sattr(z, s)[0] == 191 for s in (sym['LZ_CLASH_SPR'], e, e + 1)))

def to_clash(z):
    start_countdown(z); z.wr(sym['PLAYERY'], 120); to_fire(z)
    frame(z, trig_b=True); frame(z)
z = landed(); to_clash(z)
f = mash(z, 9)
check(f"mashing 6.7 presses/s loses -> game over even with barrier left (after {f} frames)",
      z.rd(PH) == 4 and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['BOSS_EXPL_ACTIVE']) == 0)
check("lose -> the boss beam is left drawn full length over the player (3 rows), end sprite still on",
      all(cells(z, r, 0, 26) == beams(0, 26) for r in (8, 9, 10)) and sattr(z, e)[0] == 63
      and sattr(z, sym['LZ_CLASH_SPR'])[0] == 191)
z2 = landed(); to_clash(z2)
f = mash(z2, 7, 6000)
check(f"8.6 presses/s (every 7 frames) wins (after {f} frames)", z2.rd(PH) == 4 and z2.rd(sym['GAME_OVER']) == 0)
z2 = landed(); to_clash(z2)
c0 = z2.rd(sym['LZ_CLASH_X']); p0 = z2.rd(sym['LZ_PCOL'])
check(f"clash starts halfway between the player's muzzle (x{p0 * 8 + 8}) and the boss's (x208): x{c0}",
      abs(c0 - (p0 * 8 + 8 + 208) // 2) <= 1)
frame(z2, trig_b=True)
xs = [z2.rd(sym['LZ_CLASH_X'])]
for _ in range(22): frame(z2); xs.append(z2.rd(sym['LZ_CLASH_X']))
d = [b - a for a, b in zip(xs, xs[1:])]
st = sym['LZ_STOP_FRAMES']
check(f"boss push: the press frame +8-1, then 1px/frame (60px/s, so 8 presses/s x 8px is about even), doubled to "
      f"2px/frame once the player has stopped pressing for {st} frames {d}",
      d == [7] + [-1] * (st - 1) + [-2] * (22 - st))

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

# (2026-09-23) テストモードでエナジー不足・バリア無しでも、カウントダウンの無限ループにならない
z = landed(); z.wr(sym['GAMEOVER_ENABLED'], 0); z.wr(sym['BARRIER_HP'], 0)
start_countdown(z, 300); z.wr(sym['PLAYERY'], 120); to_fire(z)
check("test mode, gauge short and no barrier: the boss still fires and holds (no endless countdown loop)",
      z.rd(PH) == 2 and z.rd(CD) == 0)
for _ in range(10): frame(z)
frame(z, trig_b=True); frame(z)
check("test mode: the laser can cut in regardless of gauge/barrier -> clash", z.rd(PH) == 3)
z = landed(); z.wr(sym['GAMEOVER_ENABLED'], 0); z.wr(sym['LZ_SPENT'], 1); start_countdown(z)
z.wr(sym['PLAYERY'], 120)
for _ in range(120): frame(z)
check("test mode, laser already used: one restart of the countdown with the energy refilled (as before)",
      z.rd(PH) == 0 and z.rd(CD) == 120 and z.rd(sym['LZ_SPENT']) == 0)
to_fire(z)
check("... and the next boss shot fires normally", z.rd(PH) == 2)

# ---------------------------------------------------------------- 割り込まない / 帯の中 / 条件未達
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 120); to_fire(z)
n = 0
while z.rd(PH) == 2 and n < 300: frame(z); n += 1
check(f"qualified but never cutting in: game over after the {sym['LZ_CUTIN_FRAMES']}-frame cut-in window (firing frame + {n}), "
      f"normal MISSION FAILED path (reason 0)",
      z.rd(sym['GAME_OVER']) == 1 and n + 1 == sym['LZ_CUTIN_FRAMES'] and z.rd(sym['LZ_FAIL_REASON']) == 0)
def hit_frame(z):
    n = 0
    while z.rd(sym['GAME_OVER']) == 0 and z.rd(PH) == 2 and n < 60: frame(z); n += 1
    return n
z = landed(); start_countdown(z); z.wr(sym['PLAYERX'], 60); z.wr(sym['PLAYERY'], 70); to_fire(z)
n = hit_frame(z)
check(f"standing inside the 3-row band: hit the moment the beam front reaches the ship (x60-67 -> front col 8, "
      f"{n} frames after firing)", z.rd(sym['GAME_OVER']) == 1 and n == 17, n)
z = landed(); start_countdown(z); z.wr(sym['PLAYERX'], 60); z.wr(sym['PLAYERY'], 70); to_fire(z)
for _ in range(16): frame(z)
check("... not before (front still at col 9, right of the ship)", z.rd(sym['GAME_OVER']) == 0 and z.rd(PH) == 2)
for y, inside in ((56, False), (57, True), (87, True), (88, False)):
    z = landed(); start_countdown(z); z.wr(sym['PLAYERX'], 60); z.wr(sym['PLAYERY'], y); to_fire(z); hit_frame(z)
    check(f"band edge: PLAYERY {y} ({'hit' if inside else 'safe'}) - hitbox y..y+7 vs rows 8-10 (y64-87)",
          z.rd(sym['GAME_OVER']) == (1 if inside else 0))
z = landed(); start_countdown(z, sc=639); z.wr(sym['PLAYERY'], 120)
n = to_fire(z)
check("gauge short of 64000 (63900): no instant game over any more - the boss starts the random barrage "
      "(phase 5), reason 2 recorded", z.rd(PH) == 5 and z.rd(sym['GAME_OVER']) == 0 and z.rd(sym['LZ_FAIL_REASON']) == 2)

# ---------------------------------------------------------------- 乱射(条件未達、2026-09-24)
# "3本レーザーを1本にするが 画面Row1からRow19まで ボス中央からランダムにレーザー乱射
# セルでラインを描く感じで 特に特別処理は入れず自然に死ぬように"
ROWS = sym['LZ_BR_ROWS']
z.wr(sym['PLAYERX'], 200); z.wr(sym['PLAYERY'], 150)      # 当たらない場所で観察
targets, bad_shape, fronts = [], [], []
prev_target = None
for f in range(400):
    frame(z)
    rows = [z.rd(ROWS + c) for c in range(26)]
    fr = z.rd(sym['LZ_BR_FRONT'])
    fronts.append(fr)
    if rows[25] != ROW or any(abs(a - b) > 1 for a, b in zip(rows, rows[1:])) or not 1 <= rows[0] <= 19:
        bad_shape.append(rows)
    if fr == 0 and rows[0] != prev_target:
        targets.append(rows[0]); prev_target = rows[0]
    # 描かれているのは先端〜列25の1本だけ(各列にレーザーのタイルは1セル)
    for c in range(fr, 26):
        col = [z.vram[0x1800 + r * 32 + c] for r in range(1, 20)]
        n = sum(1 for t in col if t in (LCODE, RCODE))
        if n != 1 or col[rows[c] - 1] not in (LCODE, RCODE): bad_shape.append(('cell', f, c, n)); break
check(f"barrage: each shot is a 1-cell-thick line from the boss centre (col25,row{ROW}) to col0 at a random row 1-19, "
      f"at most one row step per column {bad_shape[:2]}", not bad_shape)
check(f"barrage: lines keep coming at different rows ({len(targets)} shots in 400 frames, rows {targets[:12]})",
      len(targets) >= 20 and len(set(targets)) >= 8 and z.rd(sym['GAME_OVER']) == 0)
steps = [a - b for a, b in zip(fronts, fronts[1:]) if a > b]
check(f"barrage: the line is pushed out {sym['LZ_BR_SPEED']} columns per frame {sorted(set(steps))}",
      set(steps) <= {sym['LZ_BR_SPEED'], 26 % sym['LZ_BR_SPEED'] or sym['LZ_BR_SPEED'], 2})
# 自然に死ぬ: バリアがあれば普通に減る(無敵時間つき)、無ければ死ぬ
z2 = landed(); start_countdown(z2, sc=639); z2.wr(sym['BARRIER_HP'], 3); z2.wr(sym['PLAYERX'], 40)
z2.wr(sym['PLAYERY'], 70); to_fire(z2)
hp, n = [], 0
while z2.rd(sym['GAME_OVER']) == 0 and n < 3000:
    frame(z2); n += 1; hp.append(z2.rd(sym['BARRIER_HP']))
drops = [i for i in range(1, len(hp)) if hp[i] < hp[i - 1]]
check(f"barrage hits go through the normal damage path: the barrier drops 3->0 one at a time ({drops}), "
      f"then the next hit kills (frame {n})", z2.rd(sym['GAME_OVER']) == 1 and len(drops) == 3
      and all(b - a >= sym['BARRIER_IFRAMES_INIT'] for a, b in zip(drops, drops[1:])))

# ---------------------------------------------------------------- 早撃ち
z = landed(); set_score(z, 700); z.wr(sym['PLAYERY'], 150); frame(z)   # row19: ポッドの軌道外
frame(z, trig_b=True); frame(z)
prow = (150 + 8) >> 3; pcol = z.rd(sym['LZ_PCOL'])
ends = [z.rd(sym['LZ_PEND'])]
for _ in range(34): frame(z); ends.append(z.rd(sym['LZ_PEND']))
check(f"B with the gauge full before the boss laser: player stream (EbuzII tiles) on the ship's row {prow}, pushed "
      f"out one cell per frame to the right edge {ends[:4]}..{ends[-1]}",
      z.rd(PH) == 1 and z.rd(sym['LZ_PROW']) == prow and ends[0] == pcol
      and ends == [min(pcol + i, 32) for i in range(35)] and cells(z, prow, pcol, 32) == beams(pcol, 32))
gs = [z.rd(sym['GAUGE_SHOWN'])]
n = 35
while z.rd(PH) == 1 and n < 200:
    frame(z); gs.append(z.rd(sym['GAUGE_SHOWN'])); n += 1
check(f"premature laser lasts 100 frames ({n - 1}) while the gauge drains to 0 ({gs[0]},{gs[20]},{gs[-2]})",
      n - 1 == 100 and gs[0] == 66 // 2 + 66 // 8 + 66 // 32 and gs[-2] <= 1 and all(a >= b for a, b in zip(gs, gs[1:])))
frame(z)
check("after 100 frames the laser is gone, marked used, gauge 0",
      z.rd(PH) == 0 and z.rd(sym['LZ_SPENT']) == 1 and cells(z, prow, 0, 32) == [BLANK] * 32 and z.rd(sym['GAUGE_SHOWN']) == 0)
frame(z, trig_b=True); frame(z)
check("used laser cannot be fired again", z.rd(PH) == 0)
kill_all_pods(z); to_fire(z)
check("used before the countdown ended: the barrage starts when the boss fires (reason 2)",
      z.rd(PH) == 5 and z.rd(sym['GAME_OVER']) == 0 and z.rd(sym['LZ_FAIL_REASON']) == 2)
z = landed(); set_score(z, 700); frame(z)
z.wr(sym['PLAYERX'], 40); z.wr(sym['PLAYERY'], 120)
frame(z, trig_b=True); frame(z)
for _ in range(30): frame(z)
check("premature laser on a boss row stops at the boss's left edge (col 25)",
      z.rd(sym['LZ_PEND']) == 26 and cells(z, 16, z.rd(sym['LZ_PCOL']), 26) == beams(z.rd(sym['LZ_PCOL']), 26))
z = landed(); set_score(z, 700); frame(z)
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
      cells(z, 19, 0, 32) == [BLANK] * 32 and 0 < z.rd(sym['GAUGE_SHOWN']) < 64)
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
z = landed(); z.wr(sym['BARRIER_HP'], 0); set_score(z, 700); z.wr(sym['PLAYERY'], 150); frame(z)
frame(z, trig_b=True); frame(z)
check("no barrier left: B cannot fire the laser even with a full gauge", z.rd(PH) == 0)

# ---------------------------------------------------------------- 条件未達のゲームオーバー分岐
def fall_done(z, limit=600):
    n = 0
    while z.rd(sym['GAME_OVER_SEQ']) == 0 and n < limit: frame(z); n += 1
for label, setup, want in (
        ("no barrier", lambda z: z.wr(sym['BARRIER_HP'], 0), 1),
        ("gauge short of 64000", lambda z: set_score(z, 639), 2),
        ("laser already used", lambda z: z.wr(sym['LZ_SPENT'], 1), 2),
        ("no barrier and not enough energy", lambda z: (z.wr(sym['BARRIER_HP'], 0), set_score(z, 100)), 3)):
    z = landed(); start_countdown(z); setup(z); z.wr(sym['PLAYERY'], 70); z.wr(sym['PLAYERX'], 40)
    if z.rd(sym['BARRIER_HP']): z.wr(sym['BARRIER_HP'], 1)
    to_fire(z)
    r = z.rd(sym['LZ_FAIL_REASON'])
    fall_done(z, 4000)
    check(f"unqualified when the boss fires ({label}): reason {r} (want {want}); killed by the barrage, after the death "
          f"fall GAME_OVER_SEQ=4 (Comb switches to the bank7 reason screen)",
          r == want and z.rd(sym['GAME_OVER']) == 1 and z.rd(sym['GAME_OVER_SEQ']) == 4)
z = landed(); start_countdown(z); z.wr(sym['PLAYERY'], 150); to_fire(z)
while z.rd(PH) == 2: frame(z)
fall_done(z)
check("qualified player who just never cut in: normal MISSION FAILED (GAME_OVER_SEQ 1)", z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); to_clash(z); mash(z, 1000); fall_done(z)
check("losing the clash itself: normal MISSION FAILED", z.rd(sym['LZ_FAIL_REASON']) == 0 and z.rd(sym['GAME_OVER_SEQ']) == 1)
z = landed(); z.wr(sym['LZ_FAIL_REASON'], 3); z.wr(CD, 50); call(z, 'LZ_INIT')
check("LZ_INIT clears LZ_FAIL_REASON and the countdown (restart)", z.rd(sym['LZ_FAIL_REASON']) == 0 and z.rd(CD) == 0)

# ---------------------------------------------------------------- ボス戦中の自機爆発
# (2026-09-23、"ボス時に自機の爆破処理がないな"): ボス出現で8-31が全部予約されていたため
# PLAYER_EXPLが1つも出ていなかった。
for label, prep in (("landed boss", lambda z: None), ("boss laser lost", None)):
    if prep is None:
        z = landed(); to_clash(z); mash(z, 1000)
    else:
        z = landed(); z.wr(sym['BARRIER_HP'], 0); call(z, 'PLAYER_TAKE_HIT')
    seen, sounds = set(), 0
    for f in range(60):
        frame(z)
        for i in range(4):
            if z.rd(pool + i * 5):
                sn = z.rd(pool + i * 5 + 4); seen.add(sn)
                if sattr(z, sn)[2] != sym['PAT_PLAYER_EXPLOSION']: seen.add(-1)
    check(f"player death during the boss ({label}): the player-explosion bursts appear (sprites {sorted(seen)})",
          len(seen) >= 3 and seen <= set(range(26, 30)))
z = landed(); z.wr(sym['BOSS_STATE'], 0)
for i in range(32): z.wr(sym['SPRITE_USED'] + i, 0)
call(z, 'PLAYER_EXPL_TRIGGER')
check("outside the boss, PLAYER_EXPL_TRIGGER leaves SPRITE_USED alone",
      [z.rd(sym['SPRITE_USED'] + i) for i in range(32)] == [0] * 32)

print(f"\n{len(ok)} passed, {len(fail)} failed")
sys.exit(1 if fail else 0)
