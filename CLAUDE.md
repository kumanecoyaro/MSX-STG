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
- Stage1本番ROM: `cd tools/bankswitch_poc && python3 build_full_rom.py`
  → 出力: `rom/CyberS S1.ascii16k.rom`

## テストコマンド・実行方針

- 全回帰テスト: `cd tools/stage2_combined/tests && python3 run_all.py`
  - 実測: 所要2分以上(120秒タイムアウトでバックグラウンド実行に回るレベル)。トークン消費より
    ウォールクロックが重いため、**「完了」報告前の最終確認や、実機/エミュレータで疑わしい不具合が
    出た場合のデバッグ時のみ実行する**。関係なさそうな軽微な変更のたびに毎回フル実行しない。
  - 変更内容が特定の機能に限定される場合は、対応する個別テスト(例: `dash_test.py`)だけを
    先に実行して素早く確認し、全回帰は最終確認時にまとめて回す。
  - 個別テストは同ディレクトリの `*_test.py` を直接実行。

## 保留中タスク(指示なしに着手しない)

- "Comb"ビルド: `build_full_rom.py`のstage2部分を、現状の`bankswitch_poc`簡易プレースホルダーから
  本物の`stage2_combined`content に差し替える将来作業。明示的な指示があるまで着手しない。
