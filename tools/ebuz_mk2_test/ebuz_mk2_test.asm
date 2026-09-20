; 新エネミー"Ebuz Mk2"(Ebuzの大型派生、中央砲台つき)のプロトタイプ
; 検証用、独立した空のSCREEN1テストROM。tools/ebuz_test/ebuz_test.asm
; (無印Ebuz)と全く同じ方法論 - 本編(src/CYBER SHMUP.asm)には一切
; 触れず、専用の空ステージでまず見た目・状態遷移・弾発射だけを検証する
; - をそのまま踏襲した、無印Ebuzの完全に独立した姉妹プロトタイプ。
; tools/ebuz_test/は一切変更していない(このファイルからも参照しない、
; 必要なタイルデータ・弾グラフィックは全てこのファイル内に直接複製済み)。
;
; ============================================================================
; 設計(2026-09-20、ユーザー原文ママによる全面確定版 - これ以前の
; 「開幕3連ボレー」「上下キャップからの固定発射」「外側/内側交互ペア」
; 「離散3ポジションoscillation」は全て試行錯誤の末に撤回・置換済み、
; 過去の版の詳細は本ファイルの会話ログ/gitの過去コミット参照):
;
;   "まず言ったように弾は5門の砲台から出る 最初はセンター 2の状態で
;    上下4門 数が違うだけでEbuzと同じ 次に全門発射 センター、内側2門
;    外側2門の順 そのループ で弾は上下動に合わせてY位置変わる スポーン
;    位置は上から来てRow9かな で、Row1から16まで上下動"
;
; 1. 本体は5"発射管"(本体5行それぞれが1門)- 外側上/内側上/中央/
;    内側下/外側下。中央=本体の縦方向の中心(最も幅広い行)、内側/外側は
;    その上下に1行おき。
; 2. state1(閉状態)のうちは中央の発射管だけが使え、解放の瞬間に1発
;    だけ発射する(無印Ebuzのbullet0と全く同じ「1発だけ」-「数が違う
;    だけでEbuzと同じ」)。
; 3. state1→state2遷移はノーウェイト(即座)。この瞬間、本体は元の
;    固定位置(nametable row3-7)から、oscillationの開始位置である
;    Row9("上から来てRow9かな")へ丸ごと移動する(旧位置は明示的に
;    消去、新位置に7行の開状態ボディを再描画)。
; 4. state2形成後は5門全てが使用可能になり、「中央→内側2門(上下同時)
;    →外側2門(上下同時)→最初に戻る」の3ステップを無限ループする。
;    各発射でその行の翼帯にリコイル(1セル右へ表示シフト、1ティック
;    後に戻す)がかかる、無印Ebuzと同じ作法。
; 5. 本体自身がnametable row1〜16の範囲を、離散的な往復ではなく1ティック
;    1行ずつ連続的にスイープし続ける(EBUZ2_OSC_ROW、MIN/MAXで反転)。
; 6. 各発射管の実際のY(nametable行)は「今その瞬間の本体位置
;    (EBUZ2_OSC_ROW)+その管のローカル行オフセット」から都度計算される
;    - つまり「弾は上下動に合わせてY位置変わる」を文字通り実装したもの。
;    発射された弾はX(列)方向にのみ1ティック1列で直進し、Y(行)は発射
;    された瞬間の値に完全固定される(斜め移動はしない、という既存の
;    恒久ルールは不変)。
; 7. 本体は発射後も動き続けるため、弾の消去(1ティック1列前進)で単純な
;    固定の復元テーブルを使うと「本体はもう別の行にいる」ケースで誤って
;    存在しない本体タイルを描いてしまう。これを避けるため、消去のたびに
;    「今この瞬間、この行・列に本体が実際に表示しているべきタイルは
;    何か」をEBUZ2_OSC_ROWから都度計算し直す(EBUZ2_BODY_TILE_AT、
;    EBUZ2_ROW_S2_0-6[後方で定義]を参照) - 2026-09-19時点の実機/
;    レンダリング確認で発見された「砲台は5門に増えてるぞ」(弾が
;    通過するたびに本体の翼タイルを剥ぎ取ってしまう)という事故の
;    根本原因への対策をそのまま新設計にも引き継いだもの。
;
; ステップ数・速度・間隔(EBUZ2_FIRE_INTERVAL/EBUZ2_OSC_STEP_TICKS等)は
; 全て未調整のプレースホルダー(下記の各EQU定数、コメントに明記)。
; ============================================================================
;
; --- 本体タイル構成(添付画像をオーケストレーション側で既存の無印Ebuz
; タイル[A,B,C,D、下記に再掲]とバイト単位で突き合わせ済み、新規タイル
; 一切不要でこの4枚の再配置だけで両状態を表現できる) ---
;
; --- state1(閉状態、5行x5列、row0が最上段、col0が最左列、空欄=code0) ---
;   row0: .  .  A  B  C        (col2,3,4)
;   row1: .  A  B  C  D        (col1,2,3,4)
;   row2: A  B  C  D  D        (col0,1,2,3,4 - 縦方向の中心、最も幅広い行)
;   row3: .  A  B  C  D        (row1と同一)
;   row4: .  .  A  B  C        (row0と同一)
;
; --- state2(開状態・砲台露出、7行x5列) ---
;   row0: .  .  A  B  C        (col2,3,4)                    <- 外側上
;   row1: .  A  B  C  C        (col1,2,3,4)                  <- 内側上
;   row2: .  .  .  .  D        (col4のみ - 砲台上キャップ、発射管ではない)
;   row3: A  B  C  D  D        (col0,1,2,3,4 - 中心行)        <- 中央
;   row4: .  .  .  .  D        (row2と同一 - 砲台下キャップ、発射管ではない)
;   row5: .  A  B  C  C        (row1と同一)                  <- 内側下
;   row6: .  .  A  B  C        (row0と同一)                  <- 外側下
;
; --- 列のname tableへのマッピング ---
; 無印Ebuzの規約(local col1 = EBUZ_COL = name table col24)をそのまま
; 踏襲: local col0→col23, col1→col24, col2→col25, col3→col26,
; col4→col27。このアセンブラは演算子優先順位も丸括弧も無い(左から右へ
; 逐次評価するだけ)ため、"NAMTBL+ROW*32+COL"式のような複合アドレス式は
; 直接書かず、EBUZ2_CALC_ADDR(後方で定義、B=row,C=colの2レジスタ入力)
; という専用ヘルパーで都度計算する(無印Ebuzが採用していた「事前計算
; 済みリテラル」方式は、本体・弾ともに行が実行時に連続変化するこの
; 新設計にはもう適用できないため、Mk2固有の対応)。
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
; 本ファイルはHWスプライトを一切使わずBG(name table)のみで完結する。

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
; 2026-09-20 全面訂正(ユーザー原文): "まず言ったように弾は5門の砲台
; から出る 最初はセンター 2の状態で上下4門 数が違うだけでEbuzと同じ
; 次に全門発射 センター、内側2門外側2門の順 そのループ で弾は上下動に
; 合わせてY位置変わる スポーン位置は上から来てRow9かな で、Row1から
; 16まで上下動"。
;
; これに伴い、旧来の「開幕3連ボレー」「上下キャップ発射」「外側/内側
; 交互ペア」の3設計は全て撤回・削除し、以下の統一設計に置き換える:
;
; 1. 発射管は5門固定(本体5行にそれぞれ1門ずつ - 開幕ボレーの
;    ウェッジ検討で確認済みの、先端ローカル列2,1,0,1,2の5行そのもの):
;    外側上(local row0)/内側上(local row1)/中央(local row2、
;    state2では中央=local row3)/内側下/外側下。
; 2. state1のうちは中央のみ発射(無印Ebuzのbullet0と全く同じ「1発だけ」
;    -「数が違うだけでEbuzと同じ」の通り)。
; 3. state2形成後は5門全てが使用可能になり、「中央→内側2門→外側2門→
;    (最初に戻る)」の3ステップを無限ループする(内側/外側はそれぞれ
;    上下2門が同時発射)。
; 4. 本体自身がname table row1〜16の範囲を連続的に(1ティック1行ずつ、
;    従来の「離散3ポジション往復」ではなく)往復し続け、各発射管の
;    現在位置([EBUZ2_OSC_ROW]+その管のローカル行オフセット)から弾が
;    発射される - つまり弾のY(発射行)は発射管が今どこにいるかで
;    毎回変わる。開始位置はRow9(中間、"上から来て"に対応する初期値)。
; 5. 弾自体はX方向(列)にのみ1ティック1列で直進し、Y(行)は発射された
;    瞬間の値に固定される(斜め移動はしない、という既存の恒久ルールは
;    不変)。ただし本体が弾の発射後も動き続けるため、消去時に単純な
;    固定の復元テーブルを使うと(本体がもう別の行にいるかもしれない
;    ため)誤って存在しない本体タイルを描いてしまう - 消去のたびに
;    「今この瞬間、この行・列に本体が実際に表示しているべきタイルは
;    何か」を[EBUZ2_OSC_ROW]から都度計算し直す(EBUZ2_BODY_TILE_AT)。
; ============================================================================

