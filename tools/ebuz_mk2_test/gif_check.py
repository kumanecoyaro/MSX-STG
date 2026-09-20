"""tools/ebuz_mk2_test/ebuz_mk2_test.asm(2026-09-20、登場[row1に一度に
出現、成長演出なし]→中央まで剛体のまま平行移動→5門同時1斉発射→以後は
静止)の一連の流れを、実時間(T-states換算)キャプション付きの
アニメーションGIFとして可視化する。tools/ebuz_test/gif_check.pyと
全く同じ作法(render_full()の出力を3倍拡大+タイムスタンプ焼き込み)。
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
    add("guard bands painted (row0=black, row20-23=white) - permanent, never touched again", 1200)

    run_until_pc(z, sym["EBUZ2_ENTRY_SPAWN_DONE"])
    add("spawn: full 7-row body appears at row1 (from above) - no growth/deform animation", 900)

    while z.mem[sym["EBUZ2_BODY_ROW"]] != sym["EBUZ2_ENTRY_TARGET_ROW_TOP"]:
        run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_LOOP"])
        z.step()
        run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_LOOP"])
        add(f"moving down as a rigid body: row_top={z.mem[sym['EBUZ2_BODY_ROW']]}", 350)

    run_until_pc(z, sym["EBUZ2_ENTRY_MOVE_DONE"])
    add("reached center (row_top=9), shape unchanged throughout", 700)

    run_until_pc(z, sym["EBUZ2_VOLLEY_DONE"])
    add("all 5 ports fire simultaneously (one shot each, no sequencing, no repeat)", 900)

    for _ in range(80):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add("80 ticks later: body untouched, no oscillation, no repeat fire - step ends here", 1200)

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
