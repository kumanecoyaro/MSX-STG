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
run_until_pc(z, sym["GO_EXPLOSION_SEQUENCE"])
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

# (2026-09-07、実機フィードバック対応"Mission Failedの行はブランクブラック
# で埋めてくれ"): row12全体(32セル)がcols0-8/cols23-31含めHUD_ROW_BLANK_
# CODE(黒)で埋まっていること - 旧実装はメッセージの14セル以外は死亡直前の
# 地形・背景がそのまま透けて見えていた(0x33の汚染マーカーが残ってしまう)。
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
check("HUD_ROW_BLANK_CODE matches combined_test.asm's own value (120, group15 "
      "pure-black blank tile)", HUD_ROW_BLANK_CODE == 120)
row12 = nametable[12 * 32: 12 * 32 + 32]
check("row12's left margin (cols0-8, before the message) is blanked to "
      "HUD_ROW_BLANK_CODE, not left showing the pre-death terrain/background",
      row12[0:9] == [HUD_ROW_BLANK_CODE] * 9)
check("row12's right margin (cols23-31, after the message) is blanked to "
      "HUD_ROW_BLANK_CODE, not left showing the pre-death terrain/background",
      row12[23:32] == [HUD_ROW_BLANK_CODE] * 9)
check("no leftover 0x33 poison bytes remain anywhere in row12 (fully "
      "overwritten - blank margins + message, nothing untouched)",
      0x33 not in row12)

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

def signed(v):
    return v - 256 if v >= 128 else v


# ---- Round68 (2026-09-07、実機フィードバック対応その2"爆破処理での
# ---- 爆破スプライトの動きがすごく遅い ボス撃破の様に連続でバンバン
# ---- 飛び散るイメージで ほぼ処理的にはステージ2の敵を倒したときの
# ---- パーティクル爆発 それの複数スプライト版 今はふわ～っと飛び散って
# ---- 気持ち悪い"): GO_ADVANCE_PARTICLES(毎フレーム小さな乱数ジッター
# ---- を蓄積するだけ)を全面撤回し、combined_test.asm自身のEXPLODE_
# ---- DIR_DX/DYと同じ8方位固定ベクトルモデル(GO_PICK_DIR/GO_NEW_BURST/
# ---- GO_STEP_PARTICLES/GO_EXPLOSION_SEQUENCE)へ置き換えた。ジッター
# ---- 無しの直進(EXPLODE_DIR_DX/DYと完全に同じ値)を複数バースト
# ---- (NUM_BURSTS回)繰り返すことで「連続でバンバン」を実現する。
VALID_DIRS = {
    (0, -2), (2, -2), (2, 0), (2, 2), (0, 2), (-2, 2), (-2, 0), (-2, -2),
}
GO_DIR_DX = sym["GO_DIR_DX"]
GO_DIR_DY = sym["GO_DIR_DY"]
table_dx = [signed(mem0[GO_DIR_DX + i]) for i in range(8)]
table_dy = [signed(mem0[GO_DIR_DY + i]) for i in range(8)]
check("GO_DIR_DX/DY table matches combined_test.asm's own EXPLODE_DIR_DX/DY "
      "verbatim (the exact model being 'multiplied' into 4 particles)",
      set(zip(table_dx, table_dy)) == VALID_DIRS)

GO_DIR = [
    (sym["GO_DIR0X"], sym["GO_DIR0Y"]),
    (sym["GO_DIR1X"], sym["GO_DIR1Y"]),
    (sym["GO_DIR2X"], sym["GO_DIR2Y"]),
    (sym["GO_DIR3X"], sym["GO_DIR3Y"]),
]


