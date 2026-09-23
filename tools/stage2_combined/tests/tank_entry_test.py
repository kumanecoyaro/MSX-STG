"""ステージ2のスタート演出("ステージ2のスタート演出 添付ファイルの右側
8x16はブースターユニット 自機の左側に表示しYのオフセットは7 ブースター
込みで0,64から放物線で落下し地上へ着地 落下中は1と2を1フレ切り替え
着地したらブースター消滅"、"その10倍遅くしろ"、"1フレつったら1フレだろが"、
"本編開始してから落下すんだよ ステージ1もそうしてるだろうが")の検証。

Stage1のSHIP_ENTRY_ACTと同じく、演出中も本編(地形スクロール・TICK/
GAME_TICK・スケジュール)は通常通り進行し、自機の操作系だけが
UPDATE_TANK_ENTRYに差し替わる。1回のstep_frame()=MAINLOOP1周=1フレーム。
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def tick(cpu):
    """1回の呼び出し=MAINLOOP1周=1フレーム。演出中もTICK・地形スクロールは
    進むが、GAME_TICK(スケジュール)は演出終了まで0のまま(敵は出ない)。"""
    step_frame(cpu)


TANK_ENTRY_ACT = sym["TANK_ENTRY_ACT"]
TANK_ENTRY_VY = sym["TANK_ENTRY_VY"]
TANK_ENTRY_GRAV_CTR = sym["TANK_ENTRY_GRAV_CTR"]
TANK_ENTRY_ANIM = sym["TANK_ENTRY_ANIM"]
TANK_ENTRY_SLOW_CTR = sym["TANK_ENTRY_SLOW_CTR"]
TANK_ENTRY_SLOWDOWN = sym["TANK_ENTRY_SLOWDOWN"]
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

# ---- 2. 演出中も本編(TICK・地形スクロール)は進むが、("スタート演出中は
#         Tickはカウントスタートすんな") GAME_TICKは0のまま・敵は出ない ----
cpu2 = fresh_cpu(skip_intro=False)
tick0 = cpu2.rd(TICK)
px0 = cpu2.rd(sym["PXCHAR_T"]) | (cpu2.rd(sym["PXCHAR_T"] + 1) << 8)
for _ in range(50):
    tick(cpu2)
tick1 = cpu2.rd(TICK)
game_tick1 = cpu2.rd(GAME_TICK) | (cpu2.rd(GAME_TICK + 1) << 8)
check("entry still active after 50 frames (test precondition)", cpu2.rd(TANK_ENTRY_ACT) == 1)
check("while TANK_ENTRY_ACT!=0, TICK advances every frame (main loop runs)",
      (tick1 - tick0) & 0xFF == 50)
check("while TANK_ENTRY_ACT!=0, terrain keeps scrolling", (cpu2.rd(sym["PXCHAR_T"]) | (cpu2.rd(sym["PXCHAR_T"] + 1) << 8)) != px0)
check("while TANK_ENTRY_ACT!=0, GAME_TICK stays 0 (schedule clock not started)",
      game_tick1 == 0)

# ---- 3. TANK_X stays frozen for the first TANK_ENTRY_SLOWDOWN-1 simulated
#         frames, then advances by exactly 1 step on the
#         TANK_ENTRY_SLOWDOWN'th ----
cpu3a = fresh_cpu(skip_intro=False)
xs_raw = []
for _ in range(TANK_ENTRY_SLOWDOWN + 2):
    tick(cpu3a)
    xs_raw.append(cpu3a.rd(TANK_X))
check(f"TANK_X stays at TANK_ENTRY_START_X for the first {TANK_ENTRY_SLOWDOWN - 1} simulated "
      "frames (movement gated behind the slowdown counter, not "
      "advancing every frame)", all(v == TANK_ENTRY_START_X for v in xs_raw[:TANK_ENTRY_SLOWDOWN - 1]))
check(f"TANK_X advances by exactly TANK_ENTRY_VX on the {TANK_ENTRY_SLOWDOWN}th "
      "frame (the one real movement step in this window)",
      xs_raw[TANK_ENTRY_SLOWDOWN - 1] == TANK_ENTRY_START_X + TANK_ENTRY_VX and xs_raw[TANK_ENTRY_SLOWDOWN] == TANK_ENTRY_START_X + TANK_ENTRY_VX)

# ---- 4. (2026-09-23follow-up3、"なんで10フレ切り替えなんだよ！そんな
#         指示してねえだろうが 1フレつったら1フレだろが") booster
#         animation toggles every SINGLE frame, completely
#         independent of the 10x movement slowdown ----
cpu3 = fresh_cpu(skip_intro=False)
anims = []
for _ in range(TANK_ENTRY_SLOWDOWN * 3):
    tick(cpu3)
    anims.append(cpu3.rd(TANK_ENTRY_ANIM))
check("TANK_ENTRY_ANIM alternates 0/1/0/1/... every single frame "
      "(\"1フレつったら1フレ\" - independent of the movement slowdown)",
      anims == [(i + 1) % 2 for i in range(TANK_ENTRY_SLOWDOWN * 3)])

# ---- 5. an independent Python simulation of the X/Y motion, frame-for-frame, gating movement behind the same slowdown counter ----
TANK_GROUND_Y = sym["TANK_GROUND_Y"]


def simulate(grounds):
    """grounds[i] = フレームiでUPDATE_TANK_ENTRYが使った地面Y(演出中も
    地形はスクロールするため、着地先は固定値ではなく毎フレームの地面)。"""
    x, y = TANK_ENTRY_START_X, TANK_ENTRY_START_Y
    vy, ctr = 0, 0
    slow_ctr = 0
    xs, ys = [], []
    for g in grounds:
        if y >= g:
            y = g
        slow_ctr += 1
        if slow_ctr >= TANK_ENTRY_SLOWDOWN:
            slow_ctr = 0
            if x < TANK_X_INIT:
                x = min(x + TANK_ENTRY_VX, TANK_X_INIT)
            if y < g:
                ctr += 1
                if ctr >= TANK_ENTRY_GRAVITY_INTERVAL:
                    ctr = 0
                    vy += TANK_ENTRY_GRAVITY
                y = y + vy
                if y >= g:
                    y = g
            else:
                y = g
        xs.append(x)
        ys.append(y)
        if x >= TANK_X_INIT and y >= g:
            break
    return xs, ys

N_TRACE = 450
cpu4 = fresh_cpu(skip_intro=False)
xs_real, ys_real, grounds = [], [], []
for _ in range(N_TRACE):
    tick(cpu4)
    xs_real.append(cpu4.rd(TANK_X))
    ys_real.append(cpu4.rd(TANK_Y_CUR))
    grounds.append(cpu4.rd(TANK_GROUND_Y))
xs_exp, ys_exp = simulate(grounds)
landing_frame = len(xs_exp) - 1
check("TANK_X matches an independent Python parabola simulation frame-"
      "for-frame up to landing (slowdown gate included)", xs_real[:landing_frame + 1] == xs_exp)
check("TANK_Y_CUR matches an independent Python parabola simulation frame-"
      "for-frame up to landing, landing on the LIVE terrain ground Y",
      ys_real[:landing_frame + 1] == ys_exp)
check("landing: TANK_Y_CUR equals that frame's live TANK_GROUND_Y (not a "
      "fixed TANK_Y_BASE - terrain keeps scrolling during the entry)",
      ys_real[landing_frame] == grounds[landing_frame])
check("both axes actually reach their real targets within the traced window "
      "(test's own sanity check, not an ASM assertion)",
      landing_frame < N_TRACE - 5 and xs_exp[landing_frame] == TANK_X_INIT)
check("landing genuinely takes roughly 10x longer in frames "
      "than the pre-slowdown baseline", landing_frame >= 10 * 20)

# ---- 6. ("オフセット無視すんな") ブースターは演出の最初から最後まで常に
#         TANK_X-16 / TANK_Y_CUR+7(めり込み・クランプ無し)、開始時の
#         ブースター込み左端は0 ----
cpu5 = fresh_cpu(skip_intro=False)
offs_ok = True
first_bx = None
while cpu5.rd(TANK_ENTRY_ACT):
    tick(cpu5)
    if not cpu5.rd(TANK_ENTRY_ACT):
        break
    bx = cpu5.rd(BOOSTER_SPRITE_ATTRS + 1); by = cpu5.rd(BOOSTER_SPRITE_ATTRS + 0)
    if first_bx is None:
        first_bx = bx
    if bx != cpu5.rd(TANK_X) - 16 or by != cpu5.rd(TANK_Y_CUR) + BOOSTER_Y_OFFSET:
        offs_ok = False
check("first frame: booster sprite X = 0 (\"ブースター込みで0,64から\")", first_bx == 0)
check("every entry frame: booster X = TANK_X-16 and Y = TANK_Y_CUR+7 exactly "
      "(no clamp, the booster never overlaps the tank)", offs_ok)

# ---- 7. booster position/Y-offset/pattern once TANK_X is comfortably >=16 ----
cpu6 = fresh_cpu(skip_intro=False)
frame6 = 150
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
