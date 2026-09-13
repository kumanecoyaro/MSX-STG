; 新エネミー"Ebuz"のプロトタイプ検証用、独立した空のSCREEN1テストROM
; (2026-09-13、"新エネミー まず1の状態で上から登場 取り敢えず上から
; 3行目 X位置は192px...で、2の状態に変化 BG使用 動きや色々合わせるん
; で 専用の空ステージ1でそこまで")。
;
; (2026-09-13追記、ユーザー訂正: "間違えた これに変化 渡したEbuz2は
; また別のやつ" - 状態2の正しい画像はEbuz3_32x32.jsonで、最初に
; 添付されたEbuz2_32x32.jsonは無関係の別物だったと判明。以下は
; Ebuz3ベースに訂正済みの解析結果。)
;
; 添付されたEbuz1_32x32.json/Ebuz3_32x32.jsonを解析した結果:
;   - Ebuz1は上下8pxが完全に空白で実質32x16px(タイル2行x4列)、
;     しかもその2行(row8-15とrow16-23)はピクセル単位で完全に同一
;     (4種類のユニークな8x8タイルA,B,C,Dだけで構成、Dはこのファイル
;     自身の右端キャップ)。
;   - Ebuz3も新しい絵ではなく、Ebuz1と全く同じ4タイル(A,B,C,D)だけを
;     並べ直したものとバイト単位で完全一致することを確認済み:
;       state1(2行x4列): 行1: A,B,C,D / 行2: A,B,C,D (2行とも同一)
;       state2(4行x4列): 新設上段:   (空白),A,B,C
;                         元の行1: (空白),(空白),(空白),D  ※A,B,Cが消える
;                         元の行2: (空白),(空白),(空白),D  ※A,B,Cが消える
;                         新設下段:   (空白),A,B,C
;     つまりA,B,Cの帯(24x8)が元の中央2行から丸ごと上下へ分離・移動し、
;     中央にはDタイル("背骨"のような右端キャップ)だけが残る - 羽が
;     上下に分かれて広がるような変化。新規タイルは一切不要、BGパターン
;     コード4個(A,B,C,D)だけで両状態を表現できる。
;
; (2026-09-13追記、弾発射): "Okこれでいい ではEbuz1で登場した時に
; 添付ファイルの弾を左へ発射 スプライトで で、Ebuz2に変化したら
; 添付ファイルの16x8部分だけの スプライトを上下から発射 1つはY位置
; 0px 2つ目は24pxの位置 つまりスプライトは2枚追加"(添付
; EbuzBullet1_16x16.json)。この弾グラフィック自体もEbuz本体と同じ
; 構造で、16x16キャンバス中に上下対称な同一の水平バーが2本(rows2-5と
; rows10-13、pixel単位で完全一致)描かれているだけと判明 -
; 上半分(rows0-7)がそのまま「16x8部分」に相当する(tools/ebuz_test/
; ebuz_bullet_gen.py参照)。
;   - state1登場時: BULLET_FULL(添付JSONそのまま、バー2本)を1枚、
;     Ebuz本体の左(X=192、Y=16=EBUZ_ROW*8、共に本体位置基準の暫定値・
;     具体的な指定なし)から左方向へ発射。
;   - state2変化時: BULLET_HALF(上半分だけを16x16へパディング、バー
;     1本)を2枚、Y=0pxとY=24px(ユーザー指定の絶対値そのまま)から
;     同時に左方向へ発射。
;   - 速度(EBUZ_BULLET_SPEED)は指定が無いため3px/frameの暫定値。
;
; (2026-09-13追記その2、発射位置/タイミング/速度の調整): "まずEbuz1
; の時の弾の位置を左へ16px移動 この状態で0.5秒維持してから発射
; 次に添付ファイルの弾をYが0px、24pxの位置から同時発射(添付
; EbuzBullet2_16x16.json)...弾の速度が早いんで半分に"、続けて
; (割り込みでの訂正)"同時発射はEbuz2に変形後な 同じく0.5秒維持して
; 同時発射"。
;   - state1弾(BULLET_FULL)の発射X位置をEBUZ_BULLET_X(192)から
;     16px左のEBUZ_BULLET1_X(176)へ変更。state2弾2枚(Y=0/24px)は
;     従来通りEBUZ_BULLET_X(192)のまま(こちらは"位置を移動"の指示
;     対象外)。
;   - EbuzBullet2_16x16.jsonを解析した結果、そのビットマップは既存の
;     BULLET_HALF_PAT(EbuzBullet1の上半分から自前で切り出したもの)と
;     TL/BL/TR/BR全象限バイト単位で完全一致(ebuz_bullet_gen.pyの
;     verify_against_ebuz_bullet2()で検証済み) - 新規タイルデータは
;     不要、BULLET_HALF_PATをそのまま「専用データとして正式に確認
;     済みの絵」として引き続き使用する。
;   - state1・state2いずれも「BGが変化した瞬間」と「実際に発射する
;     瞬間」を分離し、間に0.5秒相当のウェイト(EBUZ_DELAY_HALF、
;     EBUZ_DELAYのちょうど半分の反復回数)を挟む2段階構成に変更
;     (EBUZ_STATE1_BG_DONE/EBUZ_STATE2_BG_DONEを新設、EBUZ_STATE1_
;     DONE/EBUZ_STATE2_DONEは「発射まで完了した」時点を指す既存の
;     意味のまま維持)。
;   - 弾速半減: 3px/frameを整数のまま厳密に半分(1.5px/frame平均)に
;     するため、1px/2pxを1フレームおきに交互適用する方式を採用したが、
;     後のRound(その5"弾遅いんで速くしてくれ 2pxで"→その6"遅いな
;     6pxで")で単純な固定速度へ再変更、交互方式は撤去済み(詳細は
;     EBUZ_BULLET_SPEEDのEQU定義コメント参照)。
; 本ファイルは本編(src/CYBER SHMUP.asm)に組み込む前の独立した
; プロトタイプ("専用の空ステージ1")。背景は完全に空(code0の空白タイル
; のみ)で、Ebuzの見た目・状態遷移・弾発射/移動だけを確認する。実際の
; スケジュール組み込みは別途指示待ち。
    ORG 4000h

