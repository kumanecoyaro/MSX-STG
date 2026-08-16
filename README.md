# MSX-STG — CYBER SHMUP

MSX (SCREEN1/GRAPHIC1, T32) 用の縦シューティング(STG)カートリッジROM。
多重レートのパララックス地形スクロール(5段)、自機ショット、ボスキャラを実装したZ80アセンブリ製ゲーム。
ASCII16バンク切り替え(64KB、実機フラッシュカートのサイズ判定対策で128KBに複製)を採用。
32KB単一バンクROMはもう使わない。

## 構成

```
src/CYBER SHMUP.asm                            Z80アセンブリソース(sjasmplus風構文、ステージ1本体)
tools/mini_z80asm.py                           このソースの構文サブセット専用の簡易2パスZ80アセンブラ
tools/z80emu.py                                デバッグ用の最小Z80+VDPエミュレータ(BIOSコールをフック)
tools/bankswitch_poc/build_full_rom.py         本番ROMのビルドスクリプト(ASCII16, 64KB→128KB)
tools/bankswitch_poc/build_stage2_world.py     ステージ2ワールド(現状は敵をシンプルのみに絞ったテスト版)の生成
tools/bankswitch_poc/verify_full.py            エミュレータでのバンク切り替え・PSGミュート等の検証
rom/CYBER SHMUP [ASCII16].rom                  ビルド済みROM(128KB, ASCII16マッパー)
```

## ビルド方法

```
cd tools/bankswitch_poc
python3 build_full_rom.py
```

`src/CYBER SHMUP.asm` は `ORG 4000h` から始まり、アセンブル後の範囲は `4000h-B0BFh`(28864バイト)。
これがステージ1本体で、`build_full_rom.py` がこれをbank0/1としてアセンブルし、
`build_stage2_world.py` が生成するステージ2ワールドをbank2/3としてアセンブル、
4バンク・64KBに結合したうえで128KBに複製して `rom/CYBER SHMUP [ASCII16].rom` に書き出す。
マッパーはASCII16固定。バンク切り替え専用コード(RAMトランポリン、ステージ1→2の
切り替えトリガー、切り替え直前のPSGミュート)はビルド時にソースのインメモリコピーへ
差し込む形で、`src/CYBER SHMUP.asm` 自体は変更しない。

`tools/mini_z80asm.py` を直接使えば `src/CYBER SHMUP.asm` 単体をORG開始アドレスからの
生バイナリとしてアセンブルすることもできる(デバッグ用途、`tools/bankswitch_poc/`配下の
各種検証スクリプトが内部で使用)。ただしこれは32KB単一バンクROMとしては出荷しない。

`tools/mini_z80asm.py` はこのソースで使われている構文サブセットのみをサポートする簡易アセンブラで、
汎用のZ80アセンブラ(sjasmplus等)の代替ではない点に注意。

## エミュレータ

`tools/z80emu.py` はメモリ・VRAMを持つ最小限のZ80 CPUインタプリタ。
主要なMSX BIOSルーチン(`LDIRVM`, `INIT32`, `WRTVDP`, `GTSTCK`, `GTTRIG`)を
実機ROMへのジャンプではなく直接インターセプトしてシミュレートする。
VDPポート(98h/99h)へのI/Oを記録し、VRAM書き込みログ(`vram_writes_log`)や
I/O出力ログ(`io_out_log`)からゲームの挙動をトレースできる。ただしVDPポート
(98h/99h)以外へのOUT(PSGレジスタ等)は記録されないので、その手の検証は
アセンブル後のバイト列を直接確認する。

単体のPythonライブラリとして提供されており、専用の実行エントリーポイントは無いため、
ROMを読み込んで `Z80` クラスを利用する簡単なドライバスクリプトを別途書いて使用する。

## 実機・エミュレータでの動作

`rom/CYBER SHMUP [ASCII16].rom` がMSXエミュレータ(WebMSX, BlueMSX, openMSX等)や
実機フラッシュカートに書き込んでそのまま起動できるROMイメージ。ASCII16マッパー、128KB。
自動マッパー判定が効かない場合は手動で `ASCII16` を指定する(WebMSXで確認済み)。
ASCII16を使うROMのファイル名には今後もカッコ付きで `[ASCII16]` を含める命名規則とする。

詳細な設計根拠・実機デバッグの経緯は `tools/bankswitch_poc/README.md` を参照。
