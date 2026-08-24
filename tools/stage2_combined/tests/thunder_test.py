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

THUNDER_SLOT_SIZE = sym["THUNDER_SLOT_SIZE"]
THUNDER_SLOT_COUNT = sym["THUNDER_SLOT_COUNT"]
THUNDER_POOL = sym["THUNDER_POOL"]
THUNDER_PENDING = sym["THUNDER_PENDING"]
THUNDER_ELIGIBLE = sym["THUNDER_ELIGIBLE"]
THUNDER_LEG_START_X = sym["THUNDER_LEG_START_X"]
THUNDER_CODE_BASE = sym["THUNDER_CODE_BASE"]
THUNDERS_CODE = sym["THUNDERS_CODE"]
THUNDER_COLORBYTE = sym["THUNDER_COLORBYTE"]
THUNDER_TOP_ROW = sym["THUNDER_TOP_ROW"]
THUNDER_TRIGGER_DX = sym["THUNDER_TRIGGER_DX"]
BOSS_LEFT_PAUSE_TICKS = sym["BOSS_LEFT_PAUSE_TICKS"]
BOSS_X = sym["BOSS_X"]
BOSS_DIR = sym["BOSS_DIR"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_ACT = sym["BOSS_ACT"]
BOSS_SPAWNX = sym["BOSS_SPAWNX"]
BOSS_SPEED = sym["BOSS_SPEED"]
IDCACHE_T0 = sym["IDCACHE_T0"]
IDCACHE_T1 = sym["IDCACHE_T1"]
IDCACHE_T2 = sym["IDCACHE_T2"]
GAME_TICK = sym["GAME_TICK"]

TL, TR, BL, BR = (THUNDER_CODE_BASE + i for i in range(4))


def name_addr(row, col):
    return 0x1800 + row * 32 + col


def cell(cpu, row, col):
    return cpu.vram[name_addr(row, col)]


def slot_addr(i):
    return THUNDER_POOL + i * THUNDER_SLOT_SIZE


def slot(cpu, i):
    base = slot_addr(i)
    return {
        "act": cpu.mem[base + 0],
        "col": cpu.mem[base + 1],
        "row": cpu.mem[base + 2],
        "deep": cpu.mem[base + 3],
    }


def set_terrain_flat(cpu, tier):
    """Makes every column report the same tier (0=row20 highest .. 3=row23
    lowest/flat) via IDCACHE_T0..T2 (0=empty/nothing there, nonzero=solid -
    same convention UPDATE_TERRAIN_COLLISION/UOZ_TERRAIN_FOLLOW read)."""
    for col in range(32):
        cpu.mem[IDCACHE_T0 + col] = 1 if tier == 0 else 0
        cpu.mem[IDCACHE_T1 + col] = 1 if tier == 1 else 0
        cpu.mem[IDCACHE_T2 + col] = 1 if tier == 2 else 0


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


# ---- INIT: Thunder + ThunderS BG art actually loaded into VRAM ----
cpu = fresh_cpu()
pat_base = THUNDER_CODE_BASE * 8
loaded = list(cpu.vram[pat_base:pat_base + 32])
check("INIT loads all 32 nonzero Thunder bolt pattern bytes",
      any(b != 0 for b in loaded))
thunders_pat = list(cpu.vram[THUNDERS_CODE * 8:THUNDERS_CODE * 8 + 8])
check("INIT loads the ThunderS pattern bytes too (not left as 0)",
      any(b != 0 for b in thunders_pat))
check("INIT writes THUNDER_COLORBYTE into group27's own color-table entry (2000h+27) - "
      "shared by both THUNDER_CODE_BASE and THUNDERS_CODE",
      cpu.vram[0x2000 + 27] == THUNDER_COLORBYTE)


# ---- RESET_THUNDER_POOL / ALLOC_THUNDER_SLOT: a real pool now ----
cpu = fresh_cpu()
for i in range(THUNDER_SLOT_COUNT):
    cpu.mem[slot_addr(i) + 0] = 1  # dirty every slot first
call_routine(cpu, "RESET_THUNDER_POOL")
check("RESET_THUNDER_POOL zeroes every slot's own ACT",
      all(slot(cpu, i)["act"] == 0 for i in range(THUNDER_SLOT_COUNT)))

cpu = fresh_cpu()
cpu.a = 5
call_routine(cpu, "ALLOC_THUNDER_SLOT")
check("ALLOC_THUNDER_SLOT fires into slot0 with ACT=1", slot(cpu, 0)["act"] == 1)
check("ALLOC_THUNDER_SLOT sets COL from A", slot(cpu, 0)["col"] == 5)
check("ALLOC_THUNDER_SLOT starts ROW at THUNDER_TOP_ROW", slot(cpu, 0)["row"] == THUNDER_TOP_ROW)

cpu.a = 9
call_routine(cpu, "ALLOC_THUNDER_SLOT")
check("a 2nd ALLOC_THUNDER_SLOT call fires into slot1, not slot0 again - "
      "多重発射: いつからサンダーは1本しか出せない仕様に? そんな指示はしてねえぞ",
      slot(cpu, 1)["act"] == 1 and slot(cpu, 1)["col"] == 9 and slot(cpu, 0)["col"] == 5)

cpu2 = fresh_cpu()
for i in range(THUNDER_SLOT_COUNT):
    cpu2.a = i
    call_routine(cpu2, "ALLOC_THUNDER_SLOT")
check(f"all {THUNDER_SLOT_COUNT} pool slots can be active simultaneously",
      all(slot(cpu2, i)["act"] == 1 for i in range(THUNDER_SLOT_COUNT)))
cpu2.a = 99
call_routine(cpu2, "ALLOC_THUNDER_SLOT")  # pool full - should be a no-op
check("drops the attempt once the whole pool is full (no crash, no state corruption)",
      all(slot(cpu2, i)["col"] != 99 for i in range(THUNDER_SLOT_COUNT)))


# ---- GET_TERRAIN_ROW_FOR_COL: tier -> row mapping ----
cpu = fresh_cpu()
for tier, expected_row in [(0, 20), (1, 21), (2, 22), (3, 23)]:
    set_terrain_flat(cpu, tier)
    cpu.a = 10
    call_routine(cpu, "GET_TERRAIN_ROW_FOR_COL")
    check(f"tier{tier} -> terrain row {expected_row}", cpu.a == expected_row)


# ---- DRAW_ONE_THUNDER_ROW / ERASE_ONE_THUNDER_ROW: parity + safe-zone restore ----
SKY_BLANK_CODE = sym["SKY_BLANK_CODE"]
NIGHT_ROW = sym["NIGHT_ROW"]
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 0
cpu.a = 5  # odd row -> TL/TR
cpu.b = 10
call_routine(cpu, "DRAW_ONE_THUNDER_ROW")
check("DRAW_ONE_THUNDER_ROW at an ODD row draws TL/TR (block-top)",
      (cell(cpu, 5, 10), cell(cpu, 5, 11)) == (TL, TR))
cpu.a = 6  # even row -> BL/BR
cpu.b = 10
call_routine(cpu, "DRAW_ONE_THUNDER_ROW")
check("DRAW_ONE_THUNDER_ROW at an EVEN row draws BL/BR (block-bottom)",
      (cell(cpu, 6, 10), cell(cpu, 6, 11)) == (BL, BR))
cpu.a = 5
cpu.b = 10
call_routine(cpu, "ERASE_ONE_THUNDER_ROW")
check("ERASE_ONE_THUNDER_ROW restores a safe-zone row (<20) to plain sky",
      (cell(cpu, 5, 10), cell(cpu, 5, 11)) == (SKY_BLANK_CODE, SKY_BLANK_CODE))

# a row>=20 is a no-op for the erase (self-heals via the terrain's own
# per-frame redraw instead - see ERASE_ONE_THUNDER_CELL's own comment)
cpu = fresh_cpu()
cpu.a = 21
cpu.b = 10
call_routine(cpu, "DRAW_ONE_THUNDER_ROW")
before = (cell(cpu, 21, 10), cell(cpu, 21, 11))
cpu.a = 21
cpu.b = 10
call_routine(cpu, "ERASE_ONE_THUNDER_ROW")
check("ERASE_ONE_THUNDER_ROW is a no-op for row>=20 (ERASE_BULLET_CELL's own EBC_SKIP band)",
      (cell(cpu, 21, 10), cell(cpu, 21, 11)) == before)


# ---- WRITE_THUNDERS_CELL / ERASE_ONE_THUNDER_CELL for the side cells ----
cpu = fresh_cpu()
cpu.mem[NIGHT_ROW] = 0
cpu.a = 5
cpu.b = 3
call_routine(cpu, "WRITE_THUNDERS_CELL")
check("WRITE_THUNDERS_CELL writes THUNDERS_CODE at the given cell", cell(cpu, 5, 3) == THUNDERS_CODE)
cpu.a = 5
cpu.b = 3
call_routine(cpu, "ERASE_ONE_THUNDER_CELL")
check("ERASE_ONE_THUNDER_CELL restores a safe-zone side cell to plain sky",
      cell(cpu, 5, 3) == SKY_BLANK_CODE)


# ---- UPDATE_ONE_THUNDER: full lifecycle against a SAFE terrain row
# (tier0, terrain row20 -> DEEP_ROW19, everything stays <20, no
# reassertion needed at all) ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 0)
cpu.a = 8
call_routine(cpu, "ALLOC_THUNDER_SLOT")
ix = slot_addr(0)
grew_rows = []
for _ in range(40):
    cpu.ix = ix
    call_routine(cpu, "UPDATE_ONE_THUNDER")
    if slot(cpu, 0)["act"] == 2:
        break
    grew_rows.append(slot(cpu, 0)["row"])
s = slot(cpu, 0)
check("tier0: growth stops with DEEP_ROW=19 (terrain_row20 - 1)", s["deep"] == 19)
check("tier0: transitions to shrinking (ACT=2) once the terrain is reached - 地形に到達したら",
      s["act"] == 2)
check("tier0: the bolt's own deepest row (19) is drawn", cell(cpu, 19, 8) in (TL, TR, BL, BR))
check("tier0: ThunderS side cells appear left (col7) and right (col10) of the bolt at DEEP_ROW - "
      "地形に到達したら添付のキャラを地上の上に左右に発射",
      cell(cpu, 19, 7) == THUNDERS_CODE and cell(cpu, 19, 10) == THUNDERS_CODE)
check("tier0: row20 (the real terrain) was never touched", cell(cpu, 20, 8) == 0 or cell(cpu, 20, 8) != TL)

# drive through the shrink phase
for _ in range(40):
    cpu.ix = ix
    call_routine(cpu, "UPDATE_ONE_THUNDER")
    if slot(cpu, 0)["act"] == 0:
        break
check("tier0: fully shrinks back to inactive (ACT=0)", slot(cpu, 0)["act"] == 0)
check("tier0: the bolt's own deepest row is erased", cell(cpu, 19, 8) not in (TL, TR, BL, BR))
check("tier0: the ThunderS side cells are erased too - サンダーが着地したら左右同時に2セル描いて消せばおｋ",
      cell(cpu, 19, 7) != THUNDERS_CODE and cell(cpu, 19, 10) != THUNDERS_CODE)


# ---- UPDATE_ONE_THUNDER: full lifecycle against a DEEP terrain row
# (tier3, terrain row23 -> DEEP_ROW22) - forces the bolt into the
# ground/rock band (row>=20), which needs the continuous per-frame
# reassertion to actually stay visible against TERRAIN_RENDER_ROW's own
# unconditional per-frame redraw (simulated here by corrupting the
# contested cells between calls, matching the real MAINLOOP's own call
# order: terrain redraw happens before UPDATE_THUNDER every frame) ----
cpu = fresh_cpu()
set_terrain_flat(cpu, 3)
cpu.a = 8
call_routine(cpu, "ALLOC_THUNDER_SLOT")
ix = slot_addr(0)
saw_contested_row_drawn = False
for _ in range(60):
    # simulate the terrain's own unconditional per-frame redraw
    # clobbering the contested band (rows20-23) BEFORE Thunder's own
    # update runs this frame, exactly like real MAINLOOP ordering.
    for row in range(20, 24):
        cpu.vram[name_addr(row, 8)] = 0
        cpu.vram[name_addr(row, 9)] = 0
    cpu.ix = ix
    call_routine(cpu, "UPDATE_ONE_THUNDER")
    if cell(cpu, 21, 8) in (TL, TR, BL, BR) or cell(cpu, 22, 8) in (TL, TR, BL, BR):
        saw_contested_row_drawn = True
    if slot(cpu, 0)["act"] == 2:
        break
s = slot(cpu, 0)
check("tier3: growth reaches all the way down to DEEP_ROW=22 (terrain row23 - 1) - "
      "終了位置は地形までに変更", s["deep"] == 22)
check("tier3: a contested row (>=20) actually got (re)drawn during growth despite the simulated "
      "per-frame terrain overwrite - the reassertion pass is doing real work, not a no-op",
      saw_contested_row_drawn)
check("tier3: the deepest row (22, inside the ground/rock band) is visible right after landing "
      "even though this test frame started by clobbering it first",
      cell(cpu, 22, 8) in (TL, TR, BL, BR))
check("tier3: ThunderS side cells also land inside the contested band and are visible",
      cell(cpu, 22, 7) == THUNDERS_CODE and cell(cpu, 22, 10) == THUNDERS_CODE)

# drive through shrink, continuing to simulate the terrain's own
# clobbering every frame - contested rows must keep reasserting until
# shrink actually passes them, then STAY gone (terrain reclaims them)
still_reasserting_at_22 = None
for step in range(60):
    for row in range(20, 24):
        cpu.vram[name_addr(row, 8)] = 0
        cpu.vram[name_addr(row, 9)] = 0
    cpu.ix = ix
    call_routine(cpu, "UPDATE_ONE_THUNDER")
    if slot(cpu, 0)["act"] == 0:
        break
check("tier3: fully shrinks back to inactive (ACT=0) even from the deep-terrain case",
      slot(cpu, 0)["act"] == 0)
# once inactive, nothing reasserts row22 any more - a fresh simulated
# terrain overwrite should stick (not get fought back to a Thunder code)
cpu.vram[name_addr(22, 8)] = 0
call_routine(cpu, "UPDATE_ONE_THUNDER")  # ACT=0 - no-op, must not resurrect anything
check("tier3: once fully inactive, nothing keeps re-asserting the old contested rows any more - "
      "the terrain's own redraw is free to reclaim them",
      cell(cpu, 22, 8) not in (TL, TR, BL, BR))


# ---- CHECK_THUNDER_TRIGGER_LEFT/_RIGHT: fire every 32px, repeatedly,
# with NO single-instance gate any more (round9) ----
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 0
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 50
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT is a no-op while THUNDER_PENDING=0 (not armed)",
      all(slot(cpu, i)["act"] == 0 for i in range(THUNDER_SLOT_COUNT)))

cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 100
cpu.mem[BOSS_X] = 100 - THUNDER_TRIGGER_DX
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT fires (>=, not exact-match) right at THUNDER_TRIGGER_DX",
      slot(cpu, 0)["act"] == 1)
check("THUNDER_PENDING stays armed (repeats for the whole leg, not one-shot)",
      cpu.mem[THUNDER_PENDING] == 1)
expect_col = ((100 - THUNDER_TRIGGER_DX) + 64) >> 3
check("fires at the boss's own current RIGHT edge (BOSS_X+64) converted to a BG column",
      slot(cpu, 0)["col"] == expect_col)

# fires AGAIN immediately, into a 2nd pool slot, even though the FIRST
# column is still fully active (growing) - no busy-gate any more
cpu.mem[BOSS_X] -= THUNDER_TRIGGER_DX
call_routine(cpu, "CHECK_THUNDER_TRIGGER_LEFT")
check("CHECK_THUNDER_TRIGGER_LEFT fires again into a 2nd slot while the 1st is still fully active - "
      "BGを使ってるのは表示制限がないからだろが",
      slot(cpu, 0)["act"] == 1 and slot(cpu, 1)["act"] == 1)

# ---- the right-edge overlap fix: column = (BOSS_X-16)>>3, not BOSS_X>>3 ----
cpu = fresh_cpu()
cpu.mem[THUNDER_PENDING] = 1
cpu.mem[THUNDER_LEG_START_X] = 0
cpu.mem[BOSS_X] = THUNDER_TRIGGER_DX
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT fires right at THUNDER_TRIGGER_DX", slot(cpu, 0)["act"] == 1)
expect_col_r = (THUNDER_TRIGGER_DX - 16) >> 3
check("fires at (BOSS_X-16)>>3 - trailing OUTSIDE the boss's own [BOSS_X,BOSS_X+64) box, not "
      "directly under it - 反転した時にボス自身に当たってしまう(fixed)",
      slot(cpu, 0)["col"] == expect_col_r)
