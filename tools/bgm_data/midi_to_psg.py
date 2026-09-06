"""MIDI -> PSGノートデータ変換パイプライン(Round40、"では添付ファイルの
MIDIをノートだけ抽出してPSGで鳴らしてくれ どちらも2ch分のデータになって
るがMIDIなのでサイズが大きい で、方法としては先ほどのRAM方式で転送
タイトル含めて各ステージにドライバを配置しRAMにコピーしてステージ
スタート")。

tools/bgm_data/midi/Alone_Fighter.mid・Defeat_.mid(いずれもSMF type1、
120 ticks/beat、テンポ変更なし=一定120BPM、2トラック=2ch、両トラックとも
真にモノフォニック(和音なし)であることを事前に`mido`で確認済み)を、
PSGチャンネルB/Cへそのまま1:1で流し込める「(note_index, duration)行」の
列に変換する。

tick変換: 1 vblank tick(H.TIMI呼び出し1回) = 4 MIDI tick(検証済み、
120 ticks/beat・500000us/quarterのテンポでmid.length[秒]と正確に一致)。
端数を累積させずに済むよう、絶対MIDI tick位置をfloor(pos/4)でvblank tick
境界へ変換してから差分を取る方式(丸め誤差が後続へ持ち越されない)。

ノート範囲: 両ファイル4トラックの実測範囲はMIDIノート50-84(調査済み)。
周期テーブルはこの範囲をそのままindex0-34として直接カバーする
(bgm_gen.py旧来のノート名テーブルとは独立、MIDI番号直接キー方式 - 名前
テーブル経由の間接参照はもう不要なため、混乱を避けるためあえて別実装)。

OCTAVE_SHIFT(実機フィードバック"ではどっちの曲もオクターブ下げてくれ"):
生MIDIノート番号から`-OCTAVE_SEMITONES`(12半音=1オクターブ)した値を
実際の周期テーブル参照キーとして使う。MIDI_MIN/MIDI_MAXはシフト後の
範囲(50-84から-12した38-72)を表す - つまりテーブル自体・行データ
双方ともシフト後の値で一貫して構築される(このモジュールの外から見て
「もう1オクターブ低い音」以外の違いは無い)。
"""
import os
import mido

HERE = os.path.dirname(os.path.abspath(__file__))
MIDI_DIR = os.path.join(HERE, "midi")

PSG_CLOCK = 3579545 / 2  # 1789772.5Hz - MSX AY-3-8910互換PSGの入力クロック

OCTAVE_SEMITONES = 12
OCTAVE_SHIFT = -OCTAVE_SEMITONES  # 実機フィードバックで両曲とも1オクターブ下げ

# (2026-09-06、TryZ/GFEnding追加時に拡張): 元々はALONE_FIGHTER/DEFEATの
# 2曲だけ(共にOCTAVE_SHIFT適用後38-72)を想定した範囲だったが、新曲2曲
# (ボス曲TryZ・エンディングGFEnding)はオクターブシフトを掛けずに生の
# MIDIノートをそのままインデックスに使う設計にしたため、実測した4曲
# 全体の和集合(TryZの2パート、GFEndingの3パート、共にシフト無し)を
# 素直にカバーできるよう32-91へ拡張した。テーブルは全曲共通の1個の
# ため、コストは2byte/note(今回+50byte)で全曲に波及するが、既存2曲は
# 生成のたびに新しい範囲に合わせて丸ごと再計算されるため後方互換の
# 心配は無い(手書きの固定データではなく、毎回mido経由で再生成する
# キャッシュのため)。
MIDI_MIN = 32
MIDI_MAX = 91
NUM_NOTES = MIDI_MAX - MIDI_MIN + 1  # 60

NOTE_REST = 0xFF
LOOP_MARK = 0xFE
END_MARK = 0xFD  # エンディング専用: ループせず、以後この行を無音のまま保持する終端マーク

MIDI_TICKS_PER_VBLANK = 4

# 実機フィードバック"Stage1のBGMのテンポを少し速く"対応: Stage1(および
# タイトルが起動時に同じデータをコピーするだけの)ALONE_FIGHTERだけ、
# 曲固有のテンポ倍率でMIDI_TICKS_PER_VBLANKを底上げする(1 vblank tickに
# 詰め込むMIDI tick数が増える=同じ音符が短い実時間で終わる=速くなる)。
# DEFEAT(Stage2)は今回のスコープ外のため1.0のまま無変更。
TEMPO_SCALE = {
    "ALONE_FIGHTER": 1.1,
    "DEFEAT": 1.0,
}

