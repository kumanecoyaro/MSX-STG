"""Stage1: エネミー6(回転グリフ敵)の耐久値制(2026-09-08、"ステージ1の
エネミー6の耐久値4に")の検証。tools/verify_enemy_bullets.py と同じ
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


ENEMY6_POOL = sym["ENEMY6_POOL"]
ENEMY6_STRUCT = sym["ENEMY6_STRUCT"]
ENEMY6_HP = sym["ENEMY6_HP"]
ENEMY6_HP_INIT = sym["ENEMY6_HP_INIT"]
ENEMY6_ROW_TABLE = sym["ENEMY6_ROW_TABLE"]
SPAWN_E6 = sym["SPAWN_E6"]
ENEMY6_HIT_ONE_SLOT = sym["ENEMY6_HIT_ONE_SLOT"]

check("ENEMY6_HP_INIT is 8 (\"エネミー6 耐久値8\")", ENEMY6_HP_INIT == 8)


def spawn_enemy6(z, row_table_index=0, row=10):
    """Spawns via the real SPAWN_E6 entry point (HL=schedule index on
    entry - 2026-09-12: widened from A to HL so index>=256 works, see
    SPAWN_SCHEDULE_CHECK's own comment), matching SSC_FIRE's own
    calling convention."""
    z.wr(ENEMY6_ROW_TABLE + row_table_index, row)
    z.h = (row_table_index >> 8) & 0xFF
    z.l = row_table_index & 0xFF
    call_routine(z, SPAWN_E6)


def slot0():
    return ENEMY6_POOL


z = fresh()
spawn_enemy6(z)
hp0 = z.rd(ENEMY6_HP)
check(f"SPAWN_E6 initializes the new slot's HP to ENEMY6_HP_INIT ({ENEMY6_HP_INIT})",
      hp0 == ENEMY6_HP_INIT)
check("SPAWN_E6 marks the slot active (ACTIVE=1)", z.rd(slot0()) == 1)

# ---- a bullet hit 3 times (HP 4->1) must NOT destroy it - the enemy ----
# ---- stays active, but the bullet is still consumed each time (A=1). ----
IX = slot0()
row = z.rd(IX + 1)
col = z.rd(IX + 2)
bullet_col = col
bullet_row = row


def hit_test_call(z):
    """Calls ENEMY6_HIT_ONE_SLOT directly with IX=slot0, B/C=bullet col/row
    (matches the (IX,B,C) input contract documented at ENEMY6_HIT_ONE_SLOT's
    own comment) and returns A (1=hit registered)."""
    z.ix = IX
    z.b = bullet_col
    z.c = bullet_row
    call_routine(z, ENEMY6_HIT_ONE_SLOT)
    return z.a


for i in range(1, ENEMY6_HP_INIT):
    result = hit_test_call(z)
    hp = z.rd(ENEMY6_HP)
    check(f"hit #{i}: bullet is consumed (A=1) but the enemy survives "
          f"(ACTIVE stays 1, HP={ENEMY6_HP_INIT - i})",
          result == 1 and z.rd(IX) == 1 and hp == ENEMY6_HP_INIT - i)

# final hit: HP reaches 0 - now it actually dies (ACTIVE=0).
result_final = hit_test_call(z)
check(f"hit #{ENEMY6_HP_INIT} (HP reaches 0): bullet is consumed AND the enemy is "
      "finally destroyed (ACTIVE=0)",
      result_final == 1 and z.rd(IX) == 0)
check("on the killing hit, HP itself lands exactly at 0 (not wrapped/negative)",
      z.rd(ENEMY6_HP) == 0)

# ---- a hit on an already-inactive slot must be a clean no-op (A=0), ----
# ---- not decrement HP further or crash. ----
result5 = hit_test_call(z)
check("hitting an already-destroyed slot again returns A=0 (no-op, no crash)",
      result5 == 0)
check("...and does not further decrement HP below 0", z.rd(ENEMY6_HP) == 0)

# ---- a miss (bullet not overlapping) must not touch HP at all. ----
z2 = fresh()
spawn_enemy6(z2)
z2.ix = slot0()
z2.b = 0   # far away column - definitely not overlapping
z2.c = 0
call_routine(z2, ENEMY6_HIT_ONE_SLOT)
check("a clean miss leaves HP completely untouched (still ENEMY6_HP_INIT)",
      z2.rd(ENEMY6_HP) == ENEMY6_HP_INIT and z2.a == 0)

# ---- ENEMY6_HP_ADDR indexing must be correct for a non-zero slot too - ----
# ---- not just slot0 (guards against an off-by-N in the pointer math). ----
z3 = fresh()
# occupy slot0 first so the 2nd spawn lands in slot1
spawn_enemy6(z3, row_table_index=0, row=5)
spawn_enemy6(z3, row_table_index=1, row=8)
slot1 = ENEMY6_POOL + ENEMY6_STRUCT
check("2nd SPAWN_E6 call lands in slot1 (slot0 was already occupied)",
      z3.rd(slot1) == 1 and z3.rd(slot1 + 1) == 8)
check("slot1's own HP (ENEMY6_HP+1) was initialized independently of slot0's",
      z3.rd(ENEMY6_HP) == ENEMY6_HP_INIT and z3.rd(ENEMY6_HP + 1) == ENEMY6_HP_INIT)

z3.ix = slot1
z3.b = z3.rd(slot1 + 2)
z3.c = z3.rd(slot1 + 1)
call_routine(z3, ENEMY6_HIT_ONE_SLOT)
check("a hit on slot1 decrements ONLY ENEMY6_HP+1, leaving slot0's own HP "
      "(ENEMY6_HP+0) untouched - confirms ENEMY6_HP_ADDR indexes the right "
      "byte for a non-zero slot, not just slot0",
      z3.rd(ENEMY6_HP + 1) == ENEMY6_HP_INIT - 1 and z3.rd(ENEMY6_HP) == ENEMY6_HP_INIT)

# ---- INIT clears the whole ENEMY6_HP array (poison test) ----
z4 = fresh()
for i in range(32):
    z4.wr(ENEMY6_HP + i, 0xAA)
z4.pc = sym["INIT"]
# MISSION_DELAY_3SEC would blow the instruction budget in a full INIT trace -
# shrink it the same way verify_enemy_bullets.py does.
z4.wr(sym["MISSION_DELAY_3SEC"] + 1, 1)
run_until_pc(z4, sym["MAINLOOP"], max_instr=2_000_000)
check("INIT zero-clears the entire ENEMY6_HP array (all 32 bytes), not just "
      "slot0 - poisoned with 0xAA beforehand to catch a partial/short clear",
      all(z4.rd(ENEMY6_HP + i) == 0 for i in range(32)))

# ============================================================
# round135follow-up15: "打つたびに当たってもないのに敵の処理をしてないか
# 探しながら弾を飛ばすとかな 普通は当たってからその先のルーチンで処理して
# リターンだぞ" - CHECK_BULLET_VS_ENEMY6にENEMY3と同じENEMY6_ACTIVE_COUNT
# 短絡ガードを追加した修正の検証。ENEMY6_ACTIVE_COUNTがSPAWN_E6/撃破/
# 画面外退出の全経路で正しく増減し、0の間はENEMY6_SLOTS(32)スロットの
# スキャン自体を完全にスキップすることを直接計測で確認する。
# ============================================================
ENEMY6_ACTIVE_COUNT = sym["ENEMY6_ACTIVE_COUNT"]
CHECK_BULLET_VS_ENEMY6 = sym["CHECK_BULLET_VS_ENEMY6"]
ENEMY6_STEP_ONE = sym["ENEMY6_STEP_ONE"]


def call_counted(z, entry_addr, max_instr=200000):
    """call_routineと同じだが、実際に何命令実行したかを返す(局所ルーチン
    単体の実行コストを直接計測するため - tools/verify_mainloop_loop_
    bounds.pyのcall_routine_countedと同じ手法)。"""
    z.sp = 0xF000
    z.wr(0xF000, 0x00); z.wr(0xF001, 0x00)
    z.pc = entry_addr
    n = 0
    for _ in range(max_instr):
        if z.pc == 0x0000:
            return n
        z.step()
        n += 1
    raise RuntimeError(f"{entry_addr:04X} did not return within {max_instr} instructions")


z5 = fresh()
z5.wr(ENEMY6_ACTIVE_COUNT, 0xAA)
z5.pc = sym["INIT"]
z5.wr(sym["MISSION_DELAY_3SEC"] + 1, 1)
run_until_pc(z5, sym["MAINLOOP"], max_instr=2_000_000)
check("INIT zero-clears ENEMY6_ACTIVE_COUNT (poisoned 0xAA beforehand)",
      z5.rd(ENEMY6_ACTIVE_COUNT) == 0)

z6 = fresh()
spawn_enemy6(z6)
check("SPAWN_E6 increments ENEMY6_ACTIVE_COUNT (0->1)",
      z6.rd(ENEMY6_ACTIVE_COUNT) == 1)
spawn_enemy6(z6, row_table_index=1, row=11)
check("a second SPAWN_E6 increments it again (1->2)",
      z6.rd(ENEMY6_ACTIVE_COUNT) == 2)

slot0_row = z6.rd(ENEMY6_POOL + 1)
slot0_col = z6.rd(ENEMY6_POOL + 2)
z6.ix = ENEMY6_POOL
z6.b = slot0_col
z6.c = slot0_row
for _ in range(ENEMY6_HP_INIT):
    call_routine(z6, ENEMY6_HIT_ONE_SLOT)
check("killing slot0 (HP reaches 0) decrements ENEMY6_ACTIVE_COUNT (2->1), "
      "slot1 (the 2nd spawn) is untouched", z6.rd(ENEMY6_ACTIVE_COUNT) == 1)

z7 = fresh()
spawn_enemy6(z7)
# 左端(col=0)まで手動で進め、ENEMY6_STEP_ONEが画面外退出で非活性化する
# 経路(E6SO_EXIT)を直接踏む。
z7.wr(ENEMY6_POOL + 2, 0)  # COL=0(次のSTEP_ONEで即E6SO_EXIT分岐)
z7.ix = ENEMY6_POOL
call_routine(z7, ENEMY6_STEP_ONE)
check("reaching the left edge (ENEMY6_STEP_ONE's E6SO_EXIT path) also "
      "decrements ENEMY6_ACTIVE_COUNT (1->0), not just the bullet-kill path",
      z7.rd(ENEMY6_POOL) == 0 and z7.rd(ENEMY6_ACTIVE_COUNT) == 0)

ENEMY6_SLOTS = sym["ENEMY6_SLOTS"]
z8 = fresh()
for i in range(ENEMY6_SLOTS):
    z8.wr(ENEMY6_POOL + i * ENEMY6_STRUCT, 0)
z8.wr(ENEMY6_ACTIVE_COUNT, 0)
z8.b, z8.c = 15, 10
n_empty = call_counted(z8, CHECK_BULLET_VS_ENEMY6)
check(f"real measurement: with ENEMY6_ACTIVE_COUNT=0 (no Enemy6 on screen at "
      f"all - the common case), CHECK_BULLET_VS_ENEMY6 short-circuits to a "
      f"handful of instructions instead of scanning all {ENEMY6_SLOTS} slots "
      f"every single bullet, every single frame (measured: {n_empty} "
      "instructions, must be well under 20)",
      n_empty < 20)

z9 = fresh()
for i in range(ENEMY6_SLOTS):
    z9.wr(ENEMY6_POOL + i * ENEMY6_STRUCT, 1)
z9.wr(ENEMY6_ACTIVE_COUNT, ENEMY6_SLOTS)
z9.b, z9.c = 15, 10
n_full = call_counted(z9, CHECK_BULLET_VS_ENEMY6)
check(f"...but when Enemy6 instances really are on screen (count={ENEMY6_SLOTS}), "
      f"the full scan still runs exactly as before (measured: {n_full} "
      "instructions - this guard must never hide a real hit)",
      n_full > 1500)


def _regress_no_active_count_gate():
    """CHECK_BULLET_VS_ENEMY6冒頭のENEMY6_ACTIVE_COUNTガード(LD A,(...):OR
    A:RET Z)を無効化する自己検証 - 無効化すると、Enemy6が1体も居なくても
    毎回ENEMY6_SLOTS(32)スロットのフルスキャンへ戻ってしまう(=修正前の
    実測202命令/回のムダが再現する)ことを確認する。RET Z(オペコードC8h、
    round135follow-up16でJR Z,CBVE6_NONEから1バイトへ切り詰め済み)自体を
    NOP1個へ置き換え、ガードの判定結果に関わらず常にフルスキャン側へ
    フォールスルーさせる(LD A,(nn)をXOR Aへ書き換える案は、A=0かつZフラグ
    セットのままだと逆に"常に早期RET"を強制してしまい逆方向のバグになると
    判明したため不採用 - 自己検証スクリプト自体のこの誤りも直接デバッグ
    して発見)。"""
    target = sym["CHECK_BULLET_VS_ENEMY6"]
    pat = bytes([0x3A, ENEMY6_ACTIVE_COUNT & 0xFF, (ENEMY6_ACTIVE_COUNT >> 8) & 0xFF,
                 0xB7, 0xC8])
    idx = bytes(mem0).find(pat, target)
    if idx < 0 or idx != target:
        raise RuntimeError("CHECK_BULLET_VS_ENEMY6's active-count gate pattern not found "
                            "at the expected entry point")
    broken_mem = bytearray(mem0)
    broken_mem[idx + 4] = 0x00  # RET Z opcode -> NOP
    zz = Z80(broken_mem)
    for i in range(ENEMY6_SLOTS):
        zz.wr(ENEMY6_POOL + i * ENEMY6_STRUCT, 0)
    zz.wr(ENEMY6_ACTIVE_COUNT, 0)
    zz.b, zz.c = 15, 10
    return call_counted(zz, CHECK_BULLET_VS_ENEMY6)


check("自己検証: CHECK_BULLET_VS_ENEMY6冒頭のENEMY6_ACTIVE_COUNTガードを"
      "無効化すると、プールが空でも修正前と同じ規模(200命令前後)の"
      "フルスキャンへ戻る(=このガードが実際に効いていることの確認)",
      _regress_no_active_count_gate() > 150)

# ---- (2026-09-23、メインループ監査"A"): ENEMY6_UPDATE_ALL/PDC_CHECK_ENEMY6も
# ENEMY6_ACTIVE_COUNT==0なら32スロット走査を省略する ----
def tstates_of(z, entry):
    t0 = z.tstates
    call_routine(z, entry)
    return z.tstates - t0

zg = fresh()
zg.wr(sym["ENEMY6_ACTIVE_COUNT"], 0)
zg.wr(sym["ENEMY6_STEP_TIMER"], 1)          # 今フレームが歩進フレーム
t_upd0 = tstates_of(zg, sym["ENEMY6_UPDATE_ALL"])
check(f"no Enemy6: ENEMY6_UPDATE_ALL skips the 32-slot scan ({t_upd0}T < 200T)", t_upd0 < 200)
check("no Enemy6: step timer still reloads to ENEMY6_STEP_FRAMES (cadence unchanged)",
      zg.rd(sym["ENEMY6_STEP_TIMER"]) == sym["ENEMY6_STEP_FRAMES"])
t_pdc0 = tstates_of(zg, sym["PDC_CHECK_ENEMY6"])
check(f"no Enemy6: PDC_CHECK_ENEMY6 skips the 32-slot scan ({t_pdc0}T < 100T) and returns A=0",
      t_pdc0 < 100 and zg.a == 0)

# 1体居る時は従来通り: 自機と重なれば被弾、更新で動く
zs = fresh()
spawn_enemy6(zs, 0, 10)
check("after SPAWN_E6: ENEMY6_ACTIVE_COUNT=1", zs.rd(sym["ENEMY6_ACTIVE_COUNT"]) == 1)
row = zs.rd(slot0() + 1); col = zs.rd(slot0() + 2)
zs.wr(sym["PLAYERX"], col * 8); zs.wr(sym["PLAYERY"], row * 8)
call_routine(zs, sym["PDC_CHECK_ENEMY6"])
check("one Enemy6 overlapping the player: PDC_CHECK_ENEMY6 still reports a hit", zs.a == 1)
zs.wr(sym["ENEMY6_STEP_TIMER"], 1)
col0 = zs.rd(slot0() + 2)
call_routine(zs, sym["ENEMY6_UPDATE_ALL"])
check("one Enemy6: ENEMY6_UPDATE_ALL still steps it (COL changes)", zs.rd(slot0() + 2) != col0)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
