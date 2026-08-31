"""round36-14 follow-up#11 ("ザコ敵の弾発射実装 ZakoII2種は反転時に添付
データEBullet発射 コリジョンは左上4x4ドット 発射タイミングの瞬間の自機
を狙って直進 発射は16方向 Flyerは画面左端まで行き反転後発射"): EBullet
is the ZacoII/Flyer enemy bullet - a hw sprite that aims at the tank's
own position at the exact instant it's fired, then flies dead straight
in 1 of 16 quantized directions until off-screen.

PAT_EBULLET reuses SBEAM_CODE(252-255) - a boss-exclusive pattern slot,
safe because SBeam's own art isn't loaded until TRIGGER_BOSS time, well
after ZacoII/Flyer (and so EBullet firing) have already stopped for
good. This round's own real-hardware feedback ("EBulletが全く違う
パターン") caught the FIRST version's own mistake: codes234-238/251-255
had looked "free" in a VRAM-content survey, but were actually blank-but-
reserved filler within PAT_FLYER/PAT_FLYER_L's own 16-code pose blocks -
see EBULLET_SLOT_SIZE's own comment in combined_test.asm for the full
account.
"""
import math
import os
import random
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


EBULLET_POOL = sym["EBULLET_POOL"]
SLOT = sym["EBULLET_SLOT_SIZE"]
COUNT = sym["EBULLET_SLOT_COUNT"]
ORIGIN_X = sym["EBULLET_ORIGIN_X"]
ORIGIN_Y = sym["EBULLET_ORIGIN_Y"]
SPRITE_ATTRS = sym["EBULLET_SPRITE_ATTRS"]
SPR_BASE = sym["EBULLET_SPR_BASE_SLOT"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_COLLISION_X_OFFSET = sym["TANK_COLLISION_X_OFFSET"]
TANK_COLLISION_Y_OFFSET = sym["TANK_COLLISION_Y_OFFSET"]
TANK_HAZARD_IFRAMES = sym["TANK_HAZARD_IFRAMES"]
TANK_LIFE = sym["TANK_LIFE"]
SAT_BASE = 0x1B00

check("EBULLET_SLOT_COUNT is 4 (matches PAT_EBULLET's own 4-code group and the 4 verified-free ATTRIBUTE slots)",
      COUNT == 4)

PAT_EBULLET = sym["PAT_EBULLET"]
SBEAM_CODE = sym["SBEAM_CODE"]
check("PAT_EBULLET really is SBEAM_CODE (the boss-exclusive slot this round's real-hardware fix reuses)",
      PAT_EBULLET == SBEAM_CODE)

# direct byte comparison against the source art, right after boot - the
# exact class of check that would have caught the original pattern-code
# collision immediately (same "direct byte comparison" precedent as
# BOSS_BROKEN_BEAM_CODE1-4's own verification).
import ebullet_gen as _eg
_cpu_pat = fresh_cpu()
_SPRPAT = 0x3800
_actual = [_cpu_pat.vram[_SPRPAT + PAT_EBULLET * 8 + i] for i in range(32)]
check("EBullet's own pattern VRAM (SPRPAT+PAT_EBULLET*8, 32 bytes) exactly matches ebullet_gen.py's own source art right after boot",
      _actual == list(_eg.EBULLET_SPRITE))

# and confirm SBeam's own later (boss-trigger-time) load safely overwrites
# it, proving the reuse ordering this round's fix depends on actually holds.
_cpu_boss = fresh_cpu()
_cpu_boss.mem[sym["BOSS_ACT"]] = 0
call_routine(_cpu_boss, "S2_BOSS_SPAWN")
_after_boss = [_cpu_boss.vram[_SPRPAT + PAT_EBULLET * 8 + i] for i in range(32)]
check("once S2_BOSS_SPAWN runs, SBeam's own real art occupies the same codes (EBullet's own data is safely gone by then)",
      _after_boss != list(_eg.EBULLET_SPRITE))


# ---------- EBULLET_DIR16 (16-direction aim reduction) ----------
import ebullet_gen


def py_dir16(dx, dy):
    return ebullet_gen.DIR16_LUT[ebullet_gen._fold_code(dx, dy)]


def call_dir16(dx, dy):
    cpu = fresh_cpu()
    cpu.d = dx & 0xFF
    cpu.e = dy & 0xFF
    call_routine(cpu, "EBULLET_DIR16")
    return cpu.a


random.seed(11)
mismatches = 0
tests = [(1, 0), (0, 1), (-1, 0), (0, -1), (1, 1), (-1, 1), (-1, -1), (1, -1),
         (50, 0), (0, 50), (-50, 0), (0, -50), (3, 1), (-5, 2)]
for _ in range(400):
    tests.append((random.randint(-127, 127), random.randint(-127, 127)))
for dx, dy in tests:
    if dx == 0 and dy == 0:
        continue
    if call_dir16(dx, dy) != py_dir16(dx, dy):
        mismatches += 1
check(f"EBULLET_DIR16 matches the Python reference model across {len(tests)} (dx,dy) samples "
      "(cheap sign-fold+swap+5*minor>major threshold, no multiply/divide - see ebullet_gen.py's own comment)",
      mismatches == 0)

check("EBULLET_DIR16 resolves an exactly-horizontal shot (dy=0) to dir0 (dead level), not 1 step off",
      call_dir16(50, 0) == 0 and call_dir16(-50, 0) == 8)
check("EBULLET_DIR16 resolves an exactly-vertical shot (dx=0) to dir4/dir12 (dead straight), not 1 step off",
      call_dir16(0, 50) == 4 and call_dir16(0, -50) == 12)


# ---------- LAUNCH_EBULLET ----------
def clear_pool(cpu):
    for i in range(COUNT):
        cpu.mem[EBULLET_POOL + i * SLOT + 0] = 0


cpu = fresh_cpu()
clear_pool(cpu)
cpu.mem[ORIGIN_X] = 100
cpu.mem[ORIGIN_Y] = 100
cpu.mem[TANK_X] = 150
cpu.mem[TANK_Y_CUR] = 100
call_routine(cpu, "LAUNCH_EBULLET")
check("LAUNCH_EBULLET activates the first free slot", cpu.mem[EBULLET_POOL + 0] == 1)
check("...at the given origin X", cpu.mem[EBULLET_POOL + 1] == 100)
check("...at the given origin Y", cpu.mem[EBULLET_POOL + 2] == 100)
dx = cpu.mem[EBULLET_POOL + 3]
dy = cpu.mem[EBULLET_POOL + 4]
dx_s = dx - 256 if dx >= 128 else dx
dy_s = dy - 256 if dy >= 128 else dy
check("...aimed toward the tank (dx>0 since tank is to the right, dy=0 since level)",
      dx_s > 0 and dy_s == 0)

cpu2 = fresh_cpu()
clear_pool(cpu2)
cpu2.mem[TANK_X] = 150
cpu2.mem[TANK_Y_CUR] = 100
for i in range(COUNT):
    cpu2.mem[ORIGIN_X] = 50 + i
    cpu2.mem[ORIGIN_Y] = 50
    call_routine(cpu2, "LAUNCH_EBULLET")
check("all 4 slots fill up across 4 separate launches",
      all(cpu2.mem[EBULLET_POOL + i * SLOT + 0] == 1 for i in range(COUNT)))
before = bytes(cpu2.mem[EBULLET_POOL + i] for i in range(COUNT * SLOT))
cpu2.mem[ORIGIN_X] = 99
call_routine(cpu2, "LAUNCH_EBULLET")
after = bytes(cpu2.mem[EBULLET_POOL + i] for i in range(COUNT * SLOT))
check("a 5th launch attempt with a full pool is silently dropped (pool left byte-for-byte unchanged)",
      before == after)


# ---------- UPDATE_EBULLET_ALL / FLUSH_EBULLET_SPRITES ----------
cpu3 = fresh_cpu()
clear_pool(cpu3)
cpu3.mem[EBULLET_POOL + 0] = 1
cpu3.mem[EBULLET_POOL + 1] = 100
cpu3.mem[EBULLET_POOL + 2] = 100
cpu3.mem[EBULLET_POOL + 3] = 3
cpu3.mem[EBULLET_POOL + 4] = 0
call_routine(cpu3, "UPDATE_EBULLET_ALL")
check("an active slot moves by its own DX/DY", cpu3.mem[EBULLET_POOL + 1] == 103 and cpu3.mem[EBULLET_POOL + 2] == 100)
check("its own real hw sprite slot shows the new position", cpu3.vram[SAT_BASE + SPR_BASE * 4] == 100)
check("slots that were never active stay hidden (Y=209) in real VRAM - not a stale Y=0 from an unprimed staging buffer",
      all(cpu3.vram[SAT_BASE + (SPR_BASE + i) * 4] == 209 for i in range(1, COUNT)))

cpu4 = fresh_cpu()
clear_pool(cpu4)
cpu4.mem[EBULLET_POOL + 0] = 1
cpu4.mem[EBULLET_POOL + 1] = 238
cpu4.mem[EBULLET_POOL + 2] = 100
cpu4.mem[EBULLET_POOL + 3] = 3
cpu4.mem[EBULLET_POOL + 4] = 0
call_routine(cpu4, "UPDATE_EBULLET_ALL")
check("a bullet crossing the right edge deactivates", cpu4.mem[EBULLET_POOL + 0] == 0)
check("...and its sprite is hidden again", cpu4.vram[SAT_BASE + SPR_BASE * 4] == 209)

cpu4b = fresh_cpu()
clear_pool(cpu4b)
cpu4b.mem[EBULLET_POOL + 0] = 1
cpu4b.mem[EBULLET_POOL + 1] = 1
cpu4b.mem[EBULLET_POOL + 2] = 100
cpu4b.mem[EBULLET_POOL + 3] = 256 - 3  # -3, signed
cpu4b.mem[EBULLET_POOL + 4] = 0
call_routine(cpu4b, "UPDATE_EBULLET_ALL")
check("a bullet crossing the left edge deactivates too", cpu4b.mem[EBULLET_POOL + 0] == 0)

cpu4c = fresh_cpu()
clear_pool(cpu4c)
cpu4c.mem[EBULLET_POOL + 0] = 1
cpu4c.mem[EBULLET_POOL + 1] = 100
cpu4c.mem[EBULLET_POOL + 2] = 190
cpu4c.mem[EBULLET_POOL + 3] = 0
cpu4c.mem[EBULLET_POOL + 4] = 3
call_routine(cpu4c, "UPDATE_EBULLET_ALL")
check("a bullet crossing the bottom edge deactivates", cpu4c.mem[EBULLET_POOL + 0] == 0)

cpu4d = fresh_cpu()
clear_pool(cpu4d)
cpu4d.mem[EBULLET_POOL + 0] = 1
cpu4d.mem[EBULLET_POOL + 1] = 100
cpu4d.mem[EBULLET_POOL + 2] = 1
cpu4d.mem[EBULLET_POOL + 3] = 0
cpu4d.mem[EBULLET_POOL + 4] = 256 - 3
call_routine(cpu4d, "UPDATE_EBULLET_ALL")
check("a bullet crossing the top edge deactivates", cpu4d.mem[EBULLET_POOL + 0] == 0)

# all 4 slots independently
cpu5 = fresh_cpu()
clear_pool(cpu5)
for i in range(COUNT):
    base = EBULLET_POOL + i * SLOT
    cpu5.mem[base + 0] = 1
    cpu5.mem[base + 1] = 100 + i
    cpu5.mem[base + 2] = 100 + i * 5
    cpu5.mem[base + 3] = 2
    cpu5.mem[base + 4] = 1
call_routine(cpu5, "UPDATE_EBULLET_ALL")
xs = [cpu5.mem[EBULLET_POOL + i * SLOT + 1] for i in range(COUNT)]
check("all 4 slots move independently on the same UPDATE_EBULLET_ALL call",
      xs == [102, 103, 104, 105])
sat_ys = [cpu5.vram[SAT_BASE + (SPR_BASE + i) * 4] for i in range(COUNT)]
check("all 4 real hw sprite slots reflect their own distinct positions (draw reached every slot)",
      len(set(sat_ys)) == 4)


# ---------- CHECK_EBULLET_VS_TANK ----------
for target in range(COUNT):
    cpu6 = fresh_cpu()
    cpu6.mem[TANK_HAZARD_IFRAMES] = 0
    tx = cpu6.mem[TANK_X] + TANK_COLLISION_X_OFFSET
    ty = cpu6.mem[TANK_Y_CUR] + TANK_COLLISION_Y_OFFSET
    for i in range(COUNT):
        base = EBULLET_POOL + i * SLOT
        cpu6.mem[base + 0] = 1
        cpu6.mem[base + 1] = tx if i == target else 10
        cpu6.mem[base + 2] = ty if i == target else 10
        cpu6.mem[base + 3] = 0
        cpu6.mem[base + 4] = 0
    life0 = cpu6.mem[TANK_LIFE]
    call_routine(cpu6, "CHECK_EBULLET_VS_TANK")
    check(f"slot{target} overlapping the tank damages it (others, far away, don't false-trigger)",
          cpu6.mem[TANK_LIFE] == life0 - 1)

cpu7 = fresh_cpu()
cpu7.mem[TANK_HAZARD_IFRAMES] = 0
for i in range(COUNT):
    base = EBULLET_POOL + i * SLOT
    cpu7.mem[base + 0] = 1
    cpu7.mem[base + 1] = 10
    cpu7.mem[base + 2] = 10
life0 = cpu7.mem[TANK_LIFE]
call_routine(cpu7, "CHECK_EBULLET_VS_TANK")
check("no slot overlapping the tank -> no damage", cpu7.mem[TANK_LIFE] == life0)

cpu8 = fresh_cpu()
tx = cpu8.mem[TANK_X] + TANK_COLLISION_X_OFFSET
ty = cpu8.mem[TANK_Y_CUR] + TANK_COLLISION_Y_OFFSET
cpu8.mem[TANK_HAZARD_IFRAMES] = 5
cpu8.mem[EBULLET_POOL + 0] = 1
cpu8.mem[EBULLET_POOL + 1] = tx
cpu8.mem[EBULLET_POOL + 2] = ty
life0 = cpu8.mem[TANK_LIFE]
call_routine(cpu8, "CHECK_EBULLET_VS_TANK")
check("no repeat damage while TANK_HAZARD_IFRAMES is still active", cpu8.mem[TANK_LIFE] == life0)


# ---------- Flyer no longer fires EBullet (実機フィードバック対応) ----------
# round36-14 follow-up#11 originally had Flyer fire an EBullet at its
# own cruise->home reversal ("Flyerは画面左端まで行き反転後発射").
# follow-up#12 実機フィードバック対応 ("反転時のBullet発射は削除"):
# removed now that Flyer has its own Mine-drop and FlyerLaser attacks
# instead (see mine_flyerlaser_test.py) - confirm the reversal no
# longer touches EBULLET_POOL at all.
FLYER_POOL = sym["FLYER_POOL"]
FLYER_SPEED = sym["FLYER_SPEED"]
cpu_fl = fresh_cpu()
clear_pool(cpu_fl)
cpu_fl.mem[FLYER_POOL + 0] = 1
cpu_fl.mem[FLYER_POOL + 1] = FLYER_SPEED - 1  # about to clamp to X=0 this frame
cpu_fl.mem[FLYER_POOL + 2] = 50
cpu_fl.mem[FLYER_POOL + 3] = 0
cpu_fl.mem[FLYER_POOL + 4] = 0
cpu_fl.mem[FLYER_POOL + 8] = 0  # PHASE=cruise
cpu_fl.mem[TANK_Y_CUR] = 100
cpu_fl.ix = FLYER_POOL
call_routine(cpu_fl, "UPDATE_ONE_FLYER")
check("Flyer's own X really did clamp to 0 at this transition (the scenario the old bug needed)",
      cpu_fl.mem[FLYER_POOL + 1] == 0 and cpu_fl.mem[FLYER_POOL + 8] == 1)
check("...and no EBullet gets allocated by Flyer's own reversal any more",
      cpu_fl.mem[EBULLET_POOL + 0] == 0)


# ---------- real end-to-end: ZacoII actually fires during real play ----------
cpu9 = fresh_cpu()
cpu9.sim_dir = 1
cpu9.sim_trig_a = True
cpu9.sim_trig_b = False
ever_fired = False
for f in range(8000):
    step_frame(cpu9)
    if cpu9.mem[sym["BOSS_ACT"]] != 0:
        break
    if any(cpu9.mem[EBULLET_POOL + i * SLOT + 0] == 1 for i in range(COUNT)):
        ever_fired = True
        break
check("real MAINLOOP play: ZacoII's own EBullet actually fires before the boss spawns",
      ever_fired)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
