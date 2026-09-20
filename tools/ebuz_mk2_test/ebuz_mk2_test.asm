; 新エネミー"Ebuz Mk2"のプロトタイプ検証用、独立した空のSCREEN1テスト
; ROM。tools/ebuz_test/ebuz_test.asm(無印Ebuz)と同じ方法論 - 本編
; (src/CYBER SHMUP.asm)には一切触れず、専用の空ステージで見た目・
; 動作だけを検証する。
;
; ============================================================================
; 2026-09-20 三度目の全面リセット(ユーザーからの強い叱責を受けての
; スコープ大幅縮小): 前の版は「弾がゴミのように散らばる」「本体が
; 勝手に上下動+連射し続ける」という酷評を受けた。ユーザー原文:
;
;   "お前は本当に順序と言うものが全く理解できてない...1ステップずつ
;    実装するしかないな まず登場 一気に全体を表示するんではなく
;    下から1セルずつ画面内に描画して 中央まで移動 その後5門全弾発射
;    まずここまで で、画面1行目と下から4行は破壊しない 侵入も描画も
;    禁止 本実装でそこは使用してるからな ちゃんと出来ているか見た目で
;    判断できないから 1行目はブラックでブランクセルを塗りつぶし
;    下から4行分はホワイトのブランクセルで塗りつぶし"
;
; これに伴い、oscillation(本体の上下連続往復)・発射シーケンスの無限
; ループ(中央→内側→外側の周回)・リコイル演出・state1/state2の閉/開
; 状態区別は全て撤回する。**このステップで実装するのはこれだけ**:
;
; 1. 画面row0(1行目)は常にブラックのブランクセルで塗りつぶす。
;    画面row20-23(下から4行)は常にホワイトのブランクセルで塗りつぶす。
;    本編ではこの5行を実際に使用するため、本体・弾は絶対にこの範囲へ
;    描画してはならない(侵入禁止)。見た目で違反が一目で分かるよう、
;    この2色は他のどの色とも混同しない専用の色グループを新設した。
; 2. 登場: 本体(5門の砲台が露出した開状態、7行)を一気に全部表示するの
;    ではなく、画面下端寄りの行(EBUZ2_ENTRY_BOTTOM_ROW=19、row20-23の
;    ガード帯のすぐ上)に下端を固定したまま、1ティックに1行ずつ下から
;    上へ積み上げるように描画していく(7ティックで全7行が出現)。
; 3. 全7行が出現したら、そのまま本体全体を1ティック1行ずつ画面中央
;    (EBUZ2_ENTRY_TARGET_ROW_TOP=9)まで平行移動する。
; 4. 中央に到達したら、5門(外側上/内側上/中央/内側下/外側下)全てから
;    同時に1発ずつ発射する(合計5発、無印Ebuzのような順番待ちは無い)。
; 5. **ここまでで今回の実装は終わり**。以後は本体は動かず、連射も
;    しない(発射済みの5発の弾がX方向に直進して消えるだけ)。
;    oscillation・無限連射・リコイル・state1閉状態は次回以降の別
;    ステップとして、この土台が確認できてから改めて追加する。
; ============================================================================
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

; --- ガードバンド専用のコード・色(2026-09-20新設) ---
; row0とrow20-23は本編で実際に使用する領域のため、本体・弾は絶対に
; 描画してはならない。違反が起きれば見た目で即座に分かるよう、他の
; どの色とも被らない専用の色グループ(group2/group3、無印Ebuzのタイル
; [group8]・弾[group9]・背景[group0]のいずれとも別)を新設し、
; ブランクセル(ビットパターン0のまま)をこの色で塗りつぶす。
GUARD_TOP_ROW    EQU 0    ; 画面1行目(ブラック)
GUARD_BOTTOM_ROW0 EQU 20  ; 下から4行(ホワイト)
GUARD_BOTTOM_ROW1 EQU 21
GUARD_BOTTOM_ROW2 EQU 22
GUARD_BOTTOM_ROW3 EQU 23
GUARD_BLACK_CODE  EQU 16  ; group2(codes16-23)
GUARD_WHITE_CODE  EQU 24  ; group3(codes24-31)
GUARD_BLACK_COLOR EQU 011h  ; fg1/bg1 = 黒/黒
GUARD_WHITE_COLOR EQU 0FFh  ; fg15/bg15 = 白/白

; 本体5"発射管"のローカル行オフセット(開状態の7行レイアウトにおける
; EBUZ2_BODY_ROW[local row0の現在nt行]からの相対行)。local row2/4
; (砲台キャップ)は発射管ではなく見た目のみのパーツ。
EBUZ2_OUTER_TOP_OFS    EQU 0
EBUZ2_INNER_TOP_OFS    EQU 1
EBUZ2_CENTER_OFS       EQU 3
EBUZ2_INNER_BOTTOM_OFS EQU 5
EBUZ2_OUTER_BOTTOM_OFS EQU 6

