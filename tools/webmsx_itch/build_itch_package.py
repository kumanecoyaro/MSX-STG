"""itch.io向けWebMSX同梱パッケージのビルドスクリプト。

WebMSX(https://webmsx.org / https://github.com/ppeccin/WebMSX)の
"C-BIOS standalone" 公式リリース版(release/stable/6.0/cbios/standalone/index.html、
C-BIOS同梱・単一HTMLファイル)をベースに、指定したROMファイルを同梱し、MSX1J・
フルスクリーン・ジョイスティック有効の設定を適用したうえで、itch.ioにそのまま
アップロードできるzipファイルを生成する。

ROM本体はindex.htmlに埋め込まず、zip内の別ファイルとして同梱する
(例: "CyberShmup [ASCII16].rom")。ファイル名の[ASCII16]はWebMSX自身の
フォーマットヒント機能(SlotCreator.js finishInfo/formatMatchesByHint、
ドキュントの「ROM Format...You can also put the format specification in
the ROM file name, between brackets」)で、これによりCARTRIDGE1_FORMATを
明示指定しなくても常にASCII16として自動選択される。CARTRIDGE1_FORMATを
空のまま(自動判定)にしてWebMSXの純粋なヒューリスティックに任せると、この
ROM(128KB, ポート0x6000/0x7000のASCII16)は"ASCII 8K Mapper Cartridge"と
誤判定され画面が壊れることを確認済み - ファイル名ヒントはその誤判定を
確実に避けつつ、設定側は自動判定のままにできる。

ベーステンプレートは vendor/wmsx-cbios-standalone-6.0.8.html
(WebMSX 6.0.8, ppeccin/WebMSXリポジトリのrelease/stable/6.0/cbios/standalone/index.html
をそのまま取得したもの)。C-BIOSはこの中に既に埋め込まれているため追加のBIOSファイルは不要。

使い方:
    python3 build_itch_package.py [ROMファイルパス] [-o 出力zipパス] [--title タイトル]

    ROMファイルパスを省略した場合はリポジトリ直下の rom/CyberS Comb.ascii16k.rom
    (tools/bankswitch_poc/build_full_rom.py が生成する、最新のStage1+実Stage2統合
    "Comb"ビルド)を使う。
"""
import argparse
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
TEMPLATE = os.path.join(HERE, "vendor", "wmsx-cbios-standalone-6.0.8.html")
DEFAULT_ROM = os.path.join(REPO, "rom", "CyberS Comb.ascii16k.rom")
DEFAULT_OUT = os.path.join(HERE, "dist", "CyberShmup_webmsx_itch.zip")
ROM_NAME_IN_ZIP = "CyberShmup [ASCII16].rom"

# 非標準配列(mapping !== "standard")のパッドだけ、0=X,1=A,2=B,3=Y の並びを
# 標準配列の位置(0=下=A, 1=右=B, 2=左=X, 3=上=Y)へ並べ替える。
GAMEPAD_REMAP_SCRIPT = """<script>
(function () {
    if (!navigator.getGamepads) return;
    var original = navigator.getGamepads.bind(navigator);
    var ORDER = [1, 2, 0, 3];
    navigator.getGamepads = function () {
        var pads = original();
        var out = [];
        for (var i = 0; i < pads.length; i++) {
            var p = pads[i];
            if (!p || p.mapping === "standard" || p.buttons.length < 4) { out.push(p); continue; }
            var buttons = Array.prototype.slice.call(p.buttons);
            for (var j = 0; j < ORDER.length; j++) buttons[j] = p.buttons[ORDER[j]];
            out.push({ id: p.id, index: p.index, connected: p.connected, timestamp: p.timestamp,
                       mapping: p.mapping, axes: p.axes, buttons: buttons });
        }
        return out;
    };
})();
</script>
"""


