"""EbuzBullet1_16x16.jsonからの、2種類のhwスプライトパターン抽出ロジック
(記録用・再検証用)。ebuz_test.asm自体にはこのスクリプトの出力を手動で
書き写し済み。

添付JSON自体は16x16キャンバスに、pixel単位で完全に同一な2本の水平バー
(rows2-5とrows10-13、それぞれ16x4)が上下に分かれて描かれている -
つまり上半分(rows0-7)と下半分(rows8-15)がそのままpixel単位で完全に
同一。これを踏まえ、2種類のスプライトパターンを用意する:
  - BULLET_FULL: 添付JSONそのまま(16x16、2本のバー)。
    "Ebuz1で登場した時に...弾を左へ発射"用。
  - BULLET_HALF: "添付ファイルの16x8部分だけ"用。上半分(rows0-7、
    バー1本)をそのまま使い、下半分は空白でパディングして16x16
    スプライトパターンにする(この2つのバーはpixel単位で同一なので
    上半分だけ切り出せば十分、どちらの半分を使っても同じ絵になる)。
    "Ebuz2に変化したら...16x8部分だけのスプライトを上下から発射"用
    (Y位置0pxと24pxの2枚、同じパターンを使い回す)。

MSX1(TMS9918)の16x16スプライトパターンは、hw内部でTL(左上8x8)→
BL(左下8x8)→TR(右上8x8)→BR(右下8x8)の順の32byteとして格納する
(src/CYBER SHMUP.asmの既存16x16スプライト[PAT_SHIP等]と同じ規約)。
"""
import json
import os

UPLOAD_DIR = "/root/.claude/uploads/8adb3f48-429f-5460-9ecb-a8cda4b8e41b"
BULLET_PATH = os.path.join(UPLOAD_DIR, "d21621cf-EbuzBullet1_16x16.json")
# 2026-09-13追記: ユーザーが"BULLET_HALF"用の専用データとして改めて
# 添付したファイル(以前はEbuzBullet1の上半分を自前で切り出して代用
# していた)。下記verify_against_ebuz_bullet2()でBULLET_HALF_PATと
# 完全一致することを確認済み(新規タイルデータは不要)。
BULLET2_PATH = os.path.join(UPLOAD_DIR, "bd587a2b-EbuzBullet2_16x16.json")


def load_bits(path=BULLET_PATH):
    with open(path, encoding="utf-8") as f:
        return json.load(f)["bits"]


def quad_bytes(bits, row_off, col_off):
    out = []
    for r in range(8):
        row = bits[row_off + r][col_off:col_off + 8]
        byte = 0
        for b in row:
            byte = (byte << 1) | b
        out.append(byte)
    return out


def bullet_full_quads():
    bits = load_bits()
    return {
        "TL": quad_bytes(bits, 0, 0),
        "BL": quad_bytes(bits, 8, 0),
        "TR": quad_bytes(bits, 0, 8),
        "BR": quad_bytes(bits, 8, 8),
    }


def bullet_half_quads():
    bits = load_bits()
    blank = [0] * 8
    return {
        "TL": quad_bytes(bits, 0, 0),
        "BL": blank,
        "TR": quad_bytes(bits, 0, 8),
        "BR": blank,
    }


def verify_against_ebuz_bullet2():
    """BULLET_HALFの4象限が、専用に添付されたEbuzBullet2_16x16.jsonと
    バイト単位で完全一致することを検証する(2026-09-13)。"""
    bits2 = load_bits(BULLET2_PATH)
    half = bullet_half_quads()
    actual = {
        "TL": quad_bytes(bits2, 0, 0),
        "TR": quad_bytes(bits2, 0, 8),
        "BL": quad_bytes(bits2, 8, 0),
        "BR": quad_bytes(bits2, 8, 8),
    }
    mismatches = [q for q in ("TL", "BL", "TR", "BR") if actual[q] != half[q]]
    return (len(mismatches) == 0), mismatches


if __name__ == "__main__":
    full = bullet_full_quads()
    half = bullet_half_quads()
    for name, quads in [("BULLET_FULL", full), ("BULLET_HALF", half)]:
        print(f"{name}:")
        for q in ("TL", "BL", "TR", "BR"):
            print(f"  {q}: DB " + ",".join(str(x) for x in quads[q]))
