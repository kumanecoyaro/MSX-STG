"""Stage1 (2026-09-24): 
(1) "ウェーブが上下移動時アニメしてないので アニメするように" - ウェーブ(TYPE_ENEMY1_LOOK)は
    サイン移動中だけ1,2,3,2の4コマを進め、頂点/下限の水平ドリフト中は基本コマに戻る。
(2) "この系統のヒット位置で判定してる敵で おそらく丁度Y位置真ん中を撃つと弾抜け" - スプライトは
    属性Y+1の行から表示されるので、パーツの当たりもY+1〜Y+8で取る(QUAD_HIT_TEST_SPR)。
    実際のENEMY_POOL_UPDATE_ALL+CHECK_BULLET_VS_ENEMY_POOLを毎フレーム回し、弾の線(2px)が
    見えている絵と重なったのに当たらずに抜ける組み合わせが0件になることを確かめる。"""
import sys, os, copy
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
E = sym['ENEMY_POOL']
z0 = Z80(bytearray(mem)); z0.pc = sym['INIT']
for _ in range(6000000):
    if z0.pc == sym['MAINLOOP']: break
    z0.step()
LUT = [mem[sym['ENEMY4_SINE_LUT'] + i] for i in range(32)]
def pat8(label): return [mem[sym[label] + i] for i in range(8)]
FRAMES = {0: pat8('ASTERISK_PATTERN'), 1: pat8('ASTERISK_PATTERN2'), 2: pat8('ASTERISK_PATTERN3'), 3: pat8('ASTERISK_PATTERN2')}

def spawn(kind, basey, state0=0, x=200):
    z = copy.deepcopy(z0)
    if kind == 'simple':
        z.wr(sym['SPAWN_E1_Y'], basey); call(z, 'ENEMY1_CLAIM_ANY')
    else:
        z.wr(sym['E4_SPAWN_TYPE'], sym['TYPE_ENEMY1_LOOK']); z.wr(sym['E4_SPAWN_BASEY'], basey)
        call(z, 'ENEMY4_CLAIM_ANY'); z.wr(E + sym['E_STATE'], state0)
    z.wr(E + sym['E_X'], x)
    return z

# ---- (1) wave animation ----
z = spawn('wave', 80, x=250)
patnum = mem[sym['SIMPLE_PATTERN_NUMS'] + z.rd(E + sym['E_PARAM3'])]
seqs, frozen_seqs, vram_ok, trace = [], [], True, []
for f in range(120):
    call(z, 'ENEMY_POOL_UPDATE_ALL')
    if not z.rd(E): break
    seq = z.rd(E + sym['E_PARAM4']); fr = z.rd(E + sym['E_PARAM5'])
    (frozen_seqs if fr else seqs).append(seq)
    trace.append((f, seq, fr))
    tl = [z.vram[0x3800 + patnum * 8 + i] for i in range(8)]
    br = [z.vram[0x3800 + patnum * 8 + 24 + i] for i in range(8)]
    if tl != FRAMES[seq] or br != FRAMES[seq]: vram_ok = False
changes = sum(1 for p, q in zip(seqs, seqs[1:]) if p != q)
check(f"wave: while bobbing the anim frame cycles through 0,1,2,3 ({changes} changes over {len(seqs)} frames)",
      set(seqs) == {0, 1, 2, 3} and changes >= 10)
steps_ok, last_change = True, None
for (f1, s1, r1), (f2, s2, r2) in zip(trace, trace[1:]):
    if r1 == 0 and r2 == 0 and s1 != s2:
        if s2 != (s1 + 1) % 4 or (last_change is not None and f2 - last_change < sym['ENEMY1_ANIM_FRAME_LEN'] + 1):
            steps_ok = False
        last_change = f2
check("wave: while bobbing each step is +1 mod 4, at most once per ENEMY1_ANIM_FRAME_LEN+1 frames", steps_ok)
check(f"wave: during the peak/trough horizontal drift it stays on the base frame (saw {set(frozen_seqs)})",
      len(frozen_seqs) > 0 and set(frozen_seqs) == {0})
check("wave: the sprite's own pattern slot in VRAM always shows the current frame (both parts)", vram_ok)

# ---- (2) bullet pass-through: shot line visibly over the art but no hit ----
ART = pat8('ASTERISK_PATTERN')
def art_px(x, y, top, bot):
    s = set()
    for qx, qy, alive in ((x, y, top), (x + 8, y + 8, bot)):
        if not alive: continue
        for r, b in enumerate(ART):
            for c in range(8):
                if b & (0x80 >> c): s.add((qx + c, qy + r + 1))   # TMS9918: shown from Y+1
    return s
