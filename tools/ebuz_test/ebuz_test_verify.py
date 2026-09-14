"""tools/ebuz_test/ebuz_test.asm(新エネミー"Ebuz"のプロトタイプ)の
検証(2026-09-13〜14)。専用の空SCREEN1環境でstate1出現→state2変化→
継続発射という一連の流れを確認する、本編未組み込みの独立テスト。

tools/verify_*.py群と同じ「mini_z80asm.Assemblerで直接アセンブル+
run_until_pcの一回性検証スクリプト」の作法に倣う。

(2026-09-14追記、"弾をBGに変更 8px移動だからスプライトの意味がない
からな"を受けた全面書き直し): 弾がHWスプライト(Y/X/pattern/colorの
4byte属性)からBGタイル(name table上の列番号1byteのみ)へ変わったため、
検証方法も「SPRATRを読む」方式から「NAMTBLの該当セルを読む」方式へ
全面的に書き直した。Python参照実装(Sim)も列(0-31)ベースの移動
モデルに合わせて再設計している。
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


def count_marker_hits(z, target_pc, marker_pc, max_instr=2_000_000):
    """target_pcへ到達するまでの間にmarker_pcを何回通過したかを正確に
    数える(2026-09-14追記: "2回目のホールドを30フレに"対応で自己発見。
    以前の「1tickあたりのステップ数[fresh()な全ゼロRAM状態で単発CALL
    測定]で割って丸める」方式は、実際の待ちループ中は各プールスロットが
    EBUZ_SLOT_EMPTY[255]で初期化済みなのに対し、fresh()の全ゼロRAMでは
    スロット値が0[=有効な列0として誤って"使用中"扱い]になり単発測定の
    コストが実際より高く出るため、tick数が大きくなるほど誤差が蓄積し
    丸め込みが破綻する[15ティックでは偶然セーフだったが30ティックで
    29と誤判定された]。ループの目印ラベル[EBUZ_WAIT_TICK_DONE]の
    実通過回数を直接数える、近似に頼らない厳密な方式に変更した)。"""
    count = 0
    for _ in range(max_instr):
        if z.pc == target_pc:
            return count
        if z.pc == marker_pc:
            count += 1
        z.step()
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


# ---------- bullets (2026-09-14, BG-based) ----------
BULLET_L_CODE = sym["BULLET_L_CODE"]
BULLET_R_CODE = sym["BULLET_R_CODE"]
BULLET1_COL = sym["EBUZ_BULLET1_COL"]     # state1弾の発射列(22)
BULLET23_COL = sym["EBUZ_BULLET23_COL"]   # state2継続弾の発射列(23)
EMPTY = sym["EBUZ_SLOT_EMPTY"]
FIRE_INTERVAL = sym["EBUZ_FIRE_INTERVAL"]
RECOIL_DURATION = sym["EBUZ_RECOIL_DURATION"]
LANE_POOL_SIZE = sym["EBUZ_LANE_POOL_SIZE"]
SENTINEL = 0x0000  # never real code - safe return trap (see tools/verify_sound_duty_cycle.py)

check("EBUZ_BULLET23_COL matches EBUZ_BULLET1_COL at col22 (2 columns left "
      "of the old sprite-era X=192/col24), keeping both bullet kinds fully "
      "clear of the wing band's col24-28 decorative cells at every tick - "
      "not just \"usually blank\" but structurally non-overlapping (an "
      "earlier col23 choice was tried and reverted after self-testing found "
      "a same-tick write-order race with the wing band's own recoil write)",
      BULLET23_COL == 22 and BULLET1_COL == 22)
check("EBUZ_ROW_TOP_BAND(1)/EBUZ_ROW_BOTTOM_BAND(4) match the actual BG row "
      "numbers used for the wing bands",
      sym["EBUZ_ROW_TOP_BAND"] == 1 and sym["EBUZ_ROW_BOTTOM_BAND"] == 4)
check("EBUZ_FIRE_INTERVAL is exactly 2 (\"2フレ交代\") and "
      "EBUZ_RECOIL_DURATION is 1 (recoil shows for 1 tick then reverts, "
      "per \"打ったら元位置に戻せ\")",
      FIRE_INTERVAL == 2 and RECOIL_DURATION == 1)
check("EBUZ_LANE_POOL_SIZE is exactly 8 per lane (top/bottom independent "
      "pools, each sized above the ~6 bullets that can be simultaneously "
      "alive per lane under fixed 2-tick-combined/4-tick-per-lane fire)",
      LANE_POOL_SIZE == 8)


def read_lane(z, row, col_addr_base):
    """指定した行(row)を、プール配列(col_addr_base、EBUZ_LANE_POOL_SIZE
    byte)の現在値それぞれについて、そのセル位置(左/右2セル)を実VRAMから
    読み出す。戻り値は各スロットの(col, [left_code, right_code])の
    リスト(非アクティブなスロットは(EMPTY, None)))。"""
    out = []
    for i in range(LANE_POOL_SIZE):
        col = z.mem[col_addr_base + i]
        if col == EMPTY:
            out.append((EMPTY, None))
        else:
            out.append((col, cells(z, row, col, 2)))
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

# (2026-09-14、実機フィードバック対応: "初弾撃った後のウェイト 2重に
# ウェイトしてるだろ 初弾ホールドを10フレ 一斉発射は15フレのホールドに
# 変更 それ以外のウェイトは入れるな"): 旧来の3段ウェイト(29/102/29)を
# 廃止し、初弾ホールド10ティック・state2形成後の一斉発射前ホールド15
# ティックの2箇所のみに削減した。state1完了→state2 BG形成の間には
# もうウェイトが一切無い(BG書き込みのみの数命令)ことも直接検証する。
# 続けて同日"2回目のホールドを30フレに"でTOPBOTTOM_HOLD_TICKSを
# 15→30へ再変更。
BULLET0_HOLD_TICKS = 10
TOPBOTTOM_HOLD_TICKS = 30

z0 = fresh()
z0.pc = sym["INIT"]
run_until_pc(z0, sym["EBUZ_STATE1_BG_DONE"])
gap1_ticks = count_marker_hits(z0, sym["EBUZ_STATE1_DONE"], sym["EBUZ_WAIT_TICK_DONE"])
check(f"state1: the BG-done -> fired gap passes EBUZ_WAIT_TICK_DONE "
      f"(one full EBUZ_TICK iteration inside EBUZ_WAIT_TICKS) exactly "
      f"{BULLET0_HOLD_TICKS} times, not more and not less "
      f"({gap1_ticks} observed) - counting the actual loop-marker passes "
      f"directly (rather than a step-count/baseline-tick-cost ratio, which "
      f"drifts as the tick count grows) avoids both a hold that's too LONG "
      f"(e.g. an unreverted 29) and the rounding-drift false negative this "
      f"same approximation hit once TOPBOTTOM_HOLD_TICKS grew to 30",
      gap1_ticks == BULLET0_HOLD_TICKS)

z1b = fresh()
z1b.pc = sym["INIT"]
run_until_pc(z1b, sym["EBUZ_STATE1_DONE"])
gap2 = run_until_pc_count(z1b, sym["EBUZ_STATE2_BG_DONE"])
check(f"state1-to-state2 gap has NO wait at all anymore (\"それ以外の "
      f"ウェイトは入れるな\") - costs far less than a single EBUZ_TICK's "
      f"worth of steps ({gap2} < {one_tick_steps}), just the BG-writing "
      f"instructions themselves",
      gap2 < one_tick_steps)

gap3_ticks = count_marker_hits(z1b, sym["EBUZ_STATE2_DONE"], sym["EBUZ_WAIT_TICK_DONE"])
check(f"state2-BG-done -> activation gap passes EBUZ_WAIT_TICK_DONE exactly "
      f"{TOPBOTTOM_HOLD_TICKS} times, not more and not less "
      f"({gap3_ticks} observed)",
      gap3_ticks == TOPBOTTOM_HOLD_TICKS)

check("BULLET_L/R's BG tile patterns actually loaded into the VRAM pattern "
      "generator (non-blank bitmaps)",
      any(z0.vram[BULLET_L_CODE * 8 + i] for i in range(8)) and
      any(z0.vram[BULLET_R_CODE * 8 + i] for i in range(8)))


# ============================================================================
# Sim: Python参照実装(2026-09-14、BG化に伴う全面書き直し)
#
# 弾は列(0-31)のみで表現し、1ティックごとに1列(=8px)ずつ左へ移動する。
# 初弾(bullet0)は単一インスタンス(2行x2列)、継続発射(上/下)は
# レーンごとの独立プール(EBUZ_LANE_POOL_SIZE個、ローテーション割当)。
# ASMの実行順序(EBUZ_TICK: 初弾更新→上プール更新→下プール更新→
# [アクティブなら]EBUZ_UPDATE_TOPBOTTOM_FIRE[反動リバート→発射
# カウントダウン→0なら無条件発射])を厳密に再現する。
# ============================================================================
class Sim:
    def __init__(self):
        self.b0_active = False
        self.b0_holding = False
        self.b0_col = None
        self.top_pool = [None] * LANE_POOL_SIZE   # None=空、int=現在の列
        self.bottom_pool = [None] * LANE_POOL_SIZE
        self.top_next = 0
        self.bottom_next = 0
        self.fire_side = 0
        self.fire_cd = 0
        self.recoil_side = 0
        self.recoil_cd = 0
        self.topbottom_active = False
        self.row1_recoiled = False
        self.row4_recoiled = False
        self.state2_formed = False  # row1/row4 wing-band cells don't exist until state2's BG transform

    def fire_bullet0(self):
        self.b0_active = True
        self.b0_holding = True
        self.b0_col = BULLET1_COL

    def end_hold(self):
        self.b0_holding = False

    def activate_topbottom(self):
        self.fire_side = 0
        self.fire_cd = 1
        self.topbottom_active = True

    def _alloc(self, pool, next_attr):
        idx = getattr(self, next_attr)
        setattr(self, next_attr, (idx + 1) % LANE_POOL_SIZE)
        pool[idx] = BULLET23_COL

    def tick(self):
        # bullet0
        if self.b0_active and not self.b0_holding:
            if self.b0_col == 0:
                self.b0_active = False
            else:
                self.b0_col -= 1
        # top/bottom pools: each active slot moves left by 1 column,
        # deactivating once it would go below column 0.
        for pool in (self.top_pool, self.bottom_pool):
            for i in range(LANE_POOL_SIZE):
                if pool[i] is None:
                    continue
                if pool[i] == 0:
                    pool[i] = None
                else:
                    pool[i] -= 1
        # EBUZ_UPDATE_TOPBOTTOM_FIRE
        if self.topbottom_active:
            if self.recoil_cd > 0:
                self.recoil_cd -= 1
            self.fire_cd -= 1
            if self.fire_cd == 0:
                self.fire_cd = FIRE_INTERVAL
                if self.fire_side == 0:
                    self._alloc(self.top_pool, "top_next")
                else:
                    self._alloc(self.bottom_pool, "bottom_next")
                self.recoil_side = self.fire_side
                self.recoil_cd = RECOIL_DURATION
                self.fire_side ^= 1
        self.row1_recoiled = self.recoil_cd > 0 and self.recoil_side == 0
        self.row4_recoiled = self.recoil_cd > 0 and self.recoil_side == 1


REST_ROW = [0, A, B, C, 0]
RECOIL_ROW = [0, 0, A, B, C]


def pool_cells(sim_pool):
    """sim側のプール(列番号のリスト)を、期待される(左セル,右セル)の
    集合(順不同 - ローテーション割当の物理的な並び順はASM/Sim間で
    一致している必要はなく、"どの列にどの絵が出ているか"だけが
    観測可能な仕様なので、集合として比較する)へ変換する。"""
    return sorted(c for c in sim_pool if c is not None)


def actual_lane_cols(z, row, col_addr_base):
    cols = []
    for i in range(LANE_POOL_SIZE):
        c = z.mem[col_addr_base + i]
        if c != EMPTY:
            cols.append(c)
    return sorted(cols)


def compare(z, sim, label):
    if sim.b0_active:
        exp_cells = [BULLET_L_CODE, BULLET_R_CODE]
        actual2 = cells(z, 2, sim.b0_col, 2)
        actual3 = cells(z, 3, sim.b0_col, 2)
        if actual2 != exp_cells or actual3 != exp_cells:
            return False, (f"{label}: bullet0 at col{sim.b0_col} "
                            f"row2={actual2} row3={actual3} expected={exp_cells}")
    top_exp = pool_cells(sim.top_pool)
    top_actual = actual_lane_cols(z, sym["EBUZ_ROW_TOP_BAND"], sym["EBUZ_TOP_COLS"])
    if top_exp != top_actual:
        return False, f"{label}: top lane columns actual={top_actual} expected={top_exp}"
    for col in top_actual:
        got = cells(z, sym["EBUZ_ROW_TOP_BAND"], col, 2)
        if got != [BULLET_L_CODE, BULLET_R_CODE]:
            return False, f"{label}: top bullet at col{col} has wrong tiles {got}"
    bottom_exp = pool_cells(sim.bottom_pool)
    bottom_actual = actual_lane_cols(z, sym["EBUZ_ROW_BOTTOM_BAND"], sym["EBUZ_BOTTOM_COLS"])
    if bottom_exp != bottom_actual:
        return False, f"{label}: bottom lane columns actual={bottom_actual} expected={bottom_exp}"
    for col in bottom_actual:
        got = cells(z, sym["EBUZ_ROW_BOTTOM_BAND"], col, 2)
        if got != [BULLET_L_CODE, BULLET_R_CODE]:
            return False, f"{label}: bottom bullet at col{col} has wrong tiles {got}"
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
# 継続発射開始後300ティックまで、毎ティック実VRAM(初弾+上下プール+BG
# 反動セル)をPython参照実装と完全一致するか検証する。
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

for i in range(2, BULLET0_HOLD_TICKS + 1):
    zf.step()
    run_until_pc(zf, sym["EBUZ_WAIT_TICK_DONE"])
    sim.tick()
    if all_match:
        ok_i, detail = compare(zf, sim, f"tick{i} (bullet0 hold phase)")
        if not ok_i:
            all_match, mismatch_detail = False, detail

run_until_pc(zf, sym["EBUZ_STATE1_DONE"])
sim.end_hold()
if all_match:
    ok_i, detail = compare(zf, sim, "at EBUZ_STATE1_DONE (hold just ended)")
    if not ok_i:
        all_match, mismatch_detail = False, detail

# state1->state2は"それ以外のウェイトは入れるな"によりノーウェイトへ
# 変更済み - EBUZ_TICKを1回も挟まずBG書き込みのみで直接到達する。
run_until_pc(zf, sym["EBUZ_STATE2_BG_DONE"])
sim.state2_formed = True
if all_match:
    ok_i, detail = compare(zf, sim, "at EBUZ_STATE2_BG_DONE (BG transformed, bullets1/2 not fired yet)")
    if not ok_i:
        all_match, mismatch_detail = False, detail

for i in range(1, TOPBOTTOM_HOLD_TICKS + 1):
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
      f"(covers the exact literal sequence: \"まず初弾を表示、ホールド、"
      f"発射、Ebuz2に変形、交互に発射\")"
      + (f" - MISMATCH: {mismatch_detail}" if not all_match else ""),
      all_match)

# --- 直接の回帰テスト: 生存チェックに引っかかって発射を待つことは ---
# 一切ない(=固定2ティックごとに無条件発射)ことと、その結果として
# 画面内に2発を大きく超える数の弾が同時に生きることを直接検証する。
zc = fresh()
zc.pc = sym["INIT"]
run_until_pc(zc, sym["EBUZ_STATE2_DONE"])
max_alive = 0
for i in range(N_MAINLOOP_TICKS):
    zc.step()
    run_until_pc(zc, sym["EBUZ_FRAME_TICK"])
    alive = (
        sum(1 for x in range(LANE_POOL_SIZE) if zc.mem[sym["EBUZ_TOP_COLS"] + x] != EMPTY) +
        sum(1 for x in range(LANE_POOL_SIZE) if zc.mem[sym["EBUZ_BOTTOM_COLS"] + x] != EMPTY)
    )
    max_alive = max(max_alive, alive)
check(f"continuous fire is NOT gated on the previous bullet's survival - "
      f"more than 2 bullets end up alive simultaneously on screen at some "
      f"point during {N_MAINLOOP_TICKS} ticks (peak observed: {max_alive} "
      f"alive)",
      max_alive > 2)

# --- BGタイルが実際に翼帯の装飾セル(col24-28)を破壊しないことの ---
# 直接検証: 弾が翼帯の行(row1/row4)を何度も通過した後でも、col25-28
# (弾の右端col24より右)は常にREST/RECOIL のどちらか正しい値のままで
# あること(既にcompare()内で毎ティック検証済みだが、ここでは特に
# 「弾がその列を通過した直後」を狙い撃ちして再確認する)。
zd = fresh()
zd.pc = sym["INIT"]
run_until_pc(zd, sym["EBUZ_STATE2_DONE"])
wing_intact = True
for i in range(N_MAINLOOP_TICKS):
    zd.step()
    run_until_pc(zd, sym["EBUZ_FRAME_TICK"])
    r1 = cells(zd, 1, 25, 3)  # col25-27 = A,B,C(REST) or shifted(RECOIL)
    r4 = cells(zd, 4, 25, 3)
    if r1 not in ([A, B, C], [0, A, B]) or r4 not in ([A, B, C], [0, A, B]):
        wing_intact = False
        break
check("bullets passing through the wing band row never corrupt the wing "
      "band's own A/B/C decorative cells (col25-27) - the bullet's right "
      "edge (col24) always lands on a cell that's blank in both REST and "
      "RECOIL states",
      wing_intact)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
