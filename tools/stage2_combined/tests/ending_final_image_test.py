"""Round80follow-up ("ではこの画像をMission completed表示後10秒したら
表示 ボタンが押されたらスタート画面へ タイトル表示同様に圧縮かけて"):
regression coverage for ENDING_SHOW_FINAL_IMAGE (tools/stage2_combined/
combined_test.asm) - the SCREEN2 final-image display + button-wait
screen that replaces the old "just wait 10 more seconds and trampoline"
behavior once ENDING_ACT reaches 4 ("MISSION COMPLETED" shown for
ENDING_RETURN_WAIT_TICKS).

This routine never RETs (it either loops waiting for a button, or - in
this standalone build with no title bank to jump to - idles forever
once pressed), so it can't be driven with call_routine()/step_frame()
like most of this project's other tests; instead this mirrors
tools/title_screen/title_test.py's own run_to_wait() technique (step()
in a loop until PC reaches a target label).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from banked_helpers import get_out, fresh_cpu, step_frame

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
sys.path.insert(0, os.path.join(REPO, "tools", "stage2_combined"))
sys.path.insert(0, os.path.join(REPO, "tools", "title_screen"))
import ending_image_gen  # noqa: E402
import title_bg_gen  # noqa: E402

out, sym, text = get_out()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


ENDING_ACT = sym["ENDING_ACT"]
SPRATR = sym["SPRATR"]
PSG_ADDR = sym["PSG_ADDR"]
PSG_DATA = sym["PSG_DATA"]
ENDING_SHOW_FINAL_IMAGE = sym["ENDING_SHOW_FINAL_IMAGE"]
ENDING_WAIT_FINAL_BUTTON = sym["ENDING_WAIT_FINAL_BUTTON"]
ENDING_FINAL_BUTTON_PRESSED = sym["ENDING_FINAL_BUTTON_PRESSED"]
ENDING_FINAL_IDLE = sym["ENDING_FINAL_IDLE"]
MAINLOOP = sym["MAINLOOP"]


def run_until_pc(cpu, targets, limit):
    """steps until PC lands on any address in `targets` (a set/list) -
    same technique title_test.py's run_to_wait() uses for a routine
    that never RETs."""
    targets = set(targets)
    steps = 0
    while cpu.pc not in targets and steps < limit:
        cpu.step()
        steps += 1
    return steps


# ---- normal frames (ENDING_ACT 0-3) are unaffected by the new per-frame ----
# ---- ENDING_ACT==4 check (regression guard on the MAINLOOP body itself) ----
for act in (0, 1, 2, 3):
    cpu = fresh_cpu()
    cpu.mem[ENDING_ACT] = act
    steps = step_frame(cpu)
    check(f"a normal frame with ENDING_ACT={act} still returns to MAINLOOP "
          "normally (doesn't get diverted into ENDING_SHOW_FINAL_IMAGE)",
          cpu.pc == MAINLOOP and steps < 300000)

# ---- ENDING_ACT==4: MAINLOOP's own per-frame body diverts here permanently ----
cpu = fresh_cpu()
cpu.mem[ENDING_ACT] = 4
cpu.pc = MAINLOOP
steps = run_until_pc(cpu, [ENDING_WAIT_FINAL_BUTTON], 600000)
check("ENDING_ACT==4 makes MAINLOOP's own per-frame body jump into "
      "ENDING_SHOW_FINAL_IMAGE (real full-frame run from MAINLOOP, not a "
      "direct CALL) and it reaches the button-wait loop",
      cpu.pc == ENDING_WAIT_FINAL_BUTTON and steps < 600000)

# ---- VRAM content: the real SCREEN2 art, decompressed byte-for-byte ----
# ---- (except SPRATR's own first byte, intentionally patched - see below) ----
_payload = ending_image_gen.load_payload()
_vram_bg = bytes(cpu.vram[0:title_bg_gen.PAYLOAD_LEN])
_payload_minus_sprattr0 = _payload[:0x1B00] + bytes([_vram_bg[0x1B00]]) + _payload[0x1B01:]
check(f"final-image VRAM 0000h-{title_bg_gen.PAYLOAD_LEN-1:04X}h matches "
      "EndingImage.SC2's real payload EXACTLY after RLE decompression through "
      "the shared bgm-data/chardata bank (except SPRATR's own first byte)",
      _vram_bg == _payload_minus_sprattr0)

check("final-image sprite attribute table's first Y byte is forced to 0D1h "
      "(stop marker) - this art has no sprite pattern data of its own",
      cpu.vram[SPRATR] == 0xD1)

# ---- RLE codec self-consistency (independent Python reference) ----
_compressed, _segments = title_bg_gen.rle_encode(_payload)
check("ENDING_IMAGE_RLE_SEGMENTS matches the real encoder's own segment count",
      sym["ENDING_IMAGE_RLE_SEGMENTS"] == _segments)
check("title_bg_gen.rle_decode(rle_encode(payload)) round-trips byte-for-byte "
      "for EndingImage.SC2 too (same codec, different asset)",
      title_bg_gen.rle_decode(_compressed, _segments) == _payload)
check(f"RLE compression: {title_bg_gen.PAYLOAD_LEN} -> {len(_compressed)} bytes "
      f"({100*len(_compressed)/title_bg_gen.PAYLOAD_LEN:.1f}%, saved "
      f"{title_bg_gen.PAYLOAD_LEN-len(_compressed)} bytes)",
      len(_compressed) < title_bg_gen.PAYLOAD_LEN)

# ---- PSG fully muted before the image is shown ----
check("chA (SE) muted (R8=0) before showing the final image",
      cpu.psg_regs.get(8) == 0)
check("chB (BGM melody) muted (R9=0) before showing the final image",
      cpu.psg_regs.get(9) == 0)
check("chC (BGM bass) muted (R10=0) before showing the final image",
      cpu.psg_regs.get(10) == 0)

# ---- windowB correctly restored to Stage2's own bank after the one-shot ----
# ---- chardata-bank borrow (SWITCH_TO_CHARDATA_BANK/RESTORE_OWN_BANK_B) ----
check("windowB (page2) is back on Stage2's own bank (bankB=1) after "
      "borrowing the shared chardata bank to decompress the image, not left "
      "pointing at the chardata bank",
      cpu.mem.bankB == 1)

# ---- button-wait loop genuinely waits (neither trigger pressed) ----
cpu_noinput = fresh_cpu()
cpu_noinput.mem[ENDING_ACT] = 4
cpu_noinput.pc = MAINLOOP
run_until_pc(cpu_noinput, [ENDING_WAIT_FINAL_BUTTON], 600000)
for _ in range(2000):
    cpu_noinput.step()
check("with neither trigger pressed, ENDING_WAIT_FINAL_BUTTON keeps looping "
      "forever instead of proceeding on its own",
      cpu_noinput.pc == ENDING_WAIT_FINAL_BUTTON)

# ---- trigger A (id1) unlocks the wait loop ----
cpu_a = fresh_cpu()
cpu_a.mem[ENDING_ACT] = 4
cpu_a.pc = MAINLOOP
run_until_pc(cpu_a, [ENDING_WAIT_FINAL_BUTTON], 600000)
cpu_a.sim_trig_a = True
steps = run_until_pc(cpu_a, [ENDING_FINAL_BUTTON_PRESSED], 2000)
check("pressing trigger A (id1) advances past ENDING_WAIT_FINAL_BUTTON to "
      "ENDING_FINAL_BUTTON_PRESSED",
      cpu_a.pc == ENDING_FINAL_BUTTON_PRESSED and steps < 2000)
for _ in range(50):
    cpu_a.step()
check("standalone build (no title bank to jump to): stays parked at "
      "ENDING_FINAL_IDLE forever after the button press, doesn't crash or "
      "run off into unrelated code (build_full_rom.py's Comb-only patch "
      "replaces this idle loop with the real title trampoline)",
      cpu_a.pc == ENDING_FINAL_IDLE)

# ---- trigger B (id3) alone also unlocks the wait loop (either button works) ----
cpu_b = fresh_cpu()
cpu_b.mem[ENDING_ACT] = 4
cpu_b.pc = MAINLOOP
run_until_pc(cpu_b, [ENDING_WAIT_FINAL_BUTTON], 600000)
cpu_b.sim_trig_b = True
steps = run_until_pc(cpu_b, [ENDING_FINAL_BUTTON_PRESSED], 2000)
check("pressing trigger B (id3) alone also advances past "
      "ENDING_WAIT_FINAL_BUTTON",
      cpu_b.pc == ENDING_FINAL_BUTTON_PRESSED and steps < 2000)


print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    sys.exit(1)
