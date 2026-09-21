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
# 1b. round138(実機フィードバック対応): Mk2の上下移動範囲
#     (EBUZ2_MOVE_MIN_ROW/MAX_ROW)が、移植元tools/ebuz_mk2_test/
#     ebuz_mk2_test.asmの値(1/13)と一致していること、および開状態
#     (S2、7行)の最下行がGROUND_ROW0(4-row ground scrollerの先頭行、
#     NAMEBUF/PREVBUF差分キャッシュ経由でしか再描画されない領域)へ
#     絶対に到達しないことを直接検証する。移植時にこの範囲が誤って
#     2/14(1セル下)にずれていたことで、(a)「上下移動が1セル下に
#     ズレてる」という見た目のバグと、(b)S2本体がrow20まで届き
#     生VRAM書き込みで地形を破損させる「ブランクが地形のデータに
#     化けてる」という重大バグの両方が同時に起きていた。
# ============================================================
check("EBUZ2_MOVE_MIN_ROW==1(移植元テストROMの値と一致、1セル下ズレの回帰ガード)",
      gsym["EBUZ2_MOVE_MIN_ROW"] == 1)
check("EBUZ2_MOVE_MAX_ROW==13(移植元テストROMの値と一致、1セル下ズレの回帰ガード)",
      gsym["EBUZ2_MOVE_MAX_ROW"] == 13)
check("EBUZ2_MOVE_MAX_ROW+6(S2本体7行の最下行)がGROUND_ROW0より上に収まる"
      "(round138の地形破損バグの構造的回帰ガード、値そのものではなく不変条件を検証)",
      gsym["EBUZ2_MOVE_MAX_ROW"] + 6 < gsym["GROUND_ROW0"])


# ============================================================
# 1c. round138 follow-up(実機フィードバック対応、"上下移動範囲は修整
#     されたがブランクが地形に化けてるのは直っていない"): 1bの修正
#     だけではこの症状は解消しなかった。真因は別にあった - 移植元
#     tools/ebuz_mk2_test/ebuz_mk2_test.asm(スタンドアロンのテストROM)
#     は本体形状データの「空白セル」を生のパターンコード0で表していた
#     が、Stage1ではコード0は空白ではなく(BIOSデフォルトフォント由来と
#     思われる)実グラフィックが残っており、Stage1全体の「空セル」の
#     唯一正しい規約はBLANKCODE(=48、row0-19のsky全体がこれで塗られて
#     いる)。移植時にこの規約差を見落とし0のまま持ち込んだ結果、Mk2
#     本体の隙間セル・BLANK5/BLANK6(消去用)がまだら状の異物(コード0の
#     残留グラフィック)を表示してしまっていた。EBUZ2_BLANK5〜
#     EBUZ2_LASER_L_TILE直前(107byte、本体形状+消去データのみ、
#     レーザータイルのビットマップ本体は対象外)の値0を全てBLANKCODE
#     (48)へ置換して解消したことを直接検証する。
# ============================================================
BLANKCODE = gsym["BLANKCODE"]
A_, B_, C_, D_ = 88, 96, 104, 112
Z = BLANKCODE  # このデータ中の"空白セル"の正しい値
expected_blank_region = {
    'EBUZ2_BLANK5': [Z, Z, Z, Z, Z],
    'EBUZ2_BLANK6': [Z, Z, Z, Z, Z, Z],
    'EBUZ2_ROW_0': [Z, Z, A_, B_, C_],
    'EBUZ2_ROW_1': [Z, A_, B_, C_, D_],
    'EBUZ2_ROW_2': [A_, B_, C_, D_, D_],
    'EBUZ2_ROW_3': [Z, A_, B_, C_, D_],
    'EBUZ2_ROW_4': [Z, Z, A_, B_, C_],
    'EBUZ2_ROW_S2_0': [Z, Z, A_, B_, C_],
    'EBUZ2_ROW_S2_1': [Z, A_, B_, C_, C_],
    'EBUZ2_ROW_S2_2': [Z, Z, Z, Z, D_],
    'EBUZ2_ROW_S2_3': [A_, B_, C_, D_, D_],
    'EBUZ2_ROW_S2_4': [Z, Z, Z, Z, D_],
    'EBUZ2_ROW_S2_5': [Z, A_, B_, C_, C_],
    'EBUZ2_ROW_S2_6': [Z, Z, A_, B_, C_],
    'EBUZ2_ROW_S2_OUTER_REST': [Z, Z, A_, B_, C_, Z],
    'EBUZ2_ROW_S2_OUTER_RECOIL': [Z, Z, Z, A_, B_, C_],
    'EBUZ2_ROW_S2_INNER_REST': [Z, A_, B_, C_, C_, Z],
    'EBUZ2_ROW_S2_INNER_RECOIL': [Z, Z, A_, B_, C_, C_],
    'EBUZ2_ROW_S2_CENTER_REST': [A_, B_, C_, D_, D_, Z],
    'EBUZ2_ROW_S2_CENTER_RECOIL': [Z, A_, B_, C_, D_, D_],
}
RAM_BASE_BLANK = gsym["EBUZ2_BLANK5"]
all_blank_region_ok = True
for name, expected in expected_blank_region.items():
    ram_addr = gsym[name]
    blob_pos = mk2_offset + (ram_addr - RAM_BASE_BLANK)
    actual = list(bgm_bank[blob_pos:blob_pos + len(expected)])
    if actual != expected:
        all_blank_region_ok = False
    check(f"{name}: bank6内のバイト列が空白セル=BLANKCODE({BLANKCODE})規約で正しく格納されている"
          "(round138 follow-upの地形化けバグの回帰ガード、コード0[残留グラフィック]ではないこと)",
          actual == expected)
