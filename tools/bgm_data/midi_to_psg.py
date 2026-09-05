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
"""
import os
import mido

HERE = os.path.dirname(os.path.abspath(__file__))
MIDI_DIR = os.path.join(HERE, "midi")

PSG_CLOCK = 3579545 / 2  # 1789772.5Hz - MSX AY-3-8910互換PSGの入力クロック

MIDI_MIN = 50
MIDI_MAX = 84
NUM_NOTES = MIDI_MAX - MIDI_MIN + 1  # 35

NOTE_REST = 0xFF
LOOP_MARK = 0xFE

MIDI_TICKS_PER_VBLANK = 4

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


def _track_segments(track):
    """1トラック分のnote_on/offを歩いて(start_tick, end_tick, note)の
    列を作る。真にモノフォニックであることは事前確認済みなので、常に
    「前のノートを閉じてから次を開く」の単純な状態機械で足りる。"""
    segments = []
    abs_time = 0
    cur_note = None
    cur_start = 0
    for msg in track:
        abs_time += msg.time
        if msg.type == "note_on" and msg.velocity > 0:
            if cur_note is not None:
                segments.append((cur_start, abs_time, cur_note))
            cur_note = msg.note
            cur_start = abs_time
        elif (msg.type == "note_off") or (msg.type == "note_on" and msg.velocity == 0):
            if cur_note is not None and msg.note == cur_note:
                segments.append((cur_start, abs_time, cur_note))
                cur_note = None
    if cur_note is not None:
        segments.append((cur_start, abs_time, cur_note))
    total_ticks = abs_time
    return segments, total_ticks


def _rows_from_segments(segments, total_ticks):
    """segments(重複無し、モノフォニック前提)+トラック全長から、
    無音区間も含めた完全な(note_or_rest, start_tick, end_tick)区間列を
    作り、MIDI tick境界をvblank tick境界へfloor変換した上で
    (note_index_or_REST, duration_vblank_ticks)行へ変換する。"""
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
        vb_s = s // MIDI_TICKS_PER_VBLANK
        vb_e = e // MIDI_TICKS_PER_VBLANK
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
    result = []
    for track in mid.tracks:
        segments, total_ticks = _track_segments(track)
        rows = _rows_from_segments(segments, total_ticks)
        result.append(rows)
    return result[0], result[1]


def rows_to_bytes(rows):
    """(note,duration)行の列 -> 2byte/行のバイト列 + 末尾LOOP_MARK(1byte)。"""
    out = bytearray()
    for note, dur in rows:
        assert 0 <= dur <= 255
        out.append(note & 0xFF)
        out.append(dur & 0xFF)
    out.append(LOOP_MARK)
    return bytes(out)


if __name__ == "__main__":
    lo, hi = build_period_table()
    print(f"period table: {len(lo)} notes (MIDI {MIDI_MIN}-{MIDI_MAX})")
    for key in SONGS:
        t0, t1 = load_song_tracks(key)
        b0, b1 = rows_to_bytes(t0), rows_to_bytes(t1)
        print(f"{key}: track0 {len(t0)} rows / {len(b0)} bytes, "
              f"track1 {len(t1)} rows / {len(b1)} bytes, total {len(b0)+len(b1)} bytes")
