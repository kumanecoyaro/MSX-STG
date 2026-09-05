import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
# import THIS directory's own build_test.py before adding stage2_combined
# (which also has a same-named build_test.py) to sys.path - same shadowing
# risk stage2_combined/render_check.py's own comment already warns about.
sys.path.insert(0, HERE)
import build_test  # noqa: E402 - this dir's own (title_screen) build_test.py

sys.path.insert(0, os.path.join(REPO, "tools"))
from z80emu import Z80  # noqa: E402

sys.path.insert(0, os.path.join(REPO, "tools", "stage2_combined"))
import importlib.util  # noqa: E402
_rc_spec = importlib.util.spec_from_file_location(
    "stage2_combined_render_check", os.path.join(REPO, "tools", "stage2_combined", "render_check.py"))
_rc = importlib.util.module_from_spec(_rc_spec)
_rc_spec.loader.exec_module(_rc)
render_full = _rc.render_full  # reuse stage2_combined's own SCREEN1+sprite renderer


class BankedMem:
    def __init__(self, bank0, bank1, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = [bank0]
        self.banksB = [bank1, bank1]
        self.bankA = 0
        self.bankB = 0
        self.portA = portA
        self.portB = portB

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
        if addr == self.portA or addr == self.portB:
            return
        if 0x4000 <= addr <= 0xBFFF:
            return
        self.flat[addr] = val


def main():
    out, sym, text = build_test.assemble()
    bank0, bank1 = build_test.build_banks(out)
    mem = BankedMem(bank0, bank1)
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    cpu.sp = 0xF380

    WAIT_FOR_START = sym["WAIT_FOR_START"]
    steps = 0
    while cpu.pc != WAIT_FOR_START and steps < 300000:
        cpu.step()
        steps += 1
    print("reached WAIT_FOR_START after", steps, "steps")

    out_path = os.path.join(HERE, "title_screen.ppm")
    render_full(bytes(cpu.vram), out_path)
    print("rendered", out_path)


if __name__ == "__main__":
    main()