INIT32   EQU 006Fh
LDIRVM   EQU 005Ch
WRTVDP   EQU 0047h
VDP_ADDR EQU 099h
VDP_DATA EQU 098h

    DB "AB"
    DW INIT
    DW 0,0,0
    DS 6,0

STACKTOP EQU 0F380h
NAMTBL   EQU 1800h
COLTBL   EQU 2000h
SPRATR   EQU 1B00h
SPRPAT   EQU 3800h    ; sprite pattern generator table - BG(0000h)とは別のVRAM領域
RG1SAV   EQU 0F3E0h   ; BIOS RAM mirror of VDP register1

; Ebuz用に確保したBGパターンコード(このファイル専用の空環境なので
; 空き番地を厳密に監査する必要はないが、group8[codes64-71]境界に
; 揃えてcolor tableの1byteで済むようにしている)。
EBUZ_CODE_A EQU 64
EBUZ_CODE_B EQU 65
EBUZ_CODE_C EQU 66
EBUZ_CODE_D EQU 67
EBUZ_COLOR  EQU 015h   ; fg=1(black)/bg=5(light blue) - 添付JSONのfg/bgそのまま

; スポーン位置: "取り敢えず上から3行目"= name table row2(0-index、
; 上から3行目)、"X位置は192px" = col24(192/8)。state1はrow2/row3の
; 2行、state2はrow1〜row4の4行に拡張(元のrow2/row3は無変更のまま)。
EBUZ_ROW  EQU 2
EBUZ_COL  EQU 24

