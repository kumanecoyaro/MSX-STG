"""round39 ("ではバンクテストをしたいので...新バンクには必要な初期化処理を
実装した上で PUSH STARTと表示しStage1とStage2のボスを適当に表示して
ボタンが押されたらStage1へトランポリンするように"): regression coverage
for the new title-screen bank (tools/title_screen/title_test.asm).

Verifies the real VRAM content INIT actually produces (boss art, sprite
attrs, text) and that the button-press trampoline writes the correct
bank-select bytes and lands on Stage1's own INIT address - the same
"assemble the real production source, run it, inspect real VRAM/port
state" approach every other test file in this project already uses, not
a reimplementation.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_test
import title_gen
from z80emu import Z80

out, sym, text = build_test.assemble()

ok = []
fail = []
def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


class BankedMem:
    """Standalone 2-bank harness (title's own bank0/bank1 numbering) -
    logs every bank-select port write so the button-press trampoline can
    be checked without needing the real Stage1/Stage2 content mapped."""
    def __init__(self, bank0, bank1, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = [bank0]
        self.banksB = [bank1, bank1]
        self.bankA = 0
        self.bankB = 0
        self.portA = portA
        self.portB = portB
        self.switch_log = []

    def __getitem__(self, addr):
        addr &= 0xFFFF
        if 0x4000 <= addr <= 0x7FFF:
            return self.banksA[self.bankA][addr - 0x4000]
        if 0x8000 <= addr <= 0xBFFF:
            return self.banksB[self.bankB][addr - 0x8000]
        return self.flat[addr]

    def __setitem__(self, addr, val):
        addr &= 0xFFFF
        val &= 0xFF
        if addr == self.portA:
            self.bankA = val % len(self.banksA)
            self.switch_log.append(("A", val))
            return
        if addr == self.portB:
            self.bankB = val % len(self.banksB)
            self.switch_log.append(("B", val))
            return
        if 0x4000 <= addr <= 0xBFFF:
            return
        self.flat[addr] = val


def fresh_cpu():
    bank0, bank1 = build_test.build_banks(out)
    mem = BankedMem(bank0, bank1)
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    cpu.sp = 0xF380
    return cpu, mem


def run_to_wait(cpu, limit=300000):
    wait = sym["WAIT_FOR_START"]
    steps = 0
    while cpu.pc != wait and steps < limit:
        cpu.step()
        steps += 1
    assert cpu.pc == wait, "title screen's own INIT never reached WAIT_FOR_START"
    return steps


# ---- INIT-time VRAM content ----
cpu, mem = fresh_cpu()
run_to_wait(cpu)

boss1_patterns = title_gen.stage1_boss_patterns()
check("Stage1 boss BG patterns loaded at codes192-255 (512 bytes)",
      list(cpu.vram[192 * 8:192 * 8 + 512]) == boss1_patterns)

blank48 = title_gen.stage1_blank48_pattern()
check("Stage1's own code48 (blank) pattern loaded",
      list(cpu.vram[48 * 8:48 * 8 + 8]) == blank48)

boss_map = title_gen.stage1_boss_map()
name_table_ok = True
for row in range(16):
    dest = 0x1800 + (2 + row) * 32 + 2
    if list(cpu.vram[dest:dest + 5]) != boss_map[row * 5:row * 5 + 5]:
        name_table_ok = False
        break
check("Stage1 BOSS_MAP drawn into the name table at row2/col2 (5x16)", name_table_ok)

for group in (4, 6, 8, 9, 10, 24, 25, 26, 27, 28, 29, 30, 31):
    check(f"color group{group} set to 0F1h (white on black)",
          cpu.vram[0x2000 + group] == 0xF1)

boss2_quads = title_gen.stage2_boss_quads()
check("Stage2 (Sasapi) hw sprite patterns loaded at SPRPAT (512 bytes)",
      list(cpu.vram[0x3800:0x3800 + 512]) == boss2_quads)

boss2_attrs = title_gen.stage2_boss_sprite_attrs(base_y=40, base_x=170, base_code=0, color=15)
check("Stage2 (Sasapi) sprite attribute table (16 entries, 64 bytes)",
      list(cpu.vram[0x1B00:0x1B00 + 64]) == boss2_attrs)

check('name table @1A8Bh reads "PUSH START"',
      bytes(cpu.vram[0x1A8B:0x1A8B + 10]) == b"PUSH START")

# ---- button-press trampoline ----
cpu, mem = fresh_cpu()
run_to_wait(cpu)
wait = sym["WAIT_FOR_START"]
revisits = 0
for _ in range(400):
    cpu.step()
    if cpu.pc == wait:
        revisits += 1
check("WAIT_FOR_START genuinely loops (revisits its own label) while the button is unpressed",
      revisits >= 5)
check("WAIT_FOR_START never touches the bank-select ports while looping",
      mem.switch_log == [])

# ---- this harness's own BankedMem only has ONE real bank at index0 for
# each window (title's own content) - it deliberately doesn't model
# Stage1's real banks (2/3), so the post-modulo mem.bankA/bankB would
# misleadingly read back as 0 regardless of what byte value was
# actually written. What this test CAN and does verify is the RAW byte
# sequence written to the two port addresses - the real thing that
# matters for wiring into the actual 6-bank Comb ROM (see
# tools/bankswitch_poc/verify_comb.py for the full real-bank version of
# this same trampoline, already passing end-to-end).
cpu, mem = fresh_cpu()
run_to_wait(cpu)
cpu.sim_trig_a = True
steps = 0
while cpu.pc != 0x4010 and steps < 100000:
    cpu.step()
    steps += 1
check("button press trampolines to Stage1's own INIT address (4010h)", cpu.pc == 0x4010)
check("trampoline wrote window B (7000h)=3 then window A (6000h)=2 - same 2-hop order as "
      "Stage1->Stage2's own trampoline in build_full_rom.py, and the real bank indices "
      "verify_comb.py's own end-to-end test confirms Stage1 actually lives at",
      mem.switch_log == [("B", 3), ("A", 2)])


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail)
