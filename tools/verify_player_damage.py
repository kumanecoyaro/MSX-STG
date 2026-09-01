"""Stage1: 自機ダメージ判定の検証("敵や敵弾に当たるとバリア耐久値1減少
なくなって当たれば終了")。PLAYER_HIT_BOX8/16・各PDC_CHECK_*・
PLAYER_DAMAGE_CHECK/PLAYER_TAKE_HITを、tools/verify_enemy_bullets.py と
同じ「mini_z80asm.Assemblerで直接アセンブル+call_routine/run_until_pcの
一回性検証スクリプト」の作法で検証する。
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
    return Z80(bytearray(mem0))


def run_until_pc(z, target_pc, max_instr=300000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frame(z):
    z.step()
    run_until_pc(z, sym["MAINLOOP"])


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


PLAYERX = sym["PLAYERX"]; PLAYERY = sym["PLAYERY"]
GAME_OVER = sym["GAME_OVER"]; BARRIER_HP = sym["BARRIER_HP"]
BARRIER_IFRAMES = sym["BARRIER_IFRAMES"]; BARRIER_IFRAMES_INIT = sym["BARRIER_IFRAMES_INIT"]
PLAYER_FLYAWAY = sym["PLAYER_FLYAWAY"]
ENEMY_POOL = sym["ENEMY_POOL"]; ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
E_ACTIVE = sym["E_ACTIVE"]; E_TYPE = sym["E_TYPE"]; E_X = sym["E_X"]; E_Y = sym["E_Y"]
E_TOP = sym["E_TOP"]; E_BOT = sym["E_BOT"]
TYPE_ENEMY4 = sym["TYPE_ENEMY4"]; TYPE_ENEMY1_LOOK = sym["TYPE_ENEMY1_LOOK"]
E2A_U0_STATE = sym["E2A_U0_STATE"]; E2A_U0_X = sym["E2A_U0_X"]; E2A_U0_Y = sym["E2A_U0_Y"]
E2A_U0_TOP = sym["E2A_U0_TOP"]; E2A_U0_BOT = sym["E2A_U0_BOT"]
E2A_U1_STATE = sym["E2A_U1_STATE"]
ENEMY3_POOL = sym["ENEMY3_POOL"]; ENEMY3_ACTIVE_COUNT = sym["ENEMY3_ACTIVE_COUNT"]
ENEMY6_POOL = sym["ENEMY6_POOL"]
BOSS_STATE = sym["BOSS_STATE"]; POD_HP = sym["POD_HP"]; POD_CUR_X = sym["POD_CUR_X"]; POD_CUR_Y = sym["POD_CUR_Y"]
EBULLET_POOL = sym["EBULLET_POOL"]; EBULLET_STRUCT = sym["EBULLET_STRUCT"]
SPRITE_USED = sym["SPRITE_USED"]
ANIM_BASE = sym["ANIM_BASE"]


# ---------- (1) PLAYER_HIT_BOX8 / PLAYER_HIT_BOX16 geometry ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)   # hitbox = (100,100)-(115,115)

def hit8(z, x, y):
    z.d = x; z.e = y
    call_routine(z, sym["PLAYER_HIT_BOX8"])
    return z.a

def hit16(z, x, y):
    z.d = x; z.e = y
    call_routine(z, sym["PLAYER_HIT_BOX16"])
    return z.a

check("PLAYER_HIT_BOX8: exact overlap (target at player's own top-left) hits",
      hit8(z, 100, 100) == 1)
check("PLAYER_HIT_BOX8: target's box entirely past the player's right/bottom edge misses",
      hit8(z, 116, 116) == 0)
check("PLAYER_HIT_BOX8: target box touching at the edge (115,115)-(122,122) still hits (edges inclusive)",
      hit8(z, 115, 115) == 1)
check("PLAYER_HIT_BOX8: far away misses",
      hit8(z, 0, 0) == 0)
check("PLAYER_HIT_BOX16: a 16x16 box at (108,108) (overlapping the player's center) hits",
      hit16(z, 108, 108) == 1)
check("PLAYER_HIT_BOX16: a 16x16 box far to the right misses",
      hit16(z, 200, 100) == 0)


# ---------- (2) PDC_CHECK_ENEMY_POOL ----------
def setup_enemy(z, etype, x, y, top=1, bot=1, behavior=None):
    slot = ENEMY_POOL
    z.wr(slot + E_ACTIVE, 1)
    z.wr(slot + E_TYPE, etype)
    z.wr(slot + E_X, x)
    z.wr(slot + E_Y, y)
    z.wr(slot + E_TOP, top)
    z.wr(slot + E_BOT, bot)
    return slot

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=1, bot=0)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave TOP quad overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=0, bot=1)   # BOT quad at (108,108)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave BOT quad overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
setup_enemy(z, TYPE_ENEMY1_LOOK, 200, 200, top=1, bot=1)   # far away
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave far away misses", z.a == 0)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1); z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_X, 100); z.wr(slot + E_Y, 92)   # E_Y+8 = 100 -> box at (100,100), overlaps
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Fighter(TYPE_ENEMY4)'s Y+8 hitbox overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 0); z.wr(slot + E_TYPE, TYPE_ENEMY1_LOOK)
z.wr(slot + E_X, 100); z.wr(slot + E_Y, 100); z.wr(slot + E_TOP, 1); z.wr(slot + E_BOT, 1)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: inactive slot never hits even at the same position", z.a == 0)


# ---------- (3) PDC_CHECK_E2_FORMATION ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(E2A_U0_STATE, 1); z.wr(E2A_U0_X, 100); z.wr(E2A_U0_Y, 100)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: U0 TOP quad overlapping the player hits (STATE=1)", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(E2A_U0_STATE, 0); z.wr(E2A_U0_X, 100); z.wr(E2A_U0_Y, 100)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: same position but STATE!=1 (not actively flying) never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(E2A_U0_STATE, 1); z.wr(E2A_U0_X, 200); z.wr(E2A_U0_Y, 200)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 1)
z.wr(E2A_U1_STATE, 1)
z.wr(sym["E2A_U1_X"], 100); z.wr(sym["E2A_U1_Y"], 100)
z.wr(sym["E2A_U1_TOP"], 1); z.wr(sym["E2A_U1_BOT"], 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: U0 misses but U1 (2nd unit, 5-byte stride) overlaps -> hits", z.a == 1)


# ---------- (4) PDC_CHECK_ENEMY3 ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(ENEMY3_ACTIVE_COUNT, 1)
z.wr(ENEMY3_POOL + 0, 1)          # ACTIVE
z.wr(ENEMY3_POOL + 5, 100 // 8)   # COL -> X=100
z.wr(ENEMY3_POOL + 4, 100 // 8)   # ROW -> Y=100
call_routine(z, sym["PDC_CHECK_ENEMY3"])
check("PDC_CHECK_ENEMY3: active slot's COL*8,ROW*8 box overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(ENEMY3_ACTIVE_COUNT, 0)      # nothing alive anywhere - short-circuit
z.wr(ENEMY3_POOL + 0, 1)
z.wr(ENEMY3_POOL + 5, 100 // 8)
z.wr(ENEMY3_POOL + 4, 100 // 8)
call_routine(z, sym["PDC_CHECK_ENEMY3"])
check("PDC_CHECK_ENEMY3: ACTIVE_COUNT=0 short-circuits even if a slot's own ACTIVE byte is stale/nonzero", z.a == 0)


# ---------- (5) PDC_CHECK_ENEMY6 ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(ENEMY6_POOL + 0, 1)          # ACTIVE
z.wr(ENEMY6_POOL + 1, 100 // 8)   # ROW -> Y=100
z.wr(ENEMY6_POOL + 2, 100 // 8)   # COL -> X=100
call_routine(z, sym["PDC_CHECK_ENEMY6"])
check("PDC_CHECK_ENEMY6: active slot's 16x16 box overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(ENEMY6_POOL + 0, 0)
z.wr(ENEMY6_POOL + 1, 100 // 8)
z.wr(ENEMY6_POOL + 2, 100 // 8)
call_routine(z, sym["PDC_CHECK_ENEMY6"])
check("PDC_CHECK_ENEMY6: inactive slot never hits", z.a == 0)


# ---------- (6) PDC_CHECK_PODS ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(BOSS_STATE, 2)
z.wr(POD_HP + 3, 1)
z.wr(POD_CUR_X + 3, 100); z.wr(POD_CUR_Y + 3, 100)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: a live pod (POD_HP>0) at the player's own position hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(BOSS_STATE, 2)
z.wr(POD_HP + 3, 0)   # dead pod
z.wr(POD_CUR_X + 3, 100); z.wr(POD_CUR_Y + 3, 100)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: a dead pod (POD_HP=0) at the same position never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(BOSS_STATE, 0)   # boss not landed yet
z.wr(POD_HP + 3, 1)
z.wr(POD_CUR_X + 3, 100); z.wr(POD_CUR_Y + 3, 100)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: BOSS_STATE!=2 (boss not landed) never hits, even with a live pod at the same position", z.a == 0)


# ---------- (7) PDC_CHECK_EBULLET (consumes the bullet on hit) ----------
z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, 100); z.wr(EBULLET_POOL + 2, 100)
z.wr(EBULLET_POOL + 3, 5)
z.wr(SPRITE_USED + 5, 1)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: overlapping bullet hits", z.a == 1)
check("...and is deactivated (consumed, unlike enemy bodies)", z.rd(EBULLET_POOL + 0) == 0)
check("...its hw sprite number is freed (SPRITE_USED cleared)", z.rd(SPRITE_USED + 5) == 0)
check("...hidden off-screen at the attribute table",
      z.vram[0x1B00 + 5 * 4] == sym["ENEMY_HIDE_Y"] and z.vram[0x1B00 + 5 * 4 + 1] == 255)

z = fresh()
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, 200); z.wr(EBULLET_POOL + 2, 200)
z.wr(EBULLET_POOL + 3, 5)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: a bullet far away misses and stays active", z.a == 0 and z.rd(EBULLET_POOL + 0) == 1)


# ---------- (8) PLAYER_DAMAGE_CHECK / PLAYER_TAKE_HIT integration ----------
z = fresh(); boot(z)
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=1, bot=0)
before_hp = z.rd(BARRIER_HP)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: a real contact costs exactly 1 barrier HP",
      z.rd(BARRIER_HP) == before_hp - 1)
check("...and arms BARRIER_IFRAMES", z.rd(BARRIER_IFRAMES) == BARRIER_IFRAMES_INIT)
check("...GAME_OVER stays 0 (barrier still had HP left)", z.rd(GAME_OVER) == 0)

# still overlapping next frame, but iframes should block a 2nd decrement
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("...still overlapping next frame, but iframes block a 2nd HP loss",
      z.rd(BARRIER_HP) == before_hp - 1)
check("...iframes counted down by 1", z.rd(BARRIER_IFRAMES) == BARRIER_IFRAMES_INIT - 1)

# run out the iframes window entirely while still overlapping - takes
# BARRIER_IFRAMES_INIT-1 more DEC-only calls to bring IFRAMES from
# INIT-1 down to exactly 0 (checked BEFORE decrementing each call), then
# one further call is the first to see IFRAMES==0 and re-run the actual
# collision check - that's the one that lands the 2nd hit.
for _ in range(BARRIER_IFRAMES_INIT - 1):
    call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("...iframes reach exactly 0 after INIT-1 further calls", z.rd(BARRIER_IFRAMES) == 0)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("...once iframes expire while still overlapping, a 2nd hit lands",
      z.rd(BARRIER_HP) == before_hp - 2)

# drain the barrier to 0, then the next hit (after iframes expire) ends the game
z = fresh(); boot(z)
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(BARRIER_HP, 0)
z.wr(BARRIER_IFRAMES, 0)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=1, bot=0)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: a hit at 0 barrier HP sets GAME_OVER", z.rd(GAME_OVER) == 1)
check("...triggers an explosion at the player's own position (ANIM_BASE slot0 ACTIVE)",
      z.rd(ANIM_BASE + 0) == 1)
check("...ANIM_BASE's own ROW/COL match (PLAYERX,PLAYERY-8)>>3",
      z.rd(ANIM_BASE + 3) == (108 - 8) // 8 and z.rd(ANIM_BASE + 4) == 100 // 8)

# once GAME_OVER is set, further calls are a no-op (no further HP change, no crash)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: once GAME_OVER=1, further calls do nothing (still 0 HP, no underflow)",
      z.rd(BARRIER_HP) == 0)

# PLAYER_FLYAWAY gates collision off entirely (leaving the screen after a boss kill)
z = fresh(); boot(z)
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(PLAYER_FLYAWAY, 2)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=1, bot=0)
before_hp = z.rd(BARRIER_HP)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: no damage while PLAYER_FLYAWAY!=0, even overlapping an enemy",
      z.rd(BARRIER_HP) == before_hp and z.rd(GAME_OVER) == 0)


# ---------- (9) real MAINLOOP: a fatal hit actually freezes the game ----------
z = fresh(); boot(z)
z.wr(PLAYERX, 100); z.wr(PLAYERY, 108)
z.wr(BARRIER_HP, 0)
setup_enemy(z, TYPE_ENEMY1_LOOK, 100, 100, top=1, bot=0)
hit_this_frame = False
for _ in range(3):
    step_frame(z)
    if z.rd(GAME_OVER) == 1:
        hit_this_frame = True
        break
check("real MAINLOOP: a real frame loop actually reaches GAME_OVER=1 via PLAYER_DAMAGE_CHECK "
      "(wired into MAINLOOP's own tail)", hit_this_frame)

tick_before = z.rd(sym["TICK"])
pxg8_before = z.rd(sym["PXCHAR_G8"])
for _ in range(20):
    step_frame(z)
check("...once frozen, the terrain scroll counter (PXCHAR_G8, gated behind the frozen body) never advances",
      z.rd(sym["PXCHAR_G8"]) == pxg8_before)
check("...BARRIER_HP stays exactly 0 (no underflow) across many more frozen frames",
      z.rd(BARRIER_HP) == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
