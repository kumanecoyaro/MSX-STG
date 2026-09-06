"""Stage1: 自機ダメージ判定の検証(初回実装+フィードバック対応)。
PLAYER_HIT_BOX8/16(自機ヒットボックス=下側左8x8に縮小)・各PDC_CHECK_*・
PLAYER_DAMAGE_CHECK/PLAYER_TAKE_HIT(バリア吸収時=カラーチェンジ+
ブザー音、バリア枯渇後の被弾=16x16スプライト爆発バースト、ゲームは
フリーズさせない)を、tools/verify_enemy_bullets.py と同じ
「mini_z80asm.Assemblerで直接アセンブル+call_routine/run_until_pcの
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

# (2026-09-06、MISSION 1導入演出): INIT内のMISSION_DELAY_3SEC(実機では
# 約3秒のZ80クロック直接カウントのビジーウェイト、LD D,10で約130万
# 命令)がこのファイルのboot()呼び出し全てに乗ってしまい、既存の
# run_until_pc/call_routineの命令数上限を軽く超えてしまう。実ROMは
# 変更せず、このテストプロセス内でのみLD D,10の即値(MISSION_DELAY_
# 3SEC+1)を1へ縮小(約13万命令、既存の上限内に収まる)。
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

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
PLAYER_ACCENT_COLOR = sym["PLAYER_ACCENT_COLOR"]
SPR_WHITE = sym["SPR_WHITE"]; SPR_PURPLE = sym["SPR_PURPLE"]; SPR_LIGHTRED = sym["SPR_LIGHTRED"]
SND_BARRIER_DUTY_TIMER = sym["SND_BARRIER_DUTY_TIMER"]
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
PLAYER_EXPL_POOL = sym["PLAYER_EXPL_POOL"]; PLAYER_EXPL_STRUCT = sym["PLAYER_EXPL_STRUCT"]
PLAYER_EXPL_SLOTS = sym["PLAYER_EXPL_SLOTS"]
PLAYER_EXPL_TOTAL_TIMER = sym["PLAYER_EXPL_TOTAL_TIMER"]; PLAYER_EXPL_SPAWN_TIMER = sym["PLAYER_EXPL_SPAWN_TIMER"]
PLAYER_EXPL_LIFE = sym["PLAYER_EXPL_LIFE"]; PLAYER_EXPL_SPAWN_INTERVAL = sym["PLAYER_EXPL_SPAWN_INTERVAL"]
PLAYER_EXPL_TOTAL_LEN = sym["PLAYER_EXPL_TOTAL_LEN"]
PAT_PLAYER_EXPLOSION = sym["PAT_PLAYER_EXPLOSION"]
PAT_ENEMY4_2 = sym["PAT_ENEMY4_2"]
SPRPAT = sym["SPRPAT"]
ATTR = 0x1B00


# Player hitbox is now (PLAYERX,PLAYERY)-(+7,+7) - "自機のヒットボックス
# は下側8x8に" - use a fixed player position for every scenario below.
PX, PY = 100, 108   # hitbox = (100,108)-(107,115)


# ---------- (1) PLAYER_HIT_BOX8 / PLAYER_HIT_BOX16 geometry ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)

def hit8(z, x, y):
    z.d = x; z.e = y
    call_routine(z, sym["PLAYER_HIT_BOX8"])
    return z.a

def hit16(z, x, y):
    z.d = x; z.e = y
    call_routine(z, sym["PLAYER_HIT_BOX16"])
    return z.a

check("PLAYER_HIT_BOX8: exact overlap (target at the player's own top-left) hits",
      hit8(z, PX, PY) == 1)
check("PLAYER_HIT_BOX8: target box touching at the far corner (107,115) still hits (edges inclusive)",
      hit8(z, PX + 7, PY + 7) == 1)
check("PLAYER_HIT_BOX8: target box just past the player's right/bottom edge misses",
      hit8(z, PX + 8, PY + 8) == 0)
check("PLAYER_HIT_BOX8: far away misses", hit8(z, 0, 0) == 0)
check("PLAYER_HIT_BOX16: a 16x16 box overlapping the player's 8x8 hitbox hits",
      hit16(z, PX - 4, PY - 4) == 1)
check("PLAYER_HIT_BOX16: a 16x16 box far to the right misses",
      hit16(z, 200, 100) == 0)


# ---------- (2) PDC_CHECK_ENEMY_POOL ----------
def setup_enemy(z, etype, x, y, top=1, bot=1):
    slot = ENEMY_POOL
    z.wr(slot + E_ACTIVE, 1)
    z.wr(slot + E_TYPE, etype)
    z.wr(slot + E_X, x)
    z.wr(slot + E_Y, y)
    z.wr(slot + E_TOP, top)
    z.wr(slot + E_BOT, bot)
    return slot

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX, PY, top=1, bot=0)   # TOP quad at the player's own top-left
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave TOP quad overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX - 8, PY - 8, top=0, bot=1)   # BOT quad = (X+8,Y+8) = (PX,PY)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave BOT quad overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
setup_enemy(z, TYPE_ENEMY1_LOOK, 200, 200, top=1, bot=1)   # far away
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Wave far away misses", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 1); z.wr(slot + E_TYPE, TYPE_ENEMY4)
z.wr(slot + E_X, PX); z.wr(slot + E_Y, PY - 8)   # E_Y+8 = PY -> box at (PX,PY)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: Fighter(TYPE_ENEMY4)'s Y+8 hitbox overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
slot = ENEMY_POOL
z.wr(slot + E_ACTIVE, 0); z.wr(slot + E_TYPE, TYPE_ENEMY1_LOOK)
z.wr(slot + E_X, PX); z.wr(slot + E_Y, PY); z.wr(slot + E_TOP, 1); z.wr(slot + E_BOT, 1)
call_routine(z, sym["PDC_CHECK_ENEMY_POOL"])
check("PDC_CHECK_ENEMY_POOL: inactive slot never hits even at the same position", z.a == 0)


# ---------- (3) PDC_CHECK_E2_FORMATION ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(E2A_U0_STATE, 1); z.wr(E2A_U0_X, PX); z.wr(E2A_U0_Y, PY)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: U0 TOP quad overlapping the player hits (STATE=1)", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(E2A_U0_STATE, 0); z.wr(E2A_U0_X, PX); z.wr(E2A_U0_Y, PY)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: same position but STATE!=1 (not actively flying) never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(E2A_U0_STATE, 1); z.wr(E2A_U0_X, 200); z.wr(E2A_U0_Y, 200)
z.wr(E2A_U0_TOP, 1); z.wr(E2A_U0_BOT, 1)
z.wr(E2A_U1_STATE, 1)
z.wr(sym["E2A_U1_X"], PX); z.wr(sym["E2A_U1_Y"], PY)
z.wr(sym["E2A_U1_TOP"], 1); z.wr(sym["E2A_U1_BOT"], 0)
z.sethl(E2A_U0_STATE)
call_routine(z, sym["PDC_CHECK_E2_FORMATION"])
check("PDC_CHECK_E2_FORMATION: U0 misses but U1 (2nd unit, 5-byte stride) overlaps -> hits", z.a == 1)


# ---------- (4) PDC_CHECK_ENEMY3 ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(ENEMY3_ACTIVE_COUNT, 1)
z.wr(ENEMY3_POOL + 0, 1)          # ACTIVE
z.wr(ENEMY3_POOL + 5, 12)         # COL -> X=96
z.wr(ENEMY3_POOL + 4, 13)         # ROW -> Y=104 (box 96..103,104..111 overlaps 100..107,108..115)
call_routine(z, sym["PDC_CHECK_ENEMY3"])
check("PDC_CHECK_ENEMY3: active slot's COL*8,ROW*8 box overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(ENEMY3_ACTIVE_COUNT, 0)      # nothing alive anywhere - short-circuit
z.wr(ENEMY3_POOL + 0, 1)
z.wr(ENEMY3_POOL + 5, 12)
z.wr(ENEMY3_POOL + 4, 13)
call_routine(z, sym["PDC_CHECK_ENEMY3"])
check("PDC_CHECK_ENEMY3: ACTIVE_COUNT=0 short-circuits even if a slot's own ACTIVE byte is stale/nonzero", z.a == 0)


# ---------- (5) PDC_CHECK_ENEMY6 ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(ENEMY6_POOL + 0, 1)          # ACTIVE
z.wr(ENEMY6_POOL + 1, 12)         # ROW -> Y=96
z.wr(ENEMY6_POOL + 2, 12)         # COL -> X=96 (16x16 box easily reaches the 8x8 hitbox)
call_routine(z, sym["PDC_CHECK_ENEMY6"])
check("PDC_CHECK_ENEMY6: active slot's 16x16 box overlapping the player hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(ENEMY6_POOL + 0, 0)
z.wr(ENEMY6_POOL + 1, 12)
z.wr(ENEMY6_POOL + 2, 12)
call_routine(z, sym["PDC_CHECK_ENEMY6"])
check("PDC_CHECK_ENEMY6: inactive slot never hits", z.a == 0)


# ---------- (6) PDC_CHECK_PODS (own inline PLAYERY reference, no SUB 8 anymore) ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BOSS_STATE, 2)
z.wr(POD_HP + 3, 1)
z.wr(POD_CUR_X + 3, PX); z.wr(POD_CUR_Y + 3, PY)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: a live pod (POD_HP>0) at the player's own (PLAYERX,PLAYERY) hits", z.a == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BOSS_STATE, 2)
z.wr(POD_HP + 3, 0)   # dead pod
z.wr(POD_CUR_X + 3, PX); z.wr(POD_CUR_Y + 3, PY)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: a dead pod (POD_HP=0) at the same position never hits", z.a == 0)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BOSS_STATE, 0)   # boss not landed yet
z.wr(POD_HP + 3, 1)
z.wr(POD_CUR_X + 3, PX); z.wr(POD_CUR_Y + 3, PY)
call_routine(z, sym["PDC_CHECK_PODS"])
check("PDC_CHECK_PODS: BOSS_STATE!=2 (boss not landed) never hits, even with a live pod at the same position", z.a == 0)


# ---------- (7) PDC_CHECK_EBULLET (consumes the bullet on hit) ----------
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, PX); z.wr(EBULLET_POOL + 2, PY)
z.wr(EBULLET_POOL + 3, 5)
z.wr(SPRITE_USED + 5, 1)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: overlapping bullet hits", z.a == 1)
check("...and is deactivated (consumed, unlike enemy bodies)", z.rd(EBULLET_POOL + 0) == 0)
check("...its hw sprite number is freed (SPRITE_USED cleared)", z.rd(SPRITE_USED + 5) == 0)
check("...hidden off-screen at the attribute table",
      z.vram[ATTR + 5 * 4] == sym["ENEMY_HIDE_Y"] and z.vram[ATTR + 5 * 4 + 1] == 255)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, 200); z.wr(EBULLET_POOL + 2, 200)
z.wr(EBULLET_POOL + 3, 5)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: a bullet far away misses and stays active", z.a == 0 and z.rd(EBULLET_POOL + 0) == 1)

# 実機フィードバック"判定も大きい様に感じる 多分上下2pxしか無いはず
# だけど" - EBULLETの実際の絵(横棒バー)はスプライト原点+2〜+3行の
# 2pxのみ(EBULLET_PATTERN自身のコメント参照)。PLAYER_HIT_BOX16の
# フル16x16のままなら判定するはずだが、PLAYER_HIT_BOX_EBULLETの
# 2px帯では判定しないはずのY位置で実際に検証する。
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)   # player hitbox Y band: [PY, PY+7] = [108,115]
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, PX); z.wr(EBULLET_POOL + 2, PY - 6)  # bullet origin Y=102, bar band=[104,105]
z.wr(EBULLET_POOL + 3, 5)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: bullet whose 16x16 sprite box overlaps the player but whose real "
      "2px bar (origin+2/+3) does NOT reach the player's own hitbox correctly misses "
      "(old full-16x16 PLAYER_HIT_BOX16 would have wrongly hit here)",
      z.a == 0 and z.rd(EBULLET_POOL + 0) == 1)

z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, PX); z.wr(EBULLET_POOL + 2, PY - 2)  # bullet origin Y=106, bar band=[108,109]
z.wr(EBULLET_POOL + 3, 5)
z.wr(SPRITE_USED + 5, 1)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: bullet whose real 2px bar band just touches the top of the "
      "player's own hitbox still correctly hits", z.a == 1 and z.rd(EBULLET_POOL + 0) == 0)

# 実機フィードバック"それも先端の1pxで良いかな その方が少しは速いし" -
# 2px帯(origin+2/+3)からさらに単一ピクセル(origin+2のみ)へ縮小。
# origin+3行だけが自機ヒットボックスに触れ、origin+2行は触れない位置を
# 作り、旧2px帯なら命中していたはずのケースが新1px判定では外れることを
# 直接確認する(revert self-check: 一時的にADD A,2をADD A,3へ戻すと
# このテストがFAILすることを確認済み)。
z = fresh()
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)   # player hitbox Y band: [PY, PY+7]
z.wr(EBULLET_POOL + 0, 1); z.wr(EBULLET_POOL + 1, PX); z.wr(EBULLET_POOL + 2, PY - 3)
# origin+2 = PY-1 (just above the player's hitbox, must miss), origin+3 = PY
# (would have been inside the old 2px band's hit range)
z.wr(EBULLET_POOL + 3, 5)
call_routine(z, sym["PDC_CHECK_EBULLET"])
check("PDC_CHECK_EBULLET: 1px-tip judged strictly at origin+2 - a bullet whose old-style "
      "origin+3 row would have grazed the player, but whose true origin+2 tip sits one row "
      "above it, now correctly misses",
      z.a == 0 and z.rd(EBULLET_POOL + 0) == 1)


# ---------- (8) PLAYER_DAMAGE_CHECK / PLAYER_TAKE_HIT - barrier-absorbed hit ----------
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX, PY, top=1, bot=0)
before_hp = z.rd(BARRIER_HP)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: a real contact costs exactly 1 barrier HP",
      z.rd(BARRIER_HP) == before_hp - 1)
check("...and arms BARRIER_IFRAMES", z.rd(BARRIER_IFRAMES) == BARRIER_IFRAMES_INIT)
check("...GAME_OVER stays 0 (barrier still had HP left)", z.rd(GAME_OVER) == 0)
check("...does NOT trigger the sprite-explosion burst (that's only for the post-barrier hit)",
      z.rd(PLAYER_EXPL_TOTAL_TIMER) == 0)
# "サウンドはブブって2回低音のデューティ比25％最大音量で" - SOUND_
# BARRIER_HIT's actual PSG writes aren't observable (z80emu.py has no
# PSG emulation - see CALC_NOISE_GATE_VOLUME's own comment), but the
# duty-gate timer it arms IS observable, and drives SOUND_UPDATE's
# actual playback (verified below via the pure CALC_DUTY_GATE_VOLUME).
# 実機フィードバック対応でチャンネルAへ統合済み(旧SND_C_DUTY_TIMER→
# SND_BARRIER_DUTY_TIMER、旧SOUND_UPDATE_C→SOUND_UPDATEへ統合)。
check("...armed the duty-gate timer to 8 (2 on-pulses over 8 frames = 25% duty)",
      z.rd(SND_BARRIER_DUTY_TIMER) == 8)


# ---------- (9) CALC_DUTY_GATE_VOLUME: exactly 2 full-volume(15) frames out of 8 ----------
# Pure function (no PSG side effects, same "directly testable without
# observing an actual PSG write" reasoning as CALC_NOISE_GATE_VOLUME).
def duty_vol(z, timer_val):
    z.wr(SND_BARRIER_DUTY_TIMER, timer_val)
    call_routine(z, sym["CALC_DUTY_GATE_VOLUME"])
    return z.a

z = fresh()
volumes = [duty_vol(z, t) for t in range(8, 0, -1)]   # counter 8,7,6,...,1 (one 8-frame window)
check("CALC_DUTY_GATE_VOLUME: exactly 2 full-volume(15) frames out of the 8-frame window",
      volumes.count(15) == 2 and volumes.count(0) == 6)
check("...the 2 on-frames are at counter values 8 and 4 (evenly spread = a clean 25% duty, "
      "not clustered)", volumes[0] == 15 and volumes[4] == 15)

# SOUND_UPDATE actually decrements SND_BARRIER_DUTY_TIMER 8->0 over 8 calls, then falls back to normal
z = fresh(); boot(z)
z.wr(SND_BARRIER_DUTY_TIMER, 8)
for _ in range(8):
    call_routine(z, sym["SOUND_UPDATE"])
check("SOUND_UPDATE: SND_BARRIER_DUTY_TIMER counts down to 0 and the gate turns itself off after 8 calls",
      z.rd(SND_BARRIER_DUTY_TIMER) == 0)

# once SND_BARRIER_DUTY_TIMER is 0, SOUND_UPDATE falls back to plain SND_TONE_TIMER playback unaffected
z = fresh(); boot(z)
z.wr(SND_BARRIER_DUTY_TIMER, 0)
z.wr(sym["SND_TONE_TIMER"], 12)
call_routine(z, sym["SOUND_UPDATE"])
check("SOUND_UPDATE: with the duty gate inactive, SOUND_SHOT/SOUND_POD_HIT/SOUND_POD_FIRE's own "
      "SND_TONE_TIMER playback is completely unaffected", z.rd(sym["SND_TONE_TIMER"]) == 11)


# ---------- (10) accent color: white normally, purple while BARRIER_IFRAMES>0 ----------
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BARRIER_IFRAMES, 0)
step_frame(z)
check("accent color: white while not in the post-hit invulnerability window",
      z.rd(PLAYER_ACCENT_COLOR) == SPR_WHITE)

z.wr(BARRIER_IFRAMES, BARRIER_IFRAMES_INIT)
step_frame(z)
check("accent color: purple during BARRIER_IFRAMES (\"被弾時はバリア色のホワイトをパープルに\")",
      z.rd(PLAYER_ACCENT_COLOR) == SPR_PURPLE)


# ---------- (11) PLAYER_DAMAGE_CHECK - post-barrier hit (sprite-explosion burst, no freeze) ----------
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BARRIER_HP, 0)
z.wr(BARRIER_IFRAMES, 0)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX, PY, top=1, bot=0)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: a hit at 0 barrier HP sets GAME_OVER", z.rd(GAME_OVER) == 1)
check("...kicks off the ~2s sprite-explosion burst sequence (PLAYER_EXPL_TOTAL_TIMER armed)",
      z.rd(PLAYER_EXPL_TOTAL_TIMER) == PLAYER_EXPL_TOTAL_LEN)
check("...does NOT touch the old BG-based explosion system (ANIM_BASE untouched, per "
      "\"爆発ではなく\")", z.rd(sym["ANIM_BASE"] + 0) == 0)

# once GAME_OVER is set, further PLAYER_DAMAGE_CHECK calls are a no-op (no crash, no re-trigger)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: once GAME_OVER=1, further calls do nothing (still 0 HP, no underflow)",
      z.rd(BARRIER_HP) == 0)

# PLAYER_FLYAWAY gates collision off entirely (leaving the screen after a boss kill)
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(PLAYER_FLYAWAY, 2)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX, PY, top=1, bot=0)
before_hp = z.rd(BARRIER_HP)
call_routine(z, sym["PLAYER_DAMAGE_CHECK"])
check("PLAYER_DAMAGE_CHECK: no damage while PLAYER_FLYAWAY!=0, even overlapping an enemy",
      z.rd(BARRIER_HP) == before_hp and z.rd(GAME_OVER) == 0)


# ---------- (12) PLAYER_EXPL_UPDATE_ALL: spawns, animates, expires - and the game keeps running ----------
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
call_routine(z, sym["PLAYER_EXPL_TRIGGER"])
check("PLAYER_EXPL_TRIGGER arms the total timer to PLAYER_EXPL_TOTAL_LEN",
      z.rd(PLAYER_EXPL_TOTAL_TIMER) == PLAYER_EXPL_TOTAL_LEN)

call_routine(z, sym["PLAYER_EXPL_UPDATE_ALL"])
slot0_active = z.rd(PLAYER_EXPL_POOL + 0)
check("PLAYER_EXPL_UPDATE_ALL: the first call spawns a burst instance immediately (spawn timer starts at 0)",
      slot0_active == 1)
sprnum = z.rd(PLAYER_EXPL_POOL + 4)
check("...allocated a real hw sprite number (>=2)", sprnum >= 2)
check("...drawn with the dedicated always-loaded pattern code",
      z.vram[ATTR + sprnum * 4 + 2] == PAT_PLAYER_EXPLOSION)
px_written = z.vram[ATTR + sprnum * 4 + 1]
py_written = z.vram[ATTR + sprnum * 4]
check("...spawned near the player's own position (within the +-8px jitter window)",
      abs(px_written - PX) <= 8 and abs(py_written - (PY - 8)) <= 8)

# run the instance out to its own life and confirm it expires/frees.
# The spawn call itself already ticks the freshly-spawned instance once
# (spawn and instance-processing happen in the same PLAYER_EXPL_UPDATE_
# ALL call), so TIMER is already PLAYER_EXPL_LIFE-1 after the very first
# call above - PLAYER_EXPL_LIFE-2 more calls brings it to 1 (still
# alive), and exactly 1 further call expires it.
for _ in range(PLAYER_EXPL_LIFE - 2):
    call_routine(z, sym["PLAYER_EXPL_UPDATE_ALL"])
check("...instance still alive just before its own PLAYER_EXPL_LIFE'th tick", z.rd(PLAYER_EXPL_POOL + 0) == 1)
call_routine(z, sym["PLAYER_EXPL_UPDATE_ALL"])
check("...expires exactly at PLAYER_EXPL_LIFE and frees its hw sprite",
      z.rd(PLAYER_EXPL_POOL + 0) == 0 and z.rd(SPRITE_USED + sprnum) == 0)
check("...hidden off-screen at the attribute table on expiry",
      z.vram[ATTR + sprnum * 4] == sym["ENEMY_HIDE_Y"] and z.vram[ATTR + sprnum * 4 + 1] == 255)

# a real MAINLOOP run: game keeps playing after death (no freeze), and the
# burst sequence actually runs to completion inside real gameplay frames
z = fresh(); boot(z)
z.wr(PLAYERX, PX); z.wr(PLAYERY, PY)
z.wr(BARRIER_HP, 0)
setup_enemy(z, TYPE_ENEMY1_LOOK, PX, PY, top=1, bot=0)
hit_this_frame = False
for _ in range(3):
    step_frame(z)
    if z.rd(GAME_OVER) == 1:
        hit_this_frame = True
        break
check("real MAINLOOP: a real frame loop reaches GAME_OVER=1 via PLAYER_DAMAGE_CHECK "
      "(wired into MAINLOOP's own tail)", hit_this_frame)

pxg8_before = z.rd(sym["PXCHAR_G8"])
for _ in range(400):
    step_frame(z)
check("...\"ゲームは止めないでくれ\" - MAINLOOP does NOT freeze after GAME_OVER: the terrain "
      "scroll counter keeps advancing across many more frames",
      z.rd(sym["PXCHAR_G8"]) != pxg8_before)
check("...the burst sequence itself finishes naturally within that same span "
      "(PLAYER_EXPL_TOTAL_TIMER back to 0)", z.rd(PLAYER_EXPL_TOTAL_TIMER) == 0)
check("...BARRIER_HP stays exactly 0 throughout (no underflow)", z.rd(BARRIER_HP) == 0)


# ---------- (13) Fighter's 2nd pose data (E42_16x16.json) is actually loaded ----------
z = fresh(); boot(z)
expected = [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,   # top-left
            0x00, 0x7C, 0xFF, 0x07, 0x00, 0x2A, 0x00, 0x00,   # bottom-left
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,   # top-right
            0x01, 0x06, 0x9E, 0xF5, 0xAA, 0x54, 0x0A, 0x01]   # bottom-right
base = SPRPAT + PAT_ENEMY4_2 * 8
got = [z.vram[base + i] for i in range(32)]
check("Fighter's 2nd pose (PAT_ENEMY4_2) VRAM content matches the new E42_16x16.json upload exactly",
      got == expected)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
