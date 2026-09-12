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
; くる(DI済み)。ここからtitle(GLOBAL bank0/1)へ戻る際も同じ2ホップ
; トランポリン手法(window B→window Aの順)を使う。
; (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバー
; ジングルの実装で追記): 着地直後のwindow Bは(TRIGGER_GAME_OVER
; 自身が一切触れないため)Stage2自身のbank5のままだが、GO_INIT_BGM
; (下記)が一度だけbgm-dataバンク(global6)へ切り替えてジングルの
; RAMコピーを行う。このバンクは以後window Bを一切参照しないため、
; Stage2自身のbank5へ復帰させる必要はない(このバンクからStage2本編
; へ戻ることは無い設計のため)。
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

; (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバー
; ジングルをこのバンクにも実装): combined_test.asm自身のBGM_PERIOD_LO/
; HI_RAM・BGM_B/C_PTR等と物理的に同じRAM(0xC200〜0xCB0Eh)をそのまま
; 再利用する(Stage2本編がこのバンクへ来た時点で二度と実行されない
; ことは、このファイル冒頭のコメント「RAM...は物理的に共有されている
; ため...再利用する」の方針と同じ - tools/bgm_data/bgm_bank_gen.pyの
; song_constants("GAME_OVER", data_base=0xC200)の出力値と一致させる
; こと)。
GO_PERIOD_LO_RAM  EQU 0C200h
GO_PERIOD_HI_RAM  EQU 0C23Ch
GO_CHB_BASE       EQU 0C278h  ; GAME_OVERジングルchB(melody, 35byte)
GO_CHC_BASE       EQU 0C29Bh  ; GAME_OVERジングルchC(harmony, 15byte)
GO_BGM_B_PTR      EQU 0CB00h
GO_BGM_C_PTR      EQU 0CB02h
GO_BGM_B_TIMER    EQU 0CB04h
GO_BGM_C_TIMER    EQU 0CB05h
GO_BGM_B_REST     EQU 0CB06h
GO_BGM_C_REST     EQU 0CB07h
GO_BGM_B_ENV_LEVEL  EQU 0CB08h
GO_BGM_B_ENV_IDX    EQU 0CB09h
GO_BGM_B_ENV_CD     EQU 0CB0Ah
GO_BGM_B_DUTY_PHASE EQU 0CB0Bh
GO_BGM_C_ENV_LEVEL  EQU 0CB0Ch
GO_BGM_C_ENV_IDX    EQU 0CB0Dh
GO_BGM_C_ENV_CD     EQU 0CB0Eh
BGM_NOTE_REST     EQU 0FFh
BGM_END_MARK      EQU 0FDh  ; 一度きり再生・以後無音保持(LOOP_MARK対応は不要 - このバンクは曲をループしない)
BGM_ENV_LAST_INDEX EQU 15
BGM_B_DUTY_MASK    EQU 1
BGM_VOL_ATTEN      EQU 4
; bgm-dataバンク(tools/bgm_data/bgm_bank_gen.py)のGLOBAL番号。gameover_
; bank.asmは他ファイルと違い最初からComb globalの固定番号(TITLE_BANK_A/B
; と同じ考え方)で書かれているためstandalone/Comb間のパッチは不要
; (build_full_rom.pyのassemble_gameover_bank()参照、無加工でアセンブル
; される)。GAME_OVERジングルのバンク内オフセット(0x9428、chB35byte+
; chC15byte)もtools/bgm_data/bgm_bank_gen.pyの出力値と一致させること。
BGMDATA_BANK EQU 6
GO_SONG_SRC  EQU 09428h
GO_SONG_LEN  EQU 032h

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

