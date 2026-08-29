# 作業指示(常時適用)

- 応答・作業ログはすべて日本語で出力すること。
- ビルドエラー、テスト失敗の詳細、T-state計測結果など、デバッグに役立つ情報は省略せず日本語で説明しながら進めること。
- 作業再開時は `tools/stage2_combined/HANDOFF.md` の末尾(最新Round)を必ず読むこと。
- **このCLAUDE.mdは強い指示として扱う。作業の進捗・方針・保留タスクなどに変更があった場合は、
  その都度このファイルも適宜更新すること(放置して古い情報のまま残さない)。**

## プロジェクト構造(探索不要)

- 開発中の作業ファイル: `tools/stage2_combined/combined_test.asm`
- 実際に出荷されるゲーム本体: `src/CYBER SHMUP.asm`(Stage1)
- Round単位の作業履歴・技術的決定・ユーザー発言の逐語記録: `tools/stage2_combined/HANDOFF.md`
  - 177KB超の大きいファイル。全文Readせず、末尾(最新Round)だけを見ること。
    例: `tail -c 8000 tools/stage2_combined/HANDOFF.md` や `grep -n "^## Round" ... | tail`
- `tools/stage2_combined/README.md` は360KB超(設計メモの蓄積)。全文Readしない。目次代わりに
  `grep -n "^# \|^## "` で見出しだけ拾ってから該当箇所を読むこと。

## ビルドコマンド

- Stage2テストROM: `cd tools/stage2_combined && python3 build_test.py`
  → 出力: `tools/stage2_combined/CyberS S2.ascii16k.rom`
  → 実測所要時間: **0.2秒**(アセンブル自体はボトルネックではない)
- Stage1+実Stage2 統合ROM("Comb"ビルド): `cd tools/bankswitch_poc && python3 build_full_rom.py`
  → 出力: `rom/CyberS Comb.ascii16k.rom`(旧`CyberS S1.ascii16k.rom`は廃止・git管理からも削除済み)
  → 実測所要時間: **0.5秒**
  → bank2/bank3は2026-08-25より`tools/stage2_combined`の実コンテンツ(地形・戦車・敵・Sasapiボス戦)。
    詳細は`tools/bankswitch_poc/README.md`の「Full-game integration test」参照。
    検証: `cd tools/bankswitch_poc && python3 verify_comb.py`(エミュレータでStage1→実Stage2への
    バンク切替を一通り確認、バンクインデックス退避のバグを主眼に検証)。

ビルド(アセンブル)そのものは高速。「ビルドが遅い」と感じる場合、実際は次項の
回帰テスト(Z80エミュレータでの命令実行)が重い。オブジェクトファイル分離・リンカ機能の
実装は効果がほぼ無いため不要と判断済み(2026-08-25 実測により確認)。

## テストコマンド・実行方針

- 全回帰テスト: `cd tools/stage2_combined/tests && python3 run_all.py`
  - **実測所要時間: 約35秒**(2026-08-29時点765テスト。テスト数は変更のたびに増減する、
    629は2026-08-25の高速化計測当時の件数。2026-08-25の高速化前は約20分だった - 経緯は下記)。
  - この所要時間ならフォアグラウンドで待っても問題ないレベルだが、環境によりPyPyが
    無い(セッション開始hookが未実行/失敗した)場合は数分かかることもあるので、
    念のため引き続きバックグラウンド実行(`run_in_background`)を推奨。
  - 変更内容が特定の機能に限定される場合は、対応する個別テスト(例: `dash_test.py`)
    だけを先に実行して素早く確認し、全回帰は最終確認時にまとめて回す。
  - 個別テストは同ディレクトリの `*_test.py` を直接実行(`python3 xxx_test.py`または
    `pypy3 xxx_test.py`、後者の方が速い)。

### 高速化の経緯(2026-08-25、629 passed/0 failedを維持したまま約34倍)

ボトルネックはアセンブルではなく`z80emu.py`(Pure Python製Z80命令エミュレータ)による命令
ステップ実行(`boss_test.py`のプロファイルで、`cpu.step()`だけで244秒中96.7秒)。実施済み:

1. **`run_all.py`の並列実行**(`tests/run_all.py`): 各テストファイルは完全に独立したsubprocessな
   ので、`ThreadPoolExecutor`(`os.cpu_count()`ワーカー)で並列起動。19分53秒→8分23秒。
2. **`fresh_cpu()`のブート状態キャッシュ**(`tests/banked_helpers.py`): 同一プロセス内で
   ブートトレースは1回だけ実際に実行し、以降は`copy.deepcopy()`したスナップショットを返す。
   `fresh_cpu()`を多用するテストに効くが、`boss_test.py`自体は最重量テストケースが
   `step_frame()`を8000回連続実行する形なので、この施策だけでは効果は限定的だった。
