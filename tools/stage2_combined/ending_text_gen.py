"""エンディング用テキスト描画データ生成(2026-09-06、"Produced by
Kumanecoyarou と画面中央に表示...Mission Cmpletedと表示 全部大文字で")。

必要な文字は2つのメッセージの和集合のみ(全て大文字):
  "PRODUCED BY KUMANECOYAROU" -> P R O D U C E B Y K M A N (+space)
  "MISSION COMPLETED"         -> M I S O N C P L E T D (+space)
  和集合: A B C D E I K L M N O P R S T U Y (17文字) + space = 18グリフ

8x8のオリジナルドット絵(このプロジェクトの他の新規アセット同様、
実在フォントの複製ではなく新規に描き起こしたブロック体)。5列x7行を
8x8セルの中央寄り(左1列・下1行を余白)に収める、古典的なドットマトリクス
表示の定石に倣ったレイアウト。行は上から下、各行は文字列(8文字、
'#'=点灯/'.'=消灯、左が最上位ビット)。

呼び出し側(combined_test.asm)は、このモジュールが計算した
ENDING_FONT_BASE(パターンコード先頭、呼び出し側が指定する既存の空き
コード)を基準に、ENDING_MSG_CREDIT/ENDING_MSG_COMPLETE(ネームテーブル
コード列、既にENDING_FONT_BASEを加算済み)をそのままLDIRVMで書き込む
だけでよい - 実行時のASCII→パターンコード変換ロジックは一切不要
(この生成スクリプト自身がPython側で一度だけ計算するため)。

(2026-09-07、"GAME OVERフォントやステージ2クリア後の表示フォントは
添付ファイルを参考に"): "MISSION COMPLETED"表示のみ、tools/pixel_
font_8x8.py(ユーザー添付Font_24x24_1.jsonベースの8x8フォント)へ差し
替え。"PRODUCED BY KUMANECOYAROU"(CREDIT)は指示になかったため既存の
5x7フォントのまま維持。新規コード領域は確保せず、ENDING_FINISH
(CREDIT表示が完全にブランク書き換えされ二度と参照されなくなる瞬間)で
CREDIT用フォントと全く同じcode96-103+144-147を新フォントで上書き
ロードする「時間的共有」設計 - combined_test.asm側で新規に空きコード
探索をする必要がない。
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import pixel_font_8x8

# 5x7ドット(8x8セル内、上1行・右1列余白 - 実際は左詰め5列+右3列空白、
# 上1行空白+下0行、visually centered enough for a small HUD-like label)
_GLYPHS_5X7 = {
    "A": [
        ".####...",
        "#....#..",
        "#....#..",
        "######..",
        "#....#..",
        "#....#..",
        "#....#..",
    ],
    "B": [
        "#####...",
        "#....#..",
        "#....#..",
        "#####...",
        "#....#..",
        "#....#..",
        "#####...",
    ],
    "C": [
        ".####...",
        "#....#..",
        "#.......",
        "#.......",
        "#.......",
        "#....#..",
        ".####...",
    ],
    "D": [
        "#####...",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        "#####...",
    ],
    "E": [
        "######..",
        "#.......",
        "#.......",
        "#####...",
        "#.......",
        "#.......",
        "######..",
    ],
    "I": [
        "#####...",
        "..#.....",
        "..#.....",
        "..#.....",
        "..#.....",
        "..#.....",
        "#####...",
    ],
    "K": [
        "#....#..",
        "#...#...",
        "#..#....",
        "###.....",
        "#..#....",
        "#...#...",
        "#....#..",
    ],
    "L": [
        "#.......",
        "#.......",
        "#.......",
        "#.......",
        "#.......",
        "#.......",
        "######..",
    ],
    "M": [
        "#.....#.",
        "##...##.",
        "#.#.#.#.",
        "#..#..#.",
        "#.....#.",
        "#.....#.",
        "#.....#.",
    ],
    "N": [
        "#....#..",
        "##...#..",
        "#.#..#..",
        "#..#.#..",
        "#...##..",
        "#....#..",
        "#....#..",
    ],
    "O": [
        ".####...",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        ".####...",
    ],
    "P": [
        "#####...",
        "#....#..",
        "#....#..",
        "#####...",
        "#.......",
        "#.......",
        "#.......",
    ],
    "R": [
        "#####...",
        "#....#..",
        "#....#..",
        "#####...",
        "#..#....",
        "#...#...",
        "#....#..",
    ],
    "S": [
        ".####...",
        "#....#..",
        "#.......",
        ".####...",
        "......#.",
        "#....#..",
        ".####...",
    ],
    "T": [
        "######..",
        "..#.....",
        "..#.....",
        "..#.....",
        "..#.....",
        "..#.....",
        "..#.....",
    ],
    "U": [
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        "#....#..",
        ".####...",
    ],
    "Y": [
        "#....#..",
        "#....#..",
        ".#..#...",
        "..##....",
        "..#.....",
        "..#.....",
        "..#.....",
    ],
    " ": [
        "........",
        "........",
        "........",
        "........",
        "........",
        "........",
        "........",
    ],
}

# 実パターンコード割り当て(2026-09-06、combined_test.asmの実VRAM調査で
# 確定): ボス戦専用で「ボスが倒された以上二度と使われない」と確認済みの
# 3グループへ分散配置(この生成スクリプト自身は空きコード探索を一切
# 行わない - 実際の探索・安全性の根拠はcombined_test.asm側のUPDATE_
# ENDING_INIT自身の長いコメント参照)。
#   group12(96-103, HORMING_BG_SAND) : A B C D E I K L
#   group18(144-151, HORMING_BG)     : M N O P R S T U
#   group19先頭2つ(152-153, BOSS_EXPL_WHITE/SASAPI_HAND) : Y (space)
CODE_MAP = {
    "A": 96, "B": 97, "C": 98, "D": 99, "E": 100, "I": 101, "K": 102, "L": 103,
    "M": 144, "N": 145, "O": 146, "P": 147, "R": 148, "S": 149, "T": 150, "U": 151,
    "Y": 152, " ": 153,
}
assert set(CODE_MAP) == set(_GLYPHS_5X7)

# LDIRVM単位(パターンコード的に連続しているブロック)3つ - 各要素は
# (先頭コード, [そのブロックに含まれる文字を先頭コード順に並べたもの])。
CODE_BLOCKS = [
    (96, list("ABCDEIKL")),
    (144, list("MNOPRSTU")),
    (152, ["Y", " "]),
]

CREDIT_TEXT = "PRODUCED BY KUMANECOYAROU"
COMPLETE_TEXT = "MISSION COMPLETED"

# (2026-09-07、"ステージ2クリア後の表示フォントは添付ファイルを参考に"):
# "MISSION COMPLETED"専用、tools/pixel_font_8x8.py(添付Font_24x24_
# 1.jsonベース)の12グリフ(M,I,S,O,N,space,C,P,L,T,D,E)。上のCODE_MAP
# (CREDIT用5x7フォント)と全く同じcode96-103+144-147を再利用する -
# ENDING_FINISHの時点でCREDIT表示は全幅ブランクされ二度と参照されない
# ため、新規コード領域なしで安全に上書きできる(モジュール冒頭コメント
# 参照)。
COMPLETE_CODE_MAP = {
    "M": 96, "I": 97, "S": 98, "O": 99, "N": 100, " ": 101, "C": 102, "P": 103,
    "L": 144, "T": 145, "D": 146, "E": 147,
}
assert set(COMPLETE_CODE_MAP) == set(COMPLETE_TEXT.replace(" ", "") + " ")

COMPLETE_CODE_BLOCKS = [
    (96, list("MISON CP")),
    (144, list("LTDE")),
]


def complete_font_bitmaps():
    """COMPLETE_CODE_BLOCKS各ブロックごとのビットマップ(8byte/グリフ)を
    [(先頭コード, バイト列), ...]として返す。"""
    out = []
    for base, chars in COMPLETE_CODE_BLOCKS:
        blob = []
        for ch in chars:
            blob.extend(pixel_font_8x8.glyph_bytes(ch))
        out.append((base, blob))
    return out


def complete_message_codes():
    return [COMPLETE_CODE_MAP[ch] for ch in COMPLETE_TEXT]


def _glyph_bytes(ch):
    rows = _GLYPHS_5X7[ch]
    assert len(rows) == 7 and all(len(r) == 8 for r in rows)
    out = [0]  # 上1行分の空白パディング(8行構成にするため)
    for row in rows:
        b = 0
        for i, c in enumerate(row):
            if c == "#":
                b |= 0x80 >> i
        out.append(b)
    assert len(out) == 8
    return out


def font_bitmaps():
    """CODE_BLOCKS各ブロックごとのビットマップ(8byte/グリフ)を
    [(先頭コード, バイト列), ...]として返す - 呼び出し側は各ブロックを
    1回のLDIRVMで対応するパターンコード位置(コード*8)へ書き込む。"""
    out = []
    for base, chars in CODE_BLOCKS:
        blob = []
        for ch in chars:
            blob.extend(_glyph_bytes(ch))
        out.append((base, blob))
    return out


def _codes_for(text):
    return [CODE_MAP[ch] for ch in text]


def message_codes():
    """(credit_codes, complete_codes) - 実際のパターンコード列。呼び出し側は
    これをそのままネームテーブルへLDIRVMするだけでよい。complete_codesは
    COMPLETE_CODE_MAP(新8x8フォント、complete_font_bitmaps()がロードする
    のと同じcode)を使う - CREDIT用の旧5x7フォントとは別物。"""
    return _codes_for(CREDIT_TEXT), complete_message_codes()


def db_bytes(values, per_line=16):
    lines = []
    for i in range(0, len(values), per_line):
        lines.append("    DB " + ",".join(str(v) for v in values[i:i + per_line]))
    return "\n".join(lines)


def num_glyphs():
    return len(CODE_MAP)


def emit_asm_tables():
    """combined_test.asmへ埋め込むASMテーブル一式(文字列)。3つのビット
    マップブロック(ENDING_FONT_BLOCK0/1/2、それぞれ対応するCODE_BLOCKS
    先頭コード*8への1回のLDIRVMでロードする想定)と、2つのメッセージの
    ネームテーブルコード列(ENDING_MSG_CREDIT/ENDING_MSG_COMPLETE)。"""
    blocks = font_bitmaps()
    credit, complete = message_codes()
    lines = ["; ===== エンディング用テキスト: ending_text_gen.pyが生成、直接編集しないこと ====="]
    for i, (base, blob) in enumerate(blocks):
        lines.append(f"ENDING_FONT_BLOCK{i}_CODE EQU {base}")
        lines.append(f"ENDING_FONT_BLOCK{i}_LEN EQU {len(blob)}")
        lines.append(f"ENDING_FONT_BLOCK{i}:")
        lines.append(db_bytes(blob))
    lines.append(f"ENDING_MSG_CREDIT_LEN EQU {len(credit)}")
    lines.append("ENDING_MSG_CREDIT:")
    lines.append(db_bytes(credit))
    lines.append(f"ENDING_MSG_COMPLETE_LEN EQU {len(complete)}")
    lines.append("ENDING_MSG_COMPLETE:")
    lines.append(db_bytes(complete))
    # HUD_ROW_BLANK_CODE(combined_test.asm本体のEQU、120)を32個並べた
    # だけの行 - "MISSION COMPLETED"表示前に前の"PRODUCED BY..."の残り
    # (25文字、こちらより8文字長い)を消すための全幅ブランク書き込み用。
    # 値はcombined_test.asm本体のHUD_ROW_BLANK_CODEと一致させること。
    lines.append("ENDING_BLANK_ROW32:")
    lines.append(db_bytes([120] * 32))
    # "MISSION COMPLETED"専用の新8x8フォント(2ブロック、ENDING_FINISHが
    # CREDIT表示消去と同じタイミングでロードする - モジュール冒頭コメント
    # 参照)。
    complete_blocks = complete_font_bitmaps()
    for i, (base, blob) in enumerate(complete_blocks):
        lines.append(f"ENDING_COMPLETE_FONT_BLOCK{i}_CODE EQU {base}")
        lines.append(f"ENDING_COMPLETE_FONT_BLOCK{i}_LEN EQU {len(blob)}")
        lines.append(f"ENDING_COMPLETE_FONT_BLOCK{i}:")
        lines.append(db_bytes(blob))
    return "\n".join(lines)


if __name__ == "__main__":
    blocks = font_bitmaps()
    total = sum(len(b) for _, b in blocks)
    print(f"{num_glyphs()} glyphs, {len(blocks)} blocks, {total} bytes bitmap total")
    for base, blob in blocks:
        print(f"  block base={base} ({len(blob)//8} glyphs, {len(blob)} bytes)")
    credit, complete = message_codes()
    print("credit codes  :", credit, f"len={len(credit)}")
    print("complete codes:", complete, f"len={len(complete)}")
