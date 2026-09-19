; 新エネミー"Ebuz Mk2"(Ebuzの大型派生、中央砲台つき)のプロトタイプ
; 検証用、独立した空のSCREEN1テストROM。tools/ebuz_test/ebuz_test.asm
; (無印Ebuz)と全く同じ方法論 - 本編(src/CYBER SHMUP.asm)には一切
; 触れず、専用の空ステージでまず見た目・状態遷移・弾発射だけを検証する
; - をそのまま踏襲した、無印Ebuzの完全に独立した姉妹プロトタイプ。
; tools/ebuz_test/は一切変更していない(このファイルからも参照しない、
; 必要なタイルデータ・弾グラフィックは全てこのファイル内に直接複製済み)。
;
; ユーザー指示(オーケストレーションのClaude経由、原文ママ):
;   "まず添付ファイルのパターンで 開くとこまでは同じ ただし真ん中に
;   砲台が増えてる"
;   (訂正・追記): "発射管は5本あるデザイン 最初はEbuzと同じだが
;   スプライト3枚でくの字上状に発射 その後2の形態に 上下に移動
;   しながら連射 まあやってみて 修正は必要だろうから"
;
; *** 2026-09-19 追加訂正(適用済み、下記1.を全面書き換え) ***
; ユーザー訂正(原文ママ): "斜め移動はしないぞ"、続けてASCII art
;   (5行、各行はただの水平な"ー"だが開始X位置が行ごとに異なる):
;     ー
;    ー
;   ー
;    ー
;     ー
;   「砲台のXセル位置が異なるんで 先端に合わせれば自然にそうなる」
; つまり: 開幕3発をHWスプライトの斜め速度(DX/DY同時)で飛ばす旧設計は
; 誤りで、正しくは「本体側の5行それぞれが既に不規則[矩形でない]形状
; なので、各行の弾を"その行自身の先端タイルのすぐ外側"から真横
; (BGレーン、1ティック1列、Y成分ゼロ)に飛ばすだけで、全体としては
; 自然にウェッジ/くの字に見える」という単純な仕組み。HWスプライト・
; 斜め速度・SPRATR/SPRPATは全面撤去し、無印Ebuzと全く同じBGレーン弾
; (EBUZ2_WRITE2/BULLET_L_CODE/BULLET_R_CODE)を3レーン分だけ独立に
; 持つ方式へ置き換えた(詳細は下記1.、および各EBUZ2_VOLLEY*定義の
; コメント参照)。前提となる「本体5行の先端ローカル列(2,1,0,1,2)」は
; 添付Ebuzmkii1_64x64_2.json(静止ポーズ)のピクセルデータから
; tools/ebuz_mk2_test/ebuz_mk2_gen.pyで機械的に再検算し、この
; ユーザーのASCII wedgeと完全一致することを確認済み(このファイル
; 自身のEBUZ2_ROW_S1_0-4のタイル配置ともちろん整合している - 元々
; 本体の形状データ自体は変更していない、変えたのは弾の発射方式のみ)。
; state2(上下往復+連続交互発射)は元々斜めではなく、この訂正の対象
; 外 - 無変更のまま。
;
; 添付画像(64x64、2状態)をオーケストレーション側で既存の無印Ebuz
; タイル(A,B,C,D、下記に再掲)とバイト単位で突き合わせた結果、Mk2も
; 新規タイル一切不要、この4枚だけの再配置で両状態を表現できると判明
; 済み(オーケストレーション側の作業、このファイルではその結果の
; タイル配置だけを実装する)。
;
; --- state1(閉状態、5行x5列、row0が最上段、col0が最左列、空欄=code0) ---
;   row0: .  .  A  B  C        (col2,3,4)
;   row1: .  A  B  C  D        (col1,2,3,4)
;   row2: A  B  C  D  D        (col0,1,2,3,4 - 縦方向の中心、最も幅広い行)
;   row3: .  A  B  C  D        (row1と同一)
;   row4: .  .  A  B  C        (row0と同一)
;
; --- state2(開状態・砲台露出、7行x5列) ---
;   row0: .  .  A  B  C        (col2,3,4)
;   row1: .  A  B  C  C        (col1,2,3,4 - col4はD ではなく C の反復)
;   row2: .  .  .  .  D        (col4のみ - 砲台上キャップ)
;   row3: A  B  C  D  D        (col0,1,2,3,4 - 中心行、羽[A,B,C]が砲台
;                                本体[D,D]と同じ行で直結)
;   row4: .  .  .  .  D        (row2と同一 - 砲台下キャップ)
;   row5: .  A  B  C  C        (row1と同一)
;   row6: .  .  A  B  C        (row0と同一)
;
; state1のrow2とstate2のrow3(いずれも"ABCDD"の最幅広行)は物理的に
; 同一のname table行に固定して置く - state1→state2遷移では既存の
; 行が動かず、その上下に新しい行が1行ずつ追加される、という無印Ebuz
; の遷移スタイルをそのまま踏襲する(このファイルではname table row5
; に固定、state1はrow3-7の5行、state2はrow2-8の7行を占有)。
;
; --- 列のname tableへのマッピング ---
; 無印Ebuzの規約(local col1 = EBUZ_COL = name table col24)をそのまま
; 踏襲: local col0→col23, col1→col24, col2→col25, col3→col26,
; col4→col27。col23は最幅広行(state1のrow2・state2のrow3)でだけ
; 使用する。このアセンブラは演算子優先順位も丸括弧も無い(左から右へ
; 逐次評価するだけ)ため、"NAMTBL+ROW*32+COL"式は一切書かず、name
; table上の絶対アドレスを全て事前計算したリテラルとして直接記述する
; (無印Ebuzと同じ規約、tools/ebuz_test/ebuz_test.asmの該当コメント
; 参照)。
;
; --- 発射/移動仕様(ユーザー自身が「修正は必要だろう」と明言済み。 ---
; 以下は原文の素直な解釈・実装であり、判断に迷った点はこのファイルの
; 各所と、送付時のレポートで明示する)。
;
; 1. state1(2026-09-19訂正版): 無印Ebuzと同じ「登場→少し静止→解放」
;    の流れ。無印Ebuzが解放の瞬間に1発(bullet0)を撃つのに対し、Mk2は
;    本体5行のうち3行(上端キャップ/中央[最深部]/下端キャップ、
;    "3 sprites"とのユーザー指定に沿ったデフォルト選択 - 上下2行
;    [row1/row3]を使う代替案も要検討、レポートに明記)から同時に3発
;    発射する。斜め速度は一切使わない - 3発とも無印Ebuzと全く同じ
;    BGレーン弾(固定name table行・1ティック1列・Y成分ゼロ、
;    EBUZ2_WRITE2/BULLET_L_CODE/BULLET_R_CODEをそのまま流用)で、
;    各行自身の「先端」(その行で最も左に描画されているタイル列の、
;    さらに1セル外側)から個別に発射を開始する列だけが行ごとに異なる
;    - この発射開始列のズレだけで、全体としては自然にウェッジ/
;    くの字状に見える(本体自体が既に不規則形状であることの帰結)。
;    HWスプライトは一切使わない。
;
; 2. state1→state2遷移: 無印Ebuzと同じLDIRVMによるタイル差し替え
;    方式を、5行→7行の大きいレイアウトへそのまま適用。
;
; 3. state2: 無印Ebuzの継続発射の仕組み(EBUZ_TOPBOTTOM_ACTIVE/
;    EBUZ_FIRE_SIDE/EBUZ_FIRE_COUNTDOWNによる固定間隔・無条件の交互
;    発射、BULLET_L_CODE/BULLET_R_CODEのBGレーン弾)をそのまま流用し、
;    発射レーンを砲台の上下キャップ行(state2のrow2/row4、中心行の
;    直上・直下)に割り当てる。「上下に移動しながら連射」については、
;    BG方式は「動く」=「毎回全体を別の行位置へ再描画する」ことを
;    意味しコストが高いため、離散的な往復(base→up→base→down→base
;    …の4段サイクル、各段は一定ティックだけ静止)として実装する。
;    **重要な簡略化(判断が必要だった点、レポートで明示する)**:
;    上下移動は本体の見た目(タイル配置)だけを動かし、発射レーン
;    自体(row2/row4)は本体の移動に追従させず固定のままにしている
;    - 追従させる設計も検討したが、既に飛行中の弾が属するレーンの
;    行を実行時に付け替えると「古い行に消し忘れの弾が残る」種類の
;    新規バグを生みやすく、プロトタイプの最初の一手としてはリスクが
;    高いと判断した。本体columnsは常にcol23-27の5列に収まり、弾の
;    飛行経路(col21以下、後述)とは物理的に重ならないため、この
;    簡略化によるVRAM破壊は起きない - 見た目上、本体がup/down位置に
;    いる間だけ砲台キャップの絵と実際の発射位置が1行分ズレて見える
;    (視覚的な違和感はあり得るが、機能的な破損はない)。継続発射
;    自体は本体の移動サイクルと独立して同じ間隔で回り続ける。
;
;    ステップ数・速度・間隔は全て未調整のプレースホルダー(下記の
;    EQU定数群、コメントに明記)。
    ORG 4000h

