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
TANK_ENTRY_ANIM = sym["TANK_ENTRY_ANIM"]
TANK_ENTRY_XFRAC = sym["TANK_ENTRY_XFRAC"]
TANK_ENTRY_YFRAC = sym["TANK_ENTRY_YFRAC"]
TANK_ENTRY_XSUB = sym["TANK_ENTRY_XSUB"]
TANK_ENTRY_GRAVITY_SUB = sym["TANK_ENTRY_GRAVITY_SUB"]
TANK_ENTRY_START_X = sym["TANK_ENTRY_START_X"]
TANK_ENTRY_START_Y = sym["TANK_ENTRY_START_Y"]
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
check("boot: TANK_ENTRY_VY (8.8) starts at 0", cpu.rd(TANK_ENTRY_VY) == 0 and cpu.rd(TANK_ENTRY_VY + 1) == 0)
check("boot: TANK_ENTRY_ANIM starts at 0", cpu.rd(TANK_ENTRY_ANIM) == 0)
check("boot: X/Y fraction bytes start at 0", cpu.rd(TANK_ENTRY_XFRAC) == 0 and cpu.rd(TANK_ENTRY_YFRAC) == 0)

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

# ---- 3. (follow-up10、"落下が荒くて滑らかになってない") 毎フレーム更新:
#         X/Yとも1フレームに最大1pxしか動かない(10フレームごとの跳びが無い) ----
cpu3a = fresh_cpu(skip_intro=False)
xs_raw, ys_raw = [cpu3a.rd(TANK_X)], [cpu3a.rd(TANK_Y_CUR)]
while cpu3a.rd(TANK_ENTRY_ACT):
    tick(cpu3a)
    xs_raw.append(cpu3a.rd(TANK_X)); ys_raw.append(cpu3a.rd(TANK_Y_CUR))
check("smooth: TANK_X never moves more than 1px in a single frame",
      max(abs(xs_raw[i] - xs_raw[i - 1]) for i in range(1, len(xs_raw))) <= 1)
check("smooth: TANK_Y_CUR never moves more than 1px in a single frame during the fall",
      max(abs(ys_raw[i] - ys_raw[i - 1]) for i in range(1, len(ys_raw) - 1)) <= 1)

# ---- 4. (2026-09-23follow-up3、"なんで10フレ切り替えなんだよ！そんな
#         指示してねえだろうが 1フレつったら1フレだろが") booster
#         animation toggles every SINGLE frame, completely
#         independent of the 10x movement slowdown ----
cpu3 = fresh_cpu(skip_intro=False)
anims = []
for _ in range(30):
    tick(cpu3)
    anims.append(cpu3.rd(TANK_ENTRY_ANIM))
pats = []
cpu3 = fresh_cpu(skip_intro=False)
for _ in range(30):
    tick(cpu3)
    pats.append(cpu3.rd(BOOSTER_SPRITE_ATTRS + 2))
exp = [PAT_BOOSTER2 if ((i + 1) & 2) else PAT_BOOSTER1 for i in range(30)]
check("booster frame switches Bunit1/Bunit2 every 2 frames (\"2フレで\"), "
      "independent of the movement slowdown", pats == exp and pats[:6] == [PAT_BOOSTER1, PAT_BOOSTER2, PAT_BOOSTER2, PAT_BOOSTER1, PAT_BOOSTER1, PAT_BOOSTER2])

# ---- 5. an independent Python simulation of the X/Y motion, frame-for-frame, gating movement behind the same slowdown counter ----
TANK_GROUND_Y = sym["TANK_GROUND_Y"]


def simulate(grounds):
    """ASMと同じ8.8固定小数点モデル。grounds[i] = フレームiで使われた地面Y。"""
    x, y = TANK_ENTRY_START_X, TANK_ENTRY_START_Y
    xf, yf, vy = 0, 0, 0
    xs, ys = [], []
    for g in grounds:
        if y >= g:
            y = g
        if x < TANK_X_INIT:
            xf += TANK_ENTRY_XSUB
            if xf >= 256:
                xf -= 256
                x += 1
        if y < g:
            vy = (vy + TANK_ENTRY_GRAVITY_SUB) & 0xFFFF
            yf += vy & 0xFF
            carry = yf >= 256
            yf &= 0xFF
            ny = y + (vy >> 8) + carry
            y = g if (ny > 255 or ny >= g) else ny
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
      "for-frame up to landing (8.8 fixed point)", xs_real[:landing_frame + 1] == xs_exp)
