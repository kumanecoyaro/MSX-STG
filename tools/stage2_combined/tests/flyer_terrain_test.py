import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine, step_frame

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

FLYER_POOL = sym["FLYER_POOL"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
LIMIT = sym["FLYER_DESCEND_LIMIT_Y"]

# descending Flyer near the cap: one more step would exceed it - must clamp+exit
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = LIMIT
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = sym["FLYER_VY"]
cpu.mem[TANK_Y_CUR] = 156  # worst-case lowest tier
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("Descending Flyer never exceeds FLYER_DESCEND_LIMIT_Y", cpu.mem[FLYER_POOL+2] <= LIMIT)
check("Descending Flyer exits once at the cap", cpu.mem[FLYER_POOL+8] == 2)

# DY=0 edge case (tank exactly level at lock) exits immediately, no infinite loop
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = 64
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = 0
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("DY=0 (level tie) exits immediately instead of looping forever", cpu.mem[FLYER_POOL+8] == 2)

# ascending Flyer is unaffected by the cap (moving away from ground)
cpu = fresh_cpu()
cpu.mem[FLYER_POOL+0] = 1
cpu.mem[FLYER_POOL+1] = 100
cpu.mem[FLYER_POOL+2] = 140   # only 16px from TANK_Y_CUR(156) - within FLYER_CLEAR_Y(32), still close
cpu.mem[FLYER_POOL+8] = 1
cpu.mem[FLYER_POOL+6] = (256 - sym["FLYER_VY"]) & 0xFF
cpu.mem[TANK_Y_CUR] = 156
cpu.ix = FLYER_POOL
call_routine(cpu, "UPDATE_ONE_FLYER")
check("Ascending Flyer steps up normally, unaffected by descend cap", cpu.mem[FLYER_POOL+2] == 140 - sym["FLYER_VY"])
check("Ascending Flyer stays in PHASE=1 (still within clearance)", cpu.mem[FLYER_POOL+8] == 1)


# ---- "Flyerのスポーン位置はランダムで指示してたはずだが固定されてし
# まってる 画面上部8pxからSandsky上部までのランダムで" - ALLOC_FLYER_
# SLOT must pick a real random Y in [FLYER_SPAWN_Y_MIN, FLYER_SPAWN_Y_
# MIN+FLYER_SPAWN_Y_SPAN), not the old fixed FLYER_CRUISE_Y(64) ----
check("the old fixed FLYER_CRUISE_Y constant is gone", "FLYER_CRUISE_Y" not in sym)
FLYER_SPAWN_Y_MIN = sym["FLYER_SPAWN_Y_MIN"]
FLYER_SPAWN_Y_SPAN = sym["FLYER_SPAWN_Y_SPAN"]
check("FLYER_SPAWN_Y_MIN is screen-top+8px", FLYER_SPAWN_Y_MIN == 8)
# round-2 fix: "Flyerの出現位置がSandskyに被ってる場合がある ランダム
# 範囲を16px狭く" - span shrunk from 121 to 105 (16px narrower), pulling
# the max top-left Y down from 128 (SkySand's own top row pixel - too
# low once the sprite's real 32x32 body is accounted for) to 112.
check("the span is 16px narrower than the original 121 - ランダム範囲を16px狭く",
      FLYER_SPAWN_Y_SPAN == 105)
check("the new max top-left Y (112) is comfortably clear of SkySand's own top row pixel (128)",
      FLYER_SPAWN_Y_MIN + FLYER_SPAWN_Y_SPAN - 1 == 112)

cpu = fresh_cpu()
ys = []
for i in range(30):
    cpu.mem[sym["GAME_RNG"]] = (cpu.mem[sym["GAME_RNG"]] + 37) & 0xFF
    cpu.mem[sym["TICK"]] = (cpu.mem[sym["TICK"]] + 13) & 0xFF
    call_routine(cpu, "ALLOC_FLYER_SLOT")
    ys.append(cpu.mem[FLYER_POOL + 2])
    cpu.mem[FLYER_POOL] = 0   # free the slot again so the next spawn reuses it
check("every spawned Y falls within [FLYER_SPAWN_Y_MIN, FLYER_SPAWN_Y_MIN+FLYER_SPAWN_Y_SPAN)",
      all(FLYER_SPAWN_Y_MIN <= y < FLYER_SPAWN_Y_MIN + FLYER_SPAWN_Y_SPAN for y in ys))
check("spawned Y actually varies across spawns (not silently stuck at one value)",
      len(set(ys)) >= 5)

# ALLOC_FLYER_SLOT reads GAME_RNG without mutating it - HORMING_WANDER's
# own round4 fix ("お前は1度もまともにランダム扱えてないな") for why a
# read-and-increment idiom correlates across back-to-back callers.
cpu = fresh_cpu()
rng_before = cpu.mem[sym["GAME_RNG"]]
call_routine(cpu, "ALLOC_FLYER_SLOT")
check("PICK_FLYER_SPAWN_Y never mutates GAME_RNG", cpu.mem[sym["GAME_RNG"]] == rng_before)

# real MAINLOOP: several natural spawns (no manual pool-freeing) also
# land at genuinely different Y values, not just under a synthetic loop
cpu = fresh_cpu()
cpu.sim_dir = 0
cpu.sim_trig_a = False
cpu.sim_trig_b = False
seen_ys = set()
for f in range(40000):
    step_frame(cpu)
    if cpu.mem[FLYER_POOL + 0] != 0:
        seen_ys.add(cpu.mem[FLYER_POOL + 2])
        cpu.mem[FLYER_POOL + 0] = 0   # despawn immediately so the next natural spawn gets a fresh roll
    if len(seen_ys) >= 4:
        break
check("real MAINLOOP: several consecutive natural spawns land at different Y values",
      len(seen_ys) >= 4)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
