"""Converts SasapiHand_64x64.json (the boss's attack-pose art, drawn
straight into SCREEN1's own name table while parked at the right edge,
NOT a hw sprite - "右端に戻ったら添付のパターンをBGに描画しスプライト
は一旦消す") into 64 row-major 8x8 BG pattern tiles (8 rows x 8 cols of
8x8 pixels each) - the exact order the name table itself is laid out
in, NOT the TL/BL/TR/BR sprite-quadrant order sasapi_gen.py/tank_gen.py
use for hw sprites, since this never becomes a hw sprite.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SPRITE_DIR = os.path.join(HERE, "sprites")


def load_bits(name):
    return json.load(open(os.path.join(SPRITE_DIR, f"{name}.json")))["bits"]


def to_bytes(tile8x8):
    out = []
    for row in tile8x8:
        b = 0
        for i, v in enumerate(row):
            if v:
                b |= (0x80 >> i)
        out.append(b)
    return out


def tiles_row_major(bits):
    tiles = []
    for ty in range(8):
        for tx in range(8):
            tile = [row[tx * 8:tx * 8 + 8] for row in bits[ty * 8:ty * 8 + 8]]
            tiles.append(to_bytes(tile))
    return tiles


SASAPI_HAND_TILES = tiles_row_major(load_bits("SasapiHand_64x64"))


def db_bytes(byte_list):
    return "    DB " + ",".join(f"{b}" for b in byte_list)


def emit_asm_tables():
    """(round64更新、"キャラクター定義データを他のバンクに逃がして
    しまえばかなり開くだろう"): SASAPI_HAND_TILES(64x64、512byte、
    INITで一度だけロードされる攻撃ポーズBG絵)も、sasapi_gen.pyの
    SASAPI_QUADS/_Lと同じ理由・同じ方式でtools/bgm_data/bgm_bank_gen.py
    が管理する共有"bgm-data"バンクへ移設した。ここでは移設先オフセットの
    EQUを埋め込むだけ - 実データはtools/bgm_data/bgm_bank_gen.pyの
    _generate()がこのファイル自身のSASAPI_HAND_TILES(モジュールレベル
    変数、生バイト列)を直接読んで共有バンクへ書き込む。実ロードは
    combined_test.asmのINIT内、SWITCH_TO_CHARDATA_BANK/RESTORE_OWN_
    BANK_Bで一時的にwindowBを切り替えてLDIRVM(SASAPI_HAND_COLOR8等の
    小さな色テーブルは毎フレーム参照されるため対象外、引き続きこの
    ファイルの出力[combined_test.asm本体]に直接DB展開されたまま)。"""
    sys.path.insert(0, os.path.join(HERE, "..", "bgm_data"))
    import bgm_bank_gen as bg
    _, layout = bg.build_bank()
    ofs = layout["SASAPI_CHARDATA"]["SASAPI_HAND_TILES"]
    return ("; ===== Sasapi attack-pose BG art DATA moved to the shared bgm-data bank "
            "(round64) - see combined_test.asm's INIT (hand-tiles load block) =====\n"
            f"SASAPI_HAND_TILES EQU {ofs}")


if __name__ == "__main__":
    print(f"SasapiHand converted: {len(SASAPI_HAND_TILES)} 8x8 BG tiles ({len(SASAPI_HAND_TILES) * 8} bytes)")
