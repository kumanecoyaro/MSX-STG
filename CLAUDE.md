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
- Stage1本番ROM: `cd tools/bankswitch_poc && python3 build_full_rom.py`
  → 出力: `rom/CyberS S1.ascii16k.rom`
  → 実測所要時間: **0.5秒**

ビルド(アセンブル)そのものは高速。「ビルドが遅い」と感じる場合、実際は次項の
回帰テスト(Z80エミュレータでの命令実行)が重い。オブジェクトファイル分離・リンカ機能の
実装は効果がほぼ無いため不要と判断済み(2026-08-25 実測により確認)。

## テストコマンド・実行方針

- 全回帰テスト: `cd tools/stage2_combined/tests && python3 run_all.py`
  - **実測所要時間: 約20分**(629テスト、出力量自体は36行/1.5KB程度でトークンコストは低いが、
    ウォールクロックが非常に重い)。ボトルネックはアセンブルではなく、`z80emu.py`(Pure Python製
    Z80命令エミュレータ)による命令ステップ実行(`fresh_cpu()`/`call_routine()`がテストケースごとに
    最大30万ステップをPythonで1命令ずつ実行)。
  - この重さのため、**「完了」報告前の最終確認や、実機/エミュレータで疑わしい不具合が出た場合の
    デバッグ時のみ実行する**。関係なさそうな軽微な変更のたびに毎回フル実行しない。
  - 実行する際は必ずバックグラウンド実行(`run_in_background`)にすること。フォアグラウンドで
    待つと120秒タイムアウトに引っかかる。
  - 変更内容が特定の機能に限定される場合は、対応する個別テスト(例: `dash_test.py`、数秒〜数十秒)
    だけを先に実行して素早く確認し、全回帰は最終確認時にまとめて回す。
  - 個別テストは同ディレクトリの `*_test.py` を直接実行。
  - 高速化の検討候補(未着手、指示があれば着手): (1) テスト並列実行、(2) `fresh_cpu()`の
    ブート済み状態をキャッシュしてテストケース間で使い回す、(3) z80emu.pyのプロファイリングと
    ホットパス最適化、(4) PyPy実行。

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

- "Comb"ビルド: `build_full_rom.py`のstage2部分を、現状の`bankswitch_poc`簡易プレースホルダーから
  本物の`stage2_combined`content に差し替える将来作業。明示的な指示があるまで着手しない。
