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
BOSS_SPAWN_TICK = sym["BOSS_SPAWN_TICK"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_SPEED = sym["BOSS_SPEED"]
BOSS_HP_INIT = sym["BOSS_HP_INIT"]
BOSS_COLOR = sym["BOSS_COLOR"]
PAT_SASAPI = sym["PAT_SASAPI"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_DIR = sym["BOSS_DIR"]
BOSS_HP = sym["BOSS_HP"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
SASAPI_QUADS = sym["SASAPI_QUADS"]
SASAPI_QUADS_L = sym["SASAPI_QUADS_L"]
BOSS_QUAD_OFFSETS = sym["BOSS_QUAD_OFFSETS"]
SPRPAT = sym["SPRPAT"]
BOSS_PHASE = sym["BOSS_PHASE"]


def sprpat_matches(cpu, rom_label):
    base = SPRPAT + PAT_SASAPI * 8
    rom_bytes = [out[rom_label + i] for i in range(16 * 32)]
    return rom_bytes == list(cpu.vram[base: base + 16 * 32])


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# Test 1: not spawned at boot.
cpu = fresh_cpu()
check("BOSS_ACT is 0 at boot", cpu.mem[BOSS_ACT] == 0)

# round34 ("全てスケジュールに"): the old Test 2-3 here directly poked
# GAME_TICK and called UPDATE_BOSS_ALL to prove it refused to spawn too
# early, including the truncated-8-bit-low-byte regression shape. That
# gate has moved to SPAWN2_SCHEDULE_CHECK now (shared by every schedule
# entry, not boss-specific) - see spawn2_schedule_test.py for the same
# regression check against the real dispatcher. S2_BOSS_SPAWN itself
# (the routine SSC2_FIRE's dispatch chain actually jumps to) has no
# tick check of its own at all any more - it always succeeds whenever
# called, exactly like Stage1's own BOSS_SPAWN.
#
# Test: spawns with the right initial state when S2_BOSS_SPAWN fires.
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")
check("BOSS_ACT becomes 1", cpu.mem[BOSS_ACT] == 1)
check("BOSS_X starts at BOSS_SPAWNX", cpu.mem[BOSS_X] == BOSS_SPAWNX)
check("BOSS_DIR starts at 0 (moving left) - 右から出現し左へ",
      cpu.mem[BOSS_DIR] == 0)
check("BOSS_HP starts at BOSS_HP_INIT(255)", cpu.mem[BOSS_HP] == BOSS_HP_INIT)

# Test 5: pattern VRAM was loaded - SASAPI_QUADS (ROM) now matches the
# REAL sprite pattern generator table (SPRPAT+PAT_SASAPI*8.., not just
# PAT_SASAPI*8 - that bare form is the BG pattern table's own address
# space instead, a real bug caught by rendering the boss and seeing
# garbage/leftover BigZum patterns instead of Sasapi's own art).
sprpat_base = SPRPAT + PAT_SASAPI * 8
rom_quads = [out[SASAPI_QUADS + i] for i in range(16 * 32)]
vram_quads = list(cpu.vram[sprpat_base: sprpat_base + 16 * 32])
check("SASAPI_QUADS pattern data loaded into the real sprite pattern table (SPRPAT+PAT_SASAPI*8)",
      rom_quads == vram_quads)

# Test 6: BOSS_SPRITE_ATTRS staging buffer - all 16 quadrants got the
# right Y/X/pattern/color from BOSS_QUAD_OFFSETS.
quad_offsets = [(out[BOSS_QUAD_OFFSETS + i * 3],
                 out[BOSS_QUAD_OFFSETS + i * 3 + 1],
                 out[BOSS_QUAD_OFFSETS + i * 3 + 2]) for i in range(16)]
attrs_ok = True
for qi, (dy, dx, dpat) in enumerate(quad_offsets):
    base = BOSS_SPRITE_ATTRS + qi * 4
    y, x, pat, col = cpu.mem[base], cpu.mem[base + 1], cpu.mem[base + 2], cpu.mem[base + 3]
    if (y != (BOSS_SPAWN_Y + dy) & 0xFF or x != (BOSS_SPAWNX + dx) & 0xFF
            or pat != (PAT_SASAPI + dpat) & 0xFF or col != BOSS_COLOR):
        attrs_ok = False
        print(f"  quadrant {qi} mismatch: got Y={y} X={x} pat={pat} col={col}, "
              f"expected Y={(BOSS_SPAWN_Y+dy)&0xFF} X={(BOSS_SPAWNX+dx)&0xFF} "
              f"pat={(PAT_SASAPI+dpat)&0xFF} col={BOSS_COLOR}")
check("all 16 quadrants staged with the right Y/X/pattern/color", attrs_ok)

# Test 7: the staged attrs were actually flushed to the real hw sprite
# table (VRAM 0x1B00 + slot*4), not just left in RAM.
hw_ok = True
for qi in range(16):
    base = 0x1B00 + (BOSS_SPR_BASE_SLOT + qi) * 4
    ram_base = BOSS_SPRITE_ATTRS + qi * 4
    if list(cpu.vram[base:base + 4]) != [cpu.mem[ram_base + k] for k in range(4)]:
        hw_ok = False
check("hw sprite table (0x1B00+slot*4) matches the staged attrs for all 16 slots", hw_ok)

# Test 8-11: patrol movement - steps left at BOSS_SPEED/frame, clamps
# and reverses at X=0, steps right back, clamps and reverses again at
# X=BOSS_SPAWNX - "左端に着いたら反転 右端に 以降繰り返し".
cpu = fresh_cpu()
call_routine(cpu, "S2_BOSS_SPAWN")   # spawn frame
# follow-up#20 ("ワイプ中は初期停止状態のスプライトでワイプが終わるまで
# 停止すること"): UBA_ACTIVE now freezes all patrol movement entirely
# while the entrance materialize effect is active (BOSS_MATERIALIZE_ACT!=0, seeded by
# S2_BOSS_SPAWN itself). This file's patrol tests below are unrelated to
# the wipe - bypass it here so the boss actually moves like every test
# below already assumes (see boss_wipe_test.py for the freeze's own
# dedicated coverage).
cpu.mem[sym["BOSS_MATERIALIZE_ACT"]] = 0
x0 = cpu.mem[BOSS_X]
call_routine(cpu, "UPDATE_BOSS_ALL")   # 1 more frame, same tick (already spawned)
check("steps left by BOSS_SPEED per call while DIR=0",
      cpu.mem[BOSS_X] == x0 - BOSS_SPEED and cpu.mem[BOSS_DIR] == 0)

# drive it all the way to the left edge
steps = 0
while cpu.mem[BOSS_X] > 0 and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    steps += 1
check("reaches X=0 exactly (clamped, no negative wraparound)", cpu.mem[BOSS_X] == 0)
call_routine(cpu, "UPDATE_BOSS_ALL")
# round10: the boss no longer reverses immediately at the left edge - it
# pauses first (BOSS_PHASE=2, "左端は2Tick停止してから反転発射に") and
# only actually reverses once BOSS_LEFT_PAUSE_TICKS GAME_TICKs elapse.
# UPDATE_BOSS_ALL never advances GAME_TICK itself (only real MAINLOOP
# does, gated behind its own 8-frame counter) - same reason boss_pose_
# test.py sets GAME_TICK directly for BOSS_POSE_TICKS rather than
# looping calls hoping it advances on its own.
check("enters the left-edge pause (BOSS_PHASE=2) instead of reversing immediately",
      cpu.mem[BOSS_PHASE] == 2 and cpu.mem[BOSS_X] == 0)
BOSS_LEFT_PAUSE_TICKS = sym["BOSS_LEFT_PAUSE_TICKS"]
tick_at_pause = cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)
set_game_tick(cpu, tick_at_pause + BOSS_LEFT_PAUSE_TICKS)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("reverses to DIR=1 (moving right) once the left-edge pause elapses", cpu.mem[BOSS_DIR] == 1)
check("mirrored facing (SASAPI_QUADS_L) reloaded into VRAM on this reversal - まず反転パターンを生成",
      sprpat_matches(cpu, SASAPI_QUADS_L))

# drive it all the way back to the right edge
steps = 0
while cpu.mem[BOSS_X] < BOSS_SPAWNX and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    steps += 1
check("returns to X=BOSS_SPAWNX exactly (clamped)", cpu.mem[BOSS_X] == BOSS_SPAWNX)
call_routine(cpu, "UPDATE_BOSS_ALL")
# returning to the right edge no longer reverses immediately - it now
# enters the attack pose instead ("右端に戻ったら...攻撃ポーズ"); the
# actual DIR=0/normal-facing-reload only happens once the pose ends -
# see tests/boss_pose_test.py for the full pose lifecycle.
check("returning to the right edge enters the attack pose (BOSS_PHASE=1) instead of reversing immediately",
      cpu.mem[BOSS_PHASE] == 1)

# Test 12: real end-to-end - the boss can never spawn before GAME_TICK
# reaches BOSS_SPAWN_TICK (SSC2_FIRE advances SPAWN2_NEXT_INDEX through
# every earlier schedule entry unconditionally, one per due GAME_TICK -
# see SPAWN2_SCHEDULE_CHECK's own comment - so this lower bound still
# holds exactly). round34-3: with no player fire input at all (this
# test's own worst-case config, unchanged from before), a ground enemy
# can still go permanently un-destroyed, but that no longer delays
# anything downstream any more - a blocked spawn is simply dropped, not
# retried - so the boss reliably spawns right at its own scheduled
# tick995 (frame~7959), verified empirically, well within this budget.
# -1: this loop's own `f` is 0-indexed (the Nth step_frame call sets
# f=N-1), so "GAME_TICK reaches BOSS_SPAWN_TICK on the (BOSS_SPAWN_TICK*8)th
# call" observes as f==BOSS_SPAWN_TICK*8-1, not BOSS_SPAWN_TICK*8 itself.
# round34-3 exposed this: the boss now spawns on the very same step_frame
# call GAME_TICK first reaches its own threshold (verified directly - no
# ASM-side delay at all any more), so this off-by-one, previously masked
# by the old design's own multi-frame spawn delay, now has to be accounted
# for explicitly instead of accidentally passing.
expected_frame = BOSS_SPAWN_TICK * 8 - 1
UPPER_BOUND_FRAME = 20000
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
spawn_frame = None
for f in range(UPPER_BOUND_FRAME):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] != 0 and spawn_frame is None:
        spawn_frame = f
        break
check(f"real MAINLOOP: boss never spawns before frame {expected_frame} (its own earliest possible tick)",
      spawn_frame is not None and spawn_frame >= expected_frame)
check(f"real MAINLOOP: boss does eventually spawn, even with no player fire input at all "
      f"(within {UPPER_BOUND_FRAME} frames - unconditional-advance SSC2_FIRE guarantees this, "
      f"since nothing can ever block the schedule from reaching its own last entry)",
      spawn_frame is not None)
print(f"spawn_frame={spawn_frame}")

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
