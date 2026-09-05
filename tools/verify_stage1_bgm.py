"""Stage1(src/CYBER SHMUP.asm): round40 BGM driver検証("タイトル含めて
各ステージにドライバを配置しRAMにコピーしてステージスタート")。

tools/verify_enemy_pool_scan.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine(センチネル0x0000方式)」の一回性検証スクリプト
の作法に倣う。Stage1はチャンネルB/Cを既存SFX(SOUND_POD_FIRE/SOUND_SHOT/
SOUND_POD_HIT/SOUND_BARRIER_HIT)と共有しているため、Stage2/Titleの
BGMドライバと違い「SFXタイマーが非0の間はBGM側が書き込みを完全に譲る」
という優先方式が本体 - このスクリプトはその優先ロジックと、
SOUND_UPDATE_B/SUC_NORMAL側の「アイドル中は何も書かない」変更の両方を
直接検証する。Stage1自身はRAMコピーもバンク切替も行わない
(Titleが起動時に一度だけコピーしたRAMをそのまま読むだけ)ため、その
部分の検証はtools/title_screen/title_test.pyの側で行う。
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
SND_TIMER_B = sym["SND_TIMER_B"]
SND_TIMER_C = sym["SND_TIMER_C"]
SND_C_DUTY_TIMER = sym["SND_C_DUTY_TIMER"]
PSG_ADDR = sym["PSG_ADDR"]
PSG_DATA = sym["PSG_DATA"]

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


# ---- normal playback (no SFX active): new-row load on each channel ----
z = fresh()
poke_period_table(z)
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, TEST_NOTE_B, TEST_DUR_B, timer=0)
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
z.wr(SND_TIMER_B, 0)
z.wr(SND_TIMER_C, 0)
z.wr(SND_C_DUTY_TIMER, 0)
call_routine(z, BGM_TICK)
check("no SFX active: chB loads a fresh row (BGM_B_TIMER reloaded to duration-1, round40 "
      "off-by-one fix - the load tick itself already plays the note once)",
      z.rd(BGM_B_TIMER) == TEST_DUR_B - 1)
exp_lo, exp_hi = periods[TEST_NOTE_B]
check("no SFX active: chB tone period (R2/R3) matches the period table",
      (z.psg_regs.get(2), z.psg_regs.get(3)) == (exp_lo, exp_hi))
check("no SFX active: chB volume (R9) is BGM_VOLUME", z.psg_regs.get(9) == sym["BGM_VOLUME"])
exp_lo_c, exp_hi_c = periods[TEST_NOTE_C]
check("no SFX active: chC loads a fresh row (BGM_C_TIMER reloaded to duration-1, round40 off-by-one fix)",
      z.rd(BGM_C_TIMER) == TEST_DUR_C - 1)
check("no SFX active: chC tone period (R4/R5) matches the period table",
      (z.psg_regs.get(4), z.psg_regs.get(5)) == (exp_lo_c, exp_hi_c))
check("no SFX active: chC volume (R10) is BGM_VOLUME", z.psg_regs.get(10) == sym["BGM_VOLUME"])

# ---- SFX priority: SND_TIMER_B active -> BGM channel B completely
# yields (no PSG writes at all, BGM_B_TIMER/BGM_B_PTR untouched) ----
z = fresh()
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, TEST_NOTE_B, TEST_DUR_B, timer=0)
z.wr(SND_TIMER_B, 15)  # SOUND_POD_FIRE currently playing
for reg in (2, 3, 9):
    z.psg_regs.pop(reg, None)
ptr_before = z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)
timer_before = z.rd(BGM_B_TIMER)
call_routine(z, BGM_TICK)
check("SND_TIMER_B active (SOUND_POD_FIRE playing): BGM writes NOTHING to R2/R3/R9",
      all(r not in z.psg_regs for r in (2, 3, 9)))
check("SND_TIMER_B active: BGM_B_PTR is completely untouched",
      (z.rd(BGM_B_PTR) | (z.rd(BGM_B_PTR + 1) << 8)) == ptr_before)
check("SND_TIMER_B active: BGM_B_TIMER is completely untouched (BGM's own timing pauses, doesn't skip ahead)",
      z.rd(BGM_B_TIMER) == timer_before)

# ---- SFX priority: SND_TIMER_C active (SOUND_SHOT/SOUND_POD_HIT) ->
# BGM channel C completely yields ----
z = fresh()
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
z.wr(SND_TIMER_C, 12)
z.wr(SND_C_DUTY_TIMER, 0)
for reg in (4, 5, 10):
    z.psg_regs.pop(reg, None)
call_routine(z, BGM_TICK)
check("SND_TIMER_C active (SOUND_SHOT/SOUND_POD_HIT playing): BGM writes NOTHING to R4/R5/R10",
      all(r not in z.psg_regs for r in (4, 5, 10)))

# ---- SFX priority: SND_C_DUTY_TIMER active (SOUND_BARRIER_HIT) ->
# BGM channel C also completely yields (the OTHER channel-C SFX gate) ----
z = fresh()
poke_channel(z, BGM_C_PTR, BGM_C_TIMER, ROW_C, TEST_NOTE_C, TEST_DUR_C, timer=0)
z.wr(SND_TIMER_C, 0)
z.wr(SND_C_DUTY_TIMER, 8)
for reg in (4, 5, 10):
    z.psg_regs.pop(reg, None)
call_routine(z, BGM_TICK)
check("SND_C_DUTY_TIMER active (SOUND_BARRIER_HIT playing): BGM writes NOTHING to R4/R5/R10",
      all(r not in z.psg_regs for r in (4, 5, 10)))

# ---- rest notes / loop marker (same shape as Stage2/Title's own driver) ----
z = fresh()
poke_channel(z, BGM_B_PTR, BGM_B_TIMER, ROW_B, BGM_NOTE_REST, 9, timer=0)
z.wr(SND_TIMER_B, 0)
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
z.wr(SND_TIMER_B, 0)
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


def observed_note_change_ticks(z, tone_lo_reg, tone_hi_reg, vol_reg, n_ticks):
    events = []
    last = None
    for tick in range(n_ticks):
        call_routine(z, BGM_TICK)
        key = (z.psg_regs.get(tone_lo_reg), z.psg_regs.get(tone_hi_reg), z.psg_regs.get(vol_reg))
        if key != last:
            note = None if key[2] == 0 else next(
                (i for i, (lo_v, hi_v) in enumerate(periods) if (lo_v, hi_v) == key[:2]), None)
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
z.wr(SND_TIMER_B, 0)
z.wr(SND_TIMER_C, 0)
z.wr(SND_C_DUTY_TIMER, 0)
observed_b = observed_note_change_ticks(z, 2, 3, 9, N_TICKS)
expected_b = []
cum = 0
for note, dur in decode_rows(chB_bytes):
    if cum >= N_TICKS:
        break
    expected_b.append((cum, None if note == BGM_NOTE_REST else note))
    cum += dur
check(f"round40 off-by-one regression: {len(expected_b)} real ALONE_FIGHTER chB note-change ticks "
      f"(over {N_TICKS} real BGM_TICK calls from a real boot, no SFX active throughout) match the "
      "real bgm_bank.bin row data EXACTLY",
      observed_b == expected_b)


# ---- the other half of the fix: SOUND_UPDATE_B/SUC_NORMAL must write
# NOTHING once idle (SND_TIMER_B/SND_TIMER_C == 0), so BGM can own the
# channel right back - direct regression check for this round's change ----
def call_sound_update(z, snd_timer=0, snd_timer_b=0, snd_timer_c=0, snd_c_duty=0, snd_noise=0):
    z.wr(sym["SND_TIMER"], snd_timer)
    z.wr(SND_TIMER_B, snd_timer_b)
    z.wr(SND_TIMER_C, snd_timer_c)
    z.wr(SND_C_DUTY_TIMER, snd_c_duty)
    call_routine(z, sym["SOUND_UPDATE"])


z = fresh()
for reg in (9,):
    z.psg_regs.pop(reg, None)
call_sound_update(z, snd_timer_b=0)
check("SOUND_UPDATE_B idle (SND_TIMER_B=0): writes NOTHING to R9 (yields to BGM)", 9 not in z.psg_regs)

z = fresh()
z.psg_regs[9] = 0x99  # poison - if SOUND_UPDATE writes anything it won't be this
call_sound_update(z, snd_timer_b=7)
check("SOUND_UPDATE_B active (SND_TIMER_B=7): still writes the current value to R9 (unchanged real behavior)",
      z.psg_regs.get(9) == 7)
check("SOUND_UPDATE_B active: SND_TIMER_B decremented as before", z.rd(SND_TIMER_B) == 6)

z = fresh()
for reg in (10,):
    z.psg_regs.pop(reg, None)
call_sound_update(z, snd_timer_c=0, snd_c_duty=0)
check("SUC_NORMAL idle (SND_TIMER_C=0): writes NOTHING to R10 (yields to BGM)", 10 not in z.psg_regs)

z = fresh()
z.psg_regs[10] = 0x99
call_sound_update(z, snd_timer_c=9, snd_c_duty=0)
check("SUC_NORMAL active (SND_TIMER_C=9): still writes the current value to R10 (unchanged real behavior)",
      z.psg_regs.get(10) == 9)
check("SUC_NORMAL active: SND_TIMER_C decremented as before", z.rd(SND_TIMER_C) == 8)


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
    ("SOUND_UPDATE", {sym["SND_TIMER"]: 5, SND_TIMER_B: 5, SND_TIMER_C: 5, SND_C_DUTY_TIMER: 0}),
    ("SOUND_UPDATE", {sym["SND_TIMER"]: 5, SND_TIMER_B: 0, SND_TIMER_C: 0, SND_C_DUTY_TIMER: 8}),
]:
    saw, masked = scan_psg_out_iff1(sym[name], presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)", masked)

# BGM_TICK itself needs no DI/EI wrapping (runs entirely inside one
# interrupt, same reasoning as Stage2/Title's own driver).
saw, masked = scan_psg_out_iff1(BGM_TICK, {BGM_B_TIMER: 0, BGM_C_TIMER: 0, SND_TIMER_B: 0, SND_TIMER_C: 0, SND_C_DUTY_TIMER: 0})
check("BGM_TICK: real PSG_ADDR/PSG_DATA OUTs found", saw)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
