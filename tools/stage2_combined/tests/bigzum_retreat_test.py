"""round35 (real-hardware feedback: "Bigzumは4回以上スケジュールしてる
が1回しか出てない...恐らくEtankでスキップされてるな...排他制御はあくま
で仮実装の仕様 これはエディットでコントロールするんで要らない"):
BIGZUM_RETREAT_TICK used to be the ONE shared tick every BigZum retreated
at regardless of when it spawned - direct emulator instrumentation of a
full worst-case playthrough showed this (not any Etank exclusion, which
doesn't exist in the current code - verified by reading ALLOC_BIGZUM_
SLOT/ALLOC_ETANK_SLOT directly) was the actual reason only 1 of 6
scheduled BigZum entries ever spawned: the first successful spawn
occupied BigZum's own single slot (BIGZUM_SLOT_COUNT=1) continuously
until the shared 950 tick, dropping every later entry as "pool full".

Fixed by making the retreat PER-INSTANCE (BIGZUM_POOL+13/+14, computed
once at spawn in ALLOC_BIGZUM_SLOT as min(spawn tick + BIGZUM_ENGAGEMENT_
DURATION, BIGZUM_RETREAT_TICK) - see BIGZUM_ENGAGEMENT_DURATION's own
comment). This file's own original tests (1-8 below) still exercise the
mechanism at the OLD constant's own value by explicitly setting +13/+14
to BIGZUM_RETREAT_TICK in spawn_bigzum's own default - their pass/fail
behavior is unchanged, since a BigZum whose own retreat tick happens to
equal the ceiling behaves identically to the old global-tick design. New
tests below (9+) cover the actual per-instance computation itself, via
the real ALLOC_BIGZUM_SLOT spawn path rather than a manual poke.

Same round, after seeing this file's own direct instrumentation log:
"スポーン条件も要らないぞ 地形も仮実装だから平地条件いらない" -
BIGZUM_TERRAIN_OK (and BIGZUM_SPAWN_COL, which only ever fed it) are
gone entirely now, so the tests below no longer need any IDCACHE/
terrain setup before calling ALLOC_BIGZUM_SLOT - a free slot is the
only precondition left.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

GAME_TICK = sym["GAME_TICK"]
BIGZUM_RETREAT_TICK = sym["BIGZUM_RETREAT_TICK"]
BIGZUM_ENGAGEMENT_DURATION = sym["BIGZUM_ENGAGEMENT_DURATION"]
BIGZUM_POOL = sym["BIGZUM_POOL"]
BIGZUM_JUMP_XSPEED = sym["BIGZUM_JUMP_XSPEED"]
BULLET0_ACT = sym["BULLET0_ACT"]


def set_game_tick(cpu, val):
    cpu.mem[GAME_TICK] = val & 0xFF
    cpu.mem[GAME_TICK + 1] = (val >> 8) & 0xFF


def get_own_retreat_tick(cpu):
    return cpu.mem[BIGZUM_POOL + 13] | (cpu.mem[BIGZUM_POOL + 14] << 8)


def spawn_bigzum(cpu, x=100, y=132, state=0, retreat_tick=None):
    if retreat_tick is None:
        retreat_tick = BIGZUM_RETREAT_TICK
    cpu.mem[BIGZUM_POOL + 0] = 1     # ACT
    cpu.mem[BIGZUM_POOL + 1] = x
    cpu.mem[BIGZUM_POOL + 2] = y
    cpu.mem[BIGZUM_POOL + 7] = state
    cpu.mem[BIGZUM_POOL + 8] = 100   # HP
    cpu.mem[BIGZUM_POOL + 9] = 1     # FACING=1 (flipped), so the transition to 0 is observable
    cpu.mem[BIGZUM_POOL + 13] = retreat_tick & 0xFF
    cpu.mem[BIGZUM_POOL + 14] = (retreat_tick >> 8) & 0xFF


# Test 1: not yet forced into retreat before BIGZUM_RETREAT_TICK.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK - 1)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE not forced to 5 just before BIGZUM_RETREAT_TICK",
      cpu.mem[BIGZUM_POOL + 7] != 5)

# Test 2: does NOT force retreat at the truncated-8-bit low byte of
# BIGZUM_RETREAT_TICK - same regression shape as the cloud/enemy-spawn
# fixes this same session.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK & 0xFF)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE not forced to 5 at the truncated-8-bit low byte of BIGZUM_RETREAT_TICK",
      cpu.mem[BIGZUM_POOL + 7] != 5)

# Test 3-4: forced into STATE=5 at BIGZUM_RETREAT_TICK, FACING reset
# to 0 (normal, facing left), overriding an in-progress punch (STATE=2).
cpu = fresh_cpu()
spawn_bigzum(cpu, x=100, state=2)   # mid-punch
set_game_tick(cpu, BIGZUM_RETREAT_TICK)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("STATE forced to 5 (retreat) at BIGZUM_RETREAT_TICK, overriding STATE=2 (punch)",
      cpu.mem[BIGZUM_POOL + 7] == 5)
check("FACING reset to 0 (normal, facing left) on forced retreat",
      cpu.mem[BIGZUM_POOL + 9] == 0)

# Test 5: steps left by BIGZUM_JUMP_XSPEED per call while retreating.
x0 = cpu.mem[BIGZUM_POOL + 1]
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("steps left by BIGZUM_JUMP_XSPEED per call while retreating",
      cpu.mem[BIGZUM_POOL + 1] == x0 - BIGZUM_JUMP_XSPEED)

# Test 6: drives all the way off the left edge - deactivates and hides.
cpu = fresh_cpu()
spawn_bigzum(cpu, x=BIGZUM_JUMP_XSPEED * 3, state=0)
set_game_tick(cpu, BIGZUM_RETREAT_TICK)
cpu.ix = BIGZUM_POOL
steps = 0
while cpu.mem[BIGZUM_POOL + 0] != 0 and steps < 50:
    call_routine(cpu, "UPDATE_ONE_BIGZUM")
    steps += 1
check("deactivates (ACT=0) once retreated off the left edge - 消す", cpu.mem[BIGZUM_POOL + 0] == 0)
sprite_y = cpu.mem[sym["BIGZUM_SPRITE_ATTRS"]]
check("hw sprite hidden (Y=209) after deactivating", sprite_y == 209)

# Test 7-8: collision disabled during forced retreat - "この時は弾が
# 居ても貫通しコリジョン無効に". Positive control first (STATE=1/jump,
# which bypasses the front/rear-facing split entirely so any AABB
# overlap registers a hit) confirms the box geometry below genuinely
# overlaps and WOULD register a hit outside of STATE=5.
def setup_hit_pair(cpu, state):
    cpu.mem[BIGZUM_POOL + 0] = 1
    cpu.mem[BIGZUM_POOL + 1] = 80    # BZ_X
    cpu.mem[BIGZUM_POOL + 2] = 80    # BZ_Y
    cpu.mem[BIGZUM_POOL + 7] = state
    cpu.mem[BIGZUM_POOL + 8] = 100   # HP
    cpu.mem[BULLET0_ACT + 0] = 1     # bullet ACT
    cpu.mem[BULLET0_ACT + 1] = 0     # TYPE=F
    cpu.mem[BULLET0_ACT + 2] = 10    # COL -> pixelX=80, matches BZ_X
    cpu.mem[BULLET0_ACT + 3] = 12    # ROW -> pixelY=96, matches BZ_Y+16 (BIGZUM_COLLISION_Y_OFFSET)


cpu = fresh_cpu()
setup_hit_pair(cpu, state=1)   # STATE=1 (jump) - positive control
cpu.ix = BULLET0_ACT
cpu.iy = BIGZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_BIGZUM")
check("positive control: overlapping bullet registers a hit while STATE=1 (bullet consumed)",
      cpu.mem[BULLET0_ACT + 0] == 0)

cpu = fresh_cpu()
setup_hit_pair(cpu, state=5)   # STATE=5 (forced retreat)
cpu.ix = BULLET0_ACT
cpu.iy = BIGZUM_POOL
call_routine(cpu, "CHECK_HIT_PAIR_BIGZUM")
check("same overlap does NOT register while STATE=5 (retreat) - bullet passes through",
      cpu.mem[BULLET0_ACT + 0] == 1)
check("HP unchanged while STATE=5", cpu.mem[BIGZUM_POOL + 8] == 100)

# ---------------------------------------------------------------------
# Test 9-12 (round35): ALLOC_BIGZUM_SLOT's own per-instance retreat-tick
# computation - min(spawn tick + BIGZUM_ENGAGEMENT_DURATION,
# BIGZUM_RETREAT_TICK), via the REAL spawn path this time (not a
# manual poke), so this exercises the actual arithmetic that shipped.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
set_game_tick(cpu, 100)
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("spawning well before the ceiling: own retreat tick = spawn(100) + BIGZUM_ENGAGEMENT_DURATION, not clamped",
      cpu.mem[BIGZUM_POOL + 0] == 1 and get_own_retreat_tick(cpu) == 100 + BIGZUM_ENGAGEMENT_DURATION)

cpu = fresh_cpu()
set_game_tick(cpu, BIGZUM_RETREAT_TICK - 1)
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("spawning 1 tick before the ceiling: candidate would overshoot it, so own retreat tick clamps to the ceiling itself",
      cpu.mem[BIGZUM_POOL + 0] == 1 and get_own_retreat_tick(cpu) == BIGZUM_RETREAT_TICK)

cpu = fresh_cpu()
set_game_tick(cpu, BIGZUM_RETREAT_TICK + 50)   # spawning AFTER the ceiling entirely (e.g. a very late schedule entry)
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("spawning after the ceiling entirely: own retreat tick still clamps to the ceiling (never past it)",
      cpu.mem[BIGZUM_POOL + 0] == 1 and get_own_retreat_tick(cpu) == BIGZUM_RETREAT_TICK)
check("UPDATE_ONE_BIGZUM forces retreat from this BigZum's very first live frame, since GAME_TICK already exceeds its own (clamped) retreat tick",
      True)  # confirmed by the next call below
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("  ...STATE forced to 5 immediately", cpu.mem[BIGZUM_POOL + 7] == 5)

# ---------------------------------------------------------------------
# Test 13: the actual end-to-end regression this round exists to fix -
# a BigZum that spawns, then naturally retreats and frees the slot well
# before BIGZUM_RETREAT_TICK, instead of squatting on it until 950.
# ---------------------------------------------------------------------
cpu = fresh_cpu()
set_game_tick(cpu, 200)
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
own_retreat = get_own_retreat_tick(cpu)
check("own retreat tick (200+duration) is well under BIGZUM_RETREAT_TICK(950) for an early spawn",
      own_retreat < BIGZUM_RETREAT_TICK)
set_game_tick(cpu, own_retreat)
cpu.ix = BIGZUM_POOL
call_routine(cpu, "UPDATE_ONE_BIGZUM")
check("retreats at its OWN computed tick, long before the old shared 950 - this is what frees the slot "
      "for later schedule entries instead of blocking them for the rest of the game",
      cpu.mem[BIGZUM_POOL + 7] == 5)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
