"""tools/ebuz_test/ebuz_test.asm(新エネミー"Ebuz"のプロトタイプ)の
検証(2026-09-13〜14)。専用の空SCREEN1環境でstate1出現→state2変化→
継続発射という一連の流れを確認する、本編未組み込みの独立テスト。

tools/verify_*.py群と同じ「mini_z80asm.Assemblerで直接アセンブル+
run_until_pcの一回性検証スクリプト」の作法に倣う。

(2026-09-14追記、実機フィードバック対応での全面書き直し): "誰が弾
生きてたら待てとか指示したんだよ...交互って言ったら平均に交互に
決まってんだろうが だれが画面内2発に制限しろって指示したんだよ"を
受け、継続発射を「対象スロットが生きていれば待つ」方式から「固定
2ティック間隔で無条件に新規スロットへ発射し続ける」方式へ全面
再設計した。これに伴い、旧来の「論理スロット0=初弾/1=上/2=下」という
固定識別自体が廃止され、単一の匿名スロットプール(EBUZ_SLOT_COUNT=16)
から発射のたびに新しい物理番号がローテーションで割り当てられる方式に
変わったため、テスト自体も「特定の固定スロットを読む」方式から
「プール全体を毎ティック、Python参照実装(Sim)と完全一致するかで
検証する」方式へ全面的に書き直した。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80

with open(os.path.join(HERE, "ebuz_test.asm"), encoding="utf-8") as f:
    text = f.read()
asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def run_until_pc_count(z, target_pc, max_instr=2_000_000):
    """run_until_pcと同じだが、実際に消費したステップ数を返す
    (「ラベル順序が正しいだけで実際は遅延処理が呼ばれていない」種類の
    回帰を検出するため - ラベル位置だけを見るテストではこれを検出
    できない)。"""
    steps = 0
    for _ in range(max_instr):
        if z.pc == target_pc:
            return steps
        z.step()
        steps += 1
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


A, B, C, D = sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"], sym["EBUZ_CODE_D"]
NAMTBL = 0x1800


def cells(z, row, col, n):
    return [z.vram[NAMTBL + row * 32 + col + i] for i in range(n)]


# ---------- state1: 2 tile rows, both identical (A,B,C,D), at row2/col24 ----------
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["EBUZ_STATE1_DONE"])
check("state1 row2 (top) is A,B,C,D at col24-27", cells(z, 2, 24, 4) == [A, B, C, D])
check("state1 row3 (bottom) is also A,B,C,D (identical to row2)", cells(z, 3, 24, 4) == [A, B, C, D])
check("state1: row1 (above) is untouched (still blank/code0)", cells(z, 1, 24, 4) == [0, 0, 0, 0])
check("state1: row4 (below) is untouched (still blank/code0)", cells(z, 4, 24, 4) == [0, 0, 0, 0])
check("EBUZ's 4 pattern codes actually loaded into VRAM pattern generator "
      "(non-blank bitmaps)",
      all(any(z.vram[code * 8 + i] for i in range(8)) for code in (A, B, C, D)))

# ---------- state2 (corrected, from Ebuz3): A,B,C band splits away from the ----------
# original 2 rows to new top/bottom bands, leaving only D behind in the middle.
z2 = fresh()
z2.pc = sym["INIT"]
run_until_pc(z2, sym["EBUZ_STATE2_DONE"])
check("state2 row1 (new top band) is blank,A,B,C at col24-27", cells(z2, 1, 24, 4) == [0, A, B, C])
check("state2 row4 (new bottom band) is blank,A,B,C at col24-27", cells(z2, 4, 24, 4) == [0, A, B, C])
check("state2 row2 (was A,B,C,D): A,B,C have moved away, only D remains", cells(z2, 2, 24, 4) == [0, 0, 0, D])
check("state2 row3 (was A,B,C,D): A,B,C have moved away, only D remains", cells(z2, 3, 24, 4) == [0, 0, 0, D])

# ---------- the 4 tiles genuinely reconstruct Ebuz3.json byte-for-byte (see ebuz_gen.py) ----------
import ebuz_gen
a, b, c, d = ebuz_gen.extract_tiles()
ok_recon, mismatch = ebuz_gen.verify_against_ebuz3(a, b, c, d)
check("the 4 extracted tiles (A,B,C,D) reconstruct the uploaded Ebuz3.json exactly "
      "(confirms Ebuz3 - the corrected state2 art - is just a rearrangement of "
      "Ebuz1's own tiles, no new art)",
      ok_recon)


# ---------- bullets ----------
SPRATR = 0x1B00
BULLET_FULL_CODE = sym["BULLET_FULL_CODE"]
BULLET_HALF_CODE = sym["BULLET_HALF_CODE"]
BULLET_COLOR = sym["EBUZ_BULLET_COLOR"]
BULLET1_X = sym["EBUZ_BULLET1_X"]   # state1弾: 192-16=176
BULLET23_X = sym["EBUZ_BULLET_X"]   # state2弾: 192のまま
SPEED = sym["EBUZ_BULLET_SPEED"]
check(f"EBUZ_BULLET_SPEED is exactly the requested flat 8px/frame, "
      f"pinned as a literal, not just self-consistency with the "
      f"simulation below",
      SPEED == 8)
SPR_HIDE_Y = sym["SPR_HIDE_Y"]
SPR_TERM_Y = sym["SPR_TERM_Y"]
Y1_STORED = sym["EBUZ_BULLET1_STORED_Y"]
Y2_STORED = sym["EBUZ_BULLET2_STORED_Y"]
Y3_STORED = sym["EBUZ_BULLET3_STORED_Y"]
FIRE_INTERVAL = sym["EBUZ_FIRE_INTERVAL"]
RECOIL_DURATION = sym["EBUZ_RECOIL_DURATION"]
SLOT_COUNT = sym["EBUZ_SLOT_COUNT"]
SENTINEL = 0x0000  # never real code - safe return trap (see tools/verify_sound_duty_cycle.py)

check("EBUZ_ROW_TOP_BAND(1)/EBUZ_ROW_BOTTOM_BAND(4) match the actual BG row "
      "numbers used for the wing bands (row1/row4, see EBUZ_STATE2_BG_DONE's "
      "own LDIRVM destinations 01838h/01898h)",
      sym["EBUZ_ROW_TOP_BAND"] == 1 and sym["EBUZ_ROW_BOTTOM_BAND"] == 4)
check(f"bullet1's desired Y is exactly 8px (top wing band's row, stored="
      f"{Y2_STORED}) and bullet2's is exactly 32px (bottom wing band's row, "
      f"stored={Y3_STORED}) - both 8px lower than the original literal "
      f"0px/24px, and both relative to the body's own wing rows now",
      Y2_STORED == 7 and Y3_STORED == 31)
check("EBUZ_FIRE_INTERVAL is exactly 2 (\"2フレ交代\") and "
      "EBUZ_RECOIL_DURATION is 1 (recoil shows for 1 tick then reverts, "
      "per \"打ったら元位置に戻せ\")",
      FIRE_INTERVAL == 2 and RECOIL_DURATION == 1)
check("EBUZ_SLOT_COUNT is exactly 16 (a single anonymous pool shared by "
      "bullet0/top/bottom, sized well above the ~13 bullets that can be "
      "simultaneously alive under fixed 2-tick unconditional fire)",
      SLOT_COUNT == 16)


def pool_snapshot(z):
    """現在のSPRATR上の全EBUZ_SLOT_COUNTスロットを読み出す(各4byte:
    Y,X,pattern,color)。"""
    out = []
    for i in range(SLOT_COUNT):
        base = SPRATR + i * 4
        out.append([z.vram[base + j] for j in range(4)])
    return out


def call_routine(z, addr, max_instr=2_000_000):
    """1回のCALL相当を実行し、SENTINELへ戻るまでのステップ数を返す
    (tools/verify_sound_duty_cycle.pyのcall_routine()と同じ作法)。"""
    z.sp = (z.sp - 2) & 0xFFFF
    z.wr(z.sp, SENTINEL & 0xFF)
    z.wr((z.sp + 1) & 0xFFFF, (SENTINEL >> 8) & 0xFF)
    z.pc = addr
    steps = 0
    while z.pc != SENTINEL and steps < max_instr:
        z.step()
        steps += 1
    if steps >= max_instr:
        raise RuntimeError(f"call to {addr:04x} never returned")
    return steps


def call_routine_tstates(z, addr, max_instr=2_000_000):
    """call_routine()と同じだが、z.tstatesの消費量(実時間換算に使える
    実際のZ80クロック数)を返す。呼び出し前にz.tstates=0へリセットする。"""
    z.tstates = 0
    call_routine(z, addr, max_instr)
    return z.tstates


# --- EBUZ_FRAME_WAIT remains calibrated to roughly a real 1/60s frame at ---
# 3.58MHz.
Z_CLOCK_HZ = 3_579_545
TARGET_FRAME_SEC = 1 / 60
frame_wait_tstates = call_routine_tstates(fresh(), sym["EBUZ_FRAME_WAIT"])
frame_wait_sec = frame_wait_tstates / Z_CLOCK_HZ
check(f"EBUZ_FRAME_WAIT still costs a realistic ~1/60s of Z80 clock time "
      f"({frame_wait_tstates} T-states = {frame_wait_sec:.5f}s, vs target "
      f"{TARGET_FRAME_SEC:.5f}s)",
      TARGET_FRAME_SEC * 0.5 <= frame_wait_sec <= TARGET_FRAME_SEC * 2.0)

# --- EBUZ_WAIT_TICKS(B=1) costs exactly one EBUZ_TICK's worth of steps - ---
# the reference unit used by the gap-verification checks below.
one_tick_steps = call_routine(fresh(), sym["EBUZ_TICK"])

WAIT_BEFORE_FIRE_TICKS = 29
WAIT_STATE1_TO_STATE2_TICKS = 102

z0 = fresh()
z0.pc = sym["INIT"]
run_until_pc(z0, sym["EBUZ_STATE1_BG_DONE"])
gap1 = run_until_pc_count(z0, sym["EBUZ_STATE1_DONE"])
check(f"state1: the BG-done -> fired gap actually spends roughly "
      f"{WAIT_BEFORE_FIRE_TICKS} EBUZ_TICK's worth of steps "
      f"({gap1} >= {one_tick_steps}*{WAIT_BEFORE_FIRE_TICKS}*0.9), not just a "
      f"few instructions",
      gap1 >= one_tick_steps * WAIT_BEFORE_FIRE_TICKS * 0.9)

z1b = fresh()
z1b.pc = sym["INIT"]
run_until_pc(z1b, sym["EBUZ_STATE1_DONE"])
gap2 = run_until_pc_count(z1b, sym["EBUZ_STATE2_BG_DONE"])
check(f"state1-to-state2 gap actually spends roughly "
      f"{WAIT_STATE1_TO_STATE2_TICKS} EBUZ_TICK's worth of steps "
      f"({gap2} >= {one_tick_steps}*{WAIT_STATE1_TO_STATE2_TICKS}*0.9), not "
      f"just a few instructions",
      gap2 >= one_tick_steps * WAIT_STATE1_TO_STATE2_TICKS * 0.9)

gap3 = run_until_pc_count(z1b, sym["EBUZ_STATE2_DONE"])
check(f"state2-BG-done -> activation gap actually spends roughly "
      f"{WAIT_BEFORE_FIRE_TICKS} EBUZ_TICK's worth of steps "
      f"({gap3} >= {one_tick_steps}*{WAIT_BEFORE_FIRE_TICKS}*0.9), not just a "
      f"few instructions",
      gap3 >= one_tick_steps * WAIT_BEFORE_FIRE_TICKS * 0.9)

check("EBUZ_BULLET1_X is exactly 16px left of EBUZ_BULLET_X (the shared base/"
      "state2 X), not just equal to it - pins the actual numeric relationship "
      "the user asked for rather than trusting the symbol names alone",
      BULLET1_X == BULLET23_X - 16)

check("BULLET_FULL's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z0.vram[0x3800 + BULLET_FULL_CODE * 8 + i] for i in range(32)))
check("BULLET_HALF's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z0.vram[0x3800 + BULLET_HALF_CODE * 8 + i] for i in range(32)))
check("16x16 sprite size mode enabled (RG1SAV mirror bit1/SI set)",
      z0.mem[sym["RG1SAV"]] & 0x02 != 0)


# ============================================================================
# Sim: Python参照実装(2026-09-14、実機フィードバック対応での全面書き直し)
#
# "誰が弾生きてたら待てとか指示したんだよ...交互って言ったら平均に交互に
# 決まってんだろうが だれが画面内2発に制限しろって指示したんだよ"を受け、
# EBUZ_UPDATE_TOPBOTTOM_FIREの新設計(生存チェックなし、固定
# EBUZ_FIRE_INTERVALごとに無条件でプールから新規スロットを割り当てて
# 発射)をそのまま1ティックずつシミュレートする。ASMの実行順序
# (EBUZ_TICK: 全EBUZ_SLOT_COUNTスロットを更新→[アクティブなら]
# EBUZ_UPDATE_TOPBOTTOM_FIRE[反動リバート→発射カウントダウン→0なら
# 無条件発射])を厳密に再現する。
# ============================================================================
class Sim:
    def __init__(self):
        self.pool = [[SPR_HIDE_Y, 0, 0, 0] for _ in range(SLOT_COUNT)]
        self.next_slot = 0
        self.bullet0_slot = None
        self.bullet0_holding = False
        self.fire_side = 0
        self.fire_cd = 0
        self.recoil_side = 0
        self.recoil_cd = 0
        self.topbottom_active = False
        self.row1_recoiled = False
        self.row4_recoiled = False
        self.state2_formed = False  # row1/row4 wing-band cells don't exist until state2's BG transform

    def alloc(self):
        idx = self.next_slot
        self.next_slot = (self.next_slot + 1) % SLOT_COUNT
        return idx

    def fire_bullet0(self):
        idx = self.alloc()
        self.pool[idx] = [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR]
        self.bullet0_slot = idx
        self.bullet0_holding = True

    def end_hold(self):
        self.bullet0_holding = False

    def activate_topbottom(self):
        self.fire_side = 0
        self.fire_cd = 1
        self.topbottom_active = True

    def tick(self):
        # EBUZ_TICK: 全スロットを更新(bullet0がホールド中ならそのスロットだけスキップ)
        for i in range(SLOT_COUNT):
            if self.bullet0_holding and i == self.bullet0_slot:
                continue
            y, x, pat, col = self.pool[i]
            if y == SPR_HIDE_Y:
                continue
            if x < SPEED:
                self.pool[i][0] = SPR_HIDE_Y
            else:
                self.pool[i][1] = x - SPEED
        # EBUZ_UPDATE_TOPBOTTOM_FIRE
        if self.topbottom_active:
            if self.recoil_cd > 0:
                self.recoil_cd -= 1
            self.fire_cd -= 1
            if self.fire_cd == 0:
                self.fire_cd = FIRE_INTERVAL
                idx = self.alloc()
                if self.fire_side == 0:
                    self.pool[idx] = [Y2_STORED, BULLET23_X, BULLET_HALF_CODE, BULLET_COLOR]
                else:
                    self.pool[idx] = [Y3_STORED, BULLET23_X, BULLET_HALF_CODE, BULLET_COLOR]
                self.recoil_side = self.fire_side
                self.recoil_cd = RECOIL_DURATION
                self.fire_side ^= 1
        self.row1_recoiled = self.recoil_cd > 0 and self.recoil_side == 0
        self.row4_recoiled = self.recoil_cd > 0 and self.recoil_side == 1


REST_ROW = [0, A, B, C, 0]
RECOIL_ROW = [0, 0, A, B, C]


def compare(z, sim, label):
    actual = pool_snapshot(z)
    if actual != sim.pool:
        for i in range(SLOT_COUNT):
            if actual[i] != sim.pool[i]:
                return False, (f"{label}: slot{i} actual={actual[i]} "
                                f"expected={sim.pool[i]}")
    if not sim.state2_formed:
        return True, ""
    r1 = cells(z, 1, 24, 5)
    r4 = cells(z, 4, 24, 5)
    exp_r1 = RECOIL_ROW if sim.row1_recoiled else REST_ROW
    exp_r4 = RECOIL_ROW if sim.row4_recoiled else REST_ROW
    if r1 != exp_r1:
        return False, f"{label}: row1(top wing) actual={r1} expected={exp_r1}"
    if r4 != exp_r4:
        return False, f"{label}: row4(bottom wing) actual={r4} expected={exp_r4}"
    return True, ""


# --- フルシーケンスの通しシミュレーション: bullet0の発射直後から ---
# 継続発射開始後300ティックまで、毎ティック実VRAM全16スロット+BG
# 反動セルをPython参照実装と完全一致するか検証する。
zf = fresh()
zf.pc = sym["INIT"]
run_until_pc(zf, sym["EBUZ_STATE1_BG_DONE"])
sim = Sim()
sim.fire_bullet0()

all_match = True
mismatch_detail = ""

zf.step()
run_until_pc(zf, sym["EBUZ_WAIT_TICK_DONE"])
sim.tick()
ok_i, detail = compare(zf, sim, "tick1 (bullet0 just displayed, holding)")
if not ok_i:
    all_match, mismatch_detail = False, detail

for i in range(2, WAIT_BEFORE_FIRE_TICKS + 1):
    zf.step()
    run_until_pc(zf, sym["EBUZ_WAIT_TICK_DONE"])
    sim.tick()
    if all_match:
        ok_i, detail = compare(zf, sim, f"tick{i} (bullet0 hold phase)")
        if not ok_i:
            all_match, mismatch_detail = False, detail

# ホールド終了(EBUZ_STATE1_DONE)、実際に飛び始める
run_until_pc(zf, sym["EBUZ_STATE1_DONE"])
sim.end_hold()
if all_match:
    ok_i, detail = compare(zf, sim, "at EBUZ_STATE1_DONE (hold just ended)")
    if not ok_i:
        all_match, mismatch_detail = False, detail

for i in range(1, WAIT_STATE1_TO_STATE2_TICKS + 1):
    zf.step()
    run_until_pc(zf, sym["EBUZ_WAIT_TICK_DONE"])
    sim.tick()
    if all_match:
        ok_i, detail = compare(zf, sim, f"state1->state2 wait tick{i}")
        if not ok_i:
            all_match, mismatch_detail = False, detail

run_until_pc(zf, sym["EBUZ_STATE2_BG_DONE"])
sim.state2_formed = True
if all_match:
    ok_i, detail = compare(zf, sim, "at EBUZ_STATE2_BG_DONE (BG transformed, bullets1/2 not fired yet)")
    if not ok_i:
        all_match, mismatch_detail = False, detail

for i in range(1, WAIT_BEFORE_FIRE_TICKS + 1):
    zf.step()
    run_until_pc(zf, sym["EBUZ_WAIT_TICK_DONE"])
    sim.tick()
    if all_match:
        ok_i, detail = compare(zf, sim, f"state2 pre-activation wait tick{i}")
        if not ok_i:
            all_match, mismatch_detail = False, detail

run_until_pc(zf, sym["EBUZ_STATE2_DONE"])
sim.activate_topbottom()
if all_match:
    ok_i, detail = compare(zf, sim, "at EBUZ_STATE2_DONE (continuous fire activated)")
    if not ok_i:
        all_match, mismatch_detail = False, detail

N_MAINLOOP_TICKS = 300
for i in range(1, N_MAINLOOP_TICKS + 1):
    zf.step()
    run_until_pc(zf, sym["EBUZ_FRAME_TICK"])
    sim.tick()
    if all_match:
        ok_i, detail = compare(zf, sim, f"mainloop tick{i}")
        if not ok_i:
            all_match, mismatch_detail = False, detail
            break

check(f"full-sequence simulation: bullet0 display->hold->fly->state2->"
      f"continuous fire ({N_MAINLOOP_TICKS} mainloop ticks) matches the "
      f"Python reference (Sim) byte-for-byte at every single tick "
      f"(covers the exact literal sequence the user specified: "
      f"\"まず初弾を表示、ホールド、発射、Ebuz2に変形、交互に発射\")"
      + (f" - MISMATCH: {mismatch_detail}" if not all_match else ""),
      all_match)

# --- (2026-09-14、実機フィードバック対応: "交互って言ったら平均に交互に ---
# 決まってんだろうが だれが画面内2発に制限しろって指示したんだよ")
# 直接の回帰テスト: 生存チェックに引っかかって発射を待つことは一切ない
# (=固定2ティックごとに無条件発射)ことと、その結果として画面内に
# 2発を大きく超える数のスプライトが同時に生きることを直接検証する。
zc = fresh()
zc.pc = sym["INIT"]
run_until_pc(zc, sym["EBUZ_STATE2_DONE"])
max_alive = 0
alive_history = []
for i in range(N_MAINLOOP_TICKS):
    zc.step()
    run_until_pc(zc, sym["EBUZ_FRAME_TICK"])
    alive = sum(1 for slot in pool_snapshot(zc) if slot[0] != SPR_HIDE_Y)
    alive_history.append(alive)
    max_alive = max(max_alive, alive)
check(f"continuous fire is NOT gated on the previous bullet's survival - "
      f"more than 2 bullets end up alive simultaneously on screen at some "
      f"point during {N_MAINLOOP_TICKS} ticks (peak observed: {max_alive} "
      f"alive) - directly refutes the \"画面内2発に制限\" bug pattern",
      max_alive > 2)

# --- 固定間隔の直接検証: 発射イベント(新規スロットの出現)の間隔が ---
# 常にEBUZ_FIRE_INTERVAL(2)ティックであること(弾の生死に一切左右
# されない、文字通りの"平均に交互")。
zi = fresh()
zi.pc = sym["INIT"]
run_until_pc(zi, sym["EBUZ_STATE2_DONE"])
prev_pool = pool_snapshot(zi)
fire_tick_numbers = []
for i in range(1, N_MAINLOOP_TICKS + 1):
    zi.step()
    run_until_pc(zi, sym["EBUZ_FRAME_TICK"])
    cur_pool = pool_snapshot(zi)
    # 「新しく生きた(非表示から生存に変わった)スロットがあるか」で発射を検出
    newly_alive = any(
        prev_pool[s][0] == SPR_HIDE_Y and cur_pool[s][0] != SPR_HIDE_Y
        for s in range(SLOT_COUNT)
    )
    if newly_alive:
        fire_tick_numbers.append(i)
    prev_pool = cur_pool
intervals = [fire_tick_numbers[i + 1] - fire_tick_numbers[i] for i in range(len(fire_tick_numbers) - 1)]
check(f"fire events occur at a perfectly fixed {FIRE_INTERVAL}-tick interval "
      f"throughout {N_MAINLOOP_TICKS} ticks, regardless of how many bullets "
      f"are still alive (\"交互って言ったら平均に交互に決まってんだろうが\") "
      f"- observed intervals: {set(intervals)}",
      len(intervals) >= 10 and all(iv == FIRE_INTERVAL for iv in intervals))

# --- ローテーションが実際に複数の異なる物理番号を巡回することの直接検証 ---
allocated_slots = set()
zj = fresh()
zj.pc = sym["INIT"]
run_until_pc(zj, sym["EBUZ_STATE2_DONE"])
prev_pool = pool_snapshot(zj)
for i in range(N_MAINLOOP_TICKS):
    zj.step()
    run_until_pc(zj, sym["EBUZ_FRAME_TICK"])
    cur_pool = pool_snapshot(zj)
    for s in range(SLOT_COUNT):
        if prev_pool[s][0] == SPR_HIDE_Y and cur_pool[s][0] != SPR_HIDE_Y:
            allocated_slots.add(s)
    prev_pool = cur_pool
check(f"physical slot allocation actually cycles through all {SLOT_COUNT} "
      f"pool slots over time (not stuck reusing a small fixed subset) - "
      f"observed slots used: {sorted(allocated_slots)}",
      allocated_slots == set(range(SLOT_COUNT)))


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
