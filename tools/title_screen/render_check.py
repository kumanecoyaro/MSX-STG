"""Renders the title screen's real VRAM content to a PPM for visual
confirmation (round43, "レンダリングで確認したほうがいいな"established
project convention). SCREEN2-specific (not stage2_combined's own
render_full, which is SCREEN1-only): each character code's pattern AND
color bytes live in one of 3 "thirds" (2048 bytes each, selected by
which 8-row band the character is in) and each of the 8 rows within a
pattern has its OWN fg/bg color byte (this is what makes Graphic2 a
near-bitmap mode) - there is no sprite rendering here since this title
bank always forces the sprite attribute table's first Y to the stop
marker (0D1h), so nothing would ever show anyway.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
import build_test  # noqa: E402 - this dir's own (title_screen) build_test.py

sys.path.insert(0, os.path.join(REPO, "tools"))
from z80emu import Z80  # noqa: E402

sys.path.insert(0, os.path.join(REPO, "tools", "stage2_terrain"))
import verify_terrain as vt  # noqa: E402 - reused only for its PALETTE table


def render_screen2(vram, path):
    W, H = 256, 192
    img = [[(0, 0, 0)] * W for _ in range(H)]
    for row in range(24):
        third = row // 8
        name_base = 0x1800 + row * 32
        for col in range(32):
            code = vram[name_base + col]
            pat_base = third * 2048 + code * 8
            col_base = 0x2000 + third * 2048 + code * 8
            for ry in range(8):
                byte = vram[pat_base + ry]
                color_byte = vram[col_base + ry]
                fg = vt.PALETTE[(color_byte >> 4) & 0xF]
                bg = vt.PALETTE[color_byte & 0xF]
                for rx in range(8):
                    v = (byte >> (7 - rx)) & 1
                    img[row * 8 + ry][col * 8 + rx] = fg if v else bg
    with open(path, "wb") as f:
        f.write(f"P6\n{W} {H}\n255\n".encode())
        for r in img:
            for px in r:
                f.write(bytes(px))


class BankedMem:
    def __init__(self, bank0, bank1, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = [bank0]
        import importlib.util
        _bgm_spec = importlib.util.spec_from_file_location(
            "bgm_bank_gen", os.path.join(REPO, "tools", "bgm_data", "bgm_bank_gen.py"))
        _bgm_mod = importlib.util.module_from_spec(_bgm_spec)
        _bgm_spec.loader.exec_module(_bgm_mod)
        bgm_bank, _ = _bgm_mod.build_bank()
        self.banksB = [bank1, bank1, bytearray(bgm_bank)]
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
        if addr == self.portA:
            self.bankA = val % len(self.banksA)
            return
        if addr == self.portB:
            self.bankB = val % len(self.banksB)
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
    render_screen2(bytes(cpu.vram), out_path)
    print("rendered", out_path)


if __name__ == "__main__":
    main()
