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
BULLET0_ACT = sym["BULLET0_ACT"]
NIGHT_ROW = sym["NIGHT_ROW"]
NIGHT_END_ROW = sym["NIGHT_END_ROW"]
BULLETU_NIGHT_CODE = sym["BULLETU_NIGHT_CODE"]
BULLETU_L_NIGHT_CODE = sym["BULLETU_L_NIGHT_CODE"]
BULLETU_ROCK_CODE = sym["BULLETU_ROCK_CODE"]
BULLETU_L_ROCK_CODE = sym["BULLETU_L_ROCK_CODE"]
BULLET_U_SPR_BASE_SLOT = sym["BULLET_U_SPR_BASE_SLOT"]

SAT_BASE = 0x1B00


def make_u_slot(cpu, row, col=10, facing=0, addr=0x1800 + 5 * 32):
    ix = BULLET0_ACT
    cpu.mem[ix + 0] = 1       # ACT
    cpu.mem[ix + 1] = 1       # TYPE = U (diagonal)
    cpu.mem[ix + 2] = col
    cpu.mem[ix + 3] = row
    cpu.mem[ix + 4] = addr & 0xFF
    cpu.mem[ix + 5] = (addr >> 8) & 0xFF
    cpu.mem[ix + 6] = facing
    cpu.ix = ix
    return ix, addr


# Tests 1-4: DRAW_BULLET_CELL picks U's own BG codes (not F's) once
# BOSS_ACT!=0 - "ボス戦になったら斜めショットをBG描画に変更" (U's own hw
# sprite was reported disappearing during the boss fight).
cpu = fresh_cpu()
cpu.mem[BOSS_ACT] = 1
cpu.mem[NIGHT_ROW] = NIGHT_END_ROW  # full night sweep always complete by BOSS_SPAWN_TICK

ix, addr = make_u_slot(cpu, row=5, col=10, facing=0)
call_routine(cpu, "DRAW_BULLET_CELL")
check("U draws BULLETU_NIGHT_CODE in the sky band while BOSS_ACT=1",
      cpu.vram[addr + 10] == BULLETU_NIGHT_CODE)

ix, addr = make_u_slot(cpu, row=5, col=10, facing=1)
call_routine(cpu, "DRAW_BULLET_CELL")
check("U draws BULLETU_L_NIGHT_CODE in the sky band, facing left, while BOSS_ACT=1",
      cpu.vram[addr + 10] == BULLETU_L_NIGHT_CODE)

ix, addr = make_u_slot(cpu, row=18, col=10, facing=0)
call_routine(cpu, "DRAW_BULLET_CELL")
check("U draws BULLETU_ROCK_CODE in the Sand/rock band while BOSS_ACT=1",
      cpu.vram[addr + 10] == BULLETU_ROCK_CODE)

ix, addr = make_u_slot(cpu, row=18, col=10, facing=1)
call_routine(cpu, "DRAW_BULLET_CELL")
check("U draws BULLETU_L_ROCK_CODE in the Sand/rock band, facing left, while BOSS_ACT=1",
      cpu.vram[addr + 10] == BULLETU_L_ROCK_CODE)

# Test 5: U's own hw sprite slot is hidden (Y=209) while BOSS_ACT=1, so
# it doesn't sit uselessly on top of the BG cell (and stops costing a
# per-frame VDP write for nothing).
cpu2 = fresh_cpu()
cpu2.mem[BOSS_ACT] = 1
make_u_slot(cpu2, row=5, col=10, facing=0)
call_routine(cpu2, "UPDATE_BULLET_U_SPRITES")
check("U's own hw sprite slot is hidden (Y=209) while BOSS_ACT=1",
      cpu2.vram[SAT_BASE + BULLET_U_SPR_BASE_SLOT * 4] == 209)

# Test 6: outside the boss fight, nothing changed - U still shows as a
# real hw sprite at its own ROW*8/COL*8 position (old behavior intact).
cpu3 = fresh_cpu()
cpu3.mem[BOSS_ACT] = 0
make_u_slot(cpu3, row=5, col=10, facing=0)
call_routine(cpu3, "UPDATE_BULLET_U_SPRITES")
check("U's own hw sprite slot shows normally (Y=ROW*8) while BOSS_ACT=0",
      cpu3.vram[SAT_BASE + BULLET_U_SPR_BASE_SLOT * 4] == 5 * 8)

# Test 7: real end-to-end - fire a diagonal shot after the boss has
# spawned, confirm it actually gets drawn via a real BULLETU_* BG code
# during flight (not just reachable in isolation) and its own hw
# sprite slot stays hidden the whole time.
cpu4 = fresh_cpu()
cpu4.sim_dir = 0
cpu4.sim_trig_a = False
cpu4.sim_trig_b = False
boss_spawned_at = None
fired = False
u_codes = {BULLETU_NIGHT_CODE, BULLETU_L_NIGHT_CODE, BULLETU_ROCK_CODE, BULLETU_L_ROCK_CODE}
saw_bg_code = False
saw_hidden_sprite = True
for f in range(9330):
    step_frame(cpu4)
    if cpu4.mem[BOSS_ACT] != 0:
        if boss_spawned_at is None:
            boss_spawned_at = f
        if not fired:
            cpu4.sim_dir = 1   # up
            cpu4.sim_trig_a = True
            fired = True
        else:
            cpu4.sim_trig_a = False
        if cpu4.mem[BULLET0_ACT] != 0 and cpu4.mem[BULLET0_ACT + 1] != 0:
            row = cpu4.mem[BULLET0_ACT + 3]
            col = cpu4.mem[BULLET0_ACT + 2]
            lo = cpu4.mem[BULLET0_ACT + 4]
            hi = cpu4.mem[BULLET0_ACT + 5]
            code = cpu4.vram[(lo | (hi << 8)) + col]
            if code in u_codes:
                saw_bg_code = True
            if cpu4.vram[SAT_BASE + BULLET_U_SPR_BASE_SLOT * 4] != 209:
                saw_hidden_sprite = False
    if boss_spawned_at is not None and f - boss_spawned_at > 60:
        break

check("real MAINLOOP: a diagonal shot fired after boss-spawn draws a real BULLETU_* BG code",
      saw_bg_code)
check("real MAINLOOP: U's own hw sprite slot stays hidden(209) throughout the boss fight",
      saw_hidden_sprite)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