INIT32   EQU 006Fh
LDIRVM   EQU 005Ch
WRTVRM   EQU 004Dh

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

STACKTOP EQU 0F380h
NAMTBL   EQU 1800h
COLTBL   EQU 2000h
; (2026-09-19訂正: 旧くの字3連が使っていたSPRATR/SPRPAT/WRTVDPは、
; HWスプライトを全廃したため削除。本ファイルはBGのみで完結する。)

; ============================================================================
; BGパターンコード・カラー(無印Ebuzと同じ割り当て番号をそのまま再利用 -
; このファイル専用の空環境につき空き番地監査は不要)
; ============================================================================
EBUZ2_CODE_A EQU 64
EBUZ2_CODE_B EQU 65
EBUZ2_CODE_C EQU 66
EBUZ2_CODE_D EQU 67
EBUZ2_COLOR  EQU 015h   ; fg=1(black)/bg=5(light blue) - 無印Ebuzと同じ空色

BULLET_L_CODE EQU 72
BULLET_R_CODE EQU 73
EBUZ2_BULLET_COLOR EQU 0B5h  ; fg=11(light yellow)/bg=5(light blue、無印Ebuzと同じ)

; ============================================================================
; name table行の絶対アドレス(row*32+NAMTBL)。row5を構造的な中心
; (state1/state2共通の最幅広行)に固定 - state1はrow3-7(5行)、
; state2の基本位置(base)はrow2-8(7行)、oscillationのup位置は
; row1-7、down位置はrow3-9を使う。
; ============================================================================
EBUZ2_ROW1_BASE EQU NAMTBL+32    ; = 1820h
EBUZ2_ROW2_BASE EQU NAMTBL+64    ; = 1840h
EBUZ2_ROW3_BASE EQU NAMTBL+96    ; = 1860h
EBUZ2_ROW4_BASE EQU NAMTBL+128   ; = 1880h  <- 発射レーン(上、固定)
EBUZ2_ROW5_BASE EQU NAMTBL+160   ; = 18A0h  <- 構造的な中心行
EBUZ2_ROW6_BASE EQU NAMTBL+192   ; = 18C0h  <- 発射レーン(下、固定)
EBUZ2_ROW7_BASE EQU NAMTBL+224   ; = 18E0h
EBUZ2_ROW8_BASE EQU NAMTBL+256   ; = 1900h
EBUZ2_ROW9_BASE EQU NAMTBL+288   ; = 1920h

