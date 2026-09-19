"""tools/ebuz_mk2_test/ebuz_mk2_test.asm のVRAM->PNGレンダリングスクリプト。
tools/stage1_render_check.pyのrender_full()を使い回す
(tools/ebuz_test/render_check.pyと同じ作法)。state1(登場直後)・
state1解放直後(開幕ボレー3発発射、2026-09-19訂正でHWスプライトの
斜めくの字からBGレーン直進3本へ置き換え済み)・state2(変化後)・
oscillation(up/downそれぞれ)のスナップショットをPNGで保存する。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO_ROOT, "tools"))

from mini_z80asm import Assembler
from z80emu import Z80
from stage1_render_check import render_full  # reuse identical rendering logic


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


def volley_dump(z, sym):
    """3レーンの[ACTIVE,現在列]をRAMから直接読む(2026-09-19訂正で
    HWスプライトのSPRATRからBGレーンのRAM変数[EBUZ2_VOLLEYn_ACTIVE/
    COLCUR]へ移行したため、sprite_dumpの代わりにこちらを使う)。"""
    out = []
    for i in range(3):
        act = z.mem[sym[f"EBUZ2_VOLLEY{i}_ACTIVE"]]
        col = z.mem[sym[f"EBUZ2_VOLLEY{i}_COLCUR"]]
        out.append((act, col))
    return out


def main():
    mem0, sym = assemble()
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]

    run_until_pc(z, sym["EBUZ2_STATE1_BG_DONE"])
    p1 = os.path.join(HERE, "ebuz_mk2_state1.ppm")
    render_full(bytes(z.vram), p1)
    print("state1 rendered:", p1)

    run_until_pc(z, sym["EBUZ2_STATE1_DONE"])
    p2 = os.path.join(HERE, "ebuz_mk2_volley_fired.ppm")
    render_full(bytes(z.vram), p2)
    print("opening volley (3 straight BG-lane bullets) just fired:", p2)
    for i, (act, col) in enumerate(volley_dump(z, sym)):
        print(f"  lane{i} [active,col]:", act, col)

    # state1->state2 itself has no wait (immediate BG transform), so jump
    # straight there; the volley bullets keep flying independently of this.
    run_until_pc(z, sym["EBUZ2_STATE2_BG_DONE"])
    p3 = os.path.join(HERE, "ebuz_mk2_state2.ppm")
    render_full(bytes(z.vram), p3)
    print("state2 (base position) rendered:", p3)

    # let the volley bullets travel a bit during the pre-activation hold
    # (EBUZ2_WAIT_TICK_DONE is the per-tick marker inside that hold loop,
    # same idiom as tools/ebuz_test/render_check.py's EBUZ_FRAME_TICK loop).
    for _ in range(8):
        z.step()
        run_until_pc(z, sym["EBUZ2_WAIT_TICK_DONE"])
    p2b = os.path.join(HERE, "ebuz_mk2_volley_flying.ppm")
    render_full(bytes(z.vram), p2b)
    print("volley mid-flight (over the freshly-formed state2 body):", p2b)
    for i, (act, col) in enumerate(volley_dump(z, sym)):
        print(f"  lane{i} [active,col]:", act, col)

    run_until_pc(z, sym["EBUZ2_STATE2_DONE"])
    p4 = os.path.join(HERE, "ebuz_mk2_state2_active.ppm")
    render_full(bytes(z.vram), p4)
    print("state2, continuous fire + oscillation activated:", p4)

    # advance until the first oscillation shift (base->up) actually happens.
    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    p5 = os.path.join(HERE, "ebuz_mk2_osc_up.ppm")
    render_full(bytes(z.vram), p5)
    print("oscillation: shifted to UP position:", p5)

    # advance to the next shift (up->base) then the one after (base->down).
    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    run_until_pc(z, sym["EBUZ2_OSC_SHIFT_DONE"])
    p6 = os.path.join(HERE, "ebuz_mk2_osc_down.ppm")
    render_full(bytes(z.vram), p6)
    print("oscillation: shifted to DOWN position:", p6)


if __name__ == "__main__":
    main()