; 本体5"発射管"のローカル行オフセット(state2の7行レイアウトにおける
; EBUZ2_OSC_ROW[local row0の現在nt行]からの相対行)。row2/row4
; (添付画像の砲台キャップ)は発射管ではなく見た目のみのパーツ。
EBUZ2_OUTER_TOP_OFS    EQU 0
EBUZ2_INNER_TOP_OFS    EQU 1
EBUZ2_CENTER_OFS       EQU 3
EBUZ2_INNER_BOTTOM_OFS EQU 5
EBUZ2_OUTER_BOTTOM_OFS EQU 6

; 各発射管の発射開始列(「先端ローカル列-1」規約、既存の開幕ボレー検討
; で確定済みの値をそのまま流用- 外側[local row0/6]は先端nt25→24、
; 内側[row1/5]は先端nt24→23、中央[row3]は先端nt23→22)。
EBUZ2_OUTER_COL  EQU 24
EBUZ2_INNER_COL  EQU 23
EBUZ2_CENTER_COL EQU 22

EBUZ2_LANE_POOL_SIZE EQU 8
EBUZ2_SLOT_EMPTY EQU 255

; 発射シーケンス(中央→内側→外側→…)の1ステップあたりの間隔、
; およびリコイル持続(いずれも無印Ebuzの継続発射と同じ作法を踏襲、
; 未調整のプレースホルダー)。
EBUZ2_FIRE_INTERVAL   EQU 8
EBUZ2_RECOIL_DURATION EQU 1

; --- state1解放までのホールド ---(無印Ebuzの実機調整値をそのまま
; 初期値として踏襲、Mk2用に再調整はしていない)。
EBUZ2_VOLLEY_HOLD_TICKS EQU 10

; --- 本体の上下連続往復(oscillation)。離散3ポジションではなく、
; name table row[MIN]〜row[MAX]の範囲を1ティック1行ずつ連続的に
; 往復する。STEP_TICKSは1行進むまでの待ちティック数(未調整の仮値)。
; STARTは"上から来てRow9かな"に対応する初期位置(範囲のほぼ中間)。
EBUZ2_OSC_ROW_MIN   EQU 1
EBUZ2_OSC_ROW_MAX   EQU 16
EBUZ2_OSC_ROW_START EQU 9
EBUZ2_OSC_STEP_TICKS EQU 6

