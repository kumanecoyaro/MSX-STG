"""tools/gameover_bank/gameover_bank.asm(2026-09-07新設、Stage2の
TANK_LIFE枯渇時の死亡演出+"MISSION FAILED"表示専用バンク)の単体検証。

standalone(このファイル単体、window Aのみの16KBバンク)としてアセンブル
し、フォントの実バイトパターン・メッセージコード列・自機爆発演出の
描画ロジックを直接検証する。実際のバンク切替統合(combined_test.asm
のTRIGGER_GAME_OVERからここへ、ここからtitleへ)はverify_comb.py側の
役割 - ここではこのファイル単体のロジックのみを見る。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
from mini_z80asm import Assembler
from z80emu import Z80
import pixel_font_8x8

with open(os.path.join(REPO, "tools", "gameover_bank", "gameover_bank.asm"), encoding="utf-8") as f:
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


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


check("assembles standalone within a single 16KB window-A bank (4000h-7FFFh)",
      max(out) <= 0x7FFF and min(out) >= 0x4000)

# ---- font glyph bytes: relocated to code96-103+144-146 (group12/18) - ----
# ---- same "boss-only, safe after terrain's own code0-93" reasoning as ----
# ---- ending_text_gen.py's GFEnding font, NOT the original code0-10    ----
# ---- that clobbered the live terrain (found via self-rendering, see   ----
# ---- this file's own INIT comment).                                  ----
FONT_CHARS = ["M", "I", "S", "O", "N", " ", "F", "A", "L", "E", "D"]
FONT_CODES = [96, 97, 98, 99, 100, 101, 102, 103, 144, 145, 146]
z = fresh()
z.pc = sym["INIT"]
run_until_pc(z, sym["GO_BLINK_LOOP"])
font_ok = True
for ch, code in zip(FONT_CHARS, FONT_CODES):
    expected = pixel_font_8x8.glyph_bytes(ch)
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != expected:
        font_ok = False
check("MISSION FAILED font glyphs loaded byte-correct at code96-103+144-146, "
      "matching tools/pixel_font_8x8.py", font_ok)
check("group12 (codes96-103) color patched to white/black (0F1h)", z.vram[0x200C] == 0xF1)
check("group18 (codes144-151) color patched to white/black (0F1h)", z.vram[0x2012] == 0xF1)

# ---- GAMEOVER2_MSG content: "MISSION FAILED" using the relocated codes ----
def read_msg(addr, length):
    return [mem0[addr + i] for i in range(length)]

GAMEOVER2_MSG = sym["GAMEOVER2_MSG"]
GAMEOVER2_MSG_LEN = sym["GAMEOVER2_MSG_LEN"]
expected_msg = [96, 97, 98, 98, 97, 99, 100, 101, 102, 103, 97, 144, 145, 146]
check("GAMEOVER2_MSG = 'MISSION FAILED' (14 bytes) using the relocated codes",
      read_msg(GAMEOVER2_MSG, GAMEOVER2_MSG_LEN) == expected_msg)

# ---- message drawn at row12/col9 (matches Stage1's own DRAW_GAMEOVER_TEXT ----
# ---- position exactly - same 14-byte-centered convention) ----
z = fresh()
for i in range(768):
    z.vram[0x1800 + i] = 0x33
z.pc = sym["INIT"]
run_until_pc(z, sym["GO_WAIT_LOOP"], max_instr=5_000_000)
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAMEOVER2_MSG_LEN]
check("MISSION FAILED text is drawn at row12/col9 by the time GO_WAIT_LOOP is reached",
      msg_region == expected_msg)

# ---- explosion drawn at the tank's last known position (4 corners, ----
# ---- reusing its own hw sprite slots 0-3 - no new ATTRIBUTE slot    ----
# ---- allocation, since the tank itself is never drawn again after   ----
# ---- this point).                                                   ----
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
PAT_EXPLOSION = sym["PAT_EXPLOSION"]
SPR_WHITE_COLOR = sym["SPR_WHITE_COLOR"]
SPR_LIGHTRED_COLOR = sym["SPR_LIGHTRED_COLOR"]


def call_draw_explosion(xjit, yjit, color_sel, tank_x=50, tank_y=80):
    """(2026-09-07、実機フィードバック対応: 4隅を同位置に固定表示する
    だけだったのを直したため) GO_DRAW_EXPLOSIONはD=Xジッター/E=Yジッター/
    C=色選択(0=白、非0=ライトレッド)を入力に取るようになった。"""
    z = fresh()
    z.wr(TANK_X, tank_x)
    z.wr(TANK_Y_CUR, tank_y)
    z.d = xjit & 0xFF
    z.e = yjit & 0xFF
    z.c = color_sel
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = sym["GO_DRAW_EXPLOSION"]
    run_until_pc(z, 0x0000, 300000)
    return [z.vram[0x1B00 + i] for i in range(16)]


attrs = call_draw_explosion(0, 0, 0)
expected_attrs = [
    80, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
    80, 66, PAT_EXPLOSION, SPR_WHITE_COLOR,
    96, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
    96, 66, PAT_EXPLOSION, SPR_WHITE_COLOR,
]
check("GO_DRAW_EXPLOSION (no jitter, color=0/white) places PAT_EXPLOSION at all 4 "
      "tank-body corners (+0/+16 offsets, matching UPDATE_TANK_SPRITES' own convention)",
      attrs == expected_attrs)

attrs_red = call_draw_explosion(0, 0, 1)
check("GO_DRAW_EXPLOSION with color select=1 draws all 4 corners in SPR_LIGHTRED_COLOR "
      "(non-zero color selector -> light red, matching src/CYBER SHMUP.asm's own "
      "PEUA_INSTANCES white/light-red parity strobe)",
      attrs_red == [
          80, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          80, 66, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          96, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          96, 66, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
      ])

# (2026-09-07、実機フィードバック対応"一度4つほどエフェクトが出るが
# その状態で停止してて"): 毎回同じ位置に描くだけだと"止まって見える"と
# 報告されたため、呼び出し元から渡されたジッター量を全4隅へ均等に
# 加算するようになった - ここではジッターがそのまま座標へ反映される
# ことを直接検証する(正のオフセット・負のオフセットの両方)。
attrs_jit_pos = call_draw_explosion(5, 3, 0)
check("GO_DRAW_EXPLOSION applies a positive X/Y jitter to all 4 corners uniformly",
      attrs_jit_pos == [
          83, 55, PAT_EXPLOSION, SPR_WHITE_COLOR,
          83, 71, PAT_EXPLOSION, SPR_WHITE_COLOR,
          99, 55, PAT_EXPLOSION, SPR_WHITE_COLOR,
          99, 71, PAT_EXPLOSION, SPR_WHITE_COLOR,
      ])

attrs_jit_neg = call_draw_explosion(-8 & 0xFF, -8 & 0xFF, 0)
check("GO_DRAW_EXPLOSION applies a negative (two's-complement) X/Y jitter to all 4 "
      "corners uniformly, matching Stage1's own -8..+7 PEUA_TRY_SPAWN jitter range",
      attrs_jit_neg == [
          72, 42, PAT_EXPLOSION, SPR_WHITE_COLOR,
          72, 58, PAT_EXPLOSION, SPR_WHITE_COLOR,
          88, 42, PAT_EXPLOSION, SPR_WHITE_COLOR,
          88, 58, PAT_EXPLOSION, SPR_WHITE_COLOR,
      ])

# ---- GO_BLINK_LOOP: seeds GO_RNG from TANK_X, then jitters/alternates ----
# ---- color across its own 10 iterations - confirm at least 2 distinct ----
# ---- (jitter, color) combinations actually get drawn (i.e. it isn't    ----
# ---- silently drawing the exact same frame 10 times over, the root     ----
# ---- cause of the original bug report).                                ----
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.pc = sym["INIT"]
seen_frames = []
GO_DRAW_EXPLOSION = sym["GO_DRAW_EXPLOSION"]
GO_BLINK_LOOP = sym["GO_BLINK_LOOP"]
DJNZ_BLINK_TARGET = sym["GO_WAIT_LOOP"]
steps = 0
while z.pc != DJNZ_BLINK_TARGET and steps < 3_000_000:
    if z.pc == GO_DRAW_EXPLOSION:
        seen_frames.append((z.d, z.e, z.c))
    z.step()
    steps += 1
check("GO_BLINK_LOOP actually calls GO_DRAW_EXPLOSION 11 times (10 blinks + the final "
      "still frame) before reaching GO_WAIT_LOOP",
      len(seen_frames) == 11)
check("GO_BLINK_LOOP's own 10 blinks are NOT all identical (jitter+color actually vary "
      "call to call) - this is the direct regression guard for \"一度4つほどエフェクトが"
      "出るがその状態で停止してて\"",
      len(set(seen_frames[:10])) > 1)
check("GO_BLINK_LOOP's final call (the still frame after DJNZ exits) uses no jitter and "
      "color=0 (white) - a clean neutral final pose",
      seen_frames[10] == (0, 0, 0))

# ---- "自機爆発はサウンドも欲しい"(2026-09-07、実機フィードバック対応): ----
# ---- GO_PLAY_BOOM_SOUND arms noise channel A (same R6/R7 values as     ----
# ---- src/CYBER SHMUP.asm's own SOUND_DESTROY) then manually decays R8  ----
# ---- from 15 down to 0 over 16 steps (no per-frame SOUND_UPDATE to     ----
# ---- rely on in this standalone routine).                              ----
MIXER_NOISE_A = sym["MIXER_NOISE_A"]
BOOM_NOISE_PERIOD = sym["BOOM_NOISE_PERIOD"]
z = fresh()
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
z.pc = sym["GO_PLAY_BOOM_SOUND"]
r8_writes = []
GO_BOOM_DECAY_LOOP = sym["GO_BOOM_DECAY_LOOP"]
steps = 0
_prev_pc = None
while z.pc != 0x0000 and steps < 2_000_000:
    if z.pc == GO_BOOM_DECAY_LOOP and _prev_pc != GO_BOOM_DECAY_LOOP:
        r8_writes.append(z.c)
    _prev_pc = z.pc
    z.step()
    steps += 1
check("GO_PLAY_BOOM_SOUND selects PSG R7 (mixer) = MIXER_NOISE_A (noise channel A on, "
      "tone B/C stay enabled for BGM - matches Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(7) == MIXER_NOISE_A)
check("GO_PLAY_BOOM_SOUND sets PSG R6 (noise period) = BOOM_NOISE_PERIOD (20, same as "
      "Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(6) == BOOM_NOISE_PERIOD)
check("GO_PLAY_BOOM_SOUND's decay loop steps R8 (channel A volume) through all 16 values "
      "15 down to 0, ending fully silent",
      r8_writes == list(range(15, -1, -1)))
check("GO_PLAY_BOOM_SOUND leaves PSG R8 at 0 (silent) once the decay finishes",
      z.psg_regs.get(8) == 0)

z2 = fresh()
z2.vram[0x1B00:0x1B10] = bytes([1] * 16)
z2.sp = 0xF000
z2.wr(0xF000, 0x00); z2.wr(0xF001, 0x00)
z2.pc = sym["GO_HIDE_EXPLOSION"]
run_until_pc(z2, 0x0000, 300000)
hide_attrs = [z2.vram[0x1B00 + i] for i in range(16)]
check("GO_HIDE_EXPLOSION hides all 4 slots (Y=209)",
      hide_attrs == [209, 0, 0, 0] * 4)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
