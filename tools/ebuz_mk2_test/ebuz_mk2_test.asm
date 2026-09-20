; 新エネミー"Ebuz Mk2"のプロトタイプ検証用、独立した空のSCREEN1テスト
; ROM。tools/ebuz_test/ebuz_test.asm(無印Ebuz)と同じ方法論 - 本編
; (src/CYBER SHMUP.asm)には一切触れず、専用の空ステージで見た目・
; 動作だけを検証する。
;
; ============================================================================
; 2026-09-20 三度目の全面リセット+ その後6回の追加訂正(ユーザー原文、
; 6回目[最新]の訂正、2連続):
;
;   "下から描画はそれでいいが 上から下に向かって画面に描画しながら
;    なんでこんな事が分からねんだよ 1手目は2行目にキャラの下3セル分
;    2手目は今描いた3セルを1セル下に移動して また2行目に4セル分
;    これを高さ分"
;   "揃うまで下にシフトするんだよ 分かったか"
;
; 5回目の訂正(直前の版)で実装した「フェーズA中は本体を静止させたまま
; 下段→上段の順に1行ずつ出現させ、全5行が揃ってから初めて移動を開始
; する」という2段階(静止して組み上がり→揃ってから移動)構成が誤りと
; 判明。正しくは、組み上がりと移動を分離せず「新しく出現する行は常に
; 固定の挿入位置(row1)に描画し、既に描画済みの行は毎ステップ必ず1行
; 下へシフト(再描画)する」という、組み上がりながら降りてくる単一の
; ベルトコンベア式動作でなければならない。フェーズA(登場フェーズ)は
; この方式に全面書き直し。5ステップ終了時点で最終的な行配置(row1に
; 先頭行が来る形)は5回目の版と一致するため、フェーズB(揃った後の
; 画面中央への平行移動)は無変更のまま継続して使える。
;
; 直前の版までの経緯(添付Ebuzmkii1_64x64_2.json[Mk2閉状態の実絵柄]で
; 確認済み): このステップの本体は「Ebuz Mk2-1」(閉状態、無印Ebuzと
; ほぼ同じ5行の見た目)であって、5門の砲台が露出した「Ebuz Mk2-2」
; (開状態、7行、砲台キャップ2行を追加した変形後の姿)ではない。開状態
; 関連のコードは全て削除済み(次にMk2-2の変形ステップを実装する時に
; 改めて追加する)。
;
; ============================================================================
; 2026-09-20 7回目の追加訂正(ユーザー原文、添付Ebuzmkii2_64x64_2.json
; [開状態Mk2-2の実絵柄]で確認済み):
;
;   "じゃあリコイル動作 今回は一斉発射だから 全体が1セル右に動いて戻る
;    降りてくる動きは今の倍に その後添付ファイルに変形 中央から1発
;    内側2門から1発 外側2門から1発 ここまで"
;
; 上記1-4(下記)に加えて以下を実装:
; 6. 登場(フェーズA+B)の速度を2倍に(EBUZ2_ENTRY_STEP_HOLD_TICKS
;    8→4、両フェーズとも同じEBUZ2_ENTRY_HOLDを使うため自動的に
;    両方が速くなる)。
; 7. 一斉発射(4番)の直後、リコイルとして本体全体(閉状態のまま、
;    個別の発射管ごとではない)が1セル右へ動いてから元の位置へ戻る。
; 8. リコイル後、開状態Mk2-2(7行、添付JSONを実際にPythonで解析し
;    5行閉状態と全く同じ4タイルで構成されることを確認済み)へ変形
;    (row9中央固定のまま、形状のみ差し替え)。
; 9. 変形後、5門(外側上/内側上/中央/内側下/外側下)から同時に1発ずつ
;    発射(中央1発+内側2門1発ずつ+外側2門1発ずつ=合計5発)。
; 10. **ここまでで今回の実装は終わり**。以後は本体(開状態)は動かず、
;     連射もしない。oscillation・無限連射・さらなる変形は次回以降の
;     別ステップとして、この土台が確認できてから改めて追加する。
; ============================================================================
;
; **前回(6回目)までに実装済みのもの**:
;
; 1. 画面row0(1行目)は常にブラックのブランクセルで塗りつぶす。
;    画面row20-23(下から4行)は常にホワイトのブランクセルで塗りつぶす。
;    本編ではこの5行を実際に使用するため、本体・弾は絶対にこの範囲へ
;    描画してはならない(侵入禁止)。
; 2. 登場フェーズA: 本体(Ebuz Mk2-1、閉状態、5行)が「揃うまで下に
;    シフトする」ベルトコンベア式で出現する(新たに出現する行は常に
;    row1に描画され、既存行は毎ステップ1行ずつ下へシフト)。
; 3. 登場フェーズB: 全5行が揃ったら、そのまま本体全体(形状は変えず
;    剛体のまま)を1ステップ1行ずつ画面中央(EBUZ2_ENTRY_TARGET_ROW_TOP
;    =9)まで下方向へ平行移動する。
; 4. 中央に到達したら、本体の5行それぞれから同時に1発ずつ発射する
;    (合計5発 - 「無印Ebuzの初弾[1発]が5発になっただけ」、本体の
;    見た目は無印Ebuzとほぼ同じ閉状態のまま、変形は一切しない)。
;    弾のY(行)は発射時点で完全固定、Xだけ直進。
;
; ユーザーの「テストで待たせるな」指示を踏まえ、今回もverify_*.pyの
; テストスイート更新は行わず、実装とROMビルド+レンダリングによる
; 視覚確認のみで進める。
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

