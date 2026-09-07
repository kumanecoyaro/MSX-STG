"""Stage1: 実機フィードバック対応("スケジュールの問題はどうなった
Tick250あたりからのジグザグが出てない コールドスタートでは問題ないが
ゲームオーバー後の再スタートで不具合")の調査記録。

**当初の仮説(誤りと判明・修正は撤回済み)**: E2A_ACTIVE/E2B_ACTIVE
(Enemy2=Zigzag編隊A/Bの生存フラグ)がINIT時に明示的にゼロクリアされて
いないためSSC_BUSY_E2が永久停止する、という理論を立てて一度は修正を
加えたが、以下2点の検証で誤りと判明し撤回した:
  (1) 実際にはINIT冒頭(0xE600-0xE663・0xE680-0xE6E3の2つの100byte
      LDIR一括ゼロクリアブロック、"enemy formation initial state"の
      すぐ後)が、E2A_ACTIVE(0xE661)・E2B_ACTIVE(0xE6E1)を含む広い
      RAM範囲を無条件にゼロクリアしている(このブロックの存在は当初の
      grepベース監査[個別シンボル名の直接参照のみを探索]では見落として
      いた - LDIRによる範囲コピーは記号名を経由しないため)。
  (2) 実際にTitle->Stage1(1周目)をEnemy2編隊生存中[E2A_ACTIVE=1]の
      瞬間に強制ゲームオーバーさせ、title経由でStage1へ再起動(2周目)
      させてtick260まで進める実プレイシミュレーションでも、1周目・
      2周目で全く同じタイミング・回数でZigzagがスポーンすることを
      確認した(tools/以下に残る一連のprobe_restart_zigzag.py相当の
      調査、詳細はHANDOFF.md参照)。
以上により、この経路自体は真因ではないと結論。**"Tick250あたりから
のジグザグが出てない"の真因は依然未特定のまま**(下記「保留」参照)。

併せて発見したDFL0-2_ACT(ボス偏向弾3スロット)のボススポーン時
初期化漏れ(これは実在するバグ、E2A/E2Bとは無関係)はこのファイルで
引き続き検証する。
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

# 既存のverify_player_damage.py等と同じ理由(MISSION_DELAY_3SECの
# 実機相当ビジーウェイトがテストの命令数上限を超えるため)、テスト
# プロセス内でのみ短縮する。実ROMは無変更。
mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


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


E2A_ACTIVE = sym["E2A_ACTIVE"]
E2B_ACTIVE = sym["E2B_ACTIVE"]
SPAWN_NEXT_INDEX = sym["SPAWN_NEXT_INDEX"]
GAME_TICK = sym["GAME_TICK"]
SPAWN_SCHEDULE_CHECK = sym["SPAWN_SCHEDULE_CHECK"]
DFL0_ACT = sym["DFL0_ACT"]
DFL1_ACT = sym["DFL1_ACT"]
DFL2_ACT = sym["DFL2_ACT"]
BOSS_UPDATE_BODY = sym["BOSS_UPDATE_BODY"]
BOSS_PHASE = sym["BOSS_PHASE"]
BOSS_COL = sym["BOSS_COL"]
BOSS_ROW = sym["BOSS_ROW"]

# ---- regression #1: poisoned-RAM boot - confirms E2A_ACTIVE/E2B_ACTIVE ----
# ---- are genuinely zeroed by INIT (via the pre-existing 0xE600-0xE663/ ----
# ---- 0xE680-0xE6E3 bulk LDIR-clear blocks right after the "enemy       ----
# ---- formation initial state" comment - NOT a new fix, this regression ----
# ---- guard exists to keep it that way; matches this project's own      ----
# ---- established poisoned-RAM testing convention, e.g. tools/          ----
# ---- stage2_combined/tests/init_ram_poison_test.py).                   ----
z = Z80(bytearray([0xFF] * 65536))
for addr, val in out.items():
    z.wr(addr & 0xFFFF, val & 0xFF)
z.pc = sym["INIT"]
run_until_pc(z, sym["MAINLOOP"], max_instr=2_000_000)
check("boot from all-0xFF poisoned RAM: E2A_ACTIVE ends up zeroed (via the "
      "existing 0xE600-0xE663 bulk clear block)",
      z.rd(E2A_ACTIVE) == 0)
check("boot from all-0xFF poisoned RAM: E2B_ACTIVE ends up zeroed (via the "
      "existing 0xE680-0xE6E3 bulk clear block)",
      z.rd(E2B_ACTIVE) == 0)

# ---- regression #2: documents SSC_BUSY_E2's own stall mechanism in    ----
# ---- isolation (this part of the theory was correct - if E2A/E2B were ----
# ---- ever both stuck non-zero, the schedule really would stall here   ----
# ---- forever - it's just that regression #1 above already proves they ----
# ---- never get the chance to, thanks to the pre-existing bulk clear). ----
def fresh_clean():
    z2 = Z80(bytearray(mem0))
    return z2

# SPAWN_THRESHOLDS index17 (type=enemy2, one of SSC_BUSY_E2's own CP list)
# has a real threshold of tick70 (DW 10,12,14,18,20,22,26,28,30,33,35,41,
# 43,45,53,55,57 for indices0-16, then 70 at index17).
E2_INDEX = 17
E2_THRESHOLD = 70

z2 = fresh_clean()
z2.wr(SPAWN_NEXT_INDEX, E2_INDEX)
z2.wr(GAME_TICK, E2_THRESHOLD & 0xFF)
z2.wr(GAME_TICK + 1, (E2_THRESHOLD >> 8) & 0xFF)
z2.wr(E2A_ACTIVE, 1)
z2.wr(E2B_ACTIVE, 1)
call_routine(z2, SPAWN_SCHEDULE_CHECK)
check(f"SPAWN_SCHEDULE_CHECK with E2A_ACTIVE=E2B_ACTIVE=1 (hypothetically stale) "
      f"stalls SPAWN_NEXT_INDEX at index{E2_INDEX} - the mechanism itself is real, "
      "even though regression #1 proves E2A/E2B never actually reach this state",
      z2.rd(SPAWN_NEXT_INDEX) == E2_INDEX)

z2.wr(E2A_ACTIVE, 0)  # one slot frees up (matches SPAWN_E2's own claim-a-free-slot logic)
call_routine(z2, SPAWN_SCHEDULE_CHECK)
check(f"...and advances past index{E2_INDEX} the instant either slot frees up "
      "(confirms the stall is purely a function of E2A_ACTIVE/E2B_ACTIVE staying "
      "stale, not a deeper bug in the dispatch logic itself)",
      z2.rd(SPAWN_NEXT_INDEX) == E2_INDEX + 1)

# ---- regression #3: end-to-end - a full INIT boot from RAM poisoned to ----
# ---- simulate "restart after a previous playthrough left E2 formations ----
# ---- alive" must NOT leave the schedule stuck at E2_INDEX.             ----
z3 = Z80(bytearray([0xFF] * 65536))
for addr, val in out.items():
    z3.wr(addr & 0xFFFF, val & 0xFF)
z3.pc = sym["INIT"]
run_until_pc(z3, sym["MAINLOOP"], max_instr=2_000_000)
z3.wr(SPAWN_NEXT_INDEX, E2_INDEX)
z3.wr(GAME_TICK, E2_THRESHOLD & 0xFF)
z3.wr(GAME_TICK + 1, (E2_THRESHOLD >> 8) & 0xFF)
call_routine(z3, SPAWN_SCHEDULE_CHECK)
check("end-to-end: after a real INIT boot from poisoned RAM (simulating a restart "
      "right after a previous game-over), the schedule correctly advances past an "
      "Enemy2 index instead of staying stuck forever",
      z3.rd(SPAWN_NEXT_INDEX) == E2_INDEX + 1)

# ---- regression #4: DFL0-2_ACT (boss deflector bullets) - found during ----
# ---- the same audit, fixed at the materialize-complete init block      ----
# ---- inside BOSS_UPDATE_BODY (matching the existing POD_*/EXPLOSION_   ----
# ---- ACT convention there, which fires exactly once per boss fight, at ----
# ---- the moment BOSS_STATE 1->2 / the boss finishes materializing).    ----
# ---- Boot normally first (so BOSS_DRAW_CUR_TILE etc. have valid ROM/   ----
# ---- RAM state to work with), THEN poison just DFL0-2_ACT to simulate  ----
# ---- stale leftovers, and set up the exact BOSS_PHASE/COL/ROW that     ----
# ---- makes this one call to BOSS_UPDATE_BODY take the "materialize     ----
# ---- just completed" branch.                                           ----
z4 = Z80(bytearray(mem0))
z4.pc = sym["INIT"]
run_until_pc(z4, sym["MAINLOOP"], max_instr=2_000_000)
z4.wr(DFL0_ACT, 1)
z4.wr(DFL1_ACT, 1)
z4.wr(DFL2_ACT, 1)
z4.wr(BOSS_PHASE, 0)
z4.wr(BOSS_COL, 4)
z4.wr(BOSS_ROW, 15)
call_routine(z4, BOSS_UPDATE_BODY)
check("BOSS_UPDATE_BODY's materialize-complete init block explicitly zeroes DFL0_ACT "
      "(boss deflector bullet slot 0) - previously never cleared anywhere, risking a "
      "stale deflector bullet reappearing if the previous playthrough's game-over "
      "interrupted a boss fight",
      z4.rd(DFL0_ACT) == 0)
check("...and DFL1_ACT", z4.rd(DFL1_ACT) == 0)
check("...and DFL2_ACT", z4.rd(DFL2_ACT) == 0)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
    sys.exit(1)
