"""BGMデータバンク(Round40)生成。midi_to_psg.pyが出力する周期テーブル+
両曲2ch分の行データを、Comb ROMの新規16KBバンク(旧Round39の0xFFパディング
予備バンクを流用、tools/bankswitch_poc/build_full_rom.py側でbank6として
差し込む)1本のバイトイメージへまとめる。

(2026-09-07、round64追記) このバンクはBGM専用ではなくなった - 曲データ
だけでは16KB中5割以上が未使用のまま余っていたため、Stage2ボス(Sasapi)の
64x64/32x32本体パターンデータ(tools/stage2_combined/sasapi_gen.py/
sasapi_hand_gen.py、合計1792byte)もこのバンクへ相乗りさせている
(`layout["SASAPI_CHARDATA"]`、下記の曲データのすぐ後ろに追記)。
combined_test.asm側は曲データと全く同じ「必要な瞬間だけwindowBを一時的に
このバンクへ切替てLDIRVM」方式でボス出現直前にだけロードする
(SWITCH_TO_CHARDATA_BANK/RESTORE_OWN_BANK_B参照)。

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

    # GAME_OVER(2026-09-08、"ではゲームオーバーBGM..."には著作権上の
    # 理由でお断りし、代わりにユーザー自身のオリジナル作曲(和音入り
    # MIDI)を試聴確認の上で採用・"これで組み込んでくれ"): 2パート
    # (melody=chB/harmony=chC、chAは使わない)・END_MARK(一度きり、
    # ループしない)方式 - ENDING_GFENDINGと同じ考え方(ゲームオーバー
    # 演出は「曲の終わりを迎えたら無音のまま保持」で十分、StageClearの
    # ような外部実時間タイマーによる強制遷移は無い)。
    tm, th = mp.load_game_over_parts()
    bm, bh = (mp.rows_to_bytes(tm, terminator=mp.END_MARK),
              mp.rows_to_bytes(th, terminator=mp.END_MARK))
    song_offset = len(blob)
    blob += bm
    blob += bh
    layout["GAME_OVER"] = {
        "bank_offset": song_offset,
        "chB_len": len(bm),
        "chC_len": len(bh),
    }

    # (2026-09-07、"ステージ2スタートでキャラクター定義データを他の
    # バンクに逃がしてしまえばかなり開くだろう ボスだけでもかなり空くの
    # では"): この時点でblobはまだ16KB中の一部しか使っていない(曲データ
    # 合計は5桁byte未満)。Sasapi(Stage2ボス)の64x64/32x32本体パターン
    # データ(tools/stage2_combined/sasapi_gen.py/sasapi_hand_gen.pyが
    # 生成、合計1792byte)は元々combined_test.asm自身に直接DB展開されて
    # いたが、Stage2 ROMの空き容量が実質枯渇していた(残り1byte)ため
    # このバンクの空き領域(BGM本体だけでは16KB中11KB以上が空き)へ
    # 相乗りさせる。ボス出現/形態変化/向き反転の瞬間にだけ必要な
    # データのため、曲データと全く同じ「必要な瞬間だけwindowBを一時的に
    # このバンクへ切替てLDIRVM」方式がそのまま使える(combined_test.asm
    # 側のSWITCH_TO_CHARDATA_BANK/RESTORE_OWN_BANK_B参照)。
    sys.path.insert(0, os.path.join(HERE, "..", "title_screen"))
    import title_bg_gen  # noqa: E402  (rle_encode/rle_decode、SASAPI/STAGE1ボスchardata圧縮に流用)
    sys.path.insert(0, os.path.join(HERE, "..", "stage2_combined"))
    import sasapi_gen as sg
    import sasapi_hand_gen as shg

    # (2026-09-14、"次にキャラデータはかなり圧縮ができる筈 RLEで十分だろう
    # 逐次読み込みはステージ1も2もボスくらいのはず なので初期状態で
    # キャラデータはVramに転送済みのはずなんで圧縮展開しても問題は無い
    # はず"): この5ブロックは全てボス出現/形態変化/向き反転という
    # "逐次読み込み"(non-init)の瞬間にしか読まれない(タイトル画面
    # ロード後にVRAMへ既に転送済みの他の全キャラクターデータと違う点)
    # ため、ENDING_IMAGE/タイトル背景と全く同じ自前RLE
    # (tools/title_screen/title_bg_gen.pyのrle_encode/rle_decode)で
    # 圧縮する。展開はcombined_test.asm側のLOAD_SASAPI_PATTERNS/
    # LOAD_SASAPI_BROKEN_PATTERNS/INITのSASAPI_HAND_TILESロードが、
    # 既存のSWITCH_TO_CHARDATA_BANK切替に続けてVRAMへ直接ストリーム
    # 展開する(新設DECOMPRESS_RLE_TO_VRAM共有ルーチン、ENDING_SHOW_
    # FINAL_IMAGEのインラインデコードをサブルーチン化したもの)。
    chardata_layout = {}
    quads, quads_l = sg.sasapi_quads_raw()
    bquads, bquads_l = sg.sasapi_broken_quads_raw()
    hand_bytes = bytes(b for tile in shg.SASAPI_HAND_TILES for b in tile)
    for key, data in [
        ("SASAPI_QUADS", quads),
        ("SASAPI_QUADS_L", quads_l),
        ("SASAPI_BROKEN_QUADS", bquads),
        ("SASAPI_BROKEN_QUADS_L", bquads_l),
        ("SASAPI_HAND_TILES", hand_bytes),
    ]:
        compressed, segments = title_bg_gen.rle_encode(data)
        assert title_bg_gen.rle_decode(compressed, segments) == data, \
            f"RLE round-trip mismatch for {key} - encoder bug"
        chardata_layout[key] = {
            "bank_offset": len(blob),
            "len": len(compressed),
            "segments": segments,
        }
        blob += compressed
    layout["SASAPI_CHARDATA"] = chardata_layout

    # ENDING_IMAGE(2026-09-12、"ではこの画像をMission completed表示後
    # 10秒したら表示...タイトル表示同様に圧縮かけて"): GFEnding
    # "MISSION COMPLETED"表示から実時間10秒後に表示する最終SCREEN2
    # 画像(tools/stage2_combined/ending_image_gen.py、タイトルと同じ
    # 自前RLEで圧縮済み)。SASAPI_CHARDATAと全く同じ相乗り方式 -
    # Stage2本編は表示する瞬間だけwindowBをこのバンクへ切り替えて
    # ストリーム展開する(combined_test.asm側のENDING_SHOW_FINAL_IMAGE
    # 参照)。
    import ending_image_gen as eig
    img_compressed, img_segments = eig.compressed_raw()
    layout["ENDING_IMAGE"] = {
        "bank_offset": len(blob),
        "len": len(img_compressed),
        "segments": img_segments,
    }
    blob += img_compressed

    # STAGE1_BOSS_CHARDATA(round135follow-up16、"ボスを別バンクに移して
    # くれ だいぶ削減出来るはずだ"): src/CYBER SHMUP.asmのBOSS_PATTERNS
    # (ボス本体64x64、512byte)はBOSS_SPAWN内の1回のLDIRVM呼び出しでしか
    # 参照されない(ボス出現の瞬間に1回だけVRAMへ転送、以後CPUから直接
    # 読まれることはない)ため、Stage2のSASAPI_CHARDATAと全く同じ
    # 「一度きりのロード専用データ」条件を満たす。BOSS_HEX_PATTERN/
    # BOSS_ORBIT_PATTERN/DFL_BULLET_PATTERN/EXPLOSION_PATTERN(各32byte、
    # 計128byte)も条件的には同様に移設可能だが、このバンクの実際の
    # 空き容量(ENDING_IMAGE追加後で522byte)が640byte全部には足りず
    # (522<640)、512byteのBOSS_PATTERNS単体(522byte以内に収まる、
    # 削減効果の大部分を占める)だけを移設する現実的な落とし所とした。
    # ただしStage1は(Round40の判断により)自分ではバンク切替を一切
    # 行わない設計を維持するため、Stage2方式(実行時にwindow Bを一時
    # 切替)ではなく、Title起動時にこのバンクからStage1専用RAM(src/
    # CYBER SHMUP.asmのBOSS_PATTERNS、0xCD8D)へ事前コピーする既存の
    # BGM/TryZ/ジングル方式をそのまま踏襲する。生バイトはASMのDB羅列
    # から一度だけ機械的に抽出しキャッシュしたtools/bgm_data/
    # stage1_boss_chardata.bin(512byte)を元に、以下で追記。
    # (2026-09-14、"キャラデータはかなり圧縮ができる筈 RLEで十分だろう"):
    # ここもSASAPI_CHARDATAと同じ自前RLEで圧縮(512byte->約290byte、
    # bank6の空き確保に直接効く一番大きな削減source)。TitleはコピーAT
    # 起動時に圧縮バイトのままRAM(0xCD8D)へコピーするだけ(コピー量も
    # 512byte->約290byteへ減りRAMも節約)、実際の展開はStage1自身の
    # BOSS_SPAWNがVRAM書き込み時に1回だけ行う(DECOMPRESS_RLE_TO_VRAM、
    # Stage2のLOAD_SASAPI_PATTERNS用と全く同じ共有ルーチンをStage1にも
    # 複製 - Stage1はバンク切替をしないためRAM上の圧縮データを直接
    # ソースにできる、Z80命令列自体はROM/RAMどちらが入力でも同一)。
    with open(os.path.join(HERE, "stage1_boss_chardata.bin"), "rb") as f:
        stage1_boss_chardata = f.read()
    assert len(stage1_boss_chardata) == 512
    stage1_boss_compressed, stage1_boss_segments = title_bg_gen.rle_encode(stage1_boss_chardata)
    assert title_bg_gen.rle_decode(stage1_boss_compressed, stage1_boss_segments) == stage1_boss_chardata, \
        "RLE round-trip mismatch for STAGE1_BOSS_CHARDATA - encoder bug"
    layout["STAGE1_BOSS_CHARDATA"] = {
        "bank_offset": len(blob),
        "len": len(stage1_boss_compressed),
        "raw_len": len(stage1_boss_chardata),
        "segments": stage1_boss_segments,
    }
    blob += stage1_boss_compressed

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
        if key not in ("SASAPI_CHARDATA", "ENDING_IMAGE", "STAGE1_BOSS_CHARDATA"):  # not songs - song_constants() doesn't apply
            print("  constants:", song_constants(key))