SONGS = {
    "ALONE_FIGHTER": "Alone_Fighter.mid",
    "DEFEAT": "Defeat_.mid",
}


def note_freq(midi_note):
    return 440.0 * (2.0 ** ((midi_note - 69) / 12.0))


def tone_period(freq):
    return round(PSG_CLOCK / (16.0 * freq))


def build_period_table():
    lo = []
    hi = []
    for midi_note in range(MIDI_MIN, MIDI_MAX + 1):
        period = tone_period(note_freq(midi_note))
        assert 0 < period < 4096, (midi_note, period)
        lo.append(period & 0xFF)
        hi.append((period >> 8) & 0x0F)
    return lo, hi


def _track_segments(track, octave_shift=OCTAVE_SHIFT):
    """1トラック分のnote_on/offを歩いて(start_tick, end_tick, note)の
    列を作る。真にモノフォニックであることは事前確認済みなので、常に
    「前のノートを閉じてから次を開く」の単純な状態機械で足りる。
    octave_shift: 呼び出し元が明示的に0を渡せば無変換(TryZ/GFEnding用、
    生MIDIノートをそのままインデックスキーに使う設計)。省略時は
    ALONE_FIGHTER/DEFEAT向けの既定値(-12)のまま。"""
    segments = []
    abs_time = 0
    cur_note = None
    cur_start = 0
    for msg in track:
        abs_time += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            if cur_note is not None:
                segments.append((cur_start, abs_time, cur_note))
            cur_note = msg.note + octave_shift
            cur_start = abs_time
        elif (msg.type == "note_off") or (msg.type == "note_on" and msg.velocity == 0):
            if cur_note is not None and msg.note + octave_shift == cur_note:
                segments.append((cur_start, abs_time, cur_note))
                cur_note = None
    if cur_note is not None:
        segments.append((cur_start, abs_time, cur_note))
    total_ticks = abs_time
    return segments, total_ticks


