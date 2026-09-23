"""ステージ2のスタート演出("ステージ2のスタート演出 添付ファイルの右側
8x16はブースターユニット 自機の左側に表示しYのオフセットは7 ブースター
込みで0,64から放物線で落下し地上へ着地 落下中は1と2を1フレ切り替え
着地したらブースター消滅"、続けて"そんな一瞬で着地しても何も確認できん
だろうが その10倍遅くしろ"、続けて"なんで10フレ切り替えなんだよ！そんな
指示してねえだろうが 1フレつったら1フレだろが"、続けて"しかも同じ
じゃねえかよ 40フレのままだろうが")の検証。

**重要**: このROMはHALT/vsync同期を一切使わないfree-running設計のため、
落下演出の実時間ペーシングは本物のVBlank(VBLANK_COUNT、H.TIMI駆動、
GFEnding等と同じ考え方)基準で実装されている。z80emu.pyは実機の割り込み
を一切発火しない(このプロジェクト全体で繰り返し確認済みの既知の限界)
ため、このテストは`banked_helpers.sim_vblank()`(本来H.TIMIが毎VBlank
呼ぶBGM_TICKを明示的に1回呼ぶ)を`step_frame()`と対にして呼ぶことで
「本物のVBlankが1回発生した」を1回ずつシミュレートする
(ending_sequence_test.py等の既存の作法と同じ)。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, step_frame, sim_vblank

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def tick(cpu):
    """1回の呼び出し=本物のVBlank1回分(sim_vblank)+MAINLOOP1周分
    (step_frame)。新設計ではこれが「実1フレーム」に対応する。"""
    sim_vblank(cpu)
    step_frame(cpu)


TANK_ENTRY_ACT = sym["TANK_ENTRY_ACT"]
TANK_ENTRY_VY = sym["TANK_ENTRY_VY"]
TANK_ENTRY_GRAV_CTR = sym["TANK_ENTRY_GRAV_CTR"]
TANK_ENTRY_ANIM = sym["TANK_ENTRY_ANIM"]
TANK_ENTRY_SLOW_CTR = sym["TANK_ENTRY_SLOW_CTR"]
TANK_ENTRY_SLOWDOWN = sym["TANK_ENTRY_SLOWDOWN"]
TANK_ENTRY_LAST_VBLANK = sym["TANK_ENTRY_LAST_VBLANK"]
TANK_ENTRY_START_X = sym["TANK_ENTRY_START_X"]
TANK_ENTRY_START_Y = sym["TANK_ENTRY_START_Y"]
TANK_ENTRY_GRAVITY = sym["TANK_ENTRY_GRAVITY"]
TANK_ENTRY_GRAVITY_INTERVAL = sym["TANK_ENTRY_GRAVITY_INTERVAL"]
TANK_ENTRY_VX = sym["TANK_ENTRY_VX"]
BOOSTER_Y_OFFSET = sym["BOOSTER_Y_OFFSET"]
BOOSTER_WIDTH = sym["BOOSTER_WIDTH"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_X_INIT = sym["TANK_X_INIT"]
TANK_Y_BASE = sym["TANK_Y_BASE"]
TICK = sym["TICK"]
GAME_TICK = sym["GAME_TICK"]
VBLANK_COUNT = sym["VBLANK_COUNT"]
BOOSTER_SPRITE_ATTRS = sym["BOOSTER_SPRITE_ATTRS"]
BOOSTER_SPR_BASE_SLOT = sym["BOOSTER_SPR_BASE_SLOT"]
SPRATR = sym["SPRATR"]
SPRPAT = sym["SPRPAT"]
PAT_BOOSTER1 = sym["PAT_BOOSTER1"]
PAT_BOOSTER2 = sym["PAT_BOOSTER2"]
PAT_TANKUP = sym["PAT_TANKUP"]
BOOSTER_COLOR = sym["BOOSTER_COLOR"]
BOOSTER1_SPRITE = sym["BOOSTER1_SPRITE"]
BOOSTER2_SPRITE = sym["BOOSTER2_SPRITE"]

# ---- 1. boot: entry armed, tank at the start position ----
cpu = fresh_cpu(skip_intro=False)
check("boot: TANK_ENTRY_ACT=1 (armed)", cpu.rd(TANK_ENTRY_ACT) == 1)
check("boot: TANK_X=TANK_ENTRY_START_X(0)", cpu.rd(TANK_X) == TANK_ENTRY_START_X)
check("boot: TANK_Y_CUR=TANK_ENTRY_START_Y(64)", cpu.rd(TANK_Y_CUR) == TANK_ENTRY_START_Y)
check("boot: TANK_ENTRY_VY starts at 0", cpu.rd(TANK_ENTRY_VY) == 0)
check("boot: TANK_ENTRY_GRAV_CTR starts at 0", cpu.rd(TANK_ENTRY_GRAV_CTR) == 0)
check("boot: TANK_ENTRY_ANIM starts at 0", cpu.rd(TANK_ENTRY_ANIM) == 0)
check("boot: TANK_ENTRY_SLOW_CTR starts at 0", cpu.rd(TANK_ENTRY_SLOW_CTR) == 0)
check("boot: TANK_ENTRY_LAST_VBLANK starts at 0", cpu.rd(TANK_ENTRY_LAST_VBLANK) == 0)

# ---- 2. while falling, TICK/GAME_TICK stay completely frozen (the
#         MAINLOOP-top gate skips everything else, including the
#         terrain-scroll/GAME_TICK-advance block) - true regardless of
#         whether any simulated vblank ever happens, since this gate is
#         keyed purely on TANK_ENTRY_ACT ----
cpu2 = fresh_cpu(skip_intro=False)
tick0 = cpu2.rd(TICK)
game_tick0 = cpu2.rd(GAME_TICK) | (cpu2.rd(GAME_TICK + 1) << 8)
for _ in range(50):
    tick(cpu2)
tick1 = cpu2.rd(TICK)
game_tick1 = cpu2.rd(GAME_TICK) | (cpu2.rd(GAME_TICK + 1) << 8)
check("while TANK_ENTRY_ACT!=0, TICK never advances (whole MAINLOOP body "
      "besides UPDATE_TANK_ENTRY is skipped)", tick1 == tick0)
check("while TANK_ENTRY_ACT!=0, GAME_TICK never advances either (no spawn "
      "scheduler activity is possible during the fall)", game_tick1 == game_tick0)

# ---- 2b. (2026-09-23follow-up4、"しかも同じじゃねえかよ 40フレのまま
#          だろうが") without any real vblank ever happening (exactly what
#          z80emu.py's own step_frame() alone gives you - no interrupts
#          simulated at all), the fall must NOT progress even 1px - this
#          is the direct regression guard for the bug the user's own
#          real-hardware/real-time observation caught (the old call-count-
#          based throttle "progressed" even with zero real elapsed time) ----
cpu2b = fresh_cpu(skip_intro=False)
for _ in range(500):
    step_frame(cpu2b)  # no sim_vblank() - pure busy-wait, no real time passes
check("with zero real vblanks simulated (matching what pure CPU-instruction "
      "stepping alone provides), TANK_X does not move at all - progress is "
      "driven by real elapsed vblank time, not by how many times MAINLOOP "
      "happens to spin", cpu2b.rd(TANK_X) == TANK_ENTRY_START_X)
check("...same for TANK_Y_CUR", cpu2b.rd(TANK_Y_CUR) == TANK_ENTRY_START_Y)
check("...same for TANK_ENTRY_ANIM (no real frame has elapsed yet)",
      cpu2b.rd(TANK_ENTRY_ANIM) == 0)

# ---- 3. TANK_X stays frozen for the first TANK_ENTRY_SLOWDOWN-1 simulated
#         real vblanks, then advances by exactly 1 step on the
#         TANK_ENTRY_SLOWDOWN'th ----
cpu3a = fresh_cpu(skip_intro=False)
xs_raw = []
for _ in range(TANK_ENTRY_SLOWDOWN + 2):
    tick(cpu3a)
    xs_raw.append(cpu3a.rd(TANK_X))
check(f"TANK_X stays at 0 for the first {TANK_ENTRY_SLOWDOWN - 1} simulated "
      "real vblanks (movement gated behind the slowdown counter, not "
      "advancing every vblank)", all(v == 0 for v in xs_raw[:TANK_ENTRY_SLOWDOWN - 1]))
check(f"TANK_X advances by exactly TANK_ENTRY_VX on the {TANK_ENTRY_SLOWDOWN}th "
      "simulated real vblank (the one real movement step in this window)",
      xs_raw[TANK_ENTRY_SLOWDOWN - 1] == TANK_ENTRY_VX and xs_raw[TANK_ENTRY_SLOWDOWN] == TANK_ENTRY_VX)

# ---- 4. (2026-09-23follow-up3、"なんで10フレ切り替えなんだよ！そんな
#         指示してねえだろうが 1フレつったら1フレだろが") booster
#         animation toggles every SINGLE simulated real vblank, completely
#         independent of the 10x movement slowdown ----
cpu3 = fresh_cpu(skip_intro=False)
anims = []
for _ in range(TANK_ENTRY_SLOWDOWN * 3):
    tick(cpu3)
    anims.append(cpu3.rd(TANK_ENTRY_ANIM))
check("TANK_ENTRY_ANIM alternates 0/1/0/1/... every single real vblank "
      "(\"1フレつったら1フレ\" - independent of the movement slowdown)",
      anims == [(i + 1) % 2 for i in range(TANK_ENTRY_SLOWDOWN * 3)])

# ---- 5. an independent Python simulation of the X/Y motion, real-vblank-
#         for-real-vblank, gating movement behind the same slowdown counter ----
def simulate(n_vblanks):
    x, y = TANK_ENTRY_START_X, TANK_ENTRY_START_Y
    vy, ctr = 0, 0
    slow_ctr = 0
    xs, ys = [], []
    for _ in range(n_vblanks):
        slow_ctr += 1
        if slow_ctr >= TANK_ENTRY_SLOWDOWN:
            slow_ctr = 0
            if x < TANK_X_INIT:
                x = min(x + TANK_ENTRY_VX, TANK_X_INIT)
            if y < TANK_Y_BASE:
                ctr += 1
                if ctr >= TANK_ENTRY_GRAVITY_INTERVAL:
                    ctr = 0
                    vy += TANK_ENTRY_GRAVITY
                y = min(y + vy, TANK_Y_BASE)
        xs.append(x)
        ys.append(y)
    return xs, ys

N_TRACE = 450
cpu4 = fresh_cpu(skip_intro=False)
xs_real, ys_real = [], []
for _ in range(N_TRACE):
    tick(cpu4)
    xs_real.append(cpu4.rd(TANK_X))
    ys_real.append(cpu4.rd(TANK_Y_CUR))
xs_exp, ys_exp = simulate(N_TRACE)
check("TANK_X matches an independent Python parabola simulation real-"
      "vblank-for-real-vblank (slowdown gate included)", xs_real == xs_exp)
check("TANK_Y_CUR matches an independent Python parabola simulation real-"
      "vblank-for-real-vblank (slowdown gate included)", ys_real == ys_exp)

# landing frame: the first simulated real vblank where BOTH axes have
# reached their target
landing_frame = next(i for i in range(N_TRACE) if xs_exp[i] == TANK_X_INIT and ys_exp[i] == TANK_Y_BASE)
check("both axes actually reach their real targets within the traced window "
      "(test's own sanity check, not an ASM assertion)",
      xs_exp[landing_frame] == TANK_X_INIT and ys_exp[landing_frame] == TANK_Y_BASE)
check("landing genuinely takes roughly 10x longer in real vblanks (~400) "
      "than the pre-slowdown baseline (~40)", landing_frame > 300)

# ---- 6. booster X clamps to 0 instead of underflowing while TANK_X<16 ----
cpu5 = fresh_cpu(skip_intro=False)
tick(cpu5)  # 1 real vblank: TANK_X still 0 (movement hasn't stepped yet)
booster_x = cpu5.rd(BOOSTER_SPRITE_ATTRS + 1)
check("early frame (TANK_X < 16): booster X clamps to 0 instead of "
      "underflowing off-screen", booster_x == 0)

# ---- 7. booster position/Y-offset/pattern once TANK_X is comfortably >=16 ----
cpu6 = fresh_cpu(skip_intro=False)
frame6 = next(i for i in range(N_TRACE) if xs_exp[i] >= 16) + 1
for _ in range(frame6):
    tick(cpu6)
tank_x = cpu6.rd(TANK_X)
tank_y = cpu6.rd(TANK_Y_CUR)
assert tank_x >= 16, "test precondition: need TANK_X>=16"
booster_y = cpu6.rd(BOOSTER_SPRITE_ATTRS + 0)
booster_x2 = cpu6.rd(BOOSTER_SPRITE_ATTRS + 1)
booster_pat = cpu6.rd(BOOSTER_SPRITE_ATTRS + 2)
booster_col = cpu6.rd(BOOSTER_SPRITE_ATTRS + 3)
anim = cpu6.rd(TANK_ENTRY_ANIM)
expected_pat = PAT_BOOSTER2 if anim else PAT_BOOSTER1
check("booster ATTRIBUTE X = TANK_X-16 (so the real art, which only occupies "
      "the right half of the 16x16 sprite, lands just left of the tank)",
      booster_x2 == tank_x - 16)
check("booster Y = TANK_Y_CUR + BOOSTER_Y_OFFSET(7)", booster_y == tank_y + BOOSTER_Y_OFFSET)
check("booster pattern code (base of the 4-code TL/BL/TR/BR quad) matches the "
      "current TANK_ENTRY_ANIM frame", booster_pat == expected_pat)
check("booster color is BOOSTER_COLOR (white)", booster_col == BOOSTER_COLOR)

# ---- 7b. the 16x16 sprite is a real hardware 4-consecutive-code quad (this
#          is the actual bug the user's own screenshot caught: an earlier
#          version staged only 1 real code per attribute entry, leaving the
#          other 3 of the mandatory 4-code group full of unrelated garbage
#          from whatever else last owned them) - verify all 4 codes of
#          whichever frame is showing exactly match the source data (TL/BL
#          blank, TR/BL real art), not just the base code's own 8 bytes ----
src_frame = BOOSTER2_SPRITE if anim else BOOSTER1_SPRITE
expected_32 = [out[src_frame + i] & 0xFF for i in range(32)]
vram_32 = list(cpu6.vram[SPRPAT + booster_pat * 8: SPRPAT + booster_pat * 8 + 32])
check("all 4 pattern codes of the currently-showing booster frame (TL/BL/TR/BR, "
      "32 bytes total) match the source data exactly - not just the base code",
      vram_32 == expected_32)

# ---- 8. the booster sprite is actually flushed to hw sprite ATTRIBUTE slot
#         BOOSTER_SPR_BASE_SLOT (not just staged in RAM) ----
vram_attr_y = cpu6.vram[SPRATR + BOOSTER_SPR_BASE_SLOT * 4]
check("VRAM sprite attribute table slot BOOSTER_SPR_BASE_SLOT matches the "
      "staged Y", vram_attr_y == booster_y)

# ---- 9. landing: TANK_ENTRY_ACT drops to 0 exactly on the frame both axes
#         land, the booster sprite is hidden (Y=209) from then on, and
#         PAT_TANKUP's own real "climbing" pose data (borrowed for the
#         booster's 2 frames) is restored byte-for-byte ----
real_tankup = [out[sym["TANK_TANKUP_TL"] + i] & 0xFF for i in range(128)]
cpu7 = fresh_cpu(skip_intro=False)
acts = []
for _ in range(landing_frame + 5):
    tick(cpu7)
    acts.append(cpu7.rd(TANK_ENTRY_ACT))
check(f"TANK_ENTRY_ACT is still 1 the frame before landing, 0 exactly on the "
      f"landing frame (frame {landing_frame + 1})",
      acts[landing_frame - 1] == 1 and acts[landing_frame] == 0)
check("TANK_ENTRY_ACT stays 0 afterward (one-shot, never re-arms)",
      all(v == 0 for v in acts[landing_frame:]))
check("TANK_X sits exactly at TANK_X_INIT after landing", cpu7.rd(TANK_X) == TANK_X_INIT)
check("TANK_Y_CUR sits exactly at TANK_Y_BASE after landing", cpu7.rd(TANK_Y_CUR) == TANK_Y_BASE)
check("booster sprite hidden (Y=209) after landing",
      cpu7.vram[SPRATR + BOOSTER_SPR_BASE_SLOT * 4] == 209)
vram_tankup_after = list(cpu7.vram[SPRPAT + PAT_TANKUP * 8: SPRPAT + PAT_TANKUP * 8 + 128])
check("PAT_TANKUP's real \"climbing\" pose data (temporarily borrowed for the "
      "booster's 2 frames) is restored byte-for-byte after landing, matching "
      "TANK_TANKUP_TL's own real source data exactly",
      vram_tankup_after == real_tankup)

# ---- 10. once landed, normal MAINLOOP processing genuinely resumes (TICK/
#          GAME_TICK advance again) ----
tick_before = cpu7.rd(TICK)
step_frame(cpu7)
tick_after = cpu7.rd(TICK)
check("after landing, TICK advances again (normal MAINLOOP processing "
      "resumed, not stuck)", tick_after != tick_before)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
