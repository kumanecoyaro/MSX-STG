"""Round40 ("では添付ファイルのMIDIをノートだけ抽出してPSGで鳴らして
くれ...方法としては先ほどのRAM方式で転送 タイトル含めて各ステージに
ドライバを配置しRAMにコピーしてステージスタート"): the redesigned BGM
driver - independent per-channel pointer/timer (BGM_B_PTR/TIMER,
BGM_C_PTR/TIMER) instead of Round38's single shared row, reading real
MIDI-derived song data (tools/bgm_data/midi_to_psg.py) copied into RAM
from a new dedicated ROM bank instead of a resident placeholder DB
table (see combined_test.asm's own long comment right above INIT_BGM
for the full design rationale, including why Stage1 needs none of this
RAM-copy machinery of its own - see src/CYBER SHMUP.asm's own BGM_TICK
comment instead).

z80emu.py has no interrupt simulation at all - BGM_TICK/BGMT_UPDATE_B/C
are verified the same way every other routine in this file's own test
suite already is: direct CALL via call_routine(). INIT_BGM's own hook
installation AND its RAM copy are checked separately, by reading back
real post-boot state (fresh_cpu() now genuinely exercises windowB's
switch-away-and-back via build_test.py's own BankedMem, which round40
gave a real bgm-data bank at index2 instead of a 0xFF placeholder).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
import bgm_bank_gen as bg  # noqa: E402 - no mido dependency, reads the cached bgm_bank.bin/bgm_layout.json

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


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
PSG_ADDR = sym["PSG_ADDR"]
PSG_DATA = sym["PSG_DATA"]

DEFEAT = bg.song_constants("DEFEAT", data_base=bg.STAGE2_DATA_BASE)
bank_image, layout = bg.build_bank()
_defeat_layout = layout["DEFEAT"]
lo = list(bank_image[0:bg.NUM_NOTES])
hi = list(bank_image[bg.NUM_NOTES:2 * bg.NUM_NOTES])
_song_start = _defeat_layout["bank_offset"]
chB_bytes = bank_image[_song_start:_song_start + _defeat_layout["chB_len"]]
chC_bytes = bank_image[_song_start + _defeat_layout["chB_len"]:
                        _song_start + _defeat_layout["chB_len"] + _defeat_layout["chC_len"]]


# ---- constants agree with tools/bgm_data/bgm_bank_gen.py's own DEFEAT/
# STAGE2_DATA_BASE layout (combined_test.asm can't use the generic
# BGM_DATA_BASE=0xC000 default - see its own EQU comment: that address
# range is already SBEAM_SPRITE_ATTRS/FLYER_POOL/BOSS_BROKEN_*/etc real
# data in this file specifically) ----
check("BGM_PERIOD_LO_RAM matches bgm_bank_gen's DEFEAT/STAGE2_DATA_BASE layout",
      BGM_PERIOD_LO_RAM == DEFEAT["PERIOD_LO_RAM"])
check("BGM_PERIOD_HI_RAM matches bgm_bank_gen's DEFEAT/STAGE2_DATA_BASE layout",
      BGM_PERIOD_HI_RAM == DEFEAT["PERIOD_HI_RAM"])
check("BGM_B_BASE matches DEFEAT's own CHB_RAM_BASE",
      BGM_B_BASE == DEFEAT["CHB_RAM_BASE"])
check("BGM_C_BASE matches DEFEAT's own CHC_RAM_BASE",
      BGM_C_BASE == DEFEAT["CHC_RAM_BASE"])
check("BGM_B_PTR/BGM_C_PTR/BGM_B_TIMER/BGM_C_TIMER match bgm_bank_gen's DEFEAT/STAGE2_DATA_BASE layout",
      (BGM_B_PTR, BGM_C_PTR, BGM_B_TIMER, BGM_C_TIMER) ==
      (DEFEAT["BGM_B_PTR"], DEFEAT["BGM_C_PTR"], DEFEAT["BGM_B_TIMER"], DEFEAT["BGM_C_TIMER"]))


# ---- real boot trace: INIT_BGM's own RAM copy + hook install ----
cpu = fresh_cpu()
check("INIT_BGM wrote a JP opcode (0C3h) into HTIMI_HOOK",
      cpu.mem[HTIMI_HOOK] == 0xC3)
hook_target = cpu.mem[HTIMI_HOOK + 1] | (cpu.mem[HTIMI_HOOK + 2] << 8)
check(f"INIT_BGM's JP target ({hex(hook_target)}) is BGM_TICK ({hex(BGM_TICK)})",
      hook_target == BGM_TICK)
check("INIT_BGM left BGM_B_PTR pointing at BGM_B_BASE",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == BGM_B_BASE)
check("INIT_BGM left BGM_C_PTR pointing at BGM_C_BASE",
      (cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)) == BGM_C_BASE)
check("INIT_BGM left BGM_B_TIMER/BGM_C_TIMER at 0 (first tick always loads a fresh row)",
      cpu.mem[BGM_B_TIMER] == 0 and cpu.mem[BGM_C_TIMER] == 0)
check("INIT_BGM's real windowB->bgm-bank->own-bank1 copy left the period table byte-correct in RAM",
      [cpu.mem[BGM_PERIOD_LO_RAM + i] for i in range(len(lo))] == lo and
      [cpu.mem[BGM_PERIOD_HI_RAM + i] for i in range(len(hi))] == hi)
check("INIT_BGM's copy left DEFEAT's own chB (track0) byte-correct in RAM",
      [cpu.mem[BGM_B_BASE + i] for i in range(len(chB_bytes))] == list(chB_bytes))
check("INIT_BGM's copy left DEFEAT's own chC (track1) byte-correct in RAM",
      [cpu.mem[BGM_C_BASE + i] for i in range(len(chC_bytes))] == list(chC_bytes))
check("INIT_BGM's copy restored windowB to this ROM's own bank1 (real game content, not the bgm bank) "
      "afterward - confirmed indirectly: MAINLOOP's own page2-resident code kept executing normally "
      "all the way through boot",
      cpu.mem.bankB == 1)


def poke_channel(cpu, ptr_sym, timer_sym, base_addr, note, duration, timer=0):
    cpu.mem[sym[timer_sym]] = timer
    cpu.mem[sym[ptr_sym]] = base_addr & 0xFF
    cpu.mem[sym[ptr_sym] + 1] = (base_addr >> 8) & 0xFF
    cpu.mem[base_addr] = note & 0xFF
    cpu.mem[base_addr + 1] = duration & 0xFF


ROW_ADDR_B = 0xD000  # scratch RAM, well clear of any real pool or the real song data
ROW_ADDR_C = 0xD100

periods = list(zip(lo, hi))
TEST_NOTE_B = 5
TEST_NOTE_C = 17
TEST_DURATION_B = 23
TEST_DURATION_C = 31


# ---- row-hold path: a channel with TIMER>0 just counts down, doesn't
# touch that channel's own PTR or PSG registers - and does so
# independently of the OTHER channel (the whole point of round40's
# redesign: chB/chC no longer share one row/duration) ----
cpu = fresh_cpu()
poke_channel(cpu, "BGM_B_PTR", "BGM_B_TIMER", ROW_ADDR_B, TEST_NOTE_B, TEST_DURATION_B, timer=5)
poke_channel(cpu, "BGM_C_PTR", "BGM_C_TIMER", ROW_ADDR_C, TEST_NOTE_C, TEST_DURATION_C, timer=0)
ptr_b_before = cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)
call_routine(cpu, "BGM_TICK")
check("row-hold (chB): BGM_B_TIMER decrements by exactly 1 (5 -> 4)",
      cpu.mem[BGM_B_TIMER] == 4)
check("row-hold (chB): BGM_B_PTR is untouched while holding",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == ptr_b_before)
check("independent channels: chC (TIMER=0) loaded its own new row in the SAME tick chB held "
      "(TIMER=duration-1, round40 off-by-one fix: this load tick itself already plays the note once, "
      "so the timer holds duration-1 MORE ticks before the next new-row load, totaling exactly "
      "duration ticks for the row)",
      cpu.mem[BGM_C_TIMER] == TEST_DURATION_C - 1)
exp_c_lo, exp_c_hi = periods[TEST_NOTE_C]
check("independent channels: chC's new-row write (R4/R5) used chC's own note, unaffected by chB holding",
      (cpu.psg_regs.get(4), cpu.psg_regs.get(5)) == (exp_c_lo, exp_c_hi))


# ---- new-row path (chB): TIMER==0 loads the next row, writes the
# looked-up period (R2/R3) + BGM_VOLUME (R9), advances the pointer by 2
# bytes, reloads TIMER from the row's own duration byte ----
cpu = fresh_cpu()
poke_channel(cpu, "BGM_B_PTR", "BGM_B_TIMER", ROW_ADDR_B, TEST_NOTE_B, TEST_DURATION_B, timer=0)
poke_channel(cpu, "BGM_C_PTR", "BGM_C_TIMER", ROW_ADDR_C, BGM_NOTE_REST, 9, timer=1)  # hold chC out of the way
call_routine(cpu, "BGM_TICK")
check("new-row (chB): BGM_B_TIMER reloaded from the row's own duration byte minus 1 (round40 "
      "off-by-one fix - see the independent-channels check above for why)",
      cpu.mem[BGM_B_TIMER] == TEST_DURATION_B - 1)
check("new-row (chB): BGM_B_PTR advanced by exactly 2 bytes (note+duration, no shared 3rd byte anymore)",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == ROW_ADDR_B + 2)
exp_b_lo, exp_b_hi = periods[TEST_NOTE_B]
check(f"new-row (chB): tone period (R2/R3) matches the period table's own note{TEST_NOTE_B} "
      f"({exp_b_lo},{exp_b_hi})",
      (cpu.psg_regs.get(2), cpu.psg_regs.get(3)) == (exp_b_lo, exp_b_hi))
check("new-row (chB): volume (R9) is BGM_VOLUME", cpu.psg_regs.get(9) == sym["BGM_VOLUME"])


# ---- rest notes: BGM_NOTE_REST silences that channel's volume register
# only, without writing that channel's period registers at all ----
cpu = fresh_cpu()
poke_channel(cpu, "BGM_B_PTR", "BGM_B_TIMER", ROW_ADDR_B, BGM_NOTE_REST, 10, timer=0)
poke_channel(cpu, "BGM_C_PTR", "BGM_C_TIMER", ROW_ADDR_C, BGM_NOTE_REST, 10, timer=0)
for poison_reg in (2, 3, 4, 5):
    cpu.psg_regs.pop(poison_reg, None)
call_routine(cpu, "BGM_TICK")
check("rest note: channel B period registers (R2/R3) are NOT written", 2 not in cpu.psg_regs and 3 not in cpu.psg_regs)
check("rest note: channel C period registers (R4/R5) are NOT written", 4 not in cpu.psg_regs and 5 not in cpu.psg_regs)
check("rest note: channel B volume (R9) is silenced to 0", cpu.psg_regs.get(9) == 0)
check("rest note: channel C volume (R10) is silenced to 0", cpu.psg_regs.get(10) == 0)


# ---- looping: BGM_LOOP_MARK at the current pointer resets that
# channel's OWN pointer to its OWN base and loads its first row -
# independently per channel (chB looping must not touch chC's pointer). ----
cpu = fresh_cpu()
loop_addr = 0xD200
cpu.mem[loop_addr] = BGM_LOOP_MARK
poke_channel(cpu, "BGM_C_PTR", "BGM_C_TIMER", ROW_ADDR_C, BGM_NOTE_REST, 5, timer=1)  # chC held, untouched
cpu.mem[sym["BGM_B_PTR"]] = loop_addr & 0xFF
cpu.mem[sym["BGM_B_PTR"] + 1] = (loop_addr >> 8) & 0xFF
cpu.mem[sym["BGM_B_TIMER"]] = 0
first_note = cpu.mem[BGM_B_BASE]
first_dur = cpu.mem[BGM_B_BASE + 1]
c_ptr_before = cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)
call_routine(cpu, "BGM_TICK")
check("loop mark (chB): BGM_B_PTR resets to BGM_B_BASE+2 (real DEFEAT chB's own first row, now consumed)",
      (cpu.mem[BGM_B_PTR] | (cpu.mem[BGM_B_PTR + 1] << 8)) == BGM_B_BASE + 2)
check("loop mark (chB): reloaded BGM_B_TIMER matches DEFEAT chB's own real first-row duration "
      "minus 1 (round40 off-by-one fix)",
      cpu.mem[BGM_B_TIMER] == first_dur - 1)
check("loop mark (chB): chC's own pointer is completely unaffected",
      (cpu.mem[BGM_C_PTR] | (cpu.mem[BGM_C_PTR + 1] << 8)) == c_ptr_before)
if first_note != BGM_NOTE_REST:
    exp_lo, exp_hi = periods[first_note]
    check("loop mark (chB): tone period matches DEFEAT chB's own real first row",
          (cpu.psg_regs.get(2), cpu.psg_regs.get(3)) == (exp_lo, exp_hi))


# ---- round40 実機フィードバック対応 ("こりゃ酷い ピーピー不協和音
# 休符も無視してるな テンポも無茶苦茶だ 自分でドライバ実装してて
# 仕様を一致させられんのかお前は"): off-by-oneの直接回帰ガード。
# BGMT_UB/UC_NEWROWは新しい行を読み込んだそのtick自体で既に1tick分の
# 再生を行っている(この直後のPSG書き込みで今tickからその音が鳴る)のに、
# 素のduration値をそのままTIMERへ積んでいたため「今tick+その後duration
# 回のホールド」で合計duration+1tick鳴ってしまっていた(DEC Aで修正
# 済み、上の3件のcheckがTEST_DURATION-1へ更新されている理由もこれ)。
# 単発の値比較だけでは「1行だけならズレに気づきにくい」ため、実際に
# BGM_TICKを多数回連続で叩いて「観測された音切り替わりtickの列」を
# tools/bgm_data/midi_to_psg.pyが計算する本物のDEFEAT chB/chC行データ
# (曲によって行数が全く違う - chB150行/chC818行 - ため、off-by-oneが
# 残っていれば2ch間のズレが曲が進むほど拡大し、これが実機報告の
# 「不協和音」の直接の原因だった)と正確に一致するかを検証する -
# 1行分の検証では検出できない類のバグを狙い撃つ回帰テスト。
def observed_note_change_ticks(cpu, ptr_sym, timer_sym, tone_lo_reg, tone_hi_reg, vol_reg, n_ticks):
    events = []
    last = None
    for tick in range(n_ticks):
        call_routine(cpu, "BGM_TICK")
        key = (cpu.psg_regs.get(tone_lo_reg), cpu.psg_regs.get(tone_hi_reg), cpu.psg_regs.get(vol_reg))
        if key != last:
            note = None if key[2] == 0 else next(
                (i for i, (lo_v, hi_v) in enumerate(periods) if (lo_v, hi_v) == key[:2]), None)
            events.append((tick, note))
            last = key
    return events


def decode_rows(row_bytes):
    """2byte/行(note,duration)+末尾1byte LOOP_MARKの実バイト列を
    (note,duration)の列へ戻す - mido不要(このファイル自身がmidoに
    依存しない設計、上のbg.build_bank()経由のコメント参照)。"""
    rows = []
    i = 0
    while i + 1 < len(row_bytes):
        rows.append((row_bytes[i], row_bytes[i + 1]))
        i += 2
    return rows


N_TICKS = 2000
cpu = fresh_cpu()
observed_b = observed_note_change_ticks(cpu, BGM_B_PTR, BGM_B_TIMER, 2, 3, 9, N_TICKS)
expected_b = []
cum = 0
for note, dur in decode_rows(chB_bytes):
    if cum >= N_TICKS:
        break
    expected_b.append((cum, None if note == BGM_NOTE_REST else note))
    cum += dur
check(f"round40 off-by-one regression: {len(expected_b)} real DEFEAT chB note-change ticks "
      f"(over {N_TICKS} real BGM_TICK calls from a fresh boot) match the real bgm_bank.bin row data "
      "EXACTLY (tick position and note both) - this is what an accumulating +1-per-row "
      "drift would break long before any single-row check would",
      observed_b == expected_b)

cpu = fresh_cpu()
observed_c = observed_note_change_ticks(cpu, BGM_C_PTR, BGM_C_TIMER, 4, 5, 10, N_TICKS)
expected_c = []
cum = 0
for note, dur in decode_rows(chC_bytes):
    if cum >= N_TICKS:
        break
    expected_c.append((cum, None if note == BGM_NOTE_REST else note))
    cum += dur
check(f"round40 off-by-one regression: {len(expected_c)} real DEFEAT chC note-change ticks match "
      "the real bgm_bank.bin row data EXACTLY",
      observed_c == expected_c)


# ---- R7 mixer read-modify-write: only bits1-2 (tone B/C enable) ever
# change - unchanged from round38 ----
cpu = fresh_cpu()
cpu.mem[BGM_B_TIMER] = 9
cpu.mem[BGM_C_TIMER] = 9
for probe in (0b10111000, 0b01000111, 0b11111111, 0b00000000):
    cpu.psg_regs[7] = probe
    call_routine(cpu, "BGM_TICK")
    written = cpu.psg_regs.get(7)
    expected = probe & 0xF9
    check(f"R7 read-modify-write: probe {bin(probe)} -> {bin(written) if written is not None else None} "
          f"(bits1-2 cleared, everything else preserved: expected {bin(expected)})",
          written == expected)


# ---- DI/EI protection: every existing SOUND_* trigger this round wrapped
# in DI/EI must genuinely execute its PSG_ADDR/PSG_DATA OUT pairs with
# IFF1 already False - unchanged from round38's own check, still valid
# since none of those routines' own PSG sequencing changed. ----
PROTECTED_ROUTINES = [
    ("SOUND_SHOT", {"SND_EXPLODING": 0}),
    ("SOUND_SPARK_CRACKLE", {}),
    ("SOUND_DESTROY", {}),
    ("SOUND_ZUM_DEFLECT", {}),
    ("SOUND_BOSS_BOOM", {}),
    ("SOUND_HORMING", {}),
    ("SOUND_THUNDER", {}),
    ("SOUND_SBEAM", {}),
    ("STOP_SBEAM_SOUND", {}),
    ("SOUND_SASAPI_LASER", {}),
    ("SOUND_BOSS_MATERIALIZE", {}),
]


def scan_psg_out_iff1(name, presets):
    cpu = fresh_cpu()
    for var, val in presets.items():
        cpu.mem[sym[var]] = val
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.mem[cpu.sp] = 0
    cpu.mem[cpu.sp + 1] = 0
    cpu.pc = sym[name]
    saw_psg_out = False
    all_masked = True
    steps = 0
    while cpu.pc != 0 and steps < 5000:
        opcode = cpu.mem[cpu.pc]
        if opcode == 0xD3:  # OUT (n),A
            port = cpu.mem[(cpu.pc + 1) & 0xFFFF]
            if port in (PSG_ADDR, PSG_DATA):
                saw_psg_out = True
                if cpu.iff1:
                    all_masked = False
        cpu.step()
        steps += 1
    return saw_psg_out, all_masked


for name, presets in PROTECTED_ROUTINES:
    saw, masked = scan_psg_out_iff1(name, presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)",
          masked)

for name, presets in [("SOUND_UPDATE", {"SND_DECAY": 2, "SND_TIMER": 5, "SND_NOISE": 0}),
                       ("SU_BOOM", {"SND_TIMER": 5, "SND_NOISE": 0})]:
    saw, masked = scan_psg_out_iff1(name, presets)
    check(f"{name}: real PSG_ADDR/PSG_DATA OUTs found", saw)
    check(f"{name}: every PSG_ADDR/PSG_DATA OUT executes with IFF1=False (DI in effect)",
          masked)

# BGM_TICK itself needs no DI/EI wrapping (it never has interrupts
# enabled inside it in the first place - see its own comment).
saw, masked = scan_psg_out_iff1("BGM_TICK", {"BGM_B_TIMER": 0, "BGM_C_TIMER": 0})
check("BGM_TICK: real PSG_ADDR/PSG_DATA OUTs found", saw)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
