"""Runs the tank sprite test in z80emu.py, reads back the real sprite
attribute table + sprite pattern generator table from VRAM, and
composites what the hardware would actually display - not a
re-derivation of the Python source model.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import build_test  # noqa: E402
from z80emu import Z80  # noqa: E402

SPRATR = 0x1B00
SPRPAT = 0x3800
PALETTE = {
    0: (0, 0, 0), 1: (0, 0, 0), 2: (33, 200, 66), 3: (94, 220, 120),
    4: (84, 85, 237), 5: (125, 118, 252), 6: (212, 82, 77), 7: (66, 235, 245),
    8: (252, 85, 84), 9: (255, 121, 120), 10: (212, 193, 84), 11: (230, 206, 128),
    12: (33, 176, 59), 13: (201, 91, 186), 14: (204, 204, 204), 15: (255, 255, 255),
}


def render_sprites(vram, out_path, bg=(20, 20, 40)):
    img = [[bg] * 256 for _ in range(192)]
    for s in range(32):
        base = SPRATR + s * 4
        y, x, pat, col = vram[base], vram[base + 1], vram[base + 2], vram[base + 3]
        if y == 0xD1:
            break
        if y >= 208:
            continue
        color = PALETTE[col & 0xF]
        # 16x16: pat groups of 4 8x8 sub-patterns: TL,BL,TR,BR
        for qi, (dy, dx) in enumerate([(0, 0), (8, 0), (0, 8), (8, 8)]):
            pbase = SPRPAT + (pat + qi) * 8
            for ry in range(8):
                byte = vram[pbase + ry]
                for rx in range(8):
                    if (byte >> (7 - rx)) & 1:
                        py, px = y + dy + ry, x + dx + rx
                        if 0 <= py < 192 and 0 <= px < 256:
                            img[py][px] = color
    with open(out_path, "wb") as f:
        f.write(f"P6\n256 192\n255\n".encode())
        for row in img:
            for px in row:
                f.write(bytes(px))


def main():
    out, sym, text = build_test.assemble()
    mem = bytearray(65536)
    for a, b in out.items():
        mem[a] = b
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    mainloop = sym["MAINLOOP"]
    steps = 0
    while cpu.pc != mainloop and steps < 300000:
        cpu.step()
        steps += 1
    assert cpu.pc == mainloop

    out_dir = os.path.join(HERE, "frames")
    os.makedirs(out_dir, exist_ok=True)
    # sample once per pose (pose advances every 64 ticks/frames)
    for pose in range(4):
        for _ in range(2):  # run a couple frames into this pose
            cpu.step()
            s = 1
            while cpu.pc != mainloop and s < 300000:
                cpu.step()
                s += 1
        render_sprites(bytes(cpu.vram), os.path.join(out_dir, f"pose{pose}.ppm"))
        for _ in range(63):
            cpu.step()
            s = 1
            while cpu.pc != mainloop and s < 300000:
                cpu.step()
                s += 1
    print("rendered 4 poses to", out_dir)


if __name__ == "__main__":
    main()
