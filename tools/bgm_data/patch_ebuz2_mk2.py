"""EBUZ2_MK2_CHARDATA(bgm_bank.bin内、bank6共有バンク)のうち、Stage1の
実コードアドレスに依存する3テーブル(EBUZ2_SCRIPT_TABLE/ALTLOOP_TABLE/
STOPSEQ_TABLE、計42byte)を、build_full_rom.assemble_game()(Comb組み込み
後のStage1アセンブル結果)のシンボルテーブルから再計算してbgm_bank.binへ
直接上書きする。

なぜ必要か: これらのテーブルは「テーブル駆動シーケンスエンジンがJP (HL)で
直接ジャンプするコードアドレス」を保持しており、Stage1(src/CYBER
SHMUP.asm)のコードサイズ・配置が変わるたびに実際のアドレスもズレる。
`bgm_bank_gen.py`の`_generate()`は循環import(build_full_rom.py側が
bgm_bank_gen.pyを読み込む設計のため逆方向は不可)によりStage1の
アセンブル結果を直接参照できないため、ここだけ別スクリプトとして分離
してある(round136由来、round145で使い捨てスクリプトから正式な
コミット対象へ格上げ)。

実行タイミング: Stage1(src/CYBER SHMUP.asm)のコードを変更した後は必ず
このスクリプトを再実行し、`tools/bankswitch_poc/verify_ebuz2_mk2_comb.py`
で整合性を再確認すること(CLAUDE.md Round136由来の教訓)。
`bgm_bank_gen.py --generate`を実行した場合も、EBUZ2部分は静的テンプレート
(ebuz2_mk2_chardata_template.bin)からそのままコピーされるだけで、
コードアドレス依存の42byteは古い値のまま復元されるため、必ずこのスクリプト
を後から実行すること。

使い方: python3 tools/bgm_data/patch_ebuz2_mk2.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(REPO, "tools"))
sys.path.insert(0, os.path.join(REPO, "tools", "bankswitch_poc"))
sys.path.insert(0, HERE)

from build_full_rom import assemble_game
import bgm_bank_gen as bg


def w(gsym, name):
    a = gsym[name]
    return [a & 0xFF, (a >> 8) & 0xFF]


def eqv(gsym, name):
    return gsym[name] & 0xFF


def build_tables(gsym):
    # tools/bankswitch_poc/verify_ebuz2_mk2_comb.pyのexpected_*と
    # 完全に同一の行構成(round138follow-up5時点のシーケンス)。テーブル
    # 内容自体を変更する場合は両ファイルを同時に更新すること。
    script = (
        w(gsym, 'EBUZ2_RECOIL_CLOSED_SHIFT') + [eqv(gsym, 'EBUZ2_RECOIL_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_RECOIL_CLOSED_REST') + [eqv(gsym, 'EBUZ2_RECOIL_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_TRANSFORM') + [eqv(gsym, 'EBUZ2_ENTRY_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_ACT_START_MOVEMENT') + [eqv(gsym, 'EBUZ2_VOLLEY2_ALT_START_HOLD_TICKS')]
    )
    altloop = (
        w(gsym, 'EBUZ2_ACT_ALT_TOP') + [eqv(gsym, 'EBUZ2_RECOIL_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_RECOIL_INNER_REST') + [eqv(gsym, 'EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_FIRE_OUTER_PAIR_AND_SHIFT') + [eqv(gsym, 'EBUZ2_RECOIL_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_ACT_ALT_LOOP_BACK') + [eqv(gsym, 'EBUZ2_VOLLEY2_WAVE_HOLD_TICKS')]
    )
    stopseq = (
        w(gsym, 'EBUZ2_FIRE_LASER_AND_SHIFT') + [eqv(gsym, 'EBUZ2_RECOIL_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_RECOIL_CENTER_REST') + [eqv(gsym, 'EBUZ2_LAP_STOP_HOLD_TICKS')] +
        w(gsym, 'EBUZ2_ACT_LOOP_RESET') + [1]
    )
    return script, altloop, stopseq


def main():
    game_bank0, game_bank1, gsym = assemble_game()
    bank, layout = bg.build_bank()
    bank = bytearray(bank)

    mk2_offset = layout['EBUZ2_MK2_CHARDATA']['bank_offset']
    ram_base = gsym['EBUZ2_BLANK5']

    script, altloop, stopseq = build_tables(gsym)
    changed = False
    for name, new_bytes in [
        ('EBUZ2_SCRIPT_TABLE', script),
        ('EBUZ2_ALTLOOP_TABLE', altloop),
        ('EBUZ2_STOPSEQ_TABLE', stopseq),
    ]:
        ram_addr = gsym[name]
        blob_pos = mk2_offset + (ram_addr - ram_base)
        old_bytes = list(bank[blob_pos:blob_pos + len(new_bytes)])
        print(f"{name} old=", old_bytes, "new=", new_bytes)
        if old_bytes != new_bytes:
            changed = True
        bank[blob_pos:blob_pos + len(new_bytes)] = bytes(new_bytes)

    with open(bg.BANK_BIN_PATH, "wb") as f:
        f.write(bytes(bank))
    print(f"patched {bg.BANK_BIN_PATH}", "(changed)" if changed else "(no change)")


if __name__ == "__main__":
    main()
