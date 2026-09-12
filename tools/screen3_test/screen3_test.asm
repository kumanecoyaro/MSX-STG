; SCREEN3(Multicolor)画像表示テスト(2026-09-12、"では取り敢えず組み込み
; はせずテストをする...この画像を表示してみてくれ 表示テスト用のROMを
; 作る ベースはタイトル表示までを流用 それ以外は空でいい" - 実機で
; 「おｋ意図通り表示できた」確認済みの続き、"次はこの6枚を連続で表示
; 3回繰り返して"→"ウェイトいらない 最大速度みたいんで"で各画像間の
; ウェイトを撤去、LDIRVM転送そのものの所要時間だけが切り替わり間隔)。
;
; tools/title_screen/title_test.asmのINIT冒頭(DI・BIOS画面モード初期化
; ・VDP R1/R7設定・スプライト停止・EI)をそのまま踏襲した最小構成。
; BGM・ボタン入力・ゲーム本編は一切無し(指示通り「それ以外は空」)。
;
; (実機フィードバック対応その2、"6枚目こうなってるんだけど これで
; 正しいのか"[市松模様ノイズのスクリーンショット添付]): 初版は6枚分の
; データ(2816byte x6=16896byte、0x4000起点で0x8000をまたぐ)を
; 単なる「flat 32KB ROM」として書き出していたが、この実機/フラッシュ
; カートは常にASCII16メガROMとしてマッピングされる(このプロジェクトの
; 他の全ROM[Comb/Title/Stage2]が実際に使っている方式)ため、windowB
; (8000h-BFFFh)を明示的にバンク選択しない限りその領域の内容は保証
; されない - 6枚目のネームテーブルがちょうど8000hをまたいでいたため、
; windowBの後半だけ別の(未選択の)バンクの内容を指してしまい、市松模様
; ノイズとして現れていたと判明(tools/stage2_combined/build_test.pyの
; 自身の過去の教訓"ファイル名に[ASCII16]を含めろ...本番テストは
; WebMSXでファイル名からマッパー種別を自動判定"と全く同じ罠)。
; title_test.asm/combined_test.asm等と同じ「INIT冒頭でwindowBを自分
; 自身のbank1へ明示的に一度だけ選択する(LD A,1:LD(7000h),A)」方式を
; 追加し、build_test.py側もbank0/bank1を実際に分離した上で64KBへ倍化
; ・ファイル名に"ascii16"を含める(このプロジェクトの他の全ROMと同じ
; 規約)よう修正した。
;
; (実機フィードバック対応: "スクリーン3に設定できてないな TMS9918の
; スクリーン3は64x48px"): このプロジェクトで既に実機検証済みのINIT32
; (SCREEN1、Stage1/Stage2/terrain_test.asm等で実績あり)をベースに、
; TMS9918のモード選択ビット(M1=VDP R1 bit4/M2=R1 bit3/M3=VDP R0
; bit1)のうちGraphics1→Multicolorへの差分であるM2(R1 bit3)だけを
; 追加で立てる方式(実機確認済み、「おｋ意図通り表示できた」)。
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

SPRATR       EQU 1B00h
STACKTOP     EQU 0F380h
REPEAT_COUNT EQU 0F000h   ; scratch RAM byte (残り周回数)

INIT:
    LD SP,STACKTOP
    DI
    ; ASCII16メガROMとしてマッピングされる実機/フラッシュカート向けに、
    ; windowB(8000h-BFFFh)をこのファイル自身のbank1へ明示的に選択
    ; (title_test.asmのINIT_BGM等と同じ規約) - これでbank0(windowA、
    ; 4000h-7FFFh)+bank1(windowB)が真に連続した32KBとしてCPUから見える。
    LD A,1
    LD (7000h),A
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

    ; このテスト画像はいずれもスプライトパターンを持たないため、
    ; スプライトを一切表示しないことを明示的に保証する(title_test.asm
    ; と同じ0D1h停止マーカー、以後全ループを通して変更不要)。
    LD A,0D1h : LD HL,SPRATR : CALL WRTVRM

    ; "6枚を連続で表示 3回繰り返して" - 6枚1周を3回。
    LD A,3
    LD (REPEAT_COUNT),A
SHOW_ALL_LOOP:
    CALL SHOW_IMG1
    CALL SHOW_IMG2
    CALL SHOW_IMG3
    CALL SHOW_IMG4
    CALL SHOW_IMG5
    CALL SHOW_IMG6
    LD A,(REPEAT_COUNT)
    DEC A
    LD (REPEAT_COUNT),A
    JR NZ,SHOW_ALL_LOOP

HALT_LOOP:
    JR HALT_LOOP

; パターンジェネレータ(2048byte)->VRAM 0000h、ネームテーブル
; (768byte)->VRAM 1800h(いずれもBIOS標準デフォルトアドレス -
; ソースファイル自体の内部配置[screen3_gen.py参照]とは無関係)へ
; 転送するだけ("ウェイトいらない 最大速度みたいんで" - 表示後は
; 一切待たず即座に次の画像のLDIRVMへ進む、実質LDIRVM自体の転送時間
; [2048+768byte]だけが切り替わり間隔になる)。
SHOW_IMG1:
    LD HL,SC3_IMG1_PGT : LD DE,0000h : LD BC,SC3_IMG1_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG1_NAME : LD DE,1800h : LD BC,SC3_IMG1_NAME_LEN : CALL LDIRVM
    RET
SHOW_IMG2:
    LD HL,SC3_IMG2_PGT : LD DE,0000h : LD BC,SC3_IMG2_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG2_NAME : LD DE,1800h : LD BC,SC3_IMG2_NAME_LEN : CALL LDIRVM
    RET
SHOW_IMG3:
    LD HL,SC3_IMG3_PGT : LD DE,0000h : LD BC,SC3_IMG3_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG3_NAME : LD DE,1800h : LD BC,SC3_IMG3_NAME_LEN : CALL LDIRVM
    RET
SHOW_IMG4:
    LD HL,SC3_IMG4_PGT : LD DE,0000h : LD BC,SC3_IMG4_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG4_NAME : LD DE,1800h : LD BC,SC3_IMG4_NAME_LEN : CALL LDIRVM
    RET
SHOW_IMG5:
    LD HL,SC3_IMG5_PGT : LD DE,0000h : LD BC,SC3_IMG5_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG5_NAME : LD DE,1800h : LD BC,SC3_IMG5_NAME_LEN : CALL LDIRVM
    RET
SHOW_IMG6:
    LD HL,SC3_IMG6_PGT : LD DE,0000h : LD BC,SC3_IMG6_PGT_LEN : CALL LDIRVM
    LD HL,SC3_IMG6_NAME : LD DE,1800h : LD BC,SC3_IMG6_NAME_LEN : CALL LDIRVM
    RET