; --- 弾スプライト(hwスプライト、このファイル専用の独立空間なので ---
; --- 空き監査は不要、コード0番から素直に割り当て)                ---
BULLET_FULL_CODE EQU 0    ; 4コード(0-3)、TL/BL/TR/BR
BULLET_HALF_CODE EQU 4    ; 4コード(4-7)、TL/BL/TR/BR
EBUZ_BULLET_COLOR EQU 11  ; fg=11(light yellow) - 添付JSONのfgそのまま
EBUZ_BULLET_X      EQU 192   ; Ebuz本体のXから発射(暫定)、state2弾(Y0/24)用
EBUZ_BULLET1_X     EQU EBUZ_BULLET_X-16   ; state1弾は16px左へ移動(2026-09-13追記)
; 弾速(2026-09-13追記その5、実機フィードバック対応: "ようやくかよ
; 弾遅いんで速くしてくれ 2pxで"): 前回の半減(1px/2px交互で平均
; 1.5px/frame)を撤回し、単純な固定速度へ変更。1px/2px交互方式・
; EBUZ_FRAME_PARITYトグルは不要になったため削除。
; (2026-09-13追記その6、実機フィードバック対応: "遅いな6pxで")
; 2px/frameでもまだ遅いとの指摘で6px/frameへ再変更。
EBUZ_BULLET_SPEED EQU 6
; TMS9918のY属性は実際の表示開始行より1小さい値を書く規約
; (tools/stage1_render_check.pyのrender_full()と同じ"y1=(y+1)&0xFF"
; デコードに対応)。state1の弾はY=16(=EBUZ_ROW*8、本体位置基準の
; 暫定値、具体的な指定なし)。
;
; (2026-09-13追記その4、実機フィードバック対応: "で、Ebuz2の弾は2つとも
; 8px下げろ 絶対位置でやりやがって 当たり前だが相対位置に決まってん
; だろうが"): state2の2発は当初ユーザー指定のY=0px/24pxを本体位置とは
; 無関係な絶対値としてそのまま使っていたのが誤りだったと判明。8px
; 下げた新しい値(Y=8px/32px)は、state2のBG自体が使っている実際の行
; 位置と厳密に一致する - EBUZ_ROW_0ABC(新設上段の帯)はrow1=Y8pxに、
; EBUZ_ROW_0ABC(新設下段の帯)はrow4=Y32pxに描画されている(下記
; EBUZ_STATE2_BG_DONE直前のLDIRVM参照)。つまり本来は「本体の上翼帯・
; 下翼帯そのものの行位置」を基準にした相対値であるべきだった、という
; ことだと理解し、EBUZ_ROW_TOP_BAND/EBUZ_ROW_BOTTOM_BANDという名前の
; 行番号定数から導出する形に変更(将来これらの行番号自体が変わっても
; 弾のY位置が自動的に追従する)。
; desired Y=8/32はどちらも既存の「stored Y>=209は非表示」慣習と
; 数値上重ならない安全な値のため、以前のY=0固有だった1pxナッジ回避策
; (stored=255問題)は不要になった。
EBUZ_ROW_TOP_BAND    EQU 1   ; state2の新設上段(EBUZ_ROW_0ABC)の行番号
EBUZ_ROW_BOTTOM_BAND EQU 4   ; state2の新設下段(EBUZ_ROW_0ABC)の行番号
EBUZ_BULLET1_STORED_Y EQU 15    ; desired Y=16(state1、本体位置基準)  -> 16-1=15
EBUZ_BULLET2_STORED_Y EQU EBUZ_ROW_TOP_BAND*8-1     ; desired Y=8(上翼帯の行位置)  -> 8-1=7
EBUZ_BULLET3_STORED_Y EQU EBUZ_ROW_BOTTOM_BAND*8-1  ; desired Y=32(下翼帯の行位置) -> 32-1=31
SPR_HIDE_Y  EQU 209   ; 個別非表示(リストは継続、既存コードの規約と同じ)
SPR_TERM_Y  EQU 208   ; SATリスト終端(このスロット以降は描画されない)

; 弾3枚分のRAM側シャドウ(Y,X,pattern,color x3=12byte)。SPRATRは
; VRAMなのでZ80の通常のLD/SUB/CPで直接読み書きできない
; (OUT/INポート経由のVDP I/Oが必要) - 毎フレームの移動計算はこちらの
; RAM側で行い、更新後にLDIRVMでまとめてSPRATRへ反映する。
EBUZ_SPR_SHADOW EQU 0F350h   ; 12 bytes (F350h-F35Bh), STACKTOPまで十分な余裕

; (2026-09-13追記その3、実機フィードバック対応、最重要の設計変更):
; "だから違うって Ebuz1の時16x16のスプライトの弾を発射 その後Ebuz2に
; して上下から発射 人間の目がどうの関係ない お前は見えてないんだから
; 勝手に判断するな"。前回「EBUZ_FRAME_WAITが遅すぎて肉眼で見えない」と
; 自己診断したが、これは誤りだった。**真因はタイミングの体感速度では
; なく、構造的なバグ**: 旧実装は「BGが変化した瞬間」と「発射する瞬間」
; の間だけをEBUZ_DELAY/EBUZ_DELAY_HALFという素のビジーウェイトで
; つないでいたが、この待ち時間中はEBUZ_UPDATE_BULLETが一切呼ばれず、
; 既に発射済みのbullet0が完全に静止したままだった。bullet0は
; state1発射後、次の待ち(2x EBUZ_DELAY)・state2発射前の待ち
; (EBUZ_DELAY_HALF)の間ずっと本体のすぐ左に張り付いたまま動かず、
; **bullets1/2が発射されるまさにその瞬間になってようやく3発同時に
; 動き始める**構造になっていた(EBUZ_MAINLOOPが全弾発射完了後にしか
; 開始されないため)。そのためbullets1/2発射の瞬間、3発全てが本体
; すぐそばに集まって見え、「全て同時に発射してる」ように見えていた -
; これは実際にgif_check.pyのt=2.65s時点のフレームで再現・確認済みの、
; 正真正銘の構造的バグ(肉眼の速度とは無関係)。
;
; 修正: 「BG変化→待ち→発射」の待ち時間そのものを、弾の移動処理を
; 内包する新設EBUZ_TICK(1"フレーム"分の更新+反映+ウェイト)の
; 反復(EBUZ_WAIT_TICKS)に置き換えた。これによりbullet0は発射された
; その次のティックから即座に動き始め、以後の待ち時間中も継続して
; 移動・画面外での非表示化が進む - bullets1/2が発射される頃には
; bullet0は既に画面外へ消えているのが正しい挙動になる。
; EBUZ_DELAY/EBUZ_DELAY_HALF(素のビジーウェイトのみ、弾更新なし)は
; 完全に削除、EBUZ_MAINLOOPの本体もEBUZ_TICKへ集約し重複を排除した。

; 1フレーム相当のウェイト(弾移動のステップ間隔、EBUZ_TICKから毎回
; 呼ばれる)。B=15の2段ループ(256回×15周)で実測約61677T-states
; (約0.0172秒/回、3.58MHz Z80での1/60秒[0.01667秒]に近似)に較正済み
; (前Roundでの調整、体感速度の問題ではなかったと判明した今も、
; 単純に「1フレーム相当」の近似値として妥当なため維持)。
EBUZ_FRAME_WAIT:
    LD B,15
EBUZ_FRAME_WAIT_OUTER:
    LD C,0
EBUZ_FRAME_WAIT_INNER:
    DEC C
    JR NZ,EBUZ_FRAME_WAIT_INNER
    DJNZ EBUZ_FRAME_WAIT_OUTER
    RET

; IX = EBUZ_SPR_SHADOW内の弾スロット先頭(+0=Y,+1=X,+2=pattern,+3=color)。
; 非表示(Y=SPR_HIDE_Y)なら何もしない、そうでなければXをEBUZ_BULLET_
; SPEED(固定2px/frame)だけ減算(左へ移動)、画面外に出る場合は
; Y=SPR_HIDE_Yにして非表示化。
EBUZ_UPDATE_BULLET:
    LD A,(IX+0)
    CP SPR_HIDE_Y
    RET Z
    LD A,(IX+1)
    CP EBUZ_BULLET_SPEED
    JR NC,EBUZ_UB_MOVE
    LD (IX+0),SPR_HIDE_Y
    RET
EBUZ_UB_MOVE:
    SUB EBUZ_BULLET_SPEED
    LD (IX+1),A
    RET

; 1"フレーム"分の処理をまとめたもの: 弾3枠を更新→VRAMへ反映→ウェイト。
; EBUZ_WAIT_TICK系とEBUZ_MAINLOOPの両方から共有で呼ばれる(2026-09-13
; 追記その3、「待ち時間中は弾が動かない」構造的バグの修正 - 発射前の
; 弾はEBUZ_UPDATE_BULLET冒頭のSPR_HIDE_Yチェックで自動的にスキップ
; されるので、まだ発射されていないスロットに対して呼んでも安全)。
EBUZ_TICK:
    DI
    LD IX,EBUZ_SPR_SHADOW   : CALL EBUZ_UPDATE_BULLET
    LD IX,EBUZ_SPR_SHADOW+4 : CALL EBUZ_UPDATE_BULLET
    LD IX,EBUZ_SPR_SHADOW+8 : CALL EBUZ_UPDATE_BULLET
    LD HL,EBUZ_SPR_SHADOW : LD DE,SPRATR : LD BC,12 : CALL LDIRVM
    EI
    CALL EBUZ_FRAME_WAIT
    RET

; B=待ちたいティック数(1-255)。EBUZ_TICKをB回呼ぶだけの「弾の移動を
; 止めない待ち」- 旧来の素のビジーウェイト(EBUZ_DELAY等)を置き換える。
EBUZ_WAIT_TICKS:
EBUZ_WAIT_TICKS_LOOP:
    PUSH BC
    CALL EBUZ_TICK
    POP BC
    DJNZ EBUZ_WAIT_TICKS_LOOP
    RET

INIT:
    LD SP,STACKTOP
    DI
    CALL INIT32

    ; 背景は空(code0のまま、パターン未ロード=全消灯)なので、
    ; group0の色をEbuzと同じfg1/bg5にして画面全体を単色の空色に。
    LD HL,EBUZ_COLOR_BYTE : LD DE,COLTBL+0 : LD BC,1 : CALL LDIRVM
    LD HL,EBUZ_COLOR_BYTE : LD DE,COLTBL+8 : LD BC,1 : CALL LDIRVM

    ; Ebuzの4タイル(A,B,C,D)をロード
    LD HL,EBUZ_TILE_A : LD DE,EBUZ_CODE_A*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_B : LD DE,EBUZ_CODE_B*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_C : LD DE,EBUZ_CODE_C*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_TILE_D : LD DE,EBUZ_CODE_D*8 : LD BC,8 : CALL LDIRVM

    ; --- 弾スプライトを16x16モードで初期化 ---
    ; NOTE(自己発見バグ): 当初"LD DE,BULLET_FULL_CODE*8"と書いてBG用
    ; パターンジェネレータ(0000h)へ上書きしてしまい、地形/背景が
    ; チェッカーボード状に破損する実害バグを起こした - スプライトの
    ; パターンジェネレータはSPRPAT(3800h、BIOSデフォルト)というBGとは
    ; 全く別のVRAM領域にある(このプロジェクトのround36-14 follow-up#4
    ; 実機フィードバック対応その2で一度踏んでいるのと同型のミス)。
    ; さらにこのアセンブラは演算子優先順位が無いため"SPRPAT+CODE*8"も
    ; 書けず、事前計算済みリテラル(3800h+0*8=3800h、3800h+4*8=3820h)を
    ; 直接指定する。
    LD A,(RG1SAV) : OR 02h : LD (RG1SAV),A
    LD B,A : LD C,1 : CALL WRTVDP
    LD HL,BULLET_FULL_PAT : LD DE,03800h : LD BC,32 : CALL LDIRVM   ; SPRPAT+BULLET_FULL_CODE*8
    LD HL,BULLET_HALF_PAT : LD DE,03820h : LD BC,32 : CALL LDIRVM   ; SPRPAT+BULLET_HALF_CODE*8

    ; 弾3枚とも非表示で初期化(RAM側シャドウ+VRAM反映)、4枠目(スロット3)
    ; はSAT終端(SPR_TERM_Y)を一度だけ書けば以降は触らない。
    LD HL,EBUZ_SPR_INIT : LD DE,EBUZ_SPR_SHADOW : LD BC,12 : LDIR
    LD HL,EBUZ_SPR_SHADOW : LD DE,SPRATR : LD BC,12 : CALL LDIRVM
    LD HL,EBUZ_SPR_TERM : LD DE,SPRATR+12 : LD BC,4 : CALL LDIRVM

    ; --- state1: A,B,C,D を row2/row3 の col24-27 へ(2行とも同一) ---
    ; NOTE: このアセンブラは演算子優先順位も丸括弧も無い(左から右へ
    ; 逐次評価するだけ)ため、"NAMTBL+ROW*32+COL"式は書かず、name
    ; table上の絶対アドレスを事前計算したリテラルで直接指定する
    ; (EBUZ_ROW=2,EBUZ_COL=24,NAMTBL=1800h: row1=1838h,row2=1858h,
    ; row3=1878h,row4=1898h - tools/ebuz_test/render_check.py等で
    ; 再検証済み)。
    LD HL,EBUZ_ROW_ABCD
    LD DE,01858h                 ; row2, col24-27
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_ABCD
    LD DE,01878h                 ; row3, col24-27
    LD BC,4
    CALL LDIRVM
EBUZ_STATE1_BG_DONE:

    ; --- "この状態で0.5秒維持してから発射"(2026-09-13追記)。 ---
    ; 待ち自体はEBUZ_WAIT_TICKS(弾更新を止めない待ち)経由 - この時点
    ; ではまだどの弾も発射されていない(EBUZ_SPR_INITが全枠SPR_HIDE_Y)
    ; ため、実質的にはEBUZ_FRAME_WAITを29回呼ぶのと同じ(約0.5秒相当)。
    LD B,29
    CALL EBUZ_WAIT_TICKS

    ; --- state1登場時: BULLET_FULLを1枚発射(スロット0、X=16px左へ) ---
    LD HL,EBUZ_SPR_BULLET1 : LD DE,EBUZ_SPR_SHADOW : LD BC,4 : LDIR
    LD HL,EBUZ_SPR_SHADOW : LD DE,SPRATR : LD BC,4 : CALL LDIRVM
EBUZ_STATE1_DONE:

    ; --- state2形成までの間(旧EBUZ_DELAY x2、約1.76秒相当)。 ---
    ; ここが今回の実機フィードバック対応の核心: この待ちの間、
    ; bullet0は既に発射済みなのでEBUZ_WAIT_TICKS経由で継続して左へ
    ; 移動し続ける(旧実装はここで完全静止していたため、bullets1/2が
    ; 発射される瞬間に3発とも本体のそばへ集まって見えていた)。
    LD B,102
    CALL EBUZ_WAIT_TICKS

    ; --- state2: A,B,Cの帯が上下へ分離・移動、中央2行はDだけが残る ---
    LD HL,EBUZ_ROW_0ABC
    LD DE,01838h                 ; row1 (new top band), col24-27
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_000D
    LD DE,01858h                 ; row2 (was A,B,C,D) - A,B,C now gone
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_000D
    LD DE,01878h                 ; row3 (was A,B,C,D) - A,B,C now gone
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_0ABC
    LD DE,01898h                 ; row4 (new bottom band), col24-27
    LD BC,4
    CALL LDIRVM
EBUZ_STATE2_BG_DONE:

    ; --- "Ebuz2に変形後...同じく0.5秒維持して同時発射"(2026-09-13追記) ---
    ; ここもEBUZ_WAIT_TICKS経由なのでbullet0は引き続き移動を続ける
    ; (この時点でbullet0は既に画面外へ消えているはず、下記の較正コメント
    ; 参照)。
    LD B,29
    CALL EBUZ_WAIT_TICKS

    ; --- state2変化時: BULLET_HALFを2枚同時発射(スロット1,2) ---
    LD HL,EBUZ_SPR_BULLET23 : LD DE,EBUZ_SPR_SHADOW+4 : LD BC,8 : LDIR
    LD HL,EBUZ_SPR_SHADOW+4 : LD DE,SPRATR+4 : LD BC,8 : CALL LDIRVM
EBUZ_STATE2_DONE:

; --- 以後、弾3枚(スロット0-2)を毎"フレーム"左へ移動、画面外で非表示化 ---
; (EBUZ_TICK自体がDI/EI/ウェイトを内包するため、ここでは単純にループ
; するだけでよい)。
EBUZ_MAINLOOP:
    CALL EBUZ_TICK
EBUZ_FRAME_TICK:
    JR EBUZ_MAINLOOP

EBUZ_COLOR_BYTE:
    DB EBUZ_COLOR

EBUZ_ROW_ABCD:
    DB EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C,EBUZ_CODE_D
EBUZ_ROW_0ABC:
    DB 0,EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C
EBUZ_ROW_000D:
    DB 0,0,0,EBUZ_CODE_D

; 4つの8x8タイル(添付Ebuz1_32x32.jsonから機械抽出、tools/ebuz_test/
; ebuz_gen.pyで再計算可能 - 抽出根拠はこのファイル冒頭コメント参照)。
EBUZ_TILE_A:
    DB 126,191,1,63,63,1,191,126
EBUZ_TILE_B:
    DB 255,84,42,126,126,42,84,255
EBUZ_TILE_C:
    DB 126,195,189,181,173,189,195,126
EBUZ_TILE_D:
    DB 255,65,127,127,127,127,65,255

; 弾2種のスプライトパターン(添付EbuzBullet1_16x16.jsonから機械抽出、
; tools/ebuz_test/ebuz_bullet_gen.pyで再計算可能)。TL/BL/TR/BR順の
; 32byte(MSX1 16x16スプライトパターンの標準レイアウト、src/CYBER
; SHMUP.asmのPAT_SHIP等と同じ規約)。
BULLET_FULL_PAT:
    DB 0,0,127,255,255,127,0,0        ; TL
    DB 0,0,127,255,255,127,0,0        ; BL(元絵の下段バーもTLと同一)
    DB 0,0,254,255,255,254,0,0        ; TR
    DB 0,0,254,255,255,254,0,0        ; BR(同上)
; 2026-09-13追記: 添付EbuzBullet2_16x16.json(専用データとして正式に
; 提供)とTL/BL/TR/BR全象限バイト単位で完全一致することを確認済み
; (ebuz_bullet_gen.py:verify_against_ebuz_bullet2())。データ自体の
; 変更は無い。
BULLET_HALF_PAT:
    DB 0,0,127,255,255,127,0,0        ; TL(上半分そのまま)
    DB 0,0,0,0,0,0,0,0                ; BL(空白パディング)
    DB 0,0,254,255,255,254,0,0        ; TR(上半分そのまま)
    DB 0,0,0,0,0,0,0,0                ; BR(空白パディング)

; 弾3枚分のRAMシャドウ初期値(全て非表示)+SAT終端行。
EBUZ_SPR_INIT:
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
    DB SPR_HIDE_Y,0,0,0
EBUZ_SPR_TERM:
    DB SPR_TERM_Y,0,0,0

; state1発射時の弾1(スロット0): BULLET_FULL、Y=16(暫定)、
; X=176(=192-16、2026-09-13追記で16px左へ移動)
EBUZ_SPR_BULLET1:
    DB EBUZ_BULLET1_STORED_Y,EBUZ_BULLET1_X,BULLET_FULL_CODE,EBUZ_BULLET_COLOR

; state2発射時の弾2/弾3(スロット1,2): BULLET_HALF、Y=0px/24px、X=192
EBUZ_SPR_BULLET23:
    DB EBUZ_BULLET2_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
    DB EBUZ_BULLET3_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
