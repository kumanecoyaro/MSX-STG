"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20三度目の全面リセット
版)を検証する。今回実装したのはこれだけ:

  1. 画面row0はブラック、row20-23はホワイトのガードバンドで塗りつぶし、
     本体・弾は絶対にこの5行へ描画しない。
  2. 登場: 本体(開状態7行)をrow19に下端を固定して1ティック1行ずつ
     下から積み上げ描画する。
  3. 全7行出現後、そのまま画面中央(row_top=9)まで1ティック1行ずつ
     平行移動する。
  4. 中央到達後、5門全てから同時に1発ずつ発射する(合計5発)。
  5. それ以降は本体は動かず、連射もしない(oscillation・無限連射・
     リコイルは未実装、次のステップ)。

検証項目はこの5点それぞれと、「ガードバンドが常に一切破壊されない」
という最重要の恒久条件。
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


def row_all(z, row):
    return cells(z, row, 0, 32)


def find_bullet_cols(z, row):
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


def check_guard_bands(z, sym, label):
    """row0が全てGUARD_BLACK_CODE、row20-23が全てGUARD_WHITE_CODEで
    埋まっていることを確認する(このプロトタイプ全体を通じて常に
    成り立たねばならない恒久条件)。"""
    black = sym["GUARD_BLACK_CODE"]
    white = sym["GUARD_WHITE_CODE"]
    check(row_all(z, 0) == [black] * 32, f"{label}: row0(ガード)が全てGUARD_BLACK_CODEのまま")
    for row in (20, 21, 22, 23):
        check(row_all(z, row) == [white] * 32,
              f"{label}: row{row}(ガード)が全てGUARD_WHITE_CODEのまま")


