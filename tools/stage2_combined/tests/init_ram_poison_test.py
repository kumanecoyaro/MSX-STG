"""実機フィードバック対応 (round36-14 follow-up#13の直後、"地形スクロール
が乱れてる...一つ前のビルドでも地形は乱れるが 実行してから最新を実行
すると正しく動く どこかで初期化ミスしてるな" + "1回だけだがスタート
直後にFlyerレーザーがいきなり飛んできた"): ETANK_BULLET_ACT/MINE_POOL/
FLYER_LASER_ACT were never explicitly zeroed at INIT - fresh_cpu()'s own
BankedMem starts as a plain zero-filled bytearray(0x10000) in Python, so
every existing test's own "cold boot" was accidentally already "RAM
starts zero", masking this exact bug class entirely. Real MSX RAM holds
whatever garbage was left over from before power-on (or, on a reload
without a full power cycle, whatever the PREVIOUS ROM's own RAM state
happened to be - exactly matching "1つ前のビルドを実行してから最新を
実行すると直る"). This test manually poisons RAM with a nonzero pattern
BEFORE running the real INIT trace (bypassing fresh_cpu()'s own cached,
already-post-boot snapshot) to catch this whole class of bug for real,
not just the 3 fields that were actually broken this round.
"""
import copy
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out
import build_test
from z80emu import Z80

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


def boot_with_poisoned_ram(poison_byte):
    """Real INIT trace, but with every flat RAM byte set to poison_byte
    before the very first instruction runs - simulates real MSX RAM
    holding leftover garbage at power-on, unlike fresh_cpu()'s own
    implicitly-zeroed bytearray."""
    bank0, bank1 = build_test.build_banks(out)
    mem = build_test.BankedMem(bank0, bank1)
    for i in range(len(mem.flat)):
        mem.flat[i] = poison_byte
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    mainloop = sym["MAINLOOP"]
    steps = 0
    while cpu.pc != mainloop and steps < 300000:
        cpu.step()
        steps += 1
    assert steps < 300000, "never reached MAINLOOP"
    return cpu


ETANK_BULLET_ACT = sym["ETANK_BULLET_ACT"]
ETANK_SPAWN_X = sym["ETANK_SPAWN_X"]
ETANK_BULLET_FIRED = sym["ETANK_BULLET_FIRED"]
MINE_POOL = sym["MINE_POOL"]
MINE_SLOT_SIZE = sym["MINE_SLOT_SIZE"]
MINE_SLOT_COUNT = sym["MINE_SLOT_COUNT"]
MINE_SPRITE_ATTRS = sym["MINE_SPRITE_ATTRS"]
FLYER_LASER_ACT = sym["FLYER_LASER_ACT"]
EBULLET_POOL = sym["EBULLET_POOL"]
EBULLET_SLOT_SIZE = sym["EBULLET_SLOT_SIZE"]
EBULLET_SLOT_COUNT = sym["EBULLET_SLOT_COUNT"]
ENEMY_POOL = sym["ENEMY_POOL"]
FLYER_POOL = sym["FLYER_POOL"]
FLYER_SLOT_SIZE = sym["FLYER_SLOT_SIZE"]
FLYER_SLOT_COUNT = sym["FLYER_SLOT_COUNT"]
ZUM_POOL = sym["ZUM_POOL"]
BIGZUM_POOL = sym["BIGZUM_POOL"]
ETANK_POOL = sym["ETANK_POOL"]
BULLET0_ACT = sym["BULLET0_ACT"]
BULLET1_ACT = sym["BULLET1_ACT"]
BULLET2_ACT = sym["BULLET2_ACT"]
BULLET3_ACT = sym["BULLET3_ACT"]
BOSS_ACT = sym["BOSS_ACT"]

for poison in (0xFF, 0xAA, 0x55, 0x01):
    cpu = boot_with_poisoned_ram(poison)
    check(f"poison=0x{poison:02X}: ETANK_BULLET_ACT is 0 after INIT (was never cleared before this round's fix)",
          cpu.mem[ETANK_BULLET_ACT] == 0)
    check(f"poison=0x{poison:02X}: ETANK_SPAWN_X/ETANK_BULLET_FIRED are 0 after INIT",
          cpu.mem[ETANK_SPAWN_X] == 0 and cpu.mem[ETANK_BULLET_FIRED] == 0)
    check(f"poison=0x{poison:02X}: both MINE_POOL instances' own ACT are 0 after INIT",
          all(cpu.mem[MINE_POOL + i * MINE_SLOT_SIZE] == 0 for i in range(MINE_SLOT_COUNT)))
    check(f"poison=0x{poison:02X}: MINE_SPRITE_ATTRS starts hidden (Y=209), not garbage",
          cpu.mem[MINE_SPRITE_ATTRS] == 209)
    check(f"poison=0x{poison:02X}: FLYER_LASER_ACT is 0 after INIT (the reported \"phantom laser at start\" bug)",
          cpu.mem[FLYER_LASER_ACT] == 0)
    check(f"poison=0x{poison:02X}: BULLET0/1/2/3_ACT are all 0 after INIT",
          all(cpu.mem[a] == 0 for a in (BULLET0_ACT, BULLET1_ACT, BULLET2_ACT, BULLET3_ACT)))
    check(f"poison=0x{poison:02X}: EBULLET_POOL is fully zeroed after INIT (already-established convention, spot-checked)",
          all(cpu.mem[EBULLET_POOL + i] == 0 for i in range(EBULLET_SLOT_SIZE * EBULLET_SLOT_COUNT)))
    check(f"poison=0x{poison:02X}: ENEMY_POOL's own ACT (slot0) is 0 after INIT",
          cpu.mem[ENEMY_POOL] == 0)
    # FLYER_POOL is NOT fully zero by design - IFLSP_LOOP deliberately
    # assigns each slot's own SPRIDX (+4) to its index (0,1,2,...), same
    # as ENEMY_POOL's own E_SPRIDX - only each slot's own ACT needs to
    # be 0.
    check(f"poison=0x{poison:02X}: every FLYER_POOL slot's own ACT is 0 after INIT",
          all(cpu.mem[FLYER_POOL + i * FLYER_SLOT_SIZE] == 0 for i in range(FLYER_SLOT_COUNT)))
    check(f"poison=0x{poison:02X}: ...and each slot's own SPRIDX (+4) is correctly its own index, not poisoned",
          all(cpu.mem[FLYER_POOL + i * FLYER_SLOT_SIZE + 4] == i for i in range(FLYER_SLOT_COUNT)))
    check(f"poison=0x{poison:02X}: ZUM_POOL/BIGZUM_POOL/ETANK_POOL's own ACT (slot0) are 0 after INIT",
          cpu.mem[ZUM_POOL] == 0 and cpu.mem[BIGZUM_POOL] == 0 and cpu.mem[ETANK_POOL] == 0)
    check(f"poison=0x{poison:02X}: BOSS_ACT is 0 (not spawned) after INIT",
          cpu.mem[BOSS_ACT] == 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