check("TANK_Y_CUR matches an independent Python parabola simulation frame-"
      "for-frame up to landing, landing on the LIVE terrain ground Y",
      ys_real[:landing_frame + 1] == ys_exp)
check("landing: TANK_Y_CUR equals that frame's live TANK_GROUND_Y (not a "
      "fixed TANK_Y_BASE - terrain keeps scrolling during the entry)",
      ys_real[landing_frame] == grounds[landing_frame])
check("both axes actually reach their real targets within the traced window "
      "(test's own sanity check, not an ASM assertion)",
      landing_frame < N_TRACE - 5 and xs_exp[landing_frame] == TANK_X_INIT)
check("landing takes ~220 frames (\"10倍遅く\" duration kept) and X/Y arrive "
      "together (no sliding on the ground)", 200 <= landing_frame <= 240)

# ---- 6. ("オフセット無視すんな") ブースターは演出の最初から最後まで常に
#         TANK_X-15 / TANK_Y_CUR+7(めり込み・クランプ無し)、開始時の
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
    if bx != cpu5.rd(TANK_X) - 15 or by != cpu5.rd(TANK_Y_CUR) + BOOSTER_Y_OFFSET:
        offs_ok = False
check("first frame: booster sprite X = 1 (\"ブースター込みで0,64から\"、2026-09-25の\"1px右に\"で0→1)", first_bx == 1)
check("every entry frame: booster X = TANK_X-15 and Y = TANK_Y_CUR+7 exactly "
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
expected_pat = PAT_BOOSTER2 if (anim & 2) else PAT_BOOSTER1
check("booster ATTRIBUTE X = TANK_X-15 (so the real art, which only occupies "
      "the right half of the 16x16 sprite, lands just left of the tank)",
      booster_x2 == tank_x - 15)
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
src_frame = BOOSTER2_SPRITE if (anim & 2) else BOOSTER1_SPRITE
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

# ---- ("右が渡したデータだぞ") 両フレームの32byteが添付JSON(16x16)を
#      そのまま4quadrant変換したものと一致(左下の炎を含む) ----
BUNIT = {
    "BOOSTER1_SPRITE": [0]*8 + [0]*8 + [0x7F,0x7F,0x00,0x7F,0x63,0x6B,0x63,0x3F] + [0x5F,0x6F,0x37,0x1B,0,0,0,0],
    "BOOSTER2_SPRITE": [0]*8 + [0x00,0x01,0x07,0x01,0x03,0x06,0x01,0x01] + [0x7F,0x7F,0x00,0x7F,0x63,0x6B,0x63,0x3F] + [0x5F,0x6F,0x37,0x9B,0xC0,0xF0,0xA0,0x20],
}
for name, data in BUNIT.items():
    check(f"{name} matches Bunit JSON 16x16 exactly (incl. left-bottom flame)",
          [out[sym[name] + i] & 0xFF for i in range(32)] == data)

# ---- (follow-up11、"落下中の自機はジャンプ時のものに") ----
PAT_TANKFGAP = sym["PAT_TANKFGAP"]; PAT_TANKF = sym["PAT_TANKF"]
TANK_SPR_BASE_SLOT = sym.get("TANK_SPR_BASE_SLOT", 0)
cj = fresh_cpu(skip_intro=False)
pose_ok = True
while True:
    tick(cj)
    if not cj.rd(TANK_ENTRY_ACT):
        break
    if cj.rd(sym["CUR_POSE_PAT"]) != PAT_TANKFGAP or cj.vram[SPRATR + TANK_SPR_BASE_SLOT * 4 + 2] != PAT_TANKFGAP:
        pose_ok = False
check("during the fall the tank uses the jump pose PAT_TANKFGAP (RAM and VRAM slot0)", pose_ok)
check("on landing the tank returns to the normal pose PAT_TANKF",
      cj.rd(sym["CUR_POSE_PAT"]) == PAT_TANKF and cj.vram[SPRATR + TANK_SPR_BASE_SLOT * 4 + 2] == PAT_TANKF)

# ---- (2026-09-25、"ステージ2のスタート演出にステージ1自機がRow1左から
#      飛び去る演出を追加 飛び去りはステージ2自機落下と同時にスタート
#      データはバリアなしノーマルのもの") ----
import re as _re
_s1 = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "src", "CYBER SHMUP.asm"), encoding="utf-8").read()
def _s1_pat(label):
    m = _re.search(r"^" + label + r":\s*\n((?:\s*DB[^\n]*\n){4})", _s1, _re.M)
    vals = []
    for line in m.group(1).splitlines():
        for v in line.split(";")[0].replace("DB", "").split(","):
            vals.append(int(v.strip().rstrip("hH"), 16))
    return vals