; 各発射管の発射開始列(「先端ローカル列-1」規約 - 外側[local row0/6]は
; 先端nt25→24、内側[row1/5]は先端nt24→23、中央[row3]は先端nt23→22)。
EBUZ2_OUTER_COL  EQU 24
EBUZ2_INNER_COL  EQU 23
EBUZ2_CENTER_COL EQU 22

EBUZ2_LANE_POOL_SIZE EQU 8
EBUZ2_SLOT_EMPTY EQU 255

; --- 登場アニメーション(2026-09-20新設、このステップの主題) ---
; ENTRY_BOTTOM_ROWは成長フェーズ中、本体の下端(local row6)を固定して
; おく行(row20-23のガード帯のすぐ上=row19、ガード帯には絶対触れない)。
; ENTRY_TARGET_ROW_TOPは移動フェーズの目標(画面中央、local row0の
; 到達nt行)。
EBUZ2_ENTRY_BOTTOM_ROW     EQU 19
EBUZ2_ENTRY_TARGET_ROW_TOP EQU 9

; ============================================================================
; RAMワークエリア(page3、無印Ebuzと同じ0F300h付近を再利用 - 別ROMの
; ため衝突しない)。2026-09-20リセットでoscillation/発射シーケンス/
; リコイル関連のRAMは全て削除、必要最小限のみ残す。
; ============================================================================
EBUZ2_BODY_ROW     EQU 0F300h  ; 1 byte: 本体の現在のlocal row0のnt行
EBUZ2_CUR_PORT_OFS EQU 0F301h  ; 1 byte: EBUZ2_UPDATE_SLOT呼び出し前に
                           ; 各UPDATE_x_POOLが自分のローカル行オフセット
                           ; を書いておく作業変数(弾のYを毎ティック
                           ; [EBUZ2_BODY_ROW]+この値から再計算するため)。
EBUZ2_C_NEXT       EQU 0F302h  ; 1 byte: 中央プールのローテーションカウンタ
EBUZ2_OT_NEXT      EQU 0F303h  ; 1 byte: 外側上の同上
EBUZ2_OB_NEXT      EQU 0F304h  ; 1 byte: 外側下の同上
EBUZ2_IT_NEXT      EQU 0F305h  ; 1 byte: 内側上の同上
EBUZ2_IB_NEXT      EQU 0F306h  ; 1 byte: 内側下の同上

; 各プール8スロット×2byte(ROW,COL)。ROW=EBUZ2_SLOT_EMPTY(255)で非活性。
EBUZ2_C_SLOTS  EQU 0F310h  ; 中央、16 bytes (8slot x 2)
EBUZ2_OT_SLOTS EQU 0F320h  ; 外側上、16 bytes
EBUZ2_OB_SLOTS EQU 0F330h  ; 外側下、16 bytes
EBUZ2_IT_SLOTS EQU 0F340h  ; 内側上、16 bytes
EBUZ2_IB_SLOTS EQU 0F350h  ; 内側下、16 bytes(0F35Fhで終了)

; ============================================================================
; 1フレーム相当のウェイト(無印Ebuzと同一の較正済みループ)。
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

; VRAMの連続2byteへ書き込む。IN: HL=左セルのアドレス、B=左セルへ書く値、
; C=右セルへ書く値。
EBUZ2_WRITE2:
    LD A,B
    CALL WRTVRM
    INC HL
    LD A,C
    CALL WRTVRM
    RET

; ガードバンド専用: Input B=nametable行番号、C=埋めるパターンコード。
; その行の32列全てをCで埋める(本体・弾の描画では使わない、ガード帯
; row0/row20-23の初期化専用)。EBUZ2_CALC_ADDR(後方で定義)は破壊:
; AF,DE,HLでCが生き残らないため、ここでは同じ「row*32」計算を単独で
; 展開する。
EBUZ2_FILL_ROW:
    PUSH BC
    LD A,B
    LD H,0 : LD L,A
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL
    ADD HL,HL          ; HL = row*32
    LD DE,NAMTBL
    ADD HL,DE            ; HL = NAMTBL + row*32 (col0)
    POP BC
    LD A,C
    LD B,32
EBUZ2_FR_LOOP:
    CALL WRTVRM
    INC HL
    DJNZ EBUZ2_FR_LOOP
    RET

; ============================================================================
; 本体形状データ(5byte/行、col23-27の順。0=空白セル)。開状態(7行)の
; みを使用する(2026-09-20リセットで閉状態[state1]は廃止)。
; EBUZ2_BODY_TILE_AT(後方)がこのデータを弾の消去時の復元元として直接
; 参照するため、参照側より前に定義しておく必要がある(このアセンブラは
; 前方参照に対応しない)。
; ============================================================================
EBUZ2_BLANK5:
    DB 0,0,0,0,0

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
; Output: HL=NAMTBL+row*32+col。B,Cは保持されたまま返る。
; 破壊: AF,DE,HL。
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