; state1もEBUZ2_OSC_ROW_START(Row9)に固定描画される(2026-09-20
; 「warp」修正: 旧設計はstate1をnametable row3-7の別位置に固定描画して
; おり、state2遷移の瞬間に本体全体がRow9へ瞬間移動する「ワープ」に
; 見えてしまっていた - 以後はstate1も最初からRow9起点で描画し、
; state1→state2遷移は同じ位置での5行→7行の形状変化のみにする)。
; ただしstate1(5行)とstate2(7行)ではローカル行番号のズレがある:
; state1の中央はrow_topから+2行目(row2local)だが、state2の中央は
; +3行目(row3local、上下キャップ2行が挿入されているため)。
; EBUZ2_FIRE_C_BULLETの発射行の式はOSC_ROW+CENTER_OFS(3)固定なので、
; state1の発射時だけEBUZ2_OSC_ROWを一時的にOSC_ROW_START-1(8)にして
; 発射すれば(8+3=11=row_top[9]+2=state1の中央行と正しく逆算)、
; state1/state2で発射ロジックを2重に持たずに済む。
EBUZ2_STATE1_OSC_ROW EQU EBUZ2_OSC_ROW_START-1

; state2形成後、連射+oscillation開始までのホールド(無印Ebuzの
; 実機調整値を踏襲、未調整のプレースホルダー)。
EBUZ2_TOPBOTTOM_HOLD_TICKS EQU 45

; ============================================================================
; RAMワークエリア(page3、無印Ebuzと同じ0F300h付近を再利用 - 別ROMの
; ため衝突しない。STACKTOP=0F380hまで十分な余白を確保している)。
; ============================================================================
EBUZ2_TOPBOTTOM_ACTIVE EQU 0F300h  ; 1 byte: 0=まだ非活性、1=連射+oscillation中
EBUZ2_FIRE_STEP        EQU 0F301h  ; 1 byte: 次に撃つステップ(0=中央/1=内側/2=外側)
EBUZ2_FIRE_COUNTDOWN   EQU 0F302h  ; 1 byte: 次の発射までの残りティック数
EBUZ2_RECOIL_STEP      EQU 0F303h  ; 1 byte: 直前に発射したステップ(反動を戻す対象)
EBUZ2_RECOIL_COUNTDOWN EQU 0F304h  ; 1 byte: 反動が元に戻るまでの残りティック数(0=反動なし)
EBUZ2_RECOIL_ROW_A     EQU 0F305h  ; 1 byte: 反動対象1行目の実nt行(発射した瞬間の値を保持)
EBUZ2_RECOIL_ROW_B     EQU 0F306h  ; 1 byte: 反動対象2行目(中央ステップでは未使用)
EBUZ2_OSC_ROW          EQU 0F307h  ; 1 byte: 現在のlocal row0のnt行(MIN-MAXで往復)
EBUZ2_OSC_DIR          EQU 0F308h  ; 1 byte: 1=下へ/0FFh=上へ
EBUZ2_OSC_TIMER        EQU 0F309h  ; 1 byte: 次の1行移動までの残りティック数
EBUZ2_C_NEXT           EQU 0F30Ah  ; 1 byte: 中央プールのローテーションカウンタ
EBUZ2_OT_NEXT          EQU 0F30Bh  ; 1 byte: 外側上の同上
EBUZ2_OB_NEXT          EQU 0F30Ch  ; 1 byte: 外側下の同上
EBUZ2_IT_NEXT          EQU 0F30Dh  ; 1 byte: 内側上の同上
EBUZ2_IB_NEXT          EQU 0F30Eh  ; 1 byte: 内側下の同上
EBUZ2_CUR_PORT_OFS     EQU 0F30Fh  ; 1 byte: EBUZ2_UPDATE_SLOT呼び出し前に
                            ; 各UPDATE_x_POOLが自分のローカル行オフセット
                            ; (EBUZ2_CENTER_OFS等)を書いておく作業変数。
                            ; 弾のYを毎ティック[EBUZ2_OSC_ROW]+この値から
                            ; 都度再計算する(「弾は上下動に合わせてY位置
                            ; 変わる」を文字通り実装 - 発射時点のYに固定
                            ; していた旧設計をここで撤回)。

; 各プール8スロット×2byte(ROW,COL)。ROW=EBUZ2_SLOT_EMPTY(255)で
; 非活性、それ以外は「発射された瞬間の実nt行」を保持したまま列だけが
; 毎ティック減っていく(Y成分固定・X成分のみ直進、という既存の
; 恒久ルール通り)。
EBUZ2_C_SLOTS  EQU 0F310h  ; 中央、16 bytes (8slot x 2)
EBUZ2_OT_SLOTS EQU 0F320h  ; 外側上、16 bytes
EBUZ2_OB_SLOTS EQU 0F330h  ; 外側下、16 bytes
EBUZ2_IT_SLOTS EQU 0F340h  ; 内側上、16 bytes
EBUZ2_IB_SLOTS EQU 0F350h  ; 内側下、16 bytes ( 0F35Fhで終了、STACKTOP
                            ; 0F380hまで32byteの余白あり)

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
; 本体形状データ(5byte/行、col23-27の順。0=空白セル)。state1は5行のみ
; 使用する専用データ(EBUZ2_ROW_S1_*)、state2は7行(EBUZ2_ROW_S2_*) -
; EBUZ2_DRAW_BODY_AT(後方で定義)がEBUZ2_OSC_ROWの現在値に応じて
; 任意のnametable行へこの7行分を描画する。EBUZ2_BODY_TILE_AT(後方)も
; この同じEBUZ2_ROW_S2_*データを弾の消去時の復元元として直接参照する
; ため、参照側より前に定義しておく必要がある(このアセンブラは前方
; 参照に対応しない - 過去のPAT_SASAPI前方参照バグと同型の制約)。
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
; 汎用アドレス計算: Input B=nametable行番号(0-23)、C=列番号(0-31)。
; Output: HL=NAMTBL+row*32+col。B,Cは保持されたまま返る(呼び出し元が
; そのまま使い回せるように)。破壊: AF,DE,HL。
; ============================================================================
EBUZ2_CALC_ADDR:
    PUSH BC
    LD A,B
    LD H,0 : LD L,A
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL          ; HL = row*32
    LD DE,NAMTBL
    ADD HL,DE
    POP BC
    LD D,0 : LD E,C
    ADD HL,DE           ; HL += col
    RET