; Ebuz Mk2-1(閉状態)の本体は5行×5列、添付Ebuzmkii1_64x64_2.jsonを
; 実際に解析して確認した通り無印Ebuzと同一のタイル4枚(EBUZ2_TILE_A-D)
; で構成される。5行それぞれの先頭から1発ずつ、計5発を同時発射する
; (「無印Ebuzの初弾[1発]が5発になっただけ」)。各発射管の発射開始列は
; 「先端ローカル列-1」規約のまま(row0/4[外側寄り、幅の狭い行]は
; nt25→24、row1/3[内側寄り]はnt24→23、row2[中央、最も幅広い行]は
; nt23→22)。
EBUZ2_OUTER_COL  EQU 24
EBUZ2_INNER_COL  EQU 23
EBUZ2_CENTER_COL EQU 22

; 各発射管のnametable行ベースアドレス(col0のVRAMアドレス、無印Ebuzの
; EBUZ_ROW1_BASE等と全く同じ扱い - コンパイル時定数)。5門は必ず
; EBUZ2_ENTRY_TARGET_ROW_TOP(9)〜+4の5行でのみ発射され、本体は発射後
; 二度と動かないためこれは安全にコンパイル時定数にできる(NAMTBL+
; row*32、このアセンブラは演算子優先順位が無いため事前計算した値を
; そのまま書く - row9=1920h,10=1940h,11=1960h,12=1980h,13=19A0h)。
EBUZ2_ROW_0_BASE EQU 1920h  ; row9  (local row0、外側寄り)
EBUZ2_ROW_1_BASE EQU 1940h  ; row10 (local row1、内側寄り)
EBUZ2_ROW_2_BASE EQU 1960h  ; row11 (local row2、中央)
EBUZ2_ROW_3_BASE EQU 1980h  ; row12 (local row3、内側寄り)
EBUZ2_ROW_4_BASE EQU 19A0h  ; row13 (local row4、外側寄り)

EBUZ2_LANE_POOL_SIZE EQU 8
EBUZ2_SLOT_EMPTY EQU 255

; --- 登場アニメーション(2026-09-20新設、二度の訂正を経て確定: 形状
; 変化・成長演出は一切無し、剛体のまま上から中央へ移動するだけ) ---
; ENTRY_TOP_ROWは本体をrow0ガード帯のすぐ下に一度に描画する行
; (local row0の到達nt行=1、"上から来て"に対応)。
; ENTRY_TARGET_ROW_TOPは移動フェーズの目標(画面中央、local row0の
; 到達nt行)。ENTRY_STEP_HOLD_TICKSは移動の各1行ステップの間隔ティック
; 数(未調整のプレースホルダー - 1ティックでは速すぎて人間の目には
; 「いきなり出現した」ようにしか見えないため導入)。
EBUZ2_ENTRY_TOP_ROW        EQU 1
EBUZ2_ENTRY_TARGET_ROW_TOP EQU 9
; 2026-09-20 追加訂正「降りてくる動きは今の倍に」を受け8→4(登場の
; シフト成長・中央への並進移動、両フェーズとも同じEBUZ2_ENTRY_HOLDを
; 使うため両方が自動的に2倍速になる)。
EBUZ2_ENTRY_STEP_HOLD_TICKS EQU 4

