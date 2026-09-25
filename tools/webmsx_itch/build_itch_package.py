"""itch.io向けWebMSX同梱パッケージのビルドスクリプト。

WebMSX(https://webmsx.org / https://github.com/ppeccin/WebMSX)の
"C-BIOS standalone" 公式リリース版(release/stable/6.0/cbios/standalone/index.html、
C-BIOS同梱・単一HTMLファイル)をベースに、指定したROMファイルをdata: URIとして
埋め込み、MSX1J・フルスクリーン・ジョイスティック有効の設定を適用したうえで、
itch.ioにそのままアップロードできるzipファイルを生成する。

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
import base64
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
TEMPLATE = os.path.join(HERE, "vendor", "wmsx-cbios-standalone-6.0.8.html")
DEFAULT_ROM = os.path.join(REPO, "rom", "CyberS Comb.ascii16k.rom")
DEFAULT_OUT = os.path.join(HERE, "dist", "CyberShmup_webmsx_itch.zip")


def patch_config(html, rom_bytes, title):
    b64 = base64.b64encode(rom_bytes).decode("ascii")
    data_uri = "data:application/octet-stream;base64," + b64

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

    # ROM本体(data: URI として直接埋め込み。MultiDownloaderはXHR status===0を
    # 成功として扱うため data: URI からのロードに標準対応している)
    html = replace_field(html, "CARTRIDGE1_URL", '""', '"' + data_uri + '"')
    html = replace_field(html, "CARTRIDGE1_FORMAT", '""', '"ASCII16"')

    # 機種: MSX1 日本(NTSC 60Hz, JIS配列)
    html = replace_field(html, "MACHINE", '""', '"MSX1J"')

    # フルスクリーン: 起動時から画面いっぱいに表示するレイアウトを既定にする
    # (実際のブラウザFullscreen APIへの切替はユーザー操作が必要、これは変わらない)
    html = replace_field(html, "SCREEN_FULLSCREEN_MODE", "-1", "1")

    # ジョイスティック: 実ゲームパッド接続を自動検出(既定のまま/明示化)に加え、
    # キーボードでもジョイスティック入力ができるようJoyKeysをポート1で有効化
    # (本ゲームはBIOS経由でポート1のジョイスティックのみを読むため、実機のパッドを
    # 持たないブラウザ利用者でも遊べるようにする)
    html = replace_field(html, "JOYSTICKS_MODE", "0", "0")
    html = replace_field(html, "JOYKEYS_MODE", "-1", "0")

    # 起動時の旧AppCache参照を除去(廃止済みAPIで、ファイルも同梱しないため)
    html = html.replace(
        '<html lang="en" translate="no" class="notranslate" manifest="cache.manifest">',
        '<html lang="en" translate="no" class="notranslate">',
        1,
    )
    html = re.sub(r'\s*<link rel="manifest" href="manifest\.webapp">\n', "\n", html, count=1)

    if title:
        html = re.sub(r"<title>.*?</title>", "<title>%s</title>" % title, html, count=1)

    return html


def build(rom_path, out_zip, title):
    with open(TEMPLATE, "r", encoding="utf-8") as f:
        html = f.read()
    with open(rom_path, "rb") as f:
        rom_bytes = f.read()

    patched = patch_config(html, rom_bytes, title)

    os.makedirs(os.path.dirname(out_zip), exist_ok=True)
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("index.html", patched)

    print("wrote %s (%d bytes, ROM %d bytes embedded)" % (out_zip, os.path.getsize(out_zip), len(rom_bytes)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", nargs="?", default=DEFAULT_ROM, help="埋め込むROMファイル(ASCII16, 128KB想定。省略時は%(default)s)")
    ap.add_argument("-o", "--out", default=DEFAULT_OUT, help="出力zipファイルパス")
    ap.add_argument("--title", default="CYBER SHMUP", help="ページタイトル(<title>)")
    args = ap.parse_args()
    build(args.rom, args.out, args.title)


if __name__ == "__main__":
    main()
