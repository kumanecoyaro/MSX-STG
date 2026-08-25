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
        # real VDP semantics: Y=208 stops the whole sprite list (early
        # terminator); any other Y>=208 (e.g. 209, this ROM's own
        # "hidden" convention - see INIT_SPRATR_CLR/UOE_HIDE/UBUS_HIDE)
        # just places that one sprite off-screen without affecting
        # later slots. Previously checked Y==0xD1(209) for the break,
        # which stopped rendering everything after the first ordinary
        # hidden slot - harmless while nothing used slots past the
        # enemy pool's own always-sometimes-hidden 4-6, but silently
        # hid every later sprite (bullet_gen.py's new U-type hw sprite
        # sprites at slots7-9) once something finally did.
        if y == 208:
            break
        if y >= 208:
            continue
        # real VDP quirk: the sprite attribute table's Y byte is the
        # actual display row MINUS 1 (this is how Y=255/-1 places a
        # sprite flush at row 0, with no other way to reach row 0) -
        # every sprite is really drawn 1 scanline lower than its own
        # stored Y. This script drew straight at the stored Y with no
        # +1, so every hw sprite in these renders sat 1px higher than
        # real hardware - caught by direct pixel comparison against a
        # real-hardware screenshot showing the tank sitting flush on
        # the ground while this script's own render showed it 1px
        # short. Y itself (and the 208 sentinel checks above, which
        # compare the raw stored byte) is unaffected - only where the
        # pattern data actually gets plotted needs the +1.
        color = vt.PALETTE[col & 0xF]
        y1 = (y + 1) & 0xFF  # wraps 255->0, same as real hardware's own top-row trick
        for qi, (dy, dx) in enumerate([(0, 0), (8, 0), (0, 8), (8, 8)]):
            pbase = 0x3800 + (pat + qi) * 8
            for ry in range(8):
                byte = vram[pbase + ry]
                for rx in range(8):
                    if (byte >> (7 - rx)) & 1:
                        py, px = y1 + dy + ry, x + dx + rx
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
    bank0, bank1 = build_test.build_banks(out)
    mem = build_test.BankedMem(bank0, bank1)
    cpu = Z80(mem)
    cpu.pc = sym["INIT"]
    mainloop = sym["MAINLOOP"]
    steps = 0
    while cpu.pc != mainloop and steps < 300000:
        cpu.step()
        steps += 1
    print("reached MAINLOOP after", steps, "steps")
    assert mem.bankB == 1, f"ASCII16 bank1 was never selected for page2 (bankB={mem.bankB}) - the boot-time trampoline switch didn't take effect"
    print("ASCII16 bank1 correctly selected for page2 by boot:", mem.switch_log)

    run_frames(cpu, mainloop, 5)
    render_full(bytes(cpu.vram), os.path.join(HERE, "combined0.ppm"))
    print("row20 sample:", list(cpu.vram[0x1800 + 20 * 32:0x1800 + 20 * 32 + 8]))

    run_frames(cpu, mainloop, 30 * 8)
    render_full(bytes(cpu.vram), os.path.join(HERE, "combined1.ppm"))
    print("row20 sample2:", list(cpu.vram[0x1800 + 20 * 32:0x1800 + 20 * 32 + 8]))


if __name__ == "__main__":
    main()
