import os
import re
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

STACKTOP = sym["STACKTOP"]

# "実機で確認すると起動直後にブラックアウトする...このバグり方で怪しい
# のは RAM、スタック、バンクだな...スタックが溢れてないかチェック" - a
# real bug found this round: SBEAM_SPRITE_ATTRS (88 bytes) originally
# sat at F314h, only 20 bytes below STACKTOP(F380h) - a direct per-
# instruction SP trace through boss spawn (z80emu.py, active input, no
# interrupts simulated at all - z80emu.py never fires them, a real
# blind spot every "real MAINLOOP" test this whole session shared)
# found ordinary nested CALLs alone already dipping SP to F36Ah,
# genuinely inside that array's own last byte (F36Bh). Relocated to
# C000h (deep in the otherwise-unused C000h-EEFFh region). This test
# guards the general case, not just that one array: (a) every RAM
# variable's own address must sit comfortably below STACKTOP with real
# headroom, and (b) a real, active-input MAINLOOP sweep's own measured
# SP low-water mark must never fall inside ANY variable's byte range -
# the exact class of check that would have caught this immediately.

RAM_VAR_RE = re.compile(r'^(\w+)\s+EQU\s+0?([0-9A-Fa-f]{4})h')
SRC_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "combined_test.asm")

addrs = []
with open(SRC_PATH) as f:
    for line in f:
        m = RAM_VAR_RE.match(line.strip())
        if m:
            name, hx = m.groups()
            val = int(hx, 16)
            # strictly BELOW STACKTOP only - addresses at/above it (e.g.
            # HTIMI_HOOK at 0FD9Fh, round36-14 follow-up#24's own BIOS
            # vblank-hook RAM reference) are never at risk of a stack
            # collision (the stack starts AT STACKTOP and only grows
            # downward from there), so they don't belong in this "how
            # close is the closest game variable to the stack" scan.
            # Before HTIMI_HOOK, nothing in this file ever happened to
            # sit above STACKTOP, so this bound was previously
            # (accidentally) equivalent to "highest of everything below
            # STACKTOP, found via addrs[-2] since addrs[-1] always
            # happened to be STACKTOP itself" - that coincidence broke
            # the moment a second above-STACKTOP symbol existed.
            if 0xC000 <= val < STACKTOP:
                addrs.append((val, name))
addrs.sort()

# STACK_SAFETY_MARGIN: every named RAM variable must end at least this
# many bytes below STACKTOP - matches the standard this file's own
# STACKTOP comment already established ("256+ bytes of genuinely free
# headroom...comfortably past anything a real interrupt handler plus
# our own deepest measured call nesting could plausibly need").
STACK_SAFETY_MARGIN = 0x60
highest_addr, highest_name = addrs[-1]
check(f"the highest-address RAM variable below STACKTOP ({highest_name} at "
      f"{hex(highest_addr)}) leaves at least {hex(STACK_SAFETY_MARGIN)} bytes of "
      "headroom before STACKTOP",
      STACKTOP - highest_addr >= STACK_SAFETY_MARGIN)

check("SBEAM_SPRITE_ATTRS no longer sits in the old danger zone (F314h, only 20 bytes "
      "below STACKTOP)", sym["SBEAM_SPRITE_ATTRS"] < 0xE000)


# ---- real, per-instruction SP trace through a real MAINLOOP playthrough
# (active input: movement + firing, through boss spawn and into its
# first pose) - the actual empirical check that would have caught the
# SBEAM_SPRITE_ATTRS collision immediately, rather than relying only on
# a static proximity margin. Checks the low-water mark against the
# highest-address named variable directly (NOT against the gap to the
# next symbol - most gaps between adjacent EQUs are legitimate free
# space, not padding, so treating "next symbol's start" as "this
# variable's own end" produces false positives for exactly the isolated
# scalar fields, like SBEAM_BLINK, that sit right below STACKTOP).
cpu = fresh_cpu()
mainloop = sym["MAINLOOP"]
min_sp = cpu.sp
min_sp_frame = -1
FRAMES = 9000  # comfortably past BOSS_SPAWN_TICK(999)*8=7992, into the boss's first pose
for f in range(FRAMES):
    cpu.sim_dir = 3       # right
    cpu.sim_trig_a = True
    cpu.sim_trig_b = False
    cpu.step()
    if cpu.sp < min_sp:
        min_sp = cpu.sp; min_sp_frame = f
    s = 1
    while cpu.pc != mainloop and s < 300000:
        cpu.step()
        if cpu.sp < min_sp:
            min_sp = cpu.sp; min_sp_frame = f
        s += 1