def _rows_from_segments(segments, total_ticks, ticks_per_vblank=MIDI_TICKS_PER_VBLANK):
    """segments(重複無し、モノフォニック前提)+トラック全長から、
    無音区間も含めた完全な(note_or_rest, start_tick, end_tick)区間列を
    作り、MIDI tick境界をvblank tick境界へfloor変換した上で
    (note_index_or_REST, duration_vblank_ticks)行へ変換する。
    ticks_per_vblank(既定はグローバルのMIDI_TICKS_PER_VBLANK)を曲ごとに
    大きくすると、同じMIDI tick差分がより少ないvblank tickへ丸められる
    - つまり同じ音楽的な長さがより短い実時間で再生される(テンポが
    速くなる)。絶対MIDI tick位置をfloorしてから差分を取る方式のため、
    非整数の値を渡しても端数が後続行へ累積することはない。"""
    intervals = []
    cursor = 0
    for (s, e, note) in segments:
        if s > cursor:
            intervals.append((NOTE_REST, cursor, s))
        intervals.append((note, s, e))
        cursor = e
    if cursor < total_ticks:
        intervals.append((NOTE_REST, cursor, total_ticks))

    rows = []
    for (note, s, e) in intervals:
        vb_s = int(s // ticks_per_vblank)
        vb_e = int(e // ticks_per_vblank)
        dur = vb_e - vb_s
        if dur <= 0:
            continue  # 丸めで消えた極短区間(次の区間へ吸収される)
        note_idx = NOTE_REST if note == NOTE_REST else note - MIDI_MIN
        if note_idx != NOTE_REST:
            assert 0 <= note_idx < NUM_NOTES, (note, note_idx)
        # 1バイトduration上限(255)を超える長い音/休符は同じnoteの複数行へ分割
        while dur > 0:
            chunk = min(dur, 255)
            rows.append((note_idx, chunk))
            dur -= chunk

    # 隣接する同一note+休符の結合(丸めで生じた1行未満の断片を除きサイズ削減、
    # 255上限で分割された行同士は結合しない=別行のまま、という意図は無い
    # ため、まず255未満同士の隣接同一noteだけ結合する)
    merged = []
    for note_idx, dur in rows:
        if merged and merged[-1][0] == note_idx and merged[-1][1] + dur <= 255:
            prev_note, prev_dur = merged[-1]
            merged[-1] = (prev_note, prev_dur + dur)
        else:
            merged.append((note_idx, dur))
    return merged


def load_song_tracks(song_key):
    """song_key -> (track0_rows, track1_rows)。トラック0/1はファイル内の
    出現順そのまま(channelB=track0, channelC=track1という対応は
    build_test.py側の設計で固定)。"""
    path = os.path.join(MIDI_DIR, SONGS[song_key])
    mid = mido.MidiFile(path)
    assert mid.type == 1 and len(mid.tracks) == 2, (song_key, mid.type, len(mid.tracks))
    ticks_per_vblank = MIDI_TICKS_PER_VBLANK * TEMPO_SCALE.get(song_key, 1.0)
    result = []
    for track in mid.tracks:
        segments, total_ticks = _track_segments(track)
        rows = _rows_from_segments(segments, total_ticks, ticks_per_vblank)
        result.append(rows)
    return result[0], result[1]


def rows_to_bytes(rows, terminator=LOOP_MARK):
    """(note,duration)行の列 -> 2byte/行のバイト列 + 末尾ターミネータ
    (1byte)。terminator=LOOP_MARK(既定、ゲームBGM用、先頭へループ)/
    END_MARK(エンディング用、以後ループせず無音のまま保持)。"""
    out = bytearray()
    for note, dur in rows:
        assert 0 <= dur <= 255
        out.append(note & 0xFF)
        out.append(dur & 0xFF)
    out.append(terminator)
    return bytes(out)


# ===== TryZ(ボス曲)・GFEnding(エンディング曲) - Round(2026-09-06)追加 =====
# どちらもALONE_FIGHTER/DEFEATと違い「type1・ちょうど2トラック」という
# 単純な形をしていない(TryZは6トラック中3トラックが実際に鳴っている
# 楽器パート、GFEndingはtype0の単一トラックに12チャンネル分が混在)ため、
# SONGS辞書経由の汎用loaderには乗らない。個別に手作業でパート(メロディ/
# ベース/ハーモニー)を選び出す専用関数を用意する。

BOSS_TRYZ_FILE = "TryZ.mid"
ENDING_GFENDING_FILE = "GFEnding.mid"


def load_boss_tryz_parts():
    """TryZ.mid(type1、6トラック)から2パート抽出:
    - track2(channel1、"Sequenced by..."、57-72、326note、曲を通して
      最も活発に動く旋律)をメロディ(chB相当)に、
    - track3(channel2、67-71、32note、track1[channel0、76-78]と対を
      成す持続和音の低い方の声部)をベース(chC相当)に採用。
    track1(channel0、76-78)はtrack3より高い側の声部で、曲全体を通じて
    3.2秒に1回しか動かない(32note)ため今回は不採用(ユーザー指示は
    「メロディ1パートベース1パートを抜き出して」の2パートのみ)。
    track4(channel9)はGM打楽器チャンネルのためドラムであり音程パートで
    はない(不採用)。オクターブシフトは掛けない(生MIDIノートのままで
    既存の周期テーブル範囲[32,91]に収まる)。"""
    path = os.path.join(MIDI_DIR, BOSS_TRYZ_FILE)
    mid = mido.MidiFile(path)
    assert mid.type == 1 and len(mid.tracks) == 6, (mid.type, len(mid.tracks))
    melody_seg, melody_total = _track_segments(mid.tracks[2], octave_shift=0)
    bass_seg, bass_total = _track_segments(mid.tracks[3], octave_shift=0)
    melody_rows = _rows_from_segments(melody_seg, melody_total)
    bass_rows = _rows_from_segments(bass_seg, bass_total)
    return melody_rows, bass_rows


def _channel_events(mid):
    """mid(type0/1どちらでも可)の全トラックを、それぞれ自分のトラック
    内相対時間で絶対tickへ復元しつつ1つの(abs_tick, is_on, channel,
    note)列にまとめる。type1でトラックが複数でも各トラックの絶対時間は
    0始まりで揃っているため、そのまま合算してよい。"""
    events = []
    for track in mid.tracks:
        t = 0
        for msg in track:
            t += msg.time
            if msg.type == "note_on" and msg.velocity > 0:
                events.append((t, True, msg.channel, msg.note))
            elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
                events.append((t, False, msg.channel, msg.note))
    # 同一tickではoff→onの順に処理(次の音が同tickで始まる場合に、直前の
    # 音を確実に閉じてから開けるようにする)。
    events.sort(key=lambda e: (e[0], 0 if not e[1] else 1))
    return events


def _segments_for_channel(events, channel, top_note_only=False):
    """1チャンネル分の(start,end,note)区間列。top_note_only=Trueの場合、
    同一チャンネル内で複数ノートが重なっている(和音)区間は「その瞬間に
    鳴っている最高音」だけを採用するモノフォニック化を行う(GFEndingの
    chan0のような、1チャンネルに和音が積まれた区間の再現に使用)。
    top_note_only=Falseの場合はそのチャンネルが真にモノフォニックである
    ことを前提とする単純な状態機械(_track_segmentsと同型)。"""
    ch_events = [e for e in events if e[2] == channel]
    segments = []
    if not top_note_only:
        cur_note = None
        cur_start = None
        for (t, is_on, ch, note) in ch_events:
            if is_on:
                if cur_note is not None:
                    segments.append((cur_start, t, cur_note))
                cur_note = note
                cur_start = t
            else:
                if cur_note == note:
                    segments.append((cur_start, t, cur_note))
                    cur_note = None
        return segments
    active = set()
    cur_note = None
    cur_start = None
    for (t, is_on, ch, note) in ch_events:
        prev_top = max(active) if active else None
        if is_on:
            active.add(note)
        else:
            active.discard(note)
        new_top = max(active) if active else None
        if new_top != prev_top:
            if cur_note is not None:
                segments.append((cur_start, t, cur_note))
            cur_note = new_top
            cur_start = t
    return segments


def _merge_parts(parts):
    """parts: [(segments, window_start, window_end), ...] - 各ソースを
    自分のwindowでクリップしてから連結・時刻順に整列し、隣接ソース間で
    重複が無いことを検証する(重複があれば、そもそものパート分割設計が
    間違っている証拠なのでAssertionErrorで早期に発覚させる)。"""
    combined = []
    for segments, w_start, w_end in parts:
        for (s, e, note) in segments:
            cs, ce = max(s, w_start), min(e, w_end)
            if ce > cs:
                combined.append((cs, ce, note))
    combined.sort()
    for i in range(1, len(combined)):
        assert combined[i][0] >= combined[i - 1][1], (
            f"GFEnding part overlap at {combined[i-1]} vs {combined[i]}"
        )
    return combined


def load_ending_gfending_parts():
    """GFEnding.mid(type0、単一トラックに12チャンネル混在)から3パート
    抽出(ユーザー: "これは3音使って良い" - ゲーム中と違いchAもSE用途と
    競合しないため3ch使用可):

    - MELODY: chan11(Electric Piano2、74-91、112note、2.4-20.1秒、
      曲中最も活発で音域も最も高い=主旋律)を軸に、そのあとの静寂の
      コーダ部分をchan0の和音の最高音(top-note化、23.18-24.52秒)→
      chan1(単声、24.75-26.09秒)の順に継ぎ足して曲の終わりまで途切れず
      続くメロディラインを構成。
    - BASS: chan12(Fretless Bass、32-45、2.4-12.61秒までの前半)→
      chan9(Piano、36-57、12.61-26.09秒の後半、実測でchan12停止直後
      から始まっており重複なし)の順に繋いだ低音パート。
    - HARMONY(3声目、chA相当): chan6(Electric Guitar和音スタックの
      うち1チャンネル分、55-77、2.4-20.55秒) - chan6/7/8/10はほぼ同一
      内容を0.2-0.4秒ずつずらして4chに重ねた和音の各声部(元々の
      General MIDI書き出し時のポリフォニー都合による分割)なので、
      代表して1本だけ採用(残り3本は捨てる、単音のPSGでは元々4声を
      完全再現できないため妥当な単純化)。

    いずれもオクターブシフトは掛けない(生MIDIノートのまま、既存の
    周期テーブル範囲[32,91]で全パートの全ノートをカバー済み)。"""
    path = os.path.join(MIDI_DIR, ENDING_GFENDING_FILE)
    mid = mido.MidiFile(path)
    assert mid.type == 0 and len(mid.tracks) == 1, (mid.type, len(mid.tracks))
    events = _channel_events(mid)
    total_ticks = max(t for (t, _, _, _) in events)

    chan11 = _segments_for_channel(events, 11)
    chan0_top = _segments_for_channel(events, 0, top_note_only=True)
    chan1 = _segments_for_channel(events, 1)
    melody_seg = _merge_parts([
        (chan11, 0, total_ticks),
        (chan0_top, 0, total_ticks),
        (chan1, 0, total_ticks),
    ])

    # chan12(Fretless Bass、2.4-20.27秒に疎らな8note、前半の低音パッド)と
    # chan9(Piano、12.61-26.09秒に連続的に動く後半の主ベースライン)は、
    # 単純に全区間(0,total_ticks)ずつで重ねると和音の音価が実際には
    # chan9開始後も鳴り続けている箇所でtick単位の重複を起こす
    # (実測で確認済み)。chan9の最初の発音開始tickを境界にして前後で
    # 明確に分担させる(chan12は境界より前だけ、chan9は境界以降だけ)。
    chan12 = _segments_for_channel(events, 12)
    chan9 = _segments_for_channel(events, 9)
    chan9_first_start = min(s for (s, e, n) in chan9)
    bass_seg = _merge_parts([
        (chan12, 0, chan9_first_start),
        (chan9, chan9_first_start, total_ticks),
    ])

    chan6 = _segments_for_channel(events, 6)
    harmony_seg = _merge_parts([
        (chan6, 0, total_ticks),
    ])

    melody_rows = _rows_from_segments(melody_seg, total_ticks)
    bass_rows = _rows_from_segments(bass_seg, total_ticks)
    harmony_rows = _rows_from_segments(harmony_seg, total_ticks)
    return melody_rows, bass_rows, harmony_rows


# ===== StageClear(ステージクリアジングル) - Round(2026-09-06)追加 =====
STAGE_CLEAR_FILE = "StageClear.mid"


def _track_segments_top_note(track, octave_shift=0):
    """1トラック内で複数ノートが重なる(和音)場合、重なっている区間は
    常に「その瞬間の最高音」だけを採用してモノフォニック化する
    (GFEnding抽出時の_segments_for_channel(top_note_only=True)と同じ
    考え方をトラック単位に適用したもの)。StageClear.midのtrack1
    ("Galaxy Force"、ベースパート)・track4("Stage Clear"、メロディ
    パート)はいずれも元データの装飾的な短い重複ノート(グレースノート・
    アルペジオ的な三和音断片、GYM2MID書き出し由来の冗長なnote_on
    重複を含む)を持つため、真のモノフォニック仮定の_track_segments
    ではなくこちらを使う。"""
    active = set()
    cur_note = None
    cur_start = None
    segments = []
    abs_time = 0
    for msg in track:
        abs_time += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            prev_top = max(active) if active else None
            active.add(msg.note + octave_shift)
            new_top = max(active)
        elif msg.type == "note_off" or (msg.type == "note_on" and msg.velocity == 0):
            prev_top = max(active) if active else None
            active.discard(msg.note + octave_shift)
            new_top = max(active) if active else None
        else:
            continue
        if new_top != prev_top:
            if cur_note is not None:
                segments.append((cur_start, abs_time, cur_note))
            cur_note = new_top
            cur_start = abs_time
    if cur_note is not None:
        segments.append((cur_start, abs_time, cur_note))
    return segments, abs_time


def load_stage_clear_parts():
    """StageClear.mid(type1、12トラック、8.56秒の短いワンショット
    ジングル)から3パート抽出(ユーザー:「3音使って良いんで」-
    GFEndingと同じくゲーム中chAもSE用途と競合しないため3ch使用可):

    - MELODY: track4("\" Stage Clear \""、channel3、MIDI57-69、曲を
      通して最も活発に動く声部で空白区間が無い、装飾的な短い重複
      ノートを含むためtop-note化)を採用。
    - HARMONY: track2("by Sega 1988"、channel1、MIDI57-76、真に
      モノフォニック)を採用。track3("CPU: Arcade..."、channel2、
      MIDI47-64)はtrack2とほぼ同一リズムで3度/6度並行移動する
      対の声部だが、3音の予算内(メロディ+ベース+ハーモニー)に
      収まらないため不採用(GFEnding抽出時の重複声部間引きと
      同じ判断)。
    - BASS: track1("Galaxy Force"、channel0、MIDI26-52)を採用。
      三和音の短いアルペジオ的断片・装飾的な短い重複ノートを含む
      ためtop-note化。最低音26が既存の周期テーブル範囲[32,91]の
      下限を割り込むため、この曲専用に+12(1オクターブ)シフトを
      掛けて38-64にする(オクターブ単位のシフトなので他パートとの
      調和関係[コード構成音の相対関係]自体は保たれる - 既存の
      ALONE_FIGHTER/DEFEAT全体への一律OCTAVE_SHIFT適用と同じ考え方を
      1パートだけに限定適用したもの。テーブル自体[MIDI_MIN/MAX]を
      拡張しない判断のため、既存3曲[ALONE_FIGHTER/DEFEAT/TryZ]・
      GFEndingが使う全RAM/ROMアドレスへの波及を避けられる)。

    track5("Originally composed by"、channel9)はGM標準のドラム
    チャンネル(観測ノート38-48はスネア/ハイハット/タムに典型的な
    ノート番号)のため不採用(TryZ抽出時のGM打楽器チャンネル除外と
    同じ判断)。メロディ・ハーモニーはオクターブシフト無し(生MIDI
    ノート57-76は周期テーブル範囲[32,91]にそのまま収まる)。"""
    path = os.path.join(MIDI_DIR, STAGE_CLEAR_FILE)
    mid = mido.MidiFile(path)
    assert mid.type == 1 and len(mid.tracks) == 12, (mid.type, len(mid.tracks))
    # ALONE_FIGHTER/DEFEATと違い、このファイルはticks_per_beat=480・
    # テンポ500000us/beat(120BPM)固定 - グローバルなMIDI_TICKS_PER_VBLANK
    # (=4)は「120 ticks/beat」の2曲専用に検証済みの値であり、この
    # ファイル(480 ticks/beat、4倍細かい)にそのまま使うと生成される
    # durationが4倍長く(=曲が4倍遅く)なってしまう。1 vblank tick=1/60秒・
    # 1 MIDI tick=tempo[us]/1e6/ticks_per_beat秒という定義から毎回
    # 汎用的に算出する: 480/(500000/1e6*60)=16。mid.length(8.5583秒)と
    # 実測ノート総和が一致することをコード側アサートで検証。
    assert mid.ticks_per_beat == 480
    tempo = 500000
    for track in mid.tracks:
        for msg in track:
            if msg.type == "set_tempo":
                tempo = msg.tempo
    ticks_per_vblank = mid.ticks_per_beat / (tempo / 1e6 * 60)
    melody_seg, melody_total = _track_segments_top_note(mid.tracks[4])
    harmony_seg, harmony_total = _track_segments(mid.tracks[2], octave_shift=0)
    bass_seg, bass_total = _track_segments_top_note(mid.tracks[1], octave_shift=12)
    melody_rows = _rows_from_segments(melody_seg, melody_total, ticks_per_vblank)
    harmony_rows = _rows_from_segments(harmony_seg, harmony_total, ticks_per_vblank)
    bass_rows = _rows_from_segments(bass_seg, bass_total, ticks_per_vblank)

    # (2026-09-06、実機フィードバック"クリアBGMの最初の方って多分無音に
    # なってると思うんで発音までの無音部分をカットして"): 全パートとも
    # 先頭行は実際にREST(元のMIDIで頭出し前の無音区間)で、しかも
    # メロディ(193tick)だけbass/harmony(180tick)よりわずかに遅れて
    # 入る - 3パート間の相対タイミング(メロディがbass/harmonyの13tick
    # 後に入る、という編曲上の関係)は保ったまま、3パート共通の
    # 「頭から必ず鳴っていない」無音長(=3パートの先頭REST長の最小値)
    # だけを全パートから一律に削る。0tickになったパートは先頭行自体を
    # 削除(durationが0の行はBGM_x_TIMERへ書く際にDEC Aで0xFFへ
    # アンダーフローし約256tickの誤ったREST行として再生されてしまう
    # ため、0まで削ったら行ごと除去する必要がある)。
    all_rows = [melody_rows, harmony_rows, bass_rows]
    common_lead_rest = min(rows[0][1] for rows in all_rows if rows and rows[0][0] == NOTE_REST)
    trimmed = []
    for rows in all_rows:
        rows = list(rows)
        if rows and rows[0][0] == NOTE_REST:
            new_dur = rows[0][1] - common_lead_rest
            if new_dur > 0:
                rows[0] = (NOTE_REST, new_dur)
            else:
                rows = rows[1:]
        trimmed.append(rows)
    melody_rows, harmony_rows, bass_rows = trimmed
    return melody_rows, bass_rows, harmony_rows


if __name__ == "__main__":
    lo, hi = build_period_table()
    print(f"period table: {len(lo)} notes (MIDI {MIDI_MIN}-{MIDI_MAX})")
    for key in SONGS:
        t0, t1 = load_song_tracks(key)
        b0, b1 = rows_to_bytes(t0), rows_to_bytes(t1)
        print(f"{key}: track0 {len(t0)} rows / {len(b0)} bytes, "
              f"track1 {len(t1)} rows / {len(b1)} bytes, total {len(b0)+len(b1)} bytes")
