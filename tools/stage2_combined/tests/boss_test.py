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

# Test 2-3: refuses to spawn before BOSS_SPAWN_TICK, including at the
# old-bug-class truncated-8-bit low byte of BOSS_SPAWN_TICK (999&0xFF)
# - same regression shape as cloud_changes_test.py/enemy_spawn_stop_test.py.
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK - 1)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("does not spawn just before BOSS_SPAWN_TICK", cpu.mem[BOSS_ACT] == 0)

cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK & 0xFF)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("does not spawn at the truncated-8-bit low byte of BOSS_SPAWN_TICK",
      cpu.mem[BOSS_ACT] == 0)

# Test 4: spawns at BOSS_SPAWN_TICK with the right initial state.
cpu = fresh_cpu()
set_game_tick(cpu, BOSS_SPAWN_TICK)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("BOSS_ACT becomes 1 at BOSS_SPAWN_TICK", cpu.mem[BOSS_ACT] == 1)
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
set_game_tick(cpu, BOSS_SPAWN_TICK)
call_routine(cpu, "UPDATE_BOSS_ALL")   # spawn frame
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
check("reverses to DIR=1 (moving right) once X=0 is reached", cpu.mem[BOSS_DIR] == 1)
check("mirrored facing (SASAPI_QUADS_L) reloaded into VRAM on this reversal - まず反転パターンを生成",
      sprpat_matches(cpu, SASAPI_QUADS_L))

# drive it all the way back to the right edge
steps = 0
while cpu.mem[BOSS_X] < BOSS_SPAWNX and steps < 200:
    call_routine(cpu, "UPDATE_BOSS_ALL")
    steps += 1
check("returns to X=BOSS_SPAWNX exactly (clamped)", cpu.mem[BOSS_X] == BOSS_SPAWNX)
call_routine(cpu, "UPDATE_BOSS_ALL")
check("reverses back to DIR=0 (moving left) once X=BOSS_SPAWNX is reached again",
      cpu.mem[BOSS_DIR] == 0)
check("normal facing (SASAPI_QUADS) reloaded into VRAM on this reversal",
      sprpat_matches(cpu, SASAPI_QUADS))

# Test 12: real end-to-end - spawns at the real frame BOSS_SPAWN_TICK*8,
# not before (GAME_TICK advances once per 8 raw frames).
expected_frame = BOSS_SPAWN_TICK * 8
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
spawn_frame = None
for f in range(expected_frame + 50):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] != 0 and spawn_frame is None:
        spawn_frame = f
check(f"real MAINLOOP: boss spawns at frame ~{expected_frame}, not earlier",
      spawn_frame is not None and expected_frame - 8 <= spawn_frame <= expected_frame)
print(f"spawn_frame={spawn_frame}")

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
