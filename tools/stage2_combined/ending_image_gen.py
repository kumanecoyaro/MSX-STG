"""GFEnding最終画面(2026-09-12、"ではこの画像をMission completed表示後
10秒したら表示 ボタンが押されたらスタート画面へ タイトル表示同様に
圧縮かけて"): ユーザー提供のSCREEN2アート(BSAVE形式VRAMダンプ、
tools/title_screen/assets/Title.SC2と全く同じフォーマット)を、
タイトル画面と同一の自前RLE(tools/title_screen/title_bg_gen.pyの
rle_encode/rle_decode - 対称フォーマット・Z80側デコード最短、詳細は
そちらの長いコメント参照)で圧縮する。

タイトルと違い、この圧縮データはStage2本編自身のROM(bank4/5)には
置かない - Round64以降の各Roundの通り、Stage2本編のROM残り容量は
常に極めて少ない(数百byte〜2KB程度)ため、ボスキャラクターデータと
同じ「共有bgm-data/chardataバンクへ相乗りさせ、表示する瞬間だけ
windowBを一時的にそちらへ切り替えて読む」方式(tools/bgm_data/
bgm_bank_gen.pyのSASAPI_CHARDATA/SWITCH_TO_CHARDATA_BANK参照)を採用。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SC2_PATH = os.path.join(HERE, "assets", "EndingImage.SC2")

sys.path.insert(0, os.path.join(HERE, "..", "title_screen"))
import title_bg_gen  # noqa: E402  (汎用: load_sc2_payload/rle_encode/rle_decode/PAYLOAD_LEN)


def load_payload():
    return title_bg_gen.load_sc2_payload(SC2_PATH)


def compressed_raw():
    """(compressed_bytes, num_segments) - ラウンドトリップ検証済み。"""
    payload = load_payload()
    compressed, segments = title_bg_gen.rle_encode(payload)
    assert title_bg_gen.rle_decode(compressed, segments) == payload, \
        "RLE round-trip mismatch - encoder bug"
    return compressed, segments


def emit_asm_tables():
    """sasapi_gen.pyのSASAPI_QUADS等と同じ規約(2026-09-07、round64) -
    実データはもうこのファイルの出力(combined_test.asmへ埋め込まれる
    テキスト)には含まれず、tools/bgm_data/bgm_bank_gen.pyがキャッシュ
    済みの共有bgm-data/chardataバンク内オフセット+セグメント数だけを
    EQU定数として埋め込む(mido不要、build_bank()はキャッシュ
    ファイルを読むだけ)。実際のロード・展開はcombined_test.asm側の
    ENDING_SHOW_FINAL_IMAGEが、"MISSION COMPLETED"表示から実時間10秒
    経過した瞬間にだけwindowBを一時的にこのバンクへ切り替えて行う。"""
    sys.path.insert(0, os.path.join(HERE, "..", "bgm_data"))
    import bgm_bank_gen as bg
    _, layout = bg.build_bank()
    entry = layout["ENDING_IMAGE"]
    out = ["; ===== GFEnding final-image (SCREEN2, RLE-compressed) DATA moved to the "
           "shared bgm-data/chardata bank (2026-09-12), see SASAPI_QUADS' own comment "
           "in sasapi_gen.py for the same pattern ====="]
    out.append(f"ENDING_IMAGE_RLE_OFFSET EQU {entry['bank_offset']}")
    out.append(f"ENDING_IMAGE_RLE_SEGMENTS EQU {entry['segments']}")
    return "\n".join(out)


if __name__ == "__main__":
    payload = load_payload()
    compressed, segments = compressed_raw()
    print(f"EndingImage.SC2 payload: {len(payload)} -> {len(compressed)} bytes "
          f"({100*len(compressed)/len(payload):.1f}%, {segments} segments, "
          f"saved {len(payload)-len(compressed)} bytes)")
