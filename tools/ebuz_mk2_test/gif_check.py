"""tools/ebuz_mk2_test/ebuz_mk2_test.asmの一連の流れ(state1本体→
中央発射管から1発だけ発射→state1→state2への瞬間移動[Row9]→
中央→内側(上下2門)→外側(上下2門)の3ステップ無限ループ発射しながら
本体がRow1-16を連続的に上下する)を、実時間(T-states換算)キャプション
付きのアニメーションGIFとして可視化する。tools/ebuz_test/gif_check.py
と全く同じ作法(render_full()の出力を3倍拡大+タイムスタンプ焼き込み)。

(2026-09-20全面訂正: 旧「開幕3連ボレー」「上下キャップ発射」「外側/
内側交互ペア」「離散3ポジションoscillation」は全て撤回され、
「5門・中央のみ→中央/内側/外側巡回・連続oscillation」設計に置き
換わった。以下のラベル文言・チェックポイントもそれに合わせて全面
更新。)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))
sys.path.insert(0, os.path.join(REPO_ROOT, "tools", "stage2_terrain"))

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

    run_until_pc(z, sym["EBUZ2_STATE1_BG_DONE"])
    add("Mk2 state1 body appears (5 rows, fixed nt row3-7), about to hold", 900)

    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])
    add("release: CENTER tube fires 1 shot only (\"最初はセンター\")", 700)

    # state1->state2 is an instantaneous relocation (old row3-7 erased,
    # body reappears at Row9) - no wait in between.
    run_until_pc(z, sym["EBUZ2_STATE2_BG_DONE"])
    add("state1->state2: body relocates to Row9 (\"上から来てRow9\")", 900)

    for _ in range(6):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add("center shot still flying - Y fixed at fire-time row, unaffected by relocation", 700)

    run_until_pc(z, sym["EBUZ2_STATE2_DONE"])
    add("sequential fire (center->inner->outer) + oscillation activated", 700)

    for label in [
        "step: CENTER fires",
        "step: INNER pair fires (top+bottom)",
        "step: OUTER pair fires (top+bottom)",
        "step: back to CENTER (loop)",
    ]:
        for _ in range(sym["EBUZ2_FIRE_INTERVAL"]):
            z.step()
            run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
        add(label, 500)

    for _ in range(200):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add(f"continuous sweep in progress (OSC_ROW={z.mem[sym['EBUZ2_OSC_ROW']]})", 700)

    for _ in range(200):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add(f"continuous sweep (OSC_ROW={z.mem[sym['EBUZ2_OSC_ROW']]}) - bullets Y varies per shot", 700)

    for _ in range(400):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add(f"continuous sweep (OSC_ROW={z.mem[sym['EBUZ2_OSC_ROW']]})", 900)

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
