; SCREEN3(Multicolor)画像表示テスト(2026-09-12、"では取り敢えず組み込み
; はせずテストをする...この画像を表示してみてくれ 表示テスト用のROMを
; 作る ベースはタイトル表示までを流用 それ以外は空でいい" - 実機で
; 「おｋ意図通り表示できた」確認済みの続き、"次はこの6枚を連続で表示
; 3回繰り返して"→"ウェイトいらない 最大速度みたいんで"→
; "6枚目こうなってるんだけど これで正しいのか"[市松模様ノイズ])。
;
; tools/title_screen/title_test.asmのINIT冒頭(DI・BIOS画面モード初期化
; ・VDP R1/R7設定・スプライト停止・EI)をそのまま踏襲した最小構成。
; BGM・ボタン入力・ゲーム本編は一切無し(指示通り「それ以外は空」)。
;
; (実機フィードバック対応の経緯): 6枚の生データ(2816byte x6=16896byte)
; は16KBの1バンクに収まらず0x8000をまたぐため、一度はASCII16の
; windowBバンク選択(LD A,1:LD(7000h),A)を追加したが実機で改善せず
; ("変わってないな")。切り分けのためImage06.SC3単体(バンク跨ぎ無し、
; Round82と同じ構成)を試したところ実機で正常表示された("画像は正しく
; 表示された")ことから、データ自体・バンク切替の実装そのものではなく
; 「16KBを超えること自体」を避ける方がこの環境では確実と判断。
; tools/title_screen/title_bg_gen.pyと全く同じ自前RLE圧縮(制御バイト
; bit7=0:リテラル/1:反復)をPGT・NAMEそれぞれに適用し、6枚まとめて
; 16KBの1バンクに余裕で収まるようにした(バンク切替自体が完全に
; 不要になる、CLAUDE.md恒久ルール通りOTIR等のブロックI/O命令は不使用・
; DJNZ+通常のOUTのみ)。
;
; (実機フィードバック対応: "スクリーン3に設定できてないな TMS9918の
; スクリーン3は64x48px"): このプロジェクトで既に実機検証済みのINIT32
; (SCREEN1、Stage1/Stage2/terrain_test.asm等で実績あり)をベースに、
; TMS9918のモード選択ビット(M1=VDP R1 bit4/M2=R1 bit3/M3=VDP R0
; bit1)のうちGraphics1→Multicolorへの差分であるM2(R1 bit3)だけを
; 追加で立てる方式(実機確認済み、「おｋ意図通り表示できた」)。
    ORG 4000h

INIT32   EQU 006Fh   ; SCREEN1初期化(BIOS) - 実機検証済み、Multicolorとの
                      ; 差分(R1のM2ビットのみ)は下で追加設定する
WRTVDP   EQU 0047h
WRTVRM   EQU 004Dh
VDP_ADDR EQU 099h
VDP_DATA EQU 098h

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

; パターンジェネレータ->VRAM 0000h、ネームテーブル->VRAM 1800h(いずれも
; BIOS標準デフォルトアドレス)へRLE展開するだけ("ウェイトいらない
; 最大速度みたいんで" - 展開完了次第即座に次の画像へ進む)。
SHOW_IMG1:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG1_PGT_RLE : LD DE,SC3_IMG1_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG1_NAME_RLE : LD DE,SC3_IMG1_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET
SHOW_IMG2:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG2_PGT_RLE : LD DE,SC3_IMG2_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG2_NAME_RLE : LD DE,SC3_IMG2_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET
SHOW_IMG3:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG3_PGT_RLE : LD DE,SC3_IMG3_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG3_NAME_RLE : LD DE,SC3_IMG3_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET
SHOW_IMG4:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG4_PGT_RLE : LD DE,SC3_IMG4_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG4_NAME_RLE : LD DE,SC3_IMG4_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET
SHOW_IMG5:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG5_PGT_RLE : LD DE,SC3_IMG5_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG5_NAME_RLE : LD DE,SC3_IMG5_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET
SHOW_IMG6:
    LD HL,0000h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG6_PGT_RLE : LD DE,SC3_IMG6_PGT_SEGMENTS : CALL DECOMPRESS_STREAM
    LD HL,1800h : CALL SET_VRAM_WRITE
    LD HL,SC3_IMG6_NAME_RLE : LD DE,SC3_IMG6_NAME_SEGMENTS : CALL DECOMPRESS_STREAM
    RET

; HL=VRAM書き込み先アドレス。以後VDPのオートインクリメントで
; DECOMPRESS_STREAMが連続して書き込める(title_test.asmのDECOMPRESS_
; TITLE_BGと同じ規約)。
SET_VRAM_WRITE:
    LD A,L : OUT (VDP_ADDR),A
    LD A,H : OR 40h : OUT (VDP_ADDR),A
    RET

; 自前の対称RLE(制御バイトbit7=0:リテラル/1:反復、下位7bitは長さ-1、
; tools/title_screen/title_bg_gen.pyと同一フォーマット)をVDPの
; オートインクリメント書き込みへ直接ストリーム展開する
; (title_test.asmのDECOMPRESS_TITLE_BGと全く同じロジック、CLAUDE.md
; 恒久ルール通りOTIR等は不使用・DJNZ+通常のOUTのみ)。
; HL=圧縮データ先頭、DE=セグメント数。
DECOMPRESS_STREAM:
    LD A,(HL) : INC HL
    OR A
    JP M,DS_RUN
    AND 7Fh
    INC A
    LD B,A
DS_LIT_LOOP:
    LD A,(HL) : INC HL
    OUT (VDP_DATA),A
    DJNZ DS_LIT_LOOP
    JR DS_NEXT
DS_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
DS_RUN_LOOP:
    OUT (VDP_DATA),A
    DJNZ DS_RUN_LOOP
DS_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,DECOMPRESS_STREAM
    RET
