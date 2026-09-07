; GAME_OVERバンク(2026-09-07新設): Stage2(tools/stage2_combined/
; combined_test.asm)のTANK_LIFE枯渇時の死亡演出+"MISSION FAILED"表示
; 専用の独立16KBバンク。
;
; 経緯: 「まずステージ2もステージ1同様にHPが無くなったら爆発処理を
; ゲームオーバーは画面中央にGAME OVERと表示」という指示に対し、Stage2
; 本体側のROM残り容量がわずか97byte(2026-09-07時点)しかなく、Stage1
; 同等の演出(16x16スプライトが自機周辺に複数回ランダムに派手に発生し
; 続ける2秒間のバースト演出、専用ATTRIBUTEスロット・専用スプライト
; パターンとも新規追加の余地なし)をそのまま移植できないと判明。
; ユーザー確認の上、tools/bgm_data/bgm_bank_gen.pyの"bgm-data"バンクと
; 同じ「専用バンクへ処理を逃がす」設計を採用。
;
; 続けてユーザーから: "ステージ2クリア後は10秒でタイトル画面に
; ゲームオーバー表示は3秒表示してボタンが押されるか10秒経過でタイトル
; 画面に で、表示もGAME OVERではなくMISSION FAILEDに変更" - 当初の
; "完全に停止"方針を上書き、タイトルへの復帰フローを追加。
;
; standaloneでは local bank index3(own bank0=このファイル1個のみ、
; bank1は無し・window Aのみで完結)としてテストされ、Combビルドでは
; build_full_rom.pyがglobal bank7(これまで完全な0xFF空きフィラー
; だった枠)へ配置する。combined_test.asm側のTRIGGER_GAME_OVERが
; window Aだけをこのバンクへ切り替える1ホップのトランポリンで飛んで
; くる(DI済み・window Bはcombined_test.asm自身のbank1のまま一切
; 触れない)。ここからtitle(GLOBAL bank0/1)へ戻る際も同じ2ホップ
; トランポリン手法(window B→window Aの順)を使う。
;
; RAM(TANK_X/TANK_Y_CUR等)とVRAM(PAT_EXPLOSIONスプライトパターン
; 含む、Stage2本編のINITが既にロード済み)は物理的に共有されている
; ため、このバンクは両方ともStage2が残した内容をそのまま再利用する
; (新規に読み込み直さない)。GAME OVER後は地形スクロール等のBG更新が
; 二度と起きないため、パターンジェネレータのコード0-10を無条件に
; このバンク専用のフォントで上書きする(空きコード探索は不要 - どうせ
; 二度と参照されない)。
    ORG 4000h

; --- combined_test.asmと物理的に同じRAM/VRAMアドレス。値は必ず一致 ---
; --- させること(このファイル単体では検証できない)。                 ---
TANK_X          EQU 0F120h
TANK_Y_CUR      EQU 0F121h
SPRATR          EQU 1B00h
PAT_EXPLOSION   EQU 136
EXPLOSION_COLOR EQU 8
PSG_ADDR        EQU 0A0h
PSG_DATA        EQU 0A1h
LDIRVM          EQU 005Ch
GTTRIG          EQU 00D8h
HTIMI_HOOK      EQU 0FD9Fh

; --- Comb globalバンク番号。standaloneでは0/1は無意味(単独バンクの ---
; --- ためtitleへは戻れない、テストは戻る直前のGOTO_TITLE_HOP2到達  ---
; --- までを検証する)。                                              ---
TITLE_BANK_A EQU 0
TITLE_BANK_B EQU 1
TITLE_INIT   EQU 04010h

