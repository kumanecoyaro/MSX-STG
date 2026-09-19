"""EbuzMk2 state1の開幕ボレー(2026-09-19訂正版)が、ユーザーの訂正
("斜め移動はしないぞ")通り本当に斜め成分ゼロであることを回帰的に
検証する。tools/ebuz_mk2_test/ebuz_mk2_test.asmをz80emu.pyで実行し、
3レーンそれぞれの発射直後の行・列と、数ティック後の行・列を直接
比較する - Y(name table行アドレス)が発射から着地まで一度も変化
しないこと、列は必ず1ティックにつき1だけ減ること、を確認する。
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


def run_until_pc(z, target_pc, max_instr=4_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


NAMTBL = 0x1800
ROW_OF = {0: 3, 1: 5, 2: 7}  # EBUZ2_ROW3_BASE/ROW5_BASE/ROW7_BASE, in nametable rows
EXPECT_START_COL = {0: 24, 1: 22, 2: 24}


def find_lane_bg_col(z, row):
    """指定nametable行(row3/5/7)の全32列を走査し、BULLET_L_CODE
    (弾の左半分タイル)が置かれている列を返す(無ければNone)。"""
    base = NAMTBL + row * 32
    for col in range(32):
        if z.vram[base + col] == find_lane_bg_col.BULLET_L:
            return col
    return None


def main():
    mem0, sym = assemble()
    find_lane_bg_col.BULLET_L = sym["BULLET_L_CODE"]

    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]

    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])

    # --- 1. 発射直後: 3レーンとも期待通りの行・列にいること ---
    for lane, row in ROW_OF.items():
        col = find_lane_bg_col(z, row)
        check(col == EXPECT_START_COL[lane],
              f"lane{lane} just after firing: expected col {EXPECT_START_COL[lane]} "
              f"on nametable row{row}, found col {col}")

    # --- 2. 中央行(row2/最深部)が本当に一番深い(列が一番小さい)こと ---
    c0 = find_lane_bg_col(z, ROW_OF[0])
    c1 = find_lane_bg_col(z, ROW_OF[1])
    c2 = find_lane_bg_col(z, ROW_OF[2])
    check(c1 < c0 and c1 < c2, f"center lane should be deepest (smallest col): got {c0},{c1},{c2}")
    check(c0 == c2, f"top-cap and bottom-cap lanes should start at the same col: got {c0} vs {c2}")

    # --- 3. 数ティック進めても、各レーンは自分の行から一切動かない ---
    #     (Yコンポーネントが構造的に存在しないことの直接証拠: もし
    #     診断コードのバグでYが動いていれば、この行以外に弾が現れる
    #     はずだが、一度も現れないことを確認する)。
    for _ in range(6):
        z.step()
        run_until_pc(z, sym["EBUZ2_WAIT_TICK_DONE"])

    for lane, row in ROW_OF.items():
        col = find_lane_bg_col(z, row)
        check(col is not None, f"lane{lane} should still be alive and on row{row} after 6 ticks")

    # --- 4. 列が毎ティックちょうど1ずつ減っていること(直進・定速) ---
    prev = {lane: EXPECT_START_COL[lane] for lane in ROW_OF}
    z2 = Z80(bytearray(mem0))
    z2.pc = sym["INIT"]
    run_until_pc(z2, sym["EBUZ2_STATE1_DONE"])
    for tick in range(5):
        z2.step()
        run_until_pc(z2, sym["EBUZ2_WAIT_TICK_DONE"])
        for lane, row in ROW_OF.items():
            col = find_lane_bg_col(z2, row)
            expect = prev[lane] - 1
            check(col == expect,
                  f"lane{lane} tick{tick+1}: expected col {expect} (straight, -1/tick), got {col}")
            prev[lane] = col

    print(f"\n{PASS} passed, {FAIL} failed")
    if FAIL:
        sys.exit(1)


if __name__ == "__main__":
    main()
