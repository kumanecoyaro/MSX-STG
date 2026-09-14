"""tools/ebuz_test/ebuz_test.asmの発射タイミング/移動速度/上下弾の
継続交互発射+反動アニメーションを、実時間(T-states換算)キャプション
付きのアニメーションGIFとして可視化する(2026-09-13、実機フィード
バック対応: "今は全て同時に発射してるし下側の弾も出てない"への対応後、
静止画3枚では"0.5秒待ってから発射""上下同時発射"というタイミング
関係そのものが伝わらないと判断し、経過時間を明示したGIFで直接確認
できるようにした)。その後(その7)"上下弾は交互に撃ち続けろ 2フレ
交代...反動"対応でstate2以降を継続交互発射+反動の可視化に更新、
さらに(その8)"撃った弾戻して交互に発射してどうすんだバカ 撃った弾は
画面外に消えるまで戻さねえ""弾を表示してホールドだって言っただろが"
対応でbullet0の表示→ホールド→飛行の流れと、弾が画面端に到達した
瞬間だけ再発射される様子を可視化。

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
    durations = []

    def add(label, dur=500):
        frames.append(snapshot(z, label))
        durations.append(dur)

    # --- bullet0: "弾を表示してホールド" (2026-09-13追記その8) ---
    run_until_pc(z, sym["EBUZ_STATE1_BG_DONE"])
    add("Ebuz1 appears, about to display bullet0", 900)
    z.step()
    run_until_pc(z, sym["EBUZ_WAIT_TICK_DONE"])
    add("bullet0 DISPLAYED immediately, now HOLDING (static)", 900)
    for _ in range(8):
        z.step()
        run_until_pc(z, sym["EBUZ_WAIT_TICK_DONE"])
    add("bullet0 still holding, unmoved (tick10 of 10)", 700)
    run_until_pc(z, sym["EBUZ_STATE1_DONE"])
    add("hold ends -> immediately transforms into Ebuz2 (no extra wait)", 700)

    run_until_pc(z, sym["EBUZ_STATE2_BG_DONE"])
    add("Ebuz2 forms, top/bottom fire not active yet", 900)

    run_until_pc(z, sym["EBUZ_STATE2_DONE"])
    add("continuous fire activated (after 30-tick pre-activation hold)", 700)

    # close-up on the first cycle to show the alternating fire + recoil
    # (2026-09-13追記その7/その8: "上下弾は交互に撃ち続けろ 2フレ交代
    # ...反動...撃った弾は画面外に消えるまで戻さねえ")
    for label in [
        "+1 tick: TOP fires (recoil shown)",
        "+2 ticks: TOP's recoil reverts, now flying",
        "+3 ticks: BOTTOM fires (recoil shown)",
        "+4 ticks: BOTTOM's recoil reverts, now flying",
    ]:
        z.step()
        run_until_pc(z, sym["EBUZ_FRAME_TICK"])
        add(label)

    for _ in range(20):
        z.step()
        run_until_pc(z, sym["EBUZ_FRAME_TICK"])
    add("+24 ticks: both bullets mid-flight, never reset early")

    # top reaches the edge at tick25 (192/8=24 ticks after its tick1 launch)
    # and must refire the INSTANT it's gone - not before (this is the exact
    # bug that was reported: "撃った弾戻して交互に発射してどうすんだバカ
    # 撃った弾は画面外に消えるまで戻さねえ").
    for _ in range(4):
        z.step()
        run_until_pc(z, sym["EBUZ_FRAME_TICK"])
    add("+28 ticks: TOP just reached the edge and refired immediately")

    for _ in range(4):
        z.step()
        run_until_pc(z, sym["EBUZ_FRAME_TICK"])
    add("+32 ticks: BOTTOM also reached the edge and refired (2-tick phase kept)")

    out_path = os.path.join(HERE, "ebuz_bullets_timeline.gif")
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