; 弾(BGレーン、無印Ebuzと同じ2タイル構成)の発射開始列。本体の最左列
; がcol23なので、無印Ebuzの「本体最左列から-2列」という規約を踏襲し
; col21を使う(col23-27の本体アートと物理的に一切重ならない)。
EBUZ2_BULLET_COL EQU 21

EBUZ2_LANE_POOL_SIZE EQU 8
EBUZ2_SLOT_EMPTY EQU 255

; "2フレ交代"(無印Ebuzの継続発射と同じ固定間隔・無条件発射の作法)。
EBUZ2_FIRE_INTERVAL EQU 2

; --- 開幕ボレー(state1解放時、3本のBGレーン弾) ---
; (2026-09-19訂正: 斜め速度のHWスプライトを全面撤去、無印Ebuzと同じ
; 「固定name table行・1ティック1列・Y成分ゼロ」のBGレーン弾3本に
; 置き換え。斜め成分が無いことがコード上でも自明になるよう、3レーン
; とも明示的に別ルーチンとして書く - 汎用ループより見た目が素直)。
;
; 各レーンの発射開始列 = 「その行の先端ローカル列-1」を、本体タイルと
; 同じマッピング式(ローカル列c → name table列23+c、このファイル
; 冒頭コメントの規約)で変換したもの。本体5行の先端ローカル列
; (2,1,0,1,2、tools/ebuz_mk2_test/ebuz_mk2_gen.pyで添付JSONの実
; ピクセルデータから検算済み)から:
;   row0(上端キャップ、先端=2) -> 発射列 = 23+(2-1) = 24
;   row2(中央、最深部、先端=0) -> 発射列 = 23+(0-1) = 22
;   row4(下端キャップ、先端=2、row0と同型) -> 発射列 = 24
; row0とrow4は同じ24、row2(中央)だけが22で一段深い - これが3点だけで
; 見てもウェッジと分かる形(浅・深・浅)になる。
EBUZ2_VOLLEY0_COL EQU 24   ; row0(nametable row3、上端キャップ)
EBUZ2_VOLLEY1_COL EQU 22   ; row2(nametable row5、中央=最深部)
EBUZ2_VOLLEY2_COL EQU 24   ; row4(nametable row7、下端キャップ、row0と同じ)

; --- state1解放までのホールド・state2形成後の連射開始までのホールド ---
; (無印Ebuzの10/45ティックという実機フィードバック調整値をそのまま
; 初期値として踏襲、Mk2用に再調整はしていない - 未調整のプレース
; ホルダー)。
EBUZ2_VOLLEY_HOLD_TICKS    EQU 10
EBUZ2_TOPBOTTOM_HOLD_TICKS EQU 45

; --- 上下往復(oscillation)。4段階サイクル(base→up→base→down→
; base…)、各段は一定ティック静止してから次へ - 「2-4箇所の離散
; 位置で第一段としては十分」という指示に沿った未調整の仮値。
EBUZ2_OSC_HOLD_TICKS EQU 20

; ============================================================================
; RAMワークエリア(page3、無印Ebuzと同じ0F300h付近を再利用 - 別ROMの
; ため衝突しない。STACKTOP=0F380hまで十分な余白を確保している)。
; ============================================================================
EBUZ2_TOPBOTTOM_ACTIVE EQU 0F300h  ; 1 byte: 0=まだ非活性、1=継続発射+oscillation中
EBUZ2_FIRE_SIDE         EQU 0F301h  ; 1 byte: 次に撃つ側(0=上/1=下)
EBUZ2_FIRE_COUNTDOWN    EQU 0F302h  ; 1 byte: 次の発射までの残りティック数
EBUZ2_TOP_NEXT          EQU 0F303h  ; 1 byte: 上レーンのプール割当ローテーションカウンタ
EBUZ2_BOTTOM_NEXT       EQU 0F304h  ; 1 byte: 下レーンの同上
EBUZ2_CUR_ROW_BASE      EQU 0F305h  ; 2 bytes: EBUZ2_UPDATE_SLOTが参照する「今どの行が対象か」

EBUZ2_TOP_COLS    EQU 0F310h  ; EBUZ2_LANE_POOL_SIZE(8) bytes
EBUZ2_BOTTOM_COLS EQU 0F318h  ; EBUZ2_LANE_POOL_SIZE(8) bytes

EBUZ2_OSC_PHASE EQU 0F320h  ; 1 byte: 0=base(→up待ち)/1=up(→base待ち)/2=base(→down待ち)/3=down(→base待ち)
EBUZ2_OSC_TIMER EQU 0F321h  ; 1 byte: 次の遷移までの残りティック数

; 開幕ボレー3レーンそれぞれの状態(2026-09-19訂正: X/Y/DX/DYの5byte
; 構造体[斜め速度]を全廃し、無印Ebuzのbullet0と全く同じACTIVE+COLの
; 2byteだけに簡略化 - 各レーンは自分のname table行に完全固定された
; まま列だけが動く、Y成分の概念自体が存在しない設計のため)。
EBUZ2_VOLLEY0_ACTIVE EQU 0F330h  ; row0レーン(nametable row3、上端キャップ)
EBUZ2_VOLLEY0_COLCUR EQU 0F331h  ; 現在の左列(0-31)
EBUZ2_VOLLEY1_ACTIVE EQU 0F332h  ; row2レーン(nametable row5、中央=最深部)
EBUZ2_VOLLEY1_COLCUR EQU 0F333h
EBUZ2_VOLLEY2_ACTIVE EQU 0F334h  ; row4レーン(nametable row7、下端キャップ)
EBUZ2_VOLLEY2_COLCUR EQU 0F335h