s1_body = _s1_pat("SHIP_MID_PATTERN")
s1_acc = _s1_pat("ACCENT_MID_PATTERN")
check("S1SHIP_BODY_SPRITE == Stage1 SHIP_MID_PATTERN byte-for-byte",
      [out[sym["S1SHIP_BODY_SPRITE"] + i] & 0xFF for i in range(32)] == s1_body)
# Stage1はアクセントを本体X+8に描く -> 8px右へずらした形と一致すること
acc_shift = [0] * 32
for r in range(16):
    left = s1_acc[r] if r < 8 else s1_acc[8 + (r - 8)]
    # accentの左半分(TL/BL)の各行 -> 本体基準では右半分(TR/BR)
    acc_shift[16 + r] = left
    assert (s1_acc[16 + r] if r < 8 else s1_acc[24 + r - 8]) == 0  # 元の右半分は空白
check("S1SHIP_ACCENT_SPRITE == Stage1 ACCENT_MID_PATTERN shifted 8px right (Stage1 draws it at body X+8)",
      [out[sym["S1SHIP_ACCENT_SPRITE"] + i] & 0xFF for i in range(32)] == acc_shift)
cs = fresh_cpu(skip_intro=False)
PB = sym["PAT_S1SHIP_BODY"]; PA = sym["PAT_S1SHIP_ACCENT"]
check("boot: Stage1 ship body/accent patterns are in sprite VRAM",
      list(cs.vram[SPRPAT + PB * 8:SPRPAT + PB * 8 + 32]) == s1_body
      and list(cs.vram[SPRPAT + PA * 8:SPRPAT + PA * 8 + 32]) == acc_shift)
# 期待X: ステージ1 PFA_MOVINGの加速カーブ(X=0から、落下1フレーム目がX=0)
exp_x = [0]; d = 0; x = 0
while True:
    sp = 8 if d >= 32 else 1 + d // 8
    d += sp; x += sp
    if x >= 248:
        break
    exp_x.append(x)
slot = sym["S1SHIP_SPR_BASE_SLOT"]
fly_ok = True; hide_ok = True; frames = 0
while True:
    tick(cs)
    if not cs.rd(TANK_ENTRY_ACT):
        break
    frames += 1
    a = [cs.vram[SPRATR + slot * 4 + i] for i in range(8)]
    WAIT = sym["S1SHIP_FLY_WAIT"]
    ex = 0 if frames <= WAIT else (exp_x[frames - WAIT] if frames - WAIT < len(exp_x) else None)
    if ex is not None:
        if a != [7, ex, PA, 15, 7, ex, PB, 8]:
            fly_ok = False
    elif a[0] != 209 or a[4] != 209:
        hide_ok = False
check("Stage1 ship: slot8(accent white)/slot9(body red) at Y=7 (Row1), held at X=0 for the first S1SHIP_FLY_WAIT(60) fall frames, then X follows Stage1's flyaway accel curve (frame61 = X1)",
      fly_ok and sym["S1SHIP_FLY_WAIT"] == 60 and frames > 60 + len(exp_x))
check("Stage1 ship: hidden (Y=209) once past X>=248, for the rest of the fall", hide_ok)
check("after entry: PAT_TANKUP (incl. codes 24-31 borrowed by the Stage1 ship) restored",
      list(cs.vram[SPRPAT + PAT_TANKUP * 8:SPRPAT + PAT_TANKUP * 8 + 128]) == [out[sym["TANK_TANKUP_TL"] + i] & 0xFF for i in range(128)])

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
