; SCREEN3(Multicolor)画像表示テスト(2026-09-12、"では取り敢えず組み込み
; はせずテストをする...この画像を表示してみてくれ 表示テスト用のROMを
; 作る ベースはタイトル表示までを流用 それ以外は空でいい" - 実機で
; 「おｋ意図通り表示できた」確認済みの続き、"次はこの6枚を連続で表示
; 3回繰り返して"→"ウェイトいらない 最大速度みたいんで"→
; "6枚目こうなってるんだけど これで正しいのか"[市松模様ノイズ]→
; RLE圧縮で単一バンクへ収める修正→"では各画像を3フレ表示でループに
; したRomを"→"では差分圧縮では"→"やってくれ"で差分[XOR]圧縮方式へ
; 再設計)。
;
; フレーム待ちはBIOS標準のJIFFY(0FC9Eh、H.TIMIのデフォルトハンドラが
; 毎vblank+1する2byteシステム変数)を参照するだけ - 本物のvblank同期
; (3フレーム=3/60秒≒50ms)、自前のビジーウェイトではない。
;
; **差分[XOR]圧縮の設計**: ネームテーブルは6枚とも完全に同一(実測
; 確認済み)なのでINIT時に1回だけVRAMへ書き込む。パターンジェネレータ
; (PGT)はフレーム間で16-22%だけ異なるため、1枚目は通常のRLE圧縮で
; フル保持、2〜6枚目は「直前フレームとのXOR差分」をRLE圧縮して保持
; (差分の大半は0=無変化のため独立圧縮より大幅に縮む - 実測合計
; 12287byte→5637byte)。実行時はRAM上にSHADOW_PGT(2048byte、現在の
; PGTの実体)を持ち、1枚目はそこへ展開してからVRAMへ一括LDIRVM、
; 2枚目以降は差分をSHADOW_PGTへXOR適用してから同じくLDIRVMでVRAMへ
; 反映する。このアセンブラはALU命令での(IX+d)直接オペランドを
; サポートしない(LD (IX+d)/LD A,(IX+d)は可、XOR (IX+d)は不可)ため、
; 「LD A,(IX+0)でシャドウの現在値を読む→XOR Cで差分値と合成→
; LD (IX+0),Aで書き戻す」という3段階で行う。
;
; (実機フィードバック対応の経緯): 6枚の生データ(2816byte x6=16896byte)
; は16KBの1バンクに収まらず0x8000をまたぐため、一度はASCII16の
; windowBバンク選択を追加したが実機で改善せず("変わってないな")。
; 切り分けのためImage06.SC3単体(バンク跨ぎ無し)を試したところ実機で
; 正常表示された("画像は正しく表示された")ことから、データ自体・
; バンク切替の実装そのものではなく「16KBを超えること自体」を避ける
; 方がこの環境では確実と判断、RLE圧縮(その後さらに差分圧縮)で単一
; バンクに収める方式にした。
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
LDIRVM   EQU 005Ch
WRTVDP   EQU 0047h
WRTVRM   EQU 004Dh
JIFFY    EQU 0FC9Eh   ; BIOS標準システム変数(2byte)、H.TIMIデフォルト
                       ; ハンドラが毎vblank+1する実時間クロック

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

SPRATR      EQU 1B00h
STACKTOP    EQU 0F380h
SHADOW_PGT  EQU 0E800h   ; 現在のPGT実体(2048byte、RAM上)- 差分適用先

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

    ; ネームテーブルは6枚とも完全に同一(screen3_gen.pyのshared_name_
    ; table()で実測確認済み)なので、ここで1回だけVRAM 1800hへ書き込み
    ; 以後二度と触らない。
    LD HL,SC3_SHARED_NAME : LD DE,1800h : LD BC,SC3_SHARED_NAME_LEN : CALL LDIRVM

    ; このテスト画像はいずれもスプライトパターンを持たないため、
    ; スプライトを一切表示しないことを明示的に保証する(title_test.asm
    ; と同じ0D1h停止マーカー)。
    LD A,0D1h : LD HL,SPRATR : CALL WRTVRM

    ; "各画像を3フレ表示でループにした" - 6枚を順に表示し続け、
    ; 6枚目の後は1枚目へ戻って無限に繰り返す(回数制限なし)。
SHOW_ALL_LOOP:
    CALL SHOW_IMG1
    CALL SHOW_IMG2
    CALL SHOW_IMG3
    CALL SHOW_IMG4
    CALL SHOW_IMG5
    CALL SHOW_IMG6
    JR SHOW_ALL_LOOP

; 1枚目(基準フレーム): SC3_IMG1_PGT_RLEをSHADOW_PGTへフル展開してから
; VRAM 0000hへ一括反映。
SHOW_IMG1:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG1_PGT_RLE : LD DE,SC3_IMG1_PGT_SEGMENTS : CALL DECOMPRESS_TO_RAM
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES

; 2〜6枚目: 直前フレームとのXOR差分をSHADOW_PGTへ適用してからVRAMへ
; 一括反映(差分方式なので、必ずこの順番[1→2→3→4→5→6]で呼ぶ前提 -
; SHOW_ALL_LOOPが常にこの順で呼ぶため成立する)。
SHOW_IMG2:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG2_PGT_XORDIFF : LD DE,SC3_IMG2_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES
SHOW_IMG3:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG3_PGT_XORDIFF : LD DE,SC3_IMG3_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES
SHOW_IMG4:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG4_PGT_XORDIFF : LD DE,SC3_IMG4_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES
SHOW_IMG5:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG5_PGT_XORDIFF : LD DE,SC3_IMG5_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES
SHOW_IMG6:
    LD IX,SHADOW_PGT
    LD HL,SC3_IMG6_PGT_XORDIFF : LD DE,SC3_IMG6_PGT_SEGMENTS : CALL APPLY_XOR_DIFF
    CALL FLUSH_SHADOW_TO_VRAM
    JP WAIT_3_FRAMES

; SHADOW_PGT(2048byte、RAM)->VRAM 0000hへ一括コピー(BIOS LDIRVM、
; CLAUDE.md恒久ルール通りOTIR等は不使用 - LDIRVMはBIOSルーチンで
; あってZ80のブロックI/O命令[OTIR等]そのものではない)。
FLUSH_SHADOW_TO_VRAM:
    LD HL,SHADOW_PGT : LD DE,0000h : LD BC,0800h : CALL LDIRVM
    RET

; 自前の対称RLE(制御バイトbit7=0:リテラル/1:反復、下位7bitは長さ-1、
; tools/title_screen/title_bg_gen.pyと同一フォーマット)を、VDPでは
; なくRAM上のSHADOW_PGTへそのまま展開する(1枚目の基準フレーム用)。
; HL=圧縮データ先頭、DE=セグメント数、IX=書き込み先(呼び出し前に
; SHADOW_PGTをセット)。
DECOMPRESS_TO_RAM:
    LD A,(HL) : INC HL
    OR A
    JP M,DTR_RUN
    AND 7Fh
    INC A
    LD B,A
DTR_LIT_LOOP:
    LD A,(HL) : INC HL
    LD (IX+0),A
    INC IX
    DJNZ DTR_LIT_LOOP
    JR DTR_NEXT
DTR_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
DTR_RUN_LOOP:
    LD (IX+0),A
    INC IX
    DJNZ DTR_RUN_LOOP
DTR_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,DECOMPRESS_TO_RAM
    RET

; 上と同じRLEフォーマットだが、展開した各バイトをSHADOW_PGTの現在値
; へ「上書き」ではなく「XOR適用」する(差分方式)。このアセンブラは
; ALU命令の(IX+d)直接オペランドをサポートしないため、"LD A,(IX+0)で
; 現在値を読む→XOR Cで差分値と合成→LD (IX+0),Aで書き戻す"の3段階で
; 行う(differenceの一回性の値はCに退避)。HL=圧縮データ先頭、
; DE=セグメント数、IX=適用先(呼び出し前にSHADOW_PGTをセット)。
APPLY_XOR_DIFF:
    LD A,(HL) : INC HL
    OR A
    JP M,AXD_RUN
    AND 7Fh
    INC A
    LD B,A
AXD_LIT_LOOP:
    LD A,(HL) : INC HL
    LD C,A
    LD A,(IX+0)
    XOR C
    LD (IX+0),A
    INC IX
    DJNZ AXD_LIT_LOOP
    JR AXD_NEXT
AXD_RUN:
    AND 7Fh
    INC A
    LD B,A
    LD A,(HL) : INC HL
    LD C,A
AXD_RUN_LOOP:
    LD A,(IX+0)
    XOR C
    LD (IX+0),A
    INC IX
    DJNZ AXD_RUN_LOOP
AXD_NEXT:
    DEC DE
    LD A,D : OR E
    JR NZ,APPLY_XOR_DIFF
    RET

; JIFFYが3回進むまで待つ(DEに基準値を保持したままHLだけ読み直して
; 比較 - SBC HL,DEはHLしか書き換えない)。
WAIT_3_FRAMES:
    CALL WAIT_1_FRAME
    CALL WAIT_1_FRAME
    JP WAIT_1_FRAME     ; 3回目はJPでRET先をSHOW_IMGxの呼び出し元(SHOW_ALL_LOOP)に委ねる
WAIT_1_FRAME:
    LD DE,(JIFFY)
WF1_LOOP:
    LD HL,(JIFFY)
    OR A
    SBC HL,DE
    JR Z,WF1_LOOP
    RET