; 本体は常に連続的に上下移動する(EBUZ2_OSC_ROW)ため、ある弾が発射
; された瞬間のnt行は、時間が経つと「今の本体の位置」とは一致しなく
; なる。したがって弾の消去は、固定の復元テーブルではなく「今この瞬間
; この(行,列)に本体が実際に表示しているべきタイルは何か」を都度
; EBUZ2_OSC_ROWから計算し直す必要がある(EBUZ2_ROW_S2_0-6は本体形状
; データそのもの、後方で定義)。
; Input: B=行, C=列。Output: A=タイル(本体の現在の占有範囲外なら0)。
; 破壊: AF,DE,HL。
EBUZ2_BODY_TILE_AT:
    LD A,(EBUZ2_OSC_ROW)
    LD D,A
    LD A,B
    SUB D
    JR C,EBUZ2_BTA_ZERO       ; row < OSC_ROW -> 本体の範囲外
    CP 7
    JR NC,EBUZ2_BTA_ZERO      ; local_row >= 7 -> 本体の範囲外
    LD D,A                     ; D = local_row(0-6)
    LD A,C
    SUB 23
    JR C,EBUZ2_BTA_ZERO        ; col < 23 -> 範囲外
    CP 5
    JR NC,EBUZ2_BTA_ZERO       ; local_col >= 5 -> 範囲外
    LD E,A                      ; E = local_col(0-4)
    LD H,0 : LD L,D
    ADD HL,HL                    ; *2
    ADD HL,HL                    ; *4
    LD A,L
    ADD A,D                       ; *4 + local_row = *5 (最大30、桁上がり無し)
    LD L,A
    LD H,0
    LD D,0
    ADD HL,DE                     ; += local_col
    LD DE,EBUZ2_ROW_S2_0
    ADD HL,DE
    LD A,(HL)
    RET
EBUZ2_BTA_ZERO:
    XOR A
    RET

; 弾スロット2byte(ROW,COL)の消去(0ではなくEBUZ2_BODY_TILE_ATで求めた
; 現在の本体タイルへ復元)。Input: B=行、C=列(呼び出し後もB,C保持 -
; 呼び出し元[EBUZ2_UPDATE_SLOT]が消去後もこの2値を読み続けるため、
; 内部でWRITE2用にB,Cを潰した後は必ず元の値へ戻してからRETすること)。
EBUZ2_ERASE_BC:
    CALL EBUZ2_CALC_ADDR       ; HL = addr(row=B,col=C)、B,Cは保持されたまま返る
    PUSH HL                      ; 保存: addr
    PUSH BC                      ; 保存: 元の(row,col)
    CALL EBUZ2_BODY_TILE_AT       ; B=row,C=colのまま -> A=左セルの復元値
    LD E,A
    LD A,C
    INC A
    LD C,A                        ; C=col+1(Bは行のまま不変)
    CALL EBUZ2_BODY_TILE_AT        ; -> A=右セルの復元値
    LD D,A
    POP BC                          ; 元の(row,col)を復元
    POP HL                          ; addrを復元
    PUSH BC                          ; WRITE2でB,Cを潰す前にもう一度退避
    LD B,E : LD C,D
    CALL EBUZ2_WRITE2
    POP BC                            ; 呼び出し元のためB,C=元の(row,col)へ戻す
    RET

; 弾スロット共通の1ティック更新。Input: HL=スロット先頭(ROWバイト、
; 直後にCOLバイトが続く)。ROW=EBUZ2_SLOT_EMPTYなら何もしない。
; 呼び出し元(各UPDATE_x_POOL)は事前に[EBUZ2_CUR_PORT_OFS]へ自分の
; ローカル行オフセットを書いておくこと - このスロットのYは発射時点で
; 固定するのではなく、毎ティック[EBUZ2_OSC_ROW]+[EBUZ2_CUR_PORT_OFS]
; から都度再計算し直す(「弾は上下動に合わせてY位置変わる」の実装、
; 2026-09-20訂正: 消去は「古い(行,列)に今あるべき本体タイル」を
; EBUZ2_ERASE_BC[EBUZ2_BODY_TILE_AT]で復元、再描画は「新しい(行,列)」
; へ - 古い行と新しい行が一致しない場合は本体の見た目に追従して
; 弾がジャンプしたように見えるが、これが仕様通りの挙動)。
EBUZ2_UPDATE_SLOT:
    LD A,(HL)
    CP EBUZ2_SLOT_EMPTY
    RET Z
    PUSH HL
    LD B,A                       ; B = old row(消去用)
    INC HL
    LD A,(HL)
    LD C,A                        ; C = old col(現在値)
    CALL EBUZ2_ERASE_BC           ; 古い位置を消す(本体タイルを復元)
    LD A,C
    OR A
    JR Z,EBUZ2_US_OFF
    DEC A
    LD C,A                         ; C = new col
    LD A,(EBUZ2_OSC_ROW)
    LD B,A
    LD A,(EBUZ2_CUR_PORT_OFS)
    ADD A,B
    LD B,A                          ; B = new row(本体の現在位置から都度再計算)
    POP HL
    LD (HL),B                        ; 新しい行を保存
    INC HL
    LD (HL),C                         ; 新しい列を保存
    CALL EBUZ2_CALC_ADDR                ; HL = addr(B=new row,C=new col)
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET
EBUZ2_US_OFF:
    POP HL
    LD (HL),EBUZ2_SLOT_EMPTY
    RET

