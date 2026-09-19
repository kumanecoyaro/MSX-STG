"""EbuzMk2(state1)の5行ウェッジ本体を、添付JSON
(Ebuzmkii1_64x64_1.json/_2.json)から機械抽出して検証するスクリプト。

(2026-09-19、ユーザー訂正: "斜め移動はしないぞ" - 当初ブリーフでは
state1の初弾3発を斜め移動のHWスプライトとして実装する想定だったが、
実際は「砲台のXセル位置が異なるんで 先端に合わせれば自然にそうなる」
という指示に訂正された。つまり本体そのものが不規則[非矩形]な形状で
あり、各行の弾は自分の行の"先端"[その行で最も左に描画されている
タイル列]のすぐ外側から真横に飛ぶだけで、全体では自然にくの字/ウェッジ
状に見える、という設計。本スクリプトはこの訂正の裏付けとして、実際に
アップロードされた添付JSONのピクセルデータから直接、各行の先端
ローカル列を計算する。)

添付JSON2枚(Ebuzmkii1_64x64_1.json=frame1[反動/縮小ポーズ]、
_2.json=frame2[静止ポーズ])はいずれも64x64px(8x8タイルで8行x8列)だが、
実際に絵が入っているのはtile row1-5(5行)・tile col0-4(5列、col5-7は
常に空白)のみ。frame2の方がユーザーの手書きASCII(2,1,0,1,2)と完全一致
するため、こちらを「静止時の基準ポーズ」として採用する。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
UPLOAD_DIR = "/root/.claude/uploads/8adb3f48-429f-5460-9ecb-a8cda4b8e41b"

# frame2 = 静止ポーズ(ユーザーのASCII wedgeと一致する方)。
FRAME2_PATH = os.path.join(UPLOAD_DIR, "d63abc7a-Ebuzmkii1_64x64_2.json")
# frame1 = もう一方のポーズ(反動/アニメ用、参考として抽出のみ行う)。
FRAME1_PATH = os.path.join(UPLOAD_DIR, "a717c091-Ebuzmkii1_64x64_1.json")


def load_bits(path):
    with open(path, encoding="utf-8") as f:
        d = json.load(f)
    return d["width"], d["height"], d["bits"], d.get("fg"), d.get("bg")


def tile_bytes(bits, tr, tc):
    """8x8タイル(tile row tr, tile col tc)のビットマップを、MSXの
    1byte=1行(MSBが左端ピクセル)8byte配列として返す。"""
    rows = []
    for y in range(tr * 8, tr * 8 + 8):
        v = 0
        for x in range(tc * 8, tc * 8 + 8):
            v = (v << 1) | bits[y][x]
        rows.append(v)
    return tuple(rows)


def main():
    w, h, bits, fg, bg = load_bits(FRAME2_PATH)
    assert (w, h) == (64, 64)
    tw, th = w // 8, h // 8

    uniq = {}
    grid = {}
    front_tip = {}
    for tr in range(1, 6):
        local_row = tr - 1
        cols_occupied = []
        row_tiles = {}
        for tc in range(0, 5):
            tb = tile_bytes(bits, tr, tc)
            if any(tb):
                cols_occupied.append(tc)
                if tb not in uniq:
                    uniq[tb] = chr(ord("A") + len(uniq))
                row_tiles[tc] = uniq[tb]
        grid[local_row] = row_tiles
        front_tip[local_row] = min(cols_occupied)

    print("=== EbuzMk2 state1 5-row wedge body (frame2/static pose) ===")
    print(f"source: {os.path.basename(FRAME2_PATH)} fg={fg} bg={bg}")
    print()
    print("row | local-cols(0-4)      | front-tip(local col)")
    for r in range(5):
        cols = grid[r]
        cells = [cols.get(c, ".") for c in range(5)]
        print(f" {r}  | {cells}         | {front_tip[r]}")
    print()
    print("unique tiles extracted:", len(uniq), "-> names:", sorted(uniq.values()))
    for tb, name in sorted(uniq.items(), key=lambda kv: kv[1]):
        print(f"  TILE_{name}: DB " + ",".join(str(b) for b in tb))

    print()
    print("Sanity check against original Ebuz1 tiles (tools/ebuz_test/ebuz_test.asm):")
    orig = {
        "A": (126, 191, 1, 63, 63, 1, 191, 126),
        "B": (255, 84, 42, 126, 126, 42, 84, 255),
        "C": (126, 195, 189, 181, 173, 189, 195, 126),
        "D": (255, 65, 127, 127, 127, 127, 65, 255),
    }
    for name, tb in orig.items():
        matched = [n2 for tb2, n2 in uniq.items() if tb2 == tb]
        print(f"  original {name} {'== ' + matched[0] if matched else 'NOT FOUND'} in Mk2 extraction")

    # --- Bullet spawn column derivation (per the user's corrected spec) ---
    # "local tile-col c -> name table col = EBUZ_COL_BASE + c - 1"
    # bullet's own starting local col = front_tip - 1 (one cell further
    # left/outward than the body's own edge for that row), translated
    # via the same mapping.
    print()
    print("=== Bullet spawn column table (EBUZ_MK2_COL_BASE=25, matches")
    print("    original single-Ebuz convention of anchoring the body's")
    print("    deepest/forward point at absolute col24=X192px) ===")
    COL_BASE = 25
    print("row | front_tip | body cols (abs)            | bullet spawn local col | bullet spawn abs col")
    for r in range(5):
        ft = front_tip[r]
        body_abs = [COL_BASE + c - 1 for c in sorted(grid[r].keys())]
        bullet_local = ft - 1
        bullet_abs = COL_BASE + bullet_local - 1
        print(f" {r}  |    {ft}      | {body_abs}   | {bullet_local}                       | {bullet_abs}")

    print()
    print("Opening volley (3 of the 5 rows, per correction default: row0/row2/row4):")
    for r in (0, 2, 4):
        ft = front_tip[r]
        bullet_local = ft - 1
        bullet_abs = COL_BASE + bullet_local - 1
        print(f"  row{r}: front_tip_local_col={ft} -> bullet spawn abs col={bullet_abs}")

    print()
    print("Resulting shape (bullet start columns by row, smaller col = further")
    print("left/forward): this should read as a symmetric wedge/chevron matching")
    print("the user's ASCII art (deepest at the center row).")
    for r in range(5):
        ft = front_tip[r]
        bullet_local = ft - 1
        bullet_abs = COL_BASE + bullet_local - 1
        indent = bullet_abs - (COL_BASE - 2)  # normalize so col23(min) = 0
        print(f"  row{r}: " + " " * indent + "-  (col{})".format(bullet_abs))


if __name__ == "__main__":
    main()
