# itch.io向けWebMSXパッケージ

`rom/CyberS Comb.ascii16k.rom`(Stage1+実Stage2統合"Comb"ビルド)を、ブラウザだけで
遊べるHTMLパッケージに変換する。ベースは
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
中身は`index.html`と`CyberShmup [ASCII16].rom`の2ファイル(後述の理由によりROMは
data: URIとしてHTMLに埋め込まず、zip内の別ファイルとして同梱している)。

## 適用している設定

- 機種: `MSX1J`(日本語MSX1、NTSC 60Hz)
- ROMフォーマット: **明示指定せず自動判定のまま**。ただしROMファイル名を
  `CyberShmup [ASCII16].rom`にすることでWebMSX自身のフォーマットヒント機能
  (`SlotCreator.js`の`finishInfo`/`formatMatchesByHint`、ドキュメントの
  「ROM Format...You can also put the format specification in the ROM file
  name, between brackets」)を使い、常にASCII16として選択されるようにしている。
  - 検証: ROMをdata: URIとしてHTML内に埋め込みつつ`CARTRIDGE1_FORMAT`も空の
    ままにすると、WebMSXは純粋なヒューリスティックで**誤って"ASCII 8K Mapper
    Cartridge"と判定し画面が崩壊**することを確認済み(このROMは128KB・ポート
    0x6000/0x7000のASCII16で、8Kマッパーとは非互換)。ファイル名ヒントに
    切り替えたことでこの誤判定を避けつつ、設定側は純粋に自動判定のままにできる
    (`AUTO Format selected: ASCII 16K Mapper Cartridge`とコンソールに出ることを
    Playwright+ローカルHTTPサーバでの実起動確認で検証済み)
- フルスクリーン: `SCREEN_FULLSCREEN_MODE=1`(起動時から画面いっぱいのレイアウト。
  ブラウザの実フルスクリーンAPIへの切替はユーザー操作が必要 - これはブラウザの制約で
  変更不可)
- ジョイスティック: `JOYSTICKS_MODE=0`(実ゲームパッド自動検出、既定のまま)。
  **このゲームは実ジョイスティック専用でキーボード操作を想定していない**
  (実際に検証済み: タイトル画面はJoyKeys/キーボード入力では一切反応せず、
  Gamepad APIで実ジョイスティックを疑似接続した場合のみ本編に進めた)。
  - 実ゲームパッドが無い/認識されない環境(itch.ioの`<iframe>`内でGamepad APIが
    ブラウザのPermissions Policyによりブロックされている場合等)でも遊べるよう、
    `TOUCH_MODE=1`/`MOBILE_MODE=1`で画面上のタッチ/マウス対応バーチャル
    ジョイスティックUI(方向パッド+A/B/ABボタン)を強制表示している。マウスの
    クリック(押しっぱなし)でも操作可能なことをPlaywrightで実証済み
    (`#wmsx-touch-T_A`等をクリック→実際にタイトル画面から本編へ進行を確認)。
  - **`JOYKEYS_MODE`は意図的に既定の-1(無効)のままにしている**。理由:
    `ControllersHub`の各ポートの入力ソース優先順位は
    Mouse > Joystick > JoyKeys > Touch で固定(1ポートにつき同時に1つしか
    有効にならない)。このゲームではキーボード入力(JoyKeys)は実際には一切
    反応しないにもかかわらず、port1で有効化するとJoyKeysがTouchより先に
    port1を専有し続けてしまい、その結果`ControllersHub.getSettingsState().
    touchActive`が常にfalseのままになって、CSS側の
    `.wmsx-full-screen.wmsx-touch-active`ゲートが掛からず、上記のバーチャル
    ジョイスティックUI自体が(要素は存在するのに)0x0サイズのまま一切
    表示されなくなるという実害を確認した(最初は誤ってJOYKEYS_MODE=0と
    TOUCH_MODE=1を両方有効にしてしまい、この競合でUIが出ないまま
    ユーザーへ送付してしまった経緯があるので要注意)。JOYKEYS_MODEを
    外すことで解消・Playwrightで表示とクリック操作の両方を確認済み。
  - itch.io側のiframeが`allow="gamepad"`を含むかは、このセッションの
    ネットワーク制限でitch.ioに直接アクセスできず未確認。実ゲームパッドが
    itch.io上で反応しない場合でも、上記のタッチ/マウスUIがあるので操作は可能。