; ============================================================================
; 1フレーム相当のウェイト(無印Ebuzと同一の較正済みループ、
; tools/ebuz_test/ebuz_test.asmのEBUZ_FRAME_WAITと完全に同じ実装)。
; ============================================================================
EBUZ2_FRAME_WAIT:
    LD B,15
EBUZ2_FRAME_WAIT_OUTER:
    LD C,0
EBUZ2_FRAME_WAIT_INNER:
    DEC C
    JR NZ,EBUZ2_FRAME_WAIT_INNER
    DJNZ EBUZ2_FRAME_WAIT_OUTER
    RET

; VRAMの連続2byteへ書き込む(無印EbuzのEBUZ_WRITE2と同一)。IN: HL=
; 左セルのアドレス、B=左セルへ書く値、C=右セルへ書く値。
EBUZ2_WRITE2:
    LD A,B
    CALL WRTVRM
    INC HL
    LD A,C
    CALL WRTVRM
    RET

; B=待ちたいティック数(1-255)。EBUZ2_TICKをB回呼ぶだけの「弾の移動を
; 止めない待ち」(無印EbuzのEBUZ_WAIT_TICKSと同一の作法)。
EBUZ2_WAIT_TICKS:
EBUZ2_WAIT_TICKS_LOOP:
    PUSH BC
    CALL EBUZ2_TICK
EBUZ2_WAIT_TICK_DONE:                ; テスト用: 「待ち期間中の1ティック完了」の目印
    POP BC
    DJNZ EBUZ2_WAIT_TICKS_LOOP
    RET