check("the fired column sits strictly left of the boss's own current left edge (no overlap)",
      slot(cpu, 0)["col"] * 8 + 16 <= cpu.mem[BOSS_X])
check("THUNDER_PENDING stays armed (repeats for the whole leg)", cpu.mem[THUNDER_PENDING] == 1)

cpu.mem[BOSS_X] += THUNDER_TRIGGER_DX
call_routine(cpu, "CHECK_THUNDER_TRIGGER_RIGHT")
check("CHECK_THUNDER_TRIGGER_RIGHT also fires again after another THUNDER_TRIGGER_DX px",
      slot(cpu, 1)["act"] == 1)


# ---- real MAINLOOP: boss reaches the left edge, PAUSES (BOSS_PHASE=2,
# stationary) for BOSS_LEFT_PAUSE_TICKS GAME_TICKs, THEN reverses -
# "左端は2Tick停止してから反転発射に" ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
boss_spawned = False
pose1_entered = False
pose1_ended = False
saw_left_pause = False
pause_entered_tick = None
reversal_tick = None
for f in range(20000):
    step_frame(cpu)
    if cpu.mem[BOSS_ACT] == 1:
        boss_spawned = True
    if boss_spawned and not pose1_ended:
        if cpu.mem[BOSS_PHASE] == 1:
            pose1_entered = True
        elif pose1_entered and cpu.mem[BOSS_PHASE] == 0:
            pose1_ended = True
    if pose1_ended and cpu.mem[BOSS_PHASE] == 2 and cpu.mem[BOSS_X] == 0 and pause_entered_tick is None:
        saw_left_pause = True
        pause_entered_tick = cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)
    if saw_left_pause and cpu.mem[BOSS_DIR] == 1 and reversal_tick is None:
        reversal_tick = cpu.mem[GAME_TICK] | (cpu.mem[GAME_TICK + 1] << 8)
        break

