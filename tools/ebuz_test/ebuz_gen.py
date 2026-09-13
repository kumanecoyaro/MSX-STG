"""Ebuz1_32x32.json/Ebuz3_32x32.jsonからのタイル抽出ロジック(記録用・
再検証用)。ebuz_test.asm自体にはこのスクリプトの出力を手動で書き写し
済み(4タイルのみで小規模なため)なので、実行は必須ではない - 元データ
から再確認したい場合、または将来的にEbuz1側の絵柄が変わった場合の
再生成に使う。

抽出結果(2026-09-13時点で確認済み):
  - Ebuz1は32x32キャンバス中、実際に絵柄があるのはrow8-23の16行だけ
    (上下8pxは完全空白)。かつrow8-15とrow16-23はピクセル単位で完全に
    同一(タイル4個の1行を単純に2回重ねているだけ)。
  - state2の正しい絵はEbuz3(ユーザー訂正: "間違えた これに変化 渡した
    Ebuz2はまた別のやつ" - 最初に添付されたEbuz2_32x32.jsonは無関係の
    別物だった)。Ebuz3はEbuz1と全く同じ4種類の8x8タイル(A,B,C,D)だけで
    構成されており、新規の絵柄は一切無い(Ebuz1の該当タイルとバイト
    単位で完全一致することを確認済み): A,B,Cの帯が中央2行から上下へ
    分離・移動し、中央にはDタイルだけが残る。
"""
import json
import os

UPLOAD_DIR = "/root/.claude/uploads/8adb3f48-429f-5460-9ecb-a8cda4b8e41b"
EBUZ1_PATH = os.path.join(UPLOAD_DIR, "84c7aa17-Ebuz1_32x32.json")
EBUZ3_PATH = os.path.join(UPLOAD_DIR, "b9262e12-Ebuz3_32x32.json")


def load_bits(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["bits"]


def get_tile(bits, tile_row, tile_col):
    """8x8 tile at (tile_row, tile_col) in tile units, as a tuple of 8 rows."""
    return tuple(tuple(bits[tile_row * 8 + r][tile_col * 8:tile_col * 8 + 8]) for r in range(8))


def tile_to_bytes(tile):
    out = []
    for row in tile:
        byte = 0
        for bit in row:
            byte = (byte << 1) | bit
        out.append(byte)
    return out


def extract_tiles():
    b1 = load_bits(EBUZ1_PATH)
    a = tile_to_bytes(get_tile(b1, 1, 0))
    b = tile_to_bytes(get_tile(b1, 1, 1))
    c = tile_to_bytes(get_tile(b1, 1, 2))
    d = tile_to_bytes(get_tile(b1, 1, 3))
    return a, b, c, d


def verify_against_ebuz3(a, b, c, d):
    """Confirms the 4-tile theory reconstructs Ebuz3.json (the correct
    state2 art) byte-for-byte: the A,B,C band splits away from the
    original 2 rows to a new top/bottom band, leaving only D behind."""
    b3 = load_bits(EBUZ3_PATH)
    blank = [0] * 8
    grid = {
        (0, 0): blank, (0, 1): a, (0, 2): b, (0, 3): c,
        (1, 0): blank, (1, 1): blank, (1, 2): blank, (1, 3): d,
        (2, 0): blank, (2, 1): blank, (2, 2): blank, (2, 3): d,
        (3, 0): blank, (3, 1): a, (3, 2): b, (3, 3): c,
    }
    for tr in range(4):
        for tc in range(4):
            actual = tile_to_bytes(get_tile(b3, tr, tc))
            expected = grid[(tr, tc)]
            if actual != expected:
                return False, (tr, tc)
    return True, None


if __name__ == "__main__":
    a, b, c, d = extract_tiles()
    for name, tile in [("A", a), ("B", b), ("C", c), ("D", d)]:
        print(f"EBUZ_TILE_{name}: DB " + ",".join(str(x) for x in tile))
    ok, mismatch = verify_against_ebuz3(a, b, c, d)
    print("Ebuz3.json byte-for-byte reconstruction OK:", ok, mismatch or "")
