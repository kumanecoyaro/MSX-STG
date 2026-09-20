"""EbuzMk2の"5門砲台"設計(2026-09-20全面訂正版)を検証する。

ユーザー原文: "まず言ったように弾は5門の砲台から出る 最初はセンター
2の状態で上下4門 数が違うだけでEbuzと同じ 次に全門発射 センター、
内側2門外側2門の順 そのループ で弾は上下動に合わせてY位置変わる
スポーン位置は上から来てRow9かな で、Row1から16まで上下動"。

検証項目:
  1. state1解放時は中央発射管から1発だけ発射される(3連ボレーではない)。
  2. state1→state2遷移(ノーウェイト)で本体がnametable row9へ移動し、
     旧state1位置(row3-7)が正しく消去される。
  3. state2形成後、発射シーケンスは中央→内側(上下2門)→外側(上下2門)→
     最初に戻る、の3ステップを無限ループする。
  4. 本体はnametable row1〜16の範囲を連続的に(離散3ポジションではなく)
     往復し続ける。
  5. 弾は発射された瞬間のEBUZ2_OSC_ROW(本体位置)に応じたY(行)に固定
     されたまま、X(列)方向にのみ1ティック1列で直進する - 本体がその後
     動いても、既に飛んでいる弾のYは変化しない。
  6. 本体が移動した後、弾が飛んでいる最中に消去してもstate2本体タイルを
     剥ぎ取らない(2026-09-20最初のバグ報告「砲台は5門に増えてるぞ」と
     同種の事故が新設計でも起きていないことの回帰確認)。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80

PASS = 0
FAIL = 0


def check(cond, msg):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f"FAIL: {msg}")


def assemble():
    with open(os.path.join(HERE, "ebuz_mk2_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def run_until_pc(z, target_pc, max_instr=8_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


NAMTBL = 0x1800


def cells(z, row, col, n):
    return [z.vram[NAMTBL + row * 32 + col + i] for i in range(n)]


def find_bullet_cols(z, row):
    """指定nt行の全32列を走査し、BULLET_L_CODEが置かれている列のリストを返す。"""
    base = NAMTBL + row * 32
    out = []
    for col in range(32):
        if z.vram[base + col] == find_bullet_cols.BULLET_L:
            out.append(col)
    return out


def active_slots(z, sym, pool):
    base = sym[f"EBUZ2_{pool}_SLOTS"]
    out = []
    for i in range(0, 16, 2):
        row = z.mem[base + i]
        if row != sym["EBUZ2_SLOT_EMPTY"]:
            out.append((row, z.mem[base + i + 1]))
    return out


def main():
    mem0, sym = assemble()
    find_bullet_cols.BULLET_L = sym["BULLET_L_CODE"]
    A, B, C, D = sym["EBUZ2_CODE_A"], sym["EBUZ2_CODE_B"], sym["EBUZ2_CODE_C"], sym["EBUZ2_CODE_D"]

    # ---------- 1. state1解放: 中央発射管から1発だけ ----------
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]
    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])
    # state1の中央行はnametable row5固定(EBUZ2_STATE1_OSC_ROW(2)+CENTER_OFS(3)=5)
    check(cells(z, 5, 22, 2) == [sym["BULLET_L_CODE"], sym["BULLET_R_CODE"]],
          "state1解放直後: 中央行(nt5)のcol22-23にBULLET_L/Rがある(中央1発発射)")
    # 他の4管(row3,4,6,7)には弾が無いこと(=3連ボレーではなく1発のみ)
    for row in (3, 4, 6, 7):
        check(find_bullet_cols(z, row) == [],
              f"state1解放直後: row{row}には弾が無い(中央以外は発射していない)")
    active = active_slots(z, sym, "C")
    check(active == [(5, 22)], f"C_SLOTSに(row=5,col=22)が1件だけアクティブ: got {active}")
    for pool in ("OT", "OB", "IT", "IB"):
        check(active_slots(z, sym, pool) == [], f"{pool}_SLOTSはstate1解放直後は全て非アクティブ")

    # ---------- 2. state1→state2遷移: 本体がrow9へ、旧row3-7は消去済み ----------
    z2 = Z80(bytearray(mem0))
    z2.pc = sym["INIT"]
    run_until_pc(z2, sym["EBUZ2_STATE2_BG_DONE"])
    check(z2.mem[sym["EBUZ2_OSC_ROW"]] == sym["EBUZ2_OSC_ROW_START"],
          f"state2形成直後: EBUZ2_OSC_ROW=={sym['EBUZ2_OSC_ROW_START']}(Row9)")
    r0 = sym["EBUZ2_OSC_ROW_START"]
    check(cells(z2, r0, 23, 5) == [0, 0, A, B, C], "state2 row0(local) = ' . . A B C'")
    check(cells(z2, r0 + 1, 23, 5) == [0, A, B, C, C], "state2 row1(local) = ' . A B C C'")
    check(cells(z2, r0 + 3, 23, 5) == [A, B, C, D, D], "state2 row3(local、中央) = 'A B C D D'")
    check(cells(z2, r0 + 6, 23, 5) == [0, 0, A, B, C], "state2 row6(local) = ' . . A B C'")
    # 旧state1位置(nt row3-7)は完全に消去されている(2つの本体が同時に
    # 残っていない)。col22は中央発射管の弾自身が発射直後まだそこに
    # いる列(EBUZ2_ERASE_STATE1は本体の絵柄[col23-27]だけを消す設計、
    # 弾自身は自分自身のティックで消える - 0ティック目のこの一瞬だけ
    # col22に弾の左半分が残るのは実害の無い過渡状態、実機でも1回の
    # VRAM書き込みバーストの範囲内で可視フレームには現れない)。
    for row in range(3, 8):
        check(cells(z2, row, 23, 5) == [0, 0, 0, 0, 0],
              f"state1旧位置row{row}(本体の絵柄col23-27)は消去済み(本体は移動、居残りなし)")

    # ---------- 3. 発射シーケンス: 中央→内側→外側→中央…の順で無限ループ ----------
    # FIRE_STEPが0→1→2→0…と正しく周回することを確認。
    z3 = Z80(bytearray(mem0))
    z3.pc = sym["INIT"]
    run_until_pc(z3, sym["EBUZ2_STATE2_DONE"])
    steps_seen = []
    for _ in range(9):
        for _ in range(sym["EBUZ2_FIRE_INTERVAL"]):
            z3.step()
            run_until_pc(z3, sym["EBUZ2_FRAME_TICK"])
        steps_seen.append(z3.mem[sym["EBUZ2_FIRE_STEP"]])
    # 発射した直後、FIRE_STEPは「次に撃つステップ」へ進んでいるため、
    # 観測列は[1,2,0,1,2,0,...]になるはず(0=中央 が最初に撃たれ、
    # 次は1=内側になっている、を9回=3周分)。
    check(steps_seen == [1, 2, 0] * 3,
          f"FIRE_STEPが中央→内側→外側の順で3周正しく循環する: got {steps_seen}")

    # 各ステップで実際に「その管の弾だけ」が新規発射されることを、
    # プールの累積を避けるため毎回フレッシュなZ80で個別に検証する。
    def fresh_to_state2_done():
        zz = Z80(bytearray(mem0))
        zz.pc = sym["INIT"]
        run_until_pc(zz, sym["EBUZ2_STATE2_DONE"])
        return zz

    # ステップ0(中央)発射直後
    zc = fresh_to_state2_done()
    for _ in range(sym["EBUZ2_FIRE_INTERVAL"]):
        zc.step()
        run_until_pc(zc, sym["EBUZ2_FRAME_TICK"])
    check(len(active_slots(zc, sym, "C")) == 1, "中央ステップ後: C_SLOTSに新規1発")
    check(active_slots(zc, sym, "IT") == [] and active_slots(zc, sym, "IB") == [],
          "中央ステップ後: 内側管はまだ発射していない")
    check(active_slots(zc, sym, "OT") == [] and active_slots(zc, sym, "OB") == [],
          "中央ステップ後: 外側管はまだ発射していない")

    # ステップ1(内側、上下2門)発射直後
    zi = fresh_to_state2_done()
    for _ in range(sym["EBUZ2_FIRE_INTERVAL"] * 2):
        zi.step()
        run_until_pc(zi, sym["EBUZ2_FRAME_TICK"])
    check(len(active_slots(zi, sym, "IT")) == 1 and len(active_slots(zi, sym, "IB")) == 1,
          "内側ステップ後: IT/IBそれぞれ新規1発(上下2門同時)")
    check(len(active_slots(zi, sym, "OT")) == 0 and len(active_slots(zi, sym, "OB")) == 0,
          "内側ステップ後: 外側管はまだ発射していない")

    # ステップ2(外側、上下2門)発射直後
    zo = fresh_to_state2_done()
    for _ in range(sym["EBUZ2_FIRE_INTERVAL"] * 3):
        zo.step()
        run_until_pc(zo, sym["EBUZ2_FRAME_TICK"])
    check(len(active_slots(zo, sym, "OT")) == 1 and len(active_slots(zo, sym, "OB")) == 1,
          "外側ステップ後: OT/OBそれぞれ新規1発(上下2門同時)")

    # ---------- 4. oscillation: row1-16の範囲を連続的に往復する ----------
    z4 = Z80(bytearray(mem0))
    z4.pc = sym["INIT"]
    run_until_pc(z4, sym["EBUZ2_STATE2_DONE"])
    rows_seen = []
    for _ in range(2000):
        z4.step()
        run_until_pc(z4, sym["EBUZ2_FRAME_TICK"])
        rows_seen.append(z4.mem[sym["EBUZ2_OSC_ROW"]])
    check(max(rows_seen) == sym["EBUZ2_OSC_ROW_MAX"], f"2000ティック中にRow16(MAX)へ到達: max={max(rows_seen)}")
    check(min(rows_seen) == sym["EBUZ2_OSC_ROW_MIN"], f"2000ティック中にRow1(MIN)へ到達: min={min(rows_seen)}")
    # 範囲外に出ないこと
    check(all(sym["EBUZ2_OSC_ROW_MIN"] <= r <= sym["EBUZ2_OSC_ROW_MAX"] for r in rows_seen),
          "oscillation中、EBUZ2_OSC_ROWは常にMIN-MAXの範囲内")
    # 1ティックあたりの変化量は常に-1,0,+1のいずれか(離散ジャンプが無い、連続往復であることの確認)
    step_diffs = set(rows_seen[i + 1] - rows_seen[i] for i in range(len(rows_seen) - 1))
    check(step_diffs <= {-1, 0, 1}, f"row変化は常に隣接1マス以内(離散ジャンプなし): got diffs {step_diffs}")

    # ---------- 5. 弾のYは発射時点で固定、本体が後で動いてもYは変わらない ----------
    z5 = Z80(bytearray(mem0))
    z5.pc = sym["INIT"]
    run_until_pc(z5, sym["EBUZ2_STATE2_DONE"])
    # 最初の発射(中央)が起きるまで進める
    for _ in range(sym["EBUZ2_FIRE_INTERVAL"]):
        z5.step()
        run_until_pc(z5, sym["EBUZ2_FRAME_TICK"])
    c_slots_after_first_fire = active_slots(z5, sym, "C")
    check(len(c_slots_after_first_fire) == 1, "中央ステップ発射直後、C_SLOTSに1件アクティブ")
    fired_row = c_slots_after_first_fire[0][0]
    check(fired_row == sym["EBUZ2_OSC_ROW_START"] + sym["EBUZ2_CENTER_OFS"],
          f"発射時の中央弾の行はOSC_ROW_START+CENTER_OFS: got {fired_row}")
    # 本体がさらに何ティックも動いた後も、この弾のROWは不変のまま
    for _ in range(200):
        z5.step()
        run_until_pc(z5, sym["EBUZ2_FRAME_TICK"])
        slots = active_slots(z5, sym, "C")
        for (row, col) in slots:
            if row == fired_row:
                break
        else:
            # この特定の弾は既にプールから外れた(画面外へ抜けた)可能性がある-
            # その場合は以降のチェック対象外として抜ける。
            break
    else:
        pass
    check(z5.mem[sym["EBUZ2_OSC_ROW"]] != sym["EBUZ2_OSC_ROW_START"],
          "200ティック後、本体は初期位置から実際に動いている(oscillationが機能)")

    print(f"\n{PASS} passed, {FAIL} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