; ============================================================================
; 開幕ボレー3レーンの更新(2026-09-19訂正: 斜め速度のHWスプライト
; [EBUZ2_UPDATE_CHEVRON]を全廃し、無印EbuzのEBUZ_TICK内bullet0処理・
; およびEBUZ2_UPDATE_SLOTと全く同じ「固定行・1ティック1列・Y成分
; ゼロ」のBGレーン弾3本に置き換え。斜め成分が構造的に存在しえない
; ことがコード上でも自明になるよう、3レーンとも独立ルーチンとして
; 明示的に書く(汎用ループより見た目が素直 - 無印Ebuzの単一bullet0
; ルーチンと同じ方針)。ACTIVE=0なら何もしない。現在位置を消し、
; 列を1減算、0だった場合はそのまま非活性化(画面外)、そうでなければ
; 新しい列に描き直す - Y座標・行アドレスは呼び出しの間ずっと固定。
; ============================================================================
; 2026-09-20訂正(実機フィードバック「砲台は5門に増えてるぞ」の原因):
; 開幕ボレー3レーンはstate1のうちは何も無い空白の行(nt row3/5/7)を
; 飛ぶ設計だったが、実際にはFIRE_VOLLEY直後・ノーウェイトでDRAW_BASE
; (state2への変形)が走るため、TICK_VOLLEYnが実際に「現在位置を消す」
; 処理を初めて実行する時点では、本体は既にstate2(この3行のちょうど
; col23-27に本体タイルが存在する形)になっている。旧実装はここを
; 無条件に0(空白)で消していたため、飛んでいく弾が通過のたびに
; state2本体の翼タイル(A/B)を剥ぎ取ってしまい、残ったD(砲台)タイルが
; 複数行に孤立して見える事故になっていた。EBUZ2_ROW3_RESTORE/
; EBUZ2_ROW5_RESTOREは「col21-28の範囲でstate2本体が実際に表示すべき
; タイル」を持つ表で、消す際は0ではなくこの表の値で復元する(col21未満は
; 元々どちらの状態でも空白なので、従来通り0のままでよい - 場合分け
; 不要)。TICK_VOLLEYnが実際に動く時点で本体は常にstate2なので、
; state1/state2の判定分岐自体も不要(詳細は本ファイルの会話ログ参照)。
; ============================================================================
EBUZ2_ROW3_RESTORE:            ; col21,22,23,24,25,26,27,28 (row3/row7共通、
    DB 0,0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C,0
    ; state2 local row1/row5 " . A B C C"と同一)
EBUZ2_ROW5_RESTORE:            ; col21,22,23,24,25,26,27,28 (row5=中心行、
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D,0
    ; state2 local row3 "A B C D D"と同一)

; Input: A=消す位置の列(COLCUR、erase前・decrement前)。破壊: AF,BC,DE,HL。
EBUZ2_ERASE_ROW3_CELL:
    PUSH AF
    CP 21
    JR C,EBUZ2_ERC_ROW3_PLAIN
    SUB 21
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW3_RESTORE : ADD HL,DE
    LD B,(HL) : INC HL : LD C,(HL)
    JR EBUZ2_ERC_ROW3_GO
EBUZ2_ERC_ROW3_PLAIN:
    LD B,0 : LD C,0
EBUZ2_ERC_ROW3_GO:
    POP AF
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW3_BASE : ADD HL,DE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_ERASE_ROW5_CELL:
    PUSH AF
    CP 21
    JR C,EBUZ2_ERC_ROW5_PLAIN
    SUB 21
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW5_RESTORE : ADD HL,DE
    LD B,(HL) : INC HL : LD C,(HL)
    JR EBUZ2_ERC_ROW5_GO
EBUZ2_ERC_ROW5_PLAIN:
    LD B,0 : LD C,0
EBUZ2_ERC_ROW5_GO:
    POP AF
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW5_BASE : ADD HL,DE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_ERASE_ROW7_CELL:
    PUSH AF
    CP 21
    JR C,EBUZ2_ERC_ROW7_PLAIN
    SUB 21
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW3_RESTORE : ADD HL,DE   ; row7もrow3と同一内容
    LD B,(HL) : INC HL : LD C,(HL)
    JR EBUZ2_ERC_ROW7_GO
EBUZ2_ERC_ROW7_PLAIN:
    LD B,0 : LD C,0
EBUZ2_ERC_ROW7_GO:
    POP AF
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW7_BASE : ADD HL,DE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_TICK_VOLLEY0:
    LD A,(EBUZ2_VOLLEY0_ACTIVE)
    OR A
    RET Z
    LD A,(EBUZ2_VOLLEY0_COLCUR)
    CALL EBUZ2_ERASE_ROW3_CELL            ; 現在位置を消す(row3固定、Y成分なし、
                                           ; state2本体タイルは剥がさず復元)
    LD A,(EBUZ2_VOLLEY0_COLCUR)
    OR A
    JR Z,EBUZ2_TV0_OFF
    DEC A
    LD (EBUZ2_VOLLEY0_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW3_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2
    RET
EBUZ2_TV0_OFF:
    XOR A
    LD (EBUZ2_VOLLEY0_ACTIVE),A
    RET

EBUZ2_TICK_VOLLEY1:
    LD A,(EBUZ2_VOLLEY1_ACTIVE)
    OR A
    RET Z
    LD A,(EBUZ2_VOLLEY1_COLCUR)
    CALL EBUZ2_ERASE_ROW5_CELL            ; 現在位置を消す(row5固定、中央=最深部
                                           ; レーン、state2本体タイルは剥がさず復元)
    LD A,(EBUZ2_VOLLEY1_COLCUR)
    OR A
    JR Z,EBUZ2_TV1_OFF
    DEC A
    LD (EBUZ2_VOLLEY1_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW5_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2
    RET
EBUZ2_TV1_OFF:
    XOR A
    LD (EBUZ2_VOLLEY1_ACTIVE),A
    RET

EBUZ2_TICK_VOLLEY2:
    LD A,(EBUZ2_VOLLEY2_ACTIVE)
    OR A
    RET Z
    LD A,(EBUZ2_VOLLEY2_COLCUR)
    CALL EBUZ2_ERASE_ROW7_CELL            ; 現在位置を消す(row7固定、Y成分なし、
                                           ; state2本体タイルは剥がさず復元)
    LD A,(EBUZ2_VOLLEY2_COLCUR)
    OR A
    JR Z,EBUZ2_TV2_OFF
    DEC A
    LD (EBUZ2_VOLLEY2_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW7_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2
    RET
EBUZ2_TV2_OFF:
    XOR A
    LD (EBUZ2_VOLLEY2_ACTIVE),A
    RET

; state1の解放瞬間、3本のBGレーン弾を同時発射する(斜め成分なし、
; row0/row2/row4それぞれ自分の行に固定されたまま、行ごとに異なる
; 発射開始列[EBUZ2_VOLLEY0/1/2_COL]から真横に飛び始める)。
EBUZ2_FIRE_VOLLEY:
    LD A,1 : LD (EBUZ2_VOLLEY0_ACTIVE),A
    LD A,EBUZ2_VOLLEY0_COL : LD (EBUZ2_VOLLEY0_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW3_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2

    LD A,1 : LD (EBUZ2_VOLLEY1_ACTIVE),A
    LD A,EBUZ2_VOLLEY1_COL : LD (EBUZ2_VOLLEY1_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW5_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2

    LD A,1 : LD (EBUZ2_VOLLEY2_ACTIVE),A
    LD A,EBUZ2_VOLLEY2_COL : LD (EBUZ2_VOLLEY2_COLCUR),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW7_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ2_WRITE2
    RET

; ============================================================================
; state2連射レーン(BG、無印EbuzのEBUZ_UPDATE_SLOT/EBUZ_UPDATE_TOP_POOL/
; BOTTOM_POOLと完全に同一のロジック、行だけをEBUZ2_ROW4_BASE/ROW6_BASE
; [砲台キャップ行、本体の上下移動には追従しない固定レーン - ファイル
; 冒頭コメント参照]に差し替え)。
; ============================================================================
EBUZ2_UPDATE_SLOT:
    LD A,(HL)
    CP EBUZ2_SLOT_EMPTY
    RET Z
    PUSH HL
    PUSH AF
    LD E,A : LD D,0
    LD HL,(EBUZ2_CUR_ROW_BASE)
    ADD HL,DE
    LD B,0 : LD C,0
    CALL EBUZ2_WRITE2
    POP AF
    OR A
    JR Z,EBUZ2_US_OFF
    DEC A
    POP HL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,(EBUZ2_CUR_ROW_BASE)
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET
EBUZ2_US_OFF:
    POP HL
    LD (HL),EBUZ2_SLOT_EMPTY
    RET

EBUZ2_UPDATE_TOP_POOL:
    LD HL,EBUZ2_ROW4_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_TOP_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_TOP_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_BOTTOM_POOL:
    LD HL,EBUZ2_ROW6_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_BOTTOM_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_BOTTOM_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_FIRE_TOP_BULLET:
    LD A,(EBUZ2_TOP_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FTB_OK
    XOR A
EBUZ2_FTB_OK:
    LD (EBUZ2_TOP_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_TOP_COLS
    ADD HL,DE
    LD A,EBUZ2_BULLET_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW4_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_BOTTOM_BULLET:
    LD A,(EBUZ2_BOTTOM_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FBB_OK
    XOR A
EBUZ2_FBB_OK:
    LD (EBUZ2_BOTTOM_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_BOTTOM_COLS
    ADD HL,DE
    LD A,EBUZ2_BULLET_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW6_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

; 継続発射(固定EBUZ2_FIRE_INTERVALティックごとに無条件・交互発射、
; 無印Ebuzの反動アニメーションは今回のMk2仕様には含まれていないため
; 省略 - 発射自体のロジックはRound125で確立した「生存チェックなし・
; 固定間隔」の作法をそのまま流用)。
EBUZ2_UPDATE_TOPBOTTOM_FIRE:
    LD A,(EBUZ2_FIRE_COUNTDOWN)
    DEC A
    LD (EBUZ2_FIRE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ2_FIRE_INTERVAL
    LD (EBUZ2_FIRE_COUNTDOWN),A
    LD A,(EBUZ2_FIRE_SIDE)
    OR A
    JR NZ,EBUZ2_UTF_FIRE_BOTTOM
    CALL EBUZ2_FIRE_TOP_BULLET
    JR EBUZ2_UTF_FIRE_DONE
EBUZ2_UTF_FIRE_BOTTOM:
    CALL EBUZ2_FIRE_BOTTOM_BULLET
EBUZ2_UTF_FIRE_DONE:
    LD A,(EBUZ2_FIRE_SIDE)
    XOR 1
    LD (EBUZ2_FIRE_SIDE),A
    RET

; ============================================================================
; 本体形状データ(5byte/行、col23-27の順。0=空白セル)。state1/state2の
; 全ポジション(base/up/down)がこの同じ7行分のデータを使い回す
; (state1は5行のみ使用する専用データ、下記EBUZ2_ROW_S1_*)。
; ============================================================================
EBUZ2_BLANK5:
    DB 0,0,0,0,0

EBUZ2_ROW_S1_0:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C
EBUZ2_ROW_S1_1:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D
EBUZ2_ROW_S1_2:
    DB EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D
EBUZ2_ROW_S1_3:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D
EBUZ2_ROW_S1_4:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C

EBUZ2_ROW_S2_0:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C
EBUZ2_ROW_S2_1:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C
EBUZ2_ROW_S2_2:
    DB 0,0,0,0,EBUZ2_CODE_D
EBUZ2_ROW_S2_3:
    DB EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D
EBUZ2_ROW_S2_4:
    DB 0,0,0,0,EBUZ2_CODE_D
EBUZ2_ROW_S2_5:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C
EBUZ2_ROW_S2_6:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C

; ============================================================================
; state1の描画(5行、row3-7、col23起点の5byte単位LDIRVM)。
; ============================================================================
EBUZ2_DRAW_STATE1:
    LD HL,EBUZ2_ROW_S1_0 : LD DE,01877h : LD BC,5 : CALL LDIRVM  ; row3
    LD HL,EBUZ2_ROW_S1_1 : LD DE,01897h : LD BC,5 : CALL LDIRVM  ; row4
    LD HL,EBUZ2_ROW_S1_2 : LD DE,018B7h : LD BC,5 : CALL LDIRVM  ; row5(中心)
    LD HL,EBUZ2_ROW_S1_3 : LD DE,018D7h : LD BC,5 : CALL LDIRVM  ; row6
    LD HL,EBUZ2_ROW_S1_4 : LD DE,018F7h : LD BC,5 : CALL LDIRVM  ; row7
    RET

; state2の3ポジション(base=row2-8/up=row1-7/down=row3-9)それぞれの
; 描画・消去。中身のデータ(EBUZ2_ROW_S2_0-6)は共通、宛先アドレスだけが
; 1行(32byte)ずつずれる。
EBUZ2_DRAW_BASE:
    LD HL,EBUZ2_ROW_S2_0 : LD DE,01857h : LD BC,5 : CALL LDIRVM  ; row2
    LD HL,EBUZ2_ROW_S2_1 : LD DE,01877h : LD BC,5 : CALL LDIRVM  ; row3
    LD HL,EBUZ2_ROW_S2_2 : LD DE,01897h : LD BC,5 : CALL LDIRVM  ; row4(上キャップ=発射レーン)
    LD HL,EBUZ2_ROW_S2_3 : LD DE,018B7h : LD BC,5 : CALL LDIRVM  ; row5(中心)
    LD HL,EBUZ2_ROW_S2_4 : LD DE,018D7h : LD BC,5 : CALL LDIRVM  ; row6(下キャップ=発射レーン)
    LD HL,EBUZ2_ROW_S2_5 : LD DE,018F7h : LD BC,5 : CALL LDIRVM  ; row7
    LD HL,EBUZ2_ROW_S2_6 : LD DE,01917h : LD BC,5 : CALL LDIRVM  ; row8
    RET

EBUZ2_ERASE_BASE:
    LD HL,EBUZ2_BLANK5 : LD DE,01857h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01877h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01897h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018B7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018D7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018F7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01917h : LD BC,5 : CALL LDIRVM
    RET

EBUZ2_DRAW_UP:
    LD HL,EBUZ2_ROW_S2_0 : LD DE,01837h : LD BC,5 : CALL LDIRVM  ; row1
    LD HL,EBUZ2_ROW_S2_1 : LD DE,01857h : LD BC,5 : CALL LDIRVM  ; row2
    LD HL,EBUZ2_ROW_S2_2 : LD DE,01877h : LD BC,5 : CALL LDIRVM  ; row3
    LD HL,EBUZ2_ROW_S2_3 : LD DE,01897h : LD BC,5 : CALL LDIRVM  ; row4
    LD HL,EBUZ2_ROW_S2_4 : LD DE,018B7h : LD BC,5 : CALL LDIRVM  ; row5
    LD HL,EBUZ2_ROW_S2_5 : LD DE,018D7h : LD BC,5 : CALL LDIRVM  ; row6
    LD HL,EBUZ2_ROW_S2_6 : LD DE,018F7h : LD BC,5 : CALL LDIRVM  ; row7
    RET

EBUZ2_ERASE_UP:
    LD HL,EBUZ2_BLANK5 : LD DE,01837h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01857h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01877h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01897h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018B7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018D7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018F7h : LD BC,5 : CALL LDIRVM
    RET

EBUZ2_DRAW_DOWN:
    LD HL,EBUZ2_ROW_S2_0 : LD DE,01877h : LD BC,5 : CALL LDIRVM  ; row3
    LD HL,EBUZ2_ROW_S2_1 : LD DE,01897h : LD BC,5 : CALL LDIRVM  ; row4
    LD HL,EBUZ2_ROW_S2_2 : LD DE,018B7h : LD BC,5 : CALL LDIRVM  ; row5
    LD HL,EBUZ2_ROW_S2_3 : LD DE,018D7h : LD BC,5 : CALL LDIRVM  ; row6
    LD HL,EBUZ2_ROW_S2_4 : LD DE,018F7h : LD BC,5 : CALL LDIRVM  ; row7
    LD HL,EBUZ2_ROW_S2_5 : LD DE,01917h : LD BC,5 : CALL LDIRVM  ; row8
    LD HL,EBUZ2_ROW_S2_6 : LD DE,01937h : LD BC,5 : CALL LDIRVM  ; row9
    RET

EBUZ2_ERASE_DOWN:
    LD HL,EBUZ2_BLANK5 : LD DE,01877h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01897h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018B7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018D7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,018F7h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01917h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_BLANK5 : LD DE,01937h : LD BC,5 : CALL LDIRVM
    RET

; ============================================================================
; 上下往復(oscillation)。EBUZ2_OSC_TIMERが0になるたび、現在のphase
; (0-3)に応じて1段階だけ遷移する(base→up→base→down→base…の4段
; サイクル)。遷移のたびに「今の位置を消す→次の位置を描く」の順で
; 呼ぶ(無印Ebuzの弾更新[消してから動かす]と同じ考え方)。発射レーン
; (row4/row6)自体はこのファイル冒頭コメントの通り追従させない -
; 本体の見た目だけが動く。
; ============================================================================
EBUZ2_UPDATE_OSCILLATION:
    LD A,(EBUZ2_OSC_TIMER)
    DEC A
    LD (EBUZ2_OSC_TIMER),A
    RET NZ
    LD A,(EBUZ2_OSC_PHASE)
    CP 0
    JR Z,EBUZ2_OSC_P0
    CP 1
    JR Z,EBUZ2_OSC_P1
    CP 2
    JR Z,EBUZ2_OSC_P2
    JR EBUZ2_OSC_P3
EBUZ2_OSC_P0:
    CALL EBUZ2_ERASE_BASE
    CALL EBUZ2_DRAW_UP
    LD A,1
    LD (EBUZ2_OSC_PHASE),A
    JR EBUZ2_OSC_RESET
EBUZ2_OSC_P1:
    CALL EBUZ2_ERASE_UP
    CALL EBUZ2_DRAW_BASE
    LD A,2
    LD (EBUZ2_OSC_PHASE),A
    JR EBUZ2_OSC_RESET
EBUZ2_OSC_P2:
    CALL EBUZ2_ERASE_BASE
    CALL EBUZ2_DRAW_DOWN
    LD A,3
    LD (EBUZ2_OSC_PHASE),A
    JR EBUZ2_OSC_RESET
EBUZ2_OSC_P3:
    CALL EBUZ2_ERASE_DOWN
    CALL EBUZ2_DRAW_BASE
    XOR A
    LD (EBUZ2_OSC_PHASE),A
EBUZ2_OSC_RESET:
    LD A,EBUZ2_OSC_HOLD_TICKS
    LD (EBUZ2_OSC_TIMER),A
EBUZ2_OSC_SHIFT_DONE:               ; テスト用: 1回の遷移完了の目印
    RET

; ============================================================================
; 1"フレーム"分の処理: 開幕ボレー3レーンの更新(常時、非活性なら早期
; RETなので無駄コストは小さい、2026-09-19訂正でくの字HWスプライト
; から差し替え)→連射レーンのプール更新(常時)→継続発射中なら発射
; カウントダウン+oscillation更新→ウェイト。
; ============================================================================
EBUZ2_TICK:
    DI
    CALL EBUZ2_TICK_VOLLEY0
    CALL EBUZ2_TICK_VOLLEY1
    CALL EBUZ2_TICK_VOLLEY2
    CALL EBUZ2_UPDATE_TOP_POOL
    CALL EBUZ2_UPDATE_BOTTOM_POOL
    LD A,(EBUZ2_TOPBOTTOM_ACTIVE)
    OR A
    CALL NZ,EBUZ2_UPDATE_TOPBOTTOM_FIRE
    LD A,(EBUZ2_TOPBOTTOM_ACTIVE)
    OR A
    CALL NZ,EBUZ2_UPDATE_OSCILLATION
    EI
    CALL EBUZ2_FRAME_WAIT
    RET

; ============================================================================
INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32

    ; (2026-09-19訂正: 旧くの字3連が使っていた「8x8スプライトモード
    ; 明示」のVDP R1書き込みは、HWスプライトを全廃したため不要になり
    ; 削除。本ファイルはBG[name table]のみで完結する。)

    ; 背景は空(code0のまま)なので、画面全体を無印Ebuzと同じ空色に。
    LD HL,EBUZ2_COLOR_BYTE : LD DE,COLTBL+0 : LD BC,1 : CALL LDIRVM
    LD HL,EBUZ2_COLOR_BYTE : LD DE,COLTBL+8 : LD BC,1 : CALL LDIRVM

    ; 本体4タイル(A,B,C,D)をロード
    LD HL,EBUZ2_TILE_A : LD DE,EBUZ2_CODE_A*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_B : LD DE,EBUZ2_CODE_B*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_C : LD DE,EBUZ2_CODE_C*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_D : LD DE,EBUZ2_CODE_D*8 : LD BC,8 : CALL LDIRVM

    ; state2連射レーン用BG弾タイル2枚(左半分/右半分)+専用カラー
    LD HL,BULLET_L_TILE : LD DE,BULLET_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_R_TILE : LD DE,BULLET_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_BULLET_COLOR_BYTE : LD DE,COLTBL+9 : LD BC,1 : CALL LDIRVM

    ; (2026-09-19訂正: 旧くの字3連用hwスプライトパターンのSPRPAT
    ; ロード・SPRATRの非表示初期化は、HWスプライトを全廃したため
    ; 丸ごと削除。開幕ボレーはBULLET_L_CODE/BULLET_R_CODE[既に上で
    ; ロード済み]のBGタイルだけで表現する。)

    ; ワークエリアの明示ゼロ初期化(RAM初期化漏れ防止 - このコード
    ; ベースの繰り返しの教訓、Round36-14 follow-up#14参照)。
    XOR A
    LD (EBUZ2_TOPBOTTOM_ACTIVE),A
    LD (EBUZ2_FIRE_SIDE),A
    LD (EBUZ2_FIRE_COUNTDOWN),A
    LD (EBUZ2_TOP_NEXT),A
    LD (EBUZ2_BOTTOM_NEXT),A
    LD (EBUZ2_OSC_PHASE),A
    LD (EBUZ2_OSC_TIMER),A
    LD (EBUZ2_VOLLEY0_ACTIVE),A
    LD (EBUZ2_VOLLEY0_COLCUR),A
    LD (EBUZ2_VOLLEY1_ACTIVE),A
    LD (EBUZ2_VOLLEY1_COLCUR),A
    LD (EBUZ2_VOLLEY2_ACTIVE),A
    LD (EBUZ2_VOLLEY2_COLCUR),A
    LD A,EBUZ2_SLOT_EMPTY
    LD (EBUZ2_TOP_COLS+0),A
    LD (EBUZ2_TOP_COLS+1),A
    LD (EBUZ2_TOP_COLS+2),A
    LD (EBUZ2_TOP_COLS+3),A
    LD (EBUZ2_TOP_COLS+4),A
    LD (EBUZ2_TOP_COLS+5),A
    LD (EBUZ2_TOP_COLS+6),A
    LD (EBUZ2_TOP_COLS+7),A
    LD (EBUZ2_BOTTOM_COLS+0),A
    LD (EBUZ2_BOTTOM_COLS+1),A
    LD (EBUZ2_BOTTOM_COLS+2),A
    LD (EBUZ2_BOTTOM_COLS+3),A
    LD (EBUZ2_BOTTOM_COLS+4),A
    LD (EBUZ2_BOTTOM_COLS+5),A
    LD (EBUZ2_BOTTOM_COLS+6),A
    LD (EBUZ2_BOTTOM_COLS+7),A

    ; --- state1描画 ---
    CALL EBUZ2_DRAW_STATE1
EBUZ2_STATE1_BG_DONE:

    ; --- ホールド(解放まで) ---
    LD B,EBUZ2_VOLLEY_HOLD_TICKS
    CALL EBUZ2_WAIT_TICKS

    ; --- 解放: 開幕ボレー(3本のBGレーン弾、斜め成分なし)を発射 ---
    CALL EBUZ2_FIRE_VOLLEY
EBUZ2_STATE1_DONE:

    ; --- state1→state2遷移(ノーウェイト、無印Ebuzの「それ以外の ---
    ; ウェイトは入れるな」の作法を踏襲)。
    CALL EBUZ2_DRAW_BASE
EBUZ2_STATE2_BG_DONE:

    ; --- state2形成後、連射開始までのホールド ---
    LD B,EBUZ2_TOPBOTTOM_HOLD_TICKS
    CALL EBUZ2_WAIT_TICKS

    ; --- 継続発射+oscillationを起動 ---
    XOR A
    LD (EBUZ2_FIRE_SIDE),A          ; 0=まず上側から
    LD A,1
    LD (EBUZ2_FIRE_COUNTDOWN),A     ; 次のティックで即発射
    XOR A
    LD (EBUZ2_OSC_PHASE),A          ; 0=base(→up待ち)
    LD A,EBUZ2_OSC_HOLD_TICKS
    LD (EBUZ2_OSC_TIMER),A
    LD A,1
    LD (EBUZ2_TOPBOTTOM_ACTIVE),A
EBUZ2_STATE2_DONE:

; --- 以後、EBUZ2_TICK自体がDI/EI/ウェイトを内包するため、単純に ---
; ループするだけでよい。
EBUZ2_MAINLOOP:
    CALL EBUZ2_TICK
EBUZ2_FRAME_TICK:
    JR EBUZ2_MAINLOOP

EBUZ2_COLOR_BYTE:
    DB EBUZ2_COLOR

EBUZ2_BULLET_COLOR_BYTE:
    DB EBUZ2_BULLET_COLOR

; 本体4タイル(無印Ebuzのタイルデータと完全に同一のバイト値 -
; オーケストレーション側で添付画像を差分照合し、新規タイルは不要と
; 確認済み)。
EBUZ2_TILE_A:
    DB 126,191,1,63,63,1,191,126
EBUZ2_TILE_B:
    DB 255,84,42,126,126,42,84,255
EBUZ2_TILE_C:
    DB 126,195,189,181,173,189,195,126
EBUZ2_TILE_D:
    DB 255,65,127,127,127,127,65,255

; 弾の8x8タイル2枚(無印EbuzのBULLET_L_TILE/BULLET_R_TILEと完全に
; 同一のバイト値、BGレーン弾・くの字3連hwスプライトの両方で共有)。
BULLET_L_TILE:
    DB 0,0,127,255,255,127,0,0
BULLET_R_TILE:
    DB 0,0,254,255,255,254,0,0