; ============================================================================
; 5プール分の更新(中央/外側上/外側下/内側上/内側下)。中身は完全に
; 同一ロジック、対象スロット配列だけが違う - 汎用ループより見た目が
; 素直という、このファイル一貫の方針を踏襲。
; ============================================================================
EBUZ2_UPDATE_C_POOL:
    LD A,EBUZ2_CENTER_OFS : LD (EBUZ2_CUR_PORT_OFS),A
    LD HL,EBUZ2_C_SLOTS+0  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+2  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+4  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+6  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+8  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+10 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+12 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_C_SLOTS+14 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_OT_POOL:
    LD A,EBUZ2_OUTER_TOP_OFS : LD (EBUZ2_CUR_PORT_OFS),A
    LD HL,EBUZ2_OT_SLOTS+0  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+2  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+4  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+6  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+8  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+10 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+12 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OT_SLOTS+14 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_OB_POOL:
    LD A,EBUZ2_OUTER_BOTTOM_OFS : LD (EBUZ2_CUR_PORT_OFS),A
    LD HL,EBUZ2_OB_SLOTS+0  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+2  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+4  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+6  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+8  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+10 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+12 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_OB_SLOTS+14 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_IT_POOL:
    LD A,EBUZ2_INNER_TOP_OFS : LD (EBUZ2_CUR_PORT_OFS),A
    LD HL,EBUZ2_IT_SLOTS+0  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+2  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+4  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+6  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+8  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+10 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+12 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IT_SLOTS+14 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_IB_POOL:
    LD A,EBUZ2_INNER_BOTTOM_OFS : LD (EBUZ2_CUR_PORT_OFS),A
    LD HL,EBUZ2_IB_SLOTS+0  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+2  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+4  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+6  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+8  : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+10 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+12 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_IB_SLOTS+14 : CALL EBUZ2_UPDATE_SLOT
    RET