def shoot(kind, basey, row, M, state0=0, kill_bot=False):
    z = spawn(kind, basey, state0)
    if kill_bot: z.wr(E + sym['E_BOT'], 0)
    col, over = 2, False
    for f in range(80):
        call(z, 'ENEMY_POOL_UPDATE_ALL')
        if not z.rd(E): return 'gone', over
        if call(z, 'CHECK_BULLET_VS_ENEMY_POOL', b=col, c=row) == 1: return 'hit', over
        col += 1
        if col > 31: return 'miss', over
        x = z.rd(E + sym['E_X'])
        y = z.rd(E + sym['E_Y']) if kind == 'simple' else (z.rd(E + sym['E_PARAM0']) + LUT[z.rd(E + sym['E_STATE'])]) & 255
        line = {(col * 8 + i, row * 8 + M + j) for i in range(8) for j in (0, 1)}
        if art_px(x, y, z.rd(E + sym['E_TOP']), z.rd(E + sym['E_BOT'])) & line: over = True
    return 'timeout', over
for kind, states in (('simple', [0]), ('wave', range(0, 32, 4))):
    for kb in (False, True):
        bad, n = [], 0
        for basey in range(40, 49):
            for st in states:
                for row in range(3, 10):
                    for M in (0, 2, 4, 6):
                        r, ov = shoot(kind, basey, row, M, st, kb)
                        n += 1
                        if r != 'hit' and ov: bad.append((basey, st, row, M, r))
        check(f"{kind}{' (bottom part already destroyed)' if kb else ''}: no shot passes through the drawn art "
              f"without a hit ({len(bad)}/{n} bad {bad[:4]})", not bad)

# the classic middle case, static: enemy at Y=48 (aligned), top part only; a shot in row 7 (56-63)
# crosses the top part's last drawn line (Y+8=56) -> must hit it.
z = spawn('simple', 48, x=100); z.wr(E + sym['E_BOT'], 0)
check("simple: top part's bottom line (drawn at Y+8) is hit by the shot row just below Y+7",
      call(z, 'CHECK_BULLET_VS_ENEMY_POOL', b=12, c=7) == 1)
z = spawn('simple', 48, x=100); z.wr(E + sym['E_BOT'], 0)
check("simple: a shot row entirely above the drawn part (row 5, 40-47) still misses",
      call(z, 'CHECK_BULLET_VS_ENEMY_POOL', b=12, c=5) == 0)
# zigzag formation unit (same QUAD_HIT_TEST_SPR)
z = copy.deepcopy(z0)
z.wr(sym['E2A_U0_STATE'], 1); z.wr(sym['E2A_U0_X'], 100); z.wr(sym['E2A_U0_Y'], 48)
z.wr(sym['E2A_U0_TOP'], 1); z.wr(sym['E2A_U0_BOT'], 0)
for u in (1, 2): z.wr(sym[f'E2A_U{u}_STATE'], 0)
check("zigzag unit: top part's bottom line (Y+8) is hit by the shot row just below",
      call(z, 'CHECK_BULLET_VS_FORMATION_A', b=12, c=7) == 1)
z.wr(sym['E2A_U0_TOP'], 1)
check("zigzag unit: row above the drawn part misses", call(z, 'CHECK_BULLET_VS_FORMATION_A', b=12, c=5) == 0)

# ---- (3) "ではそこも修正して": wave body contact uses its real drawn Y (E_Y written every frame) ----
z = spawn('wave', 100, state0=4, x=120)
call(z, 'ENEMY_POOL_UPDATE_ALL')
wy = (z.rd(E + sym['E_PARAM0']) + LUT[z.rd(E + sym['E_STATE'])]) & 255
wx = z.rd(E + sym['E_X'])
check(f"wave: E_Y follows the drawn Y every frame (E_Y={z.rd(E + sym['E_Y'])}, drawn {wy})", z.rd(E + sym['E_Y']) == wy)
z.wr(sym['PLAYERX'], wx); z.wr(sym['PLAYERY'], wy)
check("wave: player overlapping the wave's top part is detected by PDC_CHECK_ENEMY_POOL",
      call(z, 'PDC_CHECK_ENEMY_POOL') == 1)
z.wr(sym['PLAYERX'], wx); z.wr(sym['PLAYERY'], 2)
check("wave: player at the top of the screen (Y=2, far above the wave) is NOT hit any more",
      call(z, 'PDC_CHECK_ENEMY_POOL') == 0)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail: print("FAILED:", fail)