check(f"real MAINLOOP (active input, {FRAMES} frames through boss spawn): the stack's "
      f"own measured low-water mark ({hex(min_sp)} at frame {min_sp_frame}) stays at or "
      f"above the highest-address named variable ({hex(highest_addr)})",
      min_sp >= highest_addr)
check(f"real MAINLOOP: the same measured low-water mark also leaves real headroom "
      f"(>={hex(0x10)} bytes) below STACKTOP - a regression guard calibrated to the "
      f"currently-measured worst case (22 bytes/0x16), not a claim that this margin is "
      "generous: real interrupt-handler stack usage is never simulated by this test "
      "harness at all (z80emu.py never fires interrupts), so this number is a floor for "
      "catching further regressions, not proof of real-hardware safety",
      STACKTOP - min_sp >= 0x10)

# ---- round36-14 follow-up#24: this file's first REAL interrupt handler
# (BGM_TICK, installed into the H.TIMI hook) makes the above blind spot
# concrete instead of theoretical - on real hardware, BGM_TICK's own
# stack usage (measured below) plus the BIOS's own IM1 prologue land
# ON TOP OF whatever min_sp already was at the exact instant the
# interrupt fires, which could be this file's own measured worst case
# above. This check is the arithmetic that blind spot needs: does the
# real gap between "how deep MAINLOOP alone ever gets" and "the nearest
# live game variable" comfortably cover BGM_TICK's own real, measured
# footprint plus a documented (not measured - z80emu.py has no BIOS ROM
# to execute) allowance for the BIOS's own interrupt-entry overhead?
#
# round40: BGM_TICK's worst case is now BOTH channels taking their own
# new-row path in the same tick (PUSH AF/BC/DE/HL, always - the old
# "row-hold only pushes AF" asymmetric optimization no longer applies
# now that either channel can independently need a fresh row every
# tick - plus whichever of CALL BGMT_UPDATE_B/BGMT_UPDATE_C is
# currently on the stack, 2 bytes; the two calls are sequential, not
# nested, so only one adds its own return address at a time). A fresh
# post-boot cpu already has both BGM_B_TIMER/BGM_C_TIMER at 0 (INIT_BGM
# leaves them there so the very first real tick always loads a fresh
# row) with real DEFEAT song data already copied into RAM, so no manual
# poking is needed to exercise this worst case - same "just execute it
# and watch SP" method the empirical MAINLOOP trace above already uses.
cpu2 = fresh_cpu()
cpu2.sp = STACKTOP
cpu2.sp -= 2
cpu2.mem[cpu2.sp] = 0
cpu2.mem[cpu2.sp + 1] = 0
cpu2.pc = sym["BGM_TICK"]
bgm_min_sp = cpu2.sp
bgm_steps = 0
while cpu2.pc != 0 and bgm_steps < 5000:
    cpu2.step()
    if cpu2.sp < bgm_min_sp:
        bgm_min_sp = cpu2.sp
    bgm_steps += 1
BGM_TICK_WORST_CASE = STACKTOP - bgm_min_sp  # excludes the 2-byte sentinel pushed above

# BIOS IM1 prologue: not measurable at all here (z80emu.py has no real
# BIOS ROM to execute - see this file's own top-of-file comment history
# for the general "H.TIMI interrupt overhead this file's own test
# harness cannot simulate" blind spot). Conservative published-shape
# estimate: automatic PC push (2) + PUSH AF/BC/DE/HL/IX/IY (12) + a
# margin of error on top of that shape (6) = 20 bytes.
ASSUMED_BIOS_ISR_OVERHEAD = 20
real_headroom = min_sp - highest_addr
worst_case_needed = BGM_TICK_WORST_CASE + ASSUMED_BIOS_ISR_OVERHEAD
check(f"BGM_TICK's own measured worst-case stack depth ({BGM_TICK_WORST_CASE} bytes) plus "
      f"a conservative BIOS ISR-prologue allowance ({ASSUMED_BIOS_ISR_OVERHEAD} bytes, "
      "unmeasurable here - no real BIOS ROM in this harness) fits inside the real gap "
      f"between MAINLOOP's own measured low-water mark and the highest live variable "
      f"({real_headroom} bytes) - i.e. an H.TIMI interrupt firing at MAINLOOP's own worst "
      "real moment still can't reach a live variable",
      real_headroom >= worst_case_needed)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
