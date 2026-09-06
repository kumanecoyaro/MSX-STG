"""Verifies the round32 port of Stage2's noise-sound duty-cycle gating
into src/CYBER SHMUP.asm (Stage1) - "ステージ1もデューティ比操作を適用"
- channel A's own R8 volume write in SOUND_UPDATE alternates every frame
between the current envelope and silence, following TICK's own low bit,
via CALC_NOISE_GATE_VOLUME, for the NOISE-side envelope (SND_TIMER)
only.

実機フィードバック対応("そもそもchB、Cは空けてあってSE類はchAのみで
鳴らすはず")で、従来チャンネルB/Cに分かれていたトーンSE(SOUND_SHOT/
SOUND_POD_HIT/SOUND_POD_FIRE)も全てチャンネルAへ統合され、SND_TONE_
TIMER(ゲート無し)/SND_BARRIER_DUTY_TIMER(専用の2連バズゲート)という
別々の減衰タイマーを介して同じR8を奪い合うようになった。SOUND_UPDATEは
優先順位(バリア>トーン>ノイズ)で1フレームにつき1つだけを実際にR8へ
書く - このファイル自身のSOUND_UPDATEのコメント参照。

z80emu.py has no PSG emulation at all (OUT only does anything for the
VDP ports), so the actual byte written to the PSG can never be observed
directly - same limitation Stage2's own boss_boom_sound_test.py/
noise_duty_cycle_test.py work around. What IS verified: CALC_NOISE_
GATE_VOLUME's own return value (a pure, side-effect-free function, kept
standalone specifically so it's testable this way) for a matrix of
SND_TIMER/TICK combinations, independently re-derived here rather than
read back from the ASM's own logic; that SND_TIMER itself still decays
normally through SOUND_UPDATE (the gating only affects what's WRITTEN,
not the underlying envelope); that SND_TONE_TIMER decays completely
unaffected by TICK (still ungated, exactly the pre-migration character);
and the 3-way priority order among SND_BARRIER_DUTY_TIMER/SND_TONE_
TIMER/SND_TIMER when more than one is simultaneously active.

Usage: python3 tools/verify_sound_duty_cycle.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mini_z80asm import Assembler
from z80emu import Z80

SRC_PATH = os.path.join(HERE, "..", "src", "CYBER SHMUP.asm")

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


text = open(SRC_PATH, encoding="utf-8").read()
asm = Assembler(text)
out = asm.assemble()
check(f"the real file still assembles cleanly ({len(out)} bytes)", len(out) > 0)
sym = asm.symtab

TICK = sym["TICK"]
SND_TIMER = sym["SND_TIMER"]
SND_TONE_TIMER = sym["SND_TONE_TIMER"]
SND_BARRIER_DUTY_TIMER = sym["SND_BARRIER_DUTY_TIMER"]

mem = bytearray(65536)
for addr, val in out.items():
    mem[addr & 0xFFFF] = val & 0xFF

SENTINEL = 0x0000  # never real code - z80emu has no ROM/RAM mapped meaning there, safe as a return trap


def fresh_cpu():
    z = Z80(bytearray(mem))
    z.sp = 0xFE00
    return z


def call_routine(cpu, addr, max_instr=20000):
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.wr(cpu.sp, SENTINEL & 0xFF)
    cpu.wr((cpu.sp + 1) & 0xFFFF, (SENTINEL >> 8) & 0xFF)
    cpu.pc = addr
    steps = 0
    while cpu.pc != SENTINEL and steps < max_instr:
        cpu.step()
        steps += 1
    assert steps < max_instr, f"call to {addr:04x} never returned"


# ---------------------------------------------------------------------
# 1: CALC_NOISE_GATE_VOLUME itself, exercised directly - a pure function
# of SND_TIMER/TICK, independently re-derived (not read back from the
# ASM's own logic).
# ---------------------------------------------------------------------
def expected_gate(timer, tick):
    if tick & 1:
        return 0
    return timer


for timer in (0, 1, 7, 15, 14, 3):
    for tick in (0, 1, 2, 3, 62, 63):
        cpu = fresh_cpu()
        cpu.wr(SND_TIMER, timer)
        cpu.wr(TICK, tick)
        call_routine(cpu, sym["CALC_NOISE_GATE_VOLUME"])
        expected = expected_gate(timer, tick)
        check(f"CALC_NOISE_GATE_VOLUME(timer={timer},tick={tick}) == {expected} (got {cpu.a})",
              cpu.a == expected)

# ---------------------------------------------------------------------
# 2: SOUND_UPDATE's own channel-A envelope still decays normally over
# many frames - the gate only affects what's WRITTEN to the PSG, not
# the underlying SND_TIMER countdown itself.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_DESTROY"])
check("SOUND_DESTROY sets SND_TIMER to its own peak (15)", cpu.rd(SND_TIMER) == 15)
timer_trace = []
for frame in range(20):
    cpu.wr(TICK, frame)  # TICK's own real update (INC A:AND 3Fh) isn't run here - poked directly, same idiom as Stage2's own tests poking TICK between calls
    call_routine(cpu, sym["SOUND_UPDATE"])
    timer_trace.append(cpu.rd(SND_TIMER))
expected_trace = [max(0, 15 - f) for f in range(1, 21)]
check(f"SND_TIMER decays by exactly 1/frame through SOUND_UPDATE regardless of the "
      f"gating (expected {expected_trace}, got {timer_trace})",
      timer_trace == expected_trace)
check("SND_TIMER reaches exactly 0 after 15 frames (its own real peak, unaffected by "
      "the duty-cycle write gating)", timer_trace[14] == 0)

# ---------------------------------------------------------------------
# 3: SND_TONE_TIMER (SOUND_SHOT/SOUND_POD_HIT/SOUND_POD_FIRE, all merged
# onto channel A's tone generator - "そもそもchB、Cは空けてあってSE類は
# chAのみで鳴らすはず") decays completely independently of TICK -
# confirms it stays ungated exactly like before the migration (only
# SND_TIMER's own noise-side envelope gets the duty-cycle treatment).
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_SHOT"])
check("SOUND_SHOT sets SND_TONE_TIMER to its own peak (12)", cpu.rd(SND_TONE_TIMER) == 12)
tone_trace = []
for frame in range(13):
    cpu.wr(TICK, frame)  # alternates parity every frame - tone SE must not care
    call_routine(cpu, sym["SOUND_UPDATE"])
    tone_trace.append(cpu.rd(SND_TONE_TIMER))
expected_tone = [max(0, 12 - f) for f in range(1, 14)]
check(f"SND_TONE_TIMER decays by exactly 1/frame regardless of TICK's own parity "
      f"(expected {expected_tone}, got {tone_trace})", tone_trace == expected_tone)

# "SE優先でショットは消す仕様に SE発声中はショット音は鳴らない" - firing
# an SE (POD_FIRE) then a shot while the SE's decay is still active no
# longer collapses onto "last write wins": the shot request is dropped
# entirely (SND_TONE_IS_SE gates it), leaving the SE's own timer/period
# completely untouched. See tools/verify_player_damage.py (or a future
# dedicated script) for the RAM-flag-level unit tests of SND_TONE_IS_SE
# itself; this is the end-to-end confirmation via the real SOUND_* entry
# points.
SND_TONE_IS_SE = sym["SND_TONE_IS_SE"]
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_POD_FIRE"])  # sets SND_TONE_TIMER=15, SND_TONE_IS_SE=1
call_routine(cpu, sym["SOUND_SHOT"])       # SE still decaying -> dropped, not overwritten
check("a shot fired while an SE (POD_FIRE) is still decaying is dropped, not overwritten",
      cpu.rd(SND_TONE_TIMER) == 15)
check("SND_TONE_IS_SE stays set (still the SE's decay, not the shot's)",
      cpu.rd(SND_TONE_IS_SE) == 1)

# once the SE's timer has fully decayed to 0, a subsequent shot goes
# through normally (and reclaims the timer as "not SE" for itself).
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_POD_HIT"])  # sets SND_TONE_TIMER=10, SND_TONE_IS_SE=1
cpu.wr(SND_TONE_TIMER, 0)  # simulate full decay (SOUND_UPDATE ticking it down to 0)
call_routine(cpu, sym["SOUND_SHOT"])
check("a shot fired after the SE has fully decayed (timer==0) fires normally",
      cpu.rd(SND_TONE_TIMER) == 12)
check("SND_TONE_IS_SE is cleared once the shot successfully claims the timer",
      cpu.rd(SND_TONE_IS_SE) == 0)

# 実機フィードバック対応("SEがほぼ鳴らずショット音が残る"): 実バグの
# 回帰ガード。SOUND_BARRIER_HIT(SND_BARRIER_DUTY_TIMERで管理、SOUND_
# UPDATEで最優先のSE)はSOUND_SHOT/POD_HIT/POD_FIREと全く同じチャンネル
# Aトーン周期レジスタ(R0/R1)を書くが、独立したタイマー(SND_TONE_TIMER
# ではない)のため当初のSND_TONE_IS_SEチェックだけでは検出できなかった -
# バリアヒットの減衰中でもショット要求がR0/R1を横取りして上書きして
# しまい、SOUND_UPDATEは変わらずバリアの音量エンベロープ(最優先)を
# 出力し続けるため「バリアのリズムでショットの音程が鳴る」という壊れた
# 合成音になっていた。SOUND_SHOTがSND_BARRIER_DUTY_TIMERも見るよう
# 修正済み - ここではPSG_ADDR=0/1(R0/R1、トーン周期)がバリアヒット後の
# ショット要求で一切書き換わらないことを直接確認する。
SND_BARRIER_DUTY_TIMER_SYM = sym["SND_BARRIER_DUTY_TIMER"]
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_BARRIER_HIT"])  # R0=132,R1=3 (deep low pitch), SND_BARRIER_DUTY_TIMER=8
psg_before = dict(cpu.psg_regs)
call_routine(cpu, sym["SOUND_SHOT"])  # must be dropped entirely while barrier SE is still decaying
check("a shot fired while SOUND_BARRIER_HIT (top-priority SE) is still decaying makes ZERO PSG "
      "writes - barrier's own tone period (R0/R1) is never clobbered",
      cpu.psg_regs == psg_before)
check("SND_TONE_TIMER stays untouched (0) - the shot request never reached SS_FIRE",
      cpu.rd(SND_TONE_TIMER) == 0)
check("SND_BARRIER_DUTY_TIMER itself is untouched by the dropped shot request",
      cpu.rd(SND_BARRIER_DUTY_TIMER_SYM) == 8)

# once the barrier SE has fully decayed, a shot goes through normally again.
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_BARRIER_HIT"])
cpu.wr(SND_BARRIER_DUTY_TIMER_SYM, 0)  # simulate full decay
call_routine(cpu, sym["SOUND_SHOT"])
check("a shot fired after SOUND_BARRIER_HIT has fully decayed (timer==0) fires normally",
      cpu.rd(SND_TONE_TIMER) == 12)
exp_lo, exp_hi = 30, 0  # SOUND_SHOT's own tone period constants
check("...and correctly reclaims R0/R1 with the shot's own pitch",
      (cpu.psg_regs.get(0), cpu.psg_regs.get(1)) == (exp_lo, exp_hi))

# ---------------------------------------------------------------------
# 4: 3-way channel-A R8 priority (SND_BARRIER_DUTY_TIMER > SND_TONE_
# TIMER > SND_TIMER) when more than one envelope is simultaneously
# active - whichever wins the R8 write is the ONLY one SOUND_UPDATE
# touches that frame (same "freeze the masked one(s), don't corrupt
# state" precedent the pre-migration SOUND_UPDATE_C already had for
# SND_TIMER_C while SND_C_DUTY_TIMER/SOUND_BARRIER_HIT was active -
# see that routine's own old comment).
# ---------------------------------------------------------------------
cpu = fresh_cpu()
call_routine(cpu, sym["SOUND_DESTROY"])        # SND_TIMER=15 (lowest priority)
call_routine(cpu, sym["SOUND_SHOT"])            # SND_TONE_TIMER=12 (mid priority)
call_routine(cpu, sym["SOUND_BARRIER_HIT"])     # SND_BARRIER_DUTY_TIMER=8 (highest)
for frame in range(3):
    cpu.wr(TICK, frame)
    call_routine(cpu, sym["SOUND_UPDATE"])
check("lower-priority envelopes are frozen (not decremented) while masked - SND_TIMER "
      "(noise, lowest priority) stays at its own peak",
      cpu.rd(SND_TIMER) == 15)
check("lower-priority envelopes are frozen (not decremented) while masked - SND_TONE_TIMER "
      "(mid priority) stays at its own peak",
      cpu.rd(SND_TONE_TIMER) == 12)
check("all 3 envelopes decay independently while masked - SND_BARRIER_DUTY_TIMER (highest, "
      "actually reaching R8 each of these 3 frames)",
      cpu.rd(SND_BARRIER_DUTY_TIMER) == 5)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