3. **`z80emu.py`の`Z80.step()`オペコードディスパッチ並べ替え**: 実際のオペコード出現頻度を
   計測し(`boss_test.py`実行中に42.6M回の`step()`呼び出しをカウント)、if/elif連鎖の中で
   出現頻度の高い分岐(LD r,r'ブロック~8.8M、DDプレフィックス~4.8M、LD A,(nn)~3.7M、
   DJNZ~2.2M等)を先頭付近に移動。全64分岐は`op`値で完全に排他的条件かつ条件式に副作用が
   無いため、並べ替えは動作を一切変えない(新旧ファイルの全64ブロックを集合として比較し、
   内容が同一であることを機械的に検証済み)。8分23秒→6分8秒。
4. **PyPy導入**: 単体テスト(boss_test.py)で57秒→5.4秒(約10.6倍)、全回帰で6分8秒→34.7秒。
   `run_all.py`は`shutil.which("pypy3")`があれば自動的にそちらでテストサブプロセスを起動する
   (無ければ従来通り`sys.executable`にフォールバック、ポータブル)。このセッションのコンテナは
   使い捨てだが、`.claude/hooks/session-start.sh`(`.claude/settings.json`のSessionStart hookで
   登録済み)が`CLAUDE_CODE_REMOTE=true`の時に`pypy3`が無ければ`apt install`するので、
   このリポジトリのdefault branchにマージされていれば以後のweb/リモートセッションでも
   自動的にPyPyが使えるようになる(ユーザーへの確認を得て2026-08-25導入・登録済み)。

オブジェクトファイル・リンカ分離は見送り済み(アセンブル自体は0.2〜0.5秒でボトルネックでは
ないため効果なしと判断、上記「ビルドコマンド」の項参照)。

## 環境依存パスに関する注意(重要)

- このセッションの実ディレクトリは `/home/user/MSX-STG`(大文字)。過去のセッションでは
  `/home/user/msx-stg`(小文字)だったことがあり、**テストコード等に環境依存の絶対パスを
  ハードコードしないこと**。`__file__`からの相対パスを使う(`build_test.py`の
  `REPO = os.path.join(HERE, "..", "..")` パターンが正しい例)。
  - 2026-08-25: `tests/terrain_render_perf_test.py` に `/home/user/msx-stg/tools` への
    ハードコード絶対パスが残っており、このセッションの実ディレクトリ(大文字)と食い違って
    `ModuleNotFoundError: No module named 'mini_z80asm'` でクラッシュしていたのを発見・修正済み。
    全回帰テストの合計が629ではなく626+クラッシュ1件と表示され、テストカバレッジが
    静かに欠落していた(SKIPリストにも入っておらず、失敗ともカウントされない状態だった)。

## 保留中タスク(指示なしに着手しない)

- (2026-08-25、着手・完了済み) "Comb"ビルド: `build_full_rom.py`のstage2部分を、`bankswitch_poc`の
  簡易プレースホルダーから本物の`stage2_combined`contentに差し替え済み。詳細は上記「ビルドコマンド」
  および`tools/stage2_combined/HANDOFF.md`のRound30を参照。
- **Stage2の敵スポーンをStage1同様スケジュールテーブル駆動にする件**: 完了済み(2026-08-29)。
  - 第一段階(2026-08-29): `tools/schedule-editor.html`をStage2エネミー(ZacoII/Zum/BigZum/
    Flyer/Etank/Boss)対応に拡張。Stage1/Stage2切り替えボタン、相互登録禁止(`s2_`プレフィックスの
    名前空間分離)、出力ファイル分離(`stage`フィールド・`Schedule.json`/`Schedule2.json`)を実装。
    詳細は`tools/stage2_combined/HANDOFF.md`のRound33を参照。
  - 第二段階(2026-08-29、Round34): `tools/stage2_combined/combined_test.asm`側を実装。
    ユーザーがschedule-editorで実際に作成した152件のスケジュールJSONを、Stage1の
    `SPAWN_THRESHOLDS`/`SSC_FIRE`/`GAME_TICK`方式に倣ってテーブル駆動化
    (`SPAWN2_THRESHOLDS`/`SPAWN2_NEXT_INDEX`/`SSC2_FIRE`/`SPAWN2_SCHEDULE_CHECK`)。
    旧来のランダムスポーン(個別インターバルタイマー・ランダムY・ランダムバリアント・
    `ENEMY_SPAWN_STOP_TICK`一律ゲート)は全廃止。実装中に発見した「全エントリを1本の
    シーケンシャルインデックスに統合したことで、地上敵の排他制御が原因でボスが永久に
    スポーンしなくなりうる」という設計上の問題には`SPAWN2_STALL_LIMIT`安全弁で対処済み。
    詳細・技術的経緯は`tools/stage2_combined/HANDOFF.md`のRound34を参照。
  - **保留中(指示なしに着手しない)**: スケジュール自体の実プレイでの難易度・ペーシング調整
    (現状は添付JSONをそのまま実装しただけで未調整)。Sasapiボスの実物64x64ボディを
    schedule-editor.htmlに転写する件(Round33で明示的にスコープ外とした通り、引き続き未着手)。