check("EBUZ2本体形状+消去データ(107byte)の中に、パターンコード0(Stage1では非空白の"
      "残留グラフィック)が1バイトも残っていない", all_blank_region_ok)


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
NAMTBL = 0x1800
GROUND_ROW0 = gsym["GROUND_ROW0"]
BLANKCODE = gsym["BLANKCODE"]
completed = True
killed_mid_run = False
row_cur_bound_ok = True
row20_untouched = True
max_row_cur_seen = -1
raw_zero_leak_frame = None
for i in range(NFRAMES):
    if not step_frame():
        check(f"フレーム{i}でスタックせず完走する(ワイルドジャンプ/フリーズが起きていないこと)", False)
        completed = False
        break
    rc = mem[gsym["EBUZ2_ROW_CUR"]]
    max_row_cur_seen = max(max_row_cur_seen, rc)
    if rc + 6 >= GROUND_ROW0:
        row_cur_bound_ok = False
    # round138 follow-up2("ちゃんとやれよクソが"): EBUZ2_UPDATE_V1_ONE/
    # EBUZ2_UL_RETRACT/EBUZ2_UV2_SLOTの消去が生値0(=Stage1では非空白の
    # 残留グラフィック)を書き込んでいた実バグの動的回帰ガード。row0(HUD)・
    # row20-23(ground scroller)を除く全セルにパターンコード0が一度でも
    # 現れたら検出する。
    if raw_zero_leak_frame is None:
        for row in range(1, GROUND_ROW0):
            base = NAMTBL + row * 32
            for col in range(32):
                if z.vram[base + col] == 0:
                    raw_zero_leak_frame = (i, row, col)
                    break
            if raw_zero_leak_frame is not None:
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
    check(f"実プレイ中、EBUZ2_ROW_CURの実測範囲が期待通り上端(MOVE_MAX_ROW=13)まで振れている"
          f"(実測max={max_row_cur_seen}、テスト自体が境界を実際に通過していることの確認)",
          max_row_cur_seen >= 12)
    check(f"実プレイ{NFRAMES}フレームを通じて、EBUZ2_UPDATE_V1_ONE/EBUZ2_UL_RETRACT/"
          "EBUZ2_UV2_SLOTの消去跡(volley1弾・レーザー・volley2弾が通過した後のセル)に"
          "生のパターンコード0(Stage1では非空白の残留グラフィック)が一度も現れない"
          f"(round138 follow-up2の回帰ガード、検出位置={raw_zero_leak_frame})",
          raw_zero_leak_frame is None)
    check("実プレイを通じて一度もS2本体(row_cur+6)がGROUND_ROW0(20)へ到達しない"
          "(round138の地形破損バグの動的回帰ガード)", row_cur_bound_ok)


print()
print(f"{len(ok)} passed, {len(fail)} failed")
if fail:
    print("FAILED:")
    for f in fail:
        print(" -", f)
    sys.exit(1)
