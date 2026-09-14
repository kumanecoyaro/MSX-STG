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
; (弾の実装の変遷、詳細はgit履歴/tools/stage2_combined/HANDOFF.mdの
; Round118〜125を参照): 当初はHWスプライトとして実装し、発射タイミング・
; 移動・継続発射・反動アニメーション等を実機フィードバックを経て
; 何度も調整した。
;
; (2026-09-14、実機フィードバック対応、最新の設計変更: "弾をBGに変更
; 8px移動だからスプライトの意味がないからな"): 弾の移動が常に
; EBUZ_BULLET_SPEED_PX(8px)=BG1セル幅ちょうどの固定歩幅であるため、
; HWスプライトが持つサブピクセル単位の滑らかな移動能力は元から一切
; 使っていなかった(移動は常にセル境界に揃う)。HWスプライトを完全に
; 撤去し、弾をBGタイル(セル単位の書き換え)として実装し直した。
;   - 弾のグラフィックはBULLET_FULL_PAT/BULLET_HALF_PATのTL象限・
;     TR象限が完全に同一データだった(BL/BRはBULLET_HALFでは空白
;     パディング、BULLET_FULLではTL/TRの複製)ため、実際に必要な
;     ユニークな8x8タイルはわずか2枚(左半分・右半分)だけと判明。
;     この2タイルをBULLET_L_CODE/BULLET_R_CODEとして新規BGパターン
;     コードに割り当て、初弾(2行x2列=4セル、上下行とも同じ2タイルを
;     使う)・上下継続弾(1行x2列=2セル)の両方でこの2タイルを共有する。
;   - 発射開始列を、翼帯(state2のrow1/row4、col24-28)の装飾セルと
;     物理的に一切重ならないよう調整した(EBUZ_BULLET23_COL=22、旧
;     X=192のcol24から-2)。当初は「col24は静止時[REST]・反動時
;     [RECOIL]いずれでも常に空白(0)」という理由でcol23(右端col24)を
;     選んだが、発射したまさにそのティックに限り「翼帯の反動表示
;     書き込み(col24-28の5byte)」と「弾自身のcol24への描画」が
;     同一ティック内で競合し、命令の実行順序次第でどちらかが他方を
;     上書きしてしまう実バグを自己検証で発見(詳細はEBUZ_BULLET23_COL
;     のEQU直前のコメント参照)。col22ならbullet0(EBUZ_BULLET1_COL)と
;     同じ列で、翼帯のcol24-28と構造的に一切重ならないため、この種の
;     競合が発生しない。HWスプライト時代は「前面に重ねて描く」だけ
;     だったため気付かなかったが、BGはセルそのものを書き換えるため、
;     この列調整が必須になった。
;   - 継続発射のプール管理(EBUZ_TOPBOTTOM_ACTIVE/EBUZ_FIRE_SIDE/
;     EBUZ_FIRE_COUNTDOWN/EBUZ_RECOIL_SIDE/EBUZ_RECOIL_COUNTDOWNによる
;     固定2ティック間隔・無条件発射、Round125で確立した設計)自体は
;     無変更 - 変わったのは「1発をどう表現するか」(HWスプライトの
;     Y/X/pattern/color四つ組→BGの列位置1byteのみ)だけ。HWスプライト
;     固有の悩み(番号の使い回し・SATスキャン順序・4-sprites-per-line
;     制限)がBG化により全て構造的に消滅したため、ローテーション
;     プールは残しつつ(複数の同時生存インスタンスを追跡する目的では
;     引き続き必要)、プールサイズは上下弾それぞれ8個(以前の全体
;     共有16個から縮小 - 各レーン単独の最大同時生存数[約6発]に
;     十分な余裕を持たせた値)とした。
;
; 本ファイルは本編(src/CYBER SHMUP.asm)に組み込む前の独立した
; プロトタイプ("専用の空ステージ1")。背景は完全に空(code0の空白タイル
; のみ)で、Ebuzの見た目・状態遷移・弾発射/移動だけを確認する。実際の
; スケジュール組み込みは別途指示待ち。
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

; Ebuz本体用に確保したBGパターンコード(このファイル専用の空環境なので
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

; --- 弾(2026-09-14、BG化)。row1〜row4それぞれのname table上の絶対 ---
; アドレスを事前計算した定数(NAMTBL+row*32)として持つ - このアセン
; ブラーは演算子優先順位も丸括弧も無いため、実行時に"NAMTBL+ROW*32+COL"
; を計算するのではなく、行の先頭アドレスをコンパイル時定数として
; 用意し、そこへ列番号(0-31)だけを実行時に加算する設計にしている。
EBUZ_ROW1_BASE EQU NAMTBL+32    ; = 1820h
EBUZ_ROW2_BASE EQU NAMTBL+64    ; = 1840h
EBUZ_ROW3_BASE EQU NAMTBL+96    ; = 1860h
EBUZ_ROW4_BASE EQU NAMTBL+128   ; = 1880h

; 弾のBGパターンコード(2枚: 左半分/右半分)。旧HWスプライト版の
; BULLET_FULL_PAT/BULLET_HALF_PATはいずれもTL象限とTR象限が完全に
; 同一データだった(BULLET_HALFはBL/BRが空白パディングなだけ)ため、
; 実際に必要なユニークな絵柄はこの2枚だけで済む。group9(72-79)は
; このファイル専用の空環境につき空き確認不要。
BULLET_L_CODE EQU 72
BULLET_R_CODE EQU 73
EBUZ_BULLET_COLOR EQU 0B5h  ; fg=11(light yellow)/bg=5(light blue、翼帯と同じ空色)

; 発射開始列(2026-09-14、BG化に伴う列調整: 上記コメント参照)。
EBUZ_BULLET1_COL  EQU 22   ; state1弾(初弾、旧X=176=col22、調整不要)
; state2継続弾の発射列(旧X=192=col24からcol22へ、2列左に調整)。
; (2026-09-14、自己発見バグ経由での訂正): 当初col23(右端col24、
; 翼帯REST/RECOIL両状態でcol24が常に0という理由)を選んだが、発射
; したまさにそのティックは「翼帯の反動表示書き込み(col24-28の5byte)」
; と「弾自身のcol24への描画」が同一ティック内で競合し、命令の実行
; 順序次第でどちらかが他方を上書きしてしまう(自己検証で実際に
; 発生を確認)。col22なら翼帯のcol24-28と一切重ならず、この種の
; 競合が構造的に発生しない - bullet0(EBUZ_BULLET1_COL)と同じ列で
; 統一される。
EBUZ_BULLET23_COL EQU 22

EBUZ_ROW_TOP_BAND    EQU 1   ; state2の新設上段(EBUZ_ROW_0ABC)の行番号
EBUZ_ROW_BOTTOM_BAND EQU 4   ; state2の新設下段(EBUZ_ROW_0ABC)の行番号

; 継続発射レーン(上/下)それぞれの弾プール数。1発の寿命(発射列から
; 画面外[列-1]まで、最大で発射列+1ティック)に対し、固定2ティック
; 間隔(片側だけなら4ティックに1発)での発射が生む最大同時生存数
; (約6発)を安全に上回る値。
EBUZ_LANE_POOL_SIZE EQU 8
EBUZ_SLOT_EMPTY EQU 255  ; プールスロットの「非アクティブ」番兵(0-31の列番号とは重ならない)

; 初弾(bullet0)の状態。HWスプライト時代のEBUZ_BULLET0_HOLDING/
; EBUZ_BULLET0_SLOT_ADDRと同じ役割だが、BG化によりスロットアドレスの
; 代わりに単純な列番号1byteで済む。
EBUZ_B0_ACTIVE   EQU 0F300h  ; 1 byte: 0=まだ発射前 or 画面外に消えて終了、1=生存中(ホールド中含む)
EBUZ_B0_HOLDING  EQU 0F301h  ; 1 byte: 1=ホールド中(表示のみ、移動しない)、0=通常飛行中
EBUZ_B0_COL      EQU 0F302h  ; 1 byte: 現在の左列(0-31)

; (2026-09-13追記その7、実機フィードバック対応、Round125で確立した
; 設計をそのまま踏襲): state2の上下弾は2ティックごとに交互に、生存
; チェックなしで無条件に発射し続ける。発射のたびに、その側の翼帯
; (A,B,Cの3セル)を1セル右へ「反動」表示し、1ティック後に元の位置へ
; 戻す。
EBUZ_TOPBOTTOM_ACTIVE  EQU 0F303h  ; 1 byte: 0=まだ非活性、1=継続発射中
EBUZ_FIRE_SIDE         EQU 0F304h  ; 1 byte: 次に撃つ側(0=上/1=下)
EBUZ_FIRE_COUNTDOWN    EQU 0F305h  ; 1 byte: 次の発射までの残りティック数
EBUZ_RECOIL_SIDE       EQU 0F306h  ; 1 byte: 現在反動表示中の側(0/1)
EBUZ_RECOIL_COUNTDOWN  EQU 0F307h  ; 1 byte: 反動が元に戻るまでの残りティック数(0=反動なし)
EBUZ_FIRE_INTERVAL     EQU 2       ; "2フレ交代"
EBUZ_RECOIL_DURATION   EQU 1       ; 反動表示の持続ティック数(打ったら次のティックで元位置)

; 上下レーンそれぞれの弾プール(列番号の配列、EBUZ_SLOT_EMPTY=非活性)+
; ローテーション割り当てカウンタ。
EBUZ_TOP_COLS     EQU 0F310h  ; EBUZ_LANE_POOL_SIZE(8) bytes
EBUZ_BOTTOM_COLS  EQU 0F318h  ; EBUZ_LANE_POOL_SIZE(8) bytes
EBUZ_TOP_NEXT     EQU 0F320h  ; 1 byte
EBUZ_BOTTOM_NEXT  EQU 0F321h  ; 1 byte

; EBUZ_UPDATE_SLOT(共有プール更新ルーチン)が参照する「今どの行を
; 対象にしているか」のスクラッチ(呼び出し元がCALL直前にセットする)。
EBUZ_CUR_ROW_BASE EQU 0F322h  ; 2 bytes

; 1フレーム相当のウェイト(弾移動のステップ間隔、EBUZ_TICKから毎回
; 呼ばれる)。B=15の2段ループ(256回×15周)で実測約61677T-states
; (約0.0172秒/回、3.58MHz Z80での1/60秒[0.01667秒]に近似)に較正済み。
EBUZ_FRAME_WAIT:
    LD B,15
EBUZ_FRAME_WAIT_OUTER:
    LD C,0
EBUZ_FRAME_WAIT_INNER:
    DEC C
    JR NZ,EBUZ_FRAME_WAIT_INNER
    DJNZ EBUZ_FRAME_WAIT_OUTER
    RET

; VRAMの連続2byteへ書き込む(左セル・右セル)。IN: HL=左セルの
; アドレス、B=左セルへ書く値、C=右セルへ書く値。弾の「消す」
; (B=C=0)・「描く」(B=BULLET_L_CODE,C=BULLET_R_CODE)の両方で使う
; 共有ヘルパー。
EBUZ_WRITE2:
    LD A,B
    CALL WRTVRM
    INC HL
    LD A,C
    CALL WRTVRM
    RET

; プール(上/下共通)の1スロット分の更新。IN: HL=スロットの列番号
; バイトのアドレス、EBUZ_CUR_ROW_BASE=このプールが使う行の先頭
; アドレス(呼び出し元がCALL直前にセット)。非アクティブなら何もしない。
; 生きていれば現在位置を消し、列を1減算、画面外(-1)になったら
; 非アクティブ化して終了、そうでなければ新しい位置に描き直す。
EBUZ_UPDATE_SLOT:
    LD A,(HL)
    CP EBUZ_SLOT_EMPTY
    RET Z
    PUSH HL
    PUSH AF
    LD E,A : LD D,0
    LD HL,(EBUZ_CUR_ROW_BASE)
    ADD HL,DE
    LD B,0 : LD C,0
    CALL EBUZ_WRITE2
    POP AF
    OR A
    JR Z,EBUZ_US_OFF
    DEC A
    POP HL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,(EBUZ_CUR_ROW_BASE)
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET
EBUZ_US_OFF:
    POP HL
    LD (HL),EBUZ_SLOT_EMPTY
    RET

; 上レーン8スロット全ての更新(固定回数なのでDJNZループではなく
; 明示的に展開 - EBUZ_UPDATE_SLOT自身がHL/AFを使い切るため、外側を
; DJNZ+HLの汎用ループにすると干渉するのを避けるための単純な設計)。
EBUZ_UPDATE_TOP_POOL:
    LD HL,EBUZ_ROW1_BASE
    LD (EBUZ_CUR_ROW_BASE),HL
    LD HL,EBUZ_TOP_COLS+0 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+1 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+2 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+3 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+4 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+5 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+6 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_TOP_COLS+7 : CALL EBUZ_UPDATE_SLOT
    RET

EBUZ_UPDATE_BOTTOM_POOL:
    LD HL,EBUZ_ROW4_BASE
    LD (EBUZ_CUR_ROW_BASE),HL
    LD HL,EBUZ_BOTTOM_COLS+0 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+1 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+2 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+3 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+4 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+5 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+6 : CALL EBUZ_UPDATE_SLOT
    LD HL,EBUZ_BOTTOM_COLS+7 : CALL EBUZ_UPDATE_SLOT
    RET

; 1"フレーム"分の処理をまとめたもの: 初弾の更新→上下プールの更新→
; (継続発射有効なら)上下弾の継続発射処理→ウェイト。
EBUZ_TICK:
    DI
    LD A,(EBUZ_B0_ACTIVE)
    OR A
    JR Z,EBUZ_TICK_B0_DONE
    LD A,(EBUZ_B0_HOLDING)
    OR A
    JR NZ,EBUZ_TICK_B0_DONE
    LD A,(EBUZ_B0_COL)
    PUSH AF
    LD E,A : LD D,0
    LD HL,EBUZ_ROW2_BASE : ADD HL,DE
    LD B,0 : LD C,0 : CALL EBUZ_WRITE2
    POP AF
    PUSH AF
    LD E,A : LD D,0
    LD HL,EBUZ_ROW3_BASE : ADD HL,DE
    LD B,0 : LD C,0 : CALL EBUZ_WRITE2
    POP AF
    OR A
    JR Z,EBUZ_TICK_B0_OFF
    DEC A
    LD (EBUZ_B0_COL),A
    PUSH AF
    LD E,A : LD D,0
    LD HL,EBUZ_ROW2_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ_WRITE2
    POP AF
    LD E,A : LD D,0
    LD HL,EBUZ_ROW3_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ_WRITE2
    JR EBUZ_TICK_B0_DONE
EBUZ_TICK_B0_OFF:
    XOR A
    LD (EBUZ_B0_ACTIVE),A
EBUZ_TICK_B0_DONE:
    CALL EBUZ_UPDATE_TOP_POOL
    CALL EBUZ_UPDATE_BOTTOM_POOL
    LD A,(EBUZ_TOPBOTTOM_ACTIVE)
    OR A
    CALL NZ,EBUZ_UPDATE_TOPBOTTOM_FIRE
    EI
    CALL EBUZ_FRAME_WAIT
    RET

; 上レーンへ1発、無条件で新規発射する(生存チェックなし、ローテー
; ションでプールの次のスロットを使う - Round125で確立した"固定間隔・
; 無条件発射"をBG版に移植)。
EBUZ_FIRE_TOP_BULLET:
    LD A,(EBUZ_TOP_NEXT)
    LD B,A
    INC A
    CP EBUZ_LANE_POOL_SIZE
    JR C,EBUZ_FTB_OK
    XOR A
EBUZ_FTB_OK:
    LD (EBUZ_TOP_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ_TOP_COLS
    ADD HL,DE
    LD A,EBUZ_BULLET23_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ_ROW1_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET

EBUZ_FIRE_BOTTOM_BULLET:
    LD A,(EBUZ_BOTTOM_NEXT)
    LD B,A
    INC A
    CP EBUZ_LANE_POOL_SIZE
    JR C,EBUZ_FBB_OK
    XOR A
EBUZ_FBB_OK:
    LD (EBUZ_BOTTOM_NEXT),A
    LD H,0 : LD L,B
    LD DE,EBUZ_BOTTOM_COLS
    ADD HL,DE
    LD A,EBUZ_BULLET23_COL
    LD (HL),A
    LD E,A : LD D,0
    LD HL,EBUZ_ROW4_BASE
    ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE
    CALL EBUZ_WRITE2
    RET

; 上下弾の継続発射処理(Round125で確立した設計をそのまま踏襲、弾の
; 表現手段だけがHWスプライト→BGへ変わった)。EBUZ_TOPBOTTOM_ACTIVE=1
; の間、EBUZ_TICKから毎回呼ばれる。(1)反動表示中なら1ティック後に
; 元位置へ戻す。(2)発射カウントダウンがEBUZ_FIRE_INTERVAL(2)ティック
; ごとに0になったら、生存チェックを一切せず無条件に新しい弾を発射し、
; 側を反転する。
EBUZ_UPDATE_TOPBOTTOM_FIRE:
    LD A,(EBUZ_RECOIL_COUNTDOWN)
    OR A
    JR Z,EUTF_SKIP_REVERT
    DEC A
    LD (EBUZ_RECOIL_COUNTDOWN),A
    JR NZ,EUTF_SKIP_REVERT
    LD A,(EBUZ_RECOIL_SIDE)
    OR A
    JR NZ,EUTF_REVERT_BOTTOM
    LD HL,EBUZ_ROW_0ABC_REST : LD DE,01838h : LD BC,5 : CALL LDIRVM
    JR EUTF_SKIP_REVERT
EUTF_REVERT_BOTTOM:
    LD HL,EBUZ_ROW_0ABC_REST : LD DE,01898h : LD BC,5 : CALL LDIRVM
EUTF_SKIP_REVERT:
    LD A,(EBUZ_FIRE_COUNTDOWN)
    DEC A
    LD (EBUZ_FIRE_COUNTDOWN),A
    RET NZ
    LD A,EBUZ_FIRE_INTERVAL
    LD (EBUZ_FIRE_COUNTDOWN),A
    LD A,(EBUZ_FIRE_SIDE)
    OR A
    JR NZ,EUTF_FIRE_BOTTOM
    ; NOTE(2026-09-14、自己発見バグ修正): 翼帯の反動表示(RECOIL_ROW)は
    ; col24-28の5byteを無条件に書くため、弾自身の右端(col24)への
    ; 書き込みより後に実行すると弾の絵を消してしまう(col24は両状態
    ; とも0だが、それは「RECOIL_ROWの1byte目が0だから」であって、
    ; 弾を描いた直後にこの5byte書き込みが再度走れば0で上書きされる)。
    ; 必ず反動表示→弾描画の順にする。
    LD HL,EBUZ_ROW_0ABC_RECOIL : LD DE,01838h : LD BC,5 : CALL LDIRVM
    CALL EBUZ_FIRE_TOP_BULLET
    JR EUTF_FIRE_DONE
EUTF_FIRE_BOTTOM:
    LD HL,EBUZ_ROW_0ABC_RECOIL : LD DE,01898h : LD BC,5 : CALL LDIRVM
    CALL EBUZ_FIRE_BOTTOM_BULLET
EUTF_FIRE_DONE:
    LD A,(EBUZ_FIRE_SIDE)
    LD (EBUZ_RECOIL_SIDE),A
    LD A,EBUZ_RECOIL_DURATION
    LD (EBUZ_RECOIL_COUNTDOWN),A
    LD A,(EBUZ_FIRE_SIDE)
    XOR 1
    LD (EBUZ_FIRE_SIDE),A
    RET

; B=待ちたいティック数(1-255)。EBUZ_TICKをB回呼ぶだけの「弾の移動を
; 止めない待ち」。
EBUZ_WAIT_TICKS:
EBUZ_WAIT_TICKS_LOOP:
    PUSH BC
    CALL EBUZ_TICK
EBUZ_WAIT_TICK_DONE:                ; テスト用: 「待ち期間中の1ティック完了」の目印
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

    ; 弾のBGタイル2枚(左半分/右半分)をロード+専用カラーグループ
    ; (group9、fg11/bg5)を設定(2026-09-14、BG化)。
    LD HL,BULLET_L_TILE : LD DE,BULLET_L_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,BULLET_R_TILE : LD DE,BULLET_R_CODE*8 : LD BC,8 : CALL LDIRVM
    LD HL,EBUZ_BULLET_COLOR_BYTE : LD DE,COLTBL+9 : LD BC,1 : CALL LDIRVM

    ; 弾関連のワークエリアを明示的にゼロ(または非アクティブ番兵)で
    ; 初期化する(RAM初期化漏れ防止)。
    XOR A
    LD (EBUZ_B0_ACTIVE),A
    LD (EBUZ_B0_HOLDING),A
    LD (EBUZ_B0_COL),A
    LD (EBUZ_TOPBOTTOM_ACTIVE),A
    LD (EBUZ_FIRE_SIDE),A
    LD (EBUZ_FIRE_COUNTDOWN),A
    LD (EBUZ_RECOIL_SIDE),A
    LD (EBUZ_RECOIL_COUNTDOWN),A
    LD (EBUZ_TOP_NEXT),A
    LD (EBUZ_BOTTOM_NEXT),A
    LD A,EBUZ_SLOT_EMPTY
    LD (EBUZ_TOP_COLS+0),A
    LD (EBUZ_TOP_COLS+1),A
    LD (EBUZ_TOP_COLS+2),A
    LD (EBUZ_TOP_COLS+3),A
    LD (EBUZ_TOP_COLS+4),A
    LD (EBUZ_TOP_COLS+5),A
    LD (EBUZ_TOP_COLS+6),A
    LD (EBUZ_TOP_COLS+7),A
    LD (EBUZ_BOTTOM_COLS+0),A
    LD (EBUZ_BOTTOM_COLS+1),A
    LD (EBUZ_BOTTOM_COLS+2),A
    LD (EBUZ_BOTTOM_COLS+3),A
    LD (EBUZ_BOTTOM_COLS+4),A
    LD (EBUZ_BOTTOM_COLS+5),A
    LD (EBUZ_BOTTOM_COLS+6),A
    LD (EBUZ_BOTTOM_COLS+7),A

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

    ; --- "弾を表示してホールドだって言っただろが"(2026-09-13追記その8): ---
    ; Ebuz1出現と同時に弾(BULLET_L/R、row2/row3のcol22-23)を表示し、
    ; その位置で静止(ホールド)させてから実際に飛ばし始める。
    ; (2026-09-14、実機フィードバック対応: "初弾撃った後のウェイト
    ; 2重にウェイトしてるだろ 初弾ホールドを10フレ 一斉発射は15フレの
    ; ホールドに変更 それ以外のウェイトは入れるな"): 旧来は初弾ホールド
    ; 29ティック→state1-state2遷移102ティック→state2形成後29ティック
    ; ホールドの3段構成だったが、これが二重の待ちになっていた。
    ; 遷移用の102ティック待ちを完全に削除し、初弾ホールドを10ティックへ、
    ; state2形成後(継続発射開始前)のホールドを15ティックへ変更、この
    ; 2箇所以外のウェイトは一切追加しない。
    LD A,1
    LD (EBUZ_B0_ACTIVE),A
    LD A,1
    LD (EBUZ_B0_HOLDING),A
    LD A,EBUZ_BULLET1_COL
    LD (EBUZ_B0_COL),A
    LD E,A : LD D,0
    LD HL,EBUZ_ROW2_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ_WRITE2
    LD A,(EBUZ_B0_COL)
    LD E,A : LD D,0
    LD HL,EBUZ_ROW3_BASE : ADD HL,DE
    LD B,BULLET_L_CODE : LD C,BULLET_R_CODE : CALL EBUZ_WRITE2

    ; --- 初弾ホールド10ティック(EBUZ_WAIT_TICKS経由、この間EBUZ_TICKが ---
    ; 初弾の移動をスキップするので表示されたまま静止し続ける)。
    LD B,10
    CALL EBUZ_WAIT_TICKS

    ; --- ホールド終了、実際に飛び始める ---
    XOR A
    LD (EBUZ_B0_HOLDING),A
EBUZ_STATE1_DONE:

    ; --- state2: A,B,Cの帯が上下へ分離・移動、中央2行はDだけが残る ---
    ; (row1/row4はcol24-28の5byte書き込み - col28は反動アニメーション用に
    ; 確保した予備セル、静止時は空白)
    LD HL,EBUZ_ROW_0ABC_REST
    LD DE,01838h                 ; row1 (new top band), col24-28
    LD BC,5
    CALL LDIRVM
    LD HL,EBUZ_ROW_000D
    LD DE,01858h                 ; row2 (was A,B,C,D) - A,B,C now gone
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_000D
    LD DE,01878h                 ; row3 (was A,B,C,D) - A,B,C now gone
    LD BC,4
    CALL LDIRVM
    LD HL,EBUZ_ROW_0ABC_REST
    LD DE,01898h                 ; row4 (new bottom band), col24-28
    LD BC,5
    CALL LDIRVM
EBUZ_STATE2_BG_DONE:

    ; --- "一斉発射は15フレのホールドに変更"(2026-09-14実機フィード ---
    ; バック対応)、さらに"2回目のホールドを30フレに"(同日追記)で
    ; 15→30へ再変更: state2形成後、継続発射(一斉発射)を開始する前に
    ; 30ティックだけホールドする。
    LD B,30
    CALL EBUZ_WAIT_TICKS

    ; --- "上下弾は交互に撃ち続けろ 2フレ交代"(Round125で確立した ---
    ; 共有ターン制御方式): 継続発射モードを起動。初弾(上側)は次の
    ; EBUZ_TICKで即座に発射されるようFIRE_COUNTDOWN=1とする(以後は
    ; EBUZ_FIRE_INTERVALで2ティックおきに無条件で交互発射)。
    XOR A
    LD (EBUZ_FIRE_SIDE),A          ; 0=まず上側から
    LD A,1
    LD (EBUZ_FIRE_COUNTDOWN),A     ; 次のティックで即発射
    LD A,1
    LD (EBUZ_TOPBOTTOM_ACTIVE),A
EBUZ_STATE2_DONE:

; --- 以後、EBUZ_TICK自体がDI/EI/ウェイトを内包するため、ここでは ---
; 単純にループするだけでよい。
EBUZ_MAINLOOP:
    CALL EBUZ_TICK
EBUZ_FRAME_TICK:
    JR EBUZ_MAINLOOP

EBUZ_COLOR_BYTE:
    DB EBUZ_COLOR

EBUZ_BULLET_COLOR_BYTE:
    DB EBUZ_BULLET_COLOR

EBUZ_ROW_ABCD:
    DB EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C,EBUZ_CODE_D
; 2026-09-13追記その7("打つときは反動を見せたいんで 上下の3セル分を
; 1セル右に 打ったら元位置に戻せ"): col24-28の5byte(col28は反動時
; だけC タイルが入る予備セル)。静止時REST=[空,A,B,C,空]、反動時
; RECOIL=[空,空,A,B,C](A,B,Cの3セルがまるごと1セル右へシフト)。
; NOTE(2026-09-14): 弾(EBUZ_BULLET23_COL=22、右端col23)はこのcol24-28
; の範囲と一切重ならない列から発射するため、翼帯自身の絵柄を破壊する
; 心配も、発射ティックでの書き込み順序による競合の心配もない
; (当初col23[右端col24]を検討したが、翼帯の反動書き込みと弾自身の
; col24描画が同一ティックで競合することを自己検証で発見し撤回した -
; 詳細はEBUZ_BULLET23_COLのEQU直前のコメント参照)。
EBUZ_ROW_0ABC_REST:
    DB 0,EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C,0
EBUZ_ROW_0ABC_RECOIL:
    DB 0,0,EBUZ_CODE_A,EBUZ_CODE_B,EBUZ_CODE_C
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

; 弾の8x8タイル2枚(添付EbuzBullet1_16x16.jsonのTL/TR象限から機械抽出、
; tools/ebuz_test/ebuz_bullet_gen.py参照。2026-09-14、BG化に伴い
; TL==BL/TR==BRだった旧32byteスプライトパターンから、実際に必要な
; ユニークな2枚だけを抜き出した)。
BULLET_L_TILE:
    DB 0,0,127,255,255,127,0,0
BULLET_R_TILE:
    DB 0,0,254,255,255,254,0,0
