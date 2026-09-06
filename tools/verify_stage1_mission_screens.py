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

# ---- boot-time VRAM load: font pattern + color ----
z = fresh()
boot(z)
expected_font = {
    0: [0, 130, 198, 170, 146, 130, 130, 130],
    1: [0, 248, 32, 32, 32, 32, 32, 248],
    2: [0, 120, 132, 128, 120, 2, 132, 120],
    3: [0, 120, 132, 132, 132, 132, 132, 120],
    4: [0, 132, 196, 164, 148, 140, 132, 132],
    5: [0, 0, 0, 0, 0, 0, 0, 0],
}
font_ok = True
for offset, bytes_ in expected_font.items():
    code = MISSION_FONT_BASE + offset
    got = [z.vram[code * 8 + i] for i in range(8)]
    if got != bytes_:
        font_ok = False
check("boot: MISSION_FONT_PATTERNS (M,I,S,O,N,space) loaded byte-correct at "
      "MISSION_FONT_BASE(64)..+5 in the pattern generator table", font_ok)
check("boot: group8 (codes64-71) color byte at VRAM 2008h patched to white/black (0F1h)",
      z.vram[0x2008] == 0xF1)

# ---- MISSION1_MSG / MISSION2_MSG content ----
def read_msg(addr):
    return [mem0[addr + i] for i in range(9)]

expected_msg_prefix = [MISSION_FONT_BASE + 0, MISSION_FONT_BASE + 1, MISSION_FONT_BASE + 2,
                       MISSION_FONT_BASE + 2, MISSION_FONT_BASE + 1, MISSION_FONT_BASE + 3,
                       MISSION_FONT_BASE + 4, MISSION_FONT_BASE + 5]
check("MISSION1_MSG = 'MISSION' + space + digit(DIGIT_BASE+1)",
      read_msg(MISSION1_MSG) == expected_msg_prefix + [DIGIT_BASE + 1])
check("MISSION2_MSG = 'MISSION' + space + digit(DIGIT_BASE+2)",
      read_msg(MISSION2_MSG) == expected_msg_prefix + [DIGIT_BASE + 2])

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
rest_is_black = all(b == MISSION_FONT_BASE + 5 for i, b in enumerate(nametable)
                     if not (12 * 32 + 11 <= i < 12 * 32 + 11 + 9))
check("DRAW_MISSION_SCREEN: entire 768-byte name table filled with the SPACE glyph "
      "(MISSION_FONT_BASE+5) except the message region", rest_is_black)
check("DRAW_MISSION_SCREEN: message region (row12,col11..19) matches MISSION1_MSG",
      msg_region == read_msg(MISSION1_MSG))
check("DRAW_MISSION_SCREEN: sprite attribute table's first Y forced to 209 (hides all sprites)",
      z.vram[0x1B00] == 209)

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

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
