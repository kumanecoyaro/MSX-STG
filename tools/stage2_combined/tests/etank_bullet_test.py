"""round36-14 follow-up#11 ("Etankはスポーン後左へ32px移動したら発射し
方向は左直進のみ 弾はBG使用ファイルEtankBullet"): EtankBullet is Etank's
own one-shot bullet, drawn as a BG cell (not a hw sprite - see
ETANK_BULLET_ACT's own comment for why: every one of the 32 BG color
groups was already claimed by something, unlike hw sprites where a real
survey found genuine spare capacity - group31's own existing fg5/bg11
color is reused unchanged, per direct user confirmation). Only 1
concurrent instance ever needed (ETANK_SLOT_COUNT=1 itself).
"""
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


ETANK_POOL = sym["ETANK_POOL"]
ETANK_BULLET_ACT = sym["ETANK_BULLET_ACT"]
ETANK_BULLET_X = sym["ETANK_BULLET_X"]
ETANK_BULLET_Y = sym["ETANK_BULLET_Y"]
ETANK_SPAWN_X = sym["ETANK_SPAWN_X"]
ETANK_BULLET_FIRED = sym["ETANK_BULLET_FIRED"]
ETANK_SPAWNX = sym["ETANK_SPAWNX"]
ETANK_BULLET_SPEED = sym["ETANK_BULLET_SPEED"]
ETANK_BULLET_PATTERN_CODE = sym["ETANK_BULLET_PATTERN_CODE"]
SKYSAND_CODE = sym["SKYSAND_CODE"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
TANK_COLLISION_X_OFFSET = sym["TANK_COLLISION_X_OFFSET"]
TANK_COLLISION_Y_OFFSET = sym["TANK_COLLISION_Y_OFFSET"]
TANK_COLLISION_WIDTH = sym["TANK_COLLISION_WIDTH"]
TANK_COLLISION_HEIGHT = sym["TANK_COLLISION_HEIGHT"]
TANK_HAZARD_IFRAMES = sym["TANK_HAZARD_IFRAMES"]
TANK_LIFE = sym["TANK_LIFE"]

check("ETANK_BULLET_PATTERN_CODE(249) sits in group31 alongside SKYSAND_CODE(248), NOT overlapping it",
      ETANK_BULLET_PATTERN_CODE // 8 == SKYSAND_CODE // 8 and ETANK_BULLET_PATTERN_CODE != SKYSAND_CODE)

# 実機フィードバック対応: art replaced with a corrected source image
# (1px lower than the original) - direct byte comparison against the
# BG pattern-generator table right after boot, same "would have caught
# this immediately" precedent as EBullet's own equivalent check.
import etankbullet_gen as _etg
_cpu_pat = fresh_cpu()
_actual_pat = [_cpu_pat.vram[0x0000 + ETANK_BULLET_PATTERN_CODE * 8 + i] for i in range(8)]
check("EtankBullet's own BG pattern VRAM exactly matches the corrected sprites/EtankBullet_8x8.json right after boot",
      _actual_pat == list(_etg.ETANK_BULLET_PATTERN))


# ---------- ALLOC_ETANK_SLOT: spawn-time priming ----------
cpu = fresh_cpu()
cpu.mem[ETANK_BULLET_FIRED] = 1  # stale state from a hypothetical earlier instance
call_routine(cpu, "ALLOC_ETANK_SLOT")
check("ALLOC_ETANK_SLOT captures this instance's own spawn X", cpu.mem[ETANK_SPAWN_X] == ETANK_SPAWNX)
check("ALLOC_ETANK_SLOT clears the one-shot fired flag", cpu.mem[ETANK_BULLET_FIRED] == 0)


# ---------- LAUNCH_ETANK_BULLET ----------
cpu2 = fresh_cpu()
cpu2.mem[ETANK_POOL + 0] = 1
cpu2.mem[ETANK_POOL + 1] = 150
cpu2.mem[ETANK_POOL + 2] = 80
cpu2.ix = ETANK_POOL
call_routine(cpu2, "LAUNCH_ETANK_BULLET")
# round36-14 follow-up#11 実機フィードバック対応: Etank's own (IX+2) is a
# raw canvas-top Y, but its real art (UOET_DRAW's own BL/BR quadrants)
# is only ever drawn at (IX+2)+16 - "Etankはそもそも32x16しか使って
# いない" - so the bullet's own spawn Y must match that +16, not the raw
# field, or it spawns 2 cells above where Etank is actually drawn.
check("bullet activates at the firing Etank's own ACTUAL drawn position (Y offset +16, not the raw canvas-top field)",
      cpu2.mem[ETANK_BULLET_ACT] == 1 and cpu2.mem[ETANK_BULLET_X] == 150 and cpu2.mem[ETANK_BULLET_Y] == 96)


# ---------- UPDATE_ETANK_BULLET_ALL ----------
cpu3 = fresh_cpu()
cpu3.mem[ETANK_BULLET_ACT] = 1
cpu3.mem[ETANK_BULLET_X] = 100
cpu3.mem[ETANK_BULLET_Y] = 80
call_routine(cpu3, "UPDATE_ETANK_BULLET_ALL")
check("bullet moves left by ETANK_BULLET_SPEED per frame", cpu3.mem[ETANK_BULLET_X] == 100 - ETANK_BULLET_SPEED)
check("bullet stays active mid-flight", cpu3.mem[ETANK_BULLET_ACT] == 1)
check("the BG name-table cell at its own new position now shows the real bullet pattern code",
      cpu3.vram[0x1800 + (cpu3.mem[ETANK_BULLET_Y] // 8) * 32 + (cpu3.mem[ETANK_BULLET_X] // 8)] == ETANK_BULLET_PATTERN_CODE)

cpu4 = fresh_cpu()
cpu4.mem[ETANK_BULLET_ACT] = 1
cpu4.mem[ETANK_BULLET_X] = 1
cpu4.mem[ETANK_BULLET_Y] = 80
call_routine(cpu4, "UPDATE_ETANK_BULLET_ALL")
check("bullet despawns once it can no longer subtract a full step without underflowing (off the left edge)",
      cpu4.mem[ETANK_BULLET_ACT] == 0)

cpu5 = fresh_cpu()
cpu5.mem[ETANK_BULLET_ACT] = 0
before = bytes(cpu5.mem[a] for a in (ETANK_BULLET_ACT, ETANK_BULLET_X, ETANK_BULLET_Y))
call_routine(cpu5, "UPDATE_ETANK_BULLET_ALL")
after = bytes(cpu5.mem[a] for a in (ETANK_BULLET_ACT, ETANK_BULLET_X, ETANK_BULLET_Y))
check("an inactive bullet is a true no-op (nothing touched)", before == after)


# ---------- CHECK_ETANK_BULLET_VS_TANK ----------
cpu6 = fresh_cpu()
cpu6.mem[TANK_HAZARD_IFRAMES] = 0
tx = cpu6.mem[TANK_X] + TANK_COLLISION_X_OFFSET
ty = cpu6.mem[TANK_Y_CUR] + TANK_COLLISION_Y_OFFSET
cpu6.mem[ETANK_BULLET_ACT] = 1
cpu6.mem[ETANK_BULLET_X] = tx
cpu6.mem[ETANK_BULLET_Y] = ty
life0 = cpu6.mem[TANK_LIFE]
call_routine(cpu6, "CHECK_ETANK_BULLET_VS_TANK")
check("an overlapping bullet damages the tank", cpu6.mem[TANK_LIFE] == life0 - 1)
check("...but keeps flying through it (not deactivated by the hit), same convention as every other tank hazard",
      cpu6.mem[ETANK_BULLET_ACT] == 1)

cpu7 = fresh_cpu()
cpu7.mem[TANK_HAZARD_IFRAMES] = 0
cpu7.mem[ETANK_BULLET_ACT] = 1
cpu7.mem[ETANK_BULLET_X] = 10
cpu7.mem[ETANK_BULLET_Y] = 10
life0 = cpu7.mem[TANK_LIFE]
call_routine(cpu7, "CHECK_ETANK_BULLET_VS_TANK")
check("a far-away bullet doesn't false-trigger", cpu7.mem[TANK_LIFE] == life0)

cpu8 = fresh_cpu()
cpu8.mem[ETANK_BULLET_ACT] = 0
life0 = cpu8.mem[TANK_LIFE]
call_routine(cpu8, "CHECK_ETANK_BULLET_VS_TANK")
check("an inactive bullet never damages the tank", cpu8.mem[TANK_LIFE] == life0)

cpu9 = fresh_cpu()
tx = cpu9.mem[TANK_X] + TANK_COLLISION_X_OFFSET
ty = cpu9.mem[TANK_Y_CUR] + TANK_COLLISION_Y_OFFSET
cpu9.mem[TANK_HAZARD_IFRAMES] = 5
cpu9.mem[ETANK_BULLET_ACT] = 1
cpu9.mem[ETANK_BULLET_X] = tx
cpu9.mem[ETANK_BULLET_Y] = ty
life0 = cpu9.mem[TANK_LIFE]
call_routine(cpu9, "CHECK_ETANK_BULLET_VS_TANK")
check("no repeat damage while TANK_HAZARD_IFRAMES is still active", cpu9.mem[TANK_LIFE] == life0)


# ---------- real end-to-end: the 32px trigger + a real MAINLOOP playthrough ----------
cpu10 = fresh_cpu()
call_routine(cpu10, "ALLOC_ETANK_SLOT")
start_x = cpu10.mem[ETANK_POOL + 1]
fired_frame = None
for f in range(60):
    cpu10.ix = ETANK_POOL
    call_routine(cpu10, "UPDATE_ONE_ETANK")
    if cpu10.mem[ETANK_BULLET_ACT] == 1 and fired_frame is None:
        fired_frame = f
        moved = start_x - cpu10.mem[ETANK_POOL + 1]
check("a real Etank instance fires its own bullet once it has moved >=32px from spawn",
      fired_frame is not None and moved >= 32)
check("the fired flag is set (won't refire)", cpu10.mem[ETANK_BULLET_FIRED] == 1)
prev = cpu10.mem[ETANK_BULLET_FIRED]
for f in range(30):
    cpu10.ix = ETANK_POOL
    call_routine(cpu10, "UPDATE_ONE_ETANK")
check("the fired flag stays set (no refire) over many more frames", cpu10.mem[ETANK_BULLET_FIRED] == 1)

cpu11 = fresh_cpu()
cpu11.sim_dir = 1
cpu11.sim_trig_a = True
cpu11.sim_trig_b = False
ever_fired = False
for f in range(8000):
    step_frame(cpu11)
    if cpu11.mem[sym["BOSS_ACT"]] != 0:
        break
    if cpu11.mem[ETANK_BULLET_ACT] == 1:
        ever_fired = True
        break
check("real MAINLOOP play: EtankBullet actually fires before the boss spawns", ever_fired)


# ---------- 実機フィードバック対応その2("戦車の弾はコリジョンが
# セル間の移動はちゃんとpx単位で移動してるか?...ちゃんとドット単位で
# コリジョンも動いてるなら表示のズレがあるってことだ...ETankの弾の
# コリジョンを縮めれば良いってことだな コリジョンは1pxでいいや"):
# 前ラウンドの「表示と同じAND 0F8hへ判定側を量子化する」修正を撤回し、
# 判定サイズ自体を1x1pxへ縮小(生の連続座標そのまま、量子化なし)。
# 生の1点は定義上必ずその瞬間の表示セル内に収まるため、8px境界問題
# そのものが原理的に発生しなくなる。
def hit_registers(bullet_x, bullet_y, tank_x, tank_y):
    cpu = fresh_cpu()
    cpu.mem[ETANK_BULLET_ACT] = 1
    cpu.mem[ETANK_BULLET_X] = bullet_x & 0xFF
    cpu.mem[ETANK_BULLET_Y] = bullet_y & 0xFF
    cpu.mem[TANK_X] = tank_x & 0xFF
    cpu.mem[TANK_Y_CUR] = tank_y & 0xFF
    cpu.mem[TANK_HAZARD_IFRAMES] = 0
    life0 = cpu.mem[TANK_LIFE]
    call_routine(cpu, "CHECK_ETANK_BULLET_VS_TANK")
    return cpu.mem[TANK_LIFE] != life0

# a tank positioned 1px to the right of the bullet's exact dot must NOT
# be hit (this would have been a false-positive under the old 8x8 box -
# even the BG-cell-aligned 8x8 fix from the previous round would still
# have flagged this as a hit, since both bullet_x and bullet_x+1 usually
# share the same floor(x/8)*8 cell).
BULLET_X = 45
TANK_Y_CUR_FIXED = 100
BULLET_Y = TANK_Y_CUR_FIXED + TANK_COLLISION_Y_OFFSET
tank_x_one_past = BULLET_X + 1 - TANK_COLLISION_X_OFFSET
check("a tank positioned just 1px to the right of the bullet's own dot is NOT hit "
      "(1px hitbox, not an 8px box)",
      not hit_registers(BULLET_X, BULLET_Y, tank_x_one_past, TANK_Y_CUR_FIXED))

# sanity: a tank whose box exactly touches the bullet's own dot still
# takes damage (the fix must not have made the hitbox disappear entirely)
tank_x_on_dot = BULLET_X - TANK_COLLISION_X_OFFSET
check("...but a tank whose box exactly overlaps the bullet's own dot still gets hit normally",
      hit_registers(BULLET_X, BULLET_Y, tank_x_on_dot, TANK_Y_CUR_FIXED))

# full sweep, all 8 BG-cell phases of bullet_x, cross-checked against a
# pure 1x1px hitbox model at the bullet's own raw (continuous) X/Y -
# no BG-cell quantization anywhere in the reference model either.
def expected_hit_1px(tank_x, tank_y, bullet_x, bullet_y):
    tx0 = tank_x + TANK_COLLISION_X_OFFSET
    tx1 = tx0 + TANK_COLLISION_WIDTH - 1
    ty0 = tank_y + TANK_COLLISION_Y_OFFSET
    ty1 = ty0 + TANK_COLLISION_HEIGHT - 1
    return not (bullet_x < tx0 or tx1 < bullet_x or bullet_y < ty0 or ty1 < bullet_y)

mismatches = 0
total = 0
SWEEP_TANK_Y_CUR = 100
SWEEP_BULLET_Y = SWEEP_TANK_Y_CUR + TANK_COLLISION_Y_OFFSET
for bullet_x in range(0, 200, 3):
    for tank_x in range(max(0, bullet_x - 24), bullet_x + 24, 2):
        got = hit_registers(bullet_x, SWEEP_BULLET_Y, tank_x, SWEEP_TANK_Y_CUR)
        exp = expected_hit_1px(tank_x, SWEEP_TANK_Y_CUR, bullet_x, SWEEP_BULLET_Y)
        total += 1
        if got != exp:
            mismatches += 1
check(f"CHECK_ETANK_BULLET_VS_TANK matches a pure 1x1px hitbox model (raw, unquantized X/Y) "
      f"exactly across {total} bullet/tank X positions spanning every BG-cell boundary phase",
      mismatches == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
