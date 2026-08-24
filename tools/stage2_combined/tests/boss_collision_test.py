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

BOSS_ACT = sym["BOSS_ACT"]
BOSS_X = sym["BOSS_X"]
BOSS_Y = sym["BOSS_Y"]
BOSS_SPAWN_Y = sym["BOSS_SPAWN_Y"]
BOSS_HP = sym["BOSS_HP"]
BOSS_HP_INIT = sym["BOSS_HP_INIT"]
BOSS_FLASH_TIMER = sym["BOSS_FLASH_TIMER"]
BOSS_COLOR = sym["BOSS_COLOR"]
BOSS_FLASH_COLOR = sym["BOSS_FLASH_COLOR"]
BOSS_COLLISION_SIZE = sym["BOSS_COLLISION_SIZE"]
BOSS_SPRITE_ATTRS = sym["BOSS_SPRITE_ATTRS"]
BOSS_SPR_BASE_SLOT = sym["BOSS_SPR_BASE_SLOT"]
BULLET0_ACT = sym["BULLET0_ACT"]
FLASH_COLOR = sym["FLASH_COLOR"]
FLASH_DURATION = sym["FLASH_DURATION"]

SAT_BASE = 0x1B00

check("BOSS_COLLISION_SIZE matches the real 64x64 visible footprint - 見た目通り",
      BOSS_COLLISION_SIZE == 64)
# "ほかの敵のフラッシュ処理もレッドに" - the shared global FLASH_COLOR
# is now the same medium-red shade as BOSS_FLASH_COLOR (both were white
# vs boss-only-red before this round) - no longer expected to differ.
check("BOSS_FLASH_COLOR and the shared global FLASH_COLOR are now the same red shade",
      BOSS_FLASH_COLOR == FLASH_COLOR)
check("BOSS_FLASH_COLOR is also distinct from BOSS_COLOR itself (flash must actually read as a color change)",
      BOSS_FLASH_COLOR != BOSS_COLOR)


def make_boss(cpu, x=100, hp=BOSS_HP_INIT):
    cpu.mem[BOSS_ACT] = 1
    cpu.mem[BOSS_X] = x
    # round11: BOSS_Y is now a real, dynamic RAM variable (was a fixed
    # BOSS_SPAWN_Y constant) - CHECK_HIT_PAIR_BOSS's own collision box
    # reads it directly, so a manually-poked boss (bypassing the real
    # spawn branch, which is the only place that normally sets it) needs
    # it set explicitly too, or the box ends up at whatever BOSS_Y last
    # happened to be (0 on a fresh boot).
    cpu.mem[BOSS_Y] = BOSS_SPAWN_Y
    cpu.mem[BOSS_HP] = hp
    cpu.mem[BOSS_FLASH_TIMER] = 0


def make_bullet(cpu, col, row, active=1):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = active
    cpu.mem[ix + 1] = 0
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    row_addr = 0x1800 + row * 32
    cpu.mem[ix + 4] = row_addr & 0xFF
    cpu.mem[ix + 5] = (row_addr >> 8) & 0xFF
    cpu.mem[ix + 6] = 0
    cpu.ix = ix


# Test: a bullet inside the boss's own box registers a hit (HP-1, bullet
# deactivated, flash timer set).
cpu = fresh_cpu()
make_boss(cpu, x=100)
boss_row = BOSS_SPAWN_Y // 8
make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("a bullet inside the boss's own box registers a hit (HP decrements)",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT - 1)
check("the bullet is deactivated on a hit", cpu.mem[BULLET0_ACT] == 0)
check("the flash timer is armed on a non-lethal hit", cpu.mem[BOSS_FLASH_TIMER] == FLASH_DURATION)

