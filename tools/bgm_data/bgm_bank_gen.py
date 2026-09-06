"""BGMデータバンク(Round40)生成。midi_to_psg.pyが出力する周期テーブル+
両曲2ch分の行データを、Comb ROMの新規16KBバンク(旧Round39の0xFFパディング
予備バンクを流用、tools/bankswitch_poc/build_full_rom.py側でbank6として
差し込む)1本のバイトイメージへまとめる。

レイアウト(バンク先頭からのオフセット、全てPython側で確定させ、各
ステージのASM側にはリテラル値として埋め込む - このアセンブラ
[mini_z80asm.py]は演算子優先順位を持たず式は左から右へ逐次評価される
ため、複数演算を含む式はこれまで繰り返しバグの温床になってきた
[round36-14 follow-up#8のBASE+N*4、round39のNAMTBL+20*32+11] - 今回は
最初から全アドレスをPython側で計算した単一リテラルとして埋め込むことで
この種のバグ自体を作らない):

  offset 0                         : PERIOD_LO[NUM_NOTES]
  offset NUM_NOTES                 : PERIOD_HI[NUM_NOTES]
  offset 2*NUM_NOTES               : ALONE_FIGHTER track0(chB用) + LOOP_MARK
  offset ...                       : ALONE_FIGHTER track1(chC用) + LOOP_MARK
  offset ...                       : DEFEAT track0(chB用) + LOOP_MARK
  offset ...                       : DEFEAT track1(chC用) + LOOP_MARK

RAM側のコピー先(BGM_DATA_BASE、C000h固定・全ステージ共通)は常に
「周期テーブル(2*NUM_NOTES bytes)を先頭からLDIR」+「その時点で必要な
1曲分(chB+chC、曲によって長さが違う)を周期テーブルの直後にLDIR」の
2回のLDIRで完結する - 曲ごとにバンク内オフセットは違うが、コピー先は
常にBGM_DATA_BASE+2*NUM_NOTES固定なので、駆動側(BGM_TICK)のコードは
曲に依存しない共通コードのまま、曲選択は「どのオフセットからLDIRするか」
というINIT側の定数だけで切り替わる。

重要: `mido`(MIDI解析ライブラリ)はこのファイルの生成時(`python3
bgm_bank_gen.py --generate`)にのみ必要で、実行時(通常のimport・
build_bank()/song_constants()呼び出し)には一切必要ない - 生成結果は
`bgm_bank.bin`(16KBバンクイメージそのもの)+`bgm_layout.json`(曲ごとの
オフセット/長さ)としてこのディレクトリにキャッシュ・git管理し、通常は
そのキャッシュを読むだけにしてある。理由: tools/stage2_combined/
build_test.pyのBankedMemが(bgm_test.py以外の)ほぼ全てのStage2回帰
テストのfresh_cpu()経由で毎回このモジュールを読み込むため、`mido`を
実行時の必須依存にすると「BGMと無関係な40本以上のテストがpypy3環境
(run_all.pyがpypy3を優先使用、pip installした`mido`はpypy3側には無い)
で軒並みModuleNotFoundErrorでクラッシュする」という実際に起きた事故が
あった - `import midi_to_psg`(内部で`import mido`)はこのファイルの
トップレベルでは行わず、生成専用の関数の中でのみ遅延importする。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

BANK_SIZE = 0x4000  # ASCII16の1バンク=16KB
# (2026-09-06、TryZ/GFEnding追加に伴い35→60へ拡張、
# tools/bgm_data/midi_to_psg.pyのMIDI_MIN/MAX[32,91]自身のコメント参照)
# StageClear追加時(同日)はテーブル自体は拡張せず、範囲外に落ちる
# ベースパートだけ+1オクターブシフトして収める方針にしたため60のまま
# 変化なし(load_stage_clear_parts()自身のコメント参照)。
NUM_NOTES = 60       # tools/bgm_data/midi_to_psg.py参照 - キャッシュ済み
                      # 生成結果と独立に固定; 生成時にmidi_to_psg.NUM_NOTESと
                      # 一致することをアサートする。

BANK_BIN_PATH = os.path.join(HERE, "bgm_bank.bin")
LAYOUT_JSON_PATH = os.path.join(HERE, "bgm_layout.json")

# デフォルトのRAM配置(Title/Stage1向け - どちらもC000h-DFFFhを全く
# 使っていないため、そのままC000h起点でよい)。
# Stage2(combined_test.asm)は既にC000h-C173h付近を大量の実データ
# (SBEAM_SPRITE_ATTRS/FLYER_POOL/BOSS_BROKEN_*/EBULLET_POOL/MINE_POOL/
# BULLET3_*等)で使い切っており衝突するため、Stage2は
# STAGE2_DATA_BASE(0xC200、実測で空きと確認済みの領域 - 次の実使用
# シンボルはEF00hのTICKで、C200h-EEFFhの約11.7KBが丸ごと空き)を明示的に
# 指定してsong_constants()を呼ぶこと。
BGM_DATA_BASE = 0xC000
STAGE2_DATA_BASE = 0xC200
# (2026-09-06、TryZ/GFEnding追加時に0x800→0x900へ拡張・自己発見バグ修正)
# 周期テーブルをNUM_NOTES35→60へ拡張した際、旧CONTROL_OFFSET=0x800
# (2048)のままだと「2*NUM_NOTES(120)+最長曲DEFEATの総データ長(1938)=
# 2058」が2048を10byte超過し、曲データの末尾がBGM_B_PTR等の制御変数
# 領域と物理的に重なる(=曲データの終端がその瞬間だけ制御変数を
# 破壊するが、INIT_BGM側がその直後に制御変数を明示的に再初期化する
# ため実害としては顕在化しない一方、回帰テストの「コピー直後の内容が
# バイト単位で一致するか」という検証では確実に検出される)という
# RAM衝突を実際に踏んだ - 新規テスト(bgm_test.py)のFAILで発覚・
# 自己修正。0x900(2304)なら現状の最長曲(DEFEAT、2058byte)に対し
# 246byteの余裕があり、当面の曲追加程度では再発しない。
CONTROL_OFFSET = 0x900  # データ本体からのオフセット(全曲共通、制御変数用)


# 実機フィードバック対応("BGMが1chしかなってない...HWエンベロープは
# コントロール不能と判断 ソフトに切り替える"): AY-3-8910のエンベロープ
# ジェネレータはチップ全体で1個しか無い共有リソースのため、2ch独立
# タイミングの音楽ドライバとは根本的に相性が悪いと実機テストで判明、
# HWエンベロープ(R11-R13)は完全に撤回。パート1(chB)=BELL形状+
# デューティ比50%、パート2(chC)=LINEAR形状+デューティ無し、という
# 最終選定(試聴ツールでのユーザー選定結果)に基づき、各tickごとの
# 音量をソフトウェアで完全計算するテーブル駆動方式に置き換え済み。
# エンベロープテーブル(BGM_ENV_BELL_TABLE/BGM_ENV_LINEAR_TABLE、RLE
# 圧縮された(level,duration)ペア列)・デューティマスク(BGM_B_DUTY_MASK)
# は各ステージのASM側に直接定義されており、このPython側では管理しない
# (全ステージ共通の固定値のため、曲やRAM配置に応じて計算する必要が
# そもそも無い)。


def _ram_layout(data_base):
    period_lo = data_base
    period_hi = data_base + NUM_NOTES
    song_data = data_base + 2 * NUM_NOTES
    control_base = data_base + CONTROL_OFFSET
    return {
        "PERIOD_LO_RAM": period_lo,
        "PERIOD_HI_RAM": period_hi,
        "SONG_DATA_RAM": song_data,
        "BGM_B_PTR": control_base,
        "BGM_C_PTR": control_base + 2,
        "BGM_B_TIMER": control_base + 4,
        "BGM_C_TIMER": control_base + 5,
        "BGM_B_REST": control_base + 6,
        "BGM_C_REST": control_base + 7,
        # control_base+8~+14(7byte)はchB/chCそれぞれのエンベロープ状態
        # (BGM_B/C_ENV_LEVEL/IDX/CD・BGM_B_DUTY_PHASE)が既に占有している
        # - これらはこの_ram_layout()の管理外(各ステージのASM側に直接
        # ハードコードされた固定オフセット、bgm_bank_gen.py側では元々
        # 追跡していない、上のBGM_ENV_*_TABLEのコメント参照)。そのため
        # 新規のchA(harmony、3声目)関連フィールドは+15以降に置く
        # (+19~+21のENV_LEVEL/IDX/CDも同じ理由でASM側で直接ハード
        # コードし、ここでは管理しない)。
        "BGM_A_PTR": control_base + 15,
        "BGM_A_TIMER": control_base + 17,
        "BGM_A_REST": control_base + 18,
    }


# 後方互換のためのデフォルト値(Title/Stage1が使う、BGM_DATA_BASE=0xC000起点)
_default = _ram_layout(BGM_DATA_BASE)
PERIOD_LO_RAM = _default["PERIOD_LO_RAM"]
PERIOD_HI_RAM = _default["PERIOD_HI_RAM"]
SONG_DATA_RAM = _default["SONG_DATA_RAM"]
CONTROL_BASE = BGM_DATA_BASE + CONTROL_OFFSET
BGM_B_PTR = _default["BGM_B_PTR"]
BGM_C_PTR = _default["BGM_C_PTR"]
BGM_B_TIMER = _default["BGM_B_TIMER"]
BGM_C_TIMER = _default["BGM_C_TIMER"]
BGM_B_REST = _default["BGM_B_REST"]
BGM_C_REST = _default["BGM_C_REST"]


def _generate():
    """mido依存の実生成(キャッシュ再構築専用 - 通常の実行時パスからは
    呼ばれない)。"""
    import sys
    sys.path.insert(0, HERE)
    import midi_to_psg as mp
    assert mp.NUM_NOTES == NUM_NOTES

    lo, hi = mp.build_period_table()
    period_bytes = bytes(lo) + bytes(hi)
    assert len(period_bytes) == 2 * NUM_NOTES

    blob = bytearray(period_bytes)
    layout = {}
    for key in mp.SONGS:
        t0, t1 = mp.load_song_tracks(key)
        b0 = mp.rows_to_bytes(t0)
        b1 = mp.rows_to_bytes(t1)
        song_offset = len(blob)
        blob += b0
        blob += b1
        layout[key] = {
            "bank_offset": song_offset,
            "chB_len": len(b0),
            "chC_len": len(b1),
        }

    # BOSS_TRYZ(2026-09-06、"ではTryZをボス曲に...メロディ1パートベース
    # 1パートを抜き出して"): 通常のゲームBGMと同じ2パート・LOOP_MARK
    # (ループ再生)方式 - ボス出現時にDEFEATの代わりにこちらへ切り替える。
    t0, t1 = mp.load_boss_tryz_parts()
    b0, b1 = mp.rows_to_bytes(t0), mp.rows_to_bytes(t1)
    song_offset = len(blob)
    blob += b0
    blob += b1
    layout["BOSS_TRYZ"] = {
        "bank_offset": song_offset,
        "chB_len": len(b0),
        "chC_len": len(b1),
    }

    # ENDING_GFENDING(2026-09-06、"GFEndingを...再生 これは3音使って良い"):
    # 3パート(メロディ/ベース/ハーモニー=chB/chC/chA)・END_MARK(一度きり、
    # ループしない)方式。
    tm, tb, th = mp.load_ending_gfending_parts()
    bm, bb, bh = (mp.rows_to_bytes(tm, terminator=mp.END_MARK),
                  mp.rows_to_bytes(tb, terminator=mp.END_MARK),
                  mp.rows_to_bytes(th, terminator=mp.END_MARK))
    song_offset = len(blob)
    blob += bm
    blob += bb
    blob += bh
    layout["ENDING_GFENDING"] = {
        "bank_offset": song_offset,
        "chB_len": len(bm),
        "chC_len": len(bb),
        "chA_len": len(bh),
    }

    # STAGE_CLEAR(2026-09-06、"ステージ1と2のスコアを加算して...これを
    # ステージクリアで流して 3音使って良いんで"): 3パート(melody=chB/
    # bass=chC/harmony=chA)構成はENDING_GFENDINGと同型だが、こちらは
    # END_MARKではなくLOOP_MARK(ループ)を使う - GFEndingと違い「曲の
    # 自然な終わりを検出してから何かする」設計ではなく、外部の実時間
    # タイマー(Stage1側のSTAGE_CLEAR_ACT/STAGE_CLEAR_START)が曲の総
    # 長さちょうどで問答無用にStage2へのバンク切替へ進むため、ループ
    # 端に達しても実際に一巡することはまず無く(達したとしても頭に
    # 戻るだけで無音にはならない)、Stage1既存のBGMT_UPDATE_B/C
    # (ALONE_FIGHTER/TryZと同じLOOP_MARK専用実装)をそのまま再利用
    # でき、新規のEND_MARK対応コードが不要になる。
    tm, tb, th = mp.load_stage_clear_parts()
    bm, bb, bh = (mp.rows_to_bytes(tm, terminator=mp.LOOP_MARK),
                  mp.rows_to_bytes(tb, terminator=mp.LOOP_MARK),
                  mp.rows_to_bytes(th, terminator=mp.LOOP_MARK))
    song_offset = len(blob)
    blob += bm
    blob += bb
    blob += bh
    layout["STAGE_CLEAR"] = {
        "bank_offset": song_offset,
        "chB_len": len(bm),
        "chC_len": len(bb),
        "chA_len": len(bh),
    }

    assert len(blob) <= BANK_SIZE, f"BGM data ({len(blob)} bytes) exceeds one 16KB bank"
    bank = bytes(blob) + bytes([0xFF] * (BANK_SIZE - len(blob)))
    return bank, layout


def generate_and_cache():
    """`python3 bgm_bank_gen.py --generate`専用。mido経由で実際にMIDIを
    解析し、結果をbgm_bank.bin/bgm_layout.jsonへ書き出す(git管理・
    以後の通常実行はこちらを読むだけ)。"""
    bank, layout = _generate()
    with open(BANK_BIN_PATH, "wb") as f:
        f.write(bank)
    with open(LAYOUT_JSON_PATH, "w") as f:
        json.dump(layout, f, indent=2, sort_keys=True)
    return bank, layout


def build_bank():
    """(16KBバンクイメージ, layout dict)をキャッシュファイルから読む -
    mido不要、通常の実行時パス。"""
    with open(BANK_BIN_PATH, "rb") as f:
        bank = f.read()
    assert len(bank) == BANK_SIZE, f"cached {BANK_BIN_PATH} is {len(bank)} bytes, expected {BANK_SIZE}"
    with open(LAYOUT_JSON_PATH) as f:
        layout = json.load(f)
    return bank, layout


def song_constants(song_key, data_base=BGM_DATA_BASE):
    """指定曲のASM側リテラル定数一式(dict)。呼び出し元(各ステージの
    combined_test.asm/title_test.asm/CYBER SHMUP.asm)はこれを直接
    埋め込むだけで、曲データそのもの(周期テーブル含む)は一切ハード
    コードしない。data_baseは各ファイル自身のRAM空き状況に応じて
    上書き可能(Stage2はSTAGE2_DATA_BASE、それ以外はデフォルトの
    BGM_DATA_BASEのままでよい - 上の_ram_layout()コメント参照)。"""
    _, layout = build_bank()
    entry = layout[song_key]
    bank_src_base = 0x8000  # windowB(7000hセレクタ)にマップされた時の先頭アドレス
    ram = _ram_layout(data_base)
    song_len = entry["chB_len"] + entry["chC_len"] + entry.get("chA_len", 0)
    out = {
        "PERIOD_SRC": bank_src_base,
        "PERIOD_LEN": 2 * NUM_NOTES,
        "PERIOD_LO_RAM": ram["PERIOD_LO_RAM"],
        "PERIOD_HI_RAM": ram["PERIOD_HI_RAM"],
        "SONG_SRC": bank_src_base + entry["bank_offset"],
        "SONG_LEN": song_len,
        "CHB_RAM_BASE": ram["SONG_DATA_RAM"],
        "CHC_RAM_BASE": ram["SONG_DATA_RAM"] + entry["chB_len"],
        "BGM_B_PTR": ram["BGM_B_PTR"],
        "BGM_C_PTR": ram["BGM_C_PTR"],
        "BGM_B_TIMER": ram["BGM_B_TIMER"],
        "BGM_C_TIMER": ram["BGM_C_TIMER"],
        "BGM_B_REST": ram["BGM_B_REST"],
        "BGM_C_REST": ram["BGM_C_REST"],
    }
    if "chA_len" in entry:
        # 3パート曲(現状ENDING_GFENDINGのみ) - chA(harmony)はchB/chCの
        # 直後に続けて配置。
        out["CHA_RAM_BASE"] = ram["SONG_DATA_RAM"] + entry["chB_len"] + entry["chC_len"]
        out["BGM_A_PTR"] = ram["BGM_A_PTR"]
        out["BGM_A_TIMER"] = ram["BGM_A_TIMER"]
        out["BGM_A_REST"] = ram["BGM_A_REST"]
    return out


if __name__ == "__main__":
    import sys
    if "--generate" in sys.argv:
        bank, layout = generate_and_cache()
        print(f"wrote {BANK_BIN_PATH} ({len(bank)} bytes) and {LAYOUT_JSON_PATH}")
    else:
        bank, layout = build_bank()
    used = BANK_SIZE
    while used > 0 and bank[used - 1] == 0xFF:
        used -= 1
    print(f"bank image: {len(bank)} bytes total, {used} bytes actually used, {len(bank)-used} bytes free")
    for key, info in layout.items():
        print(key, info)
        print("  constants:", song_constants(key))
