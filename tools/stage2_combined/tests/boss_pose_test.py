import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

GAME_TICK = sym["GAME_TICK"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_DIR = sym["BOSS_DIR"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_POSE_END_TICK = sym["BOSS_POSE_END_TICK"]
BOSS_POSE_TICKS = sym["BOSS_POSE_TICKS"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPEED = sym["BOSS_SPEED"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
SASAPI_HAND_CODE_BASE = sym["SASAPI_HAND_CODE_BASE"]
HUD_ROW_BLANK_CODE = sym["HUD_ROW_BLANK_CODE"]
SASAPI_QUADS = sym["SASAPI_QUADS"]
SASAPI_QUADS_L = sym["SASAPI_QUADS_L"]
SPRPAT = sym["SPRPAT"]
PAT_SASAPI = sym["PAT_SASAPI"]
BOSS_FLASH_TIMER = sym["BOSS_FLASH_TIMER"]
SASAPI_HAND_COLORBYTE = sym["SASAPI_HAND_COLORBYTE"]
SASAPI_HAND_FLASH_COLORBYTE = sym["SASAPI_HAND_FLASH_COLORBYTE"]

HAND_COLOR_ADDRS = list(range(0x2000 + 19, 0x2000 + 27))


def hand_colors_are(cpu, byte_value):
    return all(cpu.vram[a] == byte_value for a in HAND_COLOR_ADDRS)

SAT_BASE = 0x1B00
HAND_ROW_ADDRS = [0x18F8, 0x1918, 0x1938, 0x1958, 0x1978, 0x1998, 0x19B8, 0x19D8]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def get_game_tick(cpu):
    return cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)


def sprpat_matches(cpu, rom_label):
    base = SPRPAT + PAT_SASAPI * 8
    rom_bytes = [out[rom_label + i] for i in range(16 * 32)]
    return rom_bytes == list(cpu.vram[base: base + 16 * 32])


def all_hand_codes_present(cpu):
    for i, addr in enumerate(HAND_ROW_ADDRS):
        row_codes = list(cpu.vram[addr:addr + 8])
        expected = [SASAPI_HAND_CODE_BASE + i * 8 + j for j in range(8)]
        if row_codes != expected:
            return False
    return True


def all_hand_cells_night(cpu):
    for addr in HAND_ROW_ADDRS:
        if list(cpu.vram[addr:addr + 8]) != [HUD_ROW_BLANK_CODE] * 8:
            return False
    return True


def all_sprites_hidden(cpu):
    return all(cpu.vram[SAT_BASE + (BOSS_SPR_BASE_SLOT + i) * 4] == 209 for i in range(16))


# ---- spawn the boss ----
# round34 ("全てスケジュールに"): S2_BOSS_SPAWN has no GAME_TICK check
# of its own any more (that moved to the shared SPAWN2_SCHEDULE_CHECK/
# SSC2_FIRE dispatcher) - it always succeeds whenever called directly.
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
check("boss spawns with BOSS_PHASE=0 (patrolling)", cpu.mem[BOSS_PHASE] == 0)
check("boss spawns at BOSS_SPAWNX", cpu.mem[BOSS_X] == BOSS_SPAWNX)
# follow-up#20 ("ワイプ中は初期停止状態のスプライトでワイプが終わるまで
# 停止すること"): UBA_ACTIVE now freezes all patrol/pose movement
# entirely while the entrance wipe is active (BOSS_WIPE_ACT!=0, seeded
# by S2_BOSS_SPAWN itself). This file tests the patrol/pose state
# machine itself, unrelated to the wipe - bypass it here so the boss
# actually moves like every test below already assumes (see
# boss_wipe_test.py for the freeze's own dedicated coverage).
cpu.mem[sym["BOSS_WIPE_ACT"]] = 0

# ---- drive it to the left edge - now pauses briefly (BOSS_PHASE=2)
# before reversing - "左端は2Tick停止してから反転発射に" (round10) ----
steps = 0
while cpu.mem[BOSS_X] > 0 and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    steps += 1
call_routine(cpu, "UPDATE_BOSS_ALL")
check("enters the left-edge pause (BOSS_PHASE=2) instead of reversing immediately",
      cpu.mem[BOSS_PHASE] == 2 and cpu.mem[BOSS_X] == 0)
# UPDATE_BOSS_ALL never advances GAME_TICK itself (only real MAINLOOP
# does) - set it forward directly, same pattern already used below for
# BOSS_POSE_TICKS.
BOSS_LEFT_PAUSE_TICKS = sym["BOSS_LEFT_PAUSE_TICKS"]
tick_at_pause = get_game_tick(cpu)
set_game_tick(cpu, tick_at_pause + BOSS_LEFT_PAUSE_TICKS)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("left-edge reversal is still a normal patrol reversal (DIR=1, moving right) once the pause elapses",
      cpu.mem[BOSS_DIR] == 1 and cpu.mem[BOSS_PHASE] == 0)
check("left-edge reversal reloads the mirrored facing (unchanged from before this round)",
      sprpat_matches(cpu, SASAPI_QUADS_L))

# ---- drive it back to the right edge - THIS should now enter the attack pose ----
steps = 0
while cpu.mem[BOSS_X] < BOSS_SPAWNX and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    steps += 1
check("returns to X=BOSS_SPAWNX exactly before the pose-entry call", cpu.mem[BOSS_X] == BOSS_SPAWNX)
tick_before_pose = get_game_tick(cpu)
call_routine(cpu, "UPDATE_BOSS_ALL")   # this call clamps X and enters the pose
check("returning to the right edge enters the attack pose (BOSS_PHASE=1) - 攻撃ポーズ",
      cpu.mem[BOSS_PHASE] == 1)
check("BOSS_POSE_END_TICK is armed to GAME_TICK+BOSS_POSE_TICKS(32)",
      cpu.mem[BOSS_POSE_END_TICK] | (cpu.mem[BOSS_POSE_END_TICK + 1] << 8)
      == tick_before_pose + BOSS_POSE_TICKS)
check("the sprite is hidden the instant the pose starts - スプライトは一旦消す",
      all_sprites_hidden(cpu))
check("the hand art's own 64 codes are drawn at the expected name-table cells - BGに描画",
      all_hand_codes_present(cpu))

# ---- while posing: nothing should move, sprite stays hidden, hand stays drawn ----
x_before = cpu.mem[BOSS_X]
dir_before = cpu.mem[BOSS_DIR]
for _ in range(5):
    call_routine(cpu, "UPDATE_BOSS_ALL")
check("BOSS_X/BOSS_DIR frozen while posing (not yet BOSS_POSE_TICKS ticks later)",
      cpu.mem[BOSS_X] == x_before and cpu.mem[BOSS_DIR] == dir_before)
check("sprite still hidden mid-pose", all_sprites_hidden(cpu))
check("hand art still drawn mid-pose", all_hand_codes_present(cpu))

# a BG-drawn bullet (or anything else) corrupting one of the hand's own
# cells mid-pose should get healed back within 1 more UPDATE_BOSS_ALL
# call - "ボスBG表示欠け発生...復帰処理で対応": DRAW_SASAPI_HAND now
# runs every frame while posing, not just once at entry.
cpu.vram[HAND_ROW_ADDRS[3] + 2] = 0
check("a corrupted hand cell mid-pose is a real corruption (sanity check before healing)",
      not all_hand_codes_present(cpu))
call_routine(cpu, "UPDATE_BOSS_ALL")
check("a corrupted hand cell heals back to the correct code within 1 more frame while still posing",
      all_hand_codes_present(cpu) and cpu.mem[BOSS_PHASE] == 1)

# ---- hit-flash during the pose: "ポーズ中の被弾フラッシュ演出を追加" ----
check("hand color groups are the normal color before any hit", hand_colors_are(cpu, SASAPI_HAND_COLORBYTE))
cpu.mem[BOSS_FLASH_TIMER] = 3
call_routine(cpu, "UPDATE_BOSS_ALL")
check("hand color groups switch to the flash color while the timer is active",
      hand_colors_are(cpu, SASAPI_HAND_FLASH_COLORBYTE))
check("the flash timer decrements once per call (not once per group)",
      cpu.mem[BOSS_FLASH_TIMER] == 2)
# timer was armed to 3, 1 call already consumed (->2, still flashing
# that same frame); 3 more calls bring it 2->1->0 (still flashing on
# the frame that brings it to 0, same "check before decrement" idiom
# every other flash timer in this file uses), then a 4th call finally
# sees timer==0 and reverts to normal.
call_routine(cpu, "UPDATE_BOSS_ALL")
call_routine(cpu, "UPDATE_BOSS_ALL")
call_routine(cpu, "UPDATE_BOSS_ALL")
check("hand color groups revert to normal once the flash timer reaches 0",
      hand_colors_are(cpu, SASAPI_HAND_COLORBYTE) and cpu.mem[BOSS_FLASH_TIMER] == 0)

# ---- advance GAME_TICK to just before the pose ends - still posing ----
set_game_tick(cpu, tick_before_pose + BOSS_POSE_TICKS - 1)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("still posing 1 tick before BOSS_POSE_TICKS elapses", cpu.mem[BOSS_PHASE] == 1)

# ---- advance GAME_TICK to exactly the end tick - pose should end now ----
set_game_tick(cpu, tick_before_pose + BOSS_POSE_TICKS)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("pose ends exactly at GAME_TICK==BOSS_POSE_END_TICK - また巡回",
      cpu.mem[BOSS_PHASE] == 0)
check("resumes moving left (DIR=0) after the pose, same as the original spawn",
      cpu.mem[BOSS_DIR] == 0)
check("the hand art's own cells are restored to plain night-black - BGは消して",
      all_hand_cells_night(cpu))
check("the normal (non-mirrored) facing is reloaded on pose-exit",
      sprpat_matches(cpu, SASAPI_QUADS))
check("the sprite is visible again immediately after the pose ends",
      cpu.vram[SAT_BASE + BOSS_SPR_BASE_SLOT * 4] != 209)

# ---- real end-to-end: a full MAINLOOP sweep through spawn -> left edge ----
# ---- -> right edge -> pose entry -> pose exit -> resumes moving left. ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned_at = None
saw_pose = False
pose_entered_at = None
pose_exited = False
# BOSS_SPAWN_TICK*8 to reach spawn (GAME_TICK boots at real 0 again -
# "Tickスキップを一旦戻して０に") + enough margin for a full patrol
# cycle (left+right, ~192 frames) and the full pose duration
# (BOSS_POSE_TICKS*8) afterward. round34-3 ("全てスケジュールに", then
# "Stage1と全く同じ処理だぞ"): with no player fire input at all (this
# test's own worst-case config), a ground enemy can still go permanently
# un-destroyed, but that no longer stalls anything downstream - a
# blocked spawn is simply dropped (unconditional-advance SSC2_FIRE), so
# the boss reliably spawns right at frame~7959 (tick995) - verified
# empirically (see boss_test.py's own Test12) - well inside this margin.
sweep_frames = 20000 + sym["BOSS_POSE_TICKS"] * 8 + 200
for f in range(sweep_frames):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1:
        if boss_spawned_at is None:
            boss_spawned_at = f
        if cpu.mem[BOSS_PHASE] == 1:
            if not saw_pose:
                saw_pose = True
                pose_entered_at = f
        elif saw_pose and pose_entered_at is not None and f > pose_entered_at:
            pose_exited = True
            break
check("real MAINLOOP: boss spawns", boss_spawned_at is not None)
check("real MAINLOOP: the boss really enters the attack pose during a real patrol cycle",
      saw_pose)
check("real MAINLOOP: the boss really exits the pose again (resumes patrol)",
      pose_exited)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
