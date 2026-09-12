; SCREEN3(Multicolor)画像表示テスト(2026-09-12、"では取り敢えず組み込み
; はせずテストをする...この画像を表示してみてくれ 表示テスト用のROMを
; 作る ベースはタイトル表示までを流用 それ以外は空でいい" - 実機で
; 「おｋ意図通り表示できた」確認済みの続き、"次はこの6枚を連続で表示
; 3回繰り返して"→"ウェイトいらない 最大速度みたいんで"で各画像間の
; ウェイトを撤去、LDIRVM転送そのものの所要時間だけが切り替わり間隔)。
;
; tools/title_screen/title_test.asmのINIT冒頭(DI・BIOS画面モード初期化
; ・VDP R1/R7設定・スプライト停止・EI)をそのまま踏襲した最小構成。
; BGM・バンク切替・ボタン入力・ゲーム本編は一切無し(指示通り「それ以外
; は空」)。単発の32KB flat ROM(tools/stage2_terrain/terrain_test.asmと
; 同じ、ASCII16のページ切替すら不要な単純な構成 - 表示に必要なデータ
; [PGT2048byte+NAME768byte=2816byte x6枚=16896byte]が32KB[0000h起点で
; 4000h-BFFFh]に余裕で収まるため)。
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
