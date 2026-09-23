import copy
import os
import sys
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # tools/stage2_combined
sys.path.insert(0, HERE)
import build_test
from z80emu import Z80

_OUT_CACHE = None
_BOOT_SNAPSHOT = None  # a real post-boot Z80/BankedMem, cloned (not re-booted) per fresh_cpu() call
_BOOT_SNAPSHOT_READY = None  # same, but stepped past the stage2-start "falling in" intro too (see fresh_cpu's own skip_intro)


def get_out():
    global _OUT_CACHE
    if _OUT_CACHE is None:
        _OUT_CACHE = build_test.assemble()
    return _OUT_CACHE


def fresh_cpu(assert_bank_switch=True, skip_intro=True):
    """Real cold-boot simulation: bankB starts at 0 (matching real
    ASCII16 power-on default), steps through INIT's own trampoline
    code, and only reaches MAINLOOP once bank1 has genuinely been
    selected for page2 - unlike a flat-memory model, this actually
    exercises (and can catch bugs in) the real boot-time bank-switch
    itself, not just the game logic that runs after it.

    The actual instruction-by-instruction boot only ever needs to run
    ONCE per process (same assembled ROM -> same deterministic boot
    trace every time) - every call after the first returns a fresh
    deepcopy of that one real post-boot snapshot instead of re-running
    tens of thousands of cpu.step() calls, which is what made tests
    that call fresh_cpu() many times (e.g. boss_test.py, 18 cases) slow.
    deepcopy, not a shared/reset object: each caller gets its own
    independent mem.flat/vram/registers, so nothing a test does to its
    cpu can leak into another test's.

    skip_intro (2026-09-23、ステージ2のスタート演出): 演出中は自機の操作
    系がUPDATE_TANK_ENTRYに差し替わるため、演出追加前から存在する大多数
    のテスト(「fresh_cpu()した瞬間から自機を普通に操作できる」前提)の
    ためにデフォルトで演出を丸ごと飛ばした状態を返す。演出自体を検証
    したいテスト(tank_entry_test.py)だけがskip_intro=Falseを指定する。"""
    global _BOOT_SNAPSHOT, _BOOT_SNAPSHOT_READY
    if _BOOT_SNAPSHOT is None:
        out, sym, text = get_out()
        bank0, bank1 = build_test.build_banks(out)
        mem = build_test.BankedMem(bank0, bank1)
        cpu = Z80(mem)
        cpu.pc = sym["INIT"]
        mainloop = sym["MAINLOOP"]
        steps = 0
        while cpu.pc != mainloop and steps < 300000:
            cpu.step()
            steps += 1
        assert steps < 300000, "never reached MAINLOOP"
        _BOOT_SNAPSHOT = cpu

    if skip_intro:
        if _BOOT_SNAPSHOT_READY is None:
            out, sym, text = get_out()
            ready = copy.deepcopy(_BOOT_SNAPSHOT)
            # (2026-09-23follow-up5): 落下演出は本編(地形スクロール・GAME_
            # TICK・敵スポーン)と並行して進むため、フレームを進めて演出を
            # 消化するとGAME_TICK等まで進んでしまい、演出追加前に書かれた
            # 既存テストの前提(fresh_cpu()直後=GAME_TICK 0・何もスポーン
            # していない)が崩れる。ASM自身の終了処理TANK_ENTRY_FINISHを
            # 直接呼んで「演出を丸ごと飛ばした」状態にする(本編は1フレーム
            # も進めない)。
            call_routine(ready, "TANK_ENTRY_FINISH")
            ready.pc = sym["MAINLOOP"]
            assert ready.rd(sym["TANK_ENTRY_ACT"]) == 0
            _BOOT_SNAPSHOT_READY = ready
        cpu = copy.deepcopy(_BOOT_SNAPSHOT_READY)
        if assert_bank_switch:
            assert cpu.mem.bankB == 1, f"ASCII16 bank1 was never selected for page2 (bankB={cpu.mem.bankB})"
        return cpu
    cpu = copy.deepcopy(_BOOT_SNAPSHOT)
    if assert_bank_switch:
        assert cpu.mem.bankB == 1, f"ASCII16 bank1 was never selected for page2 (bankB={cpu.mem.bankB})"
    return cpu


# round36-14: the old default (0x8000, page2's own base) is a real,
# reachable mid-routine address once the assembled program grows large
# enough - confirmed by a real false-positive this round (STAGE_SBEAM's
# OWN 2nd instruction landed exactly on 0x8000 after this round's new
# boss-form-change code shifted everything after it, making this loop
# mistake ordinary straight-line execution for a genuine RET and stop
# after just 1 real instruction). 0x0000 is never assembled code in this
# build (out of the real 0x4000h-0xBFFFh code range entirely - confirmed
# via get_out()'s own min address) and stays that way regardless of how
# large combined_test.asm grows, so it can't collide the same way again.
def call_routine(cpu, name, sentinel=0x0000):
    out, sym, text = get_out()
    cpu.sp = (cpu.sp - 2) & 0xFFFF
    cpu.mem[cpu.sp] = sentinel & 0xFF
    cpu.mem[cpu.sp + 1] = (sentinel >> 8) & 0xFF
    cpu.pc = sym[name]
    s = 0
    while cpu.pc != sentinel and s < 300000:
        cpu.step()
        s += 1
    assert s < 300000, f"call_routine({name}) never returned"


def step_frame(cpu):
    out, sym, text = get_out()
    mainloop = sym["MAINLOOP"]
    cpu.step()
    s = 1
    while cpu.pc != mainloop and s < 300000:
        cpu.step()
        s += 1
    return s