; (2026-09-07、実機フィードバック対応その3"4つ爆発を同時に飛ばすん
; じゃなく1個ずつバラバラにだ でその1回毎にサウンドだ 速度も遅いって
; 何回言わせんだよ 音出して1つ飛ばしてまた音出して1つ飛ばしての繰り
; 返し ボス爆発がそうなってんだろうが"): Round67/68の「4パーティクル
; 同時に直進飛翔」方式を全面撤回。src/CYBER SHMUP.asm自身のボス撃破
; 演出(BOSS_EXPL_UPDATE/BEU_FIRE)を実際に読み直したところ、その実態は
; 「移動するスプライト」ではなく「毎回ランダムな新しい位置に静止した
; 爆発を1個ポップさせ、毎回SOUND_DESTROYを1回鳴らし、次のポップまで
; TIMER=2フレームだけ待つ」という、飛翔ではなく高速連続ポップの
; 繰り返しだった - これが正しい参照実装。
GO_SLOT_IDX EQU 0F19Ch  ; 0-3、次にポップを描くセル(ラウンドロビン、下記GO_SPARK_ROW/COL参照)
GO_POP_CTR  EQU 0F19Dh  ; 残りポップ数(NUM_POPSからカウントダウン)

; (2026-09-08、実機フィードバック対応"ステージ2の自機爆発は消すのが
; 早い 爆発中は表示してて終わる少し前に消すんだよ 今は爆発処置に入った
; 途端に消えてて不自然"): VRAM→PNGレンダリングで実際に1ポップずつ
; 確認したところ根本原因を特定 - GO_LAUNCH_ONE_POPは毎回ポップを
; TANK自身が使っているのと全く同じhwスプライトATTRIBUTEスロット0-3
; (UPDATE_TANK_SPRITES参照、自機の4象限がここに常駐)へラウンドロビンで
; 上書きしていたため、スロットが4つしか無くTANK自身も4つ全部を占有して
; いる以上、ポップ1回目の時点で既にTANK本体の1/4が消え、ポップ4回目
; (40ポップ中のわずか最初の4回、実測で200ms未満)で自機が完全に
; ポップ絵へ置き換わっていた - まさに「爆発処置に入った途端に消える」
; 症状の実体。この失敗パターンはこのプロジェクト自身が過去に一度
; 踏んでいる: round32のINIT_BOSS_EXPLOSION/BOSS_EXPL_SPARK自身の
; コメント「スプライトで描画すると消えてしまうんでBGで」-
; ボス本体も同様にスプライト予算が足りず、追加のスプライトで爆発を
; 描くとボス自身が競合で消えてしまうため、当時からBGセル方式に変更
; 済みだった。同じ解決策をこのバンクにも適用: TANK自身のスプライト
; (スロット0-3)はポップの間一切触れず、ポップは自機の名前テーブル
; セルの周囲4箇所(斜め方向、GO_PREPARE_SPARKSが一度だけ計算・退避)
; へBGセルとして描く方式に全面変更。TANKのスプライトを実際に隠す
; (Y=209)のは、全ポップが終わった後の1回だけ(GO_HIDE_EXPLOSION) -
; これで「爆発中は自機が表示されたまま、終わってから消える」という
; 指示通りの順序になる。
GO_SPARK_WHITE_CODE EQU 96    ; group12 - 直後にMISSION FAILEDの"M"へ
                              ; 上書きされる(時間差での使い回し、コード
                              ; 自体は同じ96のまま、GAMEOVER2_FONT_
                              ; PATTERNSのLDIRVMが自然に上書きする)
GO_SPARK_RED_CODE   EQU 147   ; group18 - "L"(144)/"E"(145)/"D"(146)が
                              ; 使わない残り5コードのうちの1つ、以後
                              ; 名前テーブルからは二度と参照されない
                              ; ("MISSION FAILED"は144-146のみ使用)
GO_SPARK_RED_COLORBYTE EQU 081h  ; fg8(medium red、EXPLOSION_COLORと
                                 ; 同じ)/bg1(black) - group18の色は
                                 ; 爆発中だけ一時的にこの値、その後の
                                 ; フォント読込(既存のGAMEOVER2_FONT_
                                 ; COLOR+1書き込み)が白へ戻す

; GO_PREPARE_SPARKSが一度だけ計算する、ラウンドロビン4セルぶんの
; (行,列)と、そこに元々あった名前テーブルの値(GO_RESTORE_SPARKSが
; 爆発終了後に書き戻す為の退避先)。TANK自身の名前テーブル座標を基準に
; 斜め4方向へ1セルずつオフセットするだけの固定配置(自機は死亡後
; 二度と動かないため、一度計算すれば良い)。
GO_SPARK_ROW    EQU 0F1A8h  ; 4 bytes
GO_SPARK_COL    EQU 0F1ACh  ; 4 bytes
GO_SPARK_SAVED  EQU 0F1B0h  ; 4 bytes
GPS_BASE_COL    EQU 0F1B4h  ; GO_PREPARE_SPARKSだけが使うスクラッチ(TANK_X>>3)
GPS_BASE_ROW    EQU 0F1B5h  ; 同上(TANK_Y_CUR>>3)
GLOP_CODE       EQU 0F1B6h  ; GO_LAUNCH_ONE_POPだけが使うスクラッチ(このポップで描く
                            ; コード番号の一時保存 - Cレジスタは名前テーブル
                            ; アドレス計算のBCペアで使い切ってしまうため)

; (2026-09-07、実機フィードバック対応"爆発音はステージ1、2ともに
; パーティクルの回数鳴らすんだよ"): 現在の音量(ポップごとにGO_ARM_BOOM
; で撃ち直され、次のポップまでの短いウェイト中に少しだけ減衰する)。
GO_BOOM_VOL EQU 0F1A7h

NUM_POPS      EQU 40   ; 未調整の初期値、実機での見え方次第で再調整 -
                        ; 「1個ずつ」化に伴い前回のNUM_BURSTS(20)から
                        ; 増量(1回あたりが軽くなった分、密度を維持)

; --- Comb globalバンク番号。standaloneでは0/1は無意味(単独バンクの ---
; --- ためtitleへは戻れない、テストは戻る直前のGOTO_TITLE_HOP2到達  ---
; --- までを検証する)。                                              ---
TITLE_BANK_A EQU 0
TITLE_BANK_B EQU 1
TITLE_INIT   EQU 04010h

INIT:
    ; combined_test.asm側のTRIGGER_GAME_OVERで既にDI済み・PSG無音化済み
    ; - 念のためここでも明示。
    ; (2026-09-08、実機フィードバック対応"鳴ってるが最初の方が自機爆発音
    ; で消えてる 爆発が終わってからMission Failed表示して音消してゲーム
    ; オーバーサウンドだろうが"): 前Round(74)はGO_INIT_BGM(ジングルの
    ; RAMコピー+H.TIMIフック設置)をINIT冒頭で即座に呼んでいたため、
    ; H.TIMI駆動のジングル再生が爆発シーケンス(GO_EXPLOSION_SEQUENCE、
    ; チャンネルAのブーム音)と最初から並走し、ジングルの出だしが爆発音に
    ; 埋もれていた。正しい順序は「爆発→(消音+)MISSION FAILED表示→
    ; ジングル開始」- ここではまだHTIMI_HOOKを安全なbare RET(BIOS
    ; デフォルト)へ戻すだけに留め(GO_INIT_BGMは呼ばない、= ジングルは
    ; まだ鳴らさない)、以後の爆発シーケンス・テキスト描画がそれぞれ
    ; 自前のDI/EIブラケットで割り込みを一時的に再許可しても、その間
    ; H.TIMIが安全なbare RETを叩くだけで済むようにする(title_test.asmの
    ; WAIT_FOR_STARTと同じ「フック未確定の間はbare RET」防御パターン)。
    ; 実際のGO_INIT_BGM呼び出しはMISSION FAILEDテキスト描画の直後
    ; (下記)へ移設した。
    DI
    LD A,0C9h
    LD (HTIMI_HOOK),A
    EI

    ; (2026-09-08、実機フィードバック対応"爆発中は表示してて終わる少し
    ; 前に消すんだよ 今は爆発処置に入った途端に消えてて不自然"への対応で
    ; 全面再設計): 実際のMISSION FAILEDフォント読込は、爆発シーケンスが
    ; 終わった後(下記)へ移動した - 爆発中はcode96(group12)/code147
    ; (group18)を「スパーク」の絵として一時的に使い回し、爆発が終わって
    ; セルを元に戻した後で初めて本物のフォントに差し替える、という
    ; GFEnding(ending_text_gen.py)と同じ「時間差でのVRAMコード使い回し」
    ; を踏襲している。group12/18の色だけはここで先に確定させておく -
    ; group12は爆発のスパーク(白)もその後の"M"の文字色も同じ白なので
    ; 一度書けば足りる。group18は爆発中だけ赤にしたいので、白は後段の
    ; フォント読込時(既存のGAMEOVER2_FONT_COLOR+1書き込み)に任せる。
    LD HL,GAMEOVER2_FONT_COLOR : LD DE,200Ch : LD BC,1 : CALL LDIRVM   ; group12(96-103) = white
    LD HL,GO_SPARK_RED_COLOR   : LD DE,2012h : LD BC,1 : CALL LDIRVM   ; group18(144-151) = red (爆発中だけ)

    ; スパーク自身の絵柄(EXPLOSION_PATTERNの左上8x8象限と同じビット
    ; パターン、combined_test.asm自身の値をそのまま転記)を白コード・
    ; 赤コードの両方へロード - 色は上のcolor tableで分かれているので
    ; 絵柄自体は共有できる。
    LD HL,GO_SPARK_PATTERN : LD DE,GO_SPARK_WHITE_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,GO_SPARK_PATTERN : LD DE,GO_SPARK_RED_CODE*8   : LD BC,8 : CALL LDIRVM

    ; 自機の最終位置(TANK_X/TANK_Y_CUR)を中心に、NUM_POPS回「音を鳴らし
    ; てから1個ポップさせ、短く待って次」を繰り返す(ボス撃破演出
    ; BOSS_EXPL_UPDATE/BEU_FIREと同じモデル、詳細はGO_EXPLOSION_
    ; SEQUENCE自身のコメント参照)。TANK自身のスプライトはこの間
    ; 一切触れない - 爆発はTANKの周囲4セルにBGスパークとして描かれる
    ; だけで、自機本体は最後(GO_HIDE_EXPLOSION)まで表示され続ける。
    CALL GO_EXPLOSION_SEQUENCE

    ; "で爆発エフェクトが消えずのこったまま Mission Failedになってる
    ; で爆発エフェクトは消してくれ その後にMission Failed表示"
    ; (2026-09-07、実機フィードバック対応)。続けて"爆発中は表示してて
    ; 終わる少し前に消すんだよ"(2026-09-08、実機フィードバック対応)
    ; - GO_HIDE_EXPLOSIONは(1)4つのスパークセルを元の絵に戻し、
    ; (2)ここで初めてTANK自身のスプライト(スロット0-3)をY=209で隠し、
    ; (3)爆発音を確実に無音化する。自機が「表示されたまま爆発し、
    ; 終わった瞬間に消える」という指示通りの順序はこれで実現される。
    CALL GO_HIDE_EXPLOSION

    ; ここでようやく本物のMISSION FAILEDフォントをロードする - code96
    ; (スパーク白と共用済み、"M"へ自然に上書きされる)・code144-146
    ; ("L","E","D"、スパークとは別コード)。group18の色もここで白へ
    ; 戻す(既存のGAMEOVER2_FONT_COLOR+1書き込み、爆発中の赤を上書き)。
    ; どちらのグループも、この時点でスパークが表示していたセル自体は
    ; 直前のGO_HIDE_EXPLOSIONで既に元の絵へ復元済みなので、ここで
    ; スパーク用コードの中身を差し替えても画面上には一切影響しない。
    LD HL,GAMEOVER2_FONT_PATTERNS : LD DE,96*8 : LD BC,64 : CALL LDIRVM
    LD HL,GAMEOVER2_FONT_PATTERNS+64 : LD DE,144*8 : LD BC,24 : CALL LDIRVM
    LD HL,GAMEOVER2_FONT_COLOR+1 : LD DE,2012h : LD BC,1 : CALL LDIRVM ; group18(144-151) = white

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

    ; (2026-09-08、実機フィードバック対応"爆発が終わってからMission
    ; Failed表示して音消してゲームオーバーサウンドだろうが"): MISSION
    ; FAILEDが画面に出た直後、ここで初めてゲームオーバージングルの
    ; RAMコピー+H.TIMIフック(GO_BGM_TICK)設置を行う - これより前は
    ; HTIMI_HOOKが上のbare RETのままなので、爆発シーケンス中に何度も
    ; 開閉するEI窓を挟んでもジングルは絶対に鳴らない。GO_INIT_BGM自体は
    ; 複数命令にまたがる状態遷移(window B切替+LDIR+制御変数初期化+
    ; フック設置)のため、他ファイルのINIT_BGM群と同じくDI/EIで囲む。
    DI
    CALL GO_INIT_BGM
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

; NUM_POPS回、「音を鳴らす→自機周囲の固定4セルの1つへBGスパークを
; 描く→短く待つ」を繰り返す(BOSS_EXPL_UPDATE/BEU_FIREと同じモデル -
; あちらは「毎回新しい位置に1個ポップ+毎回SOUND_DESTROY+TIMER=2フレーム
; だけ待って次」の高速連続、"移動する飛翔"ではなく"高速に位置を変えて
; 出現するポップ"の連続だった)。GO_PREPARE_SPARKSで4セルの位置と退避
; データを一度だけ計算してから、あとはそのセルをラウンドロビンで
; 使い回す。TANK自身のhwスプライト(スロット0-3)は最初から最後まで
; 一切触れない(2026-09-08、実機フィードバック対応で全面再設計 - 詳細は
; GO_SLOT_IDXの上のコメント参照)。
; Trashes: AF,BC,DE,HL。
GO_EXPLOSION_SEQUENCE:
    CALL GO_PREPARE_SPARKS
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

; TANK自身の名前テーブル座標(BASE_COL=TANK_X>>3,BASE_ROW=TANK_Y_CUR>>3)
; を基準に、斜め4方向へ1セルずつオフセットした固定スパーク位置を
; GO_SPARK_ROW/COL(4要素ずつ)へ書き込み、GO_LAUNCH_ONE_POPが上書きする
; 前の元の絵をGO_SPARK_SAVEDへ退避する。自機は死亡後もう動かないため
; 一度計算すれば爆発シーケンスの間ずっと使い回せる。名前テーブルの
; 範囲外(0-31列/0-23行)へはみ出さないよう、はみ出す側だけ元のTANK側
; セルへクランプする(実際のTANKの可動範囲では起こり得ない想定だが、
; このファイルの他のオフセット計算[GO_POP_JITTERのクランプ等]と同じ
; 防御的な作法)。
; Trashes: AF,BC,DE,HL.
GO_PREPARE_SPARKS:
    LD A,(TANK_X) : SRL A : SRL A : SRL A : LD (GPS_BASE_COL),A
    LD A,(TANK_Y_CUR) : SRL A : SRL A : SRL A : LD (GPS_BASE_ROW),A

    ; slot0: col-1,row-1
    LD A,(GPS_BASE_COL) : OR A : JR Z,GPS0_COL_OK : DEC A
GPS0_COL_OK:
    LD (GO_SPARK_COL+0),A
    LD A,(GPS_BASE_ROW) : OR A : JR Z,GPS0_ROW_OK : DEC A
GPS0_ROW_OK:
    LD (GO_SPARK_ROW+0),A
    LD C,0 : CALL GPS_SAVE_SLOT

    ; slot1: col+1,row-1
    LD A,(GPS_BASE_COL) : CP 31 : JR Z,GPS1_COL_OK : INC A
GPS1_COL_OK:
    LD (GO_SPARK_COL+1),A
    LD A,(GPS_BASE_ROW) : OR A : JR Z,GPS1_ROW_OK : DEC A
GPS1_ROW_OK:
    LD (GO_SPARK_ROW+1),A
    LD C,1 : CALL GPS_SAVE_SLOT

    ; slot2: col-1,row+1
    LD A,(GPS_BASE_COL) : OR A : JR Z,GPS2_COL_OK : DEC A
GPS2_COL_OK:
    LD (GO_SPARK_COL+2),A
    LD A,(GPS_BASE_ROW) : CP 23 : JR Z,GPS2_ROW_OK : INC A
GPS2_ROW_OK:
    LD (GO_SPARK_ROW+2),A
    LD C,2 : CALL GPS_SAVE_SLOT

    ; slot3: col+1,row+1
    LD A,(GPS_BASE_COL) : CP 31 : JR Z,GPS3_COL_OK : INC A
GPS3_COL_OK:
    LD (GO_SPARK_COL+3),A
    LD A,(GPS_BASE_ROW) : CP 23 : JR Z,GPS3_ROW_OK : INC A
GPS3_ROW_OK:
    LD (GO_SPARK_ROW+3),A
    LD C,3 : CALL GPS_SAVE_SLOT
    RET

; C=スロット番号(0-3)。GO_SPARK_ROW+C/GO_SPARK_COL+Cから名前テーブル
; アドレスを計算し、そこに現在描かれているコードを生のVRAM読み出しで
; 取得してGO_SPARK_SAVED+Cへ退避する(LDIRVM/WRTVRMはROM/RAM->VRAM専用
; の書き込みBIOSのため、逆方向の読み出しは素のOUT×2+IN (98h)で行う -
; MSX標準のVRAMシーケンシャルリード手順、書き込み時と違い高位バイトの
; bit6[0x40]は立てない)。
; Trashes: AF,DE,HL. Bは呼び出し前に0であること(C単体をBCとして使う)。
GPS_SAVE_SLOT:
    LD B,0
    LD HL,GO_SPARK_ROW : ADD HL,BC : LD A,(HL)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL   ; row*32
    LD DE,1800h : ADD HL,DE
    PUSH HL
    LD HL,GO_SPARK_COL : ADD HL,BC : LD A,(HL)
    POP HL
    LD D,0 : LD E,A
    ADD HL,DE                     ; HL = 1800h+row*32+col
    LD A,L : OUT (99h),A
    LD A,H : AND 3Fh : OUT (99h),A   ; read mode (bit6=0)
    IN A,(98h)
    LD HL,GO_SPARK_SAVED : ADD HL,BC : LD (HL),A
    RET

; 1個のBGスパークを、GO_SLOT_IDXが指す固定セル(GO_SPARK_ROW/COL、
; GO_PREPARE_SPARKSが計算済み)へ描く。描いた後GO_SLOT_IDXを次のスロット
; へ進める(mod4)。色はGO_POP_CTRを2bit右シフトしたビットで白/ライト
; レッドを4ポップ(1ラウンドロビン周)ごとに交互に(Stage1のPLAYER_EXPL_
; UPDATE_ALLと同じ「白/ライトレッド交互」という考え方を、4セル固定
; 配置でも視認できる形に適用)。
; Trashes: AF,BC,DE,HL.
GO_LAUNCH_ONE_POP:
    LD A,(GO_POP_CTR) : SRL A : SRL A : AND 1
    LD A,GO_SPARK_WHITE_CODE
    JR Z,GLOP_CODE_RESOLVED
    LD A,GO_SPARK_RED_CODE
GLOP_CODE_RESOLVED:
    LD (GLOP_CODE),A               ; 描くコードを一時退避(下でCレジスタを
                                    ; 名前テーブルの添字計算に使い切るため)

    LD A,(GO_SLOT_IDX) : LD C,A : LD B,0
    LD HL,GO_SPARK_ROW : ADD HL,BC : LD A,(HL)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL   ; row*32
    LD DE,1800h : ADD HL,DE
    PUSH HL
    LD HL,GO_SPARK_COL : ADD HL,BC : LD A,(HL)
    POP HL
    LD D,0 : LD E,A
    ADD HL,DE                     ; HL = このスロットの名前テーブルアドレス

    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : AND 3Fh : OR 40h : OUT (99h),A   ; write mode
    NOP
    NOP
    LD A,(GLOP_CODE) : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    EI

    LD A,(GO_SLOT_IDX) : INC A : AND 3 : LD (GO_SLOT_IDX),A
    RET

; GO_PREPARE_SPARKSが退避した4セルぶんの元の絵をそのまま書き戻す
; (GO_HIDE_EXPLOSIONの一部として、TANK自身の見た目を隠す直前に呼ぶ)。
; Trashes: AF,BC,DE,HL.
GO_RESTORE_SPARKS:
    LD C,0 : CALL GRS_ONE_SLOT
    LD C,1 : CALL GRS_ONE_SLOT
    LD C,2 : CALL GRS_ONE_SLOT
    LD C,3 : CALL GRS_ONE_SLOT
    RET

; C=スロット番号(0-3)。GPS_SAVE_SLOTと同じアドレス計算を使い、今度は
; GO_SPARK_SAVED+Cの値を書き戻す(素のOUT×3、書き込みモード)。
; Trashes: AF,DE,HL. Bは呼び出し前に0であること。
GRS_ONE_SLOT:
    LD B,0
    LD HL,GO_SPARK_ROW : ADD HL,BC : LD A,(HL)
    LD H,0 : LD L,A
    ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL : ADD HL,HL
    LD DE,1800h : ADD HL,DE
    PUSH HL
    LD HL,GO_SPARK_COL : ADD HL,BC : LD A,(HL)
    POP HL
    LD D,0 : LD E,A
    ADD HL,DE
    PUSH HL
    LD HL,GO_SPARK_SAVED : ADD HL,BC : LD A,(HL)   ; A = 元のコード
    LD B,A
    POP HL
    DI
    LD A,L : OUT (99h),A
    NOP
    NOP
    LD A,H : AND 3Fh : OR 40h : OUT (99h),A
    NOP
    NOP
    LD A,B : OUT (98h),A
    EI
    RET

; (2026-09-08、実機フィードバック対応、"ステージ2の自機爆発で音が
; 出っぱなしでMission Failedになってる 消してからゲームオーバーに
; しろ 音の消し忘れ多すぎだろうが"): GO_ARM_BOOM/GO_STEP_BOOM_DECAY
; はポップごとに音量15へ撃ち直してから2段(15→13→11)しか減衰させず、
; 次のポップの頭でまた15へ撃ち直されるため、シーケンス全体を通じて
; R8(チャンネルA音量)が0に達することは一度も無い - 最後のポップの
; 後もR8=11のまま誰にも触れられず、MISSION FAILED表示中もずっと
; 鳴り続けていた。爆発演出の後片付けとして、ここでR8=0を明示的に
; 書き込み、テキスト表示に進む前に確実に無音化する。続けて4つの
; スパークセルを元の絵に戻し(GO_RESTORE_SPARKS)、最後にTANK自身の
; スプライト(スロット0-3)をY=209(MSX標準の「以降のスプライトも含め
; 全部隠す」センチネル)で隠す - これが自機の見た目が消える唯一の
; タイミングであり、"爆発中は表示してて終わる少し前に消す"を文字通り
; 実現する(2026-09-08、実機フィードバック対応で全面再設計 - 詳細は
; GO_SLOT_IDXの上のコメント参照)。
; Trashes: AF,BC,DE,HL.
GO_HIDE_EXPLOSION:
    DI
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A   ; channel A (boom SE) volume=0 - GO_STEP_BOOM_DECAY never reaches 0 on its own
    EI
    CALL GO_RESTORE_SPARKS
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

; (2026-09-08、"当たり前だろ 鳴らすようにしろ" - ゲームオーバー
; ジングルをこのバンクにも実装): 一度だけbgm-dataバンク(global6)へ
; windowBを切り替え、周期テーブル+GAME_OVERジングルのchB/chC(50byte)
; をcombined_test.asm自身のBGM RAM(GO_PERIOD_LO/HI_RAM・GO_CHB/CHC_
; BASE、Stage2本編が二度と実行されないため安全に再利用)へLDIRしてから
; 元のwindow B(Stage2自身のbank5)へは戻さない - このバンクは以後
; window Bを一切参照しないため復帰は不要(SWITCH_TO_CHARDATA_BANK等の
; 「必ず自分のbankへ復帰する」パターンとは違い、このバンクは最初から
; 最後まで単発利用)。続けて制御変数を全てゼロクリアし、BGM_B/C_PTRを
; ジングルの先頭へ、最後に本物のH.TIMIフック(GO_BGM_TICK)を設置する -
; INIT側がこの直後にEIするまでは割り込みは一切発生しない。
; Trashes: AF,BC,DE,HL.
GO_INIT_BGM:
    LD A,BGMDATA_BANK
    LD (7000h),A
    LD HL,08000h : LD DE,GO_PERIOD_LO_RAM : LD BC,078h : LDIR   ; 周期テーブル(60note*2)
    LD HL,GO_SONG_SRC : LD DE,GO_CHB_BASE : LD BC,GO_SONG_LEN : LDIR  ; GAME_OVER chB+chC

    LD HL,GO_CHB_BASE
    LD (GO_BGM_B_PTR),HL
    XOR A
    LD (GO_BGM_B_TIMER),A
    LD (GO_BGM_B_REST),A
    LD (GO_BGM_B_ENV_LEVEL),A
    LD (GO_BGM_B_ENV_IDX),A
    LD (GO_BGM_B_ENV_CD),A
    LD (GO_BGM_B_DUTY_PHASE),A
    LD HL,GO_CHC_BASE
    LD (GO_BGM_C_PTR),HL
    LD (GO_BGM_C_TIMER),A
    LD (GO_BGM_C_REST),A
    LD (GO_BGM_C_ENV_LEVEL),A
    LD (GO_BGM_C_ENV_IDX),A
    LD (GO_BGM_C_ENV_CD),A

    ; R7ミキサー: tone B/C有効+noise A有効(MIXER_NOISE_A、GO_ARM_BOOMも
    ; 同じ値を毎回書くが、爆発音より先にBGMが鳴り始める余地があるため
    ; ここでも明示的に一度書いておく)。
    LD A,7 : OUT (PSG_ADDR),A
    LD A,MIXER_NOISE_A : OUT (PSG_DATA),A

    LD A,0C3h                     ; JP nn opcode
    LD (HTIMI_HOOK),A
    LD HL,GO_BGM_TICK
    LD (HTIMI_HOOK+1),HL
    RET

; H.TIMIフック本体(実VBlank駆動)。GAME_OVERジングルは2パート(chB/chC)
; のみ・BGM_END_MARK方式(一度きり再生、以後無音保持) - LOOP_MARK対応は
; 不要なため、Stage1/Stage2/Titleの同名ドライバよりわずかに単純。
GO_BGM_TICK:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    CALL GO_BGMT_UPDATE_B
    CALL GO_BGMT_UPDATE_C
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; チャンネルB(R2/R3 tone、R9 volume、BELL形状+デューティ50%)。
GO_BGMT_UPDATE_B:
    LD A,(GO_BGM_B_TIMER)
    OR A
    JR Z,GO_BGMT_UB_NEWROW
    DEC A
    LD (GO_BGM_B_TIMER),A
    JR GO_BGMT_UB_ENV_STEP
GO_BGMT_UB_NEWROW:
    LD HL,(GO_BGM_B_PTR)
    LD A,(HL)
    CP BGM_END_MARK
    JR Z,GO_BGMT_UB_SETREST    ; 一度きりの終了 - PTRを進めず無音を保持し続ける
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (GO_BGM_B_PTR),HL
    DEC A                          ; round40 off-by-one修正(他ファイルと同じ)
    LD (GO_BGM_B_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,GO_BGMT_UB_SETREST
    XOR A
    LD (GO_BGM_B_REST),A
    LD E,C : LD D,0
    LD HL,GO_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,GO_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,2 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,3 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,GO_BGM_ENV_BELL_TABLE
    LD A,(HL) : LD (GO_BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (GO_BGM_B_ENV_CD),A
    XOR A : LD (GO_BGM_B_ENV_IDX),A
    LD A,BGM_B_DUTY_MASK : LD (GO_BGM_B_DUTY_PHASE),A
    JR GO_BGMT_UB_ENV_WRITE
GO_BGMT_UB_SETREST:
    LD A,1
    LD (GO_BGM_B_REST),A
    LD A,9 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
GO_BGMT_UB_ENV_STEP:
    LD A,(GO_BGM_B_REST)
    OR A
    RET NZ
    LD A,(GO_BGM_B_ENV_CD)
    OR A
    JR Z,GO_BGMT_UB_ENV_ADVANCE
    DEC A
    LD (GO_BGM_B_ENV_CD),A
    JR GO_BGMT_UB_ENV_WRITE
GO_BGMT_UB_ENV_ADVANCE:
    LD A,(GO_BGM_B_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,GO_BGMT_UB_ENV_WRITE
    INC A
    LD (GO_BGM_B_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,GO_BGM_ENV_BELL_TABLE
    ADD HL,DE
    LD A,(HL) : LD (GO_BGM_B_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,GO_BGMT_UB_ENV_WRITE
    DEC A
    LD (GO_BGM_B_ENV_CD),A
GO_BGMT_UB_ENV_WRITE:
    LD A,(GO_BGM_B_DUTY_PHASE)
    INC A
    LD (GO_BGM_B_DUTY_PHASE),A
    AND BGM_B_DUTY_MASK
    LD B,0
    JR NZ,GO_BGMT_UB_ENV_OUT
    LD A,(GO_BGM_B_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,GO_BGMT_UB_ATTEN_OK
    XOR A
GO_BGMT_UB_ATTEN_OK:
    LD B,A
GO_BGMT_UB_ENV_OUT:
    LD A,9 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    RET

; チャンネルC(R4/R5 tone、R10 volume、LINEAR形状+デューティOFF)。
GO_BGMT_UPDATE_C:
    LD A,(GO_BGM_C_TIMER)
    OR A
    JR Z,GO_BGMT_UC_NEWROW
    DEC A
    LD (GO_BGM_C_TIMER),A
    JR GO_BGMT_UC_ENV_STEP
GO_BGMT_UC_NEWROW:
    LD HL,(GO_BGM_C_PTR)
    LD A,(HL)
    CP BGM_END_MARK
    JR Z,GO_BGMT_UC_SETREST
    LD C,A
    INC HL
    LD A,(HL)
    INC HL
    LD (GO_BGM_C_PTR),HL
    DEC A
    LD (GO_BGM_C_TIMER),A
    LD A,C
    CP BGM_NOTE_REST
    JR Z,GO_BGMT_UC_SETREST
    XOR A
    LD (GO_BGM_C_REST),A
    LD E,C : LD D,0
    LD HL,GO_PERIOD_LO_RAM : ADD HL,DE : LD A,(HL) : LD B,A
    LD HL,GO_PERIOD_HI_RAM : ADD HL,DE : LD A,(HL) : LD C,A
    LD A,4 : OUT (PSG_ADDR),A
    LD A,B : OUT (PSG_DATA),A
    LD A,5 : OUT (PSG_ADDR),A
    LD A,C : OUT (PSG_DATA),A
    LD HL,GO_BGM_ENV_LINEAR_TABLE
    LD A,(HL) : LD (GO_BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL) : DEC A : LD (GO_BGM_C_ENV_CD),A
    XOR A : LD (GO_BGM_C_ENV_IDX),A
    JR GO_BGMT_UC_ENV_WRITE
GO_BGMT_UC_SETREST:
    LD A,1
    LD (GO_BGM_C_REST),A
    LD A,10 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A
    RET
GO_BGMT_UC_ENV_STEP:
    LD A,(GO_BGM_C_REST)
    OR A
    RET NZ
    LD A,(GO_BGM_C_ENV_CD)
    OR A
    JR Z,GO_BGMT_UC_ENV_ADVANCE
    DEC A
    LD (GO_BGM_C_ENV_CD),A
    JR GO_BGMT_UC_ENV_WRITE
GO_BGMT_UC_ENV_ADVANCE:
    LD A,(GO_BGM_C_ENV_IDX)
    CP BGM_ENV_LAST_INDEX
    JR Z,GO_BGMT_UC_ENV_WRITE
    INC A
    LD (GO_BGM_C_ENV_IDX),A
    LD L,A : LD H,0
    ADD HL,HL
    LD DE,GO_BGM_ENV_LINEAR_TABLE
    ADD HL,DE
    LD A,(HL) : LD (GO_BGM_C_ENV_LEVEL),A
    INC HL
    LD A,(HL)
    OR A
    JR Z,GO_BGMT_UC_ENV_WRITE
    DEC A
    LD (GO_BGM_C_ENV_CD),A
GO_BGMT_UC_ENV_WRITE:
    LD A,10 : OUT (PSG_ADDR),A
    LD A,(GO_BGM_C_ENV_LEVEL)
    SUB BGM_VOL_ATTEN
    JR NC,GO_BGMT_UC_ATTEN_OK
    XOR A
GO_BGMT_UC_ATTEN_OK:
    OUT (PSG_DATA),A
    RET

; BELL/LINEAR: 他の全ファイル(src/CYBER SHMUP.asm、combined_test.asm、
; title_test.asm)と全く同一のパラメータ("音色はゲーム中と同じでいいわ"
; の指示通り、このバンクだけ別の音にしない)。
GO_BGM_ENV_BELL_TABLE:
    DB 15,3,14,4,13,5,12,6,11,6,10,6,9,7,8,9,7,9,6,11,5,13,4,16,3,22,2,33,1,71,0,0
GO_BGM_ENV_LINEAR_TABLE:
    DB 15,2,14,3,13,2,12,3,11,2,10,3,9,3,8,3,7,2,6,3,5,3,4,2,3,3,2,2,1,3,0,0

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

; 爆発中のBGスパーク自身の絵柄。combined_test.asm自身のEXPLOSION_
; PATTERN(左上8x8象限、色8=medium redのスプライトと同じ絵)のバイト列を
; そのまま転記 - このバンクは独立バンクのため他ファイルのラベルを直接
; 参照できず、値だけコピーする(GAMEOVER2_FONT_PATTERNSがtools/pixel_
; font_8x8.pyの値を転記しているのと同じ作法)。
GO_SPARK_PATTERN:
    DB 084h,048h,000h,002h,049h,084h,020h,003h

; group18(codes144-151)の色を、爆発中だけ一時的にGO_SPARK_RED_
; COLORBYTE(赤文字/黒背景)へ - フォント読込時のGAMEOVER2_FONT_COLOR+1
; 書き込みが白へ戻す。
GO_SPARK_RED_COLOR:
    DB GO_SPARK_RED_COLORBYTE

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