; 弾の消去は固定の復元テーブルではなく「今この瞬間この(行,列)に本体が
; 実際に表示しているべきタイルは何か」を都度EBUZ2_BODY_ROWから計算し
; 直す(本体タイルを剥ぎ取る事故を避けるため)。
; Input: B=行, C=列。Output: A=タイル(本体の現在の占有範囲外なら0)。
; 破壊: AF,DE,HL。
EBUZ2_BODY_TILE_AT:
    LD A,(EBUZ2_BODY_ROW)
    LD D,A
    LD A,B
    SUB D
    JR C,EBUZ2_BTA_ZERO       ; row < BODY_ROW -> 本体の範囲外
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
; 現在の本体タイルへ復元)。Input: B=行、C=列(呼び出し後もB,C保持)。
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
; ローカル行オフセットを書いておくこと(本ステップでは本体は発射後
; 動かないため実質固定行になるが、将来のoscillation再導入に備えて
; ライブ計算のまま残す)。
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
    LD A,(EBUZ2_BODY_ROW)
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
; 5プール分の更新(中央/外側上/外側下/内側上/内側下)。
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
; 5門それぞれの発射。行は発射する瞬間の[EBUZ2_BODY_ROW]+自分のローカル
; オフセットから計算する。発射後は弾自身のY(行)は固定、Xだけ直進
; (毎ティックのライブ再計算はEBUZ2_UPDATE_SLOT側で行う)。
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
    LD A,(EBUZ2_BODY_ROW)
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
    LD A,(EBUZ2_BODY_ROW)
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
    LD A,(EBUZ2_BODY_ROW)
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
    LD A,(EBUZ2_BODY_ROW)
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
    LD A,(EBUZ2_BODY_ROW)
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

; ============================================================================
; 本体形状の汎用描画/消去(開状態、7行)。Input: A=row_top(local row0の
; 目標nt行)。EBUZ2_ROW_S2_0-6を7行分、row_top〜row_top+6へ順にLDIRVM
; する(登場の移動フェーズで使用)。
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
; 1"フレーム"分の処理: 5プールの弾更新(常時)→ウェイト。
; 2026-09-20リセットでoscillation・発射シーケンスの呼び出しは削除
; (本体は発射後動かず、連射もしない)。
; ============================================================================
EBUZ2_TICK:
    DI
    CALL EBUZ2_UPDATE_C_POOL
    CALL EBUZ2_UPDATE_OT_POOL
    CALL EBUZ2_UPDATE_OB_POOL
    CALL EBUZ2_UPDATE_IT_POOL
    CALL EBUZ2_UPDATE_IB_POOL
    EI
    CALL EBUZ2_FRAME_WAIT
    RET

; ============================================================================
INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32

    ; --- ガードバンド(row0=ブラック、row20-23=ホワイト)を最初に
    ; 塗りつぶす。本体・弾は以後絶対にこの5行へ描画しない。 ---
    LD B,GUARD_TOP_ROW    : LD C,GUARD_BLACK_CODE : CALL EBUZ2_FILL_ROW
    LD B,GUARD_BOTTOM_ROW0 : LD C,GUARD_WHITE_CODE : CALL EBUZ2_FILL_ROW
    LD B,GUARD_BOTTOM_ROW1 : LD C,GUARD_WHITE_CODE : CALL EBUZ2_FILL_ROW
    LD B,GUARD_BOTTOM_ROW2 : LD C,GUARD_WHITE_CODE : CALL EBUZ2_FILL_ROW
    LD B,GUARD_BOTTOM_ROW3 : LD C,GUARD_WHITE_CODE : CALL EBUZ2_FILL_ROW
    LD HL,GUARD_BLACK_COLOR_BYTE : LD DE,COLTBL+2 : LD BC,1 : CALL LDIRVM
    LD HL,GUARD_WHITE_COLOR_BYTE : LD DE,COLTBL+3 : LD BC,1 : CALL LDIRVM
