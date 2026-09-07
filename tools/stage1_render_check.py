"""Stage1(src/CYBER SHMUP.asm)専用のVRAM→PNGレンダリングスクリプト。

Round55のCLAUDE.md保留事項("Stage1用render-checkスクリプトの新規作成が
最優先")への対応。tools/stage2_combined/render_check.pyをベースに、
Stage1のフラット64KBメモリモデル(BankedMemを使わない、
tools/verify_stage1_mission_screens.py等と同じ作法)向けに移植した。

使い方:
    python3 tools/stage1_render_check.py

VRAMの内容(SCREEN1のname table/pattern generator/color table/sprite
attribute table)をtools/stage2_combined/render_check.pyのrender_full()
と全く同じロジックでPNG化する(見た目のバグをテスト文字列だけでなく
実際に画像として確認するため、見た目/音に関わる修正は必ずこのスクリプト
等で視覚確認してから「直った」と報告すること - Round54/55の教訓)。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "stage2_terrain"))

from mini_z80asm import Assembler
from z80emu import Z80
import verify_terrain as vt

REPO_ROOT = os.path.join(HERE, "..")


def assemble():
    with open(os.path.join(REPO_ROOT, "src", "CYBER SHMUP.asm"), encoding="utf-8") as f:
        text = f.read()
    asm = Assembler(text)
    out = asm.assemble()
    sym = asm.symtab
    mem0 = bytearray(65536)
    for addr, val in out.items():
        mem0[addr & 0xFFFF] = val & 0xFF
    return mem0, sym


def render_full(vram, path):
    """tools/stage2_combined/render_check.pyのrender_full()と同一ロジック。"""
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
        if y == 208:
            break
        if y >= 208:
            continue
        color = vt.PALETTE[col & 0xF]
        y1 = (y + 1) & 0xFF
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


def run_until_pc(z, target_pc, max_instr=2_000_000):
    for _ in range(max_instr):
        if z.pc == target_pc:
            return
        z.step()
    raise RuntimeError(f"never reached PC {target_pc:04X}, stuck at {z.pc:04X}")


def main():
    mem0, sym = assemble()
    # MISSION_DELAY_3SECの実測約3秒(数百万命令)はレンダリング確認には
    # 不要なので、tools/verify_stage1_mission_screens.pyと同じ1バイト
    # パッチで短縮する(実ROMは無変更)。
    mem0[sym["MISSION_DELAY_3SEC"] + 1] = 1

    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]
    draw_mission_screen = sym["DRAW_MISSION_SCREEN"]
    mainloop = sym["MAINLOOP"]

    # (1) DRAW_MISSION_SCREEN呼び出し直後(Mission1が実際に表示される瞬間)
    run_until_pc(z, draw_mission_screen)
    # ルーチン本体を実行しRETで戻るところまで進める
    ret_pc = z.rd(z.sp) | (z.rd((z.sp + 1) & 0xFFFF) << 8)
    run_until_pc(z, ret_pc, max_instr=200_000)
    out_path = os.path.join(HERE, "stage1_mission1.ppm")
    render_full(bytes(z.vram), out_path)
    print("MISSION1 screen rendered:", out_path)
    print("message region (row12,col11-19):",
          [z.vram[12 * 32 + 11 + 0x1800 + i] for i in range(9)])

    # (2) MAINLOOP到達後(ステージ本編の初期画面)
    run_until_pc(z, mainloop)
    out_path2 = os.path.join(HERE, "stage1_mainloop.ppm")
    render_full(bytes(z.vram), out_path2)
    print("MAINLOOP-entry screen rendered:", out_path2)


if __name__ == "__main__":
    main()