- 旧AppCache(`manifest="cache.manifest"`)関連の参照は未使用のため削除済み
- **画面向き(ランドスケープ)固定は未対応(撤回済み)**: WebMSX自身は
  レスポンシブCSSで現在の向きに追従するだけで、Screen Orientation APIに
  よる向きロックは一切行わない。itch.ioの「Mobile orientation」設定だけ
  では実機で向きが安定しない(タップした瞬間にポートレイトへ戻る)との
  報告を受け、`screen.orientation.lock("landscape")`を`fullscreenchange`
  イベントで試行するスクリプトを一度追加したが、**実機検証で「フルスクリーン
  終了案内(ブラウザネイティブの通知)がずっと消えずに出続ける」という
  より深刻な副作用が発生したため撤回した**(ロック処理自体がフルスクリーン
  状態の再検知を誘発し、通知がフェードする隙を与えていなかったと推測)。
  - この種のブラウザネイティブAPI(Fullscreen API・Screen Orientation API)
    への介入は副作用が読みにくく、実機検証なしに追加しないこと。
  - なお、iOS SafariはScreen Orientation APIのlock()自体を実装していない
    (2026-09時点)ため、そもそもiPhone/iPadでは技術的に強制不可能。
    Androidでの安全な実装方法(一度だけ試行する等)は今後の検討課題。

## itch.ioへのアップロード手順

1. itch.ioでプロジェクト作成、Kind: **HTML**を選択
2. `dist/CyberShmup_webmsx_itch.zip`をそのままアップロード(`index.html`がzip直下に
   あるので追加設定不要。`CyberShmup [ASCII16].rom`も同じzipに同梱済みで、
   index.htmlから同一originの相対パスとして参照される)
3. "This file will be played in the browser" にチェック
4. Embed optionsで **Fullscreen button** を有効化
   (WebMSX自身のフルスクリーンボタンがブラウザの実フルスクリーンAPIを呼び出すため、
   itch側のiframeに`allowfullscreen`を許可させる必要がある)
5. Viewport: 適当な横長サイズ(例: 960x720程度)を指定。WebMSXの画面は内部で
   自動リサイズされるため、iframeサイズはある程度自由でよい
6. 画面上に方向パッド+A/B/ABボタンのタッチ/マウス操作UIが常時表示される
   (`TOUCH_MODE=1`/`MOBILE_MODE=1`を強制指定済み、上記「適用している設定」参照)。
   実ゲームパッドが無い利用者はこれをマウスクリック(またはタッチ)で操作する

## クレジット表記について

ページ自体、および公開ページの説明文には
[WebMSX](https://webmsx.org)(Paulo Augusto Peccin)と
[C-BIOS](https://cbios.sourceforge.net/)への謝辞・クレジットを入れておくのが望ましい
(WebMSXの配布物には各ファイル冒頭に著作権表記があるが、リポジトリ内に明示的な
LICENSE.txtは同梱されていなかった - 商用配布等を検討する場合は改めて
webmsx.orgで利用条件を確認すること)。

## 既知の注意点(2026-09-25時点)

- ユーザーから最初に添付されたROMファイルは、WebMSXで実際に起動確認したところ
  「DOUBLE MISSION」という、`src/CYBER SHMUP.asm`(現在のgit HEAD)には存在しない
  タイトル画面から始まる、別系統(はるか昔)のビルドだった。ユーザー本人がこちらを
  使うよう指示したため、**現在この`build_itch_package.py`はデフォルトでは
  リポジトリの`rom/CyberS Comb.ascii16k.rom`(follow-up#23まで反映済みの最新ビルド、
  タイトル画面なし)を使うが、実際にitch.io向けに送付した版はユーザー添付の
  ROMファイル(タイトル画面あり、リポジトリには存在しない・非コミット)を明示的に
  `python3 build_itch_package.py <アップロードされたROMのパス>`で指定して作成した**。
  そのROMの由来・最新ソースとの機能差(follow-up#11〜#23で追加されたStage1弾発射・
  自機バリア・被ダメージ処理やStage2のEBullet・Flyer機雷/レーザー・ボス形態変化等が
  含まれない可能性)はユーザーに明示済み。次回以降、どちらのROMを使うべきかは都度
  確認すること(デフォルト引数を安易に変更しないこと - アップロード元ファイルは
  このセッション固有の一時パスにしか存在せず、将来のセッションでは参照できない)。
