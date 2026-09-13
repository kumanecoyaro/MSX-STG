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
EBUZ_BULLET_X      EQU 192   ; Ebuz本体のXから発射(暫定)
EBUZ_BULLET_SPEED  EQU 3     ; px/frame、未調整の暫定値
; TMS9918のY属性は実際の表示開始行より1小さい値を書く規約
; (tools/stage1_render_check.pyのrender_full()と同じ"y1=(y+1)&0xFF"
; デコードに対応)。state1の弾はY=16(=EBUZ_ROW*8、本体位置基準の
; 暫定値、具体的な指定なし)、state2の2発はユーザー指定のY=0px/24pxを
; そのまま絶対値として使用...のはずだったが、desired Y=0だと
; stored=0-1=255(wrap)になり、このプロジェクト全体で「非表示化」の
; 慣習として使っているstored Y>=209の範囲と数値上重なってしまう
; (実ハードウェアではY=255は実際に画面最上行に正しく表示される -
; render_full()を含むこのプロジェクトの各所が「Y>=209なら非表示」と
; 単純化して判定しているのは通常誰もこの折返し値を意図的に使わない
; という前提に基づくもので、今回はその前提が崩れる)。ENEMY3_DO_SPAWN
; が同種の折返し衝突を「254で頭打ちにする」形で回避しているのと同じ
; 考え方で、desired Y=0はY=1へ1px寄せて回避する(stored=0、既存の
; 非表示慣習と一切重ならない安全な値)。
EBUZ_BULLET1_STORED_Y EQU 15    ; desired Y=16  -> 16-1=15
EBUZ_BULLET2_STORED_Y EQU 0     ; desired Y=1(0から1pxだけ寄せた値) -> 1-1=0
EBUZ_BULLET3_STORED_Y EQU 23    ; desired Y=24  -> 24-1=23
SPR_HIDE_Y  EQU 209   ; 個別非表示(リストは継続、既存コードの規約と同じ)
SPR_TERM_Y  EQU 208   ; SATリスト終端(このスロット以降は描画されない)

; 弾3枚分のRAM側シャドウ(Y,X,pattern,color x3=12byte)。SPRATRは
; VRAMなのでZ80の通常のLD/SUB/CPで直接読み書きできない
; (OUT/INポート経由のVDP I/Oが必要) - 毎フレームの移動計算はこちらの
; RAM側で行い、更新後にLDIRVMでまとめてSPRATRへ反映する。
EBUZ_SPR_SHADOW EQU 0F350h   ; 12 bytes (F350h-F35Bh), STACKTOPまで十分な余裕

; フレーム換算しないシンプルなビジーウェイト(src/CYBER SHMUP.asmの
; MISSION_DELAY_3SECと同型、Dを小さくして約1秒相当)。
EBUZ_DELAY:
    LD D,3
EBUZ_DELAY_OUTER:
    LD B,0
EBUZ_DELAY_MID:
    LD C,0
EBUZ_DELAY_INNER:
    DEC C
    JR NZ,EBUZ_DELAY_INNER
    DJNZ EBUZ_DELAY_MID
    DEC D
    JR NZ,EBUZ_DELAY_OUTER
    RET

; 1フレーム相当の短いウェイト(弾移動のステップ間隔、EBUZ_DELAYより
; ずっと短い - 未調整の暫定値)。
EBUZ_FRAME_WAIT:
    LD B,0
EBUZ_FRAME_WAIT_LOOP:
    DEC B
    JR NZ,EBUZ_FRAME_WAIT_LOOP
    RET

; IX = EBUZ_SPR_SHADOW内の弾スロット先頭(+0=Y,+1=X,+2=pattern,+3=color)。
; 非表示(Y=SPR_HIDE_Y)なら何もしない、そうでなければXをEBUZ_BULLET_
; SPEEDだけ減算(左へ移動)、画面外に出る場合はY=SPR_HIDE_Yにして非表示化。
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

    ; --- state1登場時: BULLET_FULLを1枚発射(スロット0) ---
    LD HL,EBUZ_SPR_BULLET1 : LD DE,EBUZ_SPR_SHADOW : LD BC,4 : LDIR
    LD HL,EBUZ_SPR_SHADOW : LD DE,SPRATR : LD BC,4 : CALL LDIRVM
EBUZ_STATE1_DONE:

    EI
    CALL EBUZ_DELAY
    CALL EBUZ_DELAY
    DI

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

    ; --- state2変化時: BULLET_HALFを2枚同時発射(スロット1,2) ---
    LD HL,EBUZ_SPR_BULLET23 : LD DE,EBUZ_SPR_SHADOW+4 : LD BC,8 : LDIR
    LD HL,EBUZ_SPR_SHADOW+4 : LD DE,SPRATR+4 : LD BC,8 : CALL LDIRVM
EBUZ_STATE2_DONE:

    EI

; --- 以後、弾3枚(スロット0-2)を毎"フレーム"左へ移動、画面外で非表示化 ---
EBUZ_MAINLOOP:
    DI
    LD IX,EBUZ_SPR_SHADOW   : CALL EBUZ_UPDATE_BULLET
    LD IX,EBUZ_SPR_SHADOW+4 : CALL EBUZ_UPDATE_BULLET
    LD IX,EBUZ_SPR_SHADOW+8 : CALL EBUZ_UPDATE_BULLET
    LD HL,EBUZ_SPR_SHADOW : LD DE,SPRATR : LD BC,12 : CALL LDIRVM
    EI
EBUZ_FRAME_TICK:
    CALL EBUZ_FRAME_WAIT
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

; state1発射時の弾1(スロット0): BULLET_FULL、Y=16(暫定)、X=192
EBUZ_SPR_BULLET1:
    DB EBUZ_BULLET1_STORED_Y,EBUZ_BULLET_X,BULLET_FULL_CODE,EBUZ_BULLET_COLOR

; state2発射時の弾2/弾3(スロット1,2): BULLET_HALF、Y=0px/24px、X=192
EBUZ_SPR_BULLET23:
    DB EBUZ_BULLET2_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
    DB EBUZ_BULLET3_STORED_Y,EBUZ_BULLET_X,BULLET_HALF_CODE,EBUZ_BULLET_COLOR