; --- Ebuz Mk2-2(開状態、7行、添付Ebuzmkii2_64x64_2.jsonを実際に
; Pythonで解析して確認済み)の発射管定数。5門(外側上/内側上/中央/
; 内側下/外側下)はrow_top=EBUZ2_ENTRY_TARGET_ROW_TOP(9)固定(変形後は
; 二度と動かない)。行ベースアドレスはrow9=1920h,10=1940h,12=1980h,
; 14=19C0h,15=19E0h。
;
; 発射列は既存のEBUZ2_OUTER/INNER/CENTER_COL(24/23/22)を再利用しない
; - EBUZ2_WRITE2が2セル書くため、これらの列だと開状態の各行の実際の
; 先端タイル(row_S2_0/1/3/5/6のAタイル)を弾が直接上書きし、弾が
; 消えた後も単純ブランク消去のため二度と復元されず本体の絵が永久に
; 欠けてしまう(閉状態[5行]の1斉射でも同じ現象は起きるが、直後の
; リコイルがEBUZ2_DRAW_BODY_ATで全行を再描画し直すため偶然隠れている
; だけで、変形後はもう再描画の機会が無い)。無印Ebuzが全く同じ問題を
; 自己発見して"EBUZ_BULLET23_COL=22"(本体の絵と物理的に一切重ならない
; 列に統一)で解決した前例(tools/ebuz_test/ebuz_test.asmの
; EBUZ_BULLET23_COL定義直前コメント参照)に倣い、開状態5門は全て
; col21(本体footprint[col23-27]より確実に左、5行とも常に背景のまま)
; から統一して発射する。 ---
EBUZ2_ROW_OT_BASE  EQU 1920h  ; row9  (開状態local row0、外側上)
EBUZ2_ROW_IT_BASE  EQU 1940h  ; row10 (開状態local row1、内側上)
EBUZ2_ROW_S2C_BASE EQU 1980h  ; row12 (開状態local row3、中央)
EBUZ2_ROW_IB_BASE  EQU 19C0h  ; row14 (開状態local row5、内側下)
EBUZ2_ROW_OB_BASE  EQU 19E0h  ; row15 (開状態local row6、外側下)
EBUZ2_S2_FIRE_COL  EQU 21

; ============================================================================
; RAMワークエリア(page3、無印Ebuzと同じ0F300h付近を再利用 - 別ROMの
; ため衝突しない)。2026-09-20リセットでoscillation/発射シーケンス/
; リコイル関連のRAMは全て削除、必要最小限のみ残す。
; ============================================================================
EBUZ2_BODY_ROW     EQU 0F300h  ; 1 byte: 本体の現在のlocal row0のnt行
                                ; (登場の移動フェーズでのみ使用、発射後は不変)
EBUZ2_NEXT_0       EQU 0F301h  ; 1 byte: local row0プールのローテーションカウンタ
EBUZ2_NEXT_1       EQU 0F302h  ; 1 byte: local row1の同上
EBUZ2_NEXT_2       EQU 0F303h  ; 1 byte: local row2(中央)の同上
EBUZ2_NEXT_3       EQU 0F304h  ; 1 byte: local row3の同上
EBUZ2_NEXT_4       EQU 0F305h  ; 1 byte: local row4の同上
; EBUZ2_UPDATE_SLOT(共有プール更新ルーチン)が参照する「今どの行を
; 対象にしているか」のスクラッチ(呼び出し元がCALL直前にセットする、
; 無印EbuzのEBUZ_CUR_ROW_BASEと全く同じ役割)。
EBUZ2_CUR_ROW_BASE EQU 0F306h  ; 2 bytes

; 開状態(Mk2-2)5門分のローテーションカウンタ(0F308h-0F30Ch、
; 0F307hは未使用の1byteパディング)。
EBUZ2_S2_OT_NEXT EQU 0F308h
EBUZ2_S2_IT_NEXT EQU 0F309h
EBUZ2_S2_C_NEXT  EQU 0F30Ah
EBUZ2_S2_IB_NEXT EQU 0F30Bh
EBUZ2_S2_OB_NEXT EQU 0F30Ch

; 各プール8スロット×1byte(列番号のみ、無印EbuzのEBUZ_TOP_COLS等と
; 全く同じ設計 - 行はプールごとにEBUZ2_ROW_*_BASEで固定)。
; EBUZ2_SLOT_EMPTY(255)で非活性。
EBUZ2_COLS_0 EQU 0F310h  ; local row0、8 bytes
EBUZ2_COLS_1 EQU 0F318h  ; local row1、8 bytes
EBUZ2_COLS_2 EQU 0F320h  ; local row2(中央)、8 bytes
EBUZ2_COLS_3 EQU 0F328h  ; local row3、8 bytes
EBUZ2_COLS_4 EQU 0F330h  ; local row4、8 bytes(0F337hで終了)

