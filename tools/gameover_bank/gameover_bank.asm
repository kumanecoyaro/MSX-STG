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
PSG_ADDR        EQU 0A0h
PSG_DATA        EQU 0A1h
LDIRVM          EQU 005Ch
GTTRIG          EQU 00D8h
HTIMI_HOOK      EQU 0FD9Fh

; "自機爆発はサウンドも欲しい"(2026-09-07): 実機フィードバック対応で
; 追加。src/CYBER SHMUP.asmのSOUND_DESTROY/combined_test.asmのSOUND_
; DESTROYと同じ「ノイズch A、周期20、音量15から手動で減衰」構成を、
; このバンク自身の中で完結する形で再実装(このバンクは他ファイルを
; CALLできない独立バンクのため、既存ルーチンの呼び出しではなく値だけ
; 再利用)。
MIXER_NOISE_A     EQU 0F1h  ; combined_test.asmと同じ値(noise A on, tone B/C enabled)
BOOM_NOISE_PERIOD EQU 20
SPR_WHITE_COLOR    EQU 0Fh
SPR_LIGHTRED_COLOR EQU 09h

; combined_test.asmと同じ値(group15、fg1/bg1の純黒ブランクタイル、
; "Mission Failedの行はブランクブラックで埋めてくれ"対応で使用)。
HUD_ROW_BLANK_CODE EQU 120

; "一度4つほどエフェクトが出るがその状態で停止しててStage1の様な連続
; 爆発しない"(2026-09-07、実機フィードバック対応): 4隅を同じ位置に
; 10回点滅させるだけだったため「同じ絵が点滅しているだけ」に見えて
; いた。src/CYBER SHMUP.asmのPLAYER_EXPL_UPDATE_ALL(自機を起点に
; ランダムオフセット・色を白/ライトレッドで交互に、を繰り返す)と同じ
; 考え方を、このバンクの単純な直列ループの中に持ち込む - 毎回の点滅で
; 位置をジッターさせ、色を交互にする。RNGの種はcombined_test.asm自身の
; スケジューリング用ワーク領域SPAWN2_NEXT_INDEX(GAME OVER以後は
; Stage2本編が二度と実行されないため確実に不要、この点はこのファイル
; 冒頭のコメント「RAM...は物理的に共有されているため...再利用する」の
; 方針と同じ)を再利用する。
GO_RNG EQU 0F19Bh

