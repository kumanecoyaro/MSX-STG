"""round36-14 follow-up#13 ("4フレームにして3発制限を4発に変更"): the
player's own shot pool grew from 3 slots (BULLET0/1/2_ACT) to 4
(BULLET3_ACT added) and SHOT_COOLDOWN_FRAMES dropped from 8 to 4.
BULLET0/1/2_ACT live in the tightly-packed F1xx block with zero slack
right after them (BULLET_TEMP_BYTE/GAME_TICK) - BULLET3_ACT was
relocated to the free C1xx region instead, same idiom as FLYER_POOL/
EBULLET_POOL/MINE_POOL. BULLET3's own U-type (diagonal) shots also
needed a real hw sprite ATTRIBUTE slot - freed from Mine's own
explosion budget (slot31, shared between MINE_SLOT_COUNT instances now
instead of 1-per-instance - see mine_flyerlaser_test.py) per direct
confirmation ("Mineは演出なのでMineを削ってくれ 2発同時はまず起こら
ないんで").
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


BULLET0_ACT = sym["BULLET0_ACT"]
BULLET1_ACT = sym["BULLET1_ACT"]
BULLET2_ACT = sym["BULLET2_ACT"]
BULLET3_ACT = sym["BULLET3_ACT"]
BULLET0_VARIANT = sym["BULLET0_VARIANT"]
BULLET1_VARIANT = sym["BULLET1_VARIANT"]
BULLET2_VARIANT = sym["BULLET2_VARIANT"]
BULLET3_VARIANT = sym["BULLET3_VARIANT"]
BULLET3_U_ATTRS = sym["BULLET3_U_ATTRS"]
BULLET_U_SPRITE_ATTRS = sym["BULLET_U_SPRITE_ATTRS"]
BULLET_U_SPR_BASE_SLOT = sym["BULLET_U_SPR_BASE_SLOT"]
BULLET_U_COLOR = sym["BULLET_U_COLOR"]
SHOT_COOLDOWN = sym["SHOT_COOLDOWN"]
SHOT_COOLDOWN_FRAMES = sym["SHOT_COOLDOWN_FRAMES"]
TANK_AIMUP = sym["TANK_AIMUP"]
TANK_FACING = sym["TANK_FACING"]
TANK_X = sym["TANK_X"]
TANK_Y_CUR = sym["TANK_Y_CUR"]
JOY_TRIGA = sym["JOY_TRIGA"]
BOSS_ACT = sym["BOSS_ACT"]
PAT_BULLETU = sym["PAT_BULLETU"]
PAT_BULLETU_L = sym["PAT_BULLETU_L"]


check("SHOT_COOLDOWN_FRAMES is 4 (実機フィードバック対応: was 8)",
      SHOT_COOLDOWN_FRAMES == 4)


# ---------- boot state: BULLET3_ACT/VARIANT/U_ATTRS all clean ----------
cpu0 = fresh_cpu()
check("BULLET3_ACT starts inactive at boot", cpu0.mem[BULLET3_ACT] == 0)
check("BULLET3_U_ATTRS starts hidden (Y=209) at boot", cpu0.mem[BULLET3_U_ATTRS] == 209)
check("...and it's actually flushed to hw sprite slot31 as hidden too",
      cpu0.vram[0x1B00 + 31*4] == 209)


# ---------- TRY_SPAWN_BULLET: allocates slot0,1,2,3 in order, then drops ----------
cpu = fresh_cpu()
cpu.mem[TANK_AIMUP] = 0
cpu.mem[TANK_FACING] = 0
for expect_addr, label in [(BULLET0_ACT, "slot0"), (BULLET1_ACT, "slot1"),
                            (BULLET2_ACT, "slot2"), (BULLET3_ACT, "slot3")]:
    call_routine(cpu, "TRY_SPAWN_BULLET")
    check(f"TRY_SPAWN_BULLET claims {label} in order", cpu.mem[expect_addr] == 1)
before = bytes(cpu.mem[a] for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT))
call_routine(cpu, "TRY_SPAWN_BULLET")
after = bytes(cpu.mem[a] for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT))
check("a 5th TRY_SPAWN_BULLET with all 4 slots full is silently dropped (no crash, no state change)",
      before == after)


# ---------- SET/GET_BULLET_VARIANT round-trip for the new slot3 ----------
cpu2 = fresh_cpu()
cpu2.ix = BULLET3_ACT
for v in (0, 1, 2):
    cpu2.a = v
    call_routine(cpu2, "SET_BULLET_VARIANT")
    check(f"SET_BULLET_VARIANT({v}) on slot3 writes BULLET3_VARIANT, not slot0/1/2's own",
          cpu2.mem[BULLET3_VARIANT] == v and cpu2.mem[BULLET0_VARIANT] == 0
          and cpu2.mem[BULLET1_VARIANT] == 0 and cpu2.mem[BULLET2_VARIANT] == 0)
    cpu2.ix = BULLET3_ACT
    call_routine(cpu2, "GET_BULLET_VARIANT")
    check(f"GET_BULLET_VARIANT reads slot3's own value ({v}) back", cpu2.a == v)
    cpu2.ix = BULLET3_ACT

# slot0/1/2 still resolve correctly too (3-way compare didn't break on the new 4th branch)
cpu2b = fresh_cpu()
for addr, vbyte in ((BULLET0_ACT, BULLET0_VARIANT), (BULLET1_ACT, BULLET1_VARIANT), (BULLET2_ACT, BULLET2_VARIANT)):
    cpu2b.ix = addr
    cpu2b.a = 2
    call_routine(cpu2b, "SET_BULLET_VARIANT")
    check(f"SET_BULLET_VARIANT still resolves slot at {hex(addr)} to its own variant byte",
          cpu2b.mem[vbyte] == 2)


# ---------- UPDATE_BULLETS advances all 4 slots ----------
cpu3 = fresh_cpu()
for addr in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT):
    cpu3.mem[addr+0] = 1   # ACT
    cpu3.mem[addr+1] = 0   # TYPE=F
    cpu3.mem[addr+2] = 15  # COL
    cpu3.mem[addr+3] = 10  # ROW
    cpu3.mem[addr+6] = 0   # FACING=right
before_cols = [cpu3.mem[a+2] for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT)]
call_routine(cpu3, "UPDATE_BULLETS")
after_cols = [cpu3.mem[a+2] for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT)]
check("UPDATE_BULLETS advances all 4 slots (including the new slot3), not just the original 3",
      all(a != b for a, b in zip(before_cols, after_cols)))


# ---------- UBUS_ONE / FLUSH_BULLET3_U_SPRITE: slot3's own U-type hw sprite ----------
cpu4 = fresh_cpu()
cpu4.mem[BOSS_ACT] = 0
cpu4.mem[BULLET3_ACT+0] = 1   # ACT
cpu4.mem[BULLET3_ACT+1] = 1   # TYPE=U
cpu4.mem[BULLET3_ACT+2] = 10  # COL
cpu4.mem[BULLET3_ACT+3] = 12  # ROW
cpu4.mem[BULLET3_ACT+6] = 0   # FACING=right
call_routine(cpu4, "UPDATE_BULLET_U_SPRITES")
check("an active U-type shot in slot3 draws Y=ROW*8/X=COL*8/PAT_BULLETU/BULLET_U_COLOR into BULLET3_U_ATTRS",
      cpu4.mem[BULLET3_U_ATTRS+0] == 12*8 and cpu4.mem[BULLET3_U_ATTRS+1] == 10*8
      and cpu4.mem[BULLET3_U_ATTRS+2] == PAT_BULLETU and cpu4.mem[BULLET3_U_ATTRS+3] == BULLET_U_COLOR)
check("...and it's actually flushed to hw sprite slot31 (not slots7-9, which belong to slots0-2)",
      cpu4.vram[0x1B00 + 31*4 + 2] == PAT_BULLETU)
check("...slots7-9 (BULLET_U_SPR_BASE_SLOT) are untouched by slot3's own flush (still hidden, nothing spawned there)",
      cpu4.vram[0x1B00 + BULLET_U_SPR_BASE_SLOT*4] == 209)

cpu5 = fresh_cpu()
cpu5.mem[BULLET3_ACT+0] = 0   # inactive
call_routine(cpu5, "UPDATE_BULLET_U_SPRITES")
check("an inactive slot3 hides hw sprite slot31 (Y=209)", cpu5.vram[0x1B00 + 31*4] == 209)

cpu6 = fresh_cpu()
cpu6.mem[BOSS_ACT] = 1
cpu6.mem[BULLET3_ACT+0] = 1
cpu6.mem[BULLET3_ACT+1] = 1   # TYPE=U, but boss fight -> U is BG-drawn instead, hw sprite must stay hidden
call_routine(cpu6, "UPDATE_BULLET_U_SPRITES")
check("a U-type shot in slot3 during the boss fight still hides slot31 (U is BG-drawn during BOSS_ACT, same as slots0-2)",
      cpu6.vram[0x1B00 + 31*4] == 209)


# ---------- collision: slot3 participates in hit detection too ----------
ENEMY_POOL = sym["ENEMY_POOL"]
cpu7 = fresh_cpu()
cpu7.mem[ENEMY_POOL+0] = 1
cpu7.mem[ENEMY_POOL+1] = 100
cpu7.mem[ENEMY_POOL+2] = 100
cpu7.mem[BULLET3_ACT+0] = 1
cpu7.mem[BULLET3_ACT+2] = 100 // 8
cpu7.mem[BULLET3_ACT+3] = 100 // 8
cpu7.ix = BULLET3_ACT
call_routine(cpu7, "CHECK_HIT_ONE_BULLET")
check("a bullet in the new slot3 can still register a hit against a real enemy (CHECK_HIT_ONE_BULLET)",
      cpu7.mem[BULLET3_ACT+0] == 0 or cpu7.mem[ENEMY_POOL+0] != 1)


# ---------- real MAINLOOP play: up to 4 concurrent shots actually happen ----------
cpu8 = fresh_cpu()
cpu8.sim_dir = 0
cpu8.sim_trig_a = True
cpu8.sim_trig_b = False
max_concurrent = 0
for f in range(300):
    step_frame(cpu8)
    active = sum(cpu8.mem[a] for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT))
    max_concurrent = max(max_concurrent, active)
check("real MAINLOOP play: holding fire continuously reaches all 4 concurrent shot slots at some point",
      max_concurrent == 4)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