; 開状態(Mk2-2)5門分の列プール(0F338h以降、閉状態プールの直後)。
EBUZ2_S2_OT_COLS EQU 0F338h  ; 外側上、8 bytes
EBUZ2_S2_IT_COLS EQU 0F340h  ; 内側上、8 bytes
EBUZ2_S2_C_COLS  EQU 0F348h  ; 中央、8 bytes
EBUZ2_S2_IB_COLS EQU 0F350h  ; 内側下、8 bytes
EBUZ2_S2_OB_COLS EQU 0F358h  ; 外側下、8 bytes(0F35Fhで終了、
                               ; STACKTOP=0F380hまで余裕あり)

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
; 本体形状データ(5byte/行、col23-27の順。0=空白セル)。Ebuz Mk2-1
; (閉状態、5行)のみを使用する - 添付Ebuzmkii1_64x64_2.jsonの64x64
; ビットマップを実際にPythonで解析し(8x8セル単位に分解、非ゼロ
; セルをタイル化・重複排除)、得られた5x5セルの配置とタイルの
; ビットパターンを直接書き起こしたもの(無印Ebuzのタイル4枚
; [EBUZ2_TILE_A-D]とバイト単位で完全一致することも確認済み)。
; ============================================================================
EBUZ2_BLANK5:
    DB 0,0,0,0,0

EBUZ2_ROW_0:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C
EBUZ2_ROW_1:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D
EBUZ2_ROW_2:
    DB EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D,EBUZ2_CODE_D
EBUZ2_ROW_3:
    DB 0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C,EBUZ2_CODE_D
EBUZ2_ROW_4:
    DB 0,0,EBUZ2_CODE_A,EBUZ2_CODE_B,EBUZ2_CODE_C

; ============================================================================
; Ebuz Mk2-2(開状態、7行)の本体形状データ。添付Ebuzmkii2_64x64_2.json
; の64x64ビットマップを実際にPythonで解析(bbox行0-55/列0-39=7x5セル
; グリッドを検出、各セルを8x8タイル化・重複排除)して得たもの。
; 抽出した4種のタイルはビット単位でEBUZ2_TILE_A-D(閉状態と同じ)と
; 完全一致することを確認済みのため、新規タイルデータは不要 -
; EBUZ2_CODE_A-Dをそのまま再利用する。
; ============================================================================
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

; プール(5門共通)の1スロット分の更新。IN: HL=スロットの列番号バイトの
; アドレス、EBUZ2_CUR_ROW_BASE=このプールが使う行の先頭アドレス
; (呼び出し元がCALL直前にセット)。非アクティブなら何もしない。
; 生きていれば現在位置を消し、列を1減算、画面外(-1)になったら
; 非アクティブ化して終了、そうでなければ新しい位置に描き直す
; (無印EbuzのEBUZ_UPDATE_SLOTと全く同じ設計 - 本体は発射後動かない
; ため、本体タイル復元の仕組みは不要、単純にブランク(0,0)で消す)。
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

; ============================================================================
; 5プール分の更新(local row0〜row4)。各プール固定8スロットを明示的に
; 展開(無印EbuzのEBUZ_UPDATE_TOP_POOL等と同じ作法)。
; ============================================================================
EBUZ2_UPDATE_POOL_0:
    LD HL,EBUZ2_ROW_0_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_COLS_0+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_0+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_1:
    LD HL,EBUZ2_ROW_1_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_COLS_1+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_1+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_2:
    LD HL,EBUZ2_ROW_2_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_COLS_2+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_2+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_3:
    LD HL,EBUZ2_ROW_3_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_COLS_3+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_3+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_4:
    LD HL,EBUZ2_ROW_4_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_COLS_4+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_COLS_4+7 : CALL EBUZ2_UPDATE_SLOT
    RET

; ============================================================================
; 開状態(Mk2-2)5門分のプール更新(外側上/内側上/中央/内側下/外側下)。
; 変形前は各プールとも全スロットEBUZ2_SLOT_EMPTYのままなので、
; 変形前にEBUZ2_TICKから呼んでも何もしない(安全)。
; ============================================================================
EBUZ2_UPDATE_POOL_OT:
    LD HL,EBUZ2_ROW_OT_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_S2_OT_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OT_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_IT:
    LD HL,EBUZ2_ROW_IT_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_S2_IT_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IT_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_S2C:
    LD HL,EBUZ2_ROW_S2C_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_S2_C_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_C_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_IB:
    LD HL,EBUZ2_ROW_IB_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_S2_IB_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_IB_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

EBUZ2_UPDATE_POOL_OB:
    LD HL,EBUZ2_ROW_OB_BASE
    LD (EBUZ2_CUR_ROW_BASE),HL
    LD HL,EBUZ2_S2_OB_COLS+0 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+1 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+2 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+3 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+4 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+5 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+6 : CALL EBUZ2_UPDATE_SLOT
    LD HL,EBUZ2_S2_OB_COLS+7 : CALL EBUZ2_UPDATE_SLOT
    RET

