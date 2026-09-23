"""Stage1 EbuzII: 中央レーザー発射中に撃破されてもレーザーが画面に残らない
(2026-09-23、実機報告"EbuzIIを倒す直前に中央のレーザーが発射されていると爆発
処理に即移行してレーザーが消えないままになってる"→"消去するのではなく本来の
処理で終了するように")。撃破後もレーザーは一括消去されず、本来の保持→1フレーム
1ユニットの引っ込めで終わり、その完了までEbuzIIが無効化されないことを、実際の
MAINLOOPを回して確認する。
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

def frame(z):
    z.pc = sym['MAINLOOP']; z.step(); run_until_pc(z, sym['MAINLOOP'])
def n_laser(z):
    return sum(1 for c in laser_row_cells(z) if c in (L_CODE, R_CODE))

for label, retract_steps in (("hold (just fired, full laser)", 0), ("mid-retract (4 units already pulled back)", 4)):
    z = fresh()
    call(z, 'EBUZ2_FIRE_LASER')
    check(f"{label}: laser drawn across cols 1-22 after EBUZ2_FIRE_LASER",
          laser_row_cells(z) == [L_CODE, R_CODE] * 11)
    if retract_steps:
        z.wr(sym['EBUZ2_LASER_HOLD'], 0)
        for _ in range(retract_steps): call(z, 'EBUZ2_UPDATE_LASER')
    before = n_laser(z)
    call(z, 'EBUZ2_TRIGGER_DEFEAT')
    check(f"{label}: defeat does NOT erase the laser at once (still {n_laser(z)} of {before} cells, LASER_ACT kept)",
          n_laser(z) == before and z.rd(sym['EBUZ2_LASER_ACT']) == 1)
    counts = []; act_while_laser = True; spawned_early = False
    for f in range(600):
        frame(z)
        counts.append(n_laser(z))
        if z.rd(sym['EBUZ2_LASER_ACT']) and not z.rd(sym['EBUZ2_ACT']):
            act_while_laser = False
        if z.rd(sym['EBUZ2_LASER_ACT']) and z.rd(sym['BOSS_STATE']):
            spawned_early = True
        if not z.rd(sym['EBUZ2_ACT']) and not z.rd(sym['EBUZ2_LASER_ACT']):
            break
    steps = [counts[i - 1] - counts[i] for i in range(1, len(counts)) if counts[i - 1] != counts[i]]
    check(f"{label}: after defeat the laser retracts by the normal process, one unit (2 cells) per frame",
          steps and all(d == 2 for d in steps) and counts[-1] == 0)
    check(f"{label}: EbuzII is not deactivated (and the boss does not spawn) while the laser is still active",
          act_while_laser and not spawned_early)
    check(f"{label}: finally no laser cell remains and EBUZ2_ACT=0 (defeat completed)",
          all(c == BLANK for c in laser_row_cells(z)) and z.rd(sym['EBUZ2_ACT']) == 0)

z = fresh()
call(z, 'EBUZ2_TRIGGER_DEFEAT')
check("no laser active: defeat does not touch the laser path (LASER_ACT stays 0)", z.rd(sym['EBUZ2_LASER_ACT']) == 0)

# 爆発キューと撃破後の待ちが先に終わる場合でも(安全網)、レーザーが引っ込み
# 終わるまでEBUZ2_ACTを落とさない(落とすと更新が止まり取り残される)
z = fresh()
call(z, 'EBUZ2_FIRE_LASER')
call(z, 'EBUZ2_TRIGGER_DEFEAT')
z.wr(sym['EBUZ_EXPL_QUEUE_COUNT'], 0); z.wr(sym['EBUZ2_POST_DEFEAT_WAIT'], 0)
early = False
for f in range(300):
    frame(z)
    if z.rd(sym['EBUZ2_LASER_ACT']) and not z.rd(sym['EBUZ2_ACT']):
        early = True
    if not z.rd(sym['EBUZ2_ACT']):
        break
check("explosions finished early: EbuzII still waits for the laser to retract before deactivating",
      not early and all(c == BLANK for c in laser_row_cells(z)))

print(f"\n{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILURES:", fail); sys.exit(1)
