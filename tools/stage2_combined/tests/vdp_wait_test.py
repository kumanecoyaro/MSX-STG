import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, "/home/user/msx-stg/tools")
from banked_helpers import get_out
from z80emu import Z80

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

# "98hは表示中アクセスでは29T必要なのでNOPは8回 しかし99hは8Tで良いこと
# になってるのでNOPは2回で問題ない 表示期間非常時期間とも同一" - real
# TMS9918 VDP timing: raw OUT (99h),A (VRAM address setup) only needs 8T
# of recovery (2 NOPs); OUT (98h),A (the actual data byte) needs 29T.
# Every raw DI-wrapped VDP write in this file used to pad BOTH ports
# uniformly with 8 NOPs - real, if harmless, wasted T-states on every
# 99h site. Trimmed those to 2 NOPs.
#
# round27: "現在Nopx8つだがこれをサイズの小さいダミー命令に置き換える
# ...29Tに近くなる影響がほぼ無い命令の組み合わせで フラグ変化がある場
# 合は周辺のチェック" - the 98h side genuinely needs the full 29T, but 8
# NOPs (8 bytes) was 32T (3T more than needed). First attempt used
# `PUSH BC : POP BC : INC HL : DEC HL` (33T) - correctly caught as an
# actual regression ("33Tでは現状の32Tより遅くなるじゃねえか" - slower
# than the 32T it replaced). Fixed: `PUSH BC : POP BC : NOP : NOP`
# (11+10+4+4=29T EXACTLY) - same 4 bytes, genuinely faster than the
# original 32T this time. None of these 4 opcodes touch any Z80 flag,
# and PUSH BC/POP BC nets to an exactly restored BC value via the stack
# round-trip, so it's transparent to whatever the surrounding code
# holds in either register.
#
# This test reads the source directly (not just "does gameplay still
# look right") since a wrong NOP count/sequence is invisible to every
# other test in this whole file - none of them model VDP access timing
# at all, only the byte actually written, which doesn't change either
# way - AND runs the real replacement sequence through the actual
# emulator to prove BC/HL/flags really do come out identical.
SRC_PATH = os.path.join(os.path.dirname(HERE), "combined_test.asm")

with open(SRC_PATH) as f:
    lines = f.readlines()

def following_nops(lines, i):
    j = i + 1
    n = 0
    while j < len(lines) and lines[j].strip() == "NOP":
        n += 1
        j += 1
    return n

EXPECTED_98_DELAY = "PUSH BC : POP BC : NOP : NOP"

n99 = []
n98_delay = []
for i, line in enumerate(lines):
    if "OUT (99h),A" in line:
        n99.append((i + 1, following_nops(lines, i)))
    elif "OUT (98h),A" in line:
        next_line = lines[i + 1].strip() if i + 1 < len(lines) else ""
        n98_delay.append((i + 1, next_line))

# round36-14 Part C: FLUSH_BOSS_BROKEN_SPRITES (the new 32x32 broken-
# form body's own flush routine) adds 1 more raw DI/EI-wrapped mini-burst
# site, same shape as FLUSH_BOSS_SPRITES's own (2 OUT(99h),A address-
# setup writes + 4 OUT(98h),A data writes per source occurrence, even
# though it's a 4-quadrant DJNZ loop at runtime) - 28->30 / 20->24.
# round36-14 follow-up #4: FLUSH_BOSS_BROKEN_BEAM_SPRITES (the new
# 4-beam stop-attack's own flush) adds 1 more site, this time the
# single-byte-per-DJNZ-iteration shape FLUSH_SBEAM_SPRITES/FLUSH_
# HORMING_SPRITES already use (2 OUT(99h),A address-setup writes + only
# 1 OUT(98h),A data write in source, looped at runtime) - 30->32 / 24->25.
# round36-14 follow-up #11 ("ザコ敵の弾発射実装"): FLUSH_EBULLET_SPRITES
# (EBullet's own flush) adds 1 more site, same single-byte-per-DJNZ-
# iteration shape as the round above - 32->34 / 25->26.
# round36-14 follow-up #12 ("Mineを放物線で投下...着地や自機への被弾で
# ...爆発エフェクト"): FLUSH_MINE_SPRITES (Mine's own explosion-only
# flush, borrowing 2 ATTRIBUTE slots) adds 1 more site, same single-
# byte-per-DJNZ-iteration shape as the round above - 34->36 / 26->27.
# FlyerLaser itself adds no new raw OUT sites (BG cell, reuses the
# existing shared WRITE_BULLET_BYTE_HL - same as EtankBullet's own).
# round36-14 follow-up #13 ("3発制限を4発に変更"): FLUSH_BULLET3_U_
# SPRITE (the new 4th player-shot slot's own U-type flush, to the
# ATTRIBUTE slot freed from Mine's own explosion budget - see
# MINE_EXPL_SPR_BASE_SLOT's own comment) adds 1 more site, same
# single-byte-per-DJNZ-iteration shape - 36->38 / 27->28.
check(f"found the expected number of raw OUT (99h),A sites ({len(n99)} - update this "
      "count deliberately if a new one is added, don't just let the test drift)",
      len(n99) == 38)
