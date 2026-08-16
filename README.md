# MSX-STG — CYBER SHMUP

MSX (SCREEN1/GRAPHIC1, T32) 用の縦シューティング(STG)カートリッジROM。
多重レートのパララックス地形スクロール(5段)、自機ショット、ボスキャラを実装したZ80アセンブリ製ゲーム。

## 構成

```
src/CYBER_GD_BOSS.asm     Z80アセンブリソース(sjasmplus風構文)
rom/CYBER SHMUP.rom       ビルド済み32KB ROM(4000h-BFFFhにマップ)
tools/mini_z80asm.py      このソースの構文サブセット専用の簡易2パスZ80アセンブラ
tools/z80emu.py           デバッグ用の最小Z80+VDPエミュレータ(BIOSコールをフック)
```

## ビルド方法

```
python3 tools/mini_z80asm.py src/CYBER_GD_BOSS.asm "rom/CYBER SHMUP.rom" 32768 ff
```

`src/CYBER_GD_BOSS.asm` は `ORG 4000h` から始まり、アセンブル後の範囲は `4000h-93BFh`(21440バイト)。
出力ROMは32768バイト(32KB, カートリッジページ1: 4000h-BFFFh)、余白は `FFh` で埋める。
上記コマンドでビルドすると `rom/CYBER SHMUP.rom` は元のROMバイナリとバイト単位で完全一致する。

`tools/mini_z80asm.py` はこのソースで使われている構文サブセットのみをサポートする簡易アセンブラで、
汎用のZ80アセンブラ(sjasmplus等)の代替ではない点に注意。

## エミュレータ

`tools/z80emu.py` はメモリ・VRAMを持つ最小限のZ80 CPUインタプリタ。
主要なMSX BIOSルーチン(`LDIRVM`, `INIT32`, `WRTVDP`, `GTSTCK`, `GTTRIG`)を
実機ROMへのジャンプではなく直接インターセプトしてシミュレートする。
VDPポート(98h/99h)へのI/Oを記録し、VRAM書き込みログ(`vram_writes_log`)や
I/O出力ログ(`io_out_log`)からゲームの挙動をトレースできる。

単体のPythonライブラリとして提供されており、専用の実行エントリーポイントは無いため、
ROMを読み込んで `Z80` クラスを利用する簡単なドライバスクリプトを別途書いて使用する。

## 実機での動作

`rom/CYBER SHMUP.rom` はMSXエミュレータ(openMSX, blueMSX等)や
実機カートリッジに書き込んでそのまま起動できる標準的な16KB/32KB ROMイメージ(マッパー無し)。
ASCII16バンク切り替え版ROM(`tools/bankswitch_poc/`配下)は、ファイル名に
カッコ付きで `[ASCII16]` を含める命名規則とする(WebMSX等でのマッパー
自動/手動指定の目印として使う)。
