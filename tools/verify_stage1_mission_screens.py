"""Stage1: MISSION 1導入演出("STAGE1も2と同じで一旦画面をブラックで埋めて
MISSION 1と3秒表示してから ステージ1スタートに")・ステージクリア演出の
左端退避+MISSION 2黒画面(STAGE_CLEAR_ACT 0/1/2/3への拡張)を検証する。
tools/verify_player_damage.py等と同じ「mini_z80asm.Assemblerで直接
アセンブル+call_routine/run_until_pcの一回性検証スクリプト」の作法。
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

# MISSION_DELAY_3SEC's real ~3-second busy-wait (LD D,10 -> ~1.3M instructions)
# would blow every other test file's boot()/run_until_pc instruction budget in
# this suite. Shrink it to a single outer pass (D=1, ~130K instructions, well
# within existing limits) for every test in THIS process - patches the raw
# byte at MISSION_DELAY_3SEC+1 (the LD D,n immediate), not the shipped ROM
# source, so real hardware still gets the full ~3 seconds unchanged.
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=500_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


PLAYERX = sym["PLAYERX"]
PLAYER_RETREAT_ACT = sym["PLAYER_RETREAT_ACT"]
PLAYER_RETREAT_SPEED = sym["PLAYER_RETREAT_SPEED"]
PLAYER_FLYAWAY = sym["PLAYER_FLYAWAY"]
PLAYER_FLYAWAY_WAIT = sym["PLAYER_FLYAWAY_WAIT"]
PLAYER_FLYAWAY_SPD = sym["PLAYER_FLYAWAY_SPD"]
STAGE_CLEAR_ACT = sym["STAGE_CLEAR_ACT"]
SC_VBLANK_COUNT = sym["SC_VBLANK_COUNT"]
SC_START_TICK = sym["SC_START_TICK"]
STAGE_CLEAR_TOTAL_TICKS = sym["STAGE_CLEAR_TOTAL_TICKS"]
MISSION_SCREEN_TICKS = sym["MISSION_SCREEN_TICKS"]
MISSION_FONT_BASE = sym["MISSION_FONT_BASE"]
MISSION1_MSG = sym["MISSION1_MSG"]
MISSION2_MSG = sym["MISSION2_MSG"]
DRAW_MISSION_SCREEN = sym["DRAW_MISSION_SCREEN"]
BGM_MUTED = sym["BGM_MUTED"]
DIGIT_BASE = sym["DIGIT_BASE"]
BOSS_EXPL_ACTIVE = sym["BOSS_EXPL_ACTIVE"]
BOSS_EXPL_INDEX = sym["BOSS_EXPL_INDEX"]
BOSS_EXPL_COUNT = sym["BOSS_EXPL_COUNT"]
SND_TONE_TIMER = sym["SND_TONE_TIMER"]

# ---- real boot: MISSION1 shows then the real stage background is drawn ----
# ---- fresh afterward, as its own separate phase - before MAINLOOP starts ----
# 実機フィードバック"Mission表示して同時にステージスタートさせてんだ"
# 対応: MISSION1は今やCALL INIT32の直後、ステージ本編の背景描画
# (FILLBG_1/2/3、rows0-19)より前の独立フェーズとして表示される。その
# 背景描画はMission1の消去後に初めて走るため、MAINLOOP到達時点の
# メッセージ領域(row12はrows0-19の範囲内)はSPACEグリフ(黒画面のまま)
# ではなく、実際の背景(BLANKCODE)で上書きされているはずー単体呼び出し
# だけでなく本物のboot()経由でも確認する。
BLANKCODE = sym["BLANKCODE"]
z = fresh()
boot(z)
nametable_at_boot = [z.vram[0x1800 + i] for i in range(768)]
msg_region_at_boot = nametable_at_boot[12 * 32 + 11: 12 * 32 + 11 + 9]
check("real boot: by the time MAINLOOP is reached, the real stage background (BLANKCODE) "
      "has been freshly redrawn over the MISSION1 text region as its own separate phase "
      "AFTER Mission1 finished (not left showing the SPACE glyph / stale blackout)",
      all(b == BLANKCODE for b in msg_region_at_boot))

# ---- 実機フィードバック対応("だからまだ設定前のPSGが解放されて       ----
# ---- ノイズ状態の音がなってんだろうが 3秒待たされてんだからよ"):       ----
# ---- INIT_BGM is expected to start BGM_MUTED (muted), and only the    ----
# ---- very last thing INIT does (right before EI/HALT/JP MAINLOOP)     ----
# ---- unmutes it - so nothing can make chB/chC noise while the game is ----
# ---- still mid-setup (including throughout the whole Mission1 phase). ----
INIT_BGM = sym["INIT_BGM"]
UNMUTE_BGM = sym["UNMUTE_BGM"]
z = fresh()
call_routine(z, INIT_BGM)
check("INIT_BGM leaves BGM_MUTED=1 (muted) - BGM_TICK cannot write chB/chC PSG data until "
      "INIT explicitly calls UNMUTE_BGM at the very end",
      z.rd(BGM_MUTED) == 1)

z = fresh()
boot(z)
check("real boot: by the time MAINLOOP is reached, BGM_MUTED is back to 0 (unmuted) - "
      "INIT's own UNMUTE_BGM ran, right after all stage setup (background/sprites/enemy "
      "pools/PSG R7 mixer) finished and right before the real hardware-mute risk window "
      "(the whole earlier Mission1-plus-setup phase) closed",
      z.rd(BGM_MUTED) == 0)

# raw instruction trace: confirm BGM_MUTED is ALREADY 1 by the moment DRAW_MISSION_SCREEN
# (Mission1's own display routine) starts running - i.e. muting genuinely happens before
# Mission1, not merely by coincidence of final state. Catches a future reordering mistake
# that would silently put DRAW_MISSION_SCREEN before INIT_BGM/before the BGM_MUTED=1 write.
DRAW_MISSION_SCREEN_ADDR = sym["DRAW_MISSION_SCREEN"]
z = fresh()
z.pc = sym["INIT"]
for _ in range(500_000):
    if z.pc == DRAW_MISSION_SCREEN_ADDR:
        break
    z.step()
else:
    raise RuntimeError("never reached DRAW_MISSION_SCREEN from INIT")
check("raw trace: BGM_MUTED is already 1 by the instant DRAW_MISSION_SCREEN (Mission1's own "
      "display routine) starts executing - muting genuinely precedes Mission1, not just the "
      "final boot() snapshot",
      z.rd(BGM_MUTED) == 1)

# ---- boot-time VRAM load: font pattern + color (2026-09-07 "Mission表示の ----
# ---- フォントは添付ファイルで": M,I,S,O,N,space,1,2 の8グリフへ拡張,   ----
# ---- tools/pixel_font_8x8.pyのバイト列と同一)                          ----
import importlib.util
_pf_spec = importlib.util.spec_from_file_location(
    "pixel_font_8x8", os.path.join(REPO_ROOT, "tools", "pixel_font_8x8.py"))
pixel_font_8x8 = importlib.util.module_from_spec(_pf_spec)
_pf_spec.loader.exec_module(pixel_font_8x8)

z = fresh()
boot(z)
expected_font = {
    0: pixel_font_8x8.glyph_bytes("M"),
    1: pixel_font_8x8.glyph_bytes("I"),
    2: pixel_font_8x8.glyph_bytes("S"),
    3: pixel_font_8x8.glyph_bytes("O"),
    4: pixel_font_8x8.glyph_bytes("N"),
    5: pixel_font_8x8.glyph_bytes(" "),
    6: pixel_font_8x8.glyph_bytes("1"),
    7: pixel_font_8x8.glyph_bytes("2"),
}
font_ok = True
for offset, bytes_ in expected_font.items():
    code = MISSION_FONT_BASE + offset
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != bytes_:
        font_ok = False
check("boot: MISSION_FONT_PATTERNS (M,I,S,O,N,space,1,2 - attached Font_24x24_1.json) "
      "loaded byte-correct at MISSION_FONT_BASE(64)..+7 in the pattern generator table",
      font_ok)
check("boot: group8 (codes64-71) color byte at VRAM 2008h patched to white/black (0F1h)",
      z.vram[0x2008] == 0xF1)

# ---- GAME OVER font (G,A,E,V,R, group9 codes72-76) ----
GAMEOVER_FONT_BASE = sym["GAMEOVER_FONT_BASE"]
GAME_OVER_MSG = sym["GAME_OVER_MSG"]
expected_gameover_font = {
    0: pixel_font_8x8.glyph_bytes("G"),
    1: pixel_font_8x8.glyph_bytes("A"),
    2: pixel_font_8x8.glyph_bytes("E"),
    3: pixel_font_8x8.glyph_bytes("V"),
    4: pixel_font_8x8.glyph_bytes("R"),
}
gameover_font_ok = True
for offset, bytes_ in expected_gameover_font.items():
    code = GAMEOVER_FONT_BASE + offset
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != bytes_:
        gameover_font_ok = False
check("boot: GAMEOVER_FONT_PATTERNS (G,A,E,V,R) loaded byte-correct at "
      "GAMEOVER_FONT_BASE(72)..+4 in the pattern generator table", gameover_font_ok)
check("boot: group9 (codes72-79) color byte at VRAM 2009h patched to white/black (0F1h)",
      z.vram[0x2009] == 0xF1)

# ---- DIGIT_PATTERNS (digits0-9, used by score display etc - unrelated to ----
# ---- Mission text now, but still needs to be loaded somewhere in INIT)  ----
DIGIT_PATTERNS_EXPECTED = {
    0: [0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0x00],
    1: [0x18, 0x38, 0x58, 0x18, 0x18, 0x18, 0x7E, 0x00],
    2: [0x3C, 0x66, 0x06, 0x0C, 0x30, 0x60, 0x7E, 0x00],
}
digit_ok = True
for n, bytes_ in DIGIT_PATTERNS_EXPECTED.items():
    code = DIGIT_BASE + n
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != bytes_:
        digit_ok = False
check("boot: DIGIT_PATTERNS (digit 0/1/2, score display font) loaded byte-correct at "
      "DIGIT_BASE(176)+N in the pattern generator table - NOT left as stale/garbage VRAM "
      "from the previous stage (Title)",
      digit_ok)
check("boot: group22 (codes176-183, digits0-7) color byte at VRAM 2016h is white/black "
      "(0F1h), matching COLORDATA's own eventual value for this group",
      z.vram[0x2000 + 22] == 0xF1)

# ---- MISSION1_MSG / MISSION2_MSG content (末尾は添付フォントの'1'/'2', ----
# ---- MISSION_FONT_BASE+6/+7 - もうDIGIT_BASEには依存しない)            ----
def read_msg(addr, length=9):
    return [mem0[addr + i] for i in range(length)]

expected_msg_prefix = [MISSION_FONT_BASE + 0, MISSION_FONT_BASE + 1, MISSION_FONT_BASE + 2,
                       MISSION_FONT_BASE + 2, MISSION_FONT_BASE + 1, MISSION_FONT_BASE + 3,
                       MISSION_FONT_BASE + 4, MISSION_FONT_BASE + 5]
check("MISSION1_MSG = 'MISSION' + space + '1' (MISSION_FONT_BASE+6)",
      read_msg(MISSION1_MSG) == expected_msg_prefix + [MISSION_FONT_BASE + 6])
check("MISSION2_MSG = 'MISSION' + space + '2' (MISSION_FONT_BASE+7)",
      read_msg(MISSION2_MSG) == expected_msg_prefix + [MISSION_FONT_BASE + 7])

# ---- GAME_OVER_MSG content (2026-09-07、"表示もGAME OVERではなく       ----
# ---- MISSION FAILEDに変更"): "MISSION FAILED"(14 bytes), M/I/S/O/N/    ----
# ---- spaceはMISSION_FONT_BASE側、F/A/L/E/DはGAMEOVER_FONT_BASE側       ----
GAME_OVER_MSG_LEN = sym["GAME_OVER_MSG_LEN"]
expected_gameover_msg = [
    MISSION_FONT_BASE + 0,   # M
    MISSION_FONT_BASE + 1,   # I
    MISSION_FONT_BASE + 2,   # S
    MISSION_FONT_BASE + 2,   # S
    MISSION_FONT_BASE + 1,   # I
    MISSION_FONT_BASE + 3,   # O
    MISSION_FONT_BASE + 4,   # N
    MISSION_FONT_BASE + 5,   # space
    GAMEOVER_FONT_BASE + 5,  # F
    GAMEOVER_FONT_BASE + 1,  # A
    MISSION_FONT_BASE + 1,   # I
    GAMEOVER_FONT_BASE + 6,  # L
    GAMEOVER_FONT_BASE + 2,  # E
    GAMEOVER_FONT_BASE + 7,  # D
]
check("GAME_OVER_MSG = 'MISSION FAILED' (14 bytes, mixing MISSION_FONT_BASE/GAMEOVER_FONT_BASE)",
      read_msg(GAME_OVER_MSG, GAME_OVER_MSG_LEN) == expected_gameover_msg)

# ---- DRAW_MISSION_SCREEN: fills the whole name table black + draws the ----
# ---- 9-byte message centered at row12/col11 + hides all sprites        ----
z = fresh()
boot(z)
# poison the name table and sprite table first so a no-op call couldn't fake a pass
for i in range(768):
    z.vram[0x1800 + i] = 0x55
z.vram[0x1B00] = 0x00
z.wr(0xF000 + 100, MISSION1_MSG & 0xFF)  # scratch, unused
z.sethl(MISSION1_MSG)
call_routine(z, DRAW_MISSION_SCREEN)
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 11: 12 * 32 + 11 + 9]
# 実機フィードバック"全く修正されてねえよ...なんでスクロールを避ける必要が
# ある Mission2はその手順で問題なく動いてるだろうが"対応: row20-23
# (4-row ground scroller)を避ける版はA/Bエミュレータ比較(現行コード vs
# round53着手前コミット)で地形スクロールの出力に一切差が無いと判明し
# 誤った理論と確定、Mission2と同じ全768byte一括塗りつぶしに戻した。
rest_is_black = all(b == MISSION_FONT_BASE + 5 for i, b in enumerate(nametable)
                     if not (12 * 32 + 11 <= i < 12 * 32 + 11 + 9))
check("DRAW_MISSION_SCREEN: entire 768byte name table filled with the SPACE glyph "
      "(MISSION_FONT_BASE+5) except the message region", rest_is_black)
check("DRAW_MISSION_SCREEN: message region (row12,col11..19) matches MISSION1_MSG",
      msg_region == read_msg(MISSION1_MSG))
check("DRAW_MISSION_SCREEN: sprite attribute table's first Y forced to 209 (hides all sprites)",
      z.vram[0x1B00] == 209)
check("DRAW_MISSION_SCREEN: silences PSG channel A (SE) volume to kill any stuck tone/noise",
      z.psg_regs.get(8) == 0)

# ---- ERASE_MISSION_TEXT: MISSION1-only cleanup after the delay - restores just ----
# ---- the 9-byte message region back to SPACE, leaves everything else alone    ----
z = fresh()
boot(z)
for i in range(768):
    z.vram[0x1800 + i] = 0x77
call_routine(z, sym["ERASE_MISSION_TEXT"])
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 11: 12 * 32 + 11 + 9]
rest_untouched = all(b == 0x77 for i, b in enumerate(nametable)
                     if not (12 * 32 + 11 <= i < 12 * 32 + 11 + 9))
check("ERASE_MISSION_TEXT: message region (row12,col11..19) restored to the SPACE glyph",
      all(b == MISSION_FONT_BASE + 5 for b in msg_region))
check("ERASE_MISSION_TEXT: leaves every other byte (including the ground scroller) untouched",
      rest_untouched)

# ---- DRAW_GAMEOVER_TEXT (2026-09-07 "ゲームオーバーは画面中央にMISSION ----
# ---- FAILEDと表示" -> 実機フィードバック対応"ステージ1のMission        ----
# ---- Failedもステージ2と同じで行をブラックで埋める": row12全体(32セル) ----
# ---- を黒でブランク埋めしてから14byteメッセージをその中央(col9)へ      ----
# ---- 上書きする2パス方式(gameover_bank.asm[Stage2]と統一)。row12以外 ----
# ---- の名前テーブル・スプライト属性テーブル・PSG channel Aは           ----
# ---- DRAW_MISSION_SCREENと違い引き続き無変更(死亡直後もゲーム画面は   ----
# ---- 普通に動き続ける設計自体は維持)。                                  ----
z = fresh()
boot(z)
for i in range(768):
    z.vram[0x1800 + i] = 0x33
z.vram[0x1B00] = 0x42
z.psg_regs[8] = 0x0F
call_routine(z, sym["DRAW_GAMEOVER_TEXT"])
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAME_OVER_MSG_LEN]
row12 = nametable[12 * 32: 12 * 32 + 32]
rest_untouched = all(b == 0x33 for i, b in enumerate(nametable) if not (12 * 32 <= i < 13 * 32))
MISSION_FONT_BASE = sym["MISSION_FONT_BASE"]
check("DRAW_GAMEOVER_TEXT: message region (row12,col9..) matches GAME_OVER_MSG",
      msg_region == read_msg(GAME_OVER_MSG, GAME_OVER_MSG_LEN))
check("DRAW_GAMEOVER_TEXT: row12's left margin (cols0-8, before the message) is blanked to "
      "the SPACE glyph (black), not left showing the pre-death background",
      row12[0:9] == [MISSION_FONT_BASE + 5] * 9)
check("DRAW_GAMEOVER_TEXT: row12's right margin (cols23-31, after the message) is blanked to "
      "the SPACE glyph (black), not left showing the pre-death background",
      row12[23:32] == [MISSION_FONT_BASE + 5] * 9)
check("DRAW_GAMEOVER_TEXT: no leftover 0x33 poison bytes remain anywhere in row12 (fully "
      "overwritten - blank margins + message, nothing untouched)", 0x33 not in row12)
check("DRAW_GAMEOVER_TEXT: leaves every OTHER name-table row untouched (only row12 is "
      "touched, unlike DRAW_MISSION_SCREEN's full-screen blackout)", rest_untouched)
check("DRAW_GAMEOVER_TEXT: does NOT touch the sprite attribute table (sprites stay visible, "
      "unlike DRAW_MISSION_SCREEN's hide-all)", z.vram[0x1B00] == 0x42)
check("DRAW_GAMEOVER_TEXT: does NOT touch PSG channel A volume (SE keeps playing normally)",
      z.psg_regs.get(8) == 0x0F)

# ---- PTH_GAMEOVER wiring: reaching GAME_OVER=1 via a barrier-exhausted hit ----
# ---- actually draws GAME_OVER_MSG on screen (not just sets the flag)       ----
# (2026-09-07、"操作無効の上爆発しながら右斜め下に落下しMission Failed
# 表示に"、続けて"斜め下に落下したらそのまま画面外に消えるように変更"):
# PTH_GAMEOVER自身はもうテキスト描画・GAME_OVER_SEQ起動を即座には行わない
# - 代わりにPLAYER_DEATH_FALL_ACTを起動するだけで、実際のテキスト表示/
# SEQ起動はPLAYERYが実際に画面外(199)へ到達した瞬間まで先送りされる
# (固定フレーム数ではなく、開始位置からの距離に応じた可変長、下記
# step_frame連打で検証)。
BARRIER_HP = sym["BARRIER_HP"]
GAME_OVER = sym["GAME_OVER"]
GAME_OVER_SEQ = sym["GAME_OVER_SEQ"]
PLAYER_DEATH_FALL_ACT = sym["PLAYER_DEATH_FALL_ACT"]
PLAYER_DEATH_FALL_SPEED = sym["PLAYER_DEATH_FALL_SPEED"]
PLAYERY = sym["PLAYERY"]
z = fresh()
boot(z)
z.wr(BARRIER_HP, 0)
for i in range(768):
    z.vram[0x1800 + i] = 0x33
call_routine(z, sym["PTH_GAMEOVER"])
nametable = [z.vram[0x1800 + i] for i in range(768)]
check("PTH_GAMEOVER: sets GAME_OVER=1", z.rd(GAME_OVER) == 1)
check("PTH_GAMEOVER: arms the death-fall sequence (PLAYER_DEATH_FALL_ACT=1) "
      "instead of drawing text immediately",
      z.rd(PLAYER_DEATH_FALL_ACT) == 1)
check("PTH_GAMEOVER: does NOT draw GAME_OVER_MSG yet (deferred until the death-fall finishes)",
      all(b == 0x33 for b in nametable))
check("PTH_GAMEOVER: does NOT arm GAME_OVER_SEQ yet (deferred until the death-fall finishes)",
      z.rd(GAME_OVER_SEQ) == 0)

GAME_OVER = sym["GAME_OVER"]
y0 = z.rd(PLAYERY)
# (2026-09-07、"斜め下に落下したらそのまま画面外に消えるように変更"):
# completion is now driven purely by PLAYERY reaching 199 (2px/frame),
# so the expected frame count is derived from the actual starting Y
# rather than a fixed duration constant (which no longer exists).
expected_frames = -(-(199 - y0) // PLAYER_DEATH_FALL_SPEED)  # ceil division
z.pc = sym["MAINLOOP"]
for i in range(expected_frames):
    step_frame(z)
    if i < expected_frames - 1:
        assert z.rd(GAME_OVER_SEQ) == 0, f"GAME_OVER_SEQ armed early, at frame {i}"
        # mid-fall, before the final frame, the ship must still be
        # somewhere on the visible playfield (not yet at the hide
        # corner) - otherwise it would just vanish immediately instead
        # of visibly falling continuously toward the edge.
        assert not (z.rd(PLAYERX) == 255 and z.rd(PLAYERY) == 199), \
            f"ship reached the hide corner too early, at frame {i}"
        # the fall must be a genuine continuous diagonal descent, not a
        # jump straight to the end - PLAYERY should still be climbing
        # toward (but not yet at) the off-screen threshold each frame.
        assert z.rd(PLAYERY) < 199, \
            f"PLAYERY reached/exceeded the off-screen threshold before the expected frame, at frame {i}"
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAME_OVER_MSG_LEN]
check("death-fall completion: PLAYERX/PLAYERY land exactly on the (255,199) hide corner "
      "(drawn Y = 199-8 = 191 = ENEMY_HIDE_Y, the same off-screen convention used everywhere "
      "else in this file - falls naturally until it actually reaches this off-screen value, "
      "'斜め下に落下したらそのまま画面外に消えるように')",
      z.rd(PLAYERX) == 255 and z.rd(PLAYERY) == 199)
check("death-fall: clears its own ACT flag once the fall finishes",
      z.rd(PLAYER_DEATH_FALL_ACT) == 0)
check("death-fall completion: NOW draws GAME_OVER_MSG at the screen-center message region",
      msg_region == read_msg(GAME_OVER_MSG, GAME_OVER_MSG_LEN))
check("death-fall completion: NOW arms GAME_OVER_SEQ=1 (3-second display phase)",
      z.rd(GAME_OVER_SEQ) == 1)
# (2026-09-08、"ではゲームオーバーBGM...これで組み込んでくれ"): same real
# death-fall trace as above, confirming TRIGGER_GAME_OVER_JINGLE actually
# fired from the real PFA_DEATH_FALL_STEP code path (not just a synthetic
# call_routine(TRIGGER_GAME_OVER_JINGLE) test - see tools/verify_stage1_bgm.py
# for the driver-level checks of TRIGGER_GAME_OVER_JINGLE itself).
check("death-fall completion: NOW points BGM_B_PTR/BGM_C_PTR at the GAME_OVER jingle's own "
      "chB/chC start (TRIGGER_GAME_OVER_JINGLE actually fired on the real death-fall path)",
      (z.rd(sym["BGM_B_PTR"]) | (z.rd(sym["BGM_B_PTR"] + 1) << 8)) == sym["BGM_GAMEOVER_CHB_BASE"] and
      (z.rd(sym["BGM_C_PTR"]) | (z.rd(sym["BGM_C_PTR"] + 1) << 8)) == sym["BGM_GAMEOVER_CHC_BASE"])

# regression guard: the fall's duration is genuinely tied to the starting
# distance from the off-screen threshold, not a fixed frame count - dying
# already close to the bottom must finish in fewer frames than dying near
# the top (this is the entire point of "そのまま画面外に消えるように" -
# a real continuous fall, not a fixed-length animation regardless of
# where death occurred).
z = fresh()
boot(z)
z.wr(PLAYERY, 190)  # already very close to the 199 threshold
z.wr(GAME_OVER, 1)
z.wr(PLAYER_DEATH_FALL_ACT, 1)
z.pc = sym["MAINLOOP"]
near_bottom_frames = 0
for _ in range(30):
    step_frame(z)
    near_bottom_frames += 1
    if z.rd(GAME_OVER_SEQ) == 1:
        break
check("death-fall duration scales with starting distance from the off-screen "
      "threshold (dying near the bottom finishes in far fewer frames than the "
      "far-from-bottom case above, not a fixed duration)",
      z.rd(GAME_OVER_SEQ) == 1 and near_bottom_frames < expected_frames)

# (2026-09-07、"操作無効" persists forever after death, not just during the
# 45-frame fall itself): GAME_OVER now gates the whole movement chain, so
# once the fall finishes the ship must stay pinned at the hide corner and
# never fall through to the normal joystick-input branch again, no matter
# how many more frames run.
for _ in range(5):
    step_frame(z)
    assert z.rd(PLAYERX) == 255 and z.rd(PLAYERY) == 199, \
        "ship left the hide corner after the fall finished (input should stay disabled forever)"
check("post-death: the ship stays pinned at the hide corner across further frames "
      "(input permanently ignored once GAME_OVER is set, not just during the fall)",
      z.rd(PLAYERX) == 255 and z.rd(PLAYERY) == 199)

# (2026-09-07、"Mission Failed表示は毎フレーム表示 BG系の処理が入ると
# 上書きで消えてしまうため"): simulate some other BG write clobbering the
# message region (exactly the failure mode described), then confirm the
# very next frame's UPDATE_GAME_OVER_SEQUENCE call redraws it unprompted.
for i in range(12 * 32 + 9, 12 * 32 + 9 + GAME_OVER_MSG_LEN):
    z.vram[0x1800 + i] = 0x33
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAME_OVER_MSG_LEN]
check("(setup) message region really is clobbered before the next frame",
      all(b == 0x33 for b in msg_region))
step_frame(z)
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAME_OVER_MSG_LEN]
check("MISSION FAILED text: redrawn every frame while GAME_OVER_SEQ is 1 or 2, so it "
      "self-heals the very next frame after any other BG write clobbers it",
      msg_region == read_msg(GAME_OVER_MSG, GAME_OVER_MSG_LEN))

# regression guard: PLAYERX overflow clamps at 255 instead of wrapping to a
# low value (would look like the ship teleporting to the top-left); PLAYERY
# overflow is treated the same as legitimately reaching the off-screen
# threshold (clamped to 199, completing the fall immediately) rather than
# wrapping to a tiny value that would look like the ship reappearing near
# the top of the screen.
z = fresh()
boot(z)
z.wr(PLAYERX, 254)
z.wr(PLAYERY, 254)
z.wr(GAME_OVER, 1)
z.wr(PLAYER_DEATH_FALL_ACT, 1)
z.pc = sym["MAINLOOP"]
step_frame(z)
check("death-fall: PLAYERX clamps at 255 on overflow instead of wrapping to a low value",
      z.rd(PLAYERX) == 255)
check("death-fall: PLAYERY overflow is treated as reaching the off-screen threshold "
      "(clamped to 199, fall completes) instead of wrapping to a low on-screen value",
      z.rd(PLAYERY) == 199 and z.rd(PLAYER_DEATH_FALL_ACT) == 0 and z.rd(GAME_OVER_SEQ) == 1)

# regression guard: UPDATE_GAME_OVER_SEQUENCE must NOT redraw once SEQ==3
# (terminal - about to bank-switch away in the real Comb build; drawing
# there would just be wasted work, and this also confirms the CP 3 guard
# added alongside the redraw-every-frame change is wired correctly).
z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 3)
for i in range(768):
    z.vram[0x1800 + i] = 0x33
call_routine(z, sym["UPDATE_GAME_OVER_SEQUENCE"])
nametable = [z.vram[0x1800 + i] for i in range(768)]
check("UPDATE_GAME_OVER_SEQUENCE: does NOT redraw the text once SEQ==3 (terminal state)",
      all(b == 0x33 for b in nametable))

# ---- UPDATE_STAGE_CLEAR: 4-state machine (0/1/2/3) ----
z = fresh()
boot(z)
z.wr(STAGE_CLEAR_ACT, 1)
z.wr(SC_VBLANK_COUNT, 100 & 0xFF); z.wr(SC_VBLANK_COUNT + 1, 100 >> 8)
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check(f"UPDATE_STAGE_CLEAR: stays ACT=1 one tick before STAGE_CLEAR_TOTAL_TICKS"
      f"({STAGE_CLEAR_TOTAL_TICKS}) elapses (t=100)",
      z.rd(STAGE_CLEAR_ACT) == 1)

z = fresh()
boot(z)
for i in range(768):
    z.vram[0x1800 + i] = 0x55
z.wr(STAGE_CLEAR_ACT, 1)
z.wr(BGM_MUTED, 0)
elapsed = STAGE_CLEAR_TOTAL_TICKS
z.wr(SC_VBLANK_COUNT, elapsed & 0xFF); z.wr(SC_VBLANK_COUNT + 1, elapsed >> 8)
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR: ACT 1->2 exactly when STAGE_CLEAR_TOTAL_TICKS elapses",
      z.rd(STAGE_CLEAR_ACT) == 2)
check("UPDATE_STAGE_CLEAR: ACT 1->2 transition calls MUTE_BGM", z.rd(BGM_MUTED) == 1)
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 11: 12 * 32 + 11 + 9]
check("UPDATE_STAGE_CLEAR: ACT 1->2 transition draws MISSION2_MSG (black screen + text)",
      msg_region == read_msg(MISSION2_MSG))
new_start = z.rd(SC_START_TICK) | (z.rd(SC_START_TICK + 1) << 8)
check("UPDATE_STAGE_CLEAR: ACT 1->2 transition re-snapshots SC_START_TICK to SC_VBLANK_COUNT",
      new_start == elapsed)

# ACT==2: still not enough real time elapsed for MISSION_SCREEN_TICKS
z.wr(SC_VBLANK_COUNT, (elapsed + MISSION_SCREEN_TICKS - 1) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (elapsed + MISSION_SCREEN_TICKS - 1) >> 8)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check(f"UPDATE_STAGE_CLEAR: stays ACT=2 one tick before MISSION_SCREEN_TICKS"
      f"({MISSION_SCREEN_TICKS}) elapses",
      z.rd(STAGE_CLEAR_ACT) == 2)

z.wr(SC_VBLANK_COUNT, (elapsed + MISSION_SCREEN_TICKS) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (elapsed + MISSION_SCREEN_TICKS) >> 8)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR: ACT 2->3 exactly when MISSION_SCREEN_TICKS elapses "
      "(build_full_rom.py's Comb-only bank switch now gates on ACT==3)",
      z.rd(STAGE_CLEAR_ACT) == 3)

# ACT==3: terminal, must stay a no-op forever
z.wr(STAGE_CLEAR_ACT, 3)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR: ACT==3 is a no-op (terminal state, never re-triggers)",
      z.rd(STAGE_CLEAR_ACT) == 3)

# ACT==0: not yet triggered, must stay a no-op
z.wr(STAGE_CLEAR_ACT, 0)
call_routine(z, sym["UPDATE_STAGE_CLEAR"])
check("UPDATE_STAGE_CLEAR: ACT==0 is a no-op (not yet triggered)",
      z.rd(STAGE_CLEAR_ACT) == 0)

# ---- MAINLOOP top-of-loop freeze while STAGE_CLEAR_ACT>=2 ----
z = fresh()
boot(z)
z.wr(PLAYERX, 123)
z.wr(STAGE_CLEAR_ACT, 2)
elapsed = 500
z.wr(SC_VBLANK_COUNT, elapsed & 0xFF); z.wr(SC_VBLANK_COUNT + 1, elapsed >> 8)
z.wr(SC_START_TICK, elapsed & 0xFF); z.wr(SC_START_TICK + 1, elapsed >> 8)
step_frame(z)
check("MAINLOOP freeze: PLAYERX untouched while STAGE_CLEAR_ACT==2 (rest of the frame skipped)",
      z.rd(PLAYERX) == 123)
check("MAINLOOP freeze: UPDATE_STAGE_CLEAR is still invoked every frame while frozen "
      "(real-time 3-second timer keeps advancing)",
      z.rd(STAGE_CLEAR_ACT) == 2)
# advance real time past MISSION_SCREEN_TICKS across further frozen frames
for _ in range(3):
    hl = z.rd(SC_VBLANK_COUNT) | (z.rd(SC_VBLANK_COUNT + 1) << 8)
    hl = (hl + 1) & 0xFFFF
    z.wr(SC_VBLANK_COUNT, hl & 0xFF); z.wr(SC_VBLANK_COUNT + 1, hl >> 8)
    step_frame(z)
z.wr(SC_VBLANK_COUNT, (elapsed + MISSION_SCREEN_TICKS) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (elapsed + MISSION_SCREEN_TICKS) >> 8)
step_frame(z)
check("MAINLOOP freeze: ACT reaches 3 (done) via the frozen loop's own UPDATE_STAGE_CLEAR calls, "
      "still without ever touching PLAYERX",
      z.rd(STAGE_CLEAR_ACT) == 3 and z.rd(PLAYERX) == 123)

# a regression guard: without the freeze check, the terrain-scroll/enemy update code
# further down MAINLOOP would still run and could touch PLAYERX/VRAM - explicitly confirm
# the freeze branch is really what's responsible by checking PC never reaches the
# post-freeze body's own well-known anchor (BOSS_STATE read) while ACT>=2.
z = fresh()
boot(z)
z.wr(STAGE_CLEAR_ACT, 2)
z.wr(SC_VBLANK_COUNT, 0); z.wr(SC_VBLANK_COUNT + 1, 0)
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
boss_state_read_hit = [False]
orig_step = z.step
visited_pcs = set()
for _ in range(20000):
    visited_pcs.add(z.pc)
    if z.pc == sym["MAINLOOP"] and len(visited_pcs) > 1:
        break
    z.step()
check("MAINLOOP freeze: the frozen path's instruction trace never reaches STAGE_CLEAR_NOT_FROZEN "
      "(the label marking the start of normal per-frame gameplay logic)",
      sym["STAGE_CLEAR_NOT_FROZEN"] not in visited_pcs)

# (2026-09-07、実機フィードバック対応、"以前にも同じミスがあって止めた
# のに再発してる...飛び去るノイズ音がMission 2と出ている間鳴りっぱなし"):
# 旧実装は"STAGE_CLEAR_ACT!=1ならSOUND_UPDATEを呼ぶ"だったため、ACTが
# 1->2へ遷移するまさにそのフレーム内で(DRAW_MISSION_SCREENがR8=0を
# 書いた直後に)SOUND_UPDATEが誤って再度呼ばれ、エンジン音(ノイズ)の
# 音量計算でR8を上書きしてしまっていた。実際にMAINLOOPを1フレーム
# 進めてこの遷移を再現し、フレーム終了時点でR8が本当に0のままである
# ことを検証する(call_routine(UPDATE_STAGE_CLEAR)単体呼び出しでは
# MAINLOOP側のこのSOUND_UPDATE呼び出しガードを一切経由しないため検出
# できない - 実際にstep_frame()でMAINLOOP全体を回す必要がある)。
SND_TONE_TIMER = sym["SND_TONE_TIMER"]
z = fresh()
boot(z)
z.wr(PLAYER_FLYAWAY, 2)  # required for MAINLOOP to actually reach the real
                          # UPDATE_STAGE_CLEAR call site (PFA_SC_ALREADY_TRIGGERED) -
                          # call_routine(UPDATE_STAGE_CLEAR) alone wouldn't exercise
                          # the surrounding MAINLOOP body this bug lives in
z.wr(STAGE_CLEAR_ACT, 1)
z.wr(BGM_MUTED, 0)
elapsed = STAGE_CLEAR_TOTAL_TICKS
z.wr(SC_VBLANK_COUNT, elapsed & 0xFF); z.wr(SC_VBLANK_COUNT + 1, elapsed >> 8)
z.wr(SC_START_TICK, 0); z.wr(SC_START_TICK + 1, 0)
# (SND_TONE_TIMER used instead of SND_TIMER[noise] as the reproduction signal:
# the noise channel's own duty gate (CALC_NOISE_GATE_VOLUME, AND 1 on TICK)
# would make a naive test flaky depending on TICK's parity at boot; the tone
# branch writes unconditionally whenever nonzero, giving a deterministic signal
# for "did SOUND_UPDATE get invoked at all" regardless of which of its 3
# internal branches actually fires - confirmed reproducing the bug directly
# against the pre-fix code before writing this test).
z.wr(SND_TONE_TIMER, 10)
z.psg_regs[8] = 15   # a nonzero R8 already on the chip from a prior frame
step_frame(z)
check("engine-noise regression: STAGE_CLEAR_ACT really did cross 1->2 during this frame",
      z.rd(STAGE_CLEAR_ACT) == 2)
check("engine-noise regression: PSG R8 (channel A volume) is silenced (0) at the end of the "
      "very frame the MISSION 2 screen appears, not re-armed by a stray SOUND_UPDATE call",
      z.psg_regs.get(8) == 0)
for _ in range(5):
    step_frame(z)
check("engine-noise regression: R8 stays silenced across further frozen frames while "
      "MISSION 2 remains on screen (SOUND_UPDATE never runs again once STAGE_CLEAR_ACT!=0)",
      z.psg_regs.get(8) == 0)

# ---- retreat-to-left-edge before flyaway ----
z = fresh()
boot(z)
z.wr(PLAYERX, 100)
z.wr(PLAYER_RETREAT_ACT, 1)
z.wr(PLAYER_FLYAWAY, 0)
z.wr(PLAYER_FLYAWAY_WAIT, 0)
prev_x = 100
steps = 0
while z.rd(PLAYER_RETREAT_ACT) != 0 and steps < 200:
    step_frame(z)
    steps += 1
    cur_x = z.rd(PLAYERX)
    if steps < 100 // PLAYER_RETREAT_SPEED:
        check_label = f"retreat step {steps}: PLAYERX decreases by PLAYER_RETREAT_SPEED " \
                      f"({PLAYER_RETREAT_SPEED}) per frame (was {prev_x}, now {cur_x})"
        if not (prev_x - cur_x == PLAYER_RETREAT_SPEED or cur_x == 0):
            check(check_label, False)
    prev_x = cur_x
check("retreat: PLAYERX reaches exactly 0 (never wraps/undershoots past the left edge)",
      z.rd(PLAYERX) == 0)
check("retreat: PLAYER_RETREAT_ACT clears once X==0", z.rd(PLAYER_RETREAT_ACT) == 0)
check("retreat: reaching X==0 arms the existing flyaway-wait sequence (PLAYER_FLYAWAY_WAIT=40)",
      z.rd(PLAYER_FLYAWAY_WAIT) == 40)
check("retreat: reaching X==0 arms the existing flyaway speed (PLAYER_FLYAWAY_SPD=1)",
      z.rd(PLAYER_FLYAWAY_SPD) == 1)
check("retreat: PLAYER_FLYAWAY itself stays 0 until the existing PFA_FLYAWAY_IDLE wait "
      "counts down (unchanged downstream behavior)",
      z.rd(PLAYER_FLYAWAY) == 0)

# retreat already at X=0: must complete in a single frame, no off-by-one stall
z = fresh()
boot(z)
z.wr(PLAYERX, 0)
z.wr(PLAYER_RETREAT_ACT, 1)
step_frame(z)
check("retreat: starting already at X=0 completes the retreat sub-phase in the very first frame",
      z.rd(PLAYER_RETREAT_ACT) == 0 and z.rd(PLAYER_FLYAWAY_WAIT) == 40)

# boss-death trigger arms PLAYER_RETREAT_ACT, not PLAYER_FLYAWAY_WAIT directly
z = fresh()
boot(z)
z.wr(BOSS_EXPL_ACTIVE, 1)
z.wr(BOSS_EXPL_INDEX, BOSS_EXPL_COUNT & 0xFF)
z.wr(sym["BOSS_EXPL_TIMER"], 1)
z.wr(PLAYER_RETREAT_ACT, 0)
z.wr(PLAYER_FLYAWAY_WAIT, 0)
z.wr(SND_TONE_TIMER, 77)
call_routine(z, sym["BOSS_EXPL_UPDATE"])
check("boss-death trigger: BOSS_EXPL_UPDATE's own completion now arms PLAYER_RETREAT_ACT=1",
      z.rd(PLAYER_RETREAT_ACT) == 1)
check("boss-death trigger: PLAYER_FLYAWAY_WAIT is NOT armed directly any more "
      "(that now happens once the retreat sub-phase finishes)",
      z.rd(PLAYER_FLYAWAY_WAIT) == 0)
check("boss-death trigger: BOSS_EXPL_ACTIVE still cleared as before", z.rd(BOSS_EXPL_ACTIVE) == 0)
check("boss-death trigger: SND_TONE_TIMER still cleared as before", z.rd(SND_TONE_TIMER) == 0)

# boot: PLAYER_RETREAT_ACT must be explicitly zero-initialized (init_ram_poison_test-style lesson)
z = fresh()
z.wr(PLAYER_RETREAT_ACT, 0xFF)
boot(z)
check("boot: PLAYER_RETREAT_ACT is explicitly zero-initialized in INIT even from all-0xFF RAM "
      "(round36-14 follow-up#14 lesson: never rely on RAM happening to already be 0)",
      z.rd(PLAYER_RETREAT_ACT) == 0)

# ---- boot: GAME_OVER_SEQ/GAME_OVER_START_TICK must be explicitly zero- ----
# ---- initialized too (same round36-14 follow-up#14 lesson) - unlike    ----
# ---- GAMEOVER_ENABLED, which must NOT be cleared (Title sets it)       ----
GAME_OVER_START_TICK = sym["GAME_OVER_START_TICK"]
GAMEOVER_ENABLED = sym["GAMEOVER_ENABLED"]
z = fresh()
z.wr(GAME_OVER_SEQ, 0xFF)
z.wr(GAME_OVER_START_TICK, 0xFF); z.wr(GAME_OVER_START_TICK + 1, 0xFF)
z.wr(GAMEOVER_ENABLED, 0x42)
boot(z)
check("boot: GAME_OVER_SEQ is explicitly zero-initialized in INIT even from all-0xFF RAM",
      z.rd(GAME_OVER_SEQ) == 0)
check("boot: GAME_OVER_START_TICK is explicitly zero-initialized in INIT even from all-0xFF RAM",
      z.rd(GAME_OVER_START_TICK) == 0 and z.rd(GAME_OVER_START_TICK + 1) == 0)
check("boot: GAMEOVER_ENABLED is NOT touched by INIT (Title sets this before Stage1 boots, "
      "any INIT clear would silently discard the A/B button choice)",
      z.rd(GAMEOVER_ENABLED) == 0x42)

# ---- UPDATE_GAME_OVER_SEQUENCE: 3-state machine (1=3sec text/2=button- ----
# ---- or-10sec-timeout wait/3=ready to return to title)                 ----
UPDATE_GAME_OVER_SEQUENCE = sym["UPDATE_GAME_OVER_SEQUENCE"]
GAME_OVER_TEXT_TICKS = sym["GAME_OVER_TEXT_TICKS"]
GAME_OVER_TIMEOUT_TICKS = sym["GAME_OVER_TIMEOUT_TICKS"]

z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 1)
z.wr(GAME_OVER_START_TICK, 0); z.wr(GAME_OVER_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, (GAME_OVER_TEXT_TICKS - 1) & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, (GAME_OVER_TEXT_TICKS - 1) >> 8)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check(f"UPDATE_GAME_OVER_SEQUENCE: stays SEQ=1 one tick before GAME_OVER_TEXT_TICKS"
      f"({GAME_OVER_TEXT_TICKS}) elapses", z.rd(GAME_OVER_SEQ) == 1)

z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 1)
z.wr(GAME_OVER_START_TICK, 0); z.wr(GAME_OVER_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, GAME_OVER_TEXT_TICKS & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, GAME_OVER_TEXT_TICKS >> 8)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check("UPDATE_GAME_OVER_SEQUENCE: SEQ 1->2 exactly when GAME_OVER_TEXT_TICKS elapses",
      z.rd(GAME_OVER_SEQ) == 2)
new_start = z.rd(GAME_OVER_START_TICK) | (z.rd(GAME_OVER_START_TICK + 1) << 8)
check("UPDATE_GAME_OVER_SEQUENCE: SEQ 1->2 transition re-snapshots GAME_OVER_START_TICK",
      new_start == GAME_OVER_TEXT_TICKS)

# SEQ==2: no button, time not yet elapsed -> stays SEQ=2
z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 2)
z.wr(GAME_OVER_START_TICK, 0); z.wr(GAME_OVER_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, 0); z.wr(SC_VBLANK_COUNT + 1, 0)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check("UPDATE_GAME_OVER_SEQUENCE: stays SEQ=2 with no button input and time not yet elapsed",
      z.rd(GAME_OVER_SEQ) == 2)

# SEQ==2: button press (GTTRIG trigger A, sim_trig_a) immediately advances
# to SEQ=3 even though the 10-second timeout hasn't elapsed.
z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 2)
z.wr(GAME_OVER_START_TICK, 0); z.wr(GAME_OVER_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, 0); z.wr(SC_VBLANK_COUNT + 1, 0)
z.sim_trig_a = True
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check("UPDATE_GAME_OVER_SEQUENCE: SEQ 2->3 on a button press, before the 10-second timeout",
      z.rd(GAME_OVER_SEQ) == 3)

# SEQ==2: timeout (10 seconds) advances to SEQ=3 even without a button
z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 2)
z.wr(GAME_OVER_START_TICK, 0); z.wr(GAME_OVER_START_TICK + 1, 0)
z.wr(SC_VBLANK_COUNT, GAME_OVER_TIMEOUT_TICKS & 0xFF)
z.wr(SC_VBLANK_COUNT + 1, GAME_OVER_TIMEOUT_TICKS >> 8)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check(f"UPDATE_GAME_OVER_SEQUENCE: SEQ 2->3 when GAME_OVER_TIMEOUT_TICKS"
      f"({GAME_OVER_TIMEOUT_TICKS}) elapses with no button press",
      z.rd(GAME_OVER_SEQ) == 3)

z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 3)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check("UPDATE_GAME_OVER_SEQUENCE: SEQ==3 is a no-op (terminal state)", z.rd(GAME_OVER_SEQ) == 3)

z = fresh()
boot(z)
z.wr(GAME_OVER_SEQ, 0)
call_routine(z, UPDATE_GAME_OVER_SEQUENCE)
check("UPDATE_GAME_OVER_SEQUENCE: SEQ==0 is a no-op (not yet triggered)", z.rd(GAME_OVER_SEQ) == 0)

# ---- GAMEOVER_ENABLED==0 gating: barrier-exhausted hit no longer      ----
# ---- reaches PTH_GAMEOVER, matching round37's original "0になっても   ----
# ---- 死なない" behavior ("Bボタンならゲームオーバー無しに")            ----
z = fresh()
boot(z)
z.wr(GAMEOVER_ENABLED, 0)
z.wr(BARRIER_HP, 0)
for i in range(768):
    z.vram[0x1800 + i] = 0x33
call_routine(z, sym["PLAYER_TAKE_HIT"])
nametable = [z.vram[0x1800 + i] for i in range(768)]
msg_region = nametable[12 * 32 + 9: 12 * 32 + 9 + GAME_OVER_MSG_LEN]
check("PLAYER_TAKE_HIT with GAMEOVER_ENABLED=0: does NOT set GAME_OVER",
      z.rd(GAME_OVER) == 0)
check("PLAYER_TAKE_HIT with GAMEOVER_ENABLED=0: does NOT draw the MISSION FAILED text",
      all(b == 0x33 for b in msg_region))
check("PLAYER_TAKE_HIT with GAMEOVER_ENABLED=0: BARRIER_HP stays at 0 (no underflow)",
      z.rd(BARRIER_HP) == 0)

z = fresh()
boot(z)
z.wr(GAMEOVER_ENABLED, 1)
z.wr(BARRIER_HP, 0)
call_routine(z, sym["PLAYER_TAKE_HIT"])
check("PLAYER_TAKE_HIT with GAMEOVER_ENABLED=1: DOES set GAME_OVER (regression guard - "
      "confirms the GAMEOVER_ENABLED gate itself works both ways)",
      z.rd(GAME_OVER) == 1)

# (2026-09-07、実機フィードバック対応、"画面外に出る処理で壊れたと
# 思われる"の調査で発見・修正した実バグ): 既にGAME_OVER=1(死亡演出
# 進行中〜表示中)の間に追加で被弾しても、PTH_GAMEOVERが再実行されて
# PLAYER_EXPL_TRIGGER/PLAYER_DEATH_FALL_TRIGGER/SOUND_DESTROYを重ねて
# 再発火してはならない(旧実装にはこのガードが無く、死亡落下が可変長化
# [round65]したことで再トリガーの機会自体が大幅に増えていた)。
# PLAYER_EXPL_TOTAL_TIMER(PLAYER_EXPL_TRIGGERが呼ばれるたびPLAYER_
# EXPL_TOTAL_LEN[120]へリセットされる)を判別に使う - 途中の値のまま
# 変化しなければ再トリガーされていない証拠になる。
PLAYER_EXPL_TOTAL_TIMER = sym["PLAYER_EXPL_TOTAL_TIMER"]
z = fresh()
boot(z)
z.wr(GAMEOVER_ENABLED, 1)  # must be 1, else PTH_GAMEOVER is unreachable for an
                           # unrelated reason and this test wouldn't actually
                           # exercise the GAME_OVER re-trigger guard at all
z.wr(GAME_OVER, 1)
z.wr(PLAYER_DEATH_FALL_ACT, 1)
z.wr(PLAYER_EXPL_TOTAL_TIMER, 3)  # mid-burst, well below PLAYER_EXPL_TOTAL_LEN(120)
z.wr(BARRIER_HP, 0)  # already exhausted, as it always is once GAME_OVER=1
call_routine(z, sym["PLAYER_TAKE_HIT"])
check("PLAYER_TAKE_HIT while GAME_OVER is already 1: does NOT re-run PTH_GAMEOVER "
      "(PLAYER_EXPL_TOTAL_TIMER stays at its mid-burst value instead of being reset "
      "back to PLAYER_EXPL_TOTAL_LEN by a re-triggered PLAYER_EXPL_TRIGGER - the death "
      "sequence already in progress must not be re-armed by a further hit)",
      z.rd(PLAYER_EXPL_TOTAL_TIMER) == 3)

# ---- (2026-09-07、実機フィードバック対応、"ステージ1で画面が壊れる原因が
# 分かった 爆発処理で操作無効で落下していく時に弾を撃った状態で死ぬと
# 弾を撃ったまま画面外に出てVRAM壊してる つまり操作無効と同時に弾打つのを
# 停止すれば解決する"): 実際の再現条件は「トリガーを押しっぱなしのまま
# 死ぬ」ケース - 死亡落下が始まった瞬間、方向入力の読み取り自体が
# PFA_DEATH_FALL_STEPへ丸ごと迂回されるため、JOY_TRIG(GTTRIGの結果を
# 保持するRAM変数)を毎フレーム更新するスキャン処理も一緒に迂回され、
# 死んだ瞬間の値(押していれば0FFh)のまま以後ずっと"凍結"する - 発射
# チェック自体は独立してPLAYER_FLYAWAYしか見ていなかったため、この
# "凍結して押しっぱなし"状態のJOY_TRIGにFIRE_COOLDOWNが0になるたび
# 反応し、死亡落下中ずっと新規弾を吐き続けていた。この時PLAYERYは
# 死亡落下によって異常な値(150〜199)まで直線的に増加し続けており、
# 新規弾のBULLET0_ROWはこの生のPLAYERYから計算されるため、24行[0-23]
# しか正当なエントリを持たないROWADDR_LO/HIテーブルを範囲外indexで
# 読んでしまい、直後のPATTERNS(キャラクタパターンデータ)領域から
# 拾った値がそのまま不定のVRAM書き込みアドレスになる(実際に
# PLAYERY=199で再現・確認済み: ROW=25、結果のアドレスはカラー
# テーブル近辺0x2B00相当まで飛ぶ) - これが実機で報告された画面全体の
# 色/絵柄破損の直接原因だった。GAME_OVER=1の間は発射自体も完全に
# 止めることで、この不正な弾の発生源を断つ。
BULLET0_ACT = sym["BULLET0_ACT"]
BULLET0_ROW = sym["BULLET0_ROW"]
BULLET0_ADDR = sym["BULLET0_ADDR"]
FIRE_COOLDOWN = sym["FIRE_COOLDOWN"]
JOY_TRIG = sym["JOY_TRIG"]

z = fresh()
boot(z)
z.sim_trig_a = True
step_frame(z)  # a normal frame, still alive - legitimately latches JOY_TRIG=0FFh via the real scan
assert z.rd(JOY_TRIG) == 0xFF, "test setup: JOY_TRIG didn't actually latch 'pressed'"
# now the ship dies mid-frame (as PLAYER_TAKE_HIT/PTH_GAMEOVER would do) -
# JOY_TRIG is deliberately left untouched (== still 0FFh, "frozen" exactly
# as it would be for real, since the scan that would refresh it never runs
# again once death-fall begins).
z.wr(GAME_OVER, 1)
z.wr(PLAYER_DEATH_FALL_ACT, 1)
z.wr(PLAYERY, 199)  # deep into the death-fall, well past the 24-row screen (0-23)
z.wr(BULLET0_ACT, 0)
z.wr(BULLET0_ROW, 0xAA)   # sentinel - must stay untouched if no spawn is attempted
z.wr(BULLET0_ADDR, 0xAA); z.wr(BULLET0_ADDR + 1, 0xAA)
z.wr(FIRE_COOLDOWN, 0)
step_frame(z)
check("a JOY_TRIG frozen 'pressed' from just before death (the real-world scenario - "
      "dying while holding fire) does NOT spawn a new bullet once GAME_OVER=1 - closes "
      "the VRAM-corruption source (an out-of-range PLAYERY would compute a bogus "
      "ROWADDR_LO/HI table index, spilling into the PATTERNS data right after it)",
      z.rd(BULLET0_ACT) == 0 and z.rd(BULLET0_ROW) == 0xAA and
      z.rd(BULLET0_ADDR) == 0xAA and z.rd(BULLET0_ADDR + 1) == 0xAA)

# ---- sanity: the same frozen-trigger setup with GAME_OVER=0 (normal play, JOY_TRIG ----
# ---- just happens to still read pressed) still fires normally - this fix must not  ----
# ---- accidentally suppress ordinary firing.                                        ----
z2 = fresh()
boot(z2)
z2.sim_trig_a = True
step_frame(z2)
z2.wr(GAME_OVER, 0)
z2.wr(PLAYER_DEATH_FALL_ACT, 0)
z2.wr(PLAYERY, 100)  # ordinary in-screen Y
z2.wr(BULLET0_ACT, 0)
z2.wr(FIRE_COOLDOWN, 0)
step_frame(z2)
check("...but normal play (GAME_OVER=0) still fires a new bullet as usual - the new "
      "GAME_OVER gate doesn't regress ordinary firing",
      z2.rd(BULLET0_ACT) == 1)


print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
