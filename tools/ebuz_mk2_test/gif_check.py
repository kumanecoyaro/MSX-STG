"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20、Ebuz Mk2-1[閉状態]
が「揃うまで下にシフトする」方式で登場する版 - 新たに出現する行は常に
nt1に描画され、既存の行は毎ステップ1行ずつ下へ再描画[シフト]される
ベルトコンベア式の組み上がり。揃った後は中央へ移動→5門同時1斉発射)の
一連の流れを実時間(T-states換算)キャプション付きのアニメーションGIF
として可視化する。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80
from stage1_render_check import render_full
from PIL import Image, ImageDraw, ImageFont

Z_CLOCK_HZ = 3_579_545


def assemble():
    with open(os.path.join(HERE, "ebuz_mk2_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def run_until_pc(z, target_pc, max_instr=8_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def snapshot(z, label):
    ppm_path = os.path.join(HERE, "_gif_tmp.ppm")
    render_full(bytes(z.vram), ppm_path)
    img = Image.open(ppm_path).convert("RGB")
    img = img.resize((img.width * 3, img.height * 3), Image.NEAREST)
    canvas = Image.new("RGB", (img.width, img.height + 26), (20, 20, 20))
    canvas.paste(img, (0, 0))
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.load_default()
    elapsed_sec = z.tstates / Z_CLOCK_HZ
    draw.text((4, img.height + 4), f"t={elapsed_sec:6.2f}s  {label}", fill=(255, 255, 0), font=font)
    os.remove(ppm_path)
    return canvas


def main():
    mem0, sym = assemble()
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]
    z.tstates = 0

    frames = []
    durations = []

    def add(label, dur=500):
        frames.append(snapshot(z, label))
        durations.append(dur)

    run_until_pc(z, sym["EBUZ2_GUARD_DONE"])
    add("guard bands painted (row0=black, row20-23=white)", 1200)

    hold = sym["EBUZ2_ENTRY_STEP_HOLD_TICKS"]
    labels = [
        "shift 1/5: bottom row (3-wide) appears at nt1",
        "shift 2/5: prev row shifts down to nt2, next row (4-wide) at nt1",
        "shift 3/5: prev rows shift down, center row (5-wide) at nt1",
        "shift 4/5: prev rows shift down, next row (4-wide) at nt1",
        "shift 5/5: prev rows shift down, top row (3-wide) at nt1 - fully assembled, belt reaches nt1-nt5",
    ]
    for label in labels:
        for _ in range(hold):
            run_until_pc(z, sym["EBUZ2_TICK"])
            z.step()
        add(label, 500)

    run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_DONE"])
    add("descended to center (row9), still Mk2-1, no deformation", 700)

    run_until_pc(z, sym["EBUZ2_VOLLEY_DONE"])
    add("all 5 body rows fire simultaneously (Ebuz's 1 shot -> 5)", 900)

    for i in range(6):
        for _ in range(5):
            z.step()
            run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
        add("bullets flying straight", 350)

    for _ in range(40):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add("all bullets clipped off-screen - body untouched, step ends here", 1200)

    out_path = os.path.join(HERE, "ebuz_mk2_timeline.gif")
    frames[0].save(
        out_path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
    )
    print("timeline GIF written:", out_path, f"({len(frames)} frames)")


if __name__ == "__main__":
    main()