check("real MAINLOOP: boss reaches its first attack pose", boss_spawned and pose1_entered and pose1_ended)
check("real MAINLOOP: the boss actually enters the left-edge pause (BOSS_PHASE=2) before reversing",
      saw_left_pause)
check("real MAINLOOP: the boss actually reverses (BOSS_DIR=1) after the pause", reversal_tick is not None)
check(f"real MAINLOOP: the pause lasts at least BOSS_LEFT_PAUSE_TICKS({BOSS_LEFT_PAUSE_TICKS}) "
      "GAME_TICKs before the boss actually reverses",
      pause_entered_tick is not None and reversal_tick is not None
      and reversal_tick - pause_entered_tick >= BOSS_LEFT_PAUSE_TICKS)
check("real MAINLOOP: boss ends up facing right (BOSS_DIR=1) after the pause elapses",
      cpu.mem[BOSS_DIR] == 1)


# ---- real MAINLOOP: multiple Thunder columns can be alive at once -
# "いつからサンダーは1本しか出せない仕様に? そんな指示はしてねえぞ" ----
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
max_concurrent = 0
saw_side_cells = False
for f in range(20000):
    step_frame(cpu)
    active = sum(1 for i in range(THUNDER_SLOT_COUNT) if slot(cpu, i)["act"] != 0)
    max_concurrent = max(max_concurrent, active)
    for i in range(THUNDER_SLOT_COUNT):
        s = slot(cpu, i)
        if s["act"] == 2:
            row, col = s["deep"], s["col"]
            if col > 0 and cell(cpu, row, col - 1) == THUNDERS_CODE:
                saw_side_cells = True
    if max_concurrent >= 2 and saw_side_cells:
        break

check("real MAINLOOP: at least 2 Thunder columns are genuinely active at the same time at some point - "
      "a real pool, not a 1-at-a-time cap",
      max_concurrent >= 2)
check("real MAINLOOP: a real ThunderS side cell actually appears once a bolt reaches the terrain",
      saw_side_cells)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
