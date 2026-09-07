"""Stage1: ボス着地(BOSS_STATE 1->2)の瞬間、まだ生存中の偏向弾(DFL0-2)が
残っていると、直後にBOSS_ORBIT_DRAW_ALLが同じハードウェアスプライト
スロット(9-11、DFL_SPR0-2と周回ポッド用スロット6-13が重複)を奪い合って
壊れた見た目のまま残留するバグ(実機フィードバック対応、2026-09-07:
"ステージ1のボスのマテリアライズ中のショットの反射弾が残ってる 前は
そんな事なく消えてた")の回帰テスト。BOSS_UPDATE_BODYの着地遷移で新規に
呼ばれるDFL_FORCE_CLEARが、着地の瞬間にDFL0-2を強制的に非表示化・
非アクティブ化することを検証する。tools/verify_player_damage.py と同じ
「mini_z80asm.Assemblerで直接アセンブル+call_routine/run_until_pcの
一回性検証スクリプト」の作法に倣う。
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


def call_routine(z, entry_addr, max_instr=300000):
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    run_until_pc(z, 0x0000, max_instr)


BOSS_STATE = sym["BOSS_STATE"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_ROW = sym["BOSS_ROW"]
BOSS_COL = sym["BOSS_COL"]
DFL0_ACT = sym["DFL0_ACT"]
DFL1_ACT = sym["DFL1_ACT"]
DFL2_ACT = sym["DFL2_ACT"]
DFL0_X = sym["DFL0_X"]; DFL0_Y = sym["DFL0_Y"]
DFL_SPR0 = sym["DFL_SPR0"]; DFL_SPR1 = sym["DFL_SPR1"]; DFL_SPR2 = sym["DFL_SPR2"]
BOSS_UPDATE_BODY = sym["BOSS_UPDATE_BODY"]
DFL_FORCE_CLEAR = sym["DFL_FORCE_CLEAR"]

SPRATR = 0x1B00


def spr_y(z, slot):
    return z.vram[SPRATR + slot * 4]


def arm_final_tile(z):
    # BOSS_UPDATE_BODYがこの1回の呼び出しでBOSS_STATEを1->2へ進める
    # (最後のタイル: row15->16, col4->5)ようにセットアップ。
    z.wr(BOSS_STATE, 1)
    z.wr(BOSS_PHASE, 0)
    z.wr(BOSS_ROW, 15)
    z.wr(BOSS_COL, 4)


# ---- DFL_FORCE_CLEAR itself: unconditionally hides+deactivates all 3 slots ----
z = fresh()
z.wr(DFL0_ACT, 1); z.wr(DFL1_ACT, 1); z.wr(DFL2_ACT, 1)
z.wr(DFL0_X, 100); z.wr(DFL0_Y, 80)
call_routine(z, DFL_FORCE_CLEAR)
check("DFL_FORCE_CLEAR clears all 3 DFL ACT flags",
      z.rd(DFL0_ACT) == 0 and z.rd(DFL1_ACT) == 0 and z.rd(DFL2_ACT) == 0)
check("DFL_FORCE_CLEAR hides all 3 DFL hardware sprite slots (Y=209 sentinel)",
      spr_y(z, DFL_SPR0) == 209 and spr_y(z, DFL_SPR1) == 209 and spr_y(z, DFL_SPR2) == 209)

# ---- DFL_FORCE_CLEAR is a safe no-op-ish call when nothing was active ----
z = fresh()
call_routine(z, DFL_FORCE_CLEAR)
check("DFL_FORCE_CLEAR is safe to call even when no DFL bullet was active",
      z.rd(DFL0_ACT) == 0 and z.rd(DFL1_ACT) == 0 and z.rd(DFL2_ACT) == 0)

# ---- the actual regression: a DFL bullet still alive exactly at the ----
# ---- BOSS_STATE 1->2 landing transition must be force-cleared, not  ----
# ---- left to straggle and collide with the orbit pods' slots 6-13. ----
z = fresh()
arm_final_tile(z)
z.wr(DFL0_ACT, 1)
z.wr(DFL0_X, 120); z.wr(DFL0_Y, 64)
call_routine(z, BOSS_UPDATE_BODY)
check("landing transition (BOSS_STATE 1->2) actually happened this call",
      z.rd(BOSS_STATE) == 2)
check("a DFL bullet still active exactly at the landing transition gets "
      "deactivated (no longer straggles into the orbit-pod era)",
      z.rd(DFL0_ACT) == 0)
check("...and its hardware sprite slot (shared with the orbit pods, slots "
      "6-13) is explicitly hidden before BOSS_ORBIT_DRAW_ALL can claim it",
      spr_y(z, DFL_SPR0) == 209)

# ---- all 3 slots simultaneously active at the transition ----
z = fresh()
arm_final_tile(z)
z.wr(DFL0_ACT, 1); z.wr(DFL1_ACT, 1); z.wr(DFL2_ACT, 1)
call_routine(z, BOSS_UPDATE_BODY)
check("all 3 DFL slots active at the landing transition are all cleared",
      z.rd(DFL0_ACT) == 0 and z.rd(DFL1_ACT) == 0 and z.rd(DFL2_ACT) == 0)
check("...and all 3 hardware sprite slots are hidden",
      spr_y(z, DFL_SPR0) == 209 and spr_y(z, DFL_SPR1) == 209 and spr_y(z, DFL_SPR2) == 209)

# ---- a non-final tile (mid-materialize) must NOT force-clear DFL bullets ----
# ---- (they're still legitimately allowed to fly during materialize).    ----
z = fresh()
z.wr(BOSS_STATE, 1)
z.wr(BOSS_PHASE, 0)
z.wr(BOSS_ROW, 3)
z.wr(BOSS_COL, 2)   # not the final tile - no landing transition this call
z.wr(DFL0_ACT, 1)
z.wr(DFL0_X, 90); z.wr(DFL0_Y, 50)
call_routine(z, BOSS_UPDATE_BODY)
check("mid-materialize tile reveal does NOT trigger the landing transition",
      z.rd(BOSS_STATE) == 1)
check("...and therefore does NOT force-clear a still-legitimately-flying DFL bullet",
      z.rd(DFL0_ACT) == 1)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
