import os
import re

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

# "98hは表示中アクセスでは29T必要なのでNOPは8回 しかし99hは8Tで良いこと
# になってるのでNOPは2回で問題ない 表示期間非常時期間とも同一" - real
# TMS9918 VDP timing: raw OUT (99h),A (VRAM address setup, 2 bytes) only
# needs 8T of recovery (2 NOPs); OUT (98h),A (the actual data byte)
# needs 29T (8 NOPs). Every raw DI-wrapped VDP write in this file used
# to pad BOTH ports uniformly with 8 NOPs - real, if harmless, wasted
# T-states on every single one of the 28 OUT(99h) sites in the file.
# This test reads the source directly (not just "does gameplay still
# look right") since a wrong NOP count is invisible to every other test
# in this whole file - none of them model VDP access timing at all,
# only the byte actually written, which doesn't change either way.
SRC_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "combined_test.asm")

with open(SRC_PATH) as f:
    lines = f.readlines()

def count_following_nops(lines, i):
    j = i + 1
    n = 0
    while j < len(lines) and lines[j].strip() == "NOP":
        n += 1
        j += 1
    return n

n99 = []
n98 = []
for i, line in enumerate(lines):
    if "OUT (99h),A" in line:
        n99.append((i + 1, count_following_nops(lines, i)))
    elif "OUT (98h),A" in line:
        n98.append((i + 1, count_following_nops(lines, i)))

check(f"found the expected number of raw OUT (99h),A sites ({len(n99)} - update this "
      "count deliberately if a new one is added, don't just let the test drift)",
      len(n99) == 28)
check(f"found the expected number of raw OUT (98h),A sites ({len(n98)})",
      len(n98) == 20)

bad99 = [(ln, n) for ln, n in n99 if n != 2]
check("every OUT (99h),A (VRAM address setup) is padded with exactly 2 NOPs (8T - matches "
      "the real TMS9918 control-port recovery time), not the old uniform 8",
      not bad99)
if bad99:
    print("  wrong 99h NOP counts:", bad99)

bad98 = [(ln, n) for ln, n in n98 if n != 8]
check("every OUT (98h),A (the actual VRAM data byte) still keeps its own genuinely-needed "
      "8 NOPs (29T, active-display data-port recovery) - untouched by this round's fix",
      not bad98)
if bad98:
    print("  wrong 98h NOP counts:", bad98)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
