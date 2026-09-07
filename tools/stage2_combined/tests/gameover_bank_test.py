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
EXPLOSION_COLOR = sym["EXPLOSION_COLOR"]
z = fresh()
z.wr(TANK_X, 50)
z.wr(TANK_Y_CUR, 80)
call_routine_addr = sym["GO_DRAW_EXPLOSION"]
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
z.pc = call_routine_addr
run_until_pc(z, 0x0000, 300000)
attrs = [z.vram[0x1B00 + i] for i in range(16)]
expected_attrs = [
    80, 50, PAT_EXPLOSION, EXPLOSION_COLOR,
    80, 66, PAT_EXPLOSION, EXPLOSION_COLOR,
    96, 50, PAT_EXPLOSION, EXPLOSION_COLOR,
    96, 66, PAT_EXPLOSION, EXPLOSION_COLOR,
]
check("GO_DRAW_EXPLOSION places PAT_EXPLOSION at all 4 tank-body corners "
      "(+0/+16 offsets, matching UPDATE_TANK_SPRITES' own convention)",
      attrs == expected_attrs)

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
