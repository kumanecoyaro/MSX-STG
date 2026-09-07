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

# ---- particle-scatter explosion (2026-09-07、実機フィードバック対応 ----
# ---- "もっとエフェクトが飛び散る形に 地味すぎる 自機中心から           ----
# ---- エフェクトが飛びランダムに散る様に"): 旧GO_DRAW_EXPLOSION(4隅を  ----
# ---- 同位置に固定表示する単一ボディ)を、4つの独立した飛び散る          ----
# ---- パーティクルへ置き換えた。                                        ----
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
PAT_EXPLOSION = sym["PAT_EXPLOSION"]
SPR_WHITE_COLOR = sym["SPR_WHITE_COLOR"]
SPR_LIGHTRED_COLOR = sym["SPR_LIGHTRED_COLOR"]
GO_PX = [sym["GO_PX0"], sym["GO_PX1"], sym["GO_PX2"], sym["GO_PX3"]]
GO_PY = [sym["GO_PY0"], sym["GO_PY1"], sym["GO_PY2"], sym["GO_PY3"]]


def call_draw_particles(color_sel, offsets, tank_x=50, tank_y=80):
    """offsets: list of 4 (dx,dy) pairs (signed) to poke into GO_PX/PYn
    before calling GO_DRAW_PARTICLES(C=color_sel)."""
    z = fresh()
    z.wr(TANK_X, tank_x)
    z.wr(TANK_Y_CUR, tank_y)
    for i, (dx, dy) in enumerate(offsets):
        z.wr(GO_PX[i], dx & 0xFF)
        z.wr(GO_PY[i], dy & 0xFF)
    z.c = color_sel
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = sym["GO_DRAW_PARTICLES"]
    run_until_pc(z, 0x0000, 300000)
    return [z.vram[0x1B00 + i] for i in range(16)]


attrs = call_draw_particles(0, [(0, 0), (0, 0), (0, 0), (0, 0)])
expected_attrs = [
    80, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
    80, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
    80, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
    80, 50, PAT_EXPLOSION, SPR_WHITE_COLOR,
]
check("GO_DRAW_PARTICLES with all-zero offsets (color=0/white) places all 4 particles "
      "exactly at TANK_X/TANK_Y_CUR (the player's own center)",
      attrs == expected_attrs)

attrs_red = call_draw_particles(1, [(0, 0), (0, 0), (0, 0), (0, 0)])
check("GO_DRAW_PARTICLES with color select=1 draws all 4 particles in SPR_LIGHTRED_COLOR",
      attrs_red == [
          80, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          80, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          80, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
          80, 50, PAT_EXPLOSION, SPR_LIGHTRED_COLOR,
      ])

# each particle carries its OWN independent (dx,dy) - this is the entire
# point of "自機中心からエフェクトが飛びランダムに散る様に" (flying apart
# in different directions, not one rigid body).
attrs_scattered = call_draw_particles(0, [(-5, -3), (7, -2), (-4, 6), (3, 5)])
check("GO_DRAW_PARTICLES applies each particle's own independent offset "
      "(not the same offset for all 4, unlike the old single-body design)",
      attrs_scattered == [
          80 - 3, 50 - 5, PAT_EXPLOSION, SPR_WHITE_COLOR,
          80 - 2, 50 + 7, PAT_EXPLOSION, SPR_WHITE_COLOR,
          80 + 6, 50 - 4, PAT_EXPLOSION, SPR_WHITE_COLOR,
          80 + 5, 50 + 3, PAT_EXPLOSION, SPR_WHITE_COLOR,
      ])

# ---- GO_ADVANCE_PARTICLES: each particle's accumulator moves in its own ----
# ---- fixed diagonal direction (away from center) every call, plus a     ----
# ---- small jitter - confirm the SIGN of net movement over many calls     ----
# ---- matches each particle's documented outward direction (up-left/     ----
# ---- up-right/down-left/down-right), i.e. they really do fly apart      ----
# ---- rather than just jittering in place.                                ----
def signed(v):
    return v - 256 if v >= 128 else v


