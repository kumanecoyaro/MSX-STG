"""Stage1(src/CYBER SHMUP.asm): round40 BGM driver検証("タイトル含めて
各ステージにドライバを配置しRAMにコピーしてステージスタート")。

tools/verify_enemy_pool_scan.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine(センチネル0x0000方式)」の一回性検証スクリプト
の作法に倣う。

実機フィードバック対応("ステージ1の自機ショット音とBGMが被ってる 弾
うつとベースのほうが聞こえてない 被らないはずだぞ"→"そもそもchB、Cは
空けてあってSE類はchAのみで鳴らすはず"、確認: "SEの被りで上書きされる
のは問題ない BCはBGM専用 で、ノイズは別ch PSGは4音同時に鳴らせる
トーンでノイズは消えない"): 全SE(SOUND_SHOT/POD_HIT/POD_FIRE/
BARRIER_HIT/DESTROY/エンジン音)をチャンネルAへ統合し、チャンネルB/Cを
BGM専用にした。これにより従来Stage1だけが持っていた「SFXタイマーが
非0の間はBGM側が書き込みを完全に譲る」という優先ロジック(SND_TIMER_B/
SND_TIMER_C/SND_C_DUTY_TIMER)は完全に撤去され、BGMT_UPDATE_B/Cは
Stage2/Titleと同じ無条件版になった - このスクリプトはその撤去(SE専用
タイマーが何であってもBGMの書き込みに一切影響しない)を直接検証する。
チャンネルA側のSE統合自体(R7=0B0h・3段優先度SOUND_UPDATE)の詳細検証は
tools/verify_sound_duty_cycle.py/tools/verify_player_damage.pyが担当。
Stage1自身はRAMコピーもバンク切替も行わない(Titleが起動時に一度だけ
コピーしたRAMをそのまま読むだけ)ため、その部分の検証はtools/
title_screen/title_test.pyの側で行う。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    for _ in range(max_instr):
        if z.pc == 0x0000:
            return
        z.step()
    raise RuntimeError(f"call_routine(0x{entry_addr:04X}) never returned")


def boot(z):
    z.pc = sym["INIT"]
    for _ in range(500000):
        if z.pc == sym["MAINLOOP"]:
            return
        z.step()
    raise RuntimeError("never reached MAINLOOP")


HTIMI_HOOK = sym["HTIMI_HOOK"]
BGM_TICK = sym["BGM_TICK"]
BGM_B_PTR = sym["BGM_B_PTR"]
BGM_C_PTR = sym["BGM_C_PTR"]
BGM_B_TIMER = sym["BGM_B_TIMER"]
BGM_C_TIMER = sym["BGM_C_TIMER"]
BGM_B_BASE = sym["BGM_B_BASE"]
BGM_C_BASE = sym["BGM_C_BASE"]
BGM_B_LOOP_BASE = sym["BGM_B_LOOP_BASE"]
BGM_C_LOOP_BASE = sym["BGM_C_LOOP_BASE"]
BGM_NOTE_REST = sym["BGM_NOTE_REST"]
BGM_LOOP_MARK = sym["BGM_LOOP_MARK"]
BGM_PERIOD_LO_RAM = sym["BGM_PERIOD_LO_RAM"]
BGM_PERIOD_HI_RAM = sym["BGM_PERIOD_HI_RAM"]
SND_TIMER = sym["SND_TIMER"]
SND_TONE_TIMER = sym["SND_TONE_TIMER"]
SND_BARRIER_DUTY_TIMER = sym["SND_BARRIER_DUTY_TIMER"]
PSG_ADDR = sym["PSG_ADDR"]
PSG_DATA = sym["PSG_DATA"]
BGM_B_REST = sym["BGM_B_REST"]
BGM_C_REST = sym["BGM_C_REST"]
BGM_ENV_LAST_INDEX = sym["BGM_ENV_LAST_INDEX"]
BGM_B_DUTY_MASK = sym["BGM_B_DUTY_MASK"]
BGM_B_ENV_LEVEL = sym["BGM_B_ENV_LEVEL"]
BGM_B_ENV_IDX = sym["BGM_B_ENV_IDX"]
BGM_B_ENV_CD = sym["BGM_B_ENV_CD"]
BGM_B_DUTY_PHASE = sym["BGM_B_DUTY_PHASE"]
BGM_C_ENV_LEVEL = sym["BGM_C_ENV_LEVEL"]
BGM_C_ENV_IDX = sym["BGM_C_ENV_IDX"]
BGM_C_ENV_CD = sym["BGM_C_ENV_CD"]
BGM_ENV_BELL_TABLE = sym["BGM_ENV_BELL_TABLE"]
BGM_ENV_LINEAR_TABLE = sym["BGM_ENV_LINEAR_TABLE"]
BGM_VOL_ATTEN = sym["BGM_VOL_ATTEN"]


def read_env_table(z, addr, n_entries=BGM_ENV_LAST_INDEX + 1):
    return [(z.rd(addr + i * 2), z.rd(addr + i * 2 + 1)) for i in range(n_entries)]


def sim_envelope_sequence(table, duty_mask, n_ticks, atten=BGM_VOL_ATTEN):
    """tools/stage2_combined/tests/bgm_test.pyの同名関数と同一ロジック
    (ASM側BGMT_U[BC]_ENV_STEP/ADVANCE/WRITEの独立Pythonリファレンス)。
    実機フィードバック"BGM音量を下げたいが現在は最大か?"対応: 可聴
    tickのみR9/R10へ書く直前にatten(BGM_VOL_ATTEN)だけ減算(0未満は
    クランプ)。"""
    idx = 0
    level, dur0 = table[0]
    cd = dur0 - 1
    phase = duty_mask
    out = []
    for tick in range(n_ticks):
        if tick > 0:
            if cd > 0:
                cd -= 1
            elif idx < len(table) - 1:
                idx += 1
                level, dur = table[idx]
                if dur != 0:
                    cd = dur - 1
        if duty_mask:
            phase = (phase + 1) & 0xFF
            audible = (phase & duty_mask) == 0
        else:
            audible = True
        out.append(max(0, level - atten) if audible else 0)
    return out


def observed_channel_sequence(z, vol_reg, n_ticks):
    seq = []
    for _ in range(n_ticks):
        call_routine(z, BGM_TICK)
        seq.append(z.psg_regs.get(vol_reg))
    return seq

REPO = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
import bgm_bank_gen as bg  # noqa: E402

ALONE_FIGHTER = bg.song_constants("ALONE_FIGHTER")
bank_image, layout = bg.build_bank()
_af = layout["ALONE_FIGHTER"]
period_lo = list(bank_image[0:bg.NUM_NOTES])
period_hi = list(bank_image[bg.NUM_NOTES:2 * bg.NUM_NOTES])
periods = list(zip(period_lo, period_hi))
chB_bytes = bank_image[_af["bank_offset"]:_af["bank_offset"] + _af["chB_len"]]


# ---- constants agree with tools/bgm_data/bgm_bank_gen.py's ALONE_FIGHTER
# layout (default BGM_DATA_BASE=0xC000 - this file has zero RAM usage in
# C000h-DFFFh of its own, confirmed by EQU address survey, so no
# STAGE2_DATA_BASE-style override is needed the way combined_test.asm's
# own EQU comment explains it needed) ----
check("BGM_PERIOD_LO_RAM/BGM_PERIOD_HI_RAM match bgm_bank_gen's ALONE_FIGHTER layout",
      (BGM_PERIOD_LO_RAM, BGM_PERIOD_HI_RAM) == (ALONE_FIGHTER["PERIOD_LO_RAM"], ALONE_FIGHTER["PERIOD_HI_RAM"]))
check("BGM_B_BASE/BGM_C_BASE match bgm_bank_gen's ALONE_FIGHTER layout (same as title_test.asm's own)",
      (BGM_B_BASE, BGM_C_BASE) == (ALONE_FIGHTER["CHB_RAM_BASE"], ALONE_FIGHTER["CHC_RAM_BASE"]))
check("BGM_B_PTR/BGM_C_PTR/BGM_B_TIMER/BGM_C_TIMER match bgm_bank_gen's layout",
      (BGM_B_PTR, BGM_C_PTR, BGM_B_TIMER, BGM_C_TIMER) ==
      (ALONE_FIGHTER["BGM_B_PTR"], ALONE_FIGHTER["BGM_C_PTR"], ALONE_FIGHTER["BGM_B_TIMER"], ALONE_FIGHTER["BGM_C_TIMER"]))


# ---- real boot trace: INIT_BGM's own hook install + pointer init (no
# RAM copy of its own - see this file's own comment) ----
z = fresh()
boot(z)
check("INIT_BGM wrote a JP opcode (0C3h) into HTIMI_HOOK", z.rd(HTIMI_HOOK) == 0xC3)
hook_target = z.rd(HTIMI_HOOK + 1) | (z.rd(HTIMI_HOOK + 2) << 8)
check(f"INIT_BGM's JP target ({hex(hook_target)}) is BGM_TICK ({hex(BGM_TICK)})", hook_target == BGM_TICK)
check("INIT_BGM left BGM_B_PTR/BGM_C_PTR pointing at BGM_B_BASE/BGM_C_BASE",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8), z.rd(BGM_C_PTR) | (z.rd(BGM_C_PTR + 1) << 8)) ==
      (BGM_B_BASE, BGM_C_BASE))
check("INIT_BGM left BGM_B_TIMER/BGM_C_TIMER at 0", z.rd(BGM_B_TIMER) == 0 and z.rd(BGM_C_TIMER) == 0)


def poke_channel(z, ptr_addr, timer_addr, base_addr, note, duration, timer=0):
    z.wr(timer_addr, timer)
    z.wr(ptr_addr, base_addr & 0xFF)
    z.wr(ptr_addr + 1, (base_addr >> 8) & 0xFF)
    z.wr(base_addr, note & 0xFF)
    z.wr(base_addr + 1, duration & 0xFF)


ROW_B = 0xD000
ROW_C = 0xD100
TEST_NOTE_B, TEST_DUR_B = 5, 23
TEST_NOTE_C, TEST_DUR_C = 17, 31

def poke_period_table(z):
    # Stage1 itself never populates BGM_PERIOD_LO/HI_RAM - that's Title's
    # own one-time job (see INIT_BGM's own comment: this file only ever
    # READS the RAM Title already filled). Any test exercising a real
    # note lookup has to poke it in manually first, standing in for that
    # earlier Title step.
    for i, (lo, hi) in enumerate(zip(period_lo, period_hi)):
        z.wr(BGM_PERIOD_LO_RAM + i, lo)
        z.wr(BGM_PERIOD_HI_RAM + i, hi)


# ---- normal playback: new-row load on each channel ----
z = fresh()
poke_period_table(z)
bell_table = read_env_table(z, BGM_ENV_BELL_TABLE)
linear_table = read_env_table(z, BGM_ENV_LINEAR_TABLE)
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, TEST_NOTE_B, TEST_DUR_B, timer=0)
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
call_routine(z, BGM_TICK)
check("chB loads a fresh row (BGM_B_TIMER reloaded to duration-1, round40 "
      "off-by-one fix - the load tick itself already plays the note once)",
      z.rd(BGM_B_TIMER) == TEST_DUR_B - 1)
exp_lo, exp_hi = periods[TEST_NOTE_B]
check("chB tone period (R2/R3) matches the period table",
      (z.psg_regs.get(2), z.psg_regs.get(3)) == (exp_lo, exp_hi))
check("chB envelope retriggered to BELL table index0 (level/countdown/index)",
      (z.rd(BGM_B_ENV_LEVEL), z.rd(BGM_B_ENV_IDX), z.rd(BGM_B_ENV_CD)) ==
      (bell_table[0][0], 0, bell_table[0][1] - 1))
exp_write_b = sim_envelope_sequence(bell_table, BGM_B_DUTY_MASK, 1)[0]
check(f"chB: R9 written this very tick already reflects the duty-gated envelope level (expected {exp_write_b})",
      z.psg_regs.get(9) == exp_write_b)
exp_lo_c, exp_hi_c = periods[TEST_NOTE_C]
check("chC loads a fresh row (BGM_C_TIMER reloaded to duration-1, round40 off-by-one fix)",
      z.rd(BGM_C_TIMER) == TEST_DUR_C - 1)
check("chC tone period (R4/R5) matches the period table",
      (z.psg_regs.get(4), z.psg_regs.get(5)) == (exp_lo_c, exp_hi_c))
check("chC envelope retriggered to LINEAR table index0 (level/countdown/index)",
      (z.rd(BGM_C_ENV_LEVEL), z.rd(BGM_C_ENV_IDX), z.rd(BGM_C_ENV_CD)) ==
      (linear_table[0][0], 0, linear_table[0][1] - 1))
check("chC: R10 is written unconditionally with the attenuated envelope level "
      "(no duty overlay, but BGM_VOL_ATTEN still applies)",
      z.psg_regs.get(10) == max(0, linear_table[0][0] - BGM_VOL_ATTEN))

# ---- 実機フィードバック対応("そもそもchB、Cは空けてあってSE類は
# chAのみで鳴らすはず"): 全SEがチャンネルAへ統合され、チャンネルB/Cは
# BGM専用になったため、旧来存在した「SFXのタイマーが非0の間BGM側は
# 該当チャンネルへの書き込みを完全に譲る」という優先ロジック自体が
# 撤去された(SND_TIMER_B/SND_TIMER_C/SND_C_DUTY_TIMERはもう存在しない
# - src/CYBER SHMUP.asm自身のBGMT_UPDATE_B/Cの新しいコメント参照)。
# 以下はその撤去を直接検証する回帰ガード: チャンネルAのSE専用タイマー
# (SND_TIMER/SND_TONE_TIMER/SND_BARRIER_DUTY_TIMER)をどう設定しても、
# BGM_TICKの書き込み内容(BGM_B_PTR/BGM_B_TIMER/R2/R3/R9)は一切影響
# されない。
z = fresh()
poke_period_table(z)
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, TEST_NOTE_B, TEST_DUR_B, timer=0)
z.wr(SND_TIMER, 15)
z.wr(SND_TONE_TIMER, 15)
z.wr(SND_BARRIER_DUTY_TIMER, 8)
call_routine(z, BGM_TICK)
exp_lo_b, exp_hi_b = periods[TEST_NOTE_B]
exp_write_b2 = sim_envelope_sequence(bell_table, BGM_B_DUTY_MASK, 1)[0]
check("SE専用タイマー(SND_TIMER/SND_TONE_TIMER/SND_BARRIER_DUTY_TIMER)が全て非0でも "
      "BGM chBは無条件でR2/R3/R9へ書く(もう譲らない)",
      (z.psg_regs.get(2), z.psg_regs.get(3), z.psg_regs.get(9)) ==
      (exp_lo_b, exp_hi_b, exp_write_b2))
check("...BGM_B_TIMERも通常通り進む(SFXに凍結されない)", z.rd(BGM_B_TIMER) == TEST_DUR_B - 1)

z = fresh()
poke_period_table(z)
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
z.wr(SND_TIMER, 15)
z.wr(SND_TONE_TIMER, 15)
z.wr(SND_BARRIER_DUTY_TIMER, 8)
call_routine(z, BGM_TICK)
exp_lo_c2, exp_hi_c2 = periods[TEST_NOTE_C]
check("SE専用タイマーが全て非0でもBGM chCは無条件でR4/R5/R10へ書く(もう譲らない)",
      (z.psg_regs.get(4), z.psg_regs.get(5), z.psg_regs.get(10)) ==
      (exp_lo_c2, exp_hi_c2, max(0, linear_table[0][0] - BGM_VOL_ATTEN)))

# ---- rest notes / loop marker (same shape as Stage2/Title's own driver) ----
z = fresh()
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, BGM_NOTE_REST, 9, timer=0)
for reg in (2, 3):
    z.psg_regs.pop(reg, None)
call_routine(z, BGM_TICK)
check("rest note (chB): period registers (R2/R3) are NOT written", 2 not in z.psg_regs and 3 not in z.psg_regs)
check("rest note (chB): volume (R9) is silenced to 0", z.psg_regs.get(9) == 0)

z = fresh()
# BGM_B_BASE自体にも本物のALONE_FIGHTER chBデータをpoke(Stage1自身は
# 決してここへ書き込まない - Titleが起動時に一度だけコピーする前提。
# これを省くと"first_dur"は常に未初期化RAMの0を読むだけになり、
# このテスト自体が実質何も検証していないことになる - 実際today's fix
# 前はそれで気づかれずに"通っていた"だけだった)。
for i, b in enumerate(chB_bytes):
    z.wr(BGM_B_BASE + i, b)
loop_addr = 0xD200
z.wr(loop_addr, BGM_LOOP_MARK)
z.wr(BGM_B_PTR, loop_addr & 0xFF)
z.wr(BGM_B_PTR + 1, (loop_addr >> 8) & 0xFF)
z.wr(BGM_B_TIMER, 0)
# 実機フィードバック対応("ステージ1ボスもBGMをTryZに"): BGMT_UB_NEWROWの
# LOOP_MARK復帰先はもう固定EQU(BGM_B_BASE)の即値ロードではなく、RAM変数
# BGM_B_LOOP_BASEからの間接読み込みになった(TryZ切替時に曲ごとの実際の
# 復帰先へ差し替えるため)。このテストはINIT_BGMを経由しない生メモリの
# ためBGM_B_LOOP_BASEは自分でALONE_FIGHTER基準にpokeしておく必要がある。
z.wr(BGM_B_LOOP_BASE, BGM_B_BASE & 0xFF)
z.wr(BGM_B_LOOP_BASE + 1, (BGM_B_BASE >> 8) & 0xFF)
first_note = z.rd(BGM_B_BASE)
first_dur = z.rd(BGM_B_BASE + 1)
call_routine(z, BGM_TICK)
check("loop mark (chB): BGM_B_PTR resets to BGM_B_BASE+2 (ALONE_FIGHTER's own first row, now consumed)",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)) == BGM_B_BASE + 2)
check("loop mark (chB): reloaded BGM_B_TIMER matches ALONE_FIGHTER chB's own real first-row "
      "duration minus 1 (round40 off-by-one fix)",
      z.rd(BGM_B_TIMER) == first_dur - 1)


# ---- round40 実機フィードバック対応 ("こりゃ酷い ピーピー不協和音
# 休符も無視してるな テンポも無茶苦茶だ"): off-by-oneの直接回帰ガード。
# 多tick連続シミュレートし、観測された音切り替わりtickの列が本物の
# ALONE_FIGHTER行データと完全一致するかを検証する(1行だけの検証では
# 検出できない、行数の多いチャンネルほど大きくなる累積ズレを狙い撃つ)。
def decode_rows(row_bytes):
    rows = []
    i = 0
    while i + 1 < len(row_bytes):
        rows.append((row_bytes[i], row_bytes[i + 1]))
        i += 2
    return rows


def observed_note_change_ticks(z, rest_addr, tone_lo_reg, tone_hi_reg, n_ticks):
    # 実機フィードバック"ドライバにデューティ比実装"対応: 音量レジスタは
    # デューティゲートにより同一行の中でも周期的に0へ落ちるため、もう
    # 「行が変わった」判定材料に使えない。トーン周期+BGM_B/C_REST RAM
    # フラグ(行の頭でのみ更新される)を組み合わせたキーに変更。
    events = []
    last = None
    for tick in range(n_ticks):
        call_routine(z, BGM_TICK)
        resting = z.rd(rest_addr) != 0
        tone = (z.psg_regs.get(tone_lo_reg), z.psg_regs.get(tone_hi_reg))
        key = (tone, resting)
        if key != last:
            note = None if resting else next(
                (i for i, (lo_v, hi_v) in enumerate(periods) if (lo_v, hi_v) == tone), None)
            events.append((tick, note))
            last = key
    return events


N_TICKS = 2000
z = fresh()
boot(z)
# Stage1自身はRAMコピーを行わない(Titleが起動時に一度だけコピーする
# 前提 - このファイル自身のINIT_BGMコメント参照)ため、この検証でも
# 同じ前提を再現してTitleの代わりに本物のデータを直接RAMへ書く。
poke_period_table(z)
for i, b in enumerate(chB_bytes):
    z.wr(BGM_B_BASE + i, b)
z.wr(BGM_B_PTR, BGM_B_BASE & 0xFF)
z.wr(BGM_B_PTR + 1, (BGM_B_BASE >> 8) & 0xFF)
z.wr(BGM_B_TIMER, 0)
observed_b = observed_note_change_ticks(z, BGM_B_REST, 2, 3, N_TICKS)
expected_b = []
cum = 0
for note, dur in decode_rows(chB_bytes):
    if cum >= N_TICKS:
        break
    expected_b.append((cum, None if note == BGM_NOTE_REST else note))
    cum += dur
check(f"round40 off-by-one regression: {len(expected_b)} real ALONE_FIGHTER chB note-change ticks "
      f"(over {N_TICKS} real BGM_TICK calls from a real boot) match the "
      "real bgm_bank.bin row data EXACTLY",
      observed_b == expected_b)


# ---- 実機フィードバック対応その3("BGMが1chしかなってない...HWエンベ
# ロープはコントロール不能と判断 ソフトに切り替える")----
# Stage1もStage2/Titleと全く同じ設計: 休符でない限り毎tick必ずR9/R10へ
# ソフトウェア計算済みの音量を書く(HWエンベロープ特有の「毎フレーム
# 書くとアタックが繰り返される」罠が存在しないため、リトリガー回避の
# ための「行の頭以外は書かない」制約自体がもう無い)。チャンネルB/Cは
# もうSEと無関係(SEは全てチャンネルAへ移設済み)なので、単純にBGM単独で
# 多tick分の実出力列をPythonリファレンスと突き合わせるだけでよい。
z = fresh()
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, 0xD400, TEST_NOTE_B, 200, timer=0)
z.wr(BGM_C_TIMER, 250)  # hold chC out of the way while probing chB in isolation
N_ENV_TICKS = 120
observed_b_env = observed_channel_sequence(z, 9, N_ENV_TICKS)
expected_b_env = sim_envelope_sequence(bell_table, BGM_B_DUTY_MASK, N_ENV_TICKS)
check(f"chB over {N_ENV_TICKS} ticks: R9 sequence (BELL + 50% duty) matches the independent "
      "Python reference exactly, including reaching the terminal (silent) entry",
      observed_b_env == expected_b_env)

z = fresh()
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, 0xD400, TEST_NOTE_C, 200, timer=0)
z.wr(BGM_B_TIMER, 250)  # hold chB out of the way while probing chC in isolation
observed_c_env = observed_channel_sequence(z, 10, N_ENV_TICKS)
expected_c_env = sim_envelope_sequence(linear_table, 0, N_ENV_TICKS)
check(f"chC over {N_ENV_TICKS} ticks: R10 sequence (LINEAR, no duty) matches the independent "
      "Python reference exactly, including reaching the terminal (silent) entry",
      observed_c_env == expected_c_env)


# ---- DI/EI protection: every PSG_ADDR/PSG_DATA OUT pair this round
# wrapped must genuinely execute with IFF1 already False ----
def scan_psg_out_iff1(entry_addr, presets):
    z = fresh()
    for addr, val in presets.items():
        z.wr(addr, val)
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    saw = False
    all_masked = True
    for _ in range(5000):
        if z.pc == 0x0000:
            break
        opcode = z.rd(z.pc)
        if opcode == 0xD3:
            port = z.rd((z.pc + 1) & 0xFFFF)
            if port in (PSG_ADDR, PSG_DATA):
                saw = True
                if z.iff1:
                    all_masked = False
        z.step()
    return saw, all_masked


PROTECTED = [
    ("SOUND_SHOT", {}),
    ("SOUND_DESTROY", {}),
    ("SOUND_POD_HIT", {}),
    ("SOUND_BARRIER_HIT", {}),
    ("SOUND_POD_FIRE", {}),
]
for name, presets in PROTECTED:
    saw, masked = scan_psg_out_iff1(sym[name], presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)", masked)

for name, presets in [
    ("SOUND_UPDATE", {SND_TIMER: 5, SND_TONE_TIMER: 5, SND_BARRIER_DUTY_TIMER: 0}),
    ("SOUND_UPDATE", {SND_TIMER: 5, SND_TONE_TIMER: 0, SND_BARRIER_DUTY_TIMER: 8}),
]:
    saw, masked = scan_psg_out_iff1(sym[name], presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)", masked)

# BGM_TICK itself needs no DI/EI wrapping (runs entirely inside one
# interrupt, same reasoning as Stage2/Title's own driver).
saw, masked = scan_psg_out_iff1(BGM_TICK, {BGM_B_TIMER: 0, BGM_C_TIMER: 0})
check("BGM_TICK: real PSG_ADDR/PSG_DATA OUTs found", saw)


# ---- 実機フィードバック対応("ステージ1ボスもBGMをTryZに マテリアライズ
# 終了後に再生...どちらもマテリアライズ中は自機ショット音は停止 同様に
# マテリアライズに入る前にそれまでのBGMは停止"): BOSS_SPAWN now calls
# MUTE_BGM (silences ALONE_FIGHTER immediately, leaves its RAM state
# untouched), and BOSS_UPDATE_BODY's own BOSS_STATE 1->2 transition (the
# entrance tile-reveal finishing) calls SWITCH_BGM_TO_TRYZ, which repoints
# BGM_B/C_PTR at TryZ's own RAM copy (Title pre-loads it - see
# BGM_TRYZ_CHB/CHC_BASE's own comment, no bank-switch of Stage1's own) and
# clears BGM_MUTED again. ----
BGM_MUTED = sym["BGM_MUTED"]
BGM_TRYZ_CHB_BASE = sym["BGM_TRYZ_CHB_BASE"]
BGM_TRYZ_CHC_BASE = sym["BGM_TRYZ_CHC_BASE"]
BOSS_STATE = sym["BOSS_STATE"]

_tryz_layout = layout["BOSS_TRYZ"]
_tryz_start = _tryz_layout["bank_offset"]
tryz_chB_bytes = bank_image[_tryz_start:_tryz_start + _tryz_layout["chB_len"]]
tryz_chC_bytes = bank_image[_tryz_start + _tryz_layout["chB_len"]:
                             _tryz_start + _tryz_layout["chB_len"] + _tryz_layout["chC_len"]]

check("BGM_TRYZ_CHC_BASE = BGM_TRYZ_CHB_BASE + TryZ's own real chB length "
      "(this file's own manual layout must still match the real data)",
      BGM_TRYZ_CHC_BASE == BGM_TRYZ_CHB_BASE + _tryz_layout["chB_len"])

z = fresh()
call_routine(z, sym["BOSS_SPAWN"])
check("BOSS_SPAWN mutes BGM immediately (BGM_MUTED=1)", z.rd(BGM_MUTED) == 1)
check("BOSS_SPAWN's own MUTE_BGM silenced R9/R10 immediately",
      z.psg_regs.get(9) == 0 and z.psg_regs.get(10) == 0)
check("BOSS_SPAWN enters BOSS_STATE=1 (materializing)", z.rd(BOSS_STATE) == 1)

z = fresh()
# poke TryZ's own real chB/chC bytes at the fixed addresses Title pre-loads
# them into (this standalone test has no Title of its own - same
# established convention as the ALONE_FIGHTER poke above)
for i, b in enumerate(tryz_chB_bytes):
    z.wr(BGM_TRYZ_CHB_BASE + i, b)
for i, b in enumerate(tryz_chC_bytes):
    z.wr(BGM_TRYZ_CHC_BASE + i, b)
for addr in (BGM_B_PTR, BGM_B_PTR + 1, BGM_C_PTR, BGM_C_PTR + 1,
             BGM_B_TIMER, BGM_C_TIMER, BGM_B_REST, BGM_C_REST,
             BGM_B_LOOP_BASE, BGM_B_LOOP_BASE + 1,
             BGM_C_LOOP_BASE, BGM_C_LOOP_BASE + 1,
             BGM_B_ENV_IDX, BGM_C_ENV_IDX, BGM_B_DUTY_PHASE):
    z.wr(addr, 0xAA)  # poison first, same style as combined_test.asm's own boss_bgm_switch_test.py
z.wr(BGM_MUTED, 1)
call_routine(z, sym["SWITCH_BGM_TO_TRYZ"])
check("SWITCH_BGM_TO_TRYZ clears BGM_MUTED", z.rd(BGM_MUTED) == 0)
check("SWITCH_BGM_TO_TRYZ points BGM_B_PTR/BGM_B_LOOP_BASE at TryZ's own chB start",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)) == BGM_TRYZ_CHB_BASE and
      (z.rd(BGM_B_LOOP_BASE) | (z.rd(BGM_B_LOOP_BASE + 1) << 8)) == BGM_TRYZ_CHB_BASE)
check("SWITCH_BGM_TO_TRYZ points BGM_C_PTR/BGM_C_LOOP_BASE at TryZ's own chC start "
      "(a genuinely different address than ALONE_FIGHTER's own chC - Stage1 places TryZ "
      "in its own separate RAM region rather than overwriting ALONE_FIGHTER)",
      (z.rd(BGM_C_PTR) | (z.rd(BGM_C_PTR + 1) << 8)) == BGM_TRYZ_CHC_BASE and
      (z.rd(BGM_C_LOOP_BASE) | (z.rd(BGM_C_LOOP_BASE + 1) << 8)) == BGM_TRYZ_CHC_BASE and
      BGM_TRYZ_CHC_BASE != BGM_C_BASE)
check("SWITCH_BGM_TO_TRYZ resets BGM_B/C_TIMER and BGM_B/C_REST to 0",
      z.rd(BGM_B_TIMER) == 0 and z.rd(BGM_C_TIMER) == 0 and
      z.rd(BGM_B_REST) == 0 and z.rd(BGM_C_REST) == 0)

# ---- drive BGM_TICK once past TryZ's own chB start and confirm it reads
# TryZ's own real first row correctly - TryZ's chB actually opens with a
# REST row (the melody instrument doesn't start at tick 0 in the source
# MIDI), so the meaningful check is BGM_B_REST getting set, not a tone
# period (SETREST never touches R2/R3 at all) ----
call_routine(z, BGM_TICK)
if tryz_chB_bytes[0] == BGM_NOTE_REST:
    check("after SWITCH_BGM_TO_TRYZ, the very next BGM_TICK correctly reads TryZ's own "
          "real first chB row as a REST (BGM_B_REST=1, R9 silenced)",
          z.rd(BGM_B_REST) == 1 and z.psg_regs.get(9) == 0)
else:
    exp_lo, exp_hi = periods[tryz_chB_bytes[0]]
    check("after SWITCH_BGM_TO_TRYZ, the very next BGM_TICK plays TryZ's own real first chB note",
          (z.psg_regs.get(2), z.psg_regs.get(3)) == (exp_lo, exp_hi))

# ---- BOSS_UPDATE_BODY's own BOSS_STATE 1->2 transition (materialize
# finishing) is the real trigger site - drive it through a full real
# tile-reveal sequence and confirm SWITCH_BGM_TO_TRYZ actually fires
# there, not just when called directly above ----
z = fresh()
for i, b in enumerate(tryz_chB_bytes):
    z.wr(BGM_TRYZ_CHB_BASE + i, b)
for i, b in enumerate(tryz_chC_bytes):
    z.wr(BGM_TRYZ_CHC_BASE + i, b)
call_routine(z, sym["BOSS_SPAWN"])
check("real BOSS_SPAWN: BGM_MUTED=1 right after spawn (materialize just started)",
      z.rd(BGM_MUTED) == 1)
for _ in range(200):   # 5 rows x 16 cols = 80 tiles, each tile takes a few BOSS_UPDATE_BODY calls
    call_routine(z, sym["BOSS_UPDATE_BODY"])
    if z.rd(BOSS_STATE) == 2:
        break
else:
    raise AssertionError("BOSS_STATE never reached 2 (materialize never finished) within 200 calls")
check("real BOSS_UPDATE_BODY: BGM_MUTED cleared once BOSS_STATE reaches 2 (materialize finished)",
      z.rd(BGM_MUTED) == 0)
check("real BOSS_UPDATE_BODY: TryZ's own chB data is actually loaded (BGM_B_PTR points at it) "
      "once BOSS_STATE reaches 2 - the real trigger site, not a direct call, actually fired",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)) == BGM_TRYZ_CHB_BASE)

# ---- "マテリアライズ中は自機ショット音は停止" ----
z = fresh()
z.wr(BOSS_STATE, 1)
z.wr(SND_TONE_TIMER, 0)
z.wr(SND_BARRIER_DUTY_TIMER, 0)
z.wr(sym["SND_TONE_IS_SE"], 0)
call_routine(z, sym["SOUND_SHOT"])
check("SOUND_SHOT is silenced while BOSS_STATE==1 (materializing)", z.rd(SND_TONE_TIMER) == 0)

z = fresh()
z.wr(BOSS_STATE, 0)
z.wr(SND_TONE_TIMER, 0)
z.wr(SND_BARRIER_DUTY_TIMER, 0)
z.wr(sym["SND_TONE_IS_SE"], 0)
call_routine(z, sym["SOUND_SHOT"])
check("...but fires normally once BOSS_STATE!=1 (not materializing)", z.rd(SND_TONE_TIMER) != 0)

z = fresh()
z.wr(BOSS_STATE, 2)   # boss fully landed and fighting - must not be silenced
z.wr(SND_TONE_TIMER, 0)
z.wr(SND_BARRIER_DUTY_TIMER, 0)
z.wr(sym["SND_TONE_IS_SE"], 0)
call_routine(z, sym["SOUND_SHOT"])
check("...and also fires normally once BOSS_STATE==2 (boss landed, materialize long done)",
      z.rd(SND_TONE_TIMER) != 0)

# ---- (2026-09-06、"ではステージ1と2のスコアを加算して...これをステージ
# クリアで流して 3音使って良いんで") StageClearジングル(3パート:
# melody=chB/bass=chC/harmony=chA、LOOP_MARK方式)。TRIGGER_STAGE_CLEAR
# はPLAYER_FLYAWAYがちょうど2に到達した最初のフレームで1回だけ呼ばれ、
# UPDATE_STAGE_CLEARは以後毎フレーム呼ばれて実時間(SC_VBLANK_COUNT)を
# 監視し、STAGE_CLEAR_TOTAL_TICKS経過でSTAGE_CLEAR_ACTを2へ進める
# (build_full_rom.pyのMAINLOOP_PATCHがこれを見てStage2へバンク切替) ----
STAGE_CLEAR_ACT = sym["STAGE_CLEAR_ACT"]
SC_VBLANK_COUNT = sym["SC_VBLANK_COUNT"]
SC_START_TICK = sym["SC_START_TICK"]
STAGE_CLEAR_TOTAL_TICKS = sym["STAGE_CLEAR_TOTAL_TICKS"]
STAGE_CLEAR_CHB_BASE = sym["STAGE_CLEAR_CHB_BASE"]
STAGE_CLEAR_CHC_BASE = sym["STAGE_CLEAR_CHC_BASE"]
STAGE_CLEAR_CHA_BASE = sym["STAGE_CLEAR_CHA_BASE"]
BGM_A_PTR = sym["BGM_A_PTR"]
BGM_A_TIMER = sym["BGM_A_TIMER"]
BGM_A_REST = sym["BGM_A_REST"]
BGM_A_ENV_LEVEL = sym["BGM_A_ENV_LEVEL"]
BGM_A_ENV_IDX = sym["BGM_A_ENV_IDX"]
BGM_A_ENV_CD = sym["BGM_A_ENV_CD"]
PLAYER_FLYAWAY = sym["PLAYER_FLYAWAY"]

_sc_layout = layout["STAGE_CLEAR"]
_sc_start = _sc_layout["bank_offset"]
sc_chB_bytes = bank_image[_sc_start:_sc_start + _sc_layout["chB_len"]]
sc_chC_bytes = bank_image[_sc_start + _sc_layout["chB_len"]:
                           _sc_start + _sc_layout["chB_len"] + _sc_layout["chC_len"]]
sc_chA_bytes = bank_image[_sc_start + _sc_layout["chB_len"] + _sc_layout["chC_len"]:
                           _sc_start + _sc_layout["chB_len"] + _sc_layout["chC_len"] + _sc_layout["chA_len"]]

check("STAGE_CLEAR_CHC_BASE = STAGE_CLEAR_CHB_BASE + StageClear's own real chB length",
      STAGE_CLEAR_CHC_BASE == STAGE_CLEAR_CHB_BASE + _sc_layout["chB_len"])
check("STAGE_CLEAR_CHA_BASE = STAGE_CLEAR_CHC_BASE + StageClear's own real chC length",
      STAGE_CLEAR_CHA_BASE == STAGE_CLEAR_CHC_BASE + _sc_layout["chC_len"])

z = fresh()
for i, b in enumerate(sc_chB_bytes):
    z.wr(STAGE_CLEAR_CHB_BASE + i, b)
for i, b in enumerate(sc_chC_bytes):
    z.wr(STAGE_CLEAR_CHC_BASE + i, b)
for i, b in enumerate(sc_chA_bytes):
    z.wr(STAGE_CLEAR_CHA_BASE + i, b)
for addr in (BGM_B_PTR, BGM_B_PTR + 1, BGM_C_PTR, BGM_C_PTR + 1,
             BGM_A_PTR, BGM_A_PTR + 1,
             BGM_B_TIMER, BGM_C_TIMER, BGM_A_TIMER,
             BGM_B_REST, BGM_C_REST, BGM_A_REST,
             BGM_B_LOOP_BASE, BGM_B_LOOP_BASE + 1,
             BGM_C_LOOP_BASE, BGM_C_LOOP_BASE + 1,
             SC_START_TICK, SC_START_TICK + 1):
    z.wr(addr, 0xAA)  # poison first, same style as SWITCH_BGM_TO_TRYZ's own test above
z.wr(BGM_MUTED, 1)
z.wr(STAGE_CLEAR_ACT, 0)
z.wr(SC_VBLANK_COUNT, 0x34); z.wr(SC_VBLANK_COUNT + 1, 0x12)   # a distinctive non-zero "current real time"
call_routine(z, sym["TRIGGER_STAGE_CLEAR"])
check("TRIGGER_STAGE_CLEAR sets STAGE_CLEAR_ACT=1", z.rd(STAGE_CLEAR_ACT) == 1)
check("TRIGGER_STAGE_CLEAR snapshots SC_VBLANK_COUNT into SC_START_TICK",
      (z.rd(SC_START_TICK) | (z.rd(SC_START_TICK + 1) << 8)) == 0x1234)
check("TRIGGER_STAGE_CLEAR clears BGM_MUTED", z.rd(BGM_MUTED) == 0)
check("TRIGGER_STAGE_CLEAR points BGM_B_PTR/BGM_B_LOOP_BASE at StageClear's own chB(melody) start",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)) == STAGE_CLEAR_CHB_BASE and
      (z.rd(BGM_B_LOOP_BASE) | (z.rd(BGM_B_LOOP_BASE + 1) << 8)) == STAGE_CLEAR_CHB_BASE)
check("TRIGGER_STAGE_CLEAR points BGM_C_PTR/BGM_C_LOOP_BASE at StageClear's own chC(bass) start",
      (z.rd(BGM_C_PTR) | (z.rd(BGM_C_PTR + 1) << 8)) == STAGE_CLEAR_CHC_BASE and
      (z.rd(BGM_C_LOOP_BASE) | (z.rd(BGM_C_LOOP_BASE + 1) << 8)) == STAGE_CLEAR_CHC_BASE)
check("TRIGGER_STAGE_CLEAR points BGM_A_PTR at StageClear's own chA(harmony) start "
      "(chA is entirely new to Stage1 - only ever used for this jingle)",
      (z.rd(BGM_A_PTR) | (z.rd(BGM_A_PTR + 1) << 8)) == STAGE_CLEAR_CHA_BASE)
check("TRIGGER_STAGE_CLEAR resets BGM_B/C/A_TIMER and BGM_B/C/A_REST to 0",
      z.rd(BGM_B_TIMER) == 0 and z.rd(BGM_C_TIMER) == 0 and z.rd(BGM_A_TIMER) == 0 and
      z.rd(BGM_B_REST) == 0 and z.rd(BGM_C_REST) == 0 and z.rd(BGM_A_REST) == 0)

# ---- BGMT_UPDATE_SC_A (chA driver) actually plays StageClear's real chA
# data once armed - mirrors the TryZ chB REST-vs-note branch above ----
call_routine(z, BGM_TICK)
if sc_chA_bytes[0] == BGM_NOTE_REST:
    check("after TRIGGER_STAGE_CLEAR, the very next BGM_TICK correctly reads StageClear's own "
          "real first chA(harmony) row as a REST (BGM_A_REST=1, R8 silenced)",
          z.rd(BGM_A_REST) == 1 and z.psg_regs.get(8) == 0)
else:
    exp_lo, exp_hi = periods[sc_chA_bytes[0]]
    check("after TRIGGER_STAGE_CLEAR, the very next BGM_TICK plays StageClear's own real first "
          "chA(harmony) note",
          (z.psg_regs.get(0), z.psg_regs.get(1)) == (exp_lo, exp_hi))

# ---- UPDATE_STAGE_CLEAR's own real-time cutoff ----
z = fresh()
z.wr(STAGE_CLEAR_ACT, 1)
z.wr(SC_START_TICK, 100); z.wr(SC_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, (100 + STAGE_CLEAR_TOTAL_TICKS - 1) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (100 + STAGE_CLEAR_TOTAL_TICKS - 1) >> 8)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check(f"UPDATE_STAGE_CLEAR: still STAGE_CLEAR_ACT=1 one tick before "
      f"STAGE_CLEAR_TOTAL_TICKS({STAGE_CLEAR_TOTAL_TICKS}) elapses",
      z.rd(STAGE_CLEAR_ACT) == 1)

z = fresh()
z.wr(STAGE_CLEAR_ACT, 1)
z.wr(SC_START_TICK, 100); z.wr(SC_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, (100 + STAGE_CLEAR_TOTAL_TICKS) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (100 + STAGE_CLEAR_TOTAL_TICKS) >> 8)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR: advances to STAGE_CLEAR_ACT=2 exactly when "
      "STAGE_CLEAR_TOTAL_TICKS elapses",
      z.rd(STAGE_CLEAR_ACT) == 2)

z = fresh()
z.wr(STAGE_CLEAR_ACT, 0)   # not yet triggered - must be a no-op
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, 0xFF); z.wr(SC_VBLANK_COUNT + 1, 0xFF)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR is a no-op while STAGE_CLEAR_ACT==0 (not yet triggered)",
      z.rd(STAGE_CLEAR_ACT) == 0)

z = fresh()
z.wr(STAGE_CLEAR_ACT, 2)   # already done - must stay done, not somehow retrigger
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, 0); z.wr(SC_VBLANK_COUNT + 1, 0)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR is a no-op once STAGE_CLEAR_ACT==2 (already done)",
      z.rd(STAGE_CLEAR_ACT) == 2)

# ---- "これは3音使って良い" - ステージクリアジングル再生中(STAGE_CLEAR_
# ACT==1)は通常のSEドライバ(SOUND_UPDATE)自体がMAINLOOP側でスキップ
# される設計だが、SOUND_UPDATE自身はSTAGE_CLEAR_ACTを一切見ない(ゲート
# はMAINLOOP側の`CP 1:CALL NZ,SOUND_UPDATE`という1行のみ、GFEnding
# [Stage2]のENDING_ACT==2ゲートと同型) - SOUND_UPDATE自体を直接呼んでも
# 問題なく動作すること自体は確認できるが、MAINLOOP側のゲート判定
# そのものはcall_routine方式では検証できない独立したinline分岐のため、
# ここでは対象外(TRIGGER_STAGE_CLEAR/UPDATE_STAGE_CLEARという実際の
# 状態遷移ロジック自体は上記で直接検証済み)。

print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
