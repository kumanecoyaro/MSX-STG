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
BGM_B_PHASE = sym["BGM_B_PHASE"]
BGM_C_PHASE = sym["BGM_C_PHASE"]
BGM_B_DUTY_MASK = sym["BGM_B_DUTY_MASK"]
BGM_C_DUTY_MASK = sym["BGM_C_DUTY_MASK"]
BGM_VOLUME = sym["BGM_VOLUME"]

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
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, TEST_NOTE_B, TEST_DUR_B, timer=0)
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
call_routine(z, BGM_TICK)
check("chB loads a fresh row (BGM_B_TIMER reloaded to duration-1, round40 "
      "off-by-one fix - the load tick itself already plays the note once)",
      z.rd(BGM_B_TIMER) == TEST_DUR_B - 1)
exp_lo, exp_hi = periods[TEST_NOTE_B]
check("chB tone period (R2/R3) matches the period table",
      (z.psg_regs.get(2), z.psg_regs.get(3)) == (exp_lo, exp_hi))
check("chB volume (R9) is BGM_VOLUME", z.psg_regs.get(9) == sym["BGM_VOLUME"])
exp_lo_c, exp_hi_c = periods[TEST_NOTE_C]
check("chC loads a fresh row (BGM_C_TIMER reloaded to duration-1, round40 off-by-one fix)",
      z.rd(BGM_C_TIMER) == TEST_DUR_C - 1)
check("chC tone period (R4/R5) matches the period table",
      (z.psg_regs.get(4), z.psg_regs.get(5)) == (exp_lo_c, exp_hi_c))
check("chC volume (R10) is BGM_VOLUME", z.psg_regs.get(10) == sym["BGM_VOLUME"])

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
check("SE専用タイマー(SND_TIMER/SND_TONE_TIMER/SND_BARRIER_DUTY_TIMER)が全て非0でも "
      "BGM chBは無条件でR2/R3/R9へ書く(もう譲らない)",
      (z.psg_regs.get(2), z.psg_regs.get(3), z.psg_regs.get(9)) ==
      (exp_lo_b, exp_hi_b, sym["BGM_VOLUME"]))
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
      (exp_lo_c2, exp_hi_c2, sym["BGM_VOLUME"]))

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


# ---- デューティ比ゲート(実機フィードバック"ドライバにデューティ比
# 実装 6.25,12.5,25,50を実装 どちらの曲もパート1が25パート2が12.5")----
# Stage1もStage2/Titleと全く同じmask方式・同じ割り当て(chB=25%/chC=
# 12.5%)。チャンネルB/CはもうSEと無関係(SEは全てチャンネルAへ移設
# 済み)なので、単純にBGM単独での通常デューティ列を確認するだけでよい。
check("BGM_B_DUTY_MASK is 25%デューティ(mask=3, パート1)", BGM_B_DUTY_MASK == 3)
check("BGM_C_DUTY_MASK is 12.5%デューティ(mask=7, パート2)", BGM_C_DUTY_MASK == 7)


def duty_gate_sequence(z, ptr_addr, timer_addr, note, duration, vol_reg, n_ticks):
    row_addr = 0xD400
    poke_channel(z, ptr_addr, timer_addr, row_addr, note, duration, timer=0)
    seq = []
    for _ in range(n_ticks):
        call_routine(z, BGM_TICK)
        seq.append(z.psg_regs.get(vol_reg))
    return seq


z = fresh()
seq_b = duty_gate_sequence(z, BGM_B_PTR, BGM_B_TIMER, TEST_NOTE_B, 40, 9, 16)
expected_seq_b = [BGM_VOLUME if (t & BGM_B_DUTY_MASK) == 0 else 0 for t in range(16)]
check("chB(パート1, 25%デューティ): R9のON/OFF列が4tickに1回ONのパターンと完全一致",
      seq_b == expected_seq_b)

z = fresh()
seq_c = duty_gate_sequence(z, BGM_C_PTR, BGM_C_TIMER, TEST_NOTE_C, 40, 10, 16)
expected_seq_c = [BGM_VOLUME if (t & BGM_C_DUTY_MASK) == 0 else 0 for t in range(16)]
check("chC(パート2, 12.5%デューティ): R10のON/OFF列が8tickに1回ONのパターンと完全一致",
      seq_c == expected_seq_c)


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


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
