"""Stage1 EbuzII: 中央レーザー発射中に撃破されてもレーザーが画面に残らない
(2026-09-23、実機報告"EbuzIIを倒す直前に中央のレーザーが発射されていると爆発
処理に即移行してレーザーが消えないままになってる")。保持中と引っ込め途中の
両方で撃破し、レーザーの行(列1-22)が全部BLANKCODEに戻ることを確認する。
"""
import sys, os, json
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, 'bgm_data'))
from mini_z80asm import Assembler
from z80emu import Z80
import patch_ebuz2_mk2 as pe
text = open(os.path.join(HERE, '..', 'src', 'CYBER SHMUP.asm'), encoding='utf-8').read()
asm = Assembler(text); out = asm.assemble(); sym = asm.symtab
mem0 = bytearray(65536)
for a, v in out.items():
    mem0[a & 0xFFFF] = v & 0xFF
bank = open(os.path.join(HERE, 'bgm_data', 'bgm_bank.bin'), 'rb').read()
lay = json.load(open(os.path.join(HERE, 'bgm_data', 'bgm_layout.json')))
ok, fail = [], []
def check(label, cond):
    (ok if cond else fail).append(label); print(("PASS " if cond else "FAIL "), label)
def run_until_pc(z, pc, n=3000000):
    for _ in range(n):
        if z.pc == pc: return
        z.step()
    raise RuntimeError(hex(z.pc))
def call(z, name):
    z.sp = 0xF000; z.wr(0xF000, 0); z.wr(0xF001, 0); z.pc = sym[name]; run_until_pc(z, 0)
def fresh():
    z = Z80(bytearray(mem0))
    off = lay['EBUZ2_MK2_CHARDATA']['bank_offset']
    for i in range(lay['EBUZ2_MK2_CHARDATA']['len']):
        z.wr(sym['EBUZ2_BLANK5'] + i, bank[off + i])     # Titleが事前コピーするデータ
    for name, data in zip(('EBUZ2_SCRIPT_TABLE', 'EBUZ2_ALTLOOP_TABLE', 'EBUZ2_STOPSEQ_TABLE'), pe.build_tables(sym)):
        for i, b in enumerate(data): z.wr(sym[name] + i, b)
    z.pc = sym['INIT']; run_until_pc(z, sym['MAINLOOP']); z.wr(sym['SHIP_ENTRY_ACT'], 0)
    z.wr(sym['EBUZ2_ACT'], 1); z.wr(sym['EBUZ2_PHASE'], 1); z.wr(sym['EBUZ2_ROW_CUR'], 5)
    return z
L_CODE, R_CODE, BLANK = sym['EBUZ2_LASER_L_CODE'], sym['EBUZ2_LASER_R_CODE'], sym['BLANKCODE']
def laser_row_cells(z):
    row = z.rd(sym['EBUZ2_LASER_ROW'])
    return [z.vram[0x1800 + row * 32 + c] for c in range(1, 23)]

for label, retract_steps in (("hold (just fired, full laser)", 0), ("mid-retract (4 units already pulled back)", 4)):
    z = fresh()
    call(z, 'EBUZ2_FIRE_LASER')
    cells = laser_row_cells(z)
    check(f"{label}: laser drawn across cols 1-22 after EBUZ2_FIRE_LASER",
          cells == [L_CODE, R_CODE] * 11)
    if retract_steps:
        z.wr(sym['EBUZ2_LASER_HOLD'], 0)
        for _ in range(retract_steps): call(z, 'EBUZ2_UPDATE_LASER')
        cells = laser_row_cells(z)
        check(f"{label}: some laser cells remain before defeat", any(c in (L_CODE, R_CODE) for c in cells))
    call(z, 'EBUZ2_TRIGGER_DEFEAT')
    cells = laser_row_cells(z)
    check(f"{label}: after defeat no laser cell remains on the row (all BLANKCODE)", all(c == BLANK for c in cells))
    check(f"{label}: EBUZ2_LASER_ACT cleared and PHASE=2 (defeat)", z.rd(sym['EBUZ2_LASER_ACT']) == 0 and z.rd(sym['EBUZ2_PHASE']) == 2)

z = fresh()
call(z, 'EBUZ2_TRIGGER_DEFEAT')
check("no laser active: defeat does not touch the laser path (LASER_ACT stays 0)", z.rd(sym['EBUZ2_LASER_ACT']) == 0)

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail); sys.exit(1)
