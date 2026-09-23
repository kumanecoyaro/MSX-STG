"""Stage1 ジグザグ(Enemy2 A/B編隊)の縦ズレ維持の検証(2026-09-23、"ジグザグは
合体まで1セルずらしに変更したんだが合体すると整列してしまってる これは横並び
を回避する処理なので 合体後も1セルズレたまま移動させたい")。
実際のSPAWN_E2から編隊を出し、合体中(state0-5)・ドリフト(state6)・Z字退出
(state7)の全フレームで、1機目=基準-8/2機目=基準/3機目=基準+8の関係が
当たり判定用Y(U*_Y)と実際のスプライト属性Y(VRAM)の両方で保たれることを確認。
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from mini_z80asm import Assembler
from z80emu import Z80

text = open(os.path.join(os.path.dirname(__file__), '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
asm = Assembler(text); out = asm.assemble(); sym = asm.symtab
mem0 = bytearray(65536)
for a, v in out.items():
    mem0[a & 0xFFFF] = v & 0xFF
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def run_until_pc(z, pc, n=2000000):
    for _ in range(n):
        if z.pc == pc: return
        z.step()
    raise RuntimeError(hex(z.pc))
def call_routine(z, entry):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.pc = entry; run_until_pc(z, 0)

SPRATR = sym["SPRATR"] if "SPRATR" in sym else 0x1B00

for X in "AB":
    z = Z80(bytearray(mem0))
    z.pc = sym["INIT"]; run_until_pc(z, sym["MAINLOOP"]); z.wr(sym["SHIP_ENTRY_ACT"], 0)
    z.wr(sym["PLAYERX"], 32); z.wr(sym["PLAYERY"], 150)   # 下に居る -> 上向き退出
    if X == "B":
        z.wr(sym["E2A_ACTIVE"], 1)       # Aを使用中にしてBへ振り分けさせる
    z.wr(sym["SPAWN_BASEY_TABLE"], 80)
    z.h, z.l = 0, 0
    call_routine(z, sym["SPAWN_E2"])
    if X == "B":
        z.wr(sym["E2A_ACTIVE"], 0); z.wr(sym["E2A_SEQ_STATE"], 0xFF)
    seen = set(); ybad = []; vbad = []; lead = []; D = sym["TRAIL_DELAY"]
    for f in range(700):
        z.pc = sym["MAINLOOP"]; z.step(); run_until_pc(z, sym["MAINLOOP"])
        st = z.rd(sym[f"E2{X}_SEQ_STATE"])
        if st > 7 or not z.rd(sym[f"E2{X}_ACTIVE"]):
            break
        seen.add(st)
        y0, y1, y2 = (z.rd(sym[f"E2{X}_U{i}_Y"]) for i in range(3))
        if z.rd(sym[f"E2{X}_U0_STATE"]) == 1 and st <= 6:
            if not (y1 - y0 == 8 and y2 - y1 == 8):
                ybad.append((f, st, y0, y1, y2))
        if st == 6:
            vy = [z.vram[SPRATR + z.rd(sym[f"E2{X}_U{i}_SPRNUM"]) * 4] for i in range(3)]
            if vy != [y0, y1, y2]:
                vbad.append((f, vy, (y0, y1, y2)))
        if st == 7:
            # 退出中: 2機目=1機目のD フレーム前のY+8、3機目=2Dフレーム前のY+16
            # (軌跡をなぞりつつ1機目との縦ズレを保つ)。開始時の履歴は1機目の位置。
            lead.append(y0)
            k = len(lead) - 1
            def past(n):
                return lead[k - n] if k - n >= 0 else lead_start
            if not any(z.rd(sym[f"E2{X}_U{i}_EXITED"]) for i in range(3)):
                if not (y1 == (past(D) + 8) & 0xFF and y2 == (past(2 * D) + 16) & 0xFF):
                    ybad.append((f, st, y0, y1, y2))
        if st == 6:
            lead_start = y0
    check(f"{X}: formation passed through merge(0-5), drift(6) and exit(7): seen states {sorted(seen)}",
          {6, 7} <= seen)
    check(f"{X}: U0=base-8 / U1=base / U2=base+8 kept in merge, drift and exit (bad: {ybad[:3]})", not ybad)
    check(f"{X}: drift sprite attribute Y in VRAM matches each unit's own Y (bad: {vbad[:3]})", not vbad)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail); sys.exit(1)