def call_ret(z, target, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = target
    run_until_pc(z, 0x0000, max_instr)


# GO_PICK_DIR itself: across many seeds, the (dx,dy) it returns must always
# be one of the 8 table entries (never garbage from a misaligned lookup).
picked = set()
z = fresh()
for seed in range(0, 256, 3):
    z.wr(sym["GO_RNG"], seed)
    z.a = 0
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = sym["GO_PICK_DIR"]
    run_until_pc(z, 0x0000, 300000)
    picked.add((signed(z.a), signed(z.h)))
check("GO_PICK_DIR only ever returns one of the 8 valid EXPLODE_DIR-style "
      "vectors across many RNG seeds (no misaligned table lookup)",
      picked <= VALID_DIRS)
check("GO_PICK_DIR actually exercises more than one direction across many "
      "seeds (genuinely randomized, not stuck on a single entry)",
      len(picked) > 1)

# GO_NEW_BURST: resets all 4 accumulated offsets to 0 (particles snap back
# to the player's own center - "自機中心から...連続で" popping again) and
# assigns each of the 4 particles its OWN independently-picked direction.
z = fresh()
for addr in GO_PX + GO_PY:
    z.wr(addr, 0x7F)  # poison so a real reset is actually verified
z.wr(sym["GO_RNG"], 17)
call_ret(z, sym["GO_NEW_BURST"])
offsets_after = [z.rd(a) for a in GO_PX + GO_PY]
check("GO_NEW_BURST resets all 4 particles' accumulated (dx,dy) offset back "
      "to 0 (poisoned 0x7F values actually get cleared)",
      offsets_after == [0] * 8)
dirs_after = [(signed(z.rd(dx)), signed(z.rd(dy))) for dx, dy in GO_DIR]
check("GO_NEW_BURST assigns each of the 4 particles a valid 8-way direction",
      all(d in VALID_DIRS for d in dirs_after))
check("GO_NEW_BURST's 4 particles don't all get pushed through the exact "
      "same RNG draw pattern in lockstep (at least 2 distinct directions "
      "typically appear among 4 independent picks with a non-degenerate seed)",
      len(set(dirs_after)) >= 2)

# GO_STEP_PARTICLES: adds each particle's own fixed direction (as set by
# GO_NEW_BURST) to its accumulator by exactly 1 step - constant-velocity
# straight-line motion, no jitter (the direct fix for "ふわ～っと").
z = fresh()
test_dirs = [(2, -2), (-2, 0), (0, 2), (-2, -2)]
for (dxa, dya), (dx, dy) in zip(GO_DIR, test_dirs):
    z.wr(dxa, dx & 0xFF)
    z.wr(dya, dy & 0xFF)
for addr in GO_PX + GO_PY:
    z.wr(addr, 0)
call_ret(z, sym["GO_STEP_PARTICLES"])
# note: GO_PX + GO_PY is [PX0,PX1,PX2,PX3, PY0,PY1,PY2,PY3] - NOT interleaved
# per-particle - the expected values below follow that same grouping.
step1 = [signed(z.rd(a)) for a in GO_PX + GO_PY]
check("GO_STEP_PARTICLES advances all 4 particles by exactly their own "
      "fixed direction in one call (straight-line step, matching "
      "EXPLODE_DIR_DX/DY's own constant 2px/frame magnitude)",
      step1 == [2, -2, 0, -2, -2, 0, 2, -2])
call_ret(z, sym["GO_STEP_PARTICLES"])
step2 = [signed(z.rd(a)) for a in GO_PX + GO_PY]
check("a second GO_STEP_PARTICLES call advances by the SAME fixed amount "
      "again (constant velocity, not jitter that varies call to call)",
      step2 == [4, -4, 0, -4, -4, 0, 4, -4])

# ---- GO_EXPLOSION_SEQUENCE: the full "連続でバンバン" burst-repeat loop ----
NUM_BURSTS = sym["NUM_BURSTS"]
BURST_FRAMES = sym["BURST_FRAMES"]
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.wr(sym["GO_RNG"], 5)
seen_frames = []
GO_DRAW_PARTICLES = sym["GO_DRAW_PARTICLES"]
call_ret_target = sym["GO_EXPLOSION_SEQUENCE"]
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
z.pc = call_ret_target
steps = 0
while z.pc != 0x0000 and steps < 5_000_000:
    if z.pc == GO_DRAW_PARTICLES:
        seen_frames.append(tuple(signed(z.rd(a)) for a in GO_PX + GO_PY))
    z.step()
    steps += 1
check(f"GO_EXPLOSION_SEQUENCE calls GO_DRAW_PARTICLES exactly NUM_BURSTS*"
      f"BURST_FRAMES ({NUM_BURSTS}*{BURST_FRAMES}={NUM_BURSTS * BURST_FRAMES}) times",
      len(seen_frames) == NUM_BURSTS * BURST_FRAMES)
# every BURST_FRAMES-th draw is the 1st frame of a fresh burst - particle0's
# offset there must be exactly its own per-frame step (not 0, since the
# frame is drawn AFTER stepping once) and every burst boundary before that
# must show the particles having traveled outward, then snapping back to a
# small first-step offset for the next burst - i.e. genuine repeated bursts,
# not one continuous unbounded drift.
burst_starts = seen_frames[0::BURST_FRAMES]
burst_ends = seen_frames[BURST_FRAMES - 1::BURST_FRAMES]
check("each burst's LAST frame has traveled further from center than its "
      "FIRST frame (a real outward flight within every burst, not a static "
      "pose)",
      all(sum(abs(v) for v in end) > sum(abs(v) for v in start)
          for start, end in zip(burst_starts, burst_ends)))
check("each burst's first frame is much closer to center than the PREVIOUS "
      "burst's last frame (particles genuinely snap back near the player's "
      "own center at the start of every new burst - the 'pop back and fly "
      "again' that makes it read as continuous bursts rather than one "
      "particle wandering off forever)",
      all(sum(abs(v) for v in burst_starts[i]) < sum(abs(v) for v in burst_ends[i - 1]) / 2
          for i in range(1, len(burst_starts))))
check("bursts are not all identical (different random directions are "
      "picked burst to burst)",
      len(set(burst_ends)) > 1)
# within a single burst, consecutive frames must move by a CONSTANT vector
# per particle (straight-line, matching EXPLODE_DIR_DX/DY's fixed 2px/frame
# magnitude) - this is the literal fix for "ふわ～っと飛び散って気持ち悪い"
# (the old design accumulated a varying -1..+2 jitter every frame instead).
first_burst = seen_frames[0:BURST_FRAMES]
per_particle_deltas_constant = True
for p in range(4):
    deltas = set()
    prev = (0, 0)
    for frame in first_burst:
        cur = (frame[p * 2], frame[p * 2 + 1])
        deltas.add((cur[0] - prev[0], cur[1] - prev[1]))
        prev = cur
    if len(deltas) != 1 or next(iter(deltas)) not in VALID_DIRS:
        per_particle_deltas_constant = False
check("within a single burst, each particle's per-frame delta is constant "
      "and matches one of the 8 fixed EXPLODE_DIR-style vectors (no jitter, "
      "a true straight-line flight)",
      per_particle_deltas_constant)

GO_HIDE_EXPLOSION = sym["GO_HIDE_EXPLOSION"]
GO_WAIT_LOOP = sym["GO_WAIT_LOOP"]
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.pc = sym["INIT"]
hide_calls_before_text = 0
steps = 0
while z.pc != GO_WAIT_LOOP and steps < 5_000_000:
    if z.pc == GO_HIDE_EXPLOSION:
        hide_calls_before_text += 1
    z.step()
    steps += 1
# (2026-09-07、実機フィードバック対応"爆発エフェクトが消えずのこったまま
# Mission Failedになってる で爆発エフェクトは消してくれ"): 新設計では
# バースト間の点滅ギャップを廃止した(新バーストは即座に自機中心へ戻り
# 継続して飛ぶ)ため、GO_HIDE_EXPLOSIONはもう全バーストの内部では呼ばれず、
# 全バースト完了後・テキスト描画直前の明示的な1回だけになった。
check("GO_HIDE_EXPLOSION is called exactly once before GO_WAIT_LOOP (the "
      "single explicit hide after all bursts finish, right before the "
      "MISSION FAILED text is drawn) - the fix for the explosion sprites "
      "being left visible under the text",
      hide_calls_before_text == 1)

# confirm the sprite attribute table is really left in the "all hidden" state at
# the moment GO_WAIT_LOOP (i.e. after the text has already been drawn) is reached -
# this is the literal on-screen check for "爆発エフェクトは消してくれ".
hidden_attrs = [z.vram[0x1B00 + i] for i in range(16)]
check("by the time MISSION FAILED text is on screen (GO_WAIT_LOOP reached), all 4 "
      "explosion particle sprite slots are hidden (Y=209), not left visible under it",
      hidden_attrs == [209, 0, 0, 0] * 4)

# ---- "自機爆発はサウンドも欲しい"、続けて"爆発音はステージ1、2ともに ----
# ---- パーティクルの回数鳴らすんだよ"(2026-09-07、実機フィードバック  ----
# ---- 対応その2): 旧GO_PLAY_BOOM_SOUND(全シーケンス開始時に1回だけ、   ----
# ---- 専用の16段減衰ループで完結)を全面撤回、GO_ARM_BOOM(バースト開始 ----
# ---- 時に音量15で撃ち直す)+GO_STEP_BOOM_DECAY(その後のフレーム      ----
# ---- ループの中で毎回1段ずつ減衰、専用の追加ウェイト無し)へ分割し、  ----
# ---- Stage1のPEUA_TRY_SPAWN(spawnごとに毎回SOUND_DESTROY)と同じ      ----
# ---- 「パーティクル[バースト]の数だけ毎回鳴らす」設計にした。         ----
MIXER_NOISE_A = sym["MIXER_NOISE_A"]
BOOM_NOISE_PERIOD = sym["BOOM_NOISE_PERIOD"]
GO_BOOM_VOL = sym["GO_BOOM_VOL"]
z = fresh()
call_ret(z, sym["GO_ARM_BOOM"])
check("GO_ARM_BOOM selects PSG R7 (mixer) = MIXER_NOISE_A (noise channel A on, "
      "tone B/C stay enabled for BGM - matches Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(7) == MIXER_NOISE_A)
check("GO_ARM_BOOM sets PSG R6 (noise period) = BOOM_NOISE_PERIOD (20, same as "
      "Stage1/Stage2's own SOUND_DESTROY)",
      z.psg_regs.get(6) == BOOM_NOISE_PERIOD)
check("GO_ARM_BOOM sets PSG R8 (channel A volume) to 15 (full volume retrigger)",
      z.psg_regs.get(8) == 15)
check("GO_ARM_BOOM sets GO_BOOM_VOL to 15 (the per-frame decay countdown)",
      z.rd(GO_BOOM_VOL) == 15)

# GO_STEP_BOOM_DECAY: called once per animation frame (BURST_FRAMES=8 times
# per burst) - decays by 2 each call, floored at 0, and stays silent once
# it reaches 0 (no further decrement past the floor).
z = fresh()
z.wr(GO_BOOM_VOL, 15)
r8_writes = []
for _ in range(10):
    call_ret(z, sym["GO_STEP_BOOM_DECAY"])
    r8_writes.append(z.psg_regs.get(8))
check("GO_STEP_BOOM_DECAY decays R8 by 2 each call, floored at 0 once it "
      "would go negative, and stays silent afterward (never re-increments)",
      r8_writes == [13, 11, 9, 7, 5, 3, 1, 0, 0, 0])
check("GO_STEP_BOOM_DECAY leaves GO_BOOM_VOL at 0 once fully decayed",
      z.rd(GO_BOOM_VOL) == 0)

# GO_EXPLOSION_SEQUENCE itself: each of the NUM_BURSTS bursts must re-arm
# the boom (R8 back up near 15) at its own start - this is the literal
# fix for "パーティクルの回数鳴らすんだよ" (a boom retrigger per burst,
# not one boom for the whole sequence).
z = fresh()
z.wr(TANK_X, 120)
z.wr(TANK_Y_CUR, 90)
z.wr(sym["GO_RNG"], 9)
GO_NEW_BURST_PC = sym["GO_NEW_BURST"]
seen_r8_near_burst_start = []
z.sp = 0xF000
z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
z.pc = sym["GO_EXPLOSION_SEQUENCE"]
steps = 0
_prev_pc = None
while z.pc != 0x0000 and steps < 5_000_000:
    if z.pc == GO_NEW_BURST_PC and _prev_pc != GO_NEW_BURST_PC:
        seen_r8_near_burst_start.append(z.psg_regs.get(8))
    _prev_pc = z.pc
    z.step()
    steps += 1
NUM_BURSTS_VAL = sym["NUM_BURSTS"]
check(f"GO_EXPLOSION_SEQUENCE starts all {NUM_BURSTS_VAL} bursts (GO_NEW_BURST reached "
      f"{NUM_BURSTS_VAL} times)",
      len(seen_r8_near_burst_start) == NUM_BURSTS_VAL)
check("every burst but the very first one begins with the PREVIOUS burst's boom already "
      "decayed low/silent (R8 low) right before GO_ARM_BOOM re-triggers it back to 15 - "
      "i.e. the boom genuinely re-fires once per burst instead of firing once for the "
      "whole sequence and staying silent thereafter",
      all((v or 0) <= 1 for v in seen_r8_near_burst_start[1:]))
check("GO_ARM_BOOM is actually reached at all (R8 gets set to something at least once - "
      "guards against a regression where the boom is dropped from the burst loop entirely)",
      any(v is not None for v in seen_r8_near_burst_start))

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
