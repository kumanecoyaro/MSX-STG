"""Runs the Stage-2 terrain scroller test ROM in z80emu.py, dumps the
real VRAM (name table + pattern generator) at several tick counts, and
renders it to a PNG using the actual on-screen pattern bytes - so what
gets shown is what the emulated hardware actually drew, not a
re-derivation of the Python model.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(REPO, "tools"))

import build_test  # noqa: E402
from z80emu import Z80  # noqa: E402

NAME_BASE = 0x1800
PAT_BASE = 0x0000
COLOR_BASE = 0x2000
ROWS = list(range(16, 24))  # a few sky rows above the ground band too

# Approximate TMS9918/MSX1 16-color palette (index -> RGB)
PALETTE = {
    0: (0, 0, 0), 1: (0, 0, 0), 2: (33, 200, 66), 3: (94, 220, 120),
    4: (84, 85, 237), 5: (125, 118, 252), 6: (212, 82, 77), 7: (66, 235, 245),
    8: (252, 85, 84), 9: (255, 121, 120), 10: (212, 193, 84), 11: (230, 206, 128),
    12: (33, 176, 59), 13: (201, 91, 186), 14: (204, 204, 204), 15: (255, 255, 255),
}


def run_and_dump(n_frames, sample_ticks):
    out, sym, text = build_test.assemble()
    mem = bytearray(65536)
    for a, b in out.items():
        mem[a] = b

    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    mainloop = sym["MAINLOOP"]

    # step through INIT to the first MAINLOOP entry
    steps = 0
    while cpu.pc != mainloop and steps < 200000:
        cpu.step()
        steps += 1
    assert cpu.pc == mainloop, f"never reached MAINLOOP (stuck at {cpu.pc:04X}h)"

    samples = {}
    frame = 0
    want = sorted(sample_ticks)
    wi = 0
    while wi < len(want) and frame <= max(want):
        if frame == want[wi]:
            samples[frame] = bytes(cpu.vram)
            wi += 1
        # run exactly one MAINLOOP iteration (until PC returns to MAINLOOP)
        cpu.step()
        s = 1
        while cpu.pc != mainloop and s < 200000:
            cpu.step()
            s += 1
        frame += 1
    return samples, mem


def render_vram(vram, out_path, scale=3):
    def get_pattern(code):
        return vram[PAT_BASE + code * 8: PAT_BASE + code * 8 + 8]

    def get_colors(code):
        byte = vram[COLOR_BASE + (code // 8)]
        fg = (byte >> 4) & 0xF
        bg = byte & 0xF
        return PALETTE[fg], PALETTE[bg]

    W = 32 * 8
    H = len(ROWS) * 8
    img = [[(0, 0, 0)] * W for _ in range(H)]
    for ri, row in enumerate(ROWS):
        base = NAME_BASE + row * 32
        for col in range(32):
            code = vram[base + col]
            pat = get_pattern(code)
            fg_rgb, bg_rgb = get_colors(code)
            for ry in range(8):
                byte = pat[ry]
                for rx in range(8):
                    v = (byte >> (7 - rx)) & 1
                    img[ri * 8 + ry][col * 8 + rx] = fg_rgb if v else bg_rgb

    with open(out_path, "wb") as f:
        f.write(f"P6\n{W} {H}\n255\n".encode())
        for row in img:
            for px in row:
                f.write(bytes(px))


def main():
    # sample across the full 256-cell track's worth of MAINLOOP frames
    # (8 frames per cell-advance) plus a burst of consecutive frames
    # around the very first climb transition to check smooth blending.
    milestones = [0, 1, 2, 3, 4, 5, 6, 7, 8]  # first 9 frames: watch phase 0-7 then wrap
    around_climb = list(range(24 * 8 - 4, 24 * 8 + 20))  # near cell 24 (first climb, k=24)
    long_run = list(range(0, 256 * 8, 64))  # coarse sweep across the whole track
    sample_ticks = sorted(set(milestones + around_climb + long_run))
    samples, mem = run_and_dump(None, sample_ticks)

    out_dir = os.path.join(HERE, "frames")
    os.makedirs(out_dir, exist_ok=True)
    for f, vram in samples.items():
        render_vram(vram, os.path.join(out_dir, f"frame_{f:04d}.ppm"))
    print(f"rendered {len(samples)} frames to {out_dir}")
    return samples


if __name__ == "__main__":
    main()
