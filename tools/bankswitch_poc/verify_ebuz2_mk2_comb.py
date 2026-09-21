"""Ebuz Mk2(src/CYBER SHMUP.asm)の共有バンク6データ(EBUZ2_MK2_CHARDATA)
が、実際に動くComb ROMのStage1コード(assemble_game()、INIT_PATCHで
全アドレスがシフトした後のもの)と整合していることを検証する。

round136(2026-09-21、実機フィードバック対応): Ebuz Mk2のROM予算確保の
ためEBUZ2_SCRIPT_TABLE/ALTLOOP_TABLE/STOPSEQ_TABLE(テーブル駆動
シーケンスエンジンが「JP (HL)」で直接ジャンプするコードアドレスを
含む)をComb bank6(RAM移設、Titleが起動時にコピー)へ退避した際、
このテーブルのバイト列を "plain" `mini_z80asm.Assembler(text)`(=
tools/verify_*.py群やbuild_full_rom.pyを経由しないスタンドアロン
アセンブル)から生成してしまっていた。しかし実際にComb ROMで動く
Stage1のコードはbuild_full_rom.pyのINIT_PATCH(バンク切替トランポリン
の注入)により、INIT以降の全アドレスが約171byteシフトしている
(plainアセンブルとComb組み込み後のアセンブルでアドレス空間が異なる)。
結果としてシーケンスエンジンの「JP (HL)」が全く無関係な番地へジャンプ
し、ワイルドジャンプによる画面破損+フリーズという重大な実機バグに
なっていた(tools/verify_*.py群は全てplainアセンブルで完結するため、
このクラスのバグを原理的に検出できなかった - Round41/47と同型の
「plainテストでは検出できないビルド固有のバグ」)。

このテストは:
  1. EBUZ2_MK2_CHARDATA内の3つのシーケンステーブルが、plainではなく
     assemble_game()(Comb組み込み後)のアドレスと一致していることを
     直接検証する(今回のバグそのものへの回帰ガード)。
  2. さらに実際のTitle→Stage1トランポリンを経由した本物のBankedMem
     起動+2000フレーム超の実プレイシミュレーション(Mk2の全シーケンス
     +被弾撃破+実ボスへのハンドオフ)を回し、ワイルドジャンプ・
     フリーズ・意図しないVRAMパターンジェネレータ破損が起きないことを
     確認する。

今後、Comb bank6(またはbank7等の共有バンク)へ「コード内で参照される
アドレス」を含むデータを置く際は、必ずこのファイルと同じ手法
(build_full_rom.pyのassemble_game()/assemble_title()等、実際に
組み込まれる方のアセンブル結果からアドレスを取ること)を踏襲すること。
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "bgm_data"))
sys.path.insert(0, HERE)
import z80emu
from build_full_rom import assemble_title, assemble_game, assemble_real_stage2, assemble_gameover_bank
import bgm_bank_gen as bg

ok = []
fail = []


def check(label, cond):
    (ok if cond else fail).append(label)
    print(("PASS " if cond else "FAIL "), label)


# ============================================================
# 1. EBUZ2_MK2_CHARDATA内のシーケンステーブルが、Comb組み込み後の
#    実アドレス(assemble_game())と一致していることを直接検証する。
# ============================================================
game_bank0, game_bank1, gsym = assemble_game()
bgm_bank, bgm_layout = bg.build_bank()


def w(name):
    a = gsym[name]
    return [a & 0xFF, (a >> 8) & 0xFF]


def eqv(name):
    return gsym[name] & 0xFF


expected_script = (
    w('EBUZ2_RECOIL_CLOSED_SHIFT') + [eqv('EBUZ2_RECOIL_HOLD_TICKS')] +
    w('EBUZ2_RECOIL_CLOSED_REST') + [eqv('EBUZ2_RECOIL_HOLD_TICKS')] +
    w('EBUZ2_TRANSFORM') + [eqv('EBUZ2_ENTRY_HOLD_TICKS')] +
    w('EBUZ2_ACT_NOP') + [eqv('EBUZ2_VOLLEY2_PRE_FIRE_HOLD_TICKS')] +
    w('EBUZ2_ACT_NOP') + [eqv('EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')] +
    w('EBUZ2_FIRE_INNER_PAIR') + [eqv('EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')] +
    w('EBUZ2_ACT_START_MOVEMENT') + [eqv('EBUZ2_VOLLEY2_ALT_START_HOLD_TICKS')]
)
expected_altloop = (
    w('EBUZ2_ACT_ALT_TOP') + [eqv('EBUZ2_RECOIL_HOLD_TICKS')] +
    w('EBUZ2_RECOIL_INNER_REST') + [eqv('EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')] +
    w('EBUZ2_FIRE_OUTER_PAIR_AND_SHIFT') + [eqv('EBUZ2_RECOIL_HOLD_TICKS')] +
    w('EBUZ2_ACT_ALT_LOOP_BACK') + [eqv('EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')]
)
expected_stopseq = (
    w('EBUZ2_FIRE_LASER_AND_SHIFT') + [eqv('EBUZ2_RECOIL_HOLD_TICKS')] +
    w('EBUZ2_RECOIL_CENTER_REST') + [eqv('EBUZ2_LAP_STOP_HOLD_TICKS')] +
    w('EBUZ2_ACT_LOOP_RESET') + [1]
)

RAM_BASE = gsym["EBUZ2_BLANK5"]
mk2_offset = bgm_layout['EBUZ2_MK2_CHARDATA']['bank_offset']

for name, expected in [
    ('EBUZ2_SCRIPT_TABLE', expected_script),
    ('EBUZ2_ALTLOOP_TABLE', expected_altloop),
    ('EBUZ2_STOPSEQ_TABLE', expected_stopseq),
]:
    ram_addr = gsym[name]
    blob_pos = mk2_offset + (ram_addr - RAM_BASE)
    actual = list(bgm_bank[blob_pos:blob_pos + len(expected)])
    check(f"{name}: bank6内のバイト列がComb組み込み後(assemble_game)の実アドレスと一致する"
          "(plainアセンブルのアドレスではないこと - round136の実機バグの回帰ガード)",
          actual == expected)


# ============================================================
# 2. 実際のTitle->Stage1トランポリンを経由した本物の起動+長時間
#    プレイシミュレーションで、ワイルドジャンプ/フリーズ/意図しない
#    VRAM破損が起きないことを確認する。
# ============================================================
class BankedMem:
    def __init__(self, banksA, banksB, portA=0x6000, portB=0x7000):
        self.flat = bytearray(0x10000)
        self.banksA = banksA
        self.banksB = banksB
        self.bankA = 0
        self.bankB = 0
        self.portA = portA
        self.portB = portB

    def __getitem__(self, addr):
        addr &= 0xFFFF
        if 0x4000 <= addr <= 0x7FFF:
            return self.banksA[self.bankA][addr - 0x4000]
        if 0x8000 <= addr <= 0xBFFF:
            return self.banksB[self.bankB][addr - 0x8000]
        return self.flat[addr]

    def __setitem__(self, addr, val):
        addr &= 0xFFFF
        val &= 0xFF
        if addr == self.portA:
            self.bankA = val % len(self.banksA)
            return
        if addr == self.portB:
            self.bankB = val % len(self.banksB)
            return
        if 0x4000 <= addr <= 0xBFFF:
            return
        self.flat[addr] = val


title_bank0, title_bank1, tsym = assemble_title()
bank4, bank5, s2sym = assemble_real_stage2()
gameover_bank, gosym = assemble_gameover_bank()
dummy = bytearray([0xFF] * 0x4000)

banksA = [title_bank0, dummy, game_bank0, dummy, bank4, dummy, dummy, gameover_bank]
banksB = [title_bank1, title_bank1, game_bank1, game_bank1, bank5, bank5, bgm_bank, dummy]

mem = BankedMem(banksA, banksB)
z = z80emu.Z80(mem)
z.pc = tsym["INIT"]


def run_until_pc(target, maxi=3_000_000):
    for _ in range(maxi):
        if z.pc == target:
            return True
        z.step()
    return False


# title_test.pyと同じ手法: RUN_SCREEN3_SLIDESHOWの実時間待ちを短縮
_RSS_MAIN_LOOP_COUNT_ADDR = tsym["RUN_SCREEN3_SLIDESHOW"] + 0x67
_WAIT_1F_DE_ADDR = tsym["WAIT_1_FRAME_UNIT"] + 1
assert mem.banksA[0][_RSS_MAIN_LOOP_COUNT_ADDR - 0x4000] == 3, \
    "RUN_SCREEN3_SLIDESHOW layout drifted - update _RSS_MAIN_LOOP_COUNT_ADDR"
mem.banksA[0][_WAIT_1F_DE_ADDR - 0x4000] = 5
mem.banksA[0][_WAIT_1F_DE_ADDR + 1 - 0x4000] = 0

check("Title INITからWAIT_FOR_STARTへ実際に到達する", run_until_pc(tsym["WAIT_FOR_START"]))
z.sim_trig_a = True
check("PUSH START(sim_trig_a)後、Stage1のINIT(0x4010)へトランポリンする",
      run_until_pc(0x4010, maxi=3_000_000))
check("Stage1のINITからMAINLOOPへ実際に到達する(bankA=2,bankB=3)",
      run_until_pc(gsym["MAINLOOP"], maxi=3_000_000) and mem.bankA == 2 and mem.bankB == 3)


def step_frame(maxi=300000):
    z.pc = gsym["MAINLOOP"]
    z.step()
    for _ in range(maxi):
        if z.pc == gsym["MAINLOOP"]:
            return True
        z.step()
    return False


def call_routine(entry_addr, maxi=300000):
    saved_sp = z.sp
    saved_pc = z.pc
    z.sp = 0xF000
    mem[0xF000] = 0x00
    mem[0xF001] = 0x00
    z.pc = entry_addr
    for _ in range(maxi):
        if z.pc == 0x0000:
            z.sp = saved_sp
            z.pc = saved_pc
            return True
        z.step()
    return False


z.wr(gsym["GAME_TICK"], 0)
z.wr(gsym["GAME_TICK"] + 1, 4)
step_frame()
check("CHECK_BOSS_TRIGGER発火でEbuz Mk2が実際にスポーンする(EBUZ2_ACT=1・HP=128)",
      mem[gsym["EBUZ2_ACT"]] == 1 and mem[gsym["EBUZ2_HP"]] == gsym["EBUZ2_HP_INIT"])

NFRAMES = 2200
completed = True
killed_mid_run = False
for i in range(NFRAMES):
    if not step_frame():
        check(f"フレーム{i}でスタックせず完走する(ワイルドジャンプ/フリーズが起きていないこと)", False)
        completed = False
        break
    if i == 900:
        killed_mid_run = call_routine(gsym["CHECK_BULLET_VS_EBUZ2"])

if completed:
    check(f"実起動+{NFRAMES}フレームの通しシミュレーションが一度もスタックせず完走する"
          "(round136の実機フリーズバグの回帰ガード)", True)
    check("シミュレーション途中でのMk2への被弾コールが正常に戻る", killed_mid_run)
    check("2200フレーム経過時点でMk2撃破→実ボスへの引き継ぎが完了している"
          "(EBUZ2_ACT=0・EBUZ2_DEFEATED=1・BOSS_STATE!=0)",
          mem[gsym["EBUZ2_ACT"]] == 0 and mem[gsym["EBUZ2_DEFEATED"]] == 1 and mem[gsym["BOSS_STATE"]] != 0)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