# Test: a bullet clearly outside the box (far right, past X+63) does NOT hit.
cpu = fresh_cpu()
make_boss(cpu, x=0)
make_bullet(cpu, col=250 // 8, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("a bullet outside the box does not register a hit",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT and cpu.mem[BULLET0_ACT] == 1)

# Test: a bullet exactly at the box's own edges (見た目通り - the full
# 64x64 box, not a smaller hitbox) still registers.
cpu = fresh_cpu()
make_boss(cpu, x=100)
# right edge: boss spans X100..X163 (100+63); a bullet cell at col
# (163//8) has its own 8px cell overlapping X163 itself.
make_bullet(cpu, col=163 // 8, row=boss_row)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("a bullet at the box's own right edge (X+63) still registers - full 64px box, not a smaller hitbox",
      cpu.mem[BOSS_HP] == BOSS_HP_INIT - 1)

# Test: an inactive boss (not yet spawned) never registers a hit.
cpu = fresh_cpu()
cpu.mem[BOSS_ACT] = 0
make_bullet(cpu, col=100 // 8, row=boss_row)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("an unspawned boss (BOSS_ACT=0) never registers a hit", cpu.mem[BULLET0_ACT] == 1)

# Test: DRAW_BOSS uses BOSS_FLASH_COLOR while the flash timer is active,
# and decrements it once per draw call (not once per quadrant).
cpu = fresh_cpu()
make_boss(cpu, x=100)
cpu.mem[BOSS_FLASH_TIMER] = 3
call_routine(cpu, "DRAW_BOSS")
all_flash = all(cpu.mem[BOSS_SPRITE_ATTRS + i * 4 + 3] == BOSS_FLASH_COLOR for i in range(16))
check("DRAW_BOSS colors all 16 quadrants BOSS_FLASH_COLOR while the flash timer is active",
      all_flash)
check("DRAW_BOSS decrements the flash timer once per call, not once per quadrant",
      cpu.mem[BOSS_FLASH_TIMER] == 2)

cpu2 = fresh_cpu()
make_boss(cpu2, x=100)
cpu2.mem[BOSS_FLASH_TIMER] = 0
call_routine(cpu2, "DRAW_BOSS")
all_normal = all(cpu2.mem[BOSS_SPRITE_ATTRS + i * 4 + 3] == BOSS_COLOR for i in range(16))
check("DRAW_BOSS colors all 16 quadrants the normal BOSS_COLOR once the flash timer is 0",
      all_normal)

# Test: HP reaching exactly 0 destroys the boss (BOSS_ACT=2) and hides
# every one of its 16 hw sprite slots (Y=209) - not left at whatever
# they last showed.
cpu = fresh_cpu()
make_boss(cpu, x=100, hp=1)
make_bullet(cpu, col=100 // 8 + 1, row=boss_row + 1)
call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("HP reaching 0 destroys the boss (BOSS_ACT becomes 2)", cpu.mem[BOSS_ACT] == 2)
all_hidden = all(cpu.vram[SAT_BASE + (BOSS_SPR_BASE_SLOT + i) * 4] == 209 for i in range(16))
check("all 16 hw sprite slots are hidden (Y=209) the instant the boss is destroyed", all_hidden)

# Test: a destroyed boss (ACT=2) never re-spawns and UPDATE_BOSS_ALL
# leaves it alone permanently, even though GAME_TICK is already past
# BOSS_SPAWN_TICK (which would otherwise immediately re-trigger the
# ACT==0 spawn check).
call_routine(cpu, "UPDATE_BOSS_ALL")
check("a destroyed boss (ACT=2) is left alone by UPDATE_BOSS_ALL, never re-spawns",
      cpu.mem[BOSS_ACT] == 2)

# Test: real end-to-end - spawn the boss via a real MAINLOOP sweep,
# drive its HP down to 0 via repeated real hits, confirm it dies and
# stays dead.
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned_at = None
for f in range(9500):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1 and boss_spawned_at is None:
        boss_spawned_at = f
    if boss_spawned_at is not None and f - boss_spawned_at > 5:
        break
check("real MAINLOOP: boss reaches ACT=1 (spawned) before the manual-HP-drain test",
      cpu.mem[BOSS_ACT] == 1)

# manually drain the rest of its HP via direct CHECK_HIT_PAIR_BOSS calls
# (a real full 255-hit playthrough isn't practical here) and confirm
# the final hit both destroys it and that it stays destroyed afterward
# through more real MAINLOOP frames.
boss_x = cpu.mem[BOSS_X]
boss_row = BOSS_SPAWN_Y // 8
while cpu.mem[BOSS_HP] > 0:
    make_bullet(cpu, col=boss_x // 8 + 1, row=boss_row + 1)
    call_routine(cpu, "CHECK_BULLET_VS_BOSS")
check("real boss: repeated hits drive HP to exactly 0 and destroy it",
      cpu.mem[BOSS_ACT] == 2 and cpu.mem[BOSS_HP] == 0)

# call_routine leaves cpu.pc at its own return sentinel, not a real
# resumable point in MAINLOOP - reset it back to MAINLOOP's own top
# before driving more real frames via step_frame.
cpu.pc = sym["MAINLOOP"]
for f in range(120):
    step_frame(cpu)
check("real MAINLOOP: a destroyed boss stays destroyed (ACT still 2) over 120 more real frames",
      cpu.mem[BOSS_ACT] == 2)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