INIT:
    ; combined_test.asm側のTRIGGER_GAME_OVERで既にDI済み・PSG無音化済み
    ; - 念のためここでも明示。H.TIMIフックは明示的にbare RET(BIOS
    ; デフォルト)へ戻してから安全にEIする(title_test.asmのWAIT_FOR_
    ; STARTと同じ防御策 - 以後GTTRIGでボタン入力を検出するために割り込み
    ; を有効化する必要があるが、Stage2自身の古いBGM_TICKフックが window
    ; Aの中身[このバンク]を誤実行するレースを閉じておく)。
    DI
    LD A,0C9h
    LD (HTIMI_HOOK),A
    EI

    ; (2026-09-07、実機ではなく自己レンダリング確認で発見・修正: 当初
    ; コード0-10[パターンジェネレータ先頭]へ無条件ロードしていたところ、
    ; 地形システム自体がまさにcode0-93[terrain_gen.pyのMAX_CODE=93]を
    ; 使っており、GAME OVERの瞬間に画面全体の地形/背景が全てMISSION
    ; FAILEDフォントの絵柄へ化けるレンダリング事故を実際に確認した -
    ; 「Stage2本編は二度と実行されないのでコードを自由に上書きしてよい」
    ; という判断はコード自体の再利用には正しいが、name table(どのマス
    ; がどのコードを表示するか)はGAME OVERの瞬間の最後のフレームの
    ; まま固定される、という点を見落としていた)。ending_text_gen.py
    ; ([GFEnding]"MISSION COMPLETED"表示)が実VRAM調査で確認済みの
    ; 「ボス戦専用、ボスが実際に描画されていない限り安全」なgroup12
    ; (codes96-103)+group18先頭3つ(codes144-146)へ変更 - 地形が使う
    ; code0-93と重ならない。"MISSION FAILED"の11グリフ(M,I,S,O,N,
    ; space,F,A,L,E,D)をcode96-103(8個)+144-146(3個)の2ブロックで
    ; ロードする。
    LD HL,GAMEOVER2_FONT_PATTERNS : LD DE,96*8 : LD BC,64 : CALL LDIRVM
    LD HL,GAMEOVER2_FONT_PATTERNS+64 : LD DE,144*8 : LD BC,24 : CALL LDIRVM
    LD HL,GAMEOVER2_FONT_COLOR : LD DE,200Ch : LD BC,1 : CALL LDIRVM   ; group12(96-103)
    LD HL,GAMEOVER2_FONT_COLOR+1 : LD DE,2012h : LD BC,1 : CALL LDIRVM ; group18(144-151)

    ; 自機の最終位置(TANK_X/TANK_Y_CUR)を起点に、既存のUPDATE_TANK_
    ; SPRITESと同じ4隅オフセット(+0/+16)へPAT_EXPLOSIONスプライトを
    ; 点滅表示する(10回、表示->ウェイト->非表示->ウェイト、1回あたり
    ; 約0.3秒 - 合計約3秒、"3秒表示"に対応)。
    LD B,10
GO_BLINK_LOOP:
    PUSH BC
    CALL GO_DRAW_EXPLOSION
    CALL GO_DELAY_SHORT
    CALL GO_HIDE_EXPLOSION
    CALL GO_DELAY_SHORT
    POP BC
    DJNZ GO_BLINK_LOOP

    ; 最後は表示したまま静止させる。
    CALL GO_DRAW_EXPLOSION

    ; "MISSION FAILED"メッセージを画面中央(row12,col9、14byte - 画面幅
    ; 32セルの中央に14byteを置くには(32-14)/2=9列目から)へ描画
    ; (DRAW_MISSION_SCREEN/DRAW_GAMEOVER_TEXTと同じ位置 - テキストのみ
    ; オーバーレイ、画面全体の黒塗りはしない)。CLAUDE.md「実機ハード
    ; ウェア制約」の恒久ルール通り、VDPへの連続転送はOTIR等を使わず
    ; 手動OUT+NOPループのみ。
    DI
    LD A,089h : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 1989h (row12,col9)
    NOP
    NOP
    LD HL,GAMEOVER2_MSG
    LD B,GAMEOVER2_MSG_LEN
GO_MSG_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ GO_MSG_LOOP
    EI

    ; "ボタンが押されるか10秒経過でタイトル画面に" - GO_DELAY_SHORT
    ; (約0.15秒)単位でGTTRIGをポーリング、10秒÷0.15秒 ~= 67回で
    ; タイムアウト。
    LD B,67
GO_WAIT_LOOP:
    PUSH BC
    LD A,1
    CALL GTTRIG
    OR A
    JR NZ,GO_TO_TITLE
    CALL GO_DELAY_SHORT
    POP BC
    DJNZ GO_WAIT_LOOP

GO_TO_TITLE:
    ; PSG全チャンネル無音化してからtitleへ2ホップトランポリン
    ; (combined_test.asm自身のTRIGGER_GAME_OVERと同じ手法、window B->
    ; window Aの順)。
    DI
    LD A,8 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,9 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A
    LD A,10 : OUT (PSG_ADDR),A : XOR A : OUT (PSG_DATA),A

    LD A,TITLE_BANK_B
    LD DE,7000h
    LD HL,GOTO_TITLE_HOP2
    JP BANKSWITCH_TRAMPOLINE_RAM
GOTO_TITLE_HOP2:
    LD A,TITLE_BANK_A
    LD DE,6000h
    LD HL,TITLE_INIT
    JP BANKSWITCH_TRAMPOLINE_RAM

; combined_test.asmと同じRAM上のトランポリン(既に設置済みのものを
; そのまま使う - このバンク自身では新規コピーしない、Stage2本編の
; INITが起動時に1度だけコピー済みのものが物理RAM上にそのまま残って
; いる)。
BANKSWITCH_TRAMPOLINE_RAM EQU 0F271h