z = fresh()
z.wr(TANK_X, 1)  # seeds GO_RNG (INIT does this; here we poke it directly)
z.wr(sym["GO_RNG"], 1)
for addr in GO_PX + GO_PY:
    z.wr(addr, 0)
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
for _ in range(10):
    z.pc = sym["GO_ADVANCE_PARTICLES"]
    run_until_pc(z, 0x0000, 300000)
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
final = [(signed(z.rd(GO_PX[i])), signed(z.rd(GO_PY[i]))) for i in range(4)]
check("particle0 (documented up-left) net-moved left (dx<0) and up (dy<0) after "
      "10 advances", final[0][0] < 0 and final[0][1] < 0)
check("particle1 (documented up-right) net-moved right (dx>0) and up (dy<0) after "
      "10 advances", final[1][0] > 0 and final[1][1] < 0)
check("particle2 (documented down-left) net-moved left (dx<0) and down (dy>0) after "
      "10 advances", final[2][0] < 0 and final[2][1] > 0)
check("particle3 (documented down-right) net-moved right (dx>0) and down (dy>0) after "
      "10 advances", final[3][0] > 0 and final[3][1] > 0)

# ---- GO_BLINK_LOOP: particles must actually be moving frame to frame ----
# ---- (not just jittering in place) - this is the direct regression   ----
# ---- guard for "地味すぎる...もっとエフェクトが飛び散る形に".         ----
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.pc = sym["INIT"]
seen_frames = []
GO_DRAW_PARTICLES = sym["GO_DRAW_PARTICLES"]
GO_HIDE_EXPLOSION = sym["GO_HIDE_EXPLOSION"]
GO_WAIT_LOOP = sym["GO_WAIT_LOOP"]
hide_calls_before_text = 0
steps = 0
while z.pc != GO_WAIT_LOOP and steps < 3_000_000:
    if z.pc == GO_DRAW_PARTICLES:
        seen_frames.append(tuple(z.rd(a) for a in GO_PX + GO_PY))
    if z.pc == GO_HIDE_EXPLOSION:
        hide_calls_before_text += 1
    z.step()
    steps += 1
check("GO_BLINK_LOOP calls GO_DRAW_PARTICLES 10 times (once per blink iteration) "
      "before reaching GO_WAIT_LOOP",
      len(seen_frames) == 10)
check("GO_BLINK_LOOP's 10 draws show genuinely different particle positions each "
      "time (the particles are really flying outward, not stuck jittering in place)",
      len(set(seen_frames)) == 10)
check("the particles' distance from center (sum of |offset|) grows over the "
      "sequence (a real outward flight, not a random walk that stays near 0)",
      sum(abs(signed(v)) for v in seen_frames[-1]) > sum(abs(signed(v)) for v in seen_frames[0]))
# (2026-09-07、実機フィードバック対応"爆発エフェクトが消えずのこったまま
# Mission Failedになってる で爆発エフェクトは消してくれ"): GO_HIDE_
# EXPLOSIONはループの各反復内で毎回呼ばれる(点滅の非表示側)のに加え、
# ループを抜けた直後にも明示的にもう1回呼ばれ、その後で初めてテキストを
# 描画する設計に変更した - 10回(ループ内)+1回(ループ後、テキストより
# 前)=11回になっているはず。
check("GO_HIDE_EXPLOSION is called 11 times before GO_WAIT_LOOP (10 blink-hides + "
      "1 final explicit hide before the MISSION FAILED text is drawn) - the fix for "
      "the explosion sprites being left visible under the text",
      hide_calls_before_text == 11)

# confirm the sprite attribute table is really left in the "all hidden" state at
# the moment GO_WAIT_LOOP (i.e. after the text has already been drawn) is reached -
# this is the literal on-screen check for "爆発エフェクトは消してくれ".
hidden_attrs = [z.vram[0x1B00 + i] for i in range(16)]
check("by the time MISSION FAILED text is on screen (GO_WAIT_LOOP reached), all 4 "
      "explosion particle sprite slots are hidden (Y=209), not left visible under it",
      hidden_attrs == [209, 0, 0, 0] * 4)

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
