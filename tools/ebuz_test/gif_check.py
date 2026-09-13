"""tools/ebuz_test/ebuz_test.asmの発射タイミング/移動速度を、実時間
(T-states換算)キャプション付きのアニメーションGIFとして可視化する
(2026-09-13、実機フィードバック対応: "今は全て同時に発射してるし
下側の弾も出てない"への対応後、静止画3枚では"0.5秒待ってから発射"
"上下同時発射"というタイミング関係そのものが伝わらないと判断し、
経過時間を明示したGIFで直接確認できるようにした)。

各フレームは実際にz.tstates(Z80クロック消費量)をINITからの累積で
記録し、3.579545MHzの実クロックに換算した経過秒数をキャプションに
焼き込む - 見た目のタイミングが「本当にその通りの実時間で起きて
いるか」を、レンダリング画像そのものから確認できるようにするため。
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
    with open(os.path.join(HERE, "ebuz_test.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def run_until_pc(z, target_pc, max_instr=2_000_000):
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

    run_until_pc(z, sym["EBUZ_STATE1_BG_DONE"])
    frames.append(snapshot(z, "Ebuz1 appears, no bullet yet"))

    run_until_pc(z, sym["EBUZ_STATE1_DONE"])
    frames.append(snapshot(z, "bullet0 fired (0.5s after appearing)"))

    run_until_pc(z, sym["EBUZ_STATE2_BG_DONE"])
    frames.append(snapshot(z, "Ebuz2 forms, bullets1/2 not fired yet"))

    run_until_pc(z, sym["EBUZ_STATE2_DONE"])
    frames.append(snapshot(z, "bullets1+2 fired together (0.5s after forming)"))

    STEP_LAPS = 20
    cumulative = 0
    for _ in range(8):
        for _ in range(STEP_LAPS):
            z.step()
            run_until_pc(z, sym["EBUZ_FRAME_TICK"])
        cumulative += STEP_LAPS
        frames.append(snapshot(z, f"+{cumulative} frame-ticks: bullets moving/hiding"))

    out_path = os.path.join(HERE, "ebuz_bullets_timeline.gif")
    frames[0].save(
        out_path,
        save_all=True,
        append_images=frames[1:],
        duration=[900, 700, 900, 700] + [500] * (len(frames) - 4),
        loop=0,
    )
    print("timeline GIF written:", out_path, f"({len(frames)} frames)")


if __name__ == "__main__":
    main()
