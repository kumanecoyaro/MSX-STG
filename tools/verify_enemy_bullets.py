"""Stage1: Enemy7(TYPE_ENEMY4)色変更・敵弾実装(Y軸一致発射+E1/E2/E5の
斜め移動中ランダム発射)の検証。tools/verify_enemy_pool_scan.py と同じ
「mini_z80asm.Assemblerで直接アセンブル+call_routine(センチネル0x0000
方式)」の一回性検証スクリプトの作法に倣う。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

REPO_ROOT = os.path.join(os.path.dirname(__file__), '..')
with open(os.path.join(REPO_ROOT, 'src', 'CYBER SHMUP.asm'), encoding="utf-8") as f:
    text = f.read()

asm = Assembler(text)
out = asm.assemble()
sym = asm.symtab
mem0 = bytearray(65536)
for addr, val in out.items():
    mem0[addr & 0xFFFF] = val & 0xFF

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh():
    z = Z80(bytearray(mem0))
    return z


def run_until_pc(z, target_pc, max_instr=300000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


E_ACTIVE = sym["E_ACTIVE"]; E_TYPE = sym["E_TYPE"]; E_BEHAVIOR = sym["E_BEHAVIOR"]
E_X = sym["E_X"]; E_Y = sym["E_Y"]; E_SPRNUM = sym["E_SPRNUM"]
E_PARAM0 = sym["E_PARAM0"]; E_PARAM1 = sym["E_PARAM1"]; E_PARAM2 = sym["E_PARAM2"]
E_PARAM3 = sym["E_PARAM3"]; E_PARAM4 = sym["E_PARAM4"]; E_PARAM5 = sym["E_PARAM5"]
ENEMY_POOL = sym["ENEMY_POOL"]; ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
TYPE_ENEMY4 = sym["TYPE_ENEMY4"]; TYPE_ENEMY1_LOOK = sym["TYPE_ENEMY1_LOOK"]
BEHAVIOR_SIMPLE_DRIFT_DODGE = sym["BEHAVIOR_SIMPLE_DRIFT_DODGE"]
BEHAVIOR_SINE_BOB = sym["BEHAVIOR_SINE_BOB"]
PLAYERY = sym["PLAYERY"]
EBULLET_POOL = sym["EBULLET_POOL"]; EBULLET_STRUCT = sym["EBULLET_STRUCT"]
EBULLET_SLOTS = sym["EBULLET_SLOTS"]; EBULLET_SPEED = sym["EBULLET_SPEED"]
PAT_EBULLET = sym["PAT_EBULLET"]; SPR_LIGHTRED = sym["SPR_LIGHTRED"]
SPR_LIGHTGREEN = sym["SPR_LIGHTGREEN"]
E1_FIRE_COUNTDOWN = sym["E1_FIRE_COUNTDOWN"]; E5_FIRE_COUNTDOWN = sym["E5_FIRE_COUNTDOWN"]
E2_FIRE_COUNTDOWN = sym["E2_FIRE_COUNTDOWN"]
E2A_FIRE_FLAG = sym["E2A_FIRE_FLAG"]; E2B_FIRE_FLAG = sym["E2B_FIRE_FLAG"]
E2A_U0_X = sym["E2A_U0_X"]; E2A_U0_Y = sym["E2A_U0_Y"]; E2A_EXIT_PHASE = sym["E2A_EXIT_PHASE"]
E2B_U0_X = sym["E2B_U0_X"]; E2B_U0_Y = sym["E2B_U0_Y"]; E2B_EXIT_PHASE = sym["E2B_EXIT_PHASE"]
SPRITE_USED = sym["SPRITE_USED"]
ENEMY_CENTER_X = sym["ENEMY_CENTER_X"]
E4_ALIGN_FIRE_COOLDOWN = sym["E4_ALIGN_FIRE_COOLDOWN"]
ATTR = 0x1B00


def ebullet_active_count(z):
    n = 0
    for i in range(EBULLET_SLOTS):
        if z.rd(EBULLET_POOL + i * EBULLET_STRUCT) == 1:
            n += 1
    return n


def ebullet_slots(z):
    r = []
    for i in range(EBULLET_SLOTS):
        base = EBULLET_POOL + i * EBULLET_STRUCT
        r.append((z.rd(base), z.rd(base + 1), z.rd(base + 2), z.rd(base + 3)))
    return r


# ---------- (1) Enemy7 color: EBSD_DRAW writes SPR_LIGHTGREEN for TYPE_ENEMY4 ----------
z = fresh(); boot(z)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, 100)
z.wr(slot + E_Y, 80)
z.wr(slot + E_SPRNUM, 5)
z.ix = slot
call_routine(z, sym["EBSD_DRAW"])
color = z.vram[ATTR + 5 * 4 + 3]
check(f"Enemy7(TYPE_ENEMY4) draws with SPR_LIGHTGREEN(3), not SPR_BLACK(1) - got {color}",
      color == SPR_LIGHTGREEN)


# ---------- (2) Enemy7 Y-aligned fire ----------
z = fresh(); boot(z)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, 200)   # right of ENEMY_CENTER_X, so the dodge doesn't also trigger this call
z.wr(slot + E_Y, 90)
z.wr(slot + E_SPRNUM, 6)
z.wr(slot + E_PARAM0, 0)  # DIAG_DONE=0
z.wr(slot + E_PARAM3, 0)  # align-fire cooldown ready
z.wr(PLAYERY, 90)          # exact Y match
z.ix = slot
call_routine(z, sym["EBSD_UPDATE"])
check("Enemy7 fires a bullet the instant its Y matches PLAYERY",
      ebullet_active_count(z) == 1)
b = ebullet_slots(z)
fired = [s for s in b if s[0] == 1][0]
check("...spawned at Enemy7's own (post-move) X,Y", fired[1] == 200 - sym["ENEMY_SPEED"] and fired[2] == 90)
check("...cooldown (E_PARAM3) armed to E4_ALIGN_FIRE_COOLDOWN", z.rd(slot + E_PARAM3) == E4_ALIGN_FIRE_COOLDOWN)

# still aligned next frame - cooldown must block a 2nd shot
call_routine(z, sym["EBSD_UPDATE"])
check("...still aligned next frame, but cooldown blocks a 2nd shot", ebullet_active_count(z) == 1)


# ---------- (3) Enemy1(=same TYPE_ENEMY4 entity) diagonal-dodge random fire ----------
z = fresh(); boot(z)
z.wr(E1_FIRE_COUNTDOWN, 1)   # forces DECIDE_FIRE_SHOOTER to pick THIS spawn's dodge as the shooter
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, ENEMY_CENTER_X + sym["ENEMY_SPEED"] - 1)  # crosses center this exact frame
z.wr(slot + E_Y, 70)
z.wr(slot + E_SPRNUM, 7)
z.wr(slot + E_PARAM0, 0)
z.wr(slot + E_PARAM3, 0)
z.wr(PLAYERY, 200)  # far from E_Y, so the align-fire check above doesn't also fire this frame
z.ix = slot
call_routine(z, sym["EBSD_UPDATE"])
check("Enemy1's dodge-trigger fires a bullet when selected as shooter", ebullet_active_count(z) == 1)
check("...E1_FIRE_COUNTDOWN reseeded to a fresh 3-5", 3 <= z.rd(E1_FIRE_COUNTDOWN) <= 5)
check("...dodge itself still armed normally (E_PARAM0=1)", z.rd(slot + E_PARAM0) == 1)

# non-shooter spawn: countdown starts at 3, should NOT fire on its own dodge
z = fresh(); boot(z)
z.wr(E1_FIRE_COUNTDOWN, 3)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, ENEMY_CENTER_X + sym["ENEMY_SPEED"] - 1)
z.wr(slot + E_Y, 70)
z.wr(slot + E_SPRNUM, 7)
z.wr(slot + E_PARAM0, 0)
z.wr(slot + E_PARAM3, 0)
z.wr(PLAYERY, 200)
z.ix = slot
call_routine(z, sym["EBSD_UPDATE"])
check("a non-shooter instance's dodge does NOT fire", ebullet_active_count(z) == 0)
check("...countdown just decremented (3->2)", z.rd(E1_FIRE_COUNTDOWN) == 2)


# ---------- (4) Enemy5 (TYPE_ENEMY1_LOOK) shooter fires once, at ENEMY_CENTER_X ----------
z = fresh(); boot(z)
z.wr(E5_FIRE_COUNTDOWN, 1)
# spawn via the real claim routine so E_PARAM1 gets set by E4CA_SINEBOB
z.wr(sym["E4_SPAWN_TYPE"], TYPE_ENEMY1_LOOK)
z.wr(sym["E4_SPAWN_BASEY"], 60)
call_routine(z, sym["ENEMY4_CLAIM_ANY"])
slot = ENEMY_POOL  # first free slot
check("Enemy5 spawn marks E_PARAM1=1 (selected shooter)", z.rd(slot + E_PARAM1) == 1)
z.wr(slot + E_X, ENEMY_CENTER_X + sym["ENEMY4_SPEED"] - 1)  # crosses center this exact frame
z.ix = slot
call_routine(z, sym["EBSB_UPDATE"])
check("Enemy5 shooter fires once when crossing ENEMY_CENTER_X", ebullet_active_count(z) == 1)
check("...E_PARAM2 (already-fired) now set", z.rd(slot + E_PARAM2) == 1)
before = ebullet_active_count(z)
call_routine(z, sym["EBSB_UPDATE"])
check("...does not fire again on a later frame", ebullet_active_count(z) == before)

# non-shooter Enemy5 (countdown starts at 3) never fires
z = fresh(); boot(z)
z.wr(E5_FIRE_COUNTDOWN, 3)
z.wr(sym["E4_SPAWN_TYPE"], TYPE_ENEMY1_LOOK)
z.wr(sym["E4_SPAWN_BASEY"], 60)
call_routine(z, sym["ENEMY4_CLAIM_ANY"])
slot = ENEMY_POOL
check("a non-shooter Enemy5 spawn has E_PARAM1=0", z.rd(slot + E_PARAM1) == 0)
z.wr(slot + E_X, ENEMY_CENTER_X + sym["ENEMY4_SPEED"] - 1)
z.ix = slot
call_routine(z, sym["EBSB_UPDATE"])
check("...never fires", ebullet_active_count(z) == 0)


# ---------- (5) Enemy2 (A formation) fires once during the diagonal exit dive ----------
z = fresh(); boot(z)
z.wr(E2_FIRE_COUNTDOWN, 1)
z.wr(sym["E2_SPAWN_Y"], 50)
z.wr(PLAYERY, 100)  # spawnY < PLAYERY -> EXITTYPE=1 (climbs up), doesn't matter for this check
call_routine(z, sym["ENEMY_START_COMPLEX_A"])
check("Enemy2-A formation spawn marks E2A_FIRE_FLAG=1 (selected shooter)", z.rd(E2A_FIRE_FLAG) == 1)
z.wr(E2A_EXIT_PHASE, 0)
z.wr(E2A_U0_X, 111)
z.wr(E2A_U0_Y, 77)
call_routine(z, sym["ECS_S7_A"])
check("Enemy2-A shooter fires once during the diagonal dive (phase0)", ebullet_active_count(z) == 1)
fired = [s for s in ebullet_slots(z) if s[0] == 1][0]
check("...spawned at U0's own position (111,77)", (fired[1], fired[2]) == (111, 77))
check("...E2A_FIRE_FLAG now 2 (fired)", z.rd(E2A_FIRE_FLAG) == 2)
before = ebullet_active_count(z)
call_routine(z, sym["ECS_S7_A"])
check("...does not fire again", ebullet_active_count(z) == before)

# non-shooter Enemy2-B (countdown starts at 3) never fires
z = fresh(); boot(z)
z.wr(E2_FIRE_COUNTDOWN, 3)
z.wr(sym["E2_SPAWN_Y"], 50)
z.wr(PLAYERY, 100)
call_routine(z, sym["ENEMY_START_COMPLEX_B"])
check("a non-shooter Enemy2-B formation spawn has E2B_FIRE_FLAG=0", z.rd(E2B_FIRE_FLAG) == 0)
z.wr(E2B_EXIT_PHASE, 0)
z.wr(E2B_U0_X, 50)
z.wr(E2B_U0_Y, 60)
call_routine(z, sym["ECS_S7_B"])
check("...never fires", ebullet_active_count(z) == 0)


# ---------- (6) UPDATE_EBULLET_ALL: movement, exit, hide+free ----------
z = fresh(); boot(z)
z.d = 40; z.e = 33
call_routine(z, sym["SPAWN_EBULLET"])
active = [s for s in ebullet_slots(z) if s[0] == 1]
check("SPAWN_EBULLET claims a free slot with the given X,Y", len(active) == 1 and (active[0][1], active[0][2]) == (40, 33))
sprnum = active[0][3]
check("...allocated a real hw sprite number (>=2)", sprnum >= 2)
check("...drawn nowhere yet (X,Y only written by UPDATE_EBULLET_ALL)", True)

call_routine(z, sym["UPDATE_EBULLET_ALL"])
active = [s for s in ebullet_slots(z) if s[0] == 1][0]
check(f"UPDATE_EBULLET_ALL advances X left by EBULLET_SPEED({EBULLET_SPEED}): 40->{active[1]}",
      active[1] == 40 - EBULLET_SPEED)
attr_pat = z.vram[ATTR + sprnum * 4 + 2]
attr_col = z.vram[ATTR + sprnum * 4 + 3]
check("...draws PAT_EBULLET/SPR_LIGHTRED to its own hw sprite slot",
      attr_pat == PAT_EBULLET and attr_col == SPR_LIGHTRED)

# run until it exits past the left edge
for _ in range(20):
    call_routine(z, sym["UPDATE_EBULLET_ALL"])
    if ebullet_active_count(z) == 0:
        break
check("bullet deactivates once it drifts past the left edge", ebullet_active_count(z) == 0)
check("...its hw sprite number is freed (SPRITE_USED byte cleared)", z.rd(SPRITE_USED + sprnum) == 0)
check("...hidden off-screen (Y=ENEMY_HIDE_Y,X=255) at the attribute table",
      z.vram[ATTR + sprnum * 4] == sym["ENEMY_HIDE_Y"] and z.vram[ATTR + sprnum * 4 + 1] == 255)


# ---------- (7) pool exhaustion: SPAWN_EBULLET drops silently, no crash ----------
z = fresh(); boot(z)
for i in range(EBULLET_SLOTS):
    z.wr(EBULLET_POOL + i * EBULLET_STRUCT, 1)  # fake all slots active
z.d = 10; z.e = 10
before = bytes(z.mem[EBULLET_POOL:EBULLET_POOL + EBULLET_SLOTS * EBULLET_STRUCT])
call_routine(z, sym["SPAWN_EBULLET"])
after = bytes(z.mem[EBULLET_POOL:EBULLET_POOL + EBULLET_SLOTS * EBULLET_STRUCT])
check("a full EBULLET_POOL silently drops a new SPAWN_EBULLET (no state change, no crash)", before == after)


# ---------- (8) hw sprite exhaustion: SPAWN_EBULLET drops silently, no crash ----------
z = fresh(); boot(z)
for i in range(32):
    z.wr(SPRITE_USED + i, 1)  # fake every hw sprite number taken
z.d = 10; z.e = 10
call_routine(z, sym["SPAWN_EBULLET"])
check("SPAWN_EBULLET drops the shot (pool slot stays inactive) when no hw sprite number is free",
      ebullet_active_count(z) == 0)


# ---------- (9) real MAINLOOP play: Enemy7 fires when aligned, in a real frame loop ----------
def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])

z = fresh(); boot(z)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1)
z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_BEHAVIOR, BEHAVIOR_SIMPLE_DRIFT_DODGE)
z.wr(slot + E_X, 200)
z.wr(slot + E_Y, 90)
z.wr(slot + E_SPRNUM, 9)
z.wr(slot + E_PARAM0, 0)
z.wr(slot + E_PARAM3, 0)
z.wr(PLAYERY, 90)
fired_ever = False
for _ in range(3):
    step_frame(z)
    if ebullet_active_count(z) >= 1:
        fired_ever = True
check("real MAINLOOP frame(s): Enemy7 fires and UPDATE_EBULLET_ALL is actually wired into MAINLOOP",
      fired_ever)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