; ============================================================================
; 5門それぞれの発射。行は発射する瞬間の[EBUZ2_OSC_ROW]+自分のローカル
; オフセットから毎回計算する(「弾は上下動に合わせてY位置変わる」を
; そのまま実装したもの) - 発射後は弾自身のY(行)は固定、Xだけ直進。
; ============================================================================
EBUZ2_FIRE_C_BULLET:
    LD A,(EBUZ2_C_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FC_OK
    XOR A
EBUZ2_FC_OK:
    LD (EBUZ2_C_NEXT),A
    LD A,B : ADD A,A
    LD E,A : LD D,0
    LD HL,EBUZ2_C_SLOTS
    ADD HL,DE                     ; HL = スロット先頭(ROWバイト)
    LD A,(EBUZ2_OSC_ROW)
    ADD A,EBUZ2_CENTER_OFS
    LD (HL),A
    LD B,A                          ; B = row
    INC HL
    LD A,EBUZ2_CENTER_COL
    LD (HL),A
    LD C,A                           ; C = col
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_OT_BULLET:
    LD A,(EBUZ2_OT_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FOT_OK
    XOR A
EBUZ2_FOT_OK:
    LD (EBUZ2_OT_NEXT),A
    LD A,B : ADD A,A
    LD E,A : LD D,0
    LD HL,EBUZ2_OT_SLOTS
    ADD HL,DE
    LD A,(EBUZ2_OSC_ROW)
    ADD A,EBUZ2_OUTER_TOP_OFS
    LD (HL),A
    LD B,A
    INC HL
    LD A,EBUZ2_OUTER_COL
    LD (HL),A
    LD C,A
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_OB_BULLET:
    LD A,(EBUZ2_OB_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FOB_OK
    XOR A
EBUZ2_FOB_OK:
    LD (EBUZ2_OB_NEXT),A
    LD A,B : ADD A,A
    LD E,A : LD D,0
    LD HL,EBUZ2_OB_SLOTS
    ADD HL,DE
    LD A,(EBUZ2_OSC_ROW)
    ADD A,EBUZ2_OUTER_BOTTOM_OFS
    LD (HL),A
    LD B,A
    INC HL
    LD A,EBUZ2_OUTER_COL
    LD (HL),A
    LD C,A
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_IT_BULLET:
    LD A,(EBUZ2_IT_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FIT_OK
    XOR A
EBUZ2_FIT_OK:
    LD (EBUZ2_IT_NEXT),A
    LD A,B : ADD A,A
    LD E,A : LD D,0
    LD HL,EBUZ2_IT_SLOTS
    ADD HL,DE
    LD A,(EBUZ2_OSC_ROW)
    ADD A,EBUZ2_INNER_TOP_OFS
    LD (HL),A
    LD B,A
    INC HL
    LD A,EBUZ2_INNER_COL
    LD (HL),A
    LD C,A
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_IB_BULLET:
    LD A,(EBUZ2_IB_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FIB_OK
    XOR A
EBUZ2_FIB_OK:
    LD (EBUZ2_IB_NEXT),A
    LD A,B : ADD A,A
    LD E,A : LD D,0
    LD HL,EBUZ2_IB_SLOTS
    ADD HL,DE
    LD A,(EBUZ2_OSC_ROW)
    ADD A,EBUZ2_INNER_BOTTOM_OFS
    LD (HL),A
    LD B,A
    INC HL
    LD A,EBUZ2_INNER_COL
    LD (HL),A
    LD C,A
    CALL EBUZ2_CALC_ADDR
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

; リコイル用の翼帯データ(col23-28の6byte窓、無印Ebuzと同じ「発射時に
; 1セル右へシフト、1ティック後に戻す」作法)。中身は本体形状データ
; (EBUZ2_ROW_S2_0/1/3、後方で定義)と同一値 - 外側(row0/6)・内側
; (row1/5)・中央(row3)の3種類。行アドレスは発射時のEBUZ2_OSC_ROWから
; 都度計算するため、ここではデータ(中身)だけを持つ。
EBUZ2_OUTER_REST:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,0
EBUZ2_OUTER_RECOIL:
    DB 0,0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C
EBUZ2_INNER_REST:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C,0
EBUZ2_INNER_RECOIL:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_C
EBUZ2_CENTER_REST:
    DB EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D,0
EBUZ2_CENTER_RECOIL:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D

; Input: HL=6byteデータ先頭、B=対象nt行。col23起点へLDIRVM(破壊:AF,DE,HL,BC)。
EBUZ2_WRITE_RECOIL_ROW:
    PUSH HL
    LD C,23
    CALL EBUZ2_CALC_ADDR   ; HL = addr(row=B,col=23)
    PUSH HL
    POP DE
    POP HL
    LD BC,6
    CALL LDIRVM
    RET

; ============================================================================
; 発射シーケンス(中央→内側→外側→最初に戻る、無限ループ)。
; EBUZ2_FIRE_INTERVALごとに1ステップ進み、そのステップの発射管
; (中央=1門、内側/外側=上下2門ずつ)から一斉発射する。発射した行に
; リコイル(RECOILデータへ差し替え)、1ティック後にREST(平常状態)へ
; 戻す。行は発射した瞬間のEBUZ2_OSC_ROWから計算し、
; EBUZ2_RECOIL_ROW_A/Bへ保存しておく(戻す時点でEBUZ2_OSC_ROWがもう
; 動いているかもしれないため、発射時の行を必ず覚えておく必要がある)。
; ============================================================================
EBUZ2_UPDATE_SEQUENCE_FIRE:
    LD A,(EBUZ2_RECOIL_COUNTDOWN)
    OR A
    JR Z,EBUZ2_USF_SKIP_REVERT
    DEC A
    LD (EBUZ2_RECOIL_COUNTDOWN),A
    JR NZ,EBUZ2_USF_SKIP_REVERT
    LD A,(EBUZ2_RECOIL_STEP)
    OR A
    JR Z,EBUZ2_USF_REVERT_C
    CP 1
    JR Z,EBUZ2_USF_REVERT_I
    LD HL,EBUZ2_OUTER_REST : LD A,(EBUZ2_RECOIL_ROW_A) : LD B,A : CALL EBUZ2_WRITE_RECOIL_ROW
    LD HL,EBUZ2_OUTER_REST : LD A,(EBUZ2_RECOIL_ROW_B) : LD B,A : CALL EBUZ2_WRITE_RECOIL_ROW
    JR EBUZ2_USF_SKIP_REVERT
EBUZ2_USF_REVERT_C:
    LD HL,EBUZ2_CENTER_REST : LD A,(EBUZ2_RECOIL_ROW_A) : LD B,A : CALL EBUZ2_WRITE_RECOIL_ROW
    JR EBUZ2_USF_SKIP_REVERT
EBUZ2_USF_REVERT_I:
    LD HL,EBUZ2_INNER_REST : LD A,(EBUZ2_RECOIL_ROW_A) : LD B,A : CALL EBUZ2_WRITE_RECOIL_ROW
    LD HL,EBUZ2_INNER_REST : LD A,(EBUZ2_RECOIL_ROW_B) : LD B,A : CALL EBUZ2_WRITE_RECOIL_ROW
EBUZ2_USF_SKIP_REVERT:
    LD A,(EBUZ2_FIRE_COUNTDOWN)
    DEC A
    LD (EBUZ2_FIRE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ2_FIRE_INTERVAL
    LD (EBUZ2_FIRE_COUNTDOWN),A
    LD A,(EBUZ2_FIRE_STEP)
    OR A
    JR Z,EBUZ2_USF_FIRE_C
    CP 1
    JR Z,EBUZ2_USF_FIRE_I
    ; --- 外側(上下2門) ---
    LD A,(EBUZ2_OSC_ROW) : ADD A,EBUZ2_OUTER_TOP_OFS : LD (EBUZ2_RECOIL_ROW_A),A
    LD B,A : LD HL,EBUZ2_OUTER_RECOIL : CALL EBUZ2_WRITE_RECOIL_ROW
    LD A,(EBUZ2_OSC_ROW) : ADD A,EBUZ2_OUTER_BOTTOM_OFS : LD (EBUZ2_RECOIL_ROW_B),A
    LD B,A : LD HL,EBUZ2_OUTER_RECOIL : CALL EBUZ2_WRITE_RECOIL_ROW
    CALL EBUZ2_FIRE_OT_BULLET
    CALL EBUZ2_FIRE_OB_BULLET
    JR EBUZ2_USF_FIRE_DONE
EBUZ2_USF_FIRE_C:
    LD A,(EBUZ2_OSC_ROW) : ADD A,EBUZ2_CENTER_OFS : LD (EBUZ2_RECOIL_ROW_A),A
    LD B,A : LD HL,EBUZ2_CENTER_RECOIL : CALL EBUZ2_WRITE_RECOIL_ROW
    CALL EBUZ2_FIRE_C_BULLET
    JR EBUZ2_USF_FIRE_DONE
EBUZ2_USF_FIRE_I:
    LD A,(EBUZ2_OSC_ROW) : ADD A,EBUZ2_INNER_TOP_OFS : LD (EBUZ2_RECOIL_ROW_A),A
    LD B,A : LD HL,EBUZ2_INNER_RECOIL : CALL EBUZ2_WRITE_RECOIL_ROW
    LD A,(EBUZ2_OSC_ROW) : ADD A,EBUZ2_INNER_BOTTOM_OFS : LD (EBUZ2_RECOIL_ROW_B),A
    LD B,A : LD HL,EBUZ2_INNER_RECOIL : CALL EBUZ2_WRITE_RECOIL_ROW
    CALL EBUZ2_FIRE_IT_BULLET
    CALL EBUZ2_FIRE_IB_BULLET
EBUZ2_USF_FIRE_DONE:
    LD A,(EBUZ2_FIRE_STEP)
    LD (EBUZ2_RECOIL_STEP),A
    LD A,EBUZ2_RECOIL_DURATION
    LD (EBUZ2_RECOIL_COUNTDOWN),A
    LD A,(EBUZ2_FIRE_STEP)
    INC A
    CP 3
    JR C,EBUZ2_USF_STEP_OK
    XOR A
EBUZ2_USF_STEP_OK:
    LD (EBUZ2_FIRE_STEP),A
    RET

; ============================================================================
; state1本体の汎用描画(5行)。Input: A=row_top。EBUZ2_ROW_S1_0-4を
; row_top〜row_top+4へ順にLDIRVMする(2026-09-20「warp」修正:
; 旧設計の固定nt3-7描画を廃し、state2のEBUZ2_DRAW_BODY_ATと同じ
; row_topパラメータ方式にした - state1もRow9から描画を開始する
; ことで、state1→state2遷移が「別位置への瞬間移動」ではなく
; 「同じ位置での5行→7行の形状変化」になる)。
; ============================================================================
EBUZ2_DRAW_STATE1_AT:
    PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S1_0 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S1_1 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S1_2 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S1_3 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S1_4 : POP DE : LD BC,5 : CALL LDIRVM
    RET

; ============================================================================
; 本体形状の汎用描画/消去(state2、7行)。Input: A=row_top(local row0の
; 目標nt行)。EBUZ2_ROW_S2_0-6(後方で定義)を7行分、row_top〜row_top+6
; へ順にLDIRVMする。従来の3ポジション固定(base/up/down)を廃し、
; 任意の実行時row_topに対応させたもの(oscillationの連続往復用)。
; ============================================================================
EBUZ2_DRAW_BODY_AT:
    PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_0 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_1 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_2 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_3 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_4 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_6 : POP DE : LD BC,5 : CALL LDIRVM
    RET

EBUZ2_ERASE_BODY_AT:
    PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    RET

; ============================================================================
; 本体の連続上下往復(oscillation)。EBUZ2_OSC_TIMERが0になるたび1行
; だけ移動(消す→EBUZ2_OSC_ROW+=DIR→描く)、MIN/MAXで反転する。
; 離散3ポジションの旧設計を全廃し、指定範囲(row1-16)を連続的に
; スイープする方式に変更(「Row1から16まで上下動」への対応)。
; ============================================================================
EBUZ2_UPDATE_OSCILLATION:
    LD A,(EBUZ2_OSC_TIMER)
    DEC A
    LD (EBUZ2_OSC_TIMER),A
    RET NZ
    LD A,EBUZ2_OSC_STEP_TICKS
    LD (EBUZ2_OSC_TIMER),A
    LD A,(EBUZ2_OSC_ROW)
    CALL EBUZ2_ERASE_BODY_AT
    LD A,(EBUZ2_OSC_DIR)
    LD B,A
    LD A,(EBUZ2_OSC_ROW)
    ADD A,B
    LD (EBUZ2_OSC_ROW),A
    CP EBUZ2_OSC_ROW_MAX
    JR NZ,EBUZ2_UO_CHECKMIN
    LD A,0FFh
    LD (EBUZ2_OSC_DIR),A
    JR EBUZ2_UO_DRAW
EBUZ2_UO_CHECKMIN:
    CP EBUZ2_OSC_ROW_MIN
    JR NZ,EBUZ2_UO_DRAW
    LD A,1
    LD (EBUZ2_OSC_DIR),A
EBUZ2_UO_DRAW:
    LD A,(EBUZ2_OSC_ROW)
    CALL EBUZ2_DRAW_BODY_AT
EBUZ2_OSC_SHIFT_DONE:               ; テスト用: 1回の移動完了の目印
    RET

; ============================================================================
; 1"フレーム"分の処理: 5プールの弾更新(常時)→継続発射中なら発射
; シーケンス+oscillation更新→ウェイト。
; ============================================================================
EBUZ2_TICK:
    DI
    CALL EBUZ2_UPDATE_C_POOL
    CALL EBUZ2_UPDATE_OT_POOL
    CALL EBUZ2_UPDATE_OB_POOL
    CALL EBUZ2_UPDATE_IT_POOL
    CALL EBUZ2_UPDATE_IB_POOL
    LD A,(EBUZ2_TOPBOTTOM_ACTIVE)
    OR A
    CALL NZ,EBUZ2_UPDATE_SEQUENCE_FIRE
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
    LD (EBUZ2_FIRE_STEP),A
    LD (EBUZ2_FIRE_COUNTDOWN),A
    LD (EBUZ2_RECOIL_STEP),A
    LD (EBUZ2_RECOIL_COUNTDOWN),A
    LD (EBUZ2_RECOIL_ROW_A),A
    LD (EBUZ2_RECOIL_ROW_B),A
    LD (EBUZ2_OSC_TIMER),A
    LD (EBUZ2_C_NEXT),A
    LD (EBUZ2_OT_NEXT),A
    LD (EBUZ2_OB_NEXT),A
    LD (EBUZ2_IT_NEXT),A
    LD (EBUZ2_IB_NEXT),A
    LD (EBUZ2_CUR_PORT_OFS),A
    LD A,1
    LD (EBUZ2_OSC_DIR),A
    LD A,EBUZ2_SLOT_EMPTY
    LD (EBUZ2_C_SLOTS+0),A  : LD (EBUZ2_C_SLOTS+2),A  : LD (EBUZ2_C_SLOTS+4),A  : LD (EBUZ2_C_SLOTS+6),A
    LD (EBUZ2_C_SLOTS+8),A  : LD (EBUZ2_C_SLOTS+10),A : LD (EBUZ2_C_SLOTS+12),A : LD (EBUZ2_C_SLOTS+14),A
    LD (EBUZ2_OT_SLOTS+0),A  : LD (EBUZ2_OT_SLOTS+2),A  : LD (EBUZ2_OT_SLOTS+4),A  : LD (EBUZ2_OT_SLOTS+6),A
    LD (EBUZ2_OT_SLOTS+8),A  : LD (EBUZ2_OT_SLOTS+10),A : LD (EBUZ2_OT_SLOTS+12),A : LD (EBUZ2_OT_SLOTS+14),A
    LD (EBUZ2_OB_SLOTS+0),A  : LD (EBUZ2_OB_SLOTS+2),A  : LD (EBUZ2_OB_SLOTS+4),A  : LD (EBUZ2_OB_SLOTS+6),A
    LD (EBUZ2_OB_SLOTS+8),A  : LD (EBUZ2_OB_SLOTS+10),A : LD (EBUZ2_OB_SLOTS+12),A : LD (EBUZ2_OB_SLOTS+14),A
    LD (EBUZ2_IT_SLOTS+0),A  : LD (EBUZ2_IT_SLOTS+2),A  : LD (EBUZ2_IT_SLOTS+4),A  : LD (EBUZ2_IT_SLOTS+6),A
    LD (EBUZ2_IT_SLOTS+8),A  : LD (EBUZ2_IT_SLOTS+10),A : LD (EBUZ2_IT_SLOTS+12),A : LD (EBUZ2_IT_SLOTS+14),A
    LD (EBUZ2_IB_SLOTS+0),A  : LD (EBUZ2_IB_SLOTS+2),A  : LD (EBUZ2_IB_SLOTS+4),A  : LD (EBUZ2_IB_SLOTS+6),A
    LD (EBUZ2_IB_SLOTS+8),A  : LD (EBUZ2_IB_SLOTS+10),A : LD (EBUZ2_IB_SLOTS+12),A : LD (EBUZ2_IB_SLOTS+14),A

    ; --- state1描画(Row9から、"上から来てRow9かな"に対応する初期位置に
    ; 最初から固定描画する - 2026-09-20「warp」修正、以後state1→state2
    ; 遷移で本体が別位置へ移動することはない) ---
    LD A,EBUZ2_OSC_ROW_START
    LD (EBUZ2_OSC_ROW),A
    CALL EBUZ2_DRAW_STATE1_AT
EBUZ2_STATE1_BG_DONE:

    ; --- ホールド(解放まで) ---
    LD B,EBUZ2_VOLLEY_HOLD_TICKS
    CALL EBUZ2_WAIT_TICKS

    ; --- 解放: 中央の発射管から1発だけ発射(「最初はセンター」-
    ; state1のうちは無印Ebuzのbullet0と同じく1発のみ)。state1は
    ; row_top=9固定描画・中央はrow_top+2(local row2)にいるため、
    ; EBUZ2_OSC_ROWを一時的にEBUZ2_STATE1_OSC_ROW(=OSC_ROW_START-1=8)
    ; にしてからstate2用と同じEBUZ2_FIRE_C_BULLETを呼べば、
    ; OSC_ROW+CENTER_OFS(3)=8+3=11=row_top(9)+2と正しく逆算される。
    LD A,EBUZ2_STATE1_OSC_ROW
    LD (EBUZ2_OSC_ROW),A
    CALL EBUZ2_FIRE_C_BULLET
EBUZ2_STATE1_DONE:

    ; --- state1→state2遷移(ノーウェイト、無印Ebuzの「それ以外の ---
    ; ウェイトは入れるな」の作法を踏襲)。本体は同じrow_top(9)のまま、
    ; 5行(state1)→7行(state2)の形状だけを描き直す(位置移動はしない -
    ; 発射時に一時的に8へ変えたEBUZ2_OSC_ROWを実際の値(9)へ戻す)。
    LD A,EBUZ2_OSC_ROW_START
    LD (EBUZ2_OSC_ROW),A
    CALL EBUZ2_DRAW_BODY_AT
EBUZ2_STATE2_BG_DONE:

    ; --- state2形成後、連射開始までのホールド ---
    LD B,EBUZ2_TOPBOTTOM_HOLD_TICKS
    CALL EBUZ2_WAIT_TICKS

    ; --- 継続発射(中央→内側→外側→…)+oscillationを起動 ---
    XOR A
    LD (EBUZ2_FIRE_STEP),A          ; 0=まず中央から
    LD A,1
    LD (EBUZ2_FIRE_COUNTDOWN),A     ; 次のティックで即発射
    LD A,EBUZ2_OSC_STEP_TICKS
    LD (EBUZ2_OSC_TIMER),A
    LD A,1
    LD (EBUZ2_OSC_DIR),A            ; まず下方向(row16)へ
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