; (2026-09-07、実機フィードバック対応その3"4つ爆発を同時に飛ばすん
; じゃなく1個ずつバラバラにだ でその1回毎にサウンドだ 速度も遅いって
; 何回言わせんだよ 音出して1つ飛ばしてまた音出して1つ飛ばしての繰り
; 返し ボス爆発がそうなってんだろうが"): Round67/68の「4パーティクル
; 同時に直進飛翔」方式を全面撤回。src/CYBER SHMUP.asm自身のボス撃破
; 演出(BOSS_EXPL_UPDATE/BEU_FIRE)を実際に読み直したところ、その実態は
; 「移動するスプライト」ではなく「毎回ランダムな新しい位置に静止した
; 爆発を1個ポップさせ、毎回SOUND_DESTROYを1回鳴らし、次のポップまで
; TIMER=2フレームだけ待つ」という、飛翔ではなく高速連続ポップの
; 繰り返しだった - これが正しい参照実装。同じモデルへ全面書き換え:
; 1ポップ=(1)GO_ARM_BOOMで即座に音を鳴らす→(2)自機中心から
; ランダムオフセットの位置へPAT_EXPLOSIONを1個描画(ラウンドロビンで
; ATTRIBUTEスロット0-3を回すため、直近4ポップ分が画面上に同時に
; 残る「散らばった破片」の見た目になる、新規の消滅タイマー機構は
; 不要)→(3)短いウェイト、を合計NUM_POPS回繰り返す。GO_PX0を
; ラウンドロビンスロットindex、GO_PY0をポップ残数カウンタへ転用
; (GO_PX1-3/GO_PY1-3/GO_DIR0-3X/Yだった旧4パーティクル用スクラッチは
; もう不要)。
GO_SLOT_IDX EQU 0F19Ch  ; 0-3、次にポップを描くATTRIBUTEスロット(ラウンドロビン)
GO_POP_CTR  EQU 0F19Dh  ; 残りポップ数(NUM_POPSからカウントダウン)

; (2026-09-07、実機フィードバック対応"爆発音はステージ1、2ともに
; パーティクルの回数鳴らすんだよ"): 現在の音量(ポップごとにGO_ARM_BOOM
; で撃ち直され、次のポップまでの短いウェイト中に少しだけ減衰する)。
GO_BOOM_VOL EQU 0F1A7h

NUM_POPS      EQU 40   ; 未調整の初期値、実機での見え方次第で再調整 -
                        ; 「1個ずつ」化に伴い前回のNUM_BURSTS(20)から
                        ; 増量(1回あたりが軽くなった分、密度を維持)
GO_POP_JITTER EQU 16    ; 自機中心からのオフセット範囲、-8..+7px
                        ; (src/CYBER SHMUP.asmのPEUA_TRY_SPAWNと同じ
                        ; レンジ)

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

    ; RNGの種を自機の最終X座標から取る(プレイごとに変わる値、GO_RNG自身の
    ; 説明は上のEQU参照)。
    LD A,(TANK_X) : LD (GO_RNG),A

    ; 自機の最終位置(TANK_X/TANK_Y_CUR)を中心に、NUM_POPS回「音を鳴らし
    ; てから1個ポップさせ、短く待って次」を繰り返す(ボス撃破演出
    ; BOSS_EXPL_UPDATE/BEU_FIREと同じモデル、詳細はGO_EXPLOSION_
    ; SEQUENCE自身のコメント参照)。
    CALL GO_EXPLOSION_SEQUENCE

    ; "で爆発エフェクトが消えずのこったまま Mission Failedになってる
    ; で爆発エフェクトは消してくれ その後にMission Failed表示"
    ; (2026-09-07、実機フィードバック対応): 旧実装は最後にジッター無し
    ; の静止ポーズを表示したまま残しており、その上にMISSION FAILEDが
    ; オーバーレイされる形になっていた。明示的に非表示にしてから
    ; テキスト描画へ進む。
    CALL GO_HIDE_EXPLOSION

    ; "Mission Failedの行はブランクブラックで埋めてくれ"(2026-09-07、
    ; 実機フィードバック対応): 従来はrow12の中央14セルへメッセージを
    ; 上書きするだけで、その左右(col0-8/col23-31)には死亡直前の地形・
    ; 背景がそのまま残っていた。まずrow12を左端(col0)から32セル分
    ; HUD_ROW_BLANK_CODE(combined_test.asm自身のライフバー背景消去と
    ; 同じ、fg1/bg1の純黒タイル)で埋めてから、その中央にメッセージを
    ; 上書きする(合計32回のOUT、col0-8[9セル]blank→14セルメッセージ→
    ; col23-31[9セル]blank)。CLAUDE.md「実機ハードウェア制約」の恒久
    ; ルール通り、VDPへの連続転送はOTIR等を使わず手動OUT+NOPループのみ。
    DI
    LD A,080h : OUT (99h),A
    NOP
    NOP
    LD A,59h : OUT (99h),A      ; write address = 1980h (row12,col0)
    NOP
    NOP
    LD B,9
GO_MSG_PRE_BLANK:
    LD A,HUD_ROW_BLANK_CODE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    DJNZ GO_MSG_PRE_BLANK
    LD HL,GAMEOVER2_MSG
    LD B,GAMEOVER2_MSG_LEN
GO_MSG_LOOP:
    LD A,(HL) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    INC HL
    DJNZ GO_MSG_LOOP
    LD B,9
GO_MSG_POST_BLANK:
    LD A,HUD_ROW_BLANK_CODE : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    DJNZ GO_MSG_POST_BLANK
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

; NUM_POPS回、「音を鳴らす→自機中心付近のランダムな位置へPAT_EXPLOSION
; を1個ポップさせる→短く待つ」を繰り返す(BOSS_EXPL_UPDATE/BEU_FIREと
; 同じモデル - あちらは「毎回新しい位置に1個ポップ+毎回SOUND_DESTROY+
; TIMER=2フレームだけ待って次」の高速連続、"移動する飛翔"ではなく
; "高速に位置を変えて出現するポップ"の連続だった)。ATTRIBUTEスロット
; 0-3をラウンドロビンで使うため、直近4ポップ分が同時に画面上に残る -
; 新規の消滅タイマー機構を追加せずに「散らばった破片」の見た目になる。
; 色はポップごとに白/ライトレッドを交互に(Stage1のPLAYER_EXPL_UPDATE_
; ALLと同じ考え方)。
; Trashes: AF,BC,DE,HL。
GO_EXPLOSION_SEQUENCE:
    XOR A
    LD (GO_SLOT_IDX),A
    LD A,NUM_POPS : LD (GO_POP_CTR),A
GO_POP_LOOP:
    CALL GO_ARM_BOOM
    CALL GO_LAUNCH_ONE_POP
    CALL GO_STEP_BOOM_DECAY
    CALL GO_DELAY_TINY
    CALL GO_STEP_BOOM_DECAY
    CALL GO_DELAY_TINY
    LD A,(GO_POP_CTR) : DEC A : LD (GO_POP_CTR),A
    JR NZ,GO_POP_LOOP
    RET

; 1個のPAT_EXPLOSIONスプライトを、自機中心(TANK_X/TANK_Y_CUR)から
; ±GO_POP_JITTER/2pxのランダムオフセット位置へ、GO_SLOT_IDXが指す
; ATTRIBUTEスロット(0-3)で描く。描いた後GO_SLOT_IDXを次のスロットへ
; 進める(mod4)。色はGO_POP_CTRの最下位ビットで白/ライトレッドを交互に。
; Trashes: AF,BC,DE,HL。
GO_LAUNCH_ONE_POP:
    LD A,(GO_RNG) : ADD A,53 : LD (GO_RNG),A
    AND GO_POP_JITTER-1 : SUB GO_POP_JITTER/2 : LD D,A   ; dx
    LD A,(GO_RNG) : ADD A,53 : LD (GO_RNG),A
    AND GO_POP_JITTER-1 : SUB GO_POP_JITTER/2 : LD E,A   ; dy

    LD A,(GO_POP_CTR) : AND 1
    LD A,SPR_WHITE_COLOR
    JR Z,GLOP_COLOR_RESOLVED
    LD A,SPR_LIGHTRED_COLOR
GLOP_COLOR_RESOLVED:
    LD C,A

    LD A,(GO_SLOT_IDX)
    ADD A,A : ADD A,A                ; A = スロット*4(ATTRIBUTEレコードのバイトオフセット)
    DI
    OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD A,(TANK_Y_CUR) : ADD A,E : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,(TANK_X) : ADD A,D : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,PAT_EXPLOSION : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    LD A,C : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI

    LD A,(GO_SLOT_IDX) : INC A : AND 3 : LD (GO_SLOT_IDX),A
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

; GO_DELAY_SHORTの約1/8の短さ(~0.0186秒)。GO_PLAY_BOOM_SOUND自身の
; 手動減衰ステップ間隔専用 - GO_DELAY_SHORTをそのまま使うと16段の減衰
; だけで2秒を超えてしまい、爆発音が間延びしてしまうため専用に用意した。
; Trashes: AF,BC.
GO_DELAY_TINY:
    LD B,20
GO_DELAY_TINY_OUTER:
    LD C,0
GO_DELAY_TINY_INNER:
    DEC C
    JR NZ,GO_DELAY_TINY_INNER
    DJNZ GO_DELAY_TINY_OUTER
    RET

; "自機爆発はサウンドも欲しい"(2026-09-07、実機フィードバック対応)、
; 続けて"爆発音はステージ1、2ともにパーティクルの回数鳴らすんだよ"
; (2026-09-07、実機フィードバック対応その2): src/CYBER SHMUP.asm・
; combined_test.asm双方のSOUND_DESTROY(ノイズchannel A、周期20、音量15
; スタート)と同じ音作りを、このバンク自身の中で完結する形で再実装
; (このバンクは他ファイルをCALLできない独立バンクのため値だけ再利用、
; 既存ルーチンの呼び出しではない)。旧実装は全シーケンス開始時に1回
; だけ、専用の16段手動減衰ループ(~0.3秒)で完結する単発の効果音
; だったが、Stage1のPEUA_TRY_SPAWN(スポーンのたびに毎回SOUND_DESTROY)
; と同じ「パーティクル[バースト]の数だけ毎回鳴らす」設計に合わせて
; GO_ARM_BOOM(バースト開始時に音量15で撃ち直す)+GO_STEP_BOOM_DECAY
; (その後のBURST_FRAMESフレームループの中で毎回1段ずつ減衰させる、
; 専用の追加ウェイト無し)の2ルーチンへ分割。CLAUDE.md「実機ハード
; ウェア制約」の恒久ルール通り、ブロック転送命令は使わずOUT+DJNZの
; 手動ループのみ。
; Trashes: AF.
GO_ARM_BOOM:
    DI
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A
    LD A,6 : OUT (PSG_ADDR),A
    LD A,BOOM_NOISE_PERIOD : OUT (PSG_DATA),A
    LD A,15
    LD (GO_BOOM_VOL),A
    LD A,8 : OUT (PSG_ADDR),A
    LD A,15 : OUT (PSG_DATA),A
    EI
    RET

; GO_ARM_BOOMで撃ち直した音量(15)を、呼ばれるたびに2段ずつ0まで減衰
; させる(BURST_FRAMES=8回呼ばれる想定、15,13,11,9,7,5,3,1,(以後0)で
; ほぼバーストの飛翔と同じ時間で鳴り止む)。0に達した後は無音のまま
; 何もしない。Trashes: AF.
GO_STEP_BOOM_DECAY:
    LD A,(GO_BOOM_VOL)
    OR A
    RET Z
    SUB 2
    JR NC,GBD_STORE
    XOR A
GBD_STORE:
    LD (GO_BOOM_VOL),A
    DI
    LD A,8 : OUT (PSG_ADDR),A
    LD A,(GO_BOOM_VOL) : OUT (PSG_DATA),A
    EI
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
