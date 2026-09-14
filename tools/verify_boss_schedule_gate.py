"""Stage1: 実機フィードバック("スクショ送るが ボスでは居ないはずの
Ebuzが出てる スポーン条件をすり抜けてるな")への対応(round135follow-up16)。

根本原因: CHECK_BOSS_TRIGGER(round135follow-up13)はGAME_TICK>=1024+
全プール瞬間空という条件だけでBOSS_SPAWNを発火し、SPAWN_NEXT_INDEXが
スケジュール(SPAWN_THRESHOLDS、479件)の末尾に達しているかは一切見ない。
そのため未消化のエントリ(Ebuzを含む)を残したままボスが出現しうる。
MAINLOOP側のスケジュール駆動ブロック(GAME_TICKインクリメント+
SPAWN_SCHEDULE_CHECK呼び出し)はBOSS_STATEを一切見ておらず、ボス出現後も
GAME_TICKが進み続ける限り(EBUZ_ANY_ACTIVEだけが唯一のゲート)毎フレーム
SPAWN_SCHEDULE_CHECKが呼ばれ続けていたため、ボス戦中に残りのスケジュール
エントリがすり抜けて発火していた。

修正: SPAWN_SCHEDULE_CHECKの呼び出しだけをBOSS_STATE==0の間に限定。
GAME_TICK自体は凍結しない - POD_FIRE_START(BOSS_SPAWN時点のGAME_TICKから
の相対ターゲット、POD_FIRE_UPDATEがGAME_TICKと直接比較する)がボス戦中も
進み続けるGAME_TICKに依存しているため、GAME_TICKまで止めるとボスのポッド
発射が永久に起動しなくなる別の重大バグになる。

本ファイルはこの1点(「ボス出現後はSPAWN_SCHEDULE_CHECKが呼ばれない」)を
GAME_TICK/SPAWN_NEXT_INDEXを直接pokeした上でMAINLOOPを実際に複数フレーム
回して検証する。あわせて「BOSS_STATE==0の間は従来通りディスパッチされる」
(ゲートが効きすぎていないこと)も確認する。
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
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def fresh(mem=None):
    return Z80(bytearray(mem if mem is not None else mem0))


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def boot(z):
    z.pc = sym["INIT"]
    run_until_pc(z, sym["MAINLOOP"])


def step_frames(z, n, max_instr=2_000_000):
    for _ in range(n):
        z.pc = sym["MAINLOOP"]
        z.step()
        run_until_pc(z, sym["MAINLOOP"], max_instr=max_instr)


def wr16(z, addr, val):
    z.wr(addr, val & 0xFF)
    z.wr(addr + 1, (val >> 8) & 0xFF)


def rd16(z, addr):
    return z.rd(addr) | (z.rd(addr + 1) << 8)


BOSS_STATE = sym["BOSS_STATE"]
GAME_TICK = sym["GAME_TICK"]
SPAWN_NEXT_INDEX = sym["SPAWN_NEXT_INDEX"]
TICK = sym["TICK"]
ENEMY_POOL = sym["ENEMY_POOL"]
ENEMY_SLOT_COUNT = sym["ENEMY_SLOT_COUNT"]
ENEMY_SLOT_SIZE = sym["ENEMY_SLOT_SIZE"]
ENEMY6_POOL = sym["ENEMY6_POOL"]
ENEMY6_SLOTS = sym["ENEMY6_SLOTS"]
ENEMY6_ACTIVE_COUNT = sym["ENEMY6_ACTIVE_COUNT"]
ENEMY3_WAVE_POOL = sym["ENEMY3_WAVE_POOL"]
ENEMY3_WAVE_SLOTS = sym["ENEMY3_WAVE_SLOTS"]
E2A_ACTIVE = sym["E2A_ACTIVE"]
E2B_ACTIVE = sym["E2B_ACTIVE"]
EBUZ_SLOT0 = sym["EBUZ_SLOT0"]
EBUZ_SLOT1 = sym["EBUZ_SLOT1"]
EBUZ_OFS_ACT = sym["EBUZ_OFS_ACT"]
EBUZ_EXPL_QUEUE_COUNT = sym["EBUZ_EXPL_QUEUE_COUNT"]


def clear_zako_pools(z):
    """CHECK_BOSS_TRIGGER/EBUZ_ANY_ACTIVEが「敵なし」と見なす全プールを
    空にする(SPAWN_SCHEDULE_CHECK自体の動作確認にはボス以外の全ての
    ザコ敵が空であることが前提のため - EBUZ_ANY_ACTIVEが非ゼロだと
    GAME_TICK自体が凍結してしまいテストにならない)。"""
    for i in range(ENEMY_SLOT_COUNT):
        z.wr(ENEMY_POOL + i * ENEMY_SLOT_SIZE, 0)
    for i in range(ENEMY6_SLOTS):
        z.wr(ENEMY6_POOL + i * 4, 0)
    z.wr(ENEMY6_ACTIVE_COUNT, 0)
    for i in range(ENEMY3_WAVE_SLOTS):
        z.wr(ENEMY3_WAVE_POOL + i * 4, 0)
    z.wr(E2A_ACTIVE, 0)
    z.wr(E2B_ACTIVE, 0)
    z.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, 0)
    z.wr(EBUZ_SLOT1 + EBUZ_OFS_ACT, 0)
    z.wr(EBUZ_EXPL_QUEUE_COUNT, 0)


def arm_pending_entry(z, index=0):
    """SPAWN_NEXT_INDEXをindexへ、GAME_TICKをその閾値ちょうどへセットし、
    「このフレームで即ディスパッチされるべきエントリが1件、今まさに
    到達している」状態を作る。"""
    thresholds = sym["SPAWN_THRESHOLDS"]
    threshold = z.rd(thresholds + index * 2) | (z.rd(thresholds + index * 2 + 1) << 8)
    wr16(z, SPAWN_NEXT_INDEX, index)
    wr16(z, GAME_TICK, threshold)
    clear_zako_pools(z)
    z.wr(TICK, 0)  # TICK AND 07h==0 must hold right away so the very next frame fires the gate


# ---- regression: while BOSS_STATE!=0, the pending schedule entry must ----
# ---- NOT be dispatched (SPAWN_NEXT_INDEX stays put) even though it's  ----
# ---- fully due (GAME_TICK already at/over its threshold) and would    ----
# ---- fire immediately under normal (no-boss) play.                    ----
z1 = fresh(); boot(z1)
arm_pending_entry(z1, index=0)
z1.wr(BOSS_STATE, 2)  # boss fight in progress (orbit phase)
tick_before = rd16(z1, GAME_TICK)
index_before = rd16(z1, SPAWN_NEXT_INDEX)
step_frames(z1, 8)  # >=8 real frames guarantees at least one TICK AND 07h==0 hit
check("while BOSS_STATE!=0 (boss fight in progress), a schedule entry that "
      "is fully due does NOT get dispatched (SPAWN_NEXT_INDEX unchanged) - "
      "this is the fix for \"ボスでは居ないはずのEbuzが出てる\"",
      rd16(z1, SPAWN_NEXT_INDEX) == index_before)
check("...but GAME_TICK itself keeps advancing during the boss fight (it "
      "must - POD_FIRE_START is a GAME_TICK-relative target computed at "
      "BOSS_SPAWN time, and POD_FIRE_UPDATE compares against live GAME_TICK "
      "every frame; freezing it would silently break the boss's own pod "
      "fire timing)",
      rd16(z1, GAME_TICK) > tick_before)

# ---- positive control: the exact same setup with BOSS_STATE==0 (no    ----
# ---- boss) DOES dispatch as usual - proves the new gate isn't blocking ----
# ---- schedule dispatch unconditionally, only during an actual boss    ----
# ---- fight.                                                            ----
z2 = fresh(); boot(z2)
arm_pending_entry(z2, index=0)
z2.wr(BOSS_STATE, 0)
index_before2 = rd16(z2, SPAWN_NEXT_INDEX)
step_frames(z2, 8)
check("with BOSS_STATE==0 (no boss active), the same due schedule entry "
      "dispatches normally (SPAWN_NEXT_INDEX advances) - the new gate only "
      "suppresses dispatch during an actual boss fight, not always",
      rd16(z2, SPAWN_NEXT_INDEX) > index_before2)

# ---- self-verification: defeat the fix (CALL Z,SPAWN_SCHEDULE_CHECK -> ----
# ---- unconditional CALL, by flipping just the CALL-Z opcode 0xCC to    ----
# ---- CALL's 0xCD) and confirm the regression above is then real -      ----
# ---- i.e. this test actually catches the "Ebuz slips through the boss  ----
# ---- fight" bug, it doesn't just happen to pass.                       ----
SPAWN_SCHEDULE_CHECK = sym["SPAWN_SCHEDULE_CHECK"]
pat = bytes([0x3A, BOSS_STATE & 0xFF, (BOSS_STATE >> 8) & 0xFF,
             0xB7, 0xCC, SPAWN_SCHEDULE_CHECK & 0xFF, (SPAWN_SCHEDULE_CHECK >> 8) & 0xFF])
idx = bytes(mem0).find(pat)
if idx < 0:
    raise RuntimeError("LD A,(BOSS_STATE):OR A:CALL Z,SPAWN_SCHEDULE_CHECK "
                        "gate pattern not found - has the fix been refactored?")
broken_mem = bytearray(mem0)
broken_mem[idx + 4] = 0xCD  # CALL Z,nn -> CALL nn (unconditional, defeats the gate)
z3 = Z80(broken_mem)
boot(z3)
arm_pending_entry(z3, index=0)
z3.wr(BOSS_STATE, 2)
index_before3 = rd16(z3, SPAWN_NEXT_INDEX)
step_frames(z3, 8)
check("自己検証: BOSS_STATEガードを無効化(CALL Z->無条件CALLへ1byteパッチ)"
      "すると、実際にボス戦中でも due なエントリがディスパッチされてしまう"
      "(=このテストが今回の実バグを本当に検出できることの確認)",
      rd16(z3, SPAWN_NEXT_INDEX) > index_before3)


# ============================================================
# round137follow-up2: "まだEbuzが敵やボス居るのにでる 出ない場合もある
# てことは多分また初期化してねえだろ 何回やるんだよお前は 多分記憶じゃ
# これで7回目"。
#
# 根本原因: 上のround135follow-up16はSPAWN_SCHEDULE_CHECK自体の新規
# ディスパッチだけをBOSS_STATE==0の間に限定したが、EBUZ_CHECK_CHAIN_
# TRIGGERS(MAINLOOP、EBUZ_UPDATE_ALLの直後で毎フレーム無条件に呼ばれる)
# は全く別の独立したチェーン進行ロジック - EBUZ_SPAWN_STAGEが1/2の間、
# 現在のインスタンスのACTが0(消滅済み)になった瞬間に次のインスタンスを
# 自動スポーンする、SPAWN_SCHEDULE_CHECKの管理下に無いコード経路 - で、
# 同じガードを経由していなかった。
#
# CHECK_BOSS_TRIGGERはEBUZ_ANY_ACTIVE(SLOT0/1のACT・EXPL_QUEUE_COUNTが
# 全て0)を含む「全プール空」を要求するため、ボスが実際にスポーンできる
# 瞬間は必ずEbuz本体のACTが0になった直後 - つまりEBUZ_SPAWN_STAGEは
# まだ1か2のまま(次インスタンスの発火待ち状態)で残っていることが
# 普通にある。同一フレーム内でCHECK_BOSS_TRIGGER(この関数より先に実行
# 済み)がボスを出現させた直後に、EBUZ_CHECK_CHAIN_TRIGGERSが無条件に
# 2体目/3体目を新規スポーンしてしまっていた。
#
# 修正: EBUZ_CHECK_CHAIN_TRIGGERSの呼び出しにもSPAWN_SCHEDULE_CHECKと
# 同じBOSS_STATE==0ガードを追加。
# ============================================================
EBUZ_SPAWN_STAGE = sym["EBUZ_SPAWN_STAGE"]
EBUZ_CHAIN_TIMER = sym["EBUZ_CHAIN_TIMER"]
EBUZ_INST3_DELAY_FRAMES = sym["EBUZ_INST3_DELAY_FRAMES"]
EBUZ_CHECK_CHAIN_TRIGGERS = sym["EBUZ_CHECK_CHAIN_TRIGGERS"]


def arm_ebuz_stage1_waiting(z):
    """EBUZ_SPAWN_STAGE=1(1体目消化待ち)かつSLOT0のACTが既に0(1体目が
    消滅済み)という、次のフレームでEBUZ_CHECK_CHAIN_TRIGGERSが2体目を
    即座にスポーンする一歩手前の状態を作る。同時にCHECK_BOSS_TRIGGER
    自身が要求する「全プール空」も満たしておく(実際にボスが出現できる
    瞬間そのものを再現するため)。"""
    clear_zako_pools(z)
    z.wr(EBUZ_SPAWN_STAGE, 1)
    z.wr(EBUZ_SLOT0 + EBUZ_OFS_ACT, 0)


# ---- regression: while BOSS_STATE!=0 (the exact situation right after ----
# ---- the boss has spawned - CHECK_BOSS_TRIGGER's own EBUZ_ANY_ACTIVE  ----
# ---- gate guarantees Ebuz's instance1 had just died), a pending Ebuz  ----
# ---- chain must NOT auto-spawn instance2 (EBUZ_SPAWN_STAGE/SLOT0 ACT  ----
# ---- stay put) even though it's fully due.                            ----
z4 = fresh(); boot(z4)
arm_ebuz_stage1_waiting(z4)
z4.wr(BOSS_STATE, 2)
stage_before4 = z4.rd(EBUZ_SPAWN_STAGE)
act_before4 = z4.rd(EBUZ_SLOT0 + EBUZ_OFS_ACT)
step_frames(z4, 4)
check("while BOSS_STATE!=0, a due Ebuz chain does NOT auto-spawn instance2 "
      "(EBUZ_SPAWN_STAGE/EBUZ_SLOT0's ACT stay unchanged) - this is the fix "
      "for \"まだEbuzが敵やボス居るのにでる\" (round137follow-up2)",
      z4.rd(EBUZ_SPAWN_STAGE) == stage_before4 and
      z4.rd(EBUZ_SLOT0 + EBUZ_OFS_ACT) == act_before4)

# ---- positive control: same setup with BOSS_STATE==0 DOES advance the ----
# ---- chain as usual - proves the new gate isn't blocking Ebuz chain    ----
# ---- progression unconditionally, only during an actual boss fight.   ----
z5 = fresh(); boot(z5)
arm_ebuz_stage1_waiting(z5)
z5.wr(BOSS_STATE, 0)
step_frames(z5, 4)
check("with BOSS_STATE==0 (no boss active), the same due Ebuz chain "
      "advances normally (EBUZ_SPAWN_STAGE becomes 2, instance2 spawns "
      "into EBUZ_SLOT0)",
      z5.rd(EBUZ_SPAWN_STAGE) == 2 and z5.rd(EBUZ_SLOT0 + EBUZ_OFS_ACT) != 0)

# ---- same regression, but for the STAGE==2 (waiting on instance3's own ----
# ---- 5-second real-time delay) branch - a separate code path inside   ----
# ---- EBUZ_CHECK_CHAIN_TRIGGERS from the STAGE==1 branch above.        ----
z6 = fresh(); boot(z6)
clear_zako_pools(z6)
z6.wr(EBUZ_SPAWN_STAGE, 2)
wr16(z6, EBUZ_CHAIN_TIMER, EBUZ_INST3_DELAY_FRAMES)  # timer already at/over the threshold
z6.wr(BOSS_STATE, 2)
stage_before6 = z6.rd(EBUZ_SPAWN_STAGE)
act_before6 = z6.rd(EBUZ_SLOT1 + EBUZ_OFS_ACT)
step_frames(z6, 4)
check("while BOSS_STATE!=0, a due Ebuz instance3 (STAGE==2 branch) does "
      "NOT auto-spawn either (EBUZ_SPAWN_STAGE/EBUZ_SLOT1's ACT stay "
      "unchanged)",
      z6.rd(EBUZ_SPAWN_STAGE) == stage_before6 and
      z6.rd(EBUZ_SLOT1 + EBUZ_OFS_ACT) == act_before6)

# ---- self-verification: defeat the new fix (CALL Z,EBUZ_CHECK_CHAIN_  ----
# ---- TRIGGERS -> unconditional CALL, same 0xCC->0xCD 1-byte patch as  ----
# ---- the self-verification above) and confirm the STAGE==1 regression ----
# ---- test really is real - i.e. this test actually catches the "Ebuz  ----
# ---- chain slips through the boss fight" bug, it doesn't just happen  ----
# ---- to pass.                                                         ----
pat2 = bytes([0x3A, BOSS_STATE & 0xFF, (BOSS_STATE >> 8) & 0xFF,
              0xB7, 0xCC, EBUZ_CHECK_CHAIN_TRIGGERS & 0xFF, (EBUZ_CHECK_CHAIN_TRIGGERS >> 8) & 0xFF])
idx2 = bytes(mem0).find(pat2)
if idx2 < 0:
    raise RuntimeError("LD A,(BOSS_STATE):OR A:CALL Z,EBUZ_CHECK_CHAIN_TRIGGERS "
                        "gate pattern not found - has the fix been refactored?")
broken_mem2 = bytearray(mem0)
broken_mem2[idx2 + 4] = 0xCD  # CALL Z,nn -> CALL nn (unconditional, defeats the gate)
z7 = Z80(broken_mem2)
boot(z7)
arm_ebuz_stage1_waiting(z7)
z7.wr(BOSS_STATE, 2)
stage_before7 = z7.rd(EBUZ_SPAWN_STAGE)
step_frames(z7, 4)
check("自己検証: EBUZ_CHECK_CHAIN_TRIGGERSのBOSS_STATEガードを無効化"
      "(CALL Z->無条件CALLへ1byteパッチ)すると、実際にボス戦中でも"
      "due なEbuzチェーンがスポーンしてしまう(=このテストが今回の実"
      "バグを本当に検出できることの確認)",
      z7.rd(EBUZ_SPAWN_STAGE) != stage_before7)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