; 自機の最終位置(TANK_X/TANK_Y_CUR)を中心に4隅(TL/TR/BL/BR、既存の
; UPDATE_TANK_SPRITESと同じ+0/+16オフセット)へPAT_EXPLOSION+
; EXPLOSION_COLORを書く。VDPアドレスは一度だけ設定し、以後は自動
; インクリメントに任せて16byte連続で書く(スロット0-3、SPRATR先頭 -
; 自機自身がこれまで使っていたスロットをそのまま転用、新規スロット
; 確保は不要)。Trashes: AF,BC,HL.
GO_DRAW_EXPLOSION:
    DI
    LD A,0 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(TANK_Y_CUR) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,EXPLOSION_COLOR : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_Y_CUR) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_X) : ADD A,16 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,EXPLOSION_COLOR : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_Y_CUR) : ADD A,16 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_X) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,EXPLOSION_COLOR : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_Y_CUR) : ADD A,16 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_X) : ADD A,16 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,EXPLOSION_COLOR : OUT (98h),A
    EI
    RET

; スロット0-3(16byte)をY=209(MSX標準の「以降のスプライトも含め全部
; 隠す」センチネル)+X=0/pat=0/col=0へ戻し、点滅の非表示側を作る。
; Trashes: AF,B,HL.
GO_HIDE_EXPLOSION:
    DI
    LD A,0 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD B,4
GO_HIDE_LOOP:
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    DJNZ GO_HIDE_LOOP
    EI
    RET

; 点滅1コマ分/ボタン待ちポーリング1回分の短いビジーウェイト
; (H.TIMI/実vblankには依存しない、Z80クロック直接カウント方式 -
; Stage1のMISSION_DELAY_3SECと同じ考え方)。B=160×内側ループ256回×
; 約13T =~532,480T-state、MSXのZ80クロック3.579545MHz固定で割ると
; 約0.149秒。厳密さは求めていないための概算値。
; Trashes: AF,BC.
GO_DELAY_SHORT:
    LD B,160
GO_DELAY_OUTER:
    LD C,0
GO_DELAY_INNER:
    DEC C
    JR NZ,GO_DELAY_INNER
    DJNZ GO_DELAY_OUTER
    RET

; "MISSION FAILED"フォント(M,I,S,O,N,space,F,A,L,E,D、11グリフ、
; tools/pixel_font_8x8.pyの_GLYPHS_ATTACHED/_GLYPHS_NEWと同じ値、
; python3 -c "...pixel_font_8x8.glyph_bytes(ch)..."で計算した値を
; そのまま転記)。前半8グリフ(M,I,S,O,N,space,F,A)はcode96-103
; (group12)、後半3グリフ(L,E,D)はcode144-146(group18先頭)へ
; ロードする(ending_text_gen.py[GFEnding]が実VRAM調査で確認済みの
; 「ボス戦専用、地形のcode0-93と重ならない安全な領域」を再利用 -
; 詳細は上のINIT側コメント参照)。
GAMEOVER2_FONT_PATTERNS:
    DB 198,238,254,254,214,198,198,198    ; M (code96)
    DB 48,48,48,48,48,48,48,48            ; I (code97)
    DB 126,254,224,112,60,14,254,252      ; S (code98)
    DB 124,254,198,198,198,198,254,124    ; O (code99)
    DB 198,230,246,254,222,206,198,198    ; N (code100)
    DB 0,0,0,0,0,0,0,0                    ; space (code101)
    DB 254,254,192,252,252,192,192,192    ; F (code102)
    DB 56,124,198,198,254,254,198,198     ; A (code103)
    DB 192,192,192,192,192,192,254,254    ; L (code144)
    DB 254,254,192,252,252,192,254,254    ; E (code145)
    DB 252,254,198,198,198,198,254,252    ; D (code146)
GAMEOVER2_FONT_PATTERNS_LEN EQU $ - GAMEOVER2_FONT_PATTERNS

; group12(codes96-103)+group18(codes144-151)の色を白文字/黒背景
; (0F1h)へ。
GAMEOVER2_FONT_COLOR:
    DB 0F1h,0F1h

; "MISSION FAILED" - M,I,S,S,I,O,N,space,F,A,I,L,E,D(14byte、
; row12/col9 center)。
GAMEOVER2_MSG:
    DB 96   ; M
    DB 97   ; I
    DB 98   ; S
    DB 98   ; S
    DB 97   ; I
    DB 99   ; O
    DB 100  ; N
    DB 101  ; space
    DB 102  ; F
    DB 103  ; A
    DB 97   ; I
    DB 144  ; L
    DB 145  ; E
    DB 146  ; D
GAMEOVER2_MSG_LEN EQU $ - GAMEOVER2_MSG
