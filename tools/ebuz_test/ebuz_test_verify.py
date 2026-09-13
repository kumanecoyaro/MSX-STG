"""tools/ebuz_test/ebuz_test.asm(新エネミー"Ebuz"のプロトタイプ)の
検証(2026-09-13)。専用の空SCREEN1環境でstate1出現→state2変化という
2状態だけを確認する、本編未組み込みの独立テスト。

tools/verify_*.py群と同じ「mini_z80asm.Assemblerで直接アセンブル+
run_until_pcの一回性検証スクリプト」の作法に倣う。
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


# ---------- bullets ("Okこれでいい ではEbuz1で登場した時に添付ファイルの弾を ----------
# 左へ発射 スプライトで で、Ebuz2に変化したら添付ファイルの16x8部分だけの
# スプライトを上下から発射 1つはY位置0px 2つ目は24pxの位置")、続けて
# (2026-09-13追記その2)"まずEbuz1の時の弾の位置を左へ16px移動 この状態で
# 0.5秒維持してから発射 次に...Yが0px、24pxの位置から同時発射...弾の速度
# が早いんで半分に"、さらに"同時発射はEbuz2に変形後な 同じく0.5秒維持して
# 同時発射"。さらに(2026-09-13追記その3、実機フィードバック対応)
# "だから違うって Ebuz1の時16x16のスプライトの弾を発射 その後Ebuz2に
# して上下から発射 人間の目がどうの関係ない お前は見えてないんだから
# 勝手に判断するな" - 前回の「タイミングが速すぎて見えない」という
# 自己診断は誤りで、実際はbullet0が発射後に全く動かないまま待ち続け、
# bullets1/2発射の瞬間に3発とも本体のそばに集まって見える構造的バグ
# だったと判明(ebuz_test.asmのEBUZ_TICK/EBUZ_WAIT_TICKS参照)。
SPRATR = 0x1B00
BULLET_FULL_CODE = sym["BULLET_FULL_CODE"]
BULLET_HALF_CODE = sym["BULLET_HALF_CODE"]
BULLET_COLOR = sym["EBUZ_BULLET_COLOR"]
BULLET1_X = sym["EBUZ_BULLET1_X"]   # state1弾: 192-16=176
BULLET23_X = sym["EBUZ_BULLET_X"]   # state2弾2枚: 192のまま
# (2026-09-13追記その5/その6/その7、実機フィードバック対応: "ようやく
# かよ 弾遅いんで速くしてくれ 2pxで"→"遅いな6pxで"→"8pxで") 1px/2px
# 交互(平均1.5px/frame)方式を撤回し単純な固定速度へ、最終的に8px/frame。
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
SENTINEL = 0x0000  # never real code - safe return trap (see tools/verify_sound_duty_cycle.py)

# --- (2026-09-13追記その4、実機フィードバック対応: "で、Ebuz2の弾は2つ ---
# とも8px下げろ 絶対位置でやりやがって 当たり前だが相対位置に決まって
# んだろうが") bullets1/2's Y is now derived from the actual state2 wing
# band row numbers (EBUZ_ROW_TOP_BAND=1/EBUZ_ROW_BOTTOM_BAND=4, i.e.
# desired Y=8/32 - matching where EBUZ_ROW_0ABC is actually drawn in the
# BG, not an arbitrary absolute value), not the original literal 0px/24px.
# Pin the literal numbers directly (not just self-consistency with the
# formula) to guard against silently drifting back to an unrelated
# absolute value.
check("EBUZ_ROW_TOP_BAND(1)/EBUZ_ROW_BOTTOM_BAND(4) match the actual BG row "
      "numbers used for the wing bands (row1/row4, see EBUZ_STATE2_BG_DONE's "
      "own LDIRVM destinations 01838h/01898h)",
      sym["EBUZ_ROW_TOP_BAND"] == 1 and sym["EBUZ_ROW_BOTTOM_BAND"] == 4)
check(f"bullet1's desired Y is exactly 8px (top wing band's row, stored="
      f"{Y2_STORED}) and bullet2's is exactly 32px (bottom wing band's row, "
      f"stored={Y3_STORED}) - both 8px lower than the original literal "
      f"0px/24px, and both relative to the body's own wing rows now",
      Y2_STORED == 7 and Y3_STORED == 31)


def sprite_attr(z, slot):
    base = SPRATR + slot * 4
    return [z.vram[base + i] for i in range(4)]


def simulate_positions(x_list, n_iters):
    """Python参照実装: EBUZ_TICKの固定速度移動(EBUZ_BULLET_SPEED=2px/
    frame、2026-09-13追記その5で1px/2px交互方式から単純化)を
    シミュレートする。引数x_listの各要素を同じフレームスケジュールで
    同時に進める。戻り値は各弾の(最終X, 非表示になったか)のリスト。"""
    xs = list(x_list)
    hidden = [False] * len(xs)
    for _ in range(n_iters):
        for i in range(len(xs)):
            if hidden[i]:
                continue
            if xs[i] < SPEED:
                hidden[i] = True
            else:
                xs[i] -= SPEED
    return list(zip(xs, hidden))


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
# 3.58MHz (unrelated to the actual bug this round - see below - but still
# a meaningful sanity check that per-tick pacing hasn't regressed to the
# old ~0.00115s that made movement itself flash by too fast to see).
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

# --- at the exact PC boundary right after BG draw but before the display+hold ---
# code runs, bullet0 is still in its boot-time hidden state (this is the
# instant right before "display, then hold" - see the dedicated hold-time
# tests further below for the corrected post-display behavior).
z0 = fresh()
z0.pc = sym["INIT"]
run_until_pc(z0, sym["EBUZ_STATE1_BG_DONE"])
check("state1: at the PC boundary right after BG is drawn (before the "
      "display+hold code runs), bullet0 is still in its boot-time hidden "
      "state",
      sprite_attr(z0, 0)[0] == SPR_HIDE_Y)

# --- an actual ~29-tick wait really elapses between "BG done" and "fired" ---
# (guards against a regression where the labels are in the right order but
# the CALL EBUZ_WAIT_TICKS itself is missing/short-circuited - a check that
# only compares PC label order can't catch that, since label position doesn't
# move even if the wait call in between is deleted).
WAIT_BEFORE_FIRE_TICKS = 29
WAIT_STATE1_TO_STATE2_TICKS = 102
gap1 = run_until_pc_count(z0, sym["EBUZ_STATE1_DONE"])
check(f"state1: the BG-done -> fired gap actually spends roughly "
      f"{WAIT_BEFORE_FIRE_TICKS} EBUZ_TICK's worth of steps "
      f"({gap1} >= {one_tick_steps}*{WAIT_BEFORE_FIRE_TICKS}*0.9), not just a "
      f"few instructions",
      gap1 >= one_tick_steps * WAIT_BEFORE_FIRE_TICKS * 0.9)

# --- state1 fires exactly 1 bullet (BULLET_FULL, slot0) after the 0.5s wait; ---
# slots1/2 stay hidden. Firing X is now 16px left of the old placeholder.
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["EBUZ_STATE1_DONE"])
check("EBUZ_BULLET1_X is exactly 16px left of EBUZ_BULLET_X (the shared base/"
      "state2 X), not just equal to it - pins the actual numeric relationship "
      "the user asked for rather than trusting the symbol names alone",
      BULLET1_X == BULLET23_X - 16)
check("state1: bullet0(slot0) fired as BULLET_FULL at Y=16,X=176 (16px left of "
      "the old X=192 placeholder, per \"Ebuz1の時の弾の位置を左へ16px移動\") "
      "with the attached art's own color(11)",
      sprite_attr(z, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
check("state1: bullet1(slot1) not fired yet (still hidden)", sprite_attr(z, 1)[0] == SPR_HIDE_Y)
check("state1: bullet2(slot2) not fired yet (still hidden)", sprite_attr(z, 2)[0] == SPR_HIDE_Y)
check("SAT terminator (slot3) written once at boot", sprite_attr(z, 3)[0] == SPR_TERM_Y)
check("BULLET_FULL's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z.vram[0x3800 + BULLET_FULL_CODE * 8 + i] for i in range(32)))
check("BULLET_HALF's sprite pattern actually loaded into SPRPAT (non-blank)",
      any(z.vram[0x3800 + BULLET_HALF_CODE * 8 + i] for i in range(32)))
# NOTE: ebuz_test.asm sets 16x16 sprite mode via the WRTVDP BIOS call
# (0047h), which tools/z80emu.py implements as a pure no-op stub (register
# state not tracked) - so z.vdp_regs never gains an entry for R1 this way.
# Verify indirectly instead: RG1SAV (the BIOS RAM mirror WRTVDP is
# documented to update) must show bit1 set, since ebuz_test.asm ORs it in
# before the WRTVDP call.
check("16x16 sprite size mode enabled (RG1SAV mirror bit1/SI set)",
      z.mem[sym["RG1SAV"]] & 0x02 != 0)

# --- CRITICAL regression test for the actual reported bug ("今は全て同時に ---
# 発射してるし"): during the wait between bullet0 firing and Ebuz2 forming,
# bullet0 must keep moving (not sit frozen) - verified against the same
# fixed-speed simulation used elsewhere in this file.
(exp_bg2_x, exp_bg2_hidden) = simulate_positions([BULLET1_X], WAIT_STATE1_TO_STATE2_TICKS)[0]
z1b = fresh()
z1b.pc = sym["INIT"]
run_until_pc(z1b, sym["EBUZ_STATE2_BG_DONE"])
# at 2px/frame, bullet0 (starting at X=176) has already gone fully off-screen
# well before this 102-tick wait completes (hides at tick 88) - so "kept
# moving instead of sitting frozen" now shows up as "already hidden", not as
# some intermediate X value. Either way, it must match the simulation exactly.
if exp_bg2_hidden:
    bullet0_bg2_ok = sprite_attr(z1b, 0)[0] == SPR_HIDE_Y
else:
    bullet0_bg2_ok = sprite_attr(z1b, 0) == [Y1_STORED, exp_bg2_x, BULLET_FULL_CODE, BULLET_COLOR]
check(f"state2: bullet0 has kept moving during the state1-to-state2 wait "
      f"({WAIT_STATE1_TO_STATE2_TICKS} ticks) instead of sitting frozen next "
      f"to the body - simulation says X={exp_bg2_x}/hidden={exp_bg2_hidden}, "
      f"matches actual VRAM exactly",
      bullet0_bg2_ok)
check("state2: right after the BG transforms (before the 0.5s wait), bullets1/2 "
      "have NOT fired yet (still hidden) - proves the transform-then-wait-then-"
      "fire ordering (\"Ebuz2に変形後...0.5秒維持して\")",
      sprite_attr(z1b, 1)[0] == SPR_HIDE_Y and sprite_attr(z1b, 2)[0] == SPR_HIDE_Y)

gap2 = run_until_pc_count(z1b, sym["EBUZ_STATE2_DONE"])
check(f"state2: the transform-done -> activation gap actually spends roughly "
      f"{WAIT_BEFORE_FIRE_TICKS} EBUZ_TICK's worth of steps "
      f"({gap2} >= {one_tick_steps}*{WAIT_BEFORE_FIRE_TICKS}*0.9), not just a "
      f"few instructions",
      gap2 >= one_tick_steps * WAIT_BEFORE_FIRE_TICKS * 0.9)

# --- (2026-09-13追記その7、実機フィードバック対応: "初弾のホールドタイム ---
# はで、上下弾は交互に撃ち続けろ 2フレ交代 打つときは反動を見せたいんで
# 上下の3セル分を1セル右に 打ったら元位置に戻せ")。EBUZ_STATE2_DONEは
# もはや「bullets1/2が発射済み」ではなく「継続発射モードを起動した」
# 時点を指す(初弾は次のEBUZ_TICKで発射される) - この意味変更を
# 反映して以降のテストを全面的に書き直す。
check("bullet0 is already off-screen (Y=SPR_HIDE_Y) by the moment continuous "
      "fire activates - the state1 bullet and the state2 volley are visually "
      "separated, not bunched together at the body",
      simulate_positions([BULLET1_X], WAIT_STATE1_TO_STATE2_TICKS + WAIT_BEFORE_FIRE_TICKS)[0][1])

FIRE_INTERVAL = sym["EBUZ_FIRE_INTERVAL"]
RECOIL_DURATION = sym["EBUZ_RECOIL_DURATION"]
check(f"EBUZ_FIRE_INTERVAL is exactly 2 (\"2フレ交代\") and "
      f"EBUZ_RECOIL_DURATION is 1 (recoil shows for 1 tick then reverts, "
      f"per \"打ったら元位置に戻せ\")",
      FIRE_INTERVAL == 2 and RECOIL_DURATION == 1)


def simulate_topbottom(n_ticks):
    """Python参照実装(2026-09-13追記その8で全面書き直し): "撃った弾は
    画面外に消えるまで戻さねえ"を反映した新設計を、EBUZ_UPDATE_
    TOPBOTTOM_FIREの実行順序(上側反動リバート→下側反動リバート→
    上側「非表示なら即再発射」→下側「初回だけ位相差、以後は同じ規則」
    の順)通りに1ティックずつシミュレートする。生きている弾(非表示に
    なっていない弾)には一切触れない - リセットは「非表示になった
    その瞬間」にのみ発生する。戻り値は各ティック後の(bullet1_x,
    bullet1_hidden, bullet2_x, bullet2_hidden, row1_recoiled,
    row4_recoiled)のリスト。"""
    b1_x, b1_hidden = None, True
    b2_x, b2_hidden = None, True
    top_recoil_cd = 0
    bottom_recoil_cd = 0
    bottom_arm = FIRE_INTERVAL
    history = []
    for _ in range(n_ticks):
        # EBUZ_UPDATE_BULLET(スロット1,2) - 生きている弾だけ移動
        if not b1_hidden:
            if b1_x < SPEED:
                b1_hidden = True
            else:
                b1_x -= SPEED
        if not b2_hidden:
            if b2_x < SPEED:
                b2_hidden = True
            else:
                b2_x -= SPEED
        # EBUZ_UPDATE_TOPBOTTOM_FIRE
        if top_recoil_cd > 0:
            top_recoil_cd -= 1
        if bottom_recoil_cd > 0:
            bottom_recoil_cd -= 1
        if b1_hidden:
            b1_x, b1_hidden = BULLET23_X, False
            top_recoil_cd = RECOIL_DURATION
        if bottom_arm > 0:
            bottom_arm -= 1
        elif b2_hidden:
            b2_x, b2_hidden = BULLET23_X, False
            bottom_recoil_cd = RECOIL_DURATION
        row1_recoiled = top_recoil_cd > 0
        row4_recoiled = bottom_recoil_cd > 0
        history.append((b1_x, b1_hidden, b2_x, b2_hidden, row1_recoiled, row4_recoiled))
    return history


REST_ROW = [0, sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"], 0]
RECOIL_ROW = [0, 0, sym["EBUZ_CODE_A"], sym["EBUZ_CODE_B"], sym["EBUZ_CODE_C"]]

z2 = fresh()
z2.pc = sym["INIT"]
run_until_pc(z2, sym["EBUZ_STATE2_DONE"])
N_TICKS = 40  # 192/SPEED(8)=24ティックで画面横断するので、再発射・位相差の維持まで検証する
sim_history = simulate_topbottom(N_TICKS)
all_match = True
mismatch_detail = ""
for i in range(N_TICKS):
    z2.step()
    run_until_pc(z2, sym["EBUZ_FRAME_TICK"])
    exp_b1x, exp_b1h, exp_b2x, exp_b2h, exp_r1, exp_r4 = sim_history[i]
    b1 = sprite_attr(z2, 1)
    b2 = sprite_attr(z2, 2)
    b1_ok = (b1[0] == SPR_HIDE_Y) if exp_b1h else (b1 == [Y2_STORED, exp_b1x, BULLET_HALF_CODE, BULLET_COLOR])
    b2_ok = (b2[0] == SPR_HIDE_Y) if exp_b2h else (b2 == [Y3_STORED, exp_b2x, BULLET_HALF_CODE, BULLET_COLOR])
    r1 = cells(z2, 1, 24, 5)
    r4 = cells(z2, 4, 24, 5)
    r1_ok = r1 == (RECOIL_ROW if exp_r1 else REST_ROW)
    r4_ok = r4 == (RECOIL_ROW if exp_r4 else REST_ROW)
    if not (b1_ok and b2_ok and r1_ok and r4_ok):
        all_match = False
        mismatch_detail = (f"tick{i+1}: bullet1 actual={b1} b2 actual={b2} "
                            f"r1={r1} r4={r4} vs sim b1x={exp_b1x}/h={exp_b1h} "
                            f"b2x={exp_b2x}/h={exp_b2h} r1_recoil={exp_r1} r4_recoil={exp_r4}")
        break
check(f"continuous top/bottom fire (\"撃った弾は画面外に消えるまで戻さねえ\" - "
      f"each slot refires only the instant it naturally goes off-screen, "
      f"never mid-flight, with the initial 2-tick phase offset preserved "
      f"forever) + recoil animation matches the Python reference simulation "
      f"exactly over {N_TICKS} ticks (spans multiple full screen-crossings "
      f"at SPEED={SPEED})"
      + (f" - MISMATCH: {mismatch_detail}" if not all_match else ""),
      all_match)

# --- (2026-09-13追記その8、実機フィードバック対応: "しかもお前ホールド ---
# タイムをBuz1で打った後に入れてるじゃねえか 弾を表示してホールドだって
# 言っただろが") bullet0はEbuz1出現と同時に表示され、その位置で0.5秒
# 静止(ホールド)してから初めて実際に飛び始める - 旧実装(非表示のまま
# 待ってから表示)とは正反対の順序。
zh = fresh()
zh.pc = sym["INIT"]
run_until_pc(zh, sym["EBUZ_STATE1_BG_DONE"])
zh.step()
run_until_pc(zh, sym["EBUZ_WAIT_TICK_DONE"])
check("bullet0 is DISPLAYED (visible, not hidden) from the very first tick "
      "after Ebuz1's BG appears, at its final X=176 position already - not "
      "hidden-then-appearing-later",
      sprite_attr(zh, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
for _ in range(WAIT_BEFORE_FIRE_TICKS - 1):
    zh.step()
    run_until_pc(zh, sym["EBUZ_WAIT_TICK_DONE"])
check(f"bullet0 stays perfectly still (X unchanged) through the entire "
      f"{WAIT_BEFORE_FIRE_TICKS}-tick hold - it's holding position, not "
      f"flying yet",
      sprite_attr(zh, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
run_until_pc(zh, sym["EBUZ_STATE1_DONE"])
check("at EBUZ_STATE1_DONE (hold just ended), bullet0 is still exactly at "
      "its held position (hasn't jumped or moved yet this instant)",
      sprite_attr(zh, 0) == [Y1_STORED, BULLET1_X, BULLET_FULL_CODE, BULLET_COLOR])
zh.step()
run_until_pc(zh, sym["EBUZ_WAIT_TICK_DONE"])
zh.step()
run_until_pc(zh, sym["EBUZ_WAIT_TICK_DONE"])
zh.step()
run_until_pc(zh, sym["EBUZ_WAIT_TICK_DONE"])
check(f"after the hold ends, bullet0 actually starts flying (moved left by "
      f"3*{SPEED}px={3*SPEED}px over 3 ticks)",
      sprite_attr(zh, 0)[1] == BULLET1_X - 3 * SPEED)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
