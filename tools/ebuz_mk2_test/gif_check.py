"""tools/ebuz_mk2_test/ebuz_mk2_test.asmの一連の流れ(state1本体→
開幕ボレー[3本の直進BGレーン弾]の一斉発射→state2遷移→上下往復
[oscillation]しながらの継続発射)を、実時間(T-states換算)キャプション
付きのアニメーションGIFとして可視化する。tools/ebuz_test/gif_check.py
と全く同じ作法(render_full()の出力を3倍拡大+タイムスタンプ焼き込み)。

(2026-09-19訂正: 当初はHWスプライトの斜め速度による"くの字3連"
だったが、ユーザーから「斜め移動はしないぞ」と訂正され、無印Ebuzと
同じ固定行・1ティック1列のBGレーン弾3本[発射開始列だけが行ごとに
異なる]へ置き換え済み。以下のラベル文言もそれに合わせて更新した。)
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


def run_until_pc(z, target_pc, max_instr=4_000_000):
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
    add("Mk2 state1 body appears (5 rows), about to hold", 900)

    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])
    add("release: opening volley (3 straight BG-lane bullets) just fired", 500)

    # NOTE: state1->state2 is an immediate (no-wait) BG transform, so the
    # PC reaches EBUZ2_STATE2_BG_DONE right away and then enters the
    # post-transform hold loop (where EBUZ2_WAIT_TICK_DONE actually
    # recurs). Reaching STATE2_BG_DONE must therefore come BEFORE the
    # "let a few ticks pass" loop below, not after (matches the order
    # used in render_check.py; an earlier draft of this script had this
    # backwards and hung waiting for a PC that had already been passed).
    run_until_pc(z, sym["EBUZ2_STATE2_BG_DONE"])
    add("state1->state2 BG transform (no extra wait) - turret revealed, volley still flying", 900)

    for _ in range(6):
        z.step()
        run_until_pc(z, sym["EBUZ2_WAIT_TICK_DONE"])
    add("volley mid-flight - each lane purely horizontal, staggered start cols form the wedge", 900)

    for _ in range(20):
        z.step()
        run_until_pc(z, sym["EBUZ2_WAIT_TICK_DONE"])
    add("state2 pre-activation hold, volley bullets continuing off-screen", 700)

    run_until_pc(z, sym["EBUZ2_STATE2_DONE"])
    add("continuous top/bottom fire + oscillation activated", 700)

    for label in [
        "+1 tick: top lane fires",
        "+2 ticks",
        "+3 ticks: bottom lane fires",
        "+4 ticks",
    ]:
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
        add(label, 400)

    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    add("oscillation: body shifted UP by 1 row (fire lanes stay fixed)", 900)

    for _ in range(6):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add("UP position, continuous fire keeps alternating", 700)

    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    add("oscillation: shifted back to BASE position", 700)

    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    add("oscillation: body shifted DOWN by 1 row", 900)

    for _ in range(6):
        z.step()
        run_until_pc(z, sym["EBUZ2_FRAME_TICK"])
    add("DOWN position, continuous fire keeps alternating", 700)

    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    add("oscillation: back to BASE - one full up/down cycle complete", 900)

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