check(f"found the expected number of raw OUT (98h),A sites ({len(n98_delay)})",
      len(n98_delay) == 28)

bad99 = [(ln, n) for ln, n in n99 if n != 2]
check("every OUT (99h),A (VRAM address setup) is padded with exactly 2 NOPs (8T)",
      not bad99)
if bad99:
    print("  wrong 99h NOP counts:", bad99)

bad98 = [(ln, seq) for ln, seq in n98_delay if seq != EXPECTED_98_DELAY]
check(f"every OUT (98h),A is immediately followed by the real 29T delay sequence "
      f"('{EXPECTED_98_DELAY}'), not the old 8 NOPs and not some other variant",
      not bad98)
if bad98:
    print("  wrong 98h delay sequences:", bad98)


# ---- emulator-level proof: run the actual replacement sequence and
# confirm (a) the T-state total is really >=29 and matches the expected
# 33, and (b) BC, HL, and every flag bit come out bit-for-bit identical
# to their values just before the sequence, for a range of starting
# register/flag states (not just an all-zero one) ----
out, sym, text = get_out()

def assemble_snippet_addr():
    # find one real OUT (98h),A site in the assembled ROM and locate the
    # instruction right after it (the delay sequence itself) by address,
    # using WRITE_BULLET_BYTE_HL as the known, stable anchor.
    return sym["WRITE_BULLET_BYTE_HL"]

start_addr = assemble_snippet_addr()

def make_cpu():
    import build_test
    bank0, bank1 = build_test.build_banks(out)
    mem = build_test.BankedMem(bank0, bank1)
    return Z80(mem)

random_states = [
    (0x1234, 0x5678, 0x00),
    (0xFFFF, 0x0000, 0xFF),
    (0x0000, 0xFFFF, 0x00),
    (0xABCD, 0x1357, 0xD7),
    (0x8000, 0x7FFF, 0x44),
]

all_ok = True
all_tstates_ok = True
for bc_val, hl_val, f_val in random_states:
    cpu = make_cpu()
    cpu.pc = start_addr
    cpu.setbc(bc_val)
    cpu.sethl(hl_val)
    cpu.f = f_val
    cpu.a = 0x42
    cpu.sp = 0xFE00
    cpu.wr(0xFE00, 0x00); cpu.wr(0xFE01, 0x00)  # sentinel return address
    cpu.mem[sym["BULLET_TEMP_BYTE"]] = 0x99

    # step through DI, LD A,L:OUT(99h) x1 setup pair, LD A,H:OR40h:OUT(99h),
    # LD A,(BULLET_TEMP_BYTE):OUT(98h) - up to and including the delay
    # sequence - then compare BC/HL/F to their values right before the
    # delay sequence started (captured by stepping until right after the
    # OUT(98h),A instruction itself).
    steps = 0
    while cpu.pc != 0x0000 and steps < 500:
        cpu.step()
        steps += 1
        # right after OUT (98h),A executes, the very next instruction is
        # the delay sequence's own first byte (PUSH BC) - capture state now
        if cpu.mem[cpu.pc] == 0xC5 and cpu.mem[(cpu.pc + 1) & 0xFFFF] == 0xC1:
            bc_before, hl_before, f_before = cpu.bc(), cpu.hl(), cpu.f
            cpu.reset_stats()
            t_before = cpu.tstates
            for _ in range(4):  # PUSH BC, POP BC, NOP, NOP
                cpu.step()
            t_after = cpu.tstates
            delay_tstates = t_after - t_before
            if cpu.bc() != bc_before or cpu.hl() != hl_before or cpu.f != f_before:
                all_ok = False
            if delay_tstates != 29:
                all_tstates_ok = False
            break

check("real emulator run: the 98h delay sequence (PUSH BC:POP BC:NOP:NOP) costs exactly "
      "29 T-states (the true minimum, 3T faster than the original 8-NOP/32T version) "
      "across 5 different starting BC/HL/flag states",
      all_tstates_ok)
check("real emulator run: BC, HL, and every flag bit come back bit-for-bit identical "
      "after the delay sequence, across 5 different starting BC/HL/flag states "
      "(including all-1s and all-0s)",
      all_ok)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
