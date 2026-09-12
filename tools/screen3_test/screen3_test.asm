; SCREEN3(Multicolor)画像表示テスト(2026-09-12、"では取り敢えず組み込み
; はせずテストをする...この画像を表示してみてくれ 表示テスト用のROMを
; 作る ベースはタイトル表示までを流用 それ以外は空でいい")。
;
; tools/title_screen/title_test.asmのINIT冒頭(DI・BIOS画面モード初期化
; ・VDP R1/R7設定・スプライト停止・EI)をそのまま踏襲した最小構成。
; BGM・バンク切替・ボタン入力・ゲーム本編は一切無し(指示通り「それ以外
; は空」)。単発の16KB flat ROM(tools/stage2_terrain/terrain_test.asmと
; 同じ、ASCII16のページ切替すら不要な単純な構成 - 表示に必要なデータ
; [PGT2048byte+NAME768byte=2816byte]がこの1バンクに余裕で収まるため)。
;
; (2026-09-12、実機フィードバック対応 "スクリーン3に設定できてないな
; TMS9918のスクリーン3は64x48px"): 初版は根拠の薄い推測のBIOSアドレス
; (INIMLT=0075h、INIT32/INIGRPの並びから類推しただけで実機未検証)を
; 呼んでいたため、SCREEN3へ実際には切り替わっていなかった(添付
; スクリーンショットの縦縞ノイズは、Multicolorモードのデータを別モード
; として解釈してしまった結果と一致)。この推測ルーチンは完全に撤回し、
; 代わりにこのプロジェクトで既に実機検証済みのINIT32(SCREEN1、
; Stage1/Stage2/terrain_test.asm等で実績あり)をベースに、TMS9918の
; モード選択ビット(M1=VDP R1 bit4/M2=R1 bit3/M3=VDP R0 bit1)のうち
; Graphics1→Multicolorへの差分であるM2(R1 bit3)だけを追加で立てる
; 方式に変更(M1=0/M3=0はGraphics1・Multicolor共通、INIT32が既に
; 正しく設定済みのまま)。パターンジェネレータ/ネームテーブル/
; スプライト属性のVRAMアドレス(0000h/1800h/1B00h)もGraphics1と
; Multicolorで共通のため、INIT32が設定した値をそのまま流用できる。
    ORG 4000h

INIT32  EQU 006Fh   ; SCREEN1初期化(BIOS) - 実機検証済み、Multicolorとの
                     ; 差分(R1のM2ビットのみ)は下で追加設定する
LDIRVM  EQU 005Ch
WRTVDP  EQU 0047h
WRTVRM  EQU 004Dh

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

SPRATR   EQU 1B00h
STACKTOP EQU 0F380h

INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32
    EI

    ; Graphics1(SCREEN1)からMulticolor(SCREEN3)への切替はM2ビット
    ; (VDP R1 bit3)を追加で立てるだけ - M1(bit4)=0/M3(VDP R0 bit1)=0は
    ; 両モード共通でINIT32が既に正しく設定済み。0E2h(Graphics1で
    ; Title/Stage1/Stage2が使う値、16x16 sprite mode+display/IE on)に
    ; bit3(08h)を追加した0EAhを書く。
    LD B,0EAh : LD C,1 : CALL WRTVDP
    ; border/backdrop black
    LD B,01h : LD C,7 : CALL WRTVDP

    ; パターンジェネレータ(2048byte)->VRAM 0000h、ネームテーブル
    ; (768byte)->VRAM 1800h(いずれもBIOS標準デフォルトアドレス -
    ; ソースファイル自体の内部配置[screen3_gen.py参照]とは無関係)。
    LD HL,SC3_PGT : LD DE,0000h : LD BC,SC3_PGT_LEN : CALL LDIRVM
    LD HL,SC3_NAME : LD DE,1800h : LD BC,SC3_NAME_LEN : CALL LDIRVM

    ; このテスト画像はスプライトパターンを持たないため、スプライトを
    ; 一切表示しないことを明示的に保証する(title_test.asmと同じ
    ; 0D1h停止マーカー)。
    LD A,0D1h : LD HL,SPRATR : CALL WRTVRM

HALT_LOOP:
    JR HALT_LOOP