def main():
    mem0, sym = assemble()
    find_bullet_cols.BULLET_L = sym["BULLET_L_CODE"]
    A, B, C, D = sym["EBUZ2_CODE_A"], sym["EBUZ2_CODE_B"], sym["EBUZ2_CODE_C"], sym["EBUZ2_CODE_D"]

    # ---------- 1. ガードバンドが初期化直後から正しく塗られている ----------
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]
    run_until_pc(z, sym["EBUZ2_GUARD_DONE"])
    check_guard_bands(z, sym, "ガード初期化直後")

    # ---------- 2. 登場フェーズA: 下から1行ずつ積み上がる ----------
    z2 = Z80(bytearray(mem0))
    z2.pc = sym["INIT"]
    bottom = sym["EBUZ2_ENTRY_BOTTOM_ROW"]
    expected_rows = [
        (bottom, [0, 0, A, B, C]),
        (bottom - 1, [0, A, B, C, C]),
        (bottom - 2, [0, 0, 0, 0, D]),
        (bottom - 3, [A, B, C, D, D]),
        (bottom - 4, [0, 0, 0, 0, D]),
        (bottom - 5, [0, A, B, C, C]),
        (bottom - 6, [0, 0, A, B, C]),
    ]
    run_until_pc(z2, sym["EBUZ2_ENTRY_GROWTH_DONE"])
    check_guard_bands(z2, sym, "登場フェーズA完了直後")
    for row, data in expected_rows:
        check(cells(z2, row, 23, 5) == data, f"登場フェーズA完了後: row{row}(local)のデータが正しい")
    # 成長フェーズ中、途中経過も1行ずつ正しく積み上がっていたことを
    # 別のフレッシュなZ80で1ティックずつ確認する(EBUZ2_TICKの入口を
    # 7回通過するたびに出現行数が1つずつ増えるはず)。
    revealed_rows_over_time = []
    z2c = Z80(bytearray(mem0))
    z2c.pc = sym["INIT"]
    run_until_pc(z2c, sym["EBUZ2_GUARD_DONE"])
    for _ in range(7):
        # 1行描画+1回のEBUZ2_TICK呼び出し分だけ進める。growth内の各行は
        # 「LDIRVM描画」の直後に「CALL EBUZ2_TICK」が続くので、次に
        # EBUZ2_ENTRY_GROWTH_DONEかまだ growth 中の次のLDIRVM呼び出しかを
        # 判別せず、単純にEBUZ2_FRAME_TICKは使えない(まだmainloopに
        # 入っていない)。そこで「EBUZ2_TICK」自体の入口を7回通過する
        # ことをもって1行ずつの進行を確認する。
        run_until_pc(z2c, sym["EBUZ2_TICK"])
        z2c.step()  # 同じチェックポイントの再ヒットを避けるため1回進める
        count = sum(1 for r in range(9, bottom + 1) if cells(z2c, r, 23, 5) != [0, 0, 0, 0, 0])
        revealed_rows_over_time.append(count)
    check(revealed_rows_over_time == [1, 2, 3, 4, 5, 6, 7],
          f"登場フェーズA: 出現行数が1,2,...,7と1ティックごとに1行ずつ増える: got {revealed_rows_over_time}")

    # ---------- 3. 登場フェーズB: 画面中央まで平行移動 ----------
    z3 = Z80(bytearray(mem0))
    z3.pc = sym["INIT"]
    run_until_pc(z3, sym["EBUZ2_ENTRY_MOVE_DONE"])
    check_guard_bands(z3, sym, "移動フェーズ完了直後")
    target = sym["EBUZ2_ENTRY_TARGET_ROW_TOP"]
    check(z3.mem[sym["EBUZ2_BODY_ROW"]] == target,
          f"移動フェーズ完了後: EBUZ2_BODY_ROW=={target}(画面中央)")
    check(cells(z3, target, 23, 5) == [0, 0, A, B, C], "移動完了後: local row0が中央位置に描画されている")
    check(cells(z3, target + 3, 23, 5) == [A, B, C, D, D], "移動完了後: local row3(中央行)が中央位置に描画されている")
    check(cells(z3, target + 6, 23, 5) == [0, 0, A, B, C], "移動完了後: local row6が中央位置に描画されている")
    # 旧成長時の位置(row13-19寄りの、中央位置と重ならない範囲)には
    # 本体の絵柄が残っていないこと。
    for row in range(target + 7, bottom + 1):
        check(cells(z3, row, 23, 5) == [0, 0, 0, 0, 0],
              f"移動完了後: 旧成長位置row{row}は消去済み(本体は中央へ完全移動)")

    # ---------- 4. 中央到達後、5門全てから同時に1発ずつ発射 ----------
    z4 = Z80(bytearray(mem0))
    z4.pc = sym["INIT"]
    run_until_pc(z4, sym["EBUZ2_VOLLEY_DONE"])
    check_guard_bands(z4, sym, "5門一斉発射直後")
    for pool in ("C", "OT", "OB", "IT", "IB"):
        slots = active_slots(z4, sym, pool)
        check(len(slots) == 1, f"{pool}_SLOTSに新規1発がアクティブ: got {slots}")
    c_row = active_slots(z4, sym, "C")[0][0]
    ot_row = active_slots(z4, sym, "OT")[0][0]
    ob_row = active_slots(z4, sym, "OB")[0][0]
    it_row = active_slots(z4, sym, "IT")[0][0]
    ib_row = active_slots(z4, sym, "IB")[0][0]
    check(c_row == target + sym["EBUZ2_CENTER_OFS"], f"中央弾の行はtarget+CENTER_OFS: got {c_row}")
    check(ot_row == target + sym["EBUZ2_OUTER_TOP_OFS"], f"外側上弾の行が正しい: got {ot_row}")
    check(ob_row == target + sym["EBUZ2_OUTER_BOTTOM_OFS"], f"外側下弾の行が正しい: got {ob_row}")
    check(it_row == target + sym["EBUZ2_INNER_TOP_OFS"], f"内側上弾の行が正しい: got {it_row}")
    check(ib_row == target + sym["EBUZ2_INNER_BOTTOM_OFS"], f"内側下弾の行が正しい: got {ib_row}")

    # ---------- 5. 発射後は本体が動かず、追加の発射も一切起きない ----------
    z5 = Z80(bytearray(mem0))
    z5.pc = sym["INIT"]
    run_until_pc(z5, sym["EBUZ2_VOLLEY_DONE"])
    body_row_at_volley = z5.mem[sym["EBUZ2_BODY_ROW"]]
    next_counters_at_volley = {
        pool: z5.mem[sym[f"EBUZ2_{pool}_NEXT"]] for pool in ("C", "OT", "OB", "IT", "IB")
    }
    for _ in range(500):
        z5.step()
        run_until_pc(z5, sym["EBUZ2_FRAME_TICK"])
    check_guard_bands(z5, sym, "発射後500ティック経過時点")
    check(z5.mem[sym["EBUZ2_BODY_ROW"]] == body_row_at_volley,
          "発射後500ティック経過しても本体のEBUZ2_BODY_ROWは不変(oscillationしない)")
    for pool in ("C", "OT", "OB", "IT", "IB"):
        cur = z5.mem[sym[f"EBUZ2_{pool}_NEXT"]]
        check(cur == next_counters_at_volley[pool],
              f"発射後500ティック経過しても{pool}_NEXTは不変(追加発射が一切起きていない): "
              f"got {cur}, expected {next_counters_at_volley[pool]}")
    # 5発の弾は全て画面外へ抜けて消えているはず(500ティックあれば
    # 十分すぎるほど、1ティック1列で最大32列しか進まないため)。
    for pool in ("C", "OT", "OB", "IT", "IB"):
        check(active_slots(z5, sym, pool) == [], f"{pool}_SLOTS: 500ティック後は弾が画面外へ抜けて全て非アクティブ")

    print(f"\n{PASS} passed, {FAIL} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
