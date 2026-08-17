import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))

# NOTE: import build_test (stage2_combined's OWN one) BEFORE adding the
# stage2_terrain/stage2_tank dirs to sys.path - both of those also have
# a same-named build_test.py, and inserting them at sys.path[0] first
# would shadow this directory's own module, silently assembling the
# wrong ROM (tank_test.asm/terrain_test.asm instead of
# combined_test.asm) with no error - exactly what happened here.
import build_test
from z80emu import Z80

sys.path.insert(0, os.path.join(HERE, "..", "stage2_terrain"))
sys.path.insert(0, os.path.join(HERE, "..", "stage2_tank"))
import verify_terrain as vt


def render_full(vram, path):
    W, H = 256, 192
    img = [[(0, 0, 0)] * W for _ in range(H)]
    for row in range(24):
        base = 0x1800 + row * 32
        for col in range(32):
            code = vram[base + col]
            pat = vram[code * 8:code * 8 + 8]
            color_byte = vram[0x2000 + (code // 8)]
            fg = vt.PALETTE[(color_byte >> 4) & 0xF]
            bg = vt.PALETTE[color_byte & 0xF]
            for ry in range(8):
                byte = pat[ry]
                for rx in range(8):
                    v = (byte >> (7 - rx)) & 1
                    img[row * 8 + ry][col * 8 + rx] = fg if v else bg
    for s in range(32):
        base = 0x1B00 + s * 4
        y, x, pat, col = vram[base], vram[base + 1], vram[base + 2], vram[base + 3]
        if y == 0xD1:
            break
        if y >= 208:
            continue
        color = vt.PALETTE[col & 0xF]
        for qi, (dy, dx) in enumerate([(0, 0), (8, 0), (0, 8), (8, 8)]):
            pbase = 0x3800 + (pat + qi) * 8
            for ry in range(8):
                byte = vram[pbase + ry]
                for rx in range(8):
                    if (byte >> (7 - rx)) & 1:
                        py, px = y + dy + ry, x + dx + rx
                        if 0 <= py < H and 0 <= px < W:
                            img[py][px] = color
    with open(path, "wb") as f:
        f.write(f"P6\n{W} {H}\n255\n".encode())
        for row in img:
            for px in row:
                f.write(bytes(px))


def run_frames(cpu, mainloop, n):
    for _ in range(n):
        cpu.step()
        s = 1
        while cpu.pc != mainloop and s < 300000:
            cpu.step()
            s += 1


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
    print("reached MAINLOOP after", steps, "steps")

    run_frames(cpu, mainloop, 5)
    render_full(bytes(cpu.vram), os.path.join(HERE, "combined0.ppm"))
    print("row20 sample:", list(cpu.vram[0x1800 + 20 * 32:0x1800 + 20 * 32 + 8]))

    run_frames(cpu, mainloop, 30 * 8)
    render_full(bytes(cpu.vram), os.path.join(HERE, "combined1.ppm"))
    print("row20 sample2:", list(cpu.vram[0x1800 + 20 * 32:0x1800 + 20 * 32 + 8]))


if __name__ == "__main__":
    main()
