"""添付PNG(256x192)をSCREEN3(Multicolor)のBSAVE形式(*.SC3)へ変換する
汎用エンコーダ(2026-09-13、"09が入ってない"→実際の09.SC3が08と完全に
バイト一致していたと判明→再送してもらっても同一のまま→"じゃあこれから
作ってくれ"[PNG添付]で対応)。

Multicolor(SCREEN3)のVRAMレイアウトは、screen3_gen.py/screen3_epilogue_
gen.pyが実データから確立した規約と完全に同じ:
  - ネームテーブル(768byte、0x0800オフセット)は全画像で共有の機械的な
    ランプ(name = 32*(row_of_name//4) + col、row_of_name=Y//8の0-23)。
  - このランプにより、名前(=パターン番号)は「4キャラクター行(32ピクセル
    行)ごとの帯×32列」の組ごとに一意(0-191)。つまり実質「192枚の
    8x32ピクセル短冊」を敷き詰めるのと同じで、パターンの再利用最適化を
    一切考える必要が無い(帯の中の8バイトがそのまま32ピクセル分[4px
    刻みで8分割]の実データになる)。
  - パターン1枚(8byte)の各バイトは、その4x4ブロック行における
    左半分(x%8<4)を上位nibble・右半分(x%8>=4)を下位nibbleとして
    16色パレットの色番号(0-15)を格納する。

パレットはtools/stage2_terrain/verify_terrain.pyのPALETTE(実機VDPの
16色RGBを実測して確立済み、他の画像[Image01-06/Epilogue1/3]でも
共通で使用)をそのまま使う。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools", "screen3_test"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
import screen3_gen  # noqa: E402
import verify_terrain as vt  # noqa: E402

from PIL import Image  # noqa: E402

PALETTE = vt.PALETTE
W, H = 256, 192


def nearest_color_index(rgb):
    best_i, best_d = 0, None
    for i, (r, g, b) in PALETTE.items():
        d = (r - rgb[0]) ** 2 + (g - rgb[1]) ** 2 + (b - rgb[2]) ** 2
        if best_d is None or d < best_d:
            best_d, best_i = d, i
    return best_i


def block_color_index(px, x0, y0):
    """4x4ブロック内の各ピクセルを最近傍パレット色へ量子化し、最頻値を採用。"""
    counts = {}
    for yy in range(y0, y0 + 4):
        for xx in range(x0, x0 + 4):
            idx = nearest_color_index(px[xx, yy][:3])
            counts[idx] = counts.get(idx, 0) + 1
    return max(counts.items(), key=lambda kv: kv[1])[0]


def encode_png_to_pgt(png_path):
    img = Image.open(png_path).convert("RGB")
    assert img.size == (W, H), f"{png_path}: expected {W}x{H}, got {img.size}"
    px = img.load()

    pgt = bytearray(0x0800)  # 2048 bytes, names 192-255 (unused by the ramp) stay 0
    for band in range(6):
        for col in range(32):
            name = 32 * band + col
            for byte_idx in range(8):
                y0 = band * 32 + byte_idx * 4
                x0 = col * 8
                left = block_color_index(px, x0, y0)
                right = block_color_index(px, x0 + 4, y0)
                pgt[name * 8 + byte_idx] = (left << 4) | right
    return bytes(pgt)


def write_sc3(pgt, out_path):
    name_table = bytes(screen3_gen.shared_name_table())
    payload = bytearray(0x2040)  # 8256 bytes, matches Image01-06/Epilogue1/3's own size
    payload[0:0x0800] = pgt
    payload[0x0800:0x0800 + len(name_table)] = name_table
    header = bytes([0xFE, 0x00, 0x00, 0x3F, 0x20, 0x00, 0x00])
    with open(out_path, "wb") as f:
        f.write(header)
        f.write(payload)


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    pgt = encode_png_to_pgt(src)
    write_sc3(pgt, dst)
    print(f"wrote {dst}: {os.path.getsize(dst)} bytes")