; ============================================================================
; 本体5行それぞれからの発射(無印EbuzのEBUZ_FIRE_TOP_BULLET等と全く
; 同じ設計 - 行はコンパイル時定数のEBUZ2_ROW_*_BASE、生存チェック無しで
; プールの次のスロットを無条件に使う)。
; ============================================================================
EBUZ2_FIRE_0_BULLET:
    LD A,(EBUZ2_NEXT_0)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_F0_OK
    XOR A
EBUZ2_F0_OK:
    LD (EBUZ2_NEXT_0),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_COLS_0
    ADD HL,DE
    LD A,EBUZ2_OUTER_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_0_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_1_BULLET:
    LD A,(EBUZ2_NEXT_1)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_F1_OK
    XOR A
EBUZ2_F1_OK:
    LD (EBUZ2_NEXT_1),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_COLS_1
    ADD HL,DE
    LD A,EBUZ2_INNER_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_1_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_2_BULLET:
    LD A,(EBUZ2_NEXT_2)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_F2_OK
    XOR A
EBUZ2_F2_OK:
    LD (EBUZ2_NEXT_2),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_COLS_2
    ADD HL,DE
    LD A,EBUZ2_CENTER_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_2_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_3_BULLET:
    LD A,(EBUZ2_NEXT_3)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_F3_OK
    XOR A
EBUZ2_F3_OK:
    LD (EBUZ2_NEXT_3),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_COLS_3
    ADD HL,DE
    LD A,EBUZ2_INNER_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_3_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_4_BULLET:
    LD A,(EBUZ2_NEXT_4)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_F4_OK
    XOR A
EBUZ2_F4_OK:
    LD (EBUZ2_NEXT_4),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_COLS_4
    ADD HL,DE
    LD A,EBUZ2_OUTER_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_4_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

