# itch.io向けWebMSXパッケージ

`rom/CyberS Comb.ascii16k.rom`(Stage1+実Stage2統合"Comb"ビルド)を、ブラウザだけで
遊べる単一HTMLファイルに変換する。ベースは
[WebMSX](https://webmsx.org)([ppeccin/WebMSX](https://github.com/ppeccin/WebMSX))
の公式リリース「C-BIOS standalone」版(`release/stable/6.0/cbios/standalone/index.html`、
C-BIOS(フリーの互換BIOS)埋め込み済み・単一HTML)で、これを`vendor/`に取得済み。

## ビルド

```
cd tools/webmsx_itch
python3 build_itch_package.py
```

引数なしでリポジトリ直下の`rom/CyberS Comb.ascii16k.rom`を自動で使う
(先に`cd tools/bankswitch_poc && python3 build_full_rom.py`で最新化しておくこと)。
別のROMファイルを指定する場合は `python3 build_itch_package.py path/to/other.rom`。

出力: `dist/CyberShmup_webmsx_itch.zip`(gitignore対象、都度手元でビルドする)。
中身は`index.html`1つだけ(ROMはdata: URIとしてHTML内に埋め込み済み)。

## 適用している設定

- 機種: `MSX1J`(日本語MSX1、NTSC 60Hz)
- ROMフォーマット: `ASCII16`固定指定(128KB, 実際のマッパーポートは0x6000/0x7000)
- フルスクリーン: `SCREEN_FULLSCREEN_MODE=1`(起動時から画面いっぱいのレイアウト。
  ブラウザの実フルスクリーンAPIへの切替はユーザー操作が必要 - これはブラウザの制約で
  変更不可)
- ジョイスティック: `JOYSTICKS_MODE=0`(実ゲームパッド自動検出、既定のまま)に加え、
  `JOYKEYS_MODE=0`でポート1のキーボード代替入力(JoyKeys)を有効化。本ゲームはBIOS
  経由でポート1のジョイスティックのみを読むため、実パッドを持たないブラウザ利用者でも
  矢印キー等で遊べるようにするための設定
- 旧AppCache(`manifest="cache.manifest"`)関連の参照は未使用のため削除済み

## itch.ioへのアップロード手順

1. itch.ioでプロジェクト作成、Kind: **HTML**を選択
2. `dist/CyberShmup_webmsx_itch.zip`をそのままアップロード(index.htmlがzip直下に
   あるので追加設定不要)
3. "This file will be played in the browser" にチェック
4. Embed optionsで **Fullscreen button** を有効化
   (WebMSX自身のフルスクリーンボタンがブラウザの実フルスクリーンAPIを呼び出すため、
   itch側のiframeに`allowfullscreen`を許可させる必要がある)
5. Viewport: 適当な横長サイズ(例: 960x720程度)を指定。WebMSXの画面は内部で
   自動リサイズされるため、iframeサイズはある程度自由でよい
6. モバイル対応が必要ならmobile-friendlyの選択肢も検討(WebMSXはタッチ操作の
   仮想パッドに対応済み、`TOUCH_MODE`は既定の自動のまま)

## クレジット表記について

ページ自体、および公開ページの説明文には
[WebMSX](https://webmsx.org)(Paulo Augusto Peccin)と
[C-BIOS](https://cbios.sourceforge.net/)への謝辞・クレジットを入れておくのが望ましい
(WebMSXの配布物には各ファイル冒頭に著作権表記があるが、リポジトリ内に明示的な
LICENSE.txtは同梱されていなかった - 商用配布等を検討する場合は改めて
webmsx.orgで利用条件を確認すること)。

## 既知の注意点(2026-09-25時点)

- 今回のタスクでユーザーが添付したROMファイルは、実際にWebMSXで起動確認したところ
  本ゲームとは無関係な別タイトルの画面が表示された(恐らく古い/別のビルドの取り違え)。
  そのため本パッケージは添付ファイルではなく、リポジトリに現在コミットされている
  `rom/CyberS Comb.ascii16k.rom`(follow-up#23まで反映済み、実機確認済みのビルド)を
  使って作成している。
