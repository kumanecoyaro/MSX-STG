"""実機フィードバック対応("ステージ1クリア後にフリーズした")の回帰
ガード。根本原因はINITの「DI: CALL INIT32: EI」ブロックのEIが、INIT
冒頭のDI(自身のコメントが約束する「INIT末尾のCALL INIT_BGM直後まで
割り込み禁止」)を数千命令分も早く破っていたこと - CALL INIT32(BIOS
SCREEN1初期化)は内部でEI+HALTによるvblank待ちを行うため、Stage1から
切り替わった直後の古いH.TIMIフック(window Aの中身は既にStage2の
コードに切り替わっている)がまだ生きたまま割り込みが1回でも発火すると
暴走する。修正はCALL INIT_BGMをINIT冒頭のDIの直後(CALL INIT32より前)
へ移動し、以後EIが一切現れないようにしたこと。

このテストはINITを生トレース(banked_helpersのキャッシュ済みブート
ではなく、毎回実際にSTEPする)し、(1)最初にEIでiff1がTrueになる瞬間には
既にHTIMI_HOOKがこのファイル自身のBGM_TICKを指していること、(2)それ
より前のどの時点でもiff1がTrueにならないこと、の両方を直接検証する。
"""
import copy
import os
import sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))  # tools/stage2_combined
import build_test
from z80emu import Z80

out, sym, text = build_test.assemble()
bank0, bank1 = build_test.build_banks(out)
mem = build_test.BankedMem(bank0, bank1)
cpu = Z80(mem)
cpu.pc = sym["INIT"]
mainloop = sym["MAINLOOP"]
HTIMI_HOOK = sym["HTIMI_HOOK"]
BGM_TICK = sym["BGM_TICK"]

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

first_ei_pc = None
first_ei_hook_target = None
iff1_before_first_ei = []
steps = 0
while cpu.pc != mainloop and steps < 2_000_000:
    if cpu.iff1 and first_ei_pc is None:
        first_ei_pc = cpu.pc
        lo = mem.flat[(HTIMI_HOOK + 1) & 0xFFFF]
        hi = mem.flat[(HTIMI_HOOK + 2) & 0xFFFF]
        first_ei_hook_target = lo | (hi << 8)
    cpu.step()
    steps += 1
assert steps < 2_000_000, "never reached MAINLOOP"

check("INIT actually enables interrupts at least once before MAINLOOP (sanity check - "
      "otherwise this test would trivially pass by never exercising the bug at all)",
      first_ei_pc is not None)
check("the FIRST time interrupts are enabled anywhere in INIT, HTIMI_HOOK already points "
      "to this file's own BGM_TICK (not a stale hook from whichever stage ran before this "
      "one, nor an unset/zero address) - this is exactly the invariant the premature EI "
      "inside 'DI: CALL INIT32: EI' used to violate",
      first_ei_hook_target == BGM_TICK)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