; ============================================================================
; 開状態(Mk2-2)5門それぞれからの発射(中央1発+内側2門1発ずつ+外側2門
; 1発ずつ、合計5発)。無印Ebuz/閉状態の発射管と全く同じ設計。
; ============================================================================
EBUZ2_FIRE_OT_BULLET:
    LD A,(EBUZ2_S2_OT_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FOT_OK
    XOR A
EBUZ2_FOT_OK:
    LD (EBUZ2_S2_OT_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_S2_OT_COLS
    ADD HL,DE
    LD A,EBUZ2_S2_FIRE_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_OT_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_IT_BULLET:
    LD A,(EBUZ2_S2_IT_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FIT_OK
    XOR A
EBUZ2_FIT_OK:
    LD (EBUZ2_S2_IT_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_S2_IT_COLS
    ADD HL,DE
    LD A,EBUZ2_S2_FIRE_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_IT_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_S2C_BULLET:
    LD A,(EBUZ2_S2_C_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FS2C_OK
    XOR A
EBUZ2_FS2C_OK:
    LD (EBUZ2_S2_C_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_S2_C_COLS
    ADD HL,DE
    LD A,EBUZ2_S2_FIRE_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_S2C_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_IB_BULLET:
    LD A,(EBUZ2_S2_IB_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FIB_OK
    XOR A
EBUZ2_FIB_OK:
    LD (EBUZ2_S2_IB_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_S2_IB_COLS
    ADD HL,DE
    LD A,EBUZ2_S2_FIRE_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_IB_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

EBUZ2_FIRE_OB_BULLET:
    LD A,(EBUZ2_S2_OB_NEXT)
    LD B,A
    INC A
    CP EBUZ2_LANE_POOL_SIZE
    JR C,EBUZ2_FOB_OK
    XOR A
EBUZ2_FOB_OK:
    LD (EBUZ2_S2_OB_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ2_S2_OB_COLS
    ADD HL,DE
    LD A,EBUZ2_S2_FIRE_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ2_ROW_OB_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ2_WRITE2
    RET

; ============================================================================
; 本体形状の汎用描画/消去(Ebuz Mk2-1閉状態、5行)。Input: A=row_top
; (local row0の目標nt行)。EBUZ2_ROW_0-4を5行分、row_top〜row_top+4へ
; 順にLDIRVMする(登場の移動フェーズで使用)。
; ============================================================================
EBUZ2_DRAW_BODY_AT:
    PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_0 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_1 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_2 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A : PUSH AF
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_3 : POP DE : LD BC,5 : CALL LDIRVM
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_4 : POP DE : LD BC,5 : CALL LDIRVM
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
    POP AF : INC A
    LD B,A : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    RET

; ============================================================================
; 1"フレーム"分の処理: 10プール(閉状態5+開状態5)の弾更新(常時)→
; ウェイト。開状態5プールは変形前は全スロットEBUZ2_SLOT_EMPTYのため
; 呼んでも無害(EBUZ2_UPDATE_SLOTが即RETするだけ)。
; 2026-09-20リセットでoscillation・発射シーケンスの呼び出しは削除
; (本体は発射後動かず、連射もしない)。
; ============================================================================
EBUZ2_TICK:
    DI
    CALL EBUZ2_UPDATE_POOL_0
    CALL EBUZ2_UPDATE_POOL_1
    CALL EBUZ2_UPDATE_POOL_2
    CALL EBUZ2_UPDATE_POOL_3
    CALL EBUZ2_UPDATE_POOL_4
    CALL EBUZ2_UPDATE_POOL_OT
    CALL EBUZ2_UPDATE_POOL_IT
    CALL EBUZ2_UPDATE_POOL_S2C
    CALL EBUZ2_UPDATE_POOL_IB
    CALL EBUZ2_UPDATE_POOL_OB
    EI
    CALL EBUZ2_FRAME_WAIT
    RET

; 登場の移動フェーズ専用: EBUZ2_ENTRY_STEP_HOLD_TICKS回だけEBUZ2_TICKを
; 呼ぶ(弾プールの更新を止めない待ち、1ティック=1行では速すぎて
; 「いきなり出現した」ようにしか見えないため)。
EBUZ2_ENTRY_HOLD:
    LD B,EBUZ2_ENTRY_STEP_HOLD_TICKS
EBUZ2_ENTRY_HOLD_LOOP:
    PUSH BC
    CALL EBUZ2_TICK
    POP BC
    DJNZ EBUZ2_ENTRY_HOLD_LOOP
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
    LD (EBUZ2_NEXT_0),A
    LD (EBUZ2_NEXT_1),A
    LD (EBUZ2_NEXT_2),A
    LD (EBUZ2_NEXT_3),A
    LD (EBUZ2_NEXT_4),A
    LD (EBUZ2_S2_OT_NEXT),A
    LD (EBUZ2_S2_IT_NEXT),A
    LD (EBUZ2_S2_C_NEXT),A
    LD (EBUZ2_S2_IB_NEXT),A
    LD (EBUZ2_S2_OB_NEXT),A
    LD A,EBUZ2_SLOT_EMPTY
    LD (EBUZ2_COLS_0+0),A  : LD (EBUZ2_COLS_0+1),A  : LD (EBUZ2_COLS_0+2),A  : LD (EBUZ2_COLS_0+3),A
    LD (EBUZ2_COLS_0+4),A  : LD (EBUZ2_COLS_0+5),A  : LD (EBUZ2_COLS_0+6),A  : LD (EBUZ2_COLS_0+7),A
    LD (EBUZ2_COLS_1+0),A  : LD (EBUZ2_COLS_1+1),A  : LD (EBUZ2_COLS_1+2),A  : LD (EBUZ2_COLS_1+3),A
    LD (EBUZ2_COLS_1+4),A  : LD (EBUZ2_COLS_1+5),A  : LD (EBUZ2_COLS_1+6),A  : LD (EBUZ2_COLS_1+7),A
    LD (EBUZ2_COLS_2+0),A  : LD (EBUZ2_COLS_2+1),A  : LD (EBUZ2_COLS_2+2),A  : LD (EBUZ2_COLS_2+3),A
    LD (EBUZ2_COLS_2+4),A  : LD (EBUZ2_COLS_2+5),A  : LD (EBUZ2_COLS_2+6),A  : LD (EBUZ2_COLS_2+7),A
    LD (EBUZ2_COLS_3+0),A  : LD (EBUZ2_COLS_3+1),A  : LD (EBUZ2_COLS_3+2),A  : LD (EBUZ2_COLS_3+3),A
    LD (EBUZ2_COLS_3+4),A  : LD (EBUZ2_COLS_3+5),A  : LD (EBUZ2_COLS_3+6),A  : LD (EBUZ2_COLS_3+7),A
    LD (EBUZ2_COLS_4+0),A  : LD (EBUZ2_COLS_4+1),A  : LD (EBUZ2_COLS_4+2),A  : LD (EBUZ2_COLS_4+3),A
    LD (EBUZ2_COLS_4+4),A  : LD (EBUZ2_COLS_4+5),A  : LD (EBUZ2_COLS_4+6),A  : LD (EBUZ2_COLS_4+7),A
    LD (EBUZ2_S2_OT_COLS+0),A : LD (EBUZ2_S2_OT_COLS+1),A : LD (EBUZ2_S2_OT_COLS+2),A : LD (EBUZ2_S2_OT_COLS+3),A
    LD (EBUZ2_S2_OT_COLS+4),A : LD (EBUZ2_S2_OT_COLS+5),A : LD (EBUZ2_S2_OT_COLS+6),A : LD (EBUZ2_S2_OT_COLS+7),A
    LD (EBUZ2_S2_IT_COLS+0),A : LD (EBUZ2_S2_IT_COLS+1),A : LD (EBUZ2_S2_IT_COLS+2),A : LD (EBUZ2_S2_IT_COLS+3),A
    LD (EBUZ2_S2_IT_COLS+4),A : LD (EBUZ2_S2_IT_COLS+5),A : LD (EBUZ2_S2_IT_COLS+6),A : LD (EBUZ2_S2_IT_COLS+7),A
    LD (EBUZ2_S2_C_COLS+0),A  : LD (EBUZ2_S2_C_COLS+1),A  : LD (EBUZ2_S2_C_COLS+2),A  : LD (EBUZ2_S2_C_COLS+3),A
    LD (EBUZ2_S2_C_COLS+4),A  : LD (EBUZ2_S2_C_COLS+5),A  : LD (EBUZ2_S2_C_COLS+6),A  : LD (EBUZ2_S2_C_COLS+7),A
    LD (EBUZ2_S2_IB_COLS+0),A : LD (EBUZ2_S2_IB_COLS+1),A : LD (EBUZ2_S2_IB_COLS+2),A : LD (EBUZ2_S2_IB_COLS+3),A
    LD (EBUZ2_S2_IB_COLS+4),A : LD (EBUZ2_S2_IB_COLS+5),A : LD (EBUZ2_S2_IB_COLS+6),A : LD (EBUZ2_S2_IB_COLS+7),A
    LD (EBUZ2_S2_OB_COLS+0),A : LD (EBUZ2_S2_OB_COLS+1),A : LD (EBUZ2_S2_OB_COLS+2),A : LD (EBUZ2_S2_OB_COLS+3),A
    LD (EBUZ2_S2_OB_COLS+4),A : LD (EBUZ2_S2_OB_COLS+5),A : LD (EBUZ2_S2_OB_COLS+6),A : LD (EBUZ2_S2_OB_COLS+7),A

    ; --- 登場フェーズA: 「揃うまで下にシフトする」方式。新たに出現する
    ; 行(本体自身の下段から順)は常に固定の挿入位置(nt1=EBUZ2_ENTRY_
    ; TOP_ROW)に描画し、既に描画済みの行は全てLDIRVMで1行下の位置へ
    ; そのまま再描画し直す(=結果として1行下にシフトする)。これを5
    ; ステップ繰り返すと、ベルトコンベアのように組み上がりながら降りて
    ; くる見た目になり、5ステップ目で全5行が揃うと同時に先頭行は
    ; ちょうどnt5まで降りている(=そのままフェーズBの開始位置と一致)。
    ; 描画先はコンパイル時定数(nt1,col23=1837h 〜 nt5,col23=18B7h、
    ; NAMTBL+row*32+23)を直接使い、実行時のEBUZ2_CALC_ADDR呼び出しは
    ; 使わない(このフェーズでは5箇所の行き先しかなく全て既知のため)。 ---
    LD A,EBUZ2_ENTRY_TOP_ROW
    LD (EBUZ2_BODY_ROW),A

    ; step 1/5: nt1に本体下段(local row4、幅3)
    LD HL,EBUZ2_ROW_4 : LD DE,1837h : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD

    ; step 2/5: 既存行をnt1のままにせず1行分下(nt2)へ再描画、
    ; 新規行(local row3)をnt1へ
    LD HL,EBUZ2_ROW_3 : LD DE,1837h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_4 : LD DE,1857h : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD

    ; step 3/5
    LD HL,EBUZ2_ROW_2 : LD DE,1837h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_3 : LD DE,1857h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_4 : LD DE,1877h : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD

    ; step 4/5
    LD HL,EBUZ2_ROW_1 : LD DE,1837h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_2 : LD DE,1857h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_3 : LD DE,1877h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_4 : LD DE,1897h : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD

    ; step 5/5: 全5行が揃い、EBUZ2_BODY_ROW(=EBUZ2_ENTRY_TOP_ROW)を
    ; 上端とする配置(nt1-nt5)に一致する - フェーズBはここからそのまま
    ; 継続できる
    LD HL,EBUZ2_ROW_0 : LD DE,1837h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_1 : LD DE,1857h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_2 : LD DE,1877h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_3 : LD DE,1897h : LD BC,5 : CALL LDIRVM
    LD HL,EBUZ2_ROW_4 : LD DE,18B7h : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD
EBUZ2_ENTRY_GROWTH_DONE:

    ; --- 登場フェーズB: 全5行が出現した状態から、そのまま画面中央
    ; (ENTRY_TARGET_ROW_TOP)まで1ステップ1行ずつ下方向へ
    ; 平行移動する(形状は変えず、剛体のまま並進移動するだけ)。
    ; 各ステップはEBUZ2_ENTRY_HOLDで間隔を空け、動きが見えるようにする。 ---
EBUZ2_ENTRY_MOVE_LOOP:
    LD A,(EBUZ2_BODY_ROW)
    CP EBUZ2_ENTRY_TARGET_ROW_TOP
    JR Z,EBUZ2_ENTRY_MOVE_DONE
    CALL EBUZ2_ERASE_BODY_AT      ; A=現在のrow_topで消去(注意: この
                                    ; ルーチンはAを保持しない - 戻り値は
                                    ; row_top+4になっている、以後使わない)
    LD A,(EBUZ2_BODY_ROW)           ; 現在のrow_topをRAMから読み直す
    INC A                             ; 下方向(nt行番号は下に行くほど
                                        ; 大きい)へ1行進める
    LD (EBUZ2_BODY_ROW),A
    CALL EBUZ2_DRAW_BODY_AT          ; A=新しいrow_topで再描画
    CALL EBUZ2_ENTRY_HOLD
    JR EBUZ2_ENTRY_MOVE_LOOP
EBUZ2_ENTRY_MOVE_DONE:

    ; --- 中央に到達: 本体5行それぞれから同時に1発ずつ発射(合計5発 -
    ; 「無印Ebuzの初弾[1発]が5発になっただけ」)。 ---
    CALL EBUZ2_FIRE_0_BULLET
    CALL EBUZ2_FIRE_1_BULLET
    CALL EBUZ2_FIRE_2_BULLET
    CALL EBUZ2_FIRE_3_BULLET
    CALL EBUZ2_FIRE_4_BULLET
EBUZ2_VOLLEY_DONE:

    ; --- リコイル: 「今回は一斉発射だから」個別の発射管ごとではなく
    ; 本体全体が単純に1セル右へ動いてから元の位置へ戻る(閉状態のまま、
    ; row9固定)。EBUZ2_DRAW_BODY_AT/EBUZ2_ERASE_BODY_ATは列23固定の
    ; ため、列24側は専用のインライン展開で描画/消去する。 ---
    LD A,EBUZ2_ENTRY_TARGET_ROW_TOP
    CALL EBUZ2_ERASE_BODY_AT      ; 現在位置(row9,col23)を消去
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP   : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_0 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+1 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_1 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+2 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_2 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+3 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_3 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+4 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_4 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD
    ; 戻す: 列24側(1セル右にずれた位置)を消去し、元の列23へ再描画
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP   : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+1 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+2 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+3 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+4 : LD C,24 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_BLANK5 : POP DE : LD BC,5 : CALL LDIRVM
    LD A,EBUZ2_ENTRY_TARGET_ROW_TOP
    CALL EBUZ2_DRAW_BODY_AT       ; 元の位置(row9,col23)へ再描画
    CALL EBUZ2_ENTRY_HOLD
EBUZ2_RECOIL_DONE:

    ; --- 変形: 閉状態(5行)を消去し、開状態Mk2-2(7行、row9-15)を
    ; 描画する。中央行はそのまま(row9固定)、以後は二度と動かない。 ---
    LD A,EBUZ2_ENTRY_TARGET_ROW_TOP
    CALL EBUZ2_ERASE_BODY_AT
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP   : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_0 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+1 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_1 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+2 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_2 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+3 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_3 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+4 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_4 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+5 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_5 : POP DE : LD BC,5 : CALL LDIRVM
    LD B,EBUZ2_ENTRY_TARGET_ROW_TOP+6 : LD C,23 : CALL EBUZ2_CALC_ADDR
    PUSH HL : LD HL,EBUZ2_ROW_S2_6 : POP DE : LD BC,5 : CALL LDIRVM
    CALL EBUZ2_ENTRY_HOLD
EBUZ2_TRANSFORM_DONE:

    ; --- 変形後、5門(外側上/内側上/中央/内側下/外側下)から同時に
    ; 1発ずつ発射(中央1発+内側2門1発ずつ+外側2門1発ずつ=合計5発)。 ---
    CALL EBUZ2_FIRE_OT_BULLET
    CALL EBUZ2_FIRE_IT_BULLET
    CALL EBUZ2_FIRE_S2C_BULLET
    CALL EBUZ2_FIRE_IB_BULLET
    CALL EBUZ2_FIRE_OB_BULLET
EBUZ2_VOLLEY2_DONE:

; --- 今回の実装はここまで。以後は本体(開状態)は動かず、連射もしない。
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
