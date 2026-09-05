"""round35: BIGZUM_TERRAIN_OK/ETANK_TERRAIN_OK (and the IDCACHE/terrain
setup that used to gate spawning on them) are gone - "地形も仮実装だから
平地条件いらない". Neither ALLOC_ETANK_SLOT nor ALLOC_BIGZUM_SLOT needs
any terrain priming before spawning any more.
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, call_routine

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)

SPRPAT = sym["SPRPAT"]
PAT_BIGZUM = sym["PAT_BIGZUM"]
PAT_ETANK_BL = sym["PAT_ETANK_BL"]
PAT_ETANK_BR = sym["PAT_ETANK_BR"]

check("PAT_ETANK_BL and PAT_ETANK_BR are 4 codes apart (matching every other 16x16-mode quadrant pair)",
      PAT_ETANK_BR - PAT_ETANK_BL == 4)
check("PAT_ETANK_BL is BigZum's own BL quadrant base (PAT_BIGZUM+8)", PAT_ETANK_BL == PAT_BIGZUM + 8)
check("PAT_ETANK_BR is BigZum's own BR quadrant base (PAT_BIGZUM+12)", PAT_ETANK_BR == PAT_BIGZUM + 12)

# Load BigZum's real pattern data first (as INIT does), remember it,
# then force-spawn Etank and confirm ONLY the BL/BR quadrants (156+8..
# 156+15) changed - TL (156-159) and TR (160-163) must be untouched.
cpu = fresh_cpu()
ETANK_POOL = sym["ETANK_POOL"]
BIGZUM_POOL = sym["BIGZUM_POOL"]
cpu.mem[sym["GAME_TICK"]] = 70
cpu.mem[sym["GAME_TICK"] + 1] = 0

tl_before = bytes(cpu.vram[SPRPAT + PAT_BIGZUM * 8: SPRPAT + (PAT_BIGZUM + 4) * 8])
tr_before = bytes(cpu.vram[SPRPAT + (PAT_BIGZUM + 4) * 8: SPRPAT + (PAT_BIGZUM + 8) * 8])

call_routine(cpu, "ALLOC_ETANK_SLOT")
check("Etank actually spawned", cpu.mem[ETANK_POOL + 0] == 1)

tl_after = bytes(cpu.vram[SPRPAT + PAT_BIGZUM * 8: SPRPAT + (PAT_BIGZUM + 4) * 8])
tr_after = bytes(cpu.vram[SPRPAT + (PAT_BIGZUM + 4) * 8: SPRPAT + (PAT_BIGZUM + 8) * 8])
check("BigZum's own TL quadrant pattern untouched by Etank's spawn", tl_before == tl_after)
check("BigZum's own TR quadrant pattern untouched by Etank's spawn", tr_before == tr_after)

# The BL/BR quadrant VRAM should now hold Etank's own art, not BigZum's.
import etank_gen
bits = etank_gen.load_bits("Etank")
expected_bl, expected_br = etank_gen.bottom_quadrants(bits)
actual_bl = list(cpu.vram[SPRPAT + PAT_ETANK_BL * 8: SPRPAT + PAT_ETANK_BL * 8 + 32])
actual_br = list(cpu.vram[SPRPAT + PAT_ETANK_BR * 8: SPRPAT + PAT_ETANK_BR * 8 + 32])
check("BL quadrant VRAM matches Etank's own real BL art (not a misaligned slice)", actual_bl == expected_bl)
check("BR quadrant VRAM matches Etank's own real BR art (not a misaligned slice)", actual_br == expected_br)

# BigZum's own spawn must reload its real BL/BR bytes, undoing Etank's
# borrow - the whole dynamic-sharing scheme is only safe because of this.
cpu.mem[ETANK_POOL + 0] = 0  # despawn Etank first - not required by any exclusion any more
                             # (round34-2, "排他制御は削除"), just isolates this specific check
call_routine(cpu, "ALLOC_BIGZUM_SLOT")
check("BigZum actually spawned", cpu.mem[BIGZUM_POOL + 0] == 1)
bl_reloaded = list(cpu.vram[SPRPAT + (PAT_BIGZUM + 8) * 8: SPRPAT + (PAT_BIGZUM + 8) * 8 + 32])
check("BigZum's own spawn reloads its real BL quadrant, undoing Etank's borrow", bl_reloaded != actual_bl)

print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