def patch_config(html, rom_filename, title):
    def replace_field(src, field, old_literal, new_literal, count=1):
        pattern = re.compile(
            r'(\b' + re.escape(field) + r':\s*)' + re.escape(old_literal)
        )
        new_src, n = pattern.subn(lambda m: m.group(1) + new_literal, src, count=count)
        if n != count:
            raise RuntimeError(
                "テンプレート内でフィールド %r (旧値 %r) が期待通りに見つからなかった"
                "(件数=%d, 期待=%d)。WebMSXのテンプレートが更新された可能性がある。"
                % (field, old_literal, n, count)
            )
        return new_src

    # ROM本体: zip同梱の相対ファイルを指定(ファイル名の[ASCII16]がヒントとして
    # 働くため、CARTRIDGE1_FORMATは触らず空("" = 自動判定)のままにする)
    html = replace_field(html, "CARTRIDGE1_URL", '""', '"' + rom_filename + '"')

    # 機種: MSX1 日本(NTSC 60Hz, JIS配列)
    html = replace_field(html, "MACHINE", '""', '"MSX1J"')

    # 設定保存区画: itch.ioのHTMLゲームは全作品が同じorigin(html-classic.itch.zone)
    # で動くため、C-BIOS版WebMSX既定の101のままだと他のWebMSX作品と
    # localStorageの設定(ジョイスティック割り当て等)を共有してしまう。
    html = replace_field(html, "ENVIRONMENT", "101", "77")

    # ゲームパッドのA/B割り当て: 実機報告では、スマホ(標準配列)はA=0/B=1、
    # PCブラウザの非標準配列パッドはA=1/B=2で、固定の番号割り当て1つでは両立
    # しない(WebMSX既定のA=[0,2] B=[1,2]はボタン2がA/B両方に入っているため、
    # PCではAが「B」、Bが「A+B」になっていた)。そこで割り当て自体は標準配列
    # 基準のA=[0,2](下/左) B=[1,3](右/上)にし、非標準配列のパッドだけ
    # head内のスクリプト(GAMEPAD_REMAP_SCRIPT)で汎用USBパッドによくある
    # 0=X,1=A,2=B,3=Y の並びを標準配列の位置へ並べ替えてからWebMSXに渡す
    # (2人分の定義があるため2箇所)。
    old_joy = "J_A:[d.GB_1,d.GB_3],J_B:[d.GB_2,d.GB_3]"
    new_joy = "J_A:[d.GB_1,d.GB_3],J_B:[d.GB_2,d.GB_4]"
    if html.count(old_joy) != 2:
        raise RuntimeError("ゲームパッド既定割り当ての定義が想定通り2箇所見つからなかった")
    html = html.replace(old_joy, new_joy)

    # フルスクリーン: itch.ioのiframe内ではWebMSX自身にFullscreen APIを
    # 呼ばせない。全画面化と画面向きはitch.io側(埋め込みのFullscreen button、
    # モバイルの自動全画面+Orientation設定)に任せる。
    # - 1: 起動後の最初のタッチでWebMSXがiframe内部要素をrequestFullscreenし、
    #   itch.ioがiframeに掛けていた全画面+向きロックを奪ってポートレイトに戻る。
    #   さらにWebMSXのボタンは「解除」側にトグルする。
    # - -1(既定): MOBILE_MODE=1だと起動時に「GO!」待ちになり自動ロードされず、
    #   GO!/ボタンのrequestFullscreenもitch.ioのiframe内では効かない。
    # - 2(Full Windowed): CSS上だけiframe内いっぱいに表示し、APIは呼ばない。
    #   起動時から全画面扱いなので即自動ロード、タッチUIのCSSゲート
    #   (.wmsx-full-screen)も満たす。回転はiframeのリサイズとして追従する。
    html = replace_field(html, "SCREEN_FULLSCREEN_MODE", "-1", "2")

    # ジョイスティック: 実ゲームパッド接続を自動検出(既定のまま/明示化)
    html = replace_field(html, "JOYSTICKS_MODE", "0", "0")

    # 本ゲームはキーボード操作を想定しておらず実ジョイスティック専用のため
    # (実際に検証済み: JoyKeysでは一切反応せずGamepad APIでのみ動作した)、
    # 実ゲームパッドが無い/認識されない環境(itch.ioのiframe内でGamepad APIが
    # Permissions Policyでブロックされている場合等)でも遊べるよう、画面上の
    # タッチ/マウス操作対応バーチャルジョイスティックUIを強制表示する
    # (TOUCH_MODE=1でタッチ入力自体を強制有効化、MOBILE_MODE=1でUI自体の表示を
    # 強制)。
    #
    # JOYKEYS_MODE(キーボード代替入力)は意図的に既定の-1(無効)のままにする:
    # ControllersHubの各ポートの担当優先順位はMouse > Joystick > JoyKeys > Touchで
    # 固定(1ポートにつき同時に1つの入力ソースしか有効にならない)。この優先順位表の
    # 通り、JoyKeysをport1で有効にするとJoyKeysがTouchより先にport1を専有し続け、
    # 実際には一切使われないJoyKeysのせいで、有効な代替手段であるTouchのUI自体が
    # 表示されなくなる(`ControllersHub.getSettingsState().touchActive`が常にfalseの
    # ままになり、CSS側の`.wmsx-full-screen.wmsx-touch-active`ゲートが掛からず
    # バーチャルジョイスティックUIの要素が0x0サイズのまま描画されない、という実害を
    # 実機検証で確認済み)。キーボード操作を想定していない本ゲームではJoyKeys有効化に
    # メリットが無い一方デメリットだけがあるため、外したままにする。
    html = replace_field(html, "TOUCH_MODE", "0", "1")
    html = replace_field(html, "MOBILE_MODE", "0", "1")

    # 起動時の旧AppCache参照を除去(廃止済みAPIで、ファイルも同梱しないため)
    html = html.replace(
        '<html lang="en" translate="no" class="notranslate" manifest="cache.manifest">',
        '<html lang="en" translate="no" class="notranslate">',
        1,
    )
    html = re.sub(r'\s*<link rel="manifest" href="manifest\.webapp">\n', "\n", html, count=1)

    # WebMSX側のフルスクリーンボタンは非表示にする(mode 2では押すと
    # iframe内いっぱいの表示を解除するだけで、タッチUIも消えるため)。
    # 全画面化はitch.io側のFullscreen buttonを使う。
    head_close_idx = html.find("</head>")
    if head_close_idx == -1:
        raise RuntimeError("テンプレート内に</head>が見つからなかった")
    html = (html[:head_close_idx]
            + "<style>#wmsx-bar-full-screen { display: none !important; }</style>\n"
            + GAMEPAD_REMAP_SCRIPT
            + html[head_close_idx:])

    # (2026-09-25: ランドスケープ固定のためscreen.orientation.lock()を
    # fullscreenchangeイベントで試行するスクリプトを一時追加したが、実機
    # 検証で「フルスクリーン終了案内がずっと消えない」という重大な副作用が
    # 発生したため撤回済み。ロック処理自体がフルスクリーン状態の再検知を
    # 誘発し、ブラウザの案内表示がフェードする隙を与えず出続けていたと
    # 推測される。この種のブラウザネイティブAPIへの介入は実機検証なしに
    # 追加しないこと。)

    if title:
        html = re.sub(r"<title>.*?</title>", "<title>%s</title>" % title, html, count=1)

    return html


def build(rom_path, out_zip, title):
    with open(TEMPLATE, "r", encoding="utf-8") as f:
        html = f.read()
    with open(rom_path, "rb") as f:
        rom_bytes = f.read()

    patched = patch_config(html, ROM_NAME_IN_ZIP, title)

    os.makedirs(os.path.dirname(out_zip), exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("index.html", patched)
        z.writestr(ROM_NAME_IN_ZIP, rom_bytes)

    print("wrote %s (%d bytes, ROM %r: %d bytes)" % (out_zip, os.path.getsize(out_zip), ROM_NAME_IN_ZIP, len(rom_bytes)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", nargs="?", default=DEFAULT_ROM, help="埋め込むROMファイル(ASCII16, 128KB想定。省略時は%(default)s)")
    ap.add_argument("-o", "--out", default=DEFAULT_OUT, help="出力zipファイルパス")
    ap.add_argument("--title", default="CYBER SHMUP", help="ページタイトル(<title>)")
    args = ap.parse_args()
    build(args.rom, args.out, args.title)


if __name__ == "__main__":
    main()
