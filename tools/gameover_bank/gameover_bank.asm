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
; ATTRIBUTEスロットを回すため、直近数ポップ分が画面上に同時に
; 残る「散らばった破片」の見た目になる、新規の消滅タイマー機構は
; 不要)→(3)短いウェイト、を合計NUM_POPS回繰り返す。GO_PX0を
; ラウンドロビンスロットindex、GO_PY0をポップ残数カウンタへ転用
; (GO_PX1-3/GO_PY1-3/GO_DIR0-3X/Yだった旧4パーティクル用スクラッチは
; もう不要)。
; (2026-09-12、実機フィードバック対応"自機は消さず爆発処理して 爆発
; 処理が終わったら消すだけ もしパターンが足りないならEtankのエリア
; 使え"): 従来はこのラウンドロビンがTANK自身のhwスプライトATTRIBUTE
; スロット0-3(自機の4象限が常駐、Round76で判明済み)を直接上書きして
; おり、ポップ4回目で自機が爆発の絵に完全に置き換わっていた。指示
;通りEtankの専用スロット(ETANK_SPR_BASE_SLOT=24-25、Stage2本編が
; 二度と実行されないこのバンクでは安全に再利用可能)へ回すよう変更 -
; TANK自身のスロットには一切触れないため、爆発中も自機がそのまま
; 表示され続ける。Etank用は2スロットしか無いため、ラウンドロビンは
; mod4からmod2へ縮小(同時に画面上に残る破片は4個→2個)。
; (2026-09-12、続けての実機フィードバック対応"爆発のスプライト
; プライオリティを一番上にして 自機の後ろに隠れて見えないんで と言う
; ほもっと爆発の範囲広げて"): TMS9918のスプライト優先度はATTRIBUTE
; テーブル上のスロット番号が若いほど手前(他を隠す側)に描かれる。上の
; Etank流用(スロット24-25)はTANK自身のスロット0-3より若さで劣るため、
; 爆発がTANKの裏に隠れてしまっていた。TANK自身を(このバンクでは他に
; 誰も使わない)新規スロットNEW_TANK_SPR_BASE_SLOT(28-31)へ一度だけ
; VRAM上で移動(RELOCATE_TANK_SPRITE参照)し、空いた最若スロット0-3を
; 爆発側へ割り当て直す - これで爆発が常にTANKより手前に描かれる。
; Etank由来の「2スロットまで」という制約はTANK移動後は存在しないため
; mod2からmod4へ戻し(同時に画面上に残る破片は2個→4個)、範囲も
; GO_POP_JITTERの拡大と合わせて見た目の派手さを底上げする。
NEW_TANK_SPR_BASE_SLOT EQU 28  ; TANK自身の退避先(28-31、このバンクでは
                                ; 他に誰も使わない安全な領域)
EXPL_SPR_BASE_SLOT EQU 0   ; 爆発は最若=最優先スロットへ(TANKより必ず手前)
EXPL_SPR_SLOT_COUNT EQU 4  ; TANK移動によりEtankの2スロット制約は消滅、4に復元
GO_SLOT_IDX EQU 0F19Ch  ; 0-(EXPL_SPR_SLOT_COUNT-1)、次にポップを描く
                        ; EXPL_SPR_BASE_SLOT相対のATTRIBUTEスロット(ラウンドロビン)
GO_POP_CTR  EQU 0F19Dh  ; 残りポップ数(NUM_POPSからカウントダウン)

; (2026-09-07、実機フィードバック対応"爆発音はステージ1、2ともに
; パーティクルの回数鳴らすんだよ"): 現在の音量(ポップごとにGO_ARM_BOOM
; で撃ち直され、次のポップまでの短いウェイト中に少しだけ減衰する)。
GO_BOOM_VOL EQU 0F1A7h

NUM_POPS      EQU 40   ; 未調整の初期値、実機での見え方次第で再調整 -
                        ; 「1個ずつ」化に伴い前回のNUM_BURSTS(20)から
                        ; 増量(1回あたりが軽くなった分、密度を維持)
; (2026-09-12、実機フィードバック対応"もっと爆発の範囲広げて 今は
; ほぼ自機の範囲だけなんで"): 8→32へ拡大(AND用マスクのため2の
; べき乗を維持)。
GO_POP_JITTER EQU 32    ; 自機中心からのオフセット範囲、-16..+15px

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

    ; "爆発のスプライトプライオリティを一番上にして"(2026-09-12、実機
    ; フィードバック対応): 爆発をスロット0-3(最優先)で描くため、まず
    ; TANK自身の現在のスロット0-3の内容をNEW_TANK_SPR_BASE_SLOT(28-31)
    ; へ退避する。詳細はRELOCATE_TANK_SPRITE自身のコメント参照。
    DI
    CALL RELOCATE_TANK_SPRITE
    EI

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

; "爆発のスプライトプライオリティを一番上にして 自機の後ろに隠れて
; 見えないんで"(2026-09-12、実機フィードバック対応): TANK自身の
; 現在のATTRIBUTEスロット0-3(16byte、SPRATR基準)の内容を、そのまま
; NEW_TANK_SPR_BASE_SLOT(28-31)へVRAM上で移動する。TMS9918には
; VRAM→VRAM直接DMAが無いため、1byteずつVDPアドレスを読み出し用→
; 書き込み用に都度張り替えながらIN/OUTする(CLAUDE.md恒久ルール通り
; OTIR等のブロックI/O命令は使わない、16byteのみなので性能上も問題
; ない)。呼び出し元(INIT)がDI/EIで囲む。
; Trashes: AF,BC,DE,HL.
; (このアセンブラのeval_exprは演算子優先順位を持たず左から右へ逐次
; 評価するため、"SPRATR+NEW_TANK_SPR_BASE_SLOT*4"だと
; "(SPRATR+NEW_TANK_SPR_BASE_SLOT)*4"という誤ったアドレスに評価されて
; しまう[Round36-14 follow-up#8等で繰り返し踏んだ既知の罠] - 乗算を
; 先に書く"NEW_TANK_SPR_BASE_SLOT*4+SPRATR"の順で回避する。
RELOCATE_TANK_SPRITE:
    LD HL,SPRATR                                   ; source = slot0 base
    LD DE,NEW_TANK_SPR_BASE_SLOT*4+SPRATR          ; dest   = slot28 base
    LD B,16
RTS_LOOP:
    PUSH BC
    LD A,L : OUT (99h),A
    NOP : NOP
    LD A,H : OUT (99h),A      ; bit6=0 -> read mode (H=1Bh, bit6 already 0)
    NOP : NOP
    IN A,(98h)
    LD C,A
    LD A,E : OUT (99h),A
    NOP : NOP
    LD A,D : OR 40h : OUT (99h),A   ; bit6=1 -> write mode
    NOP : NOP
    LD A,C : OUT (98h),A
    NOP : NOP
    POP BC
    INC HL
    INC DE
    DJNZ RTS_LOOP
    RET

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
; EXPL_SPR_BASE_SLOT相対のATTRIBUTEスロット(2026-09-12実機フィード
; バック対応で0-3へ変更、TANK自身は別途NEW_TANK_SPR_BASE_SLOTへ退避
; 済みのためここには一切残っていない - 上のEQU群のコメント参照)で
; 描く。スロット0-3は最若=最優先のためTANKより必ず手前に描かれる。
; 描いた後GO_SLOT_IDXを次のスロットへ進める(mod EXPL_SPR_SLOT_
; COUNT)。色はGO_POP_CTRの最下位ビットで白/ライトレッドを交互に。
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
    ADD A,EXPL_SPR_BASE_SLOT
    ADD A,A : ADD A,A                ; A = (EXPL_SPR_BASE_SLOT+スロット)*4(ATTRIBUTEレコードのバイトオフセット)
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

    LD A,(GO_SLOT_IDX) : INC A : AND EXPL_SPR_SLOT_COUNT-1 : LD (GO_SLOT_IDX),A
    RET

; TANK自身の退避先NEW_TANK_SPR_BASE_SLOT(28-31、爆発中は一切触れて
; いないので実はY=209へ戻す必要はないが、他のGAME_OVER後処理と同じ
; 「明示的に隠す」規約に合わせて念のため含める)+EXPL_SPR_BASE_SLOT
; (0-3、爆発の破片)を、いずれもY=209(MSX標準の「個別に隠す」センチネル、project
; 全体の規約 - real terminator 208とは別、詳細はcombined_test.asm
; 自身のコメント参照)+X=0/pat=0/col=0へ戻し、点滅の非表示側を作る。
; (2026-09-08、実機フィードバック対応、"ステージ2の自機爆発で音が
; 出っぱなしでMission Failedになってる 消してからゲームオーバーに
; しろ 音の消し忘れ多すぎだろうが"): GO_ARM_BOOM/GO_STEP_BOOM_DECAY
; はポップごとに音量15へ撃ち直してから2段(15→13→11)しか減衰させず、
; 次のポップの頭でまた15へ撃ち直されるため、シーケンス全体を通じて
; R8(チャンネルA音量)が0に達することは一度も無い - 最後のポップの
; 後もR8=11のまま誰にも触れられず、MISSION FAILED表示中もずっと
; 鳴り続けていた。爆発演出の後片付け(GO_HIDE_EXPLOSION)の一部として
; ここでR8=0を明示的に書き込み、テキスト表示に進む前に確実に無音化
; する。
; (2026-09-12、実機フィードバック対応"自機は消さず爆発処理して 爆発
; 処理が終わったら消すだけ"): 従来はTANK自身のスロット0-3を隠すだけ
; だった(爆発自体がそこに描かれていたため)が、爆発をEXPL_SPR_BASE_
; SLOTへ移した今、爆発終了時にTANK自身も一緒に隠す(=「自機を消す」
; タイミングを"爆発処理が終わったら"に一本化)必要があるため、TANK
; スロット0-3への隠しループはそのまま維持し、EXPL_SPR_BASE_SLOT
; (24-25)を隠す2回目のループを追加した。
; (2026-09-12、続けての実機フィードバック対応でTANKをNEW_TANK_SPR_
; BASE_SLOT[28-31]へ退避・EXPL_SPR_BASE_SLOTを0-3へ変更したことに伴い
; 1回目のループのアドレスもNEW_TANK_SPR_BASE_SLOT基準へ更新。
; Trashes: AF,B,HL.
GO_HIDE_EXPLOSION:
    DI
    LD A,8 : OUT (PSG_ADDR),A
    XOR A : OUT (PSG_DATA),A   ; channel A (boom SE) volume=0 - GO_STEP_BOOM_DECAY never reaches 0 on its own
    LD A,NEW_TANK_SPR_BASE_SLOT*4 : OUT (99h),A
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
    LD A,EXPL_SPR_BASE_SLOT*4 : OUT (99h),A
    NOP
    NOP
    LD A,5Bh : OUT (99h),A
    NOP
    NOP
    LD B,EXPL_SPR_SLOT_COUNT
GO_HIDE_EXPL_LOOP:
    LD A,209 : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    XOR A : OUT (98h),A
    PUSH BC : POP BC : NOP : NOP
    DJNZ GO_HIDE_EXPL_LOOP
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