EBUZ2_GUARD_DONE:

    ; 背景は空(code0のまま)なので、使用可能領域(row1-19)を無印Ebuzと
    ; 同じ空色に。
    LD HL,EBUZ2_COLOR_BYTE : LD DE,COLTBL+0 : LD BC,1 : CALL LDIRVM
    LD HL,EBUZ2_COLOR_BYTE : LD DE,COLTBL+8 : LD BC,1 : CALL LDIRVM

    ; 本体4タイル(A,B,C,D)をロード
    LD HL,EBUZ2_TILE_A : LD DE,EBUZ2_CODE_A*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_B : LD DE,EBUZ2_CODE_B*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_C : LD DE,EBUZ2_CODE_C*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_TILE_D : LD DE,EBUZ2_CODE_D*8 : LD BC,8 : CALL LDIRVM

    ; 弾用BGタイル2枚(左半分/右半分)+専用カラー
    LD HL,BULLET_L_TILE : LD DE,BULLET_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_R_TILE : LD DE,BULLET_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ2_BULLET_COLOR_BYTE : LD DE,COLTBL+9 : LD BC,1 : CALL LDIRVM

    ; ワークエリアの明示ゼロ初期化(RAM初期化漏れ防止)。
    XOR A
    LD (EBUZ2_CUR_PORT_OFS),A
    LD (EBUZ2_C_NEXT),A
    LD (EBUZ2_OT_NEXT),A
    LD (EBUZ2_OB_NEXT),A
    LD (EBUZ2_IT_NEXT),A
    LD (EBUZ2_IB_NEXT),A
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

    ; --- 登場フェーズA: 下端をrow19に固定し、1ティックに1行ずつ
    ; 下から上へ積み上げて描画する(7ティックで全7行が出現)。 ---
    LD B,EBUZ2_ENTRY_BOTTOM_ROW : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_6 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-1 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_5 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-2 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_4 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-3 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_3 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-4 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_2 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-5 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_1 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
    LD B,EBUZ2_ENTRY_BOTTOM_ROW-6 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_0 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_TICK
EBUZ2_ENTRY_GROWTH_DONE:

    ; --- 登場フェーズB: 全7行が出現した状態(row_top=ENTRY_BOTTOM_ROW-6)
    ; から、そのまま画面中央(ENTRY_TARGET_ROW_TOP)まで1ティック1行ずつ
    ; 平行移動する。 ---
    LD A,EBUZ2_ENTRY_BOTTOM_ROW-6
    LD (EBUZ2_BODY_ROW),A
EBUZ2_ENTRY_MOVE_LOOP:
    LD A,(EBUZ2_BODY_ROW)
    CP EBUZ2_ENTRY_TARGET_ROW_TOP
    JR Z,EBUZ2_ENTRY_MOVE_DONE
    CALL EBUZ2_ERASE_BODY_AT      ; A=現在のrow_topで消去(注意: この
                                    ; ルーチンはAを保持しない - 戻り値は
                                    ; row_top+6になっている、以後使わない)
    LD A,(EBUZ2_BODY_ROW)           ; 現在のrow_topをRAMから読み直す
    DEC A
    LD (EBUZ2_BODY_ROW),A
    CALL EBUZ2_DRAW_BODY_AT          ; A=新しいrow_topで再描画
    CALL EBUZ2_TICK
    JR EBUZ2_ENTRY_MOVE_LOOP
EBUZ2_ENTRY_MOVE_DONE:

    ; --- 中央に到達: 5門全てから同時に1発ずつ発射(合計5発)。 ---
    CALL EBUZ2_FIRE_C_BULLET
    CALL EBUZ2_FIRE_OT_BULLET
    CALL EBUZ2_FIRE_OB_BULLET
    CALL EBUZ2_FIRE_IT_BULLET
    CALL EBUZ2_FIRE_IB_BULLET
EBUZ2_VOLLEY_DONE:

; --- 今回の実装はここまで。以後は本体は動かず、連射もしない。
; 発射済みの弾がX方向に直進して消えるだけの単純なループ。 ---
EBUZ2_MAINLOOP:
    CALL EBUZ2_TICK
EBUZ2_FRAME_TICK:
    JR EBUZ2_MAINLOOP

EBUZ2_COLOR_BYTE:
    DB EBUZ2_COLOR

EBUZ2_BULLET_COLOR_BYTE:
    DB EBUZ2_BULLET_COLOR

GUARD_BLACK_COLOR_BYTE:
    DB GUARD_BLACK_COLOR

GUARD_WHITE_COLOR_BYTE:
    DB GUARD_WHITE_COLOR

; 本体4タイル(無印Ebuzのタイルデータと完全に同一のバイト値)。
EBUZ2_TILE_A:
    DB 126,191,1,63,63,1,191,126
EBUZ2_TILE_B:
    DB 255,84,42,126,126,42,84,255
EBUZ2_TILE_C:
    DB 126,195,189,181,173,189,195,126
EBUZ2_TILE_D:
    DB 255,65,127,127,127,127,65,255

; 弾の8x8タイル2枚(無印EbuzのBULLET_L_TILE/BULLET_R_TILEと完全に
; 同一のバイト値)。
BULLET_L_TILE:
    DB 0,0,127,255,255,127,0,0
BULLET_R_TILE:
    DB 0,0,254,255,255,254,0,0
